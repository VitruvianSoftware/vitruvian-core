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
        // Unique per call: tests run in parallel and may share a `name`.
        static N: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        let n = N.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        let p = base.join(format!("go_test_lanes_{name}_{}_{n}", std::process::id()));
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

// --- aegis review on #4212: things that must NOT read as covered ---------

#[test]
fn a_commented_out_go_test_does_not_count() {
    let t = Tree::new("commented");
    t.module("").write("pkg/a_test.go", "").write(
        "pkg/BUILD",
        "# go_test(\n#     name = \"a_test\",\n#     srcs = [\"a_test.go\"],\n# )\n",
    );
    assert_eq!(t.check(CI, "").uncovered(), vec!["pkg/a_test.go"]);
}

#[test]
fn a_trailing_comment_naming_the_file_does_not_count() {
    let t = Tree::new("trailing");
    t.module("").write("pkg/a_test.go", "").write(
        "pkg/BUILD",
        "go_test(\n    name = \"t\",\n    srcs = [],  # was \"a_test.go\"\n)\n",
    );
    assert_eq!(t.check(CI, "").uncovered(), vec!["pkg/a_test.go"]);
}

#[test]
fn a_hash_inside_a_string_is_not_a_comment() {
    let t = Tree::new("hashstr");
    t.module("").write("pkg/a_test.go", "").write(
        "pkg/BUILD",
        "go_test(\n    name = \"t\",\n    args = [\"--x=#1\"],\n    srcs = [\"a_test.go\"],\n)\n",
    );
    assert_eq!(cover(&t.check(CI, ""), "pkg/a_test.go"), Cover::Bazel);
}

#[test]
fn a_bazelignored_go_test_does_not_count() {
    let t = Tree::new("bazelignore");
    t.module("")
        .write(".bazelignore", "tools/initializer\n")
        .write("tools/initializer/a_test.go", "")
        .write(
            "tools/initializer/BUILD",
            "go_test(name = \"t\", srcs = [\"a_test.go\"])\n",
        );
    assert_eq!(
        t.check(CI, "").uncovered(),
        vec!["tools/initializer/a_test.go"]
    );
}

/// A realistic example-build job: `body` replaces the job's `if:` line and
/// `cmd` the test command; `step_extra` goes on the test step.
fn example_job(job_if: &str, step_extra: &str, cmd: &str) -> String {
    format!(
        "name: CI\non:\n  pull_request:\njobs:\n  example-build:\n    {job_if}\n    runs-on: ubuntu\n    steps:\n      - uses: actions/checkout@x\n      - name: go test\n{step_extra}        env:\n          GO_TEST_WITH_RETRY: x\n        run: |\n          set -euo pipefail\n          {cmd}\n"
    )
}

fn example_tree(name: &str) -> Tree {
    let t = Tree::new(name);
    t.module("packages/pulumi/examples/e")
        .write("packages/pulumi/examples/e/e_test.go", "");
    t
}

const EX_CMD: &str = "\"$GO_TEST_WITH_RETRY\" --root packages/pulumi/examples";

#[test]
fn a_live_lane_counts() {
    let t = example_tree("live");
    let ci = example_job(
        "if: ${{ !cancelled() && needs.changes.outputs.x == 'true' }}",
        "        if: steps.gate.outputs.relevant != 'false'\n",
        EX_CMD,
    );
    let r = t.check(&ci, "");
    assert!(r.ok(), "{:?}", r);
    assert!(r.disabled.is_empty(), "{:?}", r.disabled);
}

#[test]
fn a_job_that_never_runs_is_not_a_lane() {
    for job_if in [
        "if: false",
        "if: ${{ false }}",
        "if: 'false'",
        "if: ${{ false && github.event_name == 'push' }}",
    ] {
        let t = example_tree("jobfalse");
        let r = t.check(&example_job(job_if, "", EX_CMD), "");
        assert_eq!(
            r.uncovered(),
            vec!["packages/pulumi/examples/e/e_test.go"],
            "{job_if}"
        );
        assert!(
            r.disabled[0].1.contains("never runs"),
            "{job_if}: {:?}",
            r.disabled
        );
    }
}

#[test]
fn a_step_that_never_runs_is_not_a_lane() {
    let t = example_tree("stepfalse");
    let r = t.check(
        &example_job("if: always()", "        if: false\n", EX_CMD),
        "",
    );
    assert_eq!(r.uncovered().len(), 1);
    assert!(
        r.disabled[0].1.contains("step `if: false`"),
        "{:?}",
        r.disabled
    );
}

#[test]
fn continue_on_error_is_not_a_lane() {
    let t = example_tree("coe");
    let r = t.check(
        &example_job("if: always()", "        continue-on-error: true\n", EX_CMD),
        "",
    );
    assert_eq!(r.uncovered().len(), 1, "step-level");
    let r = t.check(&example_job("continue-on-error: true", "", EX_CMD), "");
    assert_eq!(r.uncovered().len(), 1, "job-level");
}

#[test]
fn a_swallowed_status_is_not_a_lane() {
    for tail in [
        " || true",
        " || :",
        "; true",
        " | tee log",
        " &",
        " || echo failed",
    ] {
        let t = example_tree("swallow");
        let r = t.check(
            &example_job("if: always()", "", &format!("{EX_CMD}{tail}")),
            "",
        );
        assert_eq!(r.uncovered().len(), 1, "`{tail}` must not count");
    }
}

#[test]
fn a_swallow_on_a_continuation_line_is_caught() {
    let t = example_tree("cont");
    let r = t.check(
        &example_job(
            "if: always()",
            "",
            &format!("{EX_CMD} \\\n            || true"),
        ),
        "",
    );
    assert_eq!(r.uncovered().len(), 1);
}

#[test]
fn set_plus_e_with_a_later_command_is_not_a_lane() {
    let t = example_tree("setplus");
    let r = t.check(
        &example_job(
            "if: always()",
            "",
            &format!("set +e\n          {EX_CMD}\n          echo done"),
        ),
        "",
    );
    assert_eq!(r.uncovered().len(), 1);
}

// --- aegis second review on #4212 -----------------------------------------

/// `lines` as the run block, each at the block's 10-space indent.
fn block(lines: &[&str]) -> String {
    lines.join("\n          ")
}

#[test]
fn something_before_the_call_is_not_a_lane() {
    for cmd in [
        format!("! {EX_CMD}"),
        format!("true || {EX_CMD}"),
        format!("[ -n \"$X\" ] && {EX_CMD}"),
        format!("bash -c '{EX_CMD}'"),
    ] {
        let t = example_tree("before");
        let r = t.check(&example_job("if: always()", "", &cmd), "");
        assert_eq!(r.uncovered().len(), 1, "`{cmd}` must not count");
    }
}

#[test]
fn a_call_continuing_the_previous_line_is_not_a_lane() {
    for prev in ["true \\", "false &&", "true ||", "echo x |"] {
        let t = example_tree("cont2");
        let r = t.check(
            &example_job("if: always()", "", &block(&[prev, EX_CMD])),
            "",
        );
        assert_eq!(r.uncovered().len(), 1, "after `{prev}`");
    }
}

#[test]
fn a_call_inside_a_block_is_not_a_lane() {
    for (open, close) in [
        ("if false; then", "fi"),
        ("for x in; do", "done"),
        ("while false; do", "done"),
        ("case x in y)", "esac"),
        ("f() {", "}"),
        ("(", ")"),
        ("{", "}"),
    ] {
        let t = example_tree("nested");
        let r = t.check(
            &example_job("if: always()", "", &block(&[open, EX_CMD, close])),
            "",
        );
        assert_eq!(r.uncovered().len(), 1, "inside `{open}`");
        assert!(r.disabled[0].1.contains("inside"), "{:?}", r.disabled);
    }
}

#[test]
fn a_closed_block_before_the_call_is_fine() {
    let t = example_tree("closed");
    let cmd = block(&[
        "if [ -n \"$X\" ]; then echo x; fi",
        "for f in a b; do",
        "  echo \"$f\"",
        "done",
        EX_CMD,
    ]);
    let r = t.check(&example_job("if: always()", "", &cmd), "");
    assert!(r.ok(), "{:?}", r);
}

#[test]
fn an_earlier_exit_is_not_a_lane() {
    for prev in ["exit 0", "[ -z \"$X\" ] || exit 0", "test -f x && exit"] {
        let t = example_tree("exit");
        let r = t.check(
            &example_job("if: always()", "", &block(&[prev, EX_CMD])),
            "",
        );
        assert_eq!(r.uncovered().len(), 1, "after `{prev}`");
    }
}

/// The real wiring, in small: a `changes` job runs paths-filter, a `decide`
/// step `say`s one output per filter, the job maps them in `outputs:`, and
/// go-test-infra's job and step `if:`s read them. Each knob replaces one
/// link, so a test can break exactly that link.
struct Wiring<'a> {
    ex_globs: &'a [&'a str],
    /// `changes` job `outputs:` lines.
    outputs: &'a str,
    /// `say` lines in the decide step.
    says: &'a str,
    job_if: &'a str,
    step_output: &'a str,
}

impl Default for Wiring<'_> {
    fn default() -> Self {
        Wiring {
            ex_globs: &["packages/pulumi/examples/**"],
            outputs: "      go-test-iac: ${{ steps.decide.outputs.go-test-iac }}\n      go-test-examples: ${{ steps.decide.outputs.go-test-examples }}\n",
            says: "say go-test-iac \"$IAC\"\n          say go-test-examples \"$EX\"",
            job_if: "${{ !cancelled() && (needs.changes.result != 'success' || needs.changes.outputs.go-test-iac == 'true' || needs.changes.outputs.go-test-examples == 'true') }}",
            step_output: "go-test-examples",
        }
    }
}

impl Wiring<'_> {
    fn ci(&self) -> String {
        let g: String = self
            .ex_globs
            .iter()
            .map(|g| format!("              - '{g}'\n"))
            .collect();
        format!(
            "name: CI\njobs:\n  changes:\n    runs-on: x\n    outputs:\n{outputs}    steps:\n      - id: filter\n        uses: dorny/paths-filter@x\n        with:\n          filters: |\n            iac:\n              - 'infrastructure/pulumi/**'\n            ex:\n{g}      - name: Decide\n        id: decide\n        env:\n          IAC: ${{{{ steps.filter.outputs.iac }}}}\n          EX: ${{{{ steps.filter.outputs.ex }}}}\n        run: |\n          {says}\n  go-test-infra:\n    needs: [changes]\n    if: {job_if}\n    steps:\n      - name: go test\n        if: needs.changes.result != 'success' || needs.changes.outputs.{step} == 'true'\n        run: |\n          set -euo pipefail\n          {EX_CMD}\n",
            outputs = self.outputs,
            says = self.says,
            job_if = self.job_if,
            step = self.step_output,
        )
    }
}

fn filtered_ci(globs: &[&str], output: &str) -> String {
    Wiring {
        ex_globs: globs,
        step_output: output,
        ..Wiring::default()
    }
    .ci()
}

fn assert_not_a_lane(ci: &str, reason: &str) {
    let t = example_tree("wiring");
    let r = t.check(ci, "");
    assert_eq!(
        r.uncovered(),
        vec!["packages/pulumi/examples/e/e_test.go"],
        "{:?}",
        r.disabled
    );
    assert!(
        r.disabled.iter().any(|(_, w)| w.contains(reason)),
        "want `{reason}`: {:?}",
        r.disabled
    );
}

#[test]
fn the_real_wiring_is_a_lane() {
    let t = example_tree("wiringok");
    let r = t.check(&Wiring::default().ci(), "");
    assert!(r.ok(), "{:?}", r);
}

#[test]
fn n8_a_job_gate_fed_by_the_iac_filter_only_is_not_a_lane() {
    // aegis N8: main's `say go-test-infra "$IAC"`, brought back by a revert.
    let w = Wiring {
        outputs: "      go-test-infra: ${{ steps.decide.outputs.go-test-infra }}\n      go-test-examples: ${{ steps.decide.outputs.go-test-examples }}\n",
        says: "say go-test-infra \"$IAC\"\n          say go-test-examples \"$EX\"",
        job_if: "${{ needs.changes.result != 'success' || needs.changes.outputs.go-test-infra == 'true' }}",
        ..Wiring::default()
    };
    assert_not_a_lane(&w.ci(), "job `if:` path filter `iac` does not match");
}

#[test]
fn n5_a_job_gate_reading_only_the_iac_output_is_not_a_lane() {
    let w = Wiring {
        job_if: "${{ needs.changes.result != 'success' || needs.changes.outputs.go-test-iac == 'true' }}",
        ..Wiring::default()
    };
    assert_not_a_lane(&w.ci(), "job `if:` path filter `iac` does not match");
}

#[test]
fn n4_a_typo_in_the_outputs_map_is_not_a_lane() {
    let w = Wiring {
        outputs: "      go-test-iac: ${{ steps.decide.outputs.go-test-iac }}\n      go-test-examples: ${{ steps.decide.outputs.go-test-exmpls }}\n",
        ..Wiring::default()
    };
    assert_not_a_lane(&w.ci(), "never sets");
}

#[test]
fn a_missing_output_or_step_id_is_not_a_lane() {
    let w = Wiring {
        outputs: "      go-test-iac: ${{ steps.decide.outputs.go-test-iac }}\n",
        ..Wiring::default()
    };
    assert_not_a_lane(&w.ci(), "has no output `go-test-examples`");
    let w = Wiring {
        outputs: "      go-test-iac: ${{ steps.decide.outputs.go-test-iac }}\n      go-test-examples: ${{ steps.decid.outputs.go-test-examples }}\n",
        ..Wiring::default()
    };
    assert_not_a_lane(&w.ci(), "reads step `decid`");
}

#[test]
fn a_job_gate_anding_the_filters_is_not_a_lane() {
    let w = Wiring {
        job_if: "${{ needs.changes.outputs.go-test-iac == 'true' && needs.changes.outputs.go-test-examples == 'true' }}",
        ..Wiring::default()
    };
    assert_not_a_lane(&w.ci(), "combines path filters with &&");
}

#[test]
fn a_job_gate_dropping_the_fail_safe_is_not_a_lane() {
    let w = Wiring {
        job_if: "${{ needs.changes.outputs.go-test-iac == 'true' || needs.changes.outputs.go-test-examples == 'true' }}",
        ..Wiring::default()
    };
    assert_not_a_lane(&w.ci(), "drops the step's fail-safe");
}

#[test]
fn a_job_gate_on_no_path_filter_is_fine() {
    let w = Wiring {
        job_if: "${{ !cancelled() }}",
        ..Wiring::default()
    };
    let t = example_tree("nojobfilter");
    assert!(t.check(&w.ci(), "").ok());
}

#[test]
fn a_filter_that_matches_the_whole_root_is_a_lane() {
    for globs in [
        vec!["packages/pulumi/examples/**"],
        vec!["packages/pulumi/**"],
        vec![
            "packages/pulumi/examples/**/*.go",
            "packages/pulumi/examples/**/go.mod",
            "packages/pulumi/examples/**/go.sum",
        ],
    ] {
        let t = example_tree("filterok");
        let r = t.check(&filtered_ci(&globs, "go-test-examples"), "");
        assert!(r.ok(), "{globs:?}: {:?}", r);
    }
}

#[test]
fn a_filter_narrower_than_the_root_is_not_a_lane() {
    // The #4212 review repro: a new py-foundation/ tree the filter missed.
    for globs in [
        vec!["packages/pulumi/examples/go-foundation/**"],
        vec![
            "packages/pulumi/examples/**/*.go",
            "packages/pulumi/examples/**/go.mod",
        ],
        vec!["packages/pulumi/examples/*.go"],
    ] {
        let t = example_tree("filternarrow");
        let r = t.check(&filtered_ci(&globs, "go-test-examples"), "");
        assert_eq!(r.uncovered().len(), 1, "{globs:?}");
        assert!(
            r.disabled[0].1.contains("path filter `ex`"),
            "{:?}",
            r.disabled
        );
    }
}

#[test]
fn an_if_reading_an_unknown_output_is_not_a_lane() {
    let t = example_tree("nooutput");
    let r = t.check(
        &filtered_ci(&["packages/pulumi/examples/**"], "no-such-output"),
        "",
    );
    assert_eq!(r.uncovered().len(), 1);
    assert!(
        r.disabled[0].1.contains("has no output `no-such-output`"),
        "{:?}",
        r.disabled
    );
}

// --- aegis non-blocking findings on #4212 (follow-up) ---------------------

const OUT_EX: &str = "needs.changes.outputs.go-test-examples";
const OUT_IAC: &str = "needs.changes.outputs.go-test-iac";

#[test]
fn a_job_gate_comparison_must_mean_the_filter_matched() {
    for cmp in ["== 'false'", "!= 'true'", "== \"false\"", "== 'yes'"] {
        let job_if = format!(
            "${{{{ needs.changes.result != 'success' || {OUT_IAC} == 'true' || {OUT_EX} {cmp} }}}}"
        );
        let w = Wiring {
            job_if: &job_if,
            ..Wiring::default()
        };
        assert_not_a_lane(&w.ci(), "only == 'true' or != 'false'");
    }
}

#[test]
fn a_step_gate_comparison_must_mean_the_filter_matched() {
    let t = example_tree("stepcmp");
    let ci = Wiring::default().ci().replace(
        &format!("|| {OUT_EX} == 'true'\n"),
        &format!("|| {OUT_EX} == 'false'\n"),
    );
    assert!(ci.contains("== 'false'\n"), "fixture changed");
    let r = t.check(&ci, "");
    assert_eq!(r.uncovered().len(), 1, "{:?}", r.disabled);
}

#[test]
fn a_bare_or_negated_read_is_not_a_lane() {
    for gate in [
        format!("{OUT_EX}"),
        format!("!{OUT_EX}"),
        format!("!({OUT_EX} == 'true')"),
    ] {
        let job_if = format!(
            "${{{{ needs.changes.result != 'success' || {OUT_IAC} == 'true' || {gate} }}}}"
        );
        let w = Wiring {
            job_if: &job_if,
            ..Wiring::default()
        };
        let t = example_tree("bare");
        let r = t.check(&w.ci(), "");
        assert_eq!(
            r.uncovered().len(),
            1,
            "`{gate}` must not count: {:?}",
            r.disabled
        );
    }
}

#[test]
fn run_unless_sure_counts() {
    let job_if = format!("${{{{ needs.changes.result != 'success' || {OUT_IAC} != 'false' || {OUT_EX} != 'false' }}}}");
    let w = Wiring {
        job_if: &job_if,
        ..Wiring::default()
    };
    let t = example_tree("unlesssure");
    let r = t.check(&w.ci(), "");
    assert!(r.ok(), "{:?}", r);
}

#[test]
fn a_failure_or_cancelled_gate_is_not_a_lane() {
    for prefix in ["failure() && ", "cancelled() && ", "( failure() ) && "] {
        let job_if = format!("${{{{ {prefix}(needs.changes.result != 'success' || {OUT_IAC} == 'true' || {OUT_EX} == 'true') }}}}");
        let w = Wiring {
            job_if: &job_if,
            ..Wiring::default()
        };
        assert_not_a_lane(&w.ci(), "runs only on");
    }
    // The real gate's `!cancelled()` is the opposite, and fine.
    let t = example_tree("notcancelled");
    assert!(t.check(&Wiring::default().ci(), "").ok());
}
