// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT
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

//! `bazel run //tools/design-sync:prepare` -- everything that must be fresh
//! BEFORE package-build.mjs runs. `.design-sync/config.json`'s `buildCmd`
//! runs it, so the re-sync driver does too.
//!
//! 1. The design system's own `dist/` (plain `tsc -p tsconfig.json`, run from
//!    the package, per its "build" script). The converter bundles it into
//!    `window.Vitruvian`.
//! 2. The full-vocabulary stylesheet `dist/vitruvian.built.css`. See
//!    `.design-sync/tailwind-entry.css` for why it exists: a rendered design
//!    gets static CSS with no Tailwind compiler, so the utility language has to
//!    be force-generated rather than scraped. Tailwind runs from the PACKAGE,
//!    not the repo root: v4 auto-scans the working directory for class names,
//!    and a root run pulled ~270 utilities from unrelated monorepo apps into the
//!    design system's stylesheet.
//! 3. Guard: stock Tailwind palettes are not part of the design language
//!    (conventions.md says so). If one appears, something is scanning too wide.
//!
//! Replaced `.design-sync/prepare.sh`; exit codes and messages are that
//! script's (127/126 for a tool that cannot start, the tool's own status when
//! it fails, 1 on a leaked palette).

use crate::design_sync_dir;
use shell_compat::{err, out, path_bytes, status_code};
use std::fs;
use std::io;
use std::path::Path;
use std::process::{Command, Stdio};

const FORBIDDEN_PALETTES: &[&str] = &[
    "red", "amber", "yellow", "green", "emerald", "blue", "purple", "rose", "slate", "gray",
];

/// `grep -qE -- '--color-(red|amber|yellow|green|emerald|blue|purple|rose|slate|gray)-[0-9]+'`.
pub fn has_leaked_tailwind_color(css: &str) -> bool {
    let prefix = "--color-";
    let mut rest = css;
    while let Some(pos) = rest.find(prefix) {
        let after = &rest[pos + prefix.len()..];
        for pal in FORBIDDEN_PALETTES {
            if let Some(after_pal) = after.strip_prefix(pal) {
                if let Some(digits) = after_pal.strip_prefix('-') {
                    if digits.bytes().next().is_some_and(|b| b.is_ascii_digit()) {
                        return true;
                    }
                }
            }
        }
        rest = after;
    }
    false
}

/// `(cd "$pkg" && "$bin" args...)`: the tool's own status, or what bash
/// reports when it cannot start it.
fn run_in(pkg: &Path, bin: &Path, args: &[&std::ffi::OsStr]) -> i32 {
    let st = Command::new(bin)
        .args(args)
        .current_dir(pkg)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status();
    match st {
        Ok(s) => status_code(s),
        Err(e) => {
            let (why, code) = if e.kind() == io::ErrorKind::NotFound {
                ("No such file or directory", 127)
            } else {
                ("Permission denied", 126)
            };
            err(&[&path_bytes(bin)[..], b": ", why.as_bytes(), b"\n"].concat());
            code
        }
    }
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let here = design_sync_dir();
    let root = here.parent().unwrap_or(&here).to_path_buf();
    let pkg = root.join("packages/design-system");

    if !pkg.is_dir() {
        err(&[
            b"cd: ",
            &path_bytes(&pkg)[..],
            b": No such file or directory\n",
        ]
        .concat());
        return 1;
    }

    // 1. dist/
    let rc = run_in(
        &pkg,
        &root.join("node_modules/.bin/tsc"),
        &["-p".as_ref(), "tsconfig.json".as_ref()],
    );
    if rc != 0 {
        return rc;
    }

    // 2. dist/vitruvian.built.css
    let built_css = pkg.join("dist/vitruvian.built.css");
    let entry = here.join("tailwind-entry.css");
    let rc = run_in(
        &pkg,
        &root.join(".ds-sync/node_modules/.bin/tailwindcss"),
        &[
            "-i".as_ref(),
            entry.as_os_str(),
            "-o".as_ref(),
            built_css.as_os_str(),
        ],
    );
    if rc != 0 {
        return rc;
    }

    // 3. the palette guard. The script ran it as `if grep -qE ...`, where an
    // unreadable stylesheet (grep exit 2) is just "no match": grep complains,
    // and the run still reports ready. Kept as it was; the converter then logs
    // `! cssEntry: ... not found — skipped`, which NOTES.md says to treat as a
    // failure.
    let css = match fs::read(&built_css) {
        Ok(c) => c,
        Err(_) => {
            err(&[
                b"grep: ",
                &path_bytes(&built_css)[..],
                b": No such file or directory\n",
            ]
            .concat());
            Vec::new()
        }
    };
    if has_leaked_tailwind_color(&String::from_utf8_lossy(&css)) {
        err(b"prepare: stock Tailwind colours leaked into vitruvian.built.css\n");
        return 1;
    }

    out(b"prepare: dist/ + dist/vitruvian.built.css ready\n");
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_leaked_stock_tailwind_colors() {
        assert!(has_leaked_tailwind_color(
            ":root { --color-blue-500: #3b82f6; }"
        ));
        assert!(has_leaked_tailwind_color("  --color-slate-50: #f8fafc;"));
        assert!(!has_leaked_tailwind_color(
            ":root { --color-surface-primary: #111; --color-blue-sky: #00f; }"
        ));
        assert!(!has_leaked_tailwind_color("--color-reds-1: #f00"));
    }
}
