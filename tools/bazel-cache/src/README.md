# Src

## Overview
Component package providing implementation for `tools/bazel-cache/src`.

## Interface
- `[lib.rs:md5_hex]`
- `[lib.rs:md5_of]`
- `[lib.rs:md5_of_bytes]`
- `[lib.rs:is_hex32_bytes]`
- `[lib.rs:is_hex32]`
- `[lib.rs:human]`
- `[lib.rs:workspace_of]`
- `[lib.rs:live_pid_bytes]`
- `[lib.rs:live_pid]`
- `[lib.rs:used_within_bytes]`
- `[lib.rs:used_within]`
- `[lib.rs:last_used_bytes]`
- `[lib.rs:last_used]`
- `[lib.rs:size_of_bytes]`
- `[lib.rs:size_of]`
- `[lib.rs:Verdict]`
- `[lib.rs:Classification]`
- `[lib.rs:LiveState]`
- `[lib.rs:classify_base]`
- `[lib.rs:classify_root]`
- `[lib.rs:StatusEnv]`
- `[lib.rs:CacheEntry]`
- `[lib.rs:CacheStatusReport]`
- `[lib.rs:discover_cache_candidates]`
- `[lib.rs:collect_cache_status]`
- `[lib.rs:format_cache_status_text]`
- `[lib.rs:format_cache_status_json]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //tools/bazel-cache/src/...`
