# Bisect Culprit

## Overview
Component package providing implementation for `tools/ci/src/bisect_culprit`.

## Interface
- `[lib.rs:run]`

## Invariants
- None

## Side Effects
- [lib.rs:248]: `let mut child = match cmd.spawn() {`
- [lib.rs:263]: `handles.push(std::thread::spawn(move || {`

## Verification
- Run: `bazel test //tools/ci/src/bisect_culprit/...`
