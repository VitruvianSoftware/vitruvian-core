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

	// PHASE 2 adds tabula: two units off ONE shared build, both promoting on
	// their own release tag. Same discipline, second app — the legacy file is
	// read live, never copied, so the two cannot drift apart while this stays
	// green.
	legacyTabulaWorkflowRel = "../../../.github/workflows/tabula-deploy.yaml"
	changelogWorkflowRel    = "../../../.github/workflows/_changelog-summary.yaml"

	legacyTabulaBuildJob = "build"
	genTabulaBuildJob    = "tabula-build"
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

// TestGeneratedCompanionMatchesLegacy does the same for the expand half, on
// EVERY rung.
//
// PROVES: each generated companion calls _zitadel-apps-apply.yaml with exactly
// the legacy zitadel-{dev,nonprod,prod} inputs — no allowlist at all, because
// nothing about a companion is supposed to change — and keeps the two clauses
// that make it safe: the ZITADEL_APPS_AUTO_APPLY variable gate (without it the
// apply FAILS the deploy instead of cleanly no-opping while the machine key is
// unseeded) and, for the production rung, the chain behind nonproduction's
// deploy. Expanding a rung that is not about to be served is #1794's shape
// against a stack whose force-replace deletes the live OIDC client.
func TestGeneratedCompanionMatchesLegacy(t *testing.T) {
	legacy := parseWorkflow(t, mustRead(t, legacyWorkflowRel))
	generated := parseWorkflow(t, mustRead(t, deliveryWorkflowRel))

	for _, tc := range []struct {
		legacyJob, genJob, env, chainedBehind string
	}{
		{"zitadel-dev", "zitadel-apps-development", "development", ""},
		{"zitadel-nonprod", "zitadel-apps-nonproduction", "nonproduction", ""},
		{"zitadel-prod", "zitadel-apps-production", "production", "oauth-user-inspector-nonproduction"},
	} {
		t.Run(tc.genJob, func(t *testing.T) {
			legacyWith := jobWith(t, legacy, tc.legacyJob)
			if got := legacyWith["environment"]; got != tc.env {
				t.Fatalf("legacy %s applies environment=%q, want %q — comparing the wrong job", tc.legacyJob, got, tc.env)
			}
			genWith := jobWith(t, generated, tc.genJob)
			if got := genWith["environment"]; got != tc.env {
				t.Errorf("%s applies environment=%q, want %q", tc.genJob, got, tc.env)
			}
			want := jobScalar(t, legacy, tc.legacyJob, "uses")
			if got := jobScalar(t, generated, tc.genJob, "uses"); got != want {
				t.Errorf("%s calls %q but legacy %s calls %q", tc.genJob, got, tc.legacyJob, want)
			}
			assertMapsMatch(t, tc.legacyJob, legacyWith, tc.genJob, genWith, nil)

			cond := jobScalar(t, generated, tc.genJob, "if")
			if !strings.Contains(cond, "vars.ZITADEL_APPS_AUTO_APPLY == 'true'") {
				t.Errorf("%s lost the ZITADEL_APPS_AUTO_APPLY gate — the apply would FAIL the deploy instead of cleanly no-opping: %s", tc.genJob, cond)
			}
			if tc.chainedBehind != "" {
				if !strings.Contains(cond, "needs."+tc.chainedBehind+".result == 'success'") {
					t.Errorf("%s does not chain behind %s (legacy zitadel-prod needs deploy-nonprod): %s", tc.genJob, tc.chainedBehind, cond)
				}
				if needs := jobScalar(t, generated, tc.genJob, "needs"); !strings.Contains(needs, tc.chainedBehind) {
					t.Errorf("%s needs = %q, which does not include %q — the condition reads a job it never waited for", tc.genJob, needs, tc.chainedBehind)
				}
			}
		})
	}
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

// TestLegacyWorkflowsAreDispatchOnlyShells is the Phase-2 legacy-surgery
// assertion, for BOTH migrated apps.
//
// PROVES: neither legacy workflow can still deliver by itself. `push:` and
// `release:` are gone — with either in place both files would deliver the same
// environment from the same event, racing two `pulumi up`s on one stack and
// one shared Artifact Registry — while `workflow_dispatch:` survives as the
// break-glass escape hatch until Phase 3 deletes the files (spec §6).
func TestLegacyWorkflowsAreDispatchOnlyShells(t *testing.T) {
	for _, rel := range []string{legacyWorkflowRel, legacyTabulaWorkflowRel} {
		triggers := topLevelChildKeys(t, parseWorkflow(t, mustRead(t, rel)), "on")
		for _, gone := range []string{"push", "release"} {
			if contains(triggers, gone) {
				t.Errorf("%s still triggers on %q — the generated delivery.yaml owns that lane now, so BOTH would deliver the same environment from one event (triggers: %v)", rel, gone, triggers)
			}
		}
		if !contains(triggers, "workflow_dispatch") {
			t.Errorf("%s lost its workflow_dispatch trigger — that is the break-glass escape hatch Phase 2 keeps until Phase 3 deletes the file (triggers: %v)", rel, triggers)
		}
		if len(triggers) != 1 {
			t.Errorf("%s declares triggers %v — a dispatch-only shell has exactly one", rel, triggers)
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

// ---------------------------------------------------------------------------
// PHASE 2 — the shared build, the promotion ladder, the interlocks
// ---------------------------------------------------------------------------

// TestGeneratedSharedBuildJobMatchesLegacy is the transcription guard for the
// one job Phase 2 could not express as a thin caller layer.
//
// PROVES: `tabula-build` IS tabula-deploy.yaml's `build` job — the same
// checkout, the same Bazel setup, the same WIF composite, the same SHA-pinned
// Cloud SDK, the same `bazel run //tabula/api:image_push` with its remote-cache
// header, the same buildx setup and the same `docker build`/`docker push`/
// `docker inspect` digest capture — rather than a re-derivation of it. Compared
// as TEXT, because that is the only comparison that catches a dropped `--push`,
// a changed tag, a digest read back from the mutable `:latest` (the race that
// can hand one run another run's digest), or a capture that stops writing
// $GITHUB_OUTPUT. Two images, two digest idioms: a build job that merely "looks
// right" here ships an image nobody deploys, or deploys an image nobody built.
func TestGeneratedSharedBuildJobMatchesLegacy(t *testing.T) {
	legacySrc := mustRead(t, legacyTabulaWorkflowRel)
	genSrc := mustRead(t, deliveryWorkflowRel)

	wantSteps := normalizedSteps(t, legacySrc, legacyTabulaBuildJob)
	gotSteps := normalizedSteps(t, genSrc, genTabulaBuildJob)

	if len(wantSteps) != 8 {
		t.Fatalf("legacy %s has %d steps; this guard was written against its 8 (checkout, setup-bazel, gcp-auth, gcloud, docker login, api image, buildx, web image) — re-read the job before relaxing it", legacyTabulaBuildJob, len(wantSteps))
	}
	if len(gotSteps) != len(wantSteps) {
		t.Fatalf("%s renders %d steps, legacy %s has %d:\n--- generated ---\n%s\n--- legacy ---\n%s",
			genTabulaBuildJob, len(gotSteps), legacyTabulaBuildJob, len(wantSteps),
			strings.Join(gotSteps, "\n"), strings.Join(wantSteps, "\n"))
	}
	for i := range wantSteps {
		if gotSteps[i] != wantSteps[i] {
			t.Errorf("shared build step %d differs from legacy %s:\n--- generated ---\n%s\n--- legacy ---\n%s",
				i+1, legacyTabulaBuildJob, gotSteps[i], wantSteps[i])
		}
	}

	legacy := parseWorkflow(t, legacySrc)
	generated := parseWorkflow(t, genSrc)

	for _, key := range []string{"runs-on", "timeout-minutes", "environment"} {
		want := jobScalar(t, legacy, legacyTabulaBuildJob, key)
		got := jobScalar(t, generated, genTabulaBuildJob, key)
		if got != want {
			t.Errorf("%s %s = %q, legacy %s = %q", genTabulaBuildJob, key, got, legacyTabulaBuildJob, want)
		}
	}
	for _, key := range []string{"permissions", "env", "outputs"} {
		want := jobSubMap(t, legacy, legacyTabulaBuildJob, key)
		got := jobSubMap(t, generated, genTabulaBuildJob, key)
		if len(got) != len(want) {
			t.Errorf("%s %s has keys %v, legacy %s has %v", genTabulaBuildJob, key, sortedKeys(got), legacyTabulaBuildJob, sortedKeys(want))
		}
		for _, k := range sortedKeys(want) {
			if got[k] != want[k] {
				t.Errorf("%s %s.%s = %q, legacy %s = %q", genTabulaBuildJob, key, k, got[k], legacyTabulaBuildJob, want[k])
			}
		}
	}
	for key, why := range buildJobDiffAllowlist {
		if got := jobScalar(t, generated, genTabulaBuildJob, key); got == "" {
			t.Errorf("%s has no %q (allowlisted as different from legacy: %s) — different is not absent", genTabulaBuildJob, key, why)
		}
	}
}

// rungParity is one legacy job and the generated job that replaced it.
type rungParity struct {
	legacyJob string
	genJob    string
	env       string
	// digestFrom is the legacy `needs.<job>.` prefix the generated one
	// rewrites — the ONE sanctioned value difference, exactly as Phase 1's.
	digestFrom string
	digestTo   string
}

// TestGeneratedLadderMatchesLegacy walks EVERY rung of both migrated apps.
//
// PROVES: no rung's `with:` map drifted in transcription — not the project, the
// stack dir, the region, the service, the secret prefix, the refresh flag, the
// migration flag, the smoke path or the Cloudflare token project — in either
// direction, on any of the eight jobs Phase 2 moved. The only sanctioned
// difference per job is where the image digest comes from (the generated build
// job instead of the hand-written one) plus `environment`, which the ladder
// supplies and which is asserted explicitly below: a rung pointed at the wrong
// environment would promote production from a nonproduction trigger.
func TestGeneratedLadderMatchesLegacy(t *testing.T) {
	generated := parseWorkflow(t, mustRead(t, deliveryWorkflowRel))

	for _, tc := range []struct {
		legacyFile string
		rungs      []rungParity
	}{
		{
			legacyFile: legacyWorkflowRel,
			rungs: []rungParity{
				{"deploy-nonprod", "oauth-user-inspector-nonproduction", "nonproduction", "needs.build.", "needs.oauth-user-inspector-build."},
				{"deploy-prod", "oauth-user-inspector-production", "production", "needs.build.", "needs.oauth-user-inspector-build."},
			},
		},
		{
			legacyFile: legacyTabulaWorkflowRel,
			rungs: []rungParity{
				{"deploy-dev-api", "tabula-api-development", "development", "needs.build.", "needs.tabula-build."},
				{"deploy-dev-web", "tabula-web-development", "development", "needs.build.", "needs.tabula-build."},
				{"deploy-nonprod-api", "tabula-api-nonproduction", "nonproduction", "needs.build.", "needs.tabula-build."},
				{"deploy-nonprod-web", "tabula-web-nonproduction", "nonproduction", "needs.build.", "needs.tabula-build."},
				{"deploy-prod-api", "tabula-api-production", "production", "needs.build.", "needs.tabula-build."},
				{"deploy-prod-web", "tabula-web-production", "production", "needs.build.", "needs.tabula-build."},
			},
		},
	} {
		legacy := parseWorkflow(t, mustRead(t, tc.legacyFile))
		for _, r := range tc.rungs {
			t.Run(r.genJob, func(t *testing.T) {
				legacyWith := jobWith(t, legacy, r.legacyJob)
				genWith := jobWith(t, generated, r.genJob)

				if got := legacyWith["environment"]; got != r.env {
					t.Fatalf("legacy %s deploys environment=%q, want %q — this test is comparing the wrong job", r.legacyJob, got, r.env)
				}
				if got := genWith["environment"]; got != r.env {
					t.Errorf("%s deploys environment=%q, want %q", r.genJob, got, r.env)
				}
				// Same reusable workflow, or the maps agreeing proves nothing.
				want := jobScalar(t, legacy, r.legacyJob, "uses")
				if got := jobScalar(t, generated, r.genJob, "uses"); got != want {
					t.Errorf("%s calls %q but legacy %s calls %q", r.genJob, got, r.legacyJob, want)
				}
				assertMapsMatch(t, r.legacyJob, legacyWith, r.genJob, genWith, map[string]inputRewrite{
					"image-digest": {from: r.digestFrom, to: r.digestTo, why: "same build-once digest, produced by the generated build job instead of the hand-written one"},
				})
			})
		}
	}
}

// TestSharedBuildFeedsEachUnitItsOwnDigest closes the loop the shared build
// opens: one job, two outputs, two consumers that must not swap them.
//
// PROVES: tabula-api deploys the API image and tabula-web the web image, on
// EVERY rung, read from the shared job by the exact output names that job
// declares. GitHub resolves an unknown `needs.<job>.outputs.<name>` to the
// EMPTY STRING rather than erroring, so a swapped or mistyped output is not a
// red run — it is tabula-web serving the API image, or a rollout with no image
// ref at all, discovered in production.
func TestSharedBuildFeedsEachUnitItsOwnDigest(t *testing.T) {
	generated := parseWorkflow(t, mustRead(t, deliveryWorkflowRel))

	declared := jobSubMap(t, generated, genTabulaBuildJob, "outputs")
	for _, want := range []string{"image-digest", "web-image-digest"} {
		if declared[want] == "" {
			t.Fatalf("%s declares no %q output (declares %v) — every reader of it resolves to \"\"", genTabulaBuildJob, want, sortedKeys(declared))
		}
	}

	for _, tc := range []struct{ job, output string }{
		{"tabula-api-development", "image-digest"},
		{"tabula-api-nonproduction", "image-digest"},
		{"tabula-api-production", "image-digest"},
		{"tabula-web-development", "web-image-digest"},
		{"tabula-web-nonproduction", "web-image-digest"},
		{"tabula-web-production", "web-image-digest"},
	} {
		want := "${{ needs." + genTabulaBuildJob + ".outputs." + tc.output + " }}"
		if got := jobWith(t, generated, tc.job)["image-digest"]; got != want {
			t.Errorf("%s passes image-digest=%q, want %q", tc.job, got, want)
		}
		needs := jobScalar(t, generated, tc.job, "needs")
		if !strings.Contains(needs, genTabulaBuildJob) {
			t.Errorf("%s needs = %q, which does not include %q — it would read an output from a job it never waited for", tc.job, needs, genTabulaBuildJob)
		}
		if !strings.Contains(jobScalar(t, generated, tc.job, "if"), "needs."+genTabulaBuildJob+".result == 'success'") {
			t.Errorf("%s `if:` does not require the shared build to have SUCCEEDED", tc.job)
		}
	}
}

// TestGeneratedSoakJobsMatchLegacy is the interlock's transcription guard.
//
// PROVES: every generated `<unit>-require-dev-soak` runs the same script with
// the same token, the same override variable and a DERIVED job name — and
// carries `actions: read` on an ORDINARY job, never on a `uses:` caller (that
// combination makes GitHub reject the entire workflow at startup with no jobs
// instantiated, bisected four times on tabula-deploy.yaml). The expected
// DEV_JOB_NAME is composed here from the generated caller id + the reusable
// workflow's own job id, which is how GitHub names the check — so renaming
// either end fails this test instead of silently disarming the gate, which
// fail-opens on a name that matches nothing.
func TestGeneratedSoakJobsMatchLegacy(t *testing.T) {
	generated := parseWorkflow(t, mustRead(t, deliveryWorkflowRel))

	callees := jobIDsOf(t, parseWorkflow(t, mustRead(t, deployCloudRunRel)))
	if len(callees) != 1 {
		t.Fatalf("_deploy-cloud-run.yaml declares %v jobs; the check-run name is \"<caller> / <callee>\" and this test assumes exactly one callee", callees)
	}

	for _, tc := range []struct{ job, devJob string }{
		{"oauth-user-inspector-require-dev-soak", "oauth-user-inspector-development"},
		{"tabula-api-require-dev-soak", "tabula-api-development"},
		{"tabula-web-require-dev-soak", "tabula-web-development"},
	} {
		t.Run(tc.job, func(t *testing.T) {
			env := jobEnvMap(t, generated, tc.job)
			if got, want := env["DEV_JOB_NAME"], tc.devJob+" / "+callees[0]; got != want {
				t.Errorf("%s scans DEV_JOB_NAME=%q, want %q — a name that matches nothing makes the gate fail-open forever", tc.job, got, want)
			}
			if got, want := env["WORKFLOW_FILE"], "delivery.yaml"; got != want {
				t.Errorf("%s scans WORKFLOW_FILE=%q, want %q", tc.job, got, want)
			}
			if env["GH_TOKEN"] == "" {
				t.Errorf("%s passes no GH_TOKEN — every `gh` call fails and the gate fail-opens", tc.job)
			}
			if !strings.Contains(env["ALLOW_UNSOAKED"], "inputs.allow-unsoaked") {
				t.Errorf("%s ALLOW_UNSOAKED=%q does not read the dispatch input — the documented break-glass override would be unreachable from the run page", tc.job, env["ALLOW_UNSOAKED"])
			}
			perms := jobSubMap(t, generated, tc.job, "permissions")
			if perms["actions"] != "read" {
				t.Errorf("%s permissions = %v, want actions: read (the script's `gh run list` needs it)", tc.job, perms)
			}
			block, ok := jobText(mustRead(t, deliveryWorkflowRel), tc.job)
			if !ok {
				t.Fatalf("cannot isolate %s", tc.job)
			}
			if strings.Contains(block, "    uses:") {
				t.Errorf("%s is a reusable-workflow caller AND grants `actions: read` — that combination makes GitHub reject the whole workflow at startup with no jobs instantiated", tc.job)
			}
			if !strings.Contains(block, "run: ./tools/ci/require-dev-soak.sh") {
				t.Errorf("%s does not run tools/ci/require-dev-soak.sh:\n%s", tc.job, block)
			}
		})
	}

	// Legacy's soak jobs are the source; assert the generated ones run the
	// SAME script, so a future rewrite of one is not silently a fork.
	for _, tc := range []struct{ file, job string }{
		{legacyWorkflowRel, "require-dev-soak"},
		{legacyTabulaWorkflowRel, "require-dev-soak-api"},
		{legacyTabulaWorkflowRel, "require-dev-soak-web"},
	} {
		block, ok := jobText(mustRead(t, tc.file), tc.job)
		if !ok {
			t.Fatalf("cannot isolate legacy %s in %s", tc.job, tc.file)
		}
		if !strings.Contains(block, "run: ./tools/ci/require-dev-soak.sh") {
			t.Errorf("legacy %s no longer runs require-dev-soak.sh — the generated jobs were transcribed from it", tc.job)
		}
	}
}

// TestTabulaSoakGatesScanTheGeneratedDevLanes is the follow-up tabula's trigger
// removal created — the same repoint Phase 1 made for oauth.
//
// PROVES: the LEGACY workflow's interlocks still watch a real development
// deploy. They scan a workflow's push-run history for a named job; with `push:`
// removed from tabula-deploy.yaml that history is now empty, and
// require-dev-soak.sh treats "no run found" as INDETERMINATE and fail-opens —
// so the gate would look present and enforce nothing on the dispatch path that
// is still reachable until Phase 3 deletes the file.
func TestTabulaSoakGatesScanTheGeneratedDevLanes(t *testing.T) {
	legacy := parseWorkflow(t, mustRead(t, legacyTabulaWorkflowRel))
	callees := jobIDsOf(t, parseWorkflow(t, mustRead(t, deployCloudRunRel)))
	if len(callees) != 1 {
		t.Fatalf("_deploy-cloud-run.yaml declares %v jobs; this test assumes exactly one callee", callees)
	}

	for _, tc := range []struct{ job, devJob string }{
		{"require-dev-soak-api", "tabula-api-development"},
		{"require-dev-soak-web", "tabula-web-development"},
	} {
		env := jobEnvMap(t, legacy, tc.job)
		if got, want := env["WORKFLOW_FILE"], "delivery.yaml"; got != want {
			t.Errorf("legacy %s scans WORKFLOW_FILE=%q, want %q — the development deploy now lives in the generated workflow, and scanning this one finds no push runs at all (the script then fail-opens with a warning)", tc.job, got, want)
		}
		if got, want := env["DEV_JOB_NAME"], tc.devJob+" / "+callees[0]; got != want {
			t.Errorf("legacy %s looks for DEV_JOB_NAME=%q, want %q", tc.job, got, want)
		}
	}
}

// TestGeneratedChangelogJobMatchesLegacy closes the Phase-1 deferred flag.
//
// PROVES: the generated changelog job calls the same reusable workflow with the
// same inputs as tabula-deploy.yaml's, and passes no secrets it was not passed
// before. The one sanctioned difference is the added `if:` — legacy carried
// none, which was harmless in a per-app workflow and is not here: with a
// repo-wide `release:` trigger an unconditional job runs on EVERY published
// release of every unrelated component.
func TestGeneratedChangelogJobMatchesLegacy(t *testing.T) {
	legacy := parseWorkflow(t, mustRead(t, legacyTabulaWorkflowRel))
	generated := parseWorkflow(t, mustRead(t, deliveryWorkflowRel))

	want := jobScalar(t, legacy, "changelog", "uses")
	if got := jobScalar(t, generated, "tabula-api-changelog", "uses"); got != want {
		t.Errorf("tabula-api-changelog calls %q, legacy changelog calls %q", got, want)
	}
	assertMapsMatch(t, "changelog", jobWith(t, legacy, "changelog"),
		"tabula-api-changelog", jobWith(t, generated, "tabula-api-changelog"), nil)

	// The callee must actually declare the inputs being passed, or the run
	// fails at startup with "invalid input".
	declared := workflowCallInputs(t, parseWorkflow(t, mustRead(t, changelogWorkflowRel)))
	for k := range jobWith(t, generated, "tabula-api-changelog") {
		if !contains(declared, k) {
			t.Errorf("tabula-api-changelog passes %q, which %s does not declare as a workflow_call input (declares %v)", k, changelogWorkflowRel, declared)
		}
	}

	cond := jobScalar(t, generated, "tabula-api-changelog", "if")
	if !strings.Contains(cond, "github.event_name == 'push'") {
		t.Errorf("tabula-api-changelog `if:` = %q — without a push key it renders on every unrelated component's release", cond)
	}
}

// workflowCallInputs returns the input names a reusable workflow declares.
func workflowCallInputs(t *testing.T, lines []wfLine) []string {
	t.Helper()
	on := indexOfTopLevel(lines, "on")
	if on < 0 {
		t.Fatal("no top-level `on:` key")
	}
	for i := on + 1; i < len(lines); i++ {
		if lines[i].indent == 0 {
			break
		}
		if lines[i].key == "inputs" {
			return childKeys(lines, i)
		}
	}
	t.Fatal("no workflow_call inputs found")
	return nil
}

// releaseHoldRel is the FAST half of the dev→nonproduction interlock: it holds
// a component's open release PR out of auto-merge while that component's
// development deploy is red. (require-dev-soak.sh, asserted above, is the slow
// half — it blocks the promotion itself.)
const releaseHoldRel = "../../../.github/workflows/release-hold.yaml"

// TestReleaseHoldWatchesTheGeneratedDevLanes.
//
// PROVES: the release-PR hold still fires. It is a `workflow_run` consumer,
// keyed on the deploy workflow's NAME and on job names inside that run — so
// moving a development deploy into the generated workflow silently disarms it
// twice over: the trigger never fires again, and the job it looks for is not
// called that any more. Nothing goes red when that happens; the interlock just
// stops existing, which is how it was found dead after Phase 1 moved oauth's
// lane. Both halves are DERIVED here from the real files, so a rename fails
// this test instead of quietly removing the guard.
func TestReleaseHoldWatchesTheGeneratedDevLanes(t *testing.T) {
	hold := parseWorkflow(t, mustRead(t, releaseHoldRel))
	generated := parseWorkflow(t, mustRead(t, deliveryWorkflowRel))
	genSrc := mustRead(t, deliveryWorkflowRel)

	// 1. It must watch the workflow the development deploys now live in.
	watched := ""
	for _, l := range hold {
		if l.key == "workflows" {
			watched = l.value
		}
	}
	wantName := ""
	for _, l := range generated {
		if l.indent == 0 && l.key == "name" {
			wantName = l.value
		}
	}
	if wantName == "" {
		t.Fatal("the generated workflow declares no top-level `name:`")
	}
	if !strings.Contains(watched, wantName) {
		t.Errorf("release-hold.yaml watches workflows: %s, which does not include %q — the workflow_run trigger would never fire and the hold would silently stop existing", watched, wantName)
	}

	// 2. Every job name in its matrix must be a real check-run name of the
	//    generated workflow: "<caller job id> / <callee job id>".
	callees := jobIDsOf(t, parseWorkflow(t, mustRead(t, deployCloudRunRel)))
	if len(callees) != 1 {
		t.Fatalf("_deploy-cloud-run.yaml declares %v jobs; this test assumes exactly one callee", callees)
	}
	genJobs := jobIDsOf(t, generated)
	covered := map[string]bool{}
	for _, l := range hold {
		if l.key != "dev_job" {
			continue
		}
		caller, callee, ok := strings.Cut(unquote(l.value), " / ")
		if !ok {
			t.Errorf("release-hold.yaml dev_job %q is not a \"<caller> / <callee>\" check-run name", l.value)
			continue
		}
		if callee != callees[0] {
			t.Errorf("release-hold.yaml dev_job %q names callee %q, but %s declares %q", l.value, callee, deployCloudRunRel, callees[0])
		}
		if !contains(genJobs, caller) {
			t.Errorf("release-hold.yaml dev_job %q names caller job %q, which the generated workflow does not declare (declares %v) — the lookup finds nothing and every release PR sails through unheld", l.value, caller, genJobs)
			continue
		}
		covered[caller] = true
	}
	if len(covered) == 0 {
		t.Fatal("release-hold.yaml declares no dev_job entries — the parser or the file layout drifted")
	}

	// 3. ...and it must cover EVERY promoting unit. A unit with a soak gate is
	//    exactly a unit whose release PR can auto-merge into a promotion, so
	//    the two halves of the interlock must agree on the same set.
	for _, job := range genJobs {
		unit, isSoak := strings.CutSuffix(job, "-require-dev-soak")
		if !isSoak {
			continue
		}
		devJob := unit + "-" + firstEnvironmentOf(t, genSrc, unit)
		if !covered[devJob] {
			t.Errorf("%s promotes (it has a soak gate) but release-hold.yaml has no entry watching %q — its release PR can auto-merge while development is red, which is the gap require-dev-soak.sh exists to close from the other side", unit, devJob)
		}
	}
}

// firstEnvironmentOf reads the rung a unit's development job serves, from the
// generated file, so this test cannot hardcode "development".
func firstEnvironmentOf(t *testing.T, src, unit string) string {
	t.Helper()
	lines := parseWorkflow(t, src)
	for _, job := range jobIDsOf(t, lines) {
		env, ok := strings.CutPrefix(job, unit+"-")
		if !ok || env == "build" || env == "changelog" || env == "require-dev-soak" {
			continue
		}
		// The FIRST rung is the one that needs orchestrate: it is the only one
		// keyed on the push manifest.
		if strings.Contains(jobScalar(t, lines, job, "needs"), "orchestrate") {
			return env
		}
	}
	t.Fatalf("no push-lane rung found for unit %q in the generated workflow", unit)
	return ""
}

// TestTabulaTagScopingIsNarrowerThanLegacy states the ONE sanctioned behaviour
// divergence Phase 2 introduces, as a test rather than as prose.
//
// LEGACY: tabula-deploy.yaml's promotion jobs fire on EITHER tabula tag for
// BOTH services — `startsWith(tag, 'tabula-api-v') || startsWith(tag,
// 'tabula-web-v')` — so cutting a tabula-web release also promoted the API to
// production, shipping whatever was on main without an API release PR ever
// being reviewed.
//
// GENERATED: each unit promotes on its OWN tag. Strictly NARROWER, never
// wider, which is the only direction a promotion gate may move without a
// separate decision.
//
// PROVES BOTH HALVES: that legacy really does OR the two prefixes (so this is
// a real, understood divergence and not a misreading), and that the generated
// rungs really are scoped to one prefix each. When Phase 3 deletes the legacy
// file this test goes with it, and the divergence stops existing.
func TestTabulaTagScopingIsNarrowerThanLegacy(t *testing.T) {
	legacy := parseWorkflow(t, mustRead(t, legacyTabulaWorkflowRel))
	generated := parseWorkflow(t, mustRead(t, deliveryWorkflowRel))

	for _, job := range []string{"deploy-nonprod-api", "deploy-prod-api", "deploy-nonprod-web", "deploy-prod-web"} {
		cond := jobScalar(t, legacy, job, "if")
		for _, prefix := range []string{"tabula-api-v", "tabula-web-v"} {
			if !strings.Contains(cond, "startsWith(github.event.release.tag_name, '"+prefix+"')") {
				t.Errorf("legacy %s no longer ORs %q — the divergence this test sanctions has changed shape; re-read both files before trusting the generated scoping", job, prefix)
			}
		}
	}

	for _, tc := range []struct{ job, own, foreign string }{
		{"tabula-api-nonproduction", "tabula-api-v", "tabula-web-v"},
		{"tabula-api-production", "tabula-api-v", "tabula-web-v"},
		{"tabula-web-nonproduction", "tabula-web-v", "tabula-api-v"},
		{"tabula-web-production", "tabula-web-v", "tabula-api-v"},
	} {
		cond := jobScalar(t, generated, tc.job, "if")
		if !strings.Contains(cond, "startsWith(github.event.release.tag_name, '"+tc.own+"')") {
			t.Errorf("%s does not promote on its own tag %q: %s", tc.job, tc.own, cond)
		}
		if strings.Contains(cond, tc.foreign) {
			t.Errorf("%s promotes on %q, the OTHER unit's release tag — that is legacy's wider behaviour, which this migration deliberately narrows: %s", tc.job, tc.foreign, cond)
		}
	}
}

// ---------------------------------------------------------------------------
// WAVE B2 — the publishes and the Pulumi applies
// ---------------------------------------------------------------------------

// b2Rel maps a fixture's legacy_workflow (a repo-root path) to the path this
// test reads it by. The declarations state the repo-root path because that is
// what a human checks; the test runs from its own package directory, in the
// checkout and in the runfiles tree alike.
func b2Rel(legacyWorkflow string) string { return "../../../" + legacyWorkflow }

// b2Units are the Wave-B2 declarations, read from the SAME frozen fixtures the
// golden is rendered from — so the parity baseline (legacy_workflow +
// legacy_job) is declaration DATA, not a table maintained beside it. A
// declaration that stops naming its legacy job fails to be checked here, which
// is why delivery() refuses render = "transcribed" without both.
func b2Units(t *testing.T, render string) []unit {
	t.Helper()
	units, err := loadUnits(fixtureUnits)
	if err != nil {
		t.Fatalf("loadUnits: %v", err)
	}
	var out []unit
	for _, u := range units {
		if u.Render == render {
			out = append(out, u)
		}
	}
	if len(out) == 0 {
		t.Fatalf("no fixture declares render = %q — the fixtures or the attribute drifted", render)
	}
	return out
}

// TestTranscribedJobsMatchLegacy is the Wave-B2 transcription guard.
//
// PROVES: every job the generator TRANSCRIBED is the legacy job it came from —
// same steps, same order, same action pins, same script bodies, same env,
// same permissions, same timeout — rather than a re-derivation of it. Compared
// as TEXT, because that is the only comparison that catches a dropped flag, a
// changed tag, a `--clobber` that went missing, or a digest capture that stops
// writing $GITHUB_OUTPUT.
//
// The comparison is driven by the DECLARATIONS (legacy_workflow/legacy_job), so
// adding a transcribed unit without a baseline is impossible: delivery() will
// not accept it, and this test would not know to check it.
func TestTranscribedJobsMatchLegacy(t *testing.T) {
	generated := parseWorkflow(t, mustRead(t, deliveryWorkflowRel))
	genSrc := mustRead(t, deliveryWorkflowRel)

	for _, u := range b2Units(t, renderTranscribed) {
		t.Run(u.Name, func(t *testing.T) {
			legacySrc := mustRead(t, b2Rel(u.LegacyWorkflow))
			legacy := parseWorkflow(t, legacySrc)
			genJob := u.Name + "-" + u.Environments[0]

			want := canonicalSteps(t, legacySrc, u.LegacyJob)
			got := canonicalSteps(t, genSrc, genJob)
			if len(got) != len(want) {
				t.Fatalf("%s renders %d steps, legacy %s job %q has %d:\n--- generated ---\n%s\n--- legacy ---\n%s",
					genJob, len(got), u.LegacyWorkflow, u.LegacyJob, len(want),
					strings.Join(got, "\n"), strings.Join(want, "\n"))
			}
			for i := range want {
				if got[i] != want[i] {
					t.Errorf("%s step %d differs from legacy %s job %q:\n--- generated ---\n%s\n--- legacy ---\n%s",
						genJob, i+1, u.LegacyWorkflow, u.LegacyJob, got[i], want[i])
				}
			}

			for _, key := range []string{"runs-on", "timeout-minutes"} {
				w := jobScalar(t, legacy, u.LegacyJob, key)
				if g := jobScalar(t, generated, genJob, key); g != w {
					t.Errorf("%s %s = %q, legacy = %q", genJob, key, g, w)
				}
			}
			// The GitHub Environment is a LADDER fact here (the declaration's
			// github_environment resolved for this rung), so assert it against
			// the declaration AND against legacy — a rung bound to the wrong
			// Environment runs as the wrong service account.
			wantEnv := strings.ReplaceAll(u.GitHubEnvironment, "{env}", u.Environments[0])
			gotEnv := jobKeyOrEmpty(generated, genJob, "environment")
			if gotEnv != wantEnv {
				t.Errorf("%s binds environment %q, declaration resolves %q", genJob, gotEnv, wantEnv)
			}
			if legacyEnv := jobKeyOrEmpty(legacy, u.LegacyJob, "environment"); legacyEnv != wantEnv {
				t.Errorf("%s binds environment %q but legacy %s job %q binds %q — the declaration's github_environment pattern does not reproduce the legacy Environment", genJob, wantEnv, u.LegacyWorkflow, u.LegacyJob, legacyEnv)
			}

			for _, key := range []string{"permissions", "env"} {
				w := jobSubMapOrEmpty(legacy, u.LegacyJob, key)
				g := jobSubMapOrEmpty(generated, genJob, key)
				// permissions: legacy several of these declare it at the
				// WORKFLOW level, which the generated file cannot do without
				// handing it to every other unit. Fall back to the legacy
				// workflow-level block in that case, so the comparison is
				// against the grant the job actually HAD.
				if key == "permissions" && len(w) == 0 {
					w = topLevelSubMap(t, legacy, "permissions")
				}
				if len(g) != len(w) {
					t.Errorf("%s %s has %v, legacy %s job %q has %v", genJob, key, sortedKeys(g), u.LegacyWorkflow, u.LegacyJob, sortedKeys(w))
				}
				for _, k := range sortedKeys(w) {
					if g[k] != w[k] {
						t.Errorf("%s %s.%s = %q, legacy = %q", genJob, key, k, g[k], w[k])
					}
				}
			}

			// Intended difference, asserted rather than assumed: the legacy
			// job may serialize itself with a job-level `concurrency:`; the
			// generated one never does, because this file serializes EVERY
			// delivery run at the workflow level (strictly stronger, and the
			// only placement that works for `uses:` jobs — #1607).
			block, ok := jobText(genSrc, genJob)
			if !ok {
				t.Fatalf("cannot isolate %s", genJob)
			}
			if strings.Contains(block, "\n    concurrency:") {
				t.Errorf("%s declares its own concurrency group; the workflow-level group already serializes every delivery run", genJob)
			}
		})
	}
}

// TestReusableRungsMatchLegacy is the same guard for the units rendered as
// callers of a reusable workflow.
//
// PROVES: every rung of the identity ladders calls the SAME reusable workflow
// with the SAME inputs as the legacy job of that rung — in particular that
// `gh-environment` still resolves to foundation-proj-<env>. That input is the
// only thing selecting WHICH service account applies the stack: the app deploy
// SA is what these stacks CREATE, so it cannot be what applies them, and a rung
// pointed at the app pattern would fail (or, worse, apply as the wrong
// identity).
func TestReusableRungsMatchLegacy(t *testing.T) {
	generated := parseWorkflow(t, mustRead(t, deliveryWorkflowRel))

	for _, u := range b2Units(t, renderReusable) {
		t.Run(u.Name, func(t *testing.T) {
			legacy := parseWorkflow(t, mustRead(t, b2Rel(u.LegacyWorkflow)))
			for i, env := range u.Environments {
				genJob := u.Name + "-" + env
				// The legacy job ids ARE the rung names.
				legacyJob := env

				want := jobScalar(t, legacy, legacyJob, "uses")
				if got := jobScalar(t, generated, genJob, "uses"); got != want {
					t.Errorf("%s calls %q, legacy %s calls %q", genJob, got, legacyJob, want)
				}
				assertMapsMatch(t, legacyJob, jobWith(t, legacy, legacyJob), genJob, jobWith(t, generated, genJob), nil)

				gotWith := jobWith(t, generated, genJob)
				if gotWith["stack"] != env {
					t.Errorf("%s applies stack %q, want %q", genJob, gotWith["stack"], env)
				}
				if wantEnv := strings.ReplaceAll(u.GitHubEnvironment, "{env}", env); gotWith["gh-environment"] != wantEnv {
					t.Errorf("%s passes gh-environment %q, want %q (the declaration's github_environment for this rung)", genJob, gotWith["gh-environment"], wantEnv)
				}
				if gotWith["environment"] != "" {
					t.Errorf("%s passes an `environment` input; this reusable takes stack + gh-environment, and a stray key fails the run at startup with \"invalid input\"", genJob)
				}

				// The chain: rung N starts only after rung N-1 succeeded, both
				// in `needs:` and in the condition. A ladder that lost its
				// chain applies production concurrently with development.
				needs := jobScalar(t, generated, genJob, "needs")
				cond := jobScalar(t, generated, genJob, "if")
				if i == 0 {
					if strings.Contains(cond, ".result == 'success'") {
						t.Errorf("%s (first rung) waits on a predecessor: %s", genJob, cond)
					}
					continue
				}
				prev := u.Name + "-" + u.Environments[i-1]
				if !strings.Contains(needs, prev) {
					t.Errorf("%s needs = %q, which does not include %q", genJob, needs, prev)
				}
				if !strings.Contains(cond, "needs."+prev+".result == 'success'") {
					t.Errorf("%s does not require %s to have succeeded — the ladder would apply every rung at once: %s", genJob, prev, cond)
				}
			}
		})
	}
}

// TestWaveB2LegacyWorkflowsAreDispatchOnlyShells is the legacy-surgery
// assertion for every file Wave B2 migrated.
//
// PROVES: none of them can still deliver by itself. With `push:` still present
// both files would do the same work on every merge — two `helm push`es onto one
// OCI repo, two uploads onto one rolling prerelease tag, two Pulumi applies on
// one stack. `workflow_dispatch` survives as the escape hatch until Phase 3.
func TestWaveB2LegacyWorkflowsAreDispatchOnlyShells(t *testing.T) {
	units, err := loadUnits(fixtureUnits)
	if err != nil {
		t.Fatalf("loadUnits: %v", err)
	}
	seen := map[string]bool{}
	for _, u := range units {
		if u.LegacyWorkflow == "" || seen[u.LegacyWorkflow] {
			continue
		}
		seen[u.LegacyWorkflow] = true
		triggers := topLevelChildKeys(t, parseWorkflow(t, mustRead(t, b2Rel(u.LegacyWorkflow))), "on")
		for _, gone := range []string{"push", "release"} {
			if contains(triggers, gone) {
				t.Errorf("%s still triggers on %q — the generated delivery.yaml owns that lane now, so BOTH would deliver from one event (triggers: %v)", u.LegacyWorkflow, gone, triggers)
			}
		}
		if !contains(triggers, "workflow_dispatch") {
			t.Errorf("%s lost its workflow_dispatch trigger — that is the break-glass escape hatch Phase 2 keeps until Phase 3 deletes the file", u.LegacyWorkflow)
		}
	}
	if len(seen) == 0 {
		t.Fatal("no fixture names a legacy_workflow — the parity baseline is gone")
	}
}

// TestChartsPublishRunsOneScript closes the loop the extraction opened.
//
// PROVES: the legacy workflow and the generated job run the SAME
// tools/charts/publish.sh — one copy, so they cannot drift while both exist —
// and that the declaration's `run` target names it. Before the extraction the
// publish was 45 inline lines with no Bazel target of any kind, so the spec's
// "CI and break-glass execute the same target" (§4.1) had nothing to point at.
func TestChartsPublishRunsOneScript(t *testing.T) {
	const script = "bash tools/charts/publish.sh"
	legacy := mustRead(t, "../../../.github/workflows/charts-publish.yml")
	generated := mustRead(t, deliveryWorkflowRel)

	if !strings.Contains(legacy, "run: "+script) {
		t.Errorf("charts-publish.yml no longer runs %q — the two copies have diverged again", script)
	}
	if !strings.Contains(generated, "run: "+script) {
		t.Errorf("the generated charts job no longer runs %q", script)
	}
	if strings.Contains(legacy, "helm package ") || strings.Contains(generated, "helm package ") {
		t.Error("a `helm package` line is back inside a workflow — the packaging logic belongs to tools/charts/publish.sh alone")
	}

	units, err := loadUnits(fixtureUnits)
	if err != nil {
		t.Fatalf("loadUnits: %v", err)
	}
	for _, u := range units {
		if u.Name != "charts" {
			continue
		}
		if want := "//tools/charts:publish"; u.Run != want {
			t.Errorf("charts declares run = %q, want %q (the sh_binary wrapping the one script)", u.Run, want)
		}
		return
	}
	t.Fatal("no `charts` unit in the fixtures")
}

// ---------------------------------------------------------------------------
// reader extensions for Wave B2
// ---------------------------------------------------------------------------

// jobKeyOrEmpty is jobScalar without the fatal: a job legitimately may not bind
// an `environment:` at all.
func jobKeyOrEmpty(lines []wfLine, job, key string) string {
	for i, l := range lines {
		if l.indent != 2 || l.key != job {
			continue
		}
		child := -1
		for _, c := range lines[i+1:] {
			if c.indent <= l.indent {
				break
			}
			if child < 0 {
				child = c.indent
			}
			if c.indent == child && c.key == key {
				return unquote(c.value)
			}
		}
		return ""
	}
	return ""
}

// jobSubMapOrEmpty is jobSubMap without the fatal.
func jobSubMapOrEmpty(lines []wfLine, job, key string) map[string]string {
	out := map[string]string{}
	for i, l := range lines {
		if l.key != job {
			continue
		}
		child, at := -1, -1
		for j := i + 1; j < len(lines); j++ {
			if lines[j].indent <= l.indent {
				break
			}
			if child < 0 {
				child = lines[j].indent
			}
			if lines[j].indent == child && lines[j].key == key {
				at = j
				break
			}
		}
		if at < 0 {
			return out
		}
		inner := -1
		for _, c := range lines[at+1:] {
			if c.indent <= lines[at].indent {
				break
			}
			if inner < 0 {
				inner = c.indent
			}
			if c.indent == inner && c.key != "" {
				out[c.key] = unquote(c.value)
			}
		}
		return out
	}
	return out
}

// topLevelSubMap reads a column-0 mapping (e.g. a workflow-level
// `permissions:`).
func topLevelSubMap(t *testing.T, lines []wfLine, key string) map[string]string {
	t.Helper()
	i := indexOfTopLevel(lines, key)
	if i < 0 {
		return map[string]string{}
	}
	out := map[string]string{}
	inner := -1
	for _, l := range lines[i+1:] {
		if l.indent == 0 {
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

// canonicalSteps is normalizedSteps with the INDENTATION STYLE normalized
// away, and nothing else.
//
// WHY: copybara-sync-auth-apply.yaml is written with 4-space nesting while
// every generated file uses 2. That is a formatting difference with no runtime
// meaning, and without normalizing it a text comparison would fail on every
// line of that job and pass on nothing. Each line is re-indented to a canonical
// 2-space ladder by its DEPTH, and a block scalar's body is dedented to its own
// base and re-indented under its key — so the script text inside `run: |` is
// still compared character for character, which is where the risk lives.
//
// The exact bytes of the generated file are pinned separately, by the golden
// and by actionlint; this normalization exists only to compare ACROSS two files
// with different house styles.
func canonicalSteps(t *testing.T, src, job string) []string {
	t.Helper()
	steps := normalizedSteps(t, src, job)
	out := make([]string, 0, len(steps))
	for _, s := range steps {
		out = append(out, canonicalizeIndent(s))
	}
	return out
}

func isBlockScalarOpener(trimmed string) bool {
	for _, suffix := range []string{": |", ": |-", ": >", ": >-", ": |+", ": >+"} {
		if strings.HasSuffix(trimmed, suffix) {
			return true
		}
	}
	return false
}

func canonicalizeIndent(step string) string {
	lines := strings.Split(step, "\n")
	out := make([]string, 0, len(lines))
	var stack []int // raw indents, strictly increasing = the current path
	blockRaw, blockCanon, blockBody := -1, 0, -1

	for _, ln := range lines {
		if strings.TrimSpace(ln) == "" {
			out = append(out, "")
			continue
		}
		ind := indentOf(ln)
		if blockRaw >= 0 {
			if ind > blockRaw {
				if blockBody < 0 {
					blockBody = ind
				}
				rel := ind - blockBody
				if rel < 0 {
					rel = 0
				}
				out = append(out, strings.Repeat(" ", blockCanon+2+rel)+strings.TrimLeft(ln, " "))
				continue
			}
			blockRaw, blockBody = -1, -1
		}
		for len(stack) > 0 && stack[len(stack)-1] >= ind {
			stack = stack[:len(stack)-1]
		}
		stack = append(stack, ind)
		canon := 2 * (len(stack) - 1)
		body := strings.TrimLeft(ln, " ")
		out = append(out, strings.Repeat(" ", canon)+body)
		if isBlockScalarOpener(body) {
			blockRaw, blockCanon = ind, canon
		}
	}
	return strings.Join(out, "\n")
}
