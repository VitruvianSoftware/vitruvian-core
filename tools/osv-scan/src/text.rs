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

//! The text plumbing the script does with coreutils, on bytes: `$(...)`'s
//! trailing-newline strip, `tail -n`, `sed 's/^/     /'`, `grep -i[n]E` of
//! fixed alternations, `cut -c4-`, `sort` and `comm -13` (byte order, as in
//! the C locale the gate runs under), and the DEP_MANIFEST_RE match.

/// `$(...)`: drop every trailing newline.
pub fn strip_nl(b: &[u8]) -> Vec<u8> {
    let mut v = b.to_vec();
    while v.last() == Some(&b'\n') {
        v.pop();
    }
    v
}

/// The lines of a file as line-oriented tools read it: a final newline
/// terminates the last line rather than starting an empty one.
pub fn lines(b: &[u8]) -> Vec<&[u8]> {
    if b.is_empty() {
        return Vec::new();
    }
    let body = b.strip_suffix(b"\n").unwrap_or(b);
    body.split(|c| *c == b'\n').collect()
}

/// Join lines, each newline-terminated (what a tool writes for them).
pub fn unlines(ls: &[&[u8]]) -> Vec<u8> {
    let mut out = Vec::new();
    for l in ls {
        out.extend_from_slice(l);
        out.push(b'\n');
    }
    out
}

/// `tail -n N`'s output for a file's contents.
pub fn tail(b: &[u8], n: usize) -> Vec<u8> {
    let ls = lines(b);
    let start = ls.len().saturating_sub(n);
    unlines(&ls[start..])
}

/// `sed 's/^/P/'` over a stream.
pub fn prefix_stream(b: &[u8], prefix: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    let ls = lines(b);
    for (i, l) in ls.iter().enumerate() {
        out.extend_from_slice(prefix);
        out.extend_from_slice(l);
        if i + 1 < ls.len() || b.ends_with(b"\n") {
            out.push(b'\n');
        }
    }
    out
}

/// `$(printf '%s\n' "$X" | sed 's/^/     /')`.
pub fn indent_var(x: &[u8]) -> Vec<u8> {
    let mut s = x.to_vec();
    s.push(b'\n');
    strip_nl(&prefix_stream(&s, b"     "))
}

/// Case-insensitive (ASCII) substring test for any of `pats`, line by line,
/// which for newline-free literals is the same as over the whole text.
pub fn contains_any_ci(hay: &[u8], pats: &[&str]) -> bool {
    let low = hay.to_ascii_lowercase();
    pats.iter().any(|p| {
        let p = p.as_bytes();
        low.windows(p.len()).any(|w| w == p)
    })
}

/// `grep -inE 'a|b|...'`: matching lines as `N:line`, newline-terminated.
pub fn grep_n_ci(b: &[u8], pats: &[&str]) -> Vec<u8> {
    let mut out = Vec::new();
    for (i, l) in lines(b).iter().enumerate() {
        if contains_any_ci(l, pats) {
            out.extend_from_slice(format!("{}:", i + 1).as_bytes());
            out.extend_from_slice(l);
            out.push(b'\n');
        }
    }
    out
}

/// `cut -c4- | sort`.
pub fn cut4_sort(b: &[u8]) -> Vec<u8> {
    let mut ls: Vec<&[u8]> = lines(b)
        .into_iter()
        .map(|l| if l.len() >= 3 { &l[3..] } else { &l[..0] })
        .collect();
    ls.sort();
    unlines(&ls)
}

/// `comm -13 <(printf '%s\n' "$A") <(printf '%s\n' "$B")`: lines only in B.
pub fn comm_13(a: &[u8], b: &[u8]) -> Vec<u8> {
    let mut av = a.to_vec();
    av.push(b'\n');
    let mut bv = b.to_vec();
    bv.push(b'\n');
    let (x, y) = (lines(&av), lines(&bv));
    let (mut i, mut j) = (0, 0);
    let mut out: Vec<&[u8]> = Vec::new();
    while j < y.len() {
        if i >= x.len() {
            out.push(y[j]);
            j += 1;
            continue;
        }
        match x[i].cmp(y[j]) {
            std::cmp::Ordering::Less => i += 1,
            std::cmp::Ordering::Greater => {
                out.push(y[j]);
                j += 1;
            }
            std::cmp::Ordering::Equal => {
                i += 1;
                j += 1;
            }
        }
    }
    unlines(&out)
}

const MANIFESTS: &[&[u8]] = &[
    b"go.mod",
    b"go.sum",
    b"package.json",
    b"package-lock.json",
    b"pnpm-lock.yaml",
    b"yarn.lock",
    b"uv.lock",
    b"poetry.lock",
    b"Pipfile.lock",
    b"pyproject.toml",
    b"Cargo.toml",
    b"Cargo.lock",
    b"Gemfile",
    b"Gemfile.lock",
    b"composer.json",
    b"composer.lock",
    b"osv-scanner.toml",
];

/// One line against DEP_MANIFEST_RE, `(^|/)(go\.mod|...|requirements[^/]*\.txt|...)$`.
/// No alternative contains a `/`, so it matches exactly when the text after
/// the last `/` (the whole line, if there is none) is one of the names.
pub fn is_dep_manifest(line: &[u8]) -> bool {
    let last = match line.iter().rposition(|c| *c == b'/') {
        Some(i) => &line[i + 1..],
        None => line,
    };
    MANIFESTS.contains(&last)
        || (last.len() >= b"requirements.txt".len()
            && last.starts_with(b"requirements")
            && last.ends_with(b".txt"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn manifests() {
        for yes in [
            "go.mod",
            "a/b/go.sum",
            "requirements.txt",
            "x/requirements-dev.txt",
            "osv-scanner.toml",
            "Gemfile",
        ] {
            assert!(is_dep_manifest(yes.as_bytes()), "{yes}");
        }
        for no in [
            "go.mod.bak",
            "xgo.mod",
            "requirements.txtx",
            "a/requirementstxt",
            "\"a/\\303/go.mod\"",
            "gemfile",
            "",
        ] {
            assert!(!is_dep_manifest(no.as_bytes()), "{no}");
        }
    }

    #[test]
    fn comm_and_cut() {
        assert_eq!(comm_13(b"", b""), b"");
        assert_eq!(comm_13(b"", b"a"), b"a\n");
        assert_eq!(comm_13(b"a\nc", b"a\nb\nc\nd"), b"b\nd\n");
        assert_eq!(cut4_sort(b" M z\n?? a\nab\n"), b"\na\nz\n");
    }

    #[test]
    fn tails_and_indents() {
        assert_eq!(tail(b"1\n2\n3\n", 2), b"2\n3\n");
        assert_eq!(tail(b"1\n2\n3", 2), b"2\n3\n");
        assert_eq!(tail(b"", 2), b"");
        assert_eq!(strip_nl(&prefix_stream(b"a\n\n", b"> ")), b"> a\n> ");
        assert_eq!(indent_var(b""), b"     ");
        assert_eq!(
            grep_n_ci(b"ok\nAn ERROR\nfine\nFatal", &["error", "fatal"]),
            b"2:An ERROR\n4:Fatal\n"
        );
    }
}
