// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

use evaluate_rules::{handle_hookify_payload, resolve_app_dir};
use std::env;
use std::io::{self, Read, Write};
use std::thread;

fn main() {
    let mut payload = String::new();
    let _ = io::stdin().read_to_string(&mut payload);

    let app_data_dir = env::var("ANTIGRAVITY_APP_DATA_DIR").ok();
    let home = env::var("HOME").ok();
    let app_dir = resolve_app_dir(app_data_dir.as_deref(), home.as_deref());

    // Regex backtracking recurses; give it room beyond the main thread's.
    let out = thread::Builder::new()
        .stack_size(256 << 20)
        .spawn(move || handle_hookify_payload(&payload, app_dir.as_deref()))
        .ok()
        .and_then(|h| h.join().ok())
        .unwrap_or_else(|| "{}".to_string());
    print!("{out}");
    let _ = io::stdout().flush();
}
