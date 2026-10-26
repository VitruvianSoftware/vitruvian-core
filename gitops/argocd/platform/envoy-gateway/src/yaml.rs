// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Self-contained YAML parser into `serde_json::Value` and regex engine for
//! GitOps platform manifest test suites.

use serde_json::{Map, Number, Value};
use std::path::{Path, PathBuf};

/// Resolve a data file path across Bazel runfiles and workspace roots.
pub fn resolve_data_path(pkg_rel_dir: &str, rel_file: &str) -> PathBuf {
    let direct = Path::new(pkg_rel_dir).join(rel_file);
    if direct.is_file() {
        return direct;
    }
    let local = Path::new(rel_file);
    if local.is_file() {
        return local.to_path_buf();
    }
    if let Ok(srcdir) = std::env::var("TEST_SRCDIR") {
        let ws = std::env::var("TEST_WORKSPACE").unwrap_or_else(|_| "_main".to_string());
        let p = Path::new(&srcdir)
            .join(&ws)
            .join(pkg_rel_dir)
            .join(rel_file);
        if p.is_file() {
            return p;
        }
        let p_root = Path::new(&srcdir).join(&ws).join(rel_file);
        if p_root.is_file() {
            return p_root;
        }
    }
    if let Ok(ws_dir) = std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        let p = Path::new(&ws_dir).join(pkg_rel_dir).join(rel_file);
        if p.is_file() {
            return p;
        }
    }
    direct
}

/// Parse all non-null YAML documents in `src` (equivalent to `[d for d in yaml.safe_load_all(f) if d]`).
pub fn parse_all(src: &str) -> Result<Vec<Value>, String> {
    let src = src.strip_prefix('\u{feff}').unwrap_or(src);
    let raw_lines: Vec<&str> = src
        .split('\n')
        .map(|l| l.strip_suffix('\r').unwrap_or(l))
        .collect();

    let mut docs = Vec::new();
    let mut p = Parser {
        raw_lines,
        pos: 0,
        override_line: None,
    };

    while p.pos < p.raw_lines.len() || p.override_line.is_some() {
        p.skip_doc_markers_and_blanks();
        if p.pos >= p.raw_lines.len() && p.override_line.is_none() {
            break;
        }
        if let Some((first_ind, _)) = p.peek()? {
            let doc = p.block(first_ind)?;
            if !doc.is_null() {
                docs.push(doc);
            }
        } else {
            break;
        }
    }
    Ok(docs)
}

/// Parse a single YAML document from `src` (equivalent to `yaml.safe_load(src)`).
pub fn parse_doc(src: &str) -> Result<Value, String> {
    let mut docs = parse_all(src)?;
    if docs.is_empty() {
        Ok(Value::Null)
    } else {
        Ok(docs.remove(0))
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Chomp {
    Clip,
    Strip,
    Keep,
}

struct Parser<'a> {
    raw_lines: Vec<&'a str>,
    pos: usize,
    override_line: Option<(usize, String)>,
}

fn is_doc_start(raw: &str) -> bool {
    raw == "---" || raw.starts_with("--- ") || raw.starts_with("---\t")
}

fn is_doc_end(raw: &str) -> bool {
    raw == "..." || raw.starts_with("... ") || raw.starts_with("...\t")
}

impl<'a> Parser<'a> {
    fn skip_doc_markers_and_blanks(&mut self) {
        if self.override_line.is_some() {
            return;
        }
        while self.pos < self.raw_lines.len() {
            let raw = self.raw_lines[self.pos];
            let stripped = strip_comment(raw);
            let trimmed = stripped.trim_matches([' ', '\t']);
            if trimmed.is_empty() {
                self.pos += 1;
                continue;
            }
            let indent = stripped.len() - stripped.trim_start_matches(' ').len();
            if indent == 0 && (is_doc_start(trimmed) || is_doc_end(trimmed)) {
                self.pos += 1;
                continue;
            }
            break;
        }
    }

    fn peek(&mut self) -> Result<Option<(usize, String)>, String> {
        if let Some(ref ov) = self.override_line {
            return Ok(Some(ov.clone()));
        }
        while self.pos < self.raw_lines.len() {
            let raw = self.raw_lines[self.pos];
            let stripped = strip_comment(raw);
            let trimmed_end = stripped.trim_end_matches([' ', '\t']);
            if trimmed_end.trim_start_matches([' ', '\t']).is_empty() {
                self.pos += 1;
                continue;
            }
            let indent = trimmed_end.len() - trimmed_end.trim_start_matches(' ').len();
            let text = &trimmed_end[indent..];
            if text.starts_with('\t') {
                return Err(format!(
                    "line {}: tab character in indentation",
                    self.pos + 1
                ));
            }
            if indent == 0 && (is_doc_start(text) || is_doc_end(text)) {
                return Ok(None);
            }
            return Ok(Some((indent, text.to_string())));
        }
        Ok(None)
    }

    fn consume_line(&mut self) {
        self.override_line = None;
        self.pos += 1;
    }

    fn block(&mut self, n: usize) -> Result<Value, String> {
        let Some((ind, text)) = self.peek()? else {
            return Ok(Value::Null);
        };
        if is_seq_line(&text) {
            return self.seq(ind);
        }
        if split_map_entry(&text)?.is_some() {
            return self.map(ind);
        }
        self.consume_line();
        if let Some((style, chomp, explicit_ind)) = parse_block_scalar_header(&text) {
            return self.read_block_scalar(style, chomp, explicit_ind, n);
        }
        let v = parse_inline(&text)?;
        self.fold_plain(v, ind)
    }

    fn fold_plain(&mut self, v: Value, n: usize) -> Result<Value, String> {
        let Value::String(mut s) = v else {
            return Ok(v);
        };
        while let Some((ind, text)) = self.peek()? {
            if ind <= n || is_seq_line(&text) || split_map_entry(&text)?.is_some() {
                break;
            }
            self.consume_line();
            s.push(' ');
            s.push_str(&text);
        }
        Ok(Value::String(s))
    }

    fn seq(&mut self, n: usize) -> Result<Value, String> {
        let mut items = Vec::new();
        while let Some((ind, text)) = self.peek()? {
            if ind < n {
                break;
            }
            if ind > n {
                return Err(format!(
                    "line {}: unexpected indentation in sequence",
                    self.pos + 1
                ));
            }
            if !is_seq_line(&text) {
                break;
            }
            let after = &text[1..];
            let rest = after.trim_start_matches([' ', '\t']);
            if rest.is_empty() {
                self.consume_line();
                match self.peek()? {
                    Some((child_ind, _)) if child_ind > n => {
                        items.push(self.block(child_ind)?);
                    }
                    _ => items.push(Value::Null),
                }
            } else if let Some((style, chomp, explicit_ind)) = parse_block_scalar_header(rest) {
                self.consume_line();
                let s = self.read_block_scalar(style, chomp, explicit_ind, n)?;
                items.push(s);
            } else {
                let col = n + 1 + (after.len() - rest.len());
                self.override_line = Some((col, rest.to_string()));
                let v = self.block(col)?;
                items.push(v);
            }
        }
        Ok(Value::Array(items))
    }

    fn map(&mut self, n: usize) -> Result<Value, String> {
        let mut entries = Map::new();
        while let Some((ind, text)) = self.peek()? {
            if ind < n {
                break;
            }
            if ind > n {
                return Err(format!(
                    "line {}: unexpected indentation in mapping",
                    self.pos + 1
                ));
            }
            let Some((key, rest)) = split_map_entry(&text)? else {
                break;
            };
            self.consume_line();
            let value = if rest.is_empty() {
                match self.peek()? {
                    Some((child_ind, _)) if child_ind > n => self.block(child_ind)?,
                    Some((child_ind, ref child_text))
                        if child_ind == n && is_seq_line(child_text) =>
                    {
                        self.seq(n)?
                    }
                    _ => Value::Null,
                }
            } else if let Some((style, chomp, explicit_ind)) = parse_block_scalar_header(&rest) {
                self.read_block_scalar(style, chomp, explicit_ind, n)?
            } else {
                let v = parse_inline(&rest)?;
                self.fold_plain(v, n)?
            };
            entries.insert(key, value);
        }
        Ok(Value::Object(entries))
    }

    fn read_block_scalar(
        &mut self,
        style: char,
        chomp: Chomp,
        explicit_ind: Option<usize>,
        parent_indent: usize,
    ) -> Result<Value, String> {
        let mut block_indent = explicit_ind.map(|m| parent_indent + m);
        if block_indent.is_none() {
            let mut look = self.pos;
            while look < self.raw_lines.len() {
                let raw = self.raw_lines[look];
                let lead = raw.len() - raw.trim_start_matches(' ').len();
                if !raw[lead..].is_empty() {
                    if lead > parent_indent {
                        block_indent = Some(lead);
                    }
                    break;
                }
                look += 1;
            }
        }
        let Some(b_ind) = block_indent else {
            while self.pos < self.raw_lines.len() {
                let raw = self.raw_lines[self.pos];
                if raw.trim_matches(' ').is_empty() {
                    self.pos += 1;
                } else {
                    break;
                }
            }
            return Ok(Value::String(String::new()));
        };

        let mut raw_collected: Vec<(bool, &str)> = Vec::new();
        while self.pos < self.raw_lines.len() {
            let raw = self.raw_lines[self.pos];
            let lead = raw.len() - raw.trim_start_matches(' ').len();
            if raw[lead..].is_empty() {
                let extra = if raw.len() > b_ind { &raw[b_ind..] } else { "" };
                raw_collected.push((extra.is_empty(), extra));
                self.pos += 1;
                continue;
            }
            if lead == 0 && (is_doc_start(raw) || is_doc_end(raw)) {
                break;
            }
            if lead < b_ind {
                break;
            }
            raw_collected.push((false, &raw[b_ind..]));
            self.pos += 1;
        }

        let mut trailing_blanks = 0;
        while raw_collected
            .last()
            .map_or(false, |(is_blank, _)| *is_blank)
        {
            raw_collected.pop();
            trailing_blanks += 1;
        }

        if raw_collected.is_empty() {
            let out = match chomp {
                Chomp::Keep => "\n".repeat(trailing_blanks),
                _ => String::new(),
            };
            return Ok(Value::String(out));
        }

        let mut body = String::new();
        if style == '|' {
            for (idx, (_, line)) in raw_collected.iter().enumerate() {
                if idx > 0 {
                    body.push('\n');
                }
                body.push_str(line);
            }
        } else {
            let mut idx = 0;
            while idx < raw_collected.len() {
                let (is_blank, line) = raw_collected[idx];
                if is_blank {
                    body.push('\n');
                    idx += 1;
                    continue;
                }
                let more_indented = line.starts_with(' ') || line.starts_with('\t');
                if idx > 0 {
                    let (prev_blank, prev_line) = raw_collected[idx - 1];
                    let prev_more = prev_line.starts_with(' ') || prev_line.starts_with('\t');
                    if !prev_blank {
                        if more_indented || prev_more {
                            body.push('\n');
                        } else {
                            body.push(' ');
                        }
                    }
                }
                body.push_str(line);
                idx += 1;
            }
        }

        match chomp {
            Chomp::Strip => {}
            Chomp::Clip => body.push('\n'),
            Chomp::Keep => {
                body.push('\n');
                for _ in 0..trailing_blanks {
                    body.push('\n');
                }
            }
        }
        Ok(Value::String(body))
    }
}

fn parse_block_scalar_header(s: &str) -> Option<(char, Chomp, Option<usize>)> {
    let s = s.trim_matches([' ', '\t']);
    let mut chars = s.chars();
    let style = chars.next()?;
    if style != '|' && style != '>' {
        return None;
    }
    let mut chomp = Chomp::Clip;
    let mut seen_chomp = false;
    let mut explicit_ind = None;
    for c in chars {
        match c {
            '-' if !seen_chomp => {
                chomp = Chomp::Strip;
                seen_chomp = true;
            }
            '+' if !seen_chomp => {
                chomp = Chomp::Keep;
                seen_chomp = true;
            }
            '1'..='9' if explicit_ind.is_none() => {
                explicit_ind = Some((c as u8 - b'0') as usize);
            }
            _ => return None,
        }
    }
    Some((style, chomp, explicit_ind))
}

fn strip_comment(s: &str) -> String {
    let chars: Vec<char> = s.chars().collect();
    let mut out = String::with_capacity(s.len());
    let mut prev: Option<char> = None;
    let mut prev_sig: Option<char> = None;
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        let after_space = matches!(prev, None | Some(' ') | Some('\t'));
        if c == '#' && after_space {
            break;
        }
        let token_start = matches!(
            prev,
            None | Some(' ') | Some('\t') | Some('[') | Some('{') | Some(',')
        ) && matches!(
            prev_sig,
            None | Some('-') | Some(':') | Some('[') | Some('{') | Some(',') | Some('?')
        );
        if (c == '"' || c == '\'') && token_start {
            out.push(c);
            i += 1;
            while i < chars.len() {
                let q = chars[i];
                out.push(q);
                i += 1;
                if c == '"' && q == '\\' {
                    if i < chars.len() {
                        out.push(chars[i]);
                        i += 1;
                    }
                    continue;
                }
                if q == c {
                    if c == '\'' && i < chars.len() && chars[i] == '\'' {
                        out.push('\'');
                        i += 1;
                        continue;
                    }
                    break;
                }
            }
            prev = Some(c);
            prev_sig = Some(c);
            continue;
        }
        out.push(c);
        prev = Some(c);
        if c != ' ' && c != '\t' {
            prev_sig = Some(c);
        }
        i += 1;
    }
    out
}

fn is_seq_line(text: &str) -> bool {
    text == "-" || text.starts_with("- ") || text.starts_with("-\t")
}

fn split_map_entry(text: &str) -> Result<Option<(String, String)>, String> {
    let first = text.chars().next().unwrap_or(' ');
    if first == '"' || first == '\'' {
        let Ok((key, end)) = quoted(text) else {
            return Ok(None);
        };
        let after = text[end..].trim_start_matches([' ', '\t']);
        if let Some(rest) = after.strip_prefix(':') {
            if rest.is_empty() || rest.starts_with([' ', '\t']) {
                return Ok(Some((key, rest.trim_matches([' ', '\t']).to_string())));
            }
        }
        return Ok(None);
    }
    if first == '[' || first == '{' || is_seq_line(text) {
        return Ok(None);
    }
    let bytes = text.as_bytes();
    for (i, &b) in bytes.iter().enumerate() {
        if b == b':' && (i + 1 == bytes.len() || bytes[i + 1] == b' ' || bytes[i + 1] == b'\t') {
            let key = text[..i].trim_end_matches([' ', '\t']);
            if key.is_empty() || key.contains(['(', ')', '[', ']', '{', '}', '"', '\'']) {
                return Ok(None);
            }
            return Ok(Some((
                key.to_string(),
                text[i + 1..].trim_matches([' ', '\t']).to_string(),
            )));
        }
    }
    Ok(None)
}

fn parse_inline(s: &str) -> Result<Value, String> {
    let s = s.trim_matches([' ', '\t']);
    match s.chars().next() {
        None => Ok(Value::Null),
        Some('"') | Some('\'') => {
            let (v, end) = quoted(s)?;
            if !s[end..].trim_matches([' ', '\t']).is_empty() {
                return Err(format!("trailing characters after quoted string in {s:?}"));
            }
            Ok(Value::String(v))
        }
        Some('[') => {
            let (node, end) = flow_seq(s)?;
            if !s[end..].trim_matches([' ', '\t']).is_empty() {
                return Err(format!("trailing characters after flow sequence in {s:?}"));
            }
            Ok(node)
        }
        Some('{') => {
            let (node, end) = flow_map(s)?;
            if !s[end..].trim_matches([' ', '\t']).is_empty() {
                return Err(format!("trailing characters after flow mapping in {s:?}"));
            }
            Ok(node)
        }
        _ => parse_plain_scalar(s),
    }
}

fn parse_plain_scalar(s: &str) -> Result<Value, String> {
    let s = s.trim_matches([' ', '\t']);
    if matches!(s, "" | "~" | "null" | "Null" | "NULL") {
        return Ok(Value::Null);
    }
    if matches!(s, "true" | "True" | "TRUE") {
        return Ok(Value::Bool(true));
    }
    if matches!(s, "false" | "False" | "FALSE") {
        return Ok(Value::Bool(false));
    }
    if let Some(oct) = s.strip_prefix("0o") {
        if let Ok(n) = i64::from_str_radix(oct, 8) {
            return Ok(Value::Number(Number::from(n)));
        }
    }
    if s.len() > 1 && s.starts_with('0') && s[1..].bytes().all(|b| (b'0'..=b'7').contains(&b)) {
        if let Ok(n) = i64::from_str_radix(&s[1..], 8) {
            return Ok(Value::Number(Number::from(n)));
        }
    }
    if let Ok(n) = s.parse::<i64>() {
        return Ok(Value::Number(Number::from(n)));
    }
    if s.contains('.')
        && s.bytes()
            .all(|b| b.is_ascii_digit() || matches!(b, b'.' | b'-' | b'+' | b'e' | b'E'))
        && s.matches('.').count() == 1
    {
        if let Ok(f) = s.parse::<f64>() {
            if let Some(num) = Number::from_f64(f) {
                return Ok(Value::Number(num));
            }
        }
    }
    Ok(Value::String(s.to_string()))
}

fn quoted(s: &str) -> Result<(String, usize), String> {
    let q = s.as_bytes()[0];
    let mut out = String::new();
    let mut it = s.char_indices().skip(1).peekable();
    while let Some((i, c)) = it.next() {
        if q == b'\'' {
            if c == '\'' {
                if matches!(it.peek(), Some((_, '\''))) {
                    it.next();
                    out.push('\'');
                    continue;
                }
                return Ok((out, i + 1));
            }
            out.push(c);
            continue;
        }
        match c {
            '"' => return Ok((out, i + 1)),
            '\\' => {
                let Some((_, e)) = it.next() else {
                    return Err("unexpected end of double-quoted string".to_string());
                };
                match e {
                    '0' => out.push('\0'),
                    'a' => out.push('\u{7}'),
                    'b' => out.push('\u{8}'),
                    't' | '\t' => out.push('\t'),
                    'n' => out.push('\n'),
                    'v' => out.push('\u{b}'),
                    'f' => out.push('\u{c}'),
                    'r' => out.push('\r'),
                    'e' => out.push('\u{1b}'),
                    ' ' => out.push(' '),
                    '"' => out.push('"'),
                    '/' => out.push('/'),
                    '\\' => out.push('\\'),
                    _ => {
                        out.push('\\');
                        out.push(e);
                    }
                }
            }
            c => out.push(c),
        }
    }
    Err("unterminated quoted scalar".to_string())
}

fn flow_seq(s: &str) -> Result<(Value, usize), String> {
    let bytes = s.as_bytes();
    let mut i = 1;
    let mut items = Vec::new();
    let skip_ws = |i: &mut usize| {
        while *i < bytes.len() && (bytes[*i] == b' ' || bytes[*i] == b'\t') {
            *i += 1;
        }
    };
    loop {
        skip_ws(&mut i);
        if i >= bytes.len() {
            return Err("unterminated flow sequence".to_string());
        }
        if bytes[i] == b']' {
            return Ok((Value::Array(items), i + 1));
        }
        let item = match bytes[i] {
            b'"' | b'\'' => {
                let (v, end) = quoted(&s[i..])?;
                i += end;
                Value::String(v)
            }
            b'[' => {
                let (n, end) = flow_seq(&s[i..])?;
                i += end;
                n
            }
            b'{' => {
                let (n, end) = flow_map(&s[i..])?;
                i += end;
                n
            }
            _ => {
                let start = i;
                while i < bytes.len() && !matches!(bytes[i], b',' | b']') {
                    i += 1;
                }
                let raw = s[start..i].trim_matches([' ', '\t']);
                parse_plain_scalar(raw)?
            }
        };
        items.push(item);
        skip_ws(&mut i);
        if i >= bytes.len() {
            return Err("unterminated flow sequence".to_string());
        }
        match bytes[i] {
            b',' => i += 1,
            b']' => return Ok((Value::Array(items), i + 1)),
            _ => return Err("expected ',' or ']' in flow sequence".to_string()),
        }
    }
}

fn flow_map(s: &str) -> Result<(Value, usize), String> {
    let bytes = s.as_bytes();
    let mut i = 1;
    let mut map = Map::new();
    let skip_ws = |i: &mut usize| {
        while *i < bytes.len() && (bytes[*i] == b' ' || bytes[*i] == b'\t') {
            *i += 1;
        }
    };
    loop {
        skip_ws(&mut i);
        if i >= bytes.len() {
            return Err("unterminated flow mapping".to_string());
        }
        if bytes[i] == b'}' {
            return Ok((Value::Object(map), i + 1));
        }
        let key = if bytes[i] == b'"' || bytes[i] == b'\'' {
            let (k, end) = quoted(&s[i..])?;
            i += end;
            k
        } else {
            let start = i;
            while i < bytes.len() && !matches!(bytes[i], b':' | b'}' | b',') {
                i += 1;
            }
            s[start..i].trim_matches([' ', '\t']).to_string()
        };
        skip_ws(&mut i);
        if i >= bytes.len() || bytes[i] != b':' {
            return Err("expected ':' in flow mapping".to_string());
        }
        i += 1;
        skip_ws(&mut i);
        let val = match bytes.get(i).copied() {
            Some(b'"') | Some(b'\'') => {
                let (v, end) = quoted(&s[i..])?;
                i += end;
                Value::String(v)
            }
            Some(b'[') => {
                let (n, end) = flow_seq(&s[i..])?;
                i += end;
                n
            }
            Some(b'{') => {
                let (n, end) = flow_map(&s[i..])?;
                i += end;
                n
            }
            _ => {
                let start = i;
                while i < bytes.len() && !matches!(bytes[i], b',' | b'}') {
                    i += 1;
                }
                parse_plain_scalar(s[start..i].trim_matches([' ', '\t']))?
            }
        };
        map.insert(key, val);
        skip_ws(&mut i);
        if i >= bytes.len() {
            return Err("unterminated flow mapping".to_string());
        }
        match bytes[i] {
            b',' => i += 1,
            b'}' => return Ok((Value::Object(map), i + 1)),
            _ => return Err("expected ',' or '}' in flow mapping".to_string()),
        }
    }
}
