// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use std::path::Path;

#[test]
fn test_all_mutation_fixtures_match_real_sources() {
    let app_dir = Path::new("apps/desktop/vitruvian");
    let problems = mutation_checks::stale_fixtures(app_dir);
    assert!(
        problems.is_empty(),
        "These mutations in mutation_checks_rs no longer match the source they quote:\n  {}",
        problems.join("\n  ")
    );
    assert_eq!(mutation_checks::check(app_dir), 0);
    assert_eq!(
        mutation_checks::run_cli(&[
            "--check".to_string(),
            "--app-dir".to_string(),
            "apps/desktop/vitruvian".to_string(),
        ]),
        0
    );
}
