// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub const SUPPORTED_OPERATORS: &[&str] = &[
    "regex_match",
    "contains",
    "not_contains",
    "equals",
    "starts_with",
    "ends_with",
];

pub const SUPPORTED_ACTIONS: &[&str] = &[
    "allow",
    "warn",
    "ask",
    "force_ask",
    "block",
    "deny",
    "overwrite",
];

// ---------------------------------------------------------------------------
// Minimal pure-std JS-compatible regex engine (anchors, groups, alternation,
// quantifiers, character classes, shorthand escapes, word boundaries, and
// global replace).
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
enum Atom {
    AnyNotNewline,
    Literal(char),
    CharClass {
        negated: bool,
        items: Vec<ClassItem>,
    },
    Shorthand(char), // s, S, d, D, w, W
    AnchorStart,
    AnchorEnd,
    WordBoundary(bool), // true = \b, false = \B
    Group(Vec<Vec<Quantified>>),
}

#[derive(Debug, Clone)]
enum ClassItem {
    Single(char),
    Range(char, char),
    Shorthand(char),
}

#[derive(Debug, Clone)]
struct Quantified {
    atom: Atom,
    min: usize,
    max: Option<usize>, // None = unbounded
}

struct RegexParser<'a> {
    chars: Vec<char>,
    pos: usize,
    _marker: std::marker::PhantomData<&'a ()>,
}

impl<'a> RegexParser<'a> {
    fn new(pattern: &'a str) -> Self {
        Self {
            chars: pattern.chars().collect(),
            pos: 0,
            _marker: std::marker::PhantomData,
        }
    }

    fn peek(&self) -> Option<char> {
        self.chars.get(self.pos).copied()
    }

    fn next(&mut self) -> Option<char> {
        let ch = self.peek()?;
        self.pos += 1;
        Some(ch)
    }

    fn parse_alternation(&mut self) -> Result<Vec<Vec<Quantified>>, ()> {
        let mut branches = Vec::new();
        branches.push(self.parse_sequence()?);
        while self.peek() == Some('|') {
            self.next();
            branches.push(self.parse_sequence()?);
        }
        Ok(branches)
    }

    fn parse_sequence(&mut self) -> Result<Vec<Quantified>, ()> {
        let mut seq = Vec::new();
        while let Some(ch) = self.peek() {
            if ch == ')' || ch == '|' {
                break;
            }
            let atom = self.parse_atom()?;
            let (min, max) = self.parse_quantifier();
            seq.push(Quantified { atom, min, max });
        }
        Ok(seq)
    }

    fn parse_atom(&mut self) -> Result<Atom, ()> {
        let ch = self.next().ok_or(())?;
        match ch {
            '^' => Ok(Atom::AnchorStart),
            '$' => Ok(Atom::AnchorEnd),
            '.' => Ok(Atom::AnyNotNewline),
            '(' => {
                if self.peek() == Some('?') {
                    self.next();
                    if self.peek() == Some(':') {
                        self.next();
                    } else {
                        return Err(());
                    }
                }
                let branches = self.parse_alternation()?;
                if self.next() != Some(')') {
                    return Err(());
                }
                Ok(Atom::Group(branches))
            }
            '[' => self.parse_char_class(),
            '\\' => {
                let esc = self.next().ok_or(())?;
                match esc {
                    'b' => Ok(Atom::WordBoundary(true)),
                    'B' => Ok(Atom::WordBoundary(false)),
                    's' | 'S' | 'd' | 'D' | 'w' | 'W' => Ok(Atom::Shorthand(esc)),
                    'n' => Ok(Atom::Literal('\n')),
                    'r' => Ok(Atom::Literal('\r')),
                    't' => Ok(Atom::Literal('\t')),
                    other => Ok(Atom::Literal(other)),
                }
            }
            '*' | '+' | '?' => Err(()),
            other => Ok(Atom::Literal(other)),
        }
    }

    fn parse_char_class(&mut self) -> Result<Atom, ()> {
        let mut negated = false;
        if self.peek() == Some('^') {
            negated = true;
            self.next();
        }
        let mut items = Vec::new();
        let mut first = true;
        while let Some(ch) = self.peek() {
            if ch == ']' && !first {
                self.next();
                return Ok(Atom::CharClass { negated, items });
            }
            first = false;
            let start_item = self.parse_class_char()?;
            if let ClassItem::Single(start_ch) = start_item {
                if self.peek() == Some('-') && self.chars.get(self.pos + 1) != Some(&']') {
                    self.next(); // consume '-'
                    if let ClassItem::Single(end_ch) = self.parse_class_char()? {
                        if start_ch <= end_ch {
                            items.push(ClassItem::Range(start_ch, end_ch));
                            continue;
                        } else {
                            return Err(());
                        }
                    }
                }
            }
            items.push(start_item);
        }
        Err(())
    }

    fn parse_class_char(&mut self) -> Result<ClassItem, ()> {
        let ch = self.next().ok_or(())?;
        if ch == '\\' {
            let esc = self.next().ok_or(())?;
            match esc {
                's' | 'S' | 'd' | 'D' | 'w' | 'W' => Ok(ClassItem::Shorthand(esc)),
                'n' => Ok(ClassItem::Single('\n')),
                'r' => Ok(ClassItem::Single('\r')),
                't' => Ok(ClassItem::Single('\t')),
                other => Ok(ClassItem::Single(other)),
            }
        } else {
            Ok(ClassItem::Single(ch))
        }
    }

    fn parse_quantifier(&mut self) -> (usize, Option<usize>) {
        match self.peek() {
            Some('*') => {
                self.next();
                (0, None)
            }
            Some('+') => {
                self.next();
                (1, None)
            }
            Some('?') => {
                self.next();
                (0, Some(1))
            }
            Some('{') => {
                let saved = self.pos;
                self.next();
                let mut d1 = String::new();
                while let Some(c) = self.peek().filter(|c| c.is_ascii_digit()) {
                    d1.push(c);
                    self.next();
                }
                if d1.is_empty() {
                    self.pos = saved;
                    return (1, Some(1));
                }
                let min = d1.parse::<usize>().unwrap_or(0);
                if self.peek() == Some('}') {
                    self.next();
                    return (min, Some(min));
                }
                if self.peek() == Some(',') {
                    self.next();
                    if self.peek() == Some('}') {
                        self.next();
                        return (min, None);
                    }
                    let mut d2 = String::new();
                    while let Some(c) = self.peek().filter(|c| c.is_ascii_digit()) {
                        d2.push(c);
                        self.next();
                    }
                    if !d2.is_empty() && self.peek() == Some('}') {
                        self.next();
                        let max = d2.parse::<usize>().unwrap_or(min);
                        if max >= min {
                            return (min, Some(max));
                        }
                    }
                }
                self.pos = saved;
                (1, Some(1))
            }
            _ => (1, Some(1)),
        }
    }
}

struct CompiledRegex {
    branches: Vec<Vec<Quantified>>,
    case_sensitive: bool,
}

impl CompiledRegex {
    fn compile(pattern: &str, case_sensitive: bool) -> Result<Self, ()> {
        let mut parser = RegexParser::new(pattern);
        let branches = parser.parse_alternation()?;
        if parser.pos != parser.chars.len() {
            return Err(());
        }
        Ok(Self {
            branches,
            case_sensitive,
        })
    }

    fn is_match(&self, text: &str) -> bool {
        let chars: Vec<char> = text.chars().collect();
        for start in 0..=chars.len() {
            if self
                .match_alternation(&self.branches, &chars, start)
                .is_some()
            {
                return true;
            }
        }
        false
    }

    fn replace_all(&self, text: &str, replacement: &str) -> String {
        let chars: Vec<char> = text.chars().collect();
        let mut out = String::new();
        let mut pos = 0;
        while pos <= chars.len() {
            if let Some(end) = self.match_alternation(&self.branches, &chars, pos) {
                out.push_str(replacement);
                if end == pos {
                    if pos < chars.len() {
                        out.push(chars[pos]);
                    }
                    pos += 1;
                } else {
                    pos = end;
                }
            } else {
                if pos < chars.len() {
                    out.push(chars[pos]);
                }
                pos += 1;
            }
        }
        out
    }

    fn match_alternation(
        &self,
        branches: &[Vec<Quantified>],
        chars: &[char],
        pos: usize,
    ) -> Option<usize> {
        for seq in branches {
            if let Some(end) = self.match_sequence(seq, chars, pos) {
                return Some(end);
            }
        }
        None
    }

    fn match_sequence(&self, seq: &[Quantified], chars: &[char], pos: usize) -> Option<usize> {
        let Some((first, rest)) = seq.split_first() else {
            return Some(pos);
        };

        // Collect all reachable positions after matching `first` between `min` and `max` times.
        let mut ends = Vec::new();
        if first.min == 0 {
            ends.push(pos);
        }

        let mut current_positions = vec![pos];
        let mut count = 0usize;
        loop {
            if let Some(max) = first.max {
                if count >= max {
                    break;
                }
            }
            let mut next_positions = Vec::new();
            for &p in &current_positions {
                if let Some(next_p) = self.match_atom(&first.atom, chars, p) {
                    if next_p == p && count >= first.min {
                        // Avoid infinite zero-width quantifier loops
                        continue;
                    }
                    if !next_positions.contains(&next_p) {
                        next_positions.push(next_p);
                    }
                }
            }
            if next_positions.is_empty() {
                break;
            }
            count += 1;
            if count >= first.min {
                for &np in &next_positions {
                    if !ends.contains(&np) {
                        ends.push(np);
                    }
                }
            }
            current_positions = next_positions;
        }

        // Greedy: try longest match first
        for &candidate_pos in ends.iter().rev() {
            if let Some(final_pos) = self.match_sequence(rest, chars, candidate_pos) {
                return Some(final_pos);
            }
        }
        None
    }

    fn match_atom(&self, atom: &Atom, chars: &[char], pos: usize) -> Option<usize> {
        match atom {
            Atom::AnchorStart => (pos == 0).then_some(pos),
            Atom::AnchorEnd => (pos == chars.len()).then_some(pos),
            Atom::WordBoundary(expect_boundary) => {
                let prev_word = pos > 0 && is_word_char(chars[pos - 1]);
                let next_word = pos < chars.len() && is_word_char(chars[pos]);
                let is_boundary = prev_word != next_word;
                (is_boundary == *expect_boundary).then_some(pos)
            }
            Atom::AnyNotNewline => {
                let ch = *chars.get(pos)?;
                (ch != '\n' && ch != '\r').then_some(pos + 1)
            }
            Atom::Literal(lit) => {
                let ch = *chars.get(pos)?;
                self.chars_eq(ch, *lit).then_some(pos + 1)
            }
            Atom::Shorthand(kind) => {
                let ch = *chars.get(pos)?;
                matches_shorthand(ch, *kind).then_some(pos + 1)
            }
            Atom::CharClass { negated, items } => {
                let ch = *chars.get(pos)?;
                let matched = items.iter().any(|item| match item {
                    ClassItem::Single(c) => self.chars_eq(ch, *c),
                    ClassItem::Range(a, b) => {
                        if self.case_sensitive {
                            ch >= *a && ch <= *b
                        } else {
                            let cl = ch.to_ascii_lowercase();
                            cl >= a.to_ascii_lowercase() && cl <= b.to_ascii_lowercase()
                        }
                    }
                    ClassItem::Shorthand(k) => matches_shorthand(ch, *k),
                });
                (matched != *negated).then_some(pos + 1)
            }
            Atom::Group(branches) => self.match_alternation(branches, chars, pos),
        }
    }

    fn chars_eq(&self, a: char, b: char) -> bool {
        if self.case_sensitive {
            a == b
        } else {
            a.eq_ignore_ascii_case(&b)
        }
    }
}

fn is_word_char(ch: char) -> bool {
    ch.is_ascii_alphanumeric() || ch == '_'
}

fn matches_shorthand(ch: char, kind: char) -> bool {
    match kind {
        's' => ch.is_whitespace(),
        'S' => !ch.is_whitespace(),
        'd' => ch.is_ascii_digit(),
        'D' => !ch.is_ascii_digit(),
        'w' => is_word_char(ch),
        'W' => !is_word_char(ch),
        _ => false,
    }
}

// ---------------------------------------------------------------------------
// Hookify core data types and functions
// ---------------------------------------------------------------------------

fn strip_quotes(val: &str) -> String {
    let trimmed = val.trim();
    if trimmed.len() >= 2
        && ((trimmed.starts_with('"') && trimmed.ends_with('"'))
            || (trimmed.starts_with('\'') && trimmed.ends_with('\'')))
    {
        return trimmed[1..trimmed.len() - 1]
            .replace("\\\"", "\"")
            .replace("\\\\", "\\")
            .replace("\\n", "\n")
            .replace("\\t", "\t");
    }
    trimmed.to_string()
}

fn parse_scalar(raw: &str) -> Value {
    let s = raw.trim();
    if s == "true" {
        return Value::Bool(true);
    }
    if s == "false" {
        return Value::Bool(false);
    }
    if s == "null" {
        return Value::Null;
    }
    if let Ok(i) = s.parse::<i64>() {
        return json!(i);
    }
    if let Ok(f) = s.parse::<f64>() {
        if s.chars()
            .all(|c| c.is_ascii_digit() || c == '-' || c == '.')
        {
            return json!(f);
        }
    }
    Value::String(strip_quotes(s))
}

fn split_yaml_kv(line: &str) -> Option<(&str, &str)> {
    let colon_idx = line.find(':')?;
    let key = line[..colon_idx].trim();
    if key.is_empty()
        || !key
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-' || c == '.')
    {
        return None;
    }
    let rest = line[colon_idx + 1..].trim();
    Some((key, rest))
}

fn val_to_str(v: Option<&Value>) -> String {
    match v {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Number(n)) => n.to_string(),
        Some(Value::Bool(b)) => b.to_string(),
        Some(Value::Object(_) | Value::Array(_)) => {
            serde_json::to_string(v.unwrap()).unwrap_or_default()
        }
        _ => String::new(),
    }
}

/// Parses a `.agents/hookify.<name>.md` markdown document with YAML frontmatter.
pub fn parse_hookify_markdown(markdown: &str, source_path: &str) -> Option<Value> {
    let text = markdown.replace("\r\n", "\n");
    let after_open = text.strip_prefix("---\n")?;
    let (frontmatter, body_raw) = if let Some(idx) = after_open.find("\n---\n") {
        (&after_open[..idx], &after_open[idx + 5..])
    } else if let Some(stripped) = after_open.strip_suffix("\n---") {
        (stripped, "")
    } else {
        return None;
    };
    let body = body_raw.trim();

    let mut meta: Map<String, Value> = Map::new();
    let mut current_list_key: Option<String> = None;
    let mut current_map_key: Option<String> = None;

    for raw_line in frontmatter.split('\n') {
        let trimmed = raw_line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let indent = raw_line.chars().take_while(|c| c.is_whitespace()).count();

        if indent == 0 {
            current_list_key = None;
            current_map_key = None;
            let Some((key, rest)) = split_yaml_kv(trimmed) else {
                continue;
            };
            if rest.is_empty() {
                if key == "conditions" {
                    meta.insert(key.to_string(), Value::Array(Vec::new()));
                    current_list_key = Some(key.to_string());
                } else {
                    meta.insert(key.to_string(), Value::Object(Map::new()));
                    current_map_key = Some(key.to_string());
                }
            } else {
                meta.insert(key.to_string(), parse_scalar(rest));
            }
            continue;
        }

        if let Some(list_key) = &current_list_key {
            if let Some(after_dash) = trimmed.strip_prefix("- ") {
                let mut item = Map::new();
                if let Some((k, v)) = split_yaml_kv(after_dash.trim()) {
                    item.insert(k.to_string(), parse_scalar(v));
                }
                if let Some(Value::Array(arr)) = meta.get_mut(list_key) {
                    arr.push(Value::Object(item));
                }
            } else if let Some((k, v)) = split_yaml_kv(trimmed) {
                if let Some(Value::Array(arr)) = meta.get_mut(list_key) {
                    if let Some(Value::Object(last_item)) = arr.last_mut() {
                        last_item.insert(k.to_string(), parse_scalar(v));
                    }
                }
            }
            continue;
        }

        if let Some(map_key) = &current_map_key {
            if let Some((k, v)) = split_yaml_kv(trimmed) {
                if let Some(Value::Object(map_obj)) = meta.get_mut(map_key) {
                    map_obj.insert(k.to_string(), parse_scalar(v));
                }
            }
        }
    }

    let fallback_name = if !source_path.is_empty() {
        source_path
            .rsplit('/')
            .next()
            .unwrap_or("unnamed-rule")
            .strip_prefix("hookify.")
            .unwrap_or_else(|| source_path.rsplit('/').next().unwrap_or("unnamed-rule"))
            .strip_suffix(".md")
            .unwrap_or("unnamed-rule")
    } else {
        "unnamed-rule"
    };

    let name_raw = val_to_str(meta.get("name"));
    let name = if name_raw.trim().is_empty() {
        fallback_name.trim().to_string()
    } else {
        name_raw.trim().to_string()
    };

    let event_raw = val_to_str(meta.get("event"));
    let event = if event_raw.trim().is_empty() {
        "PreToolUse".to_string()
    } else {
        event_raw.trim().to_string()
    };

    let action_raw = val_to_str(meta.get("action"));
    let action = if action_raw.trim().is_empty() {
        "warn".to_string()
    } else {
        action_raw.trim().to_ascii_lowercase()
    };

    let enabled = meta.get("enabled") != Some(&Value::Bool(false));

    let mut conditions: Vec<Value> = meta
        .get("conditions")
        .and_then(|v| v.as_array())
        .map(|arr| arr.iter().filter(|c| c.is_object()).cloned().collect())
        .unwrap_or_default();

    if conditions.is_empty() {
        if let Some(pat_val) = meta.get("pattern") {
            if !pat_val.is_null() {
                let default_field = match event.to_ascii_lowercase().as_str() {
                    "file" => "Content",
                    _ => "CommandLine",
                };
                let field_str = val_to_str(meta.get("field"));
                let op_str = val_to_str(meta.get("operator"));
                conditions.push(json!({
                    "field": if field_str.is_empty() { default_field.to_string() } else { field_str },
                    "operator": if op_str.is_empty() { "regex_match".to_string() } else { op_str },
                    "pattern": val_to_str(Some(pat_val)),
                }));
            }
        }
    }

    let id_raw = val_to_str(meta.get("id"));
    let id = if id_raw.is_empty() {
        name.clone()
    } else {
        id_raw
    };

    let tool = {
        let t = val_to_str(meta.get("tool"));
        if !t.is_empty() {
            t
        } else {
            let m = val_to_str(meta.get("matcher"));
            if !m.is_empty() {
                m
            } else {
                "*".to_string()
            }
        }
    };

    let message = if !body.is_empty() {
        body.to_string()
    } else {
        let m = val_to_str(meta.get("message"));
        if !m.is_empty() {
            m
        } else {
            format!("Rule '{name}' triggered.")
        }
    };

    let mut out = Map::new();
    out.insert("id".to_string(), Value::String(id));
    out.insert("name".to_string(), Value::String(name));
    out.insert("enabled".to_string(), Value::Bool(enabled));
    out.insert("event".to_string(), Value::String(event));
    out.insert("tool".to_string(), Value::String(tool));
    out.insert("action".to_string(), Value::String(action));
    out.insert("conditions".to_string(), Value::Array(conditions));
    if let Some(Value::Object(ow)) = meta.get("overwrite") {
        out.insert("overwrite".to_string(), Value::Object(ow.clone()));
    }
    out.insert("message".to_string(), Value::String(message));
    out.insert(
        "source".to_string(),
        Value::String(if source_path.is_empty() {
            "markdown".to_string()
        } else {
            source_path.to_string()
        }),
    );

    Some(Value::Object(out))
}

/// Serializes a Hookify rule object back to `.agents/hookify.<name>.md` markdown.
pub fn serialize_hookify_markdown(rule: &Value) -> String {
    let empty = Map::new();
    let r = rule.as_object().unwrap_or(&empty);
    let name = {
        let n = val_to_str(r.get("name"));
        if !n.is_empty() {
            n
        } else {
            let id = val_to_str(r.get("id"));
            if !id.is_empty() {
                id
            } else {
                "unnamed-rule".to_string()
            }
        }
    };
    let enabled = r.get("enabled") != Some(&Value::Bool(false));
    let event = {
        let e = val_to_str(r.get("event"));
        if e.is_empty() {
            "PreToolUse".to_string()
        } else {
            e
        }
    };
    let action = {
        let a = val_to_str(r.get("action"));
        if a.is_empty() {
            "warn".to_string()
        } else {
            a
        }
    };
    let tool = {
        let t = val_to_str(r.get("tool"));
        if !t.is_empty() {
            t
        } else {
            let m = val_to_str(r.get("matcher"));
            if !m.is_empty() {
                m
            } else {
                "*".to_string()
            }
        }
    };

    let mut lines = vec![
        "---".to_string(),
        format!("name: {name}"),
        format!("enabled: {enabled}"),
        format!("event: {event}"),
    ];
    if !tool.is_empty() && tool != "*" {
        lines.push(format!("tool: {tool}"));
    }
    lines.push(format!("action: {action}"));

    let conditions = r.get("conditions").and_then(|v| v.as_array());
    if let Some(arr) = conditions.filter(|a| !a.is_empty()) {
        lines.push("conditions:".to_string());
        for c in arr {
            let Some(c_obj) = c.as_object() else {
                continue;
            };
            let pat_str = val_to_str(c_obj.get("pattern"));
            let pat_json = serde_json::to_string(&pat_str).unwrap_or_else(|_| "\"\"".to_string());
            let field = {
                let f = val_to_str(c_obj.get("field"));
                if f.is_empty() {
                    "CommandLine".to_string()
                } else {
                    f
                }
            };
            let op = {
                let o = val_to_str(c_obj.get("operator"));
                if o.is_empty() {
                    "regex_match".to_string()
                } else {
                    o
                }
            };
            lines.push(format!("  - field: {field}"));
            lines.push(format!("    operator: {op}"));
            lines.push(format!("    pattern: {pat_json}"));
        }
    } else {
        let pat = val_to_str(r.get("pattern"));
        if !pat.is_empty() {
            let pat_json = serde_json::to_string(&pat).unwrap_or_else(|_| "\"\"".to_string());
            lines.push(format!("pattern: {pat_json}"));
        }
    }

    if let Some(Value::Object(ow)) = r.get("overwrite") {
        lines.push("overwrite:".to_string());
        for (k, v) in ow {
            let v_json = serde_json::to_string(v).unwrap_or_else(|_| "null".to_string());
            lines.push(format!("  {k}: {v_json}"));
        }
    }

    lines.push("---".to_string());
    let msg = {
        let m = val_to_str(r.get("message"));
        if m.is_empty() {
            format!("Rule '{name}' triggered.")
        } else {
            m
        }
    };
    lines.push(msg.trim().to_string());
    lines.push(String::new());
    lines.join("\n")
}

/// Extracts a logical field from an Antigravity or Claude Code hook payload.
pub fn extract_field_from_payload(payload: &Value, field: &str) -> String {
    let empty = Map::new();
    let p = payload.as_object().unwrap_or(&empty);
    let args = p
        .get("toolCall")
        .and_then(|tc| tc.get("args"))
        .and_then(|v| v.as_object())
        .or_else(|| p.get("tool_input").and_then(|v| v.as_object()))
        .unwrap_or(&empty);

    let key = if field.trim().is_empty() {
        "CommandLine"
    } else {
        field.trim()
    };
    let lower = key.to_ascii_lowercase();

    if let Some(v) = args.get(key) {
        if !v.is_null() {
            return val_to_str(Some(v));
        }
    }
    if let Some(v) = p.get(key) {
        if !v.is_null() {
            return val_to_str(Some(v));
        }
    }

    let first_non_null = |candidates: &[Option<&Value>]| -> String {
        for c in candidates.iter().flatten() {
            if !c.is_null() {
                return val_to_str(Some(c));
            }
        }
        String::new()
    };

    match lower.as_str() {
        "command" | "commandline" | "cmd" => first_non_null(&[
            args.get("CommandLine"),
            args.get("command"),
            p.get("command"),
        ]),
        "file_path" | "filepath" | "path" | "file" => first_non_null(&[
            args.get("Path"),
            args.get("file_path"),
            args.get("path"),
            p.get("file_path"),
        ]),
        "content" | "new_text" | "replacement" => first_non_null(&[
            args.get("Content"),
            args.get("Replacement"),
            args.get("content"),
            args.get("new_string"),
            args.get("new_str"),
        ]),
        "target" | "old_text" | "old_string" => first_non_null(&[
            args.get("Target"),
            args.get("old_string"),
            args.get("old_str"),
        ]),
        "tool" | "tool_name" | "toolname" => first_non_null(&[
            p.get("toolCall").and_then(|tc| tc.get("name")),
            p.get("tool_name"),
        ]),
        "reason" | "stop_reason" | "transcript" => first_non_null(&[
            p.get("reason"),
            p.get("stop_reason"),
            p.get("transcript"),
            p.get("lastMessage"),
        ]),
        _ => String::new(),
    }
}

/// Evaluates a single condition against a hook payload.
pub fn evaluate_condition(condition: &Value, payload: &Value) -> bool {
    let Some(cond) = condition.as_object() else {
        return false;
    };
    let field_raw = val_to_str(cond.get("field"));
    let field = if field_raw.is_empty() {
        "CommandLine"
    } else {
        field_raw.as_str()
    };
    let op_raw = val_to_str(cond.get("operator"));
    let operator = if op_raw.trim().is_empty() {
        "regex_match".to_string()
    } else {
        op_raw.trim().to_ascii_lowercase()
    };
    let pattern = val_to_str(cond.get("pattern"));
    let raw_value = extract_field_from_payload(payload, field);
    let case_sensitive = cond.get("caseSensitive") == Some(&Value::Bool(true));

    let value = if case_sensitive {
        raw_value.clone()
    } else {
        raw_value.to_lowercase()
    };
    let target = if case_sensitive {
        pattern.clone()
    } else {
        pattern.to_lowercase()
    };

    match operator.as_str() {
        "regex_match" => CompiledRegex::compile(&pattern, case_sensitive)
            .map(|re| re.is_match(&raw_value))
            .unwrap_or(false),
        "contains" => value.contains(&target),
        "not_contains" => !value.contains(&target),
        "equals" => value == target,
        "starts_with" => value.starts_with(&target),
        "ends_with" => value.ends_with(&target),
        _ => false,
    }
}

fn matches_event_and_tool(rule: &Map<String, Value>, payload: &Value, phase: &str) -> bool {
    let rule_event_raw = val_to_str(rule.get("event"));
    let rule_event = if rule_event_raw.trim().is_empty() {
        "pretooluse".to_string()
    } else {
        rule_event_raw.trim().to_ascii_lowercase()
    };
    let tool_name = extract_field_from_payload(payload, "tool_name")
        .trim()
        .to_string();

    if phase == "Stop" {
        return rule_event == "stop" || rule_event == "all" || rule_event == "*";
    }

    if rule_event == "stop" {
        return false;
    }
    if rule_event == "bash" {
        if !tool_name.is_empty()
            && !matches!(
                tool_name.to_ascii_lowercase().as_str(),
                "run_command" | "bash" | "execute_command"
            )
        {
            return false;
        }
    } else if rule_event == "file" {
        if !tool_name.is_empty()
            && !matches!(
                tool_name.to_ascii_lowercase().as_str(),
                "write_file" | "edit_file" | "multi_edit" | "write" | "edit" | "replace"
            )
        {
            return false;
        }
    }

    let matcher_raw = {
        let t = val_to_str(rule.get("tool"));
        if !t.is_empty() {
            t
        } else {
            val_to_str(rule.get("matcher"))
        }
    };
    let matcher = matcher_raw.trim();
    if matcher.is_empty() || matcher == "*" || matcher.eq_ignore_ascii_case("all") {
        return true;
    }
    if tool_name.is_empty() {
        return false;
    }
    let anchored = format!("^({matcher})$");
    match CompiledRegex::compile(&anchored, false) {
        Ok(re) => re.is_match(&tool_name),
        Err(()) => matcher.eq_ignore_ascii_case(&tool_name),
    }
}

fn normalize_decision(action: &str) -> &'static str {
    match action.trim().to_ascii_lowercase().as_str() {
        "block" | "deny" => "deny",
        "force_ask" => "force_ask",
        "warn" | "ask" => "ask",
        "overwrite" => "overwrite",
        "allow" => "allow",
        _ => "ask",
    }
}

fn decision_rank(decision: &str) -> u8 {
    match decision {
        "allow" => 1,
        "overwrite" => 2,
        "ask" => 3,
        "force_ask" => 4,
        "deny" => 5,
        _ => 0,
    }
}

fn compute_overwritten_input(
    rule: &Map<String, Value>,
    current_args: &Map<String, Value>,
) -> Map<String, Value> {
    let mut args = current_args.clone();
    let Some(Value::Object(spec)) = rule.get("overwrite") else {
        return args;
    };

    if let (Some(Value::String(field_name)), Some(Value::String(find_pat)), Some(replace_val)) = (
        spec.get("field"),
        spec.get("find"),
        spec.get("replace").filter(|v| !v.is_null()),
    ) {
        let prev = val_to_str(args.get(field_name));
        let replace_str = val_to_str(Some(replace_val));
        let updated = match CompiledRegex::compile(find_pat, true) {
            Ok(re) => re.replace_all(&prev, &replace_str),
            Err(()) => prev.replace(find_pat, &replace_str),
        };
        args.insert(field_name.clone(), Value::String(updated));
        return args;
    }

    for (k, v) in spec {
        args.insert(k.clone(), v.clone());
    }
    args
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RuleEvalResult {
    pub matched: bool,
    pub rule_id: String,
    pub rule_name: String,
    pub action: String,
    pub decision: String,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub updated_input: Option<Map<String, Value>>,
}

/// Evaluates a single Hookify rule against a payload.
pub fn evaluate_rule(rule: &Value, payload: &Value, phase: &str) -> RuleEvalResult {
    let empty = Map::new();
    let r = rule.as_object().unwrap_or(&empty);
    let rule_id = {
        let id = val_to_str(r.get("id"));
        if !id.is_empty() {
            id
        } else {
            let n = val_to_str(r.get("name"));
            if !n.is_empty() {
                n
            } else {
                "unnamed".to_string()
            }
        }
    };
    let rule_name = {
        let n = val_to_str(r.get("name"));
        if !n.is_empty() {
            n
        } else {
            rule_id.clone()
        }
    };
    let action = {
        let a = val_to_str(r.get("action"));
        if a.is_empty() {
            "warn".to_string()
        } else {
            a.to_ascii_lowercase()
        }
    };
    let decision = normalize_decision(&action).to_string();
    let message = {
        let m = val_to_str(r.get("message"));
        if m.is_empty() {
            format!("Rule '{rule_name}' matched.")
        } else {
            m
        }
    };

    let unmatched = || RuleEvalResult {
        matched: false,
        rule_id: rule_id.clone(),
        rule_name: rule_name.clone(),
        action: action.clone(),
        decision: decision.clone(),
        message: message.clone(),
        updated_input: None,
    };

    if r.get("enabled") == Some(&Value::Bool(false)) {
        return unmatched();
    }
    if !matches_event_and_tool(r, payload, phase) {
        return unmatched();
    }

    let conditions: Vec<Value> = match r.get("conditions").and_then(|v| v.as_array()) {
        Some(arr) if !arr.is_empty() => arr.clone(),
        _ => {
            let pat = val_to_str(r.get("pattern"));
            if !pat.is_empty() {
                let default_field = if phase == "Stop" {
                    "reason"
                } else {
                    "CommandLine"
                };
                let f = val_to_str(r.get("field"));
                let o = val_to_str(r.get("operator"));
                vec![json!({
                    "field": if f.is_empty() { default_field.to_string() } else { f },
                    "operator": if o.is_empty() { "regex_match".to_string() } else { o },
                    "pattern": pat,
                })]
            } else {
                Vec::new()
            }
        }
    };

    if conditions.is_empty() {
        return unmatched();
    }

    if !conditions.iter().all(|c| evaluate_condition(c, payload)) {
        return unmatched();
    }

    let p_obj = payload.as_object().unwrap_or(&empty);
    let raw_args = p_obj
        .get("toolCall")
        .and_then(|tc| tc.get("args"))
        .and_then(|v| v.as_object())
        .or_else(|| p_obj.get("tool_input").and_then(|v| v.as_object()))
        .unwrap_or(&empty);

    let updated_input = if decision == "overwrite" {
        Some(compute_overwritten_input(r, raw_args))
    } else {
        None
    };

    RuleEvalResult {
        matched: true,
        rule_id,
        rule_name,
        action,
        decision,
        message,
        updated_input,
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PreToolHookSpecificOutput {
    hook_event_name: &'static str,
    permission_decision: String,
    permission_decision_reason: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    updated_input: Option<Map<String, Value>>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PreToolHookOutput {
    permission_decision: String,
    permission_decision_reason: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    updated_input: Option<Map<String, Value>>,
    hook_specific_output: PreToolHookSpecificOutput,
}

#[derive(Debug, Clone)]
pub struct PreToolEvalSummary {
    pub decision: String,
    pub permission_decision: String,
    pub reason: String,
    pub matched_rules: Vec<RuleEvalResult>,
    pub updated_input: Option<Map<String, Value>>,
    pub hook_output_json: String,
}

/// Evaluates a list of Hookify rules for a `PreToolUse` hook event.
pub fn evaluate_pre_tool_use(rules: &[Value], payload: &Value) -> PreToolEvalSummary {
    let empty = Map::new();
    let p_obj = payload.as_object().unwrap_or(&empty);
    let mut current_args = p_obj
        .get("toolCall")
        .and_then(|tc| tc.get("args"))
        .and_then(|v| v.as_object())
        .or_else(|| p_obj.get("tool_input").and_then(|v| v.as_object()))
        .cloned()
        .unwrap_or_default();

    let mut matched_rules = Vec::new();
    let mut has_overwrite = false;

    for rule in rules {
        let res = evaluate_rule(rule, payload, "PreToolUse");
        if res.matched {
            if res.decision == "overwrite" && res.updated_input.is_some() {
                if let Some(r_obj) = rule.as_object() {
                    current_args = compute_overwritten_input(r_obj, &current_args);
                    has_overwrite = true;
                }
            }
            matched_rules.push(res);
        }
    }

    if matched_rules.is_empty() {
        return PreToolEvalSummary {
            decision: "allow".to_string(),
            permission_decision: "allow".to_string(),
            reason: String::new(),
            matched_rules: Vec::new(),
            updated_input: None,
            hook_output_json: "{}".to_string(),
        };
    }

    let mut winning_decision = "allow".to_string();
    for m in &matched_rules {
        if decision_rank(&m.decision) > decision_rank(&winning_decision) {
            winning_decision = m.decision.clone();
        }
    }

    let reason = matched_rules
        .iter()
        .map(|m| format!("[{}] {}", m.rule_name, m.message))
        .collect::<Vec<_>>()
        .join("\n\n");

    let permission_decision = if winning_decision == "overwrite" {
        "allow".to_string()
    } else {
        winning_decision.clone()
    };

    let final_updated_input = if has_overwrite && permission_decision != "deny" {
        Some(current_args)
    } else {
        None
    };

    let hook_output = PreToolHookOutput {
        permission_decision: permission_decision.clone(),
        permission_decision_reason: reason.clone(),
        updated_input: final_updated_input.clone(),
        hook_specific_output: PreToolHookSpecificOutput {
            hook_event_name: "PreToolUse",
            permission_decision: permission_decision.clone(),
            permission_decision_reason: reason.clone(),
            updated_input: final_updated_input.clone(),
        },
    };

    let hook_output_json = serde_json::to_string(&hook_output).unwrap_or_else(|_| "{}".to_string());

    PreToolEvalSummary {
        decision: winning_decision,
        permission_decision,
        reason,
        matched_rules,
        updated_input: final_updated_input,
        hook_output_json,
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct StopBlockHookOutput {
    #[serde(rename = "continue")]
    continue_flag: bool,
    decision: &'static str,
    stop_reason: String,
    reason: String,
    system_message: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct StopWarnHookOutput {
    #[serde(rename = "continue")]
    continue_flag: bool,
    system_message: String,
}

#[derive(Debug, Clone)]
pub struct StopEvalSummary {
    pub continue_flag: bool,
    pub stop_reason: String,
    pub system_message: String,
    pub matched_rules: Vec<RuleEvalResult>,
    pub hook_output_json: String,
}

/// Evaluates a list of Hookify rules for a `Stop` hook event.
pub fn evaluate_stop(rules: &[Value], payload: &Value) -> StopEvalSummary {
    let mut matched_rules = Vec::new();
    for rule in rules {
        let res = evaluate_rule(rule, payload, "Stop");
        if res.matched {
            matched_rules.push(res);
        }
    }

    if matched_rules.is_empty() {
        return StopEvalSummary {
            continue_flag: true,
            stop_reason: String::new(),
            system_message: String::new(),
            matched_rules: Vec::new(),
            hook_output_json: "{}".to_string(),
        };
    }

    let has_blocking = matched_rules.iter().any(|m| m.decision == "deny");
    let message = matched_rules
        .iter()
        .map(|m| format!("[{}] {}", m.rule_name, m.message))
        .collect::<Vec<_>>()
        .join("\n\n");

    if has_blocking {
        let out = StopBlockHookOutput {
            continue_flag: false,
            decision: "block",
            stop_reason: message.clone(),
            reason: message.clone(),
            system_message: message.clone(),
        };
        let hook_output_json = serde_json::to_string(&out).unwrap_or_else(|_| "{}".to_string());
        return StopEvalSummary {
            continue_flag: false,
            stop_reason: message.clone(),
            system_message: message,
            matched_rules,
            hook_output_json,
        };
    }

    let out = StopWarnHookOutput {
        continue_flag: true,
        system_message: message.clone(),
    };
    let hook_output_json = serde_json::to_string(&out).unwrap_or_else(|_| "{}".to_string());
    StopEvalSummary {
        continue_flag: true,
        stop_reason: String::new(),
        system_message: message,
        matched_rules,
        hook_output_json,
    }
}

#[derive(Serialize, Deserialize)]
struct AuditEvent {
    id: String,
    timestamp: u64,
    event: String,
    tool: String,
    decision: String,
    rules: Vec<String>,
    reason: String,
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

/// Resolves the app data directory from `ANTIGRAVITY_APP_DATA_DIR` or `HOME`.
pub fn resolve_app_dir(app_data_dir: Option<&str>, home_dir: Option<&str>) -> Option<PathBuf> {
    if let Some(dir) = app_data_dir.filter(|s| !s.is_empty()) {
        return Some(PathBuf::from(dir));
    }
    let home = home_dir.filter(|s| !s.is_empty())?;
    Some(Path::new(home).join(".gemini").join("antigravity"))
}

/// Evaluates the full Hookify hook against `payload_str` and `app_dir`.
pub fn handle_hookify_payload(payload_str: &str, app_dir: Option<&Path>) -> String {
    if payload_str.is_empty() {
        return "{}".to_string();
    }
    let Ok(payload) = serde_json::from_str::<Value>(payload_str) else {
        return "{}".to_string();
    };
    let Some(p_obj) = payload.as_object() else {
        return "{}".to_string();
    };

    let mut rules: Vec<Value> = Vec::new();
    if let Some(dir) = app_dir {
        let global_rules_file = dir.join("hookify-rules.json");
        if let Ok(raw) = fs::read_to_string(global_rules_file) {
            if let Ok(parsed) = serde_json::from_str::<Value>(&raw) {
                if let Some(arr) = parsed.as_array() {
                    rules.extend(arr.iter().cloned());
                } else if let Some(arr) = parsed
                    .as_object()
                    .and_then(|o| o.get("rules"))
                    .and_then(|v| v.as_array())
                {
                    rules.extend(arr.iter().cloned());
                }
            }
        }
    }

    let cwd = p_obj
        .get("toolCall")
        .and_then(|tc| tc.get("args"))
        .and_then(|a| a.get("Cwd"))
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .or_else(|| {
            p_obj
                .get("cwd")
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
        })
        .map(PathBuf::from)
        .or_else(|| env::current_dir().ok());

    if let Some(cwd_path) = cwd {
        let agents_dir = cwd_path.join(".agents");
        if let Ok(entries) = fs::read_dir(&agents_dir) {
            let mut names: Vec<String> = entries
                .filter_map(|e| e.ok())
                .filter_map(|e| e.file_name().into_string().ok())
                .filter(|n| {
                    n.starts_with("hookify.") && n.ends_with(".md") && n.len() > "hookify..md".len()
                })
                .collect();
            names.sort();
            for name in names {
                let full = agents_dir.join(&name);
                if let Ok(md_content) = fs::read_to_string(&full) {
                    let full_str = full.to_string_lossy();
                    if let Some(rule) = parse_hookify_markdown(&md_content, &full_str) {
                        rules.push(rule);
                    }
                }
            }
        }
    }

    let is_stop = p_obj.get("hook_event_name").and_then(|v| v.as_str()) == Some("Stop")
        || p_obj.get("event").and_then(|v| v.as_str()) == Some("Stop")
        || (!p_obj.contains_key("toolCall")
            && !p_obj.contains_key("tool_name")
            && (p_obj.contains_key("stop_hook_active") || p_obj.contains_key("reason")));

    let (matched_rules, decision_str, reason_str, hook_output_json) = if is_stop {
        let res = evaluate_stop(&rules, &payload);
        let dec = if !res.continue_flag { "deny" } else { "warn" }.to_string();
        let rsn = if !res.stop_reason.is_empty() {
            res.stop_reason
        } else {
            res.system_message
        };
        (res.matched_rules, dec, rsn, res.hook_output_json)
    } else {
        let res = evaluate_pre_tool_use(&rules, &payload);
        (
            res.matched_rules,
            res.decision,
            res.reason,
            res.hook_output_json,
        )
    };

    if !matched_rules.is_empty() {
        if let Some(dir) = app_dir {
            if fs::create_dir_all(dir).is_ok() {
                let events_file = dir.join("hookify-events.json");
                let mut existing: Vec<AuditEvent> = fs::read_to_string(&events_file)
                    .ok()
                    .and_then(|raw| serde_json::from_str::<Vec<AuditEvent>>(&raw).ok())
                    .unwrap_or_default();

                let tool_name = p_obj
                    .get("toolCall")
                    .and_then(|tc| tc.get("name"))
                    .and_then(|v| v.as_str())
                    .filter(|s| !s.is_empty())
                    .or_else(|| {
                        p_obj
                            .get("tool_name")
                            .and_then(|v| v.as_str())
                            .filter(|s| !s.is_empty())
                    })
                    .unwrap_or(if is_stop { "Stop" } else { "unknown" })
                    .to_string();

                let ts = now_millis();
                let new_ev = AuditEvent {
                    id: format!("{ts}-rust0"),
                    timestamp: ts,
                    event: if is_stop {
                        "Stop".to_string()
                    } else {
                        "PreToolUse".to_string()
                    },
                    tool: tool_name,
                    decision: decision_str,
                    rules: matched_rules
                        .iter()
                        .map(|r| {
                            if !r.rule_name.is_empty() {
                                r.rule_name.clone()
                            } else {
                                r.rule_id.clone()
                            }
                        })
                        .collect(),
                    reason: reason_str,
                };

                let mut next = Vec::with_capacity(existing.len() + 1);
                next.push(new_ev);
                next.append(&mut existing);
                next.truncate(100);
                if let Ok(serialized) = serde_json::to_string_pretty(&next) {
                    let tmp = events_file.with_extension("json.tmp");
                    if fs::write(&tmp, serialized).is_ok() {
                        let _ = fs::rename(&tmp, &events_file);
                    }
                }
            }
        }
    }

    hook_output_json
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_markdown_and_round_trips() {
        let md = "---\nname: block-rm-rf\nenabled: true\nevent: bash\ntool: run_command\naction: block\nconditions:\n  - field: CommandLine\n    operator: regex_match\n    pattern: \"rm\\\\s+-rf\\\\s+/\"\n  - field: CommandLine\n    operator: not_contains\n    pattern: \"--dry-run\"\n---\nDo not run destructive `rm -rf /` commands.\n";
        let rule = parse_hookify_markdown(md, ".agents/hookify.block-rm-rf.md").unwrap();
        assert_eq!(rule["name"], "block-rm-rf");
        assert_eq!(rule["enabled"], true);
        assert_eq!(rule["event"], "bash");
        assert_eq!(rule["tool"], "run_command");
        assert_eq!(rule["action"], "block");
        assert_eq!(rule["conditions"].as_array().unwrap().len(), 2);

        let serialized = serialize_hookify_markdown(&rule);
        let reparsed = parse_hookify_markdown(&serialized, "").unwrap();
        assert_eq!(reparsed["name"], rule["name"]);
        assert_eq!(reparsed["conditions"], rule["conditions"]);
    }

    #[test]
    fn evaluates_all_six_operators() {
        let payload = json!({
            "toolCall": {
                "name": "run_command",
                "args": {
                    "CommandLine": "git push --force origin main",
                    "Path": "/workspace/src/index.ts"
                }
            }
        });
        assert!(evaluate_condition(
            &json!({"field": "CommandLine", "operator": "regex_match", "pattern": "git\\s+push.*--force"}),
            &payload
        ));
        assert!(evaluate_condition(
            &json!({"field": "CommandLine", "operator": "contains", "pattern": "--force"}),
            &payload
        ));
        assert!(evaluate_condition(
            &json!({"field": "CommandLine", "operator": "not_contains", "pattern": "--force-with-lease"}),
            &payload
        ));
        assert!(evaluate_condition(
            &json!({"field": "Path", "operator": "equals", "pattern": "/workspace/src/index.ts"}),
            &payload
        ));
        assert!(evaluate_condition(
            &json!({"field": "CommandLine", "operator": "starts_with", "pattern": "git push"}),
            &payload
        ));
        assert!(evaluate_condition(
            &json!({"field": "Path", "operator": "ends_with", "pattern": ".ts"}),
            &payload
        ));
    }

    #[test]
    fn pre_tool_use_precedence_and_overwrite() {
        let rules = vec![
            json!({
                "name": "rewrite-npm-to-pnpm",
                "enabled": true,
                "event": "bash",
                "action": "overwrite",
                "conditions": [{"field": "CommandLine", "operator": "starts_with", "pattern": "npm test"}],
                "overwrite": {"field": "CommandLine", "find": "^npm test", "replace": "bazel test //..."},
                "message": "Rewrote npm test to bazel test //..."
            }),
            json!({
                "name": "ask-on-test",
                "enabled": true,
                "event": "bash",
                "action": "warn",
                "conditions": [{"field": "CommandLine", "operator": "contains", "pattern": "test"}],
                "message": "Confirm test run."
            }),
        ];
        let payload = json!({
            "toolCall": {
                "name": "run_command",
                "args": {"CommandLine": "npm test --watch"}
            }
        });
        let res = evaluate_pre_tool_use(&rules, &payload);
        assert_eq!(res.decision, "ask");
        assert_eq!(res.permission_decision, "ask");
        assert_eq!(
            res.updated_input.unwrap().get("CommandLine").unwrap(),
            "bazel test //... --watch"
        );
    }

    #[test]
    fn stop_rule_blocks_and_allows() {
        let rules = vec![json!({
            "name": "require-worktree-hygiene",
            "enabled": true,
            "event": "Stop",
            "action": "block",
            "conditions": [{"field": "reason", "operator": "not_contains", "pattern": "worktree hygiene"}],
            "message": "Include worktree hygiene status before stopping."
        })];

        let blocked = evaluate_stop(
            &rules,
            &json!({"hook_event_name": "Stop", "reason": "All done!"}),
        );
        assert!(!blocked.continue_flag);

        let allowed = evaluate_stop(
            &rules,
            &json!({"hook_event_name": "Stop", "reason": "All done! Verified worktree hygiene."}),
        );
        assert!(allowed.continue_flag);
        assert_eq!(allowed.hook_output_json, "{}");
    }
}
