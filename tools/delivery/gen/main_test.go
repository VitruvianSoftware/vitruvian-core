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

const goldenPath = "testdata/golden.delivery.yaml"

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
	got := render(loadFixtures(t), 0)

	if os.Getenv("GEN_UPDATE_GOLDEN") == "1" {
		if err := os.WriteFile(goldenPath, []byte(got), 0o644); err != nil {
			t.Fatalf("update golden: %v", err)
		}
		t.Log("golden updated; re-run without GEN_UPDATE_GOLDEN to assert")
		return
	}

	want, err := os.ReadFile(goldenPath)
	if err != nil {
		t.Fatalf("read golden: %v (run with GEN_UPDATE_GOLDEN=1 to create it)", err)
	}
	if got != string(want) {
		t.Errorf("rendered Phase 0 workflow does not match %s\n%s", goldenPath, firstDiff(string(want), got))
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
	if render(forward, 0) != render(reversed, 0) {
		t.Error("render output depends on input order — units are not sorted by name")
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
	got := render(loadFixtures(t), 0)
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
	got := render(units, 0)

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

// TestPhase1RendersPerUnitJobs exercises the code behind the phase flag.
//
// PROVES: the Phase 1 fan-out renderer exists, is reachable, and is gated by
// --phase — so promoting to Phase 1 is a flag flip plus a regenerate whose
// diff a human reviews, not a fresh, untested renderer written under incident
// pressure. Also proves the ladder is CHAINED (nonproduction needs
// development), which is the property that stops an env skipping ahead.
func TestPhase1RendersPerUnitJobs(t *testing.T) {
	units := loadFixtures(t)
	got := render(units, 1)

	for _, u := range units {
		for _, env := range u.Environments {
			id := u.Name + "-" + env
			if !strings.Contains(got, "\n  "+id+":\n") {
				t.Errorf("phase 1: missing job %q", id)
			}
		}
		if !strings.Contains(got, "needs: [orchestrate, "+u.Name+"-development]") {
			t.Errorf("phase 1: %s ladder is not chained after development", u.Name)
		}
		if !strings.Contains(got, "bazel run "+u.Run) {
			t.Errorf("phase 1: %s never invokes its run target %s", u.Name, u.Run)
		}
	}
	// The kill switch must gate the fan-out too, or rollback level 1 would stop
	// the manifest while still deploying.
	if !strings.Contains(got, killSwitchExpr+" && needs.orchestrate.outputs.affected_") {
		t.Error("phase 1: per-unit jobs are not gated on the kill switch")
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
	content := render(loadFixtures(t), 0)

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
