# Src

## Overview
Component package providing implementation for `tools/gomod/src`.

## Interface
- `[lib.rs:GLYPH_OK]`
- `[lib.rs:GLYPH_FAIL]`
- `[lib.rs:DEFAULT_ROOTS]`
- `[lib.rs:Palette]`
- `[lib.rs:Mode]`
- `[lib.rs:ParseOutcome]`
- `[lib.rs:ParseOutcomeOs]`
- `[lib.rs:CollectError]`
- `[lib.rs:CollectErrorOs]`
- `[lib.rs:locale_cmp]`
- `[lib.rs:help_text]`
- `[lib.rs:parse_args_os]`
- `[lib.rs:parse_args]`
- `[lib.rs:posix_dirname_bytes]`
- `[lib.rs:posix_dirname]`
- `[lib.rs:logical_cd_bytes]`
- `[lib.rs:logical_cd]`
- `[lib.rs:indent_diff_bytes]`
- `[lib.rs:indent_diff]`
- `[lib.rs:is_transient_network_error_file]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //tools/gomod/src/...`
