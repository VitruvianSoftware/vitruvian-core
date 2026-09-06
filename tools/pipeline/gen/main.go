// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

func main() {
	var (
		unitsDirFlag   = flag.String("units-dir", "", "Directory containing .pipeline.json files")
		formatFlag     = flag.String("format", "matrix", "Output format: matrix, workflow, json, dag")
		tierFlag       = flag.String("tier", "all", "Tier filter: L0, L1, L2, L3, all")
		personaFlag    = flag.String("persona", "all", "Persona filter: frontend, backend, infra, platform, security, docs, all")
		outputFileFlag = flag.String("output-file", "", "Target file to write or check")
		checkFlag      = flag.Bool("check", false, "Verify output-file matches generated output without writing")
		repoRootFlag   = flag.String("repo-root", "", "Path to repository workspace root")
	)
	flag.Parse()

	repoRoot := *repoRootFlag
	if repoRoot == "" {
		if ws := os.Getenv("BUILD_WORKSPACE_DIRECTORY"); ws != "" {
			repoRoot = ws
		} else {
			var err error
			repoRoot, err = os.Getwd()
			if err != nil {
				fmt.Fprintf(os.Stderr, "failed to get current working directory: %v\n", err)
				os.Exit(1)
			}
		}
	}

	var units []Unit
	var err error

	if *unitsDirFlag != "" {
		unitsDir := *unitsDirFlag
		if !filepath.IsAbs(unitsDir) {
			unitsDir = filepath.Join(repoRoot, unitsDir)
		}
		unitFiles, err := FindUnitFiles(unitsDir)
		if err != nil {
			fmt.Fprintf(os.Stderr, "failed to find unit files in %s: %v\n", unitsDir, err)
			os.Exit(1)
		}
		if len(unitFiles) == 0 {
			// Try reading JSON files directly in dir
			entries, _ := os.ReadDir(unitsDir)
			for _, e := range entries {
				if strings.HasSuffix(e.Name(), ".json") {
					unitFiles = append(unitFiles, filepath.Join(unitsDir, e.Name()))
				}
			}
		}
		units, err = LoadUnits(unitFiles)
		if err != nil {
			fmt.Fprintf(os.Stderr, "failed to load units from %s: %v\n", unitsDir, err)
			os.Exit(1)
		}
	} else {
		// Discover units by walking repoRoot for BUILD files containing pipeline_unit declarations
		units, err = discoverUnitsFromWorkspace(repoRoot)
		if err != nil {
			fmt.Fprintf(os.Stderr, "failed to discover units in workspace %s: %v\n", repoRoot, err)
			os.Exit(1)
		}
	}

	// Validate DAG
	dag, err := BuildDAG(units)
	if err != nil {
		fmt.Fprintf(os.Stderr, "DAG validation failed: %v\n", err)
		os.Exit(1)
	}

	format := *formatFlag
	if format == "matrix" && *outputFileFlag != "" {
		if strings.HasSuffix(*outputFileFlag, ".yaml") || strings.HasSuffix(*outputFileFlag, ".yml") {
			format = "workflow"
		}
	}

	var generated string

	switch format {
	case "workflow":
		generated, err = RenderPresubmitWorkflow(units)
		if err != nil {
			fmt.Fprintf(os.Stderr, "failed to render workflow: %v\n", err)
			os.Exit(1)
		}
	case "json":
		b, err := json.MarshalIndent(units, "", "  ")
		if err != nil {
			fmt.Fprintf(os.Stderr, "failed to marshal units JSON: %v\n", err)
			os.Exit(1)
		}
		generated = string(b) + "\n"
	case "dag":
		ordered, err := dag.TopologicalOrder()
		if err != nil {
			fmt.Fprintf(os.Stderr, "topological sort failed: %v\n", err)
			os.Exit(1)
		}
		var names []string
		for _, u := range ordered {
			names = append(names, u.Name)
		}
		generated = strings.Join(names, "\n") + "\n"
	case "matrix":
		fallthrough
	default:
		payload := CompileMatrix(units, *tierFlag, *personaFlag)
		generated, err = RenderMatrixJSON(payload)
		if err != nil {
			fmt.Fprintf(os.Stderr, "failed to render matrix JSON: %v\n", err)
			os.Exit(1)
		}
	}

	outPath := *outputFileFlag
	if outPath != "" && !filepath.IsAbs(outPath) {
		outPath = filepath.Join(repoRoot, outPath)
	}

	if *checkFlag {
		if outPath == "" {
			fmt.Fprintf(os.Stderr, "--check requires --output-file\n")
			os.Exit(1)
		}
		existing, err := os.ReadFile(outPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "failed to read output file %s: %v\n", outPath, err)
			os.Exit(1)
		}
		if string(existing) != generated {
			fmt.Fprintf(os.Stderr, "ERROR: %s is out of date with pipeline_unit() declarations. Run 'bazel run //tools/pipeline:gen' to update.\n", *outputFileFlag)
			os.Exit(1)
		}
		fmt.Printf("✓ %s matches generated output cleanly\n", *outputFileFlag)
		return
	}

	if outPath != "" {
		if err := os.MkdirAll(filepath.Dir(outPath), 0o755); err != nil {
			fmt.Fprintf(os.Stderr, "failed to create directory for %s: %v\n", outPath, err)
			os.Exit(1)
		}
		if err := os.WriteFile(outPath, []byte(generated), 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "failed to write output file: %v\n", err)
			os.Exit(1)
		}
	} else {
		fmt.Print(generated)
	}
}

func discoverUnitsFromWorkspace(root string) ([]Unit, error) {
	var units []Unit
	seen := make(map[string]bool)

	// Walk workspace for BUILD files
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if info.IsDir() {
			name := info.Name()
			if name == ".git" || name == "bazel-out" || name == "bazel-bin" || name == "node_modules" {
				return filepath.SkipDir
			}
			return nil
		}

		if info.Name() == "BUILD" || info.Name() == "BUILD.bazel" {
			relDir, err := filepath.Rel(root, filepath.Dir(path))
			if err != nil {
				return nil
			}
			relDir = filepath.ToSlash(relDir)
			if relDir == "." {
				relDir = ""
			}

			content, err := os.ReadFile(path)
			if err != nil {
				return nil
			}

			parsedUnits := parseUnitsFromBuildContent(string(content), relDir)
			for _, u := range parsedUnits {
				if !seen[u.Name] {
					seen[u.Name] = true
					units = append(units, u)
				}
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}

	sort.Slice(units, func(i, j int) bool { return units[i].Name < units[j].Name })
	return units, nil
}

var (
	pipelineCallPattern = regexp.MustCompile(`pipeline_unit\s*\(([^)]+)\)`)
	nameAttrPattern     = regexp.MustCompile(`name\s*=\s*["']([^"']+)["']`)
	tierAttrPattern     = regexp.MustCompile(`tier\s*=\s*["']([^"']+)["']`)
	runnerAttrPattern   = regexp.MustCompile(`runner\s*=\s*["']([^"']+)["']`)
	personaAttrPattern  = regexp.MustCompile(`persona\s*=\s*["']([^"']+)["']`)
	timeoutAttrPattern  = regexp.MustCompile(`timeout_minutes\s*=\s*([0-9]+)`)
	testTargetsPattern  = regexp.MustCompile(`test_targets\s*=\s*\[([^\]]*)\]`)
	dependsOnPattern    = regexp.MustCompile(`depends_on\s*=\s*\[([^\]]*)\]`)
	// Starlark bools only, so True/False literally -- an expression here would
	// need a real parser, and pipeline_unit's contract is literal attributes.
	needsEmulatorPattern = regexp.MustCompile(`needs_emulator\s*=\s*(True|False)`)
)

func parseUnitsFromBuildContent(content, pkg string) []Unit {
	var units []Unit
	matches := pipelineCallPattern.FindAllStringSubmatch(content, -1)

	for _, m := range matches {
		body := m[1]

		nameMatch := nameAttrPattern.FindStringSubmatch(body)
		if len(nameMatch) < 2 {
			continue
		}
		name := nameMatch[1]

		tier := "L1"
		if tm := tierAttrPattern.FindStringSubmatch(body); len(tm) >= 2 {
			tier = tm[1]
		}

		runner := "ubuntu-latest"
		if rm := runnerAttrPattern.FindStringSubmatch(body); len(rm) >= 2 {
			runner = rm[1]
		}

		persona := "all"
		if pm := personaAttrPattern.FindStringSubmatch(body); len(pm) >= 2 {
			persona = pm[1]
		}

		timeout := 20
		if tom := timeoutAttrPattern.FindStringSubmatch(body); len(tom) >= 2 {
			fmt.Sscanf(tom[1], "%d", &timeout)
		}

		needsEmulator := false
		if em := needsEmulatorPattern.FindStringSubmatch(body); len(em) >= 2 {
			needsEmulator = em[1] == "True"
		}

		var testTargets []string
		if ttm := testTargetsPattern.FindStringSubmatch(body); len(ttm) >= 2 {
			raw := ttm[1]
			targetItems := regexp.MustCompile(`["']([^"']+)["']`).FindAllStringSubmatch(raw, -1)
			for _, item := range targetItems {
				if len(item) >= 2 {
					t := item[1]
					if strings.HasPrefix(t, ":") {
						if pkg == "" {
							t = "//" + t
						} else {
							t = "//" + pkg + t
						}
					}
					testTargets = append(testTargets, t)
				}
			}
		}

		var dependsOn []string
		if dom := dependsOnPattern.FindStringSubmatch(body); len(dom) >= 2 {
			raw := dom[1]
			depItems := regexp.MustCompile(`["']([^"']+)["']`).FindAllStringSubmatch(raw, -1)
			for _, item := range depItems {
				if len(item) >= 2 {
					dependsOn = append(dependsOn, item[1])
				}
			}
		}

		units = append(units, Unit{
			Schema:           SchemaVersion,
			Name:             name,
			Package:          pkg,
			TestTargets:      testTargets,
			Tier:             tier,
			Runner:           runner,
			Persona:          persona,
			ConcurrencyGroup: "pipeline-" + name,
			TimeoutMinutes:   timeout,
			DependsOn:        dependsOn,
			NeedsEmulator:    needsEmulator,
		})
	}

	return units
}
