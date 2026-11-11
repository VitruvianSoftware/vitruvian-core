# Src

## Overview
Component package providing implementation for `tools/npm-trusted-publisher/src`.

## Interface
- `[bootstrap.rs:usage]`
- `[bootstrap.rs:main]`
- `[manifest.rs:os_error]`
- `[manifest.rs:type_name]`
- `[manifest.rs:load_dict]`
- `[manifest.rs:name_private_line]`
- `[manifest.rs:name_of]`
- `[manifest.rs:unresolvable_deps]`
- `[pyjson.rs:Py]`
- `[pyjson.rs:loads]`
- `[pyjson.rs:load_file]`
- `[pyjson.rs:open_error_traceback]`
- `[pyjson.rs:float_repr]`
- `[pyjson.rs:str_repr]`
- `[setup.rs:DEFAULT_OTP_WAIT_SECONDS]`
- `[setup.rs:DEFAULT_OTP_POLL_SECONDS]`
- `[setup.rs:mirror_for]`
- `[setup.rs:search_dirs]`
- `[setup.rs:main]`
- `[sh.rs:R_OK]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- [bootstrap.rs:47]: `# Exit: 0 nothing to do or all published · 1 a publish failed · 2 precondition`
- [bootstrap.rs:389]: `assert!(u.starts_with("# Usage:\n"));`
- [bootstrap.rs:390]: `assert!(u.trim_end().ends_with("2 precondition"));`
- [pyjson.rs:351]: `assert!(loads("{} x").is_err());`
- [pyjson.rs:352]: `assert!(loads("NaN").is_err());`

## Side Effects
- [bootstrap.rs:25]: `//! The hand-off. The script runs `exec bash "$setup"` with the first of`
- [bootstrap.rs:28]: `//! honours `$SETUP_SH` the same way (exec'ing bash on it); otherwise it runs`
- [bootstrap.rs:31]: `//! happen here. As with `exec`, the cloned mirror is not removed on hand-off`

## Verification
- Run: `bazel test //tools/npm-trusted-publisher/src/...`
