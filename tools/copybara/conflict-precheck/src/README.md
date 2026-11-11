# Src

## Overview
Component package providing implementation for `tools/copybara/conflict-precheck/src`.

## Interface
- `[goexec.rs:ExecError]`
- `[goexec.rs:errno_string]`
- `[goexec.rs:clean]`
- `[goexec.rs:look_path]`
- `[goexec.rs:command]`
- `[lib.rs:EXPORT_LABEL]`
- `[lib.rs:to_upper]`
- `[lib.rs:decode_rune]`
- `[lib.rs:trim_space]`
- `[lib.rs:import_label]`
- `[lib.rs:latest_rev]`
- `[lib.rs:find_rev]`
- `[lib.rs:genuine_commits]`
- `[lib.rs:monorepo_only_excludes]`
- `[lib.rs:cat_file_reachable]`
- `[lib.rs:run]`

## Invariants
- None

## Side Effects
- [goexec.rs:21]: `//! What Go's `os/exec` does before and around running a program, so the port`
- [goexec.rs:23]: `//! cannot): `exec.LookPath`'s PATH walk, its `ErrDot` refusal of relative`
- [goexec.rs:32]: `/// The error Go's `exec.Command(name).Run()` reports when it cannot start.`
- [lib.rs:151]: `/// exec.Command("git", args...).Output(): stdout when git exits 0, None when`
- [lib.rs:250]: `/// /dev/null as exec.Cmd.Run leaves it).`

## Verification
- Run: `bazel test //tools/copybara/conflict-precheck/src/...`
