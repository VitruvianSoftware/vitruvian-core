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

//! What Go's `os/exec` does before and around running a program, so the port
//! finds the same binary the Go tool would (and fails the same way when it
//! cannot): `exec.LookPath`'s PATH walk, its `ErrDot` refusal of relative
//! hits, and the error text Go prints for each failure.

use std::ffi::{OsStr, OsString};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::CommandExt;
use std::process::Command;

/// The error Go's `exec.Command(name).Run()` reports when it cannot start.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ExecError {
    /// `*exec.Error`: lookup failed. `reason` is the wrapped error's text.
    Lookup { name: Vec<u8>, reason: Vec<u8> },
    /// `*fs.PathError{Op: "fork/exec"}`: found but could not be executed.
    Start { path: Vec<u8>, errno: i32 },
}

impl ExecError {
    /// Go's `err.Error()`.
    pub fn go_string(&self) -> Vec<u8> {
        match self {
            ExecError::Lookup { name, reason } => {
                let mut s = b"exec: ".to_vec();
                s.extend_from_slice(&quote_ascii_name(name));
                s.extend_from_slice(b": ");
                s.extend_from_slice(reason);
                s
            }
            ExecError::Start { path, errno } => {
                let mut s = b"fork/exec ".to_vec();
                s.extend_from_slice(path);
                s.extend_from_slice(b": ");
                s.extend_from_slice(errno_string(*errno).as_bytes());
                s
            }
        }
    }
}

/// strconv.Quote for the program names used here ("git", "docker"): plain
/// printable ASCII, which Quote leaves as is apart from `"` and `\`.
fn quote_ascii_name(name: &[u8]) -> Vec<u8> {
    let mut s = vec![b'"'];
    for &b in name {
        match b {
            b'"' | b'\\' => {
                s.push(b'\\');
                s.push(b);
            }
            0x20..=0x7e => s.push(b),
            _ => {
                s.extend_from_slice(b"\\x");
                s.push(b"0123456789abcdef"[(b >> 4) as usize]);
                s.push(b"0123456789abcdef"[(b & 15) as usize]);
            }
        }
    }
    s.push(b'"');
    s
}

/// Go's syscall error strings (zerrors_*.go), which are not always
/// strerror(3)'s, for the errnos a lookup or exec can hit.
pub fn errno_string(errno: i32) -> String {
    #[cfg(target_os = "macos")]
    let s = match errno {
        1 => "operation not permitted",
        2 => "no such file or directory",
        5 => "input/output error",
        7 => "argument list too long",
        8 => "exec format error",
        12 => "cannot allocate memory",
        13 => "permission denied",
        17 => "file exists",
        20 => "not a directory",
        21 => "is a directory",
        22 => "invalid argument",
        24 => "too many open files",
        26 => "text file busy",
        28 => "no space left on device",
        30 => "read-only file system",
        62 => "too many levels of symbolic links",
        63 => "file name too long",
        86 => "bad CPU type in executable",
        _ => "",
    };
    #[cfg(not(target_os = "macos"))]
    let s = match errno {
        1 => "operation not permitted",
        2 => "no such file or directory",
        5 => "input/output error",
        7 => "argument list too long",
        8 => "exec format error",
        12 => "cannot allocate memory",
        13 => "permission denied",
        17 => "file exists",
        20 => "not a directory",
        21 => "is a directory",
        22 => "invalid argument",
        24 => "too many open files",
        26 => "text file busy",
        28 => "no space left on device",
        30 => "read-only file system",
        36 => "file name too long",
        40 => "too many levels of symbolic links",
        _ => "",
    };
    if s.is_empty() {
        format!("errno {errno}")
    } else {
        s.to_string()
    }
}

const ENOENT: i32 = 2;
const EACCES: i32 = 13;
const EISDIR: i32 = 21;

/// os/exec's findExecutable: a non-directory the caller may execute.
/// Err is Go's text for the error it returns.
fn find_executable(file: &[u8]) -> Result<(), String> {
    find_executable_errno(file).map_err(|(stat, errno)| {
        if stat {
            // os.Stat's *PathError.
            format!(
                "stat {}: {}",
                String::from_utf8_lossy(file),
                errno_string(errno)
            )
        } else {
            errno_string(errno)
        }
    })
}

fn find_executable_errno(file: &[u8]) -> Result<(), (bool, i32)> {
    let path = OsStr::from_bytes(file);
    let meta = std::fs::metadata(path).map_err(|e| (true, e.raw_os_error().unwrap_or(ENOENT)))?;
    if meta.is_dir() {
        return Err((false, EISDIR));
    }
    // unix.Eaccess(file, X_OK): access(2) with the effective ids.
    let c = match std::ffi::CString::new(file) {
        Ok(c) => c,
        Err(_) => return Err((true, ENOENT)),
    };
    // SAFETY: c is a valid NUL-terminated path; faccessat only reads it.
    let rc = unsafe { faccessat(AT_FDCWD, c.as_ptr(), X_OK, AT_EACCESS) };
    if rc == 0 {
        return Ok(());
    }
    let err = std::io::Error::last_os_error()
        .raw_os_error()
        .unwrap_or(EACCES);
    const ENOSYS: i32 = if cfg!(target_os = "macos") { 78 } else { 38 };
    const EPERM: i32 = 1;
    if err != ENOSYS && err != EPERM {
        return Err((false, err));
    }
    if meta.permissions().mode() & 0o111 != 0 {
        return Ok(());
    }
    Err((false, EACCES))
}

#[cfg(target_os = "macos")]
const AT_FDCWD: i32 = -2;
#[cfg(not(target_os = "macos"))]
const AT_FDCWD: i32 = -100;
#[cfg(target_os = "macos")]
const AT_EACCESS: i32 = 0x10;
#[cfg(not(target_os = "macos"))]
const AT_EACCESS: i32 = 0x200;
const X_OK: i32 = 1;

extern "C" {
    fn faccessat(dirfd: i32, path: *const std::ffi::c_char, mode: i32, flags: i32) -> i32;
}

/// filepath.Join(dir, file) for a PATH entry and a bare program name.
fn join(dir: &[u8], file: &[u8]) -> Vec<u8> {
    let mut p = dir.to_vec();
    p.push(b'/');
    p.extend_from_slice(file);
    clean(&p)
}

/// filepath.Clean (Unix).
pub fn clean(path: &[u8]) -> Vec<u8> {
    if path.is_empty() {
        return b".".to_vec();
    }
    let rooted = path[0] == b'/';
    let n = path.len();
    let mut out: Vec<u8> = Vec::with_capacity(n);
    let mut r = 0;
    let mut dotdot = 0;
    if rooted {
        out.push(b'/');
        r = 1;
        dotdot = 1;
    }
    while r < n {
        if path[r] == b'/' {
            r += 1;
        } else if path[r] == b'.' && (r + 1 == n || path[r + 1] == b'/') {
            r += 1;
        } else if path[r] == b'.' && path[r + 1] == b'.' && (r + 2 == n || path[r + 2] == b'/') {
            r += 2;
            if out.len() > dotdot {
                let mut w = out.len() - 1;
                while w > dotdot && out[w] != b'/' {
                    w -= 1;
                }
                out.truncate(w);
            } else if !rooted {
                if !out.is_empty() {
                    out.push(b'/');
                }
                out.extend_from_slice(b"..");
                dotdot = out.len();
            }
        } else {
            if (rooted && out.len() != 1) || (!rooted && !out.is_empty()) {
                out.push(b'/');
            }
            while r < n && path[r] != b'/' {
                out.push(path[r]);
                r += 1;
            }
        }
    }
    if out.is_empty() {
        out.push(b'.');
    }
    out
}

/// exec.LookPath, then the decision exec.Command makes from it.
pub fn look_path(file: &[u8]) -> Result<Vec<u8>, ExecError> {
    let lookup = |reason: &str| ExecError::Lookup {
        name: file.to_vec(),
        reason: reason.as_bytes().to_vec(),
    };
    if file.is_empty() || file == b"." || file == b".." {
        return Err(lookup("executable file not found in $PATH"));
    }
    if file.contains(&b'/') {
        return match find_executable(file) {
            Ok(()) => Ok(file.to_vec()),
            Err(e) => Err(lookup(&e)),
        };
    }
    let path = std::env::var_os("PATH").unwrap_or_default();
    let path = path.as_bytes();
    if !path.is_empty() {
        for dir in path.split(|&b| b == b':') {
            let dir: &[u8] = if dir.is_empty() { b"." } else { dir };
            let candidate = join(dir, file);
            if find_executable(&candidate).is_ok() {
                if candidate.first() != Some(&b'/') {
                    return Err(lookup(
                        "cannot run executable found relative to current directory",
                    ));
                }
                return Ok(candidate);
            }
        }
    }
    Err(lookup("executable file not found in $PATH"))
}

/// exec.Command(name, args...): the resolved program, run as `name` in
/// argv[0], started with a plain execve(2) as Go starts it. (Rust's own exec
/// uses execvp, which hands a file the kernel will not run to /bin/sh; Go
/// reports ENOEXEC instead, and so must the port.)
pub fn command(name: &[u8], args: &[Vec<u8>]) -> Result<Command, ExecError> {
    use std::ffi::{c_char, CString};
    let path = look_path(name)?;
    let mut cmd = Command::new(OsString::from_vec(path.clone()));
    cmd.arg0(OsStr::from_bytes(name));
    for a in args {
        cmd.arg(OsStr::from_bytes(a));
    }
    // Everything execve needs is built here, before the fork: the closure
    // below runs in the child, where only async-signal-safe calls are allowed.
    let cpath = CString::new(path).map_err(|_| ExecError::Lookup {
        name: name.to_vec(),
        reason: b"invalid argument".to_vec(),
    })?;
    let mut owned: Vec<CString> = Vec::with_capacity(args.len() + 1);
    for a in std::iter::once(name).chain(args.iter().map(|a| a.as_slice())) {
        owned.push(CString::new(a).map_err(|_| ExecError::Lookup {
            name: name.to_vec(),
            reason: b"invalid argument".to_vec(),
        })?);
    }
    let mut argv: Vec<*const c_char> = owned.iter().map(|c| c.as_ptr()).collect();
    argv.push(std::ptr::null());
    let exec = ExecArgs {
        _owned: owned,
        path: cpath,
        argv,
    };
    // SAFETY: the closure only calls execve(2) (async-signal-safe) on memory
    // allocated before the fork; on failure it returns the errno to Rust's
    // spawn, which reports it as the start error.
    unsafe {
        cmd.pre_exec(move || {
            let e = &exec; // the whole struct, so its Send impl applies
            execve(e.path.as_ptr(), e.argv.as_ptr(), current_environ());
            Err(std::io::Error::last_os_error())
        });
    }
    Ok(cmd)
}

struct ExecArgs {
    _owned: Vec<std::ffi::CString>,
    path: std::ffi::CString,
    argv: Vec<*const std::ffi::c_char>,
}

// SAFETY: the raw pointers point into `_owned`, which moves with them.
unsafe impl Send for ExecArgs {}
unsafe impl Sync for ExecArgs {}

extern "C" {
    fn execve(
        path: *const std::ffi::c_char,
        argv: *const *const std::ffi::c_char,
        envp: *const *const std::ffi::c_char,
    ) -> i32;
}

#[cfg(target_os = "macos")]
fn current_environ() -> *const *const std::ffi::c_char {
    extern "C" {
        fn _NSGetEnviron() -> *mut *const *const std::ffi::c_char;
    }
    // SAFETY: _NSGetEnviron always returns a valid pointer to environ.
    unsafe { *_NSGetEnviron() }
}

#[cfg(not(target_os = "macos"))]
fn current_environ() -> *const *const std::ffi::c_char {
    extern "C" {
        static environ: *const *const std::ffi::c_char;
    }
    // SAFETY: reading the process's environ pointer.
    unsafe { environ }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clean_matches_go() {
        for (input, want) in [
            ("", "."),
            ("/", "/"),
            ("a//b", "a/b"),
            ("./a/", "a"),
            ("a/../..", ".."),
            ("/../x", "/x"),
            ("a/./b/../c", "a/c"),
        ] {
            assert_eq!(clean(input.as_bytes()), want.as_bytes(), "{input}");
        }
    }

    #[test]
    fn lookup_error_text() {
        let e = ExecError::Lookup {
            name: b"git".to_vec(),
            reason: b"executable file not found in $PATH".to_vec(),
        };
        assert_eq!(
            e.go_string(),
            b"exec: \"git\": executable file not found in $PATH".to_vec()
        );
    }
}
