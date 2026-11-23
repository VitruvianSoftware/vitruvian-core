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

//! The five `jq -r` filters sync-env-secrets.sh runs over `bw` output,
//! implemented as thin filters over `vitruvian_jq` (matching jq 1.8.2).

use vitruvian_jq::{each, first, one, or_empty, run, Produced, RunOptions, RunResult, Value};

/// What `jq -r FILTER` printed and its exit status.
pub type JqOut = RunResult;

fn match_attachment<'a>(name: &'a str) -> impl Fn(&Value) -> Produced + 'a {
    move |e: &Value| match e.index("fileName") {
        Ok(fname) if fname.is_str(name) => one(e.index("id")),
        Ok(_) => (Vec::new(), None),
        Err(err) => (Vec::new(), Some(err)),
    }
}

/// `jq -r '.status'`.
pub fn status(input: &[u8]) -> JqOut {
    run(input, RunOptions::raw(), |v| one(v.index("status")))
}

/// `jq -r '.id'`.
pub fn id(input: &[u8]) -> JqOut {
    run(input, RunOptions::raw(), |v| one(v.index("id")))
}

/// `jq -r '.[0].id // empty'`.
pub fn first_id_or_empty(input: &[u8]) -> JqOut {
    run(input, RunOptions::raw(), |v| {
        or_empty(one(v.index_num(0).and_then(|x| x.index("id"))))
    })
}

/// `jq -r --arg n NAME '.attachments[]? | select(.fileName==$n) | .id'`.
pub fn attachment_ids(input: &[u8], name: &str) -> JqOut {
    run(input, RunOptions::raw(), |v| {
        each(
            v.index("attachments").map(|a| a.iterate_opt()),
            match_attachment(name),
        )
    })
}

/// `jq -r --arg n NAME 'first(.attachments[]? | select(.fileName==$n) | .id) // empty'`.
pub fn first_attachment_id_or_empty(input: &[u8], name: &str) -> JqOut {
    run(input, RunOptions::raw(), |v| {
        or_empty(first(
            v.index("attachments").map(|a| a.iterate_opt()),
            match_attachment(name),
        ))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(o: JqOut) -> (String, i32) {
        (o.stdout_string(), o.status)
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
    fn error_messages_match_jq_182() {
        let o = status(b"\"s\"\n");
        assert_eq!(
            o.stderr_string(),
            "jq: error (at <stdin>:1): Cannot index string with string (\"status\")\n"
        );
        let o = first_id_or_empty(br#"{"id":"x"}"#);
        assert_eq!(
            o.stderr_string(),
            "jq: error (at <stdin>:0): Cannot index object with number (0)\n"
        );
        assert!(status(b"{")
            .stderr_string()
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

    #[test]
    fn first_attachment_short_circuits_on_falsy_match() {
        let item = br#"{"attachments":[{"fileName":"a","id":false},{"fileName":"a","id":"2"}]}"#;
        assert_eq!(s(first_attachment_id_or_empty(item, "a")), ("".into(), 0));
    }

    #[test]
    fn secret_values_never_leak_in_errors() {
        let payloads: &[&[u8]] = &[
            br#""FAKE-SECRET-VALUE-1""#,
            br#"["FAKE-SECRET-VALUE-1"]"#,
            br#"{"attachments":["FAKE-SECRET-VALUE-1"]}"#,
            br#"{"attachments":"FAKE-SECRET-VALUE-1"}"#,
            br#"{"secret":"FAKE-SECRET-VALUE-1"#,
        ];
        for inp in payloads {
            for r in [
                status(inp),
                id(inp),
                first_id_or_empty(inp),
                attachment_ids(inp, "a"),
                first_attachment_id_or_empty(inp, "a"),
            ] {
                assert!(
                    !r.stderr_string().contains("FAKE-SECRET-VALUE-1"),
                    "secret leaked in stderr for {}: {}",
                    String::from_utf8_lossy(inp),
                    r.stderr_string()
                );
                assert!(
                    !r.stdout_string().contains("FAKE-SECRET-VALUE-1"),
                    "secret leaked in stdout for {}: {}",
                    String::from_utf8_lossy(inp),
                    r.stdout_string()
                );
            }
        }
    }
}
