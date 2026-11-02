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

//! changelog-summary — render a component's release notes into the GitHub
//! Actions run page (a job summary).

use shell_compat::{basename, cat, dirname, env, err, is_file, out, path, subst};
use std::process::Command;

fn emit(data: &[u8]) {
    match env("GITHUB_STEP_SUMMARY") {
        Some(p) if !p.is_empty() => {
            if let Ok(mut f) = std::fs::OpenOptions::new()
                .append(true)
                .create(true)
                .open(path(&p))
            {
                use std::io::Write;
                let _ = f.write_all(data);
            }
        }
        _ => {
            out(data);
        }
    }
}

fn extract_block(changelog: &[u8], ver: &[u8]) -> Vec<u8> {
    let mut result = Vec::new();
    let mut capturing = false;
    for line in changelog.split(|&c| c == b'\n') {
        if line.starts_with(b"## ") {
            if capturing {
                break;
            }
            let hv = extract_bracket_version(line);
            if ver.is_empty() || hv == ver {
                capturing = true;
                result.extend_from_slice(line);
                result.push(b'\n');
                continue;
            }
            continue;
        }
        if capturing {
            result.extend_from_slice(line);
            result.push(b'\n');
        }
    }
    result
}

/// awk's `match($0, /\[[^]]+\]/)`: the LEFTMOST `[` that is followed by at
/// least one non-`]` byte and then a `]`. So `## [] [1.2.0]` reads `1.2.0`,
/// not the empty `[]`.
fn extract_bracket_version(line: &[u8]) -> Vec<u8> {
    for start in 0..line.len() {
        if line[start] != b'[' {
            continue;
        }
        if let Some(end) = line[start + 1..].iter().position(|&c| c == b']') {
            if end > 0 {
                return line[start + 1..start + 1 + end].to_vec();
            }
        }
    }
    Vec::new()
}

/// `printf '%s\n' "$block" | sed 's/^\(#\{1,\}\)/#\1/'`, where `$block`
/// came from a command substitution: every trailing newline is dropped first
/// (only `\n`; a CRLF file keeps its last `\r`), then exactly one is added.
fn nest_headings(block: &[u8]) -> Vec<u8> {
    let mut end = block.len();
    while end > 0 && block[end - 1] == b'\n' {
        end -= 1;
    }
    let block = &block[..end];
    let mut result = Vec::new();
    for line in block.split(|&c| c == b'\n') {
        if line.starts_with(b"#") {
            result.push(b'#');
        }
        result.extend_from_slice(line);
        result.push(b'\n');
    }
    result
}

pub fn run(args: &[Vec<u8>]) -> i32 {
    let mut changelog = Vec::new();
    let mut version = Vec::new();
    let mut title = Vec::new();
    let mut range = Vec::new();
    let mut scope_path = Vec::new();

    let mut pos = 0usize;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_slice() {
            b"--range" => {
                range = args.get(i + 1).cloned().unwrap_or_default();
                i += 2;
            }
            b"--path" => {
                scope_path = args.get(i + 1).cloned().unwrap_or_default();
                i += 2;
            }
            _ => {
                pos += 1;
                match pos {
                    1 => changelog = args[i].clone(),
                    2 => version = args[i].clone(),
                    3 => title = args[i].clone(),
                    _ => {}
                }
                i += 1;
            }
        }
    }

    if changelog.is_empty() {
        err(b"changelog-summary: usage: changelog_summary <changelog-path> [version] [title] [--range A..B] [--path PATHSPEC]\n");
        return 2;
    }

    if title.is_empty() {
        title = basename(&dirname(&changelog));
    }

    // WHAT IS SHIPPING section (--range)
    if !range.is_empty() {
        let mut cmd = Command::new("git");
        cmd.arg("log")
            .arg("--no-merges")
            .arg("--format=* %s")
            .arg(shell_compat::os(&range));
        if !scope_path.is_empty() {
            cmd.arg("--").arg(shell_compat::os(&scope_path));
        }
        let r = shell_compat::capture(91, &mut cmd);
        let ok = r.ok();
        let commits = subst(r.stdout);
        if ok {
            if !commits.is_empty() {
                emit(&cat(&[
                    b"## \xf0\x9f\x9a\xa2 ",
                    &title,
                    b" \xe2\x80\x94 shipping in this deploy\n\n",
                    &commits,
                    b"\n\n",
                ]));
            } else {
                let scope_note = if !scope_path.is_empty() {
                    cat(&[b" touching `", &scope_path, b"`"])
                } else {
                    Vec::new()
                };
                emit(&cat(&[
                    b"## \xf0\x9f\x9a\xa2 ",
                    &title,
                    b" \xe2\x80\x94 shipping in this deploy\n\n_No commits in `",
                    &range,
                    b"`",
                    &scope_note,
                    b"._\n\n",
                ]));
            }
        } else {
            emit(&cat(&[
                b"## \xf0\x9f\x9a\xa2 ",
                &title,
                b" \xe2\x80\x94 shipping in this deploy\n\n_Scope could not be determined for `",
                &range,
                b"` (unknown revision, or a shallow clone without that history)._\n\n",
            ]));
        }
    }

    if !is_file(&changelog) {
        emit(&cat(&[
            b"## \xf0\x9f\x93\x93 ",
            &title,
            b"\n\n_No changelog found at `",
            &changelog,
            b"`._\n\n",
        ]));
        return 0;
    }

    // Strip v prefix
    let ver = if version.starts_with(b"v") {
        version[1..].to_vec()
    } else {
        version.clone()
    };

    let content = std::fs::read(path(&changelog)).unwrap_or_default();
    let block = extract_block(&content, &ver);

    if block.is_empty() {
        let display_ver = if version.is_empty() {
            b"latest".to_vec()
        } else {
            version.clone()
        };
        emit(&cat(&[
            b"## \xf0\x9f\x93\x93 ",
            &title,
            b"\n\n_Release notes for `",
            &display_ver,
            b"` not found in `",
            &changelog,
            b"`._\n\n",
        ]));
        return 0;
    }

    let nested = nest_headings(&block);
    emit(&cat(&[
        b"## \xf0\x9f\x93\x93 ",
        &title,
        b" \xe2\x80\x94 release notes\n\n",
        &nested,
        b"\n---\n\n",
    ]));
    0
}
