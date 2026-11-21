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

use crate::json::{dedup, loads, py_eq, Value};

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
    assert!(loads("\u{feff}{}").is_err());
}

#[test]
fn strings_and_surrogates() {
    let v = loads(r#""\ud83d\ude00 \u00e9 \/ \b\f\n\r\t \"\\""#).unwrap();
    assert_eq!(
        v,
        Value::Str("\u{1F600} \u{e9} / \u{8}\u{c}\n\r\t \"\\".into())
    );
    // Lone high surrogate falls back cleanly to U+FFFD in UTF-8 strings.
    let lone = loads(r#""\ud800""#).unwrap();
    assert_eq!(lone, Value::Str("\u{fffd}".into()));
    assert!(loads("\"a\nb\"").is_err());
}

#[test]
fn key_order_and_duplicate_keys() {
    let v = loads(r#"{"z": 1, "a": 2, "z": 3, "m": 4}"#).unwrap();
    assert_eq!(v.py_repr(), "{'z': 3, 'a': 2, 'm': 4}");
    let raw = vec![
        ("b".to_string(), Value::Int("1".into())),
        ("a".into(), Value::Int("2".into())),
        ("b".into(), Value::Int("3".into())),
    ];
    assert_eq!(
        dedup(&raw),
        vec![
            ("b".to_string(), Value::Int("3".into())),
            ("a".to_string(), Value::Int("2".into())),
        ]
    );
}

#[test]
fn repr_and_float_formatting() {
    let v = loads(r#"[{"message": "it's", "n": null, "t": true}, 1.0, -0]"#).unwrap();
    assert_eq!(
        v.py_repr(),
        r#"[{'message': "it's", 'n': None, 't': True}, 1.0, 0]"#
    );
    assert_eq!(Value::Str("it's".into()).py_str(), "it's");
    assert_eq!(Value::Str("it's".into()).py_repr(), "\"it's\"");
    assert_eq!(loads("1e15").unwrap().py_repr(), "1000000000000000.0");
    assert_eq!(loads("1e16").unwrap().py_repr(), "1e+16");
    assert_eq!(loads("0.0001").unwrap().py_repr(), "0.0001");
    assert_eq!(loads("0.00001").unwrap().py_repr(), "1e-05");
    assert_eq!(loads("1.5e-7").unwrap().py_repr(), "1.5e-07");
    assert_eq!(loads("-0.0").unwrap().py_repr(), "-0.0");
    assert_eq!(loads("NaN").unwrap().py_repr(), "nan");
    assert_eq!(loads("Infinity").unwrap().py_repr(), "inf");
    assert_eq!(loads("-Infinity").unwrap().py_repr(), "-inf");
}

#[test]
fn python_equality() {
    let int = |s: &str| Value::Int(s.into());
    assert!(py_eq(&int("101"), &Value::Float(101.0)));
    assert!(py_eq(&int("1"), &Value::Bool(true)));
    assert!(py_eq(&int("0"), &Value::Bool(false)));
    assert!(py_eq(&int("-0"), &int("0")));
    assert!(!py_eq(&int("101"), &Value::Float(101.5)));
    assert!(!py_eq(&int("101"), &Value::Str("101".into())));
    assert!(!py_eq(&Value::Float(f64::NAN), &Value::Float(f64::NAN)));
    assert!(py_eq(&int("9007199254740993"), &int("9007199254740993")));
    // 2**53 + 1 is not a float; the nearest float is 2**53.
    assert!(!py_eq(
        &int("9007199254740993"),
        &Value::Float(9007199254740992.0)
    ));
    assert!(py_eq(
        &int("9007199254740992"),
        &Value::Float(9007199254740992.0)
    ));
    assert!(py_eq(&Value::Float(1e22), &int("10000000000000000000000")));
    let a = loads(r#"{"x": [1, 2.0], "y": "z"}"#).unwrap();
    let b = loads(r#"{"y": "z", "x": [1.0, 2]}"#).unwrap();
    assert!(py_eq(&a, &b));
    assert!(!py_eq(&a, &loads(r#"{"y": "z"}"#).unwrap()));
}

#[test]
fn truthiness_and_types() {
    assert!(!Value::Int("-0".into()).truthy());
    assert!(Value::Int("3".into()).truthy());
    assert!(!Value::Obj(vec![]).truthy());
    assert!(!Value::Str(String::new()).truthy());
    assert!(Value::Obj(vec![]).is_obj());
    assert!(!Value::Arr(vec![]).is_obj());
    assert_eq!(Value::Null.type_name(), "NoneType");
    assert_eq!(Value::Bool(true).type_name(), "bool");
    assert_eq!(Value::Int("1".into()).type_name(), "int");
    assert_eq!(Value::Float(1.0).type_name(), "float");
    assert_eq!(Value::Str("a".into()).type_name(), "str");
    assert_eq!(Value::Arr(vec![]).type_name(), "list");
    assert_eq!(Value::Obj(vec![]).type_name(), "dict");
    assert_eq!(
        loads("").unwrap_err().to_string(),
        "Expecting value (char 0)"
    );
}
