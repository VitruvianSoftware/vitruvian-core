// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT
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

//! Rust port of `tools/test-mcp-slack-e2e.sh`.

use serde_json::Value;
use shell_compat::{env_or, env_or_empty, err, os, out, status_code, subst};
use std::process::{Command, Stdio};

/// Match `HTTP/[0-9.]+ 200` anywhere in `resp`.
pub fn has_http_200(resp: &str) -> bool {
    let prefix = "HTTP/";
    let mut rest = resp;
    while let Some(pos) = rest.find(prefix) {
        let after = &rest[pos + prefix.len()..];
        let ver_len = after
            .bytes()
            .take_while(|&b| b.is_ascii_digit() || b == b'.')
            .count();
        if ver_len > 0 && after[ver_len..].starts_with(" 200") {
            return true;
        }
        rest = after;
    }
    false
}

/// Emulate `echo "${DISCOVERY_RESP}" | grep -A5 '{"resource"' | sed 's/^/    /'`.
/// Returns `None` if no line matches `{"resource"`.
pub fn extract_resource_preview(resp: &str) -> Option<String> {
    let lines: Vec<&str> = resp.lines().collect();
    let mut matched = false;
    let mut remaining_after = 0usize;
    let mut out_lines = Vec::new();
    for line in lines {
        if line.contains("{\"resource\"") {
            matched = true;
            remaining_after = 5;
            out_lines.push(format!("    {line}"));
        } else if remaining_after > 0 {
            remaining_after -= 1;
            out_lines.push(format!("    {line}"));
        }
    }
    if matched {
        let mut joined = out_lines.join("\n");
        joined.push('\n');
        Some(joined)
    } else {
        None
    }
}

/// Extract `.result.tools | length` from SSE `^data: ` lines, returning `"0"` on failure.
pub fn parse_tools_count(sse: &str) -> String {
    let data_lines: Vec<&str> = sse
        .lines()
        .filter_map(|l| l.strip_prefix("data: "))
        .collect();
    if data_lines.is_empty() {
        return "0".to_string();
    }
    let mut counts = Vec::new();
    for dl in data_lines {
        match serde_json::from_str::<Value>(dl) {
            Ok(v) => {
                let len = match v.pointer("/result/tools") {
                    Some(Value::Array(arr)) => arr.len(),
                    Some(Value::Object(map)) => map.len(),
                    Some(Value::String(s)) => s.chars().count(),
                    Some(Value::Null) | None => 0,
                    _ => return "0".to_string(),
                };
                counts.push(len.to_string());
            }
            Err(_) => return "0".to_string(),
        }
    }
    counts.join("\n")
}

/// Extract `.result.content[0].text | fromjson | .channels | length` from SSE `^data: ` lines.
pub fn parse_channels_count(sse: &str) -> String {
    let data_lines: Vec<&str> = sse
        .lines()
        .filter_map(|l| l.strip_prefix("data: "))
        .collect();
    if data_lines.is_empty() {
        return "0".to_string();
    }
    let mut counts = Vec::new();
    for dl in data_lines {
        match serde_json::from_str::<Value>(dl) {
            Ok(v) => {
                let Some(text) = v.pointer("/result/content/0/text").and_then(Value::as_str) else {
                    return "0".to_string();
                };
                let Ok(inner) = serde_json::from_str::<Value>(text) else {
                    return "0".to_string();
                };
                let len = match inner.get("channels") {
                    Some(Value::Array(arr)) => arr.len(),
                    Some(Value::Object(map)) => map.len(),
                    Some(Value::String(s)) => s.chars().count(),
                    Some(Value::Null) | None => 0,
                    _ => return "0".to_string(),
                };
                counts.push(len.to_string());
            }
            Err(_) => return "0".to_string(),
        }
    }
    counts.join("\n")
}

fn curl_capture(args: &[&[u8]]) -> (i32, String) {
    let mut cmd = Command::new("curl");
    for a in args {
        cmd.arg(os(a));
    }
    cmd.stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit());
    match cmd.output() {
        Ok(o) => (
            status_code(o.status),
            String::from_utf8_lossy(&subst(o.stdout)).into_owned(),
        ),
        Err(_) => (127, String::new()),
    }
}

pub fn run(args: &[Vec<u8>]) -> i32 {
    let mcp_url = env_or("MCP_URL", b"https://mcp-slack.ipv1337.dev/mcp");
    let default_disc = {
        let base = mcp_url.strip_suffix(b"/mcp").unwrap_or(&mcp_url);
        let mut v = base.to_vec();
        v.extend_from_slice(b"/.well-known/oauth-protected-resource/mcp");
        v
    };
    let discovery_url = env_or("DISCOVERY_URL", &default_disc);
    let token = {
        let env_tok = env_or_empty("MCP_TOKEN");
        if !env_tok.is_empty() {
            env_tok
        } else {
            args.first().cloned().unwrap_or_default()
        }
    };

    out(b"============================================================\n");
    out(b"  mcp-slack Live End-to-End Validation\n");
    out(b"============================================================\n\n");

    out(b"\xE2\x96\xB6 [1/4] Checking RFC 9728 OAuth Resource Discovery...\n");
    let (disc_rc, disc_resp) = curl_capture(&[b"-s", b"-i", &discovery_url]);
    if disc_rc != 0 {
        return disc_rc;
    }
    if has_http_200(&disc_resp) {
        out(b"  \xE2\x9C\x93 Discovery endpoint returned HTTP 200 OK\n");
        if let Some(preview) = extract_resource_preview(&disc_resp) {
            out(preview.as_bytes());
        } else {
            return 1;
        }
    } else {
        err(b"  \xE2\x9C\x97 Discovery endpoint check failed\n");
        return 1;
    }
    out(b"\n");

    out(b"\xE2\x96\xB6 [2/4] Verifying Unauthenticated 401 Rejection + Challenge...\n");
    let (_unauth_rc, unauth_resp) = curl_capture(&[b"-s", b"-i", &mcp_url]);
    if unauth_resp.contains("401") {
        out(b"  \xE2\x9C\x93 Unauthenticated call rejected with HTTP 401 Unauthorized\n");
        if unauth_resp
            .to_ascii_lowercase()
            .contains("www-authenticate: bearer")
        {
            out(b"  \xE2\x9C\x93 WWW-Authenticate header correctly advertises RFC 9728 resource_metadata\n");
        }
    } else {
        err(b"  \xE2\x9C\x97 Security check failed: endpoint did not return 401 for unauthenticated request\n");
        return 1;
    }
    out(b"\n");

    if token.is_empty() {
        out(b"\xE2\x96\xB6 [3/4] Authenticated checks skipped (no MCP_TOKEN provided).\n");
        out(b"  To run authenticated JSON-RPC tests:\n");
        out(b"    export MCP_TOKEN=\"<your-jwt-token>\"\n");
        out(b"    ./tools/test-mcp-slack-e2e.sh\n\n");
        out(b"\xE2\x9C\x93 Base infrastructure and OAuth discovery validation PASSED.\n");
        return 0;
    }

    let mut auth_hdr = b"Authorization: Bearer ".to_vec();
    auth_hdr.extend_from_slice(&token);

    out(b"\xE2\x96\xB6 [3/4] Testing Authenticated MCP Session Initialization...\n");
    let init_payload = b"{\n    \"jsonrpc\": \"2.0\",\n    \"id\": 1,\n    \"method\": \"initialize\",\n    \"params\": {\n      \"protocolVersion\": \"2024-11-05\",\n      \"capabilities\": {},\n      \"clientInfo\": { \"name\": \"e2e-cli-tester\", \"version\": \"1.0.0\" }\n    }\n  }";
    let (init_rc, init_resp) = curl_capture(&[
        b"-s",
        b"-X",
        b"POST",
        &mcp_url,
        b"-H",
        &auth_hdr,
        b"-H",
        b"Content-Type: application/json",
        b"-H",
        b"Accept: application/json, text/event-stream",
        b"-d",
        init_payload,
    ]);
    if init_rc != 0 {
        return init_rc;
    }

    if init_resp.contains("\"serverInfo\":{\"name\":\"mcp-slack\"") {
        out(b"  \xE2\x9C\x93 MCP Initialize succeeded (server: mcp-slack v2.0.0)\n");
    } else {
        err(b"  \xE2\x9C\x97 MCP Initialize failed:\n");
        err(format!("{init_resp}\n").as_bytes());
        return 1;
    }
    out(b"\n");

    out(b"\xE2\x96\xB6 [4/4] Testing Tool Surface & Live Slack Execution...\n");
    let tools_payload = b"{\n    \"jsonrpc\": \"2.0\",\n    \"id\": 2,\n    \"method\": \"tools/list\",\n    \"params\": {}\n  }";
    let (tools_rc, tools_resp) = curl_capture(&[
        b"-s",
        b"-X",
        b"POST",
        &mcp_url,
        b"-H",
        &auth_hdr,
        b"-H",
        b"Content-Type: application/json",
        b"-H",
        b"Accept: application/json, text/event-stream",
        b"-d",
        tools_payload,
    ]);
    if tools_rc != 0 {
        return tools_rc;
    }

    let tool_count = parse_tools_count(&tools_resp);
    out(
        format!("  ✓ Advertised tools count: {tool_count} (Impersonation tool surface active)\n")
            .as_bytes(),
    );

    out(b"  Executing live 'slack_list_channels' tool call...\n");
    let channels_payload = b"{\n    \"jsonrpc\": \"2.0\",\n    \"id\": 3,\n    \"method\": \"tools/call\",\n    \"params\": {\n      \"name\": \"slack_list_channels\",\n      \"arguments\": {}\n    }\n  }";
    let (ch_rc, ch_resp) = curl_capture(&[
        b"-s",
        b"-X",
        b"POST",
        &mcp_url,
        b"-H",
        &auth_hdr,
        b"-H",
        b"Content-Type: application/json",
        b"-H",
        b"Accept: application/json, text/event-stream",
        b"-d",
        channels_payload,
    ]);
    if ch_rc != 0 {
        return ch_rc;
    }

    let channels_count = parse_channels_count(&ch_resp);
    out(format!(
        "  ✓ Live Slack API communication successful: fetched {channels_count} allow-listed channels.\n\n"
    )
    .as_bytes());
    out(b"============================================================\n");
    out(b"  \xF0\x9F\x8E\x89 ALL END-TO-END VALIDATION CHECKS PASSED!\n");
    out(b"============================================================\n");
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_http_200_status_lines() {
        assert!(has_http_200(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json"
        ));
        assert!(has_http_200("HTTP/2 200 \r\n"));
        assert!(!has_http_200("HTTP/1.1 401 Unauthorized"));
    }

    #[test]
    fn parses_sse_tools_and_channels_counts() {
        let tools_sse = "event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"tools\":[{\"name\":\"a\"},{\"name\":\"b\"}]}}\n";
        assert_eq!(parse_tools_count(tools_sse), "2");

        let ch_sse = "event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"{\\\"channels\\\":[{\\\"id\\\":\\\"C1\\\"},{\\\"id\\\":\\\"C2\\\"},{\\\"id\\\":\\\"C3\\\"}]}\"}]}}\n";
        assert_eq!(parse_channels_count(ch_sse), "3");
    }
}
