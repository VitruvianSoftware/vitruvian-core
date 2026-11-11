# Bad Dir

## Overview
Component package providing implementation for `tools/lint-naming/testdata/violations/bad_dir`.

## Interface
- `[create_app.sh:script entrypoint]`
- `[net-hubs.go:Hub]`
- `[stream-hook.py:stream]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //tools/lint-naming/testdata/violations/bad_dir/...`
