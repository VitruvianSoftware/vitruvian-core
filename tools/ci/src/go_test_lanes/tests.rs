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

//! Unit tests for //tools/ci:go_test_lanes over scratch trees.

use super::*;
use std::path::PathBuf;

struct Tree(PathBuf);

impl Tree {
    fn new(name: &str) -> Tree {
        let base = std::env::var("TEST_TMPDIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| std::env::temp_dir());
        let p = base.join(format!("go_test_lanes_{name}_{}", std::process::id()));
        let _ = fs::remove_dir_all(&p);
        fs::create_dir_all(&p).unwrap();
        Tree(p)
    }
    fn write(&self, rel: &str, text: &str) -> &Tree {
        let p = self.0.join(rel);
        fs::create_dir_all(p.parent().unwrap()).unwrap();
        fs::write(p, text).unwrap();
        self
    }
    fn module(&self, dir: &str) -> &Tree {
        let rel = if dir.is_empty() {
            "go.mod".to_string()
        } else {
            format!("{dir}/go.mod")
        };
        self.write(&rel, "module x\n")
    }
    fn check(&self, ci: &str, allow: &str) -> Report {
        check(&self.0, ci, allow).unwrap()
    }
}

/// The two ci.yaml shapes the lanes are read from.
const CI: &str = "jobs:\n  go-test-infra:\n    steps:\n      - run: |\n          \"$GO_TEST_WITH_RETRY\"\n  example-build:\n    steps:\n      - run: |\n          \"$GO_TEST_WITH_RETRY\" --root packages/pulumi/examples\n";

fn cover(r: &Report, f: &str) -> Cover {
    r.files
        .get(f)
        .cloned()
        .unwrap_or_else(|| panic!("{f} not found: {:?}", r.files))
}

#[test]
fn each_lane_is_recognised() {
    let t = Tree::new("lanes");
    t.module("").write("pkg/a_test.go", "").write(
        "pkg/BUILD.bazel",
        "go_test(\n    name = \"a_test\",\n    srcs = [\"a_test.go\"],\n)\n",
    );
    t.module("infrastructure/pulumi/x")
        .write("infrastructure/pulumi/x/x_test.go", "");
    t.module("apps/web/site/infra")
        .write("apps/web/site/infra/sub/i_test.go", "");
    t.module("packages/pulumi/examples/e")
        .write("packages/pulumi/examples/e/e_test.go", "");
    let r = t.check(CI, "");
    assert_eq!(cover(&r, "pkg/a_test.go"), Cover::Bazel);
    assert_eq!(
        cover(&r, "infrastructure/pulumi/x/x_test.go"),
        Cover::Job("go-test-infra".into())
    );
    assert_eq!(
        cover(&r, "apps/web/site/infra/sub/i_test.go"),
        Cover::Job("go-test-infra".into())
    );
    assert_eq!(
        cover(&r, "packages/pulumi/examples/e/e_test.go"),
        Cover::Job("example-build".into())
    );
    assert!(r.ok(), "{:?}", r);
}

#[test]
fn a_test_no_lane_runs_is_uncovered() {
    // The #4205 shape: a module with tests, no go_test, under no root.
    let t = Tree::new("uncovered");
    t.module("")
        .module("packages/orphan")
        .write("packages/orphan/o_test.go", "");
    let r = t.check(CI, "");
    assert_eq!(r.uncovered(), vec!["packages/orphan/o_test.go"]);
    assert!(!r.ok());
}

#[test]
fn removing_the_root_from_ci_yaml_uncovers_its_modules() {
    // Lanes come from ci.yaml, so dropping example-build's --root is caught.
    let t = Tree::new("noroot");
    t.module("packages/pulumi/examples/e")
        .write("packages/pulumi/examples/e/e_test.go", "");
    let ci = "jobs:\n  go-test-infra:\n    steps:\n      - run: \"$GO_TEST_WITH_RETRY\"\n";
    assert_eq!(
        t.check(ci, "").uncovered(),
        vec!["packages/pulumi/examples/e/e_test.go"]
    );
}

#[test]
fn a_commented_out_step_is_not_a_lane() {
    let t = Tree::new("comment");
    t.module("packages/pulumi/examples/e")
        .write("packages/pulumi/examples/e/e_test.go", "");
    let ci = "jobs:\n  go-test-infra:\n    steps:\n      - run: \"$GO_TEST_WITH_RETRY\"\n  example-build:\n    #   \"$GO_TEST_WITH_RETRY\" --root packages/pulumi/examples\n";
    assert_eq!(
        t.check(ci, "").uncovered(),
        vec!["packages/pulumi/examples/e/e_test.go"]
    );
}

#[test]
fn no_go_test_with_retry_step_is_an_error() {
    let t = Tree::new("nolanes");
    assert!(check(&t.0, "jobs: {}\n", "").is_err());
}

#[test]
fn a_manual_go_test_does_not_count() {
    let t = Tree::new("manual");
    t.module("")
        .write("pkg/a_test.go", "")
        .write("pkg/BUILD", "go_test(\n    name = \"a_test\",\n    srcs = [\"a_test.go\"],\n    tags = [\"manual\"],\n)\n");
    assert_eq!(t.check(CI, "").uncovered(), vec!["pkg/a_test.go"]);
}

#[test]
fn a_file_missing_from_the_go_test_is_uncovered() {
    // gazelle not re-run after adding b_test.go.
    let t = Tree::new("missing");
    t.module("")
        .write("pkg/a_test.go", "")
        .write("pkg/b_test.go", "")
        .write("pkg/BUILD.bazel", "go_library(name = \"x\")\n\ngo_test(\n    name = \"a_test\",\n    srcs = [\"a_test.go\"],\n)\n");
    assert_eq!(t.check(CI, "").uncovered(), vec!["pkg/b_test.go"]);
}

#[test]
fn ignored_directories_are_skipped() {
    let t = Tree::new("skip");
    t.module("");
    for d in [
        "testdata",
        "vendor",
        "node_modules",
        ".hidden",
        "_tmp",
        "bazel-out",
    ] {
        t.write(&format!("x/{d}/m/go.mod"), "module m\n")
            .write(&format!("x/{d}/m/m_test.go"), "");
    }
    let r = t.check(CI, "");
    assert!(r.files.is_empty(), "{:?}", r.files);
}

#[test]
fn the_allowlist_covers_and_goes_stale() {
    let t = Tree::new("allow");
    t.module("").write("pkg/it_test.go", "");
    let allow = "# why\npkg/it_test.go  # integration tag\n";
    let r = t.check(CI, allow);
    assert_eq!(cover(&r, "pkg/it_test.go"), Cover::Allowlisted);
    assert!(r.ok(), "{:?}", r);

    let r = t.check(CI, "pkg/gone_test.go\n");
    assert!(r.stale[0].contains("no such _test.go"), "{:?}", r.stale);
    assert!(!r.ok());

    t.write(
        "pkg/BUILD",
        "go_test(name = \"t\", srcs = [\"it_test.go\"])\n",
    );
    let r = t.check(CI, allow);
    assert!(r.stale[0].contains("a lane covers it now"), "{:?}", r.stale);
}

#[test]
fn the_shipped_allowlist_parses() {
    let entries = parse_allowlist(ALLOWLIST);
    assert!(
        entries.iter().all(|e| e.ends_with("_test.go")),
        "{entries:?}"
    );
}

#[test]
fn a_data_glob_does_not_cover_an_unlisted_test() {
    // devx usb: srcs lists files, `data = glob(["testdata/**"])`.
    let t = Tree::new("dataglob");
    t.module("")
        .write("pkg/a_test.go", "")
        .write("pkg/it_test.go", "")
        .write("pkg/BUILD", "go_test(\n    name = \"t\",\n    srcs = [\"a_test.go\"],\n    data = glob([\"testdata/**\"]),\n)\n");
    assert_eq!(t.check(CI, "").uncovered(), vec!["pkg/it_test.go"]);
}

#[test]
fn a_srcs_glob_of_tests_covers_them() {
    let t = Tree::new("srcsglob");
    t.module("").write("pkg/a_test.go", "").write(
        "pkg/BUILD",
        "go_test(\n    name = \"t\",\n    srcs = glob([\"*_test.go\"]),\n)\n",
    );
    assert_eq!(cover(&t.check(CI, ""), "pkg/a_test.go"), Cover::Bazel);
}
