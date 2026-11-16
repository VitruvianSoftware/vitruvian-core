// Copyright (c) 2026 VitruvianSoftware
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

//! What `vrelay status` says. The link state comes from `status.json`, which
//! `vrelay run` rewrites every few seconds:
//! `{"state": "connected" | "connecting" | "waiting_for_sign_in",
//!   "updated_unix": N, "last_pong_unix": N, "next_retry_unix": N,
//!   "pid": N, "rules": {"paused": B, "sha256": "...", "reload_error": "..."},
//!   "reason": "...", "refused": "..."}` (`reason` only while waiting for a
//! sign-in that failed, such as a revoked refresh token; `refused` while the
//! relay's last answer was a refusal; `reload_error` when the last reload
//! did not load).

use std::path::Path;

use serde_json::Value;

use crate::config::STATUS_STALE_SECS;
use crate::state::{load_device, load_tokens, status_path};

/// A pong this recent, after the welcome, means the link is up.
const PONG_FRESH_SECS: u64 = 60;

#[derive(Debug, Clone, PartialEq)]
pub enum Link {
    Connected,
    /// Seconds until the next try, when known.
    Connecting(Option<u64>),
    WaitingForSignIn,
    /// No `vrelay run` process, or its status file is too old to trust.
    Stopped,
}

impl Link {
    pub fn describe(&self) -> String {
        match self {
            Link::Connected => "connected".into(),
            Link::Connecting(Some(s)) => format!("connecting (next try in {s} s)"),
            Link::Connecting(None) => "connecting".into(),
            Link::WaitingForSignIn => "waiting for sign-in".into(),
            Link::Stopped => "stopped (vrelay run is not running)".into(),
        }
    }
}

/// `status.json`, if `vrelay run` wrote it recently enough to trust.
fn fresh_status(dir: &Path, now: u64) -> Option<Value> {
    let v = std::fs::read(status_path(dir))
        .ok()
        .and_then(|b| serde_json::from_slice::<Value>(&b).ok())?;
    let u = v.get("updated_unix").and_then(Value::as_u64)?;
    (now.saturating_sub(u) <= STATUS_STALE_SECS).then_some(v)
}

/// The running `vrelay run`'s process id, from a fresh `status.json`.
pub fn agent_pid(dir: &Path, now: u64) -> Option<i32> {
    let pid = fresh_status(dir, now)?.get("pid")?.as_u64()?;
    i32::try_from(pid)
        .ok()
        .filter(|p| *p > 1 && *p as u32 != std::process::id())
}

/// Sends `vrelay run` a `SIGHUP`: it re-reads the rules and checks that
/// the sign-in is still there. False if no agent is running.
pub fn nudge_agent(dir: &Path, now: u64) -> bool {
    match agent_pid(dir, now) {
        // SAFETY: a plain signal to a pid; no memory is touched.
        Some(pid) => unsafe { libc::kill(pid, libc::SIGHUP) == 0 },
        None => false,
    }
}

/// What the running agent says about its rules: the loaded file's SHA-256,
/// and why the last reload failed, if it did.
pub fn loaded_rules(dir: &Path, now: u64) -> Option<(String, Option<String>)> {
    let v = fresh_status(dir, now)?;
    let r = v.get("rules")?;
    Some((
        r.get("sha256")?.as_str()?.to_string(),
        r.get("reload_error")
            .and_then(Value::as_str)
            .map(str::to_string),
    ))
}

/// After a `SIGHUP`: waits (up to `limit`) until the agent says it has
/// loaded `rules.toml` as it is now. `Err` with the reason if it says it
/// could not; `Ok(false)` if it never said either.
pub fn wait_for_reload(dir: &Path, limit: std::time::Duration) -> Result<bool, String> {
    let want = crate::rules::file_sha256(dir);
    let end = std::time::Instant::now() + limit;
    while std::time::Instant::now() < end {
        if let Some((sha, err)) = loaded_rules(dir, crate::state::now_unix()) {
            if Some(&sha) == want.as_ref() {
                return Ok(true);
            }
            if let Some(e) = err {
                return Err(e);
            }
        }
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
    Ok(false)
}

pub fn link_state(dir: &Path, now: u64) -> Link {
    let Some(v) = std::fs::read(status_path(dir))
        .ok()
        .and_then(|b| serde_json::from_slice::<Value>(&b).ok())
    else {
        return Link::Stopped;
    };
    let num = |k: &str| v.get(k).and_then(Value::as_u64);
    match num("updated_unix") {
        Some(u) if now.saturating_sub(u) <= STATUS_STALE_SECS => {}
        _ => return Link::Stopped,
    }
    match v.get("state").and_then(Value::as_str) {
        Some("connected") => match num("last_pong_unix") {
            Some(p) if now.saturating_sub(p) <= PONG_FRESH_SECS => Link::Connected,
            _ => Link::Connecting(None),
        },
        Some("connecting") => {
            Link::Connecting(num("next_retry_unix").map(|t| t.saturating_sub(now)))
        }
        Some("waiting_for_sign_in") => Link::WaitingForSignIn,
        _ => Link::Stopped,
    }
}

/// Why `vrelay run` is waiting for a sign-in, when it says.
pub fn waiting_reason(dir: &Path, now: u64) -> Option<String> {
    if link_state(dir, now) != Link::WaitingForSignIn {
        return None;
    }
    let v: Value = serde_json::from_slice(&std::fs::read(status_path(dir)).ok()?).ok()?;
    v.get("reason").and_then(Value::as_str).map(str::to_string)
}

/// Why the relay last refused the link, while `vrelay run` is still trying.
pub fn refusal(dir: &Path, now: u64) -> Option<String> {
    if !matches!(link_state(dir, now), Link::Connecting(_)) {
        return None;
    }
    let v = fresh_status(dir, now)?;
    v.get("refused").and_then(Value::as_str).map(str::to_string)
}

/// What to say about the rules: paused or not (as loaded, or as the file
/// says when nothing is running), and whether the file changed since.
fn rules_lines(dir: &Path, now: u64) -> Vec<String> {
    let mut out = Vec::new();
    let running = fresh_status(dir, now).and_then(|v| v.get("rules").cloned());
    match running {
        Some(r) => {
            if r.get("paused").and_then(Value::as_bool) == Some(true) {
                out.push("paused: no tools are visible and every call is refused".into());
            }
            let loaded = r.get("sha256").and_then(Value::as_str);
            if let (Some(l), Some(now_sha)) = (loaded, crate::rules::file_sha256(dir)) {
                if !l.is_empty() && l != now_sha {
                    out.push(
                        "rules.toml has changed since vrelay loaded it; run `vrelay reload` \
                         to use it (until then the rules it loaded stay in use)"
                            .into(),
                    );
                }
            }
            if let Some(e) = r.get("reload_error").and_then(Value::as_str) {
                out.push(format!("the last reload failed, so the earlier rules stay in use: {e}"));
            }
        }
        None => {
            if crate::rules::load_quietly(dir).is_some_and(|r| r.paused) {
                out.push("paused in rules.toml (applies when vrelay runs)".into());
            }
        }
    }
    out
}

pub fn render(dir: &Path, now: u64) -> String {
    let signed_in = matches!(load_tokens(dir), Ok(Some(_)));
    let mut out = String::new();
    out.push_str(if signed_in {
        "Sign-in:  signed in\n"
    } else {
        "Sign-in:  signed out (run `vrelay login`)\n"
    });
    match load_device(dir) {
        Some(d) => {
            out.push_str(&format!("Device:   {}\n", d.device_id));
            out.push_str(&format!("MCP URL:  {}\n", d.mcp_url));
        }
        None => out.push_str("Device:   not registered\n"),
    }
    out.push_str(&format!("Link:     {}\n", link_state(dir, now).describe()));
    if let Some(why) = waiting_reason(dir, now) {
        out.push_str(&format!("Why:      {why}\n"));
    }
    if let Some(why) = refusal(dir, now) {
        out.push_str(&format!("Refused:  {why}\n"));
    }
    for l in rules_lines(dir, now) {
        out.push_str(&format!("Rules:    {l}\n"));
    }
    for w in crate::rules::file_warnings(dir) {
        out.push_str(&format!("Rules:    {w}\n"));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::{save_device, save_tokens, test_dir, write_private, DeviceInfo, Tokens};

    fn sign_in(dir: &Path) {
        save_tokens(
            dir,
            &Tokens {
                access_token: "a".into(),
                refresh_token: Some("r".into()),
                expires_at_unix: 9,
            },
        )
        .unwrap();
        save_device(
            dir,
            &DeviceInfo {
                device_id: "dev-1".into(),
                mcp_url: "https://relay.example/mcp/d/dev-1".into(),
            },
        )
        .unwrap();
    }

    fn write_status(dir: &Path, body: &str) {
        write_private(&status_path(dir), body.as_bytes()).unwrap();
    }

    #[test]
    fn status_reports_signed_out() {
        let dir = test_dir("status-out");
        let out = render(&dir, 1000);
        assert!(out.contains("signed out"), "{out}");
        assert!(out.contains("stopped"), "{out}");
        assert!(!out.contains("signed in"), "{out}");
    }

    #[test]
    fn status_reports_stopped_when_status_file_is_stale() {
        let dir = test_dir("status-stale");
        sign_in(&dir);
        write_status(
            &dir,
            r#"{"state":"connected","updated_unix":880,"last_pong_unix":880}"#,
        );
        let out = render(&dir, 1000);
        assert!(out.contains("signed in"), "{out}");
        assert!(
            out.contains("dev-1") && out.contains("/mcp/d/dev-1"),
            "{out}"
        );
        assert!(out.contains("Link:     stopped"), "{out}");
    }

    #[test]
    fn status_shows_why_it_waits_for_sign_in() {
        let dir = test_dir("status-why");
        write_status(
            &dir,
            r#"{"state":"waiting_for_sign_in","updated_unix":995,"reason":"sign in again: run `vrelay login` (invalid_grant)"}"#,
        );
        let out = render(&dir, 1000);
        assert!(out.contains("Link:     waiting for sign-in"), "{out}");
        assert!(out.contains("Why:      sign in again"), "{out}");
        // Only while waiting, and only when the file says why.
        write_status(
            &dir,
            r#"{"state":"waiting_for_sign_in","updated_unix":995}"#,
        );
        assert!(!render(&dir, 1000).contains("Why:"));
        write_status(
            &dir,
            r#"{"state":"connecting","updated_unix":995,"reason":"x"}"#,
        );
        assert!(!render(&dir, 1000).contains("Why:"));
    }

    #[test]
    fn the_staleness_boundary_is_60_seconds() {
        let dir = test_dir("status-boundary");
        let body = r#"{"state":"waiting_for_sign_in","updated_unix":1000}"#;
        write_status(&dir, body);
        assert_eq!(link_state(&dir, 1059), Link::WaitingForSignIn);
        assert_eq!(link_state(&dir, 1060), Link::WaitingForSignIn);
        assert_eq!(link_state(&dir, 1061), Link::Stopped);
    }

    #[test]
    fn link_states_follow_the_status_file() {
        let dir = test_dir("status-states");
        let now = 1000;
        write_status(
            &dir,
            r#"{"state":"connected","updated_unix":995,"last_pong_unix":990}"#,
        );
        assert_eq!(link_state(&dir, now), Link::Connected);
        // Welcome received but no pong for over a minute: not connected.
        write_status(
            &dir,
            r#"{"state":"connected","updated_unix":995,"last_pong_unix":900}"#,
        );
        assert_eq!(link_state(&dir, now), Link::Connecting(None));
        write_status(
            &dir,
            r#"{"state":"connecting","updated_unix":995,"next_retry_unix":1004}"#,
        );
        assert_eq!(link_state(&dir, now), Link::Connecting(Some(4)));
        write_status(
            &dir,
            r#"{"state":"waiting_for_sign_in","updated_unix":995}"#,
        );
        assert_eq!(link_state(&dir, now), Link::WaitingForSignIn);
        write_status(&dir, "not json");
        assert_eq!(link_state(&dir, now), Link::Stopped);
    }

    #[test]
    fn status_warns_when_an_edited_rules_file_misses_new_hidden_defaults() {
        let dir = test_dir("status-rules");
        assert!(!render(&dir, 1000).contains("Rules:"));
        write_private(
            &crate::rules::rules_path(&dir),
            b"hidden = [\"set_config_value\"]\nno_prompt = []\n",
        )
        .unwrap();
        let out = render(&dir, 1000);
        assert!(out.contains("Rules:    "), "{out}");
        assert!(out.contains("get_recent_tool_calls"), "{out}");
    }
}
