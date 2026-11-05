// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

//! Antigravity runs this after every shell command an agent runs (see
//! ../hooks.json). When the command was `gh pr create` (or the repo's
//! `bazel run //tools/agent-app -- pr-create`), or the sign-up command
//! `GH_WATCH=1 gh pr view <number or URL>`, it leaves a note for the gh-watch
//! watcher in `$HOME/.gemini/antigravity/gh-watch-inbox`.

use std::fs;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

const TRIGGERS: &[&[u8]] = &[b"gh pr create", b"pr-create", b"GH_WATCH=1"];
const DESKTOP_MARKER: &[u8] = b"/.gemini/antigravity/";

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

/// Evaluates whether the hook payload should record a note for gh-watch.
pub fn should_record_note(payload: &[u8]) -> bool {
    let stripped = strip_trailing_newlines(payload);
    let matches_cmd = TRIGGERS.iter().any(|t| contains_bytes(stripped, t));
    matches_cmd && contains_bytes(stripped, DESKTOP_MARKER)
}

/// Resolves `$HOME/.gemini/antigravity/gh-watch-inbox`.
pub fn resolve_inbox_dir(home_dir: Option<&str>) -> PathBuf {
    let home = home_dir.unwrap_or("");
    PathBuf::from(format!("{home}/.gemini/antigravity/gh-watch-inbox"))
}

/// Runs the hook logic against the given inbox directory, returning the stdout bytes (`{}`).
pub fn handle_payload(payload: &[u8], inbox_dir: &Path, pid: u32) -> &'static [u8] {
    let stripped = strip_trailing_newlines(payload);
    if !should_record_note(stripped) {
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

    if !should_record_note(&input) {
        return 0;
    }

    let home = std::env::var("HOME").ok();
    let inbox = resolve_inbox_dir(home.as_deref());
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
        let dir =
            std::env::temp_dir().join(format!("gh-watch-hook-test-{}-{id}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn make_payload(cmd: &str, app_folder: &str) -> Vec<u8> {
        format!(
            r#"{{"conversationId":"c1","error":"","toolCall":{{"args":{{"CommandLine":"{cmd}","Cwd":"/work"}},"name":"run_command"}},"transcriptPath":"/Users/x/.gemini/{app_folder}/brain/c1/t.jsonl"}}"#
        )
        .into_bytes()
    }

    #[test]
    fn ignores_ordinary_commands_and_non_desktop_sessions() {
        assert!(!should_record_note(&make_payload("ls -la", "antigravity")));
        assert!(!should_record_note(&make_payload(
            "gh pr create --fill",
            "antigravity-cli"
        )));
        assert!(!should_record_note(&make_payload(
            "gh pr view 12 --json url",
            "antigravity"
        )));
    }

    #[test]
    fn matches_gh_pr_create_agent_app_and_signup() {
        assert!(should_record_note(&make_payload(
            "gh pr create --fill",
            "antigravity"
        )));
        assert!(should_record_note(&make_payload(
            "bazel run //tools/agent-app -- pr-create --agent wren --fill",
            "antigravity"
        )));
        assert!(should_record_note(&make_payload(
            "GH_WATCH=1 gh pr view 12 --json url --jq .url",
            "antigravity"
        )));
    }

    #[test]
    fn writes_note_atomically_to_inbox() {
        let sandbox = temp_sandbox();
        let inbox = resolve_inbox_dir(sandbox.to_str());
        let payload = make_payload("gh pr create --fill", "antigravity");
        let out = handle_payload(&payload, &inbox, 555);
        assert_eq!(out, b"{}");

        let entries: Vec<_> = fs::read_dir(&inbox)
            .unwrap()
            .filter_map(Result::ok)
            .collect();
        assert_eq!(entries.len(), 1);
        let saved = fs::read(entries[0].path()).unwrap();
        assert_eq!(saved, payload);
        let _ = fs::remove_dir_all(&sandbox);
    }
}
