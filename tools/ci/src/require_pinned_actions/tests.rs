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

//! //tools/ci:require_pinned_actions_test -- the commit-SHA pin check, run as
//! a subprocess in throwaway repo trees, and built the way actionlint.yaml
//! builds it: the rustc line in that workflow, run as written with the
//! toolchain's rustc. Every case held for the retired
//! require-pinned-actions.sh (the outputs were compared byte for byte).

use ci_testkit::{bin, write, Output, Run, TempDir};
use std::path::{Path, PathBuf};

const SHA: &str = "0123456789abcdef0123456789abcdef01234567";
const ERROR: &str =
    "::error::Actions must be pinned to a full commit SHA, e.g. 'owner/action@<40-hex sha> # v1.2.3':\n";

fn check_with(binary: &Path, root: &Path) -> Output {
    Run::new(binary).cwd(root).go()
}

fn check(root: &Path) -> Output {
    check_with(&bin("BIN"), root)
}

fn workflow(root: &TempDir, body: &str) {
    write(root.join(".github/workflows/ci.yaml"), body);
}

#[test]
fn a_pinned_action_passes_silently() {
    let t = TempDir::new();
    workflow(
        &t,
        &format!("steps:\n  - uses: actions/checkout@{SHA} # v4\n"),
    );
    let o = check(t.path());
    assert_eq!((o.code, o.all().as_str()), (0, ""));
}

#[test]
fn a_tag_pinned_action_fails_and_is_named() {
    let t = TempDir::new();
    workflow(
        &t,
        &format!("steps:\n  - uses: actions/checkout@{SHA}\n  - uses: actions/setup-go@v5\n"),
    );
    let o = check(t.path());
    assert_eq!(o.code, 1);
    assert_eq!(
        o.stdout,
        format!("{ERROR}.github/workflows/ci.yaml:3:  - uses: actions/setup-go@v5\n")
    );
}

#[test]
fn local_actions_and_comments_are_exempt() {
    let t = TempDir::new();
    workflow(
        &t,
        "steps:\n  - uses: ./.github/actions/setup-bazel\n  # - uses: x/y@v1\n  #uses: x/y@v1\n  - uses: #nothing\n  - uses:\njobs:\n  call:\n    uses: ./.github/workflows/_r.yaml\n",
    );
    let o = check(t.path());
    assert_eq!((o.code, o.all().as_str()), (0, ""), "{}", o.all());
}

#[test]
fn dash_and_bare_uses_are_both_checked() {
    let t = TempDir::new();
    workflow(
        &t,
        "jobs:\n  call:\n    uses: org/repo/.github/workflows/r.yaml@v1\n  s:\n    steps:\n      -   uses:   a/b@main\n      -uses: c/d@v1\n      - name: x\n        uses: docker://alpine:3\n",
    );
    let o = check(t.path());
    assert_eq!(o.code, 1);
    assert_eq!(
        o.stdout,
        format!(
            "{ERROR}.github/workflows/ci.yaml:3:    uses: org/repo/.github/workflows/r.yaml@v1\n\
             .github/workflows/ci.yaml:6:      -   uses:   a/b@main\n\
             .github/workflows/ci.yaml:7:      -uses: c/d@v1\n\
             .github/workflows/ci.yaml:9:        uses: docker://alpine:3\n"
        )
    );
}

#[test]
fn only_forty_lowercase_hex_then_space_or_end_counts_as_a_pin() {
    let t = TempDir::new();
    let upper = SHA.to_uppercase();
    workflow(
        &t,
        &format!(
            "  - uses: a/b@{SHA}0\n  - uses: a/b@{upper}\n  - uses: a/b@{SHA}\t# tab\n  - uses: \"a/b@v1\"\n  - uses: a/b@{SHA}\r\n"
        ),
    );
    let o = check(t.path());
    assert_eq!(o.code, 1);
    assert_eq!(
        o.stdout,
        format!(
            "{ERROR}.github/workflows/ci.yaml:1:  - uses: a/b@{SHA}0\n\
             .github/workflows/ci.yaml:2:  - uses: a/b@{upper}\n\
             .github/workflows/ci.yaml:4:  - uses: \"a/b@v1\"\n"
        )
    );
}

#[test]
fn composite_actions_and_devx_templates_are_checked() {
    let t = TempDir::new();
    write(
        t.join(".github/actions/a/action.yml"),
        "runs:\n  steps:\n    - uses: actions/cache@v4\n",
    );
    write(
        t.join("apps/cli/devx/internal/scaffold/templates/go/ci.yaml.tmpl"),
        "      - uses: actions/setup-go@v5 # {{ .Version }}\n",
    );
    let o = check(t.path());
    assert_eq!(o.code, 1);
    assert_eq!(
        o.stdout,
        format!(
            "{ERROR}.github/actions/a/action.yml:3:    - uses: actions/cache@v4\n\
             apps/cli/devx/internal/scaffold/templates/go/ci.yaml.tmpl:1:      - uses: actions/setup-go@v5 # {{{{ .Version }}}}\n"
        )
    );
}

#[test]
fn no_checked_directory_at_all_passes() {
    let t = TempDir::new();
    write(t.join("README.md"), "uses: a/b@v1\n");
    let o = check(t.path());
    assert_eq!((o.code, o.all().as_str()), (0, ""));
}

#[test]
fn files_outside_the_checked_directories_are_ignored() {
    let t = TempDir::new();
    workflow(&t, &format!("  - uses: a/b@{SHA}\n"));
    write(t.join(".github/dependabot.yml"), "uses: a/b@v1\n");
    write(t.join("apps/cli/devx/other.yaml"), "uses: a/b@v1\n");
    let o = check(t.path());
    assert_eq!((o.code, o.all().as_str()), (0, ""));
}

/// The toolchain's rustc from $(RUSTC), an execroot path into the generated
/// sysroot (`bazel-out/<cfg>/bin/external/<repo>/...`). In the runfiles tree
/// an external repo's files sit at `../<repo>/...` from the workspace root.
fn rustc() -> PathBuf {
    let r = std::env::var("RUSTC").expect("the rust_test passes $(RUSTC)");
    let r = match r.find("external/") {
        Some(i) => format!("../{}", &r[i + "external/".len()..]),
        None => r,
    };
    std::fs::canonicalize(&r).unwrap_or_else(|e| panic!("RUSTC={r}: {e}"))
}

/// The `rustc` lines of actionlint.yaml's pin-check step, exactly as written.
fn workflow_rustc_lines() -> Vec<String> {
    let wf = std::fs::read_to_string(std::env::var("WORKFLOW").unwrap()).unwrap();
    wf.lines()
        .map(str::trim)
        .filter(|l| l.starts_with("rustc ") && l.contains("tools/ci/src/require_pinned_actions/"))
        .map(String::from)
        .collect()
}

#[test]
fn the_workflows_rustc_line_builds_a_working_check() {
    let lines = workflow_rustc_lines();
    assert_eq!(
        lines,
        vec![
            "rustc --edition 2021 -O tools/ci/src/require_pinned_actions/main.rs -o \"$RUNNER_TEMP/require-pinned-actions\""
                .to_string()
        ],
        "actionlint.yaml's build line changed: keep this test running what CI runs"
    );
    let rustc = rustc();
    let runner_temp = TempDir::new();
    // Run from the workspace root of the runfiles, as the workflow runs from
    // the checkout's root, with the toolchain's rustc first on PATH.
    let o = Run::new(Path::new("bash"))
        .arg("-euo")
        .arg("pipefail")
        .arg("-c")
        .arg(&lines[0])
        .env("RUNNER_TEMP", runner_temp.path())
        .env(
            "PATH",
            format!("{}:/usr/bin:/bin", rustc.parent().unwrap().display()),
        )
        .go();
    assert_eq!(o.code, 0, "the workflow's rustc line failed:\n{}", o.all());
    let built = runner_temp.join("require-pinned-actions");
    assert!(
        built.is_file(),
        "rustc wrote no binary at $RUNNER_TEMP/require-pinned-actions"
    );

    let t = TempDir::new();
    workflow(&t, &format!("  - uses: a/b@{SHA}\n  - uses: a/b@v1\n"));
    let o = check_with(&built, t.path());
    assert_eq!(o.code, 1);
    assert_eq!(
        o.stdout,
        format!("{ERROR}.github/workflows/ci.yaml:2:  - uses: a/b@v1\n")
    );
    std::fs::remove_file(t.join(".github/workflows/ci.yaml")).unwrap();
    assert_eq!(check_with(&built, t.path()).code, 0);
}
