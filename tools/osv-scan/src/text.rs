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
//! the C locale the gate runs under), and which files are dependency
//! manifests.

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

/// Parse `git status --porcelain -z` output into sorted path entries (preserving
/// `orig -> new` for renames/copies so output matches `cut -c4-`).
pub fn parse_porcelain_z_paths(b: &[u8]) -> Vec<Vec<u8>> {
    let mut out = Vec::new();
    let mut parts = b.split(|c| *c == b'\0');
    while let Some(entry) = parts.next() {
        if entry.is_empty() {
            continue;
        }
        if entry.len() < 3 {
            out.push(Vec::new());
            continue;
        }
        let (x, y) = (entry[0], entry[1]);
        let path = &entry[3..];
        if matches!(x, b'R' | b'C') || matches!(y, b'R' | b'C') {
            let orig = parts.next().unwrap_or(b"");
            let mut combined = Vec::with_capacity(orig.len() + 4 + path.len());
            combined.extend_from_slice(orig);
            combined.extend_from_slice(b" -> ");
            combined.extend_from_slice(path);
            out.push(combined);
        } else {
            out.push(path.to_vec());
        }
    }
    out.sort();
    out
}

/// `comm -13` over sorted raw byte entries (never splits on newlines).
pub fn comm_13_entries<'a>(a: &'a [Vec<u8>], b: &'a [Vec<u8>]) -> Vec<&'a [u8]> {
    let (mut i, mut j) = (0, 0);
    let mut out = Vec::new();
    while j < b.len() {
        if i >= a.len() {
            out.push(b[j].as_slice());
            j += 1;
            continue;
        }
        match a[i].cmp(&b[j]) {
            std::cmp::Ordering::Less => i += 1,
            std::cmp::Ordering::Greater => {
                out.push(b[j].as_slice());
                j += 1;
            }
            std::cmp::Ordering::Equal => {
                i += 1;
                j += 1;
            }
        }
    }
    out
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

/// Dependency manifests and lockfiles osv-scanner reads, by file name. Every
/// name added since the original list was checked by scanning a sample of it
/// with the pinned osv-scanner (2.6.0) and seeing it reported as a source.
/// A change to one of these is a dependency change, so its advisories block.
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
    // Dart, Swift, Maven, Gradle, NuGet, Hex, CRAN, Conan, PyPI, Bun, Hackage.
    b"pubspec.lock",
    b"Package.resolved",
    b"pom.xml",
    b"gradle.lockfile",
    b"buildscript-gradle.lockfile",
    b"verification-metadata.xml",
    b"packages.lock.json",
    b"packages.config",
    b"mix.lock",
    b"renv.lock",
    b"conan.lock",
    b"pdm.lock",
    b"pylock.toml",
    b"bun.lock",
    b"stack.yaml.lock",
    b"cabal.project.freeze",
];

/// Manifests matched by the end of their name: .NET project files and
/// dependency manifests (`App.csproj`, `App.deps.json`).
const MANIFEST_SUFFIXES: &[&[u8]] = &[b".csproj", b".deps.json"];

/// Manifests matched by both ends of their name, `<prefix>*<suffix>`:
/// `requirements-dev.txt`, and PEP 751's named lockfiles (`pylock.dev.toml`).
const MANIFEST_PATTERNS: &[(&[u8], &[u8])] = &[(b"requirements", b".txt"), (b"pylock.", b".toml")];

/// Dependency lockfiles the pinned osv-scanner cannot check against advisories,
/// each with why (verified the same way as MANIFESTS). A scan of a tree that
/// holds one can only pass for its dependencies, so the gate fails instead.
pub const UNSCANNABLE: &[(&[u8], &str)] = &[
    (
        b"Podfile.lock",
        "CocoaPods: osv-scanner parses it, but OSV has no CocoaPods ecosystem, so every pod is dropped unchecked",
    ),
    (b"Cartfile.resolved", "Carthage: osv-scanner does not read it"),
    (b"deno.lock", "Deno: osv-scanner does not read it"),
    (b"rebar.lock", "Erlang (rebar3): osv-scanner does not read it"),
    (b"shard.lock", "Crystal: osv-scanner does not read it"),
];

/// The text after the last `/`, or the whole line if there is none.
fn file_name(line: &[u8]) -> &[u8] {
    match line.iter().rposition(|c| *c == b'/') {
        Some(i) => &line[i + 1..],
        None => line,
    }
}

/// Whether a repo-relative path names a dependency manifest. Matching is on
/// the file name alone, so it holds at any depth.
pub fn is_dep_manifest(line: &[u8]) -> bool {
    let last = file_name(line);
    MANIFESTS.contains(&last)
        || MANIFEST_SUFFIXES.iter().any(|s| last.ends_with(s))
        || MANIFEST_PATTERNS.iter().any(|(pre, suf)| {
            last.len() >= pre.len() + suf.len() && last.starts_with(pre) && last.ends_with(suf)
        })
}

/// Why osv-scanner cannot check the dependency lockfile a path names, or None
/// when it is not one of UNSCANNABLE.
pub fn unscannable_reason(line: &[u8]) -> Option<&'static str> {
    let last = file_name(line);
    UNSCANNABLE
        .iter()
        .find(|(n, _)| *n == last)
        .map(|(_, why)| *why)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// ci.yaml skips the required `osv-scan` on a PR whose files match none of
    /// its `osvscan` globs, because such a scan can only report. That holds
    /// only while the filter lists every name is_dep_manifest knows: a manifest
    /// missing there would let a PR add an advisory with the check skipped. The
    /// UNSCANNABLE names must be there too, or the gate that refuses them
    /// would never run on the PR that adds one.
    #[test]
    fn ci_yaml_osv_filter_lists_every_manifest() {
        let ci = std::fs::read_to_string(".github/workflows/ci.yaml").expect("ci.yaml in runfiles");
        let lines: Vec<&str> = ci.lines().collect();
        let start = lines
            .iter()
            .position(|l| l.trim_end() == "            osvscan:")
            .expect("ci.yaml has no `osvscan` filter");
        let globs: Vec<String> = lines[start + 1..]
            .iter()
            .map(|l| l.trim())
            .filter(|l| !l.starts_with('#'))
            .take_while(|l| l.starts_with("- "))
            .map(|l| l[2..].trim_matches('\'').to_string())
            .collect();
        let name = |b: &[u8]| String::from_utf8_lossy(b).into_owned();
        let want = MANIFESTS
            .iter()
            .chain(UNSCANNABLE.iter().map(|(n, _)| n))
            .map(|m| format!("**/{}", name(m)))
            .chain(MANIFEST_SUFFIXES.iter().map(|s| format!("**/*{}", name(s))))
            .chain(
                MANIFEST_PATTERNS
                    .iter()
                    .map(|(p, s)| format!("**/{}*{}", name(p), name(s))),
            );
        for want in want {
            assert!(
                globs.contains(&want),
                "ci.yaml osvscan filter is missing {want:?}: {globs:?}"
            );
        }
        assert!(
            globs.iter().any(|g| g == "tools/osv-scan/**"),
            "the scanner itself: {globs:?}"
        );
    }

    #[test]
    fn manifests() {
        for yes in [
            "go.mod",
            "a/b/go.sum",
            "requirements.txt",
            "x/requirements-dev.txt",
            "osv-scanner.toml",
            "Gemfile",
            "app/pubspec.lock",
            "ios/Package.resolved",
            "java/pom.xml",
            "android/app/gradle.lockfile",
            "gradle/verification-metadata.xml",
            "src/App.csproj",
            "bin/App.deps.json",
            "pylock.toml",
            "py/pylock.dev.toml",
            "bun.lock",
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
            "pom.xml.orig",
            "App.csproj.user",
            "pylock.tom",
            "a/pylock.toml/README",
            "Podfile.lock",
        ] {
            assert!(!is_dep_manifest(no.as_bytes()), "{no}");
        }
    }

    #[test]
    fn unscannable() {
        assert!(unscannable_reason(b"ios/Podfile.lock")
            .unwrap()
            .contains("CocoaPods"));
        assert!(unscannable_reason(b"deno.lock").is_some());
        for no in ["Podfile", "Podfile.lock.bak", "go.mod", "pubspec.lock", ""] {
            assert_eq!(unscannable_reason(no.as_bytes()), None, "{no}");
        }
        for (n, _) in UNSCANNABLE {
            assert!(!is_dep_manifest(n), "a name is scannable or not, not both");
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
    fn porcelain_z_and_comm_entries() {
        let z = b" M caf\xc3\xa9/go.mod\0?? nl\ndir/go.mod\0R  new.mod\0old.mod\0";
        let got = parse_porcelain_z_paths(z);
        assert_eq!(
            got,
            vec![
                b"caf\xc3\xa9/go.mod".to_vec(),
                b"nl\ndir/go.mod".to_vec(),
                b"old.mod -> new.mod".to_vec(),
            ]
        );
        let before = vec![b"caf\xc3\xa9/go.mod".to_vec()];
        assert_eq!(
            comm_13_entries(&before, &got),
            vec![&b"nl\ndir/go.mod"[..], &b"old.mod -> new.mod"[..],]
        );
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
