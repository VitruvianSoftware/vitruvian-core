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

//! `git show <rev>:<file> | jq -S 'del(.version)'`, compared across two
//! revisions, without jq.
//!
//! The script only ever asks whether jq's output for the old file equals its
//! output for the new one, with any failure (git or jq) appended as
//! `UNPARSEABLE_OLD`/`UNPARSEABLE_NEW` so a failure on either side can never
//! compare equal. So this module answers exactly that: both sides must parse
//! the way jq 1.7+ parses (a stream of values; its lenient number literals;
//! `nan`; a leading BOM; invalid UTF-8 replaced), `del(.version)` must succeed
//! on every value (objects and null only), and the canonical outputs must be
//! identical.
//!
//! This is a hand-written scanner rather than serde_json because jq prints a
//! number LITERAL in its decNumber canonical form (`1.000` stays `1.000`,
//! `1E2` becomes `1E+2`), so `1.0` and `1` differ in its output; serde_json
//! (without `arbitrary_precision`, which this repo's crate hub does not
//! enable) has already turned both into the same double.
//!
//! Divergences: matches jq 1.7 and 1.8 (jq 1.6 printed numbers through a
//! double, so `1.0` and `1` compared equal there); exponents beyond i64 and
//! NaN payloads are not modelled; invalid UTF-8 is replaced per Rust's lossy
//! decoder, which can count replacement characters differently from jq's.

use std::collections::BTreeMap;

#[derive(Clone, Debug, PartialEq)]
pub enum JqVal {
    Null,
    Bool(bool),
    /// The number exactly as jq would print it.
    Num(String),
    Str(String),
    Arr(Vec<JqVal>),
    Obj(BTreeMap<String, JqVal>),
}

struct Parser<'a> {
    b: &'a [u8],
    i: usize,
}

fn is_ws(c: u8) -> bool {
    matches!(c, b' ' | b'\t' | b'\r' | b'\n')
}

fn is_structural(c: u8) -> bool {
    matches!(c, b'[' | b'{' | b']' | b'}' | b',' | b':' | b'"')
}

impl<'a> Parser<'a> {
    fn skip_ws(&mut self) {
        while self.i < self.b.len() && is_ws(self.b[self.i]) {
            self.i += 1;
        }
    }

    fn value(&mut self) -> Result<JqVal, ()> {
        self.skip_ws();
        let c = *self.b.get(self.i).ok_or(())?;
        match c {
            b'{' => {
                self.i += 1;
                let mut m = BTreeMap::new();
                self.skip_ws();
                if self.b.get(self.i) == Some(&b'}') {
                    self.i += 1;
                    return Ok(JqVal::Obj(m));
                }
                loop {
                    self.skip_ws();
                    if self.b.get(self.i) != Some(&b'"') {
                        return Err(());
                    }
                    let k = self.string()?;
                    self.skip_ws();
                    if self.b.get(self.i) != Some(&b':') {
                        return Err(());
                    }
                    self.i += 1;
                    let v = self.value()?;
                    m.insert(k, v);
                    self.skip_ws();
                    match self.b.get(self.i) {
                        Some(b',') => self.i += 1,
                        Some(b'}') => {
                            self.i += 1;
                            return Ok(JqVal::Obj(m));
                        }
                        _ => return Err(()),
                    }
                }
            }
            b'[' => {
                self.i += 1;
                let mut v = Vec::new();
                self.skip_ws();
                if self.b.get(self.i) == Some(&b']') {
                    self.i += 1;
                    return Ok(JqVal::Arr(v));
                }
                loop {
                    v.push(self.value()?);
                    self.skip_ws();
                    match self.b.get(self.i) {
                        Some(b',') => self.i += 1,
                        Some(b']') => {
                            self.i += 1;
                            return Ok(JqVal::Arr(v));
                        }
                        _ => return Err(()),
                    }
                }
            }
            b'"' => Ok(JqVal::Str(self.string()?)),
            b']' | b'}' | b',' | b':' => Err(()),
            _ => {
                let start = self.i;
                while self.i < self.b.len()
                    && !is_ws(self.b[self.i])
                    && !is_structural(self.b[self.i])
                {
                    self.i += 1;
                }
                literal(&self.b[start..self.i])
            }
        }
    }

    fn hex4(&mut self) -> Result<u32, ()> {
        let h = self.b.get(self.i..self.i + 4).ok_or(())?;
        let s = std::str::from_utf8(h).map_err(|_| ())?;
        let v = u32::from_str_radix(s, 16).map_err(|_| ())?;
        self.i += 4;
        Ok(v)
    }

    /// At the opening quote.
    fn string(&mut self) -> Result<String, ()> {
        self.i += 1;
        let mut raw: Vec<u8> = Vec::new();
        loop {
            let c = *self.b.get(self.i).ok_or(())?;
            self.i += 1;
            match c {
                b'"' => break,
                b'\\' => {
                    let e = *self.b.get(self.i).ok_or(())?;
                    self.i += 1;
                    let ch = match e {
                        b'"' => '"',
                        b'\\' => '\\',
                        b'/' => '/',
                        b'b' => '\u{8}',
                        b'f' => '\u{c}',
                        b'n' => '\n',
                        b'r' => '\r',
                        b't' => '\t',
                        b'u' => {
                            let hi = self.hex4()?;
                            let cp = if (0xd800..0xdc00).contains(&hi) {
                                if self.b.get(self.i..self.i + 2) != Some(b"\\u") {
                                    return Err(());
                                }
                                self.i += 2;
                                let lo = self.hex4()?;
                                if !(0xdc00..0xe000).contains(&lo) {
                                    return Err(());
                                }
                                0x10000 + ((hi - 0xd800) << 10) + (lo - 0xdc00)
                            } else if (0xdc00..0xe000).contains(&hi) {
                                return Err(());
                            } else {
                                hi
                            };
                            char::from_u32(cp).ok_or(())?
                        }
                        _ => return Err(()),
                    };
                    let mut buf = [0u8; 4];
                    raw.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                }
                c if c < 0x20 => return Err(()),
                c => raw.push(c),
            }
        }
        Ok(String::from_utf8_lossy(&raw).into_owned())
    }
}

fn literal(tok: &[u8]) -> Result<JqVal, ()> {
    match tok {
        b"true" => return Ok(JqVal::Bool(true)),
        b"false" => return Ok(JqVal::Bool(false)),
        b"null" | b"nan" => return Ok(JqVal::Null),
        _ => {}
    }
    number(tok).ok_or(())
}

/// A jq number literal (decNumber's grammar), as jq prints it.
fn number(tok: &[u8]) -> Option<JqVal> {
    let s = std::str::from_utf8(tok).ok()?;
    let (neg, body) = match s.as_bytes().first()? {
        b'-' => (true, &s[1..]),
        b'+' => (false, &s[1..]),
        _ => (false, s),
    };
    let lower = body.to_ascii_lowercase();
    if lower == "inf" || lower == "infinity" {
        let v = if neg {
            "-1.7976931348623157e+308"
        } else {
            "1.7976931348623157e+308"
        };
        return Some(JqVal::Num(v.to_string()));
    }
    let nan_body = lower.strip_prefix('s').unwrap_or(&lower);
    if let Some(payload) = nan_body.strip_prefix("nan") {
        if payload.bytes().all(|c| c.is_ascii_digit()) {
            return Some(JqVal::Null);
        }
        return None;
    }
    let b = body.as_bytes();
    let mut i = 0;
    let mut int = String::new();
    while i < b.len() && b[i].is_ascii_digit() {
        int.push(b[i] as char);
        i += 1;
    }
    let mut frac = String::new();
    if i < b.len() && b[i] == b'.' {
        i += 1;
        while i < b.len() && b[i].is_ascii_digit() {
            frac.push(b[i] as char);
            i += 1;
        }
    }
    if int.is_empty() && frac.is_empty() {
        return None;
    }
    let mut exp: i64 = 0;
    if i < b.len() && (b[i] == b'e' || b[i] == b'E') {
        i += 1;
        let mut eneg = false;
        if i < b.len() && (b[i] == b'+' || b[i] == b'-') {
            eneg = b[i] == b'-';
            i += 1;
        }
        let start = i;
        while i < b.len() && b[i].is_ascii_digit() {
            exp = exp.saturating_mul(10).saturating_add((b[i] - b'0') as i64);
            i += 1;
        }
        if i == start {
            return None;
        }
        if eneg {
            exp = -exp;
        }
    }
    if i != b.len() {
        return None;
    }
    let digits = format!("{}{}", int, frac);
    let coeff = digits.trim_start_matches('0');
    let coeff = if coeff.is_empty() { "0" } else { coeff };
    let exponent = exp.saturating_sub(frac.len() as i64);
    Some(JqVal::Num(format!(
        "{}{}",
        if neg { "-" } else { "" },
        sci_string(coeff, exponent)
    )))
}

/// decNumber's to-scientific-string for a coefficient and exponent.
fn sci_string(coeff: &str, exponent: i64) -> String {
    let n = coeff.len() as i64;
    let adjusted = exponent + n - 1;
    if exponent <= 0 && adjusted >= -6 {
        if exponent == 0 {
            return coeff.to_string();
        }
        let pos = n + exponent;
        if pos > 0 {
            format!("{}.{}", &coeff[..pos as usize], &coeff[pos as usize..])
        } else {
            format!("0.{}{}", "0".repeat((-pos) as usize), coeff)
        }
    } else {
        let mut s = coeff[..1].to_string();
        if n > 1 {
            s.push('.');
            s.push_str(&coeff[1..]);
        }
        s.push('E');
        s.push(if adjusted < 0 { '-' } else { '+' });
        s.push_str(&adjusted.unsigned_abs().to_string());
        s
    }
}

/// Every value jq reads from `input`, or `None` if jq would report a parse
/// error anywhere in it.
pub fn parse_stream(input: &[u8]) -> Option<Vec<JqVal>> {
    let b = input.strip_prefix(b"\xef\xbb\xbf").unwrap_or(input);
    let mut p = Parser { b, i: 0 };
    let mut out = Vec::new();
    loop {
        p.skip_ws();
        if p.i >= p.b.len() {
            return Some(out);
        }
        out.push(p.value().ok()?);
    }
}

/// `del(.version)` over a stream; `None` if any value is not an object or null.
pub fn del_version(vals: Vec<JqVal>) -> Option<Vec<JqVal>> {
    vals.into_iter()
        .map(|v| match v {
            JqVal::Obj(mut m) => {
                m.remove("version");
                Some(JqVal::Obj(m))
            }
            JqVal::Null => Some(JqVal::Null),
            _ => None,
        })
        .collect()
}

/// The comparison the script makes: `_old = $(git show base:f | jq -S
/// 'del(.version)' || echo UNPARSEABLE_OLD)`, likewise `_new`, then `=`.
/// `None` stands for a failed `git show`.
pub fn same_without_version(old: Option<&[u8]>, new: Option<&[u8]>) -> bool {
    let canon = |side: Option<&[u8]>| side.and_then(parse_stream).and_then(del_version);
    match (canon(old), canon(new)) {
        (Some(a), Some(b)) => a == b,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn num(s: &str) -> String {
        match parse_stream(s.as_bytes()).unwrap().remove(0) {
            JqVal::Num(n) => n,
            JqVal::Null => "null".into(),
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn numbers_print_like_jq() {
        // Each pair observed from jq 1.7.1 and 1.8.2.
        for (lit, want) in [
            ("1.000", "1.000"),
            ("1E2", "1E+2"),
            ("1.0", "1.0"),
            ("100000000000000000001", "100000000000000000001"),
            ("0.1e1", "1"),
            ("-0", "-0"),
            ("1.5e300", "1.5E+300"),
            ("-0.0", "-0.0"),
            ("1e1000", "1E+1000"),
            ("01", "1"),
            ("+1", "1"),
            (".5", "0.5"),
            ("1.", "1"),
            ("0.10", "0.10"),
            ("1.5e-7", "1.5E-7"),
            ("0.0000001", "1E-7"),
            ("0e5", "0E+5"),
            ("123e-2", "1.23"),
            ("-1.20E+3", "-1.20E+3"),
            ("Infinity", "1.7976931348623157e+308"),
            ("-Infinity", "-1.7976931348623157e+308"),
            ("infinity", "1.7976931348623157e+308"),
            ("NaN", "null"),
            ("-nan", "null"),
        ] {
            assert_eq!(num(lit), want, "{lit}");
        }
    }

    #[test]
    fn parse_errors_like_jq() {
        for bad in [
            "{\"x\":1,}",
            "{'x':1}",
            "{\"x\":\"\\ud800\"}",
            "{\"x\":\"a\tb\"}",
            "{\"x\":\"\\q\"}",
            "[1,2,]",
            "{\"x\":-}",
            "{\"x\":1e}",
            "{\"x\":1}x",
            "tru",
            "{1:2}",
        ] {
            assert!(parse_stream(bad.as_bytes()).is_none(), "{bad}");
        }
        assert_eq!(parse_stream(b"").unwrap(), vec![]);
        assert_eq!(parse_stream(b"{}{} 1").unwrap().len(), 3);
        assert!(parse_stream(b"\xef\xbb\xbf{\"x\":1}").is_some());
    }

    #[test]
    fn version_only_changes_compare_equal() {
        let a = br#"{"name":"x","version":"1.0.0","dependencies":{"a":"^1"}}"#;
        let b = br#"{"dependencies": {"a": "^1"}, "version": "1.0.1", "name": "x"}"#;
        assert!(same_without_version(Some(a), Some(b)));
        let c = br#"{"name":"x","version":"1.0.1","dependencies":{"a":"^2"}}"#;
        assert!(!same_without_version(Some(a), Some(c)));
        assert!(!same_without_version(None, Some(b)));
        assert!(!same_without_version(Some(b"[]"), Some(b"[]")));
        assert!(same_without_version(Some(b""), Some(b"  \n")));
        assert!(same_without_version(Some(b"null"), Some(b"nan")));
        assert!(!same_without_version(
            Some(br#"{"a":1}"#),
            Some(br#"{"a":1.0}"#)
        ));
        assert!(same_without_version(
            Some(br#"{"a":1,"a":2}"#),
            Some(br#"{"a":2}"#)
        ));
    }
}
