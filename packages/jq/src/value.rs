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

//! jq 1.8 JSON values and exact decimal (`decNumber`) numbers.

use std::cmp::Ordering;
use std::fmt;

use crate::error::{
    cannot_index_number, cannot_index_string, cannot_iterate, cannot_iterate_redacted,
};
use crate::order::{compare, jq_eq};

const MAX_EXP: i64 = 999_999_999;

/// decNumber subnormal exponent floor in jq 1.8 (`emin = -999_999_999`,
/// `digits = 147_483_648`, so `etiny = emin - (digits - 1) = -1_147_483_646`).
const ETINY: i64 = -1_147_483_646;

/// A jq 1.8 number: either an arbitrary-precision decimal (`decNumber` literal),
/// `+Infinity`, `-Infinity`, or `NaN`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Number {
    Finite {
        neg: bool,
        /// Significant decimal digits with leading zeros stripped (`"0"` for zero).
        digits: String,
        /// Base-10 exponent applied to `digits` as an integer (`123e-2` -> `"123"`, `-2`).
        exp: i64,
    },
    PosInf,
    NegInf,
    Nan,
}

impl Number {
    /// Parses a jq 1.8 number literal (`1.000`, `.5`, `1.`, `01`, `+1`, `Infinity`, `nan`, ...).
    pub fn parse(s: &str) -> Option<Number> {
        let bytes = s.as_bytes();
        if bytes.is_empty() {
            return None;
        }
        let (neg, body) = match bytes[0] {
            b'-' => (true, &s[1..]),
            b'+' => (false, &s[1..]),
            _ => (false, s),
        };
        if body.is_empty() {
            return None;
        }
        if body.eq_ignore_ascii_case("inf") || body.eq_ignore_ascii_case("infinity") {
            return Some(if neg { Number::NegInf } else { Number::PosInf });
        }
        if body.eq_ignore_ascii_case("nan") || body.eq_ignore_ascii_case("snan") {
            return Some(Number::Nan);
        }

        let b = body.as_bytes();
        let mut i = 0;
        let int_start = i;
        while i < b.len() && b[i].is_ascii_digit() {
            i += 1;
        }
        let int_part = &body[int_start..i];
        let mut frac_part = "";
        if i < b.len() && b[i] == b'.' {
            i += 1;
            let frac_start = i;
            while i < b.len() && b[i].is_ascii_digit() {
                i += 1;
            }
            frac_part = &body[frac_start..i];
        }
        if int_part.is_empty() && frac_part.is_empty() {
            return None;
        }

        let mut raw_exp: i128 = 0;
        if i < b.len() && (b[i] == b'e' || b[i] == b'E') {
            i += 1;
            let mut exp_neg = false;
            if i < b.len() && (b[i] == b'+' || b[i] == b'-') {
                exp_neg = b[i] == b'-';
                i += 1;
            }
            let exp_start = i;
            while i < b.len() && b[i].is_ascii_digit() {
                raw_exp = raw_exp
                    .saturating_mul(10)
                    .saturating_add((b[i] - b'0') as i128);
                i += 1;
            }
            if i == exp_start {
                return None;
            }
            if exp_neg {
                raw_exp = -raw_exp;
            }
        }
        if i != b.len() {
            return None;
        }

        let combined = if frac_part.is_empty() {
            int_part.to_string()
        } else {
            format!("{int_part}{frac_part}")
        };
        let trimmed = combined.trim_start_matches('0');
        let mut digits = if trimmed.is_empty() {
            "0".to_string()
        } else {
            trimmed.to_string()
        };

        let mut exp = raw_exp.saturating_sub(frac_part.len() as i128);
        if digits == "0" {
            exp = exp.clamp(ETINY as i128, MAX_EXP as i128);
        } else {
            let adj = exp.saturating_add(digits.len() as i128 - 1);
            if adj > MAX_EXP as i128 {
                return Some(if neg { Number::NegInf } else { Number::PosInf });
            }
            if exp < ETINY as i128 {
                let shift = (ETINY as i128).saturating_sub(exp);
                digits = round_half_up_right(&digits, shift);
                exp = ETINY as i128;
            }
        }
        Some(Number::Finite {
            neg,
            digits,
            exp: exp as i64,
        })
    }

    /// Creates a decimal number from `i64`.
    pub fn from_i64(n: i64) -> Number {
        let neg = n < 0;
        let digits = n.unsigned_abs().to_string();
        Number::Finite {
            neg,
            digits,
            exp: 0,
        }
    }

    /// Creates a decimal number from `u64`.
    pub fn from_u64(n: u64) -> Number {
        Number::Finite {
            neg: false,
            digits: n.to_string(),
            exp: 0,
        }
    }

    /// Creates a decimal number from `i128`.
    pub fn from_i128(n: i128) -> Number {
        let neg = n < 0;
        let digits = n.unsigned_abs().to_string();
        Number::Finite {
            neg,
            digits,
            exp: 0,
        }
    }

    /// Creates a decimal number from `usize`.
    pub fn from_usize(n: usize) -> Number {
        Number::Finite {
            neg: false,
            digits: n.to_string(),
            exp: 0,
        }
    }

    /// Creates a jq number from `f64` (`NaN` -> `Nan`, infinities preserved, `-0.0` -> `-0`).
    pub fn from_f64(n: f64) -> Number {
        if n.is_nan() {
            return Number::Nan;
        }
        if n.is_infinite() {
            return if n.is_sign_negative() {
                Number::NegInf
            } else {
                Number::PosInf
            };
        }
        if n == 0.0 {
            return Number::Finite {
                neg: n.is_sign_negative(),
                digits: "0".to_string(),
                exp: 0,
            };
        }
        Number::parse(&n.to_string()).unwrap_or(Number::Nan)
    }

    pub fn is_nan(&self) -> bool {
        matches!(self, Number::Nan)
    }

    pub fn is_infinite(&self) -> bool {
        matches!(self, Number::PosInf | Number::NegInf)
    }

    pub fn is_zero(&self) -> bool {
        matches!(self, Number::Finite { digits, .. } if digits == "0")
    }

    /// Converts to `i64` if this number is a finite integer within `i64` range.
    pub fn as_i64(&self) -> Option<i64> {
        let int_str = self.exact_int_string()?;
        int_str.parse::<i64>().ok()
    }

    /// Converts to `u64` if this number is a non-negative finite integer within `u64` range.
    pub fn as_u64(&self) -> Option<u64> {
        let int_str = self.exact_int_string()?;
        int_str.parse::<u64>().ok()
    }

    /// Converts to `f64` (`Nan` -> `f64::NAN`, `PosInf`/`NegInf` -> `+-INFINITY`).
    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Number::Nan => Some(f64::NAN),
            Number::PosInf => Some(f64::INFINITY),
            Number::NegInf => Some(f64::NEG_INFINITY),
            Number::Finite { .. } => self.fmt_jq().parse::<f64>().ok(),
        }
    }

    /// Converts finite numbers toward zero (`trunc`) for jq array indexing (`1.5 -> 1`, `-1.5 -> -1`).
    pub(crate) fn trunc_to_isize(&self) -> Option<isize> {
        match self {
            Number::Finite { neg, digits, exp } => {
                if digits == "0" {
                    return Some(0);
                }
                if *exp >= 0 {
                    if *exp > 20 || digits.len() + (*exp as usize) > 20 {
                        return None;
                    }
                    let s = format!(
                        "{}{}{}",
                        if *neg { "-" } else { "" },
                        digits,
                        "0".repeat(*exp as usize)
                    );
                    s.parse::<isize>().ok()
                } else {
                    let drop = (-*exp) as usize;
                    if drop >= digits.len() {
                        Some(0)
                    } else {
                        let s = format!(
                            "{}{}",
                            if *neg { "-" } else { "" },
                            &digits[..digits.len() - drop]
                        );
                        s.parse::<isize>().ok()
                    }
                }
            }
            _ => None,
        }
    }

    fn exact_int_string(&self) -> Option<String> {
        let Number::Finite { neg, digits, exp } = self else {
            return None;
        };
        if digits == "0" {
            return Some("0".to_string());
        }
        if *exp >= 0 {
            let e = *exp as usize;
            if digits.len().saturating_add(e) > 40 {
                return None;
            }
            Some(format!(
                "{}{}{}",
                if *neg { "-" } else { "" },
                digits,
                "0".repeat(e)
            ))
        } else {
            let frac_len = (-*exp) as usize;
            if frac_len >= digits.len() {
                return None;
            }
            let (int_part, frac_part) = digits.split_at(digits.len() - frac_len);
            if frac_part.bytes().any(|b| b != b'0') {
                return None;
            }
            Some(format!("{}{}", if *neg { "-" } else { "" }, int_part))
        }
    }

    /// Formats the number in jq 1.8's decNumber canonical representation.
    pub fn fmt_jq(&self) -> String {
        match self {
            Number::Nan => "null".to_string(),
            Number::PosInf => "1.7976931348623157e+308".to_string(),
            Number::NegInf => "-1.7976931348623157e+308".to_string(),
            Number::Finite { neg, digits, exp } => {
                let n = digits.len() as i128;
                let e = *exp as i128;
                let adjusted = e + n - 1;
                let mut out = String::new();
                if *neg {
                    out.push('-');
                }
                if e <= 0 && adjusted >= -6 {
                    if e == 0 {
                        out.push_str(digits);
                    } else {
                        let pos = n + e;
                        if pos > 0 {
                            let split = pos as usize;
                            out.push_str(&digits[..split]);
                            out.push('.');
                            out.push_str(&digits[split..]);
                        } else {
                            out.push_str("0.");
                            for _ in 0..(-pos as usize) {
                                out.push('0');
                            }
                            out.push_str(digits);
                        }
                    }
                } else {
                    out.push(digits.as_bytes()[0] as char);
                    if digits.len() > 1 {
                        out.push('.');
                        out.push_str(&digits[1..]);
                    }
                    out.push('E');
                    if adjusted < 0 {
                        out.push('-');
                    } else {
                        out.push('+');
                    }
                    out.push_str(&adjusted.unsigned_abs().to_string());
                }
                out
            }
        }
    }

    /// Compares two numbers according to jq 1.8's total order:
    /// `NaN < -Infinity < negative finites < 0 (-0 == 0) < positive finites < +Infinity`.
    pub fn cmp_jq(&self, other: &Self) -> Ordering {
        fn num_class(n: &Number) -> u8 {
            match n {
                Number::Nan => 0,
                Number::NegInf => 1,
                Number::Finite { digits, .. } if digits == "0" => 3,
                Number::Finite { neg: true, .. } => 2,
                Number::Finite { neg: false, .. } => 4,
                Number::PosInf => 5,
            }
        }
        let ca = num_class(self);
        let cb = num_class(other);
        if ca != cb {
            return ca.cmp(&cb);
        }
        match (self, other) {
            (
                Number::Finite {
                    neg,
                    digits: da,
                    exp: ea,
                },
                Number::Finite {
                    digits: db,
                    exp: eb,
                    ..
                },
            ) => {
                if da == "0" && db == "0" {
                    return Ordering::Equal;
                }
                let mag = compare_positive_finite(da, *ea, db, *eb);
                if *neg {
                    mag.reverse()
                } else {
                    mag
                }
            }
            _ => Ordering::Equal,
        }
    }

    /// jq `==` semantics on numbers (`1 == 1.0`, `-0 == 0`, `nan != nan`, `1e309 != Infinity`).
    pub fn jq_eq(&self, other: &Self) -> bool {
        if self.is_nan() || other.is_nan() {
            return false;
        }
        self.cmp_jq(other) == Ordering::Equal
    }
}

fn round_half_up_right(digits: &str, shift: i128) -> String {
    let len = digits.len();
    if shift > len as i128 {
        return "0".to_string();
    }
    let bytes = digits.as_bytes();
    if shift == len as i128 {
        return if bytes[0] >= b'5' { "1" } else { "0" }.to_string();
    }
    let keep = len - shift as usize;
    let mut out = bytes[..keep].to_vec();
    if bytes[keep] >= b'5' {
        let mut carry = true;
        for b in out.iter_mut().rev() {
            if *b < b'9' {
                *b += 1;
                carry = false;
                break;
            }
            *b = b'0';
        }
        if carry {
            out.insert(0, b'1');
        }
    }
    String::from_utf8(out).expect("decimal ASCII digits")
}

fn compare_positive_finite(da: &str, ea: i64, db: &str, eb: i64) -> Ordering {
    let sci_a = (ea as i128) + (da.len() as i128) - 1;
    let sci_b = (eb as i128) + (db.len() as i128) - 1;
    if sci_a != sci_b {
        return sci_a.cmp(&sci_b);
    }
    let sa = da.trim_end_matches('0').as_bytes();
    let sb = db.trim_end_matches('0').as_bytes();
    sa.cmp(sb)
}

impl fmt::Display for Number {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.fmt_jq())
    }
}

/// A jq 1.8 JSON value, preserving object key insertion order (repeated keys keep
/// their first position and take the last value).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Value {
    Null,
    Bool(bool),
    Number(Number),
    String(String),
    Array(Vec<Value>),
    Object(Vec<(String, Value)>),
}

impl Value {
    /// Constructs a `Value::String`.
    pub fn str(s: impl Into<String>) -> Value {
        Value::String(s.into())
    }

    /// Constructs a `Value::Number` from `i64`.
    pub fn int(n: i64) -> Value {
        Value::Number(Number::from_i64(n))
    }

    /// Constructs a `Value::Number` from `u64`.
    pub fn uint(n: u64) -> Value {
        Value::Number(Number::from_u64(n))
    }

    /// Constructs a `Value::Number` from `f64`.
    pub fn float(n: f64) -> Value {
        Value::Number(Number::from_f64(n))
    }

    /// Constructs a `Value::Object`, deduplicating repeated keys (first position, last value).
    pub fn object(entries: impl IntoIterator<Item = (String, Value)>) -> Value {
        let mut out: Vec<(String, Value)> = Vec::new();
        for (k, v) in entries {
            if let Some(slot) = out.iter_mut().find(|(ek, _)| *ek == k) {
                slot.1 = v;
            } else {
                out.push((k, v));
            }
        }
        Value::Object(out)
    }

    /// Decodes a `--arg` byte slice the way jq does (non-UTF-8 replaced by U+FFFD).
    pub fn arg(bytes: &[u8]) -> Value {
        Value::String(String::from_utf8_lossy(bytes).into_owned())
    }

    /// Returns jq's type name (`"null"`, `"boolean"`, `"number"`, `"string"`, `"array"`, `"object"`).
    pub fn kind(&self) -> &'static str {
        match self {
            Value::Null => "null",
            Value::Bool(_) => "boolean",
            Value::Number(_) => "number",
            Value::String(_) => "string",
            Value::Array(_) => "array",
            Value::Object(_) => "object",
        }
    }

    /// Returns jq truthiness (`false` and `null` are falsy; everything else is truthy).
    pub fn truthy(&self) -> bool {
        !matches!(self, Value::Null | Value::Bool(false))
    }

    pub fn is_null(&self) -> bool {
        matches!(self, Value::Null)
    }

    pub fn is_str(&self, s: &str) -> bool {
        matches!(self, Value::String(v) if v == s)
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::String(s) => Some(s.as_str()),
            _ => None,
        }
    }

    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Value::Bool(b) => Some(*b),
            _ => None,
        }
    }

    pub fn as_i64(&self) -> Option<i64> {
        match self {
            Value::Number(n) => n.as_i64(),
            _ => None,
        }
    }

    pub fn as_u64(&self) -> Option<u64> {
        match self {
            Value::Number(n) => n.as_u64(),
            _ => None,
        }
    }

    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Value::Number(n) => n.as_f64(),
            _ => None,
        }
    }

    pub fn as_array(&self) -> Option<&[Value]> {
        match self {
            Value::Array(items) => Some(items.as_slice()),
            _ => None,
        }
    }

    pub fn as_array_mut(&mut self) -> Option<&mut Vec<Value>> {
        match self {
            Value::Array(items) => Some(items),
            _ => None,
        }
    }

    pub fn as_object(&self) -> Option<&[(String, Value)]> {
        match self {
            Value::Object(entries) => Some(entries.as_slice()),
            _ => None,
        }
    }

    pub fn as_object_mut(&mut self) -> Option<&mut Vec<(String, Value)>> {
        match self {
            Value::Object(entries) => Some(entries),
            _ => None,
        }
    }

    /// Looks up `key` on an object without cloning, returning `None` if absent or non-object.
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Object(entries) => entries.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    /// Looks up a mutable reference to `key` on an object.
    pub fn get_mut(&mut self, key: &str) -> Option<&mut Value> {
        match self {
            Value::Object(entries) => entries.iter_mut().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    /// Sets `key` on an object (updating in place if present, appending otherwise).
    /// Returns `true` if `self` is an object.
    pub fn set(&mut self, key: impl Into<String>, value: Value) -> bool {
        let key = key.into();
        match self {
            Value::Object(entries) => {
                if let Some(slot) = entries.iter_mut().find(|(k, _)| *k == key) {
                    slot.1 = value;
                } else {
                    entries.push((key, value));
                }
                true
            }
            _ => false,
        }
    }

    /// `.key`: field on an object (`Null` when absent), `Null` on `Null`, or jq 1.8 index error.
    pub fn index(&self, key: &str) -> Result<Value, String> {
        match self {
            Value::Null => Ok(Value::Null),
            Value::Object(entries) => Ok(entries
                .iter()
                .find(|(k, _)| k == key)
                .map(|(_, v)| v.clone())
                .unwrap_or(Value::Null)),
            other => Err(cannot_index_string(other.kind(), key)),
        }
    }

    /// `.[i]`: element on an array (supporting negative indices from the end; `Null` out of
    /// bounds), `Null` on `Null`, or jq 1.8 index error.
    pub fn index_num(&self, idx: isize) -> Result<Value, String> {
        self.index_number(&Number::from_i128(idx as i128))
    }

    /// `.[n]` with a jq `Number` index (truncating toward zero on arrays, preserving exact number
    /// formatting in error messages).
    pub fn index_number(&self, idx: &Number) -> Result<Value, String> {
        match self {
            Value::Null => Ok(Value::Null),
            Value::Array(items) => Ok(resolve_array_index(items.len(), idx)
                .and_then(|pos| items.get(pos).cloned())
                .unwrap_or(Value::Null)),
            other => Err(cannot_index_number(other.kind(), idx)),
        }
    }

    /// `.[]`: array elements or object values in order, or jq 1.8 iterate error.
    pub fn iterate(&self) -> Result<Vec<Value>, String> {
        match self {
            Value::Array(items) => Ok(items.clone()),
            Value::Object(entries) => Ok(entries.iter().map(|(_, v)| v.clone()).collect()),
            other => Err(cannot_iterate(other)),
        }
    }

    /// `.[]` for credential-handling tools: array elements or object values in
    /// order, or `Cannot iterate over <kind>` without quoting the value.
    ///
    /// Deliberate exception to jq 1.8.2: jq 1.8.2 prints
    /// `Cannot iterate over <kind> (<truncated value>)` (e.g.
    /// `Cannot iterate over string ("postgres://user:SECRET-M...")`). Because a
    /// bare-string response from a credential endpoint can contain a username,
    /// password, token, or key, this method omits the value while keeping jq's
    /// runtime error semantics and exit code 5. Non-secret tools should use
    /// [`Value::iterate`] for full jq 1.8.2 error parity.
    pub fn iterate_redacted(&self) -> Result<Vec<Value>, String> {
        match self {
            Value::Array(items) => Ok(items.clone()),
            Value::Object(entries) => Ok(entries.iter().map(|(_, v)| v.clone()).collect()),
            other => Err(cannot_iterate_redacted(other)),
        }
    }

    /// `.[]?`: array elements or object values; empty vec on anything else.
    pub fn iterate_opt(&self) -> Vec<Value> {
        match self {
            Value::Array(items) => items.clone(),
            Value::Object(entries) => entries.iter().map(|(_, v)| v.clone()).collect(),
            _ => Vec::new(),
        }
    }

    /// `del(.key)`: removes `key` from an object (`Null` stays `Null`); errors on anything else.
    pub fn del_key(&mut self, key: &str) -> Result<(), String> {
        match self {
            Value::Null => Ok(()),
            Value::Object(entries) => {
                entries.retain(|(k, _)| k != key);
                Ok(())
            }
            other => Err(cannot_index_string(other.kind(), key)),
        }
    }

    /// `del(.[i])`: removes element `i` from an array (`Null` stays `Null`, out-of-range is a
    /// no-op); errors on anything else.
    pub fn del_index(&mut self, idx: isize) -> Result<(), String> {
        let num = Number::from_i128(idx as i128);
        match self {
            Value::Null => Ok(()),
            Value::Array(items) => {
                if let Some(pos) = resolve_array_index(items.len(), &num) {
                    if pos < items.len() {
                        items.remove(pos);
                    }
                }
                Ok(())
            }
            other => Err(cannot_index_number(other.kind(), &num)),
        }
    }

    /// jq `==` equality.
    pub fn jq_eq(&self, other: &Value) -> bool {
        jq_eq(self, other)
    }

    /// jq total ordering.
    pub fn jq_cmp(&self, other: &Value) -> Ordering {
        compare(self, other)
    }
}

fn resolve_array_index(len: usize, idx: &Number) -> Option<usize> {
    let i = idx.trunc_to_isize()?;
    if i >= 0 {
        usize::try_from(i).ok()
    } else {
        let rev = i.unsigned_abs();
        len.checked_sub(rev)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn number_parse_and_format_matches_jq_18() {
        let cases = [
            ("0", "0"),
            ("-0", "-0"),
            ("0.0", "0.0"),
            ("-0.0", "-0.0"),
            ("1.000", "1.000"),
            ("01", "1"),
            ("+1", "1"),
            (".5", "0.5"),
            ("-.5", "-0.5"),
            ("1.", "1"),
            ("1.e2", "1E+2"),
            (".5e2", "5E+1"),
            ("1E2", "1E+2"),
            ("0.1e1", "1"),
            ("0.10", "0.10"),
            ("0.000001", "0.000001"),
            ("0.0000001", "1E-7"),
            ("0.0000010", "0.0000010"),
            ("0.0000000", "0E-7"),
            ("0e5", "0E+5"),
            ("0e-6", "0.000000"),
            ("0e-7", "0E-7"),
            ("0.0e-6", "0E-7"),
            ("123e-2", "1.23"),
            ("-1.20E+3", "-1.20E+3"),
            ("0e1000000000", "0E+999999999"),
            ("1e1000000000", "1.7976931348623157e+308"),
            ("-1e1000000000", "-1.7976931348623157e+308"),
            ("1e-1000000000", "1E-1000000000"),
            ("100000000000000000001", "100000000000000000001"),
            ("Infinity", "1.7976931348623157e+308"),
            ("-inf", "-1.7976931348623157e+308"),
            ("NaN", "null"),
            ("-snan", "null"),
        ];
        for (raw, want) in cases {
            let n = Number::parse(raw).unwrap_or_else(|| panic!("failed to parse {raw}"));
            assert_eq!(n.fmt_jq(), want, "{raw}");
        }
        for bad in ["", "-", "+", ".", "-.", "1e", "1e+", "nan123", "1a"] {
            assert!(Number::parse(bad).is_none(), "{bad}");
        }
    }

    #[test]
    fn exponent_floor_etiny_and_ceiling_emax_match_jq_182() {
        let cases = [
            // Ceiling (emax = 999_999_999)
            ("1e999999999", "1E+999999999"),
            ("1e1000000000", "1.7976931348623157e+308"),
            ("10e999999998", "1.0E+999999999"),
            ("10e999999999", "1.7976931348623157e+308"),
            ("0.1e1000000000", "1E+999999999"),
            ("0.1e1000000001", "1.7976931348623157e+308"),
            ("0.0e999999999", "0E+999999998"),
            ("0.0e1000000000", "0E+999999999"),
            ("0.0e1000000001", "0E+999999999"),
            ("-0e1000000000", "-0E+999999999"),
            // Floor (etiny = -1_147_483_646, DEC_ROUND_HALF_UP)
            ("1e-1147483646", "1E-1147483646"),
            ("1e-1147483647", "0E-1147483646"),
            ("-1e-1147483646", "-1E-1147483646"),
            ("-1e-1147483647", "-0E-1147483646"),
            ("0e-1147483646", "0E-1147483646"),
            ("0e-1147483647", "0E-1147483646"),
            ("-0e-1147483647", "-0E-1147483646"),
            ("0.00e-1147483645", "0E-1147483646"),
            ("4e-1147483647", "0E-1147483646"),
            ("5e-1147483647", "1E-1147483646"),
            ("-5e-1147483647", "-1E-1147483646"),
            ("5e-1147483648", "0E-1147483646"),
            ("12e-1147483647", "1E-1147483646"),
            ("15e-1147483647", "2E-1147483646"),
            ("25e-1147483647", "3E-1147483646"),
            ("9.5e-1147483646", "1.0E-1147483645"),
            ("99.5e-1147483646", "1.00E-1147483644"),
            ("1.23456e-1147483641", "1.23456E-1147483641"),
            ("1.23456e-1147483642", "1.2346E-1147483642"),
            ("1.23456e-1147483646", "1E-1147483646"),
            ("1.23456e-1147483647", "0E-1147483646"),
            ("0.00000000001e-1147483635", "1E-1147483646"),
            ("0.00000000001e-1147483636", "0E-1147483646"),
            ("1e-99999999999999999999", "0E-1147483646"),
        ];
        for (raw, want) in cases {
            let n = Number::parse(raw).unwrap_or_else(|| panic!("failed to parse {raw}"));
            assert_eq!(n.fmt_jq(), want, "{raw}");
        }
        assert!(Number::parse("1e-1147483647")
            .unwrap()
            .jq_eq(&Number::from_i64(0)));
        assert!(!Number::parse("1e-1147483646")
            .unwrap()
            .jq_eq(&Number::from_i64(0)));
    }

    #[test]
    fn value_index_iterate_and_del() {
        let mut obj = Value::object([
            ("a".into(), Value::int(1)),
            ("b".into(), Value::int(2)),
            ("a".into(), Value::int(3)),
        ]);
        assert_eq!(obj.index("a").unwrap(), Value::int(3));
        assert_eq!(obj.index("missing").unwrap(), Value::Null);
        assert_eq!(Value::Null.index("x").unwrap(), Value::Null);
        assert_eq!(
            Value::int(5).index("x").unwrap_err(),
            "Cannot index number with string (\"x\")"
        );

        let arr = Value::Array(vec![Value::int(10), Value::int(20), Value::int(30)]);
        assert_eq!(arr.index_num(0).unwrap(), Value::int(10));
        assert_eq!(arr.index_num(-1).unwrap(), Value::int(30));
        assert_eq!(arr.index_num(-4).unwrap(), Value::Null);
        assert_eq!(
            arr.index_number(&Number::parse("1.5").unwrap()).unwrap(),
            Value::int(20)
        );
        assert_eq!(
            arr.index_number(&Number::parse("-0.5").unwrap()).unwrap(),
            Value::int(10)
        );
        assert_eq!(
            obj.index_number(&Number::parse("1.5").unwrap())
                .unwrap_err(),
            "Cannot index object with number (1.5)"
        );

        assert_eq!(obj.iterate().unwrap(), vec![Value::int(3), Value::int(2)]);
        assert_eq!(
            Value::Null.iterate().unwrap_err(),
            "Cannot iterate over null (null)"
        );
        assert!(Value::Null.iterate_opt().is_empty());

        obj.del_key("a").unwrap();
        assert_eq!(obj, Value::object([("b".into(), Value::int(2))]));
        assert_eq!(
            Value::int(5).del_key("a").unwrap_err(),
            "Cannot index number with string (\"a\")"
        );
    }

    #[test]
    fn iterate_redacted_omits_values() {
        let arr = Value::Array(vec![Value::int(1), Value::str("x")]);
        assert_eq!(
            arr.iterate_redacted().unwrap(),
            vec![Value::int(1), Value::str("x")]
        );
        let obj = Value::object([("a".into(), Value::int(1)), ("b".into(), Value::int(2))]);
        assert_eq!(
            obj.iterate_redacted().unwrap(),
            vec![Value::int(1), Value::int(2)]
        );
        assert_eq!(
            Value::str("postgres://user:SECRET-MARKER-123@host/db")
                .iterate_redacted()
                .unwrap_err(),
            "Cannot iterate over string"
        );
        assert_eq!(
            Value::int(42).iterate_redacted().unwrap_err(),
            "Cannot iterate over number"
        );
        assert_eq!(
            Value::Null.iterate_redacted().unwrap_err(),
            "Cannot iterate over null"
        );
        assert_eq!(
            Value::Bool(false).iterate_redacted().unwrap_err(),
            "Cannot iterate over boolean"
        );
    }
}
