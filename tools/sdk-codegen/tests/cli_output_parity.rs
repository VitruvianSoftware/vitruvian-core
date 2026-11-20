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

//! Pins the `sdk-codegen` binary's stdout, stderr, and exit code for normal
//! CLI invocations against the outputs captured from the pre-refactor merge
//! base (`git merge-base origin/main HEAD`).

use std::path::PathBuf;
use std::process::{Command, Output};

fn sdk_codegen_bin() -> PathBuf {
    let rel = std::env::var("SDK_CODEGEN_BIN").expect("SDK_CODEGEN_BIN is set by the BUILD rule");
    std::env::current_dir().unwrap().join(rel)
}

fn run_sdk_codegen(args: &[&str]) -> Output {
    Command::new(sdk_codegen_bin())
        .args(args)
        .env("COLUMNS", "80")
        .env("LINES", "24")
        .env_remove("BUILD_WORKSPACE_DIRECTORY")
        .output()
        .expect("failed to execute sdk-codegen binary")
}

fn assert_output(args: &[&str], expected_code: i32, expected_stdout: &str, expected_stderr: &str) {
    let out = run_sdk_codegen(args);
    assert_eq!(out.status.code(), Some(expected_code), "args: {args:?}");
    assert_eq!(
        String::from_utf8_lossy(&out.stdout),
        expected_stdout,
        "stdout mismatch for {args:?}"
    );
    assert_eq!(
        String::from_utf8_lossy(&out.stderr),
        expected_stderr,
        "stderr mismatch for {args:?}"
    );
}

#[test]
fn cli_help_output_matches_merge_base() {
    assert_output(
        &["--help"],
        0,
        "usage: sdk-codegen [-h] [--check] [--out OUT] [--package PACKAGE]\n\nWrites each kit's generated types from the protocol's schemas.\n\noptions:\n  -h, --help         show this help message and exit\n  --check\n  --out OUT\n  --package PACKAGE  the SDK's folder; found from the repository when left out\n",
        "",
    );
}

#[test]
fn cli_bogus_flag_output_matches_merge_base() {
    assert_output(
        &["--bogus"],
        2,
        "",
        "usage: sdk-codegen [-h] [--check] [--out OUT] [--package PACKAGE]\nsdk-codegen: error: unrecognized arguments: --bogus\n",
    );
}

#[test]
fn cli_out_missing_value_output_matches_merge_base() {
    assert_output(
        &["--out"],
        2,
        "",
        "usage: sdk-codegen [-h] [--check] [--out OUT] [--package PACKAGE]\nsdk-codegen: error: argument --out: expected one argument\n",
    );
}

#[test]
fn cli_check_nonexistent_package_output_matches_merge_base() {
    assert_output(
        &["--check", "--package", "/nonexistent"],
        1,
        "",
        "Traceback (most recent call last):\n  (sdk-codegen-rs: Python's stack frames are not reproduced)\nFileNotFoundError: [Errno 2] No such file or directory: '/nonexistent/protocol/messages.schema.json'\n",
    );
}
