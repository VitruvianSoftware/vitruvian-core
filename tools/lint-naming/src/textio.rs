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

//! Text the way Python's I/O sees it: files opened with
//! `encoding="utf-8", errors="ignore"` in universal-newlines mode, file
//! names decoded with `surrogateescape`, and the error handlers of
//! `sys.stdout` and `sys.stderr` when text is written out.

use crate::pystr::{surrogate_char, surrogate_of};
use std::ffi::{OsStr, OsString};
use std::os::unix::ffi::{OsStrExt, OsStringExt};

/// Decode UTF-8, dropping what does not decode (`errors="ignore"`).
pub fn decode_ignore(mut bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len());
    loop {
        match std::str::from_utf8(bytes) {
            Ok(s) => {
                out.push_str(s);
                return out;
            }
            Err(e) => {
                let (good, rest) = bytes.split_at(e.valid_up_to());
                out.push_str(std::str::from_utf8(good).unwrap());
                match e.error_len() {
                    Some(n) => bytes = &rest[n..],
                    None => return out,
                }
            }
        }
    }
}

/// Universal newlines: `\r\n` and `\r` read as `\n`.
pub fn translate_newlines(s: &str) -> String {
    if !s.contains('\r') {
        return s.to_string();
    }
    s.replace("\r\n", "\n").replace('\r', "\n")
}

/// `open(path, encoding="utf-8", errors="ignore").read()`.
pub fn read_text_ignore(path: &std::path::Path) -> std::io::Result<String> {
    let bytes = std::fs::read(path)?;
    Ok(translate_newlines(&decode_ignore(&bytes)))
}

/// Decode an OS string as Python does (`surrogateescape`).
pub fn os_to_str(s: &OsStr) -> String {
    let mut bytes = s.as_bytes();
    let mut out = String::with_capacity(bytes.len());
    loop {
        match std::str::from_utf8(bytes) {
            Ok(t) => {
                out.push_str(t);
                return out;
            }
            Err(e) => {
                let (good, rest) = bytes.split_at(e.valid_up_to());
                out.push_str(std::str::from_utf8(good).unwrap());
                let n = e.error_len().unwrap_or(rest.len());
                for &b in &rest[..n] {
                    out.push(surrogate_char(0xDC00 + b as u32));
                }
                bytes = &rest[n..];
            }
        }
    }
}

/// The reverse of os_to_str, for a path built from decoded names.
pub fn str_to_os(s: &str) -> OsString {
    let mut bytes = Vec::with_capacity(s.len());
    for c in s.chars() {
        match surrogate_of(c) {
            Some(sur) if (0xDC80..=0xDCFF).contains(&sur) => bytes.push((sur - 0xDC00) as u8),
            _ => {
                let mut buf = [0u8; 4];
                bytes.extend_from_slice(c.encode_utf8(&mut buf).as_bytes());
            }
        }
    }
    OsString::from_vec(bytes)
}

/// An error handler of a text stream.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Errors {
    Strict,
    SurrogateEscape,
    BackslashReplace,
    Replace,
    Ignore,
}

impl Errors {
    pub fn parse(name: &str) -> Option<Errors> {
        match name {
            "strict" => Some(Errors::Strict),
            "surrogateescape" => Some(Errors::SurrogateEscape),
            "backslashreplace" => Some(Errors::BackslashReplace),
            "replace" => Some(Errors::Replace),
            "ignore" => Some(Errors::Ignore),
            _ => None,
        }
    }
}

/// A `UnicodeEncodeError`: characters `start..end` (in code points).
#[derive(Debug, PartialEq, Eq)]
pub struct EncodeError {
    pub start: usize,
    pub end: usize,
    pub first: u32,
}

impl EncodeError {
    /// The exception's message, as its last traceback line prints it.
    pub fn message(&self) -> String {
        if self.end - self.start == 1 {
            format!(
                "UnicodeEncodeError: 'utf-8' codec can't encode character '\\u{:04x}' in position {}: surrogates not allowed",
                self.first, self.start
            )
        } else {
            format!(
                "UnicodeEncodeError: 'utf-8' codec can't encode characters in position {}-{}: surrogates not allowed",
                self.start,
                self.end - 1
            )
        }
    }
}

/// Encode `s` as UTF-8 with the given error handler.
pub fn encode(s: &str, errors: Errors) -> Result<Vec<u8>, EncodeError> {
    let chars: Vec<char> = s.chars().collect();
    let mut out = Vec::with_capacity(s.len());
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        let Some(sur) = surrogate_of(c) else {
            let mut buf = [0u8; 4];
            out.extend_from_slice(c.encode_utf8(&mut buf).as_bytes());
            i += 1;
            continue;
        };
        match errors {
            Errors::SurrogateEscape if (0xDC80..=0xDCFF).contains(&sur) => {
                out.push((sur - 0xDC00) as u8)
            }
            Errors::BackslashReplace => out.extend_from_slice(format!("\\u{:04x}", sur).as_bytes()),
            Errors::Replace => out.push(b'?'),
            Errors::Ignore => {}
            _ => {
                let mut end = i + 1;
                while end < chars.len() && surrogate_of(chars[end]).is_some() {
                    end += 1;
                }
                return Err(EncodeError {
                    start: i,
                    end,
                    first: sur,
                });
            }
        }
        i += 1;
    }
    Ok(out)
}

#[cfg(target_os = "linux")]
const LC_CTYPE: i32 = 0;
#[cfg(not(target_os = "linux"))]
const LC_CTYPE: i32 = 2;

extern "C" {
    fn setlocale(category: i32, locale: *const std::os::raw::c_char) -> *mut std::os::raw::c_char;
}

/// The LC_CTYPE locale Python ends up in at startup: "C" when the
/// environment names none or one the system does not have.
fn ctype_locale_is_c() -> bool {
    // SAFETY: setlocale with "" reads the environment; the returned
    // pointer is valid until the next call, and is only read here.
    unsafe {
        let empty = b"\0";
        let p = setlocale(LC_CTYPE, empty.as_ptr() as *const _);
        let name = if p.is_null() {
            let q = setlocale(LC_CTYPE, std::ptr::null());
            if q.is_null() {
                return true;
            }
            std::ffi::CStr::from_ptr(q).to_bytes().to_vec()
        } else {
            std::ffi::CStr::from_ptr(p).to_bytes().to_vec()
        };
        name == b"C" || name == b"POSIX"
    }
}

/// The error handler of `sys.stdout` in a Python started with this
/// environment (Python/initconfig.c config_get_stdio_errors).
pub fn stdout_errors() -> Errors {
    if let Some(v) = std::env::var_os("PYTHONIOENCODING") {
        let v = os_to_str(&v);
        if let Some((_, errors)) = v.split_once(':') {
            if let Some(e) = Errors::parse(errors) {
                return e;
            }
        }
    }
    let utf8_env = std::env::var_os("PYTHONUTF8").map(|v| os_to_str(&v));
    if ctype_locale_is_c() {
        return Errors::SurrogateEscape;
    }
    if utf8_env.as_deref() == Some("1") {
        return Errors::SurrogateEscape;
    }
    Errors::Strict
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ignore_drops_bad_bytes() {
        assert_eq!(decode_ignore(b"a\xffb\xe2\x82"), "ab");
        assert_eq!(translate_newlines("a\r\nb\rc\n"), "a\nb\nc\n");
    }

    #[test]
    fn names_round_trip() {
        let raw = OsStr::from_bytes(b"bad\xffname");
        let s = os_to_str(raw);
        assert_eq!(s.chars().count(), 8);
        assert_eq!(str_to_os(&s), raw);
        assert_eq!(encode(&s, Errors::SurrogateEscape).unwrap(), b"bad\xffname");
        assert_eq!(
            encode(&s, Errors::BackslashReplace).unwrap(),
            b"bad\\udcffname"
        );
        let e = encode(&s, Errors::Strict).unwrap_err();
        assert_eq!(
            e.message(),
            "UnicodeEncodeError: 'utf-8' codec can't encode character '\\udcff' in position 3: surrogates not allowed"
        );
        let two = os_to_str(OsStr::from_bytes(b"\xfe\xff"));
        assert_eq!(
            encode(&two, Errors::Strict).unwrap_err().message(),
            "UnicodeEncodeError: 'utf-8' codec can't encode characters in position 0-1: surrogates not allowed"
        );
    }
}
