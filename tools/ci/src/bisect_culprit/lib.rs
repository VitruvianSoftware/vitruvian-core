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

//! bisect-culprit.sh — mechanical culprit-finding for a red nightly sweep.
//! Bisects [GOOD_SHA, BAD_SHA] with `git bisect run` driving `bazel test`.

use shell_compat::{capture, capture_stdout, cat, env, env_or_empty, err, out, status, subst};
use std::process::Command;

fn rev_parse(rev: &[u8]) -> Option<Vec<u8>> {
    let r = capture(
        51,
        Command::new("git")
            .arg("rev-parse")
            .arg("--verify")
            .arg("--quiet")
            .arg(shell_compat::os(&cat(&[rev, b"^{commit}"]))),
    );
    if r.ok() {
        Some(subst(r.stdout))
    } else {
        None
    }
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let good_sha = match env("GOOD_SHA") {
        Some(v) if !v.is_empty() => v,
        _ => {
            err(b"GOOD_SHA must be set (last green commit)\n");
            return 2;
        }
    };
    let bad_sha = match env("BAD_SHA") {
        Some(v) if !v.is_empty() => v,
        _ => {
            err(b"BAD_SHA must be set (known red commit)\n");
            return 2;
        }
    };
    let targets = match env("TARGETS") {
        Some(v) if !v.is_empty() => v,
        _ => {
            err(b"TARGETS must be set (space-separated Bazel labels)\n");
            return 2;
        }
    };
    let bazel_args = env_or_empty("BAZEL_ARGS");

    let good_resolved = match rev_parse(&good_sha) {
        Some(v) => v,
        None => {
            err(&cat(&[
                b"::error::bisect-culprit: '",
                &good_sha,
                b"' does not resolve to a commit\n",
            ]));
            return 2;
        }
    };
    let bad_resolved = match rev_parse(&bad_sha) {
        Some(v) => v,
        None => {
            err(&cat(&[
                b"::error::bisect-culprit: '",
                &bad_sha,
                b"' does not resolve to a commit\n",
            ]));
            return 2;
        }
    };

    if good_resolved == bad_resolved {
        err(b"::error::bisect-culprit: GOOD_SHA and BAD_SHA are the same commit \xe2\x80\x94 nothing to bisect\n");
        return 2;
    }

    let r = capture(
        79,
        Command::new("git")
            .arg("merge-base")
            .arg("--is-ancestor")
            .arg(shell_compat::os(&good_sha))
            .arg(shell_compat::os(&bad_sha)),
    );
    if !r.ok() {
        err(b"::error::bisect-culprit: GOOD_SHA is not an ancestor of BAD_SHA\n");
        return 2;
    }

    let count_r = capture(
        87,
        Command::new("git")
            .arg("rev-list")
            .arg("--count")
            .arg(shell_compat::os(&cat(&[&good_sha, b"..", &bad_sha]))),
    );
    let count = subst(count_r.stdout);
    let good_short = if good_sha.len() > 12 {
        &good_sha[..12]
    } else {
        &good_sha
    };
    let bad_short = if bad_sha.len() > 12 {
        &bad_sha[..12]
    } else {
        &bad_sha
    };
    out(&cat(&[
        b"bisect-culprit: bisecting ",
        &count,
        b" commit(s) in ",
        good_short,
        b"..",
        bad_short,
        b"\n",
    ]));

    status(
        88,
        Command::new("git")
            .arg("bisect")
            .arg("start")
            .arg(shell_compat::os(&bad_sha))
            .arg(shell_compat::os(&good_sha)),
        false,
    );

    let bisect_log;
    let test_cmd = env("TEST_CMD");
    if let Some(ref cmd) = test_cmd {
        if !cmd.is_empty() {
            let r = capture_stdout(
                97,
                Command::new("git")
                    .arg("bisect")
                    .arg("run")
                    .arg("bash")
                    .arg("-c")
                    .arg(shell_compat::os(cmd)),
            );
            bisect_log = r.stdout.clone();
            out(&r.stdout);
        } else {
            bisect_log = run_bazel_bisect(&bazel_args, &targets);
        }
    } else {
        bisect_log = run_bazel_bisect(&bazel_args, &targets);
    }

    // Reset bisect state
    let _ = capture(84, Command::new("git").arg("bisect").arg("reset"));

    // Parse culprit: "<sha> is the first bad commit" or "<sha> is the first 'bad' commit"
    let mut culprit = Vec::new();
    for line in bisect_log.split(|&c| c == b'\n') {
        if let Some(rest) = find_first_bad(line) {
            culprit = rest;
            break;
        }
    }

    if culprit.is_empty() {
        err(b"::error::bisect-culprit: bisect did not converge on a single first-bad commit (flaky in range, or GOOD_SHA red?)\n");
        return 1;
    }

    let subject_r = capture(
        111,
        Command::new("git")
            .arg("log")
            .arg("-1")
            .arg("--format=%s")
            .arg(shell_compat::os(&culprit)),
    );
    let subject = subst(subject_r.stdout);

    out(&cat(&[
        b"bisect-culprit: culprit=",
        &culprit,
        b" (",
        &subject,
        b")\n",
    ]));

    if let Some(gh_output) = env("GITHUB_OUTPUT") {
        if !gh_output.is_empty() {
            let data = cat(&[
                b"culprit=",
                &culprit,
                b"\nculprit_subject=",
                &subject,
                b"\n",
            ]);
            let _ = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(shell_compat::path(&gh_output))
                .and_then(|mut f| {
                    use std::io::Write;
                    f.write_all(&data)
                });
        }
    }

    0
}

fn run_bazel_bisect(bazel_args: &[u8], targets: &[u8]) -> Vec<u8> {
    let mut cmd = Command::new("git");
    cmd.arg("bisect").arg("run").arg("bazel").arg("test");
    for arg in shell_compat::ifs_split(bazel_args) {
        cmd.arg(shell_compat::os(&arg));
    }
    for target in shell_compat::ifs_split(targets) {
        cmd.arg(shell_compat::os(&target));
    }
    let r = capture_stdout(100, &mut cmd);
    out(&r.stdout);
    r.stdout
}

fn find_first_bad(line: &[u8]) -> Option<Vec<u8>> {
    // Match: <40-hex-sha> is the first bad commit
    // or:    <40-hex-sha> is the first 'bad' commit
    if line.len() < 40 {
        return None;
    }
    let sha = &line[..40];
    if !sha.iter().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    let rest = &line[40..];
    if rest == b" is the first bad commit" || rest == b" is the first 'bad' commit" {
        Some(sha.to_vec())
    } else {
        None
    }
}
