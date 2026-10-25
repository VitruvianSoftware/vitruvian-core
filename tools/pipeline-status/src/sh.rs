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

//! The bits of bash that pipeline-status.sh leans on, done the way bash does
//! them: `$(...)` capture, `command -v`, `${var:0:8}` and its log lines.

use std::ffi::OsStr;
use std::io::{self, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::ExitStatusExt;
use std::path::Path;
use std::process::{Command, ExitStatus, Stdio};

/// What `$(cmd 2>/dev/null)` leaves behind: stdout with NUL bytes dropped and
/// every trailing newline stripped, plus the exit status bash would report.
pub struct Captured {
    /// Raw stdout, for `$(a || b)` where b's output is appended to a's.
    pub raw: Vec<u8>,
    pub out: String,
    pub status: i32,
}

/// Bash's `$?` for a finished child: the exit code, or 128 + the signal.
pub fn status_code(status: ExitStatus) -> i32 {
    match status.code() {
        Some(code) => code,
        None => 128 + status.signal().unwrap_or(0),
    }
}

/// Bash's status when it cannot run a command: 127 not found, 126 otherwise.
pub fn spawn_failure_code(err: &io::Error) -> i32 {
    if err.kind() == io::ErrorKind::NotFound {
        127
    } else {
        126
    }
}

/// Strip what command substitution strips: NULs anywhere, newlines at the end.
pub fn subst_text(raw: &[u8]) -> String {
    let bytes: Vec<u8> = raw.iter().copied().filter(|&b| b != 0).collect();
    let mut text = String::from_utf8_lossy(&bytes).into_owned();
    while text.ends_with('\n') {
        text.pop();
    }
    text
}

/// `$(program args... 2>/dev/null)`.
pub fn capture<S: AsRef<OsStr>>(program: &str, args: &[S]) -> Captured {
    let _ = io::stdout().flush();
    match Command::new(program)
        .args(args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
    {
        Ok(output) => Captured {
            out: subst_text(&output.stdout),
            raw: output.stdout,
            status: status_code(output.status),
        },
        Err(err) => Captured {
            raw: Vec::new(),
            out: String::new(),
            status: spawn_failure_code(&err),
        },
    }
}

/// `$(program args... 2>/dev/null || echo "fallback")`.
pub fn capture_or_echo<S: AsRef<OsStr>>(program: &str, args: &[S], fallback: &str) -> String {
    let got = capture(program, args);
    if got.status == 0 {
        return got.out;
    }
    let mut raw = got.raw;
    raw.extend_from_slice(fallback.as_bytes());
    raw.push(b'\n');
    subst_text(&raw)
}

/// `cd "$dir"` as bash does it, with bash's message when it cannot.
pub fn cd(dir: &str, script: &str, line: u32) -> bool {
    if dir.is_empty() {
        return true;
    }
    match std::env::set_current_dir(dir) {
        Ok(()) => true,
        Err(err) => {
            err_text(&format!(
                "{script}: line {line}: cd: {dir}: {}\n",
                strerror(&err)
            ));
            false
        }
    }
}

/// `program args... 2>/dev/null` with stdout left on the terminal.
pub fn run_quiet<S: AsRef<OsStr>>(program: &str, args: &[S]) -> i32 {
    let _ = io::stdout().flush();
    match Command::new(program)
        .args(args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::null())
        .status()
    {
        Ok(status) => status_code(status),
        Err(err) => spawn_failure_code(&err),
    }
}

/// `command -v name`: is there an executable file called `name` on PATH?
pub fn on_path(name: &str) -> bool {
    let path = std::env::var_os("PATH").unwrap_or_default();
    let path = path.to_string_lossy().into_owned();
    path.split(':').any(|dir| {
        let dir = if dir.is_empty() { "." } else { dir };
        let candidate = Path::new(dir).join(name);
        match std::fs::metadata(&candidate) {
            Ok(meta) => meta.is_file() && meta.permissions().mode() & 0o111 != 0,
            Err(_) => false,
        }
    })
}

/// `${var:0:n}`: the first n characters.
pub fn prefix(text: &str, n: usize) -> String {
    text.chars().take(n).collect()
}

/// `${NAME:-default}`.
pub fn env_or(name: &str, default: &str) -> String {
    match std::env::var(name) {
        Ok(value) if !value.is_empty() => value,
        _ => default.to_string(),
    }
}

/// An OS error the way bash prints it (strerror, without Rust's suffix).
pub fn strerror(err: &io::Error) -> String {
    let text = err.to_string();
    match text.find(" (os error ") {
        Some(at) => text[..at].to_string(),
        None => text,
    }
}

/// The script's four log lines, colour codes and all.
pub fn info(msg: &str) {
    out_line(&format!("\x1b[36m→\x1b[0m {msg}\n"));
}

pub fn ok(msg: &str) {
    out_line(&format!("\x1b[32m✓\x1b[0m {msg}\n"));
}

pub fn warn(msg: &str) {
    out_line(&format!("\x1b[33m⏳\x1b[0m {msg}\n"));
}

pub fn die(msg: &str) {
    err_text(&format!("\x1b[31m✗\x1b[0m {msg}\n"));
}

pub fn out_line(text: &str) {
    let mut out = io::stdout().lock();
    let _ = out.write_all(text.as_bytes());
    let _ = out.flush();
}

pub fn err_text(text: &str) {
    let mut err = io::stderr().lock();
    let _ = err.write_all(text.as_bytes());
    let _ = err.flush();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn substitution_strips_trailing_newlines_and_nuls() {
        assert_eq!(subst_text(b"abc\n\n\n"), "abc");
        assert_eq!(subst_text(b"a\nb\n"), "a\nb");
        assert_eq!(subst_text(b"a\0b\n"), "ab");
        assert_eq!(subst_text(b"\n\n"), "");
    }

    #[test]
    fn prefix_takes_characters() {
        assert_eq!(prefix("0123456789abcdef", 8), "01234567");
        assert_eq!(prefix("abc", 8), "abc");
        assert_eq!(prefix("ééééééééé", 8), "éééééééé");
    }

    #[test]
    fn strerror_drops_rust_suffix() {
        let err = io::Error::from_raw_os_error(2);
        assert_eq!(strerror(&err), "No such file or directory");
    }
}
