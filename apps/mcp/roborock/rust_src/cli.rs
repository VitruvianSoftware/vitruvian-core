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

//! `rrctl`: command-line argument parser and command handlers.

use crate::auth::{self, ApiClient, LoginFlow};
use crate::config;
use crate::daemon::{self, ClientError, DaemonClient, DaemonServer, DaemonUnavailable};
use crate::mcp::{self, DaemonApi};
use crate::state::{ServiceOptions, StateStore, VacuumService};
use serde_json::{Map, Value};
use std::fs;
use std::io::Write;
use std::sync::Arc;
use std::time::Duration;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DaemonSubcommand {
    Run,
    Start,
    Stop,
    Status,
}

impl DaemonSubcommand {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Run => "run",
            Self::Start => "start",
            Self::Stop => "stop",
            Self::Status => "status",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Subcommand {
    Setup { email: Option<String>, force: bool },
    Status { json: bool },
    Map { output: String },
    Pause,
    Resume,
    Dock,
    Daemon { action: DaemonSubcommand },
    Mcp,
    Dashboard { no_open: bool },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedArgs {
    pub port: Option<u16>,
    pub command: Subcommand,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ParseOutcome {
    Args(ParsedArgs),
    Help(String),
    Version(String),
    Error(String),
}

pub fn help_text() -> String {
    concat!(
        "usage: rrctl [-h] [--version] [--port PORT] command ...\n\n",
        "Control a Roborock vacuum from this machine.\n\n",
        "positional arguments:\n",
        "  command\n",
        "    setup      log in to Roborock with an emailed code\n",
        "    status     show what the vacuum is doing\n",
        "    map        save the current map as a PNG\n",
        "    pause      pause cleaning\n",
        "    resume     resume a paused clean\n",
        "    dock       send the vacuum back to its dock\n",
        "    daemon     run or manage the background daemon\n",
        "    mcp        serve the MCP tools over stdio\n",
        "    dashboard  open the live dashboard in a browser\n\n",
        "options:\n",
        "  -h, --help   show this help message and exit\n",
        "  --version    show program's version number and exit\n",
        "  --port PORT  daemon port (default 8765, or $VITRUVIAN_ROBOROCK_PORT)\n",
    )
    .to_string()
}

pub fn parse_args(argv: &[String]) -> ParseOutcome {
    let mut port: Option<u16> = None;
    let mut idx = 0;

    while idx < argv.len() {
        let arg = argv[idx].as_str();
        match arg {
            "-h" | "--help" => return ParseOutcome::Help(help_text()),
            "--version" => return ParseOutcome::Version(format!("rrctl {}\n", crate::VERSION)),
            "--port" => {
                idx += 1;
                if idx >= argv.len() {
                    return ParseOutcome::Error(
                        "rrctl: error: argument --port: expected one argument\n".to_string(),
                    );
                }
                let Ok(p) = argv[idx].parse::<u16>() else {
                    return ParseOutcome::Error(format!(
                        "rrctl: error: argument --port: invalid int value: {:?}\n",
                        argv[idx]
                    ));
                };
                port = Some(p);
                idx += 1;
            }
            _ if arg.starts_with('-') => {
                return ParseOutcome::Error(format!(
                    "rrctl: error: unrecognized arguments: {arg}\n"
                ));
            }
            _ => break,
        }
    }

    if idx >= argv.len() {
        return ParseOutcome::Error(
            "rrctl: error: the following arguments are required: command\n".to_string(),
        );
    }

    let sub = argv[idx].as_str();
    let rest = &argv[idx + 1..];

    for arg in rest {
        if arg == "-h" || arg == "--help" {
            return ParseOutcome::Help(help_text());
        }
    }

    match sub {
        "setup" => {
            let mut email = None;
            let mut force = false;
            let mut i = 0;
            while i < rest.len() {
                match rest[i].as_str() {
                    "--force" => {
                        force = true;
                        i += 1;
                    }
                    "--email" => {
                        i += 1;
                        if i >= rest.len() {
                            return ParseOutcome::Error(
                                "rrctl setup: error: argument --email: expected one argument\n"
                                    .to_string(),
                            );
                        }
                        email = Some(rest[i].clone());
                        i += 1;
                    }
                    other => {
                        return ParseOutcome::Error(format!(
                            "rrctl setup: error: unrecognized arguments: {other}\n"
                        ));
                    }
                }
            }
            ParseOutcome::Args(ParsedArgs {
                port,
                command: Subcommand::Setup { email, force },
            })
        }
        "status" => {
            let mut json = false;
            for arg in rest {
                if arg == "--json" {
                    json = true;
                } else {
                    return ParseOutcome::Error(format!(
                        "rrctl status: error: unrecognized arguments: {arg}\n"
                    ));
                }
            }
            ParseOutcome::Args(ParsedArgs {
                port,
                command: Subcommand::Status { json },
            })
        }
        "map" => {
            let mut output = "roborock-map.png".to_string();
            let mut i = 0;
            while i < rest.len() {
                match rest[i].as_str() {
                    "-o" | "--output" => {
                        i += 1;
                        if i >= rest.len() {
                            return ParseOutcome::Error(
                                "rrctl map: error: argument -o/--output: expected one argument\n"
                                    .to_string(),
                            );
                        }
                        output = rest[i].clone();
                        i += 1;
                    }
                    other => {
                        return ParseOutcome::Error(format!(
                            "rrctl map: error: unrecognized arguments: {other}\n"
                        ));
                    }
                }
            }
            ParseOutcome::Args(ParsedArgs {
                port,
                command: Subcommand::Map { output },
            })
        }
        "pause" => ParseOutcome::Args(ParsedArgs {
            port,
            command: Subcommand::Pause,
        }),
        "resume" => ParseOutcome::Args(ParsedArgs {
            port,
            command: Subcommand::Resume,
        }),
        "dock" => ParseOutcome::Args(ParsedArgs {
            port,
            command: Subcommand::Dock,
        }),
        "daemon" => {
            let action = if rest.is_empty() {
                DaemonSubcommand::Run
            } else if rest.len() == 1 {
                match rest[0].as_str() {
                    "run" => DaemonSubcommand::Run,
                    "start" => DaemonSubcommand::Start,
                    "stop" => DaemonSubcommand::Stop,
                    "status" => DaemonSubcommand::Status,
                    other => {
                        return ParseOutcome::Error(format!(
                            "rrctl daemon: error: invalid choice: {other:?} (choose from 'run', 'start', 'stop', 'status')\n"
                        ));
                    }
                }
            } else {
                return ParseOutcome::Error(
                    "rrctl daemon: error: unrecognized arguments\n".to_string(),
                );
            };
            ParseOutcome::Args(ParsedArgs {
                port,
                command: Subcommand::Daemon { action },
            })
        }
        "mcp" => ParseOutcome::Args(ParsedArgs {
            port,
            command: Subcommand::Mcp,
        }),
        "dashboard" => {
            let mut no_open = false;
            for arg in rest {
                if arg == "--no-open" {
                    no_open = true;
                } else {
                    return ParseOutcome::Error(format!(
                        "rrctl dashboard: error: unrecognized arguments: {arg}\n"
                    ));
                }
            }
            ParseOutcome::Args(ParsedArgs {
                port,
                command: Subcommand::Dashboard { no_open },
            })
        }
        other => ParseOutcome::Error(format!(
            "rrctl: error: argument command: invalid choice: {other:?}\n"
        )),
    }
}

pub trait CliClient: DaemonApi {
    fn base_url(&self) -> String;
    fn port(&self) -> u16;
    fn health(&self) -> Option<Map<String, Value>>;
    fn reload(&self) -> Result<Map<String, Value>, ClientError>;
    fn shutdown(&self) -> Result<Map<String, Value>, ClientError>;
}

impl CliClient for DaemonClient {
    fn base_url(&self) -> String {
        DaemonClient::base_url(self)
    }

    fn port(&self) -> u16 {
        self.port
    }

    fn health(&self) -> Option<Map<String, Value>> {
        DaemonClient::health(self)
    }

    fn reload(&self) -> Result<Map<String, Value>, ClientError> {
        DaemonClient::reload(self)
    }

    fn shutdown(&self) -> Result<Map<String, Value>, ClientError> {
        DaemonClient::shutdown(self)
    }
}

pub struct CliHooks {
    pub ensure_running: Box<dyn Fn(Option<u16>) -> Result<Arc<dyn CliClient>, DaemonUnavailable>>,
    pub probe_client: Box<dyn Fn(Option<u16>) -> Result<Arc<dyn CliClient>, config::ConfigError>>,
    pub api_client_factory: Option<Arc<dyn Fn(&str) -> Arc<dyn ApiClient> + Send + Sync>>,
    pub prompt_input: Box<dyn Fn(&str) -> Result<String, String>>,
}

impl Default for CliHooks {
    fn default() -> Self {
        Self {
            ensure_running: Box::new(|port| {
                let c = daemon::ensure_running(port, Duration::from_secs(15))?;
                Ok(Arc::new(c))
            }),
            probe_client: Box::new(|port| {
                let c = DaemonClient::new(port, None, None)?;
                Ok(Arc::new(c))
            }),
            api_client_factory: None,
            prompt_input: Box::new(|prompt| {
                print!("{prompt}");
                let _ = std::io::stdout().flush();
                let mut line = String::new();
                std::io::stdin()
                    .read_line(&mut line)
                    .map_err(|e| e.to_string())?;
                Ok(line.trim().to_string())
            }),
        }
    }
}

#[derive(Debug, Default, Clone)]
pub struct CliExecution {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
}

pub fn format_status(status: &Map<String, Value>) -> String {
    let authenticated = status
        .get("authenticated")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    if !authenticated {
        return status
            .get("hint")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .unwrap_or(auth::SETUP_HINT)
            .to_string();
    }
    let connected = status
        .get("connected")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let state_str = status.get("state").and_then(|v| v.as_str());
    if !connected && state_str.is_none() {
        let err = status
            .get("error")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .unwrap_or("still connecting");
        return format!("Not connected to the vacuum: {err}");
    }

    let device_name = status
        .get("device")
        .and_then(|v| v.as_object())
        .and_then(|d| d.get("name"))
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .unwrap_or("Vacuum");
    let state_display = state_str.filter(|s| !s.is_empty()).unwrap_or("unknown");

    let mut lines = vec![format!("{device_name}: {state_display}")];
    if let Some(battery) = status.get("battery").and_then(|v| v.as_i64()) {
        lines.push(format!("  battery   {battery}%"));
    }
    if let Some(err) = status
        .get("error")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
    {
        lines.push(format!("  error     {err}"));
    }
    let in_cleaning = status
        .get("in_cleaning")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let clean_time_s = status
        .get("clean_time_s")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    if in_cleaning || clean_time_s > 0 {
        let minutes = clean_time_s / 60;
        let area = match status.get("clean_area_m2") {
            Some(Value::Number(n)) => n.to_string(),
            Some(Value::String(s)) => s.clone(),
            _ => "?".to_string(),
        };
        lines.push(format!("  cleaned   {area} m2 in {minutes} min"));
    }
    for (label, key) in [
        ("suction", "fan_speed"),
        ("water", "water_mode"),
        ("route", "mop_route"),
    ] {
        if let Some(val) = status
            .get(key)
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
        {
            lines.push(format!("  {label:<9} {val}"));
        }
    }
    if let Some(rooms_arr) = status.get("rooms").and_then(|v| v.as_array()) {
        let names: Vec<&str> = rooms_arr
            .iter()
            .filter_map(|r| r.get("name").and_then(|v| v.as_str()))
            .collect();
        if !names.is_empty() {
            lines.push(format!("  rooms     {}", names.join(", ")));
        }
    }
    if !connected {
        let err = status
            .get("error")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown");
        lines.push(format!("  (last known; currently unreachable: {err})"));
    }
    lines.join("\n")
}

pub fn run_with_hooks(argv: &[String], hooks: &CliHooks) -> CliExecution {
    let mut out = CliExecution::default();
    let parsed = match parse_args(argv) {
        ParseOutcome::Help(text) => {
            out.stdout.push_str(&text);
            out.exit_code = 0;
            return out;
        }
        ParseOutcome::Version(ver) => {
            out.stdout.push_str(&ver);
            out.exit_code = 0;
            return out;
        }
        ParseOutcome::Error(err) => {
            out.stderr.push_str(&err);
            out.exit_code = 2;
            return out;
        }
        ParseOutcome::Args(args) => args,
    };

    let fail = |out: &mut CliExecution, msg: &str| {
        out.stderr.push_str(&format!("rrctl: {msg}\n"));
        out.exit_code = 1;
    };

    match parsed.command {
        Subcommand::Setup { email, force } => {
            let st = auth::auth_status();
            if st.authenticated && !force {
                out.stdout.push_str(&format!(
                    "Already logged in as {}.\n",
                    config::mask_email(st.email.as_deref().unwrap_or(""))
                ));
                if let Some(ref migrated) = st.migrated_from {
                    out.stdout
                        .push_str(&format!("(Login was copied from {migrated}.)\n"));
                }
                out.stdout
                    .push_str("Use `rrctl setup --force` to log in again.\n");
                out.exit_code = 0;
                return out;
            }
            let resolved_email = match email {
                Some(e) => e,
                None => match (hooks.prompt_input)("Roborock account email: ") {
                    Ok(e) => e,
                    Err(_) => {
                        fail(&mut out, "setup cancelled.");
                        return out;
                    }
                },
            };
            let flow = LoginFlow::new(hooks.api_client_factory.clone());
            if let Err(err) = flow.request_code(&resolved_email) {
                fail(&mut out, err.message());
                return out;
            }
            out.stdout
                .push_str("Roborock has emailed you a verification code.\n");
            let code = match (hooks.prompt_input)("Verification code: ") {
                Ok(c) => c,
                Err(_) => {
                    fail(&mut out, "setup cancelled.");
                    return out;
                }
            };
            if let Err(err) = flow.complete(&resolved_email, &code) {
                fail(&mut out, err.message());
                return out;
            }
            out.stdout.push_str(&format!(
                "Logged in. Credentials saved to {} (readable only by you).\n",
                config::credentials_path().display()
            ));
            if let Ok(probe) = (hooks.probe_client)(parsed.port) {
                if probe.health().is_some() {
                    match probe.reload() {
                        Ok(_) => out
                            .stdout
                            .push_str("The running daemon picked up the new login.\n"),
                        Err(err) => out.stdout.push_str(&format!(
                            "Restart the daemon to use the new login ({err}).\n"
                        )),
                    }
                }
            }
            out.exit_code = 0;
        }
        Subcommand::Status { json } => {
            let client = match (hooks.ensure_running)(parsed.port) {
                Ok(c) => c,
                Err(err) => {
                    fail(&mut out, &err.to_string());
                    return out;
                }
            };
            let doc = match client.status() {
                Ok(d) => d,
                Err(err) => {
                    fail(&mut out, &err.to_string());
                    return out;
                }
            };
            if json {
                let text = serde_json::to_string_pretty(&Value::Object(doc.clone()))
                    .unwrap_or_else(|_| "{}".to_string());
                out.stdout.push_str(&format!("{text}\n"));
            } else {
                out.stdout.push_str(&format!("{}\n", format_status(&doc)));
            }
            let connected = doc
                .get("connected")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            out.exit_code = if connected { 0 } else { 1 };
        }
        Subcommand::Map { output } => {
            let client = match (hooks.ensure_running)(parsed.port) {
                Ok(c) => c,
                Err(err) => {
                    fail(&mut out, &err.to_string());
                    return out;
                }
            };
            let png = match client.map_png() {
                Ok(Some(b)) => b,
                Ok(None) => {
                    fail(
                        &mut out,
                        "the vacuum has not sent a map yet. Try again in a few seconds.",
                    );
                    return out;
                }
                Err(err) => {
                    fail(&mut out, &err.to_string());
                    return out;
                }
            };
            if output == "-" {
                let _ = std::io::stdout().write_all(&png);
                out.exit_code = 0;
                return out;
            }
            let path = config::expand_tilde(&output);
            if let Err(err) = fs::write(&path, &png) {
                fail(&mut out, &err.to_string());
                return out;
            }
            out.stdout
                .push_str(&format!("Map saved to {}\n", path.display()));
            out.exit_code = 0;
        }
        Subcommand::Pause | Subcommand::Resume | Subcommand::Dock => {
            let (action, done) = match parsed.command {
                Subcommand::Pause => ("pause", "Paused."),
                Subcommand::Resume => ("resume", "Resumed."),
                Subcommand::Dock => ("dock", "Returning to the dock."),
                _ => unreachable!(),
            };
            let client = match (hooks.ensure_running)(parsed.port) {
                Ok(c) => c,
                Err(err) => {
                    fail(&mut out, &err.to_string());
                    return out;
                }
            };
            if let Err(err) = client.command(action, None) {
                fail(&mut out, &err.to_string());
                return out;
            }
            out.stdout.push_str(&format!("{done}\n"));
            out.exit_code = 0;
        }
        Subcommand::Daemon { action } => match action {
            DaemonSubcommand::Run => {
                let port = match parsed.port {
                    Some(p) => p,
                    None => match config::daemon_port() {
                        Ok(p) => p,
                        Err(err) => {
                            fail(&mut out, &err.to_string());
                            return out;
                        }
                    },
                };
                let token = match config::load_or_create_token() {
                    Ok(t) => t,
                    Err(err) => {
                        fail(&mut out, &err.to_string());
                        return out;
                    }
                };
                let store = Arc::new(StateStore::new());
                let service = Arc::new(VacuumService::new(
                    store.clone(),
                    None,
                    ServiceOptions::default(),
                ));
                let mut server =
                    match DaemonServer::start(port, store, service.clone(), token, None) {
                        Ok(s) => s,
                        Err(err) => {
                            fail(&mut out, &err.to_string());
                            return out;
                        }
                    };
                service.start();
                server.stop_signal().wait();
                service.stop();
                server.shutdown();
                out.exit_code = 0;
            }
            DaemonSubcommand::Status => {
                let probe = match (hooks.probe_client)(parsed.port) {
                    Ok(p) => p,
                    Err(err) => {
                        fail(&mut out, &err.to_string());
                        return out;
                    }
                };
                let Some(health) = probe.health() else {
                    out.stdout.push_str(&format!(
                        "Daemon is not running on port {}.\n",
                        probe.port()
                    ));
                    out.exit_code = 1;
                    return out;
                };
                let version = health
                    .get("version")
                    .and_then(|v| v.as_str())
                    .unwrap_or(crate::VERSION);
                let pid = health.get("pid").and_then(|v| v.as_u64()).unwrap_or(0);
                out.stdout.push_str(&format!(
                    "Daemon {version} is running on {} (pid {pid}).\n",
                    probe.base_url()
                ));
                out.exit_code = 0;
            }
            DaemonSubcommand::Stop => {
                let probe = match (hooks.probe_client)(parsed.port) {
                    Ok(p) => p,
                    Err(err) => {
                        fail(&mut out, &err.to_string());
                        return out;
                    }
                };
                if probe.health().is_none() {
                    out.stdout.push_str("Daemon is not running.\n");
                    out.exit_code = 0;
                    return out;
                }
                if let Err(err) = probe.shutdown() {
                    fail(&mut out, &err.to_string());
                    return out;
                }
                out.stdout.push_str("Daemon stopped.\n");
                out.exit_code = 0;
            }
            DaemonSubcommand::Start => {
                let started = match (hooks.ensure_running)(parsed.port) {
                    Ok(c) => c,
                    Err(err) => {
                        fail(&mut out, &err.to_string());
                        return out;
                    }
                };
                out.stdout.push_str(&format!(
                    "Daemon is running on {}. Log: {}\n",
                    started.base_url(),
                    config::log_path().display()
                ));
                out.exit_code = 0;
            }
        },
        Subcommand::Mcp => {
            let server = mcp::build_server(None);
            let _ = server.run_stdio();
            out.exit_code = 0;
        }
        Subcommand::Dashboard { no_open } => {
            let client = match (hooks.ensure_running)(parsed.port) {
                Ok(c) => c,
                Err(err) => {
                    fail(&mut out, &err.to_string());
                    return out;
                }
            };
            let token = config::read_token().unwrap_or_default();
            let url = format!("{}/#token={token}", client.base_url());
            if no_open {
                out.stdout.push_str(&format!("{url}\n"));
                out.exit_code = 0;
                return out;
            }
            out.stdout
                .push_str(&format!("Opening {}/\n", client.base_url()));
            out.exit_code = 0;
        }
    }

    out
}

pub fn run(argv: &[String]) -> i32 {
    let hooks = CliHooks::default();
    let exec = run_with_hooks(argv, &hooks);
    if !exec.stdout.is_empty() {
        print!("{}", exec.stdout);
    }
    if !exec.stderr.is_empty() {
        eprint!("{}", exec.stderr);
    }
    exec.exit_code
}
