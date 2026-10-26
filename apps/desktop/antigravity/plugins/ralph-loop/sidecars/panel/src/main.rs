// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

use ralph_loop_sidecar::openui::{compile_to_html, to_openui_lang, RenderOpts};
use ralph_loop_sidecar::summarise_loops;
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
            let loops = input
                .get("loops")
                .or(Some(&input))
                .and_then(|v| v.as_array())
                .cloned()
                .unwrap_or_default();
            let out = summarise_loops(&loops);
            println!("{}", serde_json::to_string(&out).unwrap_or_default());
        }
        "html" => {
            let dsl = to_openui_lang(&input);
            let html = compile_to_html(
                &dsl,
                &RenderOpts {
                    title: Some("Ralph Loop".to_string()),
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
