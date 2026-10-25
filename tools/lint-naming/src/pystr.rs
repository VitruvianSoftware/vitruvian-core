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

//! Python `str` behaviour the linter relies on: whitespace, `strip`,
//! `splitlines`, `repr`, `int()`, `json.dumps` string escaping, and the
//! character classes of `re`.
//!
//! Python strings may hold lone surrogates (a file name that is not UTF-8
//! decodes to them under `surrogateescape`, and `"\ud800"` is a legal
//! literal). Rust strings cannot, so a surrogate U+D800+k is carried as the
//! private-use character U+10F800+k and turned back when printed.

use crate::unicode_tables;

/// First private-use character standing in for a surrogate.
pub const SURROGATE_BASE: u32 = 0x10F800;

fn in_table(table: &[(u32, u32)], c: char) -> bool {
    let c = c as u32;
    table
        .binary_search_by(|&(lo, hi)| {
            if hi < c {
                std::cmp::Ordering::Less
            } else if lo > c {
                std::cmp::Ordering::Greater
            } else {
                std::cmp::Ordering::Equal
            }
        })
        .is_ok()
}

/// The surrogate a stand-in character represents, if it is one.
pub fn surrogate_of(c: char) -> Option<u32> {
    let v = c as u32;
    if v >= SURROGATE_BASE {
        Some(0xD800 + (v - SURROGATE_BASE))
    } else {
        None
    }
}

/// The stand-in character for surrogate `s` (0xD800..=0xDFFF).
pub fn surrogate_char(s: u32) -> char {
    char::from_u32(SURROGATE_BASE + (s - 0xD800)).unwrap_or('\u{FFFD}')
}

/// The code point Python sees: stand-ins compare as their surrogates.
pub fn code_point(c: char) -> u32 {
    surrogate_of(c).unwrap_or(c as u32)
}

/// `str.isspace()`, and `re`'s `\s`.
pub fn is_space(c: char) -> bool {
    surrogate_of(c).is_none() && in_table(unicode_tables::SPACE, c)
}

/// `str.isdecimal()`, and `re`'s `\d`.
pub fn is_decimal(c: char) -> bool {
    surrogate_of(c).is_none() && in_table(unicode_tables::DECIMAL, c)
}

/// The value `int()` reads for a decimal digit.
pub fn decimal_value(c: char) -> Option<u32> {
    if surrogate_of(c).is_some() {
        return None;
    }
    let v = c as u32;
    unicode_tables::DECIMAL
        .iter()
        .find(|&&(lo, hi)| lo <= v && v <= hi)
        .map(|&(lo, _)| (v - lo) % 10)
}

/// `str.isdigit()`.
pub fn is_digit(c: char) -> bool {
    surrogate_of(c).is_none() && in_table(unicode_tables::DIGIT, c)
}

/// `str.isprintable()` for one character.
pub fn is_printable(c: char) -> bool {
    surrogate_of(c).is_none() && in_table(unicode_tables::PRINTABLE, c)
}

/// May a Python identifier start with `c`?
pub fn is_xid_start(c: char) -> bool {
    surrogate_of(c).is_none() && in_table(unicode_tables::XID_START, c)
}

/// May a Python identifier continue with `c`?
pub fn is_xid_continue(c: char) -> bool {
    surrogate_of(c).is_none() && in_table(unicode_tables::XID_CONTINUE, c)
}

/// `s.strip()`.
pub fn strip(s: &str) -> &str {
    s.trim_matches(is_space)
}

/// `s.lstrip()`.
pub fn lstrip(s: &str) -> &str {
    s.trim_start_matches(is_space)
}

/// `s.strip(chars)`.
pub fn strip_chars<'a>(s: &'a str, chars: &str) -> &'a str {
    s.trim_matches(|c| chars.contains(c))
}

/// `len(s)`: Python counts code points.
pub fn py_len(s: &str) -> usize {
    s.chars().count()
}

/// `s.lower()`. Stand-ins for surrogates have no case and stay as they are.
pub fn lower(s: &str) -> String {
    s.to_lowercase()
}

/// `s.upper()`.
pub fn upper(s: &str) -> String {
    s.to_uppercase()
}

/// `s.splitlines()`: the pieces between Python's line boundaries.
pub fn splitlines(s: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let mut start = 0;
    let mut it = s.char_indices().peekable();
    while let Some((i, c)) = it.next() {
        let boundary = matches!(
            c,
            '\n' | '\r'
                | '\x0b'
                | '\x0c'
                | '\x1c'
                | '\x1d'
                | '\x1e'
                | '\u{85}'
                | '\u{2028}'
                | '\u{2029}'
        );
        if boundary {
            out.push(&s[start..i]);
            let mut next = i + c.len_utf8();
            if c == '\r' {
                if let Some(&(j, '\n')) = it.peek() {
                    it.next();
                    next = j + 1;
                }
            }
            start = next;
        }
    }
    if start < s.len() {
        out.push(&s[start..]);
    }
    out
}

/// Compare two strings the way Python orders `str`: by code point.
pub fn cmp_str(a: &str, b: &str) -> std::cmp::Ordering {
    a.chars().map(code_point).cmp(b.chars().map(code_point))
}

/// `repr(s)` for a `str`.
pub fn repr(s: &str) -> String {
    let quote = if s.contains('\'') && !s.contains('"') {
        '"'
    } else {
        '\''
    };
    let mut out = String::with_capacity(s.len() + 2);
    out.push(quote);
    for c in s.chars() {
        if let Some(sur) = surrogate_of(c) {
            out.push_str(&format!("\\u{:04x}", sur));
            continue;
        }
        match c {
            '\\' => out.push_str("\\\\"),
            '\t' => out.push_str("\\t"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            _ if c == quote => {
                out.push('\\');
                out.push(c);
            }
            _ if (c as u32) < 0x7f && (c as u32) >= 0x20 => out.push(c),
            _ if is_printable(c) => out.push(c),
            _ => {
                let v = c as u32;
                if v < 0x100 {
                    out.push_str(&format!("\\x{:02x}", v));
                } else if v < 0x10000 {
                    out.push_str(&format!("\\u{:04x}", v));
                } else {
                    out.push_str(&format!("\\U{:08x}", v));
                }
            }
        }
    }
    out.push(quote);
    out
}

/// A string as `json.dumps(..., ensure_ascii=False)` writes it.
pub fn json_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\x08' => out.push_str("\\b"),
            '\x0c' => out.push_str("\\f"),
            _ if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            _ => out.push(c),
        }
    }
    out.push('"');
    out
}

/// `int(s)` for base 10: surrounding whitespace, a sign, Unicode decimal
/// digits and single underscores between them. Saturates rather than
/// growing without bound.
pub fn parse_int(s: &str) -> Option<i64> {
    let t = strip(s);
    let mut chars = t.chars().peekable();
    let mut neg = false;
    if let Some(&c) = chars.peek() {
        if c == '+' || c == '-' {
            neg = c == '-';
            chars.next();
        }
    }
    let mut value: i64 = 0;
    let mut digits = 0usize;
    let mut last_underscore = false;
    for c in chars {
        if c == '_' {
            if digits == 0 || last_underscore {
                return None;
            }
            last_underscore = true;
            continue;
        }
        let d = decimal_value(c)?;
        value = value.saturating_mul(10).saturating_add(d as i64);
        digits += 1;
        last_underscore = false;
    }
    if digits == 0 || last_underscore {
        return None;
    }
    Some(if neg { -value } else { value })
}

/// Python's `$` also matches just before a final newline, so `re.match(r"^X$", s)`
/// holds when X matches all of `s`, or all of `s` but a trailing `\n`.
pub fn dollar(s: &str, matches: impl Fn(&str) -> bool) -> bool {
    matches(s) || (s.ends_with('\n') && matches(&s[..s.len() - 1]))
}

/// `[a-z0-9]`
pub fn is_lower_alnum(c: char) -> bool {
    c.is_ascii_lowercase() || c.is_ascii_digit()
}

/// `[A-Z0-9]`
pub fn is_upper_alnum(c: char) -> bool {
    c.is_ascii_uppercase() || c.is_ascii_digit()
}

/// `[a-z0-9]+(<sep>[a-z0-9]+)*` over the whole string.
pub fn separated(s: &str, sep: char, class: fn(char) -> bool) -> bool {
    !s.is_empty()
        && s.split(sep)
            .all(|seg| !seg.is_empty() && seg.chars().all(class))
}

/// `^[a-z0-9]+(-[a-z0-9]+)*$`
pub fn is_kebab(s: &str) -> bool {
    dollar(s, |t| separated(t, '-', is_lower_alnum))
}

/// `^[a-z0-9]+(_[a-z0-9]+)*$`
pub fn is_snake(s: &str) -> bool {
    dollar(s, |t| separated(t, '_', is_lower_alnum))
}

/// `[A-Z][a-zA-Z0-9]*` over the whole string.
pub fn pascal_body(s: &str) -> bool {
    let mut it = s.chars();
    match it.next() {
        Some(c) if c.is_ascii_uppercase() => it.all(|c| c.is_ascii_alphanumeric()),
        _ => false,
    }
}

/// `^[A-Z][a-zA-Z0-9]*$`
pub fn is_pascal(s: &str) -> bool {
    dollar(s, pascal_body)
}

/// Python's `os.path.basename` on a `/`-separated path.
pub fn basename(p: &str) -> &str {
    match p.rfind('/') {
        Some(i) => &p[i + 1..],
        None => p,
    }
}

/// The extension `os.path.splitext` finds: from the last dot, unless every
/// character before it is a dot.
pub fn splitext_ext(name: &str) -> &str {
    let base_start = name.rfind('/').map(|i| i + 1).unwrap_or(0);
    let base = &name[base_start..];
    if let Some(dot) = base.rfind('.') {
        if base[..dot].chars().any(|c| c != '.') {
            return &base[dot..];
        }
    }
    ""
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn whitespace_matches_python() {
        assert!(is_space('\x1c'));
        assert!(is_space('\u{3000}'));
        assert!(!is_space('\u{200b}'));
        assert_eq!(strip("\x1f a \u{85}"), "a");
        assert_eq!(lstrip("  a "), "a ");
    }

    #[test]
    fn splitlines_matches_python() {
        assert_eq!(
            splitlines("a\nb\r\nc\rd\x0be\u{2028}f"),
            ["a", "b", "c", "d", "e", "f"]
        );
        assert_eq!(splitlines("a\n"), ["a"]);
        assert_eq!(splitlines("\n\n"), ["", ""]);
        assert!(splitlines("").is_empty());
    }

    #[test]
    fn repr_matches_python() {
        assert_eq!(repr("abc"), "'abc'");
        assert_eq!(repr("it's"), "\"it's\"");
        assert_eq!(repr("a'\""), "'a\\'\"'");
        assert_eq!(repr("\n\x00\u{7f}é\u{200b}"), "'\\n\\x00\\x7fé\\u200b'");
        assert_eq!(repr(&surrogate_char(0xDCFF).to_string()), "'\\udcff'");
    }

    #[test]
    fn json_matches_python() {
        assert_eq!(json_string("a\"\\\n\x01🚀"), "\"a\\\"\\\\\\n\\u0001🚀\"");
    }

    #[test]
    fn int_matches_python() {
        assert_eq!(parse_int(" 40 "), Some(40));
        assert_eq!(parse_int("4_0"), Some(40));
        assert_eq!(parse_int("٤٠"), Some(40));
        assert_eq!(parse_int("-3"), Some(-3));
        assert_eq!(parse_int("_4"), None);
        assert_eq!(parse_int("4__0"), None);
        assert_eq!(parse_int(""), None);
        assert_eq!(parse_int("4x"), None);
    }

    #[test]
    fn dollar_allows_a_final_newline() {
        assert!(is_kebab("abc\n"));
        assert!(!is_kebab("abc\n\n"));
        assert!(!is_kebab("a--b"));
        assert!(is_snake("a_1"));
        assert!(is_pascal("Abc1"));
        assert!(!is_pascal("abc"));
    }

    #[test]
    fn splitext_matches_python() {
        assert_eq!(splitext_ext("a.tar.gz"), ".gz");
        assert_eq!(splitext_ext(".bashrc"), "");
        assert_eq!(splitext_ext("..sh"), "");
        assert_eq!(splitext_ext("a."), ".");
        assert_eq!(splitext_ext("noext"), "");
    }
}
