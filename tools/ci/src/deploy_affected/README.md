# Deploy Affected

## Overview
Component package providing implementation for `tools/ci/src/deploy_affected`.

## Interface
- `[lib.rs:run]`

## Invariants
- [tests.rs:221]: `assert!(!log.exists(), "target-determinator must not run");`
- [tests.rs:282]: `assert!(`
- [tests.rs:311]: `assert!(`

## Side Effects
- [lib.rs:132]: `.spawn()`
- [lib.rs:137]: `let writer = std::thread::spawn(move || {`
- [lib.rs:220]: `Command::new("curl")`
- [tests.rs:416]: `--before-query-error-behavior=ignore-and-build-all\n{sha}\n"`
- [tests.rs:444]: `let plain = fx.work.join("not-exec");`

## Verification
- Run: `bazel test //tools/ci/src/deploy_affected/...`
