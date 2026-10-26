// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

use live_context_hooks::{resolve_state_dir, run_inject_live_context};
use std::io::{self, Read, Write};

fn main() {
    let mut payload = String::new();
    let _ = io::stdin().read_to_string(&mut payload);

    let state_dir = resolve_state_dir();
    let out = run_inject_live_context(state_dir.as_deref());
    print!("{out}");
    let _ = io::stdout().flush();
}
