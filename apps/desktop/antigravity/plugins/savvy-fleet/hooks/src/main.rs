// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

use std::env;
use std::io::{self, Read, Write};
use track_subagent::{handle_payload, resolve_inbox_dir};

fn main() {
    let mut payload = Vec::new();
    let _ = io::stdin().read_to_end(&mut payload);

    print!("{{}}");
    let _ = io::stdout().flush();

    let app_data_dir = env::var("ANTIGRAVITY_APP_DATA_DIR").ok();
    let home = env::var("HOME").ok();
    if let Some(inbox_dir) = resolve_inbox_dir(app_data_dir.as_deref(), home.as_deref()) {
        let _ = handle_payload(&payload, &inbox_dir);
    }
}
