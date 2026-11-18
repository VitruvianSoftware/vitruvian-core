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

use std::collections::VecDeque;
use std::fs::{self, File};
use std::io::{self, BufRead, BufReader, BufWriter, Write};
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;

#[derive(Clone, Debug, PartialEq)]
enum JsonValue {
    Null,
    Bool(bool),
    Number(String),
    String(String),
    Array(Vec<JsonValue>),
    Object(Vec<(String, JsonValue)>),
}

struct JsonParser<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> JsonParser<'a> {
    fn new(input: &'a str) -> Self {
        Self {
            bytes: input.as_bytes(),
            pos: 0,
        }
    }

    fn skip_ws(&mut self) {
        while self.pos < self.bytes.len() && self.bytes[self.pos].is_ascii_whitespace() {
            self.pos += 1;
        }
    }

    fn parse(&mut self) -> Result<JsonValue, ()> {
        self.skip_ws();
        let val = self.parse_value()?;
        self.skip_ws();
        if self.pos == self.bytes.len() {
            Ok(val)
        } else {
            Err(())
        }
    }

    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.pos).copied()
    }

    fn parse_value(&mut self) -> Result<JsonValue, ()> {
        self.skip_ws();
        match self.peek() {
            Some(b'n') => self.expect_literal(b"null", JsonValue::Null),
            Some(b't') => self.expect_literal(b"true", JsonValue::Bool(true)),
            Some(b'f') => self.expect_literal(b"false", JsonValue::Bool(false)),
            Some(b'"') => self.parse_string().map(JsonValue::String),
            Some(b'[') => self.parse_array(),
            Some(b'{') => self.parse_object(),
            Some(b'-' | b'0'..=b'9') => self.parse_number(),
            _ => Err(()),
        }
    }

    fn expect_literal(&mut self, lit: &[u8], out: JsonValue) -> Result<JsonValue, ()> {
        if self.bytes[self.pos..].starts_with(lit) {
            self.pos += lit.len();
            Ok(out)
        } else {
            Err(())
        }
    }

    fn parse_string(&mut self) -> Result<String, ()> {
        if self.peek() != Some(b'"') {
            return Err(());
        }
        self.pos += 1;
        let mut out = String::new();
        while self.pos < self.bytes.len() {
            let b = self.bytes[self.pos];
            self.pos += 1;
            match b {
                b'"' => return Ok(out),
                b'\\' => {
                    if self.pos >= self.bytes.len() {
                        return Err(());
                    }
                    let esc = self.bytes[self.pos];
                    self.pos += 1;
                    match esc {
                        b'"' => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'/' => out.push('/'),
                        b'b' => out.push('\x08'),
                        b'f' => out.push('\x0c'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => {
                            let code = self.parse_hex4()?;
                            if (0xD800..=0xDBFF).contains(&code) {
                                if self.bytes.get(self.pos..self.pos + 2) != Some(b"\\u") {
                                    return Err(());
                                }
                                self.pos += 2;
                                let low = self.parse_hex4()?;
                                if !(0xDC00..=0xDFFF).contains(&low) {
                                    return Err(());
                                }
                                let combined = 0x10000
                                    + (((code as u32 - 0xD800) << 10) | (low as u32 - 0xDC00));
                                out.push(char::from_u32(combined).ok_or(())?);
                            } else {
                                out.push(char::from_u32(code as u32).ok_or(())?);
                            }
                        }
                        _ => return Err(()),
                    }
                }
                _ => {
                    // Decode UTF-8 sequence starting from b
                    let start = self.pos - 1;
                    let width = if b < 0x80 {
                        1
                    } else if b & 0xE0 == 0xC0 {
                        2
                    } else if b & 0xF0 == 0xE0 {
                        3
                    } else if b & 0xF8 == 0xF0 {
                        4
                    } else {
                        return Err(());
                    };
                    let end = start + width;
                    if end > self.bytes.len() {
                        return Err(());
                    }
                    let ch = std::str::from_utf8(&self.bytes[start..end])
                        .map_err(|_| ())?
                        .chars()
                        .next()
                        .ok_or(())?;
                    out.push(ch);
                    self.pos = end;
                }
            }
        }
        Err(())
    }

    fn parse_hex4(&mut self) -> Result<u16, ()> {
        if self.pos + 4 > self.bytes.len() {
            return Err(());
        }
        let s = std::str::from_utf8(&self.bytes[self.pos..self.pos + 4]).map_err(|_| ())?;
        self.pos += 4;
        u16::from_str_radix(s, 16).map_err(|_| ())
    }

    fn parse_number(&mut self) -> Result<JsonValue, ()> {
        let start = self.pos;
        if self.peek() == Some(b'-') {
            self.pos += 1;
        }
        match self.peek() {
            Some(b'0') => self.pos += 1,
            Some(b'1'..=b'9') => {
                while matches!(self.peek(), Some(b'0'..=b'9')) {
                    self.pos += 1;
                }
            }
            _ => return Err(()),
        }
        if self.peek() == Some(b'.') {
            self.pos += 1;
            if !matches!(self.peek(), Some(b'0'..=b'9')) {
                return Err(());
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
                return Err(());
            }
            while matches!(self.peek(), Some(b'0'..=b'9')) {
                self.pos += 1;
            }
        }
        let slice = std::str::from_utf8(&self.bytes[start..self.pos]).map_err(|_| ())?;
        Ok(JsonValue::Number(slice.to_string()))
    }

    fn parse_array(&mut self) -> Result<JsonValue, ()> {
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
                Some(b',') => self.pos += 1,
                Some(b']') => {
                    self.pos += 1;
                    return Ok(JsonValue::Array(items));
                }
                _ => return Err(()),
            }
        }
    }

    fn parse_object(&mut self) -> Result<JsonValue, ()> {
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
                return Err(());
            }
            self.pos += 1;
            let value = self.parse_value()?;
            entries.push((key, value));
            self.skip_ws();
            match self.peek() {
                Some(b',') => self.pos += 1,
                Some(b'}') => {
                    self.pos += 1;
                    return Ok(JsonValue::Object(entries));
                }
                _ => return Err(()),
            }
        }
    }
}

fn push_json_escaped(out: &mut String, s: &str) {
    out.push('"');
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\x08' => out.push_str("\\b"),
            '\x0c' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                out.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

impl JsonValue {
    fn to_json_string(&self) -> String {
        let mut out = String::new();
        self.write_json(&mut out);
        out
    }

    fn write_json(&self, out: &mut String) {
        match self {
            JsonValue::Null => out.push_str("null"),
            JsonValue::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
            JsonValue::Number(n) => out.push_str(n),
            JsonValue::String(s) => push_json_escaped(out, s),
            JsonValue::Array(items) => {
                out.push('[');
                for (i, item) in items.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    item.write_json(out);
                }
                out.push(']');
            }
            JsonValue::Object(entries) => {
                out.push('{');
                for (i, (k, v)) in entries.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    push_json_escaped(out, k);
                    out.push(':');
                    v.write_json(out);
                }
                out.push('}');
            }
        }
    }

    fn get(&self, key: &str) -> Option<&JsonValue> {
        match self {
            JsonValue::Object(entries) => entries.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    fn set_object_key(&mut self, key: &str, value: JsonValue) {
        if let JsonValue::Object(entries) = self {
            for (k, v) in entries.iter_mut() {
                if k == key {
                    *v = value;
                    return;
                }
            }
            entries.push((key.to_string(), value));
        }
    }

    fn as_str(&self) -> Option<&str> {
        match self {
            JsonValue::String(s) => Some(s.as_str()),
            _ => None,
        }
    }
}

#[derive(Clone, Debug)]
struct Redactor {
    home: Option<String>,
    cwd: Option<String>,
}

impl Redactor {
    fn redact_string(&self, input: &str) -> String {
        let mut s = input.to_string();
        if let Some(cwd) = &self.cwd {
            if !cwd.is_empty() {
                s = s.replace(cwd, "/workspace");
            }
        }
        if let Some(home) = &self.home {
            if !home.is_empty() {
                s = s.replace(home, "/Users/redacted");
            }
        }
        s = redact_bearer_tokens(&s);
        s = redact_emails(&s);
        s
    }

    fn redact_value(&self, val: &mut JsonValue) {
        match val {
            JsonValue::String(s) => *s = self.redact_string(s),
            JsonValue::Array(items) => {
                for item in items {
                    self.redact_value(item);
                }
            }
            JsonValue::Object(entries) => {
                for (k, v) in entries {
                    let key_lower = k.to_ascii_lowercase();
                    if key_lower.contains("token")
                        || key_lower.contains("secret")
                        || key_lower.contains("apikey")
                        || key_lower.contains("api_key")
                        || key_lower == "authorization"
                    {
                        if matches!(v, JsonValue::String(_)) {
                            *v = JsonValue::String("[redacted-secret]".to_string());
                            continue;
                        }
                    }
                    self.redact_value(v);
                }
            }
            JsonValue::Null | JsonValue::Bool(_) | JsonValue::Number(_) => {}
        }
    }
}

fn is_token_boundary(byte: Option<u8>) -> bool {
    match byte {
        None => true,
        Some(b) => !(b.is_ascii_alphanumeric() || b == b'-' || b == b'_'),
    }
}

fn redact_bearer_tokens(input: &str) -> String {
    let mut out = input.to_string();
    for prefix in ["ya29.", "1//", "sk-", "gho_", "ghp_", "Bearer "] {
        let mut next = String::with_capacity(out.len());
        let mut rest = out.as_str();
        while let Some(idx) = rest.find(prefix) {
            let prev_byte = if idx > 0 { Some(rest.as_bytes()[idx - 1]) } else { None };
            if prefix == "sk-" && !is_token_boundary(prev_byte) {
                next.push_str(&rest[..idx + prefix.len()]);
                rest = &rest[idx + prefix.len()..];
                continue;
            }
            next.push_str(&rest[..idx]);
            next.push_str("[redacted-token]");
            let after = &rest[idx + prefix.len()..];
            let end = after
                .find(|c: char| !(c.is_ascii_alphanumeric() || "-_./~+=".contains(c)))
                .unwrap_or(after.len());
            rest = &after[end..];
        }
        next.push_str(rest);
        out = next;
    }
    out
}

fn is_email_char(b: u8) -> bool {
    b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'%' | b'+' | b'-')
}

fn redact_emails(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut result = String::with_capacity(input.len());
    let mut i = 0;
    while i < bytes.len() {
        if let Some(rel_at) = input[i..].find('@') {
            let at = i + rel_at;
            let mut local_start = at;
            while local_start > i && is_email_char(bytes[local_start - 1]) {
                local_start -= 1;
            }
            let mut domain_end = at + 1;
            while domain_end < bytes.len()
                && (bytes[domain_end].is_ascii_alphanumeric()
                    || bytes[domain_end] == b'.'
                    || bytes[domain_end] == b'-')
            {
                domain_end += 1;
            }
            let local = &input[local_start..at];
            let domain = &input[at + 1..domain_end];
            if !local.is_empty() && domain.contains('.') && !domain.ends_with('.') {
                result.push_str(&input[i..local_start]);
                result.push_str("redacted@example.com");
                i = domain_end;
                continue;
            }
            result.push_str(&input[i..=at]);
            i = at + 1;
        } else {
            result.push_str(&input[i..]);
            break;
        }
    }
    result
}

struct RecorderState {
    writer: BufWriter<File>,
    pending_client_ids: VecDeque<JsonValue>,
    redactor: Redactor,
}

impl RecorderState {
    fn write_line(&mut self, line: &str) {
        let _ = self.writer.write_all(line.as_bytes());
        let _ = self.writer.write_all(b"\n");
        let _ = self.writer.flush();
    }

    fn record_client_line(&mut self, line: &str) {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            return;
        }
        let Ok(mut val) = JsonParser::new(trimmed).parse() else {
            return;
        };
        let method = val.get("method").and_then(|v| v.as_str()).map(str::to_string);
        let id = val.get("id").cloned();

        if let Some(method_name) = method {
            if let Some(req_id) = id {
                self.pending_client_ids.push_back(req_id);
            }
            self.redactor.redact_value(&mut val);
            let record = JsonValue::Object(vec![
                ("direction".to_string(), JsonValue::String("client".to_string())),
                ("method".to_string(), JsonValue::String(method_name)),
                ("raw".to_string(), val),
            ]);
            self.write_line(&record.to_json_string());
        } else if let Some(resp_id) = id {
            self.redactor.redact_value(&mut val);
            let record = JsonValue::Object(vec![
                (
                    "direction".to_string(),
                    JsonValue::String("client_response".to_string()),
                ),
                ("id".to_string(), resp_id),
                ("raw".to_string(), val),
            ]);
            self.write_line(&record.to_json_string());
        }
    }

    fn record_agent_line(&mut self, line: &str) {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            return;
        }
        let Ok(mut val) = JsonParser::new(trimmed).parse() else {
            let redacted = self.redactor.redact_string(trimmed);
            let record = JsonValue::Object(vec![
                (
                    "direction".to_string(),
                    JsonValue::String("agent_stderr".to_string()),
                ),
                ("line".to_string(), JsonValue::String(redacted)),
            ]);
            self.write_line(&record.to_json_string());
            return;
        };
        let has_method = val.get("method").is_some();
        let has_id = val.get("id").is_some();
        if !has_method && has_id {
            if let Some(resp_id) = val.get("id").cloned() {
                if let Some(pos) = self.pending_client_ids.iter().position(|x| x == &resp_id) {
                    self.pending_client_ids.remove(pos);
                    val.set_object_key("id", JsonValue::String("$id".to_string()));
                }
            }
        }
        self.redactor.redact_value(&mut val);
        let record = JsonValue::Object(vec![
            ("direction".to_string(), JsonValue::String("agent".to_string())),
            ("send".to_string(), val),
        ]);
        self.write_line(&record.to_json_string());
    }

    fn record_stderr_line(&mut self, line: &str) {
        let trimmed = line.trim_end_matches(['\r', '\n']);
        if trimmed.is_empty() {
            return;
        }
        let redacted = self.redactor.redact_string(trimmed);
        let record = JsonValue::Object(vec![
            (
                "direction".to_string(),
                JsonValue::String("agent_stderr".to_string()),
            ),
            ("line".to_string(), JsonValue::String(redacted)),
        ]);
        self.write_line(&record.to_json_string());
    }
}

fn print_usage() {
    eprintln!(
        "Usage: record-acp-fixture <output.ndjson> [--redact-home <path>] [--redact-cwd <path>] -- <command> [args...]"
    );
}

pub fn run(args: &[String]) -> i32 {
    let rest = if args.len() > 1 { &args[1..] } else { &[] };
    if rest.is_empty() {
        print_usage();
        return 2;
    }

    let Some(dash_idx) = rest.iter().position(|a| a == "--") else {
        print_usage();
        return 2;
    };
    let options = &rest[..dash_idx];
    let cmd_args = &rest[dash_idx + 1..];
    if options.is_empty() || cmd_args.is_empty() {
        print_usage();
        return 2;
    }

    let output_path = &options[0];
    let mut redact_home = std::env::var("HOME").ok();
    let mut redact_cwd = std::env::current_dir()
        .ok()
        .and_then(|p| p.to_str().map(str::to_string));

    let mut idx = 1;
    while idx < options.len() {
        match options[idx].as_str() {
            "--redact-home" if idx + 1 < options.len() => {
                redact_home = Some(options[idx + 1].clone());
                idx += 2;
            }
            "--redact-cwd" if idx + 1 < options.len() => {
                redact_cwd = Some(options[idx + 1].clone());
                idx += 2;
            }
            _ => {
                print_usage();
                return 2;
            }
        }
    }

    if let Some(parent) = Path::new(output_path).parent() {
        if !parent.as_os_str().is_empty() {
            if let Err(err) = fs::create_dir_all(parent) {
                eprintln!("record-acp-fixture: cannot create fixture parent directory: {err}");
                return 1;
            }
        }
    }

    let file = match File::create(output_path) {
        Ok(f) => f,
        Err(err) => {
            eprintln!("record-acp-fixture: cannot create {output_path}: {err}");
            return 1;
        }
    };

    let mut child = match Command::new(&cmd_args[0])
        .args(&cmd_args[1..])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(err) => {
            eprintln!("record-acp-fixture: failed to spawn {}: {err}", cmd_args[0]);
            return 1;
        }
    };

    let state = Arc::new(Mutex::new(RecorderState {
        writer: BufWriter::new(file),
        pending_client_ids: VecDeque::new(),
        redactor: Redactor {
            home: redact_home,
            cwd: redact_cwd,
        },
    }));

    let mut child_stdin = child.stdin.take();
    let child_stdout = child.stdout.take();
    let child_stderr = child.stderr.take();

    let stdin_state = Arc::clone(&state);
    let stdin_thread = thread::spawn(move || {
        let stdin = io::stdin();
        let mut reader = BufReader::new(stdin.lock());
        let mut line = String::new();
        loop {
            line.clear();
            match reader.read_line(&mut line) {
                Ok(0) | Err(_) => break,
                Ok(_) => {
                    if let Ok(mut guard) = stdin_state.lock() {
                        guard.record_client_line(&line);
                    }
                    if let Some(ref mut writer) = child_stdin {
                        if writer.write_all(line.as_bytes()).is_err() || writer.flush().is_err() {
                            break;
                        }
                    }
                }
            }
        }
        drop(child_stdin);
    });

    let stdout_state = Arc::clone(&state);
    let stdout_thread = thread::spawn(move || {
        let Some(child_out) = child_stdout else {
            return;
        };
        let mut reader = BufReader::new(child_out);
        let stdout = io::stdout();
        let mut line = String::new();
        loop {
            line.clear();
            match reader.read_line(&mut line) {
                Ok(0) | Err(_) => break,
                Ok(_) => {
                    if let Ok(mut guard) = stdout_state.lock() {
                        guard.record_agent_line(&line);
                    }
                    let mut out_lock = stdout.lock();
                    if out_lock.write_all(line.as_bytes()).is_err() || out_lock.flush().is_err() {
                        break;
                    }
                }
            }
        }
    });

    let stderr_state = Arc::clone(&state);
    let stderr_thread = thread::spawn(move || {
        let Some(child_err) = child_stderr else {
            return;
        };
        let mut reader = BufReader::new(child_err);
        let stderr = io::stderr();
        let mut line = String::new();
        loop {
            line.clear();
            match reader.read_line(&mut line) {
                Ok(0) | Err(_) => break,
                Ok(_) => {
                    if let Ok(mut guard) = stderr_state.lock() {
                        guard.record_stderr_line(&line);
                    }
                    let mut err_lock = stderr.lock();
                    let _ = err_lock.write_all(line.as_bytes());
                    let _ = err_lock.flush();
                }
            }
        }
    });

    let status = child.wait();
    let _ = stdout_thread.join();
    let _ = stderr_thread.join();
    // Stdin thread may block if the parent didn't close stdin yet after child exited;
    // wait briefly on EOF in normal pipe callers (don't hang forever on interactive ttys).
    drop(stdin_thread);

    if let Ok(mut guard) = state.lock() {
        let _ = guard.writer.flush();
    }

    match status {
        Ok(s) => s.code().unwrap_or(1),
        Err(_) => 1,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redacts_home_emails_and_tokens() {
        let redactor = Redactor {
            home: Some("/Users/alice".to_string()),
            cwd: Some("/Users/alice/work".to_string()),
        };
        let mut v = JsonParser::new(
            r#"{"path":"/Users/alice/work/foo.txt","other":"/Users/alice/.gemini","email":"alice@example.org","oauth":"ya29.secret_123","accessToken":"abc","skill":"annotating-task-lineage","apiKeyPrefix":"sk-live123"}"#, // gitleaks:allow (made-up values to test redaction)
        )
        .parse()
        .unwrap();
        redactor.redact_value(&mut v);
        let out = v.to_json_string();
        assert!(!out.contains("/Users/alice"));
        assert!(!out.contains("alice@example.org"));
        assert!(!out.contains("ya29.secret_123"));
        assert!(!out.contains("sk-live123"));
        assert!(!out.contains("\"abc\""));
        assert!(out.contains("annotating-task-lineage"));
        assert!(out.contains("/workspace/foo.txt"));
        assert!(out.contains("/Users/redacted/.gemini"));
        assert!(out.contains("[redacted-secret]"));
    }

    #[test]
    fn substitutes_id_for_matching_agent_response() {
        let dir = std::env::temp_dir().join("record_acp_fixture_unit_test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let out_path = dir.join("out.ndjson");
        let file = File::create(&out_path).unwrap();
        let mut state = RecorderState {
            writer: BufWriter::new(file),
            pending_client_ids: VecDeque::new(),
            redactor: Redactor {
                home: None,
                cwd: None,
            },
        };
        state.record_client_line(r#"{"jsonrpc":"2.0","id":7,"method":"initialize","params":{}}"#);
        state.record_agent_line(r#"{"jsonrpc":"2.0","id":7,"result":{"protocolVersion":1}}"#);
        state.record_client_line(r#"{"jsonrpc":"2.0","id":"perm-1","result":{"outcome":{"outcome":"cancelled"}}}"#);
        drop(state);

        let text = fs::read_to_string(&out_path).unwrap();
        let lines: Vec<&str> = text.lines().collect();
        assert_eq!(lines.len(), 3);
        assert!(lines[0].contains(r#""direction":"client""#));
        assert!(lines[0].contains(r#""method":"initialize""#));
        assert!(lines[1].contains(r#""direction":"agent""#));
        assert!(lines[1].contains(r#""id":"$id""#));
        assert!(lines[2].contains(r#""direction":"client_response""#));
        assert!(lines[2].contains(r#""id":"perm-1""#));
        let _ = fs::remove_dir_all(&dir);
    }
}
