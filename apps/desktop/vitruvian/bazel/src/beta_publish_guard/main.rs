// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use std::env;
use std::path::PathBuf;
use std::process;

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let tag = args.first().map(|s| s.as_str()).unwrap_or("");
    let new_sha = args.get(1).map(|s| s.as_str()).unwrap_or("");
    let cwd = env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    process::exit(beta_publish_guard::check_beta_publish(&cwd, tag, new_sha));
}
