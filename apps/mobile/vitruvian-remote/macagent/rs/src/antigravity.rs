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

use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::mpsc::SyncSender;
use std::sync::Arc;
use std::time::Duration;

use vitruvian_remote_macagent_metrics::json::{JsonMap, JsonValue};
use vitruvian_remote_macagent_metrics::time_util::Timestamp;

use crate::exec::get_exec_dir;
use crate::hook::tilde_path;
use crate::http_util::{
    log_act, write_sse_headers, write_sse_json, CancelToken, HttpRequest, HttpResponse,
};
use crate::notify::Notifier;
use crate::pair::expand_home;
use crate::sampler::{find_executable_in_path, first_line, run_tool_within};
use crate::stream::{first_n_chars, next_exec_stream_id, run_stream_argv, StreamExit, StreamLine};

pub const AGY_IDLE_STATUS: &str = "CASCADE_RUN_STATUS_IDLE";
pub const AGY_SESSIONS_MAX: usize = 20;
pub const AGY_PROMPT_MAX_BYTES: usize = 8 << 10;
pub const AGY_RESUME_TIMEOUT: Duration = Duration::from_secs(30 * 60);
pub const AGY_SQLITE_TIMEOUT: Duration = Duration::from_secs(5);

pub const AGY_ROW_COLUMNS: &str = "conversation_id, title, preview, step_count, last_modified_time, workspace_uris, status, not_fully_idle, killed";

pub type AgyStreamFn =
    dyn Fn(&[String], &Path, &CancelToken, SyncSender<StreamLine>) -> (i32, Duration) + Send + Sync;

pub fn real_agy_stream(
    argv: &[String],
    dir: &Path,
    cancel: &CancelToken,
    lines_tx: SyncSender<StreamLine>,
) -> (i32, Duration) {
    run_stream_argv(argv, dir, AGY_RESUME_TIMEOUT, cancel, lines_tx)
}

pub fn is_valid_agy_id(s: &str) -> bool {
    s.len() == 36
        && s.chars()
            .all(|c| c.is_ascii_digit() || ('a'..='f').contains(&c) || c == '-')
}

pub fn agy_dir() -> PathBuf {
    expand_home("~/.gemini/antigravity-cli")
}

pub fn default_agy_summaries() -> PathBuf {
    agy_dir().join("conversation_summaries.db")
}

#[derive(Debug, Clone, Default)]
pub struct AgyRow {
    pub conversation_id: String,
    pub title: String,
    pub preview: String,
    pub step_count: i64,
    pub last_modified: String,
    pub workspace_uris: String,
    pub status: String,
    pub not_fully_idle: JsonValue,
    pub killed: JsonValue,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AgySession {
    pub id: String,
    pub title: String,
    pub preview: String,
    pub project: String,
    pub steps: i64,
    pub updated_at: String,
    pub state: String,
}

impl AgySession {
    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("id".to_string(), JsonValue::String(self.id.clone()));
        m.insert("title".to_string(), JsonValue::String(self.title.clone()));
        m.insert(
            "preview".to_string(),
            JsonValue::String(self.preview.clone()),
        );
        m.insert(
            "project".to_string(),
            JsonValue::String(self.project.clone()),
        );
        m.insert("steps".to_string(), JsonValue::from_i64(self.steps));
        m.insert(
            "updated_at".to_string(),
            JsonValue::String(self.updated_at.clone()),
        );
        m.insert("state".to_string(), JsonValue::String(self.state.clone()));
        JsonValue::Object(m)
    }

    pub fn from_json_value(v: &JsonValue) -> Option<Self> {
        Some(Self {
            id: v.get_opt_str("id")?,
            title: v.get_str("title").to_string(),
            preview: v.get_str("preview").to_string(),
            project: v.get_str("project").to_string(),
            steps: v.get_i64("steps"),
            updated_at: v.get_str("updated_at").to_string(),
            state: v.get_str("state").to_string(),
        })
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct AgySessionsReply {
    pub available: bool,
    pub reason: String,
    pub sessions: Vec<AgySession>,
}

impl AgySessionsReply {
    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("available".to_string(), JsonValue::Bool(self.available));
        if !self.reason.is_empty() {
            m.insert("reason".to_string(), JsonValue::String(self.reason.clone()));
        }
        m.insert(
            "sessions".to_string(),
            JsonValue::Array(self.sessions.iter().map(|s| s.to_json_value()).collect()),
        );
        JsonValue::Object(m)
    }
}

pub fn query_summaries(db: &Path, query: &str) -> Result<Vec<AgyRow>, String> {
    if !db.exists() {
        return Err(format!(
            "no Antigravity conversations yet ({} not found)",
            tilde_path(&db.to_string_lossy())
        ));
    }
    if find_executable_in_path("sqlite3").is_none() {
        return Err("sqlite3 not found on PATH".to_string());
    }
    let mut res = run_sqlite("-readonly", db, query);
    if let Err(ref e) = res {
        if e.contains("unable to open database file") {
            res = run_sqlite("", db, query);
        }
    }
    let out = res?;
    parse_agy_rows(out.as_bytes())
}

fn run_sqlite(mode: &str, db: &Path, query: &str) -> Result<String, String> {
    let mut args = Vec::new();
    if !mode.is_empty() {
        args.push(mode.to_string());
    }
    args.push("-json".to_string());
    args.push(db.to_string_lossy().to_string());
    args.push(query.to_string());
    let (stdout, stderr, err) = run_tool_within(AGY_SQLITE_TIMEOUT, "sqlite3", &args, None);
    if let Some(e) = err {
        let msg = first_line(&stderr);
        if msg.is_empty() {
            return Err(format!("sqlite3: {e}"));
        }
        return Err(format!("sqlite3: {msg}"));
    }
    Ok(stdout)
}

pub fn parse_agy_rows(out: &[u8]) -> Result<Vec<AgyRow>, String> {
    if out.iter().all(|b| b.is_ascii_whitespace()) {
        return Ok(Vec::new());
    }
    let parsed =
        JsonValue::parse_bytes(out).map_err(|e| format!("cannot parse sqlite3 output: {e}"))?;
    let arr = parsed
        .as_array()
        .ok_or_else(|| "cannot parse sqlite3 output: expected array".to_string())?;
    let mut rows = Vec::with_capacity(arr.len());
    for item in arr {
        rows.push(AgyRow {
            conversation_id: item.get_str("conversation_id").to_string(),
            title: item.get_str("title").to_string(),
            preview: item.get_str("preview").to_string(),
            step_count: item.get_i64("step_count"),
            last_modified: item.get_str("last_modified_time").to_string(),
            workspace_uris: item.get_str("workspace_uris").to_string(),
            status: item.get_str("status").to_string(),
            not_fully_idle: item
                .get("not_fully_idle")
                .cloned()
                .unwrap_or(JsonValue::Null),
            killed: item.get("killed").cloned().unwrap_or(JsonValue::Null),
        });
    }
    Ok(rows)
}

pub fn sql_bool(v: &JsonValue) -> bool {
    match v {
        JsonValue::Null => false,
        JsonValue::Bool(b) => *b,
        JsonValue::Number(n) => {
            if let Ok(f) = n.parse::<f64>() {
                f != 0.0
            } else {
                false
            }
        }
        JsonValue::String(s) => {
            let trimmed = s.trim().trim_matches('"').to_ascii_lowercase();
            match trimmed.as_str() {
                "" | "0" | "false" | "null" => false,
                _ => {
                    if let Ok(f) = trimmed.parse::<f64>() {
                        f != 0.0
                    } else {
                        true
                    }
                }
            }
        }
        _ => true,
    }
}

pub fn agy_workspaces(uris: &str) -> Vec<String> {
    let Ok(parsed) = JsonValue::parse_bytes(uris.as_bytes()) else {
        return Vec::new();
    };
    let Some(arr) = parsed.as_array() else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for item in arr {
        let Some(u) = item.as_str() else {
            continue;
        };
        if let Some(rest) = u.strip_prefix("file://") {
            let path = if let Some(p) = rest.strip_prefix("localhost/") {
                format!("/{p}")
            } else if rest.starts_with('/') {
                rest.to_string()
            } else {
                continue;
            };
            if !path.is_empty() {
                out.push(path);
            }
        }
    }
    out
}

pub fn agy_time(s: &str) -> String {
    // Convert "YYYY-MM-DD HH:MM:SS.ffffff+00:00" to RFC3339 by replacing space with 'T'
    let candidate = if s.len() > 10 && s.as_bytes()[10] == b' ' {
        let mut c = s.to_string();
        c.replace_range(10..11, "T");
        c
    } else {
        s.to_string()
    };
    if let Ok(ts) = Timestamp::parse_rfc3339(&candidate) {
        return Timestamp::from_unix_secs(ts.unix_secs()).to_rfc3339();
    }
    s.to_string()
}

pub fn agy_state(r: &AgyRow) -> String {
    if sql_bool(&r.killed) {
        "killed".to_string()
    } else if (!r.status.is_empty() && r.status != AGY_IDLE_STATUS) || sql_bool(&r.not_fully_idle) {
        "working".to_string()
    } else {
        "idle".to_string()
    }
}

pub fn agy_sessions_from(rows: &[AgyRow]) -> Vec<AgySession> {
    let mut out: Vec<AgySession> = rows
        .iter()
        .map(|r| {
            let ws = agy_workspaces(&r.workspace_uris);
            let project = ws
                .first()
                .and_then(|p| Path::new(p).file_name())
                .and_then(|s| s.to_str())
                .unwrap_or("")
                .to_string();
            AgySession {
                id: r.conversation_id.clone(),
                title: r.title.clone(),
                preview: r.preview.clone(),
                project,
                steps: r.step_count,
                updated_at: agy_time(&r.last_modified),
                state: agy_state(r),
            }
        })
        .collect();

    out.sort_by(|a, b| {
        let ta = Timestamp::parse_rfc3339(&a.updated_at)
            .ok()
            .map(|t| t.unix_nanos());
        let tb = Timestamp::parse_rfc3339(&b.updated_at)
            .ok()
            .map(|t| t.unix_nanos());
        match (ta, tb) {
            (Some(na), Some(nb)) => nb.cmp(&na),
            (Some(_), None) => std::cmp::Ordering::Less,
            (None, Some(_)) => std::cmp::Ordering::Greater,
            (None, None) => std::cmp::Ordering::Equal,
        }
    });
    if out.len() > AGY_SESSIONS_MAX {
        out.truncate(AGY_SESSIONS_MAX);
    }
    out
}

pub fn handle_agy_sessions(req: &HttpRequest, agy_summaries: &Path) -> HttpResponse {
    if req.method != "GET" {
        return HttpResponse::method_not_allowed("GET");
    }
    let query = format!(
        "SELECT {AGY_ROW_COLUMNS} FROM conversation_summaries ORDER BY last_modified_time DESC LIMIT {AGY_SESSIONS_MAX}"
    );
    match query_summaries(agy_summaries, &query) {
        Ok(rows) => HttpResponse::json(
            200,
            &AgySessionsReply {
                available: true,
                reason: String::new(),
                sessions: agy_sessions_from(&rows),
            }
            .to_json_value(),
        ),
        Err(e) => HttpResponse::json(
            200,
            &AgySessionsReply {
                available: false,
                reason: e,
                sessions: Vec::new(),
            }
            .to_json_value(),
        ),
    }
}

pub fn agy_resume_argv(conversation_id: &str, prompt: &str) -> Vec<String> {
    let mut argv = vec![
        "agy".to_string(),
        "-p".to_string(),
        prompt.to_string(),
        "--output-format".to_string(),
        "text".to_string(),
    ];
    if !conversation_id.is_empty() {
        argv.push("--conversation".to_string());
        argv.push(conversation_id.to_string());
    }
    argv
}

pub fn validate_agy_resume(conversation_id: &str, prompt: &str) -> Result<(), String> {
    if !conversation_id.is_empty() && !is_valid_agy_id(conversation_id) {
        return Err(
            "conversation_id must be empty or a conversation id (36 characters of 0-9, a-f and -)"
                .to_string(),
        );
    }
    if prompt.trim().is_empty() {
        return Err("prompt is required".to_string());
    }
    if prompt.len() > AGY_PROMPT_MAX_BYTES {
        return Err(format!(
            "prompt is {} bytes; the limit is {AGY_PROMPT_MAX_BYTES}",
            prompt.len()
        ));
    }
    Ok(())
}

pub fn agy_resume_dir(agy_summaries: &Path, conversation_id: &str) -> PathBuf {
    let fallback = get_exec_dir();
    if conversation_id.is_empty() {
        return fallback;
    }
    let query = format!(
        "SELECT {AGY_ROW_COLUMNS} FROM conversation_summaries WHERE conversation_id = '{conversation_id}' LIMIT 1"
    );
    let Ok(rows) = query_summaries(agy_summaries, &query) else {
        return fallback;
    };
    let Some(first) = rows.first() else {
        return fallback;
    };
    let ws = agy_workspaces(&first.workspace_uris);
    let Some(w0) = ws.first() else {
        return fallback;
    };
    let p = PathBuf::from(w0);
    if p.is_dir() {
        p
    } else {
        fallback
    }
}

pub fn handle_agy_resume(
    req: &HttpRequest,
    stream: &mut dyn Write,
    agy_summaries: &Path,
    agy_stream: &Arc<AgyStreamFn>,
    notifier: Option<&Notifier>,
) -> Option<HttpResponse> {
    if req.method != "POST" {
        return Some(HttpResponse::method_not_allowed("POST"));
    }
    let parsed = match req.json() {
        Ok(v) => v,
        Err(e) => return Some(HttpResponse::error(400, &e)),
    };
    let conversation_id = parsed.get_str("conversation_id").trim().to_string();
    let prompt = parsed.get_str("prompt").to_string();
    if let Err(e) = validate_agy_resume(&conversation_id, &prompt) {
        return Some(HttpResponse::error(400, &e));
    }

    let dir = agy_resume_dir(agy_summaries, &conversation_id);
    let argv = agy_resume_argv(&conversation_id, &prompt);
    let id = next_exec_stream_id();
    let target = if conversation_id.is_empty() {
        "new conversation"
    } else {
        conversation_id.as_str()
    };
    log_act(
        "antigravity-resume",
        &format!("stream #{id} start: {target}: {prompt}"),
    );

    if write_sse_headers(stream).is_err() {
        return None;
    }

    let (tx, rx) = std::sync::mpsc::sync_channel::<StreamLine>(64);
    let cancel_clone = req.cancel.clone();
    let runner = Arc::clone(agy_stream);
    let argv_clone = argv.clone();
    let dir_clone = dir.clone();

    let handle = std::thread::spawn(move || (runner)(&argv_clone, &dir_clone, &cancel_clone, tx));

    for line in rx {
        if write_sse_json(stream, "line", &line.to_json_value()).is_err() {
            req.cancel.cancel();
            break;
        }
    }

    let (code, dur) = handle.join().unwrap_or((-1, Duration::ZERO));
    let exit_ev = StreamExit {
        exit_code: code,
        duration_ms: dur.as_millis() as i64,
        timed_out: false,
    };
    let _ = write_sse_json(stream, "exit", &exit_ev.to_json_value());
    log_act(
        "antigravity-resume",
        &format!("stream #{id} exit {code} after {}ms", dur.as_millis()),
    );

    if let Some(n) = notifier {
        let prompt_preview = first_n_chars(&prompt, 80);
        n.notify(
            &format!("exec:{id}"),
            &format!("Antigravity finished · exit {code}"),
            &prompt_preview,
            "default",
            "checkered_flag",
            "vitruvian-remote://apps/antigravity",
        );
    }

    None
}

pub fn handle_agy_resume_sse(
    req: &HttpRequest,
    agy_summaries: &Path,
    agy_stream: &Arc<AgyStreamFn>,
    notifier: Option<Arc<Notifier>>,
) -> HttpResponse {
    if req.method != "POST" {
        return HttpResponse::method_not_allowed("POST");
    }
    let parsed = match req.json() {
        Ok(v) => v,
        Err(e) => return HttpResponse::error(400, &e),
    };
    let conversation_id = parsed.get_str("conversation_id").trim().to_string();
    let prompt = parsed.get_str("prompt").to_string();
    if let Err(e) = validate_agy_resume(&conversation_id, &prompt) {
        return HttpResponse::error(400, &e);
    }

    let dir = agy_resume_dir(agy_summaries, &conversation_id);
    let argv = agy_resume_argv(&conversation_id, &prompt);
    let id = next_exec_stream_id();
    let target = if conversation_id.is_empty() {
        "new conversation"
    } else {
        conversation_id.as_str()
    };
    log_act(
        "antigravity-resume",
        &format!("stream #{id} start: {target}: {prompt}"),
    );

    let runner = Arc::clone(agy_stream);
    HttpResponse::sse(move |sink, cancel| {
        let (tx, rx) = std::sync::mpsc::sync_channel::<StreamLine>(64);
        let cancel_clone = cancel.clone();
        let argv_clone = argv.clone();
        let dir_clone = dir.clone();
        let handle =
            std::thread::spawn(move || (runner)(&argv_clone, &dir_clone, &cancel_clone, tx));
        for line in rx {
            if sink.write_event("line", &line.to_json_string()).is_err() {
                cancel.cancel();
                break;
            }
        }
        let (code, dur) = handle.join().unwrap_or((-1, Duration::ZERO));
        let exit_ev = StreamExit {
            exit_code: code,
            duration_ms: dur.as_millis() as i64,
            timed_out: false,
        };
        let _ = sink.write_event("exit", &exit_ev.to_json_string());
        if let Some(n) = notifier {
            let prompt_preview = first_n_chars(&prompt, 80);
            n.notify(
                &format!("exec:{id}"),
                &format!("Antigravity finished · exit {code}"),
                &prompt_preview,
                "default",
                "checkered_flag",
                "vitruvian-remote://apps/antigravity",
            );
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::exec::set_exec_dir;
    use crate::http_util::{http_request, parse_bearer, TestServer};
    use crate::pair::Store;
    use std::process::Command;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Mutex;

    const AGY_SCHEMA: &str = "CREATE TABLE `conversation_summaries` (`conversation_id` text,`title` text NOT NULL DEFAULT \"\",`preview` text NOT NULL DEFAULT \"\",`step_count` integer NOT NULL DEFAULT 0,`last_modified_time` datetime NOT NULL,`workspace_uris` text NOT NULL,`status` text NOT NULL DEFAULT \"\",`source` text NOT NULL DEFAULT \"\",`project_id` text NOT NULL DEFAULT \"\",`agent_name` text NOT NULL DEFAULT \"\",`parent_conversation_id` text NOT NULL DEFAULT \"\",`nesting_depth` integer NOT NULL DEFAULT 0,`battle_id` text NOT NULL DEFAULT \"\",`winning_conversation_id` text NOT NULL DEFAULT \"\",`not_fully_idle` numeric NOT NULL DEFAULT false,`killed` numeric NOT NULL DEFAULT false,`last_user_input_time` datetime NOT NULL,`last_user_input_step_index` integer NOT NULL DEFAULT -1,`app_data_dir` text NOT NULL DEFAULT \"\", raw_summary BLOB, group_id TEXT NOT NULL DEFAULT '',PRIMARY KEY (`conversation_id`));";

    const AGY_IDLE: &str = "11111111-1111-4111-8111-111111111111";
    const AGY_WORKING: &str = "22222222-2222-4222-8222-222222222222";
    const AGY_KILLED: &str = "33333333-3333-4333-8333-333333333333";
    const AGY_BUSY: &str = "44444444-4444-4444-8444-444444444444";

    static NEXT_AGY_DIR: AtomicUsize = AtomicUsize::new(0);

    fn temp_dir() -> PathBuf {
        let id = NEXT_AGY_DIR.fetch_add(1, Ordering::SeqCst);
        let dir =
            std::env::temp_dir().join(format!("macagent-agy-test-{}-{}", std::process::id(), id));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn has_sqlite3() -> bool {
        find_executable_in_path("sqlite3").is_some()
    }

    fn make_agy_db(workspace: &Path) -> PathBuf {
        let dir = temp_dir();
        let db = dir.join("conversation_summaries.db");
        let ws = format!(r#"["file://{}"]"#, workspace.display());
        let gone = r#"["file:///Users/alice/src/acme","file:///Users/alice/src/other"]"#;
        let rows = [
            format!(
                "('{AGY_IDLE}','Fix the build','Run the tests',7,'2026-09-26 02:23:19.452133+00:00','{ws}','CASCADE_RUN_STATUS_IDLE',0,0,'2026-09-26 02:23:19+00:00')"
            ),
            format!(
                "('{AGY_WORKING}','Refactor','Split the file',3,'2026-09-26 02:25:00.000001+00:00','{ws}','CASCADE_RUN_STATUS_RUNNING',0,0,'2026-09-26 02:25:00+00:00')"
            ),
            format!(
                "('{AGY_KILLED}','Old one','',1,'2026-09-25 10:00:00+00:00','{gone}','CASCADE_RUN_STATUS_IDLE',0,1,'2026-09-25 10:00:00+00:00')"
            ),
            format!(
                "('{AGY_BUSY}','Busy','',2,'2026-09-24 10:00:00+00:00','{gone}','CASCADE_RUN_STATUS_IDLE',1,0,'2026-09-24 10:00:00+00:00')"
            ),
        ];
        let sql = format!(
            "{AGY_SCHEMA}INSERT INTO conversation_summaries (conversation_id,title,preview,step_count,last_modified_time,workspace_uris,status,not_fully_idle,killed,last_user_input_time) VALUES {};",
            rows.join(",")
        );
        let out = Command::new("sqlite3").arg(&db).arg(&sql).output().unwrap();
        assert!(
            out.status.success(),
            "sqlite3 failed: {}",
            String::from_utf8_lossy(&out.stderr)
        );
        db
    }

    #[derive(Debug, Clone)]
    struct AgyCall {
        argv: Vec<String>,
        dir: PathBuf,
    }

    struct AgyAgent {
        act_tok: String,
        calls: Arc<Mutex<Vec<AgyCall>>>,
        server: TestServer,
    }

    impl AgyAgent {
        fn new(db: PathBuf) -> Self {
            let dir = temp_dir();
            let store = Store::new(dir.join("store"));
            let act_tok = store.ensure_token().unwrap();
            let calls: Arc<Mutex<Vec<AgyCall>>> = Arc::new(Mutex::new(Vec::new()));
            let calls_clone = Arc::clone(&calls);

            let stream_fn: Arc<AgyStreamFn> = Arc::new(move |argv, run_dir, _cancel, lines_tx| {
                calls_clone.lock().unwrap().push(AgyCall {
                    argv: argv.to_vec(),
                    dir: run_dir.to_path_buf(),
                });
                let _ = lines_tx.send(StreamLine {
                    stream: "stdout".to_string(),
                    text: "done".to_string(),
                });
                (0, Duration::from_millis(1))
            });

            let store_srv = store.clone();
            let db_srv = db.clone();
            let stream_srv = Arc::clone(&stream_fn);

            let server = TestServer::start(move |req: &HttpRequest| match req.path.as_str() {
                "/v1/antigravity/sessions" => handle_agy_sessions(req, &db_srv),
                "/v1/antigravity/resume" => {
                    let Some(tok) = parse_bearer(req) else {
                        return HttpResponse::error(401, "missing bearer token");
                    };
                    if !store_srv.authorized(tok) {
                        return HttpResponse::error(403, "invalid bearer token");
                    }
                    handle_agy_resume_sse(req, &db_srv, &stream_srv, None)
                }
                _ => HttpResponse::error(404, "not found"),
            });

            Self {
                act_tok,
                calls,
                server,
            }
        }

        fn recorded(&self) -> Vec<AgyCall> {
            self.calls.lock().unwrap().clone()
        }

        fn resume(&self, body: &str) -> (u16, Vec<(String, String)>, String) {
            let url = format!("{}/v1/antigravity/resume", self.server.url());
            let auth = format!("Bearer {}", self.act_tok);
            let (status, headers, resp_body) = http_request(
                "POST",
                &url,
                &[
                    ("Authorization", &auth),
                    ("Content-Type", "application/json"),
                ],
                Some(body.as_bytes()),
                Duration::from_secs(5),
            )
            .unwrap();
            (
                status,
                headers,
                String::from_utf8_lossy(&resp_body).to_string(),
            )
        }
    }

    fn read_sse(body: &str) -> (Vec<String>, Vec<String>) {
        let mut texts = Vec::new();
        let mut events = Vec::new();
        let mut event = String::new();
        for line in body.lines() {
            if let Some(ev) = line.strip_prefix("event: ") {
                event = ev.to_string();
                events.push(event.clone());
            } else if let Some(data) = line.strip_prefix("data: ") {
                if event == "line" {
                    if let Ok(v) = JsonValue::parse_bytes(data.as_bytes()) {
                        if let Some(t) = v.get_opt_str("text") {
                            texts.push(t);
                        }
                    }
                }
            }
        }
        (texts, events)
    }

    #[test]
    fn test_agy_sessions_from_the_database() {
        if !has_sqlite3() {
            return;
        }
        let ws = temp_dir();
        let a = AgyAgent::new(make_agy_db(&ws));

        let url = format!("{}/v1/antigravity/sessions", a.server.url());
        let (status, _, body) =
            http_request("GET", &url, &[], None, Duration::from_secs(5)).unwrap();
        assert_eq!(status, 200);
        let parsed = JsonValue::parse_bytes(&body).unwrap();
        assert_eq!(parsed.get_opt_bool("available"), Some(true));
        assert!(parsed.get_opt_str("reason").is_none());

        let arr = parsed.get_array("sessions").unwrap();
        let sessions: Vec<AgySession> = arr
            .iter()
            .map(|v| AgySession::from_json_value(v).unwrap())
            .collect();

        let ids: Vec<&str> = sessions.iter().map(|s| s.id.as_str()).collect();
        let states: Vec<&str> = sessions.iter().map(|s| s.state.as_str()).collect();
        assert_eq!(ids, vec![AGY_WORKING, AGY_IDLE, AGY_KILLED, AGY_BUSY]);
        assert_eq!(states, vec!["working", "idle", "killed", "working"]);

        let first = &sessions[1];
        assert_eq!(first.title, "Fix the build");
        assert_eq!(first.preview, "Run the tests");
        assert_eq!(first.steps, 7);
        assert_eq!(
            first.project,
            ws.file_name().unwrap().to_string_lossy().as_ref()
        );
        assert_eq!(first.updated_at, "2026-09-26T02:23:19Z");
        assert_eq!(sessions[2].project, "acme");
    }

    #[test]
    fn test_agy_sessions_without_a_database() {
        let dir = temp_dir();
        let a = AgyAgent::new(dir.join("missing.db"));
        let url = format!("{}/v1/antigravity/sessions", a.server.url());
        let (status, _, body) =
            http_request("GET", &url, &[], None, Duration::from_secs(5)).unwrap();
        assert_eq!(status, 200);
        let got = JsonValue::parse_bytes(&body).unwrap();
        assert_eq!(got.get_opt_bool("available"), Some(false));
        assert!(got.get_str("reason").contains("missing.db"));
        assert_eq!(got.get_array("sessions").unwrap().len(), 0);
    }

    #[test]
    fn test_agy_session_state_mapping_and_cap() {
        let out = br#"[
         {"conversation_id":"a","status":"CASCADE_RUN_STATUS_IDLE","not_fully_idle":0,"killed":0,"last_modified_time":"2026-09-26 02:00:00+00:00","workspace_uris":"[\"file:///Users/alice/src/acme\"]"},
         {"conversation_id":"b","status":"CASCADE_RUN_STATUS_RUNNING","not_fully_idle":0,"killed":0,"last_modified_time":"2026-09-26 01:00:00+00:00","workspace_uris":"[]"},
         {"conversation_id":"c","status":"CASCADE_RUN_STATUS_IDLE","not_fully_idle":"true","killed":"false","last_modified_time":"2026-09-26 00:30:00+00:00","workspace_uris":"not json"},
         {"conversation_id":"d","status":"CASCADE_RUN_STATUS_RUNNING","not_fully_idle":1,"killed":1,"last_modified_time":"2026-09-26 00:00:00+00:00","workspace_uris":"[\"https://example.com\"]"},
         {"conversation_id":"e","status":"","not_fully_idle":null,"killed":null,"last_modified_time":"yesterday","workspace_uris":""}
        ]"#;
        let rows = parse_agy_rows(out).unwrap();
        let got = agy_sessions_from(&rows);
        for (id, want) in [
            ("a", "idle"),
            ("b", "working"),
            ("c", "working"),
            ("d", "killed"),
            ("e", "idle"),
        ] {
            let s = got.iter().find(|x| x.id == id).unwrap();
            assert_eq!(s.state, want, "{id}");
        }
        assert_eq!(got[0].project, "acme");
        assert_eq!(got[1].project, "");
        assert_eq!(got[3].project, "");
        assert_eq!(got[4].updated_at, "yesterday");

        assert!(parse_agy_rows(b"").unwrap().is_empty());

        let mut many = Vec::new();
        for i in 0..30 {
            many.push(AgyRow {
                conversation_id: i.to_string(),
                last_modified: format!("2026-09-26 00:00:{i:02}+00:00"),
                ..Default::default()
            });
        }
        let capped = agy_sessions_from(&many);
        assert_eq!(capped.len(), AGY_SESSIONS_MAX);
        assert_eq!(capped[0].id, "29");
    }

    #[test]
    fn test_agy_resume_argv_and_working_directory() {
        if !has_sqlite3() {
            return;
        }
        let ws = temp_dir();
        let a = AgyAgent::new(make_agy_db(&ws));
        let old_exec = get_exec_dir();
        let custom_exec = temp_dir();
        set_exec_dir(custom_exec.clone());

        let cases = [
            (
                "known conversation runs in its workspace",
                format!(r#"{{"conversation_id":"{AGY_IDLE}","prompt":"carry on"}}"#),
                vec![
                    "agy",
                    "-p",
                    "carry on",
                    "--output-format",
                    "text",
                    "--conversation",
                    AGY_IDLE,
                ],
                ws.clone(),
            ),
            (
                "a workspace that no longer exists falls back to --exec-dir",
                format!(r#"{{"conversation_id":"{AGY_KILLED}","prompt":"and now?"}}"#),
                vec![
                    "agy",
                    "-p",
                    "and now?",
                    "--output-format",
                    "text",
                    "--conversation",
                    AGY_KILLED,
                ],
                custom_exec.clone(),
            ),
            (
                "an id the database does not know falls back to --exec-dir",
                r#"{"conversation_id":"99999999-9999-4999-8999-999999999999","prompt":"hi"}"#
                    .to_string(),
                vec![
                    "agy",
                    "-p",
                    "hi",
                    "--output-format",
                    "text",
                    "--conversation",
                    "99999999-9999-4999-8999-999999999999",
                ],
                custom_exec.clone(),
            ),
            (
                "no id starts a new conversation in --exec-dir",
                r#"{"conversation_id":"","prompt":"start; rm -rf / # stays one argument"}"#
                    .to_string(),
                vec![
                    "agy",
                    "-p",
                    "start; rm -rf / # stays one argument",
                    "--output-format",
                    "text",
                ],
                custom_exec.clone(),
            ),
        ];

        for (name, body, want_argv, want_dir) in cases {
            let before = a.recorded().len();
            let (status, headers, sse_body) = a.resume(&body);
            assert_eq!(status, 200, "{name}");
            let ct = headers
                .iter()
                .find(|(k, _)| k.eq_ignore_ascii_case("content-type"))
                .map(|(_, v)| v.as_str())
                .unwrap_or("");
            assert_eq!(ct, "text/event-stream", "{name}");
            let (texts, events) = read_sse(&sse_body);
            assert_eq!(texts, vec!["done"], "{name}");
            assert_eq!(events.last().map(|s| s.as_str()), Some("exit"), "{name}");

            let calls = a.recorded();
            assert_eq!(calls.len(), before + 1, "{name}");
            let c = calls.last().unwrap();
            assert_eq!(c.argv, want_argv, "{name}");
            assert_eq!(c.dir, want_dir, "{name}");
        }

        set_exec_dir(old_exec);
    }

    #[test]
    fn test_agy_resume_validates_before_running() {
        let dir = temp_dir();
        let a = AgyAgent::new(dir.join("none.db"));
        let over_limit = format!(r#"{{"prompt":"{}"}}"#, "a".repeat(AGY_PROMPT_MAX_BYTES + 1));
        let missing_prompt = format!(r#"{{"conversation_id":"{AGY_IDLE}"}}"#);
        let cases = [
            (
                "id with a quote",
                r#"{"conversation_id":"1111111-1111-4111-8111-111111111111'","prompt":"x"}"#,
            ),
            (
                "upper-case id",
                r#"{"conversation_id":"AAAAAAAA-1111-4111-8111-111111111111","prompt":"x"}"#,
            ),
            ("short id", r#"{"conversation_id":"1234","prompt":"x"}"#),
            (
                "flag as an id",
                r#"{"conversation_id":"--dangerously-skip-permissions-xxxxxx","prompt":"x"}"#,
            ),
            ("empty prompt", r#"{"conversation_id":"","prompt":"   "}"#),
            ("missing prompt", missing_prompt.as_str()),
            ("prompt over 8KiB", over_limit.as_str()),
            ("not JSON", "nope"),
        ];
        for (name, body) in cases {
            let (status, _, _) = a.resume(body);
            assert_eq!(status, 400, "{name}");
        }
        assert_eq!(a.recorded().len(), 0);
        assert!(validate_agy_resume("", &"a".repeat(AGY_PROMPT_MAX_BYTES)).is_ok());
    }

    #[test]
    fn test_agy_endpoints_tiers() {
        let dir = temp_dir();
        let a = AgyAgent::new(dir.join("none.db"));
        let url = format!("{}/v1/antigravity/resume", a.server.url());
        let (status, _, _) = http_request(
            "POST",
            &url,
            &[("Content-Type", "application/json")],
            Some(br#"{"prompt":"x"}"#),
            Duration::from_secs(5),
        )
        .unwrap();
        assert_eq!(status, 401);
        assert_eq!(a.recorded().len(), 0);
    }

    #[test]
    fn test_summaries_readable_when_agy_is_not_running() {
        if !has_sqlite3() {
            return;
        }
        let dir = temp_dir();
        let db = dir.join("conversation_summaries.db");
        let schema = "PRAGMA journal_mode=WAL; CREATE TABLE conversation_summaries (conversation_id text, title text, preview text, step_count integer, last_modified_time datetime, workspace_uris text, status text, not_fully_idle numeric, killed numeric); INSERT INTO conversation_summaries VALUES ('11111111-2222-3333-4444-555555555555','t','p',3,'2026-09-25 10:00:00+00:00','','CASCADE_RUN_STATUS_IDLE',0,0);";
        let out = Command::new("sqlite3")
            .arg(&db)
            .arg(schema)
            .output()
            .unwrap();
        assert!(out.status.success());
        for ext in ["-wal", "-shm"] {
            let _ = std::fs::remove_file(format!("{}{ext}", db.display()));
        }
        let rows = query_summaries(
            &db,
            &format!("SELECT {AGY_ROW_COLUMNS} FROM conversation_summaries"),
        )
        .unwrap();
        assert_eq!(rows.len(), 1);
    }
}
