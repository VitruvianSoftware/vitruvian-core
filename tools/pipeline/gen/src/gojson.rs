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

//! `encoding/json.Unmarshal` as the Go tool used it on a `.pipeline.json`
//! file, kept to Go's behaviour where it shows in the output:
//!
//!  - the whole input is checked first by a copy of Go's scanner, so a
//!    syntax error carries Go's exact text ("invalid character 'x' after
//!    object key", "unexpected end of JSON input");
//!  - object keys match struct fields exactly first, then case-insensitively
//!    (Go's `foldName`), a later duplicate key wins and a map is merged;
//!  - a value of the wrong type records the first `UnmarshalTypeError` and
//!    decoding carries on, as Go's decoder does;
//!  - strings decode with Go's rules: a lone surrogate or invalid UTF-8 byte
//!    becomes U+FFFD.
//!
//! serde_json is used where JSON is produced (src/unit.rs, src/matrix.rs);
//! this reader exists because serde_json's errors, number handling and
//! field matching are not Go's, and the error text reaches stderr.

use crate::gostr::quote;

/// A parsed JSON value. Numbers keep their literal text (Go reports it in
/// errors) and objects keep their keys in document order, duplicates too.
#[derive(Debug, Clone, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Num(String),
    Str(String),
    Arr(Vec<Json>),
    Obj(Vec<(String, Json)>),
}

impl Json {
    /// The word Go's `UnmarshalTypeError` uses for this kind of value.
    pub fn kind(&self) -> &'static str {
        match self {
            Json::Null => "null",
            Json::Bool(_) => "bool",
            Json::Num(_) => "number",
            Json::Str(_) => "string",
            Json::Arr(_) => "array",
            Json::Obj(_) => "object",
        }
    }
}

const MAX_NESTING_DEPTH: usize = 10000;

#[derive(Clone, Copy, PartialEq)]
enum St {
    BeginValueOrEmpty,
    BeginValue,
    BeginStringOrEmpty,
    BeginString,
    InString,
    InStringEsc,
    EscU,
    EscU1,
    EscU12,
    EscU123,
    EndValue,
    EndTop,
    Neg,
    Zero,
    One,
    Dot,
    Dot0,
    E,
    ESign,
    E0,
    T,
    Tr,
    Tru,
    F,
    Fa,
    Fal,
    Fals,
    N,
    Nu,
    Nul,
}

#[derive(Clone, Copy, PartialEq)]
enum Ps {
    ObjectKey,
    ObjectValue,
    ArrayValue,
}

struct Scanner {
    step: St,
    stack: Vec<Ps>,
    end_top: bool,
    err: Option<String>,
}

fn is_space(c: u8) -> bool {
    c == b' ' || c == b'\t' || c == b'\r' || c == b'\n'
}

/// Go's `quoteChar`: the byte as a rune (so 0xff is 'ÿ'), quoted with `'`.
fn quote_char(c: u8) -> String {
    if c == b'\'' {
        return "'\\''".to_string();
    }
    if c == b'"' {
        return "'\"'".to_string();
    }
    let q = quote(&char::from(c).to_string());
    format!("'{}'", &q[1..q.len() - 1])
}

impl Scanner {
    fn new() -> Self {
        Scanner {
            step: St::BeginValue,
            stack: Vec::new(),
            end_top: false,
            err: None,
        }
    }

    fn error(&mut self, c: u8, context: &str) -> bool {
        self.err = Some(format!("invalid character {} {}", quote_char(c), context));
        false
    }

    fn push(&mut self, c: u8, next: St, ps: Ps) -> bool {
        self.step = next;
        self.stack.push(ps);
        if self.stack.len() > MAX_NESTING_DEPTH {
            return self.error(c, "exceeded max depth");
        }
        true
    }

    fn pop(&mut self) {
        self.stack.pop();
        if self.stack.is_empty() {
            self.step = St::EndTop;
            self.end_top = true;
        } else {
            self.step = St::EndValue;
        }
    }

    /// One byte; false on a syntax error (then `err` is set).
    fn feed(&mut self, c: u8) -> bool {
        match self.step {
            St::BeginValueOrEmpty => {
                if is_space(c) {
                    return true;
                }
                if c == b']' {
                    return self.end_value(c);
                }
                self.begin_value(c)
            }
            St::BeginValue => self.begin_value(c),
            St::BeginStringOrEmpty => {
                if is_space(c) {
                    return true;
                }
                if c == b'}' {
                    let n = self.stack.len();
                    self.stack[n - 1] = Ps::ObjectValue;
                    return self.end_value(c);
                }
                self.begin_string(c)
            }
            St::BeginString => self.begin_string(c),
            St::EndValue => self.end_value(c),
            St::EndTop => {
                if !is_space(c) {
                    return self.error(c, "after top-level value");
                }
                true
            }
            St::InString => {
                if c == b'"' {
                    self.step = St::EndValue;
                } else if c == b'\\' {
                    self.step = St::InStringEsc;
                } else if c < 0x20 {
                    return self.error(c, "in string literal");
                }
                true
            }
            St::InStringEsc => match c {
                b'b' | b'f' | b'n' | b'r' | b't' | b'\\' | b'/' | b'"' => {
                    self.step = St::InString;
                    true
                }
                b'u' => {
                    self.step = St::EscU;
                    true
                }
                _ => self.error(c, "in string escape code"),
            },
            St::EscU | St::EscU1 | St::EscU12 | St::EscU123 => {
                if !c.is_ascii_hexdigit() {
                    return self.error(c, "in \\u hexadecimal character escape");
                }
                self.step = match self.step {
                    St::EscU => St::EscU1,
                    St::EscU1 => St::EscU12,
                    St::EscU12 => St::EscU123,
                    _ => St::InString,
                };
                true
            }
            St::Neg => {
                if c == b'0' {
                    self.step = St::Zero;
                    true
                } else if (b'1'..=b'9').contains(&c) {
                    self.step = St::One;
                    true
                } else {
                    self.error(c, "in numeric literal")
                }
            }
            St::One => {
                if c.is_ascii_digit() {
                    return true;
                }
                self.zero(c)
            }
            St::Zero => self.zero(c),
            St::Dot => {
                if c.is_ascii_digit() {
                    self.step = St::Dot0;
                    true
                } else {
                    self.error(c, "after decimal point in numeric literal")
                }
            }
            St::Dot0 => {
                if c.is_ascii_digit() {
                    return true;
                }
                if c == b'e' || c == b'E' {
                    self.step = St::E;
                    return true;
                }
                self.end_value(c)
            }
            St::E => {
                if c == b'+' || c == b'-' {
                    self.step = St::ESign;
                    return true;
                }
                self.e_sign(c)
            }
            St::ESign => self.e_sign(c),
            St::E0 => {
                if c.is_ascii_digit() {
                    return true;
                }
                self.end_value(c)
            }
            St::T => self.lit(c, b'r', St::Tr, "in literal true (expecting 'r')"),
            St::Tr => self.lit(c, b'u', St::Tru, "in literal true (expecting 'u')"),
            St::Tru => self.lit(c, b'e', St::EndValue, "in literal true (expecting 'e')"),
            St::F => self.lit(c, b'a', St::Fa, "in literal false (expecting 'a')"),
            St::Fa => self.lit(c, b'l', St::Fal, "in literal false (expecting 'l')"),
            St::Fal => self.lit(c, b's', St::Fals, "in literal false (expecting 's')"),
            St::Fals => self.lit(c, b'e', St::EndValue, "in literal false (expecting 'e')"),
            St::N => self.lit(c, b'u', St::Nu, "in literal null (expecting 'u')"),
            St::Nu => self.lit(c, b'l', St::Nul, "in literal null (expecting 'l')"),
            St::Nul => self.lit(c, b'l', St::EndValue, "in literal null (expecting 'l')"),
        }
    }

    fn lit(&mut self, c: u8, want: u8, next: St, context: &str) -> bool {
        if c == want {
            self.step = next;
            true
        } else {
            self.error(c, context)
        }
    }

    fn e_sign(&mut self, c: u8) -> bool {
        if c.is_ascii_digit() {
            self.step = St::E0;
            true
        } else {
            self.error(c, "in exponent of numeric literal")
        }
    }

    fn zero(&mut self, c: u8) -> bool {
        if c == b'.' {
            self.step = St::Dot;
            return true;
        }
        if c == b'e' || c == b'E' {
            self.step = St::E;
            return true;
        }
        self.end_value(c)
    }

    fn begin_value(&mut self, c: u8) -> bool {
        if is_space(c) {
            return true;
        }
        match c {
            b'{' => self.push(c, St::BeginStringOrEmpty, Ps::ObjectKey),
            b'[' => self.push(c, St::BeginValueOrEmpty, Ps::ArrayValue),
            b'"' => {
                self.step = St::InString;
                true
            }
            b'-' => {
                self.step = St::Neg;
                true
            }
            b'0' => {
                self.step = St::Zero;
                true
            }
            b't' => {
                self.step = St::T;
                true
            }
            b'f' => {
                self.step = St::F;
                true
            }
            b'n' => {
                self.step = St::N;
                true
            }
            b'1'..=b'9' => {
                self.step = St::One;
                true
            }
            _ => self.error(c, "looking for beginning of value"),
        }
    }

    fn begin_string(&mut self, c: u8) -> bool {
        if is_space(c) {
            return true;
        }
        if c == b'"' {
            self.step = St::InString;
            return true;
        }
        self.error(c, "looking for beginning of object key string")
    }

    fn end_value(&mut self, c: u8) -> bool {
        let n = self.stack.len();
        if n == 0 {
            self.step = St::EndTop;
            self.end_top = true;
            return self.feed(c);
        }
        if is_space(c) {
            self.step = St::EndValue;
            return true;
        }
        match self.stack[n - 1] {
            Ps::ObjectKey => {
                if c == b':' {
                    self.stack[n - 1] = Ps::ObjectValue;
                    self.step = St::BeginValue;
                    return true;
                }
                self.error(c, "after object key")
            }
            Ps::ObjectValue => {
                if c == b',' {
                    self.stack[n - 1] = Ps::ObjectKey;
                    self.step = St::BeginString;
                    return true;
                }
                if c == b'}' {
                    self.pop();
                    return true;
                }
                self.error(c, "after object key:value pair")
            }
            Ps::ArrayValue => {
                if c == b',' {
                    self.step = St::BeginValue;
                    return true;
                }
                if c == b']' {
                    self.pop();
                    return true;
                }
                self.error(c, "after array element")
            }
        }
    }

    fn eof(&mut self) -> Result<(), String> {
        if let Some(e) = &self.err {
            return Err(e.clone());
        }
        if self.end_top {
            return Ok(());
        }
        self.feed(b' ');
        if self.end_top {
            return Ok(());
        }
        Err(self
            .err
            .clone()
            .unwrap_or_else(|| "unexpected end of JSON input".to_string()))
    }
}

/// Go's `checkValid`: the syntax error Unmarshal reports, if any.
pub fn check_valid(data: &[u8]) -> Result<(), String> {
    let mut s = Scanner::new();
    for &c in data {
        if !s.feed(c) {
            return Err(s.err.unwrap_or_default());
        }
    }
    s.eof()
}

/// Parses `data`, which must already have passed [`check_valid`].
pub fn parse_valid(data: &[u8]) -> Json {
    let mut p = Parser { b: data, i: 0 };
    p.value()
}

/// Validates and parses, with Go's syntax-error text.
pub fn parse(data: &[u8]) -> Result<Json, String> {
    check_valid(data)?;
    Ok(parse_valid(data))
}

struct Parser<'a> {
    b: &'a [u8],
    i: usize,
}

impl Parser<'_> {
    fn ws(&mut self) {
        while self.i < self.b.len() && is_space(self.b[self.i]) {
            self.i += 1;
        }
    }

    fn value(&mut self) -> Json {
        self.ws();
        match self.b[self.i] {
            b'{' => {
                self.i += 1;
                let mut kv = Vec::new();
                loop {
                    self.ws();
                    if self.b[self.i] == b'}' {
                        self.i += 1;
                        break;
                    }
                    if self.b[self.i] == b',' {
                        self.i += 1;
                        self.ws();
                    }
                    let k = self.string();
                    self.ws();
                    self.i += 1; // ':'
                    let v = self.value();
                    kv.push((k, v));
                }
                Json::Obj(kv)
            }
            b'[' => {
                self.i += 1;
                let mut items = Vec::new();
                loop {
                    self.ws();
                    if self.b[self.i] == b']' {
                        self.i += 1;
                        break;
                    }
                    if self.b[self.i] == b',' {
                        self.i += 1;
                    }
                    items.push(self.value());
                }
                Json::Arr(items)
            }
            b'"' => Json::Str(self.string()),
            b't' => {
                self.i += 4;
                Json::Bool(true)
            }
            b'f' => {
                self.i += 5;
                Json::Bool(false)
            }
            b'n' => {
                self.i += 4;
                Json::Null
            }
            _ => {
                let start = self.i;
                while self.i < self.b.len()
                    && matches!(
                        self.b[self.i],
                        b'0'..=b'9' | b'-' | b'+' | b'.' | b'e' | b'E'
                    )
                {
                    self.i += 1;
                }
                Json::Num(String::from_utf8_lossy(&self.b[start..self.i]).into_owned())
            }
        }
    }

    fn hex4(&self, at: usize) -> Option<u32> {
        let s = self.b.get(at..at + 4)?;
        u32::from_str_radix(std::str::from_utf8(s).ok()?, 16).ok()
    }

    /// Go's `unquote`, from the opening quote to past the closing one.
    fn string(&mut self) -> String {
        self.i += 1;
        let mut out = String::new();
        loop {
            let c = self.b[self.i];
            match c {
                b'"' => {
                    self.i += 1;
                    return out;
                }
                b'\\' => {
                    let e = self.b[self.i + 1];
                    self.i += 2;
                    match e {
                        b'b' => out.push('\u{8}'),
                        b'f' => out.push('\u{c}'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => {
                            let r = self.hex4(self.i).unwrap_or(0xfffd);
                            self.i += 4;
                            if (0xd800..0xe000).contains(&r) {
                                // A surrogate: valid only as the first half of
                                // a pair written as a second \u escape.
                                if r < 0xdc00
                                    && self.b.get(self.i) == Some(&b'\\')
                                    && self.b.get(self.i + 1) == Some(&b'u')
                                {
                                    if let Some(r2) = self.hex4(self.i + 2) {
                                        if (0xdc00..0xe000).contains(&r2) {
                                            let cp = 0x10000 + ((r - 0xd800) << 10) + (r2 - 0xdc00);
                                            out.push(char::from_u32(cp).unwrap_or('\u{fffd}'));
                                            self.i += 6;
                                            continue;
                                        }
                                    }
                                }
                                out.push('\u{fffd}');
                            } else {
                                out.push(char::from_u32(r).unwrap_or('\u{fffd}'));
                            }
                        }
                        other => out.push(other as char),
                    }
                }
                _ => {
                    let (r, n) = crate::gostr::decode_rune(&self.b[self.i..]);
                    out.push(r.unwrap_or('\u{fffd}'));
                    self.i += n;
                }
            }
        }
    }
}

/// Go's `foldName`: ASCII letters upper-cased, other runes
/// `ToUpper(ToLower(r))`, so "NAME", "Name" and "name" fold together.
pub fn fold_name(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        if c.is_ascii() {
            out.push(c.to_ascii_uppercase());
            continue;
        }
        let lower = single(c.to_lowercase(), c);
        out.push(single(lower.to_uppercase(), lower));
    }
    out
}

/// A case mapping that yields one rune, as Go's simple mappings do; a
/// mapping to several runes (Go has none) keeps the rune.
fn single(mut it: impl Iterator<Item = char>, orig: char) -> char {
    match (it.next(), it.next()) {
        (Some(c), None) => c,
        _ => orig,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn syntax_errors_carry_go_text() {
        let cases: &[(&str, &str)] = &[
            ("", "unexpected end of JSON input"),
            ("  ", "unexpected end of JSON input"),
            ("{\"a\" 1}", "invalid character '1' after object key"),
            (
                "{\"a\":1 \"b\"}",
                "invalid character '\"' after object key:value pair",
            ),
            ("[1 2]", "invalid character '2' after array element"),
            (
                "tru",
                "invalid character ' ' in literal true (expecting 'e')",
            ),
            (
                "{\"a\":\"\\q\"}",
                "invalid character 'q' in string escape code",
            ),
            (
                "{\"a\":\"\\u12g4\"}",
                "invalid character 'g' in \\u hexadecimal character escape",
            ),
            ("-", "invalid character ' ' in numeric literal"),
            (
                "1.",
                "invalid character ' ' after decimal point in numeric literal",
            ),
            (
                "1e+",
                "invalid character ' ' in exponent of numeric literal",
            ),
            (
                "{,",
                "invalid character ',' looking for beginning of object key string",
            ),
            ("01", "invalid character '1' after top-level value"),
            ("{} x", "invalid character 'x' after top-level value"),
            (
                "'",
                "invalid character '\\'' looking for beginning of value",
            ),
            (
                "\u{1}",
                "invalid character '\\x01' looking for beginning of value",
            ),
            (
                &"[".repeat(10001),
                "invalid character '[' exceeded max depth",
            ),
        ];
        for (input, want) in cases {
            assert_eq!(
                check_valid(input.as_bytes()).unwrap_err(),
                *want,
                "input {input:?}"
            );
        }
        assert!(check_valid(b"{\"a\":[1,-0.5e+3,true,false,null,\"x\"]}").is_ok());
    }

    #[test]
    fn parse_keeps_order_and_decodes_strings() {
        let j = parse(br#"{"b":"\u00e9\ud83d\ude00\ud800x","a":1.50,"b":[]}"#).unwrap();
        assert_eq!(
            j,
            Json::Obj(vec![
                ("b".into(), Json::Str("é😀\u{fffd}x".into())),
                ("a".into(), Json::Num("1.50".into())),
                ("b".into(), Json::Arr(vec![])),
            ])
        );
        assert_eq!(
            parse(b"\"a\xffb\"").unwrap(),
            Json::Str("a\u{fffd}b".into())
        );
    }

    #[test]
    fn fold_matches_go() {
        assert_eq!(fold_name("Name"), fold_name("NAME"));
        assert_eq!(fold_name("\u{17f}chema"), "SCHEMA");
    }
}
