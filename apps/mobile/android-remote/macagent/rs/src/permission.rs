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

use std::collections::HashMap;
use std::path::Path;
use std::sync::mpsc::{self, Receiver, SyncSender};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use vitruvian_remote_macagent_metrics::json::{JsonMap, JsonValue};
use vitruvian_remote_macagent_metrics::time_util::Timestamp;

use crate::hook::{claude_hook_installed, install_claude_hook, tilde_path};
use crate::http_util::{log_act, HttpRequest, HttpResponse};
use crate::mcp::loopback_gate;
use crate::notify::Notifier;
use crate::pair::Store;

pub const PERMISSION_WAIT_DEFAULT: Duration = Duration::from_secs(120);
pub const PERMISSION_WAIT_MIN: Duration = Duration::from_secs(5);
pub const PERMISSION_WAIT_MAX: Duration = Duration::from_secs(140);
pub const MAX_PENDING_PERMISSIONS: usize = 64;
pub const SUMMARY_MAX_RUNES: usize = 120;
pub const DETAIL_MAX_BYTES: usize = 4 << 10;
pub const DENY_MESSAGE_MAX_RUNES: usize = 300;
pub const DEFAULT_DENY_MESSAGE: &str = "Denied from the phone";

pub const DECISION_ALLOW: &str = "allow";
pub const DECISION_DENY: &str = "deny";
pub const DECISION_ASK: &str = "ask";

pub fn clamp_permission_wait(d: Duration) -> Duration {
    if d < PERMISSION_WAIT_MIN {
        PERMISSION_WAIT_MIN
    } else if d > PERMISSION_WAIT_MAX {
        PERMISSION_WAIT_MAX
    } else {
        d
    }
}

static PERMISSION_WAIT: Mutex<Duration> = Mutex::new(PERMISSION_WAIT_DEFAULT);

pub fn set_permission_wait(d: Duration) {
    if let Ok(mut g) = PERMISSION_WAIT.lock() {
        *g = d;
    }
}

pub fn get_permission_wait() -> Duration {
    PERMISSION_WAIT
        .lock()
        .map(|g| *g)
        .unwrap_or(PERMISSION_WAIT_DEFAULT)
}

pub fn log_permission_wait(requested: Duration, clamped: Duration) {
    if requested != clamped {
        crate::http_util::log_line(&format!(
            "permission-wait {:?} clamped to {:?}",
            requested, clamped
        ));
    }
}

#[derive(Debug, Clone)]
pub struct PermissionRequest {
    pub id: String,
    pub session_id: String,
    pub project: String,
    pub cwd: String,
    pub tool: String,
    pub summary: String,
    pub detail: String,
    pub created_at: Timestamp,
    pub expires_at: Timestamp,
    pub expires_instant: Instant,
}

impl PermissionRequest {
    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("id".to_string(), JsonValue::String(self.id.clone()));
        m.insert(
            "session_id".to_string(),
            JsonValue::String(self.session_id.clone()),
        );
        m.insert(
            "project".to_string(),
            JsonValue::String(self.project.clone()),
        );
        m.insert("cwd".to_string(), JsonValue::String(self.cwd.clone()));
        m.insert("tool".to_string(), JsonValue::String(self.tool.clone()));
        m.insert(
            "summary".to_string(),
            JsonValue::String(self.summary.clone()),
        );
        m.insert("detail".to_string(), JsonValue::String(self.detail.clone()));
        m.insert(
            "created_at".to_string(),
            JsonValue::String(self.created_at.to_rfc3339_nano()),
        );
        m.insert(
            "expires_at".to_string(),
            JsonValue::String(self.expires_at.to_rfc3339_nano()),
        );
        JsonValue::Object(m)
    }
}

#[derive(Debug, Clone)]
pub struct PermissionAnswer {
    pub decision: String,
    pub message: String,
}

struct PendingPermission {
    req: PermissionRequest,
    tx: SyncSender<PermissionAnswer>,
}

struct BrokerState {
    next_id: i64,
    order: Vec<String>,
    pending: HashMap<String, PendingPermission>,
}

#[derive(Clone)]
pub struct PermissionBroker {
    state: Arc<Mutex<BrokerState>>,
}

impl PermissionBroker {
    pub fn new() -> Self {
        Self {
            state: Arc::new(Mutex::new(BrokerState {
                next_id: 0,
                order: Vec::new(),
                pending: HashMap::new(),
            })),
        }
    }

    pub fn add(
        &self,
        mut req: PermissionRequest,
    ) -> Option<(PermissionRequest, Receiver<PermissionAnswer>)> {
        let mut st = self.state.lock().unwrap();
        if st.pending.len() >= MAX_PENDING_PERMISSIONS {
            return None;
        }
        st.next_id += 1;
        req.id = format!("p-{}", st.next_id);
        let (tx, rx) = mpsc::sync_channel(1);
        st.order.push(req.id.clone());
        st.pending.insert(
            req.id.clone(),
            PendingPermission {
                req: req.clone(),
                tx,
            },
        );
        Some((req, rx))
    }

    fn take_locked(st: &mut BrokerState, id: &str) -> Option<PendingPermission> {
        let p = st.pending.remove(id)?;
        if let Some(pos) = st.order.iter().position(|x| x == id) {
            st.order.remove(pos);
        }
        Some(p)
    }

    pub fn drop_req(&self, id: &str) -> bool {
        let mut st = self.state.lock().unwrap();
        Self::take_locked(&mut st, id).is_some()
    }

    pub fn answer(&self, id: &str, a: PermissionAnswer, now: Instant) -> Option<PermissionRequest> {
        let mut st = self.state.lock().unwrap();
        let p = st.pending.get(id)?;
        if now >= p.req.expires_instant {
            return None;
        }
        let p = Self::take_locked(&mut st, id)?;
        let _ = p.tx.send(a);
        Some(p.req)
    }

    pub fn list(&self, now: Instant) -> Vec<PermissionRequest> {
        let st = self.state.lock().unwrap();
        let mut out = Vec::with_capacity(st.order.len());
        for id in &st.order {
            if let Some(p) = st.pending.get(id) {
                if now < p.req.expires_instant {
                    out.push(p.req.clone());
                }
            }
        }
        out
    }

    pub fn len(&self) -> usize {
        self.state.lock().unwrap().pending.len()
    }
}

impl Default for PermissionBroker {
    fn default() -> Self {
        Self::new()
    }
}

pub fn permission_summary(tool: &str, input_raw: &str) -> String {
    let parsed = JsonValue::parse_bytes(input_raw.as_bytes()).ok();
    let get_str = |k: &str| -> String {
        parsed
            .as_ref()
            .map(|v| v.get_str(k))
            .unwrap_or("")
            .trim()
            .to_string()
    };

    let mut s = match tool {
        "Bash" => get_str("command"),
        "Edit" | "Write" | "MultiEdit" | "NotebookEdit" => {
            let fp = get_str("file_path");
            if !fp.is_empty() {
                format!("edit {fp}")
            } else {
                let np = get_str("notebook_path");
                if !np.is_empty() {
                    format!("edit {np}")
                } else {
                    String::new()
                }
            }
        }
        "WebFetch" => get_str("url"),
        _ => String::new(),
    };

    if s.is_empty() {
        let compact = compact_json(input_raw);
        let combined = format!("{tool} {compact}");
        s = combined.trim().to_string();
    }

    let collapsed = s.split_whitespace().collect::<Vec<_>>().join(" ");
    truncate_runes(&collapsed, SUMMARY_MAX_RUNES)
}

pub fn permission_detail(tool: &str, input_raw: &str) -> String {
    let parsed = JsonValue::parse_bytes(input_raw.as_bytes()).ok();
    let mut d = String::new();
    if tool == "Bash" {
        if let Some(cmd) = parsed.as_ref().and_then(|v| v.get_opt_str("command")) {
            if !cmd.trim().is_empty() {
                d = cmd;
            }
        }
    }
    if d.is_empty() {
        if let Some(v) = parsed {
            if !input_raw.trim().is_empty() {
                d = v.to_json_pretty();
            }
        }
    }
    truncate_bytes(&d, DETAIL_MAX_BYTES)
}

fn compact_json(raw: &str) -> String {
    if raw.trim().is_empty() {
        return String::new();
    }
    match JsonValue::parse_bytes(raw.as_bytes()) {
        Ok(v) => v.to_json_string(),
        Err(_) => String::new(),
    }
}

pub fn truncate_runes(s: &str, n: usize) -> String {
    let count = s.chars().count();
    if count <= n {
        return s.to_string();
    }
    if n == 0 {
        return String::new();
    }
    let prefix: String = s.chars().take(n - 1).collect();
    format!("{prefix}…")
}

pub fn truncate_bytes(s: &str, n: usize) -> String {
    if s.len() <= n {
        return s.to_string();
    }
    let ell = "…";
    if n < ell.len() {
        return String::new();
    }
    let mut cut = n - ell.len();
    while cut > 0 && !s.is_char_boundary(cut) {
        cut -= 1;
    }
    format!("{}{}", &s[..cut], ell)
}

fn ask_reply(a: PermissionAnswer) -> HttpResponse {
    let mut m = JsonMap::new();
    m.insert(
        "decision".to_string(),
        JsonValue::String(a.decision.clone()),
    );
    if a.decision == DECISION_DENY && !a.message.is_empty() {
        m.insert("message".to_string(), JsonValue::String(a.message));
    }
    HttpResponse::json(200, &JsonValue::Object(m))
}

pub fn handle_permission_ask(
    req: &HttpRequest,
    store: &Store,
    perms: &PermissionBroker,
    permission_wait: Duration,
    notifier: Option<&Notifier>,
) -> HttpResponse {
    if req.method != "POST" {
        return HttpResponse::method_not_allowed("POST");
    }
    if let Err(resp) = loopback_gate(
        req,
        |tok| store.hook_authorized(tok),
        "vitruvian-remote-hook",
        "the permission hook endpoint is loopback-only",
        "send the token in ~/.config/vitruvian-remote-agent/hook-token as a bearer",
    ) {
        return resp;
    }

    let parsed = match req.json() {
        Ok(v) => v,
        Err(e) => return HttpResponse::error(400, &e),
    };
    let tool_name = parsed.get_str("tool_name").trim().to_string();
    if tool_name.is_empty() {
        return HttpResponse::error(400, "tool_name is required");
    }
    let session_id = parsed.get_str("session_id").to_string();
    let cwd = parsed.get_str("cwd").to_string();
    let tool_input_raw = parsed
        .get("tool_input")
        .map(|v| v.to_json_string())
        .unwrap_or_default();

    let now_ts = Timestamp::now();
    let now_inst = Instant::now();
    let expires_ts =
        Timestamp::from_unix_nanos(now_ts.unix_nanos() + permission_wait.as_nanos() as i128);
    let expires_inst = now_inst + permission_wait;

    let project = if !cwd.is_empty() {
        Path::new(&cwd)
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("")
            .to_string()
    } else {
        String::new()
    };

    let (parked, rx) = match perms.add(PermissionRequest {
        id: String::new(),
        session_id,
        project,
        cwd,
        tool: tool_name.clone(),
        summary: permission_summary(&tool_name, &tool_input_raw),
        detail: permission_detail(&tool_name, &tool_input_raw),
        created_at: now_ts,
        expires_at: expires_ts,
        expires_instant: expires_inst,
    }) {
        Some(v) => v,
        None => {
            return ask_reply(PermissionAnswer {
                decision: DECISION_ASK.to_string(),
                message: String::new(),
            })
        }
    };

    if let Some(n) = notifier {
        let n_clone = n.clone();
        let req_clone = parked.clone();
        std::thread::spawn(move || {
            let body = if !req_clone.project.is_empty() {
                format!("{} · {}", req_clone.project, req_clone.summary)
            } else {
                req_clone.summary.clone()
            };
            n_clone.notify(
                &format!("claude-permission-{}", req_clone.id),
                &format!("Claude wants to: {}", req_clone.tool),
                &body,
                "high",
                "question",
                "vitruvian-remote://apps/claude",
            );
        });
    }

    loop {
        if req.cancel.is_cancelled() {
            perms.drop_req(&parked.id);
            return ask_reply(PermissionAnswer {
                decision: DECISION_ASK.to_string(),
                message: String::new(),
            });
        }
        let now = Instant::now();
        if now >= expires_inst {
            if perms.drop_req(&parked.id) {
                return ask_reply(PermissionAnswer {
                    decision: DECISION_ASK.to_string(),
                    message: String::new(),
                });
            }
            if let Ok(a) = rx.recv_timeout(Duration::from_millis(50)) {
                return ask_reply(a);
            }
            return ask_reply(PermissionAnswer {
                decision: DECISION_ASK.to_string(),
                message: String::new(),
            });
        }
        let rem = expires_inst
            .duration_since(now)
            .min(Duration::from_millis(10));
        match rx.recv_timeout(rem) {
            Ok(a) => return ask_reply(a),
            Err(mpsc::RecvTimeoutError::Timeout) => continue,
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                perms.drop_req(&parked.id);
                return ask_reply(PermissionAnswer {
                    decision: DECISION_ASK.to_string(),
                    message: String::new(),
                });
            }
        }
    }
}

pub fn handle_permission_list(
    req: &HttpRequest,
    perms: &PermissionBroker,
    permission_wait: Duration,
    claude_settings: &Path,
    hook_command: &str,
) -> HttpResponse {
    if req.method != "GET" {
        return HttpResponse::method_not_allowed("GET");
    }
    let on = claude_hook_installed(claude_settings, hook_command).unwrap_or(false);
    let pending: Vec<JsonValue> = perms
        .list(Instant::now())
        .into_iter()
        .map(|p| p.to_json_value())
        .collect();
    let mut m = JsonMap::new();
    m.insert("enabled".to_string(), JsonValue::Bool(on));
    m.insert(
        "wait_seconds".to_string(),
        JsonValue::from_i64(permission_wait.as_secs() as i64),
    );
    m.insert("pending".to_string(), JsonValue::Array(pending));
    HttpResponse::json(200, &JsonValue::Object(m))
}

pub fn handle_permission_enabled(
    req: &HttpRequest,
    claude_settings: &Path,
    hook_command: &str,
) -> HttpResponse {
    if req.method != "POST" {
        return HttpResponse::method_not_allowed("POST");
    }
    let parsed = match req.json() {
        Ok(v) => v,
        Err(e) => return HttpResponse::error(400, &e),
    };
    let enabled = match parsed.get_opt_bool("enabled") {
        Some(b) => b,
        None => return HttpResponse::error(400, r#""enabled" is required (true or false)"#),
    };
    if enabled && hook_command.is_empty() {
        return HttpResponse::error(
            500,
            "cannot find this agent's own path to write into the hook command",
        );
    }
    if let Err(e) = install_claude_hook(claude_settings, !enabled, hook_command) {
        return HttpResponse::error(500, &e);
    }
    log_act("claude", &format!("hook enabled {enabled}"));
    let on = match claude_hook_installed(claude_settings, hook_command) {
        Ok(b) => b,
        Err(e) => return HttpResponse::error(500, &e),
    };
    let mut m = JsonMap::new();
    m.insert("enabled".to_string(), JsonValue::Bool(on));
    m.insert(
        "settings_path".to_string(),
        JsonValue::String(tilde_path(&claude_settings.to_string_lossy())),
    );
    HttpResponse::json(200, &JsonValue::Object(m))
}

pub fn handle_permission_decide(req: &HttpRequest, perms: &PermissionBroker) -> HttpResponse {
    if req.method != "POST" {
        return HttpResponse::method_not_allowed("POST");
    }
    let parsed = match req.json() {
        Ok(v) => v,
        Err(e) => return HttpResponse::error(400, &e),
    };
    let id = parsed.get_str("id");
    let decision = parsed.get_str("decision");
    let message = parsed.get_str("message");
    if decision != DECISION_ALLOW && decision != DECISION_DENY {
        return HttpResponse::error(400, r#"decision must be "allow" or "deny""#);
    }
    let a = PermissionAnswer {
        decision: decision.to_string(),
        message: if decision == DECISION_DENY {
            truncate_runes(message.trim(), DENY_MESSAGE_MAX_RUNES)
        } else {
            String::new()
        },
    };
    let parked = match perms.answer(id, a, Instant::now()) {
        Some(p) => p,
        None => {
            return HttpResponse::error(
                404,
                "no such pending request (unknown, already answered, or expired)",
            )
        }
    };
    log_act(
        "claude",
        &format!("{decision} {} in {}", parked.tool, parked.project),
    );
    HttpResponse::json(200, &JsonValue::Object(JsonMap::new()))
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use crate::http_util::{http_request, parse_bearer, CancelToken, LogCapture, TestServer};
    use std::collections::BTreeMap;
    use std::io::Write;
    use std::net::TcpStream;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicUsize, Ordering};

    pub const TEST_HOOK_COMMAND: &str = "/opt/test/vitruvian-remote-agent permission-hook";
    pub const BASH_ASK: &str = r#"{"session_id":"s-1","cwd":"/Users/alice/src/acme","tool_name":"Bash","tool_input":{"command":"rm -rf build && make SECRET_ARG"},"transcript_path":"/t.jsonl","hook_event_name":"PermissionRequest"}"#;

    pub const EXISTING_SETTINGS: &str = "{\n  \"model\": \"opus\",\n  \"permissions\": {\"allow\": [\"Bash(ls:*)\"]},\n  \"hooks\": {\n    \"Stop\": [{\"matcher\": \"\", \"hooks\": [{\"type\": \"command\", \"command\": \"speaker-broadcast done && echo <ok>\", \"timeout\": 10}]}],\n    \"UserPromptSubmit\": [{\"hooks\": [{\"type\": \"command\", \"command\": \"~/bin/log-prompt\"}]}]\n  },\n  \"big\": 12345678901234567890\n}\n";

    static NEXT_PERM_DIR: AtomicUsize = AtomicUsize::new(0);

    fn temp_dir() -> PathBuf {
        let id = NEXT_PERM_DIR.fetch_add(1, Ordering::SeqCst);
        let dir =
            std::env::temp_dir().join(format!("macagent-perm-test-{}-{}", std::process::id(), id));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    pub struct PermAgent {
        pub store: Store,
        pub perms: PermissionBroker,
        pub permission_wait: Duration,
        pub settings: PathBuf,
        pub hook_command: String,
        pub act_tok: String,
        pub hook_tok: String,
        pub server: TestServer,
    }

    impl PermAgent {
        pub fn new(wait: Duration) -> Self {
            let dir = temp_dir();
            let store = Store::new(dir.join("store"));
            let act_tok = store.ensure_token().unwrap();
            let hook_tok = store.ensure_hook_token().unwrap();
            let perms = PermissionBroker::new();
            let settings = dir.join("settings.json");
            let hook_command = TEST_HOOK_COMMAND.to_string();

            let s_store = store.clone();
            let s_perms = perms.clone();
            let s_settings = settings.clone();
            let s_cmd = hook_command.clone();

            let server = TestServer::start(move |req: &HttpRequest| {
                Self::route(req, &s_store, &s_perms, wait, &s_settings, &s_cmd)
            });

            Self {
                store,
                perms,
                permission_wait: wait,
                settings,
                hook_command,
                act_tok,
                hook_tok,
                server,
            }
        }

        pub fn route(
            req: &HttpRequest,
            store: &Store,
            perms: &PermissionBroker,
            wait: Duration,
            settings: &Path,
            hook_command: &str,
        ) -> HttpResponse {
            if req.path == "/v1/claude/permission/ask" {
                return handle_permission_ask(req, store, perms, wait, None);
            }
            // Act tier check
            let tok = match parse_bearer(req) {
                Some(t) => t,
                None => {
                    return HttpResponse::error(401, "missing bearer token")
                        .with_header("WWW-Authenticate", r#"Bearer realm="vitruvian-remote""#)
                }
            };
            if !store.authorized(tok) {
                return HttpResponse::error(403, "invalid bearer token");
            }
            match req.path.as_str() {
                "/v1/claude/permissions" => {
                    handle_permission_list(req, perms, wait, settings, hook_command)
                }
                "/v1/claude/permissions/enabled" => {
                    handle_permission_enabled(req, settings, hook_command)
                }
                "/v1/claude/permissions/decide" => handle_permission_decide(req, perms),
                _ => HttpResponse::error(404, "not found"),
            }
        }

        pub fn ask(&self, body: &str) -> Receiver<(u16, JsonValue)> {
            let (tx, rx) = mpsc::sync_channel(1);
            let url = format!("{}/v1/claude/permission/ask", self.server.url());
            let tok = self.hook_tok.clone();
            let b = body.as_bytes().to_vec();
            std::thread::spawn(move || {
                let auth = format!("Bearer {tok}");
                let (status, _, resp_body) = http_request(
                    "POST",
                    &url,
                    &[
                        ("Authorization", &auth),
                        ("Content-Type", "application/json"),
                    ],
                    Some(&b),
                    Duration::from_secs(10),
                )
                .unwrap();
                let j = JsonValue::parse_bytes(&resp_body).unwrap_or(JsonValue::Null);
                let _ = tx.send((status, j));
            });
            rx
        }

        pub fn do_act(&self, method: &str, path: &str, body: &str) -> (u16, JsonValue) {
            let url = format!("{}{}", self.server.url(), path);
            let auth = format!("Bearer {}", self.act_tok);
            let b = if body.is_empty() {
                None
            } else {
                Some(body.as_bytes())
            };
            let (status, _, resp_body) = http_request(
                method,
                &url,
                &[("Authorization", &auth)],
                b,
                Duration::from_secs(5),
            )
            .unwrap();
            let j = JsonValue::parse_bytes(&resp_body).unwrap_or(JsonValue::Null);
            (status, j)
        }

        pub fn wait_pending(&self, n: usize) -> Vec<JsonValue> {
            let deadline = Instant::now() + Duration::from_secs(5);
            while Instant::now() < deadline {
                let (_, m) = self.do_act("GET", "/v1/claude/permissions", "");
                if let Some(arr) = m.get_array("pending") {
                    if arr.len() == n {
                        return arr.to_vec();
                    }
                }
                std::thread::sleep(Duration::from_millis(5));
            }
            panic!("never saw {n} pending");
        }
    }

    pub fn normalize_json(v: &JsonValue) -> String {
        match v {
            JsonValue::Null => "null".to_string(),
            JsonValue::Bool(b) => b.to_string(),
            JsonValue::Number(n) => n.clone(),
            JsonValue::String(s) => JsonValue::String(s.clone()).to_json_string(),
            JsonValue::Array(arr) => {
                let items: Vec<String> = arr.iter().map(normalize_json).collect();
                format!("[{}]", items.join(","))
            }
            JsonValue::Object(m) => {
                let mut sorted = BTreeMap::new();
                for (k, val) in m.iter() {
                    sorted.insert(k.clone(), normalize_json(val));
                }
                let items: Vec<String> = sorted
                    .into_iter()
                    .map(|(k, v)| format!("{}:{}", JsonValue::String(k).to_json_string(), v))
                    .collect();
                format!("{{{}}}", items.join(","))
            }
        }
    }

    pub fn assert_same_json(path: &Path, want: &str) {
        let b = std::fs::read_to_string(path).unwrap();
        let got_v = JsonValue::parse_bytes(b.as_bytes()).unwrap();
        let want_v = JsonValue::parse_bytes(want.as_bytes()).unwrap();
        assert_eq!(normalize_json(&got_v), normalize_json(&want_v));
    }

    #[test]
    fn test_permission_ask_decide_round_trip() {
        let cases = [
            ("allow", r#""decision":"allow""#, "allow", ""),
            (
                "deny with a reason",
                r#""decision":"deny","message":"not on main""#,
                "deny",
                "not on main",
            ),
            ("deny without one", r#""decision":"deny""#, "deny", ""),
        ];
        for (name, decide, want_decision, want_message) in cases {
            let logs = LogCapture::new();
            let a = PermAgent::new(Duration::from_secs(5));
            let got = a.ask(BASH_ASK);

            let pending = a.wait_pending(1);
            let p = &pending[0];
            assert_eq!(p.get_str("id"), "p-1", "{name}");
            assert_eq!(p.get_str("session_id"), "s-1", "{name}");
            assert_eq!(p.get_str("project"), "acme", "{name}");
            assert_eq!(p.get_str("cwd"), "/Users/alice/src/acme", "{name}");
            assert_eq!(p.get_str("tool"), "Bash", "{name}");
            assert_eq!(
                p.get_str("summary"),
                "rm -rf build && make SECRET_ARG",
                "{name}"
            );
            assert_eq!(
                p.get_str("detail"),
                "rm -rf build && make SECRET_ARG",
                "{name}"
            );

            let created = Timestamp::parse_rfc3339(p.get_str("created_at")).unwrap();
            let expires = Timestamp::parse_rfc3339(p.get_str("expires_at")).unwrap();
            assert_eq!(expires.unix_secs() - created.unix_secs(), 5);

            let (status, body) = a.do_act(
                "POST",
                "/v1/claude/permissions/decide",
                &format!(r#"{{"id":"p-1",{decide}}}"#),
            );
            assert_eq!(status, 200);
            assert_eq!(body.as_object().unwrap().len(), 0);

            let (r_status, r_body) = got.recv_timeout(Duration::from_secs(5)).unwrap();
            assert_eq!(r_status, 200);
            assert_eq!(r_body.get_str("decision"), want_decision);
            assert_eq!(r_body.get_str("message"), want_message);
            a.wait_pending(0);

            let logged = logs.text();
            assert!(
                logged.contains(&format!("act claude: {want_decision} Bash in acme")),
                "log {logged:?} lacks act line"
            );
            assert!(
                !logged.contains("SECRET_ARG"),
                "command leaked into log: {logged:?}"
            );
        }
    }

    #[test]
    fn test_permission_ask_is_not_gated_on_the_toggle() {
        let a = PermAgent::new(Duration::from_secs(5));
        assert!(!a.settings.exists());
        let _got = a.ask(BASH_ASK);
        a.wait_pending(1);
    }

    #[test]
    fn test_permission_timeout_falls_back_to_ask() {
        let a = PermAgent::new(Duration::from_millis(150));
        let start = Instant::now();
        let (status, body) = a
            .ask(BASH_ASK)
            .recv_timeout(Duration::from_secs(5))
            .unwrap();
        assert_eq!(status, 200);
        assert_eq!(body.get_str("decision"), "ask");
        assert!(start.elapsed() >= Duration::from_millis(140));
        assert_eq!(a.perms.len(), 0);

        let (late_status, _) = a.do_act(
            "POST",
            "/v1/claude/permissions/decide",
            r#"{"id":"p-1","decision":"allow"}"#,
        );
        assert_eq!(late_status, 404);
    }

    #[test]
    fn test_cancelled_hook_request_drops_the_prompt() {
        let a = PermAgent::new(Duration::from_secs(30));
        // Open raw TCP connection, send request, wait for pending, then drop socket
        let mut stream = TcpStream::connect(&a.server.addr).unwrap();
        let req_str = format!(
            "POST /v1/claude/permission/ask HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer {}\r\nContent-Length: {}\r\n\r\n{}",
            a.hook_tok,
            BASH_ASK.len(),
            BASH_ASK
        );
        stream.write_all(req_str.as_bytes()).unwrap();
        a.wait_pending(1);
        drop(stream);

        let deadline = Instant::now() + Duration::from_secs(5);
        while a.perms.len() != 0 {
            assert!(
                Instant::now() < deadline,
                "cancelled prompt was never dropped"
            );
            std::thread::sleep(Duration::from_millis(5));
        }
        let (status, _) = a.do_act(
            "POST",
            "/v1/claude/permissions/decide",
            r#"{"id":"p-1","decision":"allow"}"#,
        );
        assert_eq!(status, 404);
    }

    #[test]
    fn test_decide_unknown_or_answered_is_404() {
        let a = PermAgent::new(Duration::from_secs(5));
        let (s1, _) = a.do_act(
            "POST",
            "/v1/claude/permissions/decide",
            r#"{"id":"p-99","decision":"allow"}"#,
        );
        assert_eq!(s1, 404);

        let got = a.ask(BASH_ASK);
        a.wait_pending(1);
        let (s2, _) = a.do_act(
            "POST",
            "/v1/claude/permissions/decide",
            r#"{"id":"p-1","decision":"deny"}"#,
        );
        assert_eq!(s2, 200);
        let _ = got.recv_timeout(Duration::from_secs(5)).unwrap();

        let (s3, _) = a.do_act(
            "POST",
            "/v1/claude/permissions/decide",
            r#"{"id":"p-1","decision":"allow"}"#,
        );
        assert_eq!(s3, 404);
    }

    #[test]
    fn test_decide_bad_decision_is_400() {
        let a = PermAgent::new(Duration::from_secs(5));
        let _got = a.ask(BASH_ASK);
        a.wait_pending(1);
        for body in [
            r#"{"id":"p-1","decision":"ask"}"#,
            r#"{"id":"p-1","decision":"ALLOW"}"#,
            r#"{"id":"p-1"}"#,
            "not json",
        ] {
            let (status, _) = a.do_act("POST", "/v1/claude/permissions/decide", body);
            assert_eq!(status, 400, "{body}");
        }
        a.wait_pending(1);
    }

    #[test]
    fn test_deny_message_is_capped() {
        let a = PermAgent::new(Duration::from_secs(5));
        let got = a.ask(BASH_ASK);
        a.wait_pending(1);
        let long = "é".repeat(400);
        a.do_act(
            "POST",
            "/v1/claude/permissions/decide",
            &format!(r#"{{"id":"p-1","decision":"deny","message":"{long}"}}"#),
        );
        let (_, body) = got.recv_timeout(Duration::from_secs(5)).unwrap();
        let msg = body.get_str("message");
        assert_eq!(msg.chars().count(), 300);
    }

    #[test]
    fn test_permission_ask_locks() {
        let a = PermAgent::new(Duration::from_millis(50));
        let mcp = a.store.ensure_mcp_token().unwrap();

        let serve = |addr: &str, tok: &str| -> u16 {
            let mut headers = Vec::new();
            if !tok.is_empty() {
                headers.push(("Authorization".to_string(), format!("Bearer {tok}")));
            }
            let req = HttpRequest {
                method: "POST".to_string(),
                path: "/v1/claude/permission/ask".to_string(),
                raw_query: String::new(),
                headers,
                body: BASH_ASK.as_bytes().to_vec(),
                remote_addr: addr.to_string(),
                host: "127.0.0.1:7411".to_string(),
                cancel: CancelToken::new(),
            };
            PermAgent::route(
                &req,
                &a.store,
                &a.perms,
                a.permission_wait,
                &a.settings,
                &a.hook_command,
            )
            .status
        };

        for addr in [
            "100.101.102.103:5000",
            "192.168.1.10:9000",
            "[2606:4700::1]:443",
        ] {
            assert_eq!(serve(addr, &a.hook_tok), 403, "{addr}");
        }
        for (name, tok) in [
            ("none", ""),
            ("wrong", "deadbeef"),
            ("pairing token", a.act_tok.as_str()),
            ("mcp token", mcp.as_str()),
        ] {
            assert_eq!(serve("127.0.0.1:5000", tok), 401, "{name}");
        }
        assert_eq!(serve("[::1]:5000", &a.hook_tok), 200);
    }

    #[test]
    fn test_permission_phone_endpoints_are_act() {
        let a = PermAgent::new(Duration::from_secs(1));
        for (method, path, body) in [
            ("GET", "/v1/claude/permissions", ""),
            (
                "POST",
                "/v1/claude/permissions/enabled",
                r#"{"enabled":true}"#,
            ),
            (
                "POST",
                "/v1/claude/permissions/decide",
                r#"{"id":"p-1","decision":"allow"}"#,
            ),
        ] {
            for (tok, want) in [("", 401), ("wrong", 403), (a.hook_tok.as_str(), 403)] {
                let url = format!("{}{}", a.server.url(), path);
                let mut headers = Vec::new();
                let auth = format!("Bearer {tok}");
                if !tok.is_empty() {
                    headers.push(("Authorization", auth.as_str()));
                }
                let b = if body.is_empty() {
                    None
                } else {
                    Some(body.as_bytes())
                };
                let (status, _, _) =
                    http_request(method, &url, &headers, b, Duration::from_secs(5)).unwrap();
                assert_eq!(status, want, "{method} {path} with {tok:?}");
            }
        }
        assert!(!a.settings.exists());
    }

    #[test]
    fn test_enabled_toggles_the_hook_in_settings() {
        let a = PermAgent::new(Duration::from_secs(1));
        std::fs::write(&a.settings, EXISTING_SETTINGS).unwrap();

        let enabled = || -> Option<bool> {
            let (_, m) = a.do_act("GET", "/v1/claude/permissions", "");
            m.get_opt_bool("enabled")
        };
        assert_eq!(enabled(), Some(false));

        let (status, body) = a.do_act(
            "POST",
            "/v1/claude/permissions/enabled",
            r#"{"enabled":true}"#,
        );
        assert_eq!(status, 200);
        assert_eq!(body.get_opt_bool("enabled"), Some(true));
        assert_eq!(
            body.get_str("settings_path"),
            tilde_path(&a.settings.to_string_lossy()).as_str()
        );
        assert_eq!(enabled(), Some(true));

        let after = std::fs::read_to_string(&a.settings).unwrap();
        assert!(after.contains(TEST_HOOK_COMMAND));
        let bak = std::fs::read_to_string(format!("{}.bak", a.settings.display())).unwrap();
        assert_eq!(bak, EXISTING_SETTINGS);

        // Idempotent
        a.do_act(
            "POST",
            "/v1/claude/permissions/enabled",
            r#"{"enabled":true}"#,
        );
        let again = std::fs::read_to_string(&a.settings).unwrap();
        assert_eq!(again, after);

        let (status, body) = a.do_act(
            "POST",
            "/v1/claude/permissions/enabled",
            r#"{"enabled":false}"#,
        );
        assert_eq!(status, 200);
        assert_eq!(body.get_opt_bool("enabled"), Some(false));
        assert_eq!(enabled(), Some(false));
        assert_same_json(&a.settings, EXISTING_SETTINGS);

        let (status, _) = a.do_act("POST", "/v1/claude/permissions/enabled", "{}");
        assert_eq!(status, 400);
    }

    #[test]
    fn test_enabled_refuses_invalid_settings() {
        let a = PermAgent::new(Duration::from_secs(1));
        for bad in [
            r#"{"hooks": {"#,
            "[1,2]",
            r#"{"hooks": []}"#,
            r#"{"hooks": {"PermissionRequest": {}}}"#,
        ] {
            std::fs::write(&a.settings, bad).unwrap();
            let (status, body) = a.do_act(
                "POST",
                "/v1/claude/permissions/enabled",
                r#"{"enabled":true}"#,
            );
            assert_eq!(status, 500, "{bad}");
            assert!(
                body.get_str("error").contains("untouched"),
                "{bad}: {:?}",
                body
            );
            assert_eq!(std::fs::read_to_string(&a.settings).unwrap(), bad);
            assert!(!Path::new(&format!("{}.bak", a.settings.display())).exists());
            let (_, m) = a.do_act("GET", "/v1/claude/permissions", "");
            assert_eq!(m.get_opt_bool("enabled"), Some(false));
        }
    }

    #[test]
    fn test_permission_summary() {
        let long = "x".repeat(200);
        let long_json = format!(r#"{{"command":"{long}"}}"#);
        let want_long = format!("{}…", "x".repeat(119));
        let cases = [
            (
                "Bash",
                r#"{"command":"git push origin main","description":"push"}"#,
                "git push origin main",
            ),
            (
                "Bash",
                r#"{"command":"echo a\n\techo   b"}"#,
                "echo a echo b",
            ),
            ("Bash", long_json.as_str(), want_long.as_str()),
            (
                "Edit",
                r#"{"file_path":"/r/main.go","old_string":"a","new_string":"b"}"#,
                "edit /r/main.go",
            ),
            (
                "Write",
                r#"{"file_path":"/r/new.go","content":"package x"}"#,
                "edit /r/new.go",
            ),
            (
                "MultiEdit",
                r#"{"file_path":"/r/a.go","edits":[]}"#,
                "edit /r/a.go",
            ),
            (
                "NotebookEdit",
                r#"{"notebook_path":"/r/n.ipynb","new_source":"x"}"#,
                "edit /r/n.ipynb",
            ),
            (
                "WebFetch",
                r#"{"url":"https://example.com/a","prompt":"read"}"#,
                "https://example.com/a",
            ),
            (
                "mcp__phone__sms_send",
                r#"{"to": "+1 555", "body": "hi"}"#,
                r#"mcp__phone__sms_send {"to":"+1 555","body":"hi"}"#,
            ),
            ("Bash", r#"{"nope":1}"#, r#"Bash {"nope":1}"#),
            ("Glob", "", "Glob"),
        ];
        for (tool, input, want) in cases {
            let got = permission_summary(tool, input);
            assert_eq!(got, want, "{tool} {input}");
            assert!(got.chars().count() <= 120);
        }
    }

    #[test]
    fn test_permission_detail() {
        assert_eq!(permission_detail("Bash", r#"{"command":"a\nb"}"#), "a\nb");
        assert_eq!(
            permission_detail("Edit", r#"{"file_path":"/x"}"#),
            "{\n  \"file_path\": \"/x\"\n}"
        );
        let big = permission_detail("Bash", &format!(r#"{{"command":"{}"}}"#, "é".repeat(5000)));
        assert!(big.len() <= 4096);
        assert!(big.ends_with('…'));
    }

    #[test]
    fn test_clamp_permission_wait() {
        for (input, want) in [
            (Duration::ZERO, Duration::from_secs(5)),
            (Duration::from_secs(1), Duration::from_secs(5)),
            (Duration::from_secs(120), Duration::from_secs(120)),
            (Duration::from_secs(140), Duration::from_secs(140)),
            (Duration::from_secs(600), Duration::from_secs(140)),
        ] {
            assert_eq!(clamp_permission_wait(input), want);
        }
    }
}
