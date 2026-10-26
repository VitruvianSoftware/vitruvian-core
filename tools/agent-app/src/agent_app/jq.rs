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

//! The four jq programs agent-app.sh runs locally on GitHub's answers, in
//! Rust: `.token` and `.pem` (with `-re`), convert's summary line, the
//! installations table and the repository list (with `-r`). Parsed with
//! serde_json into a value that keeps object keys in document order, as jq
//! does, and printed the way jq prints: strings raw under `-r`, anything else
//! as JSON (indented by two at the top level, compact inside a string
//! interpolation), errors as `jq: error (at <stdin>:N): ...` with exit 5.

use serde::de::{Deserialize, Deserializer, MapAccess, SeqAccess, Visitor};
use std::fmt;

/// A JSON value as jq holds it: objects keep their keys in document order
/// (a repeated key keeps its first place and its last value).
#[derive(Clone, Debug, PartialEq)]
pub enum J {
    Null,
    Bool(bool),
    Uint(u64),
    Int(i64),
    Float(f64),
    Str(String),
    Arr(Vec<J>),
    Obj(Vec<(String, J)>),
}

struct JVisitor;

impl<'de> Visitor<'de> for JVisitor {
    type Value = J;

    fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str("a JSON value")
    }
    fn visit_unit<E>(self) -> Result<J, E> {
        Ok(J::Null)
    }
    fn visit_none<E>(self) -> Result<J, E> {
        Ok(J::Null)
    }
    fn visit_bool<E>(self, b: bool) -> Result<J, E> {
        Ok(J::Bool(b))
    }
    fn visit_u64<E>(self, n: u64) -> Result<J, E> {
        Ok(J::Uint(n))
    }
    fn visit_i64<E>(self, n: i64) -> Result<J, E> {
        Ok(J::Int(n))
    }
    fn visit_f64<E>(self, n: f64) -> Result<J, E> {
        Ok(J::Float(n))
    }
    fn visit_str<E>(self, s: &str) -> Result<J, E> {
        Ok(J::Str(s.to_string()))
    }
    fn visit_string<E>(self, s: String) -> Result<J, E> {
        Ok(J::Str(s))
    }
    fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<J, A::Error> {
        let mut v = Vec::new();
        while let Some(x) = seq.next_element::<J>()? {
            v.push(x);
        }
        Ok(J::Arr(v))
    }
    fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<J, A::Error> {
        let mut v: Vec<(String, J)> = Vec::new();
        while let Some((k, x)) = map.next_entry::<String, J>()? {
            match v.iter_mut().find(|(have, _)| *have == k) {
                Some(slot) => slot.1 = x,
                None => v.push((k, x)),
            }
        }
        Ok(J::Obj(v))
    }
}

impl<'de> Deserialize<'de> for J {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<J, D::Error> {
        d.deserialize_any(JVisitor)
    }
}

impl J {
    fn type_name(&self) -> &'static str {
        match self {
            J::Null => "null",
            J::Bool(_) => "boolean",
            J::Uint(_) | J::Int(_) | J::Float(_) => "number",
            J::Str(_) => "string",
            J::Arr(_) => "array",
            J::Obj(_) => "object",
        }
    }

    /// `.key`: null on null or a missing key; an error on anything but an
    /// object.
    pub fn index(&self, key: &str) -> Result<J, String> {
        match self {
            J::Null => Ok(J::Null),
            J::Obj(kv) => Ok(kv
                .iter()
                .find(|(k, _)| k == key)
                .map(|(_, v)| v.clone())
                .unwrap_or(J::Null)),
            other => Err(format!(
                "Cannot index {} with string ({})",
                other.type_name(),
                J::Str(key.to_string()).compact()
            )),
        }
    }

    /// `.[]`: an array's items or an object's values, in order.
    pub fn iterate(&self) -> Result<Vec<J>, String> {
        match self {
            J::Arr(v) => Ok(v.clone()),
            J::Obj(kv) => Ok(kv.iter().map(|(_, v)| v.clone()).collect()),
            other => Err(format!(
                "Cannot iterate over {} ({})",
                other.type_name(),
                trunc(&other.compact())
            )),
        }
    }

    /// `tojson`.
    pub fn compact(&self) -> String {
        let mut s = String::new();
        dump(self, None, 0, &mut s);
        s
    }

    /// What jq prints for a value with `-r`: a string as it is, anything else
    /// as indented JSON.
    pub fn raw(&self) -> String {
        match self {
            J::Str(s) => s.clone(),
            other => {
                let mut s = String::new();
                dump(other, Some(2), 0, &mut s);
                s
            }
        }
    }

    /// `"\(.)"`: a string as it is, anything else as compact JSON.
    pub fn interp(&self) -> String {
        match self {
            J::Str(s) => s.clone(),
            other => other.compact(),
        }
    }

    fn truthy(&self) -> bool {
        !matches!(self, J::Null | J::Bool(false))
    }
}

/// jq's error-message rendering of a value: up to 29 bytes as it is, a
/// longer one cut to 25 and "...".
fn trunc(s: &str) -> String {
    if s.len() <= 29 {
        return s.to_string();
    }
    let mut end = 25;
    while !s.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}...", &s[..end])
}

fn number(n: f64) -> String {
    if n.is_nan() {
        return "null".to_string();
    }
    if n.is_infinite() {
        return if n > 0.0 {
            "1.7976931348623157e+308".to_string()
        } else {
            "-1.7976931348623157e+308".to_string()
        };
    }
    format!("{}", n)
}

fn string(s: &str, out: &mut String) {
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
                out.push_str(&format!("\\u{:04x}", c as u32))
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

fn dump(v: &J, indent: Option<usize>, level: usize, out: &mut String) {
    let pad = |out: &mut String, l: usize| {
        if let Some(n) = indent {
            out.push('\n');
            for _ in 0..n * l {
                out.push(' ');
            }
        }
    };
    match v {
        J::Null => out.push_str("null"),
        J::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        J::Uint(n) => out.push_str(&n.to_string()),
        J::Int(n) => out.push_str(&n.to_string()),
        J::Float(n) => out.push_str(&number(*n)),
        J::Str(s) => string(s, out),
        J::Arr(items) => {
            if items.is_empty() {
                out.push_str("[]");
                return;
            }
            out.push('[');
            for (i, x) in items.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                pad(out, level + 1);
                dump(x, indent, level + 1, out);
            }
            pad(out, level);
            out.push(']');
        }
        J::Obj(kv) => {
            if kv.is_empty() {
                out.push_str("{}");
                return;
            }
            out.push('{');
            for (i, (k, x)) in kv.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                pad(out, level + 1);
                string(k, out);
                out.push(':');
                if indent.is_some() {
                    out.push(' ');
                }
                dump(x, indent, level + 1, out);
            }
            pad(out, level);
            out.push('}');
        }
    }
}

/// The jq programs agent-app.sh runs.
pub enum Prog<'a> {
    /// `.KEY`
    Field(&'a str),
    /// `"app_id=\(.id)\nslug=\(.slug)\nowner=\(.owner.login)\nkey=" + $out`
    Convert(&'a str),
    /// `.[] | "installation_id=\(.id)\taccount=\(.account.login)\tselection=\(.repository_selection)"`
    Installations,
    /// `.repositories[].full_name`
    Repos,
}

/// Every output of `prog` on `v`, in order, until the first error (the
/// outputs before it are still jq's output).
fn eval(prog: &Prog, v: &J, outs: &mut Vec<J>) -> Result<(), String> {
    match prog {
        Prog::Field(k) => outs.push(v.index(k)?),
        // jq evaluates a string's interpolations last first, so when two
        // would fail, the error is the later one's.
        Prog::Convert(out) => {
            let login = v.index("owner")?.index("login")?.interp();
            let slug = v.index("slug")?.interp();
            let id = v.index("id")?.interp();
            outs.push(J::Str(format!(
                "app_id={}\nslug={}\nowner={}\nkey={}",
                id, slug, login, out
            )));
        }
        Prog::Installations => {
            for x in v.iterate()? {
                let sel = x.index("repository_selection")?.interp();
                let acct = x.index("account")?.index("login")?.interp();
                let id = x.index("id")?.interp();
                outs.push(J::Str(format!(
                    "installation_id={}\taccount={}\tselection={}",
                    id, acct, sel
                )));
            }
        }
        Prog::Repos => {
            for x in v.index("repositories")?.iterate()? {
                outs.push(x.index("full_name")?);
            }
        }
    }
    Ok(())
}

/// What `jq -r [-e] PROG` makes of `input`: stdout, stderr, exit status.
pub struct Ran {
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub status: i32,
}

/// What jq says about input it cannot parse, for input that stops short (the
/// usual way a GitHub answer goes wrong): `<what> at EOF at line L, column C`.
/// Malformed JSON that does not stop short gets serde_json's account of it.
fn parse_error(input: &[u8], start: usize, e: &serde_json::Error) -> String {
    let rem = &input[start.min(input.len())..];
    let mut in_str = false;
    let mut esc = false;
    let mut word: Vec<u8> = Vec::new();
    let mut word_at = 0;
    for (i, &c) in rem.iter().enumerate() {
        if in_str {
            if esc {
                esc = false;
            } else if c == b'\\' {
                esc = true;
            } else if c == b'"' {
                in_str = false;
            }
            continue;
        }
        match c {
            b'"' => {
                in_str = true;
                word.clear();
            }
            b' ' | b'\t' | b'\n' | b'\r' | b'[' | b']' | b'{' | b'}' | b',' | b':' => word.clear(),
            _ => {
                if word.is_empty() {
                    word_at = start + i;
                }
                word.push(c)
            }
        }
    }
    let bad_word = || -> Option<&'static str> {
        if word.is_empty() {
            return None;
        }
        match word[0] {
            b't' | b'f' | b'n' => {
                if matches!(word.as_slice(), b"true" | b"false" | b"null" | b"nan") {
                    None
                } else {
                    Some("Invalid literal")
                }
            }
            _ => {
                let ok = std::str::from_utf8(&word)
                    .ok()
                    .map_or(false, |w| w.parse::<f64>().is_ok() && !w.starts_with('+'));
                if ok {
                    None
                } else {
                    Some("Invalid numeric literal")
                }
            }
        }
    };
    let lines = input.iter().filter(|&&c| c == b'\n').count();
    let col = input.len() - input.iter().rposition(|&c| c == b'\n').map_or(0, |i| i + 1);
    let at_eof = |what: &str| format!("{} at EOF at line {}, column {}", what, lines + 1, col);
    if e.is_eof() {
        if in_str {
            return at_eof("Unfinished string");
        }
        return at_eof(bad_word().unwrap_or("Unfinished JSON term"));
    }
    // A bad word that runs to the end: jq only judges it at EOF.
    let err_at = line_col_offset(input, e.line(), e.column());
    if let Some(what) = bad_word() {
        if !in_str && err_at.map_or(false, |o| o >= word_at) {
            return at_eof(what);
        }
    }
    let m = e.to_string();
    let m = match m.rfind(" at line ") {
        Some(i) => m[..i].to_string(),
        None => m,
    };
    format!("{} at line {}, column {}", m, e.line(), e.column())
}

fn line_col_offset(input: &[u8], line: usize, col: usize) -> Option<usize> {
    let mut l = 1;
    let mut start = 0;
    for (i, &c) in input.iter().enumerate() {
        if l == line {
            break;
        }
        if c == b'\n' {
            l += 1;
            start = i + 1;
        }
    }
    if l != line {
        return None;
    }
    Some(start + col.saturating_sub(1))
}

pub fn run(prog: &Prog, input: &[u8], exit_status: bool) -> Ran {
    let mut r = Ran {
        stdout: Vec::new(),
        stderr: Vec::new(),
        status: 0,
    };
    let mut last: Option<J> = None;
    let mut errored = false;
    let mut stream = serde_json::Deserializer::from_slice(input).into_iter::<J>();
    loop {
        let start = stream.byte_offset();
        let v = match stream.next() {
            None => break,
            Some(Ok(v)) => v,
            Some(Err(e)) => {
                // Where the failing value starts: past the whitespace.
                let mut s = start;
                while s < input.len() && matches!(input[s], b' ' | b'\t' | b'\n' | b'\r') {
                    s += 1;
                }
                r.stderr.extend_from_slice(
                    format!("jq: parse error: {}\n", parse_error(input, s, &e)).as_bytes(),
                );
                r.status = 5;
                return r;
            }
        };
        // jq counts the lines it has read when the value ends: through the
        // character after it.
        let end = stream.byte_offset();
        let upto = (end + 1).min(input.len());
        let line = input[..upto].iter().filter(|&&c| c == b'\n').count();
        let mut outs = Vec::new();
        let res = eval(prog, &v, &mut outs);
        for o in outs {
            r.stdout.extend_from_slice(o.raw().as_bytes());
            r.stdout.push(b'\n');
            last = Some(o);
        }
        if let Err(m) = res {
            r.stderr
                .extend_from_slice(format!("jq: error (at <stdin>:{}): {}\n", line, m).as_bytes());
            errored = true;
        }
    }
    r.status = if errored {
        5
    } else if !exit_status {
        0
    } else {
        match last {
            None => 4,
            Some(v) if v.truthy() => 0,
            Some(_) => 1,
        }
    };
    r
}
