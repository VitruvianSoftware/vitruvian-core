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

//! Rust port of `.design-sync/inject-reference-fonts.sh`.

use shell_compat::{err, out, status_code};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// Rewrite `url('./fonts/` to `url('./` inside `fonts.css`.
pub fn rewrite_fonts_css(css: &str) -> String {
    css.replace("url('./fonts/", "url('./")
}

/// Extract font filenames referenced by `url('...')` in `fonts.css`,
/// stripping `url('./` and `')` as `grep -o "url('[^']*')" | sed "s|url('./||; s|')||"` does.
pub fn extract_font_urls(css: &str) -> Vec<String> {
    let mut urls = Vec::new();
    let mut rest = css;
    while let Some(start) = rest.find("url('") {
        let after_open = &rest[start + 5..];
        if let Some(end) = after_open.find('\'') {
            let token = &rest[start..start + 5 + end + 2]; // url('...')
            let stripped = token
                .strip_prefix("url('./")
                .unwrap_or_else(|| token.strip_prefix("url('").unwrap_or(token));
            let stripped = stripped.strip_suffix("')").unwrap_or(stripped);
            urls.push(stripped.to_string());
            rest = &after_open[end + 1..];
        } else {
            break;
        }
    }
    urls
}

/// Inject `<link rel="stylesheet" href="./ds-fonts/fonts.css">` immediately after
/// the first `<head>` tag in `html`.
pub fn inject_stylesheet_link(html: &str) -> String {
    html.replacen(
        "<head>",
        "<head><link rel=\"stylesheet\" href=\"./ds-fonts/fonts.css\">",
        1,
    )
}

fn resolve_here(argv0: Option<&Path>) -> PathBuf {
    if let Some(p) = argv0 {
        let parent = p
            .parent()
            .filter(|d| !d.as_os_str().is_empty())
            .unwrap_or_else(|| Path::new("."));
        if let Ok(canon) = fs::canonicalize(parent) {
            if canon.join("sb-reference").exists() || canon.join("fonts.css").exists() {
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

fn list_woff2_files(dir: &Path) -> Vec<PathBuf> {
    let mut files = Vec::new();
    if let Ok(entries) = fs::read_dir(dir) {
        for e in entries.flatten() {
            let p = e.path();
            if p.extension().and_then(|s| s.to_str()) == Some("woff2") && p.is_file() {
                files.push(p);
            }
        }
    }
    files.sort();
    files
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let argv0 = std::env::args_os().next().map(PathBuf::from);
    let here = resolve_here(argv0.as_deref());
    let ref_dir = here.join("sb-reference");
    let iframe_path = ref_dir.join("iframe.html");

    if !iframe_path.is_file() {
        err(b"no sb-reference/iframe.html \xE2\x80\x94 build it first\n");
        return 1;
    }

    let ds_fonts = ref_dir.join("ds-fonts");
    if fs::create_dir_all(&ds_fonts).is_err() {
        return 1;
    }

    let fonts_dir = here.join("fonts");
    let woff2_files = list_woff2_files(&fonts_dir);
    if woff2_files.is_empty() {
        let st = Command::new("cp")
            .arg(fonts_dir.join("*.woff2"))
            .arg(&ds_fonts)
            .stdin(Stdio::null())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status();
        return st.map(status_code).unwrap_or(1);
    }
    for f in &woff2_files {
        if let Some(name) = f.file_name() {
            if fs::copy(f, ds_fonts.join(name)).is_err() {
                return 1;
            }
        }
    }

    let src_css_path = here.join("fonts.css");
    let src_css = match fs::read_to_string(&src_css_path) {
        Ok(c) => c,
        Err(_) => return 1,
    };
    let rewritten_css = rewrite_fonts_css(&src_css);
    let dst_css_path = ds_fonts.join("fonts.css");
    if fs::write(&dst_css_path, &rewritten_css).is_err() {
        return 1;
    }

    let mut missing = 0;
    for f in extract_font_urls(&rewritten_css) {
        for word in f.split_whitespace() {
            if !ds_fonts.join(word).is_file() {
                err(format!("missing font face: ds-fonts/{word}\n").as_bytes());
                missing = 1;
            }
        }
    }
    if missing != 0 {
        return 1;
    }

    let iframe = match fs::read_to_string(&iframe_path) {
        Ok(c) => c,
        Err(_) => return 1,
    };
    if iframe.contains("ds-fonts/fonts.css") {
        out(b"already injected\n");
        return 0;
    }

    let updated = inject_stylesheet_link(&iframe);
    if fs::write(&iframe_path, &updated).is_err() {
        return 1;
    }

    let check_iframe = fs::read_to_string(&iframe_path).unwrap_or_default();
    if check_iframe.contains("ds-fonts/fonts.css") {
        out(b"injected into iframe.html\n");
        0
    } else {
        1
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rewrites_and_extracts_font_urls() {
        let raw = "@font-face { src: url('./fonts/IBMPlexSans-Regular.woff2') format('woff2'); }\n@font-face { src: url('./fonts/JetBrainsMono-Regular.woff2'); }\n";
        let rewritten = rewrite_fonts_css(raw);
        assert!(rewritten.contains("url('./IBMPlexSans-Regular.woff2')"));
        assert!(!rewritten.contains("url('./fonts/"));
        let urls = extract_font_urls(&rewritten);
        assert_eq!(
            urls,
            vec!["IBMPlexSans-Regular.woff2", "JetBrainsMono-Regular.woff2"]
        );
    }

    #[test]
    fn injects_stylesheet_once_after_head() {
        let html = "<!doctype html><html><head><title>SB</title></head><body></body></html>";
        let injected = inject_stylesheet_link(html);
        assert!(injected
            .contains("<head><link rel=\"stylesheet\" href=\"./ds-fonts/fonts.css\"><title>"));
    }
}
