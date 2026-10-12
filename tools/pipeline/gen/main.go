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
	"strings"

	"github.com/VitruvianSoftware/vitruvian-core/tools/pipeline/unitfile"
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

// discoverUnitsFromWorkspace returns every pipeline unit declared in a BUILD
// file under root. The reading is done by //tools/pipeline/unitfile, the same
// reader the presubmit planner uses, so the workflow and the plan cannot
// disagree about a unit. A declaration it cannot read is an error naming the
// file and the unit, which fails `--check` on the pull request that wrote it.
func discoverUnitsFromWorkspace(root string) ([]Unit, error) {
	read, err := unitfile.Discover(root)
	if err != nil {
		return nil, err
	}
	units := make([]Unit, 0, len(read))
	for _, u := range read {
		units = append(units, unitOf(u))
	}
	return units, nil
}

// parseUnitsFromBuildContent reads the units declared in one BUILD file's
// text. pkg is the file's package.
func parseUnitsFromBuildContent(content, pkg string) ([]Unit, error) {
	read, err := unitfile.Parse(content, pkg)
	if err != nil {
		return nil, err
	}
	var units []Unit
	for _, u := range read {
		units = append(units, unitOf(u))
	}
	return units, nil
}

func unitOf(u unitfile.Unit) Unit {
	return Unit{
		Schema:           SchemaVersion,
		Name:             u.Name,
		Package:          u.Package,
		TestTargets:      u.TestTargets,
		Tier:             u.Tier,
		Runner:           u.Runner,
		Persona:          u.Persona,
		ConcurrencyGroup: "pipeline-" + u.Name,
		TimeoutMinutes:   u.TimeoutMinutes,
		DependsOn:        u.DependsOn,
		NeedsEmulator:    u.NeedsEmulator,
		Artifacts:        u.Artifacts,
		Env:              u.Env,
		BuildFlags:       u.BuildFlags,
	}
}
