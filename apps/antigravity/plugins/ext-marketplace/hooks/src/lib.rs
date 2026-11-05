// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

//! Notices `agy plugin` commands run by an agent so the Extensions Marketplace
//! sidecar knows when a plugin was installed, toggled, or removed from the CLI.

use std::fs;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

const TRIGGER: &[u8] = b"agy plugin";
const INBOX_NAME: &str = "ext-marketplace-inbox";

/// Strip trailing `\n` bytes, matching POSIX shell command substitution `payload=$(cat)`.
pub fn strip_trailing_newlines(mut input: &[u8]) -> &[u8] {
    while let Some((&b'\n', rest)) = input.split_last() {
        input = rest;
    }
    input
}

/// Returns true when `haystack` contains `needle` as a contiguous byte slice.
pub fn contains_bytes(haystack: &[u8], needle: &[u8]) -> bool {
    if needle.is_empty() {
        return true;
    }
    haystack.windows(needle.len()).any(|w| w == needle)
}

/// Resolves `${ANTIGRAVITY_APP_DATA_DIR:-$HOME/.gemini/antigravity}/ext-marketplace-inbox`.
pub fn resolve_inbox_dir(app_data_dir: Option<&str>, home_dir: Option<&str>) -> PathBuf {
    let base = match app_data_dir {
        Some(dir) if !dir.is_empty() => PathBuf::from(dir),
        _ => {
            let home = home_dir.unwrap_or("");
            PathBuf::from(format!("{home}/.gemini/antigravity"))
        }
    };
    base.join(INBOX_NAME)
}

/// Evaluates whether the hook payload should record a note in the inbox.
pub fn should_record_note(payload: &[u8]) -> bool {
    let stripped = strip_trailing_newlines(payload);
    contains_bytes(stripped, TRIGGER)
}

/// Runs the hook logic against the given inbox directory, returning the stdout bytes (`{}`).
pub fn handle_payload(payload: &[u8], inbox_dir: &Path, pid: u32) -> &'static [u8] {
    let stripped = strip_trailing_newlines(payload);
    if !contains_bytes(stripped, TRIGGER) {
        return b"{}";
    }

    if fs::create_dir_all(inbox_dir).is_err() {
        return b"{}";
    }

    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let note_path = inbox_dir.join(format!("{secs}-{pid}.json"));
    let tmp_path = inbox_dir.join(format!("{secs}-{pid}.json.tmp"));

    if let Ok(mut f) = fs::File::create(&tmp_path) {
        if f.write_all(stripped).is_ok() && f.flush().is_ok() {
            let _ = fs::rename(&tmp_path, &note_path);
        }
    }

    b"{}"
}

/// Entrypoint reading from stdin and environment variables.
pub fn run_from_stdio() -> i32 {
    let mut input = Vec::new();
    let _ = io::stdin().read_to_end(&mut input);

    let _ = io::stdout().write_all(b"{}");
    let _ = io::stdout().flush();

    let stripped = strip_trailing_newlines(&input);
    if !contains_bytes(stripped, TRIGGER) {
        return 0;
    }

    let app_data = std::env::var("ANTIGRAVITY_APP_DATA_DIR").ok();
    let home = std::env::var("HOME").ok();
    let inbox = resolve_inbox_dir(app_data.as_deref(), home.as_deref());
    let _ = handle_payload(&input, &inbox, std::process::id());
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, Ordering};

    static NEXT_PID: AtomicU32 = AtomicU32::new(1000);

    fn temp_sandbox() -> PathBuf {
        let id = NEXT_PID.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!(
            "ext-marketplace-hook-test-{}-{id}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn ignores_ordinary_commands() {
        let sandbox = temp_sandbox();
        let inbox = resolve_inbox_dir(None, sandbox.to_str());
        let payload = br#"{"toolCall":{"name":"run_command","args":{"CommandLine":"ls -la"}}}"#;
        let out = handle_payload(payload, &inbox, 42);
        assert_eq!(out, b"{}");
        assert!(!inbox.exists());
        let _ = fs::remove_dir_all(&sandbox);
    }

    #[test]
    fn records_note_for_agy_plugin_command() {
        let sandbox = temp_sandbox();
        let inbox = resolve_inbox_dir(None, sandbox.to_str());
        let payload =
            br#"{"toolCall":{"name":"run_command","args":{"CommandLine":"agy plugin install foo"}}}"#;
        let out = handle_payload(payload, &inbox, 123);
        assert_eq!(out, b"{}");

        let entries: Vec<_> = fs::read_dir(&inbox)
            .unwrap()
            .filter_map(Result::ok)
            .collect();
        assert_eq!(entries.len(), 1);
        let path = entries[0].path();
        assert!(path.extension().and_then(|e| e.to_str()) == Some("json"));
        let saved = fs::read(&path).unwrap();
        assert_eq!(saved, payload);
        let _ = fs::remove_dir_all(&sandbox);
    }

    #[test]
    fn honours_antigravity_app_data_dir_override() {
        let sandbox = temp_sandbox();
        let custom_app_dir = sandbox.join("custom-app-data");
        let inbox = resolve_inbox_dir(custom_app_dir.to_str(), Some("/unused/home"));
        assert_eq!(inbox, custom_app_dir.join("ext-marketplace-inbox"));

        let payload = b"{\"cmd\":\"agy plugin list\"}\n";
        let out = handle_payload(payload, &inbox, 999);
        assert_eq!(out, b"{}");

        let entries: Vec<_> = fs::read_dir(&inbox)
            .unwrap()
            .filter_map(Result::ok)
            .collect();
        assert_eq!(entries.len(), 1);
        let saved = fs::read(entries[0].path()).unwrap();
        assert_eq!(saved, b"{\"cmd\":\"agy plugin list\"}");
        let _ = fs::remove_dir_all(&sandbox);
    }

    #[test]
    fn gracefully_handles_unwritable_directory() {
        let unwritable = Path::new("/nonexistent/ext-marketplace-test/inbox");
        let payload = b"{\"cmd\":\"agy plugin enable gh-watch\"}";
        let out = handle_payload(payload, unwritable, 1);
        assert_eq!(out, b"{}");
    }
}
