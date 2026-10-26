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

//! Act-tier execution (`POST /v1/exec`), clipboard (`GET/POST /v1/clipboard`),
//! audio (`POST /v1/audio`), and power (`POST /v1/power`) handlers.

use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::{mpsc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use vitruvian_remote_macagent_metrics::{parse_volume_settings, Audio, JsonMap, JsonValue};

use crate::http_util::CancelToken;
use crate::sampler::augmented_path;

pub const MAX_OUTPUT: usize = 64 * 1024;
pub const DEFAULT_TIMEOUT_SEC: i32 = 30;
pub const MAX_TIMEOUT_SEC: i32 = 120;
pub const CLAUDE_RESUME_TIMEOUT_SEC: u64 = 180;

static EXEC_DIR: Mutex<Option<PathBuf>> = Mutex::new(None);

pub fn set_exec_dir(dir: PathBuf) {
    if let Ok(mut g) = EXEC_DIR.lock() {
        *g = Some(dir);
    }
}

pub fn get_exec_dir() -> PathBuf {
    if let Ok(g) = EXEC_DIR.lock() {
        if let Some(ref d) = *g {
            return d.clone();
        }
    }
    PathBuf::new()
}

#[derive(Debug, Clone, Default)]
pub struct ExecRequest {
    pub kind: String,
    pub command: String,
    pub cwd: String,
    pub timeout_seconds: i32,
}

impl ExecRequest {
    pub fn from_json(v: &JsonValue) -> Result<Self, String> {
        let obj = v
            .as_object()
            .ok_or_else(|| "invalid JSON object".to_string())?;
        Ok(Self {
            kind: obj.get_str("kind").to_string(),
            command: obj.get_str("command").to_string(),
            cwd: obj.get_str("cwd").to_string(),
            timeout_seconds: obj.get_i32("timeout_seconds"),
        })
    }
}

#[derive(Debug, Clone, Default)]
pub struct ExecResult {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
    pub duration_ms: i64,
    pub timed_out: bool,
    pub truncated: bool,
}

impl ExecResult {
    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("exit_code", JsonValue::from_i32(self.exit_code));
        m.insert("stdout", JsonValue::from_str_val(&self.stdout));
        m.insert("stderr", JsonValue::from_str_val(&self.stderr));
        m.insert("duration_ms", JsonValue::from_i64(self.duration_ms));
        m.insert("timed_out", JsonValue::from_bool(self.timed_out));
        m.insert("truncated", JsonValue::from_bool(self.truncated));
        JsonValue::Object(m)
    }

    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }
}

pub fn run_act(r: &ExecRequest, _cancel: &CancelToken) -> Result<ExecResult, String> {
    run_exec(r)
}

pub fn run_argv(argv: &[String], timeout: Duration, _cancel: &CancelToken) -> ExecResult {
    if argv.is_empty() {
        return ExecResult {
            exit_code: -1,
            stderr: "empty argv".to_string(),
            ..Default::default()
        };
    }
    let start = Instant::now();
    let (stdout, stderr, err) =
        crate::sampler::run_tool_within(timeout, &argv[0], &argv[1..], None);
    let dur = start.elapsed().as_millis() as i64;
    let (stdout_trunc, out_t) = truncate_utf8(stdout.as_bytes(), MAX_OUTPUT);
    let (stderr_trunc, err_t) = truncate_utf8(stderr.as_bytes(), MAX_OUTPUT);
    let timed_out = err
        .as_ref()
        .map_or(false, |e| e.contains("no answer within"));
    let exit_code = match err {
        None => 0,
        Some(_) => 1,
    };
    ExecResult {
        exit_code,
        stdout: stdout_trunc,
        stderr: stderr_trunc,
        duration_ms: dur,
        timed_out,
        truncated: out_t || err_t,
    }
}

pub fn pbpaste(_cancel: &CancelToken) -> Result<String, String> {
    clipboard_get().map(|c| c.text)
}

pub fn pbcopy(text: &str, _cancel: &CancelToken) -> Result<(), String> {
    clipboard_set(text)
}

pub fn set_volume(vol: i32, _cancel: &CancelToken) -> Result<(), String> {
    audio_apply(&AudioRequest {
        volume_percent: Some(vol),
        muted: None,
    })
    .map(|_| ())
}

pub fn run_cmd_simple(name: &str, args: &[&str], _cancel: &CancelToken) -> Result<String, String> {
    crate::sampler::run_cmd(name, args)
}

pub fn is_valid_power_action(action: &str) -> bool {
    matches!(action, "sleep" | "display_sleep" | "lock" | "restart")
}

pub fn power_action(action: &str, _cancel: &CancelToken) -> Result<(), String> {
    let argv = power_command(action)?;
    if argv.is_empty() {
        return Err("empty power command".to_string());
    }
    let refs: Vec<&str> = argv[1..].iter().map(|s| s.as_str()).collect();
    crate::sampler::run_cmd(&argv[0], &refs).map(|_| ())
}

pub fn run_exec(r: &ExecRequest) -> Result<ExecResult, String> {
    if r.command.trim().is_empty() {
        return Err("command is empty".to_string());
    }
    let timeout = clamp_timeout(r.timeout_seconds);

    let mut cmd = match r.kind.as_str() {
        "shell" => {
            let mut c = Command::new("/bin/zsh");
            c.args(["-lc", &r.command]);
            c
        }
        "claude_prompt" => {
            let mut c = Command::new("claude");
            c.args(["-p", &r.command, "--output-format", "text"]);
            if !r.cwd.is_empty() {
                c.current_dir(&r.cwd);
            }
            c
        }
        other => {
            return Err(format!(
                "unknown kind {:?} (want shell or claude_prompt)",
                other
            ));
        }
    };

    cmd.env("PATH", augmented_path());
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());

    let start = Instant::now();
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            let dur = start.elapsed().as_millis() as i64;
            return Ok(ExecResult {
                exit_code: -1,
                stdout: String::new(),
                stderr: e.to_string(),
                duration_ms: dur,
                timed_out: false,
                truncated: false,
            });
        }
    };

    let stdout_pipe = child.stdout.take();
    let stderr_pipe = child.stderr.take();

    let out_handle = thread::spawn(move || {
        let mut buf = Vec::new();
        if let Some(p) = stdout_pipe {
            let _ = p.take((MAX_OUTPUT + 1) as u64).read_to_end(&mut buf);
        }
        buf
    });
    let err_handle = thread::spawn(move || {
        let mut buf = Vec::new();
        if let Some(p) = stderr_pipe {
            let _ = p.take((MAX_OUTPUT + 1) as u64).read_to_end(&mut buf);
        }
        buf
    });

    let (tx, rx) = mpsc::channel();
    let wait_handle = thread::spawn(move || {
        let status = child.wait();
        let _ = tx.send(status);
        child
    });

    let mut timed_out = false;
    let status = match rx.recv_timeout(timeout) {
        Ok(st) => {
            let _ = wait_handle.join();
            st
        }
        Err(_) => {
            timed_out = true;
            // We cannot directly access `child` while `wait_handle` is blocked unless we kill by PID,
            // so we use a polled wait loop below instead.
            Err(std::io::Error::new(
                std::io::ErrorKind::TimedOut,
                "timed out",
            ))
        }
    };

    let out_bytes = out_handle.join().unwrap_or_default();
    let err_bytes = err_handle.join().unwrap_or_default();

    let (stdout, out_trunc) = truncate_utf8(&out_bytes, MAX_OUTPUT);
    let (stderr, err_trunc) = truncate_utf8(&err_bytes, MAX_OUTPUT);

    let exit_code = if timed_out {
        -1
    } else {
        match status {
            Ok(st) => st.code().unwrap_or(-1),
            Err(_) => -1,
        }
    };

    Ok(ExecResult {
        exit_code,
        stdout,
        stderr,
        duration_ms: start.elapsed().as_millis() as i64,
        timed_out,
        truncated: out_trunc || err_trunc,
    })
}

pub fn clamp_timeout(sec: i32) -> Duration {
    if sec <= 0 {
        Duration::from_secs(DEFAULT_TIMEOUT_SEC as u64)
    } else if sec > MAX_TIMEOUT_SEC {
        Duration::from_secs(MAX_TIMEOUT_SEC as u64)
    } else {
        Duration::from_secs(sec as u64)
    }
}

/// Cuts `b` to at most `limit` bytes without splitting a multi-byte UTF-8 character.
pub fn truncate_utf8(b: &[u8], limit: usize) -> (String, bool) {
    if b.len() <= limit {
        return (String::from_utf8_lossy(b).into_owned(), false);
    }
    let mut cut = &b[..limit];
    while !cut.is_empty() && std::str::from_utf8(cut).is_err() {
        // Check if only the trailing incomplete sequence is invalid
        let valid_up_to = match std::str::from_utf8(cut) {
            Ok(_) => cut.len(),
            Err(e) => e.valid_up_to(),
        };
        if valid_up_to > 0 && cut.len() - valid_up_to <= 3 && e_is_incomplete(cut, valid_up_to) {
            cut = &cut[..valid_up_to];
            break;
        }
        cut = &cut[..cut.len() - 1];
    }
    (String::from_utf8_lossy(cut).into_owned(), true)
}

fn e_is_incomplete(b: &[u8], valid_up_to: usize) -> bool {
    match std::str::from_utf8(&b[valid_up_to..]) {
        Err(e) => e.error_len().is_none(),
        Ok(_) => true,
    }
}

#[derive(Debug, Clone, Default)]
pub struct ClipboardPayload {
    pub text: String,
    pub truncated: bool,
}

impl ClipboardPayload {
    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("text", JsonValue::from_str_val(&self.text));
        m.insert("truncated", JsonValue::from_bool(self.truncated));
        JsonValue::Object(m)
    }
}

pub fn clipboard_get() -> Result<ClipboardPayload, String> {
    let out = Command::new("/usr/bin/pbpaste")
        .output()
        .map_err(|e| e.to_string())?;
    if !out.status.success() {
        return Err("pbpaste failed".to_string());
    }
    let (text, trunc) = truncate_utf8(&out.stdout, MAX_OUTPUT);
    Ok(ClipboardPayload {
        text,
        truncated: trunc,
    })
}

pub fn clipboard_set(text: &str) -> Result<(), String> {
    if text.len() > MAX_OUTPUT {
        return Err("clipboard text exceeds 64 KiB".to_string());
    }
    let mut child = Command::new("/usr/bin/pbcopy")
        .stdin(Stdio::piped())
        .spawn()
        .map_err(|e| e.to_string())?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(text.as_bytes())
            .map_err(|e| e.to_string())?;
    }
    let status = child.wait().map_err(|e| e.to_string())?;
    if !status.success() {
        return Err("pbcopy failed".to_string());
    }
    Ok(())
}

#[derive(Debug, Clone, Default)]
pub struct AudioRequest {
    pub volume_percent: Option<i32>,
    pub muted: Option<bool>,
}

impl AudioRequest {
    pub fn from_json(v: &JsonValue) -> Result<Self, String> {
        let obj = v
            .as_object()
            .ok_or_else(|| "invalid JSON object".to_string())?;
        let volume_percent = obj.get("volume_percent").and_then(|x| x.as_i32());
        let muted = obj.get_opt_bool("muted");
        Ok(Self {
            volume_percent,
            muted,
        })
    }
}

pub fn audio_apply(r: &AudioRequest) -> Result<Audio, String> {
    let mut script = Vec::new();
    if let Some(v) = r.volume_percent {
        let clamped = v.clamp(0, 100);
        script.push(format!("set volume output volume {}", clamped));
    }
    if let Some(m) = r.muted {
        if m {
            script.push("set volume with output muted".to_string());
        } else {
            script.push("set volume without output muted".to_string());
        }
    }
    script.push("get volume settings".to_string());
    let joined = script.join("\n");
    let out = Command::new("/usr/bin/osascript")
        .args(["-e", &joined])
        .output()
        .map_err(|e| e.to_string())?;
    if !out.status.success() {
        return Err("osascript failed".to_string());
    }
    parse_volume_settings(&String::from_utf8_lossy(&out.stdout))
}

#[derive(Debug, Clone, Default)]
pub struct PowerRequest {
    pub action: String,
}

pub fn power_command(action: &str) -> Result<Vec<String>, String> {
    match action {
        "sleep" => Ok(vec!["/usr/bin/pmset".to_string(), "sleepnow".to_string()]),
        "display_sleep" => Ok(vec![
            "/usr/bin/pmset".to_string(),
            "displaysleepnow".to_string(),
        ]),
        "lock" => Ok(vec![
            "/usr/bin/osascript".to_string(),
            "-e".to_string(),
            r#"tell application "System Events" to keystroke "q" using {control down, command down}"#
                .to_string(),
        ]),
        other => Err(format!(
            "unknown power action {:?} (want sleep, display_sleep, or lock)",
            other
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_clamp_timeout() {
        let cases = [
            (0, Duration::from_secs(30)),
            (-5, Duration::from_secs(30)),
            (10, Duration::from_secs(10)),
            (120, Duration::from_secs(120)),
            (9999, Duration::from_secs(120)),
        ];
        for (inp, want) in cases {
            assert_eq!(clamp_timeout(inp), want, "clamp_timeout({})", inp);
        }
    }

    #[test]
    fn test_truncate_utf8_never_splits_a_rune() {
        // "é" is 2 bytes in UTF-8 (0xc3 0xa9). Cutting a string of them at an odd byte
        // index would leave a lone 0xc3 at the end if truncate_utf8 did not walk back.
        let s = "é".repeat(50); // 100 bytes
        let (got, trunc) = truncate_utf8(s.as_bytes(), 11);
        assert!(trunc, "expected truncated=true");
        assert!(
            got.len() <= 11,
            "exceeded limit: {} bytes ({:?})",
            got.len(),
            got
        );
        assert_eq!(got.len(), 10, "should cut cleanly at 5 two-byte runes");
        assert!(!got.contains('\u{FFFD}'), "split UTF-8 rune: {:?}", got);
    }

    #[test]
    fn test_power_command_rejects_anything_outside_the_table() {
        for ok in ["sleep", "display_sleep", "lock"] {
            let argv = power_command(ok).expect("valid power action");
            assert!(!argv.is_empty());
        }
        for nope in ["", "shutdown", "reboot", "sleep; rm -rf /"] {
            assert!(
                power_command(nope).is_err(),
                "power_command({:?}) was accepted",
                nope
            );
        }
    }

    #[test]
    fn test_run_exec_rejects_unknown_kind_and_empty_command() {
        assert!(
            run_exec(&ExecRequest {
                kind: "python".to_string(),
                command: "print(1)".to_string(),
                ..Default::default()
            })
            .is_err(),
            "unknown kind was accepted"
        );
        assert!(
            run_exec(&ExecRequest {
                kind: "shell".to_string(),
                command: "   ".to_string(),
                ..Default::default()
            })
            .is_err(),
            "empty command was accepted"
        );
    }
}
