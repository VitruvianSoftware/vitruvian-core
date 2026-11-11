# Src

## Overview
Component package providing implementation for `tools/crates/src`.

## Interface
- `[fresh.rs:Value]`
- `[fresh.rs:parse_toml]`
- `[fresh.rs:req_matches]`
- `[fresh.rs:DepSource]`
- `[fresh.rs:Dep]`
- `[fresh.rs:LocalPackage]`
- `[fresh.rs:Workspace]`
- `[fresh.rs:join_normal]`
- `[fresh.rs:local_packages]`
- `[fresh.rs:percent_decode]`
- `[fresh.rs:lock_problems]`
- `[fresh.rs:unlocked_manifests]`
- `[fresh.rs:relock_hint]`
- `[lib.rs:toolchain_version]`
- `[lib.rs:repository_set_versions]`
- `[lib.rs:workspace_rust_version]`
- `[lib.rs:workspace_members]`
- `[lib.rs:package_rust_version_with_workspace]`
- `[lib.rs:package_rust_version]`
- `[lib.rs:same_minor]`

## Invariants
- [lib.rs:336]: `assert!(workspace_members("[workspace]\n").is_empty());`
- [lib.rs:367]: `assert!(split_dir_arg(&args(&["--dir"])).is_err());`
- [lib.rs:368]: `assert!(split_dir_arg(&args(&["--dir", "/etc"])).is_err());`

## Side Effects
- [fresh.rs:479]: `/// cargo writes them in the lock's `source` query (`("rev", "abc")`).`

## Verification
- Run: `bazel test //tools/crates/src/...`
