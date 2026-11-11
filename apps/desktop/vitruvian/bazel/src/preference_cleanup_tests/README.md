# Preference Cleanup Tests

## Overview
Component package providing implementation for `apps/desktop/vitruvian/bazel/src/preference_cleanup_tests`.

## Interface
- `[lib.rs:TEST_PREF_PREFIXES]`
- `[lib.rs:METRICS_TESTS_PLIST]`
- `[lib.rs:is_test_preference_filename]`
- `[lib.rs:remove_matching_test_preferences]`
- `[lib.rs:count_surviving_test_preferences]`
- `[lib.rs:discard_test_preferences_with_sleep]`
- `[lib.rs:discard_test_preferences]`
- `[lib.rs:run_preference_cleanup_test_suite]`
- `[lib.rs:run_cli]`

## Invariants
- [lib.rs:214]: `assert!(is_test_preference_filename("vitru.tests.first.plist"));`
- [lib.rs:215]: `assert!(is_test_preference_filename(`
- [lib.rs:218]: `assert!(is_test_preference_filename("metrics-tests.plist"));`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian/bazel/src/preference_cleanup_tests/...`
