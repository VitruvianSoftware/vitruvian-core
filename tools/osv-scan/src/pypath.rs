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

//! `os.path.realpath`, `normpath` and `abspath` from CPython's posixpath, on
//! bytes, for the advisory comparison. The paths come from osv-scanner's JSON
//! and the realpath of both scan roots decides whether a finding is matched
//! by relative path or counts as new, so this follows `_joinrealpath`
//! step for step (non-strict: a missing component is kept as written, a
//! symlink loop stops resolving).

use std::collections::HashMap;
use std::ffi::OsStr;
use std::os::unix::ffi::{OsStrExt, OsStringExt};

/// Python raised (an embedded NUL byte reaching `os.lstat`).
#[derive(Debug, PartialEq)]
pub struct PyError;

fn os(p: &[u8]) -> &OsStr {
    OsStr::from_bytes(p)
}

/// `posixpath.join(a, b)`.
pub fn join(a: &[u8], b: &[u8]) -> Vec<u8> {
    if b.first() == Some(&b'/') {
        return b.to_vec();
    }
    let mut out = a.to_vec();
    if !(out.is_empty() || out.ends_with(b"/")) {
        out.push(b'/');
    }
    out.extend_from_slice(b);
    out
}

/// `posixpath.split(p)`.
pub fn split(p: &[u8]) -> (Vec<u8>, Vec<u8>) {
    let i = p
        .iter()
        .rposition(|c| *c == b'/')
        .map(|i| i + 1)
        .unwrap_or(0);
    let (head, tail) = (&p[..i], &p[i..]);
    let mut head = head.to_vec();
    if !head.is_empty() && head.iter().any(|c| *c != b'/') {
        while head.ends_with(b"/") {
            head.pop();
        }
    }
    (head, tail.to_vec())
}

/// `posixpath.normpath(p)`.
pub fn normpath(p: &[u8]) -> Vec<u8> {
    if p.is_empty() {
        return b".".to_vec();
    }
    let initial = if p.starts_with(b"/") {
        if p.starts_with(b"//") && !p.starts_with(b"///") {
            2
        } else {
            1
        }
    } else {
        0
    };
    let mut comps: Vec<&[u8]> = Vec::new();
    for comp in p.split(|c| *c == b'/') {
        if comp.is_empty() || comp == b"." {
            continue;
        }
        if comp != b".." || (initial == 0 && comps.is_empty()) || comps.last() == Some(&&b".."[..])
        {
            comps.push(comp);
        } else if !comps.is_empty() {
            comps.pop();
        }
    }
    let mut out = vec![b'/'; initial];
    out.extend_from_slice(&comps.join(&b'/'));
    if out.is_empty() {
        b".".to_vec()
    } else {
        out
    }
}

/// `posixpath.abspath(p)`, against the process's real working directory.
pub fn abspath(p: &[u8]) -> Vec<u8> {
    if p.starts_with(b"/") {
        return normpath(p);
    }
    let cwd = std::env::current_dir()
        .map(|c| c.into_os_string().into_vec())
        .unwrap_or_default();
    normpath(&join(&cwd, p))
}

fn join_realpath(
    mut path: Vec<u8>,
    rest: &[u8],
    seen: &mut HashMap<Vec<u8>, Option<Vec<u8>>>,
) -> Result<(Vec<u8>, bool), PyError> {
    let mut rest: Vec<u8> = rest.to_vec();
    if rest.starts_with(b"/") {
        rest.remove(0);
        path = b"/".to_vec();
    }
    while !rest.is_empty() {
        let (name, tail) = match rest.iter().position(|c| *c == b'/') {
            Some(i) => (rest[..i].to_vec(), rest[i + 1..].to_vec()),
            None => (rest.clone(), Vec::new()),
        };
        rest = tail;
        if name.is_empty() || name == b"." {
            continue;
        }
        if name == b".." {
            if !path.is_empty() {
                let (head, n) = split(&path);
                path = head;
                if n == b".." {
                    path = join(&join(&path, b".."), b"..");
                }
            } else {
                path = b"..".to_vec();
            }
            continue;
        }
        let newpath = join(&path, &name);
        if newpath.contains(&0) {
            return Err(PyError);
        }
        let is_link = std::fs::symlink_metadata(os(&newpath))
            .map(|m| m.file_type().is_symlink())
            .unwrap_or(false);
        if !is_link {
            path = newpath;
            continue;
        }
        if let Some(entry) = seen.get(&newpath) {
            match entry {
                Some(resolved) => {
                    path = resolved.clone();
                    continue;
                }
                None => return Ok((join(&newpath, &rest), false)),
            }
        }
        seen.insert(newpath.clone(), None);
        let target = std::fs::read_link(os(&newpath))
            .map(|t| t.into_os_string().into_vec())
            .unwrap_or_default();
        let (p, ok) = join_realpath(path, &target, seen)?;
        path = p;
        if !ok {
            return Ok((join(&path, &rest), false));
        }
        seen.insert(newpath, Some(path.clone()));
    }
    Ok((path, true))
}

/// `os.path.realpath(p)`.
pub fn realpath(p: &[u8]) -> Result<Vec<u8>, PyError> {
    let (path, _) = join_realpath(Vec::new(), p, &mut HashMap::new())?;
    Ok(abspath(&path))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normpath_matches_python() {
        for (i, o) in [
            ("", "."),
            ("/", "/"),
            ("//", "//"),
            ("///", "/"),
            ("//a/../b", "//b"),
            ("a/./b/", "a/b"),
            ("../a", "../a"),
            ("a/../..", ".."),
            ("/../a", "/a"),
            ("a//b", "a/b"),
        ] {
            assert_eq!(normpath(i.as_bytes()), o.as_bytes(), "{i}");
        }
    }

    #[test]
    fn realpath_resolves_links_and_keeps_missing() {
        let d = std::env::temp_dir().join(format!("osv-scan-rp-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(d.join("real/sub")).unwrap();
        std::os::unix::fs::symlink("real", d.join("ln")).unwrap();
        std::os::unix::fs::symlink("loop2", d.join("loop1")).unwrap();
        std::os::unix::fs::symlink("loop1", d.join("loop2")).unwrap();
        let base = realpath(d.as_os_str().as_bytes()).unwrap();
        let mut want = base.clone();
        want.extend_from_slice(b"/real/sub/missing");
        let mut q = d.as_os_str().as_bytes().to_vec();
        q.extend_from_slice(b"/ln/sub/../sub/missing");
        assert_eq!(realpath(&q).unwrap(), want);
        let mut l = d.as_os_str().as_bytes().to_vec();
        l.extend_from_slice(b"/loop1/x");
        let got = realpath(&l).unwrap();
        assert!(
            got.ends_with(b"/loop1/x"),
            "{}",
            String::from_utf8_lossy(&got)
        );
        assert_eq!(realpath(b"a\0b"), Err(PyError));
        std::fs::remove_dir_all(&d).unwrap();
    }
}
