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

//! Thin adapter over `vitruvian_pycompat::json` preserving `tools/sdk-codegen`'s
//! `PyErr` error reporting (`json.decoder.JSONDecodeError`), `ValueExt` helpers,
//! and `schema_eq`.

use crate::pyerr::PyErr;

pub use vitruvian_pycompat::json::{py_eq, Value};

/// Extension helpers on [`Value`] expected by `tools/sdk-codegen`.
pub trait ValueExt {
    /// `key in d` for a dict.
    fn has(&self, key: &str) -> bool;
    fn as_str(&self) -> Option<&str>;
    fn as_obj(&self) -> Option<&Vec<(String, Value)>>;
    /// Whether this is a JSON number that is not a bool.
    fn is_number(&self) -> bool;
    /// The sign of a number: -1, 0 or 1; None for NaN or a non-number.
    fn sign(&self) -> Option<i32>;
}

impl ValueExt for Value {
    fn has(&self, key: &str) -> bool {
        self.get(key).is_some()
    }

    fn as_str(&self) -> Option<&str> {
        match self {
            Value::Str(s) => Some(s),
            _ => None,
        }
    }

    fn as_obj(&self) -> Option<&Vec<(String, Value)>> {
        match self {
            Value::Obj(items) => Some(items),
            _ => None,
        }
    }

    fn is_number(&self) -> bool {
        matches!(self, Value::Int(_) | Value::Float(_))
    }

    fn sign(&self) -> Option<i32> {
        match self {
            Value::Int(s) => {
                let (neg, digits) = match s.strip_prefix('-') {
                    Some(d) => (true, d),
                    None => (false, s.as_str()),
                };
                if digits.bytes().all(|b| b == b'0') {
                    Some(0)
                } else if neg {
                    Some(-1)
                } else {
                    Some(1)
                }
            }
            Value::Float(f) => {
                if f.is_nan() {
                    None
                } else if *f == 0.0 {
                    Some(0)
                } else if *f < 0.0 {
                    Some(-1)
                } else {
                    Some(1)
                }
            }
            Value::Bool(b) => Some(if *b { 1 } else { 0 }),
            _ => None,
        }
    }
}

/// jsonschema's `_utils.equal`: as `==`, except that a bool equals only a bool.
pub fn schema_eq(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Str(x), Value::Str(y)) => x == y,
        (Value::Str(_), _) | (_, Value::Str(_)) => false,
        (Value::Arr(x), Value::Arr(y)) => {
            x.len() == y.len() && x.iter().zip(y).all(|(l, r)| schema_eq(l, r))
        }
        (Value::Obj(x), Value::Obj(y)) => {
            x.len() == y.len()
                && x.iter().all(|(k, v)| match b.get(k) {
                    Some(w) => schema_eq(v, w),
                    None => false,
                })
        }
        (Value::Bool(x), Value::Bool(y)) => x == y,
        (Value::Bool(_), _) | (_, Value::Bool(_)) => false,
        (Value::Null, Value::Null) => true,
        (Value::Int(_) | Value::Float(_), Value::Int(_) | Value::Float(_)) => py_eq(a, b),
        _ => false,
    }
}

/// `json.loads(text)`, or the JSONDecodeError it raises.
pub fn loads(text: &str) -> Result<Value, PyErr> {
    vitruvian_pycompat::json::loads(text)
        .map_err(|e| PyErr::new("json.decoder.JSONDecodeError", e.python_str()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn msg(text: &str) -> String {
        loads(text).unwrap_err().message
    }

    fn bs(template: &str) -> String {
        const BS: char = '\\';
        template.replace('|', &BS.to_string())
    }

    #[test]
    fn reads_python_extensions() {
        let v = loads(r#"{"a": NaN, "b": -Infinity, "a": 2, "n": 123456789012345678901234567890}"#)
            .unwrap();
        assert_eq!(v.get("a").unwrap().py_repr(), "2");
        let keys: Vec<&str> = v
            .as_obj()
            .unwrap()
            .iter()
            .map(|(k, _)| k.as_str())
            .collect();
        assert_eq!(keys, ["a", "b", "n"]);
        assert_eq!(
            v.get("n").unwrap().py_repr(),
            "123456789012345678901234567890"
        );
        assert_eq!(v.get("b").unwrap().py_repr(), "-inf");
    }

    #[test]
    fn errors_name_the_place_as_python_does() {
        assert_eq!(msg(""), "Expecting value: line 1 column 1 (char 0)");
        assert_eq!(msg("[1,]"), "Expecting value: line 1 column 4 (char 3)");
        assert_eq!(
            msg("{\"a\":1,}"),
            "Expecting property name enclosed in double quotes: line 1 column 8 (char 7)"
        );
        assert_eq!(msg("{} x"), "Extra data: line 1 column 4 (char 3)");
        assert_eq!(
            msg("\n\"ab"),
            "Unterminated string starting at: line 2 column 1 (char 1)"
        );
        assert_eq!(
            msg(&bs("\"a|q\"")),
            bs("Invalid |escape: line 1 column 3 (char 2)")
        );
        assert_eq!(
            msg(&bs("\"|u12\"")),
            bs("Invalid |uXXXX escape: line 1 column 3 (char 2)")
        );
        assert_eq!(
            msg("\"a\nb\""),
            "Invalid control character at: line 1 column 3 (char 2)"
        );
        assert_eq!(
            msg("\u{feff}{}"),
            "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)"
        );
        assert_eq!(
            msg("{\"a\" 1}"),
            "Expecting ':' delimiter: line 1 column 6 (char 5)"
        );
        assert_eq!(
            msg("[1 2]"),
            "Expecting ',' delimiter: line 1 column 4 (char 3)"
        );
        assert_eq!(msg("-"), "Expecting value: line 1 column 1 (char 0)");
        assert_eq!(msg("01"), "Extra data: line 1 column 2 (char 1)");
    }

    #[test]
    fn numbers_and_strings() {
        assert_eq!(loads("1e5").unwrap().py_repr(), "100000.0");
        assert_eq!(loads("-0").unwrap().py_repr(), "0");
        assert_eq!(loads("1.5E-7").unwrap().py_repr(), "1.5e-07");
        assert!(loads("1e").is_err());
        let v = loads(&bs(r#""|ud83d|ude00 |u00e9 |/""#)).unwrap();
        assert_eq!(v.py_str(), "\u{1F600} \u{e9} /");
    }

    #[test]
    fn equality() {
        let t = Value::Bool(true);
        let one = Value::Int("1".into());
        let onef = Value::Float(1.0);
        assert!(py_eq(&t, &one));
        assert!(py_eq(&one, &onef));
        assert!(!schema_eq(&t, &one));
        assert!(schema_eq(&one, &onef));
        assert!(!py_eq(&Value::Float(f64::NAN), &Value::Float(f64::NAN)));
        let a = loads(r#"{"x": 1, "y": [true]}"#).unwrap();
        let b = loads(r#"{"y": [1], "x": 1.0}"#).unwrap();
        assert!(py_eq(&a, &b));
        assert!(!schema_eq(&a, &b));
        assert!(!Value::Int("-0".into()).truthy());
        assert_eq!(
            loads("[1, \"it's\", null, {}]").unwrap().py_repr(),
            "[1, \"it's\", None, {}]"
        );
    }

    #[test]
    fn schema_eq_and_value_ext() {
        let obj = loads(r#"{"a": "hi", "b": 0}"#).unwrap();
        assert!(obj.has("a"));
        assert!(!obj.has("missing"));
        assert_eq!(obj.get("a").unwrap().as_str(), Some("hi"));
        assert_eq!(obj.get("b").unwrap().as_str(), None);
        assert_eq!(ValueExt::as_obj(&obj).map(Vec::len), Some(2));
        assert_eq!(Value::Null.as_obj(), None);

        assert!(Value::Int("0".into()).is_number());
        assert!(Value::Float(1.5).is_number());
        assert!(!Value::Bool(true).is_number());
        assert!(!Value::Str("1".into()).is_number());

        assert_eq!(Value::Int("0".into()).sign(), Some(0));
        assert_eq!(Value::Int("-0".into()).sign(), Some(0));
        assert_eq!(Value::Int("-000".into()).sign(), Some(0));
        assert_eq!(Value::Int("-42".into()).sign(), Some(-1));
        assert_eq!(Value::Int("42".into()).sign(), Some(1));
        assert_eq!(Value::Float(0.0).sign(), Some(0));
        assert_eq!(Value::Float(-0.0).sign(), Some(0));
        assert_eq!(Value::Float(-1.5).sign(), Some(-1));
        assert_eq!(Value::Float(1.5).sign(), Some(1));
        assert_eq!(Value::Float(f64::NAN).sign(), None);
        assert_eq!(Value::Bool(true).sign(), Some(1));
        assert_eq!(Value::Bool(false).sign(), Some(0));
        assert_eq!(Value::Null.sign(), None);

        assert!(schema_eq(&Value::Null, &Value::Null));
        assert!(schema_eq(&Value::Bool(true), &Value::Bool(true)));
        assert!(!schema_eq(&Value::Bool(true), &Value::Bool(false)));
        assert!(!schema_eq(&Value::Bool(false), &Value::Int("0".into())));
        assert!(!schema_eq(&Value::Bool(false), &Value::Float(0.0)));
        assert!(schema_eq(&Value::Int("-0".into()), &Value::Float(0.0)));
        assert!(!schema_eq(&Value::Float(f64::NAN), &Value::Float(f64::NAN)));
    }

    #[test]
    fn malformed_inputs_match_cpython_312() {
        let cases: &[(&str, &str)] = &[
            ("", "Expecting value: line 1 column 1 (char 0)"),
            ("   \n\t\r  ", "Expecting value: line 2 column 5 (char 8)"),
            ("\n", "Expecting value: line 2 column 1 (char 1)"),
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
            ("\"a|q\"", "Invalid \\escape: line 1 column 3 (char 2)"),
            ("\"|x\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            ("\"|a\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            ("\"|1\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            ("\"|'\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            ("\"|0\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            ("\"|v\"", "Invalid \\escape: line 1 column 2 (char 1)"),
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
            // Complete \uXXXX right at EOF: CPython 3.12 reports "Invalid \uXXXX escape".
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
            (
                "\"|u0041x",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "\"||u0041",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "\n\"ab",
                "Unterminated string starting at: line 2 column 1 (char 1)",
            ),
            (
                "\"abc",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "[\"abc",
                "Unterminated string starting at: line 1 column 2 (char 1)",
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
            (
                "{",
                "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)",
            ),
            (
                "{\"a\" 1}",
                "Expecting ':' delimiter: line 1 column 6 (char 5)",
            ),
            (
                "{\"a\"}",
                "Expecting ':' delimiter: line 1 column 5 (char 4)",
            ),
            ("{\"a\":}", "Expecting value: line 1 column 6 (char 5)"),
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
                "{\"a\": \"b\", \"c\" 3}",
                "Expecting ':' delimiter: line 1 column 16 (char 15)",
            ),
            (
                "{\"a\": [1, 2], \"b\": {\"c\":}}",
                "Expecting value: line 1 column 25 (char 24)",
            ),
            ("[1 2]", "Expecting ',' delimiter: line 1 column 4 (char 3)"),
            (
                "{\"a\": 1 \"b\": 2}",
                "Expecting ',' delimiter: line 1 column 9 (char 8)",
            ),
            (
                "[1, 2 3]",
                "Expecting ',' delimiter: line 1 column 7 (char 6)",
            ),
            ("[", "Expecting value: line 1 column 2 (char 1)"),
            ("[1", "Expecting ',' delimiter: line 1 column 3 (char 2)"),
            ("[[[", "Expecting value: line 1 column 4 (char 3)"),
            ("[1,]", "Expecting value: line 1 column 4 (char 3)"),
            (
                "{\"a\":1,}",
                "Expecting property name enclosed in double quotes: line 1 column 8 (char 7)",
            ),
            (
                "{\"a\": 1,}",
                "Expecting property name enclosed in double quotes: line 1 column 9 (char 8)",
            ),
            ("[,]", "Expecting value: line 1 column 2 (char 1)"),
            (
                "{,}",
                "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)",
            ),
            ("{} x", "Extra data: line 1 column 4 (char 3)"),
            ("1 2", "Extra data: line 1 column 3 (char 2)"),
            ("true false", "Extra data: line 1 column 6 (char 5)"),
            ("[] []", "Extra data: line 1 column 4 (char 3)"),
            ("\"a\"\"b\"", "Extra data: line 1 column 4 (char 3)"),
            ("\"ok\"|", "Extra data: line 1 column 5 (char 4)"),
            ("-", "Expecting value: line 1 column 1 (char 0)"),
            ("-a", "Expecting value: line 1 column 1 (char 0)"),
            ("-I", "Expecting value: line 1 column 1 (char 0)"),
            ("-Inf", "Expecting value: line 1 column 1 (char 0)"),
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
            ("1.", "Extra data: line 1 column 2 (char 1)"),
            ("1..2", "Extra data: line 1 column 2 (char 1)"),
            ("--1", "Expecting value: line 1 column 1 (char 0)"),
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

        assert!(cases.len() >= 80, "need at least 80 malformed inputs");
        for &(tmpl, want) in cases {
            let input = bs(tmpl);
            let err = loads(&input).unwrap_err();
            assert_eq!(err.class, "json.decoder.JSONDecodeError", "{input:?}");
            assert_eq!(err.message, want, "{input:?}");
            assert_eq!(
                err.render(),
                format!("json.decoder.JSONDecodeError: {want}"),
                "{input:?}"
            );
        }
    }

    #[test]
    fn cli_traceback_for_malformed_json() {
        let dir = std::env::temp_dir().join(format!("sdk-codegen-json-err-{}", std::process::id()));
        let proto = dir.join("protocol");
        std::fs::create_dir_all(&proto).unwrap();
        std::fs::write(proto.join("messages.schema.json"), "{\"a\": 1").unwrap();

        let args = vec![
            "sdk-codegen".to_string(),
            "--check".to_string(),
            "--package".to_string(),
            dir.to_string_lossy().to_string(),
        ];
        let mut out = Vec::new();
        let mut err = Vec::new();
        let code = crate::cli::run(&args, &mut out, &mut err);
        let _ = std::fs::remove_dir_all(&dir);

        assert_eq!(code, 1);
        assert!(out.is_empty());
        assert_eq!(
            String::from_utf8_lossy(&err),
            "Traceback (most recent call last):\n  (sdk-codegen-rs: Python's stack frames are not reproduced)\njson.decoder.JSONDecodeError: Expecting ',' delimiter: line 1 column 8 (char 7)\n"
        );
    }
}
