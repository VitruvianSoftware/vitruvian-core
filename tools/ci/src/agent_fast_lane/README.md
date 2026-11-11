# Agent Fast Lane

## Overview
Component package providing implementation for `tools/ci/src/agent_fast_lane`.

## Interface
- `[lib.rs:run]`

## Invariants
- [lib.rs:195]: `assert!(r.is_empty());`
- [lib.rs:218]: `assert!(parse_json_string_array(b"\"agent-fast-lane\"").is_none());`
- [lib.rs:223]: `assert!(parse_json_string_array(b"not json").is_none());`
- [tests.rs:47]: `assert!(`
- [tests.rs:79]: `assert!(o.code == 0 && said(&o, "verdict=full"), "{what}: got {o:?}");`
- [tests.rs:80]: `assert!(`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/ci/src/agent_fast_lane/...`
