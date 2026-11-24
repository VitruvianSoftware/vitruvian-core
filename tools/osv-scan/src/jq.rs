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

//! `git show <rev>:<file> | jq -S 'del(.version)'`, compared across two
//! revisions, without jq.
//!
//! Powered by `vitruvian_jq`: both sides must parse as a jq 1.8 stream,
//! `del(.version)` must succeed on every value (objects and null only), and
//! the sorted compact canonical outputs must be identical.

use vitruvian_jq::{compact_sorted, parse_stream, StreamItem};

fn canon(input: &[u8]) -> Option<Vec<String>> {
    let mut out = Vec::new();
    for item in parse_stream(input) {
        match item {
            StreamItem::Value(mut v, _) => {
                v.del_key("version").ok()?;
                out.push(compact_sorted(&v));
            }
            StreamItem::ParseError(_) => return None,
        }
    }
    Some(out)
}

/// The comparison the script makes: `_old = $(git show base:f | jq -S
/// 'del(.version)' || echo UNPARSEABLE_OLD)`, likewise `_new`, then `=`.
/// `None` stands for a failed `git show`.
pub fn same_without_version(old: Option<&[u8]>, new: Option<&[u8]>) -> bool {
    match (old.and_then(canon), new.and_then(canon)) {
        (Some(a), Some(b)) => a == b,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use vitruvian_jq::{parse_one, Value};

    fn num(s: &str) -> String {
        match &parse_one(s.as_bytes()).unwrap() {
            Value::Number(n) => n.fmt_jq(),
            Value::Null => "null".into(),
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn numbers_print_like_jq() {
        // Each pair observed from jq 1.7.1 and 1.8.2.
        for (lit, want) in [
            ("1.000", "1.000"),
            ("1E2", "1E+2"),
            ("1.0", "1.0"),
            ("100000000000000000001", "100000000000000000001"),
            ("0.1e1", "1"),
            ("-0", "-0"),
            ("1.5e300", "1.5E+300"),
            ("-0.0", "-0.0"),
            ("1e1000", "1E+1000"),
            ("01", "1"),
            ("+1", "1"),
            (".5", "0.5"),
            ("1.", "1"),
            ("0.10", "0.10"),
            ("1.5e-7", "1.5E-7"),
            ("0.0000001", "1E-7"),
            ("0e5", "0E+5"),
            ("123e-2", "1.23"),
            ("-1.20E+3", "-1.20E+3"),
            ("Infinity", "1.7976931348623157e+308"),
            ("-Infinity", "-1.7976931348623157e+308"),
            ("infinity", "1.7976931348623157e+308"),
            ("NaN", "null"),
            ("-nan", "null"),
        ] {
            assert_eq!(num(lit), want, "{lit}");
        }
    }

    #[test]
    fn parse_errors_like_jq() {
        for bad in [
            "{\"x\":1,}",
            "{'x':1}",
            "{\"x\":\"\\ud800\"}",
            "{\"x\":\"a\tb\"}",
            "{\"x\":\"\\q\"}",
            "[1,2,]",
            "{\"x\":-}",
            "{\"x\":1e}",
            "{\"x\":1}x",
            "tru",
            "{1:2}",
            "nan123",
            "snan123",
        ] {
            assert!(canon(bad.as_bytes()).is_none(), "{bad}");
        }
        assert_eq!(canon(b"").unwrap(), Vec::<String>::new());
        assert_eq!(canon(b"{}{} ").unwrap().len(), 2);
        assert!(canon(b"\xef\xbb\xbf{\"x\":1}").is_some());
        // Lone low surrogate decodes to U+FFFD in jq 1.8.2.
        assert_eq!(
            canon(br#"{"x":"\udc00"}"#).unwrap(),
            vec!["{\"x\":\"\u{fffd}\"}".to_string()]
        );
    }

    #[test]
    fn version_only_changes_compare_equal() {
        let a = br#"{"name":"x","version":"1.0.0","dependencies":{"a":"^1"}}"#;
        let b = br#"{"dependencies": {"a": "^1"}, "version": "1.0.1", "name": "x"}"#;
        assert!(same_without_version(Some(a), Some(b)));
        let c = br#"{"name":"x","version":"1.0.1","dependencies":{"a":"^2"}}"#;
        assert!(!same_without_version(Some(a), Some(c)));
        assert!(!same_without_version(None, Some(b)));
        assert!(!same_without_version(Some(b"[]"), Some(b"[]")));
        assert!(same_without_version(Some(b""), Some(b"  \n")));
        // In jq 1.8.2, top-level `nan` is a number and `del(.version)` fails,
        // while inside an object `nan` prints as `null`.
        assert!(!same_without_version(Some(b"null"), Some(b"nan")));
        assert!(same_without_version(
            Some(br#"{"a":null}"#),
            Some(br#"{"a":nan}"#)
        ));
        assert!(!same_without_version(
            Some(br#"{"a":1}"#),
            Some(br#"{"a":1.0}"#)
        ));
        assert!(same_without_version(
            Some(br#"{"a":1,"a":2}"#),
            Some(br#"{"a":2}"#)
        ));
    }

    fn nested_version_doc(version: &str, array_depth: usize) -> Vec<u8> {
        let mut buf = Vec::with_capacity(32 + array_depth * 2);
        buf.extend_from_slice(br#"{"version":""#);
        buf.extend_from_slice(version.as_bytes());
        buf.extend_from_slice(br#"","x":"#);
        buf.resize(buf.len() + array_depth, b'[');
        buf.push(b'1');
        buf.resize(buf.len() + array_depth, b']');
        buf.push(b'}');
        buf
    }

    #[test]
    fn depth_at_jq_limit_compares_version_only() {
        // Object + 9,998 arrays = depth 10,000, accepted by jq 1.8.2 (exit 0).
        let a = nested_version_doc("1", 9_998);
        let b = nested_version_doc("2", 9_998);
        assert!(same_without_version(Some(&a), Some(&b)));
    }

    #[test]
    fn depth_over_jq_limit_fails_closed() {
        // Object + 9,999 arrays = depth 10,001, rejected by jq 1.8.2 (exit 5).
        let a = nested_version_doc("1", 9_999);
        let b = nested_version_doc("2", 9_999);
        assert!(!same_without_version(Some(&a), Some(&b)));
    }
}
