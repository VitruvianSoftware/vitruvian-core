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

//! Rust port of `.design-sync/prepare.sh`.

use shell_compat::{err, out, status_code};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const FORBIDDEN_PALETTES: &[&str] = &[
    "red", "amber", "yellow", "green", "emerald", "blue", "purple", "rose", "slate", "gray",
];

/// Matches `--color-(red|amber|yellow|green|emerald|blue|purple|rose|slate|gray)-[0-9]+`.
pub fn has_leaked_tailwind_color(css: &str) -> bool {
    let prefix = "--color-";
    let mut rest = css;
    while let Some(pos) = rest.find(prefix) {
        let after = &rest[pos + prefix.len()..];
        for pal in FORBIDDEN_PALETTES {
            if let Some(after_pal) = after.strip_prefix(pal) {
                if let Some(digits) = after_pal.strip_prefix('-') {
                    if digits.bytes().next().map_or(false, |b| b.is_ascii_digit()) {
                        return true;
                    }
                }
            }
        }
        rest = after;
    }
    false
}

fn resolve_here(argv0: Option<&Path>) -> PathBuf {
    if let Some(p) = argv0 {
        let parent = p
            .parent()
            .filter(|d| !d.as_os_str().is_empty())
            .unwrap_or_else(|| Path::new("."));
        if let Ok(canon) = fs::canonicalize(parent) {
            if canon
                .parent()
                .map_or(false, |r| r.join("packages/design-system").exists())
            {
                return canon;
            }
            let ds = PathBuf::from(".design-sync");
            if let Ok(ds_canon) = fs::canonicalize(&ds) {
                return ds_canon;
            }
            return canon;
        }
    }
    std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let argv0 = std::env::args_os().next().map(PathBuf::from);
    let here = resolve_here(argv0.as_deref());
    let root = match fs::canonicalize(here.join("..")) {
        Ok(r) => r,
        Err(_) => here.parent().unwrap_or(&here).to_path_buf(),
    };
    let pkg = root.join("packages/design-system");

    if !pkg.is_dir() {
        let st = Command::new("bash")
            .arg("-c")
            .arg("cd \"$1\"")
            .arg("_")
            .arg(&pkg)
            .status();
        return st.map(status_code).unwrap_or(1);
    }

    let tsc_bin = root.join("node_modules/.bin/tsc");
    let tsc_st = Command::new(&tsc_bin)
        .arg("-p")
        .arg("tsconfig.json")
        .current_dir(&pkg)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status();
    match tsc_st {
        Ok(s) if s.success() => {}
        Ok(s) => return status_code(s),
        Err(_) => return 127,
    }

    let tailwind_bin = root.join(".ds-sync/node_modules/.bin/tailwindcss");
    let built_css = pkg.join("dist/vitruvian.built.css");
    let tw_st = Command::new(&tailwind_bin)
        .arg("-i")
        .arg(here.join("tailwind-entry.css"))
        .arg("-o")
        .arg(&built_css)
        .current_dir(&pkg)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status();
    match tw_st {
        Ok(s) if s.success() => {}
        Ok(s) => return status_code(s),
        Err(_) => return 127,
    }

    let css_content = match fs::read_to_string(&built_css) {
        Ok(c) => c,
        Err(_) => return 2,
    };

    if has_leaked_tailwind_color(&css_content) {
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
    }
}
