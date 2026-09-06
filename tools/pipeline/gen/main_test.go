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
	"os"
	"reflect"
	"strings"
	"testing"
)

func TestDecodeUnit(t *testing.T) {
	validJSON := `{
		"schema": 1,
		"name": "tabula-api",
		"package": "tabula/api",
		"test_targets": [":integration_tests"],
		"tier": "L1",
		"runner": "ubuntu-latest",
		"persona": "backend",
		"timeout_minutes": 20
	}`

	u, err := DecodeUnit([]byte(validJSON))
	if err != nil {
		t.Fatalf("DecodeUnit error: %v", err)
	}
	if u.Name != "tabula-api" {
		t.Errorf("Name = %s, expected tabula-api", u.Name)
	}
	if u.ConcurrencyGroup != "pipeline-tabula-api" {
		t.Errorf("ConcurrencyGroup = %s, expected pipeline-tabula-api", u.ConcurrencyGroup)
	}

	// Invalid schema
	invalidSchema := `{"schema": 2, "name": "foo", "test_targets": [":test"]}`
	if _, err := DecodeUnit([]byte(invalidSchema)); err == nil {
		t.Errorf("expected error on invalid schema version, got nil")
	}

	// Empty name
	emptyName := `{"schema": 1, "name": "", "test_targets": [":test"]}`
	if _, err := DecodeUnit([]byte(emptyName)); err == nil {
		t.Errorf("expected error on empty name, got nil")
	}

	// Empty test targets
	emptyTargets := `{"schema": 1, "name": "foo", "test_targets": []}`
	if _, err := DecodeUnit([]byte(emptyTargets)); err == nil {
		t.Errorf("expected error on empty test targets, got nil")
	}
}

func TestDAGTopologicalOrder(t *testing.T) {
	units := []Unit{
		{Schema: 1, Name: "tabula-web", TestTargets: []string{":test"}, DependsOn: []string{"tabula-shared", "design-system"}},
		{Schema: 1, Name: "tabula-shared", TestTargets: []string{":test"}},
		{Schema: 1, Name: "design-system", TestTargets: []string{":test"}},
		{Schema: 1, Name: "tabula-api", TestTargets: []string{":test"}, DependsOn: []string{"tabula-shared"}},
	}

	dag, err := BuildDAG(units)
	if err != nil {
		t.Fatalf("BuildDAG error: %v", err)
	}

	ordered, err := dag.TopologicalOrder()
	if err != nil {
		t.Fatalf("TopologicalOrder error: %v", err)
	}

	idxMap := make(map[string]int)
	for i, u := range ordered {
		idxMap[u.Name] = i
	}

	// Invariant: tabula-shared and design-system must appear before tabula-web
	if idxMap["tabula-shared"] >= idxMap["tabula-web"] {
		t.Errorf("tabula-shared (idx %d) must precede tabula-web (idx %d)", idxMap["tabula-shared"], idxMap["tabula-web"])
	}
	if idxMap["design-system"] >= idxMap["tabula-web"] {
		t.Errorf("design-system (idx %d) must precede tabula-web (idx %d)", idxMap["design-system"], idxMap["tabula-web"])
	}
	if idxMap["tabula-shared"] >= idxMap["tabula-api"] {
		t.Errorf("tabula-shared (idx %d) must precede tabula-api (idx %d)", idxMap["tabula-shared"], idxMap["tabula-api"])
	}
}

func TestDAGCycleDetection(t *testing.T) {
	units := []Unit{
		{Schema: 1, Name: "unit-a", TestTargets: []string{":test"}, DependsOn: []string{"unit-b"}},
		{Schema: 1, Name: "unit-b", TestTargets: []string{":test"}, DependsOn: []string{"unit-c"}},
		{Schema: 1, Name: "unit-c", TestTargets: []string{":test"}, DependsOn: []string{"unit-a"}},
	}

	_, err := BuildDAG(units)
	if err == nil {
		t.Fatalf("expected cycle error, got nil")
	}
	if !strings.Contains(err.Error(), "cyclic dependency") {
		t.Errorf("expected 'cyclic dependency' in error, got %q", err.Error())
	}
}

func TestDAGMissingDependency(t *testing.T) {
	units := []Unit{
		{Schema: 1, Name: "unit-a", TestTargets: []string{":test"}, DependsOn: []string{"non-existent-unit"}},
	}

	_, err := BuildDAG(units)
	if err == nil {
		t.Fatalf("expected missing dependency error, got nil")
	}
	if !strings.Contains(err.Error(), "non-existent unit") {
		t.Errorf("expected 'non-existent unit' in error, got %q", err.Error())
	}
}

func TestCompileMatrix(t *testing.T) {
	units := []Unit{
		{Schema: 1, Name: "fe-unit", Tier: "L1", Persona: "frontend", TestTargets: []string{":test"}},
		{Schema: 1, Name: "be-unit", Tier: "L1", Persona: "backend", TestTargets: []string{":test"}},
		{Schema: 1, Name: "soak-unit", Tier: "L3", Persona: "backend", TestTargets: []string{":test"}},
	}

	// Filter L1
	m1 := CompileMatrix(units, "L1", "all")
	if len(m1.Include) != 2 {
		t.Errorf("expected 2 units for L1, got %d", len(m1.Include))
	}

	// Filter frontend
	m2 := CompileMatrix(units, "all", "frontend")
	if len(m2.Include) != 1 || m2.Include[0].Name != "fe-unit" {
		t.Errorf("expected fe-unit, got %v", m2.Include)
	}
}

func TestGoldenMatrixValidation(t *testing.T) {
	unitFiles, err := FindUnitFiles("testdata/units")
	if err != nil {
		t.Fatalf("FindUnitFiles error: %v", err)
	}
	if len(unitFiles) == 0 {
		t.Fatalf("no unit files found in testdata/units")
	}

	units, err := LoadUnits(unitFiles)
	if err != nil {
		t.Fatalf("LoadUnits error: %v", err)
	}

	matrixPayload := CompileMatrix(units, "all", "all")
	renderedJSON, err := RenderMatrixJSON(matrixPayload)
	if err != nil {
		t.Fatalf("RenderMatrixJSON error: %v", err)
	}

	goldenJSON, err := os.ReadFile("testdata/golden.matrix.json")
	var gotPayload, wantPayload MatrixPayload
	if err := json.Unmarshal([]byte(renderedJSON), &gotPayload); err != nil {
		t.Fatalf("unmarshal renderedJSON: %v", err)
	}
	if err := json.Unmarshal(goldenJSON, &wantPayload); err != nil {
		t.Fatalf("unmarshal goldenJSON: %v", err)
	}

	if !reflect.DeepEqual(gotPayload, wantPayload) {
		t.Errorf("rendered matrix JSON diverges from testdata/golden.matrix.json:\nGOT:\n%+v\nWANT:\n%+v", gotPayload, wantPayload)
	}
}

func TestGoldenPresubmitValidation(t *testing.T) {
	unitFiles, err := FindUnitFiles("testdata/units")
	if err != nil {
		t.Fatalf("FindUnitFiles error: %v", err)
	}

	units, err := LoadUnits(unitFiles)
	if err != nil {
		t.Fatalf("LoadUnits error: %v", err)
	}

	renderedYAML, err := RenderPresubmitWorkflow(units)
	if err != nil {
		t.Fatalf("RenderPresubmitWorkflow error: %v", err)
	}

	// If golden.presubmit.yaml does not exist, write it
	goldenPath := "testdata/golden.presubmit.yaml"
	if _, err := os.Stat(goldenPath); os.IsNotExist(err) {
		if err := os.WriteFile(goldenPath, []byte(renderedYAML), 0o644); err != nil {
			t.Fatalf("write golden.presubmit.yaml: %v", err)
		}
	}

	goldenYAML, err := os.ReadFile(goldenPath)
	if err != nil {
		t.Fatalf("read golden.presubmit.yaml: %v", err)
	}

	if string(goldenYAML) != renderedYAML {
		t.Errorf("rendered presubmit workflow diverges from testdata/golden.presubmit.yaml")
	}
}

// Unit jobs must run only when the change affects them, and must fail OPEN:
// any planner problem has to run everything rather than quietly skip it.
// Getting this backwards turns a CI saving into silent loss of coverage.
func TestUnitJobsAreGatedOnThePlan(t *testing.T) {
	units := []Unit{
		{
			Schema: SchemaVersion, Name: "alpha", Package: "a",
			TestTargets: []string{"//a:t"}, Tier: "L1",
			Runner: "ubuntu-latest", Persona: "all", TimeoutMinutes: 10,
		},
		{
			Schema: SchemaVersion, Name: "beta", Package: "b",
			TestTargets: []string{"//b:t"}, Tier: "L1",
			Runner: "ubuntu-latest", Persona: "all", TimeoutMinutes: 10,
			DependsOn: []string{"alpha"},
		},
	}
	got, err := RenderPresubmitWorkflow(units)
	if err != nil {
		t.Fatalf("RenderPresubmitWorkflow error: %v", err)
	}

	if !strings.Contains(got, "  plan:\n") {
		t.Fatalf("no plan job rendered:\n%s", got)
	}
	// The fail-open list has to be baked in, or a planner failure has nothing
	// to fall back to.
	if !strings.Contains(got, `ALL_UNITS: '["alpha","beta"]'`) {
		t.Error("plan job does not carry the full unit list as its fallback")
	}
	// fetch-depth: 0 -- a shallow clone cannot diff against the base.
	planJob := got[strings.Index(got, "  plan:"):strings.Index(got, "  unit-alpha:")]
	if !strings.Contains(planJob, "fetch-depth: 0") {
		t.Error("plan job needs full history to compute a diff")
	}

	for _, name := range []string{"alpha", "beta"} {
		want := "contains(fromJSON(needs.plan.outputs.units || '[]'), '" + name + "')"
		if !strings.Contains(got, want) {
			t.Errorf("unit %q is not gated on the affected list (missing %q)", name, want)
		}
	}

	// beta depends on alpha; alpha may be skipped as unaffected. Without
	// always(), GitHub skips beta too, silently dropping a unit the plan DID
	// select.
	betaStart := strings.Index(got, "  unit-beta:")
	betaJob := got[betaStart : betaStart+400]
	if !strings.Contains(betaJob, "needs: [plan, unit-alpha]") {
		t.Errorf("beta should depend on plan and alpha:\n%s", betaJob)
	}
	if !strings.Contains(betaJob, "always()") {
		t.Errorf("beta must use always(), or a skipped alpha skips beta too:\n%s", betaJob)
	}
	if !strings.Contains(betaJob, "needs.plan.result != 'success'") {
		t.Errorf("beta must run when the plan job itself failed (fail open):\n%s", betaJob)
	}

	// A broken plan job must not take the gate down with a quiet pass.
	if !strings.Contains(got, "needs: [plan, unit-alpha, unit-beta]") {
		t.Error("gate must depend on the plan job so a planning failure is a red gate")
	}
}
