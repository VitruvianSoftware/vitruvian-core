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

//! The shell behaviour check.sh depends on, reproduced.

use std::path::Path;

/// `$(...)`: command substitution drops every trailing newline.
pub fn strip_trailing_newlines(s: &str) -> String {
    s.trim_end_matches('\n').to_string()
}

/// `read -r v1 .. vn` on one line of input with the default IFS: only the
/// first line is read; fields split on runs of space/tab/newline, leading
/// and trailing whitespace dropped; the last variable takes the remainder
/// (internal whitespace kept, trailing stripped). Missing fields are empty.
pub fn read_fields(input: &str, n: usize) -> Vec<String> {
    let line = input.split('\n').next().unwrap_or("");
    let is_ws = |c: char| c == ' ' || c == '\t' || c == '\n';
    let mut rest = line.trim_start_matches(is_ws);
    let mut out = Vec::with_capacity(n);
    for i in 0..n {
        if i == n - 1 {
            out.push(rest.trim_end_matches(is_ws).to_string());
            break;
        }
        match rest.find(is_ws) {
            Some(p) => {
                out.push(rest[..p].to_string());
                rest = rest[p..].trim_start_matches(is_ws);
            }
            None => {
                out.push(rest.to_string());
                rest = "";
            }
        }
    }
    out
}

/// `printf '%-Ns'`: left-justified, padded with spaces to N BYTES (bash's
/// printf counts bytes, not characters).
pub fn pad(s: &str, width: usize) -> String {
    if s.len() >= width {
        s.to_string()
    } else {
        format!("{}{}", s, " ".repeat(width - s.len()))
    }
}

/// POSIX `dirname`.
pub fn dirname(p: &str) -> String {
    let t = p.trim_end_matches('/');
    if t.is_empty() {
        return if p.starts_with('/') { "/" } else { "." }.to_string();
    }
    match t.rfind('/') {
        None => ".".to_string(),
        Some(i) => {
            let d = t[..i].trim_end_matches('/');
            if d.is_empty() {
                "/".to_string()
            } else {
                d.to_string()
            }
        }
    }
}

/// POSIX `basename`.
pub fn basename(p: &str) -> String {
    let t = p.trim_end_matches('/');
    if t.is_empty() {
        return if p.starts_with('/') { "/" } else { "" }.to_string();
    }
    match t.rfind('/') {
        None => t.to_string(),
        Some(i) => t[i + 1..].to_string(),
    }
}

fn is_executable_file(p: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    match std::fs::metadata(p) {
        Ok(m) => m.is_file() && m.permissions().mode() & 0o111 != 0,
        Err(_) => false,
    }
}

/// `command -v "$cmd" >/dev/null`: a path with a slash must be an executable
/// file; a bare name must be one in some `$PATH` entry (empty = `.`).
pub fn command_exists(cmd: &str) -> bool {
    if cmd.contains('/') {
        return is_executable_file(Path::new(cmd));
    }
    let path = std::env::var("PATH").unwrap_or_default();
    path.split(':').any(|dir| {
        let dir = if dir.is_empty() { "." } else { dir };
        is_executable_file(&Path::new(dir).join(cmd))
    })
}

/// `find ROOTS -maxdepth 2 -name package.json -not -path '*/node_modules/*'
/// 2>/dev/null | sort`. Like find's default `-P`, symlinks are never
/// followed: a symlinked directory (even a root) is not descended, while a
/// symlink NAMED package.json is listed whatever it points at.
pub fn find_manifests(roots: &[&str]) -> Vec<String> {
    fn visit(dir: &str, depth: usize, out: &mut Vec<String>) {
        let entries = match std::fs::read_dir(dir) {
            Ok(e) => e,
            Err(_) => return,
        };
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            let path = format!("{}/{}", dir, name);
            if name == "package.json" && !path.contains("/node_modules/") {
                out.push(path.clone());
            }
            if depth < 2 {
                if let Ok(ft) = entry.file_type() {
                    if ft.is_dir() {
                        visit(&path, depth + 1, out);
                    }
                }
            }
        }
    }
    let mut out = Vec::new();
    for root in roots {
        let real_dir = std::fs::symlink_metadata(root)
            .map(|m| m.is_dir())
            .unwrap_or(false);
        if basename(root) == "package.json" && !root.contains("/node_modules/") {
            out.push(root.to_string());
        }
        if real_dir {
            visit(root, 1, &mut out);
        }
    }
    out.sort();
    out
}

/// The reason part of an I/O error, as the shell prints it.
pub fn io_reason(e: &std::io::Error) -> String {
    match e.kind() {
        std::io::ErrorKind::NotFound => "No such file or directory".to_string(),
        std::io::ErrorKind::PermissionDenied => "Permission denied".to_string(),
        _ => {
            let s = e.to_string();
            match s.find(" (os error") {
                Some(i) => s[..i].to_string(),
                None => s,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn read_splits_like_bash() {
        assert_eq!(read_fields("a b c", 3), ["a", "b", "c"]);
        assert_eq!(read_fields("  a\tb  c d  ", 3), ["a", "b", "c d"]);
        assert_eq!(read_fields("a", 3), ["a", "", ""]);
        assert_eq!(read_fields("a b\nc d", 3), ["a", "b", ""]);
        assert_eq!(read_fields("", 2), ["", ""]);
    }

    #[test]
    fn pad_counts_bytes() {
        assert_eq!(pad("ab", 4), "ab  ");
        assert_eq!(pad("é", 3), "é ");
        assert_eq!(pad("abcdef", 3), "abcdef");
    }

    #[test]
    fn dir_and_base_names() {
        assert_eq!(dirname("a/b/c"), "a/b");
        assert_eq!(dirname("a"), ".");
        assert_eq!(dirname("/a"), "/");
        assert_eq!(basename("a/b/"), "b");
        assert_eq!(basename("a/b/c"), "c");
    }

    #[test]
    fn finds_like_find() {
        let t = std::env::temp_dir().join(format!("npa-find-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&t);
        for d in ["r/a", "r/b/c", "r/node_modules/x", "other"] {
            std::fs::create_dir_all(t.join(d)).unwrap();
        }
        for f in [
            "r/package.json",
            "r/a/package.json",
            "r/b/c/package.json",
            "r/node_modules/package.json",
            "other/package.json",
        ] {
            std::fs::write(t.join(f), "{}").unwrap();
        }
        std::os::unix::fs::symlink(t.join("other"), t.join("r/link")).unwrap();
        std::os::unix::fs::symlink(t.join("other"), t.join("lroot")).unwrap();
        let cwd = std::env::current_dir().unwrap();
        std::env::set_current_dir(&t).unwrap();
        let got = find_manifests(&["r", "lroot"]);
        std::env::set_current_dir(cwd).unwrap();
        let _ = std::fs::remove_dir_all(&t);
        assert_eq!(got, ["r/a/package.json", "r/package.json"]);
    }
}
