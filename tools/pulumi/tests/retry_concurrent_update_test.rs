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

//! //tools/pulumi:retry-concurrent-update with a stub command and a stub
//! `sleep` that records each wait. Ported 1:1 from the former
//! retry_concurrent_update_test.sh (9 checks), plus the negative-budget case,
//! plus the parity checks that held the binary to the shell
//! retry-concurrent-update.sh it replaced in CI (exit codes, streams, args).

mod common;
use common::*;
use std::path::PathBuf;

const CONFLICT: &str = "error: [409] Conflict: You have a running update for the stack 'tabula-deploy-identity/development'. Your organization does not support concurrent updates.";

struct Run {
    rc: i32,
    n: u32,
    waits: String,
    out: String,
    err: String,
}

/// fake-pulumi fails `fail_times` times with `msg` on stderr (exit 23), then
/// exits 0; every attempt prints "stdout from attempt N".
fn run_retry(fail_times: u32, msg: &str, env: &[(&str, &str)]) -> Run {
    let d = tempdir("retry");
    let stubs = d.join("stubs");
    write_exec(
        &stubs.join("fake-pulumi"),
        r#"#!/usr/bin/env bash
n=0
[ -f "$STUB_COUNT" ] && n="$(cat "$STUB_COUNT")"
n=$((n + 1))
echo "$n" >"$STUB_COUNT"
echo "stdout from attempt $n"
if [ "$n" -le "${STUB_FAIL_TIMES:-0}" ]; then
  echo "$STUB_MSG" >&2
  exit 23
fi
exit 0
"#,
    );
    write_exec(
        &stubs.join("sleep"),
        "#!/usr/bin/env bash\necho \"$1\" >>\"$SLEEP_LOG\"\n",
    );
    let count: PathBuf = d.join("count");
    let sleeps: PathBuf = d.join("sleeps");
    let mut c = cmd(
        &bin("RETRY_CONCURRENT_UPDATE_BIN"),
        &format!("{}:/usr/bin:/bin", stubs.display()),
    );
    c.env("STUB_COUNT", &count)
        .env("SLEEP_LOG", &sleeps)
        .env("STUB_FAIL_TIMES", fail_times.to_string())
        .env("STUB_MSG", msg)
        .args(["fake-pulumi", "up", "--yes"]);
    for (k, v) in env {
        c.env(k, v);
    }
    let o = run(c);
    Run {
        rc: code(&o),
        n: read(&count).trim().parse().unwrap_or(0),
        waits: read(&sleeps).lines().map(|l| format!("{l},")).collect(),
        out: stdout(&o),
        err: stderr(&o),
    }
}

// --- the concurrent-update 409 is retried, then succeeds ---
#[test]
fn conflict_is_retried_then_succeeds() {
    let r = run_retry(2, CONFLICT, &[]);
    assert_eq!((r.rc, r.n), (0, 3), "retried twice, succeeded on attempt 3");
}

#[test]
fn stdout_passes_through_unchanged() {
    let r = run_retry(2, CONFLICT, &[]);
    assert!(r.out.contains("stdout from attempt 3"), "out: {}", r.out);
}

#[test]
fn conflict_still_shown_on_stderr() {
    let r = run_retry(2, CONFLICT, &[]);
    assert!(r.err.contains(CONFLICT), "err: {}", r.err);
}

// --- the wait doubles and is capped ---
#[test]
fn wait_doubles_and_is_capped() {
    let r = run_retry(
        6,
        CONFLICT,
        &[
            ("PULUMI_CONFLICT_RETRY_DELAY", "15"),
            ("PULUMI_CONFLICT_MAX_DELAY", "60"),
        ],
    );
    assert_eq!((r.waits.as_str(), r.rc), ("15,30,60,60,60,60,", 0));
}

// --- the default budget ---
#[test]
fn default_budget_then_own_exit_code() {
    let r = run_retry(99, CONFLICT, &[]);
    assert_eq!(
        (r.rc, r.n, r.waits.as_str()),
        (23, 8, "15,30,60,60,60,60,60,"),
        "8 attempts, ~6 minutes of waiting, then the command's own exit code"
    );
}

#[test]
fn says_it_gave_up() {
    let r = run_retry(99, CONFLICT, &[]);
    assert!(
        r.err
            .contains("still blocked by another update after 8 attempts; giving up."),
        "err: {}",
        r.err
    );
}

// --- anything else fails at once ---
#[test]
fn unrelated_error_not_retried() {
    let r = run_retry(99, "error: provider mis-configured", &[]);
    assert_eq!((r.rc, r.n, r.waits.as_str()), (23, 1, ""));
}

#[test]
fn bare_409_not_retried() {
    let r = run_retry(
        99,
        "error: [409] Conflict: Another update is currently in progress.",
        &[],
    );
    assert_eq!((r.rc, r.n), (23, 1));
}

#[test]
fn marker_without_409_not_retried() {
    let r = run_retry(
        99,
        "warning: this stack does not support concurrent updates",
        &[],
    );
    assert_eq!((r.rc, r.n), (23, 1));
}

// New: a budget below 1 means "no retry" in the shell's integer test
// (`[ 1 -lt -1 ]` is false); it must not fall back to the default 8.
#[test]
fn negative_budget_means_no_retry() {
    let r = run_retry(99, CONFLICT, &[("PULUMI_CONFLICT_MAX_ATTEMPTS", "-1")]);
    assert_eq!((r.rc, r.n, r.waits.as_str()), (23, 1, ""));
}

// New: no arguments is a usage error, exit 2.
#[test]
fn no_args_is_usage_exit_2() {
    let o = run(cmd(&bin("RETRY_CONCURRENT_UPDATE_BIN"), "/usr/bin:/bin"));
    assert_eq!(code(&o), 2);
    assert!(stderr(&o).contains("usage: retry-concurrent-update"));
}

// --- parity with the retired retry-concurrent-update.sh ---------------------

/// Run the binary over `stub` (a bash script installed as `cmd`) with `args`.
/// `$STUB_DIR` is the script's scratch directory.
fn run_stub(stub: &str, args: &[&str], env: &[(&str, &str)]) -> (std::process::Output, PathBuf) {
    let d = tempdir("retry-stub");
    let stubs = d.join("stubs");
    write_exec(&stubs.join("cmd"), stub);
    write_exec(
        &stubs.join("sleep"),
        "#!/usr/bin/env bash\necho \"$1\" >>\"$STUB_DIR/sleeps\"\n",
    );
    let mut c = cmd(
        &bin("RETRY_CONCURRENT_UPDATE_BIN"),
        &format!("{}:/usr/bin:/bin", stubs.display()),
    );
    c.env("STUB_DIR", &d).arg("cmd").args(args);
    for (k, v) in env {
        c.env(k, v);
    }
    (run(c), d)
}

#[test]
fn marker_is_case_insensitive() {
    let r = run_retry(1, "error: [409] Conflict: CONCURRENT UPDATE refused", &[]);
    assert_eq!((r.rc, r.n), (0, 2), "the shell's grep -i matched any case");
}

#[test]
fn announces_each_retry_on_stderr() {
    let r = run_retry(1, CONFLICT, &[]);
    assert!(
        r.err.contains(
            "retry-concurrent-update: attempt 1/8 hit Pulumi's account-wide \
             concurrent-update 409; retrying in 15s"
        ),
        "err: {}",
        r.err
    );
}

#[test]
fn stdout_and_stderr_stay_separate() {
    let r = run_retry(1, CONFLICT, &[]);
    assert!(
        !r.out.contains("[409]"),
        "stderr leaked into stdout: {}",
        r.out
    );
    assert!(
        !r.err.contains("stdout from attempt"),
        "stdout leaked into stderr: {}",
        r.err
    );
}

#[test]
fn args_pass_through_verbatim() {
    let (o, d) = run_stub(
        "#!/usr/bin/env bash\nprintf '%s|' \"$#\" \"$@\" >\"$STUB_DIR/argv\"\n",
        &["up", "--message", "two words", ""],
        &[],
    );
    assert_eq!(code(&o), 0);
    assert_eq!(read(&d.join("argv")), "4|up|--message|two words||");
}

#[test]
fn missing_command_exits_127() {
    let mut c = cmd(&bin("RETRY_CONCURRENT_UPDATE_BIN"), "/usr/bin:/bin");
    c.arg("no-such-command-xyz");
    let o = run(c);
    assert_eq!(code(&o), 127, "bash's status for a command it cannot find");
}

#[test]
fn killed_by_signal_is_128_plus_signal() {
    let (o, d) = run_stub(
        "#!/usr/bin/env bash\necho x >>\"$STUB_DIR/count\"\nkill -TERM $$\n",
        &[],
        &[],
    );
    assert_eq!(
        code(&o),
        143,
        "SIGTERM is 128 + 15, as PIPESTATUS reported it"
    );
    assert_eq!(read(&d.join("count")).lines().count(), 1, "not retried");
}

#[test]
fn conflict_then_other_error_returns_that_error() {
    let (o, d) = run_stub(
        r#"#!/usr/bin/env bash
n=$(cat "$STUB_DIR/n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" >"$STUB_DIR/n"
if [ "$n" -eq 1 ]; then echo "error: [409] Conflict: concurrent update" >&2; exit 23; fi
echo "error: provider mis-configured" >&2
exit 5
"#,
        &[],
        &[],
    );
    assert_eq!(code(&o), 5);
    assert_eq!(read(&d.join("n")).trim(), "2");
    assert_eq!(read(&d.join("sleeps")), "15\n");
    assert!(
        !stderr(&o).contains("giving up"),
        "only a 409 at the budget gives up"
    );
}

#[test]
fn large_stderr_is_streamed_without_deadlock() {
    // Well past a pipe buffer on both streams; a reader that waited for the
    // child before draining stderr would hang here until the test timeout.
    let (o, _d) = run_stub(
        "#!/usr/bin/env bash\nhead -c 1048576 /dev/zero | tr '\\0' e >&2\nhead -c 1048576 /dev/zero | tr '\\0' o\n",
        &[],
        &[],
    );
    assert_eq!(code(&o), 0);
    assert_eq!(o.stderr.len(), 1 << 20);
    assert_eq!(o.stdout.len(), 1 << 20);
}
