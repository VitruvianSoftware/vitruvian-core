# Release Hold

## Overview
Component package providing implementation for `tools/ci/src/release_hold`.

## Interface
- `[lib.rs:run]`

## Invariants
- None

## Side Effects
- [tests.rs:45]: `echo "gh: HTTP 502 (something went wrong)" >&2`
- [tests.rs:52]: `echo "gh: HTTP 500 (internal error)" >&2`
- [tests.rs:165]: `assert_has(&o.stdout, "HTTP 502", "gh's own error is quoted");`

## Verification
- Run: `bazel test //tools/ci/src/release_hold/...`
