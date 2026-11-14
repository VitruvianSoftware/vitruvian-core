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

//! Claude Code JSONL transcript tail parser (`~/.claude/projects/*/*.jsonl`).

use std::time::Duration;

use crate::json::{JsonMap, JsonValue};
use crate::time_util::Timestamp;

pub type SessionState = String;

pub const STATE_WAITING_FOR_PERMISSION: &str = "waiting_for_permission";
pub const STATE_WORKING: &str = "working";
pub const STATE_IDLE: &str = "idle";
pub const STATE_UNKNOWN: &str = "unknown";

/// How long an unanswered `tool_use` must sit before we call it `waiting_for_permission`.
pub const PERMISSION_AFTER: Duration = Duration::from_secs(90);

/// Caps the assistant snippet carried on a session.
pub const LAST_TEXT_LIMIT: usize = 300;

/// Payload of `GET /v1/claude/sessions`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct ClaudeSessions {
    pub running: i32,
    pub sessions: Vec<ClaudeSession>,
}

impl ClaudeSessions {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("running", JsonValue::from_i32(self.running));
        m.insert(
            "sessions",
            JsonValue::Array(self.sessions.iter().map(|s| s.to_json_value()).collect()),
        );
        JsonValue::Object(m)
    }

    pub fn to_json_string(&self) -> String {
        self.to_json_value().to_json_string()
    }
}

/// One recent Claude Code transcript on this Mac.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct ClaudeSession {
    pub session_id: String,
    pub project: String,
    pub branch: String,
    pub slug: String,
    pub state: SessionState,
    pub last_tool: String,
    pub last_text: String,
    pub updated_at: Timestamp,
}

impl ClaudeSession {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("session_id", JsonValue::from_str_val(&self.session_id));
        m.insert("project", JsonValue::from_str_val(&self.project));
        if !self.branch.is_empty() {
            m.insert("branch", JsonValue::from_str_val(&self.branch));
        }
        if !self.slug.is_empty() {
            m.insert("slug", JsonValue::from_str_val(&self.slug));
        }
        m.insert("state", JsonValue::from_str_val(&self.state));
        if !self.last_tool.is_empty() {
            m.insert("last_tool", JsonValue::from_str_val(&self.last_tool));
        }
        if !self.last_text.is_empty() {
            m.insert("last_text", JsonValue::from_str_val(&self.last_text));
        }
        m.insert(
            "updated_at",
            JsonValue::from_str_val(self.updated_at.to_rfc3339()),
        );
        JsonValue::Object(m)
    }
}

/// Reads the last chunk of a Claude Code `.jsonl` transcript and returns its derived state.
pub fn parse_transcript_tail(tail: &str, now: Timestamp) -> ClaudeSession {
    let mut out = ClaudeSession {
        state: STATE_UNKNOWN.to_string(),
        ..Default::default()
    };

    let mut last_meaningful_type = String::new();
    let mut last_assistant_has_tool_use = false;
    let mut last_assistant_tool_name = String::new();

    for raw in tail.split('\n') {
        let line = raw.trim();
        if line.is_empty() || !line.starts_with('{') {
            continue;
        }
        let rec = match JsonValue::parse(line) {
            Ok(v) => v,
            Err(_) => continue,
        };
        if rec.get_bool("isSidechain") {
            continue;
        }
        let sid = rec.get_str("sessionId");
        if !sid.is_empty() {
            out.session_id = sid.to_string();
        }
        let cwd = rec.get_str("cwd");
        if !cwd.is_empty() {
            out.project = cwd.to_string();
        }
        let branch = rec.get_str("gitBranch");
        if !branch.is_empty() {
            out.branch = branch.to_string();
        }
        let slug = rec.get_str("slug");
        if !slug.is_empty() {
            out.slug = slug.to_string();
        }
        let ts = rec.get_str("timestamp");
        if !ts.is_empty() {
            if let Ok(t) = Timestamp::parse_rfc3339(ts) {
                out.updated_at = t;
            }
        }

        let rec_type = rec.get_str("type");
        match rec_type {
            "user" => {
                last_meaningful_type = "user".to_string();
                last_assistant_has_tool_use = false;
            }
            "assistant" => {
                let blocks = rec
                    .get("message")
                    .and_then(|m| m.get("content"))
                    .and_then(|c| c.as_array())
                    .unwrap_or(&[]);
                if blocks.is_empty() {
                    continue;
                }
                last_meaningful_type = "assistant".to_string();
                last_assistant_has_tool_use = false;
                last_assistant_tool_name.clear();
                for b in blocks {
                    match b.get_str("type") {
                        "tool_use" => {
                            last_assistant_has_tool_use = true;
                            last_assistant_tool_name = b.get_str("name").to_string();
                        }
                        "text" => {
                            let t = b.get_str("text").trim();
                            if !t.is_empty() {
                                out.last_text = trim_runes(t, LAST_TEXT_LIMIT);
                            }
                        }
                        _ => {}
                    }
                }
            }
            _ => {}
        }
    }

    match last_meaningful_type.as_str() {
        "user" => {
            out.state = STATE_WORKING.to_string();
        }
        "assistant" => {
            if last_assistant_has_tool_use {
                out.last_tool = last_assistant_tool_name;
                if !out.updated_at.is_zero()
                    && now.duration_since(out.updated_at) >= PERMISSION_AFTER
                {
                    out.state = STATE_WAITING_FOR_PERMISSION.to_string();
                } else {
                    out.state = STATE_WORKING.to_string();
                }
            } else {
                out.state = STATE_IDLE.to_string();
            }
        }
        _ => {}
    }

    out
}

pub fn trim_runes(s: &str, max: usize) -> String {
    let char_count = s.chars().count();
    if char_count <= max {
        return s.to_string();
    }
    let truncated: String = s.chars().take(max.saturating_sub(1)).collect();
    format!("{}…", truncated)
}

#[cfg(test)]
mod tests {
    use super::*;

    const TRANSCRIPT_IDLE: &str = concat!(
        r#"{"type":"user","sessionId":"s-1","cwd":"/Users/alice/src/core","gitBranch":"feat/x","slug":"calm-otter","timestamp":"2026-09-07T12:00:00Z","message":{"role":"user","content":"ship it"}}"#,
        "\n",
        r#"{"type":"assistant","sessionId":"s-1","cwd":"/Users/alice/src/core","gitBranch":"feat/x","slug":"calm-otter","timestamp":"2026-09-07T12:00:10Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"bazel test //..."}}]}}"#,
        "\n",
        r#"{"type":"user","sessionId":"s-1","timestamp":"2026-09-07T12:00:25Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"PASS"}]}}"#,
        "\n",
        r#"{"type":"assistant","sessionId":"s-1","timestamp":"2026-09-07T12:00:30Z","message":{"role":"assistant","content":[{"type":"text","text":"All 14 targets passed. Ready for you."}]}}"#,
        "\n",
    );

    const TRANSCRIPT_UNANSWERED_TOOL_USE: &str = concat!(
        r#"{"type":"user","sessionId":"s-2","cwd":"/Users/alice/src/core","gitBranch":"main","slug":"bold-heron","timestamp":"2026-09-07T12:00:00Z","message":{"role":"user","content":"push it"}}"#,
        "\n",
        r#"{"type":"assistant","sessionId":"s-2","cwd":"/Users/alice/src/core","gitBranch":"main","slug":"bold-heron","timestamp":"2026-09-07T12:01:00Z","message":{"role":"assistant","content":[{"type":"text","text":"Pushing the branch now."},{"type":"tool_use","id":"toolu_9","name":"Bash","input":{"command":"git push"}}]}}"#,
        "\n",
        r#"{"type":"progress","sessionId":"s-2","timestamp":"2026-09-07T12:01:01Z","data":{"type":"hook_progress"}}"#,
        "\n",
    );

    #[test]
    fn test_parse_transcript_tail_idle() {
        let now = Timestamp::from_ymd_hms(2026, 9, 7, 12, 5, 0);
        let s = parse_transcript_tail(TRANSCRIPT_IDLE, now);
        assert_eq!(s.session_id, "s-1");
        assert_eq!(s.project, "/Users/alice/src/core");
        assert_eq!(s.branch, "feat/x");
        assert_eq!(s.slug, "calm-otter");
        assert_eq!(s.state, STATE_IDLE);
        assert_eq!(s.last_tool, "");
        assert_eq!(s.last_text, "All 14 targets passed. Ready for you.");
    }

    #[test]
    fn test_parse_transcript_tail_working_vs_waiting() {
        // 20 seconds after the tool_use: could be a slow command -> working.
        let soon = Timestamp::from_ymd_hms(2026, 9, 7, 12, 1, 20);
        let s = parse_transcript_tail(TRANSCRIPT_UNANSWERED_TOOL_USE, soon);
        assert_eq!(s.state, STATE_WORKING);
        assert_eq!(s.last_tool, "Bash");

        // Two minutes later and still no tool_result -> waiting_for_permission.
        let late = Timestamp::from_ymd_hms(2026, 9, 7, 12, 3, 0);
        let s = parse_transcript_tail(TRANSCRIPT_UNANSWERED_TOOL_USE, late);
        assert_eq!(s.state, STATE_WAITING_FOR_PERMISSION);
        assert_eq!(s.last_tool, "Bash");
        assert_eq!(s.last_text, "Pushing the branch now.");
    }

    #[test]
    fn test_parse_transcript_tail_tolerates_cut_first_line() {
        let cut = &TRANSCRIPT_IDLE[37..];
        let s = parse_transcript_tail(cut, Timestamp::from_ymd_hms(2026, 9, 7, 12, 5, 0));
        assert_eq!(s.state, STATE_IDLE);
        assert_eq!(s.session_id, "s-1");
    }

    #[test]
    fn test_parse_transcript_tail_ignores_sidechain() {
        let tail = format!(
            "{}{}\n",
            TRANSCRIPT_IDLE,
            r#"{"type":"assistant","isSidechain":true,"sessionId":"s-1","timestamp":"2026-09-07T12:00:40Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read"}]}}"#
        );
        let s = parse_transcript_tail(&tail, Timestamp::from_ymd_hms(2026, 9, 7, 12, 10, 0));
        assert_eq!(s.state, STATE_IDLE);
    }

    #[test]
    fn test_trim_runes_caps_on_characters() {
        let long = "é".repeat(500);
        let got = trim_runes(&long, 300);
        assert_eq!(got.chars().count(), 300);
    }
}
