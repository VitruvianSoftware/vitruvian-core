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
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// fixtureUnits are copies of the two real declarations' metadata JSON
// (oauth-user-inspector = cloud-run with companions/excludes, zitadel-apps =
// pulumi). Frozen copies rather than a live read of bazel-bin so the golden
// cannot move under the test when someone edits a real BUILD file.
var fixtureUnits = []string{
	"testdata/units/oauth-user-inspector.delivery.json",
	"testdata/units/zitadel-apps.delivery.json",
}

const (
	goldenPhase0Path = "testdata/golden.delivery.yaml"
	goldenPhase1Path = "testdata/golden.phase1.delivery.yaml"

	// The generated file's own basename, which render() puts in the
	// durable-base resolver's WORKFLOW_FILE. main() derives it from --out.
	testWorkflowFile = "delivery.yaml"
)

// mustRender renders or fails the test. render() returns an error for every
// declaration that would produce a workflow GitHub rejects at startup (or
// accepts and then fails mid-delivery), so a test that ignored it could assert
// happily against the empty string.
func mustRender(t *testing.T, units []unit, phase int) string {
	t.Helper()
	got, err := render(units, phase, testWorkflowFile)
	if err != nil {
		t.Fatalf("render(phase %d): %v", phase, err)
	}
	return got
}

func loadFixtures(t *testing.T) []unit {
	t.Helper()
	units, err := loadUnits(fixtureUnits)
	if err != nil {
		t.Fatalf("loadUnits(fixtures): %v", err)
	}
	if len(units) != 2 {
		t.Fatalf("want 2 fixture units, got %d", len(units))
	}
	return units
}

// TestRenderPhase0Golden pins the ENTIRE Phase 0 output byte for byte.
//
// PROVES: the generated workflow's shape is reviewed, not incidental — a change
// to any line of it (a pin bump, a permission, the concurrency posture, the
// kill switch) has to be made deliberately and shows up in a diff a human
// reads. Without a full-file golden, a renderer edit could silently drop the
// `if:` gate or widen `permissions:` and every other test would still pass.
//
// Set GEN_UPDATE_GOLDEN=1 to rewrite the golden after an intentional change.
func TestRenderPhase0Golden(t *testing.T) {
	assertGolden(t, goldenPhase0Path, mustRender(t, loadFixtures(t), 0))
}

// TestRenderPhase1Golden pins the ACTING output — the one that deploys.
//
// PROVES: every clause of every fan-out job (the kill switch, the fail-open
// arm, the companion interlock, the `with:` map, `secrets: inherit`, the WIF
// permission grant) is reviewed as text. The narrower tests below each state
// ONE property in isolation so a failure names the property; this one catches
// everything they do not think to ask about.
func TestRenderPhase1Golden(t *testing.T) {
	assertGolden(t, goldenPhase1Path, mustRender(t, loadFixtures(t), 1))
}

func assertGolden(t *testing.T, path, got string) {
	t.Helper()
	if os.Getenv("GEN_UPDATE_GOLDEN") == "1" {
		if err := os.WriteFile(path, []byte(got), 0o644); err != nil {
			t.Fatalf("update golden: %v", err)
		}
		t.Log("golden updated; re-run without GEN_UPDATE_GOLDEN to assert")
		return
	}
	want, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read golden: %v (run with GEN_UPDATE_GOLDEN=1 to create it)", err)
	}
	if got != string(want) {
		t.Errorf("rendered workflow does not match %s\n%s", path, firstDiff(string(want), got))
	}
}

// firstDiff reports the first differing line, which is far more useful in a
// test log than dumping two ~120-line files.
func firstDiff(want, got string) string {
	w := strings.Split(want, "\n")
	g := strings.Split(got, "\n")
	for i := 0; i < len(w) || i < len(g); i++ {
		var wl, gl string
		if i < len(w) {
			wl = w[i]
		}
		if i < len(g) {
			gl = g[i]
		}
		if wl != gl {
			return fmt.Sprintf("first difference at line %d:\n  want: %q\n  got:  %q", i+1, wl, gl)
		}
	}
	return "(files differ only in trailing bytes)"
}

// TestRenderIsOrderIndependent feeds the same units in the opposite order.
//
// PROVES: the byte-stability tidy-check depends on. `bazel query` makes no
// ordering promise, so an unsorted render would produce a workflow that
// alternates between two equally-valid forms — turning the regeneration gate
// into a flaky red on unrelated PRs, which is how enforcement gets deleted.
func TestRenderIsOrderIndependent(t *testing.T) {
	forward, err := loadUnits(fixtureUnits)
	if err != nil {
		t.Fatalf("loadUnits: %v", err)
	}
	reversed, err := loadUnits([]string{fixtureUnits[1], fixtureUnits[0]})
	if err != nil {
		t.Fatalf("loadUnits(reversed): %v", err)
	}
	for _, phase := range []int{0, 1} {
		if mustRender(t, forward, phase) != mustRender(t, reversed, phase) {
			t.Errorf("phase %d: render output depends on input order — units are not sorted by name", phase)
		}
	}
}

// TestKillSwitchIsRendered asserts the spec §6.1 level-1 rollback guarantee.
//
// PROVES: the orchestrate job carries `vars.DELIVERY_ORCHESTRATOR_ENABLED ==
// 'true'`, so the whole orchestrator can be disabled by flipping a repo
// variable — no commit, no revert, no deploy. A rollback control nobody tests
// is a rollback control nobody has; //tools/conformance:check asserts the same
// thing against the COMMITTED file, so neither a renderer regression nor a
// hand-edit of the workflow can remove it quietly.
func TestKillSwitchIsRendered(t *testing.T) {
	got := mustRender(t, loadFixtures(t), 0)
	want := "    if: vars.DELIVERY_ORCHESTRATOR_ENABLED == 'true'\n"
	if !strings.Contains(got, want) {
		t.Errorf("orchestrate job is missing the kill switch condition %q", strings.TrimSpace(want))
	}
	// It must gate the JOB, not merely appear somewhere in the file: assert it
	// sits between the job id and its `runs-on`.
	job := got[strings.Index(got, "  orchestrate:\n"):]
	if strings.Index(job, want) > strings.Index(job, "    runs-on:") {
		t.Error("kill switch condition is not a job-level `if:` on orchestrate")
	}
}

// TestPhase0RendersNoFanOut is the shadow-mode invariant.
//
// PROVES: Phase 0 delivers nothing. The only job is `orchestrate`; no per-unit
// job, no `environment:` binding, no `bazel run <unit run target>` appears.
// This is the assertion that lets Phase 0 ship enabled by default.
func TestPhase0RendersNoFanOut(t *testing.T) {
	units := loadFixtures(t)
	got := mustRender(t, units, 0)

	jobs := jobIDs(got)
	if len(jobs) != 1 || jobs[0] != "orchestrate" {
		t.Errorf("Phase 0 must render exactly one job `orchestrate`, got %v", jobs)
	}
	if strings.Contains(got, "\n    environment:") {
		t.Error("Phase 0 output binds a GitHub Environment — that is a Phase 1 fan-out artifact")
	}
	for _, u := range units {
		if strings.Contains(got, "bazel run "+u.Run) {
			t.Errorf("Phase 0 output invokes the delivery target %s — shadow mode must not act", u.Run)
		}
	}
}

// jobIDs returns the job ids declared under the top-level `jobs:` key.
func jobIDs(yaml string) []string {
	var ids []string
	inJobs := false
	for _, line := range strings.Split(yaml, "\n") {
		if line == "jobs:" {
			inJobs = true
			continue
		}
		if !inJobs {
			continue
		}
		if line != "" && !strings.HasPrefix(line, " ") && !strings.HasPrefix(line, "#") {
			break
		}
		if strings.HasPrefix(line, "  ") && !strings.HasPrefix(line, "   ") &&
			strings.HasSuffix(line, ":") && !strings.HasPrefix(strings.TrimSpace(line), "#") {
			ids = append(ids, strings.TrimSuffix(strings.TrimSpace(line), ":"))
		}
	}
	return ids
}

// TestWriteAtomicIsIdempotent covers the property tidy-check literally asserts.
//
// PROVES: `bazel run //tools/ci:gen` twice leaves the tree byte-identical and
// reports "unchanged" the second time — so the regeneration gate can never
// redden a PR that changed nothing. Also proves no temp file is left behind
// next to the output (a stray `.delivery-gen-*` would itself show as a dirty
// tree and fail the same gate).
func TestWriteAtomicIsIdempotent(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "sub", "delivery.yaml")
	content := mustRender(t, loadFixtures(t), 0)

	changed, err := writeAtomic(path, content)
	if err != nil || !changed {
		t.Fatalf("first write: changed=%v err=%v (want changed=true, nil)", changed, err)
	}
	changed, err = writeAtomic(path, content)
	if err != nil || changed {
		t.Fatalf("second write: changed=%v err=%v (want changed=false, nil)", changed, err)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read back: %v", err)
	}
	if string(got) != content {
		t.Error("file content drifted across two identical writes")
	}
	entries, err := os.ReadDir(filepath.Dir(path))
	if err != nil {
		t.Fatalf("readdir: %v", err)
	}
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), ".delivery-gen-") {
			t.Errorf("temp file %q left behind — a dirty tree would fail tidy-check", e.Name())
		}
	}
}

// TestDecodeUnitRejectsDrift covers the macro/generator contract.
//
// PROVES: a *.delivery.json this generator does not understand is a hard error,
// not a silently-skipped unit. The macro (tools/delivery/defs.bzl) and this
// renderer are edited independently; a dropped unit is invisible in the output
// (nothing to see) and is precisely the #1794 shape — the thing that should
// have been governed simply was not there.
func TestDecodeUnitRejectsDrift(t *testing.T) {
	cases := []struct {
		name string
		json string
		want string
	}{
		{"future schema", `{"schema":2,"name":"x","run":"//a:b","environments":["development"]}`, "schema 2"},
		{"no name", `{"schema":1,"run":"//a:b","environments":["development"]}`, "no name"},
		{"no run target", `{"schema":1,"name":"x","environments":["development"]}`, "no run target"},
		{"empty ladder", `{"schema":1,"name":"x","run":"//a:b"}`, "empty environment ladder"},
		{"not json", `{`, "decode"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := decodeUnit([]byte(tc.json))
			if err == nil {
				t.Fatalf("want an error containing %q, got nil", tc.want)
			}
			if !strings.Contains(err.Error(), tc.want) {
				t.Errorf("want error containing %q, got %v", tc.want, err)
			}
		})
	}
}

// TestLoadUnitsRejectsDuplicateNames guards the second half of that contract.
//
// PROVES: two units with the same name never render — they would collide into
// one job id, and YAML resolves the collision by silently keeping the last one.
// //tools/conformance:check catches this offline; this stops the generator
// producing the broken file even if conformance is not run.
func TestLoadUnitsRejectsDuplicateNames(t *testing.T) {
	dir := t.TempDir()
	body := `{"schema":1,"name":"dup","kind":"pulumi","run":"//a:up","environments":["development"],"github_environment":"e-{env}"}`
	var paths []string
	for i := 0; i < 2; i++ {
		p := filepath.Join(dir, fmt.Sprintf("u%d.delivery.json", i))
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			t.Fatalf("write fixture: %v", err)
		}
		paths = append(paths, p)
	}
	if _, err := loadUnits(paths); err == nil || !strings.Contains(err.Error(), "duplicate delivery unit name") {
		t.Errorf("want a duplicate-name error, got %v", err)
	}
}

// TestDiscoverUsesBazelAndFailsClosed drives discovery against a fake bazel.
//
// PROVES: (1) discovery is pluggable and therefore testable at all — the
// --bazel/GEN_BAZEL seam works; (2) it filters the query output down to
// `.delivery_unit` labels; (3) it maps a label to the right bazel-bin path;
// and (4) an EMPTY query result is a hard failure, not an empty inventory.
// (4) is the important one: silently rendering "no units" is the
// green-while-checking-nothing failure this repo has shipped before.
func TestDiscoverUsesBazelAndFailsClosed(t *testing.T) {
	bin := t.TempDir()

	fake := func(queryOut string) bazelRunner {
		return func(args ...string) ([]byte, error) {
			switch args[0] {
			case "query":
				return []byte(queryOut), nil
			case "build":
				return nil, nil
			case "info":
				return []byte(bin + "\n"), nil
			}
			return nil, fmt.Errorf("unexpected bazel %v", args)
		}
	}

	paths, err := discover(fake("//pkg/one:alpha.delivery_unit\n//pkg/two:beta.delivery_unit\n//pkg/two:beta.delivery\n"))
	if err != nil {
		t.Fatalf("discover: %v", err)
	}
	want := []string{
		filepath.Join(bin, "pkg/one", "alpha.delivery.json"),
		filepath.Join(bin, "pkg/two", "beta.delivery.json"),
	}
	if len(paths) != len(want) {
		t.Fatalf("want %d metadata paths, got %v", len(want), paths)
	}
	for i := range want {
		if paths[i] != want[i] {
			t.Errorf("path %d: want %q, got %q", i, want[i], paths[i])
		}
	}

	if _, err := discover(fake("\n")); err == nil {
		t.Error("an empty query result must fail closed, not render an empty inventory")
	}
}

// ---------------------------------------------------------------------------
// Phase 1 — the rung that acts (spec §4.3, §6)
// ---------------------------------------------------------------------------

// TestOutputVarNameIsTheOrchestratorContract pins the CROSS-BINARY rule.
//
// PROVES: this generator folds a unit name into an output key exactly as
// //tools/delivery/orchestrate does. The table is duplicated verbatim in that
// package's TestOutputVarName; the two cannot share a Go package in this repo
// (the root go.mod module path and the Bazel/gazelle importpath prefix
// disagree, so a first-party cross-package import compiles under one build
// system or the other, never both), so they are pinned by identical tables
// instead — a one-sided edit fails its own package's test.
//
// The Phase-1 skeleton failed exactly this: it left "-" alone and rendered
// `affected_oauth-user-inspector`, which GitHub Actions resolves to "" rather
// than erroring, so the deploy condition could never be true.
func TestOutputVarNameIsTheOrchestratorContract(t *testing.T) {
	tests := map[string]string{
		"oauth-user-inspector": "oauth_user_inspector",
		"tabula-api":           "tabula_api",
		"charts":               "charts",
		"a.b/c":                "a_b_c",
	}
	for in, want := range tests {
		if got := outputVarName(in); got != want {
			t.Errorf("outputVarName(%q) = %q, want %q", in, got, want)
		}
	}
}

// affectedToken matches the output names the rendered conditions read.
var affectedToken = regexp.MustCompile(`needs\.orchestrate\.outputs\.affected_([A-Za-z0-9_.\-/]+)`)

// TestEveryAffectedOutputNameIsOneTheOrchestratorEmits is the output-name
// contract, asserted against the rendered YAML rather than against the
// function that produced it.
//
// PROVES: every `affected_*` token in the workflow is a key the orchestrator
// will actually publish for a DECLARED unit. It fails on the skeleton's dash
// bug, on a typo, and on a condition referencing a unit that no longer exists
// — all three of which GitHub Actions accepts silently, evaluating the unknown
// output to the empty string and skipping the job forever.
func TestEveryAffectedOutputNameIsOneTheOrchestratorEmits(t *testing.T) {
	units := loadFixtures(t)
	emitted := map[string]string{} // output key -> the unit that emits it
	for _, u := range units {
		emitted[outputVarName(u.Name)] = u.Name
	}

	for _, src := range []struct{ what, body string }{
		{"rendered phase 1", mustRender(t, units, 1)},
		// ...and the file actually committed, which is rendered from the REAL
		// declarations rather than these fixtures.
		{deliveryWorkflowRel, mustRead(t, deliveryWorkflowRel)},
	} {
		found := affectedToken.FindAllStringSubmatch(src.body, -1)
		if len(found) == 0 {
			t.Errorf("%s references no affected_* output at all — the fan-out is ungated, or this test's pattern drifted", src.what)
			continue
		}
		for _, m := range found {
			if _, ok := emitted[m[1]]; !ok {
				t.Errorf("%s reads needs.orchestrate.outputs.affected_%s, which the orchestrator never emits (it emits %v) — GitHub resolves an unknown output to \"\", so that condition can never be true and the job silently never runs",
					src.what, m[1], sortedKeys(emitted))
			}
		}

		// ...and the orchestrate JOB must re-export each of them. A step
		// writing $GITHUB_OUTPUT is invisible to `needs.<job>.outputs.<name>`
		// unless the job declares it: without the block the conditions above
		// read "" forever. Same silent-skip outcome as the dash bug, different
		// cause — actionlint reports it as "property ... is not defined in
		// object type {}".
		declared := childKeysOfJobKey(t, parseWorkflow(t, src.body), "orchestrate", "outputs")
		for _, m := range found {
			if !contains(declared, "affected_"+m[1]) {
				t.Errorf("%s: the orchestrate job does not declare the output affected_%s it re-exports (declares %v) — every reader of it resolves to \"\"",
					src.what, m[1], declared)
			}
		}
	}
}

// childKeysOfJobKey returns the child keys of one mapping key inside one job
// (e.g. the names under `outputs:`).
func childKeysOfJobKey(t *testing.T, lines []wfLine, job, key string) []string {
	t.Helper()
	start := indexOfJob(t, lines, job)
	parent := lines[start].indent
	child := -1
	for i := start + 1; i < len(lines); i++ {
		if lines[i].indent <= parent {
			break
		}
		if child < 0 {
			child = lines[i].indent
		}
		if lines[i].indent == child && lines[i].key == key {
			return childKeys(lines, i)
		}
	}
	t.Fatalf("job %q has no %q mapping", job, key)
	return nil
}

// TestPhase1RendersOnlyTheFirstRung is the blast-radius assertion.
//
// PROVES: a push delivers DEVELOPMENT and nothing else. The skeleton chained
// the whole declared ladder off the push trigger, so a merge to main would
// have walked straight into production — with the environment approval as the
// only thing in the way.
func TestPhase1RendersOnlyTheFirstRung(t *testing.T) {
	units := loadFixtures(t)
	got := mustRender(t, units, 1)

	want := []string{"orchestrate", "oauth-user-inspector-build", "zitadel-apps-development", "oauth-user-inspector-development"}
	jobs := jobIDs(got)
	if len(jobs) != len(want) {
		t.Fatalf("phase 1 rendered jobs %v, want exactly %v", jobs, want)
	}
	for _, w := range want {
		if !contains(jobs, w) {
			t.Errorf("phase 1 is missing job %q (got %v)", w, jobs)
		}
	}
	for _, u := range units {
		for _, env := range u.Environments[1:] {
			if contains(jobs, u.Name+"-"+env) {
				t.Errorf("phase 1 rendered a %q job — promotion stays release-gated in the legacy workflow until Phase 2", u.Name+"-"+env)
			}
		}
	}
}

// TestPhase1ChainsTheDeployBehindItsCompanions is expand-before-serve (§2.15).
//
// PROVES: the deploy job cannot start before its companion has finished, and
// tolerates a SKIPPED companion (the ZITADEL_APPS_AUTO_APPLY gate is off)
// while refusing a FAILED one — legacy deploy-dev's exact interlock.
func TestPhase1ChainsTheDeployBehindItsCompanions(t *testing.T) {
	lines := parseWorkflow(t, mustRender(t, loadFixtures(t), 1))

	needs := jobScalar(t, lines, "oauth-user-inspector-development", "needs")
	if want := "[orchestrate, oauth-user-inspector-build, zitadel-apps-development]"; needs != want {
		t.Errorf("deploy job needs = %q, want %q", needs, want)
	}
	if got := jobScalar(t, lines, "oauth-user-inspector-build", "needs"); got != "[orchestrate]" {
		t.Errorf("build job needs = %q, want [orchestrate]", got)
	}
	if got := jobScalar(t, lines, "zitadel-apps-development", "needs"); got != "[orchestrate]" {
		t.Errorf("companion job needs = %q, want [orchestrate]", got)
	}

	cond := jobScalar(t, lines, "oauth-user-inspector-development", "if")
	if !strings.Contains(cond, "needs.zitadel-apps-development.result != 'failure'") {
		t.Errorf("deploy `if:` does not tolerate a skipped companion / refuse a failed one: %s", cond)
	}
}

// TestPhase1ConditionsPreserveLegacyParity walks every clause the jobs this
// replaces carried.
//
// PROVES, clause by clause: the kill switch gates BOTH jobs (rollback level 1
// must stop the whole fan-out, not half of it); the companion keeps its
// ZITADEL_APPS_AUTO_APPLY gate (without it the apply fails instead of cleanly
// no-opping while the machine key is unseeded); both keep the FAIL-OPEN arm
// (if the orchestrator could not decide, deliver anyway — detection must never
// be the reason a real change fails to ship); and both use `!cancelled()`
// rather than the implicit success()-of-needs, which would make the fail-open
// arm unreachable.
func TestPhase1ConditionsPreserveLegacyParity(t *testing.T) {
	lines := parseWorkflow(t, mustRender(t, loadFixtures(t), 1))
	failOpen := "(needs.orchestrate.result != 'success' || needs.orchestrate.outputs.affected_oauth_user_inspector == 'true')"

	for _, tc := range []struct {
		job   string
		wants []string
		nots  []string
	}{
		{
			job:   "zitadel-apps-development",
			wants: []string{killSwitchExpr, "vars.ZITADEL_APPS_AUTO_APPLY == 'true'", "always()", "!cancelled()", failOpen},
		},
		{
			// The build job is push-lane only: legacy's release/dispatch arms
			// belong to the promotion ladder, which stays legacy in Phase 1.
			job:   "oauth-user-inspector-build",
			wants: []string{killSwitchExpr, "always()", "!cancelled()", failOpen},
			nots:  []string{"github.event_name", "github.event.release"},
		},
		{
			job: "oauth-user-inspector-development",
			wants: []string{
				killSwitchExpr, "!cancelled()", failOpen,
				// No image, no deploy — and `== 'success'` rather than
				// `!= 'failure'`, so a SKIPPED build stops it too.
				"needs.oauth-user-inspector-build.result == 'success'",
			},
			// The deploy must NOT inherit the companion's variable gate:
			// turning zitadel auto-apply off would then stop deploying the app.
			nots: []string{"vars.ZITADEL_APPS_AUTO_APPLY"},
		},
	} {
		cond := jobScalar(t, lines, tc.job, "if")
		if !strings.HasPrefix(cond, killSwitchExpr) {
			t.Errorf("%s: `if:` must LEAD with the kill switch (a bare `!cancelled()` first would also be an invalid YAML tag): %s", tc.job, cond)
		}
		for _, w := range tc.wants {
			if !strings.Contains(cond, w) {
				t.Errorf("%s: `if:` is missing %q\n  got: %s", tc.job, w, cond)
			}
		}
		for _, n := range tc.nots {
			if strings.Contains(cond, n) {
				t.Errorf("%s: `if:` must not contain %q\n  got: %s", tc.job, n, cond)
			}
		}
	}
}

// TestPhase1CallerJobsCarryWifAndSecrets covers the credentials half.
//
// PROVES: every generated caller grants `id-token: write` on ITSELF and passes
// `secrets: inherit`. A called workflow's permissions can only NARROW the
// caller's, so without the job-level grant both callees' keyless-WIF auth step
// fails — and without `secrets: inherit` the deploy has no Pulumi token, no
// BuildBuddy key and no tailnet credentials. The skeleton had neither.
func TestPhase1CallerJobsCarryWifAndSecrets(t *testing.T) {
	body := mustRender(t, loadFixtures(t), 1)
	lines := parseWorkflow(t, body)

	for _, job := range []string{"zitadel-apps-development", "oauth-user-inspector-development"} {
		if got := jobScalar(t, lines, job, "secrets"); got != "inherit" {
			t.Errorf("%s: secrets = %q, want inherit", job, got)
		}
	}
	// The build job is a PLAIN job (it authenticates itself and needs no
	// `secrets: inherit`), but it mints a WIF token like the callers do, so the
	// permission grant is asserted for all three.
	for _, job := range []string{"oauth-user-inspector-build", "zitadel-apps-development", "oauth-user-inspector-development"} {
		block, ok := jobText(body, job)
		if !ok {
			t.Fatalf("%s: cannot isolate the job block", job)
		}
		for _, want := range []string{"    permissions:\n", "      contents: read\n", "      id-token: write\n"} {
			if !strings.Contains(block, want) {
				t.Errorf("%s: missing %q — keyless WIF needs it granted on the job that authenticates", job, strings.TrimSpace(want))
			}
		}
	}

	// The workflow-level grant must stay narrow: orchestrate never talks to
	// GCP, and a workflow-level id-token would hand it a cloud credential.
	// Read the real mapping, not the file text — the header COMMENT explains
	// this very rule and would otherwise satisfy a substring check.
	wf := topLevelChildKeys(t, lines, "permissions")
	sort.Strings(wf)
	if want := []string{"actions", "contents"}; strings.Join(wf, ",") != strings.Join(want, ",") {
		t.Errorf("workflow-level permissions = %v, want %v — id-token: write belongs on the fan-out jobs that need it, not on orchestrate", wf, want)
	}
}

// TestNoCallerJobDeclaresConcurrency is a REGRESSION GUARD, not a preference.
//
// PROVES: no job with `uses:` carries a `concurrency:` key. Spec §4.3 asks for
// per-unit+env groups and this is the one place the implementation knowingly
// differs: #1607 put exactly that on tabula-deploy.yaml's calling jobs and
// every dispatch failed INSTANTLY with no runner assigned, reproducibly, even
// with a static expression-free group string — the same happened with the
// group inside the reusable workflow's own job. Serialization is achieved by
// the workflow-level constant group instead, which is strictly stronger (it
// also serializes unrelated units). Someone will eventually "fix" this by
// adding the group back; this test is the note they will read when it goes red.
func TestNoCallerJobDeclaresConcurrency(t *testing.T) {
	body := mustRender(t, loadFixtures(t), 1)
	for _, job := range jobIDs(body) {
		block, ok := jobText(body, job)
		if !ok {
			t.Fatalf("cannot isolate job %q", job)
		}
		if !strings.Contains(block, "    uses:") {
			continue
		}
		if strings.Contains(block, "    concurrency:") {
			t.Errorf("job %q has both `uses:` and `concurrency:` — GitHub Actions rejects that combination (#1607: every dispatch failed instantly, no runner assigned). Serialize at the workflow level instead", job)
		}
	}
	// ...and the workflow-level group must therefore actually be there.
	if !strings.Contains(body, "\nconcurrency:\n  group: delivery-orchestrate\n  cancel-in-progress: false\n") {
		t.Error("the workflow-level coalescing group is gone — nothing serializes two delivery runs against one live environment")
	}
}

// TestPhase1RejectsDeclarationsThatWouldRenderABrokenWorkflow.
//
// PROVES: the generator fails at REGENERATE time (cheap, local, attributable
// to whoever changed the declaration) for every input that GitHub would
// otherwise reject at workflow startup — taking `orchestrate` down with it —
// or accept and fail mid-delivery on main.
func TestPhase1RejectsDeclarationsThatWouldRenderABrokenWorkflow(t *testing.T) {
	base := func() unit {
		return unit{
			Schema: 1, Name: "app", Kind: kindCloudRun, Run: "//app:deploy",
			Environments: []string{"development"}, GitHubEnvironment: "app-{env}",
			BuildContext: "app/", ImageRepositoryPath: "app/api",
			WorkflowInputs: map[string]any{
				"app-name": "app", "env-prefix": "APP",
				"pulumi-dir": "app/infra", "service-name": "app",
			},
		}
	}
	companion := unit{
		Schema: 1, Name: "zitadel-apps", Kind: "pulumi", Run: "//z:up",
		Environments: []string{"development"}, GitHubEnvironment: "app-{env}",
	}

	cases := []struct {
		name  string
		units []unit
		want  string
	}{
		{
			name: "companion is not a declared unit",
			units: func() []unit {
				u := base()
				u.Companions = []string{"nope"}
				return []unit{u}
			}(),
			want: "not a declared delivery() unit",
		},
		{
			name: "companion has no reusable workflow registered",
			units: func() []unit {
				u := base()
				u.Companions = []string{"other"}
				o := companion
				o.Name = "other"
				return []unit{u, o}
			}(),
			want: "no reusable workflow registered",
		},
		{
			name: "companion does not declare the rung",
			units: func() []unit {
				u := base()
				u.Companions = []string{"zitadel-apps"}
				c := companion
				c.Environments = []string{"production"}
				return []unit{u, c}
			}(),
			want: "declares no \"development\" rung",
		},
		{
			name: "no docker build attrs on a non-Bazel cloud-run unit",
			units: func() []unit {
				u := base()
				u.BuildContext = ""
				return []unit{u}
			}(),
			want: "needs build_context and image_repository_path",
		},
		{
			name: "a Bazel image target is not renderable yet",
			units: func() []unit {
				u := base()
				u.Build = "//app:image_push"
				return []unit{u}
			}(),
			want: "renders the Docker path only",
		},
		{
			name: "required reusable-workflow input missing",
			units: func() []unit {
				u := base()
				delete(u.WorkflowInputs, "pulumi-dir")
				return []unit{u}
			}(),
			want: "missing required workflow_inputs",
		},
		{
			name: "non-scalar workflow input",
			units: func() []unit {
				u := base()
				u.WorkflowInputs["extra"] = []any{"a"}
				return []unit{u}
			}(),
			want: "is not a scalar",
		},
		{
			name: "null workflow input",
			units: func() []unit {
				u := base()
				u.WorkflowInputs["extra"] = nil
				return []unit{u}
			}(),
			want: "value is null",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			sorted := append([]unit(nil), tc.units...)
			sort.Slice(sorted, func(i, j int) bool { return sorted[i].Name < sorted[j].Name })
			_, err := render(sorted, 1, testWorkflowFile)
			if err == nil {
				t.Fatalf("render succeeded; want an error containing %q", tc.want)
			}
			if !strings.Contains(err.Error(), tc.want) {
				t.Errorf("want an error containing %q, got: %v", tc.want, err)
			}
		})
	}
}

// TestPhase1DeliversNothingWhenAUnitIsNotCloudRun keeps the fan-out honest
// about what it knows how to invoke.
//
// PROVES: a "pulumi" unit that is nobody's companion renders no job at all —
// rather than a guessed one. zitadel-apps IS a declared unit in its own right;
// it appears once, as oauth's companion, and never as a standalone ladder.
func TestPhase1DeliversNothingWhenAUnitIsNotCloudRun(t *testing.T) {
	got := mustRender(t, loadFixtures(t), 1)
	if n := strings.Count(got, "\n  zitadel-apps-development:\n"); n != 1 {
		t.Errorf("zitadel-apps-development is rendered %d times, want exactly 1 (a job id declared twice silently keeps only the last)", n)
	}
	for _, env := range []string{"nonproduction", "production"} {
		if strings.Contains(got, "\n  zitadel-apps-"+env+":\n") {
			t.Errorf("a standalone zitadel-apps-%s job was rendered — companions follow their consumer's rung", env)
		}
	}
}

// jobText returns the text of one job block (its id line plus every following
// line indented deeper than the id).
func jobText(yaml, job string) (string, bool) {
	marker := "\n  " + job + ":\n"
	i := strings.Index(yaml, marker)
	if i < 0 {
		return "", false
	}
	rest := yaml[i+1:]
	var b strings.Builder
	for n, line := range strings.Split(rest, "\n") {
		if n > 0 && line != "" && !strings.HasPrefix(line, "   ") {
			break
		}
		b.WriteString(line)
		b.WriteString("\n")
	}
	return b.String(), true
}
