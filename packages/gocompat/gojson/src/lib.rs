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

//! Go's `encoding/json` behaviour on top of `serde_json`.
//!
//! Covers:
//! - Marshaling via [`GoFormatter`] and [`IndentFormatter`] (escaping `<`, `>`,
//!   `&`, `U+2028`, `U+2029`; Go's `float32`/`float64` formatting; `MarshalIndent`
//!   prefixes/indents with empty containers on one line; and byte-level invalid
//!   UTF-8 escaping via [`marshal_raw_string`]).
//! - Go's byte-by-byte UTF-8 string decoding ([`go_string`]).
//! - Go's exact JSON scanner ([`check_valid`] and streaming [`value_len`]) with
//!   `MAX_DEPTH = 10000` and identical syntax error text.
//! - Iterative AST parsing ([`parse`], [`GoValue`]) preserving exact number
//!   literals, duplicate keys, byte-by-byte invalid UTF-8 replacement, and lone
//!   surrogate replacement with `U+FFFD`.
//! - Typed struct decoding ([`Dec`], [`GoSlice`], [`decode_string_map`]) with
//!   exact-first then `unicode.SimpleFold` field matching, backing-array slice
//!   reuse on duplicate keys, and Go's exact `json: cannot unmarshal ...` errors.

use serde::Serialize;
use std::collections::BTreeMap;
use std::io;
use vitruvian_gocompat::{gostd, unicode};

const MAX_DEPTH: usize = 10000;

// ---------------------------------------------------------------------------
// emission
// ---------------------------------------------------------------------------

/// Escapes `<`, `>`, `&`, `U+2028`, and `U+2029` inside an already-encoded JSON string.
pub fn go_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '<' => out.push_str("\\u003c"),
            '>' => out.push_str("\\u003e"),
            '&' => out.push_str("\\u0026"),
            '\u{2028}' => out.push_str("\\u2028"),
            '\u{2029}' => out.push_str("\\u2029"),
            _ => out.push(c),
        }
    }
    out
}

fn format_go_float<W: ?Sized + io::Write>(
    w: &mut W,
    is_neg: bool,
    is_zero: bool,
    sci_abs: &str,
    use_fixed: bool,
) -> io::Result<()> {
    if is_zero {
        return w.write_all(if is_neg { b"-0" } else { b"0" });
    }
    if is_neg {
        w.write_all(b"-")?;
    }
    let (mantissa, exp_str) = sci_abs.split_once('e').unwrap_or((sci_abs, "0"));
    let exp: isize = exp_str.parse().unwrap_or(0);
    if !use_fixed {
        w.write_all(mantissa.as_bytes())?;
        return if exp >= 0 {
            write!(w, "e+{exp}")
        } else {
            write!(w, "e{exp}")
        };
    }
    let digits: Vec<u8> = mantissa.bytes().filter(|&b| b != b'.').collect();
    let dec_pos = exp + 1;
    if dec_pos <= 0 {
        w.write_all(b"0.")?;
        for _ in 0..(-dec_pos) {
            w.write_all(b"0")?;
        }
        w.write_all(&digits)
    } else if (dec_pos as usize) < digits.len() {
        let split = dec_pos as usize;
        w.write_all(&digits[..split])?;
        w.write_all(b".")?;
        w.write_all(&digits[split..])
    } else {
        w.write_all(&digits)?;
        for _ in 0..(dec_pos as usize - digits.len()) {
            w.write_all(b"0")?;
        }
        Ok(())
    }
}

/// A `serde_json` formatter that matches Go's `encoding/json` string escaping and float formatting.
pub struct GoFormatter<F>(pub F);

macro_rules! delegate_fmt {
    ($($name:ident($($arg:ident: $ty:ty),*);)*) => {
        $(
            #[inline]
            fn $name<W: ?Sized + io::Write>(&mut self, w: &mut W $(, $arg: $ty)*) -> io::Result<()> {
                self.0.$name(w $(, $arg)*)
            }
        )*
    };
}

impl<F: serde_json::ser::Formatter> serde_json::ser::Formatter for GoFormatter<F> {
    delegate_fmt! {
        begin_array();
        end_array();
        begin_array_value(first: bool);
        end_array_value();
        begin_object();
        end_object();
        begin_object_key(first: bool);
        end_object_key();
        begin_object_value();
        end_object_value();
    }

    fn write_string_fragment<W: ?Sized + io::Write>(
        &mut self,
        w: &mut W,
        fragment: &str,
    ) -> io::Result<()> {
        let mut start = 0;
        for (i, c) in fragment.char_indices() {
            let esc = match c {
                '<' => "\\u003c",
                '>' => "\\u003e",
                '&' => "\\u0026",
                '\u{2028}' => "\\u2028",
                '\u{2029}' => "\\u2029",
                _ => continue,
            };
            w.write_all(fragment[start..i].as_bytes())?;
            w.write_all(esc.as_bytes())?;
            start = i + c.len_utf8();
        }
        w.write_all(fragment[start..].as_bytes())
    }

    fn write_f32<W: ?Sized + io::Write>(&mut self, w: &mut W, value: f32) -> io::Result<()> {
        if !value.is_finite() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "json: unsupported value",
            ));
        }
        let abs = value.abs();
        let sci_abs = format!("{abs:e}");
        let use_fixed = (1e-6_f32..1e21_f32).contains(&abs);
        format_go_float(
            w,
            value.is_sign_negative(),
            value == 0.0,
            &sci_abs,
            use_fixed,
        )
    }

    fn write_f64<W: ?Sized + io::Write>(&mut self, w: &mut W, value: f64) -> io::Result<()> {
        if !value.is_finite() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "json: unsupported value",
            ));
        }
        let abs = value.abs();
        let sci_abs = format!("{abs:e}");
        let use_fixed = (1e-6_f64..1e21_f64).contains(&abs);
        format_go_float(
            w,
            value.is_sign_negative(),
            value == 0.0,
            &sci_abs,
            use_fixed,
        )
    }
}

/// Formatter implementing Go's `json.MarshalIndent(v, prefix, indent)`.
pub struct IndentFormatter<'a> {
    prefix: &'a [u8],
    indent: &'a [u8],
    depth: usize,
    has_value: bool,
}

impl<'a> IndentFormatter<'a> {
    /// Creates an `IndentFormatter` with the given line prefix and per-level indent.
    pub fn new(prefix: &'a str, indent: &'a str) -> Self {
        Self {
            prefix: prefix.as_bytes(),
            indent: indent.as_bytes(),
            depth: 0,
            has_value: false,
        }
    }

    fn write_newline_indent<W: ?Sized + io::Write>(&self, w: &mut W) -> io::Result<()> {
        w.write_all(b"\n")?;
        w.write_all(self.prefix)?;
        for _ in 0..self.depth {
            w.write_all(self.indent)?;
        }
        Ok(())
    }
}

impl serde_json::ser::Formatter for IndentFormatter<'_> {
    #[inline]
    fn begin_array<W: ?Sized + io::Write>(&mut self, w: &mut W) -> io::Result<()> {
        self.depth += 1;
        self.has_value = false;
        w.write_all(b"[")
    }

    #[inline]
    fn end_array<W: ?Sized + io::Write>(&mut self, w: &mut W) -> io::Result<()> {
        self.depth -= 1;
        if self.has_value {
            self.write_newline_indent(w)?;
        }
        w.write_all(b"]")
    }

    #[inline]
    fn begin_array_value<W: ?Sized + io::Write>(
        &mut self,
        w: &mut W,
        first: bool,
    ) -> io::Result<()> {
        if !first {
            w.write_all(b",")?;
        }
        self.write_newline_indent(w)
    }

    #[inline]
    fn end_array_value<W: ?Sized + io::Write>(&mut self, _w: &mut W) -> io::Result<()> {
        self.has_value = true;
        Ok(())
    }

    #[inline]
    fn begin_object<W: ?Sized + io::Write>(&mut self, w: &mut W) -> io::Result<()> {
        self.depth += 1;
        self.has_value = false;
        w.write_all(b"{")
    }

    #[inline]
    fn end_object<W: ?Sized + io::Write>(&mut self, w: &mut W) -> io::Result<()> {
        self.depth -= 1;
        if self.has_value {
            self.write_newline_indent(w)?;
        }
        w.write_all(b"}")
    }

    #[inline]
    fn begin_object_key<W: ?Sized + io::Write>(
        &mut self,
        w: &mut W,
        first: bool,
    ) -> io::Result<()> {
        if !first {
            w.write_all(b",")?;
        }
        self.write_newline_indent(w)
    }

    #[inline]
    fn begin_object_value<W: ?Sized + io::Write>(&mut self, w: &mut W) -> io::Result<()> {
        w.write_all(b": ")
    }

    #[inline]
    fn end_object_value<W: ?Sized + io::Write>(&mut self, _w: &mut W) -> io::Result<()> {
        self.has_value = true;
        Ok(())
    }
}

/// `json.Marshal(v)` returning UTF-8 bytes.
pub fn marshal<T: Serialize>(v: &T) -> Vec<u8> {
    let mut out = Vec::new();
    let mut ser = serde_json::Serializer::with_formatter(
        &mut out,
        GoFormatter(serde_json::ser::CompactFormatter),
    );
    v.serialize(&mut ser)
        .expect("serializing to memory cannot fail");
    out
}

/// `json.Marshal(v)` returning a `String`.
pub fn marshal_string<T: Serialize>(v: &T) -> String {
    String::from_utf8(marshal(v)).expect("Go JSON output is valid UTF-8")
}

/// `json.MarshalIndent(v, "", "  ")` returning UTF-8 bytes.
pub fn marshal_indent<T: Serialize>(v: &T) -> Vec<u8> {
    marshal_indent_with(v, "", "  ")
}

/// `json.MarshalIndent(v, "", "  ")` returning a `String`.
pub fn marshal_indent_string<T: Serialize>(v: &T) -> String {
    String::from_utf8(marshal_indent(v)).expect("Go JSON output is valid UTF-8")
}

/// `json.MarshalIndent(v, prefix, indent)` returning UTF-8 bytes.
pub fn marshal_indent_with<T: Serialize>(v: &T, prefix: &str, indent: &str) -> Vec<u8> {
    let mut out = Vec::new();
    let mut ser = serde_json::Serializer::with_formatter(
        &mut out,
        GoFormatter(IndentFormatter::new(prefix, indent)),
    );
    v.serialize(&mut ser)
        .expect("serializing to memory cannot fail");
    out
}

/// `json.MarshalIndent(v, prefix, indent)` returning a `String`.
pub fn marshal_indent_with_string<T: Serialize>(v: &T, prefix: &str, indent: &str) -> String {
    String::from_utf8(marshal_indent_with(v, prefix, indent))
        .expect("Go JSON output is valid UTF-8")
}

/// Marshals arbitrary bytes as a Go JSON string (`json.Marshal(string(bytes))`),
/// escaping each invalid UTF-8 byte as `\ufffd` while keeping valid `U+FFFD` literal.
pub fn marshal_raw_string(bytes: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(bytes.len() + 2);
    out.push(b'"');
    let mut i = 0;
    while i < bytes.len() {
        let (decoded, width) = gostd::decode_rune(&bytes[i..]);
        i += width;
        let Some(c) = decoded else {
            out.extend_from_slice(b"\\ufffd");
            continue;
        };
        match c {
            '"' => out.extend_from_slice(b"\\\""),
            '\\' => out.extend_from_slice(b"\\\\"),
            '\x08' => out.extend_from_slice(b"\\b"),
            '\x0c' => out.extend_from_slice(b"\\f"),
            '\n' => out.extend_from_slice(b"\\n"),
            '\r' => out.extend_from_slice(b"\\r"),
            '\t' => out.extend_from_slice(b"\\t"),
            c if (c as u32) < 0x20 => {
                use io::Write;
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            '<' => out.extend_from_slice(b"\\u003c"),
            '>' => out.extend_from_slice(b"\\u003e"),
            '&' => out.extend_from_slice(b"\\u0026"),
            '\u{2028}' => out.extend_from_slice(b"\\u2028"),
            '\u{2029}' => out.extend_from_slice(b"\\u2029"),
            c => {
                let mut buf = [0u8; 4];
                out.extend_from_slice(c.encode_utf8(&mut buf).as_bytes());
            }
        }
    }
    out.push(b'"');
    out
}

/// Go's `string(b)` conversion: invalid UTF-8 bytes become `U+FFFD` one byte at a time.
pub fn go_string(b: &[u8]) -> String {
    let mut out = String::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        let (c, n) = gostd::decode_rune(&b[i..]);
        out.push(c.unwrap_or('\u{fffd}'));
        i += n;
    }
    out
}

// ---------------------------------------------------------------------------
// Go's scanner
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, PartialEq)]
enum St {
    BeginValue,
    BeginValueOrEmpty,
    BeginStringOrEmpty,
    BeginString,
    EndValue,
    EndTop,
    InString,
    InStringEsc,
    EscU(u8),
    Neg,
    One,
    Zero,
    Dot,
    Dot0,
    E,
    ESign,
    E0,
    Lit(&'static [u8], usize, &'static str),
}

#[derive(Clone, Copy, PartialEq)]
enum Ps {
    ObjectKey,
    ObjectValue,
    ArrayValue,
}

/// Go's `quoteChar`: formats a byte as `strconv.QuoteRune(rune(c))`.
pub fn quote_char(c: u8) -> String {
    match c {
        b'\'' => "'\\''".to_string(),
        b'"' => "'\"'".to_string(),
        b'\\' => "'\\\\'".to_string(),
        0x07 => "'\\a'".to_string(),
        0x08 => "'\\b'".to_string(),
        b'\t' => "'\\t'".to_string(),
        b'\n' => "'\\n'".to_string(),
        0x0b => "'\\v'".to_string(),
        0x0c => "'\\f'".to_string(),
        b'\r' => "'\\r'".to_string(),
        _ if c < 0x20 || c == 0x7f => format!("'\\x{:02x}'", c),
        _ if c < 0x7f => format!("'{}'", c as char),
        _ if c <= 0xa0 || c == 0xad => format!("'\\u{:04x}'", c),
        _ => format!("'{}'", char::from(c)),
    }
}

fn is_space(c: u8) -> bool {
    matches!(c, b' ' | b'\t' | b'\r' | b'\n')
}

struct Scanner {
    step: St,
    parse: Vec<Ps>,
    end_top: bool,
    err: Option<String>,
}

impl Scanner {
    fn new() -> Self {
        Self {
            step: St::BeginValue,
            parse: Vec::new(),
            end_top: false,
            err: None,
        }
    }

    fn error(&mut self, c: u8, ctx: &str) {
        self.err = Some(format!("invalid character {} {}", quote_char(c), ctx));
    }

    fn push(&mut self, c: u8, next: St, p: Ps) {
        self.step = next;
        self.parse.push(p);
        if self.parse.len() > MAX_DEPTH {
            self.error(c, "exceeded max depth");
        }
    }

    fn pop(&mut self) {
        self.parse.pop();
        if self.parse.is_empty() {
            self.step = St::EndTop;
            self.end_top = true;
        } else {
            self.step = St::EndValue;
        }
    }

    fn begin_value(&mut self, c: u8) {
        if is_space(c) {
            return;
        }
        match c {
            b'{' => self.push(c, St::BeginStringOrEmpty, Ps::ObjectKey),
            b'[' => self.push(c, St::BeginValueOrEmpty, Ps::ArrayValue),
            b'"' => self.step = St::InString,
            b'-' => self.step = St::Neg,
            b'0' => self.step = St::Zero,
            b't' => self.step = St::Lit(b"rue", 0, "true"),
            b'f' => self.step = St::Lit(b"alse", 0, "false"),
            b'n' => self.step = St::Lit(b"ull", 0, "null"),
            b'1'..=b'9' => self.step = St::One,
            _ => self.error(c, "looking for beginning of value"),
        }
    }

    fn end_value(&mut self, c: u8) {
        let Some(&ps) = self.parse.last() else {
            self.step = St::EndTop;
            self.end_top = true;
            return self.end_top_step(c);
        };
        if is_space(c) {
            self.step = St::EndValue;
            return;
        }
        match ps {
            Ps::ObjectKey => {
                if c == b':' {
                    *self.parse.last_mut().unwrap() = Ps::ObjectValue;
                    self.step = St::BeginValue;
                } else {
                    self.error(c, "after object key");
                }
            }
            Ps::ObjectValue => {
                if c == b',' {
                    *self.parse.last_mut().unwrap() = Ps::ObjectKey;
                    self.step = St::BeginString;
                } else if c == b'}' {
                    self.pop();
                } else {
                    self.error(c, "after object key:value pair");
                }
            }
            Ps::ArrayValue => {
                if c == b',' {
                    self.step = St::BeginValue;
                } else if c == b']' {
                    self.pop();
                } else {
                    self.error(c, "after array element");
                }
            }
        }
    }

    fn end_top_step(&mut self, c: u8) {
        if !is_space(c) {
            self.error(c, "after top-level value");
        }
    }

    fn begin_string(&mut self, c: u8) {
        if is_space(c) {
            return;
        }
        if c == b'"' {
            self.step = St::InString;
        } else {
            self.error(c, "looking for beginning of object key string");
        }
    }

    fn zero(&mut self, c: u8) {
        if c == b'.' {
            self.step = St::Dot;
        } else if c == b'e' || c == b'E' {
            self.step = St::E;
        } else {
            self.end_value(c);
        }
    }

    fn e_sign(&mut self, c: u8) {
        if c.is_ascii_digit() {
            self.step = St::E0;
        } else {
            self.error(c, "in exponent of numeric literal");
        }
    }

    fn feed(&mut self, c: u8) {
        match self.step {
            St::BeginValue => self.begin_value(c),
            St::BeginValueOrEmpty => {
                if is_space(c) {
                } else if c == b']' {
                    self.end_value(c);
                } else {
                    self.begin_value(c);
                }
            }
            St::BeginStringOrEmpty => {
                if is_space(c) {
                } else if c == b'}' {
                    *self.parse.last_mut().unwrap() = Ps::ObjectValue;
                    self.end_value(c);
                } else {
                    self.begin_string(c);
                }
            }
            St::BeginString => self.begin_string(c),
            St::EndValue => self.end_value(c),
            St::EndTop => self.end_top_step(c),
            St::InString => {
                if c == b'"' {
                    self.step = St::EndValue;
                } else if c == b'\\' {
                    self.step = St::InStringEsc;
                } else if c < 0x20 {
                    self.error(c, "in string literal");
                }
            }
            St::InStringEsc => match c {
                b'b' | b'f' | b'n' | b'r' | b't' | b'\\' | b'/' | b'"' => self.step = St::InString,
                b'u' => self.step = St::EscU(0),
                _ => self.error(c, "in string escape code"),
            },
            St::EscU(n) => {
                if c.is_ascii_hexdigit() {
                    self.step = if n == 3 {
                        St::InString
                    } else {
                        St::EscU(n + 1)
                    };
                } else {
                    self.error(c, "in \\u hexadecimal character escape");
                }
            }
            St::Neg => match c {
                b'0' => self.step = St::Zero,
                b'1'..=b'9' => self.step = St::One,
                _ => self.error(c, "in numeric literal"),
            },
            St::One => {
                if !c.is_ascii_digit() {
                    self.zero(c);
                }
            }
            St::Zero => self.zero(c),
            St::Dot => {
                if c.is_ascii_digit() {
                    self.step = St::Dot0;
                } else {
                    self.error(c, "after decimal point in numeric literal");
                }
            }
            St::Dot0 => {
                if c.is_ascii_digit() {
                } else if c == b'e' || c == b'E' {
                    self.step = St::E;
                } else {
                    self.end_value(c);
                }
            }
            St::E => {
                if c == b'+' || c == b'-' {
                    self.step = St::ESign;
                } else {
                    self.e_sign(c);
                }
            }
            St::ESign => self.e_sign(c),
            St::E0 => {
                if !c.is_ascii_digit() {
                    self.end_value(c);
                }
            }
            St::Lit(rest, i, word) => {
                if c == rest[i] {
                    self.step = if i + 1 == rest.len() {
                        St::EndValue
                    } else {
                        St::Lit(rest, i + 1, word)
                    };
                } else {
                    let ctx = format!("in literal {} (expecting {})", word, quote_char(rest[i]));
                    self.error(c, &ctx);
                }
            }
        }
    }
}

/// Go's `checkValid`: validates JSON syntax and returns Go's exact error wording.
pub fn check_valid(data: &[u8]) -> Result<(), String> {
    let mut s = Scanner::new();
    for &c in data {
        s.feed(c);
        if let Some(e) = s.err.take() {
            return Err(e);
        }
    }
    if s.end_top {
        return Ok(());
    }
    s.feed(b' ');
    if let Some(e) = s.err.take() {
        return Err(e);
    }
    if s.end_top {
        return Ok(());
    }
    Err("unexpected end of JSON input".to_string())
}

/// Length of the first JSON value in `data`, matching `json.Decoder.readValue`.
///
/// A scalar terminates at the first byte that cannot continue it; an object or
/// array terminates at its closing bracket. Returns `"unexpected EOF"` when
/// input ends before a top-level value finishes.
pub fn value_len(data: &[u8]) -> Result<usize, String> {
    let mut s = Scanner::new();
    for (i, &c) in data.iter().enumerate() {
        let depth_before = s.parse.len();
        s.feed(c);
        if s.end_top {
            return Ok(if depth_before > 0 { i + 1 } else { i });
        }
        if let Some(e) = s.err.take() {
            return Err(e);
        }
    }
    s.feed(b' ');
    if s.end_top {
        return Ok(data.len());
    }
    Err("unexpected EOF".to_string())
}

// ---------------------------------------------------------------------------
// iterative AST parser (preserves number literals, duplicate keys, UTF-8)
// ---------------------------------------------------------------------------

/// A parsed JSON value preserving literal number text and document key order.
#[derive(Debug, Clone, PartialEq)]
pub enum GoValue {
    Null,
    Bool(bool),
    Num(String),
    Str(String),
    Arr(Vec<GoValue>),
    Obj(Vec<(String, GoValue)>),
}

/// Backwards-compatible alias for [`GoValue`].
pub type Val = GoValue;

impl GoValue {
    /// The word Go's `UnmarshalTypeError` prints for this JSON value kind.
    pub fn kind(&self) -> &'static str {
        match self {
            GoValue::Null => "null",
            GoValue::Bool(_) => "bool",
            GoValue::Num(_) => "number",
            GoValue::Str(_) => "string",
            GoValue::Arr(_) => "array",
            GoValue::Obj(_) => "object",
        }
    }
}

/// Validates `data` with [`check_valid`] and iteratively constructs a [`GoValue`].
pub fn parse(data: &[u8]) -> Result<GoValue, String> {
    check_valid(data)?;
    Ok(Builder { d: data, i: 0 }.build())
}

struct Builder<'a> {
    d: &'a [u8],
    i: usize,
}

enum Frame {
    Arr(Vec<GoValue>),
    Obj(Vec<(String, GoValue)>, Option<String>),
}

impl Builder<'_> {
    fn ws(&mut self) {
        while self.i < self.d.len() && is_space(self.d[self.i]) {
            self.i += 1;
        }
    }

    fn hex4(&mut self) -> u32 {
        let h = std::str::from_utf8(&self.d[self.i..self.i + 4]).unwrap();
        self.i += 4;
        u32::from_str_radix(h, 16).unwrap()
    }

    /// Go's `unquote`: lone surrogates and invalid UTF-8 bytes become `U+FFFD`.
    fn string(&mut self) -> String {
        self.i += 1; // opening quote
        let mut out = String::new();
        loop {
            let c = self.d[self.i];
            match c {
                b'"' => {
                    self.i += 1;
                    return out;
                }
                b'\\' => {
                    self.i += 1;
                    let e = self.d[self.i];
                    self.i += 1;
                    match e {
                        b'b' => out.push('\x08'),
                        b'f' => out.push('\x0c'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => {
                            let r = self.hex4();
                            if (0xd800..0xe000).contains(&r) {
                                if r < 0xdc00 && self.d[self.i..].starts_with(b"\\u") {
                                    let save = self.i;
                                    self.i += 2;
                                    let r2 = self.hex4();
                                    if (0xdc00..0xe000).contains(&r2) {
                                        let cp = 0x10000 + ((r - 0xd800) << 10) + (r2 - 0xdc00);
                                        out.push(char::from_u32(cp).unwrap());
                                        continue;
                                    }
                                    self.i = save;
                                }
                                out.push('\u{fffd}');
                            } else {
                                out.push(char::from_u32(r).unwrap());
                            }
                        }
                        other => out.push(other as char),
                    }
                }
                _ => {
                    let (r, n) = gostd::decode_rune(&self.d[self.i..]);
                    out.push(r.unwrap_or('\u{fffd}'));
                    self.i += n;
                }
            }
        }
    }

    fn build(&mut self) -> GoValue {
        let mut stack: Vec<Frame> = Vec::new();
        loop {
            self.ws();
            if let Some(frame) = stack.last_mut() {
                match frame {
                    Frame::Arr(_) => {
                        if self.d[self.i] == b']' {
                            self.i += 1;
                            let Frame::Arr(items) = stack.pop().unwrap() else {
                                unreachable!();
                            };
                            let val = GoValue::Arr(items);
                            if let Some(parent) = stack.last_mut() {
                                Self::attach(parent, val);
                                continue;
                            }
                            return val;
                        }
                        if self.d[self.i] == b',' {
                            self.i += 1;
                            self.ws();
                        }
                    }
                    Frame::Obj(_, pending_key) => {
                        if pending_key.is_none() {
                            if self.d[self.i] == b'}' {
                                self.i += 1;
                                let Frame::Obj(entries, _) = stack.pop().unwrap() else {
                                    unreachable!();
                                };
                                let val = GoValue::Obj(entries);
                                if let Some(parent) = stack.last_mut() {
                                    Self::attach(parent, val);
                                    continue;
                                }
                                return val;
                            }
                            if self.d[self.i] == b',' {
                                self.i += 1;
                                self.ws();
                            }
                            let key = self.string();
                            self.ws();
                            self.i += 1; // ':'
                            self.ws();
                            *pending_key = Some(key);
                        }
                    }
                }
            }

            let leaf = match self.d[self.i] {
                b'{' => {
                    self.i += 1;
                    stack.push(Frame::Obj(Vec::new(), None));
                    continue;
                }
                b'[' => {
                    self.i += 1;
                    stack.push(Frame::Arr(Vec::new()));
                    continue;
                }
                b'"' => GoValue::Str(self.string()),
                b't' => {
                    self.i += 4;
                    GoValue::Bool(true)
                }
                b'f' => {
                    self.i += 5;
                    GoValue::Bool(false)
                }
                b'n' => {
                    self.i += 4;
                    GoValue::Null
                }
                _ => {
                    let start = self.i;
                    while self.i < self.d.len()
                        && matches!(
                            self.d[self.i],
                            b'-' | b'+' | b'.' | b'e' | b'E' | b'0'..=b'9'
                        )
                    {
                        self.i += 1;
                    }
                    GoValue::Num(String::from_utf8_lossy(&self.d[start..self.i]).into_owned())
                }
            };

            if let Some(parent) = stack.last_mut() {
                Self::attach(parent, leaf);
            } else {
                return leaf;
            }
        }
    }

    fn attach(frame: &mut Frame, val: GoValue) {
        match frame {
            Frame::Arr(items) => items.push(val),
            Frame::Obj(entries, pending_key) => {
                let key = pending_key.take().expect("object key precedes value");
                entries.push((key, val));
            }
        }
    }
}

// ---------------------------------------------------------------------------
// typed decoding: Go's field matching, slice reuse, and UnmarshalTypeError
// ---------------------------------------------------------------------------

/// Canonicalizes a rune by Go's `unicode.SimpleFold` equivalence class.
pub fn fold_rune(c: char) -> char {
    match c {
        '\u{0131}' => '\u{0131}',
        '\u{212A}' => 'K',
        '\u{212B}' => '\u{00C5}',
        '\u{2126}' => '\u{03A9}',
        '\u{03F4}' => '\u{0398}',
        '\u{1E9E}' => '\u{00DF}',
        _ => unicode::to_upper(c),
    }
}

/// Case-insensitive comparison matching Go's `encoding/json` `equalFold`.
pub fn fold_eq(a: &str, b: &str) -> bool {
    a.chars().map(fold_rune).eq(b.chars().map(fold_rune))
}

/// `strconv.ParseInt(s, 10, 64)` (`-0` parses as `0`).
pub fn parse_int(s: &str) -> Option<i64> {
    let (neg, digits) = match s.as_bytes().first() {
        Some(b'-') => (true, &s[1..]),
        Some(b'+') => (false, &s[1..]),
        _ => (false, s),
    };
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let mag: u64 = digits.parse().ok()?;
    if neg {
        if mag > (i64::MAX as u64) + 1 {
            None
        } else {
            Some((mag as i128).wrapping_neg() as i64)
        }
    } else if mag > i64::MAX as u64 {
        None
    } else {
        Some(mag as i64)
    }
}

/// A Go slice (`[]T`) preserving spare backing-array capacity across duplicate-key re-decodes.
#[derive(Debug, Clone)]
pub struct GoSlice<T> {
    backing: Vec<T>,
    len: usize,
    non_nil: bool,
}

impl<T> Default for GoSlice<T> {
    fn default() -> Self {
        Self {
            backing: Vec::new(),
            len: 0,
            non_nil: false,
        }
    }
}

impl<T: Clone> GoSlice<T> {
    /// Returns `None` for a Go `nil` slice or `Some(elements)` for a non-nil slice.
    pub fn get(&self) -> Option<Vec<T>> {
        if self.non_nil {
            Some(self.backing[..self.len].to_vec())
        } else {
            None
        }
    }

    /// Consumes the slice into `Option<Vec<T>>`.
    pub fn into_option(mut self) -> Option<Vec<T>> {
        if self.non_nil {
            self.backing.truncate(self.len);
            Some(self.backing)
        } else {
            None
        }
    }
}

impl<T> GoSlice<T> {
    /// Whether the slice is non-nil (distinct from `nil`, even when empty).
    pub fn is_non_nil(&self) -> bool {
        self.non_nil
    }
}

/// Go's `decodeState`: tracks struct field context and retains the first type error.
#[derive(Default)]
pub struct Dec {
    err: Option<String>,
    struct_name: Option<&'static str>,
    fields: Vec<&'static str>,
}

impl Dec {
    /// Creates an empty decoder state.
    pub fn new() -> Dec {
        Dec::default()
    }

    /// Returns the first type error recorded, or `Ok(())`.
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

    /// Decodes a `string` field (`null` leaves `dst` unchanged).
    pub fn string(&mut self, v: &GoValue, dst: &mut String) {
        match v {
            GoValue::Str(s) => *dst = s.clone(),
            GoValue::Null => {}
            other => self.type_err(other.kind(), "string"),
        }
    }

    /// Decodes an `int` / `int64` field (`null` leaves `dst` unchanged).
    pub fn int(&mut self, v: &GoValue, dst: &mut i64) {
        match v {
            GoValue::Num(t) => match parse_int(t) {
                Some(n) => *dst = n,
                None => self.type_err(&format!("number {t}"), "int"),
            },
            GoValue::Null => {}
            other => self.type_err(other.kind(), "int"),
        }
    }

    /// Decodes a `bool` field (`null` leaves `dst` unchanged).
    pub fn bool(&mut self, v: &GoValue, dst: &mut bool) {
        match v {
            GoValue::Bool(b) => *dst = *b,
            GoValue::Null => {}
            other => self.type_err(other.kind(), "bool"),
        }
    }

    /// Decodes a `[]string` field into a `GoSlice<String>` with full Go capacity reuse.
    pub fn go_strings(&mut self, v: &GoValue, dst: &mut GoSlice<String>) {
        self.go_slice(v, "[]string", dst, |d, item, slot| d.string(item, slot));
    }

    /// Decodes a `[]T` field into a `GoSlice<T>`, preserving spare backing-array capacity
    /// across duplicate keys and resetting to an empty non-nil slice when the array is empty.
    pub fn go_slice<T: Clone + Default>(
        &mut self,
        v: &GoValue,
        ty: &str,
        dst: &mut GoSlice<T>,
        mut each: impl FnMut(&mut Dec, &GoValue, &mut T),
    ) {
        match v {
            GoValue::Arr(items) => {
                if items.is_empty() {
                    *dst = GoSlice {
                        backing: Vec::new(),
                        len: 0,
                        non_nil: true,
                    };
                    return;
                }
                let mut sl = std::mem::take(dst);
                for (i, item) in items.iter().enumerate() {
                    let cap = sl.backing.len();
                    if i >= cap {
                        let newcap = (cap + cap / 2).max(4);
                        let mut nb: Vec<T> = sl.backing[..sl.len].to_vec();
                        nb.resize_with(newcap, T::default);
                        sl.backing = nb;
                        sl.non_nil = true;
                    }
                    if i >= sl.len {
                        sl.len = i + 1;
                    }
                    each(self, item, &mut sl.backing[i]);
                }
                if items.len() < sl.len {
                    sl.len = items.len();
                }
                *dst = sl;
            }
            GoValue::Null => *dst = GoSlice::default(),
            other => self.type_err(other.kind(), ty),
        }
    }

    /// Decodes a `[]string` field into `Option<Vec<String>>` (`None` is Go's `nil` slice),
    /// reusing existing elements on duplicate keys when `null` elements appear.
    pub fn strings(&mut self, v: &GoValue, dst: &mut Option<Vec<String>>) {
        self.slice(v, "[]string", dst, |d, it, slot| d.string(it, slot));
    }

    /// Decodes a `[]T` field into `Option<Vec<T>>`, matching Go's slice-reuse rules for
    /// duplicate keys and `null` elements.
    pub fn slice<T: Default>(
        &mut self,
        v: &GoValue,
        ty: &str,
        dst: &mut Option<Vec<T>>,
        mut each: impl FnMut(&mut Dec, &GoValue, &mut T),
    ) {
        match v {
            GoValue::Arr(items) => {
                let mut out = dst.take().unwrap_or_default();
                if items.is_empty() {
                    out.clear();
                    *dst = Some(out);
                    return;
                }
                if items.len() > out.len() {
                    out.resize_with(items.len(), T::default);
                } else {
                    out.truncate(items.len());
                }
                for (slot, it) in out.iter_mut().zip(items.iter()) {
                    each(self, it, slot);
                }
                *dst = Some(out);
            }
            GoValue::Null => *dst = None,
            other => self.type_err(other.kind(), ty),
        }
    }

    /// Decodes a `map[string][]string` field (Go allocates a fresh zero slice per map entry).
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

    /// Decodes a struct named `struct_name` (Go type `ty`) with JSON field `names`.
    ///
    /// Matches exact names before case-folded names (`unicode.SimpleFold`), preserves
    /// input key order so the last duplicate key wins, and tracks nested field paths
    /// for Go's `json: cannot unmarshal ... into Go struct field ...` errors.
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

/// Decodes a JSON object into key/value pairs matching Go's `json.Unmarshal(raw, &map[string]string)`.
pub fn decode_string_map(raw: &[u8]) -> Option<Vec<(String, String)>> {
    match parse(raw).ok()? {
        GoValue::Null => Some(Vec::new()),
        GoValue::Obj(entries) => {
            let mut out = Vec::with_capacity(entries.len());
            for (k, v) in entries {
                match v {
                    GoValue::Str(s) => out.push((k, s)),
                    GoValue::Null => out.push((k, String::new())),
                    _ => return None,
                }
            }
            Some(out)
        }
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn decode_hex(s: &str) -> Vec<u8> {
        assert_eq!(s.len() % 2, 0, "odd hex length: {s}");
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    }

    fn fixture_path() -> PathBuf {
        for cand in [
            "packages/gocompat/gojson/testdata/goparity/fixture.txt",
            "testdata/goparity/fixture.txt",
        ] {
            let p = PathBuf::from(cand);
            if p.is_file() {
                return p;
            }
        }
        if let Ok(sd) = std::env::var("TEST_SRCDIR") {
            let p = PathBuf::from(sd)
                .join("_main/packages/gocompat/gojson/testdata/goparity/fixture.txt");
            if p.is_file() {
                return p;
            }
        }
        panic!("could not locate goparity fixture.txt");
    }

    fn build_map_case(kind: &str) -> Vec<u8> {
        match kind {
            "empty_map" => marshal(&BTreeMap::<String, i64>::new()),
            "empty_slice" => marshal(&Vec::<i64>::new()),
            "ascii_keys" => {
                let mut m = BTreeMap::new();
                m.insert("b".to_string(), 1);
                m.insert("A".to_string(), 2);
                m.insert("_".to_string(), 3);
                m.insert("".to_string(), 4);
                m.insert("a".to_string(), 5);
                marshal(&m)
            }
            "html_keys" => {
                let mut m = BTreeMap::new();
                m.insert(">".to_string(), "<");
                m.insert("&".to_string(), "\u{2028}");
                m.insert("<".to_string(), ">");
                marshal(&m)
            }
            "utf8_keys" => {
                let mut m = BTreeMap::new();
                m.insert("\u{1f600}".to_string(), 1);
                m.insert("é".to_string(), 2);
                m.insert("e".to_string(), 3);
                m.insert("\u{2028}".to_string(), 4);
                marshal(&m)
            }
            "nested_containers" => {
                #[derive(Serialize)]
                struct Nested {
                    a: BTreeMap<String, i64>,
                    b: Vec<i64>,
                    c: Vec<BTreeMap<String, i64>>,
                    d: BTreeMap<String, i64>,
                }
                let mut d = BTreeMap::new();
                d.insert("z".to_string(), 1);
                d.insert("a".to_string(), 2);
                let n = Nested {
                    a: BTreeMap::new(),
                    b: Vec::new(),
                    c: vec![BTreeMap::new()],
                    d,
                };
                marshal(&n)
            }
            other => panic!("unknown map case: {other}"),
        }
    }

    fn build_indent_case(kind: &str, prefix: &str, indent: &str) -> Vec<u8> {
        match kind {
            "empty_map" => marshal_indent_with(&BTreeMap::<String, i64>::new(), prefix, indent),
            "empty_slice" => marshal_indent_with(&Vec::<i64>::new(), prefix, indent),
            "nested_empty" | "nested_empty_prefix" => {
                #[derive(Serialize)]
                struct S {
                    a: BTreeMap<String, i64>,
                    b: Vec<i64>,
                    c: Vec<i64>,
                }
                let s = S {
                    a: BTreeMap::new(),
                    b: Vec::new(),
                    c: vec![1, 2],
                };
                marshal_indent_with(&s, prefix, indent)
            }
            "nested_mixed_html_float" | "nested_tab_indent" => {
                #[derive(Serialize)]
                struct S {
                    html: String,
                    num: f64,
                    empty_arr: Vec<Vec<i64>>,
                }
                let s = S {
                    html: "<a&b>\u{2028}".to_string(),
                    num: 1.0,
                    empty_arr: vec![vec![]],
                };
                marshal_indent_with(&s, prefix, indent)
            }
            other => panic!("unknown indent case: {other}"),
        }
    }

    fn run_unm_struct_case(name: &str, raw: &[u8]) -> String {
        if name.starts_with("int_") {
            let v = parse(raw).unwrap();
            let mut n = 0i64;
            let mut d = Dec::new();
            d.object(&v, "S", "main.S", &["N"], |d, _, x| d.int(x, &mut n));
            return match d.finish() {
                Ok(()) => format!("OK:{n}"),
                Err(e) => format!("ERR:{e}"),
            };
        }
        if name.starts_with("fold_") {
            let v = parse(raw).unwrap();
            let (mut k, mut ss, mut e, mut s, mut ii) = (
                String::new(),
                String::new(),
                String::new(),
                String::new(),
                String::new(),
            );
            let mut d = Dec::new();
            d.object(
                &v,
                "FoldS",
                "main.FoldS",
                &["k", "ss", "é", "s", "I"],
                |d, f, x| match f {
                    "k" => d.string(x, &mut k),
                    "ss" => d.string(x, &mut ss),
                    "é" => d.string(x, &mut e),
                    "s" => d.string(x, &mut s),
                    _ => d.string(x, &mut ii),
                },
            );
            d.finish().unwrap();
            return format!("k={k}|ss={ss}|e={e}|s={s}|i={ii}");
        }
        if name == "exact_vs_fold" {
            let v = parse(raw).unwrap();
            let (mut upper, mut lower) = (String::new(), String::new());
            let mut d = Dec::new();
            d.object(&v, "Exact", "main.Exact", &["A", "a"], |d, f, x| match f {
                "A" => d.string(x, &mut upper),
                _ => d.string(x, &mut lower),
            });
            d.finish().unwrap();
            return format!("A={upper}|a={lower}");
        }
        if name.starts_with("slice_") {
            let v = parse(raw).unwrap();
            let mut envs = GoSlice::<String>::default();
            let mut d = Dec::new();
            d.object(&v, "SlS", "main.SlS", &["environments"], |d, _, x| {
                d.go_strings(x, &mut envs);
            });
            d.finish().unwrap();
            return match envs.get() {
                None => "NIL".to_string(),
                Some(items) => format!("LEN={}:{}", items.len(), items.join(",")),
            };
        }
        if name == "nest_struct" {
            let v = parse(raw).unwrap();
            let mut inner_name = String::new();
            let mut d = Dec::new();
            d.object(&v, "Outer", "main.Outer", &["in"], |d, _, x| {
                d.object(x, "Inner", "main.Inner", &["name"], |d, _, y| {
                    d.string(y, &mut inner_name);
                });
            });
            return format!("ERR:{}", d.finish().unwrap_err());
        }
        if name == "nest_slice" {
            #[derive(Default)]
            struct Inner {
                name: String,
            }
            let v = parse(raw).unwrap();
            let mut arr: Option<Vec<Inner>> = None;
            let mut d = Dec::new();
            d.object(&v, "Outer", "main.Outer", &["matrix"], |d, _, x| {
                d.slice(x, "[]main.Inner", &mut arr, |d, item, out| {
                    d.object(item, "Inner", "main.Inner", &["name"], |d, _, y| {
                        d.string(y, &mut out.name);
                    });
                });
            });
            return format!("ERR:{}", d.finish().unwrap_err());
        }
        if name == "map_slice_dup" {
            let v = parse(raw).unwrap();
            let mut m: Option<BTreeMap<String, Vec<String>>> = None;
            let mut d = Dec::new();
            d.object(&v, "C", "main.C", &["m"], |d, _, x| {
                d.strings_map(x, &mut m);
            });
            d.finish().unwrap();
            let k = m.unwrap().remove("k").unwrap();
            return format!("LEN={}:{}", k.len(), k.join(","));
        }
        panic!("unknown unm struct case: {name}");
    }

    #[test]
    fn parity_against_go_fixture() {
        let raw = std::fs::read_to_string(fixture_path()).unwrap();
        let mut count = 0usize;
        for (idx, line) in raw.lines().enumerate() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            count += 1;
            let cols: Vec<&str> = line.split('\t').collect();
            match cols[0] {
                "MSTR" => {
                    let name = cols[1];
                    let inp = decode_hex(cols[2]);
                    let want = decode_hex(cols[3]);
                    assert_eq!(
                        marshal_raw_string(&inp),
                        want,
                        "line {} MSTR marshal_raw_string({name})",
                        idx + 1
                    );
                    if let Ok(s) = std::str::from_utf8(&inp) {
                        assert_eq!(
                            marshal(&s),
                            want,
                            "line {} MSTR marshal(&str) ({name})",
                            idx + 1
                        );
                    }
                }
                "MF64" => {
                    let name = cols[1];
                    let bits = u64::from_str_radix(cols[2], 16).unwrap();
                    let f = f64::from_bits(bits);
                    assert_eq!(marshal_string(&f), cols[3], "line {} MF64({name})", idx + 1);
                }
                "MF32" => {
                    let name = cols[1];
                    let bits = u32::from_str_radix(cols[2], 16).unwrap();
                    let f = f32::from_bits(bits);
                    assert_eq!(marshal_string(&f), cols[3], "line {} MF32({name})", idx + 1);
                }
                "MI64" => {
                    let name = cols[1];
                    let val: i64 = cols[2].parse().unwrap();
                    assert_eq!(
                        marshal_string(&val),
                        cols[3],
                        "line {} MI64({name})",
                        idx + 1
                    );
                }
                "MU64" => {
                    let name = cols[1];
                    let val: u64 = cols[2].parse().unwrap();
                    assert_eq!(
                        marshal_string(&val),
                        cols[3],
                        "line {} MU64({name})",
                        idx + 1
                    );
                }
                "MMAP" => {
                    let name = cols[1];
                    let want = decode_hex(cols[3]);
                    assert_eq!(build_map_case(name), want, "line {} MMAP({name})", idx + 1);
                }
                "MIND" => {
                    let name = cols[1];
                    let prefix_bytes = decode_hex(cols[2]);
                    let indent_bytes = decode_hex(cols[3]);
                    let prefix = std::str::from_utf8(&prefix_bytes).unwrap();
                    let indent = std::str::from_utf8(&indent_bytes).unwrap();
                    let want = decode_hex(cols[4]);
                    assert_eq!(
                        build_indent_case(name, prefix, indent),
                        want,
                        "line {} MIND({name})",
                        idx + 1
                    );
                }
                "SYN" => {
                    let name = cols[1];
                    let inp = decode_hex(cols[2]);
                    let want = String::from_utf8(decode_hex(cols[3])).unwrap();
                    let got = match check_valid(&inp) {
                        Ok(()) => "OK".to_string(),
                        Err(e) => format!("ERR:{e}"),
                    };
                    assert_eq!(got, want, "line {} SYN check_valid({name})", idx + 1);
                    let got_parse = match parse(&inp) {
                        Ok(_) => "OK".to_string(),
                        Err(e) => format!("ERR:{e}"),
                    };
                    assert_eq!(got_parse, want, "line {} SYN parse({name})", idx + 1);
                }
                "DEC" => {
                    let name = cols[1];
                    let inp = decode_hex(cols[2]);
                    let want = String::from_utf8(decode_hex(cols[3])).unwrap();
                    let got = match value_len(&inp) {
                        Ok(_) => "OK".to_string(),
                        Err(e) => format!("ERR:{e}"),
                    };
                    assert_eq!(got, want, "line {} DEC({name})", idx + 1);
                }
                "UNM_STR" => {
                    let name = cols[1];
                    let inp = decode_hex(cols[2]);
                    let want = decode_hex(cols[3]);
                    let GoValue::Str(s) = parse(&inp).unwrap() else {
                        panic!("line {} expected Str", idx + 1);
                    };
                    assert_eq!(
                        s.as_bytes(),
                        want.as_slice(),
                        "line {} UNM_STR({name})",
                        idx + 1
                    );
                }
                "UNM_STRUCT" => {
                    let name = cols[1];
                    let inp = decode_hex(cols[2]);
                    let want = String::from_utf8(decode_hex(cols[3])).unwrap();
                    assert_eq!(
                        run_unm_struct_case(name, &inp),
                        want,
                        "line {} UNM_STRUCT({name})",
                        idx + 1
                    );
                }
                other => panic!("unknown fixture tag {other} on line {}", idx + 1),
            }
        }
        assert!(count >= 100, "expected >= 100 fixture cases, got {count}");
    }

    // ---- dedicated tests proving each difference between Copy A, Copy B, and Go ----

    #[test]
    fn diff_escape_html_controls_and_invalid_utf8() {
        assert_eq!(
            marshal_string(&"<a&b>\u{2028}\u{2029}\x08\x0c\x7f\u{fffd}"),
            "\"\\u003ca\\u0026b\\u003e\\u2028\\u2029\\b\\f\x7f\u{fffd}\""
        );
        assert_eq!(
            marshal_raw_string(b"\xff\xe2\x82a\xef\xbf\xbd"),
            b"\"\\ufffd\\ufffd\\ufffda\xef\xbf\xbd\""
        );
    }

    #[test]
    fn diff_float_formatting_matches_go() {
        assert_eq!(marshal_string(&0.0_f64), "0");
        assert_eq!(marshal_string(&-0.0_f64), "-0");
        assert_eq!(marshal_string(&1.0_f64), "1");
        assert_eq!(marshal_string(&1e-6_f64), "0.000001");
        assert_eq!(marshal_string(&9.999999e-7_f64), "9.999999e-7");
        assert_eq!(marshal_string(&1e20_f64), "100000000000000000000");
        assert_eq!(marshal_string(&1e21_f64), "1e+21");
        assert_eq!(marshal_string(&9.999999e-7_f32), "9.999999e-7");
    }

    #[test]
    fn diff_invalid_utf8_parse_byte_by_byte() {
        let GoValue::Str(s) = parse(b"\"\xe2\x82a\"").unwrap() else {
            panic!("expected string");
        };
        assert_eq!(s, "\u{fffd}\u{fffd}a");
    }

    #[test]
    fn diff_lone_surrogates_decode_to_fffd() {
        let GoValue::Str(s) = parse(br#""\ud800x\udc00\ud83d\ude00""#).unwrap() else {
            panic!("expected string");
        };
        assert_eq!(s, "\u{fffd}x\u{fffd}😀");
    }

    #[test]
    fn diff_numbers_preserve_literal_and_neg_zero_int() {
        let GoValue::Num(n) = parse(b"1e2").unwrap() else {
            panic!("expected num");
        };
        assert_eq!(n, "1e2");
        assert!(matches!(parse(b"1e400").unwrap(), GoValue::Num(ref s) if s == "1e400"));

        let v = parse(br#"{"N":-0}"#).unwrap();
        let mut out = 42i64;
        let mut d = Dec::new();
        d.object(&v, "S", "main.S", &["N"], |d, _, x| d.int(x, &mut out));
        d.finish().unwrap();
        assert_eq!(out, 0);

        for (lit, want) in [
            ("1.0", "number 1.0"),
            ("1.50", "number 1.50"),
            ("1e2", "number 1e2"),
            ("99999999999999999999", "number 99999999999999999999"),
            ("1e400", "number 1e400"),
        ] {
            let v = parse(format!(r#"{{"N":{lit}}}"#).as_bytes()).unwrap();
            let mut n = 0i64;
            let mut d = Dec::new();
            d.object(&v, "S", "main.S", &["N"], |d, _, x| d.int(x, &mut n));
            assert_eq!(
                d.finish().unwrap_err(),
                format!("json: cannot unmarshal {want} into Go struct field S.N of type int")
            );
        }
    }

    #[test]
    fn diff_deep_nesting_up_to_10000() {
        let ok200 = format!("{}{}", "[".repeat(200), "]".repeat(200));
        assert!(parse(ok200.as_bytes()).is_ok());

        let ok10000 = format!("{}{}", "[".repeat(10000), "]".repeat(10000));
        assert!(parse(ok10000.as_bytes()).is_ok());

        let too_deep = format!("{}{}", "[".repeat(10001), "]".repeat(10001));
        assert_eq!(
            parse(too_deep.as_bytes()).unwrap_err(),
            "invalid character '[' exceeded max depth"
        );
    }

    #[test]
    fn diff_unicode_case_folding_and_exact_match_priority() {
        // Kelvin (\u212a), long s (\u017f), É vs é, ẞ vs ß all fold; ß vs ss and ı vs I do not.
        assert!(fold_eq("\u{212a}", "k"));
        assert!(fold_eq("\u{017f}", "s"));
        assert!(fold_eq("É", "é"));
        assert!(fold_eq("ẞ", "ß"));
        assert!(!fold_eq("ß", "ss"));
        assert!(!fold_eq("ı", "I"));

        let v = parse(br#"{"a":"low","A":"up"}"#).unwrap();
        let (mut up, mut low) = (String::new(), String::new());
        let mut d = Dec::new();
        d.object(&v, "Exact", "main.Exact", &["A", "a"], |d, f, x| match f {
            "A" => d.string(x, &mut up),
            _ => d.string(x, &mut low),
        });
        d.finish().unwrap();
        assert_eq!(up, "up");
        assert_eq!(low, "low");
    }

    #[test]
    fn diff_duplicate_slice_reuses_backing_array() {
        let v = parse(br#"{"e":["x","y"],"e":["a"],"e":[null,null]}"#).unwrap();
        let mut sl = GoSlice::<String>::default();
        let mut d = Dec::new();
        d.object(&v, "S", "main.S", &["e"], |d, _, x| {
            d.go_strings(x, &mut sl)
        });
        d.finish().unwrap();
        assert_eq!(sl.get(), Some(vec!["a".into(), "y".into()]));

        let v2 = parse(br#"{"e":["x","y"],"e":[],"e":[null]}"#).unwrap();
        let mut sl2 = GoSlice::<String>::default();
        let mut d2 = Dec::new();
        d2.object(&v2, "S", "main.S", &["e"], |d, _, x| {
            d.go_strings(x, &mut sl2)
        });
        d2.finish().unwrap();
        assert_eq!(sl2.get(), Some(vec!["".into()]));

        // Option<Vec<String>> reuses elements up to current vec len on duplicate keys.
        let v3 = parse(br#"{"e":["x","y"],"e":[null]}"#).unwrap();
        let mut opt: Option<Vec<String>> = None;
        let mut d3 = Dec::new();
        d3.object(&v3, "S", "main.S", &["e"], |d, _, x| d.strings(x, &mut opt));
        d3.finish().unwrap();
        assert_eq!(opt, Some(vec!["x".into()]));
    }

    #[test]
    fn diff_marshal_indent_prefix_and_empty_containers() {
        #[derive(Serialize)]
        struct S {
            a: BTreeMap<String, i64>,
            b: Vec<i64>,
            c: Vec<i64>,
        }
        let s = S {
            a: BTreeMap::new(),
            b: Vec::new(),
            c: vec![1, 2],
        };
        assert_eq!(
            marshal_indent_with_string(&s, ">>", "  "),
            "{\n>>  \"a\": {},\n>>  \"b\": [],\n>>  \"c\": [\n>>    1,\n>>    2\n>>  ]\n>>}"
        );
    }

    #[test]
    fn diff_value_len_streaming_eof_vs_check_valid() {
        for inp in [b"1.".as_slice(), b"-", b"1e", b"tru", b"{"] {
            assert_eq!(value_len(inp).unwrap_err(), "unexpected EOF");
        }
        assert_eq!(value_len(b"123x").unwrap(), 3);
        assert_eq!(value_len(b"{}x").unwrap(), 2);
        assert_eq!(
            check_valid(b"1.").unwrap_err(),
            "invalid character ' ' after decimal point in numeric literal"
        );
    }

    #[test]
    fn diff_nested_struct_and_slice_error_context() {
        let v = parse(br#"{"in":{"name":123}}"#).unwrap();
        let mut d = Dec::new();
        d.object(&v, "Outer", "main.Outer", &["in"], |d, _, x| {
            d.object(x, "Inner", "main.Inner", &["name"], |d, _, y| {
                d.string(y, &mut String::new());
            });
        });
        assert_eq!(
            d.finish().unwrap_err(),
            "json: cannot unmarshal number into Go struct field Inner.in.name of type string"
        );
    }

    #[test]
    fn quote_char_basics() {
        assert_eq!(quote_char(b'\''), "'\\''");
        assert_eq!(quote_char(b'"'), "'\"'");
        assert_eq!(quote_char(b'\\'), "'\\\\'");
        assert_eq!(quote_char(b'\n'), "'\\n'");
        assert_eq!(quote_char(0x01), "'\\x01'");
        assert_eq!(quote_char(0x7f), "'\\x7f'");
        assert_eq!(quote_char(0x80), "'\\u0080'");
        assert_eq!(quote_char(0xad), "'\\u00ad'");
        assert_eq!(quote_char(0xc3), "'Ã'");
    }
}
