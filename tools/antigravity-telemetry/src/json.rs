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

//! Thin adapter over `vitruvian_pycompat::json` preserving `tools/antigravity-telemetry`'s
//! [`J`] alias, `MAX_DEPTH = 900` nesting limit, `String` errors via
//! `JsonError::python_str`, [`ValueExt`] helpers/mutators, and [`dumps`].

pub use vitruvian_pycompat::json::{
    dumps_with, loads_with, py_eq, DumpOptions, LoadOptions, Value,
};
pub use vitruvian_pycompat::pystr::repr_float as float_repr;

/// Alias preserving telemetry's historical value type name.
pub type J = Value;

/// Nesting limit kept from telemetry's original parser.
pub const MAX_DEPTH: usize = 900;

/// `json.loads(text)`, keeping key order and enforcing [`MAX_DEPTH`].
/// The error is `JSONDecodeError`'s message (`"{msg}: line {line} column {col} (char {pos})"`).
pub fn loads(text: &str) -> Result<J, String> {
    loads_with(
        text,
        &LoadOptions {
            max_depth: Some(MAX_DEPTH),
        },
    )
    .map_err(|e| e.python_str())
}

/// `json.dumps(v, indent=indent, ensure_ascii=ensure_ascii)`.
pub fn dumps(v: &J, indent: Option<usize>, ensure_ascii: bool) -> String {
    dumps_with(
        v,
        &DumpOptions {
            indent,
            ensure_ascii,
            ..DumpOptions::default()
        },
    )
}

/// Convert `Value::Int`'s decimal text to `f64`, matching `i as f64` for every
/// integer that fits in `i128` (so `"-0"` yields `+0.0`) and falling back to
/// `f64::from_str` for larger integers.
pub fn int_as_f64(s: &str) -> f64 {
    if let Ok(i) = s.parse::<i128>() {
        i as f64
    } else {
        s.parse::<f64>().unwrap_or(f64::NAN)
    }
}

/// Telemetry-specific constructors and object mutators over [`Value`].
pub trait ValueExt: Sized {
    fn int(n: i128) -> Self;
    fn obj<K: Into<String>>(pairs: Vec<(K, Value)>) -> Self;
    fn empty_obj() -> Self;
    fn str<S: Into<String>>(s: S) -> Self;
    fn parse(text: &str) -> Result<Self, String>;
    fn as_str(&self) -> Option<&str>;
    fn as_i128(&self) -> Option<i128>;
    fn is_null(&self) -> bool;
    fn get_mut(&mut self, key: &str) -> Option<&mut Value>;
    fn contains_key(&self, key: &str) -> bool;
    fn set(&mut self, key: &str, value: Value);
    fn remove(&mut self, key: &str) -> Option<Value>;
}

impl ValueExt for Value {
    fn int(n: i128) -> Self {
        Value::Int(n.to_string())
    }

    /// An object from `(key, value)` pairs, in order.
    fn obj<K: Into<String>>(pairs: Vec<(K, Value)>) -> Self {
        let mut out = Value::Obj(Vec::with_capacity(pairs.len()));
        for (k, v) in pairs {
            out.set(&k.into(), v);
        }
        out
    }

    fn empty_obj() -> Self {
        Value::Obj(Vec::new())
    }

    fn str<S: Into<String>>(s: S) -> Self {
        Value::Str(s.into())
    }

    fn parse(text: &str) -> Result<Self, String> {
        loads(text)
    }

    fn as_str(&self) -> Option<&str> {
        match self {
            Value::Str(s) => Some(s),
            _ => None,
        }
    }

    fn as_i128(&self) -> Option<i128> {
        match self {
            Value::Int(s) => s.parse::<i128>().ok(),
            _ => None,
        }
    }

    fn is_null(&self) -> bool {
        matches!(self, Value::Null)
    }

    fn get_mut(&mut self, key: &str) -> Option<&mut Value> {
        match self {
            Value::Obj(pairs) => pairs.iter_mut().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    fn contains_key(&self, key: &str) -> bool {
        self.get(key).is_some()
    }

    /// `d[key] = value`: replaces in place (keeping position) or appends.
    /// A no-op on a non-object.
    fn set(&mut self, key: &str, value: Value) {
        if let Value::Obj(pairs) = self {
            if let Some(slot) = pairs.iter_mut().find(|(k, _)| k == key) {
                slot.1 = value;
            } else {
                pairs.push((key.to_string(), value));
            }
        }
    }

    /// `d.pop(key, None)`.
    fn remove(&mut self, key: &str) -> Option<Value> {
        if let Value::Obj(pairs) = self {
            if let Some(i) = pairs.iter().position(|(k, _)| k == key) {
                return Some(pairs.remove(i).1);
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bs(template: &str) -> String {
        const BS: char = '\\';
        assert!(
            !template.contains(BS),
            "build escapes in code with '|' instead of literal backslashes: {template:?}"
        );
        template.replace('|', &BS.to_string())
    }

    #[test]
    fn float_repr_matches_python() {
        let cases = [
            (145.0, "145.0"),
            (0.1, "0.1"),
            (1e-05, "1e-05"),
            (0.0001, "0.0001"),
            (1e16, "1e+16"),
            (123456789012345678.0, "1.2345678901234568e+17"),
            (1e15, "1000000000000000.0"),
            (-0.0, "-0.0"),
            (0.0, "0.0"),
            (2.5e-7, "2.5e-07"),
            (12.5, "12.5"),
            (1792885118.2732465, "1792885118.2732465"),
            (1792712318.3030279, "1792712318.3030279"),
        ];
        for (f, want) in cases {
            assert_eq!(float_repr(f), want, "{f}");
        }
        assert_eq!(float_repr(f64::NAN), "nan");
        assert_eq!(float_repr(f64::INFINITY), "inf");
        assert_eq!(float_repr(f64::NEG_INFINITY), "-inf");
    }

    #[test]
    fn dumps_matches_python_layout() {
        let v = J::parse(r#"{"b": [1, 2.0, {"x": null}], "a": {}, "c": [], "d": "é\n"}"#).unwrap();
        assert_eq!(
            dumps(&v, None, true),
            r#"{"b": [1, 2.0, {"x": null}], "a": {}, "c": [], "d": "\u00e9\n"}"#
        );
        assert_eq!(
            dumps(&v, None, false),
            "{\"b\": [1, 2.0, {\"x\": null}], \"a\": {}, \"c\": [], \"d\": \"é\\n\"}"
        );
        assert_eq!(
            dumps(&v, Some(2), true),
            "{\n  \"b\": [\n    1,\n    2.0,\n    {\n      \"x\": null\n    }\n  ],\n  \"a\": {},\n  \"c\": [],\n  \"d\": \"\\u00e9\\n\"\n}"
        );
    }

    #[test]
    fn parse_keeps_order_and_last_duplicate() {
        let v = J::parse(r#"{"z": 1, "a": 2, "z": 3}"#).unwrap();
        assert_eq!(dumps(&v, None, true), r#"{"z": 3, "a": 2}"#);
    }

    #[test]
    fn parse_matches_python_json() {
        // Exact float parsing: these round-trip through repr unchanged.
        for text in [
            "1792885118.2732465",
            "1792712318.3030279",
            "0.1",
            "1e-05",
            "1.2345678901234568e+17",
        ] {
            assert_eq!(
                float_repr(match J::parse(text).unwrap() {
                    J::Float(f) => f,
                    other => panic!("{:?}", other),
                }),
                text
            );
        }
        assert_eq!(J::parse("12").unwrap(), J::int(12));
        let neg_zero = J::parse("-0").unwrap();
        assert_eq!(neg_zero.as_i128(), Some(0));
        assert_eq!(neg_zero.py_repr(), "0");
        assert_eq!(dumps(&neg_zero, None, true), "0");
        assert!(py_eq(&neg_zero, &J::int(0)));
        assert_eq!(
            int_as_f64(match &neg_zero {
                J::Int(s) => s,
                other => panic!("{other:?}"),
            })
            .to_bits(),
            0.0_f64.to_bits()
        );
        assert_eq!(J::parse("1E2").unwrap(), J::Float(100.0));
        assert!(matches!(J::parse("NaN").unwrap(), J::Float(f) if f.is_nan()));
        assert_eq!(
            J::parse(&bs(" [1, \"a|u00e9|ud83d|ude00|n\"] ")).unwrap(),
            J::Arr(vec![J::int(1), J::str("a\u{e9}\u{1F600}\n")])
        );
    }

    #[test]
    fn astral_escapes_as_surrogate_pair() {
        assert_eq!(dumps(&J::str("😀"), None, true), r#""\ud83d\ude00""#);
    }

    #[test]
    fn value_ext_constructors_and_mutators() {
        let mut obj = J::obj(vec![("a", J::int(1)), ("b", J::str("x")), ("a", J::int(2))]);
        assert_eq!(dumps(&obj, None, true), r#"{"a": 2, "b": "x"}"#);
        assert!(obj.contains_key("a"));
        assert!(!obj.contains_key("c"));
        assert_eq!(obj.get("a").and_then(J::as_i128), Some(2));
        assert_eq!(obj.get("b").and_then(J::as_str), Some("x"));
        assert!(!obj.is_null());
        assert!(J::Null.is_null());

        *obj.get_mut("a").unwrap() = J::int(9);
        obj.set("c", J::Bool(true));
        assert_eq!(obj.remove("b"), Some(J::str("x")));
        assert_eq!(obj.remove("missing"), None);
        assert_eq!(dumps(&obj, None, true), r#"{"a": 9, "c": true}"#);

        let mut empty = J::empty_obj();
        empty.set("k", J::Null);
        assert_eq!(dumps(&empty, None, true), r#"{"k": null}"#);

        // Non-object mutators are no-ops / None, matching legacy J.
        let mut arr = J::Arr(vec![]);
        arr.set("k", J::int(1));
        assert_eq!(arr.get_mut("k"), None);
        assert_eq!(arr.remove("k"), None);
        assert_eq!(arr, J::Arr(vec![]));
    }

    #[test]
    fn behaviour_changes_match_cpython_312() {
        // 1. UTF-8 BOM: CPython 3.12 rejects with Unexpected UTF-8 BOM.
        for bom_input in ["\u{feff}{}", "\u{feff}1", "\u{feff}"] {
            assert_eq!(
                J::parse(bom_input).unwrap_err(),
                "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)",
                "{bom_input:?}"
            );
        }

        // 2. Complete \uXXXX right at EOF: CPython 3.12 reports "Invalid \uXXXX escape".
        for (tmpl, want) in [
            (
                "\"|u0041",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"ab|u0041",
                "Invalid \\uXXXX escape: line 1 column 5 (char 4)",
            ),
            (
                "\"|ud800|u0041",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"|ud800|udc00",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"|ud800",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "[\"|u0041",
                "Invalid \\uXXXX escape: line 1 column 4 (char 3)",
            ),
        ] {
            let input = bs(tmpl);
            assert_eq!(J::parse(&input).unwrap_err(), want, "{input:?}");
        }

        // 3. Integers > i128 preserve exact digits.
        for big in [
            "170141183460469231731687303715884105728",
            "-170141183460469231731687303715884105729",
            "10000000000000000000000000000000000000000",
            "-10000000000000000000000000000000000000000",
        ] {
            let v = J::parse(big).unwrap();
            assert_eq!(v, J::Int(big.to_string()), "{big:?}");
            assert_eq!(dumps(&v, None, true), big, "{big:?}");
            assert_eq!(crate::pyutil::py_repr(&v), big, "{big:?}");
        }
    }

    #[test]
    fn malformed_inputs_match_cpython_312() {
        let cases: &[(&str, &str)] = &[
            // Empty / whitespace
            ("", "Expecting value: line 1 column 1 (char 0)"),
            (" ", "Expecting value: line 1 column 2 (char 1)"),
            ("   \n\t\r  ", "Expecting value: line 2 column 5 (char 8)"),
            ("\n", "Expecting value: line 2 column 1 (char 1)"),
            ("not json", "Expecting value: line 1 column 1 (char 0)"),
            // BOM
            (
                "\u{feff}{}",
                "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)",
            ),
            (
                "\u{feff}1",
                "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)",
            ),
            (
                "\u{feff}",
                "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)",
            ),
            // Invalid simple escapes
            ("\"a|qb\"", "Invalid \\escape: line 1 column 3 (char 2)"),
            ("\"|q\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            ("\"|x\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            ("\"|a\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            ("\"|1\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            ("\"|'\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            ("\"|0\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            ("\"|v\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            // Invalid \uXXXX inside string or after high surrogate
            (
                "\"|u12\"",
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
                "\"|u 123\"",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"|ud800|u12\"",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"|ud800|u123g\"",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"|ud800|u123\"",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            // Truncated \u at EOF
            ("\"|u", "Invalid \\uXXXX escape: line 1 column 3 (char 2)"),
            ("\"|u1", "Invalid \\uXXXX escape: line 1 column 3 (char 2)"),
            ("\"|u12", "Invalid \\uXXXX escape: line 1 column 3 (char 2)"),
            (
                "\"|u123",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"|ud800|u",
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
                "\"|ud800|u123",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            // Complete \uXXXX right at EOF (CPython 3.12)
            (
                "\"|u0041",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"ab|u0041",
                "Invalid \\uXXXX escape: line 1 column 5 (char 4)",
            ),
            (
                "\"|ud800|u0041",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"|ud800|udc00",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"|ud800",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "[\"|u0041",
                "Invalid \\uXXXX escape: line 1 column 4 (char 3)",
            ),
            // Controls around \uXXXX + EOF
            (
                "\"|u0041x",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "\"||u0041",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "\"|u0041|",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            // Unterminated strings
            (
                "\"abc",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "[\"abc",
                "Unterminated string starting at: line 1 column 2 (char 1)",
            ),
            (
                "\n\"ab",
                "Unterminated string starting at: line 2 column 1 (char 1)",
            ),
            (
                "\"ab|",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "\"|",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "\"|\"",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "{\"k\": \"v",
                "Unterminated string starting at: line 1 column 7 (char 6)",
            ),
            // Unescaped control characters
            (
                "\"a\nb\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            (
                "\"a\tb\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            (
                "\"a\rb\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            (
                "\"a\x00b\"",
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
                "\"a\x0cb\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            (
                "\"a\x1fb\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            // Object syntax errors
            (
                "{",
                "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)",
            ),
            (
                "{   ",
                "Expecting property name enclosed in double quotes: line 1 column 5 (char 4)",
            ),
            ("{\"a\": ", "Expecting value: line 1 column 7 (char 6)"),
            ("{\"a\":}", "Expecting value: line 1 column 6 (char 5)"),
            (
                "{\"a\" 1}",
                "Expecting ':' delimiter: line 1 column 6 (char 5)",
            ),
            (
                "{\"a\"   1}",
                "Expecting ':' delimiter: line 1 column 8 (char 7)",
            ),
            (
                "{\"a\"}",
                "Expecting ':' delimiter: line 1 column 5 (char 4)",
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
                "{\"a\": 1",
                "Expecting ',' delimiter: line 1 column 8 (char 7)",
            ),
            (
                "{\"a\": 1 \"b\": 2}",
                "Expecting ',' delimiter: line 1 column 9 (char 8)",
            ),
            (
                "{\"a\": \"b\", \"c\" 3}",
                "Expecting ':' delimiter: line 1 column 16 (char 15)",
            ),
            (
                "{\"a\": [1, 2], \"b\": {\"c\":}}",
                "Expecting value: line 1 column 25 (char 24)",
            ),
            (
                "{\"a\": 1,}",
                "Expecting property name enclosed in double quotes: line 1 column 9 (char 8)",
            ),
            (
                "{\"a\":1,}",
                "Expecting property name enclosed in double quotes: line 1 column 8 (char 7)",
            ),
            (
                "{\"a\": 1, ",
                "Expecting property name enclosed in double quotes: line 1 column 10 (char 9)",
            ),
            (
                "{,}",
                "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)",
            ),
            // Array syntax errors
            ("[", "Expecting value: line 1 column 2 (char 1)"),
            ("[  ", "Expecting value: line 1 column 4 (char 3)"),
            ("[[[", "Expecting value: line 1 column 4 (char 3)"),
            ("[1", "Expecting ',' delimiter: line 1 column 3 (char 2)"),
            ("[1 2]", "Expecting ',' delimiter: line 1 column 4 (char 3)"),
            (
                "[1, 2 3]",
                "Expecting ',' delimiter: line 1 column 7 (char 6)",
            ),
            ("[1,]", "Expecting value: line 1 column 4 (char 3)"),
            ("[,]", "Expecting value: line 1 column 2 (char 1)"),
            // Extra data
            ("{} x", "Extra data: line 1 column 4 (char 3)"),
            ("[1]\n x", "Extra data: line 2 column 2 (char 5)"),
            ("1 2", "Extra data: line 1 column 3 (char 2)"),
            ("true false", "Extra data: line 1 column 6 (char 5)"),
            ("[] []", "Extra data: line 1 column 4 (char 3)"),
            ("\"a\"\"b\"", "Extra data: line 1 column 4 (char 3)"),
            ("\"ok\"|", "Extra data: line 1 column 5 (char 4)"),
            // Invalid numbers and literals
            ("-", "Expecting value: line 1 column 1 (char 0)"),
            ("-a", "Expecting value: line 1 column 1 (char 0)"),
            ("-I", "Expecting value: line 1 column 1 (char 0)"),
            ("-Inf", "Expecting value: line 1 column 1 (char 0)"),
            ("-Infin", "Expecting value: line 1 column 1 (char 0)"),
            ("Na", "Expecting value: line 1 column 1 (char 0)"),
            ("Inf", "Expecting value: line 1 column 1 (char 0)"),
            ("nan", "Expecting value: line 1 column 1 (char 0)"),
            ("infinity", "Expecting value: line 1 column 1 (char 0)"),
            ("True", "Expecting value: line 1 column 1 (char 0)"),
            ("False", "Expecting value: line 1 column 1 (char 0)"),
            ("Null", "Expecting value: line 1 column 1 (char 0)"),
            ("[01]", "Expecting ',' delimiter: line 1 column 3 (char 2)"),
            ("01", "Extra data: line 1 column 2 (char 1)"),
            ("00", "Extra data: line 1 column 2 (char 1)"),
            ("-01", "Extra data: line 1 column 3 (char 2)"),
            (".5", "Expecting value: line 1 column 1 (char 0)"),
            ("+1", "Expecting value: line 1 column 1 (char 0)"),
            ("--1", "Expecting value: line 1 column 1 (char 0)"),
            ("1.", "Extra data: line 1 column 2 (char 1)"),
            ("1..2", "Extra data: line 1 column 2 (char 1)"),
            ("1e", "Extra data: line 1 column 2 (char 1)"),
            ("1e+", "Extra data: line 1 column 2 (char 1)"),
            ("1e-", "Extra data: line 1 column 2 (char 1)"),
            ("1e+a", "Extra data: line 1 column 2 (char 1)"),
            ("1e-a", "Extra data: line 1 column 2 (char 1)"),
            ("1e1e1", "Extra data: line 1 column 4 (char 3)"),
            ("1.2.3", "Extra data: line 1 column 4 (char 3)"),
            ("tru", "Expecting value: line 1 column 1 (char 0)"),
            ("nul", "Expecting value: line 1 column 1 (char 0)"),
            ("fals", "Expecting value: line 1 column 1 (char 0)"),
            ("}}}", "Expecting value: line 1 column 1 (char 0)"),
            ("]]]", "Expecting value: line 1 column 1 (char 0)"),
            (":", "Expecting value: line 1 column 1 (char 0)"),
            (",", "Expecting value: line 1 column 1 (char 0)"),
            // Multiline, CRLF, multibyte & astral positions
            (
                "{\"a\":\n tru}",
                "Expecting value: line 2 column 2 (char 7)",
            ),
            (
                "[\n1,\n\"x\" 2]",
                "Expecting ',' delimiter: line 3 column 5 (char 9)",
            ),
            (
                "[\r\n1,\r\n\"é\" 2]",
                "Expecting ',' delimiter: line 3 column 5 (char 11)",
            ),
            (
                "[\"😀\" 2]",
                "Expecting ',' delimiter: line 1 column 6 (char 5)",
            ),
            (
                "{\n  \"a\": 1,\n  \"b\": [1, 2,\n    \"ok\", tru]\n}",
                "Expecting value: line 4 column 11 (char 36)",
            ),
        ];

        assert!(
            cases.len() >= 80,
            "need >= 80 malformed inputs, got {}",
            cases.len()
        );
        for &(tmpl, want) in cases {
            let input = bs(tmpl);
            assert_eq!(J::parse(&input).unwrap_err(), want, "{input:?}");
        }
    }

    #[test]
    fn depth_limit_900_on_32mib_thread() {
        let handle = std::thread::Builder::new()
            .stack_size(32 << 20)
            .spawn(|| {
                fn obj_chain(depth: usize, leaf: &str) -> String {
                    let mut out = String::new();
                    for _ in 0..depth {
                        out.push_str(r#"{"a":"#);
                    }
                    out.push_str(leaf);
                    for _ in 0..depth {
                        out.push('}');
                    }
                    out
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

                let mut depth_cases: Vec<(String, Option<&str>)> = Vec::new();
                for d in [899usize, 900] {
                    depth_cases.push((format!("{}{}", "[".repeat(d), "]".repeat(d)), None));
                    depth_cases.push((format!("{}1{}", "[".repeat(d), "]".repeat(d)), None));
                    depth_cases.push((obj_chain(d, "1"), None));
                    depth_cases.push((mixed_chain(d, false, "0"), None));
                    depth_cases.push((mixed_chain(d, true, "\"ok\""), None));
                }
                depth_cases.push((obj_chain(899, "{}"), None));
                depth_cases.push((
                    obj_chain(900, "{}"),
                    Some("maximum recursion depth exceeded: line 1 column 4501 (char 4500)"),
                ));
                depth_cases.push((
                    format!("{}[],{}{}", "[".repeat(899), "{}", "]".repeat(899)),
                    None,
                ));
                depth_cases.push((
                    format!("{}[],{}{}", "[".repeat(900), "{}", "]".repeat(900)),
                    Some("maximum recursion depth exceeded: line 1 column 901 (char 900)"),
                ));
                depth_cases.push((
                    format!("{}[],[{{}}]{}", "[".repeat(899), "]".repeat(899)),
                    Some("maximum recursion depth exceeded: line 1 column 904 (char 903)"),
                ));
                depth_cases.push((
                    format!("{}{}", "[".repeat(901), "]".repeat(901)),
                    Some("maximum recursion depth exceeded: line 1 column 901 (char 900)"),
                ));
                depth_cases.push((
                    "[".repeat(901),
                    Some("maximum recursion depth exceeded: line 1 column 901 (char 900)"),
                ));
                depth_cases.push((
                    obj_chain(901, "1"),
                    Some("maximum recursion depth exceeded: line 1 column 4501 (char 4500)"),
                ));
                depth_cases.push((
                    mixed_chain(901, false, "0"),
                    Some("maximum recursion depth exceeded: line 1 column 2701 (char 2700)"),
                ));
                depth_cases.push((
                    mixed_chain(901, true, "0"),
                    Some("maximum recursion depth exceeded: line 1 column 2701 (char 2700)"),
                ));
                depth_cases.push((
                    format!("{{\"é\":\n  {}{}}}", "[".repeat(899), "\n  ["),
                    Some("maximum recursion depth exceeded: line 3 column 3 (char 910)"),
                ));

                assert!(depth_cases.len() >= 20);
                for (doc, want_err) in &depth_cases {
                    match want_err {
                        None => assert!(J::parse(doc).is_ok()),
                        Some(want) => assert_eq!(J::parse(doc).unwrap_err(), *want),
                    }
                }
            })
            .unwrap();
        handle.join().unwrap();
    }

    #[test]
    fn pinned_telemetry_file_and_payload_dumps() {
        // 1. Cleaned Gemini CLI settings.json (written by cli::cmd_setup)
        let settings = J::parse(
            r#"{"theme": "dark", "hooks": {
                "AfterModel": [{"matcher": "*", "hooks": [
                    {"name": "telemetry-hook", "command": "python3 x"},
                    {"name": "mine", "command": "echo hi"}]}],
                "BeforeTool": [{"hooks": [{"command": "/x/stream_hook.sh"}]}],
                "Stop": [{"hooks": "not-a-list"}, 3]}}"#,
        )
        .unwrap();
        let (cleaned, _) = crate::cli::strip_legacy_hooks(&settings).unwrap();
        assert_eq!(
            format!("{}\n", dumps(&cleaned, Some(2), true)),
            "{\n  \"theme\": \"dark\",\n  \"hooks\": {\n    \"AfterModel\": [\n      {\n        \"matcher\": \"*\",\n        \"hooks\": [\n          {\n            \"name\": \"mine\",\n            \"command\": \"echo hi\"\n          }\n        ]\n      }\n    ],\n    \"Stop\": [\n      {\n        \"hooks\": \"not-a-list\"\n      },\n      3\n    ]\n  }\n}\n"
        );

        // 2. Saved .telemetry_state.json written via TranscriptScanner::save_state
        let state_dir = std::env::temp_dir().join(format!("agt-json-pin-{}", std::process::id()));
        std::fs::create_dir_all(&state_dir).unwrap();
        let state_path = state_dir.join("state.json");
        let mut scanner = crate::session_exporter::TranscriptScanner::new(
            Some(vec![]),
            Some("/nonexistent"),
            Some(state_path.to_str().unwrap()),
            "http://127.0.0.1:9",
            Some("mbp"),
        );
        scanner.sessions = J::obj(vec![(
            "/Users/james/.gemini/antigravity/brain/é/transcript.jsonl",
            J::obj(vec![
                ("service", J::str("antigravity")),
                ("model", J::str("gemini-3.8-flash")),
                ("offset", J::int(1234)),
                ("turns", J::int(3)),
                ("tools", J::obj(vec![("run_command", J::int(2))])),
                ("subagents", J::int(1)),
                (
                    "tokens",
                    J::obj(vec![
                        ("input", J::int(13500)),
                        ("output", J::int(1050)),
                        ("cached", J::int(96000)),
                        ("thinking", J::int(42)),
                    ]),
                ),
                ("mtime", J::Float(1792885118.2732465)),
            ]),
        )]);
        scanner.save_state();
        let state_bytes = std::fs::read_to_string(&state_path).unwrap();
        let _ = std::fs::remove_dir_all(&state_dir);
        assert_eq!(
            state_bytes,
            "{\n  \"/Users/james/.gemini/antigravity/brain/\\u00e9/transcript.jsonl\": {\n    \"service\": \"antigravity\",\n    \"model\": \"gemini-3.8-flash\",\n    \"offset\": 1234,\n    \"turns\": 3,\n    \"tools\": {\n      \"run_command\": 2\n    },\n    \"subagents\": 1,\n    \"tokens\": {\n      \"input\": 13500,\n      \"output\": 1050,\n      \"cached\": 96000,\n      \"thinking\": 42\n    },\n    \"mtime\": 1792885118.2732465\n  }\n}"
        );

        // 3. OTLP metrics payload (http_client wire JSON: None, false)
        let otlp_m = crate::otlp_builder::build_metrics_payload(
            vec![crate::otlp_builder::build_token_usage_metric(
                &J::int(10),
                &J::int(20),
                &J::int(5),
                &J::int(0),
                &J::str("gemini-x"),
                Some("mbp"),
                Some(1700000000000000000),
            )],
            "antigravity",
            Some("mbp"),
            crate::otlp_builder::SCOPE_NAME,
            crate::otlp_builder::SCOPE_VERSION,
        );
        assert_eq!(
            dumps(&otlp_m, None, false),
            r#"{"resourceMetrics": [{"resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "antigravity"}}, {"key": "service.version", "value": {"stringValue": "1.0.0"}}, {"key": "host.name", "value": {"stringValue": "mbp"}}]}, "scopeMetrics": [{"scope": {"name": "tools/antigravity-telemetry", "version": "1.0.0"}, "metrics": [{"name": "antigravity_token_usage_total", "description": "Total tokens consumed by Antigravity and AGY CLI", "unit": "{tokens}", "sum": {"aggregationTemporality": 2, "isMonotonic": true, "dataPoints": [{"attributes": [{"key": "host", "value": {"stringValue": "mbp"}}, {"key": "token_type", "value": {"stringValue": "input"}}, {"key": "model", "value": {"stringValue": "gemini-x"}}], "timeUnixNano": "1700000000000000000", "asInt": "10"}, {"attributes": [{"key": "host", "value": {"stringValue": "mbp"}}, {"key": "token_type", "value": {"stringValue": "output"}}, {"key": "model", "value": {"stringValue": "gemini-x"}}], "timeUnixNano": "1700000000000000000", "asInt": "20"}, {"attributes": [{"key": "host", "value": {"stringValue": "mbp"}}, {"key": "token_type", "value": {"stringValue": "thinking"}}, {"key": "model", "value": {"stringValue": "gemini-x"}}], "timeUnixNano": "1700000000000000000", "asInt": "5"}, {"attributes": [{"key": "host", "value": {"stringValue": "mbp"}}, {"key": "token_type", "value": {"stringValue": "cached"}}, {"key": "model", "value": {"stringValue": "gemini-x"}}], "timeUnixNano": "1700000000000000000", "asInt": "0"}]}}]}]}]}"#
        );

        // 4. OTLP traces payload (fixed trace/span IDs)
        let mut span_args = crate::otlp_builder::SpanArgs::new("op", 100, 250);
        span_args.trace_id = Some("0123456789abcdef0123456789abcdef".into());
        span_args.span_id = Some("0123456789abcdef".into());
        span_args.attributes = vec![("tool.name", J::str("é"))];
        let otlp_t = crate::otlp_builder::build_traces_payload(
            vec![crate::otlp_builder::build_span(&span_args)],
            "antigravity",
            Some("mbp"),
            crate::otlp_builder::SCOPE_NAME,
            crate::otlp_builder::SCOPE_VERSION,
        );
        assert_eq!(
            dumps(&otlp_t, None, false),
            r#"{"resourceSpans": [{"resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "antigravity"}}, {"key": "service.version", "value": {"stringValue": "1.0.0"}}, {"key": "host.name", "value": {"stringValue": "mbp"}}]}, "scopeSpans": [{"scope": {"name": "tools/antigravity-telemetry", "version": "1.0.0"}, "spans": [{"traceId": "0123456789abcdef0123456789abcdef", "spanId": "0123456789abcdef", "name": "op", "kind": 1, "startTimeUnixNano": "100", "endTimeUnixNano": "250", "attributes": [{"key": "tool.name", "value": {"stringValue": "é"}}], "status": {"code": 1}}]}]}]}"#
        );

        // 5. telemetry_hook payload (None, false)
        let hook_ev = J::parse(r#"{"hook_event": "AfterAgent", "status": "completed"}"#).unwrap();
        let hook_metrics = crate::telemetry_hook::process_event(
            &hook_ev,
            Some("mbp"),
            &mut crate::telemetry_hook::ToolTimers::default(),
        )
        .unwrap();
        let hook_payload =
            crate::telemetry_hook::build_metrics_payload(hook_metrics, "antigravity", "mbp");
        let hook_dump = dumps(&hook_payload, None, false);
        assert!(
            hook_dump.starts_with(
                r#"{"resourceMetrics": [{"resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "antigravity"}}, {"key": "host.name", "value": {"stringValue": "mbp"}}]}, "scopeMetrics": [{"scope": {"name": "antigravity-telemetry", "version": "1.0.0"}, "metrics": [{"name": "antigravity_session_count_total", "description": "Total count of Antigravity / agy interactive sessions", "unit": "{sessions}", "sum": {"aggregationTemporality": 2, "isMonotonic": true, "dataPoints": [{"attributes": [{"key": "host", "value": {"stringValue": "mbp"}}, {"key": "status", "value": {"stringValue": "completed"}}], "timeUnixNano": "#
            ),
            "{hook_dump}"
        );

        // 6. session_exporter wire payload (None, true via send_exporter_payload)
        let exp_wire = J::obj(vec![
            ("host", J::str("mbp")),
            ("tool", J::str("é")),
            ("latency", J::Float(145.0)),
        ]);
        assert_eq!(
            dumps(&exp_wire, None, true),
            r#"{"host": "mbp", "tool": "\u00e9", "latency": 145.0}"#
        );

        // 7. cli --json summary output (Some(2), true)
        let cli_json = J::obj(vec![
            ("status", J::str("success")),
            ("host", J::str("mbp")),
            ("metrics_emitted", J::int(7)),
            ("traces_emitted", J::int(1)),
            ("iterations", J::int(1)),
        ]);
        assert_eq!(
            dumps(&cli_json, Some(2), true),
            "{\n  \"status\": \"success\",\n  \"host\": \"mbp\",\n  \"metrics_emitted\": 7,\n  \"traces_emitted\": 1,\n  \"iterations\": 1\n}"
        );
    }
}
