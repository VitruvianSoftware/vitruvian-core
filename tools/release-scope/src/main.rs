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

//! release_scope_rs: the release-scope check, in Rust. The same command
//! line as release_scope.py:
//!
//!     release_scope_rs --pr-json pr.json --commits-json commits.json --files files.txt
//!
//! This file gathers what the process provides (arguments, environment,
//! terminal width, locale) the way CPython does at startup; the decision is
//! in the library.

use release_scope::pystr::{decode_os, Errors, PyStr};
use std::ffi::{c_char, c_int, c_ulong, CStr};
use std::io::Write;
use std::os::unix::ffi::{OsStrExt, OsStringExt};

extern "C" {
    fn ioctl(fd: c_int, request: c_ulong, ...) -> c_int;
    fn setlocale(category: c_int, locale: *const c_char) -> *mut c_char;
}

#[cfg(target_os = "macos")]
const TIOCGWINSZ: c_ulong = 0x40087468;
#[cfg(not(target_os = "macos"))]
const TIOCGWINSZ: c_ulong = 0x5413;
#[cfg(target_os = "macos")]
const LC_CTYPE: c_int = 2;
#[cfg(not(target_os = "macos"))]
const LC_CTYPE: c_int = 0;

#[repr(C)]
struct Winsize {
    rows: u16,
    cols: u16,
    xpixel: u16,
    ypixel: u16,
}

/// os.get_terminal_size(sys.__stdout__.fileno()).columns.
fn tty_columns() -> Option<i64> {
    let mut size = Winsize {
        rows: 0,
        cols: 0,
        xpixel: 0,
        ypixel: 0,
    };
    // SAFETY: TIOCGWINSZ writes one winsize into the struct it is given.
    let rc = unsafe { ioctl(1, TIOCGWINSZ, &mut size as *mut Winsize) };
    if rc == 0 {
        Some(size.cols as i64)
    } else {
        None
    }
}

fn env(name: &str) -> Option<PyStr> {
    std::env::var_os(name).map(|v| decode_os(v.as_bytes()))
}

/// sys.stdout.errors as CPython 3.12 chooses it (config_get_stdio_errors):
/// PYTHONIOENCODING's handler if it names one; surrogateescape in UTF-8
/// mode and in the C, POSIX and coercion-target locales; else strict.
fn stdout_errors() -> Errors {
    if let Some(value) = std::env::var_os("PYTHONIOENCODING") {
        let value = value.to_string_lossy().into_owned();
        if let Some((_, handler)) = value.split_once(':') {
            if let Some(errors) = Errors::parse(handler) {
                return errors;
            }
        }
    }
    if std::env::var_os("PYTHONUTF8").map_or(false, |v| v == "1") {
        return Errors::SurrogateEscape;
    }
    // SAFETY: setlocale with "" reads the environment, and the name it
    // returns stays valid until the next call; this is the only caller.
    let name = unsafe {
        let empty = b"\0";
        let found = setlocale(LC_CTYPE, empty.as_ptr() as *const c_char);
        if found.is_null() {
            "C".to_string()
        } else {
            CStr::from_ptr(found).to_string_lossy().into_owned()
        }
    };
    match name.as_str() {
        "C" | "POSIX" | "C.UTF-8" | "C.utf8" | "UTF-8" => Errors::SurrogateEscape,
        _ => Errors::Strict,
    }
}

/// os.path.normpath for an absolute POSIX path.
fn normpath(path: &str) -> String {
    let slashes = if path.starts_with("//") && !path.starts_with("///") {
        2
    } else {
        1
    };
    let mut parts: Vec<&str> = Vec::new();
    for part in path.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            other => parts.push(other),
        }
    }
    format!("{}{}", "/".repeat(slashes), parts.join("/"))
}

/// What release_scope.py's HERE is: the folder the program was started
/// from, by the path it was started by.
fn here(argv0: &[u8]) -> (String, String) {
    let started_by = if argv0.contains(&b'/') {
        String::from_utf8_lossy(argv0).into_owned()
    } else {
        std::env::current_exe()
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_default()
    };
    let absolute = if started_by.starts_with('/') {
        started_by
    } else {
        let cwd = std::env::current_dir()
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_default();
        format!("{}/{}", cwd, started_by)
    };
    let absolute = normpath(&absolute);
    let folder = match absolute.rfind('/') {
        Some(0) => "/".to_string(),
        Some(at) => absolute[..at].to_string(),
        None => String::new(),
    };
    (folder, absolute)
}

/// aliases.json beside the program, as release_scope.py finds its own; or,
/// when `bazel run` starts it from the output tree, its runfiles copy.
fn default_aliases(argv0: &[u8]) -> PyStr {
    let (folder, program) = here(argv0);
    let beside = format!("{}/aliases.json", folder);
    let mut candidates = vec![beside.clone()];
    let in_runfiles = "_main/tools/release-scope/aliases.json";
    // Only the program's own runfiles: an inherited RUNFILES_DIR belongs to
    // whatever started it, and would find a file where the script finds none.
    candidates.push(format!("{}.runfiles/{}", program, in_runfiles));
    let chosen = candidates
        .into_iter()
        .find(|c| std::path::Path::new(c).is_file())
        .unwrap_or(beside);
    PyStr::from(chosen.as_str())
}

fn main() {
    let raw: Vec<Vec<u8>> = std::env::args_os().map(|a| a.into_vec()).collect();
    let argv0 = raw.first().cloned().unwrap_or_default();
    let env = release_scope::Env {
        argv: raw.iter().map(|a| decode_os(a)).collect(),
        default_aliases: default_aliases(&argv0),
        columns: release_scope::cli::terminal_columns(env("COLUMNS").as_ref(), tty_columns()),
        stdout_errors: stdout_errors(),
    };
    // Python lets JSON nest 9997 deep; a thread with room for that.
    let outcome = std::thread::Builder::new()
        .stack_size(1 << 30)
        .spawn(move || {
            let outcome = release_scope::main(&env);
            std::mem::forget(env);
            outcome
        })
        .expect("start the check's thread")
        .join()
        .expect("the check's thread ends");
    let _ = std::io::stdout().write_all(&outcome.stdout);
    let _ = std::io::stdout().flush();
    let _ = std::io::stderr().write_all(&outcome.stderr);
    std::process::exit(outcome.code);
}
