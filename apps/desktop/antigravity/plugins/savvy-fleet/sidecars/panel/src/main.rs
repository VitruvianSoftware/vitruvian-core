// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

use savvy_fleet_sidecar::openui::{compile_to_html, to_openui_lang, RenderOptions};
use savvy_fleet_sidecar::summarise_fleet_state;
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
        "summarise" => {
            let state = summarise_fleet_state(&input);
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
