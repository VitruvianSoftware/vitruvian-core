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

//! Python string semantics the guard depends on: character classes as
//! Python's `str` methods and `re` see them, and the handful of `str`
//! operations (strip, split, splitlines, slicing by character) whose
//! behaviour differs from Rust's.

use crate::unicode_tables::{PY_DIGIT, PY_SPACE, RE_DIGIT, RE_WORD};

fn in_table(table: &[(u32, u32)], c: char) -> bool {
    let cp = c as u32;
    table
        .binary_search_by(|&(lo, hi)| {
            if hi < cp {
                std::cmp::Ordering::Less
            } else if lo > cp {
                std::cmp::Ordering::Greater
            } else {
                std::cmp::Ordering::Equal
            }
        })
        .is_ok()
}

/// `str.isspace()` for one character; also `re`'s `\s`.
pub fn is_space(c: char) -> bool {
    if c.is_ascii() {
        return matches!(
            c,
            '\t' | '\n' | '\x0b' | '\x0c' | '\r' | '\x1c'..='\x1f' | ' '
        );
    }
    in_table(&PY_SPACE, c)
}

/// `str.isdigit()` for one character.
pub fn is_digit(c: char) -> bool {
    if c.is_ascii() {
        return c.is_ascii_digit();
    }
    in_table(&PY_DIGIT, c)
}

/// `re`'s `\d` (Unicode decimal digits).
pub fn is_decimal(c: char) -> bool {
    if c.is_ascii() {
        return c.is_ascii_digit();
    }
    in_table(&RE_DIGIT, c)
}

/// `re`'s `\w`.
pub fn is_word(c: char) -> bool {
    if c.is_ascii() {
        return c.is_ascii_alphanumeric() || c == '_';
    }
    in_table(&RE_WORD, c)
}

/// `s.isdigit()`: non-empty and every character a digit.
pub fn str_isdigit(s: &str) -> bool {
    !s.is_empty() && s.chars().all(is_digit)
}

pub fn py_strip(s: &str) -> &str {
    s.trim_matches(is_space)
}

pub fn py_lstrip(s: &str) -> &str {
    s.trim_start_matches(is_space)
}

/// `s.split()` with no separator.
pub fn py_split_ws(s: &str) -> Vec<String> {
    s.split(is_space)
        .filter(|w| !w.is_empty())
        .map(|w| w.to_string())
        .collect()
}

/// `s.splitlines()`.
pub fn py_splitlines(s: &str) -> Vec<String> {
    let chars: Vec<char> = s.chars().collect();
    let mut out = Vec::new();
    let mut start = 0;
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        let is_break = matches!(
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
        if is_break {
            out.push(chars[start..i].iter().collect());
            if c == '\r' && i + 1 < chars.len() && chars[i + 1] == '\n' {
                i += 1;
            }
            start = i + 1;
        }
        i += 1;
    }
    if start < chars.len() {
        out.push(chars[start..].iter().collect());
    }
    out
}

/// What reading a file in Python's text mode does to line endings.
pub fn universal_newlines(s: &str) -> String {
    if !s.contains('\r') {
        return s.to_string();
    }
    s.replace("\r\n", "\n").replace('\r', "\n")
}

/// `for line in fh`: lines with their "\n" kept (after universal newlines).
pub fn text_lines(s: &str) -> Vec<String> {
    s.split_inclusive('\n').map(|l| l.to_string()).collect()
}

pub fn char_len(s: &str) -> usize {
    s.chars().count()
}

/// `s[:n]` by characters.
pub fn take_chars(s: &str, n: usize) -> String {
    s.chars().take(n).collect()
}

/// A character slice as a String.
pub fn cs(chars: &[char]) -> String {
    chars.iter().collect()
}

pub fn chars(s: &str) -> Vec<char> {
    s.chars().collect()
}

/// Does `t[i..]` start with `pat`?
pub fn starts_at(t: &[char], i: usize, pat: &str) -> bool {
    let mut k = i;
    for p in pat.chars() {
        if k >= t.len() || t[k] != p {
            return false;
        }
        k += 1;
    }
    true
}

/// `t.find(c, from)` by characters.
pub fn find_char(t: &[char], c: char, from: usize) -> Option<usize> {
    if from >= t.len() {
        return None;
    }
    t[from..].iter().position(|&x| x == c).map(|p| p + from)
}

/// `t.find(pat, from)` by characters.
pub fn find_str(t: &[char], pat: &str, from: usize) -> Option<usize> {
    let p: Vec<char> = pat.chars().collect();
    if p.is_empty() {
        return if from <= t.len() { Some(from) } else { None };
    }
    if t.len() < p.len() {
        return None;
    }
    let mut i = from;
    while i + p.len() <= t.len() {
        if t[i] == p[0] && t[i..i + p.len()] == p[..] {
            return Some(i);
        }
        i += 1;
    }
    None
}

/// `re`'s `$` (no MULTILINE): the end, or just before a final newline.
pub fn dollar(t: &[char], pos: usize) -> bool {
    pos == t.len() || (pos + 1 == t.len() && t[pos] == '\n')
}

/// `re`'s `\b` at pos.
pub fn word_boundary(t: &[char], pos: usize) -> bool {
    let before = pos > 0 && is_word(t[pos - 1]);
    let after = pos < t.len() && is_word(t[pos]);
    before != after
}

/// The characters Python's IGNORECASE matching folds onto an ASCII letter
/// besides its two cases (checked against Python 3.12's `re`).
fn ci_extra(c: char) -> Option<char> {
    match c {
        '\u{130}' | '\u{131}' => Some('i'),
        '\u{17f}' => Some('s'),
        '\u{212a}' => Some('k'),
        _ => None,
    }
}

/// Does c match the ASCII letter or other ASCII char `lit` under `(?i)`?
pub fn ci_eq(c: char, lit: char) -> bool {
    if c == lit {
        return true;
    }
    if lit.is_ascii_alphabetic() {
        if c.is_ascii() {
            return c.to_ascii_lowercase() == lit.to_ascii_lowercase();
        }
        return ci_extra(c) == Some(lit.to_ascii_lowercase());
    }
    false
}

/// `(?i)` literal match of the ASCII `pat` at `t[i..]`.
pub fn ci_starts_at(t: &[char], i: usize, pat: &str) -> bool {
    let mut k = i;
    for p in pat.chars() {
        if k >= t.len() || !ci_eq(t[k], p) {
            return false;
        }
        k += 1;
    }
    true
}

/// `(?i)[A-Za-z]` for one character.
pub fn ci_alpha(c: char) -> bool {
    c.is_ascii_alphabetic() || ci_extra(c).is_some()
}

/// Python's `str.upper()`.
pub fn py_upper(s: &str) -> String {
    s.to_uppercase()
}

/// Python's `str.lower()`.
pub fn py_lower(s: &str) -> String {
    s.to_lowercase()
}

/// `s.split(sep, 1)` as (head, Some(tail)) or (s, None).
pub fn split1(s: &str, sep: char) -> (&str, Option<&str>) {
    match s.find(sep) {
        Some(i) => (&s[..i], Some(&s[i + sep.len_utf8()..])),
        None => (s, None),
    }
}

/// `re.match(r"^python3(\.\d+)?$", s)`.
pub fn is_python3_dotted(s: &str) -> bool {
    let t = chars(s);
    if !starts_at(&t, 0, "python3") {
        return false;
    }
    let mut i = 7;
    if dollar(&t, i) {
        return true;
    }
    if i < t.len() && t[i] == '.' {
        let j = i + 1;
        i = j;
        while i < t.len() && is_decimal(t[i]) {
            i += 1;
        }
        if i > j && dollar(&t, i) {
            return true;
        }
    }
    false
}

/// `re.match(r"^python(3(\.\d+)?)?$", s)`.
pub fn is_python_prog(s: &str) -> bool {
    let t = chars(s);
    if !starts_at(&t, 0, "python") {
        return false;
    }
    if dollar(&t, 6) {
        return true;
    }
    is_python3_dotted(s)
}

/// `re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", s)`.
pub fn is_assignment(s: &str) -> bool {
    let mut it = s.chars();
    match it.next() {
        Some(c) if c.is_ascii_alphabetic() || c == '_' => {}
        _ => return false,
    }
    for c in it {
        if c == '=' {
            return true;
        }
        if !(c.is_ascii_alphanumeric() || c == '_') {
            return false;
        }
    }
    false
}

/// Python's `repr(str)`.
pub fn py_repr_str(s: &str) -> String {
    let quote = if s.contains('\'') && !s.contains('"') {
        '"'
    } else {
        '\''
    };
    let mut out = String::new();
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
            c if !printable(c) => {
                let cp = c as u32;
                if cp < 0x100 {
                    out.push_str(&format!("\\x{:02x}", cp));
                } else if cp < 0x10000 {
                    out.push_str(&format!("\\u{:04x}", cp));
                } else {
                    out.push_str(&format!("\\U{:08x}", cp));
                }
            }
            c => out.push(c),
        }
    }
    out.push(quote);
    out
}

/// An approximation of `str.isprintable()` for one character: controls,
/// separators other than space, and the common format characters are not.
fn printable(c: char) -> bool {
    if c == ' ' {
        return true;
    }
    if c.is_control() || is_space(c) {
        return false;
    }
    !matches!(c as u32, 0xAD | 0x600..=0x605 | 0x61C | 0x6DD | 0x70F | 0x180E | 0x200B..=0x200F
        | 0x202A..=0x202E | 0x2060..=0x2064 | 0x2066..=0x206F | 0xFEFF | 0xFFF9..=0xFFFB
        | 0xE000..=0xF8FF | 0xF0000..=0x10FFFF)
}

/// Python's `repr(float)` (also what `json.dumps` writes for a finite float).
pub fn py_float_repr(f: f64) -> String {
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
    let e = format!("{:e}", f);
    let (mant, exp) = e.split_once('e').unwrap();
    let exp: i32 = exp.parse().unwrap();
    let neg = mant.starts_with('-');
    let digits: String = mant.chars().filter(|c| c.is_ascii_digit()).collect();
    let mut out = String::new();
    if neg {
        out.push('-');
    }
    if (-4..16).contains(&exp) {
        let point = exp + 1; // digits before the decimal point
        if point <= 0 {
            out.push_str("0.");
            for _ in 0..(-point) {
                out.push('0');
            }
            out.push_str(&digits);
        } else {
            let p = point as usize;
            if digits.len() <= p {
                out.push_str(&digits);
                for _ in 0..(p - digits.len()) {
                    out.push('0');
                }
                out.push_str(".0");
            } else {
                out.push_str(&digits[..p]);
                out.push('.');
                out.push_str(&digits[p..]);
            }
        }
    } else {
        out.push_str(&digits[..1]);
        if digits.len() > 1 {
            out.push('.');
            out.push_str(&digits[1..]);
        }
        out.push('e');
        out.push(if exp < 0 { '-' } else { '+' });
        out.push_str(&format!("{:02}", exp.abs()));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn float_repr_matches_python() {
        for (f, want) in [
            (1.0, "1.0"),
            (0.1, "0.1"),
            (1e16, "1e+16"),
            (1e15, "1000000000000000.0"),
            (0.0001, "0.0001"),
            (0.00001, "1e-05"),
            (-2.5, "-2.5"),
            (123.456, "123.456"),
            (1.5e300, "1.5e+300"),
        ] {
            assert_eq!(py_float_repr(f), want);
        }
    }

    #[test]
    fn classes() {
        assert!(is_space('\u{a0}') && is_space('\x1c') && !is_space('\u{200b}'));
        assert!(is_digit('²') && !is_decimal('²') && is_decimal('٣'));
        assert!(is_word('é') && !is_word('-'));
        assert!(ci_eq('K', 'K') && ci_eq('\u{212a}', 'k') && ci_eq('\u{17f}', 'S'));
    }

    #[test]
    fn splitlines_and_dollar() {
        assert_eq!(py_splitlines("a\r\nb\rc\n"), vec!["a", "b", "c"]);
        assert!(dollar(&chars("ab\n"), 2) && !dollar(&chars("ab\n\n"), 2));
        assert!(
            is_python_prog("python3.12") && is_python_prog("python") && !is_python_prog("python2")
        );
        assert!(is_assignment("A_1=x") && !is_assignment("1A=x") && !is_assignment("A"));
    }
}
