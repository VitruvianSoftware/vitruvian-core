// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone)]
pub struct BuiltinPattern {
    pub id: &'static str,
    pub category: &'static str,
    pub severity: &'static str,
    pub cwe: &'static str,
    pub message: &'static str,
    pub remediation: &'static str,
    pub matcher: fn(&str) -> bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Finding {
    pub id: String,
    pub rule_id: String,
    pub category: String,
    pub severity: String,
    pub cwe: String,
    pub file_path: String,
    pub line: usize,
    pub snippet: String,
    pub message: String,
    pub remediation: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub conversation_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tool: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub timestamp: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SecurityStore {
    pub findings: Vec<Finding>,
    pub suppressions: Vec<Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SeverityCounts {
    pub critical: usize,
    pub high: usize,
    pub medium: usize,
    pub low: usize,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SecuritySummary {
    pub total_active: usize,
    pub total_recorded: usize,
    pub suppressed_count: usize,
    pub counts: SeverityCounts,
    pub active_findings: Vec<Finding>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct HookSpecificOutput {
    hook_event_name: &'static str,
    permission_decision: String,
    permission_decision_reason: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SecurityHookOutput {
    permission_decision: String,
    permission_decision_reason: String,
    hook_specific_output: HookSpecificOutput,
}

fn is_word_byte(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

fn word_boundary_at(bytes: &[u8], idx: usize) -> bool {
    let prev = idx > 0 && is_word_byte(bytes[idx - 1]);
    let next = idx < bytes.len() && is_word_byte(bytes[idx]);
    prev != next
}

fn match_hardcoded_private_key(line: &str) -> bool {
    let Some(idx) = line.find("-----BEGIN") else {
        return false;
    };
    let rest = &line[idx + "-----BEGIN".len()..];
    if !rest.starts_with(|c: char| c.is_whitespace()) {
        return false;
    }
    let rest = rest.trim_start();
    let rest = for_optional_key_type(rest);
    if !rest.starts_with("PRIVATE") {
        return false;
    }
    let rest = &rest["PRIVATE".len()..];
    if !rest.starts_with(|c: char| c.is_whitespace()) {
        return false;
    }
    let rest = rest.trim_start();
    rest.starts_with("KEY-----")
}

fn for_optional_key_type(s: &str) -> &str {
    for prefix in ["RSA", "EC", "DSA", "OPENSSH", "PGP"] {
        if let Some(after) = s.strip_prefix(prefix) {
            if after.starts_with(|c: char| c.is_whitespace()) {
                return after.trim_start();
            }
        }
    }
    s
}

fn match_aws_access_key(line: &str) -> bool {
    let bytes = line.as_bytes();
    if bytes.len() < 20 {
        return false;
    }
    for i in 0..=bytes.len() - 20 {
        if (&bytes[i..i + 4] == b"AKIA" || &bytes[i..i + 4] == b"ASIA")
            && word_boundary_at(bytes, i)
            && word_boundary_at(bytes, i + 20)
            && bytes[i + 4..i + 20]
                .iter()
                .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit())
        {
            return true;
        }
    }
    false
}

fn match_gcp_api_key(line: &str) -> bool {
    let bytes = line.as_bytes();
    if bytes.len() < 37 {
        return false;
    }
    for i in 0..=bytes.len() - 37 {
        if &bytes[i..i + 4] == b"AIza" && word_boundary_at(bytes, i) {
            let mut count = 0usize;
            while i + 4 + count < bytes.len() && is_word_or_hyphen(bytes[i + 4 + count]) {
                count += 1;
            }
            if (33..=39).contains(&count) && word_boundary_at(bytes, i + 4 + count) {
                return true;
            }
        }
    }
    false
}

fn is_word_or_hyphen(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_' || b == b'-'
}

fn match_github_pat(line: &str) -> bool {
    let bytes = line.as_bytes();
    for i in 0..bytes.len() {
        if i + 40 <= bytes.len()
            && &bytes[i..i + 4] == b"ghp_"
            && word_boundary_at(bytes, i)
            && bytes[i + 4..i + 40]
                .iter()
                .all(|b| b.is_ascii_alphanumeric())
            && word_boundary_at(bytes, i + 40)
        {
            return true;
        }
        if i + 61 <= bytes.len()
            && &bytes[i..i + 11] == b"github_pat_"
            && word_boundary_at(bytes, i)
        {
            let mut count = 0usize;
            while i + 11 + count < bytes.len() && is_word_byte(bytes[i + 11 + count]) {
                count += 1;
            }
            if count >= 50 && word_boundary_at(bytes, i + 11 + count) {
                return true;
            }
        }
    }
    false
}

fn match_command_injection_curl_sh(line: &str) -> bool {
    let bytes = line.as_bytes();
    for i in 0..bytes.len() {
        let cmd_len = if line[i..].starts_with("curl") {
            4
        } else if line[i..].starts_with("wget") {
            4
        } else {
            continue;
        };
        if !word_boundary_at(bytes, i) || !word_boundary_at(bytes, i + cmd_len) {
            continue;
        }
        let after_cmd = &line[i + cmd_len..];
        let Some(pipe_rel) = after_cmd.find('|') else {
            continue;
        };
        if after_cmd[..pipe_rel].contains('\n') {
            continue;
        }
        let mut after_pipe = after_cmd[pipe_rel + 1..].trim_start();
        if let Some(rest) = after_pipe.strip_prefix("sudo") {
            if rest.starts_with(|c: char| c.is_whitespace()) {
                after_pipe = rest.trim_start();
            }
        }
        let sh_len = if after_pipe.starts_with("bash") {
            4
        } else if after_pipe.starts_with("sh") {
            2
        } else {
            continue;
        };
        let sh_bytes = after_pipe.as_bytes();
        if word_boundary_at(sh_bytes, sh_len) {
            return true;
        }
    }
    false
}

fn match_js_eval(line: &str) -> bool {
    let bytes = line.as_bytes();
    for i in 0..bytes.len() {
        if line[i..].starts_with("eval") && word_boundary_at(bytes, i) {
            let rest = line[i + 4..].trim_start();
            if rest.starts_with('(') {
                return true;
            }
        }
        if line[i..].starts_with("new")
            && word_boundary_at(bytes, i)
            && word_boundary_at(bytes, i + 3)
        {
            let rest = &line[i + 3..];
            if !rest.starts_with(|c: char| c.is_whitespace()) {
                continue;
            }
            let rest = rest.trim_start();
            if let Some(after_fn) = rest.strip_prefix("Function") {
                if after_fn.trim_start().starts_with('(') {
                    return true;
                }
            }
        }
    }
    false
}

fn match_dom_xss_innerhtml(line: &str) -> bool {
    for needle in [".innerHTML", "dangerouslySetInnerHTML"] {
        let mut search = line;
        while let Some(idx) = search.find(needle) {
            let after = search[idx + needle.len()..].trim_start();
            if after.starts_with('=') {
                return true;
            }
            search = &search[idx + needle.len()..];
        }
    }
    false
}

fn match_python_pickle_loads(line: &str) -> bool {
    let bytes = line.as_bytes();
    for i in 0..bytes.len() {
        let prefix_len = if line[i..].starts_with("cpickle.") {
            8
        } else if line[i..].starts_with("pickle.") {
            7
        } else {
            continue;
        };
        if !word_boundary_at(bytes, i) {
            continue;
        }
        let after_dot = &line[i + prefix_len..];
        for method in ["loads", "load", "Unpickler"] {
            if let Some(rest) = after_dot.strip_prefix(method) {
                if rest.trim_start().starts_with('(') {
                    return true;
                }
            }
        }
    }
    false
}

fn match_python_yaml_unsafe_load(line: &str) -> bool {
    let bytes = line.as_bytes();
    for i in 0..bytes.len() {
        if line[i..].starts_with("yaml.load") && word_boundary_at(bytes, i) {
            let rest = line[i + "yaml.load".len()..].trim_start();
            if let Some(inside) = rest.strip_prefix('(') {
                let before_close = inside.split(')').next().unwrap_or(inside);
                if !before_close.contains("SafeLoader") {
                    return true;
                }
            }
        }
    }
    false
}

fn match_pytorch_unsafe_load(line: &str) -> bool {
    let bytes = line.as_bytes();
    for i in 0..bytes.len() {
        if line[i..].starts_with("torch.load") && word_boundary_at(bytes, i) {
            let rest = line[i + "torch.load".len()..].trim_start();
            if let Some(inside) = rest.strip_prefix('(') {
                let before_close = inside.split(')').next().unwrap_or(inside);
                if !has_weights_only_true(before_close) {
                    return true;
                }
            }
        }
    }
    false
}

fn has_weights_only_true(s: &str) -> bool {
    let Some(idx) = s.find("weights_only") else {
        return false;
    };
    let rest = s[idx + "weights_only".len()..].trim_start();
    let Some(rest) = rest.strip_prefix('=') else {
        return false;
    };
    rest.trim_start().starts_with("True")
}

fn match_python_subprocess_shell(line: &str) -> bool {
    let bytes = line.as_bytes();
    for i in 0..bytes.len() {
        if line[i..].starts_with("os.system") && word_boundary_at(bytes, i) {
            if line[i + "os.system".len()..].trim_start().starts_with('(') {
                return true;
            }
        }
        if line[i..].starts_with("subprocess.") && word_boundary_at(bytes, i) {
            let after_dot = &line[i + "subprocess.".len()..];
            for func in ["check_output", "check_call", "Popen", "run", "call"] {
                if let Some(rest) = after_dot.strip_prefix(func) {
                    let rest = rest.trim_start();
                    if let Some(inside) = rest.strip_prefix('(') {
                        let before_close = inside.split(')').next().unwrap_or(inside);
                        if has_shell_true(before_close) {
                            return true;
                        }
                    }
                }
            }
        }
    }
    false
}

fn has_shell_true(s: &str) -> bool {
    let Some(idx) = s.find("shell") else {
        return false;
    };
    let rest = s[idx + "shell".len()..].trim_start();
    let Some(rest) = rest.strip_prefix('=') else {
        return false;
    };
    rest.trim_start().starts_with("True")
}

fn match_node_child_process_exec(line: &str) -> bool {
    let bytes = line.as_bytes();
    for i in 0..bytes.len() {
        let fn_len = if line[i..].starts_with("execSync") {
            8
        } else if line[i..].starts_with("exec") {
            4
        } else {
            continue;
        };
        if !word_boundary_at(bytes, i) || !word_boundary_at(bytes, i + fn_len) {
            continue;
        }
        let rest = line[i + fn_len..].trim_start();
        let Some(rest) = rest.strip_prefix('(') else {
            continue;
        };
        let rest = rest.trim_start();
        let Some(inside_bt) = rest.strip_prefix('`') else {
            continue;
        };
        let before_close_bt = inside_bt.split('`').next().unwrap_or("");
        if before_close_bt.contains("${") {
            return true;
        }
    }
    false
}

fn match_sql_string_concat(line: &str) -> bool {
    let upper = line.to_ascii_uppercase();
    let bytes = upper.as_bytes();
    for i in 0..bytes.len() {
        if !word_boundary_at(bytes, i) {
            continue;
        }
        let kw_end = if upper[i..].starts_with("SELECT") && word_boundary_at(bytes, i + 6) {
            Some(i + 6)
        } else if upper[i..].starts_with("UPDATE") && word_boundary_at(bytes, i + 6) {
            Some(i + 6)
        } else if upper[i..].starts_with("INSERT") && word_boundary_at(bytes, i + 6) {
            let rest = &upper[i + 6..];
            if rest.starts_with(|c: char| c.is_whitespace()) {
                let trimmed = rest.trim_start();
                let ws_len = rest.len() - trimmed.len();
                if trimmed.starts_with("INTO") && word_boundary_at(bytes, i + 6 + ws_len + 4) {
                    Some(i + 6 + ws_len + 4)
                } else {
                    None
                }
            } else {
                None
            }
        } else if upper[i..].starts_with("DELETE") && word_boundary_at(bytes, i + 6) {
            let rest = &upper[i + 6..];
            if rest.starts_with(|c: char| c.is_whitespace()) {
                let trimmed = rest.trim_start();
                let ws_len = rest.len() - trimmed.len();
                if trimmed.starts_with("FROM") && word_boundary_at(bytes, i + 6 + ws_len + 4) {
                    Some(i + 6 + ws_len + 4)
                } else {
                    None
                }
            } else {
                None
            }
        } else {
            None
        };

        let Some(start_after_kw) = kw_end else {
            continue;
        };
        let tail = &line[start_after_kw..];
        if check_sql_tail_interpolation(tail) {
            return true;
        }
    }
    false
}

fn check_sql_tail_interpolation(tail: &str) -> bool {
    let bytes = tail.as_bytes();
    let mut j = 0;
    while j < bytes.len() {
        let b = bytes[j];
        if b == b'\n' || b == b';' || b == b'`' || b == b'\'' || b == b'"' {
            if b == b'+' || (b == b'$' && j + 1 < bytes.len() && bytes[j + 1] == b'{') {
                // handled below
            } else {
                return false;
            }
        }
        if b == b'+' {
            let after_plus = tail[j + 1..].trim_start();
            if let Some(first_ch) = after_plus.chars().next() {
                if first_ch.is_ascii_alphabetic() || first_ch == '_' || first_ch == '$' {
                    return true;
                }
            }
        } else if b == b'$' && j + 1 < bytes.len() && bytes[j + 1] == b'{' {
            let after_open = &tail[j + 2..];
            if let Some(close_idx) = after_open.find('}') {
                if close_idx > 0 {
                    return true;
                }
            }
        }
        j += 1;
    }
    false
}

fn match_path_traversal(line: &str) -> bool {
    line.contains("../../")
}

fn match_ssrf_metadata_ip(line: &str) -> bool {
    let needle = "169.254.169.254";
    let bytes = line.as_bytes();
    let mut start = 0;
    while let Some(rel) = line[start..].find(needle) {
        let idx = start + rel;
        if word_boundary_at(bytes, idx) && word_boundary_at(bytes, idx + needle.len()) {
            return true;
        }
        start = idx + needle.len();
    }
    false
}

fn match_github_actions_script_injection(line: &str) -> bool {
    let mut rest = line;
    while let Some(idx) = rest.find("${{") {
        let after = rest[idx + 3..].trim_start();
        if let Some(after_ev) = after.strip_prefix("github.event.") {
            for kind in [
                "issue.",
                "pull_request.",
                "comment.",
                "review.",
                "commits.",
                "head_commit.",
            ] {
                if let Some(after_kind) = after_ev.strip_prefix(kind) {
                    if let Some(close_idx) = after_kind.find("}}") {
                        if close_idx > 0 && !after_kind[..close_idx].contains('}') {
                            return true;
                        }
                    }
                }
            }
        }
        rest = &rest[idx + 3..];
    }
    false
}

pub static BUILTIN_PATTERNS: &[BuiltinPattern] = &[
    BuiltinPattern {
        id: "hardcoded-private-key",
        category: "secrets",
        severity: "critical",
        cwe: "CWE-798",
        message: "Hardcoded PEM private key block detected.",
        remediation: "Remove private keys from source code and load them from secret managers or environment variables at runtime.",
        matcher: match_hardcoded_private_key,
    },
    BuiltinPattern {
        id: "aws-access-key",
        category: "secrets",
        severity: "critical",
        cwe: "CWE-798",
        message: "Hardcoded AWS Access Key ID detected.",
        remediation: "Use IAM workload identity federation or environment credentials instead of embedding AWS access keys.",
        matcher: match_aws_access_key,
    },
    BuiltinPattern {
        id: "gcp-api-key",
        category: "secrets",
        severity: "high",
        cwe: "CWE-798",
        message: "Hardcoded Google Cloud API key detected.",
        remediation: "Inject API keys via secret manager or runtime environment variables and restrict key scope.",
        matcher: match_gcp_api_key,
    },
    BuiltinPattern {
        id: "github-pat",
        category: "secrets",
        severity: "critical",
        cwe: "CWE-798",
        message: "Hardcoded GitHub Personal Access Token detected.",
        remediation: "Revoke the token immediately and use short-lived GitHub App installation tokens instead.",
        matcher: match_github_pat,
    },
    BuiltinPattern {
        id: "command-injection-curl-sh",
        category: "command-injection",
        severity: "critical",
        cwe: "CWE-78",
        message: "Remote script piped directly into a shell interpreter.",
        remediation: "Download the artifact to a temporary file, verify its cryptographic checksum or signature, and then execute it.",
        matcher: match_command_injection_curl_sh,
    },
    BuiltinPattern {
        id: "js-eval",
        category: "code-injection",
        severity: "high",
        cwe: "CWE-95",
        message: "Dynamic JavaScript code execution via eval() or new Function().",
        remediation: "Use JSON.parse() for data parsing or an explicit lookup table instead of dynamic code evaluation.",
        matcher: match_js_eval,
    },
    BuiltinPattern {
        id: "dom-xss-innerhtml",
        category: "xss",
        severity: "high",
        cwe: "CWE-79",
        message: "Potential DOM XSS via direct HTML injection (.innerHTML / dangerouslySetInnerHTML).",
        remediation: "Use .textContent, safe DOM node construction, or sanitize untrusted HTML with DOMPurify before rendering.",
        matcher: match_dom_xss_innerhtml,
    },
    BuiltinPattern {
        id: "python-pickle-loads",
        category: "deserialization",
        severity: "high",
        cwe: "CWE-502",
        message: "Unsafe Python pickle deserialization can execute arbitrary code.",
        remediation: "Use json.loads(), msgpack, or protobuf instead of unpickling untrusted bytes.",
        matcher: match_python_pickle_loads,
    },
    BuiltinPattern {
        id: "python-yaml-unsafe-load",
        category: "deserialization",
        severity: "high",
        cwe: "CWE-502",
        message: "yaml.load() called without SafeLoader allows arbitrary object instantiation.",
        remediation: "Use yaml.safe_load() or pass Loader=yaml.SafeLoader explicitly.",
        matcher: match_python_yaml_unsafe_load,
    },
    BuiltinPattern {
        id: "pytorch-unsafe-load",
        category: "deserialization",
        severity: "high",
        cwe: "CWE-502",
        message: "torch.load() without weights_only=True uses pickle under the hood.",
        remediation: "Pass weights_only=True to torch.load() or use safetensors.",
        matcher: match_pytorch_unsafe_load,
    },
    BuiltinPattern {
        id: "python-subprocess-shell",
        category: "command-injection",
        severity: "high",
        cwe: "CWE-78",
        message: "Shell command execution via subprocess(shell=True) or os.system().",
        remediation: "Pass an argument list (e.g. subprocess.run(['cmd', arg])) with shell=False.",
        matcher: match_python_subprocess_shell,
    },
    BuiltinPattern {
        id: "node-child-process-exec",
        category: "command-injection",
        severity: "medium",
        cwe: "CWE-78",
        message: "Interpolated template literal passed to child_process.exec / execSync.",
        remediation: "Use execFile / execFileSync or spawn with an explicit arguments array instead of shell interpolation.",
        matcher: match_node_child_process_exec,
    },
    BuiltinPattern {
        id: "sql-string-concat",
        category: "sql-injection",
        severity: "high",
        cwe: "CWE-89",
        message: "SQL statement constructed using string concatenation or template interpolation.",
        remediation: "Use parameterized queries ($1, ?) with bound parameter arrays.",
        matcher: match_sql_string_concat,
    },
    BuiltinPattern {
        id: "path-traversal",
        category: "path-traversal",
        severity: "medium",
        cwe: "CWE-22",
        message: "Multi-level relative path traversal sequence (../../) detected.",
        remediation: "Resolve paths with path.resolve() and verify they remain inside the allowed base directory.",
        matcher: match_path_traversal,
    },
    BuiltinPattern {
        id: "ssrf-metadata-ip",
        category: "ssrf",
        severity: "high",
        cwe: "CWE-918",
        message: "Cloud instance metadata service IP (169.254.169.254) referenced directly.",
        remediation: "Block link-local metadata addresses in outbound HTTP validators and use official SDK credential providers.",
        matcher: match_ssrf_metadata_ip,
    },
    BuiltinPattern {
        id: "github-actions-script-injection",
        category: "code-injection",
        severity: "high",
        cwe: "CWE-94",
        message: "Untrusted GitHub event context interpolated directly in workflow.",
        remediation: "Bind the expression to an intermediate step env: variable and reference it as a quoted shell variable.",
        matcher: match_github_actions_script_injection,
    },
];

/// Checks whether a single source line has an inline suppression comment for `rule_id`.
pub fn has_inline_suppression(line_text: &str, rule_id: &str) -> bool {
    let lower = line_text.to_ascii_lowercase();
    for marker in ["//", "#"] {
        let mut search = lower.as_str();
        while let Some(idx) = search.find(marker) {
            let after_marker = search[idx + marker.len()..].trim_start();
            for kw in ["security-guidance-ignore", "nosec"] {
                if let Some(after_kw) = after_marker.strip_prefix(kw) {
                    let rest = after_kw.trim_start();
                    let list_part = rest.strip_prefix(':').unwrap_or(rest).trim_start();
                    let captured: String = list_part
                        .chars()
                        .take_while(|c| {
                            c.is_ascii_alphanumeric()
                                || *c == '_'
                                || *c == ','
                                || *c == '-'
                                || *c == '*'
                                || c.is_whitespace()
                        })
                        .collect();
                    let trimmed = captured.trim();
                    if trimmed.is_empty() {
                        return true;
                    }
                    let target = rule_id.to_ascii_lowercase();
                    for id in trimmed.split(',').map(str::trim).filter(|s| !s.is_empty()) {
                        if id == "*" || id == "all" || id == target {
                            return true;
                        }
                    }
                }
            }
            search = &search[idx + marker.len()..];
        }
    }
    false
}

/// Scans `content` against `BUILTIN_PATTERNS`, respecting inline suppression comments.
pub fn scan_content_for_patterns(
    content: &str,
    file_path: Option<&str>,
    start_line: Option<usize>,
) -> Vec<Finding> {
    let text = content.replace("\r\n", "\n");
    if text.is_empty() {
        return Vec::new();
    }
    let fp = file_path.filter(|s| !s.is_empty()).unwrap_or("<inline>");
    let base_line = start_line.filter(|&n| n > 0).unwrap_or(1);

    let mut findings = Vec::new();
    for (i, line_text) in text.split('\n').enumerate() {
        let line_num = base_line + i;
        for pat in BUILTIN_PATTERNS {
            if (pat.matcher)(line_text) {
                if has_inline_suppression(line_text, pat.id) {
                    continue;
                }
                let snippet: String = line_text.trim().chars().take(160).collect();
                findings.push(Finding {
                    id: format!("{}:{}:{}", pat.id, fp, line_num),
                    rule_id: pat.id.to_string(),
                    category: pat.category.to_string(),
                    severity: pat.severity.to_string(),
                    cwe: pat.cwe.to_string(),
                    file_path: fp.to_string(),
                    line: line_num,
                    snippet,
                    message: pat.message.to_string(),
                    remediation: pat.remediation.to_string(),
                    conversation_id: None,
                    tool: None,
                    timestamp: None,
                });
            }
        }
    }
    findings
}

fn parse_hunk_new_start(line: &str) -> Option<usize> {
    let rest = line.strip_prefix("@@")?;
    let rest = rest.trim_start();
    let rest = rest.strip_prefix('-')?;
    let rest = rest.trim_start_matches(|c: char| c.is_ascii_digit() || c == ',');
    let rest = rest.trim_start();
    let rest = rest.strip_prefix('+')?;
    let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
    if digits.is_empty() {
        return None;
    }
    let after_digits = &rest[digits.len()..];
    let after_range = if let Some(after_comma) = after_digits.strip_prefix(',') {
        after_comma.trim_start_matches(|c: char| c.is_ascii_digit())
    } else {
        after_digits
    };
    if !after_range.trim_start().starts_with("@@") {
        return None;
    }
    digits.parse::<usize>().ok()
}

/// Scans a unified git diff (only added `+` lines) for vulnerabilities.
pub fn scan_diff_for_vulnerabilities(diff_text: &str) -> Vec<Finding> {
    let normalized = diff_text.replace("\r\n", "\n");
    let mut current_file = "<diff>".to_string();
    let mut current_line = 1usize;
    let mut findings = Vec::new();

    for line in normalized.split('\n') {
        if let Some(rest) = line.strip_prefix("+++ b/") {
            current_file = rest.trim().to_string();
            continue;
        }
        if let Some(rest) = line.strip_prefix("+++ ") {
            current_file = rest.trim().to_string();
            continue;
        }
        if let Some(new_start) = parse_hunk_new_start(line) {
            current_line = new_start;
            continue;
        }
        if let Some(added_text) = line.strip_prefix('+') {
            if !line.starts_with("+++") {
                let line_findings =
                    scan_content_for_patterns(added_text, Some(&current_file), Some(current_line));
                findings.extend(line_findings);
                current_line += 1;
            }
        } else if !line.starts_with('-') && !line.starts_with('\\') {
            current_line += 1;
        }
    }
    findings
}

/// Filters out findings that match any stored suppression rule.
pub fn filter_suppressed_findings(findings: &[Finding], suppressions: &[Value]) -> Vec<Finding> {
    if suppressions.is_empty() {
        return findings.to_vec();
    }
    findings
        .iter()
        .filter(|f| {
            !suppressions.iter().any(|s| match s {
                Value::String(str_val) => {
                    str_val == &f.id || str_val == &f.rule_id || str_val == &f.file_path
                }
                Value::Object(obj) => {
                    if let Some(id) = obj.get("id").and_then(|v| v.as_str()) {
                        if !id.is_empty() && id == f.id {
                            return true;
                        }
                    }
                    let rule_id = obj.get("ruleId").and_then(|v| v.as_str()).unwrap_or("");
                    let file_path = obj.get("filePath").and_then(|v| v.as_str()).unwrap_or("");
                    if !rule_id.is_empty() && !file_path.is_empty() {
                        return rule_id == f.rule_id && file_path == f.file_path;
                    }
                    if !rule_id.is_empty() && file_path.is_empty() {
                        return rule_id == f.rule_id;
                    }
                    false
                }
                _ => false,
            })
        })
        .cloned()
        .collect()
}

/// Summarises active findings, severity counts, and suppressions.
pub fn summarise_security_state(store: &SecurityStore) -> SecuritySummary {
    let active = filter_suppressed_findings(&store.findings, &store.suppressions);
    let mut counts = SeverityCounts {
        critical: 0,
        high: 0,
        medium: 0,
        low: 0,
    };
    for f in &active {
        match f.severity.to_ascii_lowercase().as_str() {
            "critical" => counts.critical += 1,
            "high" => counts.high += 1,
            "medium" => counts.medium += 1,
            "low" => counts.low += 1,
            _ => counts.medium += 1,
        }
    }
    let diff = store.findings.len().saturating_sub(active.len());
    let suppressed_count = if diff > 0 {
        diff
    } else {
        store.suppressions.len()
    };

    SecuritySummary {
        total_active: active.len(),
        total_recorded: store.findings.len(),
        suppressed_count,
        counts,
        active_findings: active,
    }
}

/// Resolves the app data directory from `ANTIGRAVITY_APP_DATA_DIR` or `HOME`.
pub fn resolve_app_dir(app_data_dir: Option<&str>, home_dir: Option<&str>) -> Option<PathBuf> {
    if let Some(dir) = app_data_dir.filter(|s| !s.is_empty()) {
        return Some(PathBuf::from(dir));
    }
    let home = home_dir.filter(|s| !s.is_empty())?;
    Some(Path::new(home).join(".gemini").join("antigravity"))
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

fn val_str(v: Option<&Value>) -> Option<String> {
    match v {
        Some(Value::String(s)) => Some(s.clone()),
        Some(Value::Number(n)) => Some(n.to_string()),
        Some(Value::Bool(b)) => Some(b.to_string()),
        _ => None,
    }
}

/// Evaluates the hook payload, updates `security-guidance-state.json` on active findings,
/// and returns the JSON output string.
pub fn handle_security_hook(payload_str: &str, app_dir: Option<&Path>) -> String {
    if payload_str.is_empty() {
        return "{}".to_string();
    }
    let Ok(Value::Object(payload)) = serde_json::from_str::<Value>(payload_str) else {
        return "{}".to_string();
    };

    let is_stop = payload.get("hook_event_name").and_then(|v| v.as_str()) == Some("Stop")
        || payload.get("event").and_then(|v| v.as_str()) == Some("Stop")
        || (!payload.contains_key("toolCall")
            && !payload.contains_key("tool_name")
            && (payload.contains_key("stop_hook_active") || payload.contains_key("reason")));

    if is_stop {
        return "{}".to_string();
    }

    let state_file = app_dir.map(|d| d.join("security-guidance-state.json"));
    let mut store = SecurityStore::default();
    if let Some(sf) = &state_file {
        if let Ok(raw) = fs::read_to_string(sf) {
            if let Ok(parsed) = serde_json::from_str::<SecurityStore>(&raw) {
                store = parsed;
            }
        }
    }

    let tool_call = payload.get("toolCall").and_then(|v| v.as_object());
    let args = tool_call
        .and_then(|tc| tc.get("args"))
        .and_then(|v| v.as_object())
        .or_else(|| payload.get("tool_input").and_then(|v| v.as_object()));

    let tool_name = tool_call
        .and_then(|tc| tc.get("name"))
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .or_else(|| {
            payload
                .get("tool_name")
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
        })
        .unwrap_or("unknown");

    let file_path = args
        .and_then(|a| {
            a.get("Path")
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
                .or_else(|| {
                    a.get("file_path")
                        .and_then(|v| v.as_str())
                        .filter(|s| !s.is_empty())
                })
        })
        .map(str::to_string)
        .unwrap_or_else(|| {
            if tool_name == "run_command" {
                "<shell>".to_string()
            } else {
                "<unknown>".to_string()
            }
        });

    let content = args
        .and_then(|a| {
            val_str(a.get("Content"))
                .or_else(|| val_str(a.get("Replacement")))
                .or_else(|| val_str(a.get("new_string")))
                .or_else(|| val_str(a.get("CommandLine")))
                .or_else(|| val_str(a.get("command")))
        })
        .unwrap_or_default();

    let raw_findings = scan_content_for_patterns(&content, Some(&file_path), None);
    let active_findings = filter_suppressed_findings(&raw_findings, &store.suppressions);

    if active_findings.is_empty() {
        return "{}".to_string();
    }

    let now = now_millis();
    let conv_id = payload
        .get("conversationId")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    let recorded: Vec<Finding> = active_findings
        .iter()
        .map(|f| {
            let mut item = f.clone();
            item.conversation_id = Some(conv_id.clone());
            item.tool = Some(tool_name.to_string());
            item.timestamp = Some(now);
            item
        })
        .collect();

    if let (Some(dir), Some(sf)) = (app_dir, &state_file) {
        if fs::create_dir_all(dir).is_ok() {
            let mut seen = HashSet::new();
            let mut merged = Vec::new();
            for item in recorded.into_iter().chain(store.findings.into_iter()) {
                if !item.id.is_empty() && seen.insert(item.id.clone()) {
                    merged.push(item);
                    if merged.len() >= 200 {
                        break;
                    }
                }
            }
            store.findings = merged;
            if let Ok(serialized) = serde_json::to_string_pretty(&store) {
                let tmp = sf.with_extension("json.tmp");
                if fs::write(&tmp, format!("{serialized}\n")).is_ok() {
                    let _ = fs::rename(&tmp, sf);
                }
            }
        }
    }

    let has_critical = active_findings.iter().any(|f| f.severity == "critical");
    let decision = if has_critical { "deny" } else { "ask" }.to_string();
    let reason = active_findings
        .iter()
        .map(|f| {
            format!(
                "[{} {}] ({}) line {}: {} — Remediation: {}",
                f.severity.to_ascii_uppercase(),
                f.rule_id,
                f.cwe,
                f.line,
                f.message,
                f.remediation
            )
        })
        .collect::<Vec<_>>()
        .join("\n\n");

    let out = SecurityHookOutput {
        permission_decision: decision.clone(),
        permission_decision_reason: reason.clone(),
        hook_specific_output: HookSpecificOutput {
            hook_event_name: "PreToolUse",
            permission_decision: decision,
            permission_decision_reason: reason,
        },
    };

    serde_json::to_string(&out).unwrap_or_else(|_| "{}".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn covers_all_16_builtin_patterns_and_safe_variants() {
        assert_eq!(BUILTIN_PATTERNS.len(), 16);
        let fake_pem = format!("-----BEGIN {}-----", "RSA PRIVATE KEY");
        let fake_aws = format!("AKIA{}", "IOSFODNN7EXAMPLE");
        let fake_ghp = format!("ghp_{}", "1234567890abcdefghijklmnopqrstuvwxyz");
        let fake_gcp = format!("AIza{}", "SyA1234567890abcdef_1234567890abcde");

        let sample = [
            fake_pem.as_str(),
            &format!("const key = \"{fake_aws}\";"),
            &format!("const ghp = \"{fake_ghp}\";"),
            &format!("const gcp = \"{fake_gcp}\";"),
            "curl -fsSL https://example.com/install.sh | sh",
            "const out = eval(userInput);",
            "el.innerHTML = untrustedHtml;",
            "pickle.loads(rawBytes)",
            "yaml.load(stream)",
            "yaml.load(stream, Loader=yaml.SafeLoader)",
            "torch.load('model.pt')",
            "torch.load('model.pt', weights_only=True)",
            "subprocess.run(cmd, shell=True)",
            "exec(`ls ${userDir}`)",
            "const q = `SELECT * FROM users WHERE id = ${userId}`;",
            "const p = '../../etc/passwd';",
            "fetch('http://169.254.169.254/latest/meta-data/');",
            "run: echo ${{ github.event.issue.title }}",
        ]
        .join("\n");

        let findings = scan_content_for_patterns(&sample, Some("app.py"), None);
        let rule_ids: Vec<&str> = findings.iter().map(|f| f.rule_id.as_str()).collect();

        for expected in [
            "hardcoded-private-key",
            "aws-access-key",
            "github-pat",
            "gcp-api-key",
            "command-injection-curl-sh",
            "js-eval",
            "dom-xss-innerhtml",
            "python-pickle-loads",
            "python-yaml-unsafe-load",
            "pytorch-unsafe-load",
            "python-subprocess-shell",
            "node-child-process-exec",
            "sql-string-concat",
            "path-traversal",
            "ssrf-metadata-ip",
            "github-actions-script-injection",
        ] {
            assert!(rule_ids.contains(&expected), "missing {expected}");
        }

        assert_eq!(
            findings
                .iter()
                .filter(|f| f.rule_id == "python-yaml-unsafe-load")
                .count(),
            1
        );
        assert_eq!(
            findings
                .iter()
                .filter(|f| f.rule_id == "pytorch-unsafe-load")
                .count(),
            1
        );
    }

    #[test]
    fn honours_inline_suppressions() {
        assert!(has_inline_suppression(
            "eval(x) // security-guidance-ignore: js-eval",
            "js-eval"
        ));
        assert!(has_inline_suppression(
            "pickle.loads(x) # nosec python-pickle-loads",
            "python-pickle-loads"
        ));
        let code = "eval(a); // security-guidance-ignore: js-eval\neval(b);";
        let findings = scan_content_for_patterns(code, Some("index.js"), None);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].line, 2);
    }

    #[test]
    fn scans_diff_added_lines_only() {
        let diff = [
            "--- a/src/view.js",
            "+++ b/src/view.js",
            "@@ -10,3 +10,4 @@",
            " const clean = 1;",
            "-oldNode.innerHTML = legacy;",
            "+newNode.innerHTML = untrusted;",
            " const done = true;",
        ]
        .join("\n");
        let findings = scan_diff_for_vulnerabilities(&diff);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].file_path, "src/view.js");
        assert_eq!(findings[0].line, 11);
        assert_eq!(findings[0].rule_id, "dom-xss-innerhtml");
    }

    #[test]
    fn filters_suppressed_and_summarises() {
        let findings = scan_content_for_patterns("eval(x)\n../../etc/passwd", Some("a.js"), None);
        assert_eq!(findings.len(), 2);
        let sup = vec![json!("js-eval:a.js:1")];
        let filtered = filter_suppressed_findings(&findings, &sup);
        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].rule_id, "path-traversal");

        let summary = summarise_security_state(&SecurityStore {
            findings,
            suppressions: sup,
        });
        assert_eq!(summary.total_active, 1);
        assert_eq!(summary.total_recorded, 2);
        assert_eq!(summary.suppressed_count, 1);
        assert_eq!(summary.counts.medium, 1);
        assert_eq!(summary.counts.high, 0);
    }
}
