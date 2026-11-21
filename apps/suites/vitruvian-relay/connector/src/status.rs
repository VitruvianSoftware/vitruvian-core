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

/// The running `vrelay run`'s process id, from a fresh `status.json`, and
/// only while that pid is still the process that wrote it: its start time
/// (`pid_start`) must match. A crashed agent's pid taken by another program
/// is never signalled.
pub fn agent_pid(dir: &Path, now: u64) -> Option<i32> {
    let v = fresh_status(dir, now)?;
    let pid = i32::try_from(v.get("pid")?.as_u64()?)
        .ok()
        .filter(|p| *p > 1 && *p as u32 != std::process::id())?;
    let written = v.get("pid_start")?.as_u64()?;
    (crate::proc::process_start(pid) == Some(written)).then_some(pid)
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
/// how many reloads it has handled, and why the last one failed, if it did.
pub fn loaded_rules(dir: &Path, now: u64) -> Option<(String, u64, Option<String>)> {
    let v = fresh_status(dir, now)?;
    let r = v.get("rules")?;
    Some((
        r.get("sha256")?.as_str()?.to_string(),
        r.get("reloads").and_then(Value::as_u64).unwrap_or(0),
        r.get("reload_error")
            .and_then(Value::as_str)
            .map(str::to_string),
    ))
}

/// How many reloads the running agent has handled; read it before the
/// `SIGHUP`, and pass it to [`wait_for_reload`].
pub fn reloads(dir: &Path, now: u64) -> Option<u64> {
    loaded_rules(dir, now).map(|(_, n, _)| n)
}

/// After a `SIGHUP`: waits (up to `limit`) until the agent has handled a
/// reload after `before` (its count when the signal was sent), then says
/// what that reload did: `Ok(true)` once it has loaded `rules.toml` as it
/// is now, `Err` with its reason if it could not. `Ok(false)` if the agent
/// never answered. An error left by an earlier reload is not this one's.
pub fn wait_for_reload(
    dir: &Path,
    before: Option<u64>,
    limit: std::time::Duration,
) -> Result<bool, String> {
    let want = crate::rules::file_sha256(dir);
    let end = std::time::Instant::now() + limit;
    while std::time::Instant::now() < end {
        if let Some((sha, n, err)) = loaded_rules(dir, crate::state::now_unix()) {
            if before.is_none_or(|b| n > b) {
                if let Some(e) = err {
                    return Err(e);
                }
                if Some(&sha) == want.as_ref() {
                    return Ok(true);
                }
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

/// Whether the running `vrelay run` is holding the Mac awake right now.
/// With no agent running, nothing is.
pub fn keeping_awake(dir: &Path, now: u64) -> bool {
    fresh_status(dir, now)
        .and_then(|v| v.get("keep_awake").and_then(Value::as_bool))
        .unwrap_or(false)
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
                out.push(format!(
                    "the last reload failed, so the earlier rules stay in use: {e}"
                ));
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
    out.push_str(&format!(
        "Keeping this Mac awake: {}\n",
        if keeping_awake(dir, now) { "yes" } else { "no" }
    ));
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
    fn status_says_whether_the_mac_is_kept_awake() {
        let dir = test_dir("status-awake");
        // Nothing running: nothing is holding it awake.
        assert!(render(&dir, 1000).contains("Keeping this Mac awake: no\n"));
        write_status(
            &dir,
            r#"{"state":"connected","updated_unix":999,"last_pong_unix":999,"keep_awake":true}"#,
        );
        assert!(render(&dir, 1000).contains("Keeping this Mac awake: yes\n"));
        write_status(
            &dir,
            r#"{"state":"connected","updated_unix":999,"last_pong_unix":999,"keep_awake":false}"#,
        );
        assert!(render(&dir, 1000).contains("Keeping this Mac awake: no\n"));
        // A status from an older vrelay, or a stale one: no.
        write_status(&dir, r#"{"state":"connected","updated_unix":999}"#);
        assert!(render(&dir, 1000).contains("Keeping this Mac awake: no\n"));
        write_status(
            &dir,
            r#"{"state":"connected","updated_unix":1,"keep_awake":true}"#,
        );
        assert!(render(&dir, 1000).contains("Keeping this Mac awake: no\n"));
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

#[cfg(test)]
mod reload_tests {
    use super::*;
    use crate::state::{now_unix, test_dir, write_private};

    fn status(dir: &Path, reloads: u64, sha: &str, err: Option<&str>) {
        let mut rules = serde_json::json!({"paused": false, "sha256": sha, "reloads": reloads});
        if let Some(e) = err {
            rules["reload_error"] = serde_json::json!(e);
        }
        let body = serde_json::json!({
            "state": "connected", "updated_unix": now_unix(), "pid": 99999,
            "rules": rules,
        });
        write_private(&status_path(dir), body.to_string().as_bytes()).unwrap();
    }

    /// Re-review N1: right after the SIGHUP the file still holds the last
    /// reload's error. The wait goes by the agent's reload count, so a
    /// fixed file is confirmed, not refused with the old error.
    #[test]
    fn an_old_reload_error_is_not_this_reloads_answer() {
        let dir = test_dir("status-reload-seq");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(crate::rules::rules_path(&dir), "hidden=[]\nno_prompt=[]\n").unwrap();
        let fixed = crate::rules::file_sha256(&dir).unwrap();
        status(&dir, 1, "old-digest", Some("rules.toml: the old typo"));
        let before = reloads(&dir, now_unix());
        assert_eq!(before, Some(1));
        let d = dir.clone();
        let agent = std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(300));
            status(&d, 2, &fixed, None);
        });
        let got = wait_for_reload(&dir, before, std::time::Duration::from_secs(10));
        agent.join().unwrap();
        assert_eq!(got, Ok(true));
        // A reload that fails says so, with its own error.
        status(&dir, 3, "x", Some("rules.toml: new error"));
        assert_eq!(
            wait_for_reload(&dir, Some(2), std::time::Duration::from_secs(1)),
            Err("rules.toml: new error".into())
        );
        // Nothing handled yet: no answer, not the old one.
        assert_eq!(
            wait_for_reload(&dir, Some(3), std::time::Duration::from_millis(200)),
            Ok(false)
        );
    }
}

#[cfg(test)]
mod identity_tests {
    use super::*;
    use crate::state::{now_unix, test_dir, write_private};

    fn status(dir: &Path, pid: u32, start: Option<u64>) {
        let mut body =
            serde_json::json!({"state": "connected", "updated_unix": now_unix(), "pid": pid});
        if let Some(s) = start {
            body["pid_start"] = serde_json::json!(s);
        }
        write_private(&status_path(dir), body.to_string().as_bytes()).unwrap();
    }

    /// Re-review N2: the pid in status.json is signalled only while it is
    /// still the process that wrote it (same start time), so a pid handed
    /// to another program after a crash is never sent SIGHUP.
    #[test]
    fn only_the_process_that_wrote_the_status_is_signalled() {
        let dir = test_dir("status-identity");
        std::fs::create_dir_all(&dir).unwrap();
        let mut child = std::process::Command::new("/bin/sleep")
            .arg("30")
            .spawn()
            .unwrap();
        let pid = child.id();
        let start = crate::proc::process_start(pid as i32).expect("a start time");
        assert_eq!(
            crate::proc::process_start(pid as i32),
            Some(start),
            "stable"
        );
        status(&dir, pid, Some(start));
        assert_eq!(agent_pid(&dir, now_unix()), Some(pid as i32));
        // Another process now has that pid (a different start), or the
        // file does not say: never.
        status(&dir, pid, Some(start + 1));
        assert_eq!(agent_pid(&dir, now_unix()), None);
        status(&dir, pid, None);
        assert_eq!(agent_pid(&dir, now_unix()), None);
        let _ = child.kill();
        let _ = child.wait();
        status(&dir, pid, Some(start));
        assert_eq!(agent_pid(&dir, now_unix()), None, "the process is gone");
    }
}
