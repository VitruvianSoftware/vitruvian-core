# Hook Tests

## Overview
Component package providing implementation for `tools/ci/src/hook_tests`.

## Interface
- `[common.rs:repo]`
- `[common.rs:jq_dir]`
- `[common.rs:jq]`
- `[common.rs:wired]`
- `[common.rs:is_executable]`
- `[common.rs:planted_break_fails]`

## Invariants
- [block_queue_bypass.rs:90]: `assert!(`
- [block_queue_bypass.rs:179]: `assert!(`
- [block_queue_bypass.rs:206]: `assert!(ok, "unhelpful reason: {why}");`
- [common.rs:40]: `assert!(`
- [common.rs:58]: `std::fs::canonicalize(&j).unwrap_or_else(|e| panic!("JQ_BIN={j}: {e}"))`
- [common.rs:69]: `assert!(o.status.success(), "the hermetic jq does not run");`
- [kube_setup.rs:189]: `assert!(`
- [kube_setup.rs:194]: `assert!(`
- [kube_setup.rs:198]: `assert!(`
- [session_start.rs:163]: `assert!(`

## Side Effects
- [block_queue_bypass.rs:127]: `r#"gh api graphql -f query="mutation { mergePullRequest(input: {pullRequestId...`
- [block_queue_bypass.rs:157]: `r#"gh api graphql -f query="mutation { enqueuePullRequest(input: {pullRequest...`
- [block_queue_bypass.rs:165]: `("fetch main", "git fetch origin main"),`
- [common.rs:81]: `.spawn()`
- [common.rs:82]: `.expect("spawn jq");`
- [kube_setup.rs:152]: `exec(self.command(path, answer, extra))`
- [kube_setup.rs:156]: `fn exec(mut c: Command) -> Ran {`
- [kube_setup.rs:341]: `let joiner = std::thread::spawn(move || {`

## Verification
- Run: `bazel test //tools/ci/src/hook_tests/...`
