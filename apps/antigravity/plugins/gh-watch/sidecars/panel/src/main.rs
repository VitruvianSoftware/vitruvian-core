// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

use gh_watch_sidecar::openui::{compile_to_html, to_openui_lang, RenderOptions};
use gh_watch_sidecar::{clean_settings, decide, extract_failure_excerpt, DEFAULT_HOLD_MS};
use serde_json::{json, Value};
use std::env;
use std::io::{self, Read};

fn read_stdin_json() -> Value {
    let mut buf = String::new();
    let _ = io::stdin().read_to_string(&mut buf);
    serde_json::from_str(&buf).unwrap_or_else(|_| json!({}))
}

fn main() {
    let cmd = env::args().nth(1).unwrap_or_else(|| "openui".to_string());
    let input = read_stdin_json();
    match cmd.as_str() {
        "decide" => {
            let prev = input.get("prev");
            let snap = input.get("snap").unwrap_or(&input);
            let now = input.get("now").and_then(|v| v.as_i64()).unwrap_or(0);
            let hold_ms = input
                .get("holdMs")
                .and_then(|v| v.as_i64())
                .unwrap_or(DEFAULT_HOLD_MS);
            let out = decide(prev, snap, now, hold_ms);
            println!("{}", serde_json::to_string_pretty(&out).unwrap_or_default());
        }
        "clean-settings" => {
            let out = clean_settings(Some(&input), None);
            println!("{}", serde_json::to_string_pretty(&out).unwrap_or_default());
        }
        "extract-log" => {
            let raw = input.get("log").and_then(|v| v.as_str()).unwrap_or("");
            let max_lines = input.get("maxLines").and_then(|v| v.as_u64()).unwrap_or(40) as usize;
            println!("{}", extract_failure_excerpt(raw, max_lines));
        }
        "html" => {
            let dsl = to_openui_lang(Some(&input));
            let html = compile_to_html(&dsl, &json!({}), &RenderOptions::default());
            print!("{html}");
        }
        _ => {
            let dsl = to_openui_lang(Some(&input));
            print!("{dsl}");
        }
    }
}
