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

//! The slice of Python semantics adb_connect.py relies on.
//!
//! The Python tool passes devices and profiles around as dicts whose values
//! come from mDNS, `adb`, `tailscale status --json` and a user-edited JSON
//! file, so a value can be any JSON type. To behave the same on every input
//! (and print byte-identical output), the port keeps that shape: an
//! insertion-ordered [`Dict`] of [`Val`]s, Python's truthiness, `str()` and
//! `repr()`, and Python's text helpers (`strip`, `split`, `splitlines`,
//! `int()`, `float()`). Where Python would raise an uncaught exception, the
//! port raises a [`PyExc`] panic that `main` turns into a traceback-style
//! message and exit status 1, as the interpreter does.

use std::fmt::Write as _;

/// A Python value as it can occur in adb_connect.py's dicts.
#[derive(Clone, Debug, PartialEq)]
pub enum Val {
    None,
    Bool(bool),
    /// An int, kept as its canonical decimal digits so JSON's unbounded
    /// integers survive unchanged.
    Int(String),
    Float(f64),
    Str(String),
    List(Vec<Val>),
    Dict(Dict),
}

/// An insertion-ordered dict with string keys, like a Python 3.7+ dict.
#[derive(Clone, Debug, PartialEq, Default)]
pub struct Dict(pub Vec<(String, Val)>);

/// An exception Python would raise and not catch.
#[derive(Clone, Debug, PartialEq)]
pub struct PyExc {
    pub kind: &'static str,
    pub msg: String,
}

/// Raise an uncaught Python exception (unwinds to `main`).
pub fn raise(kind: &'static str, msg: impl Into<String>) -> ! {
    std::panic::panic_any(PyExc {
        kind,
        msg: msg.into(),
    })
}

/// `Val::Str` from anything string-like.
pub fn s(v: impl Into<String>) -> Val {
    Val::Str(v.into())
}

/// `Val::Int` from a machine integer.
pub fn int(v: i64) -> Val {
    Val::Int(v.to_string())
}

impl Dict {
    pub fn new() -> Self {
        Dict(Vec::new())
    }

    /// Build from `(key, value)` pairs, later duplicates replacing earlier.
    pub fn from_pairs<K: Into<String>>(pairs: Vec<(K, Val)>) -> Self {
        let mut d = Dict::new();
        for (k, v) in pairs {
            d.set(k, v);
        }
        d
    }

    /// `d.get(k)`.
    pub fn get(&self, key: &str) -> Option<&Val> {
        self.0.iter().find(|(k, _)| k == key).map(|(_, v)| v)
    }

    /// `d.get(k, default)`, cloned.
    pub fn get_or(&self, key: &str, default: Val) -> Val {
        self.get(key).cloned().unwrap_or(default)
    }

    /// `d.get(k)` with Python's `None` default.
    pub fn get_none(&self, key: &str) -> Val {
        self.get_or(key, Val::None)
    }

    /// `d.get(k, "")`.
    pub fn get_str_default(&self, key: &str) -> Val {
        self.get_or(key, s(""))
    }

    /// `d[k]`, raising `KeyError` when absent.
    pub fn item(&self, key: &str) -> Val {
        match self.get(key) {
            Some(v) => v.clone(),
            None => raise("KeyError", repr_str(key)),
        }
    }

    /// `d[k] = v`: replace in place, or append a new key.
    pub fn set(&mut self, key: impl Into<String>, val: Val) {
        let key = key.into();
        if let Some(slot) = self.0.iter_mut().find(|(k, _)| *k == key) {
            slot.1 = val;
        } else {
            self.0.push((key, val));
        }
    }

    /// `d.setdefault(k, v)`.
    pub fn setdefault(&mut self, key: &str, val: Val) {
        if self.get(key).is_none() {
            self.0.push((key.to_string(), val));
        }
    }

    /// `d.update(other)`.
    pub fn update(&mut self, other: &Dict) {
        for (k, v) in &other.0 {
            self.set(k.clone(), v.clone());
        }
    }

    pub fn contains_key(&self, key: &str) -> bool {
        self.get(key).is_some()
    }

    pub fn len(&self) -> usize {
        self.0.len()
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
}

impl Val {
    /// Python's type name, for exception messages.
    pub fn type_name(&self) -> &'static str {
        match self {
            Val::None => "NoneType",
            Val::Bool(_) => "bool",
            Val::Int(_) => "int",
            Val::Float(_) => "float",
            Val::Str(_) => "str",
            Val::List(_) => "list",
            Val::Dict(_) => "dict",
        }
    }

    /// `bool(v)`.
    pub fn truthy(&self) -> bool {
        match self {
            Val::None => false,
            Val::Bool(b) => *b,
            Val::Int(d) => d != "0",
            Val::Float(f) => *f != 0.0,
            Val::Str(s) => !s.is_empty(),
            Val::List(l) => !l.is_empty(),
            Val::Dict(d) => !d.is_empty(),
        }
    }

    /// `a or b`: `a` when truthy, else `b`.
    pub fn or(self, other: Val) -> Val {
        if self.truthy() {
            self
        } else {
            other
        }
    }

    /// `a or b` with `b` computed lazily.
    pub fn or_else(self, other: impl FnOnce() -> Val) -> Val {
        if self.truthy() {
            self
        } else {
            other()
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Val::Str(s) => Some(s),
            _ => None,
        }
    }

    pub fn as_dict(&self) -> Option<&Dict> {
        match self {
            Val::Dict(d) => Some(d),
            _ => None,
        }
    }

    /// The string inside, raising Python's AttributeError for `method`
    /// when the value is not a str (as `v.lower()` would).
    pub fn expect_str(&self, method: &str) -> &str {
        match self {
            Val::Str(s) => s,
            other => raise(
                "AttributeError",
                format!(
                    "'{}' object has no attribute '{}'",
                    other.type_name(),
                    method
                ),
            ),
        }
    }

    /// `v.lower()`.
    pub fn lower(&self) -> String {
        self.expect_str("lower").to_lowercase()
    }

    /// `str(v)`.
    pub fn py_str(&self) -> String {
        match self {
            Val::Str(s) => s.clone(),
            other => other.py_repr(),
        }
    }

    /// `repr(v)`.
    pub fn py_repr(&self) -> String {
        match self {
            Val::None => "None".into(),
            Val::Bool(true) => "True".into(),
            Val::Bool(false) => "False".into(),
            Val::Int(d) => d.clone(),
            Val::Float(f) => float_repr(*f),
            Val::Str(s) => repr_str(s),
            Val::List(items) => {
                let inner: Vec<String> = items.iter().map(Val::py_repr).collect();
                format!("[{}]", inner.join(", "))
            }
            Val::Dict(d) => {
                let inner: Vec<String> =
                    d.0.iter()
                        .map(|(k, v)| format!("{}: {}", repr_str(k), v.py_repr()))
                        .collect();
                format!("{{{}}}", inner.join(", "))
            }
        }
    }

    /// `list(v)`: the items a `for` loop over `v` yields.
    pub fn iter_items(&self) -> Vec<Val> {
        match self {
            Val::List(items) => items.clone(),
            Val::Str(st) => st.chars().map(|c| Val::Str(c.to_string())).collect(),
            Val::Dict(d) => d.0.iter().map(|(k, _)| Val::Str(k.clone())).collect(),
            other => raise(
                "TypeError",
                format!("'{}' object is not iterable", other.type_name()),
            ),
        }
    }

    /// `needle in v` for a str needle.
    pub fn contains_str(&self, needle: &str) -> bool {
        match self {
            Val::Str(hay) => hay.contains(needle),
            Val::List(items) => items.iter().any(|i| i.as_str() == Some(needle)),
            Val::Dict(d) => d.contains_key(needle),
            other => raise(
                "TypeError",
                format!("argument of type '{}' is not iterable", other.type_name()),
            ),
        }
    }

    /// `v == "literal"`.
    pub fn eq_str(&self, other: &str) -> bool {
        self.as_str() == Some(other)
    }
}

/// `" ".join(items)`, raising TypeError on a non-str item.
pub fn join_strs(sep: &str, items: &[Val]) -> String {
    let mut parts = Vec::with_capacity(items.len());
    for (i, item) in items.iter().enumerate() {
        match item {
            Val::Str(st) => parts.push(st.as_str()),
            other => raise(
                "TypeError",
                format!(
                    "sequence item {}: expected str instance, {} found",
                    i,
                    other.type_name()
                ),
            ),
        }
    }
    parts.join(sep)
}

/// `float.__repr__`.
pub fn float_repr(f: f64) -> String {
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
    // `{:e}` gives the shortest round-trip digits, as Python's repr does.
    let sci = format!("{:e}", f);
    let (mantissa, exp) = sci.split_once('e').expect("LowerExp has an exponent");
    let exp: i32 = exp.parse().expect("LowerExp exponent is an integer");
    let negative = mantissa.starts_with('-');
    let digits: String = mantissa.chars().filter(|c| c.is_ascii_digit()).collect();
    let mut out = String::new();
    if negative {
        out.push('-');
    }
    if (-4..16).contains(&exp) {
        let n = digits.len() as i32;
        if exp >= 0 {
            if n <= exp + 1 {
                out.push_str(&digits);
                out.push_str(&"0".repeat((exp + 1 - n) as usize));
                out.push_str(".0");
            } else {
                let (a, b) = digits.split_at((exp + 1) as usize);
                out.push_str(a);
                out.push('.');
                out.push_str(b);
            }
        } else {
            out.push_str("0.");
            out.push_str(&"0".repeat((-exp - 1) as usize));
            out.push_str(&digits);
        }
    } else {
        out.push_str(&digits[..1]);
        if digits.len() > 1 {
            out.push('.');
            out.push_str(&digits[1..]);
        }
        let _ = write!(out, "e{}{:02}", if exp < 0 { '-' } else { '+' }, exp.abs());
    }
    out
}

/// Close to `str.isprintable()` for one character (Python escapes the
/// rest in `repr`). Exact for ASCII and Latin-1; covers the common
/// non-printable categories above that.
fn is_printable(c: char) -> bool {
    let cp = c as u32;
    if cp < 0x20 || (0x7f..=0xa0).contains(&cp) || cp == 0xad {
        return false;
    }
    !matches!(
        cp,
        0x1680
            | 0x2000..=0x200f
            | 0x2028..=0x202f
            | 0x205f..=0x2064
            | 0x3000
            | 0xd800..=0xdfff
            | 0xe000..=0xf8ff
            | 0xfeff
            | 0xfff9..=0xfffb
            | 0xfffe..=0xffff
    )
}

/// `repr(s)` for a str.
pub fn repr_str(st: &str) -> String {
    let quote = if st.contains('\'') && !st.contains('"') {
        '"'
    } else {
        '\''
    };
    let mut out = String::with_capacity(st.len() + 2);
    out.push(quote);
    for c in st.chars() {
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
                    let _ = write!(out, "\\x{:02x}", cp);
                } else if cp < 0x10000 {
                    let _ = write!(out, "\\u{:04x}", cp);
                } else {
                    let _ = write!(out, "\\U{:08x}", cp);
                }
            }
            c => out.push(c),
        }
    }
    out.push(quote);
    out
}

/// `str.isspace()` for one character.
pub fn is_space(c: char) -> bool {
    matches!(
        c as u32,
        0x09..=0x0d
            | 0x1c..=0x20
            | 0x85
            | 0xa0
            | 0x1680
            | 0x2000..=0x200a
            | 0x2028
            | 0x2029
            | 0x202f
            | 0x205f
            | 0x3000
    )
}

/// `s.strip()`.
pub fn strip(st: &str) -> &str {
    st.trim_matches(is_space)
}

/// `s.rstrip(chars)`.
pub fn rstrip_chars<'a>(st: &'a str, chars: &str) -> &'a str {
    st.trim_end_matches(|c| chars.contains(c))
}

/// `s.split()` (no separator: runs of whitespace, no empty items).
pub fn split_ws(st: &str) -> Vec<&str> {
    st.split(is_space).filter(|p| !p.is_empty()).collect()
}

/// `s.splitlines()`.
pub fn splitlines(st: &str) -> Vec<&str> {
    let mut lines = Vec::new();
    let mut start = 0;
    let mut chars = st.char_indices().peekable();
    while let Some((i, c)) = chars.next() {
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
            lines.push(&st[start..i]);
            let mut end = i + c.len_utf8();
            if c == '\r' {
                if let Some(&(j, '\n')) = chars.peek() {
                    chars.next();
                    end = j + 1;
                }
            }
            start = end;
        }
    }
    if start < st.len() {
        lines.push(&st[start..]);
    }
    lines
}

/// `bytes.decode("utf-8")`'s UnicodeDecodeError message, or None when
/// the bytes are valid UTF-8.
pub fn utf8_error(bytes: &[u8]) -> Option<String> {
    let e = std::str::from_utf8(bytes).err()?;
    let pos = e.valid_up_to();
    let prefix = "'utf-8' codec can't decode";
    Some(match e.error_len() {
        Some(1) => {
            let b = bytes[pos];
            let reason = if (0xc2..=0xf4).contains(&b) {
                "invalid continuation byte"
            } else {
                "invalid start byte"
            };
            format!(
                "{} byte 0x{:02x} in position {}: {}",
                prefix, b, pos, reason
            )
        }
        Some(n) => format!(
            "{} bytes in position {}-{}: invalid continuation byte",
            prefix,
            pos,
            pos + n - 1
        ),
        None if bytes.len() - pos == 1 => format!(
            "{} byte 0x{:02x} in position {}: unexpected end of data",
            prefix, bytes[pos], pos
        ),
        None => format!(
            "{} bytes in position {}-{}: unexpected end of data",
            prefix,
            pos,
            bytes.len() - 1
        ),
    })
}

/// What text-mode pipes do to child output: universal newlines.
pub fn universal_newlines(st: &str) -> String {
    st.replace("\r\n", "\n").replace('\r', "\n")
}

/// Strip Python-style digit-group underscores, refusing misplaced ones.
fn strip_underscores(body: &str) -> Option<String> {
    let b = body.as_bytes();
    for (i, &ch) in b.iter().enumerate() {
        if ch == b'_' {
            let before = i > 0 && b[i - 1].is_ascii_digit();
            let after = i + 1 < b.len() && b[i + 1].is_ascii_digit();
            if !before || !after {
                return None;
            }
        }
    }
    Some(body.replace('_', ""))
}

/// `int(text)` in base 10: canonical digits, or None for ValueError.
pub fn parse_int(text: &str) -> Option<String> {
    let t = strip(text);
    let (neg, body) = match t.as_bytes().first() {
        Some(b'-') => (true, &t[1..]),
        Some(b'+') => (false, &t[1..]),
        _ => (false, t),
    };
    if body.is_empty() || !body.chars().all(|c| c.is_ascii_digit() || c == '_') {
        return None;
    }
    let digits = strip_underscores(body)?;
    let trimmed = digits.trim_start_matches('0');
    if trimmed.is_empty() {
        return Some("0".into());
    }
    Some(if neg {
        format!("-{}", trimmed)
    } else {
        trimmed.to_string()
    })
}

/// `float(text)`, or None for ValueError.
pub fn parse_float(text: &str) -> Option<f64> {
    let t = strip(text);
    let (sign, body) = match t.as_bytes().first() {
        Some(b'-') => (-1.0, &t[1..]),
        Some(b'+') => (1.0, &t[1..]),
        _ => (1.0, t),
    };
    let lower = body.to_ascii_lowercase();
    if lower == "inf" || lower == "infinity" {
        return Some(sign * f64::INFINITY);
    }
    if lower == "nan" {
        return Some(f64::NAN);
    }
    // digits [. digits] | . digits, then an optional exponent.
    let b = body.as_bytes();
    let mut i = 0;
    let digit_run = |i: &mut usize| {
        let start = *i;
        while *i < b.len() && (b[*i].is_ascii_digit() || b[*i] == b'_') {
            *i += 1;
        }
        *i - start
    };
    let int_len = digit_run(&mut i);
    let mut frac_len = 0;
    if i < b.len() && b[i] == b'.' {
        i += 1;
        frac_len = digit_run(&mut i);
    }
    if int_len == 0 && frac_len == 0 {
        return None;
    }
    if i < b.len() && (b[i] == b'e' || b[i] == b'E') {
        i += 1;
        if i < b.len() && (b[i] == b'+' || b[i] == b'-') {
            i += 1;
        }
        if digit_run(&mut i) == 0 {
            return None;
        }
    }
    if i != b.len() {
        return None;
    }
    // Underscores must sit between digits within each digit group.
    for group in body.split(['.', 'e', 'E', '+', '-']) {
        if group.contains('_') {
            strip_underscores(group)?;
        }
    }
    let cleaned = body.replace('_', "");
    cleaned.parse::<f64>().ok().map(|v| sign * v)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn float_repr_matches_python() {
        assert_eq!(float_repr(1.5), "1.5");
        assert_eq!(float_repr(15.0), "15.0");
        assert_eq!(float_repr(1e16), "1e+16");
        assert_eq!(float_repr(123456789012345.0), "123456789012345.0");
        assert_eq!(float_repr(0.0001), "0.0001");
        assert_eq!(float_repr(0.00001), "1e-05");
        assert_eq!(float_repr(-2.5e-7), "-2.5e-07");
        assert_eq!(float_repr(0.1), "0.1");
        assert_eq!(float_repr(f64::INFINITY), "inf");
        assert_eq!(float_repr(-0.0), "-0.0");
    }

    #[test]
    fn repr_str_quotes_like_python() {
        assert_eq!(repr_str("x"), "'x'");
        assert_eq!(repr_str("it's"), "\"it's\"");
        assert_eq!(repr_str("a'b\"c"), "'a\\'b\"c'");
        assert_eq!(repr_str("tab\there\n"), "'tab\\there\\n'");
        assert_eq!(repr_str("\u{7}"), "'\\x07'");
        assert_eq!(repr_str("é"), "'é'");
    }

    #[test]
    fn int_and_float_parse_like_python() {
        assert_eq!(parse_int(" +07 ").as_deref(), Some("7"));
        assert_eq!(parse_int("-0").as_deref(), Some("0"));
        assert_eq!(parse_int("1_000").as_deref(), Some("1000"));
        assert_eq!(parse_int("1__0"), None);
        assert_eq!(parse_int("_1"), None);
        assert_eq!(parse_int("0x10"), None);
        assert_eq!(parse_int(""), None);
        assert_eq!(parse_float(" 1_5 "), Some(15.0));
        assert_eq!(parse_float("1e999"), Some(f64::INFINITY));
        assert_eq!(parse_float("-Infinity"), Some(f64::NEG_INFINITY));
        assert!(parse_float("nan").unwrap().is_nan());
        assert_eq!(parse_float(".5"), Some(0.5));
        assert_eq!(parse_float("5."), Some(5.0));
        assert_eq!(parse_float("."), None);
        assert_eq!(parse_float("1e"), None);
        assert_eq!(parse_float("1_.5"), None);
        assert_eq!(parse_float("abc"), None);
    }

    #[test]
    fn text_helpers_match_python() {
        assert_eq!(splitlines("a\r\nb\rc\n\nd\n"), vec!["a", "b", "c", "", "d"]);
        assert_eq!(splitlines(""), Vec::<&str>::new());
        assert_eq!(split_ws("  a \t b\x1c c  "), vec!["a", "b", "c"]);
        assert_eq!(strip("\u{a0} x \n"), "x");
        assert_eq!(rstrip_chars("host.local..", "."), "host.local");
        assert_eq!(universal_newlines("a\r\nb\rc"), "a\nb\nc");
    }

    #[test]
    fn utf8_errors_match_python() {
        assert_eq!(utf8_error(b"ok"), None);
        assert_eq!(
            utf8_error(b"\xff").unwrap(),
            "'utf-8' codec can't decode byte 0xff in position 0: invalid start byte"
        );
        assert_eq!(
            utf8_error(b"a\xe2\x28").unwrap(),
            "'utf-8' codec can't decode byte 0xe2 in position 1: invalid continuation byte"
        );
        assert_eq!(
            utf8_error(b"\xe2\x82A").unwrap(),
            "'utf-8' codec can't decode bytes in position 0-1: invalid continuation byte"
        );
        assert_eq!(
            utf8_error(b"\xe2\x82").unwrap(),
            "'utf-8' codec can't decode bytes in position 0-1: unexpected end of data"
        );
        assert_eq!(
            utf8_error(b"x\xe2").unwrap(),
            "'utf-8' codec can't decode byte 0xe2 in position 1: unexpected end of data"
        );
    }

    #[test]
    fn dict_keeps_insertion_order_and_python_semantics() {
        let mut d = Dict::new();
        d.set("b", int(1));
        d.set("a", s("x"));
        d.set("b", int(2));
        d.setdefault("a", s("ignored"));
        d.setdefault("c", Val::Bool(false));
        let keys: Vec<&str> = d.0.iter().map(|(k, _)| k.as_str()).collect();
        assert_eq!(keys, vec!["b", "a", "c"]);
        assert_eq!(d.get("b"), Some(&int(2)));
        assert!(!Val::Int("0".into()).truthy());
        assert!(Val::Float(f64::NAN).truthy());
        assert_eq!(s("").or(s("y")), s("y"));
        assert_eq!(Val::List(vec![s("a"), Val::None]).py_str(), "['a', None]");
        assert_eq!(s("ab").iter_items(), vec![s("a"), s("b")]);
    }

    #[test]
    fn python_errors_raise_pyexc() {
        let err = std::panic::catch_unwind(|| int(5).lower()).unwrap_err();
        let exc = err.downcast_ref::<PyExc>().unwrap();
        assert_eq!(exc.kind, "AttributeError");
        assert_eq!(exc.msg, "'int' object has no attribute 'lower'");
        let err = std::panic::catch_unwind(|| join_strs(" ", &[s("a"), int(1)])).unwrap_err();
        let exc = err.downcast_ref::<PyExc>().unwrap();
        assert_eq!(exc.msg, "sequence item 1: expected str instance, int found");
    }
}
