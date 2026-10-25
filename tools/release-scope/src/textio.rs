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

//! Files as `open(path, encoding="utf-8")` reads them: strict UTF-8 with
//! Python's error messages, universal newlines, and the OSError text Python
//! prints when a file cannot be opened. Also os.walk, as find_configs uses it.

use crate::pystr::{decode_os, decode_utf8, encode_os, PyStr};
use crate::pyval::Exc;
use std::ffi::OsStr;
use std::fs::File;
use std::io::{self, Read};
use std::os::unix::ffi::OsStrExt;
use std::path::PathBuf;

/// TextIOWrapper's _CHUNK_SIZE: line-by-line reading decodes this much at
/// a time, and a decode error's position counts from the chunk.
const CHUNK: usize = 8192;

/// The text of strerror(errno), as Python puts it in an OSError.
fn strerror(errno: i32) -> String {
    let text = io::Error::from_raw_os_error(errno).to_string();
    match text.rfind(" (os error ") {
        Some(at) => text[..at].to_string(),
        None => text,
    }
}

/// str(OSError(errno, strerror, filename)).
pub fn os_error(errno: i32, filename: Option<&PyStr>) -> Exc {
    let mut text = PyStr::from(format!("[Errno {}] {}", errno, strerror(errno)).as_str());
    if let Some(name) = filename {
        text.push_str(": ");
        text.push_py(&name.repr());
    }
    Exc::OsError(text)
}

fn io_error(err: &io::Error, filename: Option<&PyStr>) -> Exc {
    match err.raw_os_error() {
        Some(errno) => os_error(errno, filename),
        None => Exc::OsError(PyStr::from(err.to_string().as_str())),
    }
}

/// The path Python would hand the system, or the ValueError it raises first.
pub fn os_path(path: &PyStr) -> Result<PathBuf, Exc> {
    if path.cps().contains(&0) {
        return Err(Exc::ValueError(PyStr::from("embedded null byte")));
    }
    match encode_os(path) {
        Some(bytes) => Ok(PathBuf::from(OsStr::from_bytes(&bytes))),
        // UnicodeEncodeError, a ValueError. Only a surrogate that is not an
        // escaped byte gets here, and no path from the system has one.
        None => {
            let at = path
                .cps()
                .iter()
                .position(|&c| crate::pystr::is_surrogate(c) && !(0xDC80..=0xDCFF).contains(&c))
                .unwrap_or(0);
            Err(Exc::ValueError(PyStr::from(
                crate::pystr::encode_error(path.cps(), at, at + 1).as_str(),
            )))
        }
    }
}

/// open(path, encoding="utf-8"): it fails on a directory, as FileIO does.
fn open(path: &PyStr) -> Result<File, Exc> {
    let os = os_path(path)?;
    let file = File::open(os).map_err(|e| io_error(&e, Some(path)))?;
    match file.metadata() {
        Ok(meta) if meta.is_dir() => Err(os_error(21, Some(path))),
        Ok(_) => Ok(file),
        Err(e) => Err(io_error(&e, Some(path))),
    }
}

/// Universal newlines: `\r\n` and `\r` read as `\n`.
fn translate_newlines(text: Vec<u32>) -> Vec<u32> {
    let mut out = Vec::with_capacity(text.len());
    let mut i = 0;
    while i < text.len() {
        if text[i] == 0x0D {
            out.push(0x0A);
            if i + 1 < text.len() && text[i + 1] == 0x0A {
                i += 1;
            }
        } else {
            out.push(text[i]);
        }
        i += 1;
    }
    out
}

/// `handle.read()`: decoded whole, so an error's position is in the file.
pub fn read_text(path: &PyStr) -> Result<Vec<u32>, Exc> {
    let mut file = open(path)?;
    let mut bytes = Vec::new();
    file.read_to_end(&mut bytes)
        .map_err(|e| io_error(&e, None))?;
    let (text, _) = decode_utf8(&bytes, true)
        .map_err(|e| Exc::ValueError(PyStr::from(e.message().as_str())))?;
    Ok(translate_newlines(text))
}

/// `[line.strip() for line in handle if line.strip()]`.
pub fn read_stripped_lines(path: &PyStr) -> Result<Vec<PyStr>, Exc> {
    let mut file = open(path)?;
    let mut decoded = Vec::new();
    let mut pending: Vec<u8> = Vec::new();
    let mut chunk = vec![0u8; CHUNK];
    loop {
        let got = loop {
            match file.read(&mut chunk) {
                Ok(n) => break n,
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(e) => return Err(io_error(&e, None)),
            }
        };
        let mut input = std::mem::take(&mut pending);
        input.extend_from_slice(&chunk[..got]);
        let last = got == 0;
        let (text, used) = decode_utf8(&input, last)
            .map_err(|e| Exc::ValueError(PyStr::from(e.message().as_str())))?;
        decoded.extend(text);
        pending = input[used..].to_vec();
        if last {
            break;
        }
    }
    let text = PyStr(translate_newlines(decoded));
    Ok(text
        .split("\n")
        .into_iter()
        .map(|line| line.strip())
        .filter(|line| !line.is_empty())
        .collect())
}

/// os.path.join(a, b) for a b with no leading slash.
pub fn join(a: &PyStr, b: &str) -> PyStr {
    let mut out = a.clone();
    if !(a.is_empty() || a.cps().last() == Some(&('/' as u32))) {
        out.push_str("/");
    }
    out.push_str(b);
    out
}

fn join_py(a: &PyStr, b: &PyStr) -> PyStr {
    let mut out = join(a, "");
    out.push_py(b);
    out
}

/// One folder os.walk(top) visits: its path from `top` (the names of the
/// folders on the way), the path os.walk opens it by, and the names in it.
pub struct Folder {
    pub names: Vec<PyStr>,
    pub path: PyStr,
    pub files: Vec<PyStr>,
}

/// os.walk(root), top-down, errors ignored, links to folders not followed,
/// with find_configs' pruning: subfolders in sorted order, never `.git`,
/// `node_modules` or `bazel-*`. Calls `visit` on each folder as os.walk
/// yields it; stops at the first error `visit` returns.
pub fn walk(root: &PyStr, mut visit: impl FnMut(&Folder) -> Result<(), Exc>) -> Result<(), Exc> {
    let mut stack: Vec<(Vec<PyStr>, PyStr)> = vec![(Vec::new(), root.clone())];
    while let Some((names, top)) = stack.pop() {
        let Ok(os_top) = os_path(&top) else { continue };
        let Ok(entries) = std::fs::read_dir(&os_top) else {
            continue;
        };
        let mut dirs = Vec::new();
        let mut files = Vec::new();
        let mut broken = false;
        for entry in entries {
            let Ok(entry) = entry else {
                broken = true;
                break;
            };
            let name = decode_os(entry.file_name().as_bytes());
            // DirEntry.is_dir(): follows a link, and an error means no.
            let is_dir = match entry.file_type() {
                Ok(t) if t.is_symlink() => std::fs::metadata(entry.path())
                    .map(|m| m.is_dir())
                    .unwrap_or(false),
                Ok(t) => t.is_dir(),
                Err(_) => false,
            };
            if is_dir {
                dirs.push(name);
            } else {
                files.push(name);
            }
        }
        if broken {
            continue;
        }
        dirs.retain(|d| !(d.eq_str(".git") || d.eq_str("node_modules") || d.starts_with("bazel-")));
        dirs.sort();
        visit(&Folder {
            names: names.clone(),
            path: top.clone(),
            files,
        })?;
        for d in dirs.iter().rev() {
            let path = join_py(&top, d);
            let is_link = os_path(&path)
                .ok()
                .and_then(|p| std::fs::symlink_metadata(p).ok())
                .map_or(false, |m| m.file_type().is_symlink());
            if !is_link {
                let mut sub = names.clone();
                sub.push(d.clone());
                stack.push((sub, path));
            }
        }
    }
    Ok(())
}
