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

//! A JSON reader that reads what Python's `json.loads` reads (NaN and
//! Infinity, integers of any size, the last of two equal keys winning), a
//! writer that writes what `json.dumps` writes with its defaults, and
//! Python's `==` (`py_eq`).

use crate::pystr;

#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Null,
    Bool(bool),
    /// An integer, kept as its text: Python's ints have no size limit.
    Int(String),
    Float(f64),
    Str(String),
    Arr(Vec<Value>),
    /// Keys in document order; a repeated key keeps its first position and
    /// its last value, as a dict built by `json.loads` does.
    Obj(Vec<(String, Value)>),
}

/// Code-point-preserving JSON value returned by [`loads_codepoints`].
///
/// Keeps Python's exact `str` code points (`Vec<u32>`), including lone
/// surrogates (`0xD800..=0xDFFF`) that Rust's UTF-8 `String` cannot hold.
/// Implements an iterative [`Drop`] so arbitrarily nested values can be
/// dropped without overflowing the call stack.
#[derive(Clone, Debug, PartialEq)]
pub enum CodepointValue {
    Null,
    Bool(bool),
    /// An integer, kept as its text: Python's ints have no size limit.
    Int(String),
    Float(f64),
    /// A string as Unicode code points (may contain lone surrogates `0xD800..=0xDFFF`).
    Str(Vec<u32>),
    Arr(Vec<CodepointValue>),
    /// Keys in document order; a repeated key keeps its first position and
    /// its last value, as a dict built by `json.loads` does.
    Obj(Vec<(Vec<u32>, CodepointValue)>),
}

impl Drop for CodepointValue {
    fn drop(&mut self) {
        if !matches!(self, CodepointValue::Arr(a) if !a.is_empty())
            && !matches!(self, CodepointValue::Obj(o) if !o.is_empty())
        {
            return;
        }
        let mut stack: Vec<CodepointValue> = Vec::new();
        drain_codepoint_value(self, &mut stack);
        while let Some(mut v) = stack.pop() {
            drain_codepoint_value(&mut v, &mut stack);
        }
    }
}

fn drain_codepoint_value(v: &mut CodepointValue, stack: &mut Vec<CodepointValue>) {
    match v {
        CodepointValue::Arr(items) if !items.is_empty() => stack.extend(std::mem::take(items)),
        CodepointValue::Obj(items) if !items.is_empty() => {
            for (_, val) in std::mem::take(items) {
                stack.push(val);
            }
        }
        _ => {}
    }
}

impl Value {
    /// Drop a potentially deeply nested [`Value`] using an explicit heap stack
    /// instead of call-stack recursion.
    ///
    /// [`Value`] intentionally does not implement [`Drop`] so existing callers
    /// can move fields out by pattern match; call this to safely free very
    /// deeply nested values without overflowing the stack.
    pub fn drop_iteratively(self) {
        let mut stack = vec![self];
        while let Some(v) = stack.pop() {
            match v {
                Value::Arr(items) => stack.extend(items),
                Value::Obj(items) => {
                    for (_, val) in items {
                        stack.push(val);
                    }
                }
                _ => {}
            }
        }
    }

    /// `d.get(key)` on an object; None for a missing key or a non-object.
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Obj(items) => items.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    pub fn is_obj(&self) -> bool {
        matches!(self, Value::Obj(_))
    }

    /// Python truthiness.
    pub fn truthy(&self) -> bool {
        match self {
            Value::Null => false,
            Value::Bool(b) => *b,
            Value::Int(s) => s.trim_start_matches('-').chars().any(|c| c != '0'),
            Value::Float(f) => *f != 0.0,
            Value::Str(s) => !s.is_empty(),
            Value::Arr(a) => !a.is_empty(),
            Value::Obj(o) => !o.is_empty(),
        }
    }

    /// The Python type name, for error messages.
    pub fn type_name(&self) -> &'static str {
        match self {
            Value::Null => "NoneType",
            Value::Bool(_) => "bool",
            Value::Int(_) => "int",
            Value::Float(_) => "float",
            Value::Str(_) => "str",
            Value::Arr(_) => "list",
            Value::Obj(_) => "dict",
        }
    }

    /// As a float, the way arithmetic on an int, float or bool sees it.
    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Value::Bool(b) => Some(if *b { 1.0 } else { 0.0 }),
            Value::Int(s) => s.parse::<f64>().ok(),
            Value::Float(f) => Some(*f),
            _ => None,
        }
    }

    /// `str(value)`, as an f-string would format it.
    pub fn py_str(&self) -> String {
        match self {
            Value::Str(s) => s.clone(),
            other => other.py_repr(),
        }
    }

    /// `repr(value)`.
    pub fn py_repr(&self) -> String {
        match self {
            Value::Null => "None".into(),
            Value::Bool(true) => "True".into(),
            Value::Bool(false) => "False".into(),
            Value::Int(s) => normalize_int(s),
            Value::Float(f) => pystr::repr_float(*f),
            Value::Str(s) => pystr::repr_str(s),
            Value::Arr(items) => {
                let parts: Vec<String> = items.iter().map(|v| v.py_repr()).collect();
                format!("[{}]", parts.join(", "))
            }
            Value::Obj(items) => {
                let parts: Vec<String> = dedup(items)
                    .iter()
                    .map(|(k, v)| format!("{}: {}", pystr::repr_str(k), v.py_repr()))
                    .collect();
                format!("{{{}}}", parts.join(", "))
            }
        }
    }
}

fn normalize_int(s: &str) -> String {
    let (neg, digits) = match s.strip_prefix('-') {
        Some(d) => (true, d),
        None => (false, s),
    };
    let trimmed = digits.trim_start_matches('0');
    if trimmed.is_empty() {
        "0".into()
    } else if neg {
        format!("-{}", trimmed)
    } else {
        trimmed.into()
    }
}

/// The items of an object as the dict holds them: first position, last value.
pub fn dedup(items: &[(String, Value)]) -> Vec<(String, Value)> {
    let mut out: Vec<(String, Value)> = Vec::new();
    for (k, v) in items {
        if let Some(slot) = out.iter_mut().find(|(ek, _)| ek == k) {
            slot.1 = v.clone();
        } else {
            out.push((k.clone(), v.clone()));
        }
    }
    out
}

/// `a == b` in Python: ints, floats and bools compare by value, exactly
/// (an int equals a float only if the float is that very integer), dicts
/// regardless of key order.
pub fn py_eq(a: &Value, b: &Value) -> bool {
    use Value::*;
    match (a, b) {
        (Null, Null) => true,
        (Str(x), Str(y)) => x == y,
        (Float(x), Float(y)) => x == y,
        (Arr(x), Arr(y)) => x.len() == y.len() && x.iter().zip(y).all(|(p, q)| py_eq(p, q)),
        (Obj(x), Obj(y)) => {
            let (x, y) = (dedup(x), dedup(y));
            x.len() == y.len()
                && x.iter()
                    .all(|(k, v)| y.iter().any(|(k2, v2)| k == k2 && py_eq(v, v2)))
        }
        _ => match (int_text(a), int_text(b)) {
            (Some(x), Some(y)) => x == y,
            (Some(x), None) => float_is(b, &x),
            (None, Some(y)) => float_is(a, &y),
            (None, None) => false,
        },
    }
}

/// An int or a bool as its normalized decimal text.
fn int_text(v: &Value) -> Option<String> {
    match v {
        Value::Int(s) => Some(normalize_int(s)),
        Value::Bool(b) => Some(if *b { "1" } else { "0" }.into()),
        _ => None,
    }
}

/// Is `v` a float whose exact value is the integer `n`?
fn float_is(v: &Value, n: &str) -> bool {
    match v {
        Value::Float(f) if f.is_finite() && f.fract() == 0.0 => {
            // Rust prints a float's exact decimal value.
            normalize_int(&format!("{:.0}", f)) == n
        }
        _ => false,
    }
}

/// Classification of why [`loads`], [`loads_with`], [`loads_with_limits`],
/// or [`loads_codepoints`] rejected an input.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum JsonErrorKind {
    Decode,
    Recursion,
    IntDigitLimit,
}

/// A document that does not parse. The message is in Python's words where
/// that was easy; callers that mirror a crash only rely on the class.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct JsonError {
    pub msg: String,
    pub pos: usize,
    pub line: usize,
    pub col: usize,
    py_msg: String,
    py_pos: usize,
    kind: JsonErrorKind,
    recursion_msg: Option<&'static str>,
}

impl JsonError {
    /// Classification of the parse failure, for callers that raise distinct
    /// Python exception types (such as `RecursionError` vs `ValueError`).
    pub fn kind(&self) -> JsonErrorKind {
        self.kind
    }

    /// CPython 3.12's `RecursionError` message for container depth errors,
    /// matching whichever container (`array` or `object`) hit the limit;
    /// `None` for non-recursion errors.
    pub fn recursion_message(&self) -> Option<&'static str> {
        self.recursion_msg
    }

    /// Matches CPython 3.12's `json` module `str(json.JSONDecodeError)`:
    /// `"{msg}: line {line} column {col} (char {pos})"`.
    ///
    /// Known version differences vs. CPython 3.13 and later:
    /// 1. For a `\uXXXX` escape that ends at end of input, CPython 3.13 and
    ///    later say `"Unterminated string starting at"`.
    /// 2. For a trailing comma, CPython 3.13 and later say
    ///    `"Illegal trailing comma before end of array/object"`.
    ///
    /// Not an error-text difference, but worth knowing: a lone surrogate
    /// escape (`\ud800` with no low half) decodes to U+FFFD here, where
    /// CPython keeps the surrogate in the string (a Rust `String` cannot).
    /// Callers that need exact lone surrogates should use [`loads_codepoints`].
    pub fn python_str(&self) -> String {
        format!(
            "{}: line {} column {} (char {})",
            self.py_msg, self.line, self.col, self.py_pos
        )
    }
}

impl std::fmt::Display for JsonError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{} (char {})", self.msg, self.pos)
    }
}

/// JSONDecodeError's line and column for a position in the document.
fn locate(codepoints: &[u32], mut e: JsonError) -> JsonError {
    let before = &codepoints[..e.py_pos.min(codepoints.len())];
    e.line = before.iter().filter(|c| **c == 0x0A).count() + 1;
    e.col = match before.iter().rposition(|c| *c == 0x0A) {
        Some(nl) => e.py_pos - nl,
        None => e.py_pos + 1,
    };
    e
}

/// CPython 3.12's default `sys.get_int_max_str_digits()`.
pub const DEFAULT_INT_MAX_STR_DIGITS: usize = 4300;

/// CPython 3.12.16 `json.loads` decodes 9,997 nested arrays or objects and
/// raises `RecursionError` at 9,998 (measured with `/opt/homebrew/bin/python3.12 -I`).
pub const CPYTHON_312_MAX_DEPTH: usize = 9997;

/// Options for [`loads_with`].
///
/// `Default` (`None`) imposes no nesting limit, matching [`loads`].
/// Setting `max_depth: Some(n)` allows up to `n` nested objects/arrays and
/// fails on the `(n + 1)`-th opening `{` or `[` with
/// `"maximum recursion depth exceeded"`.
#[derive(Copy, Clone, Debug, Default, PartialEq, Eq)]
pub struct LoadOptions {
    pub max_depth: Option<usize>,
}

/// Options for [`loads_codepoints`].
///
/// `Default` imposes no nesting limit and no integer-digit limit.
#[derive(Copy, Clone, Debug, Default, PartialEq, Eq)]
pub struct CodepointLoadOptions {
    pub max_depth: Option<usize>,
    pub max_int_digits: Option<usize>,
}

/// Parse JSON with Python's `json.loads` semantics and no nesting limit.
pub fn loads(text: &str) -> Result<Value, JsonError> {
    loads_with(text, &LoadOptions::default())
}

/// Parse JSON with Python's `json.loads` semantics and the given
/// [`LoadOptions`].
pub fn loads_with(text: &str, opts: &LoadOptions) -> Result<Value, JsonError> {
    loads_with_limits(text, opts.max_depth, None)
}

/// Parse JSON with Python's `json.loads` semantics and optional nesting depth
/// (`max_depth`) and integer literal digit (`int_max_str_digits`) limits.
pub fn loads_with_limits(
    text: &str,
    max_depth: Option<usize>,
    int_max_str_digits: Option<usize>,
) -> Result<Value, JsonError> {
    let codepoints: Vec<u32> = text.chars().map(|c| c as u32).collect();
    parse_codepoints::<Utf8Sink>(&codepoints, max_depth, int_max_str_digits)
}

/// Parse Unicode code points with Python's `json.loads` semantics while
/// preserving lone surrogates (`0xD800..=0xDFFF`) and optionally capping
/// nesting depth and integer literal digits.
pub fn loads_codepoints(
    codepoints: &[u32],
    opts: &CodepointLoadOptions,
) -> Result<CodepointValue, JsonError> {
    parse_codepoints::<CodepointSink>(codepoints, opts.max_depth, opts.max_int_digits)
}

trait Sink {
    type Str: Eq;
    type Val;
    fn new_str() -> Self::Str;
    fn push_cp(s: &mut Self::Str, cp: u32);
    fn null() -> Self::Val;
    fn bool(b: bool) -> Self::Val;
    fn int(text: String) -> Self::Val;
    fn float(f: f64) -> Self::Val;
    fn str(s: Self::Str) -> Self::Val;
    fn arr(items: Vec<Self::Val>) -> Self::Val;
    fn obj(items: Vec<(Self::Str, Self::Val)>) -> Self::Val;
    fn drop_val(v: Self::Val);
}

struct Utf8Sink;

impl Sink for Utf8Sink {
    type Str = String;
    type Val = Value;

    fn new_str() -> Self::Str {
        String::new()
    }

    fn push_cp(s: &mut Self::Str, cp: u32) {
        // A lone surrogate cannot live in a Rust string.
        s.push(char::from_u32(cp).unwrap_or('\u{fffd}'));
    }

    fn null() -> Self::Val {
        Value::Null
    }

    fn bool(b: bool) -> Self::Val {
        Value::Bool(b)
    }

    fn int(text: String) -> Self::Val {
        Value::Int(text)
    }

    fn float(f: f64) -> Self::Val {
        Value::Float(f)
    }

    fn str(s: Self::Str) -> Self::Val {
        Value::Str(s)
    }

    fn arr(items: Vec<Self::Val>) -> Self::Val {
        Value::Arr(items)
    }

    fn obj(items: Vec<(Self::Str, Self::Val)>) -> Self::Val {
        Value::Obj(items)
    }

    fn drop_val(v: Self::Val) {
        v.drop_iteratively();
    }
}

struct CodepointSink;

impl Sink for CodepointSink {
    type Str = Vec<u32>;
    type Val = CodepointValue;

    fn new_str() -> Self::Str {
        Vec::new()
    }

    fn push_cp(s: &mut Self::Str, cp: u32) {
        s.push(cp);
    }

    fn null() -> Self::Val {
        CodepointValue::Null
    }

    fn bool(b: bool) -> Self::Val {
        CodepointValue::Bool(b)
    }

    fn int(text: String) -> Self::Val {
        CodepointValue::Int(text)
    }

    fn float(f: f64) -> Self::Val {
        CodepointValue::Float(f)
    }

    fn str(s: Self::Str) -> Self::Val {
        CodepointValue::Str(s)
    }

    fn arr(items: Vec<Self::Val>) -> Self::Val {
        CodepointValue::Arr(items)
    }

    fn obj(items: Vec<(Self::Str, Self::Val)>) -> Self::Val {
        CodepointValue::Obj(items)
    }

    fn drop_val(v: Self::Val) {
        drop(v);
    }
}

fn parse_codepoints<S: Sink>(
    codepoints: &[u32],
    max_depth: Option<usize>,
    max_int_digits: Option<usize>,
) -> Result<S::Val, JsonError> {
    if codepoints.first() == Some(&0xFEFF) {
        let msg = "Unexpected UTF-8 BOM (decode using utf-8-sig)";
        return Err(locate(
            codepoints,
            JsonError {
                msg: msg.into(),
                pos: 0,
                line: 0,
                col: 0,
                py_msg: msg.into(),
                py_pos: 0,
                kind: JsonErrorKind::Decode,
                recursion_msg: None,
            },
        ));
    }
    let mut p = Parser {
        s: codepoints,
        i: 0,
        max_depth,
        max_int_digits,
    };
    let parsed = (|| {
        p.ws();
        let v = p.document::<S>()?;
        p.ws();
        if p.i != codepoints.len() {
            S::drop_val(v);
            return Err(p.err("Extra data"));
        }
        Ok(v)
    })();
    parsed.map_err(|e| locate(codepoints, e))
}

enum Frame<S: Sink> {
    Arr(Vec<S::Val>),
    Obj(Vec<(S::Str, S::Val)>, S::Str),
}

struct FrameStack<S: Sink>(Vec<Frame<S>>);

impl<S: Sink> Drop for FrameStack<S> {
    fn drop(&mut self) {
        while let Some(frame) = self.0.pop() {
            match frame {
                Frame::Arr(items) => {
                    for v in items {
                        S::drop_val(v);
                    }
                }
                Frame::Obj(items, _) => {
                    for (_, v) in items {
                        S::drop_val(v);
                    }
                }
            }
        }
    }
}

fn is_ascii_digit(cp: u32) -> bool {
    (0x30..=0x39).contains(&cp)
}

struct Parser<'a> {
    s: &'a [u32],
    i: usize,
    max_depth: Option<usize>,
    max_int_digits: Option<usize>,
}

impl<'a> Parser<'a> {
    fn err(&self, msg: &str) -> JsonError {
        self.err_with_py(msg, self.i, msg, self.i)
    }

    fn err_with_py(&self, msg: &str, pos: usize, py_msg: &str, py_pos: usize) -> JsonError {
        self.err_kind(msg, pos, py_msg, py_pos, JsonErrorKind::Decode, None)
    }

    fn err_kind(
        &self,
        msg: &str,
        pos: usize,
        py_msg: &str,
        py_pos: usize,
        kind: JsonErrorKind,
        recursion_msg: Option<&'static str>,
    ) -> JsonError {
        JsonError {
            msg: msg.into(),
            pos,
            line: 0,
            col: 0,
            py_msg: py_msg.into(),
            py_pos,
            kind,
            recursion_msg,
        }
    }

    fn peek(&self) -> Option<u32> {
        self.s.get(self.i).copied()
    }

    fn ws(&mut self) {
        while matches!(self.peek(), Some(0x20 | 0x09 | 0x0A | 0x0D)) {
            self.i += 1;
        }
    }

    fn lit(&mut self, word: &str) -> bool {
        let mut j = self.i;
        for b in word.bytes() {
            if self.s.get(j) != Some(&(b as u32)) {
                return false;
            }
            j += 1;
        }
        self.i = j;
        true
    }

    fn object_key<S: Sink>(&mut self) -> Result<S::Str, JsonError> {
        if self.peek() != Some('"' as u32) {
            return Err(self.err("Expecting property name enclosed in double quotes"));
        }
        self.i += 1;
        let key = self.string::<S>()?;
        self.ws();
        if self.peek() != Some(':' as u32) {
            return Err(self.err("Expecting ':' delimiter"));
        }
        self.i += 1;
        self.ws();
        Ok(key)
    }

    fn document<S: Sink>(&mut self) -> Result<S::Val, JsonError> {
        let mut stack = FrameStack::<S>(Vec::new());
        loop {
            let mut container: Option<S::Val> = None;
            if matches!(self.peek(), Some(c) if c == '{' as u32 || c == '[' as u32) {
                let is_obj = self.peek() == Some('{' as u32);
                if let Some(max) = self.max_depth {
                    if stack.0.len() >= max {
                        let recursion_msg = if is_obj {
                            "maximum recursion depth exceeded while decoding a JSON object from a unicode string"
                        } else {
                            "maximum recursion depth exceeded while decoding a JSON array from a unicode string"
                        };
                        return Err(self.err_kind(
                            "maximum recursion depth exceeded",
                            self.i,
                            "maximum recursion depth exceeded",
                            self.i,
                            JsonErrorKind::Recursion,
                            Some(recursion_msg),
                        ));
                    }
                }
                self.i += 1;
                self.ws();
                if is_obj {
                    if self.peek() == Some('}' as u32) {
                        self.i += 1;
                        container = Some(S::obj(Vec::new()));
                    } else {
                        let key = self.object_key::<S>()?;
                        stack.0.push(Frame::Obj(Vec::new(), key));
                        continue;
                    }
                } else if self.peek() == Some(']' as u32) {
                    self.i += 1;
                    container = Some(S::arr(Vec::new()));
                } else {
                    stack.0.push(Frame::Arr(Vec::new()));
                    continue;
                }
            }
            let mut val = match container {
                Some(v) => v,
                None => self.scalar::<S>()?,
            };
            loop {
                let Some(frame) = stack.0.last_mut() else {
                    return Ok(val);
                };
                let (close, is_arr) = match frame {
                    Frame::Arr(items) => {
                        items.push(val);
                        (']' as u32, true)
                    }
                    Frame::Obj(items, key) => {
                        let k = std::mem::replace(key, S::new_str());
                        if let Some(slot) = items.iter_mut().find(|(ek, _)| *ek == k) {
                            let old = std::mem::replace(&mut slot.1, val);
                            S::drop_val(old);
                        } else {
                            items.push((k, val));
                        }
                        ('}' as u32, false)
                    }
                };
                self.ws();
                match self.peek() {
                    Some(ch) if ch == close => {
                        self.i += 1;
                        val = match stack.0.pop().expect("frame present") {
                            Frame::Arr(items) => S::arr(items),
                            Frame::Obj(items, _) => S::obj(items),
                        };
                    }
                    Some(ch) if ch == ',' as u32 => {
                        self.i += 1;
                        self.ws();
                        if !is_arr {
                            let key = self.object_key::<S>()?;
                            if let Some(Frame::Obj(_, slot)) = stack.0.last_mut() {
                                *slot = key;
                            }
                        }
                        break;
                    }
                    _ => return Err(self.err("Expecting ',' delimiter")),
                }
            }
        }
    }

    fn scalar<S: Sink>(&mut self) -> Result<S::Val, JsonError> {
        match self.peek().and_then(char::from_u32) {
            Some('"') => {
                self.i += 1;
                Ok(S::str(self.string::<S>()?))
            }
            Some('n') if self.lit("null") => Ok(S::null()),
            Some('t') if self.lit("true") => Ok(S::bool(true)),
            Some('f') if self.lit("false") => Ok(S::bool(false)),
            Some('N') if self.lit("NaN") => Ok(S::float(f64::NAN)),
            Some('I') if self.lit("Infinity") => Ok(S::float(f64::INFINITY)),
            Some('-') if self.s.get(self.i + 1) == Some(&('I' as u32)) && self.lit("-Infinity") => {
                Ok(S::float(f64::NEG_INFINITY))
            }
            Some(c) if c == '-' || c.is_ascii_digit() => self.number::<S>(),
            _ => Err(self.err("Expecting value")),
        }
    }

    fn number<S: Sink>(&mut self) -> Result<S::Val, JsonError> {
        let start = self.i;
        if self.peek() == Some('-' as u32) {
            self.i += 1;
        }
        match self.peek() {
            Some(c) if c == '0' as u32 => self.i += 1,
            Some(c) if is_ascii_digit(c) => {
                while matches!(self.peek(), Some(c) if is_ascii_digit(c)) {
                    self.i += 1;
                }
            }
            _ => {
                self.i = start;
                return Err(self.err("Expecting value"));
            }
        }
        let mut is_float = false;
        if self.peek() == Some('.' as u32)
            && matches!(self.s.get(self.i + 1), Some(&c) if is_ascii_digit(c))
        {
            is_float = true;
            self.i += 1;
            while matches!(self.peek(), Some(c) if is_ascii_digit(c)) {
                self.i += 1;
            }
        }
        if matches!(self.peek(), Some(c) if c == 'e' as u32 || c == 'E' as u32) {
            let save = self.i;
            self.i += 1;
            if matches!(self.peek(), Some(c) if c == '+' as u32 || c == '-' as u32) {
                self.i += 1;
            }
            if matches!(self.peek(), Some(c) if is_ascii_digit(c)) {
                is_float = true;
                while matches!(self.peek(), Some(c) if is_ascii_digit(c)) {
                    self.i += 1;
                }
            } else {
                self.i = save;
            }
        }
        let text: String = self.s[start..self.i]
            .iter()
            .map(|&c| c as u8 as char)
            .collect();
        if is_float {
            Ok(S::float(text.parse::<f64>().unwrap_or(f64::NAN)))
        } else {
            if let Some(limit) = self.max_int_digits {
                let digits = text.trim_start_matches('-').len();
                if digits > limit {
                    let msg = format!(
                        "Exceeds the limit ({} digits) for integer string conversion: value has {} digits; use sys.set_int_max_str_digits() to increase the limit",
                        limit, digits
                    );
                    return Err(self.err_kind(
                        &msg,
                        start,
                        &msg,
                        start,
                        JsonErrorKind::IntDigitLimit,
                        None,
                    ));
                }
            }
            Ok(S::int(text))
        }
    }

    fn hex4(&mut self) -> Result<u32, JsonError> {
        // JSONDecodeError points at the `u`, just before the digits; preserve
        // `self.i` in `pos` so `Display` matches origin/main.
        if self.i + 4 > self.s.len() {
            return Err(self.err_with_py(
                "Invalid \\uXXXX escape",
                self.i,
                "Invalid \\uXXXX escape",
                self.i - 1,
            ));
        }
        let mut cp = 0u32;
        for k in 0..4 {
            let d = char::from_u32(self.s[self.i + k])
                .and_then(|c| c.to_digit(16))
                .ok_or_else(|| {
                    self.err_with_py(
                        "Invalid \\uXXXX escape",
                        self.i,
                        "Invalid \\uXXXX escape",
                        self.i - 1,
                    )
                })?;
            cp = (cp << 4) | d;
        }
        self.i += 4;
        Ok(cp)
    }

    fn string<S: Sink>(&mut self) -> Result<S::Str, JsonError> {
        let start = self.i - 1;
        let mut out = S::new_str();
        let mut last_u_pos: Option<usize> = None;
        loop {
            let c = match self.peek() {
                None => {
                    // CPython 3.12's `_json.c` rejects a `\uXXXX` escape that ends
                    // right at EOF as `"Invalid \uXXXX escape"` at `u` (3.13+
                    // reports `"Unterminated string starting at"`). Preserve the
                    // legacy `msg`/`pos` so `Display` stays unchanged.
                    let (py_msg, py_pos) = match last_u_pos {
                        Some(u_pos) => ("Invalid \\uXXXX escape", u_pos),
                        None => ("Unterminated string starting at", start),
                    };
                    return Err(self.err_with_py(
                        "Unterminated string starting at",
                        self.i,
                        py_msg,
                        py_pos,
                    ));
                }
                Some(c) => c,
            };
            last_u_pos = None;
            self.i += 1;
            if c == '"' as u32 {
                return Ok(out);
            }
            if c == '\\' as u32 {
                let e = self.peek().ok_or_else(|| {
                    self.err_with_py(
                        "Unterminated string",
                        self.i,
                        "Unterminated string starting at",
                        start,
                    )
                })?;
                self.i += 1;
                match char::from_u32(e) {
                    Some('"') => S::push_cp(&mut out, '"' as u32),
                    Some('\\') => S::push_cp(&mut out, '\\' as u32),
                    Some('/') => S::push_cp(&mut out, '/' as u32),
                    Some('b') => S::push_cp(&mut out, 0x08),
                    Some('f') => S::push_cp(&mut out, 0x0C),
                    Some('n') => S::push_cp(&mut out, 0x0A),
                    Some('r') => S::push_cp(&mut out, 0x0D),
                    Some('t') => S::push_cp(&mut out, 0x09),
                    Some('u') => {
                        let mut cp = self.hex4()?;
                        if (0xD800..0xDC00).contains(&cp)
                            && self.s.get(self.i) == Some(&('\\' as u32))
                            && self.s.get(self.i + 1) == Some(&('u' as u32))
                        {
                            let save = self.i;
                            self.i += 2;
                            let lo = self.hex4()?;
                            if (0xDC00..0xE000).contains(&lo) {
                                cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                            } else {
                                self.i = save;
                            }
                        }
                        last_u_pos = Some(self.i - 5);
                        S::push_cp(&mut out, cp);
                    }
                    _ => {
                        self.i -= 1;
                        return Err(self.err_with_py(
                            "Invalid \\escape",
                            self.i,
                            "Invalid \\escape",
                            self.i - 1,
                        ));
                    }
                }
            } else if c < 0x20 {
                self.i -= 1;
                return Err(self.err("Invalid control character at"));
            } else {
                S::push_cp(&mut out, c);
            }
        }
    }
}

/// Options for [`dumps_with`], matching CPython's
/// `json.dumps(v, indent=..., ensure_ascii=..., separators=(item_sep, key_sep))`.
///
/// When `item_sep` is `None`, CPython's default applies: `","` when `indent`
/// is `Some(_)`, and `", "` when `indent` is `None`. When `key_sep` is
/// `None`, `": "` is used.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct DumpOptions {
    pub indent: Option<usize>,
    pub ensure_ascii: bool,
    pub item_sep: Option<&'static str>,
    pub key_sep: Option<&'static str>,
}

impl Default for DumpOptions {
    fn default() -> Self {
        Self {
            indent: None,
            ensure_ascii: true,
            item_sep: None,
            key_sep: None,
        }
    }
}

impl DumpOptions {
    /// Compact JSON matching `json.dumps(v, separators=(",", ":"))`.
    pub fn compact() -> Self {
        Self {
            indent: None,
            ensure_ascii: true,
            item_sep: Some(","),
            key_sep: Some(":"),
        }
    }
}

/// `json.dumps(value)` with its defaults: ", " and ": " separators,
/// non-ASCII escaped.
pub fn dumps(v: &Value) -> String {
    dumps_with(v, &DumpOptions::default())
}

/// `json.dumps(value, indent=..., ensure_ascii=..., separators=(...))`.
pub fn dumps_with(v: &Value, opts: &DumpOptions) -> String {
    let item_sep = opts
        .item_sep
        .unwrap_or(if opts.indent.is_some() { "," } else { ", " });
    let key_sep = opts.key_sep.unwrap_or(": ");
    let mut out = String::new();
    write_value(v, opts, item_sep, key_sep, 0, &mut out);
    out
}

fn write_indent(out: &mut String, indent: usize, level: usize) {
    out.push('\n');
    for _ in 0..indent.saturating_mul(level) {
        out.push(' ');
    }
}

fn write_value(
    v: &Value,
    opts: &DumpOptions,
    item_sep: &str,
    key_sep: &str,
    level: usize,
    out: &mut String,
) {
    match v {
        Value::Null => out.push_str("null"),
        Value::Bool(true) => out.push_str("true"),
        Value::Bool(false) => out.push_str("false"),
        Value::Int(s) => out.push_str(&normalize_int(s)),
        Value::Float(f) => {
            if f.is_nan() {
                out.push_str("NaN")
            } else if f.is_infinite() {
                out.push_str(if *f > 0.0 { "Infinity" } else { "-Infinity" })
            } else {
                out.push_str(&pystr::repr_float(*f))
            }
        }
        Value::Str(s) => write_str(s, opts.ensure_ascii, out),
        Value::Arr(items) => {
            if items.is_empty() {
                out.push_str("[]");
                return;
            }
            out.push('[');
            for (i, item) in items.iter().enumerate() {
                if i > 0 {
                    out.push_str(item_sep);
                }
                if let Some(n) = opts.indent {
                    write_indent(out, n, level + 1);
                }
                write_value(item, opts, item_sep, key_sep, level + 1, out);
            }
            if let Some(n) = opts.indent {
                write_indent(out, n, level);
            }
            out.push(']');
        }
        Value::Obj(items) => {
            if items.is_empty() {
                out.push_str("{}");
                return;
            }
            out.push('{');
            for (i, (k, item)) in dedup(items).iter().enumerate() {
                if i > 0 {
                    out.push_str(item_sep);
                }
                if let Some(n) = opts.indent {
                    write_indent(out, n, level + 1);
                }
                write_str(k, opts.ensure_ascii, out);
                out.push_str(key_sep);
                write_value(item, opts, item_sep, key_sep, level + 1, out);
            }
            if let Some(n) = opts.indent {
                write_indent(out, n, level);
            }
            out.push('}');
        }
    }
}

fn write_str(s: &str, ensure_ascii: bool, out: &mut String) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            c if (c as u32) < 0x20 || (ensure_ascii && (c as u32) > 0x7e) => {
                let cp = c as u32;
                if cp >= 0x10000 {
                    let v = cp - 0x10000;
                    out.push_str(&format!(
                        "\\u{:04x}\\u{:04x}",
                        0xD800 + (v >> 10),
                        0xDC00 + (v & 0x3FF)
                    ));
                } else {
                    out.push_str(&format!("\\u{:04x}", cp));
                }
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_python_extensions() {
        let v = loads(r#"{"a": NaN, "b": -Infinity, "a": 2, "n": 123456789012345678901234567890}"#)
            .unwrap();
        assert_eq!(v.get("a"), Some(&Value::Int("2".into())));
        assert_eq!(
            v.get("n").unwrap().py_repr(),
            "123456789012345678901234567890"
        );
        assert!(matches!(v.get("b"), Some(Value::Float(f)) if f.is_infinite()));
        assert!(loads("[1,]").is_err());
        assert!(loads("{} x").is_err());
        assert!(loads("").is_err());
    }

    #[test]
    fn strings_and_surrogates() {
        let v = loads(r#""\ud83d\ude00 \u00e9 \/""#).unwrap();
        assert_eq!(v, Value::Str("\u{1F600} \u{e9} /".into()));
        assert!(loads("\"a\nb\"").is_err());
    }

    #[test]
    fn repr_and_dumps() {
        let v = loads(r#"[{"message": "it's", "n": null, "t": true}, 1.0, -0]"#).unwrap();
        assert_eq!(
            v.py_repr(),
            r#"[{'message': "it's", 'n': None, 't': True}, 1.0, 0]"#
        );
        assert_eq!(
            dumps(&v),
            r#"[{"message": "it's", "n": null, "t": true}, 1.0, 0]"#
        );
        assert_eq!(
            dumps(&Value::Str("é\u{1F600}".into())),
            r#""\u00e9\ud83d\ude00""#
        );
    }

    #[test]
    fn truthiness() {
        assert!(!Value::Int("-0".into()).truthy());
        assert!(Value::Int("3".into()).truthy());
        assert!(!Value::Obj(vec![]).truthy());
        assert!(!Value::Str(String::new()).truthy());
    }

    #[test]
    fn python_equality() {
        let int = |s: &str| Value::Int(s.into());
        assert!(py_eq(&int("101"), &Value::Float(101.0)));
        assert!(py_eq(&int("1"), &Value::Bool(true)));
        assert!(py_eq(&int("0"), &Value::Bool(false)));
        assert!(py_eq(&int("-0"), &int("0")));
        assert!(!py_eq(&int("101"), &Value::Float(101.5)));
        assert!(!py_eq(&int("101"), &Value::Str("101".into())));
        assert!(!py_eq(&Value::Float(f64::NAN), &Value::Float(f64::NAN)));
        assert!(py_eq(&int("9007199254740993"), &int("9007199254740993")));
        // 2**53 + 1 is not a float; the nearest float is 2**53.
        assert!(!py_eq(
            &int("9007199254740993"),
            &Value::Float(9007199254740992.0)
        ));
        assert!(py_eq(
            &int("9007199254740992"),
            &Value::Float(9007199254740992.0)
        ));
        assert!(py_eq(&Value::Float(1e22), &int("10000000000000000000000")));
        let a = loads(r#"{"x": [1, 2.0], "y": "z"}"#).unwrap();
        let b = loads(r#"{"y": "z", "x": [1.0, 2]}"#).unwrap();
        assert!(py_eq(&a, &b));
        assert!(!py_eq(&a, &loads(r#"{"y": "z"}"#).unwrap()));
    }

    #[test]
    fn dumps_loads_round_trip() {
        let src = r#"{"z": [1, 1.0, -0.0, 1e+16, 1.5e-07], "a": "é\ud83d\ude00\t\n", "z": "last"}"#;
        let v = loads(src).unwrap();
        assert_eq!(v.py_repr(), "{'z': 'last', 'a': 'é😀\\t\\n'}");
        let dumped = dumps(&v);
        assert_eq!(dumped, r#"{"z": "last", "a": "\u00e9\ud83d\ude00\t\n"}"#);
        assert!(py_eq(&loads(&dumped).unwrap(), &v));
    }

    #[test]
    fn error_line_and_column() {
        let e1 = loads("").unwrap_err();
        assert_eq!((e1.line, e1.col, e1.pos), (1, 1, 0));
        assert_eq!(e1.to_string(), "Expecting value (char 0)");

        let e_lf = loads("[\n1,\n\"x\" 2]").unwrap_err();
        assert_eq!((e_lf.line, e_lf.col, e_lf.pos), (3, 5, 9));

        let e_crlf = loads("[\r\n1,\r\n\"x\" 2]").unwrap_err();
        assert_eq!((e_crlf.line, e_crlf.col, e_crlf.pos), (3, 5, 11));

        let e_mb = loads("[\"é\" 2]").unwrap_err();
        assert_eq!((e_mb.line, e_mb.col, e_mb.pos), (1, 6, 5));

        let e_mb_crlf = loads("[\r\n1,\r\n\"é\" 2]").unwrap_err();
        assert_eq!((e_mb_crlf.line, e_mb_crlf.col, e_mb_crlf.pos), (3, 5, 11));

        let e_astral = loads("[\"😀\" 2]").unwrap_err();
        assert_eq!((e_astral.line, e_astral.col, e_astral.pos), (1, 6, 5));

        let e_bom = loads("\u{feff}{}").unwrap_err();
        assert_eq!((e_bom.line, e_bom.col, e_bom.pos), (1, 1, 0));
        assert_eq!(
            e_bom.python_str(),
            "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)"
        );
        assert_eq!(
            e_bom.to_string(),
            "Unexpected UTF-8 BOM (decode using utf-8-sig) (char 0)"
        );
    }

    #[test]
    fn error_python_str_matches_cpython() {
        let cases = [
            // python3: json.loads("") -> Expecting value: line 1 column 1 (char 0)
            ("", "Expecting value: line 1 column 1 (char 0)"),
            // python3: json.loads("[1 2]") -> Expecting ',' delimiter: line 1 column 4 (char 3)
            ("[1 2]", "Expecting ',' delimiter: line 1 column 4 (char 3)"),
            // python3: json.loads("{") -> Expecting property name enclosed in double quotes: line 1 column 2 (char 1)
            (
                "{",
                "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)",
            ),
            // python3: json.loads('["abc') -> Unterminated string starting at: line 1 column 2 (char 1)
            (
                "[\"abc",
                "Unterminated string starting at: line 1 column 2 (char 1)",
            ),
            // python3: json.loads('"ab\\') -> Unterminated string starting at: line 1 column 1 (char 0)
            (
                "\"ab\\",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            // python3: json.loads("{} x") -> Extra data: line 1 column 4 (char 3)
            ("{} x", "Extra data: line 1 column 4 (char 3)"),
            // python3: json.loads('"a\nb"') -> Invalid control character at: line 1 column 3 (char 2)
            (
                "\"a\nb\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            // python3: json.loads('{"a" 1}') -> Expecting ':' delimiter: line 1 column 6 (char 5)
            (
                "{\"a\" 1}",
                "Expecting ':' delimiter: line 1 column 6 (char 5)",
            ),
            // python3: json.loads('"\\x"') -> Invalid \escape: line 1 column 2 (char 1)
            ("\"\\x\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            // python3: json.loads('"\\u12"') -> Invalid \uXXXX escape: line 1 column 3 (char 2)
            (
                "\"\\u12\"",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            // python3: json.loads('"\\ud800\\u12"') -> Invalid \uXXXX escape: line 1 column 9 (char 8)
            (
                "\"\\ud800\\u12\"",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            // python3: json.loads('{"a":\n tru}') -> Expecting value: line 2 column 2 (char 7)
            (
                "{\"a\":\n tru}",
                "Expecting value: line 2 column 2 (char 7)",
            ),
            // python3.12: json.loads('"\\u0041') -> Invalid \uXXXX escape: line 1 column 3 (char 2)
            (
                "\"\\u0041",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            // python3.12: json.loads('"ab\\u0041') -> Invalid \uXXXX escape: line 1 column 5 (char 4)
            (
                "\"ab\\u0041",
                "Invalid \\uXXXX escape: line 1 column 5 (char 4)",
            ),
            // python3.12: json.loads('"\\ud800\\u0041') -> Invalid \uXXXX escape: line 1 column 9 (char 8)
            (
                "\"\\ud800\\u0041",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            // python3.12: json.loads('"\\ud800\\udc00') -> Invalid \uXXXX escape: line 1 column 9 (char 8)
            (
                "\"\\ud800\\udc00",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            // python3.12: json.loads('"\\\\u0041') -> Unterminated string starting at: line 1 column 1 (char 0)
            (
                "\"\\\\u0041",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
        ];
        for (input, want) in cases {
            let err = loads(input).unwrap_err();
            assert_eq!(err.python_str(), want, "{input:?}");
            assert_eq!(err.to_string(), format!("{} (char {})", err.msg, err.pos));
        }
    }

    #[test]
    fn error_display_unchanged_for_existing_paths() {
        let cases = [
            (
                "\"\\x\"",
                "Invalid \\escape",
                2,
                "Invalid \\escape (char 2)",
                (1, 2),
                "Invalid \\escape: line 1 column 2 (char 1)",
            ),
            (
                "\"\\u12\"",
                "Invalid \\uXXXX escape",
                3,
                "Invalid \\uXXXX escape (char 3)",
                (1, 3),
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"\\u123g\"",
                "Invalid \\uXXXX escape",
                3,
                "Invalid \\uXXXX escape (char 3)",
                (1, 3),
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"\\ud800\\u12\"",
                "Invalid \\uXXXX escape",
                9,
                "Invalid \\uXXXX escape (char 9)",
                (1, 9),
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"ab\\",
                "Unterminated string",
                4,
                "Unterminated string (char 4)",
                (1, 1),
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "[\"abc",
                "Unterminated string starting at",
                5,
                "Unterminated string starting at (char 5)",
                (1, 2),
                "Unterminated string starting at: line 1 column 2 (char 1)",
            ),
            (
                "\"\\u0041",
                "Unterminated string starting at",
                7,
                "Unterminated string starting at (char 7)",
                (1, 3),
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"ab\\u0041",
                "Unterminated string starting at",
                9,
                "Unterminated string starting at (char 9)",
                (1, 5),
                "Invalid \\uXXXX escape: line 1 column 5 (char 4)",
            ),
            (
                "\"\\ud800\\u0041",
                "Unterminated string starting at",
                13,
                "Unterminated string starting at (char 13)",
                (1, 9),
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"\\ud800\\udc00",
                "Unterminated string starting at",
                13,
                "Unterminated string starting at (char 13)",
                (1, 9),
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
        ];
        for (input, old_msg, old_pos, old_display, (py_line, py_col), py_str) in cases {
            let err = loads(input).unwrap_err();
            assert_eq!(err.msg, old_msg, "{input:?}");
            assert_eq!(err.pos, old_pos, "{input:?}");
            assert_eq!(err.to_string(), old_display, "{input:?}");
            assert_eq!((err.line, err.col), (py_line, py_col), "{input:?}");
            assert_eq!(err.python_str(), py_str, "{input:?}");
        }
    }

    #[test]
    fn dumps_with_options() {
        let nested = loads(r#"{"a": [1, {"b": true, "c": null}], "e": {}, "f": []}"#).unwrap();
        assert_eq!(
            dumps_with(
                &nested,
                &DumpOptions {
                    indent: Some(2),
                    ..DumpOptions::default()
                }
            ),
            "{\n  \"a\": [\n    1,\n    {\n      \"b\": true,\n      \"c\": null\n    }\n  ],\n  \"e\": {},\n  \"f\": []\n}"
        );
        assert_eq!(
            dumps_with(
                &Value::Obj(vec![]),
                &DumpOptions {
                    indent: Some(2),
                    ..DumpOptions::default()
                }
            ),
            "{}"
        );
        assert_eq!(
            dumps_with(
                &Value::Arr(vec![]),
                &DumpOptions {
                    indent: Some(2),
                    ..DumpOptions::default()
                }
            ),
            "[]"
        );

        let shallow = loads(r#"{"a": [1, 2]}"#).unwrap();
        assert_eq!(
            dumps_with(
                &shallow,
                &DumpOptions {
                    indent: Some(0),
                    ..DumpOptions::default()
                }
            ),
            "{\n\"a\": [\n1,\n2\n]\n}"
        );
        assert_eq!(
            dumps_with(
                &shallow,
                &DumpOptions {
                    indent: Some(2),
                    item_sep: Some(", "),
                    key_sep: Some(": "),
                    ..DumpOptions::default()
                }
            ),
            "{\n  \"a\": [\n    1, \n    2\n  ]\n}"
        );

        let text = Value::Obj(vec![(
            "a".into(),
            Value::Str("é😀\n\u{0000}\u{007f}".into()),
        )]);
        assert_eq!(
            dumps_with(
                &text,
                &DumpOptions {
                    ensure_ascii: false,
                    ..DumpOptions::default()
                }
            ),
            "{\"a\": \"é😀\\n\\u0000\x7f\"}"
        );
        assert_eq!(
            dumps_with(
                &text,
                &DumpOptions {
                    ensure_ascii: true,
                    ..DumpOptions::default()
                }
            ),
            r#"{"a": "\u00e9\ud83d\ude00\n\u0000\u007f"}"#
        );

        let compact_val = loads(r#"{"a": [1, 2], "b": {"c": 3}}"#).unwrap();
        let want_compact = r#"{"a":[1,2],"b":{"c":3}}"#;
        assert_eq!(
            dumps_with(&compact_val, &DumpOptions::compact()),
            want_compact
        );
        assert_eq!(
            dumps_with(
                &compact_val,
                &DumpOptions {
                    indent: None,
                    ensure_ascii: true,
                    item_sep: Some(","),
                    key_sep: Some(":"),
                }
            ),
            want_compact
        );
    }

    #[test]
    fn dumps_default_unchanged() {
        let v = Value::Obj(vec![
            ("z".into(), Value::Int("-0".into())),
            (
                "a".into(),
                Value::Arr(vec![
                    Value::Null,
                    Value::Bool(true),
                    Value::Bool(false),
                    Value::Int("123456789012345678901234567890".into()),
                    Value::Float(1.0),
                    Value::Float(-0.0),
                    Value::Float(1e16),
                    Value::Float(1.5e-7),
                    Value::Float(f64::NAN),
                    Value::Float(f64::INFINITY),
                    Value::Float(f64::NEG_INFINITY),
                    Value::Str("é\u{1F600}\t\n\"\\".into()),
                    Value::Obj(vec![]),
                    Value::Arr(vec![]),
                ]),
            ),
            ("z".into(), Value::Str("last".into())),
        ]);
        let pinned = r#"{"z": "last", "a": [null, true, false, 123456789012345678901234567890, 1.0, -0.0, 1e+16, 1.5e-07, NaN, Infinity, -Infinity, "\u00e9\ud83d\ude00\t\n\"\\", {}, []]}"#;
        assert_eq!(dumps(&v), pinned);
        assert_eq!(dumps_with(&v, &DumpOptions::default()), pinned);
    }

    #[test]
    fn loads_with_max_depth_boundary_900() {
        let handle = std::thread::Builder::new()
            .stack_size(32 * 1024 * 1024)
            .spawn(|| {
                let opts = LoadOptions {
                    max_depth: Some(900),
                };
                let ok_empty = format!("{}{}", "[".repeat(900), "]".repeat(900));
                assert!(loads_with(&ok_empty, &opts).is_ok());

                let ok_scalar = format!("{}1{}", "[".repeat(900), "]".repeat(900));
                assert!(loads_with(&ok_scalar, &opts).is_ok());

                let ok_siblings = format!("{}[],{}{}", "[".repeat(899), "{}", "]".repeat(899));
                assert!(loads_with(&ok_siblings, &opts).is_ok());

                let fail_unclosed = "[".repeat(901);
                let err = loads_with(&fail_unclosed, &opts).unwrap_err();
                assert_eq!(
                    err.python_str(),
                    "maximum recursion depth exceeded: line 1 column 901 (char 900)"
                );
                assert_eq!(
                    err.to_string(),
                    "maximum recursion depth exceeded (char 900)"
                );
                assert_eq!((err.line, err.col, err.pos), (1, 901, 900));

                let fail_empty = format!("{}{}", "[".repeat(901), "]".repeat(901));
                let err_closed = loads_with(&fail_empty, &opts).unwrap_err();
                assert_eq!(
                    err_closed.python_str(),
                    "maximum recursion depth exceeded: line 1 column 901 (char 900)"
                );

                let zero_opts = LoadOptions { max_depth: Some(0) };
                assert!(loads_with("1", &zero_opts).is_ok());
                assert!(loads_with(r#""hi""#, &zero_opts).is_ok());
                assert!(loads_with("null", &zero_opts).is_ok());
                for container in ["[]", "{}"] {
                    let err_zero = loads_with(container, &zero_opts).unwrap_err();
                    assert_eq!(
                        err_zero.python_str(),
                        "maximum recursion depth exceeded: line 1 column 1 (char 0)"
                    );
                }
            })
            .unwrap();
        handle.join().unwrap();
    }

    #[test]
    fn loads_with_max_depth_mixed_containers() {
        let handle = std::thread::Builder::new()
            .stack_size(32 * 1024 * 1024)
            .spawn(|| {
                fn mixed_chain(depth: usize, start_obj: bool) -> String {
                    let mut out = String::new();
                    for k in 0..depth {
                        if (k % 2 == 0) == start_obj {
                            out.push_str(r#"{"a":"#);
                        } else {
                            out.push('[');
                        }
                    }
                    out.push('0');
                    for k in (0..depth).rev() {
                        if (k % 2 == 0) == start_obj {
                            out.push('}');
                        } else {
                            out.push(']');
                        }
                    }
                    out
                }

                let opts = LoadOptions {
                    max_depth: Some(900),
                };
                for start_obj in [false, true] {
                    let ok_doc = mixed_chain(900, start_obj);
                    assert!(loads_with(&ok_doc, &opts).is_ok());

                    let fail_doc = mixed_chain(901, start_obj);
                    let err = loads_with(&fail_doc, &opts).unwrap_err();
                    assert_eq!(err.msg, "maximum recursion depth exceeded");
                }

                let err_small =
                    loads_with(r#"[{"a":{}}]"#, &LoadOptions { max_depth: Some(2) }).unwrap_err();
                assert_eq!(
                    err_small.python_str(),
                    "maximum recursion depth exceeded: line 1 column 7 (char 6)"
                );
            })
            .unwrap();
        handle.join().unwrap();
    }

    #[test]
    fn loads_with_max_depth_error_line_and_column() {
        let handle = std::thread::Builder::new()
            .stack_size(32 * 1024 * 1024)
            .spawn(|| {
                let doc = format!("{}\n[", "[".repeat(900));
                let err = loads_with(
                    &doc,
                    &LoadOptions {
                        max_depth: Some(900),
                    },
                )
                .unwrap_err();
                assert_eq!(
                    err.python_str(),
                    "maximum recursion depth exceeded: line 2 column 1 (char 901)"
                );
                assert_eq!((err.line, err.col, err.pos), (2, 1, 901));

                let mb_err = loads_with("{\"é\":\n  [[]]}", &LoadOptions { max_depth: Some(2) })
                    .unwrap_err();
                assert_eq!(
                    mb_err.python_str(),
                    "maximum recursion depth exceeded: line 2 column 4 (char 9)"
                );
                assert_eq!((mb_err.line, mb_err.col, mb_err.pos), (2, 4, 9));
            })
            .unwrap();
        handle.join().unwrap();
    }

    #[test]
    fn loads_default_accepts_depth_5000() {
        assert_eq!(LoadOptions::default(), LoadOptions { max_depth: None });
        // Unoptimized test threads default to a 2 MiB stack; give the recursive
        // parser and Value::drop enough stack to walk 5,000 levels.
        let handle = std::thread::Builder::new()
            .stack_size(32 * 1024 * 1024)
            .spawn(|| {
                let doc = format!("{}{}", "[".repeat(5_000), "]".repeat(5_000));
                let v = loads(&doc);
                assert!(matches!(v, Ok(Value::Arr(_))));
                drop(v);
            })
            .unwrap();
        handle.join().unwrap();
    }

    #[test]
    fn existing_display_python_str_and_dumps_pinned() {
        let e1 = loads("[1 2]").unwrap_err();
        assert_eq!(e1.to_string(), "Expecting ',' delimiter (char 3)");
        assert_eq!(
            e1.python_str(),
            "Expecting ',' delimiter: line 1 column 4 (char 3)"
        );

        let e2 = loads("").unwrap_err();
        assert_eq!(e2.to_string(), "Expecting value (char 0)");
        assert_eq!(e2.python_str(), "Expecting value: line 1 column 1 (char 0)");

        let e3 = loads(r#""\x""#).unwrap_err();
        assert_eq!(e3.to_string(), "Invalid \\escape (char 2)");
        assert_eq!(
            e3.python_str(),
            "Invalid \\escape: line 1 column 2 (char 1)"
        );

        let v = loads(r#"{"b": [1, 2.0, "é"], "a": null}"#).unwrap();
        assert_eq!(dumps(&v), r#"{"b": [1, 2.0, "\u00e9"], "a": null}"#);
    }

    fn bs(template: &str) -> String {
        const BS: char = '\\';
        assert!(
            !template.contains(BS),
            "build escapes in code with '|' instead of literal backslashes: {template:?}"
        );
        template.replace('|', &BS.to_string())
    }

    /// Test-only copy of the pre-refactor recursive parser from `origin/main`
    /// (`8426c71bd`) for differential testing against the new iterative parser.
    mod legacy_recursive_parser {
        use super::{LoadOptions, Value};

        #[derive(Debug, Clone, PartialEq, Eq)]
        pub struct LegacyJsonError {
            pub msg: String,
            pub pos: usize,
            pub line: usize,
            pub col: usize,
            py_msg: String,
            py_pos: usize,
        }

        impl LegacyJsonError {
            pub fn python_str(&self) -> String {
                format!(
                    "{}: line {} column {} (char {})",
                    self.py_msg, self.line, self.col, self.py_pos
                )
            }
        }

        impl std::fmt::Display for LegacyJsonError {
            fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                write!(f, "{} (char {})", self.msg, self.pos)
            }
        }

        fn locate(chars: &[char], mut e: LegacyJsonError) -> LegacyJsonError {
            let before = &chars[..e.py_pos.min(chars.len())];
            e.line = before.iter().filter(|c| **c == '\n').count() + 1;
            e.col = match before.iter().rposition(|c| *c == '\n') {
                Some(nl) => e.py_pos - nl,
                None => e.py_pos + 1,
            };
            e
        }

        pub fn loads_with(text: &str, opts: &LoadOptions) -> Result<Value, LegacyJsonError> {
            let chars: Vec<char> = text.chars().collect();
            if text.starts_with('\u{feff}') {
                let msg = "Unexpected UTF-8 BOM (decode using utf-8-sig)";
                return Err(locate(
                    &chars,
                    LegacyJsonError {
                        msg: msg.into(),
                        pos: 0,
                        line: 0,
                        col: 0,
                        py_msg: msg.into(),
                        py_pos: 0,
                    },
                ));
            }
            let mut p = Parser {
                s: &chars,
                i: 0,
                max_depth: opts.max_depth,
                depth: 0,
            };
            let parsed = (|| {
                p.ws();
                let v = p.value()?;
                p.ws();
                if p.i != chars.len() {
                    return Err(p.err("Extra data"));
                }
                Ok(v)
            })();
            parsed.map_err(|e| locate(&chars, e))
        }

        struct Parser<'a> {
            s: &'a [char],
            i: usize,
            max_depth: Option<usize>,
            depth: usize,
        }

        impl<'a> Parser<'a> {
            fn err(&self, msg: &str) -> LegacyJsonError {
                self.err_with_py(msg, self.i, msg, self.i)
            }

            fn err_with_py(
                &self,
                msg: &str,
                pos: usize,
                py_msg: &str,
                py_pos: usize,
            ) -> LegacyJsonError {
                LegacyJsonError {
                    msg: msg.into(),
                    pos,
                    line: 0,
                    col: 0,
                    py_msg: py_msg.into(),
                    py_pos,
                }
            }

            fn enter(&mut self) -> Result<(), LegacyJsonError> {
                if let Some(max) = self.max_depth {
                    if self.depth >= max {
                        return Err(self.err_with_py(
                            "maximum recursion depth exceeded",
                            self.i,
                            "maximum recursion depth exceeded",
                            self.i,
                        ));
                    }
                }
                self.depth += 1;
                Ok(())
            }

            fn peek(&self) -> Option<char> {
                self.s.get(self.i).copied()
            }

            fn ws(&mut self) {
                while matches!(self.peek(), Some(' ' | '\t' | '\n' | '\r')) {
                    self.i += 1;
                }
            }

            fn lit(&mut self, word: &str) -> bool {
                let w: Vec<char> = word.chars().collect();
                if self.s.len() >= self.i + w.len() && self.s[self.i..self.i + w.len()] == w[..] {
                    self.i += w.len();
                    true
                } else {
                    false
                }
            }

            fn value(&mut self) -> Result<Value, LegacyJsonError> {
                match self.peek() {
                    Some('{') => {
                        self.enter()?;
                        let r = self.object();
                        self.depth -= 1;
                        r
                    }
                    Some('[') => {
                        self.enter()?;
                        let r = self.array();
                        self.depth -= 1;
                        r
                    }
                    Some('"') => {
                        self.i += 1;
                        Ok(Value::Str(self.string()?))
                    }
                    Some('n') if self.lit("null") => Ok(Value::Null),
                    Some('t') if self.lit("true") => Ok(Value::Bool(true)),
                    Some('f') if self.lit("false") => Ok(Value::Bool(false)),
                    Some('N') if self.lit("NaN") => Ok(Value::Float(f64::NAN)),
                    Some('I') if self.lit("Infinity") => Ok(Value::Float(f64::INFINITY)),
                    Some('-') if self.s.get(self.i + 1) == Some(&'I') && self.lit("-Infinity") => {
                        Ok(Value::Float(f64::NEG_INFINITY))
                    }
                    Some(c) if c == '-' || c.is_ascii_digit() => self.number(),
                    _ => Err(self.err("Expecting value")),
                }
            }

            fn number(&mut self) -> Result<Value, LegacyJsonError> {
                let start = self.i;
                if self.peek() == Some('-') {
                    self.i += 1;
                }
                match self.peek() {
                    Some('0') => self.i += 1,
                    Some(c) if c.is_ascii_digit() => {
                        while matches!(self.peek(), Some(c) if c.is_ascii_digit()) {
                            self.i += 1;
                        }
                    }
                    _ => {
                        self.i = start;
                        return Err(self.err("Expecting value"));
                    }
                }
                let mut is_float = false;
                if self.peek() == Some('.')
                    && matches!(self.s.get(self.i + 1), Some(c) if c.is_ascii_digit())
                {
                    is_float = true;
                    self.i += 1;
                    while matches!(self.peek(), Some(c) if c.is_ascii_digit()) {
                        self.i += 1;
                    }
                }
                if matches!(self.peek(), Some('e' | 'E')) {
                    let save = self.i;
                    self.i += 1;
                    if matches!(self.peek(), Some('+' | '-')) {
                        self.i += 1;
                    }
                    if matches!(self.peek(), Some(c) if c.is_ascii_digit()) {
                        is_float = true;
                        while matches!(self.peek(), Some(c) if c.is_ascii_digit()) {
                            self.i += 1;
                        }
                    } else {
                        self.i = save;
                    }
                }
                let text: String = self.s[start..self.i].iter().collect();
                if is_float {
                    Ok(Value::Float(text.parse::<f64>().unwrap_or(f64::NAN)))
                } else {
                    Ok(Value::Int(text))
                }
            }

            fn hex4(&mut self) -> Result<u32, LegacyJsonError> {
                if self.i + 4 > self.s.len() {
                    return Err(self.err_with_py(
                        "Invalid \\uXXXX escape",
                        self.i,
                        "Invalid \\uXXXX escape",
                        self.i - 1,
                    ));
                }
                let h: String = self.s[self.i..self.i + 4].iter().collect();
                if !h.chars().all(|c| c.is_ascii_hexdigit()) {
                    return Err(self.err_with_py(
                        "Invalid \\uXXXX escape",
                        self.i,
                        "Invalid \\uXXXX escape",
                        self.i - 1,
                    ));
                }
                self.i += 4;
                Ok(u32::from_str_radix(&h, 16).unwrap())
            }

            fn string(&mut self) -> Result<String, LegacyJsonError> {
                let start = self.i - 1;
                let mut out = String::new();
                let mut last_u_pos: Option<usize> = None;
                loop {
                    let c = match self.peek() {
                        None => {
                            let (py_msg, py_pos) = match last_u_pos {
                                Some(u_pos) => ("Invalid \\uXXXX escape", u_pos),
                                None => ("Unterminated string starting at", start),
                            };
                            return Err(self.err_with_py(
                                "Unterminated string starting at",
                                self.i,
                                py_msg,
                                py_pos,
                            ));
                        }
                        Some(c) => c,
                    };
                    last_u_pos = None;
                    self.i += 1;
                    match c {
                        '"' => return Ok(out),
                        '\\' => {
                            let e = self.peek().ok_or_else(|| {
                                self.err_with_py(
                                    "Unterminated string",
                                    self.i,
                                    "Unterminated string starting at",
                                    start,
                                )
                            })?;
                            self.i += 1;
                            match e {
                                '"' => out.push('"'),
                                '\\' => out.push('\\'),
                                '/' => out.push('/'),
                                'b' => out.push('\u{8}'),
                                'f' => out.push('\u{c}'),
                                'n' => out.push('\n'),
                                'r' => out.push('\r'),
                                't' => out.push('\t'),
                                'u' => {
                                    let mut cp = self.hex4()?;
                                    if (0xD800..0xDC00).contains(&cp)
                                        && self.s.get(self.i) == Some(&'\\')
                                        && self.s.get(self.i + 1) == Some(&'u')
                                    {
                                        let save = self.i;
                                        self.i += 2;
                                        let lo = self.hex4()?;
                                        if (0xDC00..0xE000).contains(&lo) {
                                            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                                        } else {
                                            self.i = save;
                                        }
                                    }
                                    last_u_pos = Some(self.i - 5);
                                    out.push(char::from_u32(cp).unwrap_or('\u{fffd}'));
                                }
                                _ => {
                                    self.i -= 1;
                                    return Err(self.err_with_py(
                                        "Invalid \\escape",
                                        self.i,
                                        "Invalid \\escape",
                                        self.i - 1,
                                    ));
                                }
                            }
                        }
                        c if (c as u32) < 0x20 => {
                            self.i -= 1;
                            return Err(self.err("Invalid control character at"));
                        }
                        c => out.push(c),
                    }
                }
            }

            fn array(&mut self) -> Result<Value, LegacyJsonError> {
                self.i += 1;
                let mut items = Vec::new();
                self.ws();
                if self.peek() == Some(']') {
                    self.i += 1;
                    return Ok(Value::Arr(items));
                }
                loop {
                    self.ws();
                    items.push(self.value()?);
                    self.ws();
                    match self.peek() {
                        Some(',') => self.i += 1,
                        Some(']') => {
                            self.i += 1;
                            return Ok(Value::Arr(items));
                        }
                        _ => return Err(self.err("Expecting ',' delimiter")),
                    }
                }
            }

            fn object(&mut self) -> Result<Value, LegacyJsonError> {
                self.i += 1;
                let mut items: Vec<(String, Value)> = Vec::new();
                self.ws();
                if self.peek() == Some('}') {
                    self.i += 1;
                    return Ok(Value::Obj(items));
                }
                loop {
                    self.ws();
                    if self.peek() != Some('"') {
                        return Err(self.err("Expecting property name enclosed in double quotes"));
                    }
                    self.i += 1;
                    let key = self.string()?;
                    self.ws();
                    if self.peek() != Some(':') {
                        return Err(self.err("Expecting ':' delimiter"));
                    }
                    self.i += 1;
                    self.ws();
                    let v = self.value()?;
                    if let Some(slot) = items.iter_mut().find(|(k, _)| *k == key) {
                        slot.1 = v;
                    } else {
                        items.push((key, v));
                    }
                    self.ws();
                    match self.peek() {
                        Some(',') => self.i += 1,
                        Some('}') => {
                            self.i += 1;
                            return Ok(Value::Obj(items));
                        }
                        _ => return Err(self.err("Expecting ',' delimiter")),
                    }
                }
            }
        }
    }

    struct SplitMix64(u64);

    impl SplitMix64 {
        fn next(&mut self) -> u64 {
            self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
            let mut z = self.0;
            z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
            z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
            z ^ (z >> 31)
        }

        fn bound(&mut self, n: usize) -> usize {
            (self.next() as usize) % n
        }
    }

    fn rand_ws(rng: &mut SplitMix64, out: &mut String) {
        let count = rng.bound(3);
        for _ in 0..count {
            match rng.bound(5) {
                0 => out.push(' '),
                1 => out.push('\t'),
                2 => out.push('\n'),
                3 => out.push('\r'),
                _ => out.push_str("\r\n"),
            }
        }
    }

    fn rand_string_literal(rng: &mut SplitMix64, out: &mut String) {
        const BS: char = '\\';
        let tokens: &[&str] = &[
            "",
            "a",
            "k",
            "dup",
            "key",
            "hello",
            "é",
            "😀",
            "日本語",
            "|\"",
            "||",
            "|/",
            "|b",
            "|f",
            "|n",
            "|r",
            "|t",
            "|u0041",
            "|u00e9",
            "|ud83d|ude00",
            "|ud800",
            "|udc00",
            "|ud800|u0041",
            "|ud800|ud83d|ude00",
            "|udfff|ud800",
            "it's",
        ];
        out.push('"');
        let pieces = rng.bound(5);
        for _ in 0..pieces {
            let tok = tokens[rng.bound(tokens.len())].replace('|', &BS.to_string());
            out.push_str(&tok);
        }
        out.push('"');
    }

    fn rand_scalar(rng: &mut SplitMix64, out: &mut String) {
        let big_ints = [
            "0",
            "-0",
            "1",
            "-1",
            "42",
            "-999999999999999999",
            "170141183460469231731687303715884105728",
            "-170141183460469231731687303715884105729",
            "12345678901234567890123456789012345678901234567890",
        ];
        let floats = [
            "0.0",
            "-0.0",
            "1.0",
            "123.456",
            "1e5",
            "1E-07",
            "1.5e+16",
            "1e400",
            "-1e400",
            "5e-324",
            "NaN",
            "Infinity",
            "-Infinity",
        ];
        match rng.bound(6) {
            0 => out.push_str("null"),
            1 => out.push_str(if rng.bound(2) == 0 { "true" } else { "false" }),
            2 => out.push_str(big_ints[rng.bound(big_ints.len())]),
            3 => out.push_str(floats[rng.bound(floats.len())]),
            4 => rand_string_literal(rng, out),
            _ => {
                // Multi-digit generated integer > i128.
                let len = 39 + rng.bound(25);
                if rng.bound(2) == 0 {
                    out.push('-');
                }
                out.push(char::from(b'1' + rng.bound(9) as u8));
                for _ in 1..len {
                    out.push(char::from(b'0' + rng.bound(10) as u8));
                }
            }
        }
    }

    fn gen_valid_doc(rng: &mut SplitMix64, depth: usize, max_depth: usize, out: &mut String) {
        if depth >= max_depth || (depth > 0 && rng.bound(5) == 0) {
            rand_scalar(rng, out);
            return;
        }
        match rng.bound(3) {
            0 => rand_scalar(rng, out),
            1 => {
                out.push('[');
                rand_ws(rng, out);
                let n = rng.bound(4);
                for idx in 0..n {
                    if idx > 0 {
                        rand_ws(rng, out);
                        out.push(',');
                        rand_ws(rng, out);
                    }
                    gen_valid_doc(rng, depth + 1, max_depth, out);
                }
                rand_ws(rng, out);
                out.push(']');
            }
            _ => {
                out.push('{');
                rand_ws(rng, out);
                let n = rng.bound(4);
                for idx in 0..n {
                    if idx > 0 {
                        rand_ws(rng, out);
                        out.push(',');
                        rand_ws(rng, out);
                    }
                    if idx > 0 && rng.bound(3) == 0 {
                        // Force duplicate keys.
                        out.push_str("\"dup\"");
                    } else {
                        rand_string_literal(rng, out);
                    }
                    rand_ws(rng, out);
                    out.push(':');
                    rand_ws(rng, out);
                    gen_valid_doc(rng, depth + 1, max_depth, out);
                }
                rand_ws(rng, out);
                out.push('}');
            }
        }
    }

    fn gen_malformed_doc(rng: &mut SplitMix64, valid_seed: &str) -> String {
        const BS: char = '\\';
        let chars: Vec<char> = valid_seed.chars().collect();
        match rng.bound(11) {
            0 => {
                // Random truncation.
                let k = rng.bound(chars.len().max(1));
                chars[..k].iter().collect()
            }
            1 => {
                // Prepend UTF-8 BOM.
                format!("\u{feff}{valid_seed}")
            }
            2 => {
                // Trailing extra data.
                let tail = [" x", " 1", " []", " {}", ","][rng.bound(5)];
                format!("{valid_seed}{tail}")
            }
            3 => {
                // Bad escape or truncated \uXXXX at EOF.
                let bad = [
                    "\"|x\"",
                    "\"|q\"",
                    "\"|0\"",
                    "\"|u12\"",
                    "\"|u123g\"",
                    "\"|ud800|u12\"",
                    "\"|u0041",
                    "\"ab|u0041",
                    "\"|ud800|u0041",
                    "\"|ud800|udc00",
                    "\"||u0041",
                    "\"ab|",
                ];
                bad[rng.bound(bad.len())].replace('|', &BS.to_string())
            }
            4 => {
                // Unescaped control character inside string.
                let ctrl = char::from_u32(rng.bound(0x20) as u32).unwrap();
                format!("\"a{ctrl}b\"")
            }
            5 => {
                // Trailing comma or missing delimiter.
                let fixed = [
                    "[1,]",
                    "{\"a\": 1,}",
                    "[1 2]",
                    "{\"a\" 1}",
                    "{\"a\": 1 \"b\": 2}",
                    "[,]",
                    "{,}",
                    "{1: 2}",
                    "{\"a\":}",
                ];
                fixed[rng.bound(fixed.len())].to_string()
            }
            6 => {
                // Invalid numbers / literals.
                let fixed = [
                    "-", "-a", "-I", "-Inf", "01", "-01", "1.", "1e", "1e+", "1e-", ".5", "+1",
                    "tru", "nul", "fals", "Na", "Inf", "nan", "True", "False", "Null",
                ];
                fixed[rng.bound(fixed.len())].to_string()
            }
            7 if !chars.is_empty() => {
                // Random single-char mutation.
                let mut mutated = chars;
                let idx = rng.bound(mutated.len());
                let repl = [
                    '{', '}', '[', ']', ':', ',', '"', BS, '\n', 'x', '0', '\u{0001}',
                ][rng.bound(12)];
                mutated[idx] = repl;
                mutated.into_iter().collect()
            }
            8 if !chars.is_empty() => {
                // Random char insertion.
                let mut mutated = chars;
                let idx = rng.bound(mutated.len() + 1);
                let ins = ['{', '}', '[', ']', ':', ',', '"', BS, '\x07', ' '][rng.bound(10)];
                mutated.insert(idx, ins);
                mutated.into_iter().collect()
            }
            9 if chars.len() > 1 => {
                // Random char deletion.
                let mut mutated = chars;
                let idx = rng.bound(mutated.len());
                mutated.remove(idx);
                mutated.into_iter().collect()
            }
            _ => {
                // Unclosed deep chain.
                let d = 1 + rng.bound(45);
                let mut s = String::new();
                for k in 0..d {
                    if k % 2 == 0 {
                        s.push('[');
                    } else {
                        s.push_str("{\"k\":");
                    }
                }
                s
            }
        }
    }

    fn contains_nan(v: &Value) -> bool {
        match v {
            Value::Float(f) => f.is_nan(),
            Value::Arr(items) => items.iter().any(contains_nan),
            Value::Obj(items) => items.iter().any(|(_, val)| contains_nan(val)),
            _ => false,
        }
    }

    fn values_bit_equal(a: &Value, b: &Value) -> bool {
        match (a, b) {
            (Value::Null, Value::Null) => true,
            (Value::Bool(x), Value::Bool(y)) => x == y,
            (Value::Int(x), Value::Int(y)) => x == y,
            (Value::Float(x), Value::Float(y)) => x.to_bits() == y.to_bits(),
            (Value::Str(x), Value::Str(y)) => x == y,
            (Value::Arr(x), Value::Arr(y)) => {
                x.len() == y.len() && x.iter().zip(y).all(|(p, q)| values_bit_equal(p, q))
            }
            (Value::Obj(x), Value::Obj(y)) => {
                x.len() == y.len()
                    && x.iter()
                        .zip(y)
                        .all(|((kx, vx), (ky, vy))| kx == ky && values_bit_equal(vx, vy))
            }
            _ => false,
        }
    }

    fn cp_str_to_utf8(cps: &[u32]) -> String {
        cps.iter()
            .map(|&cp| char::from_u32(cp).unwrap_or('\u{fffd}'))
            .collect()
    }

    fn cp_value_to_lossy(v: &CodepointValue) -> Value {
        match v {
            CodepointValue::Null => Value::Null,
            CodepointValue::Bool(b) => Value::Bool(*b),
            CodepointValue::Int(s) => Value::Int(s.clone()),
            CodepointValue::Float(f) => Value::Float(*f),
            CodepointValue::Str(cps) => Value::Str(cp_str_to_utf8(cps)),
            CodepointValue::Arr(items) => Value::Arr(items.iter().map(cp_value_to_lossy).collect()),
            CodepointValue::Obj(items) => Value::Obj(
                items
                    .iter()
                    .map(|(k, val)| (cp_str_to_utf8(k), cp_value_to_lossy(val)))
                    .collect(),
            ),
        }
    }

    fn assert_differential_case(
        input: &str,
        opts: &LoadOptions,
        check_int_limit: bool,
        valid_count: &mut usize,
        malformed_count: &mut usize,
        mismatch_count: &mut usize,
    ) {
        let old_res = legacy_recursive_parser::loads_with(input, opts);
        let new_res = loads_with(input, opts);
        let lim_no_int_res = loads_with_limits(input, opts.max_depth, None);
        let lim_int_res = if check_int_limit {
            Some(loads_with_limits(
                input,
                opts.max_depth,
                Some(DEFAULT_INT_MAX_STR_DIGITS),
            ))
        } else {
            None
        };
        let cps: Vec<u32> = input.chars().map(|c| c as u32).collect();
        let cp_opts = CodepointLoadOptions {
            max_depth: opts.max_depth,
            max_int_digits: None,
        };
        let cp_res = loads_codepoints(&cps, &cp_opts);

        match (old_res, new_res) {
            (Ok(old_v), Ok(new_v)) => {
                *valid_count += 1;
                if !values_bit_equal(&old_v, &new_v) {
                    *mismatch_count += 1;
                }
                assert!(
                    values_bit_equal(&old_v, &new_v),
                    "value mismatch on input {input:?} opts={opts:?}: old={old_v:?} new={new_v:?}"
                );
                let lim_v = lim_no_int_res.unwrap_or_else(|e| {
                    panic!("loads_with_limits(..., None) failed when loads_with succeeded on {input:?}: {e:?}")
                });
                assert!(
                    values_bit_equal(&new_v, &lim_v),
                    "loads_with_limits(..., None) value mismatch on {input:?}"
                );
                if let Some(res) = lim_int_res {
                    let lim_int_v = res.unwrap_or_else(|e| {
                        panic!("loads_with_limits(..., Some(DEFAULT_INT_MAX_STR_DIGITS)) failed on {input:?}: {e:?}")
                    });
                    assert!(
                        values_bit_equal(&new_v, &lim_int_v),
                        "loads_with_limits(..., Some(4300)) value mismatch on {input:?}"
                    );
                }
                assert_eq!(
                    format!("{old_v:?}"),
                    format!("{new_v:?}"),
                    "debug mismatch on {input:?}"
                );
                assert_eq!(
                    old_v.py_str(),
                    new_v.py_str(),
                    "py_str mismatch on {input:?}"
                );
                assert_eq!(
                    old_v.py_repr(),
                    new_v.py_repr(),
                    "py_repr mismatch on {input:?}"
                );
                assert_eq!(dumps(&old_v), dumps(&new_v), "dumps mismatch on {input:?}");
                assert_eq!(
                    dumps_with(&old_v, &DumpOptions::compact()),
                    dumps_with(&new_v, &DumpOptions::compact()),
                    "compact dumps mismatch on {input:?}"
                );
                let pretty = DumpOptions {
                    indent: Some(2),
                    ensure_ascii: false,
                    ..DumpOptions::default()
                };
                assert_eq!(
                    dumps_with(&old_v, &pretty),
                    dumps_with(&new_v, &pretty),
                    "pretty dumps mismatch on {input:?}"
                );
                if !contains_nan(&old_v) {
                    assert!(py_eq(&old_v, &new_v), "py_eq mismatch on {input:?}");
                } else {
                    assert!(!py_eq(&old_v, &new_v), "NaN py_eq mismatch on {input:?}");
                }
                let cp_v = cp_res.unwrap_or_else(|e| {
                    panic!("loads_codepoints failed when loads succeeded on {input:?}: {e:?}")
                });
                let lossy = cp_value_to_lossy(&cp_v);
                assert!(
                    values_bit_equal(&new_v, &lossy),
                    "codepoint lossy mismatch on {input:?}: new={new_v:?} cp_lossy={lossy:?}"
                );
            }
            (Err(old_e), Err(new_e)) => {
                *malformed_count += 1;
                let same = old_e.msg == new_e.msg
                    && old_e.pos == new_e.pos
                    && old_e.line == new_e.line
                    && old_e.col == new_e.col
                    && old_e.to_string() == new_e.to_string()
                    && old_e.python_str() == new_e.python_str();
                if !same {
                    *mismatch_count += 1;
                }
                assert_eq!(old_e.msg, new_e.msg, "err.msg mismatch on {input:?}");
                assert_eq!(old_e.pos, new_e.pos, "err.pos mismatch on {input:?}");
                assert_eq!(old_e.line, new_e.line, "err.line mismatch on {input:?}");
                assert_eq!(old_e.col, new_e.col, "err.col mismatch on {input:?}");
                assert_eq!(
                    old_e.to_string(),
                    new_e.to_string(),
                    "err Display mismatch on {input:?}"
                );
                assert_eq!(
                    old_e.python_str(),
                    new_e.python_str(),
                    "err.python_str() mismatch on {input:?}"
                );
                if old_e.msg == "maximum recursion depth exceeded" {
                    assert_eq!(new_e.kind(), JsonErrorKind::Recursion, "{input:?}");
                    assert!(new_e.recursion_message().is_some(), "{input:?}");
                } else {
                    assert_eq!(new_e.kind(), JsonErrorKind::Decode, "{input:?}");
                    assert_eq!(new_e.recursion_message(), None, "{input:?}");
                }
                assert_eq!(
                    lim_no_int_res.unwrap_err(),
                    new_e,
                    "loads_with_limits(..., None) error mismatch on {input:?}"
                );
                if let Some(res) = lim_int_res {
                    assert_eq!(
                        res.unwrap_err(),
                        new_e,
                        "loads_with_limits(..., Some(4300)) error mismatch on {input:?}"
                    );
                }
                let cp_e = cp_res.unwrap_err();
                assert_eq!(
                    cp_e.python_str(),
                    new_e.python_str(),
                    "cp_e.python_str() mismatch on {input:?}"
                );
                assert_eq!(
                    cp_e.to_string(),
                    new_e.to_string(),
                    "cp_e.to_string() mismatch on {input:?}"
                );
            }
            (old_r, new_r) => {
                *mismatch_count += 1;
                panic!(
                    "accept/reject mismatch on input {input:?} opts={opts:?}: old={old_r:?} new={new_r:?}"
                );
            }
        }
    }

    #[test]
    fn differential_against_legacy_recursive_parser() {
        let mut rng = SplitMix64(0x5EED_C0DE_2026_1122);
        let mut total = 0usize;
        let mut valid = 0usize;
        let mut malformed = 0usize;
        let mut mismatches = 0usize;

        // 1. Targeted edge-case corpus covering scalars, escapes, surrogates, BOM, dup keys.
        let edge_templates = [
            "",
            " ",
            "\n\t\r  ",
            "\u{feff}{}",
            "\u{feff}1",
            "null",
            "true",
            "false",
            "NaN",
            "Infinity",
            "-Infinity",
            "0",
            "-0",
            "-0.0",
            "1e+16",
            "1.5e-07",
            "123456789012345678901234567890123456789012345",
            "-123456789012345678901234567890123456789012345",
            "\"|\"||/|b|f|n|r|t\"",
            "\"|ud83d|ude00|ud800|udc00|ud800|u0041|ud800\"",
            "{\"k\": 1, \"a\": 2, \"k\": 3}",
            "{\"k\": 1, \"k\": 2, \"k\": 3}",
            "[NaN, Infinity, -Infinity, {\"a\": [1, 2.0, -0]}]",
            "\"|u0041",
            "\"ab|u0041",
            "\"|ud800|u0041",
            "\"|ud800|udc00",
            "\"||u0041",
            "\"|u0041|",
            "\"|u0041x",
        ];
        for tmpl in edge_templates {
            let input = bs(tmpl);
            total += 1;
            assert_differential_case(
                &input,
                &LoadOptions::default(),
                true,
                &mut valid,
                &mut malformed,
                &mut mismatches,
            );
        }

        // 2. 2,500 generated valid inputs (depth 0..=50) + 3,500 mutated malformed inputs.
        let depth_caps = [None, Some(0), Some(1), Some(2), Some(5), Some(12), Some(25)];
        for i in 0..2_500usize {
            let max_d = match i % 5 {
                0 => 0,
                1 => 1 + rng.bound(6),
                2 => 6 + rng.bound(15),
                3 => 20 + rng.bound(25),
                _ => 35 + rng.bound(16), // up to 50
            };
            let mut doc = String::new();
            rand_ws(&mut rng, &mut doc);
            gen_valid_doc(&mut rng, 0, max_d, &mut doc);
            rand_ws(&mut rng, &mut doc);

            total += 1;
            assert_differential_case(
                &doc,
                &LoadOptions::default(),
                true,
                &mut valid,
                &mut malformed,
                &mut mismatches,
            );

            if i % 5 == 0 {
                let cap = depth_caps[rng.bound(depth_caps.len())];
                total += 1;
                assert_differential_case(
                    &doc,
                    &LoadOptions { max_depth: cap },
                    true,
                    &mut valid,
                    &mut malformed,
                    &mut mismatches,
                );
            }

            let bad = gen_malformed_doc(&mut rng, &doc);
            total += 1;
            assert_differential_case(
                &bad,
                &LoadOptions::default(),
                true,
                &mut valid,
                &mut malformed,
                &mut mismatches,
            );
        }

        // 3. 1,500 extra pure malformed mutations across varied truncations/escapes/depths.
        for _ in 0..1_500usize {
            let max_d = 1 + rng.bound(50);
            let mut doc = String::new();
            gen_valid_doc(&mut rng, 0, max_d, &mut doc);
            let bad = gen_malformed_doc(&mut rng, &doc);
            total += 1;
            assert_differential_case(
                &bad,
                &LoadOptions::default(),
                true,
                &mut valid,
                &mut malformed,
                &mut mismatches,
            );
        }

        // 4. `loads_with_limits` with `CPYTHON_312_MAX_DEPTH` and `DEFAULT_INT_MAX_STR_DIGITS`.
        let cp_depth_opts = LoadOptions {
            max_depth: Some(CPYTHON_312_MAX_DEPTH),
        };
        for _ in 0..400usize {
            let max_d = 1 + rng.bound(50);
            let mut doc = String::new();
            rand_ws(&mut rng, &mut doc);
            gen_valid_doc(&mut rng, 0, max_d, &mut doc);
            rand_ws(&mut rng, &mut doc);
            total += 1;
            assert_differential_case(
                &doc,
                &cp_depth_opts,
                true,
                &mut valid,
                &mut malformed,
                &mut mismatches,
            );

            let bad = gen_malformed_doc(&mut rng, &doc);
            total += 1;
            assert_differential_case(
                &bad,
                &cp_depth_opts,
                true,
                &mut valid,
                &mut malformed,
                &mut mismatches,
            );
        }

        // Boundary integers <= 4300 digits match old parser under both limit-free and 4300-digit caps.
        let int_4299 = format!("1{}", "0".repeat(4298));
        let int_4300 = format!("1{}", "0".repeat(4299));
        let neg_4300 = format!("-{}", "9".repeat(4300));
        let int_boundary_docs = [
            int_4299.clone(),
            int_4300.clone(),
            neg_4300.clone(),
            format!("[{int_4300}, {neg_4300}]"),
            format!(r#"{{"n": {int_4300}, "neg": {neg_4300}}}"#),
        ];
        for doc in &int_boundary_docs {
            total += 1;
            assert_differential_case(
                doc,
                &cp_depth_opts,
                true,
                &mut valid,
                &mut malformed,
                &mut mismatches,
            );
        }

        // >4300-digit integers: the old parser has no digit limit, so compare only the
        // digit-limit-free path against it, and verify `Some(DEFAULT_INT_MAX_STR_DIGITS)`
        // rejects with `IntDigitLimit`.
        let int_4301 = format!("1{}", "0".repeat(4300));
        let neg_4301 = format!("-{}", "9".repeat(4301));
        let over_limit_docs = [
            int_4301.clone(),
            neg_4301.clone(),
            format!("[1, {int_4301}]"),
            format!(r#"{{"big": {neg_4301}}}"#),
        ];
        for doc in &over_limit_docs {
            total += 1;
            assert_differential_case(
                doc,
                &cp_depth_opts,
                false,
                &mut valid,
                &mut malformed,
                &mut mismatches,
            );
            let err = loads_with_limits(
                doc,
                Some(CPYTHON_312_MAX_DEPTH),
                Some(DEFAULT_INT_MAX_STR_DIGITS),
            )
            .unwrap_err();
            assert_eq!(err.kind(), JsonErrorKind::IntDigitLimit, "{doc}");
            assert_eq!(err.recursion_message(), None, "{doc}");
        }

        assert!(total >= 7_030, "expected >= 7030 cases, got {total}");
        assert!(valid >= 3_349, "expected >= 3349 valid cases, got {valid}");
        assert!(
            malformed >= 3_681,
            "expected >= 3681 malformed cases, got {malformed}"
        );
        assert_eq!(mismatches, 0);
        eprintln!(
            "DIFFERENTIAL_STATS total={total} valid={valid} malformed={malformed} mismatches={mismatches}"
        );
    }

    #[test]
    fn malformed_parity_cases_match_old_and_cpython_312() {
        // Deduplicated union (151 distinct inputs from 464 total occurrences) of every
        // CPython 3.12 malformed JSON error parity table and assertion across:
        // antigravity-telemetry, gitops, sdk-codegen, sync-site-tools, pycompat,
        // adb-connect (pyjson + profiles), agent-guard (install/pyjson + install_test),
        // registry-trust, release-scope, and design-system/android/tools.
        let cases: &[(&str, &str)] = &[
            ("", "Expecting value: line 1 column 1 (char 0)"),
            ("\n", "Expecting value: line 2 column 1 (char 1)"),
            ("\n\n  x", "Expecting value: line 3 column 3 (char 4)"),
            (
                "\n\"ab",
                "Unterminated string starting at: line 2 column 1 (char 1)",
            ),
            (" ", "Expecting value: line 1 column 2 (char 1)"),
            ("  ", "Expecting value: line 1 column 3 (char 2)"),
            ("  x", "Expecting value: line 1 column 3 (char 2)"),
            ("   \n\t\r  ", "Expecting value: line 2 column 5 (char 8)"),
            (
                "\"|",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "\"|\"",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            ("\"|'\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            ("\"|0\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            ("\"|1\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            (
                "\"||u0041",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            ("\"|a\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            ("\"|q\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            ("\"|u", "Invalid \\uXXXX escape: line 1 column 3 (char 2)"),
            (
                "\"|u 123\"",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"|u0041",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"|u0041|",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "\"|u0041x",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            ("\"|u1", "Invalid \\uXXXX escape: line 1 column 3 (char 2)"),
            ("\"|u12", "Invalid \\uXXXX escape: line 1 column 3 (char 2)"),
            (
                "\"|u12\"",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"|u123",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"|u1234",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"|u123g\"",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"|uZZZZ\"",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"|ud800",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"|ud800|u",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"|ud800|u0041",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"|ud800|u1",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"|ud800|u12",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"|ud800|u12\"",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"|ud800|u123",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"|ud800|u123\"",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"|ud800|u123g\"",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"|ud800|udc00",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"|ud83d|u12\"",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"|ud83d|ude00",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"|ud800|uzzzz\"",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"|ud83d|uzzzz\"x",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            ("\"|v\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            ("\"|x\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            (
                "\"a\x00b\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            (
                "\"a\x01\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            (
                "\"a\x01b\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            (
                "\"a\x08b\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            (
                "\"a\tb\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            (
                "\"a\nb\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            (
                "\"a\x0cb\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            (
                "\"a\rb\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            (
                "\"a\x1fb\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            ("\"a\"\"b\"", "Extra data: line 1 column 4 (char 3)"),
            ("\"a|q\"", "Invalid \\escape: line 1 column 3 (char 2)"),
            ("\"a|qb\"", "Invalid \\escape: line 1 column 3 (char 2)"),
            ("\"a|x\"", "Invalid \\escape: line 1 column 3 (char 2)"),
            (
                "\"ab",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "\"ab|",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "\"ab|u0041",
                "Invalid \\uXXXX escape: line 1 column 5 (char 4)",
            ),
            (
                "\"abc",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "\"abc|u12\"",
                "Invalid \\uXXXX escape: line 1 column 6 (char 5)",
            ),
            ("\"ok\"|", "Extra data: line 1 column 5 (char 4)"),
            ("+1", "Expecting value: line 1 column 1 (char 0)"),
            (",", "Expecting value: line 1 column 1 (char 0)"),
            ("-", "Expecting value: line 1 column 1 (char 0)"),
            ("--1", "Expecting value: line 1 column 1 (char 0)"),
            ("-01", "Extra data: line 1 column 3 (char 2)"),
            ("-I", "Expecting value: line 1 column 1 (char 0)"),
            ("-Inf", "Expecting value: line 1 column 1 (char 0)"),
            ("-Infin", "Expecting value: line 1 column 1 (char 0)"),
            ("-a", "Expecting value: line 1 column 1 (char 0)"),
            (".5", "Expecting value: line 1 column 1 (char 0)"),
            ("00", "Extra data: line 1 column 2 (char 1)"),
            ("01", "Extra data: line 1 column 2 (char 1)"),
            ("1 2", "Extra data: line 1 column 3 (char 2)"),
            ("1 x", "Extra data: line 1 column 3 (char 2)"),
            ("1.", "Extra data: line 1 column 2 (char 1)"),
            ("1.e5", "Extra data: line 1 column 2 (char 1)"),
            ("1..2", "Extra data: line 1 column 2 (char 1)"),
            ("1.2.3", "Extra data: line 1 column 4 (char 3)"),
            ("1e", "Extra data: line 1 column 2 (char 1)"),
            ("1e+", "Extra data: line 1 column 2 (char 1)"),
            ("1e+a", "Extra data: line 1 column 2 (char 1)"),
            ("1e-", "Extra data: line 1 column 2 (char 1)"),
            ("1e-a", "Extra data: line 1 column 2 (char 1)"),
            ("1e1e1", "Extra data: line 1 column 4 (char 3)"),
            (":", "Expecting value: line 1 column 1 (char 0)"),
            ("False", "Expecting value: line 1 column 1 (char 0)"),
            ("Inf", "Expecting value: line 1 column 1 (char 0)"),
            ("Na", "Expecting value: line 1 column 1 (char 0)"),
            ("Null", "Expecting value: line 1 column 1 (char 0)"),
            ("True", "Expecting value: line 1 column 1 (char 0)"),
            ("[", "Expecting value: line 1 column 2 (char 1)"),
            (
                "[\n1,\n\"x\" 2]",
                "Expecting ',' delimiter: line 3 column 5 (char 9)",
            ),
            (
                "[\r\n1,\r\n\"é\" 2]",
                "Expecting ',' delimiter: line 3 column 5 (char 11)",
            ),
            ("[  ", "Expecting value: line 1 column 4 (char 3)"),
            (
                "[\"|u0041",
                "Invalid \\uXXXX escape: line 1 column 4 (char 3)",
            ),
            (
                "[\"abc",
                "Unterminated string starting at: line 1 column 2 (char 1)",
            ),
            (
                "[\"😀\" 2]",
                "Expecting ',' delimiter: line 1 column 6 (char 5)",
            ),
            ("[,]", "Expecting value: line 1 column 2 (char 1)"),
            ("[01]", "Expecting ',' delimiter: line 1 column 3 (char 2)"),
            ("[1", "Expecting ',' delimiter: line 1 column 3 (char 2)"),
            ("[1 2]", "Expecting ',' delimiter: line 1 column 4 (char 3)"),
            (
                "[1, 2 3]",
                "Expecting ',' delimiter: line 1 column 7 (char 6)",
            ),
            ("[1,]", "Expecting value: line 1 column 4 (char 3)"),
            ("[1]\n x", "Extra data: line 2 column 2 (char 5)"),
            ("[[[", "Expecting value: line 1 column 4 (char 3)"),
            ("[] []", "Extra data: line 1 column 4 (char 3)"),
            ("]]]", "Expecting value: line 1 column 1 (char 0)"),
            ("fals", "Expecting value: line 1 column 1 (char 0)"),
            ("infinity", "Expecting value: line 1 column 1 (char 0)"),
            ("nan", "Expecting value: line 1 column 1 (char 0)"),
            ("not json", "Expecting value: line 1 column 1 (char 0)"),
            ("nul", "Expecting value: line 1 column 1 (char 0)"),
            ("tru", "Expecting value: line 1 column 1 (char 0)"),
            ("true false", "Extra data: line 1 column 6 (char 5)"),
            (
                "{",
                "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)",
            ),
            (
                "{\n  \"a\": x\n}",
                "Expecting value: line 2 column 8 (char 9)",
            ),
            (
                "{\n  \"a\": 1,\n  \"b\": [1, 2,\n    \"ok\", tru]\n}",
                "Expecting value: line 4 column 11 (char 36)",
            ),
            (
                "{   ",
                "Expecting property name enclosed in double quotes: line 1 column 5 (char 4)",
            ),
            (
                "{\"a\"   1}",
                "Expecting ':' delimiter: line 1 column 8 (char 7)",
            ),
            (
                "{\"a\" 1}",
                "Expecting ':' delimiter: line 1 column 6 (char 5)",
            ),
            (
                "{\"a\":\n tru}",
                "Expecting value: line 2 column 2 (char 7)",
            ),
            ("{\"a\": ", "Expecting value: line 1 column 7 (char 6)"),
            (
                "{\"a\": \"b\", \"c\" 3}",
                "Expecting ':' delimiter: line 1 column 16 (char 15)",
            ),
            (
                "{\"a\": 1",
                "Expecting ',' delimiter: line 1 column 8 (char 7)",
            ),
            (
                "{\"a\": 1 \"b\"}",
                "Expecting ',' delimiter: line 1 column 9 (char 8)",
            ),
            (
                "{\"a\": 1 \"b\": 2}",
                "Expecting ',' delimiter: line 1 column 9 (char 8)",
            ),
            (
                "{\"a\": 1, ",
                "Expecting property name enclosed in double quotes: line 1 column 10 (char 9)",
            ),
            (
                "{\"a\": 1,}",
                "Expecting property name enclosed in double quotes: line 1 column 9 (char 8)",
            ),
            (
                "{\"a\": [1, 2], \"b\": {\"c\":}}",
                "Expecting value: line 1 column 25 (char 24)",
            ),
            (
                "{\"a\":1 \"b\"}",
                "Expecting ',' delimiter: line 1 column 8 (char 7)",
            ),
            (
                "{\"a\":1,}",
                "Expecting property name enclosed in double quotes: line 1 column 8 (char 7)",
            ),
            ("{\"a\":1}x", "Extra data: line 1 column 8 (char 7)"),
            (
                "{\"a\":[1,2",
                "Expecting ',' delimiter: line 1 column 10 (char 9)",
            ),
            ("{\"a\":[}", "Expecting value: line 1 column 7 (char 6)"),
            ("{\"a\":}", "Expecting value: line 1 column 6 (char 5)"),
            (
                "{\"a\"}",
                "Expecting ':' delimiter: line 1 column 5 (char 4)",
            ),
            (
                "{\"devices\": [}",
                "Expecting value: line 1 column 14 (char 13)",
            ),
            (
                "{\"k\": \"v",
                "Unterminated string starting at: line 1 column 7 (char 6)",
            ),
            (
                "{,}",
                "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)",
            ),
            (
                "{1: 2}",
                "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)",
            ),
            (
                "{a: 1}",
                "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)",
            ),
            (
                "{broken",
                "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)",
            ),
            ("{} x", "Extra data: line 1 column 4 (char 3)"),
            ("{}\n x", "Extra data: line 2 column 2 (char 4)"),
            ("}}}", "Expecting value: line 1 column 1 (char 0)"),
            (
                "\u{feff}",
                "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)",
            ),
            (
                "\u{feff}1",
                "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)",
            ),
            (
                "\u{feff}{}",
                "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)",
            ),
        ];

        let mut seen = std::collections::HashSet::new();
        let mut matched = 0usize;
        for &(tmpl, want) in cases {
            let input = bs(tmpl);
            assert!(
                seen.insert(input.clone()),
                "duplicate parity case {input:?}"
            );
            let old_e =
                legacy_recursive_parser::loads_with(&input, &LoadOptions::default()).unwrap_err();
            let new_e = loads(&input).unwrap_err();
            let lim_e = loads_with_limits(
                &input,
                Some(CPYTHON_312_MAX_DEPTH),
                Some(DEFAULT_INT_MAX_STR_DIGITS),
            )
            .unwrap_err();
            let cps: Vec<u32> = input.chars().map(|c| c as u32).collect();
            let cp_e = loads_codepoints(&cps, &CodepointLoadOptions::default()).unwrap_err();
            assert_eq!(old_e.python_str(), want, "old vs CPython on {input:?}");
            assert_eq!(new_e.python_str(), want, "new vs CPython on {input:?}");
            assert_eq!(lim_e.python_str(), want, "lim vs CPython on {input:?}");
            assert_eq!(cp_e.python_str(), want, "cp vs CPython on {input:?}");
            assert_eq!(
                (new_e.msg.as_str(), new_e.pos, new_e.line, new_e.col),
                (old_e.msg.as_str(), old_e.pos, old_e.line, old_e.col),
                "{input:?}"
            );
            assert_eq!(new_e.to_string(), old_e.to_string(), "{input:?}");
            assert_eq!(new_e.kind(), JsonErrorKind::Decode, "{input:?}");
            assert_eq!(new_e.recursion_message(), None, "{input:?}");
            assert_eq!(lim_e, new_e, "{input:?}");
            matched += 1;
        }
        assert_eq!(matched, 151);
        assert_eq!(matched, cases.len());
        eprintln!("PARITY_CASES matched={matched}/{}", cases.len());
    }

    #[test]
    fn loads_default_accepts_depth_200_000_on_normal_thread() {
        const DEPTH: usize = 200_000;

        // 200,000-deep array via `loads` on a normal test thread; freed via
        // `Value::drop_iteratively` because `Value` intentionally lacks a
        // custom `Drop` so existing callers can move fields by pattern match.
        let deep_arr = format!("{}1{}", "[".repeat(DEPTH), "]".repeat(DEPTH));
        let val = loads(&deep_arr).unwrap();
        assert!(matches!(val, Value::Arr(_)));
        val.drop_iteratively();

        // 200,000-deep object via `loads` on a normal test thread.
        let deep_obj = format!("{}1{}", "{\"a\":".repeat(DEPTH), "}".repeat(DEPTH));
        let obj_val = loads(&deep_obj).unwrap();
        assert!(matches!(obj_val, Value::Obj(_)));
        obj_val.drop_iteratively();

        // 200,000-deep malformed inputs must unwind partial FrameStack and
        // completed Extra-data trees iteratively without overflowing.
        let deep_unclosed = "[".repeat(DEPTH);
        assert_eq!(loads(&deep_unclosed).unwrap_err().msg, "Expecting value");

        let deep_extra = format!("{deep_arr} x");
        assert_eq!(loads(&deep_extra).unwrap_err().msg, "Extra data");

        let deep_bad_outer = format!("[{deep_arr} x]");
        assert_eq!(
            loads(&deep_bad_outer).unwrap_err().msg,
            "Expecting ',' delimiter"
        );

        // 200,000-deep array via `loads_codepoints`, dropped via CodepointValue's
        // native iterative `Drop`.
        let deep_cps: Vec<u32> = deep_arr.chars().map(|c| c as u32).collect();
        let cp_val = loads_codepoints(&deep_cps, &CodepointLoadOptions::default()).unwrap();
        assert!(matches!(cp_val, CodepointValue::Arr(_)));
        drop(cp_val);

        // Exact max_depth boundary at 200,000 on a normal test thread.
        let ok = loads_with(
            &deep_arr,
            &LoadOptions {
                max_depth: Some(DEPTH),
            },
        )
        .unwrap();
        ok.drop_iteratively();

        let over = format!("[{deep_arr}]");
        let err = match loads_with(
            &over,
            &LoadOptions {
                max_depth: Some(DEPTH),
            },
        ) {
            Err(e) => e,
            Ok(v) => {
                v.drop_iteratively();
                panic!("expected recursion error at depth {}", DEPTH + 1);
            }
        };
        assert_eq!(err.kind(), JsonErrorKind::Recursion);
        assert_eq!(
            err.recursion_message(),
            Some("maximum recursion depth exceeded while decoding a JSON array from a unicode string")
        );
        assert_eq!(err.msg, "maximum recursion depth exceeded");
        assert_eq!(err.pos, DEPTH);
    }

    #[test]
    fn loads_with_limits_cpython_312_depth_boundary() {
        // Run directly on the normal default test thread (no 32 MiB stack thread needed);
        // the iterative parser handles 9,997 levels without call-stack recursion, and
        // accepted Values are freed iteratively.
        let arr_ok = format!(
            "{}{}",
            "[".repeat(CPYTHON_312_MAX_DEPTH),
            "]".repeat(CPYTHON_312_MAX_DEPTH)
        );
        let parsed_arr = loads_with_limits(&arr_ok, Some(CPYTHON_312_MAX_DEPTH), None).unwrap();
        parsed_arr.drop_iteratively();

        let arr_scalar_ok = format!(
            "{}1{}",
            "[".repeat(CPYTHON_312_MAX_DEPTH),
            "]".repeat(CPYTHON_312_MAX_DEPTH)
        );
        loads_with_limits(&arr_scalar_ok, Some(CPYTHON_312_MAX_DEPTH), None)
            .unwrap()
            .drop_iteratively();

        let arr_fail = format!(
            "{}{}",
            "[".repeat(CPYTHON_312_MAX_DEPTH + 1),
            "]".repeat(CPYTHON_312_MAX_DEPTH + 1)
        );
        let err_arr = match loads_with_limits(&arr_fail, Some(CPYTHON_312_MAX_DEPTH), None) {
            Err(e) => e,
            Ok(v) => {
                v.drop_iteratively();
                panic!("expected array recursion error at depth 9998");
            }
        };
        assert_eq!(err_arr.kind(), JsonErrorKind::Recursion);
        assert_eq!(
            err_arr.recursion_message(),
            Some("maximum recursion depth exceeded while decoding a JSON array from a unicode string")
        );
        assert_eq!(err_arr.msg, "maximum recursion depth exceeded");
        assert_eq!(err_arr.pos, CPYTHON_312_MAX_DEPTH);

        let obj_ok = format!(
            "{}1{}",
            "{\"a\":".repeat(CPYTHON_312_MAX_DEPTH),
            "}".repeat(CPYTHON_312_MAX_DEPTH)
        );
        let parsed_obj = loads_with_limits(&obj_ok, Some(CPYTHON_312_MAX_DEPTH), None).unwrap();
        parsed_obj.drop_iteratively();

        let obj_fail = format!(
            "{}1{}",
            "{\"a\":".repeat(CPYTHON_312_MAX_DEPTH + 1),
            "}".repeat(CPYTHON_312_MAX_DEPTH + 1)
        );
        let err_obj = match loads_with_limits(&obj_fail, Some(CPYTHON_312_MAX_DEPTH), None) {
            Err(e) => e,
            Ok(v) => {
                v.drop_iteratively();
                panic!("expected object recursion error at depth 9998");
            }
        };
        assert_eq!(err_obj.kind(), JsonErrorKind::Recursion);
        assert_eq!(
            err_obj.recursion_message(),
            Some("maximum recursion depth exceeded while decoding a JSON object from a unicode string")
        );
        assert_eq!(err_obj.msg, "maximum recursion depth exceeded");
        assert_eq!(err_obj.pos, CPYTHON_312_MAX_DEPTH * 5);
    }

    #[test]
    fn loads_with_limits_int_digit_boundary_and_error_kinds() {
        assert_eq!(DEFAULT_INT_MAX_STR_DIGITS, 4300);
        assert_eq!(CPYTHON_312_MAX_DEPTH, 9997);

        // Positive 4300-digit boundary: accepted at 4300, rejected at 4301.
        let ok_4300 = format!("1{}", "0".repeat(4299));
        assert_eq!(
            loads_with_limits(&ok_4300, None, Some(DEFAULT_INT_MAX_STR_DIGITS)).unwrap(),
            Value::Int(ok_4300)
        );

        let too_big = format!("1{}", "0".repeat(4300));
        let err_pos =
            loads_with_limits(&too_big, None, Some(DEFAULT_INT_MAX_STR_DIGITS)).unwrap_err();
        assert_eq!(err_pos.kind(), JsonErrorKind::IntDigitLimit);
        assert_eq!(err_pos.recursion_message(), None);
        assert_eq!(
            err_pos.msg,
            "Exceeds the limit (4300 digits) for integer string conversion: value has 4301 digits; use sys.set_int_max_str_digits() to increase the limit"
        );
        assert_eq!((err_pos.line, err_pos.col, err_pos.pos), (1, 1, 0));

        // Nested 4301-digit integer records value start position.
        let nested_too_big = format!("[1, {too_big}]");
        let err_nested =
            loads_with_limits(&nested_too_big, None, Some(DEFAULT_INT_MAX_STR_DIGITS)).unwrap_err();
        assert_eq!(err_nested.kind(), JsonErrorKind::IntDigitLimit);
        assert_eq!(err_nested.recursion_message(), None);
        assert_eq!((err_nested.line, err_nested.col, err_nested.pos), (1, 5, 4));

        // Negative integer at the boundary: '-' does not count as a digit.
        let neg_4300 = format!("-{}", "9".repeat(4300));
        assert_eq!(
            loads_with_limits(&neg_4300, None, Some(DEFAULT_INT_MAX_STR_DIGITS)).unwrap(),
            Value::Int(neg_4300)
        );

        let neg_4301 = format!("-{}", "9".repeat(4301));
        let err_neg =
            loads_with_limits(&neg_4301, None, Some(DEFAULT_INT_MAX_STR_DIGITS)).unwrap_err();
        assert_eq!(err_neg.kind(), JsonErrorKind::IntDigitLimit);
        assert_eq!(err_neg.recursion_message(), None);
        assert_eq!(
            err_neg.msg,
            "Exceeds the limit (4300 digits) for integer string conversion: value has 4301 digits; use sys.set_int_max_str_digits() to increase the limit"
        );
        assert_eq!((err_neg.line, err_neg.col, err_neg.pos), (1, 1, 0));

        // Float with 4301 integer digits is not capped; unlimited `loads`/`loads_with`/`loads_with_limits(..., None)` remain unlimited.
        let float_4301 = format!("{too_big}.0");
        assert!(matches!(
            loads_with_limits(&float_4301, None, Some(DEFAULT_INT_MAX_STR_DIGITS)),
            Ok(Value::Float(f)) if f.is_infinite()
        ));
        assert_eq!(loads(&too_big).unwrap(), Value::Int(too_big.clone()));
        assert_eq!(
            loads_with(&too_big, &LoadOptions::default()).unwrap(),
            Value::Int(too_big.clone())
        );
        assert_eq!(
            loads_with_limits(&too_big, None, None).unwrap(),
            Value::Int(too_big)
        );

        // `kind()` and `recursion_message()` across every error class.
        for decode_input in ["", "[1 2]", r#""\x""#, r#""\u12""#, "\"a\nb\"", "{} x"] {
            let err = loads_with_limits(
                decode_input,
                Some(CPYTHON_312_MAX_DEPTH),
                Some(DEFAULT_INT_MAX_STR_DIGITS),
            )
            .unwrap_err();
            assert_eq!(err.kind(), JsonErrorKind::Decode, "{decode_input:?}");
            assert_eq!(err.recursion_message(), None, "{decode_input:?}");
        }

        let err_bom = loads_with_limits(
            "\u{feff}{}",
            Some(CPYTHON_312_MAX_DEPTH),
            Some(DEFAULT_INT_MAX_STR_DIGITS),
        )
        .unwrap_err();
        assert_eq!(err_bom.kind(), JsonErrorKind::Decode);
        assert_eq!(err_bom.recursion_message(), None);

        let err_rec_arr = loads_with_limits("[[]]", Some(1), None).unwrap_err();
        assert_eq!(err_rec_arr.kind(), JsonErrorKind::Recursion);
        assert_eq!(
            err_rec_arr.recursion_message(),
            Some("maximum recursion depth exceeded while decoding a JSON array from a unicode string")
        );

        let err_rec_obj = loads_with_limits("[{}]", Some(1), None).unwrap_err();
        assert_eq!(err_rec_obj.kind(), JsonErrorKind::Recursion);
        assert_eq!(
            err_rec_obj.recursion_message(),
            Some("maximum recursion depth exceeded while decoding a JSON object from a unicode string")
        );
    }

    #[test]
    fn loads_codepoints_preserves_lone_surrogates_and_int_limit() {
        let cps = |s: &str| -> Vec<u32> { s.chars().map(|c| c as u32).collect() };
        let opts = CodepointLoadOptions {
            max_depth: Some(CPYTHON_312_MAX_DEPTH),
            max_int_digits: Some(DEFAULT_INT_MAX_STR_DIGITS),
        };

        let raw = loads_codepoints(
            &cps(&bs(
                r#"{"|ud800": 1, "|ud801": 2, "pair": "|ud83d|ude00|ud800|u0041|ud800|ud83d|ude00"}"#,
            )),
            &opts,
        )
        .unwrap();
        assert_eq!(
            raw,
            CodepointValue::Obj(vec![
                (vec![0xD800], CodepointValue::Int("1".into())),
                (vec![0xD801], CodepointValue::Int("2".into())),
                (
                    cps("pair"),
                    CodepointValue::Str(vec![0x1F600, 0xD800, 'A' as u32, 0xD800, 0x1F600])
                ),
            ])
        );

        // Duplicate lone-surrogate key keeps first position and last value.
        let dup_surr =
            loads_codepoints(&cps(&bs(r#"{"|ud800": 1, "b": 2, "|ud800": 3}"#)), &opts).unwrap();
        assert_eq!(
            dup_surr,
            CodepointValue::Obj(vec![
                (vec![0xD800], CodepointValue::Int("3".into())),
                (cps("b"), CodepointValue::Int("2".into())),
            ])
        );

        // Literal surrogate code point inside quoted JSON string survives.
        let literal_surr = vec!['"' as u32, 0xD800, '"' as u32];
        assert_eq!(
            loads_codepoints(&literal_surr, &opts).unwrap(),
            CodepointValue::Str(vec![0xD800])
        );
        // Bare surrogate code point outside string fails like CPython.
        let err_bare = loads_codepoints(&[0xD800], &opts).unwrap_err();
        assert_eq!(err_bare.kind(), JsonErrorKind::Decode);
        assert_eq!(err_bare.recursion_message(), None);
        assert_eq!(
            err_bare.python_str(),
            "Expecting value: line 1 column 1 (char 0)"
        );

        // Integer digit cap: 4300 OK, 4301 fails with IntDigitLimit; 4301 float OK.
        let ok_4300 = format!("-{}", "9".repeat(4300));
        assert!(loads_codepoints(&cps(&ok_4300), &opts).is_ok());

        let too_big = format!("1{}", "0".repeat(4300));
        let err_int = loads_codepoints(&cps(&too_big), &opts).unwrap_err();
        assert_eq!(err_int.kind(), JsonErrorKind::IntDigitLimit);
        assert_eq!(err_int.recursion_message(), None);
        assert_eq!(
            err_int.msg,
            "Exceeds the limit (4300 digits) for integer string conversion: value has 4301 digits; use sys.set_int_max_str_digits() to increase the limit"
        );

        let too_big_neg = format!("-{}", "9".repeat(4301));
        assert_eq!(
            loads_codepoints(&cps(&too_big_neg), &opts)
                .unwrap_err()
                .kind(),
            JsonErrorKind::IntDigitLimit
        );

        let float_4301 = format!("1{}.0", "0".repeat(4300));
        assert!(matches!(
            loads_codepoints(&cps(&float_4301), &opts),
            Ok(CodepointValue::Float(f)) if f.is_infinite()
        ));
    }

    #[test]
    fn loads_codepoints_depth_9997_and_error_kinds() {
        let opts = CodepointLoadOptions {
            max_depth: Some(CPYTHON_312_MAX_DEPTH),
            max_int_digits: Some(DEFAULT_INT_MAX_STR_DIGITS),
        };
        let arr_ok: Vec<u32> = format!(
            "{}{}",
            "[".repeat(CPYTHON_312_MAX_DEPTH),
            "]".repeat(CPYTHON_312_MAX_DEPTH)
        )
        .chars()
        .map(|c| c as u32)
        .collect();
        let parsed = loads_codepoints(&arr_ok, &opts).unwrap();
        drop(parsed);

        let arr_fail: Vec<u32> = format!(
            "{}{}",
            "[".repeat(CPYTHON_312_MAX_DEPTH + 1),
            "]".repeat(CPYTHON_312_MAX_DEPTH + 1)
        )
        .chars()
        .map(|c| c as u32)
        .collect();
        let err_arr = match loads_codepoints(&arr_fail, &opts) {
            Err(e) => e,
            Ok(v) => {
                drop(v);
                panic!("expected codepoints array recursion error at depth 9998");
            }
        };
        assert_eq!(err_arr.kind(), JsonErrorKind::Recursion);
        assert_eq!(
            err_arr.recursion_message(),
            Some("maximum recursion depth exceeded while decoding a JSON array from a unicode string")
        );

        let obj_ok: Vec<u32> = format!(
            "{}1{}",
            "{\"a\":".repeat(CPYTHON_312_MAX_DEPTH),
            "}".repeat(CPYTHON_312_MAX_DEPTH)
        )
        .chars()
        .map(|c| c as u32)
        .collect();
        let parsed_obj = loads_codepoints(&obj_ok, &opts).unwrap();
        drop(parsed_obj);

        let obj_fail: Vec<u32> = format!(
            "{}1{}",
            "{\"a\":".repeat(CPYTHON_312_MAX_DEPTH + 1),
            "}".repeat(CPYTHON_312_MAX_DEPTH + 1)
        )
        .chars()
        .map(|c| c as u32)
        .collect();
        let err_obj = match loads_codepoints(&obj_fail, &opts) {
            Err(e) => e,
            Ok(v) => {
                drop(v);
                panic!("expected codepoints object recursion error at depth 9998");
            }
        };
        assert_eq!(err_obj.kind(), JsonErrorKind::Recursion);
        assert_eq!(
            err_obj.recursion_message(),
            Some("maximum recursion depth exceeded while decoding a JSON object from a unicode string")
        );
    }
}
