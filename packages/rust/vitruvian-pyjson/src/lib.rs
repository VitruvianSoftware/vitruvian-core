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

//! JSON as the bash tools' `python3 -c 'json.load(...)'` snippets see it.
//!
//! The shell scripts read manifests with Python and print fields with
//! `print()`, so what reaches the terminal is Python's `str()` of a JSON
//! value: `True`/`None`, `1e+20`, `['a', 1]`, keys in file order. This module
//! parses with serde_json (through a custom `Deserialize`, so key order and
//! Python's duplicate-key rule survive: the LAST value wins, at the FIRST
//! key's position) and renders values the way CPython 3 does.
//!
//! Known gaps, all inputs no real manifest contains: `NaN`/`Infinity`
//! literals, lone surrogate escapes and numbers beyond f64 range are rejected
//! (Python accepts them); integers beyond 64 bits lose precision; `-0` reads
//! as a float; and nesting deeper than serde_json's 128 levels is rejected.

use serde::de::{Deserialize, Deserializer, MapAccess, SeqAccess, Visitor};
use std::collections::HashMap;
use std::fmt;

/// A JSON value with Python's semantics.
#[derive(Clone, Debug, PartialEq)]
pub enum Py {
    None,
    Bool(bool),
    Int(i128),
    Float(f64),
    Str(String),
    List(Vec<Py>),
    /// Insertion-ordered, keys unique.
    Dict(Vec<(String, Py)>),
}

/// Alias for callers that name the JSON value type `Value`.
pub type Value = Py;

impl Py {
    /// Python's name for the type, as its error messages use it.
    pub fn type_name(&self) -> &'static str {
        match self {
            Py::None => "NoneType",
            Py::Bool(_) => "bool",
            Py::Int(_) => "int",
            Py::Float(_) => "float",
            Py::Str(_) => "str",
            Py::List(_) => "list",
            Py::Dict(_) => "dict",
        }
    }

    /// `d.get(key)` on a dict; `None` for a missing key or a non-dict.
    pub fn get(&self, key: &str) -> Option<&Py> {
        match self {
            Py::Dict(items) => items.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    pub fn is_dict(&self) -> bool {
        matches!(self, Py::Dict(_))
    }

    /// Python truthiness: `bool(value)`.
    pub fn truthy(&self) -> bool {
        match self {
            Py::None => false,
            Py::Bool(b) => *b,
            Py::Int(i) => *i != 0,
            Py::Float(f) => *f != 0.0,
            Py::Str(s) => !s.is_empty(),
            Py::List(v) => !v.is_empty(),
            Py::Dict(v) => !v.is_empty(),
        }
    }

    /// Python `str(value)`.
    pub fn py_str(&self) -> String {
        match self {
            Py::Str(s) => s.clone(),
            other => other.py_repr(),
        }
    }

    /// Python `repr(value)`.
    pub fn py_repr(&self) -> String {
        match self {
            Py::None => "None".to_string(),
            Py::Bool(true) => "True".to_string(),
            Py::Bool(false) => "False".to_string(),
            Py::Int(i) => i.to_string(),
            Py::Float(f) => float_repr(*f),
            Py::Str(s) => str_repr(s),
            Py::List(v) => {
                let parts: Vec<String> = v.iter().map(Py::py_repr).collect();
                format!("[{}]", parts.join(", "))
            }
            Py::Dict(items) => {
                let parts: Vec<String> = items
                    .iter()
                    .map(|(k, v)| format!("{}: {}", str_repr(k), v.py_repr()))
                    .collect();
                format!("{{{}}}", parts.join(", "))
            }
        }
    }
}

/// `json.loads(text)`.
pub fn loads(text: &str) -> Result<Py, String> {
    serde_json::from_str::<Py>(text).map_err(|e| e.to_string())
}

/// `json.load(open(path))`: read, decode as UTF-8, parse.
pub fn load_file(path: &std::path::Path) -> Result<Py, String> {
    let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
    let text = String::from_utf8(bytes).map_err(|e| e.to_string())?;
    loads(&text)
}

/// The traceback `python3 -c` prints when `open(path)` on line `line` of the
/// snippet fails, e.g. `FileNotFoundError: [Errno 2] No such file or
/// directory: 'x'`.
pub fn open_error_traceback(e: &std::io::Error, path: &str, line: u32) -> String {
    let errno = e.raw_os_error().unwrap_or(0);
    let class = match errno {
        1 | 13 => "PermissionError",
        2 => "FileNotFoundError",
        20 => "NotADirectoryError",
        21 => "IsADirectoryError",
        _ => "OSError",
    };
    let msg = e.to_string();
    let msg = match msg.find(" (os error") {
        Some(i) => msg[..i].to_string(),
        None => msg,
    };
    format!(
        "Traceback (most recent call last):\n  File \"<string>\", line {}, in <module>\n{}: [Errno {}] {}: {}\n",
        line,
        class,
        errno,
        msg,
        str_repr(path)
    )
}

/// CPython's `repr(float)`: the shortest round-tripping digits, positional
/// for decimal exponents in [-4, 16), scientific (`1e+16`, `1.5e-05`) outside.
pub fn float_repr(f: f64) -> String {
    vitruvian_pycompat::pystr::repr_float(f)
}

/// CPython's `repr(str)`.
pub fn str_repr(s: &str) -> String {
    vitruvian_pycompat::pystr::repr_str(s)
}

impl<'de> Deserialize<'de> for Py {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        d.deserialize_any(PyVisitor)
    }
}

struct PyVisitor;

impl<'de> Visitor<'de> for PyVisitor {
    type Value = Py;

    fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str("a JSON value")
    }
    fn visit_unit<E>(self) -> Result<Py, E> {
        Ok(Py::None)
    }
    fn visit_bool<E>(self, b: bool) -> Result<Py, E> {
        Ok(Py::Bool(b))
    }
    fn visit_i64<E>(self, i: i64) -> Result<Py, E> {
        Ok(Py::Int(i as i128))
    }
    fn visit_u64<E>(self, u: u64) -> Result<Py, E> {
        Ok(Py::Int(u as i128))
    }
    fn visit_f64<E>(self, f: f64) -> Result<Py, E> {
        Ok(Py::Float(f))
    }
    fn visit_str<E>(self, s: &str) -> Result<Py, E> {
        Ok(Py::Str(s.to_string()))
    }
    fn visit_string<E>(self, s: String) -> Result<Py, E> {
        Ok(Py::Str(s))
    }
    fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<Py, A::Error> {
        let mut v = Vec::new();
        while let Some(item) = seq.next_element::<Py>()? {
            v.push(item);
        }
        Ok(Py::List(v))
    }
    fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Py, A::Error> {
        let mut items: Vec<(String, Py)> = Vec::new();
        let mut seen: HashMap<String, usize> = HashMap::new();
        while let Some((k, v)) = map.next_entry::<String, Py>()? {
            // Python's dict: a repeated key keeps its first position and
            // takes the last value.
            match seen.get(&k) {
                Some(&at) => items[at].1 = v,
                None => {
                    seen.insert(k.clone(), items.len());
                    items.push((k, v));
                }
            }
        }
        Ok(Py::Dict(items))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn floats_print_like_python() {
        let cases = [
            (1.0, "1.0"),
            (0.1, "0.1"),
            (1e16, "1e+16"),
            (1e15, "1000000000000000.0"),
            (1.5e-7, "1.5e-07"),
            (0.0001, "0.0001"),
            (0.00001, "1e-05"),
            (-2.5, "-2.5"),
            (123.456, "123.456"),
            (1.2345e20, "1.2345e+20"),
            (1e100, "1e+100"),
        ];
        for (f, want) in cases {
            assert_eq!(float_repr(f), want, "{f}");
        }
    }

    #[test]
    fn str_repr_matches_python() {
        assert_eq!(str_repr("a"), "'a'");
        assert_eq!(str_repr("it's"), "\"it's\"");
        assert_eq!(str_repr("a'b\"c"), "'a\\'b\"c'");
        assert_eq!(str_repr("x\ny\t\u{1}"), "'x\\ny\\t\\x01'");
        assert_eq!(str_repr("é"), "'é'");
    }

    #[test]
    fn values_print_like_python() {
        let v = loads(r#"{"b":[1,"x",null,true],"a":{"k":1.0},"b":false}"#).unwrap();
        // duplicate "b": first position, last value
        assert_eq!(v.py_str(), "{'b': False, 'a': {'k': 1.0}}");
        assert_eq!(loads("1e2").unwrap().py_str(), "100.0");
        assert_eq!(loads("12").unwrap().py_str(), "12");
        assert!(loads("{} x").is_err());
        assert!(loads("NaN").is_err());
    }

    #[test]
    fn truthiness() {
        for (j, want) in [
            ("0", false),
            ("1", true),
            ("0.0", false),
            ("\"\"", false),
            ("\"false\"", true),
            ("[]", false),
            ("{}", false),
            ("null", false),
            ("[0]", true),
        ] {
            assert_eq!(loads(j).unwrap().truthy(), want, "{j}");
        }
    }

    #[test]
    fn unicode15_floats_and_value_alias() {
        assert_eq!(float_repr(-0.0), "-0.0");
        assert_eq!(float_repr(0.0), "0.0");
        assert_eq!(float_repr(1.5e300), "1.5e+300");
        assert_eq!(str_repr("é✓\u{a0}\u{200b}"), "'é✓\\xa0\\u200b'");
        assert_eq!(str_repr("\u{e0001}"), "'\\U000e0001'");
        assert_eq!(str_repr("\u{0378}"), "'\\u0378'");

        let v: Value =
            loads(r#"{"n":null,"b":false,"i":1,"f":1.5,"s":"x","l":[],"d":{}}"#).unwrap();
        assert_eq!(v.type_name(), "dict");
        assert_eq!(v.get("n").unwrap().type_name(), "NoneType");
        assert_eq!(v.get("b").unwrap().type_name(), "bool");
        assert_eq!(v.get("i").unwrap().type_name(), "int");
        assert_eq!(v.get("f").unwrap().type_name(), "float");
        assert_eq!(v.get("s").unwrap().type_name(), "str");
        assert_eq!(v.get("l").unwrap().type_name(), "list");
        assert_eq!(Value::Int(7).type_name(), "int");
    }
}
