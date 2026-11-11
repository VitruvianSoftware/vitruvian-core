# Emitters

## Overview
Component package providing implementation for `tools/sdk-codegen/src/emitters`.

## Interface
- `[go.rs:exported]`
- `[go.rs:emit]`
- `[mod.rs:Emitter]`
- `[mod.rs:all]`
- `[plain.rs:PKind]`
- `[plain.rs:kind]`
- `[plain.rs:PField]`
- `[plain.rs:Shape]`
- `[plain.rs:Entry]`
- `[plain.rs:Plain]`
- `[plain.rs:adapt]`
- `[python.rs:header]`
- `[python.rs:safe]`
- `[python.rs:title_opt]`
- `[python.rs:constant]`
- `[python.rs:groups]`
- `[python.rs:emit]`
- `[python.rs:SHAPES]`
- `[rust.rs:words]`
- `[rust.rs:type_name]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //tools/sdk-codegen/src/emitters/...`
