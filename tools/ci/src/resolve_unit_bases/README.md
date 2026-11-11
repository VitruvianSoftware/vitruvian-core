# Resolve Unit Bases

## Overview
Component package providing implementation for `tools/ci/src/resolve_unit_bases`.

## Interface
- `[lib.rs:run]`

## Invariants
- [tests.rs:129]: `panic!("no unit_bases line: {o:?}");`
- [tests.rs:161]: `assert!(!got.contains(r#""app":"shaNEW""#), "changelog trap: {got}");`
- [tests.rs:234]: `assert!(!got.contains(r#""app""#), "app must be omitted: {got}");`

## Side Effects
- [tests.rs:304]: `"a full window must not query the legacy workflow"`
- [tests.rs:306]: `// With room for 9 more, the legacy query asks for exactly that many.`

## Verification
- Run: `bazel test //tools/ci/src/resolve_unit_bases/...`
