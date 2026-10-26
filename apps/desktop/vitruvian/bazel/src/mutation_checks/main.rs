// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    std::process::exit(mutation_checks::run_cli(&args));
}
