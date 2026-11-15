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

//! Streamable-HTTP MCP server (`POST /mcp/phone`) for local coding agents.

use std::net::IpAddr;

use vitruvian_remote_macagent_metrics::{JsonMap, JsonValue};

use crate::http_util::{agent_log, HttpRequest, HttpResponse};
use crate::pair::Store;
use crate::phone::{phone_call_timeout, PhoneBridge, PhoneContentBlock};
use crate::server::VERSION;

pub const MCP_PROTOCOL_VERSION: &str = "2025-03-26";
pub const MCP_SERVER_NAME: &str = "vitruvian-phone";

pub const RPC_PARSE_ERROR: i32 = -32700;
pub const RPC_INVALID_REQUEST: i32 = -32600;
pub const RPC_METHOD_NOT_FOUND: i32 = -32601;
pub const RPC_INVALID_PARAMS: i32 = -32602;

pub fn handle_mcp_phone(store: &Store, phone: &PhoneBridge, req: &HttpRequest) -> HttpResponse {
    if !is_loopback(&req.remote_addr) {
        return HttpResponse::json_error(403, "MCP endpoint is loopback-only");
    }
    let tok = req
        .header("Authorization")
        .strip_prefix("Bearer ")
        .unwrap_or("")
        .trim();
    if !store.authorize_mcp(tok) {
        let mut resp = HttpResponse::json_error(
            401,
            "missing or invalid MCP token (see ~/.config/vitruvian-remote/mcp-token)",
        );
        resp.set_header("WWW-Authenticate", r#"Bearer realm="vitruvian-remote-mcp""#);
        return resp;
    }
    if req.method != "POST" {
        let mut resp = HttpResponse::json_error(405, "POST only");
        resp.set_header("Allow", "POST");
        return resp;
    }

    let Ok(rpc_req) = JsonValue::parse(&req.body_str()) else {
        return write_rpc_error(JsonValue::Null, RPC_PARSE_ERROR, "invalid JSON");
    };
    let Some(obj) = rpc_req.as_object() else {
        return write_rpc_error(
            JsonValue::Null,
            RPC_INVALID_REQUEST,
            "expected JSON-RPC 2.0",
        );
    };
    let id_opt = obj.get("id").cloned();
    if obj.get_str("jsonrpc") != "2.0" {
        return write_rpc_error(
            id_opt.unwrap_or(JsonValue::Null),
            RPC_INVALID_REQUEST,
            "expected JSON-RPC 2.0",
        );
    }

    // Notifications have no `id` and expect `202 Accepted` with empty body.
    let Some(id) = id_opt else {
        return HttpResponse::new(202, Vec::new());
    };

    match obj.get_str("method") {
        "initialize" => {
            let mut tools_cap = JsonMap::new();
            tools_cap.insert("listChanged", JsonValue::from_bool(false));
            let mut caps = JsonMap::new();
            caps.insert("tools", JsonValue::Object(tools_cap));

            let mut srv_info = JsonMap::new();
            srv_info.insert("name", JsonValue::from_str_val(MCP_SERVER_NAME));
            srv_info.insert("version", JsonValue::from_str_val(VERSION));

            let mut res = JsonMap::new();
            res.insert(
                "protocolVersion",
                JsonValue::from_str_val(MCP_PROTOCOL_VERSION),
            );
            res.insert("capabilities", JsonValue::Object(caps));
            res.insert("serverInfo", JsonValue::Object(srv_info));
            write_rpc_result(id, JsonValue::Object(res))
        }
        "ping" => write_rpc_result(id, JsonValue::empty_object()),
        "tools/list" => {
            let tools: Vec<JsonValue> = phone
                .tools_list()
                .into_iter()
                .map(|t| t.to_mcp_json())
                .collect();
            let mut res = JsonMap::new();
            res.insert("tools", JsonValue::Array(tools));
            write_rpc_result(id, JsonValue::Object(res))
        }
        "tools/call" => {
            let Some(params) = obj.get("params").and_then(|p| p.as_object()) else {
                return write_rpc_error(id, RPC_INVALID_PARAMS, "invalid params");
            };
            let name = params.get_str("name");
            if name.is_empty() {
                return write_rpc_error(id, RPC_INVALID_PARAMS, "invalid params");
            }
            let args = params.get("arguments").cloned().unwrap_or(JsonValue::Null);

            agent_log(&format!("act mcp: {}", name));

            let timeout = phone_call_timeout(&phone.tier_of(name));
            match phone.call(name, args, timeout) {
                Ok(res) => {
                    let content = if res.content.is_empty() {
                        vec![PhoneContentBlock {
                            kind: "text".to_string(),
                            text: String::new(),
                        }]
                    } else {
                        res.content
                    };
                    let mut out = JsonMap::new();
                    out.insert(
                        "content",
                        JsonValue::Array(content.iter().map(|c| c.to_json_value()).collect()),
                    );
                    out.insert("isError", JsonValue::from_bool(res.is_error));
                    write_rpc_result(id, JsonValue::Object(out))
                }
                Err(err_msg) => {
                    let block = PhoneContentBlock {
                        kind: "text".to_string(),
                        text: err_msg,
                    };
                    let mut out = JsonMap::new();
                    out.insert("content", JsonValue::Array(vec![block.to_json_value()]));
                    out.insert("isError", JsonValue::from_bool(true));
                    write_rpc_result(id, JsonValue::Object(out))
                }
            }
        }
        other => write_rpc_error(
            id,
            RPC_METHOD_NOT_FOUND,
            &format!("unknown method {:?}", other),
        ),
    }
}

fn write_rpc_result(id: JsonValue, result: JsonValue) -> HttpResponse {
    let mut m = JsonMap::new();
    m.insert("jsonrpc", JsonValue::from_str_val("2.0"));
    m.insert("id", id);
    m.insert("result", result);
    HttpResponse::json(200, &JsonValue::Object(m))
}

fn write_rpc_error(id: JsonValue, code: i32, message: &str) -> HttpResponse {
    let mut err_obj = JsonMap::new();
    err_obj.insert("code", JsonValue::from_i32(code));
    err_obj.insert("message", JsonValue::from_str_val(message));
    let mut m = JsonMap::new();
    m.insert("jsonrpc", JsonValue::from_str_val("2.0"));
    m.insert("id", id);
    m.insert("error", JsonValue::Object(err_obj));
    HttpResponse::json(200, &JsonValue::Object(m))
}

pub fn is_loopback(remote_addr: &str) -> bool {
    let host = split_host_from_addr(remote_addr);
    let Ok(ip) = host.parse::<IpAddr>() else {
        return false;
    };
    ip.is_loopback()
}

pub fn is_loopback_host(host_port: &str) -> bool {
    let host = split_host_from_addr(host_port.trim());
    let host = host.trim_start_matches('[').trim_end_matches(']');
    if host.eq_ignore_ascii_case("localhost") {
        return true;
    }
    host.parse::<IpAddr>().map_or(false, |ip| ip.is_loopback())
}

pub fn loopback_gate<F>(
    req: &HttpRequest,
    auth_ok: F,
    realm: &str,
    non_loopback_msg: &str,
    unauth_msg: &str,
) -> Result<(), HttpResponse>
where
    F: FnOnce(&str) -> bool,
{
    if !is_loopback(&req.remote_addr) {
        return Err(HttpResponse::json_error(403, non_loopback_msg));
    }
    let tok = req
        .header("Authorization")
        .strip_prefix("Bearer ")
        .unwrap_or("")
        .trim();
    if !auth_ok(tok) {
        let mut resp = HttpResponse::json_error(401, unauth_msg);
        resp.set_header("WWW-Authenticate", format!(r#"Bearer realm="{}""#, realm));
        return Err(resp);
    }
    Ok(())
}

pub fn split_host_from_addr(addr: &str) -> &str {
    let addr = addr.trim();
    if let Some(after_bracket) = addr.strip_prefix('[') {
        if let Some((ip_part, _)) = after_bracket.split_once(']') {
            return ip_part;
        }
    }
    if let Some((host, _port)) = addr.rsplit_once(':') {
        if !host.contains(':') {
            return host;
        }
    }
    addr
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use crate::http_util::{
        http_do, http_get, http_open_stream, http_post_json, HttpHandler, LogCapture, TestServer,
    };
    use crate::phone::{
        PhoneCall, PhoneTool, PHONE_OUTBOUND_TIMEOUT, PHONE_TOOL_TIMEOUT, TIER_ACT, TIER_OUTBOUND,
        TIER_READ,
    };
    use crate::sampler::Sampler;
    use crate::server::new_mux;
    use std::io::BufRead;
    use std::net::Shutdown;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::{mpsc, Arc, Mutex};
    use std::thread;
    use std::time::Duration;

    fn temp_dir() -> std::path::PathBuf {
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let id = COUNTER.fetch_add(1, Ordering::Relaxed);
        let d =
            std::env::temp_dir().join(format!("macagent-phone-test-{}-{}", std::process::id(), id));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn new_bridge_agent() -> (Store, TestServer) {
        let s = Sampler::new(Duration::from_secs(1), "", "", Vec::new(), None);
        let store = Store::new(temp_dir());
        store.ensure_token().unwrap();
        store.ensure_mcp_token().unwrap();
        let srv = TestServer::start(new_mux(s, store.clone(), "", ""));
        (store, srv)
    }

    pub struct FakePhone {
        pub ended_rx: mpsc::Receiver<()>,
        ctrl: std::net::TcpStream,
        pub calls: Arc<Mutex<Vec<PhoneCall>>>,
    }

    impl FakePhone {
        pub fn cancel(&self) {
            let _ = self.ctrl.shutdown(Shutdown::Both);
        }

        pub fn calls(&self) -> Vec<PhoneCall> {
            self.calls.lock().unwrap().clone()
        }
    }

    pub fn link_phone<F>(srv_url: &str, token: &str, body: &str, answer: Option<F>) -> FakePhone
    where
        F: Fn(PhoneCall) -> (String, bool) + Send + Sync + 'static,
    {
        let answer_fn: Arc<dyn Fn(PhoneCall) -> (String, bool) + Send + Sync> = match answer {
            Some(f) => Arc::new(f),
            None => Arc::new(|c: PhoneCall| (c.tool, false)),
        };

        let auth = format!("Bearer {}", token);
        let (status, headers, reader, ctrl) = http_open_stream(
            "POST",
            &format!("{}/v1/phone/link", srv_url),
            &[("Authorization", &auth)],
            body.as_bytes(),
        )
        .expect("open /v1/phone/link");
        assert_eq!(status, 200, "link status {}", status);
        let ct = headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case("content-type"))
            .map(|(_, v)| v.as_str())
            .unwrap_or("");
        assert_eq!(ct, "text/event-stream");

        let (hello_tx, hello_rx) = mpsc::channel();
        let (ended_tx, ended_rx) = mpsc::channel();
        let calls = Arc::new(Mutex::new(Vec::new()));
        let calls_clone = Arc::clone(&calls);
        let srv_url_owned = srv_url.to_string();
        let token_owned = token.to_string();

        thread::spawn(move || {
            let mut event = String::new();
            let mut hello_seen = false;
            for line in reader.lines().map_while(Result::ok) {
                if let Some(ev) = line.strip_prefix("event: ") {
                    event = ev.to_string();
                } else if let Some(data) = line.strip_prefix("data: ") {
                    match event.as_str() {
                        "hello" => {
                            if !hello_seen {
                                hello_seen = true;
                                let _ = hello_tx.send(());
                            }
                        }
                        "call" => {
                            let Ok(v) = JsonValue::parse(data) else {
                                break;
                            };
                            let c = PhoneCall {
                                id: v.get_str("id").to_string(),
                                tool: v.get_str("tool").to_string(),
                                arguments: v.get("arguments").cloned().unwrap_or(JsonValue::Null),
                            };
                            calls_clone.lock().unwrap().push(c.clone());
                            let (text, is_err) = answer_fn(c.clone());
                            post_result(&srv_url_owned, &token_owned, &c.id, &text, is_err);
                        }
                        _ => {}
                    }
                } else if line.is_empty() {
                    event.clear();
                }
            }
            let _ = ended_tx.send(());
        });

        hello_rx
            .recv_timeout(Duration::from_secs(5))
            .expect("no hello event within 5s");

        FakePhone {
            ended_rx,
            ctrl,
            calls,
        }
    }

    fn post_result(srv_url: &str, token: &str, id: &str, text: &str, is_err: bool) {
        let mut block = JsonMap::new();
        block.insert("type", JsonValue::from_str_val("text"));
        block.insert("text", JsonValue::from_str_val(text));
        let mut body = JsonMap::new();
        body.insert("id", JsonValue::from_str_val(id));
        body.insert("content", JsonValue::Array(vec![JsonValue::Object(block)]));
        body.insert("is_error", JsonValue::from_bool(is_err));
        let _ = http_post_json(
            &format!("{}/v1/phone/result", srv_url),
            token,
            &JsonValue::Object(body).to_json_string(),
        );
    }

    fn rpc(srv_url: &str, token: &str, body: &str) -> (u16, Option<JsonValue>) {
        let auth = format!("Bearer {}", token);
        let resp = http_do(
            "POST",
            &format!("{}/mcp/phone", srv_url),
            &[("Authorization", &auth)],
            body.as_bytes(),
            None,
        )
        .expect("rpc call");
        if resp.status == 202 {
            return (202, None);
        }
        (resp.status, Some(resp.json().expect("decode rpc json")))
    }

    const TWO_TOOLS: &str = r#"{"device":{"model":"Pixel Fold","android":"16"},"tools":[
      {"name":"sms.list","description":"list texts","inputSchema":{"type":"object"},"tier":"read"},
      {"name":"sms.send","description":"send a text","inputSchema":{"type":"object"},"tier":"outbound"}]}"#;

    #[test]
    fn test_mcp_tool_call_round_trips_through_the_phone() {
        let (store, srv) = new_bridge_agent();
        let tok = store.token().unwrap();
        let mtok = store.ensure_mcp_token().unwrap();

        let p = link_phone(
            &srv.url,
            &tok,
            TWO_TOOLS,
            Some(|c: PhoneCall| {
                if c.tool != "sms.list" {
                    return (format!("unexpected tool {}", c.tool), true);
                }
                (format!("args={}", c.arguments.to_json_string()), false)
            }),
        );

        let logs = LogCapture::start();
        let (status, out_opt) = rpc(
            &srv.url,
            &mtok,
            r#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"sms.list","arguments":{"n":5}}}"#,
        );
        assert_eq!(status, 200);
        let out = out_opt.unwrap();
        let res = out.get("result").expect("result in rpc response");
        assert_eq!(res.get_bool("isError"), false);
        let content_str = res.get("content").unwrap().to_json_string();
        assert!(
            content_str.contains(r#"args={\"n\":5}"#),
            "content: {}",
            content_str
        );

        let logged = logs.contents();
        assert!(logged.contains("act mcp: sms.list"), "logged: {}", logged);
        assert!(
            !logged.contains(r#""n":5"#),
            "args leaked in log: {}",
            logged
        );

        let calls = p.calls();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].id, "c-1");
    }

    #[test]
    fn test_phone_status_reflects_the_link() {
        let (store, srv) = new_bridge_agent();
        let tok = store.token().unwrap();

        let before = http_get(&format!("{}/v1/phone", srv.url))
            .unwrap()
            .json()
            .unwrap();
        assert_eq!(before.get_bool("connected"), false);

        let _p = link_phone::<fn(PhoneCall) -> (String, bool)>(&srv.url, &tok, TWO_TOOLS, None);
        let after = http_get(&format!("{}/v1/phone", srv.url))
            .unwrap()
            .json()
            .unwrap();
        assert_eq!(after.get_bool("connected"), true);
        assert_eq!(
            after.get("tools").unwrap().to_json_string(),
            r#"["sms.list","sms.send"]"#
        );
        assert!(!after.get("since").unwrap().is_null());
        assert!(after.get("trust_until").unwrap().is_null());
    }

    #[test]
    fn test_trust_until_comes_from_the_phone() {
        let (store, srv) = new_bridge_agent();
        let tok = store.token().unwrap();
        let mtok = store.ensure_mcp_token().unwrap();

        let want = "2026-09-08T12:00:00Z";
        let _p = link_phone(
            &srv.url,
            &tok,
            r#"{"device":{"model":"Pixel Fold"},"tools":[{"name":"phone.status","description":"status","tier":"read"}]}"#,
            Some(move |_c: PhoneCall| {
                (
                    format!(r#"{{"battery":81,"trust_until":"{}"}}"#, want),
                    false,
                )
            }),
        );

        let (_, out) = rpc(
            &srv.url,
            &mtok,
            r#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"phone.status"}}"#,
        );
        assert!(out.unwrap().get("result").is_some());

        let st = http_get(&format!("{}/v1/phone", srv.url))
            .unwrap()
            .json()
            .unwrap();
        assert_eq!(st.get_str("trust_until"), want);
    }

    #[test]
    fn test_a_second_link_replaces_the_first() {
        let (store, srv) = new_bridge_agent();
        let tok = store.token().unwrap();

        let first = link_phone::<fn(PhoneCall) -> (String, bool)>(&srv.url, &tok, TWO_TOOLS, None);
        let second = link_phone::<fn(PhoneCall) -> (String, bool)>(
            &srv.url,
            &tok,
            r#"{"device":{"model":"Pixel 9"},"tools":[{"name":"contacts.search","description":"search","tier":"read"}]}"#,
            None,
        );

        first
            .ended_rx
            .recv_timeout(Duration::from_secs(5))
            .expect("the first link was still open after a second one arrived");

        let st = http_get(&format!("{}/v1/phone", srv.url))
            .unwrap()
            .json()
            .unwrap();
        assert_eq!(st.get_bool("connected"), true);
        assert_eq!(
            st.get("tools").unwrap().to_json_string(),
            r#"["contacts.search"]"#
        );
        assert!(second.ended_rx.try_recv().is_err(), "second link ended too");
    }

    #[test]
    fn test_result_for_an_unknown_id_is_404() {
        let (store, srv) = new_bridge_agent();
        let tok = store.token().unwrap();
        let _p = link_phone::<fn(PhoneCall) -> (String, bool)>(&srv.url, &tok, TWO_TOOLS, None);

        let resp = http_post_json(
            &format!("{}/v1/phone/result", srv.url),
            &tok,
            r#"{"id":"c-999","content":[{"type":"text","text":"hi"}],"is_error":false}"#,
        )
        .unwrap();
        assert_eq!(resp.status, 404);
    }

    #[test]
    fn test_a_second_result_for_the_same_call_is_404() {
        let (store, srv) = new_bridge_agent();
        let tok = store.token().unwrap();
        let mtok = store.ensure_mcp_token().unwrap();

        let (id_tx, id_rx) = mpsc::channel();
        let _p = link_phone(
            &srv.url,
            &tok,
            TWO_TOOLS,
            Some(move |c: PhoneCall| {
                let _ = id_tx.send(c.id);
                ("ok".to_string(), false)
            }),
        );
        rpc(
            &srv.url,
            &mtok,
            r#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"sms.list"}}"#,
        );
        let id = id_rx.recv_timeout(Duration::from_secs(5)).unwrap();

        let resp = http_post_json(
            &format!("{}/v1/phone/result", srv.url),
            &tok,
            &format!(
                r#"{{"id":"{}","content":[{{"type":"text","text":"again"}}],"is_error":false}}"#,
                id
            ),
        )
        .unwrap();
        assert_eq!(resp.status, 404);
    }

    #[test]
    fn test_link_refuses_bad_tool_names_and_tiers() {
        let (store, srv) = new_bridge_agent();
        let tok = store.token().unwrap();
        let long_65 = format!("a{}", "b".repeat(64));
        let cases = [
            r#"{"tools":[{"name":"SMS.list","tier":"read"}]}"#.to_string(),
            r#"{"tools":[{"name":"9lives","tier":"read"}]}"#.to_string(),
            r#"{"tools":[{"name":"sms list","tier":"read"}]}"#.to_string(),
            r#"{"tools":[{"name":"sms/list","tier":"read"}]}"#.to_string(),
            r#"{"tools":[{"name":"","tier":"read"}]}"#.to_string(),
            format!(r#"{{"tools":[{{"name":"{}","tier":"read"}}]}}"#, long_65),
            r#"{"tools":[{"name":"sms.list","tier":"admin"}]}"#.to_string(),
            r#"{"tools":[{"name":"sms.list"}]}"#.to_string(),
        ];
        for body in cases {
            let resp = http_post_json(&format!("{}/v1/phone/link", srv.url), &tok, &body).unwrap();
            assert_eq!(resp.status, 400, "body: {}", body);
        }

        let valid_64 = format!("a{}", "b".repeat(63));
        let valid_body = format!(
            r#"{{"tools":[{{"name":"a","tier":"act"}},{{"name":"screen.tap","tier":"act"}},{{"name":"{}","tier":"outbound"}}]}}"#,
            valid_64
        );
        let _p = link_phone::<fn(PhoneCall) -> (String, bool)>(&srv.url, &tok, &valid_body, None);
    }

    #[test]
    fn test_mcp_tools_list_is_empty_without_a_phone() {
        let (store, srv) = new_bridge_agent();
        let mtok = store.ensure_mcp_token().unwrap();
        let (_, out) = rpc(
            &srv.url,
            &mtok,
            r#"{"jsonrpc":"2.0","id":7,"method":"tools/list"}"#,
        );
        let out = out.unwrap();
        let tools = out
            .get("result")
            .unwrap()
            .get("tools")
            .unwrap()
            .as_array()
            .unwrap();
        assert!(tools.is_empty());
        assert_eq!(out.get_i32("id"), 7);
    }

    #[test]
    fn test_mcp_tool_call_without_a_phone_is_a_tool_error() {
        let (store, srv) = new_bridge_agent();
        let mtok = store.ensure_mcp_token().unwrap();
        let (_, out) = rpc(
            &srv.url,
            &mtok,
            r#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"sms.send","arguments":{}}}"#,
        );
        let out = out.unwrap();
        assert!(out.get("error").is_none());
        let res = out.get("result").unwrap();
        assert_eq!(res.get_bool("isError"), true);
        assert!(res
            .get("content")
            .unwrap()
            .to_json_string()
            .contains("phone not connected"));
    }

    #[test]
    fn test_mcp_initialize_and_ping() {
        let (store, srv) = new_bridge_agent();
        let mtok = store.ensure_mcp_token().unwrap();
        let (_, out) = rpc(
            &srv.url,
            &mtok,
            r#"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{}}"#,
        );
        let out = out.unwrap();
        let res = out.get("result").unwrap();
        assert_eq!(res.get_str("protocolVersion"), MCP_PROTOCOL_VERSION);
        let info = res.get("serverInfo").unwrap();
        assert_eq!(info.get_str("name"), MCP_SERVER_NAME);
        assert_eq!(info.get_str("version"), VERSION);
        assert_eq!(
            res.get("capabilities")
                .unwrap()
                .get("tools")
                .unwrap()
                .get_bool("listChanged"),
            false
        );
        assert_eq!(out.get_str("id"), "a");

        let (_, ping_out) = rpc(
            &srv.url,
            &mtok,
            r#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#,
        );
        assert!(ping_out.unwrap().get("result").is_some());

        let (status, body) = rpc(
            &srv.url,
            &mtok,
            r#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
        );
        assert_eq!(status, 202);
        assert!(body.is_none());
    }

    #[test]
    fn test_mcp_unknown_method_and_bad_json() {
        let (store, srv) = new_bridge_agent();
        let mtok = store.ensure_mcp_token().unwrap();
        let (_, out) = rpc(
            &srv.url,
            &mtok,
            r#"{"jsonrpc":"2.0","id":1,"method":"resources/list"}"#,
        );
        let e = out.unwrap();
        assert_eq!(
            e.get("error").unwrap().get_i32("code"),
            RPC_METHOD_NOT_FOUND
        );

        let (_, out) = rpc(&srv.url, &mtok, r#"{"jsonrpc":"2.0","id":1,"#);
        let e = out.unwrap();
        assert_eq!(e.get("error").unwrap().get_i32("code"), RPC_PARSE_ERROR);
        assert!(e.get("id").unwrap().is_null());
    }

    #[test]
    fn test_mcp_needs_its_own_token() {
        let (store, srv) = new_bridge_agent();
        let pair_tok = store.token().unwrap();
        let wrong_tok = "a".repeat(64);
        for tok in ["", wrong_tok.as_str(), pair_tok.as_str()] {
            let mut hdrs = Vec::new();
            let auth;
            if !tok.is_empty() {
                auth = format!("Bearer {}", tok);
                hdrs.push(("Authorization", auth.as_str()));
            }
            let resp = http_do(
                "POST",
                &format!("{}/mcp/phone", srv.url),
                &hdrs,
                br#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#,
                None,
            )
            .unwrap();
            assert_eq!(resp.status, 401);
        }
    }

    #[test]
    fn test_mcp_get_is_405() {
        let (store, srv) = new_bridge_agent();
        let mtok = store.ensure_mcp_token().unwrap();
        let auth = format!("Bearer {}", mtok);
        let resp = http_do(
            "GET",
            &format!("{}/mcp/phone", srv.url),
            &[("Authorization", &auth)],
            &[],
            None,
        )
        .unwrap();
        assert_eq!(resp.status, 405);
        assert_eq!(resp.header("Allow"), "POST");
    }

    #[test]
    fn test_mcp_refuses_a_non_loopback_caller() {
        let s = Sampler::new(Duration::from_secs(1), "", "", Vec::new(), None);
        let store = Store::new(temp_dir());
        store.ensure_token().unwrap();
        let tok = store.ensure_mcp_token().unwrap();
        let mux = new_mux(s, store, "", "");

        for addr in [
            "100.101.102.103:51234",
            "192.168.1.10:9000",
            "[2606:4700::1]:443",
        ] {
            let mut req = HttpRequest::new(
                "POST",
                "/mcp/phone",
                br#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.to_vec(),
            );
            req.remote_addr = addr.to_string();
            req.set_header("Authorization", format!("Bearer {}", tok));
            let resp = mux.handle(&req);
            assert_eq!(resp.status, 403, "addr: {}", addr);
        }

        for addr in ["127.0.0.1:51234", "[::1]:51234"] {
            let mut req = HttpRequest::new(
                "POST",
                "/mcp/phone",
                br#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.to_vec(),
            );
            req.remote_addr = addr.to_string();
            req.set_header("Authorization", format!("Bearer {}", tok));
            let resp = mux.handle(&req);
            assert_eq!(resp.status, 200, "addr: {}", addr);
        }
    }

    #[test]
    fn test_phone_endpoint_tiers() {
        let (_, srv) = new_bridge_agent();
        for path in ["/v1/phone/link", "/v1/phone/result"] {
            let resp = http_post_json(&format!("{}{}", srv.url, path), "", "{}").unwrap();
            assert_eq!(resp.status, 401);
        }
        let resp = http_get(&format!("{}/v1/phone", srv.url)).unwrap();
        assert_eq!(resp.status, 200);
    }

    #[test]
    fn test_phone_call_timeout_depends_on_the_tier() {
        assert_eq!(phone_call_timeout(TIER_OUTBOUND), Duration::from_secs(90));
        for tier in [TIER_READ, TIER_ACT, "", "nonsense"] {
            assert_eq!(phone_call_timeout(tier), Duration::from_secs(30));
        }
    }

    #[test]
    fn test_tier_of_uses_the_phones_declaration() {
        let b = PhoneBridge::new();
        let parsed = JsonValue::parse(TWO_TOOLS).unwrap();
        let tools: Vec<PhoneTool> = parsed
            .get("tools")
            .unwrap()
            .as_array()
            .unwrap()
            .iter()
            .map(PhoneTool::from_json)
            .collect();
        b.set_tools_for_test(tools);
        assert_eq!(b.tier_of("sms.send"), TIER_OUTBOUND);
        assert_eq!(
            phone_call_timeout(&b.tier_of("sms.send")),
            PHONE_OUTBOUND_TIMEOUT
        );
        assert_eq!(
            phone_call_timeout(&b.tier_of("sms.list")),
            PHONE_TOOL_TIMEOUT
        );
        assert_eq!(
            phone_call_timeout(&b.tier_of("nothing.here")),
            PHONE_TOOL_TIMEOUT
        );
    }

    #[test]
    fn test_a_call_in_flight_ends_when_the_link_drops() {
        let (store, srv) = new_bridge_agent();
        let tok = store.token().unwrap();
        let mtok = store.ensure_mcp_token().unwrap();

        let (reached_tx, reached_rx) = mpsc::channel();
        let (stop_tx, stop_rx) = mpsc::channel::<()>();
        let stop_rx_arc = Arc::new(Mutex::new(stop_rx));
        let reached_tx_arc = Arc::new(Mutex::new(Some(reached_tx)));

        let p = link_phone(
            &srv.url,
            &tok,
            TWO_TOOLS,
            Some(move |_c: PhoneCall| {
                if let Some(tx) = reached_tx_arc.lock().unwrap().take() {
                    let _ = tx.send(());
                }
                let _ = stop_rx_arc.lock().unwrap().recv();
                ("too late".to_string(), true)
            }),
        );

        let srv_url = srv.url.clone();
        let (done_tx, done_rx) = mpsc::channel();
        thread::spawn(move || {
            let (_, out) = rpc(
                &srv_url,
                &mtok,
                r#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"sms.list"}}"#,
            );
            let _ = done_tx.send(out.unwrap());
        });

        reached_rx
            .recv_timeout(Duration::from_secs(5))
            .expect("call reached phone");
        p.cancel();

        let out = done_rx
            .recv_timeout(Duration::from_secs(10))
            .expect("the call did not end when the link dropped");
        let res = out.get("result").expect("result in rpc response");
        assert_eq!(res.get_bool("isError"), true);
        let _ = stop_tx.send(());
    }
}
