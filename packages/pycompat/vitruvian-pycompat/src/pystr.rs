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

//! Python's string semantics where Rust's differ: what counts as whitespace,
//! a decimal digit or a line break, how `repr` quotes, how floats print, and
//! how `round` breaks ties. Tables are Unicode 15.0, as in Python 3.12.

/// The first code point of every run of ten Nd (decimal) digits.
const DIGIT_ZEROS: [u32; 68] = [
    0x30, 0x660, 0x6F0, 0x7C0, 0x966, 0x9E6, 0xA66, 0xAE6, 0xB66, 0xBE6, 0xC66, 0xCE6, 0xD66,
    0xDE6, 0xE50, 0xED0, 0xF20, 0x1040, 0x1090, 0x17E0, 0x1810, 0x1946, 0x19D0, 0x1A80, 0x1A90,
    0x1B50, 0x1BB0, 0x1C40, 0x1C50, 0xA620, 0xA8D0, 0xA900, 0xA9D0, 0xA9F0, 0xAA50, 0xABF0, 0xFF10,
    0x104A0, 0x10D30, 0x11066, 0x110F0, 0x11136, 0x111D0, 0x112F0, 0x11450, 0x114D0, 0x11650,
    0x116C0, 0x11730, 0x118E0, 0x11950, 0x11C50, 0x11D50, 0x11DA0, 0x11F50, 0x16A60, 0x16AC0,
    0x16B50, 0x1D7CE, 0x1D7D8, 0x1D7E2, 0x1D7EC, 0x1D7F6, 0x1E140, 0x1E2F0, 0x1E4F0, 0x1E950,
    0x1FBF0,
];

/// The value of a decimal digit as Python's `\d` and `int()` read it.
pub fn decimal_value(c: char) -> Option<u32> {
    let cp = c as u32;
    // The table is sorted: the last zero at or below cp is the candidate.
    let idx = DIGIT_ZEROS.partition_point(|&z| z <= cp);
    if idx == 0 {
        return None;
    }
    let zero = DIGIT_ZEROS[idx - 1];
    if cp - zero < 10 {
        Some(cp - zero)
    } else {
        None
    }
}

/// `str.isspace()`, which is also what `\s` matches in a str pattern.
pub fn is_space(c: char) -> bool {
    matches!(
        c as u32,
        0x09..=0x0D
            | 0x1C..=0x20
            | 0x85
            | 0xA0
            | 0x1680
            | 0x2000..=0x200A
            | 0x2028
            | 0x2029
            | 0x202F
            | 0x205F
            | 0x3000
    )
}

/// `str.strip()` with no argument.
pub fn strip(s: &str) -> &str {
    s.trim_matches(is_space)
}

/// `str.splitlines(keepends=True)`.
pub fn splitlines_keepends(s: &str) -> Vec<String> {
    let chars: Vec<char> = s.chars().collect();
    let mut out = Vec::new();
    let mut start = 0;
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        let brk = matches!(
            c as u32,
            0x0A | 0x0B | 0x0C | 0x0D | 0x1C | 0x1D | 0x1E | 0x85 | 0x2028 | 0x2029
        );
        if brk {
            let mut end = i + 1;
            if c == '\r' && i + 1 < chars.len() && chars[i + 1] == '\n' {
                end += 1;
            }
            out.push(chars[start..end].iter().collect());
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

/// The first element of `str.splitlines()` (no ends), or "" for "".
pub fn first_line(s: &str) -> String {
    match splitlines_keepends(s).into_iter().next() {
        None => String::new(),
        Some(line) => line
            .trim_end_matches(|c: char| {
                matches!(
                    c as u32,
                    0x0A | 0x0B | 0x0C | 0x0D | 0x1C | 0x1D | 0x1E | 0x85 | 0x2028 | 0x2029
                )
            })
            .to_string(),
    }
}

/// `str.isprintable()` for one character, from Python's own table: what
/// `repr()` leaves as it is rather than escaping.
fn is_printable(c: char) -> bool {
    in_ranges(crate::unicode_tables::PRINTABLE, c as u32)
}

/// Whether `cp` falls in one of the sorted, inclusive `ranges`.
fn in_ranges(ranges: &[(u32, u32)], cp: u32) -> bool {
    ranges
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

/// `repr(x)` / `str(x)` for a float.
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
    // Rust's {:e} is the shortest round-trip digits, as Python's repr is.
    let sci = format!("{:e}", x);
    let (mant, exp) = sci.split_once('e').unwrap();
    let exp: i32 = exp.parse().unwrap();
    let (neg, mant) = match mant.strip_prefix('-') {
        Some(m) => (true, m),
        None => (false, mant),
    };
    let digits: String = mant.chars().filter(|c| *c != '.').collect();
    let decpt = exp + 1; // digits[0] sits just left of this decimal position
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

/// Python's `round(x)` to an integer-valued float: ties go to even.
pub fn round_half_even(x: f64) -> f64 {
    let r = x.round(); // ties away from zero
    if (x - x.trunc()).abs() == 0.5 && r % 2.0 != 0.0 {
        r - x.signum()
    } else {
        r
    }
}

/// `f"{x:.{prec}f}"`: fixed notation from the exact binary value, ties to
/// even, as Python's formatter (and Rust's) do.
pub fn format_fixed(x: f64, prec: usize) -> String {
    if x.is_nan() {
        return "nan".into();
    }
    if x.is_infinite() {
        return if x > 0.0 { "inf".into() } else { "-inf".into() };
    }
    format!("{:.*}", prec, x)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn digits() {
        assert_eq!(decimal_value('7'), Some(7));
        assert_eq!(decimal_value('\u{0663}'), Some(3));
        assert_eq!(decimal_value('a'), None);
        assert_eq!(decimal_value('\u{00B2}'), None); // superscript two is No
    }

    #[test]
    fn spaces_and_lines() {
        assert!(is_space('\u{1c}'));
        assert!(!is_space('\u{200b}'));
        assert_eq!(strip("\u{3000} x \n"), "x");
        assert_eq!(
            splitlines_keepends("a\r\nb\rc\u{2028}d"),
            vec!["a\r\n", "b\r", "c\u{2028}", "d"]
        );
        assert_eq!(first_line("Revert \"x\"\r\nbody"), "Revert \"x\"");
    }

    #[test]
    fn reprs() {
        assert_eq!(repr_str("it's"), "\"it's\"");
        assert_eq!(repr_str("a\nb"), "'a\\nb'");
        assert_eq!(repr_str("'\""), "'\\'\"'");
        assert_eq!(repr_float(1e16), "1e+16");
        assert_eq!(repr_float(1e15), "1000000000000000.0");
        assert_eq!(repr_float(1.5e-5), "1.5e-05");
        assert_eq!(repr_float(0.0001), "0.0001");
        assert_eq!(repr_float(2.5), "2.5");
        assert_eq!(repr_float(-3.0), "-3.0");
    }

    #[test]
    fn rounding() {
        assert_eq!(round_half_even(0.5), 0.0);
        assert_eq!(round_half_even(1.5), 2.0);
        assert_eq!(round_half_even(2.5), 2.0);
        assert_eq!(round_half_even(-0.5), 0.0);
        assert_eq!(round_half_even(2.6), 3.0);
        assert_eq!(format_fixed(0.25, 1), "0.2");
        assert_eq!(format_fixed(0.35, 1), "0.3"); // 0.35 is below .35 in binary
        assert_eq!(format_fixed(10.0, 1), "10.0");
    }

    #[test]
    fn exhaustive_unicode_classification_and_repr() {
        for cp in 0u32..=0x10FFFF {
            let Some(c) = char::from_u32(cp) else {
                continue;
            };
            let expect_space = in_ranges(crate::unicode_tables::SPACE, cp);
            assert_eq!(is_space(c), expect_space, "is_space {cp:#x}");

            let dec_idx = crate::unicode_tables::DECIMAL.partition_point(|&(lo, _)| lo <= cp);
            let expect_dec = if dec_idx > 0 && cp <= crate::unicode_tables::DECIMAL[dec_idx - 1].1 {
                Some((cp - crate::unicode_tables::DECIMAL[dec_idx - 1].0) % 10)
            } else {
                None
            };
            assert_eq!(decimal_value(c), expect_dec, "decimal_value {cp:#x}");

            let p = format!(" {c}x{c} ");
            let expect_strip = if expect_space {
                "x"
            } else {
                p.trim_matches(' ')
            };
            assert_eq!(strip(&p), expect_strip, "strip {cp:#x}");

            let s = c.to_string();
            let expect_repr = match c {
                '\\' => "'\\\\'".to_string(),
                '\t' => "'\\t'".to_string(),
                '\n' => "'\\n'".to_string(),
                '\r' => "'\\r'".to_string(),
                '\'' => "\"'\"".to_string(),
                _ if in_ranges(crate::unicode_tables::PRINTABLE, cp) => format!("'{c}'"),
                _ if cp < 0x100 => format!("'\\x{:02x}'", cp),
                _ if cp < 0x10000 => format!("'\\u{:04x}'", cp),
                _ => format!("'\\U{:08x}'", cp),
            };
            assert_eq!(repr_str(&s), expect_repr, "repr_str {cp:#x}");
        }
        // Unassigned characters like U+0378 must be escaped as Python does.
        assert_eq!(repr_str("\u{0378}"), "'\\u0378'");
    }

    /// The printable table is Python's own (`str.isprintable()`), not an
    /// approximation: these code points are not printable, so `repr()` escapes
    /// them exactly as Python 3 does. Checked with `repr(chr(cp))` in Python 3.15.
    #[test]
    fn printable_table_matches_python_repr() {
        for cp in [0x0378u32, 0x2028, 0xE0001, 0xF0000, 0x10FFFE] {
            let c = char::from_u32(cp).expect("valid scalar");
            assert!(!is_printable(c), "U+{cp:04X} must not be printable");
        }
        // Control: a printable non-ASCII letter must stay as it is.
        assert!(is_printable('\u{e9}'));
        assert_eq!(repr_str("\u{e9}"), "'\u{e9}'");
        assert_eq!(repr_str("\u{0378}"), "'\\u0378'");
        assert_eq!(repr_str("\u{2028}"), "'\\u2028'");
        assert_eq!(repr_str("\u{e0001}"), "'\\U000e0001'");
        assert_eq!(repr_str("\u{f0000}"), "'\\U000f0000'");
        assert_eq!(repr_str("\u{10fffe}"), "'\\U0010fffe'");
    }
}
