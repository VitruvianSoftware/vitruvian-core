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
// SPDX-License-Identifier: MIT

//! The MCP server, tools, and resources exposed over stdio.

use crate::auth::{self, LoginFlow};
use crate::config;
use crate::daemon::{self, ClientError, DaemonClient, DaemonUnavailable};
use serde_json::{json, Map, Value};
use std::fmt;
use std::io::{BufRead, Write};
use std::sync::Arc;
use std::time::Duration;

pub const DASHBOARD_URI: &str = "ui://dashboard";
pub const STATUS_URI: &str = "roborock://status";
pub const MAP_URI: &str = "roborock://map.png";

pub const INSTRUCTIONS: &str = "Controls a Roborock vacuum through a local daemon. Call get_status first: it says whether anyone is logged in and whether the vacuum is reachable. If it reports authenticated=false, walk the user through setup_login before anything else.";

pub trait DaemonApi: Send + Sync {
    fn status(&self) -> Result<Map<String, Value>, ClientError>;
    fn map_png(&self) -> Result<Option<Vec<u8>>, ClientError>;
    fn command(
        &self,
        action: &str,
        params: Option<&Map<String, Value>>,
    ) -> Result<Map<String, Value>, ClientError>;
}

impl DaemonApi for DaemonClient {
    fn status(&self) -> Result<Map<String, Value>, ClientError> {
        DaemonClient::status(self)
    }

    fn map_png(&self) -> Result<Option<Vec<u8>>, ClientError> {
        DaemonClient::map_png(self)
    }

    fn command(
        &self,
        action: &str,
        params: Option<&Map<String, Value>>,
    ) -> Result<Map<String, Value>, ClientError> {
        DaemonClient::command(self, action, params)
    }
}

pub type DaemonClientFactory =
    Arc<dyn Fn() -> Result<Arc<dyn DaemonApi>, DaemonUnavailable> + Send + Sync>;
pub type ReloadCheckFn = Arc<dyn Fn() -> bool + Send + Sync>;

#[derive(Clone)]
pub struct Bridge {
    client_factory: DaemonClientFactory,
    pub login_flow: LoginFlow,
    reload_fn: ReloadCheckFn,
}

impl Default for Bridge {
    fn default() -> Self {
        Self::new(None, None, None)
    }
}

impl Bridge {
    pub fn new(
        client_factory: Option<DaemonClientFactory>,
        login_flow: Option<LoginFlow>,
        reload_fn: Option<ReloadCheckFn>,
    ) -> Self {
        let factory = client_factory.unwrap_or_else(|| {
            Arc::new(|| {
                let c = daemon::ensure_running(None, Duration::from_secs(15))?;
                Ok(Arc::new(c) as Arc<dyn DaemonApi>)
            })
        });
        let reload = reload_fn.unwrap_or_else(|| {
            Arc::new(|| {
                let Ok(probe) = DaemonClient::new(None, None, None) else {
                    return false;
                };
                if probe.health().is_none() {
                    return false;
                }
                probe.reload().is_ok()
            })
        });
        Self {
            client_factory: factory,
            login_flow: login_flow.unwrap_or_default(),
            reload_fn: reload,
        }
    }

    pub fn call_status(&self) -> Result<Map<String, Value>, ClientError> {
        let client = (self.client_factory)().map_err(ClientError::Unavailable)?;
        client.status()
    }

    pub fn call_map_png(&self) -> Result<Option<Vec<u8>>, ClientError> {
        let client = (self.client_factory)().map_err(ClientError::Unavailable)?;
        client.map_png()
    }

    pub fn call_command(
        &self,
        action: &str,
        params: Option<&Map<String, Value>>,
    ) -> Result<Map<String, Value>, ClientError> {
        let client = (self.client_factory)().map_err(ClientError::Unavailable)?;
        client.command(action, params)
    }

    pub fn safe_status(&self) -> Map<String, Value> {
        Self::into_safe_doc(self.call_status())
    }

    pub fn safe_command(
        &self,
        action: &str,
        params: Option<&Map<String, Value>>,
    ) -> Map<String, Value> {
        Self::into_safe_doc(self.call_command(action, params))
    }

    pub fn reload_if_running(&self) -> bool {
        (self.reload_fn)()
    }

    fn into_safe_doc(res: Result<Map<String, Value>, ClientError>) -> Map<String, Value> {
        match res {
            Ok(doc) => doc,
            Err(ClientError::Request(err)) => {
                let mut doc = err.payload.clone();
                if err.code() == "not_authenticated" && !doc.contains_key("hint") {
                    doc.insert(
                        "hint".to_string(),
                        Value::String(auth::SETUP_HINT.to_string()),
                    );
                }
                doc
            }
            Err(ClientError::Unavailable(err)) => {
                let mut doc = Map::new();
                doc.insert("ok".to_string(), Value::Bool(false));
                doc.insert(
                    "error".to_string(),
                    Value::String("daemon_unavailable".to_string()),
                );
                doc.insert("message".to_string(), Value::String(err.to_string()));
                doc
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolAnnotations {
    pub read_only_hint: bool,
    pub destructive_hint: bool,
    pub idempotent_hint: bool,
    pub open_world_hint: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolDefinition {
    pub name: String,
    pub title: String,
    pub description: String,
    pub input_schema: Value,
    pub annotations: ToolAnnotations,
    pub meta: Option<Value>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResourceDefinition {
    pub uri: String,
    pub name: String,
    pub title: String,
    pub description: String,
    pub mime_type: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContentBlock {
    pub content_type: String,
    pub text: Option<String>,
    pub data: Option<String>,
    pub mime_type: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolCallResult {
    pub is_error: bool,
    pub structured_content: Option<Map<String, Value>>,
    pub content: Vec<ContentBlock>,
}

impl ToolCallResult {
    pub fn structured(doc: Map<String, Value>) -> Self {
        let text = serde_json::to_string(&doc).unwrap_or_else(|_| "{}".to_string());
        Self {
            is_error: false,
            structured_content: Some(doc),
            content: vec![ContentBlock {
                content_type: "text".to_string(),
                text: Some(text),
                data: None,
                mime_type: None,
            }],
        }
    }

    pub fn text(message: impl Into<String>) -> Self {
        Self {
            is_error: false,
            structured_content: None,
            content: vec![ContentBlock {
                content_type: "text".to_string(),
                text: Some(message.into()),
                data: None,
                mime_type: None,
            }],
        }
    }

    pub fn image(base64_data: String, mime_type: impl Into<String>) -> Self {
        Self {
            is_error: false,
            structured_content: None,
            content: vec![ContentBlock {
                content_type: "image".to_string(),
                text: None,
                data: Some(base64_data),
                mime_type: Some(mime_type.into()),
            }],
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolError(pub String);

impl fmt::Display for ToolError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for ToolError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResourceItem {
    pub uri: String,
    pub mime_type: String,
    pub text: Option<String>,
    pub bytes: Option<Vec<u8>>,
}

pub struct McpServer {
    pub name: String,
    pub version: String,
    pub instructions: String,
    pub bridge: Bridge,
}

pub fn build_server(bridge: Option<Bridge>) -> McpServer {
    McpServer {
        name: "vitruvian-roborock".to_string(),
        version: crate::VERSION.to_string(),
        instructions: INSTRUCTIONS.to_string(),
        bridge: bridge.unwrap_or_default(),
    }
}

impl McpServer {
    pub fn list_tools(&self) -> Vec<ToolDefinition> {
        let read_only = ToolAnnotations {
            read_only_hint: true,
            destructive_hint: false,
            idempotent_hint: true,
            open_world_hint: false,
        };
        let action = ToolAnnotations {
            read_only_hint: false,
            destructive_hint: false,
            idempotent_hint: true,
            open_world_hint: false,
        };

        vec![
            ToolDefinition {
                name: "get_status".to_string(),
                title: "Vacuum status".to_string(),
                description: "What the vacuum is doing now: state, battery, any error, cleaning progress and its rooms.".to_string(),
                input_schema: json!({"type": "object", "properties": {}}),
                annotations: read_only.clone(),
                meta: Some(json!({"ui": {"resourceUri": DASHBOARD_URI}})),
            },
            ToolDefinition {
                name: "start_clean".to_string(),
                title: "Start cleaning".to_string(),
                description: "Start cleaning. With no rooms, clean everywhere; otherwise only the named rooms.".to_string(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "rooms": {"type": "array", "items": {"type": "string"}},
                        "repeat": {"type": "integer", "default": 1}
                    }
                }),
                annotations: action.clone(),
                meta: None,
            },
            ToolDefinition {
                name: "control".to_string(),
                title: "Pause, resume, stop or locate".to_string(),
                description: "Pause or resume the current clean, stop it, or make the vacuum announce where it is.".to_string(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "action": {
                            "type": "string",
                            "enum": ["pause", "resume", "stop", "find"]
                        }
                    },
                    "required": ["action"]
                }),
                annotations: action.clone(),
                meta: None,
            },
            ToolDefinition {
                name: "return_to_dock".to_string(),
                title: "Return to dock".to_string(),
                description: "Send the vacuum back to its dock to charge.".to_string(),
                input_schema: json!({"type": "object", "properties": {}}),
                annotations: action.clone(),
                meta: None,
            },
            ToolDefinition {
                name: "wash_mop".to_string(),
                title: "Wash the mop".to_string(),
                description: "Start or stop a mop wash at the dock. Only docks with a mop washer support this.".to_string(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "action": {
                            "type": "string",
                            "enum": ["start", "stop"],
                            "default": "start"
                        }
                    }
                }),
                annotations: action.clone(),
                meta: None,
            },
            ToolDefinition {
                name: "get_map".to_string(),
                title: "Vacuum map".to_string(),
                description: "The current floor map as a PNG image, with the vacuum's position and path.".to_string(),
                input_schema: json!({"type": "object", "properties": {}}),
                annotations: read_only,
                meta: None,
            },
            ToolDefinition {
                name: "setup_login".to_string(),
                title: "Log in to Roborock".to_string(),
                description: "Log in to the Roborock cloud. Two calls.".to_string(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "email": {"type": "string"},
                        "code": {"type": "string"}
                    },
                    "required": ["email"]
                }),
                annotations: action,
                meta: None,
            },
        ]
    }

    pub fn list_resources(&self) -> Vec<ResourceDefinition> {
        vec![
            ResourceDefinition {
                uri: STATUS_URI.to_string(),
                name: "status".to_string(),
                title: "Vacuum status".to_string(),
                description: "The same document as the get_status tool.".to_string(),
                mime_type: "application/json".to_string(),
            },
            ResourceDefinition {
                uri: MAP_URI.to_string(),
                name: "map".to_string(),
                title: "Vacuum map".to_string(),
                description: "The current floor map as a PNG.".to_string(),
                mime_type: "image/png".to_string(),
            },
            ResourceDefinition {
                uri: DASHBOARD_URI.to_string(),
                name: "dashboard".to_string(),
                title: "Roborock dashboard".to_string(),
                description: "Live map and status for the vacuum.".to_string(),
                mime_type: "text/html;profile=mcp-app".to_string(),
            },
        ]
    }

    pub fn call_tool(
        &self,
        name: &str,
        arguments: &Map<String, Value>,
    ) -> Result<ToolCallResult, ToolError> {
        match name {
            "get_status" => Ok(ToolCallResult::structured(self.bridge.safe_status())),
            "start_clean" => {
                let rooms = arguments
                    .get("rooms")
                    .and_then(|v| v.as_array())
                    .filter(|arr| !arr.is_empty());
                let repeat = arguments
                    .get("repeat")
                    .and_then(|v| v.as_i64())
                    .unwrap_or(1);
                if let Some(rooms_arr) = rooms {
                    let mut params = Map::new();
                    params.insert("rooms".to_string(), Value::Array(rooms_arr.clone()));
                    params.insert("repeat".to_string(), Value::from(repeat));
                    Ok(ToolCallResult::structured(
                        self.bridge.safe_command("clean_rooms", Some(&params)),
                    ))
                } else {
                    Ok(ToolCallResult::structured(
                        self.bridge.safe_command("start", None),
                    ))
                }
            }
            "control" => {
                let action = arguments
                    .get("action")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                if !matches!(action, "pause" | "resume" | "stop" | "find") {
                    return Err(ToolError(
                        "Input should be 'pause', 'resume', 'stop' or 'find'".to_string(),
                    ));
                }
                Ok(ToolCallResult::structured(
                    self.bridge.safe_command(action, None),
                ))
            }
            "return_to_dock" => Ok(ToolCallResult::structured(
                self.bridge.safe_command("dock", None),
            )),
            "wash_mop" => {
                let action = arguments
                    .get("action")
                    .and_then(|v| v.as_str())
                    .unwrap_or("start");
                if !matches!(action, "start" | "stop") {
                    return Err(ToolError("Input should be 'start' or 'stop'".to_string()));
                }
                let cmd = format!("wash_{action}");
                Ok(ToolCallResult::structured(
                    self.bridge.safe_command(&cmd, None),
                ))
            }
            "get_map" => match self.bridge.call_map_png() {
                Ok(Some(png)) => Ok(ToolCallResult::image(
                    config::base64_encode(&png),
                    "image/png",
                )),
                Ok(None) => Ok(ToolCallResult::text(
                    "The vacuum has not sent a map yet. Check get_status, then try again.",
                )),
                Err(ClientError::Request(err)) => Ok(ToolCallResult::text(err.message())),
                Err(ClientError::Unavailable(err)) => Ok(ToolCallResult::text(err.to_string())),
            },
            "setup_login" => {
                let email = arguments
                    .get("email")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                let code = arguments.get("code").and_then(|v| v.as_str());
                let res = match code {
                    None => self.bridge.login_flow.request_code(email).map(|()| {
                        json!({
                            "ok": true,
                            "authenticated": false,
                            "next": "Roborock emailed a verification code. Ask the user for it, then call setup_login again with email and code."
                        })
                    }),
                    Some(c) => self.bridge.login_flow.complete(email, c).map(|_| {
                        let reloaded = self.bridge.reload_if_running();
                        json!({
                            "ok": true,
                            "authenticated": true,
                            "daemon_reloaded": reloaded
                        })
                    }),
                };
                match res {
                    Ok(val) => Ok(ToolCallResult::structured(
                        val.as_object().cloned().unwrap_or_default(),
                    )),
                    Err(err) => {
                        let doc = json!({
                            "ok": false,
                            "error": "login_failed",
                            "message": err.to_string()
                        });
                        Ok(ToolCallResult::structured(
                            doc.as_object().cloned().unwrap_or_default(),
                        ))
                    }
                }
            }
            other => Err(ToolError(format!("Unknown tool: {other}"))),
        }
    }

    pub fn read_resource(&self, uri: &str) -> Result<Vec<ResourceItem>, String> {
        match uri {
            STATUS_URI => {
                let doc = Value::Object(self.bridge.safe_status());
                let text = serde_json::to_string_pretty(&doc).map_err(|e| e.to_string())?;
                Ok(vec![ResourceItem {
                    uri: STATUS_URI.to_string(),
                    mime_type: "application/json".to_string(),
                    text: Some(text),
                    bytes: None,
                }])
            }
            MAP_URI => {
                let png = self
                    .bridge
                    .call_map_png()
                    .map_err(|e| e.to_string())?
                    .ok_or_else(|| "The vacuum has not sent a map yet.".to_string())?;
                Ok(vec![ResourceItem {
                    uri: MAP_URI.to_string(),
                    mime_type: "image/png".to_string(),
                    text: None,
                    bytes: Some(png),
                }])
            }
            DASHBOARD_URI => Ok(vec![ResourceItem {
                uri: DASHBOARD_URI.to_string(),
                mime_type: "text/html;profile=mcp-app".to_string(),
                text: Some(crate::dashboard_html().to_string()),
                bytes: None,
            }]),
            _ => Err(format!("Unknown resource URI: {uri}")),
        }
    }

    pub fn run_stdio(&self) -> std::io::Result<()> {
        let stdin = std::io::stdin();
        let mut stdout = std::io::stdout();
        for line in stdin.lock().lines() {
            let line = line?;
            if line.trim().is_empty() {
                continue;
            }
            let Ok(req) = serde_json::from_str::<Value>(&line) else {
                continue;
            };
            let id = req.get("id").cloned();
            let method = req.get("method").and_then(|v| v.as_str()).unwrap_or("");
            let Some(req_id) = id else {
                continue;
            };
            let response = match method {
                "initialize" => json!({
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "protocolVersion": "2024-11-05",
                        "serverInfo": {"name": self.name, "version": self.version},
                        "instructions": self.instructions,
                        "capabilities": {"tools": {}, "resources": {}}
                    }
                }),
                "tools/list" => {
                    let tools: Vec<Value> = self
                        .list_tools()
                        .into_iter()
                        .map(|t| {
                            json!({
                                "name": t.name,
                                "title": t.title,
                                "description": t.description,
                                "inputSchema": t.input_schema,
                            })
                        })
                        .collect();
                    json!({"jsonrpc": "2.0", "id": req_id, "result": {"tools": tools}})
                }
                "resources/list" => {
                    let resources: Vec<Value> = self
                        .list_resources()
                        .into_iter()
                        .map(|r| {
                            json!({
                                "uri": r.uri,
                                "name": r.name,
                                "title": r.title,
                                "description": r.description,
                                "mimeType": r.mime_type,
                            })
                        })
                        .collect();
                    json!({"jsonrpc": "2.0", "id": req_id, "result": {"resources": resources}})
                }
                "tools/call" => {
                    let params = req.get("params").and_then(|v| v.as_object());
                    let tool_name = params
                        .and_then(|p| p.get("name"))
                        .and_then(|v| v.as_str())
                        .unwrap_or("");
                    let args = params
                        .and_then(|p| p.get("arguments"))
                        .and_then(|v| v.as_object())
                        .cloned()
                        .unwrap_or_default();
                    match self.call_tool(tool_name, &args) {
                        Ok(res) => json!({
                            "jsonrpc": "2.0",
                            "id": req_id,
                            "result": {
                                "isError": res.is_error,
                                "structuredContent": res.structured_content,
                            }
                        }),
                        Err(err) => json!({
                            "jsonrpc": "2.0",
                            "id": req_id,
                            "error": {"code": -32602, "message": err.to_string()}
                        }),
                    }
                }
                _ => json!({
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {"code": -32601, "message": "Method not found"}
                }),
            };
            writeln!(stdout, "{response}")?;
            stdout.flush()?;
        }
        Ok(())
    }
}
