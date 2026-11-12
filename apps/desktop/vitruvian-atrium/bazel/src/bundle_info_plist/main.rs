// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use std::env;
use std::process;

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let config = match bundle_info_plist::parse_args(&args) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{}", e);
            process::exit(2);
        }
    };
    if let Err(e) = bundle_info_plist::run(&config) {
        eprintln!("{}", e);
        process::exit(1);
    }
}
