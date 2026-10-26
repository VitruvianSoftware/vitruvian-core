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

//! Native Rust port of `apps/desktop/nexus-agent/src/agy.js`.
//! Drives the Antigravity CLI (`agy -p`) in headless and streaming modes,
//! manages per-chat settings, inspects `conversation_summaries.db`, lists
//! models/MCP servers/plugins/skills, and extracts image/document paths.

use crate::annotations::archived_conversation_ids;
use crate::sessions::{
    delete_persisted_session, get_persisted_session, has_persisted_session, SessionManager,
};
use crate::{dotenv_parse, JsonValue};
use std::collections::{BTreeMap, BTreeSet};
use std::env;
use std::fs;
use std::io::{BufRead, BufReader, Read};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

// ─── Settings & State Types ──────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatSettings {
    pub working_dir: String,
    pub model: String,
    pub approval_mode: String,
    pub sandbox: bool,
    pub thinking: bool,
    pub effort: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ChatSettingsOverrides {
    pub working_dir: Option<String>,
    pub model: Option<String>,
    pub approval_mode: Option<String>,
    pub sandbox: Option<bool>,
    pub thinking: Option<bool>,
    pub effort: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunningProcessInfo {
    pub pid: u32,
    pub start_time_ms: u64,
    pub prompt: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PromptResult {
    pub text: String,
    pub session_id: Option<String>,
    pub timed_out: bool,
    pub stale_session: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct StreamUpdate {
    pub session_id: Option<String>,
    pub delta: Option<String>,
    pub result: Option<JsonValue>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ParsedAgyOutput {
    pub text: String,
    pub session_id: Option<String>,
    pub raw: JsonValue,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelInfo {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Conversation {
    pub id: String,
    pub title: String,
    pub last_modified_ms: u64,
    pub steps: u64,
    pub workspaces: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProviderCommand {
    pub bin: String,
    pub args: Vec<String>,
}

// ─── Environment & Binary Resolution ─────────────────────────────────────────

pub fn env_compat_from_map(
    env_map: &BTreeMap<String, String>,
    name: &str,
    fallback: &str,
) -> String {
    if let Some(v) = env_map.get(&format!("AGY_{}", name)) {
        return v.clone();
    }
    if let Some(v) = env_map.get(&format!("GEMINI_{}", name)) {
        return v.clone();
    }
    fallback.to_string()
}

pub fn env_compat(name: &str, fallback: &str) -> String {
    if let Ok(v) = env::var(format!("AGY_{}", name)) {
        return v;
    }
    if let Ok(v) = env::var(format!("GEMINI_{}", name)) {
        return v;
    }
    fallback.to_string()
}

pub fn current_environment_map() -> BTreeMap<String, String> {
    env::vars().collect()
}

fn is_executable_file(path: &Path) -> bool {
    if !path.is_file() {
        return false;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if let Ok(meta) = fs::metadata(path) {
            return meta.permissions().mode() & 0o111 != 0;
        }
        false
    }
    #[cfg(not(unix))]
    {
        true
    }
}

pub fn resolve_agy_binary_from_map(env_map: &BTreeMap<String, String>) -> String {
    let explicit = env_compat_from_map(env_map, "BIN", "");
    if !explicit.is_empty() {
        return explicit;
    }
    let home = env_map
        .get("HOME")
        .cloned()
        .or_else(|| env::var("HOME").ok())
        .unwrap_or_else(|| "/".to_string());
    let candidates = [
        PathBuf::from(&home).join(".local/bin/agy"),
        PathBuf::from("/opt/homebrew/bin/agy"),
        PathBuf::from("/usr/local/bin/agy"),
    ];
    for candidate in &candidates {
        if is_executable_file(candidate) {
            return candidate.to_string_lossy().to_string();
        }
    }
    "agy".to_string()
}

/// Locate the `agy` binary. Checks `AGY_BIN` / `GEMINI_BIN`, then standard
/// macOS/Linux install paths before falling back to `"agy"`.
pub fn resolve_agy_binary() -> String {
    resolve_agy_binary_from_map(&current_environment_map())
}

// ─── Argument Builders & Error Helpers ───────────────────────────────────────

/// Translate an approval mode into `agy` flags. Accepts retired Gemini names
/// (`auto_edit`) as well as `agy`'s own (`accept-edits`). Does not trim whitespace.
pub fn approval_args(mode: &str) -> Vec<String> {
    match mode.to_ascii_lowercase().as_str() {
        "yolo" => vec!["--dangerously-skip-permissions".to_string()],
        "auto_edit" | "accept-edits" | "accept_edits" => {
            vec!["--mode".to_string(), "accept-edits".to_string()]
        }
        "plan" => vec!["--mode".to_string(), "plan".to_string()],
        _ => Vec::new(),
    }
}

/// Build the argv for one `agy -p` run.
pub fn build_agy_args(
    prompt: &str,
    settings: &ChatSettings,
    format: &str,
    conversation_id: Option<&str>,
    timeout_ms: Option<u64>,
) -> Vec<String> {
    let mut args = vec![
        "-p".to_string(),
        prompt.to_string(),
        "--output-format".to_string(),
        format.to_string(),
    ];
    args.extend(approval_args(&settings.approval_mode));
    if !settings.model.is_empty() {
        args.push("--model".to_string());
        args.push(settings.model.clone());
    }
    let effort = if !settings.effort.is_empty() {
        settings.effort.as_str()
    } else if settings.thinking {
        "high"
    } else {
        ""
    };
    if !effort.is_empty() {
        args.push("--effort".to_string());
        args.push(effort.to_string());
    }
    if settings.sandbox {
        args.push("--sandbox".to_string());
    }
    if let Some(cid) = conversation_id.filter(|s| !s.is_empty()) {
        args.push("--conversation".to_string());
        args.push(cid.to_string());
    }
    if let Some(ms) = timeout_ms.filter(|&m| m > 0) {
        let secs = ((ms as f64 / 1000.0).round() as u64).max(1);
        args.push("--print-timeout".to_string());
        args.push(format!("{}s", secs));
    }
    args
}

/// Turn `agy`'s raw error text into something a person can act on.
pub fn friendly_error(raw: &str) -> String {
    let text = raw.trim();
    let lower = text.to_ascii_lowercase();
    if lower.contains("unavailable")
        || contains_word(&lower, "503")
        || lower.contains("currently unavailable")
    {
        return "Antigravity is temporarily unavailable (503). Try again in a moment.".to_string();
    }
    if lower.contains("not signed in")
        || lower.contains("not authenticated")
        || lower.contains("no authentication")
        || lower.contains("sign in")
        || lower.contains("sign-in")
        || lower.contains("signin")
        || lower.contains("login required")
        || contains_word(&lower, "401")
    {
        return "agy is not signed in. Run `agy` in a terminal on the Mac and sign in, then try again."
            .to_string();
    }
    if lower.contains("not installed") || lower.contains("enoent") || lower.contains("no such file")
    {
        return "agy was not found. Install the Antigravity CLI from https://antigravity.google and run `agy install`."
            .to_string();
    }
    if text.is_empty() {
        "unknown error".to_string()
    } else {
        text.to_string()
    }
}

fn contains_word(haystack: &str, word: &str) -> bool {
    let chars: Vec<char> = haystack.chars().collect();
    let wchars: Vec<char> = word.chars().collect();
    if wchars.is_empty() || chars.len() < wchars.len() {
        return false;
    }
    for i in 0..=chars.len() - wchars.len() {
        if chars[i..i + wchars.len()] == wchars[..] {
            let before_ok = i == 0 || !chars[i - 1].is_ascii_alphanumeric();
            let after_ok =
                i + wchars.len() == chars.len() || !chars[i + wchars.len()].is_ascii_alphanumeric();
            if before_ok && after_ok {
                return true;
            }
        }
    }
    false
}

/// Detect `warning: conversation "<id>" not found` on stderr.
pub fn mentions_unknown_conversation(stderr: &str) -> bool {
    let lower = stderr.to_ascii_lowercase();
    let mut rest = lower.as_str();
    while let Some(idx) = rest.find("conversation \"") {
        let after_open = &rest[idx + "conversation \"".len()..];
        if let Some(close_idx) = after_open.find('"') {
            let after_quote = &after_open[close_idx + 1..];
            if after_quote.starts_with(" not found") {
                return true;
            }
        }
        rest = &rest[idx + 1..];
    }
    false
}

/// Parse a provider command template into `(bin, args)` by tokenizing single/double
/// quotes and substituting `{prompt}` and `{model}` verbatim.
pub fn build_provider_args(template: &str, prompt: &str, model: &str) -> Option<ProviderCommand> {
    let mut tokens = Vec::new();
    let mut current = String::new();
    let mut in_single = false;
    let mut in_double = false;

    for c in template.chars() {
        if c == '\'' && !in_double {
            in_single = !in_single;
        } else if c == '"' && !in_single {
            in_double = !in_double;
        } else if c == ' ' && !in_single && !in_double {
            if !current.is_empty() {
                tokens.push(std::mem::take(&mut current));
            }
        } else {
            current.push(c);
        }
    }
    if !current.is_empty() {
        tokens.push(current);
    }
    if tokens.is_empty() {
        return None;
    }

    let active_model = if model.is_empty() {
        "gemma4:31b-cloud"
    } else {
        model
    };
    let resolved: Vec<String> = tokens
        .into_iter()
        .map(|t| {
            t.replace("{prompt}", prompt)
                .replace("{model}", active_model)
        })
        .collect();
    Some(ProviderCommand {
        bin: resolved[0].clone(),
        args: resolved[1..].to_vec(),
    })
}

/// Clean CLI output by removing noise lines (telemetry, warnings, etc.)
pub fn clean_cli_output(raw: &str) -> String {
    raw.split('\n')
        .filter(|line| {
            let trimmed = line.trim();
            let lower = trimmed.to_ascii_lowercase();
            if lower.starts_with("npm warn") {
                return false;
            }
            if trimmed.starts_with("Warning: Skipping")
                || trimmed.starts_with("Telemetry ")
                || trimmed.starts_with("Loading plugin:")
                || trimmed.starts_with("Scheduling MCP context")
                || trimmed.starts_with("Executing MCP context")
                || trimmed.starts_with("MCP context refresh")
                || trimmed.starts_with("Registering notification")
            {
                return false;
            }
            if let Some(after_server) = trimmed.strip_prefix("Server '") {
                if let Some(quote_pos) = after_server.find('\'') {
                    if quote_pos > 0 {
                        let rest = &after_server[quote_pos + 1..];
                        if rest.starts_with(" supports") || rest.starts_with(" has") {
                            return false;
                        }
                    }
                }
            }
            true
        })
        .collect::<Vec<&str>>()
        .join("\n")
        .trim()
        .to_string()
}

// ─── JSON Stream & Output Parsing ────────────────────────────────────────────

/// Parse one `stream-json` line from `agy`.
pub fn parse_stream_line(line: &str) -> Option<StreamUpdate> {
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return None;
    }
    let event = JsonValue::parse(trimmed).ok()?;
    let mut out = StreamUpdate {
        session_id: None,
        delta: None,
        result: None,
    };
    if let Some(cid) = event.get("conversation_id").and_then(|v| v.as_str()) {
        if !cid.is_empty() {
            out.session_id = Some(cid.to_string());
        }
    }
    if event.get("event").and_then(|v| v.as_str()) == Some("step_update") {
        if let Some(su) = event.get("step_update") {
            if let Some(cid) = su.get("conversation_id").and_then(|v| v.as_str()) {
                if !cid.is_empty() {
                    out.session_id = Some(cid.to_string());
                }
            }
            if su.get("step_type").and_then(|v| v.as_str()) == Some("agent_response") {
                if let Some(td) = su.get("text_delta").and_then(|v| v.as_str()) {
                    out.delta = Some(td.to_string());
                }
            }
        }
    }
    if event.get("event").and_then(|v| v.as_str()) == Some("result") {
        if let Some(res) = event.get("result") {
            if let Some(cid) = res.get("conversation_id").and_then(|v| v.as_str()) {
                if !cid.is_empty() {
                    out.session_id = Some(cid.to_string());
                }
            }
            out.result = Some(res.clone());
        }
    }
    Some(out)
}

/// Parse `agy --output-format json` output.
pub fn parse_agy_output(raw: &str) -> Result<ParsedAgyOutput, String> {
    let data = JsonValue::parse(raw)?;
    let result = match data.get("result") {
        Some(r @ JsonValue::Object(_)) => r.clone(),
        _ => data.clone(),
    };
    let session_id = result
        .get("conversation_id")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .or_else(|| {
            data.get("conversation_id")
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
        })
        .map(|s| s.to_string());

    let text = if let Some(resp) = result
        .get("response")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
    {
        resp.to_string()
    } else if result
        .get("error")
        .and_then(|v| v.as_str())
        .map(|s| !s.is_empty())
        .unwrap_or(false)
    {
        String::new()
    } else {
        result.to_json_pretty(0)
    };

    Ok(ParsedAgyOutput {
        text: if text.is_empty() {
            "No response.".to_string()
        } else {
            text
        },
        session_id,
        raw: result,
    })
}

/// Interpret a `result` object from `agy`. Returns `Err` on `status == "ERROR"`.
pub fn handle_result<F>(
    result: &JsonValue,
    chat_id: Option<i64>,
    mut clear_stale: F,
) -> Result<(), String>
where
    F: FnMut(i64),
{
    let status = result
        .get("status")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_ascii_uppercase();
    if status == "ERROR" {
        let message = result
            .get("error")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .unwrap_or("agy reported an error");
        let lower = message.to_ascii_lowercase();
        if lower.contains("conversation")
            && (lower.contains("not found")
                || lower.contains("unknown")
                || lower.contains("invalid")
                || lower.contains("no such"))
        {
            if let Some(cid) = chat_id {
                clear_stale(cid);
            }
            return Err(
                "Conversation expired or was deleted. Send your message again to start a new one."
                    .to_string(),
            );
        }
        return Err(friendly_error(message));
    }
    Ok(())
}

// ─── Models, Plugins & Skills ────────────────────────────────────────────────

/// Parse `agy models` output (`Fetching...` line, then `id<TAB>display name` rows).
pub fn parse_models(raw: &str) -> Vec<ModelInfo> {
    raw.split('\n')
        .map(|l| l.trim())
        .filter(|l| !l.is_empty() && !l.to_ascii_lowercase().starts_with("fetching"))
        .filter_map(|l| {
            let mut parts = l.split('\t');
            let id = parts.next()?.trim().to_string();
            if id.is_empty() {
                return None;
            }
            let rest: String = parts.collect::<Vec<&str>>().join(" ").trim().to_string();
            let name = if rest.is_empty() { id.clone() } else { rest };
            Some(ModelInfo { id, name })
        })
        .collect()
}

/// Render `agy plugin list` JSON for chat.
pub fn format_plugin_list(raw: &str) -> String {
    let Ok(data) = JsonValue::parse(raw) else {
        let trimmed = raw.trim();
        return if trimmed.is_empty() {
            "No plugins installed.".to_string()
        } else {
            trimmed.to_string()
        };
    };
    let Some(imports) = data.get("imports").and_then(|v| v.as_array()) else {
        return "No plugins installed.".to_string();
    };
    if imports.is_empty() {
        return "No plugins installed.".to_string();
    }
    imports
        .iter()
        .map(|p| {
            let name = p
                .get("name")
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
                .unwrap_or("(unnamed)");
            let mut parts = vec![format!("• {}", name)];
            if let Some(source) = p
                .get("source")
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
            {
                parts.push(format!("from {}", source));
            }
            if let Some(comps) = p.get("components").and_then(|v| v.as_array()) {
                let comp_strs: Vec<&str> = comps.iter().filter_map(|c| c.as_str()).collect();
                if !comp_strs.is_empty() {
                    parts.push(format!("({})", comp_strs.join(", ")));
                }
            }
            parts.join(" ")
        })
        .collect::<Vec<String>>()
        .join("\n")
}

/// List skills from the customization roots (`~/.gemini/config/skills`,
/// `~/.agents/skills`, `<working_dir>/.agents/skills`).
pub fn list_skills_in_roots(roots: &[PathBuf]) -> String {
    let mut seen = BTreeSet::new();
    let mut lines = Vec::new();
    for root in roots {
        let Ok(entries) = fs::read_dir(root) else {
            continue;
        };
        for entry in entries.flatten() {
            let file_name = entry.file_name();
            let Some(name) = file_name.to_str() else {
                continue;
            };
            if name.starts_with('.') || seen.contains(name) {
                continue;
            }
            if entry.path().join("SKILL.md").exists() {
                seen.insert(name.to_string());
                lines.push(format!("• {}", name));
            }
        }
    }
    if lines.is_empty() {
        "No skills found.".to_string()
    } else {
        lines.sort();
        lines.join("\n")
    }
}

// ─── Image & File Path Extraction ────────────────────────────────────────────

const IMAGE_EXTENSIONS: &[&str] = &[".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg"];

const SENDABLE_FILE_EXTENSIONS: &[&str] = &[
    ".py", ".js", ".ts", ".jsx", ".tsx", ".json", ".md", ".txt", ".html", ".css", ".sh", ".yaml",
    ".yml", ".csv", ".pdf", ".xml", ".sql", ".go", ".rs", ".swift", ".java", ".c", ".cpp", ".h",
    ".rb", ".php", ".toml", ".conf", ".cfg", ".log",
];

fn extract_candidate_paths(text: &str) -> Vec<String> {
    let mut candidates = Vec::new();
    let chars: Vec<char> = text.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        // Optional `file://` prefix followed by `/`
        let start_slash = if chars[i..].starts_with(&['f', 'i', 'l', 'e', ':', '/', '/', '/']) {
            Some(i + 7)
        } else if chars[i] == '/'
            && (i == 0
                || chars[i - 1].is_whitespace()
                || matches!(chars[i - 1], '"' | '\'' | '`' | '<' | '(' | '['))
        {
            Some(i)
        } else {
            None
        };

        if let Some(slash_idx) = start_slash {
            let mut j = slash_idx;
            while j < chars.len()
                && !chars[j].is_whitespace()
                && !matches!(chars[j], '"' | '\'' | '`' | '<' | '>' | ')' | ']')
            {
                j += 1;
            }
            // Trim trailing punctuation like `.`, `,`, `;`, `:` if not part of extension
            let token: String = chars[slash_idx..j].iter().collect();
            if token.starts_with('/') && token.contains('.') {
                candidates.push(token);
            }
            i = j;
        } else {
            i += 1;
        }
    }
    candidates
}

/// Scan response text for image file paths that exist on disk.
pub fn extract_image_paths(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut seen = BTreeSet::new();
    for candidate in extract_candidate_paths(text) {
        let lower = candidate.to_ascii_lowercase();
        if IMAGE_EXTENSIONS.iter().any(|ext| lower.ends_with(ext)) {
            if Path::new(&candidate).exists() && seen.insert(candidate.clone()) {
                out.push(candidate);
            }
        }
    }
    out
}

/// Scan response text for code/document file paths that exist on disk.
pub fn extract_file_paths(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut seen = BTreeSet::new();
    for candidate in extract_candidate_paths(text) {
        let Some(dot_idx) = candidate.rfind('.') else {
            continue;
        };
        let ext = candidate[dot_idx..].to_ascii_lowercase();
        if SENDABLE_FILE_EXTENSIONS.contains(&ext.as_str()) {
            let path = Path::new(&candidate);
            if path.is_file() && seen.insert(candidate.clone()) {
                out.push(candidate);
            }
        }
    }
    out
}

// ─── Relative Time & Conversations ───────────────────────────────────────────

pub fn relative_time_from_diff_ms(diff_ms: u64) -> String {
    let m = diff_ms / 60_000;
    if m < 1 {
        return "just now".to_string();
    }
    if m < 60 {
        return format!("{}m ago", m);
    }
    let h = m / 60;
    if h < 24 {
        return format!("{}h ago", h);
    }
    format!("{}d ago", h / 24)
}

pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

pub fn agy_data_dirs_for_home(home: &Path) -> Vec<PathBuf> {
    vec![
        home.join(".gemini/antigravity"),
        home.join(".gemini/antigravity-cli"),
    ]
}

pub fn agy_data_dir_from_dirs(dirs: &[PathBuf]) -> PathBuf {
    dirs.iter()
        .find(|d| d.join("conversation_summaries.db").exists())
        .cloned()
        .unwrap_or_else(|| dirs[0].clone())
}

// ─── Isolated AgyBridge Engine (used by both global API and isolated tests) ──

#[derive(Debug)]
pub struct AgyBridge {
    pub agy_bin: String,
    pub working_dir: String,
    pub timeout_ms: u64,
    pub approval_mode: String,
    pub model: String,
    pub effort: String,
    pub thinking: bool,
    pub cli_provider: String,
    pub cli_command_template: String,
    pub env_map: BTreeMap<String, String>,
    chat_settings: Mutex<BTreeMap<i64, ChatSettingsOverrides>>,
    running_processes: Arc<Mutex<BTreeMap<i64, RunningProcessInfo>>>,
    last_session_listing: Mutex<BTreeMap<i64, Vec<String>>>,
    session_manager: Mutex<SessionManager>,
}

impl AgyBridge {
    /// Construct an `AgyBridge` the exact way `bot.js` + `agy.js` start:
    /// `dotenv` parses `env_text` and populates keys not already present in
    /// `process_env`, then `agy` reads its configuration once.
    pub fn from_dotenv_and_env(
        env_text: &str,
        process_env: &BTreeMap<String, String>,
        default_cwd: &str,
    ) -> Self {
        let mut merged = process_env.clone();
        for (k, v) in dotenv_parse(env_text) {
            merged.entry(k).or_insert(v);
        }
        Self::from_env_map(merged, default_cwd)
    }

    pub fn from_env_map(env_map: BTreeMap<String, String>, default_cwd: &str) -> Self {
        let agy_bin = resolve_agy_binary_from_map(&env_map);
        let working_dir = {
            let w = env_compat_from_map(&env_map, "WORKING_DIR", default_cwd);
            if w.is_empty() {
                default_cwd.to_string()
            } else {
                w
            }
        };
        let timeout_ms = env_compat_from_map(&env_map, "TIMEOUT_MS", "300000")
            .parse::<u64>()
            .unwrap_or(300_000);
        // Note: `??` in JS keeps `""` when `AGY_APPROVAL_MODE=""` is present!
        let approval_mode = env_compat_from_map(&env_map, "APPROVAL_MODE", "yolo");
        let model = env_compat_from_map(&env_map, "MODEL", "");
        let effort = env_map.get("AGY_EFFORT").cloned().unwrap_or_default();
        let thinking = env_compat_from_map(&env_map, "THINKING", "") == "true";
        let raw_provider = env_map
            .get("CLI_PROVIDER")
            .filter(|s| !s.is_empty())
            .map(|s| s.as_str())
            .unwrap_or("agy");
        let cli_provider = if raw_provider == "gemini" {
            "agy".to_string()
        } else {
            raw_provider.to_string()
        };
        let cli_command_template = env_map
            .get("CLI_COMMAND_TEMPLATE")
            .cloned()
            .unwrap_or_default();

        let sessions_file = PathBuf::from(&working_dir).join(".bot-sessions.json");
        AgyBridge {
            agy_bin,
            working_dir,
            timeout_ms,
            approval_mode,
            model,
            effort,
            thinking,
            cli_provider,
            cli_command_template,
            env_map,
            chat_settings: Mutex::new(BTreeMap::new()),
            running_processes: Arc::new(Mutex::new(BTreeMap::new())),
            last_session_listing: Mutex::new(BTreeMap::new()),
            session_manager: Mutex::new(SessionManager::new(sessions_file)),
        }
    }

    pub fn from_process_env() -> Self {
        let cwd = env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("."))
            .to_string_lossy()
            .to_string();
        let env_text = fs::read_to_string(".env").unwrap_or_default();
        Self::from_dotenv_and_env(&env_text, &current_environment_map(), &cwd)
    }

    pub fn default_settings(&self) -> ChatSettings {
        ChatSettings {
            working_dir: self.working_dir.clone(),
            model: self.model.clone(),
            approval_mode: self.approval_mode.clone(),
            sandbox: false,
            thinking: self.thinking,
            effort: self.effort.clone(),
        }
    }

    pub fn get_chat_settings(&self, chat_id: i64) -> ChatSettings {
        let map = self.chat_settings.lock().unwrap_or_else(|e| e.into_inner());
        let ov = map.get(&chat_id).cloned().unwrap_or_default();
        ChatSettings {
            working_dir: ov
                .working_dir
                .filter(|s| !s.is_empty())
                .unwrap_or_else(|| self.working_dir.clone()),
            model: ov
                .model
                .filter(|s| !s.is_empty())
                .unwrap_or_else(|| self.model.clone()),
            approval_mode: ov
                .approval_mode
                .filter(|s| !s.is_empty())
                .unwrap_or_else(|| self.approval_mode.clone()),
            sandbox: ov.sandbox.unwrap_or(false),
            thinking: ov.thinking.unwrap_or(self.thinking),
            effort: ov
                .effort
                .filter(|s| !s.is_empty())
                .unwrap_or_else(|| self.effort.clone()),
        }
    }

    pub fn set_chat_setting_str(&self, chat_id: i64, key: &str, value: &str) {
        let mut map = self.chat_settings.lock().unwrap_or_else(|e| e.into_inner());
        let entry = map.entry(chat_id).or_default();
        match key {
            "workingDir" | "working_dir" => entry.working_dir = Some(value.to_string()),
            "model" => entry.model = Some(value.to_string()),
            "approvalMode" | "approval_mode" => entry.approval_mode = Some(value.to_string()),
            "effort" => entry.effort = Some(value.to_string()),
            _ => {}
        }
    }

    pub fn set_chat_setting_bool(&self, chat_id: i64, key: &str, value: bool) {
        let mut map = self.chat_settings.lock().unwrap_or_else(|e| e.into_inner());
        let entry = map.entry(chat_id).or_default();
        match key {
            "sandbox" => entry.sandbox = Some(value),
            "thinking" => entry.thinking = Some(value),
            _ => {}
        }
    }

    pub fn execute_prompt(
        &self,
        prompt: &str,
        chat_id: Option<i64>,
    ) -> Result<PromptResult, String> {
        let settings = match chat_id {
            Some(cid) if cid != 0 => self.get_chat_settings(cid),
            _ => self.default_settings(),
        };

        // Custom provider path
        if self.cli_provider != "agy" && !self.cli_command_template.is_empty() {
            let parsed = build_provider_args(&self.cli_command_template, prompt, &settings.model)
                .ok_or_else(|| {
                format!(
                    "Invalid CLI_COMMAND_TEMPLATE: {}",
                    self.cli_command_template
                )
            })?;

            let mut cmd = Command::new(&parsed.bin);
            cmd.args(&parsed.args)
                .current_dir(&settings.working_dir)
                .envs(&self.env_map)
                .env("NO_COLOR", "1")
                .stdout(Stdio::piped())
                .stderr(Stdio::piped());

            let child = cmd
                .spawn()
                .map_err(|e| format!("Failed to start provider: {}", e))?;
            let pid = child.id();
            if let Some(cid) = chat_id {
                self.running_processes
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .insert(
                        cid,
                        RunningProcessInfo {
                            pid,
                            start_time_ms: now_ms(),
                            prompt: prompt.chars().take(100).collect(),
                        },
                    );
            }
            let output = child
                .wait_with_output()
                .map_err(|e| format!("Failed waiting for provider: {}", e))?;
            if let Some(cid) = chat_id {
                self.running_processes
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .remove(&cid);
            }
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            let code = output.status.code().unwrap_or(1);
            if code != 0 && stdout.is_empty() {
                return Err(format!(
                    "Provider exited with code {}: {}",
                    code,
                    if stderr.is_empty() {
                        "unknown error"
                    } else {
                        &stderr
                    }
                ));
            }
            let text = if !stdout.is_empty() {
                stdout
            } else if !stderr.is_empty() {
                stderr
            } else {
                "No response from provider.".to_string()
            };
            return Ok(PromptResult {
                text,
                session_id: None,
                timed_out: false,
                stale_session: false,
            });
        }

        // agy path
        let existing_session = chat_id.and_then(|cid| {
            self.session_manager
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .get_persisted_session(&cid.to_string())
        });
        let timeout = if settings.thinking || settings.effort == "high" {
            self.timeout_ms.max(600_000)
        } else {
            self.timeout_ms
        };
        let args = build_agy_args(
            prompt,
            &settings,
            "json",
            existing_session.as_deref(),
            Some(timeout),
        );

        let mut cmd = Command::new(&self.agy_bin);
        cmd.args(&args)
            .current_dir(&settings.working_dir)
            .envs(&self.env_map)
            .env("NO_COLOR", "1")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());

        let child = cmd
            .spawn()
            .map_err(|e| format!("Failed to start agy: {}", e))?;
        let pid = child.id();
        if let Some(cid) = chat_id {
            self.running_processes
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .insert(
                    cid,
                    RunningProcessInfo {
                        pid,
                        start_time_ms: now_ms(),
                        prompt: prompt.chars().take(100).collect(),
                    },
                );
        }

        let output = child
            .wait_with_output()
            .map_err(|e| format!("Failed waiting for agy: {}", e))?;
        if let Some(cid) = chat_id {
            self.running_processes
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .remove(&cid);
        }

        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let stale_session = chat_id.is_some()
            && existing_session.is_some()
            && mentions_unknown_conversation(&stderr);
        if stale_session {
            if let Some(cid) = chat_id {
                self.session_manager
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .delete_persisted_session(&cid.to_string());
            }
        }

        let code = output.status.code().unwrap_or(1);
        if code != 0 && stdout.is_empty() {
            return Err(friendly_error(&clean_cli_output(&stderr)));
        }

        match parse_agy_output(&stdout) {
            Ok(parsed) => {
                handle_result(&parsed.raw, chat_id, |cid| {
                    self.session_manager
                        .lock()
                        .unwrap_or_else(|e| e.into_inner())
                        .delete_persisted_session(&cid.to_string());
                })?;
                if let (Some(sid), Some(cid)) = (&parsed.session_id, chat_id) {
                    self.session_manager
                        .lock()
                        .unwrap_or_else(|e| e.into_inner())
                        .set_persisted_session(&cid.to_string(), sid);
                }
                Ok(PromptResult {
                    text: parsed.text,
                    session_id: parsed.session_id,
                    timed_out: false,
                    stale_session,
                })
            }
            Err(_) => {
                let text = if !stdout.is_empty() {
                    stdout
                } else if !stderr.is_empty() {
                    stderr
                } else {
                    "No response from agy.".to_string()
                };
                Ok(PromptResult {
                    text,
                    session_id: None,
                    timed_out: false,
                    stale_session,
                })
            }
        }
    }

    pub fn execute_prompt_streaming<F>(
        &self,
        prompt: &str,
        chat_id: Option<i64>,
        mut on_chunk: F,
    ) -> Result<PromptResult, String>
    where
        F: FnMut(&str),
    {
        let settings = match chat_id {
            Some(cid) if cid != 0 => self.get_chat_settings(cid),
            _ => self.default_settings(),
        };

        if self.cli_provider != "agy" && !self.cli_command_template.is_empty() {
            let res = self.execute_prompt(prompt, chat_id)?;
            on_chunk(&res.text);
            return Ok(res);
        }

        let existing_session = chat_id.and_then(|cid| {
            self.session_manager
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .get_persisted_session(&cid.to_string())
        });
        let timeout = if settings.thinking || settings.effort == "high" {
            self.timeout_ms.max(600_000)
        } else {
            self.timeout_ms
        };
        let args = build_agy_args(
            prompt,
            &settings,
            "stream-json",
            existing_session.as_deref(),
            Some(timeout),
        );

        let mut child = Command::new(&self.agy_bin)
            .args(&args)
            .current_dir(&settings.working_dir)
            .envs(&self.env_map)
            .env("NO_COLOR", "1")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("Failed to start agy: {}", e))?;

        let pid = child.id();
        if let Some(cid) = chat_id {
            self.running_processes
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .insert(
                    cid,
                    RunningProcessInfo {
                        pid,
                        start_time_ms: now_ms(),
                        prompt: prompt.chars().take(100).collect(),
                    },
                );
        }

        let mut accumulated_text = String::new();
        let mut final_text: Option<String> = None;
        let mut session_id: Option<String> = None;
        let mut final_result: Option<JsonValue> = None;

        if let Some(stdout) = child.stdout.take() {
            let reader = BufReader::new(stdout);
            for line in reader.lines().map_while(Result::ok) {
                if let Some(update) = parse_stream_line(&line) {
                    if let Some(sid) = update.session_id {
                        session_id = Some(sid);
                    }
                    if let Some(delta) = update.delta {
                        accumulated_text.push_str(&delta);
                        on_chunk(&accumulated_text);
                    }
                    if let Some(res) = update.result {
                        if let Some(resp) = res
                            .get("response")
                            .and_then(|v| v.as_str())
                            .filter(|s| !s.is_empty())
                        {
                            final_text = Some(resp.to_string());
                        }
                        final_result = Some(res);
                    }
                }
            }
        }

        let mut stderr = String::new();
        if let Some(mut err_pipe) = child.stderr.take() {
            let _ = err_pipe.read_to_string(&mut stderr);
        }
        let status = child
            .wait()
            .map_err(|e| format!("Failed waiting for agy: {}", e))?;
        if let Some(cid) = chat_id {
            self.running_processes
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .remove(&cid);
        }

        let stderr = stderr.trim().to_string();
        let stale_session = chat_id.is_some()
            && existing_session.is_some()
            && mentions_unknown_conversation(&stderr);
        if stale_session {
            if let Some(cid) = chat_id {
                self.session_manager
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .delete_persisted_session(&cid.to_string());
            }
        }

        if let Some(ref res) = final_result {
            handle_result(res, chat_id, |cid| {
                self.session_manager
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .delete_persisted_session(&cid.to_string());
            })?;
        }

        let text = final_text.unwrap_or(accumulated_text);
        let code = status.code().unwrap_or(1);
        if text.is_empty() && code != 0 {
            return Err(friendly_error(&clean_cli_output(&stderr)));
        }

        if let (Some(ref sid), Some(cid)) = (&session_id, chat_id) {
            self.session_manager
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .set_persisted_session(&cid.to_string(), sid);
        }

        Ok(PromptResult {
            text: if text.is_empty() {
                "No response from agy.".to_string()
            } else {
                text
            },
            session_id,
            timed_out: false,
            stale_session,
        })
    }

    pub fn cancel_prompt(&self, chat_id: i64) -> bool {
        let mut map = self
            .running_processes
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        if let Some(info) = map.remove(&chat_id) {
            let _ = Command::new("kill")
                .args(["-TERM", &info.pid.to_string()])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
            true
        } else {
            false
        }
    }

    pub fn get_running_info(&self, chat_id: i64) -> Option<RunningProcessInfo> {
        self.running_processes
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(&chat_id)
            .cloned()
    }

    pub fn register_running_process_for_test(&self, chat_id: i64, info: RunningProcessInfo) {
        self.running_processes
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(chat_id, info);
    }

    pub fn run_cli_command(&self, args: &[&str], cwd: Option<&str>) -> Result<String, String> {
        let dir = cwd.unwrap_or(&self.working_dir);
        let output = Command::new(&self.agy_bin)
            .args(args)
            .current_dir(dir)
            .envs(&self.env_map)
            .env("NO_COLOR", "1")
            .output()
            .map_err(|e| format!("Failed to run agy command: {}", e))?;
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let combined = if !stdout.is_empty() { stdout } else { stderr };
        let cleaned = clean_cli_output(&combined);
        Ok(if cleaned.is_empty() {
            "Command completed (no output).".to_string()
        } else {
            cleaned
        })
    }

    pub fn list_models(&self) -> Result<Vec<ModelInfo>, String> {
        Ok(parse_models(&self.run_cli_command(&["models"], None)?))
    }

    pub fn agy_version(&self) -> Option<String> {
        let out = self.run_cli_command(&["--version"], None).ok()?;
        extract_semver(&out).or_else(|| {
            let first = out.lines().next().unwrap_or("").trim();
            if first.is_empty() || first == "Command completed (no output)." {
                None
            } else {
                Some(first.to_string())
            }
        })
    }

    pub fn list_mcp_servers(&self) -> Result<String, String> {
        self.run_cli_command(&["mcp", "list"], None)
    }

    pub fn list_extensions(&self) -> Result<String, String> {
        Ok(format_plugin_list(
            &self.run_cli_command(&["plugin", "list"], None)?,
        ))
    }

    pub fn list_skills(&self) -> String {
        let home = self
            .env_map
            .get("HOME")
            .cloned()
            .or_else(|| env::var("HOME").ok())
            .unwrap_or_else(|| "/".to_string());
        let roots = vec![
            PathBuf::from(&home).join(".gemini/config/skills"),
            PathBuf::from(&home).join(".agents/skills"),
            PathBuf::from(&self.working_dir).join(".agents/skills"),
        ];
        list_skills_in_roots(&roots)
    }

    pub fn list_conversations(&self, working_dir: Option<&str>) -> Vec<Conversation> {
        let home = self
            .env_map
            .get("HOME")
            .cloned()
            .or_else(|| env::var("HOME").ok())
            .unwrap_or_else(|| "/".to_string());
        let data_dirs = agy_data_dirs_for_home(Path::new(&home));
        let data_dir = agy_data_dir_from_dirs(&data_dirs);
        let db_path = data_dir.join("conversation_summaries.db");
        if !db_path.exists() {
            return Vec::new();
        }
        let archived = archived_conversation_ids(&data_dirs);
        let query = "SELECT conversation_id, title, preview, step_count, last_modified_time, workspace_uris \
                     FROM conversation_summaries \
                     WHERE nesting_depth = 0 AND killed = 0 \
                     ORDER BY last_modified_time DESC LIMIT 200";
        let Ok(out) = Command::new("sqlite3")
            .args(["-json", &db_path.to_string_lossy(), query])
            .output()
        else {
            return Vec::new();
        };
        let raw = String::from_utf8_lossy(&out.stdout);
        let Ok(parsed) = JsonValue::parse(raw.trim()) else {
            return Vec::new();
        };
        let Some(rows) = parsed.as_array() else {
            return Vec::new();
        };
        let wanted = working_dir.map(|w| {
            let abs = fs::canonicalize(w).unwrap_or_else(|_| PathBuf::from(w));
            format!("file://{}", abs.to_string_lossy())
        });

        rows.iter()
            .filter_map(|r| {
                let id = r
                    .get("conversation_id")
                    .and_then(|v| v.as_str())?
                    .to_string();
                let raw_title = r
                    .get("title")
                    .and_then(|v| v.as_str())
                    .filter(|s| !s.is_empty())
                    .or_else(|| {
                        r.get("preview")
                            .and_then(|v| v.as_str())
                            .filter(|s| !s.is_empty())
                    })
                    .unwrap_or("");
                let first_line = raw_title.split('\n').next().unwrap_or("");
                let title: String = first_line.chars().take(80).collect();
                let title = if title.is_empty() {
                    "(untitled)".to_string()
                } else {
                    title
                };
                let steps = r
                    .get("step_count")
                    .and_then(|v| v.as_i64())
                    .unwrap_or(0)
                    .max(0) as u64;
                let workspaces = r
                    .get("workspace_uris")
                    .and_then(|v| v.as_str())
                    .and_then(|s| JsonValue::parse(s).ok())
                    .and_then(|j| {
                        j.as_array().map(|arr| {
                            arr.iter()
                                .filter_map(|x| x.as_str().map(|s| s.to_string()))
                                .collect::<Vec<String>>()
                        })
                    })
                    .unwrap_or_default();
                Some(Conversation {
                    id,
                    title,
                    last_modified_ms: now_ms(),
                    steps,
                    workspaces,
                })
            })
            .filter(|c| {
                !archived.contains(&c.id)
                    && match &wanted {
                        None => true,
                        Some(w) => c.workspaces.is_empty() || c.workspaces.contains(w),
                    }
            })
            .collect()
    }

    pub fn list_sessions(&self, cwd: Option<&str>, chat_id: Option<i64>) -> String {
        let conversations = self.list_conversations(cwd);
        if conversations.is_empty() {
            return "No conversations yet for this workspace.".to_string();
        }
        let shown: Vec<&Conversation> = conversations.iter().take(20).collect();
        if let Some(cid) = chat_id {
            self.last_session_listing
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .insert(cid, shown.iter().map(|c| c.id.clone()).collect());
        }
        let current = now_ms();
        shown
            .iter()
            .enumerate()
            .map(|(i, c)| {
                let diff = current.saturating_sub(c.last_modified_ms);
                format!(
                    "{}. {} ({}, {} steps)",
                    i + 1,
                    c.title,
                    relative_time_from_diff_ms(diff),
                    c.steps
                )
            })
            .collect::<Vec<String>>()
            .join("\n")
    }

    pub fn set_last_session_listing(&self, chat_id: i64, ids: Vec<String>) {
        self.last_session_listing
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(chat_id, ids);
    }

    pub fn resolve_session_ref(
        &self,
        chat_id: i64,
        reference: &str,
        cwd: Option<&str>,
    ) -> Option<String> {
        let trimmed = reference.trim();
        if trimmed.is_empty() {
            return None;
        }
        if trimmed.chars().all(|c| c.is_ascii_digit()) {
            let idx = trimmed.parse::<usize>().ok()?;
            if idx == 0 {
                return None;
            }
            let mut map = self
                .last_session_listing
                .lock()
                .unwrap_or_else(|e| e.into_inner());
            let ids = map.entry(chat_id).or_insert_with(|| {
                self.list_conversations(cwd)
                    .into_iter()
                    .take(20)
                    .map(|c| c.id)
                    .collect()
            });
            return ids.get(idx - 1).cloned();
        }
        if trimmed == "latest" {
            return self
                .list_conversations(cwd)
                .into_iter()
                .next()
                .map(|c| c.id);
        }
        Some(trimmed.to_string())
    }

    pub fn set_session_resume(
        &self,
        chat_id: i64,
        session_ref: &str,
        cwd: Option<&str>,
    ) -> Result<String, String> {
        let id = self
            .resolve_session_ref(chat_id, session_ref, cwd)
            .ok_or_else(|| {
                format!(
                    "No session matches \"{}\". Use /sessions first.",
                    session_ref
                )
            })?;
        self.session_manager
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .set_persisted_session(&chat_id.to_string(), &id);
        Ok(id)
    }

    pub fn delete_session(
        &self,
        reference: &str,
        cwd: Option<&str>,
        chat_id: Option<i64>,
    ) -> String {
        let cid = chat_id.unwrap_or(0);
        let Some(id) = self.resolve_session_ref(cid, reference, cwd) else {
            return format!("No session matches \"{}\". Use /sessions first.", reference);
        };
        let home = self
            .env_map
            .get("HOME")
            .cloned()
            .or_else(|| env::var("HOME").ok())
            .unwrap_or_else(|| "/".to_string());
        let data_dirs = agy_data_dirs_for_home(Path::new(&home));
        let data_dir = agy_data_dir_from_dirs(&data_dirs);
        let db_path = data_dir.join("conversation_summaries.db");
        if db_path.exists() {
            let escaped = id.replace('\'', "''");
            let sql = format!(
                "DELETE FROM conversation_summaries WHERE conversation_id = '{}';",
                escaped
            );
            let _ = Command::new("sqlite3").arg(&db_path).arg(&sql).status();
        }
        for suffix in [".db", ".db-wal", ".db-shm"] {
            let _ = fs::remove_file(
                data_dir
                    .join("conversations")
                    .join(format!("{}{}", id, suffix)),
            );
        }
        if let Some(c) = chat_id {
            self.last_session_listing
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .remove(&c);
        }
        let short: String = id.chars().take(8).collect();
        format!("Deleted conversation {}…", short)
    }
}

pub fn extract_semver(text: &str) -> Option<String> {
    for token in text.split_whitespace() {
        let clean = token.trim_matches(|c: char| !c.is_ascii_digit() && c != '.');
        let parts: Vec<&str> = clean.split('.').collect();
        if parts.len() == 3
            && parts
                .iter()
                .all(|p| !p.is_empty() && p.chars().all(|c| c.is_ascii_digit()))
        {
            return Some(clean.to_string());
        }
    }
    None
}

// ─── Global Module-Level Functions (matching agy.js exports) ─────────────────

static GLOBAL_BRIDGE: OnceLock<AgyBridge> = OnceLock::new();

pub fn global_bridge() -> &'static AgyBridge {
    GLOBAL_BRIDGE.get_or_init(AgyBridge::from_process_env)
}

pub fn get_chat_settings(chat_id: i64) -> ChatSettings {
    global_bridge().get_chat_settings(chat_id)
}

pub fn set_chat_setting_str(chat_id: i64, key: &str, value: &str) {
    global_bridge().set_chat_setting_str(chat_id, key, value);
}

pub fn set_chat_setting_bool(chat_id: i64, key: &str, value: bool) {
    global_bridge().set_chat_setting_bool(chat_id, key, value);
}

pub fn clear_session(chat_id: i64) {
    delete_persisted_session(chat_id);
}

pub fn has_session(chat_id: i64) -> bool {
    has_persisted_session(chat_id)
}

pub fn get_session(chat_id: i64) -> Option<String> {
    get_persisted_session(chat_id)
}

pub fn cancel_prompt(chat_id: i64) -> bool {
    global_bridge().cancel_prompt(chat_id)
}

pub fn get_running_info(chat_id: i64) -> Option<RunningProcessInfo> {
    global_bridge().get_running_info(chat_id)
}
