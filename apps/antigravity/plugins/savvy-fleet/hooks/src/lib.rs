// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

use std::fs;
use std::path::{Path, PathBuf};
use std::process;
use std::time::{SystemTime, UNIX_EPOCH};

/// Returns true if the hook payload contains a subagent-related tool call
/// (`invoke_subagent` or `send_message`).
pub fn is_subagent_payload(payload: impl AsRef<[u8]>) -> bool {
    let payload = payload.as_ref();
    contains_bytes(payload, b"invoke_subagent") || contains_bytes(payload, b"send_message")
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
pub fn handle_payload(
    payload: impl AsRef<[u8]>,
    inbox_dir: &Path,
) -> std::io::Result<Option<PathBuf>> {
    // Raw bytes: a payload that is not UTF-8 is still recorded, as the
    // shell hook recorded it.
    let payload = strip_trailing_newlines(payload.as_ref());
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

    // Parity with the shell hook this replaced (`payload=$(cat)`, then
    // `printf '%s' "$payload"` into the note).

    #[test]
    fn note_drops_trailing_newlines_like_the_shell_hook() {
        let inbox = temp_inbox();
        let payload = "{\"x\":\"invoke_subagent\"}\r\n\n\n";
        let written = handle_payload(payload, &inbox).unwrap().unwrap();
        // Only the newlines go; a carriage return stays, as in the shell.
        assert_eq!(
            fs::read(&written).unwrap(),
            b"{\"x\":\"invoke_subagent\"}\r"
        );
        let _ = fs::remove_dir_all(&inbox);
    }

    #[test]
    fn note_keeps_inner_newlines_and_bytes_that_are_not_utf8() {
        let inbox = temp_inbox();
        let payload: &[u8] = b"{\"a\":\"\xe9\",\n\"x\":\"invoke_subagent\"}\n";
        let written = handle_payload(payload, &inbox)
            .unwrap()
            .expect("a payload that is not UTF-8 is still recorded");
        assert_eq!(fs::read(&written).unwrap(), &payload[..payload.len() - 1]);
        let _ = fs::remove_dir_all(&inbox);
    }
}
