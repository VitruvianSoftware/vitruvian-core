// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

use std::env;
use std::process;

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    process::exit(package_release::run_cli(&args));
}
