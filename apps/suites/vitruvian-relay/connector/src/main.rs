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

//! `vrelay` commands. `run` and `install` come in later tasks.

use vitruvian_relay_connector::auth::{fresh_token, login, register_device};
use vitruvian_relay_connector::bridge::{Bridge, BridgeCommand};
use vitruvian_relay_connector::config::Config;
use vitruvian_relay_connector::keys::{load_or_create, public_key_b64};
use vitruvian_relay_connector::state::{
    clear_sign_in, ensure_dir, now_unix, save_device, save_tokens,
};
use vitruvian_relay_connector::{rules, status, Result};

const USAGE: &str = "usage: vrelay <login|status|logout|tools [--raw]>";

fn cmd_login(cfg: &Config) -> Result<()> {
    ensure_dir(&cfg.dir)?;
    // The key first, so a failure here does not cost the person a sign-in.
    let key = load_or_create(&cfg.dir)?;
    let mut tokens = login(cfg)?;
    save_tokens(&cfg.dir, &tokens)?;
    let access = fresh_token(cfg, &mut tokens)?;
    let device = register_device(cfg, &access, &public_key_b64(&key))?;
    save_device(&cfg.dir, &device)?;
    println!("Signed in. This Mac is registered with the relay.");
    println!();
    println!("To use it from Claude, add a custom connector with:");
    println!("  MCP URL:    {}", device.mcp_url);
    println!("  Client ID:  {}", cfg.claude_client_id);
    Ok(())
}

fn cmd_logout(cfg: &Config) -> Result<()> {
    if clear_sign_in(&cfg.dir)? {
        println!("Signed out. The device key was kept; sign in again to reconnect.");
    } else {
        println!("Already signed out.");
    }
    Ok(())
}

/// Starts desktop-commander, lists its tools with what the rules decide for
/// each (`run`, `ask first`, `hidden`), and stops it. With `--raw`, prints its
/// own `tools/list` result as JSON instead, unfiltered.
fn cmd_tools(cfg: &Config, raw: bool) -> Result<()> {
    let rules = if raw {
        None
    } else {
        Some(rules::load(&cfg.dir)?)
    };
    let cmd = BridgeCommand::locate()?;
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|e| format!("start the runtime: {e}"))?;
    let bridge = Bridge::start(&cmd)?;
    let out = match rules {
        None => rt.block_on(bridge.tools_raw()).and_then(|v| {
            serde_json::to_string_pretty(&v).map_err(|e| format!("print tools: {e}"))
        }),
        Some(rules) => {
            let tools = rt.block_on(bridge.tools());
            let mut s = String::new();
            if rules.paused {
                s.push_str("Paused in rules.toml: every tool is hidden.\n");
            }
            let width = tools.iter().map(|t| t.name.len()).max().unwrap_or(0);
            for t in &tools {
                let what = if rules.paused || rules.is_hidden(&t.name) {
                    "hidden"
                } else {
                    match rules.decide(&t.name, &serde_json::json!({})) {
                        rules::Decision::Run => "run",
                        rules::Decision::AskFirst => "ask first",
                        rules::Decision::Refuse(_) => "hidden",
                    }
                };
                let args: Vec<_> = rules::ASK_FIRST_ARGS
                    .iter()
                    .filter(|(tool, _)| *tool == t.name && what == "run")
                    .map(|(_, a)| *a)
                    .collect();
                let extra = if args.is_empty() {
                    String::new()
                } else {
                    format!(" (asks first with {})", args.join(", "))
                };
                s.push_str(&format!("{:width$}  {what}{extra}\n", t.name));
            }
            s.push_str(&format!("{} tools from desktop-commander.", tools.len()));
            Ok(s)
        }
    };
    bridge.stop();
    println!("{}", out?);
    Ok(())
}

fn main() {
    let cfg = Config::from_env();
    let result = match std::env::args().nth(1).as_deref() {
        Some("login") => cmd_login(&cfg),
        Some("status") => {
            print!("{}", status::render(&cfg.dir, now_unix()));
            Ok(())
        }
        Some("logout") => cmd_logout(&cfg),
        Some("tools") => match std::env::args().nth(2).as_deref() {
            None => cmd_tools(&cfg, false),
            Some("--raw") => cmd_tools(&cfg, true),
            Some(_) => Err(USAGE.to_string()),
        },
        _ => Err(USAGE.to_string()),
    };
    if let Err(e) = result {
        eprintln!("vrelay: {e}");
        std::process::exit(1);
    }
}
