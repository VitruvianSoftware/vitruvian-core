// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

use session_worktree::{handle_payload, resolve_inbox_dir};
use std::env;
use std::io::{self, Read, Write};

fn main() {
    let mut payload = Vec::new();
    let _ = io::stdin().read_to_end(&mut payload);

    print!("{{}}");
    let _ = io::stdout().flush();

    let home = env::var("HOME").ok();
    if let Some(inbox_dir) = resolve_inbox_dir(home.as_deref()) {
        let _ = handle_payload(&payload, &inbox_dir);
    }
}
