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

//! Retries a command ONLY on Pulumi Cloud's account-wide concurrent-update
//! 409; every other failure exits at once with the command's own status.
//!
//! Standard library only and free of `crate::` paths ON PURPOSE: CI jobs
//! without Bazel (.github/actions/pulumi-run-captured, the zitadel-apps
//! applies) build the binary straight from the checkout with
//! `rustc --edition 2021 -O tools/pulumi/src/bin/retry_concurrent_update.rs`,
//! which pulls this file in by `#[path]`. Keep it that way.

use std::io::{Read, Write};
use std::os::unix::process::ExitStatusExt;
use std::process::{ChildStderr, Command, Stdio};

/// Backoff configuration for retrying Pulumi Cloud's concurrent-update 409.
#[derive(Clone, Copy, Debug)]
pub struct RetryPolicy {
    pub max: i64,
    pub initial_delay: u64,
    pub cap: u64,
}

impl RetryPolicy {
    /// Reads retry limits from environment variables.
    /// Signed `max` means a budget below 1 disables retries rather than
    /// falling back to the default.
    pub fn from_env() -> Self {
        Self {
            max: std::env::var("PULUMI_CONFLICT_MAX_ATTEMPTS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(8),
            initial_delay: std::env::var("PULUMI_CONFLICT_RETRY_DELAY")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(15),
            cap: std::env::var("PULUMI_CONFLICT_MAX_DELAY")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(60),
        }
    }
}

/// The shell's `$?`: the exit code, or 128 + the signal that killed it.
pub fn exit_code(status: std::process::ExitStatus) -> i32 {
    if let Some(c) = status.code() {
        c
    } else if let Some(sig) = status.signal() {
        128 + sig
    } else {
        1
    }
}

/// Both markers are required (AND, not OR): `[409]` in the text AND
/// `concurrent update` case-insensitively.
pub fn is_concurrent_conflict(stderr: &[u8]) -> bool {
    let text = String::from_utf8_lossy(stderr);
    if !text.contains("[409]") {
        return false;
    }
    let lower = text.to_ascii_lowercase();
    lower.contains("concurrent update")
}

/// Sleep via external `sleep` so test stubs on PATH can intercept and record
/// delays, falling back to `std::thread::sleep` if `sleep` is unavailable.
pub fn sleep_seconds(wait: u64) {
    if Command::new("sleep")
        .arg(wait.to_string())
        .status()
        .is_err()
    {
        std::thread::sleep(std::time::Duration::from_secs(wait));
    }
}

/// Read all bytes from `stderr_pipe`, mirroring them live to process stderr.
pub fn tee_stderr(stderr_pipe: ChildStderr) -> Vec<u8> {
    std::thread::spawn(move || {
        let mut buf = Vec::new();
        let mut reader = std::io::BufReader::new(stderr_pipe);
        let mut chunk = [0u8; 4096];
        loop {
            match reader.read(&mut chunk) {
                Ok(0) => break,
                Ok(n) => {
                    let _ = std::io::stderr().write_all(&chunk[..n]);
                    buf.extend_from_slice(&chunk[..n]);
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(_) => break,
            }
        }
        buf
    })
    .join()
    .unwrap_or_default()
}

/// Run `cmd_args[0] cmd_args[1..]`, retrying only the Pulumi Cloud
/// account-wide concurrent-update 409. Every other failure exits at once with
/// the command's own status, unchanged.
pub fn retry_command(cmd_args: &[String]) -> i32 {
    let policy = RetryPolicy::from_env();

    let mut attempt: i64 = 1;
    let mut delay = policy.initial_delay;

    loop {
        let mut child = match Command::new(&cmd_args[0])
            .args(&cmd_args[1..])
            .stdout(Stdio::inherit())
            .stderr(Stdio::piped())
            .spawn()
        {
            Ok(c) => c,
            Err(e) => {
                eprintln!("{}: {}", cmd_args[0], e);
                return if e.kind() == std::io::ErrorKind::NotFound {
                    127
                } else {
                    126
                };
            }
        };

        let captured = tee_stderr(child.stderr.take().unwrap());

        let status = match child.wait() {
            Ok(s) => s,
            Err(_) => return 1,
        };
        let rc = exit_code(status);

        if rc == 0 {
            return 0;
        }

        if attempt < policy.max && is_concurrent_conflict(&captured) {
            let wait = delay.min(policy.cap);
            eprintln!(
                "retry-concurrent-update: attempt {}/{} hit Pulumi's account-wide \
                 concurrent-update 409; retrying in {}s",
                attempt, policy.max, wait
            );
            sleep_seconds(wait);
            attempt += 1;
            delay = delay.saturating_mul(2);
            continue;
        }

        if attempt >= policy.max && is_concurrent_conflict(&captured) {
            eprintln!(
                "retry-concurrent-update: still blocked by another update after \
                 {} attempts; giving up.",
                policy.max
            );
        }
        return rc;
    }
}

/// Entry point: `retry-concurrent-update <command> [args...]`.
pub fn run(args: &[String]) -> i32 {
    if args.is_empty() {
        eprintln!("usage: retry-concurrent-update pulumi <subcommand> [args...]");
        return 2;
    }
    retry_command(args)
}
