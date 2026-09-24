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
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// The shape `bazel query --output=graph --graph:factored=false` prints. The
// path from //app:test to //shared:lib goes THROUGH an external repo, which
// the walk must follow.
const sampleDot = `digraph mygraph {
  node [shape=box];
  "//app:test"
  "//app:test" -> "//app:lib"
  "//app:lib" -> "@rules_x//:wrapper"
  "@rules_x//:wrapper" -> "//shared:lib"
  "//other:test"
  "//other:test" -> "//other:lib"
  "//shared:lib"
  "//other:lib"
}
`

func TestParseGraphEdges(t *testing.T) {
	edges, err := ParseGraphEdges(sampleDot)
	if err != nil {
		t.Fatal(err)
	}
	if got := edges["@rules_x//:wrapper"]; !reflect.DeepEqual(got, []string{"//shared:lib"}) {
		t.Errorf("wrapper deps = %v", got)
	}
	if _, ok := edges["//shared:lib"]; !ok {
		t.Error("node-only line must register the node")
	}

	// A factored graph merges nodes into "a\nb" and would silently lose edges.
	if _, err := ParseGraphEdges(`"//a:x\n//a:y" -> "//b:z"`); err == nil {
		t.Error("factored graph must be rejected")
	}
}

func TestComputeRdepsMapFollowsExternalRepos(t *testing.T) {
	edges, _ := ParseGraphEdges(sampleDot)
	m := ComputeRdepsMap("abc", []string{"//app:test", "//other:test"}, edges, []string{"app", "other", "shared", "unused"})

	want := map[string][]string{
		"app":    {"//app:test"},
		"shared": {"//app:test"},
		"other":  {"//other:test"},
	}
	if !reflect.DeepEqual(m.Tests, want) {
		t.Errorf("Tests = %v, want %v", m.Tests, want)
	}
}

func TestLookup(t *testing.T) {
	edges, _ := ParseGraphEdges(sampleDot)
	m := ComputeRdepsMap("abc", []string{"//app:test", "//other:test"}, edges, []string{"app", "other", "shared", "unused"})

	got, ok := m.Lookup([]string{"//shared:all", "//other:all"})
	if !ok || !reflect.DeepEqual(got, []string{"//app:test", "//other:test"}) {
		t.Errorf("Lookup = %v, %v", got, ok)
	}
	// Known package that no test depends on: a valid, empty answer.
	if got, ok := m.Lookup([]string{"//unused:all"}); !ok || len(got) != 0 {
		t.Errorf("unused package: %v, %v", got, ok)
	}
	// A package the map has never seen (added in the PR): not trustworthy.
	if _, ok := m.Lookup([]string{"//shared:all", "//brand/new:all"}); ok {
		t.Error("an unknown package must make Lookup report !ok")
	}
}

func TestLoadRdepsMap(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "map.json")

	if m, err := LoadRdepsMap(path, "abc"); m != nil || err != nil {
		t.Errorf("missing file: want (nil, nil), got (%v, %v)", m, err)
	}

	write := func(m RdepsMap) {
		data, _ := json.Marshal(m)
		if err := os.WriteFile(path, data, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	good := RdepsMap{Schema: RdepsMapSchema, Commit: "abc", Packages: []string{"app"}}

	write(good)
	if m, err := LoadRdepsMap(path, "abc"); err != nil || m == nil {
		t.Errorf("valid map rejected: %v", err)
	}
	if _, err := LoadRdepsMap(path, "def"); err == nil {
		t.Error("a map for another commit must be rejected")
	}
	if _, err := LoadRdepsMap(path, ""); err == nil {
		t.Error("an unresolved diff base must reject the map")
	}
	stale := good
	stale.Schema = RdepsMapSchema + 1
	write(stale)
	if _, err := LoadRdepsMap(path, "abc"); err == nil {
		t.Error("a map with another schema must be rejected")
	}
}

func TestInternalQueryErrors(t *testing.T) {
	root := "/home/runner/work/repo/repo"
	stderr := strings.Join([]string{
		"Loading: 5322 packages loaded",
		// Seen in real runs: an Android SDK target missing inside an external repo.
		"ERROR: /home/runner/.bazel/external/rules_android+/tools/jdk/BUILD:86:27: no such target '@@rules_android++android_sdk_repository_extension+androidsdk//:core-for-system-modules-jar'",
		"ERROR: no such package '@@some_repo//': fetch failed",
		`ERROR: Evaluation of query "rdeps(//..., set(//a:all))" failed: errors were encountered while computing transitive closure`,
	}, "\n")
	if bad := internalQueryErrors(stderr, root); len(bad) != 0 {
		t.Errorf("external-only errors flagged as internal: %v", bad)
	}

	for _, line := range []string{
		"ERROR: " + root + "/apps/x/BUILD:3:1: no such target '//apps/y:z'",
		"ERROR: Skipping '//apps/x': no such package",
		"ERROR: something bazel has never printed before",
	} {
		if bad := internalQueryErrors(line, root); len(bad) != 1 {
			t.Errorf("must count as internal: %q", line)
		}
	}
}

// With a valid map covering every changed package, the planner must not run
// a live query at all (the runner here fails if it is called).
func TestComputePlanUsesMap(t *testing.T) {
	repo := t.TempDir()
	for _, dir := range []string{"shared", "app", "app/sub"} {
		if err := os.MkdirAll(filepath.Join(repo, dir), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	writeFile(t, filepath.Join(repo, "shared", "BUILD"), "")
	writeFile(t, filepath.Join(repo, "app", "BUILD"), `pipeline_unit(
    name = "app",
    test_targets = [":test"],
)
`)
	writeFile(t, filepath.Join(repo, "app", "sub", "BUILD"), "")

	edges, _ := ParseGraphEdges(sampleDot)
	m := ComputeRdepsMap("abc", []string{"//app:test"}, edges, []string{"app", "app/sub", "shared"})

	e := NewEngine(repo, &mockQueryRunner{shouldErr: true})
	e.RdepsMap = m

	p, err := e.ComputePlan(context.Background(), []string{"shared/lib.go"}, "abc", "HEAD")
	if err != nil {
		t.Fatal(err)
	}
	if p.IsDegraded || p.PlanSource != PlanSourceMap {
		t.Fatalf("want map-sourced plan, got source=%q degraded=%v (%s)", p.PlanSource, p.IsDegraded, p.SweepReason)
	}
	if len(p.Matrix) != 1 || p.Matrix[0].Name != "app" {
		t.Errorf("shared/ feeds app's test through an external repo; want [app], got %+v", p.Matrix)
	}

	// A new test in app/sub is unknown to the map. app/sub is inside the
	// unit's package, so the unit must still run.
	p, err = e.ComputePlan(context.Background(), []string{"app/sub/new_test.go"}, "abc", "HEAD")
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Matrix) != 1 || p.Matrix[0].Name != "app" {
		t.Errorf("change inside the unit's package must select it; got %+v", p.Matrix)
	}

	// A package the map does not know: fall back to the live query, which
	// this runner fails -> degraded full sweep, never a silent skip.
	if err := os.MkdirAll(filepath.Join(repo, "brandnew"), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(repo, "brandnew", "BUILD"), "")
	p, err = e.ComputePlan(context.Background(), []string{"brandnew/x.go"}, "abc", "HEAD")
	if err != nil {
		t.Fatal(err)
	}
	if p.PlanSource != PlanSourceLive || !p.IsDegraded {
		t.Errorf("unknown package must use the live query; got source=%q degraded=%v", p.PlanSource, p.IsDegraded)
	}
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
