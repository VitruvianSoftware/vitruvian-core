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

//! Refuses a `pulumi preview --json` plan if any step (or `changeSummary`)
//! deletes, replaces, or falls outside the non-destructive allowlist.
//!
//! A destructive step is let through only when its exact URN is approved by an
//! `Allow-destroy: <urn>` line in a commit message of the push being applied
//! (`--allow-destroy-from-event "$GITHUB_EVENT_PATH"`, read from the event's
//! `commits[].message`). Commit messages are reviewed with the PR and cannot be
//! edited after merge, unlike the PR description. Scheduled and manual runs pass
//! no event, so they never honour an approval.
//!
//! Standard library only and free of `crate::` paths ON PURPOSE: CI workflows
//! without Bazel build the binary straight from the checkout with
//! `rustc --edition 2021 -O tools/pulumi/src/bin/refuse_destructive_plan.rs`,
//! which pulls this file in by `#[path]`. Keep it that way.

const SAFE_OPS: &[&str] = &["same", "create", "update", "read", "refresh"];
const MAX_JSON_DEPTH: usize = 128;

#[derive(Debug, Clone, PartialEq)]
enum JsonValue {
    Null,
    Bool(bool),
    Num(String),
    Str(String),
    Arr(Vec<JsonValue>),
    Obj(Vec<(String, JsonValue)>),
}

impl JsonValue {
    fn as_str(&self) -> Option<&str> {
        match self {
            JsonValue::Str(s) => Some(s.as_str()),
            _ => None,
        }
    }

    fn as_arr(&self) -> Option<&[JsonValue]> {
        match self {
            JsonValue::Arr(a) => Some(a.as_slice()),
            _ => None,
        }
    }

    fn as_obj(&self) -> Option<&[(String, JsonValue)]> {
        match self {
            JsonValue::Obj(o) => Some(o.as_slice()),
            _ => None,
        }
    }

    fn get(&self, key: &str) -> Option<&JsonValue> {
        self.as_obj()?
            .iter()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v)
    }
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
        while self.pos < self.bytes.len() {
            match self.bytes[self.pos] {
                b' ' | b'\t' | b'\r' | b'\n' => self.pos += 1,
                _ => break,
            }
        }
    }

    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.pos).copied()
    }

    fn parse_root(&mut self) -> Result<JsonValue, String> {
        self.skip_ws();
        let val = self.parse_value(0)?;
        self.skip_ws();
        if self.pos != self.bytes.len() {
            return Err(format!(
                "trailing bytes in JSON at byte offset {}",
                self.pos
            ));
        }
        Ok(val)
    }

    fn parse_value(&mut self, depth: usize) -> Result<JsonValue, String> {
        if depth > MAX_JSON_DEPTH {
            return Err("JSON nesting exceeds maximum depth".to_string());
        }
        self.skip_ws();
        match self.peek() {
            Some(b'{') => self.parse_obj(depth + 1),
            Some(b'[') => self.parse_arr(depth + 1),
            Some(b'"') => self.parse_str().map(JsonValue::Str),
            Some(b't') => self.expect_lit(b"true", JsonValue::Bool(true)),
            Some(b'f') => self.expect_lit(b"false", JsonValue::Bool(false)),
            Some(b'n') => self.expect_lit(b"null", JsonValue::Null),
            Some(b'-') | Some(b'0'..=b'9') => self.parse_num(),
            Some(b) => Err(format!(
                "unexpected byte '{}' at offset {}",
                b as char, self.pos
            )),
            None => Err("unexpected end of JSON input".to_string()),
        }
    }

    fn expect_lit(&mut self, lit: &[u8], val: JsonValue) -> Result<JsonValue, String> {
        if self.bytes[self.pos..].starts_with(lit) {
            self.pos += lit.len();
            Ok(val)
        } else {
            Err(format!("invalid JSON literal at offset {}", self.pos))
        }
    }

    fn parse_obj(&mut self, depth: usize) -> Result<JsonValue, String> {
        self.pos += 1; // '{'
        self.skip_ws();
        let mut entries = Vec::new();
        let mut seen = std::collections::HashSet::new();
        if self.peek() == Some(b'}') {
            self.pos += 1;
            return Ok(JsonValue::Obj(entries));
        }
        loop {
            self.skip_ws();
            if self.peek() != Some(b'"') {
                return Err(format!("expected object key string at offset {}", self.pos));
            }
            let key_offset = self.pos;
            let key = self.parse_str()?;
            if !seen.insert(key.clone()) {
                return Err(format!("duplicate JSON object key at offset {key_offset}"));
            }
            self.skip_ws();
            if self.peek() != Some(b':') {
                return Err(format!("expected ':' after key at offset {}", self.pos));
            }
            self.pos += 1;
            let val = self.parse_value(depth)?;
            entries.push((key, val));
            self.skip_ws();
            match self.peek() {
                Some(b',') => self.pos += 1,
                Some(b'}') => {
                    self.pos += 1;
                    return Ok(JsonValue::Obj(entries));
                }
                _ => return Err(format!("expected ',' or '}}' at offset {}", self.pos)),
            }
        }
    }

    fn parse_arr(&mut self, depth: usize) -> Result<JsonValue, String> {
        self.pos += 1; // '['
        self.skip_ws();
        let mut items = Vec::new();
        if self.peek() == Some(b']') {
            self.pos += 1;
            return Ok(JsonValue::Arr(items));
        }
        loop {
            let val = self.parse_value(depth)?;
            items.push(val);
            self.skip_ws();
            match self.peek() {
                Some(b',') => self.pos += 1,
                Some(b']') => {
                    self.pos += 1;
                    return Ok(JsonValue::Arr(items));
                }
                _ => return Err(format!("expected ',' or ']' at offset {}", self.pos)),
            }
        }
    }

    fn parse_str(&mut self) -> Result<String, String> {
        self.pos += 1; // '"'
        let mut out = String::new();
        while self.pos < self.bytes.len() {
            let start = self.pos;
            while self.pos < self.bytes.len() {
                let b = self.bytes[self.pos];
                if b == b'"' || b == b'\\' {
                    break;
                }
                if b < 0x20 {
                    return Err(format!("unescaped control char at offset {}", self.pos));
                }
                self.pos += 1;
            }
            let slice = std::str::from_utf8(&self.bytes[start..self.pos])
                .map_err(|e| format!("invalid UTF-8 in JSON string: {e}"))?;
            out.push_str(slice);
            if self.pos >= self.bytes.len() {
                break;
            }
            let b = self.bytes[self.pos];
            self.pos += 1;
            if b == b'"' {
                return Ok(out);
            }
            // Escape sequence after '\'.
            let esc = self
                .bytes
                .get(self.pos)
                .copied()
                .ok_or_else(|| "unterminated JSON string escape".to_string())?;
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
                    let u1 = self.parse_hex4()?;
                    if (0xD800..=0xDBFF).contains(&u1) {
                        if self.bytes.get(self.pos..self.pos + 2) != Some(b"\\u") {
                            return Err("unpaired high surrogate in JSON string".to_string());
                        }
                        self.pos += 2;
                        let u2 = self.parse_hex4()?;
                        if !(0xDC00..=0xDFFF).contains(&u2) {
                            return Err("invalid low surrogate in JSON string".to_string());
                        }
                        let cp = 0x10000 + (((u1 as u32 - 0xD800) << 10) | (u2 as u32 - 0xDC00));
                        let ch = char::from_u32(cp)
                            .ok_or_else(|| "invalid Unicode scalar value".to_string())?;
                        out.push(ch);
                    } else if (0xDC00..=0xDFFF).contains(&u1) {
                        return Err("unpaired low surrogate in JSON string".to_string());
                    } else {
                        let ch = char::from_u32(u1 as u32)
                            .ok_or_else(|| "invalid Unicode scalar value".to_string())?;
                        out.push(ch);
                    }
                }
                other => {
                    return Err(format!(
                        "invalid escape '\\{}' at offset {}",
                        other as char, self.pos
                    ));
                }
            }
        }
        Err("unterminated JSON string".to_string())
    }

    fn parse_hex4(&mut self) -> Result<u16, String> {
        let start = self.pos;
        let Some(slice) = self.bytes.get(start..start + 4) else {
            return Err(format!("truncated \\uXXXX escape at offset {start}"));
        };
        let mut val: u16 = 0;
        for &b in slice {
            let digit = match b {
                b'0'..=b'9' => (b - b'0') as u16,
                b'a'..=b'f' => (b - b'a' + 10) as u16,
                b'A'..=b'F' => (b - b'A' + 10) as u16,
                _ => return Err(format!("invalid \\uXXXX hex escape at offset {start}")),
            };
            val = (val << 4) | digit;
        }
        self.pos += 4;
        Ok(val)
    }

    fn parse_num(&mut self) -> Result<JsonValue, String> {
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
            _ => return Err(format!("invalid JSON number at offset {}", self.pos)),
        }
        if self.peek() == Some(b'.') {
            self.pos += 1;
            if !matches!(self.peek(), Some(b'0'..=b'9')) {
                return Err(format!("invalid fraction in number at offset {}", self.pos));
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
                return Err(format!("invalid exponent in number at offset {}", self.pos));
            }
            while matches!(self.peek(), Some(b'0'..=b'9')) {
                self.pos += 1;
            }
        }
        let raw = std::str::from_utf8(&self.bytes[start..self.pos])
            .map_err(|_| "invalid UTF-8 in number".to_string())?;
        Ok(JsonValue::Num(raw.to_string()))
    }
}

fn rtype_from_urn(urn: &str) -> Option<&str> {
    let parts: Vec<&str> = urn.split("::").collect();
    if parts.len() >= 4 {
        let candidate = parts[parts.len() - 2];
        if !candidate.is_empty() {
            return Some(candidate);
        }
    }
    None
}

fn name_from_urn(urn: &str) -> &str {
    match urn.rsplit_once("::") {
        Some((_, name)) if !name.is_empty() => name,
        _ => "<unknown-name>",
    }
}

#[derive(Debug, PartialEq)]
struct DestructiveStep {
    op: String,
    rtype: String,
    name: String,
    urn: String,
}

#[derive(Debug, PartialEq)]
struct PlanVerdict {
    total_steps: usize,
    destructive_steps: Vec<DestructiveStep>,
    destructive_summary: Vec<(String, String)>,
    allowed_steps: Vec<DestructiveStep>,
}

impl PlanVerdict {
    fn is_safe(&self) -> bool {
        self.destructive_steps.is_empty() && self.destructive_summary.is_empty()
    }
}

fn check_plan_json(raw: &str, allow: &[String]) -> Result<PlanVerdict, String> {
    if raw.trim().is_empty() {
        return Err("Pulumi preview JSON is empty".to_string());
    }
    let root = JsonParser::new(raw).parse_root()?;
    if root.as_obj().is_none() {
        return Err("Pulumi preview JSON root is not an object".to_string());
    }
    let steps = root
        .get("steps")
        .and_then(JsonValue::as_arr)
        .ok_or_else(|| "Pulumi preview JSON is missing a \"steps\" array".to_string())?;

    let mut destructive_steps = Vec::new();
    let mut allowed_steps = Vec::new();
    for (idx, step) in steps.iter().enumerate() {
        if step.as_obj().is_none() {
            return Err(format!("step[{idx}] in preview JSON is not an object"));
        }
        let op = step
            .get("op")
            .and_then(JsonValue::as_str)
            .filter(|s| !s.is_empty())
            .ok_or_else(|| format!("step[{idx}] in preview JSON is missing a string \"op\""))?;
        if !SAFE_OPS.contains(&op) {
            let urn = step
                .get("urn")
                .and_then(JsonValue::as_str)
                .filter(|s| !s.is_empty())
                .unwrap_or("<unknown-urn>");
            let rtype = step
                .get("oldState")
                .and_then(|s| s.get("type"))
                .and_then(JsonValue::as_str)
                .or_else(|| {
                    step.get("newState")
                        .and_then(|s| s.get("type"))
                        .and_then(JsonValue::as_str)
                })
                .or_else(|| step.get("type").and_then(JsonValue::as_str))
                .or_else(|| rtype_from_urn(urn))
                .unwrap_or("<unknown-type>");
            let name = name_from_urn(urn);
            let step = DestructiveStep {
                op: op.to_string(),
                rtype: rtype.to_string(),
                name: name.to_string(),
                urn: urn.to_string(),
            };
            if allow.iter().any(|a| a == urn) {
                allowed_steps.push(step);
            } else {
                destructive_steps.push(step);
            }
        }
    }

    let mut destructive_summary = Vec::new();
    if let Some(summary) = root.get("changeSummary") {
        if *summary != JsonValue::Null {
            let entries = summary
                .as_obj()
                .ok_or_else(|| "\"changeSummary\" in preview JSON is not an object".to_string())?;
            for (op, val) in entries {
                let raw_num = match val {
                    JsonValue::Num(n) => n.as_str(),
                    _ => {
                        return Err(format!(
                            "\"changeSummary.{op}\" in preview JSON is not a number"
                        ))
                    }
                };
                let is_zero = raw_num.parse::<f64>().map(|v| v == 0.0).unwrap_or(false);
                if !is_zero && !SAFE_OPS.contains(&op.as_str()) {
                    // A summary count is accounted for only when the approved
                    // steps with that op explain all of it. A larger count means
                    // a destructive change with no step to check, so it stays.
                    let approved = allowed_steps.iter().filter(|s| &s.op == op).count();
                    let explained = destructive_steps.iter().all(|s| &s.op != op)
                        && raw_num.parse::<usize>().ok() == Some(approved);
                    if !explained {
                        destructive_summary.push((op.clone(), raw_num.to_string()));
                    }
                }
            }
        }
    }

    Ok(PlanVerdict {
        total_steps: steps.len(),
        destructive_steps,
        destructive_summary,
        allowed_steps,
    })
}

const ALLOW_KEY: &str = "allow-destroy:";
const MAX_SHOWN_VALUE: usize = 200;

/// Pulls `Allow-destroy: <urn>` lines out of commit-message text. Returns the
/// approved URNs and the values of `Allow-destroy:` lines that are not a single
/// Pulumi URN (they approve nothing; the caller warns about them).
fn parse_allow_destroy_lines(text: &str) -> (Vec<String>, Vec<String>) {
    let mut urns: Vec<String> = Vec::new();
    let mut invalid = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        let Some(head) = line.get(..ALLOW_KEY.len()) else {
            continue;
        };
        if !head.eq_ignore_ascii_case(ALLOW_KEY) {
            continue;
        }
        let value = line[ALLOW_KEY.len()..].trim();
        let is_urn = value.starts_with("urn:pulumi:")
            && value.matches("::").count() >= 3
            && !value.chars().any(char::is_whitespace);
        if is_urn {
            if !urns.iter().any(|u| u == value) {
                urns.push(value.to_string());
            }
        } else {
            invalid.push(value.chars().take(MAX_SHOWN_VALUE).collect());
        }
    }
    (urns, invalid)
}

/// Reads the approved URNs from a GitHub push event payload
/// (`$GITHUB_EVENT_PATH`): every `Allow-destroy:` line in `commits[].message`.
/// Errors on anything that is not a push payload, so a wrong file can never
/// approve anything.
fn allow_list_from_event_json(raw: &str) -> Result<(Vec<String>, Vec<String>), String> {
    let root = JsonParser::new(raw).parse_root()?;
    let commits = root
        .get("commits")
        .and_then(JsonValue::as_arr)
        .ok_or_else(|| "event payload has no \"commits\" array (not a push event)".to_string())?;
    let mut text = String::new();
    for (idx, c) in commits.iter().enumerate() {
        let msg = c
            .get("message")
            .and_then(JsonValue::as_str)
            .ok_or_else(|| format!("commits[{idx}] in event payload has no string \"message\""))?;
        text.push_str(msg);
        text.push('\n');
    }
    Ok(parse_allow_destroy_lines(&text))
}

/// Loads the approvals named by `--allow-destroy-from-event <path>`, printing
/// a warning for each malformed `Allow-destroy:` line. An event that cannot be
/// read approves nothing (with a warning) rather than failing the run: no
/// approvals is the safe default, and a safe plan must still apply.
pub fn load_allow_list(label: &str, event_path: &str) -> Vec<String> {
    let parsed = std::fs::read_to_string(event_path)
        .map_err(|e| format!("could not read {event_path}: {e}"))
        .and_then(|raw| allow_list_from_event_json(&raw));
    let (urns, invalid) = match parsed {
        Ok(v) => v,
        Err(e) => {
            println!(
                "::warning::plan-guard ({label}): no Allow-destroy approvals were read ({e}); every delete or replace will be refused"
            );
            return Vec::new();
        }
    };
    for v in &invalid {
        println!(
            "::warning::plan-guard ({label}): ignoring an Allow-destroy line that is not one Pulumi URN: {v:?}"
        );
    }
    urns
}

/// Splits `[--allow-destroy-from-event <path>]` off the end of `args`.
/// Returns the positional args and the optional path; Err on a malformed flag.
pub fn split_allow_flag(args: &[String]) -> Result<(Vec<String>, Option<String>), ()> {
    let mut positional = Vec::new();
    let mut event = None;
    let mut it = args.iter();
    while let Some(a) = it.next() {
        if a == "--allow-destroy-from-event" {
            match it.next() {
                Some(p) if !p.trim().is_empty() && event.is_none() => event = Some(p.clone()),
                _ => return Err(()),
            }
        } else if a.starts_with("--") {
            return Err(());
        } else {
            positional.push(a.clone());
        }
    }
    Ok((positional, event))
}

/// Validate a `pulumi preview --json` payload and print the guard verdict.
/// Returns 0 if non-destructive, 1 if destructive or unreadable/malformed.
pub fn check_and_report(label: &str, raw: &str, allow: &[String]) -> i32 {
    let verdict = match check_plan_json(raw, allow) {
        Ok(v) => v,
        Err(e) => {
            eprintln!(
                "::error::Refusing to apply {label}: could not verify Pulumi preview plan ({e}); failing closed."
            );
            eprintln!(
                "error: Refusing to apply {label}: could not verify Pulumi preview plan ({e}); failing closed."
            );
            return 1;
        }
    };

    for a in allow {
        if !verdict.allowed_steps.iter().any(|s| &s.urn == a)
            && !verdict.destructive_steps.iter().any(|s| &s.urn == a)
        {
            println!(
                "::notice::plan-guard ({label}): Allow-destroy {a} matches nothing this plan deletes or replaces"
            );
        }
    }

    if verdict.is_safe() {
        if verdict.allowed_steps.is_empty() {
            println!(
                "plan-guard ({label}): non-destructive ({} step(s) checked; 0 delete/replace) — safe to apply",
                verdict.total_steps
            );
        } else {
            println!(
                "::warning::plan-guard ({label}): applying {} destructive step(s) approved by Allow-destroy in the merged commits ({} step(s) checked)",
                verdict.allowed_steps.len(),
                verdict.total_steps
            );
            for s in &verdict.allowed_steps {
                println!("  - approved {}: {} {} ({})", s.op, s.rtype, s.name, s.urn);
            }
        }
        return 0;
    }

    let step_count = verdict.destructive_steps.len();
    let summary_desc: Vec<String> = verdict
        .destructive_summary
        .iter()
        .map(|(op, count)| format!("{op}={count}"))
        .collect();
    let detail = if step_count > 0 && !summary_desc.is_empty() {
        format!(
            "{step_count} destructive step(s); changeSummary: {}",
            summary_desc.join(", ")
        )
    } else if step_count > 0 {
        format!("{step_count} destructive step(s)")
    } else {
        format!("changeSummary: {}", summary_desc.join(", "))
    };

    eprintln!(
        "::error::Refusing to apply {label}: Pulumi preview contains destructive changes ({detail}). Deleting or replacing a resource can destroy its data. If this is intended, add one `Allow-destroy: <urn>` line per resource to a commit message in the PR and merge it; scheduled runs never apply a delete."
    );
    eprintln!(
        "error: Refusing to apply {label}: Pulumi preview contains destructive changes ({detail}); refusing to run pulumi up."
    );
    for s in &verdict.destructive_steps {
        eprintln!("  - {}: {} {} ({})", s.op, s.rtype, s.name, s.urn);
    }
    for s in &verdict.allowed_steps {
        eprintln!(
            "  - approved, but held back with the rest: {}: {} {} ({})",
            s.op, s.rtype, s.name, s.urn
        );
    }
    for (op, count) in &verdict.destructive_summary {
        if !verdict.destructive_steps.iter().any(|s| &s.op == op) {
            eprintln!("  - changeSummary[{op}] = {count}");
        }
    }
    1
}

const USAGE: &str = "usage: refuse-destructive-plan <stack-label> <preview-json-path> [--allow-destroy-from-event <github-event.json>]";

/// Entry point: `refuse-destructive-plan <stack-label> <preview-json-path>
/// [--allow-destroy-from-event <github-event.json>]`.
pub fn run(args: &[String]) -> i32 {
    let Ok((pos, event)) = split_allow_flag(args) else {
        eprintln!("{USAGE}");
        return 2;
    };
    if pos.len() != 2 || pos[0].trim().is_empty() || pos[1].trim().is_empty() {
        eprintln!("{USAGE}");
        return 2;
    }
    let label = &pos[0];
    let path = &pos[1];
    let allow = event
        .as_deref()
        .map(|p| load_allow_list(label, p))
        .unwrap_or_default();

    let raw = match std::fs::read_to_string(path) {
        Ok(s) => s,
        Err(e) => {
            eprintln!(
                "::error::Refusing to apply {label}: could not read Pulumi preview JSON at {path}: {e}"
            );
            eprintln!(
                "error: Refusing to apply {label}: could not read Pulumi preview JSON at {path}: {e}"
            );
            return 1;
        }
    };

    check_and_report(label, &raw, &allow)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_safe_ops_and_unicode_escapes() {
        let json = r#"{
          "steps": [
            {"op": "same", "urn": "urn:pulumi:production::sentry::pulumi:pulumi:Stack::sentry-production"},
            {"op": "create", "urn": "urn:pulumi:production::sentry::sentry:index/sentryProject:SentryProject::project-new\u0026app", "newState": {"type": "sentry:index/sentryProject:SentryProject"}},
            {"op": "update", "urn": "urn:pulumi:production::sentry::sentry:index/sentryTeam:SentryTeam::team-vitruvian"},
            {"op": "read", "urn": "urn:pulumi:production::sentry::sentry:index/getAllProjects:getAllProjects::all"},
            {"op": "refresh", "urn": "urn:pulumi:production::sentry::command:local:Command::sentry-org-privacy"}
          ],
          "changeSummary": {"create": 1, "update": 1, "same": 3}
        }"#;
        let verdict = check_plan_json(json, &[]).expect("valid safe plan");
        assert!(verdict.is_safe());
        assert_eq!(verdict.total_steps, 5);
    }

    #[test]
    fn rejects_all_destructive_ops() {
        for op in [
            "delete",
            "replace",
            "create-replacement",
            "delete-replaced",
            "remove-pending-replace",
            "import-replacement",
            "discard-replaced",
            "read-replacement",
            "discard",
            "import",
            "unknown-op",
        ] {
            let json = format!(
                r#"{{"steps": [{{"op": "{op}", "urn": "urn:pulumi:production::sentry::sentry:index/sentryProject:SentryProject::project-backstage", "oldState": {{"type": "sentry:index/sentryProject:SentryProject"}}}}]}}"#
            );
            let verdict = check_plan_json(&json, &[]).expect("parses");
            assert!(!verdict.is_safe(), "op {op} must be rejected");
            assert_eq!(verdict.destructive_steps.len(), 1);
            assert_eq!(verdict.destructive_steps[0].op, op);
            assert_eq!(
                verdict.destructive_steps[0].rtype,
                "sentry:index/sentryProject:SentryProject"
            );
            assert_eq!(verdict.destructive_steps[0].name, "project-backstage");
        }
    }

    #[test]
    fn rejects_destructive_change_summary_even_without_destructive_step() {
        let json = r#"{"steps": [{"op": "same", "urn": "urn:pulumi:p::s::t::n"}], "changeSummary": {"delete": 1, "same": 1}}"#;
        let verdict = check_plan_json(json, &[]).expect("parses");
        assert!(!verdict.is_safe());
        assert_eq!(
            verdict.destructive_summary,
            vec![("delete".to_string(), "1".to_string())]
        );
    }

    #[test]
    fn fails_closed_on_missing_steps_or_malformed_json() {
        for bad in [
            "",
            "   ",
            "{}",
            "[]",
            r#"{"steps": null}"#,
            r#"{"steps": [{"urn": "x"}]}"#,
            "{bad",
        ] {
            assert!(
                check_plan_json(bad, &[]).is_err(),
                "expected error for {bad:?}"
            );
        }
    }

    #[test]
    fn rejects_duplicate_object_keys() {
        for dup in [
            r#"{"steps":[{"op":"delete","op":"same","urn":"urn:pulumi:p::s::t::n"}]}"#,
            r#"{"steps":[{"op":"delete","\u006fp":"same","urn":"urn:pulumi:p::s::t::n"}]}"#,
            r#"{"steps":[{"op":"delete","urn":"urn:pulumi:p::s::t::n"}],"steps":[]}"#,
            r#"{"steps":[{"op":"same","urn":"urn:pulumi:p::s::t::n"}],"changeSummary":{"delete":1,"delete":0}}"#,
        ] {
            assert!(
                check_plan_json(dup, &[]).is_err(),
                "expected duplicate-key error for {dup:?}"
            );
        }
    }

    #[test]
    fn rejects_non_hex_or_short_unicode_escapes() {
        for bad in [
            r#"{"steps":[{"op":"\u+073ame","urn":"urn:pulumi:p::s::t::n"}]}"#,
            r#"{"steps":[{"op":"\u-073ame","urn":"urn:pulumi:p::s::t::n"}]}"#,
            r#"{"steps":[{"op":"\u07","urn":"urn:pulumi:p::s::t::n"}]}"#,
            r#"{"steps":[{"op":"\u07"#,
        ] {
            assert!(
                check_plan_json(bad, &[]).is_err(),
                "expected unicode-escape error for {bad:?}"
            );
        }
    }

    const P: &str =
        "urn:pulumi:production::sentry::sentry:index/sentryProject:SentryProject::project-old";
    const Q: &str =
        "urn:pulumi:production::sentry::sentry:index/sentryProject:SentryProject::project-keep";

    fn delete_plan(urns: &[&str], summary_delete: usize) -> String {
        let steps: Vec<String> = urns
            .iter()
            .map(|u| format!(r#"{{"op":"delete","urn":"{u}"}}"#))
            .collect();
        format!(
            r#"{{"steps":[{}],"changeSummary":{{"delete":{summary_delete}}}}}"#,
            steps.join(",")
        )
    }

    #[test]
    fn approved_delete_is_safe_and_reported_as_approved() {
        let v = check_plan_json(&delete_plan(&[P], 1), &[P.to_string()]).unwrap();
        assert!(v.is_safe(), "{v:?}");
        assert_eq!(v.allowed_steps.len(), 1);
        assert_eq!(v.allowed_steps[0].urn, P);
    }

    #[test]
    fn approval_for_one_resource_does_not_cover_another() {
        let v = check_plan_json(&delete_plan(&[P, Q], 2), &[P.to_string()]).unwrap();
        assert!(!v.is_safe());
        assert_eq!(v.destructive_steps.len(), 1);
        assert_eq!(v.destructive_steps[0].urn, Q);
        // The summary still counts Q's delete, so it is not explained away.
        assert_eq!(v.destructive_summary, vec![("delete".into(), "2".into())]);
    }

    #[test]
    fn approval_must_match_the_whole_urn() {
        for near in [
            &P[..P.len() - 1],
            "project-old",
            "urn:pulumi:staging::sentry::sentry:index/sentryProject:SentryProject::project-old",
        ] {
            let v = check_plan_json(&delete_plan(&[P], 1), &[near.to_string()]).unwrap();
            assert!(!v.is_safe(), "{near} must not approve {P}");
        }
    }

    #[test]
    fn summary_count_beyond_approved_steps_is_refused() {
        // changeSummary says two deletes but only one (approved) step is listed.
        let v = check_plan_json(&delete_plan(&[P], 2), &[P.to_string()]).unwrap();
        assert!(!v.is_safe());
        assert!(v.destructive_steps.is_empty());
        assert_eq!(v.destructive_summary, vec![("delete".into(), "2".into())]);
    }

    #[test]
    fn approved_replace_covers_all_of_its_steps() {
        let json = format!(
            r#"{{"steps":[{{"op":"create-replacement","urn":"{P}"}},{{"op":"replace","urn":"{P}"}},{{"op":"delete-replaced","urn":"{P}"}}],"changeSummary":{{"replace":1,"same":3}}}}"#
        );
        let v = check_plan_json(&json, &[P.to_string()]).unwrap();
        assert!(v.is_safe(), "{v:?}");
        assert_eq!(v.allowed_steps.len(), 3);
    }

    #[test]
    fn parses_allow_destroy_lines_and_flags_bad_values() {
        let text = format!(
            "fix(sentry): drop the old project\n\nbody text\nAllow-destroy: {P}\n  allow-DESTROY:   {Q}  \nAllow-destroy: {P}\nAllow-destroy: project-old\nAllow-destroy: {P} extra\nNot-Allow-destroy: {Q}\nsee Allow-destroy: {Q} inline\nAllow-destroy:\n"
        );
        let (urns, invalid) = parse_allow_destroy_lines(&text);
        assert_eq!(urns, vec![P.to_string(), Q.to_string()]);
        assert_eq!(
            invalid,
            vec![
                "project-old".to_string(),
                format!("{P} extra"),
                String::new()
            ]
        );
    }

    #[test]
    fn reads_approvals_from_push_event_commits() {
        let event = format!(
            r#"{{"ref":"refs/heads/main","commits":[{{"message":"a\n\nAllow-destroy: {P}"}},{{"message":"b"}}],"head_commit":{{"message":"Allow-destroy: {Q}"}}}}"#
        );
        let (urns, invalid) = allow_list_from_event_json(&event).unwrap();
        // head_commit is not read: only the commits of this push count.
        assert_eq!(urns, vec![P.to_string()]);
        assert!(invalid.is_empty());
    }

    #[test]
    fn non_push_event_payloads_fail_closed() {
        for bad in [
            r#"{"schedule":"23 */6 * * *"}"#,
            r#"{"commits":null}"#,
            r#"{"commits":[{"id":"abc"}]}"#,
            r#"{"commits":[{"message":1}]}"#,
            r#"{"commits":[],"commits":[]}"#,
            "not json",
        ] {
            assert!(allow_list_from_event_json(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn allow_flag_parsing() {
        let a = |v: &[&str]| v.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert_eq!(
            split_allow_flag(&a(&["l", "p"])).unwrap(),
            (a(&["l", "p"]), None)
        );
        assert_eq!(
            split_allow_flag(&a(&["l", "--allow-destroy-from-event", "e.json", "p"])).unwrap(),
            (a(&["l", "p"]), Some("e.json".to_string()))
        );
        for bad in [
            &["l", "--allow-destroy-from-event"][..],
            &["l", "--allow-destroy-from-event", ""][..],
            &[
                "l",
                "--allow-destroy-from-event",
                "a",
                "--allow-destroy-from-event",
                "b",
            ][..],
            &["l", "--allow-destroy", "urn"][..],
        ] {
            assert!(split_allow_flag(&a(bad)).is_err(), "{bad:?}");
        }
    }
}
