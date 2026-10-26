// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

pub mod auth;
pub mod channel_allowlist;
pub mod config;
pub mod dispatch;
pub mod http_transport;
pub mod permalink;
pub mod slack_client;
pub mod tools;

pub mod json {
    use std::fmt;

    #[derive(Clone, PartialEq)]
    pub enum JsonValue {
        Null,
        Bool(bool),
        Number(f64),
        String(String),
        Array(Vec<JsonValue>),
        Object(Vec<(String, JsonValue)>),
    }

    impl fmt::Debug for JsonValue {
        fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            write!(f, "{}", self.to_json_string())
        }
    }

    impl fmt::Display for JsonValue {
        fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            write!(f, "{}", self.to_json_string())
        }
    }

    impl JsonValue {
        pub fn str(s: &str) -> Self {
            JsonValue::String(s.to_string())
        }

        pub fn number(n: f64) -> Self {
            JsonValue::Number(n)
        }

        pub fn boolean(b: bool) -> Self {
            JsonValue::Bool(b)
        }

        pub fn object(entries: Vec<(&str, JsonValue)>) -> Self {
            JsonValue::Object(
                entries
                    .into_iter()
                    .map(|(k, v)| (k.to_string(), v))
                    .collect(),
            )
        }

        pub fn empty_object() -> Self {
            JsonValue::Object(Vec::new())
        }

        pub fn array(items: Vec<JsonValue>) -> Self {
            JsonValue::Array(items)
        }

        pub fn is_null(&self) -> bool {
            matches!(self, JsonValue::Null)
        }

        pub fn as_bool(&self) -> Option<bool> {
            match self {
                JsonValue::Bool(b) => Some(*b),
                _ => None,
            }
        }

        pub fn as_f64(&self) -> Option<f64> {
            match self {
                JsonValue::Number(n) => Some(*n),
                _ => None,
            }
        }

        pub fn as_i64(&self) -> Option<i64> {
            match self {
                JsonValue::Number(n) if n.is_finite() => Some(*n as i64),
                _ => None,
            }
        }

        pub fn as_u64(&self) -> Option<u64> {
            match self {
                JsonValue::Number(n) if n.is_finite() && *n >= 0.0 => Some(*n as u64),
                _ => None,
            }
        }

        pub fn as_str(&self) -> Option<&str> {
            match self {
                JsonValue::String(s) => Some(s.as_str()),
                _ => None,
            }
        }

        pub fn as_array(&self) -> Option<&Vec<JsonValue>> {
            match self {
                JsonValue::Array(a) => Some(a),
                _ => None,
            }
        }

        pub fn as_object(&self) -> Option<&Vec<(String, JsonValue)>> {
            match self {
                JsonValue::Object(o) => Some(o),
                _ => None,
            }
        }

        pub fn as_object_mut(&mut self) -> Option<&mut Vec<(String, JsonValue)>> {
            match self {
                JsonValue::Object(o) => Some(o),
                _ => None,
            }
        }

        pub fn get(&self, key: &str) -> Option<&JsonValue> {
            match self {
                JsonValue::Object(entries) => {
                    entries.iter().find(|(k, _)| k == key).map(|(_, v)| v)
                }
                _ => None,
            }
        }

        pub fn contains_key(&self, key: &str) -> bool {
            self.get(key).is_some()
        }

        pub fn insert(&mut self, key: impl Into<String>, value: JsonValue) {
            let key = key.into();
            if let JsonValue::Object(entries) = self {
                if let Some(existing) = entries.iter_mut().find(|(k, _)| *k == key) {
                    existing.1 = value;
                } else {
                    entries.push((key, value));
                }
            }
        }

        pub fn to_json_string(&self) -> String {
            let mut out = String::new();
            self.write_compact(&mut out);
            out
        }

        pub fn to_json_pretty(&self) -> String {
            let mut out = String::new();
            self.write_pretty(&mut out, 0);
            out
        }

        pub fn to_string_pretty(&self) -> String {
            self.to_json_pretty()
        }

        fn write_compact(&self, out: &mut String) {
            match self {
                JsonValue::Null => out.push_str("null"),
                JsonValue::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
                JsonValue::Number(n) => {
                    if !n.is_finite() {
                        out.push_str("null");
                    } else if n.fract() == 0.0 && *n >= (i64::MIN as f64) && *n <= (i64::MAX as f64)
                    {
                        out.push_str(&(*n as i64).to_string());
                    } else {
                        out.push_str(&n.to_string());
                    }
                }
                JsonValue::String(s) => write_escaped_string(out, s),
                JsonValue::Array(items) => {
                    out.push('[');
                    for (i, item) in items.iter().enumerate() {
                        if i > 0 {
                            out.push(',');
                        }
                        item.write_compact(out);
                    }
                    out.push(']');
                }
                JsonValue::Object(entries) => {
                    out.push('{');
                    for (i, (k, v)) in entries.iter().enumerate() {
                        if i > 0 {
                            out.push(',');
                        }
                        write_escaped_string(out, k);
                        out.push(':');
                        v.write_compact(out);
                    }
                    out.push('}');
                }
            }
        }

        fn write_pretty(&self, out: &mut String, indent: usize) {
            let pad = "  ".repeat(indent);
            let inner_pad = "  ".repeat(indent + 1);
            match self {
                JsonValue::Array(items) if !items.is_empty() => {
                    out.push_str("[\n");
                    for (i, item) in items.iter().enumerate() {
                        out.push_str(&inner_pad);
                        item.write_pretty(out, indent + 1);
                        if i + 1 < items.len() {
                            out.push(',');
                        }
                        out.push('\n');
                    }
                    out.push_str(&pad);
                    out.push(']');
                }
                JsonValue::Object(entries) if !entries.is_empty() => {
                    out.push_str("{\n");
                    for (i, (k, v)) in entries.iter().enumerate() {
                        out.push_str(&inner_pad);
                        write_escaped_string(out, k);
                        out.push_str(": ");
                        v.write_pretty(out, indent + 1);
                        if i + 1 < entries.len() {
                            out.push(',');
                        }
                        out.push('\n');
                    }
                    out.push_str(&pad);
                    out.push('}');
                }
                _ => self.write_compact(out),
            }
        }

        pub fn parse(input: &str) -> Result<JsonValue, String> {
            let mut parser = Parser {
                bytes: input.as_bytes(),
                pos: 0,
            };
            let val = parser.parse_value()?;
            parser.skip_ws();
            if parser.pos != parser.bytes.len() {
                return Err(format!("Unexpected trailing data at byte {}", parser.pos));
            }
            Ok(val)
        }
    }

    impl From<&str> for JsonValue {
        fn from(s: &str) -> Self {
            JsonValue::String(s.to_string())
        }
    }

    impl From<String> for JsonValue {
        fn from(s: String) -> Self {
            JsonValue::String(s)
        }
    }

    impl From<bool> for JsonValue {
        fn from(b: bool) -> Self {
            JsonValue::Bool(b)
        }
    }

    impl From<i64> for JsonValue {
        fn from(n: i64) -> Self {
            JsonValue::Number(n as f64)
        }
    }

    impl From<usize> for JsonValue {
        fn from(n: usize) -> Self {
            JsonValue::Number(n as f64)
        }
    }

    impl From<f64> for JsonValue {
        fn from(n: f64) -> Self {
            JsonValue::Number(n)
        }
    }

    fn write_escaped_string(out: &mut String, s: &str) {
        out.push('"');
        for ch in s.chars() {
            match ch {
                '"' => out.push_str("\\\""),
                '\\' => out.push_str("\\\\"),
                '\n' => out.push_str("\\n"),
                '\r' => out.push_str("\\r"),
                '\t' => out.push_str("\\t"),
                '\u{08}' => out.push_str("\\b"),
                '\u{0C}' => out.push_str("\\f"),
                c if (c as u32) < 0x20 => {
                    out.push_str(&format!("\\u{:04x}", c as u32));
                }
                c => out.push(c),
            }
        }
        out.push('"');
    }

    struct Parser<'a> {
        bytes: &'a [u8],
        pos: usize,
    }

    impl<'a> Parser<'a> {
        fn skip_ws(&mut self) {
            while self.pos < self.bytes.len() {
                match self.bytes[self.pos] {
                    b' ' | b'\t' | b'\n' | b'\r' => self.pos += 1,
                    _ => break,
                }
            }
        }

        fn peek(&self) -> Option<u8> {
            self.bytes.get(self.pos).copied()
        }

        fn parse_value(&mut self) -> Result<JsonValue, String> {
            self.skip_ws();
            match self.peek() {
                Some(b'n') => self.parse_literal(b"null", JsonValue::Null),
                Some(b't') => self.parse_literal(b"true", JsonValue::Bool(true)),
                Some(b'f') => self.parse_literal(b"false", JsonValue::Bool(false)),
                Some(b'"') => Ok(JsonValue::String(self.parse_string()?)),
                Some(b'[') => self.parse_array(),
                Some(b'{') => self.parse_object(),
                Some(b'-') | Some(b'0'..=b'9') => self.parse_number(),
                Some(b) => Err(format!(
                    "Unexpected byte '{}' at position {}",
                    b as char, self.pos
                )),
                None => Err("Unexpected end of JSON input".to_string()),
            }
        }

        fn parse_literal(&mut self, expected: &[u8], val: JsonValue) -> Result<JsonValue, String> {
            if self.bytes[self.pos..].starts_with(expected) {
                self.pos += expected.len();
                Ok(val)
            } else {
                Err(format!("Invalid literal at position {}", self.pos))
            }
        }

        fn parse_string(&mut self) -> Result<String, String> {
            if self.peek() != Some(b'"') {
                return Err(format!("Expected '\"' at position {}", self.pos));
            }
            self.pos += 1;
            let mut out = String::new();
            while self.pos < self.bytes.len() {
                let b = self.bytes[self.pos];
                if b == b'"' {
                    self.pos += 1;
                    return Ok(out);
                } else if b == b'\\' {
                    self.pos += 1;
                    if self.pos >= self.bytes.len() {
                        return Err("Unterminated escape sequence".to_string());
                    }
                    let esc = self.bytes[self.pos];
                    self.pos += 1;
                    match esc {
                        b'"' => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'/' => out.push('/'),
                        b'b' => out.push('\u{08}'),
                        b'f' => out.push('\u{0C}'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => {
                            if self.pos + 4 > self.bytes.len() {
                                return Err("Invalid unicode escape".to_string());
                            }
                            let hex = std::str::from_utf8(&self.bytes[self.pos..self.pos + 4])
                                .map_err(|_| "Invalid hex".to_string())?;
                            let code = u32::from_str_radix(hex, 16)
                                .map_err(|_| "Invalid hex digits".to_string())?;
                            self.pos += 4;
                            if let Some(ch) = char::from_u32(code) {
                                out.push(ch);
                            } else {
                                out.push('\u{FFFD}');
                            }
                        }
                        other => out.push(other as char),
                    }
                } else {
                    let rest = &self.bytes[self.pos..];
                    let s =
                        std::str::from_utf8(rest).map_err(|_| "Invalid UTF-8 in JSON string")?;
                    let ch = s.chars().next().unwrap();
                    out.push(ch);
                    self.pos += ch.len_utf8();
                }
            }
            Err("Unterminated JSON string".to_string())
        }

        fn parse_number(&mut self) -> Result<JsonValue, String> {
            let start = self.pos;
            if self.peek() == Some(b'-') {
                self.pos += 1;
            }
            while matches!(self.peek(), Some(b'0'..=b'9')) {
                self.pos += 1;
            }
            if self.peek() == Some(b'.') {
                self.pos += 1;
                while matches!(self.peek(), Some(b'0'..=b'9')) {
                    self.pos += 1;
                }
            }
            if matches!(self.peek(), Some(b'e' | b'E')) {
                self.pos += 1;
                if matches!(self.peek(), Some(b'+' | b'-')) {
                    self.pos += 1;
                }
                while matches!(self.peek(), Some(b'0'..=b'9')) {
                    self.pos += 1;
                }
            }
            let s = std::str::from_utf8(&self.bytes[start..self.pos])
                .map_err(|_| "Invalid UTF-8 in number".to_string())?;
            let n: f64 = s
                .parse()
                .map_err(|_| format!("Invalid number '{s}' at {start}"))?;
            Ok(JsonValue::Number(n))
        }

        fn parse_array(&mut self) -> Result<JsonValue, String> {
            self.pos += 1; // '['
            self.skip_ws();
            let mut items = Vec::new();
            if self.peek() == Some(b']') {
                self.pos += 1;
                return Ok(JsonValue::Array(items));
            }
            loop {
                items.push(self.parse_value()?);
                self.skip_ws();
                match self.peek() {
                    Some(b',') => {
                        self.pos += 1;
                    }
                    Some(b']') => {
                        self.pos += 1;
                        return Ok(JsonValue::Array(items));
                    }
                    _ => return Err(format!("Expected ',' or ']' at position {}", self.pos)),
                }
            }
        }

        fn parse_object(&mut self) -> Result<JsonValue, String> {
            self.pos += 1; // '{'
            self.skip_ws();
            let mut entries = Vec::new();
            if self.peek() == Some(b'}') {
                self.pos += 1;
                return Ok(JsonValue::Object(entries));
            }
            loop {
                self.skip_ws();
                let key = self.parse_string()?;
                self.skip_ws();
                if self.peek() != Some(b':') {
                    return Err(format!("Expected ':' at position {}", self.pos));
                }
                self.pos += 1;
                let val = self.parse_value()?;
                entries.push((key, val));
                self.skip_ws();
                match self.peek() {
                    Some(b',') => {
                        self.pos += 1;
                    }
                    Some(b'}') => {
                        self.pos += 1;
                        return Ok(JsonValue::Object(entries));
                    }
                    _ => return Err(format!("Expected ',' or '}}' at position {}", self.pos)),
                }
            }
        }
    }
}

pub mod base64 {
    const STD_ALPHABET: &[u8; 64] =
        b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const URL_ALPHABET: &[u8; 64] =
        b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

    pub fn encode(data: &[u8]) -> String {
        encode_with(data, STD_ALPHABET, true)
    }

    pub fn encode_url(data: &[u8]) -> String {
        encode_with(data, URL_ALPHABET, false)
    }

    fn encode_with(data: &[u8], alphabet: &[u8; 64], pad: bool) -> String {
        let mut out = String::with_capacity((data.len() + 2) / 3 * 4);
        for chunk in data.chunks(3) {
            let b0 = chunk[0] as u32;
            let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
            let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
            let triple = (b0 << 16) | (b1 << 8) | b2;

            out.push(alphabet[((triple >> 18) & 0x3F) as usize] as char);
            out.push(alphabet[((triple >> 12) & 0x3F) as usize] as char);
            if chunk.len() > 1 {
                out.push(alphabet[((triple >> 6) & 0x3F) as usize] as char);
            } else if pad {
                out.push('=');
            }
            if chunk.len() > 2 {
                out.push(alphabet[(triple & 0x3F) as usize] as char);
            } else if pad {
                out.push('=');
            }
        }
        out
    }

    pub fn decode(input: &str) -> Result<Vec<u8>, String> {
        let clean: Vec<u8> = input
            .bytes()
            .filter(|b| !matches!(b, b'=' | b'\r' | b'\n' | b' ' | b'\t'))
            .collect();
        let mut out = Vec::with_capacity(clean.len() * 3 / 4);
        for chunk in clean.chunks(4) {
            if chunk.len() == 1 {
                return Err("Invalid base64 length".to_string());
            }
            let mut vals = [0u32; 4];
            for (i, &b) in chunk.iter().enumerate() {
                vals[i] = match b {
                    b'A'..=b'Z' => (b - b'A') as u32,
                    b'a'..=b'z' => (b - b'a' + 26) as u32,
                    b'0'..=b'9' => (b - b'0' + 52) as u32,
                    b'+' | b'-' => 62,
                    b'/' | b'_' => 63,
                    _ => return Err(format!("Invalid base64 byte: {}", b as char)),
                };
            }
            let triple = (vals[0] << 18) | (vals[1] << 12) | (vals[2] << 6) | vals[3];
            out.push(((triple >> 16) & 0xFF) as u8);
            if chunk.len() > 2 {
                out.push(((triple >> 8) & 0xFF) as u8);
            }
            if chunk.len() > 3 {
                out.push((triple & 0xFF) as u8);
            }
        }
        Ok(out)
    }
}

pub mod url {
    #[derive(Debug, Clone, PartialEq, Eq)]
    pub struct ParsedUrl {
        pub protocol: String,
        pub hostname: String,
        pub port: Option<u16>,
        pub pathname: String,
        pub search: String,
        pub query_params: Vec<(String, String)>,
    }

    impl ParsedUrl {
        pub fn parse(input: &str) -> Result<Self, String> {
            let (scheme, rest) = input
                .split_once("://")
                .ok_or_else(|| "missing scheme".to_string())?;
            if scheme.is_empty() {
                return Err("empty scheme".to_string());
            }
            let protocol = format!("{}:", scheme.to_ascii_lowercase());
            let rest_no_frag = match rest.split_once('#') {
                Some((before, _)) => before,
                None => rest,
            };
            let (authority, path_and_query) = match rest_no_frag.find('/') {
                Some(idx) => (&rest_no_frag[..idx], &rest_no_frag[idx..]),
                None => match rest_no_frag.find('?') {
                    Some(idx) => (&rest_no_frag[..idx], &rest_no_frag[idx..]),
                    None => (rest_no_frag, "/"),
                },
            };
            if authority.is_empty() || authority.contains('@') || authority.contains(' ') {
                return Err("invalid authority".to_string());
            }
            let (hostname, port) = if let Some((h, p)) = authority.rsplit_once(':') {
                if !authority.starts_with('[') {
                    let parsed_port: u16 = p.parse().map_err(|_| "invalid port".to_string())?;
                    (h.to_ascii_lowercase(), Some(parsed_port))
                } else {
                    (authority.to_ascii_lowercase(), None)
                }
            } else {
                (authority.to_ascii_lowercase(), None)
            };
            if hostname.is_empty() {
                return Err("empty hostname".to_string());
            }

            let (raw_path, search, query_str) = match path_and_query.split_once('?') {
                Some((p, q)) => (
                    if p.is_empty() { "/" } else { p },
                    if q.is_empty() {
                        String::new()
                    } else {
                        format!("?{q}")
                    },
                    q,
                ),
                None => (path_and_query, String::new(), ""),
            };

            let mut query_params = Vec::new();
            if !query_str.is_empty() {
                for pair in query_str.split('&') {
                    if pair.is_empty() {
                        continue;
                    }
                    let (k, v) = match pair.split_once('=') {
                        Some((k, v)) => (percent_decode(k), percent_decode(v)),
                        None => (percent_decode(pair), String::new()),
                    };
                    query_params.push((k, v));
                }
            }

            Ok(ParsedUrl {
                protocol,
                hostname,
                port,
                pathname: raw_path.to_string(),
                search,
                query_params,
            })
        }

        pub fn query_get(&self, key: &str) -> Option<&str> {
            self.query_params
                .iter()
                .find(|(k, _)| k == key)
                .map(|(_, v)| v.as_str())
        }
    }

    pub fn percent_encode(input: &str) -> String {
        let mut out = String::new();
        for b in input.bytes() {
            match b {
                b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'*' => {
                    out.push(b as char);
                }
                b' ' => out.push('+'),
                _ => out.push_str(&format!("%{:02X}", b)),
            }
        }
        out
    }

    pub fn percent_decode(input: &str) -> String {
        let bytes = input.as_bytes();
        let mut out = Vec::with_capacity(bytes.len());
        let mut i = 0;
        while i < bytes.len() {
            if bytes[i] == b'+' {
                out.push(b' ');
                i += 1;
            } else if bytes[i] == b'%' && i + 2 < bytes.len() {
                if let Ok(hex) = std::str::from_utf8(&bytes[i + 1..i + 3]) {
                    if let Ok(val) = u8::from_str_radix(hex, 16) {
                        out.push(val);
                        i += 3;
                        continue;
                    }
                }
                out.push(bytes[i]);
                i += 1;
            } else {
                out.push(bytes[i]);
                i += 1;
            }
        }
        String::from_utf8_lossy(&out).into_owned()
    }

    pub fn encode_query_params(params: &[(&str, String)]) -> String {
        let mut parts = Vec::new();
        for (k, v) in params {
            parts.push(format!("{}={}", percent_encode(k), percent_encode(v)));
        }
        parts.join("&")
    }
}
