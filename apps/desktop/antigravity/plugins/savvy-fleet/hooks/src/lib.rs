// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

use std::fs;
use std::path::{Path, PathBuf};
use std::process;
use std::time::{SystemTime, UNIX_EPOCH};

/// Returns true if the hook payload contains a subagent-related tool call
/// (`invoke_subagent` or `send_message`).
pub fn is_subagent_payload(payload: &str) -> bool {
    payload.contains("invoke_subagent") || payload.contains("send_message")
}

/// Resolves the savvy-fleet inbox directory from `ANTIGRAVITY_APP_DATA_DIR` or `HOME`.
pub fn resolve_inbox_dir(app_data_dir: Option<&str>, home_dir: Option<&str>) -> Option<PathBuf> {
    if let Some(dir) = app_data_dir.filter(|s| !s.is_empty()) {
        return Some(Path::new(dir).join("savvy-fleet-inbox"));
    }
    let home = home_dir?;
    Some(
        Path::new(home)
            .join(".gemini")
            .join("antigravity")
            .join("savvy-fleet-inbox"),
    )
}

/// Atomically writes the payload to `<inbox_dir>/<epoch>-<pid>.json` if it matches
/// `is_subagent_payload`. Never panics; returns `Ok(Some(path))` when written.
pub fn handle_payload(payload: &str, inbox_dir: &Path) -> std::io::Result<Option<PathBuf>> {
    if !is_subagent_payload(payload) {
        return Ok(None);
    }

    fs::create_dir_all(inbox_dir)?;

    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let pid = process::id();
    let filename = format!("{secs}-{pid}.json");
    let note_path = inbox_dir.join(&filename);
    let tmp_path = inbox_dir.join(format!("{filename}.tmp"));

    fs::write(&tmp_path, payload.as_bytes())?;
    fs::rename(&tmp_path, &note_path)?;

    Ok(Some(note_path))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static TEST_COUNTER: AtomicU64 = AtomicU64::new(0);

    fn temp_inbox() -> PathBuf {
        let id = TEST_COUNTER.fetch_add(1, Ordering::SeqCst);
        let dir = std::env::temp_dir().join(format!("savvy-fleet-test-{}-{}", process::id(), id));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn matches_subagent_payloads() {
        assert!(is_subagent_payload(
            r#"{"tool_name":"invoke_subagent","tool_input":{"agent":"wren"}}"#
        ));
        assert!(is_subagent_payload(
            r#"{"tool_name":"send_message","tool_input":{"Recipient":"abc"}}"#
        ));
    }

    #[test]
    fn ignores_unrelated_payloads() {
        assert!(!is_subagent_payload(""));
        assert!(!is_subagent_payload(
            r#"{"tool_name":"run_command","tool_input":{"CommandLine":"ls"}}"#
        ));
    }

    #[test]
    fn resolves_inbox_dir_from_app_data_or_home() {
        assert_eq!(
            resolve_inbox_dir(Some("/custom/data"), Some("/Users/test")),
            Some(PathBuf::from("/custom/data/savvy-fleet-inbox"))
        );
        assert_eq!(
            resolve_inbox_dir(None, Some("/Users/test")),
            Some(PathBuf::from(
                "/Users/test/.gemini/antigravity/savvy-fleet-inbox"
            ))
        );
        assert_eq!(
            resolve_inbox_dir(Some(""), Some("/Users/test")),
            Some(PathBuf::from(
                "/Users/test/.gemini/antigravity/savvy-fleet-inbox"
            ))
        );
        assert_eq!(resolve_inbox_dir(None, None), None);
    }

    #[test]
    fn writes_note_for_matching_payload() {
        let inbox = temp_inbox();
        let payload = r#"{"tool_name":"invoke_subagent","tool_input":{"agent":"scout"}}"#;
        let written = handle_payload(payload, &inbox)
            .expect("handle_payload should succeed")
            .expect("should write a note");
        assert!(written.exists());
        assert_eq!(fs::read_to_string(&written).unwrap(), payload);
        let _ = fs::remove_dir_all(&inbox);
    }

    #[test]
    fn skips_note_for_unrelated_payload() {
        let inbox = temp_inbox();
        let payload = r#"{"tool_name":"view_file"}"#;
        let written = handle_payload(payload, &inbox).expect("handle_payload should succeed");
        assert!(written.is_none());
        assert!(!inbox.exists());
    }
}
