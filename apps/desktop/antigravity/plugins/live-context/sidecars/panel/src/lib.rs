// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

pub mod openui;

pub use live_context_hooks::{
    build_ephemeral_context_payload, check_response_contract, evaluate_stop_shape,
    format_live_git_summary, json, resolve_state_dir, run_inject_live_context,
    run_verify_response_shape, ContractCheckResult, StopEvaluationResult, VerdictLogRecord,
    DEFAULT_RESPONSE_CONTRACT,
};

#[cfg(test)]
mod tests {
    use super::*;
    use live_context_hooks::json::Map;
    use serde_json::{json, Value};

    /// The hook library takes its own std-only JSON type.
    fn as_map(v: Value) -> Map {
        json::parse_object(&v.to_string()).unwrap()
    }

    #[test]
    fn format_live_git_summary_formats_branch_dirty_files_and_github_prs() {
        let git = as_map(json!({
            "branch": "feat/live-ctx",
            "headSha": "abc1234",
            "dirtyCount": 2,
            "dirtyFiles": ["src/index.ts", "README.md"]
        }));
        let github = as_map(json!({
            "repo": "VitruvianSoftware/vitruvian-core",
            "openPrs": [{ "number": 42, "title": "Add live context", "isDraft": false }],
            "mergedPrs": [
                {
                    "number": 41,
                    "title": "Fix bug",
                    "mergedAt": "2026-04-20T10:00:00Z"
                }
            ],
            "openIssues": 3
        }));
        let text = format_live_git_summary(Some(&git), Some(&github), true, true);
        assert!(text.contains("feat/live-ctx (abc1234)"));
        assert!(text.contains("2 uncommitted files: src/index.ts, README.md"));
        assert!(text.contains("#42 Add live context"));
        assert!(text.contains("#41 Fix bug"));
        assert!(text.contains("OPEN issues: 3"));
    }

    #[test]
    fn build_ephemeral_context_payload_produces_antigravity_inject_steps() {
        let git = as_map(json!({ "branch": "main", "headSha": "1112223", "dirtyCount": 0 }));
        let github = as_map(json!({ "unavailable": true }));
        let settings = as_map(json!({
            "injectGit": true,
            "injectGitHub": true,
            "injectContract": true
        }));
        let payload = build_ephemeral_context_payload(Some(&git), Some(&github), Some(&settings));
        assert_eq!(payload["injectSteps"].as_array().unwrap().len(), 1);
        let msg = payload["injectSteps"][0]["ephemeralMessage"]
            .as_str()
            .unwrap();
        assert!(msg.contains("LIVE GIT WORKSPACE: branch main"));
        assert!(msg.contains("GitHub state unavailable"));
        assert!(msg.contains("RESPONSE CONTRACT"));
    }

    #[test]
    fn check_response_contract_exempts_short_replies_and_flags_filler_closings() {
        let short_res = check_response_contract("Yes, that works.", None, None);
        assert!(short_res.exempt);
        assert!(short_res.valid);

        let long_filler = format!(
            "{}\n\nNothing needed from you.",
            "GIST: We updated the service.\n\nDETAIL: ".repeat(12)
        );
        let bad = check_response_contract(&long_filler, None, None);
        assert!(!bad.exempt);
        assert!(bad.has_filler);
        assert!(!bad.valid);

        let quoted_filler = format!(
            "{}\n\nNever write 'Nothing needed from you.' in the summary.",
            "GIST: We updated the rule.\n\nDETAIL: ".repeat(12)
        );
        let ok_quoted = check_response_contract(&quoted_filler, None, None);
        assert!(ok_quoted.valid);
    }

    #[test]
    fn evaluate_stop_shape_bounces_once_in_enforce_mode_and_allows_in_log_mode() {
        let msg = format!(
            "{}\n\nNo action needed.",
            "Substantive explanation of the architecture change. ".repeat(10)
        );
        let log_event = as_map(json!({
            "executionNum": 1,
            "terminationReason": "NO_TOOL_CALL",
            "lastAssistantMessage": msg
        }));
        let log_res = evaluate_stop_shape(&log_event, Some("log"), None, None, None);
        assert_eq!(log_res.output["decision"], "allow");
        assert!(!log_res.bounced);
        assert_eq!(log_res.log_record.unwrap().verdict, "block");

        let enforce_res = evaluate_stop_shape(&log_event, Some("enforce"), None, None, None);
        assert_eq!(enforce_res.output["decision"], "continue");
        assert!(enforce_res.bounced);
        assert!(enforce_res.output["reason"]
            .as_str()
            .unwrap()
            .contains("RESPONSE CONTRACT"));
    }
}
