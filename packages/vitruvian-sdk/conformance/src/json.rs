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

//! Thin adapter over `vitruvian_pycompat::json` preserving `conformance_rs_lib`'s
//! `String`-error `loads`/`loads_bytes` helpers and re-exporting `Value`, `py_eq`,
//! and `normalize_int`.

pub use vitruvian_pycompat::json::{normalize_int, py_eq, Value};

pub fn loads_bytes(bytes: &[u8]) -> Result<Value, String> {
    let text = std::str::from_utf8(bytes).map_err(|e| e.to_string())?;
    loads(text)
}

pub fn loads(text: &str) -> Result<Value, String> {
    vitruvian_pycompat::json::loads(text).map_err(|e| e.python_str())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bs(template: &str) -> String {
        const BS: char = '\\';
        assert!(
            !template.contains(BS),
            "build escapes with '|' instead of literal backslashes: {template:?}"
        );
        template.replace('|', &BS.to_string())
    }

    #[test]
    fn loads_and_loads_bytes_preserve_python_semantics() {
        let raw = r#"{"a": NaN, "b": -Infinity, "c": Infinity, "a": 2, "n": 123456789012345678901234567890}"#;
        let v = loads_bytes(raw.as_bytes()).unwrap();
        assert_eq!(v.get("a"), Some(&Value::Int("2".into())));
        assert_eq!(
            v.get("n").unwrap().py_repr(),
            "123456789012345678901234567890"
        );
        assert!(matches!(v.get("b"), Some(Value::Float(f)) if f.is_infinite() && *f < 0.0));
        assert!(matches!(v.get("c"), Some(Value::Float(f)) if f.is_infinite() && *f > 0.0));

        assert!(loads_bytes(&[0xff, 0xfe]).is_err());
        assert_eq!(
            loads("\u{feff}{}").unwrap_err(),
            "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)"
        );
        assert_eq!(
            loads(&bs("\"|u0041")).unwrap_err(),
            bs("Invalid |uXXXX escape: line 1 column 3 (char 2)")
        );
    }

    #[test]
    fn value_methods_and_dumps_compact_match_conformance() {
        let escaped = loads(&bs(r#""|ud83d|ude00 |u00e9 |/ |"|| |b|f|n|r|t""#)).unwrap();
        assert!(escaped.is_str());
        assert_eq!(
            escaped.as_str(),
            Some("\u{1F600} \u{e9} / \"\x5c \u{8}\u{c}\n\r\t")
        );
        assert_eq!(
            escaped.dumps_compact(),
            bs(r#""|ud83d|ude00 |u00e9 / |"|| |b|f|n|r|t""#)
        );

        let obj = loads(r#"{"flag": true, "neg_zero": -0, "whole": 4.0, "arr": [1, 2]}"#).unwrap();
        assert!(obj.is_dict());
        assert!(obj.has("flag"));
        assert!(!obj.has("missing"));
        assert_eq!(obj.as_obj().map(|items| items.len()), Some(4));

        let flag = obj.get("flag").unwrap();
        assert!(flag.is_bool());
        assert_eq!(flag.as_bool(), Some(true));
        assert!(!flag.is_number());

        let neg_zero = obj.get("neg_zero").unwrap();
        assert!(neg_zero.is_int());
        assert!(neg_zero.is_number());
        assert!(neg_zero.is_whole());
        assert!(neg_zero.is_non_negative());
        assert_eq!(neg_zero.py_str(), "0");
        assert_eq!(normalize_int("-000"), "0");

        let whole = obj.get("whole").unwrap();
        assert!(whole.is_number());
        assert!(whole.is_whole());
        assert!(whole.is_non_negative());

        let arr = obj.get("arr").unwrap();
        assert!(arr.is_list());
        assert_eq!(arr.as_arr().map(|items| items.len()), Some(2));
        assert!(py_eq(neg_zero, &Value::Bool(false)));
        assert_eq!(
            obj.py_repr(),
            "{'flag': True, 'neg_zero': 0, 'whole': 4.0, 'arr': [1, 2]}"
        );
        assert_eq!(
            obj.dumps_compact(),
            r#"{"flag":true,"neg_zero":0,"whole":4.0,"arr":[1,2]}"#
        );
    }
}
