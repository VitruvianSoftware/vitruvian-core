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

//! `os.path` (posixpath) and `pathlib` as sync.py uses them, over Python
//! strings, and the file system calls it makes, with the exceptions Python
//! 3.12 raises and their messages.

use std::ffi::OsStr;
use std::fs;
use std::io::{self, Read, Write};
use std::os::unix::ffi::OsStrExt;
use std::path::PathBuf;

use crate::pyerr::PyErr;
use crate::pystr::{self, PyStr};

const SLASH: u32 = '/' as u32;

/// `os.path.join(a, b)`.
pub fn join(a: &PyStr, b: &str) -> PyStr {
    join_s(a, &PyStr::from(b))
}

pub fn join_s(a: &PyStr, b: &PyStr) -> PyStr {
    if b.chars().first() == Some(&SLASH) {
        return b.clone();
    }
    let mut out = a.clone();
    if !a.is_empty() && a.chars().last() != Some(&SLASH) {
        out.push_char(SLASH);
    }
    out.push(b);
    out
}

/// `os.path.normpath(path)`.
pub fn normpath(path: &PyStr) -> PyStr {
    if path.is_empty() {
        return PyStr::from(".");
    }
    let chars = path.chars();
    let mut initial = 0;
    while initial < chars.len() && chars[initial] == SLASH {
        initial += 1;
    }
    let initial = match initial {
        0 => 0,
        2 => 2,
        _ => 1,
    };
    let mut comps: Vec<PyStr> = Vec::new();
    for comp in path.split_char(SLASH) {
        if comp.is_empty() || comp == PyStr::from(".") {
            continue;
        }
        if comp == PyStr::from("..") {
            if (initial == 0 && comps.is_empty())
                || comps
                    .last()
                    .map_or(false, |last| *last == PyStr::from(".."))
            {
                comps.push(comp);
            } else if !comps.is_empty() {
                comps.pop();
            }
            continue;
        }
        comps.push(comp);
    }
    let mut out = PyStr::from("/".repeat(initial).as_str());
    out.push(&PyStr::join("/", &comps));
    if out.is_empty() {
        PyStr::from(".")
    } else {
        out
    }
}

/// `os.path.split(path)`.
pub fn split(path: &PyStr) -> (PyStr, PyStr) {
    let i = path
        .chars()
        .iter()
        .rposition(|&c| c == SLASH)
        .map_or(0, |i| i + 1);
    let mut head = path.slice(0, i);
    let tail = path.slice(i, path.len());
    if !head.is_empty() && head.chars().iter().any(|&c| c != SLASH) {
        head = head.rstrip_char(SLASH);
    }
    (head, tail)
}

/// `os.path.dirname(path)`.
pub fn dirname(path: &PyStr) -> PyStr {
    split(path).0
}

/// `os.path.basename(path)`.
pub fn basename(path: &PyStr) -> PyStr {
    split(path).1
}

/// `os.path.abspath(path)`.
pub fn abspath(path: &PyStr) -> PyStr {
    if path.chars().first() == Some(&SLASH) {
        return normpath(path);
    }
    let cwd = std::env::current_dir()
        .map(|p| PyStr::from_surrogateescape(p.as_os_str().as_bytes()))
        .unwrap_or_default();
    normpath(&join_s(&cwd, path))
}

/// `str(PurePosixPath(path))`: no `.` parts, no doubled or trailing
/// slashes, and `.` for nothing.
pub fn path_str(path: &PyStr) -> PyStr {
    if path.is_empty() {
        return PyStr::from(".");
    }
    let chars = path.chars();
    let root = if chars.first() != Some(&SLASH) {
        ""
    } else if chars.get(1) != Some(&SLASH) || chars.get(2) == Some(&SLASH) {
        "/"
    } else {
        "//"
    };
    let parts: Vec<PyStr> = path
        .split_char(SLASH)
        .into_iter()
        .filter(|part| !part.is_empty() && *part != PyStr::from("."))
        .collect();
    let mut out = PyStr::from(root);
    out.push(&PyStr::join("/", &parts));
    if out.is_empty() {
        PyStr::from(".")
    } else {
        out
    }
}

/// `str(Path(a) / b)`.
pub fn path_join(a: &PyStr, b: &str) -> PyStr {
    path_str(&join(&path_str(a), b))
}

/// The path a Python str names, for the system call.
pub fn os_path(path: &PyStr) -> PathBuf {
    PathBuf::from(OsStr::from_bytes(&path.to_surrogateescape()))
}

fn errno_class(errno: i32) -> &'static str {
    const EPERM: i32 = 1;
    const ENOENT: i32 = 2;
    const EACCES: i32 = 13;
    const EEXIST: i32 = 17;
    const ENOTDIR: i32 = 20;
    const EISDIR: i32 = 21;
    match errno {
        ENOENT => "FileNotFoundError",
        EACCES | EPERM => "PermissionError",
        EEXIST => "FileExistsError",
        ENOTDIR => "NotADirectoryError",
        EISDIR => "IsADirectoryError",
        _ => "OSError",
    }
}

fn strerror(errno: i32) -> String {
    let text = io::Error::from_raw_os_error(errno).to_string();
    match text.rfind(" (os error ") {
        Some(i) => text[..i].to_string(),
        None => text,
    }
}

/// The OSError Python raises for a failed call on `filename`.
pub fn os_error(error: &io::Error, filename: &PyStr) -> PyErr {
    match error.raw_os_error() {
        Some(errno) => {
            let mut message = PyStr::from(format!("[Errno {}] {}: ", errno, strerror(errno)));
            message.push(&filename.repr());
            PyErr::exc_s(errno_class(errno), message)
        }
        None => PyErr::exc("OSError", &error.to_string()),
    }
}

fn eisdir() -> io::Error {
    io::Error::from_raw_os_error(21)
}

/// `open(path, "rb").read()`.
pub fn read_bytes(path: &PyStr) -> Result<Vec<u8>, PyErr> {
    let fail = |e: io::Error| os_error(&e, path);
    let mut file = fs::File::open(os_path(path)).map_err(fail)?;
    if file.metadata().map_err(fail)?.is_dir() {
        return Err(fail(eisdir()));
    }
    let mut data = Vec::new();
    file.read_to_end(&mut data).map_err(fail)?;
    Ok(data)
}

/// `open(path, encoding="utf-8").read()`, and `Path.read_text`: strict
/// UTF-8 and universal newlines.
pub fn read_text(path: &PyStr) -> Result<PyStr, PyErr> {
    let data = read_bytes(path)?;
    Ok(pystr::universal_newlines(pystr::decode_utf8(&data)?))
}

/// `Path.read_text(encoding="ascii")`.
pub fn read_text_ascii(path: &PyStr) -> Result<PyStr, PyErr> {
    let data = read_bytes(path)?;
    Ok(pystr::universal_newlines(pystr::decode_ascii(&data)?))
}

/// Errors `Path.is_file` and `Path.is_dir` turn into False in 3.12;
/// any other is raised.
fn ignored(error: &io::Error) -> bool {
    const ENOENT: i32 = 2;
    const EBADF: i32 = 9;
    const ENOTDIR: i32 = 20;
    #[cfg(target_os = "linux")]
    const ELOOP: i32 = 40;
    #[cfg(not(target_os = "linux"))]
    const ELOOP: i32 = 62;
    matches!(error.raw_os_error(), Some(ENOENT | EBADF | ENOTDIR | ELOOP))
}

fn path_stat(path: &PyStr) -> Result<Option<fs::Metadata>, PyErr> {
    match fs::metadata(os_path(path)) {
        Ok(meta) => Ok(Some(meta)),
        Err(e) if ignored(&e) => Ok(None),
        Err(e) => Err(os_error(&e, path)),
    }
}

/// `Path(path).is_file()` (3.12).
pub fn is_file(path: &PyStr) -> Result<bool, PyErr> {
    Ok(path_stat(path)?.map_or(false, |m| m.file_type().is_file()))
}

/// `Path(path).is_dir()` (3.12).
pub fn is_dir(path: &PyStr) -> Result<bool, PyErr> {
    Ok(path_stat(path)?.map_or(false, |m| m.file_type().is_dir()))
}

/// `os.path.isfile(path)`: False on any error.
pub fn os_isfile(path: &PyStr) -> bool {
    fs::metadata(os_path(path)).map_or(false, |m| m.file_type().is_file())
}

fn os_isdir(path: &PyStr) -> bool {
    fs::metadata(os_path(path)).map_or(false, |m| m.file_type().is_dir())
}

fn os_exists(path: &PyStr) -> bool {
    fs::metadata(os_path(path)).is_ok()
}

/// `sorted(Path(path).iterdir())`: each child's path, in name order.
pub fn sorted_children(path: &PyStr) -> Result<Vec<(PyStr, PyStr)>, PyErr> {
    let fail = |e: io::Error| os_error(&e, path);
    let mut names: Vec<PyStr> = Vec::new();
    for entry in fs::read_dir(os_path(path)).map_err(fail)? {
        let entry = entry.map_err(fail)?;
        names.push(PyStr::from_surrogateescape(entry.file_name().as_bytes()));
    }
    names.sort();
    Ok(names
        .into_iter()
        .map(|name| {
            let mut child = path.clone();
            if *path == PyStr::from(".") {
                child = name.clone();
            } else {
                if path.chars().last() != Some(&SLASH) {
                    child.push_char(SLASH);
                }
                child.push(&name);
            }
            (child, name)
        })
        .collect())
}

/// `os.makedirs(name, exist_ok=True)`.
pub fn makedirs(name: &PyStr) -> Result<(), PyErr> {
    let (mut head, mut tail) = split(name);
    if tail.is_empty() {
        let again = split(&head);
        head = again.0;
        tail = again.1;
    }
    if !head.is_empty() && !tail.is_empty() && !os_exists(&head) {
        match makedirs(&head) {
            Ok(()) => {}
            Err(PyErr::Exception { ref kind, .. }) if kind == "FileExistsError" => {}
            Err(e) => return Err(e),
        }
        if tail == PyStr::from(".") {
            return Ok(());
        }
    }
    match fs::create_dir(os_path(name)) {
        Ok(()) => Ok(()),
        Err(e) => {
            if os_isdir(name) {
                Ok(())
            } else {
                Err(os_error(&e, name))
            }
        }
    }
}

/// `open(path, "wb").write(data)`.
pub fn write_bytes(path: &PyStr, data: &[u8]) -> Result<(), PyErr> {
    let fail = |e: io::Error| os_error(&e, path);
    let mut file = fs::File::create(os_path(path)).map_err(fail)?;
    file.write_all(data).map_err(fail)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(text: &str) -> PyStr {
        PyStr::from(text)
    }

    #[test]
    fn normpath_is_posixpaths() {
        let cases = [
            ("", "."),
            ("docs/../samples/hello-python", "samples/hello-python"),
            ("docs/../../x", "../x"),
            ("/../x", "/x"),
            ("//a//b/./c/", "//a/b/c"),
            ("///a", "/a"),
            ("a/b/../..", "."),
            ("../../a", "../../a"),
        ];
        for (path, want) in cases {
            assert_eq!(normpath(&s(path)), s(want), "{}", path);
        }
    }

    #[test]
    fn split_join_and_path_str() {
        assert_eq!(split(&s("a/b/c")), (s("a/b"), s("c")));
        assert_eq!(split(&s("/a")), (s("/"), s("a")));
        assert_eq!(split(&s("a//")), (s("a"), s("")));
        assert_eq!(join(&s("a"), "/b"), s("/b"));
        assert_eq!(join(&s("a/"), "b"), s("a/b"));
        assert_eq!(join(&s(""), "b"), s("b"));
        assert_eq!(path_str(&s("/tmp//x/./y/")), s("/tmp/x/y"));
        assert_eq!(path_str(&s("./a")), s("a"));
        assert_eq!(path_str(&s("//a")), s("//a"));
        assert_eq!(
            path_join(&s("."), "catalog/tools.json"),
            s("catalog/tools.json")
        );
    }

    #[test]
    fn errors_name_the_file_as_python_does() {
        let missing = s("/nonexistent-sync-site-tools/x'y");
        let e = read_bytes(&missing).unwrap_err();
        assert_eq!(
            e.last_line(),
            "FileNotFoundError: [Errno 2] No such file or directory: \"/nonexistent-sync-site-tools/x'y\""
        );
        assert!(!is_file(&missing).unwrap());
        let e = read_bytes(&s("/")).unwrap_err();
        assert_eq!(
            e.last_line(),
            "IsADirectoryError: [Errno 21] Is a directory: '/'"
        );
    }
}
