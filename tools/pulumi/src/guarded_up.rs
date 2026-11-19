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

//! Atomically runs `pulumi preview --json` -> `refuse_destructive_plan` ->
//! `pulumi up` as one unit, retrying the WHOLE unit on Pulumi Cloud's
//! concurrent-update 409 so `pulumi up` never applies a plan that the guard
//! has not checked on the current attempt.
//!
//! Standard library only and free of `crate::` paths ON PURPOSE: CI workflows
//! without Bazel build the binary straight from the checkout with
//! `rustc --edition 2021 -O tools/pulumi/src/bin/guarded_up.rs`, which pulls
//! sibling modules in by `#[path]`. Keep it that way.

use std::io::{Read, Write};
use std::process::{Command, Stdio};

use super::refuse_destructive_plan;
use super::retry_concurrent_update::{
    exit_code, is_concurrent_conflict, sleep_seconds, tee_stderr, RetryPolicy,
};

#[derive(Debug, Clone)]
pub struct CommandCapture {
    pub code: i32,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

pub trait StepRunner {
    fn preview_json(&mut self) -> Result<CommandCapture, i32>;
    fn check_plan(&mut self, label: &str, plan_json: &str) -> i32;
    fn up(&mut self) -> Result<(i32, Vec<u8>), i32>;
    fn sleep(&mut self, seconds: u64);
}

fn spawn_error_code(err: &std::io::Error) -> i32 {
    if err.kind() == std::io::ErrorKind::NotFound {
        127
    } else {
        126
    }
}

fn drain_pipe(mut pipe: impl Read + Send + 'static) -> std::thread::JoinHandle<Vec<u8>> {
    std::thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = pipe.read_to_end(&mut buf);
        buf
    })
}

struct ProcessRunner;

impl StepRunner for ProcessRunner {
    fn preview_json(&mut self) -> Result<CommandCapture, i32> {
        let mut child = Command::new("pulumi")
            .args(["preview", "--json", "--non-interactive"])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| {
                eprintln!("pulumi: {e}");
                spawn_error_code(&e)
            })?;

        let out_handle = drain_pipe(child.stdout.take().unwrap());
        let err_handle = drain_pipe(child.stderr.take().unwrap());

        let status = child.wait().map_err(|_| 1)?;
        let stdout = out_handle.join().unwrap_or_default();
        let stderr = err_handle.join().unwrap_or_default();
        Ok(CommandCapture {
            code: exit_code(status),
            stdout,
            stderr,
        })
    }

    fn check_plan(&mut self, label: &str, plan_json: &str) -> i32 {
        let rc = refuse_destructive_plan::check_and_report(label, plan_json);
        let _ = std::io::stdout().flush();
        let _ = std::io::stderr().flush();
        rc
    }

    fn up(&mut self) -> Result<(i32, Vec<u8>), i32> {
        let mut child = Command::new("pulumi")
            .args(["up", "--yes", "--diff", "--non-interactive"])
            .stdout(Stdio::inherit())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| {
                eprintln!("pulumi: {e}");
                spawn_error_code(&e)
            })?;

        let captured = tee_stderr(child.stderr.take().unwrap());
        let status = child.wait().map_err(|_| 1)?;
        let _ = std::io::stdout().flush();
        let _ = std::io::stderr().flush();
        Ok((exit_code(status), captured))
    }

    fn sleep(&mut self, seconds: u64) {
        sleep_seconds(seconds);
    }
}

pub fn run_with_runner(label: &str, policy: RetryPolicy, runner: &mut dyn StepRunner) -> i32 {
    let mut attempt: i64 = 1;
    let mut delay = policy.initial_delay;

    loop {
        let preview = match runner.preview_json() {
            Ok(cap) => cap,
            Err(rc) => return rc,
        };
        if preview.code != 0 {
            let _ = std::io::stderr().write_all(&preview.stderr);
            let _ = std::io::stderr().flush();
            if attempt < policy.max && is_concurrent_conflict(&preview.stderr) {
                let wait = delay.min(policy.cap);
                eprintln!(
                    "guarded-up: attempt {}/{} hit Pulumi's account-wide concurrent-update 409 \
                     during preview; retrying preview+guard+up in {}s",
                    attempt, policy.max, wait
                );
                let _ = std::io::stderr().flush();
                runner.sleep(wait);
                attempt += 1;
                delay = delay.saturating_mul(2);
                continue;
            }
            if attempt >= policy.max && is_concurrent_conflict(&preview.stderr) {
                eprintln!(
                    "guarded-up: still blocked by another update after {} attempts; giving up.",
                    policy.max
                );
            }
            return preview.code;
        }

        let plan_json = match std::str::from_utf8(&preview.stdout) {
            Ok(s) => s,
            Err(e) => {
                eprintln!(
                    "::error::Refusing to apply {label}: Pulumi preview JSON is not valid UTF-8 ({e}); failing closed."
                );
                eprintln!(
                    "error: Refusing to apply {label}: Pulumi preview JSON is not valid UTF-8 ({e}); failing closed."
                );
                return 1;
            }
        };
        let guard_rc = runner.check_plan(label, plan_json);
        if guard_rc != 0 {
            return guard_rc;
        }

        let (up_rc, up_stderr) = match runner.up() {
            Ok(res) => res,
            Err(rc) => return rc,
        };
        if up_rc == 0 {
            return 0;
        }

        if attempt < policy.max && is_concurrent_conflict(&up_stderr) {
            let wait = delay.min(policy.cap);
            eprintln!(
                "guarded-up: attempt {}/{} hit Pulumi's account-wide concurrent-update 409 \
                 during up; retrying preview+guard+up in {}s",
                attempt, policy.max, wait
            );
            let _ = std::io::stderr().flush();
            runner.sleep(wait);
            attempt += 1;
            delay = delay.saturating_mul(2);
            continue;
        }
        if attempt >= policy.max && is_concurrent_conflict(&up_stderr) {
            eprintln!(
                "guarded-up: still blocked by another update after {} attempts; giving up.",
                policy.max
            );
        }
        return up_rc;
    }
}

/// Entry point: `guarded-up <stack-label>`.
pub fn run(args: &[String]) -> i32 {
    if args.len() != 1 || args[0].trim().is_empty() {
        eprintln!("usage: guarded-up <stack-label>");
        return 2;
    }
    let policy = RetryPolicy::from_env();
    let mut runner = ProcessRunner;
    run_with_runner(&args[0], policy, &mut runner)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::VecDeque;

    const CONFLICT: &[u8] = b"error: [409] Conflict: concurrent update in progress";
    const SAFE_JSON: &str =
        r#"{"steps":[{"op":"same","urn":"urn:pulumi:p::s::t::n"}],"changeSummary":{"same":1}}"#;
    const DESTRUCTIVE_JSON: &str =
        r#"{"steps":[{"op":"delete","urn":"urn:pulumi:p::s::t::n"}],"changeSummary":{"delete":1}}"#;

    struct MockRunner {
        previews: VecDeque<CommandCapture>,
        ups: VecDeque<(i32, Vec<u8>)>,
        events: Vec<String>,
        sleeps: Vec<u64>,
    }

    impl MockRunner {
        fn new(previews: Vec<CommandCapture>, ups: Vec<(i32, Vec<u8>)>) -> Self {
            Self {
                previews: previews.into(),
                ups: ups.into(),
                events: Vec::new(),
                sleeps: Vec::new(),
            }
        }
    }

    impl StepRunner for MockRunner {
        fn preview_json(&mut self) -> Result<CommandCapture, i32> {
            self.events.push("preview".to_string());
            Ok(self.previews.pop_front().expect("unexpected preview call"))
        }

        fn check_plan(&mut self, label: &str, plan_json: &str) -> i32 {
            self.events.push("check_plan".to_string());
            refuse_destructive_plan::check_and_report(label, plan_json)
        }

        fn up(&mut self) -> Result<(i32, Vec<u8>), i32> {
            self.events.push("up".to_string());
            Ok(self.ups.pop_front().expect("unexpected up call"))
        }

        fn sleep(&mut self, seconds: u64) {
            self.events.push(format!("sleep:{seconds}"));
            self.sleeps.push(seconds);
        }
    }

    fn policy(max: i64) -> RetryPolicy {
        RetryPolicy {
            max,
            initial_delay: 15,
            cap: 60,
        }
    }

    #[test]
    fn up_409_retries_fresh_preview_and_guard_before_second_up() {
        let mut runner = MockRunner::new(
            vec![
                CommandCapture {
                    code: 0,
                    stdout: SAFE_JSON.as_bytes().to_vec(),
                    stderr: Vec::new(),
                },
                CommandCapture {
                    code: 0,
                    stdout: SAFE_JSON.as_bytes().to_vec(),
                    stderr: Vec::new(),
                },
            ],
            vec![(23, CONFLICT.to_vec()), (0, Vec::new())],
        );
        let rc = run_with_runner("sentry production", policy(4), &mut runner);
        assert_eq!(rc, 0);
        assert_eq!(
            runner.events,
            vec![
                "preview",
                "check_plan",
                "up",
                "sleep:15",
                "preview",
                "check_plan",
                "up"
            ]
        );
        assert_eq!(runner.sleeps, vec![15]);
    }

    #[test]
    fn up_409_followed_by_destructive_preview_refuses_second_up() {
        let mut runner = MockRunner::new(
            vec![
                CommandCapture {
                    code: 0,
                    stdout: SAFE_JSON.as_bytes().to_vec(),
                    stderr: Vec::new(),
                },
                CommandCapture {
                    code: 0,
                    stdout: DESTRUCTIVE_JSON.as_bytes().to_vec(),
                    stderr: Vec::new(),
                },
            ],
            vec![(23, CONFLICT.to_vec())],
        );
        let rc = run_with_runner("sentry production", policy(4), &mut runner);
        assert_eq!(rc, 1);
        assert_eq!(
            runner.events,
            vec![
                "preview",
                "check_plan",
                "up",
                "sleep:15",
                "preview",
                "check_plan"
            ]
        );
    }

    #[test]
    fn preview_409_retries_whole_unit() {
        let mut runner = MockRunner::new(
            vec![
                CommandCapture {
                    code: 23,
                    stdout: Vec::new(),
                    stderr: CONFLICT.to_vec(),
                },
                CommandCapture {
                    code: 0,
                    stdout: SAFE_JSON.as_bytes().to_vec(),
                    stderr: Vec::new(),
                },
            ],
            vec![(0, Vec::new())],
        );
        let rc = run_with_runner("sentry production", policy(4), &mut runner);
        assert_eq!(rc, 0);
        assert_eq!(
            runner.events,
            vec!["preview", "sleep:15", "preview", "check_plan", "up"]
        );
    }

    #[test]
    fn non_409_up_error_and_first_guard_failure_do_not_retry() {
        let mut guard_fail = MockRunner::new(
            vec![CommandCapture {
                code: 0,
                stdout: DESTRUCTIVE_JSON.as_bytes().to_vec(),
                stderr: Vec::new(),
            }],
            vec![],
        );
        assert_eq!(
            run_with_runner("sentry production", policy(4), &mut guard_fail),
            1
        );
        assert_eq!(guard_fail.events, vec!["preview", "check_plan"]);

        let mut up_fail = MockRunner::new(
            vec![CommandCapture {
                code: 0,
                stdout: SAFE_JSON.as_bytes().to_vec(),
                stderr: Vec::new(),
            }],
            vec![(17, b"error: provider failure".to_vec())],
        );
        assert_eq!(
            run_with_runner("sentry production", policy(4), &mut up_fail),
            17
        );
        assert_eq!(up_fail.events, vec!["preview", "check_plan", "up"]);
    }
}
