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
- `[pyjson.rs:Py]`
- `[pyjson.rs:loads]`
- `[pyjson.rs:load_file]`
- `[pyjson.rs:open_error_traceback]`
- `[pyjson.rs:float_repr]`
- `[pyjson.rs:str_repr]`
- `[sh.rs:strip_trailing_newlines]`
- `[sh.rs:read_fields]`
- `[sh.rs:pad]`
- `[sh.rs:dirname]`
- `[sh.rs:basename]`
- `[sh.rs:command_exists]`
- `[sh.rs:find_manifests]`
- `[sh.rs:io_reason]`

## Invariants
- [pyjson.rs:351]: `assert!(loads("{} x").is_err());`
- [pyjson.rs:352]: `assert!(loads("NaN").is_err());`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/npm-publish-audit/src/...`
