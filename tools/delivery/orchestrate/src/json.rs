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

//! JSON, the way Go's encoding/json does it.
//!
//! Emitting goes through serde_json with [`GoFormatter`], which adds the one
//! thing serde_json does differently: Go escapes `<`, `>`, `&`, U+2028 and
//! U+2029. Everything else (key order, `null` for an absent list, the
//! two-space indent) falls out of serde's derive.
//!
//! Reading cannot go through serde_json, because the manifest QUOTES the
//! decoder's error: a unit whose metadata is broken fails open with
//! "delivery metadata for X unreadable: <Go's message>". [`parse`] is Go's
//! scanner state machine, so its first error is Go's, word for word, and
//! [`decode_unit_meta`] applies encoding/json's struct rules (case-folded
//! keys, last key wins, null leaves a field alone, the first type error is
//! the one reported).

use crate::gostd::quote_rune;
use serde::Serialize;
use std::io;

// ---------------------------------------------------------------------------
// emission
// ---------------------------------------------------------------------------

/// A serde_json formatter that escapes like Go's json.Marshal.
pub struct GoFormatter<F>(pub F);

macro_rules! delegate {
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
    delegate! {
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
}

/// json.Marshal.
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

/// json.MarshalIndent(v, "", "  ").
pub fn marshal_indent<T: Serialize>(v: &T) -> Vec<u8> {
    let mut out = Vec::new();
    let fmt = GoFormatter(serde_json::ser::PrettyFormatter::with_indent(b"  "));
    let mut ser = serde_json::Serializer::with_formatter(&mut out, fmt);
    v.serialize(&mut ser)
        .expect("serializing to memory cannot fail");
    out
}

// ---------------------------------------------------------------------------
// reading: Go's scanner
// ---------------------------------------------------------------------------

/// A parsed JSON value. Numbers keep their literal text (Go's int decoding
/// and its error message both work from it) and objects keep document order
/// and duplicates (the last duplicate wins, as in Go).
#[derive(Debug, Clone, PartialEq)]
pub enum Val {
    Null,
    Bool(bool),
    Num(String),
    Str(String),
    Arr(Vec<Val>),
    Obj(Vec<(String, Val)>),
}

const MAX_DEPTH: usize = 10000;

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

/// quoteChar from encoding/json/scanner.go. A byte is quoted as the rune
/// with that value, so 0xC3 prints as 'Ã'.
fn quote_char(c: u8) -> String {
    if c == b'\'' {
        return "'\\''".to_string();
    }
    if c == b'"' {
        return "'\"'".to_string();
    }
    let mut s = String::from("'");
    quote_rune(&mut s, char::from(c), '"');
    s.push('\'');
    s
}

struct Scanner {
    step: St,
    parse: Vec<Ps>,
    end_top: bool,
    err: Option<String>,
}

fn is_space(c: u8) -> bool {
    c == b' ' || c == b'\t' || c == b'\r' || c == b'\n'
}

impl Scanner {
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
                if c.is_ascii_digit() {
                } else {
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
}

/// checkValid: Go's syntax verdict and, on failure, its exact message.
pub fn check_valid(data: &[u8]) -> Result<(), String> {
    let mut s = Scanner {
        step: St::BeginValue,
        parse: Vec::new(),
        end_top: false,
        err: None,
    };
    for &c in data {
        s.feed(c);
        if let Some(e) = s.err.take() {
            return Err(e);
        }
    }
    // eof(): one more space, then "unexpected end" unless that completed it.
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

/// json.Unmarshal's syntax pass followed by building the value.
pub fn parse(data: &[u8]) -> Result<Val, String> {
    check_valid(data)?;
    let mut p = Builder { d: data, i: 0 };
    Ok(p.value())
}

/// utf8.DecodeRune: one invalid byte is one U+FFFD.
fn decode_rune(s: &[u8]) -> (char, usize) {
    for n in 1..=s.len().min(4) {
        if let Ok(t) = std::str::from_utf8(&s[..n]) {
            return (t.chars().next().unwrap(), n);
        }
    }
    ('\u{fffd}', 1)
}

/// Go's string-bytes conversion: invalid UTF-8 becomes U+FFFD byte by byte.
pub fn go_string(b: &[u8]) -> String {
    let mut out = String::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        let (c, n) = decode_rune(&b[i..]);
        out.push(c);
        i += n;
    }
    out
}

/// Builds the tree from input check_valid already accepted.
struct Builder<'a> {
    d: &'a [u8],
    i: usize,
}

impl<'a> Builder<'a> {
    fn ws(&mut self) {
        while self.i < self.d.len() && is_space(self.d[self.i]) {
            self.i += 1;
        }
    }

    fn value(&mut self) -> Val {
        self.ws();
        match self.d[self.i] {
            b'{' => {
                self.i += 1;
                let mut out = Vec::new();
                loop {
                    self.ws();
                    if self.d[self.i] == b'}' {
                        self.i += 1;
                        return Val::Obj(out);
                    }
                    if self.d[self.i] == b',' {
                        self.i += 1;
                        self.ws();
                    }
                    let k = self.string();
                    self.ws();
                    self.i += 1; // ':'
                    let v = self.value();
                    out.push((k, v));
                }
            }
            b'[' => {
                self.i += 1;
                let mut out = Vec::new();
                loop {
                    self.ws();
                    if self.d[self.i] == b']' {
                        self.i += 1;
                        return Val::Arr(out);
                    }
                    if self.d[self.i] == b',' {
                        self.i += 1;
                    }
                    out.push(self.value());
                }
            }
            b'"' => Val::Str(self.string()),
            b't' => {
                self.i += 4;
                Val::Bool(true)
            }
            b'f' => {
                self.i += 5;
                Val::Bool(false)
            }
            b'n' => {
                self.i += 4;
                Val::Null
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
                Val::Num(String::from_utf8_lossy(&self.d[start..self.i]).into_owned())
            }
        }
    }

    fn hex4(&mut self) -> u32 {
        let h = std::str::from_utf8(&self.d[self.i..self.i + 4]).unwrap();
        self.i += 4;
        u32::from_str_radix(h, 16).unwrap()
    }

    /// Go's unquote: lone surrogates and invalid UTF-8 become U+FFFD.
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
                                // A high surrogate pairs only with an immediately
                                // following \u low surrogate.
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
                    let (r, n) = decode_rune(&self.d[self.i..]);
                    out.push(r);
                    self.i += n;
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// reading: encoding/json's struct rules
// ---------------------------------------------------------------------------

/// The case folding encoding/json matches struct field names with.
fn fold(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        if c.is_ascii() {
            out.push(c.to_ascii_uppercase());
        } else {
            for l in c.to_lowercase() {
                out.extend(l.to_uppercase());
            }
        }
    }
    out
}

fn kind_name(v: &Val) -> &'static str {
    match v {
        Val::Null => "null",
        Val::Bool(_) => "bool",
        Val::Num(_) => "number",
        Val::Str(_) => "string",
        Val::Arr(_) => "array",
        Val::Obj(_) => "object",
    }
}

/// A Go []string as the decoder sees it: a backing array whose spare
/// capacity survives a shorter re-decode (Go decodes a duplicate key's array
/// into the slice it already has, and a null element leaves a slot alone).
#[derive(Debug, Clone, Default)]
pub struct GoSlice {
    backing: Vec<String>,
    len: usize,
    non_nil: bool,
}

impl GoSlice {
    pub fn get(&self) -> Option<Vec<String>> {
        if self.non_nil {
            Some(self.backing[..self.len].to_vec())
        } else {
            None
        }
    }
}

/// tools/delivery/defs.bzl's metadata, as unitMeta decodes it.
#[derive(Debug, Clone, Default)]
pub struct UnitMeta {
    pub schema: i64,
    pub name: String,
    pub kind: String,
    pub run: String,
    pub build: String,
    pub environments: Option<Vec<String>>,
    pub github_environment: String,
    pub promotion: String,
    pub companions: Option<Vec<String>>,
    pub extra_paths: Option<Vec<String>>,
    pub exclude_paths: Option<Vec<String>>,
    pub graph_targets: Option<Vec<String>>,
    pub preflight: String,
    pub package: String,
}

#[derive(Clone, Copy)]
enum FieldKind {
    Int,
    Str,
    List,
}

const FIELDS: [(&str, FieldKind); 14] = [
    ("schema", FieldKind::Int),
    ("name", FieldKind::Str),
    ("kind", FieldKind::Str),
    ("run", FieldKind::Str),
    ("build", FieldKind::Str),
    ("environments", FieldKind::List),
    ("github_environment", FieldKind::Str),
    ("promotion", FieldKind::Str),
    ("companions", FieldKind::List),
    ("extra_paths", FieldKind::List),
    ("exclude_paths", FieldKind::List),
    ("graph_targets", FieldKind::List),
    ("preflight", FieldKind::Str),
    ("package", FieldKind::Str),
];

struct Decoding {
    ints: i64,
    strs: [String; 14],
    lists: Vec<GoSlice>,
    first_err: Option<String>,
}

impl Decoding {
    fn type_err(&mut self, value: &str, field: &str, ty: &str) {
        if self.first_err.is_none() {
            self.first_err = Some(format!(
                "json: cannot unmarshal {} into Go struct field unitMeta.{} of type {}",
                value, field, ty
            ));
        }
    }
}

/// strconv.ParseInt(s, 10, 64).
fn parse_int(s: &str) -> Option<i64> {
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

/// json.Unmarshal(raw, &unitMeta{}).
pub fn decode_unit_meta(raw: &[u8]) -> Result<UnitMeta, String> {
    let v = parse(raw)?;
    let mut d = Decoding {
        ints: 0,
        strs: Default::default(),
        lists: vec![GoSlice::default(); 14],
        first_err: None,
    };
    match &v {
        Val::Null => {}
        Val::Obj(entries) => {
            for (key, val) in entries {
                let fk = fold(key);
                let Some(idx) = FIELDS.iter().position(|(n, _)| fold(n) == fk) else {
                    continue;
                };
                let (fname, kind) = FIELDS[idx];
                match (kind, val) {
                    (_, Val::Null) if !matches!(kind, FieldKind::List) => {}
                    (FieldKind::Int, Val::Num(lit)) => match parse_int(lit) {
                        Some(n) => d.ints = n,
                        None => d.type_err(&format!("number {}", lit), fname, "int"),
                    },
                    (FieldKind::Int, other) => d.type_err(kind_name(other), fname, "int"),
                    (FieldKind::Str, Val::Str(s)) => d.strs[idx] = s.clone(),
                    (FieldKind::Str, other) => d.type_err(kind_name(other), fname, "string"),
                    (FieldKind::List, Val::Null) => d.lists[idx] = GoSlice::default(),
                    (FieldKind::List, Val::Arr(items)) => {
                        let mut sl = std::mem::take(&mut d.lists[idx]);
                        let mut i = 0;
                        for item in items {
                            let cap = sl.backing.len();
                            if i >= cap {
                                let newcap = (cap + cap / 2).max(4);
                                let mut nb: Vec<String> = sl.backing[..sl.len].to_vec();
                                nb.resize(newcap, String::new());
                                sl.backing = nb;
                                sl.non_nil = true;
                            }
                            if i >= sl.len {
                                sl.len = i + 1;
                            }
                            match item {
                                Val::Null => {}
                                Val::Str(s) => sl.backing[i] = s.clone(),
                                other => d.type_err(kind_name(other), fname, "string"),
                            }
                            i += 1;
                        }
                        if i < sl.len {
                            sl.len = i;
                        }
                        if i == 0 {
                            sl = GoSlice {
                                backing: Vec::new(),
                                len: 0,
                                non_nil: true,
                            };
                        }
                        d.lists[idx] = sl;
                    }
                    (FieldKind::List, other) => d.type_err(kind_name(other), fname, "[]string"),
                }
            }
        }
        other => {
            return Err(format!(
                "json: cannot unmarshal {} into Go value of type main.unitMeta",
                kind_name(other)
            ))
        }
    }
    if let Some(e) = d.first_err {
        return Err(e);
    }
    let s = |i: usize| d.strs[i].clone();
    let l = |i: usize| d.lists[i].get();
    Ok(UnitMeta {
        schema: d.ints,
        name: s(1),
        kind: s(2),
        run: s(3),
        build: s(4),
        environments: l(5),
        github_environment: s(6),
        promotion: s(7),
        companions: l(8),
        extra_paths: l(9),
        exclude_paths: l(10),
        graph_targets: l(11),
        preflight: s(12),
        package: s(13),
    })
}

/// json.Unmarshal into a map[string]string, as orchestrate() uses it for
/// UNIT_BASES_JSON: any error leaves the caller with an empty map.
pub fn decode_string_map(raw: &[u8]) -> Option<Vec<(String, String)>> {
    match parse(raw).ok()? {
        Val::Null => Some(Vec::new()),
        Val::Obj(entries) => {
            let mut out = Vec::with_capacity(entries.len());
            for (k, v) in entries {
                match v {
                    Val::Str(s) => out.push((k, s)),
                    Val::Null => out.push((k, String::new())),
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

    #[test]
    fn syntax_errors_are_gos() {
        let cases: &[(&str, &str)] = &[
            (
                "{ this is not json",
                "invalid character 't' looking for beginning of object key string",
            ),
            ("", "unexpected end of JSON input"),
            ("{", "unexpected end of JSON input"),
            ("-", "invalid character ' ' in numeric literal"),
            (
                "1.",
                "invalid character ' ' after decimal point in numeric literal",
            ),
            ("1e", "invalid character ' ' in exponent of numeric literal"),
            (
                "tx",
                "invalid character 'x' in literal true (expecting 'r')",
            ),
            ("{} x", "invalid character 'x' after top-level value"),
            ("[1 2]", "invalid character '2' after array element"),
            ("{\"a\" 1}", "invalid character '1' after object key"),
            (
                "{\"a\":1 2}",
                "invalid character '2' after object key:value pair",
            ),
            ("\"\\q\"", "invalid character 'q' in string escape code"),
            (
                "\"\\u12x4\"",
                "invalid character 'x' in \\u hexadecimal character escape",
            ),
            ("\"a\nb\"", "invalid character '\\n' in string literal"),
            (
                "'",
                "invalid character '\\'' looking for beginning of value",
            ),
        ];
        for (input, want) in cases {
            assert_eq!(
                check_valid(input.as_bytes()).unwrap_err(),
                *want,
                "input {:?}",
                input
            );
        }
        assert!(check_valid(b" {\"a\": [1, -0.5e+3, true, null, \"\\ud83d\\ude00\"]} ").is_ok());
    }

    #[test]
    fn unit_meta_follows_go_rules() {
        let m = decode_unit_meta(
            br#"{"NAME":"a","name":"b","environments":["x","y"],"environments":[null]}"#,
        )
        .unwrap();
        assert_eq!(m.name, "b");
        assert_eq!(m.environments, Some(vec!["x".to_string()]));
        assert_eq!(decode_unit_meta(b"null").unwrap().name, "");
        assert_eq!(
            decode_unit_meta(br#"{"extra_paths":[]}"#)
                .unwrap()
                .extra_paths,
            Some(vec![])
        );
        assert_eq!(
            decode_unit_meta(br#"{"extra_paths":null}"#)
                .unwrap()
                .extra_paths,
            None
        );
        assert_eq!(
            decode_unit_meta(br#"{"schema":"1","name":3}"#).unwrap_err(),
            "json: cannot unmarshal string into Go struct field unitMeta.schema of type int"
        );
        assert_eq!(
            decode_unit_meta(br#"{"schema":1.5}"#).unwrap_err(),
            "json: cannot unmarshal number 1.5 into Go struct field unitMeta.schema of type int"
        );
        assert_eq!(
            decode_unit_meta(b"[]").unwrap_err(),
            "json: cannot unmarshal array into Go value of type main.unitMeta"
        );
    }

    #[test]
    fn marshal_escapes_like_go() {
        let v = vec!["<a&b>\u{2028}\n\u{1}"];
        assert_eq!(
            String::from_utf8(marshal(&v)).unwrap(),
            r#"["\u003ca\u0026b\u003e\u2028\n\u0001"]"#
        );
    }

    #[test]
    fn string_map() {
        assert_eq!(decode_string_map(b"{not json"), None);
        assert_eq!(decode_string_map(br#"{"a":1}"#), None);
        assert_eq!(
            decode_string_map(br#"{"a":"x"}"#),
            Some(vec![("a".into(), "x".into())])
        );
    }
}
