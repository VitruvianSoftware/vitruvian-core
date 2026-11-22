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

impl Value {
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
}

impl JsonError {
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
fn locate(chars: &[char], mut e: JsonError) -> JsonError {
    let before = &chars[..e.py_pos.min(chars.len())];
    e.line = before.iter().filter(|c| **c == '\n').count() + 1;
    e.col = match before.iter().rposition(|c| *c == '\n') {
        Some(nl) => e.py_pos - nl,
        None => e.py_pos + 1,
    };
    e
}

pub fn loads(text: &str) -> Result<Value, JsonError> {
    let chars: Vec<char> = text.chars().collect();
    if text.starts_with('\u{feff}') {
        let msg = "Unexpected UTF-8 BOM (decode using utf-8-sig)";
        return Err(locate(
            &chars,
            JsonError {
                msg: msg.into(),
                pos: 0,
                line: 0,
                col: 0,
                py_msg: msg.into(),
                py_pos: 0,
            },
        ));
    }
    let mut p = Parser { s: &chars, i: 0 };
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
}

impl<'a> Parser<'a> {
    fn err(&self, msg: &str) -> JsonError {
        self.err_with_py(msg, self.i, msg, self.i)
    }

    fn err_with_py(&self, msg: &str, pos: usize, py_msg: &str, py_pos: usize) -> JsonError {
        JsonError {
            msg: msg.into(),
            pos,
            line: 0,
            col: 0,
            py_msg: py_msg.into(),
            py_pos,
        }
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

    fn value(&mut self) -> Result<Value, JsonError> {
        match self.peek() {
            Some('{') => self.object(),
            Some('[') => self.array(),
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

    fn number(&mut self) -> Result<Value, JsonError> {
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

    fn string(&mut self) -> Result<String, JsonError> {
        let start = self.i - 1;
        let mut out = String::new();
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
                            // A lone surrogate cannot live in a Rust string.
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

    fn array(&mut self) -> Result<Value, JsonError> {
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

    fn object(&mut self) -> Result<Value, JsonError> {
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
}
