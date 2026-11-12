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

use std::cell::RefCell;
use std::collections::HashSet;
use std::fmt;
use std::fs::OpenOptions;
use std::io::{Read, Write};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use crate::base64;
use crate::channel_allowlist::{
    assert_file_share_allowed, assert_params_allowed, ChannelAllowlistError, ChannelGuard,
    FileShares,
};
use crate::config::{SlackCredentials, WriteTokenPreference};
use crate::json::{
    js_number_to_string, js_string, js_string_to_number, js_to_number, js_truthy, JsonValue,
};
use crate::permalink::InvalidPermalinkError;
use crate::url::encode_query_params;

/// Conversations inspected at once by list_unread; Slack allows ~50 calls/min.
const UNREAD_CONCURRENCY: usize = 4;
const UNREAD_MAX_RETRIES: usize = 3;
const UNREAD_MAX_WAIT_SECONDS: u64 = 30;
const UNREAD_MAX_PAGES: usize = 5;
const DEFAULT_READ_CAP: usize = 1_048_576;
const API_RATE_LIMIT_MAX_RETRIES: usize = 2;
const API_RATE_LIMIT_MAX_WAIT_SECONDS: f64 = 10.0;

const UNREAD_IGNORED_SUBTYPES: &[&str] =
    &["channel_join", "channel_leave", "group_join", "group_leave"];

const TEXT_MIMETYPES: &[&str] = &[
    "application/json",
    "application/xml",
    "application/javascript",
    "application/x-javascript",
    "application/x-sh",
    "application/x-yaml",
    "application/yaml",
    "application/toml",
    "application/csv",
    "application/x-ndjson",
    "application/sql",
];

#[derive(Debug, Clone, PartialEq)]
pub enum SlackClientError {
    ChannelAllowlist(ChannelAllowlistError),
    InvalidPermalink(InvalidPermalinkError),
    UserTokenUnavailable { method: String },
    Message(String),
}

impl SlackClientError {
    pub fn message(&self) -> String {
        match self {
            SlackClientError::ChannelAllowlist(e) => e.message(),
            SlackClientError::InvalidPermalink(e) => e.message.clone(),
            SlackClientError::UserTokenUnavailable { method } => format!(
                "Slack method {method} requires the user token, which is not available on this transport."
            ),
            SlackClientError::Message(m) => m.clone(),
        }
    }
}

impl fmt::Display for SlackClientError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message())
    }
}

impl std::error::Error for SlackClientError {}

impl From<ChannelAllowlistError> for SlackClientError {
    fn from(e: ChannelAllowlistError) -> Self {
        SlackClientError::ChannelAllowlist(e)
    }
}

impl From<InvalidPermalinkError> for SlackClientError {
    fn from(e: InvalidPermalinkError) -> Self {
        SlackClientError::InvalidPermalink(e)
    }
}

#[derive(Debug, Clone)]
pub struct HttpRequest {
    pub url: String,
    pub method: String,
    pub headers: Vec<(String, String)>,
    pub body: Option<Vec<u8>>,
}

impl HttpRequest {
    pub fn auth(&self) -> Option<&str> {
        self.headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case("authorization"))
            .map(|(_, v)| v.as_str())
    }

    pub fn body_str(&self) -> Option<String> {
        self.body
            .as_ref()
            .map(|b| String::from_utf8_lossy(b).into_owned())
    }
}

#[derive(Debug, Clone)]
pub struct HttpResponse {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

impl HttpResponse {
    pub fn json(status: u16, payload: JsonValue) -> Self {
        Self {
            status,
            headers: vec![("Content-Type".to_string(), "application/json".to_string())],
            body: payload.to_json_string().into_bytes(),
        }
    }

    pub fn with_header(mut self, k: impl Into<String>, v: impl Into<String>) -> Self {
        self.headers.push((k.into(), v.into()));
        self
    }

    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(name))
            .map(|(_, v)| v.as_str())
    }
}

pub type FetchHandler = Arc<dyn Fn(&HttpRequest) -> Result<HttpResponse, String> + Send + Sync>;

thread_local! {
    static THREAD_MOCK_FETCH: RefCell<Option<FetchHandler>> = RefCell::new(None);
}

pub struct MockFetchGuard {
    pub calls: Arc<Mutex<Vec<HttpRequest>>>,
}

impl Drop for MockFetchGuard {
    fn drop(&mut self) {
        THREAD_MOCK_FETCH.with(|cell| {
            *cell.borrow_mut() = None;
        });
    }
}

pub fn set_mock_fetch<F>(handler: F) -> MockFetchGuard
where
    F: Fn(&HttpRequest) -> Result<HttpResponse, String> + Send + Sync + 'static,
{
    let calls = Arc::new(Mutex::new(Vec::new()));
    let calls_clone = Arc::clone(&calls);
    let wrapped: FetchHandler = Arc::new(move |req: &HttpRequest| {
        calls_clone.lock().unwrap().push(req.clone());
        handler(req)
    });
    THREAD_MOCK_FETCH.with(|cell| {
        *cell.borrow_mut() = Some(wrapped);
    });
    MockFetchGuard { calls }
}

/// The tool handlers run list_unread's workers on their own threads; this
/// carries the calling thread's test double (if any) onto them so a test's
/// mock sees every request, exactly as it would on one thread.
fn current_mock() -> Option<FetchHandler> {
    THREAD_MOCK_FETCH.with(|cell| cell.borrow().clone())
}

fn install_mock(mock: Option<FetchHandler>) {
    THREAD_MOCK_FETCH.with(|cell| {
        *cell.borrow_mut() = mock;
    });
}

#[cfg(test)]
thread_local! {
    static THREAD_MOCK_SLEEP: RefCell<Option<Arc<Mutex<Vec<Duration>>>>> = const { RefCell::new(None) };
}

#[cfg(test)]
pub struct MockSleepGuard {
    pub sleeps: Arc<Mutex<Vec<Duration>>>,
}

#[cfg(test)]
impl Drop for MockSleepGuard {
    fn drop(&mut self) {
        THREAD_MOCK_SLEEP.with(|cell| {
            *cell.borrow_mut() = None;
        });
    }
}

#[cfg(test)]
pub fn set_mock_sleep() -> MockSleepGuard {
    let sleeps = Arc::new(Mutex::new(Vec::new()));
    let cloned = Arc::clone(&sleeps);
    THREAD_MOCK_SLEEP.with(|cell| {
        *cell.borrow_mut() = Some(cloned);
    });
    MockSleepGuard { sleeps }
}

fn sleep_for_retry(duration: Duration) {
    #[cfg(test)]
    {
        let recorded = THREAD_MOCK_SLEEP.with(|cell| cell.borrow().clone());
        if let Some(sink) = recorded {
            sink.lock().unwrap().push(duration);
            return;
        }
    }
    std::thread::sleep(duration);
}

/// Longest a single Slack Web API call may take, end to end.
const API_TIMEOUT: Duration = Duration::from_secs(60);
/// Time allowed to establish a connection (DNS, TCP and TLS).
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
/// Longest a socket may sit idle mid-transfer. File downloads and uploads
/// have no overall deadline, since a large file on a slow link is legitimate;
/// this is what stops a stalled one.
const IO_IDLE_TIMEOUT: Duration = Duration::from_secs(60);
/// fetch follows up to 20 redirects.
const MAX_REDIRECTS: u32 = 20;

/// One connection pool for the process, as Node's global fetch has.
///
/// Redirects are followed, as fetch follows them (Slack's `url_private`
/// downloads can redirect). ureq 2.12's default `RedirectAuthHeaders::Never`
/// drops Authorization on every redirect; `SameHost` keeps it only when the
/// next hop is the same host over https (or an upgrade to it), and strips it
/// otherwise. Once stripped it is never re-added (ureq reuses the trimmed
/// header list for later hops), so the token never reaches a host other than
/// the one it was sent to. Read in ureq-2.12.1/src/unit.rs
/// (`can_propagate_authorization_on_redirect`). TLS is the shared
/// `crate::tls::client_config()`: rustls on ring with the system trust store.
fn agent() -> &'static ureq::Agent {
    static AGENT: OnceLock<ureq::Agent> = OnceLock::new();
    AGENT.get_or_init(|| {
        ureq::AgentBuilder::new()
            .timeout_connect(CONNECT_TIMEOUT)
            .timeout_read(IO_IDLE_TIMEOUT)
            .timeout_write(IO_IDLE_TIMEOUT)
            .redirects(MAX_REDIRECTS)
            .redirect_auth_headers(ureq::RedirectAuthHeaders::SameHost)
            .tls_config(crate::tls::client_config())
            .build()
    })
}

/// A Web API call: bounded by [`API_TIMEOUT`].
fn execute_http(req: &HttpRequest) -> Result<HttpResponse, String> {
    execute_http_with_deadline(req, Some(API_TIMEOUT))
}

/// A file transfer: no overall deadline, only the per-socket idle timeouts.
fn execute_transfer(req: &HttpRequest) -> Result<HttpResponse, String> {
    execute_http_with_deadline(req, None)
}

fn execute_http_with_deadline(
    req: &HttpRequest,
    deadline: Option<Duration>,
) -> Result<HttpResponse, String> {
    if let Some(mock) = current_mock() {
        return mock(req);
    }
    ureq_fetch(req, deadline)
}

/// Sends `req` and returns whatever came back, as fetch would: any status,
/// all headers, and the body as raw bytes. Only a failure to get a response
/// at all is an `Err`.
fn ureq_fetch(req: &HttpRequest, deadline: Option<Duration>) -> Result<HttpResponse, String> {
    let mut request = agent().request(&req.method, &req.url);
    if let Some(d) = deadline {
        request = request.timeout(d);
    }
    for (k, v) in &req.headers {
        request = request.set(k, v);
    }
    let result = match &req.body {
        Some(body) => request.send_bytes(body),
        None => request.call(),
    };
    let response = match result {
        Ok(response) => response,
        // ureq 2 reports 4xx/5xx as errors; fetch does not, and api() reads
        // the 429 itself.
        Err(ureq::Error::Status(_, response)) => response,
        Err(ureq::Error::Transport(t)) => return Err(transport_error_message(&t)),
    };
    let status = response.status();
    let mut names: Vec<String> = Vec::new();
    for name in response.headers_names() {
        if !names.contains(&name) {
            names.push(name);
        }
    }
    let mut headers = Vec::new();
    for name in &names {
        for value in response.all(name) {
            headers.push((name.clone(), value.to_string()));
        }
    }
    let mut body = Vec::new();
    response
        .into_reader()
        .read_to_end(&mut body)
        .map_err(|e| format!("fetch failed: {e}"))?;
    Ok(HttpResponse {
        status,
        headers,
        body,
    })
}

/// "fetch failed" as Node words it, plus the cause. The URL is left out on
/// purpose: ureq's own Display leads with it, and for a download that is the
/// bearer-authenticated `url_private` this server keeps out of tool results.
fn transport_error_message(t: &ureq::Transport) -> String {
    let mut msg = format!("fetch failed: {}", t.kind());
    if let Some(m) = t.message() {
        msg.push_str(": ");
        msg.push_str(m);
    }
    if let Some(source) = std::error::Error::source(t) {
        msg.push_str(": ");
        msg.push_str(&source.to_string());
    }
    msg
}

// ── JavaScript semantics the TypeScript client relied on ────────────────
//
// The TypeScript client read Slack's answers with JavaScript's loose rules:
// `!data.ok` is truthiness, `data.error ?? "x"` substitutes only for a
// missing or null field, and a template literal stringifies whatever is
// there. These keep the Rust reading of the same answer identical.

/// `!!data.ok`
fn is_ok(data: &JsonValue) -> bool {
    js_truthy(data.get("ok"))
}

/// `value ?? fallback`, as a JSON value.
fn value_or(value: Option<&JsonValue>, fallback: &str) -> JsonValue {
    match value {
        None | Some(JsonValue::Null) => JsonValue::str(fallback),
        Some(v) => v.clone(),
    }
}

/// `${value ?? fallback}`
fn string_or(value: Option<&JsonValue>, fallback: &str) -> String {
    match value {
        None | Some(JsonValue::Null) => fallback.to_string(),
        Some(v) => js_string(v),
    }
}

/// `${value}`, where a missing field is `undefined`.
fn template(value: Option<&JsonValue>) -> String {
    match value {
        None => "undefined".to_string(),
        Some(v) => js_string(v),
    }
}

/// Copies `key` from `from` into `to` unless it is absent: what an object
/// literal `{ key: from.key }` serialises to, since JSON.stringify drops
/// `undefined` but keeps `null`.
fn copy_if_present(to: &mut JsonValue, from: &JsonValue, key: &str) {
    if let Some(v) = from.get(key) {
        to.insert(key, v.clone());
    }
}

/// `Math.min(a, b)`, which is NaN if either is.
fn js_min(a: f64, b: f64) -> f64 {
    if a.is_nan() || b.is_nan() {
        f64::NAN
    } else {
        a.min(b)
    }
}

/// `Math.max(a, b)`, which is NaN if either is.
fn js_max(a: f64, b: f64) -> f64 {
    if a.is_nan() || b.is_nan() {
        f64::NAN
    } else {
        a.max(b)
    }
}

/// Reads Retry-After as `Number(res.headers.get("Retry-After") ?? "1")`
/// did: a missing header means 1 second, an empty one 0, fractions are kept,
/// and anything that is not a finite number falls back to 1. fetch's
/// `Headers.get` joins repeated headers with ", ", which is then not a number.
fn retry_after_seconds(res: &HttpResponse) -> f64 {
    let values: Vec<&str> = res
        .headers
        .iter()
        .filter(|(k, _)| k.eq_ignore_ascii_case("retry-after"))
        .map(|(_, v)| v.as_str())
        .collect();
    let raw = if values.is_empty() {
        "1".to_string()
    } else {
        values.join(", ")
    };
    let n = js_string_to_number(&raw);
    if n.is_finite() {
        n
    } else {
        1.0
    }
}

/// How long list_unread's patient retry waits: `Math.min(retry_after ?? 1,
/// 30)` seconds, where setTimeout treats NaN or a negative delay as none.
fn unread_backoff(data: &JsonValue) -> Duration {
    let requested = match data.get("retry_after") {
        None | Some(JsonValue::Null) => 1.0,
        Some(v) => js_to_number(v),
    };
    let seconds = js_min(requested, UNREAD_MAX_WAIT_SECONDS as f64);
    if seconds.is_finite() && seconds > 0.0 {
        Duration::from_secs_f64(seconds)
    } else {
        Duration::ZERO
    }
}

/// Decodes bytes as `new TextDecoder("utf-8").decode` does: a leading BOM
/// is removed and invalid sequences become U+FFFD (Rust's lossy decoding
/// replaces the same maximal subparts the WHATWG decoder does).
fn decode_utf8_like_text_decoder(bytes: &[u8]) -> String {
    let bytes = bytes.strip_prefix(b"\xEF\xBB\xBF").unwrap_or(bytes);
    String::from_utf8_lossy(bytes).into_owned()
}

fn is_text_file(file: &JsonValue) -> bool {
    let mimetype = file
        .get("mimetype")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    if mimetype.starts_with("text/") || TEXT_MIMETYPES.contains(&mimetype.as_str()) {
        return true;
    }
    let filetype = file.get("filetype").and_then(|v| v.as_str()).unwrap_or("");
    filetype == "text" || filetype == "markdown"
}

fn is_canvas_file(file: &JsonValue) -> bool {
    let mimetype = file
        .get("mimetype")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    if mimetype == "application/vnd.slack-docs" {
        return true;
    }
    let filetype = file
        .get("filetype")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    filetype == "canvas" || filetype == "quip"
}

fn search_message_match_allowed(guard: &ChannelGuard, item: &JsonValue) -> bool {
    let channel_id = match item.get("channel") {
        Some(JsonValue::String(s)) if !s.is_empty() => Some(s.as_str()),
        Some(obj) => obj
            .get("id")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty()),
        None => None,
    };
    channel_id.is_some_and(|id| guard.is_allowed(id))
}

fn search_file_match_allowed(guard: &ChannelGuard, item: &JsonValue) -> bool {
    if assert_file_share_allowed(guard, &FileShares::from_json(item)).is_ok() {
        return true;
    }
    if let Some(shares) = item.get("shares") {
        for bucket in ["public", "private"] {
            if let Some(entries) = shares.get(bucket).and_then(|v| v.as_object()) {
                if entries.iter().any(|(cid, _)| guard.is_allowed(cid)) {
                    return true;
                }
            }
        }
    }
    search_message_match_allowed(guard, item)
}

fn public_file(file: &JsonValue) -> JsonValue {
    let Some(entries) = file.as_object() else {
        return JsonValue::empty_object();
    };
    let mut shown = Vec::new();
    for (k, v) in entries {
        if k.starts_with("url_private") || k == "permalink_public" {
            continue;
        }
        shown.push((k.clone(), v.clone()));
    }
    JsonValue::Object(shown)
}

#[derive(Debug, Clone, Default)]
pub struct ChannelHistoryOptions {
    pub limit: Option<f64>,
    pub oldest: Option<String>,
    pub latest: Option<String>,
    pub since: Option<String>,
    pub cursor: Option<String>,
    pub include_activity: Option<bool>,
}

#[derive(Debug, Clone, Default)]
pub struct ThreadRepliesOptions {
    pub limit: Option<f64>,
    pub cursor: Option<String>,
    pub oldest: Option<String>,
    pub latest: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct SearchOptions {
    pub count: Option<f64>,
    pub sort: Option<String>,
    pub sort_dir: Option<String>,
    pub page: Option<f64>,
}

#[derive(Debug, Clone, Default)]
pub struct PostMessageOptions {
    pub thread_ts: Option<String>,
    pub reply_broadcast: Option<bool>,
    pub unfurl_links: Option<bool>,
}

#[derive(Debug, Clone, Default)]
pub struct ReplyToThreadOptions {
    pub reply_broadcast: Option<bool>,
    pub unfurl_links: Option<bool>,
}

fn parse_relative_since(raw: &str, now_epoch_secs: f64) -> Result<String, SlackClientError> {
    let trimmed = raw.trim();
    let invalid = || {
        SlackClientError::Message(format!(
            "Invalid since value {raw:?}: expected a positive duration like \"30m\", \"24h\", or \"7d\"."
        ))
    };
    let Some(unit_ch) = trimmed.chars().last() else {
        return Err(invalid());
    };
    let unit_secs = match unit_ch {
        's' | 'S' => 1.0,
        'm' | 'M' => 60.0,
        'h' | 'H' => 3_600.0,
        'd' | 'D' => 86_400.0,
        'w' | 'W' => 604_800.0,
        _ => return Err(invalid()),
    };
    let num_part = &trimmed[..trimmed.len() - unit_ch.len_utf8()];
    let amount: f64 = num_part.trim().parse().map_err(|_| invalid())?;
    if !amount.is_finite() || amount <= 0.0 {
        return Err(invalid());
    }
    let oldest = (now_epoch_secs - amount * unit_secs).max(0.0);
    Ok(format!("{oldest:.6}"))
}

#[derive(Debug, Clone)]
pub struct UploadFileInput {
    pub channel_id: String,
    pub filename: String,
    pub content: Option<String>,
    pub content_base64: Option<String>,
    pub title: Option<String>,
    pub initial_comment: Option<String>,
    pub thread_ts: Option<String>,
}

#[derive(Debug, Clone)]
pub struct CreateUserGroupInput {
    pub name: String,
    pub handle: String,
    pub description: Option<String>,
    pub channel_ids: Option<Vec<String>>,
}

#[derive(Debug, Clone, Default)]
pub struct UpdateUserGroupFields {
    pub name: Option<String>,
    pub handle: Option<String>,
    pub description: Option<String>,
}

/// What inspecting one conversation for list_unread found.
enum UnreadOutcome {
    /// Unread messages; the entry for `conversations`.
    Unread(JsonValue),
    /// A call failed; the entry for `errors`.
    Failed(JsonValue),
    /// Nothing to report (read, archived, or not tracked).
    Nothing,
}

#[derive(Debug, Clone)]
pub struct SlackClient {
    bot_auth: String,
    user_auth: Option<String>,
    team_id: String,
    channel_guard: ChannelGuard,
    write_token: WriteTokenPreference,
}

impl SlackClient {
    pub fn new(
        slack: SlackCredentials,
        channel_guard: ChannelGuard,
        write_token: WriteTokenPreference,
    ) -> Self {
        Self {
            bot_auth: format!("Bearer {}", slack.bot_token),
            user_auth: slack.user_token.map(|t| format!("Bearer {t}")),
            team_id: slack.team_id,
            channel_guard,
            write_token,
        }
    }

    pub fn has_user_token(&self) -> bool {
        self.user_auth.is_some()
    }

    fn guard_params(&self, params: &JsonValue) -> Result<(), SlackClientError> {
        assert_params_allowed(&self.channel_guard, params)?;
        Ok(())
    }

    pub fn api(
        &self,
        method: &str,
        params: JsonValue,
        token: WriteTokenPreference,
        http_method: &str,
    ) -> Result<JsonValue, SlackClientError> {
        self.api_inner(method, params, token, http_method, true)
    }

    fn api_inner(
        &self,
        method: &str,
        params: JsonValue,
        token: WriteTokenPreference,
        http_method: &str,
        retry_rate_limit: bool,
    ) -> Result<JsonValue, SlackClientError> {
        self.guard_params(&params)?;

        let auth_header = match token {
            WriteTokenPreference::Bot => Some(self.bot_auth.as_str()),
            WriteTokenPreference::User => self.user_auth.as_deref(),
        };
        let Some(auth) = auth_header else {
            return Err(SlackClientError::UserTokenUnavailable {
                method: method.to_string(),
            });
        };

        let headers = vec![
            ("Authorization".to_string(), auth.to_string()),
            ("Content-Type".to_string(), "application/json".to_string()),
        ];

        let req = if http_method == "GET" {
            // qs.append(k, String(v)) for every non-null value.
            let mut qs_pairs = Vec::new();
            if let Some(entries) = params.as_object() {
                for (k, v) in entries {
                    if !v.is_null() {
                        qs_pairs.push((k.as_str(), js_string(v)));
                    }
                }
            }
            let qs = encode_query_params(&qs_pairs);
            HttpRequest {
                url: format!("https://slack.com/api/{method}?{qs}"),
                method: "GET".to_string(),
                headers,
                body: None,
            }
        } else {
            HttpRequest {
                url: format!("https://slack.com/api/{method}"),
                method: "POST".to_string(),
                headers,
                body: Some(params.to_json_string().into_bytes()),
            }
        };

        let max_retries = if retry_rate_limit {
            API_RATE_LIMIT_MAX_RETRIES
        } else {
            0
        };
        let mut rate_limit_attempt = 0usize;
        let res = loop {
            let res = execute_http(&req).map_err(SlackClientError::Message)?;
            if res.status == 429 {
                let retry_after = retry_after_seconds(&res);
                if rate_limit_attempt < max_retries {
                    let wait_secs = js_min(retry_after, API_RATE_LIMIT_MAX_WAIT_SECONDS);
                    if wait_secs.is_finite() && wait_secs > 0.0 {
                        sleep_for_retry(Duration::from_secs_f64(wait_secs));
                    }
                    rate_limit_attempt += 1;
                    continue;
                }
                let body_str = decode_utf8_like_text_decoder(&res.body);
                let mut data = match JsonValue::parse(&body_str) {
                    Ok(val @ JsonValue::Object(_)) => val,
                    _ => JsonValue::object(vec![
                        ("ok", false.into()),
                        ("error", "ratelimited".into()),
                    ]),
                };
                if data.get("ok").is_none() {
                    data.insert("ok", false.into());
                }
                if data.get("error").is_none() {
                    data.insert("error", "ratelimited".into());
                }
                data.insert("retry_after", JsonValue::Number(retry_after));
                return Ok(data);
            }
            break res;
        };
        // res.json(): UTF-8 with a leading BOM dropped.
        let body_str = decode_utf8_like_text_decoder(&res.body);
        let data = JsonValue::parse(&body_str).map_err(SlackClientError::Message)?;

        let err_str = data.get("error").and_then(|v| v.as_str()).unwrap_or("");
        if !is_ok(&data)
            && token == WriteTokenPreference::Bot
            && self.user_auth.is_some()
            && self.channel_guard.is_unrestricted()
            && (err_str == "not_in_channel" || err_str == "channel_not_found")
        {
            return self.api_inner(
                method,
                params,
                WriteTokenPreference::User,
                http_method,
                retry_rate_limit,
            );
        }

        Ok(data)
    }

    // ── Channels ────────────────────────────────────────────────────────
    //
    // Methods that take a count come in two forms. The `usize` one is the
    // original API; the `_num` one takes the number exactly as the tool
    // caller sent it, which is what the TypeScript handlers passed through
    // (dispatch.ts optNum): Slack received `-1` or `0.5` as written, not a
    // clamped or truncated integer.

    pub fn list_channels(
        &self,
        limit: Option<usize>,
        cursor: Option<&str>,
    ) -> Result<JsonValue, SlackClientError> {
        self.list_channels_num(limit.map(|n| n as f64), cursor)
    }

    pub fn list_channels_num(
        &self,
        limit: Option<f64>,
        cursor: Option<&str>,
    ) -> Result<JsonValue, SlackClientError> {
        let limit = limit.unwrap_or(100.0);
        if self.channel_guard.allowed.is_empty() {
            let types = if self.user_auth.is_some() {
                "public_channel,private_channel,im,mpim"
            } else {
                "public_channel"
            };
            let mut params = JsonValue::object(vec![
                ("types", types.into()),
                ("exclude_archived", "true".into()),
                ("limit", js_min(limit, 200.0).into()),
                ("team_id", self.team_id.as_str().into()),
            ]);
            if let Some(c) = cursor {
                if !c.is_empty() {
                    params.insert("cursor", c.into());
                }
            }
            let tok = if self.user_auth.is_some() {
                WriteTokenPreference::User
            } else {
                WriteTokenPreference::Bot
            };
            return self.api("conversations.list", params, tok, "GET");
        }

        let mut channels = Vec::new();
        for channel_id in &self.channel_guard.allowed {
            let data = self.api(
                "conversations.info",
                JsonValue::object(vec![("channel", channel_id.as_str().into())]),
                WriteTokenPreference::Bot,
                "GET",
            )?;
            let channel = data.get("channel");
            if is_ok(&data) && js_truthy(channel) {
                let ch = channel.unwrap_or(&JsonValue::Null);
                self.channel_guard
                    .assert_visibility_matches(channel_id, ch.get("is_private"))?;
                if !js_truthy(ch.get("is_archived")) {
                    channels.push(ch.clone());
                }
            }
        }
        Ok(JsonValue::object(vec![
            ("ok", true.into()),
            ("channels", JsonValue::Array(channels)),
            (
                "response_metadata",
                JsonValue::object(vec![("next_cursor", "".into())]),
            ),
        ]))
    }

    pub fn get_channel_info(&self, channel_id: &str) -> Result<JsonValue, SlackClientError> {
        let data = self.api(
            "conversations.info",
            JsonValue::object(vec![
                ("channel", channel_id.into()),
                ("include_num_members", "true".into()),
            ]),
            WriteTokenPreference::Bot,
            "GET",
        )?;
        if let Some(ch) = data.get("channel").filter(|c| js_truthy(Some(c))) {
            self.channel_guard
                .assert_visibility_matches(channel_id, ch.get("is_private"))?;
        }
        Ok(data)
    }

    pub fn verify_allowlist_visibility(&self) -> Result<(), SlackClientError> {
        for channel_id in &self.channel_guard.allowed {
            let data = match self.api(
                "conversations.info",
                JsonValue::object(vec![("channel", channel_id.as_str().into())]),
                WriteTokenPreference::Bot,
                "GET",
            ) {
                Ok(d) => d,
                Err(SlackClientError::UserTokenUnavailable { method }) => {
                    return Err(SlackClientError::UserTokenUnavailable { method });
                }
                Err(err) => {
                    return Err(SlackClientError::Message(format!(
                        "Could not verify allow-listed channel {channel_id} — Slack did not \
return a usable answer: {}. \
The allow-list has not been judged either way, so startup fails \
closed rather than serving unverified channels. Usually this is \
Slack or network availability; the underlying message above is \
the thing to read, not this sentence.",
                        err.message()
                    )));
                }
            };

            let channel = data.get("channel");
            if !is_ok(&data) || !js_truthy(channel) {
                let err_value = data.get("error");
                let remedy = match err_value.and_then(|v| v.as_str()) {
                    Some("channel_not_found") | Some("not_in_channel") => {
                        " Invite the bot to the channel first, then deploy — this check \
runs before the listener starts, so an uninvited private \
channel stops the server rather than degrading it."
                    }
                    _ => "",
                };
                return Err(SlackClientError::Message(format!(
                    "Cannot verify allow-listed channel {channel_id}: Slack returned \
{}. Every channel in SLACK_CHANNEL_IDS \
and SLACK_PRIVATE_CHANNEL_IDS must be readable by this bot.{remedy}",
                    string_or(err_value, "no channel")
                )));
            }

            self.channel_guard
                .assert_visibility_matches(channel_id, channel.and_then(|c| c.get("is_private")))?;
        }
        Ok(())
    }

    pub fn get_channel_history(
        &self,
        channel_id: &str,
        limit: Option<usize>,
    ) -> Result<JsonValue, SlackClientError> {
        self.get_channel_history_num(channel_id, limit.map(|n| n as f64))
    }

    pub fn get_channel_history_num(
        &self,
        channel_id: &str,
        limit: Option<f64>,
    ) -> Result<JsonValue, SlackClientError> {
        self.get_channel_history_with_options(
            channel_id,
            ChannelHistoryOptions {
                limit,
                ..ChannelHistoryOptions::default()
            },
        )
    }

    pub fn get_channel_history_with_options(
        &self,
        channel_id: &str,
        opts: ChannelHistoryOptions,
    ) -> Result<JsonValue, SlackClientError> {
        self.history_with_channel_param(channel_id.into(), opts)
    }

    pub fn get_channel_history_param(
        &self,
        channel_param: JsonValue,
        limit: Option<usize>,
    ) -> Result<JsonValue, SlackClientError> {
        self.history_with_channel_param(
            channel_param,
            ChannelHistoryOptions {
                limit: limit.map(|n| n as f64),
                ..ChannelHistoryOptions::default()
            },
        )
    }

    fn history_with_channel_param(
        &self,
        channel_param: JsonValue,
        opts: ChannelHistoryOptions,
    ) -> Result<JsonValue, SlackClientError> {
        let resolved_oldest = match opts.oldest.as_deref().filter(|s| !s.is_empty()) {
            Some(explicit) => Some(explicit.to_string()),
            None => match opts.since.as_deref() {
                Some(raw) => {
                    let now_secs = SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .unwrap_or(Duration::ZERO)
                        .as_secs_f64();
                    Some(parse_relative_since(raw, now_secs)?)
                }
                None => None,
            },
        };

        let mut params = JsonValue::object(vec![
            ("channel", channel_param),
            ("limit", opts.limit.unwrap_or(10.0).into()),
        ]);
        if let Some(oldest) = resolved_oldest {
            params.insert("oldest", oldest.into());
        }
        if let Some(latest) = opts.latest.as_deref().filter(|s| !s.is_empty()) {
            params.insert("latest", latest.into());
        }
        if let Some(cursor) = opts.cursor.as_deref().filter(|s| !s.is_empty()) {
            params.insert("cursor", cursor.into());
        }

        let mut data = self.api(
            "conversations.history",
            params,
            WriteTokenPreference::Bot,
            "GET",
        )?;

        if opts.include_activity == Some(false) && is_ok(&data) {
            if let Some(messages) = data.get("messages").and_then(|v| v.as_array()) {
                let filtered: Vec<JsonValue> = messages
                    .iter()
                    .filter(|m| {
                        let subtype = m.get("subtype").and_then(|v| v.as_str()).unwrap_or("");
                        !UNREAD_IGNORED_SUBTYPES.contains(&subtype)
                    })
                    .cloned()
                    .collect();
                data.insert("messages", JsonValue::Array(filtered));
            }
        }
        Ok(data)
    }

    pub fn get_thread_replies(
        &self,
        channel_id: &str,
        thread_ts: &str,
    ) -> Result<JsonValue, SlackClientError> {
        self.get_thread_replies_with_options(channel_id, thread_ts, ThreadRepliesOptions::default())
    }

    pub fn get_thread_replies_with_options(
        &self,
        channel_id: &str,
        thread_ts: &str,
        opts: ThreadRepliesOptions,
    ) -> Result<JsonValue, SlackClientError> {
        let mut params = JsonValue::object(vec![
            ("channel", channel_id.into()),
            ("ts", thread_ts.into()),
        ]);
        if let Some(limit) = opts.limit {
            params.insert("limit", js_min(limit, 200.0).into());
        }
        if let Some(cursor) = opts.cursor.as_deref().filter(|s| !s.is_empty()) {
            params.insert("cursor", cursor.into());
        }
        if let Some(oldest) = opts.oldest.as_deref().filter(|s| !s.is_empty()) {
            params.insert("oldest", oldest.into());
        }
        if let Some(latest) = opts.latest.as_deref().filter(|s| !s.is_empty()) {
            params.insert("latest", latest.into());
        }
        self.api(
            "conversations.replies",
            params,
            WriteTokenPreference::Bot,
            "GET",
        )
    }

    pub fn get_message(
        &self,
        channel_id: &str,
        ts: &str,
        thread_ts: Option<&str>,
    ) -> Result<JsonValue, SlackClientError> {
        if let Some(thread_ts) = thread_ts {
            let data = self.api(
                "conversations.replies",
                JsonValue::object(vec![
                    ("channel", channel_id.into()),
                    ("ts", thread_ts.into()),
                ]),
                WriteTokenPreference::Bot,
                "GET",
            )?;
            if !is_ok(&data) {
                return Ok(data);
            }
            let found = data
                .get("messages")
                .and_then(|v| v.as_array())
                .and_then(|msgs| {
                    msgs.iter()
                        .find(|m| m.get("ts").and_then(|v| v.as_str()) == Some(ts))
                })
                .cloned();
            return Ok(match found {
                Some(message) => JsonValue::object(vec![("ok", true.into()), ("message", message)]),
                None => JsonValue::object(vec![
                    ("ok", false.into()),
                    ("error", "message_not_found".into()),
                ]),
            });
        }

        let data = self.api(
            "conversations.history",
            JsonValue::object(vec![
                ("channel", channel_id.into()),
                ("latest", ts.into()),
                ("oldest", ts.into()),
                ("inclusive", "true".into()),
                ("limit", 1i64.into()),
            ]),
            WriteTokenPreference::Bot,
            "GET",
        )?;
        if !is_ok(&data) {
            return Ok(data);
        }
        let found = data
            .get("messages")
            .and_then(|v| v.as_array())
            .and_then(|msgs| {
                msgs.iter()
                    .find(|m| m.get("ts").and_then(|v| v.as_str()) == Some(ts))
            })
            .cloned();
        Ok(match found {
            Some(message) => JsonValue::object(vec![("ok", true.into()), ("message", message)]),
            None => JsonValue::object(vec![
                ("ok", false.into()),
                ("error", "message_not_found".into()),
            ]),
        })
    }

    pub fn get_permalink(&self, channel_id: &str, ts: &str) -> Result<JsonValue, SlackClientError> {
        self.api(
            "chat.getPermalink",
            JsonValue::object(vec![
                ("channel", channel_id.into()),
                ("message_ts", ts.into()),
            ]),
            WriteTokenPreference::Bot,
            "GET",
        )
    }

    pub fn set_channel_topic(
        &self,
        channel_id: &str,
        topic: &str,
    ) -> Result<JsonValue, SlackClientError> {
        self.api(
            "conversations.setTopic",
            JsonValue::object(vec![
                ("channel", channel_id.into()),
                ("topic", topic.into()),
            ]),
            WriteTokenPreference::User,
            "POST",
        )
    }

    // ── Channel membership ─────────────────────────────────────────────

    pub fn join_channel(
        &self,
        channel_id: &str,
        as_token: WriteTokenPreference,
    ) -> Result<JsonValue, SlackClientError> {
        self.api(
            "conversations.join",
            JsonValue::object(vec![("channel", channel_id.into())]),
            as_token,
            "POST",
        )
    }

    pub fn leave_channel(
        &self,
        channel_id: &str,
        as_token: WriteTokenPreference,
    ) -> Result<JsonValue, SlackClientError> {
        self.api(
            "conversations.leave",
            JsonValue::object(vec![("channel", channel_id.into())]),
            as_token,
            "POST",
        )
    }

    pub fn mark_read(
        &self,
        channel_id: &str,
        timestamp: &str,
    ) -> Result<JsonValue, SlackClientError> {
        self.api(
            "conversations.mark",
            JsonValue::object(vec![
                ("channel", channel_id.into()),
                ("ts", timestamp.into()),
            ]),
            WriteTokenPreference::User,
            "POST",
        )
    }

    pub fn list_unread(
        &self,
        max_per_conversation: Option<usize>,
    ) -> Result<JsonValue, SlackClientError> {
        self.list_unread_num(max_per_conversation.map(|n| n as f64))
    }

    /// Lists the conversations the authenticated human has unread messages
    /// in: per conversation, where the read cursor is (`conversations.info`)
    /// and what was posted after it (`conversations.history`), four
    /// conversations at a time as the TypeScript client did
    /// (`UNREAD_CONCURRENCY`).
    ///
    /// Results are assembled in candidate order before the final sort, so
    /// the output is deterministic. TypeScript pushed in completion order,
    /// which equals candidate order whenever Slack answers in the order
    /// asked; only conversations with an identical `latest_ts`, and the
    /// `errors` list, could ever have come out in a different order there.
    pub fn list_unread_num(
        &self,
        max_per_conversation: Option<f64>,
    ) -> Result<JsonValue, SlackClientError> {
        let per_conversation = js_min(js_max(1.0, max_per_conversation.unwrap_or(100.0)), 200.0);
        let mut skipped = Vec::new();
        let mut truncated = false;
        let mut candidates: Vec<String> = self.channel_guard.allowed.clone();

        if candidates.is_empty() {
            // One listing per type group, so a token without im:read still
            // gets its channels rather than one missing_scope for everything.
            for types in ["public_channel,private_channel", "im", "mpim"] {
                let mut cursor: Option<JsonValue> = None;
                for page in 0.. {
                    let mut params = JsonValue::object(vec![
                        ("types", types.into()),
                        ("exclude_archived", "true".into()),
                        ("limit", 200i64.into()),
                        ("team_id", self.team_id.as_str().into()),
                    ]);
                    if let Some(c) = &cursor {
                        params.insert("cursor", c.clone());
                    }
                    // No api()-level 429 retry: list_unread keeps main's call count.
                    let data = self.api_inner(
                        "users.conversations",
                        params,
                        WriteTokenPreference::User,
                        "GET",
                        false,
                    )?;
                    if !is_ok(&data) {
                        skipped.push(JsonValue::object(vec![
                            ("types", types.into()),
                            ("error", value_or(data.get("error"), "unknown_error")),
                        ]));
                        break;
                    }
                    if let Some(chs) = data.get("channels").and_then(|v| v.as_array()) {
                        for c in chs {
                            if let Some(id) = c.get("id").and_then(|v| v.as_str()) {
                                candidates.push(id.to_string());
                            }
                        }
                    }
                    // `data.response_metadata?.next_cursor || undefined`
                    cursor = data
                        .get("response_metadata")
                        .and_then(|m| m.get("next_cursor"))
                        .filter(|c| js_truthy(Some(c)))
                        .cloned();
                    if cursor.is_none() {
                        break;
                    }
                    if page >= UNREAD_MAX_PAGES - 1 {
                        truncated = true;
                        break;
                    }
                }
            }
        }

        // `[...new Set(candidates)]`: first occurrence wins.
        let mut seen = HashSet::new();
        candidates.retain(|id| seen.insert(id.clone()));

        let outcomes = self.inspect_unread_concurrently(&candidates, per_conversation)?;

        let mut conversations: Vec<JsonValue> = Vec::new();
        let mut errors: Vec<JsonValue> = Vec::new();
        for outcome in outcomes {
            match outcome {
                UnreadOutcome::Unread(entry) => conversations.push(entry),
                UnreadOutcome::Failed(err) => errors.push(err),
                UnreadOutcome::Nothing => {}
            }
        }

        // String(b.latest_ts).localeCompare(String(a.latest_ts)), stable.
        // Slack timestamps are digits and one dot, which ICU's root collation
        // orders exactly as bytes; a code-unit comparison is used here.
        conversations.sort_by(|a, b| {
            let a_ts = template(a.get("latest_ts"));
            let b_ts = template(b.get("latest_ts"));
            b_ts.cmp(&a_ts)
        });

        Ok(JsonValue::object(vec![
            ("ok", true.into()),
            ("conversations", JsonValue::Array(conversations)),
            ("checked", candidates.len().into()),
            ("truncated", truncated.into()),
            ("skipped", JsonValue::Array(skipped)),
            ("errors", JsonValue::Array(errors)),
        ]))
    }

    /// Runs [`Self::inspect_unread`] over `candidates` on
    /// [`UNREAD_CONCURRENCY`] worker threads, each taking the next unclaimed
    /// conversation, and returns the outcomes in candidate order.
    ///
    /// The first error stops every worker from claiming more and is returned
    /// for the whole listing, as the rejected `Promise.all` did.
    fn inspect_unread_concurrently(
        &self,
        candidates: &[String],
        per_conversation: f64,
    ) -> Result<Vec<UnreadOutcome>, SlackClientError> {
        let next = AtomicUsize::new(0);
        let abort = AtomicBool::new(false);
        let failure: Mutex<Option<SlackClientError>> = Mutex::new(None);
        let slots: Mutex<Vec<Option<UnreadOutcome>>> =
            Mutex::new((0..candidates.len()).map(|_| None).collect());
        let mock = current_mock();

        std::thread::scope(|scope| {
            for _ in 0..UNREAD_CONCURRENCY.min(candidates.len()) {
                let mock = mock.clone();
                let (next, abort, failure, slots) = (&next, &abort, &failure, &slots);
                scope.spawn(move || {
                    install_mock(mock);
                    loop {
                        if abort.load(Ordering::SeqCst) {
                            break;
                        }
                        let i = next.fetch_add(1, Ordering::SeqCst);
                        let Some(id) = candidates.get(i) else {
                            break;
                        };
                        match self.inspect_unread(id, per_conversation) {
                            Ok(outcome) => {
                                slots.lock().unwrap_or_else(|p| p.into_inner())[i] = Some(outcome);
                            }
                            Err(err) => {
                                abort.store(true, Ordering::SeqCst);
                                let mut slot = failure.lock().unwrap_or_else(|p| p.into_inner());
                                if slot.is_none() {
                                    *slot = Some(err);
                                }
                                break;
                            }
                        }
                    }
                });
            }
        });

        if let Some(err) = failure.into_inner().unwrap_or_else(|p| p.into_inner()) {
            return Err(err);
        }
        Ok(slots
            .into_inner()
            .unwrap_or_else(|p| p.into_inner())
            .into_iter()
            .map(|o| o.unwrap_or(UnreadOutcome::Nothing))
            .collect())
    }

    /// A rate limit is waited out and asked again, up to
    /// [`UNREAD_MAX_RETRIES`] times: a listing that drops the rate-limited
    /// conversations reads as "nothing unread" when it means "did not look".
    fn patient(&self, method: &str, params: JsonValue) -> Result<JsonValue, SlackClientError> {
        let mut attempt = 0;
        loop {
            let data = self.api_inner(
                method,
                params.clone(),
                WriteTokenPreference::User,
                "GET",
                false,
            )?;
            let err = data.get("error").and_then(|v| v.as_str());
            if err != Some("ratelimited") || attempt >= UNREAD_MAX_RETRIES {
                return Ok(data);
            }
            let wait = unread_backoff(&data);
            if !wait.is_zero() {
                std::thread::sleep(wait);
            }
            attempt += 1;
        }
    }

    fn inspect_unread(
        &self,
        id: &str,
        per_conversation: f64,
    ) -> Result<UnreadOutcome, SlackClientError> {
        let info = self.patient(
            "conversations.info",
            JsonValue::object(vec![("channel", id.into())]),
        )?;
        let channel = match info.get("channel") {
            Some(c) if is_ok(&info) && js_truthy(Some(c)) => c,
            _ => {
                return Ok(UnreadOutcome::Failed(JsonValue::object(vec![
                    ("id", id.into()),
                    ("error", value_or(info.get("error"), "unknown_error")),
                ])));
            }
        };
        self.channel_guard
            .assert_visibility_matches(id, channel.get("is_private"))?;
        // No cursor (the field is absent) means Slack does not track this
        // conversation for the caller, so "unread" has no meaning for it.
        // A cursor of null or "" is present, and reads as never read.
        let last_read = match channel.get("last_read") {
            Some(v) if !js_truthy(channel.get("is_archived")) => v,
            _ => return Ok(UnreadOutcome::Nothing),
        };

        // `Number(last_read) === 0 ? "0" : last_read`: a never-opened
        // conversation reports all zeros, which history rejects.
        let oldest = if js_to_number(last_read) == 0.0 {
            JsonValue::str("0")
        } else {
            last_read.clone()
        };
        let history = self.patient(
            "conversations.history",
            JsonValue::object(vec![
                ("channel", id.into()),
                ("oldest", oldest),
                ("limit", per_conversation.into()),
            ]),
        )?;
        if !is_ok(&history) {
            return Ok(UnreadOutcome::Failed(JsonValue::object(vec![
                ("id", id.into()),
                ("error", value_or(history.get("error"), "unknown_error")),
            ])));
        }

        // Slack's own badge ignores membership notices.
        let messages: Vec<&JsonValue> = history
            .get("messages")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter(|m| {
                        let subtype = m.get("subtype").and_then(|v| v.as_str()).unwrap_or("");
                        !UNREAD_IGNORED_SUBTYPES.contains(&subtype)
                    })
                    .collect()
            })
            .unwrap_or_default();
        if messages.is_empty() {
            return Ok(UnreadOutcome::Nothing);
        }

        let conv_type = if js_truthy(channel.get("is_im")) {
            "im"
        } else if js_truthy(channel.get("is_mpim")) {
            "mpim"
        } else if js_truthy(channel.get("is_private")) {
            "private_channel"
        } else {
            "public_channel"
        };

        let mut entry = JsonValue::object(vec![("id", id.into())]);
        for key in ["name", "user"] {
            if let Some(v) = channel.get(key).filter(|v| js_truthy(Some(v))) {
                entry.insert(key, v.clone());
            }
        }
        entry.insert("type", conv_type.into());
        entry.insert("unread_count", messages.len().into());
        entry.insert(
            "unread_count_is_minimum",
            js_truthy(history.get("has_more")).into(),
        );
        entry.insert("last_read", last_read.clone());
        // Newest first: this is the timestamp slack_mark_read wants. An
        // absent ts is `undefined`, which JSON.stringify leaves out.
        if let Some(ts) = messages[0].get("ts") {
            entry.insert("latest_ts", ts.clone());
        }
        Ok(UnreadOutcome::Unread(entry))
    }

    pub fn list_channel_members(
        &self,
        channel_id: &str,
        limit: Option<usize>,
        cursor: Option<&str>,
    ) -> Result<JsonValue, SlackClientError> {
        self.list_channel_members_num(channel_id, limit.map(|n| n as f64), cursor)
    }

    pub fn list_channel_members_num(
        &self,
        channel_id: &str,
        limit: Option<f64>,
        cursor: Option<&str>,
    ) -> Result<JsonValue, SlackClientError> {
        let mut params = JsonValue::object(vec![
            ("channel", channel_id.into()),
            ("limit", js_min(limit.unwrap_or(100.0), 200.0).into()),
        ]);
        if let Some(c) = cursor {
            if !c.is_empty() {
                params.insert("cursor", c.into());
            }
        }
        self.api(
            "conversations.members",
            params,
            WriteTokenPreference::Bot,
            "GET",
        )
    }

    pub fn invite_to_channel(
        &self,
        channel_id: &str,
        user_ids: &[String],
    ) -> Result<JsonValue, SlackClientError> {
        self.api(
            "conversations.invite",
            JsonValue::object(vec![
                ("channel", channel_id.into()),
                ("users", user_ids.join(",").into()),
            ]),
            WriteTokenPreference::User,
            "POST",
        )
    }

    // ── Custom emoji ───────────────────────────────────────────────────

    /// Lists the workspace's custom emoji, filtered client-side as
    /// slackClient.ts listEmoji did. Values are kept whatever their type;
    /// with aliases excluded, a value that is not a string fails the call
    /// with the TypeError JavaScript raised calling `startsWith` on it. The
    /// query is lower-cased with full Unicode rules, as `toLowerCase()` is.
    pub fn list_emoji(
        &self,
        query: Option<&str>,
        include_aliases: Option<bool>,
    ) -> Result<JsonValue, SlackClientError> {
        let include_aliases = include_aliases.unwrap_or(true);
        let data = self.api(
            "emoji.list",
            JsonValue::empty_object(),
            WriteTokenPreference::Bot,
            "GET",
        )?;
        if !is_ok(&data) || !js_truthy(data.get("emoji")) {
            return Ok(data);
        }
        // Object.entries(data.emoji). An array's entries are keyed by index;
        // any other truthy non-object has none worth naming here.
        let entries: Vec<(String, JsonValue)> = match data.get("emoji") {
            Some(JsonValue::Object(o)) => o.clone(),
            Some(JsonValue::Array(a)) => a
                .iter()
                .enumerate()
                .map(|(i, v)| (i.to_string(), v.clone()))
                .collect(),
            _ => Vec::new(),
        };
        // `needle && ...`: an empty query filters nothing.
        let needle = query.filter(|q| !q.is_empty()).map(str::to_lowercase);
        let mut filtered = Vec::new();
        for (name, value) in entries {
            if !include_aliases {
                let is_alias = match &value {
                    JsonValue::String(s) => s.starts_with("alias:"),
                    JsonValue::Null => {
                        return Err(SlackClientError::Message(
                            "Cannot read properties of null (reading 'startsWith')".to_string(),
                        ))
                    }
                    _ => {
                        return Err(SlackClientError::Message(
                            "value.startsWith is not a function".to_string(),
                        ))
                    }
                };
                if is_alias {
                    continue;
                }
            }
            if let Some(n) = &needle {
                if !name.to_lowercase().contains(n.as_str()) {
                    continue;
                }
            }
            filtered.push((name, value));
        }
        let mut out = data.clone();
        out.insert("emoji", JsonValue::Object(filtered));
        Ok(out)
    }

    // ── Users ──────────────────────────────────────────────────────────

    pub fn get_users(
        &self,
        limit: Option<usize>,
        cursor: Option<&str>,
    ) -> Result<JsonValue, SlackClientError> {
        self.get_users_num(limit.map(|n| n as f64), cursor)
    }

    pub fn get_users_num(
        &self,
        limit: Option<f64>,
        cursor: Option<&str>,
    ) -> Result<JsonValue, SlackClientError> {
        let mut params = JsonValue::object(vec![
            ("limit", js_min(limit.unwrap_or(100.0), 200.0).into()),
            ("team_id", self.team_id.as_str().into()),
        ]);
        if let Some(c) = cursor {
            if !c.is_empty() {
                params.insert("cursor", c.into());
            }
        }
        self.api("users.list", params, WriteTokenPreference::Bot, "GET")
    }

    pub fn get_user_profile(&self, user_id: &str) -> Result<JsonValue, SlackClientError> {
        self.api(
            "users.profile.get",
            JsonValue::object(vec![
                ("user", user_id.into()),
                ("include_labels", "true".into()),
            ]),
            WriteTokenPreference::Bot,
            "GET",
        )
    }

    pub fn whoami(&self) -> Result<JsonValue, SlackClientError> {
        let bot = self.api(
            "auth.test",
            JsonValue::empty_object(),
            WriteTokenPreference::Bot,
            "POST",
        )?;
        let user = if self.user_auth.is_some() {
            self.api(
                "auth.test",
                JsonValue::empty_object(),
                WriteTokenPreference::User,
                "POST",
            )?
        } else {
            JsonValue::Null
        };
        Ok(JsonValue::object(vec![("bot", bot), ("user", user)]))
    }

    // ── Search ─────────────────────────────────────────────────────────

    pub fn search_messages(
        &self,
        query: &str,
        count: Option<usize>,
        sort: Option<&str>,
    ) -> Result<JsonValue, SlackClientError> {
        self.search_messages_num(query, count.map(|n| n as f64), sort)
    }

    pub fn search_messages_num(
        &self,
        query: &str,
        count: Option<f64>,
        sort: Option<&str>,
    ) -> Result<JsonValue, SlackClientError> {
        self.search_messages_with_options(
            query,
            SearchOptions {
                count,
                sort: sort.map(str::to_string),
                ..SearchOptions::default()
            },
        )
    }

    pub fn search_messages_with_options(
        &self,
        query: &str,
        opts: SearchOptions,
    ) -> Result<JsonValue, SlackClientError> {
        self.search("search.messages", query, opts)
    }

    pub fn search_files(
        &self,
        query: &str,
        count: Option<usize>,
        sort: Option<&str>,
    ) -> Result<JsonValue, SlackClientError> {
        self.search_files_num(query, count.map(|n| n as f64), sort)
    }

    pub fn search_files_num(
        &self,
        query: &str,
        count: Option<f64>,
        sort: Option<&str>,
    ) -> Result<JsonValue, SlackClientError> {
        self.search_files_with_options(
            query,
            SearchOptions {
                count,
                sort: sort.map(str::to_string),
                ..SearchOptions::default()
            },
        )
    }

    pub fn search_files_with_options(
        &self,
        query: &str,
        opts: SearchOptions,
    ) -> Result<JsonValue, SlackClientError> {
        self.search("search.files", query, opts)
    }

    fn search(
        &self,
        method: &str,
        query: &str,
        opts: SearchOptions,
    ) -> Result<JsonValue, SlackClientError> {
        if let Some(dir) = opts.sort_dir.as_deref().filter(|s| !s.is_empty()) {
            if dir != "asc" && dir != "desc" {
                return Err(SlackClientError::Message(format!(
                    "Argument sort_dir must be \"asc\" or \"desc\" (got {dir:?})."
                )));
            }
        }
        if let Some(page) = opts.page {
            if !page.is_finite() || page < 1.0 || page.fract() != 0.0 {
                return Err(SlackClientError::Message(format!(
                    "Argument page must be a whole number >= 1 (got {}).",
                    js_number_to_string(page)
                )));
            }
        }
        let mut params = JsonValue::object(vec![
            ("query", query.into()),
            ("count", js_min(opts.count.unwrap_or(20.0), 100.0).into()),
            ("sort", opts.sort.as_deref().unwrap_or("score").into()),
        ]);
        if let Some(dir) = opts.sort_dir.as_deref().filter(|s| !s.is_empty()) {
            params.insert("sort_dir", dir.into());
        }
        if let Some(page) = opts.page {
            params.insert("page", page.into());
        }
        let mut data = self.api(method, params, WriteTokenPreference::User, "GET")?;
        if !self.channel_guard.is_unrestricted() && is_ok(&data) {
            let container_key = if method == "search.files" {
                "files"
            } else {
                "messages"
            };
            let mut filtered_out = 0usize;
            if let Some(mut updated_container) = data.get(container_key).cloned() {
                if let Some(matches) = updated_container.get("matches").and_then(|v| v.as_array()) {
                    let mut kept = Vec::with_capacity(matches.len());
                    for item in matches {
                        let allowed = if method == "search.files" {
                            search_file_match_allowed(&self.channel_guard, item)
                        } else {
                            search_message_match_allowed(&self.channel_guard, item)
                        };
                        if allowed {
                            kept.push(item.clone());
                        } else {
                            filtered_out += 1;
                        }
                    }
                    updated_container.insert("matches", JsonValue::Array(kept));
                }
                if let Some(entries) = updated_container.as_object_mut() {
                    entries
                        .retain(|(k, _)| !matches!(k.as_str(), "total" | "paging" | "pagination"));
                }
                data.insert(container_key, updated_container);
            }
            if let Some(entries) = data.as_object_mut() {
                entries.retain(|(k, _)| !matches!(k.as_str(), "total" | "paging" | "pagination"));
            }
            data.insert("filtered_out", filtered_out.into());
        }
        Ok(data)
    }

    // ── Messaging ──────────────────────────────────────────────────────

    pub fn post_message(
        &self,
        channel_id: &str,
        text: &str,
    ) -> Result<JsonValue, SlackClientError> {
        self.post_message_with_options(channel_id, text, PostMessageOptions::default())
    }

    pub fn post_message_with_options(
        &self,
        channel_id: &str,
        text: &str,
        opts: PostMessageOptions,
    ) -> Result<JsonValue, SlackClientError> {
        let mut params =
            JsonValue::object(vec![("channel", channel_id.into()), ("text", text.into())]);
        if let Some(ts) = opts.thread_ts.as_deref().filter(|s| !s.is_empty()) {
            params.insert("thread_ts", ts.into());
        }
        if let Some(rb) = opts.reply_broadcast {
            params.insert("reply_broadcast", rb.into());
        }
        if let Some(ul) = opts.unfurl_links {
            params.insert("unfurl_links", ul.into());
        }
        self.api("chat.postMessage", params, self.write_token, "POST")
    }

    pub fn reply_to_thread(
        &self,
        channel_id: &str,
        thread_ts: &str,
        text: &str,
    ) -> Result<JsonValue, SlackClientError> {
        self.reply_to_thread_with_options(
            channel_id,
            thread_ts,
            text,
            ReplyToThreadOptions::default(),
        )
    }

    pub fn reply_to_thread_with_options(
        &self,
        channel_id: &str,
        thread_ts: &str,
        text: &str,
        opts: ReplyToThreadOptions,
    ) -> Result<JsonValue, SlackClientError> {
        let mut params = JsonValue::object(vec![
            ("channel", channel_id.into()),
            ("thread_ts", thread_ts.into()),
            ("text", text.into()),
        ]);
        if let Some(rb) = opts.reply_broadcast {
            params.insert("reply_broadcast", rb.into());
        }
        if let Some(ul) = opts.unfurl_links {
            params.insert("unfurl_links", ul.into());
        }
        self.api("chat.postMessage", params, self.write_token, "POST")
    }

    pub fn update_message(
        &self,
        channel_id: &str,
        ts: &str,
        text: &str,
    ) -> Result<JsonValue, SlackClientError> {
        self.api(
            "chat.update",
            JsonValue::object(vec![
                ("channel", channel_id.into()),
                ("ts", ts.into()),
                ("text", text.into()),
            ]),
            self.write_token,
            "POST",
        )
    }

    pub fn add_reaction(
        &self,
        channel_id: &str,
        timestamp: &str,
        reaction: &str,
    ) -> Result<JsonValue, SlackClientError> {
        self.api(
            "reactions.add",
            JsonValue::object(vec![
                ("channel", channel_id.into()),
                ("timestamp", timestamp.into()),
                ("name", reaction.into()),
            ]),
            WriteTokenPreference::User,
            "POST",
        )
    }

    pub fn remove_reaction(
        &self,
        channel_id: &str,
        timestamp: &str,
        emoji: &str,
    ) -> Result<JsonValue, SlackClientError> {
        self.api(
            "reactions.remove",
            JsonValue::object(vec![
                ("channel", channel_id.into()),
                ("timestamp", timestamp.into()),
                ("name", emoji.into()),
            ]),
            WriteTokenPreference::User,
            "POST",
        )
    }

    // ── Pins ───────────────────────────────────────────────────────────

    pub fn list_pins(&self, channel_id: &str) -> Result<JsonValue, SlackClientError> {
        let tok = if self.user_auth.is_some() {
            WriteTokenPreference::User
        } else {
            WriteTokenPreference::Bot
        };
        self.api(
            "pins.list",
            JsonValue::object(vec![("channel", channel_id.into())]),
            tok,
            "GET",
        )
    }

    pub fn pin_message(
        &self,
        channel_id: &str,
        timestamp: &str,
    ) -> Result<JsonValue, SlackClientError> {
        self.api(
            "pins.add",
            JsonValue::object(vec![
                ("channel", channel_id.into()),
                ("timestamp", timestamp.into()),
            ]),
            WriteTokenPreference::User,
            "POST",
        )
    }

    pub fn unpin_message(
        &self,
        channel_id: &str,
        timestamp: &str,
    ) -> Result<JsonValue, SlackClientError> {
        self.api(
            "pins.remove",
            JsonValue::object(vec![
                ("channel", channel_id.into()),
                ("timestamp", timestamp.into()),
            ]),
            WriteTokenPreference::User,
            "POST",
        )
    }

    // ── Bookmarks ──────────────────────────────────────────────────────

    pub fn list_bookmarks(&self, channel_id: &str) -> Result<JsonValue, SlackClientError> {
        let tok = if self.user_auth.is_some() {
            WriteTokenPreference::User
        } else {
            WriteTokenPreference::Bot
        };
        self.api(
            "bookmarks.list",
            JsonValue::object(vec![("channel_id", channel_id.into())]),
            tok,
            "GET",
        )
    }

    pub fn add_bookmark(
        &self,
        channel_id: &str,
        title: &str,
        link: &str,
        emoji: Option<&str>,
    ) -> Result<JsonValue, SlackClientError> {
        let mut params = JsonValue::object(vec![
            ("channel_id", channel_id.into()),
            ("title", title.into()),
            ("type", "link".into()),
            ("link", link.into()),
        ]);
        if let Some(e) = emoji {
            if !e.is_empty() {
                params.insert("emoji", e.into());
            }
        }
        self.api("bookmarks.add", params, WriteTokenPreference::User, "POST")
    }

    // ── Canvases ───────────────────────────────────────────────────────

    pub fn create_canvas(
        &self,
        title: Option<&str>,
        markdown: Option<&str>,
        channel_id: Option<&str>,
    ) -> Result<JsonValue, SlackClientError> {
        let mut params = JsonValue::empty_object();
        if let Some(t) = title {
            if !t.is_empty() {
                params.insert("title", t.into());
            }
        }
        if let Some(md) = markdown {
            if !md.is_empty() {
                params.insert(
                    "document_content",
                    JsonValue::object(vec![("type", "markdown".into()), ("markdown", md.into())]),
                );
            }
        }
        if let Some(cid) = channel_id {
            if !cid.is_empty() {
                params.insert("channel_id", cid.into());
            }
        }
        self.api(
            "canvases.create",
            params,
            WriteTokenPreference::User,
            "POST",
        )
    }

    pub fn edit_canvas(
        &self,
        canvas_id: &str,
        operation: &str,
        markdown: Option<&str>,
        section_id: Option<&str>,
    ) -> Result<JsonValue, SlackClientError> {
        if !self.channel_guard.is_unrestricted() {
            self.fetch_file_info(canvas_id)?;
        }
        let mut change = JsonValue::object(vec![("operation", operation.into())]);
        if let Some(md) = markdown.filter(|s| !s.is_empty()) {
            if operation == "rename" {
                change.insert(
                    "title_content",
                    JsonValue::object(vec![("type", "markdown".into()), ("markdown", md.into())]),
                );
            } else if operation != "delete" {
                change.insert(
                    "document_content",
                    JsonValue::object(vec![("type", "markdown".into()), ("markdown", md.into())]),
                );
            }
        }
        if let Some(sid) = section_id.filter(|s| !s.is_empty()) {
            change.insert("section_id", sid.into());
        }
        self.api(
            "canvases.edit",
            JsonValue::object(vec![
                ("canvas_id", canvas_id.into()),
                ("changes", JsonValue::Array(vec![change])),
            ]),
            WriteTokenPreference::User,
            "POST",
        )
    }

    pub fn lookup_canvas_sections(
        &self,
        canvas_id: &str,
        section_types: Option<&[String]>,
        contains_text: Option<&str>,
    ) -> Result<JsonValue, SlackClientError> {
        if !self.channel_guard.is_unrestricted() {
            self.fetch_file_info(canvas_id)?;
        }
        let mut criteria = JsonValue::empty_object();
        if let Some(types) = section_types.filter(|t| !t.is_empty()) {
            criteria.insert(
                "section_types",
                JsonValue::Array(types.iter().map(|s| s.as_str().into()).collect()),
            );
        }
        if let Some(text) = contains_text.filter(|s| !s.is_empty()) {
            criteria.insert("contains_text", text.into());
        }
        self.api(
            "canvases.sections.lookup",
            JsonValue::object(vec![
                ("canvas_id", canvas_id.into()),
                ("criteria", criteria),
            ]),
            WriteTokenPreference::User,
            "POST",
        )
    }

    pub fn delete_canvas(&self, canvas_id: &str) -> Result<JsonValue, SlackClientError> {
        if !self.channel_guard.is_unrestricted() {
            self.fetch_file_info(canvas_id)?;
        }
        self.api(
            "canvases.delete",
            JsonValue::object(vec![("canvas_id", canvas_id.into())]),
            WriteTokenPreference::User,
            "POST",
        )
    }

    // ── Files ──────────────────────────────────────────────────────────

    fn fetch_file_info(
        &self,
        file_id: &str,
    ) -> Result<(JsonValue, WriteTokenPreference), SlackClientError> {
        let mut token = WriteTokenPreference::Bot;
        let mut data = self.api(
            "files.info",
            JsonValue::object(vec![("file", file_id.into())]),
            WriteTokenPreference::Bot,
            "GET",
        )?;
        // The bot cannot see files in conversations it is not in. Slack says
        // `file_not_found` for most files and `not_visible` for canvases.
        // The share check below still applies to whatever the user token sees.
        let err_str = data.get("error").and_then(|v| v.as_str()).unwrap_or("");
        if !is_ok(&data)
            && (err_str == "file_not_found" || err_str == "not_visible")
            && self.user_auth.is_some()
        {
            token = WriteTokenPreference::User;
            data = self.api(
                "files.info",
                JsonValue::object(vec![("file", file_id.into())]),
                WriteTokenPreference::User,
                "GET",
            )?;
        }
        let file = match data.get("file") {
            Some(f) if is_ok(&data) && js_truthy(Some(f)) => f.clone(),
            _ => {
                return Err(SlackClientError::Message(format!(
                    "files.info failed: {}",
                    string_or(data.get("error"), "no file returned")
                )));
            }
        };
        assert_file_share_allowed(&self.channel_guard, &FileShares::from_json(&file))?;
        Ok((file, token))
    }

    fn fetch_file_bytes(
        &self,
        file: &JsonValue,
        token: WriteTokenPreference,
    ) -> Result<Vec<u8>, SlackClientError> {
        let url_private = if is_canvas_file(file) {
            file.get("url_private")
                .filter(|v| js_truthy(Some(v)))
                .or_else(|| file.get("url_private_download"))
        } else {
            file.get("url_private")
        };
        if !js_truthy(url_private) {
            return Err(SlackClientError::Message(format!(
                "File {} has no downloadable content.",
                template(file.get("id"))
            )));
        }
        let auth_header = match token {
            WriteTokenPreference::Bot => Some(self.bot_auth.as_str()),
            WriteTokenPreference::User => self.user_auth.as_deref(),
        };
        let Some(auth) = auth_header else {
            return Err(SlackClientError::UserTokenUnavailable {
                method: "files download".to_string(),
            });
        };
        let res = execute_transfer(&HttpRequest {
            url: template(url_private),
            method: "GET".to_string(),
            headers: vec![("Authorization".to_string(), auth.to_string())],
            body: None,
        })
        .map_err(SlackClientError::Message)?;
        if !(200..300).contains(&res.status) {
            return Err(SlackClientError::Message(format!(
                "Downloading file {} failed: HTTP {}",
                template(file.get("id")),
                res.status
            )));
        }
        Ok(res.body)
    }

    pub fn get_file_info(&self, file_id: &str) -> Result<JsonValue, SlackClientError> {
        let (file, _) = self.fetch_file_info(file_id)?;
        Ok(JsonValue::object(vec![
            ("ok", true.into()),
            ("file", public_file(&file)),
        ]))
    }

    pub fn read_file(
        &self,
        file_id: &str,
        max_bytes: Option<usize>,
    ) -> Result<JsonValue, SlackClientError> {
        self.read_file_num(file_id, max_bytes.map(|n| n as f64))
    }

    /// Returns a text file's content, shaped as slackClient.ts readFile's
    /// object literal: `name`, `title` and `mimetype` appear only when
    /// files.info returned them (JSON.stringify drops `undefined`), and the
    /// content is decoded as TextDecoder does, leading BOM removed.
    pub fn read_file_num(
        &self,
        file_id: &str,
        max_bytes: Option<f64>,
    ) -> Result<JsonValue, SlackClientError> {
        let max_bytes = max_bytes.unwrap_or(DEFAULT_READ_CAP as f64);
        let (file, token) = self.fetch_file_info(file_id)?;
        let id = template(file.get("id"));
        let is_canvas = is_canvas_file(&file);
        if !is_text_file(&file) && !is_canvas {
            return Err(SlackClientError::Message(format!(
                "File {id} ({}) is not a text file. Use slack_download_file to save it locally instead.",
                string_or(file.get("mimetype"), "unknown type")
            )));
        }
        // typeof file.size === "number" && file.size > maxBytes
        if let Some(size) = file.get("size").and_then(|v| v.as_f64()) {
            if size > max_bytes {
                return Err(SlackClientError::Message(format!(
                    "File {id} is {} bytes, larger than the {} byte cap. Raise max_bytes or use slack_download_file.",
                    js_number_to_string(size),
                    js_number_to_string(max_bytes)
                )));
            }
        }
        let bytes = self.fetch_file_bytes(&file, token)?;
        if is_canvas && (bytes.len() as f64) > max_bytes {
            return Err(SlackClientError::Message(format!(
                "File {id} is {} bytes, larger than the {} byte cap. Raise max_bytes or use slack_download_file.",
                js_number_to_string(bytes.len() as f64),
                js_number_to_string(max_bytes)
            )));
        }
        let mut out = JsonValue::object(vec![("ok", true.into())]);
        for key in ["id", "name", "title", "mimetype"] {
            copy_if_present(&mut out, &file, key);
        }
        if is_canvas {
            out.insert("format", "html".into());
        }
        out.insert("size", bytes.len().into());
        out.insert("content", decode_utf8_like_text_decoder(&bytes).into());
        Ok(out)
    }

    /// Slack's three-step external upload: reserve a URL, send the bytes,
    /// then complete the upload naming the channel. The channel is checked
    /// first because the first two steps name none.
    pub fn upload_file(&self, input: UploadFileInput) -> Result<JsonValue, SlackClientError> {
        self.guard_params(&JsonValue::object(vec![(
            "channel_id",
            input.channel_id.as_str().into(),
        )]))?;

        if input.content.is_none() == input.content_base64.is_none() {
            return Err(SlackClientError::Message(
                "Provide exactly one of content and content_base64.".to_string(),
            ));
        }

        let bytes = match (&input.content, &input.content_base64) {
            (Some(content), _) => content.as_bytes().to_vec(),
            // Buffer.from(b64, "base64"): lenient, never throws.
            (None, Some(b64)) => base64::decode_node(b64),
            (None, None) => Vec::new(),
        };

        let reserve = self.api(
            "files.getUploadURLExternal",
            JsonValue::object(vec![
                ("filename", input.filename.as_str().into()),
                ("length", bytes.len().into()),
            ]),
            self.write_token,
            "GET",
        )?;

        let upload_url = reserve.get("upload_url");
        let file_id = reserve.get("file_id");
        if !is_ok(&reserve) || !js_truthy(upload_url) || !js_truthy(file_id) {
            return Err(SlackClientError::Message(format!(
                "files.getUploadURLExternal failed: {}",
                string_or(reserve.get("error"), "no upload URL")
            )));
        }

        // No Authorization: the upload URL is itself the credential, and the
        // TypeScript client sent only the content type.
        let put = execute_transfer(&HttpRequest {
            url: template(upload_url),
            method: "POST".to_string(),
            headers: vec![(
                "Content-Type".to_string(),
                "application/octet-stream".to_string(),
            )],
            body: Some(bytes),
        })
        .map_err(SlackClientError::Message)?;
        if !(200..300).contains(&put.status) {
            return Err(SlackClientError::Message(format!(
                "Uploading file bytes failed: HTTP {}",
                put.status
            )));
        }

        let mut file_entry =
            JsonValue::object(vec![("id", file_id.cloned().unwrap_or(JsonValue::Null))]);
        if let Some(title) = input.title.as_deref().filter(|s| !s.is_empty()) {
            file_entry.insert("title", title.into());
        }
        let mut params = JsonValue::object(vec![
            ("files", JsonValue::Array(vec![file_entry])),
            ("channel_id", input.channel_id.as_str().into()),
        ]);
        if let Some(ic) = input.initial_comment.as_deref().filter(|s| !s.is_empty()) {
            params.insert("initial_comment", ic.into());
        }
        if let Some(ts) = input.thread_ts.as_deref().filter(|s| !s.is_empty()) {
            params.insert("thread_ts", ts.into());
        }
        self.api(
            "files.completeUploadExternal",
            params,
            self.write_token,
            "POST",
        )
    }

    pub fn download_file(
        &self,
        file_id: &str,
        output_path: &str,
    ) -> Result<JsonValue, SlackClientError> {
        let (file, token) = self.fetch_file_info(file_id)?;
        let bytes = self.fetch_file_bytes(&file, token)?;
        let mut handle = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(output_path)
            .map_err(|e| {
                if e.kind() == std::io::ErrorKind::AlreadyExists {
                    SlackClientError::Message(format!(
                        "{output_path} already exists; refusing to overwrite it."
                    ))
                } else {
                    SlackClientError::Message(e.to_string())
                }
            })?;
        handle
            .write_all(&bytes)
            .map_err(|e| SlackClientError::Message(e.to_string()))?;
        let mut out = JsonValue::object(vec![
            ("ok", true.into()),
            ("path", output_path.into()),
            ("bytes", bytes.len().into()),
        ]);
        copy_if_present(&mut out, &file, "name");
        Ok(out)
    }

    // ── User groups ────────────────────────────────────────────────────

    pub fn list_user_groups(
        &self,
        include_disabled: Option<bool>,
    ) -> Result<JsonValue, SlackClientError> {
        let inc = if include_disabled.unwrap_or(false) {
            "true"
        } else {
            "false"
        };
        self.api(
            "usergroups.list",
            JsonValue::object(vec![
                ("include_disabled", inc.into()),
                ("team_id", self.team_id.as_str().into()),
            ]),
            WriteTokenPreference::Bot,
            "GET",
        )
    }

    pub fn list_user_group_members(
        &self,
        usergroup_id: &str,
    ) -> Result<JsonValue, SlackClientError> {
        self.api(
            "usergroups.users.list",
            JsonValue::object(vec![
                ("usergroup", usergroup_id.into()),
                ("team_id", self.team_id.as_str().into()),
            ]),
            WriteTokenPreference::Bot,
            "GET",
        )
    }

    pub fn create_user_group(
        &self,
        input: CreateUserGroupInput,
    ) -> Result<JsonValue, SlackClientError> {
        if let Some(cids) = &input.channel_ids {
            for cid in cids {
                self.guard_params(&JsonValue::object(vec![("channel", cid.as_str().into())]))?;
            }
        }
        let mut params = JsonValue::object(vec![
            ("name", input.name.as_str().into()),
            ("handle", input.handle.as_str().into()),
        ]);
        if let Some(desc) = input.description.as_deref().filter(|s| !s.is_empty()) {
            params.insert("description", desc.into());
        }
        if let Some(cids) = input.channel_ids.as_ref().filter(|c| !c.is_empty()) {
            params.insert("channels", cids.join(",").into());
        }
        params.insert("team_id", self.team_id.as_str().into());
        self.api(
            "usergroups.create",
            params,
            WriteTokenPreference::User,
            "POST",
        )
    }

    pub fn update_user_group(
        &self,
        usergroup_id: &str,
        fields: UpdateUserGroupFields,
    ) -> Result<JsonValue, SlackClientError> {
        let mut params = JsonValue::object(vec![("usergroup", usergroup_id.into())]);
        if let Some(name) = fields.name.as_deref().filter(|s| !s.is_empty()) {
            params.insert("name", name.into());
        }
        if let Some(handle) = fields.handle.as_deref().filter(|s| !s.is_empty()) {
            params.insert("handle", handle.into());
        }
        if let Some(desc) = fields.description.as_deref() {
            params.insert("description", desc.into());
        }
        params.insert("team_id", self.team_id.as_str().into());
        self.api(
            "usergroups.update",
            params,
            WriteTokenPreference::User,
            "POST",
        )
    }

    pub fn set_user_group_members(
        &self,
        usergroup_id: &str,
        user_ids: &[String],
    ) -> Result<JsonValue, SlackClientError> {
        self.api(
            "usergroups.users.update",
            JsonValue::object(vec![
                ("usergroup", usergroup_id.into()),
                ("users", user_ids.join(",").into()),
                ("team_id", self.team_id.as_str().into()),
            ]),
            WriteTokenPreference::User,
            "POST",
        )
    }

    pub fn set_user_group_enabled(
        &self,
        usergroup_id: &str,
        enabled: bool,
    ) -> Result<JsonValue, SlackClientError> {
        let endpoint = if enabled {
            "usergroups.enable"
        } else {
            "usergroups.disable"
        };
        self.api(
            endpoint,
            JsonValue::object(vec![
                ("usergroup", usergroup_id.into()),
                ("team_id", self.team_id.as_str().into()),
            ]),
            WriteTokenPreference::User,
            "POST",
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{resolve_config, EnvSource};
    use crate::tools::{all_tools, tools_for, HTTP_WITHHELD_ALWAYS, HTTP_WITHHELD_DESTRUCTIVE};
    use crate::url::ParsedUrl;
    use std::collections::BTreeMap;

    fn stdio_env() -> BTreeMap<String, String> {
        let mut m = BTreeMap::new();
        m.insert("SLACK_BOT_TOKEN".to_string(), "xoxb-test".to_string());
        m.insert("SLACK_USER_TOKEN".to_string(), "xoxp-test".to_string());
        m.insert("SLACK_TEAM_ID".to_string(), "T123".to_string());
        m
    }

    fn http_env() -> BTreeMap<String, String> {
        let mut m = BTreeMap::new();
        m.insert("MCP_TRANSPORT".to_string(), "http".to_string());
        m.insert("SLACK_BOT_TOKEN".to_string(), "xoxb-test".to_string());
        m.insert("SLACK_TEAM_ID".to_string(), "T123".to_string());
        m.insert(
            "SLACK_CHANNEL_IDS".to_string(),
            "C_ALLOWED, C_SECOND,".to_string(),
        );
        m.insert(
            "OIDC_ISSUER".to_string(),
            "https://auth.example.test".to_string(),
        );
        m.insert("OIDC_PROJECT_ID".to_string(), "999".to_string());
        m.insert(
            "OIDC_ALLOWED_SUBJECTS".to_string(),
            "379361013981513322".to_string(),
        );
        m.insert(
            "OIDC_ALLOWED_CLIENT_ID".to_string(),
            "111222333".to_string(),
        );
        m
    }

    fn client_for<E: EnvSource + ?Sized>(env: &E) -> SlackClient {
        let cfg = resolve_config(env).unwrap();
        SlackClient::new(cfg.slack, cfg.channel_guard, cfg.write_token)
    }

    #[test]
    fn stdio_regression_and_allowlist_enforcement() {
        let guard = set_mock_fetch(|_| {
            Ok(HttpResponse::json(
                200,
                JsonValue::object(vec![
                    ("ok", true.into()),
                    (
                        "channel",
                        JsonValue::object(vec![("is_private", false.into())]),
                    ),
                ]),
            ))
        });

        client_for(&stdio_env())
            .get_channel_history("C_ANYTHING", Some(5))
            .unwrap();
        {
            let calls = guard.calls.lock().unwrap();
            assert_eq!(calls.len(), 1);
            assert_eq!(calls[0].auth(), Some("Bearer xoxb-test"));
        }

        guard.calls.lock().unwrap().clear();
        client_for(&stdio_env())
            .post_message("C_ANYTHING", "hello")
            .unwrap();
        {
            let calls = guard.calls.lock().unwrap();
            assert_eq!(calls[0].auth(), Some("Bearer xoxp-test"));
            assert!(calls[0].url.contains("chat.postMessage"));
        }

        // Allow-list on stdio when configured
        let mut stdio_restricted = stdio_env();
        stdio_restricted.insert("SLACK_CHANNEL_IDS".to_string(), "C_ONLY".to_string());
        let c_rest = client_for(&stdio_restricted);
        assert!(c_rest.get_channel_history("C_ONLY", None).is_ok());
        assert!(matches!(
            c_rest.get_channel_history("C_OTHER", None),
            Err(SlackClientError::ChannelAllowlist(
                ChannelAllowlistError::ChannelNotAllowed { .. }
            ))
        ));

        // Enforced across all channel-scoped methods on HTTP
        guard.calls.lock().unwrap().clear();
        let hc = client_for(&http_env());
        assert!(hc.get_channel_history("G_PRIVATE", None).is_err());
        assert!(hc.get_channel_info("G_PRIVATE").is_err());
        assert!(hc.get_thread_replies("G_PRIVATE", "1.0").is_err());
        assert!(hc.list_pins("G_PRIVATE").is_err());
        assert!(hc.list_bookmarks("G_PRIVATE").is_err());
        assert!(hc.post_message("G_PRIVATE", "x").is_err());
        assert!(hc.reply_to_thread("G_PRIVATE", "1.0", "x").is_err());
        assert!(hc.update_message("G_PRIVATE", "1.0", "x").is_err());
        assert!(hc
            .get_channel_history_param(JsonValue::Array(vec!["G_PRIVATE".into()]), None)
            .is_err());
        assert!(guard.calls.lock().unwrap().is_empty());

        // Allowed channel passes and writes with bot token on bot-only HTTP
        hc.post_message("C_ALLOWED", "hello").unwrap();
        assert_eq!(
            guard.calls.lock().unwrap()[0].auth(),
            Some("Bearer xoxb-test")
        );

        // User-token tool refused when no user token exists
        assert!(matches!(
            hc.search_messages("anything", None, None),
            Err(SlackClientError::UserTokenUnavailable { .. })
        ));

        // listChannels skips blank entries from trailing comma
        guard.calls.lock().unwrap().clear();
        let res = hc.list_channels(None, None).unwrap();
        assert_eq!(res.get("ok").and_then(|v| v.as_bool()), Some(true));
        assert_eq!(guard.calls.lock().unwrap().len(), 2);

        // Workspace-scoped tool visibility
        let http_tools: Vec<&str> = tools_for(&resolve_config(&http_env()).unwrap())
            .iter()
            .map(|t| t.name)
            .collect();
        assert!(!http_tools.contains(&"slack_get_users"));
        assert!(http_tools.contains(&"slack_get_user_profile"));

        let mut http_imp = http_env();
        http_imp.insert("SLACK_USER_TOKEN".to_string(), "xoxp-test".to_string());
        let imp_tools: Vec<&str> = tools_for(&resolve_config(&http_imp).unwrap())
            .iter()
            .map(|t| t.name)
            .collect();
        assert_eq!(
            imp_tools.len(),
            all_tools().len() - HTTP_WITHHELD_ALWAYS.len() - HTTP_WITHHELD_DESTRUCTIVE.len()
        );
        assert!(imp_tools.contains(&"slack_search_messages"));
        assert!(imp_tools.contains(&"slack_create_canvas"));
        for withheld in HTTP_WITHHELD_DESTRUCTIVE {
            assert!(!imp_tools.contains(withheld), "{withheld} must be withheld");
        }

        http_imp.insert(
            "SLACK_HTTP_ALLOW_DESTRUCTIVE".to_string(),
            "true".to_string(),
        );
        let imp_destructive_tools: Vec<&str> = tools_for(&resolve_config(&http_imp).unwrap())
            .iter()
            .map(|t| t.name)
            .collect();
        assert_eq!(
            imp_destructive_tools.len(),
            all_tools().len() - HTTP_WITHHELD_ALWAYS.len()
        );
        for allowed in HTTP_WITHHELD_DESTRUCTIVE {
            assert!(
                imp_destructive_tools.contains(allowed),
                "{allowed} must be enabled"
            );
        }
    }

    #[test]
    fn verify_allowlist_visibility_checks_and_remedies() {
        let mut priv_env = http_env();
        priv_env.insert("SLACK_CHANNEL_IDS".to_string(), "C_PUBLIC".to_string());
        priv_env.insert(
            "SLACK_PRIVATE_CHANNEL_IDS".to_string(),
            "G_PRIVATE".to_string(),
        );

        {
            let _guard = set_mock_fetch(|req| {
                let is_priv = req.url.contains("G_PRIVATE");
                Ok(HttpResponse::json(
                    200,
                    JsonValue::object(vec![
                        ("ok", true.into()),
                        (
                            "channel",
                            JsonValue::object(vec![("is_private", is_priv.into())]),
                        ),
                    ]),
                ))
            });
            assert!(client_for(&priv_env).verify_allowlist_visibility().is_ok());
        }

        {
            let _guard = set_mock_fetch(|_| {
                Ok(HttpResponse::json(
                    200,
                    JsonValue::object(vec![
                        ("ok", true.into()),
                        (
                            "channel",
                            JsonValue::object(vec![("is_private", true.into())]),
                        ),
                    ]),
                ))
            });
            assert!(matches!(
                client_for(&priv_env).verify_allowlist_visibility(),
                Err(SlackClientError::ChannelAllowlist(
                    ChannelAllowlistError::ChannelVisibilityMismatch { .. }
                ))
            ));
        }

        {
            let _guard = set_mock_fetch(|_| {
                Ok(HttpResponse::json(
                    200,
                    JsonValue::object(vec![
                        ("ok", false.into()),
                        ("error", "channel_not_found".into()),
                    ]),
                ))
            });
            let err = client_for(&priv_env)
                .verify_allowlist_visibility()
                .unwrap_err();
            assert!(err.message().contains("channel_not_found"));
            assert!(err
                .message()
                .contains("Invite the bot to the channel first"));
        }

        {
            let _guard = set_mock_fetch(|_| Err("fetch failed".to_string()));
            let err = client_for(&priv_env)
                .verify_allowlist_visibility()
                .unwrap_err();
            assert!(err.message().contains("did not return a usable answer"));
            assert!(err.message().contains("fetch failed"));
        }
    }

    #[test]
    fn files_info_read_upload_and_download() {
        let private_url = "https://files.slack.com/files-pri/T123-F0TEXT0001/notes.txt";
        let make_file_info = |channels: Vec<&str>, mime: &str, size: i64| -> JsonValue {
            JsonValue::object(vec![
                ("id", "F0TEXT0001".into()),
                ("name", "notes.txt".into()),
                ("title", "notes".into()),
                ("mimetype", mime.into()),
                ("filetype", "text".into()),
                ("size", size.into()),
                ("url_private", private_url.into()),
                (
                    "channels",
                    JsonValue::Array(channels.into_iter().map(|s| s.into()).collect()),
                ),
                ("groups", JsonValue::Array(vec![])),
                ("ims", JsonValue::Array(vec![])),
            ])
        };

        let mut env = http_env();
        env.insert("SLACK_CHANNEL_IDS".to_string(), "C0ALLOWED1".to_string());

        // Allowed file info and read
        {
            let info = make_file_info(vec!["C0ALLOWED1"], "text/plain", 11);
            let guard = set_mock_fetch(move |req| {
                if req.url.contains("/api/files.info") {
                    Ok(HttpResponse::json(
                        200,
                        JsonValue::object(vec![("ok", true.into()), ("file", info.clone())]),
                    ))
                } else if req.url.contains("/api/files.getUploadURLExternal") {
                    Ok(HttpResponse::json(
                        200,
                        JsonValue::object(vec![
                            ("ok", true.into()),
                            ("upload_url", "https://files.slack.com/upload/v1/abc".into()),
                            ("file_id", "F0NEW00001".into()),
                        ]),
                    ))
                } else if req.url.contains("/api/files.completeUploadExternal") {
                    Ok(HttpResponse::json(
                        200,
                        JsonValue::object(vec![
                            ("ok", true.into()),
                            (
                                "files",
                                JsonValue::Array(vec![JsonValue::object(vec![(
                                    "id",
                                    "F0NEW00001".into(),
                                )])]),
                            ),
                        ]),
                    ))
                } else if req.url.starts_with("https://files.slack.com/upload/") {
                    Ok(HttpResponse {
                        status: 200,
                        headers: vec![],
                        body: b"OK".to_vec(),
                    })
                } else if req.url == private_url {
                    Ok(HttpResponse {
                        status: 200,
                        headers: vec![("Content-Type".to_string(), "text/plain".to_string())],
                        body: b"hello world".to_vec(),
                    })
                } else {
                    Ok(HttpResponse::json(
                        200,
                        JsonValue::object(vec![("ok", false.into())]),
                    ))
                }
            });

            let info_res = client_for(&env).get_file_info("F0TEXT0001").unwrap();
            assert!(!info_res.to_json_string().contains("files-pri"));

            guard.calls.lock().unwrap().clear();
            let read_res = client_for(&env).read_file("F0TEXT0001", None).unwrap();
            assert_eq!(
                read_res.get("content").and_then(|v| v.as_str()),
                Some("hello world")
            );
            assert_eq!(guard.calls.lock().unwrap().len(), 2);

            // Upload 3-step
            guard.calls.lock().unwrap().clear();
            let up_res = client_for(&stdio_env())
                .upload_file(UploadFileInput {
                    channel_id: "C0ALLOWED1".to_string(),
                    filename: "hello.txt".to_string(),
                    content: Some("hello".to_string()),
                    content_base64: None,
                    title: Some("Hello".to_string()),
                    initial_comment: Some("here you go".to_string()),
                    thread_ts: Some("1.000001".to_string()),
                })
                .unwrap();
            assert_eq!(up_res.get("ok").and_then(|v| v.as_bool()), Some(true));
            assert_eq!(guard.calls.lock().unwrap().len(), 3);

            // Download file to temp path and refuse overwrite
            let tmp_dir = std::env::temp_dir().join(format!(
                "mcp-slack-rs-dl-{}",
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_nanos()
            ));
            std::fs::create_dir_all(&tmp_dir).unwrap();
            let target = tmp_dir.join("out.txt");
            let target_str = target.to_str().unwrap();
            let dl = client_for(&stdio_env())
                .download_file("F0TEXT0001", target_str)
                .unwrap();
            assert_eq!(dl.get("bytes").and_then(|v| v.as_i64()), Some(11));
            assert_eq!(std::fs::read_to_string(&target).unwrap(), "hello world");

            // Refuse overwrite
            let overwrite_err = client_for(&stdio_env())
                .download_file("F0TEXT0001", target_str)
                .unwrap_err();
            assert!(overwrite_err.message().contains("already exists"));
            let _ = std::fs::remove_dir_all(&tmp_dir);
        }

        // Disallowed file share
        {
            let bad_info = make_file_info(vec!["C0OTHER00"], "text/plain", 11);
            let guard = set_mock_fetch(move |_| {
                Ok(HttpResponse::json(
                    200,
                    JsonValue::object(vec![("ok", true.into()), ("file", bad_info.clone())]),
                ))
            });
            assert!(matches!(
                client_for(&env).read_file("F0TEXT0001", None),
                Err(SlackClientError::ChannelAllowlist(
                    ChannelAllowlistError::FileNotAllowed { .. }
                ))
            ));
            assert_eq!(guard.calls.lock().unwrap().len(), 1);
        }
    }

    #[test]
    fn membership_emoji_and_unread_listing() {
        let mut env = http_env();
        env.insert("SLACK_CHANNEL_IDS".to_string(), "C0ALLOWED1".to_string());

        // Emoji filtering
        {
            let _guard = set_mock_fetch(|_| {
                Ok(HttpResponse::json(
                    200,
                    JsonValue::object(vec![
                        ("ok", true.into()),
                        (
                            "emoji",
                            JsonValue::object(vec![
                                ("partyparrot", "https://emoji/a.gif".into()),
                                ("parrot", "alias:partyparrot".into()),
                                ("shipit", "https://emoji/b.png".into()),
                            ]),
                        ),
                    ]),
                ))
            });
            let c = client_for(&stdio_env());
            let all = c.list_emoji(None, None).unwrap();
            assert_eq!(all.get("emoji").unwrap().as_object().unwrap().len(), 3);
            let parrot = c.list_emoji(Some("PARROT"), None).unwrap();
            assert_eq!(parrot.get("emoji").unwrap().as_object().unwrap().len(), 2);
            let no_alias = c.list_emoji(None, Some(false)).unwrap();
            assert_eq!(no_alias.get("emoji").unwrap().as_object().unwrap().len(), 2);
        }

        // Unread listing with rate-limit retry and join-subtype filtering
        {
            let limited_once = Arc::new(Mutex::new(false));
            let lim_clone = Arc::clone(&limited_once);
            let _guard = set_mock_fetch(move |req| {
                let parsed = ParsedUrl::parse(&req.url).unwrap();
                let method = parsed.pathname.trim_start_matches("/api/");
                if method == "users.conversations" {
                    let types = parsed.query_get("types").unwrap_or("");
                    if types == "im" {
                        return Ok(HttpResponse::json(
                            200,
                            JsonValue::object(vec![
                                ("ok", false.into()),
                                ("error", "missing_scope".into()),
                            ]),
                        ));
                    }
                    if types == "mpim" {
                        return Ok(HttpResponse::json(
                            200,
                            JsonValue::object(vec![
                                ("ok", true.into()),
                                (
                                    "channels",
                                    JsonValue::Array(vec![JsonValue::object(vec![(
                                        "id",
                                        "D_NEVER_OPENED".into(),
                                    )])]),
                                ),
                            ]),
                        ));
                    }
                    return Ok(HttpResponse::json(
                        200,
                        JsonValue::object(vec![
                            ("ok", true.into()),
                            (
                                "channels",
                                JsonValue::Array(vec![
                                    JsonValue::object(vec![("id", "C_QUIET".into())]),
                                    JsonValue::object(vec![("id", "C_BUSY".into())]),
                                    JsonValue::object(vec![("id", "C_LIMITED".into())]),
                                    JsonValue::object(vec![("id", "C_JOINS".into())]),
                                ]),
                            ),
                        ]),
                    ));
                }
                let id = parsed.query_get("channel").unwrap_or("");
                if method == "conversations.info" {
                    let last_read = if id == "D_NEVER_OPENED" {
                        "0000000000.000000"
                    } else if id == "C_QUIET" {
                        "200.0"
                    } else {
                        "100.0"
                    };
                    return Ok(HttpResponse::json(
                        200,
                        JsonValue::object(vec![
                            ("ok", true.into()),
                            (
                                "channel",
                                JsonValue::object(vec![
                                    ("name", id.to_ascii_lowercase().into()),
                                    ("last_read", last_read.into()),
                                ]),
                            ),
                        ]),
                    ));
                }
                // conversations.history
                if id == "D_NEVER_OPENED" {
                    if parsed.query_get("oldest") != Some("0") {
                        return Ok(HttpResponse::json(
                            200,
                            JsonValue::object(vec![
                                ("ok", false.into()),
                                ("error", "invalid_ts_oldest".into()),
                            ]),
                        ));
                    }
                    return Ok(HttpResponse::json(
                        200,
                        JsonValue::object(vec![
                            ("ok", true.into()),
                            (
                                "messages",
                                JsonValue::Array(vec![JsonValue::object(vec![(
                                    "ts",
                                    "500.0".into(),
                                )])]),
                            ),
                        ]),
                    ));
                }
                if id == "C_BUSY" {
                    let mut lim = lim_clone.lock().unwrap();
                    if !*lim {
                        *lim = true;
                        return Ok(HttpResponse::json(
                            429,
                            JsonValue::object(vec![
                                ("ok", false.into()),
                                ("error", "ratelimited".into()),
                            ]),
                        )
                        .with_header("Retry-After", "0"));
                    }
                    return Ok(HttpResponse::json(
                        200,
                        JsonValue::object(vec![
                            ("ok", true.into()),
                            ("has_more", true.into()),
                            (
                                "messages",
                                JsonValue::Array(vec![
                                    JsonValue::object(vec![("ts", "300.0".into())]),
                                    JsonValue::object(vec![("ts", "250.0".into())]),
                                ]),
                            ),
                        ]),
                    ));
                }
                if id == "C_LIMITED" {
                    return Ok(HttpResponse::json(
                        429,
                        JsonValue::object(vec![
                            ("ok", false.into()),
                            ("error", "ratelimited".into()),
                        ]),
                    )
                    .with_header("Retry-After", "0"));
                }
                if id == "C_JOINS" {
                    return Ok(HttpResponse::json(
                        200,
                        JsonValue::object(vec![
                            ("ok", true.into()),
                            (
                                "messages",
                                JsonValue::Array(vec![JsonValue::object(vec![
                                    ("ts", "400.0".into()),
                                    ("subtype", "channel_join".into()),
                                ])]),
                            ),
                        ]),
                    ));
                }
                Ok(HttpResponse::json(
                    200,
                    JsonValue::object(vec![
                        ("ok", true.into()),
                        ("messages", JsonValue::Array(vec![])),
                    ]),
                ))
            });

            let unread = client_for(&stdio_env()).list_unread(None).unwrap();
            let convs = unread.get("conversations").unwrap().as_array().unwrap();
            assert_eq!(convs.len(), 2);
            assert_eq!(
                convs[0].get("id").and_then(|v| v.as_str()),
                Some("D_NEVER_OPENED")
            );
            assert_eq!(convs[1].get("id").and_then(|v| v.as_str()), Some("C_BUSY"));
            assert_eq!(unread.get("checked").and_then(|v| v.as_i64()), Some(5));
            assert_eq!(unread.get("skipped").unwrap().as_array().unwrap().len(), 1);
            assert_eq!(unread.get("errors").unwrap().as_array().unwrap().len(), 1);
        }
    }

    #[test]
    fn user_groups_reads_writes_and_allowlist() {
        let guard = set_mock_fetch(|_| {
            Ok(HttpResponse::json(
                200,
                JsonValue::object(vec![("ok", true.into())]),
            ))
        });

        let c = client_for(&stdio_env());
        c.list_user_groups(None).unwrap();
        assert!(guard.calls.lock().unwrap()[0]
            .url
            .contains("include_disabled=false"));

        c.list_user_groups(Some(true)).unwrap();
        assert!(guard.calls.lock().unwrap()[1]
            .url
            .contains("include_disabled=true"));

        guard.calls.lock().unwrap().clear();
        c.create_user_group(CreateUserGroupInput {
            name: "Platform".to_string(),
            handle: "platform".to_string(),
            description: Some("Platform engineers".to_string()),
            channel_ids: Some(vec!["C0ALLOWED1".to_string(), "C0SECOND01".to_string()]),
        })
        .unwrap();
        assert_eq!(
            guard.calls.lock().unwrap()[0].auth(),
            Some("Bearer xoxp-test")
        );

        let mut http_imp = http_env();
        http_imp.insert("SLACK_CHANNEL_IDS".to_string(), "C0ALLOWED1".to_string());
        http_imp.insert("SLACK_USER_TOKEN".to_string(), "xoxp-test".to_string());
        assert!(matches!(
            client_for(&http_imp).create_user_group(CreateUserGroupInput {
                name: "x".to_string(),
                handle: "x".to_string(),
                description: None,
                channel_ids: Some(vec!["C0ALLOWED1".to_string(), "G0PRIVATE1".to_string()]),
            }),
            Err(SlackClientError::ChannelAllowlist(
                ChannelAllowlistError::ChannelNotAllowed { .. }
            ))
        ));
    }

    // ── Real transport (ureq) against a loopback server ─────────────────

    /// What the loopback server saw of one request.
    #[derive(Debug, Clone)]
    struct Seen {
        request_line: String,
        headers: Vec<(String, String)>,
        body: Vec<u8>,
    }

    impl Seen {
        fn header(&self, name: &str) -> Option<&str> {
            self.headers
                .iter()
                .find(|(k, _)| k.eq_ignore_ascii_case(name))
                .map(|(_, v)| v.as_str())
        }
    }

    /// A one-shot-per-connection HTTP/1.1 server on 127.0.0.1. `respond`
    /// gets the request and returns raw response bytes; every response
    /// closes the connection so pooling cannot blur the count.
    fn loopback_server<F>(respond: F) -> (u16, Arc<Mutex<Vec<Seen>>>)
    where
        F: Fn(&Seen) -> Vec<u8> + Send + 'static,
    {
        use std::io::{BufRead, BufReader};
        use std::net::TcpListener;
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let seen = Arc::new(Mutex::new(Vec::new()));
        let seen_clone = Arc::clone(&seen);
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut stream) = stream else { return };
                let mut reader = BufReader::new(stream.try_clone().unwrap());
                let mut request_line = String::new();
                if reader.read_line(&mut request_line).is_err() {
                    continue;
                }
                let mut headers = Vec::new();
                loop {
                    let mut line = String::new();
                    reader.read_line(&mut line).unwrap();
                    let line = line.trim_end().to_string();
                    if line.is_empty() {
                        break;
                    }
                    if let Some((k, v)) = line.split_once(':') {
                        headers.push((k.trim().to_string(), v.trim().to_string()));
                    }
                }
                let len: usize = headers
                    .iter()
                    .find(|(k, _)| k.eq_ignore_ascii_case("content-length"))
                    .and_then(|(_, v)| v.parse().ok())
                    .unwrap_or(0);
                let mut body = vec![0u8; len];
                reader.read_exact(&mut body).unwrap();
                let req = Seen {
                    request_line: request_line.trim_end().to_string(),
                    headers,
                    body,
                };
                let response = respond(&req);
                seen_clone.lock().unwrap().push(req);
                let _ = stream.write_all(&response);
                let _ = stream.flush();
            }
        });
        (port, seen)
    }

    fn raw_response(status: &str, headers: &[(&str, &str)], body: &[u8]) -> Vec<u8> {
        let mut out = format!("HTTP/1.1 {status}\r\nConnection: close\r\n");
        for (k, v) in headers {
            out.push_str(&format!("{k}: {v}\r\n"));
        }
        out.push_str(&format!("Content-Length: {}\r\n\r\n", body.len()));
        let mut out = out.into_bytes();
        out.extend_from_slice(body);
        out
    }

    #[test]
    fn ureq_transport_returns_errors_statuses_and_binary_bodies_untouched() {
        let binary: Vec<u8> = vec![0x00, 0xFF, 0xFE, b'\r', b'\n', 0x80, b'@'];
        let reply = binary.clone();
        let (port, seen) = loopback_server(move |_| {
            raw_response(
                "503 Service Unavailable",
                &[("Retry-After", "7"), ("X-Multi", "a"), ("X-Multi", "b")],
                &reply,
            )
        });
        // A body starting with '@' made curl upload a local file; it must
        // go out as these exact bytes, invalid UTF-8 included.
        let sent = b"@/etc/passwd\xff\x00".to_vec();
        let res = ureq_fetch(
            &HttpRequest {
                url: format!("http://127.0.0.1:{port}/upload"),
                method: "POST".to_string(),
                headers: vec![(
                    "Content-Type".to_string(),
                    "application/octet-stream".to_string(),
                )],
                body: Some(sent.clone()),
            },
            Some(API_TIMEOUT),
        )
        .expect("a 503 is a response, not an error");
        assert_eq!(res.status, 503);
        assert_eq!(res.body, binary);
        assert_eq!(res.header("retry-after"), Some("7"));
        let multi: Vec<&str> = res
            .headers
            .iter()
            .filter(|(k, _)| k.eq_ignore_ascii_case("x-multi"))
            .map(|(_, v)| v.as_str())
            .collect();
        assert_eq!(multi, vec!["a", "b"]);
        let seen = seen.lock().unwrap();
        assert_eq!(seen[0].request_line, "POST /upload HTTP/1.1");
        assert_eq!(seen[0].body, sent);
        assert_eq!(seen[0].header("authorization"), None);
    }

    #[test]
    fn ureq_transport_failure_is_fetch_failed_without_the_url() {
        // Bind and drop, so nothing listens on the port.
        let port = std::net::TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .port();
        let err = ureq_fetch(
            &HttpRequest {
                url: format!("http://127.0.0.1:{port}/files-pri/secret-path"),
                method: "GET".to_string(),
                headers: vec![],
                body: None,
            },
            Some(API_TIMEOUT),
        )
        .unwrap_err();
        assert!(err.starts_with("fetch failed"), "{err}");
        assert!(!err.contains("secret-path"), "{err}");
    }

    #[test]
    fn redirects_are_followed_but_authorization_never_changes_host() {
        // B is the redirect target; A sends every request to B, once by the
        // same host name and once by a different one.
        let (port_b, seen_b) = loopback_server(|_| raw_response("200 OK", &[], b"file bytes"));
        let (port_a, _seen_a) = loopback_server(move |req| {
            let host = if req.request_line.contains("/cross") {
                "localhost"
            } else {
                "127.0.0.1"
            };
            raw_response(
                "302 Found",
                &[("Location", &format!("http://{host}:{port_b}/target"))],
                b"",
            )
        });
        for path in ["/same", "/cross"] {
            let res = ureq_fetch(
                &HttpRequest {
                    url: format!("http://127.0.0.1:{port_a}{path}"),
                    method: "GET".to_string(),
                    headers: vec![(
                        "Authorization".to_string(),
                        "Bearer xoxb-secret".to_string(),
                    )],
                    body: None,
                },
                None,
            )
            .unwrap();
            assert_eq!(res.status, 200);
            assert_eq!(res.body, b"file bytes");
        }
        let seen_b = seen_b.lock().unwrap();
        assert_eq!(seen_b.len(), 2);
        // Same host (127.0.0.1, a different port): kept, as fetch keeps it.
        assert_eq!(
            seen_b[0].header("authorization"),
            Some("Bearer xoxb-secret")
        );
        // A different host name: stripped.
        assert_eq!(seen_b[1].header("authorization"), None);
    }

    // ── api() details ───────────────────────────────────────────────────

    #[test]
    fn retry_after_is_read_as_javascript_number_did() {
        let _sleep = set_mock_sleep();
        let cases: Vec<(Vec<&str>, f64)> = vec![
            (vec![], 1.0),
            (vec![""], 0.0),
            (vec!["1.5"], 1.5),
            (vec![" 2 "], 2.0),
            (vec!["abc"], 1.0),
            (vec!["Infinity"], 1.0),
            (vec!["0x10"], 16.0),
            (vec!["3", "4"], 1.0),
        ];
        for (values, want) in cases {
            let values_clone: Vec<String> = values.iter().map(|s| s.to_string()).collect();
            let _guard = set_mock_fetch(move |_| {
                let mut res = HttpResponse::json(
                    429,
                    JsonValue::object(vec![("ok", false.into()), ("error", "ratelimited".into())]),
                );
                for v in &values_clone {
                    res = res.with_header("Retry-After", v.as_str());
                }
                Ok(res)
            });
            let data = client_for(&stdio_env())
                .get_channel_history("C1", None)
                .unwrap();
            assert_eq!(
                data.get("retry_after").and_then(|v| v.as_f64()),
                Some(want),
                "Retry-After {values:?}"
            );
        }
        // And the wait list_unread derives from it.
        let wait = |v: JsonValue| unread_backoff(&JsonValue::object(vec![("retry_after", v)]));
        assert_eq!(wait(JsonValue::Number(1.5)), Duration::from_millis(1500));
        assert_eq!(wait(JsonValue::Number(0.0)), Duration::ZERO);
        assert_eq!(wait(JsonValue::Number(-3.0)), Duration::ZERO);
        assert_eq!(wait(JsonValue::Number(99.0)), Duration::from_secs(30));
        assert_eq!(wait(JsonValue::Null), Duration::from_secs(1));
        assert_eq!(
            unread_backoff(&JsonValue::empty_object()),
            Duration::from_secs(1)
        );
    }

    #[test]
    fn api_reads_a_bom_prefixed_body_as_res_json_does() {
        let _guard = set_mock_fetch(|_| {
            Ok(HttpResponse {
                status: 200,
                headers: vec![],
                body: b"\xEF\xBB\xBF{\"ok\":true,\"t\":\"\\ud83d\\ude80\"}".to_vec(),
            })
        });
        let data = client_for(&stdio_env())
            .get_channel_history("C1", None)
            .unwrap();
        assert_eq!(data.get("t").and_then(|v| v.as_str()), Some("🚀"));
    }

    // ── list_unread ─────────────────────────────────────────────────────

    #[test]
    fn list_unread_inspects_four_conversations_at_once() {
        use std::sync::Condvar;
        let ids: Vec<String> = (0..9).map(|i| format!("C{i}")).collect();
        let state = Arc::new((Mutex::new((0usize, 0usize)), Condvar::new()));
        let state_clone = Arc::clone(&state);
        let ids_clone = ids.clone();
        let _guard = set_mock_fetch(move |req| {
            let parsed = ParsedUrl::parse(&req.url).unwrap();
            let method = parsed.pathname.trim_start_matches("/api/").to_string();
            if method == "users.conversations" {
                let channels =
                    if parsed.query_get("types") == Some("public_channel,private_channel") {
                        ids_clone
                            .iter()
                            .map(|id| JsonValue::object(vec![("id", id.as_str().into())]))
                            .collect()
                    } else {
                        vec![]
                    };
                return Ok(HttpResponse::json(
                    200,
                    JsonValue::object(vec![
                        ("ok", true.into()),
                        ("channels", JsonValue::Array(channels)),
                    ]),
                ));
            }
            let id = parsed.query_get("channel").unwrap_or("").to_string();
            if method == "conversations.info" {
                // Hold each info call until four are in flight together (or
                // a timeout passes), recording the most seen at once.
                let (lock, cvar) = &*state_clone;
                let mut g = lock.lock().unwrap();
                g.0 += 1;
                g.1 = g.1.max(g.0);
                cvar.notify_all();
                let deadline = std::time::Instant::now() + Duration::from_secs(2);
                while g.1 < 4 && std::time::Instant::now() < deadline {
                    g = cvar.wait_timeout(g, Duration::from_millis(50)).unwrap().0;
                }
                g.0 -= 1;
                drop(g);
                return Ok(HttpResponse::json(
                    200,
                    JsonValue::object(vec![
                        ("ok", true.into()),
                        (
                            "channel",
                            JsonValue::object(vec![("last_read", "100.0".into())]),
                        ),
                    ]),
                ));
            }
            // History: C0..C8 get descending-in-id timestamps, with C3 and
            // C5 tied, to pin down the order ties come out in.
            let n: usize = id[1..].parse().unwrap();
            let ts = if n == 5 {
                "203.0".to_string()
            } else {
                format!("{}.0", 200 + n)
            };
            Ok(HttpResponse::json(
                200,
                JsonValue::object(vec![
                    ("ok", true.into()),
                    (
                        "messages",
                        JsonValue::Array(vec![JsonValue::object(vec![("ts", ts.as_str().into())])]),
                    ),
                ]),
            ))
        });

        let res = client_for(&stdio_env()).list_unread(None).unwrap();
        assert_eq!(state.0.lock().unwrap().1, UNREAD_CONCURRENCY);
        let order: Vec<&str> = res
            .get("conversations")
            .unwrap()
            .as_array()
            .unwrap()
            .iter()
            .map(|c| c.get("id").unwrap().as_str().unwrap())
            .collect();
        // Newest first; the C3/C5 tie keeps candidate order.
        assert_eq!(
            order,
            vec!["C8", "C7", "C6", "C4", "C3", "C5", "C2", "C1", "C0"]
        );
        assert_eq!(res.get("checked").and_then(|v| v.as_f64()), Some(9.0));
    }

    fn unread_with_channel(
        mut channel: JsonValue,
    ) -> (Result<JsonValue, SlackClientError>, Vec<String>) {
        if let JsonValue::Object(ref mut entries) = channel {
            if !entries.iter().any(|(k, _)| k == "is_private") {
                entries.push(("is_private".to_string(), false.into()));
            }
        }
        let _guard = set_mock_fetch(move |req| {
            if req.url.contains("/api/conversations.info") {
                return Ok(HttpResponse::json(
                    200,
                    JsonValue::object(vec![("ok", true.into()), ("channel", channel.clone())]),
                ));
            }
            Ok(HttpResponse::json(
                200,
                JsonValue::object(vec![
                    ("ok", true.into()),
                    (
                        "messages",
                        JsonValue::Array(vec![JsonValue::object(vec![("ts", "5.0".into())])]),
                    ),
                ]),
            ))
        });
        let mut env = stdio_env();
        env.insert("SLACK_CHANNEL_IDS".to_string(), "C1".to_string());
        let res = client_for(&env).list_unread(None);
        let urls = _guard
            .calls
            .lock()
            .unwrap()
            .iter()
            .map(|c| c.url.clone())
            .collect();
        (res, urls)
    }

    #[test]
    fn list_unread_reads_cursors_as_typescript_did() {
        let oldest_of = |urls: &[String]| -> Option<String> {
            urls.iter()
                .find(|u| u.contains("conversations.history"))
                .and_then(|u| {
                    ParsedUrl::parse(u)
                        .unwrap()
                        .query_get("oldest")
                        .map(str::to_string)
                })
        };

        // "" is Number("") === 0: asked from the start, as never read.
        let (res, urls) = unread_with_channel(JsonValue::object(vec![("last_read", "".into())]));
        assert_eq!(oldest_of(&urls).as_deref(), Some("0"));
        let res = res.unwrap();
        let conv = &res.get("conversations").unwrap().as_array().unwrap()[0];
        assert_eq!(conv.get("last_read"), Some(&JsonValue::str("")));

        // null is present (only undefined skips) and Number(null) === 0.
        let (res, urls) =
            unread_with_channel(JsonValue::object(vec![("last_read", JsonValue::Null)]));
        assert_eq!(oldest_of(&urls).as_deref(), Some("0"));
        let res = res.unwrap();
        let conv = &res.get("conversations").unwrap().as_array().unwrap()[0];
        assert_eq!(conv.get("last_read"), Some(&JsonValue::Null));
        assert_eq!(conv.get("latest_ts"), Some(&JsonValue::str("5.0")));

        // A real cursor is passed through as written.
        let (_, urls) =
            unread_with_channel(JsonValue::object(vec![("last_read", "123.000400".into())]));
        assert_eq!(oldest_of(&urls).as_deref(), Some("123.000400"));

        // No field at all: not tracked, so not asked about.
        let (res, urls) = unread_with_channel(JsonValue::object(vec![("name", "x".into())]));
        assert!(oldest_of(&urls).is_none());
        assert!(res
            .unwrap()
            .get("conversations")
            .unwrap()
            .as_array()
            .unwrap()
            .is_empty());

        // Truthiness, not strict booleans: is_archived 1 skips.
        let (_, urls) = unread_with_channel(JsonValue::object(vec![
            ("last_read", "1.0".into()),
            ("is_archived", JsonValue::Number(1.0)),
        ]));
        assert!(oldest_of(&urls).is_none());
    }

    #[test]
    fn list_unread_fails_the_whole_listing_when_a_call_throws() {
        // TS: an exception in any worker rejected Promise.all, so the tool
        // answered with that error rather than a partial listing.
        let _guard = set_mock_fetch(|req| {
            if req.url.contains("/api/conversations.history") && req.url.contains("channel=C3") {
                return Err("fetch failed".to_string());
            }
            if req.url.contains("/api/conversations.info") {
                return Ok(HttpResponse::json(
                    200,
                    JsonValue::object(vec![
                        ("ok", true.into()),
                        (
                            "channel",
                            JsonValue::object(vec![
                                ("is_private", false.into()),
                                ("last_read", "1.0".into()),
                            ]),
                        ),
                    ]),
                ));
            }
            Ok(HttpResponse::json(
                200,
                JsonValue::object(vec![("ok", true.into())]),
            ))
        });
        let mut env = stdio_env();
        env.insert(
            "SLACK_CHANNEL_IDS".to_string(),
            "C0,C1,C2,C3,C4,C5,C6,C7".to_string(),
        );
        let res = client_for(&env).list_unread(None);
        assert_eq!(res.unwrap_err().message(), "fetch failed");
    }

    // ── emoji ───────────────────────────────────────────────────────────

    #[test]
    fn list_emoji_keeps_values_and_lowercases_with_unicode_rules() {
        let _guard = set_mock_fetch(|_| {
            Ok(HttpResponse::json(
                200,
                JsonValue::parse(
                    r#"{"ok":true,"emoji":{"Émoji_party":"https://e/a.png","odd":7,"gone":null,"parrot":"alias:party"}}"#,
                )
                .unwrap(),
            ))
        });
        let c = client_for(&stdio_env());
        let all = c.list_emoji(None, None).unwrap();
        // Non-string values are kept, as TS kept them.
        assert_eq!(
            all.get("emoji").unwrap().to_json_string(),
            r#"{"Émoji_party":"https://e/a.png","odd":7,"gone":null,"parrot":"alias:party"}"#
        );
        // "ÉMOJI".toLowerCase() === "émoji", matching "Émoji_party".
        let found = c.list_emoji(Some("ÉMOJI"), None).unwrap();
        assert_eq!(
            found.get("emoji").unwrap().to_json_string(),
            r#"{"Émoji_party":"https://e/a.png"}"#
        );
        // An empty query filters nothing.
        assert_eq!(
            c.list_emoji(Some(""), None).unwrap().get("emoji"),
            all.get("emoji")
        );
        // Excluding aliases calls startsWith on every value; JavaScript threw
        // on the first non-string, and so does this.
        let err = c.list_emoji(None, Some(false)).unwrap_err();
        assert_eq!(err.message(), "value.startsWith is not a function");
    }

    #[test]
    fn list_emoji_reports_a_null_value_as_javascript_did() {
        let _guard = set_mock_fetch(|_| {
            Ok(HttpResponse::json(
                200,
                JsonValue::parse(r#"{"ok":true,"emoji":{"a":"alias:b","gone":null}}"#).unwrap(),
            ))
        });
        let err = client_for(&stdio_env())
            .list_emoji(None, Some(false))
            .unwrap_err();
        assert_eq!(
            err.message(),
            "Cannot read properties of null (reading 'startsWith')"
        );
    }

    // ── files ───────────────────────────────────────────────────────────

    fn file_mock(file: JsonValue, bytes: &'static [u8]) -> MockFetchGuard {
        set_mock_fetch(move |req| {
            if req.url.contains("/api/files.info") {
                return Ok(HttpResponse::json(
                    200,
                    JsonValue::object(vec![("ok", true.into()), ("file", file.clone())]),
                ));
            }
            if req.url.contains("/api/files.getUploadURLExternal") {
                return Ok(HttpResponse::json(
                    200,
                    JsonValue::object(vec![
                        ("ok", true.into()),
                        ("upload_url", "https://files.slack.com/upload/v1/abc".into()),
                        ("file_id", "F0NEW00001".into()),
                    ]),
                ));
            }
            if req.url.contains("/api/") {
                return Ok(HttpResponse::json(
                    200,
                    JsonValue::object(vec![("ok", true.into())]),
                ));
            }
            Ok(HttpResponse {
                status: 200,
                headers: vec![],
                body: bytes.to_vec(),
            })
        })
    }

    #[test]
    fn read_file_retries_with_the_user_token_when_the_bot_gets_not_visible() {
        // Live Slack answers `not_visible` (not `file_not_found`) when the bot
        // cannot see a canvas; the user token can. Found in UAT 2026-11-11.
        let _guard = set_mock_fetch(|req| {
            if req.url.contains("/api/files.info") {
                if req.auth() == Some("Bearer xoxp-test") {
                    return Ok(HttpResponse::json(
                        200,
                        JsonValue::object(vec![
                            ("ok", true.into()),
                            (
                                "file",
                                JsonValue::object(vec![
                                    ("id", "F1".into()),
                                    ("filetype", "text".into()),
                                    (
                                        "url_private",
                                        "https://files.slack.com/files-pri/T-F1/x".into(),
                                    ),
                                ]),
                            ),
                        ]),
                    ));
                }
                return Ok(HttpResponse::json(
                    200,
                    JsonValue::object(vec![("ok", false.into()), ("error", "not_visible".into())]),
                ));
            }
            Ok(HttpResponse {
                status: 200,
                headers: vec![],
                body: b"hello".to_vec(),
            })
        });
        let res = client_for(&stdio_env()).read_file("F1", None).unwrap();
        assert_eq!(res.get("content").and_then(|v| v.as_str()), Some("hello"));
    }

    #[test]
    fn read_file_shapes_its_answer_like_the_typescript_literal() {
        // name/title/mimetype absent: omitted, not null. BOM: stripped.
        let _guard = file_mock(
            JsonValue::object(vec![
                ("id", "F1".into()),
                ("filetype", "text".into()),
                (
                    "url_private",
                    "https://files.slack.com/files-pri/T-F1/x".into(),
                ),
            ]),
            b"\xEF\xBB\xBFhello",
        );
        let res = client_for(&stdio_env()).read_file("F1", None).unwrap();
        assert_eq!(
            res.to_json_string(),
            r#"{"ok":true,"id":"F1","size":8,"content":"hello"}"#
        );
        drop(_guard);

        // Present-but-null fields stay, as JSON.stringify keeps null.
        let _guard = file_mock(
            JsonValue::object(vec![
                ("id", "F1".into()),
                ("name", JsonValue::Null),
                ("title", "T".into()),
                ("mimetype", "text/plain".into()),
                (
                    "url_private",
                    "https://files.slack.com/files-pri/T-F1/x".into(),
                ),
            ]),
            b"hi \xFF",
        );
        let res = client_for(&stdio_env()).read_file("F1", None).unwrap();
        assert_eq!(
            res.to_json_string(),
            "{\"ok\":true,\"id\":\"F1\",\"name\":null,\"title\":\"T\",\"mimetype\":\"text/plain\",\"size\":4,\"content\":\"hi \u{FFFD}\"}"
        );
    }

    #[test]
    fn read_file_compares_and_reports_the_cap_as_numbers() {
        let _guard = file_mock(
            JsonValue::object(vec![
                ("id", "F1".into()),
                ("mimetype", "text/plain".into()),
                ("size", JsonValue::Number(10.75)),
                (
                    "url_private",
                    "https://files.slack.com/files-pri/T-F1/x".into(),
                ),
            ]),
            b"",
        );
        let err = client_for(&stdio_env())
            .read_file_num("F1", Some(10.5))
            .unwrap_err();
        assert_eq!(
            err.message(),
            "File F1 is 10.75 bytes, larger than the 10.5 byte cap. Raise max_bytes or use slack_download_file."
        );
    }

    #[test]
    fn download_file_omits_an_absent_name() {
        let _guard = file_mock(
            JsonValue::object(vec![
                ("id", "F1".into()),
                (
                    "url_private",
                    "https://files.slack.com/files-pri/T-F1/x".into(),
                ),
            ]),
            b"abc",
        );
        let dir = std::env::temp_dir().join(format!(
            "mcp-slack-rs-noname-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let target = dir.join("out.bin");
        let res = client_for(&stdio_env())
            .download_file("F1", target.to_str().unwrap())
            .unwrap();
        assert!(!res.contains_key("name"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn upload_decodes_base64_as_node_and_sends_no_authorization_with_the_bytes() {
        let guard = file_mock(JsonValue::object(vec![]), b"");
        client_for(&stdio_env())
            .upload_file(UploadFileInput {
                channel_id: "C1".to_string(),
                filename: "a.bin".to_string(),
                content: None,
                // Node stops at the first '=': this is "hello", 5 bytes.
                content_base64: Some("aGVsbG8=d29ybGQ=".to_string()),
                title: None,
                initial_comment: None,
                thread_ts: None,
            })
            .unwrap();
        let calls = guard.calls.lock().unwrap();
        assert_eq!(calls.len(), 3);
        assert!(calls[0].url.contains("length=5"));
        assert_eq!(calls[1].url, "https://files.slack.com/upload/v1/abc");
        assert_eq!(calls[1].body.as_deref(), Some(&b"hello"[..]));
        assert_eq!(calls[1].auth(), None);
    }

    // ── A1-A4 allow-list gap guards ─────────────────────────────────────

    #[test]
    fn bot_to_user_fallback_only_when_channel_guard_is_unrestricted() {
        let guard = set_mock_fetch(|req| {
            if req.auth() == Some("Bearer xoxb-test") {
                let err = if req.url.contains("C_MISSING") {
                    "channel_not_found"
                } else {
                    "not_in_channel"
                };
                Ok(HttpResponse::json(
                    200,
                    JsonValue::object(vec![("ok", false.into()), ("error", err.into())]),
                ))
            } else {
                Ok(HttpResponse::json(
                    200,
                    JsonValue::object(vec![
                        ("ok", true.into()),
                        (
                            "messages",
                            JsonValue::Array(vec![JsonValue::object(vec![
                                ("ts", "1.0".into()),
                                ("text", "secret".into()),
                            ])]),
                        ),
                    ]),
                ))
            }
        });

        // Restricted HTTP with user token: must NOT retry with user token.
        let mut restricted_http = http_env();
        restricted_http.insert("SLACK_USER_TOKEN".to_string(), "xoxp-test".to_string());
        restricted_http.insert(
            "SLACK_CHANNEL_IDS".to_string(),
            "C_ALLOWED,C_MISSING".to_string(),
        );
        let res = client_for(&restricted_http)
            .get_channel_history("C_ALLOWED", None)
            .unwrap();
        assert_eq!(res.get("ok").and_then(|v| v.as_bool()), Some(false));
        assert_eq!(
            res.get("error").and_then(|v| v.as_str()),
            Some("not_in_channel")
        );
        assert_eq!(guard.calls.lock().unwrap().len(), 1);

        guard.calls.lock().unwrap().clear();
        let res_missing = client_for(&restricted_http)
            .get_channel_history("C_MISSING", None)
            .unwrap();
        assert_eq!(res_missing.get("ok").and_then(|v| v.as_bool()), Some(false));
        assert_eq!(
            res_missing.get("error").and_then(|v| v.as_str()),
            Some("channel_not_found")
        );
        assert_eq!(guard.calls.lock().unwrap().len(), 1);

        // Restricted stdio with allow-list: also must NOT retry with user token.
        guard.calls.lock().unwrap().clear();
        let mut restricted_stdio = stdio_env();
        restricted_stdio.insert("SLACK_CHANNEL_IDS".to_string(), "C_ALLOWED".to_string());
        let res_stdio = client_for(&restricted_stdio)
            .get_channel_history("C_ALLOWED", None)
            .unwrap();
        assert_eq!(res_stdio.get("ok").and_then(|v| v.as_bool()), Some(false));
        assert_eq!(guard.calls.lock().unwrap().len(), 1);

        // Unrestricted stdio: fallback to user token still works.
        guard.calls.lock().unwrap().clear();
        let ok_res = client_for(&stdio_env())
            .get_channel_history("C_ALLOWED", None)
            .unwrap();
        assert_eq!(ok_res.get("ok").and_then(|v| v.as_bool()), Some(true));
        assert_eq!(guard.calls.lock().unwrap().len(), 2);
    }

    #[test]
    fn http_enforces_visibility_whenever_allowlist_is_configured_even_with_user_token() {
        let _guard = set_mock_fetch(|_| {
            Ok(HttpResponse::json(
                200,
                JsonValue::object(vec![
                    ("ok", true.into()),
                    (
                        "channel",
                        JsonValue::object(vec![
                            ("id", "C_ACTUALLY_PRIVATE".into()),
                            ("is_private", true.into()),
                        ]),
                    ),
                ]),
            ))
        });

        let mut env = http_env();
        env.insert("SLACK_USER_TOKEN".to_string(), "xoxp-test".to_string());
        env.insert(
            "SLACK_CHANNEL_IDS".to_string(),
            "C_ACTUALLY_PRIVATE".to_string(),
        );
        let client = client_for(&env);
        assert!(matches!(
            client.verify_allowlist_visibility(),
            Err(SlackClientError::ChannelAllowlist(
                ChannelAllowlistError::ChannelVisibilityMismatch { .. }
            ))
        ));
        assert!(matches!(
            client.get_channel_info("C_ACTUALLY_PRIVATE"),
            Err(SlackClientError::ChannelAllowlist(
                ChannelAllowlistError::ChannelVisibilityMismatch { .. }
            ))
        ));

        // Unrestricted HTTP with user token: allow-list remains optional and visibility unguarded.
        let mut unrestricted_http = http_env();
        unrestricted_http.insert("SLACK_USER_TOKEN".to_string(), "xoxp-test".to_string());
        unrestricted_http.insert("SLACK_CHANNEL_IDS".to_string(), "".to_string());
        let unrestricted_client = client_for(&unrestricted_http);
        assert!(unrestricted_client.verify_allowlist_visibility().is_ok());
        assert!(unrestricted_client
            .get_channel_info("C_ACTUALLY_PRIVATE")
            .is_ok());

        // Restricted stdio with allow-list: visibility is enforced too.
        let mut restricted_stdio = stdio_env();
        restricted_stdio.insert(
            "SLACK_CHANNEL_IDS".to_string(),
            "C_ACTUALLY_PRIVATE".to_string(),
        );
        let stdio_restricted_client = client_for(&restricted_stdio);
        assert!(matches!(
            stdio_restricted_client.verify_allowlist_visibility(),
            Err(SlackClientError::ChannelAllowlist(
                ChannelAllowlistError::ChannelVisibilityMismatch { .. }
            ))
        ));
        assert!(matches!(
            stdio_restricted_client.get_channel_info("C_ACTUALLY_PRIVATE"),
            Err(SlackClientError::ChannelAllowlist(
                ChannelAllowlistError::ChannelVisibilityMismatch { .. }
            ))
        ));

        // Unrestricted stdio: visibility stays unguarded.
        let stdio_unrestricted_client = client_for(&stdio_env());
        assert!(stdio_unrestricted_client
            .verify_allowlist_visibility()
            .is_ok());
        assert!(stdio_unrestricted_client
            .get_channel_info("C_ACTUALLY_PRIVATE")
            .is_ok());
    }

    #[test]
    fn search_filters_disallowed_channels_and_reports_filtered_out_count() {
        let _guard = set_mock_fetch(|req| {
            if req.url.contains("/api/search.messages") {
                Ok(HttpResponse::json(
                    200,
                    JsonValue::parse(
                        r#"{"ok":true,"messages":{"total":3,"matches":[{"ts":"1.0","text":"ok","channel":{"id":"C_ALLOWED","name":"general"}},{"ts":"2.0","text":"secret","channel":{"id":"C_SECRET","name":"secret"}},{"ts":"3.0","text":"priv","channel":{"id":"G_PRIVATE"}}]}}"#,
                    )
                    .unwrap(),
                ))
            } else {
                Ok(HttpResponse::json(
                    200,
                    JsonValue::parse(
                        r#"{"ok":true,"files":{"total":3,"matches":[{"id":"F_OK","channels":["C_ALLOWED"],"groups":[],"ims":[]},{"id":"F_SECRET","channels":["C_OTHER"],"groups":["G_PRIV"],"ims":[]},{"id":"F_UNSHARED","channels":[],"groups":[],"ims":[]}]}}"#,
                    )
                    .unwrap(),
                ))
            }
        });

        let mut restricted = http_env();
        restricted.insert("SLACK_USER_TOKEN".to_string(), "xoxp-test".to_string());
        restricted.insert("SLACK_CHANNEL_IDS".to_string(), "C_ALLOWED".to_string());
        let client = client_for(&restricted);

        let msg_res = client.search_messages("deploy", None, None).unwrap();
        let msg_matches = msg_res
            .get("messages")
            .and_then(|m| m.get("matches"))
            .and_then(|m| m.as_array())
            .unwrap();
        assert_eq!(msg_matches.len(), 1);
        assert_eq!(
            msg_matches[0].get("ts").and_then(|v| v.as_str()),
            Some("1.0")
        );
        assert_eq!(
            msg_res.get("filtered_out").and_then(|v| v.as_i64()),
            Some(2)
        );

        let file_res = client.search_files("spec", None, None).unwrap();
        let file_matches = file_res
            .get("files")
            .and_then(|f| f.get("matches"))
            .and_then(|m| m.as_array())
            .unwrap();
        assert_eq!(file_matches.len(), 1);
        assert_eq!(
            file_matches[0].get("id").and_then(|v| v.as_str()),
            Some("F_OK")
        );
        assert_eq!(
            file_res.get("filtered_out").and_then(|v| v.as_i64()),
            Some(2)
        );

        // Unrestricted client leaves search output untouched with no filtered_out key.
        let unrestricted = client_for(&stdio_env());
        let raw_msg = unrestricted.search_messages("deploy", None, None).unwrap();
        assert_eq!(
            raw_msg
                .get("messages")
                .and_then(|m| m.get("matches"))
                .and_then(|m| m.as_array())
                .unwrap()
                .len(),
            3
        );
        assert!(!raw_msg.contains_key("filtered_out"));
    }

    #[test]
    fn canvas_operations_check_file_shares_when_allowlist_is_configured() {
        let guard = set_mock_fetch(|req| {
            if req.url.contains("/api/files.info") {
                if req.url.contains("file=F_ALLOWED") {
                    Ok(HttpResponse::json(
                        200,
                        JsonValue::parse(
                            r#"{"ok":true,"file":{"id":"F_ALLOWED","channels":["C_ALLOWED"],"groups":[],"ims":[]}}"#,
                        )
                        .unwrap(),
                    ))
                } else {
                    Ok(HttpResponse::json(
                        200,
                        JsonValue::parse(
                            r#"{"ok":true,"file":{"id":"F_DISALLOWED","channels":["C_SECRET"],"groups":[],"ims":[]}}"#,
                        )
                        .unwrap(),
                    ))
                }
            } else {
                Ok(HttpResponse::json(
                    200,
                    JsonValue::object(vec![("ok", true.into())]),
                ))
            }
        });

        let mut restricted = http_env();
        restricted.insert("SLACK_USER_TOKEN".to_string(), "xoxp-test".to_string());
        restricted.insert("SLACK_CHANNEL_IDS".to_string(), "C_ALLOWED".to_string());
        let client = client_for(&restricted);

        assert!(matches!(
            client.edit_canvas("F_DISALLOWED", "insert_at_end", Some("hi"), None),
            Err(SlackClientError::ChannelAllowlist(
                ChannelAllowlistError::FileNotAllowed { .. }
            ))
        ));
        assert!(matches!(
            client.lookup_canvas_sections("F_DISALLOWED", None, Some("hi")),
            Err(SlackClientError::ChannelAllowlist(
                ChannelAllowlistError::FileNotAllowed { .. }
            ))
        ));
        assert!(matches!(
            client.delete_canvas("F_DISALLOWED"),
            Err(SlackClientError::ChannelAllowlist(
                ChannelAllowlistError::FileNotAllowed { .. }
            ))
        ));
        // None of the disallowed calls may have reached canvases.* endpoints.
        assert!(guard
            .calls
            .lock()
            .unwrap()
            .iter()
            .all(|c| !c.url.contains("/api/canvases.")));

        // Allowed canvas succeeds.
        assert!(client
            .edit_canvas("F_ALLOWED", "insert_at_end", Some("hi"), None)
            .is_ok());
        assert!(client
            .lookup_canvas_sections("F_ALLOWED", None, Some("hi"))
            .is_ok());
        assert!(client.delete_canvas("F_ALLOWED").is_ok());

        // Unrestricted client skips files.info pre-check altogether.
        guard.calls.lock().unwrap().clear();
        let unrestricted = client_for(&stdio_env());
        assert!(unrestricted.delete_canvas("F_DISALLOWED").is_ok());
        let calls = guard.calls.lock().unwrap();
        assert_eq!(calls.len(), 1);
        assert!(calls[0].url.contains("/api/canvases.delete"));
    }

    #[test]
    fn parse_relative_since_converts_durations_and_rejects_invalid_inputs() {
        assert_eq!(
            parse_relative_since("30m", 1_700_001_800.0).unwrap(),
            "1700000000.000000"
        );
        assert_eq!(
            parse_relative_since("24h", 1_700_086_400.0).unwrap(),
            "1700000000.000000"
        );
        assert_eq!(
            parse_relative_since("7d", 1_700_604_800.0).unwrap(),
            "1700000000.000000"
        );
        assert_eq!(
            parse_relative_since("45s", 1_700_000_045.0).unwrap(),
            "1700000000.000000"
        );
        assert_eq!(
            parse_relative_since("1w", 1_700_604_800.0).unwrap(),
            "1700000000.000000"
        );
        for bad in ["", "   ", "abc", "30", "30ms", "-5m", "0h", "5y"] {
            let err = parse_relative_since(bad, 1_700_000_000.0).unwrap_err();
            assert!(
                err.to_string().contains("Invalid since value"),
                "expected clear error for {bad:?}, got {err}"
            );
        }
    }

    // ── D1-D5 ergonomics & resilience ───────────────────────────────────

    #[test]
    fn whoami_calls_auth_test_for_bot_and_optional_user_token() {
        let guard = set_mock_fetch(|req| {
            assert!(req.url.ends_with("/api/auth.test"));
            if req.auth() == Some("Bearer xoxb-test") {
                Ok(HttpResponse::json(
                    200,
                    JsonValue::parse(
                        r#"{"ok":true,"user_id":"U_BOT","team_id":"T123","bot_id":"B1"}"#,
                    )
                    .unwrap(),
                ))
            } else {
                Ok(HttpResponse::json(
                    200,
                    JsonValue::parse(r#"{"ok":true,"user_id":"U_HUMAN","team_id":"T123"}"#)
                        .unwrap(),
                ))
            }
        });

        // With user token: both bot and user populated.
        let with_user = client_for(&stdio_env()).whoami().unwrap();
        assert_eq!(
            with_user
                .get("bot")
                .and_then(|b| b.get("user_id"))
                .and_then(|v| v.as_str()),
            Some("U_BOT")
        );
        assert_eq!(
            with_user
                .get("user")
                .and_then(|u| u.get("user_id"))
                .and_then(|v| v.as_str()),
            Some("U_HUMAN")
        );
        assert_eq!(guard.calls.lock().unwrap().len(), 2);

        // Without user token (bot-only HTTP): user is null, only 1 call made.
        guard.calls.lock().unwrap().clear();
        let bot_only = client_for(&http_env()).whoami().unwrap();
        assert_eq!(
            bot_only
                .get("bot")
                .and_then(|b| b.get("bot_id"))
                .and_then(|v| v.as_str()),
            Some("B1")
        );
        assert_eq!(bot_only.get("user"), Some(&JsonValue::Null));
        assert_eq!(guard.calls.lock().unwrap().len(), 1);
    }

    #[test]
    fn remove_reaction_uses_user_token_and_enforces_channel_allowlist() {
        let guard = set_mock_fetch(|_| {
            Ok(HttpResponse::json(
                200,
                JsonValue::object(vec![("ok", true.into())]),
            ))
        });

        let mut restricted = http_env();
        restricted.insert("SLACK_USER_TOKEN".to_string(), "xoxp-test".to_string());
        restricted.insert("SLACK_CHANNEL_IDS".to_string(), "C_ALLOWED".to_string());
        let client = client_for(&restricted);

        assert!(matches!(
            client.remove_reaction("C_DISALLOWED", "1.0", "thumbsup"),
            Err(SlackClientError::ChannelAllowlist(
                ChannelAllowlistError::ChannelNotAllowed { .. }
            ))
        ));
        assert!(guard.calls.lock().unwrap().is_empty());

        client
            .remove_reaction("C_ALLOWED", "1.0", "thumbsup")
            .unwrap();
        let calls = guard.calls.lock().unwrap();
        assert_eq!(calls.len(), 1);
        assert!(calls[0].url.contains("/api/reactions.remove"));
        assert_eq!(calls[0].auth(), Some("Bearer xoxp-test"));
    }

    #[test]
    fn read_file_accepts_canvases_with_html_format_marker_and_enforces_size_cap() {
        for meta in [
            r#"{"id":"F_CANVAS","title":"Runbook","filetype":"canvas","url_private":"https://files.slack.com/files-pri/T-F/canvas"}"#,
            r#"{"id":"F_QUIP","title":"Notes","filetype":"quip","url_private":"https://files.slack.com/files-pri/T-F/quip"}"#,
            r#"{"id":"F_DOC","title":"Doc","mimetype":"application/vnd.slack-docs","url_private":"https://files.slack.com/files-pri/T-F/doc"}"#,
        ] {
            let file_json = JsonValue::parse(meta).unwrap();
            let id = file_json
                .get("id")
                .and_then(|v| v.as_str())
                .unwrap()
                .to_string();
            let _guard = file_mock(file_json, b"<h1>Runbook</h1><p>Step 1</p>");
            let res = client_for(&stdio_env()).read_file(&id, None).unwrap();
            assert_eq!(res.get("ok").and_then(|v| v.as_bool()), Some(true));
            assert_eq!(res.get("format").and_then(|v| v.as_str()), Some("html"));
            assert_eq!(
                res.get("content").and_then(|v| v.as_str()),
                Some("<h1>Runbook</h1><p>Step 1</p>")
            );

            // Size cap applies to canvases too, even when files.info omitted `size`.
            let err = client_for(&stdio_env())
                .read_file_num(&id, Some(10.0))
                .unwrap_err();
            assert!(err.message().contains("larger than the 10 byte cap"));
        }
    }

    #[test]
    fn api_retries_429_before_json_parsing_with_capped_backoff_then_returns_ratelimited() {
        let sleep_guard = set_mock_sleep();
        let attempt = Arc::new(AtomicUsize::new(0));
        let attempt_ref = attempt.clone();

        // 1. Two non-JSON 429s (plain text + HTML) followed by a 200 JSON success:
        //    status checked before JSON parsing; waits clamped to min(Retry-After, 10s).
        let fetch_guard = set_mock_fetch(move |_| {
            let n = attempt_ref.fetch_add(1, Ordering::SeqCst);
            match n {
                0 => Ok(HttpResponse {
                    status: 429,
                    headers: vec![("Retry-After".to_string(), "25".to_string())],
                    body: b"Too Many Requests".to_vec(),
                }),
                1 => Ok(HttpResponse {
                    status: 429,
                    headers: vec![("Retry-After".to_string(), "2.5".to_string())],
                    body: b"<html><body>429</body></html>".to_vec(),
                }),
                _ => Ok(HttpResponse::json(
                    200,
                    JsonValue::parse(r#"{"ok":true,"messages":[]}"#).unwrap(),
                )),
            }
        });

        let client = client_for(&stdio_env());
        let ok_res = client.get_channel_history("C1", None).unwrap();
        assert_eq!(ok_res.get("ok").and_then(|v| v.as_bool()), Some(true));
        assert_eq!(fetch_guard.calls.lock().unwrap().len(), 3);
        assert_eq!(
            *sleep_guard.sleeps.lock().unwrap(),
            vec![Duration::from_secs(10), Duration::from_millis(2_500)]
        );
        drop(fetch_guard);

        // 2. Persistent non-JSON 429 exhausts 2 retries (3 total attempts) and returns
        //    {ok: false, error: "ratelimited", retry_after: 7}.
        sleep_guard.sleeps.lock().unwrap().clear();
        let persistent_guard = set_mock_fetch(|_| {
            Ok(HttpResponse {
                status: 429,
                headers: vec![("Retry-After".to_string(), "7".to_string())],
                body: b"upstream rate limit exceeded".to_vec(),
            })
        });
        let limited = client.get_channel_history("C1", None).unwrap();
        assert_eq!(limited.get("ok").and_then(|v| v.as_bool()), Some(false));
        assert_eq!(
            limited.get("error").and_then(|v| v.as_str()),
            Some("ratelimited")
        );
        assert_eq!(
            limited.get("retry_after").and_then(|v| v.as_f64()),
            Some(7.0)
        );
        assert_eq!(persistent_guard.calls.lock().unwrap().len(), 3);
        assert_eq!(
            *sleep_guard.sleeps.lock().unwrap(),
            vec![Duration::from_secs(7), Duration::from_secs(7)]
        );
        drop(persistent_guard);

        // 3. Non-429 Slack errors do not trigger 429 retries.
        sleep_guard.sleeps.lock().unwrap().clear();
        let err_guard = set_mock_fetch(|_| {
            Ok(HttpResponse::json(
                200,
                JsonValue::parse(r#"{"ok":false,"error":"invalid_auth"}"#).unwrap(),
            ))
        });
        let non_429 = client.get_channel_history("C1", None).unwrap();
        assert_eq!(
            non_429.get("error").and_then(|v| v.as_str()),
            Some("invalid_auth")
        );
        assert_eq!(err_guard.calls.lock().unwrap().len(), 1);
        assert!(sleep_guard.sleeps.lock().unwrap().is_empty());
    }

    #[test]
    fn history_and_replies_pass_response_through_without_top_level_next_cursor() {
        let payload = r#"{"ok":true,"messages":[{"ts":"1.0","text":"hi"}],"response_metadata":{"next_cursor":"cur_abc"}}"#;
        let _guard = set_mock_fetch(move |_| {
            Ok(HttpResponse::json(200, JsonValue::parse(payload).unwrap()))
        });
        let client = client_for(&stdio_env());

        let hist = client.get_channel_history("C1", None).unwrap();
        assert!(!hist.contains_key("next_cursor"));
        assert_eq!(hist.to_json_string(), payload);

        let replies = client.get_thread_replies("C1", "1.0").unwrap();
        assert!(!replies.contains_key("next_cursor"));
        assert_eq!(replies.to_json_string(), payload);
    }

    #[test]
    fn list_unread_patient_skips_api_429_retries_so_call_count_matches_main() {
        let sleep_guard = set_mock_sleep();
        let guard = set_mock_fetch(|req| {
            assert!(req.url.contains("/api/conversations.info"));
            Ok(HttpResponse::json(
                429,
                JsonValue::object(vec![("ok", false.into()), ("error", "ratelimited".into())]),
            )
            .with_header("Retry-After", "0"))
        });

        let mut env = stdio_env();
        env.insert("SLACK_CHANNEL_IDS".to_string(), "C1".to_string());
        let res = client_for(&env).list_unread(None).unwrap();

        // Main's patient() makes 1 initial attempt + UNREAD_MAX_RETRIES (3) = 4 HTTP calls.
        assert_eq!(guard.calls.lock().unwrap().len(), 4);
        assert!(sleep_guard.sleeps.lock().unwrap().is_empty());
        let errors = res.get("errors").and_then(|v| v.as_array()).unwrap();
        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].get("id").and_then(|v| v.as_str()), Some("C1"));
        assert_eq!(
            errors[0].get("error").and_then(|v| v.as_str()),
            Some("ratelimited")
        );
    }

    #[test]
    fn read_file_post_download_size_cap_applies_only_to_canvases() {
        // Text file with no `size` in files.info keeps main's behaviour (no post-download cap).
        let _guard = file_mock(
            JsonValue::parse(
                r#"{"id":"F_TXT","filetype":"text","mimetype":"text/plain","url_private":"https://files.slack.com/files-pri/T-F/txt"}"#,
            )
            .unwrap(),
            b"01234567890123456789",
        );
        let res = client_for(&stdio_env())
            .read_file_num("F_TXT", Some(10.0))
            .unwrap();
        assert_eq!(res.get("size").and_then(|v| v.as_i64()), Some(20));
        assert_eq!(
            res.get("content").and_then(|v| v.as_str()),
            Some("01234567890123456789")
        );
        drop(_guard);

        // Text file with files.info `size` <= max_bytes also succeeds even if downloaded bytes exceed max_bytes.
        let _guard = file_mock(
            JsonValue::parse(
                r#"{"id":"F_TXT2","filetype":"text","mimetype":"text/plain","size":5,"url_private":"https://files.slack.com/files-pri/T-F/txt2"}"#,
            )
            .unwrap(),
            b"01234567890123456789",
        );
        let res2 = client_for(&stdio_env())
            .read_file_num("F_TXT2", Some(10.0))
            .unwrap();
        assert_eq!(res2.get("size").and_then(|v| v.as_i64()), Some(20));
        drop(_guard);

        // Canvas without files.info `size` still enforces the post-download size cap.
        let _guard = file_mock(
            JsonValue::parse(
                r#"{"id":"F_CANVAS","filetype":"canvas","url_private":"https://files.slack.com/files-pri/T-F/canvas"}"#,
            )
            .unwrap(),
            b"01234567890123456789",
        );
        let err = client_for(&stdio_env())
            .read_file_num("F_CANVAS", Some(10.0))
            .unwrap_err();
        assert!(err.message().contains("larger than the 10 byte cap"));
    }

    #[test]
    fn read_file_url_private_download_fallback_applies_only_to_canvases() {
        // Text file missing url_private keeps main's error even if url_private_download is present.
        let _guard = file_mock(
            JsonValue::parse(
                r#"{"id":"F_TXT","filetype":"text","mimetype":"text/plain","url_private_download":"https://files.slack.com/files-pri/T-F/download/txt"}"#,
            )
            .unwrap(),
            b"hello",
        );
        let err = client_for(&stdio_env())
            .read_file("F_TXT", None)
            .unwrap_err();
        assert_eq!(err.message(), "File F_TXT has no downloadable content.");
        drop(_guard);

        // Canvas missing url_private falls back to url_private_download.
        let _guard = file_mock(
            JsonValue::parse(
                r#"{"id":"F_CANVAS","filetype":"canvas","url_private_download":"https://files.slack.com/files-pri/T-F/download/canvas"}"#,
            )
            .unwrap(),
            b"<p>canvas body</p>",
        );
        let res = client_for(&stdio_env())
            .read_file("F_CANVAS", None)
            .unwrap();
        assert_eq!(res.get("format").and_then(|v| v.as_str()), Some("html"));
        assert_eq!(
            res.get("content").and_then(|v| v.as_str()),
            Some("<p>canvas body</p>")
        );
    }

    #[test]
    fn search_strips_total_paging_and_pagination_when_allowlist_is_set() {
        let _guard = set_mock_fetch(|req| {
            if req.url.contains("/api/search.messages") {
                Ok(HttpResponse::json(
                    200,
                    JsonValue::parse(
                        r#"{"ok":true,"query":"deploy","messages":{"total":47,"paging":{"count":20,"total":47,"page":1,"pages":3},"pagination":{"total_count":47,"page":1,"per_page":20,"page_count":3,"first":1,"last":20},"matches":[{"ts":"1.0","text":"ok","channel":{"id":"C_ALLOWED"}},{"ts":"2.0","text":"secret","channel":{"id":"C_SECRET"}}]}}"#,
                    )
                    .unwrap(),
                ))
            } else {
                Ok(HttpResponse::json(
                    200,
                    JsonValue::parse(
                        r#"{"ok":true,"query":"spec","files":{"total":19,"paging":{"count":20,"total":19,"page":1,"pages":1},"pagination":{"total_count":19,"page":1,"per_page":20,"page_count":1,"first":1,"last":19},"matches":[{"id":"F_OK","channels":["C_ALLOWED"],"groups":[],"ims":[]},{"id":"F_SECRET","channels":["C_SECRET"],"groups":[],"ims":[]}]}}"#,
                    )
                    .unwrap(),
                ))
            }
        });

        let mut restricted = http_env();
        restricted.insert("SLACK_USER_TOKEN".to_string(), "xoxp-test".to_string());
        restricted.insert("SLACK_CHANNEL_IDS".to_string(), "C_ALLOWED".to_string());
        let client = client_for(&restricted);

        let msg_res = client.search_messages("deploy", None, None).unwrap();
        let messages = msg_res.get("messages").unwrap();
        assert!(!messages.contains_key("total"));
        assert!(!messages.contains_key("paging"));
        assert!(!messages.contains_key("pagination"));
        assert_eq!(
            messages
                .get("matches")
                .and_then(|m| m.as_array())
                .unwrap()
                .len(),
            1
        );
        assert_eq!(
            msg_res.get("filtered_out").and_then(|v| v.as_i64()),
            Some(1)
        );

        let file_res = client.search_files("spec", None, None).unwrap();
        let files = file_res.get("files").unwrap();
        assert!(!files.contains_key("total"));
        assert!(!files.contains_key("paging"));
        assert!(!files.contains_key("pagination"));
        assert_eq!(
            files
                .get("matches")
                .and_then(|m| m.as_array())
                .unwrap()
                .len(),
            1
        );
        assert_eq!(
            file_res.get("filtered_out").and_then(|v| v.as_i64()),
            Some(1)
        );

        // Unrestricted output keeps total, paging, and pagination intact.
        let unrestricted = client_for(&stdio_env());
        let raw_msg = unrestricted.search_messages("deploy", None, None).unwrap();
        let raw_messages = raw_msg.get("messages").unwrap();
        assert_eq!(raw_messages.get("total").and_then(|v| v.as_i64()), Some(47));
        assert!(raw_messages.contains_key("paging"));
        assert!(raw_messages.contains_key("pagination"));
        assert!(!raw_msg.contains_key("filtered_out"));
    }
}
