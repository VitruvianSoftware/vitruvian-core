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

//! Operating-system helpers the Python standard library provided for free:
//! hostname, uid, `os.access`, randomness, clocks, `subprocess.run(timeout=)`,
//! `os.path.expanduser`/`abspath`, `shutil.which`.
//!
//! No crates: the few libc calls std does not wrap are declared here. Every
//! one exists with the same signature on macOS and glibc.

use std::ffi::CString;
use std::io::{Read, Write};
use std::os::raw::{c_char, c_int, c_long};
use std::path::{Component, Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

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
    fn gethostname(name: *mut c_char, len: usize) -> c_int;
    fn getuid() -> u32;
    fn access(path: *const c_char, mode: c_int) -> c_int;
    fn localtime_r(time: *const i64, result: *mut Tm) -> *mut Tm;
}

const X_OK: c_int = 1;

/// `socket.gethostname()`.
pub fn hostname() -> String {
    let mut buf = vec![0u8; 256];
    // SAFETY: the buffer is valid for `len` bytes; gethostname NUL-terminates
    // on success (and we cap at the buffer regardless).
    let rc = unsafe { gethostname(buf.as_mut_ptr() as *mut c_char, buf.len()) };
    if rc != 0 {
        return "localhost".to_string();
    }
    let end = buf.iter().position(|b| *b == 0).unwrap_or(buf.len());
    String::from_utf8_lossy(&buf[..end]).into_owned()
}

/// `os.getuid()`.
pub fn uid() -> u32 {
    // SAFETY: getuid has no preconditions and cannot fail.
    unsafe { getuid() }
}

/// `os.access(path, os.X_OK)`.
pub fn is_executable(path: &str) -> bool {
    if path.is_empty() {
        return false;
    }
    let Ok(c) = CString::new(path) else {
        return false;
    };
    // SAFETY: `c` is a valid NUL-terminated string for the call's duration.
    unsafe { access(c.as_ptr(), X_OK) == 0 }
}

/// `datetime.datetime.now().strftime("%Y%m%d%H%M%S")` in local time.
pub fn local_timestamp_compact() -> String {
    let secs = now_secs() as i64;
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
    // SAFETY: both pointers are valid; localtime_r writes only into `tm`.
    let ok = unsafe { !localtime_r(&secs, &mut tm).is_null() };
    if !ok {
        let (y, mo, d, h, mi, s, _) = utc_parts(now_ns());
        return format!("{:04}{:02}{:02}{:02}{:02}{:02}", y, mo, d, h, mi, s);
    }
    format!(
        "{:04}{:02}{:02}{:02}{:02}{:02}",
        tm.tm_year + 1900,
        tm.tm_mon + 1,
        tm.tm_mday,
        tm.tm_hour,
        tm.tm_min,
        tm.tm_sec
    )
}

/// `time.time_ns()`.
pub fn now_ns() -> i128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos() as i128)
        .unwrap_or(0)
}

/// `time.time()`.
pub fn now_secs() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn days_to_civil(z: i64) -> (i64, u32, u32) {
    // Howard Hinnant's civil_from_days.
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if m <= 2 { y + 1 } else { y }, m, d)
}

fn utc_parts(ns: i128) -> (i64, u32, u32, u32, u32, u32, u32) {
    let secs = ns.div_euclid(1_000_000_000) as i64;
    let micros = (ns.rem_euclid(1_000_000_000) / 1000) as u32;
    let days = secs.div_euclid(86_400);
    let sod = secs.rem_euclid(86_400);
    let (y, m, d) = days_to_civil(days);
    (
        y,
        m,
        d,
        (sod / 3600) as u32,
        ((sod % 3600) / 60) as u32,
        (sod % 60) as u32,
        micros,
    )
}

/// `datetime.datetime.now(datetime.timezone.utc).isoformat()`.
pub fn utc_isoformat_now() -> String {
    let (y, mo, d, h, mi, s, us) = utc_parts(now_ns());
    if us == 0 {
        format!(
            "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}+00:00",
            y, mo, d, h, mi, s
        )
    } else {
        format!(
            "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}.{:06}+00:00",
            y, mo, d, h, mi, s, us
        )
    }
}

/// Cryptographically random bytes from the kernel (`secrets.token_bytes`).
pub fn random_bytes(n: usize) -> Vec<u8> {
    let mut buf = vec![0u8; n];
    let filled = std::fs::File::open("/dev/urandom")
        .and_then(|mut f| f.read_exact(&mut buf))
        .is_ok();
    if !filled {
        // /dev/urandom is always present on macOS and Linux; this only keeps
        // IDs unique if it somehow is not.
        let mut x = (now_ns() as u128) ^ ((std::process::id() as u128) << 64);
        for b in buf.iter_mut() {
            x = x
                .wrapping_mul(6_364_136_223_846_793_005)
                .wrapping_add(1_442_695_040_888_963_407);
            *b = (x >> 64) as u8;
        }
    }
    buf
}

pub fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write;
    bytes
        .iter()
        .fold(String::with_capacity(bytes.len() * 2), |mut out, b| {
            let _ = write!(out, "{:02x}", b);
            out
        })
}

/// `secrets.token_hex(n)`.
pub fn token_hex(n: usize) -> String {
    hex(&random_bytes(n))
}

/// `uuid.uuid4().hex`.
pub fn uuid4_hex() -> String {
    let mut b = random_bytes(16);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    hex(&b)
}

/// `os.path.expanduser`.
pub fn expanduser(path: &str) -> String {
    if path == "~" || path.starts_with("~/") {
        if let Ok(home) = std::env::var("HOME") {
            let home = home.trim_end_matches('/');
            let home = if home.is_empty() { "/" } else { home };
            if path == "~" {
                return home.to_string();
            }
            if home == "/" {
                return path[1..].to_string();
            }
            return format!("{}{}", home, &path[1..]);
        }
    }
    path.to_string()
}

/// `os.path.normpath(os.path.abspath(path))`, lexically.
pub fn abspath(path: &str) -> String {
    let p = Path::new(path);
    let joined: PathBuf = if p.is_absolute() {
        p.to_path_buf()
    } else {
        std::env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("/"))
            .join(p)
    };
    let mut parts: Vec<String> = Vec::new();
    for c in joined.components() {
        match c {
            Component::Normal(s) => parts.push(s.to_string_lossy().into_owned()),
            Component::ParentDir => {
                parts.pop();
            }
            _ => {}
        }
    }
    format!("/{}", parts.join("/"))
}

/// `os.path.join(a, b)` for the simple, relative-`b` case used here.
pub fn join(a: &str, b: &str) -> String {
    if b.starts_with('/') {
        return b.to_string();
    }
    if a.is_empty() || a.ends_with('/') {
        format!("{}{}", a, b)
    } else {
        format!("{}/{}", a, b)
    }
}

/// `os.path.dirname`.
pub fn dirname(p: &str) -> String {
    match p.rfind('/') {
        Some(0) => "/".to_string(),
        Some(i) => {
            let head = &p[..i];
            let trimmed = head.trim_end_matches('/');
            if trimmed.is_empty() {
                "/".to_string()
            } else {
                trimmed.to_string()
            }
        }
        None => String::new(),
    }
}

/// `os.path.basename`.
pub fn basename(p: &str) -> String {
    match p.rfind('/') {
        Some(i) => p[i + 1..].to_string(),
        None => p.to_string(),
    }
}

/// `os.path.getmtime` as float seconds.
pub fn mtime(path: &str) -> Option<f64> {
    std::fs::metadata(path)
        .ok()?
        .modified()
        .ok()?
        .duration_since(UNIX_EPOCH)
        .ok()
        .map(|d| d.as_secs() as f64 + d.subsec_nanos() as f64 * 1e-9)
}

/// `shutil.which(name)`.
pub fn which(name: &str) -> Option<String> {
    let path = std::env::var("PATH").ok()?;
    for dir in path.split(':') {
        let dir = if dir.is_empty() { "." } else { dir };
        let candidate = join(dir, name);
        let is_file = std::fs::metadata(&candidate)
            .map(|m| m.is_file())
            .unwrap_or(false);
        if is_file && is_executable(&candidate) {
            return Some(candidate);
        }
    }
    None
}

pub struct CmdOutput {
    /// Exit status: the code, or the negated signal number (Python's
    /// `returncode`).
    pub code: i32,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

pub enum CmdError {
    /// The program could not be started.
    Spawn(std::io::Error),
    /// `subprocess.TimeoutExpired`: killed after the deadline.
    Timeout,
}

/// `subprocess.run(argv, input=stdin, capture_output=True, timeout=timeout)`.
pub fn run(
    argv: &[&str],
    stdin: Option<&[u8]>,
    timeout: Option<f64>,
) -> Result<CmdOutput, CmdError> {
    let mut cmd = Command::new(argv[0]);
    cmd.args(&argv[1..])
        .stdin(if stdin.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        })
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut child = cmd.spawn().map_err(CmdError::Spawn)?;

    let writer = stdin.map(|data| {
        let data = data.to_vec();
        let mut pipe = child.stdin.take().expect("stdin was piped");
        std::thread::spawn(move || {
            let _ = pipe.write_all(&data);
        })
    });
    let mut out_pipe = child.stdout.take().expect("stdout was piped");
    let mut err_pipe = child.stderr.take().expect("stderr was piped");
    let out_reader = std::thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = out_pipe.read_to_end(&mut buf);
        buf
    });
    let err_reader = std::thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = err_pipe.read_to_end(&mut buf);
        buf
    });

    let deadline = timeout.map(|t| Instant::now() + Duration::from_secs_f64(t.max(0.0)));
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) => {}
            Err(e) => return Err(CmdError::Spawn(e)),
        }
        if let Some(d) = deadline {
            if Instant::now() >= d {
                let _ = child.kill();
                let _ = child.wait();
                return Err(CmdError::Timeout);
            }
        }
        std::thread::sleep(Duration::from_millis(5));
    };
    if let Some(w) = writer {
        let _ = w.join();
    }
    let stdout = out_reader.join().unwrap_or_default();
    let stderr = err_reader.join().unwrap_or_default();
    let code = match status.code() {
        Some(c) => c,
        None => {
            use std::os::unix::process::ExitStatusExt;
            -status.signal().unwrap_or(0)
        }
    };
    Ok(CmdOutput {
        code,
        stdout,
        stderr,
    })
}

/// `platform.system()` and `platform.release()`.
pub fn uname() -> (String, String) {
    let field = |flag: &str| {
        run(&["uname", flag], None, Some(2.0))
            .ok()
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .unwrap_or_default()
    };
    (field("-s"), field("-r"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn civil_dates() {
        assert_eq!(days_to_civil(0), (1970, 1, 1));
        assert_eq!(days_to_civil(20_751), (2026, 10, 25));
        assert_eq!(days_to_civil(-1), (1969, 12, 31));
    }

    #[test]
    fn path_helpers() {
        assert_eq!(dirname("/a/b/c"), "/a/b");
        assert_eq!(dirname("/a"), "/");
        assert_eq!(basename("/a/b/c.jsonl"), "c.jsonl");
        assert_eq!(abspath("/a/./b/../c/"), "/a/c");
        assert_eq!(join("/a/", "b"), "/a/b");
    }

    #[test]
    fn uuid4_shape() {
        let u = uuid4_hex();
        assert_eq!(u.len(), 32);
        assert_eq!(&u[12..13], "4");
        assert!(u
            .chars()
            .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()));
        assert_ne!(u, uuid4_hex());
    }
}
