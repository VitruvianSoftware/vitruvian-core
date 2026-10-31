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

//! bisect-culprit — mechanical culprit-finding for a red nightly sweep.
//! Bisects [GOOD_SHA, BAD_SHA] with `git bisect run` driving `bazel test`.

use shell_compat::{capture, cat, env, env_or_empty, err, out, spawn_diag, status, subst};
use std::io::Read;
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};

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
            // bash's `${VAR:?msg}` in a non-interactive script: message, status 1.
            err(b"bisect-culprit: GOOD_SHA: GOOD_SHA must be set (last green commit)\n");
            return 1;
        }
    };
    let bad_sha = match env("BAD_SHA") {
        Some(v) if !v.is_empty() => v,
        _ => {
            // bash's `${VAR:?msg}` in a non-interactive script: message, status 1.
            err(b"bisect-culprit: BAD_SHA: BAD_SHA must be set (known red commit)\n");
            return 1;
        }
    };
    let targets = match env("TARGETS") {
        Some(v) if !v.is_empty() => v,
        _ => {
            // bash's `${VAR:?msg}` in a non-interactive script: message, status 1.
            err(b"bisect-culprit: TARGETS: TARGETS must be set (space-separated Bazel labels)\n");
            return 1;
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

    // The script runs under `set -e`, so a refused `git bisect start` ends it
    // here with 1 (and the EXIT trap resets bisect state).
    let start_rc = status(
        88,
        Command::new("git")
            .arg("bisect")
            .arg("start")
            .arg(shell_compat::os(&bad_sha))
            .arg(shell_compat::os(&good_sha)),
        false,
    );
    if start_rc != 0 {
        let _ = capture(84, Command::new("git").arg("bisect").arg("reset"));
        return 1;
    }

    // `git bisect run ... 2>&1 | tee LOG`: the child's stdout and stderr both go
    // to our stdout as they arrive, and are kept to read the verdict from.
    let bisect_log = match env("TEST_CMD") {
        Some(cmd) if !cmd.is_empty() => {
            let mut c = Command::new("git");
            c.arg("bisect")
                .arg("run")
                .arg("bash")
                .arg("-c")
                .arg(shell_compat::os(&cmd));
            tee_run(97, &mut c)
        }
        _ => run_bazel_bisect(&bazel_args, &targets),
    };

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
    tee_run(100, &mut cmd)
}

/// Run `cmd` with its stdout and stderr merged onto our stdout, line by line as
/// they arrive (a bisect over a long range must not be silent for hours), and
/// return everything it printed. The exit status is ignored, as in the script
/// (`|| true`): the verdict is read from the log.
fn tee_run(line: u32, cmd: &mut Command) -> Vec<u8> {
    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            err(&spawn_diag(line, cmd, &e));
            return Vec::new();
        }
    };
    let log: Arc<Mutex<Vec<u8>>> = Arc::new(Mutex::new(Vec::new()));
    let mut handles = Vec::new();
    let pipes: [Box<dyn Read + Send>; 2] = [
        Box::new(child.stdout.take().expect("piped stdout")),
        Box::new(child.stderr.take().expect("piped stderr")),
    ];
    for mut pipe in pipes {
        let log = Arc::clone(&log);
        handles.push(std::thread::spawn(move || {
            let mut buf = [0u8; 4096];
            let mut pending: Vec<u8> = Vec::new();
            loop {
                let n = match pipe.read(&mut buf) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => n,
                };
                pending.extend_from_slice(&buf[..n]);
                while let Some(i) = pending.iter().position(|&c| c == b'\n') {
                    let line: Vec<u8> = pending.drain(..=i).collect();
                    let mut g = log.lock().unwrap();
                    out(&line);
                    g.extend_from_slice(&line);
                }
            }
            if !pending.is_empty() {
                let mut g = log.lock().unwrap();
                out(&pending);
                g.extend_from_slice(&pending);
            }
        }));
    }
    for h in handles {
        let _ = h.join();
    }
    let _ = child.wait();
    let g = log.lock().unwrap();
    g.clone()
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
