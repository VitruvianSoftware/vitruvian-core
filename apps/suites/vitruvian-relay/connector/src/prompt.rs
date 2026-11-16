// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,

//! The "ask first" dialog, shown on this Mac with `osascript`.

use std::io::Read;
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use serde_json::Value;

pub const OSASCRIPT: &str = "/usr/bin/osascript";
pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(60);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Answer {
    Allow,
    Deny,
}

/// A dialog that is showing (or failed to start, which answers `Deny`).
pub struct PromptHandle {
    child: Option<Child>,
    output: Option<JoinHandle<String>>,
    /// Backstop in case osascript never gives up on its own.
    deadline: Instant,
}

impl PromptHandle {
    /// Waits for the person's answer. Only a clean exit whose output says
    /// "Allow" and "gave up:false" is `Allow`; timeout, failure or anything
    /// else is `Deny`.
    pub fn wait(mut self) -> Answer {
        let Some(mut child) = self.child.take() else {
            return Answer::Deny;
        };
        let status = loop {
            match child.try_wait() {
                Ok(Some(s)) => break Some(s),
                Ok(None) if Instant::now() < self.deadline => {
                    std::thread::sleep(Duration::from_millis(25))
                }
                _ => {
                    let _ = child.kill();
                    let _ = child.wait();
                    break None;
                }
            }
        };
        let out = self
            .output
            .take()
            .and_then(|h| h.join().ok())
            .unwrap_or_default();
        match status {
            Some(s) if s.success() && is_allow(&out) => Answer::Allow,
            _ => Answer::Deny,
        }
    }

    /// Closes the dialog without an answer (the call was cancelled or timed out
    /// elsewhere).
    pub fn dismiss(mut self) {
        if let Some(mut child) = self.child.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
        if let Some(h) = self.output.take() {
            let _ = h.join();
        }
    }
}

/// `osascript` prints e.g. `button returned:Allow, gave up:false`.
fn is_allow(out: &str) -> bool {
    let out = out.trim();
    out.contains("button returned:Allow,") && out.ends_with("gave up:false")
}

pub fn ask(tool: &str, summary: &str, timeout: Duration) -> PromptHandle {
    ask_with(Path::new(OSASCRIPT), tool, summary, timeout)
}

/// Like [`ask`] with the `osascript` path given (tests use a fake). The script
/// is fixed; `summary` and the seconds travel as arguments, so nothing in the
/// summary can be read as script. `tool` is already part of `summary`
/// (see [`summarize`]) and is not used separately.
pub fn ask_with(osascript: &Path, _tool: &str, summary: &str, timeout: Duration) -> PromptHandle {
    let secs = timeout.as_secs().max(1);
    let mut cmd = Command::new(osascript);
    cmd.args(["-e", "on run argv", "-e"])
        .arg(
            "display dialog (item 1 of argv) buttons {\"Deny\",\"Allow\"} \
             default button \"Deny\" giving up after (item 2 of argv as integer)",
        )
        .args(["-e", "end run", "--"])
        .arg(summary)
        .arg(secs.to_string())
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    let deadline = Instant::now() + Duration::from_secs(secs) + Duration::from_secs(5);
    let mut spawned = None;
    // A just-written script can briefly be "text file busy" while another
    // thread forks; retry that, and treat any other failure as no answer.
    for _ in 0..20 {
        match cmd.spawn() {
            Ok(c) => {
                spawned = Some(c);
                break;
            }
            Err(e) if e.raw_os_error() == Some(26) => std::thread::sleep(Duration::from_millis(20)),
            Err(_) => break,
        }
    }
    let Some(mut child) = spawned else {
        return PromptHandle {
            child: None,
            output: None,
            deadline,
        };
    };
    let mut stdout = child.stdout.take();
    let output = std::thread::spawn(move || {
        let mut s = String::new();
        if let Some(o) = stdout.as_mut() {
            let _ = o.read_to_string(&mut s);
        }
        s
    });
    PromptHandle {
        child: Some(child),
        output: Some(output),
        deadline,
    }
}

const MAX_FIELD: usize = 200;

fn clean(s: &str) -> String {
    s.chars()
        .filter(|c| !c.is_control())
        .take(MAX_FIELD)
        .collect()
}

fn field(v: &Value) -> String {
    match v {
        Value::String(s) => clean(s),
        Value::Number(n) => clean(&n.to_string()),
        Value::Bool(b) => b.to_string(),
        _ => String::new(),
    }
}

/// What the dialog shows: the tool name and its key arguments, each cut to
/// 200 characters with control characters removed. Names are checked against
/// the pinned desktop-commander in Task 7.
pub fn summarize(tool: &str, args: &Value) -> String {
    let keys: &[&str] = match tool {
        "start_process" => &["command"],
        "interact_with_process" => &["pid", "input"],
        "write_file" => &["path"],
        "edit_block" => &["file_path"],
        "move_file" => &["source", "destination"],
        "create_directory" => &["path"],
        "kill_process" | "force_terminate" => &["pid"],
        "write_pdf" => &["outputPath"],
        _ => {
            let json = serde_json::to_string(args).unwrap_or_default();
            return format!("{}: {}", clean(tool), clean(&json));
        }
    };
    let parts: Vec<String> = keys
        .iter()
        .filter_map(|k| {
            let v = field(args.get(*k).unwrap_or(&Value::Null));
            (!v.is_empty()).then(|| format!("{k}={v}"))
        })
        .collect();
    if parts.is_empty() {
        clean(tool)
    } else {
        format!("{}: {}", clean(tool), parts.join(", "))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::test_dir;
    use serde_json::json;
    use std::os::unix::fs::PermissionsExt;
    use std::path::PathBuf;

    /// A fake osascript: records argv (NUL-separated) to `argv.out`, prints
    /// `stdout`, exits with `code`.
    fn fake(name: &str, stdout: &str, code: i32) -> (PathBuf, PathBuf) {
        let dir = test_dir(name);
        std::fs::create_dir_all(&dir).unwrap();
        let out = dir.join("argv.out");
        let script = dir.join("osascript");
        std::fs::write(
            &script,
            format!(
                "#!/bin/sh\nprintf '%s\\0' \"$@\" > '{}'\necho '{}'\nexit {}\n",
                out.display(),
                stdout,
                code
            ),
        )
        .unwrap();
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
        (script, out)
    }

    fn argv(out: &Path) -> Vec<String> {
        let raw = std::fs::read(out).unwrap();
        let mut parts: Vec<String> = raw
            .split(|b| *b == 0)
            .map(|p| String::from_utf8(p.to_vec()).unwrap())
            .collect();
        parts.pop(); // trailing empty after the last NUL
        parts
    }

    fn run(script: &Path, summary: &str) -> Answer {
        ask_with(script, "start_process", summary, Duration::from_secs(7)).wait()
    }

    #[test]
    fn allow_only_on_an_explicit_allow() {
        let (s, _) = fake("p-allow", "button returned:Allow, gave up:false", 0);
        assert_eq!(run(&s, "x"), Answer::Allow);
        let (s, _) = fake("p-deny", "button returned:Deny, gave up:false", 0);
        assert_eq!(run(&s, "x"), Answer::Deny);
        let (s, _) = fake("p-empty", "", 0);
        assert_eq!(run(&s, "x"), Answer::Deny);
        let (s, _) = fake("p-junk", "button returned:Allowed, gave up:false", 0);
        assert_eq!(run(&s, "x"), Answer::Deny);
    }

    #[test]
    fn prompt_timeout_denies() {
        // Even if the button text says Allow, giving up means Deny.
        let (s, _) = fake("p-timeout", "button returned:Allow, gave up:true", 0);
        assert_eq!(run(&s, "x"), Answer::Deny);
        let (s, _) = fake("p-timeout2", "button returned:, gave up:true", 0);
        assert_eq!(run(&s, "x"), Answer::Deny);
    }

    #[test]
    fn prompt_failure_denies() {
        let (s, _) = fake("p-fail", "button returned:Allow, gave up:false", 1);
        assert_eq!(run(&s, "x"), Answer::Deny);
        // Cannot even start the program.
        assert_eq!(run(Path::new("/nonexistent/osascript"), "x"), Answer::Deny);
    }

    #[test]
    fn prompt_passes_summary_as_argument() {
        let (s, out) = fake("p-argv", "button returned:Allow, gave up:false", 0);
        let nasty = "rm \"a\" \\ b\nline2 ' $(x) `y`";
        ask_with(&s, "start_process", nasty, Duration::from_secs(60)).wait();
        let a = argv(&out);
        assert_eq!(
            a[..6],
            [
                "-e",
                "on run argv",
                "-e",
                "display dialog (item 1 of argv) buttons {\"Deny\",\"Allow\"} default button \"Deny\" giving up after (item 2 of argv as integer)",
                "-e",
                "end run"
            ]
        );
        assert_eq!(a[6], "--");
        assert_eq!(a[7], nasty);
        assert_eq!(a[8], "60");
        assert_eq!(a.len(), 9);
        // The script text (the -e arguments) never contains the summary.
        for i in [1, 3, 5] {
            assert!(!a[i].contains("rm") && !a[i].contains("line2"), "{}", a[i]);
        }
    }

    #[test]
    fn dismiss_kills_a_pending_dialog() {
        let dir = test_dir("p-dismiss");
        std::fs::create_dir_all(&dir).unwrap();
        let script = dir.join("osascript");
        std::fs::write(&script, "#!/bin/sh\nsleep 30\n").unwrap();
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
        let t = std::time::Instant::now();
        let h = ask_with(&script, "start_process", "x", Duration::from_secs(60));
        h.dismiss();
        assert!(t.elapsed() < Duration::from_secs(10));
    }

    #[test]
    fn summary_shows_key_arguments() {
        let s = |t: &str, a: Value| summarize(t, &a);
        assert!(s(
            "start_process",
            json!({"command": "ls -la", "timeout_ms": 5})
        )
        .contains("ls -la"));
        assert!(!s(
            "start_process",
            json!({"command": "ls", "timeout_ms": 5999})
        )
        .contains("5999"));
        let i = s(
            "interact_with_process",
            json!({"pid": 42, "input": "echo hi"}),
        );
        assert!(i.contains("42") && i.contains("echo hi"), "{i}");
        assert!(s(
            "write_file",
            json!({"path": "/tmp/a", "content": "SECRETBODY"})
        )
        .contains("/tmp/a"));
        assert!(!s(
            "write_file",
            json!({"path": "/tmp/a", "content": "SECRETBODY"})
        )
        .contains("SECRETBODY"));
        assert!(s(
            "edit_block",
            json!({"file_path": "/tmp/b", "old_string": "o"})
        )
        .contains("/tmp/b"));
        let m = s("move_file", json!({"source": "/a", "destination": "/b"}));
        assert!(m.contains("/a") && m.contains("/b"), "{m}");
        assert!(s("create_directory", json!({"path": "/tmp/d"})).contains("/tmp/d"));
        assert!(s("kill_process", json!({"pid": 7})).contains('7'));
        assert!(s("force_terminate", json!({"pid": 8})).contains('8'));
        assert!(s(
            "write_pdf",
            json!({"outputPath": "/tmp/o.pdf", "content": "z"})
        )
        .contains("/tmp/o.pdf"));
        // Any other tool: compact JSON of the arguments.
        let o = s("mystery", json!({"a": 1, "b": "two"}));
        assert!(o.starts_with("mystery"), "{o}");
        assert!(o.contains(r#"{"a":1,"b":"two"}"#), "{o}");
    }

    #[test]
    fn summary_is_cut_and_cleaned() {
        let long = "x".repeat(500);
        let m = summarize("start_process", &json!({ "command": long }));
        assert!(m.chars().filter(|c| *c == 'x').count() == 200, "{m}");
        let m = summarize(
            "start_process",
            &json!({"command": "a\nb\tc\u{1b}[31md\u{0}e"}),
        );
        assert!(!m.chars().any(|c| c.is_control()), "{m:?}");
        let m = summarize("mystery", &json!({"k": "y".repeat(500)}));
        // Name, then at most 200 characters of JSON.
        assert!(
            m.chars().count() <= "mystery".len() + 2 + 200 + 2,
            "{}",
            m.len()
        );
        // Cutting counts characters, not bytes: no panic on multi-byte text.
        let _ = summarize("start_process", &json!({"command": "é".repeat(300)}));
        // Missing or odd arguments do not panic.
        let _ = summarize("start_process", &json!(null));
        let _ = summarize("kill_process", &json!({"pid": {"x": 1}}));
    }
}
