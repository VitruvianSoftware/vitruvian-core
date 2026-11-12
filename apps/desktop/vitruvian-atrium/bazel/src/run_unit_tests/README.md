# Run Unit Tests

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/bazel/src/run_unit_tests`.

## Interface
- `[lib.rs:Config]`
- `[lib.rs:parse_args]`
- `[lib.rs:count_expected_suites_in_test_groups]`
- `[lib.rs:count_expected_suites]`
- `[lib.rs:is_suite_report_line]`
- `[lib.rs:count_reported_suites]`
- `[lib.rs:run_cli]`
- `[lib.rs:test_preferences]`
- `[lib.rs:changed_test_preferences]`

## Invariants
- [lib.rs:421]: `assert!(changed_test_preferences(&before, &test_preferences(&dir)).is_empty());`
- [lib.rs:449]: `assert!(changed_test_preferences(&before, &test_preferences(&dir))`
- [lib.rs:465]: `assert!(parse_args(&[`

## Side Effects
- [lib.rs:195]: `.spawn()`
- [lib.rs:196]: `.map_err(|e| format!("spawn test binary: {}", e))?;`
- [lib.rs:202]: `let t_out = thread::spawn(move || {`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/bazel/src/run_unit_tests/...`
