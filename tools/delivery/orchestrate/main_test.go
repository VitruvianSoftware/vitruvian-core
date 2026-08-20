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

// Hermetic tests for the delivery orchestrator.
//
// Two halves, deliberately asymmetric:
//
//   - bazel is FAKED (a shell stub emitting canned query output over a canned
//     bazel-bin). Discovery is a plumbing concern — what matters is that its
//     every failure mode reaches fail-open — and running real bazel here would
//     make the tests slow, non-hermetic and dependent on a checkout state.
//   - deploy-affected.sh is REAL. It is the decision engine; stubbing it would
//     only test our stub. Every decision test drives the actual script from
//     tools/ci over a scratch git repo built here, in PATH-ONLY mode (and one
//     graph-mode case that proves the DEPLOY_TARGETS plumbing without needing
//     target-determinator or the network).
//
// The matrix mirrors spec §5's failure table:
// docs/superpowers/specs/2026-08-19-delivery-orchestrator-design.md
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// ---------------------------------------------------------------------------
// TestMain: the scratch git repos, built once, never mutated afterwards
// ---------------------------------------------------------------------------

// scratch is one immutable diff shape: a repo whose HEAD differs from base by
// exactly the files a single test case cares about. Built once in TestMain and
// read-only thereafter, so tests cannot interfere with each other's git state
// the way a single shared repo with a moving HEAD would.
type scratch struct {
	dir  string // repo root; also the engine's cwd
	base string // BEFORE_REV: the commit immediately before the interesting one
}

var (
	// realScript is tools/ci/deploy-affected.sh — the real engine, not a copy.
	realScript string

	// One repo per diff shape (see TestMain).
	repoDeclared     scratch // touches a path the declaration claims
	repoUndeclared   scratch // touches nothing the declaration claims
	repoExcluded     scratch // touches a path claimed by extra_paths AND exclude_paths
	repoGlobalImpact scratch // touches MODULE.bazel (graph mode's global-impact guard)
)

func TestMain(m *testing.M) {
	os.Exit(func() int {
		abs, err := filepath.Abs(filepath.Join("..", "..", "ci", "deploy-affected.sh"))
		if err != nil {
			panic(err)
		}
		if _, err := os.Stat(abs); err != nil {
			// The engine moving is a contract break, not a flake — say so.
			panic(fmt.Sprintf("the real decision engine is missing at %s: %v", abs, err))
		}
		realScript = abs

		root, err := os.MkdirTemp("", "delivery-orchestrate-repos-")
		if err != nil {
			panic(err)
		}
		defer os.RemoveAll(root)

		repoDeclared = newScratch(root, "declared", "oauth-user-inspector/infra/app/main.go")
		repoUndeclared = newScratch(root, "undeclared", "docs/notes.md")
		repoExcluded = newScratch(root, "excluded", "oauth-user-inspector/infra/identity/main.go")
		repoGlobalImpact = newScratch(root, "global-impact", "MODULE.bazel")

		return m.Run()
	}())
}

// newScratch builds a repo with two commits: an initial one (the diff base)
// and one that adds `file`. Commit subjects deliberately avoid
// "chore(main): release …" — deploy-affected.sh short-circuits those to
// affected=false and it would mask every other assertion.
func newScratch(root, name, file string) scratch {
	dir := filepath.Join(root, name)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		panic(err)
	}
	mustGit(dir, "-c", "init.defaultBranch=main", "init")
	mustGit(dir, "config", "user.email", "test@example.com")
	mustGit(dir, "config", "user.name", "Test")
	mustWrite(dir, "README.md", "init\n")
	mustGit(dir, "add", ".")
	mustGit(dir, "commit", "-m", "test: initial commit")
	base := mustGit(dir, "rev-parse", "HEAD")

	mustWrite(dir, file, "changed\n")
	mustGit(dir, "add", ".")
	mustGit(dir, "commit", "-m", "test: touch "+file)
	return scratch{dir: dir, base: base}
}

func mustGit(dir string, args ...string) string {
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		panic(fmt.Sprintf("git %v in %s: %v\n%s", args, dir, err, out))
	}
	return strings.TrimSpace(string(out))
}

func mustWrite(dir, rel, content string) {
	p := filepath.Join(dir, rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		panic(err)
	}
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		panic(err)
	}
}

// ---------------------------------------------------------------------------
// the fake bazel, and the harness that drives orchestrate()
// ---------------------------------------------------------------------------

type fakeBazel struct {
	labels    []string // what `bazel query` prints
	binDir    string   // what `bazel info bazel-bin` prints
	failQuery bool
	failBuild bool
}

// install writes the stub and returns its path. It only ever prints: the
// metadata files are pre-written by the test into binDir, so `build` has
// nothing to do but succeed (or fail on demand).
func (f fakeBazel) install(t *testing.T) string {
	t.Helper()
	query := "true"
	if len(f.labels) > 0 {
		query = "printf '%s\\n'"
		for _, l := range f.labels {
			query += " '" + l + "'"
		}
	}
	if f.failQuery {
		query = "echo 'ERROR: package contains errors' >&2; exit 1"
	}
	build := "true"
	if f.failBuild {
		build = "echo 'ERROR: analysis of target failed' >&2; exit 1"
	}
	script := fmt.Sprintf(`#!/usr/bin/env bash
set -uo pipefail
case "${1:-}" in
  query) %s ;;
  build) %s ;;
  info)  echo '%s' ;;
  *) echo "fake bazel: unexpected invocation: $*" >&2; exit 64 ;;
esac
`, query, build, f.binDir)
	p := filepath.Join(t.TempDir(), "fake-bazel")
	if err := os.WriteFile(p, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return p
}

// decl builds the metadata JSON delivery() would emit (tools/delivery/defs.bzl).
func decl(name string, over map[string]any) map[string]any {
	m := map[string]any{
		"schema":             1,
		"name":               name,
		"kind":               "cloud-run",
		"run":                "//" + name + "/infra/app:deploy",
		"build":              "",
		"environments":       []string{"development", "nonproduction", "production"},
		"github_environment": name + "-{env}",
		"promotion":          "release:" + name + "-v",
		"companions":         []string{},
		"extra_paths":        []string{},
		"exclude_paths":      []string{},
		"preflight":          "",
		"package":            name + "/infra/app",
	}
	for k, v := range over {
		m[k] = v
	}
	return m
}

// writeMeta puts a unit's metadata where `bazel build` would have left it, and
// returns the label the fake query should report for it.
func writeMeta(t *testing.T, binDir string, meta map[string]any) string {
	t.Helper()
	pkg, _ := meta["package"].(string)
	name, _ := meta["name"].(string)
	dir := filepath.Join(binDir, filepath.FromSlash(pkg))
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	raw, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, name+".delivery.json"), raw, 0o644); err != nil {
		t.Fatal(err)
	}
	return "//" + pkg + ":" + name + ".delivery_unit"
}

type result struct {
	code     int
	stdout   string
	man      manifest
	manRaw   string
	ghOutput string
}

// outputs parses $GITHUB_OUTPUT into a key->value map (last write wins, as GHA
// itself does).
func (r result) outputs(t *testing.T) map[string]string {
	t.Helper()
	m := map[string]string{}
	for _, line := range strings.Split(r.ghOutput, "\n") {
		if k, v, ok := strings.Cut(line, "="); ok {
			m[k] = v
		}
	}
	return m
}

// harness wires a scratch repo, a fake bazel and the real engine together.
type harness struct {
	repo   scratch
	fake   fakeBazel
	env    map[string]string // overrides merged over the hermetic base env
	script string            // defaults to the real engine
}

func (h harness) run(t *testing.T) result {
	t.Helper()
	work := t.TempDir()
	ghOut := filepath.Join(work, "github_output")
	if err := os.WriteFile(ghOut, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	// A deliberately minimal environment: no ambient DEPLOY_TARGETS,
	// BEFORE_REV or GITHUB_* can reach the engine and fake a verdict, and no
	// user-level git config can change what `git diff` reports.
	env := map[string]string{
		"PATH":              os.Getenv("PATH"),
		"HOME":              work,
		"GIT_CONFIG_GLOBAL": filepath.Join(work, "nonexistent-gitconfig"),
		"GIT_CONFIG_SYSTEM": filepath.Join(work, "nonexistent-gitconfig"),
		"BEFORE_REV":        h.repo.base,
		"GITHUB_OUTPUT":     ghOut,
	}
	for k, v := range h.env {
		if v == "" {
			delete(env, k)
			continue
		}
		env[k] = v
	}
	script := h.script
	if script == "" {
		script = realScript
	}
	var sb strings.Builder
	code := orchestrate(config{
		repoRoot: h.repo.dir,
		script:   script,
		bazel:    h.fake.install(t),
		out:      filepath.Join(work, "delivery-manifest.json"),
		env:      env,
		stdout:   &sb,
	})
	raw, err := os.ReadFile(filepath.Join(work, "delivery-manifest.json"))
	if err != nil {
		t.Fatalf("no manifest written (exit %d):\n%s", code, sb.String())
	}
	var man manifest
	if err := json.Unmarshal(raw, &man); err != nil {
		t.Fatalf("manifest is not valid JSON: %v\n%s", err, raw)
	}
	gh, err := os.ReadFile(ghOut)
	if err != nil {
		t.Fatal(err)
	}
	return result{code: code, stdout: sb.String(), man: man, manRaw: string(raw), ghOutput: string(gh)}
}

// oneUnit is the common shape: a single path-only unit declared over the
// oauth-user-inspector paths, mirroring the real declaration in
// oauth-user-inspector/infra/app/BUILD.
func oneUnit(t *testing.T, over map[string]any) fakeBazel {
	t.Helper()
	bin := t.TempDir()
	base := map[string]any{
		"extra_paths": []string{"oauth-user-inspector/", "tools/deploy/"},
	}
	for k, v := range over {
		base[k] = v
	}
	label := writeMeta(t, bin, decl("oauth-user-inspector", base))
	return fakeBazel{labels: []string{label}, binDir: bin}
}

func requireUnit(t *testing.T, m manifest, name string) manifestUnit {
	t.Helper()
	for _, u := range m.Units {
		if u.Name == name {
			return u
		}
	}
	t.Fatalf("unit %q missing from manifest: %+v", name, m.Units)
	return manifestUnit{}
}

// ---------------------------------------------------------------------------
// happy path — the engine actually decides (spec §5: no failure row)
// ---------------------------------------------------------------------------

// A diff that touches a path the declaration claims must come back affected,
// decided by the real engine in PATH-ONLY mode, and must say so in BOTH the
// manifest and $GITHUB_OUTPUT.
func TestOrchestrate_PathMatch_Affected(t *testing.T) {
	r := harness{repo: repoDeclared, fake: oneUnit(t, nil)}.run(t)

	if r.code != 0 {
		t.Fatalf("exit = %d, want 0\n%s", r.code, r.stdout)
	}
	if r.man.ComputedBy != computedByPaths {
		t.Errorf("manifest computed_by = %q, want %q", r.man.ComputedBy, computedByPaths)
	}
	if r.man.Reason != "" {
		t.Errorf("manifest reason = %q, want empty on a clean decision", r.man.Reason)
	}
	if r.man.Schema != schemaVersion {
		t.Errorf("manifest schema = %d, want %d", r.man.Schema, schemaVersion)
	}
	if r.man.Before != repoDeclared.base {
		t.Errorf("manifest before = %q, want %q", r.man.Before, repoDeclared.base)
	}
	if r.man.Commit == "" {
		t.Error("manifest commit is empty; want the scratch repo's HEAD sha")
	}
	u := requireUnit(t, r.man, "oauth-user-inspector")
	if !u.Affected {
		t.Errorf("unit affected = false, want true (reason %q)", u.Reason)
	}
	if u.ComputedBy != computedByPaths {
		t.Errorf("unit computed_by = %q, want %q", u.ComputedBy, computedByPaths)
	}
	if !strings.Contains(u.Reason, "path matched") {
		t.Errorf("unit reason = %q, want the engine's own 'path matched …' text", u.Reason)
	}
	// The declared shape must survive into the manifest unchanged.
	if u.Kind != "cloud-run" || u.Run != "//oauth-user-inspector/infra/app:deploy" {
		t.Errorf("unit kind/run = %q/%q, want cloud-run///oauth-user-inspector/infra/app:deploy", u.Kind, u.Run)
	}
	if got, want := strings.Join(u.Environments, ","), "development,nonproduction,production"; got != want {
		t.Errorf("unit environments = %q, want %q", got, want)
	}
	if u.GithubEnvironment != "oauth-user-inspector-{env}" {
		t.Errorf("unit github_environment = %q, want the declared pattern", u.GithubEnvironment)
	}

	out := r.outputs(t)
	if out["affected_oauth_user_inspector"] != "true" {
		t.Errorf("GITHUB_OUTPUT affected_oauth_user_inspector = %q, want true\n%s",
			out["affected_oauth_user_inspector"], r.ghOutput)
	}
	// manifest= must be a single line of compact JSON agreeing with the file.
	if strings.Contains(out["manifest"], "\n") {
		t.Error("GITHUB_OUTPUT manifest= spans multiple lines; GHA's key=value form cannot carry that")
	}
	var echoed manifest
	if err := json.Unmarshal([]byte(out["manifest"]), &echoed); err != nil {
		t.Fatalf("GITHUB_OUTPUT manifest= is not JSON: %v (%q)", err, out["manifest"])
	}
	if len(echoed.Units) != 1 || echoed.Units[0].Affected != u.Affected || echoed.ComputedBy != r.man.ComputedBy {
		t.Errorf("GITHUB_OUTPUT manifest disagrees with the file:\n got %+v\nwant %+v", echoed, r.man)
	}
}

// The only way to affected=false: a successfully computed diff that matches
// nothing the unit declared.
func TestOrchestrate_NoPathMatch_NotAffected(t *testing.T) {
	r := harness{repo: repoUndeclared, fake: oneUnit(t, nil)}.run(t)

	if r.code != 0 {
		t.Fatalf("exit = %d, want 0\n%s", r.code, r.stdout)
	}
	if r.man.ComputedBy != computedByPaths {
		t.Errorf("manifest computed_by = %q, want %q", r.man.ComputedBy, computedByPaths)
	}
	u := requireUnit(t, r.man, "oauth-user-inspector")
	if u.Affected {
		t.Errorf("unit affected = true, want false (reason %q)", u.Reason)
	}
	if out := r.outputs(t); out["affected_oauth_user_inspector"] != "false" {
		t.Errorf("GITHUB_OUTPUT affected_oauth_user_inspector = %q, want false\n%s",
			out["affected_oauth_user_inspector"], r.ghOutput)
	}
}

// exclude_paths must reach the engine as EXCLUDE_PATH_REGEX: a file matching
// extra_paths but also exclude_paths is dropped before the match test, so the
// unit is NOT affected. Without the plumbing this diff reads as affected=true.
func TestOrchestrate_ExcludePaths_Respected(t *testing.T) {
	fake := oneUnit(t, map[string]any{
		"extra_paths":   []string{"oauth-user-inspector/"},
		"exclude_paths": []string{"oauth-user-inspector/infra/identity/"},
	})
	r := harness{repo: repoExcluded, fake: fake}.run(t)

	if r.code != 0 {
		t.Fatalf("exit = %d, want 0\n%s", r.code, r.stdout)
	}
	u := requireUnit(t, r.man, "oauth-user-inspector")
	if u.Affected {
		t.Errorf("unit affected = true, want false — exclude_paths did not reach EXCLUDE_PATH_REGEX (reason %q)", u.Reason)
	}
	if u.ComputedBy != computedByPaths {
		t.Errorf("unit computed_by = %q, want %q", u.ComputedBy, computedByPaths)
	}
}

// A unit with a `build` target runs in GRAPH mode. Proving DEPLOY_TARGETS was
// really exported (rather than just labelling the row "graph") without running
// target-determinator: MODULE.bazel trips deploy-affected.sh's global-impact
// guard, which is reachable ONLY past the `[ -z DEPLOY_TARGETS ]` early exit.
// With DEPLOY_TARGETS unset this same diff would return
// "no path matched (path-only mode …)" and affected=false.
func TestOrchestrate_GraphMode_ExportsDeployTargets(t *testing.T) {
	fake := oneUnit(t, map[string]any{
		"build":       "//oauth-user-inspector:image",
		"extra_paths": []string{"oauth-user-inspector/"},
	})
	r := harness{repo: repoGlobalImpact, fake: fake}.run(t)

	if r.code != 0 {
		t.Fatalf("exit = %d, want 0\n%s", r.code, r.stdout)
	}
	u := requireUnit(t, r.man, "oauth-user-inspector")
	if u.ComputedBy != computedByGraph {
		t.Errorf("unit computed_by = %q, want %q", u.ComputedBy, computedByGraph)
	}
	if !u.Affected || !strings.Contains(u.Reason, "global-impact") {
		t.Errorf("unit affected/reason = %t/%q, want true/'global-impact file changed' — "+
			"the engine never got past its path-only early exit, so DEPLOY_TARGETS was not exported",
			u.Affected, u.Reason)
	}
	if r.man.ComputedBy != computedByGraph {
		t.Errorf("manifest computed_by = %q, want %q", r.man.ComputedBy, computedByGraph)
	}
}

// A unit with DECLARED graph_targets runs in GRAPH mode even though it has no
// `build` target — the tabula shape: two units share one build job, so neither
// declares `build`, while both must be attributed against the API image AND
// the extension bundle (the `deploy-targets:` its hand-written gate passes).
//
// Same proof technique as the test above: MODULE.bazel trips the engine's
// global-impact guard, which is reachable ONLY past the `[ -z DEPLOY_TARGETS ]`
// early exit. With graph_targets ignored this diff comes back
// "no path matched (path-only mode ...)" and affected=false, so a pass here is
// evidence the declared universe really reached the engine.
func TestOrchestrate_GraphTargets_ExportDeployTargets(t *testing.T) {
	bin := t.TempDir()
	label := writeMeta(t, bin, decl("tabula-api", map[string]any{
		"build":         "",
		"shared_build":  "tabula",
		"graph_targets": []string{"//tabula/api:image_push", "//tabula/extension:chrome_zip"},
		"extra_paths":   []string{"tabula/infra/app/"},
	}))
	r := harness{repo: repoGlobalImpact, fake: fakeBazel{labels: []string{label}, binDir: bin}}.run(t)

	if r.code != 0 {
		t.Fatalf("exit = %d, want 0\n%s", r.code, r.stdout)
	}
	u := requireUnit(t, r.man, "tabula-api")
	if u.ComputedBy != computedByGraph {
		t.Errorf("unit computed_by = %q, want %q — graph_targets did not select graph mode", u.ComputedBy, computedByGraph)
	}
	if !u.Affected || !strings.Contains(u.Reason, "global-impact") {
		t.Errorf("unit affected/reason = %t/%q, want true/'global-impact file changed' — "+
			"the engine never got past its path-only early exit, so the declared DEPLOY_TARGETS was not exported",
			u.Affected, u.Reason)
	}
}

// ...and the exported universe must be the DECLARED one, not the build+run
// derivation. The test above proves DEPLOY_TARGETS was non-empty; this one
// reads its VALUE, through a stub engine that echoes it back. Attributing
// tabula's diff against `//tabula/infra/app:deploy` alone would miss every
// commit that only moves the extension bundle — a real under-delivery, which
// is the one direction this system is not allowed to fail in.
func TestDecide_ExportsTheDeclaredGraphUniverse(t *testing.T) {
	dir := t.TempDir()
	stub := filepath.Join(dir, "engine.sh")
	if err := os.WriteFile(stub, []byte(`#!/usr/bin/env bash
echo "stub-engine: DEPLOY_TARGETS=[${DEPLOY_TARGETS-<unset>}]"
echo "deploy-affected: affected=false (stub)"
echo "affected=false" >> "$GITHUB_OUTPUT"
`), 0o755); err != nil {
		t.Fatal(err)
	}

	for _, tc := range []struct {
		name string
		meta unitMeta
		want string
	}{
		{
			name: "declared graph_targets win",
			meta: unitMeta{
				Name:         "tabula-api",
				Run:          "//tabula/infra/app:deploy",
				GraphTargets: []string{"//tabula/api:image_push", "//tabula/extension:chrome_zip"},
			},
			want: "DEPLOY_TARGETS=[//tabula/api:image_push //tabula/extension:chrome_zip]",
		},
		{
			name: "build target derivation, unchanged",
			meta: unitMeta{
				Name:  "app",
				Run:   "//app/infra:deploy",
				Build: "//app:image",
			},
			want: "DEPLOY_TARGETS=[//app:image //app/infra:deploy]",
		},
		{
			name: "neither: path-only mode leaves it UNSET",
			meta: unitMeta{Name: "app", Run: "//app/infra:deploy"},
			want: "DEPLOY_TARGETS=[<unset>]",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var out bytes.Buffer
			cfg := config{
				repoRoot: dir,
				script:   stub,
				env:      map[string]string{"PATH": os.Getenv("PATH")},
				stdout:   &out,
			}
			if _, _, _, err := decide(cfg, "HEAD~1", tc.meta); err != nil {
				t.Fatalf("decide: %v\n%s", err, out.String())
			}
			if !strings.Contains(out.String(), tc.want) {
				t.Errorf("engine env is wrong: want a line containing %q\n%s", tc.want, out.String())
			}
		})
	}
}

// Units are decided independently: one manifest, two different verdicts.
func TestOrchestrate_TwoUnits_IndependentVerdicts(t *testing.T) {
	bin := t.TempDir()
	hit := writeMeta(t, bin, decl("oauth-user-inspector", map[string]any{
		"extra_paths": []string{"oauth-user-inspector/"},
	}))
	miss := writeMeta(t, bin, decl("tabula-api", map[string]any{
		"extra_paths": []string{"tabula/api/"},
	}))
	r := harness{repo: repoDeclared, fake: fakeBazel{labels: []string{hit, miss}, binDir: bin}}.run(t)

	if r.code != 0 {
		t.Fatalf("exit = %d, want 0\n%s", r.code, r.stdout)
	}
	if got := requireUnit(t, r.man, "oauth-user-inspector"); !got.Affected {
		t.Errorf("oauth-user-inspector affected = false, want true")
	}
	if got := requireUnit(t, r.man, "tabula-api"); got.Affected {
		t.Errorf("tabula-api affected = true, want false")
	}
	out := r.outputs(t)
	if out["affected_oauth_user_inspector"] != "true" || out["affected_tabula_api"] != "false" {
		t.Errorf("per-unit GITHUB_OUTPUTs wrong:\n%s", r.ghOutput)
	}
}

// ---------------------------------------------------------------------------
// spec §5, row 1: "Orchestrator can't compute → fail-open, all units affected,
// loud computed_by: fail-open annotation"
// ---------------------------------------------------------------------------

// assertFailOpen is the shared assertion for every uncertainty row: exit 0,
// computed_by fail-open with a reason, every listed unit affected, and a
// ::warning:: in the run log.
func assertFailOpen(t *testing.T, r result, wantReason string) {
	t.Helper()
	if r.code != 0 {
		t.Fatalf("exit = %d, want 0 — a detection problem must never redden CI\n%s", r.code, r.stdout)
	}
	if r.man.ComputedBy != computedByFailOpen {
		t.Errorf("manifest computed_by = %q, want %q", r.man.ComputedBy, computedByFailOpen)
	}
	if r.man.Reason == "" {
		t.Error("manifest reason is empty; a fail-open that does not say why is a silent one")
	}
	if wantReason != "" && !strings.Contains(r.man.Reason, wantReason) {
		t.Errorf("manifest reason = %q, want it to mention %q", r.man.Reason, wantReason)
	}
	for _, u := range r.man.Units {
		if !u.Affected {
			t.Errorf("unit %q affected = false under fail-open; every unit must be affected", u.Name)
		}
		if u.ComputedBy != computedByFailOpen {
			t.Errorf("unit %q computed_by = %q, want %q", u.Name, u.ComputedBy, computedByFailOpen)
		}
	}
	if !strings.Contains(r.stdout, "::warning title=delivery-orchestrator-fail-open::") {
		t.Errorf("no ::warning:: annotation in the run log; the fail-open is invisible\n%s", r.stdout)
	}
}

// An unresolvable BEFORE_REV means there is no trustworthy diff.
func TestOrchestrate_UnresolvableBeforeRev_FailsOpen(t *testing.T) {
	r := harness{
		repo: repoUndeclared, // a diff that WOULD have said affected=false
		fake: oneUnit(t, nil),
		env:  map[string]string{"BEFORE_REV": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"},
	}.run(t)

	assertFailOpen(t, r, "does not resolve to a commit")
	u := requireUnit(t, r.man, "oauth-user-inspector")
	if !u.Affected {
		t.Error("the unit that would have been false must flip to affected under fail-open")
	}
	if out := r.outputs(t); out["affected_oauth_user_inspector"] != "true" {
		t.Errorf("GITHUB_OUTPUT affected_oauth_user_inspector = %q, want true\n%s",
			out["affected_oauth_user_inspector"], r.ghOutput)
	}
}

// Neither BEFORE_REV nor BASE_REF set: nothing to diff against.
func TestOrchestrate_NoBaseAtAll_FailsOpen(t *testing.T) {
	r := harness{
		repo: repoUndeclared,
		fake: oneUnit(t, nil),
		env:  map[string]string{"BEFORE_REV": "", "BASE_REF": ""},
	}.run(t)
	assertFailOpen(t, r, "neither BEFORE_REV nor BASE_REF")
}

// BASE_REF is the documented fallback when BEFORE_REV is absent — it must
// actually be used, not merely tolerated.
func TestOrchestrate_BaseRefFallback_Decides(t *testing.T) {
	r := harness{
		repo: repoDeclared,
		fake: oneUnit(t, nil),
		env:  map[string]string{"BEFORE_REV": "", "BASE_REF": repoDeclared.base},
	}.run(t)

	if r.man.ComputedBy != computedByPaths {
		t.Fatalf("manifest computed_by = %q, want %q (BASE_REF was ignored)\n%s",
			r.man.ComputedBy, computedByPaths, r.stdout)
	}
	if r.man.Before != repoDeclared.base {
		t.Errorf("manifest before = %q, want the BASE_REF value %q", r.man.Before, repoDeclared.base)
	}
	if u := requireUnit(t, r.man, "oauth-user-inspector"); !u.Affected {
		t.Error("unit affected = false, want true")
	}
}

// A forced push destroys the diff base's meaning (spec §4.2).
func TestOrchestrate_ForcedPush_FailsOpen(t *testing.T) {
	r := harness{
		repo: repoUndeclared,
		fake: oneUnit(t, nil),
		env:  map[string]string{"FORCED_PUSH": "true"},
	}.run(t)
	assertFailOpen(t, r, "forced push")
}

// Discovery failure #1: the query itself fails (a BUILD error anywhere in the
// universe). No units are known, so the manifest is legitimately short — the
// top-level fail-open is what consumers must key on.
func TestOrchestrate_BazelQueryFails_FailsOpen(t *testing.T) {
	fake := oneUnit(t, nil)
	fake.failQuery = true
	r := harness{repo: repoUndeclared, fake: fake}.run(t)

	assertFailOpen(t, r, "bazel query")
	if len(r.man.Units) != 0 {
		t.Errorf("units = %+v, want none — the query never told us any", r.man.Units)
	}
}

// Discovery failure #2: the query worked, the build did not. The unit labels
// ARE known here, so every one of them must still appear, affected.
func TestOrchestrate_BazelBuildFails_FailsOpen(t *testing.T) {
	fake := oneUnit(t, nil)
	fake.failBuild = true
	r := harness{repo: repoUndeclared, fake: fake}.run(t)

	assertFailOpen(t, r, "bazel build")
	u := requireUnit(t, r.man, "oauth-user-inspector")
	if !u.Affected {
		t.Error("unit affected = false, want true")
	}
	if out := r.outputs(t); out["affected_oauth_user_inspector"] != "true" {
		t.Errorf("GITHUB_OUTPUT affected_oauth_user_inspector = %q, want true\n%s",
			out["affected_oauth_user_inspector"], r.ghOutput)
	}
}

// Discovery failure #3: the metadata is on disk but unreadable as a unit. The
// unit must NOT vanish — an absent unit reads as "not affected" downstream,
// which is precisely the silent under-delivery the invariant forbids.
func TestOrchestrate_MetadataUnparsable_FailsOpen(t *testing.T) {
	bin := t.TempDir()
	label := writeMeta(t, bin, decl("oauth-user-inspector", nil))
	broken := filepath.Join(bin, "oauth-user-inspector", "infra", "app", "oauth-user-inspector.delivery.json")
	if err := os.WriteFile(broken, []byte("{ this is not json"), 0o644); err != nil {
		t.Fatal(err)
	}
	r := harness{repo: repoUndeclared, fake: fakeBazel{labels: []string{label}, binDir: bin}}.run(t)

	assertFailOpen(t, r, "unreadable")
	// The name is recovered from the label, so the unit is still nameable.
	u := requireUnit(t, r.man, "oauth-user-inspector")
	if !u.Affected {
		t.Error("unit affected = false, want true")
	}
}

// Discovery failure #4: the metadata file the label promises is simply absent.
func TestOrchestrate_MetadataMissing_FailsOpen(t *testing.T) {
	bin := t.TempDir()
	r := harness{
		repo: repoUndeclared,
		fake: fakeBazel{labels: []string{"//some/pkg:ghost.delivery_unit"}, binDir: bin},
	}.run(t)

	assertFailOpen(t, r, "unreadable")
	u := requireUnit(t, r.man, "ghost")
	if !u.Affected {
		t.Error("unit affected = false, want true")
	}
	// The filegroup label is not a delivery target; a placeholder must not
	// present it as one.
	if u.Run != "" {
		t.Errorf("placeholder run = %q, want empty — that label delivers nothing", u.Run)
	}
	if !strings.Contains(r.man.Reason, "//some/pkg:ghost.delivery_unit") {
		t.Errorf("reason = %q, want it to name the label whose metadata was missing", r.man.Reason)
	}
}

// The engine itself refusing to run (here: its own guard against a path-only
// unit with no path signal at all — deploy-affected.sh:107) is an uncertainty,
// not a verdict. It must fail the WHOLE manifest open, not just that row.
func TestOrchestrate_EngineNonZero_FailsOpen(t *testing.T) {
	bin := t.TempDir()
	// A second, perfectly decidable unit proves the failure is not contained
	// to the offending row.
	fine := writeMeta(t, bin, decl("tabula-api", map[string]any{"extra_paths": []string{"tabula/api/"}}))
	broken := writeMeta(t, bin, decl("no-signal", map[string]any{"extra_paths": []string{}}))
	r := harness{repo: repoUndeclared, fake: fakeBazel{labels: []string{fine, broken}, binDir: bin}}.run(t)

	assertFailOpen(t, r, "exited non-zero")
	if u := requireUnit(t, r.man, "tabula-api"); !u.Affected {
		t.Error("tabula-api affected = false; a sibling unit's engine failure must flip it too")
	}
	if u := requireUnit(t, r.man, "no-signal"); !u.Affected {
		t.Error("no-signal affected = false, want true")
	}
}

// An empty universe is NOT an uncertainty: nothing is declared, so there is
// nothing to be wrong about. This must stay a clean manifest, or the very
// first commit of Phase 0 would fail open on every push forever.
func TestOrchestrate_EmptyUniverse_IsNotFailOpen(t *testing.T) {
	r := harness{repo: repoUndeclared, fake: fakeBazel{binDir: t.TempDir()}}.run(t)

	if r.code != 0 {
		t.Fatalf("exit = %d, want 0\n%s", r.code, r.stdout)
	}
	if r.man.ComputedBy == computedByFailOpen {
		t.Errorf("computed_by = %q, want a clean verdict for an empty universe (reason %q)",
			r.man.ComputedBy, r.man.Reason)
	}
	if len(r.man.Units) != 0 {
		t.Errorf("units = %+v, want none", r.man.Units)
	}
	if !strings.Contains(r.manRaw, `"units": []`) {
		t.Errorf("units serialized as null rather than []; consumers do fromJSON(...).units\n%s", r.manRaw)
	}
}

// ---------------------------------------------------------------------------
// pure helpers
// ---------------------------------------------------------------------------

func TestMetadataRelPath(t *testing.T) {
	tests := []struct {
		label string
		want  string
	}{
		{
			"//oauth-user-inspector/infra/app:oauth-user-inspector.delivery_unit",
			"oauth-user-inspector/infra/app/oauth-user-inspector.delivery.json",
		},
		{"@//a/b:c.delivery_unit", "a/b/c.delivery.json"},
		{"@@//a/b:c.delivery_unit", "a/b/c.delivery.json"},
		// A tagged target that ignores the macro's naming still resolves to
		// *a* path; it will simply not exist, which is a fail-open.
		{"//a/b:weird", "a/b/weird.delivery.json"},
	}
	for _, tc := range tests {
		got, err := metadataRelPath(tc.label)
		if err != nil {
			t.Errorf("metadataRelPath(%q) errored: %v", tc.label, err)
			continue
		}
		if got != tc.want {
			t.Errorf("metadataRelPath(%q) = %q, want %q", tc.label, got, tc.want)
		}
	}
}

func TestUnitNameFromLabel(t *testing.T) {
	tests := map[string]string{
		"//oauth-user-inspector/infra/app:oauth-user-inspector.delivery_unit": "oauth-user-inspector",
		"//a/b:c.delivery_unit": "c",
	}
	for in, want := range tests {
		if got := unitNameFromLabel(in); got != want {
			t.Errorf("unitNameFromLabel(%q) = %q, want %q", in, got, want)
		}
	}
}

// The unit-name -> output-key rule is a CROSS-BINARY CONTRACT with
// //tools/delivery/gen, which renders the `if:` that reads these keys. This
// table is duplicated verbatim there (TestOutputVarNameIsTheOrchestratorContract)
// because a shared Go package cannot compile under both bazel and plain `go`
// in this repo — see outputVarName's comment. A one-sided change to either
// sanitizer fails its own package's test.
func TestOutputVarName(t *testing.T) {
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

// The engine's env is an allowlist precisely so DEPLOY_TARGETS cannot be
// inherited: an inherited value would silently switch a path-only unit into
// graph mode and make it consult target-determinator over the wrong universe.
func TestEngineEnv_DoesNotInheritDeployTargets(t *testing.T) {
	cfg := config{env: map[string]string{
		"PATH":             "/usr/bin",
		"DEPLOY_TARGETS":   "//leaked:target",
		"SOME_OTHER_THING": "x",
	}}
	for _, kv := range engineEnv(cfg, map[string]string{"BEFORE_REV": "abc"}) {
		if strings.HasPrefix(kv, "DEPLOY_TARGETS=") {
			t.Fatalf("DEPLOY_TARGETS leaked into the engine env: %q", kv)
		}
		if strings.HasPrefix(kv, "SOME_OTHER_THING=") {
			t.Errorf("non-allowlisted %q reached the engine env", kv)
		}
	}
}

// --- per-unit durable bases (#1842) ------------------------------------------
//
// Run-level `success` is not a faithful proxy for "everything in this range was
// delivered": a run whose delivery jobs were all SKIPPED still concludes success
// and still becomes the base, so a wrongly-skipped unit's commits fall outside
// every future diff. UNIT_BASES_JSON lets tools/ci/resolve-unit-bases.sh hand the
// engine a per-unit base instead. These prove the plumbing is real and that every
// failure of it degrades to today's single-base behaviour.

func headOf(t *testing.T, dir string) string {
	t.Helper()
	cmd := exec.Command("git", "rev-parse", "HEAD")
	cmd.Dir = dir
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("git rev-parse HEAD in %s: %v", dir, err)
	}
	return strings.TrimSpace(string(out))
}

func TestOrchestrate_PerUnitBase_OverridesTheSingleBase(t *testing.T) {
	head := headOf(t, repoDeclared.dir)
	// repoDeclared is affected against its own base. Pinning the unit at HEAD
	// empties its diff, so the verdict must flip — which it can only do if the
	// per-unit base actually reached the engine.
	r := harness{
		repo: repoDeclared,
		fake: oneUnit(t, nil),
		env:  map[string]string{"UNIT_BASES_JSON": `{"oauth-user-inspector":"` + head + `"}`},
	}.run(t)

	if r.code != 0 {
		t.Fatalf("exit = %d, want 0\n%s", r.code, r.stdout)
	}
	u := requireUnit(t, r.man, "oauth-user-inspector")
	if u.Affected {
		t.Errorf("unit affected = true, want false: the per-unit base did not reach the engine (reason %q)", u.Reason)
	}
	if u.Base != head {
		t.Errorf("unit base = %q, want the per-unit base %q", u.Base, head)
	}
	// The manifest-level base still reports the single base it was given.
	if r.man.Before != repoDeclared.base {
		t.Errorf("manifest before = %q, want the single base %q", r.man.Before, repoDeclared.base)
	}
}

func TestOrchestrate_PerUnitBase_UnresolvableFallsBackToTheSingleBase(t *testing.T) {
	r := harness{
		repo: repoDeclared,
		fake: oneUnit(t, nil),
		env: map[string]string{
			"UNIT_BASES_JSON": `{"oauth-user-inspector":"0000000000000000000000000000000000000000"}`,
		},
	}.run(t)

	if r.code != 0 {
		t.Fatalf("exit = %d, want 0\n%s", r.code, r.stdout)
	}
	u := requireUnit(t, r.man, "oauth-user-inspector")
	// A base that does not resolve must NOT fail the unit open and must NOT be
	// used: it degrades to exactly today's behaviour.
	if !u.Affected {
		t.Errorf("unit affected = false, want true after falling back to the single base (reason %q)", u.Reason)
	}
	if u.Base != repoDeclared.base {
		t.Errorf("unit base = %q, want the single base %q", u.Base, repoDeclared.base)
	}
}

func TestOrchestrate_PerUnitBase_MalformedJSONIsIgnored(t *testing.T) {
	r := harness{
		repo: repoDeclared,
		fake: oneUnit(t, nil),
		env:  map[string]string{"UNIT_BASES_JSON": "{not json"},
	}.run(t)

	if r.code != 0 {
		t.Fatalf("exit = %d, want 0\n%s", r.code, r.stdout)
	}
	u := requireUnit(t, r.man, "oauth-user-inspector")
	if !u.Affected {
		t.Errorf("unit affected = false, want true: malformed input must cost nothing (reason %q)", u.Reason)
	}
	if u.Base != repoDeclared.base {
		t.Errorf("unit base = %q, want the single base %q", u.Base, repoDeclared.base)
	}
}
