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

//! `vrelay` commands. Installing it is `scripts:install`.

use vitruvian_relay_connector::auth::{fresh_token, login, register_device};
use vitruvian_relay_connector::awake::Awake;
use vitruvian_relay_connector::bridge::{Bridge, BridgeCommand};
use vitruvian_relay_connector::config::Config;
use vitruvian_relay_connector::keys::{load_or_create, public_key_b64};
use vitruvian_relay_connector::link::{system_rng, Dialog, FileTokens, Link, Timing};
use vitruvian_relay_connector::state::{
    clear_sign_in, ensure_dir, now_unix, save_new_device, save_new_sign_in,
};
use vitruvian_relay_connector::{rules, state, status, Result};

use std::sync::{Arc, Mutex};
use std::time::Duration;

const USAGE: &str = "usage: vrelay <login|run|status|logout|pause|resume|reload|tools [--raw]>";

fn cmd_login(cfg: &Config) -> Result<()> {
    ensure_dir(&cfg.dir)?;
    // The key first, so a failure here does not cost the person a sign-in.
    let key = load_or_create(&cfg.dir)?;
    let mut tokens = login(cfg)?;
    // Under the sign-in lock, so a running agent's refresh finishing at
    // the same moment cannot write the old session over this one.
    save_new_sign_in(&cfg.dir, &tokens)?;
    let access = fresh_token(cfg, &mut tokens)?;
    let device = register_device(cfg, &access, &public_key_b64(&key))?;
    save_new_device(&cfg.dir, &device)?;
    println!("Signed in. This Mac is registered with the relay.");
    println!();
    println!("To use it from Claude, add a custom connector with:");
    println!("  MCP URL:    {}", device.mcp_url);
    println!("  Client ID:  {}", cfg.claude_client_id);
    Ok(())
}

fn cmd_logout(cfg: &Config) -> Result<()> {
    if clear_sign_in(&cfg.dir)? {
        println!(
            "Signed out. The sign-in and the device key are removed; sign in again to reconnect."
        );
    } else {
        println!("Already signed out.");
    }
    // The running agent checks the sign-in every 20 s anyway; this makes
    // it look now.
    if status::nudge_agent(&cfg.dir, now_unix()) {
        println!("The running vrelay is dropping its link to the relay.");
    }
    Ok(())
}

/// Tells the running agent to re-read the rules, and waits for it to say
/// it has. `what` is what the person just did, for the message.
fn reload_agent(cfg: &Config, what: &str) -> Result<()> {
    // Read first: the answer is the reload this signal causes, not one
    // before it.
    let before = status::reloads(&cfg.dir, now_unix());
    if !status::nudge_agent(&cfg.dir, now_unix()) {
        println!("{what} vrelay run is not running; the rules apply when it starts.");
        return Ok(());
    }
    match status::wait_for_reload(&cfg.dir, before, Duration::from_secs(5)) {
        Ok(true) => {
            println!("{what} The running vrelay is using the rules now.");
            Ok(())
        }
        Ok(false) => Err(format!(
            "{what} The running vrelay did not confirm it reloaded the rules; \
             check `vrelay status`."
        )),
        Err(e) => Err(format!(
            "the running vrelay could not load the rules, so it keeps the ones it had: {e}"
        )),
    }
}

/// `vrelay pause` / `vrelay resume`: sets `paused` in rules.toml, then
/// reloads. While paused no tools are visible and every call is refused.
fn cmd_pause(cfg: &Config, paused: bool) -> Result<()> {
    ensure_dir(&cfg.dir)?;
    rules::set_paused(&cfg.dir, paused)?;
    let what = if paused {
        "Paused: the relay sees no tools and every call is refused."
    } else {
        "Resumed: the relay sees the tools the rules allow."
    };
    reload_agent(cfg, what)
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

/// The link to the relay, until SIGTERM or Ctrl-C. Starts without a token
/// (it waits for `vrelay login`), but not with a rules file it cannot read.
fn cmd_run(cfg: &Config) -> Result<()> {
    ensure_dir(&cfg.dir)?;
    let mut rules = rules::load(&cfg.dir)
        .map_err(|e| format!("not starting: the rules file does not load: {e}"))?;
    // vrelay's own folders are off limits to remote calls (ruling R17).
    rules.set_guard(rules::Guard::new(cfg));
    let key = Arc::new(load_or_create(&cfg.dir)?);
    let cmd = BridgeCommand::locate()?;
    let rt = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .map_err(|e| format!("start the runtime: {e}"))?;
    // launchd never rotates vrelay.log: cut it back now and then.
    let agent_log = cfg.log_dir.join(state::AGENT_LOG);
    let cap = move || {
        for fd in [1, 2] {
            if let Err(e) = state::cap_log(fd, &agent_log, state::AGENT_LOG_MAX_BYTES) {
                eprintln!("vrelay: {e}");
            }
        }
    };
    cap();
    let bridge = Arc::new(Bridge::start(&cmd)?);
    let log: vitruvian_relay_connector::bridge::Log = Arc::new(|s: &str| eprintln!("vrelay: {s}"));
    // Keep the Mac awake while we run, if the rules say so (a reload that
    // flips `keep_awake` starts or stops it; dropping it stops it).
    let awake = Arc::new(Awake::system());
    let awake_at_exit = awake.clone();
    if let Err(e) = awake.set(rules.keep_awake) {
        log(&e);
    }
    let link = Link {
        dir: cfg.dir.clone(),
        log_dir: cfg.log_dir.clone(),
        relay_url: cfg.relay_url.clone(),
        tools: bridge.clone(),
        asker: Arc::new(Dialog),
        tokens: Arc::new(FileTokens::new(cfg.clone())),
        rules,
        awake,
        key,
        timing: Timing::default(),
        clock: Arc::new(now_unix),
        rng: Arc::new(Mutex::new(system_rng)),
        log: log.clone(),
        tls: None,
    };
    let ran: Result<()> = rt.block_on(async {
        use tokio::signal::unix::{signal, SignalKind};
        let mut hup = signal(SignalKind::hangup()).map_err(|e| format!("watch SIGHUP: {e}"))?;
        let mut term =
            signal(SignalKind::terminate()).map_err(|e| format!("watch SIGTERM: {e}"))?;
        let (reload_tx, reload_rx) = tokio::sync::mpsc::channel(4);
        tokio::spawn(async move {
            while hup.recv().await.is_some() {
                let _ = reload_tx.try_send(());
            }
        });
        tokio::spawn(async move {
            let mut every = tokio::time::interval(Duration::from_secs(60));
            loop {
                every.tick().await;
                let cap = cap.clone();
                let _ = tokio::task::spawn_blocking(cap).await;
            }
        });
        let (stop_tx, stop_rx) = tokio::sync::watch::channel(false);
        tokio::spawn(async move {
            tokio::select! {
                _ = term.recv() => {}
                _ = tokio::signal::ctrl_c() => {}
            }
            let _ = stop_tx.send(true);
        });
        link.run(reload_rx, stop_rx).await;
        Ok(())
    });
    // Open dialogs were told to close; give their threads a moment, and drop
    // the call tasks (they hold the bridge).
    rt.shutdown_timeout(Duration::from_secs(2));
    // (caffeinate also quits by itself when vrelay does.)
    let _ = awake_at_exit.set(false);
    match Arc::try_unwrap(bridge) {
        Ok(b) => b.stop(),
        // Dropping the last handle kills desktop-commander at once.
        Err(b) => {
            log("stopping desktop-commander without waiting");
            drop(b);
        }
    }
    ran
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
        Some("pause") => cmd_pause(&cfg, true),
        Some("resume") => cmd_pause(&cfg, false),
        Some("reload") => reload_agent(&cfg, "Reloaded rules.toml."),
        Some("run") => cmd_run(&cfg),
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
