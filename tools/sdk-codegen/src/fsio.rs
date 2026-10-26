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

//! Files as Python's `open(path, encoding="utf-8")` reads and writes them:
//! UTF-8 strictly, "\r\n" and "\r" read as "\n", and the OSError or
//! UnicodeDecodeError Python raises, in its words. `os.path.join` and
//! `os.walk` as sdk_codegen.py uses them.

use crate::pyerr::{PyErr, PyResult};
use crate::pystr;
use std::fs;
use std::io;
use std::path::Path;

/// `os.path.join(a, b)` on POSIX.
pub fn join(a: &str, b: &str) -> String {
    if b.starts_with('/') || a.is_empty() {
        b.to_string()
    } else if a.ends_with('/') {
        format!("{}{}", a, b)
    } else {
        format!("{}/{}", a, b)
    }
}

/// `os.path.dirname(p)` on POSIX.
pub fn dirname(p: &str) -> String {
    let i = p.rfind('/').map(|i| i + 1).unwrap_or(0);
    let head = &p[..i];
    if !head.is_empty() && head.chars().any(|c| c != '/') {
        head.trim_end_matches('/').to_string()
    } else {
        head.to_string()
    }
}

/// The OSError Python raises for `err` on `path`.
pub fn os_error(err: &io::Error, path: &str) -> PyErr {
    let code = err.raw_os_error().unwrap_or(0);
    let class = match code {
        1 | 13 => "PermissionError",
        2 => "FileNotFoundError",
        17 => "FileExistsError",
        20 => "NotADirectoryError",
        21 => "IsADirectoryError",
        _ => "OSError",
    };
    let text = err.to_string();
    let strerror = match text.rfind(" (os error ") {
        Some(i) => text[..i].to_string(),
        None => text,
    };
    PyErr::new(
        class,
        format!("[Errno {}] {}: {}", code, strerror, pystr::repr_str(path)),
    )
}

fn is_dir_error(path: &str) -> PyErr {
    PyErr::new(
        "IsADirectoryError",
        format!("[Errno 21] Is a directory: {}", pystr::repr_str(path)),
    )
}

/// The UnicodeDecodeError `bytes.decode("utf-8")` raises, or the text.
pub fn decode_utf8(data: &[u8]) -> PyResult<String> {
    match std::str::from_utf8(data) {
        Ok(s) => Ok(s.to_string()),
        Err(e) => {
            let start = e.valid_up_to();
            let (end, reason) = match e.error_len() {
                None => (data.len(), "unexpected end of data"),
                Some(n) => {
                    let lead = data[start];
                    let bad_start = (0x80..=0xC1).contains(&lead) || lead >= 0xF5;
                    (
                        start + n,
                        if bad_start {
                            "invalid start byte"
                        } else {
                            "invalid continuation byte"
                        },
                    )
                }
            };
            let message = if end - start == 1 {
                format!(
                    "'utf-8' codec can't decode byte 0x{:02x} in position {}: {}",
                    data[start], start, reason
                )
            } else {
                format!(
                    "'utf-8' codec can't decode bytes in position {}-{}: {}",
                    start,
                    end - 1,
                    reason
                )
            };
            Err(PyErr::new("UnicodeDecodeError", message))
        }
    }
}

/// `open(path, encoding="utf-8").read()`.
pub fn read_text(path: &str) -> PyResult<String> {
    let file = fs::File::open(path).map_err(|e| os_error(&e, path))?;
    if file.metadata().map(|m| m.is_dir()).unwrap_or(false) {
        return Err(is_dir_error(path));
    }
    let mut data = Vec::new();
    io::Read::read_to_end(&mut &file, &mut data).map_err(|e| os_error(&e, path))?;
    let text = decode_utf8(&data)?;
    Ok(text.replace("\r\n", "\n").replace('\r', "\n"))
}

/// `os.makedirs(path, exist_ok=True)`.
pub fn makedirs(path: &str) -> PyResult<()> {
    if path.is_empty() {
        return Err(PyErr::new(
            "FileNotFoundError",
            "[Errno 2] No such file or directory: ''",
        ));
    }
    if Path::new(path).is_dir() {
        return Ok(());
    }
    let head = dirname(path.trim_end_matches('/'));
    if !head.is_empty() && !Path::new(&head).exists() {
        makedirs(&head)?;
    }
    match fs::create_dir(path) {
        Ok(()) => Ok(()),
        Err(_) if Path::new(path).is_dir() => Ok(()),
        Err(e) => Err(os_error(&e, path)),
    }
}

/// `open(path, "w", encoding="utf-8").write(text)`.
pub fn write_text(path: &str, text: &str) -> PyResult<()> {
    if Path::new(path).is_dir() {
        return Err(is_dir_error(path));
    }
    fs::write(path, text.as_bytes()).map_err(|e| os_error(&e, path))
}

/// Every file under `top` as `os.walk` finds them, by its path below `top`,
/// skipping the folders `skip` names; nothing for a `top` that is no folder.
pub fn walk(top: &str, skip: &[&str]) -> Vec<String> {
    let mut out = Vec::new();
    walk_into(top, "", skip, &mut out);
    out
}

fn walk_into(dir: &str, below: &str, skip: &[&str], out: &mut Vec<String>) {
    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(_) => return,
    };
    let mut folders = Vec::new();
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        let path = join(dir, &name);
        let rel = if below.is_empty() {
            name.clone()
        } else {
            format!("{}/{}", below, name)
        };
        let is_dir = fs::metadata(&path).map(|m| m.is_dir()).unwrap_or(false);
        if is_dir {
            let link = fs::symlink_metadata(&path)
                .map(|m| m.file_type().is_symlink())
                .unwrap_or(false);
            if !skip.contains(&name.as_str()) && !link {
                folders.push((path, rel));
            }
        } else {
            out.push(rel);
        }
    }
    for (path, rel) in folders {
        walk_into(&path, &rel, skip, out);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paths() {
        assert_eq!(join("a", "b"), "a/b");
        assert_eq!(join("a/", "b"), "a/b");
        assert_eq!(join("", "b"), "b");
        assert_eq!(join("a", "/b"), "/b");
        assert_eq!(dirname("a/b/c.txt"), "a/b");
        assert_eq!(dirname("c.txt"), "");
        assert_eq!(dirname("/c"), "/");
    }

    #[test]
    fn decode_errors_are_pythons() {
        let msg = |b: &[u8]| decode_utf8(b).unwrap_err().message;
        assert_eq!(
            msg(b"\xff"),
            "'utf-8' codec can't decode byte 0xff in position 0: invalid start byte"
        );
        assert_eq!(
            msg(b"ab\xe2\x82"),
            "'utf-8' codec can't decode bytes in position 2-3: unexpected end of data"
        );
        assert_eq!(
            msg(b"\xe2\x28"),
            "'utf-8' codec can't decode byte 0xe2 in position 0: invalid continuation byte"
        );
        assert_eq!(
            msg(b"\xe2\x82\x28"),
            "'utf-8' codec can't decode bytes in position 0-1: invalid continuation byte"
        );
    }

    #[test]
    fn reads_with_universal_newlines() {
        let dir = std::env::temp_dir().join(format!("sdk-codegen-fsio-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let file = dir.join("x.txt");
        fs::write(&file, b"a\r\nb\rc\n").unwrap();
        assert_eq!(read_text(file.to_str().unwrap()).unwrap(), "a\nb\nc\n");
        let missing = dir.join("nope");
        assert_eq!(
            read_text(missing.to_str().unwrap()).unwrap_err().render(),
            format!(
                "FileNotFoundError: [Errno 2] No such file or directory: '{}'",
                missing.to_str().unwrap()
            )
        );
        assert!(read_text(dir.to_str().unwrap())
            .unwrap_err()
            .render()
            .starts_with("IsADirectoryError"));
        fs::remove_dir_all(&dir).unwrap();
    }
}
