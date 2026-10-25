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

//! The cases of plan_test.go, rdepsmap_test.go and units_test.go.

use super::*;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

struct Mock {
    rdeps: HashMap<String, Vec<String>>,
    should_err: bool,
}

impl Mock {
    fn new(pairs: &[(&str, &[&str])]) -> Mock {
        Mock {
            rdeps: pairs
                .iter()
                .map(|(k, v)| (k.to_string(), v.iter().map(|s| s.to_string()).collect()))
                .collect(),
            should_err: false,
        }
    }
    fn failing() -> Mock {
        Mock {
            rdeps: HashMap::new(),
            should_err: true,
        }
    }
}

impl QueryRunner for Mock {
    fn query_test_rdeps(&self, _: &str, packages: &[String]) -> Result<Vec<String>, String> {
        if self.should_err {
            return Err("simulated query error".into());
        }
        Ok(packages
            .iter()
            .filter_map(|p| self.rdeps.get(p))
            .flatten()
            .cloned()
            .collect())
    }
}

fn v(s: &[&str]) -> Vec<String> {
    s.iter().map(|x| x.to_string()).collect()
}

fn tmp(tag: &str) -> PathBuf {
    let base = std::env::var("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir());
    let d = base.join(format!("plan-{tag}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&d);
    fs::create_dir_all(&d).unwrap();
    d
}

fn write(root: &Path, rel: &str, content: &str) {
    let p = root.join(rel);
    fs::create_dir_all(p.parent().unwrap()).unwrap();
    fs::write(p, content).unwrap();
}

#[test]
fn docs_only_fast_gate() {
    let cases: &[(&[&str], bool)] = &[
        (&["docs/index.md", "README.md", "devx/docs/guide.md"], true),
        (&["gitops/argocd/app.yaml", ".agents/task.md"], true),
        (&[".agents/hooks.json"], false),
        (
            &[".agents/agents/wren.md", ".agents/skills/x/SKILL.yaml"],
            true,
        ),
        (&["docs/arch.png", "docs/diagram.svg"], true),
        (
            &[
                "catalog-info.yaml",
                "apps/mobile/android-remote/catalog-info.yaml",
            ],
            true,
        ),
        (
            &["OWNERS", "apps/cli/devx/OWNERS", ".github/CODEOWNERS"],
            true,
        ),
        (&["docs/index.md", "tabula/api/src/app.ts"], false),
        (
            &[
                "apps/mobile/android-remote/catalog-info.yaml",
                "apps/mobile/android-remote/src/main/kotlin/dev/vitruvian/remote/MainActivity.kt",
            ],
            false,
        ),
        (&[], false),
        (&["xcatalog-info.yaml"], false),
        (&["notes.txt.bak"], false),
    ];
    for (files, want) in cases {
        assert_eq!(is_docs_only(&v(files)), *want, "{files:?}");
    }
}

#[test]
fn global_impact_check() {
    let cases: &[(&str, bool, &str)] = &[
        (
            "MODULE.bazel",
            true,
            "root build/toolchain config changed: MODULE.bazel",
        ),
        (
            ".bazelrc",
            true,
            "root build/toolchain config changed: .bazelrc",
        ),
        ("BUILD", true, "root build/toolchain config changed: BUILD"),
        ("tools/ci/affected-targets.sh", false, ""),
        ("tools/pipeline/defs.bzl", false, ""),
        ("tools/owners/main.go", false, ""),
        ("tools/adb-connect/adb_connect.py", false, ""),
        ("tools/repin", false, ""),
        (
            "tools/repin2",
            true,
            "core toolchain directory changed: tools/repin2",
        ),
        (
            "tools/remote.bazelrc",
            true,
            "core toolchain directory changed: tools/remote.bazelrc",
        ),
        ("tabula/web/src/index.tsx", false, ""),
        ("apps/x/BUILD", false, ""),
    ];
    for (f, global, reason) in cases {
        assert_eq!(
            check_global_impact(&v(&[f])),
            (*global, reason.to_string()),
            "{f}"
        );
    }
}

#[test]
fn classify_persona_and_operation_cases() {
    let cases: &[(&[&str], bool, bool, Persona, Operation)] = &[
        (
            &["docs/index.md"],
            true,
            false,
            Persona::DocsAuthor,
            Operation::DocsOnly,
        ),
        (
            &["MODULE.bazel"],
            false,
            true,
            Persona::PlatformAdmin,
            Operation::GlobalConfig,
        ),
        (
            &[
                "tabula/web/app/page.tsx",
                "packages/design-system/src/Button.tsx",
            ],
            false,
            false,
            Persona::FrontendDev,
            Operation::UiFeature,
        ),
        (
            &["tabula/api/src/server.ts", "tabula/api/src/routes/auth.ts"],
            false,
            false,
            Persona::BackendDev,
            Operation::BackendApi,
        ),
        (
            &["tabula/api/prisma/migrations/20260101_init/migration.sql"],
            false,
            false,
            Persona::BackendDev,
            Operation::DatabaseMigration,
        ),
        (
            &["pnpm-lock.yaml"],
            false,
            false,
            Persona::BackendDev,
            Operation::DepUpdate,
        ),
        (
            &["infrastructure/pulumi/platform/repo-config/main.go"],
            false,
            false,
            Persona::InfraEng,
            Operation::InfraProvision,
        ),
        (
            &["tabula/web/app/page.tsx", "tabula/api/src/server.ts"],
            false,
            false,
            Persona::FullStackDev,
            Operation::MultiDiscipline,
        ),
        (
            &["tools/ci/x.sh"],
            false,
            false,
            Persona::PlatformAdmin,
            Operation::BackendApi,
        ),
    ];
    for (files, docs, global, p, o) in cases {
        assert_eq!(
            classify_persona_and_operation(&v(files), *docs, *global),
            (*p, *o),
            "{files:?}"
        );
    }
}

#[test]
fn resolve_packages_finds_enclosing_packages() {
    let d = tmp("resolve");
    write(&d, "app/ui/BUILD", "");
    write(&d, "app/server/BUILD.bazel", "");
    fs::create_dir_all(d.join("app/server/nested")).unwrap();
    let got = resolve_packages(
        d.to_str().unwrap(),
        &v(&[
            "app/ui/src/App.tsx",
            "app/ui/src/components/Header.tsx",
            "app/server/nested/handler.go",
            "./README.md",
            "",
        ]),
    );
    assert_eq!(got, v(&["//app/server:all", "//app/ui:all"]));
}

const TABULA_BUILD: &str = r#"
pipeline_unit(
    name = "tabula-web",
    tier = "L1",
    persona = "frontend",
    runner = "ubuntu-26.04",
    test_targets = [":unit_tests"],
)
"#;

#[test]
fn compute_plan_hermetic() {
    let d = tmp("hermetic");
    write(&d, "tabula/web/BUILD", TABULA_BUILD);
    let root = d.to_str().unwrap();
    let runner = Mock::new(&[("//tabula/web:all", &["//tabula/web:unit_tests"])]);
    let e = Engine::new(root, &runner);

    let p = e
        .compute_plan(v(&["tabula/web/src/App.tsx"]), "main", "HEAD")
        .unwrap();
    assert_eq!(p.persona, Some(Persona::FrontendDev));
    assert_eq!(p.operation, Some(Operation::UiFeature));
    assert_eq!(p.targets, Some(v(&["//tabula/web:unit_tests"])));
    assert_eq!(p.matrix.len(), 1);
    assert_eq!(p.matrix[0].name, "tabula-web");
    assert_eq!(p.plan_source, PLAN_SOURCE_LIVE);

    let docs = e
        .compute_plan(v(&["docs/index.md"]), "main", "HEAD")
        .unwrap();
    assert!(docs.is_docs_only);
    assert_eq!(docs.targets, Some(vec![]));

    let failing = Mock::failing();
    let e = Engine::new(root, &failing);
    let p = e
        .compute_plan(v(&["tabula/web/src/App.tsx"]), "main", "HEAD")
        .unwrap();
    assert!(p.is_global_impact);
    assert_eq!(p.targets, Some(v(&["//..."])));
}

#[test]
fn degraded_query_is_distinguishable_from_real_global_impact() {
    let d = tmp("degraded");
    write(&d, "tabula/web/BUILD", TABULA_BUILD);
    let root = d.to_str().unwrap();

    let failing = Mock::failing();
    let p = Engine::new(root, &failing)
        .compute_plan(v(&["tabula/web/src/App.tsx"]), "main", "HEAD")
        .unwrap();
    assert!(p.is_global_impact && p.is_degraded);
    assert_eq!(
        p.sweep_reason,
        "query degraded: fallback to full sweep (simulated query error)"
    );

    let ok = Mock::new(&[("//tabula/web:all", &["//tabula/web:unit_tests"])]);
    let p = Engine::new(root, &ok)
        .compute_plan(v(&["MODULE.bazel"]), "main", "HEAD")
        .unwrap();
    assert!(p.is_global_impact && !p.is_degraded);

    let p = Engine::new(root, &ok)
        .compute_plan(v(&["tabula/web/src/App.tsx"]), "main", "HEAD")
        .unwrap();
    assert!(!p.is_global_impact && !p.is_degraded);
}

#[test]
fn test_rdeps_query_shape() {
    let q = build_test_rdeps_query(&v(&["//apps/mobile/android-remote:all"]));
    assert!(q.contains(r#"except attr(tags, "manual", //...)"#));
    assert!(q.find("except").unwrap() > q.find("rdeps(").unwrap());
    assert!(q.contains("rdeps(//...") && q.contains("_test"));
    let q = build_test_rdeps_query(&v(&["//apps/embedded/esp32-s3:all"]));
    assert!(q.contains("set(//apps/embedded/esp32-s3:*)") && !q.contains(":all"));
}

#[test]
fn last_lines_keeps_the_end() {
    let mut b = String::new();
    for i in 0..500 {
        b.push_str(&format!("Loading: {i} packages loaded\n"));
    }
    b.push_str("ERROR: the real reason\n");
    assert_eq!(
        last_lines(&b, 3),
        "Loading: 498 packages loaded\nLoading: 499 packages loaded\nERROR: the real reason"
    );
    assert_eq!(last_lines("one\ntwo", 15), "one\ntwo");
}

const SAMPLE_DOT: &str = r#"digraph mygraph {
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
"#;

#[test]
fn parse_graph_edges_reads_the_graph() {
    let edges = parse_graph_edges(SAMPLE_DOT).unwrap();
    assert_eq!(edges["@rules_x//:wrapper"], v(&["//shared:lib"]));
    assert!(edges.contains_key("//shared:lib"));
    let err = parse_graph_edges(r#""//a:x\n//a:y" -> "//b:z""#).unwrap_err();
    assert_eq!(
        err,
        r#"factored graph node "//a:x\\n//a:y"; query must use --graph:factored=false"#
    );
}

fn sample_map() -> RdepsMap {
    let edges = parse_graph_edges(SAMPLE_DOT).unwrap();
    compute_rdeps_map(
        "abc",
        &v(&["//app:test", "//other:test"]),
        &edges,
        &v(&["app", "other", "shared", "unused"]),
    )
}

#[test]
fn compute_rdeps_map_follows_external_repos() {
    let m = sample_map();
    let tests = m.tests.unwrap();
    assert_eq!(tests.len(), 3);
    assert_eq!(tests["app"], v(&["//app:test"]));
    assert_eq!(tests["shared"], v(&["//app:test"]));
    assert_eq!(tests["other"], v(&["//other:test"]));
}

#[test]
fn lookup() {
    let m = sample_map();
    assert_eq!(
        m.lookup(&v(&["//shared:all", "//other:all"])),
        Some(v(&["//app:test", "//other:test"]))
    );
    assert_eq!(m.lookup(&v(&["//unused:all"])), Some(vec![]));
    assert_eq!(m.lookup(&v(&["//shared:all", "//brand/new:all"])), None);
}

#[test]
fn load_rdeps_map_checks() {
    let d = tmp("loadmap");
    let p = d.join("map.json");
    let ps = p.to_str().unwrap();
    assert_eq!(load_rdeps_map(ps, "abc"), Ok(None));

    let good = RdepsMap {
        schema: 1,
        commit: "abc".into(),
        packages: Some(v(&["app"])),
        tests: None,
    };
    fs::write(&p, unitfile::gocompat::json::marshal(&good)).unwrap();
    assert!(load_rdeps_map(ps, "abc").unwrap().is_some());
    assert_eq!(
        load_rdeps_map(ps, "def").unwrap_err(),
        r#"map is for commit "abc", diff base is "def""#
    );
    assert!(load_rdeps_map(ps, "").is_err());

    let stale = RdepsMap {
        schema: 2,
        ..good.clone()
    };
    fs::write(&p, unitfile::gocompat::json::marshal(&stale)).unwrap();
    assert_eq!(
        load_rdeps_map(ps, "abc").unwrap_err(),
        "map schema 2, want 1"
    );

    fs::write(&p, "not json").unwrap();
    assert_eq!(
        load_rdeps_map(ps, "abc").unwrap_err(),
        format!("parse {ps}: invalid character 'o' in literal null (expecting 'u')")
    );
    fs::write(&p, r#"{"schema":1,"commit":"abc","packages":[]}"#).unwrap();
    assert_eq!(
        load_rdeps_map(ps, "abc").unwrap_err(),
        "map lists no packages"
    );
    fs::write(&p, r#"{"Schema":"1"}"#).unwrap();
    assert_eq!(
        load_rdeps_map(ps, "abc").unwrap_err(),
        format!("parse {ps}: json: cannot unmarshal string into Go struct field RdepsMap.schema of type int")
    );
}

#[test]
fn internal_query_errors_tell_ours_from_external() {
    let root = "/home/runner/work/repo/repo";
    let stderr = [
        "Loading: 5322 packages loaded",
        "ERROR: /home/runner/.bazel/external/rules_android+/tools/jdk/BUILD:86:27: no such target '@@rules_android++android_sdk_repository_extension+androidsdk//:core-for-system-modules-jar'",
        "ERROR: no such package '@@some_repo//': fetch failed",
        r#"ERROR: Evaluation of query "rdeps(//..., set(//a:all))" failed: errors were encountered while computing transitive closure"#,
    ]
    .join("\n");
    assert!(internal_query_errors(&stderr, root).is_empty());
    for line in [
        format!("ERROR: {root}/apps/x/BUILD:3:1: no such target '//apps/y:z'"),
        "ERROR: Skipping '//apps/x': no such package".to_string(),
        "ERROR: something bazel has never printed before".to_string(),
    ] {
        assert_eq!(internal_query_errors(&line, root).len(), 1, "{line}");
    }
}

#[test]
fn compute_plan_uses_map() {
    let d = tmp("usesmap");
    write(&d, "shared/BUILD", "");
    write(
        &d,
        "app/BUILD",
        "pipeline_unit(\n    name = \"app\",\n    test_targets = [\":test\"],\n)\n",
    );
    write(&d, "app/sub/BUILD", "");
    let edges = parse_graph_edges(SAMPLE_DOT).unwrap();
    let m = compute_rdeps_map(
        "abc",
        &v(&["//app:test"]),
        &edges,
        &v(&["app", "app/sub", "shared"]),
    );
    let failing = Mock::failing();
    let mut e = Engine::new(d.to_str().unwrap(), &failing);
    e.rdeps_map = Some(m);

    let p = e
        .compute_plan(v(&["shared/lib.go"]), "abc", "HEAD")
        .unwrap();
    assert!(!p.is_degraded && p.plan_source == PLAN_SOURCE_MAP);
    assert_eq!(
        p.matrix.iter().map(|m| m.name.as_str()).collect::<Vec<_>>(),
        ["app"]
    );

    let p = e
        .compute_plan(v(&["app/sub/new_test.go"]), "abc", "HEAD")
        .unwrap();
    assert_eq!(
        p.matrix.iter().map(|m| m.name.as_str()).collect::<Vec<_>>(),
        ["app"]
    );

    write(&d, "brandnew/BUILD", "");
    let p = e
        .compute_plan(v(&["brandnew/x.go"]), "abc", "HEAD")
        .unwrap();
    assert!(p.plan_source == PLAN_SOURCE_LIVE && p.is_degraded);
    assert_eq!(
        p.plan_source_note,
        "dependency map does not know every changed package (new package?); used the live query"
    );
}

struct FakeGraph {
    commits: Vec<&'static str>,
    files: HashMap<&'static str, Vec<String>>,
}

impl FakeGraph {
    fn index(&self, c: &str) -> i64 {
        self.commits
            .iter()
            .position(|x| *x == c)
            .map(|i| i as i64)
            .unwrap_or(-1)
    }
}

impl RevGraph for FakeGraph {
    fn is_ancestor(&self, older: &str, newer: &str) -> bool {
        let (o, n) = (self.index(older), self.index(newer));
        o >= 0 && n >= 0 && o <= n
    }
    fn commits_between(&self, older: &str, newer: &str) -> Result<i64, String> {
        Ok(self.index(newer) - self.index(older))
    }
    fn changed_files(&self, older: &str, newer: &str) -> Result<Vec<String>, String> {
        let mut out = Vec::new();
        for i in (self.index(older) + 1)..=self.index(newer) {
            out.extend(
                self.files
                    .get(self.commits[i as usize])
                    .cloned()
                    .unwrap_or_default(),
            );
        }
        Ok(out)
    }
}

#[test]
fn earlier_map_base_rules() {
    let g = FakeGraph {
        commits: vec!["a", "b", "c", "d"],
        files: [
            ("b", v(&["MODULE.bazel"])),
            ("c", v(&["apps/x/main.go"])),
            ("d", v(&["apps/y/main.go"])),
        ]
        .into_iter()
        .collect(),
    };
    let cases: &[(&str, &str, i64, bool, &str)] = &[
        ("c", "d", 9, true, "1 commit(s) back"),
        ("b", "d", 9, true, "2 commit(s) back"),
        ("b", "d", 1, false, "2 commits behind"),
        ("a", "d", 9, false, "MODULE.bazel"),
        ("d", "c", 9, false, "not an ancestor"),
        ("zzz", "d", 9, false, "not an ancestor"),
    ];
    for (m, base, max, ok, why) in cases {
        let (got_ok, got_why) = earlier_map_base(&g, m, base, *max);
        assert!(
            got_ok == *ok && got_why.contains(why),
            "{m}..{base}: ({got_ok}, {got_why})"
        );
    }
    assert_eq!(
        earlier_map_base(&g, "c", "d", 9).1,
        "note: dependency map is from 1 commit(s) back (c); planning against that commit, so everything changed since then counts as changed"
    );
}

#[test]
fn peek_rdeps_map_commit_reads_only_the_commit() {
    let d = tmp("peek");
    let good = d.join("good.json");
    fs::write(&good, r#"{"schema":1,"commit":"abc"}"#).unwrap();
    let bad = d.join("bad.json");
    fs::write(&bad, "not json").unwrap();
    let typed = d.join("typed.json");
    fs::write(&typed, r#"{"commit":5}"#).unwrap();
    assert_eq!(peek_rdeps_map_commit(good.to_str().unwrap()), "abc");
    for p in [bad, typed, d.join("missing.json")] {
        assert_eq!(peek_rdeps_map_commit(p.to_str().unwrap()), "");
    }
}

// ---- units_test.go ----------------------------------------------------------

fn must_read(build: &str, pkg: &str) -> Vec<UnitDef> {
    parse_pipeline_units_from_build(build, pkg).unwrap_or_else(|e| panic!("reading units: {e}"))
}

fn targets(u: &UnitDef) -> Vec<&str> {
    u.test_targets.iter().map(|s| s.as_str()).collect()
}

#[test]
fn unit_with_bracket_in_comment() {
    let u = must_read("\npipeline_unit(\n    name = \"u\",\n    # Built with strict checking (see REFACTOR.md 6zu), so the log is long.\n    runner = \"xcode-27\",\n    test_targets = [\n        \":a\",\n        \":b\",\n    ],\n    timeout_minutes = 60,\n)\n", "pkg");
    assert_eq!(u.len(), 1);
    assert_eq!(targets(&u[0]), ["//pkg:a", "//pkg:b"]);
    assert_eq!(
        (u[0].runner.as_str(), u[0].timeout_minutes),
        ("xcode-27", 60)
    );
}

#[test]
fn unit_with_bracket_in_string() {
    let u = must_read("\npipeline_unit(\n    name = \"u\",\n    build_flags = [\"--test_arg=f(1)]\"],\n    env = {\"NOTE\": 'say \"hi\") }'},\n    runner = \"xcode-27\",\n    test_targets = [\":a\"],\n)\n", "pkg");
    assert_eq!(targets(&u[0]), ["//pkg:a"]);
    assert_eq!(u[0].runner, "xcode-27");
}

#[test]
fn unit_with_triple_quoted_string() {
    let u = must_read("\npipeline_unit(\n    name = \"u\",\n    env = {\"NOTE\": \"\"\"two lines )\nand a \"quote\" ] and an escaped \\\"\"\" inside\"\"\"},\n    test_targets = [\":a\"],\n    tier = \"L2\",\n)\n", "pkg");
    assert_eq!(targets(&u[0]), ["//pkg:a"]);
    assert_eq!(u[0].tier, "L2");
}

#[test]
fn unit_with_nested_calls() {
    let u = must_read("\npipeline_unit(\n    name = \"u\",\n    tags = glob([\"*.tag\"]) + select({\n        \"//conditions:default\": [\"x\"],\n    }),\n    runner = \"xcode-27\",\n    test_targets = [\":a\", \"//other:b\"],\n    depends_on = [\"first\"],\n)\n", "pkg");
    assert_eq!(targets(&u[0]), ["//pkg:a", "//other:b"]);
    assert_eq!(u[0].runner, "xcode-27");
    assert_eq!(u[0].depends_on, v(&["first"]));
}

#[test]
fn target_list_with_bracket_in_comment() {
    let u = must_read("\npipeline_unit(\n    name = \"u\",\n    test_targets = [\n        \":a\",  # flaky on arm64 [#1234]\n        # the list below is sorted (mostly]\n        \":b\",\n    ],\n    runner = \"xcode-27\",\n)\n", "pkg");
    assert_eq!(targets(&u[0]), ["//pkg:a", "//pkg:b"]);
    assert_eq!(u[0].runner, "xcode-27");
}

#[test]
fn commented_out_target_is_not_a_target() {
    let u = must_read("\npipeline_unit(\n    name = \"u\",\n    test_targets = [\n        \":a\",  # replaces \":old\"\n        # \":disabled_test\",  # see [1] (flaky)\n        \":b\",\n    ],\n)\n", "pkg");
    assert_eq!(targets(&u[0]), ["//pkg:a", "//pkg:b"]);
}

#[test]
fn two_units_in_one_file() {
    let u = must_read("\nload(\"//tools/pipeline:defs.bzl\", \"pipeline_unit\")\n\npipeline_unit(\n    name = \"first\",\n    # one (bracketed) comment\n    test_targets = [\":a\"],\n)\n\nfilegroup(name = \"between\", srcs = glob([\"*.txt\"]))\n\npipeline_unit(\n    name = \"second\",\n    runner = \"xcode-27\",\n    test_targets = [\":b\", \":c\"],\n    depends_on = [\"first\"],\n)\n", "pkg");
    assert_eq!(u.len(), 2);
    assert_eq!(targets(&u[0]), ["//pkg:a"]);
    assert_eq!(targets(&u[1]), ["//pkg:b", "//pkg:c"]);
    assert_eq!(
        (u[0].name.as_str(), u[1].name.as_str()),
        ("first", "second")
    );
    assert_eq!(
        (u[0].runner.as_str(), u[1].runner.as_str()),
        ("ubuntu-26.04", "xcode-27")
    );
    assert_eq!(u[1].concurrency_group, "pipeline-second");
}

#[test]
fn unit_as_last_statement_without_newline() {
    let u = must_read(
        "pipeline_unit(name = \"u\", test_targets = [\":a\"],  # (last)\n)",
        "",
    );
    assert_eq!(targets(&u[0]), ["//:a"]);
}

#[test]
fn only_calls_are_units() {
    let u = must_read("\nload(\"//tools/pipeline:defs.bzl\", \"pipeline_unit\")\n\n# pipeline_unit(name = \"commented-out\", test_targets = [\":x\"])\ngenrule(name = \"g\", cmd = \"echo 'pipeline_unit(name = \\\"in-a-string\\\")'\")\n\ndef pipeline_unit(name, test_targets):\n    pass\n\npipeline_unit(name = \"real\", test_targets = [\":a\"])\n", "pkg");
    assert_eq!(u.len(), 1);
    assert_eq!(u[0].name, "real");
}

const DESKTOP_BUILD: &str = r#"load("//tools/delivery:defs.bzl", "delivery")
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
"#;

#[test]
fn desktop_unit_as_it_was_before_the_workaround() {
    let u = must_read(DESKTOP_BUILD, "apps/desktop/vitruvian");
    assert_eq!(u.len(), 1);
    let u = &u[0];
    assert_eq!(u.name, "vitruvian-desktop-macos");
    assert_eq!(u.test_targets.len(), 10);
    assert_eq!(
        (u.runner.as_str(), u.timeout_minutes, u.persona.as_str()),
        ("xcode-27", 60, "frontend")
    );
    assert!(u
        .test_targets
        .contains(&"//apps/desktop/vitruvian:tool_protocol_pin_test".to_string()));
}

#[test]
fn unreadable_unit_is_an_error() {
    let cases = [
        "\npipeline_unit(\n    name = \"broken\",\n    test_targets = [\":a\"],\n",
        "\npipeline_unit(\n    name = \"broken\",\n    test_targets = [\":a\"),\n)\n",
        "\npipeline_unit(\n    name = \"broken\",\n    runner = \"xcode-27,\n    test_targets = [\":a\"],\n)\n",
        "\npipeline_unit(\n    name = \"broken\",\n    test_targets = glob([\"*_test.go\"]),\n)\n",
        "\npipeline_unit(\n    name = \"broken\",\n    test_targets = [\":a\", SOME_CONSTANT],\n)\n",
        "\npipeline_unit(\n    name = \"broken\",\n    test_targets = [\n        # \":a\",\n    ],\n)\n",
        "\npipeline_unit(\n    name = \"broken\",\n    runner = \"xcode-27\",\n)\n",
        "\npipeline_unit(\n    name = \"broken\",\n    runner = MAC_RUNNER,\n    test_targets = [\":a\"],\n)\n",
    ];
    for build in cases {
        let err = parse_pipeline_units_from_build(build, "pkg")
            .err()
            .unwrap_or_else(|| panic!("no error: {build}"));
        assert!(err.contains("broken"), "{err}");
    }
    let err = parse_pipeline_units_from_build(
        "\npipeline_unit(\n    name = PREFIX + \"-unit\",\n    test_targets = [\":a\"],\n)\n",
        "pkg",
    )
    .unwrap_err();
    assert!(err.contains("line 2"), "{err}");
}

#[test]
fn compute_plan_fails_on_an_unreadable_unit() {
    let d = tmp("unreadable");
    write(&d, "apps/broken/BUILD", "\npipeline_unit(\n    name = \"broken-unit\",\n    test_targets = glob([\"*_test.go\"]),\n)\n");
    let runner = Mock::new(&[]);
    let err = Engine::new(d.to_str().unwrap(), &runner)
        .compute_plan(v(&["apps/broken/main.go"]), "main", "HEAD")
        .unwrap_err();
    assert!(err.starts_with("discover pipeline units: cannot read every pipeline unit:\napps/broken/BUILD: line 2: pipeline_unit(name = \"broken-unit\")"), "{err}");
}

#[test]
fn unit_is_selected_through_a_dependency() {
    let d = tmp("throughdep");
    write(&d, "apps/desktop/vitruvian/BUILD", DESKTOP_BUILD);
    write(&d, "packages/tool-protocol/BUILD", "# a package\n");
    let runner = Mock::new(&[(
        "//packages/tool-protocol:all",
        &["//apps/desktop/vitruvian:tool_protocol_pin_test"],
    )]);
    let p = Engine::new(d.to_str().unwrap(), &runner)
        .compute_plan(
            v(&["packages/tool-protocol/Sources/Protocol.swift"]),
            "main",
            "HEAD",
        )
        .unwrap();
    assert_eq!(p.matrix.len(), 1);
    assert_eq!(p.matrix[0].name, "vitruvian-desktop-macos");
    assert_eq!(
        (p.matrix[0].runner.as_str(), p.matrix[0].target_count),
        ("xcode-27", 10)
    );
}

#[test]
fn plan_json_matches_go_shape() {
    let d = tmp("json");
    write(&d, "tabula/web/BUILD", TABULA_BUILD);
    let runner = Mock::new(&[]);
    let mut p = Engine::new(d.to_str().unwrap(), &runner)
        .compute_plan(v(&["tabula/web/x.ts"]), "base<&>", "")
        .unwrap();
    p.duration_ms = 0;
    let got = unitfile::gocompat::json::marshal(&p);
    assert_eq!(
        got,
        r#"{"schema_version":1,"base_rev":"base\u003c\u0026\u003e","head_rev":"","duration_ms":0,"changed_files":["tabula/web/x.ts"],"affected_packages":["//tabula/web:all"],"persona":"frontend-dev","operation":"ui-feature","is_docs_only":false,"is_global_impact":false,"is_degraded":false,"plan_source":"live-query","targets":null,"target_count":0,"matrix":[{"name":"tabula-web","package":"tabula/web","runner":"ubuntu-26.04","tier":"L1","persona":"frontend","targets":["//tabula/web:unit_tests"],"test_targets":"//tabula/web:unit_tests","target_count":1,"timeout_minutes":20,"concurrency_group":"pipeline-tabula-web","is_required":true}]}"#
    );
}
