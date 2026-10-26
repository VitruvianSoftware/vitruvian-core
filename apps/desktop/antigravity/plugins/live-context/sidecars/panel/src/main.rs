// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

use live_context_sidecar::build_ephemeral_context_payload;
use live_context_sidecar::openui::{compile_to_html, to_openui_lang, RenderOpts};
use serde_json::{json, Value};
use std::io::{self, Read};

fn read_stdin_json() -> Value {
    let mut buf = String::new();
    let _ = io::stdin().read_to_string(&mut buf);
    if buf.trim().is_empty() {
        json!({})
    } else {
        serde_json::from_str(&buf).unwrap_or_else(|_| json!({}))
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let cmd = args.get(1).map(|s| s.as_str()).unwrap_or("openui");
    let input = read_stdin_json();

    match cmd {
        "summarise" => {
            let git = input.get("git").and_then(|v| v.as_object());
            let github = input.get("github").and_then(|v| v.as_object());
            let settings = input.get("settings").and_then(|v| v.as_object());
            let out = build_ephemeral_context_payload(git, github, settings);
            println!("{}", serde_json::to_string(&out).unwrap_or_default());
        }
        "html" => {
            let dsl = to_openui_lang(&input);
            let html = compile_to_html(
                &dsl,
                &RenderOpts {
                    title: Some("Live Context".to_string()),
                    ..Default::default()
                },
            );
            print!("{html}");
        }
        _ => {
            print!("{}", to_openui_lang(&input));
        }
    }
}
