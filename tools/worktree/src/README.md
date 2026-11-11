# Src

## Overview
Component package providing implementation for `tools/worktree/src`.

## Interface
- `[lib.rs:WORKTREE_SH]`
- `[lib.rs:WorktreeEntry]`
- `[lib.rs:WorktreeEntryBytes]`
- `[lib.rs:extract_usage]`
- `[lib.rs:slug]`
- `[lib.rs:slug_bytes]`
- `[lib.rs:md5_hex]`
- `[lib.rs:format_utc_hm]`
- `[lib.rs:strip_ansi_sgr_bytes]`
- `[lib.rs:strip_ansi_sgr]`
- `[lib.rs:clean_landed_output_bytes]`
- `[lib.rs:clean_landed_output]`
- `[lib.rs:parse_worktrees_porcelain_bytes]`
- `[lib.rs:parse_worktrees_porcelain]`
- `[lib.rs:resolve_output_root_bytes]`
- `[lib.rs:resolve_output_root]`
- `[lib.rs:extract_primary_bazelrc_cache_bytes]`
- `[lib.rs:extract_primary_bazelrc_cache_lines]`
- `[lib.rs:real_path_bytes]`
- `[lib.rs:real_path]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //tools/worktree/src/...`
