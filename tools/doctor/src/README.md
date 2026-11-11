# Src

## Overview
Component package providing implementation for `tools/doctor/src`.

## Interface
- `[lib.rs:GLYPH_OK]`
- `[lib.rs:GLYPH_WARN]`
- `[lib.rs:GLYPH_FAIL]`
- `[lib.rs:Colors]`
- `[lib.rs:Options]`
- `[lib.rs:parse_args]`
- `[lib.rs:csv_to_keys]`
- `[lib.rs:parse_bazelversion]`
- `[lib.rs:parse_nvmrc]`
- `[lib.rs:parse_package_json_pnpm]`
- `[lib.rs:parse_gomod]`
- `[lib.rs:extract_version]`
- `[lib.rs:field]`
- `[lib.rs:Verdict]`
- `[lib.rs:compare_versions]`
- `[lib.rs:tool_binary]`
- `[lib.rs:is_pinned]`
- `[lib.rs:fix_hint]`
- `[lib.rs:head_lines]`
- `[lib.rs:bazel_build_label]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //tools/doctor/src/...`
