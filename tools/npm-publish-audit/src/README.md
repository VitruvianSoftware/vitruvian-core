# Src

## Overview
Component package providing implementation for `tools/npm-publish-audit/src`.

## Interface
- `[lib.rs:SEARCH_DIRS]`
- `[lib.rs:manifest_fields]`
- `[lib.rs:repository_url]`
- `[lib.rs:repository_directory]`
- `[lib.rs:expected_directory]`
- `[lib.rs:run]`
- `[sh.rs:strip_trailing_newlines]`
- `[sh.rs:read_fields]`
- `[sh.rs:pad]`
- `[sh.rs:dirname]`
- `[sh.rs:basename]`
- `[sh.rs:command_exists]`
- `[sh.rs:find_manifests]`
- `[sh.rs:io_reason]`

## Invariants

## Side Effects
- None

## Verification
- Run: `bazel test //tools/npm-publish-audit/src/...`
