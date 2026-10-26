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

//! Milestone 3: AI Agent & CI/CD Pipeline Deck verification suite.
//! Migrated from `tests/test_agent_ci.py`.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use agent_ci_monitor::{
    build_agent_ci_payload, determine_agent_state, parse_agent_processes, parse_agent_progress,
    parse_gh_pr_checks, parse_gh_run_list, parse_git_status, serialize_packet, AGENT_STATE_ERROR,
    AGENT_STATE_IDLE, AGENT_STATE_REVIEW, AGENT_STATE_RUNNING, CI_STATUS_FAILING, CI_STATUS_NONE,
    CI_STATUS_PASSING, CI_STATUS_PENDING, CI_STATUS_UNKNOWN,
};

use crate::{json_extract_bool, json_extract_i64, json_extract_str};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DispatchedAction {
    RunChecks { cwd: String },
    OpenPr { pr: u64, cwd: String },
    OpenRepo { cwd: String },
    RefreshOnly,
    FocusAgent,
    Ignored,
}

#[derive(Clone, Debug)]
pub struct MockMonitorState {
    pub workspace_dir: String,
    pub refresh_count: usize,
    pub active_pr: u64,
}

impl Default for MockMonitorState {
    fn default() -> Self {
        Self {
            workspace_dir: "/test/repo/vitruvian-core".to_string(),
            refresh_count: 0,
            active_pr: 0,
        }
    }
}

/// Simulates `handle_esp_command` from `mac_stats_daemon` for ESP32 touch button actions.
pub fn dispatch_esp_command(line: &str, monitor: &mut MockMonitorState) -> DispatchedAction {
    let trimmed = line.trim();
    if !trimmed.starts_with('{') || !trimmed.ends_with('}') {
        return DispatchedAction::Ignored;
    }
    let cmd = json_extract_str(trimmed, "cmd")
        .or_else(|| json_extract_str(trimmed, "action"))
        .unwrap_or_default();

    match cmd.as_str() {
        "run_checks" => {
            monitor.refresh_count += 1;
            DispatchedAction::RunChecks {
                cwd: monitor.workspace_dir.clone(),
            }
        }
        "open_pr" | "open_ci" => {
            if monitor.active_pr > 0 {
                DispatchedAction::OpenPr {
                    pr: monitor.active_pr,
                    cwd: monitor.workspace_dir.clone(),
                }
            } else {
                DispatchedAction::OpenRepo {
                    cwd: monitor.workspace_dir.clone(),
                }
            }
        }
        "refresh" | "refresh_ci" => {
            monitor.refresh_count += 1;
            DispatchedAction::RefreshOnly
        }
        "focus_agent" => DispatchedAction::FocusAgent,
        _ => DispatchedAction::Ignored,
    }
}

/// Thread-safe background monitor model matching `AgentCIMonitor`.
pub struct ThreadedAgentCIMonitor {
    payload: Arc<Mutex<String>>,
    refresh_event: Arc<AtomicBool>,
    running: Arc<AtomicBool>,
    worker: Option<thread::JoinHandle<()>>,
}

impl ThreadedAgentCIMonitor {
    pub fn new() -> Self {
        let initial = build_agent_ci_payload(
            "None",
            AGENT_STATE_IDLE,
            "Idle",
            0,
            "vitruvian-core",
            "main",
            false,
            0,
            CI_STATUS_PASSING,
            0,
            1,
            1,
        );
        Self {
            payload: Arc::new(Mutex::new(initial)),
            refresh_event: Arc::new(AtomicBool::new(false)),
            running: Arc::new(AtomicBool::new(false)),
            worker: None,
        }
    }

    pub fn start(&mut self, poll_interval_ms: u64) {
        self.running.store(true, Ordering::SeqCst);
        let payload = Arc::clone(&self.payload);
        let running = Arc::clone(&self.running);
        let refresh = Arc::clone(&self.refresh_event);

        self.worker = Some(thread::spawn(move || {
            while running.load(Ordering::SeqCst) {
                let updated = build_agent_ci_payload(
                    "MockAgent",
                    AGENT_STATE_IDLE,
                    "Idle",
                    0,
                    "repo",
                    "main",
                    false,
                    0,
                    CI_STATUS_PASSING,
                    0,
                    1,
                    1,
                );
                if let Ok(mut guard) = payload.lock() {
                    *guard = updated;
                }
                let _ = refresh.load(Ordering::SeqCst);
                thread::sleep(Duration::from_millis(poll_interval_ms.max(1)));
            }
        }));
    }

    pub fn trigger_refresh(&self) {
        self.refresh_event.store(true, Ordering::SeqCst);
    }

    pub fn is_refresh_set(&self) -> bool {
        self.refresh_event.load(Ordering::SeqCst)
    }

    pub fn is_alive(&self) -> bool {
        self.running.load(Ordering::SeqCst) && self.worker.is_some()
    }

    pub fn get_payload(&self) -> String {
        self.payload.lock().unwrap().clone()
    }

    pub fn stop(&mut self) {
        self.running.store(false, Ordering::SeqCst);
        if let Some(handle) = self.worker.take() {
            let _ = handle.join();
        }
    }
}

impl Default for ThreadedAgentCIMonitor {
    fn default() -> Self {
        Self::new()
    }
}

pub fn run_suite() -> usize {
    let mut checks = 0usize;

    // 1. Agent process detection
    let (name, count) = parse_agent_processes("12345 /opt/homebrew/bin/python3 -m antigravity\n");
    assert_eq!(name.as_deref(), Some("Antigravity"));
    assert_eq!(count, 1);
    checks += 1;

    let (name, count) = parse_agent_processes("54321 /usr/local/bin/agy\n");
    assert_eq!(name.as_deref(), Some("Antigravity"));
    assert_eq!(count, 1);
    checks += 1;

    let (name, count) = parse_agent_processes("99999 /Users/user/.npm-global/bin/claude\n");
    assert_eq!(name.as_deref(), Some("Claude Code"));
    assert_eq!(count, 1);
    checks += 1;

    let (name, count) = parse_agent_processes(
        "10001 /usr/local/bin/antigravity\n10002 /usr/local/bin/antigravity --worker\n10003 /usr/local/bin/antigravity --worker\n",
    );
    assert_eq!(name.as_deref(), Some("Antigravity"));
    assert_eq!(count, 3);
    checks += 1;

    let (name, count) = parse_agent_processes(
        "12300 /System/Library/CoreServices/Finder.app/Contents/MacOS/Finder\n",
    );
    assert!(name.is_none());
    assert_eq!(count, 0);
    checks += 1;

    let (name, count) = parse_agent_processes("");
    assert!(name.is_none());
    assert_eq!(count, 0);
    checks += 1;

    let (name, count) = parse_agent_processes("44444 pgrep -fl antigravity\n");
    assert!(name.is_none());
    assert_eq!(count, 0);
    checks += 1;

    // 2. Agent state transitions
    assert_eq!(
        determine_agent_state(true, 1000.0, 1000.0, true),
        AGENT_STATE_ERROR
    );
    assert_eq!(
        determine_agent_state(false, 1000.0, 1000.0, false),
        AGENT_STATE_IDLE
    );
    assert_eq!(
        determine_agent_state(true, 985.0, 1000.0, false),
        AGENT_STATE_RUNNING
    );
    assert_eq!(
        determine_agent_state(true, 910.0, 1000.0, false),
        AGENT_STATE_REVIEW
    );
    assert_eq!(
        determine_agent_state(true, 650.0, 1000.0, false),
        AGENT_STATE_IDLE
    );
    assert_eq!(
        determine_agent_state(true, 0.0, 1000.0, false),
        AGENT_STATE_RUNNING
    );
    checks += 6;

    // 3. Progress parsing
    let (task, status) = parse_agent_progress(
        "# Progress\n**Current Status:** In Progress\n\n## Tasks\n- [x] Task 1 done\n- [/] Implement Smart Deck UI\n- [ ] Task 3 planned\n",
    );
    assert_eq!(task, "Implement Smart Deck UI");
    assert_eq!(status, "In Progress");
    checks += 1;

    let (task, _) = parse_agent_progress(
        "# Progress\n**Current Status:** Working\n\n- [x] Initial setup\n- [ ] Build ArduinoJson Deserializer\n",
    );
    assert_eq!(task, "Build ArduinoJson Deserializer");
    checks += 1;

    let (task, status) = parse_agent_progress("");
    assert_eq!(task, "Idle");
    assert_eq!(status, "idle");
    checks += 1;

    // 4. Git status parsing
    let (branch, dirty, count) =
        parse_git_status("## feat/mac-controller...origin/feat/mac-controller\n");
    assert_eq!(branch, "feat/mac-controller");
    assert!(!dirty);
    assert_eq!(count, 0);
    checks += 1;

    let (branch, dirty, count) = parse_git_status(
        "## main...origin/main [ahead 2, behind 1]\n M mac-controller/src/main.cpp\n M mac-controller/src/ui.cpp\n?? mac-controller/tests/test_agent_ci.py\n",
    );
    assert_eq!(branch, "main");
    assert!(dirty);
    assert_eq!(count, 3);
    checks += 1;

    let (branch, dirty, count) = parse_git_status("## HEAD (no branch)\n");
    assert_eq!(branch, "HEAD");
    assert!(!dirty);
    assert_eq!(count, 0);
    checks += 1;

    let (branch, dirty, count) = parse_git_status("## Initial commit on main\n");
    assert_eq!(branch, "main");
    assert!(!dirty);
    assert_eq!(count, 0);
    checks += 1;

    let (branch, dirty, count) = parse_git_status("");
    assert_eq!(branch, "main");
    assert!(!dirty);
    assert_eq!(count, 0);
    checks += 1;

    // 5. GitHub checks & run list parsing
    let (st, passed, total) = parse_gh_pr_checks(
        r#"[{"name":"build","state":"SUCCESS","bucket":"pass"},{"name":"test","state":"SUCCESS","bucket":"pass"},{"name":"lint","state":"SUCCESS","bucket":"pass"}]"#,
    );
    assert_eq!(st, CI_STATUS_PASSING);
    assert_eq!(passed, 3);
    assert_eq!(total, 3);
    checks += 1;

    let (st, passed, total) = parse_gh_pr_checks(
        r#"[{"name":"build","state":"SUCCESS","bucket":"pass"},{"name":"test","state":"FAILURE","bucket":"fail"},{"name":"lint","state":"SUCCESS","bucket":"pass"}]"#,
    );
    assert_eq!(st, CI_STATUS_FAILING);
    assert_eq!(passed, 2);
    assert_eq!(total, 3);
    checks += 1;

    let (st, passed, total) = parse_gh_pr_checks(
        r#"[{"name":"build","state":"SUCCESS","bucket":"pass"},{"name":"test","state":"PENDING","bucket":"pending"}]"#,
    );
    assert_eq!(st, CI_STATUS_PENDING);
    assert_eq!(passed, 1);
    assert_eq!(total, 2);
    checks += 1;

    let (st, _, total) = parse_gh_pr_checks("[]");
    assert_eq!(st, CI_STATUS_NONE);
    assert_eq!(total, 0);
    checks += 1;

    let (st, _, _) = parse_gh_pr_checks("{not valid json}");
    assert_eq!(st, CI_STATUS_UNKNOWN);
    checks += 1;

    let (st, _, _) = parse_gh_run_list(r#"[{"status":"completed","conclusion":"success"}]"#);
    assert_eq!(st, CI_STATUS_PASSING);
    let (st, _, _) = parse_gh_run_list(r#"[{"status":"completed","conclusion":"failure"}]"#);
    assert_eq!(st, CI_STATUS_FAILING);
    let (st, _, _) = parse_gh_run_list(r#"[{"status":"in_progress","conclusion":""}]"#);
    assert_eq!(st, CI_STATUS_PENDING);
    checks += 3;

    // 6. Wire protocol conformance
    let payload = build_agent_ci_payload(
        "Antigravity",
        "running",
        "Survey specs R1-R5",
        3,
        "vitruvian-core",
        "main",
        true,
        2,
        "passing",
        2177,
        54,
        54,
    );
    let packet = serialize_packet(&payload);
    assert!(packet.ends_with('\n'));
    assert_eq!(packet.matches('\n').count(), 1);
    assert!(packet.len() < 512);
    assert_eq!(
        json_extract_str(&packet, "type").as_deref(),
        Some("agent_ci")
    );
    assert_eq!(
        json_extract_str(&packet, "name").as_deref(),
        Some("Antigravity")
    );
    assert_eq!(
        json_extract_str(&packet, "task").as_deref(),
        Some("Survey specs R1-R5")
    );
    assert_eq!(json_extract_i64(&packet, "active_agents"), Some(3));
    assert_eq!(json_extract_i64(&packet, "passed"), Some(54));
    assert_eq!(json_extract_i64(&packet, "total"), Some(54));
    assert_eq!(json_extract_bool(&packet, "dirty"), Some(true));
    checks += 4;

    // 7. Host command dispatcher
    let mut mon = MockMonitorState::default();
    assert_eq!(
        dispatch_esp_command("{\"cmd\":\"run_checks\"}\n", &mut mon),
        DispatchedAction::RunChecks {
            cwd: "/test/repo/vitruvian-core".to_string()
        }
    );
    assert_eq!(mon.refresh_count, 1);

    mon.active_pr = 42;
    assert_eq!(
        dispatch_esp_command("{\"cmd\":\"open_pr\"}\n", &mut mon),
        DispatchedAction::OpenPr {
            pr: 42,
            cwd: "/test/repo/vitruvian-core".to_string()
        }
    );

    mon.active_pr = 0;
    assert_eq!(
        dispatch_esp_command("{\"cmd\":\"open_pr\"}\n", &mut mon),
        DispatchedAction::OpenRepo {
            cwd: "/test/repo/vitruvian-core".to_string()
        }
    );
    checks += 3;

    // 8. Threaded monitor lifecycle
    let mut threaded = ThreadedAgentCIMonitor::new();
    assert!(threaded.get_payload().contains("\"type\":\"agent_ci\""));
    threaded.start(5);
    assert!(threaded.is_alive());
    threaded.trigger_refresh();
    assert!(threaded.is_refresh_set());
    threaded.stop();
    assert!(!threaded.is_alive());
    checks += 3;

    checks
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_detect_antigravity() {
        let (name, count) =
            parse_agent_processes("12345 /opt/homebrew/bin/python3 -m antigravity\n");
        assert_eq!(name.as_deref(), Some("Antigravity"));
        assert_eq!(count, 1);
    }

    #[test]
    fn test_detect_agy_alias() {
        let (name, count) = parse_agent_processes("54321 /usr/local/bin/agy\n");
        assert_eq!(name.as_deref(), Some("Antigravity"));
        assert_eq!(count, 1);
    }

    #[test]
    fn test_detect_claude_code() {
        let (name, count) = parse_agent_processes("99999 /Users/user/.npm-global/bin/claude\n");
        assert_eq!(name.as_deref(), Some("Claude Code"));
        assert_eq!(count, 1);
    }

    #[test]
    fn test_multiple_subagents() {
        let pgrep_out = "10001 /usr/local/bin/antigravity\n\
                         10002 /usr/local/bin/antigravity --worker\n\
                         10003 /usr/local/bin/antigravity --worker\n";
        let (name, count) = parse_agent_processes(pgrep_out);
        assert_eq!(name.as_deref(), Some("Antigravity"));
        assert_eq!(count, 3);
    }

    #[test]
    fn test_no_agent_process_and_empty_and_grep_self() {
        let (name, count) = parse_agent_processes(
            "12300 /System/Library/CoreServices/Finder.app/Contents/MacOS/Finder\n",
        );
        assert!(name.is_none());
        assert_eq!(count, 0);

        let (name2, count2) = parse_agent_processes("");
        assert!(name2.is_none());
        assert_eq!(count2, 0);

        let (name3, count3) = parse_agent_processes("44444 pgrep -fl antigravity\n");
        assert!(name3.is_none());
        assert_eq!(count3, 0);
    }

    #[test]
    fn test_agent_state_transitions() {
        assert_eq!(
            determine_agent_state(true, 1000.0, 1000.0, true),
            AGENT_STATE_ERROR
        );
        assert_eq!(
            determine_agent_state(false, 1000.0, 1000.0, false),
            AGENT_STATE_IDLE
        );
        assert_eq!(
            determine_agent_state(true, 985.0, 1000.0, false),
            AGENT_STATE_RUNNING
        );
        assert_eq!(
            determine_agent_state(true, 910.0, 1000.0, false),
            AGENT_STATE_REVIEW
        );
        assert_eq!(
            determine_agent_state(true, 650.0, 1000.0, false),
            AGENT_STATE_IDLE
        );
        assert_eq!(
            determine_agent_state(true, 0.0, 1000.0, false),
            AGENT_STATE_RUNNING
        );
    }

    #[test]
    fn test_agent_progress_parsing() {
        let content = "# Progress\n\
                       **Current Status:** In Progress\n\n\
                       ## Tasks\n\
                       - [x] Task 1 done\n\
                       - [/] Implement Smart Deck UI\n\
                       - [ ] Task 3 planned\n";
        let (task, status) = parse_agent_progress(content);
        assert_eq!(task, "Implement Smart Deck UI");
        assert_eq!(status, "In Progress");

        let content2 = "# Progress\n\
                        **Current Status:** Working\n\n\
                        - [x] Initial setup\n\
                        - [ ] Build ArduinoJson Deserializer\n";
        let (task2, _) = parse_agent_progress(content2);
        assert_eq!(task2, "Build ArduinoJson Deserializer");

        let (task3, status3) = parse_agent_progress("");
        assert_eq!(task3, "Idle");
        assert_eq!(status3, "idle");
    }

    #[test]
    fn test_git_status_parsing() {
        let (branch, dirty, count) =
            parse_git_status("## feat/mac-controller...origin/feat/mac-controller\n");
        assert_eq!(branch, "feat/mac-controller");
        assert!(!dirty);
        assert_eq!(count, 0);

        let out = "## main...origin/main [ahead 2, behind 1]\n\
                    M mac-controller/src/main.cpp\n\
                    M mac-controller/src/ui.cpp\n\
                   ?? mac-controller/tests/test_agent_ci.py\n";
        let (branch, dirty, count) = parse_git_status(out);
        assert_eq!(branch, "main");
        assert!(dirty);
        assert_eq!(count, 3);

        let (branch, dirty, count) = parse_git_status("## HEAD (no branch)\n");
        assert_eq!(branch, "HEAD");
        assert!(!dirty);
        assert_eq!(count, 0);

        let (branch, dirty, count) = parse_git_status("## Initial commit on main\n");
        assert_eq!(branch, "main");
        assert!(!dirty);
        assert_eq!(count, 0);

        let (branch, dirty, count) = parse_git_status("");
        assert_eq!(branch, "main");
        assert!(!dirty);
        assert_eq!(count, 0);
    }

    #[test]
    fn test_github_checks_and_run_list_parsing() {
        let (status, passed, total) = parse_gh_pr_checks(
            r#"[{"name":"build","state":"SUCCESS","bucket":"pass"},{"name":"test","state":"SUCCESS","bucket":"pass"},{"name":"lint","state":"SUCCESS","bucket":"pass"}]"#,
        );
        assert_eq!(status, CI_STATUS_PASSING);
        assert_eq!(passed, 3);
        assert_eq!(total, 3);

        let (status, passed, total) = parse_gh_pr_checks(
            r#"[{"name":"build","state":"SUCCESS","bucket":"pass"},{"name":"test","state":"FAILURE","bucket":"fail"},{"name":"lint","state":"SUCCESS","bucket":"pass"}]"#,
        );
        assert_eq!(status, CI_STATUS_FAILING);
        assert_eq!(passed, 2);
        assert_eq!(total, 3);

        let (status, passed, total) = parse_gh_pr_checks(
            r#"[{"name":"build","state":"SUCCESS","bucket":"pass"},{"name":"test","state":"PENDING","bucket":"pending"}]"#,
        );
        assert_eq!(status, CI_STATUS_PENDING);
        assert_eq!(passed, 1);
        assert_eq!(total, 2);

        let (status, _, total) = parse_gh_pr_checks("[]");
        assert_eq!(status, CI_STATUS_NONE);
        assert_eq!(total, 0);

        let (status, _, _) = parse_gh_pr_checks("{not valid json}");
        assert_eq!(status, CI_STATUS_UNKNOWN);

        assert_eq!(
            parse_gh_run_list(r#"[{"status":"completed","conclusion":"success"}]"#).0,
            CI_STATUS_PASSING
        );
        assert_eq!(
            parse_gh_run_list(r#"[{"status":"completed","conclusion":"failure"}]"#).0,
            CI_STATUS_FAILING
        );
        assert_eq!(
            parse_gh_run_list(r#"[{"status":"in_progress","conclusion":""}]"#).0,
            CI_STATUS_PENDING
        );
    }

    #[test]
    fn test_wire_protocol_conformance_and_partial_payloads() {
        let payload = build_agent_ci_payload(
            "Antigravity",
            "running",
            "Survey specs R1-R5",
            3,
            "vitruvian-core",
            "main",
            true,
            2,
            "passing",
            2177,
            54,
            54,
        );
        let packet = serialize_packet(&payload);
        assert!(packet.ends_with('\n'));
        assert_eq!(packet.matches('\n').count(), 1);
        assert!(packet.len() < 512);

        let trimmed = packet.trim();
        assert_eq!(
            json_extract_str(trimmed, "type").as_deref(),
            Some("agent_ci")
        );
        assert_eq!(
            json_extract_str(trimmed, "name").as_deref(),
            Some("Antigravity")
        );
        assert_eq!(
            json_extract_str(trimmed, "state").as_deref(),
            Some("running")
        );
        assert_eq!(
            json_extract_str(trimmed, "task").as_deref(),
            Some("Survey specs R1-R5")
        );
        assert_eq!(json_extract_i64(trimmed, "active_agents"), Some(3));
        assert_eq!(
            json_extract_str(trimmed, "repo").as_deref(),
            Some("vitruvian-core")
        );
        assert_eq!(json_extract_str(trimmed, "branch").as_deref(), Some("main"));
        assert_eq!(
            json_extract_str(trimmed, "status").as_deref(),
            Some("passing")
        );
        assert_eq!(json_extract_i64(trimmed, "passed"), Some(54));
        assert_eq!(json_extract_i64(trimmed, "total"), Some(54));
        assert_eq!(json_extract_bool(trimmed, "dirty"), Some(true));

        // Partial/null resilience
        let partial = r#"{"type":"agent_ci","agent":null,"ci":{}}"#;
        let a_name = json_extract_str(partial, "name").unwrap_or_else(|| "Agent".to_string());
        let c_status = json_extract_str(partial, "status").unwrap_or_else(|| "unknown".to_string());
        assert_eq!(a_name, "Agent");
        assert_eq!(c_status, "unknown");
    }

    #[test]
    fn test_host_command_dispatcher() {
        let mut mon = MockMonitorState::default();
        assert_eq!(
            dispatch_esp_command("{\"cmd\":\"run_checks\"}\n", &mut mon),
            DispatchedAction::RunChecks {
                cwd: "/test/repo/vitruvian-core".to_string()
            }
        );
        assert_eq!(mon.refresh_count, 1);

        mon.active_pr = 42;
        assert_eq!(
            dispatch_esp_command("{\"cmd\":\"open_pr\"}\n", &mut mon),
            DispatchedAction::OpenPr {
                pr: 42,
                cwd: "/test/repo/vitruvian-core".to_string()
            }
        );

        mon.active_pr = 0;
        assert_eq!(
            dispatch_esp_command("{\"cmd\":\"open_pr\"}\n", &mut mon),
            DispatchedAction::OpenRepo {
                cwd: "/test/repo/vitruvian-core".to_string()
            }
        );

        assert_eq!(
            dispatch_esp_command("{\"cmd\":\"refresh\"}\n", &mut mon),
            DispatchedAction::RefreshOnly
        );
        assert_eq!(mon.refresh_count, 2);

        assert_eq!(
            dispatch_esp_command("{\"action\":\"refresh_ci\"}\n", &mut mon),
            DispatchedAction::RefreshOnly
        );
        assert_eq!(mon.refresh_count, 3);

        mon.active_pr = 10;
        assert_eq!(
            dispatch_esp_command("{\"action\":\"open_ci\"}\n", &mut mon),
            DispatchedAction::OpenPr {
                pr: 10,
                cwd: "/test/repo/vitruvian-core".to_string()
            }
        );

        assert_eq!(
            dispatch_esp_command("{\"cmd\":\"focus_agent\"}\n", &mut mon),
            DispatchedAction::FocusAgent
        );

        assert_eq!(
            dispatch_esp_command("not-json-payload\n", &mut mon),
            DispatchedAction::Ignored
        );
        assert_eq!(
            dispatch_esp_command("", &mut mon),
            DispatchedAction::Ignored
        );
        assert_eq!(
            dispatch_esp_command("{}\n", &mut mon),
            DispatchedAction::Ignored
        );
        assert_eq!(
            dispatch_esp_command("{\"cmd\":\"some_unhandled_action\"}\n", &mut mon),
            DispatchedAction::Ignored
        );
    }

    #[test]
    fn test_agent_ci_monitor_thread() {
        let mut m = ThreadedAgentCIMonitor::new();
        let p = m.get_payload();
        assert_eq!(json_extract_str(&p, "type").as_deref(), Some("agent_ci"));
        m.start(10);
        assert!(m.is_alive());
        m.trigger_refresh();
        assert!(m.is_refresh_set());
        m.stop();
        assert!(!m.is_alive());
    }
}
