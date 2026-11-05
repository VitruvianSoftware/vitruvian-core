// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

use std::fs;
use std::path::{Path, PathBuf};
use std::process;
use std::time::{SystemTime, UNIX_EPOCH};

/// Returns true if the hook payload contains session workspace metadata
/// (`"workspacePaths"`, `"cwd"`, or `"conversationId"`).
pub fn is_session_worktree_payload(payload: impl AsRef<[u8]>) -> bool {
    let payload = payload.as_ref();
    contains_bytes(payload, b"\"workspacePaths\"")
        || contains_bytes(payload, b"\"cwd\"")
        || contains_bytes(payload, b"\"conversationId\"")
}

/// The payload as the shell hook saw it: `payload=$(cat)` drops every
/// trailing newline (and nothing else), and the note gets exactly that.
pub fn strip_trailing_newlines(mut input: &[u8]) -> &[u8] {
    while let Some((&b'\n', rest)) = input.split_last() {
        input = rest;
    }
    input
}

fn contains_bytes(haystack: &[u8], needle: &[u8]) -> bool {
    haystack.windows(needle.len()).any(|w| w == needle)
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
pub fn handle_payload(
    payload: impl AsRef<[u8]>,
    inbox_dir: &Path,
) -> std::io::Result<Option<PathBuf>> {
    // Raw bytes: a payload that is not UTF-8 is still recorded, as the
    // shell hook recorded it.
    let payload = strip_trailing_newlines(payload.as_ref());
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

    fs::write(&tmp_path, payload)?;
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

    // Parity with the shell hook this replaced (`payload=$(cat)`, then
    // `printf '%s' "$payload"` into the note).

    #[test]
    fn note_drops_trailing_newlines_like_the_shell_hook() {
        let inbox = temp_inbox();
        let payload = "{\"x\":\"\"cwd\"\"}\r\n\n\n";
        let written = handle_payload(payload, &inbox).unwrap().unwrap();
        // Only the newlines go; a carriage return stays, as in the shell.
        assert_eq!(fs::read(&written).unwrap(), b"{\"x\":\"\"cwd\"\"}\r");
        let _ = fs::remove_dir_all(&inbox);
    }

    #[test]
    fn note_keeps_inner_newlines_and_bytes_that_are_not_utf8() {
        let inbox = temp_inbox();
        let payload: &[u8] = b"{\"a\":\"\xe9\",\n\"x\":\"\"cwd\"\"}\n";
        let written = handle_payload(payload, &inbox)
            .unwrap()
            .expect("a payload that is not UTF-8 is still recorded");
        assert_eq!(fs::read(&written).unwrap(), &payload[..payload.len() - 1]);
        let _ = fs::remove_dir_all(&inbox);
    }
}
