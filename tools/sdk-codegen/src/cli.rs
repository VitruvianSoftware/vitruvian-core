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

//! sdk_codegen.py itself: write the kits' generated files, or `--check` the
//! committed ones, with its output and exit status.
//!
//!     sdk-codegen                 writes the files into packages/vitruvian-sdk
//!     sdk-codegen --check         fails when a committed file is not what
//!                                 would be written, or is one no emitter writes
//!     sdk-codegen --out FOLDER    writes them under FOLDER instead
//!
//! Where Python would stop with an exception nothing catches, this prints
//! the traceback's last line, which names the exception, under a header
//! that says Python's stack frames are not reproduced, and exits 1.

use crate::argparse::{self, Parsed};
use crate::difflib;
use crate::emitters;
use crate::fsio;
use crate::model;
use crate::pyerr::{PyErr, PyResult};
use crate::pystr;
use std::collections::{BTreeMap, BTreeSet};
use std::io::Write;

const PACKAGE: &str = "packages/vitruvian-sdk";

/// Whether an emitter may write `path`: inside a folder named `generated`,
/// or a Go file named `*_gen.go`.
pub fn is_generated(path: &str) -> bool {
    let parts: Vec<&str> = path.split('/').collect();
    let (last, folders) = parts.split_last().unwrap();
    folders.contains(&"generated") || last.ends_with("_gen.go")
}

/// Every generated file, by its path under `package`, and its text.
pub fn generate(package: &str) -> PyResult<BTreeMap<String, String>> {
    let built = model::load(&fsio::join(package, "protocol"))?;
    let mut files = BTreeMap::new();
    for emitter in emitters::all() {
        for (path, text) in (emitter.emit)(&built)? {
            if !is_generated(&path) {
                return Err(PyErr::exit(format!(
                    "{} writes {}, which is not inside a folder named generated",
                    emitter.name, path
                )));
            }
            if files.contains_key(&path) {
                return Err(PyErr::exit(format!("{} is written by two emitters", path)));
            }
            files.insert(path, text);
        }
    }
    Ok(files)
}

/// Every generated file in the package's kits and its Go module.
pub fn committed(package: &str) -> PyResult<BTreeMap<String, String>> {
    let mut found = BTreeMap::new();
    for folder in ["kits", "go"] {
        let top = fsio::join(package, folder);
        for rel in fsio::walk(&top, &["node_modules", "__pycache__", "dist"]) {
            let relative = format!("{}/{}", folder, rel);
            if !is_generated(&relative) {
                continue;
            }
            found.insert(relative, fsio::read_text(&fsio::join(&top, &rel))?);
        }
    }
    Ok(found)
}

/// `check(package)`: its exit status, with what it printed.
pub fn check(package: &str, out: &mut dyn Write, err: &mut dyn Write) -> PyResult<i32> {
    let wanted = generate(package)?;
    let have = committed(package)?;
    let paths: BTreeSet<&String> = wanted.keys().chain(have.keys()).collect();
    let mut problems = Vec::new();
    for path in paths {
        match (have.get(path), wanted.get(path)) {
            (None, _) => problems.push(format!("{}: missing", path)),
            (_, None) => problems.push(format!("{}: no emitter writes it", path)),
            (Some(h), Some(w)) if h != w => {
                let diff = difflib::unified_diff(
                    &pystr::splitlines(h, false),
                    &pystr::splitlines(w, false),
                    &format!("committed/{}", path),
                    &format!("generated/{}", path),
                    1,
                );
                let shown: Vec<String> = diff.into_iter().take(40).collect();
                problems.push(format!("{}: out of date\n{}", path, shown.join("\n")));
            }
            _ => {}
        }
    }
    for problem in &problems {
        let _ = writeln!(err, "{}", problem);
    }
    let verdict = if problems.is_empty() {
        "in sync"
    } else {
        "OUT OF SYNC, run: bazel run //tools/sdk-codegen"
    };
    let _ = writeln!(out, "sdk-codegen: {} files, {}", wanted.len(), verdict);
    Ok(if problems.is_empty() { 0 } else { 1 })
}

/// `write(package, out)`.
pub fn write(package: &str, folder: &str, out: &mut dyn Write) -> PyResult<i32> {
    let files = generate(package)?;
    for (path, text) in &files {
        let target = fsio::join(folder, path);
        fsio::makedirs(&fsio::dirname(&target))?;
        fsio::write_text(&target, text)?;
        let _ = writeln!(out, "wrote {}", target);
    }
    Ok(0)
}

/// `os.path.normpath` on POSIX.
pub fn normpath(path: &str) -> String {
    if path.is_empty() {
        return ".".into();
    }
    let initial = if path.starts_with("//") && !path.starts_with("///") {
        2
    } else if path.starts_with('/') {
        1
    } else {
        0
    };
    let mut parts: Vec<&str> = Vec::new();
    for comp in path.split('/') {
        if comp.is_empty() || comp == "." {
            continue;
        }
        if comp != ".." || (initial == 0 && parts.is_empty()) || parts.last() == Some(&"..") {
            parts.push(comp);
        } else if !parts.is_empty() {
            parts.pop();
        }
    }
    let joined = format!("{}{}", "/".repeat(initial), parts.join("/"));
    if joined.is_empty() {
        ".".into()
    } else {
        joined
    }
}

fn abspath(path: &str) -> String {
    if path.starts_with('/') {
        normpath(path)
    } else {
        let cwd = std::env::current_dir()
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_default();
        normpath(&fsio::join(&cwd, path))
    }
}

/// The folder this program is in, as sdk_codegen.py's HERE is its own:
/// the runfiles' copy of tools/sdk-codegen when Bazel built one beside it.
fn here(argv0: &str) -> String {
    let exe = if argv0.contains('/') {
        Some(abspath(argv0))
    } else {
        std::env::var("PATH").ok().and_then(|path| {
            path.split(':')
                .map(|dir| fsio::join(if dir.is_empty() { "." } else { dir }, argv0))
                .find(|p| std::path::Path::new(p).is_file())
                .map(|p| abspath(&p))
        })
    };
    let exe = exe.unwrap_or_else(|| {
        std::env::current_exe()
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_default()
    });
    let runfiles = format!("{}.runfiles/_main/tools/sdk-codegen", exe);
    if std::path::Path::new(&runfiles).is_dir() {
        return runfiles;
    }
    fsio::dirname(&exe)
}

#[repr(C)]
struct Winsize {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
}

extern "C" {
    fn ioctl(fd: i32, request: std::os::raw::c_ulong, ...) -> i32;
}

#[cfg(target_os = "macos")]
const TIOCGWINSZ: std::os::raw::c_ulong = 0x40087468;
#[cfg(not(target_os = "macos"))]
const TIOCGWINSZ: std::os::raw::c_ulong = 0x5413;

/// The columns of the terminal stdout is, as `os.get_terminal_size` reads them.
fn terminal_columns() -> Option<usize> {
    let mut size = Winsize {
        ws_row: 0,
        ws_col: 0,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    // SAFETY: TIOCGWINSZ writes one winsize into the struct it is given.
    let rc = unsafe { ioctl(1, TIOCGWINSZ, &mut size as *mut Winsize) };
    if rc != 0 {
        return None;
    }
    let _ = (size.ws_row, size.ws_xpixel, size.ws_ypixel);
    Some(if size.ws_col == 0 {
        80
    } else {
        size.ws_col as usize
    })
}

/// How an exception nothing caught is printed.
pub fn traceback(e: &PyErr) -> String {
    let own = format!(
        "Traceback (most recent call last):\n  (sdk-codegen-rs: Python's stack frames are not reproduced)\n{}\n",
        e.render()
    );
    match &e.cause {
        None => own,
        Some(cause) => format!(
            "{}\nThe above exception was the direct cause of the following exception:\n\n{}",
            traceback(cause),
            own
        ),
    }
}

/// The whole program: `main(arguments)` and how Python exits from it.
pub fn run(argv: &[String], out: &mut dyn Write, err: &mut dyn Write) -> i32 {
    let argv0 = argv.first().cloned().unwrap_or_default();
    let prog = argv0.rsplit('/').next().unwrap_or("").to_string();
    let columns = std::env::var("COLUMNS").ok();
    let width = argparse::width_from(columns.as_deref(), terminal_columns());
    let options = match argparse::parse(&prog, &argv[argv.len().min(1)..], width) {
        Parsed::Help(text) => {
            let _ = out.write_all(text.as_bytes());
            return 0;
        }
        Parsed::Error(text) => {
            let _ = err.write_all(text.as_bytes());
            return 2;
        }
        Parsed::Run(options) => options,
    };
    let root = std::env::var("BUILD_WORKSPACE_DIRECTORY")
        .ok()
        .filter(|r| !r.is_empty());
    let package = match options.package.filter(|p| !p.is_empty()) {
        Some(p) => p,
        None => {
            let base = root.unwrap_or_else(|| fsio::dirname(&fsio::dirname(&here(&argv0))));
            fsio::join(&base, PACKAGE)
        }
    };
    let result = if options.check {
        check(&package, out, err)
    } else {
        let folder = options
            .out
            .filter(|o| !o.is_empty())
            .unwrap_or_else(|| package.clone());
        write(&package, &folder, out)
    };
    match result {
        Ok(code) => code,
        Err(e) if e.exit => {
            let _ = writeln!(err, "{}", e.message);
            1
        }
        Err(e) => {
            let _ = out.flush();
            let _ = err.write_all(traceback(&e).as_bytes());
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_paths() {
        assert!(is_generated("kits/python/x/generated/messages.py"));
        assert!(is_generated("go/toolkit/protocol_gen.go"));
        assert!(!is_generated("kits/generated"));
        assert!(!is_generated("go/toolkit/protocol.go"));
    }

    #[test]
    fn normpaths() {
        assert_eq!(normpath("a/./b/../c"), "a/c");
        assert_eq!(normpath("/a/../../b"), "/b");
        assert_eq!(normpath("../a"), "../a");
        assert_eq!(normpath(""), ".");
        assert_eq!(normpath("//a"), "//a");
    }

    #[test]
    fn a_crash_prints_the_traceback_line() {
        let e = PyErr::new("KeyError", "'$defs'");
        assert!(traceback(&e).ends_with("\nKeyError: '$defs'\n"));
    }
}
