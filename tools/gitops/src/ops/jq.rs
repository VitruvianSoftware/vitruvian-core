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

//! The jq filters the gitops tools run, implemented as thin filters over
//! `vitruvian_jq` (matching jq 1.8.2).

use vitruvian_jq::{alt, any, each, one, or_empty, run, OutputOptions, RunOptions, Value};

/// `jq -r '.KEY'`.
pub fn field_r(input: &[u8], key: &str) -> (Vec<u8>, bool) {
    let res = run(input, RunOptions::raw(), |v| one(v.index(key)));
    (res.stdout, res.status == 0)
}

/// `jq -r '.KEY // empty'`.
pub fn field_or_empty_r(input: &[u8], key: &str) -> (Vec<u8>, bool) {
    let res = run(input, RunOptions::raw(), |v| or_empty(one(v.index(key))));
    (res.stdout, res.status == 0)
}

/// `jq -r --arg f FILE '.attachments[]? | select(.fileName == $f) | .id'`:
/// the matching ids, one per line.
pub fn attachment_ids(input: &[u8], file: &str) -> (Vec<u8>, bool) {
    let res = run(input, RunOptions::raw(), |v| {
        each(
            v.index("attachments").map(|a| a.iterate_opt()),
            |a| match a.index("fileName") {
                Ok(f) if f.is_str(file) => one(a.index("id")),
                Ok(_) => (Vec::new(), None),
                Err(e) => (Vec::new(), Some(e)),
            },
        )
    });
    (res.stdout, res.status == 0)
}

/// `jq -e --arg f FILE 'any(.attachments[]?; .fileName == $f)'`: true when
/// the last output is true.
pub fn has_attachment(input: &[u8], file: &str) -> bool {
    let res = run(
        input,
        RunOptions {
            output: OutputOptions::pretty(),
            exit_status: true,
        },
        |v| {
            any(v.index("attachments").map(|a| a.iterate_opt()), |a| {
                Ok(a.index("fileName")?.is_str(file))
            })
        },
    );
    res.status == 0
}

/// `jq '[.items[]? | select(.kind == "Secret")] | length'` per input value;
/// None when jq would fail (bad JSON, an item that is not an object).
pub fn count_secrets(input: &[u8]) -> Option<Vec<usize>> {
    let mut counts = Vec::new();
    let res = run(input, RunOptions::compact(), |v| {
        let items = match v.index("items") {
            Ok(x) => x.iterate_opt(),
            Err(e) => return (Vec::new(), Some(e)),
        };
        let mut n = 0usize;
        for it in &items {
            match it.index("kind") {
                Ok(k) if k.is_str("Secret") => n += 1,
                Ok(_) => {}
                Err(e) => return (Vec::new(), Some(e)),
            }
        }
        counts.push(n);
        (vec![Value::uint(n as u64)], None)
    });
    if res.status != 0 {
        None
    } else {
        Some(counts)
    }
}

/// `jq -r '.data.result[0].value[1] // "0"'` (Prometheus' instant query).
pub fn prom_value(input: &[u8]) -> (Vec<u8>, bool) {
    let res = run(input, RunOptions::raw(), |v| {
        alt(
            one(v
                .index("data")
                .and_then(|d| d.index("result"))
                .and_then(|r| r.index_num(0))
                .and_then(|r| r.index("value"))
                .and_then(|r| r.index_num(1))),
            || (vec![Value::str("0")], None),
        )
    });
    (res.stdout, res.status == 0)
}

/// `jq -r '.traces[0].traceID // empty'` (Tempo's search).
pub fn first_trace_id(input: &[u8]) -> Vec<u8> {
    run(input, RunOptions::raw(), |v| {
        or_empty(one(v
            .index("traces")
            .and_then(|d| d.index_num(0))
            .and_then(|r| r.index("traceID"))))
    })
    .stdout
}

#[cfg(test)]
mod tests {
    use super::*;

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
        // jq 1.8 `// empty` propagates errors on its left operand.
        assert!(!field_or_empty_r(br#""s""#, "id").1);
    }

    #[test]
    fn attachments() {
        let item = br#"{"attachments":[{"fileName":"a","id":"1"},{"fileName":"k.json","id":"2"},{"fileName":"k.json","id":"3"}]}"#;
        assert_eq!(attachment_ids(item, "k.json"), (b"2\n3\n".to_vec(), true));
        assert!(!attachment_ids(br#""s""#, "k.json").1);
        assert!(has_attachment(item, "k.json"));
        assert!(!has_attachment(item, "zzz"));
        assert!(!has_attachment(br#"{}"#, "k.json"));
        // Short-circuits on first match before later invalid element.
        let short = br#"{"attachments":[{"fileName":"k.json"},"x"]}"#;
        assert!(has_attachment(short, "k.json"));
        let bad_first = br#"{"attachments":["x",{"fileName":"k.json"}]}"#;
        assert!(!has_attachment(bad_first, "k.json"));
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
        assert_eq!(count_secrets(br#"{"items":["FAKE-SECRET-VALUE-1"]}"#), None);
        assert_eq!(count_secrets(b"{"), None);
    }

    #[test]
    fn prometheus_and_tempo() {
        assert_eq!(
            prom_value(br#"{"data":{"result":[{"value":[0,"1"]}]}}"#).0,
            b"1\n"
        );
        assert_eq!(
            prom_value(br#"{"data":{"result":[]}}"#),
            (b"0\n".to_vec(), true)
        );
        assert!(!prom_value(br#""bad""#).1);
        assert_eq!(
            first_trace_id(br#"{"traces":[{"traceID":"abc"}]}"#),
            b"abc\n"
        );
        assert_eq!(first_trace_id(br#"{"traces":[]}"#), b"");
    }
}
