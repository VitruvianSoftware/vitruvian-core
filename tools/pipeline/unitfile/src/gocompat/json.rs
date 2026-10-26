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

//! `encoding/json` as the Go tools use it, on top of serde_json.
//!
//! Writing: serde_json does the encoding; [`go_escape`] then applies the
//! one thing Go's encoder does that serde_json does not, HTML-safe escaping
//! of `<`, `>`, `&`, U+2028 and U+2029.
//!
//! Reading: Go first checks the whole input with its scanner, so a syntax
//! error reads as Go's ("invalid character 'o' in literal null (expecting
//! 'u')", "unexpected end of JSON input"); [`check_valid`] is that scanner.
//! The value is then read by serde into an ordered [`GoValue`], and
//! [`Dec`] stores it into fields the way Go's decoder does: keys matched
//! exactly or case-insensitively, the last duplicate wins, null leaves a
//! field alone, and a value of the wrong type is the first error kept,
//! worded as Go words it ("json: cannot unmarshal string into Go struct
//! field RdepsMap.schema of type int").

use std::collections::BTreeMap;
use std::fmt;

use serde::de::{Deserialize, Deserializer, MapAccess, SeqAccess, Visitor};
use serde::Serialize;

/// Go's HTML-safe escaping, applied to serde_json output.
pub fn go_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '<' => out.push_str("\\u003c"),
            '>' => out.push_str("\\u003e"),
            '&' => out.push_str("\\u0026"),
            '\u{2028}' => out.push_str("\\u2028"),
            '\u{2029}' => out.push_str("\\u2029"),
            c => out.push(c),
        }
    }
    out
}

/// `json.Marshal(v)`.
pub fn marshal<T: Serialize>(v: &T) -> String {
    go_escape(&serde_json::to_string(v).expect("json encoding cannot fail"))
}

/// `json.MarshalIndent(v, "", "  ")`.
pub fn marshal_indent<T: Serialize>(v: &T) -> String {
    go_escape(&serde_json::to_string_pretty(v).expect("json encoding cannot fail"))
}

// ---- Go's scanner ----------------------------------------------------------

#[derive(Clone, Copy, PartialEq)]
enum Step {
    BeginValue,
    BeginValueOrEmpty,
    BeginStringOrEmpty,
    BeginString,
    EndValue,
    EndTop,
    InString,
    InStringEsc,
    InStringEscU(u8),
    Neg,
    One,
    Zero,
    Dot,
    Dot0,
    E,
    ESign,
    E0,
    Lit(&'static [u8], &'static str, usize),
}

#[derive(Clone, Copy, PartialEq)]
enum Parse {
    ObjectKey,
    ObjectValue,
    ArrayValue,
}

struct Scanner {
    step: Step,
    parse: Vec<Parse>,
    end_top: bool,
    err: Option<String>,
}

fn quote_char(c: u8) -> String {
    match c {
        b'\'' => "'\\''".to_string(),
        b'"' => "'\"'".to_string(),
        _ => {
            let s = super::quote::quote(&char::from(c).to_string());
            format!("'{}'", &s[1..s.len() - 1])
        }
    }
}

fn is_space(c: u8) -> bool {
    matches!(c, b' ' | b'\t' | b'\r' | b'\n')
}

fn is_hex(c: u8) -> bool {
    c.is_ascii_hexdigit()
}

impl Scanner {
    fn error(&mut self, c: u8, context: &str) -> bool {
        self.err = Some(format!("invalid character {} {}", quote_char(c), context));
        false
    }

    fn push(&mut self, c: u8, p: Parse) -> bool {
        self.parse.push(p);
        if self.parse.len() > 10000 {
            return self.error(c, "exceeded max depth");
        }
        true
    }

    fn pop(&mut self) {
        self.parse.pop();
        if self.parse.is_empty() {
            self.step = Step::EndTop;
            self.end_top = true;
        } else {
            self.step = Step::EndValue;
        }
    }

    /// Feeds one byte; false on a syntax error.
    fn feed(&mut self, c: u8) -> bool {
        match self.step {
            Step::BeginValueOrEmpty => {
                if is_space(c) {
                    return true;
                }
                if c == b']' {
                    return self.end_value(c);
                }
                self.begin_value(c)
            }
            Step::BeginValue => self.begin_value(c),
            Step::BeginStringOrEmpty => {
                if is_space(c) {
                    return true;
                }
                if c == b'}' {
                    let n = self.parse.len();
                    self.parse[n - 1] = Parse::ObjectValue;
                    return self.end_value(c);
                }
                self.begin_string(c)
            }
            Step::BeginString => self.begin_string(c),
            Step::EndValue => self.end_value(c),
            Step::EndTop => {
                if !is_space(c) {
                    self.error(c, "after top-level value");
                }
                // Go's checkValid stops at the first error but keeps going
                // after scanEnd; the error is reported at eof.
                self.err.is_none()
            }
            Step::InString => {
                if c == b'"' {
                    self.step = Step::EndValue;
                    return true;
                }
                if c == b'\\' {
                    self.step = Step::InStringEsc;
                    return true;
                }
                if c < 0x20 {
                    return self.error(c, "in string literal");
                }
                true
            }
            Step::InStringEsc => match c {
                b'b' | b'f' | b'n' | b'r' | b't' | b'\\' | b'/' | b'"' => {
                    self.step = Step::InString;
                    true
                }
                b'u' => {
                    self.step = Step::InStringEscU(0);
                    true
                }
                _ => self.error(c, "in string escape code"),
            },
            Step::InStringEscU(n) => {
                if is_hex(c) {
                    self.step = if n == 3 {
                        Step::InString
                    } else {
                        Step::InStringEscU(n + 1)
                    };
                    return true;
                }
                self.error(c, "in \\u hexadecimal character escape")
            }
            Step::Neg => {
                if c == b'0' {
                    self.step = Step::Zero;
                    return true;
                }
                if (b'1'..=b'9').contains(&c) {
                    self.step = Step::One;
                    return true;
                }
                self.error(c, "in numeric literal")
            }
            Step::One => {
                if c.is_ascii_digit() {
                    return true;
                }
                self.zero(c)
            }
            Step::Zero => self.zero(c),
            Step::Dot => {
                if c.is_ascii_digit() {
                    self.step = Step::Dot0;
                    return true;
                }
                self.error(c, "after decimal point in numeric literal")
            }
            Step::Dot0 => {
                if c.is_ascii_digit() {
                    return true;
                }
                if c == b'e' || c == b'E' {
                    self.step = Step::E;
                    return true;
                }
                self.end_value(c)
            }
            Step::E => {
                if c == b'+' || c == b'-' {
                    self.step = Step::ESign;
                    return true;
                }
                self.e_sign(c)
            }
            Step::ESign => self.e_sign(c),
            Step::E0 => {
                if c.is_ascii_digit() {
                    return true;
                }
                self.end_value(c)
            }
            Step::Lit(word, name, i) => {
                if c == word[i] {
                    self.step = if i + 1 == word.len() {
                        Step::EndValue
                    } else {
                        Step::Lit(word, name, i + 1)
                    };
                    return true;
                }
                let ctx = format!("in literal {name} (expecting '{}')", word[i] as char);
                self.error(c, &ctx)
            }
        }
    }

    fn e_sign(&mut self, c: u8) -> bool {
        if c.is_ascii_digit() {
            self.step = Step::E0;
            return true;
        }
        self.error(c, "in exponent of numeric literal")
    }

    fn zero(&mut self, c: u8) -> bool {
        if c == b'.' {
            self.step = Step::Dot;
            return true;
        }
        if c == b'e' || c == b'E' {
            self.step = Step::E;
            return true;
        }
        self.end_value(c)
    }

    fn begin_value(&mut self, c: u8) -> bool {
        if is_space(c) {
            return true;
        }
        match c {
            b'{' => {
                self.step = Step::BeginStringOrEmpty;
                self.push(c, Parse::ObjectKey)
            }
            b'[' => {
                self.step = Step::BeginValueOrEmpty;
                self.push(c, Parse::ArrayValue)
            }
            b'"' => {
                self.step = Step::InString;
                true
            }
            b'-' => {
                self.step = Step::Neg;
                true
            }
            b'0' => {
                self.step = Step::Zero;
                true
            }
            b't' => {
                self.step = Step::Lit(b"true", "true", 1);
                true
            }
            b'f' => {
                self.step = Step::Lit(b"false", "false", 1);
                true
            }
            b'n' => {
                self.step = Step::Lit(b"null", "null", 1);
                true
            }
            b'1'..=b'9' => {
                self.step = Step::One;
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
            self.step = Step::InString;
            return true;
        }
        self.error(c, "looking for beginning of object key string")
    }

    fn end_value(&mut self, c: u8) -> bool {
        let n = self.parse.len();
        if n == 0 {
            self.step = Step::EndTop;
            self.end_top = true;
            if !is_space(c) {
                return self.error(c, "after top-level value");
            }
            return true;
        }
        if is_space(c) {
            self.step = Step::EndValue;
            return true;
        }
        match self.parse[n - 1] {
            Parse::ObjectKey => {
                if c == b':' {
                    self.parse[n - 1] = Parse::ObjectValue;
                    self.step = Step::BeginValue;
                    return true;
                }
                self.error(c, "after object key")
            }
            Parse::ObjectValue => {
                if c == b',' {
                    self.parse[n - 1] = Parse::ObjectKey;
                    self.step = Step::BeginString;
                    return true;
                }
                if c == b'}' {
                    self.pop();
                    return true;
                }
                self.error(c, "after object key:value pair")
            }
            Parse::ArrayValue => {
                if c == b',' {
                    self.step = Step::BeginValue;
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
}

/// Go's `checkValid`: the syntax error `json.Unmarshal` would report.
pub fn check_valid(data: &[u8]) -> Result<(), String> {
    let mut s = Scanner {
        step: Step::BeginValue,
        parse: Vec::new(),
        end_top: false,
        err: None,
    };
    for &c in data {
        if !s.feed(c) {
            return Err(s.err.unwrap_or_default());
        }
    }
    // eof
    if s.end_top {
        return Ok(());
    }
    s.feed(b' ');
    if let Some(e) = s.err {
        return Err(e);
    }
    if s.end_top {
        return Ok(());
    }
    Err("unexpected end of JSON input".to_string())
}

/// The length of the first JSON value in `data` (which starts at the
/// value), as `json.Decoder` reads one value off a stream: a scalar ends at
/// the first byte that cannot continue it, an object or array at its
/// closing bracket. "unexpected EOF" if the data ends inside the value.
pub fn value_len(data: &[u8]) -> Result<usize, String> {
    let mut s = Scanner {
        step: Step::BeginValue,
        parse: Vec::new(),
        end_top: false,
        err: None,
    };
    for (i, &c) in data.iter().enumerate() {
        let depth_before = s.parse.len();
        let ok = s.feed(c);
        if s.end_top {
            return Ok(if depth_before > 0 { i + 1 } else { i });
        }
        if !ok {
            return Err(s.err.unwrap_or_default());
        }
    }
    s.feed(b' ');
    if s.end_top {
        return Ok(data.len());
    }
    if let Some(e) = s.err {
        return Err(e);
    }
    Err("unexpected EOF".to_string())
}

// ---- an ordered value, read by serde ---------------------------------------

/// A JSON value with object keys in the order written.
#[derive(Debug, Clone, PartialEq)]
pub enum GoValue {
    Null,
    Bool(bool),
    /// The number's text, and whether it was a whole number.
    Num(String, bool),
    Str(String),
    Arr(Vec<GoValue>),
    Obj(Vec<(String, GoValue)>),
}

impl GoValue {
    /// The word Go's UnmarshalTypeError uses for this kind of value.
    fn kind(&self) -> &'static str {
        match self {
            GoValue::Null => "null",
            GoValue::Bool(_) => "bool",
            GoValue::Num(..) => "number",
            GoValue::Str(_) => "string",
            GoValue::Arr(_) => "array",
            GoValue::Obj(_) => "object",
        }
    }
}

struct GoValueVisitor;

impl<'de> Visitor<'de> for GoValueVisitor {
    type Value = GoValue;

    fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str("any JSON value")
    }
    fn visit_bool<E>(self, v: bool) -> Result<GoValue, E> {
        Ok(GoValue::Bool(v))
    }
    fn visit_i64<E>(self, v: i64) -> Result<GoValue, E> {
        Ok(GoValue::Num(v.to_string(), true))
    }
    fn visit_u64<E>(self, v: u64) -> Result<GoValue, E> {
        Ok(GoValue::Num(v.to_string(), true))
    }
    fn visit_f64<E>(self, v: f64) -> Result<GoValue, E> {
        Ok(GoValue::Num(format!("{v:?}"), false))
    }
    fn visit_str<E>(self, v: &str) -> Result<GoValue, E> {
        Ok(GoValue::Str(v.to_string()))
    }
    fn visit_string<E>(self, v: String) -> Result<GoValue, E> {
        Ok(GoValue::Str(v))
    }
    fn visit_unit<E>(self) -> Result<GoValue, E> {
        Ok(GoValue::Null)
    }
    fn visit_none<E>(self) -> Result<GoValue, E> {
        Ok(GoValue::Null)
    }
    fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<GoValue, A::Error> {
        let mut v = Vec::new();
        while let Some(x) = seq.next_element()? {
            v.push(x);
        }
        Ok(GoValue::Arr(v))
    }
    fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<GoValue, A::Error> {
        let mut v = Vec::new();
        while let Some((k, x)) = map.next_entry::<String, GoValue>()? {
            v.push((k, x));
        }
        Ok(GoValue::Obj(v))
    }
}

impl<'de> Deserialize<'de> for GoValue {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<GoValue, D::Error> {
        d.deserialize_any(GoValueVisitor)
    }
}

/// Reads `data` as Go's json.Unmarshal would see it, or Go's syntax error.
pub fn parse(data: &[u8]) -> Result<GoValue, String> {
    check_valid(data)?;
    let text = String::from_utf8_lossy(data);
    let mut de = serde_json::Deserializer::from_str(&text);
    GoValue::deserialize(&mut de).map_err(|e| e.to_string())
}

// ---- storing into fields, as Go's decoder does -------------------------------

/// Go's decodeState: the first type error and where it happened.
#[derive(Default)]
pub struct Dec {
    err: Option<String>,
    struct_name: Option<&'static str>,
    fields: Vec<&'static str>,
}

fn fold_eq(a: &str, b: &str) -> bool {
    fn fold(c: char) -> char {
        match c {
            '\u{212a}' => 'k',
            '\u{17f}' => 's',
            c => c.to_ascii_lowercase(),
        }
    }
    a.chars().map(fold).eq(b.chars().map(fold))
}

impl Dec {
    pub fn new() -> Dec {
        Dec::default()
    }

    /// The first error, as `json.Unmarshal` returns it.
    pub fn finish(self) -> Result<(), String> {
        match self.err {
            Some(e) => Err(e),
            None => Ok(()),
        }
    }

    fn type_err(&mut self, value: &str, ty: &str) {
        if self.err.is_some() {
            return;
        }
        self.err = Some(if self.struct_name.is_some() || !self.fields.is_empty() {
            format!(
                "json: cannot unmarshal {value} into Go struct field {}.{} of type {ty}",
                self.struct_name.unwrap_or(""),
                self.fields.join(".")
            )
        } else {
            format!("json: cannot unmarshal {value} into Go value of type {ty}")
        });
    }

    pub fn string(&mut self, v: &GoValue, dst: &mut String) {
        match v {
            GoValue::Str(s) => *dst = s.clone(),
            GoValue::Null => {}
            other => self.type_err(other.kind(), "string"),
        }
    }

    pub fn int(&mut self, v: &GoValue, dst: &mut i64) {
        match v {
            GoValue::Num(t, whole) => match (whole, t.parse::<i64>()) {
                (true, Ok(n)) => *dst = n,
                _ => self.type_err(&format!("number {t}"), "int"),
            },
            GoValue::Null => {}
            other => self.type_err(other.kind(), "int"),
        }
    }

    pub fn bool(&mut self, v: &GoValue, dst: &mut bool) {
        match v {
            GoValue::Bool(b) => *dst = *b,
            GoValue::Null => {}
            other => self.type_err(other.kind(), "bool"),
        }
    }

    /// `[]string`; None is Go's nil slice.
    pub fn strings(&mut self, v: &GoValue, dst: &mut Option<Vec<String>>) {
        match v {
            GoValue::Arr(items) => {
                let mut out = Vec::with_capacity(items.len());
                for it in items {
                    let mut s = String::new();
                    self.string(it, &mut s);
                    out.push(s);
                }
                *dst = Some(out);
            }
            GoValue::Null => *dst = None,
            other => self.type_err(other.kind(), "[]string"),
        }
    }

    /// `map[string][]string`.
    pub fn strings_map(&mut self, v: &GoValue, dst: &mut Option<BTreeMap<String, Vec<String>>>) {
        match v {
            GoValue::Obj(pairs) => {
                let m = dst.get_or_insert_with(BTreeMap::new);
                for (k, x) in pairs {
                    let mut s: Option<Vec<String>> = None;
                    self.strings(x, &mut s);
                    m.insert(k.clone(), s.unwrap_or_default());
                }
            }
            GoValue::Null => *dst = None,
            other => self.type_err(other.kind(), "map[string][]string"),
        }
    }

    /// A slice of structs: `each` reads one element.
    pub fn slice<T: Default>(
        &mut self,
        v: &GoValue,
        ty: &str,
        dst: &mut Option<Vec<T>>,
        mut each: impl FnMut(&mut Dec, &GoValue, &mut T),
    ) {
        match v {
            GoValue::Arr(items) => {
                let mut out = Vec::with_capacity(items.len());
                for it in items {
                    let mut t = T::default();
                    each(self, it, &mut t);
                    out.push(t);
                }
                *dst = Some(out);
            }
            GoValue::Null => *dst = None,
            other => self.type_err(other.kind(), ty),
        }
    }

    /// A struct named `struct_name` (Go type `ty`) with the given JSON field
    /// names: `field` is called for each key that matches one, with the
    /// field's name, in the order the keys were written.
    pub fn object(
        &mut self,
        v: &GoValue,
        struct_name: &'static str,
        ty: &str,
        names: &[&'static str],
        mut field: impl FnMut(&mut Dec, &'static str, &GoValue),
    ) {
        let pairs = match v {
            GoValue::Obj(p) => p,
            GoValue::Null => return,
            other => {
                self.type_err(other.kind(), ty);
                return;
            }
        };
        for (k, x) in pairs {
            let name = names
                .iter()
                .find(|n| **n == k.as_str())
                .or_else(|| names.iter().find(|n| fold_eq(n, k)));
            let Some(&name) = name else { continue };
            let (saved_struct, saved_len) = (self.struct_name, self.fields.len());
            self.fields.push(name);
            self.struct_name = Some(struct_name);
            field(self, name, x);
            self.fields.truncate(saved_len);
            self.struct_name = saved_struct;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn syntax_errors_read_like_go() {
        assert_eq!(
            check_valid(b"not json").unwrap_err(),
            "invalid character 'o' in literal null (expecting 'u')"
        );
        assert_eq!(
            check_valid(b"{\"a\":").unwrap_err(),
            "unexpected end of JSON input"
        );
        assert_eq!(
            check_valid(b"").unwrap_err(),
            "unexpected end of JSON input"
        );
        assert_eq!(
            check_valid(b"{} x").unwrap_err(),
            "invalid character 'x' after top-level value"
        );
        assert_eq!(
            check_valid(b"[1,]").unwrap_err(),
            "invalid character ']' looking for beginning of value"
        );
        assert_eq!(
            check_valid(b"{\"a\" 1}").unwrap_err(),
            "invalid character '1' after object key"
        );
        assert_eq!(
            check_valid(b"\"\\q\"").unwrap_err(),
            "invalid character 'q' in string escape code"
        );
        assert_eq!(
            check_valid(b"01").unwrap_err(),
            "invalid character '1' after top-level value"
        );
        assert!(check_valid(b" {\"a\": [1, -2.5e3, true, null, \"x\"]} ").is_ok());
        assert!(check_valid(b"5").is_ok());
    }

    #[test]
    fn typed_decoding_reads_like_go() {
        let v = parse(br#"{"Schema": "1", "commit": "abc"}"#).unwrap();
        let mut d = Dec::new();
        let (mut schema, mut commit) = (0i64, String::new());
        d.object(
            &v,
            "RdepsMap",
            "main.RdepsMap",
            &["schema", "commit"],
            |d, n, x| match n {
                "schema" => d.int(x, &mut schema),
                _ => d.string(x, &mut commit),
            },
        );
        assert_eq!(commit, "abc");
        assert_eq!(
            d.finish().unwrap_err(),
            "json: cannot unmarshal string into Go struct field RdepsMap.schema of type int"
        );
        let mut d = Dec::new();
        d.object(
            &parse(b"[]").unwrap(),
            "RdepsMap",
            "main.RdepsMap",
            &[],
            |_, _, _| {},
        );
        assert_eq!(
            d.finish().unwrap_err(),
            "json: cannot unmarshal array into Go value of type main.RdepsMap"
        );
    }

    #[test]
    fn escapes_like_go() {
        assert_eq!(marshal(&"<a & b>"), r#""\u003ca \u0026 b\u003e""#);
    }
}
