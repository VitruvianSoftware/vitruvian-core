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

//! Python's str, where Rust's differs.
//!
//! A Python str is a sequence of code points, and JSON's `\ud800` escapes
//! put lone surrogates in one, which a Rust `String` cannot hold. So token
//! text is a [`PyStr`], code points as `u32`, and the handful of str
//! methods gen_tokens.py calls are written out over it: `upper`,
//! `capitalize`, `repr`, `int()`'s reading of digits. The character data
//! comes from Python 3.12 itself, through src/unicode_tables.rs.

use crate::unicode_tables;

/// A Python str: code points, surrogates allowed.
pub type PyStr = Vec<u32>;

/// A Rust string as a [`PyStr`].
pub fn ps(s: &str) -> PyStr {
    s.chars().map(|c| c as u32).collect()
}

fn in_table(table: &[(u32, u32)], cp: u32) -> bool {
    let i = table.partition_point(|&(lo, _)| lo <= cp);
    i > 0 && cp <= table[i - 1].1
}

/// `str.isprintable()` for one code point.
pub fn is_printable_cp(cp: u32) -> bool {
    in_table(unicode_tables::PRINTABLE, cp)
}

/// `str.isspace()` for one code point.
pub fn is_space_cp(cp: u32) -> bool {
    in_table(unicode_tables::SPACE, cp)
}

/// The digit a decimal (Nd) code point stands for, as `int()` reads it.
pub fn decimal_cp(cp: u32) -> Option<u32> {
    let t = unicode_tables::DECIMAL;
    let i = t.partition_point(|&(lo, _)| lo <= cp);
    if i == 0 || cp > t[i - 1].1 {
        return None;
    }
    Some((cp - t[i - 1].0) % 10)
}

fn is_cased(cp: u32) -> bool {
    in_table(unicode_tables::CASED, cp)
}

fn is_case_ignorable(cp: u32) -> bool {
    in_table(unicode_tables::CASE_IGNORABLE, cp)
}

fn is_surrogate(cp: u32) -> bool {
    (0xD800..=0xDFFF).contains(&cp)
}

/// `str.upper()`: Rust's full mapping, which is Python's; surrogates stay.
pub fn upper(s: &[u32]) -> PyStr {
    let mut out = Vec::with_capacity(s.len());
    for &cp in s {
        match char::from_u32(cp) {
            Some(c) => out.extend(c.to_uppercase().map(|u| u as u32)),
            None => out.push(cp),
        }
    }
    out
}

fn lower_one(cp: u32, out: &mut PyStr) {
    match char::from_u32(cp) {
        Some(c) => out.extend(c.to_lowercase().map(|u| u as u32)),
        None => out.push(cp),
    }
}

fn title_one(cp: u32, out: &mut PyStr) {
    let t = unicode_tables::TITLE;
    match t.binary_search_by_key(&cp, |&(k, _)| k) {
        Ok(i) => out.extend_from_slice(t[i].1),
        Err(_) => out.extend(upper(&[cp])),
    }
}

/// Whether the capital sigma at `i` lowers to a final sigma: CPython's
/// handle_capital_sigma, which reads the whole string around it.
fn final_sigma(s: &[u32], i: usize) -> bool {
    let mut j = i;
    let mut before = None;
    while j > 0 {
        j -= 1;
        if !is_case_ignorable(s[j]) {
            before = Some(s[j]);
            break;
        }
    }
    if !before.is_some_and(is_cased) {
        return false;
    }
    let mut k = i + 1;
    while k < s.len() && is_case_ignorable(s[k]) {
        k += 1;
    }
    k == s.len() || !is_cased(s[k])
}

/// `str.capitalize()`: the first character in title case, the rest lowered
/// (a capital sigma lowering by its context, as CPython's do_capitalize).
pub fn capitalize(s: &[u32]) -> PyStr {
    let mut out = Vec::with_capacity(s.len());
    if let Some(&first) = s.first() {
        title_one(first, &mut out);
    }
    for i in 1..s.len() {
        if s[i] == 0x3A3 {
            out.push(if final_sigma(s, i) { 0x3C2 } else { 0x3C3 });
        } else {
            lower_one(s[i], &mut out);
        }
    }
    out
}

/// `repr(s)`. Every surrogate is escaped, so the result is a Rust string.
pub fn repr(s: &[u32]) -> String {
    let has = |q: u32| s.contains(&q);
    let quote = if has('\'' as u32) && !has('"' as u32) {
        '"'
    } else {
        '\''
    };
    let mut out = String::with_capacity(s.len() + 2);
    out.push(quote);
    for &cp in s {
        match cp {
            0x5C => out.push_str("\\\\"),
            0x09 => out.push_str("\\t"),
            0x0A => out.push_str("\\n"),
            0x0D => out.push_str("\\r"),
            _ if cp == quote as u32 => {
                out.push('\\');
                out.push(quote);
            }
            _ if cp < 0x20 || cp == 0x7F => out.push_str(&format!("\\x{:02x}", cp)),
            _ if cp < 0x7F => out.push(cp as u8 as char),
            _ if is_printable_cp(cp) => out.push(char::from_u32(cp).unwrap()),
            _ if cp <= 0xFF => out.push_str(&format!("\\x{:02x}", cp)),
            _ if cp <= 0xFFFF => out.push_str(&format!("\\u{:04x}", cp)),
            _ => out.push_str(&format!("\\U{:08x}", cp)),
        }
    }
    out.push(quote);
    out
}

/// The text as stderr writes it: UTF-8, a surrogate as `\udXXX`
/// (Python's backslashreplace).
pub fn backslashreplace(s: &[u32]) -> String {
    let mut out = String::with_capacity(s.len());
    for &cp in s {
        match char::from_u32(cp) {
            Some(c) => out.push(c),
            None => out.push_str(&format!("\\u{:04x}", cp)),
        }
    }
    out
}

/// `s.encode("utf-8")`, or the first run of surrogates that stops it, as
/// (start, end) code-point positions.
pub fn encode_utf8(s: &[u32]) -> Result<Vec<u8>, (usize, usize)> {
    let mut out = Vec::with_capacity(s.len());
    let mut buf = [0u8; 4];
    for (i, &cp) in s.iter().enumerate() {
        match char::from_u32(cp) {
            Some(c) => out.extend_from_slice(c.encode_utf8(&mut buf).as_bytes()),
            None => {
                let mut end = i + 1;
                while end < s.len() && is_surrogate(s[end]) {
                    end += 1;
                }
                return Err((i, end));
            }
        }
    }
    Ok(out)
}

/// `s.startswith(prefix)`.
pub fn starts_with(s: &[u32], prefix: &str) -> bool {
    let p = ps(prefix);
    s.len() >= p.len() && s[..p.len()] == p[..]
}

/// `s.endswith(suffix)`.
pub fn ends_with(s: &[u32], suffix: &str) -> bool {
    let p = ps(suffix);
    s.len() >= p.len() && s[s.len() - p.len()..] == p[..]
}

/// `s.removesuffix(suffix)`.
pub fn remove_suffix(s: &[u32], suffix: &str) -> PyStr {
    let n = suffix.chars().count();
    if !suffix.is_empty() && ends_with(s, suffix) {
        s[..s.len() - n].to_vec()
    } else {
        s.to_vec()
    }
}

/// `s.split(sep)` for a one-character separator.
pub fn split(s: &[u32], sep: char) -> Vec<PyStr> {
    s.split(|&cp| cp == sep as u32)
        .map(|p| p.to_vec())
        .collect()
}

/// `needle in haystack` for two strs.
pub fn contains(haystack: &[u32], needle: &[u32]) -> bool {
    needle.is_empty() || haystack.windows(needle.len()).any(|w| w == needle)
}

/// A whole number of any size: its sign and its decimal digits, with no
/// leading zeros (zero is "0", never negative).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BigInt {
    pub neg: bool,
    pub digits: String,
}

impl BigInt {
    pub fn from_digits(neg: bool, digits: &str) -> BigInt {
        let d = digits.trim_start_matches('0');
        if d.is_empty() {
            BigInt {
                neg: false,
                digits: "0".into(),
            }
        } else {
            BigInt {
                neg,
                digits: d.into(),
            }
        }
    }

    pub fn small(v: i64) -> BigInt {
        BigInt::from_digits(v < 0, &v.unsigned_abs().to_string())
    }

    /// `int(x)` for a finite float: toward zero, exactly.
    pub fn from_f64(x: f64) -> BigInt {
        let t = x.trunc();
        let bits = t.abs().to_bits();
        let exp = ((bits >> 52) & 0x7FF) as i64;
        if exp == 0 {
            return BigInt::small(0);
        }
        let mant = (bits & ((1u64 << 52) - 1)) | (1u64 << 52);
        let shift = exp - 1075;
        // |t| = mant * 2^shift, a whole number.
        let digits = if shift < 0 {
            (mant >> (-shift)).to_string()
        } else {
            // Little-endian base 10^9 limbs, doubled `shift` times.
            let mut limbs: Vec<u64> = vec![mant % 1_000_000_000, mant / 1_000_000_000];
            for _ in 0..shift {
                let mut carry = 0;
                for l in limbs.iter_mut() {
                    let v = *l * 2 + carry;
                    *l = v % 1_000_000_000;
                    carry = v / 1_000_000_000;
                }
                if carry > 0 {
                    limbs.push(carry);
                }
            }
            while limbs.len() > 1 && *limbs.last().unwrap() == 0 {
                limbs.pop();
            }
            let mut s = limbs.last().unwrap().to_string();
            for l in limbs.iter().rev().skip(1) {
                s.push_str(&format!("{:09}", l));
            }
            s
        };
        BigInt::from_digits(t < 0.0, &digits)
    }

    /// The value as an index, when it fits one.
    pub fn to_isize(&self) -> Option<isize> {
        let v: i128 = self.digits.parse().ok()?;
        let v = if self.neg { -v } else { v };
        isize::try_from(v).ok()
    }

    pub fn to_string_py(&self) -> String {
        if self.neg {
            format!("-{}", self.digits)
        } else {
            self.digits.clone()
        }
    }
}

impl Ord for BigInt {
    fn cmp(&self, other: &BigInt) -> std::cmp::Ordering {
        use std::cmp::Ordering;
        let mag = |a: &BigInt, b: &BigInt| {
            a.digits
                .len()
                .cmp(&b.digits.len())
                .then_with(|| a.digits.cmp(&b.digits))
        };
        match (self.neg, other.neg) {
            (false, true) => Ordering::Greater,
            (true, false) => Ordering::Less,
            (false, false) => mag(self, other),
            (true, true) => mag(other, self),
        }
    }
}

impl PartialOrd for BigInt {
    fn partial_cmp(&self, other: &BigInt) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

/// sys.int_info.default_max_str_digits.
pub const MAX_STR_DIGITS: usize = 4300;

/// Why a str is not a base-10 int.
#[derive(Debug, PartialEq)]
pub enum IntError {
    /// "invalid literal for int() with base 10: ..."
    Invalid,
    /// More digits than int() converts; the count.
    TooLong(usize),
}

/// `int(s)` for a str: CPython's PyLong_FromUnicodeObject. Non-ASCII
/// whitespace reads as a space and decimal digits as ASCII ones (anything
/// else non-ASCII ends the text); then ASCII whitespace around, a sign, and
/// digits with single underscores between them.
pub fn parse_int(s: &[u32]) -> Result<BigInt, IntError> {
    let mut ascii: Vec<u8> = Vec::with_capacity(s.len());
    for &cp in s {
        if cp < 127 {
            ascii.push(cp as u8);
        } else if is_space_cp(cp) {
            ascii.push(b' ');
        } else if let Some(d) = decimal_cp(cp) {
            ascii.push(b'0' + d as u8);
        } else {
            ascii.push(b'?');
            break;
        }
    }
    let ws = |b: u8| matches!(b, b' ' | b'\t' | b'\n' | 0x0B | 0x0C | b'\r');
    let mut i = 0;
    while i < ascii.len() && ws(ascii[i]) {
        i += 1;
    }
    let mut neg = false;
    if i < ascii.len() && (ascii[i] == b'+' || ascii[i] == b'-') {
        neg = ascii[i] == b'-';
        i += 1;
    }
    let mut digits = String::new();
    let mut prev_underscore = true; // no underscore may lead
    while i < ascii.len() {
        let b = ascii[i];
        if b.is_ascii_digit() {
            digits.push(b as char);
            prev_underscore = false;
        } else if b == b'_' {
            if prev_underscore {
                return Err(IntError::Invalid);
            }
            prev_underscore = true;
        } else {
            break;
        }
        i += 1;
    }
    if digits.is_empty() || prev_underscore {
        return Err(IntError::Invalid);
    }
    while i < ascii.len() && ws(ascii[i]) {
        i += 1;
    }
    if i != ascii.len() {
        return Err(IntError::Invalid);
    }
    if digits.len() > MAX_STR_DIGITS {
        return Err(IntError::TooLong(digits.len()));
    }
    Ok(BigInt::from_digits(neg, &digits))
}

/// `repr(x)` (and `str(x)`) for a float.
pub fn repr_float(x: f64) -> String {
    if x.is_nan() {
        return "nan".into();
    }
    if x.is_infinite() {
        return if x > 0.0 { "inf" } else { "-inf" }.into();
    }
    if x == 0.0 {
        return if x.is_sign_negative() { "-0.0" } else { "0.0" }.into();
    }
    // Rust's {:e} gives the shortest digits that round-trip, as repr does.
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
        out.push_str(&format!(
            "e{}{:02}",
            if exp < 0 { '-' } else { '+' },
            exp.abs()
        ));
    } else if decpt <= 0 {
        out.push_str("0.");
        out.push_str(&"0".repeat((-decpt) as usize));
        out.push_str(&digits);
    } else {
        let d = decpt as usize;
        if digits.len() <= d {
            out.push_str(&digits);
            out.push_str(&"0".repeat(d - digits.len()));
            out.push_str(".0");
        } else {
            out.push_str(&digits[..d]);
            out.push('.');
            out.push_str(&digits[d..]);
        }
    }
    out
}

// What src/argparse.rs (shared with the repository's other ports) asks of
// this module, over Rust strings.

/// The value of a decimal digit, as `int()` reads it.
pub fn decimal_value(c: char) -> Option<u32> {
    decimal_cp(c as u32)
}

/// `str.isspace()` for one character.
pub fn is_space(c: char) -> bool {
    is_space_cp(c as u32)
}

/// `str.strip()` with no argument.
pub fn strip(s: &str) -> &str {
    s.trim_matches(is_space)
}

/// `repr(s)` for a Rust string.
pub fn repr_str(s: &str) -> String {
    repr(&ps(s))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(p: &PyStr) -> String {
        backslashreplace(p)
    }

    #[test]
    fn capitalize_is_title_then_lower() {
        assert_eq!(s(&capitalize(&ps("sm"))), "Sm");
        assert_eq!(s(&capitalize(&ps("mOBILE"))), "Mobile");
        assert_eq!(s(&capitalize(&ps("ǆx"))), "ǅx");
        assert_eq!(s(&capitalize(&ps("ßa"))), "Ssa");
        assert_eq!(s(&capitalize(&ps(""))), "");
    }

    #[test]
    fn capital_sigma_lowers_by_context() {
        assert_eq!(s(&capitalize(&ps("AΣ"))), "Aς");
        assert_eq!(s(&capitalize(&ps("AΣA"))), "Aσa");
        assert_eq!(s(&capitalize(&ps("Σ"))), "Σ");
        assert_eq!(s(&capitalize(&ps("A'Σ'"))), "A'ς'");
    }

    #[test]
    fn upper_uses_full_mappings() {
        assert_eq!(s(&upper(&ps("ß#ﬃ"))), "SS#FFI");
        assert_eq!(upper(&[0xD800, 0x61]), vec![0xD800, 0x41]);
    }

    #[test]
    fn repr_quotes_and_escapes_as_python() {
        assert_eq!(repr(&ps("a'b")), "\"a'b\"");
        assert_eq!(repr(&ps("a\"b")), "'a\"b'");
        assert_eq!(repr(&ps("a'\"b")), "'a\\'\"b'");
        assert_eq!(
            repr(&[0x7F, 0x80, 0xA0, 0xAD, 0x200B, 0x1F600, 0xE0001, 0xD800]),
            "'\\x7f\\x80\\xa0\\xad\\u200b😀\\U000e0001\\ud800'"
        );
    }

    #[test]
    fn floats_print_as_repr() {
        let got: Vec<String> = [1e16, 1e15, 1.5e16, 0.0001, 0.00001, -0.0, 1e308, 5e-324]
            .iter()
            .map(|x| repr_float(*x))
            .collect();
        assert_eq!(
            got,
            [
                "1e+16",
                "1000000000000000.0",
                "1.5e+16",
                "0.0001",
                "1e-05",
                "-0.0",
                "1e+308",
                "5e-324"
            ]
        );
        assert_eq!(repr_float(0.1 + 0.2), "0.30000000000000004");
    }

    #[test]
    fn int_reads_what_python_reads() {
        let ok = |t: &str| parse_int(&ps(t)).map(|b| b.to_string_py());
        assert_eq!(ok(" \u{661}\u{662}_3 "), Ok("123".into()));
        assert_eq!(ok("-0"), Ok("0".into()));
        assert_eq!(ok("+007"), Ok("7".into()));
        assert_eq!(ok("1_"), Err(IntError::Invalid));
        assert_eq!(ok("_1"), Err(IntError::Invalid));
        assert_eq!(ok("1__0"), Err(IntError::Invalid));
        assert_eq!(ok("\u{1c}1"), Err(IntError::Invalid));
        assert_eq!(ok(""), Err(IntError::Invalid));
        assert_eq!(ok(&"1".repeat(4301)), Err(IntError::TooLong(4301)));
    }

    #[test]
    fn floats_truncate_to_exact_ints() {
        assert_eq!(BigInt::from_f64(-1.9).to_string_py(), "-1");
        assert_eq!(BigInt::from_f64(-0.5).to_string_py(), "0");
        assert_eq!(
            BigInt::from_f64(1e20).to_string_py(),
            "100000000000000000000"
        );
        assert_eq!(
            BigInt::from_f64(2f64.powi(70)).to_string_py(),
            "1180591620717411303424"
        );
        assert_eq!(BigInt::from_f64(f64::MAX).digits.len(), 309);
    }

    #[test]
    fn big_ints_order_as_numbers() {
        let b = |t: &str| parse_int(&ps(t)).unwrap();
        assert!(b("-10") < b("-9"));
        assert!(b("9") < b("10"));
        assert!(b("-1") < b("0"));
        assert_eq!(b("010"), b("10"));
    }

    #[test]
    fn surrogates_stop_utf8() {
        assert_eq!(encode_utf8(&[0x61, 0xD800, 0xDFFF, 0x62]), Err((1, 3)));
        assert_eq!(encode_utf8(&ps("é")), Ok("é".as_bytes().to_vec()));
    }
}
