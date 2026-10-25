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

use std::io::Write;

use crate::json::Value;
use crate::pystr;

/// An exception Python would raise: its class and `str()` of it.
#[derive(Debug, Clone, PartialEq)]
pub struct Crash {
    pub class: String,
    pub msg: String,
}

pub type Res<T> = Result<T, Crash>;

impl Crash {
    pub fn new(class: &str, msg: impl Into<String>) -> Crash {
        Crash {
            class: class.into(),
            msg: msg.into(),
        }
    }

    /// The traceback Python prints for this exception.
    pub fn traceback(&self) -> String {
        let tail = if self.msg.is_empty() {
            self.class.clone()
        } else {
            format!("{}: {}", self.class, self.msg)
        };
        format!(
            "Traceback (most recent call last):\n  File \"<rust port>\", line 0, in <module>\n{}\n",
            tail
        )
    }

    /// Whether `except ValueError` catches it.
    pub fn is_value_error(&self) -> bool {
        matches!(
            self.class.as_str(),
            "ValueError"
                | "json.decoder.JSONDecodeError"
                | "UnicodeDecodeError"
                | "UnicodeEncodeError"
        )
    }

    /// `value.get(...)` on something that is not a dict.
    pub fn no_attr(v: &Value, attr: &str) -> Crash {
        Crash::new(
            "AttributeError",
            format!("'{}' object has no attribute '{}'", v.type_name(), attr),
        )
    }

    pub fn no_get(v: &Value) -> Crash {
        Crash::no_attr(v, "get")
    }

    /// Hashing a list or a dict, to key a dict or test a set.
    pub fn unhashable(v: &Value) -> Crash {
        Crash::new("TypeError", format!("unhashable type: '{}'", v.type_name()))
    }

    /// `d[key]` with no such key.
    pub fn key_error(key: &str) -> Crash {
        Crash::new("KeyError", pystr::repr_str(key))
    }

    /// `x[...]` on a value that cannot be subscripted that way.
    pub fn not_subscriptable(v: &Value) -> Crash {
        Crash::new(
            "TypeError",
            format!("'{}' object is not subscriptable", v.type_name()),
        )
    }

    pub fn not_iterable(v: &Value) -> Crash {
        Crash::new(
            "TypeError",
            format!("'{}' object is not iterable", v.type_name()),
        )
    }

    /// An OSError about a file, as `open()` raises it.
    pub fn os(err: &std::io::Error, filename: &str) -> Crash {
        let class = match err.kind() {
            std::io::ErrorKind::NotFound => "FileNotFoundError",
            std::io::ErrorKind::PermissionDenied => "PermissionError",
            std::io::ErrorKind::AlreadyExists => "FileExistsError",
            _ => match err.raw_os_error() {
                Some(21) => "IsADirectoryError",
                Some(20) => "NotADirectoryError",
                _ => "OSError",
            },
        };
        Crash::new(class, os_error_with_name(err, filename))
    }

    /// `raise SystemExit(message)`: the message on stderr, status 1.
    pub fn system_exit(msg: impl Into<String>) -> Crash {
        Crash::new("SystemExit", msg)
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

/// How the program ends on an uncaught exception: SystemExit prints its
/// message and exits 1; anything else prints a traceback and exits 1.
pub fn finish(c: &Crash) -> i32 {
    let _ = std::io::stdout().flush();
    if c.class == "SystemExit" {
        eprintln!("{}", c.msg);
    } else {
        eprint!("{}", c.traceback());
    }
    1
}

/// CPython's UTF-8 decoder: the text, or the UnicodeDecodeError it raises,
/// with the same byte range and reason. `surrogatepass` lets an encoded
/// surrogate through (as U+FFFD, which a Rust string can hold).
pub fn decode_utf8_py(bytes: &[u8], surrogatepass: bool) -> Res<String> {
    let mut out = String::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        let b = bytes[i];
        if b < 0x80 {
            out.push(b as char);
            i += 1;
            continue;
        }
        let (need, lo, hi) = match b {
            0xC2..=0xDF => (1, 0x80, 0xBF),
            0xE0 => (2, 0xA0, 0xBF),
            0xE1..=0xEC | 0xEE..=0xEF => (2, 0x80, 0xBF),
            0xED => (2, 0x80, if surrogatepass { 0xBF } else { 0x9F }),
            0xF0 => (3, 0x90, 0xBF),
            0xF1..=0xF3 => (3, 0x80, 0xBF),
            0xF4 => (3, 0x80, 0x8F),
            _ => return Err(utf8_error(bytes, i, 1, "invalid start byte")),
        };
        let mut k = 1;
        while k <= need {
            if i + k >= bytes.len() {
                return Err(utf8_error(
                    bytes,
                    i,
                    bytes.len() - i,
                    "unexpected end of data",
                ));
            }
            let c = bytes[i + k];
            let (l, h) = if k == 1 { (lo, hi) } else { (0x80, 0xBF) };
            if c < l || c > h {
                return Err(utf8_error(bytes, i, k, "invalid continuation byte"));
            }
            k += 1;
        }
        let seq = &bytes[i..i + need + 1];
        match std::str::from_utf8(seq) {
            Ok(s) => out.push_str(s),
            Err(_) => out.push('\u{FFFD}'),
        }
        i += need + 1;
    }
    Ok(out)
}

fn utf8_error(bytes: &[u8], start: usize, len: usize, reason: &str) -> Crash {
    let msg = if len <= 1 {
        format!(
            "'utf-8' codec can't decode byte 0x{:02x} in position {}: {}",
            bytes[start], start, reason
        )
    } else {
        format!(
            "'utf-8' codec can't decode bytes in position {}-{}: {}",
            start,
            start + len - 1,
            reason
        )
    };
    Crash::new("UnicodeDecodeError", msg)
}

/// `bytes.decode("ascii")`.
pub fn decode_ascii(bytes: &[u8]) -> Res<String> {
    match bytes.iter().position(|b| *b >= 0x80) {
        None => Ok(bytes.iter().map(|b| *b as char).collect()),
        Some(at) => Err(Crash::new(
            "UnicodeDecodeError",
            format!(
                "'ascii' codec can't decode byte 0x{:02x} in position {}: ordinal not in range(128)",
                bytes[at], at
            ),
        )),
    }
}

/// `path.read_text(encoding="utf-8")`: the file's text, newlines as they
/// are written on a POSIX system (universal newlines turn \r\n and \r into
/// \n).
pub fn read_text(path: &str) -> Res<String> {
    let data = std::fs::read(path).map_err(|e| Crash::os(&e, path))?;
    Ok(universal_newlines(&decode_utf8_py(&data, false)?))
}

/// `path.read_text(encoding="ascii")`.
pub fn read_text_ascii(path: &str) -> Res<String> {
    let data = std::fs::read(path).map_err(|e| Crash::os(&e, path))?;
    Ok(universal_newlines(&decode_ascii(&data)?))
}

pub fn read_bytes(path: &str) -> Res<Vec<u8>> {
    std::fs::read(path).map_err(|e| Crash::os(&e, path))
}

pub fn write_bytes(path: &str, data: &[u8]) -> Res<()> {
    std::fs::write(path, data).map_err(|e| Crash::os(&e, path))
}

/// Text mode's reading of line ends.
pub fn universal_newlines(s: &str) -> String {
    if !s.contains('\r') {
        return s.to_string();
    }
    s.replace("\r\n", "\n").replace('\r', "\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn utf8_errors_match_cpython() {
        assert_eq!(decode_utf8_py(b"ok\xc3\xa9", false).unwrap(), "ok\u{e9}");
        let e = decode_utf8_py(b"a\xffb", false).unwrap_err();
        assert_eq!(
            e.msg,
            "'utf-8' codec can't decode byte 0xff in position 1: invalid start byte"
        );
        let e = decode_utf8_py(b"\xe2\x82", false).unwrap_err();
        assert_eq!(
            e.msg,
            "'utf-8' codec can't decode bytes in position 0-1: unexpected end of data"
        );
        let e = decode_utf8_py(b"\xf0\x90\x28", false).unwrap_err();
        assert_eq!(
            e.msg,
            "'utf-8' codec can't decode bytes in position 0-1: invalid continuation byte"
        );
        let e = decode_utf8_py(b"\xe0\x80\x80", false).unwrap_err();
        assert_eq!(
            e.msg,
            "'utf-8' codec can't decode byte 0xe0 in position 0: invalid continuation byte"
        );
        assert!(decode_utf8_py(b"\xed\xa0\x80", false).is_err());
        assert_eq!(decode_utf8_py(b"\xed\xa0\x80", true).unwrap(), "\u{FFFD}");
    }

    #[test]
    fn os_errors_name_the_file() {
        let e = std::fs::read("/definitely/not/here").unwrap_err();
        let c = Crash::os(&e, "/definitely/not/here");
        assert_eq!(c.class, "FileNotFoundError");
        assert_eq!(
            c.msg,
            "[Errno 2] No such file or directory: '/definitely/not/here'"
        );
    }
}

// --- Names the domain modules use ------------------------------------------------

/// The modules ported from the scripts call an exception a Stop.
pub type Stop = Crash;

impl Crash {
    pub fn crash(class: &str, msg: impl Into<String>) -> Crash {
        Crash::new(class, msg)
    }
}

pub fn key_error(key: &str) -> Crash {
    Crash::key_error(key)
}

pub fn no_attribute(v: &Value, attr: &str) -> Crash {
    Crash::no_attr(v, attr)
}

pub fn os_stop<P: AsRef<std::path::Path>>(err: &std::io::Error, filename: P) -> Crash {
    Crash::os(err, &filename.as_ref().to_string_lossy())
}

impl Crash {
    /// An exception written as `Class: message`.
    pub fn from_text(text: &str) -> Crash {
        match text.split_once(": ") {
            Some((class, msg)) if !class.contains(' ') => Crash::new(class, msg),
            _ => Crash::new("Exception", text),
        }
    }
}

impl std::fmt::Display for Crash {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}: {}", self.class, self.msg)
    }
}

pub fn os_error<P: AsRef<std::path::Path>>(err: &std::io::Error, filename: P) -> Crash {
    Crash::os(err, &filename.as_ref().to_string_lossy())
}

/// `str(OSError)` with no file name: `[Errno N] text`.
pub fn os_error_plain(err: &std::io::Error) -> String {
    let text = err.to_string();
    let text = match text.rfind(" (os error ") {
        Some(i) => text[..i].to_string(),
        None => text,
    };
    format!("[Errno {}] {}", err.raw_os_error().unwrap_or(0), text)
}
