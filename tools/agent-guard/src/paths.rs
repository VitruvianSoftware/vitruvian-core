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

//! `os.path` (posixpath) as Python has it, string in and string out, and the
//! file reads the guard makes, with Python's decoding.

use std::fs;
use std::path::Path;

/// Python raises ValueError on a path with a NUL byte where the guard does not
/// catch it; the hook then allows the call and logs the error. A panic is the
/// same thing here (the hook catches it the same way).
pub fn nul_check(p: &str) {
    if p.contains('\0') {
        panic!("ValueError: embedded null byte");
    }
}

pub fn isabs(p: &str) -> bool {
    p.starts_with('/')
}

pub fn basename(p: &str) -> &str {
    match p.rfind('/') {
        Some(i) => &p[i + 1..],
        None => p,
    }
}

pub fn dirname(p: &str) -> String {
    let i = p.rfind('/').map(|i| i + 1).unwrap_or(0);
    let head = &p[..i];
    if !head.is_empty() && head.chars().any(|c| c != '/') {
        head.trim_end_matches('/').to_string()
    } else {
        head.to_string()
    }
}

/// `os.path.split`.
pub fn split(p: &str) -> (String, String) {
    let i = p.rfind('/').map(|i| i + 1).unwrap_or(0);
    let (head, tail) = (&p[..i], &p[i..]);
    let head = if !head.is_empty() && head.chars().any(|c| c != '/') {
        head.trim_end_matches('/')
    } else {
        head
    };
    (head.to_string(), tail.to_string())
}

pub fn join(a: &str, b: &str) -> String {
    if b.starts_with('/') {
        return b.to_string();
    }
    if a.is_empty() || a.ends_with('/') {
        format!("{}{}", a, b)
    } else {
        format!("{}/{}", a, b)
    }
}

pub fn normpath(path: &str) -> String {
    if path.is_empty() {
        return ".".into();
    }
    let mut initial = if path.starts_with('/') { 1 } else { 0 };
    if initial == 1 && path.starts_with("//") && !path.starts_with("///") {
        initial = 2;
    }
    let mut comps: Vec<&str> = Vec::new();
    for comp in path.split('/') {
        if comp.is_empty() || comp == "." {
            continue;
        }
        if comp != ".." || (initial == 0 && comps.is_empty()) || comps.last() == Some(&"..") {
            comps.push(comp);
        } else if !comps.is_empty() {
            comps.pop();
        }
    }
    let mut out = "/".repeat(initial);
    out.push_str(&comps.join("/"));
    if out.is_empty() {
        ".".into()
    } else {
        out
    }
}

pub fn getcwd() -> String {
    std::env::current_dir()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|_| "/".into())
}

pub fn abspath(p: &str) -> String {
    if isabs(p) {
        normpath(p)
    } else {
        normpath(&join(&getcwd(), p))
    }
}

pub fn exists(p: &str) -> bool {
    fs::metadata(p).is_ok()
}

pub fn lexists(p: &str) -> bool {
    fs::symlink_metadata(p).is_ok()
}

pub fn isdir(p: &str) -> bool {
    fs::metadata(p).map(|m| m.is_dir()).unwrap_or(false)
}

pub fn isfile(p: &str) -> bool {
    fs::metadata(p).map(|m| m.is_file()).unwrap_or(false)
}

fn islink(p: &str) -> bool {
    nul_check(p);
    fs::symlink_metadata(p)
        .map(|m| m.file_type().is_symlink())
        .unwrap_or(false)
}

/// `os.path.realpath(p)` (not strict), Python 3.12's algorithm.
pub fn realpath(p: &str) -> String {
    let mut seen: std::collections::HashMap<String, Option<String>> = Default::default();
    let (path, _) = join_realpath(String::new(), p, &mut seen);
    abspath(&path)
}

fn join_realpath(
    mut path: String,
    rest: &str,
    seen: &mut std::collections::HashMap<String, Option<String>>,
) -> (String, bool) {
    let mut rest = rest.to_string();
    if isabs(&rest) {
        rest = rest[1..].to_string();
        path = "/".into();
    }
    while !rest.is_empty() {
        let (name, tail) = match rest.find('/') {
            Some(i) => (rest[..i].to_string(), rest[i + 1..].to_string()),
            None => (rest.clone(), String::new()),
        };
        rest = tail;
        if name.is_empty() || name == "." {
            continue;
        }
        if name == ".." {
            if !path.is_empty() {
                let (head, n) = split(&path);
                path = head;
                if n == ".." {
                    path = join(&join(&path, ".."), "..");
                }
            } else {
                path = "..".into();
            }
            continue;
        }
        let newpath = join(&path, &name);
        if !islink(&newpath) {
            path = newpath;
            continue;
        }
        if let Some(prev) = seen.get(&newpath) {
            match prev {
                Some(resolved) => {
                    path = resolved.clone();
                    continue;
                }
                None => return (join(&newpath, &rest), false),
            }
        }
        seen.insert(newpath.clone(), None);
        let target = match fs::read_link(&newpath) {
            Ok(t) => t.to_string_lossy().into_owned(),
            Err(_) => {
                // Python's os.readlink would raise here; it cannot, as lstat
                // just said this is a link. Treat it as not one.
                path = newpath;
                continue;
            }
        };
        let (p2, ok) = join_realpath(path, &target, seen);
        path = p2;
        if !ok {
            return (join(&path, &rest), false);
        }
        seen.insert(newpath, Some(path.clone()));
    }
    (path, true)
}

pub fn relpath(path: &str, start: &str) -> String {
    let s = abspath(start);
    let p = abspath(path);
    let sl: Vec<&str> = s.split('/').filter(|x| !x.is_empty()).collect();
    let pl: Vec<&str> = p.split('/').filter(|x| !x.is_empty()).collect();
    let mut i = 0;
    while i < sl.len() && i < pl.len() && sl[i] == pl[i] {
        i += 1;
    }
    let mut rel: Vec<&str> = vec![".."; sl.len() - i];
    rel.extend_from_slice(&pl[i..]);
    if rel.is_empty() {
        return ".".into();
    }
    let mut out = String::new();
    for r in rel {
        out = if out.is_empty() {
            r.to_string()
        } else {
            join(&out, r)
        };
    }
    out
}

/// `os.path.expanduser("~")`.
pub fn home_dir() -> String {
    let home = std::env::var("HOME").unwrap_or_default();
    let home = home.trim_end_matches('/');
    if home.is_empty() {
        "/".into()
    } else {
        home.to_string()
    }
}

/// `open(p, encoding="utf-8", errors="replace").read()`.
pub fn read_text_replace(p: &str) -> Option<String> {
    let bytes = fs::read(p).ok()?;
    Some(crate::pyutil::universal_newlines(&String::from_utf8_lossy(
        &bytes,
    )))
}

/// `open(p, encoding="utf-8").read()`: None on OSError; a strict decode
/// failure is Python's UnicodeDecodeError, which the guard does not catch.
pub fn read_text_strict(p: &str) -> Option<String> {
    let bytes = fs::read(p).ok()?;
    match String::from_utf8(bytes) {
        Ok(s) => Some(crate::pyutil::universal_newlines(&s)),
        Err(_) => panic!("UnicodeDecodeError: {}", p),
    }
}

/// The first `n` characters of a text file, as `fh.read(n)` returns them.
pub fn read_text_head(p: &str, n: usize) -> Option<String> {
    use std::io::Read;
    let mut f = fs::File::open(Path::new(p)).ok()?;
    let mut buf = Vec::new();
    f.by_ref()
        .take((n * 4 + 4) as u64)
        .read_to_end(&mut buf)
        .ok()?;
    let text = crate::pyutil::universal_newlines(&String::from_utf8_lossy(&buf));
    Some(text.chars().take(n).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn posixpath() {
        assert_eq!(normpath("//a/../b/./c/"), "//b/c");
        assert_eq!(normpath("///a"), "/a");
        assert_eq!(normpath("a/../.."), "..");
        assert_eq!(normpath(""), ".");
        assert_eq!(normpath("/.."), "/");
        assert_eq!(dirname("/a/b//"), "/a/b");
        assert_eq!(dirname("//"), "//");
        assert_eq!(basename("/a/b"), "b");
        assert_eq!(join("a", "/b"), "/b");
        assert_eq!(relpath("/a/b/c", "/a"), "b/c");
        assert_eq!(relpath("/a", "/a"), ".");
    }
}
