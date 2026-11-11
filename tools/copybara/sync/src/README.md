# Src

## Overview
Component package providing implementation for `tools/copybara/sync/src`.

## Interface
- `[goexec.rs:ExecError]`
- `[goexec.rs:errno_string]`
- `[goexec.rs:clean]`
- `[goexec.rs:look_path]`
- `[goexec.rs:command]`
- `[gostr.rs:decode_rune]`
- `[gostr.rs:is_print]`
- `[gostr.rs:quote]`
- `[gostr.rs:escape_rune]`
- `[gostr.rs:join]`
- `[lib.rs:PINNED_IMAGE]`
- `[lib.rs:DEFAULT_OPTIONS]`
- `[lib.rs:MAX_ATTEMPTS]`
- `[lib.rs:Runner]`
- `[lib.rs:DockerRunner]`
- `[lib.rs:workflow_name]`
- `[lib.rs:is_success]`
- `[lib.rs:resolve_workspace]`
- `[lib.rs:run]`
- `[lib.rs:is_digits]`

## Invariants
- None

## Side Effects
- [goexec.rs:21]: `//! What Go's `os/exec` does before and around running a program, so the port`
- [goexec.rs:23]: `//! cannot): `exec.LookPath`'s PATH walk, its `ErrDot` refusal of relative`
- [goexec.rs:32]: `/// The error Go's `exec.Command(name).Run()` reports when it cannot start.`
- [lib.rs:53]: `/// stderr (stdin is /dev/null, as exec.Cmd leaves it).`
- [lib.rs:268]: `"Copybara exit {exit_code} (attempt {}/{MAX_ATTEMPTS}) — retrying after re-fe...`
- [lib.rs:282]: `/// Go's *fs.PathError text: "<op> <path>: <errno text>".`

## Verification
- Run: `bazel test //tools/copybara/sync/src/...`
