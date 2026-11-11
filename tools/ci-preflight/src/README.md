# Src

## Overview
Component package providing implementation for `tools/ci-preflight/src`.

## Interface
- `[lib.rs:GLYPH_OK]`
- `[lib.rs:GLYPH_FAIL]`
- `[lib.rs:GLYPH_WARN]`
- `[lib.rs:GLYPH_UNKNOWN]`
- `[lib.rs:init_locale]`
- `[lib.rs:strcoll_cmp]`
- `[lib.rs:sort_u_locale]`
- `[lib.rs:Colors]`
- `[lib.rs:help_text]`
- `[lib.rs:pad_right_bytes]`
- `[lib.rs:is_posix_space]`
- `[lib.rs:split_lines_bytes]`
- `[lib.rs:is_pr_triggered_bytes]`
- `[lib.rs:extract_refs_from_bytes]`
- `[lib.rs:pr_triggered]`
- `[lib.rs:refs_in]`
- `[lib.rs:matches_workflow_glob_bytes]`
- `[lib.rs:matches_workflow_glob]`
- `[lib.rs:has_line]`
- `[lib.rs:has_line_bytes]`

## Invariants
- None

## Side Effects
- [lib.rs:444]: `.spawn()`
- [lib.rs:481]: `.spawn()`
- [lib.rs:495]: `.spawn()`

## Verification
- Run: `bazel test //tools/ci-preflight/src/...`
