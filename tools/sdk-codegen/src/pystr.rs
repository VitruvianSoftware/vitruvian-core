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

//! Python's `str` where Rust's differs: lengths in code points, what counts as
//! upper case, a digit or whitespace, how `upper`, `lower` and `capitalize`
//! map, and how `repr` quotes. The facts come from Python 3.12 itself, by
//! way of src/unicode_tables.rs.

use crate::unicode_tables as t;

fn in_ranges(table: &[(u32, u32)], c: char) -> bool {
    let cp = c as u32;
    let idx = table.partition_point(|&(lo, _)| lo <= cp);
    idx > 0 && cp <= table[idx - 1].1
}

fn mapped(table: &'static [(u32, &'static str)], c: char) -> Option<&'static str> {
    let cp = c as u32;
    table
        .binary_search_by_key(&cp, |&(k, _)| k)
        .ok()
        .map(|i| table[i].1)
}

/// `str.isspace()` of one character, which is also `\s`.
pub fn is_space(c: char) -> bool {
    in_ranges(t::SPACE, c)
}

/// `\w` in a str pattern.
pub fn is_word(c: char) -> bool {
    in_ranges(t::WORD, c)
}

/// `str.isdecimal()` of one character, which is also `\d`.
pub fn is_decimal(c: char) -> bool {
    in_ranges(t::DECIMAL, c)
}

/// `str.isdigit()` of one character.
pub fn is_digit(c: char) -> bool {
    in_ranges(t::DIGIT, c)
}

/// `str.isalpha()` of one character.
pub fn is_alpha(c: char) -> bool {
    in_ranges(t::ALPHA, c)
}

/// `str.isupper()` of one character.
pub fn is_upper(c: char) -> bool {
    in_ranges(t::UPPER, c)
}

/// `str.islower()` of one character.
pub fn is_lower(c: char) -> bool {
    in_ranges(t::LOWER, c)
}

/// `str.isprintable()` of one character.
pub fn is_printable(c: char) -> bool {
    in_ranges(t::PRINTABLE, c)
}

/// `str.isidentifier()`.
pub fn is_identifier(s: &str) -> bool {
    let mut chars = s.chars();
    match chars.next() {
        None => false,
        Some(first) => in_ranges(t::ID_START, first) && chars.all(|c| in_ranges(t::ID_CONTINUE, c)),
    }
}

/// `c.upper()` for one character.
pub fn upper_char(c: char) -> String {
    match mapped(t::UPPER_MAP, c) {
        Some(m) => m.to_string(),
        None => c.to_string(),
    }
}

/// `c.lower()` for one character, which no final sigma touches.
pub fn lower_char(c: char) -> String {
    match mapped(t::LOWER_MAP, c) {
        Some(m) => m.to_string(),
        None => c.to_string(),
    }
}

/// `s.upper()`.
pub fn upper(s: &str) -> String {
    s.chars().map(upper_char).collect()
}

/// `s.lower()` with the final sigma rule, as CPython's lower_ucs4 does it.
pub fn lower(s: &str) -> String {
    let chars: Vec<char> = s.chars().collect();
    let mut out = String::new();
    for (i, &c) in chars.iter().enumerate() {
        out.push_str(&lower_at(&chars, i, c));
    }
    out
}

fn lower_at(chars: &[char], i: usize, c: char) -> String {
    if c == '\u{3a3}' {
        return if final_sigma(chars, i) {
            "\u{3c2}".into()
        } else {
            "\u{3c3}".into()
        };
    }
    lower_char(c)
}

fn final_sigma(chars: &[char], i: usize) -> bool {
    let mut j = i as isize - 1;
    while j >= 0 && in_ranges(t::CASE_IGNORABLE, chars[j as usize]) {
        j -= 1;
    }
    let before = j >= 0 && in_ranges(t::CASED, chars[j as usize]);
    if !before {
        return false;
    }
    let mut k = i + 1;
    while k < chars.len() && in_ranges(t::CASE_IGNORABLE, chars[k]) {
        k += 1;
    }
    k == chars.len() || !in_ranges(t::CASED, chars[k])
}

/// `s.capitalize()`: the first character in title case, the rest lower.
pub fn capitalize(s: &str) -> String {
    let chars: Vec<char> = s.chars().collect();
    let mut out = String::new();
    for (i, &c) in chars.iter().enumerate() {
        if i == 0 {
            match mapped(t::TITLE_MAP, c) {
                Some(m) => out.push_str(m),
                None => out.push(c),
            }
        } else {
            out.push_str(&lower_at(&chars, i, c));
        }
    }
    out
}

/// `len(s)`.
pub fn len(s: &str) -> usize {
    s.chars().count()
}

/// `s[a:b]` on code points, clamped as a slice is.
pub fn slice(s: &str, a: usize, b: usize) -> String {
    s.chars().skip(a).take(b.saturating_sub(a)).collect()
}

/// `s.ljust(width)`.
pub fn ljust(s: &str, width: usize) -> String {
    let n = len(s);
    let mut out = s.to_string();
    for _ in n..width {
        out.push(' ');
    }
    out
}

/// `s.strip()` with no argument.
pub fn strip(s: &str) -> &str {
    s.trim_matches(is_space)
}

/// `s.rstrip()` with no argument.
pub fn rstrip(s: &str) -> &str {
    s.trim_end_matches(is_space)
}

/// `s.expandtabs(tabsize)`.
pub fn expandtabs(s: &str, tabsize: usize) -> String {
    let mut out = String::new();
    let mut col = 0usize;
    for c in s.chars() {
        match c {
            '\t' => {
                if tabsize > 0 {
                    let n = tabsize - col % tabsize;
                    for _ in 0..n {
                        out.push(' ');
                    }
                    col += n;
                }
            }
            '\n' | '\r' => {
                out.push(c);
                col = 0;
            }
            c => {
                out.push(c);
                col += 1;
            }
        }
    }
    out
}

/// Whether `c` ends a line for `str.splitlines`.
pub fn is_line_break(c: char) -> bool {
    matches!(
        c as u32,
        0x0A | 0x0B | 0x0C | 0x0D | 0x1C | 0x1D | 0x1E | 0x85 | 0x2028 | 0x2029
    )
}

/// `s.splitlines(keepends)`.
pub fn splitlines(s: &str, keepends: bool) -> Vec<String> {
    let chars: Vec<char> = s.chars().collect();
    let mut out = Vec::new();
    let mut start = 0;
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if is_line_break(c) {
            let mut end = i + 1;
            if c == '\r' && i + 1 < chars.len() && chars[i + 1] == '\n' {
                end += 1;
            }
            let stop = if keepends { end } else { i };
            out.push(chars[start..stop].iter().collect());
            start = end;
            i = end;
        } else {
            i += 1;
        }
    }
    if start < chars.len() {
        out.push(chars[start..].iter().collect());
    }
    out
}

/// `repr(s)` for a str.
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
            '\t' => out.push_str("\\t"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            c if c == quote => {
                out.push('\\');
                out.push(c);
            }
            c if (c as u32) < 0x20 || c as u32 == 0x7f => {
                out.push_str(&format!("\\x{:02x}", c as u32));
            }
            c if (c as u32) < 0x7f => out.push(c),
            c if !is_printable(c) => {
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

/// `repr(x)` (and `str(x)`) for a float.
pub fn repr_float(x: f64) -> String {
    if x.is_nan() {
        return "nan".into();
    }
    if x.is_infinite() {
        return if x > 0.0 { "inf".into() } else { "-inf".into() };
    }
    if x == 0.0 {
        return if x.is_sign_negative() {
            "-0.0".into()
        } else {
            "0.0".into()
        };
    }
    // Rust's {:e} gives the shortest digits that read back, as repr does.
    let sci = format!("{:e}", x);
    let (mant, exp) = sci.split_once('e').unwrap();
    let exp: i32 = exp.parse().unwrap();
    let (neg, mant) = match mant.strip_prefix('-') {
        Some(m) => (true, m),
        None => (false, mant),
    };
    let digits: String = mant.chars().filter(|c| *c != '.').collect();
    let decpt = exp + 1;
    let mut out = String::new();
    if neg {
        out.push('-');
    }
    if !(-4 < decpt && decpt <= 16) {
        out.push_str(&digits[..1]);
        if digits.len() > 1 {
            out.push('.');
            out.push_str(&digits[1..]);
        }
        out.push('e');
        out.push(if exp < 0 { '-' } else { '+' });
        out.push_str(&format!("{:02}", exp.abs()));
    } else if decpt <= 0 {
        out.push_str("0.");
        for _ in 0..(-decpt) {
            out.push('0');
        }
        out.push_str(&digits);
    } else {
        let d = decpt as usize;
        if digits.len() <= d {
            out.push_str(&digits);
            for _ in digits.len()..d {
                out.push('0');
            }
            out.push_str(".0");
        } else {
            out.push_str(&digits[..d]);
            out.push('.');
            out.push_str(&digits[d..]);
        }
    }
    out
}

/// Python 3.12's keywords (`keyword.iskeyword`).
pub fn is_keyword(s: &str) -> bool {
    matches!(
        s,
        "False"
            | "None"
            | "True"
            | "and"
            | "as"
            | "assert"
            | "async"
            | "await"
            | "break"
            | "class"
            | "continue"
            | "def"
            | "del"
            | "elif"
            | "else"
            | "except"
            | "finally"
            | "for"
            | "from"
            | "global"
            | "if"
            | "import"
            | "in"
            | "is"
            | "lambda"
            | "nonlocal"
            | "not"
            | "or"
            | "pass"
            | "raise"
            | "return"
            | "try"
            | "while"
            | "with"
            | "yield"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cases() {
        assert!(is_upper('A'));
        assert!(!is_upper('a'));
        assert!(!is_upper('1'));
        assert!(is_lower('\u{df}'));
        assert_eq!(upper("stra\u{df}e"), "STRASSE");
        assert_eq!(lower_char('\u{130}'), "i\u{307}");
        assert_eq!(lower("A\u{3a3}"), "a\u{3c2}");
        assert_eq!(lower("\u{3a3}"), "\u{3c3}");
        assert_eq!(lower("A\u{3a3}B"), "a\u{3c3}b");
        assert_eq!(capitalize("nOTIFY"), "Notify");
        assert_eq!(capitalize("\u{1c6}x"), "\u{1c5}x");
        assert_eq!(capitalize(""), "");
    }

    #[test]
    fn classes() {
        assert!(is_digit('\u{b2}'));
        assert!(!is_decimal('\u{b2}'));
        assert!(is_decimal('\u{663}'));
        assert!(is_word('_'));
        assert!(!is_word('-'));
        assert!(is_space('\u{a0}'));
        assert!(!is_space('\u{200b}'));
        assert!(is_identifier("_a1"));
        assert!(!is_identifier("1a"));
        assert!(!is_identifier(""));
        assert!(is_keyword("lambda"));
        assert!(!is_keyword("match"));
    }

    #[test]
    fn strings() {
        assert_eq!(len("h\u{e9}"), 2);
        assert_eq!(slice("hello", 1, 3), "el");
        assert_eq!(slice("hi", 1, 9), "i");
        assert_eq!(ljust("ab", 4), "ab  ");
        assert_eq!(strip("\u{3000} x \n"), "x");
        assert_eq!(expandtabs("a\tb", 8), "a       b");
        assert_eq!(expandtabs("\t", 8), "        ");
        assert_eq!(
            splitlines("a\r\nb\rc\u{2028}d", true),
            vec!["a\r\n", "b\r", "c\u{2028}", "d"]
        );
        assert_eq!(splitlines("a\nb\n", false), vec!["a", "b"]);
    }

    #[test]
    fn reprs() {
        assert_eq!(repr_str("it's"), "\"it's\"");
        assert_eq!(repr_str("a\nb"), "'a\\nb'");
        assert_eq!(repr_str("'\""), "'\\'\"'");
        assert_eq!(repr_str("\u{7f}\u{a0}\u{e9}"), "'\\x7f\\xa0\u{e9}'");
        assert_eq!(repr_str("\u{200b}"), "'\\u200b'");
        assert_eq!(repr_float(1e16), "1e+16");
        assert_eq!(repr_float(1e15), "1000000000000000.0");
        assert_eq!(repr_float(1.5e-5), "1.5e-05");
        assert_eq!(repr_float(0.0001), "0.0001");
        assert_eq!(repr_float(-3.0), "-3.0");
        assert_eq!(repr_float(f64::INFINITY), "inf");
    }
}
