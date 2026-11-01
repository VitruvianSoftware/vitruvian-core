// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

use security_guidance_sidecar::openui::{compile_to_html, to_openui_lang, RenderOpts};
use security_guidance_sidecar::{json as hook_json, summarise_security_state, SecurityStore};
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
            // The hook library has its own std-only JSON type.
            let input = hook_json::parse(&input.to_string()).unwrap_or_default();
            let out = summarise_security_state(&SecurityStore::from_json(&input));
            println!("{}", out.to_json());
        }
        "html" => {
            let dsl = to_openui_lang(&input);
            let html = compile_to_html(
                &dsl,
                &RenderOpts {
                    title: Some("Security Guidance".to_string()),
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
