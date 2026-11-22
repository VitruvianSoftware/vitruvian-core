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

//! Thin adapter over `vitruvian_pycompat::json` preserving `tools/gitops`'s
//! `JsonError` `Display` format (`"{msg}: line {line} column {col} (char {pos})"`).

pub use vitruvian_pycompat::json::{dedup, dumps, py_eq, Value};

/// A document that does not parse, worded as `json.JSONDecodeError` words it:
/// `Expecting value: line 1 column 1 (char 0)`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct JsonError(pub vitruvian_pycompat::json::JsonError);

impl std::fmt::Display for JsonError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0.python_str())
    }
}

pub fn loads(text: &str) -> Result<Value, JsonError> {
    vitruvian_pycompat::json::loads(text).map_err(JsonError)
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
    fn python_equality() {
        let v = |t: &str| loads(t).unwrap();
        assert!(py_eq(&v("1"), &v("true")));
        assert!(py_eq(&v("1.0"), &v("1")));
        assert!(py_eq(&v("-0.0"), &v("0")));
        assert!(py_eq(&v("1e20"), &v("100000000000000000000")));
        assert!(!py_eq(&v("1.5"), &v("1")));
        assert!(!py_eq(&v("\"1\""), &v("1")));
        assert!(!py_eq(&v("NaN"), &v("NaN")));
        assert!(py_eq(
            &v(r#"{"a": [1, null], "b": 2}"#),
            &v(r#"{"b": 2.0, "a": [true, null]}"#)
        ));
        assert!(!py_eq(&v(r#"{"a": 1}"#), &v(r#"{"a": 1, "b": 2}"#)));
        assert!(!py_eq(&v("null"), &v("0")));
    }

    #[test]
    fn errors_read_as_python_words_them() {
        let e = |t: &str| loads(t).unwrap_err().to_string();
        assert_eq!(e(""), "Expecting value: line 1 column 1 (char 0)");
        assert_eq!(
            e("{"),
            "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)"
        );
        assert_eq!(e("[1,]"), "Expecting value: line 1 column 4 (char 3)");
        assert_eq!(
            e("{\"a\" 1}"),
            "Expecting ':' delimiter: line 1 column 6 (char 5)"
        );
        assert_eq!(e("{} x"), "Extra data: line 1 column 4 (char 3)");
        assert_eq!(
            e("[1 2]"),
            "Expecting ',' delimiter: line 1 column 4 (char 3)"
        );
        assert_eq!(
            e("[\"abc"),
            "Unterminated string starting at: line 1 column 2 (char 1)"
        );
        assert_eq!(
            e("\"ab\\"),
            "Unterminated string starting at: line 1 column 1 (char 0)"
        );
        assert_eq!(
            e("{\"a\":\n tru}"),
            "Expecting value: line 2 column 2 (char 7)"
        );
        assert_eq!(
            e("\u{feff}{}"),
            "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)"
        );
        assert_eq!(e("\"\\x\""), "Invalid \\escape: line 1 column 2 (char 1)");
        assert_eq!(
            e("\"\\u12\""),
            "Invalid \\uXXXX escape: line 1 column 3 (char 2)"
        );
        assert_eq!(
            e("\"\\ud800\\u12\""),
            "Invalid \\uXXXX escape: line 1 column 9 (char 8)"
        );
        assert_eq!(
            e("\"a\nb\""),
            "Invalid control character at: line 1 column 3 (char 2)"
        );
        assert_eq!(
            e("[01]"),
            "Expecting ',' delimiter: line 1 column 3 (char 2)"
        );
        assert_eq!(e("-I"), "Expecting value: line 1 column 1 (char 0)");
    }

    #[test]
    fn malformed_inputs_match_cpython_312() {
        let cases: &[(&str, &str)] = &[
            // Empty / whitespace
            ("", "Expecting value: line 1 column 1 (char 0)"),
            ("   \n\t\r  ", "Expecting value: line 2 column 5 (char 8)"),
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
            // Bad escape
            (r#""\x""#, "Invalid \\escape: line 1 column 2 (char 1)"),
            (r#""\a""#, "Invalid \\escape: line 1 column 2 (char 1)"),
            (r#""\1""#, "Invalid \\escape: line 1 column 2 (char 1)"),
            (r#""\'""#, "Invalid \\escape: line 1 column 2 (char 1)"),
            (r#""\0""#, "Invalid \\escape: line 1 column 2 (char 1)"),
            // Bad \u (in string)
            (
                r#""\u12""#,
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                r#""\u123g""#,
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                r#""\uZZZZ""#,
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                r#""\u 123""#,
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                r#""\ud800\u12""#,
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                r#""\ud800\u123g""#,
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            // Truncated \u at EOF
            ("\"\\u", "Invalid \\uXXXX escape: line 1 column 3 (char 2)"),
            ("\"\\u1", "Invalid \\uXXXX escape: line 1 column 3 (char 2)"),
            (
                "\"\\u12",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"\\u123",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"\\ud800\\u",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"\\ud800\\u12",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            // Complete \uXXXX immediately at EOF:
            // CPython 3.12 reports "Invalid \uXXXX escape"; CPython 3.13+ reports "Unterminated string starting at".
            (
                "\"\\u0041",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            // CPython 3.12 reports "Invalid \uXXXX escape"; CPython 3.13+ reports "Unterminated string starting at".
            (
                "\"ab\\u0041",
                "Invalid \\uXXXX escape: line 1 column 5 (char 4)",
            ),
            // CPython 3.12 reports "Invalid \uXXXX escape"; CPython 3.13+ reports "Unterminated string starting at".
            (
                "\"\\ud800\\u0041",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            // CPython 3.12 reports "Invalid \uXXXX escape"; CPython 3.13+ reports "Unterminated string starting at".
            (
                "\"\\ud800\\udc00",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            // CPython 3.12 reports "Invalid \uXXXX escape"; CPython 3.13+ reports "Unterminated string starting at".
            (
                "\"\\ud800",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            // CPython 3.12 reports "Invalid \uXXXX escape"; CPython 3.13+ reports "Unterminated string starting at".
            (
                "[\"\\u0041",
                "Invalid \\uXXXX escape: line 1 column 4 (char 3)",
            ),
            // Control cases around \uXXXX + EOF
            (
                "\"\\u0041x",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "\"\\\\u0041",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            // Unterminated string
            (
                "\"abc",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "[\"abc",
                "Unterminated string starting at: line 1 column 2 (char 1)",
            ),
            (
                "\"ab\\",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "\"\\",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "\"\\\"",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            // Control chars
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
                "\"a\x1fb\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            // Missing colon / bad object key / unclosed object
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
            // Missing comma / unclosed array
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
            // Trailing comma
            ("[1,]", "Expecting value: line 1 column 4 (char 3)"),
            (
                "{\"a\": 1,}",
                "Expecting property name enclosed in double quotes: line 1 column 9 (char 8)",
            ),
            ("[,]", "Expecting value: line 1 column 2 (char 1)"),
            // Extra data
            ("{} x", "Extra data: line 1 column 4 (char 3)"),
            ("1 2", "Extra data: line 1 column 3 (char 2)"),
            ("true false", "Extra data: line 1 column 6 (char 5)"),
            ("[] []", "Extra data: line 1 column 4 (char 3)"),
            ("\"a\"\"b\"", "Extra data: line 1 column 4 (char 3)"),
            // Invalid numbers / literals
            ("-", "Expecting value: line 1 column 1 (char 0)"),
            ("-a", "Expecting value: line 1 column 1 (char 0)"),
            ("-I", "Expecting value: line 1 column 1 (char 0)"),
            ("-Inf", "Expecting value: line 1 column 1 (char 0)"),
            ("Na", "Expecting value: line 1 column 1 (char 0)"),
            ("Inf", "Expecting value: line 1 column 1 (char 0)"),
            ("[01]", "Expecting ',' delimiter: line 1 column 3 (char 2)"),
            ("01", "Extra data: line 1 column 2 (char 1)"),
            (".5", "Expecting value: line 1 column 1 (char 0)"),
            ("+1", "Expecting value: line 1 column 1 (char 0)"),
            ("1.", "Extra data: line 1 column 2 (char 1)"),
            ("1e", "Extra data: line 1 column 2 (char 1)"),
            ("1e+", "Extra data: line 1 column 2 (char 1)"),
            ("1e-", "Extra data: line 1 column 2 (char 1)"),
            ("tru", "Expecting value: line 1 column 1 (char 0)"),
            ("nul", "Expecting value: line 1 column 1 (char 0)"),
            ("fals", "Expecting value: line 1 column 1 (char 0)"),
            // Multiline / multibyte / astral error locations
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
        ];

        assert!(cases.len() >= 30, "need at least 30 malformed inputs");
        for &(input, want) in cases {
            assert_eq!(loads(input).unwrap_err().to_string(), want, "{input:?}");
        }
    }
}
