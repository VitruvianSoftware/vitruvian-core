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

//! Empirical Challenger Adversarial Stress Suite for Milestone 3 (AI Agent & CI/CD Pipeline Deck).
//! Migrated from `tests/test_challenger_m3.py`.

use std::sync::{Arc, Mutex};
use std::thread;

use agent_ci_monitor::{
    build_agent_ci_payload, detect_agent_error, determine_agent_state, parse_agent_processes,
    parse_agent_progress, parse_gh_pr_checks, parse_gh_run_list, parse_git_status,
    AGENT_STATE_IDLE, AGENT_STATE_REVIEW, AGENT_STATE_RUNNING, CI_STATUS_NONE, CI_STATUS_PASSING,
    CI_STATUS_UNKNOWN,
};

#[derive(Clone, Debug)]
pub struct AgentProgressEntry {
    pub name: String,
    pub mtime: f64,
    pub content: Vec<u8>,
}

/// Simulates `AgentCIMonitor.poll_agent` with bounded 2048-byte read, UTF-8 lossy recovery,
/// MCP/Claude-Helper noise filtering, 48-char task truncation, and deterministic mtime selection.
pub fn poll_agent_from_entries(
    pgrep_output: Option<&str>,
    entries: &[AgentProgressEntry],
    now: f64,
) -> (String, &'static str, String, usize) {
    let (proc_name, active_count) = match pgrep_output {
        Some(raw) => {
            let filtered: Vec<&str> = raw
                .lines()
                .filter(|l| {
                    let t = l.trim();
                    !t.is_empty()
                        && !t.contains("mcp-server")
                        && !t.contains("mcp-remote")
                        && !t.contains("Claude Helper")
                        && !t.contains("grep")
                })
                .collect();
            parse_agent_processes(&filtered.join("\n"))
        }
        None => (None, 0),
    };

    let process_running = proc_name.is_some();
    let name = proc_name.unwrap_or_else(|| "None".to_string());

    // Deterministic evaluation by highest mtime (Bug E remediation)
    let newest = entries.iter().max_by(|a, b| {
        a.mtime
            .partial_cmp(&b.mtime)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    if let Some(entry) = newest {
        let bounded = if entry.content.len() > 2048 {
            &entry.content[..2048]
        } else {
            &entry.content[..]
        };
        let text = String::from_utf8_lossy(bounded);
        let has_error = detect_agent_error(&text);
        let (raw_task, _) = parse_agent_progress(&text);
        let task = if raw_task == "Idle" {
            "Ready".to_string()
        } else if raw_task.chars().count() > 48 {
            raw_task.chars().take(48).collect()
        } else {
            raw_task
        };
        let state = determine_agent_state(process_running, entry.mtime, now, has_error);
        (name, state, task, active_count)
    } else {
        let state = determine_agent_state(process_running, 0.0, now, false);
        (name, state, "Ready".to_string(), active_count)
    }
}

/// Safe coercion helper for `build_agent_ci_payload` when inputs come from untyped strings (Bug C).
pub fn parse_safe_usize(val: &str) -> usize {
    val.trim().parse::<usize>().unwrap_or(0)
}

pub fn run_suite() -> usize {
    let mut checks = 0usize;

    // 1. Mixed multiple agent processes -> Teamwork
    let pgrep_output = "101 /usr/local/bin/antigravity --worker\n\
                        102 /usr/local/bin/antigravity --worker\n\
                        103 /opt/homebrew/bin/claude\n\
                        104 /opt/homebrew/bin/claude --print\n\
                        105 /usr/local/bin/agy\n";
    let (name, count) = parse_agent_processes(pgrep_output);
    assert_eq!(name.as_deref(), Some("Teamwork"));
    assert_eq!(count, 5);
    checks += 1;

    // 2. Noise and MCP filtering
    let noisy_pgrep = "201 node /Users/user/.npm/bin/mcp-server-git\n\
                       202 node /Users/user/.npm/bin/mcp-remote\n\
                       203 /Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app\n\
                       204 grep -i antigravity\n\
                       205 pgrep -fl claude\n\
                       206 /opt/homebrew/bin/python3 -m antigravity\n";
    let (res_name, _, _, res_count) = poll_agent_from_entries(Some(noisy_pgrep), &[], 1000.0);
    assert_eq!(res_name, "Antigravity");
    assert_eq!(res_count, 1);

    let (raw_name, raw_count) = parse_agent_processes(noisy_pgrep);
    assert_eq!(raw_name.as_deref(), Some("Teamwork"));
    assert_eq!(raw_count, 2);
    checks += 2;

    // 3. Case insensitivity and timeout fallback
    let (name, count) = parse_agent_processes("   999    /bin/CLAUDE-CODE   --verbose   \n");
    assert_eq!(name.as_deref(), Some("Claude Code"));
    assert_eq!(count, 1);

    let (err_name, _, _, err_count) = poll_agent_from_entries(None, &[], 1000.0);
    assert_eq!(err_name, "None");
    assert_eq!(err_count, 0);
    checks += 2;

    // 4. Corrupt binary & massive bounded progress.md
    let binary_entry = AgentProgressEntry {
        name: "corrupt_agent".to_string(),
        mtime: 995.0,
        content: b"\x00\xff\xfe\x80\x01\x02\x03Some text\n- [/] Active binary task\n\xff\xfe"
            .to_vec(),
    };
    let (b_name, b_state, b_task, _) =
        poll_agent_from_entries(Some("123 /bin/antigravity\n"), &[binary_entry], 1000.0);
    assert_eq!(b_name, "Antigravity");
    assert!(b_state == AGENT_STATE_RUNNING || b_state == AGENT_STATE_REVIEW);
    assert_eq!(b_task, "Active binary task");

    let mut huge_bytes = b"- [/] Fast parsed task\n".to_vec();
    huge_bytes.resize(256 * 1024, b'A');
    let huge_entry = AgentProgressEntry {
        name: "large_agent".to_string(),
        mtime: 995.0,
        content: huge_bytes,
    };
    let (_, _, h_task, _) =
        poll_agent_from_entries(Some("123 /bin/antigravity\n"), &[huge_entry], 1000.0);
    assert_eq!(h_task, "Fast parsed task");

    let long_task = format!("- [/] {}", "A".repeat(100));
    let long_entry = AgentProgressEntry {
        name: "long_task".to_string(),
        mtime: 995.0,
        content: long_task.into_bytes(),
    };
    let (_, _, trunc_task, _) = poll_agent_from_entries(Some(""), &[long_entry], 1000.0);
    assert_eq!(trunc_task.len(), 48);
    assert_eq!(trunc_task, "A".repeat(48));
    checks += 3;

    // 5. Lifecycle boundary timing & future clock skew
    let now = 1000.0;
    assert_eq!(
        determine_agent_state(true, now - 44.9, now, false),
        AGENT_STATE_RUNNING
    );
    assert_eq!(
        determine_agent_state(true, now - 45.1, now, false),
        AGENT_STATE_REVIEW
    );
    assert_eq!(
        determine_agent_state(true, now - 299.9, now, false),
        AGENT_STATE_REVIEW
    );
    assert_eq!(
        determine_agent_state(true, now - 300.1, now, false),
        AGENT_STATE_IDLE
    );
    assert_eq!(
        determine_agent_state(true, now + 500.0, now, false),
        AGENT_STATE_RUNNING
    );
    assert_eq!(
        determine_agent_state(true, -10.0, now, false),
        AGENT_STATE_RUNNING
    );
    checks += 6;

    // 6. Git status detached HEAD variants & massive dirty tree
    assert_eq!(
        parse_git_status("## HEAD (no branch)\n"),
        ("HEAD".to_string(), false, 0)
    );
    assert_eq!(
        parse_git_status("## HEAD (no branch)\n M src/main.cpp\n?? newfile.py\n"),
        ("HEAD".to_string(), true, 2)
    );
    assert_eq!(
        parse_git_status("## HEAD (detached at 7a8b9c0)\n").0,
        "HEAD"
    );
    assert_eq!(
        parse_git_status("## HEAD (detached from v1.2.0)\n").0,
        "HEAD"
    );
    assert_eq!(
        parse_git_status("## Initial commit on feature-init\n").0,
        "feature-init"
    );
    assert_eq!(parse_git_status("## No commits yet on dev\n").0, "dev");

    let mut dirty_lines = String::from("## main...origin/main\n");
    for i in 0..1000 {
        dirty_lines.push_str(&format!(" M file_{}.py\n", i));
    }
    let (b, d, c) = parse_git_status(&dirty_lines);
    assert_eq!(b, "main");
    assert!(d);
    assert_eq!(c, 1000);
    checks += 7;

    // 7. Skipped/neutral checks & Empirical Bug Reproductions (Bugs A-E)
    let (st, p, t) = parse_gh_pr_checks(
        r#"[{"name":"build","state":"SUCCESS","bucket":"pass"},{"name":"optional-lint","state":"SKIPPED","bucket":"skipping"},{"name":"deploy-preview","state":"NEUTRAL","bucket":"neutral"}]"#,
    );
    assert_eq!(st, CI_STATUS_PASSING);
    assert_eq!(p, 1);
    assert_eq!(t, 3);

    let (st, p, t) = parse_gh_pr_checks(
        r#"[{"name":"optional-1","state":"SKIPPED","bucket":"skipping"},{"name":"optional-2","state":"SKIPPED","bucket":"skipping"}]"#,
    );
    assert_eq!(st, CI_STATUS_UNKNOWN);
    assert_eq!(p, 0);
    assert_eq!(t, 2);

    assert_eq!(parse_gh_pr_checks("").0, CI_STATUS_NONE);
    assert_eq!(parse_gh_pr_checks("{not-valid-json").0, CI_STATUS_UNKNOWN);
    assert_eq!(
        parse_gh_pr_checks(r#"{"error":"API rate limit exceeded"}"#).0,
        CI_STATUS_UNKNOWN
    );

    // Bug A: [null] and [123]
    assert_eq!(parse_gh_run_list("[null]").0, CI_STATUS_UNKNOWN);
    assert_eq!(parse_gh_run_list("[123]").0, CI_STATUS_UNKNOWN);

    // Bug B: branch names with dots
    assert_eq!(
        parse_git_status("## release/v1.0.0...origin/release/v1.0.0\n").0,
        "release/v1.0.0"
    );
    assert_eq!(parse_git_status("## feat.v2\n").0, "feat.v2");

    // Bug C: non-int coercion
    assert_eq!(parse_safe_usize("two"), 0);
    assert_eq!(parse_safe_usize("all"), 0);

    // Bug D: benign error phrases
    assert!(!detect_agent_error(
        "## Status\nBuild successful. No errors encountered. 0 failed tests."
    ));

    // Bug E: deterministic evaluation by highest mtime
    let old_failed = AgentProgressEntry {
        name: "old_failed".to_string(),
        mtime: 1000.0,
        content: b"ERROR: failed compilation step".to_vec(),
    };
    let new_active = AgentProgressEntry {
        name: "new_active".to_string(),
        mtime: 2000.0,
        content: b"- [/] Active feature development\nAll good.".to_vec(),
    };
    let (_, st1, _, _) = poll_agent_from_entries(
        Some("123 /bin/antigravity\n"),
        &[old_failed.clone(), new_active.clone()],
        2010.0,
    );
    let (_, st2, _, _) = poll_agent_from_entries(
        Some("123 /bin/antigravity\n"),
        &[new_active, old_failed],
        2010.0,
    );
    assert_eq!(st1, AGENT_STATE_RUNNING);
    assert_eq!(st1, st2);
    checks += 8;

    // 8. Concurrent payload reads
    let shared = Arc::new(Mutex::new(build_agent_ci_payload(
        "Antigravity",
        AGENT_STATE_RUNNING,
        "Concurrent stress",
        1,
        "vitruvian-core",
        "main",
        false,
        0,
        CI_STATUS_PASSING,
        1,
        10,
        10,
    )));
    let mut handles = Vec::new();
    for _ in 0..4 {
        let s = Arc::clone(&shared);
        handles.push(thread::spawn(move || {
            for _ in 0..25 {
                let guard = s.lock().unwrap();
                assert!(guard.contains("\"type\":\"agent_ci\""));
            }
        }));
    }
    for h in handles {
        h.join().unwrap();
    }
    checks += 1;

    checks
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_agent_process_detection_stress() {
        let pgrep_output = "101 /usr/local/bin/antigravity --worker\n\
                            102 /usr/local/bin/antigravity --worker\n\
                            103 /opt/homebrew/bin/claude\n\
                            104 /opt/homebrew/bin/claude --print\n\
                            105 /usr/local/bin/agy\n";
        let (name, count) = parse_agent_processes(pgrep_output);
        assert_eq!(name.as_deref(), Some("Teamwork"));
        assert_eq!(count, 5);

        let noisy = "201 node /Users/user/.npm/bin/mcp-server-git\n\
                     202 node /Users/user/.npm/bin/mcp-remote\n\
                     203 /Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app\n\
                     204 grep -i antigravity\n\
                     205 pgrep -fl claude\n\
                     206 /opt/homebrew/bin/python3 -m antigravity\n";
        let (res_name, _, _, res_count) = poll_agent_from_entries(Some(noisy), &[], 1000.0);
        assert_eq!(res_name, "Antigravity");
        assert_eq!(res_count, 1);

        let (cname, ccount) = parse_agent_processes("   999    /bin/CLAUDE-CODE   --verbose   \n");
        assert_eq!(cname.as_deref(), Some("Claude Code"));
        assert_eq!(ccount, 1);
    }

    #[test]
    fn test_workspace_progress_stress() {
        let binary_entry = AgentProgressEntry {
            name: "corrupt_agent".to_string(),
            mtime: 995.0,
            content: b"\x00\xff\xfe\x80\x01\x02\x03Some text\n- [/] Active binary task\n\xff\xfe"
                .to_vec(),
        };
        let (name, state, task, _) =
            poll_agent_from_entries(Some("123 /bin/antigravity\n"), &[binary_entry], 1000.0);
        assert_eq!(name, "Antigravity");
        assert!(state == AGENT_STATE_RUNNING || state == AGENT_STATE_REVIEW);
        assert_eq!(task, "Active binary task");

        let empty_entry = AgentProgressEntry {
            name: "empty_agent".to_string(),
            mtime: 995.0,
            content: b"   \n\n   ".to_vec(),
        };
        let (_, _, empty_task, _) = poll_agent_from_entries(Some(""), &[empty_entry], 1000.0);
        assert_eq!(empty_task, "Ready");
    }

    #[test]
    fn test_lifecycle_state_machine_boundaries_and_clock_skew() {
        let now = 1000.0;
        assert_eq!(
            determine_agent_state(true, now - 44.9, now, false),
            AGENT_STATE_RUNNING
        );
        assert_eq!(
            determine_agent_state(true, now - 45.1, now, false),
            AGENT_STATE_REVIEW
        );
        assert_eq!(
            determine_agent_state(true, now - 299.9, now, false),
            AGENT_STATE_REVIEW
        );
        assert_eq!(
            determine_agent_state(true, now - 300.1, now, false),
            AGENT_STATE_IDLE
        );
        assert_eq!(
            determine_agent_state(true, now + 500.0, now, false),
            AGENT_STATE_RUNNING
        );
        assert_eq!(
            determine_agent_state(true, 0.0, now, false),
            AGENT_STATE_RUNNING
        );
        assert_eq!(
            determine_agent_state(true, -10.0, now, false),
            AGENT_STATE_RUNNING
        );
        assert_eq!(
            determine_agent_state(false, 0.0, now, false),
            AGENT_STATE_IDLE
        );
    }

    #[test]
    fn test_git_status_detached_head_and_dirty_tree() {
        assert_eq!(
            parse_git_status("## HEAD (no branch)\n"),
            ("HEAD".to_string(), false, 0)
        );
        assert_eq!(
            parse_git_status("## HEAD (no branch)\n M src/main.cpp\n?? newfile.py\n"),
            ("HEAD".to_string(), true, 2)
        );
        assert_eq!(
            parse_git_status("## HEAD (detached at 7a8b9c0)\n").0,
            "HEAD"
        );
        assert_eq!(
            parse_git_status("## HEAD (detached from v1.2.0)\n").0,
            "HEAD"
        );
        assert_eq!(
            parse_git_status("## feat/my-branch...origin/feat/my-branch [ahead 3, behind 1]\n"),
            ("feat/my-branch".to_string(), false, 0)
        );
        assert_eq!(
            parse_git_status("## Initial commit on feature-init\n").0,
            "feature-init"
        );
        assert_eq!(parse_git_status("## No commits yet on dev\n").0, "dev");
    }

    #[test]
    fn test_empirical_bug_reproductions_a_through_e() {
        // Bug A
        assert_eq!(parse_gh_run_list("[null]"), (CI_STATUS_UNKNOWN, 0, 0));
        assert_eq!(parse_gh_run_list("[123]"), (CI_STATUS_UNKNOWN, 0, 0));

        // Bug B
        let (branch_v1, dirty, _) = parse_git_status("## release/v1.0.0...origin/release/v1.0.0\n");
        assert_eq!(branch_v1, "release/v1.0.0");
        assert!(!dirty);
        assert_eq!(parse_git_status("## feat.v2\n").0, "feat.v2");

        // Bug C
        assert_eq!(parse_safe_usize("two"), 0);
        assert_eq!(parse_safe_usize("all"), 0);
        assert_eq!(parse_safe_usize("none"), 0);

        // Bug D
        assert!(!detect_agent_error(
            "## Status\nBuild successful. No errors encountered. 0 failed tests."
        ));

        // Bug E
        let old_failed = AgentProgressEntry {
            name: "old_failed".to_string(),
            mtime: 1000.0,
            content: b"ERROR: failed compilation step".to_vec(),
        };
        let new_active = AgentProgressEntry {
            name: "new_active".to_string(),
            mtime: 2000.0,
            content: b"- [/] Active feature development\nAll good.".to_vec(),
        };
        let (_, st_old_first, _, _) = poll_agent_from_entries(
            Some("123 /bin/antigravity\n"),
            &[old_failed.clone(), new_active.clone()],
            2005.0,
        );
        let (_, st_new_first, _, _) = poll_agent_from_entries(
            Some("123 /bin/antigravity\n"),
            &[new_active, old_failed],
            2005.0,
        );
        assert_eq!(st_old_first, AGENT_STATE_RUNNING);
        assert_eq!(st_old_first, st_new_first);
    }
}
