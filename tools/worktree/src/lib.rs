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

use std::env;
use std::ffi::{OsStr, OsString};
use std::fs::{self, OpenOptions};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::os::raw::{c_char, c_int, c_void};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::io::{AsRawFd, FromRawFd};
use std::os::unix::process::ExitStatusExt;
use std::path::Path;
use std::process::{Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering as AtomicOrdering};
use std::time::{SystemTime, UNIX_EPOCH};

#[cfg(target_os = "macos")]
const LC_ALL: c_int = 0;
#[cfg(not(target_os = "macos"))]
const LC_ALL: c_int = 6;

const F_DUPFD: c_int = 0;
const F_SETFD: c_int = 2;
const FD_CLOEXEC: c_int = 1;

extern "C" {
    fn setlocale(category: c_int, locale: *const c_char) -> *mut c_char;
    fn pipe(fds: *mut c_int) -> c_int;
    fn close(fd: c_int) -> c_int;
    fn fcntl(fd: c_int, cmd: c_int, ...) -> c_int;
    fn kill(pid: c_int, sig: c_int) -> c_int;
    fn getpid() -> c_int;
    fn write(fd: c_int, buf: *const c_void, count: usize) -> isize;
}

pub const WORKTREE_SH: &str = include_str!("../worktree.sh");

const MARKER: &[u8] = b".vitruvian-worktree";
const SCRATCH_MARK: &[u8] = b"vitruvian-scratch";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorktreeEntry {
    pub path: String,
    pub branch: String,
    pub locked: String,
    pub prunable: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorktreeEntryBytes {
    pub path: Vec<u8>,
    pub branch: Vec<u8>,
    pub locked: Vec<u8>,
    pub prunable: bool,
}

trait IntoBytes {
    fn write_into(&self, buf: &mut Vec<u8>);
}

impl IntoBytes for [u8] {
    fn write_into(&self, buf: &mut Vec<u8>) {
        buf.extend_from_slice(self);
    }
}

impl IntoBytes for &[u8] {
    fn write_into(&self, buf: &mut Vec<u8>) {
        buf.extend_from_slice(self);
    }
}

impl<const N: usize> IntoBytes for &[u8; N] {
    fn write_into(&self, buf: &mut Vec<u8>) {
        buf.extend_from_slice(*self);
    }
}

impl IntoBytes for Vec<u8> {
    fn write_into(&self, buf: &mut Vec<u8>) {
        buf.extend_from_slice(self);
    }
}

impl IntoBytes for &Vec<u8> {
    fn write_into(&self, buf: &mut Vec<u8>) {
        buf.extend_from_slice(self);
    }
}

impl IntoBytes for str {
    fn write_into(&self, buf: &mut Vec<u8>) {
        buf.extend_from_slice(self.as_bytes());
    }
}

impl IntoBytes for &str {
    fn write_into(&self, buf: &mut Vec<u8>) {
        buf.extend_from_slice(self.as_bytes());
    }
}

impl IntoBytes for String {
    fn write_into(&self, buf: &mut Vec<u8>) {
        buf.extend_from_slice(self.as_bytes());
    }
}

impl IntoBytes for &String {
    fn write_into(&self, buf: &mut Vec<u8>) {
        buf.extend_from_slice(self.as_bytes());
    }
}

impl IntoBytes for usize {
    fn write_into(&self, buf: &mut Vec<u8>) {
        buf.extend_from_slice(self.to_string().as_bytes());
    }
}

impl IntoBytes for i64 {
    fn write_into(&self, buf: &mut Vec<u8>) {
        buf.extend_from_slice(self.to_string().as_bytes());
    }
}

macro_rules! bcat {
    ($($part:expr),* $(,)?) => {{
        let mut _v = Vec::new();
        $( IntoBytes::write_into(&($part), &mut _v); )*
        _v
    }};
}

fn write_fd_all(fd: c_int, mut buf: &[u8]) -> io::Result<()> {
    while !buf.is_empty() {
        let n = unsafe { write(fd, buf.as_ptr() as *const c_void, buf.len()) };
        if n < 0 {
            let err = io::Error::last_os_error();
            if err.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(err);
        }
        buf = &buf[(n as usize)..];
    }
    Ok(())
}

fn write_stderr_raw(bytes: &[u8]) {
    let _ = write_fd_all(2, bytes);
}

fn write_builtin_out(
    argv0: &[u8],
    line_no: usize,
    builtin: &[u8],
    bytes: &[u8],
) -> Result<(), i32> {
    if let Err(e) = write_fd_all(1, bytes) {
        let msg = bcat!(
            argv0,
            ": line ",
            line_no,
            ": ",
            builtin,
            ": write error: ",
            os_error_str(&e),
            "\n"
        );
        let _ = write_fd_all(2, &msg);
        return Err(1);
    }
    Ok(())
}

fn write_builtin_err(
    argv0: &[u8],
    line_no: usize,
    builtin: &[u8],
    bytes: &[u8],
) -> Result<(), i32> {
    if let Err(e) = write_fd_all(2, bytes) {
        let msg = bcat!(
            argv0,
            ": line ",
            line_no,
            ": ",
            builtin,
            ": write error: ",
            os_error_str(&e),
            "\n"
        );
        let _ = write_fd_all(2, &msg);
        return Err(1);
    }
    Ok(())
}

macro_rules! echo_ln {
    ($argv0:expr, $line:expr) => {{
        write_builtin_out($argv0, $line, b"echo", b"\n")
    }};
    ($argv0:expr, $line:expr, $($part:expr),+ $(,)?) => {{
        let mut _v = Vec::new();
        $( IntoBytes::write_into(&($part), &mut _v); )+
        _v.push(b'\n');
        write_builtin_out($argv0, $line, b"echo", &_v)
    }};
}

macro_rules! printf_ln {
    ($argv0:expr, $line:expr, $($part:expr),+ $(,)?) => {{
        let mut _v = Vec::new();
        $( IntoBytes::write_into(&($part), &mut _v); )+
        _v.push(b'\n');
        write_builtin_out($argv0, $line, b"printf", &_v)
    }};
}

macro_rules! echo_err_ln {
    ($argv0:expr, $line:expr, $($part:expr),+ $(,)?) => {{
        let mut _v = Vec::new();
        $( IntoBytes::write_into(&($part), &mut _v); )+
        _v.push(b'\n');
        write_builtin_err($argv0, $line, b"echo", &_v)
    }};
}

macro_rules! err_ln {
    ($($part:expr),+ $(,)?) => {{
        let mut _v = Vec::new();
        $( IntoBytes::write_into(&($part), &mut _v); )+
        _v.push(b'\n');
        write_stderr_raw(&_v);
    }};
}

fn bytes_to_os(b: &[u8]) -> &OsStr {
    OsStr::from_bytes(b)
}

fn bytes_to_path(b: &[u8]) -> &Path {
    Path::new(OsStr::from_bytes(b))
}

fn split_lf(data: &[u8]) -> Vec<&[u8]> {
    if data.is_empty() {
        return Vec::new();
    }
    let stripped = data.strip_suffix(b"\n").unwrap_or(data);
    stripped.split(|&b| b == b'\n').collect()
}

fn trim_trailing_newlines(mut data: &[u8]) -> &[u8] {
    while let Some(rest) = data.strip_suffix(b"\n") {
        data = rest;
    }
    data
}

fn head_1_slice(data: &[u8]) -> &[u8] {
    match data.iter().position(|&b| b == b'\n') {
        Some(idx) => &data[..=idx],
        None => data,
    }
}

// 0 = unknown, 1 = bash 3.x, 2 = bash 4.0..4.3, 3 = bash >= 4.4
static BASH_INFO_CACHE: AtomicUsize = AtomicUsize::new(0);

fn detect_bash_info() -> usize {
    let cached = BASH_INFO_CACHE.load(AtomicOrdering::Relaxed);
    if cached != 0 {
        return cached;
    }
    let out = Command::new("bash")
        .args([
            "-c",
            "printf '%s.%s' \"${BASH_VERSINFO[0]:-0}\" \"${BASH_VERSINFO[1]:-0}\"",
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output();
    let info = match out {
        Ok(o) if o.status.success() => {
            let s = String::from_utf8_lossy(&o.stdout);
            let mut parts = s.trim().split('.');
            let maj: u32 = parts.next().and_then(|p| p.parse().ok()).unwrap_or(0);
            let min: u32 = parts.next().and_then(|p| p.parse().ok()).unwrap_or(0);
            if maj > 4 || (maj == 4 && min >= 4) {
                3
            } else if maj == 4 {
                2
            } else {
                1
            }
        }
        _ => 3,
    };
    BASH_INFO_CACHE.store(info, AtomicOrdering::Relaxed);
    info
}

fn bash_warns_on_nul() -> bool {
    detect_bash_info() == 3
}

fn bash_is_v3() -> bool {
    detect_bash_info() == 1
}

/// Emulate bash command substitution `$(...)`: drop NUL bytes, strip trailing newlines,
/// and emit `warning: command substitution: ignored null byte in input` when bash >= 4.4 is in use.
fn comsub_bytes(raw: &[u8], argv0: &[u8], line_no: usize) -> Vec<u8> {
    if raw.contains(&0) {
        let filtered: Vec<u8> = raw.iter().copied().filter(|&b| b != 0).collect();
        let res = trim_trailing_newlines(&filtered).to_vec();
        if bash_warns_on_nul() {
            err_ln!(
                argv0,
                ": line ",
                line_no,
                ": warning: command substitution: ignored null byte in input"
            );
        }
        res
    } else {
        trim_trailing_newlines(raw).to_vec()
    }
}

fn status_to_exit_code(status: ExitStatus) -> i32 {
    if let Some(code) = status.code() {
        code
    } else if let Some(sig) = status.signal() {
        128 + sig
    } else {
        1
    }
}

fn handle_spawn_error(
    err: &io::Error,
    cmd: &[u8],
    argv0: &[u8],
    line_no: usize,
    quiet_stderr: bool,
) -> i32 {
    if !cmd.contains(&b'/') {
        if let Some(path_os) = env::var_os("PATH") {
            let path_bytes = path_os.into_vec();
            if !path_bytes.is_empty() {
                for dir in path_bytes.split(|&b| b == b':') {
                    let cand = if dir.is_empty() {
                        cmd.to_vec()
                    } else {
                        bcat!(dir, "/", cmd)
                    };
                    let p = bytes_to_path(&cand);
                    if let Ok(meta) = fs::metadata(p) {
                        if meta.is_file() && (meta.permissions().mode() & 0o111 == 0) {
                            if !quiet_stderr {
                                err_ln!(
                                    argv0,
                                    ": line ",
                                    line_no,
                                    ": ",
                                    &cand,
                                    ": Permission denied"
                                );
                            }
                            return 126;
                        }
                    }
                }
                if !quiet_stderr {
                    err_ln!(argv0, ": line ", line_no, ": ", cmd, ": command not found");
                }
                return 127;
            }
        }
        let p = bytes_to_path(cmd);
        if p.exists() {
            if !quiet_stderr {
                err_ln!(argv0, ": line ", line_no, ": ", cmd, ": Permission denied");
            }
            return 126;
        }
        if !quiet_stderr {
            err_ln!(
                argv0,
                ": line ",
                line_no,
                ": ",
                cmd,
                ": No such file or directory"
            );
        }
        return 127;
    }

    if err.kind() == io::ErrorKind::NotFound {
        if !quiet_stderr {
            err_ln!(
                argv0,
                ": line ",
                line_no,
                ": ",
                cmd,
                ": No such file or directory"
            );
        }
        127
    } else {
        if !quiet_stderr {
            err_ln!(
                argv0,
                ": line ",
                line_no,
                ": ",
                cmd,
                ": ",
                os_error_str(err)
            );
        }
        126
    }
}

fn is_utf8_locale() -> bool {
    let p = unsafe { setlocale(LC_ALL, std::ptr::null()) };
    if p.is_null() {
        return false;
    }
    let bytes = unsafe { std::ffi::CStr::from_ptr(p).to_bytes() };
    let lower: Vec<u8> = bytes.iter().map(|b| b.to_ascii_lowercase()).collect();
    lower.windows(5).any(|w| w == b"utf-8") || lower.windows(4).any(|w| w == b"utf8")
}

fn first_n_chars_bytes(data: &[u8], n: usize) -> Vec<u8> {
    if is_utf8_locale() {
        if let Ok(s) = std::str::from_utf8(data) {
            return s.chars().take(n).collect::<String>().into_bytes();
        }
    }
    data[..data.len().min(n)].to_vec()
}

fn os_error_str(e: &io::Error) -> String {
    let s = e.to_string();
    if let Some(idx) = s.rfind(" (os error ") {
        s[..idx].to_string()
    } else {
        s
    }
}

/// Extract usage text from the embedded `worktree.sh` header comment,
/// matching: `sed -n '/^# worktree.sh/,/^set -euo/p' | sed '$d' | sed 's/^# \{0,1\}//'`
pub fn extract_usage(script: &str) -> String {
    let mut in_block = false;
    let mut collected = Vec::new();
    for line in split_lf(script.as_bytes()) {
        let line_s = std::str::from_utf8(line).unwrap_or("");
        if !in_block {
            if line_s.starts_with("# worktree.sh") {
                in_block = true;
            } else {
                continue;
            }
        }
        collected.push(line_s);
        if line_s.starts_with("set -euo") {
            break;
        }
    }
    if !collected.is_empty() {
        collected.pop();
    }
    let mut out = String::new();
    for line in collected {
        let stripped = if let Some(rest) = line.strip_prefix("# ") {
            rest
        } else if let Some(rest) = line.strip_prefix('#') {
            rest
        } else {
            line
        };
        out.push_str(stripped);
        out.push('\n');
    }
    out
}

/// Replace `/` with `-` in a branch or worktree name.
pub fn slug(s: &str) -> String {
    s.replace('/', "-")
}

pub fn slug_bytes(s: &[u8]) -> Vec<u8> {
    s.iter()
        .map(|&b| if b == b'/' { b'-' } else { b })
        .collect()
}

/// Pure Rust RFC 1321 MD5 implementation returning lowercase 32-char hex string.
pub fn md5_hex(input: &[u8]) -> String {
    const S: [u32; 64] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5,
        9, 14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10,
        15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ];
    const K: [u32; 64] = [
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613,
        0xfd469501, 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193,
        0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d,
        0x02441453, 0xd8a1e681, 0xe7d3fbc8, 0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
        0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122,
        0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70, 0x289b7ec6, 0xeaa127fa,
        0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665, 0xf4292244,
        0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb,
        0xeb86d391,
    ];

    let mut a0: u32 = 0x67452301;
    let mut b0: u32 = 0xefcdab89;
    let mut c0: u32 = 0x98badcfe;
    let mut d0: u32 = 0x10325476;

    let bit_len = (input.len() as u64).wrapping_mul(8);
    let mut msg = input.to_vec();
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_le_bytes());

    for chunk in msg.chunks_exact(64) {
        let mut m = [0u32; 16];
        for (i, word) in m.iter_mut().enumerate() {
            let base = i * 4;
            *word = u32::from_le_bytes([
                chunk[base],
                chunk[base + 1],
                chunk[base + 2],
                chunk[base + 3],
            ]);
        }

        let mut a = a0;
        let mut b = b0;
        let mut c = c0;
        let mut d = d0;

        for i in 0..64 {
            let (f, g) = match i {
                0..=15 => ((b & c) | ((!b) & d), i),
                16..=31 => ((d & b) | ((!d) & c), (5 * i + 1) % 16),
                32..=47 => (b ^ c ^ d, (3 * i + 5) % 16),
                _ => (c ^ (b | (!d)), (7 * i) % 16),
            };
            let temp = d;
            d = c;
            c = b;
            let sum = a.wrapping_add(f).wrapping_add(K[i]).wrapping_add(m[g]);
            b = b.wrapping_add(sum.rotate_left(S[i]));
            a = temp;
        }

        a0 = a0.wrapping_add(a);
        b0 = b0.wrapping_add(b);
        c0 = c0.wrapping_add(c);
        d0 = d0.wrapping_add(d);
    }

    let mut digest = [0u8; 16];
    digest[0..4].copy_from_slice(&a0.to_le_bytes());
    digest[4..8].copy_from_slice(&b0.to_le_bytes());
    digest[8..12].copy_from_slice(&c0.to_le_bytes());
    digest[12..16].copy_from_slice(&d0.to_le_bytes());

    let mut out = String::with_capacity(32);
    for byte in digest {
        out.push_str(&format!("{byte:02x}"));
    }
    out
}

/// Format UTC epoch seconds as `%Y-%m-%dT%H:%MZ` (matching `date -u +%Y-%m-%dT%H:%MZ`).
pub fn format_utc_hm(epoch_secs: u64) -> String {
    let days = (epoch_secs / 86400) as i64;
    let secs_of_day = epoch_secs % 86400;
    let hour = secs_of_day / 3600;
    let minute = (secs_of_day % 3600) / 60;

    let z = days + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = (z - era * 146097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = (yoe as i64) + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if m <= 2 { y + 1 } else { y };

    format!("{year:04}-{m:02}-{d:02}T{hour:02}:{minute:02}Z")
}

/// Strip `\033\[[0-9;]*m` ANSI CSI SGR sequences from a byte slice.
pub fn strip_ansi_sgr_bytes(bytes: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == 0x1b && i + 1 < bytes.len() && bytes[i + 1] == b'[' {
            let mut j = i + 2;
            while j < bytes.len() && (bytes[j].is_ascii_digit() || bytes[j] == b';') {
                j += 1;
            }
            if j < bytes.len() && bytes[j] == b'm' {
                i = j + 1;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    out
}

/// Strip `\033\[[0-9;]*m` ANSI CSI SGR sequences from a string.
pub fn strip_ansi_sgr(s: &str) -> String {
    String::from_utf8_lossy(&strip_ansi_sgr_bytes(s.as_bytes())).into_owned()
}

/// Clean output from `landed.sh`, matching:
/// `printf '%s' "${LANDED_SAYS}" | sed -e $'s/\033\\[[0-9;]*m//g' -e 's/^✓ //' -e 's/^✗ //' -e 's/^→ //' | head -1`
pub fn clean_landed_output_bytes(raw: &[u8]) -> Vec<u8> {
    let trimmed = trim_trailing_newlines(raw);
    let first_line = trimmed.split(|&b| b == b'\n').next().unwrap_or(b"");
    let no_ansi = strip_ansi_sgr_bytes(first_line);
    let s = no_ansi.strip_prefix("✓ ".as_bytes()).unwrap_or(&no_ansi);
    let s = s.strip_prefix("✗ ".as_bytes()).unwrap_or(s);
    let s = s.strip_prefix("→ ".as_bytes()).unwrap_or(s);
    s.to_vec()
}

pub fn clean_landed_output(raw: &str) -> String {
    String::from_utf8_lossy(&clean_landed_output_bytes(raw.as_bytes())).into_owned()
}

/// Parse `git worktree list --porcelain` output in bytes, matching the awk script in `worktrees()`.
pub fn parse_worktrees_porcelain_bytes(porcelain: &[u8]) -> Vec<WorktreeEntryBytes> {
    let mut entries = Vec::new();
    let mut p = Vec::new();
    let mut b = Vec::new();
    let mut l = Vec::new();
    let mut pr = false;

    let flush = |entries: &mut Vec<WorktreeEntryBytes>,
                 p: &mut Vec<u8>,
                 b: &mut Vec<u8>,
                 l: &mut Vec<u8>,
                 pr: &mut bool| {
        if !p.is_empty() {
            entries.push(WorktreeEntryBytes {
                path: std::mem::take(p),
                branch: std::mem::take(b),
                locked: std::mem::take(l),
                prunable: *pr,
            });
        }
        p.clear();
        b.clear();
        l.clear();
        *pr = false;
    };

    for line in split_lf(porcelain) {
        if let Some(rest) = line.strip_prefix(b"worktree ") {
            flush(&mut entries, &mut p, &mut b, &mut l, &mut pr);
            p = rest.to_vec();
        } else if let Some(rest) = line.strip_prefix(b"branch ") {
            let short = rest.strip_prefix(b"refs/heads/").unwrap_or(rest);
            b = short.to_vec();
        } else if line.starts_with(b"locked") {
            let char_len = std::str::from_utf8(line)
                .map(|s| s.chars().count())
                .unwrap_or(line.len());
            if char_len > 7 && line.len() > 7 {
                l = bcat!("locked: ", &line[7..]);
            } else {
                l = b"locked".to_vec();
            }
        } else if line.starts_with(b"prunable") {
            pr = true;
        }
    }
    flush(&mut entries, &mut p, &mut b, &mut l, &mut pr);
    entries
}

/// Parse `git worktree list --porcelain` output, matching the awk script in `worktrees()`.
pub fn parse_worktrees_porcelain(porcelain: &str) -> Vec<WorktreeEntry> {
    parse_worktrees_porcelain_bytes(porcelain.as_bytes())
        .into_iter()
        .map(|e| WorktreeEntry {
            path: String::from_utf8_lossy(&e.path).into_owned(),
            branch: String::from_utf8_lossy(&e.branch).into_owned(),
            locked: String::from_utf8_lossy(&e.locked).into_owned(),
            prunable: e.prunable,
        })
        .collect()
}

fn resolve_output_root_bytes_inner(
    bazelrc_content: Option<&[u8]>,
    cache_root: &[u8],
    repo_name: &[u8],
    branch_or_name: &[u8],
    warn_ctx: Option<(&[u8], usize)>,
) -> Vec<u8> {
    let mut r = Vec::new();
    let mut raw_matched: Option<&[u8]> = None;
    if let Some(content) = bazelrc_content {
        for line in split_lf(content) {
            if let Some(val) = line.strip_prefix(b"startup --output_user_root=") {
                raw_matched = Some(val);
            }
        }
    }
    if let Some(val) = raw_matched {
        r = match warn_ctx {
            Some((argv0, line_no)) => comsub_bytes(val, argv0, line_no),
            None => val.iter().copied().filter(|&b| b != 0).collect(),
        };
    }
    if r.is_empty() {
        // Deliberate KEEP-SAFE divergence from worktree.sh: on macOS in a UTF-8 locale,
        // `/usr/bin/tr '/' '-'` aborts mid-stream on non-UTF-8 branch bytes and outputs a
        // truncated prefix, which in `output_root_of` would resolve to and `rm -rf` a
        // shorter-named sibling worktree's Bazel cache root. Use pure-byte slugging here.
        r = bcat!(cache_root, "/", repo_name, "-", slug_bytes(branch_or_name));
    }
    if r.windows(2).any(|w| w == b"..") {
        Vec::new()
    } else {
        let prefix = bcat!(cache_root, "/");
        if r.starts_with(&prefix) && r.len() > prefix.len() {
            r
        } else {
            Vec::new()
        }
    }
}

/// Compute `output_root_of` from optional `user.bazelrc` byte contents.
pub fn resolve_output_root_bytes(
    bazelrc_content: Option<&[u8]>,
    cache_root: &[u8],
    repo_name: &[u8],
    branch_or_name: &[u8],
) -> Vec<u8> {
    resolve_output_root_bytes_inner(bazelrc_content, cache_root, repo_name, branch_or_name, None)
}

/// Compute `output_root_of` from optional `user.bazelrc` contents.
pub fn resolve_output_root(
    bazelrc_content: Option<&str>,
    cache_root: &str,
    repo_name: &str,
    branch_or_name: &str,
) -> String {
    let res = resolve_output_root_bytes(
        bazelrc_content.map(|s| s.as_bytes()),
        cache_root.as_bytes(),
        repo_name.as_bytes(),
        branch_or_name.as_bytes(),
    );
    String::from_utf8_lossy(&res).into_owned()
}

/// Extract the managed build-cache block and remote headers from the primary `user.bazelrc` bytes.
pub fn extract_primary_bazelrc_cache_bytes(primary_rc: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    let mut inblk = false;
    let lines = split_lf(primary_rc);
    for line in &lines {
        if line.starts_with(b"# >>> build cache (managed by tools/remote:setup)") {
            inblk = true;
        }
        if inblk {
            out.extend_from_slice(line);
            out.push(b'\n');
        }
        if line.starts_with(b"# <<< build cache (managed by tools/remote:setup)") {
            inblk = false;
        }
    }
    for line in &lines {
        if line.starts_with(b"common:remote --remote_header=")
            || line.starts_with(b"common:remote --bes_header=")
        {
            out.extend_from_slice(line);
            out.push(b'\n');
        }
    }
    out
}

/// Extract the managed build-cache block and remote headers from the primary `user.bazelrc`.
pub fn extract_primary_bazelrc_cache_lines(primary_rc: &str) -> String {
    String::from_utf8_lossy(&extract_primary_bazelrc_cache_bytes(primary_rc.as_bytes()))
        .into_owned()
}

/// Resolve physical directory path like `real() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }`.
pub fn real_path_bytes(p: &[u8]) -> Vec<u8> {
    if p.is_empty() {
        return Vec::new();
    }
    let path = bytes_to_path(p);
    if path.is_dir() {
        if let Ok(canon) = fs::canonicalize(path) {
            return canon.into_os_string().into_vec();
        }
    }
    p.to_vec()
}

pub fn real_path(p: &str) -> String {
    String::from_utf8_lossy(&real_path_bytes(p.as_bytes())).into_owned()
}

fn basename_bytes(p: &[u8]) -> Vec<u8> {
    let mut end = p.len();
    while end > 0 && p[end - 1] == b'/' {
        end -= 1;
    }
    let trimmed = &p[..end];
    if trimmed.is_empty() {
        return b"/".to_vec();
    }
    match trimmed.iter().rposition(|&b| b == b'/') {
        Some(idx) => trimmed[idx + 1..].to_vec(),
        None => trimmed.to_vec(),
    }
}

fn dirname_bytes(p: &[u8]) -> Vec<u8> {
    let mut end = p.len();
    while end > 0 && p[end - 1] == b'/' {
        end -= 1;
    }
    let trimmed = &p[..end];
    if trimmed.is_empty() {
        return b"/".to_vec();
    }
    match trimmed.iter().rposition(|&b| b == b'/') {
        Some(0) => b"/".to_vec(),
        Some(idx) => {
            let mut pend = idx;
            while pend > 0 && trimmed[pend - 1] == b'/' {
                pend -= 1;
            }
            if pend == 0 {
                b"/".to_vec()
            } else {
                trimmed[..pend].to_vec()
            }
        }
        None => b".".to_vec(),
    }
}

fn cd_and_pwd_p(dir: &[u8], argv0: &[u8], line_no: usize) -> Result<Vec<u8>, i32> {
    let saved = env::current_dir().ok();
    if let Err(e) = env::set_current_dir(bytes_to_path(dir)) {
        err_ln!(
            argv0,
            ": line ",
            line_no,
            ": cd: ",
            dir,
            ": ",
            os_error_str(&e)
        );
        return Err(1);
    }
    let phys = match env::current_dir() {
        Ok(p) => p.into_os_string().into_vec(),
        Err(_) => real_path_bytes(dir),
    };
    if let Some(s) = saved {
        let _ = env::set_current_dir(s);
    }
    Ok(phys)
}

fn ensure_file_above_stdio(f: fs::File) -> io::Result<fs::File> {
    let raw = f.as_raw_fd();
    if raw < 3 {
        let new_fd = unsafe { fcntl(raw, F_DUPFD, 3 as c_int) };
        if new_fd < 0 {
            return Err(io::Error::last_os_error());
        }
        let _ = unsafe { fcntl(new_fd, F_SETFD, FD_CLOEXEC) };
        drop(f);
        Ok(unsafe { fs::File::from_raw_fd(new_fd) })
    } else {
        Ok(f)
    }
}

fn write_file_redirect(
    path: &[u8],
    data: &[u8],
    append: bool,
    argv0: &[u8],
    line_no: usize,
) -> Result<(), i32> {
    let mut opts = OpenOptions::new();
    opts.create(true).write(true);
    if append {
        opts.append(true);
    } else {
        opts.truncate(true);
    }
    let mut file = match opts.open(bytes_to_path(path)) {
        Ok(f) => f,
        Err(e) => {
            err_ln!(
                argv0,
                ": line ",
                line_no,
                ": ",
                path,
                ": ",
                os_error_str(&e)
            );
            return Err(1);
        }
    };
    if let Err(e) = file.write_all(data) {
        err_ln!(
            argv0,
            ": line ",
            line_no,
            ": printf: write error: ",
            os_error_str(&e)
        );
        return Err(1);
    }
    Ok(())
}

fn mkdir_p(path: &[u8], argv0: &[u8], line_no: usize) -> Result<(), i32> {
    let status = Command::new("mkdir")
        .arg("-p")
        .arg(bytes_to_os(path))
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status();
    match status {
        Ok(s) if s.success() => Ok(()),
        Ok(s) => Err(status_to_exit_code(s)),
        Err(e) => Err(handle_spawn_error(&e, b"mkdir", argv0, line_no, false)),
    }
}

fn chmod_and_rm_rf(path: &[u8], errexit: bool, argv0: &[u8], rm_line: usize) -> Result<(), i32> {
    let _ = Command::new("chmod")
        .args(["-R", "u+w"])
        .arg(bytes_to_os(path))
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::null())
        .status();
    let status = Command::new("rm")
        .arg("-rf")
        .arg(bytes_to_os(path))
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status();
    let code = match status {
        Ok(s) if s.success() => 0,
        Ok(s) => status_to_exit_code(s),
        Err(e) => handle_spawn_error(&e, b"rm", argv0, rm_line, false),
    };
    if code != 0 && errexit {
        return Err(code);
    }
    Ok(())
}

static TEMP_COUNTER: AtomicUsize = AtomicUsize::new(0);

fn open_temp_stdin(input: &[u8]) -> io::Result<fs::File> {
    let pid = unsafe { getpid() };
    for attempt in 0..1000usize {
        let seq = TEMP_COUNTER.fetch_add(1, AtomicOrdering::Relaxed);
        let path = format!("/tmp/.wt-stdin-{pid}-{seq}-{attempt}");
        match OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .open(&path)
        {
            Ok(mut f) => {
                let _ = fs::remove_file(&path);
                f.write_all(input)?;
                f.seek(SeekFrom::Start(0))?;
                return ensure_file_above_stdio(f);
            }
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
    Err(io::Error::new(
        io::ErrorKind::Other,
        "failed to create temp stdin",
    ))
}

fn run_with_stdin(
    prog: &str,
    args: &[&str],
    input: &[u8],
    stderr_inherit: bool,
) -> io::Result<std::process::Output> {
    let stdin_file = open_temp_stdin(input)?;
    Command::new(prog)
        .args(args)
        .stdin(Stdio::from(stdin_file))
        .stdout(Stdio::piped())
        .stderr(if stderr_inherit {
            Stdio::inherit()
        } else {
            Stdio::null()
        })
        .output()
}

fn spawn_with_temp_stdin(
    prog: &str,
    args: &[&str],
    input: &[u8],
    stdout_inherit: bool,
    stderr_inherit: bool,
) -> io::Result<ExitStatus> {
    let stdin_file = open_temp_stdin(input)?;
    Command::new(prog)
        .args(args)
        .stdin(Stdio::from(stdin_file))
        .stdout(if stdout_inherit {
            Stdio::inherit()
        } else {
            Stdio::null()
        })
        .stderr(if stderr_inherit {
            Stdio::inherit()
        } else {
            Stdio::null()
        })
        .status()
}

fn write_heredoc_cat(argv0: &[u8], line_no: usize, data: &[u8]) -> i32 {
    if write_fd_all(1, data).is_ok() {
        return 0;
    }
    match spawn_with_temp_stdin("cat", &[], data, true, true) {
        Ok(s) => status_to_exit_code(s),
        Err(e) => handle_spawn_error(&e, b"cat", argv0, line_no, false),
    }
}

fn write_usage_sed(argv0: &[u8], line_no: usize, data: &[u8]) -> i32 {
    if write_fd_all(1, data).is_ok() {
        return 0;
    }
    match spawn_with_temp_stdin("sed", &["s/^# \\{0,1\\}//"], data, true, true) {
        Ok(s) => status_to_exit_code(s),
        Err(e) => handle_spawn_error(&e, b"sed", argv0, line_no, false),
    }
}

fn cut_first_field(out: &[u8]) -> Vec<u8> {
    let trimmed = trim_trailing_newlines(out);
    let line = trimmed.split(|&b| b == b'\n').next().unwrap_or(b"");
    line.split(|&b| b == b' ').next().unwrap_or(b"").to_vec()
}

fn make_cloexec_above_stdio(fd: c_int) -> Option<c_int> {
    let target = if fd < 3 {
        let new_fd = unsafe { fcntl(fd, F_DUPFD, 3 as c_int) };
        unsafe {
            close(fd);
        }
        if new_fd < 0 {
            return None;
        }
        new_fd
    } else {
        fd
    };
    if unsafe { fcntl(target, F_SETFD, FD_CLOEXEC) } < 0 {
        unsafe {
            close(target);
        }
        return None;
    }
    Some(target)
}

fn run_landed_merged(
    script: &[u8],
    branch: &[u8],
    repo: &[u8],
    base_ref: &[u8],
) -> (Vec<u8>, bool) {
    let mut fds = [0 as c_int; 2];
    if unsafe { pipe(fds.as_mut_ptr()) } != 0 {
        return (Vec::new(), false);
    }
    let Some(read_fd) = make_cloexec_above_stdio(fds[0]) else {
        unsafe {
            close(fds[1]);
        }
        return (Vec::new(), false);
    };
    let Some(write_fd1) = make_cloexec_above_stdio(fds[1]) else {
        unsafe {
            close(read_fd);
        }
        return (Vec::new(), false);
    };
    let raw_w2 = unsafe { fcntl(write_fd1, F_DUPFD, 3 as c_int) };
    if raw_w2 < 0 {
        unsafe {
            close(read_fd);
            close(write_fd1);
        }
        return (Vec::new(), false);
    }
    if unsafe { fcntl(raw_w2, F_SETFD, FD_CLOEXEC) } < 0 {
        unsafe {
            close(read_fd);
            close(write_fd1);
            close(raw_w2);
        }
        return (Vec::new(), false);
    }
    let write_fd2 = raw_w2;

    let mut read_file = unsafe { fs::File::from_raw_fd(read_fd) };
    let spawn_res = {
        let stdout_stdio = unsafe { Stdio::from_raw_fd(write_fd1) };
        let stderr_stdio = unsafe { Stdio::from_raw_fd(write_fd2) };
        Command::new("bash")
            .arg(bytes_to_os(script))
            .arg("--branch")
            .arg(bytes_to_os(branch))
            .env("BUILD_WORKSPACE_DIRECTORY", bytes_to_os(repo))
            .env("LANDED_BASE", bytes_to_os(base_ref))
            .env("LANDED_NO_FETCH", "1")
            .stdin(Stdio::null())
            .stdout(stdout_stdio)
            .stderr(stderr_stdio)
            .spawn()
    };
    let Ok(mut child) = spawn_res else {
        return (Vec::new(), false);
    };
    let mut buf = Vec::new();
    let _ = read_file.read_to_end(&mut buf);
    drop(read_file);
    let success = child.wait().map(|s| s.success()).unwrap_or(false);
    (buf, success)
}

fn eval_scratch_ttl_hours(raw: &[u8], argv0: &[u8]) -> Result<i64, ()> {
    let mut start = 0;
    let mut end = raw.len();
    while start < end && raw[start].is_ascii_whitespace() {
        start += 1;
    }
    while end > start && raw[end - 1].is_ascii_whitespace() {
        end -= 1;
    }
    let trimmed = &raw[start..end];
    if trimmed.is_empty() {
        err_ln!(
            argv0,
            ": line 246: * 60: syntax error: operand expected (error token is \"* 60\")"
        );
        return Err(());
    }

    let (neg, digits) = if let Some(rest) = trimmed.strip_prefix(b"-") {
        (true, rest)
    } else if let Some(rest) = trimmed.strip_prefix(b"+") {
        (false, rest)
    } else {
        (false, trimmed)
    };

    if !digits.is_empty() && digits.iter().all(|b| b.is_ascii_digit()) {
        let s = std::str::from_utf8(digits).unwrap_or("");
        if digits.len() > 1 && digits[0] == b'0' {
            if digits.iter().all(|&b| (b'0'..=b'7').contains(&b)) {
                if let Ok(v) = i64::from_str_radix(s, 8) {
                    return Ok(if neg { -v } else { v });
                }
            }
            err_ln!(
                argv0,
                ": line 246: ",
                trimmed,
                ": value too great for base (error token is \"",
                trimmed,
                "\")"
            );
            return Err(());
        }
        if let Ok(v) = s.parse::<i64>() {
            return Ok(if neg { -v } else { v });
        }
    }

    if !digits.is_empty() && digits[0].is_ascii_digit() {
        err_ln!(
            argv0,
            ": line 246: ",
            trimmed,
            ": value too great for base (error token is \"",
            trimmed,
            "\")"
        );
        return Err(());
    }

    if (trimmed[0].is_ascii_alphabetic() || trimmed[0] == b'_')
        && trimmed[1..]
            .iter()
            .all(|&b| b.is_ascii_alphanumeric() || b == b'_')
    {
        err_ln!(argv0, ": line 246: ", trimmed, ": unbound variable");
        return Err(());
    }

    err_ln!(
        argv0,
        ": line 246: ",
        trimmed,
        ": syntax error: operand expected (error token is \"",
        trimmed,
        "\")"
    );
    Err(())
}

struct Context {
    argv0: Vec<u8>,
    start_pwd: Vec<u8>,
    here: Vec<u8>,
    repo: Vec<u8>,
    repo_name: Vec<u8>,
    wt_root: Vec<u8>,
    cache_root: Vec<u8>,
    bazel_root: Vec<u8>,
    user: Vec<u8>,
    scratch_ttl_hours: Vec<u8>,
    base_ref: Vec<u8>,
    landed_says: Vec<u8>,
}

impl Context {
    fn slug_tr(&self, input: &[u8], line_no: usize) -> Result<Vec<u8>, i32> {
        match run_with_stdin("tr", &["/", "-"], input, true) {
            Ok(o) => {
                if !o.status.success() {
                    return Err(status_to_exit_code(o.status));
                }
                Ok(comsub_bytes(&o.stdout, &self.argv0, line_no))
            }
            Err(e) => Err(handle_spawn_error(&e, b"tr", &self.argv0, 101, false)),
        }
    }

    fn resolve_landed_script(&self) -> Option<Vec<u8>> {
        let rel = b"tools/landed/landed.sh";
        let runfiles_rel = b"_main/tools/landed/landed.sh";

        let wt_landed = env::var_os("WORKTREE_LANDED")
            .map(|v| v.into_vec())
            .unwrap_or_default();
        let rf_dir = env::var_os("RUNFILES_DIR")
            .map(|v| v.into_vec())
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| b"/nonexistent".to_vec());

        let candidates = [
            wt_landed,
            bcat!(&rf_dir, "/", runfiles_rel),
            bcat!(&self.start_pwd, "/", rel),
            bcat!(&self.argv0, ".runfiles/", runfiles_rel),
            bcat!(&self.repo, "/", rel),
        ];

        for c in candidates {
            if !c.is_empty() && bytes_to_path(&c).is_file() {
                return Some(c);
            }
        }
        None
    }

    fn is_landed(&mut self, branch: &[u8]) -> bool {
        let Some(script) = self.resolve_landed_script() else {
            self.landed_says = b"cannot find tools/landed/landed.sh".to_vec();
            return false;
        };

        let (combined, success) = run_landed_merged(&script, branch, &self.repo, &self.base_ref);
        let comsub = comsub_bytes(&combined, &self.argv0, 128);
        self.landed_says = clean_landed_output_bytes(&comsub);
        success
    }

    fn worktrees(&self) -> Result<Vec<WorktreeEntryBytes>, i32> {
        let out = Command::new("git")
            .args(["worktree", "list", "--porcelain"])
            .stdin(Stdio::inherit())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .output()
            .map_err(|e| handle_spawn_error(&e, b"git", &self.argv0, 137, false))?;
        if !out.status.success() {
            return Err(status_to_exit_code(out.status));
        }
        Ok(parse_worktrees_porcelain_bytes(&out.stdout))
    }

    fn find_worktree(&self, want: &[u8]) -> Result<Option<WorktreeEntryBytes>, i32> {
        if let Ok(entries) = self.worktrees() {
            for e in entries {
                // Deliberate KEEP-SAFE divergence from worktree.sh: awk -v b="$want" '$2 == b'
                // compares numeric-looking branch names numerically (so "1.1" matches "1.10")
                // and expands backslash escapes; use exact byte comparison so we never
                // match or remove the wrong branch.
                if e.branch == want {
                    return Ok(Some(e));
                }
            }
        }
        let want_slug = slug_bytes(want);
        let want_real = real_path_bytes(want);
        let entries2 = self.worktrees()?;
        for e in entries2 {
            if !e.branch.is_empty() {
                continue;
            }
            if basename_bytes(&e.path) == want_slug || real_path_bytes(&e.path) == want_real {
                return Ok(Some(e));
            }
        }
        Ok(None)
    }

    fn output_root_of(&self, wt_path: &[u8], branch: &[u8]) -> Vec<u8> {
        let rc_path = bcat!(wt_path, "/user.bazelrc");
        let content = if bytes_to_path(&rc_path).is_file() {
            fs::read(bytes_to_path(&rc_path)).ok()
        } else {
            None
        };
        resolve_output_root_bytes_inner(
            content.as_deref(),
            &self.cache_root,
            &self.repo_name,
            branch,
            Some((&self.argv0, 152)),
        )
    }

    fn md5_of(&self, input: &[u8]) -> Vec<u8> {
        if let Ok(o) = run_with_stdin("md5sum", &[], input, false) {
            if o.status.success() {
                return cut_first_field(&o.stdout);
            }
        }
        if let Ok(o) = run_with_stdin("/sbin/md5", &["-q"], input, false) {
            if o.status.success() {
                return cut_first_field(&o.stdout);
            }
        }
        if let Ok(o) = run_with_stdin("md5", &["-q"], input, false) {
            if o.status.success() {
                return cut_first_field(&o.stdout);
            }
        }
        match run_with_stdin("openssl", &["md5", "-r"], input, true) {
            Ok(o) => cut_first_field(&o.stdout),
            Err(e) => {
                let _ = handle_spawn_error(&e, b"openssl", &self.argv0, 105, false);
                Vec::new()
            }
        }
    }

    fn server_pids(&self, wt_path: &[u8], output_root: &[u8]) -> Vec<u8> {
        let h = self.md5_of(wt_path);
        if h.is_empty() {
            return b"unknown(no md5 tool)".to_vec();
        }
        let mut files = vec![bcat!(&self.bazel_root, "/", &h, "/server/server.pid.txt")];
        if !output_root.is_empty() {
            files.push(bcat!(output_root, "/", &h, "/server/server.pid.txt"));
        }
        let mut out = Vec::new();
        for f in files {
            let p = bytes_to_path(&f);
            if !p.is_file() {
                continue;
            }
            let raw = fs::read(p).unwrap_or_default();
            let pid = comsub_bytes(&raw, &self.argv0, 172);
            if !pid.is_empty() && kill_check(&pid) {
                out.extend_from_slice(&pid);
                out.push(b'\n');
            }
        }
        trim_trailing_newlines(&out).to_vec()
    }

    fn stop_servers(&self, wt_path: &[u8], output_root: &[u8]) -> bool {
        let mut pids = self.server_pids(wt_path, output_root);
        if pids.is_empty() {
            return true;
        }
        if pids.starts_with(b"unknown") {
            let _ = echo_err_ln!(
                &self.argv0,
                185,
                "worktree: cannot tell whether a Bazel server runs for ",
                wt_path,
                " (no md5 tool)"
            );
            return false;
        }
        for pid in pids
            .split(|&b| b == b' ' || b == b'\t' || b == b'\n')
            .filter(|s| !s.is_empty())
        {
            kill_send(pid);
        }
        for _ in 1..=20 {
            pids = self.server_pids(wt_path, output_root);
            if pids.is_empty() {
                // `stop_servers ... || { ... }` runs with errexit disabled and `return 0` follows `echo`.
                let _ = echo_ln!(
                    &self.argv0,
                    189,
                    "worktree: stopped the Bazel server(s) for ",
                    wt_path
                );
                return true;
            }
            let _ = Command::new("sleep")
                .arg("0.5")
                .stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .status();
        }
        let joined: Vec<u8> = pids
            .iter()
            .map(|&b| if b == b'\n' { b' ' } else { b })
            .collect();
        let _ = echo_err_ln!(
            &self.argv0,
            192,
            "worktree: Bazel server(s) for ",
            wt_path,
            " did not stop (pid ",
            &joined,
            ")"
        );
        false
    }

    fn scratch_mark_of(&self, path: &[u8]) -> Vec<u8> {
        let out = Command::new("git")
            .arg("-C")
            .arg(bytes_to_os(path))
            .args(["rev-parse", "--path-format=absolute", "--git-dir"])
            .stdin(Stdio::inherit())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .output();
        let Ok(out) = out else {
            return Vec::new();
        };
        if !out.status.success() {
            return Vec::new();
        }
        let gd = comsub_bytes(&out.stdout, &self.argv0, 218);
        let mark = bcat!(&gd, "/", SCRATCH_MARK);
        if bytes_to_path(&mark).is_file() {
            mark
        } else {
            Vec::new()
        }
    }

    fn scratch_keep_reason(&self, path: &[u8], mark: &[u8]) -> Vec<u8> {
        let name = basename_bytes(path);
        let gd = dirname_bytes(mark);

        let status_out = Command::new("git")
            .arg("--no-optional-locks")
            .arg("-C")
            .arg(bytes_to_os(path))
            .args(["status", "--porcelain"])
            .stdin(Stdio::inherit())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .output();
        if let Ok(o) = status_out {
            if !comsub_bytes(&o.stdout, &self.argv0, 232).is_empty() {
                return b"uncommitted or untracked files".to_vec();
            }
        }

        let out_root = self.output_root_of(path, &name);
        if !self.server_pids(path, &out_root).is_empty() {
            return b"a Bazel server is running for it (in use)".to_vec();
        }

        let made = fs::read(bytes_to_path(mark))
            .ok()
            .map(|d| comsub_bytes(head_1_slice(&d), &self.argv0, 238))
            .unwrap_or_default();

        // Capture stdout even on non-zero exit (e.g. unborn HEAD prints `HEAD` and exits 128).
        let head = Command::new("git")
            .arg("-C")
            .arg(bytes_to_os(path))
            .args(["rev-parse", "HEAD"])
            .stdin(Stdio::inherit())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .output()
            .ok()
            .map(|o| comsub_bytes(&o.stdout, &self.argv0, 239))
            .unwrap_or_default();

        if made.is_empty() {
            return bcat!(
                "no record of the commit it was made at; remove by hand: --remove ",
                &name
            );
        }
        if head != made {
            let made_12 = first_n_chars_bytes(&made, 12);
            let head_12 = first_n_chars_bytes(&head, 12);
            return bcat!(
                "HEAD moved from ",
                &made_12,
                " to ",
                &head_12,
                " since it was made (in use); remove by hand: --remove ",
                &name
            );
        }

        // Deliberate KEEP-SAFE divergence from worktree.sh: on an invalid WORKTREE_SCRATCH_TTL_HOURS,
        // bash arithmetic expansion fails inside $(...) leaving recent="" and deleting the
        // scratch worktree regardless of age; we keep the scratch worktree instead.
        let ttl_hours = match eval_scratch_ttl_hours(&self.scratch_ttl_hours, &self.argv0) {
            Ok(v) => v,
            Err(()) => {
                return bcat!(
                    "used in the last ",
                    &self.scratch_ttl_hours,
                    "h; keep it longer with --lock, or remove it now: --remove ",
                    &name
                );
            }
        };
        let ttl_mins = ttl_hours.saturating_mul(60);
        let find_out = Command::new("find")
            .arg(bytes_to_os(mark))
            .arg(bytes_to_os(&bcat!(&gd, "/index")))
            .arg(bytes_to_os(&bcat!(&gd, "/HEAD")))
            .arg(bytes_to_os(&bcat!(&gd, "/logs/HEAD")))
            .arg("-mmin")
            .arg(format!("-{ttl_mins}"))
            .stdin(Stdio::inherit())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .output();
        if let Ok(o) = find_out {
            if !comsub_bytes(&o.stdout, &self.argv0, 246).is_empty() {
                return bcat!(
                    "used in the last ",
                    &self.scratch_ttl_hours,
                    "h; keep it longer with --lock, or remove it now: --remove ",
                    &name
                );
            }
        }

        Vec::new()
    }

    fn remove_default_base(&self, wt_path: &[u8], errexit: bool) -> Result<(), i32> {
        let h = self.md5_of(wt_path);
        if h.is_empty() {
            return Ok(());
        }
        let base = bcat!(&self.bazel_root, "/", &h);
        if !bytes_to_path(&base).is_dir() {
            return Ok(());
        }
        if !self.server_pids(wt_path, b"").is_empty() {
            let r = echo_err_ln!(
                &self.argv0,
                266,
                "worktree: kept ",
                &base,
                ": a Bazel server is still running there (//tools/bazel-cache:gc takes it later)"
            );
            if r.is_err() && errexit {
                return r;
            }
            return Ok(());
        }
        let dnbh = bcat!(&base, "/DO_NOT_BUILD_HERE");
        if bytes_to_path(&dnbh).is_file() {
            let owner = fs::read(bytes_to_path(&dnbh))
                .ok()
                .map(|d| comsub_bytes(head_1_slice(&d), &self.argv0, 270))
                .unwrap_or_default();
            if !owner.is_empty() && real_path_bytes(&owner) != wt_path && owner != wt_path {
                let r = echo_err_ln!(
                    &self.argv0,
                    272,
                    "worktree: kept ",
                    &base,
                    ": it belongs to ",
                    &owner,
                    ", not ",
                    wt_path
                );
                if r.is_err() && errexit {
                    return r;
                }
                return Ok(());
            }
        }
        chmod_and_rm_rf(&base, errexit, &self.argv0, 277)?;
        let r = echo_ln!(
            &self.argv0,
            278,
            "worktree: pruned Bazel cache ",
            &base,
            " (the default output base for ",
            wt_path,
            ")"
        );
        if r.is_err() && errexit {
            return r;
        }
        Ok(())
    }

    fn remove_one(
        &mut self,
        br: &[u8],
        force: bool,
        delete_branch: bool,
        errexit: bool,
    ) -> Result<bool, i32> {
        let found = match self.find_worktree(br) {
            Ok(v) => v,
            Err(code) => {
                if errexit {
                    return Err(code);
                }
                None
            }
        };
        let Some(entry) = found else {
            let _ = echo_err_ln!(
                &self.argv0,
                287,
                "worktree: no worktree has branch ",
                br,
                " checked out, and no scratch worktree is called ",
                br,
                " (see --list)"
            );
            return Ok(false);
        };
        let dest = entry.path;
        let branch = entry.branch;
        let locked = entry.locked;

        if branch.is_empty() && delete_branch {
            let _ = echo_err_ln!(
                &self.argv0,
                292,
                "worktree: ",
                &dest,
                " is detached, so it has no branch to delete. Remove it with: bazel run //tools/worktree -- --remove ",
                br
            );
            return Ok(false);
        }
        if real_path_bytes(&dest) == self.repo {
            let _ = echo_err_ln!(
                &self.argv0,
                296,
                "worktree: ",
                br,
                " is checked out in the primary checkout, which is not removed"
            );
            return Ok(false);
        }
        if real_path_bytes(&dest) == self.here {
            let r = echo_err_ln!(
                &self.argv0,
                300,
                "worktree: ",
                &dest,
                " is the worktree this command is running from, so it is kept."
            );
            if r.is_err() && errexit {
                return Err(1);
            }
            let _ = echo_err_ln!(
                &self.argv0,
                301,
                "worktree: run it from the primary checkout instead: cd ",
                &self.repo,
                " && bazel run //tools/worktree -- --remove ",
                br
            );
            return Ok(false);
        }
        if !locked.is_empty() {
            let _ = echo_err_ln!(
                &self.argv0,
                307,
                "worktree: ",
                &dest,
                " is ",
                &locked,
                ", so it is kept. Unlock it first: bazel run //tools/worktree -- --unlock --on ",
                br
            );
            return Ok(false);
        }

        let unsaved = Command::new("git")
            .arg("-C")
            .arg(bytes_to_os(&dest))
            .args(["status", "--porcelain"])
            .stdin(Stdio::inherit())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .output()
            .ok()
            .map(|o| comsub_bytes(&o.stdout, &self.argv0, 314))
            .unwrap_or_default();

        if !unsaved.is_empty() && (!force || delete_branch) {
            let r = echo_err_ln!(
                &self.argv0,
                317,
                "worktree: ",
                &dest,
                " has uncommitted or untracked files, so it is kept:"
            );
            if r.is_err() && errexit {
                return Err(1);
            }
            for line in split_lf(&unsaved).into_iter().take(20) {
                err_ln!("  ", line);
            }
            if delete_branch {
                let _ = echo_err_ln!(
                    &self.argv0,
                    320,
                    "worktree: --delete-branch only removes a CLEAN worktree. Commit or discard them first."
                );
            } else {
                let _ = echo_err_ln!(
                    &self.argv0,
                    322,
                    "worktree: commit them, or remove it anyway with: bazel run //tools/worktree -- --remove ",
                    br,
                    " --force"
                );
            }
            return Ok(false);
        }

        if delete_branch && !self.is_landed(br) {
            let _ = echo_err_ln!(
                &self.argv0,
                328,
                "worktree: ",
                br,
                " is not landed on ",
                &self.base_ref,
                ", so it and its worktree are kept: ",
                &self.landed_says
            );
            return Ok(false);
        }

        let fallback_name = if branch.is_empty() {
            basename_bytes(&dest)
        } else {
            branch.clone()
        };
        let output_root = self.output_root_of(&dest, &fallback_name);
        if !self.stop_servers(&dest, &output_root) {
            let _ = echo_err_ln!(
                &self.argv0,
                336,
                "worktree: not removing ",
                &dest,
                " while its Bazel server is still running"
            );
            return Ok(false);
        }

        if !unsaved.is_empty() {
            let status = Command::new("git")
                .args(["worktree", "remove", "--force"])
                .arg(bytes_to_os(&dest))
                .stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .status();
            let ok = match status {
                Ok(s) => s.success(),
                Err(e) => {
                    let _ = handle_spawn_error(&e, b"git", &self.argv0, 340, false);
                    false
                }
            };
            if !ok {
                let _ = echo_err_ln!(&self.argv0, 341, "worktree: could not remove ", &dest);
                return Ok(false);
            }
            let r = echo_err_ln!(
                &self.argv0,
                344,
                "worktree: ",
                &dest,
                " had uncommitted or untracked files; they were removed with it"
            );
            if r.is_err() && errexit {
                return Err(1);
            }
        } else {
            let status = Command::new("git")
                .args(["worktree", "remove"])
                .arg(bytes_to_os(&dest))
                .stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .status();
            let ok = match status {
                Ok(s) => s.success(),
                Err(e) => {
                    let _ = handle_spawn_error(&e, b"git", &self.argv0, 345, false);
                    false
                }
            };
            if !ok {
                let _ = echo_err_ln!(&self.argv0, 346, "worktree: could not remove ", &dest);
                return Ok(false);
            }
        }

        let _ = Command::new("git")
            .args(["worktree", "prune"])
            .stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::null())
            .status();

        if fs::metadata(bytes_to_path(&dest)).is_ok() {
            let _ = echo_err_ln!(
                &self.argv0,
                351,
                "worktree: ",
                &dest,
                " is still on disk after removal"
            );
            return Ok(false);
        }

        if !output_root.is_empty() && bytes_to_path(&output_root).is_dir() {
            chmod_and_rm_rf(&output_root, errexit, &self.argv0, 356)?;
            let r = echo_ln!(
                &self.argv0,
                357,
                "worktree: pruned Bazel cache ",
                &output_root
            );
            if r.is_err() && errexit {
                return Err(1);
            }
        }

        self.remove_default_base(&dest, errexit)?;

        if branch.is_empty() {
            let r = echo_ln!(
                &self.argv0,
                363,
                "worktree: removed scratch worktree ",
                &dest
            );
            if r.is_err() && errexit {
                return Err(1);
            }
        } else if delete_branch {
            let status = Command::new("git")
                .args(["branch", "-D"])
                .arg(bytes_to_os(&branch))
                .stdin(Stdio::inherit())
                .stdout(Stdio::null())
                .stderr(Stdio::inherit())
                .status();
            let code = match status {
                Ok(s) if s.success() => 0,
                Ok(s) => status_to_exit_code(s),
                Err(e) => handle_spawn_error(&e, b"git", &self.argv0, 365, false),
            };
            if code != 0 && errexit {
                return Err(code);
            }
            let r = echo_ln!(
                &self.argv0,
                366,
                "worktree: removed ",
                &dest,
                " and deleted branch ",
                &branch,
                " (landed: ",
                &self.landed_says,
                ")"
            );
            if r.is_err() && errexit {
                return Err(1);
            }
        } else {
            let r = echo_ln!(
                &self.argv0,
                368,
                "worktree: removed ",
                &dest,
                " (branch ",
                &branch,
                " is kept; --prune deletes it once it has landed)"
            );
            if r.is_err() && errexit {
                return Err(1);
            }
        }

        Ok(true)
    }

    fn cmd_prune(&mut self, args: &[Vec<u8>]) -> i32 {
        let mut execute = false;
        for a in args {
            if a == b"--execute" {
                execute = true;
            } else {
                let _ = echo_err_ln!(&self.argv0, 394, "worktree: unknown --prune flag: ", a);
                return 2;
            }
        }

        let _ = Command::new("git")
            .args(["fetch", "origin", "main", "-q"])
            .stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::null())
            .status();

        if execute {
            if let Err(code) =
                echo_ln!(&self.argv0, 398, "worktree: prune against ", &self.base_ref)
            {
                return code;
            }
        } else if let Err(code) = echo_ln!(
            &self.argv0,
            398,
            "worktree: prune against ",
            &self.base_ref,
            " (DRY RUN)"
        ) {
            return code;
        }

        // Matches `done < <(worktrees)`: process substitution ignores non-zero exit.
        let entries = self.worktrees().unwrap_or_default();

        let mut n_rm = 0usize;
        let mut n_keep = 0usize;
        let mut failed = 0usize;
        let mut candidates: Vec<Vec<u8>> = Vec::new();
        let mut scratch_candidates: Vec<Vec<u8>> = Vec::new();

        for entry in entries {
            let path = entry.path;
            let br = entry.branch;
            let locked = entry.locked;
            let prunable = entry.prunable;

            let mut reason = Vec::new();
            let mut why = Vec::new();
            let mut scratch = false;

            if real_path_bytes(&path) == self.repo {
                reason = b"primary checkout".to_vec();
            } else if real_path_bytes(&path) == self.here {
                reason = b"this command is running from it".to_vec();
            } else if !locked.is_empty() {
                reason = locked;
            } else if prunable || !bytes_to_path(&path).is_dir() {
                reason =
                    b"directory is missing (git worktree prune clears the record; branch kept)"
                        .to_vec();
            } else if br.is_empty() {
                let mark = self.scratch_mark_of(&path);
                if mark.is_empty() {
                    reason = bcat!(
                        "detached HEAD, not a --detach scratch tree; remove by hand: --remove ",
                        basename_bytes(&path)
                    );
                } else {
                    reason = self.scratch_keep_reason(&path, &mark);
                    if reason.is_empty() {
                        why = bcat!(
                            "scratch tree, clean, unlocked, unmoved and unused for ",
                            &self.scratch_ttl_hours,
                            "h"
                        );
                        scratch = true;
                    }
                }
            } else {
                let dirty = Command::new("git")
                    .arg("-C")
                    .arg(bytes_to_os(&path))
                    .args(["status", "--porcelain"])
                    .stdin(Stdio::inherit())
                    .stdout(Stdio::piped())
                    .stderr(Stdio::null())
                    .output()
                    .ok()
                    .map(|o| !comsub_bytes(&o.stdout, &self.argv0, 421).is_empty())
                    .unwrap_or(false);
                if dirty {
                    reason = b"uncommitted or untracked files".to_vec();
                } else if !self
                    .server_pids(&path, &self.output_root_of(&path, &br))
                    .is_empty()
                {
                    reason = b"a Bazel server is running for it (in use)".to_vec();
                } else if git_is_ancestor(&bcat!("refs/heads/", &br), &self.base_ref) {
                    reason = bcat!(
                        "no commits of its own yet (new or unused); remove by hand: --remove ",
                        &br,
                        " --delete-branch"
                    );
                } else if !self.is_landed(&br) {
                    reason = bcat!("not landed: ", &self.landed_says);
                }
            }

            if !reason.is_empty() {
                let r = if br.is_empty() {
                    printf_ln!(
                        &self.argv0,
                        428,
                        "  KEEP    ",
                        &path,
                        "\n          ",
                        &reason
                    )
                } else {
                    printf_ln!(
                        &self.argv0,
                        428,
                        "  KEEP    ",
                        &path,
                        "  (",
                        &br,
                        ")\n          ",
                        &reason
                    )
                };
                if let Err(code) = r {
                    return code;
                }
                n_keep += 1;
            } else {
                if scratch {
                    if let Err(code) = printf_ln!(
                        &self.argv0,
                        432,
                        "  REMOVE  ",
                        &path,
                        "  (scratch)\n          ",
                        &why
                    ) {
                        return code;
                    }
                    scratch_candidates.push(path);
                } else {
                    if let Err(code) = printf_ln!(
                        &self.argv0,
                        435,
                        "  REMOVE  ",
                        &path,
                        "  (",
                        &br,
                        ")\n          ",
                        &self.landed_says
                    ) {
                        return code;
                    }
                    candidates.push(br);
                }
                n_rm += 1;
            }
        }

        if let Err(code) = echo_ln!(&self.argv0, 442) {
            return code;
        }
        if let Err(code) = echo_ln!(&self.argv0, 443, "worktree: branches with no worktree") {
            return code;
        }

        let checked_out_entries = match self.worktrees() {
            Ok(e) => e,
            Err(code) => return code,
        };
        let checked_out: Vec<Vec<u8>> = checked_out_entries
            .into_iter()
            .filter(|e| !e.branch.is_empty())
            .map(|e| e.branch)
            .collect();

        // Matches `done < <(git for-each-ref ...)`: process substitution ignores non-zero exit.
        let refs_out = Command::new("git")
            .args(["for-each-ref", "--format=%(refname:short)", "refs/heads"])
            .stdin(Stdio::inherit())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .output()
            .ok()
            .map(|o| o.stdout)
            .unwrap_or_default();

        let mut b_rm = 0usize;
        let mut b_keep = 0usize;
        let mut b_failed = 0usize;
        let mut branch_candidates: Vec<Vec<u8>> = Vec::new();
        let base_short = self
            .base_ref
            .strip_prefix(b"origin/")
            .unwrap_or(&self.base_ref)
            .to_vec();

        for br in split_lf(&refs_out) {
            if br.is_empty() {
                continue;
            }
            if checked_out.iter().any(|c| c.as_slice() == br) {
                continue;
            }
            let mut reason = Vec::new();
            if br == b"main" || br == base_short.as_slice() {
                reason = b"the base branch".to_vec();
            } else if git_is_ancestor(&bcat!("refs/heads/", br), &self.base_ref) {
                reason = bcat!(
                    "no commits of its own (new or unused); delete by hand: git branch -D ",
                    br
                );
            } else if !self.is_landed(br) {
                reason = bcat!("not landed: ", &self.landed_says);
            }

            if !reason.is_empty() {
                if let Err(code) = printf_ln!(
                    &self.argv0,
                    455,
                    "  KEEP    branch ",
                    br,
                    "\n          ",
                    &reason
                ) {
                    return code;
                }
                b_keep += 1;
            } else {
                if let Err(code) = printf_ln!(
                    &self.argv0,
                    458,
                    "  REMOVE  branch ",
                    br,
                    "\n          ",
                    &self.landed_says
                ) {
                    return code;
                }
                branch_candidates.push(br.to_vec());
                b_rm += 1;
            }
        }

        if let Err(code) = echo_ln!(&self.argv0, 464) {
            return code;
        }
        if !execute {
            if let Err(code) = echo_ln!(
                &self.argv0,
                466,
                "worktree: DRY RUN: would remove ",
                n_rm,
                " worktree(s) and their branches, keep ",
                n_keep,
                "."
            ) {
                return code;
            }
            if let Err(code) = echo_ln!(
                &self.argv0,
                467,
                "worktree: DRY RUN: would delete ",
                b_rm,
                " branch(es) with no worktree, keep ",
                b_keep,
                "."
            ) {
                return code;
            }
            if n_rm + b_rm != 0 {
                if let Err(code) = echo_ln!(
                    &self.argv0,
                    468,
                    "worktree: re-run with --prune --execute to remove them."
                ) {
                    return code;
                }
            }
            return 0;
        }

        for br in &candidates {
            // In bash: `remove_one "${br}" 0 1 || failed=$((failed + 1))` runs with errexit disabled.
            match self.remove_one(br, false, true, false) {
                Ok(true) => {}
                Ok(false) => failed += 1,
                Err(_) => failed += 1,
            }
        }

        for path in &scratch_candidates {
            let mark = self.scratch_mark_of(path);
            let reason = self.scratch_keep_reason(path, &mark);
            if !reason.is_empty() {
                if let Err(code) = echo_err_ln!(
                    &self.argv0,
                    481,
                    "worktree: ",
                    path,
                    " is kept after all: ",
                    &reason
                ) {
                    return code;
                }
                failed += 1;
                continue;
            }
            match self.remove_one(path, false, false, false) {
                Ok(true) => {}
                Ok(false) => failed += 1,
                Err(_) => failed += 1,
            }
        }

        for br in &branch_candidates {
            // Deliberate KEEP-SAFE divergence from worktree.sh: awk -v b="$br" '$2 == b' compares
            // numeric-looking branch names numerically and expands backslash escapes;
            // use exact byte comparison.
            let is_checked_out = self
                .worktrees()
                .map(|wts| wts.iter().any(|e| &e.branch == br))
                .unwrap_or(false);
            if is_checked_out {
                if let Err(code) = echo_err_ln!(
                    &self.argv0,
                    491,
                    "worktree: ",
                    br,
                    " is now checked out in a worktree, so it is kept"
                ) {
                    return code;
                }
                b_failed += 1;
            } else if !self.is_landed(br) {
                if let Err(code) = echo_err_ln!(
                    &self.argv0,
                    494,
                    "worktree: ",
                    br,
                    " is no longer landed, so it is kept: ",
                    &self.landed_says
                ) {
                    return code;
                }
                b_failed += 1;
            } else {
                let del_ok = Command::new("git")
                    .args(["branch", "-D"])
                    .arg(bytes_to_os(br))
                    .stdin(Stdio::inherit())
                    .stdout(Stdio::null())
                    .stderr(Stdio::inherit())
                    .status()
                    .map(|s| s.success())
                    .unwrap_or(false);
                if del_ok {
                    if let Err(code) = echo_ln!(
                        &self.argv0,
                        497,
                        "worktree: deleted branch ",
                        br,
                        " (landed: ",
                        &self.landed_says,
                        ")"
                    ) {
                        return code;
                    }
                } else {
                    if let Err(code) =
                        echo_err_ln!(&self.argv0, 499, "worktree: could not delete branch ", br)
                    {
                        return code;
                    }
                    b_failed += 1;
                }
            }
        }

        let removed_wt = n_rm - failed;
        let refused_wt = if failed == 0 {
            Vec::new()
        } else {
            bcat!(", ", failed, " refused on re-check")
        };
        if let Err(code) = echo_ln!(
            &self.argv0,
            503,
            "worktree: removed ",
            removed_wt,
            " worktree(s), kept ",
            n_keep,
            &refused_wt,
            "."
        ) {
            return code;
        }

        let deleted_br = b_rm - b_failed;
        let refused_br = if b_failed == 0 {
            Vec::new()
        } else {
            bcat!(", ", b_failed, " refused on re-check")
        };
        if let Err(code) = echo_ln!(
            &self.argv0,
            504,
            "worktree: deleted ",
            deleted_br,
            " branch(es) with no worktree, kept ",
            b_keep,
            &refused_br,
            "."
        ) {
            return code;
        }

        if failed == 0 && b_failed == 0 {
            0
        } else {
            1
        }
    }

    fn lock_cmd(&self, op: &[u8], args: &[Vec<u8>]) -> i32 {
        let mut target = Vec::new();
        let mut reason = Vec::new();
        let mut i = 0;
        while i < args.len() {
            let arg = &args[i];
            if arg == b"--on" {
                let val = args.get(i + 1).map(|v| v.as_slice()).unwrap_or(b"");
                if val.is_empty() {
                    err_ln!(&self.argv0, ": line 517: 2: --on needs a <branch|name>");
                    return 1;
                }
                target = val.to_vec();
                i += 2;
                continue;
            } else if arg.starts_with(b"-") {
                let _ = echo_err_ln!(&self.argv0, 518, "worktree: unknown --", op, " flag: ", arg);
                return 2;
            } else {
                if !reason.is_empty() {
                    reason.push(b' ');
                }
                reason.extend_from_slice(arg);
            }
            i += 1;
        }

        let (dest, locked) = if !target.is_empty() {
            let entry = match self.find_worktree(&target) {
                Ok(Some(e)) => e,
                Ok(None) => {
                    let _ = echo_err_ln!(
                        &self.argv0,
                        525,
                        "worktree: no worktree has branch ",
                        &target,
                        " checked out, and no scratch worktree is called ",
                        &target,
                        " (see --list)"
                    );
                    return 1;
                }
                Err(code) => return code,
            };
            (entry.path, entry.locked)
        } else {
            let entries = match self.worktrees() {
                Ok(e) => e,
                Err(code) => return code,
            };
            // Deliberate KEEP-SAFE divergence from worktree.sh: awk -v p="$HERE" '$1 == p'
            // expands backslash escapes in HERE; use exact byte comparison.
            let locked = entries
                .into_iter()
                .find(|e| e.path == self.here)
                .map(|e| e.locked)
                .unwrap_or_default();
            (self.here.clone(), locked)
        };

        if real_path_bytes(&dest) == self.repo {
            let _ = echo_err_ln!(
                &self.argv0,
                532,
                "worktree: ",
                &dest,
                " is the primary checkout, which no pruner removes; there is nothing to ",
                op,
                "."
            );
            let _ = echo_err_ln!(
                &self.argv0,
                533,
                "worktree: run it from inside the worktree to ",
                op,
                ", or name it: bazel run //tools/worktree -- --",
                op,
                " --on <branch|name>"
            );
            return 1;
        }

        if op == b"lock" {
            if !locked.is_empty() {
                if let Err(code) = echo_ln!(
                    &self.argv0,
                    538,
                    "worktree: ",
                    &dest,
                    " is already ",
                    &locked
                ) {
                    return code;
                }
                return 0;
            }
            if reason.is_empty() {
                let now_secs = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .map(|d| d.as_secs())
                    .unwrap_or(0);
                let ts = format_utc_hm(now_secs);
                reason = bcat!(
                    "kept by ",
                    &self.user,
                    " since ",
                    ts,
                    " (//tools/worktree --lock)"
                );
            }
            let status = Command::new("git")
                .args(["worktree", "lock", "--reason"])
                .arg(bytes_to_os(&reason))
                .arg(bytes_to_os(&dest))
                .stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .status();
            match status {
                Ok(s) if s.success() => {}
                Ok(s) => return status_to_exit_code(s),
                Err(e) => return handle_spawn_error(&e, b"git", &self.argv0, 542, false),
            }
            if let Err(code) = echo_ln!(&self.argv0, 543, "worktree: locked ", &dest, ": ", &reason)
            {
                return code;
            }
            let on_suffix = if target.is_empty() {
                Vec::new()
            } else {
                bcat!(" --on ", &target)
            };
            if let Err(code) = echo_ln!(
                &self.argv0,
                544,
                "worktree: no pruner removes it now. Let it go with: bazel run //tools/worktree -- --unlock",
                &on_suffix
            ) {
                return code;
            }
        } else {
            if locked.is_empty() {
                if let Err(code) = echo_ln!(&self.argv0, 547, "worktree: ", &dest, " is not locked")
                {
                    return code;
                }
                return 0;
            }
            let status = Command::new("git")
                .args(["worktree", "unlock"])
                .arg(bytes_to_os(&dest))
                .stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .status();
            match status {
                Ok(s) if s.success() => {}
                Ok(s) => return status_to_exit_code(s),
                Err(e) => return handle_spawn_error(&e, b"git", &self.argv0, 550, false),
            }
            if let Err(code) = echo_ln!(
                &self.argv0,
                551,
                "worktree: unlocked ",
                &dest,
                "; --prune may remove it once it is clean and landed"
            ) {
                return code;
            }
        }
        0
    }

    fn setup_tree(&self, dest: &[u8], output_root: &[u8]) -> Result<(), i32> {
        let rc_path = bcat!(dest, "/user.bazelrc");
        let rc_initial = bcat!(
            "# Auto-generated by //tools/worktree (issue #455). Gives this worktree its own\n\
             # Bazel server + analysis cache so it doesn't contend with the main checkout or\n\
             # sibling worktrees. Safe to edit or delete. Not committed (user.bazelrc is\n\
             # gitignored).\n\
             startup --output_user_root=",
            output_root,
            "\n"
        );
        write_file_redirect(&rc_path, &rc_initial, false, &self.argv0, 563)?;

        mkdir_p(output_root, &self.argv0, 574)?;
        let marker_path = bcat!(output_root, "/", MARKER);
        let marker_data = bcat!(real_path_bytes(dest), "\n");
        write_file_redirect(&marker_path, &marker_data, false, &self.argv0, 575)?;

        let primary_rc = bcat!(&self.repo, "/user.bazelrc");
        if bytes_to_path(&primary_rc).is_file() {
            // In bash (`{ awk ...; grep ... || true; } >> "${dest}/user.bazelrc"` inside `if`
            // inside `setup_tree()`), the append redirect is opened BEFORE running `awk`, and
            // redirect errors on that compound block report line 558 (`setup_tree() {`) in both
            // bash 3.2 and bash 5.2.
            let append_file = match OpenOptions::new()
                .create(true)
                .write(true)
                .append(true)
                .open(bytes_to_path(&rc_path))
                .and_then(ensure_file_above_stdio)
            {
                Ok(f) => f,
                Err(e) => {
                    err_ln!(
                        &self.argv0,
                        ": line 558: ",
                        &rc_path,
                        ": ",
                        os_error_str(&e)
                    );
                    return Err(1);
                }
            };
            let grep_file = match append_file.try_clone().and_then(ensure_file_above_stdio) {
                Ok(f) => f,
                Err(e) => {
                    err_ln!(
                        &self.argv0,
                        ": line 558: ",
                        &rc_path,
                        ": ",
                        os_error_str(&e)
                    );
                    return Err(1);
                }
            };

            const AWK_PROG: &str = "/^# >>> build cache \\(managed by tools\\/remote:setup\\)/{inblk=1}\n           inblk{print}\n           /^# <<< build cache \\(managed by tools\\/remote:setup\\)/{inblk=0}";
            let awk_status = Command::new("awk")
                .arg(AWK_PROG)
                .arg(bytes_to_os(&primary_rc))
                .stdin(Stdio::inherit())
                .stdout(Stdio::from(append_file))
                .stderr(Stdio::inherit())
                .status();
            match awk_status {
                Ok(s) if s.success() => {}
                Ok(s) => return Err(status_to_exit_code(s)),
                Err(e) => return Err(handle_spawn_error(&e, b"awk", &self.argv0, 585, false)),
            }

            let _ = Command::new("grep")
                .args(["-E", "^common:remote --(remote_header|bes_header)="])
                .arg(bytes_to_os(&primary_rc))
                .stdin(Stdio::inherit())
                .stdout(Stdio::from(grep_file))
                .stderr(Stdio::inherit())
                .status();
        }
        Ok(())
    }
}

/// Parse a PID argument matching bash's `legal_number` in `builtins/kill.def`:
/// leading ASCII whitespace (`isspace`, skipped by `strtoimax`) is allowed;
/// trailing space `' '` and tab `'\t'` (skipped by bash's `whitespace(*ep)`) are allowed,
/// while trailing `\r`, `\v`, `\f`, `\n` are rejected; optional `+`, base-10 digits only,
/// fitting in `i32` (`pid_t`) and `> 0` (KEEP-SAFE: never signal `0` or negative process groups).
fn parse_pid(pid: &[u8]) -> Option<i32> {
    let mut start = 0;
    let mut end = pid.len();
    while start < end && pid[start].is_ascii_whitespace() {
        start += 1;
    }
    while end > start && (pid[end - 1] == b' ' || pid[end - 1] == b'\t') {
        end -= 1;
    }
    let trimmed = &pid[start..end];
    let digits = trimmed.strip_prefix(b"+").unwrap_or(trimmed);
    if digits.is_empty() || !digits.iter().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let s = std::str::from_utf8(digits).ok()?;
    let val = s.parse::<i64>().ok()?;
    let p = i32::try_from(val).ok()?;
    if p > 0 {
        Some(p)
    } else {
        None
    }
}

fn kill_check(pid: &[u8]) -> bool {
    if let Some(p) = parse_pid(pid) {
        unsafe { kill(p, 0) == 0 }
    } else {
        false
    }
}

fn kill_send(pid: &[u8]) {
    if let Some(p) = parse_pid(pid) {
        unsafe {
            let _ = kill(p, 15);
        }
    }
}

fn git_show_ref_quiet(refname: &[u8]) -> bool {
    Command::new("git")
        .args(["show-ref", "--verify", "--quiet"])
        .arg(bytes_to_os(refname))
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn git_is_ancestor(anc: &[u8], desc: &[u8]) -> bool {
    Command::new("git")
        .args(["merge-base", "--is-ancestor"])
        .arg(bytes_to_os(anc))
        .arg(bytes_to_os(desc))
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn resolve_user(argv0: &[u8], line_no: usize) -> Result<Vec<u8>, i32> {
    if let Some(u) = env::var_os("USER") {
        let b = u.into_vec();
        if !b.is_empty() {
            return Ok(b);
        }
    }
    let out = Command::new("id")
        .arg("-un")
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .output()
        .map_err(|e| handle_spawn_error(&e, b"id", argv0, line_no, false))?;
    if !out.status.success() {
        return Err(status_to_exit_code(out.status));
    }
    Ok(comsub_bytes(&out.stdout, argv0, line_no))
}

pub fn run(args: &[String]) -> i32 {
    let os_args: Vec<OsString> = args.iter().map(OsString::from).collect();
    run_os(&os_args)
}

pub fn run_os(args: &[OsString]) -> i32 {
    BASH_INFO_CACHE.store(0, AtomicOrdering::Relaxed);
    unsafe {
        setlocale(LC_ALL, b"\0".as_ptr() as *const c_char);
    }

    let raw_args: Vec<Vec<u8>> = args.iter().map(|a| a.as_bytes().to_vec()).collect();
    let argv0 = raw_args
        .first()
        .cloned()
        .unwrap_or_else(|| b"worktree".to_vec());
    let rest_args: &[Vec<u8>] = if raw_args.len() > 1 {
        &raw_args[1..]
    } else {
        &[]
    };

    let start_pwd = env::current_dir()
        .map(|p| p.into_os_string().into_vec())
        .unwrap_or_default();
    if env::var_os("PWD").is_none() && !start_pwd.is_empty() {
        env::set_var("PWD", bytes_to_os(&start_pwd));
    }

    let here_raw = match env::var_os("BUILD_WORKSPACE_DIRECTORY") {
        Some(val) if !val.is_empty() => val.into_vec(),
        _ => Command::new("git")
            .args(["rev-parse", "--show-toplevel"])
            .stdin(Stdio::inherit())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .output()
            .ok()
            .map(|o| comsub_bytes(&o.stdout, &argv0, 67))
            .unwrap_or_default(),
    };

    if here_raw.is_empty() {
        let _ = echo_err_ln!(
            &argv0,
            69,
            "worktree: not inside a git repo and BUILD_WORKSPACE_DIRECTORY is unset"
        );
        return 1;
    }

    let here = match cd_and_pwd_p(&here_raw, &argv0, 72) {
        Ok(p) => p,
        Err(code) => return code,
    };

    let common_out = match Command::new("git")
        .arg("-C")
        .arg(bytes_to_os(&here))
        .args(["rev-parse", "--path-format=absolute", "--git-common-dir"])
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .output()
    {
        Ok(o) if o.status.success() => comsub_bytes(&o.stdout, &argv0, 73),
        Ok(o) => return status_to_exit_code(o.status),
        Err(e) => return handle_spawn_error(&e, b"git", &argv0, 73, false),
    };

    let repo = if basename_bytes(&common_out) == b".git" {
        let parent = dirname_bytes(&common_out);
        match cd_and_pwd_p(&parent, &argv0, 75) {
            Ok(p) => p,
            Err(code) => return code,
        }
    } else {
        here.clone()
    };

    let old_pwd = env::var_os("PWD").unwrap_or_else(|| OsString::from_vec(start_pwd.clone()));
    if let Err(e) = env::set_current_dir(bytes_to_path(&repo)) {
        err_ln!(&argv0, ": line 79: cd: ", &repo, ": ", os_error_str(&e));
        return 1;
    }
    env::set_var("OLDPWD", old_pwd);
    env::set_var("PWD", bytes_to_os(&repo));

    let repo_name = basename_bytes(&repo);
    let wt_root = match env::var_os("WORKTREE_ROOT") {
        Some(v) if !v.is_empty() => v.into_vec(),
        _ => bcat!(dirname_bytes(&repo), "/", &repo_name, "-worktrees"),
    };
    let Some(home_os) = env::var_os("HOME") else {
        err_ln!(&argv0, ": line 83: HOME: unbound variable");
        return 1;
    };
    let home = home_os.into_vec();
    let cache_root = bcat!(&home, "/.cache/bazel/worktrees");
    let user = match resolve_user(&argv0, 84) {
        Ok(u) => u,
        Err(code) => return code,
    };
    let macos_bazel_root = bcat!(&home, "/Library/Caches/bazel/_bazel_", &user);
    let bazel_root = if bytes_to_path(&macos_bazel_root).is_dir() {
        macos_bazel_root
    } else {
        let user2 = match resolve_user(&argv0, 85) {
            Ok(u) => u,
            Err(code) => return code,
        };
        bcat!(&home, "/.cache/bazel/_bazel_", &user2)
    };
    let scratch_ttl_hours = match env::var_os("WORKTREE_SCRATCH_TTL_HOURS") {
        Some(v) if !v.is_empty() => v.into_vec(),
        _ => b"24".to_vec(),
    };

    let base_ref = if git_show_ref_quiet(b"refs/remotes/origin/main") {
        b"origin/main".to_vec()
    } else {
        b"main".to_vec()
    };

    let mut ctx = Context {
        argv0,
        start_pwd,
        here,
        repo,
        repo_name,
        wt_root,
        cache_root,
        bazel_root,
        user,
        scratch_ttl_hours,
        base_ref,
        landed_says: Vec::new(),
    };

    let first: &[u8] = rest_args.first().map(|v| v.as_slice()).unwrap_or(b"");
    match first {
        b"" | b"-h" | b"--help" => {
            return write_usage_sed(&ctx.argv0, 53, extract_usage(WORKTREE_SH).as_bytes());
        }
        b"--list" => {
            let status = Command::new("git")
                .args(["worktree", "list"])
                .stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .status();
            return match status {
                Ok(s) if s.success() => 0,
                Ok(s) => status_to_exit_code(s),
                Err(e) => handle_spawn_error(&e, b"git", &ctx.argv0, 599, false),
            };
        }
        b"--prune" => {
            return ctx.cmd_prune(&rest_args[1..]);
        }
        b"--lock" | b"--unlock" => {
            let op = &first[2..];
            return ctx.lock_cmd(op, &rest_args[1..]);
        }
        b"--remove" => {
            let br: &[u8] = rest_args.get(1).map(|v| v.as_slice()).unwrap_or(b"");
            if br.is_empty() {
                err_ln!(
                    &ctx.argv0,
                    ": line 613: 2: --remove needs a <branch> or a scratch <name>"
                );
                return 1;
            }
            let mut force = false;
            let mut delete_branch = false;
            for a in &rest_args[2..] {
                match a.as_slice() {
                    b"--force" => force = true,
                    b"--delete-branch" => delete_branch = true,
                    _ => {
                        let _ =
                            echo_err_ln!(&ctx.argv0, 619, "worktree: unknown --remove flag: ", a);
                        return 2;
                    }
                }
            }
            if delete_branch {
                let _ = Command::new("git")
                    .args(["fetch", "origin", "main", "-q"])
                    .stdin(Stdio::inherit())
                    .stdout(Stdio::inherit())
                    .stderr(Stdio::null())
                    .status();
            }
            return match ctx.remove_one(br, force, delete_branch, true) {
                Ok(true) => 0,
                Ok(false) => 1,
                Err(code) => code,
            };
        }
        b"--detach" => {
            let r_ref: &[u8] = rest_args.get(1).map(|v| v.as_slice()).unwrap_or(b"");
            let name: &[u8] = rest_args.get(2).map(|v| v.as_slice()).unwrap_or(b"");
            if r_ref.is_empty() || name.is_empty() || rest_args.len() > 3 {
                let _ = echo_err_ln!(
                    &ctx.argv0,
                    631,
                    "worktree: usage: bazel run //tools/worktree -- --detach <ref> <name>"
                );
                return 2;
            }
            let commit_spec = bcat!(r_ref, "^{commit}");
            let commit_out = Command::new("git")
                .args(["rev-parse", "--verify", "--quiet"])
                .arg(bytes_to_os(&commit_spec))
                .stdin(Stdio::inherit())
                .stdout(Stdio::piped())
                .stderr(Stdio::inherit())
                .output();
            let commit = match commit_out {
                Ok(o) if o.status.success() => comsub_bytes(&o.stdout, &ctx.argv0, 634),
                _ => {
                    let _ = echo_err_ln!(
                        &ctx.argv0,
                        635,
                        "worktree: ",
                        r_ref,
                        " is not a commit here. Fetch it first (git fetch origin <ref>), or name a sha or origin/<branch>."
                    );
                    return 1;
                }
            };
            let slug_name = match ctx.slug_tr(name, 638) {
                Ok(s) => s,
                Err(code) => return code,
            };
            let dest = bcat!(&ctx.wt_root, "/", &slug_name);
            if fs::metadata(bytes_to_path(&dest)).is_ok() {
                let _ = echo_err_ln!(
                    &ctx.argv0,
                    640,
                    "worktree: destination already exists: ",
                    &dest,
                    ". Pick another name, or remove it: bazel run //tools/worktree -- --remove ",
                    name
                );
                return 1;
            }
            if let Err(code) = mkdir_p(&ctx.wt_root, &ctx.argv0, 643) {
                return code;
            }
            let add_status = Command::new("git")
                .args(["worktree", "add", "--detach"])
                .arg(bytes_to_os(&dest))
                .arg(bytes_to_os(&commit))
                .stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .status();
            match add_status {
                Ok(s) if s.success() => {}
                Ok(s) => return status_to_exit_code(s),
                Err(e) => return handle_spawn_error(&e, b"git", &ctx.argv0, 644, false),
            }
            // In bash: `printf '%s\n' "${COMMIT}" >"$(git -C "${DEST}" rev-parse --path-format=absolute --git-dir)/${SCRATCH_MARK}"`
            // A failed command substitution inside the redirect target does not abort immediately;
            // it evaluates to its stdout (empty on failure), so bash tries to open `/vitruvian-scratch`.
            let gd_out = Command::new("git")
                .arg("-C")
                .arg(bytes_to_os(&dest))
                .args(["rev-parse", "--path-format=absolute", "--git-dir"])
                .stdin(Stdio::inherit())
                .stdout(Stdio::piped())
                .stderr(Stdio::inherit())
                .output()
                .map(|o| comsub_bytes(&o.stdout, &ctx.argv0, 647))
                .unwrap_or_default();
            let mark_file = bcat!(&gd_out, "/", SCRATCH_MARK);
            let mark_data = bcat!(&commit, "\n");
            match OpenOptions::new()
                .create(true)
                .write(true)
                .truncate(true)
                .open(bytes_to_path(&mark_file))
            {
                Ok(mut f) => {
                    if let Err(e) = f.write_all(&mark_data) {
                        err_ln!(
                            &ctx.argv0,
                            ": line 647: printf: write error: ",
                            os_error_str(&e)
                        );
                        return 1;
                    }
                }
                Err(e) => {
                    // In bash 3.2, `redirection_error` re-expands the redirect word to format the error message.
                    let err_path = if bash_is_v3() {
                        let gd2 = Command::new("git")
                            .arg("-C")
                            .arg(bytes_to_os(&dest))
                            .args(["rev-parse", "--path-format=absolute", "--git-dir"])
                            .stdin(Stdio::inherit())
                            .stdout(Stdio::piped())
                            .stderr(Stdio::inherit())
                            .output()
                            .map(|o| comsub_bytes(&o.stdout, &ctx.argv0, 647))
                            .unwrap_or_default();
                        bcat!(&gd2, "/", SCRATCH_MARK)
                    } else {
                        mark_file
                    };
                    err_ln!(
                        &ctx.argv0,
                        ": line 647: ",
                        &err_path,
                        ": ",
                        os_error_str(&e)
                    );
                    return 1;
                }
            }
            let slug_name2 = match ctx.slug_tr(name, 648) {
                Ok(s) => s,
                Err(code) => return code,
            };
            let output_root = bcat!(&ctx.cache_root, "/", &ctx.repo_name, "-", &slug_name2);
            if let Err(code) = ctx.setup_tree(&dest, &output_root) {
                return code;
            }
            // In bash, `$(git rev-parse --short "${COMMIT}")` is inside a heredoc, so a non-zero exit is ignored.
            let short_commit = Command::new("git")
                .args(["rev-parse", "--short"])
                .arg(bytes_to_os(&commit))
                .stdin(Stdio::inherit())
                .stdout(Stdio::piped())
                .stderr(Stdio::inherit())
                .output()
                .map(|o| comsub_bytes(&o.stdout, &ctx.argv0, 655))
                .unwrap_or_default();
            let done_block = bcat!(
                "\n  ✔ scratch worktree ready (detached, no branch)\n    \
                 name:               ",
                name,
                "\n    \
                 path:               ",
                &dest,
                "\n    \
                 at:                 ",
                r_ref,
                " (",
                &short_commit,
                ")\n    \
                 bazel output root:  ",
                &output_root,
                "\n                        \
                 (pinned in ",
                &dest,
                "/user.bazelrc)\n\n  \
                 --prune removes it once it is clean, unlocked, still at this commit, and unused for ",
                &ctx.scratch_ttl_hours,
                "h.\n  \
                 Keep it longer:  bazel run //tools/worktree -- --lock --on ",
                name,
                "\n  \
                 Remove it now:   bazel run //tools/worktree -- --remove ",
                name,
                "\n\n  \
                 next:\n    \
                 cd ",
                &dest,
                "\n"
            );
            return write_heredoc_cat(&ctx.argv0, 650, &done_block);
        }
        s if s.starts_with(b"-") => {
            let _ = echo_err_ln!(
                &ctx.argv0,
                669,
                "worktree: unknown flag: ",
                s,
                " (see --help)"
            );
            return 2;
        }
        _ => {}
    }

    let branch = &rest_args[0];
    let mut base = rest_args.get(1).cloned().unwrap_or_default();
    let slug_branch = match ctx.slug_tr(branch, 676) {
        Ok(s) => s,
        Err(code) => return code,
    };
    let dest = bcat!(&ctx.wt_root, "/", &slug_branch);

    if fs::metadata(bytes_to_path(&dest)).is_ok() {
        let _ = echo_err_ln!(
            &ctx.argv0,
            679,
            "worktree: destination already exists: ",
            &dest
        );
        return 1;
    }

    if base.is_empty() {
        if git_show_ref_quiet(b"refs/remotes/origin/main") {
            base = b"origin/main".to_vec();
        } else {
            base = b"HEAD".to_vec();
        }
    }

    if let Err(code) = mkdir_p(&ctx.wt_root, &ctx.argv0, 692) {
        return code;
    }

    let (add_status, add_line) = if git_show_ref_quiet(&bcat!("refs/heads/", branch)) {
        (
            Command::new("git")
                .args(["worktree", "add"])
                .arg(bytes_to_os(&dest))
                .arg(bytes_to_os(branch))
                .stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .status(),
            697usize,
        )
    } else {
        (
            Command::new("git")
                .args(["worktree", "add", "-b"])
                .arg(bytes_to_os(branch))
                .arg(bytes_to_os(&dest))
                .arg(bytes_to_os(&base))
                .stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .status(),
            699usize,
        )
    };
    match add_status {
        Ok(s) if s.success() => {}
        Ok(s) => return status_to_exit_code(s),
        Err(e) => return handle_spawn_error(&e, b"git", &ctx.argv0, add_line, false),
    }

    let slug_branch2 = match ctx.slug_tr(branch, 702) {
        Ok(s) => s,
        Err(code) => return code,
    };
    let output_root = bcat!(&ctx.cache_root, "/", &ctx.repo_name, "-", &slug_branch2);
    if let Err(code) = ctx.setup_tree(&dest, &output_root) {
        return code;
    }

    let done_block = bcat!(
        "\n  ✔ worktree ready\n    \
         branch:             ",
        branch,
        "\n    \
         path:               ",
        &dest,
        "\n    \
         base:               ",
        &base,
        "\n    \
         bazel output root:  ",
        &output_root,
        "\n                        \
         (pinned in ",
        &dest,
        "/user.bazelrc)\n\n  \
         next:\n    \
         cd ",
        &dest,
        "\n"
    );
    write_heredoc_cat(&ctx.argv0, 705, &done_block)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn test_slug() {
        assert_eq!(slug("fix/one"), "fix-one");
        assert_eq!(slug("feat/a/b/c"), "feat-a-b-c");
        assert_eq!(slug("plain"), "plain");
        assert_eq!(slug(""), "");
    }

    #[test]
    fn test_parse_pid() {
        assert_eq!(parse_pid(b"123"), Some(123));
        assert_eq!(parse_pid(b" 123"), Some(123));
        assert_eq!(parse_pid(b"\t\n\r123"), Some(123));
        assert_eq!(parse_pid(b"123 "), Some(123));
        assert_eq!(parse_pid(b"123\t"), Some(123));
        assert_eq!(parse_pid(b"+123"), Some(123));
        assert_eq!(parse_pid(b" +00123 \t"), Some(123));
        assert_eq!(parse_pid(b"123\r"), None);
        assert_eq!(parse_pid(b"123\x0b"), None);
        assert_eq!(parse_pid(b"123\x0c"), None);
        assert_eq!(parse_pid(b"123\n456"), None);
        assert_eq!(parse_pid(b"0x1f"), None);
        assert_eq!(parse_pid(b"java"), None);
        assert_eq!(parse_pid(b""), None);
        assert_eq!(parse_pid(b"   "), None);
        assert_eq!(parse_pid(b"0"), None);
        assert_eq!(parse_pid(b"-1"), None);
    }

    #[test]
    fn test_md5_rfc1321_vectors() {
        assert_eq!(md5_hex(b""), "d41d8cd98f00b204e9800998ecf8427e");
        assert_eq!(md5_hex(b"a"), "0cc175b9c0f1b6a831c399e269772661");
        assert_eq!(md5_hex(b"abc"), "900150983cd24fb0d6963f7d28e17f72");
        assert_eq!(
            md5_hex(b"message digest"),
            "f96b697d7cb7938d525a2f31aaf161d0"
        );
        assert_eq!(
            md5_hex(b"abcdefghijklmnopqrstuvwxyz"),
            "c3fcd3d76192e4007dfb496cca67e13b"
        );
        assert_eq!(
            md5_hex(b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"),
            "d174ab98d277d9f5a5611c2c9f419d9f"
        );
    }

    #[test]
    fn test_format_utc_hm() {
        assert_eq!(format_utc_hm(0), "1970-01-01T00:00Z");
        assert_eq!(format_utc_hm(1761356820), "2025-10-25T01:47Z");
        assert_eq!(format_utc_hm(1709164800), "2024-02-29T00:00Z"); // leap year day
    }

    #[test]
    fn test_strip_ansi_and_clean_landed() {
        assert_eq!(
            clean_landed_output(
                "\x1b[32m✓\x1b[0m fix/one is landed: content check.\nsecond line\n"
            ),
            "fix/one is landed: content check."
        );
        assert_eq!(
            clean_landed_output(
                "\x1b[31m✗\x1b[0m fix/two is NOT landed: 1 commit(s)\n   more details\n"
            ),
            "fix/two is NOT landed: 1 commit(s)"
        );
        assert_eq!(
            clean_landed_output("\x1b[36m→\x1b[0m info line"),
            "info line"
        );
    }

    #[test]
    fn test_parse_worktrees_porcelain() {
        let sample = "\
worktree /path/to/repo
HEAD 1111111111111111111111111111111111111111
branch refs/heads/main

worktree /path/to/wt/fix-one
HEAD 2222222222222222222222222222222222222222
branch refs/heads/fix/one
locked agent wren reviewing

worktree /path/to/wt/scratch
HEAD 3333333333333333333333333333333333333333
detached
locked
prunable gitdir file points to non-existent location
";
        let entries = parse_worktrees_porcelain(sample);
        assert_eq!(
            entries,
            vec![
                WorktreeEntry {
                    path: "/path/to/repo".to_string(),
                    branch: "main".to_string(),
                    locked: String::new(),
                    prunable: false,
                },
                WorktreeEntry {
                    path: "/path/to/wt/fix-one".to_string(),
                    branch: "fix/one".to_string(),
                    locked: "locked: agent wren reviewing".to_string(),
                    prunable: false,
                },
                WorktreeEntry {
                    path: "/path/to/wt/scratch".to_string(),
                    branch: String::new(),
                    locked: "locked".to_string(),
                    prunable: true,
                },
            ]
        );
    }

    #[test]
    fn test_resolve_output_root() {
        let cache = "/home/u/.cache/bazel/worktrees";
        assert_eq!(
            resolve_output_root(None, cache, "repo", "fix/one"),
            "/home/u/.cache/bazel/worktrees/repo-fix-one"
        );
        assert_eq!(
            resolve_output_root(
                Some("startup --output_user_root=/home/u/.cache/bazel/worktrees/custom\n"),
                cache,
                "repo",
                "fix/one"
            ),
            "/home/u/.cache/bazel/worktrees/custom"
        );
        // Preserves \r on CRLF lines just like sed/tail
        assert_eq!(
            resolve_output_root(
                Some("startup --output_user_root=/home/u/.cache/bazel/worktrees/custom\r\n"),
                cache,
                "repo",
                "fix/one"
            ),
            "/home/u/.cache/bazel/worktrees/custom\r"
        );
        // Rejects path outside cache_root or containing ..
        assert_eq!(
            resolve_output_root(
                Some("startup --output_user_root=/tmp/evil\n"),
                cache,
                "repo",
                "fix/one"
            ),
            ""
        );
        assert_eq!(
            resolve_output_root(
                Some("startup --output_user_root=/home/u/.cache/bazel/worktrees/../evil\n"),
                cache,
                "repo",
                "fix/one"
            ),
            ""
        );
        assert_eq!(
            resolve_output_root(
                Some("startup --output_user_root=/home/u/.cache/bazel/worktrees/\n"),
                cache,
                "repo",
                "fix/one"
            ),
            ""
        );
    }

    #[test]
    fn test_extract_primary_bazelrc_cache_lines() {
        let primary = "\
# unrelated comment
build --jobs=8
# >>> build cache (managed by tools/remote:setup)
build --remote_cache=grpcs://example.com
# <<< build cache (managed by tools/remote:setup)
common:remote --remote_header=x-buildbuddy-api-key=secret
common:remote --bes_header=x-buildbuddy-api-key=secret
common:other --remote_header=ignored
";
        let extracted = extract_primary_bazelrc_cache_lines(primary);
        assert_eq!(
            extracted,
            "\
# >>> build cache (managed by tools/remote:setup)
build --remote_cache=grpcs://example.com
# <<< build cache (managed by tools/remote:setup)
common:remote --remote_header=x-buildbuddy-api-key=secret
common:remote --bes_header=x-buildbuddy-api-key=secret
"
        );
    }

    #[test]
    fn test_extract_usage() {
        let usage = extract_usage(WORKTREE_SH);
        assert!(usage.starts_with("worktree.sh — create an isolated git worktree"));
        assert!(usage.contains("WORKTREE_SCRATCH_TTL_HOURS"));
        assert!(!usage.contains("set -euo pipefail"));
        assert!(usage.ends_with("\n\n"));
    }

    #[test]
    fn test_first_n_chars_multibyte_no_panic() {
        // Byte index 12 is in the middle of the 4th 3-byte character (`a` + 3*3 = 10..13);
        // `&str[..12]` would panic, whereas `first_n_chars_bytes` never panics in any locale.
        let mb = "a日本語日本語日本語日本語extra".as_bytes();
        let c_loc = CString::new("C").unwrap();
        unsafe {
            setlocale(LC_ALL, c_loc.as_ptr());
        }
        assert_eq!(first_n_chars_bytes(mb, 12), &mb[..12]);
        let utf8_loc = CString::new("en_US.UTF-8").unwrap();
        let p = unsafe { setlocale(LC_ALL, utf8_loc.as_ptr()) };
        if !p.is_null() {
            assert_eq!(
                first_n_chars_bytes(mb, 12),
                "a日本語日本語日本語日本".as_bytes()
            );
        }
        let non_utf8 = b"\xff\xfe\xfd123456789012345";
        assert_eq!(first_n_chars_bytes(non_utf8, 12).len(), 12);
    }
}
