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

//! The values json.load gives release_scope.py, and what Python does with
//! them: truth, ==, <, repr() and str(), iteration, `.get` and `[...]`, and
//! the exception each raises on a value of the wrong type. The configs and
//! the pull request are other people's files, so a wrong type is an input
//! like any other, and the port must fail where and as the script fails.

use crate::pystr::PyStr;
use std::cmp::Ordering;

/// An exception, by the class Python would raise.
#[derive(Clone, Debug, PartialEq)]
pub enum Exc {
    /// release_scope.Misconfigured: the check cannot tell.
    Misconfigured(PyStr),
    /// OSError, already formatted: `[Errno 2] No such file or directory: 'x'`.
    OsError(PyStr),
    /// ValueError and its kinds (JSONDecodeError, UnicodeDecodeError).
    ValueError(PyStr),
    /// KeyError, holding repr() of the key.
    KeyError(PyStr),
    TypeError(PyStr),
    AttributeError(PyStr),
    RecursionError(PyStr),
    UnicodeEncodeError(PyStr),
}

impl Exc {
    pub fn type_error(msg: &str) -> Exc {
        Exc::TypeError(PyStr::from(msg))
    }

    pub fn attribute(value: &PyVal, attr: &str) -> Exc {
        Exc::AttributeError(PyStr::from(
            format!("'{}' object has no attribute '{}'", value.type_name(), attr).as_str(),
        ))
    }

    /// The name a traceback's last line starts with.
    pub fn class(&self) -> &'static str {
        match self {
            Exc::Misconfigured(_) => "Misconfigured",
            Exc::OsError(_) => "OSError",
            Exc::ValueError(_) => "ValueError",
            Exc::KeyError(_) => "KeyError",
            Exc::TypeError(_) => "TypeError",
            Exc::AttributeError(_) => "AttributeError",
            Exc::RecursionError(_) => "RecursionError",
            Exc::UnicodeEncodeError(_) => "UnicodeEncodeError",
        }
    }

    /// str(exception).
    pub fn message(&self) -> &PyStr {
        match self {
            Exc::Misconfigured(m)
            | Exc::OsError(m)
            | Exc::ValueError(m)
            | Exc::KeyError(m)
            | Exc::TypeError(m)
            | Exc::AttributeError(m)
            | Exc::RecursionError(m)
            | Exc::UnicodeEncodeError(m) => m,
        }
    }

    /// repr(exception), for the KeyError and TypeError load_aliases turns
    /// into a message.
    pub fn repr(&self) -> PyStr {
        let mut out = PyStr::from(self.class());
        out.push_str("(");
        match self {
            Exc::KeyError(key) => out.push_py(key),
            other => out.push_py(&other.message().repr()),
        }
        out.push_str(")");
        out
    }

    /// The exceptions main() catches and reports as "could not tell".
    pub fn caught_by_main(&self) -> bool {
        matches!(
            self,
            Exc::Misconfigured(_) | Exc::OsError(_) | Exc::ValueError(_)
        )
    }
}

/// A Python int of any size, in decimal.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PyInt {
    pub negative: bool,
    /// Most significant first, no leading zeros; zero is `[0]`.
    pub digits: Vec<u8>,
}

impl PyInt {
    pub fn from_decimal(text: &str) -> PyInt {
        let (negative, body) = match text.strip_prefix('-') {
            Some(rest) => (true, rest),
            None => (false, text),
        };
        let mut digits: Vec<u8> = body
            .bytes()
            .map(|b| b - b'0')
            .skip_while(|&d| d == 0)
            .collect();
        if digits.is_empty() {
            digits.push(0);
        }
        let zero = digits == [0];
        PyInt {
            negative: negative && !zero,
            digits,
        }
    }

    pub fn small(n: u64) -> PyInt {
        PyInt::from_decimal(&n.to_string())
    }

    fn is_zero(&self) -> bool {
        self.digits == [0]
    }

    fn cmp_magnitude(a: &[u8], b: &[u8]) -> Ordering {
        a.len().cmp(&b.len()).then_with(|| a.cmp(b))
    }

    fn cmp(&self, other: &PyInt) -> Ordering {
        match (self.negative, other.negative) {
            (false, true) => Ordering::Greater,
            (true, false) => Ordering::Less,
            (false, false) => PyInt::cmp_magnitude(&self.digits, &other.digits),
            (true, true) => PyInt::cmp_magnitude(&other.digits, &self.digits),
        }
    }

    pub fn repr(&self) -> String {
        let mut out = String::new();
        if self.negative {
            out.push('-');
        }
        out.extend(self.digits.iter().map(|&d| (b'0' + d) as char));
        out
    }
}

/// The exact decimal digits of a finite float's integer part, |x|.
fn float_integer_digits(x: f64) -> Vec<u8> {
    let x = x.abs().trunc();
    if x < 18446744073709551616.0 {
        return PyInt::small(x as u64).digits;
    }
    let bits = x.to_bits();
    let exponent = ((bits >> 52) & 0x7FF) as i32 - 1075;
    let mantissa = (bits & ((1u64 << 52) - 1)) | (1u64 << 52);
    // mantissa * 2^exponent, exponent > 0 here, in base 10^9 limbs.
    let mut limbs: Vec<u64> = vec![mantissa % 1_000_000_000, mantissa / 1_000_000_000];
    for _ in 0..exponent {
        let mut carry = 0;
        for limb in limbs.iter_mut() {
            let v = *limb * 2 + carry;
            *limb = v % 1_000_000_000;
            carry = v / 1_000_000_000;
        }
        if carry > 0 {
            limbs.push(carry);
        }
    }
    let mut text = String::new();
    for (i, limb) in limbs.iter().rev().enumerate() {
        if i == 0 {
            text.push_str(&limb.to_string());
        } else {
            text.push_str(&format!("{:09}", limb));
        }
    }
    PyInt::from_decimal(&text).digits
}

/// int against float, exactly, as Python compares them. None when x is NaN.
fn cmp_int_float(i: &PyInt, x: f64) -> Option<Ordering> {
    if x.is_nan() {
        return None;
    }
    if x.is_infinite() {
        return Some(if x > 0.0 {
            Ordering::Less
        } else {
            Ordering::Greater
        });
    }
    let whole = PyInt {
        negative: x < 0.0 && x.trunc() != 0.0,
        digits: float_integer_digits(x),
    };
    match i.cmp(&whole) {
        Ordering::Equal => {
            let frac = x - x.trunc();
            Some(if frac == 0.0 {
                Ordering::Equal
            } else if frac > 0.0 {
                Ordering::Less
            } else {
                Ordering::Greater
            })
        }
        other => Some(other),
    }
}

/// repr(float): the shortest digits that read back as the same float, laid
/// out as Python lays them out.
pub fn float_repr(x: f64) -> String {
    if x.is_nan() {
        return "nan".into();
    }
    if x.is_infinite() {
        return if x > 0.0 { "inf".into() } else { "-inf".into() };
    }
    let text = format!("{:e}", x.abs());
    let (mantissa, exponent) = text.split_once('e').expect("{:e} has an e");
    let exponent: i32 = exponent.parse().expect("{:e} exponent");
    let digits: String = mantissa.chars().filter(|c| *c != '.').collect();
    let n = digits.len() as i32;
    let point = exponent + 1;
    let body = if point <= -4 || point > 16 {
        let mut m = digits[..1].to_string();
        if n > 1 {
            m.push('.');
            m.push_str(&digits[1..]);
        }
        let e = point - 1;
        format!("{}e{}{:02}", m, if e < 0 { '-' } else { '+' }, e.abs())
    } else if point <= 0 {
        format!("0.{}{}", "0".repeat((-point) as usize), digits)
    } else if point >= n {
        format!("{}{}.0", digits, "0".repeat((point - n) as usize))
    } else {
        format!(
            "{}.{}",
            &digits[..point as usize],
            &digits[point as usize..]
        )
    };
    if x.is_sign_negative() {
        format!("-{}", body)
    } else {
        body
    }
}

/// A JSON object, keys in the order the file gives them, as a Python dict
/// keeps them (a repeated key keeps its first place and its last value).
#[derive(Clone, Debug, Default)]
pub struct Dict(pub Vec<(PyStr, PyVal)>);

impl Dict {
    pub fn get(&self, key: &str) -> Option<&PyVal> {
        self.0.iter().find(|(k, _)| k.eq_str(key)).map(|(_, v)| v)
    }

    pub fn insert(&mut self, key: PyStr, value: PyVal) {
        match self.0.iter_mut().find(|(k, _)| *k == key) {
            Some(slot) => slot.1 = value,
            None => self.0.push((key, value)),
        }
    }
}

#[derive(Clone, Debug)]
pub enum PyVal {
    None,
    Bool(bool),
    Int(PyInt),
    Float(f64),
    Str(PyStr),
    List(Vec<PyVal>),
    Dict(Dict),
}

enum Num<'a> {
    Int(std::borrow::Cow<'a, PyInt>),
    Float(f64),
}

impl PyVal {
    pub fn str(s: &str) -> PyVal {
        PyVal::Str(PyStr::from(s))
    }

    pub fn type_name(&self) -> &'static str {
        match self {
            PyVal::None => "NoneType",
            PyVal::Bool(_) => "bool",
            PyVal::Int(_) => "int",
            PyVal::Float(_) => "float",
            PyVal::Str(_) => "str",
            PyVal::List(_) => "list",
            PyVal::Dict(_) => "dict",
        }
    }

    pub fn truthy(&self) -> bool {
        match self {
            PyVal::None => false,
            PyVal::Bool(b) => *b,
            PyVal::Int(i) => !i.is_zero(),
            PyVal::Float(x) => *x != 0.0,
            PyVal::Str(s) => !s.is_empty(),
            PyVal::List(l) => !l.is_empty(),
            PyVal::Dict(d) => !d.0.is_empty(),
        }
    }

    pub fn as_str(&self) -> Option<&PyStr> {
        match self {
            PyVal::Str(s) => Some(s),
            _ => None,
        }
    }

    fn num(&self) -> Option<Num<'_>> {
        match self {
            PyVal::Bool(b) => Some(Num::Int(std::borrow::Cow::Owned(PyInt::small(*b as u64)))),
            PyVal::Int(i) => Some(Num::Int(std::borrow::Cow::Borrowed(i))),
            PyVal::Float(x) => Some(Num::Float(*x)),
            _ => None,
        }
    }

    fn cmp_num(a: &Num, b: &Num) -> Option<Ordering> {
        match (a, b) {
            (Num::Int(a), Num::Int(b)) => Some(a.cmp(b)),
            (Num::Float(a), Num::Float(b)) => a.partial_cmp(b),
            (Num::Int(a), Num::Float(b)) => cmp_int_float(a, *b),
            (Num::Float(a), Num::Int(b)) => cmp_int_float(b, *a).map(Ordering::reverse),
        }
    }

    /// `a == b` as list.count, `in` and dict keys test it: identity first,
    /// so json's one NaN object equals itself.
    pub fn py_eq(&self, other: &PyVal) -> bool {
        if let (Some(a), Some(b)) = (self.num(), other.num()) {
            if let (Num::Float(x), Num::Float(y)) = (&a, &b) {
                if x.is_nan() && y.is_nan() {
                    return true;
                }
            }
            return PyVal::cmp_num(&a, &b) == Some(Ordering::Equal);
        }
        match (self, other) {
            (PyVal::None, PyVal::None) => true,
            (PyVal::Str(a), PyVal::Str(b)) => a == b,
            (PyVal::List(a), PyVal::List(b)) => {
                a.len() == b.len() && a.iter().zip(b).all(|(x, y)| x.py_eq(y))
            }
            (PyVal::Dict(a), PyVal::Dict(b)) => {
                a.0.len() == b.0.len()
                    && a.0.iter().all(|(k, v)| {
                        b.0.iter()
                            .find(|(k2, _)| k2 == k)
                            .map_or(false, |(_, v2)| v.py_eq(v2))
                    })
            }
            _ => false,
        }
    }

    /// `a < b`, or the TypeError Python raises for types it cannot order.
    pub fn lt(&self, other: &PyVal) -> Result<bool, Exc> {
        if let (Some(a), Some(b)) = (self.num(), other.num()) {
            return Ok(PyVal::cmp_num(&a, &b) == Some(Ordering::Less));
        }
        match (self, other) {
            (PyVal::Str(a), PyVal::Str(b)) => Ok(a < b),
            _ => Err(Exc::TypeError(PyStr::from(
                format!(
                    "'<' not supported between instances of '{}' and '{}'",
                    self.type_name(),
                    other.type_name()
                )
                .as_str(),
            ))),
        }
    }

    /// What putting the value in a set or a dict's keys raises, if anything.
    pub fn check_hashable(&self) -> Result<(), Exc> {
        match self {
            PyVal::List(_) | PyVal::Dict(_) => Err(Exc::TypeError(PyStr::from(
                format!("unhashable type: '{}'", self.type_name()).as_str(),
            ))),
            _ => Ok(()),
        }
    }

    /// repr(value). Iterative: a JSON file may nest thousands deep.
    pub fn repr(&self) -> PyStr {
        enum Step<'a> {
            Value(&'a PyVal),
            Text(&'static str),
            Key(&'a PyStr),
        }
        let mut out = PyStr::new();
        let mut stack = vec![Step::Value(self)];
        while let Some(step) = stack.pop() {
            match step {
                Step::Text(t) => out.push_str(t),
                Step::Key(k) => {
                    out.push_py(&k.repr());
                    out.push_str(": ");
                }
                Step::Value(v) => match v {
                    PyVal::None => out.push_str("None"),
                    PyVal::Bool(true) => out.push_str("True"),
                    PyVal::Bool(false) => out.push_str("False"),
                    PyVal::Int(i) => out.push_str(&i.repr()),
                    PyVal::Float(x) => out.push_str(&float_repr(*x)),
                    PyVal::Str(s) => out.push_py(&s.repr()),
                    PyVal::List(items) => {
                        out.push_str("[");
                        stack.push(Step::Text("]"));
                        for (i, item) in items.iter().enumerate().rev() {
                            stack.push(Step::Value(item));
                            if i > 0 {
                                stack.push(Step::Text(", "));
                            }
                        }
                    }
                    PyVal::Dict(d) => {
                        out.push_str("{");
                        stack.push(Step::Text("}"));
                        for (i, (k, item)) in d.0.iter().enumerate().rev() {
                            stack.push(Step::Value(item));
                            stack.push(Step::Key(k));
                            if i > 0 {
                                stack.push(Step::Text(", "));
                            }
                        }
                    }
                },
            }
        }
        out
    }

    /// str(value), as an f-string writes it.
    pub fn py_str(&self) -> PyStr {
        match self {
            PyVal::Str(s) => s.clone(),
            other => other.repr(),
        }
    }

    /// `list(value)`: what a for loop over it sees.
    pub fn iterate(&self) -> Result<Vec<PyVal>, Exc> {
        match self {
            PyVal::List(items) => Ok(items.clone()),
            PyVal::Dict(d) => Ok(d.0.iter().map(|(k, _)| PyVal::Str(k.clone())).collect()),
            PyVal::Str(s) => Ok(s
                .cps()
                .iter()
                .map(|&c| PyVal::Str(PyStr(vec![c])))
                .collect()),
            other => Err(Exc::TypeError(PyStr::from(
                format!("'{}' object is not iterable", other.type_name()).as_str(),
            ))),
        }
    }

    /// `value.get(key)`: the dict's value or None, or AttributeError.
    pub fn get(&self, key: &str) -> Result<PyVal, Exc> {
        match self {
            PyVal::Dict(d) => Ok(d.get(key).cloned().unwrap_or(PyVal::None)),
            other => Err(Exc::attribute(other, "get")),
        }
    }

    /// `value[key]` for a str key.
    pub fn index(&self, key: &str) -> Result<PyVal, Exc> {
        match self {
            PyVal::Dict(d) => d
                .get(key)
                .cloned()
                .ok_or_else(|| Exc::KeyError(PyStr::from(key).repr())),
            PyVal::List(_) => Err(Exc::type_error(
                "list indices must be integers or slices, not str",
            )),
            PyVal::Str(_) => Err(Exc::type_error(
                "string indices must be integers, not 'str'",
            )),
            other => Err(Exc::TypeError(PyStr::from(
                format!("'{}' object is not subscriptable", other.type_name()).as_str(),
            ))),
        }
    }

    /// `a or b`.
    pub fn or(self, other: PyVal) -> PyVal {
        if self.truthy() {
            self
        } else {
            other
        }
    }
}

/// `sep.join(items)`, or its TypeError for an item that is not a str.
pub fn join(sep: &str, items: &[PyVal]) -> Result<PyStr, Exc> {
    let mut parts = Vec::with_capacity(items.len());
    for (i, item) in items.iter().enumerate() {
        match item {
            PyVal::Str(s) => parts.push(s.clone()),
            other => {
                return Err(Exc::TypeError(PyStr::from(
                    format!(
                        "sequence item {}: expected str instance, {} found",
                        i,
                        other.type_name()
                    )
                    .as_str(),
                )))
            }
        }
    }
    Ok(PyStr::join(sep, &parts))
}

/// `value in items`.
pub fn contains(items: &[PyVal], value: &PyVal) -> bool {
    items.iter().any(|item| item.py_eq(value))
}

/// The elements of a set built from `items` in order: hashable, one of each.
pub fn set_of(items: impl IntoIterator<Item = PyVal>) -> Result<Vec<PyVal>, Exc> {
    let mut out: Vec<PyVal> = Vec::new();
    for item in items {
        item.check_hashable()?;
        if !contains(&out, &item) {
            out.push(item);
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn floats_print_as_python_prints_them() {
        for (x, want) in [
            (1.0, "1.0"),
            (1e16, "1e+16"),
            (1e15, "1000000000000000.0"),
            (0.0001, "0.0001"),
            (0.00001, "1e-05"),
            (-0.0, "-0.0"),
            (1.5e300, "1.5e+300"),
            (123456789012345678.0, "1.2345678901234568e+17"),
            (0.1, "0.1"),
            (f64::INFINITY, "inf"),
        ] {
            assert_eq!(float_repr(x), want);
        }
    }

    #[test]
    fn ints_and_floats_compare_exactly() {
        let big = PyVal::Int(PyInt::from_decimal("9007199254740993"));
        let float = PyVal::Float(9007199254740992.0);
        assert!(!big.py_eq(&float));
        assert!(float.lt(&big).unwrap());
        assert!(PyVal::Bool(true).py_eq(&PyVal::Float(1.0)));
        let huge = PyVal::Int(PyInt::from_decimal(&format!("1{}", "0".repeat(400))));
        assert!(PyVal::Float(1e308).lt(&huge).unwrap());
        assert!(PyVal::Float(f64::NAN).py_eq(&PyVal::Float(f64::NAN)));
    }

    #[test]
    fn mixed_types_do_not_order() {
        let err = PyVal::Int(PyInt::small(1))
            .lt(&PyVal::str("a"))
            .unwrap_err();
        assert_eq!(
            err.message().lossy(),
            "'<' not supported between instances of 'int' and 'str'"
        );
    }

    #[test]
    fn repr_of_containers() {
        let mut d = Dict::default();
        d.insert(
            PyStr::from("a"),
            PyVal::List(vec![PyVal::Bool(true), PyVal::None]),
        );
        d.insert(PyStr::from("b"), PyVal::Float(2.5));
        assert_eq!(
            PyVal::Dict(d).repr().lossy(),
            "{'a': [True, None], 'b': 2.5}"
        );
    }
}
