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

//! Reverse-MCP phone bridge (`/v1/phone/link`, `/v1/phone/result`, `/v1/phone`).

use std::collections::HashMap;
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use vitruvian_remote_macagent_metrics::{JsonMap, JsonValue, Timestamp};

use crate::http_util::{agent_log, CancelToken, HttpRequest, HttpResponse, SseSink};

pub const TIER_READ: &str = "read";
pub const TIER_ACT: &str = "act";
pub const TIER_OUTBOUND: &str = "outbound";

pub const PHONE_TOOL_TIMEOUT: Duration = Duration::from_secs(30);
pub const PHONE_OUTBOUND_TIMEOUT: Duration = Duration::from_secs(90);
pub const PHONE_PING_INTERVAL: Duration = Duration::from_secs(20);

#[derive(Debug, Clone, PartialEq, Default)]
pub struct PhoneTool {
    pub name: String,
    pub description: String,
    pub input_schema: JsonValue,
    pub tier: String,
}

impl PhoneTool {
    pub fn from_json(v: &JsonValue) -> Self {
        Self {
            name: v.get_str("name").to_string(),
            description: v.get_str("description").to_string(),
            input_schema: v.get("inputSchema").cloned().unwrap_or(JsonValue::Null),
            tier: v.get_str("tier").to_string(),
        }
    }

    pub fn to_mcp_json(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("name", JsonValue::from_str_val(&self.name));
        m.insert("description", JsonValue::from_str_val(&self.description));
        let schema = if self.input_schema.is_null() {
            let mut sm = JsonMap::new();
            sm.insert("type", JsonValue::from_str_val("object"));
            JsonValue::Object(sm)
        } else {
            self.input_schema.clone()
        };
        m.insert("inputSchema", schema);
        JsonValue::Object(m)
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct PhoneDevice {
    pub model: String,
    pub android: String,
    /// The Vitruvian Remote version on the phone. Empty from phones older than
    /// 0.1.49, which do not send it.
    pub app_version: String,
}

impl PhoneDevice {
    pub fn from_json(v: &JsonValue) -> Self {
        Self {
            model: v.get_str("model").to_string(),
            android: v.get_str("android").to_string(),
            // Bounded and printable: it is the phone's claim, shown in a menu.
            app_version: v
                .get_str("app_version")
                .chars()
                .filter(|c| c.is_ascii_graphic())
                .take(32)
                .collect(),
        }
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        if !self.model.is_empty() {
            m.insert("model", JsonValue::from_str_val(&self.model));
        }
        if !self.android.is_empty() {
            m.insert("android", JsonValue::from_str_val(&self.android));
        }
        if !self.app_version.is_empty() {
            m.insert("app_version", JsonValue::from_str_val(&self.app_version));
        }
        JsonValue::Object(m)
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct PhoneCall {
    pub id: String,
    pub tool: String,
    pub arguments: JsonValue,
}

impl PhoneCall {
    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("id", JsonValue::from_str_val(&self.id));
        m.insert("tool", JsonValue::from_str_val(&self.tool));
        if !self.arguments.is_null() {
            m.insert("arguments", self.arguments.clone());
        }
        JsonValue::Object(m)
    }

    pub fn to_json_string(&self) -> String {
        self.to_json_value().to_json_string()
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct PhoneContentBlock {
    pub kind: String,
    pub text: String,
}

impl PhoneContentBlock {
    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("type", JsonValue::from_str_val(&self.kind));
        m.insert("text", JsonValue::from_str_val(&self.text));
        JsonValue::Object(m)
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct PhoneResult {
    pub id: String,
    pub content: Vec<PhoneContentBlock>,
    pub is_error: bool,
    pub trust_until: Option<Timestamp>,
}

impl PhoneResult {
    pub fn from_json(v: &JsonValue) -> Result<Self, String> {
        let obj = v
            .as_object()
            .ok_or_else(|| "invalid JSON object".to_string())?;
        let id = obj.get_str("id").to_string();
        let is_error = obj.get_bool("is_error");
        let mut content = Vec::new();
        if let Some(arr) = obj.get("content").and_then(|c| c.as_array()) {
            for item in arr {
                content.push(PhoneContentBlock {
                    kind: item.get_str("type").to_string(),
                    text: item.get_str("text").to_string(),
                });
            }
        }
        let trust_until = obj
            .get("trust_until")
            .and_then(|t| t.as_str())
            .and_then(|s| Timestamp::parse_rfc3339(s).ok());
        Ok(Self {
            id,
            content,
            is_error,
            trust_until,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct PhoneStatus {
    pub connected: bool,
    pub device: Option<PhoneDevice>,
    pub since: Option<Timestamp>,
    pub trust_until: Option<Timestamp>,
    pub tools: Vec<String>,
}

impl PhoneStatus {
    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("connected", JsonValue::from_bool(self.connected));
        if let Some(dev) = &self.device {
            m.insert("device", dev.to_json_value());
        }
        match &self.since {
            Some(ts) => m.insert("since", JsonValue::from_str_val(ts.to_rfc3339())),
            None => m.insert("since", JsonValue::Null),
        }
        match &self.trust_until {
            Some(ts) => m.insert("trust_until", JsonValue::from_str_val(ts.to_rfc3339())),
            None => m.insert("trust_until", JsonValue::Null),
        }
        m.insert(
            "tools",
            JsonValue::Array(
                self.tools
                    .iter()
                    .map(|t| JsonValue::from_str_val(t))
                    .collect(),
            ),
        );
        JsonValue::Object(m)
    }
}

struct PhoneLinkState {
    id: u64,
    tx: Sender<PhoneCall>,
    cancel: CancelToken,
    device: PhoneDevice,
    since: Timestamp,
}

#[derive(Default)]
struct BridgeInner {
    next_link_id: u64,
    link: Option<PhoneLinkState>,
    tools: Vec<PhoneTool>,
    trust_until: Option<Timestamp>,
    seq: u64,
    inflight: HashMap<String, Sender<PhoneResult>>,
}

pub struct PhoneBridge {
    inner: Mutex<BridgeInner>,
}

impl Default for PhoneBridge {
    fn default() -> Self {
        Self::new()
    }
}

impl PhoneBridge {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(BridgeInner::default()),
        }
    }

    pub fn set_tools_for_test(&self, tools: Vec<PhoneTool>) {
        if let Ok(mut g) = self.inner.lock() {
            g.tools = tools;
        }
    }

    pub fn connected(&self) -> bool {
        self.status().connected
    }

    pub fn dispatch(
        &self,
        tool: &str,
        args: JsonValue,
        timeout: Duration,
    ) -> Result<PhoneResult, String> {
        self.call(tool, args, timeout)
    }

    pub fn status(&self) -> PhoneStatus {
        let Ok(g) = self.inner.lock() else {
            return PhoneStatus::default();
        };
        let Some(link) = &g.link else {
            return PhoneStatus {
                connected: false,
                device: None,
                since: None,
                trust_until: None,
                tools: Vec::new(),
            };
        };
        let names = g.tools.iter().map(|t| t.name.clone()).collect();
        PhoneStatus {
            connected: true,
            device: Some(link.device.clone()),
            since: Some(link.since),
            trust_until: g.trust_until,
            tools: names,
        }
    }

    pub fn tools_list(&self) -> Vec<PhoneTool> {
        let Ok(g) = self.inner.lock() else {
            return Vec::new();
        };
        if g.link.is_none() {
            return Vec::new();
        }
        g.tools.clone()
    }

    pub fn tier_of(&self, tool: &str) -> String {
        let Ok(g) = self.inner.lock() else {
            return String::new();
        };
        for t in &g.tools {
            if t.name == tool {
                return t.tier.clone();
            }
        }
        String::new()
    }

    pub fn call(
        &self,
        tool: &str,
        args: JsonValue,
        timeout: Duration,
    ) -> Result<PhoneResult, String> {
        let (id, rx) = {
            let Ok(mut g) = self.inner.lock() else {
                return Err("phone not connected".to_string());
            };
            let Some(link_tx) = g.link.as_ref().map(|l| l.tx.clone()) else {
                return Err("phone not connected".to_string());
            };
            g.seq += 1;
            let id = format!("c-{}", g.seq);
            let (res_tx, res_rx) = mpsc::channel();
            let call = PhoneCall {
                id: id.clone(),
                tool: tool.to_string(),
                arguments: args,
            };
            if link_tx.send(call).is_err() {
                return Err("phone link is busy".to_string());
            }
            g.inflight.insert(id.clone(), res_tx);
            (id, res_rx)
        };

        let result = match rx.recv_timeout(timeout) {
            Ok(res) => {
                if tool == "phone.status" && !res.is_error {
                    if let Some(t) = read_trust_until(&res) {
                        if let Ok(mut g) = self.inner.lock() {
                            g.trust_until = Some(t);
                        }
                    }
                }
                Ok(res)
            }
            Err(_) => {
                if let Ok(mut g) = self.inner.lock() {
                    g.inflight.remove(&id);
                }
                Err("phone did not answer before timeout".to_string())
            }
        };
        result
    }

    pub fn deliver(&self, res: PhoneResult) -> bool {
        let tx_opt = {
            let Ok(mut g) = self.inner.lock() else {
                return false;
            };
            if let Some(tu) = res.trust_until {
                g.trust_until = Some(tu);
            }
            g.inflight.remove(&res.id)
        };
        if let Some(tx) = tx_opt {
            let _ = tx.send(res);
            true
        } else {
            false
        }
    }

    fn install(
        &self,
        dev: PhoneDevice,
        tools: Vec<PhoneTool>,
        cancel: CancelToken,
    ) -> (u64, Receiver<PhoneCall>) {
        let mut g = self.inner.lock().unwrap();
        if let Some(old) = g.link.take() {
            old.cancel.cancel();
            for (_, tx) in g.inflight.drain() {
                let _ = tx.send(tool_error_result("phone reconnected"));
            }
        }
        g.next_link_id += 1;
        let link_id = g.next_link_id;
        let (tx, rx) = mpsc::channel();
        g.link = Some(PhoneLinkState {
            id: link_id,
            tx,
            cancel,
            device: dev,
            since: Timestamp::now(),
        });
        g.tools = tools;
        g.trust_until = None;
        (link_id, rx)
    }

    /// Drops the link if it is still the current one. Returns false when a
    /// newer link already replaced it, so the caller can say why it ended.
    fn unlink(&self, link_id: u64) -> bool {
        let mut g = self.inner.lock().unwrap();
        if g.link.as_ref().map(|l| l.id) != Some(link_id) {
            return false;
        }
        g.link = None;
        g.tools.clear();
        g.trust_until = None;
        for (_, tx) in g.inflight.drain() {
            let _ = tx.send(tool_error_result("phone not connected"));
        }
        true
    }

    /// Test-only: link a fake phone in-process. Every call is answered by
    /// `answer` (text, is_error) on a background thread.
    #[cfg(test)]
    pub fn attach_fake_phone_for_test<F>(self: &Arc<Self>, answer: F) -> u64
    where
        F: Fn(&PhoneCall) -> (String, bool) + Send + 'static,
    {
        let (link_id, rx) = self.install(PhoneDevice::default(), Vec::new(), CancelToken::new());
        let bridge = Arc::clone(self);
        std::thread::spawn(move || {
            for call in rx {
                let (text, is_error) = answer(&call);
                bridge.deliver(PhoneResult {
                    id: call.id.clone(),
                    content: vec![PhoneContentBlock {
                        kind: "text".to_string(),
                        text,
                    }],
                    is_error,
                    trust_until: None,
                });
            }
        });
        link_id
    }

    /// Test-only: a linked phone whose stream is already gone, so sending it
    /// a call fails at once.
    #[cfg(test)]
    pub fn attach_dead_phone_for_test(self: &Arc<Self>) -> u64 {
        let (link_id, rx) = self.install(PhoneDevice::default(), Vec::new(), CancelToken::new());
        drop(rx);
        link_id
    }
}

/// Why a phone link ended. Logged so a dropped link can be explained later.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LinkEnd {
    /// The phone closed the connection (or the network dropped it).
    StreamEnded,
    /// A newer link from the phone took this one's place.
    Replaced,
    /// Sending a call or the hello to the phone failed.
    WriteError,
    /// The keep-alive ping could not be written.
    PingFailure,
}

impl LinkEnd {
    pub fn as_str(&self) -> &'static str {
        match self {
            LinkEnd::StreamEnded => "stream ended",
            LinkEnd::Replaced => "replaced by a new link",
            LinkEnd::WriteError => "write error",
            LinkEnd::PingFailure => "ping failure",
        }
    }
}

/// The current time in UTC to the second, e.g. `2026-11-18T16:50:03Z`.
/// Log lines that need a time start with it.
pub fn utc_stamp() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    Timestamp::from_unix_secs(secs).to_rfc3339()
}

/// A link's lifetime for the log: `45s`, `12m05s`, `3h02m09s`.
pub fn format_link_duration(d: Duration) -> String {
    let total = d.as_secs();
    let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60);
    if h > 0 {
        format!("{h}h{m:02}m{s:02}s")
    } else if m > 0 {
        format!("{m}m{s:02}s")
    } else {
        format!("{s}s")
    }
}

/// Feeds calls and keep-alive pings to one linked phone until the link ends,
/// and says how it ended. Split out of `handle_phone_link` so the ping
/// interval can be shortened in tests.
fn serve_link(
    sink: &mut dyn SseSink,
    cancel: &CancelToken,
    rx: &Receiver<PhoneCall>,
    ping_interval: Duration,
) -> LinkEnd {
    if sink.write_event("hello", "{}").is_err() {
        return LinkEnd::WriteError;
    }
    let mut last_ping = Instant::now();
    loop {
        if cancel.is_cancelled() {
            return LinkEnd::StreamEnded;
        }
        match rx.recv_timeout(Duration::from_millis(25)) {
            Ok(call) => {
                if sink.write_event("call", &call.to_json_string()).is_err() {
                    return LinkEnd::WriteError;
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {
                if last_ping.elapsed() >= ping_interval {
                    last_ping = Instant::now();
                    if sink.write_event("ping", "{}").is_err() {
                        return LinkEnd::PingFailure;
                    }
                }
            }
            // The sender lives in the bridge's link slot; it is dropped only
            // when another link replaces this one.
            Err(mpsc::RecvTimeoutError::Disconnected) => return LinkEnd::Replaced,
        }
    }
}

/// Runs one link from install to close, logging when it opened, when it
/// closed, why, and how long it lasted.
fn run_link(
    bridge: &PhoneBridge,
    device: PhoneDevice,
    tools: Vec<PhoneTool>,
    sink: &mut dyn SseSink,
    cancel: CancelToken,
    ping_interval: Duration,
) -> LinkEnd {
    // The phone names itself; cap it so a long name cannot flood the log.
    let model: String = device.model.chars().take(64).collect();
    let tool_count = tools.len();
    let (link_id, rx) = bridge.install(device, tools, cancel.clone());
    let opened = Instant::now();
    agent_log(&format!(
        "{} phone link: open id={} model={:?} tools={}",
        utc_stamp(),
        link_id,
        model,
        tool_count
    ));
    let mut end = serve_link(sink, &cancel, &rx, ping_interval);
    // A replaced link is cancelled by its successor, which looks like the
    // stream ending from inside the loop. The bridge knows which it was.
    if !bridge.unlink(link_id) {
        end = LinkEnd::Replaced;
    }
    agent_log(&format!(
        "{} phone link: closed id={} reason={} lasted={}",
        utc_stamp(),
        link_id,
        end.as_str(),
        format_link_duration(opened.elapsed())
    ));
    end
}

fn tool_error_result(msg: &str) -> PhoneResult {
    PhoneResult {
        id: String::new(),
        is_error: true,
        content: vec![PhoneContentBlock {
            kind: "text".to_string(),
            text: msg.to_string(),
        }],
        trust_until: None,
    }
}

pub fn valid_tool_name(s: &str) -> bool {
    if s.is_empty() || s.len() > 64 {
        return false;
    }
    let bytes = s.as_bytes();
    if !bytes[0].is_ascii_lowercase() {
        return false;
    }
    bytes[1..]
        .iter()
        .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || *b == b'.' || *b == b'_')
}

pub fn valid_tier(t: &str) -> bool {
    matches!(t, TIER_READ | TIER_ACT | TIER_OUTBOUND)
}

pub fn phone_call_timeout(tier: &str) -> Duration {
    if tier == TIER_OUTBOUND {
        PHONE_OUTBOUND_TIMEOUT
    } else {
        PHONE_TOOL_TIMEOUT
    }
}

pub fn read_trust_until(res: &PhoneResult) -> Option<Timestamp> {
    for c in &res.content {
        if let Ok(v) = JsonValue::parse(&c.text) {
            let s = v.get_str("trust_until");
            if !s.is_empty() {
                if let Ok(ts) = Timestamp::parse_rfc3339(s) {
                    return Some(ts);
                }
            }
        }
    }
    None
}

pub fn handle_phone_link(bridge: Arc<PhoneBridge>, req: &HttpRequest) -> HttpResponse {
    if req.method != "POST" {
        return HttpResponse::json_error(405, "POST only");
    }
    let Ok(body) = JsonValue::parse(&req.body_str()) else {
        return HttpResponse::json_error(400, "invalid JSON");
    };
    let device = body
        .get("device")
        .map(PhoneDevice::from_json)
        .unwrap_or_default();
    let mut tools = Vec::new();
    if let Some(arr) = body.get("tools").and_then(|v| v.as_array()) {
        for item in arr {
            let t = PhoneTool::from_json(item);
            if !valid_tool_name(&t.name) {
                return HttpResponse::json_error(400, &format!("invalid tool name {:?}", t.name));
            }
            if !valid_tier(&t.tier) {
                return HttpResponse::json_error(
                    400,
                    &format!("tool {:?}: tier must be read, act or outbound", t.name),
                );
            }
            tools.push(t);
        }
    }

    HttpResponse::sse(move |sink: &mut dyn SseSink, cancel: CancelToken| {
        run_link(&bridge, device, tools, sink, cancel, PHONE_PING_INTERVAL);
    })
}

pub fn handle_phone_result(bridge: &PhoneBridge, req: &HttpRequest) -> HttpResponse {
    if req.method != "POST" {
        return HttpResponse::json_error(405, "POST only");
    }
    let Ok(val) = JsonValue::parse(&req.body_str()) else {
        return HttpResponse::json_error(400, "invalid JSON");
    };
    let Ok(res) = PhoneResult::from_json(&val) else {
        return HttpResponse::json_error(400, "invalid JSON");
    };
    if res.id.is_empty() {
        return HttpResponse::json_error(400, "id is empty");
    }
    if !bridge.deliver(res) {
        return HttpResponse::json_error(404, "no call waiting for that id");
    }
    HttpResponse::json(200, &JsonValue::empty_object())
}

pub fn first_text_content(res: &PhoneResult) -> String {
    for c in &res.content {
        if (c.kind.is_empty() || c.kind == "text") && !c.text.trim().is_empty() {
            return c.text.trim().to_string();
        }
    }
    String::new()
}

impl PhoneBridge {
    pub fn handle_link(self: &Arc<Self>, req: &HttpRequest) -> HttpResponse {
        handle_phone_link(Arc::clone(self), req)
    }

    pub fn handle_result(&self, req: &HttpRequest) -> HttpResponse {
        handle_phone_result(self, req)
    }

    pub fn handle_status(&self) -> HttpResponse {
        HttpResponse::json(200, &self.status().to_json_value())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::http_util::LogCapture;

    /// An SSE sink that fails the first write of `fail_on`.
    struct FailingSink {
        fail_on: &'static str,
        events: Vec<String>,
    }

    impl SseSink for FailingSink {
        fn write_event(&mut self, event: &str, _data: &str) -> std::io::Result<()> {
            if event == self.fail_on {
                return Err(std::io::Error::new(std::io::ErrorKind::BrokenPipe, "gone"));
            }
            self.events.push(event.to_string());
            Ok(())
        }
    }

    fn sink(fail_on: &'static str) -> FailingSink {
        FailingSink {
            fail_on,
            events: Vec::new(),
        }
    }

    fn device(model: &str) -> PhoneDevice {
        PhoneDevice {
            model: model.to_string(),
            android: "16".to_string(),
            app_version: String::new(),
        }
    }

    #[test]
    fn device_keeps_the_phone_app_version_and_reports_it() {
        let v = JsonValue::parse(r#"{"model":"Pixel Fold","android":"16","app_version":"0.1.47"}"#)
            .unwrap();
        let dev = PhoneDevice::from_json(&v);
        assert_eq!(dev.app_version, "0.1.47");
        let out = dev.to_json_value();
        assert_eq!(out.get_str("app_version"), "0.1.47");
    }

    #[test]
    fn device_from_an_older_phone_has_no_app_version_field() {
        let v = JsonValue::parse(r#"{"model":"Pixel","android":"15"}"#).unwrap();
        let dev = PhoneDevice::from_json(&v);
        assert_eq!(dev.app_version, "");
        assert!(dev.to_json_value().get("app_version").is_none());
    }

    #[test]
    fn device_app_version_is_bounded_and_printable() {
        let long = format!("0.1.47\n{}", "9".repeat(100));
        let v = JsonValue::parse(&format!(
            r#"{{"model":"Pixel","android":"15","app_version":{:?}}}"#,
            long
        ))
        .unwrap();
        let dev = PhoneDevice::from_json(&v);
        assert_eq!(dev.app_version.len(), 32);
        assert!(dev.app_version.starts_with("0.1.479"));
    }

    /// `2026-11-18T16:50:03Z` and nothing longer: the stamp is to the second.
    fn is_utc_stamp(s: &str) -> bool {
        let b = s.as_bytes();
        s.len() == 20
            && b[4] == b'-'
            && b[7] == b'-'
            && b[10] == b'T'
            && b[13] == b':'
            && b[16] == b':'
            && b[19] == b'Z'
            && s.chars()
                .enumerate()
                .all(|(i, c)| [4, 7, 10, 13, 16, 19].contains(&i) || c.is_ascii_digit())
    }

    fn line_with<'a>(log: &'a str, needle: &str) -> &'a str {
        log.lines()
            .find(|l| l.contains(needle))
            .unwrap_or_else(|| panic!("no log line containing {needle:?} in:\n{log}"))
    }

    #[test]
    fn format_link_duration_reads_as_hours_minutes_seconds() {
        assert_eq!(format_link_duration(Duration::from_secs(0)), "0s");
        assert_eq!(format_link_duration(Duration::from_secs(45)), "45s");
        assert_eq!(format_link_duration(Duration::from_secs(725)), "12m05s");
        assert_eq!(
            format_link_duration(Duration::from_secs(3 * 3600 + 129)),
            "3h02m09s"
        );
    }

    #[test]
    fn utc_stamp_is_rfc3339_to_the_second() {
        let s = utc_stamp();
        assert!(is_utc_stamp(&s), "{s}");
    }

    #[test]
    fn a_link_the_phone_hangs_up_logs_open_and_close_with_time_and_reason() {
        let capture = LogCapture::start();
        let bridge = PhoneBridge::new();
        let cancel = CancelToken::new();
        cancel.cancel(); // the phone has already gone
        let end = run_link(
            &bridge,
            device("Pixel Fold"),
            Vec::new(),
            &mut sink("none"),
            cancel,
            PHONE_PING_INTERVAL,
        );
        assert_eq!(end, LinkEnd::StreamEnded);
        assert!(!bridge.connected());

        let log = capture.contents();
        let open = line_with(&log, "phone link: open");
        assert!(is_utc_stamp(&open[..20]), "{open}");
        assert!(
            open.ends_with(r#"phone link: open id=1 model="Pixel Fold" tools=0"#),
            "{open}"
        );
        let closed = line_with(&log, "phone link: closed");
        assert!(is_utc_stamp(&closed[..20]), "{closed}");
        assert!(
            closed.ends_with("phone link: closed id=1 reason=stream ended lasted=0s"),
            "{closed}"
        );
    }

    #[test]
    fn a_failed_ping_closes_the_link_and_says_so() {
        let capture = LogCapture::start();
        let bridge = PhoneBridge::new();
        let end = run_link(
            &bridge,
            device("Pixel"),
            Vec::new(),
            &mut sink("ping"),
            CancelToken::new(),
            Duration::from_millis(1),
        );
        assert_eq!(end, LinkEnd::PingFailure);
        assert!(!bridge.connected());
        assert!(
            line_with(&capture.contents(), "phone link: closed").contains("reason=ping failure")
        );
    }

    #[test]
    fn a_failed_call_write_closes_the_link_and_says_so() {
        let capture = LogCapture::start();
        let bridge = Arc::new(PhoneBridge::new());
        let b = Arc::clone(&bridge);
        let caller = std::thread::spawn(move || {
            // Wait for the link, then send it a call it cannot deliver.
            for _ in 0..200 {
                if b.connected() {
                    break;
                }
                std::thread::sleep(Duration::from_millis(5));
            }
            b.call("phone.speak", JsonValue::Null, Duration::from_secs(2))
        });
        let end = run_link(
            &bridge,
            device("Pixel"),
            Vec::new(),
            &mut sink("call"),
            CancelToken::new(),
            PHONE_PING_INTERVAL,
        );
        assert_eq!(end, LinkEnd::WriteError);
        let res = caller.join().unwrap().unwrap();
        assert!(
            res.is_error,
            "the waiting call is failed, not left to time out"
        );
        assert!(line_with(&capture.contents(), "phone link: closed").contains("reason=write error"));
    }

    #[test]
    fn a_link_replaced_by_a_newer_one_says_it_was_replaced() {
        let capture = LogCapture::start();
        let bridge = Arc::new(PhoneBridge::new());
        let b = Arc::clone(&bridge);
        let old = std::thread::spawn(move || {
            let mut s = sink("none");
            let log = LogCapture::start();
            let end = run_link(
                &b,
                device("old"),
                Vec::new(),
                &mut s,
                CancelToken::new(),
                PHONE_PING_INTERVAL,
            );
            (end, log.contents())
        });
        for _ in 0..200 {
            if bridge.connected() {
                break;
            }
            std::thread::sleep(Duration::from_millis(5));
        }
        // The phone reconnects: a new link takes the slot.
        let (_new_id, _rx) = bridge.install(device("new"), Vec::new(), CancelToken::new());
        let (end, old_log) = old.join().unwrap();
        assert_eq!(end, LinkEnd::Replaced);
        assert!(
            line_with(&old_log, "phone link: closed id=1")
                .contains("reason=replaced by a new link"),
            "{old_log}"
        );
        assert!(bridge.connected(), "the new link stays up");
        drop(capture);
    }
}
