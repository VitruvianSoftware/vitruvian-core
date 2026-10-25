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

//! `json.loads` and `json.dumps` as CPython 3.12 runs them (its C scanner,
//! with its messages and positions), and the few things sync.py does with
//! what they return: subscripts, `.get`, iteration, truthiness, `str()`,
//! `repr()`, `==` and `<`, with Python's errors when a value is the wrong
//! type.

use std::cmp::Ordering;

use crate::pyerr::PyErr;
use crate::pystr::PyStr;

/// An `int`: its sign and decimal digits, without leading zeros.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BigInt {
    pub negative: bool,
    pub digits: String,
}

impl BigInt {
    pub fn from_i64(value: i64) -> BigInt {
        BigInt {
            negative: value < 0,
            digits: value.unsigned_abs().to_string(),
        }
    }

    /// From a JSON integer literal: `-?(0|[1-9][0-9]*)`.
    fn from_literal(text: &str) -> BigInt {
        let (negative, digits) = match text.strip_prefix('-') {
            Some(rest) => (true, rest),
            None => (false, text),
        };
        let digits = digits.trim_start_matches('0');
        if digits.is_empty() {
            BigInt {
                negative: false,
                digits: "0".to_string(),
            }
        } else {
            BigInt {
                negative,
                digits: digits.to_string(),
            }
        }
    }

    pub fn is_zero(&self) -> bool {
        self.digits == "0"
    }

    pub fn repr(&self) -> String {
        if self.negative {
            format!("-{}", self.digits)
        } else {
            self.digits.clone()
        }
    }

    fn cmp_magnitude(a: &str, b: &str) -> Ordering {
        a.len().cmp(&b.len()).then_with(|| a.cmp(b))
    }

    pub fn cmp_int(&self, other: &BigInt) -> Ordering {
        match (self.negative, other.negative) {
            (false, true) => Ordering::Greater,
            (true, false) => Ordering::Less,
            (false, false) => BigInt::cmp_magnitude(&self.digits, &other.digits),
            (true, true) => BigInt::cmp_magnitude(&other.digits, &self.digits),
        }
    }

    /// `self` against a float, exactly, as Python compares them; None for
    /// a NaN.
    pub fn cmp_float(&self, f: f64) -> Option<Ordering> {
        if f.is_nan() {
            return None;
        }
        if f.is_infinite() {
            return Some(if f > 0.0 {
                Ordering::Less
            } else {
                Ordering::Greater
            });
        }
        let whole = f.trunc();
        // Rust prints an integral float's exact value at precision 0.
        let exact = format!("{:.0}", whole);
        let as_int = BigInt::from_literal(&exact);
        match self.cmp_int(&as_int) {
            Ordering::Equal => {
                let frac = f - whole;
                Some(if frac > 0.0 {
                    Ordering::Less
                } else if frac < 0.0 {
                    Ordering::Greater
                } else {
                    Ordering::Equal
                })
            }
            other => Some(other),
        }
    }

    /// `self / 2**power`, correctly rounded, as Python's true division
    /// gives it; None where Python raises OverflowError.
    pub fn div_pow2(&self, power: u32) -> Option<f64> {
        // self / 2**p == self * 5**p / 10**p, and both are exact decimals.
        let mut product: Vec<u32> = self
            .digits
            .bytes()
            .rev()
            .map(|b| (b - b'0') as u32)
            .collect();
        for _ in 0..power {
            let mut carry = 0u32;
            for digit in product.iter_mut() {
                let v = *digit * 5 + carry;
                *digit = v % 10;
                carry = v / 10;
            }
            while carry > 0 {
                product.push(carry % 10);
                carry /= 10;
            }
        }
        let digits: String = product
            .iter()
            .rev()
            .map(|&d| char::from(b'0' + d as u8))
            .collect();
        let text = format!(
            "{}{}e-{}",
            if self.negative { "-" } else { "" },
            digits,
            power
        );
        let value: f64 = text.parse().ok()?;
        if value.is_infinite() {
            None
        } else {
            Some(value)
        }
    }
}

/// A value `json.loads` returns.
#[derive(Clone, Debug)]
pub enum Value {
    Null,
    Bool(bool),
    Int(BigInt),
    Float(f64),
    Str(PyStr),
    List(Vec<Value>),
    /// Keys in insertion order; a repeated key keeps its first place and
    /// takes its last value, as a dict does.
    Dict(Vec<(PyStr, Value)>),
}

pub fn s(text: &str) -> Value {
    Value::Str(PyStr::from(text))
}

pub fn obj(pairs: Vec<(&str, Value)>) -> Value {
    Value::Dict(
        pairs
            .into_iter()
            .map(|(k, v)| (PyStr::from(k), v))
            .collect(),
    )
}

pub fn list_of_str(items: &[&str]) -> Value {
    Value::List(items.iter().map(|item| s(item)).collect())
}

fn dict_insert(pairs: &mut Vec<(PyStr, Value)>, key: PyStr, value: Value) {
    if let Some(slot) = pairs.iter_mut().find(|(k, _)| *k == key) {
        slot.1 = value;
    } else {
        pairs.push((key, value));
    }
}

/// Python's `float.__repr__`.
pub fn float_repr(f: f64) -> String {
    if f.is_nan() {
        return "nan".to_string();
    }
    if f.is_infinite() {
        return if f > 0.0 { "inf" } else { "-inf" }.to_string();
    }
    // Rust's {:e} prints the shortest digits that round-trip, as Python's
    // repr chooses them; only the layout differs.
    let sci = format!("{:e}", f);
    let (negative, sci) = match sci.strip_prefix('-') {
        Some(rest) => (true, rest.to_string()),
        None => (false, sci),
    };
    let (mantissa, exponent) = sci.split_once('e').unwrap_or((&sci, "0"));
    let exponent: i64 = exponent.parse().unwrap_or(0);
    let digits: String = mantissa.chars().filter(|c| *c != '.').collect();
    let decpt = exponent + 1;
    let n = digits.len() as i64;
    let mut out = String::new();
    if negative {
        out.push('-');
    }
    if decpt <= -4 || decpt > 16 {
        out.push_str(&digits[..1]);
        if n > 1 {
            out.push('.');
            out.push_str(&digits[1..]);
        }
        let e = decpt - 1;
        out.push_str(&format!(
            "e{}{:02}",
            if e < 0 { '-' } else { '+' },
            e.unsigned_abs()
        ));
    } else if decpt <= 0 {
        out.push_str("0.");
        for _ in 0..(-decpt) {
            out.push('0');
        }
        out.push_str(&digits);
    } else if decpt >= n {
        out.push_str(&digits);
        for _ in 0..(decpt - n) {
            out.push('0');
        }
        out.push_str(".0");
    } else {
        out.push_str(&digits[..decpt as usize]);
        out.push('.');
        out.push_str(&digits[decpt as usize..]);
    }
    out
}

/// `f"{value:.1f}"` of a float.
pub fn format_fixed1(f: f64) -> String {
    if f.is_nan() {
        return "nan".to_string();
    }
    if f.is_infinite() {
        return if f > 0.0 { "inf" } else { "-inf" }.to_string();
    }
    format!("{:.1}", f)
}

impl Value {
    pub fn type_name(&self) -> &'static str {
        match self {
            Value::Null => "NoneType",
            Value::Bool(_) => "bool",
            Value::Int(_) => "int",
            Value::Float(_) => "float",
            Value::Str(_) => "str",
            Value::List(_) => "list",
            Value::Dict(_) => "dict",
        }
    }

    pub fn str_value(&self) -> Option<&PyStr> {
        match self {
            Value::Str(text) => Some(text),
            _ => None,
        }
    }

    /// `bool(self)`.
    pub fn truthy(&self) -> bool {
        match self {
            Value::Null => false,
            Value::Bool(b) => *b,
            Value::Int(i) => !i.is_zero(),
            Value::Float(f) => *f != 0.0,
            Value::Str(text) => !text.is_empty(),
            Value::List(items) => !items.is_empty(),
            Value::Dict(pairs) => !pairs.is_empty(),
        }
    }

    /// `self[key]` for a str key.
    pub fn subscript(&self, key: &str) -> Result<&Value, PyErr> {
        match self {
            Value::Dict(pairs) => {
                let key = PyStr::from(key);
                pairs
                    .iter()
                    .find(|(k, _)| *k == key)
                    .map(|(_, v)| v)
                    .ok_or_else(|| PyErr::key_error(&key))
            }
            Value::List(_) => Err(PyErr::type_error(
                "list indices must be integers or slices, not str",
            )),
            Value::Str(_) => Err(PyErr::type_error(
                "string indices must be integers, not 'str'",
            )),
            other => Err(PyErr::type_error(&format!(
                "'{}' object is not subscriptable",
                other.type_name()
            ))),
        }
    }

    /// `self.get(key)`: None for a missing key, AttributeError on a value
    /// that is not a dict.
    pub fn get(&self, key: &str) -> Result<Option<&Value>, PyErr> {
        match self {
            Value::Dict(pairs) => {
                let key = PyStr::from(key);
                Ok(pairs.iter().find(|(k, _)| *k == key).map(|(_, v)| v))
            }
            other => Err(PyErr::exc(
                "AttributeError",
                &format!("'{}' object has no attribute 'get'", other.type_name()),
            )),
        }
    }

    /// `self.get(key, default)`.
    pub fn get_or(&self, key: &str, default: Value) -> Result<Value, PyErr> {
        Ok(self.get(key)?.cloned().unwrap_or(default))
    }

    /// `self.get(key)`, the value or None.
    pub fn get_value(&self, key: &str) -> Result<Value, PyErr> {
        self.get_or(key, Value::Null)
    }

    /// `list(self)`: what iterating it gives.
    pub fn iterate(&self) -> Result<Vec<Value>, PyErr> {
        match self {
            Value::List(items) => Ok(items.clone()),
            Value::Dict(pairs) => Ok(pairs.iter().map(|(k, _)| Value::Str(k.clone())).collect()),
            Value::Str(text) => Ok(text
                .chars()
                .iter()
                .map(|&c| Value::Str(PyStr(vec![c])))
                .collect()),
            other => Err(PyErr::type_error(&format!(
                "'{}' object is not iterable",
                other.type_name()
            ))),
        }
    }

    /// Raises what `hash(self)` raises: a dict lookup or `in` on a dict.
    pub fn check_hashable(&self) -> Result<(), PyErr> {
        match self {
            Value::List(_) | Value::Dict(_) => Err(PyErr::type_error(&format!(
                "unhashable type: '{}'",
                self.type_name()
            ))),
            _ => Ok(()),
        }
    }

    /// `self == "text"`.
    pub fn eq_str(&self, text: &str) -> bool {
        match self {
            Value::Str(own) => *own == PyStr::from(text),
            _ => false,
        }
    }

    fn number(&self) -> Option<Number> {
        match self {
            Value::Bool(b) => Some(Number::Int(BigInt::from_i64(*b as i64))),
            Value::Int(i) => Some(Number::Int(i.clone())),
            Value::Float(f) => Some(Number::Float(*f)),
            _ => None,
        }
    }

    /// `PyObject_RichCompareBool(self, other, Py_EQ)`. json.loads returns
    /// one object for every `NaN`, so a NaN is equal to a NaN here, by
    /// identity, as it is in a sort's comparisons or `in`.
    pub fn py_eq(&self, other: &Value) -> bool {
        if let (Some(a), Some(b)) = (self.number(), other.number()) {
            if let (Number::Float(x), Number::Float(y)) = (&a, &b) {
                if x.is_nan() && y.is_nan() {
                    return true;
                }
            }
            return a.partial_cmp(&b) == Some(Ordering::Equal);
        }
        match (self, other) {
            (Value::Null, Value::Null) => true,
            (Value::Str(a), Value::Str(b)) => a == b,
            (Value::List(a), Value::List(b)) => {
                a.len() == b.len() && a.iter().zip(b).all(|(x, y)| x.py_eq(y))
            }
            (Value::Dict(a), Value::Dict(b)) => {
                a.len() == b.len()
                    && a.iter().all(|(k, v)| {
                        b.iter()
                            .find(|(k2, _)| k2 == k)
                            .map_or(false, |(_, v2)| v.py_eq(v2))
                    })
            }
            _ => false,
        }
    }

    /// `self < other`.
    pub fn py_lt(&self, other: &Value) -> Result<bool, PyErr> {
        if let (Some(a), Some(b)) = (self.number(), other.number()) {
            return Ok(a.partial_cmp(&b) == Some(Ordering::Less));
        }
        match (self, other) {
            (Value::Str(a), Value::Str(b)) => Ok(a < b),
            (Value::List(a), Value::List(b)) => {
                for (x, y) in a.iter().zip(b) {
                    if !x.py_eq(y) {
                        return x.py_lt(y);
                    }
                }
                Ok(a.len() < b.len())
            }
            _ => Err(PyErr::type_error(&format!(
                "'<' not supported between instances of '{}' and '{}'",
                self.type_name(),
                other.type_name()
            ))),
        }
    }

    /// `str(self)`, which an f-string's `{value}` is.
    pub fn py_str(&self) -> PyStr {
        match self {
            Value::Str(text) => text.clone(),
            other => other.py_repr(),
        }
    }

    /// `repr(self)`.
    pub fn py_repr(&self) -> PyStr {
        match self {
            Value::Null => PyStr::from("None"),
            Value::Bool(true) => PyStr::from("True"),
            Value::Bool(false) => PyStr::from("False"),
            Value::Int(i) => PyStr::from(i.repr()),
            Value::Float(f) => PyStr::from(float_repr(*f)),
            Value::Str(text) => text.repr(),
            Value::List(items) => {
                let mut out = PyStr::from("[");
                for (i, item) in items.iter().enumerate() {
                    if i > 0 {
                        out.push_str(", ");
                    }
                    out.push(&item.py_repr());
                }
                out.push_str("]");
                out
            }
            Value::Dict(pairs) => {
                let mut out = PyStr::from("{");
                for (i, (k, v)) in pairs.iter().enumerate() {
                    if i > 0 {
                        out.push_str(", ");
                    }
                    out.push(&k.repr());
                    out.push_str(": ");
                    out.push(&v.py_repr());
                }
                out.push_str("}");
                out
            }
        }
    }
}

#[derive(Clone, Debug)]
enum Number {
    Int(BigInt),
    Float(f64),
}

impl PartialEq for Number {
    fn eq(&self, other: &Self) -> bool {
        self.partial_cmp(other) == Some(Ordering::Equal)
    }
}

impl PartialOrd for Number {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        match (self, other) {
            (Number::Int(a), Number::Int(b)) => Some(a.cmp_int(b)),
            (Number::Float(a), Number::Float(b)) => a.partial_cmp(b),
            (Number::Int(a), Number::Float(b)) => a.cmp_float(*b),
            (Number::Float(a), Number::Int(b)) => b.cmp_float(*a).map(Ordering::reverse),
        }
    }
}

// --- json.loads -----------------------------------------------------------

fn decode_error(message: &str, doc: &[u32], pos: usize) -> PyErr {
    let before = &doc[..pos.min(doc.len())];
    let lineno = before.iter().filter(|&&c| c == '\n' as u32).count() + 1;
    let colno = match before.iter().rposition(|&c| c == '\n' as u32) {
        Some(nl) => pos - nl,
        None => pos + 1,
    };
    PyErr::exc(
        "json.decoder.JSONDecodeError",
        &format!(
            "{}: line {} column {} (char {})",
            message, lineno, colno, pos
        ),
    )
}

/// Not a value at `pos`: the C scanner's StopIteration, which
/// `raw_decode` turns into "Expecting value".
enum ScanErr {
    Stop(usize),
    Raise(PyErr),
}

impl From<PyErr> for ScanErr {
    fn from(e: PyErr) -> Self {
        ScanErr::Raise(e)
    }
}

struct Scanner<'a> {
    s: &'a [u32],
}

fn is_ws(c: u32) -> bool {
    c == ' ' as u32 || c == '\t' as u32 || c == '\n' as u32 || c == '\r' as u32
}

fn is_digit(c: u32) -> bool {
    ('0' as u32..='9' as u32).contains(&c)
}

impl<'a> Scanner<'a> {
    fn at(&self, i: usize) -> u32 {
        self.s[i]
    }

    fn matches(&self, idx: usize, word: &str) -> bool {
        let word: Vec<u32> = word.chars().map(|c| c as u32).collect();
        idx + word.len() <= self.s.len() && self.s[idx..idx + word.len()] == word[..]
    }

    fn scan_once(&self, idx: usize) -> Result<(Value, usize), ScanErr> {
        let len = self.s.len();
        if idx >= len {
            return Err(ScanErr::Stop(idx));
        }
        let c = self.at(idx);
        match char::from_u32(c).unwrap_or('\0') {
            '"' => {
                let (text, end) = self.scanstring(idx + 1)?;
                return Ok((Value::Str(text), end));
            }
            '{' => return self.parse_object(idx + 1),
            '[' => return self.parse_array(idx + 1),
            'n' if idx + 3 < len && self.matches(idx, "null") => return Ok((Value::Null, idx + 4)),
            't' if idx + 3 < len && self.matches(idx, "true") => {
                return Ok((Value::Bool(true), idx + 4))
            }
            'f' if idx + 4 < len && self.matches(idx, "false") => {
                return Ok((Value::Bool(false), idx + 5))
            }
            'N' if idx + 2 < len && self.matches(idx, "NaN") => {
                return Ok((Value::Float(f64::NAN), idx + 3))
            }
            'I' if idx + 7 < len && self.matches(idx, "Infinity") => {
                return Ok((Value::Float(f64::INFINITY), idx + 8))
            }
            '-' if idx + 8 < len && self.matches(idx, "-Infinity") => {
                return Ok((Value::Float(f64::NEG_INFINITY), idx + 9))
            }
            _ => {}
        }
        self.match_number(idx)
    }

    fn match_number(&self, start: usize) -> Result<(Value, usize), ScanErr> {
        let s = self.s;
        let end_idx = s.len() - 1;
        let mut idx = start;
        if s[idx] == '-' as u32 {
            idx += 1;
            if idx > end_idx {
                return Err(ScanErr::Stop(start));
            }
        }
        if (('1' as u32)..=('9' as u32)).contains(&s[idx]) {
            idx += 1;
            while idx <= end_idx && is_digit(s[idx]) {
                idx += 1;
            }
        } else if s[idx] == '0' as u32 {
            idx += 1;
        } else {
            return Err(ScanErr::Stop(start));
        }
        let mut is_float = false;
        if idx < end_idx && s[idx] == '.' as u32 && is_digit(s[idx + 1]) {
            is_float = true;
            idx += 2;
            while idx <= end_idx && is_digit(s[idx]) {
                idx += 1;
            }
        }
        if idx < end_idx && (s[idx] == 'e' as u32 || s[idx] == 'E' as u32) {
            let e_start = idx;
            idx += 1;
            if idx < end_idx && (s[idx] == '-' as u32 || s[idx] == '+' as u32) {
                idx += 1;
            }
            while idx <= end_idx && is_digit(s[idx]) {
                idx += 1;
            }
            if is_digit(s[idx - 1]) {
                is_float = true;
            } else {
                idx = e_start;
            }
        }
        let text: String = s[start..idx]
            .iter()
            .map(|&c| char::from_u32(c).unwrap_or('0'))
            .collect();
        if is_float {
            let value: f64 = text.parse().unwrap_or(f64::NAN);
            Ok((Value::Float(value), idx))
        } else {
            let digits = text.trim_start_matches('-').len();
            if digits > 4300 {
                return Err(ScanErr::Raise(PyErr::exc(
                    "ValueError",
                    &format!(
                        "Exceeds the limit (4300 digits) for integer string conversion: value has {} digits; use sys.set_int_max_str_digits() to increase the limit",
                        digits
                    ),
                )));
            }
            Ok((Value::Int(BigInt::from_literal(&text)), idx))
        }
    }

    /// The string whose opening quote is at `end - 1`, and the index after
    /// its closing quote.
    fn scanstring(&self, mut end: usize) -> Result<(PyStr, usize), PyErr> {
        let s = self.s;
        let len = s.len();
        let begin = end - 1;
        let mut out = PyStr::new();
        loop {
            let mut next = end;
            let mut c = 0u32;
            while next < len {
                c = s[next];
                if c == '"' as u32 || c == '\\' as u32 {
                    break;
                }
                if c <= 0x1F {
                    return Err(decode_error("Invalid control character at", s, next));
                }
                next += 1;
            }
            if next >= len || (c != '"' as u32 && c != '\\' as u32) {
                return Err(decode_error("Unterminated string starting at", s, begin));
            }
            out.0.extend_from_slice(&s[end..next]);
            next += 1;
            if c == '"' as u32 {
                return Ok((out, next));
            }
            if next == len {
                return Err(decode_error("Unterminated string starting at", s, begin));
            }
            let mut ch = s[next];
            if ch != 'u' as u32 {
                end = next + 1;
                ch = match char::from_u32(ch).unwrap_or('\0') {
                    '"' => '"' as u32,
                    '\\' => '\\' as u32,
                    '/' => '/' as u32,
                    'b' => 0x08,
                    'f' => 0x0C,
                    'n' => '\n' as u32,
                    'r' => '\r' as u32,
                    't' => '\t' as u32,
                    _ => return Err(decode_error("Invalid \\escape", s, end - 2)),
                };
            } else {
                next += 1;
                end = next + 4;
                if end >= len {
                    return Err(decode_error("Invalid \\uXXXX escape", s, next - 1));
                }
                ch = self.hex4(next, end)?;
                next = end;
                if (0xD800..=0xDBFF).contains(&ch)
                    && end + 6 < len
                    && s[next] == '\\' as u32
                    && s[next + 1] == 'u' as u32
                {
                    next += 2;
                    let end2 = end + 6;
                    let low = self.hex4(next, end2)?;
                    if (0xDC00..=0xDFFF).contains(&low) {
                        ch = 0x10000 + (((ch - 0xD800) << 10) | (low - 0xDC00));
                        end = end2;
                    }
                }
            }
            out.push_char(ch);
        }
    }

    /// Four hex digits ending at `end`.
    fn hex4(&self, from: usize, end: usize) -> Result<u32, PyErr> {
        let mut value = 0u32;
        for i in from..end {
            let digit = char::from_u32(self.s[i]).and_then(|c| c.to_digit(16));
            match digit {
                Some(d) => value = (value << 4) | d,
                None => return Err(decode_error("Invalid \\uXXXX escape", self.s, end - 5)),
            }
        }
        Ok(value)
    }

    fn skip_ws(&self, mut idx: usize) -> usize {
        while idx < self.s.len() && is_ws(self.s[idx]) {
            idx += 1;
        }
        idx
    }

    fn parse_object(&self, idx: usize) -> Result<(Value, usize), ScanErr> {
        let s = self.s;
        let len = s.len();
        let mut pairs: Vec<(PyStr, Value)> = Vec::new();
        let mut idx = self.skip_ws(idx);
        if idx >= len || s[idx] != '}' as u32 {
            loop {
                if idx >= len || s[idx] != '"' as u32 {
                    return Err(ScanErr::Raise(decode_error(
                        "Expecting property name enclosed in double quotes",
                        s,
                        idx,
                    )));
                }
                let (key, next) = self.scanstring(idx + 1)?;
                idx = self.skip_ws(next);
                if idx >= len || s[idx] != ':' as u32 {
                    return Err(ScanErr::Raise(decode_error(
                        "Expecting ':' delimiter",
                        s,
                        idx,
                    )));
                }
                idx = self.skip_ws(idx + 1);
                let (value, next) = self.scan_once(idx)?;
                dict_insert(&mut pairs, key, value);
                idx = self.skip_ws(next);
                if idx < len && s[idx] == '}' as u32 {
                    break;
                }
                if idx >= len || s[idx] != ',' as u32 {
                    return Err(ScanErr::Raise(decode_error(
                        "Expecting ',' delimiter",
                        s,
                        idx,
                    )));
                }
                idx = self.skip_ws(idx + 1);
            }
        }
        Ok((Value::Dict(pairs), idx + 1))
    }

    fn parse_array(&self, idx: usize) -> Result<(Value, usize), ScanErr> {
        let s = self.s;
        let len = s.len();
        let mut items = Vec::new();
        let mut idx = self.skip_ws(idx);
        if idx >= len || s[idx] != ']' as u32 {
            loop {
                let (value, next) = self.scan_once(idx)?;
                items.push(value);
                idx = self.skip_ws(next);
                if idx < len && s[idx] == ']' as u32 {
                    break;
                }
                if idx >= len || s[idx] != ',' as u32 {
                    return Err(ScanErr::Raise(decode_error(
                        "Expecting ',' delimiter",
                        s,
                        idx,
                    )));
                }
                idx = self.skip_ws(idx + 1);
            }
        }
        Ok((Value::List(items), idx + 1))
    }
}

/// `json.loads(text)`.
pub fn loads(text: &PyStr) -> Result<Value, PyErr> {
    let s = text.chars();
    if s.first() == Some(&0xFEFF) {
        return Err(decode_error(
            "Unexpected UTF-8 BOM (decode using utf-8-sig)",
            s,
            0,
        ));
    }
    let scanner = Scanner { s };
    let start = scanner.skip_ws(0);
    let (value, end) = match scanner.scan_once(start) {
        Ok(found) => found,
        Err(ScanErr::Stop(pos)) => return Err(decode_error("Expecting value", s, pos)),
        Err(ScanErr::Raise(e)) => return Err(e),
    };
    let end = scanner.skip_ws(end);
    if end != s.len() {
        return Err(decode_error("Extra data", s, end));
    }
    Ok(value)
}

// --- json.dumps -----------------------------------------------------------

fn encode_string(text: &PyStr, ensure_ascii: bool, out: &mut PyStr) {
    out.push_char('"' as u32);
    for &c in text.chars() {
        match c {
            0x22 => out.push_str("\\\""),
            0x5C => out.push_str("\\\\"),
            0x0A => out.push_str("\\n"),
            0x0D => out.push_str("\\r"),
            0x09 => out.push_str("\\t"),
            0x08 => out.push_str("\\b"),
            0x0C => out.push_str("\\f"),
            _ if c < 0x20 => out.push_str(&format!("\\u{:04x}", c)),
            _ if ensure_ascii && c > 0x7E => {
                if c > 0xFFFF {
                    let v = c - 0x10000;
                    out.push_str(&format!(
                        "\\u{:04x}\\u{:04x}",
                        0xD800 | ((v >> 10) & 0x3FF),
                        0xDC00 | (v & 0x3FF)
                    ));
                } else {
                    out.push_str(&format!("\\u{:04x}", c));
                }
            }
            _ => out.push_char(c),
        }
    }
    out.push_char('"' as u32);
}

fn float_json(f: f64) -> String {
    if f.is_nan() {
        "NaN".to_string()
    } else if f.is_infinite() {
        if f > 0.0 { "Infinity" } else { "-Infinity" }.to_string()
    } else {
        float_repr(f)
    }
}

fn dump_into(
    value: &Value,
    ensure_ascii: bool,
    indent: Option<usize>,
    level: usize,
    out: &mut PyStr,
) {
    match value {
        Value::Null => out.push_str("null"),
        Value::Bool(true) => out.push_str("true"),
        Value::Bool(false) => out.push_str("false"),
        Value::Int(i) => out.push_str(&i.repr()),
        Value::Float(f) => out.push_str(&float_json(*f)),
        Value::Str(text) => encode_string(text, ensure_ascii, out),
        Value::List(items) => {
            if items.is_empty() {
                out.push_str("[]");
                return;
            }
            out.push_str("[");
            for (i, item) in items.iter().enumerate() {
                separator(i, indent, level + 1, out);
                dump_into(item, ensure_ascii, indent, level + 1, out);
            }
            closing(indent, level, out);
            out.push_str("]");
        }
        Value::Dict(pairs) => {
            if pairs.is_empty() {
                out.push_str("{}");
                return;
            }
            out.push_str("{");
            for (i, (k, v)) in pairs.iter().enumerate() {
                separator(i, indent, level + 1, out);
                encode_string(k, ensure_ascii, out);
                out.push_str(": ");
                dump_into(v, ensure_ascii, indent, level + 1, out);
            }
            closing(indent, level, out);
            out.push_str("}");
        }
    }
}

fn separator(i: usize, indent: Option<usize>, level: usize, out: &mut PyStr) {
    match indent {
        None => {
            if i > 0 {
                out.push_str(", ");
            }
        }
        Some(width) => {
            if i > 0 {
                out.push_str(",");
            }
            out.push_str("\n");
            out.push_str(&" ".repeat(width * level));
        }
    }
}

fn closing(indent: Option<usize>, level: usize, out: &mut PyStr) {
    if let Some(width) = indent {
        out.push_str("\n");
        out.push_str(&" ".repeat(width * level));
    }
}

/// `json.dumps(value, ensure_ascii=..., indent=...)`.
pub fn dumps(value: &Value, ensure_ascii: bool, indent: Option<usize>) -> PyStr {
    let mut out = PyStr::new();
    dump_into(value, ensure_ascii, indent, 0, &mut out);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn load(text: &str) -> Result<Value, String> {
        loads(&PyStr::from(text)).map_err(|e| e.last_line())
    }

    fn err(text: &str) -> String {
        load(text)
            .unwrap_err()
            .trim_start_matches("json.decoder.JSONDecodeError: ")
            .to_string()
    }

    #[test]
    fn errors_are_the_c_scanners() {
        let cases = [
            (
                "\"\\ud83d\\ude00",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"\\ud83d\\u12\"",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"\\ud83d\\uzzzz\"x",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"abc\\u12\"",
                "Invalid \\uXXXX escape: line 1 column 6 (char 5)",
            ),
            (
                "\"\\u1234",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"\\",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            ("\"a\\q\"", "Invalid \\escape: line 1 column 3 (char 2)"),
            (
                "{\"a\":1,}",
                "Expecting property name enclosed in double quotes: line 1 column 8 (char 7)",
            ),
            ("[1,]", "Expecting value: line 1 column 4 (char 3)"),
            ("[", "Expecting value: line 1 column 2 (char 1)"),
            (
                "{",
                "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)",
            ),
            ("1.", "Extra data: line 1 column 2 (char 1)"),
            ("1e+", "Extra data: line 1 column 2 (char 1)"),
            ("-", "Expecting value: line 1 column 1 (char 0)"),
            ("nul", "Expecting value: line 1 column 1 (char 0)"),
            ("  ", "Expecting value: line 1 column 3 (char 2)"),
            (
                "\u{feff}1",
                "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)",
            ),
            ("[1 2]", "Expecting ',' delimiter: line 1 column 4 (char 3)"),
            (
                "{\"a\" 1}",
                "Expecting ':' delimiter: line 1 column 6 (char 5)",
            ),
            (
                "{\"a\":1 \"b\"}",
                "Expecting ',' delimiter: line 1 column 8 (char 7)",
            ),
            (
                "\"a\u{1}\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            ("1 x", "Extra data: line 1 column 3 (char 2)"),
            ("{\"a\":[}", "Expecting value: line 1 column 7 (char 6)"),
            ("\n\n  x", "Expecting value: line 3 column 3 (char 4)"),
        ];
        for (text, want) in cases {
            assert_eq!(err(text), want, "{:?}", text);
        }
    }

    #[test]
    fn values_and_dumps_round_trip_as_python() {
        let v = load("{\"a\": [1, 2.50, -0, -0.0, 1e400, NaN, true, null], \"b\": {}, \"a\": \"\\ud83d\\ude00\\u00e9\"}").unwrap();
        assert_eq!(
            dumps(&v, false, None).to_string_lossy(),
            "{\"a\": \"😀é\", \"b\": {}}"
        );
        assert_eq!(
            dumps(&v, true, None).to_string_lossy(),
            "{\"a\": \"\\ud83d\\ude00\\u00e9\", \"b\": {}}"
        );
        let w =
            load("[1, 2.50, -0, -0.0, 1e400, -Infinity, NaN, true, null, [], {\"k\": [\"x\"]}]")
                .unwrap();
        assert_eq!(
            dumps(&w, false, Some(2)).to_string_lossy(),
            "[\n  1,\n  2.5,\n  0,\n  -0.0,\n  Infinity,\n  -Infinity,\n  NaN,\n  true,\n  null,\n  [],\n  {\n    \"k\": [\n      \"x\"\n    ]\n  }\n]"
        );
        assert_eq!(
            w.py_repr().to_string_lossy(),
            "[1, 2.5, 0, -0.0, inf, -inf, nan, True, None, [], {'k': ['x']}]"
        );
    }

    #[test]
    fn float_repr_is_pythons() {
        let cases = [
            (1e16, "1e+16"),
            (1234567890123456.0, "1234567890123456.0"),
            (0.0001, "0.0001"),
            (1e-5, "1e-05"),
            (-0.0, "-0.0"),
            (0.0, "0.0"),
            (1.5e300, "1.5e+300"),
            (0.1, "0.1"),
            (123.456, "123.456"),
            (5e-324, "5e-324"),
        ];
        for (f, want) in cases {
            assert_eq!(float_repr(f), want);
        }
        assert_eq!(format_fixed1(0.25), "0.2");
        assert_eq!(format_fixed1(0.35), "0.3");
        assert_eq!(format_fixed1(2.25), "2.2");
        assert_eq!(format_fixed1(f64::NAN), "nan");
    }

    #[test]
    fn big_ints_compare_and_divide_exactly() {
        let big = BigInt::from_literal(&format!("1{}", "0".repeat(309)));
        assert_eq!(
            big.div_pow2(20).map(float_repr),
            Some("9.5367431640625e+302".to_string())
        );
        assert_eq!(
            BigInt::from_literal(&format!("1{}", "0".repeat(400))).div_pow2(10),
            None
        );
        assert_eq!(BigInt::from_i64(4000).div_pow2(10), Some(3.90625));
        assert_eq!(BigInt::from_i64(3).cmp_float(3.5), Some(Ordering::Less));
        assert_eq!(
            BigInt::from_i64(-3).cmp_float(-3.5),
            Some(Ordering::Greater)
        );
        assert_eq!(
            BigInt::from_i64(9007199254740993).cmp_float(9007199254740992.0),
            Some(Ordering::Greater)
        );
        assert!(load(&"1".repeat(4301))
            .unwrap_err()
            .starts_with("ValueError: Exceeds the limit (4300 digits)"));
    }

    #[test]
    fn python_type_errors() {
        let v = load("[1]").unwrap();
        assert_eq!(
            v.subscript("a").unwrap_err().last_line(),
            "TypeError: list indices must be integers or slices, not str"
        );
        assert_eq!(
            load("\"x\"")
                .unwrap()
                .subscript("a")
                .unwrap_err()
                .last_line(),
            "TypeError: string indices must be integers, not 'str'"
        );
        assert_eq!(
            load("null")
                .unwrap()
                .subscript("a")
                .unwrap_err()
                .last_line(),
            "TypeError: 'NoneType' object is not subscriptable"
        );
        assert_eq!(
            load("{}").unwrap().subscript("a").unwrap_err().last_line(),
            "KeyError: 'a'"
        );
        assert_eq!(
            load("5").unwrap().iterate().unwrap_err().last_line(),
            "TypeError: 'int' object is not iterable"
        );
        assert_eq!(
            v.get("a").unwrap_err().last_line(),
            "AttributeError: 'list' object has no attribute 'get'"
        );
        assert_eq!(
            s("a")
                .py_lt(&Value::Int(BigInt::from_i64(1)))
                .unwrap_err()
                .last_line(),
            "TypeError: '<' not supported between instances of 'str' and 'int'"
        );
        assert!(Value::Float(f64::NAN).py_eq(&Value::Float(f64::NAN)));
        assert!(Value::Bool(true).py_eq(&Value::Float(1.0)));
    }
}
