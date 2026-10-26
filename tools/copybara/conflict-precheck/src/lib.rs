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

//! conflict-precheck, the Rust port of main.go: refuse a Copybara sync when
//! the peer repo holds a genuine change the sync would overwrite.
//!
//!   conflict-precheck <export|import> <component> <monorepo_dir> <standalone_dir> [standalone_only...]
//!
//! Exit 0 when the sync is safe (or there is no baseline to judge from), 1
//! when an un-synced genuine peer commit exists, 2 on a usage error. Output,
//! git invocations and exit codes are the Go tool's, byte for byte; arguments
//! are handled as raw bytes, as Go strings are.

use std::io::Write;
use std::process::Stdio;

pub mod goexec;
mod unicode_tables;

pub const EXPORT_LABEL: &[u8] = b"MONOREPO_REV_ID";

/// Go's strings.ToUpper: ASCII fast path, otherwise unicode.ToUpper per rune
/// with invalid UTF-8 bytes becoming U+FFFD (strings.Map's behaviour).
pub fn to_upper(s: &[u8]) -> Vec<u8> {
    if s.is_ascii() {
        return s.to_ascii_uppercase();
    }
    let mut out = Vec::with_capacity(s.len());
    let mut i = 0;
    while i < s.len() {
        let (r, w) = decode_rune(&s[i..]);
        let u = match r {
            Some(c) => upper_rune(c),
            None => '\u{FFFD}',
        };
        let mut buf = [0u8; 4];
        out.extend_from_slice(u.encode_utf8(&mut buf).as_bytes());
        i += w;
    }
    out
}

fn upper_rune(c: char) -> char {
    let cp = c as u32;
    match unicode_tables::TO_UPPER.binary_search_by(|&(from, _)| from.cmp(&cp)) {
        Ok(i) => char::from_u32(unicode_tables::TO_UPPER[i].1).unwrap_or(c),
        Err(_) => c,
    }
}

/// utf8.DecodeRune: the rune (None for an invalid encoding) and its width.
pub fn decode_rune(s: &[u8]) -> (Option<char>, usize) {
    let b0 = s[0];
    if b0 < 0x80 {
        return (Some(b0 as char), 1);
    }
    let (n, min, init) = match b0 {
        0xC2..=0xDF => (2, 0x80, (b0 & 0x1F) as u32),
        0xE0..=0xEF => (3, 0x800, (b0 & 0x0F) as u32),
        0xF0..=0xF4 => (4, 0x10000, (b0 & 0x07) as u32),
        _ => return (None, 1),
    };
    if s.len() < n {
        return (None, 1);
    }
    let mut cp = init;
    for &b in &s[1..n] {
        if b & 0xC0 != 0x80 {
            return (None, 1);
        }
        cp = (cp << 6) | (b & 0x3F) as u32;
    }
    if cp < min || cp > 0x10FFFF || (0xD800..=0xDFFF).contains(&cp) {
        return (None, 1);
    }
    (char::from_u32(cp), n)
}

/// unicode.IsSpace.
fn is_space(c: char) -> bool {
    matches!(
        c,
        '\t' | '\n'
            | '\u{0B}'
            | '\u{0C}'
            | '\r'
            | ' '
            | '\u{85}'
            | '\u{A0}'
            | '\u{1680}'
            | '\u{2000}'
            ..='\u{200A}' | '\u{2028}' | '\u{2029}' | '\u{202F}' | '\u{205F}' | '\u{3000}'
    )
}

/// strings.TrimSpace on bytes.
pub fn trim_space(s: &[u8]) -> &[u8] {
    let mut start = 0;
    while start < s.len() {
        let (r, w) = decode_rune(&s[start..]);
        match r {
            Some(c) if is_space(c) => start += w,
            _ => break,
        }
    }
    let mut end = s.len();
    while end > start {
        // Find the start of the last rune in s[start..end].
        let mut k = end - 1;
        while k > start && end - k < 4 && s[k] & 0xC0 == 0x80 {
            k -= 1;
        }
        let (r, w) = decode_rune(&s[k..end]);
        let (r, w) = if k + w == end { (r, w) } else { (None, 1) };
        match r {
            Some(c) if is_space(c) => end -= w,
            _ => break,
        }
    }
    &s[start..end]
}

/// "mcp-slack" -> "MCP_SLACK_REV_ID", "devx" -> "DEVX_REV_ID".
pub fn import_label(component: &[u8]) -> Vec<u8> {
    let replaced: Vec<u8> = component
        .iter()
        .map(|&b| if b == b'-' { b'_' } else { b })
        .collect();
    let mut s = to_upper(&replaced);
    s.extend_from_slice(b"_REV_ID");
    s
}

/// exec.Command("git", args...).Output(): stdout when git exits 0, None when
/// it cannot be run or fails (its stderr is captured and dropped, as Go does).
fn git_output(args: &[Vec<u8>]) -> Option<Vec<u8>> {
    let mut cmd = goexec::command(b"git", args).ok()?;
    let out = cmd
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .ok()?;
    if out.status.success() {
        Some(out.stdout)
    } else {
        None
    }
}

fn arg(parts: &[&[u8]]) -> Vec<u8> {
    parts.concat()
}

/// The first `<label>: <sha>` (7–40 lowercase hex) at a line start in the
/// newest commit message that mentions `<label>:`, or empty.
pub fn latest_rev(repo_dir: &[u8], label: &[u8]) -> Vec<u8> {
    let args = vec![
        b"-C".to_vec(),
        repo_dir.to_vec(),
        b"log".to_vec(),
        b"-1".to_vec(),
        arg(&[b"--grep=", label, b":"]),
        b"--format=%B".to_vec(),
    ];
    match git_output(&args) {
        Some(out) => find_rev(&out, label),
        None => Vec::new(),
    }
}

/// `(?m)^<label>: ([0-9a-f]{7,40})`, leftmost match, submatch 1.
pub fn find_rev(text: &[u8], label: &[u8]) -> Vec<u8> {
    let mut prefix = label.to_vec();
    prefix.extend_from_slice(b": ");
    let mut line_start = 0;
    loop {
        if text[line_start..].starts_with(&prefix) {
            let rest = &text[line_start + prefix.len()..];
            let n = rest
                .iter()
                .take(40)
                .take_while(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(b))
                .count();
            if n >= 7 {
                return rest[..n].to_vec();
            }
        }
        match text[line_start..].iter().position(|&b| b == b'\n') {
            Some(p) => line_start += p + 1,
            None => return Vec::new(),
        }
    }
}

/// One-line log (`  %h %s`) of non-merge commits in rev_range that do not
/// carry `<peer_label>:`, limited to pathspecs; trimmed, empty if none.
pub fn genuine_commits(
    repo_dir: &[u8],
    rev_range: &[u8],
    peer_label: &[u8],
    pathspecs: &[Vec<u8>],
) -> Vec<u8> {
    let mut args = vec![
        b"-C".to_vec(),
        repo_dir.to_vec(),
        b"log".to_vec(),
        rev_range.to_vec(),
        b"--no-merges".to_vec(),
        b"--invert-grep".to_vec(),
        arg(&[b"--grep=", peer_label, b":"]),
        b"--format=  %h %s".to_vec(),
        b"--".to_vec(),
    ];
    args.extend(pathspecs.iter().cloned());
    match git_output(&args) {
        Some(out) => trim_space(&out).to_vec(),
        None => Vec::new(),
    }
}

/// Excludes for the monorepo-only Bazel BUILD files under a component.
pub fn monorepo_only_excludes(c: &[u8]) -> Vec<Vec<u8>> {
    vec![
        arg(&[b":(exclude,glob)", c, b"/**/BUILD"]),
        arg(&[b":(exclude,glob)", c, b"/**/BUILD.bazel"]),
        arg(&[b":(exclude)", c, b"/BUILD"]),
        arg(&[b":(exclude)", c, b"/BUILD.bazel"]),
    ]
}

/// Whether `<sha>^{commit}` exists in repo_dir (`git cat-file -e`, stdio on
/// /dev/null as exec.Cmd.Run leaves it).
pub fn cat_file_reachable(repo_dir: &[u8], sha: &[u8]) -> bool {
    let args = vec![
        b"-C".to_vec(),
        repo_dir.to_vec(),
        b"cat-file".to_vec(),
        b"-e".to_vec(),
        arg(&[sha, b"^{commit}"]),
    ];
    let mut cmd = match goexec::command(b"git", &args) {
        Ok(c) => c,
        Err(_) => return false,
    };
    cmd.stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn put(w: &mut dyn Write, parts: &[&[u8]]) {
    for p in parts {
        let _ = w.write_all(p);
    }
    let _ = w.flush();
}

/// The whole tool. args: [direction, component, monorepo_dir, standalone_dir,
/// standalone_only...]. Returns the exit code.
pub fn run(args: &[Vec<u8>], out: &mut dyn Write, err: &mut dyn Write) -> i32 {
    if args.len() < 4 {
        put(err, &[b"usage: conflict-precheck <export|import> <component> <monorepo_dir> <standalone_dir> [standalone_only...]\n"]);
        return 2;
    }
    let direction = &args[0][..];
    let component = &args[1][..];
    let monorepo_dir = &args[2][..];
    let standalone_dir = &args[3][..];
    let standalone_only = &args[4..];

    let import_lbl = import_label(component);

    let (base, pending, what): (Vec<u8>, Vec<u8>, Vec<u8>) = match direction {
        b"export" => {
            let base = latest_rev(monorepo_dir, &import_lbl);
            if base.is_empty() {
                put(
                    out,
                    &["[precheck/export] no import baseline yet — skipping\n".as_bytes()],
                );
                return 0;
            }
            if !cat_file_reachable(standalone_dir, &base) {
                put(
                    out,
                    &[
                        b"::warning::[precheck/export] import baseline ",
                        &base,
                        " not reachable in standalone — skipping\n".as_bytes(),
                    ],
                );
                return 0;
            }
            let mut scan = vec![b".".to_vec()];
            for p in standalone_only {
                scan.push(arg(&[b":(exclude)", p]));
            }
            let pending = genuine_commits(
                standalone_dir,
                &arg(&[&base, b"..HEAD"]),
                EXPORT_LABEL,
                &scan,
            );
            (
                base,
                pending,
                b"standalone change not yet imported into the monorepo".to_vec(),
            )
        }
        b"import" => {
            let base = latest_rev(standalone_dir, EXPORT_LABEL);
            if base.is_empty() {
                put(
                    out,
                    &["[precheck/import] no export baseline yet — skipping\n".as_bytes()],
                );
                return 0;
            }
            if !cat_file_reachable(monorepo_dir, &base) {
                put(
                    out,
                    &[
                        b"::warning::[precheck/import] export baseline ",
                        &base,
                        " not reachable in monorepo — skipping\n".as_bytes(),
                    ],
                );
                return 0;
            }
            let mut pathspecs = vec![arg(&[component, b"/"])];
            pathspecs.extend(monorepo_only_excludes(component));
            let pending = genuine_commits(
                monorepo_dir,
                &arg(&[&base, b"..HEAD"]),
                &import_lbl,
                &pathspecs,
            );
            (
                base,
                pending,
                arg(&[
                    b"monorepo ",
                    component,
                    b"/ change not yet exported to the standalone",
                ]),
            )
        }
        _ => {
            put(
                err,
                &[b"unknown direction: ", direction, b" (use export|import)\n"],
            );
            return 2;
        }
    };

    if !pending.is_empty() {
        put(
            out,
            &[
                b"::error title=Copybara conflict pre-check::Refusing to ",
                direction,
                b" ",
                component,
                " — the peer repo has an un-synced ".as_bytes(),
                &what,
                b". Syncing now would overwrite it (concurrent conflicting edit). Reconcile by hand, then re-run.\n",
            ],
        );
        put(out, &[b"Offending un-synced commit(s):\n"]);
        put(out, &[&pending, b"\n"]);
        return 1;
    }
    put(
        out,
        &[
            b"[precheck/",
            direction,
            b"] OK (",
            component,
            ") — no un-synced genuine peer changes (baseline ".as_bytes(),
            &base,
            b").\n",
        ],
    );
    0
}

#[cfg(test)]
mod lib_test;
