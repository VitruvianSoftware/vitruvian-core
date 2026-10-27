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
                    // JSON.stringify writes NaN and the infinities as null.
                    if !n.is_finite() {
                        out.push_str("null");
                    } else {
                        out.push_str(&js_number_to_string(*n));
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

        /// Parses JSON the way `JSON.parse` would, through serde_json.
        ///
        /// serde_json does the parsing (and caps nesting at 128 levels, so
        /// hostile input cannot exhaust the stack). Two JavaScript behaviours
        /// are layered on top so values read here look the same as they did to
        /// the TypeScript server:
        /// - a duplicate key keeps the LAST value at the FIRST key's position
        ///   (serde_json's `preserve_order` map does exactly this);
        /// - keys that are array indices ("0", "42") come first, in ascending
        ///   numeric order, as they do on every JavaScript object;
        /// - a lone UTF-16 surrogate escape (`"\ud800"`), which JavaScript
        ///   accepts but a Rust string cannot hold, becomes U+FFFD instead of
        ///   failing the whole document.
        pub fn parse(input: &str) -> Result<JsonValue, String> {
            let input = replace_lone_surrogate_escapes(input);
            let value: serde_json::Value =
                serde_json::from_str(&input).map_err(|e| e.to_string())?;
            Ok(JsonValue::from_serde(value))
        }

        fn from_serde(value: serde_json::Value) -> JsonValue {
            match value {
                serde_json::Value::Null => JsonValue::Null,
                serde_json::Value::Bool(b) => JsonValue::Bool(b),
                // Every serde_json number converts: u64/i64 are exact and
                // round to the nearest double, as JSON.parse would.
                serde_json::Value::Number(n) => JsonValue::Number(n.as_f64().unwrap_or(f64::NAN)),
                serde_json::Value::String(s) => JsonValue::String(s),
                serde_json::Value::Array(items) => {
                    JsonValue::Array(items.into_iter().map(JsonValue::from_serde).collect())
                }
                serde_json::Value::Object(map) => {
                    let mut index_keys: Vec<(u32, String, JsonValue)> = Vec::new();
                    let mut other_keys: Vec<(String, JsonValue)> = Vec::new();
                    for (k, v) in map {
                        let v = JsonValue::from_serde(v);
                        match array_index(&k) {
                            Some(i) => index_keys.push((i, k, v)),
                            None => other_keys.push((k, v)),
                        }
                    }
                    index_keys.sort_by_key(|(i, _, _)| *i);
                    let mut entries: Vec<(String, JsonValue)> =
                        index_keys.into_iter().map(|(_, k, v)| (k, v)).collect();
                    entries.extend(other_keys);
                    JsonValue::Object(entries)
                }
            }
        }
    }

    /// The key is an ECMAScript array index: a canonical decimal integer in
    /// 0..2^32-1. Such keys are ordered first on a JavaScript object.
    fn array_index(key: &str) -> Option<u32> {
        if key.is_empty() || key.len() > 10 || !key.bytes().all(|b| b.is_ascii_digit()) {
            return None;
        }
        if key.len() > 1 && key.starts_with('0') {
            return None;
        }
        let n: u64 = key.parse().ok()?;
        if n < u64::from(u32::MAX) {
            Some(n as u32)
        } else {
            None
        }
    }

    fn hex4(bytes: &[u8]) -> Option<u32> {
        if bytes.len() < 4 {
            return None;
        }
        let s = std::str::from_utf8(&bytes[..4]).ok()?;
        if !s.bytes().all(|b| b.is_ascii_hexdigit()) {
            return None;
        }
        u32::from_str_radix(s, 16).ok()
    }

    /// Rewrites `\uD800`-style escapes that are not half of a valid pair to
    /// `�`. Only escapes inside strings are touched; everything else is
    /// copied byte for byte, so malformed JSON stays malformed.
    fn replace_lone_surrogate_escapes(input: &str) -> std::borrow::Cow<'_, str> {
        let bytes = input.as_bytes();
        // Fast path: no escape that could start a surrogate.
        let maybe = bytes
            .windows(3)
            .any(|w| w[0] == b'\\' && w[1] == b'u' && matches!(w[2], b'd' | b'D'));
        if !maybe {
            return std::borrow::Cow::Borrowed(input);
        }
        let mut out: Vec<u8> = Vec::with_capacity(bytes.len());
        let mut in_string = false;
        let mut i = 0;
        while i < bytes.len() {
            let b = bytes[i];
            if !in_string {
                if b == b'"' {
                    in_string = true;
                }
                out.push(b);
                i += 1;
                continue;
            }
            match b {
                b'"' => {
                    in_string = false;
                    out.push(b);
                    i += 1;
                }
                b'\\' if bytes.get(i + 1) == Some(&b'u') => match hex4(&bytes[i + 2..]) {
                    Some(0xD800..=0xDBFF) => {
                        let paired = bytes.get(i + 6) == Some(&b'\\')
                            && bytes.get(i + 7) == Some(&b'u')
                            && matches!(bytes.get(i + 8..).and_then(hex4), Some(0xDC00..=0xDFFF));
                        if paired {
                            out.extend_from_slice(&bytes[i..i + 12]);
                            i += 12;
                        } else {
                            out.extend_from_slice(b"\\ufffd");
                            i += 6;
                        }
                    }
                    Some(0xDC00..=0xDFFF) => {
                        out.extend_from_slice(b"\\ufffd");
                        i += 6;
                    }
                    Some(_) => {
                        out.extend_from_slice(&bytes[i..i + 6]);
                        i += 6;
                    }
                    None => {
                        out.extend_from_slice(&bytes[i..i + 2]);
                        i += 2;
                    }
                },
                b'\\' => {
                    out.push(b);
                    if let Some(&next) = bytes.get(i + 1) {
                        out.push(next);
                    }
                    i += 2;
                }
                _ => {
                    out.push(b);
                    i += 1;
                }
            }
        }
        // Every byte is copied except whole ASCII escape sequences replaced by
        // other ASCII, so the output is still valid UTF-8.
        match String::from_utf8(out) {
            Ok(s) => std::borrow::Cow::Owned(s),
            Err(_) => std::borrow::Cow::Borrowed(input),
        }
    }

    /// Formats a finite number exactly as JavaScript's `String(n)` and
    /// `JSON.stringify(n)` do (Number::toString, ECMA-262 §6.1.6.1.20):
    /// shortest round-trip digits, plain notation for 1e-6 <= |n| < 1e21 and
    /// exponent notation (`1e+21`, `1e-7`) outside it, and `-0` as `0`.
    pub fn js_number_to_string(n: f64) -> String {
        if n.is_nan() {
            return "NaN".to_string();
        }
        if n == 0.0 {
            return "0".to_string();
        }
        if n.is_infinite() {
            return if n > 0.0 { "Infinity" } else { "-Infinity" }.to_string();
        }
        let sign = if n < 0.0 { "-" } else { "" };
        // `{:e}` yields the shortest digits that round-trip, e.g. "1.2345e-7".
        let sci = format!("{:e}", n.abs());
        let (mantissa, exp) = sci.split_once('e').unwrap_or((sci.as_str(), "0"));
        let exp: i32 = exp.parse().unwrap_or(0);
        let digits: String = mantissa.chars().filter(|c| *c != '.').collect();
        let k = digits.len() as i32;
        // n in the spec: the decimal point sits after this many digits.
        let point = exp + 1;
        let body = if k <= point && point <= 21 {
            let mut s = digits.clone();
            s.extend(std::iter::repeat('0').take((point - k) as usize));
            s
        } else if 0 < point && point <= 21 {
            format!(
                "{}.{}",
                &digits[..point as usize],
                &digits[point as usize..]
            )
        } else if -6 < point && point <= 0 {
            format!("0.{}{}", "0".repeat((-point) as usize), digits)
        } else {
            let e = point - 1;
            let e_str = if e >= 0 {
                format!("+{e}")
            } else {
                e.to_string()
            };
            if k == 1 {
                format!("{digits}e{e_str}")
            } else {
                format!("{}.{}e{e_str}", &digits[..1], &digits[1..])
            }
        };
        format!("{sign}{body}")
    }

    /// JavaScript's `String(value)` for a JSON value: what
    /// `URLSearchParams.append(k, String(v))` and template literals produce.
    pub fn js_string(value: &JsonValue) -> String {
        match value {
            JsonValue::Null => "null".to_string(),
            JsonValue::Bool(b) => b.to_string(),
            JsonValue::Number(n) => js_number_to_string(*n),
            JsonValue::String(s) => s.clone(),
            // Array.prototype.toString is join(","), with null as "".
            JsonValue::Array(items) => items
                .iter()
                .map(|v| match v {
                    JsonValue::Null => String::new(),
                    other => js_string(other),
                })
                .collect::<Vec<_>>()
                .join(","),
            JsonValue::Object(_) => "[object Object]".to_string(),
        }
    }

    /// JavaScript truthiness of a JSON value (`!!value`).
    pub fn js_truthy(value: Option<&JsonValue>) -> bool {
        match value {
            None | Some(JsonValue::Null) => false,
            Some(JsonValue::Bool(b)) => *b,
            Some(JsonValue::Number(n)) => *n != 0.0 && !n.is_nan(),
            Some(JsonValue::String(s)) => !s.is_empty(),
            Some(JsonValue::Array(_)) | Some(JsonValue::Object(_)) => true,
        }
    }

    /// JavaScript's `Number(string)` (StringToNumber, ECMA-262 §7.1.4.1.1):
    /// surrounding whitespace ignored, empty means 0, `0x`/`0o`/`0b`
    /// prefixes, `Infinity`, and NaN for anything else.
    pub fn js_string_to_number(input: &str) -> f64 {
        let is_js_ws = |c: char| {
            matches!(
                c,
                '\u{9}'
                    | '\u{A}'
                    | '\u{B}'
                    | '\u{C}'
                    | '\u{D}'
                    | ' '
                    | '\u{A0}'
                    | '\u{FEFF}'
                    | '\u{1680}'
                    | '\u{2000}'
                    ..='\u{200A}' | '\u{2028}' | '\u{2029}' | '\u{202F}' | '\u{205F}' | '\u{3000}'
            )
        };
        let s = input.trim_matches(is_js_ws);
        if s.is_empty() {
            return 0.0;
        }
        for (prefix, radix) in [
            ("0x", 16),
            ("0X", 16),
            ("0o", 8),
            ("0O", 8),
            ("0b", 2),
            ("0B", 2),
        ] {
            if let Some(rest) = s.strip_prefix(prefix) {
                if rest.is_empty() || !rest.chars().all(|c| c.is_digit(radix)) {
                    return f64::NAN;
                }
                return rest.chars().fold(0.0, |acc, c| {
                    acc * f64::from(radix) + f64::from(c.to_digit(radix).unwrap_or(0))
                });
            }
        }
        let (sign, unsigned) = match s.as_bytes()[0] {
            b'+' => (1.0, &s[1..]),
            b'-' => (-1.0, &s[1..]),
            _ => (1.0, s),
        };
        if unsigned == "Infinity" {
            return sign * f64::INFINITY;
        }
        // StrUnsignedDecimalLiteral: digits [. digits] [e [+-] digits], with
        // at least one digit in the significand.
        let b = unsigned.as_bytes();
        let mut i = 0;
        let int_start = i;
        while i < b.len() && b[i].is_ascii_digit() {
            i += 1;
        }
        let mut sig_digits = i - int_start;
        if i < b.len() && b[i] == b'.' {
            i += 1;
            let frac_start = i;
            while i < b.len() && b[i].is_ascii_digit() {
                i += 1;
            }
            sig_digits += i - frac_start;
        }
        if sig_digits == 0 {
            return f64::NAN;
        }
        if i < b.len() && (b[i] == b'e' || b[i] == b'E') {
            i += 1;
            if i < b.len() && (b[i] == b'+' || b[i] == b'-') {
                i += 1;
            }
            let exp_start = i;
            while i < b.len() && b[i].is_ascii_digit() {
                i += 1;
            }
            if i == exp_start {
                return f64::NAN;
            }
        }
        if i != b.len() {
            return f64::NAN;
        }
        // The grammar above is a subset of what Rust's parser accepts, and
        // Rust parses decimal strings with correct rounding.
        sign * unsigned.parse::<f64>().unwrap_or(f64::NAN)
    }

    /// JavaScript's `Number(value)` for a JSON value.
    pub fn js_to_number(value: &JsonValue) -> f64 {
        match value {
            JsonValue::Null => 0.0,
            JsonValue::Bool(b) => {
                if *b {
                    1.0
                } else {
                    0.0
                }
            }
            JsonValue::Number(n) => *n,
            JsonValue::String(s) => js_string_to_number(s),
            JsonValue::Array(_) => js_string_to_number(&js_string(value)),
            JsonValue::Object(_) => f64::NAN,
        }
    }

    /// `Object.prototype.toString.call(value)`; `None` is `undefined`.
    pub fn js_object_tag(value: Option<&JsonValue>) -> &'static str {
        match value {
            None => "[object Undefined]",
            Some(JsonValue::Null) => "[object Null]",
            Some(JsonValue::Bool(_)) => "[object Boolean]",
            Some(JsonValue::Number(_)) => "[object Number]",
            Some(JsonValue::String(_)) => "[object String]",
            Some(JsonValue::Array(_)) => "[object Array]",
            Some(JsonValue::Object(_)) => "[object Object]",
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

    #[cfg(test)]
    mod tests {
        use super::*;

        fn obj_keys(v: &JsonValue) -> Vec<&str> {
            v.as_object()
                .unwrap()
                .iter()
                .map(|(k, _)| k.as_str())
                .collect()
        }

        #[test]
        fn decodes_surrogate_pairs() {
            let v = JsonValue::parse(r#""🚀""#).unwrap();
            assert_eq!(v.as_str(), Some("🚀"));
            let v = JsonValue::parse(r#"{"t":"go 🚀!"}"#).unwrap();
            assert_eq!(v.get("t").and_then(|v| v.as_str()), Some("go 🚀!"));
        }

        #[test]
        fn lone_surrogate_escapes_become_replacement_characters() {
            // JSON.parse accepts these; a Rust String cannot hold them.
            let v = JsonValue::parse(r#"["\ud800","a\udc00b","\ud83dx","\\ud800"]"#).unwrap();
            let items: Vec<&str> = v
                .as_array()
                .unwrap()
                .iter()
                .map(|i| i.as_str().unwrap())
                .collect();
            assert_eq!(
                items,
                vec!["\u{FFFD}", "a\u{FFFD}b", "\u{FFFD}x", "\\ud800"]
            );
        }

        #[test]
        fn duplicate_keys_keep_last_value_at_first_position() {
            // JSON.stringify(JSON.parse('{"a":1,"b":2,"a":3}')) === '{"a":3,"b":2}'
            let v = JsonValue::parse(r#"{"a":1,"b":2,"a":3}"#).unwrap();
            assert_eq!(v.to_json_string(), r#"{"a":3,"b":2}"#);
        }

        #[test]
        fn array_index_keys_come_first_like_a_javascript_object() {
            // Observed in Node: JSON.stringify(JSON.parse(<input>)).
            let v = JsonValue::parse(
                r#"{"b":1,"10":2,"2":3,"a":4,"01":5,"4294967295":6,"4294967294":7,"-1":8}"#,
            )
            .unwrap();
            assert_eq!(
                obj_keys(&v),
                vec!["2", "10", "4294967294", "b", "a", "01", "4294967295", "-1"]
            );
        }

        #[test]
        fn nesting_is_capped_at_128_levels() {
            let ok = format!("{}{}", "[".repeat(100), "]".repeat(100));
            assert!(JsonValue::parse(&ok).is_ok());
            let deep = format!("{}{}", "[".repeat(100_000), "]".repeat(100_000));
            assert!(JsonValue::parse(&deep).is_err());
        }

        #[test]
        fn parses_large_documents_in_linear_time() {
            // The old parser re-validated the remaining input per character.
            let big = format!("[\"{}\"]", "é".repeat(2_000_000));
            let start = std::time::Instant::now();
            let v = JsonValue::parse(&big).unwrap();
            assert_eq!(v.as_array().unwrap()[0].as_str().unwrap().len(), 4_000_000);
            assert!(start.elapsed() < std::time::Duration::from_secs(5));
        }

        #[test]
        fn rejects_invalid_json() {
            for bad in ["", "{", "[1,]", "{\"a\":1}x", "nul", "'a'", "01"] {
                assert!(JsonValue::parse(bad).is_err(), "{bad:?} should fail");
            }
        }

        #[test]
        fn numbers_format_like_javascript() {
            // Each pair is (value, String(value) in Node).
            let cases: &[(f64, &str)] = &[
                (0.0, "0"),
                (-0.0, "0"),
                (1.0, "1"),
                (-1.0, "-1"),
                (0.5, "0.5"),
                (-0.5, "-0.5"),
                (100.0, "100"),
                (1e20, "100000000000000000000"),
                (1e21, "1e+21"),
                (1.5e21, "1.5e+21"),
                (123456789012345680000.0, "123456789012345680000"),
                (1e-6, "0.000001"),
                (1e-7, "1e-7"),
                (1.5e-7, "1.5e-7"),
                (0.000001234, "0.000001234"),
                (-1e-7, "-1e-7"),
                (1.0 / 3.0, "0.3333333333333333"),
                (2.0 / 3.0, "0.6666666666666666"),
                (f64::MAX, "1.7976931348623157e+308"),
                (5e-324, "5e-324"),
                (123.456, "123.456"),
                (9007199254740993.0, "9007199254740992"),
                (4294967295.0, "4294967295"),
                (1e100, "1e+100"),
                (-1e21, "-1e+21"),
                (0.1 + 0.2, "0.30000000000000004"),
                (12345678.9, "12345678.9"),
                (1e6, "1000000"),
            ];
            for (n, want) in cases {
                assert_eq!(js_number_to_string(*n), *want, "String({n:e})");
                assert_eq!(JsonValue::Number(*n).to_json_string(), *want);
            }
            assert_eq!(JsonValue::Number(f64::NAN).to_json_string(), "null");
            assert_eq!(JsonValue::Number(f64::INFINITY).to_json_string(), "null");
        }

        #[test]
        fn strings_escape_like_json_stringify() {
            // JSON.stringify("a/é \u007f\u0001\u001f\"\\\b\f\n\r\t🚀")
            let s = "a/é\u{2028}\u{7f}\u{1}\u{1f}\"\\\u{8}\u{c}\n\r\t🚀";
            assert_eq!(
                JsonValue::str(s).to_json_string(),
                "\"a/é\u{2028}\u{7f}\\u0001\\u001f\\\"\\\\\\b\\f\\n\\r\\t🚀\""
            );
        }

        #[test]
        fn pretty_printing_matches_json_stringify_with_indent_2() {
            let v = JsonValue::parse(r#"{"a":[1,{}],"b":{},"c":[]}"#).unwrap();
            assert_eq!(
                v.to_json_pretty(),
                "{\n  \"a\": [\n    1,\n    {}\n  ],\n  \"b\": {},\n  \"c\": []\n}"
            );
        }

        #[test]
        fn string_to_number_matches_javascript() {
            // Each pair is (s, Number(s) in Node); None stands for NaN.
            let cases: &[(&str, Option<f64>)] = &[
                ("", Some(0.0)),
                ("  ", Some(0.0)),
                (" 2 ", Some(2.0)),
                ("1.5", Some(1.5)),
                ("abc", None),
                ("0x10", Some(16.0)),
                ("0X1f", Some(31.0)),
                ("1e2", Some(100.0)),
                ("Infinity", Some(f64::INFINITY)),
                ("-Infinity", Some(f64::NEG_INFINITY)),
                ("+Infinity", Some(f64::INFINITY)),
                ("-5", Some(-5.0)),
                ("inf", None),
                ("nan", None),
                ("NaN", None),
                ("1_0", None),
                (".5", Some(0.5)),
                ("5.", Some(5.0)),
                ("+3", Some(3.0)),
                ("-0x10", None),
                ("0b11", Some(3.0)),
                ("0o7", Some(7.0)),
                ("\t3\n", Some(3.0)),
                ("\u{a0}3\u{feff}", Some(3.0)),
                ("1e", None),
                ("e5", None),
                (".", None),
                ("+.5", Some(0.5)),
                ("1.2.3", None),
                ("0x", None),
                ("00012", Some(12.0)),
                ("1e400", Some(f64::INFINITY)),
            ];
            for (s, want) in cases {
                let got = js_string_to_number(s);
                match want {
                    None => assert!(got.is_nan(), "Number({s:?}) = {got}, want NaN"),
                    Some(w) => assert_eq!(got, *w, "Number({s:?})"),
                }
            }
            assert!(js_string_to_number("-0").is_sign_negative());
        }

        #[test]
        fn js_string_and_truthiness() {
            assert_eq!(js_string(&JsonValue::Number(-0.0)), "0");
            assert_eq!(js_string(&JsonValue::Number(0.5)), "0.5");
            assert_eq!(
                js_string(&JsonValue::parse(r#"["C1",null,2,[3,4]]"#).unwrap()),
                "C1,,2,3,4"
            );
            assert_eq!(js_string(&JsonValue::empty_object()), "[object Object]");
            assert!(!js_truthy(None));
            assert!(!js_truthy(Some(&JsonValue::str(""))));
            assert!(!js_truthy(Some(&JsonValue::Number(0.0))));
            assert!(js_truthy(Some(&JsonValue::array(vec![]))));
            assert_eq!(js_object_tag(None), "[object Undefined]");
            assert_eq!(js_object_tag(Some(&JsonValue::Null)), "[object Null]");
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

    /// Decodes exactly as Node's `Buffer.from(input, "base64")` does, which is
    /// what the TypeScript server used for upload content. Observed in Node
    /// (v26) rather than taken from its docs:
    /// - both alphabets are accepted, even mixed (`+`/`-` are 62, `/`/`_` 63);
    /// - every other character is skipped, not rejected;
    /// - decoding stops at the first `=`, wherever it is;
    /// - a trailing group of 2 or 3 characters yields 1 or 2 bytes, and a
    ///   lone trailing character is dropped;
    /// - Node reads the string as UTF-16 code units and looks only at the low
    ///   byte of each, so `Ł` (U+0141) counts as `A`, and the first half of
    ///   an emoji's surrogate pair (0xD83D) counts as `=` and stops decoding.
    ///
    /// It never fails, as Node never throws here.
    pub fn decode_node(input: &str) -> Vec<u8> {
        let mut out = Vec::with_capacity(input.len() * 3 / 4);
        let mut group = [0u32; 4];
        let mut n = 0;
        for unit in input.encode_utf16() {
            let b = (unit & 0xFF) as u8;
            let v = match b {
                b'A'..=b'Z' => u32::from(b - b'A'),
                b'a'..=b'z' => u32::from(b - b'a' + 26),
                b'0'..=b'9' => u32::from(b - b'0' + 52),
                b'+' | b'-' => 62,
                b'/' | b'_' => 63,
                b'=' => break,
                _ => continue,
            };
            group[n] = v;
            n += 1;
            if n == 4 {
                let triple = (group[0] << 18) | (group[1] << 12) | (group[2] << 6) | group[3];
                out.push((triple >> 16) as u8);
                out.push((triple >> 8) as u8);
                out.push(triple as u8);
                n = 0;
            }
        }
        if n >= 2 {
            let triple = (group[0] << 18) | (group[1] << 12) | (group[2] << 6);
            out.push((triple >> 16) as u8);
            if n == 3 {
                out.push((triple >> 8) as u8);
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

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn decode_node_matches_buffer_from_base64() {
            // Each pair is (input, [...Buffer.from(input, "base64")]) as
            // printed by Node v26.12.1.
            let cases: &[(&str, &[u8])] = &[
                ("aGVsbG8=d29ybGQ=", &[104, 101, 108, 108, 111]),
                (
                    "aGVsbG8gd29ybGQ",
                    &[104, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100],
                ),
                (
                    "aGVs bG8\nd29y\tbGQ=",
                    &[104, 101, 108, 108, 111, 29, 219, 220, 155, 25],
                ),
                ("aGVsbG8_-w==", &[104, 101, 108, 108, 111, 63, 251]),
                ("aGVsbG8/+w==", &[104, 101, 108, 108, 111, 63, 251]),
                ("a", &[]),
                ("ab", &[105]),
                ("abc", &[105, 183]),
                ("abcd", &[105, 183, 29]),
                ("abcde", &[105, 183, 29]),
                ("a===b", &[]),
                ("=abc", &[]),
                ("!!aGk!!", &[104, 105]),
                ("aGk", &[104, 105]),
                ("aGk=", &[104, 105]),
                ("aGk===x", &[104, 105]),
                ("YR", &[97]),
                ("Y", &[]),
                ("////", &[255, 255, 255]),
                ("____", &[255, 255, 255]),
                ("-_+/", &[251, 255, 191]),
                (
                    "aGVsbG8.d29ybGQ",
                    &[104, 101, 108, 108, 111, 29, 219, 220, 155, 25],
                ),
                ("8J+agA==", &[240, 159, 154, 128]),
                ("", &[]),
                (" ", &[]),
                ("aG=Vs", &[104]),
                ("aGk\u{e9}aGk", &[104, 105, 26, 26]),
                ("YWJj\u{0}ZGVm", &[97, 98, 99, 100, 101, 102]),
                // Node reads the low byte of each UTF-16 code unit.
                ("aGk\u{141}\u{141}\u{141}\u{141}", &[104, 105, 0, 0, 0]),
                ("\u{141}\u{141}\u{141}\u{141}", &[0, 0, 0]),
                ("aGk\u{13d}", &[104, 105]),
                ("aGk\u{ff1d}\u{141}\u{141}", &[104, 105, 0]),
                ("aGk\u{1F680}aGk", &[104, 105]),
                ("\u{100}\u{100}\u{100}\u{100}", &[]),
                ("aGk\u{178}aGk", &[104, 105, 49, 104, 105]),
            ];
            for (input, want) in cases {
                assert_eq!(
                    decode_node(input),
                    *want,
                    "Buffer.from({input:?}, \"base64\")"
                );
            }
        }

        #[test]
        fn decode_node_round_trips_binary_and_stops_mid_string_at_padding() {
            let data: Vec<u8> = (0..300u32).map(|i| ((i * 37) & 255) as u8).collect();
            let s = encode(&data);
            assert_eq!(decode_node(&s), data);
            assert_eq!(decode_node(&encode_url(&data)), data);
            let wrapped: String = s
                .as_bytes()
                .chunks(76)
                .map(|c| std::str::from_utf8(c).unwrap())
                .collect::<Vec<_>>()
                .join("\n");
            assert_eq!(decode_node(&wrapped), data);
            // An `=` after 100 characters stops decoding there: 75 bytes.
            let mid = format!("{}={}", &s[..100], &s[100..]);
            assert_eq!(decode_node(&mid), data[..75].to_vec());
        }
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
            // As the WHATWG URL parser (`new URL`) does before anything else:
            // drop leading/trailing C0 controls and spaces, and every ASCII
            // tab or newline anywhere. A permalink pasted with a trailing
            // newline parsed in the TypeScript server and must parse here.
            let cleaned: String = input
                .trim_matches(|c: char| c <= ' ')
                .chars()
                .filter(|c| !matches!(c, '\t' | '\n' | '\r'))
                .collect();
            let input = cleaned.as_str();
            let (scheme, rest) = input
                .split_once("://")
                .ok_or_else(|| "missing scheme".to_string())?;
            if scheme.is_empty() {
                return Err("empty scheme".to_string());
            }
            let scheme_lower = scheme.to_ascii_lowercase();
            let protocol = format!("{scheme_lower}:");
            // Special schemes treat a backslash as a path separator.
            let special = matches!(
                scheme_lower.as_str(),
                "http" | "https" | "ws" | "wss" | "ftp" | "file"
            );
            let rest_owned;
            let rest = if special && rest.contains('\\') {
                rest_owned = rest.replace('\\', "/");
                rest_owned.as_str()
            } else {
                rest
            };
            let rest_no_frag = match rest.split_once('#') {
                Some((before, _)) => before,
                None => rest,
            };
            // The authority ends at the first `/` or `?`, whichever comes
            // first (`host?a=/b` has host `host`).
            let (authority, path_and_query) =
                match rest_no_frag.find(|c: char| c == '/' || c == '?') {
                    Some(idx) => (&rest_no_frag[..idx], &rest_no_frag[idx..]),
                    None => (rest_no_frag, "/"),
                };
            // Credentials before the last `@` are not part of the host, as in
            // WHATWG URL: `https://x@acme.slack.com/` has hostname
            // acme.slack.com.
            let authority = match authority.rsplit_once('@') {
                Some((_, host)) => host,
                None => authority,
            };
            if authority.is_empty() || authority.contains(' ') {
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

            let pathname = if special {
                remove_dot_segments(raw_path)
            } else {
                raw_path.to_string()
            };

            Ok(ParsedUrl {
                protocol,
                hostname,
                port,
                pathname,
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

    /// Resolves `.` and `..` path segments the way the WHATWG URL parser
    /// does for special schemes, so `/archives/X/../C1/p1` reads as
    /// `/archives/C1/p1`, as it did to `new URL` in the TypeScript server.
    fn remove_dot_segments(path: &str) -> String {
        let is_single = |s: &str| s == "." || s.eq_ignore_ascii_case("%2e");
        let is_double = |s: &str| {
            matches!(
                s.to_ascii_lowercase().as_str(),
                ".." | ".%2e" | "%2e." | "%2e%2e"
            )
        };
        let segments: Vec<&str> = path.strip_prefix('/').unwrap_or(path).split('/').collect();
        let last = segments.len().saturating_sub(1);
        let mut out: Vec<&str> = Vec::new();
        for (i, seg) in segments.iter().enumerate() {
            if is_double(seg) {
                out.pop();
                if i == last {
                    out.push("");
                }
            } else if is_single(seg) {
                if i == last {
                    out.push("");
                }
            } else {
                out.push(seg);
            }
        }
        format!("/{}", out.join("/"))
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

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn normalises_input_like_the_whatwg_parser() {
            let u = ParsedUrl::parse("  https://acme.slack.com/archives/C1/p1700000000123456\n")
                .unwrap();
            assert_eq!(u.hostname, "acme.slack.com");
            assert_eq!(u.pathname, "/archives/C1/p1700000000123456");

            let u = ParsedUrl::parse("https://acme.slack.com/arch\tives/C1/p1").unwrap();
            assert_eq!(u.pathname, "/archives/C1/p1");

            let u = ParsedUrl::parse("https://user:pw@acme.slack.com/x").unwrap();
            assert_eq!(u.hostname, "acme.slack.com");

            let u = ParsedUrl::parse("https://acme.slack.com\\archives\\C1").unwrap();
            assert_eq!(u.hostname, "acme.slack.com");
            assert_eq!(u.pathname, "/archives/C1");

            let u = ParsedUrl::parse("https://acme.slack.com/archives/X/../C1/./p1").unwrap();
            assert_eq!(u.pathname, "/archives/C1/p1");
            let u = ParsedUrl::parse("https://acme.slack.com/a/b/..").unwrap();
            assert_eq!(u.pathname, "/a/");

            let u = ParsedUrl::parse("https://acme.slack.com?thread_ts=1/2").unwrap();
            assert_eq!(u.hostname, "acme.slack.com");
            assert_eq!(u.pathname, "/");
            assert_eq!(u.query_get("thread_ts"), Some("1/2"));
        }

        #[test]
        fn encodes_query_like_urlsearchparams() {
            // String(new URLSearchParams({q: "a b&c=d/é*~"}))
            assert_eq!(
                encode_query_params(&[("q", "a b&c=d/é*~".to_string())]),
                "q=a+b%26c%3Dd%2F%C3%A9*%7E"
            );
        }
    }
}
