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

//! Handle and per-file pattern validation, as the Go tool's validate.go.

use crate::gostr;
use crate::schema::Config;

fn is_alnum(b: u8) -> bool {
    b.is_ascii_alphanumeric()
}

/// `^[a-zA-Z0-9]([a-zA-Z0-9-]{0,37}[a-zA-Z0-9])?$`
fn is_username(s: &[u8]) -> bool {
    match s.len() {
        0 => false,
        1 => is_alnum(s[0]),
        n if n <= 39 => {
            is_alnum(s[0])
                && is_alnum(s[n - 1])
                && s[1..n - 1].iter().all(|&b| is_alnum(b) || b == b'-')
        }
        _ => false,
    }
}

fn is_slug(s: &[u8]) -> bool {
    !s.is_empty() && s.iter().all(|&b| is_alnum(b) || b == b'_' || b == b'-')
}

/// `^@[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$`
fn is_team(s: &[u8]) -> bool {
    let Some(rest) = s.strip_prefix(b"@") else {
        return false;
    };
    match rest.iter().position(|&b| b == b'/') {
        Some(i) => is_slug(&rest[..i]) && is_slug(&rest[i + 1..]),
        None => false,
    }
}

/// `^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`
fn is_email(s: &[u8]) -> bool {
    let Some(at) = s.iter().position(|&b| b == b'@') else {
        return false;
    };
    let (local, domain) = (&s[..at], &s[at + 1..]);
    if local.is_empty() || !local.iter().all(|&b| is_alnum(b) || b"._%+-".contains(&b)) {
        return false;
    }
    if !domain
        .iter()
        .all(|&b| is_alnum(b) || b == b'.' || b == b'-')
    {
        return false;
    }
    match domain.iter().rposition(|&b| b == b'.') {
        Some(dot) if dot >= 1 => {
            let tld = &domain[dot + 1..];
            tld.len() >= 2 && tld.iter().all(|b| b.is_ascii_alphabetic())
        }
        _ => false,
    }
}

/// Go's `ValidateHandle`.
pub fn validate_handle(handle: &str) -> Result<(), String> {
    let handle = gostr::trim_space(handle);
    if handle.is_empty() {
        return Err("empty handle".to_string());
    }
    let b = handle.as_bytes();
    if is_team(b) || b.strip_prefix(b"@").is_some_and(is_username) || is_email(b) || is_username(b)
    {
        return Ok(());
    }
    Err(format!(
        "invalid handle syntax {} (expected @Org/team or @username)",
        gostr::quote(handle)
    ))
}

/// Go's `ValidateConfig`.
pub fn validate_config(path: &str, cfg: &Config) -> Result<(), String> {
    let approvers = cfg.effective_approvers();
    if approvers.is_empty() && !cfg.options.no_parent_owners {
        return Err(format!(
            "{path}: must declare at least one owner or approver"
        ));
    }
    for a in &approvers {
        validate_handle(a).map_err(|e| format!("{path}: invalid approver {e}"))?;
    }
    for r in &cfg.reviewers {
        validate_handle(r).map_err(|e| format!("{path}: invalid reviewer {e}"))?;
    }
    for pf in &cfg.per_file {
        if pf.pattern.is_empty() {
            return Err(format!("{path}: per_file rule has empty pattern"));
        }
        if glob_match(&pf.pattern, "test.txt").is_err() {
            return Err(format!(
                "{path}: invalid per_file glob pattern {}: syntax error in pattern",
                gostr::quote(&pf.pattern)
            ));
        }
        for a in &pf.approvers {
            validate_handle(a).map_err(|e| format!("{path}: invalid per_file approver {e}"))?;
        }
        for o in &pf.owners {
            validate_handle(o).map_err(|e| format!("{path}: invalid per_file owner {e}"))?;
        }
    }
    Ok(())
}

// ---- Go's filepath.Match, which is how the Go tool vetted a pattern ---------

#[derive(Debug)]
pub struct BadPattern;

fn scan_chunk(pattern: &[u8]) -> (bool, &[u8], &[u8]) {
    let mut p = pattern;
    let mut star = false;
    while let Some((&b'*', rest)) = p.split_first() {
        p = rest;
        star = true;
    }
    let mut inrange = false;
    let mut i = 0;
    while i < p.len() {
        match p[i] {
            b'\\' => {
                if i + 1 < p.len() {
                    i += 1;
                }
            }
            b'[' => inrange = true,
            b']' => inrange = false,
            b'*' if !inrange => break,
            _ => {}
        }
        i += 1;
    }
    (star, &p[..i], &p[i..])
}

fn decode_rune(s: &[u8]) -> (u32, usize) {
    if s.is_empty() {
        return (0xfffd, 0);
    }
    let w = match s[0] {
        0x00..=0x7f => return (s[0] as u32, 1),
        0xc2..=0xdf => 2,
        0xe0..=0xef => 3,
        0xf0..=0xf4 => 4,
        _ => return (0xfffd, 1),
    };
    match std::str::from_utf8(&s[..w.min(s.len())]) {
        Ok(t) => (t.chars().next().map(|c| c as u32).unwrap_or(0xfffd), w),
        Err(_) => (0xfffd, 1),
    }
}

fn get_esc(chunk: &[u8]) -> Result<(u32, &[u8]), BadPattern> {
    if chunk.is_empty() || chunk[0] == b'-' || chunk[0] == b']' {
        return Err(BadPattern);
    }
    let mut c = chunk;
    if c[0] == b'\\' {
        c = &c[1..];
        if c.is_empty() {
            return Err(BadPattern);
        }
    }
    let (r, n) = decode_rune(c);
    if r == 0xfffd && n == 1 {
        return Err(BadPattern);
    }
    let rest = &c[n..];
    if rest.is_empty() {
        return Err(BadPattern);
    }
    Ok((r, rest))
}

fn match_chunk<'a>(chunk: &[u8], s: &'a [u8]) -> Result<Option<&'a [u8]>, BadPattern> {
    let mut chunk = chunk;
    let mut s = s;
    let mut failed = false;
    while !chunk.is_empty() {
        if !failed && s.is_empty() {
            failed = true;
        }
        match chunk[0] {
            b'[' => {
                let mut r = 0;
                if !failed {
                    let (rr, n) = decode_rune(s);
                    r = rr;
                    s = &s[n..];
                }
                chunk = &chunk[1..];
                let mut negated = false;
                if chunk.first() == Some(&b'^') {
                    negated = true;
                    chunk = &chunk[1..];
                }
                let mut matched = false;
                let mut nrange = 0;
                loop {
                    if chunk.first() == Some(&b']') && nrange > 0 {
                        chunk = &chunk[1..];
                        break;
                    }
                    let (lo, rest) = get_esc(chunk)?;
                    chunk = rest;
                    let mut hi = lo;
                    if chunk[0] == b'-' {
                        let (h, rest) = get_esc(&chunk[1..])?;
                        hi = h;
                        chunk = rest;
                    }
                    if lo <= r && r <= hi {
                        matched = true;
                    }
                    nrange += 1;
                }
                if matched == negated {
                    failed = true;
                }
            }
            b'?' => {
                if !failed {
                    if s[0] == b'/' {
                        failed = true;
                    }
                    let (_, n) = decode_rune(s);
                    s = &s[n..];
                }
                chunk = &chunk[1..];
            }
            c => {
                let c = if c == b'\\' {
                    chunk = &chunk[1..];
                    if chunk.is_empty() {
                        return Err(BadPattern);
                    }
                    chunk[0]
                } else {
                    c
                };
                if !failed {
                    if c != s[0] {
                        failed = true;
                    }
                    s = &s[1..];
                }
                chunk = &chunk[1..];
            }
        }
    }
    if failed {
        Ok(None)
    } else {
        Ok(Some(s))
    }
}

/// Go's `filepath.Match` on Unix.
pub fn glob_match(pattern: &str, name: &str) -> Result<bool, BadPattern> {
    let mut pattern = pattern.as_bytes();
    let mut name = name.as_bytes();
    'outer: while !pattern.is_empty() {
        let (star, chunk, rest) = scan_chunk(pattern);
        pattern = rest;
        if star && chunk.is_empty() {
            return Ok(!name.contains(&b'/'));
        }
        let res = match_chunk(chunk, name);
        if let Ok(Some(t)) = res {
            if t.is_empty() || !pattern.is_empty() {
                name = t;
                continue;
            }
        }
        res?;
        if star {
            let mut i = 0;
            while i < name.len() && name[i] != b'/' {
                match match_chunk(chunk, &name[i + 1..]) {
                    Ok(Some(t)) => {
                        if pattern.is_empty() && !t.is_empty() {
                            i += 1;
                            continue;
                        }
                        name = t;
                        continue 'outer;
                    }
                    Ok(None) => {}
                    Err(e) => return Err(e),
                }
                i += 1;
            }
        }
        while !pattern.is_empty() {
            let (_, chunk, rest) = scan_chunk(pattern);
            pattern = rest;
            match_chunk(chunk, b"")?;
        }
        return Ok(false);
    }
    Ok(name.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn handles() {
        for h in [
            "@VitruvianSoftware/platform-team",
            "@VitruvianSoftware/devx-team",
            "@alice",
            "@bob-123",
            "charlie",
            "user@example.com",
        ] {
            assert!(validate_handle(h).is_ok(), "{h}");
        }
        for h in [
            "",
            "@",
            "@/team",
            "@org/",
            "@invalid@user",
            "invalid user with spaces",
            "-a",
            "a-",
            "@a.b",
        ] {
            assert!(validate_handle(h).is_err(), "{h}");
        }
        assert_eq!(
            validate_handle("a b").unwrap_err(),
            "invalid handle syntax \"a b\" (expected @Org/team or @username)"
        );
        assert_eq!(validate_handle(" \t").unwrap_err(), "empty handle");
        assert!(validate_handle(&"a".repeat(39)).is_ok());
        assert!(validate_handle(&"a".repeat(40)).is_err());
    }

    #[test]
    fn glob_matches_go() {
        assert!(glob_match("*.txt", "test.txt").unwrap());
        assert!(!glob_match("*.md", "test.txt").unwrap());
        assert!(glob_match("t?st.[a-z]xt", "test.txt").unwrap());
        assert!(glob_match("[", "test.txt").is_err());
        assert!(glob_match("a[", "test.txt").is_err());
        assert!(glob_match("*.md[", "test.txt").is_err());
        assert!(glob_match("x\\", "test.txt").is_err());
        assert!(glob_match("[]a]", "test.txt").is_err());
        assert!(glob_match("[a-]", "test.txt").is_err());
        assert!(!glob_match("[^a-z]*", "test.txt").unwrap());
        assert!(glob_match("*", "test.txt").unwrap());
        assert!(glob_match("**", "a").unwrap());
    }
}
