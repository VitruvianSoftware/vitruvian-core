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

//! The pieces of Go's standard library whose exact output the Go tool
//! printed: `strconv.Quote` (`%q`), `filepath.Clean`/`Join`/`Abs`, Go's
//! `unicode.IsSpace` trimming, and the text of an `*os.PathError`.

use std::io;
use std::path::Path;

/// Go's `unicode.IsSpace`: the Unicode White_Space property, as Rust's
/// `char::is_whitespace` is.
pub fn is_space(c: char) -> bool {
    c.is_whitespace()
}

/// Go's `strings.TrimSpace`.
pub fn trim_space(s: &str) -> &str {
    s.trim_matches(is_space)
}

/// Go's `strings.Fields`.
pub fn fields(s: &str) -> Vec<&str> {
    s.split(is_space).filter(|f| !f.is_empty()).collect()
}

fn is_print(c: char) -> bool {
    let u = c as u32;
    if u < 0x80 {
        return (0x20..0x7f).contains(&u);
    }
    if c.is_control() || c.is_whitespace() {
        return false;
    }
    !matches!(u,
        0xad
        | 0x600..=0x605
        | 0x61c
        | 0x6dd
        | 0x70f
        | 0x180e
        | 0x200b..=0x200f
        | 0x202a..=0x202e
        | 0x2060..=0x206f
        | 0xd800..=0xf8ff
        | 0xfeff
        | 0xfff9..=0xfffb
        | 0xfffe..=0xffff
        | 0xe0000..=0x10ffff)
}

/// Go's `strconv.Quote`, which is what `%q` prints for a string.
pub fn quote(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{7}' => out.push_str("\\a"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{b}' => out.push_str("\\v"),
            c if is_print(c) => out.push(c),
            c if (c as u32) < 0x20 || c as u32 == 0x7f => {
                out.push_str(&format!("\\x{:02x}", c as u32));
            }
            c if (c as u32) < 0x10000 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push_str(&format!("\\U{:08x}", c as u32)),
        }
    }
    out.push('"');
    out
}

/// Go's `filepath.Clean` on a Unix path.
pub fn clean(path: &str) -> String {
    if path.is_empty() {
        return ".".to_string();
    }
    let rooted = path.starts_with('/');
    let mut parts: Vec<&str> = Vec::new();
    for part in path.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                if matches!(parts.last(), Some(p) if *p != "..") {
                    parts.pop();
                } else if !rooted {
                    parts.push("..");
                }
            }
            p => parts.push(p),
        }
    }
    let joined = parts.join("/");
    if rooted {
        format!("/{joined}")
    } else if joined.is_empty() {
        ".".to_string()
    } else {
        joined
    }
}

/// Go's `filepath.Join` of two elements.
pub fn join(a: &str, b: &str) -> String {
    match (a.is_empty(), b.is_empty()) {
        (true, true) => String::new(),
        (true, false) => clean(b),
        (false, true) => clean(a),
        (false, false) => clean(&format!("{a}/{b}")),
    }
}

/// Go's `filepath.Dir`.
pub fn dir(path: &str) -> String {
    match path.rfind('/') {
        Some(i) => clean(&path[..=i]),
        None => clean(""),
    }
}

/// Go's `os.Getwd`: `$PWD` when it names the current directory (so a
/// symlinked path is kept as the user typed it), else the kernel's answer.
pub fn getwd() -> io::Result<String> {
    use std::os::unix::fs::MetadataExt;
    let dot = std::fs::metadata(".")?;
    if let Ok(pwd) = std::env::var("PWD") {
        if pwd.starts_with('/') {
            if let Ok(d) = std::fs::metadata(&pwd) {
                if d.dev() == dot.dev() && d.ino() == dot.ino() {
                    return Ok(pwd);
                }
            }
        }
    }
    Ok(std::env::current_dir()?.to_string_lossy().into_owned())
}

/// Go's `filepath.Abs`.
pub fn abs(path: &str) -> io::Result<String> {
    if path.starts_with('/') {
        return Ok(clean(path));
    }
    Ok(join(&getwd()?, path))
}

/// The errno text Go's `syscall.Errno.Error()` prints for the common cases.
pub fn errno_text(err: &io::Error) -> String {
    let known = match err.raw_os_error() {
        Some(1) => Some("operation not permitted"),
        Some(2) => Some("no such file or directory"),
        Some(5) => Some("input/output error"),
        Some(13) => Some("permission denied"),
        Some(17) => Some("file exists"),
        Some(20) => Some("not a directory"),
        Some(21) => Some("is a directory"),
        Some(28) => Some("no space left on device"),
        Some(30) => Some("read-only file system"),
        Some(36) | Some(63) => Some("file name too long"),
        Some(40) | Some(62) => Some("too many levels of symbolic links"),
        _ => None,
    };
    match known {
        Some(t) => t.to_string(),
        None => {
            let s = err.to_string();
            match s.find(" (os error") {
                Some(i) => s[..i].to_lowercase(),
                None => s.to_lowercase(),
            }
        }
    }
}

/// The text of a Go `*os.PathError`: "<op> <path>: <errno>".
pub fn path_error(op: &str, path: &str, err: &io::Error) -> String {
    format!("{op} {path}: {}", errno_text(err))
}

/// Go's `os.ReadFile`, with its error text.
pub fn read_file(path: &str) -> Result<Vec<u8>, String> {
    use std::io::Read;
    let mut f = std::fs::File::open(path).map_err(|e| path_error("open", path, &e))?;
    let mut buf = Vec::new();
    f.read_to_end(&mut buf)
        .map_err(|e| path_error("read", path, &e))?;
    Ok(buf)
}

/// Go's `os.WriteFile(path, data, 0o644)`, with its error text.
pub fn write_file(path: &str, data: &[u8]) -> Result<(), String> {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    let mut f = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o644)
        .open(path)
        .map_err(|e| path_error("open", path, &e))?;
    f.write_all(data).map_err(|e| path_error("write", path, &e))
}

/// Go's `os.MkdirAll(path, 0o755)`, with its error text.
pub fn mkdir_all(path: &str) -> Result<(), String> {
    use std::os::unix::fs::DirBuilderExt;
    match std::fs::metadata(path) {
        Ok(m) if m.is_dir() => return Ok(()),
        Ok(_) => return Err(path_error("mkdir", path, &io::Error::from_raw_os_error(20))),
        Err(_) => {}
    }
    let trimmed = path.trim_end_matches('/');
    if let Some(i) = trimmed.rfind('/') {
        let parent = trimmed[..i].trim_end_matches('/');
        if !parent.is_empty() {
            mkdir_all(parent)?;
        }
    }
    match std::fs::DirBuilder::new().mode(0o755).create(path) {
        Ok(()) => Ok(()),
        Err(e) => match std::fs::symlink_metadata(path) {
            Ok(m) if m.is_dir() => Ok(()),
            _ => Err(path_error("mkdir", path, &e)),
        },
    }
}

/// Whether anything exists at `path` (Go's `os.Stat(path) == nil`).
pub fn exists(path: &str) -> bool {
    Path::new(path).metadata().is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quote_matches_go() {
        assert_eq!(quote("a b"), "\"a b\"");
        assert_eq!(quote("@x\"y"), "\"@x\\\"y\"");
        assert_eq!(quote("a\tb\u{1}"), "\"a\\tb\\x01\"");
        assert_eq!(quote("é"), "\"é\"");
        assert_eq!(quote("\u{a0}"), "\"\\u00a0\"");
    }

    #[test]
    fn clean_matches_go() {
        assert_eq!(clean(""), ".");
        assert_eq!(clean("/a/b/../c/"), "/a/c");
        assert_eq!(clean("a/../.."), "..");
        assert_eq!(clean("/../x"), "/x");
        assert_eq!(clean("//a//b"), "/a/b");
        assert_eq!(join("/r", ".github/CODEOWNERS"), "/r/.github/CODEOWNERS");
        assert_eq!(join("/r", "/abs"), "/r/abs");
        assert_eq!(dir("/a/b/c"), "/a/b");
        assert_eq!(dir("c"), ".");
    }

    #[test]
    fn trimming_matches_go() {
        assert_eq!(trim_space("\u{a0} x \t"), "x");
        assert_eq!(fields(" a  b\tc "), vec!["a", "b", "c"]);
    }
}
