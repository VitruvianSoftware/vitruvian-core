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

//! The five `jq -r` filters sync-env-secrets.sh runs over `bw` output, over
//! serde_json instead of a jq binary. Each reads a stream of JSON values the
//! way jq 1.7 does: every value in turn, a runtime error on one (indexing a
//! string, say) reported and the next one still processed; the exit status
//! is that of the LAST value (5 if it failed, else 0), and a parse error
//! ends the stream with 5. Output is `-r`: a string raw, anything else as
//! JSON, one per line.

use serde_json::Value;

/// A jq runtime error: the message after "jq: error (at <stdin>:N): ".
type JqErr = String;

/// One filter applied to one input: what it output, then the error it hit
/// if it hit one (outputs before the error are still printed).
type Filter<'a> = dyn Fn(&Value) -> (Vec<Value>, Option<JqErr>) + 'a;

/// What `jq -r FILTER` printed and its exit status.
#[derive(Debug, PartialEq)]
pub struct JqOut {
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub status: i32,
}

fn render(v: &Value, out: &mut Vec<u8>) {
    match v {
        Value::String(s) => out.extend_from_slice(s.as_bytes()),
        Value::Array(a) if a.is_empty() => out.extend_from_slice(b"[]"),
        Value::Object(o) if o.is_empty() => out.extend_from_slice(b"{}"),
        Value::Array(_) | Value::Object(_) => {
            out.extend(serde_json::to_vec_pretty(v).unwrap_or_default());
        }
        other => out.extend(serde_json::to_vec(other).unwrap_or_default()),
    }
    out.push(b'\n');
}

fn run(input: &[u8], f: &Filter) -> JqOut {
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();
    let mut status = 0;
    // jq names the input line it had read up to; it reads small inputs whole.
    let lines = input.iter().filter(|&&c| c == b'\n').count();
    let stream = serde_json::Deserializer::from_slice(input).into_iter::<Value>();
    for item in stream {
        match item {
            Ok(v) => {
                let (outs, failed) = f(&v);
                outs.iter().for_each(|o| render(o, &mut stdout));
                status = match failed {
                    Some(msg) => {
                        stderr.extend(
                            format!("jq: error (at <stdin>:{}): {}\n", lines, msg).into_bytes(),
                        );
                        5
                    }
                    None => 0,
                };
            }
            Err(e) => {
                stderr.extend(format!("jq: parse error: {}\n", e).into_bytes());
                status = 5;
                break;
            }
        }
    }
    JqOut {
        stdout,
        stderr,
        status,
    }
}

fn type_name(v: &Value) -> &'static str {
    match v {
        Value::Null => "null",
        Value::Bool(_) => "boolean",
        Value::Number(_) => "number",
        Value::String(_) => "string",
        Value::Array(_) => "array",
        Value::Object(_) => "object",
    }
}

/// `.key` on one value: null and objects index, anything else is an error.
fn field(v: &Value, key: &str) -> Result<Value, JqErr> {
    match v {
        Value::Null => Ok(Value::Null),
        Value::Object(o) => Ok(o.get(key).cloned().unwrap_or(Value::Null)),
        other => Err(format!(
            "Cannot index {} with string (\"{}\")",
            type_name(other),
            key
        )),
    }
}

/// `.[0]`: null and arrays index, anything else is an error.
fn first_elem(v: &Value) -> Result<Value, JqErr> {
    match v {
        Value::Null => Ok(Value::Null),
        Value::Array(a) => Ok(a.first().cloned().unwrap_or(Value::Null)),
        other => Err(format!("Cannot index {} with number", type_name(other))),
    }
}

fn truthy(v: &Value) -> bool {
    !matches!(v, Value::Null | Value::Bool(false))
}

/// `.attachments[]? | select(.fileName==$n) | .id`, stopping after `limit`
/// outputs when given (jq's `first(...)`).
fn matching_attachment_ids(
    v: &Value,
    name: &str,
    limit: Option<usize>,
) -> (Vec<Value>, Option<JqErr>) {
    // `.attachments[]?`: the ? swallows an error from the iteration only, so
    // a non-iterable `.attachments` yields nothing, but indexing a value that
    // is not an object (or null) is still an error.
    let elems: Vec<Value> = match field(v, "attachments") {
        Ok(Value::Array(a)) => a,
        Ok(Value::Object(o)) => o.into_iter().map(|(_, x)| x).collect(),
        Ok(_) => Vec::new(),
        Err(e) => return (Vec::new(), Some(e)),
    };
    let mut out = Vec::new();
    for e in &elems {
        let fname = match field(e, "fileName") {
            Ok(x) => x,
            Err(err) => return (out, Some(err)),
        };
        if fname == Value::String(name.to_string()) {
            match field(e, "id") {
                Ok(x) => out.push(x),
                Err(err) => return (out, Some(err)),
            }
            if limit.map_or(false, |l| out.len() >= l) {
                break;
            }
        }
    }
    (out, None)
}

fn one(r: Result<Value, JqErr>) -> (Vec<Value>, Option<JqErr>) {
    match r {
        Ok(x) => (vec![x], None),
        Err(e) => (Vec::new(), Some(e)),
    }
}

/// `a // empty`: a's truthy outputs. jq 1.7 does not swallow an error in
/// `a`; it is still raised.
fn or_empty((outs, err): (Vec<Value>, Option<JqErr>)) -> (Vec<Value>, Option<JqErr>) {
    (outs.into_iter().filter(truthy).collect(), err)
}

/// `jq -r '.status'`.
pub fn status(input: &[u8]) -> JqOut {
    run(input, &|v| one(field(v, "status")))
}

/// `jq -r '.id'`.
pub fn id(input: &[u8]) -> JqOut {
    run(input, &|v| one(field(v, "id")))
}

/// `jq -r '.[0].id // empty'`.
pub fn first_id_or_empty(input: &[u8]) -> JqOut {
    run(input, &|v| {
        or_empty(one(first_elem(v).and_then(|x| field(&x, "id"))))
    })
}

/// `jq -r --arg n NAME '.attachments[]? | select(.fileName==$n) | .id'`.
pub fn attachment_ids(input: &[u8], name: &str) -> JqOut {
    run(input, &|v| matching_attachment_ids(v, name, None))
}

/// `jq -r --arg n NAME 'first(.attachments[]? | select(.fileName==$n) | .id) // empty'`.
pub fn first_attachment_id_or_empty(input: &[u8], name: &str) -> JqOut {
    run(input, &|v| {
        or_empty(matching_attachment_ids(v, name, Some(1)))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(o: JqOut) -> (String, i32) {
        (String::from_utf8(o.stdout).unwrap(), o.status)
    }

    #[test]
    fn status_field() {
        assert_eq!(
            s(status(br#"{"status":"unlocked"}"#)),
            ("unlocked\n".into(), 0)
        );
        assert_eq!(s(status(b"")), ("".into(), 0));
        assert_eq!(s(status(b"{}")), ("null\n".into(), 0));
        assert_eq!(s(status(b"not json")), ("".into(), 5));
        assert_eq!(s(status(br#""str""#)), ("".into(), 5));
        assert_eq!(
            s(status(br#"{"status":"a"} {"status":"b"}"#)),
            ("a\nb\n".into(), 0)
        );
        assert_eq!(s(status(br#"{"status":"a"} oops"#)), ("a\n".into(), 5));
        // The status is the last value's: an earlier failure is forgiven.
        assert_eq!(s(status(br#"[1] {"status":"b"}"#)), ("b\n".into(), 0));
        assert_eq!(s(status(br#"{"status":"b"} [1]"#)), ("b\n".into(), 5));
        assert_eq!(
            s(status(br#"{"status":{"x":1}}"#)),
            ("{\n  \"x\": 1\n}\n".into(), 0)
        );
        assert_eq!(s(status(br#"{"status":3}"#)), ("3\n".into(), 0));
    }

    #[test]
    fn first_id() {
        assert_eq!(
            s(first_id_or_empty(br#"[{"id":"abc"},{"id":"def"}]"#)),
            ("abc\n".into(), 0)
        );
        assert_eq!(s(first_id_or_empty(b"[]")), ("".into(), 0));
        assert_eq!(s(first_id_or_empty(br#"{"id":"x"}"#)), ("".into(), 5));
        assert_eq!(s(first_id_or_empty(br#"[{"id":false}]"#)), ("".into(), 0));
        assert_eq!(s(first_id_or_empty(br#"["str"]"#)), ("".into(), 5));
        assert_eq!(s(first_id_or_empty(b"garbage")), ("".into(), 5));
    }

    #[test]
    fn error_messages_name_the_types() {
        let o = status(b"\"s\"\n");
        assert_eq!(
            String::from_utf8(o.stderr).unwrap(),
            "jq: error (at <stdin>:1): Cannot index string with string (\"status\")\n"
        );
        let o = first_id_or_empty(br#"{"id":"x"}"#);
        assert_eq!(
            String::from_utf8(o.stderr).unwrap(),
            "jq: error (at <stdin>:0): Cannot index object with number\n"
        );
        assert!(String::from_utf8(status(b"{").stderr)
            .unwrap()
            .starts_with("jq: parse error: "));
    }

    #[test]
    fn plain_id() {
        assert_eq!(s(id(br#"{"id":"new"}"#)), ("new\n".into(), 0));
        assert_eq!(s(id(br#"{}"#)), ("null\n".into(), 0));
        assert_eq!(s(id(b"")), ("".into(), 0));
        assert_eq!(s(id(b"[]")), ("".into(), 5));
    }

    #[test]
    fn attachments() {
        let item = br#"{"attachments":[{"fileName":"a.tgz","id":"1"},{"fileName":"b","id":"2"},{"fileName":"a.tgz","id":"3"}]}"#;
        assert_eq!(s(attachment_ids(item, "a.tgz")), ("1\n3\n".into(), 0));
        assert_eq!(
            s(first_attachment_id_or_empty(item, "a.tgz")),
            ("1\n".into(), 0)
        );
        assert_eq!(s(attachment_ids(br#"{}"#, "a.tgz")), ("".into(), 0));
        assert_eq!(
            s(attachment_ids(br#"{"attachments":null}"#, "a")),
            ("".into(), 0)
        );
        assert_eq!(
            s(attachment_ids(br#"{"attachments":5}"#, "a")),
            ("".into(), 0)
        );
        assert_eq!(s(attachment_ids(br#""str""#, "a")), ("".into(), 5));
        assert_eq!(
            s(attachment_ids(
                br#""str" {"attachments":[{"fileName":"a","id":"1"}]}"#,
                "a"
            )),
            ("1\n".into(), 0)
        );
        assert_eq!(
            s(attachment_ids(br#"{"attachments":["x"]}"#, "a")),
            ("".into(), 5)
        );
        assert_eq!(
            s(attachment_ids(
                br#"{"attachments":[{"fileName":"a","id":"1"},"x"]}"#,
                "a"
            )),
            ("1\n".into(), 5)
        );
        assert_eq!(
            s(first_attachment_id_or_empty(
                br#"{"attachments":["x"]}"#,
                "a"
            )),
            ("".into(), 5)
        );
        assert_eq!(
            s(first_attachment_id_or_empty(
                br#"{"attachments":[{"fileName":"a","id":"1"},"x"]}"#,
                "a"
            )),
            ("1\n".into(), 0)
        );
        assert_eq!(
            s(first_attachment_id_or_empty(
                br#"{"attachments":[{"fileName":"a"}]}"#,
                "a"
            )),
            ("".into(), 0)
        );
        assert_eq!(
            s(attachment_ids(
                br#"{"attachments":[{"fileName":"a"}]}"#,
                "a"
            )),
            ("null\n".into(), 0)
        );
    }
}
