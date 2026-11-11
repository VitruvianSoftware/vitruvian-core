# Src

## Overview
Component package providing implementation for `apps/web/gods-eye-view/tests/e2e/src`.

## Interface
- `[runner.rs:TestStatus]`
- `[runner.rs:TestCaseResult]`
- `[runner.rs:TierReport]`
- `[runner.rs:SuiteReport]`
- `[runner.rs:OutputFormat]`
- `[runner.rs:RunnerOptions]`
- `[runner.rs:TierFilter]`
- `[runner.rs:find_repo_root]`
- `[runner.rs:parse_args]`
- `[runner.rs:emit_report]`
- `[runner.rs:TestContext]`
- `[runner.rs:run_single_tier]`
- `[runner.rs:parse_json_string]`
- `[runner.rs:json_has_key]`
- `[runner.rs:json_object_has_all_keys]`
- `[tier1.rs:run]`
- `[tier2.rs:run]`
- `[tier3.rs:run]`
- `[tier4.rs:run]`
- `[tier5.rs:run]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- [lib.rs:47]: `assert!(!opts.strict);`
- [lib.rs:48]: `assert!(!opts.verbose);`
- [lib.rs:68]: `assert!(parse_args(&args).is_err());`
- [tier1.rs:491]: `"assert", "buffer", "child_process", "crypto", "dns", "events", "fs", "http",...`

## Side Effects
- [tier1.rs:491]: `"assert", "buffer", "child_process", "crypto", "dns", "events", "fs", "http",...`
- [tier5.rs:141]: `scan_dir_for_pattern(&providers_dir, ".js", "http")`
- [tier5.rs:144]: `|| scan_dir_for_pattern(&src_dir, ".js", "http(s)")`
- [tier5.rs:145]: `|| scan_dir_for_pattern(&src_dir, ".js", "must be http"));`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/tests/e2e/src/...`
