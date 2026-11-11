# Src

## Overview
Component package providing implementation for `tools/techdocs/src`.

## Interface
- `[lib.rs:GREEN]`
- `[lib.rs:RED]`
- `[lib.rs:BOLD]`
- `[lib.rs:RESET]`
- `[lib.rs:TECHDOCS_CORE]`
- `[lib.rs:logical_pwd]`
- `[lib.rs:cd]`
- `[lib.rs:rm_rf]`
- `[lib.rs:bexpand]`
- `[lib.rs:run]`

## Invariants
- [lib.rs:450]: `assert!(!stop);`
- [lib.rs:465]: `assert!(stop);`
- [lib.rs:483]: `assert!(!d.join("site").exists());`

## Side Effects
- [lib.rs:226]: `let (child, sink): (Option<std::process::Child>, Option<OwnedFd>) = match sor...`
- [lib.rs:297]: `let spawned = cmd.spawn();`

## Verification
- Run: `bazel test //tools/techdocs/src/...`
