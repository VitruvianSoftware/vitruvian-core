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

//! The bash and coreutils behaviour watch-pr.sh relies on, done natively:
//! `$(...)` capture (with and without `2>&1`), `command -v`, `read` with a
//! non-blank IFS, `[ a -gt b ]`, `$(( ))`, `date`, `sleep`, `tail`, and the
//! grep/cut pipelines it uses to pick fields out of text.

use std::ffi::OsStr;
use std::fs::File;
use std::io::{self, Read, Write};
use std::os::raw::{c_char, c_int, c_long};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::io::{FromRawFd, OwnedFd};
use std::os::unix::process::ExitStatusExt;
use std::path::Path;
use std::process::{Command, ExitStatus, Stdio};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub struct Captured {
    pub out: String,
    pub status: i32,
}

pub fn status_code(status: ExitStatus) -> i32 {
    match status.code() {
        Some(code) => code,
        None => 128 + status.signal().unwrap_or(0),
    }
}

pub fn spawn_failure_code(err: &io::Error) -> i32 {
    if err.kind() == io::ErrorKind::NotFound {
        127
    } else {
        126
    }
}

/// What command substitution keeps: NULs dropped, trailing newlines stripped.
pub fn subst_text(raw: &[u8]) -> String {
    let bytes: Vec<u8> = raw.iter().copied().filter(|&b| b != 0).collect();
    let mut text = String::from_utf8_lossy(&bytes).into_owned();
    while text.ends_with('\n') {
        text.pop();
    }
    text
}

fn raw_capture<S: AsRef<OsStr>>(program: &str, args: &[S]) -> (Vec<u8>, i32) {
    let _ = io::stdout().flush();
    match Command::new(program)
        .args(args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
    {
        Ok(output) => (output.stdout, status_code(output.status)),
        Err(err) => (Vec::new(), spawn_failure_code(&err)),
    }
}

/// `$(program args... 2>/dev/null)`.
pub fn capture<S: AsRef<OsStr>>(program: &str, args: &[S]) -> Captured {
    let (raw, status) = raw_capture(program, args);
    Captured {
        out: subst_text(&raw),
        status,
    }
}

/// `$(program args... 2>/dev/null || echo "fallback")`.
pub fn capture_or_echo<S: AsRef<OsStr>>(program: &str, args: &[S], fallback: &str) -> String {
    let (mut raw, status) = raw_capture(program, args);
    if status != 0 {
        raw.extend_from_slice(fallback.as_bytes());
        raw.push(b'\n');
    }
    subst_text(&raw)
}

/// `program args... 2>/dev/null | tail -n <lines>`, written to our stdout.
pub fn run_tail<S: AsRef<OsStr>>(program: &str, args: &[S], lines: usize) {
    let (raw, _) = raw_capture(program, args);
    out_bytes(tail(&raw, lines));
}

/// `tail -n <lines>` of a byte stream (a last line without a newline counts).
pub fn tail(raw: &[u8], lines: usize) -> &[u8] {
    if lines == 0 || raw.is_empty() {
        return &raw[..0];
    }
    let mut seen = 0;
    let mut end = raw.len();
    if raw[end - 1] == b'\n' {
        end -= 1;
    }
    for i in (0..end).rev() {
        if raw[i] == b'\n' {
            seen += 1;
            if seen == lines {
                return &raw[i + 1..];
            }
        }
    }
    raw
}

extern "C" {
    fn pipe(fds: *mut c_int) -> c_int;
    fn fcntl(fd: c_int, cmd: c_int, ...) -> c_int;
}

const F_SETFD: c_int = 2;
const FD_CLOEXEC: c_int = 1;

fn cloexec_pipe() -> io::Result<(OwnedFd, OwnedFd)> {
    let mut fds = [0 as c_int; 2];
    // SAFETY: pipe() fills two descriptors we then own.
    if unsafe { pipe(fds.as_mut_ptr()) } != 0 {
        return Err(io::Error::last_os_error());
    }
    for fd in fds {
        // SAFETY: fd is a descriptor pipe() just returned.
        unsafe { fcntl(fd, F_SETFD, FD_CLOEXEC) };
    }
    // SAFETY: each descriptor is open and owned by nothing else.
    Ok(unsafe { (OwnedFd::from_raw_fd(fds[0]), OwnedFd::from_raw_fd(fds[1])) })
}

/// `$(program args... 2>&1)`: stdout and stderr through one pipe, in order.
pub fn capture_merged<S: AsRef<OsStr>>(program: &str, args: &[S]) -> Captured {
    let _ = io::stdout().flush();
    let (read_end, write_end) = match cloexec_pipe() {
        Ok(p) => p,
        Err(_) => return capture(program, args),
    };
    let write_err = match write_end.try_clone() {
        Ok(fd) => fd,
        Err(_) => return capture(program, args),
    };
    let child = Command::new(program)
        .args(args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::from(write_end))
        .stderr(Stdio::from(write_err))
        .spawn();
    let mut child = match child {
        Ok(child) => child,
        Err(err) => {
            return Captured {
                out: String::new(),
                status: spawn_failure_code(&err),
            }
        }
    };
    let mut raw = Vec::new();
    let _ = File::from(read_end).read_to_end(&mut raw);
    let status = child.wait().map(status_code).unwrap_or(1);
    Captured {
        out: subst_text(&raw),
        status,
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

/// `command -v name`.
pub fn on_path(name: &str) -> bool {
    let path = std::env::var_os("PATH").unwrap_or_default();
    let path = path.to_string_lossy().into_owned();
    path.split(':').any(|dir| {
        let dir = if dir.is_empty() { "." } else { dir };
        match std::fs::metadata(Path::new(dir).join(name)) {
            Ok(meta) => meta.is_file() && meta.permissions().mode() & 0o111 != 0,
            Err(_) => false,
        }
    })
}

/// `[ -f path ]`.
pub fn is_file(path: &str) -> bool {
    std::fs::metadata(path)
        .map(|m| m.is_file())
        .unwrap_or(false)
}

pub fn prefix(text: &str, n: usize) -> String {
    text.chars().take(n).collect()
}

pub fn env_or(name: &str, default: &str) -> String {
    match std::env::var(name) {
        Ok(value) if !value.is_empty() => value,
        _ => default.to_string(),
    }
}

pub fn strerror(err: &io::Error) -> String {
    let text = err.to_string();
    match text.find(" (os error ") {
        Some(at) => text[..at].to_string(),
        None => text,
    }
}

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

// --- time ---------------------------------------------------------------------

#[repr(C)]
struct Tm {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
    tm_gmtoff: c_long,
    tm_zone: *const c_char,
}

extern "C" {
    fn localtime_r(t: *const i64, tm: *mut Tm) -> *mut Tm;
    fn tzset();
}

/// `date +%s`.
pub fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// `date +%H:%M:%S`, in local time as TZ says.
pub fn clock() -> String {
    let t = now();
    let mut tm = Tm {
        tm_sec: 0,
        tm_min: 0,
        tm_hour: 0,
        tm_mday: 0,
        tm_mon: 0,
        tm_year: 0,
        tm_wday: 0,
        tm_yday: 0,
        tm_isdst: 0,
        tm_gmtoff: 0,
        tm_zone: std::ptr::null(),
    };
    // SAFETY: tzset reads TZ; localtime_r fills the struct we pass.
    let filled = unsafe {
        tzset();
        !localtime_r(&t, &mut tm).is_null()
    };
    if !filled {
        let s = t.rem_euclid(86400);
        return format!("{:02}:{:02}:{:02}", s / 3600, s / 60 % 60, s % 60);
    }
    format!("{:02}:{:02}:{:02}", tm.tm_hour, tm.tm_min, tm.tm_sec)
}

/// `sleep "$interval"`: plain decimal seconds natively, anything else by the
/// system's sleep so its own rules (and complaints) apply.
pub fn sleep(interval: &str) {
    let plain = !interval.is_empty()
        && interval != "."
        && interval.chars().all(|c| c.is_ascii_digit() || c == '.')
        && interval.matches('.').count() <= 1;
    if plain {
        if let Ok(secs) = interval.parse::<f64>() {
            if secs.is_finite() && secs >= 0.0 && secs < 1e9 {
                let _ = io::stdout().flush();
                std::thread::sleep(Duration::from_secs_f64(secs));
                return;
            }
        }
    }
    let _ = io::stdout().flush();
    let _ = Command::new("sleep").arg(interval).status();
}

// --- text ---------------------------------------------------------------------

/// `IFS=<delim> read -r v1 ... vn <<< "$line"`: split on the delimiter, the
/// last variable taking the rest; bash drops one trailing delimiter from that
/// rest when what remains holds no other.
pub fn read_fields(line: &str, delim: char, n: usize) -> Vec<String> {
    let line = line.split('\n').next().unwrap_or("");
    let mut out = Vec::with_capacity(n);
    let mut rest = line;
    while out.len() + 1 < n {
        match rest.find(delim) {
            Some(at) => {
                out.push(rest[..at].to_string());
                rest = &rest[at + delim.len_utf8()..];
            }
            None => {
                out.push(rest.to_string());
                rest = "";
                break;
            }
        }
    }
    if out.len() + 1 == n {
        let mut last = rest;
        if let Some(stripped) = last.strip_suffix(delim) {
            if !stripped.contains(delim) {
                last = stripped;
            }
        }
        out.push(last.to_string());
    }
    while out.len() < n {
        out.push(String::new());
    }
    out
}

/// The integer `[ ... -gt ... ]` sees, or None where bash would complain.
pub fn test_int(text: &str) -> Option<i64> {
    let t = text.trim_matches(|c| c == ' ' || c == '\t' || c == '\n');
    let digits = t.strip_prefix(['+', '-']).unwrap_or(t);
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    t.parse::<i64>().ok()
}

/// `[ "$a" <op> "$b" ]` for -gt and -eq, with bash's complaint on stderr when
/// an operand is not an integer (the test is then false).
pub fn test_cmp(a: &str, op: &str, b: &str, script: &str, line: u32) -> bool {
    for side in [a, b] {
        if test_int(side).is_none() {
            err_text(&format!(
                "{script}: line {line}: [: {side}: integer expression expected\n"
            ));
            return false;
        }
    }
    let (x, y) = (test_int(a).unwrap_or(0), test_int(b).unwrap_or(0));
    match op {
        "-gt" => x > y,
        "-eq" => x == y,
        _ => false,
    }
}

/// `echo "$text" | grep -o '"<key>":"[^"]*"' | cut -d'"' -f4`: each value,
/// and whether grep matched anything.
pub fn json_field_values(text: &str, key: &str) -> (Vec<String>, bool) {
    let needle = format!("\"{key}\":\"");
    let mut values = Vec::new();
    for line in text.split('\n') {
        let mut rest = line;
        while let Some(at) = rest.find(&needle) {
            let after = &rest[at + needle.len()..];
            match after.find('"') {
                Some(close) => {
                    values.push(after[..close].to_string());
                    rest = &after[close + 1..];
                }
                None => break,
            }
        }
    }
    let matched = !values.is_empty();
    (values, matched)
}

/// `echo "$link" | grep -o '/runs/[0-9]*' | cut -d'/' -f3`, as `$(...)`.
pub fn run_ids(link: &str) -> String {
    let mut ids = Vec::new();
    for line in link.split('\n') {
        let mut rest = line;
        while let Some(at) = rest.find("/runs/") {
            let after = &rest[at + "/runs/".len()..];
            let digits: String = after.chars().take_while(|c| c.is_ascii_digit()).collect();
            rest = &after[digits.len()..];
            ids.push(digits);
        }
    }
    subst_text(ids.join("\n").as_bytes())
}

// --- output -------------------------------------------------------------------

pub fn info(msg: &str) {
    out_text(&format!("\x1b[36m[{}] →\x1b[0m {msg}\n", clock()));
}

pub fn ok(msg: &str) {
    out_text(&format!("\x1b[32m[{}] ✓\x1b[0m {msg}\n", clock()));
}

pub fn warn(msg: &str) {
    out_text(&format!("\x1b[33m[{}] ⏳\x1b[0m {msg}\n", clock()));
}

pub fn die(msg: &str) {
    err_text(&format!("\x1b[31m[{}] ✗\x1b[0m {msg}\n", clock()));
}

pub fn out_text(text: &str) {
    out_bytes(text.as_bytes());
}

pub fn out_bytes(bytes: &[u8]) {
    let mut out = io::stdout().lock();
    let _ = out.write_all(bytes);
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
    fn read_matches_bash() {
        assert_eq!(read_fields("1:2:3:4:5:", ':', 4), ["1", "2", "3", "4:5:"]);
        assert_eq!(read_fields("1:2:", ':', 4), ["1", "2", "", ""]);
        assert_eq!(
            read_fields(" 1 : 2:3:4: ", ':', 4),
            [" 1 ", " 2", "3", "4: "]
        );
        assert_eq!(read_fields("x|y|z|", '|', 3), ["x", "y", "z"]);
        assert_eq!(read_fields("x|y|z||", '|', 3), ["x", "y", "z||"]);
        assert_eq!(read_fields("", ':', 4), ["", "", "", ""]);
        assert_eq!(read_fields("2:0:0:0", ':', 4), ["2", "0", "0", "0"]);
    }

    #[test]
    fn test_integers() {
        assert_eq!(test_int(" 5 "), Some(5));
        assert_eq!(test_int("+5"), Some(5));
        assert_eq!(test_int("05"), Some(5));
        assert_eq!(test_int("0x5"), None);
        assert_eq!(test_int(""), None);
        assert_eq!(test_int("99999999999999999999"), None);
    }

    #[test]
    fn json_fields_like_grep_and_cut() {
        let (v, m) = json_field_values(r#"{"state":"MERGED","mergeStateStatus":"CLEAN"}"#, "state");
        assert_eq!((v, m), (vec!["MERGED".to_string()], true));
        let (v, m) = json_field_values(r#"{"mergeStateStatus":""}"#, "mergeStateStatus");
        assert_eq!((v, m), (vec![String::new()], true));
        assert_eq!(json_field_values("{}", "state"), (vec![], false));
    }

    #[test]
    fn run_ids_like_grep_and_cut() {
        assert_eq!(
            run_ids("https://github.com/o/r/actions/runs/123/job/4"),
            "123"
        );
        assert_eq!(run_ids("https://ci.run/1"), "");
        assert_eq!(run_ids("/runs//runs/5"), "\n5");
        assert_eq!(run_ids("/runs/1/runs/2"), "1\n2");
    }

    #[test]
    fn tail_keeps_the_last_lines() {
        assert_eq!(tail(b"a\nb\nc\n", 2), b"b\nc\n");
        assert_eq!(tail(b"a\nb\nc", 2), b"b\nc");
        assert_eq!(tail(b"a\n", 25), b"a\n");
        assert_eq!(tail(b"", 25), b"");
    }

    #[test]
    fn merged_capture_keeps_both_streams() {
        let got = capture_merged("sh", &["-c", "echo out; echo err >&2; exit 3"]);
        assert_eq!((got.out.as_str(), got.status), ("out\nerr", 3));
    }

    #[test]
    fn clock_is_hh_mm_ss() {
        let c = clock();
        assert_eq!(c.len(), 8);
        assert_eq!(&c[2..3], ":");
    }
}
