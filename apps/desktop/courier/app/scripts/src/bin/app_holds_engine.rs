// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

fn main() {
    std::process::exit(courier_scripts_lib::app_holds_engine::run(
        &std::env::args().collect::<Vec<_>>(),
    ));
}
