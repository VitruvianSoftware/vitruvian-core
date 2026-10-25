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

//! The jq filters the scripts ran, over serde_json: JSON is parsed with
//! serde_json into a value that keeps object keys in input order (as jq
//! does), and written back the way `jq` (pretty, 2-space indent) and `jq -r`
//! (strings raw) print it.

use std::fmt;

use serde::de::{Deserialize, Deserializer, MapAccess, SeqAccess, Visitor};

/// A JSON value with its object keys in the order they came.
#[derive(Debug, Clone, PartialEq)]
pub enum J {
    Null,
    Bool(bool),
    Num(serde_json::Number),
    Str(String),
    Arr(Vec<J>),
    Obj(Vec<(String, J)>),
}

impl<'de> Deserialize<'de> for J {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<J, D::Error> {
        struct V;
        impl<'de> Visitor<'de> for V {
            type Value = J;
            fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
                f.write_str("any JSON value")
            }
            fn visit_bool<E>(self, b: bool) -> Result<J, E> {
                Ok(J::Bool(b))
            }
            fn visit_i64<E>(self, n: i64) -> Result<J, E> {
                Ok(J::Num(n.into()))
            }
            fn visit_u64<E>(self, n: u64) -> Result<J, E> {
                Ok(J::Num(n.into()))
            }
            fn visit_f64<E>(self, n: f64) -> Result<J, E> {
                Ok(serde_json::Number::from_f64(n).map_or(J::Null, J::Num))
            }
            fn visit_str<E>(self, s: &str) -> Result<J, E> {
                Ok(J::Str(s.to_string()))
            }
            fn visit_string<E>(self, s: String) -> Result<J, E> {
                Ok(J::Str(s))
            }
            fn visit_unit<E>(self) -> Result<J, E> {
                Ok(J::Null)
            }
            fn visit_none<E>(self) -> Result<J, E> {
                Ok(J::Null)
            }
            fn visit_seq<A: SeqAccess<'de>>(self, mut a: A) -> Result<J, A::Error> {
                let mut v = Vec::new();
                while let Some(x) = a.next_element()? {
                    v.push(x);
                }
                Ok(J::Arr(v))
            }
            fn visit_map<A: MapAccess<'de>>(self, mut a: A) -> Result<J, A::Error> {
                let mut v: Vec<(String, J)> = Vec::new();
                while let Some((k, x)) = a.next_entry::<String, J>()? {
                    // jq keeps a repeated key where it first appeared, with
                    // the last value.
                    match v.iter_mut().find(|(k2, _)| *k2 == k) {
                        Some(slot) => slot.1 = x,
                        None => v.push((k, x)),
                    }
                }
                Ok(J::Obj(v))
            }
        }
        d.deserialize_any(V)
    }
}

impl J {
    /// `.key` on an object (null when absent); None where jq would error
    /// (indexing a string, a number, ...).
    pub fn get(&self, key: &str) -> Option<J> {
        match self {
            J::Obj(m) => Some(
                m.iter()
                    .find(|(k, _)| k == key)
                    .map_or(J::Null, |(_, v)| v.clone()),
            ),
            J::Null => Some(J::Null),
            _ => None,
        }
    }

    /// `.[i]` on an array (null when out of range); None where jq errors.
    pub fn idx(&self, i: usize) -> Option<J> {
        match self {
            J::Arr(a) => Some(a.get(i).cloned().unwrap_or(J::Null)),
            J::Null => Some(J::Null),
            _ => None,
        }
    }

    /// `.[]?`: the elements of an array or values of an object; nothing for
    /// anything else.
    pub fn iter_opt(&self) -> Vec<J> {
        match self {
            J::Arr(a) => a.clone(),
            J::Obj(m) => m.iter().map(|(_, v)| v.clone()).collect(),
            _ => Vec::new(),
        }
    }

    /// jq's truthiness: everything but null and false.
    pub fn truthy(&self) -> bool {
        !matches!(self, J::Null | J::Bool(false))
    }

    /// Remove `key` from an object (del(.key)).
    pub fn del(&mut self, key: &str) {
        if let J::Obj(m) = self {
            m.retain(|(k, _)| k != key);
        }
    }

    pub fn get_mut(&mut self, key: &str) -> Option<&mut J> {
        match self {
            J::Obj(m) => m.iter_mut().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }
}

/// Every JSON value in `input` (jq reads a stream); Err on a parse error,
/// with the values read before it.
pub fn parse_stream(input: &[u8]) -> Result<Vec<J>, Vec<J>> {
    let mut out = Vec::new();
    for v in serde_json::Deserializer::from_slice(input).into_iter::<J>() {
        match v {
            Ok(v) => out.push(v),
            Err(_) => return Err(out),
        }
    }
    Ok(out)
}

fn quote(s: &str) -> String {
    let mut o = String::with_capacity(s.len() + 2);
    o.push('"');
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\n' => o.push_str("\\n"),
            '\t' => o.push_str("\\t"),
            '\r' => o.push_str("\\r"),
            '\u{8}' => o.push_str("\\b"),
            '\u{c}' => o.push_str("\\f"),
            c if (c as u32) < 0x20 || c as u32 == 0x7f => {
                o.push_str(&format!("\\u{:04x}", c as u32))
            }
            c => o.push(c),
        }
    }
    o.push('"');
    o
}

fn write_pretty(v: &J, indent: usize, o: &mut String) {
    match v {
        J::Null => o.push_str("null"),
        J::Bool(b) => o.push_str(if *b { "true" } else { "false" }),
        J::Num(n) => o.push_str(&n.to_string()),
        J::Str(s) => o.push_str(&quote(s)),
        J::Arr(a) if a.is_empty() => o.push_str("[]"),
        J::Obj(m) if m.is_empty() => o.push_str("{}"),
        J::Arr(a) => {
            o.push_str("[\n");
            for (i, x) in a.iter().enumerate() {
                o.push_str(&"  ".repeat(indent + 1));
                write_pretty(x, indent + 1, o);
                if i + 1 < a.len() {
                    o.push(',');
                }
                o.push('\n');
            }
            o.push_str(&"  ".repeat(indent));
            o.push(']');
        }
        J::Obj(m) => {
            o.push_str("{\n");
            for (i, (k, x)) in m.iter().enumerate() {
                o.push_str(&"  ".repeat(indent + 1));
                o.push_str(&quote(k));
                o.push_str(": ");
                write_pretty(x, indent + 1, o);
                if i + 1 < m.len() {
                    o.push(',');
                }
                o.push('\n');
            }
            o.push_str(&"  ".repeat(indent));
            o.push('}');
        }
    }
}

/// How `jq` prints a value (pretty, two-space indent), newline included.
pub fn pretty(v: &J) -> String {
    let mut o = String::new();
    write_pretty(v, 0, &mut o);
    o.push('\n');
    o
}

/// How `jq -r` prints a value: a string raw, anything else as `jq` would.
pub fn raw(v: &J) -> String {
    match v {
        J::Str(s) => format!("{}\n", s),
        _ => pretty(v),
    }
}

/// `jq -r 'FILTER'` over a stream, where FILTER maps each input to zero or
/// one output (None: jq's runtime error, which ends the run). The printed
/// text and whether jq succeeded.
pub fn run_r(input: &[u8], f: impl Fn(&J) -> Option<Option<J>>) -> (Vec<u8>, bool) {
    let (vals, parsed) = match parse_stream(input) {
        Ok(v) => (v, true),
        Err(v) => (v, false),
    };
    let mut out = String::new();
    for v in &vals {
        match f(v) {
            Some(Some(x)) => out.push_str(&raw(&x)),
            Some(None) => {}
            None => return (out.into_bytes(), false),
        }
    }
    (out.into_bytes(), parsed)
}

/// `jq -r '.KEY'`.
pub fn field_r(input: &[u8], key: &str) -> (Vec<u8>, bool) {
    run_r(input, |v| v.get(key).map(Some))
}

/// `jq -r '.KEY // empty'`.
pub fn field_or_empty_r(input: &[u8], key: &str) -> (Vec<u8>, bool) {
    run_r(input, |v| match v.get(key) {
        Some(x) if x.truthy() => Some(Some(x)),
        Some(_) => Some(None),
        // `a // b` swallows an error in `a`.
        None => Some(None),
    })
}

/// `jq -r --arg f FILE '.attachments[]? | select(.fileName == $f) | .id'`:
/// the matching ids, one per line.
pub fn attachment_ids(input: &[u8], file: &str) -> (Vec<u8>, bool) {
    let (vals, mut ok) = match parse_stream(input) {
        Ok(v) => (v, true),
        Err(v) => (v, false),
    };
    let mut out = String::new();
    'outer: for v in &vals {
        let atts = match v.get("attachments") {
            Some(a) => a.iter_opt(),
            None => Vec::new(),
        };
        for a in atts {
            match a.get("fileName") {
                Some(J::Str(ref s)) if s == file => match a.get("id") {
                    Some(id) => out.push_str(&raw(&id)),
                    None => {
                        ok = false;
                        break 'outer;
                    }
                },
                Some(_) => {}
                None => {
                    ok = false;
                    break 'outer;
                }
            }
        }
    }
    (out.into_bytes(), ok)
}

/// `jq -e --arg f FILE 'any(.attachments[]?; .fileName == $f)'`: true when
/// the last output is true.
pub fn has_attachment(input: &[u8], file: &str) -> bool {
    let vals = match parse_stream(input) {
        Ok(v) => v,
        Err(_) => return false,
    };
    let mut last = None;
    for v in &vals {
        let atts = match v.get("attachments") {
            Some(a) => a.iter_opt(),
            None => Vec::new(),
        };
        let mut any = false;
        for a in atts {
            match a.get("fileName") {
                Some(J::Str(ref s)) if s == file => {
                    any = true;
                    break;
                }
                Some(_) => {}
                None => return false,
            }
        }
        last = Some(any);
    }
    last == Some(true)
}

/// `jq '[.items[]? | select(.kind == "Secret")] | length'` per input value;
/// None when jq would fail (bad JSON, an item that is not an object).
pub fn count_secrets(input: &[u8]) -> Option<Vec<usize>> {
    let vals = parse_stream(input).ok()?;
    let mut out = Vec::new();
    for v in &vals {
        let items = v.get("items")?.iter_opt();
        let mut n = 0;
        for it in items {
            if it.get("kind")? == J::Str("Secret".into()) {
                n += 1;
            }
        }
        out.push(n);
    }
    Some(out)
}

/// `jq -r '.data.result[0].value[1] // "0"'` (Prometheus' instant query).
pub fn prom_value(input: &[u8]) -> (Vec<u8>, bool) {
    run_r(input, |v| {
        let x = v
            .get("data")
            .and_then(|d| d.get("result"))
            .and_then(|r| r.idx(0))
            .and_then(|r| r.get("value"))
            .and_then(|r| r.idx(1));
        Some(Some(match x {
            Some(x) if x.truthy() => x,
            _ => J::Str("0".into()),
        }))
    })
}

/// `jq -r '.traces[0].traceID // empty'` (Tempo's search).
pub fn first_trace_id(input: &[u8]) -> Vec<u8> {
    run_r(input, |v| {
        let x = v
            .get("traces")
            .and_then(|d| d.idx(0))
            .and_then(|r| r.get("traceID"));
        Some(match x {
            Some(x) if x.truthy() => Some(x),
            _ => None,
        })
    })
    .0
}

/// `jq -sRr @uri`: percent-encode everything but the unreserved characters.
pub fn uri(s: &[u8]) -> String {
    let mut o = String::new();
    for &c in s {
        if c.is_ascii_alphanumeric() || matches!(c, b'-' | b'_' | b'.' | b'~') {
            o.push(c as char);
        } else {
            o.push_str(&format!("%{:02X}", c));
        }
    }
    o
}

/// A JSON string literal as jq writes one (`--arg` values going into
/// `jq -n` output).
pub fn string_literal(s: &str) -> String {
    quote(s)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_key_order_and_prints_like_jq() {
        let v = &parse_stream(br#"{"b":1,"a":{"z":[1,"x"],"y":{}},"c":[]}"#).unwrap()[0];
        assert_eq!(
            pretty(v),
            "{\n  \"b\": 1,\n  \"a\": {\n    \"z\": [\n      1,\n      \"x\"\n    ],\n    \"y\": {}\n  },\n  \"c\": []\n}\n"
        );
    }

    #[test]
    fn raw_fields() {
        assert_eq!(
            field_r(br#"{"status":"locked"}"#, "status"),
            (b"locked\n".to_vec(), true)
        );
        assert_eq!(field_r(br#"{}"#, "status"), (b"null\n".to_vec(), true));
        assert_eq!(field_r(b"", "status"), (b"".to_vec(), true));
        assert!(!field_r(b"nope", "status").1);
        assert!(!field_r(br#""s""#, "status").1);
        assert_eq!(
            field_or_empty_r(br#"{"id":null}"#, "id"),
            (b"".to_vec(), true)
        );
        assert_eq!(
            field_or_empty_r(br#"{"id":"abc"}"#, "id"),
            (b"abc\n".to_vec(), true)
        );
    }

    #[test]
    fn attachments() {
        let item = br#"{"attachments":[{"fileName":"a","id":"1"},{"fileName":"k.json","id":"2"},{"fileName":"k.json","id":"3"}]}"#;
        assert_eq!(attachment_ids(item, "k.json"), (b"2\n3\n".to_vec(), true));
        assert!(has_attachment(item, "k.json"));
        assert!(!has_attachment(item, "zzz"));
        assert!(!has_attachment(br#"{}"#, "k.json"));
    }

    #[test]
    fn secret_count() {
        assert_eq!(
            count_secrets(
                br#"{"items":[{"kind":"Secret"},{"kind":"ConfigMap"},{"kind":"Secret"}]}"#
            ),
            Some(vec![2])
        );
        assert_eq!(count_secrets(br#"{}"#), Some(vec![0]));
        assert_eq!(count_secrets(b""), Some(vec![]));
        assert_eq!(count_secrets(br#"{"items":["x"]}"#), None);
        assert_eq!(count_secrets(b"{"), None);
    }

    #[test]
    fn prometheus_and_tempo() {
        assert_eq!(
            prom_value(br#"{"data":{"result":[{"value":[0,"1"]}]}}"#).0,
            b"1\n"
        );
        assert_eq!(prom_value(br#"{"data":{"result":[]}}"#).0, b"0\n");
        assert_eq!(
            first_trace_id(br#"{"traces":[{"traceID":"abc"}]}"#),
            b"abc\n"
        );
        assert_eq!(first_trace_id(br#"{"traces":[]}"#), b"");
    }

    #[test]
    fn uri_encodes_like_jq() {
        assert_eq!(uri(b"a b{\"=\"}~._-"), "a%20b%7B%22%3D%22%7D~._-");
    }
}
