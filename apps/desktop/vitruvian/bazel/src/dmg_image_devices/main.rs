// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use std::env;
use std::io::{self, Read};
use std::process;

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.is_empty() || args[0].is_empty() {
        eprintln!("usage: dmg-image-devices.sh <image-path>");
        process::exit(2);
    }
    let mut input = String::new();
    if let Err(e) = io::stdin().read_to_string(&mut input) {
        eprintln!("read stdin: {}", e);
        process::exit(1);
    }
    for dev in dmg_image_devices::extract_devices(&input, &args[0]) {
        println!("{}", dev);
    }
}
