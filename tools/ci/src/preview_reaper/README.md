# Preview Reaper

## Overview
Component package providing implementation for `tools/ci/src/preview_reaper`.

## Interface
- `[lib.rs:run]`

## Invariants
- None

## Side Effects
- [lib.rs:215]: `let curl_bin = env_or("CURL", b"curl");`
- [lib.rs:218]: `// Trimmed once, here: curl is sent this key and the redaction looks for`

## Verification
- Run: `bazel test //tools/ci/src/preview_reaper/...`
