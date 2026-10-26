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

//! The cases of unitfile_test.go, plus every pipeline_unit in the repo as
//! snapshotted under testdata/real_units.

use super::*;
use std::path::Path;

fn must_parse(build: &str, pkg: &str) -> Vec<Unit> {
    parse(build, pkg).unwrap_or_else(|e| panic!("parse: {e}"))
}

fn s(v: &[&str]) -> Vec<String> {
    v.iter().map(|x| x.to_string()).collect()
}

fn m(v: &[(&str, &str)]) -> BTreeMap<String, String> {
    v.iter()
        .map(|(k, x)| (k.to_string(), x.to_string()))
        .collect()
}

#[test]
fn parse_reads_every_attribute() {
    let units = must_parse(
        r#"
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
"#,
        "apps/x",
    );
    let want = vec![Unit {
        name: "remote".into(),
        package: "apps/x".into(),
        test_targets: s(&["//apps/x:app", "//other:lib", "@repo//pkg:t"]),
        tier: "L2".into(),
        runner: "xcode-27".into(),
        persona: "frontend".into(),
        timeout_minutes: 45,
        depends_on: s(&["design-system"]),
        needs_emulator: true,
        env: m(&[("ANDROID_NDK_HOME", "${{ env.ANDROID_NDK_ROOT }}")]),
        artifacts: m(&[("apk", "apps/x/app.apk")]),
        build_flags: s(&["--fat_apk_cpu=arm64-v8a,x86_64"]),
        line: 2,
    }];
    assert_eq!(units, want);
}

#[test]
fn parse_defaults() {
    let units = must_parse(r#"pipeline_unit(name = "u", test_targets = [":t"])"#, "");
    let want = vec![Unit {
        name: "u".into(),
        test_targets: s(&["//:t"]),
        tier: "L1".into(),
        runner: "ubuntu-26.04".into(),
        persona: "all".into(),
        timeout_minutes: 20,
        line: 1,
        ..Unit::default()
    }];
    assert_eq!(units, want);
}

#[test]
fn parse_file_without_units() {
    let units = parse("filegroup(name = \"x\", srcs = [\"unclosed)", "pkg").unwrap();
    assert!(units.is_empty());
}

#[test]
fn parse_strings() {
    let units = must_parse(
        r#"
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
"#,
        "pkg",
    );
    assert_eq!(units.len(), 1);
    let want = m(&[
        ("A", "double ) ] } # not a comment"),
        ("B", r#"single ( [ { "quoted""#),
        ("C", r#"escaped " quote ) and \"#),
        ("D", r#"raw \) backslash\""#),
        ("E", "triple\nwith a \" and a ) and a # inside"),
        ("F", "other triple ] with '' inside"),
        ("G", ""),
    ]);
    assert_eq!(units[0].env, want);
    assert_eq!(units[0].test_targets, s(&["//pkg:t"]));
}

#[test]
fn parse_skips_expressions_it_does_not_read() {
    let units = must_parse(
        r#"
pipeline_unit(
    name = "u",
    concurrency_group = "group-%s" % (SUFFIX if SUFFIX != "" else "x"),
    tags = ["a"] + glob(["*.tag"]) + select({
        "//conditions:default": [t for t in TAGS if t == "b"],
    }),
    test_targets = [":t"],
    timeout_minutes = 60,
)
"#,
        "pkg",
    );
    assert_eq!(units.len(), 1);
    assert_eq!(units[0].timeout_minutes, 60);
    assert_eq!(units[0].test_targets.len(), 1);
}

#[test]
fn parse_line_numbers() {
    let units = must_parse(
        "x = \"\"\"one\ntwo\nthree\"\"\"\n\npipeline_unit(name = \"first\", test_targets = [\":a\"])\n# comment\npipeline_unit(\n    name = \"second\",\n    test_targets = [\":b\"],\n)\n",
        "pkg",
    );
    assert_eq!(units.len(), 2);
    assert_eq!((units[0].line, units[1].line), (5, 7));
}

#[test]
fn parse_ignores_what_is_not_a_call() {
    let units = must_parse(
        r#"
load("//tools/pipeline:defs.bzl", "pipeline_unit")
# pipeline_unit(name = "in-a-comment", test_targets = [":x"])
NOTE = "pipeline_unit(name = 'in-a-string', test_targets = [':x'])"
defs.pipeline_unit(name = "a-method", test_targets = [":x"])
my_pipeline_unit(name = "another-name", test_targets = [":x"])

def pipeline_unit(name, test_targets):
    pass
"#,
        "pkg",
    );
    assert!(units.is_empty(), "{units:?}");
}

#[test]
fn parse_errors() {
    let cases: &[(&str, &str, &[&str])] = &[
        ("never closed", "\npipeline_unit(\n    name = \"u\",\n    test_targets = [\":a\"],\n", &["line 2", "\"u\"", "never closed"]),
        ("closed by the wrong bracket", "pipeline_unit(\n    name = \"u\",\n    test_targets = [\":a\"),\n)\n", &["\"u\"", "line 3", "\")\" closes the \"[\""]),
        ("string runs off the line", "pipeline_unit(\n    name = \"u\",\n    runner = \"xcode-27,\n    test_targets = [\":a\"],\n)\n", &["\"u\"", "line 3", "not closed before the end of the line"]),
        ("triple-quoted string never ends", "pipeline_unit(\n    name = \"u\",\n    env = {\"A\": \"\"\"oops},\n)\n", &["\"u\"", "line 3", "never closed"]),
        ("name is an expression", "pipeline_unit(name = PREFIX + \"-u\", test_targets = [\":a\"])", &["line 1", "name must be a quoted string"]),
        ("no name", "pipeline_unit(test_targets = [\":a\"])", &["line 1", "name must be a quoted string"]),
        ("positional arguments", "pipeline_unit(\"u\", [\":a\"])", &["line 1", "name = value"]),
        ("keyword splat", "pipeline_unit(name = \"u\", **COMMON)", &["line 1", "name = value"]),
        ("targets from glob", "pipeline_unit(name = \"u\", test_targets = glob([\"*_test.go\"]))", &["\"u\"", "test_targets must be a list written out"]),
        ("targets from a constant", "pipeline_unit(name = \"u\", test_targets = TARGETS)", &["\"u\"", "test_targets must be a list written out"]),
        ("targets concatenated", "pipeline_unit(name = \"u\", test_targets = [\":a\"] + [\":b\"])", &["\"u\"", "test_targets must be a list written out"]),
        ("a target that is a name", "pipeline_unit(name = \"u\", test_targets = [\":a\", OTHER])", &["\"u\"", "every entry of test_targets"]),
        ("no targets", "pipeline_unit(name = \"u\", runner = \"xcode-27\")", &["\"u\"", "test_targets is missing or empty"]),
        ("only commented-out targets", "pipeline_unit(name = \"u\", test_targets = [\n    # \":a\",\n])", &["\"u\"", "test_targets is missing or empty"]),
        ("runner is a name", "pipeline_unit(name = \"u\", runner = MAC, test_targets = [\":a\"])", &["\"u\"", "runner must be a quoted string"]),
        ("timeout is an expression", "pipeline_unit(name = \"u\", timeout_minutes = 2 * 30, test_targets = [\":a\"])", &["\"u\"", "timeout_minutes must be a whole number"]),
        ("emulator flag is a name", "pipeline_unit(name = \"u\", needs_emulator = ON_LINUX, test_targets = [\":a\"])", &["\"u\"", "needs_emulator must be True or False"]),
        ("env from select", "pipeline_unit(name = \"u\", env = select({\"//conditions:default\": {}}), test_targets = [\":a\"])", &["\"u\"", "env must be a dict written out"]),
        ("env value is a name", "pipeline_unit(name = \"u\", env = {\"A\": VALUE}, test_targets = [\":a\"])", &["\"u\"", "every key and value of env"]),
    ];
    for (what, build, wants) in cases {
        let err = match parse(build, "pkg") {
            Ok(u) => panic!("{what}: no error; got {u:?}"),
            Err(e) => e,
        };
        for w in *wants {
            assert!(err.contains(w), "{what}: error does not say {w:?}: {err}");
        }
    }
}

/// The exact wording, for the shapes whose message is fixed.
#[test]
fn parse_error_wording() {
    assert_eq!(
        parse(
            "\npipeline_unit(\n    name = \"u\",\n    test_targets = [\":a\"],\n",
            "pkg"
        )
        .unwrap_err(),
        "line 2: pipeline_unit(name = \"u\"): the \"(\" opened on line 2 is never closed"
    );
    assert_eq!(
        parse("pipeline_unit(\n    name = \"u\",\n    runner = \"xcode-27,\n    test_targets = [\":a\"],\n)\n", "pkg").unwrap_err(),
        "pipeline_unit(name = \"u\"), which starts on line 1: line 3: a string starting \"xcode-27, is not closed before the end of the line"
    );
    assert_eq!(
        parse("pipeline_unit(name = \"u\", test_targets = glob([\"*_test.go\"]))", "pkg").unwrap_err(),
        "line 1: pipeline_unit(name = \"u\"): test_targets must be a list written out in the call, [\"...\", ...]; this reader does not run Bazel, so it cannot follow a name, glob() or select()"
    );
    assert_eq!(
        parse(
            "x = r'unclosed\npipeline_unit(name = \"u\", test_targets = [\":a\"])",
            "pkg"
        )
        .unwrap_err(),
        "line 1: a string starting 'unclosed is not closed before the end of the line"
    );
    assert_eq!(
        parse(
            "pipeline_unit(name = \"u\", test_targets = [\":a\"]))",
            "pkg"
        )
        .unwrap(),
        parse(
            "pipeline_unit(name = \"u\", test_targets = [\":a\"])",
            "pkg"
        )
        .unwrap(),
        "a stray closer after the call is not part of it"
    );
}

fn write_build(root: &Path, dir: &str, name: &str, content: &str) {
    let full = root.join(dir);
    fs::create_dir_all(&full).unwrap();
    fs::write(full.join(name), content).unwrap();
}

fn temp_dir(tag: &str) -> std::path::PathBuf {
    let base = std::env::var("TEST_TMPDIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir());
    let d = base.join(format!("unitfile-{tag}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&d);
    fs::create_dir_all(&d).unwrap();
    d
}

fn unit(name: &str) -> String {
    format!("pipeline_unit(name = \"{name}\", test_targets = [\":t\"])\n")
}

#[test]
fn discover_walks_like_go() {
    let root = temp_dir("discover");
    write_build(&root, "", "BUILD", &unit("root-unit"));
    write_build(&root, "apps/zeta", "BUILD", &unit("zeta"));
    write_build(&root, "apps/alpha", "BUILD.bazel", &unit("alpha"));
    write_build(&root, "tools/bazel-cache", "BUILD", &unit("cache"));
    write_build(&root, "bazel-out/k8/bin/apps/zeta", "BUILD", &unit("zeta"));
    write_build(
        &root,
        "node_modules/dep",
        "BUILD",
        &unit("from-node-modules"),
    );
    write_build(
        &root,
        ".claude/worktrees/w/apps/zeta",
        "BUILD",
        &unit("zeta"),
    );
    write_build(&root, ".git/x", "BUILD", &unit("from-git"));
    write_build(&root, "apps/zeta", "BUILD.txt", &unit("not-a-build-file"));

    let units = discover(root.to_str().unwrap()).unwrap();
    let got: Vec<String> = units
        .iter()
        .map(|u| format!("{} {}", u.name, u.test_targets[0]))
        .collect();
    assert_eq!(
        got,
        s(&[
            "alpha //apps/alpha:t",
            "cache //tools/bazel-cache:t",
            "root-unit //:t",
            "zeta //apps/zeta:t"
        ])
    );
}

#[test]
fn discover_reports_every_unreadable_file() {
    let root = temp_dir("unreadable");
    write_build(
        &root,
        "apps/good",
        "BUILD",
        "pipeline_unit(name = \"good\", test_targets = [\":t\"])\n",
    );
    write_build(
        &root,
        "apps/one",
        "BUILD",
        "pipeline_unit(name = \"one\", test_targets = glob([\"*\"]))\n",
    );
    write_build(
        &root,
        "apps/two",
        "BUILD",
        "\n\npipeline_unit(\n    name = \"two\",\n",
    );
    let err = discover(root.to_str().unwrap()).unwrap_err();
    assert_eq!(
        err,
        "cannot read every pipeline unit:\napps/one/BUILD: line 1: pipeline_unit(name = \"one\"): test_targets must be a list written out in the call, [\"...\", ...]; this reader does not run Bazel, so it cannot follow a name, glob() or select()\napps/two/BUILD: line 3: pipeline_unit(name = \"two\"): the \"(\" opened on line 3 is never closed"
    );
}

#[test]
fn discover_refuses_a_name_declared_twice() {
    let root = temp_dir("twice");
    write_build(
        &root,
        "apps/a",
        "BUILD",
        "pipeline_unit(name = \"same\", test_targets = [\":t\"])\n",
    );
    write_build(
        &root,
        "apps/b",
        "BUILD",
        "pipeline_unit(name = \"same\", test_targets = [\":t\"])\n",
    );
    let err = discover(root.to_str().unwrap()).unwrap_err();
    for w in [
        "apps/b/BUILD",
        "\"same\"",
        "already declared in apps/a/BUILD",
    ] {
        assert!(err.contains(w), "{err}");
    }
}

#[test]
fn discover_of_a_missing_root_is_empty() {
    assert_eq!(
        discover("/no/such/root/anywhere").unwrap(),
        Vec::<Unit>::new()
    );
}

/// Every BUILD file in the repo that declared a unit when this was written
/// (testdata/real_units/<path with / as __>.txt) reads without error, and
/// every unit in it has targets, all absolute.
#[test]
fn real_repo_unit_files_read_completely() {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("testdata/real_units");
    let dir = if dir.is_dir() {
        dir
    } else {
        Path::new("tools/pipeline/unitfile/testdata/real_units").to_path_buf()
    };
    let mut files: Vec<_> = fs::read_dir(&dir)
        .unwrap_or_else(|e| panic!("{}: {e}", dir.display()))
        .map(|e| e.unwrap().path())
        .collect();
    files.sort();
    assert!(files.len() >= 30, "found only {} snapshots", files.len());
    let mut total = 0;
    let mut names = std::collections::BTreeSet::new();
    for f in &files {
        let stem = f
            .file_name()
            .unwrap()
            .to_str()
            .unwrap()
            .trim_end_matches(".txt")
            .replace("__", "/");
        let pkg = stem.rsplit_once('/').map(|(p, _)| p).unwrap_or("");
        let content = fs::read(f).unwrap();
        let units = parse_bytes(&content, pkg).unwrap_or_else(|e| panic!("{stem}: {e}"));
        assert!(!units.is_empty(), "{stem}: no unit read");
        for u in &units {
            assert!(names.insert(u.name.clone()), "{} declared twice", u.name);
            assert_eq!(u.package, pkg);
            assert!(!u.test_targets.is_empty());
            for t in &u.test_targets {
                assert!(t.starts_with("//") || t.starts_with('@'), "{stem}: {t}");
            }
        }
        total += units.len();
    }
    assert!(total >= files.len());
    // The desktop unit the truncated read once missed.
    let desk = fs::read(dir.join("apps__desktop__vitruvian__BUILD.txt")).unwrap();
    let u = &parse_bytes(&desk, "apps/desktop/vitruvian").unwrap()[0];
    assert_eq!(u.runner, "xcode-27");
    assert!(u.test_targets.len() >= 10, "{:?}", u.test_targets);
}
