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
}

impl PhoneDevice {
    pub fn from_json(v: &JsonValue) -> Self {
        Self {
            model: v.get_str("model").to_string(),
            android: v.get_str("android").to_string(),
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

    fn unlink(&self, link_id: u64) {
        let mut g = self.inner.lock().unwrap();
        if g.link.as_ref().map(|l| l.id) != Some(link_id) {
            return;
        }
        g.link = None;
        g.tools.clear();
        g.trust_until = None;
        for (_, tx) in g.inflight.drain() {
            let _ = tx.send(tool_error_result("phone not connected"));
        }
    }
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

    agent_log(&format!(
        "phone link: model={:?} tools={}",
        device.model,
        tools.len()
    ));

    HttpResponse::sse(move |sink: &mut dyn SseSink, cancel: CancelToken| {
        let (link_id, rx) = bridge.install(device, tools, cancel.clone());
        if sink.write_event("hello", "{}").is_err() {
            bridge.unlink(link_id);
            return;
        }
        let mut last_ping = Instant::now();
        loop {
            if cancel.is_cancelled() {
                break;
            }
            match rx.recv_timeout(Duration::from_millis(25)) {
                Ok(call) => {
                    if sink.write_event("call", &call.to_json_string()).is_err() {
                        break;
                    }
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    if last_ping.elapsed() >= PHONE_PING_INTERVAL {
                        last_ping = Instant::now();
                        if sink.write_event("ping", "{}").is_err() {
                            break;
                        }
                    }
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
            }
        }
        bridge.unlink(link_id);
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
