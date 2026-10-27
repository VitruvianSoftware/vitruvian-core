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

use mcp_slack_rs_lib::auth::{
    create_token_verifier, full_scope_string, TokenVerifier, TokenVerifierConfig,
};
use mcp_slack_rs_lib::config::{resolve_config, TransportMode};
use mcp_slack_rs_lib::http_transport::{start_http_transport, McpServer};
use mcp_slack_rs_lib::slack_client::SlackClient;
use mcp_slack_rs_lib::tools::tools_for;
use std::collections::HashMap;
use std::io::{BufRead, Write};
use std::sync::Arc;
use std::time::Duration;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    for arg in &args {
        if arg == "--help" || arg == "-h" {
            println!("mcp-slack v2.0.0 - Model Context Protocol server for Slack");
            println!("Usage: mcp-slack-rs [--help] [--version]");
            println!("Configured via environment variables (MCP_TRANSPORT=stdio|http, SLACK_BOT_TOKEN, SLACK_TEAM_ID, etc.).");
            return;
        }
        if arg == "--version" || arg == "-V" {
            println!("mcp-slack 2.0.0");
            return;
        }
    }

    let env_map: HashMap<String, String> = std::env::vars().collect();
    let config = match resolve_config(&env_map) {
        Ok(cfg) => cfg,
        Err(err) => {
            eprintln!("Configuration error: {err}");
            std::process::exit(1);
        }
    };

    let client = Arc::new(SlackClient::new(
        config.slack.clone(),
        config.channel_guard.clone(),
        config.write_token,
    ));

    let advertised_tools = tools_for(&config);
    let advertised_tools_count = advertised_tools.len();

    let client_for_factory = client.clone();
    let tools_for_factory = advertised_tools.clone();
    let create_server = move || {
        McpServer::with_slack(
            "mcp-slack",
            "2.0.0",
            client_for_factory.clone(),
            tools_for_factory.clone(),
        )
    };

    if config.transport == TransportMode::Http {
        let http_cfg = config.http.clone().expect("HTTP config present");

        if let Err(err) = client.verify_allowlist_visibility() {
            eprintln!("Allow-list verification failed: {err}");
            std::process::exit(1);
        }

        let verifier: Arc<dyn TokenVerifier> = match create_token_verifier(TokenVerifierConfig {
            issuer: http_cfg.issuer.clone(),
            project_id: http_cfg.project_id.clone(),
            allowed_subjects: http_cfg.allowed_subjects.clone(),
            allowed_client_id: http_cfg.allowed_client_id.clone(),
            jwks_uri: None,
            key_source: None,
            jwks_timeout_ms: None,
        }) {
            Ok(v) => Arc::new(v),
            Err(err) => {
                eprintln!("Configuration error: {err}");
                std::process::exit(1);
            }
        };

        let _listener = match start_http_transport(create_server, http_cfg.clone(), verifier) {
            Ok(h) => h,
            Err(err) => {
                eprintln!("Fatal error starting HTTP transport: {err}");
                std::process::exit(1);
            }
        };

        eprint!(
            "mcp-slack server v2.0.0 running on http :{} ({} tools, {} channels allow-listed)\n",
            http_cfg.port,
            advertised_tools_count,
            config.channel_guard.allowed.len()
        );
        eprint!(
            "  issuer:   {}\n  project:  {}\n  serving:  {} allowed subject(s)\n  expects scope: {}\n",
            http_cfg.issuer,
            http_cfg.project_id,
            http_cfg.allowed_subjects.len(),
            full_scope_string(&http_cfg.project_id)
        );

        loop {
            std::thread::sleep(Duration::from_secs(3600));
        }
    }

    let server = create_server();
    eprint!(
        "mcp-slack server v2.0.0 running on stdio ({} tools)\n",
        advertised_tools_count
    );

    let stdin = std::io::stdin();
    let mut stdout = std::io::stdout();
    for line in stdin.lock().lines() {
        let line = match line {
            Ok(l) => l,
            Err(_) => break,
        };
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        match server.handle_jsonrpc_message(trimmed) {
            Ok(Some(resp)) => {
                let _ = writeln!(stdout, "{}", resp);
                let _ = stdout.flush();
            }
            Ok(None) => {}
            Err(err) => {
                eprintln!("mcp-slack stdio error: {err}");
            }
        }
    }
}
