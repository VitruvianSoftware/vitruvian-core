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

//! Streaming JSON parser matching jq 1.8 (`jv_parse.c`): multiple top-level
//! values, lenient number literals (`decNumber`), leading BOM handling,
//! jq UTF-8 lossy decoding, key-order-preserving objects (first position, last
//! value on duplicate keys), exact jq 1.8 parse-error diagnostics, and
//! `<stdin>:N` line numbers for runtime errors.

use std::collections::HashMap;

use crate::value::{Number, Value};

/// One item in a jq JSON input stream.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum StreamItem {
    /// A parsed JSON value and the 0-based line number jq reports in
    /// `jq: error (at <stdin>:N): ...` (count of newlines in input up to the
    /// end of the line holding the value's last byte).
    Value(Value, usize),
    /// A syntax error (without the `"jq: parse error: "` prefix or trailing newline).
    ParseError(String),
}

enum Container {
    Array {
        items: Vec<Value>,
        after_comma: bool,
    },
    Object {
        entries: Vec<(String, Value)>,
        index_by_key: HashMap<String, usize>,
        pending_key: Option<String>,
        after_comma: bool,
    },
}

struct StreamParser<'a> {
    bytes: &'a [u8],
    pos: usize,
    line: usize,
    col: usize,
    stack: Vec<Container>,
    next: Option<Value>,
    token_buf: Vec<u8>,
    in_string: bool,
    str_escaped: bool,
    str_buf: Vec<u8>,
    out: Vec<StreamItem>,
}

impl<'a> StreamParser<'a> {
    fn new(input: &'a [u8]) -> Self {
        let pos = if input.starts_with(b"\xef\xbb\xbf") {
            3
        } else {
            0
        };
        Self {
            bytes: input,
            pos,
            line: 1,
            col: 0,
            stack: Vec::new(),
            next: None,
            token_buf: Vec::new(),
            in_string: false,
            str_escaped: false,
            str_buf: Vec::new(),
            out: Vec::new(),
        }
    }

    fn err(&self, msg: &str) -> String {
        format!("{msg} at line {}, column {}", self.line, self.col)
    }

    fn err_eof(&self, msg: &str) -> String {
        format!("{msg} at EOF at line {}, column {}", self.line, self.col)
    }

    fn emit_top(&mut self, value: Value, end_exclusive: usize) {
        let line_no = line_after(self.bytes, end_exclusive);
        self.out.push(StreamItem::Value(value, line_no));
    }

    fn push_value(&mut self, v: Value) -> Result<(), String> {
        if self.next.is_some() {
            return Err(self.err("Expected separator between values"));
        }
        self.next = Some(v);
        Ok(())
    }

    fn flush_token(&mut self, at_eof: bool, end_exclusive: usize) -> Result<(), String> {
        if self.token_buf.is_empty() {
            return Ok(());
        }
        let val = parse_token(&self.token_buf).ok_or_else(|| {
            let what = classify_bad_token(&self.token_buf);
            if at_eof {
                self.err_eof(what)
            } else {
                self.err(what)
            }
        })?;
        self.token_buf.clear();
        self.push_value(val)?;
        if at_eof && self.stack.is_empty() {
            if let Some(v) = self.next.take() {
                self.emit_top(v, end_exclusive);
            }
        }
        Ok(())
    }

    fn maybe_emit_top(&mut self, end_exclusive: usize) {
        if self.stack.is_empty() {
            if let Some(v) = self.next.take() {
                self.emit_top(v, end_exclusive);
            }
        }
    }

    fn handle_open(&mut self, container: Container) -> Result<(), String> {
        if self.next.is_some() {
            return Err(self.err("Expected separator between values"));
        }
        self.stack.push(container);
        Ok(())
    }

    fn handle_close_array(&mut self, end_exclusive: usize) -> Result<(), String> {
        let Some(Container::Array {
            mut items,
            after_comma,
        }) = self.stack.pop()
        else {
            return Err(self.err("Unmatched ']'"));
        };
        if let Some(v) = self.next.take() {
            items.push(v);
        } else if after_comma {
            return Err(self.err("Expected another array element"));
        }
        let arr = Value::Array(items);
        if self.stack.is_empty() {
            self.emit_top(arr, end_exclusive);
        } else {
            self.next = Some(arr);
        }
        Ok(())
    }

    fn handle_close_object(&mut self, end_exclusive: usize) -> Result<(), String> {
        let next_val = self.next.take();
        match self.stack.pop() {
            None => Err(self.err("Unmatched '}'")),
            Some(Container::Array { .. }) => {
                if next_val.is_some() {
                    Err(self.err("Objects must consist of key:value pairs"))
                } else {
                    Err(self.err("Unmatched '}'"))
                }
            }
            Some(Container::Object {
                mut entries,
                mut index_by_key,
                pending_key,
                after_comma,
            }) => {
                match (pending_key, next_val) {
                    (Some(k), Some(v)) => insert_entry(&mut entries, &mut index_by_key, k, v),
                    (Some(_), None) => return Err(self.err("Unmatched '}'")),
                    (None, Some(_)) => {
                        return Err(self.err("Objects must consist of key:value pairs"));
                    }
                    (None, None) => {
                        if after_comma {
                            return Err(self.err("Expected another key-value pair"));
                        }
                    }
                }
                let obj = Value::Object(entries);
                if self.stack.is_empty() {
                    self.emit_top(obj, end_exclusive);
                } else {
                    self.next = Some(obj);
                }
                Ok(())
            }
        }
    }

    fn handle_colon(&mut self) -> Result<(), String> {
        let next_val = self.next.take();
        let Some(val) = next_val else {
            return Err(self.err("Expected string key before ':'"));
        };
        match self.stack.last_mut() {
            None => Err(self.err("Expected string key before ':'")),
            Some(Container::Array { .. }) => Err(self.err("':' not as part of an object")),
            Some(Container::Object { pending_key, .. }) => {
                if pending_key.is_some() {
                    return Err(self.err("':' not as part of an object"));
                }
                match val {
                    Value::String(k) => {
                        *pending_key = Some(k);
                        Ok(())
                    }
                    _ => Err(self.err("Object keys must be strings")),
                }
            }
        }
    }

    fn handle_comma(&mut self) -> Result<(), String> {
        let next_val = self.next.take();
        match self.stack.last_mut() {
            Some(Container::Array { items, after_comma }) => {
                let Some(v) = next_val else {
                    return Err(self.err("Expected value before ','"));
                };
                items.push(v);
                *after_comma = true;
                Ok(())
            }
            Some(Container::Object {
                entries,
                index_by_key,
                pending_key,
                after_comma,
            }) => match (pending_key.take(), next_val) {
                (Some(k), Some(v)) => {
                    insert_entry(entries, index_by_key, k, v);
                    *after_comma = true;
                    Ok(())
                }
                (None, Some(_)) => Err(self.err("Objects must consist of key:value pairs")),
                _ => Err(self.err("Expected value before ','")),
            },
            None => Err(self.err("Expected value before ','")),
        }
    }

    fn finish_string(&mut self) -> Result<(), String> {
        let decoded = decode_jq_string(&self.str_buf).map_err(|msg| self.err(msg))?;
        self.str_buf.clear();
        self.in_string = false;
        self.str_escaped = false;
        self.push_value(Value::String(decoded))
    }

    fn run(mut self) -> Vec<StreamItem> {
        let mut idx = self.pos;
        let len = self.bytes.len();
        while idx < len {
            let b = self.bytes[idx];
            if b == b'\n' {
                self.line += 1;
                self.col = 0;
            } else {
                self.col += 1;
            }

            if self.in_string {
                if b == b'\\' && !self.str_escaped {
                    self.str_buf.push(b);
                    self.str_escaped = true;
                } else if b == b'"' && !self.str_escaped {
                    if let Err(msg) = self.finish_string() {
                        self.out.push(StreamItem::ParseError(msg));
                        return self.out;
                    }
                    // Top-level string stays buffered in `self.next` until whitespace,
                    // next value, or EOF — wait: what about `"a"]`?
                    // Look at `b'"a"]'`: jq yielded `"a"` THEN errored `Unmatched ']'`!
                    // Because in jq, `"a"` has `stack.is_empty()` so it emits immediately!
                    self.maybe_emit_top(idx + 1);
                } else {
                    self.str_buf.push(b);
                    self.str_escaped = false;
                }
                idx += 1;
                continue;
            }

            let step: Result<(), String> = match b {
                b' ' | b'\t' | b'\r' | b'\n' => {
                    let res = self.flush_token(false, idx);
                    if res.is_ok() {
                        self.maybe_emit_top(idx);
                    }
                    res
                }
                b'[' => self.flush_token(false, idx).and_then(|()| {
                    self.maybe_emit_top(idx);
                    self.handle_open(Container::Array {
                        items: Vec::new(),
                        after_comma: false,
                    })
                }),
                b'{' => self.flush_token(false, idx).and_then(|()| {
                    self.maybe_emit_top(idx);
                    self.handle_open(Container::Object {
                        entries: Vec::new(),
                        index_by_key: HashMap::new(),
                        pending_key: None,
                        after_comma: false,
                    })
                }),
                b'"' => self.flush_token(false, idx).map(|()| {
                    self.maybe_emit_top(idx);
                    self.in_string = true;
                    self.str_escaped = false;
                    self.str_buf.clear();
                }),
                b']' => self
                    .flush_token(false, idx)
                    .and_then(|()| self.handle_close_array(idx + 1)),
                b'}' => self
                    .flush_token(false, idx)
                    .and_then(|()| self.handle_close_object(idx + 1)),
                b':' => self
                    .flush_token(false, idx)
                    .and_then(|()| self.handle_colon()),
                b',' => self
                    .flush_token(false, idx)
                    .and_then(|()| self.handle_comma()),
                _ => {
                    // Any non-whitespace/non-structural byte after a buffered value inside a
                    // container (e.g. `[1, 2 3]` or `{"a":1 "b":2}`): token_buf collects `3`
                    // and `flush_token` reports `Expected separator between values`.
                    self.token_buf.push(b);
                    Ok(())
                }
            };

            if let Err(msg) = step {
                self.out.push(StreamItem::ParseError(msg));
                return self.out;
            }
            idx += 1;
        }

        if self.in_string {
            self.out
                .push(StreamItem::ParseError(self.err_eof("Unfinished string")));
            return self.out;
        }
        if let Err(msg) = self.flush_token(true, len) {
            self.out.push(StreamItem::ParseError(msg));
            return self.out;
        }
        if !self.stack.is_empty() {
            self.out
                .push(StreamItem::ParseError(self.err_eof("Unfinished JSON term")));
            return self.out;
        }
        if let Some(v) = self.next.take() {
            self.emit_top(v, len);
        }
        self.out
    }
}

fn insert_entry(
    entries: &mut Vec<(String, Value)>,
    index_by_key: &mut HashMap<String, usize>,
    key: String,
    value: Value,
) {
    if let Some(&idx) = index_by_key.get(&key) {
        entries[idx].1 = value;
    } else {
        index_by_key.insert(key.clone(), entries.len());
        entries.push((key, value));
    }
}

fn parse_token(tok: &[u8]) -> Option<Value> {
    match tok {
        b"true" => Some(Value::Bool(true)),
        b"false" => Some(Value::Bool(false)),
        b"null" => Some(Value::Null),
        _ => {
            let s = std::str::from_utf8(tok).ok()?;
            Number::parse(s).map(Value::Number)
        }
    }
}

fn classify_bad_token(tok: &[u8]) -> &'static str {
    if tok.starts_with(b"t") || tok.starts_with(b"f") || tok.starts_with(b"nu") {
        "Invalid literal"
    } else if tok.starts_with(b"'") {
        "Invalid string literal; expected \", but got '"
    } else {
        "Invalid numeric literal"
    }
}

/// Counts newlines up to the end of the line holding the value's last byte
/// (matching jq's line-at-a-time parser feed for `<stdin>:N`).
fn line_after(bytes: &[u8], end_exclusive: usize) -> usize {
    let from = end_exclusive.saturating_sub(1).min(bytes.len());
    match bytes[from..].iter().position(|&b| b == b'\n') {
        Some(rel) => bytes[..from + rel + 1]
            .iter()
            .filter(|&&b| b == b'\n')
            .count(),
        None => bytes.iter().filter(|&&b| b == b'\n').count(),
    }
}

/// Decodes raw bytes inside `"..."` according to jq 1.8's string rules.
fn decode_jq_string(raw: &[u8]) -> Result<String, &'static str> {
    let mut out = String::with_capacity(raw.len());
    let mut i = 0;
    while i < raw.len() {
        let b = raw[i];
        if b < 0x20 {
            return Err(
                "Invalid string: control characters from U+0000 through U+001F must be escaped",
            );
        }
        if b == b'\\' {
            i += 1;
            let esc = *raw.get(i).ok_or("Invalid escape")?;
            i += 1;
            match esc {
                b'"' => out.push('"'),
                b'\\' => out.push('\\'),
                b'/' => out.push('/'),
                b'b' => out.push('\u{08}'),
                b'f' => out.push('\u{0c}'),
                b'n' => out.push('\n'),
                b'r' => out.push('\r'),
                b't' => out.push('\t'),
                b'u' => {
                    let hi = parse_hex4(raw, &mut i)?;
                    if (0xD800..=0xDBFF).contains(&hi) {
                        if raw.get(i..i + 2) != Some(b"\\u") {
                            return Err("Invalid \\uXXXX\\uXXXX surrogate pair escape");
                        }
                        i += 2;
                        let lo = parse_hex4_surrogate(raw, &mut i)?;
                        if !(0xDC00..=0xDFFF).contains(&lo) {
                            return Err("Invalid \\uXXXX\\uXXXX surrogate pair escape");
                        }
                        let cp = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00);
                        out.push(
                            char::from_u32(cp)
                                .ok_or("Invalid \\uXXXX\\uXXXX surrogate pair escape")?,
                        );
                    } else if (0xDC00..=0xDFFF).contains(&hi) {
                        out.push('\u{fffd}');
                    } else {
                        out.push(char::from_u32(hi).unwrap_or('\u{fffd}'));
                    }
                }
                _ => return Err("Invalid escape"),
            }
            continue;
        }
        let (ch, next_i) = decode_utf8_jq(raw, i);
        out.push(ch);
        i = next_i;
    }
    Ok(out)
}

fn parse_hex4_inner(
    raw: &[u8],
    i: &mut usize,
    short_err: &'static str,
    hex_err: &'static str,
) -> Result<u32, &'static str> {
    let end = *i + 4;
    if end > raw.len() {
        return Err(short_err);
    }
    let slice = &raw[*i..end];
    if !slice.iter().all(|b| b.is_ascii_hexdigit()) {
        return Err(hex_err);
    }
    let s = std::str::from_utf8(slice).map_err(|_| hex_err)?;
    let val = u32::from_str_radix(s, 16).map_err(|_| hex_err)?;
    *i = end;
    Ok(val)
}

fn parse_hex4(raw: &[u8], i: &mut usize) -> Result<u32, &'static str> {
    parse_hex4_inner(
        raw,
        i,
        "Invalid \\uXXXX escape",
        "Invalid characters in \\uXXXX escape",
    )
}

fn parse_hex4_surrogate(raw: &[u8], i: &mut usize) -> Result<u32, &'static str> {
    parse_hex4_inner(
        raw,
        i,
        "Invalid \\uXXXX\\uXXXX surrogate pair escape",
        "Invalid \\uXXXX\\uXXXX surrogate pair escape",
    )
}

/// Decodes one UTF-8 character the way jq's `jvp_utf8_next` does:
/// consumes up to the declared sequence length while continuation bytes match
/// `0b10xxxxxx`, returning `U+FFFD` for overlong encodings, surrogates, or
/// invalid bytes.
fn decode_utf8_jq(raw: &[u8], start: usize) -> (char, usize) {
    let b0 = raw[start];
    if b0 < 0x80 {
        return (b0 as char, start + 1);
    }
    let (expected_len, init_cp, min_cp) = match b0 {
        0xC2..=0xDF => (2, (b0 & 0x1F) as u32, 0x80),
        0xE0..=0xEF => (3, (b0 & 0x0F) as u32, 0x800),
        0xF0..=0xF4 => (4, (b0 & 0x07) as u32, 0x10000),
        _ => return ('\u{fffd}', start + 1),
    };
    let mut cp = init_cp;
    let mut i = start + 1;
    let mut count = 1;
    while count < expected_len && i < raw.len() {
        let b = raw[i];
        if (b & 0xC0) != 0x80 {
            return ('\u{fffd}', i);
        }
        cp = (cp << 6) | (b & 0x3F) as u32;
        i += 1;
        count += 1;
    }
    if count < expected_len || cp < min_cp || cp > 0x10FFFF {
        return ('\u{fffd}', i);
    }
    match char::from_u32(cp) {
        Some(ch) => (ch, i),
        None => ('\u{fffd}', i),
    }
}

/// Parses a stream of JSON texts the way jq 1.8 reads stdin.
pub fn parse_stream(input: &[u8]) -> Vec<StreamItem> {
    StreamParser::new(input).run()
}

/// Convenience wrapper over [`parse_stream`] for `&str`.
pub fn parse_stream_str(input: &str) -> Vec<StreamItem> {
    parse_stream(input.as_bytes())
}

/// Parses a single JSON value from `input`, returning an error on empty input,
/// trailing values, or parse errors.
pub fn parse_one(input: &[u8]) -> Result<Value, String> {
    let mut items = parse_stream(input).into_iter();
    match items.next() {
        None => Err("empty JSON input".to_string()),
        Some(StreamItem::ParseError(msg)) => Err(msg),
        Some(StreamItem::Value(v, _)) => match items.next() {
            None => Ok(v),
            Some(StreamItem::ParseError(msg)) => Err(msg),
            Some(StreamItem::Value(_, _)) => Err("unexpected trailing JSON value".to_string()),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::format::compact;

    #[test]
    fn preserves_key_order_and_last_duplicate_value() {
        let v = parse_one(br#"{"b":1,"a":2,"b":3}"#).unwrap();
        assert_eq!(compact(&v), r#"{"b":3,"a":2}"#);
    }

    #[test]
    fn stream_bom_numbers_and_parse_errors() {
        let items = parse_stream(b"\xef\xbb\xbf{\"x\":1}\n[1,2,]");
        assert_eq!(items.len(), 2);
        assert!(matches!(items[0], StreamItem::Value(_, 1)));
        assert_eq!(
            items[1],
            StreamItem::ParseError("Expected another array element at line 2, column 6".into())
        );

        let items = parse_stream(b"\"a\nb\"");
        assert_eq!(
            items,
            vec![StreamItem::ParseError(
                "Invalid string: control characters from U+0000 through U+001F must be escaped at line 2, column 2".into()
            )]
        );
    }

    #[test]
    fn jq_utf8_replacement_matches_jq() {
        assert_eq!(
            parse_one(b"\"\xc0\xaf\"").unwrap(),
            Value::str("\u{fffd}\u{fffd}")
        );
        assert_eq!(
            parse_one(b"\"\xf4\x90\x80\x80\"").unwrap(),
            Value::str("\u{fffd}")
        );
        assert_eq!(
            parse_one(b"\"\xed\xa0\x80\"").unwrap(),
            Value::str("\u{fffd}")
        );
        assert_eq!(
            parse_one(b"\"\xf1\x80A\x80\"").unwrap(),
            Value::str("\u{fffd}A\u{fffd}")
        );
    }

    #[test]
    fn colon_and_key_errors_match_jq_182() {
        let err_cases: &[(&[u8], &str)] = &[
            (b":", "Expected string key before ':' at line 1, column 1"),
            (b"1:2", "Expected string key before ':' at line 1, column 2"),
            (
                b"true:1",
                "Expected string key before ':' at line 1, column 5",
            ),
            (
                b"false:1",
                "Expected string key before ':' at line 1, column 6",
            ),
            (
                b"null:1",
                "Expected string key before ':' at line 1, column 5",
            ),
            (b"[:]", "Expected string key before ':' at line 1, column 2"),
            (b"[1:2]", "':' not as part of an object at line 1, column 3"),
            (
                b"[\"a\":1]",
                "':' not as part of an object at line 1, column 5",
            ),
            (
                b"{:1}",
                "Expected string key before ':' at line 1, column 2",
            ),
            (
                b"{\"a\"::1}",
                "Expected string key before ':' at line 1, column 6",
            ),
            (
                b"{\"a\":1,:2}",
                "Expected string key before ':' at line 1, column 8",
            ),
            (
                b"{\"a\":1,\"b\"::2}",
                "Expected string key before ':' at line 1, column 12",
            ),
            (
                b"{\"a\":1:2}",
                "':' not as part of an object at line 1, column 7",
            ),
            (
                b"{\"a\":\"b\":1}",
                "':' not as part of an object at line 1, column 9",
            ),
            (b"{1:2}", "Object keys must be strings at line 1, column 3"),
            (
                b"{true:1}",
                "Object keys must be strings at line 1, column 6",
            ),
            (
                b"{\"a\":1,null:2}",
                "Object keys must be strings at line 1, column 12",
            ),
        ];
        for &(inp, want_err) in err_cases {
            assert_eq!(
                parse_stream(inp),
                vec![StreamItem::ParseError(want_err.to_string())],
                "input={:?}",
                String::from_utf8_lossy(inp)
            );
        }

        assert_eq!(
            parse_stream(b"1 : 2"),
            vec![
                StreamItem::Value(Value::int(1), 0),
                StreamItem::ParseError("Expected string key before ':' at line 1, column 3".into()),
            ]
        );
        assert_eq!(
            parse_stream(b"\"a\":1"),
            vec![
                StreamItem::Value(Value::str("a"), 0),
                StreamItem::ParseError("Expected string key before ':' at line 1, column 4".into()),
            ]
        );
    }

    #[test]
    fn mismatched_bracket_errors_match_jq_182() {
        let cases: &[(&[u8], &str)] = &[
            (b"[}", "Unmatched '}' at line 1, column 2"),
            (b"{]", "Unmatched ']' at line 1, column 2"),
            (
                b"[1}",
                "Objects must consist of key:value pairs at line 1, column 3",
            ),
            (b"[1,}", "Unmatched '}' at line 1, column 4"),
            (
                b"[1,2}",
                "Objects must consist of key:value pairs at line 1, column 5",
            ),
            (
                b"[\"a\"}",
                "Objects must consist of key:value pairs at line 1, column 5",
            ),
            (b"{\"a\"]", "Unmatched ']' at line 1, column 5"),
            (b"{\"a\":]", "Unmatched ']' at line 1, column 6"),
            (b"{\"a\":1]", "Unmatched ']' at line 1, column 7"),
            (b"{\"a\":1,]", "Unmatched ']' at line 1, column 8"),
            (b"[{]", "Unmatched ']' at line 1, column 3"),
            (b"{\"a\":[}", "Unmatched '}' at line 1, column 7"),
            (
                b"{\"a\":[1}",
                "Objects must consist of key:value pairs at line 1, column 8",
            ),
            (b"1}", "Unmatched '}' at line 1, column 2"),
            (
                b"[\n1\n}",
                "Objects must consist of key:value pairs at line 3, column 1",
            ),
        ];
        for &(inp, want_err) in cases {
            assert_eq!(
                parse_stream(inp),
                vec![StreamItem::ParseError(want_err.to_string())],
                "input={:?}",
                String::from_utf8_lossy(inp)
            );
        }
    }
}
