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
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

// ANTI-TRANSCRIPTION-DRIFT GUARD.
//
// Phase 1 moves oauth-user-inspector's development lane out of a hand-written
// workflow and into a generated one. The inputs were TRANSCRIBED — a human
// copied ten `with:` values from oauth-user-inspector-deploy.yaml into a
// delivery() declaration. Transcription is exactly the failure this whole
// program exists to end (the spec's §1 table is four instances of one copy
// drifting from another), and it is invisible in review: a wrong
// `pulumi-dir`, `env-prefix` or `cloudflare-token-secret-project` renders as a
// perfectly plausible line of YAML and fails, if at all, in the middle of a
// deploy.
//
// So the two files are compared here, mechanically, on every test run: the
// REAL generated workflow against the REAL legacy workflow, with an EXPLICIT
// allowlist of the differences Phase 1 intends. Any other divergence — in
// either direction, in either file — fails. Both files are runfiles (see the
// BUILD `data` attr), so this holds under `bazel test` and under a plain
// `GOWORK=off go test ./...`.
//
// The allowlist is deliberately stated as data rather than prose: a reviewer
// reads three entries and decides whether Phase 1 should differ in exactly
// those ways, instead of diffing two YAML files by eye.

const (
	legacyWorkflowRel   = "../../../.github/workflows/oauth-user-inspector-deploy.yaml"
	deliveryWorkflowRel = "../../../.github/workflows/delivery.yaml"

	// The legacy jobs whose behaviour the generated development lane assumes.
	legacyDeployJob    = "deploy-dev"
	legacyCompanionJob = "zitadel-dev"
	legacyBuildJob     = "build"

	// Their generated counterparts.
	genDeployJob    = "oauth-user-inspector-development"
	genCompanionJob = "zitadel-apps-development"
	genBuildJob     = "oauth-user-inspector-build"

	// The reusable deploy workflow, read to derive the CHECK-RUN NAME the
	// promotion soak gate has to scan for.
	deployCloudRunRel = "../../../.github/workflows/_deploy-cloud-run.yaml"
)

// inputRewrite is a value difference Phase 1 intends, stated as the exact
// textual rewrite that turns the legacy value into the generated one — so the
// test still compares the whole value, not merely "this key may differ".
type inputRewrite struct {
	from, to string
	why      string
}

// expectedInputDiff is the ENTIRE sanctioned difference between the legacy
// deploy-dev `with:` map and the generated one: no key is added, none dropped,
// and exactly one VALUE is rewritten — the digest's source job. Everything
// else must be equal, in both directions.
var expectedInputDiff = struct {
	rewrites map[string]inputRewrite
}{
	rewrites: map[string]inputRewrite{
		"image-digest": {
			from: "needs." + legacyBuildJob + ".",
			to:   "needs." + genBuildJob + ".",
			why:  "same build-once digest, produced by the generated build job instead of the hand-written one",
		},
	},
}

// TestGeneratedDevLaneMatchesLegacy is the guard itself.
//
// PROVES: the generated development deploy passes _deploy-cloud-run.yaml
// exactly what the hand-written one passed, apart from the three-entry
// allowlist above — so the migration cannot silently change WHICH project,
// stack, region, service, smoke script or Cloudflare token the deploy uses.
func TestGeneratedDevLaneMatchesLegacy(t *testing.T) {
	legacy := parseWorkflow(t, mustRead(t, legacyWorkflowRel))
	generated := parseWorkflow(t, mustRead(t, deliveryWorkflowRel))

	legacyWith := jobWith(t, legacy, legacyDeployJob)
	genWith := jobWith(t, generated, genDeployJob)

	// `environment` is not a transcribed input: the ladder supplies it. Assert
	// it explicitly instead of allowlisting it away — a generated job pointed
	// at the wrong rung would deploy production from a push.
	if got := genWith["environment"]; got != "development" {
		t.Errorf("%s passes environment=%q, want %q (environments[0] of the declaration)", genDeployJob, got, "development")
	}
	if got := legacyWith["environment"]; got != "development" {
		t.Fatalf("legacy %s passes environment=%q — this test is comparing the wrong job", legacyDeployJob, got)
	}

	assertMapsMatch(t, legacyDeployJob, legacyWith, genDeployJob, genWith, expectedInputDiff.rewrites)
}

// TestGeneratedCompanionMatchesLegacy does the same for the expand half.
//
// PROVES: the generated companion calls _zitadel-apps-apply.yaml with exactly
// the legacy zitadel-dev inputs — no allowlist at all, because nothing about
// the companion is supposed to change in Phase 1.
func TestGeneratedCompanionMatchesLegacy(t *testing.T) {
	legacy := parseWorkflow(t, mustRead(t, legacyWorkflowRel))
	generated := parseWorkflow(t, mustRead(t, deliveryWorkflowRel))

	assertMapsMatch(t, legacyCompanionJob, jobWith(t, legacy, legacyCompanionJob),
		genCompanionJob, jobWith(t, generated, genCompanionJob), nil)
}

// TestGeneratedLaneCallsTheSameReusableWorkflows keeps the comparison honest:
// two `with:` maps agreeing means nothing if they are fed to different files.
func TestGeneratedLaneCallsTheSameReusableWorkflows(t *testing.T) {
	legacy := parseWorkflow(t, mustRead(t, legacyWorkflowRel))
	generated := parseWorkflow(t, mustRead(t, deliveryWorkflowRel))

	for _, pair := range []struct{ legacyJob, genJob string }{
		{legacyDeployJob, genDeployJob},
		{legacyCompanionJob, genCompanionJob},
	} {
		want := jobScalar(t, legacy, pair.legacyJob, "uses")
		got := jobScalar(t, generated, pair.genJob, "uses")
		if got != want {
			t.Errorf("%s calls %q but legacy %s calls %q", pair.genJob, got, pair.legacyJob, want)
		}
	}
}

// TestLegacyWorkflowNoLongerTriggersOnPush is the legacy-surgery assertion.
//
// PROVES: exactly one trigger was removed. `push:` is gone (otherwise BOTH
// workflows would deploy development on every merge — a double deploy racing
// itself on one Pulumi stack), while `release:` and `workflow_dispatch:`
// survive, because the release ladder still lives there and dispatch is the
// escape hatch Phase 1 promises for one release cycle (spec §6).
func TestLegacyWorkflowNoLongerTriggersOnPush(t *testing.T) {
	triggers := topLevelChildKeys(t, parseWorkflow(t, mustRead(t, legacyWorkflowRel)), "on")

	if contains(triggers, "push") {
		t.Errorf("%s still triggers on push — the generated delivery.yaml now owns the development lane, so both would deploy it on every merge (triggers: %v)", legacyWorkflowRel, triggers)
	}
	for _, want := range []string{"release", "workflow_dispatch"} {
		if !contains(triggers, want) {
			t.Errorf("%s lost its %q trigger — Phase 1 removes ONLY `push:`; %q still drives the promotion ladder / break-glass (triggers: %v)", legacyWorkflowRel, want, want, triggers)
		}
	}
}

// ---------------------------------------------------------------------------
// assertions
// ---------------------------------------------------------------------------

// assertMapsMatch compares two `with:` maps modulo an expected set of value
// rewrites, and fails on ANY unlisted difference — a missing key, an extra key,
// a changed value, or a rewrite that turned out to be a no-op (a stale
// allowlist entry hides a real divergence, the same way a stale row in
// delivery-legacy.tsv would).
func assertMapsMatch(t *testing.T, legacyJob string, legacy map[string]string, genJob string, gen map[string]string, rewrites map[string]inputRewrite) {
	t.Helper()

	for k, rw := range rewrites {
		if _, ok := legacy[k]; !ok {
			t.Errorf("allowlist rewrites %q (%s) but legacy %s does not pass it — stale allowlist entry", k, rw.why, legacyJob)
		}
		if _, ok := gen[k]; !ok {
			t.Errorf("allowlist rewrites %q (%s) but %s does not pass it — stale allowlist entry", k, rw.why, genJob)
		}
		if v, ok := legacy[k]; ok && !strings.Contains(v, rw.from) {
			t.Errorf("allowlist rewrites %q from %q, which does not appear in legacy's value %q — stale allowlist entry", k, rw.from, v)
		}
	}

	for _, k := range sortedKeys(legacy) {
		if k == "environment" {
			continue // asserted explicitly by the caller; supplied by the ladder
		}
		got, ok := gen[k]
		if !ok {
			t.Errorf("%s does not pass %q, which legacy %s passes as %q — an input silently lost in transcription", genJob, k, legacyJob, legacy[k])
			continue
		}
		want := legacy[k]
		if rw, isRewritten := rewrites[k]; isRewritten {
			want = strings.ReplaceAll(want, rw.from, rw.to)
		}
		if got != want {
			t.Errorf("%s passes %s=%q but legacy %s passes %s=%q (expected here as %q) — transcription drift", genJob, k, got, legacyJob, k, legacy[k], want)
		}
	}
	for _, k := range sortedKeys(gen) {
		if k == "environment" {
			continue
		}
		if _, ok := legacy[k]; !ok {
			t.Errorf("%s passes %s=%q, which legacy %s does not pass and the allowlist does not sanction", genJob, k, gen[k], legacyJob)
		}
	}
}

// ---------------------------------------------------------------------------
// a deliberately tiny workflow reader
// ---------------------------------------------------------------------------
//
// WHY NOT A YAML LIBRARY: the repo's root go.mod requires nothing, so pulling
// gopkg.in/yaml.v3 in for a test would mean a go.mod/go.sum edit plus a
// MODULE.bazel dep — a build-graph change to read four mappings. This reads
// only what it needs (mapping keys and single-line scalars at known
// indentation, the same shape check.sh's awk scanners parse) and FAILS LOUDLY
// on anything it was not designed for: a block scalar, a flow mapping, a tab.
// A parser that silently mis-reads would turn this guard green while comparing
// nothing, which is the failure mode the guard exists to prevent.

// wfLine is one significant line: its indentation, key and raw scalar.
type wfLine struct {
	indent int
	key    string
	value  string
	num    int
}

// parseWorkflow reduces a workflow to its significant "key: value" lines.
func parseWorkflow(t *testing.T, src string) []wfLine {
	t.Helper()
	var out []wfLine
	for i, raw := range strings.Split(src, "\n") {
		line := strings.TrimRight(raw, "\r")
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		if strings.Contains(line, "\t") {
			t.Fatalf("line %d contains a tab — this reader assumes space indentation", i+1)
		}
		indent := len(line) - len(strings.TrimLeft(line, " "))
		if trimmed == "-" {
			out = append(out, wfLine{indent: indent, key: "", value: trimmed, num: i + 1})
			continue
		}
		if strings.HasPrefix(trimmed, "- ") {
			// A sequence item whose value is a mapping: `- env:` puts `env` at
			// the item's indent + 2, which is exactly where its siblings on the
			// following lines sit. Modelling it that way (rather than as an
			// opaque non-key line) is what lets a step's own keys —
			// `- env:` / `uses:` / `run:` — be read at all; the promotion soak
			// gate's settings live in one.
			trimmed = strings.TrimSpace(trimmed[2:])
			indent += 2
		}
		key, value, ok := strings.Cut(trimmed, ":")
		if !ok {
			out = append(out, wfLine{indent: indent, key: "", value: trimmed, num: i + 1})
			continue
		}
		value = strings.TrimSpace(value)
		if value == "|" || value == ">" || strings.HasPrefix(value, "|-") || strings.HasPrefix(value, ">-") {
			// Block scalars exist in these files (script steps). They are not
			// inside anything this test reads; record the key with an
			// unmistakable marker so a future assertion cannot compare it as
			// if it were a plain value.
			value = "<block-scalar>"
		}
		out = append(out, wfLine{indent: indent, key: strings.TrimSpace(key), value: value, num: i + 1})
	}
	if len(out) == 0 {
		t.Fatal("workflow parsed to zero significant lines — the reader or the file layout drifted")
	}
	return out
}

// childKeys returns the keys directly under the mapping that starts at
// lines[start], i.e. the keys at the first indentation deeper than lines[start].
func childKeys(lines []wfLine, start int) []string {
	if start+1 >= len(lines) {
		return nil
	}
	parent := lines[start].indent
	child := -1
	var keys []string
	for _, l := range lines[start+1:] {
		if l.indent <= parent {
			break
		}
		if child < 0 {
			child = l.indent
		}
		if l.indent == child && l.key != "" {
			keys = append(keys, l.key)
		}
	}
	return keys
}

// indexOfTopLevel finds a column-0 key.
func indexOfTopLevel(lines []wfLine, key string) int {
	for i, l := range lines {
		if l.indent == 0 && l.key == key {
			return i
		}
	}
	return -1
}

func topLevelChildKeys(t *testing.T, lines []wfLine, key string) []string {
	t.Helper()
	i := indexOfTopLevel(lines, key)
	if i < 0 {
		t.Fatalf("no top-level %q key in the workflow", key)
	}
	return childKeys(lines, i)
}

// indexOfJob finds a job id under the top-level `jobs:` mapping.
func indexOfJob(t *testing.T, lines []wfLine, job string) int {
	t.Helper()
	jobs := indexOfTopLevel(lines, "jobs")
	if jobs < 0 {
		t.Fatal("no top-level `jobs:` key in the workflow")
	}
	jobIndent := -1
	for i := jobs + 1; i < len(lines); i++ {
		if lines[i].indent == 0 {
			break
		}
		if jobIndent < 0 {
			jobIndent = lines[i].indent
		}
		if lines[i].indent == jobIndent && lines[i].key == job {
			return i
		}
	}
	t.Fatalf("no job %q in the workflow", job)
	return -1
}

// jobScalar reads one job-level key ("uses", "if", "needs", "secrets").
func jobScalar(t *testing.T, lines []wfLine, job, key string) string {
	t.Helper()
	start := indexOfJob(t, lines, job)
	parent := lines[start].indent
	child := -1
	for _, l := range lines[start+1:] {
		if l.indent <= parent {
			break
		}
		if child < 0 {
			child = l.indent
		}
		if l.indent == child && l.key == key {
			return unquote(l.value)
		}
	}
	t.Fatalf("job %q has no %q key", job, key)
	return ""
}

// jobWith reads a job's `with:` mapping as key -> normalized scalar.
//
// Values are unquoted before comparison, so the legacy file's bare
// `app-name: oauth-user-inspector` and the generated file's quoted
// `app-name: "oauth-user-inspector"` compare equal — they pass the same value,
// and quoting style is the generator's business. Types are pinned separately
// by the golden (`workload-migrated: false` renders as a YAML boolean).
func jobWith(t *testing.T, lines []wfLine, job string) map[string]string {
	t.Helper()
	start := indexOfJob(t, lines, job)
	parent := lines[start].indent
	child := -1
	withAt := -1
	for i := start + 1; i < len(lines); i++ {
		if lines[i].indent <= parent {
			break
		}
		if child < 0 {
			child = lines[i].indent
		}
		if lines[i].indent == child && lines[i].key == "with" {
			withAt = i
			break
		}
	}
	if withAt < 0 {
		t.Fatalf("job %q has no `with:` mapping", job)
	}

	out := map[string]string{}
	inputIndent := -1
	for _, l := range lines[withAt+1:] {
		if l.indent <= lines[withAt].indent {
			break
		}
		if inputIndent < 0 {
			inputIndent = l.indent
		}
		if l.indent != inputIndent {
			t.Fatalf("job %q: `with:` input at line %d is nested deeper than its siblings — this reader handles scalar inputs only", job, l.num)
		}
		if l.key == "" {
			t.Fatalf("job %q: unexpected non-mapping line %d inside `with:` (%q)", job, l.num, l.value)
		}
		if l.value == "<block-scalar>" {
			t.Fatalf("job %q: input %q is a block scalar — this reader handles single-line scalars only", job, l.key)
		}
		out[l.key] = unquote(l.value)
	}
	if len(out) == 0 {
		t.Fatalf("job %q has an empty `with:` mapping — the reader or the file layout drifted", job)
	}
	return out
}

func unquote(v string) string {
	if len(v) >= 2 && (v[0] == '"' && v[len(v)-1] == '"' || v[0] == '\'' && v[len(v)-1] == '\'') {
		return v[1 : len(v)-1]
	}
	return v
}

func sortedKeys(m map[string]string) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// mustRead reads a workspace file relative to this package's directory.
//
// The same relative path works in both worlds: rules_go runs the test from its
// own package dir inside the runfiles tree (where the BUILD `data` attr puts
// these two files), and `GOWORK=off go test ./...` runs it from the checkout.
// A missing file is a HARD FAILURE, never a skip: a parity guard that quietly
// skips is indistinguishable from one that passes.
func mustRead(t *testing.T, rel string) string {
	t.Helper()
	b, err := os.ReadFile(rel)
	if err != nil {
		abs, _ := filepath.Abs(rel)
		t.Fatalf("cannot read %s (%s): %v — under `bazel test` it must be listed in the go_test's `data`, and the root BUILD must export it", rel, abs, err)
	}
	if len(b) == 0 {
		t.Fatalf("%s is empty", rel)
	}
	return string(b)
}

// ---------------------------------------------------------------------------
// the build job: transcription, asserted text-for-text
// ---------------------------------------------------------------------------

// buildJobDiffAllowlist names the job-level keys that Phase 1 intends to differ
// between the hand-written `build` job and the generated `<unit>-build` job.
// Everything NOT listed here — every step, every permission, the environment,
// the env map, the outputs map, runs-on, timeout-minutes — must match exactly.
var buildJobDiffAllowlist = map[string]string{
	"needs": "legacy waits on its `gate` job; the generated one waits on `orchestrate`",
	"if":    "legacy carries the release/dispatch arms of the promotion ladder, which stays legacy in Phase 1; the generated one carries the kill switch and the orchestrator's verdict",
}

// TestGeneratedBuildJobMatchesLegacy is the transcription guard for the half of
// Phase 1 that is NOT a thin caller layer.
//
// PROVES: the generated build job is the hand-written one — same checkout, same
// WIF auth composite with the same inputs, the same SHA-pinned Cloud SDK
// action, the same docker configure, and a byte-identical buildx + digest-
// capture script — rather than a re-derivation of it. The steps are compared as
// TEXT because that is the only comparison that catches a changed flag, a
// dropped `--push`, a different tag, or a digest capture that stops writing
// $GITHUB_OUTPUT. A build job that merely "looks right" is how an app ships an
// image nobody deploys.
func TestGeneratedBuildJobMatchesLegacy(t *testing.T) {
	legacySrc := mustRead(t, legacyWorkflowRel)
	genSrc := mustRead(t, deliveryWorkflowRel)

	wantSteps := normalizedSteps(t, legacySrc, legacyBuildJob)
	gotSteps := normalizedSteps(t, genSrc, genBuildJob)

	if len(gotSteps) != len(wantSteps) {
		t.Fatalf("%s renders %d steps, legacy %s has %d:\n--- generated ---\n%s\n--- legacy ---\n%s",
			genBuildJob, len(gotSteps), legacyBuildJob, len(wantSteps),
			strings.Join(gotSteps, "\n"), strings.Join(wantSteps, "\n"))
	}
	for i := range wantSteps {
		if gotSteps[i] != wantSteps[i] {
			t.Errorf("build step %d differs from legacy %s:\n--- generated ---\n%s\n--- legacy ---\n%s",
				i+1, legacyBuildJob, gotSteps[i], wantSteps[i])
		}
	}

	legacy := parseWorkflow(t, legacySrc)
	generated := parseWorkflow(t, genSrc)

	for _, key := range []string{"runs-on", "timeout-minutes", "environment"} {
		want := jobScalar(t, legacy, legacyBuildJob, key)
		got := jobScalar(t, generated, genBuildJob, key)
		if got != want {
			t.Errorf("%s %s = %q, legacy %s = %q", genBuildJob, key, got, legacyBuildJob, want)
		}
	}
	for _, key := range []string{"permissions", "env", "outputs"} {
		want := jobSubMap(t, legacy, legacyBuildJob, key)
		got := jobSubMap(t, generated, genBuildJob, key)
		if len(got) != len(want) {
			t.Errorf("%s %s has keys %v, legacy %s has %v", genBuildJob, key, sortedKeys(got), legacyBuildJob, sortedKeys(want))
		}
		for _, k := range sortedKeys(want) {
			if got[k] != want[k] {
				t.Errorf("%s %s.%s = %q, legacy %s = %q", genBuildJob, key, k, got[k], legacyBuildJob, want[k])
			}
		}
	}

	// The two keys that ARE allowed to differ must still both exist — a build
	// job with no `if:` would run on every push, which is #1794's shape.
	for key, why := range buildJobDiffAllowlist {
		if got := jobScalar(t, generated, genBuildJob, key); got == "" {
			t.Errorf("%s has no %q (allowlisted as different from legacy: %s) — different is not absent", genBuildJob, key, why)
		}
	}
}

// TestGeneratedDeployConsumesTheGeneratedBuild closes the loop between them.
//
// PROVES: the deploy reads the digest from the job that produced it, waits for
// that job, and refuses to run unless it SUCCEEDED. `== 'success'` and not
// `!= 'failure'`: a SKIPPED build means no image was pushed for this commit, and
// deploying then would silently promote whatever digest the registry's `latest`
// happens to hold.
func TestGeneratedDeployConsumesTheGeneratedBuild(t *testing.T) {
	generated := parseWorkflow(t, mustRead(t, deliveryWorkflowRel))

	digest := jobWith(t, generated, genDeployJob)["image-digest"]
	want := "${{ needs." + genBuildJob + ".outputs.image-digest }}"
	if digest != want {
		t.Errorf("%s passes image-digest=%q, want %q", genDeployJob, digest, want)
	}
	needs := jobScalar(t, generated, genDeployJob, "needs")
	if !strings.Contains(needs, genBuildJob) {
		t.Errorf("%s needs = %q, which does not include %q — it would read an output from a job it never waited for", genDeployJob, needs, genBuildJob)
	}
	cond := jobScalar(t, generated, genDeployJob, "if")
	if !strings.Contains(cond, "needs."+genBuildJob+".result == 'success'") {
		t.Errorf("%s `if:` does not require the build to have SUCCEEDED: %s", genDeployJob, cond)
	}

	// ...and the build job must actually export the digest, or every reader of
	// it resolves to "" and the deploy runs with an empty image ref.
	outs := jobSubMap(t, generated, genBuildJob, "outputs")
	if outs["image-digest"] == "" {
		t.Errorf("%s declares no image-digest output (declares %v)", genBuildJob, sortedKeys(outs))
	}
}

// TestPromotionSoakGateScansTheGeneratedDevLane is the follow-up the trigger
// removal created.
//
// PROVES: the legacy workflow's promotion interlock still watches a real
// development deploy. It scans a workflow's push-run history for a named job;
// with `push:` removed from the legacy workflow, that history is now empty, and
// require-dev-soak.sh treats "no run found" as INDETERMINATE and fail-opens —
// so the gate would look present and enforce nothing, which its own header
// calls worse than no gate. The expected job name is DERIVED here (caller job
// id + the callee's job id, which is how GitHub names a reusable-workflow
// check) rather than hardcoded, so renaming either end fails this test instead
// of silently disarming the interlock.
func TestPromotionSoakGateScansTheGeneratedDevLane(t *testing.T) {
	legacy := parseWorkflow(t, mustRead(t, legacyWorkflowRel))
	env := jobEnvMap(t, legacy, "require-dev-soak")

	if got, want := env["WORKFLOW_FILE"], "delivery.yaml"; got != want {
		t.Errorf("require-dev-soak scans WORKFLOW_FILE=%q, want %q — the development deploy now lives in the generated workflow, and scanning the legacy one finds no push runs at all (the script then fail-opens with a warning)", got, want)
	}

	callees := jobIDsOf(t, parseWorkflow(t, mustRead(t, deployCloudRunRel)))
	if len(callees) != 1 {
		t.Fatalf("_deploy-cloud-run.yaml declares %v jobs; the check-run name is \"<caller> / <callee>\" and this test assumes exactly one callee", callees)
	}
	want := genDeployJob + " / " + callees[0]
	if got := env["DEV_JOB_NAME"]; got != want {
		t.Errorf("require-dev-soak looks for DEV_JOB_NAME=%q, want %q (the generated caller job id + the reusable workflow's job id, which is how GitHub names the check) — a name that matches nothing makes the gate fail-open forever", got, want)
	}
}

// ---------------------------------------------------------------------------
// reader extensions
// ---------------------------------------------------------------------------

// normalizedSteps returns one entry per step of a job: the step's raw YAML,
// de-indented to a common origin, with comment-only lines and blank lines
// removed.
//
// Text, not structure, is the point — see TestGeneratedBuildJobMatchesLegacy.
// Comments and blank lines are dropped from BOTH sides because they carry no
// runtime meaning and the two files format them differently (the legacy job
// separates steps with blank lines; a generator that emitted them would be
// formatting for a diff nobody reads).
func normalizedSteps(t *testing.T, src, job string) []string {
	t.Helper()
	lines := parseWorkflow(t, src)
	start := indexOfJob(t, lines, job)
	stepsLine := -1
	parent := lines[start].indent
	child := -1
	for i := start + 1; i < len(lines); i++ {
		if lines[i].indent <= parent {
			break
		}
		if child < 0 {
			child = lines[i].indent
		}
		if lines[i].indent == child && lines[i].key == "steps" {
			stepsLine = lines[i].num
			break
		}
	}
	if stepsLine < 0 {
		t.Fatalf("job %q has no `steps:`", job)
	}

	raw := strings.Split(src, "\n")
	// stepsLine is 1-based; collect the raw lines below it that are indented
	// deeper than `steps:` itself.
	stepsIndent := indentOf(raw[stepsLine-1])
	var body []string
	for i := stepsLine; i < len(raw); i++ {
		line := strings.TrimRight(raw[i], " \r")
		if strings.TrimSpace(line) == "" {
			continue
		}
		if strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		if indentOf(line) <= stepsIndent {
			break
		}
		body = append(body, line)
	}
	if len(body) == 0 {
		t.Fatalf("job %q has an empty `steps:` block", job)
	}

	itemIndent := indentOf(body[0])
	var steps []string
	var cur []string
	for _, line := range body {
		if indentOf(line) == itemIndent && strings.HasPrefix(strings.TrimSpace(line), "- ") {
			if len(cur) > 0 {
				steps = append(steps, strings.Join(cur, "\n"))
				cur = nil
			}
		}
		cur = append(cur, line[itemIndent:])
	}
	if len(cur) > 0 {
		steps = append(steps, strings.Join(cur, "\n"))
	}
	return steps
}

func indentOf(line string) int {
	return len(line) - len(strings.TrimLeft(line, " "))
}

// jobSubMap reads a mapping nested one level inside a job (permissions, env,
// outputs) as key -> raw scalar.
func jobSubMap(t *testing.T, lines []wfLine, job, key string) map[string]string {
	t.Helper()
	start := indexOfJob(t, lines, job)
	parent := lines[start].indent
	child := -1
	at := -1
	for i := start + 1; i < len(lines); i++ {
		if lines[i].indent <= parent {
			break
		}
		if child < 0 {
			child = lines[i].indent
		}
		if lines[i].indent == child && lines[i].key == key {
			at = i
			break
		}
	}
	if at < 0 {
		t.Fatalf("job %q has no %q mapping", job, key)
	}
	out := map[string]string{}
	inner := -1
	for _, l := range lines[at+1:] {
		if l.indent <= lines[at].indent {
			break
		}
		if inner < 0 {
			inner = l.indent
		}
		if l.indent == inner && l.key != "" {
			out[l.key] = unquote(l.value)
		}
	}
	return out
}

// jobEnvMap merges every `env:` mapping inside a job (job-level and per-step).
func jobEnvMap(t *testing.T, lines []wfLine, job string) map[string]string {
	t.Helper()
	start := indexOfJob(t, lines, job)
	parent := lines[start].indent
	out := map[string]string{}
	for i := start + 1; i < len(lines); i++ {
		if lines[i].indent <= parent {
			break
		}
		if lines[i].key != "env" {
			continue
		}
		inner := -1
		for _, l := range lines[i+1:] {
			if l.indent <= lines[i].indent {
				break
			}
			if inner < 0 {
				inner = l.indent
			}
			if l.indent == inner && l.key != "" {
				out[l.key] = unquote(l.value)
			}
		}
	}
	if len(out) == 0 {
		t.Fatalf("job %q declares no env: mapping", job)
	}
	return out
}

// jobIDsOf returns every job id declared under a workflow's `jobs:` key.
func jobIDsOf(t *testing.T, lines []wfLine) []string {
	t.Helper()
	jobs := indexOfTopLevel(lines, "jobs")
	if jobs < 0 {
		t.Fatal("no top-level `jobs:` key in the workflow")
	}
	return childKeys(lines, jobs)
}
