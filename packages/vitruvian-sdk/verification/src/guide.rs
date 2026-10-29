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

//! The guide check behind `:guide_test`.
//! Verifies every fenced block, manifest field, protocol message, kit method table,
//! and CLI usage reference in `docs/writing-a-tool.md` and the kit sample READMEs.

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::fs;
use std::path::Path;

use conformance_rs_lib::json::{self, Value};

use crate::find_package_dir;
use crate::schema;

pub const EXAMPLES: &[&str] = &[
    "samples/hello-typescript/README.md",
    "samples/hello-python-kit/README.md",
    "samples/hello-panel-typescript/README.md",
    "samples/hello-panel-python/README.md",
    "samples/hello-go/README.md",
    "samples/hello-rust/README.md",
];

pub const VERBS: &[&str] = &["init", "validate", "run"];
pub const ALONE: &[&str] = &["--version"];
pub const FLAGS: &[&str] = &[
    "--id",
    "--name",
    "--publisher",
    "--template",
    "--sdk",
    "--command",
    "--refuse",
    "--app-path",
    "--wait",
];

fn slice_chars(s: &str, max_chars: usize) -> &str {
    match s.char_indices().nth(max_chars) {
        Some((idx, _)) => &s[..idx],
        None => s,
    }
}

fn is_word_byte(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

/// Each fenced block: `(info_line, lines, start_line_1_based)`.
/// A block inside a list is indented, and is read without its indent.
pub fn blocks(text: &str) -> Vec<(String, Vec<String>, usize)> {
    let mut found = Vec::new();
    let mut info: Option<String> = None;
    let mut lines: Vec<String> = Vec::new();
    let mut start: usize = 0;
    let mut indent: usize = 0;

    for (idx, line) in text.split('\n').enumerate() {
        let number = idx + 1;
        let trimmed_start = line.trim_start_matches(' ');
        if trimmed_start.starts_with("```") {
            if info.is_none() {
                indent = line.len() - trimmed_start.len();
                let tag = line.trim()[3..].trim().to_string();
                info = Some(tag);
                lines = Vec::new();
                start = number;
            } else {
                found.push((info.take().unwrap(), std::mem::take(&mut lines), start));
            }
        } else if info.is_some() {
            let stripped = if line.len() >= indent
                && line.is_char_boundary(indent)
                && line[..indent].trim().is_empty()
            {
                &line[indent..]
            } else {
                line
            };
            lines.push(stripped.to_string());
        }
    }
    found
}

pub fn message_problems(
    lines: &[String],
    where_loc: &str,
    schema_val: &Value,
    table: &HashMap<String, Value>,
    shown: &mut BTreeSet<String>,
) -> Vec<String> {
    let mut problems = Vec::new();
    let mut asked: HashMap<String, String> = HashMap::new();

    for line in lines {
        let message = match json::loads(line) {
            Ok(m) => m,
            Err(_) => {
                problems.push(format!("{where_loc}: not JSON: {}", slice_chars(line, 60)));
                continue;
            }
        };
        if !schema::is_valid(schema_val, &message) {
            problems.push(format!(
                "{where_loc}: not a message of the protocol: {}",
                slice_chars(line, 80)
            ));
            continue;
        }
        if let Some(method) = message.get("method").and_then(|m| m.as_str()) {
            shown.insert(method.to_string());
            let Some(_row) = table.get(method) else {
                problems.push(format!("{where_loc}: {method} is no message of version 1"));
                continue;
            };
            if let Some(id) = message.get("id") {
                asked.insert(id.dumps_compact(), method.to_string());
            }
        } else if let Some(result_val) = message.get("result") {
            let id_key = message
                .get("id")
                .map(|id| id.dumps_compact())
                .unwrap_or_default();
            let Some(method) = asked.get(&id_key) else {
                problems.push(format!("{where_loc}: a result with no request above it"));
                continue;
            };
            let result_def = table
                .get(method)
                .and_then(|r| r.get("result"))
                .and_then(|r| r.as_str())
                .unwrap_or("");
            let part = Value::Obj(vec![(
                "$ref".into(),
                Value::Str(format!("#/$defs/{result_def}")),
            )]);
            if !schema::is_valid_with_root(&part, result_val, schema_val) {
                problems.push(format!(
                    "{where_loc}: not the result of {method}: {}",
                    slice_chars(line, 80)
                ));
            }
        }
    }
    problems
}

pub fn excerpt_problems(
    lines: &[String],
    where_loc: &str,
    path: &str,
    package_dir: &Path,
) -> Vec<String> {
    let Ok(source) = fs::read_to_string(package_dir.join(path)) else {
        return vec![format!("{where_loc}: there is no file {path}")];
    };
    let joined = lines.join("\n");
    if !source.contains(&joined) {
        return vec![format!(
            "{where_loc}: these lines are not in {path}, together and in this order"
        )];
    }
    Vec::new()
}

/// Replaces `r" ?\\\n\s*"` with `" "`: a Swift line continuation reads as one space.
pub fn join_swift_line_continuations(source: &str) -> String {
    let mut out = String::with_capacity(source.len());
    let mut chars = source.chars().peekable();
    while let Some(c) = chars.next() {
        if c == ' ' {
            let mut look = chars.clone();
            if look.next() == Some('\\') && look.next() == Some('\n') {
                chars.next(); // '\'
                chars.next(); // '\n'
                while let Some(&nc) = chars.peek() {
                    if nc.is_whitespace() {
                        chars.next();
                    } else {
                        break;
                    }
                }
                out.push(' ');
                continue;
            }
        } else if c == '\\' && chars.peek() == Some(&'\n') {
            chars.next(); // '\n'
            while let Some(&nc) = chars.peek() {
                if nc.is_whitespace() {
                    chars.next();
                } else {
                    break;
                }
            }
            out.push(' ');
            continue;
        }
        out.push(c);
    }
    out
}

pub fn said_problems(
    lines: &[String],
    where_loc: &str,
    path: &str,
    package_dir: &Path,
) -> Vec<String> {
    let Ok(raw_source) = fs::read_to_string(package_dir.join(path)) else {
        return vec![format!("{where_loc}: there is no file {path}")];
    };
    let source = join_swift_line_continuations(&raw_source);
    let mut problems = Vec::new();
    for line in lines {
        let trimmed = line.trim();
        if !trimmed.is_empty() && !source.contains(trimmed) {
            problems.push(format!(
                "{where_loc}: the command does not say this, by {path}: {}",
                slice_chars(trimmed, 60)
            ));
        }
    }
    problems
}

fn split_table_cells(line: &str) -> Vec<&str> {
    let parts: Vec<&str> = line.split('|').collect();
    if parts.len() <= 2 {
        return Vec::new();
    }
    parts[1..parts.len() - 1].iter().map(|c| c.trim()).collect()
}

/// Checks `re.match(r"`\w+(\(|`)", s)`.
fn starts_with_backtick_call_or_word(s: &str) -> bool {
    let bytes = s.as_bytes();
    if bytes.first() != Some(&b'`') {
        return false;
    }
    let mut i = 1;
    while i < bytes.len() && is_word_byte(bytes[i]) {
        i += 1;
    }
    i > 1 && i < bytes.len() && (bytes[i] == b'(' || bytes[i] == b'`')
}

/// Extracts `re.findall(r"`(\w+)", s)`.
fn find_backtick_words(s: &str) -> Vec<String> {
    let bytes = s.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'`' {
            let start = i + 1;
            let mut end = start;
            while end < bytes.len() && is_word_byte(bytes[end]) {
                end += 1;
            }
            if end > start {
                out.push(s[start..end].to_string());
                i = end;
                continue;
            }
        }
        i += 1;
    }
    out
}

/// Extracts `re.findall(r"`([\w/]+)`", s)`.
fn find_backtick_methods(s: &str) -> Vec<String> {
    let bytes = s.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'`' {
            let start = i + 1;
            let mut end = start;
            while end < bytes.len() && (is_word_byte(bytes[end]) || bytes[end] == b'/') {
                end += 1;
            }
            if end > start && end < bytes.len() && bytes[end] == b'`' {
                out.push(s[start..end].to_string());
                i = end + 1;
                continue;
            }
        }
        i += 1;
    }
    out
}

/// Checks `re.search(rf"public (func|var) {call}\b", kit)`.
fn kit_has_public_member(kit: &str, call: &str) -> bool {
    for prefix in [format!("public func {call}"), format!("public var {call}")] {
        let mut search_from = 0;
        while let Some(pos) = kit[search_from..].find(&prefix) {
            let after_idx = search_from + pos + prefix.len();
            let next_byte = kit.as_bytes().get(after_idx).copied();
            if !next_byte.is_some_and(is_word_byte) {
                return true;
            }
            search_from = search_from + pos + 1;
        }
    }
    false
}

pub fn kit_problems(guide: &str, table: &HashMap<String, Value>, kit: &str) -> Vec<String> {
    let mut problems = Vec::new();
    let mut rows = 0usize;
    let mut inside = false;

    for (idx, line) in guide.split('\n').enumerate() {
        let number = idx + 1;
        let cells = split_table_cells(line);
        if cells.len() >= 2 && cells[0] == "Call on `app`" && cells[1] == "Message" {
            inside = true;
        } else if !line.starts_with('|') {
            inside = false;
        }
        if !inside || cells.len() != 3 || !starts_with_backtick_call_or_word(cells[0]) {
            continue;
        }
        let where_loc = format!("writing-a-tool.md:{number}");
        let calls = find_backtick_words(cells[0]);
        let raw_methods = find_backtick_methods(cells[1]);
        rows += 1;
        for method in &raw_methods {
            if !table.contains_key(method) {
                problems.push(format!("{where_loc}: {method} is no message of version 1"));
            }
        }
        let methods: Vec<String> = raw_methods
            .into_iter()
            .filter(|m| table.contains_key(m))
            .collect();
        for call in &calls {
            if !kit_has_public_member(kit, call) {
                problems.push(format!("{where_loc}: the kit has no call `{call}`"));
            }
        }
        for method in &methods {
            let row = &table[method];
            if row.get("sender").and_then(|s| s.as_str()) != Some("tool") {
                continue;
            }
            let uses = row.get("uses").and_then(|u| u.as_str()).unwrap_or("");
            let expected_cell = if !uses.is_empty() {
                format!("`{uses}`")
            } else {
                String::new()
            };
            if cells[2] != expected_cell {
                let want_desc = if !uses.is_empty() { uses } else { "nothing" };
                let got_desc = if !cells[2].is_empty() {
                    cells[2]
                } else {
                    "nothing"
                };
                problems.push(format!(
                    "{where_loc}: {method} needs {want_desc} in uses, not {got_desc}"
                ));
            }
        }
    }
    if rows < 10 {
        problems.push(format!(
            "the table of the kit's calls has {rows} rows this test can read"
        ));
    }
    problems
}

/// Extracts `re.findall(r"`app\.(?:(\w+)\.)?(\w+)`", s)`.
fn find_go_app_calls(s: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let mut rest = s;
    while let Some(pos) = rest.find("`app.") {
        let after_prefix = &rest[pos + 5..];
        if let Some(end_bt) = after_prefix.find('`') {
            let inner = &after_prefix[..end_bt];
            let parts: Vec<&str> = inner.split('.').collect();
            if parts.len() == 1 && !parts[0].is_empty() && parts[0].bytes().all(is_word_byte) {
                out.push((String::new(), parts[0].to_string()));
                rest = &after_prefix[end_bt + 1..];
                continue;
            } else if parts.len() == 2
                && !parts[0].is_empty()
                && parts[0].bytes().all(is_word_byte)
                && !parts[1].is_empty()
                && parts[1].bytes().all(is_word_byte)
            {
                out.push((parts[0].to_string(), parts[1].to_string()));
                rest = &after_prefix[end_bt + 1..];
                continue;
            }
        }
        rest = &rest[pos + 1..];
    }
    out
}

/// Extracts `re.findall(r"`app\.(?:(\w+)\(\)\.)?(\w+)`", s)`.
fn find_rust_app_calls(s: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let mut rest = s;
    while let Some(pos) = rest.find("`app.") {
        let after_prefix = &rest[pos + 5..];
        if let Some(end_bt) = after_prefix.find('`') {
            let inner = &after_prefix[..end_bt];
            if let Some((grp, nm)) = inner.split_once("().") {
                if !grp.is_empty()
                    && grp.bytes().all(is_word_byte)
                    && !nm.is_empty()
                    && nm.bytes().all(is_word_byte)
                {
                    out.push((grp.to_string(), nm.to_string()));
                    rest = &after_prefix[end_bt + 1..];
                    continue;
                }
            } else if !inner.is_empty() && inner.bytes().all(is_word_byte) {
                out.push((String::new(), inner.to_string()));
                rest = &after_prefix[end_bt + 1..];
                continue;
            }
        }
        rest = &rest[pos + 1..];
    }
    out
}

/// Checks `re.search(rf"func \(\w+ \*?{owner}\) {name}\(", go)`.
fn go_has_method(go: &str, owner: &str, name: &str) -> bool {
    let mut rest = go;
    while let Some(pos) = rest.find("func (") {
        let after = &rest[pos + 6..];
        let recv_len = after.bytes().take_while(|&b| is_word_byte(b)).count();
        if recv_len > 0 && after.as_bytes().get(recv_len) == Some(&b' ') {
            let after_space = &after[recv_len + 1..];
            let after_star = after_space.strip_prefix('*').unwrap_or(after_space);
            let target = format!("{owner}) {name}(");
            if after_star.starts_with(&target) {
                return true;
            }
        }
        rest = &rest[pos + 6..];
    }
    false
}

pub fn native_kit_problems(
    guide: &str,
    table: &HashMap<String, Value>,
    go: &str,
    rust: &str,
) -> Vec<String> {
    let mut problems = Vec::new();
    let mut rows = 0usize;
    let mut inside = false;

    for (idx, line) in guide.split('\n').enumerate() {
        let number = idx + 1;
        let cells = split_table_cells(line);
        if cells.len() >= 3 && cells[0] == "In Go" && cells[1] == "In Rust" && cells[2] == "Message"
        {
            inside = true;
            continue;
        }
        if !line.starts_with('|') {
            inside = false;
        }
        if !inside || cells.len() != 4 || !cells[0].starts_with('`') {
            continue;
        }
        let where_loc = format!("writing-a-tool.md:{number}");
        rows += 1;
        for (group, name) in find_go_app_calls(cells[0]) {
            let owner = if group.is_empty() { "App" } else { &group };
            if !go_has_method(go, owner, &name) {
                let prefix = if group.is_empty() {
                    String::new()
                } else {
                    format!("{group}.")
                };
                problems.push(format!(
                    "{where_loc}: the Go kit has no call app.{prefix}{name}"
                ));
            }
        }
        for (group, name) in find_rust_app_calls(cells[1]) {
            if !group.is_empty() && !rust.contains(&format!("pub fn {group}(")) {
                problems.push(format!("{where_loc}: the Rust kit has no app.{group}()"));
            }
            if !rust.contains(&format!("pub fn {name}(")) {
                problems.push(format!("{where_loc}: the Rust kit has no call {name}"));
            }
        }
        for method in find_backtick_methods(cells[2]) {
            let Some(row) = table.get(&method) else {
                problems.push(format!("{where_loc}: {method} is no message of version 1"));
                continue;
            };
            let uses = row.get("uses").and_then(|u| u.as_str()).unwrap_or("");
            if row.get("sender").and_then(|s| s.as_str()) == Some("tool") {
                let expected = if !uses.is_empty() {
                    format!("`{uses}`")
                } else {
                    String::new()
                };
                if cells[3] != expected {
                    let want_desc = if !uses.is_empty() { uses } else { "nothing" };
                    problems.push(format!("{where_loc}: {method} needs {want_desc} in uses"));
                }
            }
        }
    }
    if rows < 11 {
        problems.push(format!(
            "the table of the Go and Rust calls has {rows} rows this test can read"
        ));
    }
    problems
}

pub fn templates(package_dir: &Path) -> BTreeSet<String> {
    let source = fs::read_to_string(package_dir.join("Sources/VitruvianToolCLI/NewTool.swift"))
        .unwrap_or_default();
    let Some(idx) = source.find("public enum ToolTemplate") else {
        return BTreeSet::new();
    };
    let body = source[idx..].split('}').next().unwrap_or("");
    let mut set = BTreeSet::new();
    for line in body.lines() {
        let trimmed = line.trim();
        if let Some(after_case) = trimmed.strip_prefix("case ") {
            let name_len = after_case.bytes().take_while(|&b| is_word_byte(b)).count();
            if name_len > 0 {
                let name = &after_case[..name_len];
                let rest = &after_case[name_len..];
                if let Some(after_eq) = rest.strip_prefix(" = \"") {
                    if let Some(end_q) = after_eq.find('"') {
                        set.insert(after_eq[..end_q].to_string());
                        continue;
                    }
                }
                set.insert(name.to_string());
            }
        }
    }
    set
}

fn find_template_args(line: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut rest = line;
    while let Some(pos) = rest.find("--template ") {
        let after = &rest[pos + 11..];
        let tok: String = after.chars().take_while(|c| !c.is_whitespace()).collect();
        if !tok.is_empty() {
            out.push(tok);
        }
        rest = &rest[pos + 11..];
    }
    out
}

fn find_sdk_targets(line: &str) -> Vec<String> {
    const PREFIX: &str = "//packages/vitruvian-sdk:";
    let mut out = Vec::new();
    let mut rest = line;
    while let Some(pos) = rest.find(PREFIX) {
        let after = &rest[pos + PREFIX.len()..];
        let len = after
            .bytes()
            .take_while(|&b| is_word_byte(b) || b == b'.' || b == b'-')
            .count();
        if len > 0 {
            out.push(after[..len].to_string());
        }
        rest = &rest[pos + PREFIX.len()..];
    }
    out
}

pub fn shell_problems(
    lines: &[String],
    where_loc: &str,
    build: &str,
    valid_templates: &BTreeSet<String>,
) -> Vec<String> {
    let mut problems = Vec::new();
    for line in lines {
        let words: Vec<&str> = line.split_whitespace().collect();
        if words.first().copied() == Some("vitruvian-tool") {
            if let Some(&second) = words.get(1) {
                if ALONE.contains(&second) {
                    if words.len() > 2 {
                        problems.push(format!(
                            "{where_loc}: vitruvian-tool {second} takes nothing after it"
                        ));
                    }
                    continue;
                }
                if !VERBS.contains(&second) {
                    problems.push(format!("{where_loc}: vitruvian-tool has no `{second}`"));
                }
            }
            for &word in &words {
                if word.starts_with("--") && !FLAGS.contains(&word) {
                    problems.push(format!("{where_loc}: vitruvian-tool has no flag {word}"));
                }
            }
            for named in find_template_args(line) {
                if !valid_templates.contains(&named) {
                    problems.push(format!("{where_loc}: init has no template {named}"));
                }
            }
        }
        for target in find_sdk_targets(line) {
            if !build.contains(&format!("name = \"{target}\"")) {
                problems.push(format!("{where_loc}: this package has no target {target}"));
            }
        }
    }
    problems
}

pub fn run_in(package_dir: &Path) -> (i32, Vec<String>, String) {
    let read =
        |rel: &str| -> String { fs::read_to_string(package_dir.join(rel)).unwrap_or_default() };

    let guide = read("docs/writing-a-tool.md");
    let messages_schema = json::loads(&read("protocol/messages.schema.json")).unwrap();
    let manifest_schema = json::loads(&read("protocol/manifest.schema.json")).unwrap();
    let methods_json = json::loads(&read("protocol/methods.json")).unwrap();

    let mut table: HashMap<String, Value> = HashMap::new();
    let mut method_order: Vec<String> = Vec::new();
    if let Some(methods_arr) = methods_json.get("methods").and_then(|m| m.as_arr()) {
        for row in methods_arr {
            if let Some(m) = row.get("method").and_then(|v| v.as_str()) {
                method_order.push(m.to_string());
                table.insert(m.to_string(), row.clone());
            }
        }
    }

    let build = read("BUILD");
    let valid_templates = templates(package_dir);
    let mut problems = Vec::new();
    let mut shown = BTreeSet::new();
    let mut kinds: BTreeMap<String, usize> = BTreeMap::new();

    for (info, lines, start) in blocks(&guide) {
        let where_loc = format!("writing-a-tool.md:{start}");
        let kind = info
            .split(" file=")
            .next()
            .unwrap_or("")
            .split(" said=")
            .next()
            .unwrap_or("")
            .to_string();
        *kinds.entry(kind.clone()).or_insert(0) += 1;

        if info == "json message" {
            problems.extend(message_problems(
                &lines,
                &where_loc,
                &messages_schema,
                &table,
                &mut shown,
            ));
        } else if info == "json manifest" {
            if let Ok(example) = json::loads(&lines.join("\n")) {
                for err in schema::iter_errors(&manifest_schema, &example) {
                    problems.push(format!("{where_loc}: {err}"));
                }
                if let Some(defs) = manifest_schema.get("$defs") {
                    for field in schema::unknown_fields(&example, &manifest_schema, defs, "") {
                        problems.push(format!("{where_loc}: the manifest has no field `{field}`"));
                    }
                }
            }
        } else if matches!(
            kind.as_str(),
            "swift" | "python" | "javascript" | "go" | "rust"
        ) && info.contains(" file=")
        {
            let file_path = info.split_once(" file=").map(|(_, p)| p).unwrap_or("");
            problems.extend(excerpt_problems(&lines, &where_loc, file_path, package_dir));
        } else if info == "sh" {
            problems.extend(shell_problems(&lines, &where_loc, &build, &valid_templates));
        } else if let Some(file_path) = info.strip_prefix("sh file=") {
            problems.extend(excerpt_problems(&lines, &where_loc, file_path, package_dir));
        } else if let Some(file_path) = info.strip_prefix("text said=") {
            problems.extend(said_problems(&lines, &where_loc, file_path, package_dir));
        } else if info != "text" {
            problems.push(format!(
                "{where_loc}: a block of a kind this test does not know: `{info}`"
            ));
        }
    }

    for &example in EXAMPLES {
        for (info, lines, start) in blocks(&read(example)) {
            let where_loc = format!("{example}:{start}");
            if info == "sh" {
                problems.extend(shell_problems(&lines, &where_loc, &build, &valid_templates));
            } else if let Some((lang, file_path)) = info.split_once(" file=") {
                if matches!(lang, "sh" | "javascript" | "python" | "go" | "rust") {
                    problems.extend(excerpt_problems(&lines, &where_loc, file_path, package_dir));
                } else {
                    problems.push(format!(
                        "{where_loc}: a block of a kind this test does not know: `{info}`"
                    ));
                }
            } else {
                problems.push(format!(
                    "{where_loc}: a block of a kind this test does not know: `{info}`"
                ));
            }
        }
    }

    for method in &method_order {
        if !shown.contains(method) {
            problems.push(format!("the guide shows no example of {method}"));
        }
    }
    if let Some(props) = manifest_schema.get("properties").and_then(|p| p.as_obj()) {
        for (field, _) in props {
            if !guide.contains(&format!("| `{field}` |")) {
                problems.push(format!(
                    "the guide's table of the manifest has no row for `{field}`"
                ));
            }
        }
    }

    let kit_dir = package_dir.join("Sources").join("VitruvianToolKit");
    let mut swift_files: Vec<String> = fs::read_dir(&kit_dir)
        .ok()
        .into_iter()
        .flatten()
        .filter_map(|e| e.ok())
        .filter_map(|e| e.file_name().into_string().ok())
        .filter(|name| name.ends_with(".swift"))
        .collect();
    swift_files.sort();
    let kit_source: String = swift_files
        .iter()
        .map(|name| read(&format!("Sources/VitruvianToolKit/{name}")))
        .collect::<Vec<_>>()
        .join("\n");

    problems.extend(kit_problems(&guide, &table, &kit_source));
    problems.extend(native_kit_problems(
        &guide,
        &table,
        &read("go/toolkit/app.go"),
        &read("kits/rust/src/app.rs"),
    ));

    let words_swift = read("Sources/VitruvianToolCLI/Words.swift");
    let mut all_cli_tokens = BTreeSet::new();
    for &t in FLAGS.iter().chain(VERBS.iter()).chain(ALONE.iter()) {
        all_cli_tokens.insert(t);
    }
    for token in all_cli_tokens {
        if !words_swift.contains(token) {
            problems.push(format!("the command's usage does not name {token}"));
        }
    }

    let counts = kinds
        .iter()
        .map(|(k, c)| format!("{c} {k}"))
        .collect::<Vec<_>>()
        .join(", ");
    let status_word = if problems.is_empty() { "OK" } else { "FAILED" };
    let stdout_text = format!("guide: {counts}\nguide: {status_word}\n");
    let code = if problems.is_empty() { 0 } else { 1 };
    (code, problems, stdout_text)
}

pub fn main() -> i32 {
    let package_dir = match find_package_dir() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("{e}");
            return 1;
        }
    };
    let (code, problems, stdout_text) = run_in(&package_dir);
    for problem in problems {
        eprintln!("{problem}");
    }
    print!("{stdout_text}");
    code
}
