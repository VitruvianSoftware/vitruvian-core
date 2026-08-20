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
	"regexp"
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

// TestGeneratedSoakJobsAreWired is the promotion interlock's wiring guard.
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
func TestGeneratedSoakJobsAreWired(t *testing.T) {
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

	// ...and the script the jobs run must exist. It is the interlock: a
	// `run:` naming a missing file fails the job, which (because the rung
	// requires `result == 'success'`) blocks every promotion — loudly, at
	// least, but the guard is cheap and the deletion is easy to make.
	if _, err := os.Stat("../../../tools/ci/require-dev-soak.sh"); err != nil {
		t.Errorf("tools/ci/require-dev-soak.sh is missing (%v) — every soak job would fail and no promotion could run", err)
	}
}

// TestGeneratedChangelogJobPassesDeclaredInputs closes the Phase-1 deferred flag.
//
// PROVES: the generated changelog job calls _changelog-summary.yaml with inputs
// that workflow actually declares, and is keyed on `push`. The key matters:
// with a repo-wide `release:` trigger an unconditional job would run on EVERY
// published release of every unrelated component (the per-app workflow it came
// from carried no `if:` because it could not see other components' releases).
func TestGeneratedChangelogJobPassesDeclaredInputs(t *testing.T) {
	generated := parseWorkflow(t, mustRead(t, deliveryWorkflowRel))

	if got, want := jobScalar(t, generated, "tabula-api-changelog", "uses"), changelogWorkflow; got != want {
		t.Errorf("tabula-api-changelog calls %q, want %q", got, want)
	}
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

// ---------------------------------------------------------------------------
// WAVE B2 — the publishes and the Pulumi applies
// ---------------------------------------------------------------------------

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

// b2Units are the Wave-B2 declarations, read from the SAME frozen fixtures the
// golden is rendered from — so which units a guard covers is declaration DATA
// (render = ...), not a list maintained beside it. A new unit of that shape is
// covered the moment it is declared.
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

// ---------------------------------------------------------------------------
// PHASE 3 — the guards that replace the deleted parity baselines
// ---------------------------------------------------------------------------
//
// Phases 1 and 2 proved every generated job against the hand-written job it
// replaced, mechanically, on every test run. Phase 3 deletes those workflows —
// that is the point of the migration — so those comparisons are gone with them.
// What replaces them is not "nothing": it is the set of properties that were
// only ever IMPLIED by matching the legacy file, now asserted directly against
// the things that still exist.
//
//	every `uses:` resolves to a file that exists          (a deleted callee = a
//	                                                       run that fails at
//	                                                       startup, no jobs)
//	every `with:` key is an input the callee declares      ("invalid input")
//	every `run:` script exists and is executable           (a job that fails)
//	the 8 deleted workflows are gone AND unreferenced      (no dangling links)
//
// Plus the golden, which pins every byte of the rendered file, so a change to
// any transcribed step is still a diff a human reads in review.

// localUse is one `uses: ./…` in the generated workflow and the `with:` keys
// passed to it.
type localUse struct {
	path string
	keys []string
	line int
}

// localUses scans the generated workflow for local `uses:` references. Text
// scanning rather than the wfLine reader because these appear at two different
// nestings (a job-level `uses:` and a step-level `- uses:`), and both matter.
func localUses(t *testing.T, src string) []localUse {
	t.Helper()
	var out []localUse
	lines := strings.Split(src, "\n")
	for i, raw := range lines {
		trimmed := strings.TrimSpace(raw)
		trimmed = strings.TrimPrefix(trimmed, "- ")
		val, ok := strings.CutPrefix(trimmed, "uses: ")
		if !ok || !strings.HasPrefix(val, "./") {
			continue
		}
		u := localUse{path: strings.TrimSpace(val), line: i + 1}
		// `with:` is a sibling of this `uses:`, i.e. at the same indent.
		indent := len(raw) - len(strings.TrimLeft(raw, " "))
		if strings.HasPrefix(strings.TrimLeft(raw, " "), "- ") {
			indent += 2
		}
		for j := i + 1; j < len(lines); j++ {
			l := lines[j]
			if strings.TrimSpace(l) == "" || strings.HasPrefix(strings.TrimSpace(l), "#") {
				continue
			}
			ind := len(l) - len(strings.TrimLeft(l, " "))
			if ind < indent {
				break
			}
			if ind == indent && strings.TrimSpace(l) != "with:" {
				continue
			}
			if ind == indent && strings.TrimSpace(l) == "with:" {
				for k := j + 1; k < len(lines); k++ {
					wl := lines[k]
					if strings.TrimSpace(wl) == "" || strings.HasPrefix(strings.TrimSpace(wl), "#") {
						continue
					}
					wind := len(wl) - len(strings.TrimLeft(wl, " "))
					if wind <= indent {
						break
					}
					if key, _, ok := strings.Cut(strings.TrimSpace(wl), ":"); ok {
						u.keys = append(u.keys, key)
					}
				}
				break
			}
		}
		out = append(out, u)
	}
	if len(out) == 0 {
		t.Fatal("the generated workflow references no local `uses:` at all — the scanner or the file layout drifted")
	}
	return out
}

// declaredInputs reads the input names a local workflow or composite action
// declares.
func declaredInputs(t *testing.T, rel string) []string {
	t.Helper()
	lines := parseWorkflow(t, mustRead(t, rel))
	for i, l := range lines {
		if l.key != "inputs" {
			continue
		}
		return childKeys(lines, i)
	}
	t.Fatalf("%s declares no `inputs:` mapping", rel)
	return nil
}

// TestEveryLocalUseResolvesAndPassesDeclaredInputs is the guard that replaces
// "the generated job matches the hand-written one it came from".
//
// PROVES: every reusable workflow and composite action the generated file calls
// EXISTS, and every input it passes is one that callee declares. Both failures
// are startup failures with no jobs instantiated — a missing callee takes the
// whole run down (orchestrate included), and an undeclared input is rejected
// as "invalid input" — so neither is caught by anything downstream. This is
// exactly what deleting the legacy workflows could have broken silently: a
// `uses:` pointing at a file that no longer exists.
func TestEveryLocalUseResolvesAndPassesDeclaredInputs(t *testing.T) {
	src := mustRead(t, deliveryWorkflowRel)

	for _, u := range localUses(t, src) {
		rel := "../../../" + strings.TrimPrefix(u.path, "./")
		target := rel
		if strings.Contains(u.path, "/actions/") {
			target = rel + "/action.yml"
			if _, err := os.Stat(target); err != nil {
				target = rel + "/action.yaml"
			}
		}
		if _, err := os.Stat(target); err != nil {
			t.Errorf("line %d: `uses: %s` resolves to %s, which does not exist (%v) — GitHub fails the WHOLE workflow at startup for that, taking orchestrate down with it", u.line, u.path, target, err)
			continue
		}
		if len(u.keys) == 0 {
			continue
		}
		declared := declaredInputs(t, target)
		for _, k := range u.keys {
			if !contains(declared, k) {
				t.Errorf("line %d: `uses: %s` is passed %q, which %s does not declare as an input (declares %v) — the run fails at startup with \"invalid input\"", u.line, u.path, k, u.path, declared)
			}
		}
	}
}

// TestEveryRunScriptExists is the same property for the `run:` half.
//
// PROVES: every script the generated workflow shells out to is present and
// executable. A `run: bash <missing>` is a failed job — for a promotion rung's
// soak gate that is a blocked promotion, and for a publish it is a delivery
// that silently stopped happening the day someone moved a file.
func TestEveryRunScriptExists(t *testing.T) {
	src := mustRead(t, deliveryWorkflowRel)
	re := regexp.MustCompile(`(?m)^\s*run: (?:bash |\./)([A-Za-z0-9_./-]+\.sh)\s*$`)

	found := re.FindAllStringSubmatch(src, -1)
	if len(found) == 0 {
		t.Fatal("the generated workflow runs no scripts at all — the pattern or the file drifted")
	}
	seen := map[string]bool{}
	for _, m := range found {
		if seen[m[1]] {
			continue
		}
		seen[m[1]] = true
		info, err := os.Stat("../../../" + m[1])
		if err != nil {
			t.Errorf("the generated workflow runs %q, which does not exist (%v)", m[1], err)
			continue
		}
		if info.Mode()&0o111 == 0 {
			t.Errorf("%s is not executable — `bash <file>` still works, but `bazel run` on its sh_binary wrapper does not, and those are supposed to be the same path", m[1])
		}
	}
}

// TestDeletedLegacyWorkflowsAreGoneAndUnreferenced is the Phase-3 deletion
// assertion.
//
// PROVES: the eight hand-written delivery workflows are actually gone, and
// nothing under .github/ still points at one. A dangling `uses:` or
// `workflow_run: workflows: [<deleted>]` is not an error GitHub reports — the
// trigger simply never fires again, which is how the release-hold interlock
// was found silently dead after Phase 1 moved a lane out from under it.
func TestDeletedLegacyWorkflowsAreGoneAndUnreferenced(t *testing.T) {
	deleted := []string{
		"oauth-user-inspector-deploy.yaml",
		"tabula-deploy.yaml",
		"tabula-dev-latest.yaml",
		"charts-publish.yml",
		"tabula-build-stack.yaml",
		"copybara-sync-auth-apply.yaml",
		"tabula-identity-stack.yaml",
		"oauth-user-inspector-identity-stack.yaml",
	}
	dir := "../../../.github/workflows"
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("cannot read %s: %v", dir, err)
	}
	present := map[string]bool{}
	for _, e := range entries {
		present[e.Name()] = true
	}

	for _, name := range deleted {
		if present[name] {
			t.Errorf(".github/workflows/%s still exists — Phase 3 deletes every workflow whose lane the orchestrator took over; two workflows on one lane race each other", name)
		}
	}

	// ...and nothing left under .github/workflows/ ACTIVELY references one.
	//
	// "Actively" = outside a comment. A `uses:`, a `workflow_run: workflows:`
	// entry or a WORKFLOW_FILE value naming a deleted file is not an error
	// GitHub reports: the callee is missing (the run dies at startup) or the
	// trigger simply never fires again — which is how the release-hold
	// interlock was found silently dead after Phase 1 moved a lane out from
	// under it. A COMMENT naming one is allowed and deliberate: the generated
	// file records where each transcribed job came from, since git history is
	// the only place the original now exists.
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		body, err := os.ReadFile(dir + "/" + e.Name())
		if err != nil {
			t.Fatalf("read %s: %v", e.Name(), err)
		}
		for i, line := range strings.Split(string(body), "\n") {
			if strings.HasPrefix(strings.TrimSpace(line), "#") {
				continue
			}
			for _, name := range deleted {
				if strings.Contains(line, name) {
					t.Errorf(".github/workflows/%s:%d actively references the deleted workflow %q — that trigger never fires, or that call fails the run at startup:\n  %s", e.Name(), i+1, name, strings.TrimSpace(line))
				}
			}
		}
	}
}

// TestGeneratedCompanionsCallTheirWorkhorse replaces the companion parity test.
//
// PROVES what matching zitadel-dev/-nonprod/-prod used to prove, asserted
// directly: each companion rung calls _zitadel-apps-apply.yaml with the rung it
// serves, keeps the ZITADEL_APPS_AUTO_APPLY gate (without it the apply FAILS
// the deploy instead of cleanly no-opping while the machine key is unseeded),
// and the production companion chains behind the nonproduction DEPLOY —
// expanding a rung that is not about to be served is #1794's shape against a
// stack whose force-replace deletes the live OIDC client.
func TestGeneratedCompanionsCallTheirWorkhorse(t *testing.T) {
	generated := parseWorkflow(t, mustRead(t, deliveryWorkflowRel))
	spec, ok := companionWorkflows["zitadel-apps"]
	if !ok {
		t.Fatal("no zitadel-apps companion is registered — this guard is checking nothing")
	}

	for _, tc := range []struct {
		job, env, chainedBehind string
	}{
		{"zitadel-apps-development", "development", ""},
		{"zitadel-apps-nonproduction", "nonproduction", ""},
		{"zitadel-apps-production", "production", "oauth-user-inspector-nonproduction"},
	} {
		t.Run(tc.job, func(t *testing.T) {
			if got := jobScalar(t, generated, tc.job, "uses"); got != spec.workflow {
				t.Errorf("%s calls %q, want %q", tc.job, got, spec.workflow)
			}
			with := jobWith(t, generated, tc.job)
			if with["environment"] != tc.env {
				t.Errorf("%s applies environment=%q, want %q", tc.job, with["environment"], tc.env)
			}
			if len(with) != 1 {
				t.Errorf("%s passes %v; the companion takes only `environment`", tc.job, sortedKeys(with))
			}
			cond := jobScalar(t, generated, tc.job, "if")
			if !strings.Contains(cond, spec.gateVar) {
				t.Errorf("%s lost the %q gate — the apply would FAIL the deploy instead of cleanly no-opping: %s", tc.job, spec.gateVar, cond)
			}
			if tc.chainedBehind == "" {
				return
			}
			if !strings.Contains(cond, "needs."+tc.chainedBehind+".result == 'success'") {
				t.Errorf("%s does not chain behind %s: %s", tc.job, tc.chainedBehind, cond)
			}
			if needs := jobScalar(t, generated, tc.job, "needs"); !strings.Contains(needs, tc.chainedBehind) {
				t.Errorf("%s needs = %q, which does not include %q — the condition reads a job it never waited for", tc.job, needs, tc.chainedBehind)
			}
		})
	}
}

// TestReusableRungsPassWhatTheCalleeDeclares replaces the identity-ladder
// parity test.
//
// PROVES: every rung passes the reusable applier the two inputs it declares —
// `stack` (the Pulumi stack) and `gh-environment` — with gh-environment
// resolving to foundation-proj-<env>. That input is the only thing selecting
// WHICH service account applies the stack: the app deploy SA is what these
// stacks CREATE, so it cannot be what applies them, and a rung pointed at the
// app pattern would apply as the wrong identity (or fail at startup on a
// non-existent Environment).
func TestReusableRungsPassWhatTheCalleeDeclares(t *testing.T) {
	generated := parseWorkflow(t, mustRead(t, deliveryWorkflowRel))

	for _, u := range b2Units(t, renderReusable) {
		t.Run(u.Name, func(t *testing.T) {
			spec, ok := reusableWorkflows[u.Name]
			if !ok {
				t.Fatalf("unit %q declares render=reusable but no workflow is registered", u.Name)
			}
			calleeRel := "../../../" + strings.TrimPrefix(spec.workflow, "./")
			declared := declaredInputs(t, calleeRel)

			for i, env := range u.Environments {
				job := u.Name + "-" + env
				if got := jobScalar(t, generated, job, "uses"); got != spec.workflow {
					t.Errorf("%s calls %q, want %q", job, got, spec.workflow)
				}
				with := jobWith(t, generated, job)
				for k := range with {
					if !contains(declared, k) {
						t.Errorf("%s passes %q, which %s does not declare (declares %v)", job, k, spec.workflow, declared)
					}
				}
				if with["stack"] != env {
					t.Errorf("%s applies stack %q, want %q", job, with["stack"], env)
				}
				if want := strings.ReplaceAll(u.GitHubEnvironment, "{env}", env); with["gh-environment"] != want {
					t.Errorf("%s passes gh-environment %q, want %q — that input selects the applying service account", job, with["gh-environment"], want)
				}
				if i == 0 {
					continue
				}
				prev := u.Name + "-" + u.Environments[i-1]
				if !strings.Contains(jobScalar(t, generated, job, "if"), "needs."+prev+".result == 'success'") {
					t.Errorf("%s does not require %s to have succeeded — the ladder would apply every rung at once", job, prev)
				}
			}
		})
	}
}

// TestPublishersAreOneScriptEach is the "CI and break-glass run the same
// thing" assertion (spec §4.1), now true of every unit.
//
// PROVES: the two publish units run a SCRIPT, that script is what their
// delivery() `run` target wraps, and no packaging logic leaked back into the
// workflow. Before Phase 3 the extension publisher was three inline steps and
// its `run` named a genrule that `bazel run` cannot execute — the last unit
// where the delivered thing and the break-glass thing were different code.
func TestPublishersAreOneScriptEach(t *testing.T) {
	generated := mustRead(t, deliveryWorkflowRel)
	units, err := loadUnits(fixtureUnits)
	if err != nil {
		t.Fatalf("loadUnits: %v", err)
	}

	for _, tc := range []struct{ unit, script, runTarget string }{
		{"charts", "tools/charts/publish.sh", "//tools/charts:publish"},
		{"tabula-dev-latest", "tabula/extension/publish-dev-latest.sh", "//tabula/extension:publish-dev-latest"},
	} {
		t.Run(tc.unit, func(t *testing.T) {
			if !strings.Contains(generated, "run: bash "+tc.script) {
				t.Errorf("the generated workflow does not run %q", tc.script)
			}
			if _, err := os.Stat("../../../" + tc.script); err != nil {
				t.Errorf("%s is missing: %v", tc.script, err)
			}
			var found bool
			for _, u := range units {
				if u.Name != tc.unit {
					continue
				}
				found = true
				if u.Run != tc.runTarget {
					t.Errorf("unit %q declares run = %q, want %q (the sh_binary wrapping the one script)", tc.unit, u.Run, tc.runTarget)
				}
			}
			if !found {
				t.Fatalf("no %q unit in the fixtures", tc.unit)
			}
		})
	}
	// The packaging/publishing logic must not exist in two places again.
	for _, leaked := range []string{"helm package ", "gh release upload "} {
		if strings.Contains(generated, leaked) {
			t.Errorf("%q is back inside the generated workflow — that logic belongs to the extracted script alone, or CI and break-glass drift apart", leaked)
		}
	}
}

// TestPreflightRendersSkipIfUnchanged is the Phase-3 detection-sharpening
// guard (spec §4.5).
//
// PROVES the whole chain the `preflight` attr stands for:
//
//  1. a unit declaring it passes `skip-if-unchanged: true` on EVERY rung, so
//     _deploy-cloud-run.yaml runs tools/ci/tabula-deploy-preflight.sh and skips
//     the migrate + blue-green + smoke when the live service already serves the
//     desired revision;
//  2. a unit NOT declaring it passes the key at all — the reusable workflow's
//     default is false, and an explicit `false` in a declaration would be a
//     second place saying the same thing;
//  3. the declaring unit's Pulumi program actually SHIPS cmd/revname. Without
//     it the preflight's desired-name computation fails, and the script's
//     fail-open turns that into `unchanged=false` FOREVER: a preflight that
//     runs on every deploy, costs a `go run`, and can never skip anything.
//     That is the failure this test exists for — it is invisible in the run
//     log, which just says "deploying".
//
// WHY THE PREFLIGHT IS NOT AN ORCHESTRATOR VETO, recorded here because the
// alternative is the obvious-looking one: its input is IMAGE_DIGEST (the
// script requires it), and `orchestrate` runs BEFORE every build job — there is
// no digest at decide time. Producing one would mean building every unit's
// image inside the DECIDE job, which is the cost graph/path detection exists to
// avoid, and for a Dockerfile-built app the pre-built digest would never equal
// the pushed one anyway, so the veto could never fire.
func TestPreflightRendersSkipIfUnchanged(t *testing.T) {
	units := loadFixtures(t)
	generated := parseWorkflow(t, mustRead(t, deliveryWorkflowRel))

	declared := 0
	for _, u := range units {
		if u.Kind != kindCloudRun {
			continue
		}
		for _, env := range u.Environments {
			with := jobWith(t, generated, u.Name+"-"+env)
			got, present := with["skip-if-unchanged"]
			if u.Preflight == "" {
				if present {
					t.Errorf("%s-%s passes skip-if-unchanged=%q but its declaration has no preflight — the reusable workflow's default is false, and a second source for the same fact is how the two drift", u.Name, env, got)
				}
				continue
			}
			if got != "true" {
				t.Errorf("%s-%s declares preflight=%q but passes skip-if-unchanged=%q (present=%v) — the deploy would run the full rollout even when the live service already serves the desired revision", u.Name, env, u.Preflight, got, present)
			}
		}
		if u.Preflight == "" {
			continue
		}
		declared++
		// The mechanism has to exist for THIS unit's stack.
		dir, ok := u.WorkflowInputs["pulumi-dir"].(string)
		if !ok || dir == "" {
			t.Errorf("unit %q declares preflight but passes no pulumi-dir — the preflight runs inside that directory", u.Name)
			continue
		}
		revname := "../../../" + dir + "/cmd/revname"
		if _, err := os.Stat(revname); err != nil {
			t.Errorf("unit %q declares preflight=%q but %s/cmd/revname does not exist (%v) — tools/ci/tabula-deploy-preflight.sh defaults REVNAME to `go run ./cmd/revname` inside pulumi-dir, so the desired-name computation would fail and the gate would fail open on every single deploy", u.Name, u.Preflight, dir, err)
		}
	}
	if declared == 0 {
		t.Fatal("no fixture declares a preflight — this guard is checking nothing")
	}
}
