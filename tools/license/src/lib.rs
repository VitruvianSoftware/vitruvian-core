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

//! //tools/license:verify in Rust: the CONTENT license gate (issue #457).
//!
//! The same checks, messages and exit codes as verify.sh (`:verify-sh`):
//!   1. every first-party app ships an MIT LICENSE naming VitruvianSoftware;
//!   2. every tracked source file that carries a license header carries the
//!      MIT grant with the VitruvianSoftware holder (header-less files are
//!      addlicense's business, so they are skipped).
//!
//! Headers are read from the file directly, so the SIGPIPE false verdict
//! verify.sh's herestrings guard against cannot arise here at all.

use std::io::{Read, Write};
use std::process::{Command, Stdio};

/// The apps that must each ship an MIT LICENSE.
pub const APPS: &[&str] = &[
    "apps/suites/tabula",
    "apps/web/oauth-user-inspector",
    "apps/cli/devx",
    "apps/cli/homelab",
    "apps/mcp/slack",
    "apps/desktop/nexus-agent",
    "apps/desktop/home-speaker",
];

/// The `git ls-files` pathspecs whose headers are content-checked.
pub const PATHSPECS: &[&str] = &["*.go", "*.ts", "*.tsx", "*.js", "*.mjs", "*.cjs", "*.swift"];

/// Trees exempt from the header check, as verify.sh's `grep -vE ^...` filters.
const EXEMPT_PREFIXES: &[&str] = &[
    "pulumi/library/",
    "pulumi/examples/",
    "packages/pulumi/library/",
    "packages/pulumi/examples/",
    // an imported GPL-3.0-or-later fork, kept with its upstream headers
    "apps/desktop/vitruvian/",
    // carries code from that fork, so GPL-3.0-or-later too
    "apps/desktop/vitruvian-tool-github/",
    // Nexus Agent's unmodified vendored Mermaid (another holder's MIT)
    "apps/desktop/nexus-agent/macos/Sources/NexusAgentUI/Resources/",
    // AGPL-3.0-or-later, with SPDX AGPL headers
    "apps/desktop/courier/",
];

/// Whether verify.sh's filters drop this `git ls-files` line.
pub fn is_exempt(path: &str) -> bool {
    // (^|/)(node_modules|dist|dist-server|bazel-[^/]*)/
    let parts: Vec<&str> = path.split('/').collect();
    if parts.len() > 1
        && parts[..parts.len() - 1].iter().any(|c| {
            matches!(*c, "node_modules" | "dist" | "dist-server") || c.starts_with("bazel-")
        })
    {
        return true;
    }
    path.ends_with(".d.ts")
        || path.contains("/internal/scaffold/templates/")
        || EXEMPT_PREFIXES.iter().any(|p| path.starts_with(p))
}

/// `grep -qE "Copyright \(c\) [0-9]{4} VitruvianSoftware"`.
pub fn has_holder(text: &[u8]) -> bool {
    const LEAD: &[u8] = b"Copyright (c) ";
    const TAIL: &[u8] = b" VitruvianSoftware";
    let mut i = 0;
    while let Some(off) = find(&text[i..], LEAD) {
        let at = i + off + LEAD.len();
        if text.len() >= at + 4 + TAIL.len()
            && text[at..at + 4].iter().all(u8::is_ascii_digit)
            && &text[at + 4..at + 4 + TAIL.len()] == TAIL
        {
            return true;
        }
        i = i + off + 1;
    }
    false
}

fn find(hay: &[u8], needle: &[u8]) -> Option<usize> {
    hay.windows(needle.len()).position(|w| w == needle)
}

/// `grep -qiE "copyright|licensed under|SPDX-License-Identifier"`.
pub fn has_any_header(text: &[u8]) -> bool {
    let lower = text.to_ascii_lowercase();
    [
        &b"copyright"[..],
        b"licensed under",
        b"spdx-license-identifier",
    ]
    .iter()
    .any(|n| find(&lower, n).is_some())
}

/// `grep -q "Permission is hereby granted, free of charge"`.
pub fn has_mit_grant(text: &[u8]) -> bool {
    find(text, b"Permission is hereby granted, free of charge").is_some()
}

/// `head -n` as bash's `$(...)` keeps it: NUL bytes dropped.
fn head_lines(data: &[u8], n: usize) -> Vec<u8> {
    let mut end = data.len();
    let mut seen = 0;
    for (i, &b) in data.iter().enumerate() {
        if b == b'\n' {
            seen += 1;
            if seen == n {
                end = i + 1;
                break;
            }
        }
    }
    data[..end].iter().copied().filter(|&b| b != 0).collect()
}

fn read(path: &str) -> std::io::Result<Vec<u8>> {
    let mut buf = Vec::new();
    std::fs::File::open(path)?.read_to_end(&mut buf)?;
    Ok(buf)
}

fn head_error(path: &str, e: &std::io::Error) -> String {
    let why = match e.raw_os_error() {
        Some(2) => "No such file or directory".to_string(),
        Some(13) => "Permission denied".to_string(),
        Some(21) => "Is a directory".to_string(),
        _ => e.to_string(),
    };
    if cfg!(target_os = "macos") {
        format!("head: {path}: {why}\n")
    } else {
        format!("head: cannot open '{path}' for reading: {why}\n")
    }
}

/// Runs the gate in the current directory; returns the exit code.
pub fn verify() -> i32 {
    let mut err = std::io::stderr().lock();
    let mut fail = false;
    let mut note = |msg: String, err: &mut std::io::StderrLock| {
        let _ = writeln!(err, "license-verify: FAIL — {msg}");
        fail = true;
    };

    // 1. Every first-party app has an MIT LICENSE + VitruvianSoftware holder.
    for app in APPS {
        let lf = format!("{app}/LICENSE");
        if !std::fs::metadata(&lf).map(|m| m.is_file()).unwrap_or(false) {
            note(format!("{lf} is missing"), &mut err);
            continue;
        }
        let data = read(&lf).unwrap_or_default();
        let first: Vec<u8> = head_lines(&data, 1)
            .into_iter()
            .filter(|&b| b != b'\r' && b != b'\n')
            .collect();
        if first != b"MIT License" {
            note(
                format!("{lf} is not an MIT License (first line is not 'MIT License')"),
                &mut err,
            );
        }
        if !has_holder(&data) {
            note(
                format!("{lf} does not carry 'Copyright (c) <year> VitruvianSoftware'"),
                &mut err,
            );
        }
    }

    // 2. Any source header present must be MIT + VitruvianSoftware.
    let listed = Command::new("git")
        .arg("ls-files")
        .args(PATHSPECS)
        .stdin(Stdio::null())
        .stderr(Stdio::inherit())
        .output()
        .map(|o| o.stdout)
        .unwrap_or_default();
    for f in String::from_utf8_lossy(&listed).lines() {
        if is_exempt(f) {
            continue;
        }
        let data = match read(f) {
            Ok(d) => d,
            Err(e) => {
                // verify.sh runs `head` under `set -e`: an unreadable file
                // stops the gate there.
                let _ = err.write_all(head_error(f, &e).as_bytes());
                return 1;
            }
        };
        let hdr = head_lines(&data, 30);
        if !has_any_header(&hdr) {
            continue;
        }
        if !has_mit_grant(&hdr) {
            note(format!("{f}: has a non-MIT license header"), &mut err);
            continue;
        }
        if !has_holder(&hdr) {
            note(
                format!("{f}: license header holder is not 'VitruvianSoftware'"),
                &mut err,
            );
        }
    }

    if fail {
        let _ = writeln!(
            err,
            "license-verify: FAILED — first-party LICENSE files and source headers must be MIT + 'VitruvianSoftware'."
        );
        return 1;
    }
    let _ = writeln!(
        std::io::stdout(),
        "license-verify: OK — all first-party LICENSE files + source headers are MIT + VitruvianSoftware."
    );
    0
}

/// Moves to the workspace, as verify.sh's opening `cd` does.
pub fn enter_workspace() -> Result<(), i32> {
    let dir = match std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        Ok(d) if !d.is_empty() => d,
        _ => {
            let out = Command::new("git")
                .args(["rev-parse", "--show-toplevel"])
                .stdin(Stdio::null())
                .stderr(Stdio::inherit())
                .output()
                .map(|o| {
                    String::from_utf8_lossy(&o.stdout)
                        .trim_end_matches('\n')
                        .to_string()
                })
                .unwrap_or_default();
            if out.is_empty() {
                return Ok(());
            }
            out
        }
    };
    std::env::set_current_dir(&dir).map_err(|e| {
        eprintln!("license-verify: cd: {dir}: {e}");
        1
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn holder() {
        assert!(has_holder(b"// Copyright (c) 2026 VitruvianSoftware\n"));
        assert!(has_holder(
            b"Copyright (c) Copyright (c) 1999 VitruvianSoftware"
        ));
        assert!(!has_holder(b"Copyright (c) 202 VitruvianSoftware"));
        assert!(!has_holder(b"Copyright (c) 20266 VitruvianSoftware"));
        assert!(!has_holder(b"Copyright (C) 2026 VitruvianSoftware"));
        assert!(!has_holder(b"Copyright (c) 2026 Somebody"));
    }

    #[test]
    fn headers() {
        assert!(has_any_header(b"// COPYRIGHT 2026"));
        assert!(has_any_header(b"// spdx-license-identifier: MIT"));
        assert!(!has_any_header(b"package main\n"));
        assert!(has_mit_grant(
            b"// Permission is hereby granted, free of charge, to"
        ));
    }

    #[test]
    fn exemptions() {
        for p in [
            "a/node_modules/x.js",
            "dist/x.js",
            "a/bazel-out/x.go",
            "x.d.ts",
            "a/internal/scaffold/templates/t.go",
            "pulumi/library/x.go",
            "packages/pulumi/examples/y.ts",
            "apps/desktop/vitruvian/S/main.swift",
            "apps/desktop/courier/a.swift",
            "bazel-/x.go",
        ] {
            assert!(is_exempt(p), "{p}");
        }
        for p in [
            "a.go",
            "dist.go",
            "a/dist",
            "apps/desktop/vitruvian-x/a.swift",
            "x/pulumi/library/a.go",
            "a/distx/b.go",
        ] {
            assert!(!is_exempt(p), "{p}");
        }
    }

    #[test]
    fn head() {
        assert_eq!(head_lines(b"a\nb\nc", 2), b"a\nb\n");
        assert_eq!(head_lines(b"a\0b", 1), b"ab");
    }
}
