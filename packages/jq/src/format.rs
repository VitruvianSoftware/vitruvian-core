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

//! jq 1.8 output writers (`jq`, `jq -c`, `jq -r`, `jq -S`), `tostring`,
//! string interpolation, error-message truncation, and `@uri`.

use crate::value::Value;

/// Formatting flags matching jq CLI output options (`-c`, `-r`, `-S`).
#[derive(Copy, Clone, Debug, Default, PartialEq, Eq)]
pub struct OutputOptions {
    pub compact: bool,
    pub raw: bool,
    pub sort_keys: bool,
}

impl OutputOptions {
    pub const fn pretty() -> Self {
        Self {
            compact: false,
            raw: false,
            sort_keys: false,
        }
    }

    pub const fn compact() -> Self {
        Self {
            compact: true,
            raw: false,
            sort_keys: false,
        }
    }

    pub const fn raw() -> Self {
        Self {
            compact: false,
            raw: true,
            sort_keys: false,
        }
    }

    pub const fn raw_compact() -> Self {
        Self {
            compact: true,
            raw: true,
            sort_keys: false,
        }
    }

    pub const fn sorted() -> Self {
        Self {
            compact: false,
            raw: false,
            sort_keys: true,
        }
    }

    pub const fn sorted_compact() -> Self {
        Self {
            compact: true,
            raw: false,
            sort_keys: true,
        }
    }

    pub const fn raw_sorted() -> Self {
        Self {
            compact: false,
            raw: true,
            sort_keys: true,
        }
    }
}

/// Escapes and quotes a JSON string the way jq 1.8 does:
/// `"` and `\`, C0 controls (`\b`, `\t`, `\n`, `\f`, `\r`, `\u00xx`), and
/// DEL (`\u007f`); `/` and non-ASCII UTF-8 pass through verbatim.
pub fn dump_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    write_string(s, &mut out);
    out
}

fn write_string(s: &str, out: &mut String) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{08}' => out.push_str("\\b"),
            '\t' => out.push_str("\\t"),
            '\n' => out.push_str("\\n"),
            '\u{0c}' => out.push_str("\\f"),
            '\r' => out.push_str("\\r"),
            c if (c as u32) < 0x20 || c as u32 == 0x7f => {
                out.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

fn dump_value(v: &Value, indent: Option<usize>, level: usize, sort_keys: bool, out: &mut String) {
    let pad = |out: &mut String, l: usize| {
        if let Some(n) = indent {
            out.push('\n');
            for _ in 0..n * l {
                out.push(' ');
            }
        }
    };
    match v {
        Value::Null => out.push_str("null"),
        Value::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        Value::Number(n) => out.push_str(&n.fmt_jq()),
        Value::String(s) => write_string(s, out),
        Value::Array(items) => {
            if items.is_empty() {
                out.push_str("[]");
                return;
            }
            out.push('[');
            for (i, item) in items.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                pad(out, level + 1);
                dump_value(item, indent, level + 1, sort_keys, out);
            }
            pad(out, level);
            out.push(']');
        }
        Value::Object(entries) => {
            if entries.is_empty() {
                out.push_str("{}");
                return;
            }
            out.push('{');
            let mut order: Vec<usize> = (0..entries.len()).collect();
            if sort_keys {
                order.sort_by(|&a, &b| entries[a].0.as_bytes().cmp(entries[b].0.as_bytes()));
            }
            for (i, idx) in order.into_iter().enumerate() {
                let (k, item) = &entries[idx];
                if i > 0 {
                    out.push(',');
                }
                pad(out, level + 1);
                write_string(k, out);
                out.push(':');
                if indent.is_some() {
                    out.push(' ');
                }
                dump_value(item, indent, level + 1, sort_keys, out);
            }
            pad(out, level);
            out.push('}');
        }
    }
}

/// `jq -c`: compact JSON without trailing newline.
pub fn compact(v: &Value) -> String {
    let mut out = String::new();
    dump_value(v, None, 0, false, &mut out);
    out
}

/// `jq -Sc`: sorted-key compact JSON without trailing newline.
pub fn compact_sorted(v: &Value) -> String {
    let mut out = String::new();
    dump_value(v, None, 0, true, &mut out);
    out
}

/// `jq`: two-space pretty JSON without trailing newline.
pub fn pretty(v: &Value) -> String {
    let mut out = String::new();
    dump_value(v, Some(2), 0, false, &mut out);
    out
}

/// `jq -S`: sorted-key two-space pretty JSON without trailing newline.
pub fn pretty_sorted(v: &Value) -> String {
    let mut out = String::new();
    dump_value(v, Some(2), 0, true, &mut out);
    out
}

/// `jq -r`: string unquoted, anything else formatted with [`pretty`].
pub fn raw(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        other => pretty(other),
    }
}

/// `jq -rc`: string unquoted, anything else formatted with [`compact`].
pub fn raw_compact(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        other => compact(other),
    }
}

/// `jq -rS`: string unquoted, anything else formatted with [`pretty_sorted`].
pub fn raw_sorted(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        other => pretty_sorted(other),
    }
}

/// `tostring` / `"\(v)"`: string as itself, anything else as compact JSON.
pub fn tostring(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        other => compact(other),
    }
}

/// Alias for [`tostring`], matching string interpolation `"\(.)"`.
pub fn interpolate(v: &Value) -> String {
    tostring(v)
}

/// Formats `v` according to `opts` (without trailing newline).
pub fn format_value(v: &Value, opts: OutputOptions) -> String {
    if opts.raw {
        if let Value::String(s) = v {
            return s.clone();
        }
    }
    let indent = if opts.compact { None } else { Some(2) };
    let mut out = String::new();
    dump_value(v, indent, 0, opts.sort_keys, &mut out);
    out
}

/// Formats `v` for a jq 1.8 error message (matching `jv_dump_string_trunc` with
/// jq's 30-byte buffer: up to 29 bytes verbatim; longer strings keep up to 25
/// bytes on a UTF-8 char boundary + `..."`, arrays + `...]`, objects + `...}`,
/// numbers/others keep up to 26 bytes + `...`).
pub fn dump_trunc(v: &Value) -> String {
    let dumped = compact(v);
    if dumped.len() <= 29 {
        return dumped;
    }
    let (keep, suffix) = match v {
        Value::String(_) => (25, "...\""),
        Value::Array(_) => (25, "...]"),
        Value::Object(_) => (25, "...}"),
        _ => (26, "..."),
    };
    let mut cut = keep.min(dumped.len());
    while !dumped.is_char_boundary(cut) {
        cut -= 1;
    }
    format!("{}{}", &dumped[..cut], suffix)
}

/// `jq -sRr @uri`: percent-encodes every byte outside `[A-Za-z0-9\-_.~]`.
pub fn uri_encode(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len());
    for &b in bytes {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~') {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{:02X}", b));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::value::Number;

    #[test]
    fn escapes_and_sorts_like_jq_18() {
        assert_eq!(
            dump_string("a\u{7f}\u{01}\u{08}\u{0c}\t\n\r/\"\\é"),
            "\"a\\u007f\\u0001\\b\\f\\t\\n\\r/\\\"\\\\é\""
        );
        let obj = Value::object([("b".into(), Value::int(1)), ("a".into(), Value::int(2))]);
        assert_eq!(compact(&obj), "{\"b\":1,\"a\":2}");
        assert_eq!(compact_sorted(&obj), "{\"a\":2,\"b\":1}");
        assert_eq!(pretty_sorted(&obj), "{\n  \"a\": 2,\n  \"b\": 1\n}");
    }

    #[test]
    fn truncates_matching_jq_30_byte_buffer() {
        assert_eq!(
            dump_trunc(&Value::str("a".repeat(27))),
            format!("\"{}\"", "a".repeat(27))
        );
        assert_eq!(
            dump_trunc(&Value::str("a".repeat(28))),
            format!("\"{}...", "a".repeat(24)) + "\""
        );
        assert_eq!(
            dump_trunc(&Value::str(format!("{}\u{e9}aaaa", "a".repeat(23)))),
            format!("\"{}...", "a".repeat(23)) + "\""
        );
        assert_eq!(
            dump_trunc(&Value::str(format!(
                "{}\n{}",
                "a".repeat(23),
                "a".repeat(5)
            ))),
            format!("\"{}\\...\"", "a".repeat(23))
        );
        let num = Number::parse(&format!("1{}", "0".repeat(29))).unwrap();
        assert_eq!(
            dump_trunc(&Value::Number(num)),
            format!("1{}...", "0".repeat(25))
        );
        let arr = Value::Array(vec![Value::int(1); 15]);
        assert_eq!(dump_trunc(&arr), "[1,1,1,1,1,1,1,1,1,1,1,1,...]");
        let obj = Value::object([("k".repeat(25), Value::int(1))]);
        assert_eq!(
            dump_trunc(&obj),
            format!("{{\"\"{}...}}", "k".repeat(23)).replace("\"\"", "\"")
        );
    }

    #[test]
    fn uri_encode_unreserved_only() {
        assert_eq!(uri_encode(b"a b{\"=\"}~._-"), "a%20b%7B%22%3D%22%7D~._-");
    }
}
