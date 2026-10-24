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

//! Transcript-tailing exporter daemon (`session_exporter.py`).
//!
//! Antigravity, the `agy` CLI and Claude Code all write JSONL transcripts.
//! This tails them from a per-file byte offset kept in a state file, keeps
//! cumulative per-session counts (turns, tools, subagents, tokens), posts
//! those as monotonic OTLP sums once per scan, and posts a span per new tool
//! call.
//!
//! The per-line handling deliberately mirrors the Python `try`/`except`
//! structure: a malformed line is skipped, but whatever it incremented before
//! the error stays incremented, exactly as in Python.

use crate::http_client::send_exporter_payload;
use crate::json::{dumps, J};
use crate::pyutil::{
    add_assign, as_number, get, get_or, gt_zero, index_mut, py_iter, py_len, py_str,
    require_hashable, strip, truthy, PyResult,
};
use crate::sys;
use crate::telemetry_hook::{get_hostname, get_target_endpoint, DEFAULT_ENDPOINT};
use std::fs::File;
use std::io::{BufRead, BufReader, Read, Seek, SeekFrom};

pub const DEFAULT_ANTIGRAVITY_MODEL: &str = "gemini-3.8-flash";
const LEGACY_DEFAULT_MODEL: &str = "gemini-3.7-flash";
const CLAUDE_DEFAULT_MODEL: &str = "claude-opus-5";
pub const HISTOGRAM_BOUNDS: [f64; 9] = [
    10.0, 50.0, 100.0, 250.0, 500.0, 1000.0, 2500.0, 5000.0, 10000.0,
];

/// One brain directory per Antigravity surface.
pub fn default_brain_dirs() -> Vec<String> {
    vec![
        sys::expanduser("~/.gemini/antigravity/brain"),
        sys::expanduser("~/.gemini/antigravity-cli/brain"),
        sys::expanduser("~/.gemini/antigravity-ide/brain"),
    ]
}

pub fn default_claude_dir() -> String {
    sys::expanduser("~/.claude/projects")
}

pub fn default_state_file() -> String {
    sys::expanduser("~/.gemini/antigravity/.telemetry_state.json")
}

/// The `service` label for a transcript, from the brain directory it is in.
pub fn service_for_transcript(path: &str) -> &'static str {
    if path.contains("/antigravity-cli/") {
        "agy"
    } else if path.contains("/antigravity-ide/") {
        "antigravity-ide"
    } else {
        "antigravity"
    }
}

/// The model a `<USER_SETTINGS_CHANGE>` line switches to, as a slug:
/// "... setting `Model Selection` from X to Gemini 3.8 Flash (High)." gives
/// `gemini-3.8-flash`.
///
/// A hand translation of
/// `re.search(r"setting [`']Model Selection[`'] from .*? to (.*?)\.(?:\s+|$)")`
/// with its leftmost, lazy-first matching order.
pub fn parse_model_selection(text: &str) -> Option<String> {
    let c: Vec<char> = text.chars().collect();
    let n = c.len();
    let lit = |at: usize, s: &str| -> bool {
        let s: Vec<char> = s.chars().collect();
        at + s.len() <= n && c[at..at + s.len()] == s[..]
    };
    let quote = |at: usize| at < n && (c[at] == '`' || c[at] == '\'');
    let at_end_or_space = |at: usize| at >= n || crate::pyutil::is_space(c[at]);

    let mut found: Option<(usize, usize)> = None;
    'start: for i in 0..n {
        if !lit(i, "setting ")
            || !quote(i + 8)
            || !lit(i + 9, "Model Selection")
            || !quote(i + 24)
            || !lit(i + 25, " from ")
        {
            continue;
        }
        let p = i + 31;
        let mut k = p;
        loop {
            if k > p && c[k - 1] == '\n' {
                break;
            }
            if lit(k, " to ") {
                let q = k + 4;
                let mut j = q;
                loop {
                    if j > q && c[j - 1] == '\n' {
                        break;
                    }
                    if j < n && c[j] == '.' && at_end_or_space(j + 1) {
                        found = Some((q, j));
                        break 'start;
                    }
                    if j >= n {
                        break;
                    }
                    j += 1;
                }
            }
            if k >= n {
                break;
            }
            k += 1;
        }
    }
    let (q, j) = found?;
    let raw: String = c[q..j].iter().collect();
    let raw = strip(&raw);
    let cleaned = strip(&remove_parentheticals(raw)).to_string();
    let slug = cleaned.to_lowercase().replace(' ', "-");
    if slug.is_empty() {
        None
    } else {
        Some(slug)
    }
}

/// `re.sub(r"\s*\([^)]*\)", "", s)`.
fn remove_parentheticals(s: &str) -> String {
    let c: Vec<char> = s.chars().collect();
    let mut out = String::new();
    let mut i = 0;
    while i < c.len() {
        let mut j = i;
        while j < c.len() && crate::pyutil::is_space(c[j]) {
            j += 1;
        }
        if j < c.len() && c[j] == '(' {
            if let Some(close) = c[j + 1..].iter().position(|ch| *ch == ')') {
                i = j + 1 + close + 1;
                continue;
            }
        }
        out.push(c[i]);
        i += 1;
    }
    out
}

/// `re.findall(r"conversationId[\\\"\s:]+([0-9a-f-]{36})", text)`.
pub fn find_conversation_ids(text: &str) -> Vec<String> {
    let c: Vec<char> = text.chars().collect();
    let key: Vec<char> = "conversationId".chars().collect();
    let sep = |ch: char| ch == '\\' || ch == '"' || ch == ':' || crate::pyutil::is_space(ch);
    let hexish = |ch: char| ch.is_ascii_digit() || ('a'..='f').contains(&ch) || ch == '-';
    let mut out = Vec::new();
    let mut i = 0;
    while i + key.len() <= c.len() {
        if c[i..i + key.len()] != key[..] {
            i += 1;
            continue;
        }
        let mut j = i + key.len();
        let sep_start = j;
        while j < c.len() && sep(c[j]) {
            j += 1;
        }
        if j > sep_start && j + 36 <= c.len() && c[j..j + 36].iter().all(|ch| hexish(*ch)) {
            out.push(c[j..j + 36].iter().collect());
            i = j + 36;
        } else {
            i += 1;
        }
    }
    out
}

fn is_hidden(name: &str) -> bool {
    name.starts_with('.')
}

/// Directory entries in `readdir` order, as `glob` sees them (hidden names
/// excluded).
fn list_dir(dir: &str) -> Vec<String> {
    match std::fs::read_dir(dir) {
        Ok(entries) => entries
            .filter_map(|e| e.ok())
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .filter(|n| !is_hidden(n))
            .collect(),
        Err(_) => Vec::new(),
    }
}

/// `glob(brain_dir/*/.system_generated/logs/transcript.jsonl)`.
pub fn glob_brain_transcripts(brain_dir: &str) -> Vec<String> {
    list_dir(brain_dir)
        .into_iter()
        .map(|name| {
            sys::join(
                &sys::join(brain_dir, &name),
                ".system_generated/logs/transcript.jsonl",
            )
        })
        .filter(|p| std::fs::symlink_metadata(p).is_ok())
        .collect()
}

/// `glob(claude_dir/*/*.jsonl)`.
pub fn glob_claude_transcripts(claude_dir: &str) -> Vec<String> {
    let mut out = Vec::new();
    for project in list_dir(claude_dir) {
        let pdir = sys::join(claude_dir, &project);
        if !std::path::Path::new(&pdir).is_dir() {
            continue;
        }
        for name in list_dir(&pdir) {
            if name.ends_with(".jsonl") {
                out.push(sys::join(&pdir, &name));
            }
        }
    }
    out
}

/// Decode with `errors="ignore"`: invalid UTF-8 bytes are dropped.
fn decode_ignore(mut bytes: &[u8]) -> String {
    let mut out = String::new();
    loop {
        match std::str::from_utf8(bytes) {
            Ok(s) => {
                out.push_str(s);
                return out;
            }
            Err(e) => {
                let good = e.valid_up_to();
                out.push_str(std::str::from_utf8(&bytes[..good]).expect("validated prefix"));
                let skip = e.error_len().unwrap_or(bytes.len() - good);
                bytes = &bytes[good + skip..];
            }
        }
    }
}

/// Text-mode lines with universal newlines (`\n`, `\r\n` and `\r` all end a
/// line), decoded with `errors="ignore"`. Returns the lines and the number of
/// bytes consumed.
fn universal_lines(bytes: &[u8]) -> Vec<String> {
    let mut lines = Vec::new();
    let mut start = 0;
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'\n' => {
                lines.push(decode_ignore(&bytes[start..i]) + "\n");
                i += 1;
                start = i;
            }
            b'\r' => {
                lines.push(decode_ignore(&bytes[start..i]) + "\n");
                i += if bytes.get(i + 1) == Some(&b'\n') {
                    2
                } else {
                    1
                };
                start = i;
            }
            _ => i += 1,
        }
    }
    if start < bytes.len() {
        lines.push(decode_ignore(&bytes[start..]));
    }
    lines
}

/// The first `max` lines of a file, for model detection.
fn head_lines(path: &str, max: usize) -> std::io::Result<Vec<String>> {
    let mut reader = BufReader::new(File::open(path)?);
    let mut out = Vec::new();
    let mut buf = Vec::new();
    while out.len() < max {
        buf.clear();
        if reader.read_until(b'\n', &mut buf)? == 0 {
            break;
        }
        for line in universal_lines(&buf) {
            if out.len() < max {
                out.push(line);
            }
        }
    }
    Ok(out)
}

/// Everything from `offset` to the end of the file, as lines, plus the new
/// offset (Python's `f.tell()` at EOF).
fn read_from(path: &str, offset: u64) -> std::io::Result<(Vec<String>, u64)> {
    let mut f = File::open(path)?;
    f.seek(SeekFrom::Start(offset))?;
    let mut bytes = Vec::new();
    f.read_to_end(&mut bytes)?;
    Ok((universal_lines(&bytes), offset + bytes.len() as u64))
}

fn zero_tokens() -> J {
    J::obj(vec![
        ("input", J::Int(0)),
        ("output", J::Int(0)),
        ("cached", J::Int(0)),
        ("thinking", J::Int(0)),
    ])
}

fn new_session(service: &str, model: J) -> J {
    J::obj(vec![
        ("service", J::str(service)),
        ("model", model),
        ("offset", J::Int(0)),
        ("turns", J::Int(0)),
        ("tools", J::empty_obj()),
        ("subagents", J::Int(0)),
        ("tokens", zero_tokens()),
        ("mtime", J::Int(0)),
    ])
}

fn reset_counts(st: &mut J) {
    st.set("turns", J::Int(0));
    st.set("tools", J::empty_obj());
    st.set("subagents", J::Int(0));
    st.set("tokens", zero_tokens());
}

/// `st["a"]["b"] += inc`.
fn bump2(st: &mut J, a: &str, b: &str, inc: i128) -> PyResult<()> {
    let inner = index_mut(st, a)?;
    let slot = index_mut(inner, b)?;
    add_assign(slot, &J::Int(inc))
}

/// `st[a] += inc`.
fn bump(st: &mut J, a: &str, inc: &J) -> PyResult<()> {
    add_assign(index_mut(st, a)?, inc)
}

/// `st["tools"][name] = st["tools"].get(name, 0) + 1`.
fn bump_tool(st: &mut J, tname: &J) -> PyResult<()> {
    let tools = index_mut(st, "tools")?;
    require_hashable(tname)?;
    let key = py_str(tname);
    let current = get(tools, &key)?.cloned().unwrap_or(J::Int(0));
    let next = crate::pyutil::num_add(&current, &J::Int(1))?;
    // `tools` is a dict here, or `get` above would have failed.
    tools.set(&key, next);
    Ok(())
}

/// A span to export for one new tool call.
#[derive(Clone, Debug)]
pub struct PendingSpan {
    pub name: String,
    pub tool_name: J,
    pub duration_ms: f64,
    pub model: J,
}

/// `st.get("model", default)`: a present `null` stays `null`.
fn model_or(st: &J, default: &J) -> J {
    st.get("model").cloned().unwrap_or_else(|| default.clone())
}

pub struct TranscriptScanner {
    pub brain_dirs: Vec<String>,
    pub claude_dir: String,
    pub state_file: String,
    pub endpoint: String,
    pub host: String,
    pub latest_model: String,
    /// Conversation id -> model, learned from a parent's `GENERIC` steps so a
    /// subagent's transcript gets its parent's model.
    pub subagent_models: Vec<(String, J)>,
    /// Transcript path -> cumulative session state (a dict per path).
    pub sessions: J,
}

fn sm_get<'a>(map: &'a [(String, J)], key: &str) -> Option<&'a J> {
    map.iter().find(|(k, _)| k == key).map(|(_, v)| v)
}

fn sm_set(map: &mut Vec<(String, J)>, key: &str, value: J) {
    match map.iter_mut().find(|(k, _)| k == key) {
        Some(slot) => slot.1 = value,
        None => map.push((key.to_string(), value)),
    }
}

struct AgCtx<'a> {
    new_events: &'a mut i64,
    spans: &'a mut Vec<PendingSpan>,
    latest_model: &'a mut String,
    subagent_models: &'a mut Vec<(String, J)>,
    convo_id: &'a str,
    backfill_all: bool,
}

fn process_antigravity_step(step: &J, st: &mut J, ctx: &mut AgCtx) -> PyResult<()> {
    let stype = get(step, "type")?.cloned().unwrap_or(J::Null);
    let content = get_or(step, "content", J::str(""))?;

    if stype == J::str("USER_INPUT") {
        if let J::Str(text) = &content {
            if text.contains("<USER_SETTINGS_CHANGE>") {
                if let Some(det) = parse_model_selection(text) {
                    st.set("model", J::str(det.clone()));
                    *ctx.latest_model = det.clone();
                    if !ctx.convo_id.is_empty() {
                        sm_set(ctx.subagent_models, ctx.convo_id, J::str(det));
                    }
                }
            }
        }
    }

    let th = get_or(step, "thinking", J::str(""))?;
    if truthy(&th) {
        if let J::Str(s) = &th {
            bump2(
                st,
                "tokens",
                "thinking",
                (s.chars().count() as f64 / 4.0) as i128,
            )?;
        }
    }

    if stype == J::str("PLANNER_RESPONSE") {
        bump(st, "turns", &J::Int(1))?;
        *ctx.new_events += 1;
        bump2(st, "tokens", "input", 4500)?;
        bump2(st, "tokens", "output", 350)?;
        bump2(st, "tokens", "cached", 32000)?;

        for tc in py_iter(&get_or(step, "tool_calls", J::Arr(vec![]))?)? {
            let tname = get_or(&tc, "name", J::str("unknown"))?;
            bump_tool(st, &tname)?;
            let dur_ms = match tname.as_str() {
                Some("run_command") => 450.0,
                Some("replace_file_content") | Some("write_to_file") => 120.0,
                Some("invoke_subagent") => {
                    bump(st, "subagents", &J::Int(1))?;
                    2500.0
                }
                _ => 180.0,
            };
            if !ctx.backfill_all {
                let latest = J::str(ctx.latest_model.clone());
                ctx.spans.push(PendingSpan {
                    name: format!("antigravity:{}", py_str(&tname)),
                    tool_name: tname.clone(),
                    duration_ms: dur_ms,
                    model: model_or(st, &latest),
                });
            }
        }
    } else if stype == J::str("GENERIC") {
        *ctx.new_events += 1;
        if let J::Str(text) = &content {
            if text.contains("conversationId") {
                for child in find_conversation_ids(text) {
                    let latest = J::str(ctx.latest_model.clone());
                    sm_set(ctx.subagent_models, &child, model_or(st, &latest));
                }
            }
        }
    }
    Ok(())
}

struct CcCtx<'a> {
    new_events: &'a mut i64,
    spans: &'a mut Vec<PendingSpan>,
    backfill_all: bool,
}

fn process_claude_line(obj: &J, st: &mut J, ctx: &mut CcCtx) -> PyResult<()> {
    let msg = get_or(obj, "message", J::empty_obj())?;
    let is_assistant = get(obj, "type")?
        .map(|t| *t == J::str("assistant"))
        .unwrap_or(false)
        || get(&msg, "role")?
            .map(|r| *r == J::str("assistant"))
            .unwrap_or(false);
    if !is_assistant {
        return Ok(());
    }
    *ctx.new_events += 1;
    let model = get_or(&msg, "model", J::str(CLAUDE_DEFAULT_MODEL))?;
    st.set("model", model.clone());
    bump(st, "turns", &J::Int(1))?;

    let usage = get_or(&msg, "usage", J::empty_obj())?;
    if truthy(&usage) {
        let input = get_or(&usage, "input_tokens", J::Int(0))?;
        add_assign(index_mut(index_mut(st, "tokens")?, "input")?, &input)?;
        let output = get_or(&usage, "output_tokens", J::Int(0))?;
        add_assign(index_mut(index_mut(st, "tokens")?, "output")?, &output)?;
        let cached = crate::pyutil::num_add(
            &get_or(&usage, "cache_read_input_tokens", J::Int(0))?,
            &get_or(&usage, "cache_creation_input_tokens", J::Int(0))?,
        )?;
        add_assign(index_mut(index_mut(st, "tokens")?, "cached")?, &cached)?;
        if let Some(thinking) = usage.get("thinking_tokens") {
            let thinking = thinking.clone();
            add_assign(index_mut(index_mut(st, "tokens")?, "thinking")?, &thinking)?;
        }
    }

    for block in py_iter(&get_or(&msg, "content", J::Arr(vec![]))?)? {
        if !matches!(block, J::Obj(_)) {
            continue;
        }
        let btype = block.get("type").cloned().unwrap_or(J::Null);
        if btype == J::str("thinking") {
            let th_text = block.get("thinking").cloned().unwrap_or(J::str(""));
            let len = py_len(&th_text)?;
            bump2(st, "tokens", "thinking", (len as f64 / 4.0) as i128)?;
        } else if btype == J::str("tool_use") {
            let tname = block.get("name").cloned().unwrap_or(J::str("unknown"));
            bump_tool(st, &tname)?;
            let dur_ms = match tname.as_str() {
                Some("Bash") => 600.0,
                Some("Edit") | Some("Write") => 150.0,
                Some("Agent") | Some("Subagent") => {
                    bump(st, "subagents", &J::Int(1))?;
                    3500.0
                }
                _ => 220.0,
            };
            if !ctx.backfill_all {
                ctx.spans.push(PendingSpan {
                    name: format!("claude-code:{}", py_str(&tname)),
                    tool_name: tname.clone(),
                    duration_ms: dur_ms,
                    model: model.clone(),
                });
            }
        }
    }
    Ok(())
}

/// `st.get("offset", 0)` as a seek position.
fn offset_of(st: &J) -> u64 {
    match st.get("offset") {
        Some(J::Int(i)) if *i > 0 => *i as u64,
        Some(J::Bool(true)) => 1,
        _ => 0,
    }
}

/// A small ordered multimap stand-in for the Python dicts keyed by tuples.
struct Tally<K: PartialEq + Clone> {
    entries: Vec<(K, J)>,
}

impl<K: PartialEq + Clone> Tally<K> {
    fn new() -> Self {
        Tally {
            entries: Vec::new(),
        }
    }

    fn add(&mut self, key: K, inc: &J) {
        match self.entries.iter_mut().find(|(k, _)| *k == key) {
            Some(slot) => {
                if let Ok(v) = crate::pyutil::num_add(&slot.1, inc) {
                    slot.1 = v;
                }
            }
            None => {
                let start = crate::pyutil::num_add(&J::Int(0), inc).unwrap_or(J::Int(0));
                self.entries.push((key, start));
            }
        }
    }

    fn get(&self, key: &K) -> Option<&J> {
        self.entries.iter().find(|(k, _)| k == key).map(|(_, v)| v)
    }
}

fn sattr(key: &str, value: J) -> J {
    J::obj(vec![
        ("key", J::str(key)),
        ("value", J::obj(vec![("stringValue", value)])),
    ])
}

impl TranscriptScanner {
    pub fn new(
        brain_dirs: Option<Vec<String>>,
        claude_dir: Option<&str>,
        state_file: Option<&str>,
        endpoint: &str,
        host: Option<&str>,
    ) -> Self {
        let dirs = brain_dirs.unwrap_or_else(default_brain_dirs);
        let host = match host {
            Some(h) if !h.is_empty() => h.to_string(),
            _ => get_hostname(),
        };
        let mut s = TranscriptScanner {
            brain_dirs: dirs.iter().map(|d| sys::expanduser(d)).collect(),
            claude_dir: sys::expanduser(
                &claude_dir
                    .map(str::to_string)
                    .unwrap_or_else(default_claude_dir),
            ),
            state_file: sys::expanduser(
                &state_file
                    .map(str::to_string)
                    .unwrap_or_else(default_state_file),
            ),
            endpoint: endpoint.trim_end_matches('/').to_string(),
            host,
            latest_model: DEFAULT_ANTIGRAVITY_MODEL.to_string(),
            subagent_models: Vec::new(),
            sessions: J::empty_obj(),
        };
        s.sessions = s.load_state();
        s
    }

    /// Per-transcript byte offsets.
    pub fn offsets(&self) -> Vec<(String, J)> {
        match &self.sessions {
            J::Obj(pairs) => pairs
                .iter()
                .map(|(k, v)| (k.clone(), v.get("offset").cloned().unwrap_or(J::Int(0))))
                .collect(),
            _ => Vec::new(),
        }
    }

    fn load_state(&self) -> J {
        let Ok(text) = std::fs::read(&self.state_file) else {
            return J::empty_obj();
        };
        let Ok(text) = String::from_utf8(text) else {
            return J::empty_obj();
        };
        let Ok(J::Obj(raw)) = J::parse(&text) else {
            return J::empty_obj();
        };
        let mut migrated = J::empty_obj();
        for (k, v) in raw {
            match v {
                J::Obj(_) => migrated.set(&k, v),
                // Legacy format: path -> offset.
                J::Int(_) | J::Bool(_) => migrated.set(&k, J::obj(vec![("offset", v)])),
                _ => {}
            }
        }
        migrated
    }

    pub fn save_state(&self) {
        let dir = sys::dirname(&self.state_file);
        if std::fs::create_dir_all(if dir.is_empty() { "." } else { &dir }).is_err() {
            return;
        }
        let tmp = format!("{}.tmp.{}", self.state_file, std::process::id());
        if std::fs::write(&tmp, dumps(&self.sessions, Some(2), true)).is_ok() {
            let _ = std::fs::rename(&tmp, &self.state_file);
        }
    }

    fn ensure_session(&mut self, path: &str, make: impl FnOnce() -> J) {
        if !self.sessions.contains_key(path) {
            self.sessions.set(path, make());
        }
    }

    /// Scan Antigravity transcripts in every brain directory; returns the
    /// number of new events.
    pub fn scan_antigravity(&mut self, backfill_all: bool) -> i64 {
        let mut transcripts = Vec::new();
        for brain_dir in &self.brain_dirs {
            if !std::path::Path::new(brain_dir).exists() {
                continue;
            }
            transcripts.extend(glob_brain_transcripts(brain_dir));
        }
        if transcripts.is_empty() {
            return 0;
        }
        let mut new_events = 0i64;
        let mut spans: Vec<PendingSpan> = Vec::new();

        for path in transcripts {
            let Ok(meta) = std::fs::metadata(&path) else {
                continue;
            };
            let file_size = meta.len();
            let convo_id = sys::basename(&sys::dirname(&sys::dirname(&sys::dirname(&path))));
            let initial_model = sm_get(&self.subagent_models, &convo_id)
                .cloned()
                .unwrap_or_else(|| J::str(self.latest_model.clone()));
            let service = service_for_transcript(&path);
            self.ensure_session(&path, || new_session(service, initial_model));

            let latest_model = &mut self.latest_model;
            let subagent_models = &mut self.subagent_models;
            let st = self.sessions.get_mut(&path).expect("ensured above");
            st.set("service", J::str(service));

            let model = st.get("model").cloned().unwrap_or(J::Null);
            if model.is_null() || model == J::str(LEGACY_DEFAULT_MODEL) {
                if let Some(m) = sm_get(subagent_models, &convo_id).cloned() {
                    st.set("model", m);
                } else if let Ok(lines) = head_lines(&path, 15) {
                    for hline in lines {
                        if hline.contains("<USER_SETTINGS_CHANGE>") {
                            if let Some(det) = parse_model_selection(&hline) {
                                st.set("model", J::str(det.clone()));
                                *latest_model = det.clone();
                                sm_set(subagent_models, &convo_id, J::str(det));
                                break;
                            }
                        }
                    }
                }
                let recent = sys::mtime(&path)
                    .map(|m| m > sys::now_secs() - 86400.0)
                    .unwrap_or(false);
                if st.get("model") == Some(&J::str(LEGACY_DEFAULT_MODEL)) && recent {
                    st.set("model", J::str(latest_model.clone()));
                }
            }

            let last_offset = if backfill_all { 0 } else { offset_of(st) };
            if backfill_all {
                reset_counts(st);
            }
            if file_size <= last_offset && !backfill_all {
                continue;
            }

            st.set(
                "mtime",
                sys::mtime(&path).map(J::Float).unwrap_or(J::Int(0)),
            );
            match read_from(&path, last_offset) {
                Ok((lines, end)) => {
                    let mut ctx = AgCtx {
                        new_events: &mut new_events,
                        spans: &mut spans,
                        latest_model,
                        subagent_models,
                        convo_id: &convo_id,
                        backfill_all,
                    };
                    for line in lines {
                        if strip(&line).is_empty() {
                            continue;
                        }
                        if let Ok(step) = J::parse(&line) {
                            let _ = process_antigravity_step(&step, st, &mut ctx);
                        }
                    }
                    st.set("offset", J::Int(end as i128));
                }
                Err(e) => {
                    eprintln!(
                        "[session_exporter] Error reading Antigravity transcript {}: {}",
                        path, e
                    );
                }
            }
        }

        if !spans.is_empty() {
            spans.truncate(20);
            self.dispatch_traces("antigravity", &spans);
        }
        new_events
    }

    /// Scan Claude Code session transcripts under `~/.claude/projects/`.
    pub fn scan_claude(&mut self, backfill_all: bool) -> i64 {
        if !std::path::Path::new(&self.claude_dir).exists() {
            return 0;
        }
        let transcripts = glob_claude_transcripts(&self.claude_dir);
        let mut new_events = 0i64;
        let mut spans: Vec<PendingSpan> = Vec::new();

        for path in transcripts {
            let Ok(meta) = std::fs::metadata(&path) else {
                continue;
            };
            let file_size = meta.len();
            self.ensure_session(&path, || {
                new_session("claude-code", J::str(CLAUDE_DEFAULT_MODEL))
            });
            let st = self.sessions.get_mut(&path).expect("ensured above");

            let last_offset = if backfill_all { 0 } else { offset_of(st) };
            if backfill_all {
                reset_counts(st);
            }
            if file_size <= last_offset && !backfill_all {
                continue;
            }

            st.set(
                "mtime",
                sys::mtime(&path).map(J::Float).unwrap_or(J::Int(0)),
            );
            match read_from(&path, last_offset) {
                Ok((lines, end)) => {
                    let mut ctx = CcCtx {
                        new_events: &mut new_events,
                        spans: &mut spans,
                        backfill_all,
                    };
                    for line in lines {
                        if strip(&line).is_empty() {
                            continue;
                        }
                        if let Ok(obj) = J::parse(&line) {
                            let _ = process_claude_line(&obj, st, &mut ctx);
                        }
                    }
                    st.set("offset", J::Int(end as i128));
                }
                Err(e) => {
                    eprintln!(
                        "[session_exporter] Error reading Claude transcript {}: {}",
                        path, e
                    );
                }
            }
        }

        if !spans.is_empty() {
            spans.truncate(20);
            self.dispatch_traces("claude-code", &spans);
        }
        new_events
    }

    /// Scan everything, post the cumulative state, persist offsets.
    pub fn scan_once(&mut self, backfill_all: bool) -> i64 {
        let ag = self.scan_antigravity(backfill_all);
        let cc = self.scan_claude(backfill_all);
        self.dispatch_cumulative_state();
        self.save_state();
        ag + cc
    }

    /// The cumulative OTLP metrics for each service, one export request per
    /// service, in sorted service order.
    pub fn build_cumulative_payloads(&mut self) -> Vec<(String, J)> {
        let now = sys::now_secs();
        let t = J::Str(sys::now_ns().to_string());
        let host = J::str(self.host.clone());

        let mut services_seen: Vec<String> = Vec::new();
        let mut sessions_by_service: Tally<String> = Tally::new();
        let mut active_by_service: Tally<String> = Tally::new();
        let mut active_by_model: Tally<(String, J)> = Tally::new();
        let mut turns_by_key: Tally<(String, J)> = Tally::new();
        let mut subagents_by_service: Tally<String> = Tally::new();
        let mut tokens_by_key: Tally<(String, J, String)> = Tally::new();
        let mut tools_by_key: Tally<(String, String)> = Tally::new();

        if let J::Obj(pairs) = &mut self.sessions {
            for (path, st) in pairs.iter_mut() {
                let (srv, mdl) = if path.contains(".claude") {
                    let m = st
                        .get("model")
                        .filter(|m| truthy(m))
                        .cloned()
                        .unwrap_or(J::str(CLAUDE_DEFAULT_MODEL));
                    ("claude-code".to_string(), m)
                } else {
                    let m = st
                        .get("model")
                        .filter(|m| truthy(m))
                        .cloned()
                        .unwrap_or(J::str(self.latest_model.clone()));
                    (service_for_transcript(path).to_string(), m)
                };
                st.set("service", J::str(srv.clone()));
                st.set("model", mdl.clone());
                if !services_seen.contains(&srv) {
                    services_seen.push(srv.clone());
                }
                sessions_by_service.add(srv.clone(), &J::Int(1));

                let mtime = st.get("mtime").and_then(as_number).unwrap_or(0.0);
                if mtime > now - 900.0 {
                    active_by_service.add(srv.clone(), &J::Int(1));
                    active_by_model.add((srv.clone(), mdl.clone()), &J::Int(1));
                }

                let turns = st.get("turns").cloned().unwrap_or(J::Int(0));
                if gt_zero(&turns) {
                    turns_by_key.add((srv.clone(), mdl.clone()), &turns);
                }
                let subagents = st.get("subagents").cloned().unwrap_or(J::Int(0));
                if gt_zero(&subagents) {
                    subagents_by_service.add(srv.clone(), &subagents);
                }
                if let Some(J::Obj(tokens)) = st.get("tokens") {
                    for (ttype, count) in tokens {
                        if gt_zero(count) {
                            tokens_by_key.add((srv.clone(), mdl.clone(), ttype.clone()), count);
                        }
                    }
                }
                if let Some(J::Obj(tools)) = st.get("tools") {
                    for (tname, count) in tools {
                        if gt_zero(count) {
                            tools_by_key.add((srv.clone(), tname.clone()), count);
                        }
                    }
                }
            }
        }

        let mut observed: Vec<String> = services_seen;
        for s in ["antigravity", "claude-code"] {
            if !observed.iter().any(|o| o == s) {
                observed.push(s.to_string());
            }
        }
        observed.sort();

        let dp = |attrs: Vec<J>, value: &J| {
            J::obj(vec![
                ("attributes", J::Arr(attrs)),
                ("timeUnixNano", t.clone()),
                ("asInt", J::Str(py_str(value))),
            ])
        };
        let sum_metric = |name: &str, desc: &str, unit: &str, dps: Vec<J>| {
            J::obj(vec![
                ("name", J::str(name)),
                ("description", J::str(desc)),
                ("unit", J::str(unit)),
                (
                    "sum",
                    J::obj(vec![
                        ("aggregationTemporality", J::Int(2)),
                        ("isMonotonic", J::Bool(true)),
                        ("dataPoints", J::Arr(dps)),
                    ]),
                ),
            ])
        };

        let mut payloads = Vec::new();
        for srv in observed {
            let srv_j = J::str(srv.clone());
            let mut metrics: Vec<J> = Vec::new();

            // 1. Active sessions gauge.
            metrics.push(J::obj(vec![
                ("name", J::str("antigravity_active_session_count")),
                (
                    "description",
                    J::str("Count of currently active agent sessions"),
                ),
                ("unit", J::str("{sessions}")),
                (
                    "gauge",
                    J::obj(vec![(
                        "dataPoints",
                        J::Arr(vec![dp(
                            vec![
                                sattr("host", host.clone()),
                                sattr("service", srv_j.clone()),
                                sattr("status", J::str("active")),
                            ],
                            active_by_service.get(&srv).unwrap_or(&J::Int(0)),
                        )]),
                    )]),
                ),
            ]));

            // 1b. Active sessions per model.
            let model_active: Vec<J> = active_by_model
                .entries
                .iter()
                .filter(|((s, _), c)| *s == srv && gt_zero(c))
                .map(|((_, mdl), c)| {
                    dp(
                        vec![
                            sattr("host", host.clone()),
                            sattr("model", mdl.clone()),
                            sattr("service", srv_j.clone()),
                        ],
                        c,
                    )
                })
                .collect();
            if !model_active.is_empty() {
                metrics.push(J::obj(vec![
                    ("name", J::str("antigravity_active_model_sessions")),
                    (
                        "description",
                        J::str("Count of currently active agent sessions per model"),
                    ),
                    ("unit", J::str("{sessions}")),
                    ("gauge", J::obj(vec![("dataPoints", J::Arr(model_active))])),
                ]));
            }

            // 2. Cumulative sessions.
            metrics.push(sum_metric(
                "antigravity_session_count_total",
                "Total count of agent sessions",
                "{sessions}",
                vec![dp(
                    vec![
                        sattr("host", host.clone()),
                        sattr("service", srv_j.clone()),
                        sattr("status", J::str("completed")),
                    ],
                    sessions_by_service.get(&srv).unwrap_or(&J::Int(0)),
                )],
            ));

            // 3. Turns and API requests.
            let mut turn_dps = Vec::new();
            let mut api_dps = Vec::new();
            for ((s, mdl), count) in &turns_by_key.entries {
                if *s == srv && gt_zero(count) {
                    let attrs = vec![
                        sattr("host", host.clone()),
                        sattr("model", mdl.clone()),
                        sattr("service", srv_j.clone()),
                    ];
                    let mut api_attrs = attrs.clone();
                    api_attrs.push(sattr("status_code", J::str("200")));
                    turn_dps.push(dp(attrs, count));
                    api_dps.push(dp(api_attrs, count));
                }
            }
            if !turn_dps.is_empty() {
                metrics.push(sum_metric(
                    "antigravity_turn_count_total",
                    "Total agent turns in session",
                    "{turns}",
                    turn_dps,
                ));
                metrics.push(sum_metric(
                    "antigravity_api_request_count_total",
                    "Total API requests sent to model provider",
                    "{requests}",
                    api_dps,
                ));
            }

            // 4. Tokens.
            let token_dps: Vec<J> = tokens_by_key
                .entries
                .iter()
                .filter(|((s, _, _), c)| *s == srv && gt_zero(c))
                .map(|((_, mdl, ttype), c)| {
                    dp(
                        vec![
                            sattr("host", host.clone()),
                            sattr("model", mdl.clone()),
                            sattr("service", srv_j.clone()),
                            sattr("token_type", J::str(ttype.clone())),
                        ],
                        c,
                    )
                })
                .collect();
            if !token_dps.is_empty() {
                metrics.push(sum_metric(
                    "antigravity_token_usage_total",
                    "Total count of LLM tokens consumed",
                    "{tokens}",
                    token_dps,
                ));
            }

            // 5. Tool calls and their (estimated) latency histogram.
            let mut tool_dps = Vec::new();
            let mut latency_dps = Vec::new();
            for ((s, tname), count) in &tools_by_key.entries {
                if *s != srv || !gt_zero(count) {
                    continue;
                }
                let attrs = vec![
                    sattr("host", host.clone()),
                    sattr("service", srv_j.clone()),
                    sattr("tool_name", J::str(tname.clone())),
                    sattr("status", J::str("success")),
                ];
                tool_dps.push(dp(attrs.clone(), count));

                let dur_ms = match tname.as_str() {
                    "Bash" | "run_command" => 600.0,
                    "Agent" | "invoke_subagent" => 3500.0,
                    "Edit" | "replace_file_content" | "Write" => 150.0,
                    _ => 180.0,
                };
                let mut buckets: Vec<J> = vec![J::Int(0); HISTOGRAM_BOUNDS.len() + 1];
                match HISTOGRAM_BOUNDS.iter().position(|b| dur_ms <= *b) {
                    Some(i) => buckets[i] = count.clone(),
                    None => *buckets.last_mut().expect("non-empty") = count.clone(),
                }
                latency_dps.push(J::obj(vec![
                    ("attributes", J::Arr(attrs)),
                    ("timeUnixNano", t.clone()),
                    ("count", J::Str(py_str(count))),
                    ("sum", J::Float(as_number(count).unwrap_or(0.0) * dur_ms)),
                    (
                        "bucketCounts",
                        J::Arr(buckets.iter().map(|b| J::Str(py_str(b))).collect()),
                    ),
                    (
                        "explicitBounds",
                        J::Arr(HISTOGRAM_BOUNDS.iter().map(|b| J::Float(*b)).collect()),
                    ),
                ]));
            }
            if !tool_dps.is_empty() {
                metrics.push(sum_metric(
                    "antigravity_tool_call_count_total",
                    "Total count of tools executed",
                    "{calls}",
                    tool_dps,
                ));
            }
            if !latency_dps.is_empty() {
                metrics.push(J::obj(vec![
                    ("name", J::str("antigravity_tool_call_latency_milliseconds")),
                    (
                        "description",
                        J::str("Execution latency of tool calls in milliseconds"),
                    ),
                    ("unit", J::str("ms")),
                    (
                        "histogram",
                        J::obj(vec![
                            ("aggregationTemporality", J::Int(2)),
                            ("dataPoints", J::Arr(latency_dps)),
                        ]),
                    ),
                ]));
            }

            // 6. Subagents.
            if let Some(sub) = subagents_by_service.get(&srv).filter(|c| gt_zero(c)) {
                metrics.push(sum_metric(
                    "antigravity_subagent_spawn_count_total",
                    "Total count of subagents invoked",
                    "{subagents}",
                    vec![dp(
                        vec![
                            sattr("host", host.clone()),
                            sattr("service", srv_j.clone()),
                            sattr("subagent_type", J::str("research")),
                        ],
                        sub,
                    )],
                ));
            }

            let payload = J::obj(vec![(
                "resourceMetrics",
                J::Arr(vec![J::obj(vec![
                    (
                        "resource",
                        J::obj(vec![(
                            "attributes",
                            J::Arr(vec![
                                sattr("service.name", srv_j.clone()),
                                sattr("host.name", host.clone()),
                            ]),
                        )]),
                    ),
                    (
                        "scopeMetrics",
                        J::Arr(vec![J::obj(vec![
                            (
                                "scope",
                                J::obj(vec![
                                    ("name", J::str(format!("{}-session-exporter", srv))),
                                    ("version", J::str("1.0.0")),
                                ]),
                            ),
                            ("metrics", J::Arr(metrics)),
                        ])]),
                    ),
                ])]),
            )]);
            payloads.push((srv, payload));
        }
        payloads
    }

    /// Post the cumulative metrics for every service.
    pub fn dispatch_cumulative_state(&mut self) {
        for (_, payload) in self.build_cumulative_payloads() {
            send_exporter_payload(&format!("{}/v1/metrics", self.endpoint), &payload);
        }
    }

    /// One trace per tool call, for Tempo.
    pub fn build_traces_payload(&self, service_name: &str, spans: &[PendingSpan]) -> J {
        let t_now = sys::now_ns();
        let host = J::str(self.host.clone());
        let items: Vec<J> = spans
            .iter()
            .map(|s| {
                let dur_ns = (s.duration_ms * 1_000_000.0) as i128;
                let span_id = sys::uuid4_hex()[..16].to_string();
                J::obj(vec![
                    ("traceId", J::Str(sys::uuid4_hex())),
                    ("spanId", J::Str(span_id)),
                    ("name", J::str(s.name.clone())),
                    ("kind", J::Int(1)),
                    ("startTimeUnixNano", J::Str((t_now - dur_ns).to_string())),
                    ("endTimeUnixNano", J::Str(t_now.to_string())),
                    (
                        "attributes",
                        J::Arr(vec![
                            sattr("service.name", J::str(service_name)),
                            sattr("tool.name", s.tool_name.clone()),
                            sattr("host.name", host.clone()),
                            sattr("model", s.model.clone()),
                        ]),
                    ),
                    ("status", J::obj(vec![("code", J::Int(1))])),
                ])
            })
            .collect();
        J::obj(vec![(
            "resourceSpans",
            J::Arr(vec![J::obj(vec![
                (
                    "resource",
                    J::obj(vec![(
                        "attributes",
                        J::Arr(vec![
                            sattr("service.name", J::str(service_name)),
                            sattr("host.name", host.clone()),
                        ]),
                    )]),
                ),
                (
                    "scopeSpans",
                    J::Arr(vec![J::obj(vec![
                        (
                            "scope",
                            J::obj(vec![
                                ("name", J::str(format!("{}-session-exporter", service_name))),
                                ("version", J::str("1.0.0")),
                            ]),
                        ),
                        ("spans", J::Arr(items)),
                    ])]),
                ),
            ])]),
        )])
    }

    fn dispatch_traces(&self, service_name: &str, spans: &[PendingSpan]) {
        if spans.is_empty() {
            return;
        }
        let payload = self.build_traces_payload(service_name, spans);
        send_exporter_payload(&format!("{}/v1/traces", self.endpoint), &payload);
    }
}

/// The persistent loop: a full backfill, then incremental scans every
/// `interval` seconds, posting state on new events or every 10 s.
pub fn run_daemon(interval: f64, endpoint: &str, host: Option<&str>) -> ! {
    let mut scanner = TranscriptScanner::new(None, None, None, endpoint, host);
    println!(
        "[session_exporter] Started daemon on {} -> {}",
        scanner.host, scanner.endpoint
    );
    use std::io::Write;
    let _ = std::io::stdout().flush();

    scanner.scan_once(true);
    let mut last_heartbeat = sys::now_secs();
    loop {
        let mut new_events = scanner.scan_antigravity(false);
        new_events += scanner.scan_claude(false);
        let now = sys::now_secs();
        if new_events > 0 || now - last_heartbeat >= 10.0 {
            scanner.dispatch_cumulative_state();
            scanner.save_state();
            last_heartbeat = now;
        }
        std::thread::sleep(std::time::Duration::from_secs_f64(interval.max(0.0)));
    }
}

/// `session_exporter.py`'s command line.
pub fn main(args: &[String]) -> i32 {
    use crate::cli::{ArgParser, Kind};
    let parser = ArgParser::new(
        "session-exporter",
        "Antigravity & Claude Code Session & Transcript Telemetry Exporter",
    )
    .opt(
        "--endpoint",
        Kind::Str,
        Some(J::str(get_target_endpoint())),
        "OTLP Collector endpoint",
    )
    .opt("--host", Kind::Str, None, "Hostname override")
    .opt(
        "--interval",
        Kind::Float,
        Some(J::Float(2.0)),
        "Polling interval in seconds",
    )
    .opt("--once", Kind::Flag, None, "Run a single scan and exit")
    .opt(
        "--backfill",
        Kind::Flag,
        None,
        "Backfill all historical conversation transcripts",
    );
    let ns = match parser.parse(args) {
        Ok(ns) => ns,
        Err(code) => return code,
    };
    let endpoint = ns
        .str("--endpoint")
        .unwrap_or_else(|| DEFAULT_ENDPOINT.to_string());
    let host = ns.str("--host");
    let mut scanner = TranscriptScanner::new(None, None, None, &endpoint, host.as_deref());
    if ns.flag("--backfill") {
        let count = scanner.scan_once(true);
        println!(
            "Backfill complete: processed {} events across active conversations.",
            count
        );
    } else if ns.flag("--once") {
        let count = scanner.scan_once(false);
        println!("Single scan complete: processed {} new events.", count);
    } else {
        run_daemon(
            ns.float("--interval").unwrap_or(2.0),
            &endpoint,
            host.as_deref(),
        );
    }
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn model_selection_parsing() {
        let t = "<USER_SETTINGS_CHANGE>The user changed setting `Model Selection` from Gemini 3.7 Flash to Gemini 3.8 Pro (High). Done";
        assert_eq!(parse_model_selection(t).as_deref(), Some("gemini-3.8-pro"));
        let t = "setting 'Model Selection' from a to Claude Opus 5.";
        assert_eq!(parse_model_selection(t).as_deref(), Some("claude-opus-5"));
        // The dot inside "3.8" is not followed by whitespace, so the lazy group
        // runs on to the sentence's full stop.
        let t = "setting `Model Selection` from x to Gemini 3.8 Flash.\n";
        assert_eq!(
            parse_model_selection(t).as_deref(),
            Some("gemini-3.8-flash")
        );
        assert_eq!(parse_model_selection("no change here"), None);
        assert_eq!(
            parse_model_selection("setting `Model Selection` from a to (x)."),
            None
        );
    }

    #[test]
    fn conversation_ids_found() {
        let id = "0123abcd-0123-4567-89ab-0123456789ab";
        let text = format!(
            "{{\\\"conversationId\\\": \\\"{}\\\"}} conversationId: nope conversationId:{}",
            id, id
        );
        assert_eq!(
            find_conversation_ids(&text),
            vec![id.to_string(), id.to_string()]
        );
    }

    #[test]
    fn universal_newlines_and_ignore_errors() {
        let lines = universal_lines(b"a\r\nb\rc\n\xffd");
        assert_eq!(lines, vec!["a\n", "b\n", "c\n", "d"]);
    }

    #[test]
    fn service_labels() {
        assert_eq!(
            service_for_transcript("/h/.gemini/antigravity-cli/brain/x"),
            "agy"
        );
        assert_eq!(
            service_for_transcript("/h/.gemini/antigravity-ide/brain/x"),
            "antigravity-ide"
        );
        assert_eq!(
            service_for_transcript("/h/.gemini/antigravity/brain/x"),
            "antigravity"
        );
    }

    fn tmpdir(tag: &str) -> String {
        let d = std::env::temp_dir().join(format!(
            "agt-{}-{}-{}",
            tag,
            std::process::id(),
            sys::token_hex(4)
        ));
        std::fs::create_dir_all(&d).unwrap();
        d.to_string_lossy().into_owned()
    }

    #[test]
    fn incremental_antigravity_scan_tracks_offsets_and_counts() {
        let root = tmpdir("ag");
        let brain = format!("{}/brain", root);
        let logs = format!("{}/convo-1/.system_generated/logs", brain);
        std::fs::create_dir_all(&logs).unwrap();
        let path = format!("{}/transcript.jsonl", logs);
        std::fs::write(
            &path,
            "{\"type\": \"USER_INPUT\", \"content\": \"Hello\"}\n{\"type\": \"PLANNER_RESPONSE\", \"tool_calls\": [{\"name\": \"run_command\"}, {\"name\": \"view_file\"}]}\n",
        )
        .unwrap();
        let state = format!("{}/state.json", root);
        let mut s = TranscriptScanner::new(
            Some(vec![brain.clone()]),
            Some(&format!("{}/claude", root)),
            Some(&state),
            "http://127.0.0.1:9",
            Some("h"),
        );
        assert_eq!(s.scan_antigravity(false), 1);
        let st = s.sessions.get(&path).unwrap().clone();
        assert_eq!(st.get("turns"), Some(&J::Int(1)));
        assert_eq!(
            st.get("tools").unwrap().get("run_command"),
            Some(&J::Int(1))
        );
        assert_eq!(
            st.get("tokens").unwrap().get("cached"),
            Some(&J::Int(32000))
        );
        let offset = st.get("offset").cloned().unwrap();
        assert!(matches!(offset, J::Int(n) if n > 0));

        // Nothing new: no events, offset unchanged.
        assert_eq!(s.scan_antigravity(false), 0);
        std::fs::OpenOptions::new()
            .append(true)
            .open(&path)
            .and_then(|mut f| {
                use std::io::Write;
                f.write_all(b"{\"type\": \"PLANNER_RESPONSE\", \"tool_calls\": [{\"name\": \"invoke_subagent\"}]}\n")
            })
            .unwrap();
        assert_eq!(s.scan_antigravity(false), 1);
        assert_eq!(
            s.sessions.get(&path).unwrap().get("subagents"),
            Some(&J::Int(1))
        );

        s.save_state();
        let reloaded = TranscriptScanner::new(
            Some(vec![brain]),
            None,
            Some(&state),
            "http://127.0.0.1:9",
            Some("h"),
        );
        assert_eq!(reloaded.sessions, s.sessions);
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn legacy_int_state_is_migrated() {
        let root = tmpdir("legacy");
        let state = format!("{}/state.json", root);
        std::fs::write(&state, r#"{"/a": 12, "/b": {"offset": 3}, "/c": "junk"}"#).unwrap();
        let s = TranscriptScanner::new(
            Some(vec![]),
            Some("/nonexistent"),
            Some(&state),
            "http://x",
            Some("h"),
        );
        assert_eq!(
            dumps(&s.sessions, None, true),
            r#"{"/a": {"offset": 12}, "/b": {"offset": 3}}"#
        );
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn cumulative_payload_always_reports_both_default_services() {
        let root = tmpdir("cum");
        let mut s = TranscriptScanner::new(
            Some(vec![]),
            Some("/nonexistent"),
            Some(&format!("{}/s.json", root)),
            "http://x",
            Some("h"),
        );
        let payloads = s.build_cumulative_payloads();
        let services: Vec<&str> = payloads.iter().map(|(s, _)| s.as_str()).collect();
        assert_eq!(services, vec!["antigravity", "claude-code"]);
        let _ = std::fs::remove_dir_all(root);
    }
}
