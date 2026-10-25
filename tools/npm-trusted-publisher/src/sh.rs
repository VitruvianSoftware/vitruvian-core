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

//! The bash semantics setup.sh and bootstrap.sh lean on, made explicit.
//!
//! Each helper names the shell construct it stands in for, so a reader can
//! hold the port against the script line by line: `$(...)` capture (trailing
//! newlines and NUL bytes dropped), `2>&1` merged capture, `cd` with a
//! logical `$PWD`, `command -v` / `type -aP`, `[ -r ]` via access(2),
//! `read -r a b c` field splitting, the `find | sort` manifest discovery,
//! `grep -q` with a basic regular expression, and `awk -F '\t'`.

use std::ffi::CString;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom, Write};
use std::os::raw::{c_char, c_int};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::MetadataExt;
use std::os::unix::process::ExitStatusExt;
use std::path::Path;
use std::process::{Command, ExitStatus, Stdio};

extern "C" {
    fn access(path: *const c_char, mode: c_int) -> c_int;
}

pub const R_OK: c_int = 4;
pub const W_OK: c_int = 2;
pub const X_OK: c_int = 1;

/// `[ -r path ]` / `[ -w path ]` / `[ -x path ]`: access(2), which is NOT the
/// same as opening the file -- `/dev/tty` passes it without a controlling
/// terminal and then fails to open.
pub fn can_access(path: &str, mode: c_int) -> bool {
    match CString::new(path.as_bytes()) {
        Ok(c) => unsafe { access(c.as_ptr(), mode) == 0 },
        Err(_) => false,
    }
}

// --- output ------------------------------------------------------------------

/// Write bytes to stdout. Errors (a closed pipe) are ignored, as `echo` to a
/// dead reader is not something these tools can act on.
pub fn out(b: &[u8]) {
    let mut o = std::io::stdout().lock();
    let _ = o.write_all(b);
}

/// `echo "$s"`.
pub fn outln(s: &str) {
    let mut o = std::io::stdout().lock();
    let _ = o.write_all(s.as_bytes());
    let _ = o.write_all(b"\n");
}

/// `echo "$s" >&2`.
pub fn errln(s: &str) {
    let mut e = std::io::stderr().lock();
    let _ = e.write_all(s.as_bytes());
    let _ = e.write_all(b"\n");
}

pub fn err(b: &[u8]) {
    let mut e = std::io::stderr().lock();
    let _ = e.write_all(b);
}

/// Before any child inherits our stdout: what we printed comes first.
pub fn flush() {
    let _ = std::io::stdout().flush();
    let _ = std::io::stderr().flush();
}

/// io::Error text without Rust's " (os error N)" suffix, i.e. strerror(3).
pub fn strerror(e: &std::io::Error) -> String {
    let s = e.to_string();
    match s.find(" (os error ") {
        Some(i) => s[..i].to_string(),
        None => s,
    }
}

// --- environment ---------------------------------------------------------------

/// `${NAME:-default}`: unset and empty both take the default.
pub fn env_or(name: &str, default: &str) -> String {
    match std::env::var(name) {
        Ok(v) if !v.is_empty() => v,
        _ => default.to_string(),
    }
}

/// `[ -n "${NAME:-}" ]`.
pub fn env_set(name: &str) -> bool {
    std::env::var_os(name).map_or(false, |v| !v.is_empty())
}

/// An integer as `[ x -lt y ]` reads it: surrounding blanks allowed, an
/// optional sign, decimal digits. `None` is bash's "integer expression
/// expected".
pub fn parse_int(s: &str) -> Option<i64> {
    let t = s.trim_matches(|c: char| c == ' ' || c == '\t' || c == '\n');
    let digits = t.strip_prefix(|c: char| c == '-' || c == '+').unwrap_or(t);
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    t.parse::<i64>().ok()
}

/// `[ "$a" -lt "$b" ]`, including bash's complaint and false result when
/// either side is not an integer.
pub fn test_lt(prog: &str, a: &str, b: &str) -> bool {
    match (parse_int(a), parse_int(b)) {
        (Some(x), Some(y)) => x < y,
        (None, _) => {
            errln(&format!("{}: [: {}: integer expression expected", prog, a));
            false
        }
        (_, None) => {
            errln(&format!("{}: [: {}: integer expression expected", prog, b));
            false
        }
    }
}

// --- processes -----------------------------------------------------------------

/// An exit status as `$?` reports it: the code, or 128 + the signal.
pub fn code(st: ExitStatus) -> i32 {
    match st.code() {
        Some(c) => c,
        None => 128 + st.signal().unwrap_or(0),
    }
}

/// bash's status and message for a command it could not start.
fn spawn_failure(prog: &str, e: &std::io::Error) -> (i32, String) {
    match e.kind() {
        std::io::ErrorKind::NotFound => {
            if prog.contains('/') {
                (127, format!("{}: No such file or directory\n", prog))
            } else {
                (127, format!("{}: command not found\n", prog))
            }
        }
        std::io::ErrorKind::PermissionDenied => (126, format!("{}: Permission denied\n", prog)),
        _ => (126, format!("{}: {}\n", prog, strerror(e))),
    }
}

/// `$(cmd)` with stderr inherited or (`2>/dev/null`) discarded. Returns the
/// status and stdout with trailing newlines and NUL bytes removed. The CALLER
/// sets stdin: `Command::output` would otherwise default it to null.
pub fn capture(c: &mut Command, stderr_inherit: bool) -> (i32, Vec<u8>) {
    flush();
    let prog = c.get_program().to_string_lossy().into_owned();
    c.stdout(Stdio::piped());
    c.stderr(if stderr_inherit {
        Stdio::inherit()
    } else {
        Stdio::null()
    });
    match c.output() {
        Ok(o) => (code(o.status), subst(o.stdout)),
        Err(e) => {
            let (rc, msg) = spawn_failure(&prog, &e);
            if stderr_inherit {
                err(msg.as_bytes());
            }
            (rc, Vec::new())
        }
    }
}

/// `"$(cmd 2>&1)"`: stdout and stderr through ONE file description, so the
/// interleaving is exactly the order the child wrote in.
pub fn capture_merged(c: &mut Command) -> (i32, Vec<u8>) {
    flush();
    let prog = c.get_program().to_string_lossy().into_owned();
    let (mut f, path) = match scratch_file() {
        Ok(x) => x,
        Err(e) => return (1, format!("{}\n", strerror(&e)).into_bytes()),
    };
    let _ = std::fs::remove_file(&path);
    let (o, e) = match (f.try_clone(), f.try_clone()) {
        (Ok(o), Ok(e)) => (o, e),
        _ => return (1, Vec::new()),
    };
    c.stdout(Stdio::from(o));
    c.stderr(Stdio::from(e));
    let rc = match c.status() {
        Ok(st) => code(st),
        Err(e) => {
            let (rc, msg) = spawn_failure(&prog, &e);
            let _ = f.write_all(msg.as_bytes());
            rc
        }
    };
    let mut buf = Vec::new();
    let _ = f.seek(SeekFrom::Start(0));
    let _ = f.read_to_end(&mut buf);
    (rc, subst(buf))
}

/// A command whose stdout and stderr are ours.
pub fn run_inherit(c: &mut Command) -> i32 {
    flush();
    let prog = c.get_program().to_string_lossy().into_owned();
    match c.status() {
        Ok(st) => code(st),
        Err(e) => {
            let (rc, msg) = spawn_failure(&prog, &e);
            err(msg.as_bytes());
            rc
        }
    }
}

/// A command with every stream discarded (`>/dev/null 2>&1`).
pub fn run_quiet(c: &mut Command) -> i32 {
    c.stdout(Stdio::null()).stderr(Stdio::null());
    match c.status() {
        Ok(st) => code(st),
        Err(e) => spawn_failure("", &e).0,
    }
}

/// `sleep "$arg"`, run as the real sleep(1) so fractional and malformed
/// intervals behave (and complain) exactly as in the script.
pub fn sleep(arg: &str) -> i32 {
    run_inherit(Command::new("sleep").arg(arg))
}

/// `$(...)`'s post-processing: NUL bytes dropped, trailing newlines removed.
pub fn subst(mut v: Vec<u8>) -> Vec<u8> {
    v.retain(|b| *b != 0);
    while v.last() == Some(&b'\n') {
        v.pop();
    }
    v
}

fn scratch_file() -> std::io::Result<(File, std::path::PathBuf)> {
    let dir = std::env::temp_dir();
    for i in 0..100u32 {
        let p = dir.join(format!(
            ".ntp-capture-{}-{}-{}",
            std::process::id(),
            unique(),
            i
        ));
        match std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .open(&p)
        {
            Ok(f) => return Ok((f, p)),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
    Err(std::io::Error::new(
        std::io::ErrorKind::Other,
        "no scratch file",
    ))
}

/// A cheap source of distinct names: time, pid and a counter.
pub fn unique() -> u64 {
    use std::sync::atomic::{AtomicU64, Ordering};
    static N: AtomicU64 = AtomicU64::new(0);
    let t = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0);
    let mut x = t
        ^ ((std::process::id() as u64) << 32)
        ^ N.fetch_add(1, Ordering::Relaxed)
            .wrapping_mul(0x9e37_79b9_7f4a_7c15);
    // splitmix64
    x = x.wrapping_add(0x9e37_79b9_7f4a_7c15);
    x = (x ^ (x >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
    x = (x ^ (x >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
    x ^ (x >> 31)
}

/// `mktemp -d`, by running it: where it puts the directory is platform
/// policy (GNU honours `$TMPDIR`; macOS uses the per-user temp dir).
pub fn mktemp_d() -> Result<String, i32> {
    let (rc, o) = capture(
        Command::new("mktemp").arg("-d").stdin(Stdio::inherit()),
        true,
    );
    if rc != 0 {
        return Err(rc);
    }
    Ok(String::from_utf8_lossy(&o).into_owned())
}

// --- cd, $PWD, the workspace root ---------------------------------------------

/// `$PWD` as bash holds it: the inherited value when it still names the
/// current directory, else getcwd().
pub fn shell_pwd() -> String {
    let cwd = std::env::current_dir()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_default();
    if let Ok(p) = std::env::var("PWD") {
        if p.starts_with('/') {
            if let (Ok(a), Ok(b)) = (std::fs::metadata(&p), std::fs::metadata(".")) {
                if a.dev() == b.dev() && a.ino() == b.ino() {
                    return p;
                }
            }
        }
    }
    cwd
}

/// `cd`'s logical path: `target` against `$PWD`, with `.`, `..` and repeated
/// slashes resolved textually (symlinks are kept, as `cd -L` keeps them).
/// `None` when a component before a `..` is not a directory, where bash
/// abandons the logical path and lets the kernel resolve the raw one.
pub fn logical_path(target: &str, pwd: &str) -> Option<String> {
    let joined = if target.starts_with('/') {
        target.to_string()
    } else {
        format!("{}/{}", pwd, target)
    };
    let mut parts: Vec<&str> = Vec::new();
    for seg in joined.split('/') {
        match seg {
            "" | "." => {}
            ".." => {
                if !Path::new(&format!("/{}", parts.join("/"))).is_dir() {
                    return None;
                }
                parts.pop();
            }
            s => parts.push(s),
        }
    }
    Some(format!("/{}", parts.join("/")))
}

/// `cd "$dir"` for this process: chdir, then export the logical `$PWD` so
/// every child sees what bash's children would.
pub fn cd(dir: &str) -> Result<String, String> {
    let logical = logical_path(dir, &shell_pwd());
    let pwd = match logical.as_deref().map(std::env::set_current_dir) {
        Some(Ok(())) => logical.unwrap_or_default(),
        _ => {
            std::env::set_current_dir(dir).map_err(|e| format!("cd: {}: {}", dir, strerror(&e)))?;
            std::env::current_dir()
                .map(|p| p.to_string_lossy().into_owned())
                .unwrap_or_default()
        }
    };
    std::env::set_var("PWD", &pwd);
    Ok(pwd)
}

/// `cd "${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"`.
/// On failure prints bash's complaint and returns Err (the script exits 1
/// under `set -e`).
pub fn cd_workspace(prog: &str) -> Result<String, ()> {
    let target = match std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        Ok(v) if !v.is_empty() => v,
        _ => {
            let (rc, o) = capture(
                Command::new("git")
                    .args(["rev-parse", "--show-toplevel"])
                    .stdin(Stdio::inherit()),
                false,
            );
            let mut s = o;
            if rc != 0 {
                if !s.is_empty() {
                    s.push(b'\n');
                }
                s.extend_from_slice(shell_pwd().as_bytes());
            }
            String::from_utf8_lossy(&subst(s)).into_owned()
        }
    };
    match cd(&target) {
        Ok(p) => Ok(p),
        Err(m) => {
            errln(&format!("{}: {}", prog, m));
            Err(())
        }
    }
}

/// A child that runs in `dir` with the logical `$PWD` bash's `( cd "$dir" &&
/// ... )` subshell would export.
pub fn in_dir(c: &mut Command, dir: &str) -> Result<(), String> {
    match logical_path(dir, &shell_pwd()) {
        Some(l) if Path::new(&l).is_dir() => {
            c.current_dir(&l);
            c.env("PWD", &l);
            Ok(())
        }
        _ => match std::fs::canonicalize(dir) {
            Ok(p) if p.is_dir() => {
                c.current_dir(&p);
                c.env("PWD", &p);
                Ok(())
            }
            Ok(_) => Err(format!("cd: {}: Not a directory", dir)),
            Err(e) => Err(format!("cd: {}: {}", dir, strerror(&e))),
        },
    }
}

// --- command lookup --------------------------------------------------------------

fn executable_file(p: &str) -> bool {
    std::fs::metadata(p).map_or(false, |m| !m.is_dir()) && can_access(p, X_OK)
}

fn path_dirs() -> Vec<String> {
    let path = std::env::var("PATH").unwrap_or_default();
    path.split(':')
        .map(|d| {
            if d.is_empty() {
                ".".to_string()
            } else {
                d.to_string()
            }
        })
        .collect()
}

fn join_dir(d: &str, name: &str) -> String {
    if d.ends_with('/') {
        format!("{}{}", d, name)
    } else {
        format!("{}/{}", d, name)
    }
}

/// `type -aP name`: every executable `name` along `$PATH`, in order.
pub fn type_ap(name: &str) -> Vec<String> {
    if name.contains('/') {
        return if executable_file(name) {
            vec![name.to_string()]
        } else {
            vec![]
        };
    }
    path_dirs()
        .iter()
        .map(|d| join_dir(d, name))
        .filter(|p| executable_file(p))
        .collect()
}

/// `command -v name` for a non-builtin.
pub fn command_v(name: &str) -> Option<String> {
    if name.is_empty() {
        return None;
    }
    type_ap(name).into_iter().next()
}

// --- read, find, sort ------------------------------------------------------------

/// `read -r v1 .. vn` with the default IFS on the FIRST line of `text`:
/// blank-separated words, the last variable taking the rest of the line.
pub fn read_fields(text: &[u8], n: usize) -> Vec<Vec<u8>> {
    let line = match text.iter().position(|b| *b == b'\n') {
        Some(i) => &text[..i],
        None => text,
    };
    split_ifs(line, n, |b| b == b' ' || b == b'\t' || b == b'\n')
}

/// `IFS=$'\t' read -r v1 .. vn`: tabs are IFS whitespace, so runs collapse
/// and leading/trailing tabs vanish; spaces are ordinary characters.
pub fn read_tab_fields(line: &[u8], n: usize) -> Vec<Vec<u8>> {
    split_ifs(line, n, |b| b == b'\t')
}

fn split_ifs(line: &[u8], n: usize, ws: impl Fn(u8) -> bool) -> Vec<Vec<u8>> {
    let mut out = vec![Vec::new(); n];
    let mut i = 0;
    let len = line.len();
    for (k, slot) in out.iter_mut().enumerate() {
        while i < len && ws(line[i]) {
            i += 1;
        }
        if i >= len {
            break;
        }
        if k == n - 1 {
            let mut end = len;
            while end > i && ws(line[end - 1]) {
                end -= 1;
            }
            *slot = line[i..end].to_vec();
            break;
        }
        let start = i;
        while i < len && !ws(line[i]) {
            i += 1;
        }
        *slot = line[start..i].to_vec();
    }
    out
}

/// Lines a `while read` loop over a heredoc (or a file) actually visits: a
/// final line with no newline is NOT visited, because `read` fails at EOF.
pub fn read_loop_lines(data: &[u8]) -> Vec<&[u8]> {
    let mut v: Vec<&[u8]> = data.split(|b| *b == b'\n').collect();
    v.pop(); // the segment after the last newline (empty, or unterminated)
    v
}

/// `find ROOTS -maxdepth 2 -name package.json -not -path '*/node_modules/*'
/// 2>/dev/null | sort`, in byte order. Like find's default `-P`, symbolic
/// links are never descended -- not even a root that is one.
pub fn find_manifests(roots: &[String]) -> Vec<String> {
    let mut found: Vec<String> = Vec::new();
    let keep = |p: &str, found: &mut Vec<String>| {
        if !p.contains("/node_modules/") {
            found.push(p.to_string());
        }
    };
    for root in roots {
        let meta = match std::fs::symlink_metadata(root) {
            Ok(m) => m,
            Err(_) => continue,
        };
        if Path::new(root)
            .file_name()
            .map_or(false, |n| n == "package.json")
        {
            keep(root, &mut found);
        }
        if !meta.is_dir() {
            continue;
        }
        let mut entries: Vec<_> = match std::fs::read_dir(root) {
            Ok(rd) => rd.filter_map(|e| e.ok()).collect(),
            Err(_) => continue,
        };
        entries.sort_by_key(|e| e.file_name());
        for e in entries {
            let name = e.file_name();
            let p1 = join_dir(root, &name.to_string_lossy());
            if name.as_bytes() == b"package.json" {
                keep(&p1, &mut found);
            }
            let is_dir = e.file_type().map_or(false, |t| t.is_dir());
            if !is_dir {
                continue;
            }
            if let Ok(rd) = std::fs::read_dir(&p1) {
                for e2 in rd.filter_map(|e| e.ok()) {
                    if e2.file_name().as_bytes() == b"package.json" {
                        keep(&join_dir(&p1, "package.json"), &mut found);
                    }
                }
            }
        }
    }
    found.sort_by(|a, b| a.as_bytes().cmp(b.as_bytes()));
    found
}

/// `$(...)` word splitting of a whitespace-separated list (`for x in $list`).
/// Pathname expansion of the words is not performed.
pub fn words(s: &str) -> Vec<String> {
    s.split(|c: char| c == ' ' || c == '\t' || c == '\n')
        .filter(|w| !w.is_empty())
        .map(String::from)
        .collect()
}

/// `dirname`.
pub fn dirname(p: &str) -> String {
    let t = p.trim_end_matches('/');
    if t.is_empty() {
        return if p.starts_with('/') {
            "/".into()
        } else {
            ".".into()
        };
    }
    match t.rfind('/') {
        None => ".".into(),
        Some(i) => {
            let d = t[..i].trim_end_matches('/');
            if d.is_empty() {
                "/".into()
            } else {
                d.to_string()
            }
        }
    }
}

// --- grep ------------------------------------------------------------------------

/// The lines grep sees in `$(...)`-style text.
pub fn lines(text: &[u8]) -> Vec<&[u8]> {
    if text.is_empty() {
        return Vec::new();
    }
    let t = if text.last() == Some(&b'\n') {
        &text[..text.len() - 1]
    } else {
        text
    };
    t.split(|b| *b == b'\n').collect()
}

/// `grep -q FIXED` (case-sensitive substring on some line).
pub fn grep_fixed(text: &[u8], needle: &str) -> bool {
    lines(text).iter().any(|l| contains(l, needle.as_bytes()))
}

/// `grep -i FIXED` lines (ASCII case folding, as in the C locale).
pub fn grep_i_lines<'a>(text: &'a [u8], needle: &str) -> Vec<&'a [u8]> {
    let n = needle.to_ascii_lowercase();
    lines(text)
        .into_iter()
        .filter(|l| contains(&l.to_ascii_lowercase(), n.as_bytes()))
        .collect()
}

pub fn contains(hay: &[u8], needle: &[u8]) -> bool {
    needle.is_empty() || hay.windows(needle.len()).any(|w| w == needle)
}

#[derive(Debug, Clone, PartialEq)]
enum Atom {
    Lit(u8),
    Any,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Bre {
    start: bool,
    end: bool,
    items: Vec<(Atom, bool)>, // (atom, starred)
}

/// The basic-regular-expression subset workflow file names use: literals,
/// `.`, `*`, a leading `^`, a trailing `$`, and `\` before a special
/// character. Anything else (brackets, groups, intervals, back-references,
/// GNU `\+`, a leading `-` grep would read as an option, a newline) is
/// `None`, and the caller hands the pattern to the system grep instead.
pub fn parse_bre(pat: &str) -> Option<Bre> {
    let b = pat.as_bytes();
    if b.first() == Some(&b'-') || b.contains(&b'\n') || b.contains(&b'[') {
        return None;
    }
    let mut i = 0;
    let mut start = false;
    if b.first() == Some(&b'^') {
        start = true;
        i = 1;
    }
    let mut end = false;
    let mut stop = b.len();
    if stop > i && b[stop - 1] == b'$' {
        // An escaped `\$` at the end is a literal, not the anchor.
        let mut bs = 0;
        let mut k = stop - 1;
        while k > i && b[k - 1] == b'\\' {
            bs += 1;
            k -= 1;
        }
        if bs % 2 == 0 {
            end = true;
            stop -= 1;
        }
    }
    let mut items: Vec<(Atom, bool)> = Vec::new();
    while i < stop {
        let c = b[i];
        match c {
            b'\\' => {
                if i + 1 >= stop {
                    return None;
                }
                let n = b[i + 1];
                if b".*[]^$\\/".contains(&n) {
                    items.push((Atom::Lit(n), false));
                    i += 2;
                } else {
                    return None;
                }
            }
            b'*' => {
                match items.last_mut() {
                    // `*` at the start (after any `^`) is a literal.
                    None => items.push((Atom::Lit(b'*'), false)),
                    Some(last) if last.1 => {} // `a**` == `a*`
                    Some(last) => last.1 = true,
                }
                i += 1;
            }
            b'.' => {
                items.push((Atom::Any, false));
                i += 1;
            }
            _ => {
                items.push((Atom::Lit(c), false));
                i += 1;
            }
        }
    }
    Some(Bre { start, end, items })
}

impl Bre {
    pub fn is_match(&self, line: &[u8]) -> bool {
        if self.start {
            return self.m(0, line, 0);
        }
        (0..=line.len()).any(|s| self.m(0, line, s))
    }

    fn m(&self, k: usize, line: &[u8], pos: usize) -> bool {
        if k == self.items.len() {
            return !self.end || pos == line.len();
        }
        let (atom, star) = &self.items[k];
        let one = |p: usize| {
            p < line.len()
                && match atom {
                    Atom::Any => true,
                    Atom::Lit(c) => line[p] == *c,
                }
        };
        if *star {
            let mut p = pos;
            let mut stops = vec![p];
            while one(p) {
                p += 1;
                stops.push(p);
            }
            stops.into_iter().rev().any(|q| self.m(k + 1, line, q))
        } else {
            one(pos) && self.m(k + 1, line, pos + 1)
        }
    }
}

/// `grep -q "$pattern"` over `text`: true when some line matches.
pub fn grep_q_bre(text: &[u8], pattern: &str) -> bool {
    match parse_bre(pattern) {
        Some(re) => lines(text).iter().any(|l| re.is_match(l)),
        None => {
            // Outside the native subset: ask grep itself, exactly as the
            // script does (its stderr, e.g. "invalid option", is ours).
            flush();
            let child = Command::new("grep")
                .arg("-q")
                .arg(pattern)
                .stdin(Stdio::piped())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .spawn();
            match child {
                Ok(mut ch) => {
                    if let Some(mut si) = ch.stdin.take() {
                        let _ = si.write_all(text);
                    }
                    ch.wait().map_or(false, |s| s.success())
                }
                Err(_) => false,
            }
        }
    }
}

// --- awk ---------------------------------------------------------------------------

/// The escape processing `awk -v var=value` applies to `value`.
pub fn awk_v_unescape(s: &str) -> Vec<u8> {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] != b'\\' || i + 1 >= b.len() {
            out.push(b[i]);
            i += 1;
            continue;
        }
        let n = b[i + 1];
        i += 2;
        match n {
            b'n' => out.push(b'\n'),
            b't' => out.push(b'\t'),
            b'r' => out.push(b'\r'),
            b'\\' => out.push(b'\\'),
            b'"' => out.push(b'"'),
            b'/' => out.push(b'/'),
            b'a' => out.push(7),
            b'b' => out.push(8),
            b'f' => out.push(12),
            b'v' => out.push(11),
            b'0'..=b'7' => {
                let mut v: u32 = (n - b'0') as u32;
                let mut k = 0;
                while k < 2 && i < b.len() && (b'0'..=b'7').contains(&b[i]) {
                    v = v * 8 + (b[i] - b'0') as u32;
                    i += 1;
                    k += 1;
                }
                out.push(v as u8);
            }
            other => {
                out.push(b'\\');
                out.push(other);
            }
        }
    }
    out
}

/// `awk -F '\t' -v mf="$mf" -v n="$n" '$1 == mf { print $n; exit }' file`,
/// through `$(...)`: field `n` of the first row whose first tab-separated
/// field is `mf` (single tabs separate; empty fields count).
pub fn awk_tab_field(data: &[u8], mf: &str, n: usize) -> Vec<u8> {
    let want = awk_v_unescape(mf);
    for rec in lines(data) {
        let fields: Vec<&[u8]> = rec.split(|b| *b == b'\t').collect();
        if fields[0] == want.as_slice() {
            return subst(fields.get(n - 1).map(|f| f.to_vec()).unwrap_or_default());
        }
    }
    Vec::new()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(v: &[Vec<u8>]) -> Vec<String> {
        v.iter()
            .map(|x| String::from_utf8_lossy(x).into_owned())
            .collect()
    }

    #[test]
    fn read_splits_like_bash() {
        assert_eq!(s(&read_fields(b"  a b  c d \nzzz", 3)), ["a", "b", "c d"]);
        assert_eq!(s(&read_fields(b"a", 3)), ["a", "", ""]);
        assert_eq!(
            s(&read_tab_fields(b"\ta\t\tb\tc\t", 4)),
            ["a", "b", "c", ""]
        );
        assert_eq!(
            s(&read_tab_fields(b"a b\tc\td\te\tf\t", 4)),
            ["a b", "c", "d", "e\tf"]
        );
    }

    #[test]
    fn read_loop_skips_unterminated_last_line() {
        assert_eq!(read_loop_lines(b"a\nb\nc"), vec![&b"a"[..], &b"b"[..]]);
        assert_eq!(read_loop_lines(b"a\n"), vec![&b"a"[..]]);
    }

    #[test]
    fn bre_subset() {
        let m = |p: &str, l: &str| parse_bre(p).unwrap().is_match(l.as_bytes());
        assert!(m("release.yml", "xx release.yml yy"));
        assert!(m("release.yml", "releaseXyml"));
        assert!(!m("release\\.yml", "releaseXyml"));
        assert!(m("^rel", "release"));
        assert!(!m("^rel", " release"));
        assert!(m("yml$", "release.yml"));
        assert!(!m("yml$", "release.yml "));
        assert!(m("re*lease", "rlease"));
        assert!(m("*x", "a*x"));
        assert!(m("", "anything"));
        assert!(m("a$b", "a$b"));
        assert!(parse_bre("-x").is_none());
        assert!(parse_bre("[r]x").is_none());
        assert!(parse_bre("a\\+").is_none());
    }

    #[test]
    fn awk_fields() {
        let d = b"a\t\tw\nb\tr\tw2\n";
        assert_eq!(awk_tab_field(d, "a", 2), b"");
        assert_eq!(awk_tab_field(d, "a", 3), b"w");
        assert_eq!(awk_tab_field(d, "b", 2), b"r");
        assert_eq!(awk_tab_field(d, "c", 2), b"");
    }

    #[test]
    fn paths() {
        assert_eq!(logical_path("x/./y//z", "/"), Some("/x/y/z".to_string()));
        assert_eq!(logical_path("/", "/a"), Some("/".to_string()));
        assert_eq!(logical_path("../tmp", "/"), Some("/tmp".to_string()));
        assert_eq!(logical_path("/no/such/dir/../x", "/"), None);
        assert_eq!(dirname("a/b/package.json"), "a/b");
        assert_eq!(dirname("package.json"), ".");
        assert_eq!(dirname("/package.json"), "/");
    }

    #[test]
    fn ints() {
        assert_eq!(parse_int(" 5 "), Some(5));
        assert_eq!(parse_int("-3"), Some(-3));
        assert_eq!(parse_int("1.5"), None);
        assert_eq!(parse_int(""), None);
    }
}
