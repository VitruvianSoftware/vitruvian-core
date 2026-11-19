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
            .rev()
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
        if self.peek() == Some(b'}') {
            self.pos += 1;
            return Ok(JsonValue::Obj(entries));
        }
        loop {
            self.skip_ws();
            if self.peek() != Some(b'"') {
                return Err(format!("expected object key string at offset {}", self.pos));
            }
            let key = self.parse_str()?;
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
        if self.pos + 4 > self.bytes.len() {
            return Err("truncated \\uXXXX escape".to_string());
        }
        let hex = std::str::from_utf8(&self.bytes[self.pos..self.pos + 4])
            .map_err(|_| "invalid UTF-8 in \\uXXXX escape".to_string())?;
        self.pos += 4;
        u16::from_str_radix(hex, 16).map_err(|_| format!("invalid \\u{hex} escape"))
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
}

impl PlanVerdict {
    fn is_safe(&self) -> bool {
        self.destructive_steps.is_empty() && self.destructive_summary.is_empty()
    }
}

fn check_plan_json(raw: &str) -> Result<PlanVerdict, String> {
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
            destructive_steps.push(DestructiveStep {
                op: op.to_string(),
                rtype: rtype.to_string(),
                name: name.to_string(),
                urn: urn.to_string(),
            });
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
                    destructive_summary.push((op.clone(), raw_num.to_string()));
                }
            }
        }
    }

    Ok(PlanVerdict {
        total_steps: steps.len(),
        destructive_steps,
        destructive_summary,
    })
}

/// Entry point: `refuse-destructive-plan <stack-label> <preview-json-path>`.
pub fn run(args: &[String]) -> i32 {
    if args.len() != 2 || args[0].trim().is_empty() || args[1].trim().is_empty() {
        eprintln!("usage: refuse-destructive-plan <stack-label> <preview-json-path>");
        return 2;
    }
    let label = &args[0];
    let path = &args[1];

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

    let verdict = match check_plan_json(&raw) {
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

    if verdict.is_safe() {
        println!(
            "plan-guard ({label}): non-destructive ({} step(s) checked; 0 delete/replace) — safe to apply",
            verdict.total_steps
        );
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
        "::error::Refusing to apply {label}: Pulumi preview contains destructive changes ({detail}). Deleting or replacing a Sentry resource can destroy data; a human must review and apply this deliberately."
    );
    eprintln!(
        "error: Refusing to apply {label}: Pulumi preview contains destructive changes ({detail}); refusing to run pulumi up."
    );
    for s in &verdict.destructive_steps {
        eprintln!("  - {}: {} {} ({})", s.op, s.rtype, s.name, s.urn);
    }
    for (op, count) in &verdict.destructive_summary {
        if !verdict.destructive_steps.iter().any(|s| &s.op == op) {
            eprintln!("  - changeSummary[{op}] = {count}");
        }
    }
    1
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
        let verdict = check_plan_json(json).expect("valid safe plan");
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
            "unknown-op",
        ] {
            let json = format!(
                r#"{{"steps": [{{"op": "{op}", "urn": "urn:pulumi:production::sentry::sentry:index/sentryProject:SentryProject::project-backstage", "oldState": {{"type": "sentry:index/sentryProject:SentryProject"}}}}]}}"#
            );
            let verdict = check_plan_json(&json).expect("parses");
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
        let verdict = check_plan_json(json).expect("parses");
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
            assert!(check_plan_json(bad).is_err(), "expected error for {bad:?}");
        }
    }
}
