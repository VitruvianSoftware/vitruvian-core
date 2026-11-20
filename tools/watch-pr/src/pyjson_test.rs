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

use crate::pyjson::{float_repr, loads, str_repr, Value};

#[test]
fn float_reprs_match_python() {
    for (f, want) in [
        (1.0, "1.0"),
        (100.0, "100.0"),
        (0.1, "0.1"),
        (1.5, "1.5"),
        (0.0001, "0.0001"),
        (0.00001, "1e-05"),
        (1e15, "1000000000000000.0"),
        (1e16, "1e+16"),
        (1.5e300, "1.5e+300"),
        (-0.0, "-0.0"),
        (0.0, "0.0"),
        (123456.789, "123456.789"),
        (2.5e-7, "2.5e-07"),
    ] {
        assert_eq!(float_repr(f), want, "{f}");
    }
}

#[test]
fn string_reprs_match_python() {
    assert_eq!(str_repr("abc"), "'abc'");
    assert_eq!(str_repr("it's"), "\"it's\"");
    assert_eq!(str_repr("it's \"x\""), "'it\\'s \"x\"'");
    assert_eq!(str_repr("a\tb\nc\\"), "'a\\tb\\nc\\\\'");
    assert_eq!(str_repr("\u{7f}\u{1}"), "'\\x7f\\x01'");
    assert_eq!(str_repr("é✓\u{a0}\u{200b}"), "'é✓\\xa0\\u200b'");
    assert_eq!(str_repr("\u{e0001}"), "'\\U000e0001'");
    // Unassigned code point in Unicode 15.0 (Python 3.12) must be escaped.
    assert_eq!(str_repr("\u{0378}"), "'\\u0378'");
}

#[test]
fn containers_key_order_and_duplicate_keys() {
    let v = loads(r#"{"b":[1,"a",null,true,1.0],"a":{"k":"v"},"b":[]}"#).unwrap();
    assert_eq!(v.py_str(), "{'b': [], 'a': {'k': 'v'}}");
    let dup = loads(r#"{"z": 1, "a": 2, "z": 3, "m": 4}"#).unwrap();
    assert_eq!(dup.py_str(), "{'z': 3, 'a': 2, 'm': 4}");
    assert_eq!(dup.get("z"), Some(&Value::Int(3)));
    assert_eq!(dup.get("missing"), None);
    assert_eq!(Value::Int(1).get("z"), None);
    assert_eq!(
        loads(r#"[1,"a",null,true,1.0]"#).unwrap().py_str(),
        "[1, 'a', None, True, 1.0]"
    );
}

#[test]
fn escapes_surrogates_and_errors() {
    let v = loads(r#""\ud83d\ude00 \u00e9 \/ \t\n\r\"\\""#).unwrap();
    assert_eq!(v.py_str(), "\u{1F600} \u{e9} / \t\n\r\"\\");
    assert_eq!(v.py_repr(), "'😀 é / \\t\\n\\r\"\\\\'");
    assert!(loads("{} x").is_err());
    assert!(loads("NaN").is_err());
    assert!(loads("").is_err());
}

#[test]
fn truthiness_and_type_names() {
    for falsy in ["null", "false", "0", "0.0", "\"\"", "[]", "{}"] {
        assert!(!loads(falsy).unwrap().truthy(), "{falsy}");
    }
    for truthy in ["true", "1", "-0.5", "\"x\"", "[0]", "{\"a\":0}"] {
        assert!(loads(truthy).unwrap().truthy(), "{truthy}");
    }
    assert_eq!(Value::None.type_name(), "NoneType");
    assert_eq!(Value::Bool(false).type_name(), "bool");
    assert_eq!(Value::Int(0).type_name(), "int");
    assert_eq!(Value::Float(0.0).type_name(), "float");
    assert_eq!(Value::Str(String::new()).type_name(), "str");
    assert_eq!(Value::List(vec![]).type_name(), "list");
    assert_eq!(Value::Dict(vec![]).type_name(), "dict");
}
