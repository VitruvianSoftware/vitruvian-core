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
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! The "ask first" dialog, shown on this Mac with `osascript`.

use std::io::Read;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::time::{Duration, Instant};

use serde_json::Value;

pub const OSASCRIPT: &str = "/usr/bin/osascript";
pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(60);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Answer {
    Allow,
    Deny,
}

/// How long past the dialog's own time limit we wait for osascript to exit
/// before killing it.
const GRACE: Duration = Duration::from_millis(500);
/// After the dialog process is gone, how long to wait for its last output.
const OUTPUT_WAIT: Duration = Duration::from_millis(500);

/// A dialog that is showing (or failed to start, which answers `Deny`).
pub struct PromptHandle {
    child: Option<Child>,
    output: Option<Receiver<String>>,
    deadline: Instant,
}

/// Kills the dialog's whole process group (it was started as its own group
/// leader), so a child that inherited the output pipe dies with it.
fn kill_group(child: &Child) {
    let pgid = child.id() as i32;
    if pgid > 1 {
        // SAFETY: plain syscall on a group we created; no memory is touched.
        unsafe {
            libc::kill(-pgid, libc::SIGKILL);
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum LeaderState {
    Running,
    Exited,
    /// The check itself failed; treated like a timeout (kill, Deny).
    Error,
}

/// Has the dialog process exited? Uses `waitid(WNOWAIT)`, which reports the
/// exit but leaves the zombie in place (`try_wait` would reap it).
fn leader_state(child: &Child) -> LeaderState {
    // SAFETY: `info` is plain zeroed memory that waitid fills in.
    let (ret, pid) = unsafe {
        let mut info: libc::siginfo_t = std::mem::zeroed();
        let ret = libc::waitid(
            libc::P_PID,
            child.id() as libc::id_t,
            &mut info,
            libc::WEXITED | libc::WNOHANG | libc::WNOWAIT,
        );
        #[cfg(target_os = "macos")]
        let pid = info.si_pid;
        #[cfg(not(target_os = "macos"))]
        let pid = info.si_pid();
        (ret, pid)
    };
    match (ret, pid) {
        (0, 0) => LeaderState::Running,
        (0, _) => LeaderState::Exited,
        _ => LeaderState::Error,
    }
}

impl PromptHandle {
    /// Waits for the person's answer, for at most the timeout plus a short
    /// grace, however the dialog process behaves. Only a clean exit whose
    /// output is exactly `button returned:Allow, gave up:false` is `Allow`;
    /// timeout, failure or anything else is `Deny`.
    pub fn wait(mut self) -> Answer {
        let Some(mut child) = self.child.take() else {
            return Answer::Deny;
        };
        // Watch for the leader's exit without reaping it, so its process
        // group id cannot be reused before the group is killed.
        let mut ok = false;
        loop {
            match leader_state(&child) {
                LeaderState::Exited => {
                    ok = true;
                    break;
                }
                LeaderState::Running if Instant::now() < self.deadline => {
                    std::thread::sleep(Duration::from_millis(20))
                }
                _ => break,
            }
        }
        // Whatever the outcome, nothing the dialog started stays alive.
        kill_group(&child);
        let success = child.wait().map(|s| s.success()).unwrap_or(false) && ok;
        if !success {
            return Answer::Deny;
        }
        let out = self
            .output
            .take()
            .and_then(|rx| rx.recv_timeout(OUTPUT_WAIT).ok())
            .unwrap_or_default();
        if is_allow(&out) {
            Answer::Allow
        } else {
            Answer::Deny
        }
    }

    /// Closes the dialog without an answer (the call was cancelled or timed out
    /// elsewhere).
    pub fn dismiss(mut self) {
        if let Some(mut child) = self.child.take() {
            kill_group(&child);
            let _ = child.wait();
        }
    }
}

/// `osascript` prints exactly this when the person clicks Allow.
fn is_allow(out: &str) -> bool {
    out.trim() == "button returned:Allow, gave up:false"
}

pub fn ask(_tool: &str, summary: &str, timeout: Duration) -> PromptHandle {
    ask_with(Path::new(OSASCRIPT), summary, timeout)
}

/// Spawn attempts. Tests write a fake script and run it from parallel
/// threads, which can briefly fail with "text file busy"; production runs a
/// binary that is not being written, so one attempt.
#[cfg(test)]
const SPAWN_TRIES: u32 = 20;
#[cfg(not(test))]
const SPAWN_TRIES: u32 = 1;

/// Like [`ask`] with the `osascript` path given (tests use a fake). The script
/// is fixed; `summary` and the seconds travel as arguments, so nothing in the
/// summary can be read as script. The dialog runs in its own process group.
pub fn ask_with(osascript: &Path, summary: &str, timeout: Duration) -> PromptHandle {
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
        .process_group(0)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    let deadline = Instant::now() + Duration::from_secs(secs) + GRACE;
    let mut spawned = None;
    for _ in 0..SPAWN_TRIES {
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
    let (tx, rx) = mpsc::channel();
    // Detached: if a straggler holds the pipe open this thread ends when the
    // group is killed; nobody waits for it past the deadline.
    std::thread::spawn(move || {
        let mut s = String::new();
        if let Some(o) = stdout.as_mut() {
            let _ = o.read_to_string(&mut s);
        }
        let _ = tx.send(s);
    });
    PromptHandle {
        child: Some(child),
        output: Some(rx),
        deadline,
    }
}

const MAX_FIELD: usize = 200;
/// Shown where the text has a line break.
const LINE_BREAK: char = '⏎';

/// Characters that show nothing or change how the text reads: controls
/// (Cc), the line and paragraph separators (Zl, Zp), and the invisible
/// formatting characters (Cf: zero-width, bidi overrides and isolates,
/// BOM, soft hyphen, tag characters).
fn is_hidden_char(c: char) -> bool {
    c.is_control()
        || matches!(c,
            '\u{00AD}' | '\u{034F}' | '\u{0600}'..='\u{0605}' | '\u{061C}' | '\u{06DD}' | '\u{070F}'
            | '\u{0890}'..='\u{0891}' | '\u{08E2}' | '\u{115F}' | '\u{1160}' | '\u{17B4}' | '\u{17B5}' | '\u{180B}'..='\u{180E}' | '\u{2800}' | '\u{3164}' | '\u{FE00}'..='\u{FE0F}' | '\u{FFA0}' | '\u{E0100}'..='\u{E01EF}' | '\u{200B}'..='\u{200F}'
            | '\u{2028}'..='\u{202E}' | '\u{2060}'..='\u{2064}' | '\u{2066}'..='\u{206F}'
            | '\u{FEFF}' | '\u{FFF9}'..='\u{FFFB}' | '\u{110BD}' | '\u{110CD}'
            | '\u{13430}'..='\u{1343F}' | '\u{1BCA0}'..='\u{1BCA3}'
            | '\u{1D173}'..='\u{1D17A}' | '\u{E0001}' | '\u{E0020}'..='\u{E007F}')
}

/// Hidden characters removed, runs of whitespace made one space (so padding
/// cannot push text out of view), then cut to 200 characters. A cut ends with
/// "…" and says how much was dropped, so it never reads as complete.
fn clean(s: &str) -> String {
    let mut out = String::new();
    let mut space = false;
    let mut after_cr = false;
    for c in s.chars() {
        // A line break is a command separator or Enter: show it, never
        // blend it into a space. "\r\n" is one break. Tabs and other
        // whitespace become a single space.
        if matches!(c, '\n' | '\r' | '\u{85}' | '\u{2028}' | '\u{2029}') {
            if c == '\n' && after_cr {
                after_cr = false;
                continue;
            }
            after_cr = c == '\r';
            if !out.is_empty() && !out.ends_with(' ') {
                out.push(' ');
            }
            out.push(LINE_BREAK);
            space = true;
            continue;
        }
        after_cr = false;
        if c.is_whitespace() {
            space = true;
            continue;
        }
        if is_hidden_char(c) {
            continue;
        }
        if space && !out.is_empty() {
            out.push(' ');
        }
        space = false;
        out.push(c);
    }
    let total = out.chars().count();
    if total <= MAX_FIELD {
        return out;
    }
    let mut cut: String = out.chars().take(MAX_FIELD).collect();
    cut.push_str(&format!(
        "… (truncated, {} more characters)",
        total - MAX_FIELD
    ));
    cut
}

/// A key argument as text; `None` when it is absent, empty or not a scalar.
fn field(v: &Value) -> Option<String> {
    let s = match v {
        Value::String(s) => clean(s),
        Value::Number(n) => clean(&n.to_string()),
        Value::Bool(b) => b.to_string(),
        _ => return None,
    };
    (!s.is_empty()).then_some(s)
}

/// What the dialog shows: the tool name and its key arguments, each cleaned
/// and cut to 200 characters (see [`clean`]). If a key argument is missing or
/// is not plain text, the person sees everything that was sent instead, with
/// a note of what was missing, so a renamed argument is never approved
/// blind. Names are checked against the pinned desktop-commander in Task 7.
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
        _ => &[],
    };
    let mut parts = Vec::new();
    let mut missing = None;
    for k in keys {
        match args.get(*k).and_then(field) {
            Some(v) => parts.push(format!("{k}={v}")),
            None => {
                missing = Some(*k);
                break;
            }
        }
    }
    let name = clean(tool);
    if keys.is_empty() || missing.is_some() {
        let json = serde_json::to_string(args).unwrap_or_default();
        return match missing {
            Some(k) => format!("{name} (no {k}): {}", clean(&json)),
            None => format!("{name}: {}", clean(&json)),
        };
    }
    format!("{name}: {}", parts.join(", "))
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

    fn ask_t(script: &Path, summary: &str, timeout: Duration) -> PromptHandle {
        ask_with(script, summary, timeout)
    }

    fn run(script: &Path, summary: &str) -> Answer {
        ask_t(script, summary, Duration::from_secs(7)).wait()
    }

    fn script_in(name: &str, body: &str) -> (PathBuf, PathBuf) {
        let dir = test_dir(name);
        std::fs::create_dir_all(&dir).unwrap();
        let script = dir.join("osascript");
        std::fs::write(&script, format!("#!/bin/sh\n{body}\n")).unwrap();
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
        (script, dir)
    }

    fn pid_gone(pid: i32) -> bool {
        for _ in 0..40 {
            if unsafe { libc::kill(pid, 0) } != 0 {
                return true;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        false
    }

    fn read_pid(dir: &Path) -> i32 {
        for _ in 0..40 {
            if let Ok(t) = std::fs::read_to_string(dir.join("pid")) {
                if let Ok(p) = t.trim().parse() {
                    return p;
                }
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        panic!("no pid file");
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
        ask_t(&s, nasty, Duration::from_secs(60)).wait();
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
    fn dismiss_kills_the_dialog_and_its_child() {
        let (script, dir) = script_in(
            "p-dismiss",
            "sleep 30 &\necho $! > \"$(dirname \"$0\")/pid\"\nsleep 30",
        );
        let h = ask_t(&script, "x", Duration::from_secs(60));
        let pid = read_pid(&dir); // the child has started
        let t = Instant::now();
        h.dismiss();
        assert!(t.elapsed() < Duration::from_secs(1), "{:?}", t.elapsed());
        assert!(pid_gone(pid), "child {pid} outlived dismiss");
    }

    #[test]
    fn deadline_is_a_hard_limit_even_with_a_lingering_child() {
        // The fake neither exits nor gives up, and a child holds stdout.
        let (script, dir) = script_in(
            "p-hard",
            "sleep 30 &\necho $! > \"$(dirname \"$0\")/pid\"\nsleep 30",
        );
        let t = Instant::now();
        let ans = ask_t(&script, "x", Duration::from_secs(1)).wait();
        assert_eq!(ans, Answer::Deny);
        assert!(t.elapsed() < Duration::from_secs(2), "{:?}", t.elapsed());
        assert!(pid_gone(read_pid(&dir)), "child outlived the deadline");
    }

    #[test]
    fn deadline_backstop_denies_a_dialog_that_never_answers() {
        let (script, _) = script_in("p-backstop", "sleep 30");
        let t = Instant::now();
        assert_eq!(
            ask_t(&script, "x", Duration::from_secs(1)).wait(),
            Answer::Deny
        );
        assert!(t.elapsed() < Duration::from_secs(2), "{:?}", t.elapsed());
    }

    #[test]
    fn a_lingering_child_after_a_real_answer_does_not_delay_it() {
        let (script, dir) = script_in(
            "p-linger",
            "sleep 30 &\necho $! > \"$(dirname \"$0\")/pid\"\necho 'button returned:Allow, gave up:false'",
        );
        let t = Instant::now();
        assert_eq!(
            ask_t(&script, "x", Duration::from_secs(60)).wait(),
            Answer::Allow
        );
        assert!(t.elapsed() < Duration::from_secs(2), "{:?}", t.elapsed());
        assert!(pid_gone(read_pid(&dir)));
    }

    #[test]
    fn allow_output_must_match_exactly() {
        for out in [
            "button returned:Deny, gave up:false button returned:Allow, gave up:false",
            "xbutton returned:Allow, gave up:false",
            "button returned:Allow, gave up:false extra",
        ] {
            let (s, _) = fake("p-exact", out, 0);
            assert_eq!(run(&s, "x"), Answer::Deny, "{out}");
        }
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
        // Cutting counts characters, not bytes: no panic on multi-byte text.
        let _ = summarize("start_process", &json!({"command": "é".repeat(300)}));
        // Missing or odd arguments do not panic.
        let _ = summarize("start_process", &json!(null));
        let _ = summarize("kill_process", &json!({"pid": {"x": 1}}));
    }

    #[test]
    fn summary_strips_invisible_and_format_characters() {
        let nasty = "a\u{202A}b\u{202A}c\u{202A}d\u{202D}e\u{202E}f\u{2066}g\u{2067}h\u{2068}i\u{2069}j\u{200B}k\u{200E}l\u{200F}m\u{FEFF}n\u{00AD}o\u{2060}p\u{E0041}q";
        let m = summarize("start_process", &json!({ "command": nasty }));
        assert_eq!(m, "start_process: command=abcdefghijklmnopq");
        let m = summarize("mystery", &json!({ "k": "x\u{202E}y" }));
        assert!(!m.contains('\u{202E}'), "{m:?}");
    }

    #[test]
    fn summary_collapses_whitespace_runs() {
        let m = summarize(
            "start_process",
            &json!({ "command": format!("ls{}; rm -rf ~", " ".repeat(300)) }),
        );
        assert!(m.contains("ls ; rm -rf ~"), "{m}");
    }

    #[test]
    fn truncation_is_marked() {
        let m = summarize(
            "start_process",
            &json!({ "command": format!("echo {}", "a".repeat(300)) }),
        );
        assert!(m.contains('…'), "{m}");
        assert!(m.contains("truncated"), "{m}");
        let m = summarize("mystery", &json!({ "k": "y".repeat(500) }));
        assert!(m.contains('…') && m.contains("truncated"), "{m}");
        // A field that fits is not marked.
        let m = summarize("start_process", &json!({ "command": "ls" }));
        assert!(!m.contains('…') && !m.contains("truncated"), "{m}");
        let m = summarize("start_process", &json!({ "command": "x".repeat(200) }));
        assert!(!m.contains("truncated"), "{m}");
    }

    #[test]
    fn missing_key_argument_shows_what_was_sent() {
        let m = summarize(
            "start_process",
            &json!({ "cmd": "rm -rf ~", "shell": "/bin/zsh" }),
        );
        assert!(m.contains("no command"), "{m}");
        assert!(m.contains("rm -rf ~") && m.contains("/bin/zsh"), "{m}");
        for args in [
            json!({"command": ["a"]}),
            json!({"command": {"x": 1}}),
            json!({"command": ""}),
            json!(null),
        ] {
            let m = summarize("start_process", &args);
            assert!(m.contains("no command"), "{m}");
        }
        // A tool with two keys where one is missing also falls back.
        let m = summarize("move_file", &json!({ "source": "/a" }));
        assert!(m.contains("no destination") && m.contains("/a"), "{m}");
    }

    #[test]
    fn line_breaks_stay_visible() {
        let m = summarize(
            "start_process",
            &json!({"command": "echo backup done\nrm -rf ~/Documents"}),
        );
        assert_eq!(
            m,
            "start_process: command=echo backup done ⏎ rm -rf ~/Documents"
        );
        for (input, want) in [
            ("a\r\nb", "a ⏎ b"),
            ("a\rb", "a ⏎ b"),
            ("a\u{2028}b", "a ⏎ b"),
            ("a\u{2029}b", "a ⏎ b"),
            ("a\u{85}b", "a ⏎ b"),
            ("a\n\nb", "a ⏎ ⏎ b"),
            ("a\n", "a ⏎"),
            ("\nb", "⏎ b"),
            ("a\tb", "a b"),
            ("a \n  b", "a ⏎ b"),
        ] {
            let m = summarize("start_process", &json!({ "command": input }));
            assert_eq!(m, format!("start_process: command={want}"), "{input:?}");
        }
        // Interactive input: a newline is Enter.
        let m = summarize(
            "interact_with_process",
            &json!({"pid": 3, "input": "y\nrm x"}),
        );
        assert!(m.contains("y ⏎ rm x"), "{m}");
    }

    #[test]
    fn line_break_marker_counts_as_one_character_in_the_cut() {
        let long = format!("{}\nrm -rf ~", "a".repeat(190));
        let m = summarize("start_process", &json!({ "command": long }));
        // 190 a's + " ⏎ " + 6 more characters = 200, then the cut.
        assert!(m.contains('⏎'), "{m}");
        assert!(m.contains("truncated"), "{m}");
        let m = summarize(
            "start_process",
            &json!({ "command": format!("{}\nrm", "a".repeat(195)) }),
        );
        assert!(m.contains("a ⏎") || m.contains("a ⏎ "), "{m}");
        let field: String = m
            .trim_start_matches("start_process: command=")
            .chars()
            .take_while(|c| *c != '…')
            .collect();
        assert!(field.chars().count() <= 200, "{}", field.chars().count());
    }

    #[test]
    fn summary_strips_blank_look_alikes() {
        let nasty = "a\u{115F}b\u{1160}c\u{3164}d\u{FFA0}e\u{2800}f\u{034F}g\u{FE00}h\u{FE0F}i\u{E0100}j\u{E01EF}k";
        let m = summarize("start_process", &json!({ "command": nasty }));
        assert_eq!(m, "start_process: command=abcdefghijk");
    }

    #[test]
    fn exit_is_observed_without_reaping() {
        let mut child = Command::new("/bin/sh")
            .args(["-c", "exit 0"])
            .spawn()
            .unwrap();
        let t = Instant::now();
        while leader_state(&child) == LeaderState::Running {
            assert!(t.elapsed() < Duration::from_secs(5));
            std::thread::sleep(Duration::from_millis(10));
        }
        // Still a zombie: the id cannot be reused yet, and asking again says the same.
        assert_eq!(leader_state(&child), LeaderState::Exited);
        assert_eq!(leader_state(&child), LeaderState::Exited);
        assert!(child.wait().unwrap().success());
    }
}
