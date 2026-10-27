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
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! Rust migration of `test_cloud_ci.py`:
//! Standalone Cloud CI polling, GitHub Actions response parsing, transition-edge chime
//! state machine, piezo buzzer note tables, poll scheduling, and TLS hardening checks.

use crate::{json_extract_i64, json_extract_str, read_component_file};
use std::collections::BTreeMap;

pub fn build_runs_url(repo: &str, branch: &str) -> String {
    let mut url = format!(
        "https://api.github.com/repos/{repo}/actions/runs?per_page=1&exclude_pull_requests=true"
    );
    if !branch.is_empty() {
        url.push_str(&format!("&branch={branch}"));
    }
    url
}

pub fn build_headers(token: &str) -> BTreeMap<String, String> {
    let mut headers = BTreeMap::new();
    headers.insert("User-Agent".to_string(), "Vitruvian-ESP32-S3".to_string());
    headers.insert(
        "Accept".to_string(),
        "application/vnd.github+json".to_string(),
    );
    headers.insert("X-GitHub-Api-Version".to_string(), "2022-11-28".to_string());
    if !token.is_empty() {
        headers.insert("Authorization".to_string(), format!("Bearer {token}"));
    }
    headers
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedRun {
    pub id: i64,
    pub status: String,
    pub conclusion: String,
    pub head_branch: String,
    pub head_sha: String,
    pub name: String,
}

pub fn parse_latest_run(body: &str) -> Option<ParsedRun> {
    let runs_pos = body.find("\"workflow_runs\"")?;
    let after_runs = &body[runs_pos..];
    let bracket_start = after_runs.find('[')?;
    let inside = &after_runs[bracket_start + 1..];
    let trimmed = inside.trim_start();
    if trimmed.starts_with(']') || !trimmed.starts_with('{') {
        return None;
    }
    let id = json_extract_i64(trimmed, "id")?;
    let status = json_extract_str(trimmed, "status").unwrap_or_default();
    if status.is_empty() {
        return None;
    }
    let conclusion = json_extract_str(trimmed, "conclusion").unwrap_or_default();
    let head_branch = json_extract_str(trimmed, "head_branch")
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "-".to_string());
    let head_sha: String = json_extract_str(trimmed, "head_sha")
        .unwrap_or_default()
        .chars()
        .take(7)
        .collect();
    let name = json_extract_str(trimmed, "name")
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "CI".to_string());
    Some(ParsedRun {
        id,
        status,
        conclusion,
        head_branch,
        head_sha,
        name,
    })
}

#[derive(Debug, Default)]
pub struct ChimeModel {
    pub last_run_id: i64,
    pub last_conclusion: String,
    pub muted: bool,
    pub played: Vec<String>,
}

impl ChimeModel {
    pub fn on_run(&mut self, run: &ParsedRun) {
        if run.status != "completed" || run.conclusion.is_empty() {
            return;
        }
        if self.last_run_id == 0 {
            self.last_run_id = run.id;
            self.last_conclusion = run.conclusion.clone();
            return;
        }
        let changed = run.id != self.last_run_id || run.conclusion != self.last_conclusion;
        self.last_run_id = run.id;
        self.last_conclusion = run.conclusion.clone();
        if !changed || self.muted {
            return;
        }
        if run.conclusion == "success" {
            self.played.push("pass".to_string());
        } else if matches!(
            run.conclusion.as_str(),
            "failure" | "timed_out" | "startup_failure"
        ) {
            self.played.push("fail".to_string());
        }
    }
}

pub fn parse_note_table(src: &str, name: &str) -> Vec<(u32, u32)> {
    let marker = format!("k{name}[]");
    let start = src
        .find(&marker)
        .unwrap_or_else(|| panic!("missing note table {marker}"));
    let after = &src[start..];
    let open_brace = after.find('{').unwrap();
    let close_semi = after.find("};").unwrap();
    let body = &after[open_brace + 1..close_semi];
    let mut notes = Vec::new();
    let mut rest = body;
    while let Some(open) = rest.find('{') {
        let after_open = &rest[open + 1..];
        if let Some(close) = after_open.find('}') {
            let pair = &after_open[..close];
            let parts: Vec<&str> = pair.split(',').map(|s| s.trim()).collect();
            if parts.len() == 2 {
                if let (Ok(f), Ok(d)) = (parts[0].parse::<u32>(), parts[1].parse::<u32>()) {
                    notes.push((f, d));
                }
            }
            rest = &after_open[close + 1..];
        } else {
            break;
        }
    }
    notes
}

pub fn clamp_interval(sec: i32) -> i32 {
    if sec < 15 {
        15
    } else if sec > 3600 {
        3600
    } else {
        sec
    }
}

pub fn backoff_ms(base_sec: u64, consecutive_errors: u32) -> u64 {
    let interval_ms = base_sec * 1000;
    if consecutive_errors == 0 {
        return interval_ms;
    }
    let shift = consecutive_errors.min(5);
    let wait = (interval_ms << shift).min(15 * 60 * 1000);
    interval_ms.max(wait)
}

pub fn test_request_and_parsing() {
    assert_eq!(
        build_runs_url("VitruvianSoftware/vitruvian-core", ""),
        "https://api.github.com/repos/VitruvianSoftware/vitruvian-core/actions/runs?per_page=1&exclude_pull_requests=true"
    );
    assert_eq!(
        build_runs_url("VitruvianSoftware/vitruvian-core", "main"),
        "https://api.github.com/repos/VitruvianSoftware/vitruvian-core/actions/runs?per_page=1&exclude_pull_requests=true&branch=main"
    );
    let h_anon = build_headers("");
    assert!(!h_anon.contains_key("Authorization"));
    assert_eq!(h_anon.get("User-Agent").unwrap(), "Vitruvian-ESP32-S3");
    assert_eq!(h_anon.get("Accept").unwrap(), "application/vnd.github+json");
    assert_eq!(h_anon.get("X-GitHub-Api-Version").unwrap(), "2022-11-28");

    let h_auth = build_headers("ghp_secret123");
    assert_eq!(h_auth.get("Authorization").unwrap(), "Bearer ghp_secret123");

    let body_completed = r#"{"total_count":1,"workflow_runs":[{"id":987654321,"name":"CI","head_branch":"main","head_sha":"4e4fbf4abcdef1234567890","status":"completed","conclusion":"success"}]}"#;
    let r = parse_latest_run(body_completed).unwrap();
    assert_eq!(r.id, 987_654_321);
    assert_eq!(r.status, "completed");
    assert_eq!(r.conclusion, "success");
    assert_eq!(r.head_branch, "main");
    assert_eq!(r.head_sha, "4e4fbf4");
    assert_eq!(r.name, "CI");

    let body_inflight = r#"{"workflow_runs":[{"id":999,"name":"Build","head_branch":"feat/x","head_sha":"1234567890","status":"in_progress","conclusion":null}]}"#;
    let r_in = parse_latest_run(body_inflight).unwrap();
    assert_eq!(r_in.status, "in_progress");
    assert_eq!(r_in.conclusion, "");
    assert_eq!(r_in.head_sha, "1234567");

    assert!(parse_latest_run(r#"{"total_count":0,"workflow_runs":[]}"#).is_none());
    assert!(parse_latest_run("not json").is_none());
    assert!(parse_latest_run(r#"{"message":"API rate limit exceeded"}"#).is_none());
    assert!(parse_latest_run(r#"{"workflow_runs":[{"id":0}]}"#).is_none());

    let r_min = parse_latest_run(r#"{"workflow_runs":[{"id":42,"status":"queued"}]}"#).unwrap();
    assert_eq!(r_min.head_branch, "-");
    assert_eq!(r_min.name, "CI");
}

pub fn test_chime_transitions() {
    let run = |id: i64, status: &str, conclusion: &str| ParsedRun {
        id,
        status: status.to_string(),
        conclusion: conclusion.to_string(),
        head_branch: "main".to_string(),
        head_sha: "abc1234".to_string(),
        name: "CI".to_string(),
    };

    let mut m = ChimeModel::default();
    m.on_run(&run(100, "completed", "failure"));
    assert!(m.played.is_empty());
    assert_eq!(m.last_run_id, 100);

    for _ in 0..5 {
        m.on_run(&run(100, "completed", "failure"));
    }
    assert!(m.played.is_empty());

    let mut m2 = ChimeModel::default();
    m2.on_run(&run(100, "completed", "success"));
    m2.on_run(&run(101, "in_progress", ""));
    assert!(m2.played.is_empty());
    m2.on_run(&run(101, "completed", "failure"));
    assert_eq!(m2.played, vec!["fail"]);
    m2.on_run(&run(102, "completed", "success"));
    assert_eq!(m2.played, vec!["fail", "pass"]);

    let mut m3 = ChimeModel::default();
    m3.on_run(&run(100, "completed", "success"));
    m3.on_run(&run(101, "completed", "success"));
    assert_eq!(m3.played, vec!["pass"]);

    let mut m4 = ChimeModel::default();
    m4.on_run(&run(1, "completed", "success"));
    m4.on_run(&run(2, "completed", "timed_out"));
    m4.on_run(&run(3, "completed", "startup_failure"));
    assert_eq!(m4.played, vec!["fail", "fail"]);

    let mut m5 = ChimeModel::default();
    m5.on_run(&run(1, "completed", "success"));
    m5.on_run(&run(2, "completed", "cancelled"));
    m5.on_run(&run(3, "completed", "skipped"));
    assert!(m5.played.is_empty());

    let mut m6 = ChimeModel::default();
    m6.on_run(&run(1, "completed", "success"));
    m6.muted = true;
    m6.on_run(&run(2, "completed", "failure"));
    assert!(m6.played.is_empty());
    m6.muted = false;
    m6.on_run(&run(3, "completed", "success"));
    assert_eq!(m6.played, vec!["pass"]);
}

pub fn test_buzzer_firmware_source() {
    let buzzer_cpp = read_component_file("src/buzzer.cpp");
    let buzzer_h = read_component_file("src/buzzer.h");
    let ui_cpp = read_component_file("src/ui.cpp");
    let mac_hid_cpp = read_component_file("src/mac_hid.cpp");

    let notes_pass = parse_note_table(&buzzer_cpp, "Pass");
    assert_eq!(
        notes_pass,
        vec![(523, 80), (659, 80), (784, 120), (1046, 200)]
    );
    let freqs_pass: Vec<u32> = notes_pass.iter().map(|n| n.0).collect();
    let mut sorted_pass = freqs_pass.clone();
    sorted_pass.sort_unstable();
    assert_eq!(freqs_pass, sorted_pass);

    let notes_fail = parse_note_table(&buzzer_cpp, "Fail");
    assert_eq!(notes_fail, vec![(698, 150), (587, 150), (494, 300)]);
    let freqs_fail: Vec<u32> = notes_fail.iter().map(|n| n.0).collect();
    let mut sorted_fail = freqs_fail.clone();
    sorted_fail.sort_unstable_by(|a, b| b.cmp(a));
    assert_eq!(freqs_fail, sorted_fail);

    let notes_click = parse_note_table(&buzzer_cpp, "Click");
    assert_eq!(notes_click, vec![(1000, 20)]);

    let gap_line = buzzer_cpp
        .lines()
        .find(|l| l.contains("NOTE_GAP_MS"))
        .expect("missing NOTE_GAP_MS");
    let gap: u32 = gap_line
        .split('=')
        .next_back()
        .unwrap()
        .trim()
        .trim_end_matches(';')
        .parse()
        .unwrap();
    let pass_total: u32 = notes_pass.iter().map(|n| n.1).sum::<u32>()
        + gap * (notes_pass.len().saturating_sub(1) as u32);
    assert!(pass_total < 1000);

    let set_muted_idx = buzzer_cpp
        .find("void buzzer_set_muted(")
        .expect("missing buzzer_set_muted");
    let set_muted_body = &buzzer_cpp[set_muted_idx..];
    assert!(set_muted_body.contains("playing = false;"));
    assert!(set_muted_body.contains("silence();"));
    assert!(buzzer_cpp.contains("NVS_SETTINGS_NS = \"settings\""));
    assert!(buzzer_cpp.contains("NVS_MUTED_KEY = \"chimes_muted\""));
    assert!(buzzer_cpp.contains("buzzer_prefs.getBool(NVS_MUTED_KEY, false)"));
    assert!(buzzer_cpp.contains("buzzer_prefs.putBool(NVS_MUTED_KEY, muted)"));

    let max_notes_line = buzzer_h
        .lines()
        .find(|l| l.contains("#define BUZZER_MAX_NOTES"))
        .expect("missing BUZZER_MAX_NOTES");
    let cap: usize = max_notes_line
        .split_whitespace()
        .last()
        .unwrap()
        .parse()
        .unwrap();
    for tbl in [&notes_pass, &notes_fail, &notes_click] {
        assert!(tbl.len() <= cap);
    }

    let loop_pos = buzzer_cpp.find("void buzzer_loop()").unwrap();
    let loop_body = &buzzer_cpp[loop_pos..];
    assert!(!loop_body.contains("delay("));
    assert!(!loop_body.contains("vTaskDelay"));

    let buzz_ch_line = buzzer_cpp
        .lines()
        .find(|l| l.contains("BUZZER_LEDC_CH"))
        .unwrap();
    let buzz_ch: u32 = buzz_ch_line
        .split('=')
        .next_back()
        .unwrap()
        .trim()
        .trim_end_matches(';')
        .parse()
        .unwrap();
    let bl_ch_line = ui_cpp.lines().find(|l| l.contains("BL_PWM_CH")).unwrap();
    let bl_ch: u32 = bl_ch_line
        .split('=')
        .next_back()
        .unwrap()
        .trim()
        .trim_end_matches(';')
        .parse()
        .unwrap();
    assert_ne!(buzz_ch, bl_ch);

    assert!(mac_hid_cpp.contains("buzzer_play_click()"));
}

pub fn test_poll_scheduling_and_tls() {
    assert_eq!(clamp_interval(0), 15);
    assert_eq!(clamp_interval(5), 15);
    assert_eq!(clamp_interval(15), 15);
    assert_eq!(clamp_interval(60), 60);
    assert_eq!(clamp_interval(3600), 3600);
    assert_eq!(clamp_interval(99_999), 3600);

    assert_eq!(backoff_ms(60, 0), 60_000);
    assert_eq!(backoff_ms(60, 1), 120_000);
    assert_eq!(backoff_ms(60, 2), 240_000);
    assert_eq!(backoff_ms(60, 5), 900_000);
    assert_eq!(backoff_ms(60, 10), 900_000);
    assert_eq!(backoff_ms(3600, 10), 3_600_000);

    let cloud_cpp = read_component_file("src/cloud_ci.cpp");
    let cloud_h = read_component_file("src/cloud_ci.h");
    let main_cpp = read_component_file("src/main.cpp");
    let router_h = read_component_file("src/packet_router.h");
    let router_cpp = read_component_file("src/packet_router.cpp");
    let ca_h = read_component_file("src/github_ca.h");
    let ui_cpp = read_component_file("src/ui.cpp");

    assert!(cloud_h.contains("char sha[8];"));
    for field in [
        "name",
        "status",
        "conclusion",
        "head_sha",
        "head_branch",
        "run_number",
    ] {
        assert!(
            cloud_cpp.contains(&format!("run[\"{field}\"] = true")),
            "missing filter field {field}"
        );
    }
    let set_repo_idx = cloud_cpp
        .find("void cloud_ci_set_repo")
        .expect("missing cloud_ci_set_repo");
    let set_repo_body = &cloud_cpp[set_repo_idx..];
    assert!(set_repo_body.contains("primed = false;"));
    assert!(set_repo_body.contains("last_run_number = -1;"));

    assert!(router_cpp.contains("strcmp(cmd, \"cloud_config\") == 0"));
    assert!(router_cpp.contains("cloud_ci_set_repo("));
    assert!(router_cpp.contains("cloud_ci_set_token("));
    assert!(router_cpp.contains("cloud_ci_set_enabled("));
    assert!(router_cpp.contains("cloud_ci_has_token() ? \"yes\" : \"no\""));
    for line in router_cpp.lines() {
        if line.contains("Serial.print") && line.contains("[CLOUD]") {
            assert!(!line.contains("token)"));
            assert!(!line.contains("token,"));
        }
    }

    let idle_ms: u64 = main_cpp
        .lines()
        .find(|l| l.contains("#define CLOUD_TAKEOVER_IDLE_MS"))
        .unwrap()
        .split_whitespace()
        .last()
        .unwrap()
        .trim_end_matches("UL")
        .parse()
        .unwrap();
    let active_ms: u64 = router_h
        .lines()
        .find(|l| l.contains("#define LINK_ACTIVE_WINDOW_MS"))
        .unwrap()
        .split_whitespace()
        .last()
        .unwrap()
        .trim_end_matches("UL")
        .parse()
        .unwrap();
    assert!(idle_ms > active_ms);

    assert!(cloud_cpp.contains("client.setCACert(GITHUB_ROOT_CAS)"));
    assert!(cloud_cpp.contains("cfg_insecure = cloud_prefs.getBool(\"insecure\", false)"));

    let begins = ca_h.matches("-----BEGIN CERTIFICATE-----").count();
    let ends = ca_h.matches("-----END CERTIFICATE-----").count();
    assert_eq!(begins, 3);
    assert_eq!(begins, ends);

    assert!(cloud_cpp.contains("xTaskCreatePinnedToCore(cloud_ci_task"));
    assert!(cloud_cpp.contains("xSemaphoreCreateMutex()"));
    assert!(cloud_cpp.contains("#define CLOUD_CI_MAX_BODY 65536"));

    for line in cloud_cpp.lines() {
        if line.contains("Serial.print") && line.contains("cfg_token") {
            assert!(line.contains("\"yes\" : \"no\""));
        }
    }

    assert!(ui_cpp.contains("card_audio"));
    assert!(ui_cpp.contains("sw_chimes"));
    assert!(ui_cpp.contains("buzzer_set_muted(!checked);"));
    assert!(ui_cpp.contains("lv_obj_set_scroll_dir(t3, LV_DIR_VER);"));
}

pub fn run_suite() -> usize {
    test_request_and_parsing();
    test_chime_transitions();
    test_buzzer_firmware_source();
    test_poll_scheduling_and_tls();
    4
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cloud_ci_suite() {
        assert_eq!(run_suite(), 4);
    }
}
