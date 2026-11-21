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

//! The exceptions gen_tokens.py can die with, and the traceback it prints.
//!
//! Where the script would stop on an uncaught exception, the port stops
//! the same way: a traceback, the exception's class and message, exit 1.
//! Python's traceback names its own files and source lines, which the port
//! cannot have, so only its last line (class and message) is the same.

use crate::pystr::{self, ps, PyStr};

#[derive(Clone, Debug, PartialEq)]
pub struct Exc {
    /// The class as the traceback names it (`json.decoder.JSONDecodeError`).
    pub class: &'static str,
    /// `str(exception)`; may carry lone surrogates.
    pub msg: PyStr,
}

impl Exc {
    pub fn new(class: &'static str, msg: impl AsRef<str>) -> Exc {
        Exc {
            class,
            msg: ps(msg.as_ref()),
        }
    }

    pub fn type_error(msg: impl AsRef<str>) -> Exc {
        Exc::new("TypeError", msg)
    }

    pub fn value_error(msg: impl AsRef<str>) -> Exc {
        Exc::new("ValueError", msg)
    }

    /// The KeyError a missing key raises: its message is the key's repr.
    pub fn key_error(repr: String) -> Exc {
        Exc::new("KeyError", repr)
    }

    pub fn recursion(context: &str) -> Exc {
        Exc::new(
            "RecursionError",
            format!("maximum recursion depth exceeded{}", context),
        )
    }

    /// What Python's excepthook writes to stderr.
    pub fn traceback(&self) -> String {
        let last = if self.msg.is_empty() {
            self.class.to_string()
        } else {
            format!("{}: {}", self.class, pystr::backslashreplace(&self.msg))
        };
        format!(
            "Traceback (most recent call last):\n  File \"<rust port of gen_tokens.py>\", line 0, in <module>\n{}\n",
            last
        )
    }
}

/// The OSError subclass Python raises for an errno.
fn os_error_class(errno: i32) -> &'static str {
    match errno {
        1 | 13 => "PermissionError",
        2 => "FileNotFoundError",
        4 => "InterruptedError",
        17 => "FileExistsError",
        20 => "NotADirectoryError",
        21 => "IsADirectoryError",
        _ => "OSError",
    }
}

/// The OSError for a failed open, read or write of `filename`:
/// `[Errno N] strerror: 'filename'`.
pub fn os_error(err: &std::io::Error, filename: &PyStr) -> Exc {
    let Some(errno) = err.raw_os_error() else {
        return Exc::new("OSError", err.to_string());
    };
    let text = err.to_string();
    let text = match text.rfind(" (os error ") {
        Some(i) => text[..i].to_string(),
        None => text,
    };
    Exc::new(
        os_error_class(errno),
        format!("[Errno {}] {}: {}", errno, text, pystr::repr(filename)),
    )
}

/// `data.decode("utf-8")`, failing with the UnicodeDecodeError CPython's
/// decoder raises (the same maximal-subpart ranges Rust reports).
pub fn decode_utf8(data: &[u8]) -> Result<String, Exc> {
    match std::str::from_utf8(data) {
        Ok(s) => Ok(s.to_string()),
        Err(e) => {
            let start = e.valid_up_to();
            let (len, reason) = match e.error_len() {
                None => (data.len() - start, "unexpected end of data"),
                Some(n) => {
                    let b = data[start];
                    let invalid_start = (0x80..0xC2).contains(&b) || b > 0xF4;
                    let reason = if invalid_start {
                        "invalid start byte"
                    } else {
                        "invalid continuation byte"
                    };
                    (n, reason)
                }
            };
            let what = if len == 1 {
                format!("byte 0x{:02x} in position {}", data[start], start)
            } else {
                format!("bytes in position {}-{}", start, start + len - 1)
            };
            Err(Exc::new(
                "UnicodeDecodeError",
                format!("'utf-8' codec can't decode {}: {}", what, reason),
            ))
        }
    }
}

/// The UnicodeEncodeError for surrogates at `start..end` of `text`.
pub fn encode_error(text: &[u32], start: usize, end: usize) -> Exc {
    let what = if end - start == 1 {
        format!("character '\\u{:04x}' in position {}", text[start], start)
    } else {
        format!("characters in position {}-{}", start, end - 1)
    };
    Exc::new(
        "UnicodeEncodeError",
        format!(
            "'utf-8' codec can't encode {}: surrogates not allowed",
            what
        ),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decode_errors_name_the_bytes() {
        let msg = |b: &[u8]| pystr::backslashreplace(&decode_utf8(b).unwrap_err().msg);
        assert_eq!(
            msg(b"a\xe2\x82"),
            "'utf-8' codec can't decode bytes in position 1-2: unexpected end of data"
        );
        assert_eq!(
            msg(b"a\xe2\x82x"),
            "'utf-8' codec can't decode bytes in position 1-2: invalid continuation byte"
        );
        assert_eq!(
            msg(b"\xe0\x80"),
            "'utf-8' codec can't decode byte 0xe0 in position 0: invalid continuation byte"
        );
        assert_eq!(
            msg(b"\xff"),
            "'utf-8' codec can't decode byte 0xff in position 0: invalid start byte"
        );
    }

    #[test]
    fn os_errors_name_the_file() {
        let e = std::fs::read("/definitely/not/here").unwrap_err();
        let exc = os_error(&e, &ps("/definitely/not/here"));
        assert_eq!(exc.class, "FileNotFoundError");
        assert_eq!(
            pystr::backslashreplace(&exc.msg),
            "[Errno 2] No such file or directory: '/definitely/not/here'"
        );
    }

    #[test]
    fn traceback_ends_with_class_and_message() {
        let t = Exc::key_error("'space'".into()).traceback();
        assert!(t.starts_with("Traceback (most recent call last):\n"));
        assert!(t.ends_with("\nKeyError: 'space'\n"));
        assert!(Exc::new("ValueError", "")
            .traceback()
            .ends_with("\nValueError\n"));
    }

    #[test]
    fn encode_errors_group_surrogates() {
        let e = encode_error(&[0x61, 0xD800, 0xDFFF], 1, 3);
        assert_eq!(
            pystr::backslashreplace(&e.msg),
            "'utf-8' codec can't encode characters in position 1-2: surrogates not allowed"
        );
        let e = encode_error(&[0xD800], 0, 1);
        assert_eq!(
            pystr::backslashreplace(&e.msg),
            "'utf-8' codec can't encode character '\\ud800' in position 0: surrogates not allowed"
        );
    }
}
