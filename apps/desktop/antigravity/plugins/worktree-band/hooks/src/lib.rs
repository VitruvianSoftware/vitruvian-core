// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

use std::fs;
use std::path::{Path, PathBuf};
use std::process;
use std::time::{SystemTime, UNIX_EPOCH};

/// Returns true if the hook payload contains session workspace metadata
/// (`"workspacePaths"`, `"cwd"`, or `"conversationId"`).
pub fn is_session_worktree_payload(payload: &str) -> bool {
    payload.contains("\"workspacePaths\"")
        || payload.contains("\"cwd\"")
        || payload.contains("\"conversationId\"")
}

/// Resolves `~/.gemini/antigravity/worktree-band-inbox` from `HOME`.
pub fn resolve_inbox_dir(home_dir: Option<&str>) -> Option<PathBuf> {
    let home = home_dir.filter(|s| !s.is_empty())?;
    Some(
        Path::new(home)
            .join(".gemini")
            .join("antigravity")
            .join("worktree-band-inbox"),
    )
}

/// Atomically writes the payload to `<inbox_dir>/<epoch>-<pid>.json` if it matches
/// `is_session_worktree_payload`.
pub fn handle_payload(payload: &str, inbox_dir: &Path) -> std::io::Result<Option<PathBuf>> {
    if !is_session_worktree_payload(payload) {
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
        let dir = std::env::temp_dir().join(format!("worktree-band-test-{}-{}", process::id(), id));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn matches_session_worktree_keys() {
        assert!(is_session_worktree_payload(
            r#"{"workspacePaths":["/repo"]}"#
        ));
        assert!(is_session_worktree_payload(r#"{"cwd":"/repo"}"#));
        assert!(is_session_worktree_payload(
            r#"{"conversationId":"abc-123"}"#
        ));
    }

    #[test]
    fn ignores_unrelated_payloads() {
        assert!(!is_session_worktree_payload(""));
        assert!(!is_session_worktree_payload(r#"{"tool_name":"view_file"}"#));
    }

    #[test]
    fn resolves_inbox_dir_from_home() {
        assert_eq!(
            resolve_inbox_dir(Some("/Users/test")),
            Some(PathBuf::from(
                "/Users/test/.gemini/antigravity/worktree-band-inbox"
            ))
        );
        assert_eq!(resolve_inbox_dir(Some("")), None);
        assert_eq!(resolve_inbox_dir(None), None);
    }

    #[test]
    fn writes_note_for_matching_payload() {
        let inbox = temp_inbox();
        let payload = r#"{"conversationId":"conv-1","workspacePaths":["/tmp/wt"]}"#;
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
        let payload = r#"{"event":"other"}"#;
        let written = handle_payload(payload, &inbox).expect("handle_payload should succeed");
        assert!(written.is_none());
        assert!(!inbox.exists());
    }
}
