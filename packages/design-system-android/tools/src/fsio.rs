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

//! `pathlib.Path(p).read_text(encoding="utf-8")` and `.write_text(...)`:
//! the path as pathlib spells it (which is what an OSError names), the
//! decode and its errors, universal newlines on the way in.

use std::io::{Read, Write};

use crate::pyerr::{self, Exc};
use crate::pystr::{self, ps, PyStr};

/// `str(pathlib.PurePosixPath(p))`: `.` parts and repeated or trailing
/// slashes dropped, a leading `//` (exactly two) kept, `.` for nothing.
pub fn pathlib_str(p: &str) -> String {
    let root = if p.starts_with("//") && !p.starts_with("///") {
        "//"
    } else if p.starts_with('/') {
        "/"
    } else {
        ""
    };
    let parts: Vec<&str> = p
        .split('/')
        .filter(|x| !x.is_empty() && *x != ".")
        .collect();
    let s = format!("{}{}", root, parts.join("/"));
    if s.is_empty() {
        ".".into()
    } else {
        s
    }
}

/// Universal newlines: `\r\n` and a lone `\r` read as `\n`.
fn translate_newlines(text: &str) -> PyStr {
    let mut out = Vec::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\r' {
            if chars.peek() == Some(&'\n') {
                chars.next();
            }
            out.push('\n' as u32);
        } else {
            out.push(c as u32);
        }
    }
    out
}

/// `Path(p).read_text(encoding="utf-8")`.
pub fn read_text(p: &str) -> Result<PyStr, Exc> {
    let path = pathlib_str(p);
    let mut data = Vec::new();
    std::fs::File::open(&path)
        .and_then(|mut f| f.read_to_end(&mut data))
        .map_err(|e| pyerr::os_error(&e, &ps(&path)))?;
    let text = pyerr::decode_utf8(&data)?;
    Ok(translate_newlines(&text))
}

/// `Path(p).write_text(text, encoding="utf-8")`. Like Python, the file is
/// created (or emptied) before the text is encoded, so text that cannot be
/// encoded leaves it empty.
pub fn write_text(p: &str, text: &[u32]) -> Result<(), Exc> {
    let path = pathlib_str(p);
    let os = |e: std::io::Error| pyerr::os_error(&e, &ps(&path));
    let mut f = std::fs::File::create(&path).map_err(os)?;
    let bytes = pystr::encode_utf8(text).map_err(|(a, b)| pyerr::encode_error(text, a, b))?;
    f.write_all(&bytes).map_err(os)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paths_spell_as_pathlib() {
        for (given, want) in [
            ("", "."),
            (".", "."),
            ("./", "."),
            ("a/./b//c/", "a/b/c"),
            ("//a", "//a"),
            ("///a", "/a"),
            ("/", "/"),
            ("//", "//"),
            ("../x", "../x"),
        ] {
            assert_eq!(pathlib_str(given), want, "{:?}", given);
        }
    }

    #[test]
    fn newlines_are_universal() {
        assert_eq!(translate_newlines("a\r\nb\rc\n\r"), ps("a\nb\nc\n\n"));
    }
}
