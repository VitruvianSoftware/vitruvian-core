// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use tests_rs_lib::conformance;

#[test]
fn conformance_suite() {
    let args: Vec<String> = std::env::args().collect();
    let paths = conformance::resolve_paths(&args);
    let code = conformance::run_conformance(&paths);
    assert_eq!(code, 0, "conformance checks failed");
}
