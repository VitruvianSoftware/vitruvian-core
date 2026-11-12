// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::time::Duration;

use vitruvian_remote_macagent_metrics::json::{JsonMap, JsonValue};

use crate::http_util::{http_request, MAX_REQUEST_BODY};
use crate::pair::{default_config_dir, expand_home, Store};
use crate::permission::{DECISION_ALLOW, DECISION_DENY, DEFAULT_DENY_MESSAGE};

pub const HOOK_BINARY_NAME: &str = "vitruvian-remote-agent";
pub const HOOK_VERB: &str = "permission-hook";
pub const HOOK_TIMEOUT_SECONDS: i64 = 150;
pub const HOOK_CONNECT_TIMEOUT: Duration = Duration::from_secs(1);
pub const HOOK_TOTAL_TIMEOUT: Duration = Duration::from_secs(145);

pub fn permission_hook_output(
    mut stdin: impl Read,
    base_url: &str,
    token: &str,
) -> Option<Vec<u8>> {
    if token.is_empty() {
        return None;
    }
    let mut input = Vec::new();
    if stdin
        .by_ref()
        .take((MAX_REQUEST_BODY + 1) as u64)
        .read_to_end(&mut input)
        .is_err()
    {
        return None;
    }
    if input.len() > MAX_REQUEST_BODY || JsonValue::parse_bytes(&input).is_err() {
        return None;
    }
    let url = format!(
        "{}/v1/claude/permission/ask",
        base_url.trim_end_matches('/')
    );
    let auth = format!("Bearer {token}");
    let (status, _, mut body) = http_request(
        "POST",
        &url,
        &[
            ("Content-Type", "application/json"),
            ("Authorization", &auth),
        ],
        Some(&input),
        HOOK_TOTAL_TIMEOUT,
    )
    .ok()?;
    if body.len() > MAX_REQUEST_BODY {
        body.truncate(MAX_REQUEST_BODY);
    }
    if status != 200 {
        return None;
    }
    let reply = JsonValue::parse_bytes(&body).ok()?;
    let decision = reply.get_opt_str("decision")?;
    let mut dec_map = JsonMap::new();
    match decision.as_str() {
        DECISION_ALLOW => {
            dec_map.insert(
                "behavior".to_string(),
                JsonValue::String(DECISION_ALLOW.to_string()),
            );
        }
        DECISION_DENY => {
            let raw_msg = reply.get_str("message").trim();
            let msg = if raw_msg.is_empty() {
                DEFAULT_DENY_MESSAGE.to_string()
            } else {
                raw_msg.to_string()
            };
            dec_map.insert(
                "behavior".to_string(),
                JsonValue::String(DECISION_DENY.to_string()),
            );
            dec_map.insert("message".to_string(), JsonValue::String(msg));
        }
        _ => return None,
    }

    let mut spec_map = JsonMap::new();
    spec_map.insert(
        "hookEventName".to_string(),
        JsonValue::String("PermissionRequest".to_string()),
    );
    spec_map.insert("decision".to_string(), JsonValue::Object(dec_map));

    let mut root_map = JsonMap::new();
    root_map.insert(
        "hookSpecificOutput".to_string(),
        JsonValue::Object(spec_map),
    );

    let mut out = JsonValue::Object(root_map).to_json_string();
    out.push('\n');
    Some(out.into_bytes())
}

pub fn run_permission_hook(args: &[String], stdin: impl Read, mut stdout: impl Write) {
    let mut config_dir = PathBuf::new();
    let mut i = 0;
    while i < args.len() {
        if args[i] == "--config-dir" && i + 1 < args.len() {
            config_dir = PathBuf::from(&args[i + 1]);
            i += 2;
        } else if let Some(val) = args[i].strip_prefix("--config-dir=") {
            config_dir = PathBuf::from(val);
            i += 1;
        } else {
            i += 1;
        }
    }
    let tok_path = Store::new(config_dir).hook_token_path();
    let tok = match std::fs::read_to_string(tok_path) {
        Ok(s) => s.trim().to_string(),
        Err(_) => return,
    };
    if let Some(out) = permission_hook_output(stdin, "http://127.0.0.1:9949", &tok) {
        let _ = stdout.write_all(&out);
    }
}

pub fn run_install_claude_hook(args: &[String]) -> Result<(), String> {
    let mut remove = false;
    let mut settings = String::new();
    let mut config_dir = String::new();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--remove" => {
                remove = true;
                i += 1;
            }
            "--settings" if i + 1 < args.len() => {
                settings = args[i + 1].clone();
                i += 2;
            }
            "--config-dir" if i + 1 < args.len() => {
                config_dir = args[i + 1].clone();
                i += 2;
            }
            s if s.starts_with("--settings=") => {
                settings = s.trim_start_matches("--settings=").to_string();
                i += 1;
            }
            s if s.starts_with("--config-dir=") => {
                config_dir = s.trim_start_matches("--config-dir=").to_string();
                i += 1;
            }
            _ => i += 1,
        }
    }
    let path = if settings.is_empty() {
        default_claude_settings()
    } else {
        expand_home(&settings)
    };
    let cmd = hook_command_line_for_dir(&config_dir)?;
    let msg = install_claude_hook(&path, remove, &cmd)?;
    println!("{msg}");
    Ok(())
}

pub fn default_claude_settings() -> PathBuf {
    expand_home("~/.claude/settings.json")
}

pub fn tilde_path(p: &str) -> String {
    if let Ok(home) = std::env::var("HOME") {
        if !home.is_empty() {
            let prefix = format!("{home}/");
            if let Some(rest) = p.strip_prefix(&prefix) {
                return format!("~/{rest}");
            }
        }
    }
    p.to_string()
}

pub fn hook_command_line() -> Result<String, String> {
    hook_command_line_for_dir("")
}

pub fn hook_command_line_for_dir(config_dir: &str) -> Result<String, String> {
    let exe =
        std::env::current_exe().map_err(|e| format!("cannot find this binary's path: {e}"))?;
    let real = std::fs::canonicalize(&exe).unwrap_or(exe);
    Ok(format_hook_command(&real.to_string_lossy(), config_dir))
}

pub fn format_hook_command(exe: &str, config_dir: &str) -> String {
    let base = format!("{} {}", shell_quote(exe), HOOK_VERB);
    let trimmed = config_dir.trim();
    if trimmed.is_empty() {
        return base;
    }
    let expanded = expand_home(trimmed);
    let cleaned = clean_path(&expanded);
    let def_cleaned = clean_path(&default_config_dir());
    if cleaned == def_cleaned {
        return base;
    }
    format!(
        "{base} --config-dir {}",
        shell_quote(&cleaned.to_string_lossy())
    )
}

fn clean_path(p: &Path) -> PathBuf {
    let s = p.to_string_lossy();
    let trimmed = s.trim_end_matches('/');
    if trimmed.is_empty() {
        PathBuf::from("/")
    } else {
        PathBuf::from(trimmed)
    }
}

pub fn shell_quote(s: &str) -> String {
    let safe = !s.is_empty()
        && s.chars()
            .all(|c| c.is_ascii_alphanumeric() || "/._-+".contains(c));
    if safe {
        return s.to_string();
    }
    format!("'{}'", s.replace('\'', r"'\''"))
}

pub fn is_our_hook(command: &str, ours: &str) -> bool {
    let c = command.trim();
    if c == ours {
        return true;
    }
    c.contains(HOOK_BINARY_NAME)
        && (c.ends_with(HOOK_VERB) || c.contains(&format!(" {HOOK_VERB} ")))
}

struct ClaudeSettingsFile {
    path: PathBuf,
    orig: Vec<u8>,
    existed: bool,
    perm: u32,
    settings: JsonMap,
    hooks: JsonMap,
    groups: Vec<JsonValue>,
}

fn read_claude_settings(path: &Path) -> Result<ClaudeSettingsFile, String> {
    let resolved = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let mut f = ClaudeSettingsFile {
        path: resolved.clone(),
        orig: Vec::new(),
        existed: false,
        perm: 0o600,
        settings: JsonMap::new(),
        hooks: JsonMap::new(),
        groups: Vec::new(),
    };

    match std::fs::read(&resolved) {
        Ok(orig) => {
            f.orig = orig;
            f.existed = true;
            #[cfg(unix)]
            if let Ok(meta) = std::fs::metadata(&resolved) {
                use std::os::unix::fs::PermissionsExt;
                f.perm = meta.permissions().mode() & 0o777;
            }
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => {
            return Err(format!(
                "cannot read {}; left it untouched: {e}",
                resolved.display()
            ))
        }
    }

    let trimmed_empty = f.orig.iter().all(|b| b.is_ascii_whitespace());
    if !trimmed_empty {
        let parsed = JsonValue::parse_bytes(&f.orig).map_err(|e| {
            format!(
                "{} is not a valid JSON object; left it untouched: {e}",
                resolved.display()
            )
        })?;
        match parsed {
            JsonValue::Object(m) => f.settings = m,
            _ => {
                return Err(format!(
                    "{} is not a valid JSON object; left it untouched: not an object",
                    resolved.display()
                ))
            }
        }
    }

    if let Some(v) = f.settings.get("hooks") {
        match v {
            JsonValue::Object(m) => f.hooks = m.clone(),
            _ => {
                return Err(format!(
                    r#"{}: "hooks" is not an object; left it untouched"#,
                    resolved.display()
                ))
            }
        }
    }

    if let Some(v) = f.hooks.get("PermissionRequest") {
        match v {
            JsonValue::Array(arr) => f.groups = arr.clone(),
            _ => {
                return Err(format!(
                    r#"{}: "hooks.PermissionRequest" is not an array; left it untouched"#,
                    resolved.display()
                ))
            }
        }
    }

    Ok(f)
}

pub fn claude_hook_installed(path: &Path, ours: &str) -> Result<bool, String> {
    let f = read_claude_settings(path)?;
    let (_, n, _) = without_our_hook(&f.groups, ours);
    Ok(n > 0)
}

pub fn install_claude_hook(path: &Path, remove: bool, ours: &str) -> Result<String, String> {
    let mut f = read_claude_settings(path)?;
    let (mut kept, removed, exact) = without_our_hook(&f.groups, ours);

    if remove {
        if removed == 0 {
            return Ok(format!(
                "the Vitruvian Remote permission hook is not in {}; nothing to remove",
                f.path.display()
            ));
        }
        f.set_groups(kept);
        f.write()?;
        return Ok(format!(
            "removed the Vitruvian Remote permission hook from {}{}",
            f.path.display(),
            f.backup_note()
        ));
    }

    if removed == 1 && exact {
        return Ok(format!(
            "the Vitruvian Remote permission hook is already in {}; nothing to do",
            f.path.display()
        ));
    }

    let mut hook_entry = JsonMap::new();
    hook_entry.insert("type".to_string(), JsonValue::String("command".to_string()));
    hook_entry.insert("command".to_string(), JsonValue::String(ours.to_string()));
    hook_entry.insert(
        "timeout".to_string(),
        JsonValue::from_i64(HOOK_TIMEOUT_SECONDS),
    );

    let mut group_entry = JsonMap::new();
    group_entry.insert("matcher".to_string(), JsonValue::String(String::new()));
    group_entry.insert(
        "hooks".to_string(),
        JsonValue::Array(vec![JsonValue::Object(hook_entry)]),
    );
    kept.push(JsonValue::Object(group_entry));

    f.set_groups(kept);
    f.write()?;

    let verb = if removed > 0 { "updated" } else { "added" };
    Ok(format!(
        "{verb} the Vitruvian Remote permission hook in {} ({ours}){}",
        f.path.display(),
        f.backup_note()
    ))
}

impl ClaudeSettingsFile {
    fn set_groups(&mut self, groups: Vec<JsonValue>) {
        if groups.is_empty() {
            self.hooks.remove("PermissionRequest");
        } else {
            self.hooks
                .insert("PermissionRequest".to_string(), JsonValue::Array(groups));
        }
        if self.hooks.is_empty() {
            self.settings.remove("hooks");
        } else {
            self.settings
                .insert("hooks".to_string(), JsonValue::Object(self.hooks.clone()));
        }
    }

    fn backup_note(&self) -> String {
        if !self.existed {
            String::new()
        } else {
            format!("; the previous file is at {}.bak", self.path.display())
        }
    }

    fn write(&self) -> Result<(), String> {
        let mut content = JsonValue::Object(self.settings.clone()).to_json_pretty();
        content.push('\n');

        if let Some(dir) = self.path.parent() {
            std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
        }
        if self.existed {
            let bak = PathBuf::from(format!("{}.bak", self.path.display()));
            std::fs::write(&bak, &self.orig).map_err(|e| format!("backup: {e}"))?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let _ = std::fs::set_permissions(&bak, std::fs::Permissions::from_mode(self.perm));
            }
        }
        let dir = self.path.parent().unwrap_or_else(|| Path::new("."));
        let base = self
            .path
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("settings.json");
        let tmp = dir.join(format!(".{base}.tmp-{}", std::process::id()));
        std::fs::write(&tmp, content.as_bytes()).map_err(|e| e.to_string())?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(self.perm));
        }
        std::fs::rename(&tmp, &self.path).map_err(|e| {
            let _ = std::fs::remove_file(&tmp);
            e.to_string()
        })?;
        Ok(())
    }
}

fn without_our_hook(groups: &[JsonValue], ours: &str) -> (Vec<JsonValue>, usize, bool) {
    let mut out = Vec::with_capacity(groups.len());
    let mut removed = 0;
    let mut exact = true;

    for g in groups {
        let gm = match g.as_object() {
            Some(m) => m,
            None => {
                out.push(g.clone());
                continue;
            }
        };
        let hs = match gm.get("hooks").and_then(|v| v.as_array()) {
            Some(a) => a,
            None => {
                out.push(g.clone());
                continue;
            }
        };
        let mut keep = Vec::with_capacity(hs.len());
        for h in hs {
            if let Some(hm) = h.as_object() {
                if let Some(c) = hm.get("command").and_then(|v| v.as_str()) {
                    if is_our_hook(c, ours) {
                        removed += 1;
                        exact = exact && c.trim() == ours;
                        continue;
                    }
                }
            }
            keep.push(h.clone());
        }
        if keep.len() == hs.len() {
            out.push(g.clone());
            continue;
        }
        if keep.is_empty() {
            continue;
        }
        let mut cp = gm.clone();
        cp.insert("hooks".to_string(), JsonValue::Array(keep));
        out.push(JsonValue::Object(cp));
    }

    (out, removed, exact)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::http_util::{HttpResponse, TestServer};
    use crate::permission::tests::{
        assert_same_json, PermAgent, BASH_ASK, EXISTING_SETTINGS, TEST_HOOK_COMMAND,
    };
    use std::io::Cursor;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use std::sync::{mpsc, Arc, Mutex};

    static NEXT_HOOK_DIR: AtomicUsize = AtomicUsize::new(0);

    fn temp_dir() -> PathBuf {
        let id = NEXT_HOOK_DIR.fetch_add(1, Ordering::SeqCst);
        let dir =
            std::env::temp_dir().join(format!("macagent-hook-test-{}-{}", std::process::id(), id));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn test_permission_hook_output() {
        let allow_out =
            "{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"}}}\n";
        let cases = [
            ("allow", 200u16, r#"{"decision":"allow"}"#, allow_out),
            (
                "deny with a message",
                200,
                r#"{"decision":"deny","message":"not on main & not <now>"}"#,
                "{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"deny\",\"message\":\"not on main & not <now>\"}}}\n",
            ),
            (
                "deny without one",
                200,
                r#"{"decision":"deny"}"#,
                "{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"deny\",\"message\":\"Denied from the phone\"}}}\n",
            ),
            ("ask", 200, r#"{"decision":"ask"}"#, ""),
            ("an unknown decision", 200, r#"{"decision":"maybe"}"#, ""),
            ("garbage", 200, r#"{"decision":"#, ""),
            ("a 401", 401, r#"{"error":"no"}"#, ""),
            ("a 500 that says allow", 500, r#"{"decision":"allow"}"#, ""),
        ];

        for (name, status, reply, want) in cases {
            let got_auth = Arc::new(Mutex::new(String::new()));
            let got_body = Arc::new(Mutex::new(String::new()));
            let ga = Arc::clone(&got_auth);
            let gb = Arc::clone(&got_body);
            let rep = reply.to_string();

            let srv = TestServer::start(move |req: &crate::http_util::HttpRequest| {
                assert_eq!(req.path, "/v1/claude/permission/ask");
                assert_eq!(req.method, "POST");
                *ga.lock().unwrap() = req.header("Authorization").to_string();
                *gb.lock().unwrap() = String::from_utf8_lossy(&req.body).to_string();
                HttpResponse::new(status, rep.as_bytes().to_vec())
                    .with_header("Content-Type", "application/json")
            });

            let out = permission_hook_output(Cursor::new(BASH_ASK), &srv.url(), "tok")
                .unwrap_or_default();
            assert_eq!(String::from_utf8_lossy(&out), want, "{name}");
            assert_eq!(*got_auth.lock().unwrap(), "Bearer tok", "{name}");
            assert_eq!(*got_body.lock().unwrap(), BASH_ASK, "{name}");
        }
    }

    #[test]
    fn test_permission_hook_falls_through_when_the_agent_is_down() {
        let out = permission_hook_output(Cursor::new(BASH_ASK), "http://127.0.0.1:1", "tok");
        assert!(out.is_none());

        let called = Arc::new(AtomicBool::new(false));
        let c2 = Arc::clone(&called);
        let srv = TestServer::start(move |_: &crate::http_util::HttpRequest| {
            c2.store(true, Ordering::SeqCst);
            HttpResponse::new(200, br#"{"decision":"allow"}"#.to_vec())
        });
        assert!(permission_hook_output(Cursor::new(BASH_ASK), &srv.url(), "").is_none());
        assert!(!called.load(Ordering::SeqCst));

        assert!(permission_hook_output(Cursor::new("not json"), &srv.url(), "tok").is_none());
        assert!(!called.load(Ordering::SeqCst));
    }

    #[test]
    fn test_run_permission_hook_without_a_token_prints_nothing() {
        let dir = temp_dir();
        let mut out = Vec::new();
        run_permission_hook(
            &[
                "--config-dir".to_string(),
                dir.to_string_lossy().to_string(),
                "--unknown-flag".to_string(),
            ],
            Cursor::new(BASH_ASK),
            &mut out,
        );
        assert!(out.is_empty());
    }

    #[test]
    fn test_permission_hook_against_the_real_agent() {
        let a = PermAgent::new(Duration::from_secs(5));
        let (tx, rx) = mpsc::sync_channel(1);
        let url = a.server.url().to_string();
        let tok = a.hook_tok.clone();
        std::thread::spawn(move || {
            let out = permission_hook_output(Cursor::new(BASH_ASK), &url, &tok);
            let _ = tx.send(out);
        });
        a.wait_pending(1);
        a.do_act(
            "POST",
            "/v1/claude/permissions/decide",
            r#"{"id":"p-1","decision":"allow"}"#,
        );
        let out = rx
            .recv_timeout(Duration::from_secs(5))
            .unwrap()
            .expect("expected output");
        let s = String::from_utf8(out).unwrap();
        assert!(JsonValue::parse_bytes(s.as_bytes()).is_ok());
        assert!(s.contains(r#""behavior":"allow""#));
    }

    #[test]
    fn test_install_claude_hook_add_idempotent_remove() {
        let dir = temp_dir();
        let path = dir.join("settings.json");
        std::fs::write(&path, EXISTING_SETTINGS).unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).unwrap();
        }

        let msg = install_claude_hook(&path, false, TEST_HOOK_COMMAND).unwrap();
        assert!(msg.starts_with("added"), "{msg}");
        let added = std::fs::read_to_string(&path).unwrap();
        let parsed = JsonValue::parse_bytes(added.as_bytes()).unwrap();
        let pr = parsed
            .get("hooks")
            .unwrap()
            .get_array("PermissionRequest")
            .unwrap();
        assert_eq!(pr.len(), 1);
        assert_eq!(pr[0].get_str("matcher"), "");
        let hs = pr[0].get_array("hooks").unwrap();
        assert_eq!(hs.len(), 1);
        assert_eq!(hs[0].get_str("type"), "command");
        assert_eq!(hs[0].get_str("command"), TEST_HOOK_COMMAND);
        assert_eq!(hs[0].get_i64("timeout"), 150);

        for keep in [
            r#""speaker-broadcast done && echo <ok>""#,
            r#""~/bin/log-prompt""#,
            "12345678901234567890",
            r#""Bash(ls:*)""#,
            r#""model": "opus""#,
        ] {
            assert!(added.contains(keep), "lost {keep} in:\n{added}");
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let perm = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
            assert_eq!(perm, 0o600);
        }
        let bak = std::fs::read_to_string(format!("{}.bak", path.display())).unwrap();
        assert_eq!(bak, EXISTING_SETTINGS);
        assert!(claude_hook_installed(&path, TEST_HOOK_COMMAND).unwrap());

        let msg = install_claude_hook(&path, false, TEST_HOOK_COMMAND).unwrap();
        assert!(msg.contains("already"));
        let again = std::fs::read_to_string(&path).unwrap();
        assert_eq!(again, added);

        let msg = install_claude_hook(&path, true, TEST_HOOK_COMMAND).unwrap();
        assert!(msg.starts_with("removed"));
        assert_same_json(&path, EXISTING_SETTINGS);
        assert!(!claude_hook_installed(&path, TEST_HOOK_COMMAND).unwrap());

        let msg = install_claude_hook(&path, true, TEST_HOOK_COMMAND).unwrap();
        assert!(msg.contains("nothing to remove"));
    }

    #[test]
    fn test_install_claude_hook_replaces_a_stale_entry_and_keeps_others() {
        let dir = temp_dir();
        let path = dir.join("settings.json");
        let stale = r#"{"hooks":{"PermissionRequest":[{"matcher":"","hooks":[{"type":"command","command":"~/.local/bin/vitruvian-remote-agent permission-hook","timeout":150},{"type":"command","command":"my-own-audit-hook"}]}]}}"#;
        std::fs::write(&path, stale).unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o644)).unwrap();
        }
        assert!(claude_hook_installed(&path, TEST_HOOK_COMMAND).unwrap());

        let msg = install_claude_hook(&path, false, TEST_HOOK_COMMAND).unwrap();
        assert!(msg.starts_with("updated"), "{msg}");
        let b = std::fs::read_to_string(&path).unwrap();
        assert_eq!(b.matches("permission-hook").count(), 1);
        assert!(b.contains(TEST_HOOK_COMMAND));
        assert!(b.contains("my-own-audit-hook"));
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let perm = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
            assert_eq!(perm, 0o644);
        }
        install_claude_hook(&path, true, TEST_HOOK_COMMAND).unwrap();
        assert_same_json(
            &path,
            r#"{"hooks":{"PermissionRequest":[{"matcher":"","hooks":[{"type":"command","command":"my-own-audit-hook"}]}]}}"#,
        );
    }

    #[test]
    fn test_install_claude_hook_creates_the_file() {
        let dir = temp_dir();
        let path = dir.join("nested").join("settings.json");
        install_claude_hook(&path, false, TEST_HOOK_COMMAND).unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let perm = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
            assert_eq!(perm, 0o600);
        }
        assert!(!Path::new(&format!("{}.bak", path.display())).exists());
        install_claude_hook(&path, true, TEST_HOOK_COMMAND).unwrap();
        assert_same_json(&path, "{}");
    }

    #[test]
    fn test_install_claude_hook_follows_a_symlink() {
        let dir = temp_dir();
        let target = dir.join("dotfiles-settings.json");
        let link = dir.join("settings.json");
        std::fs::write(&target, "{}").unwrap();
        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(&target, &link).unwrap();
            install_claude_hook(&link, false, TEST_HOOK_COMMAND).unwrap();
            let meta = std::fs::symlink_metadata(&link).unwrap();
            assert!(meta.file_type().is_symlink());
            let b = std::fs::read_to_string(&target).unwrap();
            assert!(b.contains(TEST_HOOK_COMMAND));
        }
    }

    #[test]
    fn test_shell_quote_and_is_our_hook() {
        assert_eq!(
            shell_quote("/Users/j/.local/bin/vitruvian-remote-agent"),
            "/Users/j/.local/bin/vitruvian-remote-agent"
        );
        assert_eq!(
            shell_quote("/Users/j/My Apps/it's"),
            r"'/Users/j/My Apps/it'\''s'"
        );
        let cases = [
            (TEST_HOOK_COMMAND, true),
            ("~/.local/bin/vitruvian-remote-agent permission-hook", true),
            ("'/Users/j/My Apps/vitruvian-remote-agent' permission-hook", true),
            (
                "'/Users/j/Library/Application Support/com.vitruviansoftware.vitruvian/Tools/dev.vitruvian.remote/bin/vitruvian-remote-agent' permission-hook --config-dir '/Users/j/Library/Application Support/com.vitruviansoftware.vitruvian/ToolData/dev.vitruvian.remote/config'",
                true,
            ),
            ("vitruvian-remote-agent token", false),
            ("other-tool permission-hook", false),
            ("speaker-broadcast done", false),
        ];
        for (c, want) in cases {
            assert_eq!(is_our_hook(c, TEST_HOOK_COMMAND), want, "{c}");
        }
    }

    #[test]
    fn test_format_hook_command_and_extension_replacement() {
        let standalone_exe = "/Users/j/.local/bin/vitruvian-remote-agent";
        let ext_exe = "/Users/j/Library/Application Support/com.vitruviansoftware.vitruvian/Tools/dev.vitruvian.remote/bin/vitruvian-remote-agent";
        let ext_cfg = "/Users/j/Library/Application Support/com.vitruviansoftware.vitruvian/ToolData/dev.vitruvian.remote/config";

        assert_eq!(
            format_hook_command(standalone_exe, ""),
            format!("{standalone_exe} permission-hook")
        );
        assert_eq!(
            format_hook_command(standalone_exe, &default_config_dir().to_string_lossy()),
            format!("{standalone_exe} permission-hook")
        );
        let ext_cmd = format_hook_command(ext_exe, ext_cfg);
        let want_ext_cmd = format!("'{ext_exe}' permission-hook --config-dir '{ext_cfg}'");
        assert_eq!(ext_cmd, want_ext_cmd);

        let dir = temp_dir();
        let path = dir.join("settings.json");
        install_claude_hook(&path, false, &format!("{standalone_exe} permission-hook")).unwrap();
        let msg = install_claude_hook(&path, false, &ext_cmd).unwrap();
        assert!(msg.starts_with("updated"));
        let b = std::fs::read_to_string(&path).unwrap();
        assert_eq!(b.matches("permission-hook").count(), 1);
        assert!(b.contains(&ext_cmd));

        let msg = install_claude_hook(&path, false, &format!("{standalone_exe} permission-hook"))
            .unwrap();
        assert!(msg.starts_with("updated"));
        let b2 = std::fs::read_to_string(&path).unwrap();
        assert_eq!(b2.matches("permission-hook").count(), 1);
        assert!(!b2.contains("--config-dir"));
    }
}
