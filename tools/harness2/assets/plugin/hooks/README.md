# Hooks

## Overview
Component package providing implementation for `tools/harness2/assets/plugin/hooks`.

## Interface
- `[pre-invocation.sh:script entrypoint]`
- `[pre-tool-use.sh:script entrypoint]`
- `[stop-check.sh:script entrypoint]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //tools/harness2/assets/plugin/hooks/...`
