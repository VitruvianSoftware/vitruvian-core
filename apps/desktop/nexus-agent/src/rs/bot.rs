// Copyright (c) 2026 VitruvianSoftware
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

//! Native Rust port of `apps/desktop/nexus-agent/src/bot.js`.
//! Implements the Antigravity Telegram Bot command router, inline callback
//! handlers, media prompt builders, rate-limiting, and Telegram HTTP Bot API.

use crate::agy::{extract_file_paths, extract_image_paths, now_ms, AgyBridge, ModelInfo};
use crate::formatter::{format_response, split_message_default};
use crate::sessions::SessionManager;
use crate::{dotenv_parse, escape_json_string, JsonValue};
use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;

pub const RATE_LIMIT_MS: u64 = 3000;
pub const STREAM_UPDATE_INTERVAL_MS: u64 = 1500;
pub const MAX_RETRIES: usize = 1;
pub const LONG_REQUEST_THRESHOLD_MS: u64 = 30_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BotCommandSpec {
    pub command: &'static str,
    pub description: &'static str,
}

pub const BOT_COMMANDS: &[BotCommandSpec] = &[
    BotCommandSpec {
        command: "help",
        description: "Show all available commands",
    },
    BotCommandSpec {
        command: "cancel",
        description: "Cancel the current running request",
    },
    BotCommandSpec {
        command: "status",
        description: "Check if a request is running",
    },
    BotCommandSpec {
        command: "new",
        description: "Start a fresh session (clears context)",
    },
    BotCommandSpec {
        command: "session",
        description: "Show current session info",
    },
    BotCommandSpec {
        command: "sessions",
        description: "Browse and resume sessions",
    },
    BotCommandSpec {
        command: "name",
        description: "Name current session (e.g. /name Auth Fix)",
    },
    BotCommandSpec {
        command: "resume",
        description: "Resume a session by index",
    },
    BotCommandSpec {
        command: "delete_session",
        description: "Delete a session by index",
    },
    BotCommandSpec {
        command: "extensions",
        description: "List installed agy plugins",
    },
    BotCommandSpec {
        command: "skills",
        description: "List available agent skills",
    },
    BotCommandSpec {
        command: "mcp",
        description: "List configured MCP servers",
    },
    BotCommandSpec {
        command: "model",
        description: "Pick or show the model",
    },
    BotCommandSpec {
        command: "effort",
        description: "Reasoning effort (low|medium|high)",
    },
    BotCommandSpec {
        command: "mode",
        description: "Set approval mode (default|accept-edits|plan|yolo)",
    },
    BotCommandSpec {
        command: "thinking",
        description: "Toggle deep reasoning (--effort high)",
    },
    BotCommandSpec {
        command: "sandbox",
        description: "Toggle agy sandbox mode",
    },
    BotCommandSpec {
        command: "workdir",
        description: "Manage workspace shortcuts",
    },
    BotCommandSpec {
        command: "settings",
        description: "Show all current settings",
    },
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InlineButton {
    pub text: String,
    pub callback_data: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BotReplyMessage {
    pub text: String,
    pub plain_fallback: Option<String>,
    pub parse_mode: Option<String>,
    pub inline_keyboard: Vec<Vec<InlineButton>>,
    pub disable_notification: bool,
}

impl BotReplyMessage {
    pub fn plain(text: impl Into<String>) -> Self {
        BotReplyMessage {
            text: text.into(),
            plain_fallback: None,
            parse_mode: None,
            inline_keyboard: Vec::new(),
            disable_notification: false,
        }
    }

    pub fn with_keyboard(text: impl Into<String>, inline_keyboard: Vec<Vec<InlineButton>>) -> Self {
        BotReplyMessage {
            text: text.into(),
            plain_fallback: None,
            parse_mode: None,
            inline_keyboard,
            disable_notification: false,
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct BotDispatchOutcome {
    pub messages: Vec<BotReplyMessage>,
    pub callback_answer: Option<String>,
    pub photos: Vec<String>,
    pub documents: Vec<(String, String)>,
}

// ─── Configuration & Auth Helpers ────────────────────────────────────────────

pub fn parse_allowed_user_ids(raw: &str) -> Vec<i64> {
    raw.split(',')
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .filter_map(|s| s.parse::<i64>().ok())
        .collect()
}

pub fn is_user_authorized(user_id: Option<i64>, allowed_user_ids: &[i64]) -> bool {
    if allowed_user_ids.is_empty() {
        return true;
    }
    match user_id {
        Some(uid) => allowed_user_ids.contains(&uid),
        None => false,
    }
}

pub fn format_reply_context_prompt(prompt: &str, bot_reply_text: Option<&str>) -> String {
    if let Some(reply_text) = bot_reply_text.filter(|s| !s.is_empty()) {
        let quoted: String = reply_text.chars().take(2000).collect();
        format!(
            "Previous assistant response:\n\"\"\"\n{}\n\"\"\"\n\nUser follow-up:\n{}",
            quoted, prompt
        )
    } else {
        prompt.to_string()
    }
}

pub fn format_photo_prompt(local_path: &str, caption: Option<&str>) -> String {
    let cap = caption
        .filter(|s| !s.is_empty())
        .unwrap_or("Describe this image.");
    format!(
        "The user sent an image saved at: {}\n\nPlease use the view_file tool to look at this image, then respond to the user's request:\n\n{}",
        local_path, cap
    )
}

pub fn format_document_prompt(
    local_path: &str,
    file_name: &str,
    mime_type: &str,
    caption: Option<&str>,
) -> String {
    let default_cap = format!("Review this file: {}", file_name);
    let cap = caption.filter(|s| !s.is_empty()).unwrap_or(&default_cap);
    format!(
        "The user sent a file saved at: {} (original name: {}, MIME: {})\n\nPlease use the view_file tool to look at this file, then respond to the user's request:\n\n{}",
        local_path, file_name, mime_type, cap
    )
}

pub fn format_voice_prompt(local_path: &str) -> String {
    format!(
        "The user sent a voice message saved at: {}\n\nPlease use the view_file tool to listen to/transcribe this audio, then respond to what the user said.",
        local_path
    )
}

// ─── BotEngine ───────────────────────────────────────────────────────────────

pub struct BotEngine {
    pub bot_token: String,
    pub allowed_user_ids: Vec<i64>,
    pub working_dir: String,
    pub bridge: AgyBridge,
    pub sessions: Mutex<SessionManager>,
    pub last_request_time: Mutex<BTreeMap<i64, u64>>,
}

impl BotEngine {
    pub fn from_dotenv_and_env(
        env_text: &str,
        process_env: &BTreeMap<String, String>,
        default_cwd: &str,
    ) -> Self {
        let mut merged = process_env.clone();
        for (k, v) in dotenv_parse(env_text) {
            merged.entry(k).or_insert(v);
        }
        let bot_token = merged
            .get("TELEGRAM_BOT_TOKEN")
            .cloned()
            .unwrap_or_default();
        let allowed_user_ids = merged
            .get("ALLOWED_USER_IDS")
            .map(|s| parse_allowed_user_ids(s))
            .unwrap_or_default();
        let bridge = AgyBridge::from_env_map(merged, default_cwd);
        let working_dir = bridge.working_dir.clone();
        let sessions_file = PathBuf::from(&working_dir).join(".bot-sessions.json");
        BotEngine {
            bot_token,
            allowed_user_ids,
            working_dir,
            bridge,
            sessions: Mutex::new(SessionManager::new(sessions_file)),
            last_request_time: Mutex::new(BTreeMap::new()),
        }
    }

    pub fn from_process_env() -> Self {
        let cwd = env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("."))
            .to_string_lossy()
            .to_string();
        let env_text = fs::read_to_string(".env").unwrap_or_default();
        let proc_env: BTreeMap<String, String> = env::vars().collect();
        Self::from_dotenv_and_env(&env_text, &proc_env, &cwd)
    }

    pub fn check_auth(&self, user_id: Option<i64>) -> Option<BotDispatchOutcome> {
        if !is_user_authorized(user_id, &self.allowed_user_ids) {
            Some(BotDispatchOutcome {
                messages: vec![BotReplyMessage::plain(
                    "⛔ You are not authorized to use this bot.",
                )],
                ..Default::default()
            })
        } else {
            None
        }
    }

    /// Dispatch a slash command (e.g. `/start`, `/help`, `/mode plan`, etc.).
    pub fn handle_command(
        &self,
        chat_id: i64,
        user_id: Option<i64>,
        first_name: Option<&str>,
        text: &str,
    ) -> BotDispatchOutcome {
        if let Some(unauth) = self.check_auth(user_id) {
            return unauth;
        }

        let mut parts = text.trim().split_whitespace();
        let raw_cmd = parts.next().unwrap_or("");
        let cmd_without_slash = raw_cmd.strip_prefix('/').unwrap_or(raw_cmd);
        let cmd = cmd_without_slash
            .split('@')
            .next()
            .unwrap_or(cmd_without_slash);
        let arg = parts.collect::<Vec<&str>>().join(" ").trim().to_string();

        match cmd {
            "start" => {
                let name = first_name.filter(|s| !s.is_empty()).unwrap_or("there");
                BotDispatchOutcome {
                    messages: vec![BotReplyMessage::plain(format!(
                        "👋 Hi {}! I'm your Antigravity bridge.\n\n\
                         Send me any message and I'll forward it to the Antigravity CLI (agy) running on your machine.\n\n\
                         📂 Working directory: {}\n\n\
                         Type /help to see all available commands.",
                        name, self.working_dir
                    ))],
                    ..Default::default()
                }
            }
            "help" => BotDispatchOutcome {
                messages: vec![BotReplyMessage::plain(
                    "🤖 Antigravity Telegram Bot\n\n\
                     Just send me a message — I'll pass it to the Antigravity CLI (agy) and return the response.\n\n\
                     ━━━ Session Commands ━━━\n\
                     /new — Start a fresh session\n\
                     /cancel — Cancel the current running request\n\
                     /status — Check if a request is running and how long\n\
                     /session — Show current session info\n\
                     /sessions — Browse and resume sessions\n\
                     /name <label> — Name the current session\n\
                     /resume <n> — Resume session by index\n\
                     /delete_session <n> — Delete a session by index\n\n\
                     ━━━ CLI Management ━━━\n\
                     /extensions — List installed plugins\n\
                     /skills — List available skills\n\
                     /mcp — List MCP servers\n\n\
                     ━━━ Settings ━━━\n\
                     /model — Pick a model (or /model <id>)\n\
                     /effort <low|medium|high> — Reasoning effort\n\
                     /mode <mode> — Approval mode (yolo|accept-edits|plan|default)\n\
                     /thinking — Shortcut for /effort high on/off\n\
                     /sandbox — Toggle sandbox mode\n\
                     /workdir — Manage workspace shortcuts\n\
                     /settings — Show current settings\n\n\
                     ━━━ Other ━━━\n\
                     /help — Show this message",
                )],
                ..Default::default()
            },
            "new" => {
                self.sessions
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .delete_persisted_session(&chat_id.to_string());
                BotDispatchOutcome {
                    messages: vec![BotReplyMessage::plain(
                        "🆕 Session cleared. Your next message will start a fresh conversation.",
                    )],
                    ..Default::default()
                }
            }
            "cancel" => {
                let was_running = self.bridge.cancel_prompt(chat_id);
                let msg = if was_running {
                    "⛔ Request cancelled. The running prompt has been terminated."
                } else {
                    "ℹ️ No request is currently running."
                };
                BotDispatchOutcome {
                    messages: vec![BotReplyMessage::plain(msg)],
                    ..Default::default()
                }
            }
            "status" => {
                if let Some(info) = self.bridge.get_running_info(chat_id) {
                    let elapsed = ((now_ms().saturating_sub(info.start_time_ms) as f64) / 1000.0)
                        .round() as u64;
                    let mins = elapsed / 60;
                    let secs = elapsed % 60;
                    let ellipsis = if info.prompt.chars().count() >= 100 {
                        "..."
                    } else {
                        ""
                    };
                    BotDispatchOutcome {
                        messages: vec![BotReplyMessage::plain(format!(
                            "⏳ Request in progress\n\n\
                             ⏱️ Elapsed: {}m {}s\n\
                             💬 Prompt: {}{}\n\n\
                             Use /cancel to stop it.",
                            mins, secs, info.prompt, ellipsis
                        ))],
                        ..Default::default()
                    }
                } else {
                    BotDispatchOutcome {
                        messages: vec![BotReplyMessage::plain(
                            "✅ No request is currently running.",
                        )],
                        ..Default::default()
                    }
                }
            }
            "session" => {
                let settings = self.bridge.get_chat_settings(chat_id);
                let sess = self
                    .sessions
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .get_persisted_session(&chat_id.to_string());
                if let Some(sid) = sess {
                    BotDispatchOutcome {
                        messages: vec![BotReplyMessage::plain(format!(
                            "📋 Active session: {}\n📂 Working dir: {}",
                            sid, settings.working_dir
                        ))],
                        ..Default::default()
                    }
                } else {
                    BotDispatchOutcome {
                        messages: vec![BotReplyMessage::plain(format!(
                            "No active session. Send a message to start one.\n📂 Working dir: {}",
                            settings.working_dir
                        ))],
                        ..Default::default()
                    }
                }
            }
            "sessions" => {
                let settings = self.bridge.get_chat_settings(chat_id);
                let output = self
                    .bridge
                    .list_sessions(Some(&settings.working_dir), Some(chat_id));
                let mut buttons = Vec::new();
                for line in output.lines().map(|l| l.trim()).filter(|l| !l.is_empty()) {
                    let digits: String = line.chars().take_while(|c| c.is_ascii_digit()).collect();
                    if !digits.is_empty() && line[digits.len()..].starts_with('.') {
                        let label: String = line.chars().take(40).collect();
                        buttons.push(vec![InlineButton {
                            text: format!("📋 {}", label),
                            callback_data: format!("resume_session_{}", digits),
                        }]);
                    }
                }
                if !buttons.is_empty() {
                    BotDispatchOutcome {
                        messages: vec![BotReplyMessage::with_keyboard(
                            "📋 Available Sessions\n\nTap to resume:",
                            buttons,
                        )],
                        ..Default::default()
                    }
                } else {
                    let chunks =
                        split_message_default(&format!("📋 Available Sessions\n\n{}", output));
                    BotDispatchOutcome {
                        messages: chunks.into_iter().map(BotReplyMessage::plain).collect(),
                        ..Default::default()
                    }
                }
            }
            "resume" => {
                if arg.is_empty() {
                    return BotDispatchOutcome {
                        messages: vec![BotReplyMessage::plain(
                            "Usage: /resume <index|latest>\n\nExample: /resume 5 or /resume latest\n\nUse /sessions to see available sessions.",
                        )],
                        ..Default::default()
                    };
                }
                let working_dir = self.bridge.get_chat_settings(chat_id).working_dir;
                match self
                    .bridge
                    .set_session_resume(chat_id, &arg, Some(&working_dir))
                {
                    Ok(id) => {
                        self.sessions
                            .lock()
                            .unwrap_or_else(|e| e.into_inner())
                            .set_persisted_session(&chat_id.to_string(), &id);
                        let short: String = id.chars().take(8).collect();
                        BotDispatchOutcome {
                            messages: vec![BotReplyMessage::plain(format!(
                                "🔗 Session set to: {} ({}…)\nYour next message will resume that conversation.",
                                arg, short
                            ))],
                            ..Default::default()
                        }
                    }
                    Err(e) => BotDispatchOutcome {
                        messages: vec![BotReplyMessage::plain(format!("❌ {}", e))],
                        ..Default::default()
                    },
                }
            }
            "delete_session" => {
                if arg.is_empty() {
                    return BotDispatchOutcome {
                        messages: vec![BotReplyMessage::plain(
                            "Usage: /delete_session <index>\n\nUse /sessions to see available sessions.",
                        )],
                        ..Default::default()
                    };
                }
                let working_dir = self.bridge.get_chat_settings(chat_id).working_dir;
                let out = self
                    .bridge
                    .delete_session(&arg, Some(&working_dir), Some(chat_id));
                BotDispatchOutcome {
                    messages: vec![BotReplyMessage::plain(format!("🗑️ {}", out))],
                    ..Default::default()
                }
            }
            "extensions" => match self.bridge.list_extensions() {
                Ok(out) => {
                    let chunks =
                        split_message_default(&format!("🧩 Installed Extensions\n\n{}", out));
                    BotDispatchOutcome {
                        messages: chunks.into_iter().map(BotReplyMessage::plain).collect(),
                        ..Default::default()
                    }
                }
                Err(e) => BotDispatchOutcome {
                    messages: vec![BotReplyMessage::plain(format!(
                        "❌ Error listing extensions: {}",
                        e
                    ))],
                    ..Default::default()
                },
            },
            "skills" => {
                let out = self.bridge.list_skills();
                let chunks = split_message_default(&format!("🎯 Available Skills\n\n{}", out));
                BotDispatchOutcome {
                    messages: chunks.into_iter().map(BotReplyMessage::plain).collect(),
                    ..Default::default()
                }
            }
            "mcp" => match self.bridge.list_mcp_servers() {
                Ok(out) => {
                    let chunks = split_message_default(&format!("🔌 MCP Servers\n\n{}", out));
                    BotDispatchOutcome {
                        messages: chunks.into_iter().map(BotReplyMessage::plain).collect(),
                        ..Default::default()
                    }
                }
                Err(e) => BotDispatchOutcome {
                    messages: vec![BotReplyMessage::plain(format!(
                        "❌ Error listing MCP servers: {}",
                        e
                    ))],
                    ..Default::default()
                },
            },
            "model" => {
                if arg.is_empty() {
                    let settings = self.bridge.get_chat_settings(chat_id);
                    let models = self.bridge.list_models().unwrap_or_default();
                    return self.build_model_picker_reply(&settings.model, &models);
                }
                let value = if arg == "default" { "" } else { &arg };
                self.bridge.set_chat_setting_str(chat_id, "model", value);
                let display = if value.is_empty() {
                    "(agy default)"
                } else {
                    value
                };
                BotDispatchOutcome {
                    messages: vec![BotReplyMessage::plain(format!(
                        "🤖 Model set to: {}",
                        display
                    ))],
                    ..Default::default()
                }
            }
            "effort" => {
                let lower = arg.to_ascii_lowercase();
                let settings = self.bridge.get_chat_settings(chat_id);
                if lower.is_empty() {
                    let cur = if !settings.effort.is_empty() {
                        settings.effort.as_str()
                    } else if settings.thinking {
                        "high"
                    } else {
                        "(agy default)"
                    };
                    return BotDispatchOutcome {
                        messages: vec![BotReplyMessage::plain(format!(
                            "🧠 Reasoning effort: {}\n\n\
                             Usage: /effort <low|medium|high|default>\n\
                             high is thorough but slower (the bot waits up to 10 minutes for it).",
                            cur
                        ))],
                        ..Default::default()
                    };
                }
                if !matches!(lower.as_str(), "low" | "medium" | "high" | "default") {
                    return BotDispatchOutcome {
                        messages: vec![BotReplyMessage::plain(
                            "Usage: /effort <low|medium|high|default>",
                        )],
                        ..Default::default()
                    };
                }
                let val = if lower == "default" { "" } else { lower.as_str() };
                self.bridge.set_chat_setting_str(chat_id, "effort", val);
                self.bridge
                    .set_chat_setting_bool(chat_id, "thinking", lower == "high");
                BotDispatchOutcome {
                    messages: vec![BotReplyMessage::plain(format!(
                        "🧠 Effort set to: {}",
                        lower
                    ))],
                    ..Default::default()
                }
            }
            "mode" => {
                let valid_modes = ["yolo", "accept-edits", "plan", "default", "auto_edit"];
                if arg.is_empty() {
                    let settings = self.bridge.get_chat_settings(chat_id);
                    return BotDispatchOutcome {
                        messages: vec![BotReplyMessage::plain(format!(
                            "Current approval mode: {}\n\n\
                             Usage: /mode <yolo|accept-edits|plan|default>\n\n\
                             • yolo — auto-approve everything (--dangerously-skip-permissions)\n\
                             • accept-edits — auto-approve file edits; other tools are denied\n\
                             • plan — read-only: agy explains, changes nothing\n\
                             • default — nobody is here to click Approve, so agy denies any tool that needs it",
                            settings.approval_mode
                        ))],
                        ..Default::default()
                    };
                }
                if !valid_modes.contains(&arg.as_str()) {
                    return BotDispatchOutcome {
                        messages: vec![BotReplyMessage::plain(format!(
                            "❌ Invalid mode: {}\nValid modes: {}",
                            arg,
                            valid_modes.join(", ")
                        ))],
                        ..Default::default()
                    };
                }
                self.bridge
                    .set_chat_setting_str(chat_id, "approvalMode", &arg);
                BotDispatchOutcome {
                    messages: vec![BotReplyMessage::plain(format!(
                        "⚙️ Approval mode set to: {}",
                        arg
                    ))],
                    ..Default::default()
                }
            }
            "sandbox" => {
                let settings = self.bridge.get_chat_settings(chat_id);
                let new_val = !settings.sandbox;
                self.bridge
                    .set_chat_setting_bool(chat_id, "sandbox", new_val);
                let status = if new_val { "ON ✅" } else { "OFF ❌" };
                let detail = if new_val {
                    "agy will run tools in its sandbox (terminal restrictions)."
                } else {
                    "agy will run tools directly on the host."
                };
                BotDispatchOutcome {
                    messages: vec![BotReplyMessage::plain(format!(
                        "🏖️ Sandbox mode: {}\n\n{}",
                        status, detail
                    ))],
                    ..Default::default()
                }
            }
            "thinking" => {
                let settings = self.bridge.get_chat_settings(chat_id);
                let new_val = !settings.thinking;
                self.bridge
                    .set_chat_setting_bool(chat_id, "thinking", new_val);
                let status = if new_val { "ON ✅" } else { "OFF ❌" };
                let detail = if new_val {
                    "agy runs with --effort high. Responses may take longer but will be more thorough."
                } else {
                    "agy runs at its default effort."
                };
                BotDispatchOutcome {
                    messages: vec![BotReplyMessage::plain(format!(
                        "🧠 Thinking mode: {}\n\n{}",
                        status, detail
                    ))],
                    ..Default::default()
                }
            }
            "workdir" => {
                let workspaces = self
                    .sessions
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .get_workspaces();
                if arg.is_empty() {
                    let settings = self.bridge.get_chat_settings(chat_id);
                    if !workspaces.is_empty() {
                        let buttons: Vec<Vec<InlineButton>> = workspaces
                            .iter()
                            .map(|(alias, path)| {
                                let last = path.rsplit('/').next().unwrap_or(path);
                                vec![InlineButton {
                                    text: format!("📂 {}: {}", alias, last),
                                    callback_data: format!("workdir_switch_{}", alias),
                                }]
                            })
                            .collect();
                        return BotDispatchOutcome {
                            messages: vec![BotReplyMessage::with_keyboard(
                                format!(
                                    "📂 Current: {}\n\nSaved workspaces (tap to switch):",
                                    settings.working_dir
                                ),
                                buttons,
                            )],
                            ..Default::default()
                        };
                    } else {
                        return BotDispatchOutcome {
                            messages: vec![BotReplyMessage::plain(format!(
                                "📂 Current: {}\n\n\
                                 Usage:\n\
                                 /workdir save <alias> — Save current directory\n\
                                 /workdir /path/to/dir — Switch directly\n\
                                 /workdir remove <alias> — Remove a shortcut",
                                settings.working_dir
                            ))],
                            ..Default::default()
                        };
                    }
                }
                if let Some(rest) = arg.strip_prefix("save ") {
                    let alias = rest.trim();
                    if alias.is_empty() {
                        return BotDispatchOutcome {
                            messages: vec![BotReplyMessage::plain("Usage: /workdir save <alias>")],
                            ..Default::default()
                        };
                    }
                    let settings = self.bridge.get_chat_settings(chat_id);
                    self.sessions
                        .lock()
                        .unwrap_or_else(|e| e.into_inner())
                        .set_workspace(alias, &settings.working_dir);
                    return BotDispatchOutcome {
                        messages: vec![BotReplyMessage::plain(format!(
                            "💾 Saved \"{}\" → {}",
                            alias, settings.working_dir
                        ))],
                        ..Default::default()
                    };
                }
                if let Some(rest) = arg.strip_prefix("remove ") {
                    let alias = rest.trim();
                    if alias.is_empty() {
                        return BotDispatchOutcome {
                            messages: vec![BotReplyMessage::plain(
                                "Usage: /workdir remove <alias>",
                            )],
                            ..Default::default()
                        };
                    }
                    self.sessions
                        .lock()
                        .unwrap_or_else(|e| e.into_inner())
                        .delete_workspace(alias);
                    return BotDispatchOutcome {
                        messages: vec![BotReplyMessage::plain(format!(
                            "🗑️ Removed workspace shortcut \"{}\"",
                            alias
                        ))],
                        ..Default::default()
                    };
                }
                if let Some(saved_dir) = workspaces.get(&arg) {
                    self.bridge
                        .set_chat_setting_str(chat_id, "workingDir", saved_dir);
                    self.sessions
                        .lock()
                        .unwrap_or_else(|e| e.into_inner())
                        .delete_persisted_session(&chat_id.to_string());
                    return BotDispatchOutcome {
                        messages: vec![BotReplyMessage::plain(format!(
                            "📂 Switched to: {}\n\nSession cleared (new directory context).",
                            saved_dir
                        ))],
                        ..Default::default()
                    };
                }
                self.bridge
                    .set_chat_setting_str(chat_id, "workingDir", &arg);
                self.sessions
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .delete_persisted_session(&chat_id.to_string());
                BotDispatchOutcome {
                    messages: vec![BotReplyMessage::plain(format!(
                        "📂 Working directory set to: {}\n\nSession cleared (new directory context).",
                        arg
                    ))],
                    ..Default::default()
                }
            }
            "name" => {
                if arg.is_empty() {
                    let current = self
                        .sessions
                        .lock()
                        .unwrap_or_else(|e| e.into_inner())
                        .get_session_name(&chat_id.to_string());
                    let msg = match current {
                        Some(name) => format!(
                            "📛 Current session name: \"{}\"\n\nUsage: /name <label> to rename",
                            name
                        ),
                        None => "No session name set.\n\nUsage: /name <label>\nExample: /name Refactoring Auth"
                            .to_string(),
                    };
                    return BotDispatchOutcome {
                        messages: vec![BotReplyMessage::plain(msg)],
                        ..Default::default()
                    };
                }
                self.sessions
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .set_session_name(&chat_id.to_string(), &arg);
                BotDispatchOutcome {
                    messages: vec![BotReplyMessage::plain(format!(
                        "📛 Session named: \"{}\"",
                        arg
                    ))],
                    ..Default::default()
                }
            }
            "settings" => {
                let version = self.bridge.agy_version();
                let settings = self.bridge.get_chat_settings(chat_id);
                let session_id = self
                    .sessions
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .get_persisted_session(&chat_id.to_string());
                let ver_str = match version {
                    Some(v) => format!("agy {}", v),
                    None => "not found".to_string(),
                };
                let model_str = if settings.model.is_empty() {
                    "(agy default)"
                } else {
                    &settings.model
                };
                let effort_str = if !settings.effort.is_empty() {
                    settings.effort.as_str()
                } else if settings.thinking {
                    "high"
                } else {
                    "(agy default)"
                };
                let sandbox_str = if settings.sandbox { "ON" } else { "OFF" };
                let conv_str = match session_id {
                    Some(sid) => format!("{}…", sid.chars().take(8).collect::<String>()),
                    None => "(none)".to_string(),
                };
                BotDispatchOutcome {
                    messages: vec![BotReplyMessage::plain(format!(
                        "⚙️ Current Settings\n\n\
                         🚀 Antigravity CLI: {}\n\
                         📂 Working dir: {}\n\
                         🤖 Model: {}\n\
                         🔐 Approval mode: {}\n\
                         🧠 Effort: {}\n\
                         🏖️ Sandbox: {}\n\
                         📋 Conversation: {}",
                        ver_str,
                        settings.working_dir,
                        model_str,
                        settings.approval_mode,
                        effort_str,
                        sandbox_str,
                        conv_str
                    ))],
                    ..Default::default()
                }
            }
            _ => BotDispatchOutcome::default(),
        }
    }

    pub fn build_model_picker_reply(
        &self,
        current_model: &str,
        models: &[ModelInfo],
    ) -> BotDispatchOutcome {
        let model_display = if current_model.is_empty() {
            "(agy default)"
        } else {
            current_model
        };
        let header = format!(
            "🤖 Current model: {}\n\nTap one, or /model <id>. /model default clears it.",
            model_display
        );
        if models.is_empty() {
            return BotDispatchOutcome {
                messages: vec![BotReplyMessage::plain(header)],
                ..Default::default()
            };
        }
        let mut rows: Vec<Vec<InlineButton>> = models
            .iter()
            .take(12)
            .map(|m| {
                vec![InlineButton {
                    text: m.name.clone(),
                    callback_data: format!("set_model_{}", m.id),
                }]
            })
            .collect();
        rows.push(vec![InlineButton {
            text: "agy default".to_string(),
            callback_data: "set_model_default".to_string(),
        }]);
        BotDispatchOutcome {
            messages: vec![BotReplyMessage::with_keyboard(header, rows)],
            ..Default::default()
        }
    }

    /// Dispatch an inline keyboard callback query.
    pub fn handle_callback(
        &self,
        chat_id: i64,
        user_id: Option<i64>,
        data: &str,
    ) -> BotDispatchOutcome {
        if let Some(unauth) = self.check_auth(user_id) {
            return unauth;
        }

        if let Some(idx) = data.strip_prefix("resume_session_") {
            let working_dir = self.bridge.get_chat_settings(chat_id).working_dir;
            match self
                .bridge
                .set_session_resume(chat_id, idx, Some(&working_dir))
            {
                Ok(id) => {
                    self.sessions
                        .lock()
                        .unwrap_or_else(|e| e.into_inner())
                        .set_persisted_session(&chat_id.to_string(), &id);
                    let short: String = id.chars().take(8).collect();
                    return BotDispatchOutcome {
                        messages: vec![BotReplyMessage::plain(format!(
                            "🔗 Session set to: {} ({}…)\nYour next message will resume that conversation.",
                            idx, short
                        ))],
                        callback_answer: Some(format!("🔗 Resuming session {}", idx)),
                        ..Default::default()
                    };
                }
                Err(e) => {
                    return BotDispatchOutcome {
                        messages: vec![BotReplyMessage::plain(format!("❌ {}", e))],
                        callback_answer: Some(String::new()),
                        ..Default::default()
                    };
                }
            }
        }

        if let Some(model_arg) = data.strip_prefix("set_model_") {
            let value = if model_arg == "default" {
                ""
            } else {
                model_arg
            };
            self.bridge.set_chat_setting_str(chat_id, "model", value);
            let cb_label = if value.is_empty() {
                "agy default"
            } else {
                value
            };
            let reply_label = if value.is_empty() {
                "(agy default)"
            } else {
                value
            };
            return BotDispatchOutcome {
                messages: vec![BotReplyMessage::plain(format!(
                    "🤖 Model set to: {}",
                    reply_label
                ))],
                callback_answer: Some(format!("Model: {}", cb_label)),
                ..Default::default()
            };
        }

        if let Some(alias) = data.strip_prefix("workdir_switch_") {
            let workspaces = self
                .sessions
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .get_workspaces();
            if let Some(dir) = workspaces.get(alias) {
                self.bridge.set_chat_setting_str(chat_id, "workingDir", dir);
                self.sessions
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .delete_persisted_session(&chat_id.to_string());
                return BotDispatchOutcome {
                    messages: vec![BotReplyMessage::plain(format!(
                        "📂 Switched to: {}\n\nSession cleared.",
                        dir
                    ))],
                    callback_answer: Some(format!("📂 Switched to {}", alias)),
                    ..Default::default()
                };
            } else {
                return BotDispatchOutcome {
                    callback_answer: Some("❌ Workspace not found".to_string()),
                    ..Default::default()
                };
            }
        }

        if data == "cancel_prompt" {
            let was_running = self.bridge.cancel_prompt(chat_id);
            let mut messages = Vec::new();
            if was_running {
                messages.push(BotReplyMessage::plain("⛔ Request cancelled."));
            }
            return BotDispatchOutcome {
                messages,
                callback_answer: Some(
                    if was_running {
                        "⛔ Request cancelled"
                    } else {
                        "ℹ️ No request running"
                    }
                    .to_string(),
                ),
                ..Default::default()
            };
        }

        if data == "check_status" {
            if let Some(info) = self.bridge.get_running_info(chat_id) {
                let elapsed =
                    ((now_ms().saturating_sub(info.start_time_ms) as f64) / 1000.0).round() as u64;
                let mins = elapsed / 60;
                let secs = elapsed % 60;
                return BotDispatchOutcome {
                    callback_answer: Some(format!("⏱️ Running for {}m {}s", mins, secs)),
                    ..Default::default()
                };
            } else {
                return BotDispatchOutcome {
                    callback_answer: Some("✅ No request running".to_string()),
                    ..Default::default()
                };
            }
        }

        BotDispatchOutcome::default()
    }

    /// Execute a user prompt with rate-limiting, empty-response retry, stale/timeout
    /// notices, HTML formatting, and image/document path extraction.
    pub fn send_agent_response(
        &self,
        chat_id: i64,
        user_id: Option<i64>,
        prompt: &str,
        retry_count: usize,
    ) -> BotDispatchOutcome {
        if let Some(unauth) = self.check_auth(user_id) {
            return unauth;
        }

        let now = now_ms();
        if retry_count == 0 {
            let mut map = self
                .last_request_time
                .lock()
                .unwrap_or_else(|e| e.into_inner());
            let last_time = map.get(&chat_id).copied().unwrap_or(0);
            if last_time > 0 && now.saturating_sub(last_time) < RATE_LIMIT_MS {
                return BotDispatchOutcome {
                    messages: vec![BotReplyMessage::plain(
                        "⏳ Please wait a moment before sending another request.",
                    )],
                    ..Default::default()
                };
            }
            map.insert(chat_id, now);
        }

        let request_start = now_ms();
        match self.bridge.execute_prompt(prompt, Some(chat_id)) {
            Ok(result) => {
                if result.text.trim().is_empty()
                    || result.text == "No response."
                    || result.text == "No response from agy."
                {
                    if retry_count < MAX_RETRIES {
                        return self.send_agent_response(chat_id, user_id, prompt, retry_count + 1);
                    }
                    return BotDispatchOutcome {
                        messages: vec![BotReplyMessage::plain(
                            "⚠️ agy returned an empty response. Try rephrasing or run /new to start a fresh conversation.",
                        )],
                        ..Default::default()
                    };
                }

                let mut response_text = result.text.clone();
                if result.stale_session {
                    response_text.push_str(
                        "\n\n🔁 _The previous conversation was gone on agy's side, so this started a new one._",
                    );
                }
                if result.timed_out {
                    response_text
                        .push_str("\n\n⏰ _Response timed out — partial output shown above._");
                }

                let formatted = format_response(&response_text);
                let html_chunks = split_message_default(&formatted.text);
                let raw_chunks = split_message_default(&response_text);
                let elapsed = now_ms().saturating_sub(request_start);
                let notify_user = elapsed > LONG_REQUEST_THRESHOLD_MS || result.timed_out;

                let mut messages = Vec::new();
                for (i, html_chunk) in html_chunks.iter().enumerate() {
                    let raw_fallback = raw_chunks
                        .get(i)
                        .cloned()
                        .unwrap_or_else(|| html_chunk.clone());
                    messages.push(BotReplyMessage {
                        text: html_chunk.clone(),
                        plain_fallback: Some(raw_fallback),
                        parse_mode: formatted.parse_mode.clone(),
                        inline_keyboard: Vec::new(),
                        disable_notification: !notify_user,
                    });
                }

                let photos = extract_image_paths(&result.text);
                let documents: Vec<(String, String)> = extract_file_paths(&result.text)
                    .into_iter()
                    .map(|p| {
                        let fname = Path::new(&p)
                            .file_name()
                            .map(|f| f.to_string_lossy().to_string())
                            .unwrap_or_else(|| p.clone());
                        (p, fname)
                    })
                    .collect();

                BotDispatchOutcome {
                    messages,
                    callback_answer: None,
                    photos,
                    documents,
                }
            }
            Err(err) => {
                let short_err: String = err.chars().take(200).collect();
                BotDispatchOutcome {
                    messages: vec![BotReplyMessage::plain(format!("❌ Error: {}", short_err))],
                    ..Default::default()
                }
            }
        }
    }
}

// ─── Telegram HTTP Client (std + curl) ───────────────────────────────────────

pub struct TelegramHttpClient {
    pub bot_token: String,
    pub api_base: String,
}

impl TelegramHttpClient {
    pub fn new(bot_token: impl Into<String>) -> Self {
        let token = bot_token.into();
        let api_base = format!("https://api.telegram.org/bot{}", token);
        TelegramHttpClient {
            bot_token: token,
            api_base,
        }
    }

    pub fn call_json(&self, method: &str, body_json: &str) -> Result<JsonValue, String> {
        let url = format!("{}/{}", self.api_base, method);
        let output = Command::new("curl")
            .args([
                "-sS",
                "-X",
                "POST",
                "-H",
                "Content-Type: application/json",
                "-d",
                body_json,
                &url,
            ])
            .output()
            .map_err(|e| format!("Failed to invoke curl for {}: {}", method, e))?;
        let text = String::from_utf8_lossy(&output.stdout);
        let parsed = JsonValue::parse(text.trim())?;
        if parsed.get("ok").and_then(|v| v.as_bool()) != Some(true) {
            let desc = parsed
                .get("description")
                .and_then(|v| v.as_str())
                .unwrap_or("Telegram API error");
            return Err(desc.to_string());
        }
        Ok(parsed)
    }

    pub fn register_commands(&self) -> Result<usize, String> {
        let cmds: Vec<JsonValue> = BOT_COMMANDS
            .iter()
            .map(|c| {
                JsonValue::Object(vec![
                    (
                        "command".to_string(),
                        JsonValue::String(c.command.to_string()),
                    ),
                    (
                        "description".to_string(),
                        JsonValue::String(c.description.to_string()),
                    ),
                ])
            })
            .collect();
        let body = JsonValue::Object(vec![("commands".to_string(), JsonValue::Array(cmds))])
            .to_json_compact();
        self.call_json("setMyCommands", &body)?;
        let get_res = self.call_json("getMyCommands", "{}")?;
        let count = get_res
            .get("result")
            .and_then(|v| v.as_array())
            .map(|a| a.len())
            .unwrap_or(0);
        Ok(count)
    }

    pub fn send_reply(&self, chat_id: i64, msg: &BotReplyMessage) -> Result<(), String> {
        let mut fields = vec![
            ("chat_id".to_string(), JsonValue::Number(chat_id as f64)),
            ("text".to_string(), JsonValue::String(msg.text.clone())),
        ];
        if let Some(ref pm) = msg.parse_mode {
            fields.push(("parse_mode".to_string(), JsonValue::String(pm.clone())));
        }
        if msg.disable_notification {
            fields.push(("disable_notification".to_string(), JsonValue::Bool(true)));
        }
        if !msg.inline_keyboard.is_empty() {
            let rows: Vec<JsonValue> = msg
                .inline_keyboard
                .iter()
                .map(|r| {
                    JsonValue::Array(
                        r.iter()
                            .map(|b| {
                                JsonValue::Object(vec![
                                    ("text".to_string(), JsonValue::String(b.text.clone())),
                                    (
                                        "callback_data".to_string(),
                                        JsonValue::String(b.callback_data.clone()),
                                    ),
                                ])
                            })
                            .collect(),
                    )
                })
                .collect();
            fields.push((
                "reply_markup".to_string(),
                JsonValue::Object(vec![(
                    "inline_keyboard".to_string(),
                    JsonValue::Array(rows),
                )]),
            ));
        }
        let body = JsonValue::Object(fields).to_json_compact();
        if self.call_json("sendMessage", &body).is_err() {
            if let Some(ref fallback) = msg.plain_fallback {
                let fb_body = format!(
                    "{{\"chat_id\":{},\"text\":{},\"disable_notification\":{}}}",
                    chat_id,
                    escape_json_string(fallback),
                    msg.disable_notification
                );
                self.call_json("sendMessage", &fb_body)?;
            }
        }
        Ok(())
    }
}
