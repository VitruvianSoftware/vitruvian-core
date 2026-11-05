// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

use serde_json::{json, Value};
use std::env;
use std::io::{self, Read};
use worktree_band_sidecar::openui::{compile_to_html, to_openui_lang, RenderOptions};
use worktree_band_sidecar::summarise_worktrees;

fn read_stdin_json() -> Value {
    let mut buf = String::new();
    let _ = io::stdin().read_to_string(&mut buf);
    serde_json::from_str(&buf).unwrap_or_else(|_| json!({}))
}

fn main() {
    let cmd = env::args().nth(1).unwrap_or_else(|| "openui".to_string());
    let input = read_stdin_json();
    match cmd.as_str() {
        "summarise" => {
            let arr = input
                .get("worktrees")
                .and_then(|v| v.as_array())
                .or_else(|| input.as_array())
                .map(|v| v.as_slice());
            let state = summarise_worktrees(arr);
            println!(
                "{}",
                serde_json::to_string_pretty(&state).unwrap_or_default()
            );
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
