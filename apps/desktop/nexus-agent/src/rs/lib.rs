// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
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

//! Native Rust implementation of the Nexus Agent Antigravity bridge, formatter,
//! session store, annotation reader, dotenv loader, and Telegram bot engine.

pub mod agy;
pub mod annotations;
pub mod bot;
pub mod formatter;
pub mod sessions;

use std::collections::BTreeMap;

// ─── Minimal Zero-Dependency JSON Parser & Serializer ────────────────────────

#[derive(Debug, Clone, PartialEq)]
pub enum JsonValue {
    Null,
    Bool(bool),
    Number(f64),
    String(String),
    Array(Vec<JsonValue>),
    Object(Vec<(String, JsonValue)>),
}

impl JsonValue {
    pub fn parse(input: &str) -> Result<JsonValue, String> {
        let chars: Vec<char> = input.chars().collect();
        let mut pos = 0;
        skip_ws(&chars, &mut pos);
        if pos >= chars.len() {
            return Err("Unexpected end of JSON input".to_string());
        }
        let val = parse_value(&chars, &mut pos)?;
        skip_ws(&chars, &mut pos);
        if pos < chars.len() {
            return Err(format!("Trailing characters at position {}", pos));
        }
        Ok(val)
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

    pub fn as_f64(&self) -> Option<f64> {
        match self {
            JsonValue::Number(n) => Some(*n),
            _ => None,
        }
    }

    pub fn as_i64(&self) -> Option<i64> {
        match self {
            JsonValue::Number(n) => Some(*n as i64),
            _ => None,
        }
    }

    pub fn as_array(&self) -> Option<&[JsonValue]> {
        match self {
            JsonValue::Array(arr) => Some(arr.as_slice()),
            _ => None,
        }
    }

    pub fn as_object(&self) -> Option<&[(String, JsonValue)]> {
        match self {
            JsonValue::Object(entries) => Some(entries.as_slice()),
            _ => None,
        }
    }

    pub fn get(&self, key: &str) -> Option<&JsonValue> {
        match self {
            JsonValue::Object(entries) => {
                entries.iter().rev().find(|(k, _)| k == key).map(|(_, v)| v)
            }
            _ => None,
        }
    }

    pub fn is_null(&self) -> bool {
        matches!(self, JsonValue::Null)
    }

    pub fn to_json_pretty(&self, indent: usize) -> String {
        let pad = "  ".repeat(indent);
        let inner_pad = "  ".repeat(indent + 1);
        match self {
            JsonValue::Null => "null".to_string(),
            JsonValue::Bool(b) => b.to_string(),
            JsonValue::Number(n) => {
                if n.fract() == 0.0 && n.is_finite() {
                    format!("{}", *n as i64)
                } else {
                    format!("{}", n)
                }
            }
            JsonValue::String(s) => escape_json_string(s),
            JsonValue::Array(arr) => {
                if arr.is_empty() {
                    "[]".to_string()
                } else {
                    let items: Vec<String> = arr
                        .iter()
                        .map(|v| format!("{}{}", inner_pad, v.to_json_pretty(indent + 1)))
                        .collect();
                    format!("[\n{}\n{}]", items.join(",\n"), pad)
                }
            }
            JsonValue::Object(entries) => {
                if entries.is_empty() {
                    "{}".to_string()
                } else {
                    let items: Vec<String> = entries
                        .iter()
                        .map(|(k, v)| {
                            format!(
                                "{}{}: {}",
                                inner_pad,
                                escape_json_string(k),
                                v.to_json_pretty(indent + 1)
                            )
                        })
                        .collect();
                    format!("{{\n{}\n{}}}", items.join(",\n"), pad)
                }
            }
        }
    }

    pub fn to_json_compact(&self) -> String {
        match self {
            JsonValue::Null => "null".to_string(),
            JsonValue::Bool(b) => b.to_string(),
            JsonValue::Number(n) => {
                if n.fract() == 0.0 && n.is_finite() {
                    format!("{}", *n as i64)
                } else {
                    format!("{}", n)
                }
            }
            JsonValue::String(s) => escape_json_string(s),
            JsonValue::Array(arr) => {
                let items: Vec<String> = arr.iter().map(|v| v.to_json_compact()).collect();
                format!("[{}]", items.join(","))
            }
            JsonValue::Object(entries) => {
                let items: Vec<String> = entries
                    .iter()
                    .map(|(k, v)| format!("{}:{}", escape_json_string(k), v.to_json_compact()))
                    .collect();
                format!("{{{}}}", items.join(","))
            }
        }
    }
}

pub fn escape_json_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
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
    out
}

fn skip_ws(chars: &[char], pos: &mut usize) {
    while *pos < chars.len() && matches!(chars[*pos], ' ' | '\t' | '\n' | '\r') {
        *pos += 1;
    }
}

fn parse_value(chars: &[char], pos: &mut usize) -> Result<JsonValue, String> {
    skip_ws(chars, pos);
    if *pos >= chars.len() {
        return Err("Unexpected EOF".to_string());
    }
    match chars[*pos] {
        '"' => parse_string(chars, pos).map(JsonValue::String),
        '{' => parse_object(chars, pos),
        '[' => parse_array(chars, pos),
        't' => {
            if chars[*pos..].starts_with(&['t', 'r', 'u', 'e']) {
                *pos += 4;
                Ok(JsonValue::Bool(true))
            } else {
                Err(format!("Invalid token at {}", *pos))
            }
        }
        'f' => {
            if chars[*pos..].starts_with(&['f', 'a', 'l', 's', 'e']) {
                *pos += 5;
                Ok(JsonValue::Bool(false))
            } else {
                Err(format!("Invalid token at {}", *pos))
            }
        }
        'n' => {
            if chars[*pos..].starts_with(&['n', 'u', 'l', 'l']) {
                *pos += 4;
                Ok(JsonValue::Null)
            } else {
                Err(format!("Invalid token at {}", *pos))
            }
        }
        c if c == '-' || c.is_ascii_digit() => parse_number(chars, pos),
        c => Err(format!("Unexpected character '{}' at {}", c, *pos)),
    }
}

fn parse_string(chars: &[char], pos: &mut usize) -> Result<String, String> {
    if chars[*pos] != '"' {
        return Err(format!("Expected '\"' at {}", *pos));
    }
    *pos += 1;
    let mut out = String::new();
    while *pos < chars.len() {
        let c = chars[*pos];
        *pos += 1;
        if c == '"' {
            return Ok(out);
        }
        if c == '\\' {
            if *pos >= chars.len() {
                return Err("Unterminated escape in string".to_string());
            }
            let esc = chars[*pos];
            *pos += 1;
            match esc {
                '"' => out.push('"'),
                '\\' => out.push('\\'),
                '/' => out.push('/'),
                'b' => out.push('\u{08}'),
                'f' => out.push('\u{0C}'),
                'n' => out.push('\n'),
                'r' => out.push('\r'),
                't' => out.push('\t'),
                'u' => {
                    if *pos + 4 > chars.len() {
                        return Err("Incomplete unicode escape".to_string());
                    }
                    let hex: String = chars[*pos..*pos + 4].iter().collect();
                    *pos += 4;
                    let code = u16::from_str_radix(&hex, 16)
                        .map_err(|_| format!("Invalid unicode escape \\u{}", hex))?;
                    if (0xD800..=0xDBFF).contains(&code) {
                        if *pos + 6 <= chars.len() && chars[*pos] == '\\' && chars[*pos + 1] == 'u'
                        {
                            let low_hex: String = chars[*pos + 2..*pos + 6].iter().collect();
                            if let Ok(low) = u16::from_str_radix(&low_hex, 16) {
                                if (0xDC00..=0xDFFF).contains(&low) {
                                    *pos += 6;
                                    let combined = 0x10000
                                        + (((code as u32 - 0xD800) << 10) | (low as u32 - 0xDC00));
                                    if let Some(ch) = char::from_u32(combined) {
                                        out.push(ch);
                                        continue;
                                    }
                                }
                            }
                        }
                    }
                    let ch = char::from_u32(code as u32)
                        .ok_or_else(|| format!("Invalid unicode scalar \\u{}", hex))?;
                    out.push(ch);
                }
                other => out.push(other),
            }
        } else {
            out.push(c);
        }
    }
    Err("Unterminated string literal".to_string())
}

fn parse_number(chars: &[char], pos: &mut usize) -> Result<JsonValue, String> {
    let start = *pos;
    if chars[*pos] == '-' {
        *pos += 1;
    }
    while *pos < chars.len() && chars[*pos].is_ascii_digit() {
        *pos += 1;
    }
    if *pos < chars.len() && chars[*pos] == '.' {
        *pos += 1;
        while *pos < chars.len() && chars[*pos].is_ascii_digit() {
            *pos += 1;
        }
    }
    if *pos < chars.len() && (chars[*pos] == 'e' || chars[*pos] == 'E') {
        *pos += 1;
        if *pos < chars.len() && (chars[*pos] == '+' || chars[*pos] == '-') {
            *pos += 1;
        }
        while *pos < chars.len() && chars[*pos].is_ascii_digit() {
            *pos += 1;
        }
    }
    let s: String = chars[start..*pos].iter().collect();
    let n = s
        .parse::<f64>()
        .map_err(|e| format!("Invalid number '{}': {}", s, e))?;
    Ok(JsonValue::Number(n))
}

fn parse_array(chars: &[char], pos: &mut usize) -> Result<JsonValue, String> {
    *pos += 1; // skip '['
    skip_ws(chars, pos);
    let mut items = Vec::new();
    if *pos < chars.len() && chars[*pos] == ']' {
        *pos += 1;
        return Ok(JsonValue::Array(items));
    }
    loop {
        let val = parse_value(chars, pos)?;
        items.push(val);
        skip_ws(chars, pos);
        if *pos >= chars.len() {
            return Err("Unterminated array".to_string());
        }
        if chars[*pos] == ']' {
            *pos += 1;
            return Ok(JsonValue::Array(items));
        }
        if chars[*pos] != ',' {
            return Err(format!("Expected ',' or ']' at {}", *pos));
        }
        *pos += 1;
    }
}

fn parse_object(chars: &[char], pos: &mut usize) -> Result<JsonValue, String> {
    *pos += 1; // skip '{'
    skip_ws(chars, pos);
    let mut entries = Vec::new();
    if *pos < chars.len() && chars[*pos] == '}' {
        *pos += 1;
        return Ok(JsonValue::Object(entries));
    }
    loop {
        skip_ws(chars, pos);
        let key = parse_string(chars, pos)?;
        skip_ws(chars, pos);
        if *pos >= chars.len() || chars[*pos] != ':' {
            return Err(format!("Expected ':' at {}", *pos));
        }
        *pos += 1;
        let val = parse_value(chars, pos)?;
        entries.push((key, val));
        skip_ws(chars, pos);
        if *pos >= chars.len() {
            return Err("Unterminated object".to_string());
        }
        if chars[*pos] == '}' {
            *pos += 1;
            return Ok(JsonValue::Object(entries));
        }
        if chars[*pos] != ',' {
            return Err(format!("Expected ',' or '}}' at {}", *pos));
        }
        *pos += 1;
    }
}

// ─── Dotenv Parser & Encoder (100% compatible with npm `dotenv` & Swift Core) ─

/// Parse a whole `.env` file content into a key-value map, splitting lines only
/// at `\n`, `\r\n`, or `\r` (never at U+2028, U+2029, U+0085, `\f`, or `\v`),
/// with later lines winning over earlier ones.
pub fn dotenv_parse(content: &str) -> BTreeMap<String, String> {
    let mut values = BTreeMap::new();
    for line in dotenv_lines(content) {
        if let Some((k, v)) = dotenv_parse_line(&line) {
            values.insert(k, v);
        }
    }
    values
}

/// Split content into lines ending only at `\n`, `\r\n`, or `\r`.
pub fn dotenv_lines(content: &str) -> Vec<String> {
    let mut lines = Vec::new();
    let mut current = String::new();
    let mut chars = content.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '\n' => {
                lines.push(std::mem::take(&mut current));
            }
            '\r' => {
                if chars.peek() == Some(&'\n') {
                    chars.next();
                }
                lines.push(std::mem::take(&mut current));
            }
            other => current.push(other),
        }
    }
    if !current.is_empty() {
        lines.push(current);
    }
    lines
}

/// Parse a single `.env` line according to `dotenv` rules.
pub fn dotenv_parse_line(line: &str) -> Option<(String, String)> {
    let mut text: Vec<char> = line.chars().collect();
    if let Some(end) = text.iter().position(|&c| c == '\n' || c == '\r') {
        text.truncate(end);
    }
    let mut start = 0;
    while start < text.len() && is_js_space(text[start]) {
        start += 1;
    }
    let export_kw = ['e', 'x', 'p', 'o', 'r', 't'];
    if text[start..].starts_with(&export_kw) {
        let mut after_export = start + export_kw.len();
        if after_export < text.len() && is_js_space(text[after_export]) {
            while after_export < text.len() && is_js_space(text[after_export]) {
                after_export += 1;
            }
            if let Some(pair) = dotenv_key_and_value(&text, after_export) {
                return Some(pair);
            }
        }
    }
    dotenv_key_and_value(&text, start)
}

fn dotenv_key_and_value(text: &[char], start: usize) -> Option<(String, String)> {
    let mut index = start;
    while index < text.len() && is_dotenv_key_char(text[index]) {
        index += 1;
    }
    if index == start {
        return None;
    }
    let key: String = text[start..index].iter().collect();
    if index < text.len() && text[index] == ':' {
        if index + 1 >= text.len() || !is_js_space(text[index + 1]) {
            return None;
        }
        index += 2;
    } else {
        while index < text.len() && is_js_space(text[index]) {
            index += 1;
        }
        if index >= text.len() || text[index] != '=' {
            return None;
        }
        index += 1;
    }
    Some((key, dotenv_value(text, index)))
}

fn dotenv_value(text: &[char], start: usize) -> String {
    let mut open = start;
    while open < text.len() && is_js_space(text[open]) {
        open += 1;
    }
    let mut raw: &[char] = if open < text.len() && is_dotenv_quote(text[open]) {
        if let Some(close) = dotenv_closing_quote(text, open) {
            &text[open..=close]
        } else {
            let end = text[start..]
                .iter()
                .position(|&c| c == '#')
                .map(|p| start + p)
                .unwrap_or(text.len());
            &text[start..end]
        }
    } else {
        let end = text[start..]
            .iter()
            .position(|&c| c == '#')
            .map(|p| start + p)
            .unwrap_or(text.len());
        &text[start..end]
    };

    while let Some(&first) = raw.first() {
        if is_js_space(first) {
            raw = &raw[1..];
        } else {
            break;
        }
    }
    while let Some(&last) = raw.last() {
        if is_js_space(last) {
            raw = &raw[..raw.len() - 1];
        } else {
            break;
        }
    }

    let first = raw.first().copied();
    if raw.len() >= 2 {
        if let Some(f) = first {
            if is_dotenv_quote(f) && raw.last() == Some(&f) {
                raw = &raw[1..raw.len() - 1];
            }
        }
    }

    let mut value: String = raw.iter().collect();
    if first == Some('"') {
        value = value.replace("\\n", "\n").replace("\\r", "\r");
    }
    value
}

fn dotenv_closing_quote(text: &[char], open: usize) -> Option<usize> {
    let quote = text[open];
    let mut candidates = Vec::new();
    let mut index = open + 1;
    while index < text.len() {
        if text[index] == quote {
            candidates.push(index);
            let escaped = index - 1 > open && text[index - 1] == '\\';
            if !escaped {
                break;
            }
        }
        index += 1;
    }
    candidates.into_iter().rev().find(|&close| {
        let mut rest = close + 1;
        while rest < text.len() && is_js_space(text[rest]) {
            rest += 1;
        }
        rest == text.len() || text[rest] == '#'
    })
}

fn is_dotenv_quote(c: char) -> bool {
    matches!(c, '"' | '\'' | '`')
}

fn is_dotenv_key_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '-')
}

fn is_js_space(c: char) -> bool {
    matches!(
        c as u32,
        0x09..=0x0D
            | 0x20
            | 0xA0
            | 0x1680
            | 0x2000..=0x200A
            | 0x2028
            | 0x2029
            | 0x202F
            | 0x205F
            | 0x3000
            | 0xFEFF
    )
}

/// Encode a single-line `.env` value so `dotenv` reads it back unchanged.
pub fn dotenv_encode_value(value: &str) -> String {
    let flat: String = value.chars().filter(|&c| c != '\n' && c != '\r').collect();
    let reads_back = |written: &str| -> bool {
        dotenv_parse_line(&format!("K={}", written))
            .map(|(_, v)| v == flat)
            .unwrap_or(false)
    };
    let trimmed = flat.trim_matches(|c: char| c == ' ' || c == '\t');
    let needs_quotes = flat.contains('#')
        || flat.starts_with('"')
        || flat.starts_with('\'')
        || flat.starts_with('`')
        || flat != trimmed;
    if !needs_quotes && reads_back(&flat) {
        return flat;
    }
    let quotes = if flat.contains('\'') {
        ["\"", "`", "'"]
    } else {
        ["'", "\"", "`"]
    };
    let spellings: Vec<String> = quotes
        .iter()
        .map(|q| format!("{}{}{}", q, flat, q))
        .collect();
    spellings
        .iter()
        .find(|s| reads_back(s))
        .cloned()
        .unwrap_or_else(|| spellings[0].clone())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::agy::{
        approval_args, build_agy_args, build_provider_args, clean_cli_output, extract_file_paths,
        extract_image_paths, extract_semver, format_plugin_list, friendly_error, handle_result,
        list_skills_in_roots, mentions_unknown_conversation, parse_agy_output, parse_models,
        parse_stream_line, relative_time_from_diff_ms, ChatSettings, RunningProcessInfo,
    };
    use crate::bot::{
        format_document_prompt, format_photo_prompt, format_reply_context_prompt,
        format_voice_prompt, is_user_authorized, parse_allowed_user_ids, BotEngine, BOT_COMMANDS,
    };
    use crate::formatter::markdown_to_telegram_html;
    use std::env;
    use std::fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn make_temp_dir(prefix: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = env::temp_dir().join(format!("{}-{}-{}", prefix, std::process::id(), nanos));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn test_agy_friendly_error_and_unknown_conversation() {
        assert_eq!(
            friendly_error("Error: 503 Service Unavailable"),
            "Antigravity is temporarily unavailable (503). Try again in a moment."
        );
        assert_eq!(
            friendly_error("User is not signed in (401)"),
            "agy is not signed in. Run `agy` in a terminal on the Mac and sign in, then try again."
        );
        assert_eq!(
            friendly_error("spawn agy ENOENT"),
            "agy was not found. Install the Antigravity CLI from https://antigravity.google and run `agy install`."
        );
        assert_eq!(friendly_error("custom failure"), "custom failure");
        assert_eq!(friendly_error("   "), "unknown error");

        assert!(mentions_unknown_conversation(
            "warning: conversation \"abc-123\" not found"
        ));
        assert!(!mentions_unknown_conversation("all good"));
    }

    #[test]
    fn test_agy_provider_args_and_clean_cli_output() {
        let cmd = build_provider_args(
            "ollama launch claude --model {model} -- -p \"{prompt}\"",
            "hello world",
            "",
        )
        .unwrap();
        assert_eq!(cmd.bin, "ollama");
        assert_eq!(
            cmd.args,
            vec![
                "launch",
                "claude",
                "--model",
                "gemma4:31b-cloud",
                "--",
                "-p",
                "hello world"
            ]
        );

        let noisy = "npm warn deprecated\nTelemetry initialized\nLoading plugin: x\nServer 'mcp' supports tools\nReal output line\n";
        assert_eq!(clean_cli_output(noisy), "Real output line");
    }

    #[test]
    fn test_agy_stream_and_json_parsing_and_handle_result() {
        let init =
            parse_stream_line("{\"event\":\"init\",\"conversation_id\":\"conv-1\"}").unwrap();
        assert_eq!(init.session_id.as_deref(), Some("conv-1"));

        let delta = parse_stream_line(
            "{\"event\":\"step_update\",\"step_update\":{\"step_type\":\"agent_response\",\"text_delta\":\"Hello\"}}",
        )
        .unwrap();
        assert_eq!(delta.delta.as_deref(), Some("Hello"));

        let res_line = parse_stream_line(
            "{\"event\":\"result\",\"result\":{\"conversation_id\":\"conv-1\",\"status\":\"SUCCESS\",\"response\":\"Done\"}}",
        )
        .unwrap();
        assert_eq!(res_line.session_id.as_deref(), Some("conv-1"));
        assert!(res_line.result.is_some());

        let parsed = parse_agy_output(
            "{\"result\":{\"conversation_id\":\"c2\",\"status\":\"SUCCESS\",\"response\":\"Hi there\"}}",
        )
        .unwrap();
        assert_eq!(parsed.text, "Hi there");
        assert_eq!(parsed.session_id.as_deref(), Some("c2"));

        let err_json = JsonValue::parse(
            "{\"status\":\"ERROR\",\"error\":\"Conversation not found on server\"}",
        )
        .unwrap();
        let mut cleared = None;
        let res = handle_result(&err_json, Some(42), |cid| cleared = Some(cid));
        assert!(res.is_err());
        assert_eq!(cleared, Some(42));
        assert!(res.unwrap_err().contains("Conversation expired"));
    }

    #[test]
    fn test_agy_models_plugins_skills_and_file_extraction() {
        let models = parse_models("Fetching models...\ngemini-2.5-pro\tGemini 2.5 Pro\nclaude-4\n");
        assert_eq!(models.len(), 2);
        assert_eq!(models[0].id, "gemini-2.5-pro");
        assert_eq!(models[0].name, "Gemini 2.5 Pro");
        assert_eq!(models[1].id, "claude-4");
        assert_eq!(models[1].name, "claude-4");

        let plugins = format_plugin_list(
            "{\"imports\":[{\"name\":\"live-context\",\"source\":\"gh\",\"components\":[\"rules\",\"hooks\"]}]}",
        );
        assert_eq!(plugins, "• live-context from gh (rules, hooks)");
        assert_eq!(format_plugin_list("{}"), "No plugins installed.");

        let tmp = make_temp_dir("nexus-lib-test");
        let skill_dir = tmp.join("skills/my-skill");
        fs::create_dir_all(&skill_dir).unwrap();
        fs::write(skill_dir.join("SKILL.md"), "# Skill").unwrap();
        assert_eq!(list_skills_in_roots(&[tmp.join("skills")]), "• my-skill");

        let img_path = tmp.join("chart.png");
        let doc_path = tmp.join("report.md");
        fs::write(&img_path, "png").unwrap();
        fs::write(&doc_path, "# report").unwrap();
        let text = format!(
            "Generated {} and file://{}",
            img_path.display(),
            doc_path.display()
        );
        assert_eq!(extract_image_paths(&text), vec![img_path.to_string_lossy()]);
        assert_eq!(extract_file_paths(&text), vec![doc_path.to_string_lossy()]);

        assert_eq!(
            extract_semver("agy version 1.19.2 (darwin)"),
            Some("1.19.2".to_string())
        );
        assert_eq!(relative_time_from_diff_ms(10_000), "just now");
        assert_eq!(relative_time_from_diff_ms(180_000), "3m ago");
        assert_eq!(relative_time_from_diff_ms(7_200_000), "2h ago");
        assert_eq!(relative_time_from_diff_ms(172_800_000), "2d ago");

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_bot_commands_callbacks_and_auth() {
        assert_eq!(BOT_COMMANDS.len(), 19);
        assert_eq!(parse_allowed_user_ids("101, 202 , "), vec![101, 202]);
        assert!(is_user_authorized(Some(101), &[101, 202]));
        assert!(!is_user_authorized(Some(999), &[101, 202]));
        assert!(is_user_authorized(Some(999), &[]));

        let tmp = make_temp_dir("nexus-bot-engine");
        let env_text =
            "TELEGRAM_BOT_TOKEN=test:token\nALLOWED_USER_IDS=100\nAGY_APPROVAL_MODE=plan\n";
        let engine =
            BotEngine::from_dotenv_and_env(env_text, &BTreeMap::new(), &tmp.to_string_lossy());

        // Unauthorized user
        let unauth = engine.handle_command(1, Some(999), Some("Eve"), "/start");
        assert_eq!(
            unauth.messages[0].text,
            "⛔ You are not authorized to use this bot."
        );

        // /start and /help
        let start = engine.handle_command(1, Some(100), Some("Alice"), "/start");
        assert!(start.messages[0].text.contains("👋 Hi Alice!"));
        let help = engine.handle_command(1, Some(100), Some("Alice"), "/help");
        assert!(help.messages[0].text.contains("━━━ Session Commands ━━━"));

        // /mode, /effort, /sandbox, /thinking
        let mode_out = engine.handle_command(1, Some(100), None, "/mode accept-edits");
        assert_eq!(
            mode_out.messages[0].text,
            "⚙️ Approval mode set to: accept-edits"
        );
        assert_eq!(
            engine.bridge.get_chat_settings(1).approval_mode,
            "accept-edits"
        );

        let effort_out = engine.handle_command(1, Some(100), None, "/effort high");
        assert_eq!(effort_out.messages[0].text, "🧠 Effort set to: high");
        assert_eq!(engine.bridge.get_chat_settings(1).effort, "high");
        assert!(engine.bridge.get_chat_settings(1).thinking);

        let sb_out = engine.handle_command(1, Some(100), None, "/sandbox");
        assert!(sb_out.messages[0].text.contains("ON ✅"));
        assert!(engine.bridge.get_chat_settings(1).sandbox);

        // /workdir save, list, switch, remove
        let save_ws = engine.handle_command(1, Some(100), None, "/workdir save myproj");
        assert!(save_ws.messages[0].text.contains("💾 Saved \"myproj\""));
        let list_ws = engine.handle_command(1, Some(100), None, "/workdir");
        assert_eq!(list_ws.messages[0].inline_keyboard.len(), 1);
        let cb_ws = engine.handle_callback(1, Some(100), "workdir_switch_myproj");
        assert_eq!(
            cb_ws.callback_answer.as_deref(),
            Some("📂 Switched to myproj")
        );

        // /name and /session and /new
        let name_out = engine.handle_command(1, Some(100), None, "/name Auth Refactor");
        assert_eq!(
            name_out.messages[0].text,
            "📛 Session named: \"Auth Refactor\""
        );
        let get_name = engine.handle_command(1, Some(100), None, "/name");
        assert!(get_name.messages[0].text.contains("\"Auth Refactor\""));

        // /status and check_status callback
        engine.bridge.register_running_process_for_test(
            1,
            RunningProcessInfo {
                pid: 999999,
                start_time_ms: crate::agy::now_ms().saturating_sub(5000),
                prompt: "explain rust".to_string(),
            },
        );
        let status_out = engine.handle_command(1, Some(100), None, "/status");
        assert!(status_out.messages[0]
            .text
            .contains("⏳ Request in progress"));
        let cb_status = engine.handle_callback(1, Some(100), "check_status");
        assert!(cb_status
            .callback_answer
            .as_deref()
            .unwrap()
            .contains("⏱️ Running for"));

        // Media & reply context prompt builders
        assert!(
            format_reply_context_prompt("follow up", Some("earlier answer"))
                .contains("Previous assistant response:")
        );
        assert!(format_photo_prompt("/tmp/a.jpg", None).contains("Describe this image."));
        assert!(
            format_document_prompt("/tmp/a.pdf", "a.pdf", "application/pdf", None)
                .contains("Review this file: a.pdf")
        );
        assert!(format_voice_prompt("/tmp/v.oga").contains("listen to/transcribe this audio"));

        // Markdown tables & blockquotes & lists
        let md = "| A | B |\n|---|---|\n| 1 | 2 |\n\n> quote 1\n> quote 2\n\n- item 1\n  - item 2";
        let html = markdown_to_telegram_html(md);
        assert!(html.contains("<pre>"));
        assert!(html.contains("<blockquote>quote 1\nquote 2</blockquote>"));
        assert!(html.contains("• item 1"));
        assert!(html.contains("  ◦ item 2"));

        let settings = ChatSettings {
            working_dir: "/tmp".to_string(),
            model: "m1".to_string(),
            approval_mode: "yolo".to_string(),
            sandbox: true,
            thinking: false,
            effort: "low".to_string(),
        };
        let args = build_agy_args("hi", &settings, "json", Some("conv-9"), Some(300_000));
        assert_eq!(
            args,
            vec![
                "-p",
                "hi",
                "--output-format",
                "json",
                "--dangerously-skip-permissions",
                "--model",
                "m1",
                "--effort",
                "low",
                "--sandbox",
                "--conversation",
                "conv-9",
                "--print-timeout",
                "300s"
            ]
        );
        assert_eq!(approval_args("auto_edit"), vec!["--mode", "accept-edits"]);

        let _ = fs::remove_dir_all(&tmp);
    }
}
