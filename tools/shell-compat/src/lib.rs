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

//! The handful of bash and coreutils behaviours the Rust ports of the
//! credential tools in tools/ have to reproduce exactly: `command -v`,
//! `$(...)` capture, `${#var}`, `read -r`, `sed 's/^/  /'`, `grep -qi`,
//! `mktemp`, `umask`, `dirname`, and IFS word splitting.
//!
//! Byte strings throughout, as bash has them: an argument or a file need not
//! be UTF-8, and a port that decoded it would print something the script
//! never did.

use std::ffi::{OsStr, OsString};
use std::fs;
use std::io::{self, Read, Write};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

// ---------------------------------------------------------------------------
// environment
// ---------------------------------------------------------------------------

/// `$NAME`, as bytes; None when unset.
pub fn env(name: &str) -> Option<Vec<u8>> {
    std::env::var_os(name).map(OsString::into_vec)
}

/// `${NAME:-}`: the value, or empty when unset.
pub fn env_or_empty(name: &str) -> Vec<u8> {
    env(name).unwrap_or_default()
}

/// `${NAME:-default}`: the value when set AND non-empty, else `default`.
pub fn env_or(name: &str, default: &[u8]) -> Vec<u8> {
    match env(name) {
        Some(v) if !v.is_empty() => v,
        _ => default.to_vec(),
    }
}

/// `[ -n "${NAME:-}" ]`.
pub fn env_set_nonempty(name: &str) -> bool {
    env(name).map_or(false, |v| !v.is_empty())
}

pub fn os(b: &[u8]) -> &OsStr {
    OsStr::from_bytes(b)
}

pub fn path(b: &[u8]) -> PathBuf {
    PathBuf::from(OsStr::from_bytes(b))
}

pub fn path_bytes(p: &Path) -> Vec<u8> {
    p.as_os_str().as_bytes().to_vec()
}

// ---------------------------------------------------------------------------
// output
// ---------------------------------------------------------------------------

/// Write to stdout and flush, so it interleaves with children's output in the
/// order the script produces it.
pub fn out(b: &[u8]) {
    let mut o = io::stdout().lock();
    let _ = o.write_all(b);
    let _ = o.flush();
}

/// Write to stderr (unbuffered in std already).
pub fn err(b: &[u8]) {
    let _ = io::stderr().lock().write_all(b);
}

/// Concatenate byte-ish pieces: `cat(&[b"a", name, b"\n"])`.
pub fn cat(parts: &[&[u8]]) -> Vec<u8> {
    let mut v = Vec::new();
    for p in parts {
        v.extend_from_slice(p);
    }
    v
}

// ---------------------------------------------------------------------------
// command lookup and capture
// ---------------------------------------------------------------------------

fn is_executable_file(p: &Path) -> bool {
    match fs::metadata(p) {
        Ok(m) => m.is_file() && m.permissions().mode() & 0o111 != 0,
        Err(_) => false,
    }
}

/// `command -v NAME` for an external command: a name with a `/` is checked
/// as it stands, any other is looked up on `$PATH` (an empty entry is the
/// current directory).
pub fn which(name: &[u8]) -> Option<PathBuf> {
    if name.is_empty() {
        return None;
    }
    if name.contains(&b'/') {
        let p = path(name);
        return if is_executable_file(&p) {
            Some(p)
        } else {
            None
        };
    }
    let path_var = env_or_empty("PATH");
    for dir in path_var.split(|&c| c == b':') {
        let d = if dir.is_empty() { b"." as &[u8] } else { dir };
        let mut cand = path(d);
        cand.push(os(name));
        if is_executable_file(&cand) {
            return Some(cand);
        }
    }
    None
}

/// What `$(...)` makes of a command's output: NUL bytes dropped, every
/// trailing newline removed.
pub fn subst(mut v: Vec<u8>) -> Vec<u8> {
    v.retain(|&c| c != 0);
    while v.last() == Some(&b'\n') {
        v.pop();
    }
    v
}

/// `tr -d '\r\n'`.
pub fn strip_cr_lf(v: &[u8]) -> Vec<u8> {
    v.iter()
        .copied()
        .filter(|&c| c != b'\r' && c != b'\n')
        .collect()
}

/// A finished child: its exit status the way `$?` reports it (128+N for a
/// signal), and whatever was captured.
pub struct Ran {
    pub status: i32,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

impl Ran {
    pub fn ok(&self) -> bool {
        self.status == 0
    }
}

pub fn status_code(st: std::process::ExitStatus) -> i32 {
    use std::os::unix::process::ExitStatusExt;
    if let Some(c) = st.code() {
        c
    } else if let Some(sig) = st.signal() {
        128 + sig
    } else {
        1
    }
}

/// The status bash reports for a command it could not start: 127 when it was
/// not found, 126 when it was found but could not be executed.
pub fn spawn_failure_status(e: &io::Error) -> i32 {
    if e.kind() == io::ErrorKind::NotFound {
        127
    } else {
        126
    }
}

/// What bash prints when it cannot start a command:
/// `<script>: line <n>: <cmd>: command not found` for a bare name missing
/// from PATH, `<script>: line <n>: <path>: <strerror>` otherwise. `line` is
/// the line of the script the port mirrors.
pub fn spawn_diag(line: u32, cmd: &Command, e: &io::Error) -> Vec<u8> {
    let prog = std::env::args_os()
        .next()
        .map(OsString::into_vec)
        .unwrap_or_default();
    let name = cmd.get_program().as_bytes().to_vec();
    let what = if !name.contains(&b'/') && e.kind() == io::ErrorKind::NotFound {
        "command not found".to_string()
    } else {
        strerror(e)
    };
    cat(&[
        &prog,
        format!(": line {}: ", line).as_bytes(),
        &name,
        b": ",
        what.as_bytes(),
        b"\n",
    ])
}

/// Run `cmd`, stdin inherited (a command substitution inherits it), stdout
/// and stderr captured. A command that cannot start reports what bash would,
/// its diagnostic in the captured stderr (`line`: see spawn_diag).
pub fn capture(line: u32, cmd: &mut Command) -> Ran {
    cmd.stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    match cmd.output() {
        Ok(o) => Ran {
            status: status_code(o.status),
            stdout: o.stdout,
            stderr: o.stderr,
        },
        Err(e) => Ran {
            status: spawn_failure_status(&e),
            stdout: Vec::new(),
            stderr: spawn_diag(line, cmd, &e),
        },
    }
}

/// Run `cmd` with stdout captured and stderr passed through to ours (where a
/// failure to start is reported).
pub fn capture_stdout(line: u32, cmd: &mut Command) -> Ran {
    cmd.stdout(Stdio::piped()).stderr(Stdio::inherit());
    match cmd.spawn() {
        Ok(child) => match child.wait_with_output() {
            Ok(o) => Ran {
                status: status_code(o.status),
                stdout: o.stdout,
                stderr: Vec::new(),
            },
            Err(_) => Ran {
                status: 1,
                stdout: Vec::new(),
                stderr: Vec::new(),
            },
        },
        Err(e) => {
            err(&spawn_diag(line, cmd, &e));
            Ran {
                status: spawn_failure_status(&e),
                stdout: Vec::new(),
                stderr: Vec::new(),
            }
        }
    }
}

/// Run `cmd` to completion with whatever stdio it was given; the status. A
/// failure to start is reported on our stderr unless `quiet` (the script
/// sent the command's stderr to /dev/null, which bash's message follows).
pub fn status(line: u32, cmd: &mut Command, quiet: bool) -> i32 {
    match cmd.status() {
        Ok(st) => status_code(st),
        Err(e) => {
            if !quiet {
                err(&spawn_diag(line, cmd, &e));
            }
            spawn_failure_status(&e)
        }
    }
}

/// Run `cmd` feeding `input` on its stdin. A write the child refuses (it
/// exited without reading) counts as failure, as `printf | cmd` does under
/// pipefail. `quiet` as for `status`.
pub fn status_with_input(line: u32, cmd: &mut Command, input: &[u8], quiet: bool) -> i32 {
    cmd.stdin(Stdio::piped());
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            if !quiet {
                err(&spawn_diag(line, cmd, &e));
            }
            return spawn_failure_status(&e);
        }
    };
    let wrote = {
        let mut sin = child.stdin.take().expect("piped stdin");
        sin.write_all(input).is_ok()
    };
    let st = match child.wait() {
        Ok(st) => status_code(st),
        Err(_) => 1,
    };
    if st != 0 {
        st
    } else if !wrote {
        // printf died of SIGPIPE.
        141
    } else {
        0
    }
}

// ---------------------------------------------------------------------------
// text
// ---------------------------------------------------------------------------

/// Whether the active locale is a UTF-8 one (the first set of LC_ALL,
/// LC_CTYPE, LANG), which is what decides how bash counts `${#var}`.
pub fn utf8_locale() -> bool {
    for name in ["LC_ALL", "LC_CTYPE", "LANG"] {
        if let Some(v) = env(name) {
            if !v.is_empty() {
                let l: Vec<u8> = v.iter().map(|c| c.to_ascii_lowercase()).collect();
                return contains(&l, b"utf-8") || contains(&l, b"utf8");
            }
        }
    }
    false
}

/// `${#var}`: characters in a UTF-8 locale (a byte that cannot start or
/// continue a character counts as one), bytes otherwise.
pub fn char_len(s: &[u8]) -> usize {
    if !utf8_locale() {
        return s.len();
    }
    match std::str::from_utf8(s) {
        Ok(t) => t.chars().count(),
        Err(_) => {
            // Lossy: each invalid byte is its own character, as bash's
            // mbrlen fallback counts it.
            let mut n = 0;
            let mut rest = s;
            while !rest.is_empty() {
                match std::str::from_utf8(rest) {
                    Ok(t) => {
                        n += t.chars().count();
                        break;
                    }
                    Err(e) => {
                        let good = e.valid_up_to();
                        n += std::str::from_utf8(&rest[..good]).map_or(0, |t| t.chars().count());
                        let bad = e.error_len().unwrap_or(rest.len() - good).max(1);
                        n += bad;
                        rest = &rest[good + bad..];
                    }
                }
            }
            n
        }
    }
}

pub fn contains(hay: &[u8], needle: &[u8]) -> bool {
    if needle.is_empty() {
        return true;
    }
    hay.windows(needle.len()).any(|w| w == needle)
}

/// `grep -qi 'a\|b\|c'` over `text`: any line holding any of the needles,
/// ASCII case folded. (No needle spans a newline, so the whole text will do.)
pub fn grep_qi(text: &[u8], needles: &[&str]) -> bool {
    let low: Vec<u8> = text.iter().map(|c| c.to_ascii_lowercase()).collect();
    needles
        .iter()
        .any(|n| contains(&low, n.to_ascii_lowercase().as_bytes()))
}

/// `grep -q '^PREFIX'`: some line starts with `prefix`.
pub fn grep_q_line_start(text: &[u8], prefix: &[u8]) -> bool {
    text.split(|&c| c == b'\n').any(|l| l.starts_with(prefix))
}

/// `sed 's/^/  /'`: every line indented two spaces; a last line without a
/// newline keeps going without one, and empty input stays empty.
pub fn indent(text: &[u8]) -> Vec<u8> {
    let mut v = Vec::with_capacity(text.len() + 16);
    if text.is_empty() {
        return v;
    }
    let mut at_line_start = true;
    for &c in text {
        if at_line_start {
            v.extend_from_slice(b"  ");
            at_line_start = false;
        }
        v.push(c);
        if c == b'\n' {
            at_line_start = true;
        }
    }
    v
}

/// `head -1 FILE` captured with `$(...)`: the first line without its newline.
pub fn first_line(text: &[u8]) -> Vec<u8> {
    match text.iter().position(|&c| c == b'\n') {
        Some(i) => text[..i].to_vec(),
        None => text.to_vec(),
    }
}

/// `printf '%-Ns'`: left-justified, padded with spaces to `width` bytes.
pub fn pad_right(s: &[u8], width: usize) -> Vec<u8> {
    let mut v = s.to_vec();
    while v.len() < width {
        v.push(b' ');
    }
    v
}

/// Unquoted `$x` in a word list: split on runs of space, tab and newline
/// (the default IFS), empty fields dropped.
pub fn ifs_split(s: &[u8]) -> Vec<Vec<u8>> {
    s.split(|&c| c == b' ' || c == b'\t' || c == b'\n')
        .filter(|w| !w.is_empty())
        .map(<[u8]>::to_vec)
        .collect()
}

/// `IFS=<ifs> read -r v1 v2 ... vN <<<"$line"` for a single-line input:
/// fields split on `ifs`, the last variable taking the rest of the line. IFS
/// whitespace (space, tab, newline) in `ifs` is trimmed at both ends and runs
/// of it delimit once; any other IFS byte delimits on every occurrence.
pub fn read_fields(line: &[u8], ifs: &[u8], n: usize) -> Vec<Vec<u8>> {
    let is_ifs = |c: u8| ifs.contains(&c);
    let is_ws = |c: u8| is_ifs(c) && (c == b' ' || c == b'\t' || c == b'\n');
    let mut s = line;
    while let Some((&c, rest)) = s.split_first() {
        if is_ws(c) {
            s = rest;
        } else {
            break;
        }
    }
    let mut fields: Vec<Vec<u8>> = Vec::new();
    while fields.len() + 1 < n {
        if s.is_empty() {
            break;
        }
        let end = s.iter().position(|&c| is_ifs(c)).unwrap_or(s.len());
        fields.push(s[..end].to_vec());
        s = &s[end..];
        // Consume the delimiter: surrounding IFS whitespace plus at most one
        // non-whitespace IFS byte.
        while let Some((&c, rest)) = s.split_first() {
            if is_ws(c) {
                s = rest;
            } else {
                break;
            }
        }
        if let Some((&c, rest)) = s.split_first() {
            if is_ifs(c) && !is_ws(c) {
                s = rest;
                while let Some((&c2, rest2)) = s.split_first() {
                    if is_ws(c2) {
                        s = rest2;
                    } else {
                        break;
                    }
                }
            }
        }
    }
    if fields.len() < n {
        // The last variable gets the remainder, trailing IFS whitespace cut;
        // when that remainder is one field and a single delimiter, the
        // delimiter goes too ("y:" -> "y", but "y:z:" stays).
        let mut rest = s.to_vec();
        while rest.last().map_or(false, |&c| is_ws(c)) {
            rest.pop();
        }
        if let Some(&c) = rest.last() {
            if is_ifs(c) && !is_ws(c) {
                let mut head = rest[..rest.len() - 1].to_vec();
                while head.last().map_or(false, |&c| is_ws(c)) {
                    head.pop();
                }
                if !head.iter().any(|&c| is_ifs(c)) {
                    rest = head;
                }
            }
        }
        fields.push(rest);
    }
    while fields.len() < n {
        fields.push(Vec::new());
    }
    fields
}

/// `read -r` with the default IFS on one line: leading and trailing spaces
/// and tabs trimmed.
pub fn read_trim(line: &[u8]) -> Vec<u8> {
    read_fields(line, b" \t\n", 1).remove(0)
}

/// Lines of `text` as a `while read` over `<<<"$text"` sees them.
pub fn lines(text: &[u8]) -> Vec<Vec<u8>> {
    let mut v: Vec<Vec<u8>> = text.split(|&c| c == b'\n').map(<[u8]>::to_vec).collect();
    if text.ends_with(b"\n") {
        v.pop();
    }
    v
}

// ---------------------------------------------------------------------------
// paths and files
// ---------------------------------------------------------------------------

/// `dirname`.
pub fn dirname(p: &[u8]) -> Vec<u8> {
    let mut s = p;
    while s.len() > 1 && s.ends_with(b"/") {
        s = &s[..s.len() - 1];
    }
    match s.iter().rposition(|&c| c == b'/') {
        None => b".".to_vec(),
        Some(i) => {
            let mut d = &s[..i];
            while d.len() > 1 && d.ends_with(b"/") {
                d = &d[..d.len() - 1];
            }
            if d.is_empty() {
                b"/".to_vec()
            } else {
                d.to_vec()
            }
        }
    }
}

/// `basename`.
pub fn basename(p: &[u8]) -> Vec<u8> {
    let mut s = p;
    while s.len() > 1 && s.ends_with(b"/") {
        s = &s[..s.len() - 1];
    }
    if s == b"/" {
        return b"/".to_vec();
    }
    match s.iter().rposition(|&c| c == b'/') {
        None => s.to_vec(),
        Some(i) => s[i + 1..].to_vec(),
    }
}

/// `[ -f P ]`.
pub fn is_file(p: &[u8]) -> bool {
    fs::metadata(path(p)).map_or(false, |m| m.is_file())
}

/// `[ -d P ]`.
pub fn is_dir(p: &[u8]) -> bool {
    fs::metadata(path(p)).map_or(false, |m| m.is_dir())
}

/// `[ -e P ]`.
pub fn exists(p: &[u8]) -> bool {
    fs::metadata(path(p)).is_ok()
}

extern "C" {
    #[link_name = "access"]
    fn c_access(path: *const std::ffi::c_char, mode: std::ffi::c_int) -> std::ffi::c_int;
}

/// `[ -r P ]`: access(2) says this user may read it, as test(1) asks. (So
/// /dev/tty passes even with no controlling terminal to open.)
pub fn is_readable(p: &[u8]) -> bool {
    let c = match std::ffi::CString::new(p.to_vec()) {
        Ok(c) => c,
        Err(_) => return false,
    };
    // SAFETY: c is a valid NUL-terminated string for the call's duration.
    unsafe { c_access(c.as_ptr(), 4) == 0 }
}

const ALNUM: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

fn random_suffix(n: usize) -> Vec<u8> {
    use std::collections::hash_map::RandomState;
    use std::hash::{BuildHasher, Hasher};
    let mut out = Vec::with_capacity(n);
    let mut h = RandomState::new().build_hasher();
    h.write_u128(
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos()),
    );
    h.write_u32(std::process::id());
    let mut x = h.finish();
    for _ in 0..n {
        if x < ALNUM.len() as u64 {
            let mut h2 = RandomState::new().build_hasher();
            h2.write_u64(x);
            x = h2.finish() | (1 << 63);
        }
        out.push(ALNUM[(x % ALNUM.len() as u64) as usize]);
        x /= ALNUM.len() as u64;
    }
    out
}

/// `${TMPDIR:-/tmp}` with any trailing slash dropped.
pub fn tmpdir() -> Vec<u8> {
    let mut t = env_or("TMPDIR", b"/tmp");
    while t.len() > 1 && t.ends_with(b"/") {
        t.pop();
    }
    t
}

/// `mktemp TEMPLATE` where TEMPLATE ends in X's: a new mode-0600 file.
pub fn mktemp_file(template: &[u8]) -> io::Result<Vec<u8>> {
    use std::os::unix::fs::OpenOptionsExt;
    let xs = template.iter().rev().take_while(|&&c| c == b'X').count();
    let stem = &template[..template.len() - xs];
    for _ in 0..100 {
        let mut p = stem.to_vec();
        p.extend(random_suffix(xs.max(1)));
        match fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(path(&p))
        {
            Ok(_) => return Ok(p),
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
    Err(io::Error::new(
        io::ErrorKind::AlreadyExists,
        "mktemp: too many tries",
    ))
}

/// `mktemp -d`: a new mode-0700 directory `$TMPDIR/tmp.XXXXXXXXXX`.
pub fn mktemp_dir() -> io::Result<Vec<u8>> {
    use std::os::unix::fs::DirBuilderExt;
    for _ in 0..100 {
        let p = cat(&[&tmpdir(), b"/tmp.", &random_suffix(10)]);
        match fs::DirBuilder::new().mode(0o700).create(path(&p)) {
            Ok(()) => return Ok(p),
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
    Err(io::Error::new(
        io::ErrorKind::AlreadyExists,
        "mktemp: too many tries",
    ))
}

/// `mkdir -p` with directories made mode 0777 & ~umask, as mkdir does.
pub fn mkdir_p(p: &[u8]) -> io::Result<()> {
    fs::create_dir_all(path(p))
}

#[cfg(target_os = "macos")]
type ModeT = u16;
#[cfg(not(target_os = "macos"))]
type ModeT = u32;

extern "C" {
    #[link_name = "umask"]
    fn c_umask(mask: ModeT) -> ModeT;
}

/// `umask MASK`; the previous mask. Affects this process and every child it
/// starts afterwards, as the builtin does.
pub fn umask(mask: u32) -> u32 {
    // SAFETY: umask(2) cannot fail and touches no memory.
    unsafe { c_umask(mask as ModeT) as u32 }
}

/// `printf '%s' DATA >FILE` (create or truncate), with the file made mode
/// `mode` & ~umask when it is new.
pub fn write_file(p: &[u8], data: &[u8], mode: u32) -> io::Result<()> {
    use std::os::unix::fs::OpenOptionsExt;
    let mut f = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(mode)
        .open(path(p))?;
    f.write_all(data)
}

/// strerror(3) text for an I/O error: its Display without std's
/// " (os error N)" suffix.
pub fn strerror(e: &io::Error) -> String {
    let s = e.to_string();
    match s.rfind(" (os error ") {
        Some(i) => s[..i].to_string(),
        None => s,
    }
}

/// The diagnostic bash prints when a redirection cannot be opened:
/// `<script>: line <n>: <file>: <strerror>`. The script is this program.
pub fn redirect_error(line: u32, file: &[u8], e: &io::Error) {
    let prog = std::env::args_os()
        .next()
        .map(OsString::into_vec)
        .unwrap_or_default();
    err(&cat(&[
        &prog,
        format!(": line {}: ", line).as_bytes(),
        file,
        b": ",
        strerror(e).as_bytes(),
        b"\n",
    ]));
}

// ---------------------------------------------------------------------------
// signals
// ---------------------------------------------------------------------------

static CAUGHT: std::sync::atomic::AtomicI32 = std::sync::atomic::AtomicI32::new(0);

extern "C" fn record_signal(sig: std::ffi::c_int) {
    CAUGHT.store(sig, std::sync::atomic::Ordering::SeqCst);
}

extern "C" {
    #[link_name = "signal"]
    fn c_signal(sig: std::ffi::c_int, handler: usize) -> usize;
}

const EXIT_SIGNALS: [std::ffi::c_int; 3] = [1, 2, 15]; // SIGHUP, SIGINT, SIGTERM

/// The port's stand-in for an EXIT trap: from here on SIGHUP, SIGINT and
/// SIGTERM are only recorded, so the tool gets to remove what it must (a
/// decrypted archive, say) and then exit 128+N (see caught_signal). A child
/// in the foreground gets the terminal's Ctrl-C itself and dies of it, so
/// the step that ran it fails and the tool unwinds.
pub fn record_exit_signals() {
    for s in EXIT_SIGNALS {
        // SAFETY: record_signal only stores to an atomic, which is
        // async-signal-safe.
        unsafe {
            c_signal(s, record_signal as usize);
        }
    }
}

/// Back to the default (die at once) for SIGHUP, SIGINT and SIGTERM: for a
/// prompt, where a recorded Ctrl-C would leave the read waiting.
pub fn default_exit_signals() {
    for s in EXIT_SIGNALS {
        // SAFETY: SIG_DFL (0) is always a valid disposition.
        unsafe {
            c_signal(s, 0);
        }
    }
}

/// The signal recorded since record_exit_signals, if any.
pub fn caught_signal() -> Option<i32> {
    match CAUGHT.load(std::sync::atomic::Ordering::SeqCst) {
        0 => None,
        s => Some(s),
    }
}

// ---------------------------------------------------------------------------
// input
// ---------------------------------------------------------------------------

/// `IFS= read -r line` from `r`, one byte at a time so nothing past the
/// newline is consumed (a child started afterwards inherits the rest). NUL
/// bytes are dropped. Returns the line and whether a newline ended it (the
/// builtin's exit status).
pub fn read_line_raw<R: Read>(r: &mut R) -> (Vec<u8>, bool) {
    let mut v = Vec::new();
    let mut b = [0u8; 1];
    loop {
        match r.read(&mut b) {
            Ok(0) => return (v, false),
            Ok(_) => {
                if b[0] == b'\n' {
                    return (v, true);
                }
                if b[0] != 0 {
                    v.push(b[0]);
                }
            }
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(_) => return (v, false),
        }
    }
}

/// Unbuffered handle on fd 0. `std::io::stdin()` buffers, which would swallow
/// input a later child is meant to read.
pub struct RawStdin;

impl Read for RawStdin {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        use std::os::unix::io::FromRawFd;
        // SAFETY: fd 0 stays open for the life of the process; ManuallyDrop
        // keeps the File from closing it.
        let mut f = std::mem::ManuallyDrop::new(unsafe { fs::File::from_raw_fd(0) });
        f.read(buf)
    }
}

/// `read -r line` from stdin.
pub fn read_stdin_line() -> (Vec<u8>, bool) {
    read_line_raw(&mut RawStdin)
}

/// `[ -t 0 ]`.
pub fn stdin_is_tty() -> bool {
    use std::io::IsTerminal;
    io::stdin().is_terminal()
}

/// `[ -t 1 ]`.
pub fn stdout_is_tty() -> bool {
    use std::io::IsTerminal;
    io::stdout().is_terminal()
}

/// Run `f` with terminal echo off on `tty` (when it is a terminal), the way
/// `read -s` does, restoring the previous settings afterwards.
pub fn with_echo_off<T>(tty: Option<&fs::File>, f: impl FnOnce() -> T) -> T {
    use std::io::IsTerminal;
    let saved = match tty {
        Some(t) if t.is_terminal() => {
            let stty = |args: &[&str]| -> Option<Vec<u8>> {
                let fd = t.try_clone().ok()?;
                let o = Command::new("stty")
                    .args(args)
                    .stdin(Stdio::from(fd))
                    .stderr(Stdio::null())
                    .output()
                    .ok()?;
                if o.status.success() {
                    Some(o.stdout)
                } else {
                    None
                }
            };
            let s = stty(&["-g"]).map(subst);
            if s.is_some() {
                stty(&["-echo"]);
            }
            s.map(|s| (s, t))
        }
        _ => None,
    };
    let r = f();
    if let Some((s, t)) = saved {
        if let Ok(fd) = t.try_clone() {
            let _ = Command::new("stty")
                .arg(os(&s))
                .stdin(Stdio::from(fd))
                .stderr(Stdio::null())
                .status();
        }
    }
    r
}

/// The script's arguments as bytes (`$1`...), without the program name.
pub fn args() -> Vec<Vec<u8>> {
    std::env::args_os()
        .skip(1)
        .map(OsString::into_vec)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn subst_strips_every_trailing_newline_and_nul() {
        assert_eq!(subst(b"tok\n\n".to_vec()), b"tok");
        assert_eq!(subst(b"a\0b\n".to_vec()), b"ab");
        assert_eq!(subst(b"\n".to_vec()), b"");
        assert_eq!(subst(b"a\nb".to_vec()), b"a\nb");
    }

    #[test]
    fn indent_matches_sed() {
        assert_eq!(indent(b""), b"");
        assert_eq!(indent(b"a\nb"), b"  a\n  b");
        assert_eq!(indent(b"a\n"), b"  a\n");
        assert_eq!(indent(b"\n"), b"  \n");
    }

    #[test]
    fn dirname_and_basename_match_coreutils() {
        assert_eq!(dirname(b"a"), b".");
        assert_eq!(dirname(b"/a"), b"/");
        assert_eq!(dirname(b"/a/b/"), b"/a");
        assert_eq!(dirname(b"a//b"), b"a");
        assert_eq!(dirname(b"/"), b"/");
        assert_eq!(basename(b"/a/b"), b"b");
        assert_eq!(basename(b"/a/b/"), b"b");
        assert_eq!(basename(b"b"), b"b");
    }

    #[test]
    fn read_fields_tab_ifs() {
        let f = read_fields(b"acct\tproj", b"\t", 2);
        assert_eq!(f, vec![b"acct".to_vec(), b"proj".to_vec()]);
        let f = read_fields(b"acct\t", b"\t", 2);
        assert_eq!(f, vec![b"acct".to_vec(), b"".to_vec()]);
        let f = read_fields(b"\t\tacct\t\tproj x\t", b"\t", 2);
        assert_eq!(f, vec![b"acct".to_vec(), b"proj x".to_vec()]);
        let f = read_fields(b"", b"\t", 2);
        assert_eq!(f, vec![b"".to_vec(), b"".to_vec()]);
    }

    #[test]
    fn read_fields_pipe_ifs_keeps_empty_fields() {
        assert_eq!(read_fields(b"x:y:", b":", 2)[1], b"y");
        assert_eq!(read_fields(b"x:y:z:", b":", 2)[1], b"y:z:");
        assert_eq!(read_fields(b"x::", b":", 2)[1], b"");
        let f = read_fields(b"a||c|d|e", b"|", 4);
        assert_eq!(
            f,
            vec![b"a".to_vec(), b"".to_vec(), b"c".to_vec(), b"d|e".to_vec()]
        );
    }

    #[test]
    fn read_fields_default_ifs() {
        let f = read_fields(b"  slug id  pem  ", b" \t\n", 3);
        assert_eq!(f, vec![b"slug".to_vec(), b"id".to_vec(), b"pem".to_vec()]);
        let f = read_fields(b"one", b" \t\n", 3);
        assert_eq!(f, vec![b"one".to_vec(), b"".to_vec(), b"".to_vec()]);
        assert_eq!(read_trim(b"  x y \t"), b"x y");
    }

    #[test]
    fn ifs_split_drops_empty_fields() {
        assert_eq!(
            ifs_split(b" a \n b\tc "),
            vec![b"a".to_vec(), b"b".to_vec(), b"c".to_vec()]
        );
        assert!(ifs_split(b"").is_empty());
    }

    #[test]
    fn lines_like_here_string() {
        assert_eq!(lines(b"a\nb"), vec![b"a".to_vec(), b"b".to_vec()]);
        assert_eq!(lines(b""), vec![b"".to_vec()]);
    }

    #[test]
    fn grep_helpers() {
        assert!(grep_qi(b"x\nReauthentication failed\n", &["reauth"]));
        assert!(!grep_qi(b"fine", &["reauth", "credentials"]));
        assert!(grep_q_line_start(b"warn\nERROR: x", b"ERROR:"));
        assert!(!grep_q_line_start(b"warn ERROR: x", b"ERROR:"));
    }

    #[test]
    fn read_line_raw_stops_at_newline() {
        let mut r: &[u8] = b"one\ntwo\n";
        assert_eq!(read_line_raw(&mut r), (b"one".to_vec(), true));
        assert_eq!(read_line_raw(&mut r), (b"two".to_vec(), true));
        assert_eq!(read_line_raw(&mut r), (b"".to_vec(), false));
        let mut r: &[u8] = b"tail";
        assert_eq!(read_line_raw(&mut r), (b"tail".to_vec(), false));
    }

    #[test]
    fn pad_right_counts_bytes() {
        assert_eq!(pad_right(b"ab", 4), b"ab  ");
        assert_eq!(pad_right(b"abcde", 4), b"abcde");
    }
}
