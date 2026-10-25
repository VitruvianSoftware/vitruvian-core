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

//! The slice of jq 1.8 the preview scripts lean on, over serde_json: parse a
//! stream of JSON texts (`echo "$json" | jq ...`), run one of the scripts'
//! filters on each, and print the results the way `jq` / `jq -r` does --
//! pretty, two-space indent, object keys in input order, jq's string escapes
//! -- with jq's error messages and its exit status 5.
//!
//! Objects keep their input order (jq does; a serde_json `Map` without
//! `preserve_order` would sort them), so values are read into [`J`] through
//! serde's `Deserialize` rather than into `serde_json::Value`.

use serde::de::{self, Deserialize, Deserializer, MapAccess, SeqAccess, Visitor};
use std::fmt;

/// A JSON value as jq holds it.
#[derive(Clone, Debug, PartialEq)]
pub enum J {
    Null,
    Bool(bool),
    Int(i64),
    UInt(u64),
    Float(f64),
    Str(String),
    Arr(Vec<J>),
    Obj(Vec<(String, J)>),
}

impl J {
    pub fn str(s: &str) -> J {
        J::Str(s.to_string())
    }

    fn type_name(&self) -> &'static str {
        match self {
            J::Null => "null",
            J::Bool(_) => "boolean",
            J::Int(_) | J::UInt(_) | J::Float(_) => "number",
            J::Str(_) => "string",
            J::Arr(_) => "array",
            J::Obj(_) => "object",
        }
    }

    /// jq truthiness: everything but null and false.
    pub fn truthy(&self) -> bool {
        !matches!(self, J::Null | J::Bool(false))
    }

    /// `.key`: a member of an object, null on null, an error on anything else.
    pub fn index(&self, key: &str) -> Result<J, String> {
        match self {
            J::Null => Ok(J::Null),
            J::Obj(m) => Ok(m
                .iter()
                .find(|(k, _)| k == key)
                .map(|(_, v)| v.clone())
                .unwrap_or(J::Null)),
            other => Err(format!(
                "Cannot index {} with string ({})",
                other.type_name(),
                trunc(&compact(&J::str(key)))
            )),
        }
    }

    /// `.[]`: an array's elements or an object's values, in order.
    pub fn iterate(&self) -> Result<Vec<J>, String> {
        match self {
            J::Arr(a) => Ok(a.clone()),
            J::Obj(m) => Ok(m.iter().map(|(_, v)| v.clone()).collect()),
            other => Err(format!(
                "Cannot iterate over {} ({})",
                other.type_name(),
                trunc(&compact(other))
            )),
        }
    }

    /// `== "s"` against a string.
    pub fn is_str(&self, s: &[u8]) -> bool {
        matches!(self, J::Str(v) if v.as_bytes() == s)
    }
}

// ---------------------------------------------------------------------------
// reading
// ---------------------------------------------------------------------------

impl<'de> Deserialize<'de> for J {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<J, D::Error> {
        d.deserialize_any(JVisitor)
    }
}

struct JVisitor;

impl<'de> Visitor<'de> for JVisitor {
    type Value = J;

    fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str("a JSON value")
    }
    fn visit_unit<E: de::Error>(self) -> Result<J, E> {
        Ok(J::Null)
    }
    fn visit_none<E: de::Error>(self) -> Result<J, E> {
        Ok(J::Null)
    }
    fn visit_bool<E: de::Error>(self, v: bool) -> Result<J, E> {
        Ok(J::Bool(v))
    }
    fn visit_i64<E: de::Error>(self, v: i64) -> Result<J, E> {
        Ok(J::Int(v))
    }
    fn visit_u64<E: de::Error>(self, v: u64) -> Result<J, E> {
        Ok(J::UInt(v))
    }
    fn visit_f64<E: de::Error>(self, v: f64) -> Result<J, E> {
        Ok(J::Float(v))
    }
    fn visit_str<E: de::Error>(self, v: &str) -> Result<J, E> {
        Ok(J::str(v))
    }
    fn visit_string<E: de::Error>(self, v: String) -> Result<J, E> {
        Ok(J::Str(v))
    }
    fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<J, A::Error> {
        let mut v = Vec::new();
        while let Some(e) = seq.next_element::<J>()? {
            v.push(e);
        }
        Ok(J::Arr(v))
    }
    fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<J, A::Error> {
        // A repeated key keeps its first position and takes the last value.
        let mut m: Vec<(String, J)> = Vec::new();
        while let Some((k, v)) = map.next_entry::<String, J>()? {
            match m.iter_mut().find(|(ek, _)| *ek == k) {
                Some(slot) => slot.1 = v,
                None => m.push((k, v)),
            }
        }
        Ok(J::Obj(m))
    }
}

// ---------------------------------------------------------------------------
// writing
// ---------------------------------------------------------------------------

fn escape_into(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            c if (c as u32) < 0x20 || c as u32 == 0x7f => {
                out.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

fn number(out: &mut String, v: &J) {
    match v {
        J::Int(i) => out.push_str(&i.to_string()),
        J::UInt(u) => out.push_str(&u.to_string()),
        J::Float(f) => {
            if f.is_finite() {
                out.push_str(&f.to_string());
            } else if f.is_nan() {
                out.push_str("null");
            } else if *f > 0.0 {
                out.push_str("1.7976931348623157e+308");
            } else {
                out.push_str("-1.7976931348623157e+308");
            }
        }
        _ => unreachable!(),
    }
}

fn dump(out: &mut String, v: &J, indent: Option<usize>) {
    match v {
        J::Null => out.push_str("null"),
        J::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        J::Int(_) | J::UInt(_) | J::Float(_) => number(out, v),
        J::Str(s) => escape_into(out, s),
        J::Arr(a) => {
            if a.is_empty() {
                out.push_str("[]");
                return;
            }
            out.push('[');
            for (i, e) in a.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                if let Some(n) = indent {
                    out.push('\n');
                    out.push_str(&" ".repeat(n + 2));
                    dump(out, e, Some(n + 2));
                } else {
                    dump(out, e, None);
                }
            }
            if let Some(n) = indent {
                out.push('\n');
                out.push_str(&" ".repeat(n));
            }
            out.push(']');
        }
        J::Obj(m) => {
            if m.is_empty() {
                out.push_str("{}");
                return;
            }
            out.push('{');
            for (i, (k, e)) in m.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                match indent {
                    Some(n) => {
                        out.push('\n');
                        out.push_str(&" ".repeat(n + 2));
                        escape_into(out, k);
                        out.push_str(": ");
                        dump(out, e, Some(n + 2));
                    }
                    None => {
                        escape_into(out, k);
                        out.push(':');
                        dump(out, e, None);
                    }
                }
            }
            if let Some(n) = indent {
                out.push('\n');
                out.push_str(&" ".repeat(n));
            }
            out.push('}');
        }
    }
}

/// `jq .` output for one value: pretty, two-space indent, no newline.
pub fn pretty(v: &J) -> String {
    let mut s = String::new();
    dump(&mut s, v, Some(0));
    s
}

/// `jq -c .` output for one value.
pub fn compact(v: &J) -> String {
    let mut s = String::new();
    dump(&mut s, v, None);
    s
}

/// How jq quotes a value in an error message: its compact dump, cut to 25
/// bytes (back to a character boundary) plus `...` when longer than 29.
pub fn trunc(s: &str) -> String {
    if s.len() <= 29 {
        return s.to_string();
    }
    let mut cut = 25;
    while !s.is_char_boundary(cut) {
        cut -= 1;
    }
    format!("{}...", &s[..cut])
}

/// One `jq` / `jq -r` result line.
fn emit(out: &mut Vec<u8>, v: &J, raw: bool) {
    match v {
        J::Str(s) if raw => out.extend_from_slice(s.as_bytes()),
        _ => out.extend_from_slice(pretty(v).as_bytes()),
    }
    out.push(b'\n');
}

/// What a jq run left: stdout, stderr and its exit status.
#[derive(Debug, Default, PartialEq)]
pub struct Run {
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub status: i32,
}

/// What one filter produced on one input: its outputs, in order, and the
/// error that stopped it, if one did.
pub type Produced = (Vec<J>, Option<String>);

/// `printf '%s' "$input" | jq [-r] <filter>`. Each JSON text in the input
/// is run through `filter`; an error ends that input (its earlier outputs
/// stand) and the run goes on to the next, exiting 5 at the end, as jq does.
/// Bytes that are not UTF-8 read as U+FFFD, as in jq.
pub fn run(input: &[u8], raw: bool, filter: &dyn Fn(&J) -> Produced) -> Run {
    let text = String::from_utf8_lossy(input).into_owned();
    let bytes = text.as_bytes();
    let mut r = Run::default();
    let mut stream = serde_json::Deserializer::from_str(&text).into_iter::<J>();
    loop {
        match stream.next() {
            None => break,
            Some(Ok(v)) => {
                let (outs, e) = filter(&v);
                for o in &outs {
                    emit(&mut r.stdout, o, raw);
                }
                if let Some(msg) = e {
                    // jq's location: the newlines read by the time the value
                    // was complete -- the whitespace after it up to and
                    // including the first newline.
                    let mut i = stream.byte_offset();
                    while i < bytes.len() && matches!(bytes[i], b' ' | b'\t' | b'\r' | b'\n') {
                        i += 1;
                        if bytes[i - 1] == b'\n' {
                            break;
                        }
                    }
                    let line = bytes[..i].iter().filter(|&&c| c == b'\n').count();
                    r.stderr.extend_from_slice(
                        format!("jq: error (at <stdin>:{}): {}\n", line, msg).as_bytes(),
                    );
                    r.status = 5;
                }
            }
            Some(Err(e)) => {
                r.stderr
                    .extend_from_slice(format!("jq: parse error: {}\n", e).as_bytes());
                r.status = 5;
                break;
            }
        }
    }
    r
}

/// Run `f` on each of `items`, collecting outputs until the first error.
pub fn each(items: Result<Vec<J>, String>, f: &dyn Fn(&J) -> Produced) -> Produced {
    let items = match items {
        Ok(v) => v,
        Err(e) => return (Vec::new(), Some(e)),
    };
    let mut outs = Vec::new();
    for it in &items {
        let (o, e) = f(it);
        outs.extend(o);
        if e.is_some() {
            return (outs, e);
        }
    }
    (outs, None)
}

/// A single-output step (`.a.b`) as a filter result.
pub fn one(r: Result<J, String>) -> Produced {
    match r {
        Ok(v) => (vec![v], None),
        Err(e) => (Vec::new(), Some(e)),
    }
}

/// `jq -n --arg ...`: a string argument as jq reads it (not UTF-8 -> U+FFFD).
pub fn arg(b: &[u8]) -> J {
    J::Str(String::from_utf8_lossy(b).into_owned())
}

/// `head -n 1` of some output: the first line, newline included.
pub fn head1(b: &[u8]) -> Vec<u8> {
    match b.iter().position(|&c| c == b'\n') {
        Some(i) => b[..=i].to_vec(),
        None => b.to_vec(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn branches_ids(p: &'static [u8]) -> impl Fn(&J) -> Produced {
        move |v: &J| {
            each(
                v.index("branches").and_then(|b| b.iterate()),
                &|b: &J| -> Produced {
                    let id = match b.index("id") {
                        Ok(x) => x,
                        Err(e) => return (vec![], Some(e)),
                    };
                    let hit = id.is_str(p)
                        || match b.index("name") {
                            Ok(n) => n.is_str(p),
                            Err(e) => return (vec![], Some(e)),
                        };
                    if hit {
                        one(b.index("id"))
                    } else {
                        (vec![], None)
                    }
                },
            )
        }
    }

    #[test]
    fn pretty_keeps_input_order_and_jq_escapes() {
        let r = run(
            b"{\"b\":{\"z\":1,\"a\":[]},\"a\":\"x\\u007f\\u0001\\\"\\\\\xc3\xa9\",\"o\":{}}\n",
            false,
            &|v: &J| (vec![v.clone()], None),
        );
        assert_eq!(
            String::from_utf8(r.stdout).unwrap(),
            "{\n  \"b\": {\n    \"z\": 1,\n    \"a\": []\n  },\n  \"a\": \"x\\u007f\\u0001\\\"\\\\\u{e9}\",\n  \"o\": {}\n}\n"
        );
        assert_eq!(r.status, 0);
    }

    #[test]
    fn duplicate_key_keeps_first_position_last_value() {
        let r = run(b"{\"a\":\"x\",\"b\":1,\"a\":\"y\"}", false, &|v: &J| {
            (vec![v.clone()], None)
        });
        assert_eq!(r.stdout, b"{\n  \"a\": \"y\",\n  \"b\": 1\n}\n");
    }

    #[test]
    fn iterate_null_error_and_location() {
        let f = branches_ids(b"main");
        let r = run(b"{}\n", true, &f);
        assert_eq!(
            r.stderr,
            b"jq: error (at <stdin>:1): Cannot iterate over null (null)\n"
        );
        assert_eq!(r.status, 5);
        let r = run(b"{}", true, &f);
        assert_eq!(
            r.stderr,
            b"jq: error (at <stdin>:0): Cannot iterate over null (null)\n"
        );
        let r = run(b"{}\n\n\n", true, &f);
        assert!(r.stderr.starts_with(b"jq: error (at <stdin>:1)"));
        let r = run(b"\n\n{\n}\n", true, &f);
        assert!(r.stderr.starts_with(b"jq: error (at <stdin>:4)"));
    }

    #[test]
    fn select_by_id_or_name_streams_until_error() {
        let f = branches_ids(b"main");
        let r = run(
            b"{\"branches\":[{\"id\":\"a\",\"name\":\"main\"},{\"id\":\"main\"},\"s\",{\"id\":\"z\",\"name\":\"main\"}]}\n",
            true,
            &f,
        );
        assert_eq!(r.stdout, b"a\nmain\n");
        assert_eq!(
            r.stderr,
            b"jq: error (at <stdin>:1): Cannot index string with string (\"id\")\n"
        );
        assert_eq!(r.status, 5);
    }

    #[test]
    fn error_values_truncate_like_jq() {
        assert_eq!(trunc(&compact(&J::str(&"a".repeat(27)))).len(), 29);
        assert_eq!(
            trunc(&compact(&J::str(&"a".repeat(28)))),
            format!("\"{}...", "a".repeat(24))
        );
        assert_eq!(
            trunc(&compact(&J::str(&format!(
                "{}\u{e9}aaaaaaaaaa",
                "a".repeat(23)
            )))),
            format!("\"{}...", "a".repeat(23))
        );
    }

    #[test]
    fn empty_input_is_no_output() {
        let r = run(b"\n", true, &|v: &J| one(v.index("id")));
        assert_eq!(r, Run::default());
    }

    #[test]
    fn raw_strings_and_nonstrings() {
        let r = run(
            b"{\"id\":null} {\"id\":7} {\"id\":\"x\"}",
            true,
            &|v: &J| one(v.index("id")),
        );
        assert_eq!(r.stdout, b"null\n7\nx\n");
    }

    #[test]
    fn head1_takes_first_line() {
        assert_eq!(head1(b"a\nb\n"), b"a\n");
        assert_eq!(head1(b"a"), b"a");
        assert_eq!(head1(b""), b"");
    }
}
