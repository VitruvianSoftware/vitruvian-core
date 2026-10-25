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

//! The parts of Python's behaviour the scripts' output depends on: what
//! counts as whitespace and as a word character, `repr` of a string and of a
//! float, `os.path`'s normpath, join, dirname and basename,
//! `urllib.parse.quote` and `urlsplit(...).hostname`, and reading a file the
//! way `open(path, encoding="utf-8").read()` does, with the same OSError and
//! codec messages.

use std::fs;
use std::io;

/// `str.isspace()`, which is also what `\s` and `str.strip()` use.
pub fn is_space(c: char) -> bool {
    c.is_whitespace() || ('\u{1c}'..='\u{1f}').contains(&c)
}

/// `\w` in a `str` pattern: a letter, a digit or an underscore.
pub fn is_word(c: char) -> bool {
    c == '_' || c.is_alphanumeric()
}

pub fn strip(s: &str) -> &str {
    s.trim_matches(is_space)
}

pub fn lstrip(s: &str) -> &str {
    s.trim_start_matches(is_space)
}

/// `len(line) - len(line.lstrip())`, in characters.
pub fn indent_of(s: &str) -> usize {
    s.chars().count() - lstrip(s).chars().count()
}

/// `str.strip("\"'")`.
pub fn strip_quotes(s: &str) -> &str {
    s.trim_matches(|c| c == '"' || c == '\'')
}

fn is_printable(c: char) -> bool {
    let n = c as u32;
    if c == ' ' {
        return true;
    }
    if c.is_control() || c.is_whitespace() {
        return false;
    }
    !matches!(n,
        0xad | 0x600..=0x605 | 0x61c | 0x6dd | 0x70f | 0x180e
        | 0x200b..=0x200f | 0x202a..=0x202e | 0x2060..=0x2064 | 0x2066..=0x206f
        | 0xd800..=0xdfff | 0xe000..=0xf8ff | 0xfeff | 0xfff9..=0xfffb
        | 0xf0000..=0x10ffff)
}

/// `repr()` of a `str`.
pub fn repr_str(s: &str) -> String {
    let quote = if s.contains('\'') && !s.contains('"') {
        '"'
    } else {
        '\''
    };
    let mut out = String::with_capacity(s.len() + 2);
    out.push(quote);
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c == quote => {
                out.push('\\');
                out.push(c);
            }
            c if is_printable(c) => out.push(c),
            c => {
                let n = c as u32;
                if n < 0x100 {
                    out.push_str(&format!("\\x{n:02x}"));
                } else if n < 0x10000 {
                    out.push_str(&format!("\\u{n:04x}"));
                } else {
                    out.push_str(&format!("\\U{n:08x}"));
                }
            }
        }
    }
    out.push(quote);
    out
}

/// `repr()` of a tuple of strings, as tomllib prints a key.
pub fn repr_tuple(parts: &[String]) -> String {
    let inner: Vec<String> = parts.iter().map(|p| repr_str(p)).collect();
    match inner.len() {
        1 => format!("({},)", inner[0]),
        _ => format!("({})", inner.join(", ")),
    }
}

/// `repr()` of a float (also its `str()`): the shortest digits that read
/// back the same, in exponent form below 1e-4 and from 1e16.
pub fn repr_float(f: f64) -> String {
    if f.is_nan() {
        return "nan".into();
    }
    if f.is_infinite() {
        return if f > 0.0 { "inf".into() } else { "-inf".into() };
    }
    if f == 0.0 {
        return if f.is_sign_negative() {
            "-0.0".into()
        } else {
            "0.0".into()
        };
    }
    let sci = format!("{:e}", f); // e.g. -1.5e16, 1e-5
    let (mantissa, exp) = sci.split_once('e').unwrap();
    let exp: i32 = exp.parse().unwrap();
    let negative = mantissa.starts_with('-');
    let digits: String = mantissa.chars().filter(|c| c.is_ascii_digit()).collect();
    let sign = if negative { "-" } else { "" };
    if !(-4..16).contains(&exp) {
        let (first, rest) = digits.split_at(1);
        let mantissa = if rest.is_empty() {
            first.to_string()
        } else {
            format!("{first}.{rest}")
        };
        let esign = if exp < 0 { '-' } else { '+' };
        return format!("{sign}{mantissa}e{esign}{:02}", exp.abs());
    }
    if exp < 0 {
        let zeros = "0".repeat((-exp - 1) as usize);
        return format!("{sign}0.{zeros}{digits}");
    }
    let point = (exp + 1) as usize;
    if digits.len() <= point {
        let zeros = "0".repeat(point - digits.len());
        format!("{sign}{digits}{zeros}.0")
    } else {
        format!("{sign}{}.{}", &digits[..point], &digits[point..])
    }
}

// --- os.path (posixpath) --------------------------------------------------------

pub fn join(a: &str, b: &str) -> String {
    if b.starts_with('/') {
        b.to_string()
    } else if a.is_empty() || a.ends_with('/') {
        format!("{a}{b}")
    } else {
        format!("{a}/{b}")
    }
}

pub fn dirname(p: &str) -> String {
    let i = p.rfind('/').map(|i| i + 1).unwrap_or(0);
    let head = &p[..i];
    if !head.is_empty() && head.chars().any(|c| c != '/') {
        head.trim_end_matches('/').to_string()
    } else {
        head.to_string()
    }
}

pub fn basename(p: &str) -> &str {
    match p.rfind('/') {
        Some(i) => &p[i + 1..],
        None => p,
    }
}

pub fn normpath(path: &str) -> String {
    if path.is_empty() {
        return ".".into();
    }
    let mut initial = if path.starts_with('/') { 1 } else { 0 };
    if initial == 1 && path.starts_with("//") && !path.starts_with("///") {
        initial = 2;
    }
    let mut comps: Vec<&str> = Vec::new();
    for comp in path.split('/') {
        if comp.is_empty() || comp == "." {
            continue;
        }
        if comp != ".." || (initial == 0 && comps.is_empty()) || comps.last() == Some(&"..") {
            comps.push(comp);
        } else if !comps.is_empty() {
            comps.pop();
        }
    }
    let joined = format!("{}{}", "/".repeat(initial), comps.join("/"));
    if joined.is_empty() {
        ".".into()
    } else {
        joined
    }
}

// --- urllib.parse ---------------------------------------------------------------

/// `urllib.parse.quote(s, safe=safe)`.
pub fn quote(s: &str, safe: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        let c = b as char;
        if b.is_ascii_alphanumeric() || "_.-~".contains(c) || (b < 0x80 && safe.contains(c)) {
            out.push(c);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// `(scheme, hostname)` of `urllib.parse.urlsplit(url)`: the scheme
/// lowercased, the host lowercased with any user and port taken off.
pub fn split_url(url: &str) -> (String, Option<String>) {
    let url = url.trim_matches(|c: char| (c as u32) <= 0x20);
    let mut scheme = String::new();
    let mut rest = url;
    if let Some(i) = url.find(':') {
        let candidate = &url[..i];
        if !candidate.is_empty()
            && candidate.chars().next().unwrap().is_ascii_alphabetic()
            && candidate
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || "+-.".contains(c))
        {
            scheme = candidate.to_ascii_lowercase();
            rest = &url[i + 1..];
        }
    }
    let Some(after) = rest.strip_prefix("//") else {
        return (scheme, None);
    };
    let end = after.find(['/', '?', '#']).unwrap_or(after.len());
    let netloc = &after[..end];
    let host = netloc.rsplit_once('@').map(|(_, h)| h).unwrap_or(netloc);
    let host = if let Some(stripped) = host.strip_prefix('[') {
        stripped.split(']').next().unwrap_or("")
    } else {
        host.split(':').next().unwrap_or("")
    };
    if host.is_empty() {
        (scheme, None)
    } else {
        (scheme, Some(host.to_lowercase()))
    }
}

// --- reading a file as Python does ------------------------------------------

/// What `open(path, encoding="utf-8").read()` raises, as `str(error)`.
#[derive(Debug, Clone, PartialEq)]
pub enum ReadError {
    /// An OSError: `[Errno 2] No such file or directory: '/x'`, and which
    /// subclass (FileNotFoundError, IsADirectoryError, ...).
    Os(String, &'static str),
    /// A UnicodeDecodeError, which is a ValueError.
    Decode(String),
}

impl std::fmt::Display for ReadError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ReadError::Os(m, _) | ReadError::Decode(m) => f.write_str(m),
        }
    }
}

impl ReadError {
    /// The last line of the traceback when nothing catches it.
    pub fn crash_line(&self) -> String {
        match self {
            ReadError::Os(m, class) => format!("{class}: {m}"),
            ReadError::Decode(m) => format!("UnicodeDecodeError: {m}"),
        }
    }
}

/// The OSError subclass Python raises for an errno.
pub fn os_error_class(error: &io::Error) -> &'static str {
    match error.raw_os_error() {
        Some(2) => "FileNotFoundError",
        Some(13) | Some(1) => "PermissionError",
        Some(21) => "IsADirectoryError",
        Some(20) => "NotADirectoryError",
        Some(17) => "FileExistsError",
        _ => "OSError",
    }
}

/// `str(OSError)` for an error about one file.
pub fn os_error(error: &io::Error, path: &str) -> String {
    match error.raw_os_error() {
        Some(code) => {
            let text = io::Error::from_raw_os_error(code).to_string();
            let strerror = text
                .strip_suffix(&format!(" (os error {code})"))
                .unwrap_or(&text)
                .to_string();
            format!("[Errno {code}] {strerror}: {}", repr_str(path))
        }
        None => format!("{error}: {}", repr_str(path)),
    }
}

/// The message of a UnicodeDecodeError from the 'utf-8' codec, or None.
pub fn utf8_error(bytes: &[u8]) -> Option<String> {
    let error = std::str::from_utf8(bytes).err()?;
    let start = error.valid_up_to();
    let (end, reason) = match error.error_len() {
        None => (bytes.len(), "unexpected end of data"),
        Some(n) => {
            let first = bytes[start];
            let starts = matches!(first, 0xc2..=0xf4);
            (
                start + n,
                if starts {
                    "invalid continuation byte"
                } else {
                    "invalid start byte"
                },
            )
        }
    };
    Some(if end - start == 1 {
        format!(
            "'utf-8' codec can't decode byte 0x{:02x} in position {start}: {reason}",
            bytes[start]
        )
    } else {
        format!(
            "'utf-8' codec can't decode bytes in position {start}-{}: {reason}",
            end - 1
        )
    })
}

/// Universal newlines: `\r\n` and a lone `\r` both read as `\n`.
pub fn translate_newlines(text: &str) -> String {
    if !text.contains('\r') {
        return text.to_string();
    }
    text.replace("\r\n", "\n").replace('\r', "\n")
}

/// `open(path, encoding="utf-8").read()`.
pub fn read_text(path: &str) -> Result<String, ReadError> {
    let bytes =
        fs::read(path).map_err(|e| ReadError::Os(os_error(&e, path), os_error_class(&e)))?;
    if let Some(message) = utf8_error(&bytes) {
        return Err(ReadError::Decode(message));
    }
    Ok(translate_newlines(std::str::from_utf8(&bytes).unwrap()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn repr_of_strings_picks_quotes_and_escapes_like_python() {
        assert_eq!(repr_str("gems"), "'gems'");
        assert_eq!(repr_str("it's"), "\"it's\"");
        assert_eq!(repr_str("a'b\"c"), "'a\\'b\"c'");
        assert_eq!(repr_str("a\tb\n\u{1}é"), "'a\\tb\\n\\x01é'");
        assert_eq!(repr_tuple(&["a".into()]), "('a',)");
        assert_eq!(repr_tuple(&["a".into(), "b".into()]), "('a', 'b')");
    }

    #[test]
    fn floats_print_as_python_prints_them() {
        for (f, want) in [
            (1.0, "1.0"),
            (0.1, "0.1"),
            (1.5e16, "1.5e+16"),
            (1e-5, "1e-05"),
            (0.0001, "0.0001"),
            (123456.789, "123456.789"),
            (-2.5, "-2.5"),
            (1e22, "1e+22"),
        ] {
            assert_eq!(repr_float(f), want, "{f}");
        }
    }

    #[test]
    fn paths_follow_posixpath() {
        assert_eq!(
            normpath("packages/sdk/./kits/../kits/ts/package.json"),
            "packages/sdk/kits/ts/package.json"
        );
        assert_eq!(normpath(""), ".");
        assert_eq!(normpath("../a"), "../a");
        assert_eq!(normpath("//a//b"), "//a/b");
        assert_eq!(normpath("///a"), "/a");
        assert_eq!(join("", "package.json"), "package.json");
        assert_eq!(join("a/", "b"), "a/b");
        assert_eq!(join("a", "/b"), "/b");
        assert_eq!(dirname("release-please-config.json"), "");
        assert_eq!(dirname("a/b/c"), "a/b");
        assert_eq!(dirname("/x"), "/");
        assert_eq!(basename("a/b/Cargo.toml"), "Cargo.toml");
    }

    #[test]
    fn quote_and_hostname_follow_urllib() {
        assert_eq!(
            quote("@vitruviansoftware/tool-kit", "@"),
            "@vitruviansoftware%2Ftool-kit"
        );
        assert_eq!(quote("a b/é", "/"), "a%20b/%C3%A9");
        assert_eq!(
            split_url("https://crates.io/api").1.as_deref(),
            Some("crates.io")
        );
        assert_eq!(
            split_url("https://u@Crates.IO:443/x").1.as_deref(),
            Some("crates.io")
        );
        assert_eq!(split_url("http://crates.io/x").0, "http");
        assert_eq!(
            split_url("https://crates.io.example.com/x").1.as_deref(),
            Some("crates.io.example.com")
        );
    }

    #[test]
    fn decode_errors_read_as_python_s() {
        assert_eq!(
            utf8_error(b"ab\xffc").unwrap(),
            "'utf-8' codec can't decode byte 0xff in position 2: invalid start byte"
        );
        assert_eq!(
            utf8_error(b"\xe2\x28").unwrap(),
            "'utf-8' codec can't decode byte 0xe2 in position 0: invalid continuation byte"
        );
        assert_eq!(
            utf8_error(b"x\xe2\x82").unwrap(),
            "'utf-8' codec can't decode bytes in position 1-2: unexpected end of data"
        );
        assert_eq!(utf8_error("ok".as_bytes()), None);
    }

    #[test]
    fn a_missing_file_is_python_s_oserror() {
        let error = read_text("/nonexistent/registry-trust").unwrap_err();
        assert_eq!(
            error.to_string(),
            "[Errno 2] No such file or directory: '/nonexistent/registry-trust'"
        );
    }

    #[test]
    fn newlines_are_universal() {
        assert_eq!(translate_newlines("a\r\nb\rc\n"), "a\nb\nc\n");
    }
}
