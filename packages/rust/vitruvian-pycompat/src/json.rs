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
//! Infinity, integers of any size, the last of two equal keys winning) and a
//! writer that writes what `json.dumps` writes with its defaults.

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

/// A document that does not parse. The message is in Python's words where
/// that was easy; callers that mirror a crash only rely on the class.
#[derive(Debug)]
pub struct JsonError {
    pub msg: String,
    pub pos: usize,
}

impl std::fmt::Display for JsonError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{} (char {})", self.msg, self.pos)
    }
}

pub fn loads(text: &str) -> Result<Value, JsonError> {
    if text.starts_with('\u{feff}') {
        return Err(JsonError {
            msg: "Unexpected UTF-8 BOM (decode using utf-8-sig)".into(),
            pos: 0,
        });
    }
    let chars: Vec<char> = text.chars().collect();
    let mut p = Parser { s: &chars, i: 0 };
    p.ws();
    let v = p.value()?;
    p.ws();
    if p.i != chars.len() {
        return Err(p.err("Extra data"));
    }
    Ok(v)
}

struct Parser<'a> {
    s: &'a [char],
    i: usize,
}

impl<'a> Parser<'a> {
    fn err(&self, msg: &str) -> JsonError {
        JsonError {
            msg: msg.into(),
            pos: self.i,
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
        if self.i + 4 > self.s.len() {
            return Err(self.err("Invalid \\uXXXX escape"));
        }
        let h: String = self.s[self.i..self.i + 4].iter().collect();
        if !h.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(self.err("Invalid \\uXXXX escape"));
        }
        self.i += 4;
        Ok(u32::from_str_radix(&h, 16).unwrap())
    }

    fn string(&mut self) -> Result<String, JsonError> {
        let mut out = String::new();
        loop {
            let c = match self.peek() {
                None => return Err(self.err("Unterminated string starting at")),
                Some(c) => c,
            };
            self.i += 1;
            match c {
                '"' => return Ok(out),
                '\\' => {
                    let e = self.peek().ok_or_else(|| self.err("Unterminated string"))?;
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
                            // A lone surrogate cannot live in a Rust string.
                            out.push(char::from_u32(cp).unwrap_or('\u{fffd}'));
                        }
                        _ => {
                            self.i -= 1;
                            return Err(self.err("Invalid \\escape"));
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

/// `json.dumps(value)` with its defaults: ", " and ": " separators,
/// non-ASCII escaped.
pub fn dumps(v: &Value) -> String {
    let mut out = String::new();
    write_value(v, &mut out);
    out
}

fn write_value(v: &Value, out: &mut String) {
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
        Value::Str(s) => write_str(s, out),
        Value::Arr(items) => {
            out.push('[');
            for (i, item) in items.iter().enumerate() {
                if i > 0 {
                    out.push_str(", ");
                }
                write_value(item, out);
            }
            out.push(']');
        }
        Value::Obj(items) => {
            out.push('{');
            for (i, (k, item)) in dedup(items).iter().enumerate() {
                if i > 0 {
                    out.push_str(", ");
                }
                write_str(k, out);
                out.push_str(": ");
                write_value(item, out);
            }
            out.push('}');
        }
    }
}

fn write_str(s: &str, out: &mut String) {
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
            c if (c as u32) < 0x20 || (c as u32) > 0x7e => {
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
}
