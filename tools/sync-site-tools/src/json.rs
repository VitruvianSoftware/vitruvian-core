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

//! Thin adapter over `vitruvian_pycompat::json` and `vitruvian_pycompat::pyerr`
//! preserving `tools/sync-site-tools`'s `PyStr`/`PyErr` signatures, CPython 3.12
//! 4300-digit integer limit, bounded nesting, and Python object semantics
//! (`subscript`, `py_get`, `iterate`, `truthy`, `py_eq`, `py_lt`, `to_pystr`,
//! `to_pyrepr`).

use vitruvian_pycompat::json::{dedup, dumps_with, JsonErrorKind, DEFAULT_INT_MAX_STR_DIGITS};
use vitruvian_pycompat::pyerr::{self, Crash};

pub use vitruvian_pycompat::json::{DumpOptions, Value};
pub use vitruvian_pycompat::pystr::repr_float as float_repr;

use crate::pyerr::PyErr;
use crate::pystr::PyStr;

/// CPython 3.12's measured container nesting limit for `json.loads`
/// (`/opt/homebrew/bin/python3.12 -I` accepts depth 9,997 and raises
/// `RecursionError` at depth 9,998).
pub const MAX_DEPTH: usize = 9_997;

/// `f"{value:.1f}"` of a float.
pub fn format_fixed1(f: f64) -> String {
    vitruvian_pycompat::pystr::format_fixed(f, 1)
}

pub fn s(text: &str) -> Value {
    Value::Str(text.to_string())
}

pub fn s_py(text: &PyStr) -> Value {
    Value::Str(text.to_string_lossy())
}

pub fn int(value: i64) -> Value {
    Value::Int(value.to_string())
}

pub fn obj(pairs: Vec<(&str, Value)>) -> Value {
    let mut out: Vec<(String, Value)> = Vec::with_capacity(pairs.len());
    for (k, v) in pairs {
        if let Some(slot) = out.iter_mut().find(|(ek, _)| ek == k) {
            slot.1 = v;
        } else {
            out.push((k.to_string(), v));
        }
    }
    Value::Obj(out)
}

pub fn list_of_str(items: &[&str]) -> Value {
    Value::Arr(items.iter().map(|item| s(item)).collect())
}

/// `int_str / 2**power`, correctly rounded, as Python's true division gives it;
/// `None` where Python raises `OverflowError`.
pub fn int_div_pow2(text: &str, power: u32) -> Option<f64> {
    let (negative, rest) = match text.strip_prefix('-') {
        Some(d) => (true, d),
        None => (false, text),
    };
    let trimmed = rest.trim_start_matches('0');
    if trimmed.is_empty() {
        return Some(0.0);
    }
    // n / 2**p == n * 5**p / 10**p, and both are exact decimals.
    let mut product: Vec<u32> = trimmed.bytes().rev().map(|b| (b - b'0') as u32).collect();
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
    let decimal = format!(
        "{}e-{}",
        if negative {
            format!("-{digits}")
        } else {
            digits
        },
        power
    );
    let value: f64 = decimal.parse().ok()?;
    if value.is_infinite() {
        None
    } else {
        Some(value)
    }
}

fn crash_to_pyerr(crash: Crash) -> PyErr {
    PyErr::exc(&crash.class, &crash.msg)
}

/// `json.loads(text)`.
pub fn loads(text: &PyStr) -> Result<Value, PyErr> {
    vitruvian_pycompat::json::loads_with_limits(
        &text.to_string_lossy(),
        Some(MAX_DEPTH),
        Some(DEFAULT_INT_MAX_STR_DIGITS),
    )
    .map_err(|e| match e.kind() {
        JsonErrorKind::Recursion => {
            PyErr::exc("RecursionError", e.recursion_message().unwrap_or(&e.msg))
        }
        JsonErrorKind::IntDigitLimit => PyErr::exc("ValueError", &e.msg),
        JsonErrorKind::Decode => PyErr::exc("json.decoder.JSONDecodeError", &e.python_str()),
    })
}

/// `json.dumps(value, ensure_ascii=..., indent=...)`.
pub fn dumps(value: &Value, ensure_ascii: bool, indent: Option<usize>) -> PyStr {
    PyStr::from(dumps_with(
        value,
        &DumpOptions {
            indent,
            ensure_ascii,
            ..DumpOptions::default()
        },
    ))
}

/// Python-object operations expected by `tools/sync-site-tools` over `Value`.
pub trait ValueExt {
    fn subscript(&self, key: &str) -> Result<&Value, PyErr>;
    /// Named `py_get` so `Value::get(&self, &str) -> Option<&Value>` does not shadow it.
    fn py_get(&self, key: &str) -> Result<Option<&Value>, PyErr>;
    fn get_or(&self, key: &str, default: Value) -> Result<Value, PyErr>;
    fn get_value(&self, key: &str) -> Result<Value, PyErr>;
    fn iterate(&self) -> Result<Vec<Value>, PyErr>;
    fn check_hashable(&self) -> Result<(), PyErr>;
    fn eq_str(&self, text: &str) -> bool;
    fn py_eq(&self, other: &Value) -> bool;
    fn py_lt(&self, other: &Value) -> Result<bool, PyErr>;
    fn to_pystr(&self) -> PyStr;
    fn to_pyrepr(&self) -> PyStr;
}

impl ValueExt for Value {
    fn subscript(&self, key: &str) -> Result<&Value, PyErr> {
        pyerr::index_ref(self, key).map_err(crash_to_pyerr)
    }

    fn py_get(&self, key: &str) -> Result<Option<&Value>, PyErr> {
        pyerr::get_ref(self, key).map_err(crash_to_pyerr)
    }

    fn get_or(&self, key: &str, default: Value) -> Result<Value, PyErr> {
        pyerr::get_or(self, key, default).map_err(crash_to_pyerr)
    }

    fn get_value(&self, key: &str) -> Result<Value, PyErr> {
        self.get_or(key, Value::Null)
    }

    fn iterate(&self) -> Result<Vec<Value>, PyErr> {
        pyerr::iterate(self).map_err(crash_to_pyerr)
    }

    fn check_hashable(&self) -> Result<(), PyErr> {
        pyerr::check_hashable(self).map_err(crash_to_pyerr)
    }

    fn eq_str(&self, text: &str) -> bool {
        matches!(self, Value::Str(own) if own == text)
    }

    /// `PyObject_RichCompareBool(self, other, Py_EQ)`. `json.loads` returns one
    /// singleton `NaN` object, so `NaN` compares equal to `NaN` here.
    fn py_eq(&self, other: &Value) -> bool {
        match (self, other) {
            (Value::Float(x), Value::Float(y)) if x.is_nan() && y.is_nan() => true,
            (Value::Arr(a), Value::Arr(b)) => {
                a.len() == b.len() && a.iter().zip(b).all(|(x, y)| x.py_eq(y))
            }
            (Value::Obj(a), Value::Obj(b)) => {
                let (a, b) = (dedup(a), dedup(b));
                a.len() == b.len()
                    && a.iter()
                        .all(|(k, v)| b.iter().any(|(k2, v2)| k == k2 && v.py_eq(v2)))
            }
            _ => vitruvian_pycompat::json::py_eq(self, other),
        }
    }

    fn py_lt(&self, other: &Value) -> Result<bool, PyErr> {
        pyerr::lt(self, other).map_err(crash_to_pyerr)
    }

    fn to_pystr(&self) -> PyStr {
        PyStr::from(self.py_str())
    }

    fn to_pyrepr(&self) -> PyStr {
        PyStr::from(self.py_repr())
    }
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
            ("\r\r  x", "Expecting value: line 1 column 5 (char 4)"),
            ("\r\n  x", "Expecting value: line 2 column 3 (char 4)"),
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
            w.to_pyrepr().to_string_lossy(),
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
        let big = format!("1{}", "0".repeat(309));
        assert_eq!(
            int_div_pow2(&big, 20).map(float_repr),
            Some("9.5367431640625e+302".to_string())
        );
        assert_eq!(int_div_pow2(&format!("1{}", "0".repeat(400)), 10), None);
        assert_eq!(int_div_pow2("4000", 10), Some(3.90625));
        assert_eq!(int_div_pow2("-0", 10), Some(0.0));
        assert!(int(3).py_lt(&Value::Float(3.5)).unwrap());
        assert!(!int(-3).py_lt(&Value::Float(-3.5)).unwrap());
        assert!(!int(9007199254740993)
            .py_lt(&Value::Float(9007199254740992.0))
            .unwrap());
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
            v.py_get("a").unwrap_err().last_line(),
            "AttributeError: 'list' object has no attribute 'get'"
        );
        assert_eq!(
            s("a").py_lt(&int(1)).unwrap_err().last_line(),
            "TypeError: '<' not supported between instances of 'str' and 'int'"
        );
        assert!(Value::Float(f64::NAN).py_eq(&Value::Float(f64::NAN)));
        assert!(Value::Bool(true).py_eq(&Value::Float(1.0)));
    }

    #[test]
    fn truthiness_and_adapter_helpers() {
        assert!(!Value::Null.truthy());
        assert!(!Value::Bool(false).truthy());
        assert!(Value::Bool(true).truthy());
        assert!(!Value::Int("-0".into()).truthy());
        assert!(int(1).truthy());
        assert!(!Value::Float(-0.0).truthy());
        assert!(Value::Float(0.1).truthy());
        assert!(!s("").truthy());
        assert!(s("x").truthy());
        assert!(!Value::Arr(vec![]).truthy());
        assert!(list_of_str(&["a"]).truthy());
        assert!(!obj(vec![]).truthy());
        assert!(obj(vec![("a", int(1)), ("a", int(2))]).truthy());

        let d = obj(vec![("k", s("v")), ("k", s("v2"))]);
        assert!(d.subscript("k").unwrap().eq_str("v2"));
        assert!(!d.subscript("k").unwrap().eq_str("v"));
        assert_eq!(d.py_get("missing").unwrap(), None);
        assert_eq!(d.get_value("missing").unwrap(), Value::Null);
        assert_eq!(d.get_or("missing", int(7)).unwrap(), int(7));
        assert!(s("a").check_hashable().is_ok());
        assert_eq!(
            d.check_hashable().unwrap_err().last_line(),
            "TypeError: unhashable type: 'dict'"
        );
    }

    #[test]
    fn deep_nesting_returns_recursion_error_without_crashing() {
        // Value::drop is compiler-generated and recursive because Value variants
        // are moved out by callers, so test depth 9,997 on a 32 MiB stack.
        let handle = std::thread::Builder::new()
            .stack_size(32 << 20)
            .spawn(|| {
                fn obj_chain(depth: usize, leaf: &str) -> String {
                    format!("{}{}{}", r#"{"a":"#.repeat(depth), leaf, "}".repeat(depth))
                }
                fn mixed_chain(depth: usize, start_obj: bool, leaf: &str) -> String {
                    let mut out = String::new();
                    for k in 0..depth {
                        if (k % 2 == 0) == start_obj {
                            out.push_str(r#"{"a":"#);
                        } else {
                            out.push('[');
                        }
                    }
                    out.push_str(leaf);
                    for k in (0..depth).rev() {
                        if (k % 2 == 0) == start_obj {
                            out.push('}');
                        } else {
                            out.push(']');
                        }
                    }
                    out
                }

                const ACCEPTED_DEPTH: usize = 9_997;
                // Exact accepted depth: 9,997 across arrays, objects, and mixed chains.
                let ok_cases = [
                    format!("{}{}", "[".repeat(ACCEPTED_DEPTH), "]".repeat(ACCEPTED_DEPTH)),
                    format!("{}1{}", "[".repeat(ACCEPTED_DEPTH), "]".repeat(ACCEPTED_DEPTH)),
                    obj_chain(ACCEPTED_DEPTH, "1"),
                    mixed_chain(ACCEPTED_DEPTH, false, "0"),
                    mixed_chain(ACCEPTED_DEPTH, true, "0"),
                ];
                for doc in &ok_cases {
                    let v = load(doc);
                    assert!(v.is_ok(), "depth {} should succeed: {:?}", ACCEPTED_DEPTH, v);
                }

                // Exact rejected depth: 9,998 and deeper (50,000), never aborting.
                let arr_err = "RecursionError: maximum recursion depth exceeded while decoding a JSON array from a unicode string";
                let obj_err = "RecursionError: maximum recursion depth exceeded while decoding a JSON object from a unicode string";

                for doc in [
                    "[".repeat(ACCEPTED_DEPTH + 1),
                    format!(
                        "{}{}",
                        "[".repeat(ACCEPTED_DEPTH + 1),
                        "]".repeat(ACCEPTED_DEPTH + 1)
                    ),
                    "[".repeat(50_000),
                    format!("{}{}", "[".repeat(50_000), "]".repeat(50_000)),
                    // k=0..9997 -> 9,998th opener is k=9997 (odd); start_obj=true alternates {'a':[... -> '[' at k=9997.
                    mixed_chain(ACCEPTED_DEPTH + 1, true, "0"),
                ] {
                    assert_eq!(load(&doc).unwrap_err(), arr_err);
                }

                for doc in [
                    r#"{"a":"#.repeat(ACCEPTED_DEPTH + 1),
                    obj_chain(ACCEPTED_DEPTH + 1, "1"),
                    r#"{"a":"#.repeat(50_000),
                    obj_chain(50_000, "1"),
                    // k=0..9997 -> 9,998th opener is k=9997 (odd); start_obj=false alternates [{"a":... -> '{' at k=9997.
                    mixed_chain(ACCEPTED_DEPTH + 1, false, "0"),
                ] {
                    assert_eq!(load(&doc).unwrap_err(), obj_err);
                }

                let err = loads(&PyStr::from("[".repeat(ACCEPTED_DEPTH + 1))).unwrap_err();
                let stderr = String::from_utf8(err.stderr_bytes()).unwrap();
                assert!(
                    stderr.ends_with(&format!("{arr_err}\n")),
                    "unexpected stderr: {stderr:?}"
                );
            })
            .unwrap();
        handle.join().unwrap();
    }
}
