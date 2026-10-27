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

use std::cmp::Ordering as CmpOrdering;
use std::ffi::{CStr, OsStr, OsString};
use std::fs::{self, OpenOptions};
use std::io::{self, IsTerminal, Write};
use std::os::raw::{c_char, c_void};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::MetadataExt;
use std::os::unix::process::ExitStatusExt;
use std::path::Path;
use std::process::{Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

const TIDY_SH_SOURCE: &str = r#"#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# tidy.sh — keep the `replace`-coupled Go modules' pins in sync.
#
#   bazel run //tools/gomod:tidy     # fix:   rewrite go.mod/go.sum in place
#   bazel run //tools/gomod:check    # gate:  report drift, change nothing
#
# WHY THIS EXISTS — the example modules duplicate the library's dep graph:
#   Every module under pulumi/examples/go-foundation consumes the library
#   through a `replace` to a LOCAL PATH, but still carries its own full pin of
#   the library's transitive graph (`google.golang.org/grpc v1.80.0 // indirect`
#   and friends) in its own go.mod/go.sum.
#
#   Nothing keeps those two copies in step. Dependabot tidies ONLY the module it
#   bumps -- it cannot see across a `replace` edge -- so bumping a library leaves
#   every example that consumes it unbuildable. That is not hypothetical: PRs
#   #1166/#1175/#1179 (grpc 1.80.0 -> 1.82.1) each red-lined `example-build`
#   this way, and the error the developer actually saw was:
#
#       go: updates to go.mod needed; to update it:
#           go mod tidy
#
#   -- which names no module, no dependency, and no PR. Three separate bumps
#   were diagnosed from scratch before the shared cause was obvious.
#
# WHAT THIS FIXES, AND WHAT IT DOES NOT:
#   This is the GATE, not the cure. It cannot stop a bump from desyncing the
#   examples; it makes the desync fail EARLY and LEGIBLY, against the module and
#   the diff that caused it, with the exact command that fixes it. The
#   complementary half lives in .github/dependabot.yml, which groups the library
#   and example directories into one update so a shared dependency moves on both
#   sides in the same PR -- that reduces how often this gate fires, but grouping
#   only covers deps that ALREADY exist in both go.mods, so it can never be the
#   whole answer. Hence both.
#
# WHY `go mod tidy -diff` AND NOT tidy-then-`git diff`:
#   -diff (Go 1.23+) computes the necessary changes and exits non-zero WITHOUT
#   writing. The tidy-then-diff alternative mutates the tree inside a required
#   check -- exactly the failure mode tools/osv-scan/osv-scan.sh documents at
#   length (a gate that rewrites go.work.sum corrupts the checkout it is
#   inspecting and reddens tidy-check two jobs later). Check mode here is
#   read-only by construction, not by convention.
#
# GOWORK=off, deliberately:
#   Same reason the rest of this repo's Go CI sets it. In workspace mode `go mod
#   tidy` resolves against the workspace, not the module's own requirements, so
#   it would compute a DIFFERENT (and wrong) answer than the standalone `go
#   build` that example-build runs -- and could normalise go.work.sum as a side
#   effect. The examples are also copybara-exported as standalone modules, so
#   the standalone resolution is the only one that matches how they ship.
set -euo pipefail

"#;

extern "C" {
    fn setlocale(category: i32, locale: *const c_char) -> *mut c_char;
    fn strcoll(s1: *const c_char, s2: *const c_char) -> i32;
    fn signal(sig: i32, handler: usize) -> usize;
    fn unlink(path: *const c_char) -> i32;
    fn raise(sig: i32) -> i32;
    fn strerror(errnum: i32) -> *const c_char;
    fn access(path: *const c_char, amode: i32) -> i32;
    fn write(fd: i32, buf: *const c_void, count: usize) -> isize;
}

#[cfg(target_os = "macos")]
const LC_ALL: i32 = 0;
#[cfg(not(target_os = "macos"))]
const LC_ALL: i32 = 6;

const SIGHUP: i32 = 1;
const SIGINT: i32 = 2;
const SIGPIPE: i32 = 13;
const SIGTERM: i32 = 15;
const SIG_DFL: usize = 0;
const SIG_IGN: usize = 1;
const SIG_ERR: usize = usize::MAX;
const X_OK: i32 = 1;

static mut DIFF_FILE_PATH: [u8; 4096] = [0; 4096];
static DIFF_FILE_READY: AtomicBool = AtomicBool::new(false);
static PREV_SIGHUP: AtomicUsize = AtomicUsize::new(SIG_DFL);
static PREV_SIGINT: AtomicUsize = AtomicUsize::new(SIG_DFL);
static PREV_SIGTERM: AtomicUsize = AtomicUsize::new(SIG_DFL);
static PREV_SIGPIPE: AtomicUsize = AtomicUsize::new(SIG_DFL);

extern "C" fn cleanup_signal_handler(sig: i32) {
    unsafe {
        if DIFF_FILE_READY.load(Ordering::SeqCst) {
            let _ = unlink(DIFF_FILE_PATH.as_ptr() as *const c_char);
        }
        let prev = match sig {
            SIGHUP => PREV_SIGHUP.load(Ordering::SeqCst),
            SIGINT => PREV_SIGINT.load(Ordering::SeqCst),
            SIGTERM => PREV_SIGTERM.load(Ordering::SeqCst),
            SIGPIPE => PREV_SIGPIPE.load(Ordering::SeqCst),
            _ => SIG_DFL,
        };
        let restore = if prev == SIG_ERR { SIG_DFL } else { prev };
        signal(sig, restore);
        raise(sig);
    }
}

fn install_trap_signal(sig: i32, slot: &AtomicUsize) {
    unsafe {
        let prev = signal(sig, SIG_IGN);
        slot.store(prev, Ordering::SeqCst);
        if prev != SIG_IGN && prev != SIG_ERR {
            let handler = cleanup_signal_handler as *const () as usize;
            signal(sig, handler);
        }
    }
}

struct TempFileGuard {
    path: Vec<u8>,
}

impl TempFileGuard {
    fn new(path: Vec<u8>) -> Self {
        unsafe {
            if path.len() < DIFF_FILE_PATH.len() && !path.contains(&0) {
                DIFF_FILE_PATH[..path.len()].copy_from_slice(&path);
                DIFF_FILE_PATH[path.len()] = 0;
                DIFF_FILE_READY.store(true, Ordering::SeqCst);
            }
        }
        install_trap_signal(SIGHUP, &PREV_SIGHUP);
        install_trap_signal(SIGINT, &PREV_SIGINT);
        install_trap_signal(SIGTERM, &PREV_SIGTERM);
        install_trap_signal(SIGPIPE, &PREV_SIGPIPE);
        Self { path }
    }
}

impl Drop for TempFileGuard {
    fn drop(&mut self) {
        DIFF_FILE_READY.store(false, Ordering::SeqCst);
        for (sig, slot) in [
            (SIGHUP, &PREV_SIGHUP),
            (SIGINT, &PREV_SIGINT),
            (SIGTERM, &PREV_SIGTERM),
            (SIGPIPE, &PREV_SIGPIPE),
        ] {
            let prev = slot.load(Ordering::SeqCst);
            if prev != SIG_IGN && prev != SIG_ERR {
                unsafe {
                    signal(sig, prev);
                }
            }
        }
        let _ = fs::remove_file(OsStr::from_bytes(&self.path));
    }
}

pub const GLYPH_OK: &str = "✓";
pub const GLYPH_FAIL: &str = "✗";

pub const DEFAULT_ROOTS: &[&str] = &[
    "packages/pulumi/library/go",
    "packages/pulumi/examples/go-foundation",
    "infrastructure/pulumi/platform/repo-config",
];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Palette {
    pub red: &'static str,
    pub green: &'static str,
    pub yellow: &'static str,
    pub cyan: &'static str,
    pub reset: &'static str,
}

impl Palette {
    pub const COLOR: Self = Self {
        red: "\x1b[31m",
        green: "\x1b[32m",
        yellow: "\x1b[33m",
        cyan: "\x1b[36m",
        reset: "\x1b[0m",
    };

    pub const PLAIN: Self = Self {
        red: "",
        green: "",
        yellow: "",
        cyan: "",
        reset: "",
    };

    pub fn for_tty(is_tty: bool) -> Self {
        if is_tty {
            Self::COLOR
        } else {
            Self::PLAIN
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    Fix,
    Check,
}

#[derive(Debug, PartialEq, Eq)]
pub enum ParseOutcome {
    Help,
    UnknownFlag(String),
    Run { mode: Mode, roots: Vec<String> },
}

#[derive(Debug, PartialEq, Eq)]
pub enum ParseOutcomeOs {
    Help,
    UnknownFlag(Vec<u8>),
    Run { mode: Mode, roots: Vec<Vec<u8>> },
}

#[derive(Debug, PartialEq, Eq)]
pub enum CollectError {
    MissingModule(String),
    MissingRoot(String),
    ZeroModules(String),
}

#[derive(Debug, PartialEq, Eq)]
pub enum CollectErrorOs {
    MissingModule(Vec<u8>),
    MissingRoot(Vec<u8>),
    ZeroModules(Vec<u8>),
}

fn write_fd_all(fd: i32, mut bytes: &[u8]) -> io::Result<()> {
    while !bytes.is_empty() {
        let n = unsafe { write(fd, bytes.as_ptr() as *const c_void, bytes.len()) };
        if n < 0 {
            let err = io::Error::last_os_error();
            if err.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(err);
        }
        if n == 0 {
            return Err(io::Error::new(
                io::ErrorKind::WriteZero,
                "failed to write whole buffer",
            ));
        }
        bytes = &bytes[n as usize..];
    }
    Ok(())
}

fn write_stderr(bytes: &[u8]) {
    let _ = write_fd_all(2, bytes);
}

fn os_error_message(err: &io::Error) -> Vec<u8> {
    if let Some(errno) = err.raw_os_error() {
        unsafe {
            let ptr = strerror(errno);
            if !ptr.is_null() {
                return CStr::from_ptr(ptr).to_bytes().to_vec();
            }
        }
    }
    let s = err.to_string();
    if let Some(idx) = s.rfind(" (os error ") {
        s[..idx].as_bytes().to_vec()
    } else {
        s.into_bytes()
    }
}

fn report_builtin_write_error(argv0: &[u8], line: usize, builtin: &[u8], err: &io::Error) {
    let mut msg = Vec::new();
    msg.extend_from_slice(argv0);
    msg.extend_from_slice(format!(": line {line}: ").as_bytes());
    msg.extend_from_slice(builtin);
    msg.extend_from_slice(b": write error: ");
    msg.extend_from_slice(&os_error_message(err));
    msg.push(b'\n');
    write_stderr(&msg);
}

fn printf_stdout(argv0: &[u8], line: usize, bytes: &[u8]) -> Result<(), i32> {
    if let Err(e) = write_fd_all(1, bytes) {
        report_builtin_write_error(argv0, line, b"printf", &e);
        return Err(1);
    }
    Ok(())
}

fn printf_stderr(argv0: &[u8], line: usize, bytes: &[u8]) -> Result<(), i32> {
    if let Err(e) = write_fd_all(2, bytes) {
        report_builtin_write_error(argv0, line, b"printf", &e);
        return Err(1);
    }
    Ok(())
}

fn exit_status_code(status: ExitStatus) -> i32 {
    if let Some(code) = status.code() {
        code
    } else if let Some(sig) = status.signal() {
        128 + sig
    } else {
        1
    }
}

/// Compare two byte strings using the active C locale (`strcoll`), falling back
/// to byte comparison (`memcmp`) on ties to match `sort(1)`'s last-resort order.
pub fn locale_cmp(a: &[u8], b: &[u8]) -> CmpOrdering {
    let mut ca = Vec::with_capacity(a.len() + 1);
    for &byte in a {
        if byte == 0 {
            break;
        }
        ca.push(byte);
    }
    ca.push(0);
    let mut cb = Vec::with_capacity(b.len() + 1);
    for &byte in b {
        if byte == 0 {
            break;
        }
        cb.push(byte);
    }
    cb.push(0);
    let res = unsafe { strcoll(ca.as_ptr() as *const c_char, cb.as_ptr() as *const c_char) };
    match res.cmp(&0) {
        CmpOrdering::Equal => a.cmp(b),
        ord => ord,
    }
}

/// Extract lines 21..=70 of `tidy.sh`, matching `sed -n '21,70p' "$0"`.
pub fn help_text() -> String {
    let mut out = String::new();
    for line in TIDY_SH_SOURCE.lines().skip(20).take(50) {
        out.push_str(line);
        out.push('\n');
    }
    out
}

/// Parse command-line arguments (excluding argv[0]) as raw byte slices with exact `tidy.sh` semantics.
pub fn parse_args_os<I, S>(args: I) -> ParseOutcomeOs
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let mut mode = Mode::Fix;
    let mut roots: Vec<Vec<u8>> = Vec::new();
    for raw in args {
        let arg = raw.as_ref().as_bytes();
        match arg {
            b"--check" => mode = Mode::Check,
            b"--fix" => mode = Mode::Fix,
            b"-h" | b"--help" => return ParseOutcomeOs::Help,
            s if s.starts_with(b"-") => return ParseOutcomeOs::UnknownFlag(s.to_vec()),
            s => roots.push(s.to_vec()),
        }
    }
    if roots.is_empty() {
        roots = DEFAULT_ROOTS
            .iter()
            .map(|s| s.as_bytes().to_vec())
            .collect();
    }
    ParseOutcomeOs::Run { mode, roots }
}

/// Parse command-line arguments (excluding argv[0]) with exact `tidy.sh` semantics.
pub fn parse_args<I, S>(args: I) -> ParseOutcome
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    match parse_args_os(args.into_iter().map(|s| OsString::from(s.as_ref()))) {
        ParseOutcomeOs::Help => ParseOutcome::Help,
        ParseOutcomeOs::UnknownFlag(b) => {
            ParseOutcome::UnknownFlag(String::from_utf8_lossy(&b).into_owned())
        }
        ParseOutcomeOs::Run { mode, roots } => ParseOutcome::Run {
            mode,
            roots: roots
                .into_iter()
                .map(|b| String::from_utf8_lossy(&b).into_owned())
                .collect(),
        },
    }
}

/// POSIX `dirname(1)` byte implementation.
pub fn posix_dirname_bytes(path: &[u8]) -> Vec<u8> {
    if path.is_empty() {
        return b".".to_vec();
    }
    if path.iter().all(|&b| b == b'/') {
        return b"/".to_vec();
    }
    let mut end = path.len();
    while end > 0 && path[end - 1] == b'/' {
        end -= 1;
    }
    let trimmed = &path[..end];
    let Some(slash_idx) = trimmed.iter().rposition(|&b| b == b'/') else {
        return b".".to_vec();
    };
    let mut parent_end = slash_idx;
    while parent_end > 0 && trimmed[parent_end - 1] == b'/' {
        parent_end -= 1;
    }
    if parent_end == 0 {
        b"/".to_vec()
    } else {
        trimmed[..parent_end].to_vec()
    }
}

/// POSIX `dirname(1)` string implementation.
pub fn posix_dirname(path: &str) -> String {
    String::from_utf8_lossy(&posix_dirname_bytes(path.as_bytes())).into_owned()
}

/// Compute logical `PWD` after `cd <target>` from `current_pwd` in raw bytes.
pub fn logical_cd_bytes(current_pwd: &[u8], target: &[u8]) -> Vec<u8> {
    let mut combined = Vec::new();
    if target.starts_with(b"/") {
        combined.extend_from_slice(target);
    } else {
        combined.extend_from_slice(current_pwd);
        if !current_pwd.ends_with(b"/") {
            combined.push(b'/');
        }
        combined.extend_from_slice(target);
    }
    let mut parts: Vec<&[u8]> = Vec::new();
    for seg in combined.split(|&b| b == b'/') {
        match seg {
            b"" | b"." => {}
            b".." => {
                parts.pop();
            }
            s => parts.push(s),
        }
    }
    if parts.is_empty() {
        b"/".to_vec()
    } else {
        let mut out = Vec::new();
        for part in parts {
            out.push(b'/');
            out.extend_from_slice(part);
        }
        out
    }
}

/// Compute logical `PWD` after `cd <target>` from `current_pwd`.
pub fn logical_cd(current_pwd: &str, target: &str) -> String {
    String::from_utf8_lossy(&logical_cd_bytes(current_pwd.as_bytes(), target.as_bytes()))
        .into_owned()
}

/// Format captured `go mod tidy -diff` output with 5-space indentation in raw bytes,
/// matching `printf '%s\n' "$diff_out" | sed 's/^/     /'`.
pub fn indent_diff_bytes(diff_out: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(diff_out.len() + 32);
    for line in diff_out.split(|&b| b == b'\n') {
        out.extend_from_slice(b"     ");
        out.extend_from_slice(line);
        out.push(b'\n');
    }
    out
}

/// Format captured `go mod tidy -diff` output with 5-space indentation,
/// matching `printf '%s\n' "$diff_out" | sed 's/^/     /'`.
pub fn indent_diff(diff_out: &str) -> String {
    String::from_utf8_lossy(&indent_diff_bytes(diff_out.as_bytes())).into_owned()
}

/// Locate `tools/ci/transient-lib.sh` using the exact candidate list and order of `tidy.sh`.
pub fn locate_transient_lib(argv0: &[u8], self_dir: &[u8], root: &[u8]) -> Option<Vec<u8>> {
    let runfiles_base = match std::env::var_os("RUNFILES_DIR") {
        Some(v) if !v.as_bytes().is_empty() => v.as_bytes().to_vec(),
        _ => {
            let mut b = argv0.to_vec();
            b.extend_from_slice(b".runfiles");
            b
        }
    };
    let mut cand1 = runfiles_base;
    cand1.extend_from_slice(b"/_main/tools/ci/transient-lib.sh");

    let mut cand2 = self_dir.to_vec();
    cand2.extend_from_slice(b"/../ci/transient-lib.sh");

    let mut cand3 = root.to_vec();
    cand3.extend_from_slice(b"/tools/ci/transient-lib.sh");

    for cand in [cand1, cand2, cand3] {
        if Path::new(OsStr::from_bytes(&cand)).is_file() {
            return Some(cand);
        }
    }
    None
}

fn source_transient_lib_startup(argv0: &[u8], transient_lib: &[u8]) -> Result<(), i32> {
    let mut script = Vec::with_capacity(105 + 120);
    script.resize(105, b'\n');
    script.extend_from_slice(
        b"set -euo pipefail; if [ \"${BASH_VERSINFO[0]}\" -ge 4 ]; then . \"$1\"; else\n. \"$1\"; fi",
    );
    match Command::new("bash")
        .env_remove("BASH_ENV")
        .env_remove("ENV")
        .arg("-c")
        .arg(OsStr::from_bytes(&script))
        .arg(OsStr::from_bytes(argv0))
        .arg(OsStr::from_bytes(transient_lib))
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
    {
        Ok(s) if s.success() => Ok(()),
        Ok(s) => Err(exit_status_code(s)),
        Err(e) => Err(report_exec_error(argv0, 106, b"bash", &e)),
    }
}

/// Classify whether `diff_file` contains a transient network error by shelling out to
/// `tools/ci/transient-lib.sh`, keeping a single authoritative copy of the regex.
pub fn is_transient_network_error_file(transient_lib: &[u8], diff_file: &[u8]) -> bool {
    Command::new("bash")
        .env_remove("BASH_ENV")
        .env_remove("ENV")
        .arg("-c")
        .arg(". \"$1\"; is_transient_network_error \"$2\"")
        .arg("_")
        .arg(OsStr::from_bytes(transient_lib))
        .arg(OsStr::from_bytes(diff_file))
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn is_file_executable(candidate: &Path) -> bool {
    let Ok(meta) = fs::metadata(candidate) else {
        return false;
    };
    if !meta.is_file() {
        return false;
    }
    let bytes = candidate.as_os_str().as_bytes();
    if bytes.contains(&0) {
        return false;
    }
    let mut c_path = Vec::with_capacity(bytes.len() + 1);
    c_path.extend_from_slice(bytes);
    c_path.push(0);
    unsafe { access(c_path.as_ptr() as *const c_char, X_OK) == 0 }
}

/// Check if an executable file named `prog` exists on `PATH` (`command -v <prog>`).
pub fn is_executable_on_path_bytes(prog: &[u8]) -> bool {
    let Some(path_var) = std::env::var_os("PATH") else {
        return false;
    };
    if path_var.is_empty() {
        return false;
    }
    for entry in path_var.as_bytes().split(|&b| b == b':') {
        let dir = if entry.is_empty() {
            Path::new(".")
        } else {
            Path::new(OsStr::from_bytes(entry))
        };
        let candidate = dir.join(OsStr::from_bytes(prog));
        if is_file_executable(&candidate) {
            return true;
        }
    }
    false
}

/// Check if an executable file named `prog` exists on `PATH` (`command -v <prog>`).
pub fn is_executable_on_path(prog: &str) -> bool {
    is_executable_on_path_bytes(prog.as_bytes())
}

fn find_first_file_on_path(prog: &[u8]) -> Option<Vec<u8>> {
    let path_var = std::env::var_os("PATH")?;
    for entry in path_var.as_bytes().split(|&b| b == b':') {
        let dir = if entry.is_empty() {
            Path::new(".")
        } else {
            Path::new(OsStr::from_bytes(entry))
        };
        let candidate = dir.join(OsStr::from_bytes(prog));
        if candidate.exists() {
            return Some(candidate.into_os_string().into_vec());
        }
    }
    None
}

fn report_exec_error(argv0: &[u8], line: usize, prog: &[u8], err: &io::Error) -> i32 {
    let mut msg = Vec::new();
    msg.extend_from_slice(argv0);
    msg.extend_from_slice(format!(": line {line}: ").as_bytes());
    match err.kind() {
        io::ErrorKind::NotFound => {
            msg.extend_from_slice(prog);
            msg.extend_from_slice(b": command not found\n");
            write_stderr(&msg);
            127
        }
        io::ErrorKind::PermissionDenied => {
            let display_prog = find_first_file_on_path(prog).unwrap_or_else(|| prog.to_vec());
            msg.extend_from_slice(&display_prog);
            msg.extend_from_slice(b": ");
            msg.extend_from_slice(&os_error_message(err));
            msg.push(b'\n');
            write_stderr(&msg);
            126
        }
        _ => {
            msg.extend_from_slice(prog);
            msg.extend_from_slice(b": ");
            msg.extend_from_slice(&os_error_message(err));
            msg.push(b'\n');
            write_stderr(&msg);
            1
        }
    }
}

/// Find `go.mod` files under `root` excluding `*/vendor/*` by running `find` and sorting
/// its output in the user's locale (`setlocale(LC_ALL, "")` + `strcoll`), matching `tidy.sh`.
pub fn find_gomod_files_bytes(root: &[u8]) -> Vec<Vec<u8>> {
    unsafe {
        setlocale(LC_ALL, b"\0".as_ptr() as *const c_char);
    }
    let out = Command::new("find")
        .arg(OsStr::from_bytes(root))
        .args(["-name", "go.mod", "-not", "-path", "*/vendor/*"])
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .output();
    let Ok(out) = out else {
        return Vec::new();
    };
    if out.stdout.is_empty() {
        return Vec::new();
    }
    let trimmed = out.stdout.strip_suffix(b"\n").unwrap_or(&out.stdout);
    let mut lines: Vec<Vec<u8>> = trimmed
        .split(|&b| b == b'\n')
        .map(|line| line.to_vec())
        .collect();
    lines.sort_by(|a, b| locale_cmp(a, b));
    lines
}

/// Recursively find `go.mod` files under `root` excluding `*/vendor/*`, sorted in locale order.
pub fn find_gomod_files(root: &str) -> Vec<String> {
    find_gomod_files_bytes(root.as_bytes())
        .into_iter()
        .map(|b| String::from_utf8_lossy(&b).into_owned())
        .collect()
}

fn join_bytes_space(items: &[Vec<u8>]) -> Vec<u8> {
    let mut out = Vec::new();
    for (idx, item) in items.iter().enumerate() {
        if idx > 0 {
            out.push(b' ');
        }
        out.extend_from_slice(item);
    }
    out
}

/// Collect module directories from `roots` (as raw bytes) following `tidy.sh` rules.
pub fn collect_modules_os(roots: &[Vec<u8>]) -> Result<Vec<Vec<u8>>, CollectErrorOs> {
    let mut mods = Vec::new();
    for root in roots {
        if root.ends_with(b"/go.mod") {
            if !Path::new(OsStr::from_bytes(root)).is_file() {
                return Err(CollectErrorOs::MissingModule(root.clone()));
            }
            mods.push(posix_dirname_bytes(root));
        } else {
            if !Path::new(OsStr::from_bytes(root)).is_dir() {
                return Err(CollectErrorOs::MissingRoot(root.clone()));
            }
            for mod_file in find_gomod_files_bytes(root) {
                mods.push(posix_dirname_bytes(&mod_file));
            }
        }
    }
    if mods.is_empty() {
        return Err(CollectErrorOs::ZeroModules(join_bytes_space(roots)));
    }
    Ok(mods)
}

/// Collect module directories from `roots` following `tidy.sh` rules.
pub fn collect_modules(roots: &[String]) -> Result<Vec<String>, CollectError> {
    let byte_roots: Vec<Vec<u8>> = roots.iter().map(|s| s.as_bytes().to_vec()).collect();
    match collect_modules_os(&byte_roots) {
        Ok(mods) => Ok(mods
            .into_iter()
            .map(|b| String::from_utf8_lossy(&b).into_owned())
            .collect()),
        Err(CollectErrorOs::MissingModule(m)) => Err(CollectError::MissingModule(
            String::from_utf8_lossy(&m).into_owned(),
        )),
        Err(CollectErrorOs::MissingRoot(r)) => Err(CollectError::MissingRoot(
            String::from_utf8_lossy(&r).into_owned(),
        )),
        Err(CollectErrorOs::ZeroModules(z)) => Err(CollectError::ZeroModules(
            String::from_utf8_lossy(&z).into_owned(),
        )),
    }
}

fn resolve_initial_pwd() -> Vec<u8> {
    if let Some(pwd_os) = std::env::var_os("PWD") {
        let pwd_bytes = pwd_os.as_bytes();
        if pwd_bytes.starts_with(b"/") {
            if let (Ok(m_pwd), Ok(m_dot)) = (fs::metadata(&pwd_os), fs::metadata(".")) {
                if m_pwd.dev() == m_dot.dev() && m_pwd.ino() == m_dot.ino() {
                    return pwd_os.into_vec();
                }
            }
        }
    }
    let cwd = std::env::current_dir()
        .ok()
        .map(|p| p.into_os_string().into_vec())
        .unwrap_or_else(|| b"/".to_vec());
    std::env::set_var("PWD", OsStr::from_bytes(&cwd));
    cwd
}

fn resolve_root_dir(initial_pwd: &[u8]) -> Vec<u8> {
    if let Some(val) = std::env::var_os("BUILD_WORKSPACE_DIRECTORY") {
        if !val.as_bytes().is_empty() {
            return val.into_vec();
        }
    }
    if let Ok(out) = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
    {
        if out.status.success() {
            let mut stdout = out.stdout;
            while stdout.last() == Some(&b'\n') {
                stdout.pop();
            }
            return stdout;
        }
    }
    initial_pwd.to_vec()
}

fn read_mod_and_sum_snapshot(argv0: &[u8], line: usize, dir: &[u8]) -> Result<Vec<u8>, i32> {
    let mut sum_path = dir.to_vec();
    sum_path.extend_from_slice(b"/go.sum");
    if !Path::new(OsStr::from_bytes(&sum_path)).is_file() {
        return Ok(Vec::new());
    }
    let mut mod_path = dir.to_vec();
    mod_path.extend_from_slice(b"/go.mod");
    let out = match Command::new("cat")
        .arg(OsStr::from_bytes(&mod_path))
        .arg(OsStr::from_bytes(&sum_path))
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .output()
    {
        Ok(o) => o,
        Err(e) => return Err(report_exec_error(argv0, line, b"cat", &e)),
    };
    if !out.status.success() {
        return Err(exit_status_code(out.status));
    }
    let mut buf = out.stdout;
    while buf.last() == Some(&b'\n') {
        buf.pop();
    }
    Ok(buf)
}

fn create_temp_diff_file(argv0: &[u8]) -> Result<TempFileGuard, i32> {
    let out = match Command::new("mktemp")
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .output()
    {
        Ok(o) => o,
        Err(e) => return Err(report_exec_error(argv0, 217, b"mktemp", &e)),
    };
    if !out.status.success() {
        return Err(exit_status_code(out.status));
    }
    let mut path = out.stdout;
    while path.last() == Some(&b'\n') {
        path.pop();
    }
    Ok(TempFileGuard::new(path))
}

fn write_diff_file(argv0: &[u8], path: &[u8], diff_out: &[u8]) -> Result<(), i32> {
    let mut file = match OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(OsStr::from_bytes(path))
    {
        Ok(f) => f,
        Err(e) => {
            let mut msg = Vec::new();
            msg.extend_from_slice(argv0);
            msg.extend_from_slice(b": line 249: ");
            msg.extend_from_slice(path);
            msg.extend_from_slice(b": ");
            msg.extend_from_slice(&os_error_message(&e));
            msg.push(b'\n');
            write_stderr(&msg);
            return Err(1);
        }
    };
    if !diff_out.is_empty() {
        if let Err(e) = file.write_all(diff_out).and_then(|_| file.flush()) {
            report_builtin_write_error(argv0, 249, b"printf", &e);
            return Err(1);
        }
    }
    Ok(())
}

fn run_help_sed(argv0: &[u8]) -> i32 {
    let mut child = match Command::new("sed")
        .args(["-n", "21,70p"])
        .stdin(Stdio::piped())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()
    {
        Ok(c) => c,
        Err(e) => return report_exec_error(argv0, 152, b"sed", &e),
    };
    if let Some(mut stdin) = child.stdin.take() {
        let prev_pipe = unsafe { signal(SIGPIPE, SIG_IGN) };
        let _ = stdin.write_all(TIDY_SH_SOURCE.as_bytes());
        drop(stdin);
        if prev_pipe != SIG_ERR {
            unsafe {
                signal(SIGPIPE, prev_pipe);
            }
        }
    }
    match child.wait() {
        Ok(status) => exit_status_code(status),
        Err(_) => 1,
    }
}

fn run_indent_diff_sed(argv0: &[u8], diff_out: &[u8]) -> Result<(), i32> {
    let mut child = match Command::new("sed")
        .arg("s/^/     /")
        .stdin(Stdio::piped())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()
    {
        Ok(c) => c,
        Err(e) => return Err(report_exec_error(argv0, 268, b"sed", &e)),
    };
    if let Some(mut stdin) = child.stdin.take() {
        let prev_pipe = unsafe { signal(SIGPIPE, SIG_IGN) };
        let _ = stdin.write_all(diff_out);
        let _ = stdin.write_all(b"\n");
        drop(stdin);
        if prev_pipe != SIG_ERR {
            unsafe {
                signal(SIGPIPE, prev_pipe);
            }
        }
    }
    match child.wait() {
        Ok(status) if status.success() => Ok(()),
        Ok(status) => Err(exit_status_code(status)),
        Err(_) => Err(1),
    }
}

fn build_bash_subshell_command(
    argv0: &[u8],
    dir: &[u8],
    script_after_env_restore: &[u8],
) -> Command {
    let orig_bash_env = std::env::var_os("BASH_ENV");
    let orig_env = std::env::var_os("ENV");

    let mut full_script = Vec::with_capacity(script_after_env_restore.len() + 64);
    if orig_bash_env.is_some() {
        full_script.extend_from_slice(b"export BASH_ENV=\"$2\"; ");
    }
    if orig_env.is_some() {
        full_script.extend_from_slice(b"export ENV=\"$3\"; ");
    }
    full_script.extend_from_slice(script_after_env_restore);

    let mut cmd = Command::new("bash");
    cmd.env_remove("BASH_ENV")
        .env_remove("ENV")
        .arg("-c")
        .arg(OsStr::from_bytes(&full_script))
        .arg(OsStr::from_bytes(argv0))
        .arg(OsStr::from_bytes(dir))
        .arg(orig_bash_env.unwrap_or_default())
        .arg(orig_env.unwrap_or_default());
    cmd
}

fn run_go_mod_tidy_diff(argv0: &[u8], dir: &[u8]) -> (bool, Vec<u8>) {
    let mut script = Vec::with_capacity(245 + 120);
    script.resize(245, b'\n');
    script.extend_from_slice(
        b"if [ \"${BASH_VERSINFO[0]}\" -ge 4 ]; then cd \"$1\" && go mod tidy -diff 2>&1; else\ncd \"$1\" && go mod tidy -diff 2>&1; fi",
    );
    let out = build_bash_subshell_command(argv0, dir, &script)
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .output();
    match out {
        Ok(o) => {
            let mut stdout = o.stdout;
            while stdout.last() == Some(&b'\n') {
                stdout.pop();
            }
            (o.status.success(), stdout)
        }
        Err(_) => (false, Vec::new()),
    }
}

fn run_go_mod_tidy_fix(argv0: &[u8], dir: &[u8]) -> Result<(), i32> {
    let mut script = Vec::with_capacity(235 + 38 + 140);
    script.resize(235, b'\n');
    script.extend_from_slice(b"for _ in 1; do");
    script.resize(script.len() + 38, b'\n');
    script.extend_from_slice(
        b"if [ \"${BASH_VERSINFO[0]}\" -ge 4 ]; then (cd \"$1\" && go mod tidy); else\n(cd \"$1\" && go mod tidy); fi; done",
    );
    let status = build_bash_subshell_command(argv0, dir, &script)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status();
    match status {
        Ok(s) if s.success() => Ok(()),
        Ok(s) => Err(exit_status_code(s)),
        Err(e) => Err(report_exec_error(argv0, 274, b"bash", &e)),
    }
}

fn sleep_backoff(argv0: &[u8], seconds: u64) -> Result<(), i32> {
    match Command::new("sleep")
        .arg(seconds.to_string())
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
    {
        Ok(status) if status.success() => Ok(()),
        Ok(status) => Err(exit_status_code(status)),
        Err(e) => Err(report_exec_error(argv0, 253, b"sleep", &e)),
    }
}

/// Entrypoint accepting the full `args_os` iterator (including `argv[0]`).
pub fn run_os<I, S>(args_os: I) -> i32
where
    I: IntoIterator<Item = S>,
    S: Into<OsString>,
{
    let mut iter = args_os.into_iter().map(Into::into);
    let argv0 = iter
        .next()
        .map(|s| s.into_vec())
        .unwrap_or_else(|| b"tidy".to_vec());
    let rest: Vec<OsString> = iter.collect();
    run_with_argv0(&argv0, &rest)
}

/// Entrypoint accepting CLI arguments (excluding `argv[0]`). Returns process exit code.
pub fn run<I, S>(args: I) -> i32
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    let argv0 = std::env::args_os()
        .next()
        .map(|s| s.into_vec())
        .unwrap_or_else(|| b"tidy".to_vec());
    let rest: Vec<OsString> = args
        .into_iter()
        .map(|s| OsString::from(s.as_ref()))
        .collect();
    run_with_argv0(&argv0, &rest)
}

fn run_with_argv0(argv0: &[u8], args: &[OsString]) -> i32 {
    unsafe {
        setlocale(LC_ALL, b"\0".as_ptr() as *const c_char);
    }

    // Replicate non-interactive bash reading BASH_ENV once at script startup.
    if let Some(bash_env) = std::env::var_os("BASH_ENV") {
        if !bash_env.is_empty() {
            match Command::new("bash")
                .arg("-c")
                .arg(":")
                .arg(OsStr::from_bytes(argv0))
                .stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .status()
            {
                Ok(s) if s.success() => {}
                Ok(s) => return exit_status_code(s),
                Err(_) => {}
            }
        }
    }

    let initial_pwd = resolve_initial_pwd();

    // Line 74: SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    let self_dir = logical_cd_bytes(&initial_pwd, &posix_dirname_bytes(argv0));

    // Lines 76-77: ROOT="${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
    //              cd "${ROOT}"
    let root = resolve_root_dir(&initial_pwd);
    if let Err(e) = std::env::set_current_dir(OsStr::from_bytes(&root)) {
        let mut msg = Vec::new();
        msg.extend_from_slice(argv0);
        msg.extend_from_slice(b": line 77: cd: ");
        msg.extend_from_slice(&root);
        msg.extend_from_slice(b": ");
        msg.extend_from_slice(&os_error_message(&e));
        msg.push(b'\n');
        write_stderr(&msg);
        return 1;
    }
    let root_pwd = logical_cd_bytes(&initial_pwd, &root);
    std::env::set_var("OLDPWD", OsStr::from_bytes(&initial_pwd));
    std::env::set_var("PWD", OsStr::from_bytes(&root_pwd));

    // Lines 93-106: locate and source tools/ci/transient-lib.sh.
    let Some(transient_lib) = locate_transient_lib(argv0, &self_dir, &root) else {
        let Some(c_red) = std::env::var_os("C_RED") else {
            let mut msg = Vec::new();
            msg.extend_from_slice(argv0);
            msg.extend_from_slice(b": line 101: C_RED: unbound variable\n");
            write_stderr(&msg);
            return 1;
        };
        let Some(glyph_fail) = std::env::var_os("GLYPH_FAIL") else {
            let mut msg = Vec::new();
            msg.extend_from_slice(argv0);
            msg.extend_from_slice(b": line 101: GLYPH_FAIL: unbound variable\n");
            write_stderr(&msg);
            return 1;
        };
        let Some(c_reset) = std::env::var_os("C_RESET") else {
            let mut msg = Vec::new();
            msg.extend_from_slice(argv0);
            msg.extend_from_slice(b": line 101: C_RESET: unbound variable\n");
            write_stderr(&msg);
            return 1;
        };
        let mut msg = Vec::new();
        msg.extend_from_slice(c_red.as_bytes());
        msg.extend_from_slice(glyph_fail.as_bytes());
        msg.extend_from_slice(b" gomod");
        msg.extend_from_slice(c_reset.as_bytes());
        msg.extend_from_slice(" — cannot locate tools/ci/transient-lib.sh\n".as_bytes());
        let _ = printf_stderr(argv0, 101, &msg);
        return 1;
    };

    if let Err(code) = source_transient_lib_startup(argv0, &transient_lib) {
        return code;
    }

    // Line 111: export GOWORK=off
    std::env::set_var("GOWORK", "off");

    let palette = Palette::for_tty(io::stdout().is_terminal());

    let (mode, roots) = match parse_args_os(args) {
        ParseOutcomeOs::Help => {
            return run_help_sed(argv0);
        }
        ParseOutcomeOs::UnknownFlag(flag) => {
            let mut msg = Vec::new();
            msg.extend_from_slice(palette.red.as_bytes());
            msg.extend_from_slice(GLYPH_FAIL.as_bytes());
            msg.extend_from_slice(b" gomod");
            msg.extend_from_slice(palette.reset.as_bytes());
            msg.extend_from_slice(" — unknown flag: ".as_bytes());
            msg.extend_from_slice(&flag);
            msg.push(b'\n');
            if let Err(code) = printf_stderr(argv0, 156, &msg) {
                return code;
            }
            return 2;
        }
        ParseOutcomeOs::Run { mode, roots } => (mode, roots),
    };

    if !is_executable_on_path_bytes(b"go") {
        let mut msg = Vec::new();
        msg.extend_from_slice(palette.red.as_bytes());
        msg.extend_from_slice(GLYPH_FAIL.as_bytes());
        msg.extend_from_slice(b" gomod");
        msg.extend_from_slice(palette.reset.as_bytes());
        msg.extend_from_slice(
            " — go not on PATH. Install it (see `bazel run //:doctor`).\n".as_bytes(),
        );
        let _ = printf_stderr(argv0, 167, &msg);
        return 1;
    }

    let mods = match collect_modules_os(&roots) {
        Ok(m) => m,
        Err(CollectErrorOs::MissingModule(m)) => {
            let mut msg = Vec::new();
            msg.extend_from_slice(palette.red.as_bytes());
            msg.extend_from_slice(GLYPH_FAIL.as_bytes());
            msg.extend_from_slice(b" gomod");
            msg.extend_from_slice(palette.reset.as_bytes());
            msg.extend_from_slice(" — module does not exist: ".as_bytes());
            msg.extend_from_slice(&m);
            msg.push(b'\n');
            let _ = printf_stderr(argv0, 184, &msg);
            return 1;
        }
        Err(CollectErrorOs::MissingRoot(r)) => {
            let mut msg = Vec::new();
            msg.extend_from_slice(palette.red.as_bytes());
            msg.extend_from_slice(GLYPH_FAIL.as_bytes());
            msg.extend_from_slice(b" gomod");
            msg.extend_from_slice(palette.reset.as_bytes());
            msg.extend_from_slice(" — root does not exist: ".as_bytes());
            msg.extend_from_slice(&r);
            msg.push(b'\n');
            let _ = printf_stderr(argv0, 192, &msg);
            return 1;
        }
        Err(CollectErrorOs::ZeroModules(joined)) => {
            let mut msg = Vec::new();
            msg.extend_from_slice(palette.red.as_bytes());
            msg.extend_from_slice(GLYPH_FAIL.as_bytes());
            msg.extend_from_slice(b" gomod");
            msg.extend_from_slice(palette.reset.as_bytes());
            msg.extend_from_slice(" — found no go.mod under: ".as_bytes());
            msg.extend_from_slice(&joined);
            msg.extend_from_slice(
                b"\n   Refusing to report green: this is a broken invocation, not a tidy tree.\n",
            );
            let _ = printf_stderr(argv0, 204, &msg);
            return 1;
        }
    };

    let verb = match mode {
        Mode::Check => "checking",
        Mode::Fix => "tidying",
    };
    {
        let mut header = Vec::new();
        header.extend_from_slice(palette.cyan.as_bytes());
        header.extend_from_slice("→".as_bytes());
        header.extend_from_slice(palette.reset.as_bytes());
        header.extend_from_slice(format!(" {verb} {} module(s) under ", mods.len()).as_bytes());
        header.extend_from_slice(&join_bytes_space(&roots));
        header.push(b'\n');
        if let Err(code) = printf_stdout(argv0, 209, &header) {
            return code;
        }
    }

    let mut drifted: Vec<Vec<u8>> = Vec::new();
    let mut unreachable: Vec<Vec<u8>> = Vec::new();
    let mut changed: usize = 0;

    let temp_guard = match create_temp_diff_file(argv0) {
        Ok(g) => g,
        Err(code) => return code,
    };

    for dir in &mods {
        match mode {
            Mode::Check => {
                let mut attempt: u64 = 1;
                loop {
                    let (ok, diff_out) = run_go_mod_tidy_diff(argv0, dir);
                    if ok {
                        break;
                    }
                    if let Err(code) = write_diff_file(argv0, &temp_guard.path, &diff_out) {
                        return code;
                    }
                    if attempt < 3
                        && is_transient_network_error_file(&transient_lib, &temp_guard.path)
                    {
                        let mut msg = Vec::new();
                        msg.extend_from_slice(palette.yellow.as_bytes());
                        msg.push(b'~');
                        msg.extend_from_slice(palette.reset.as_bytes());
                        msg.push(b' ');
                        msg.extend_from_slice(dir);
                        msg.extend_from_slice(
                            format!(" — module proxy error, retrying ({attempt}/3)\n").as_bytes(),
                        );
                        if let Err(code) = printf_stderr(argv0, 251, &msg) {
                            return code;
                        }
                        if let Err(code) = sleep_backoff(argv0, attempt * 5) {
                            return code;
                        }
                        attempt += 1;
                        continue;
                    }
                    if is_transient_network_error_file(&transient_lib, &temp_guard.path) {
                        unreachable.push(dir.clone());
                        let mut line = Vec::new();
                        line.extend_from_slice(palette.red.as_bytes());
                        line.extend_from_slice(GLYPH_FAIL.as_bytes());
                        line.extend_from_slice(palette.reset.as_bytes());
                        line.push(b' ');
                        line.extend_from_slice(dir);
                        line.extend_from_slice(" — could not reach the module proxy\n".as_bytes());
                        if let Err(code) = printf_stdout(argv0, 262, &line) {
                            return code;
                        }
                    } else {
                        drifted.push(dir.clone());
                        let mut line = Vec::new();
                        line.extend_from_slice(palette.red.as_bytes());
                        line.extend_from_slice(GLYPH_FAIL.as_bytes());
                        line.extend_from_slice(palette.reset.as_bytes());
                        line.push(b' ');
                        line.extend_from_slice(dir);
                        line.push(b'\n');
                        if let Err(code) = printf_stdout(argv0, 266, &line) {
                            return code;
                        }
                    }
                    if let Err(code) = run_indent_diff_sed(argv0, &diff_out) {
                        return code;
                    }
                    break;
                }
            }
            Mode::Fix => {
                let before = match read_mod_and_sum_snapshot(argv0, 273, dir) {
                    Ok(b) => b,
                    Err(code) => return code,
                };
                if let Err(code) = run_go_mod_tidy_fix(argv0, dir) {
                    return code;
                }
                let after = match read_mod_and_sum_snapshot(argv0, 276, dir) {
                    Ok(a) => a,
                    Err(code) => return code,
                };
                if before != after {
                    changed += 1;
                    let mut line = Vec::new();
                    line.extend_from_slice(palette.yellow.as_bytes());
                    line.push(b'~');
                    line.extend_from_slice(palette.reset.as_bytes());
                    line.push(b' ');
                    line.extend_from_slice(dir);
                    line.push(b'\n');
                    if let Err(code) = printf_stdout(argv0, 279, &line) {
                        return code;
                    }
                }
            }
        }
    }

    match mode {
        Mode::Check => {
            if !unreachable.is_empty() {
                let msg1 = format!(
                    "\n{}{} gomod{} — could not reach the Go module proxy for {} of {} module(s) after 3 attempts.\n",
                    palette.red,
                    GLYPH_FAIL,
                    palette.reset,
                    unreachable.len(),
                    mods.len()
                );
                if let Err(code) = printf_stderr(argv0, 286, msg1.as_bytes()) {
                    return code;
                }
                if let Err(code) = printf_stderr(
                    argv0,
                    288,
                    b"   This is an INFRASTRUCTURE failure, not drift: these modules may well be tidy.\n",
                ) {
                    return code;
                }
                if let Err(code) = printf_stderr(
                    argv0,
                    289,
                    b"   Do NOT run `bazel run //tools/gomod:tidy` on the strength of this -- re-run the job.\n\n",
                ) {
                    return code;
                }
                return 1;
            }
            if !drifted.is_empty() {
                let msg1 = format!(
                    "\n{}{} gomod{} — {} of {} module(s) are out of sync with their `replace` targets (diffs above).\n",
                    palette.red,
                    GLYPH_FAIL,
                    palette.reset,
                    drifted.len(),
                    mods.len()
                );
                if let Err(code) = printf_stderr(argv0, 293, msg1.as_bytes()) {
                    return code;
                }
                if let Err(code) = printf_stderr(
                    argv0,
                    295,
                    b"   Fix with:\n\n     bazel run //tools/gomod:tidy\n\n   then commit the go.mod/go.sum changes.\n\n",
                ) {
                    return code;
                }
                if let Err(code) = printf_stderr(
                    argv0,
                    296,
                    b"   If this fired on a Dependabot PR, that is the known `replace`-edge blind\n",
                ) {
                    return code;
                }
                if let Err(code) = printf_stderr(
                    argv0,
                    297,
                    b"   spot: it bumped a library module and cannot tidy the examples that consume\n",
                ) {
                    return code;
                }
                if let Err(code) = printf_stderr(
                    argv0,
                    298,
                    b"   it. Running the command above on the PR branch is the whole fix.\n",
                ) {
                    return code;
                }
                return 1;
            }
            let msg = format!(
                "{}{} gomod{} — all {} module(s) tidy\n",
                palette.green,
                GLYPH_OK,
                palette.reset,
                mods.len()
            );
            if let Err(code) = printf_stdout(argv0, 301, msg.as_bytes()) {
                return code;
            }
            0
        }
        Mode::Fix => {
            let msg = format!(
                "{}{} gomod{} — tidied {} module(s), {} changed\n",
                palette.green,
                GLYPH_OK,
                palette.reset,
                mods.len(),
                changed
            );
            if let Err(code) = printf_stdout(argv0, 304, msg.as_bytes()) {
                return code;
            }
            0
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_help_text_matches_lines_21_to_70() {
        let text = help_text();
        let lines: Vec<&str> = text.lines().collect();
        assert_eq!(lines.len(), 50);
        assert!(lines[0]
            .starts_with("# tidy.sh — keep the `replace`-coupled Go modules' pins in sync."));
        assert_eq!(lines[48], "set -euo pipefail");
        assert_eq!(lines[49], "");
        assert!(text.ends_with("\n\n"));
    }

    #[test]
    fn test_parse_args_defaults_and_modes() {
        assert_eq!(
            parse_args(Vec::<&str>::new()),
            ParseOutcome::Run {
                mode: Mode::Fix,
                roots: DEFAULT_ROOTS.iter().map(|s| (*s).to_string()).collect(),
            }
        );
        assert_eq!(
            parse_args(["--check"]),
            ParseOutcome::Run {
                mode: Mode::Check,
                roots: DEFAULT_ROOTS.iter().map(|s| (*s).to_string()).collect(),
            }
        );
        assert_eq!(
            parse_args(["--check", "--fix", "a", "b/go.mod"]),
            ParseOutcome::Run {
                mode: Mode::Fix,
                roots: vec!["a".to_string(), "b/go.mod".to_string()],
            }
        );
        assert_eq!(parse_args(["-h"]), ParseOutcome::Help);
        assert_eq!(
            parse_args(["--check", "--help", "--bogus"]),
            ParseOutcome::Help
        );
        assert_eq!(
            parse_args(["--bogus", "-h"]),
            ParseOutcome::UnknownFlag("--bogus".to_string())
        );
        assert_eq!(
            parse_args(["-"]),
            ParseOutcome::UnknownFlag("-".to_string())
        );
    }

    #[test]
    fn test_posix_dirname() {
        assert_eq!(posix_dirname("src/go.mod"), "src");
        assert_eq!(posix_dirname("src/m1/go.mod"), "src/m1");
        assert_eq!(posix_dirname("src//go.mod"), "src");
        assert_eq!(posix_dirname("/go.mod"), "/");
        assert_eq!(posix_dirname("go.mod"), ".");
        assert_eq!(posix_dirname(""), ".");
        assert_eq!(posix_dirname("///"), "/");
    }

    #[test]
    fn test_logical_cd() {
        assert_eq!(logical_cd("/tmp/work", "src/m1"), "/tmp/work/src/m1");
        assert_eq!(logical_cd("/tmp/work/", "./src/../a"), "/tmp/work/a");
        assert_eq!(logical_cd("/tmp/work", "/var/folders/x"), "/var/folders/x");
    }

    #[test]
    fn test_indent_diff() {
        assert_eq!(indent_diff(""), "     \n");
        assert_eq!(
            indent_diff("-a v1.0.0\n+a v1.1.0"),
            "     -a v1.0.0\n     +a v1.1.0\n"
        );
        assert_eq!(indent_diff("a\n\nb"), "     a\n     \n     b\n");
    }

    #[test]
    fn test_palette_tty_selection() {
        assert_eq!(Palette::for_tty(true), Palette::COLOR);
        assert_eq!(Palette::for_tty(false), Palette::PLAIN);
    }

    #[test]
    fn test_locale_cmp_tiebreaker() {
        assert_eq!(locale_cmp(b"abc\0x", b"abc\0y"), CmpOrdering::Less);
        assert_eq!(locale_cmp(b"abc", b"abc"), CmpOrdering::Equal);
    }
}
