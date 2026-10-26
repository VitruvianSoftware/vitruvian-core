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

use std::collections::BTreeSet;
use std::env;
use std::ffi::{CStr, OsStr, OsString};
use std::fs;
use std::io::{self, Write};
use std::os::raw::{c_char, c_int, c_void};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

#[cfg(unix)]
use std::os::unix::ffi::{OsStrExt, OsStringExt};
#[cfg(unix)]
use std::os::unix::fs::{MetadataExt, PermissionsExt};
#[cfg(unix)]
use std::os::unix::process::{CommandExt, ExitStatusExt};

const SCRIPT_SOURCE: &str = include_str!("../ci-preflight.sh");

pub const GLYPH_OK: &str = "✓";
pub const GLYPH_FAIL: &str = "✗";
pub const GLYPH_WARN: &str = "⚠";
pub const GLYPH_UNKNOWN: &str = "?";

const AUTO_PROVIDED: &[&str] = &["GITHUB_TOKEN"];

/// Standard GNU bash `DEFAULT_PATH_VALUE` used when `PATH` is unset at startup.
const BASH_DEFAULT_PATH: &str = "/usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:.";

#[cfg(any(
    target_os = "macos",
    target_os = "ios",
    target_os = "freebsd",
    target_os = "openbsd",
    target_os = "netbsd",
    target_os = "dragonfly"
))]
const LC_ALL: c_int = 0;

#[cfg(not(any(
    target_os = "macos",
    target_os = "ios",
    target_os = "freebsd",
    target_os = "openbsd",
    target_os = "netbsd",
    target_os = "dragonfly"
)))]
const LC_ALL: c_int = 6;

extern "C" {
    fn setlocale(category: c_int, locale: *const c_char) -> *mut c_char;
    fn strcoll(s1: *const c_char, s2: *const c_char) -> c_int;
    fn strerror(errnum: c_int) -> *const c_char;
    fn write(fd: c_int, buf: *const c_void, count: usize) -> isize;
    fn isatty(fd: c_int) -> c_int;
}

/// Initialise C locale state from the environment (`LC_ALL` / `LC_COLLATE` / `LANG`).
pub fn init_locale() {
    unsafe {
        setlocale(LC_ALL, b"\0".as_ptr() as *const c_char);
    }
}

/// Compare two byte slices using the active locale's `strcoll`.
pub fn strcoll_cmp(a: &[u8], b: &[u8]) -> std::cmp::Ordering {
    let a_nul: Vec<u8> = a
        .iter()
        .copied()
        .take_while(|&c| c != 0)
        .chain(std::iter::once(0))
        .collect();
    let b_nul: Vec<u8> = b
        .iter()
        .copied()
        .take_while(|&c| c != 0)
        .chain(std::iter::once(0))
        .collect();
    let cmp = unsafe {
        strcoll(
            a_nul.as_ptr() as *const c_char,
            b_nul.as_ptr() as *const c_char,
        )
    };
    if cmp < 0 {
        std::cmp::Ordering::Less
    } else if cmp > 0 {
        std::cmp::Ordering::Greater
    } else {
        std::cmp::Ordering::Equal
    }
}

/// Sort strings using locale collation (`strcoll`) and deduplicate where `strcoll() == 0`
/// (keeping the first occurrence, matching `sort -u`).
pub fn sort_u_locale(items: &mut Vec<String>) {
    items.sort_by(|a, b| strcoll_cmp(a.as_bytes(), b.as_bytes()));
    items.dedup_by(|a, b| strcoll_cmp(a.as_bytes(), b.as_bytes()) == std::cmp::Ordering::Equal);
}

fn write_all_fd(fd: c_int, mut bytes: &[u8]) -> io::Result<()> {
    while !bytes.is_empty() {
        let n = unsafe { write(fd, bytes.as_ptr() as *const c_void, bytes.len()) };
        if n < 0 {
            let err = io::Error::last_os_error();
            if err.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(err);
        }
        bytes = &bytes[n as usize..];
    }
    Ok(())
}

fn write_stderr_bytes(bytes: &[u8]) {
    let _ = write_all_fd(2, bytes);
}

fn report_write_error(prog_name: &OsStr, line_no: u32, builtin: &str, err: &io::Error) {
    let mut msg = Vec::new();
    msg.extend_from_slice(os_bytes(prog_name));
    msg.extend_from_slice(
        format!(
            ": line {}: {}: write error: {}\n",
            line_no,
            builtin,
            os_error_message(err)
        )
        .as_bytes(),
    );
    let _ = write_all_fd(2, &msg);
}

fn printf_stdout(prog_name: &OsStr, line_no: u32, bytes: &[u8]) -> Result<(), i32> {
    if let Err(e) = write_all_fd(1, bytes) {
        report_write_error(prog_name, line_no, "printf", &e);
        return Err(1);
    }
    Ok(())
}

fn echo_stdout(prog_name: &OsStr, line_no: u32, bytes: &[u8]) -> Result<(), i32> {
    if let Err(e) = write_all_fd(1, bytes) {
        report_write_error(prog_name, line_no, "echo", &e);
        return Err(1);
    }
    Ok(())
}

fn printf_stderr(prog_name: &OsStr, line_no: u32, bytes: &[u8]) -> Result<(), i32> {
    if let Err(e) = write_all_fd(2, bytes) {
        report_write_error(prog_name, line_no, "printf", &e);
        return Err(1);
    }
    Ok(())
}

macro_rules! printf_out {
    ($prog:expr, $line:expr, $($arg:tt)*) => {{
        let s = format!($($arg)*);
        if let Err(code) = printf_stdout($prog, $line, s.as_bytes()) {
            return code;
        }
    }};
}

macro_rules! printf_out_ln {
    ($prog:expr, $line:expr, $($arg:tt)*) => {{
        let mut s = format!($($arg)*);
        s.push('\n');
        if let Err(code) = printf_stdout($prog, $line, s.as_bytes()) {
            return code;
        }
    }};
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Colors {
    pub red: &'static str,
    pub green: &'static str,
    pub yellow: &'static str,
    pub cyan: &'static str,
    pub dim: &'static str,
    pub reset: &'static str,
}

impl Colors {
    pub fn for_tty(is_tty: bool) -> Self {
        if is_tty {
            Self {
                red: "\x1b[31m",
                green: "\x1b[32m",
                yellow: "\x1b[33m",
                cyan: "\x1b[36m",
                dim: "\x1b[2m",
                reset: "\x1b[0m",
            }
        } else {
            Self {
                red: "",
                green: "",
                yellow: "",
                cyan: "",
                dim: "",
                reset: "",
            }
        }
    }
}

/// Extract lines 21..=55 (1-indexed) of the embedded `ci-preflight.sh` script.
pub fn help_text() -> String {
    let mut out = String::new();
    for line in SCRIPT_SOURCE.lines().skip(20).take(35) {
        out.push_str(line);
        out.push('\n');
    }
    out
}

/// Right-pad `s` with ASCII spaces up to `width` BYTES (matching bash `printf '%-Ns'` / `'%-Nb'`).
pub fn pad_right_bytes(s: &str, width: usize) -> String {
    let byte_len = s.len();
    if byte_len >= width {
        s.to_string()
    } else {
        let mut out = String::with_capacity(width);
        out.push_str(s);
        for _ in 0..(width - byte_len) {
            out.push(' ');
        }
        out
    }
}

/// POSIX `[[:space:]]` in ASCII on a single line (`\n` is the line delimiter).
#[inline]
pub fn is_posix_space(b: u8) -> bool {
    matches!(b, b' ' | b'\t' | b'\r' | 0x0b | 0x0c)
}

#[inline]
fn trim_leading_space(mut slice: &[u8]) -> &[u8] {
    while let Some((&first, rest)) = slice.split_first() {
        if is_posix_space(first) {
            slice = rest;
        } else {
            break;
        }
    }
    slice
}

#[inline]
fn contains_subslice(haystack: &[u8], needle: &[u8]) -> bool {
    if needle.is_empty() {
        return true;
    }
    if haystack.len() < needle.len() {
        return false;
    }
    haystack.windows(needle.len()).any(|w| w == needle)
}

/// Split bytes into lines by `\n` (without stripping `\r`), matching POSIX `sed`/`grep`.
pub fn split_lines_bytes(bytes: &[u8]) -> Vec<&[u8]> {
    if bytes.is_empty() {
        return Vec::new();
    }
    let stripped = bytes.strip_suffix(b"\n").unwrap_or(bytes);
    stripped.split(|&b| b == b'\n').collect()
}

/// Pure-byte matcher used by unit tests; `run_os` shells out via `pr_triggered`.
pub fn is_pr_triggered_bytes(bytes: &[u8]) -> bool {
    let lines = split_lines_bytes(bytes);

    // 1. Flow style: ^on:[[:space:]]*\[.*pull_request
    for &line in &lines {
        if let Some(after_on) = line.strip_prefix(b"on:") {
            let trimmed = trim_leading_space(after_on);
            if let Some(after_bracket) = trimmed.strip_prefix(b"[") {
                if contains_subslice(after_bracket, b"pull_request") {
                    return true;
                }
            }
        }
    }

    // 2. Block style: sed -n '/^on:[[:space:]]*$/,/^[^[:space:]#]/p'
    let mut in_range = false;
    for &line in &lines {
        if !in_range {
            if let Some(after_on) = line.strip_prefix(b"on:") {
                if after_on.iter().all(|&b| is_posix_space(b)) {
                    in_range = true;
                    if matches_block_pr_trigger(line) {
                        return true;
                    }
                }
            }
        } else {
            if matches_block_pr_trigger(line) {
                return true;
            }
            if let Some(&first) = line.first() {
                if !is_posix_space(first) && first != b'#' {
                    in_range = false;
                }
            }
        }
    }

    false
}

#[inline]
fn matches_block_pr_trigger(line: &[u8]) -> bool {
    let Some(&first) = line.first() else {
        return false;
    };
    if !is_posix_space(first) {
        return false;
    }
    let rest = trim_leading_space(line);
    rest.starts_with(b"pull_request:") || rest.starts_with(b"pull_request_target:")
}

/// Extract all matches of `<kind>\.[A-Z][A-Z0-9_]*` from `bytes`, stripping `<kind>.`.
pub fn extract_refs_from_bytes(kind: &str, bytes: &[u8], out: &mut BTreeSet<String>) {
    let prefix = format!("{}.", kind);
    let prefix_bytes = prefix.as_bytes();
    let plen = prefix_bytes.len();

    let mut pos = 0;
    while pos + plen < bytes.len() {
        if &bytes[pos..pos + plen] == prefix_bytes {
            let start = pos + plen;
            if bytes[start].is_ascii_uppercase() {
                let mut end = start + 1;
                while end < bytes.len()
                    && (bytes[end].is_ascii_uppercase()
                        || bytes[end].is_ascii_digit()
                        || bytes[end] == b'_')
                {
                    end += 1;
                }
                if let Ok(name) = std::str::from_utf8(&bytes[start..end]) {
                    out.insert(name.to_string());
                }
                pos = end;
                continue;
            }
        }
        pos += 1;
    }
}

fn make_command(name: &str) -> Command {
    if let CommandLookup::Executable(exec_path) = lookup_command(name) {
        let mut cmd = Command::new(exec_path);
        #[cfg(unix)]
        cmd.arg0(name);
        cmd
    } else {
        Command::new(name)
    }
}

/// Matches `pr_triggered` in `ci-preflight.sh` by running the exact `grep`/`sed` pipeline
/// under `set -o pipefail` without spawning a subshell (so `BASH_ENV` is never re-read per
/// workflow), while binary/non-UTF-8 files, Unicode `[[:space:]]`, and `pipefail` semantics
/// on huge `on:` blocks match bash identically.
pub fn pr_triggered(wf_path: &Path) -> bool {
    if let Ok(status) = make_command("grep")
        .args(["-qE", "^on:[[:space:]]*\\[.*pull_request"])
        .arg(wf_path.as_os_str())
        .stdin(Stdio::inherit())
        .stdout(Stdio::null())
        .stderr(Stdio::inherit())
        .status()
    {
        if status.success() {
            return true;
        }
    }

    let Ok(mut sed_child) = make_command("sed")
        .args(["-n", "/^on:[[:space:]]*$/,/^[^[:space:]#]/p"])
        .arg(wf_path.as_os_str())
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
    else {
        return false;
    };
    let Some(sed_stdout) = sed_child.stdout.take() else {
        let _ = sed_child.wait();
        return false;
    };
    let grep_status = make_command("grep")
        .args([
            "-qE",
            "^[[:space:]]+pull_request:|^[[:space:]]+pull_request_target:",
        ])
        .stdin(Stdio::from(sed_stdout))
        .stdout(Stdio::null())
        .stderr(Stdio::inherit())
        .status();
    let sed_status = sed_child.wait();
    match (sed_status, grep_status) {
        (Ok(s), Ok(g)) => s.success() && g.success(),
        _ => false,
    }
}

/// Matches `refs_in` in `ci-preflight.sh` by running the exact
/// `grep -rhoE "$1\.[A-Z][A-Z0-9_]*" "${@:2}" 2>/dev/null | sed "s/^$1\.//" | sort -u`
/// pipeline directly without spawning `bash -c` (so `BASH_ENV` is never re-read).
pub fn refs_in<P: AsRef<Path>>(kind: &str, paths: &[P]) -> Vec<String> {
    let mut grep_cmd = make_command("grep");
    grep_cmd.args(["-rhoE", &format!("{}\\.[A-Z][A-Z0-9_]*", kind)]);
    for p in paths {
        grep_cmd.arg(p.as_ref().as_os_str());
    }
    let Ok(mut grep_child) = grep_cmd
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    else {
        return Vec::new();
    };
    let Some(grep_stdout) = grep_child.stdout.take() else {
        let _ = grep_child.wait();
        return Vec::new();
    };

    let Ok(mut sed_child) = make_command("sed")
        .arg(format!("s/^{}\\.//", kind))
        .stdin(Stdio::from(grep_stdout))
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
    else {
        let _ = grep_child.wait();
        return Vec::new();
    };
    let Some(sed_stdout) = sed_child.stdout.take() else {
        let _ = sed_child.wait();
        let _ = grep_child.wait();
        return Vec::new();
    };

    let Ok(sort_child) = make_command("sort")
        .arg("-u")
        .stdin(Stdio::from(sed_stdout))
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
    else {
        let _ = sed_child.wait();
        let _ = grep_child.wait();
        return Vec::new();
    };

    let sort_out = sort_child.wait_with_output();
    let _ = sed_child.wait();
    let _ = grep_child.wait();

    let out = match sort_out {
        Ok(o) => o.stdout,
        Err(_) => return Vec::new(),
    };
    let s = String::from_utf8_lossy(&out);
    bash_read_lines(&s)
        .into_iter()
        .filter(|line| !line.is_empty())
        .map(|line| line.to_string())
        .collect()
}

/// Matches bash glob `*.y*ml` on raw filename bytes inside `.github/workflows/`.
pub fn matches_workflow_glob_bytes(file_name: &[u8]) -> bool {
    if file_name.starts_with(b".") {
        return false;
    }
    if !file_name.ends_with(b"ml") || file_name.len() < 4 {
        return false;
    }
    let prefix = &file_name[..file_name.len() - 2];
    prefix.windows(2).any(|w| w == b".y")
}

/// Matches bash glob `*.y*ml` on a filename inside `.github/workflows/`.
pub fn matches_workflow_glob(file_name: &str) -> bool {
    matches_workflow_glob_bytes(file_name.as_bytes())
}

/// Matches `has() { printf '%s\n' "$2" | grep -qxF "$1"; }` in `ci-preflight.sh`.
pub fn has_line(needle: &str, haystack: &str) -> bool {
    has_line_bytes(needle.as_bytes(), haystack.as_bytes())
}

pub fn has_line_bytes(needle: &[u8], haystack: &[u8]) -> bool {
    haystack.split(|&b| b == b'\n').any(|line| line == needle)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CommandLookup {
    Executable(PathBuf),
    NonExecutable(PathBuf),
    NotFound,
}

fn is_executable_meta(meta: &fs::Metadata) -> bool {
    if meta.is_dir() {
        return false;
    }
    #[cfg(unix)]
    {
        meta.permissions().mode() & 0o111 != 0
    }
    #[cfg(not(unix))]
    {
        true
    }
}

/// Resolve `name` along `PATH` with bash's `FS_EXEC_PREFERRED` / `command -v` semantics:
/// returns the first executable non-directory entry if one exists; otherwise returns the first
/// non-executable non-directory entry if one exists; otherwise `NotFound`.
/// When `PATH` is unset (`None`), uses standard bash's compiled-in `DEFAULT_PATH_VALUE`.
pub fn lookup_command(name: &str) -> CommandLookup {
    if name.contains('/') {
        let p = PathBuf::from(name);
        let Ok(meta) = fs::metadata(&p) else {
            return CommandLookup::NotFound;
        };
        if meta.is_dir() {
            return CommandLookup::NotFound;
        }
        return if is_executable_meta(&meta) {
            CommandLookup::Executable(p)
        } else {
            CommandLookup::NonExecutable(p)
        };
    }
    let path_os = env::var_os("PATH").unwrap_or_else(|| OsString::from(BASH_DEFAULT_PATH));
    let dirs: Vec<PathBuf> = if path_os.is_empty() {
        vec![PathBuf::from(".")]
    } else {
        env::split_paths(&path_os)
            .map(|d| {
                if d.as_os_str().is_empty() {
                    PathBuf::from(".")
                } else {
                    d
                }
            })
            .collect()
    };
    let mut first_non_exec: Option<PathBuf> = None;
    for dir in dirs {
        let candidate = dir.join(name);
        let Ok(meta) = fs::metadata(&candidate) else {
            continue;
        };
        if meta.is_dir() {
            continue;
        }
        if is_executable_meta(&meta) {
            return CommandLookup::Executable(candidate);
        }
        if first_non_exec.is_none() {
            first_non_exec = Some(candidate);
        }
    }
    if let Some(non_exec) = first_non_exec {
        CommandLookup::NonExecutable(non_exec)
    } else {
        CommandLookup::NotFound
    }
}

/// Check if `command -v <name> >/dev/null 2>&1` succeeds in bash (succeeds for any non-directory
/// file on `PATH`, even if non-executable).
pub fn command_exists(name: &str) -> bool {
    matches!(
        lookup_command(name),
        CommandLookup::Executable(_) | CommandLookup::NonExecutable(_)
    )
}

fn os_error_message(err: &io::Error) -> String {
    if let Some(code) = err.raw_os_error() {
        unsafe {
            let ptr = strerror(code);
            if !ptr.is_null() {
                return CStr::from_ptr(ptr).to_string_lossy().into_owned();
            }
        }
    }
    let s = err.to_string();
    if let Some(idx) = s.rfind(" (os error ") {
        s[..idx].to_string()
    } else {
        s
    }
}

#[cfg(unix)]
fn os_bytes(s: &OsStr) -> &[u8] {
    s.as_bytes()
}

#[cfg(not(unix))]
fn os_bytes(s: &OsStr) -> &[u8] {
    s.to_str().map(|v| v.as_bytes()).unwrap_or(b"")
}

#[cfg(unix)]
fn os_from_bytes(b: Vec<u8>) -> OsString {
    OsString::from_vec(b)
}

#[cfg(not(unix))]
fn os_from_bytes(b: Vec<u8>) -> OsString {
    OsString::from(String::from_utf8_lossy(&b).into_owned())
}

fn stack_to_path_bytes(stack: &[&[u8]]) -> Vec<u8> {
    if stack.is_empty() {
        b"/".to_vec()
    } else {
        let mut out = Vec::new();
        for part in stack {
            out.push(b'/');
            out.extend_from_slice(part);
        }
        out
    }
}

/// Logically normalise `target` relative to `base_pwd` like bash's `sh_canonpath` with
/// `PATH_CHECKDOTDOT`: returns `Some(canonical_bytes)` if every directory preceding `..`
/// exists as a directory, or `None` if an intermediate directory before `..` does not exist.
pub fn logical_normalize_bytes(base_pwd: &[u8], target: &[u8]) -> Option<Vec<u8>> {
    let mut combined = Vec::new();
    if target.starts_with(b"/") {
        combined.extend_from_slice(target);
    } else {
        let mut base = base_pwd;
        while base.ends_with(b"/") && base.len() > 1 {
            base = &base[..base.len() - 1];
        }
        if base != b"/" {
            combined.extend_from_slice(base);
        }
        combined.push(b'/');
        combined.extend_from_slice(target);
    }

    let mut stack: Vec<&[u8]> = Vec::new();
    for part in combined.split(|&b| b == b'/') {
        match part {
            b"" | b"." => {}
            b".." => {
                let prefix_os = os_from_bytes(stack_to_path_bytes(&stack));
                if !fs::metadata(Path::new(&prefix_os))
                    .map(|m| m.is_dir())
                    .unwrap_or(false)
                {
                    return None;
                }
                stack.pop();
            }
            other => stack.push(other),
        }
    }
    Some(stack_to_path_bytes(&stack))
}

#[cfg(unix)]
fn same_file(a: &Path, b: &Path) -> bool {
    match (fs::metadata(a), fs::metadata(b)) {
        (Ok(ma), Ok(mb)) => ma.dev() == mb.dev() && ma.ino() == mb.ino(),
        _ => false,
    }
}

#[cfg(not(unix))]
fn same_file(a: &Path, b: &Path) -> bool {
    a == b
}

fn current_logical_pwd() -> OsString {
    if let Some(pwd) = env::var_os("PWD") {
        if os_bytes(&pwd).starts_with(b"/") && same_file(Path::new(&pwd), Path::new(".")) {
            return pwd;
        }
    }
    env::current_dir()
        .map(|p| p.into_os_string())
        .unwrap_or_else(|_| OsString::from("."))
}

fn resolve_root_and_cd(prog_name: &OsStr) -> Result<(OsString, OsString), i32> {
    let old_pwd = current_logical_pwd();
    let root: OsString = match env::var_os("BUILD_WORKSPACE_DIRECTORY") {
        Some(val) if !val.is_empty() => val,
        _ => {
            let git_out = make_command("git")
                .args(["rev-parse", "--show-toplevel"])
                .stdin(Stdio::inherit())
                .stderr(Stdio::null())
                .stdout(Stdio::piped())
                .output();
            match git_out {
                Ok(out) if out.status.success() => {
                    let mut raw = out.stdout;
                    while raw.ends_with(b"\n") {
                        raw.pop();
                    }
                    os_from_bytes(raw)
                }
                _ => old_pwd.clone(),
            }
        }
    };

    let new_pwd = if root.is_empty() {
        old_pwd.clone()
    } else {
        let logical_cand =
            logical_normalize_bytes(os_bytes(&old_pwd), os_bytes(&root)).map(os_from_bytes);
        if let Some(ref cand) = logical_cand {
            if env::set_current_dir(Path::new(cand)).is_ok() {
                cand.clone()
            } else {
                if let Err(e) = env::set_current_dir(Path::new(&root)) {
                    let mut msg = Vec::new();
                    msg.extend_from_slice(os_bytes(prog_name));
                    msg.extend_from_slice(b": line 59: cd: ");
                    msg.extend_from_slice(os_bytes(&root));
                    msg.extend_from_slice(b": ");
                    msg.extend_from_slice(os_error_message(&e).as_bytes());
                    msg.push(b'\n');
                    write_stderr_bytes(&msg);
                    return Err(1);
                }
                env::current_dir()
                    .map(|p| p.into_os_string())
                    .unwrap_or_else(|_| cand.clone())
            }
        } else {
            if let Err(e) = env::set_current_dir(Path::new(&root)) {
                let mut msg = Vec::new();
                msg.extend_from_slice(os_bytes(prog_name));
                msg.extend_from_slice(b": line 59: cd: ");
                msg.extend_from_slice(os_bytes(&root));
                msg.extend_from_slice(b": ");
                msg.extend_from_slice(os_error_message(&e).as_bytes());
                msg.push(b'\n');
                write_stderr_bytes(&msg);
                return Err(1);
            }
            env::current_dir()
                .map(|p| p.into_os_string())
                .unwrap_or_else(|_| root.clone())
        }
    };

    env::set_var("OLDPWD", &old_pwd);
    env::set_var("PWD", &new_pwd);
    Ok((root, new_pwd))
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ParsedArgs {
    Help,
    Run { list_only: bool, repo_slug: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ParsedArgsOs {
    Help,
    Run {
        list_only: bool,
        repo_slug: OsString,
    },
}

pub fn parse_args_os(
    args: &[OsString],
    default_repo_slug: OsString,
    colors: &Colors,
    prog_name: &OsStr,
) -> Result<ParsedArgsOs, (Vec<u8>, u32, bool, i32)> {
    let mut list_only = false;
    let mut repo_slug = default_repo_slug;
    let mut i = 0;
    while i < args.len() {
        let arg_bytes = os_bytes(&args[i]);
        if arg_bytes == b"--list" {
            list_only = true;
            i += 1;
        } else if arg_bytes == b"--repo" {
            match args.get(i + 1) {
                Some(val) if !val.is_empty() => {
                    repo_slug = val.clone();
                    i += 2;
                }
                _ => {
                    let mut msg = Vec::new();
                    msg.extend_from_slice(os_bytes(prog_name));
                    msg.extend_from_slice(b": line 83: 2: --repo needs owner/name\n");
                    // Parameter expansion `${2:?...}` failure is emitted by the shell itself, not `printf`.
                    return Err((msg, 83, false, 1));
                }
            }
        } else if arg_bytes == b"-h" || arg_bytes == b"--help" {
            return Ok(ParsedArgsOs::Help);
        } else {
            let mut msg = Vec::new();
            msg.extend_from_slice(colors.red.as_bytes());
            msg.extend_from_slice(GLYPH_FAIL.as_bytes());
            msg.extend_from_slice(b" ci-preflight");
            msg.extend_from_slice(colors.reset.as_bytes());
            msg.extend_from_slice(" — unknown flag: ".as_bytes());
            msg.extend_from_slice(arg_bytes);
            msg.push(b'\n');
            return Err((msg, 86, true, 2));
        }
    }
    Ok(ParsedArgsOs::Run {
        list_only,
        repo_slug,
    })
}

pub fn parse_args(
    args: &[String],
    default_repo_slug: String,
    colors: &Colors,
    prog_name: &str,
) -> Result<ParsedArgs, (String, i32)> {
    let os_args: Vec<OsString> = args.iter().map(OsString::from).collect();
    match parse_args_os(
        &os_args,
        OsString::from(default_repo_slug),
        colors,
        OsStr::new(prog_name),
    ) {
        Ok(ParsedArgsOs::Help) => Ok(ParsedArgs::Help),
        Ok(ParsedArgsOs::Run {
            list_only,
            repo_slug,
        }) => Ok(ParsedArgs::Run {
            list_only,
            repo_slug: repo_slug.to_string_lossy().into_owned(),
        }),
        Err((bytes, _line, _is_printf, code)) => {
            Err((String::from_utf8_lossy(&bytes).into_owned(), code))
        }
    }
}

fn run_gh_status(args: &[&str]) -> bool {
    let CommandLookup::Executable(exec_path) = lookup_command("gh") else {
        return false;
    };
    let mut cmd = Command::new(exec_path);
    #[cfg(unix)]
    cmd.arg0("gh");
    cmd.args(args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn run_gh_capture_raw_bytes(args: &[&OsStr]) -> Vec<u8> {
    let CommandLookup::Executable(exec_path) = lookup_command("gh") else {
        return Vec::new();
    };
    let mut cmd = Command::new(exec_path);
    #[cfg(unix)]
    cmd.arg0("gh");
    let out = cmd
        .args(args)
        .stdin(Stdio::inherit())
        .stderr(Stdio::null())
        .stdout(Stdio::piped())
        .output();
    match out {
        Ok(o) => o.stdout,
        Err(_) => Vec::new(),
    }
}

fn run_gh_capture_bytes(args: &[&OsStr]) -> Vec<u8> {
    let mut out = run_gh_capture_raw_bytes(args);
    while out.ends_with(b"\n") {
        out.pop();
    }
    out
}

fn api_names_bytes(api_path: &[u8], jq_filter: &str) -> Vec<u8> {
    let path_os = os_from_bytes(api_path.to_vec());
    run_gh_capture_bytes(&[
        OsStr::new("api"),
        OsStr::new("--paginate"),
        path_os.as_os_str(),
        OsStr::new("--jq"),
        OsStr::new(jq_filter),
    ])
}

fn api_names_raw_bytes(api_path: &[u8], jq_filter: &str) -> Vec<u8> {
    let path_os = os_from_bytes(api_path.to_vec());
    run_gh_capture_raw_bytes(&[
        OsStr::new("api"),
        OsStr::new("--paginate"),
        path_os.as_os_str(),
        OsStr::new("--jq"),
        OsStr::new(jq_filter),
    ])
}

fn exit_status_to_bash_code(status: std::process::ExitStatus) -> i32 {
    if let Some(code) = status.code() {
        return code;
    }
    #[cfg(unix)]
    if let Some(sig) = status.signal() {
        return 128 + sig;
    }
    1
}

fn run_checked_tool(prog_name: &OsStr, line_no: u32, tool_name: &str, args: &[&OsStr]) -> i32 {
    match lookup_command(tool_name) {
        CommandLookup::Executable(exec_path) => {
            let mut cmd = Command::new(&exec_path);
            #[cfg(unix)]
            cmd.arg0(tool_name);
            match cmd
                .args(args)
                .stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .status()
            {
                Ok(status) => exit_status_to_bash_code(status),
                Err(e) if e.kind() == io::ErrorKind::PermissionDenied => {
                    let mut msg = Vec::new();
                    msg.extend_from_slice(os_bytes(prog_name));
                    msg.extend_from_slice(format!(": line {}: ", line_no).as_bytes());
                    msg.extend_from_slice(os_bytes(exec_path.as_os_str()));
                    msg.extend_from_slice(b": Permission denied\n");
                    write_stderr_bytes(&msg);
                    126
                }
                Err(e) if e.kind() == io::ErrorKind::NotFound => {
                    let mut msg = Vec::new();
                    msg.extend_from_slice(os_bytes(prog_name));
                    msg.extend_from_slice(
                        format!(": line {}: {}: command not found\n", line_no, tool_name)
                            .as_bytes(),
                    );
                    write_stderr_bytes(&msg);
                    127
                }
                Err(_) => 126,
            }
        }
        CommandLookup::NonExecutable(non_exec_path) => {
            let mut msg = Vec::new();
            msg.extend_from_slice(os_bytes(prog_name));
            msg.extend_from_slice(format!(": line {}: ", line_no).as_bytes());
            msg.extend_from_slice(os_bytes(non_exec_path.as_os_str()));
            msg.extend_from_slice(b": Permission denied\n");
            write_stderr_bytes(&msg);
            126
        }
        CommandLookup::NotFound => {
            let mut msg = Vec::new();
            msg.extend_from_slice(os_bytes(prog_name));
            msg.extend_from_slice(
                format!(": line {}: {}: command not found\n", line_no, tool_name).as_bytes(),
            );
            write_stderr_bytes(&msg);
            127
        }
    }
}

/// Lines read by `while IFS= read -r line` in bash (only `\n`-terminated lines).
pub fn bash_read_lines(raw: &str) -> Vec<&str> {
    let parts: Vec<&str> = raw.split('\n').collect();
    if parts.len() <= 1 {
        Vec::new()
    } else {
        parts[..parts.len() - 1].to_vec()
    }
}

/// Raw byte lines read by `while IFS= read -r line` in bash (only `\n`-terminated lines).
pub fn bash_read_lines_bytes(raw: &[u8]) -> Vec<&[u8]> {
    let parts: Vec<&[u8]> = raw.split(|&b| b == b'\n').collect();
    if parts.len() <= 1 {
        Vec::new()
    } else {
        parts[..parts.len() - 1].to_vec()
    }
}

pub fn run(argv: &[String]) -> i32 {
    let os_argv: Vec<OsString> = argv.iter().map(OsString::from).collect();
    run_os(&os_argv)
}

pub fn run_os(argv: &[OsString]) -> i32 {
    init_locale();

    let prog_name: &OsStr = argv
        .first()
        .map(|s| s.as_os_str())
        .unwrap_or_else(|| OsStr::new("ci-preflight"));

    let (root, pwd) = match resolve_root_and_cd(prog_name) {
        Ok(v) => v,
        Err(code) => return code,
    };

    let colors = Colors::for_tty(unsafe { isatty(1) == 1 });
    let cli_args = if argv.len() > 1 { &argv[1..] } else { &[] };
    let default_repo = env::var_os("GITHUB_REPOSITORY").unwrap_or_default();

    let (list_only, mut repo_slug_os) =
        match parse_args_os(cli_args, default_repo, &colors, prog_name) {
            Ok(ParsedArgsOs::Help) => {
                // Deliberate divergence from ci-preflight.sh: emit embedded lines 21..=55 rather
                // than running `sed -n '21,55p' "$0"` after `cd "${ROOT}"`, which fails with a sed
                // file-not-found error when invoked via a relative path from another directory.
                if let Err(e) = write_all_fd(1, help_text().as_bytes()) {
                    // Delegate the write error to the platform's `sed` (feeding 1 byte via stdin)
                    // so BSD sed (exit 1, `sed: stdout: Bad file descriptor`) and GNU sed
                    // (exit 4, `sed: couldn't close stdout: Bad file descriptor`) match identically.
                    if let Ok(mut child) = make_command("sed")
                        .args(["-n", "1p"])
                        .stdin(Stdio::piped())
                        .stdout(Stdio::inherit())
                        .stderr(Stdio::inherit())
                        .spawn()
                    {
                        if let Some(mut child_in) = child.stdin.take() {
                            let _ = child_in.write_all(b"\n");
                        }
                        if let Ok(status) = child.wait() {
                            let code = exit_status_to_bash_code(status);
                            if code != 0 {
                                return code;
                            }
                        }
                    }
                    let msg = format!("sed: stdout: {}\n", os_error_message(&e));
                    write_stderr_bytes(msg.as_bytes());
                    return 1;
                }
                return 0;
            }
            Ok(ParsedArgsOs::Run {
                list_only,
                repo_slug,
            }) => (list_only, repo_slug),
            Err((msg, line_no, is_printf, code)) => {
                if is_printf {
                    if let Err(err_code) = printf_stderr(prog_name, line_no, &msg) {
                        return err_code;
                    }
                } else {
                    write_stderr_bytes(&msg);
                }
                return code;
            }
        };

    if !Path::new(".github/workflows").is_dir() {
        let mut msg = Vec::new();
        msg.extend_from_slice(colors.red.as_bytes());
        msg.extend_from_slice(GLYPH_FAIL.as_bytes());
        msg.extend_from_slice(b" ci-preflight");
        msg.extend_from_slice(colors.reset.as_bytes());
        msg.extend_from_slice(" — no .github/workflows here (cwd: ".as_bytes());
        msg.extend_from_slice(os_bytes(&pwd));
        msg.extend_from_slice(b")\n");
        if let Err(err_code) = printf_stderr(prog_name, 95, &msg) {
            return err_code;
        }
        return 1;
    }

    // ---------------------------------------------------------------------------
    // 1. Derive the required set from the workflows themselves.
    // ---------------------------------------------------------------------------
    let mut sources = vec![".github/workflows"];
    if Path::new(".github/actions").is_dir() {
        sources.push(".github/actions");
    }
    let sources_joined = sources.join(" ");

    let req_secrets = refs_in("secrets", &sources);
    let req_vars = refs_in("vars", &sources);

    let mut wf_files: Vec<OsString> = Vec::new();
    if let Ok(entries) = fs::read_dir(".github/workflows") {
        for entry in entries.flatten() {
            let name = entry.file_name();
            if matches_workflow_glob_bytes(os_bytes(&name)) {
                wf_files.push(name);
            }
        }
    }
    wf_files.sort_by(|a, b| {
        strcoll_cmp(os_bytes(a), os_bytes(b)).then_with(|| os_bytes(a).cmp(os_bytes(b)))
    });

    let mut pr_secrets = String::new();
    for wf_name in &wf_files {
        let wf_path = Path::new(".github/workflows").join(wf_name);
        if !fs::metadata(&wf_path).map(|m| m.is_file()).unwrap_or(false) {
            continue;
        }
        if !pr_triggered(&wf_path) {
            continue;
        }
        for s in refs_in("secrets", &[&wf_path]) {
            let needle = format!(" {} ", s);
            let hay = format!(" {} ", pr_secrets);
            if !hay.contains(&needle) {
                pr_secrets.push(' ');
                pr_secrets.push_str(&s);
            }
        }
    }

    if list_only {
        printf_out_ln!(
            prog_name,
            175,
            "{}→{} required by CI (derived from {})\n",
            colors.cyan,
            colors.reset,
            sources_joined
        );
        // Deliberate divergence from ci-preflight.sh: do not reproduce the bash 3.2 `set -u`
        // unbound-variable crash when `${REQ_SECRETS[@]}` or `${REQ_VARS[@]}` is empty.
        printf_out_ln!(prog_name, 177, "  secrets ({}):", req_secrets.len());
        {
            let mut buf = String::new();
            if req_secrets.is_empty() {
                buf.push_str("    \n");
            } else {
                for s in &req_secrets {
                    buf.push_str("    ");
                    buf.push_str(s);
                    buf.push('\n');
                }
            }
            if let Err(code) = printf_stdout(prog_name, 178, buf.as_bytes()) {
                return code;
            }
        }
        printf_out_ln!(prog_name, 179, "  variables ({}):", req_vars.len());
        {
            let mut buf = String::new();
            if req_vars.is_empty() {
                buf.push_str("    \n");
            } else {
                for v in &req_vars {
                    buf.push_str("    ");
                    buf.push_str(v);
                    buf.push('\n');
                }
            }
            if let Err(code) = printf_stdout(prog_name, 180, buf.as_bytes()) {
                return code;
            }
        }
        printf_out_ln!(
            prog_name,
            181,
            "\n  read by PR-triggered workflows (must also exist in the Dependabot store):"
        );
        for s in pr_secrets.split(|c: char| c == ' ' || c == '\t' || c == '\n') {
            if s.is_empty() {
                continue;
            }
            if AUTO_PROVIDED.contains(&s) {
                continue;
            }
            printf_out_ln!(prog_name, 184, "    {}", s);
        }
        return 0;
    }

    // ---------------------------------------------------------------------------
    // 2. Ask GitHub what is actually configured.
    // ---------------------------------------------------------------------------
    let mut live = true;
    let mut why_not_live: Vec<u8> = Vec::new();

    if !command_exists("gh") {
        live = false;
        why_not_live = b"gh is not installed".to_vec();
    } else if !run_gh_status(&["auth", "status"]) {
        live = false;
        why_not_live = b"gh is not authenticated (run: gh auth login)".to_vec();
    }

    if live && repo_slug_os.is_empty() {
        let resolved = run_gh_capture_bytes(&[
            OsStr::new("repo"),
            OsStr::new("view"),
            OsStr::new("--json"),
            OsStr::new("nameWithOwner"),
            OsStr::new("--jq"),
            OsStr::new(".nameWithOwner"),
        ]);
        if resolved.is_empty() {
            live = false;
            why_not_live = b"could not resolve owner/repo (pass --repo)".to_vec();
        } else {
            repo_slug_os = os_from_bytes(resolved);
        }
    }

    let repo_slug_bytes = os_bytes(&repo_slug_os).to_vec();

    let mut repo_secrets: Vec<u8> = Vec::new();
    let mut repo_vars: Vec<u8> = Vec::new();
    let mut dependabot_secrets: Vec<u8> = Vec::new();
    let mut env_secrets: Vec<u8> = Vec::new();
    let mut env_vars: Vec<u8> = Vec::new();

    if live {
        let mut path_buf = Vec::new();

        path_buf.clear();
        path_buf.extend_from_slice(b"repos/");
        path_buf.extend_from_slice(&repo_slug_bytes);
        path_buf.extend_from_slice(b"/actions/secrets");
        repo_secrets = api_names_bytes(&path_buf, ".secrets[].name");

        path_buf.clear();
        path_buf.extend_from_slice(b"repos/");
        path_buf.extend_from_slice(&repo_slug_bytes);
        path_buf.extend_from_slice(b"/actions/variables");
        repo_vars = api_names_bytes(&path_buf, ".variables[].name");

        path_buf.clear();
        path_buf.extend_from_slice(b"repos/");
        path_buf.extend_from_slice(&repo_slug_bytes);
        path_buf.extend_from_slice(b"/dependabot/secrets");
        dependabot_secrets = api_names_bytes(&path_buf, ".secrets[].name");

        path_buf.clear();
        path_buf.extend_from_slice(b"repos/");
        path_buf.extend_from_slice(&repo_slug_bytes);
        path_buf.extend_from_slice(b"/environments");
        let envs_raw = api_names_raw_bytes(&path_buf, ".environments[].name");
        for env_name in bash_read_lines_bytes(&envs_raw) {
            if env_name.is_empty() {
                continue;
            }
            path_buf.clear();
            path_buf.extend_from_slice(b"repos/");
            path_buf.extend_from_slice(&repo_slug_bytes);
            path_buf.extend_from_slice(b"/environments/");
            path_buf.extend_from_slice(env_name);
            path_buf.extend_from_slice(b"/secrets");
            let es = api_names_bytes(&path_buf, ".secrets[].name");
            env_secrets.push(b'\n');
            env_secrets.extend_from_slice(&es);

            path_buf.clear();
            path_buf.extend_from_slice(b"repos/");
            path_buf.extend_from_slice(&repo_slug_bytes);
            path_buf.extend_from_slice(b"/environments/");
            path_buf.extend_from_slice(env_name);
            path_buf.extend_from_slice(b"/variables");
            let ev = api_names_bytes(&path_buf, ".variables[].name");
            env_vars.push(b'\n');
            env_vars.extend_from_slice(&ev);
        }

        if repo_secrets.is_empty()
            && repo_vars.is_empty()
            && dependabot_secrets.is_empty()
            && env_secrets.is_empty()
            && env_vars.is_empty()
        {
            live = false;
            why_not_live.extend_from_slice(b"the GitHub API returned nothing for ");
            why_not_live.extend_from_slice(&repo_slug_bytes);
            why_not_live.extend_from_slice(" — the token likely lacks admin:repo scope".as_bytes());
        }
    }

    // ---------------------------------------------------------------------------
    // 3. Report.
    // ---------------------------------------------------------------------------
    let mut missing: usize = 0;
    let mut dependabot_blind: usize = 0;
    let mut unknown: usize = 0;

    {
        let mut header = Vec::new();
        header.extend_from_slice(colors.cyan.as_bytes());
        header.extend_from_slice("→".as_bytes());
        header.extend_from_slice(colors.reset.as_bytes());
        header.extend_from_slice(b" CI preflight for ");
        if repo_slug_bytes.is_empty() {
            header.extend_from_slice(b"<unresolved repo>");
        } else {
            header.extend_from_slice(&repo_slug_bytes);
        }
        header.push(b'\n');
        if let Err(code) = printf_stdout(prog_name, 253, &header) {
            return code;
        }
    }
    printf_out_ln!(
        prog_name,
        255,
        "{}  required set derived from {}{}\n",
        colors.dim,
        sources_joined,
        colors.reset
    );

    if !live {
        let mut line = Vec::new();
        line.extend_from_slice(colors.yellow.as_bytes());
        line.extend_from_slice(GLYPH_WARN.as_bytes());
        line.extend_from_slice(b" offline");
        line.extend_from_slice(colors.reset.as_bytes());
        line.extend_from_slice(" — ".as_bytes());
        line.extend_from_slice(&why_not_live);
        line.push(b'\n');
        if let Err(code) = printf_stdout(prog_name, 259, &line) {
            return code;
        }
        printf_out_ln!(
            prog_name,
            260,
            "{}  Listing what CI requires; presence shown as \"?\" (not checked).{}\n",
            colors.dim,
            colors.reset
        );
    }

    printf_out_ln!(
        prog_name,
        264,
        "  {} {} {}",
        pad_right_bytes("SECRET", 38),
        pad_right_bytes("REPO", 10),
        "DEPENDABOT"
    );

    let mut all_repo_secrets = repo_secrets.clone();
    all_repo_secrets.extend_from_slice(&env_secrets);
    let mut all_repo_vars = repo_vars.clone();
    all_repo_vars.extend_from_slice(&env_vars);

    for s in &req_secrets {
        if AUTO_PROVIDED.contains(&s.as_str()) {
            printf_out_ln!(
                prog_name,
                268,
                "  {} {}{}{} {}(provided by Actions){}",
                pad_right_bytes(s, 38),
                colors.dim,
                pad_right_bytes("auto", 10),
                colors.reset,
                colors.dim,
                colors.reset
            );
            continue;
        }

        let needs_dependabot = format!(" {} ", pr_secrets).contains(&format!(" {} ", s));

        if !live {
            unknown += 1;
            let dep_col = if needs_dependabot {
                format!(
                    "{}{} required (PR-triggered){}",
                    colors.yellow, GLYPH_UNKNOWN, colors.reset
                )
            } else {
                format!("{}n/a{}", colors.dim, colors.reset)
            };
            printf_out_ln!(
                prog_name,
                278,
                "  {} {}{}{} {}",
                pad_right_bytes(s, 38),
                colors.yellow,
                pad_right_bytes(GLYPH_UNKNOWN, 10),
                colors.reset,
                dep_col
            );
            continue;
        }

        let repo_cell = if has_line_bytes(s.as_bytes(), &all_repo_secrets) {
            format!("{}{}{}", colors.green, GLYPH_OK, colors.reset)
        } else {
            missing += 1;
            format!("{}{} MISSING{}", colors.red, GLYPH_FAIL, colors.reset)
        };

        let dep_cell = if !needs_dependabot {
            format!("{}n/a{}", colors.dim, colors.reset)
        } else if has_line_bytes(s.as_bytes(), &dependabot_secrets) {
            format!("{}{}{}", colors.green, GLYPH_OK, colors.reset)
        } else {
            dependabot_blind += 1;
            format!(
                "{}{} empty on Dependabot PRs{}",
                colors.yellow, GLYPH_WARN, colors.reset
            )
        };

        printf_out_ln!(
            prog_name,
            299,
            "  {} {} {}",
            pad_right_bytes(s, 38),
            pad_right_bytes(&repo_cell, 19),
            dep_cell
        );
    }

    printf_out_ln!(
        prog_name,
        302,
        "\n  {} {}",
        pad_right_bytes("VARIABLE", 38),
        "REPO"
    );
    for v in &req_vars {
        if !live {
            unknown += 1;
            printf_out_ln!(
                prog_name,
                306,
                "  {} {}{}{}",
                pad_right_bytes(v, 38),
                colors.yellow,
                GLYPH_UNKNOWN,
                colors.reset
            );
        } else if has_line_bytes(v.as_bytes(), &all_repo_vars) {
            printf_out_ln!(
                prog_name,
                308,
                "  {} {}{}{}",
                pad_right_bytes(v, 38),
                colors.green,
                GLYPH_OK,
                colors.reset
            );
        } else {
            printf_out_ln!(
                prog_name,
                310,
                "  {} {}{} MISSING{}",
                pad_right_bytes(v, 38),
                colors.red,
                GLYPH_FAIL,
                colors.reset
            );
            missing += 1;
        }
    }

    if let Err(code) = echo_stdout(prog_name, 315, b"\n") {
        return code;
    }
    if !live {
        let mut summary = Vec::new();
        summary.extend_from_slice(colors.yellow.as_bytes());
        summary.extend_from_slice(GLYPH_WARN.as_bytes());
        summary.extend_from_slice(b" ci-preflight");
        summary.extend_from_slice(colors.reset.as_bytes());
        summary.extend_from_slice(
            format!(
                " — {} requirement(s) listed, presence NOT verified (",
                unknown
            )
            .as_bytes(),
        );
        summary.extend_from_slice(&why_not_live);
        summary.extend_from_slice(b").\n");
        if let Err(code) = printf_stdout(prog_name, 317, &summary) {
            return code;
        }
        return 0;
    }

    if dependabot_blind > 0 {
        printf_out_ln!(
            prog_name,
            325,
            "{}{} {} secret(s) are read by PR-triggered workflows but absent from the Dependabot store.{}",
            colors.yellow,
            GLYPH_WARN,
            dependabot_blind,
            colors.reset
        );
        printf_out_ln!(
            prog_name,
            327,
            "   On a Dependabot PR they resolve to the EMPTY STRING, with no warning."
        );
        printf_out_ln!(
            prog_name,
            328,
            "   Add as code in infrastructure/pulumi/platform/repo_config (dependabotSecrets),"
        );
        let mut adhoc = Vec::new();
        adhoc.extend_from_slice(b"   or ad hoc:  gh secret set <NAME> --app dependabot --repo ");
        adhoc.extend_from_slice(&repo_slug_bytes);
        adhoc.extend_from_slice(b"\n\n");
        if let Err(code) = printf_stdout(prog_name, 329, &adhoc) {
            return code;
        }
    }

    // ---------------------------------------------------------------------------
    // 4. Naming convention validation
    // ---------------------------------------------------------------------------
    let mut naming_failed: usize = 0;
    let lint_naming_py = Path::new(&root).join("tools/lint-naming/lint_naming.py");
    if !list_only
        && fs::metadata(&lint_naming_py)
            .map(|m| m.is_file())
            .unwrap_or(false)
    {
        printf_out_ln!(
            prog_name,
            337,
            "\n{}→{} Monorepo naming convention preflight{}",
            colors.cyan,
            colors.dim,
            colors.reset
        );
        let module_bazel = Path::new(&root).join("MODULE.bazel");
        if command_exists("bazel")
            && fs::metadata(&module_bazel)
                .map(|m| m.is_file())
                .unwrap_or(false)
        {
            if run_checked_tool(
                prog_name,
                339,
                "bazel",
                &[
                    OsStr::new("test"),
                    OsStr::new("//tools/lint-naming:lint-naming_test"),
                ],
            ) != 0
            {
                naming_failed = 1;
            }
        } else if run_checked_tool(
            prog_name,
            343,
            "python3",
            &[
                lint_naming_py.as_os_str(),
                OsStr::new("--root"),
                root.as_os_str(),
                OsStr::new("--check"),
            ],
        ) != 0
        {
            naming_failed = 1;
        }
    }

    if missing > 0 || naming_failed > 0 {
        printf_out_ln!(
            prog_name,
            350,
            "{}{} ci-preflight{} — preflight checks failed (missing values: {}, naming failures: {}).",
            colors.red,
            GLYPH_FAIL,
            colors.reset,
            missing,
            naming_failed
        );
        return 1;
    }

    printf_out!(
        prog_name,
        355,
        "{}{} ci-preflight{} — every value CI references is configured",
        colors.green,
        GLYPH_OK,
        colors.reset
    );
    if dependabot_blind > 0 {
        printf_out!(
            prog_name,
            357,
            " ({} Dependabot gap(s) above)",
            dependabot_blind
        );
    }
    printf_out_ln!(prog_name, 358, ".");
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_help_text_matches_lines_21_to_55() {
        let h = help_text();
        let lines: Vec<&str> = h.lines().collect();
        assert_eq!(lines.len(), 35);
        assert!(lines[0].starts_with("# ci-preflight.sh — what CI requires"));
        assert!(lines[34].contains("worse than one that refuses to."));
    }

    #[test]
    fn test_pad_right_bytes_multibyte_and_ansi() {
        let p = pad_right_bytes(GLYPH_OK, 19);
        assert_eq!(p.len(), 19);
        assert!(p.starts_with(GLYPH_OK));

        let colored = format!("\x1b[32m{}\x1b[0m", GLYPH_OK);
        let pc = pad_right_bytes(&colored, 19);
        assert_eq!(pc.len(), 19);

        let missing_col = format!("\x1b[31m{} MISSING\x1b[0m", GLYPH_FAIL);
        let pm = pad_right_bytes(&missing_col, 19);
        assert_eq!(pm.len(), 20);
        assert_eq!(pm, missing_col);
    }

    #[test]
    fn test_pr_triggered_flow_and_block() {
        assert!(is_pr_triggered_bytes(
            b"name: X\non: [pull_request, push]\n"
        ));
        assert!(is_pr_triggered_bytes(
            b"on:   [push, pull_request_target]\n"
        ));
        assert!(!is_pr_triggered_bytes(b"on: [push, workflow_dispatch]\n"));

        assert!(is_pr_triggered_bytes(
            b"name: PR\non:\n  pull_request:\n    branches: [main]\njobs:\n  a:\n"
        ));
        assert!(is_pr_triggered_bytes(
            b"name: PR4\non:\n    pull_request:\n        branches: [main]\njobs:\n"
        ));
        assert!(is_pr_triggered_bytes(
            b"on:\n  # comment\n\n  pull_request_target:\n"
        ));

        assert!(!is_pr_triggered_bytes(
            b"name: Push\non:\n  push:\n    branches: [main]\njobs:\n  a:\n    if: github.event.pull_request.number\n    pull_request:\n"
        ));

        assert!(is_pr_triggered_bytes(b"on:\n  push:\n  pull_request:"));
    }

    #[test]
    fn test_extract_refs_from_bytes() {
        let mut s = BTreeSet::new();
        extract_refs_from_bytes(
            "secrets",
            b"env:\n  A: ${{ secrets.Z_SEC }} ${{ secrets.A_0 }}\n  B: secrets.secrets.INNER_1\n  C: secrets.lower_ignored\n",
            &mut s,
        );
        let v: Vec<String> = s.into_iter().collect();
        assert_eq!(v, vec!["A_0", "INNER_1", "Z_SEC"]);
    }

    #[test]
    fn test_matches_workflow_glob() {
        assert!(matches_workflow_glob("ci.yaml"));
        assert!(matches_workflow_glob("ci.yml"));
        assert!(matches_workflow_glob("_repo-config.yaml"));
        assert!(matches_workflow_glob("weird.y_anything_ml"));
        assert!(!matches_workflow_glob(".hidden.yaml"));
        assert!(!matches_workflow_glob("README.md"));
        assert!(!matches_workflow_glob(".yml"));
    }

    #[test]
    fn test_has_line() {
        assert!(has_line("FOO", "BAR\nFOO\nBAZ"));
        assert!(!has_line("FOO", "FOO_BAR\nBAR_FOO"));
        assert!(!has_line("FOO", ""));
    }

    #[test]
    fn test_parse_args() {
        let c = Colors::for_tty(false);
        assert_eq!(
            parse_args(
                &["--list".to_string()],
                "org/repo".to_string(),
                &c,
                "ci-preflight"
            ),
            Ok(ParsedArgs::Run {
                list_only: true,
                repo_slug: "org/repo".to_string()
            })
        );
        assert_eq!(
            parse_args(
                &["--repo".to_string(), "a/b".to_string()],
                "".to_string(),
                &c,
                "ci-preflight"
            ),
            Ok(ParsedArgs::Run {
                list_only: false,
                repo_slug: "a/b".to_string()
            })
        );
        assert_eq!(
            parse_args(&["-h".to_string()], "".to_string(), &c, "ci-preflight"),
            Ok(ParsedArgs::Help)
        );
        let err_missing =
            parse_args(&["--repo".to_string()], "".to_string(), &c, "ci-preflight").unwrap_err();
        assert_eq!(err_missing.1, 1);
        assert!(err_missing.0.contains("--repo needs owner/name"));

        let err_unknown =
            parse_args(&["--bogus".to_string()], "".to_string(), &c, "ci-preflight").unwrap_err();
        assert_eq!(err_unknown.1, 2);
        assert!(err_unknown.0.contains("unknown flag: --bogus"));
    }

    #[test]
    fn test_bash_read_lines() {
        assert_eq!(bash_read_lines(""), Vec::<&str>::new());
        assert_eq!(bash_read_lines("prod\nstaging\n"), vec!["prod", "staging"]);
        assert_eq!(bash_read_lines("prod\nunterminated"), vec!["prod"]);
    }

    #[test]
    fn test_sort_u_locale_dedup() {
        init_locale();
        let mut items = vec![
            "B".to_string(),
            "A".to_string(),
            "B".to_string(),
            "A".to_string(),
        ];
        sort_u_locale(&mut items);
        assert_eq!(items, vec!["A".to_string(), "B".to_string()]);
    }

    #[cfg(unix)]
    #[test]
    fn test_parse_args_os_preserves_non_utf8_bytes() {
        let c = Colors::for_tty(false);
        let bad_flag = OsString::from_vec(b"--bad\xffflag".to_vec());
        let (msg, line_no, is_printf, code) = parse_args_os(
            &[bad_flag],
            OsString::new(),
            &c,
            OsStr::from_bytes(b"prog\xfe"),
        )
        .unwrap_err();
        assert_eq!(line_no, 86);
        assert!(is_printf);
        assert_eq!(code, 2);
        assert!(msg.ends_with(b"--bad\xffflag\n"));
    }

    #[test]
    fn test_bash_read_lines_bytes() {
        assert_eq!(bash_read_lines_bytes(b""), Vec::<&[u8]>::new());
        assert_eq!(
            bash_read_lines_bytes(b"pr\xffod\nstaging\n"),
            vec![&b"pr\xffod"[..], &b"staging"[..]]
        );
    }
}
