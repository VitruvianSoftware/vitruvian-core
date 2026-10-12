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
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// The planner used to read a pipeline_unit call up to the first ")" and a
// list up to the first "]". Anything that put one of those inside the call --
// a comment, a string, a nested expression -- cut the call short, and the
// unit came out with no test targets and the default runner. Nothing failed:
// the unit was simply never selected through a dependency. These tests are
// the shapes that did it, and the shapes that must stay loud.

func mustReadUnits(t *testing.T, build, pkg string) []PipelineUnitDefinition {
	t.Helper()
	units, err := parsePipelineUnitsFromBuild(build, pkg)
	if err != nil {
		t.Fatalf("reading units: %v", err)
	}
	return units
}

func wantTargets(t *testing.T, u PipelineUnitDefinition, want ...string) {
	t.Helper()
	if !reflect.DeepEqual(u.TestTargets, want) {
		t.Errorf("unit %q: test targets = %q, want %q", u.Name, u.TestTargets, want)
	}
}

func TestUnitWithBracketInComment(t *testing.T) {
	units := mustReadUnits(t, `
pipeline_unit(
    name = "u",
    # Built with strict checking (see REFACTOR.md 6zu), so the log is long.
    runner = "xcode-27",
    test_targets = [
        ":a",
        ":b",
    ],
    timeout_minutes = 60,
)
`, "pkg")
	if len(units) != 1 {
		t.Fatalf("got %d units, want 1", len(units))
	}
	wantTargets(t, units[0], "//pkg:a", "//pkg:b")
	if units[0].Runner != "xcode-27" || units[0].TimeoutMinutes != 60 {
		t.Errorf("runner = %q, timeout = %d; the attributes after the comment were lost", units[0].Runner, units[0].TimeoutMinutes)
	}
}

func TestUnitWithBracketInString(t *testing.T) {
	units := mustReadUnits(t, `
pipeline_unit(
    name = "u",
    build_flags = ["--test_arg=f(1)]"],
    env = {"NOTE": 'say "hi") }'},
    runner = "xcode-27",
    test_targets = [":a"],
)
`, "pkg")
	if len(units) != 1 {
		t.Fatalf("got %d units, want 1", len(units))
	}
	wantTargets(t, units[0], "//pkg:a")
	if units[0].Runner != "xcode-27" {
		t.Errorf("runner = %q, want xcode-27", units[0].Runner)
	}
}

func TestUnitWithTripleQuotedString(t *testing.T) {
	units := mustReadUnits(t, `
pipeline_unit(
    name = "u",
    env = {"NOTE": """two lines )
and a "quote" ] and an escaped \""" inside"""},
    test_targets = [":a"],
    tier = "L2",
)
`, "pkg")
	if len(units) != 1 {
		t.Fatalf("got %d units, want 1", len(units))
	}
	wantTargets(t, units[0], "//pkg:a")
	if units[0].Tier != "L2" {
		t.Errorf("tier = %q, want L2", units[0].Tier)
	}
}

func TestUnitWithNestedCalls(t *testing.T) {
	units := mustReadUnits(t, `
pipeline_unit(
    name = "u",
    tags = glob(["*.tag"]) + select({
        "//conditions:default": ["x"],
    }),
    runner = "xcode-27",
    test_targets = [":a", "//other:b"],
    depends_on = ["first"],
)
`, "pkg")
	if len(units) != 1 {
		t.Fatalf("got %d units, want 1", len(units))
	}
	wantTargets(t, units[0], "//pkg:a", "//other:b")
	if units[0].Runner != "xcode-27" {
		t.Errorf("runner = %q, want xcode-27", units[0].Runner)
	}
	if !reflect.DeepEqual(units[0].DependsOn, []string{"first"}) {
		t.Errorf("depends_on = %q, want [first]", units[0].DependsOn)
	}
}

func TestTargetListWithBracketInComment(t *testing.T) {
	units := mustReadUnits(t, `
pipeline_unit(
    name = "u",
    test_targets = [
        ":a",  # flaky on arm64 [#1234]
        # the list below is sorted (mostly]
        ":b",
    ],
    runner = "xcode-27",
)
`, "pkg")
	if len(units) != 1 {
		t.Fatalf("got %d units, want 1", len(units))
	}
	wantTargets(t, units[0], "//pkg:a", "//pkg:b")
	if units[0].Runner != "xcode-27" {
		t.Errorf("runner = %q, want xcode-27", units[0].Runner)
	}
}

// A commented-out entry is not a target, and neither is a label quoted in a
// trailing comment.
func TestCommentedOutTargetIsNotATarget(t *testing.T) {
	units := mustReadUnits(t, `
pipeline_unit(
    name = "u",
    test_targets = [
        ":a",  # replaces ":old"
        # ":disabled_test",  # see [1] (flaky)
        ":b",
    ],
)
`, "pkg")
	if len(units) != 1 {
		t.Fatalf("got %d units, want 1", len(units))
	}
	wantTargets(t, units[0], "//pkg:a", "//pkg:b")
}

func TestTwoUnitsInOneFile(t *testing.T) {
	units := mustReadUnits(t, `
load("//tools/pipeline:defs.bzl", "pipeline_unit")

pipeline_unit(
    name = "first",
    # one (bracketed) comment
    test_targets = [":a"],
)

filegroup(name = "between", srcs = glob(["*.txt"]))

pipeline_unit(
    name = "second",
    runner = "xcode-27",
    test_targets = [":b", ":c"],
    depends_on = ["first"],
)
`, "pkg")
	if len(units) != 2 {
		t.Fatalf("got %d units, want 2: %+v", len(units), units)
	}
	wantTargets(t, units[0], "//pkg:a")
	wantTargets(t, units[1], "//pkg:b", "//pkg:c")
	if units[0].Name != "first" || units[1].Name != "second" {
		t.Errorf("names = %q, %q", units[0].Name, units[1].Name)
	}
	if units[0].Runner != "ubuntu-26.04" || units[1].Runner != "xcode-27" {
		t.Errorf("runners = %q, %q", units[0].Runner, units[1].Runner)
	}
}

func TestUnitAsLastStatementWithoutNewline(t *testing.T) {
	units := mustReadUnits(t, `pipeline_unit(name = "u", test_targets = [":a"],  # (last)
)`, "")
	if len(units) != 1 {
		t.Fatalf("got %d units, want 1", len(units))
	}
	wantTargets(t, units[0], "//:a")
}

// The words "pipeline_unit(" in a load, a string, a comment or a macro
// definition are not a unit.
func TestOnlyCallsAreUnits(t *testing.T) {
	units := mustReadUnits(t, `
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# pipeline_unit(name = "commented-out", test_targets = [":x"])
genrule(name = "g", cmd = "echo 'pipeline_unit(name = \"in-a-string\")'")

def pipeline_unit(name, test_targets):
    pass

pipeline_unit(name = "real", test_targets = [":a"])
`, "pkg")
	if len(units) != 1 || units[0].Name != "real" {
		t.Fatalf("units = %+v, want only \"real\"", units)
	}
}

// apps/desktop/vitruvian/BUILD as it stood before the bracket was reworded
// out of its comment (39b6a2d21~3), cut down to the call and its neighbours.
// The planner read this unit as: no targets, runner ubuntu-26.04.
const desktopBuildBeforeTheWorkaround = `load("//tools/delivery:defs.bzl", "delivery")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:ignore

MACOS_ONLY = ["@platforms//os:macos"]

py_test(
    name = "upstream_test",
    size = "small",
    srcs = [
        "upstream/upstream.py",
        "upstream/upstream_test.py",
    ],
    data = ["upstream/ledger.tsv"],
    env = {"UPSTREAM_LEDGER": "$(rootpath upstream/ledger.tsv)"},
    main = "upstream/upstream_test.py",
)

# --- Pipeline -----------------------------------------------------------------

pipeline_unit(
    name = "vitruvian-desktop-macos",
    # Services builds with complete concurrency checking (REFACTOR.md 6zu),
    # and each of its compile actions writes more than Bazel's default 1 MB of
    # warnings, which Bazel then skips printing. Show all of it, so the log
    # lists what still stands between Services and Swift 6 mode.
    build_flags = ["--experimental_ui_max_stdouterr_bytes=-1"],
    persona = "frontend",
    runner = "xcode-27",
    test_targets = [
        ":Vitruvian",
        ":VitruvianLibWithSampleTool",
        ":app_holds_mermaid_test",
        ":fan_helper_selftest",
        ":selftest",
        ":source_lints_test",
        ":sources_in_sync_test",
        ":nexus_agent_shared_pin_test",
        ":tool_protocol_pin_test",
        ":unit_tests",
    ],
    tier = "L1",
    timeout_minutes = 60,
)

# Build + package + upload. The generated delivery workflow runs the script
# directly (bash apps/desktop/vitruvian/publish.sh).
exports_files([
    "Tools/ci-setup-signing.sh",
    "publish.sh",
])
`

func TestDesktopUnitAsItWasBeforeTheWorkaround(t *testing.T) {
	units := mustReadUnits(t, desktopBuildBeforeTheWorkaround, "apps/desktop/vitruvian")
	if len(units) != 1 {
		t.Fatalf("got %d units, want 1", len(units))
	}
	u := units[0]
	if u.Name != "vitruvian-desktop-macos" {
		t.Errorf("name = %q", u.Name)
	}
	if len(u.TestTargets) != 10 {
		t.Errorf("got %d test targets, want 10: %q", len(u.TestTargets), u.TestTargets)
	}
	if u.Runner != "xcode-27" {
		t.Errorf("runner = %q, want xcode-27", u.Runner)
	}
	if u.TimeoutMinutes != 60 || u.Persona != "frontend" {
		t.Errorf("timeout = %d, persona = %q", u.TimeoutMinutes, u.Persona)
	}
	found := false
	for _, tt := range u.TestTargets {
		if tt == "//apps/desktop/vitruvian:tool_protocol_pin_test" {
			found = true
		}
	}
	if !found {
		t.Errorf("the pin test is not among the targets: %q", u.TestTargets)
	}
}

// A call the reader cannot make sense of is an error that names the unit.
// It must never come back as a unit with no targets.
func TestUnreadableUnitIsAnError(t *testing.T) {
	cases := map[string]string{
		"call never closes": `
pipeline_unit(
    name = "broken",
    test_targets = [":a"],
`,
		"mismatched brackets": `
pipeline_unit(
    name = "broken",
    test_targets = [":a"),
)
`,
		"string never closes": `
pipeline_unit(
    name = "broken",
    runner = "xcode-27,
    test_targets = [":a"],
)
`,
		"targets are not a literal list": `
pipeline_unit(
    name = "broken",
    test_targets = glob(["*_test.go"]),
)
`,
		"a target is not a string": `
pipeline_unit(
    name = "broken",
    test_targets = [":a", SOME_CONSTANT],
)
`,
		"targets are empty": `
pipeline_unit(
    name = "broken",
    test_targets = [
        # ":a",
    ],
)
`,
		"no targets at all": `
pipeline_unit(
    name = "broken",
    runner = "xcode-27",
)
`,
		"runner is not a string": `
pipeline_unit(
    name = "broken",
    runner = MAC_RUNNER,
    test_targets = [":a"],
)
`,
	}
	for what, build := range cases {
		t.Run(what, func(t *testing.T) {
			units, err := parsePipelineUnitsFromBuild(build, "pkg")
			if err == nil {
				t.Fatalf("no error; got units %+v", units)
			}
			if !strings.Contains(err.Error(), "broken") {
				t.Errorf("the error does not name the unit: %v", err)
			}
		})
	}
}

func TestUnitWithoutALiteralNameIsAnError(t *testing.T) {
	_, err := parsePipelineUnitsFromBuild(`
pipeline_unit(
    name = PREFIX + "-unit",
    test_targets = [":a"],
)
`, "pkg")
	if err == nil || !strings.Contains(err.Error(), "line 2") {
		t.Fatalf("want an error naming line 2, got %v", err)
	}
}

// End to end: a BUILD file the reader cannot read stops the plan, and the
// error names the file and the unit. CI treats a planner that exits non-zero
// as "run every unit", so this fails safe as well as loud.
func TestComputePlanFailsOnAnUnreadableUnit(t *testing.T) {
	tmpDir := t.TempDir()
	dir := filepath.Join(tmpDir, "apps", "broken")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	build := `
pipeline_unit(
    name = "broken-unit",
    test_targets = glob(["*_test.go"]),
)
`
	if err := os.WriteFile(filepath.Join(dir, "BUILD"), []byte(build), 0o644); err != nil {
		t.Fatal(err)
	}

	engine := NewEngine(tmpDir, &mockQueryRunner{})
	plan, err := engine.ComputePlan(context.Background(), []string{"apps/broken/main.go"}, "main", "HEAD")
	if err == nil {
		t.Fatalf("no error; got a plan with matrix %+v", plan.Matrix)
	}
	for _, want := range []string{"apps/broken/BUILD", "broken-unit"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("the error does not name %q: %v", want, err)
		}
	}
}

// A unit reached only through a dependency is selected when one of its
// declared targets is among the affected tests. This is the selection the
// truncated read broke: with no targets there is nothing to intersect.
func TestUnitIsSelectedThroughADependency(t *testing.T) {
	tmpDir := t.TempDir()
	dir := filepath.Join(tmpDir, "apps", "desktop", "vitruvian")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "BUILD"), []byte(desktopBuildBeforeTheWorkaround), 0o644); err != nil {
		t.Fatal(err)
	}
	pkgDir := filepath.Join(tmpDir, "packages", "tool-protocol")
	if err := os.MkdirAll(pkgDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(pkgDir, "BUILD"), []byte("# a package\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	runner := &mockQueryRunner{rdepsMap: map[string][]string{
		"//packages/tool-protocol:all": {"//apps/desktop/vitruvian:tool_protocol_pin_test"},
	}}
	engine := NewEngine(tmpDir, runner)
	plan, err := engine.ComputePlan(context.Background(), []string{"packages/tool-protocol/Sources/Protocol.swift"}, "main", "HEAD")
	if err != nil {
		t.Fatalf("ComputePlan: %v", err)
	}
	if len(plan.Matrix) != 1 || plan.Matrix[0].Name != "vitruvian-desktop-macos" {
		t.Fatalf("matrix = %+v, want the desktop unit", plan.Matrix)
	}
	if plan.Matrix[0].Runner != "xcode-27" || plan.Matrix[0].TargetCount != 10 {
		t.Errorf("runner = %q, target count = %d; want xcode-27 and 10", plan.Matrix[0].Runner, plan.Matrix[0].TargetCount)
	}
}
