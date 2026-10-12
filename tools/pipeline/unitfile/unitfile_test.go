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

package unitfile

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func mustParse(t *testing.T, build, pkg string) []Unit {
	t.Helper()
	units, err := Parse(build, pkg)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	return units
}

func TestParseReadsEveryAttribute(t *testing.T) {
	units := mustParse(t, `
pipeline_unit(
    name = "remote",
    artifacts = {"apk": "apps/x/app.apk"},
    build_flags = ["--fat_apk_cpu=arm64-v8a,x86_64"],
    depends_on = ["design-system"],
    env = {"ANDROID_NDK_HOME": "${{ env.ANDROID_NDK_ROOT }}"},
    needs_emulator = True,
    persona = "frontend",
    runner = "xcode-27",
    test_targets = [
        ":app",
        "//other:lib",
        "@repo//pkg:t",
    ],
    tier = "L2",
    timeout_minutes = 45,
)
`, "apps/x")
	want := []Unit{{
		Name:           "remote",
		Package:        "apps/x",
		TestTargets:    []string{"//apps/x:app", "//other:lib", "@repo//pkg:t"},
		Tier:           "L2",
		Runner:         "xcode-27",
		Persona:        "frontend",
		TimeoutMinutes: 45,
		DependsOn:      []string{"design-system"},
		NeedsEmulator:  true,
		Env:            map[string]string{"ANDROID_NDK_HOME": "${{ env.ANDROID_NDK_ROOT }}"},
		Artifacts:      map[string]string{"apk": "apps/x/app.apk"},
		BuildFlags:     []string{"--fat_apk_cpu=arm64-v8a,x86_64"},
		Line:           2,
	}}
	if !reflect.DeepEqual(units, want) {
		t.Errorf("got  %+v\nwant %+v", units, want)
	}
}

func TestParseDefaults(t *testing.T) {
	units := mustParse(t, `pipeline_unit(name = "u", test_targets = [":t"])`, "")
	want := []Unit{{
		Name: "u", TestTargets: []string{"//:t"},
		Tier: "L1", Runner: "ubuntu-26.04", Persona: "all", TimeoutMinutes: 20, Line: 1,
	}}
	if !reflect.DeepEqual(units, want) {
		t.Errorf("got  %+v\nwant %+v", units, want)
	}
}

func TestParseFileWithoutUnits(t *testing.T) {
	// Not even scanned: a BUILD file with no unit cannot fail the reader.
	units, err := Parse("filegroup(name = \"x\", srcs = [\"unclosed)", "pkg")
	if err != nil || len(units) != 0 {
		t.Fatalf("units = %+v, err = %v", units, err)
	}
}

// Every way a string can hold a bracket, a quote or a "#".
func TestParseStrings(t *testing.T) {
	units := mustParse(t, `
pipeline_unit(
    name = "u",
    env = {
        "A": "double ) ] } # not a comment",
        'B': 'single ( [ { "quoted"',
        "C": "escaped \" quote ) and \\",
        "D": r"raw \) backslash\"",
        "E": """triple
with a " and a ) and a # inside""",
        "F": '''other triple ] with '' inside''',
        "G": "",
    },
    test_targets = [":t"],  # trailing ) comment
)
`, "pkg")
	if len(units) != 1 {
		t.Fatalf("got %d units, want 1", len(units))
	}
	want := map[string]string{
		"A": "double ) ] } # not a comment",
		"B": `single ( [ { "quoted"`,
		"C": `escaped " quote ) and \`,
		"D": `raw \) backslash\"`,
		"E": "triple\nwith a \" and a ) and a # inside",
		"F": "other triple ] with '' inside",
		"G": "",
	}
	if !reflect.DeepEqual(units[0].Env, want) {
		t.Errorf("env:\n got  %q\n want %q", units[0].Env, want)
	}
	if !reflect.DeepEqual(units[0].TestTargets, []string{"//pkg:t"}) {
		t.Errorf("test targets = %q", units[0].TestTargets)
	}
}

// Attributes this package does not read may hold any expression.
func TestParseSkipsExpressionsItDoesNotRead(t *testing.T) {
	units := mustParse(t, `
pipeline_unit(
    name = "u",
    concurrency_group = "group-%s" % (SUFFIX if SUFFIX != "" else "x"),
    tags = ["a"] + glob(["*.tag"]) + select({
        "//conditions:default": [t for t in TAGS if t == "b"],
    }),
    test_targets = [":t"],
    timeout_minutes = 60,
)
`, "pkg")
	if len(units) != 1 || units[0].TimeoutMinutes != 60 || len(units[0].TestTargets) != 1 {
		t.Fatalf("units = %+v", units)
	}
}

func TestParseLineNumbers(t *testing.T) {
	units := mustParse(t, `x = """one
two
three"""

pipeline_unit(name = "first", test_targets = [":a"])
# comment
pipeline_unit(
    name = "second",
    test_targets = [":b"],
)
`, "pkg")
	if len(units) != 2 || units[0].Line != 5 || units[1].Line != 7 {
		t.Fatalf("units = %+v, want lines 5 and 7", units)
	}
}

func TestParseIgnoresWhatIsNotACall(t *testing.T) {
	units := mustParse(t, `
load("//tools/pipeline:defs.bzl", "pipeline_unit")
# pipeline_unit(name = "in-a-comment", test_targets = [":x"])
NOTE = "pipeline_unit(name = 'in-a-string', test_targets = [':x'])"
defs.pipeline_unit(name = "a-method", test_targets = [":x"])
my_pipeline_unit(name = "another-name", test_targets = [":x"])

def pipeline_unit(name, test_targets):
    pass
`, "pkg")
	if len(units) != 0 {
		t.Fatalf("units = %+v, want none", units)
	}
}

func TestParseErrors(t *testing.T) {
	cases := []struct {
		what, build string
		want        []string
	}{
		{
			"never closed", "\npipeline_unit(\n    name = \"u\",\n    test_targets = [\":a\"],\n",
			[]string{"line 2", `"u"`, "never closed"},
		},
		{
			"closed by the wrong bracket", "pipeline_unit(\n    name = \"u\",\n    test_targets = [\":a\"),\n)\n",
			[]string{`"u"`, "line 3", `")" closes the "["`},
		},
		{
			"string runs off the line", "pipeline_unit(\n    name = \"u\",\n    runner = \"xcode-27,\n    test_targets = [\":a\"],\n)\n",
			[]string{`"u"`, "line 3", "not closed before the end of the line"},
		},
		{
			"triple-quoted string never ends", "pipeline_unit(\n    name = \"u\",\n    env = {\"A\": \"\"\"oops},\n)\n",
			[]string{`"u"`, "line 3", "never closed"},
		},
		{
			"name is an expression", "pipeline_unit(name = PREFIX + \"-u\", test_targets = [\":a\"])",
			[]string{"line 1", "name must be a quoted string"},
		},
		{
			"no name", "pipeline_unit(test_targets = [\":a\"])",
			[]string{"line 1", "name must be a quoted string"},
		},
		{
			"positional arguments", "pipeline_unit(\"u\", [\":a\"])",
			[]string{"line 1", "name = value"},
		},
		{
			"keyword splat", "pipeline_unit(name = \"u\", **COMMON)",
			[]string{"line 1", "name = value"},
		},
		{
			"targets from glob", "pipeline_unit(name = \"u\", test_targets = glob([\"*_test.go\"]))",
			[]string{`"u"`, "test_targets must be a list written out"},
		},
		{
			"targets from a constant", "pipeline_unit(name = \"u\", test_targets = TARGETS)",
			[]string{`"u"`, "test_targets must be a list written out"},
		},
		{
			"targets concatenated", "pipeline_unit(name = \"u\", test_targets = [\":a\"] + [\":b\"])",
			[]string{`"u"`, "test_targets must be a list written out"},
		},
		{
			"a target that is a name", "pipeline_unit(name = \"u\", test_targets = [\":a\", OTHER])",
			[]string{`"u"`, "every entry of test_targets"},
		},
		{
			"no targets", "pipeline_unit(name = \"u\", runner = \"xcode-27\")",
			[]string{`"u"`, "test_targets is missing or empty"},
		},
		{
			"only commented-out targets", "pipeline_unit(name = \"u\", test_targets = [\n    # \":a\",\n])",
			[]string{`"u"`, "test_targets is missing or empty"},
		},
		{
			"runner is a name", "pipeline_unit(name = \"u\", runner = MAC, test_targets = [\":a\"])",
			[]string{`"u"`, "runner must be a quoted string"},
		},
		{
			"timeout is an expression", "pipeline_unit(name = \"u\", timeout_minutes = 2 * 30, test_targets = [\":a\"])",
			[]string{`"u"`, "timeout_minutes must be a whole number"},
		},
		{
			"emulator flag is a name", "pipeline_unit(name = \"u\", needs_emulator = ON_LINUX, test_targets = [\":a\"])",
			[]string{`"u"`, "needs_emulator must be True or False"},
		},
		{
			"env from select", "pipeline_unit(name = \"u\", env = select({\"//conditions:default\": {}}), test_targets = [\":a\"])",
			[]string{`"u"`, "env must be a dict written out"},
		},
		{
			"env value is a name", "pipeline_unit(name = \"u\", env = {\"A\": VALUE}, test_targets = [\":a\"])",
			[]string{`"u"`, "every key and value of env"},
		},
	}
	for _, c := range cases {
		t.Run(c.what, func(t *testing.T) {
			units, err := Parse(c.build, "pkg")
			if err == nil {
				t.Fatalf("no error; got %+v", units)
			}
			for _, w := range c.want {
				if !strings.Contains(err.Error(), w) {
					t.Errorf("error does not say %q: %v", w, err)
				}
			}
		})
	}
}

func writeBuild(t *testing.T, root, dir, name, content string) {
	t.Helper()
	full := filepath.Join(root, filepath.FromSlash(dir))
	if err := os.MkdirAll(full, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(full, name), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestDiscover(t *testing.T) {
	root := t.TempDir()
	unit := func(name string) string {
		return "pipeline_unit(name = \"" + name + "\", test_targets = [\":t\"])\n"
	}
	writeBuild(t, root, "", "BUILD", unit("root-unit"))
	writeBuild(t, root, "apps/zeta", "BUILD", unit("zeta"))
	writeBuild(t, root, "apps/alpha", "BUILD.bazel", unit("alpha"))
	// A real directory that merely starts with "bazel-" is read ...
	writeBuild(t, root, "tools/bazel-cache", "BUILD", unit("cache"))
	// ... the output trees and other checkouts are not.
	writeBuild(t, root, "bazel-out/k8/bin/apps/zeta", "BUILD", unit("zeta"))
	writeBuild(t, root, "node_modules/dep", "BUILD", unit("from-node-modules"))
	writeBuild(t, root, ".claude/worktrees/w/apps/zeta", "BUILD", unit("zeta"))
	writeBuild(t, root, ".git/x", "BUILD", unit("from-git"))
	// Other files are not BUILD files.
	writeBuild(t, root, "apps/zeta", "BUILD.txt", unit("not-a-build-file"))

	units, err := Discover(root)
	if err != nil {
		t.Fatalf("Discover: %v", err)
	}
	var got []string
	for _, u := range units {
		got = append(got, u.Name+" "+u.TestTargets[0])
	}
	want := []string{
		"alpha //apps/alpha:t",
		"cache //tools/bazel-cache:t",
		"root-unit //:t",
		"zeta //apps/zeta:t",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got  %q\nwant %q", got, want)
	}
}

// Every bad file is reported in one go, each with its path.
func TestDiscoverReportsEveryUnreadableFile(t *testing.T) {
	root := t.TempDir()
	writeBuild(t, root, "apps/good", "BUILD", "pipeline_unit(name = \"good\", test_targets = [\":t\"])\n")
	writeBuild(t, root, "apps/one", "BUILD", "pipeline_unit(name = \"one\", test_targets = glob([\"*\"]))\n")
	writeBuild(t, root, "apps/two", "BUILD", "\n\npipeline_unit(\n    name = \"two\",\n")

	units, err := Discover(root)
	if err == nil {
		t.Fatalf("no error; got %+v", units)
	}
	if units != nil {
		t.Errorf("units returned alongside an error: %+v", units)
	}
	for _, w := range []string{"apps/one/BUILD: line 1", `"one"`, "apps/two/BUILD: line 3", `"two"`} {
		if !strings.Contains(err.Error(), w) {
			t.Errorf("error does not say %q:\n%v", w, err)
		}
	}
}

func TestDiscoverRefusesANameDeclaredTwice(t *testing.T) {
	root := t.TempDir()
	writeBuild(t, root, "apps/a", "BUILD", "pipeline_unit(name = \"same\", test_targets = [\":t\"])\n")
	writeBuild(t, root, "apps/b", "BUILD", "pipeline_unit(name = \"same\", test_targets = [\":t\"])\n")

	_, err := Discover(root)
	if err == nil {
		t.Fatal("no error for a duplicate unit name")
	}
	for _, w := range []string{"apps/b/BUILD", `"same"`, "already declared in apps/a/BUILD"} {
		if !strings.Contains(err.Error(), w) {
			t.Errorf("error does not say %q: %v", w, err)
		}
	}
}
