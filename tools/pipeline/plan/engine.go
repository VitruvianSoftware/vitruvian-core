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
	"strings"
	"time"

	"github.com/VitruvianSoftware/vitruvian-core/tools/pipeline/unitfile"
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
	// RdepsMap, when set, answers "which tests depend on these packages?"
	// instead of a live query. It must describe the diff base; main.go only
	// sets it after LoadRdepsMap has checked that.
	RdepsMap *RdepsMap
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

// DiscoverUnits returns every pipeline unit declared in a BUILD file under
// repoRoot. The reading is done by //tools/pipeline/unitfile, the same reader
// the workflow generator uses, so the two cannot disagree about a unit.
//
// A declaration that cannot be read is an error naming the file and the unit.
// It is never a unit with no test targets: that looks exactly like a unit the
// change does not affect, and it is how a unit went unselected for weeks.
func (e *Engine) DiscoverUnits() ([]PipelineUnitDefinition, error) {
	read, err := unitfile.Discover(e.RepoRoot)
	if err != nil {
		return nil, err
	}
	units := make([]PipelineUnitDefinition, 0, len(read))
	for _, u := range read {
		units = append(units, definitionOf(u))
	}
	return units, nil
}

// parsePipelineUnitsFromBuild reads the units declared in one BUILD file's
// text. pkg is the file's package.
func parsePipelineUnitsFromBuild(content, pkg string) ([]PipelineUnitDefinition, error) {
	read, err := unitfile.Parse(content, pkg)
	if err != nil {
		return nil, err
	}
	var units []PipelineUnitDefinition
	for _, u := range read {
		units = append(units, definitionOf(u))
	}
	return units, nil
}

func definitionOf(u unitfile.Unit) PipelineUnitDefinition {
	return PipelineUnitDefinition{
		Name:             u.Name,
		Package:          u.Package,
		TestTargets:      u.TestTargets,
		Tier:             u.Tier,
		Runner:           u.Runner,
		Persona:          u.Persona,
		ConcurrencyGroup: "pipeline-" + u.Name,
		TimeoutMinutes:   u.TimeoutMinutes,
		DependsOn:        u.DependsOn,
	}
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
	allUnits, err := e.DiscoverUnits()
	if err != nil {
		return nil, fmt.Errorf("discover pipeline units: %w", err)
	}

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

	// 5. Find the tests that depend on the changed packages: from the
	// dependency map when it covers every changed package, else live.
	var testTargets []string
	usedMap := false
	if e.RdepsMap != nil {
		if mapped, ok := e.RdepsMap.Lookup(packages); ok {
			testTargets, usedMap = mapped, true
			plan.PlanSource = PlanSourceMap
		} else {
			plan.PlanSourceNote = "dependency map does not know every changed package (new package?); used the live query"
		}
	}
	if !usedMap {
		plan.PlanSource = PlanSourceLive
		testTargets, err = e.Runner.QueryTestRdeps(ctx, e.RepoRoot, packages)
	}
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

		// With the map, a test ADDED in this PR is unknown to it. Such a test
		// lives in a changed package; if that package is inside the unit's
		// package, select the unit. (The live query would have found the new
		// test and matched it by the package prefix check below.)
		if usedMap {
			for p := range pkgPrefixSet {
				if strings.HasPrefix(p, u.Package+"/") {
					isAffected = true
				}
			}
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
