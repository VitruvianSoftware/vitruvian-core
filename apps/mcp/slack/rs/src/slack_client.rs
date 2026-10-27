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
use std::io::Write;
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use crate::base64;
use crate::channel_allowlist::{
    assert_file_share_allowed, assert_params_allowed, ChannelAllowlistError, ChannelGuard,
    FileShares,
};
use crate::config::{SlackCredentials, WriteTokenPreference};
use crate::json::JsonValue;
use crate::permalink::InvalidPermalinkError;
use crate::url::encode_query_params;

const UNREAD_MAX_RETRIES: usize = 3;
const UNREAD_MAX_WAIT_SECONDS: u64 = 30;
const UNREAD_MAX_PAGES: usize = 5;
const DEFAULT_READ_CAP: usize = 1_048_576;

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

fn execute_http(req: &HttpRequest) -> Result<HttpResponse, String> {
    let maybe_mock = THREAD_MOCK_FETCH.with(|cell| cell.borrow().clone());
    if let Some(mock) = maybe_mock {
        return mock(req);
    }

    // Production fallback via system curl
    let mut cmd = Command::new("curl");
    cmd.arg("-sS")
        .arg("-i")
        .arg("-X")
        .arg(&req.method)
        .arg(&req.url);
    for (k, v) in &req.headers {
        cmd.arg("-H").arg(format!("{k}: {v}"));
    }
    if let Some(body) = &req.body {
        cmd.arg("--data-binary")
            .arg(String::from_utf8_lossy(body).as_ref());
    }
    let output = cmd.output().map_err(|e| format!("fetch failed: {e}"))?;
    if !output.status.success() {
        return Err(format!(
            "fetch failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    let raw = output.stdout;
    let text = String::from_utf8_lossy(&raw);
    let (head, body_str) = text
        .split_once("\r\n\r\n")
        .or_else(|| text.split_once("\n\n"))
        .unwrap_or(("", text.as_ref()));
    let mut status = 200u16;
    let mut headers = Vec::new();
    for (idx, line) in head.lines().enumerate() {
        if idx == 0 {
            if let Some(code_str) = line.split_whitespace().nth(1) {
                if let Ok(code) = code_str.parse::<u16>() {
                    status = code;
                }
            }
        } else if let Some((k, v)) = line.split_once(':') {
            headers.push((k.trim().to_string(), v.trim().to_string()));
        }
    }
    Ok(HttpResponse {
        status,
        headers,
        body: body_str.as_bytes().to_vec(),
    })
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
            let mut qs_pairs = Vec::new();
            if let Some(entries) = params.as_object() {
                for (k, v) in entries {
                    if !v.is_null() {
                        let s = match v {
                            JsonValue::String(s) => s.clone(),
                            other => other.to_json_string(),
                        };
                        qs_pairs.push((k.as_str(), s));
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

        let res = execute_http(&req).map_err(SlackClientError::Message)?;
        let body_str = String::from_utf8_lossy(&res.body);
        let mut data = JsonValue::parse(&body_str).map_err(SlackClientError::Message)?;

        if res.status == 429 {
            let retry_after = res
                .header("Retry-After")
                .and_then(|h| h.parse::<f64>().ok())
                .filter(|n| n.is_finite())
                .unwrap_or(1.0);
            data.insert("retry_after", JsonValue::Number(retry_after));
        }

        let ok = data.get("ok").and_then(|v| v.as_bool()).unwrap_or(false);
        let err_str = data.get("error").and_then(|v| v.as_str()).unwrap_or("");
        if !ok
            && token == WriteTokenPreference::Bot
            && self.user_auth.is_some()
            && (err_str == "not_in_channel" || err_str == "channel_not_found")
        {
            return self.api(method, params, WriteTokenPreference::User, http_method);
        }

        Ok(data)
    }

    // ── Channels ────────────────────────────────────────────────────────

    pub fn list_channels(
        &self,
        limit: Option<usize>,
        cursor: Option<&str>,
    ) -> Result<JsonValue, SlackClientError> {
        let limit = limit.unwrap_or(100);
        if self.channel_guard.allowed.is_empty() {
            let types = if self.user_auth.is_some() {
                "public_channel,private_channel,im,mpim"
            } else {
                "public_channel"
            };
            let mut params = JsonValue::object(vec![
                ("types", types.into()),
                ("exclude_archived", "true".into()),
                ("limit", limit.min(200).into()),
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
            let ok = data.get("ok").and_then(|v| v.as_bool()).unwrap_or(false);
            if let (true, Some(ch)) = (ok, data.get("channel")) {
                self.channel_guard
                    .assert_visibility_matches(channel_id, ch.get("is_private"))?;
                let archived = ch
                    .get("is_archived")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);
                if !archived {
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
        if let Some(ch) = data.get("channel") {
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

            let ok = data.get("ok").and_then(|v| v.as_bool()).unwrap_or(false);
            let channel = data.get("channel");
            if !ok || channel.is_none() {
                let err_code = data
                    .get("error")
                    .and_then(|v| v.as_str())
                    .unwrap_or("no channel");
                let remedy = if err_code == "channel_not_found" || err_code == "not_in_channel" {
                    " Invite the bot to the channel first, then deploy — this check \
runs before the listener starts, so an uninvited private \
channel stops the server rather than degrading it."
                } else {
                    ""
                };
                return Err(SlackClientError::Message(format!(
                    "Cannot verify allow-listed channel {channel_id}: Slack returned \
{err_code}. Every channel in SLACK_CHANNEL_IDS \
and SLACK_PRIVATE_CHANNEL_IDS must be readable by this bot.{remedy}"
                )));
            }

            self.channel_guard
                .assert_visibility_matches(channel_id, channel.unwrap().get("is_private"))?;
        }
        Ok(())
    }

    pub fn get_channel_history(
        &self,
        channel_id: &str,
        limit: Option<usize>,
    ) -> Result<JsonValue, SlackClientError> {
        self.api(
            "conversations.history",
            JsonValue::object(vec![
                ("channel", channel_id.into()),
                ("limit", limit.unwrap_or(10).into()),
            ]),
            WriteTokenPreference::Bot,
            "GET",
        )
    }

    pub fn get_channel_history_param(
        &self,
        channel_param: JsonValue,
        limit: Option<usize>,
    ) -> Result<JsonValue, SlackClientError> {
        self.api(
            "conversations.history",
            JsonValue::object(vec![
                ("channel", channel_param),
                ("limit", limit.unwrap_or(10).into()),
            ]),
            WriteTokenPreference::Bot,
            "GET",
        )
    }

    pub fn get_thread_replies(
        &self,
        channel_id: &str,
        thread_ts: &str,
    ) -> Result<JsonValue, SlackClientError> {
        self.api(
            "conversations.replies",
            JsonValue::object(vec![
                ("channel", channel_id.into()),
                ("ts", thread_ts.into()),
            ]),
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
            if data.get("ok").and_then(|v| v.as_bool()) != Some(true) {
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
        if data.get("ok").and_then(|v| v.as_bool()) != Some(true) {
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
        let per_conversation = max_per_conversation.unwrap_or(100).clamp(1, 200);
        let mut skipped = Vec::new();
        let mut truncated = false;
        let mut candidates: Vec<String> = self.channel_guard.allowed.clone();

        if candidates.is_empty() {
            for types in ["public_channel,private_channel", "im", "mpim"] {
                let mut cursor: Option<String> = None;
                for page in 0.. {
                    let mut params = JsonValue::object(vec![
                        ("types", types.into()),
                        ("exclude_archived", "true".into()),
                        ("limit", 200i64.into()),
                        ("team_id", self.team_id.as_str().into()),
                    ]);
                    if let Some(c) = &cursor {
                        params.insert("cursor", c.as_str().into());
                    }
                    let data = self.api(
                        "users.conversations",
                        params,
                        WriteTokenPreference::User,
                        "GET",
                    )?;
                    let ok = data.get("ok").and_then(|v| v.as_bool()).unwrap_or(false);
                    if !ok {
                        let err = data
                            .get("error")
                            .and_then(|v| v.as_str())
                            .unwrap_or("unknown_error");
                        skipped.push(JsonValue::object(vec![
                            ("types", types.into()),
                            ("error", err.into()),
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
                    let next_cursor = data
                        .get("response_metadata")
                        .and_then(|m| m.get("next_cursor"))
                        .and_then(|v| v.as_str())
                        .filter(|s| !s.is_empty())
                        .map(str::to_string);
                    cursor = next_cursor;
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

        // Deduplicate preserving order
        let mut seen = HashSet::new();
        candidates.retain(|id| seen.insert(id.clone()));

        let mut conversations: Vec<JsonValue> = Vec::new();
        let mut errors: Vec<JsonValue> = Vec::new();

        let patient = |method: &str, params: JsonValue| -> Result<JsonValue, SlackClientError> {
            let mut attempt = 0;
            loop {
                let data = self.api(method, params.clone(), WriteTokenPreference::User, "GET")?;
                let err = data.get("error").and_then(|v| v.as_str()).unwrap_or("");
                if err != "ratelimited" || attempt >= UNREAD_MAX_RETRIES {
                    return Ok(data);
                }
                let seconds = data
                    .get("retry_after")
                    .and_then(|v| v.as_u64())
                    .unwrap_or(1)
                    .min(UNREAD_MAX_WAIT_SECONDS);
                if seconds > 0 {
                    std::thread::sleep(Duration::from_secs(seconds));
                }
                attempt += 1;
            }
        };

        for id in &candidates {
            let info = patient(
                "conversations.info",
                JsonValue::object(vec![("channel", id.as_str().into())]),
            )?;
            let ok = info.get("ok").and_then(|v| v.as_bool()).unwrap_or(false);
            let Some(channel) = info.get("channel").filter(|_| ok) else {
                let err = info
                    .get("error")
                    .and_then(|v| v.as_str())
                    .unwrap_or("unknown_error");
                errors.push(JsonValue::object(vec![
                    ("id", id.as_str().into()),
                    ("error", err.into()),
                ]));
                continue;
            };

            self.channel_guard
                .assert_visibility_matches(id, channel.get("is_private"))?;
            let is_archived = channel
                .get("is_archived")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            let Some(last_read) = channel.get("last_read").and_then(|v| v.as_str()) else {
                continue;
            };
            if is_archived {
                continue;
            }

            let oldest = if last_read.parse::<f64>().ok() == Some(0.0) {
                "0"
            } else {
                last_read
            };
            let history = patient(
                "conversations.history",
                JsonValue::object(vec![
                    ("channel", id.as_str().into()),
                    ("oldest", oldest.into()),
                    ("limit", per_conversation.into()),
                ]),
            )?;
            if history.get("ok").and_then(|v| v.as_bool()) != Some(true) {
                let err = history
                    .get("error")
                    .and_then(|v| v.as_str())
                    .unwrap_or("unknown_error");
                errors.push(JsonValue::object(vec![
                    ("id", id.as_str().into()),
                    ("error", err.into()),
                ]));
                continue;
            }

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
                continue;
            }

            let conv_type = if channel.get("is_im").and_then(|v| v.as_bool()) == Some(true) {
                "im"
            } else if channel.get("is_mpim").and_then(|v| v.as_bool()) == Some(true) {
                "mpim"
            } else if channel.get("is_private").and_then(|v| v.as_bool()) == Some(true) {
                "private_channel"
            } else {
                "public_channel"
            };

            let mut entry = JsonValue::object(vec![("id", id.as_str().into())]);
            if let Some(name) = channel
                .get("name")
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
            {
                entry.insert("name", name.into());
            }
            if let Some(user) = channel
                .get("user")
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
            {
                entry.insert("user", user.into());
            }
            entry.insert("type", conv_type.into());
            entry.insert("unread_count", messages.len().into());
            entry.insert(
                "unread_count_is_minimum",
                history
                    .get("has_more")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false)
                    .into(),
            );
            entry.insert("last_read", last_read.into());
            let latest_ts = messages[0].get("ts").and_then(|v| v.as_str()).unwrap_or("");
            entry.insert("latest_ts", latest_ts.into());
            conversations.push(entry);
        }

        conversations.sort_by(|a, b| {
            let b_ts = b.get("latest_ts").and_then(|v| v.as_str()).unwrap_or("");
            let a_ts = a.get("latest_ts").and_then(|v| v.as_str()).unwrap_or("");
            b_ts.cmp(a_ts)
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

    pub fn list_channel_members(
        &self,
        channel_id: &str,
        limit: Option<usize>,
        cursor: Option<&str>,
    ) -> Result<JsonValue, SlackClientError> {
        let mut params = JsonValue::object(vec![
            ("channel", channel_id.into()),
            ("limit", limit.unwrap_or(100).min(200).into()),
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
        let ok = data.get("ok").and_then(|v| v.as_bool()).unwrap_or(false);
        let Some(emoji_obj) = data.get("emoji").and_then(|v| v.as_object()).filter(|_| ok) else {
            return Ok(data);
        };
        let needle = query.map(|q| q.to_ascii_lowercase());
        let mut filtered = Vec::new();
        for (name, val) in emoji_obj {
            let Some(val_str) = val.as_str() else {
                continue;
            };
            if !include_aliases && val_str.starts_with("alias:") {
                continue;
            }
            if let Some(n) = &needle {
                if !name.to_ascii_lowercase().contains(n.as_str()) {
                    continue;
                }
            }
            filtered.push((name.clone(), JsonValue::String(val_str.to_string())));
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
        let mut params = JsonValue::object(vec![
            ("limit", limit.unwrap_or(100).min(200).into()),
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

    // ── Search ─────────────────────────────────────────────────────────

    pub fn search_messages(
        &self,
        query: &str,
        count: Option<usize>,
        sort: Option<&str>,
    ) -> Result<JsonValue, SlackClientError> {
        self.api(
            "search.messages",
            JsonValue::object(vec![
                ("query", query.into()),
                ("count", count.unwrap_or(20).min(100).into()),
                ("sort", sort.unwrap_or("score").into()),
            ]),
            WriteTokenPreference::User,
            "GET",
        )
    }

    pub fn search_files(
        &self,
        query: &str,
        count: Option<usize>,
        sort: Option<&str>,
    ) -> Result<JsonValue, SlackClientError> {
        self.api(
            "search.files",
            JsonValue::object(vec![
                ("query", query.into()),
                ("count", count.unwrap_or(20).min(100).into()),
                ("sort", sort.unwrap_or("score").into()),
            ]),
            WriteTokenPreference::User,
            "GET",
        )
    }

    // ── Messaging ──────────────────────────────────────────────────────

    pub fn post_message(
        &self,
        channel_id: &str,
        text: &str,
    ) -> Result<JsonValue, SlackClientError> {
        self.api(
            "chat.postMessage",
            JsonValue::object(vec![("channel", channel_id.into()), ("text", text.into())]),
            self.write_token,
            "POST",
        )
    }

    pub fn reply_to_thread(
        &self,
        channel_id: &str,
        thread_ts: &str,
        text: &str,
    ) -> Result<JsonValue, SlackClientError> {
        self.api(
            "chat.postMessage",
            JsonValue::object(vec![
                ("channel", channel_id.into()),
                ("thread_ts", thread_ts.into()),
                ("text", text.into()),
            ]),
            self.write_token,
            "POST",
        )
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
        let ok = data.get("ok").and_then(|v| v.as_bool()).unwrap_or(false);
        let err_str = data.get("error").and_then(|v| v.as_str()).unwrap_or("");
        if !ok && err_str == "file_not_found" && self.user_auth.is_some() {
            token = WriteTokenPreference::User;
            data = self.api(
                "files.info",
                JsonValue::object(vec![("file", file_id.into())]),
                WriteTokenPreference::User,
                "GET",
            )?;
        }
        let ok2 = data.get("ok").and_then(|v| v.as_bool()).unwrap_or(false);
        let Some(file) = data.get("file").filter(|_| ok2).cloned() else {
            let reason = data
                .get("error")
                .and_then(|v| v.as_str())
                .unwrap_or("no file returned");
            return Err(SlackClientError::Message(format!(
                "files.info failed: {reason}"
            )));
        };
        assert_file_share_allowed(&self.channel_guard, &FileShares::from_json(&file))?;
        Ok((file, token))
    }

    fn fetch_file_bytes(
        &self,
        file: &JsonValue,
        token: WriteTokenPreference,
    ) -> Result<Vec<u8>, SlackClientError> {
        let file_id = file.get("id").and_then(|v| v.as_str()).unwrap_or("");
        let Some(url_private) = file.get("url_private").and_then(|v| v.as_str()) else {
            return Err(SlackClientError::Message(format!(
                "File {file_id} has no downloadable content."
            )));
        };
        let auth_header = match token {
            WriteTokenPreference::Bot => Some(self.bot_auth.as_str()),
            WriteTokenPreference::User => self.user_auth.as_deref(),
        };
        let Some(auth) = auth_header else {
            return Err(SlackClientError::UserTokenUnavailable {
                method: "files download".to_string(),
            });
        };
        let res = execute_http(&HttpRequest {
            url: url_private.to_string(),
            method: "GET".to_string(),
            headers: vec![("Authorization".to_string(), auth.to_string())],
            body: None,
        })
        .map_err(SlackClientError::Message)?;
        if !(200..300).contains(&res.status) {
            return Err(SlackClientError::Message(format!(
                "Downloading file {file_id} failed: HTTP {}",
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
        let max_bytes = max_bytes.unwrap_or(DEFAULT_READ_CAP);
        let (file, token) = self.fetch_file_info(file_id)?;
        let id = file.get("id").and_then(|v| v.as_str()).unwrap_or(file_id);
        if !is_text_file(&file) {
            let mime = file
                .get("mimetype")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown type");
            return Err(SlackClientError::Message(format!(
                "File {id} ({mime}) is not a text file. Use slack_download_file to save it locally instead."
            )));
        }
        if let Some(size) = file.get("size").and_then(|v| v.as_u64()) {
            if (size as usize) > max_bytes {
                return Err(SlackClientError::Message(format!(
                    "File {id} is {size} bytes, larger than the {max_bytes} byte cap. Raise max_bytes or use slack_download_file."
                )));
            }
        }
        let bytes = self.fetch_file_bytes(&file, token)?;
        Ok(JsonValue::object(vec![
            ("ok", true.into()),
            ("id", id.into()),
            ("name", file.get("name").cloned().unwrap_or(JsonValue::Null)),
            (
                "title",
                file.get("title").cloned().unwrap_or(JsonValue::Null),
            ),
            (
                "mimetype",
                file.get("mimetype").cloned().unwrap_or(JsonValue::Null),
            ),
            ("size", bytes.len().into()),
            (
                "content",
                String::from_utf8_lossy(&bytes).into_owned().into(),
            ),
        ]))
    }

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

        let bytes = if let Some(content) = &input.content {
            content.as_bytes().to_vec()
        } else {
            base64::decode(input.content_base64.as_deref().unwrap())
                .map_err(SlackClientError::Message)?
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

        let ok = reserve.get("ok").and_then(|v| v.as_bool()).unwrap_or(false);
        let upload_url = reserve.get("upload_url").and_then(|v| v.as_str());
        let file_id = reserve.get("file_id").and_then(|v| v.as_str());
        let (true, Some(upload_url), Some(file_id)) = (ok, upload_url, file_id) else {
            let err = reserve
                .get("error")
                .and_then(|v| v.as_str())
                .unwrap_or("no upload URL");
            return Err(SlackClientError::Message(format!(
                "files.getUploadURLExternal failed: {err}"
            )));
        };

        let put = execute_http(&HttpRequest {
            url: upload_url.to_string(),
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

        let mut file_entry = JsonValue::object(vec![("id", file_id.into())]);
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
        Ok(JsonValue::object(vec![
            ("ok", true.into()),
            ("path", output_path.into()),
            ("bytes", bytes.len().into()),
            ("name", file.get("name").cloned().unwrap_or(JsonValue::Null)),
        ]))
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
    use crate::tools::{all_tools, tools_for, HTTP_WITHHELD_ALWAYS};
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
            all_tools().len() - HTTP_WITHHELD_ALWAYS.len()
        );
        assert!(imp_tools.contains(&"slack_search_messages"));
        assert!(imp_tools.contains(&"slack_create_canvas"));
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
}
