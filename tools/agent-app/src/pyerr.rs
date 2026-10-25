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

//! Where the Python script would die with an uncaught exception, the port
//! stops the same way: a traceback header, the exception's class and
//! message, exit 1. Only the last line can match Python's, since the port
//! has no Python frames to show.

use crate::json::Value;
use crate::pystr;

#[derive(Debug, Clone, PartialEq)]
pub struct Crash {
    pub class: String,
    pub msg: String,
}

impl Crash {
    pub fn new(class: &str, msg: impl Into<String>) -> Crash {
        Crash {
            class: class.into(),
            msg: msg.into(),
        }
    }

    /// The traceback Python prints for this exception.
    pub fn traceback(&self) -> String {
        format!(
            "Traceback (most recent call last):\n  File \"<rust port>\", line 0, in <module>\n{}: {}\n",
            self.class, self.msg
        )
    }

    /// `value.get(...)` on something that is not a dict.
    pub fn no_get(v: &Value) -> Crash {
        Crash::new(
            "AttributeError",
            format!("'{}' object has no attribute 'get'", v.type_name()),
        )
    }

    /// Hashing a list or a dict, to key a dict or test a set.
    pub fn unhashable(v: &Value) -> Crash {
        Crash::new("TypeError", format!("unhashable type: '{}'", v.type_name()))
    }
}

/// `str(OSError)` for an error about a file: `[Errno N] text: 'name'`.
pub fn os_error_with_name(err: &std::io::Error, filename: &str) -> String {
    let code = err.raw_os_error().unwrap_or(0);
    let text = err.to_string();
    let text = match text.rfind(" (os error ") {
        Some(i) => text[..i].to_string(),
        None => text,
    };
    format!("[Errno {}] {}: {}", code, text, pystr::repr_str(filename))
}

/// `bytes.decode("utf-8")`, failing with the UnicodeDecodeError Python
/// raises.
pub fn decode_utf8(bytes: &[u8]) -> Result<String, Crash> {
    match std::str::from_utf8(bytes) {
        Ok(s) => Ok(s.to_string()),
        Err(e) => {
            let at = e.valid_up_to();
            let reason = match e.error_len() {
                None => "unexpected end of data",
                Some(_) if (0x80..0xC2).contains(&bytes[at]) || bytes[at] > 0xF4 => {
                    "invalid start byte"
                }
                Some(_) => "invalid continuation byte",
            };
            Err(Crash::new(
                "UnicodeDecodeError",
                format!(
                    "'utf-8' codec can't decode byte 0x{:02x} in position {}: {}",
                    bytes[at], at, reason
                ),
            ))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decode_errors_name_the_byte() {
        assert_eq!(decode_utf8(b"ok").unwrap(), "ok");
        let e = decode_utf8(b"a\xffb").unwrap_err();
        assert_eq!(e.class, "UnicodeDecodeError");
        assert!(
            e.msg.contains("0xff in position 1: invalid start byte"),
            "{}",
            e.msg
        );
        assert!(decode_utf8(b"\xe2\x82")
            .unwrap_err()
            .msg
            .contains("unexpected end"));
    }

    #[test]
    fn os_errors_name_the_file() {
        let e = std::fs::read("/definitely/not/here").unwrap_err();
        assert_eq!(
            os_error_with_name(&e, "/definitely/not/here"),
            "[Errno 2] No such file or directory: '/definitely/not/here'"
        );
    }
}
