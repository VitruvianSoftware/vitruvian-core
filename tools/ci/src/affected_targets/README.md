# Affected Targets

## Overview
Component package providing implementation for `tools/ci/src/affected_targets`.

## Interface
- `[lib.rs:run]`

## Invariants
- None

## Side Effects
- [lib.rs:82]: `match cmd.spawn() {`
- [lib.rs:118]: `match cmd.spawn() {`
- [lib.rs:152]: `match cmd.spawn() {`

## Verification
- Run: `bazel test //tools/ci/src/affected_targets/...`
