// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use std::env;
use std::process;

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    process::exit(helper_version_plist::run_cli(&args));
}
