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

//! //tools/ci:require_pinned_actions: every action from outside this repo is
//! pinned to a full commit SHA (with the version in a trailing comment, which
//! Dependabot keeps in step). A tag can be moved to different code after
//! review; a commit cannot. Local `./` actions and reusable workflows are
//! exempt. The devx scaffold templates are checked too: Dependabot cannot see
//! a `.tmpl`, and every repo devx creates starts from these pins.
//!
//! Run from the repository root. Both the required `actionlint` check
//! (.github/workflows/actionlint.yaml) and `bazel run //tools/ci:actionlint`
//! run this, so the two cannot disagree. Exit 0 clean, 1 an unpinned action.
//!
//! Standard library only, one file, ON PURPOSE: actionlint.yaml has no Bazel
//! and builds this with
//!   rustc --edition 2021 -O tools/ci/src/require_pinned_actions/main.rs
//! (//tools/ci:require_pinned_actions_test runs that exact line). Adding a
//! dependency would break that job, not the Bazel build.
//!
//! Ported from require-pinned-actions.sh, which was
//!   grep -rnE '^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*[^.#[:space:]]' DIRS |
//!     grep -vE '@[0-9a-f]{40}([[:space:]]|$)'
//! The match rules below are those two regexes, by hand. One difference: grep
//! -r lists files in directory order; this lists them sorted, so the output is
//! stable.

use std::io::Write;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};

const DIRS: &[&str] = &[
    ".github/workflows",
    ".github/actions",
    "apps/cli/devx/internal/scaffold/templates",
];

/// POSIX `[[:space:]]`.
fn is_space(b: u8) -> bool {
    matches!(b, b' ' | b'\t' | b'\n' | 0x0b | 0x0c | b'\r')
}

/// `^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*[^.#[:space:]]`
fn is_uses_line(line: &[u8]) -> bool {
    let skip = |mut i: usize| {
        while i < line.len() && is_space(line[i]) {
            i += 1;
        }
        i
    };
    let starts = |i: usize| {
        let i = skip(i);
        if !line[i..].starts_with(b"uses:") {
            return false;
        }
        let j = skip(i + 5);
        j < line.len() && !matches!(line[j], b'.' | b'#') && !is_space(line[j])
    };
    // Regex alternation: with or without the `-` (the optional group).
    let i = skip(0);
    starts(i) || (i < line.len() && line[i] == b'-' && starts(i + 1))
}

/// `@[0-9a-f]{40}([[:space:]]|$)` anywhere in `text`.
fn has_sha_pin(text: &[u8]) -> bool {
    (0..text.len()).any(|at| {
        text[at] == b'@'
            && text.len() >= at + 41
            && text[at + 1..at + 41]
                .iter()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(b))
            && (text.len() == at + 41 || is_space(text[at + 41]))
    })
}

/// Regular files under `dir`, sorted, not following symlinked directories
/// (grep -r does not either).
fn walk(dir: &Path, files: &mut Vec<PathBuf>) {
    let Ok(rd) = std::fs::read_dir(dir) else {
        return;
    };
    let mut entries: Vec<PathBuf> = rd.filter_map(|e| e.ok().map(|e| e.path())).collect();
    entries.sort();
    for p in entries {
        let Ok(md) = std::fs::symlink_metadata(&p) else {
            continue;
        };
        if md.is_dir() {
            walk(&p, files);
        } else if md.is_file() {
            files.push(p);
        }
    }
}

/// The `path:line:content` lines (grep -rn's format) that name an unpinned
/// outside action, across every directory in `DIRS` under `root`.
pub fn unpinned(root: &Path) -> Option<Vec<Vec<u8>>> {
    let dirs: Vec<&str> = DIRS
        .iter()
        .copied()
        .filter(|d| root.join(d).is_dir())
        .collect();
    if dirs.is_empty() {
        return None;
    }
    let mut found = Vec::new();
    for d in dirs {
        let mut files = Vec::new();
        walk(&root.join(d), &mut files);
        for f in files {
            let Ok(data) = std::fs::read(&f) else {
                continue;
            };
            // grep reports a match in a binary file without printing it; no
            // workflow or template is binary, so skip such files outright.
            if data.contains(&0) {
                continue;
            }
            let shown = Path::new(d).join(f.strip_prefix(root.join(d)).unwrap());
            let mut body: &[u8] = &data;
            if body.last() == Some(&b'\n') {
                body = &body[..body.len() - 1];
            }
            for (n, line) in body.split(|&b| b == b'\n').enumerate() {
                if !is_uses_line(line) {
                    continue;
                }
                let mut out = shown.as_os_str().as_bytes().to_vec();
                out.extend_from_slice(format!(":{}:", n + 1).as_bytes());
                out.extend_from_slice(line);
                // The second grep sees the whole `path:line:content` line.
                if !has_sha_pin(&out) {
                    found.push(out);
                }
            }
        }
    }
    Some(found)
}

fn main() {
    let Some(found) = unpinned(Path::new(".")) else {
        std::process::exit(0);
    };
    if found.is_empty() {
        std::process::exit(0);
    }
    let mut so = std::io::stdout().lock();
    let _ = so.write_all(
        b"::error::Actions must be pinned to a full commit SHA, e.g. 'owner/action@<40-hex sha> # v1.2.3':\n",
    );
    for l in &found {
        let _ = so.write_all(l);
        let _ = so.write_all(b"\n");
    }
    let _ = so.flush();
    std::process::exit(1);
}
