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

use std::process::Command;

pub const AGENT_STATE_IDLE: &str = "idle";
pub const AGENT_STATE_RUNNING: &str = "running";
pub const AGENT_STATE_REVIEW: &str = "review";
pub const AGENT_STATE_ERROR: &str = "error";

pub const CI_STATUS_UNKNOWN: &str = "unknown";
pub const CI_STATUS_PASSING: &str = "passing";
pub const CI_STATUS_FAILING: &str = "failing";
pub const CI_STATUS_PENDING: &str = "pending";
pub const CI_STATUS_NONE: &str = "none";

pub fn detect_agent_error(content: &str) -> bool {
    if content.trim().is_empty() {
        return false;
    }

    for line in content.lines() {
        let lower = line.to_lowercase();
        if (lower.contains("status:") || lower.contains("state:") || lower.contains("state="))
            && (lower.contains("error")
                || lower.contains("failed")
                || lower.contains("failure")
                || lower.contains("blocked"))
        {
            return true;
        }
    }

    for line in content.lines() {
        let trimmed = line.trim();
        let lower = trimmed.to_lowercase();

        if trimmed.starts_with('#') {
            let heading = lower.trim_start_matches('#').trim();
            if heading.starts_with("verification failure")
                || heading.starts_with("failure")
                || heading.starts_with("blocked")
            {
                return true;
            }
            if heading.starts_with("error")
                && !heading.starts_with("error handling")
                && !heading.starts_with("error recovery")
            {
                return true;
            }
        }

        if lower.starts_with("error:")
            || lower.starts_with("fatal:")
            || lower.starts_with("failed:")
            || lower.starts_with("critical:")
        {
            return true;
        }

        if trimmed.starts_with("- ") || trimmed.starts_with("* ") {
            let rest = trimmed[2..].trim();
            let rest_lower = rest.to_lowercase();
            if rest_lower.starts_with("error:")
                || rest_lower.starts_with("blocked:")
                || rest_lower.starts_with("failed:")
            {
                return true;
            }
            if rest.starts_with("[") {
                if let Some(end) = rest.find(']') {
                    let after = rest[end + 1..].trim().to_lowercase();
                    if after.starts_with("error:")
                        || after.starts_with("blocked:")
                        || after.starts_with("failed:")
                    {
                        return true;
                    }
                }
            }
        }
    }

    false
}

pub fn parse_agent_processes(pgrep_output: &str) -> (Option<String>, usize) {
    if pgrep_output.trim().is_empty() {
        return (None, 0);
    }

    let mut count = 0usize;
    let mut has_agy = false;
    let mut has_claude = false;

    for line in pgrep_output.lines() {
        let line = line.trim();
        if line.is_empty() || line.contains("pgrep") || line.contains("grep") {
            continue;
        }
        let lower = line.to_lowercase();
        if lower.contains("antigravity") || lower.contains("agy") {
            has_agy = true;
            count += 1;
        } else if lower.contains("claude-code") || lower.contains("claude") {
            has_claude = true;
            count += 1;
        }
    }

    let name = if has_agy && has_claude {
        Some("Teamwork".into())
    } else if has_agy {
        Some("Antigravity".into())
    } else if has_claude {
        Some("Claude Code".into())
    } else {
        None
    };

    (name, count)
}

pub fn determine_agent_state(
    process_running: bool,
    last_mtime: f64,
    current_time: f64,
    has_error: bool,
) -> &'static str {
    if has_error {
        return AGENT_STATE_ERROR;
    }
    if !process_running {
        return AGENT_STATE_IDLE;
    }
    if last_mtime <= 0.0 {
        return AGENT_STATE_RUNNING;
    }
    let elapsed = (current_time - last_mtime).max(0.0);
    if elapsed < 45.0 {
        AGENT_STATE_RUNNING
    } else if elapsed < 300.0 {
        AGENT_STATE_REVIEW
    } else {
        AGENT_STATE_IDLE
    }
}

pub fn parse_agent_progress(content: &str) -> (String, String) {
    if content.trim().is_empty() {
        return ("Idle".into(), "idle".into());
    }

    let mut task = "Idle".to_string();
    let mut status = "idle".to_string();

    for line in content.lines() {
        let trimmed = line.trim();
        let lower = trimmed.to_lowercase();

        if lower.contains("status:") {
            if let Some(pos) = trimmed.find(':') {
                let val = trimmed[pos + 1..].trim().trim_matches(|c: char| {
                    c == '*' || c == '_' || c == '#' || c == '`' || c == ' '
                });
                if !val.is_empty() {
                    status = val.to_string();
                }
            }
        }

        if trimmed.starts_with("- [/]") || trimmed.starts_with("* [/]") {
            let rest = trimmed[5..].trim();
            if !rest.is_empty() {
                task = rest.to_string();
                break;
            }
        } else if (trimmed.starts_with("- [ ]") || trimmed.starts_with("* [ ]")) && task == "Idle" {
            let rest = trimmed[5..].trim();
            if !rest.is_empty() {
                task = rest.to_string();
            }
        }
    }

    (task, status)
}

pub fn parse_git_status(porcelain_output: &str) -> (String, bool, usize) {
    if porcelain_output.trim().is_empty() {
        return ("main".into(), false, 0);
    }

    let lines: Vec<&str> = porcelain_output
        .lines()
        .filter(|l| !l.trim().is_empty())
        .collect();
    if lines.is_empty() {
        return ("main".into(), false, 0);
    }

    let first = lines[0];
    let mut branch = "main".to_string();

    if first.starts_with("##") {
        let content = first[2..].trim();
        let cleaned = content
            .strip_prefix("Initial commit on ")
            .or_else(|| content.strip_prefix("No commits yet on "))
            .unwrap_or(content);

        if let Some(end) = cleaned.find(|c: char| {
            c == '.' && cleaned[cleaned.find(c).unwrap()..].starts_with("...") || c.is_whitespace()
        }) {
            branch = cleaned[..end].to_string();
        } else {
            branch = cleaned.to_string();
        }
        if let Some(dots) = branch.find("...") {
            branch = branch[..dots].to_string();
        }
    }

    let dirty_files = if lines.len() > 1 { lines.len() - 1 } else { 0 };
    let is_dirty = dirty_files > 0;

    (branch, is_dirty, dirty_files)
}

pub fn parse_gh_pr_checks(checks_json: &str) -> (&'static str, usize, usize) {
    if checks_json.trim().is_empty() {
        return (CI_STATUS_NONE, 0, 0);
    }

    let checks = match parse_json_array(checks_json) {
        Some(c) => c,
        None => return (CI_STATUS_UNKNOWN, 0, 0),
    };

    if checks.is_empty() {
        return (CI_STATUS_NONE, 0, 0);
    }

    let total = checks.len();
    let mut passed = 0;
    let mut has_failing = false;
    let mut has_pending = false;

    for check in &checks {
        let state = json_str_field(check, "state").to_uppercase();
        let bucket = json_str_field(check, "bucket").to_lowercase();

        if bucket == "pass" || matches!(state.as_str(), "SUCCESS" | "PASS" | "PASSED") {
            passed += 1;
        } else if bucket == "fail"
            || matches!(
                state.as_str(),
                "FAILURE" | "FAIL" | "FAILED" | "ERROR" | "CANCELLED"
            )
        {
            has_failing = true;
        } else if bucket == "pending"
            || matches!(state.as_str(), "PENDING" | "IN_PROGRESS" | "QUEUED")
        {
            has_pending = true;
        }
    }

    let status = if has_failing {
        CI_STATUS_FAILING
    } else if has_pending {
        CI_STATUS_PENDING
    } else if passed == total && total > 0 {
        CI_STATUS_PASSING
    } else if passed > 0 {
        CI_STATUS_PASSING
    } else {
        CI_STATUS_UNKNOWN
    };

    (status, passed, total)
}

pub fn parse_gh_run_list(run_json: &str) -> (&'static str, usize, usize) {
    if run_json.trim().is_empty() {
        return (CI_STATUS_NONE, 0, 0);
    }

    let runs = match parse_json_array(run_json) {
        Some(r) => r,
        None => return (CI_STATUS_UNKNOWN, 0, 0),
    };

    if runs.is_empty() {
        return (CI_STATUS_NONE, 0, 0);
    }

    let run = &runs[0];
    let status_field = json_str_field(run, "status").to_lowercase();
    let conclusion = json_str_field(run, "conclusion").to_lowercase();

    if matches!(conclusion.as_str(), "success" | "pass") {
        (CI_STATUS_PASSING, 1, 1)
    } else if matches!(
        conclusion.as_str(),
        "failure" | "fail" | "cancelled" | "timed_out"
    ) {
        (CI_STATUS_FAILING, 0, 1)
    } else if matches!(status_field.as_str(), "in_progress" | "queued" | "waiting") {
        (CI_STATUS_PENDING, 0, 1)
    } else {
        (CI_STATUS_UNKNOWN, 0, 0)
    }
}

pub fn build_agent_ci_payload(
    agent_name: &str,
    agent_state: &str,
    agent_task: &str,
    active_agents: usize,
    repo: &str,
    branch: &str,
    dirty: bool,
    dirty_files: usize,
    ci_status: &str,
    pr: usize,
    passed: usize,
    total: usize,
) -> String {
    format!(
        r#"{{"type":"agent_ci","agent":{{"name":"{}","state":"{}","task":"{}","detail":"{}","active_agents":{}}},"ci":{{"repo":"{}","branch":"{}","dirty":{},"dirty_files":{},"status":"{}","state":"{}","pr":{},"passed":{},"total":{}}}}}"#,
        json_escape(agent_name),
        json_escape(agent_state),
        json_escape(agent_task),
        json_escape(agent_task),
        active_agents,
        json_escape(repo),
        json_escape(branch),
        dirty,
        dirty_files,
        json_escape(ci_status),
        json_escape(ci_status),
        pr,
        passed,
        total,
    )
}

pub fn serialize_packet(payload: &str) -> String {
    format!("{}\n", payload)
}

pub fn get_github_ci_status(repo_dir: &str) -> (&'static str, usize, usize) {
    let pr_num = get_pr_number(repo_dir);

    if pr_num > 0 {
        if let Ok(output) = Command::new("gh")
            .args([
                "pr",
                "checks",
                &pr_num.to_string(),
                "--json",
                "name,state,bucket",
            ])
            .current_dir(repo_dir)
            .output()
        {
            if output.status.success() {
                let text = String::from_utf8_lossy(&output.stdout);
                return parse_gh_pr_checks(&text);
            }
        }
    }

    if let Ok(output) = Command::new("gh")
        .args(["run", "list", "--limit", "1", "--json", "status,conclusion"])
        .current_dir(repo_dir)
        .output()
    {
        if output.status.success() {
            let text = String::from_utf8_lossy(&output.stdout);
            return parse_gh_run_list(&text);
        }
    }

    (CI_STATUS_NONE, 0, 0)
}

fn get_pr_number(repo_dir: &str) -> usize {
    let output = Command::new("gh")
        .args(["pr", "view", "--json", "number,state"])
        .current_dir(repo_dir)
        .output();

    if let Ok(o) = output {
        if o.status.success() {
            let text = String::from_utf8_lossy(&o.stdout);
            if let Some(num_str) = extract_json_number(&text, "number") {
                return num_str.parse().unwrap_or(0);
            }
        }
    }
    0
}

pub fn get_active_agents() -> (Option<String>, usize) {
    let output = Command::new("pgrep")
        .args(["-fl", "antigravity|claude|agy"])
        .output();

    match output {
        Ok(o) => {
            let text = String::from_utf8_lossy(&o.stdout);
            let filtered: Vec<&str> = text
                .lines()
                .filter(|l| {
                    let l = l.trim();
                    !l.is_empty()
                        && !l.contains("mcp-server")
                        && !l.contains("mcp-remote")
                        && !l.contains("Claude Helper")
                        && !l.contains("grep")
                })
                .collect();
            parse_agent_processes(&filtered.join("\n"))
        }
        Err(_) => (None, 0),
    }
}

pub fn get_companion_payload(repo_dir: &str) -> String {
    let (agent_name, agent_count) = get_active_agents();
    let agent_name_str = agent_name.as_deref().unwrap_or("None");
    let state = if agent_name.is_some() {
        AGENT_STATE_RUNNING
    } else {
        AGENT_STATE_IDLE
    };

    let (branch, dirty, dirty_files) = get_git_status(repo_dir);
    let (ci_status, passed, total) = get_github_ci_status(repo_dir);
    let pr = get_pr_number(repo_dir);
    let repo = std::path::Path::new(repo_dir)
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "unknown".into());

    build_agent_ci_payload(
        agent_name_str,
        state,
        "Monitoring",
        agent_count,
        &repo,
        &branch,
        dirty,
        dirty_files,
        ci_status,
        pr,
        passed,
        total,
    )
}

fn get_git_status(repo_dir: &str) -> (String, bool, usize) {
    let output = Command::new("git")
        .args(["status", "--porcelain", "-b"])
        .current_dir(repo_dir)
        .output();

    match output {
        Ok(o) if o.status.success() => parse_git_status(&String::from_utf8_lossy(&o.stdout)),
        _ => ("main".into(), false, 0),
    }
}

fn json_escape(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
}

fn parse_json_array(json: &str) -> Option<Vec<String>> {
    let trimmed = json.trim();
    if !trimmed.starts_with('[') || !trimmed.ends_with(']') {
        return None;
    }
    let inner = &trimmed[1..trimmed.len() - 1];
    if inner.trim().is_empty() {
        return Some(Vec::new());
    }

    let mut items = Vec::new();
    let mut depth = 0i32;
    let mut start = 0;
    let bytes = inner.as_bytes();
    let mut in_string = false;
    let mut escaped = false;

    for (i, &b) in bytes.iter().enumerate() {
        if escaped {
            escaped = false;
            continue;
        }
        if b == b'\\' {
            escaped = true;
            continue;
        }
        if b == b'"' {
            in_string = !in_string;
            continue;
        }
        if in_string {
            continue;
        }
        match b {
            b'{' | b'[' => depth += 1,
            b'}' | b']' => depth -= 1,
            b',' if depth == 0 => {
                items.push(inner[start..i].trim().to_string());
                start = i + 1;
            }
            _ => {}
        }
    }
    let last = inner[start..].trim();
    if !last.is_empty() {
        items.push(last.to_string());
    }

    Some(items)
}

fn json_str_field(obj: &str, key: &str) -> String {
    let search = format!(r#""{}""#, key);
    if let Some(pos) = obj.find(&search) {
        let rest = &obj[pos + search.len()..];
        if let Some(colon) = rest.find(':') {
            let after = rest[colon + 1..].trim();
            if after.starts_with('"') {
                if let Some(end) = after[1..].find('"') {
                    return after[1..1 + end].to_string();
                }
            }
        }
    }
    String::new()
}

fn extract_json_number(json: &str, key: &str) -> Option<String> {
    let search = format!(r#""{}""#, key);
    if let Some(pos) = json.find(&search) {
        let rest = &json[pos + search.len()..];
        if let Some(colon) = rest.find(':') {
            let after = rest[colon + 1..].trim();
            let num: String = after.chars().take_while(|c| c.is_ascii_digit()).collect();
            if !num.is_empty() {
                return Some(num);
            }
        }
    }
    None
}

#[derive(Debug)]
pub struct CliArgs {
    pub repo: String,
    pub once: bool,
    pub interval: f64,
}

pub fn parse_cli_args(args: &[String]) -> Result<CliArgs, String> {
    let mut repo = ".".to_string();
    let mut once = false;
    let mut interval = 10.0;
    let mut i = 0;

    while i < args.len() {
        match args[i].as_str() {
            "--repo" => {
                i += 1;
                if i >= args.len() {
                    return Err("--repo requires an argument".into());
                }
                repo = args[i].clone();
            }
            "--once" => once = true,
            "--interval" => {
                i += 1;
                if i >= args.len() {
                    return Err("--interval requires an argument".into());
                }
                interval = args[i]
                    .parse()
                    .map_err(|_| format!("invalid interval: {}", args[i]))?;
            }
            "-h" | "--help" => {
                return Err(
                    "Usage: agent_ci_monitor [--repo <dir>] [--once] [--interval <sec>]".into(),
                );
            }
            other => return Err(format!("unexpected argument: {}", other)),
        }
        i += 1;
    }

    Ok(CliArgs {
        repo,
        once,
        interval,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_detect_error_empty() {
        assert!(!detect_agent_error(""));
        assert!(!detect_agent_error("   \n  "));
    }

    #[test]
    fn test_detect_error_status_line() {
        assert!(detect_agent_error("Status: **error**"));
        assert!(detect_agent_error("state: failed"));
        assert!(detect_agent_error("Status: blocked"));
    }

    #[test]
    fn test_detect_error_heading() {
        assert!(detect_agent_error(
            "## Verification Failure\nSomething broke"
        ));
        assert!(detect_agent_error("# Error\nDetails here"));
    }

    #[test]
    fn test_detect_no_false_positive() {
        assert!(!detect_agent_error("0 errors found"));
        assert!(!detect_agent_error("No failed tests"));
        assert!(!detect_agent_error("## Error Handling\nGood patterns"));
        assert!(!detect_agent_error("## Error Recovery\nRecovery steps"));
    }

    #[test]
    fn test_detect_error_prefixed_line() {
        assert!(detect_agent_error("ERROR: Build failed"));
        assert!(detect_agent_error("FATAL: Cannot continue"));
        assert!(detect_agent_error("- BLOCKED: Waiting on PR"));
    }

    #[test]
    fn test_parse_processes_empty() {
        let (name, count) = parse_agent_processes("");
        assert!(name.is_none());
        assert_eq!(count, 0);
    }

    #[test]
    fn test_parse_processes_claude() {
        let (name, count) = parse_agent_processes("12345 claude-code --session abc");
        assert_eq!(name, Some("Claude Code".into()));
        assert_eq!(count, 1);
    }

    #[test]
    fn test_parse_processes_agy() {
        let (name, count) = parse_agent_processes("67890 antigravity delegate task");
        assert_eq!(name, Some("Antigravity".into()));
        assert_eq!(count, 1);
    }

    #[test]
    fn test_parse_processes_teamwork() {
        let input = "12345 claude-code session\n67890 antigravity delegate";
        let (name, count) = parse_agent_processes(input);
        assert_eq!(name, Some("Teamwork".into()));
        assert_eq!(count, 2);
    }

    #[test]
    fn test_parse_processes_filters_grep() {
        let (name, count) = parse_agent_processes("99999 grep claude");
        assert!(name.is_none());
        assert_eq!(count, 0);
    }

    #[test]
    fn test_determine_state_error() {
        assert_eq!(
            determine_agent_state(true, 100.0, 110.0, true),
            AGENT_STATE_ERROR
        );
    }

    #[test]
    fn test_determine_state_idle_no_process() {
        assert_eq!(
            determine_agent_state(false, 100.0, 110.0, false),
            AGENT_STATE_IDLE
        );
    }

    #[test]
    fn test_determine_state_running_fresh() {
        assert_eq!(
            determine_agent_state(true, 100.0, 130.0, false),
            AGENT_STATE_RUNNING
        );
    }

    #[test]
    fn test_determine_state_review() {
        assert_eq!(
            determine_agent_state(true, 100.0, 200.0, false),
            AGENT_STATE_REVIEW
        );
    }

    #[test]
    fn test_determine_state_idle_stale() {
        assert_eq!(
            determine_agent_state(true, 100.0, 500.0, false),
            AGENT_STATE_IDLE
        );
    }

    #[test]
    fn test_determine_state_running_no_mtime() {
        assert_eq!(
            determine_agent_state(true, 0.0, 1000.0, false),
            AGENT_STATE_RUNNING
        );
    }

    #[test]
    fn test_parse_progress_empty() {
        let (task, status) = parse_agent_progress("");
        assert_eq!(task, "Idle");
        assert_eq!(status, "idle");
    }

    #[test]
    fn test_parse_progress_in_progress() {
        let content = "**Current Status:** In Progress\n- [/] Building the widget\n- [ ] Testing";
        let (task, _status) = parse_agent_progress(content);
        assert_eq!(task, "Building the widget");
    }

    #[test]
    fn test_parse_progress_todo_fallback() {
        let content = "**Current Status:** Queued\n- [ ] First task\n- [ ] Second task";
        let (task, _) = parse_agent_progress(content);
        assert_eq!(task, "First task");
    }

    #[test]
    fn test_parse_git_status_clean() {
        let (branch, dirty, count) = parse_git_status("## main...origin/main\n");
        assert_eq!(branch, "main");
        assert!(!dirty);
        assert_eq!(count, 0);
    }

    #[test]
    fn test_parse_git_status_dirty() {
        let input = "## feature/foo...origin/feature/foo\n M src/lib.rs\n?? new.txt\n";
        let (branch, dirty, count) = parse_git_status(input);
        assert_eq!(branch, "feature/foo");
        assert!(dirty);
        assert_eq!(count, 2);
    }

    #[test]
    fn test_parse_git_status_empty() {
        let (branch, dirty, count) = parse_git_status("");
        assert_eq!(branch, "main");
        assert!(!dirty);
        assert_eq!(count, 0);
    }

    #[test]
    fn test_parse_checks_all_pass() {
        let json = r#"[{"name":"CI","state":"SUCCESS","bucket":"pass"},{"name":"Lint","state":"SUCCESS","bucket":"pass"}]"#;
        let (status, passed, total) = parse_gh_pr_checks(json);
        assert_eq!(status, CI_STATUS_PASSING);
        assert_eq!(passed, 2);
        assert_eq!(total, 2);
    }

    #[test]
    fn test_parse_checks_has_failure() {
        let json = r#"[{"name":"CI","state":"SUCCESS","bucket":"pass"},{"name":"Lint","state":"FAILURE","bucket":"fail"}]"#;
        let (status, passed, total) = parse_gh_pr_checks(json);
        assert_eq!(status, CI_STATUS_FAILING);
        assert_eq!(passed, 1);
        assert_eq!(total, 2);
    }

    #[test]
    fn test_parse_checks_pending() {
        let json = r#"[{"name":"CI","state":"IN_PROGRESS","bucket":"pending"}]"#;
        let (status, _, total) = parse_gh_pr_checks(json);
        assert_eq!(status, CI_STATUS_PENDING);
        assert_eq!(total, 1);
    }

    #[test]
    fn test_parse_checks_empty_array() {
        let (status, passed, total) = parse_gh_pr_checks("[]");
        assert_eq!(status, CI_STATUS_NONE);
        assert_eq!(passed, 0);
        assert_eq!(total, 0);
    }

    #[test]
    fn test_parse_checks_empty_string() {
        let (status, _, _) = parse_gh_pr_checks("");
        assert_eq!(status, CI_STATUS_NONE);
    }

    #[test]
    fn test_parse_run_list_success() {
        let json = r#"[{"status":"completed","conclusion":"success"}]"#;
        let (status, passed, total) = parse_gh_run_list(json);
        assert_eq!(status, CI_STATUS_PASSING);
        assert_eq!(passed, 1);
        assert_eq!(total, 1);
    }

    #[test]
    fn test_parse_run_list_failure() {
        let json = r#"[{"status":"completed","conclusion":"failure"}]"#;
        let (status, passed, total) = parse_gh_run_list(json);
        assert_eq!(status, CI_STATUS_FAILING);
        assert_eq!(passed, 0);
        assert_eq!(total, 1);
    }

    #[test]
    fn test_parse_run_list_in_progress() {
        let json = r#"[{"status":"in_progress","conclusion":""}]"#;
        let (status, _, _) = parse_gh_run_list(json);
        assert_eq!(status, CI_STATUS_PENDING);
    }

    #[test]
    fn test_parse_run_list_empty() {
        let (status, _, _) = parse_gh_run_list("");
        assert_eq!(status, CI_STATUS_NONE);
    }

    #[test]
    fn test_build_payload_structure() {
        let payload = build_agent_ci_payload(
            "Claude Code",
            "running",
            "Building widgets",
            1,
            "vitruvian-core",
            "feat/x",
            true,
            3,
            "passing",
            42,
            5,
            5,
        );
        assert!(payload.contains(r#""type":"agent_ci""#));
        assert!(payload.contains(r#""name":"Claude Code""#));
        assert!(payload.contains(r#""state":"running""#));
        assert!(payload.contains(r#""task":"Building widgets""#));
        assert!(payload.contains(r#""repo":"vitruvian-core""#));
        assert!(payload.contains(r#""branch":"feat/x""#));
        assert!(payload.contains(r#""dirty":true"#));
        assert!(payload.contains(r#""pr":42"#));
        assert!(payload.contains(r#""passed":5"#));
        assert!(payload.contains(r#""total":5"#));
    }

    #[test]
    fn test_serialize_packet_newline() {
        let p = serialize_packet(r#"{"type":"test"}"#);
        assert!(p.ends_with('\n'));
        assert_eq!(p, "{\"type\":\"test\"}\n");
    }

    #[test]
    fn test_cli_args_once() {
        let args = vec!["--once".to_string()];
        let parsed = parse_cli_args(&args).unwrap();
        assert!(parsed.once);
        assert_eq!(parsed.repo, ".");
    }

    #[test]
    fn test_cli_args_full() {
        let args = vec![
            "--repo".to_string(),
            "/my/repo".to_string(),
            "--interval".to_string(),
            "5".to_string(),
            "--once".to_string(),
        ];
        let parsed = parse_cli_args(&args).unwrap();
        assert_eq!(parsed.repo, "/my/repo");
        assert!(parsed.once);
        assert_eq!(parsed.interval, 5.0);
    }

    #[test]
    fn test_json_escape() {
        assert_eq!(json_escape("hello"), "hello");
        assert_eq!(json_escape(r#"he"llo"#), r#"he\"llo"#);
        assert_eq!(json_escape("line\nnewline"), "line\\nnewline");
    }
}
