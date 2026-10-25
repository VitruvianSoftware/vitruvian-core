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

use std::cmp::Ordering;
use std::env;
use std::ffi::{CStr, CString, OsStr};
use std::fs;
use std::io::{self, Write};
use std::os::raw::{c_char, c_int};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::MetadataExt;
use std::os::unix::process::ExitStatusExt;
use std::path::Path;
use std::process::{Command, ExitStatus, Stdio};

const MARKER: &[u8] = b".vitruvian-worktree";
const ORPHAN_GRACE_DAYS: &[u8] = b"1";

#[cfg(target_os = "macos")]
const LC_ALL: c_int = 0;
#[cfg(not(target_os = "macos"))]
const LC_ALL: c_int = 6;

extern "C" {
    fn setlocale(category: c_int, locale: *const c_char) -> *mut c_char;
    fn strcoll(s1: *const c_char, s2: *const c_char) -> c_int;
    fn kill(pid: c_int, sig: c_int) -> c_int;
    fn strerror(errnum: c_int) -> *const c_char;
    fn write(fd: c_int, buf: *const u8, count: usize) -> isize;
}

struct FdWriter(c_int);

impl Write for FdWriter {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        if buf.is_empty() {
            return Ok(0);
        }
        loop {
            let n = unsafe { write(self.0, buf.as_ptr(), buf.len()) };
            if n >= 0 {
                return Ok(n as usize);
            }
            let err = io::Error::last_os_error();
            if err.kind() != io::ErrorKind::Interrupted {
                return Err(err);
            }
        }
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

const MD5_S: [u32; 64] = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9,
    14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10, 15,
    21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
];

const MD5_K: [u32; 64] = [
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
];

/// Compute RFC 1321 MD5 digest of `input` as a 32-character lowercase hex string.
pub fn md5_hex(input: &[u8]) -> String {
    let mut a0: u32 = 0x67452301;
    let mut b0: u32 = 0xefcdab89;
    let mut c0: u32 = 0x98badcfe;
    let mut d0: u32 = 0x10325476;

    let bit_len = (input.len() as u64).wrapping_mul(8);
    let mut msg = Vec::with_capacity(((input.len() + 9 + 63) / 64) * 64);
    msg.extend_from_slice(input);
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0x00);
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
                0..=15 => ((b & c) | (!b & d), i),
                16..=31 => ((d & b) | (!d & c), (5 * i + 1) % 16),
                32..=47 => (b ^ c ^ d, (3 * i + 5) % 16),
                _ => (c ^ (b | !d), (7 * i) % 16),
            };
            let temp = f.wrapping_add(a).wrapping_add(MD5_K[i]).wrapping_add(m[g]);
            a = d;
            d = c;
            c = b;
            b = b.wrapping_add(temp.rotate_left(MD5_S[i]));
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

    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(32);
    for &byte in &digest {
        out.push(HEX[(byte >> 4) as usize] as char);
        out.push(HEX[(byte & 0x0f) as usize] as char);
    }
    out
}

pub fn md5_of(s: &str) -> String {
    md5_hex(s.as_bytes())
}

pub fn md5_of_bytes(b: &[u8]) -> Vec<u8> {
    md5_hex(b).into_bytes()
}

pub fn is_hex32_bytes(b: &[u8]) -> bool {
    b.len() == 32
        && b.iter()
            .all(|&c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
}

pub fn is_hex32(s: &str) -> bool {
    is_hex32_bytes(s.as_bytes())
}

pub fn human(bytes: u64) -> String {
    const UNITS: [&str; 5] = ["B", "KB", "MB", "GB", "TB"];
    let mut b = bytes as f64;
    let mut i = 0;
    while b >= 1024.0 && i < 4 {
        b /= 1024.0;
        i += 1;
    }
    format!("{:.1}{}", b, UNITS[i])
}

fn bytes_to_path(b: &[u8]) -> &Path {
    Path::new(OsStr::from_bytes(b))
}

fn join_path_bytes(base: &[u8], rel: &[u8]) -> Vec<u8> {
    let mut v = Vec::with_capacity(base.len() + 1 + rel.len());
    v.extend_from_slice(base);
    if !base.ends_with(b"/") {
        v.push(b'/');
    }
    v.extend_from_slice(rel);
    v
}

fn os_err_bytes(err: &io::Error) -> Vec<u8> {
    if let Some(code) = err.raw_os_error() {
        unsafe {
            let ptr = strerror(code);
            if !ptr.is_null() {
                return CStr::from_ptr(ptr).to_bytes().to_vec();
            }
        }
    }
    err.to_string().into_bytes()
}

fn exit_code_from_status(st: ExitStatus) -> i32 {
    if let Some(code) = st.code() {
        code
    } else if let Some(sig) = st.signal() {
        128 + sig
    } else {
        1
    }
}

fn report_write_error(
    prog: &[u8],
    line: u32,
    builtin: &[u8],
    e: &io::Error,
    err: &mut dyn Write,
) -> i32 {
    let mut msg = Vec::new();
    msg.extend_from_slice(prog);
    msg.extend_from_slice(b": line ");
    msg.extend_from_slice(line.to_string().as_bytes());
    msg.extend_from_slice(b": ");
    msg.extend_from_slice(builtin);
    msg.extend_from_slice(b": write error: ");
    msg.extend_from_slice(&os_err_bytes(e));
    msg.push(b'\n');
    let _ = err.write_all(&msg);
    let _ = err.flush();
    1
}

fn write_builtin_bytes(
    out: &mut dyn Write,
    err: &mut dyn Write,
    prog: &[u8],
    line: u32,
    builtin: &[u8],
    bytes: &[u8],
) -> Result<(), i32> {
    if let Err(e) = out.write_all(bytes).and_then(|()| out.flush()) {
        return Err(report_write_error(prog, line, builtin, &e, err));
    }
    Ok(())
}

fn info_bytes(
    out: &mut dyn Write,
    err: &mut dyn Write,
    prog: &[u8],
    msg: &[u8],
) -> Result<(), i32> {
    let mut buf = Vec::with_capacity(msg.len() + 15);
    buf.extend_from_slice(b"\x1b[36m\xe2\x86\x92\x1b[0m ");
    buf.extend_from_slice(msg);
    buf.push(b'\n');
    write_builtin_bytes(out, err, prog, 63, b"printf", &buf)
}

fn ok_bytes(out: &mut dyn Write, err: &mut dyn Write, prog: &[u8], msg: &[u8]) -> Result<(), i32> {
    let mut buf = Vec::with_capacity(msg.len() + 15);
    buf.extend_from_slice(b"\x1b[32m\xe2\x9c\x93\x1b[0m ");
    buf.extend_from_slice(msg);
    buf.push(b'\n');
    write_builtin_bytes(out, err, prog, 64, b"printf", &buf)
}

fn warn_bytes(
    out: &mut dyn Write,
    err: &mut dyn Write,
    prog: &[u8],
    msg: &[u8],
) -> Result<(), i32> {
    let mut buf = Vec::with_capacity(msg.len() + 13);
    buf.extend_from_slice(b"\x1b[33m!\x1b[0m ");
    buf.extend_from_slice(msg);
    buf.push(b'\n');
    write_builtin_bytes(out, err, prog, 65, b"printf", &buf)
}

fn die_bytes(err: &mut dyn Write, prog: &[u8], msg: &[u8]) -> i32 {
    let mut buf = Vec::with_capacity(msg.len() + 15);
    buf.extend_from_slice(b"\x1b[31m\xe2\x9c\x97\x1b[0m ");
    buf.extend_from_slice(msg);
    buf.push(b'\n');
    if let Err(e) = err.write_all(&buf).and_then(|()| err.flush()) {
        return report_write_error(prog, 66, b"printf", &e, err);
    }
    1
}

fn bash_warns_null_byte() -> bool {
    const NEEDLE: &[u8] = b"ignored null byte in input";
    if let Some(path_os) = env::var_os("PATH") {
        for dir in path_os.as_bytes().split(|&b| b == b':') {
            let dir = if dir.is_empty() { b"." } else { dir };
            let cand = join_path_bytes(dir, b"bash");
            let p = bytes_to_path(&cand);
            if p.is_file() {
                if let Ok(bytes) = fs::read(p) {
                    return bytes.windows(NEEDLE.len()).any(|w| w == NEEDLE);
                }
            }
        }
    }
    if let Ok(bytes) = fs::read("/bin/bash") {
        return bytes.windows(NEEDLE.len()).any(|w| w == NEEDLE);
    }
    false
}

fn strip_nulls_cmd_subst(bytes: &mut Vec<u8>, line_no: u32, prog: &[u8], err: &mut dyn Write) {
    if bytes.contains(&0) {
        bytes.retain(|&b| b != 0);
        if bash_warns_null_byte() {
            let mut msg = Vec::new();
            msg.extend_from_slice(prog);
            msg.extend_from_slice(b": line ");
            msg.extend_from_slice(line_no.to_string().as_bytes());
            msg.extend_from_slice(b": warning: command substitution: ignored null byte in input\n");
            let _ = err.write_all(&msg);
            let _ = err.flush();
        }
    }
}

fn strip_one_trailing_slash(s: &[u8]) -> &[u8] {
    s.strip_suffix(b"/").unwrap_or(s)
}

fn trim_trailing_slashes(mut s: &[u8]) -> &[u8] {
    while let Some(rest) = s.strip_suffix(b"/") {
        s = rest;
    }
    s
}

fn basename_bytes(s: &[u8]) -> &[u8] {
    let trimmed = trim_trailing_slashes(s);
    if trimmed.is_empty() {
        return b"/";
    }
    match trimmed.iter().rposition(|&b| b == b'/') {
        Some(idx) => &trimmed[idx + 1..],
        None => trimmed,
    }
}

fn first_line_bytes(bytes: &[u8]) -> Vec<u8> {
    bytes.split(|&b| b == b'\n').next().unwrap_or(&[]).to_vec()
}

fn workspace_of_bytes(base: &[u8], prog: &[u8], err: &mut dyn Write) -> Vec<u8> {
    for rel in [
        b"DO_NOT_BUILD_HERE".as_slice(),
        b"execroot/DO_NOT_BUILD_HERE".as_slice(),
    ] {
        let p_bytes = join_path_bytes(base, rel);
        let p = bytes_to_path(&p_bytes);
        if p.is_file() {
            if let Ok(bytes) = fs::read(p) {
                let mut w = first_line_bytes(&bytes);
                strip_nulls_cmd_subst(&mut w, 117, prog, err);
                if !w.is_empty() {
                    return w;
                }
            }
        }
    }
    let cmdline_bytes = join_path_bytes(base, b"server/cmdline");
    let cmdline = bytes_to_path(&cmdline_bytes);
    if cmdline.is_file() {
        match fs::read(cmdline) {
            Ok(bytes) => {
                for part in bytes.split(|&b| b == 0 || b == b'\n') {
                    if let Some(rest) = part.strip_prefix(b"--workspace_directory=") {
                        return rest.to_vec();
                    }
                }
            }
            Err(e) => {
                // In bash: `tr '\0' '\n' < "${b}/server/cmdline"` prints a redirection error
                // to stderr on line 120, while the `$(...)` subshell completes with empty output.
                let mut msg = Vec::new();
                msg.extend_from_slice(prog);
                msg.extend_from_slice(b": line 120: ");
                msg.extend_from_slice(&cmdline_bytes);
                msg.extend_from_slice(b": ");
                msg.extend_from_slice(&os_err_bytes(&e));
                msg.push(b'\n');
                let _ = err.write_all(&msg);
                let _ = err.flush();
            }
        }
    }
    Vec::new()
}

pub fn workspace_of(base: &str) -> String {
    let mut sink = io::sink();
    let bytes = workspace_of_bytes(base.as_bytes(), b"bazel-cache.sh", &mut sink);
    String::from_utf8_lossy(&bytes).into_owned()
}

fn pid_is_alive_bytes(pid_bytes: &[u8]) -> bool {
    let mut s = pid_bytes;
    // Match bash's `legal_number` in `general.c`:
    // 1. `strtoimax` skips leading ASCII `isspace` (' ', '\t', '\n', '\r', '\v', '\f').
    while let Some(&first) = s.first() {
        if matches!(first, b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c) {
            s = &s[1..];
        } else {
            break;
        }
    }
    // 2. After `strtoimax`, `legal_number` skips trailing `whitespace(*ep)`,
    //    where in bash `whitespace(c)` is ONLY ' ' and '\t' (NOT '\r', '\n', '\v', '\f').
    while let Some(&last) = s.last() {
        if matches!(last, b' ' | b'\t') {
            s = &s[..s.len() - 1];
        } else {
            break;
        }
    }
    let digits = match s.first() {
        Some(b'+' | b'-') => &s[1..],
        _ => s,
    };
    if digits.is_empty() || !digits.iter().all(|c| c.is_ascii_digit()) {
        return false;
    }
    let Ok(pid_str) = std::str::from_utf8(s) else {
        return false;
    };
    let Ok(pid) = pid_str.parse::<c_int>() else {
        return false;
    };
    // Match bash's `kill -0` builtin: returns 0 (success) iff kill(pid, 0) == 0.
    // Both ESRCH and EPERM return -1 from kill(pid, 0), causing the builtin to fail.
    unsafe { kill(pid, 0) == 0 }
}

fn live_pid_with_err(base: &[u8], prog: &[u8], err: &mut dyn Write) -> Vec<u8> {
    let f_bytes = join_path_bytes(base, b"server/server.pid.txt");
    let f = bytes_to_path(&f_bytes);
    if !f.is_file() {
        return Vec::new();
    }
    let Ok(mut bytes) = fs::read(f) else {
        return Vec::new();
    };
    strip_nulls_cmd_subst(&mut bytes, 106, prog, err);
    while bytes.last() == Some(&b'\n') {
        bytes.pop();
    }
    if bytes.is_empty() {
        return Vec::new();
    }
    if pid_is_alive_bytes(&bytes) {
        return bytes;
    }
    Vec::new()
}

pub fn live_pid_bytes(base: &[u8]) -> Vec<u8> {
    let mut sink = io::sink();
    live_pid_with_err(base, b"bazel-cache.sh", &mut sink)
}

pub fn live_pid(base: &str) -> String {
    String::from_utf8_lossy(&live_pid_bytes(base.as_bytes())).into_owned()
}

pub fn used_within_bytes(dir: &[u8], days: &[u8]) -> bool {
    let mut mtime_arg = Vec::with_capacity(1 + days.len());
    mtime_arg.push(b'-');
    mtime_arg.extend_from_slice(days);
    let output = Command::new("find")
        .arg(OsStr::from_bytes(dir))
        .arg("-maxdepth")
        .arg("0")
        .arg("-mtime")
        .arg(OsStr::from_bytes(&mtime_arg))
        .stdin(Stdio::inherit())
        .stderr(Stdio::null())
        .output();
    match output {
        Ok(mut out) => {
            out.stdout.retain(|&b| b != 0);
            while out.stdout.last() == Some(&b'\n') {
                out.stdout.pop();
            }
            !out.stdout.is_empty()
        }
        Err(_) => false,
    }
}

pub fn used_within(dir: &str, days_str: &str) -> bool {
    used_within_bytes(dir.as_bytes(), days_str.as_bytes())
}

pub fn last_used_bytes(dir: &[u8]) -> Vec<u8> {
    let output = Command::new("date")
        .arg("-r")
        .arg(OsStr::from_bytes(dir))
        .arg("+%Y-%m-%d")
        .stdin(Stdio::inherit())
        .stderr(Stdio::null())
        .output();
    match output {
        Ok(mut out) if out.status.success() => {
            out.stdout.retain(|&b| b != 0);
            while out.stdout.last() == Some(&b'\n') {
                out.stdout.pop();
            }
            out.stdout
        }
        _ => b"?".to_vec(),
    }
}

pub fn last_used(dir: &str) -> String {
    String::from_utf8_lossy(&last_used_bytes(dir.as_bytes())).into_owned()
}

pub fn size_of_bytes(dir: &[u8]) -> u64 {
    let output = Command::new("du")
        .arg("-sk")
        .arg(OsStr::from_bytes(dir))
        .stdin(Stdio::inherit())
        .stderr(Stdio::null())
        .output();
    let Ok(mut out) = output else {
        return 0;
    };
    out.stdout.retain(|&b| b != 0);
    let first_line = out.stdout.split(|&b| b == b'\n').next().unwrap_or(b"");
    let first_field = first_line.split(|&b| b == b'\t').next().unwrap_or(b"");
    let k_str = std::str::from_utf8(first_field).unwrap_or("").trim();
    let k = k_str.parse::<u64>().unwrap_or(0);
    k.saturating_mul(1024)
}

pub fn size_of(dir: &str) -> u64 {
    size_of_bytes(dir.as_bytes())
}

fn locale_cmp(a: &[u8], b: &[u8]) -> Ordering {
    if let (Ok(ca), Ok(cb)) = (CString::new(a), CString::new(b)) {
        let r = unsafe { strcoll(ca.as_ptr(), cb.as_ptr()) };
        if r < 0 {
            return Ordering::Less;
        } else if r > 0 {
            return Ordering::Greater;
        }
    }
    a.cmp(b)
}

fn non_hidden_subdirs_bytes(parent: &[u8]) -> Vec<Vec<u8>> {
    let Ok(rd) = fs::read_dir(bytes_to_path(parent)) else {
        return Vec::new();
    };
    let mut entries: Vec<(Vec<u8>, Vec<u8>)> = Vec::new();
    for entry in rd.flatten() {
        let name = entry.file_name().into_vec();
        if name.starts_with(b".") {
            continue;
        }
        let full = join_path_bytes(parent, &name);
        if bytes_to_path(&full).is_dir() {
            let mut glob_expanded = Vec::with_capacity(full.len() + 1);
            glob_expanded.extend_from_slice(&full);
            glob_expanded.push(b'/');
            entries.push((glob_expanded, full));
        }
    }
    // Bash expands `"${parent}"/*/` with a trailing `/` on each candidate and sorts
    // the resulting strings with strcoll (falling back to byte comparison on tie).
    entries.sort_by(|(ga, _), (gb, _)| locale_cmp(ga, gb));
    entries.into_iter().map(|(_, full)| full).collect()
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Verdict {
    Keep,
    Reclaim,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Classification {
    pub verdict: Verdict,
    pub why: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ClassificationBytes {
    verdict: Verdict,
    why: Vec<u8>,
}

#[derive(Debug, Clone, Default)]
pub struct LiveState {
    pub live_ws: Vec<String>,
    pub live_hash: Vec<String>,
    pub live_roots: Vec<String>,
}

#[derive(Debug, Clone, Default)]
struct LiveStateBytes {
    live_ws: Vec<Vec<u8>>,
    live_hash: Vec<Vec<u8>>,
    live_roots: Vec<Vec<u8>>,
}

impl LiveStateBytes {
    fn is_live_ws(&self, ws: &[u8]) -> bool {
        self.live_ws.iter().any(|w| w.as_slice() == ws)
    }

    fn is_live_hash(&self, h: &[u8]) -> bool {
        self.live_hash.iter().any(|x| x.as_slice() == h)
    }

    fn is_live_root(&self, r: &[u8]) -> bool {
        self.live_roots.iter().any(|x| x.as_slice() == r)
    }
}

impl LiveState {
    fn to_bytes(&self) -> LiveStateBytes {
        LiveStateBytes {
            live_ws: self.live_ws.iter().map(|s| s.as_bytes().to_vec()).collect(),
            live_hash: self
                .live_hash
                .iter()
                .map(|s| s.as_bytes().to_vec())
                .collect(),
            live_roots: self
                .live_roots
                .iter()
                .map(|s| s.as_bytes().to_vec())
                .collect(),
        }
    }
}

fn classify_base_bytes(
    b_raw: &[u8],
    days: &[u8],
    state: &LiveStateBytes,
    prog: &[u8],
    err: &mut dyn Write,
) -> ClassificationBytes {
    let b = strip_one_trailing_slash(b_raw);
    let pid = live_pid_with_err(b, prog, err);
    if !pid.is_empty() {
        let mut why = b"live Bazel server (pid ".to_vec();
        why.extend_from_slice(&pid);
        why.push(b')');
        return ClassificationBytes {
            verdict: Verdict::Keep,
            why,
        };
    }
    let ws = workspace_of_bytes(b, prog, err);
    if !ws.is_empty() {
        if state.is_live_ws(&ws) {
            let mut why = b"worktree ".to_vec();
            why.extend_from_slice(&ws);
            return ClassificationBytes {
                verdict: Verdict::Keep,
                why,
            };
        } else if !bytes_to_path(&ws).exists() {
            if used_within_bytes(b, ORPHAN_GRACE_DAYS) {
                let mut why = b"workspace gone, but used within ".to_vec();
                why.extend_from_slice(ORPHAN_GRACE_DAYS);
                why.extend_from_slice(b"d (may be recreated): ");
                why.extend_from_slice(&ws);
                return ClassificationBytes {
                    verdict: Verdict::Keep,
                    why,
                };
            } else {
                let mut why = b"its workspace is gone: ".to_vec();
                why.extend_from_slice(&ws);
                return ClassificationBytes {
                    verdict: Verdict::Reclaim,
                    why,
                };
            }
        } else if used_within_bytes(b, days) {
            let mut why = b"workspace ".to_vec();
            why.extend_from_slice(&ws);
            why.extend_from_slice(b", used within ");
            why.extend_from_slice(days);
            why.push(b'd');
            return ClassificationBytes {
                verdict: Verdict::Keep,
                why,
            };
        } else {
            let mut why = b"workspace ".to_vec();
            why.extend_from_slice(&ws);
            why.extend_from_slice(b" exists, but this base is untouched for ");
            why.extend_from_slice(days);
            why.extend_from_slice(b"d+");
            return ClassificationBytes {
                verdict: Verdict::Reclaim,
                why,
            };
        }
    }
    if state.is_live_hash(basename_bytes(b)) {
        ClassificationBytes {
            verdict: Verdict::Keep,
            why: b"output base of a live worktree".to_vec(),
        }
    } else if used_within_bytes(b, days) {
        let mut why = b"unknown workspace, used within ".to_vec();
        why.extend_from_slice(days);
        why.push(b'd');
        ClassificationBytes {
            verdict: Verdict::Keep,
            why,
        }
    } else {
        let mut why = b"unknown workspace, untouched for ".to_vec();
        why.extend_from_slice(days);
        why.extend_from_slice(b"d+");
        ClassificationBytes {
            verdict: Verdict::Reclaim,
            why,
        }
    }
}

pub fn classify_base(b_raw: &str, days: &str, state: &LiveState) -> Classification {
    let mut sink = io::sink();
    let res = classify_base_bytes(
        b_raw.as_bytes(),
        days.as_bytes(),
        &state.to_bytes(),
        b"bazel-cache.sh",
        &mut sink,
    );
    Classification {
        verdict: res.verdict,
        why: String::from_utf8_lossy(&res.why).into_owned(),
    }
}

fn read_marker_first_line(
    marker_bytes: &[u8],
    prog: &[u8],
    err: &mut dyn Write,
) -> Result<Vec<u8>, i32> {
    let marker_path = bytes_to_path(marker_bytes);
    match fs::read(marker_path) {
        Ok(bytes) => {
            let mut w = first_line_bytes(&bytes);
            strip_nulls_cmd_subst(&mut w, 168, prog, err);
            Ok(w)
        }
        Err(_) => {
            // Match bash line 168: `[ -f "${r}/${MARKER}" ] && ws="$(head -1 "${r}/${MARKER}")"`
            // Under `set -e`, if `head -1` fails (e.g. unreadable marker), `head`'s stderr is
            // printed and the script aborts with `head`'s exit status.
            let output = Command::new("head")
                .arg("-1")
                .arg(OsStr::from_bytes(marker_bytes))
                .stdin(Stdio::inherit())
                .output();
            match output {
                Ok(out) => {
                    if !out.stderr.is_empty() {
                        let _ = err.write_all(&out.stderr);
                        let _ = err.flush();
                    }
                    if !out.status.success() {
                        return Err(exit_code_from_status(out.status));
                    }
                    let mut w = first_line_bytes(&out.stdout);
                    strip_nulls_cmd_subst(&mut w, 168, prog, err);
                    Ok(w)
                }
                Err(e) => {
                    let mut msg = Vec::new();
                    msg.extend_from_slice(prog);
                    msg.extend_from_slice(b": line 168: head: ");
                    if e.kind() == io::ErrorKind::NotFound {
                        msg.extend_from_slice(b"command not found\n");
                        let _ = err.write_all(&msg);
                        let _ = err.flush();
                        Err(127)
                    } else {
                        msg.extend_from_slice(&os_err_bytes(&e));
                        msg.push(b'\n');
                        let _ = err.write_all(&msg);
                        let _ = err.flush();
                        Err(126)
                    }
                }
            }
        }
    }
}

fn classify_root_bytes(
    r_raw: &[u8],
    days: &[u8],
    state: &LiveStateBytes,
    prog: &[u8],
    err: &mut dyn Write,
) -> Result<ClassificationBytes, i32> {
    let r = strip_one_trailing_slash(r_raw);
    if state.is_live_root(r) {
        return Ok(ClassificationBytes {
            verdict: Verdict::Keep,
            why: b"pinned by a live worktree's user.bazelrc".to_vec(),
        });
    }
    let mut ws = Vec::new();
    for b in non_hidden_subdirs_bytes(r) {
        if !is_hex32_bytes(basename_bytes(&b)) {
            continue;
        }
        let b_trimmed = strip_one_trailing_slash(&b);
        let pid = live_pid_with_err(b_trimmed, prog, err);
        if !pid.is_empty() {
            let mut why = b"live Bazel server (pid ".to_vec();
            why.extend_from_slice(&pid);
            why.push(b')');
            return Ok(ClassificationBytes {
                verdict: Verdict::Keep,
                why,
            });
        }
        if ws.is_empty() {
            ws = workspace_of_bytes(b_trimmed, prog, err);
        }
    }
    let marker_bytes = join_path_bytes(r, MARKER);
    if bytes_to_path(&marker_bytes).is_file() {
        ws = read_marker_first_line(&marker_bytes, prog, err)?;
    }
    if !ws.is_empty() {
        if state.is_live_ws(&ws) {
            let mut why = b"worktree ".to_vec();
            why.extend_from_slice(&ws);
            return Ok(ClassificationBytes {
                verdict: Verdict::Keep,
                why,
            });
        } else if bytes_to_path(&ws).exists() {
            let mut why = b"workspace ".to_vec();
            why.extend_from_slice(&ws);
            why.extend_from_slice(b" still exists");
            return Ok(ClassificationBytes {
                verdict: Verdict::Keep,
                why,
            });
        } else if used_within_bytes(r, ORPHAN_GRACE_DAYS) {
            let mut why = b"worktree gone, but used within ".to_vec();
            why.extend_from_slice(ORPHAN_GRACE_DAYS);
            why.extend_from_slice(b"d: ");
            why.extend_from_slice(&ws);
            return Ok(ClassificationBytes {
                verdict: Verdict::Keep,
                why,
            });
        } else {
            let mut why = b"its worktree is gone: ".to_vec();
            why.extend_from_slice(&ws);
            return Ok(ClassificationBytes {
                verdict: Verdict::Reclaim,
                why,
            });
        }
    }
    if used_within_bytes(r, days) {
        let mut why = b"no marker or workspace record, used within ".to_vec();
        why.extend_from_slice(days);
        why.push(b'd');
        Ok(ClassificationBytes {
            verdict: Verdict::Keep,
            why,
        })
    } else {
        let mut why = b"no marker or workspace record, untouched for ".to_vec();
        why.extend_from_slice(days);
        why.extend_from_slice(b"d+");
        Ok(ClassificationBytes {
            verdict: Verdict::Reclaim,
            why,
        })
    }
}

pub fn classify_root(r_raw: &str, days: &str, state: &LiveState) -> Classification {
    let mut sink = io::sink();
    match classify_root_bytes(
        r_raw.as_bytes(),
        days.as_bytes(),
        &state.to_bytes(),
        b"bazel-cache.sh",
        &mut sink,
    ) {
        Ok(res) => Classification {
            verdict: res.verdict,
            why: String::from_utf8_lossy(&res.why).into_owned(),
        },
        Err(_) => Classification {
            verdict: Verdict::Keep,
            why: String::new(),
        },
    }
}

fn resolve_bazel_user_bytes(prog: &[u8], err: &mut dyn Write) -> Result<Vec<u8>, i32> {
    if let Some(u) = env::var_os("USER") {
        if !u.as_bytes().is_empty() {
            return Ok(u.into_vec());
        }
    }
    let output = Command::new("id")
        .arg("-un")
        .stdin(Stdio::inherit())
        .output();
    match output {
        Ok(mut out) => {
            if !out.stderr.is_empty() {
                let _ = err.write_all(&out.stderr);
                let _ = err.flush();
            }
            if !out.status.success() {
                return Err(exit_code_from_status(out.status));
            }
            strip_nulls_cmd_subst(&mut out.stdout, 73, prog, err);
            while out.stdout.last() == Some(&b'\n') {
                out.stdout.pop();
            }
            Ok(out.stdout)
        }
        Err(e) => {
            let mut msg = Vec::new();
            msg.extend_from_slice(prog);
            msg.extend_from_slice(b": line 73: id: ");
            if e.kind() == io::ErrorKind::NotFound {
                msg.extend_from_slice(b"command not found\n");
                let _ = err.write_all(&msg);
                let _ = err.flush();
                Err(127)
            } else {
                msg.extend_from_slice(&os_err_bytes(&e));
                msg.push(b'\n');
                let _ = err.write_all(&msg);
                let _ = err.flush();
                Err(126)
            }
        }
    }
}

fn parse_user_bazelrc_root_bytes(
    bazelrc_bytes: &[u8],
    prog: &[u8],
    err: &mut dyn Write,
) -> Result<Option<Vec<u8>>, i32> {
    let bytes = match fs::read(bytes_to_path(bazelrc_bytes)) {
        Ok(b) => b,
        Err(_) => {
            let output = Command::new("sed")
                .args(["-n", "s/^startup --output_user_root=//p"])
                .arg(OsStr::from_bytes(bazelrc_bytes))
                .stdin(Stdio::inherit())
                .output();
            match output {
                Ok(out) => {
                    if !out.stderr.is_empty() {
                        let _ = err.write_all(&out.stderr);
                        let _ = err.flush();
                    }
                    if !out.status.success() {
                        return Err(exit_code_from_status(out.status));
                    }
                    out.stdout
                }
                Err(e) => {
                    let mut msg = Vec::new();
                    msg.extend_from_slice(prog);
                    msg.extend_from_slice(b": line 211: sed: ");
                    if e.kind() == io::ErrorKind::NotFound {
                        msg.extend_from_slice(b"command not found\n");
                        let _ = err.write_all(&msg);
                        let _ = err.flush();
                        return Err(127);
                    } else {
                        msg.extend_from_slice(&os_err_bytes(&e));
                        msg.push(b'\n');
                        let _ = err.write_all(&msg);
                        let _ = err.flush();
                        return Err(126);
                    }
                }
            }
        }
    };
    let mut last_root: Option<Vec<u8>> = None;
    for line in bytes.split(|&b| b == b'\n') {
        if let Some(rest) = line.strip_prefix(b"startup --output_user_root=") {
            last_root = Some(rest.to_vec());
        }
    }
    let Some(mut r) = last_root else {
        return Ok(None);
    };
    strip_nulls_cmd_subst(&mut r, 211, prog, err);
    if r.is_empty() {
        Ok(None)
    } else {
        Ok(Some(strip_one_trailing_slash(&r).to_vec()))
    }
}

fn open_slash_stdin_file() -> Option<fs::File> {
    let dir = env::temp_dir();
    let pid = std::process::id();
    for attempt in 0..100u32 {
        let path = dir.join(format!(".bazel_cache_md5_{}_{}", pid, attempt));
        if let Ok(mut w) = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
        {
            let write_ok = w.write_all(b"/").is_ok() && w.flush().is_ok();
            drop(w);
            let r = fs::File::open(&path).ok();
            let _ = fs::remove_file(&path);
            if write_ok {
                return r;
            }
            return None;
        }
    }
    None
}

fn run_md5_candidate(
    cmd: &str,
    args: &[&str],
    prog_err: Option<(&[u8], &mut dyn Write)>,
) -> Option<Vec<u8>> {
    let stdin_file = open_slash_stdin_file()?;
    let output = Command::new(cmd)
        .args(args)
        .stdin(Stdio::from(stdin_file))
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output();
    match output {
        Ok(out) => {
            if let Some((_, err)) = prog_err {
                if !out.stderr.is_empty() {
                    let _ = err.write_all(&out.stderr);
                    let _ = err.flush();
                }
            }
            if out.status.success() {
                Some(out.stdout)
            } else {
                None
            }
        }
        Err(e) => {
            if let Some((prog, err)) = prog_err {
                let mut msg = Vec::new();
                msg.extend_from_slice(prog);
                msg.extend_from_slice(b": line 95: ");
                msg.extend_from_slice(cmd.as_bytes());
                msg.extend_from_slice(b": ");
                if e.kind() == io::ErrorKind::NotFound {
                    msg.extend_from_slice(b"command not found\n");
                } else {
                    msg.extend_from_slice(&os_err_bytes(&e));
                    msg.push(b'\n');
                }
                let _ = err.write_all(&msg);
                let _ = err.flush();
            }
            None
        }
    }
}

fn probe_md5_tool(prog: &[u8], err: &mut dyn Write) -> bool {
    let stdout = run_md5_candidate("md5sum", &[], None)
        .or_else(|| run_md5_candidate("/sbin/md5", &["-q"], None))
        .or_else(|| run_md5_candidate("md5", &["-q"], None))
        .or_else(|| run_md5_candidate("openssl", &["md5", "-r"], Some((prog, err))));
    let Some(mut raw) = stdout else {
        return false;
    };
    raw.retain(|&b| b != 0);
    let mut out = Vec::new();
    let trimmed = raw.strip_suffix(b"\n").unwrap_or(&raw);
    for (i, line) in trimmed.split(|&b| b == b'\n').enumerate() {
        if i > 0 {
            out.push(b'\n');
        }
        let f1 = line.split(|&b| b == b' ').next().unwrap_or(b"");
        out.extend_from_slice(f1);
    }
    while out.last() == Some(&b'\n') {
        out.pop();
    }
    !out.is_empty()
}

fn discover_live_state_bytes(prog: &[u8], err: &mut dyn Write) -> Result<LiveStateBytes, i32> {
    let mut state = LiveStateBytes::default();
    let output = Command::new("git")
        .args(["worktree", "list", "--porcelain"])
        .stdin(Stdio::inherit())
        .stderr(Stdio::null())
        .output();
    let Ok(out) = output else {
        return Ok(state);
    };
    // Match bash's `while IFS= read -r w`: only process newline-terminated lines,
    // dropping any unterminated trailing line.
    let Some(last_nl) = out.stdout.iter().rposition(|&b| b == b'\n') else {
        return Ok(state);
    };
    let terminated = &out.stdout[..last_nl];
    for line in terminated.split(|&b| b == b'\n') {
        if let Some(w) = line.strip_prefix(b"worktree ") {
            if w.is_empty() {
                continue;
            }
            state.live_ws.push(w.to_vec());
            state.live_hash.push(md5_of_bytes(w));
            let bazelrc = join_path_bytes(w, b"user.bazelrc");
            if bytes_to_path(&bazelrc).is_file() {
                if let Some(r) = parse_user_bazelrc_root_bytes(&bazelrc, prog, err)? {
                    state.live_roots.push(r);
                }
            }
        }
    }
    Ok(state)
}

fn git_show_toplevel_bytes() -> Vec<u8> {
    let output = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .stdin(Stdio::inherit())
        .stderr(Stdio::null())
        .output();
    match output {
        Ok(mut out) => {
            out.stdout.retain(|&b| b != 0);
            while out.stdout.last() == Some(&b'\n') {
                out.stdout.pop();
            }
            out.stdout
        }
        Err(_) => Vec::new(),
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ItemKind {
    Base,
    Root,
}

fn same_dir_inode(a: &Path, b: &Path) -> bool {
    let (Ok(ma), Ok(mb)) = (fs::metadata(a), fs::metadata(b)) else {
        return false;
    };
    ma.dev() == mb.dev() && ma.ino() == mb.ino()
}

fn current_logical_pwd() -> Option<Vec<u8>> {
    if let Some(pwd_os) = env::var_os("PWD") {
        let pwd_bytes = pwd_os.as_bytes();
        if pwd_bytes.starts_with(b"/") && same_dir_inode(bytes_to_path(pwd_bytes), Path::new(".")) {
            return Some(pwd_os.into_vec());
        }
    }
    env::current_dir()
        .ok()
        .map(|p| p.into_os_string().into_vec())
}

fn normalize_logical_path(base_abs: &[u8], target: &[u8]) -> Vec<u8> {
    let mut comps: Vec<&[u8]> = Vec::new();
    if !target.starts_with(b"/") {
        for seg in base_abs.split(|&b| b == b'/') {
            if !seg.is_empty() && seg != b"." {
                comps.push(seg);
            }
        }
    }
    for seg in target.split(|&b| b == b'/') {
        if seg.is_empty() || seg == b"." {
            continue;
        } else if seg == b".." {
            comps.pop();
        } else {
            comps.push(seg);
        }
    }
    if comps.is_empty() {
        return b"/".to_vec();
    }
    let mut out = Vec::new();
    for seg in comps {
        out.push(b'/');
        out.extend_from_slice(seg);
    }
    out
}

fn logical_cd_bytes(target: &[u8]) -> Result<Vec<u8>, io::Error> {
    let old_pwd = current_logical_pwd();
    let candidate = if target.starts_with(b"/") {
        Some(normalize_logical_path(b"/", target))
    } else {
        old_pwd
            .as_ref()
            .map(|base| normalize_logical_path(base, target))
    };

    // If target does not contain `..`, chdir directly to target so intermediate
    // symlinks are traversed as the kernel expects; if it contains `..`, bash
    // resolves `..` logically against $PWD first.
    let has_dotdot = target.split(|&b| b == b'/').any(|seg| seg == b"..");
    let pwd = if has_dotdot {
        if let Some(ref cand) = candidate {
            if env::set_current_dir(OsStr::from_bytes(cand)).is_ok() {
                cand.clone()
            } else {
                env::set_current_dir(OsStr::from_bytes(target))?;
                env::current_dir()?.into_os_string().into_vec()
            }
        } else {
            env::set_current_dir(OsStr::from_bytes(target))?;
            env::current_dir()?.into_os_string().into_vec()
        }
    } else {
        env::set_current_dir(OsStr::from_bytes(target))?;
        match candidate {
            Some(cand) if same_dir_inode(bytes_to_path(&cand), Path::new(".")) => cand,
            _ => env::current_dir()?.into_os_string().into_vec(),
        }
    };

    if let Some(old) = old_pwd {
        env::set_var("OLDPWD", OsStr::from_bytes(&old));
    }
    env::set_var("PWD", OsStr::from_bytes(&pwd));
    Ok(pwd)
}

#[allow(clippy::too_many_arguments)]
fn cmd_gc_bytes(
    prog: &[u8],
    args: &[&[u8]],
    pwd: &[u8],
    bazel_root: &[u8],
    wt_cache_root: &[u8],
    stray_parents: &[Vec<u8>; 2],
    out: &mut dyn Write,
    err: &mut dyn Write,
) -> i32 {
    let mut days: Vec<u8> = b"30".to_vec();
    let mut execute = false;

    let mut idx = 0;
    while idx < args.len() {
        match args[idx] {
            b"--days" => {
                let val = args.get(idx + 1).copied().unwrap_or(b"");
                if val.is_empty() {
                    let mut msg = Vec::new();
                    msg.extend_from_slice(prog);
                    msg.extend_from_slice(b": line 198: 2: --days needs a value\n");
                    let _ = err.write_all(&msg);
                    let _ = err.flush();
                    return 1;
                }
                days = val.to_vec();
                idx += 2;
            }
            b"--execute" => {
                execute = true;
                idx += 1;
            }
            other => {
                let mut msg = b"unknown flag: ".to_vec();
                msg.extend_from_slice(other);
                return die_bytes(err, prog, &msg);
            }
        }
    }

    if !probe_md5_tool(prog, err) {
        return die_bytes(
            err,
            prog,
            b"no md5 tool (md5sum, md5 or openssl), so output bases cannot be matched to worktrees.",
        );
    }

    let state = match discover_live_state_bytes(prog, err) {
        Ok(s) => s,
        Err(code) => return code,
    };
    if state.live_ws.is_empty() {
        let mut msg = b"found 0 git worktrees from ".to_vec();
        msg.extend_from_slice(pwd);
        msg.extend_from_slice(
            b", so nothing can be protected.\n   Run it from the repo: bazel run //tools/bazel-cache:gc",
        );
        return die_bytes(err, prog, &msg);
    }

    let toplevel = git_show_toplevel_bytes();
    let mut hdr1 = Vec::new();
    hdr1.extend_from_slice(b"protecting ");
    hdr1.extend_from_slice(state.live_ws.len().to_string().as_bytes());
    hdr1.extend_from_slice(b" worktree(s) of ");
    hdr1.extend_from_slice(&toplevel);
    hdr1.extend_from_slice(b"; age threshold ");
    hdr1.extend_from_slice(&days);
    hdr1.push(b'd');
    if let Err(code) = info_bytes(out, err, prog, &hdr1) {
        return code;
    }

    let mut hdr2 = Vec::new();
    hdr2.extend_from_slice(b"scanning ");
    hdr2.extend_from_slice(bazel_root);
    hdr2.extend_from_slice(b", ");
    hdr2.extend_from_slice(wt_cache_root);
    hdr2.extend_from_slice(b"/*, and stray bases in ");
    hdr2.extend_from_slice(&stray_parents[0]);
    hdr2.push(b' ');
    hdr2.extend_from_slice(&stray_parents[1]);
    if let Err(code) = info_bytes(out, err, prog, &hdr2) {
        return code;
    }
    if let Err(code) = write_builtin_bytes(out, err, prog, 222, b"echo", b"\n") {
        return code;
    }

    let mut items: Vec<(ItemKind, Vec<u8>)> = Vec::new();
    if bytes_to_path(bazel_root).is_dir() {
        for d in non_hidden_subdirs_bytes(bazel_root) {
            let name = basename_bytes(&d);
            if name == b"install" || name == b"cache" {
                continue;
            }
            items.push((ItemKind::Base, strip_one_trailing_slash(&d).to_vec()));
        }
    }
    if bytes_to_path(wt_cache_root).is_dir() {
        for d in non_hidden_subdirs_bytes(wt_cache_root) {
            items.push((ItemKind::Root, strip_one_trailing_slash(&d).to_vec()));
        }
    }
    for r in stray_parents {
        if !bytes_to_path(r).is_dir() {
            continue;
        }
        for d in non_hidden_subdirs_bytes(r) {
            if is_hex32_bytes(basename_bytes(&d)) {
                items.push((ItemKind::Base, strip_one_trailing_slash(&d).to_vec()));
            }
        }
    }

    let mut total: u64 = 0;
    let mut n: usize = 0;
    let mut kept: usize = 0;

    for (kind, d) in &items {
        if !bytes_to_path(d).is_dir() {
            continue;
        }
        let first = match kind {
            ItemKind::Root => match classify_root_bytes(d, &days, &state, prog, err) {
                Ok(c) => c,
                Err(code) => return code,
            },
            ItemKind::Base => classify_base_bytes(d, &days, &state, prog, err),
        };
        if first.verdict == Verdict::Keep {
            let mut msg = Vec::new();
            msg.extend_from_slice(b"  KEEP     ");
            msg.extend_from_slice(d);
            msg.extend_from_slice(b"\n           ");
            msg.extend_from_slice(&first.why);
            msg.push(b'\n');
            if let Err(code) = write_builtin_bytes(out, err, prog, 250, b"printf", &msg) {
                return code;
            }
            kept += 1;
            continue;
        }
        let sz = size_of_bytes(d);
        let used = last_used_bytes(d);
        let mut msg = Vec::new();
        msg.extend_from_slice(b"  RECLAIM  ");
        msg.extend_from_slice(d);
        msg.extend_from_slice(b"  ");
        msg.extend_from_slice(human(sz).as_bytes());
        msg.extend_from_slice(b", last used ");
        msg.extend_from_slice(&used);
        msg.extend_from_slice(b"\n           ");
        msg.extend_from_slice(&first.why);
        msg.push(b'\n');
        if let Err(code) = write_builtin_bytes(out, err, prog, 255, b"printf", &msg) {
            return code;
        }

        if execute {
            let second = match kind {
                ItemKind::Root => match classify_root_bytes(d, &days, &state, prog, err) {
                    Ok(c) => c,
                    Err(code) => return code,
                },
                ItemKind::Base => classify_base_bytes(d, &days, &state, prog, err),
            };
            if second.verdict != Verdict::Reclaim {
                let mut wmsg = b"  changed since classification (".to_vec();
                wmsg.extend_from_slice(&second.why);
                wmsg.extend_from_slice(") — skipping".as_bytes());
                if let Err(code) = warn_bytes(out, err, prog, &wmsg) {
                    return code;
                }
                continue;
            }
            let _ = Command::new("chmod")
                .args(["-R", "u+w"])
                .arg(OsStr::from_bytes(d))
                .stdin(Stdio::inherit())
                .stderr(Stdio::null())
                .status();
            let rm_status = Command::new("rm")
                .arg("-rf")
                .arg(OsStr::from_bytes(d))
                .stdin(Stdio::inherit())
                .stderr(Stdio::null())
                .status();
            if !matches!(rm_status, Ok(st) if st.success()) {
                let mut wmsg = b"  could not fully remove ".to_vec();
                wmsg.extend_from_slice(d);
                if let Err(code) = warn_bytes(out, err, prog, &wmsg) {
                    return code;
                }
            }
        }
        total = total.saturating_add(sz);
        n += 1;
    }

    if let Err(code) = write_builtin_bytes(out, err, prog, 270, b"echo", b"\n") {
        return code;
    }
    if n == 0 {
        let mut msg = b"nothing reclaimable (kept ".to_vec();
        msg.extend_from_slice(kept.to_string().as_bytes());
        msg.extend_from_slice(b"; threshold ");
        msg.extend_from_slice(&days);
        msg.extend_from_slice(b"d)");
        if let Err(code) = ok_bytes(out, err, prog, &msg) {
            return code;
        }
        return 0;
    }
    if execute {
        let mut msg = b"reclaimed ".to_vec();
        msg.extend_from_slice(human(total).as_bytes());
        msg.extend_from_slice(b" across ");
        msg.extend_from_slice(n.to_string().as_bytes());
        msg.extend_from_slice(b" output base(s)/root(s); kept ");
        msg.extend_from_slice(kept.to_string().as_bytes());
        if let Err(code) = ok_bytes(out, err, prog, &msg) {
            return code;
        }
    } else {
        let mut msg = "DRY RUN — ".as_bytes().to_vec();
        msg.extend_from_slice(human(total).as_bytes());
        msg.extend_from_slice(b" reclaimable across ");
        msg.extend_from_slice(n.to_string().as_bytes());
        msg.extend_from_slice(b" output base(s)/root(s); kept ");
        msg.extend_from_slice(kept.to_string().as_bytes());
        if let Err(code) = ok_bytes(out, err, prog, &msg) {
            return code;
        }
        if let Err(code) = info_bytes(
            out,
            err,
            prog,
            b"re-run with --execute to delete. Deleting only discards build state; Bazel re-analyses on the next build.",
        ) {
            return code;
        }
    }
    0
}

pub fn run<S: AsRef<OsStr>>(args: &[S]) -> i32 {
    let mut stdout = FdWriter(1);
    let mut stderr = FdWriter(2);
    run_with_io(args, &mut stdout, &mut stderr)
}

pub fn run_with_io<S: AsRef<OsStr>>(args: &[S], out: &mut dyn Write, err: &mut dyn Write) -> i32 {
    unsafe {
        setlocale(LC_ALL, b"\0".as_ptr() as *const c_char);
    }

    let raw_args: Vec<&[u8]> = args.iter().map(|s| s.as_ref().as_bytes()).collect();
    let prog = raw_args.first().copied().unwrap_or(b"bazel-cache.sh");

    let ws_dir: Vec<u8> = match env::var_os("BUILD_WORKSPACE_DIRECTORY") {
        Some(val) if !val.as_bytes().is_empty() => val.into_vec(),
        _ => b".".to_vec(),
    };
    let pwd = match logical_cd_bytes(&ws_dir) {
        Ok(p) => p,
        Err(e) => {
            let mut cd_err = Vec::new();
            cd_err.extend_from_slice(prog);
            cd_err.extend_from_slice(b": line 71: cd: ");
            cd_err.extend_from_slice(&ws_dir);
            cd_err.extend_from_slice(b": ");
            cd_err.extend_from_slice(&os_err_bytes(&e));
            cd_err.push(b'\n');
            let _ = err.write_all(&cd_err);
            let _ = err.flush();
            let mut die_msg = b"cannot cd to ".to_vec();
            die_msg.extend_from_slice(&ws_dir);
            return die_bytes(err, prog, &die_msg);
        }
    };

    let bazel_user = match resolve_bazel_user_bytes(prog, err) {
        Ok(u) => u,
        Err(code) => return code,
    };

    let Some(home_os) = env::var_os("HOME") else {
        let mut msg = Vec::new();
        msg.extend_from_slice(prog);
        msg.extend_from_slice(b": line 74: HOME: unbound variable\n");
        let _ = err.write_all(&msg);
        let _ = err.flush();
        return 1;
    };
    let home = home_os.into_vec();

    let mut mac_root = home.clone();
    mac_root.extend_from_slice(b"/Library/Caches/bazel/_bazel_");
    mac_root.extend_from_slice(&bazel_user);

    let bazel_root = if bytes_to_path(&mac_root).is_dir() {
        mac_root
    } else {
        let mut r = home.clone();
        r.extend_from_slice(b"/.cache/bazel/_bazel_");
        r.extend_from_slice(&bazel_user);
        r
    };

    let mut wt_cache_root = home.clone();
    wt_cache_root.extend_from_slice(b"/.cache/bazel/worktrees");

    let mut stray0 = home.clone();
    stray0.extend_from_slice(b"/Library/Caches/bazel");
    let mut stray1 = home;
    stray1.extend_from_slice(b"/.cache/bazel");
    let stray_parents = [stray0, stray1];

    match raw_args.get(1).copied() {
        Some(b"gc") => cmd_gc_bytes(
            prog,
            &raw_args[2..],
            &pwd,
            &bazel_root,
            &wt_cache_root,
            &stray_parents,
            out,
            err,
        ),
        _ => die_bytes(
            err,
            prog,
            b"usage: bazel-cache.sh gc [--days N] [--execute]",
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_md5_rfc1321_vectors() {
        assert_eq!(md5_of(""), "d41d8cd98f00b204e9800998ecf8427e");
        assert_eq!(md5_of("a"), "0cc175b9c0f1b6a831c399e269772661");
        assert_eq!(md5_of("abc"), "900150983cd24fb0d6963f7d28e17f72");
        assert_eq!(md5_of("message digest"), "f96b697d7cb7938d525a2f31aaf161d0");
        assert_eq!(
            md5_of("abcdefghijklmnopqrstuvwxyz"),
            "c3fcd3d76192e4007dfb496cca67e13b"
        );
        assert_eq!(
            md5_of("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"),
            "d174ab98d277d9f5a5611c2c9f419d9f"
        );
        assert_eq!(
            md5_of(
                "12345678901234567890123456789012345678901234567890123456789012345678901234567890"
            ),
            "57edf4a22be3c955ac49da2e2107b67a"
        );
        assert_eq!(md5_of("/"), "6666cd76f96956469e7be39d750cc7d9");
    }

    #[test]
    fn test_md5_multi_block_lengths() {
        let s55 = "a".repeat(55);
        assert_eq!(md5_of(&s55), "ef1772b6dff9a122358552954ad0df65");
        let s56 = "a".repeat(56);
        assert_eq!(md5_of(&s56), "3b0c8ac703f828b04c6c197006d17218");
        let s64 = "a".repeat(64);
        assert_eq!(md5_of(&s64), "014842d480b571495a4a0363793f7367");
    }

    #[test]
    fn test_is_hex32() {
        assert!(is_hex32("0123456789abcdef0123456789abcdef"));
        assert!(is_hex32("fedcba9876543210fedcba9876543210"));
        assert!(!is_hex32("0123456789abcdef0123456789abcde"));
        assert!(!is_hex32("0123456789abcdef0123456789abcdef0"));
        assert!(!is_hex32("0123456789ABCDEF0123456789abcdef"));
        assert!(!is_hex32("0123456789abcdef0123456789abcdeg"));
    }

    #[test]
    fn test_human() {
        assert_eq!(human(0), "0.0B");
        assert_eq!(human(1), "1.0B");
        assert_eq!(human(512), "512.0B");
        assert_eq!(human(1024), "1.0KB");
        assert_eq!(human(1536), "1.5KB");
        assert_eq!(human(4096), "4.0KB");
        assert_eq!(human(1024 * 1024), "1.0MB");
        assert_eq!(human(1024 * 1024 * 1024), "1.0GB");
        assert_eq!(human(1024u64 * 1024 * 1024 * 1024), "1.0TB");
        assert_eq!(human(1024u64 * 1024 * 1024 * 1024 * 2), "2.0TB");
    }

    #[test]
    fn test_used_within() {
        let tmp = env::temp_dir().join(format!("bazel_cache_unit_{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();
        let tmp_str = tmp.to_string_lossy();

        // Modified just now -> within 1 day
        assert!(used_within(&tmp_str, "1"));
        // Invalid days -> false
        assert!(!used_within(&tmp_str, "abc"));
        assert!(!used_within(&tmp_str, ""));

        // Backdate mtime to 2020-01-01 so `-mtime -1` and `-mtime -0` are deterministically false
        // on both BSD find (macOS) and GNU find (Linux).
        let _ = Command::new("touch")
            .args(["-t", "202001010000.00", &tmp_str])
            .status();
        assert!(!used_within(&tmp_str, "1"));
        assert!(!used_within(&tmp_str, "0"));

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_workspace_of_sources() {
        let tmp = env::temp_dir().join(format!("bazel_cache_ws_{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(tmp.join("execroot")).unwrap();
        fs::create_dir_all(tmp.join("server")).unwrap();
        let b = tmp.to_string_lossy().into_owned();

        assert_eq!(workspace_of(&b), "");

        fs::write(
            tmp.join("server/cmdline"),
            b"bazel\0--workspace_directory=/tmp/from_cmdline\0--batch\0",
        )
        .unwrap();
        assert_eq!(workspace_of(&b), "/tmp/from_cmdline");

        fs::write(
            tmp.join("execroot/DO_NOT_BUILD_HERE"),
            "/tmp/from_execroot\nignored_second_line\n",
        )
        .unwrap();
        assert_eq!(workspace_of(&b), "/tmp/from_execroot");

        fs::write(tmp.join("DO_NOT_BUILD_HERE"), "/tmp/from_top\n").unwrap();
        assert_eq!(workspace_of(&b), "/tmp/from_top");

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_classify_base_and_root() {
        let tmp = env::temp_dir().join(format!("bazel_cache_cls_{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        let live_ws_dir = tmp.join("live-ws");
        let existing_other_ws = tmp.join("other-ws");
        fs::create_dir_all(&live_ws_dir).unwrap();
        fs::create_dir_all(&existing_other_ws).unwrap();

        let live_ws_str = live_ws_dir.to_string_lossy().into_owned();
        let pinned_root_str = tmp.join("pinned-root").to_string_lossy().into_owned();
        let state = LiveState {
            live_ws: vec![live_ws_str.clone()],
            live_hash: vec![md5_of(&live_ws_str)],
            live_roots: vec![pinned_root_str.clone()],
        };

        let b_live = tmp.join("b_live");
        fs::create_dir_all(&b_live).unwrap();
        fs::write(b_live.join("DO_NOT_BUILD_HERE"), format!("{live_ws_str}\n")).unwrap();
        let c = classify_base(&b_live.to_string_lossy(), "30", &state);
        assert_eq!(c.verdict, Verdict::Keep);
        assert_eq!(c.why, format!("worktree {live_ws_str}"));

        let b_hash = tmp.join(md5_of(&live_ws_str));
        fs::create_dir_all(&b_hash).unwrap();
        let c = classify_base(&b_hash.to_string_lossy(), "30", &state);
        assert_eq!(c.verdict, Verdict::Keep);
        assert_eq!(c.why, "output base of a live worktree");

        fs::create_dir_all(&pinned_root_str).unwrap();
        let c = classify_root(&pinned_root_str, "30", &state);
        assert_eq!(c.verdict, Verdict::Keep);
        assert_eq!(c.why, "pinned by a live worktree's user.bazelrc");

        let r_exists = tmp.join("r_exists");
        fs::create_dir_all(&r_exists).unwrap();
        let other_str = existing_other_ws.to_string_lossy().into_owned();
        fs::write(
            r_exists.join(".vitruvian-worktree"),
            format!("{other_str}\n"),
        )
        .unwrap();
        let c = classify_root(&r_exists.to_string_lossy(), "30", &state);
        assert_eq!(c.verdict, Verdict::Keep);
        assert_eq!(c.why, format!("workspace {other_str} still exists"));

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_pid_parsing_and_nul_stripping() {
        let me = std::process::id().to_string();
        assert!(pid_is_alive_bytes(me.as_bytes()));
        assert!(pid_is_alive_bytes(format!(" {me}").as_bytes()));
        assert!(pid_is_alive_bytes(format!("{me} ").as_bytes()));
        assert!(pid_is_alive_bytes(format!("{me}\t").as_bytes()));
        assert!(!pid_is_alive_bytes(format!("{me}\r").as_bytes()));
        assert!(pid_is_alive_bytes(format!("+{me}").as_bytes()));
        assert!(!pid_is_alive_bytes(b"java"));
        assert!(!pid_is_alive_bytes(b""));

        let tmp = env::temp_dir().join(format!("bazel_cache_nul_{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(tmp.join("server")).unwrap();
        let mut pid_with_nul = Vec::new();
        pid_with_nul.extend_from_slice(me.as_bytes());
        pid_with_nul.push(0);
        pid_with_nul.push(b'\n');
        fs::write(tmp.join("server/server.pid.txt"), &pid_with_nul).unwrap();
        assert_eq!(live_pid(&tmp.to_string_lossy()), me);

        fs::write(tmp.join("DO_NOT_BUILD_HERE"), b"/tmp/foo\0bar\n").unwrap();
        assert_eq!(workspace_of(&tmp.to_string_lossy()), "/tmp/foobar");

        let _ = fs::remove_dir_all(&tmp);
    }
}
