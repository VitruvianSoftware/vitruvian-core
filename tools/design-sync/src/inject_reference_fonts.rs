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

//! `bazel run //tools/design-sync:inject-reference-fonts`.
//!
//! The reference storybook must render with the SAME real typefaces the sync
//! ships, or `[FONT_MISSING]` hides behind a matching fallback on both panels.
//! tokens.css pulls IBM Plex Sans / JetBrains Mono from the Google Fonts CDN
//! with an @import that Vite+lightningcss DROPS from the compiled stylesheet,
//! so storybook itself renders on system fonts. Re-run this after every
//! `storybook build -o .design-sync/sb-reference`.
//!
//! Replaced `.design-sync/inject-reference-fonts.sh` and keeps its exact
//! semantics, including the regex ones: the script's sed/grep patterns treat
//! `.` as "any character", so the matchers below do too.

use crate::design_sync_dir;
use shell_compat::{err, out, path_bytes, status_code, utf8_locale};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const LINK: &str = "<link rel=\"stylesheet\" href=\"./ds-fonts/fonts.css\">";

/// Length of the one character a regex `.` matches at `s[i..]`: a whole UTF-8
/// sequence in a UTF-8 locale, one byte otherwise. Never matches a newline
/// (sed and grep work line by line).
fn dot_len(s: &[u8], i: usize, utf8: bool) -> Option<usize> {
    let c = *s.get(i)?;
    if c == b'\n' {
        return None;
    }
    if !utf8 || c < 0x80 {
        return Some(1);
    }
    let want = match c {
        0xC2..=0xDF => 2,
        0xE0..=0xEF => 3,
        0xF0..=0xF4 => 4,
        _ => return Some(1),
    };
    match s.get(i..i + want).map(std::str::from_utf8) {
        Some(Ok(_)) => Some(want),
        _ => Some(1),
    }
}

/// Does `pat` (literal bytes, where `.` is any one character) match at `s[i..]`?
/// Returns the match length.
fn match_at(s: &[u8], i: usize, pat: &[u8], utf8: bool) -> Option<usize> {
    let mut j = i;
    for &p in pat {
        if p == b'.' {
            j += dot_len(s, j, utf8)?;
        } else if s.get(j) == Some(&p) {
            j += 1;
        } else {
            return None;
        }
    }
    Some(j - i)
}

/// `grep -q PAT FILE` for a pattern with no anchors and no metacharacter but `.`.
fn grep_q(text: &[u8], pat: &[u8]) -> bool {
    let utf8 = utf8_locale();
    (0..text.len()).any(|i| match_at(text, i, pat, utf8).is_some())
}

/// `sed "s|url('./fonts/|url('./|g"`: every non-overlapping match, left to right.
pub fn rewrite_fonts_css(css: &[u8]) -> Vec<u8> {
    let utf8 = utf8_locale();
    let mut v = Vec::with_capacity(css.len());
    let mut i = 0;
    while i < css.len() {
        if let Some(n) = match_at(css, i, b"url('./fonts/", utf8) {
            v.extend_from_slice(b"url('./");
            i += n;
        } else {
            v.push(css[i]);
            i += 1;
        }
    }
    v
}

/// `grep -o "url('[^']*')" | sed "s|url('./||; s|')||"`, then the unquoted
/// `for f in $(...)` word split: the font file names the stylesheet names.
pub fn extract_font_urls(css: &[u8]) -> Vec<Vec<u8>> {
    let utf8 = utf8_locale();
    let mut tokens: Vec<Vec<u8>> = Vec::new();
    for line in css.split(|&c| c == b'\n') {
        let mut i = 0;
        while let Some(off) = find(&line[i..], b"url('") {
            let start = i + off;
            let body = start + 5;
            match line[body..].iter().position(|&c| c == b'\'') {
                Some(q) if line.get(body + q + 1) == Some(&b')') => {
                    tokens.push(line[start..body + q + 2].to_vec());
                    i = body + q + 2;
                }
                // `[^']*'` must be followed by `)`; grep then retries from the
                // next byte, where no `url('` can start inside the quote.
                Some(_) | None => i = start + 1,
            }
        }
    }
    let mut words = Vec::new();
    for mut t in tokens {
        // s|url('./||  -- first match anywhere; a token holds one `url('`.
        if let Some(n) = match_at(&t, 0, b"url('./", utf8) {
            t.drain(..n);
        }
        // s|')||  -- first occurrence: the token's closing `')`.
        if let Some(p) = find(&t, b"')") {
            t.drain(p..p + 2);
        }
        words.extend(shell_compat::ifs_split(&t));
    }
    words
}

fn find(hay: &[u8], needle: &[u8]) -> Option<usize> {
    hay.windows(needle.len()).position(|w| w == needle)
}

/// `perl -0pi -e 's|<head>|<head><link ...>|'`: the first `<head>` only.
pub fn inject_stylesheet_link(html: &[u8]) -> Vec<u8> {
    match find(html, b"<head>") {
        Some(p) => [&html[..p + 6], LINK.as_bytes(), &html[p + 6..]].concat(),
        None => html.to_vec(),
    }
}

/// `"$here"/fonts/*.woff2`: sorted, dot-files excluded. No match leaves the
/// pattern itself, which `cp` then reports as missing.
fn woff2_glob(fonts: &Path) -> Vec<PathBuf> {
    let mut names: Vec<Vec<u8>> = fs::read_dir(fonts)
        .map(|rd| {
            rd.flatten()
                .map(|e| path_bytes(Path::new(&e.file_name())))
                .filter(|n| !n.starts_with(b".") && n.ends_with(b".woff2"))
                .collect()
        })
        .unwrap_or_default();
    names.sort();
    if names.is_empty() {
        return vec![fonts.join("*.woff2")];
    }
    names
        .into_iter()
        .map(|n| fonts.join(shell_compat::path(&n)))
        .collect()
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let here = design_sync_dir();
    let ref_dir = here.join("sb-reference");
    let iframe_path = ref_dir.join("iframe.html");

    if !iframe_path.is_file() {
        err("no sb-reference/iframe.html — build it first\n".as_bytes());
        return 1;
    }

    let ds_fonts = ref_dir.join("ds-fonts");
    if let Err(e) = fs::create_dir_all(&ds_fonts) {
        err(format!("mkdir: {}: {e}\n", ds_fonts.display()).as_bytes());
        return 1;
    }

    // cp "$here"/fonts/*.woff2 "$ref/ds-fonts/" -- cp itself, so a bad entry
    // (a directory, an unreadable face) fails exactly as it did.
    let st = Command::new("cp")
        .args(woff2_glob(&here.join("fonts")))
        .arg(&ds_fonts)
        .stdin(Stdio::null())
        .status();
    match st {
        Ok(s) if s.success() => {}
        Ok(s) => return status_code(s),
        Err(_) => return 127,
    }

    // url() resolves against the stylesheet, which lives IN ds-fonts/ next to
    // the woff2 -- so the faces are siblings ('./x.woff2'). Rewriting to
    // './ds-fonts/x.woff2' pointed at ds-fonts/ds-fonts/ and 404'd every face
    // from #2195 until that was fixed: the oracle silently ran on fallback fonts.
    // The shell redirect created the output before sed ran, so a missing
    // source still leaves an empty fonts.css behind.
    let dst_css = ds_fonts.join("fonts.css");
    let src_css = here.join("fonts.css");
    let css = match fs::read(&src_css) {
        Ok(c) => rewrite_fonts_css(&c),
        Err(_) => {
            let _ = fs::write(&dst_css, b"");
            err(&[
                b"sed: ",
                &path_bytes(&src_css)[..],
                b": No such file or directory\n",
            ]
            .concat());
            return 1;
        }
    };
    if fs::write(&dst_css, &css).is_err() {
        return 1;
    }

    // Guard: every face the stylesheet names must exist beside it.
    let mut missing = false;
    for f in extract_font_urls(&css) {
        if !ds_fonts.join(shell_compat::path(&f)).is_file() {
            err(&[b"missing font face: ds-fonts/", &f[..], b"\n"].concat());
            missing = true;
        }
    }
    if missing {
        return 1;
    }

    let iframe = match fs::read(&iframe_path) {
        Ok(c) => c,
        Err(_) => return 2,
    };
    if grep_q(&iframe, b"ds-fonts/fonts.css") {
        out(b"already injected\n");
        return 0;
    }
    let updated = inject_stylesheet_link(&iframe);
    if fs::write(&iframe_path, &updated).is_err() {
        return 1;
    }
    if grep_q(&updated, b"ds-fonts/fonts.css") {
        out(b"injected into iframe.html\n");
        0
    } else {
        1
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(v: &[Vec<u8>]) -> Vec<String> {
        v.iter()
            .map(|w| String::from_utf8_lossy(w).into_owned())
            .collect()
    }

    #[test]
    fn rewrites_and_extracts_font_urls() {
        let raw = b"@font-face { src: url('./fonts/IBMPlexSans-Regular.woff2') format('woff2'); }\n@font-face { src: url('./fonts/JetBrainsMono-Regular.woff2'); }\n";
        let rewritten = rewrite_fonts_css(raw);
        let text = String::from_utf8(rewritten.clone()).unwrap();
        assert!(text.contains("url('./IBMPlexSans-Regular.woff2')"));
        assert!(!text.contains("url('./fonts/"));
        assert_eq!(
            s(&extract_font_urls(&rewritten)),
            vec!["IBMPlexSans-Regular.woff2", "JetBrainsMono-Regular.woff2"]
        );
    }

    #[test]
    fn dot_is_any_character_like_sed() {
        // sed's `.` in `url('./fonts/` matches any character.
        assert_eq!(
            rewrite_fonts_css(b"url('Q/fonts/a.woff2')"),
            b"url('./a.woff2')"
        );
        // A url without `./` keeps its `url('` through the extraction sed.
        assert_eq!(
            s(&extract_font_urls(b"url('a.woff2')")),
            vec!["url('a.woff2"]
        );
        // grep -o works per line: a quote never closes on the next line.
        assert_eq!(
            s(&extract_font_urls(b"url('./a\n.woff2')")),
            Vec::<String>::new()
        );
        // The unquoted word split.
        assert_eq!(
            s(&extract_font_urls(
                b"url('./a.woff2 b.woff2'),url('./c.woff2')"
            )),
            vec!["a.woff2", "b.woff2", "c.woff2"]
        );
    }

    #[test]
    fn injects_stylesheet_once_after_head() {
        let html = b"<!doctype html><html><head><title>SB</title></head><head></head></html>";
        let injected = String::from_utf8(inject_stylesheet_link(html)).unwrap();
        assert!(injected
            .contains("<head><link rel=\"stylesheet\" href=\"./ds-fonts/fonts.css\"><title>"));
        assert_eq!(injected.matches("ds-fonts").count(), 1);
        assert!(grep_q(b"ds-fonts/fontsXcss", b"ds-fonts/fonts.css"));
        assert!(!grep_q(b"<head></head>", b"ds-fonts/fonts.css"));
    }
}
