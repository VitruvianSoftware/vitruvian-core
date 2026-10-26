// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

use ralph_stop::{handle_stop_payload, resolve_state_dir};
use std::env;
use std::io::{self, Read, Write};

fn main() {
    let mut payload = String::new();
    let _ = io::stdin().read_to_string(&mut payload);

    let app_data_dir = env::var("ANTIGRAVITY_APP_DATA_DIR").ok();
    let home = env::var("HOME").ok();
    let state_dir = resolve_state_dir(app_data_dir.as_deref(), home.as_deref());

    let out = handle_stop_payload(&payload, state_dir.as_deref());
    print!("{out}");
    let _ = io::stdout().flush();
}
