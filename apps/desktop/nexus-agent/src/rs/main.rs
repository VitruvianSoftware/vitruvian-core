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

//! Native Rust binary (`bot-engine`) for the Antigravity Telegram Bot.

use nexus_agent_src_lib::bot::{BotEngine, TelegramHttpClient, BOT_COMMANDS};
use nexus_agent_src_lib::JsonValue;
use std::env;
use std::process;
use std::thread;
use std::time::Duration;

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let engine = BotEngine::from_process_env();

    // Support `--print-agy-flags <prompt>` for non-interactive flag inspection
    if args.first().map(|s| s.as_str()) == Some("--print-agy-flags") {
        let prompt = args.get(1).map(|s| s.as_str()).unwrap_or("hi");
        let settings = engine.bridge.get_chat_settings(0);
        let built =
            nexus_agent_src_lib::agy::build_agy_args(prompt, &settings, "stream-json", None, None);
        let head: Vec<JsonValue> = built
            .iter()
            .take(4)
            .cloned()
            .map(JsonValue::String)
            .collect();
        let flags: Vec<JsonValue> = built
            .iter()
            .skip(4)
            .cloned()
            .map(JsonValue::String)
            .collect();
        let out = JsonValue::Object(vec![
            ("head".to_string(), JsonValue::Array(head)),
            ("flags".to_string(), JsonValue::Array(flags)),
        ]);
        println!("RESULT {}", out.to_json_compact());
        return;
    }

    if engine.bot_token.trim().is_empty() {
        eprintln!("❌ TELEGRAM_BOT_TOKEN is required. Set it in .env");
        process::exit(1);
    }

    println!("🚀 Starting Antigravity Telegram Bot...");
    println!("📂 Working directory: {}", engine.working_dir);
    let allowed_display = if engine.allowed_user_ids.is_empty() {
        "ALL (no whitelist set!)".to_string()
    } else {
        engine
            .allowed_user_ids
            .iter()
            .map(|id| id.to_string())
            .collect::<Vec<String>>()
            .join(", ")
    };
    println!("🔒 Allowed users: {}", allowed_display);

    if args.iter().any(|a| a == "--dry-run") {
        println!("✅ Bot is running!");
        println!(
            "📋 Registered {} commands with Telegram.",
            BOT_COMMANDS.len()
        );
        return;
    }

    let client = TelegramHttpClient::new(&engine.bot_token);
    println!("✅ Bot is running!");
    match client.register_commands() {
        Ok(registered) => {
            println!(
                "📋 Registered {} commands with Telegram.",
                BOT_COMMANDS.len()
            );
            println!("📋 Telegram reports {} commands registered.", registered);
        }
        Err(e) => {
            eprintln!("⚠️ Failed to register commands: {}", e);
        }
    }

    let mut offset: i64 = 0;
    loop {
        let poll_body = format!("{{\"offset\":{},\"timeout\":25}}", offset);
        let Ok(resp) = client.call_json("getUpdates", &poll_body) else {
            thread::sleep(Duration::from_secs(2));
            continue;
        };
        let Some(updates) = resp.get("result").and_then(|v| v.as_array()) else {
            continue;
        };
        for upd in updates {
            if let Some(uid) = upd.get("update_id").and_then(|v| v.as_i64()) {
                offset = uid + 1;
            }
            if let Some(cb) = upd.get("callback_query") {
                let chat_id = cb
                    .get("message")
                    .and_then(|m| m.get("chat"))
                    .and_then(|c| c.get("id"))
                    .and_then(|v| v.as_i64())
                    .unwrap_or(0);
                let user_id = cb
                    .get("from")
                    .and_then(|f| f.get("id"))
                    .and_then(|v| v.as_i64());
                let data = cb.get("data").and_then(|v| v.as_str()).unwrap_or("");
                let outcome = engine.handle_callback(chat_id, user_id, data);
                for msg in &outcome.messages {
                    let _ = client.send_reply(chat_id, msg);
                }
                continue;
            }
            if let Some(msg) = upd.get("message") {
                let chat_id = msg
                    .get("chat")
                    .and_then(|c| c.get("id"))
                    .and_then(|v| v.as_i64())
                    .unwrap_or(0);
                let user_id = msg
                    .get("from")
                    .and_then(|f| f.get("id"))
                    .and_then(|v| v.as_i64());
                let first_name = msg
                    .get("from")
                    .and_then(|f| f.get("first_name"))
                    .and_then(|v| v.as_str());
                if let Some(text) = msg.get("text").and_then(|v| v.as_str()) {
                    let outcome = if text.starts_with('/') {
                        engine.handle_command(chat_id, user_id, first_name, text)
                    } else {
                        engine.send_agent_response(chat_id, user_id, text, 0)
                    };
                    for reply in &outcome.messages {
                        let _ = client.send_reply(chat_id, reply);
                    }
                }
            }
        }
    }
}
