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

//! PerformanceTest: the whole hook, end to end, must answer well inside its
//! 10 s timeout. The command-tool entry fails closed, so a slow answer is a
//! refusal. Each case runs hook::main on a full payload: parse, decide,
//! redact and log. The same sizes and the same 1 s bound as the Python test.
//! These hold the process lock exclusively (they set AGENT_GUARD_HOME), so
//! they are timed with nothing else running in the process.

use std::time::Instant;

use agent_guard::hook::{log_path, main};
use agent_guard::pyval::PyVal;

use crate::common::*;

const LIMIT: f64 = 1.0;

struct Perf {
    fx: Fixture,
    _env: EnvGuard,
    _lock: std::sync::RwLockWriteGuard<'static, ()>,
}

impl Perf {
    fn new() -> Self {
        let lock = exclusive();
        let fx = Fixture::new();
        let mut env = EnvGuard::new();
        env.set("AGENT_GUARD_HOME", &fx.home);
        Perf {
            fx,
            _env: env,
            _lock: lock,
        }
    }

    /// The decision the hook printed ("allow" if it printed nothing; None
    /// if it printed an answer without a permission decision, as warn does).
    fn timed(&self, name: &str, command: &str, cwd: Option<&str>) -> Option<String> {
        let payload = to_json(&bash(cwd.unwrap_or(&self.fx.repo), command));
        let start = Instant::now();
        let out = main(&[], payload.as_bytes());
        let took = start.elapsed().as_secs_f64();
        eprintln!(
            "perf: {:<34} {:8.3} s ({} bytes)",
            name,
            took,
            command.len()
        );
        assert!(took < LIMIT, "{}: {:.3} s", name, took);
        assert_eq!(out.code, 0, "{}: {}", name, out.stderr);
        let t = out.stdout.trim();
        if t.is_empty() {
            return Some("allow".into());
        }
        let v = from_json(t);
        match at(&v, "hookSpecificOutput").get("permissionDecision") {
            Some(PyVal::Str(d)) => Some(d.clone()),
            _ => None,
        }
    }
}

fn allow() -> Option<String> {
    Some("allow".into())
}

fn deny() -> Option<String> {
    Some("deny".into())
}

#[test]
fn single_word_100kb() {
    let p = Perf::new();
    let cmd = format!("echo {}", "QUJD".repeat(25000));
    assert_eq!(p.timed("100 KB single word", &cmd, None), allow());
}

#[test]
fn word_shaped_like_a_secret_name_100kb() {
    // The pattern that backtracked: NAME_TOKEN followed by a long word.
    let p = Perf::new();
    let cmd = format!("echo X_TOKEN{}=v", "a".repeat(100000));
    assert_eq!(p.timed("100 KB X_TOKEN word", &cmd, None), allow());
}

#[test]
fn command_1mb() {
    let p = Perf::new();
    let cmd = format!("echo {}", "QUJD".repeat(262144));
    assert_eq!(p.timed("1 MB single word", &cmd, None), allow());
    let blob = to_json(&PyVal::Dict(
        (0..30000)
            .map(|i| (format!("k{}", i), s(&"v".repeat(20))))
            .collect(),
    ));
    assert_eq!(
        p.timed("1 MB JSON line", &format!("echo '{}' | jq .", blob), None),
        allow()
    );
    let cmd = format!("echo {}&& git push", "word ".repeat(200000));
    assert_eq!(p.timed("1 MB of words then git push", &cmd, None), deny());
}

#[test]
fn heredoc_5mb() {
    let p = Perf::new();
    let body = "a line with token=abc, it's `git push` and $(go test)\n".repeat(95000);
    assert_eq!(
        p.timed(
            "5 MB quoted heredoc",
            &format!("cat <<'EOF' > f\n{}EOF", body),
            None
        ),
        allow()
    );
    assert_eq!(
        p.timed(
            "5 MB heredoc in $(cat)",
            &format!(
                "gh issue comment 1 --body \"$(cat <<'EOF'\n{}EOF\n)\"",
                body
            ),
            None
        ),
        allow()
    );
    let unquoted = format!(
        "cat <<EOF > f\n{}EOF",
        "line $x `date` it's\n".repeat(300000)
    );
    assert_eq!(p.timed("5 MB unquoted heredoc", &unquoted, None), allow());
}

#[test]
fn too_many_commands_is_refused_quickly() {
    let p = Perf::new();
    let cmd = "a;".repeat(500000);
    assert_eq!(p.timed("500k commands", &cmd, None), deny());
    let out = p.fx.out.clone();
    assert_eq!(p.timed("500k commands, outside", &cmd, Some(&out)), allow());
}

#[test]
fn adversarial_shapes() {
    let p = Perf::new();
    for (name, cmd) in [
        ("1M open parens", "(".repeat(1000000)),
        ("300k $( unbalanced", "$(".repeat(300000)),
        ("1M backslashes", "\\".repeat(1000000)),
        ("1M double quotes", "\"".repeat(1000000)),
        ("500k && ", "&&".repeat(500000)),
    ] {
        p.timed(name, &cmd, None);
    }
}

#[test]
fn log_line_is_bounded_and_redacted() {
    let p = Perf::new();
    let secret = format!("ghp_{}", "A".repeat(36));
    let cmd = format!("GH_TOKEN={} echo {}", secret, "x".repeat(1000000));
    p.timed("secret then 1 MB", &cmd, None);
    let log = read(&log_path(&p.fx.home));
    let rec = from_json(log.lines().last().expect("a log line"));
    let command = st(&rec, "command");
    assert!(!command.contains(&secret), "{}", command);
    assert!(command.contains("[truncated, "), "{}", command);
    assert!(
        command.chars().count() < 1100,
        "{} chars",
        command.chars().count()
    );
}
