// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

fn main() {
    std::process::exit(vitruvian_courier_scripts_lib::run_test_copy::run(
        &std::env::args().collect::<Vec<_>>(),
    ));
}
