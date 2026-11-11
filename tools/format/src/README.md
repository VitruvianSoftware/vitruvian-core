# Src

## Overview
Component package providing implementation for `tools/format/src`.

## Interface
- `[lib.rs:find_prettier_recursive]`
- `[lib.rs:locate_prettier_bin]`
- `[lib.rs:is_symlink_path]`
- `[lib.rs:filter_non_symlink_args]`
- `[lib.rs:script_dir]`
- `[lib.rs:run]`

## Invariants
- [lib.rs:185]: `assert!(out.status.success());`

## Side Effects
- [lib.rs:87]: `let err = Command::new(&prettier_bin).args(&filtered).exec();`
- [lib.rs:88]: `eprintln!("ERROR: Failed to exec {}: {err}", prettier_bin.display());`
- [lib.rs:166]: `let dir = make_temp_dir("prettier-exec");`

## Verification
- Run: `bazel test //tools/format/src/...`
