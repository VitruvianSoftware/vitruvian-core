# Src

## Overview
Component package providing implementation for `tools/secret-scan/src`.

## Interface
- `[lib.rs:usage]`
- `[lib.rs:Finding]`
- `[lib.rs:format_findings]`
- `[lib.rs:Mode]`
- `[lib.rs:Parsed]`
- `[lib.rs:parse_args]`
- `[lib.rs:locate_tools]`
- `[lib.rs:run]`

## Invariants
- [lib.rs:490]: `assert!(matches!(parse_args(&a(&["--range"])), Parsed::Usage(_)));`
- [lib.rs:496]: `assert!(u.starts_with("secret-scan.sh — look for secrets"));`
- [lib.rs:497]: `assert!(u.contains(`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/secret-scan/src/...`
