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

//! Go's `path/filepath` on Unix: Clean, Join, Dir, Base, Ext and Rel, byte
//! for byte, so paths in messages read the same.

/// `filepath.Clean`.
pub fn clean(path: &str) -> String {
    if path.is_empty() {
        return ".".to_string();
    }
    let p = path.as_bytes();
    let n = p.len();
    let rooted = p[0] == b'/';
    let mut out: Vec<u8> = Vec::with_capacity(n);
    let (mut r, mut dotdot) = (0usize, 0usize);
    if rooted {
        out.push(b'/');
        r = 1;
        dotdot = 1;
    }
    while r < n {
        if p[r] == b'/' || (p[r] == b'.' && (r + 1 == n || p[r + 1] == b'/')) {
            r += 1;
        } else if p[r] == b'.' && p[r + 1] == b'.' && (r + 2 == n || p[r + 2] == b'/') {
            r += 2;
            if out.len() > dotdot {
                out.pop();
                while out.len() > dotdot && out[out.len() - 1] != b'/' {
                    out.pop();
                }
                // Drop the separator before the removed element, as Go's
                // lazybuf does by moving w back onto it.
                if out.len() > dotdot && out[out.len() - 1] == b'/' {
                    out.pop();
                }
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
            while r < n && p[r] != b'/' {
                out.push(p[r]);
                r += 1;
            }
        }
    }
    if out.is_empty() {
        return ".".to_string();
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// `filepath.Join`.
pub fn join(elems: &[&str]) -> String {
    let parts: Vec<&str> = elems.iter().copied().filter(|e| !e.is_empty()).collect();
    if parts.is_empty() {
        return String::new();
    }
    clean(&parts.join("/"))
}

/// `filepath.Dir`.
pub fn dir(path: &str) -> String {
    match path.rfind('/') {
        Some(i) => clean(&path[..=i]),
        None => clean(""),
    }
}

/// `filepath.Base`.
pub fn base(path: &str) -> String {
    if path.is_empty() {
        return ".".to_string();
    }
    let trimmed = path.trim_end_matches('/');
    if trimmed.is_empty() {
        return "/".to_string();
    }
    match trimmed.rfind('/') {
        Some(i) => trimmed[i + 1..].to_string(),
        None => trimmed.to_string(),
    }
}

/// `filepath.Ext`.
pub fn ext(path: &str) -> &str {
    let b = path.as_bytes();
    let mut i = b.len();
    while i > 0 && b[i - 1] != b'/' {
        if b[i - 1] == b'.' {
            return &path[i - 1..];
        }
        i -= 1;
    }
    ""
}

/// `filepath.Rel`.
pub fn rel(basepath: &str, targpath: &str) -> Result<String, String> {
    let mut base = clean(basepath);
    let targ = clean(targpath);
    if targ == base {
        return Ok(".".to_string());
    }
    if base == "." {
        base = String::new();
    }
    let cant = || Err(format!("Rel: can't make {targpath} relative to {basepath}"));
    if base.starts_with('/') != targ.starts_with('/') {
        return cant();
    }
    let (b, t) = (base.as_bytes(), targ.as_bytes());
    let (bl, tl) = (b.len(), t.len());
    let (mut b0, mut bi, mut t0, mut ti) = (0, 0, 0, 0);
    loop {
        while bi < bl && b[bi] != b'/' {
            bi += 1;
        }
        while ti < tl && t[ti] != b'/' {
            ti += 1;
        }
        if t[t0..ti] != b[b0..bi] {
            break;
        }
        if bi < bl {
            bi += 1;
        }
        if ti < tl {
            ti += 1;
        }
        b0 = bi;
        t0 = ti;
        if b0 >= bl && t0 >= tl {
            break;
        }
    }
    if &b[b0..bi] == b".." {
        return cant();
    }
    if b0 != bl {
        let seps = b[b0..bl].iter().filter(|&&c| c == b'/').count();
        let mut out = String::from("..");
        for _ in 0..seps {
            out.push_str("/..");
        }
        if t0 != tl {
            out.push('/');
            out.push_str(&targ[t0..]);
        }
        return Ok(out);
    }
    Ok(targ[t0..].to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clean_matches_go() {
        for (i, o) in [
            ("", "."),
            ("a/b/../c", "a/c"),
            ("/a/../../b", "/b"),
            ("../../a", "../../a"),
            ("a/../..", ".."),
            ("./a//b/", "a/b"),
            ("/", "/"),
            ("abc/def/../../..", ".."),
            ("/abc/def/../..", "/"),
        ] {
            assert_eq!(clean(i), o, "clean({i:?})");
        }
    }

    #[test]
    fn dir_base_ext_rel() {
        assert_eq!(dir("a/b/c"), "a/b");
        assert_eq!(dir("c"), ".");
        assert_eq!(dir("/c"), "/");
        assert_eq!(base("a/b/"), "b");
        assert_eq!(ext("a/b.tar.gz"), ".gz");
        assert_eq!(ext("a.b/c"), "");
        assert_eq!(ext(".bazelrc"), ".bazelrc");
        assert_eq!(rel("/x/y", "/x/y/a/BUILD").unwrap(), "a/BUILD");
        assert_eq!(rel("/x/y/", "/x/y/BUILD").unwrap(), "BUILD");
        assert_eq!(rel(".", "a/BUILD").unwrap(), "a/BUILD");
        assert_eq!(rel("/a/b", "/a/c").unwrap(), "../c");
        assert!(rel("a", "/a").is_err());
        assert_eq!(join(&["/r", "", "a", "BUILD"]), "/r/a/BUILD");
        assert_eq!(join(&["", ""]), "");
    }
}
