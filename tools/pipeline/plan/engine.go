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
	"context"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

// PipelineUnitDefinition represents a parsed pipeline_unit declaration.
type PipelineUnitDefinition struct {
	Name             string            `json:"name"`
	Package          string            `json:"package"`
	TestTargets      []string          `json:"test_targets"`
	Tier             string            `json:"tier"`
	Runner           string            `json:"runner"`
	Persona          string            `json:"persona"`
	ConcurrencyGroup string            `json:"concurrency_group"`
	TimeoutMinutes   int               `json:"timeout_minutes"`
	Env              map[string]string `json:"env,omitempty"`
	DependsOn        []string          `json:"depends_on,omitempty"`
	Tags             []string          `json:"tags,omitempty"`
}

// Engine encapsulates the plan execution logic.
type Engine struct {
	RepoRoot string
	Runner   QueryRunner
}

// NewEngine constructs a new plan Engine.
func NewEngine(repoRoot string, runner QueryRunner) *Engine {
	if runner == nil {
		runner = &BazelQueryRunner{}
	}
	return &Engine{
		RepoRoot: repoRoot,
		Runner:   runner,
	}
}

// DiscoverUnits scans repoRoot for pipeline units either from *.pipeline.json files or by parsing BUILD files.
func (e *Engine) DiscoverUnits() ([]PipelineUnitDefinition, error) {
	var units []PipelineUnitDefinition
	seen := make(map[string]bool)

	// 1. Walk repoRoot for BUILD files containing pipeline_unit declarations
	err := filepath.Walk(e.RepoRoot, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if info.IsDir() {
			name := info.Name()
			if name == ".git" || name == "bazel-out" || name == "bazel-bin" || name == "bazel-testlogs" || name == "node_modules" {
				return filepath.SkipDir
			}
			return nil
		}

		if info.Name() == "BUILD" || info.Name() == "BUILD.bazel" {
			relDir, err := filepath.Rel(e.RepoRoot, filepath.Dir(path))
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

			parsedUnits := parsePipelineUnitsFromBuild(string(content), relDir)
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

// regex helpers for parsing pipeline_unit calls in Starlark BUILD files
var (
	pipelineUnitCallRegex = regexp.MustCompile(`pipeline_unit\s*\(([^)]+)\)`)
	nameFieldRegex        = regexp.MustCompile(`name\s*=\s*["']([^"']+)["']`)
	tierFieldRegex        = regexp.MustCompile(`tier\s*=\s*["']([^"']+)["']`)
	runnerFieldRegex      = regexp.MustCompile(`runner\s*=\s*["']([^"']+)["']`)
	personaFieldRegex     = regexp.MustCompile(`persona\s*=\s*["']([^"']+)["']`)
	timeoutFieldRegex     = regexp.MustCompile(`timeout_minutes\s*=\s*([0-9]+)`)
	testTargetsFieldRegex = regexp.MustCompile(`test_targets\s*=\s*\[([^\]]*)\]`)
	dependsOnFieldRegex   = regexp.MustCompile(`depends_on\s*=\s*\[([^\]]*)\]`)
)

func parsePipelineUnitsFromBuild(content, pkg string) []PipelineUnitDefinition {
	var units []PipelineUnitDefinition
	matches := pipelineUnitCallRegex.FindAllStringSubmatch(content, -1)

	for _, m := range matches {
		body := m[1]

		nameMatch := nameFieldRegex.FindStringSubmatch(body)
		if len(nameMatch) < 2 {
			continue
		}
		name := nameMatch[1]

		tier := "L1"
		if tm := tierFieldRegex.FindStringSubmatch(body); len(tm) >= 2 {
			tier = tm[1]
		}

		runner := "ubuntu-latest"
		if rm := runnerFieldRegex.FindStringSubmatch(body); len(rm) >= 2 {
			runner = rm[1]
		}

		persona := "all"
		if pm := personaFieldRegex.FindStringSubmatch(body); len(pm) >= 2 {
			persona = pm[1]
		}

		timeout := 20
		if tom := timeoutFieldRegex.FindStringSubmatch(body); len(tom) >= 2 {
			fmt.Sscanf(tom[1], "%d", &timeout)
		}

		var testTargets []string
		if ttm := testTargetsFieldRegex.FindStringSubmatch(body); len(ttm) >= 2 {
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
		if dom := dependsOnFieldRegex.FindStringSubmatch(body); len(dom) >= 2 {
			raw := dom[1]
			depItems := regexp.MustCompile(`["']([^"']+)["']`).FindAllStringSubmatch(raw, -1)
			for _, item := range depItems {
				if len(item) >= 2 {
					dependsOn = append(dependsOn, item[1])
				}
			}
		}

		units = append(units, PipelineUnitDefinition{
			Name:             name,
			Package:          pkg,
			TestTargets:      testTargets,
			Tier:             tier,
			Runner:           runner,
			Persona:          persona,
			ConcurrencyGroup: "pipeline-" + name,
			TimeoutMinutes:   timeout,
			DependsOn:        dependsOn,
		})
	}

	return units
}

// ComputePlan executes the complete change detection analysis.
func (e *Engine) ComputePlan(ctx context.Context, files []string, baseRev, headRev string) (*Plan, error) {
	start := time.Now()

	plan := &Plan{
		SchemaVersion: SchemaVersion,
		BaseRev:       baseRev,
		HeadRev:       headRev,
		ChangedFiles:  files,
		Targets:       []string{},
		Matrix:        []MatrixEntry{},
	}

	// 1. Fast-Gate: Docs/Markdown only
	if IsDocsOnly(files) {
		plan.IsDocsOnly = true
		plan.Persona = PersonaDocsAuthor
		plan.Operation = OperationDocsOnly
		plan.DurationMs = time.Since(start).Milliseconds()
		return plan, nil
	}

	// 2. Discover all declared pipeline units
	allUnits, _ := e.DiscoverUnits()

	// 3. Fast-Gate: Global Impact
	if isGlobal, reason := CheckGlobalImpact(files); isGlobal {
		plan.IsGlobalImpact = true
		plan.SweepReason = reason
		plan.Persona = PersonaPlatformAdmin
		plan.Operation = OperationGlobalConfig
		plan.Targets = []string{"//..."}
		plan.TargetCount = 1

		// Expand matrix to include all declared units (or fallback)
		for _, u := range allUnits {
			plan.Matrix = append(plan.Matrix, MatrixEntry{
				Name:             u.Name,
				Package:          u.Package,
				Runner:           u.Runner,
				Tier:             ExecutionTier(u.Tier),
				Persona:          Persona(u.Persona),
				Targets:          u.TestTargets,
				TestTargets:      strings.Join(u.TestTargets, " "),
				TargetCount:      len(u.TestTargets),
				TimeoutMinutes:   u.TimeoutMinutes,
				ConcurrencyGroup: u.ConcurrencyGroup,
				Needs:            u.DependsOn,
				IsRequired:       true,
			})
		}
		plan.DurationMs = time.Since(start).Milliseconds()
		return plan, nil
	}

	// 4. Resolve changed packages
	packages, err := ResolvePackages(e.RepoRoot, files)
	if err != nil {
		return nil, fmt.Errorf("resolve packages: %w", err)
	}
	plan.AffectedPackages = packages

	if len(packages) == 0 {
		// No bazel packages affected
		persona, op := ClassifyPersonaAndOperation(files, false, false)
		plan.Persona = persona
		plan.Operation = op
		plan.DurationMs = time.Since(start).Milliseconds()
		return plan, nil
	}

	// 5. Query affected test rdeps
	testTargets, err := e.Runner.QueryTestRdeps(ctx, e.RepoRoot, packages)
	if err != nil {
		// Fail-closed fallback to full sweep. Correct, but expensive: mark it
		// degraded so callers can tell this apart from a real global change.
		plan.IsGlobalImpact = true
		plan.IsDegraded = true
		plan.SweepReason = fmt.Sprintf("query degraded: fallback to full sweep (%v)", err)
		plan.Targets = []string{"//..."}
		plan.TargetCount = 1
		for _, u := range allUnits {
			plan.Matrix = append(plan.Matrix, MatrixEntry{
				Name:             u.Name,
				Package:          u.Package,
				Runner:           u.Runner,
				Tier:             ExecutionTier(u.Tier),
				Persona:          Persona(u.Persona),
				Targets:          u.TestTargets,
				TestTargets:      strings.Join(u.TestTargets, " "),
				TargetCount:      len(u.TestTargets),
				TimeoutMinutes:   u.TimeoutMinutes,
				ConcurrencyGroup: u.ConcurrencyGroup,
				Needs:            u.DependsOn,
				IsRequired:       true,
			})
		}
		persona, op := ClassifyPersonaAndOperation(files, false, true)
		plan.Persona = persona
		plan.Operation = op
		plan.DurationMs = time.Since(start).Milliseconds()
		return plan, nil
	}

	plan.Targets = testTargets
	plan.TargetCount = len(testTargets)

	// 6. Classify Persona and Operation
	persona, op := ClassifyPersonaAndOperation(files, false, false)
	plan.Persona = persona
	plan.Operation = op

	// 7. Match affected targets / packages to declared Pipeline Units
	targetSet := make(map[string]bool, len(testTargets))
	for _, t := range testTargets {
		targetSet[t] = true
	}

	pkgPrefixSet := make(map[string]bool, len(packages))
	for _, p := range packages {
		// e.g. "//tabula/api:all" -> "tabula/api"
		clean := strings.TrimPrefix(p, "//")
		clean = strings.TrimSuffix(clean, ":all")
		pkgPrefixSet[clean] = true
	}

	var affectedUnits []PipelineUnitDefinition
	for _, u := range allUnits {
		isAffected := false

		// Check if package directly matched
		if pkgPrefixSet[u.Package] {
			isAffected = true
		}

		// Check if any declared test_targets intersect with affected testTargets
		for _, tt := range u.TestTargets {
			if targetSet[tt] {
				isAffected = true
				break
			}
			// Check package prefix matching
			for at := range targetSet {
				if strings.HasPrefix(at, "//"+u.Package) {
					isAffected = true
					break
				}
			}
		}

		if isAffected {
			affectedUnits = append(affectedUnits, u)
		}
	}

	// Build Matrix Entries
	for _, u := range affectedUnits {
		plan.Matrix = append(plan.Matrix, MatrixEntry{
			Name:             u.Name,
			Package:          u.Package,
			Runner:           u.Runner,
			Tier:             ExecutionTier(u.Tier),
			Persona:          Persona(u.Persona),
			Targets:          u.TestTargets,
			TestTargets:      strings.Join(u.TestTargets, " "),
			TargetCount:      len(u.TestTargets),
			TimeoutMinutes:   u.TimeoutMinutes,
			ConcurrencyGroup: u.ConcurrencyGroup,
			Needs:            u.DependsOn,
			IsRequired:       true,
		})
	}

	plan.DurationMs = time.Since(start).Milliseconds()
	return plan, nil
}
