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

//! The three jq programs sync.sh runs, as jq 1.8 (the repo's pinned
//! @jq_toolchains) runs them, on JSON read through serde:
//!
//!   jq -r .status                                         (bw status)
//!   jq -c --arg n "$ITEM" '[.[] | select(.name==$n)][0] // empty'
//!   jq -r '.login.password // empty'
//!
//! jq reads a STREAM of values and runs the program on each; an error on one
//! value is printed (`jq: error (at <stdin>:N): ...`, N the lines read so
//! far) and the rest still run, and the exit status is then 5. Objects keep
//! their key order (serde_json's own map would sort them), because jq's
//! output does.

use std::fmt;

use serde::de::{self, Deserialize, Deserializer, MapAccess, SeqAccess, Visitor};

#[derive(Clone, Debug, PartialEq)]
pub enum Jv {
    Null,
    Bool(bool),
    Int(i128),
    Float(f64),
    Str(String),
    Arr(Vec<Jv>),
    /// Key order as in the input; a repeated key keeps its first place and
    /// its last value, as jq's objects do.
    Obj(Vec<(String, Jv)>),
}

impl<'de> Deserialize<'de> for Jv {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        struct V;
        impl<'de> Visitor<'de> for V {
            type Value = Jv;
            fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
                f.write_str("any JSON value")
            }
            fn visit_unit<E: de::Error>(self) -> Result<Jv, E> {
                Ok(Jv::Null)
            }
            fn visit_bool<E: de::Error>(self, b: bool) -> Result<Jv, E> {
                Ok(Jv::Bool(b))
            }
            fn visit_i64<E: de::Error>(self, n: i64) -> Result<Jv, E> {
                Ok(Jv::Int(n as i128))
            }
            fn visit_u64<E: de::Error>(self, n: u64) -> Result<Jv, E> {
                Ok(Jv::Int(n as i128))
            }
            fn visit_f64<E: de::Error>(self, n: f64) -> Result<Jv, E> {
                Ok(Jv::Float(n))
            }
            fn visit_str<E: de::Error>(self, s: &str) -> Result<Jv, E> {
                Ok(Jv::Str(s.to_string()))
            }
            fn visit_string<E: de::Error>(self, s: String) -> Result<Jv, E> {
                Ok(Jv::Str(s))
            }
            fn visit_seq<A: SeqAccess<'de>>(self, mut a: A) -> Result<Jv, A::Error> {
                let mut v = Vec::new();
                while let Some(x) = a.next_element::<Jv>()? {
                    v.push(x);
                }
                Ok(Jv::Arr(v))
            }
            fn visit_map<A: MapAccess<'de>>(self, mut a: A) -> Result<Jv, A::Error> {
                let mut items: Vec<(String, Jv)> = Vec::new();
                while let Some((k, v)) = a.next_entry::<String, Jv>()? {
                    if let Some(slot) = items.iter_mut().find(|(ek, _)| *ek == k) {
                        slot.1 = v;
                    } else {
                        items.push((k, v));
                    }
                }
                Ok(Jv::Obj(items))
            }
        }
        d.deserialize_any(V)
    }
}

impl Jv {
    pub fn kind(&self) -> &'static str {
        match self {
            Jv::Null => "null",
            Jv::Bool(_) => "boolean",
            Jv::Int(_) | Jv::Float(_) => "number",
            Jv::Str(_) => "string",
            Jv::Arr(_) => "array",
            Jv::Obj(_) => "object",
        }
    }

    fn truthy(&self) -> bool {
        !matches!(self, Jv::Null | Jv::Bool(false))
    }

    /// `.key`: a value or null for an object, null for null, else an error.
    pub fn index(&self, key: &str) -> Result<Jv, String> {
        match self {
            Jv::Obj(items) => Ok(items
                .iter()
                .find(|(k, _)| k == key)
                .map(|(_, v)| v.clone())
                .unwrap_or(Jv::Null)),
            Jv::Null => Ok(Jv::Null),
            other => Err(format!(
                "Cannot index {} with string ({})",
                other.kind(),
                dump_string(key)
            )),
        }
    }

    /// `.[]`.
    pub fn iterate(&self) -> Result<Vec<Jv>, String> {
        match self {
            Jv::Arr(v) => Ok(v.clone()),
            Jv::Obj(items) => Ok(items.iter().map(|(_, v)| v.clone()).collect()),
            other => Err(format!(
                "Cannot iterate over {} ({})",
                other.kind(),
                dump_trunc(other)
            )),
        }
    }
}

/// A JSON string as jq writes it: `"` and `\` escaped, the C0 controls and
/// DEL as \b \t \n \f \r or \u00xx, everything else as it is.
pub fn dump_string(s: &str) -> String {
    let mut o = String::with_capacity(s.len() + 2);
    o.push('"');
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\u{8}' => o.push_str("\\b"),
            '\t' => o.push_str("\\t"),
            '\n' => o.push_str("\\n"),
            '\u{c}' => o.push_str("\\f"),
            '\r' => o.push_str("\\r"),
            c if (c as u32) < 0x20 || c as u32 == 0x7f => {
                o.push_str(&format!("\\u{:04x}", c as u32))
            }
            c => o.push(c),
        }
    }
    o.push('"');
    o
}

fn num(v: &Jv) -> String {
    match v {
        Jv::Int(n) => n.to_string(),
        Jv::Float(f) => {
            if f.is_finite() {
                format!("{}", f)
            } else if *f > 0.0 {
                "1.7976931348623157e+308".into()
            } else {
                "-1.7976931348623157e+308".into()
            }
        }
        _ => String::new(),
    }
}

/// `jq -c` of a value.
pub fn dump_compact(v: &Jv) -> String {
    match v {
        Jv::Null => "null".into(),
        Jv::Bool(b) => b.to_string(),
        Jv::Int(_) | Jv::Float(_) => num(v),
        Jv::Str(s) => dump_string(s),
        Jv::Arr(a) => {
            let parts: Vec<String> = a.iter().map(dump_compact).collect();
            format!("[{}]", parts.join(","))
        }
        Jv::Obj(items) => {
            let parts: Vec<String> = items
                .iter()
                .map(|(k, x)| format!("{}:{}", dump_string(k), dump_compact(x)))
                .collect();
            format!("{{{}}}", parts.join(","))
        }
    }
}

/// jq's default (pretty, two-space) output of a value.
pub fn dump_pretty(v: &Jv, depth: usize) -> String {
    let pad = |d: usize| "  ".repeat(d);
    match v {
        Jv::Arr(a) if !a.is_empty() => {
            let parts: Vec<String> = a
                .iter()
                .map(|x| format!("{}{}", pad(depth + 1), dump_pretty(x, depth + 1)))
                .collect();
            format!("[\n{}\n{}]", parts.join(",\n"), pad(depth))
        }
        Jv::Obj(items) if !items.is_empty() => {
            let parts: Vec<String> = items
                .iter()
                .map(|(k, x)| {
                    format!(
                        "{}{}: {}",
                        pad(depth + 1),
                        dump_string(k),
                        dump_pretty(x, depth + 1)
                    )
                })
                .collect();
            format!("{{\n{}\n{}}}", parts.join(",\n"), pad(depth))
        }
        other => dump_compact(other),
    }
}

/// `jq -r` of a value: a string raw, anything else as jq prints it.
pub fn raw(v: &Jv) -> String {
    match v {
        Jv::Str(s) => s.clone(),
        other => dump_pretty(other, 0),
    }
}

/// A value as jq names it in an error message: its compact dump, cut to
/// fit jq's 30-byte buffer (`..."` closing a cut string, `...` otherwise).
pub fn dump_trunc(v: &Jv) -> String {
    let d = dump_compact(v);
    if d.len() <= 29 {
        return d;
    }
    let keep = if matches!(v, Jv::Str(_)) { 25 } else { 26 };
    let mut cut = keep;
    while !d.is_char_boundary(cut) {
        cut -= 1;
    }
    let tail = if matches!(v, Jv::Str(_)) {
        "...\""
    } else {
        "..."
    };
    format!("{}{}", &d[..cut], tail)
}

/// The result of running one jq program over an input stream.
#[derive(Debug, Default, PartialEq)]
pub struct Run {
    pub stdout: String,
    pub stderr: String,
    pub status: i32,
}

/// The values in `input`, each with N for its error messages: the newlines
/// up to the end of the line it ends on (jq feeds its parser a line at a
/// time). A parse error ends the stream: Err(message) after the values
/// before it.
pub fn values(input: &[u8]) -> (Vec<(Jv, usize)>, Option<String>) {
    let mut out = Vec::new();
    let mut it = serde_json::Deserializer::from_slice(input).into_iter::<Jv>();
    loop {
        match it.next() {
            None => return (out, None),
            Some(Ok(v)) => {
                let end = it.byte_offset();
                let line_end = input[end..]
                    .iter()
                    .position(|&c| c == b'\n')
                    .map(|i| end + i + 1)
                    .unwrap_or(input.len());
                let n = input[..line_end].iter().filter(|&&c| c == b'\n').count();
                out.push((v, n));
            }
            Some(Err(e)) => {
                return (
                    out,
                    Some(format!(
                        "{} at line {}, column {}",
                        e.to_string()
                            .split(" at line ")
                            .next()
                            .unwrap_or("Invalid JSON"),
                        e.line(),
                        e.column()
                    )),
                )
            }
        }
    }
}

/// Run `program` (value -> outputs or an error) over the stream in `input`,
/// writing each output with `show` and a newline.
pub fn run(
    input: &[u8],
    program: impl Fn(&Jv) -> Result<Vec<Jv>, String>,
    show: impl Fn(&Jv) -> String,
) -> Run {
    let (vals, parse_err) = values(input);
    let mut r = Run::default();
    for (v, n) in vals {
        match program(&v) {
            Ok(outs) => {
                for o in outs {
                    r.stdout.push_str(&show(&o));
                    r.stdout.push('\n');
                }
            }
            Err(msg) => {
                r.stderr
                    .push_str(&format!("jq: error (at <stdin>:{}): {}\n", n, msg));
                r.status = 5;
            }
        }
    }
    if let Some(msg) = parse_err {
        r.stderr.push_str(&format!("jq: parse error: {}\n", msg));
        r.status = 5;
    }
    r
}

/// `.status`.
pub fn status(v: &Jv) -> Result<Vec<Jv>, String> {
    Ok(vec![v.index("status")?])
}

/// `[.[] | select(.name==$n)][0] // empty`.
pub fn select_item(n: &str) -> impl Fn(&Jv) -> Result<Vec<Jv>, String> + '_ {
    move |v: &Jv| {
        let mut first = None;
        for x in v.iterate()? {
            if x.index("name")? == Jv::Str(n.to_string()) && first.is_none() {
                first = Some(x);
            }
        }
        Ok(match first {
            Some(x) if x.truthy() => vec![x],
            _ => vec![],
        })
    }
}

/// `.login.password // empty`.
pub fn password(v: &Jv) -> Result<Vec<Jv>, String> {
    let p = v.index("login")?.index("password")?;
    Ok(if p.truthy() { vec![p] } else { vec![] })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run_status(input: &str) -> Run {
        run(input.as_bytes(), status, raw)
    }

    #[test]
    fn status_of_a_stream() {
        let r = run_status("{\"status\":\"unlocked\"} {\"status\":\"x\"}");
        assert_eq!(r.stdout, "unlocked\nx\n");
        assert_eq!(r.status, 0);
        let r = run_status("{\"a\":1}\n[1]\n");
        assert_eq!(r.stdout, "null\n");
        assert_eq!(
            r.stderr,
            "jq: error (at <stdin>:2): Cannot index array with string (\"status\")\n"
        );
        assert_eq!(r.status, 5);
        assert_eq!(run_status("").stdout, "");
    }

    #[test]
    fn error_line_numbers_count_lines_fed() {
        let n = |s: &str| run_status(s).stderr;
        assert!(n("\"s\"\n").contains("<stdin>:1"));
        assert!(n("\n\n\"s\"").contains("<stdin>:2"));
        assert!(n("\"s\"\n\n\n").contains("<stdin>:1"));
        assert!(n("\"s\" \n").contains("<stdin>:1"));
        assert!(n("[1,\n2]\n").contains("<stdin>:2"));
        assert!(n("true").contains("<stdin>:0"));
    }

    #[test]
    fn selecting_the_item() {
        let f = select_item("argocd admin (dev-local)");
        let r = run(
            b"[{\"name\":\"x\"},null,{\"name\":\"argocd admin (dev-local)\",\"z\":1,\"b\":2},{\"name\":\"argocd admin (dev-local)\"}]",
            &f,
            dump_compact,
        );
        assert_eq!(
            r.stdout,
            "{\"name\":\"argocd admin (dev-local)\",\"z\":1,\"b\":2}\n"
        );
        let r = run(b"[1]", &f, dump_compact);
        assert_eq!(
            r.stderr,
            "jq: error (at <stdin>:0): Cannot index number with string (\"name\")\n"
        );
        let r = run(b"null", &f, dump_compact);
        assert_eq!(
            r.stderr,
            "jq: error (at <stdin>:0): Cannot iterate over null (null)\n"
        );
        let r = run(b"\"aaaaaaaaaaaaaaaaaaaaaaaaaaaa\"", &f, dump_compact);
        assert_eq!(
            r.stderr,
            "jq: error (at <stdin>:0): Cannot iterate over string (\"aaaaaaaaaaaaaaaaaaaaaaaa...\")\n"
        );
    }

    #[test]
    fn passwords() {
        let r = run(b"{\"login\":{\"password\":\"p\"}}\n{\"login\":null}\n{\"login\":{\"password\":false}}\n", password, raw);
        assert_eq!(r.stdout, "p\n");
        let r = run(b"{\"login\":\"x\"}\n", password, raw);
        assert_eq!(
            r.stderr,
            "jq: error (at <stdin>:1): Cannot index string with string (\"password\")\n"
        );
        let r = run(
            b"{\"login\":{\"password\":{\"b\":1,\"a\":[1,2]}}}",
            password,
            raw,
        );
        assert_eq!(
            r.stdout,
            "{\n  \"b\": 1,\n  \"a\": [\n    1,\n    2\n  ]\n}\n"
        );
    }

    #[test]
    fn strings_escape_as_jq() {
        assert_eq!(
            dump_string("a\u{7f}\u{1}é/\"\\\n"),
            "\"a\\u007f\\u0001é/\\\"\\\\\\n\""
        );
    }
}
