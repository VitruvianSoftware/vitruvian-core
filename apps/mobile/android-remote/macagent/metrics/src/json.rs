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

//! Zero-dependency (std-only) RFC 8259 JSON parser, serializer, and ordered object map.

use std::fmt::Write as FmtWrite;

#[derive(Debug, Clone, PartialEq, Default)]
pub struct JsonMap {
    entries: Vec<(String, JsonValue)>,
}

pub type JsonObject = JsonMap;

impl JsonMap {
    pub fn new() -> Self {
        Self {
            entries: Vec::new(),
        }
    }

    pub fn push(&mut self, key: impl Into<String>, value: JsonValue) {
        self.insert(key, value);
    }

    pub fn into_value(self) -> JsonValue {
        JsonValue::Object(self)
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn get(&self, key: &str) -> Option<&JsonValue> {
        self.entries.iter().find(|(k, _)| k == key).map(|(_, v)| v)
    }

    pub fn get_mut(&mut self, key: &str) -> Option<&mut JsonValue> {
        self.entries
            .iter_mut()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v)
    }

    pub fn contains_key(&self, key: &str) -> bool {
        self.entries.iter().any(|(k, _)| k == key)
    }

    pub fn insert(&mut self, key: impl Into<String>, value: JsonValue) {
        let key = key.into();
        if let Some((_, existing)) = self.entries.iter_mut().find(|(k, _)| *k == key) {
            *existing = value;
        } else {
            self.entries.push((key, value));
        }
    }

    pub fn remove(&mut self, key: &str) -> Option<JsonValue> {
        if let Some(pos) = self.entries.iter().position(|(k, _)| k == key) {
            Some(self.entries.remove(pos).1)
        } else {
            None
        }
    }

    pub fn iter(&self) -> std::slice::Iter<'_, (String, JsonValue)> {
        self.entries.iter()
    }

    pub fn iter_mut(&mut self) -> std::slice::IterMut<'_, (String, JsonValue)> {
        self.entries.iter_mut()
    }

    pub fn keys(&self) -> impl Iterator<Item = &str> {
        self.entries.iter().map(|(k, _)| k.as_str())
    }

    pub fn sort_keys_recursive(&mut self) {
        self.entries.sort_by(|(a, _), (b, _)| a.cmp(b));
        for (_, v) in &mut self.entries {
            v.sort_keys_recursive();
        }
    }

    pub fn get_str(&self, key: &str) -> &str {
        self.get(key).and_then(|v| v.as_str()).unwrap_or("")
    }

    pub fn get_opt_str(&self, key: &str) -> Option<String> {
        self.get(key)
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    }

    pub fn get_bool(&self, key: &str) -> bool {
        self.get(key).and_then(|v| v.as_bool()).unwrap_or(false)
    }

    pub fn get_opt_bool(&self, key: &str) -> Option<bool> {
        self.get(key).and_then(|v| v.as_bool())
    }

    pub fn get_i64(&self, key: &str) -> i64 {
        self.get(key).and_then(|v| v.as_i64()).unwrap_or(0)
    }

    pub fn get_opt_i64(&self, key: &str) -> Option<i64> {
        self.get(key).and_then(|v| v.as_i64())
    }

    pub fn get_i32(&self, key: &str) -> i32 {
        self.get(key).and_then(|v| v.as_i32()).unwrap_or(0)
    }

    pub fn get_f64(&self, key: &str) -> f64 {
        self.get(key).and_then(|v| v.as_f64()).unwrap_or(0.0)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum JsonValue {
    Null,
    Bool(bool),
    Number(String),
    String(String),
    Array(Vec<JsonValue>),
    Object(JsonMap),
}

impl Default for JsonValue {
    fn default() -> Self {
        JsonValue::Null
    }
}

impl JsonValue {
    pub fn from_str_val(s: impl Into<String>) -> Self {
        JsonValue::String(s.into())
    }

    #[allow(non_snake_case)]
    pub fn Str(s: impl Into<String>) -> Self {
        JsonValue::String(s.into())
    }

    #[allow(non_snake_case)]
    pub fn Int(n: i64) -> Self {
        Self::from_i64(n)
    }

    #[allow(non_snake_case)]
    pub fn Float(n: f64) -> Self {
        Self::from_f64(n)
    }

    pub fn from_bool(b: bool) -> Self {
        JsonValue::Bool(b)
    }

    pub fn from_i64(n: i64) -> Self {
        JsonValue::Number(n.to_string())
    }

    pub fn from_u64(n: u64) -> Self {
        JsonValue::Number(n.to_string())
    }

    pub fn from_i32(n: i32) -> Self {
        JsonValue::Number(n.to_string())
    }

    pub fn from_usize(n: usize) -> Self {
        JsonValue::Number(n.to_string())
    }

    pub fn from_f64(n: f64) -> Self {
        if !n.is_finite() {
            return JsonValue::Number("0".to_string());
        }
        if n.fract() == 0.0 && n.abs() < 1e15 {
            JsonValue::Number(format!("{}", n as i64))
        } else {
            JsonValue::Number(format!("{}", n))
        }
    }

    pub fn empty_object() -> Self {
        JsonValue::Object(JsonMap::new())
    }

    pub fn empty_array() -> Self {
        JsonValue::Array(Vec::new())
    }

    pub fn is_null(&self) -> bool {
        matches!(self, JsonValue::Null)
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            JsonValue::String(s) => Some(s.as_str()),
            _ => None,
        }
    }

    pub fn as_bool(&self) -> Option<bool> {
        match self {
            JsonValue::Bool(b) => Some(*b),
            _ => None,
        }
    }

    pub fn as_i64(&self) -> Option<i64> {
        match self {
            JsonValue::Number(s) => {
                if let Ok(n) = s.parse::<i64>() {
                    Some(n)
                } else if let Ok(f) = s.parse::<f64>() {
                    Some(f as i64)
                } else {
                    None
                }
            }
            _ => None,
        }
    }

    pub fn as_u64(&self) -> Option<u64> {
        match self {
            JsonValue::Number(s) => {
                if let Ok(n) = s.parse::<u64>() {
                    Some(n)
                } else if let Ok(f) = s.parse::<f64>() {
                    if f >= 0.0 {
                        Some(f as u64)
                    } else {
                        None
                    }
                } else {
                    None
                }
            }
            _ => None,
        }
    }

    pub fn as_i32(&self) -> Option<i32> {
        self.as_i64().map(|n| n as i32)
    }

    pub fn as_f64(&self) -> Option<f64> {
        match self {
            JsonValue::Number(s) => s.parse::<f64>().ok(),
            _ => None,
        }
    }

    pub fn as_array(&self) -> Option<&[JsonValue]> {
        match self {
            JsonValue::Array(a) => Some(a.as_slice()),
            _ => None,
        }
    }

    pub fn as_array_mut(&mut self) -> Option<&mut Vec<JsonValue>> {
        match self {
            JsonValue::Array(a) => Some(a),
            _ => None,
        }
    }

    pub fn as_object(&self) -> Option<&JsonMap> {
        match self {
            JsonValue::Object(m) => Some(m),
            _ => None,
        }
    }

    pub fn as_object_mut(&mut self) -> Option<&mut JsonMap> {
        match self {
            JsonValue::Object(m) => Some(m),
            _ => None,
        }
    }

    pub fn get(&self, key: &str) -> Option<&JsonValue> {
        self.as_object().and_then(|m| m.get(key))
    }

    pub fn get_mut(&mut self, key: &str) -> Option<&mut JsonValue> {
        self.as_object_mut().and_then(|m| m.get_mut(key))
    }

    pub fn get_str(&self, key: &str) -> &str {
        self.as_object().map(|m| m.get_str(key)).unwrap_or("")
    }

    pub fn get_opt_str(&self, key: &str) -> Option<String> {
        self.as_object().and_then(|m| m.get_opt_str(key))
    }

    pub fn get_bool(&self, key: &str) -> bool {
        self.as_object().map(|m| m.get_bool(key)).unwrap_or(false)
    }

    pub fn get_opt_bool(&self, key: &str) -> Option<bool> {
        self.as_object().and_then(|m| m.get_opt_bool(key))
    }

    pub fn get_i64(&self, key: &str) -> i64 {
        self.as_object().map(|m| m.get_i64(key)).unwrap_or(0)
    }

    pub fn get_opt_i64(&self, key: &str) -> Option<i64> {
        self.as_object().and_then(|m| m.get_opt_i64(key))
    }

    pub fn get_i32(&self, key: &str) -> i32 {
        self.as_object().map(|m| m.get_i32(key)).unwrap_or(0)
    }

    pub fn get_f64(&self, key: &str) -> f64 {
        self.as_object().map(|m| m.get_f64(key)).unwrap_or(0.0)
    }

    pub fn get_array(&self, key: &str) -> Option<&[JsonValue]> {
        self.get(key).and_then(|v| v.as_array())
    }

    pub fn sort_keys_recursive(&mut self) {
        match self {
            JsonValue::Object(m) => m.sort_keys_recursive(),
            JsonValue::Array(arr) => {
                for v in arr {
                    v.sort_keys_recursive();
                }
            }
            _ => {}
        }
    }

    pub fn parse(input: &str) -> Result<JsonValue, String> {
        Self::parse_bytes(input.as_bytes())
    }

    pub fn parse_bytes(input: &[u8]) -> Result<JsonValue, String> {
        let mut parser = Parser::new(input);
        let val = parser.parse_value()?;
        parser.skip_ws();
        if parser.pos < parser.bytes.len() {
            return Err(format!("trailing characters at byte {}", parser.pos));
        }
        Ok(val)
    }

    pub fn to_json_string(&self) -> String {
        let mut out = String::new();
        self.write_compact(&mut out);
        out
    }

    pub fn to_json_string_pretty(&self) -> String {
        let mut out = String::new();
        self.write_pretty(&mut out, 0);
        out
    }

    pub fn to_json_pretty(&self) -> String {
        self.to_json_string_pretty()
    }

    fn write_compact(&self, out: &mut String) {
        match self {
            JsonValue::Null => out.push_str("null"),
            JsonValue::Bool(true) => out.push_str("true"),
            JsonValue::Bool(false) => out.push_str("false"),
            JsonValue::Number(n) => out.push_str(n),
            JsonValue::String(s) => write_escaped_str(out, s),
            JsonValue::Array(arr) => {
                out.push('[');
                for (i, item) in arr.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    item.write_compact(out);
                }
                out.push(']');
            }
            JsonValue::Object(map) => {
                out.push('{');
                for (i, (k, v)) in map.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    write_escaped_str(out, k);
                    out.push(':');
                    v.write_compact(out);
                }
                out.push('}');
            }
        }
    }

    fn write_pretty(&self, out: &mut String, indent: usize) {
        match self {
            JsonValue::Null | JsonValue::Bool(_) | JsonValue::Number(_) | JsonValue::String(_) => {
                self.write_compact(out);
            }
            JsonValue::Array(arr) => {
                if arr.is_empty() {
                    out.push_str("[]");
                    return;
                }
                out.push_str("[\n");
                for (i, item) in arr.iter().enumerate() {
                    if i > 0 {
                        out.push_str(",\n");
                    }
                    for _ in 0..(indent + 2) {
                        out.push(' ');
                    }
                    item.write_pretty(out, indent + 2);
                }
                out.push('\n');
                for _ in 0..indent {
                    out.push(' ');
                }
                out.push(']');
            }
            JsonValue::Object(map) => {
                if map.is_empty() {
                    out.push_str("{}");
                    return;
                }
                out.push_str("{\n");
                for (i, (k, v)) in map.iter().enumerate() {
                    if i > 0 {
                        out.push_str(",\n");
                    }
                    for _ in 0..(indent + 2) {
                        out.push(' ');
                    }
                    write_escaped_str(out, k);
                    out.push_str(": ");
                    v.write_pretty(out, indent + 2);
                }
                out.push('\n');
                for _ in 0..indent {
                    out.push(' ');
                }
                out.push('}');
            }
        }
    }
}

pub fn write_escaped_str(out: &mut String, s: &str) {
    out.push('"');
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\x08' => out.push_str("\\b"),
            '\x0C' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

pub fn escape_json_str(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    write_escaped_str(&mut out, s);
    out
}

struct Parser<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> Parser<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, pos: 0 }
    }

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
        let b = self
            .peek()
            .ok_or_else(|| "unexpected end of JSON input".to_string())?;
        match b {
            b'n' => self.parse_null(),
            b't' | b'f' => self.parse_bool(),
            b'"' => self.parse_string().map(JsonValue::String),
            b'[' => self.parse_array(),
            b'{' => self.parse_object(),
            b'-' | b'0'..=b'9' => self.parse_number(),
            _ => Err(format!(
                "unexpected byte '{}' at position {}",
                b as char, self.pos
            )),
        }
    }

    fn parse_null(&mut self) -> Result<JsonValue, String> {
        if self.bytes[self.pos..].starts_with(b"null") {
            self.pos += 4;
            Ok(JsonValue::Null)
        } else {
            Err(format!("invalid literal at {}", self.pos))
        }
    }

    fn parse_bool(&mut self) -> Result<JsonValue, String> {
        if self.bytes[self.pos..].starts_with(b"true") {
            self.pos += 4;
            Ok(JsonValue::Bool(true))
        } else if self.bytes[self.pos..].starts_with(b"false") {
            self.pos += 5;
            Ok(JsonValue::Bool(false))
        } else {
            Err(format!("invalid boolean at {}", self.pos))
        }
    }

    fn parse_number(&mut self) -> Result<JsonValue, String> {
        let start = self.pos;
        if self.peek() == Some(b'-') {
            self.pos += 1;
        }
        match self.peek() {
            Some(b'0') => {
                self.pos += 1;
            }
            Some(b'1'..=b'9') => {
                self.pos += 1;
                while matches!(self.peek(), Some(b'0'..=b'9')) {
                    self.pos += 1;
                }
            }
            _ => return Err(format!("invalid number at {}", start)),
        }
        if self.peek() == Some(b'.') {
            self.pos += 1;
            if !matches!(self.peek(), Some(b'0'..=b'9')) {
                return Err(format!("invalid fraction in number at {}", self.pos));
            }
            while matches!(self.peek(), Some(b'0'..=b'9')) {
                self.pos += 1;
            }
        }
        if matches!(self.peek(), Some(b'e' | b'E')) {
            self.pos += 1;
            if matches!(self.peek(), Some(b'+' | b'-')) {
                self.pos += 1;
            }
            if !matches!(self.peek(), Some(b'0'..=b'9')) {
                return Err(format!("invalid exponent in number at {}", self.pos));
            }
            while matches!(self.peek(), Some(b'0'..=b'9')) {
                self.pos += 1;
            }
        }
        let raw = std::str::from_utf8(&self.bytes[start..self.pos])
            .map_err(|e| e.to_string())?
            .to_string();
        Ok(JsonValue::Number(raw))
    }

    fn parse_string(&mut self) -> Result<String, String> {
        if self.peek() != Some(b'"') {
            return Err(format!("expected '\"' at {}", self.pos));
        }
        self.pos += 1;
        let mut out = String::new();
        while self.pos < self.bytes.len() {
            let b = self.bytes[self.pos];
            if b == b'"' {
                self.pos += 1;
                return Ok(out);
            }
            if b == b'\\' {
                self.pos += 1;
                if self.pos >= self.bytes.len() {
                    return Err("unterminated escape sequence".to_string());
                }
                let esc = self.bytes[self.pos];
                self.pos += 1;
                match esc {
                    b'"' => out.push('"'),
                    b'\\' => out.push('\\'),
                    b'/' => out.push('/'),
                    b'b' => out.push('\x08'),
                    b'f' => out.push('\x0C'),
                    b'n' => out.push('\n'),
                    b'r' => out.push('\r'),
                    b't' => out.push('\t'),
                    b'u' => {
                        let code = self.parse_hex4()?;
                        if (0xD800..=0xDBFF).contains(&code) {
                            // High surrogate; check for following \uXXXX low surrogate
                            if self.pos + 2 <= self.bytes.len()
                                && self.bytes[self.pos] == b'\\'
                                && self.bytes[self.pos + 1] == b'u'
                            {
                                self.pos += 2;
                                let low = self.parse_hex4()?;
                                if (0xDC00..=0xDFFF).contains(&low) {
                                    let combined = 0x10000
                                        + (((code as u32 - 0xD800) << 10) | (low as u32 - 0xDC00));
                                    if let Some(ch) = char::from_u32(combined) {
                                        out.push(ch);
                                        continue;
                                    }
                                }
                            }
                            out.push('\u{FFFD}');
                        } else if let Some(ch) = char::from_u32(code as u32) {
                            out.push(ch);
                        } else {
                            out.push('\u{FFFD}');
                        }
                    }
                    other => {
                        return Err(format!("invalid escape '\\{}'", other as char));
                    }
                }
            } else if b < 0x20 {
                return Err(format!("unescaped control character 0x{:02x}", b));
            } else {
                // Decode UTF-8 char starting at self.pos
                let s = std::str::from_utf8(&self.bytes[self.pos..])
                    .map_err(|_| "invalid UTF-8 in JSON string".to_string())?;
                let ch = s.chars().next().unwrap();
                out.push(ch);
                self.pos += ch.len_utf8();
            }
        }
        Err("unterminated JSON string".to_string())
    }

    fn parse_hex4(&mut self) -> Result<u16, String> {
        if self.pos + 4 > self.bytes.len() {
            return Err("incomplete \\u escape".to_string());
        }
        let hex_str = std::str::from_utf8(&self.bytes[self.pos..self.pos + 4])
            .map_err(|_| "invalid hex in \\u escape".to_string())?;
        let val = u16::from_str_radix(hex_str, 16)
            .map_err(|_| format!("invalid hex '{}' in \\u escape", hex_str))?;
        self.pos += 4;
        Ok(val)
    }

    fn parse_array(&mut self) -> Result<JsonValue, String> {
        self.pos += 1; // skip '['
        self.skip_ws();
        let mut arr = Vec::new();
        if self.peek() == Some(b']') {
            self.pos += 1;
            return Ok(JsonValue::Array(arr));
        }
        loop {
            let v = self.parse_value()?;
            arr.push(v);
            self.skip_ws();
            match self.peek() {
                Some(b',') => {
                    self.pos += 1;
                }
                Some(b']') => {
                    self.pos += 1;
                    return Ok(JsonValue::Array(arr));
                }
                _ => return Err(format!("expected ',' or ']' at {}", self.pos)),
            }
        }
    }

    fn parse_object(&mut self) -> Result<JsonValue, String> {
        self.pos += 1; // skip '{'
        self.skip_ws();
        let mut map = JsonMap::new();
        if self.peek() == Some(b'}') {
            self.pos += 1;
            return Ok(JsonValue::Object(map));
        }
        loop {
            self.skip_ws();
            let key = self.parse_string()?;
            self.skip_ws();
            if self.peek() != Some(b':') {
                return Err(format!("expected ':' after object key at {}", self.pos));
            }
            self.pos += 1;
            let val = self.parse_value()?;
            map.insert(key, val);
            self.skip_ws();
            match self.peek() {
                Some(b',') => {
                    self.pos += 1;
                }
                Some(b'}') => {
                    self.pos += 1;
                    return Ok(JsonValue::Object(map));
                }
                _ => return Err(format!("expected ',' or '}}' at {}", self.pos)),
            }
        }
    }
}
