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
		"runner": "ubuntu-26.04",
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
			Runner: "ubuntu-26.04", Persona: "all", TimeoutMinutes: 10,
		},
		{
			Schema: SchemaVersion, Name: "beta", Package: "b",
			TestTargets: []string{"//b:t"}, Tier: "L1",
			Runner: "ubuntu-26.04", Persona: "all", TimeoutMinutes: 10,
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

	// GitHub runs `run:` steps as `bash -e -o pipefail`, so errexit is already
	// on before the script starts. Writing `set -uo pipefail` does NOT turn it
	// off, and every fail-open branch in the plan step then becomes
	// unreachable -- the step dies on the first non-zero exit with none of its
	// warnings printed. That is not hypothetical: it is how the first run of
	// this job failed, silently, after three minutes.
	if !strings.Contains(planJob, "set +e") {
		t.Error("plan step must explicitly disable errexit; GitHub's default -e makes every fail-open path dead code")
	}
	// Suppressing the planner's stderr turns a failure into three blank
	// minutes. Keep it and show it.
	if strings.Contains(planJob, "--format=github-matrix --repo-root=\"$PWD\" 2>/dev/null") {
		t.Error("plan step must not discard the planner's stderr; a failure has to be diagnosable")
	}
}

// A unit that drives a device must get an emulator booted before its targets
// run, and must have the device environment forwarded into the test -- Bazel
// scrubs the environment for tests, so without those flags the test cannot
// find adb or the device and the lane is green-but-blind.
//
// The negative half matters as much as the positive: every other unit in the
// repo must NOT pay for an emulator, so assert the step is absent by default.
func TestRenderEmulatorUnit(t *testing.T) {
	units := []Unit{
		{
			Schema: SchemaVersion, Name: "with-emulator", Package: "apps/mobile/android-remote",
			TestTargets: []string{"//apps/mobile/android-remote:boot_smoke"},
			Tier:        "L1", Runner: "ubuntu-26.04", Persona: "frontend",
			ConcurrencyGroup: "pipeline-with-emulator", TimeoutMinutes: 45,
			NeedsEmulator: true,
		},
		{
			Schema: SchemaVersion, Name: "without-emulator", Package: "apps/mobile/android-remote",
			TestTargets: []string{"//apps/mobile/android-remote:lib"},
			Tier:        "L1", Runner: "ubuntu-26.04", Persona: "frontend",
			ConcurrencyGroup: "pipeline-without-emulator", TimeoutMinutes: 30,
		},
	}

	got, err := RenderPresubmitWorkflow(units)
	if err != nil {
		t.Fatalf("RenderPresubmitWorkflow error: %v", err)
	}

	withJob, withoutJob := splitJob(t, got, "  unit-with-emulator:", "  unit-without-emulator:")

	for _, want := range []string{
		"uses: ./.github/actions/android-emulator",
		"--test_env=ANDROID_HOME",
		"--test_env=ANDROID_SERIAL",
		"--test_env=PATH",
	} {
		if !strings.Contains(withJob, want) {
			t.Errorf("emulator unit is missing %q; without it the lane cannot reach a device:\n%s", want, withJob)
		}
	}

	for _, unwanted := range []string{
		"uses: ./.github/actions/android-emulator",
		"--test_env=ANDROID_SERIAL",
	} {
		if strings.Contains(withoutJob, unwanted) {
			t.Errorf("non-emulator unit unexpectedly contains %q; every other lane would pay for an emulator:\n%s", unwanted, withoutJob)
		}
	}

	// The emulator has to be up before the targets run, not after.
	emuAt := strings.Index(withJob, "./.github/actions/android-emulator")
	testAt := strings.Index(withJob, "Build & Test Unit with-emulator")
	if emuAt < 0 || testAt < 0 || emuAt > testAt {
		t.Errorf("emulator step must precede the test step (emulator at %d, test at %d):\n%s", emuAt, testAt, withJob)
	}
}

// The generator discovers units by regex-parsing BUILD files, not by reading
// the .pipeline.json metadata, unless --units-dir is passed. So an attribute
// can be correct in defs.bzl, correct in the metadata, correct in the
// renderer, and still never reach the workflow. That is not hypothetical: the
// first cut of artifacts support did exactly that -- test_targets picked up a
// new target while artifacts silently vanished, because only the former had a
// pattern here.
func TestParseArtifactsFromBuildContent(t *testing.T) {
	build := `
pipeline_unit(
    name = "remote",
    artifacts = {"android-remote-apk": "bazel-bin/apps/mobile/android-remote/app.apk"},
    persona = "frontend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":app",
        ":lib",
    ],
    tier = "L1",
    timeout_minutes = 30,
)
`
	units := parseUnitsFromBuildContent(build, "apps/mobile/android-remote")
	if len(units) != 1 {
		t.Fatalf("expected 1 unit, got %d", len(units))
	}
	got := units[0].Artifacts
	if len(got) != 1 || got["android-remote-apk"] != "bazel-bin/apps/mobile/android-remote/app.apk" {
		t.Fatalf("artifacts not parsed from BUILD content: %#v", got)
	}
}

// A unit that declares none must parse to none, not to an empty-but-present
// map that renders a nameless upload step.
func TestParseNoArtifactsFromBuildContent(t *testing.T) {
	build := `
pipeline_unit(
    name = "plain",
    test_targets = [":lib"],
    tier = "L1",
)
`
	units := parseUnitsFromBuildContent(build, "pkg")
	if len(units) != 1 {
		t.Fatalf("expected 1 unit, got %d", len(units))
	}
	if len(units[0].Artifacts) != 0 {
		t.Fatalf("expected no artifacts, got %#v", units[0].Artifacts)
	}
}

// The APK that CI publishes has to install on a real phone. Bazel defaults an
// android_binary's ABI to the build host, so a Linux runner produces an
// x86_64-only APK that fails on an arm64 device with
// INSTALL_FAILED_NO_MATCHING_ABIS -- off a completely green build. That is
// what build_flags carries here, so it has to survive parse AND render.
func TestParseAndRenderBuildFlags(t *testing.T) {
	build := `
pipeline_unit(
    name = "remote",
    artifacts = {"apk": "bazel-bin/app.apk"},
    build_flags = ["--fat_apk_cpu=arm64-v8a,x86_64"],
    test_targets = [":app"],
    tier = "L1",
)
`
	units := parseUnitsFromBuildContent(build, "pkg")
	if len(units) != 1 || len(units[0].BuildFlags) != 1 || units[0].BuildFlags[0] != "--fat_apk_cpu=arm64-v8a,x86_64" {
		t.Fatalf("build_flags not parsed: %#v", units)
	}

	rendered, err := RenderPresubmitWorkflow(units)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	// Quoted: the comma in the value would otherwise trip shellcheck SC2054
	// and fail actionlint, which is how this first reached CI.
	if !strings.Contains(rendered, `extra_flags+=("--fat_apk_cpu=arm64-v8a,x86_64")`) {
		t.Errorf("build_flags did not reach the workflow:\n%s", rendered)
	}
	// Last wins: a unit's own flags must come after the shared config flags,
	// or the config would override the very thing the unit asked for.
	if cfg, own := strings.Index(rendered, "cache_flags=(--config="), strings.Index(rendered, `extra_flags+=("--fat_apk_cpu`); cfg < 0 || own < 0 || own < cfg {
		t.Errorf("unit flags must follow the shared config flags (config at %d, own at %d)", cfg, own)
	}
}

// env had the same hole artifacts did: the renderer supported it, the BUILD
// parser never populated it, so `env = {...}` on a unit vanished without a
// word. Found when ANDROID_NDK_HOME failed to reach the workflow.
// A ")" inside a comment used to truncate the attribute body, because the
// call is matched with [^)]*. Everything after the comment vanished -- in the
// case that found this, test_targets -- and the generated workflow ran
// `bazel test` with no targets at all, passing while building nothing.
func TestParseSurvivesParenthesesInComments(t *testing.T) {
	build := `
pipeline_unit(
    name = "remote",
    # NDK 29.0.14206865 (the version installed when this landed) decides ABIs.
    artifacts = {"apk": "apps/x/app.apk"},
    test_targets = [
        ":app",
        ":lib",
    ],
    tier = "L1",
)
`
	units := parseUnitsFromBuildContent(build, "pkg")
	if len(units) != 1 {
		t.Fatalf("expected 1 unit, got %d", len(units))
	}
	if len(units[0].TestTargets) != 2 {
		t.Fatalf("test_targets lost to a comment: %#v", units[0].TestTargets)
	}
	if units[0].Artifacts["apk"] != "apps/x/app.apk" {
		t.Fatalf("artifacts lost to a comment: %#v", units[0].Artifacts)
	}
}

// A "#" inside a quoted value is data, not a comment.
func TestParseKeepsHashInsideStrings(t *testing.T) {
	build := `
pipeline_unit(
    name = "u",
    env = {"REF": "main#head"},
    test_targets = [":t"],
    tier = "L1",
)
`
	units := parseUnitsFromBuildContent(build, "pkg")
	if len(units) != 1 || units[0].Env["REF"] != "main#head" {
		t.Fatalf("hash inside a string was treated as a comment: %#v", units)
	}
}

func TestParseEnvFromBuildContent(t *testing.T) {
	build := `
pipeline_unit(
    name = "remote",
    env = {"ANDROID_NDK_HOME": "${{ env.ANDROID_NDK_ROOT }}"},
    test_targets = [":app"],
    tier = "L1",
)
`
	units := parseUnitsFromBuildContent(build, "pkg")
	if len(units) != 1 || units[0].Env["ANDROID_NDK_HOME"] != "${{ env.ANDROID_NDK_ROOT }}" {
		t.Fatalf("env not parsed from BUILD content: %#v", units)
	}

	rendered, err := RenderPresubmitWorkflow(units)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	if !strings.Contains(rendered, "ANDROID_NDK_HOME:") {
		t.Errorf("env did not reach the workflow:\n%s", rendered)
	}
}

func TestRenderArtifactUpload(t *testing.T) {
	units := []Unit{
		{
			Schema: SchemaVersion, Name: "with-artifacts", Package: "apps/mobile/android-remote",
			TestTargets: []string{"//apps/mobile/android-remote:app"},
			Tier:        "L1", Runner: "ubuntu-26.04", Persona: "frontend",
			ConcurrencyGroup: "pipeline-with-artifacts", TimeoutMinutes: 30,
			// Two, deliberately declared out of order: Go map order is random,
			// so an unsorted range would render differently run to run and
			// tidy-check would fail on a file nobody touched.
			Artifacts: map[string]string{
				"zebra": "z.txt",
				"alpha": "apps/mobile/android-remote/app.apk",
			},
		},
		{
			Schema: SchemaVersion, Name: "without-artifacts", Package: "apps/mobile/android-remote",
			TestTargets: []string{"//apps/mobile/android-remote:lib"},
			Tier:        "L1", Runner: "ubuntu-26.04", Persona: "frontend",
			ConcurrencyGroup: "pipeline-without-artifacts", TimeoutMinutes: 30,
		},
	}

	got, err := RenderPresubmitWorkflow(units)
	if err != nil {
		t.Fatalf("RenderPresubmitWorkflow error: %v", err)
	}

	withJob, withoutJob := splitJob(t, got, "  unit-with-artifacts:", "  unit-without-artifacts:")

	for _, want := range []string{
		"uses: actions/upload-artifact@v7",
		"name: alpha",
		// Resolved through `bazel info`, not the workspace symlink: the unit's
		// own flags decide which bin directory Bazel actually writes to.
		"bin=$(bazel info",
		"cp -L \"$bin/apps/mobile/android-remote/app.apk\" .pipeline-artifacts/alpha/",
		"path: .pipeline-artifacts/alpha",
		// Without this a silently-missing output uploads as an empty artifact,
		// which is discovered only when someone tries to install it.
		"if-no-files-found: error",
	} {
		if !strings.Contains(withJob, want) {
			t.Errorf("artifact unit is missing %q:\n%s", want, withJob)
		}
	}

	// An artifact lane must not run under :remote: that config downloads
	// minimal outputs, so a cache hit leaves bazel-bin empty and the upload
	// publishes nothing off a green build (#1296).
	if !strings.Contains(withJob, "--config=remotecache-ci") {
		t.Errorf("artifact unit must use :remotecache-ci so outputs materialise:\n%s", withJob)
	}
	if strings.Contains(withJob, "cache_flags=(--config=remote ") {
		t.Errorf("artifact unit must not use :remote (minimal downloads):\n%s", withJob)
	}
	if !strings.Contains(withoutJob, "--config=remote ") {
		t.Errorf("a unit with no artifacts should keep using :remote:\n%s", withoutJob)
	}

	if strings.Contains(withoutJob, "upload-artifact") {
		t.Errorf("a unit declaring no artifacts must not upload anything:\n%s", withoutJob)
	}

	// Sorted, not map order.
	if a, z := strings.Index(withJob, "name: alpha"), strings.Index(withJob, "name: zebra"); a < 0 || z < 0 || a > z {
		t.Errorf("artifacts must render in sorted order (alpha at %d, zebra at %d):\n%s", a, z, withJob)
	}

	// Uploading before the targets have run would capture a stale or absent
	// output, and uploading on failure hands someone a broken build that still
	// looks installable.
	upAt := strings.Index(withJob, "upload-artifact")
	testAt := strings.Index(withJob, "Build & Test Unit with-artifacts")
	if upAt < 0 || testAt < 0 || upAt < testAt {
		t.Errorf("upload must follow the test step (upload at %d, test at %d):\n%s", upAt, testAt, withJob)
	}
	if !strings.Contains(withJob[testAt:upAt+len("upload-artifact")], "if: success()") {
		t.Errorf("upload must be gated on success():\n%s", withJob)
	}
}

// splitJob carves the rendered workflow into the two job bodies, so an
// assertion about one job cannot accidentally be satisfied by the other.
func splitJob(t *testing.T, rendered, firstHeader, secondHeader string) (string, string) {
	t.Helper()
	i := strings.Index(rendered, firstHeader)
	j := strings.Index(rendered, secondHeader)
	if i < 0 || j < 0 || j < i {
		t.Fatalf("could not locate both job headers %q and %q in:\n%s", firstHeader, secondHeader, rendered)
	}
	k := strings.Index(rendered[j:], "\n  gate:")
	if k < 0 {
		k = len(rendered) - j
	}
	return rendered[i:j], rendered[j : j+k]
}

// The fan-in gate is the ONLY required status check covering the pipeline
// units -- the units themselves are not required on main. With `if: always()`
// the gate job runs even when upstreams fail, so unless it reads
// needs.*.result it reports green over a red pipeline. That is not
// hypothetical: runs 34012010463 (2 units red) and 34010090082 (7 units red)
// both showed this gate green.
func TestGateEvaluatesUpstreamResults(t *testing.T) {
	units := []Unit{
		{
			Schema: SchemaVersion, Name: "alpha", Package: "a",
			TestTargets: []string{"//a:t"}, Tier: "L1",
			Runner: "ubuntu-26.04", Persona: "all", TimeoutMinutes: 10,
		},
	}
	got, err := RenderPresubmitWorkflow(units)
	if err != nil {
		t.Fatalf("RenderPresubmitWorkflow error: %v", err)
	}

	i := strings.Index(got, "  gate:")
	if i < 0 {
		t.Fatalf("no gate job rendered:\n%s", got)
	}
	gate := got[i:]

	if !strings.Contains(gate, "toJSON(needs)") {
		t.Errorf("gate does not read needs.*.result, so it cannot fail when a unit fails:\n%s", gate)
	}
	// Fail-closed on an empty upstream set, and on any result that is neither
	// success nor skipped.
	for _, want := range []string{
		`select(.value.result != "success" and .value.result != "skipped")`,
		"exit 1",
	} {
		if !strings.Contains(gate, want) {
			t.Errorf("gate is missing %q:\n%s", want, gate)
		}
	}
	// A gate whose only outcome is the success echo is the bug itself.
	if strings.Count(gate, "exit 1") < 2 {
		t.Errorf("gate should fail closed on both an empty and a failing upstream set:\n%s", gate)
	}
}

func TestDegradedPlanIsAnnounced(t *testing.T) {
	units := []Unit{
		{
			Schema: SchemaVersion, Name: "alpha", Package: "a",
			TestTargets: []string{"//a:t"}, Tier: "L1",
			Runner: "ubuntu-26.04", Persona: "all", TimeoutMinutes: 10,
		},
	}
	got, err := RenderPresubmitWorkflow(units)
	if err != nil {
		t.Fatalf("RenderPresubmitWorkflow error: %v", err)
	}

	i := strings.Index(got, "  plan:")
	if i < 0 {
		t.Fatalf("no plan job rendered:\n%s", got)
	}
	j := strings.Index(got[i+1:], "\n  unit-")
	if j < 0 {
		t.Fatalf("could not find the end of the plan job:\n%s", got)
	}
	plan := got[i : i+1+j]

	// The planner reports degradation separately from a genuine global change
	// for exactly one reason: so a sweep that happened because the query FAILED
	// can be told apart from a sweep that was correct. Capturing the flag into
	// an output nothing reads reproduces the original silence -- a 15s default
	// timeout made every plan a full sweep for months without a word.
	if !strings.Contains(plan, `if [ "$degraded" = "true" ]`) {
		t.Errorf("the plan job never branches on $degraded, so a degraded plan is silent:\n%s", plan)
	}
	if !strings.Contains(plan, "::warning::") || !strings.Contains(plan, "DEGRADED") {
		t.Errorf("a degraded plan must raise an annotation on the run:\n%s", plan)
	}
	if !strings.Contains(plan, "Degraded plan.") {
		t.Errorf("a degraded plan must say so in the step summary:\n%s", plan)
	}
	// Write-only is the bug. The flag has to be read somewhere it can be seen,
	// not just echoed into GITHUB_OUTPUT.
	writes := strings.Count(plan, `echo "degraded=$degraded" >> "$GITHUB_OUTPUT"`)
	reads := strings.Count(plan, `"$degraded" = "true"`)
	if writes > 0 && reads == 0 {
		t.Errorf("$degraded is written but never read -- the flag cannot do its job:\n%s", plan)
	}
}
