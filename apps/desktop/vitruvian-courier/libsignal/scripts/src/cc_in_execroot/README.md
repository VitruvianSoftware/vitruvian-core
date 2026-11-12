# Cc In Execroot

## Overview
Component package providing implementation for `apps/desktop/vitruvian-courier/libsignal/scripts/src/cc_in_execroot`.

## Interface
- `[lib.rs:CcInvocation]`
- `[lib.rs:resolve_invocation]`
- `[lib.rs:run]`

## Invariants
- [lib.rs:95]: `assert!(resolve_invocation(None, Some("/usr/bin/clang"), &args).is_err());`
- [lib.rs:96]: `assert!(resolve_invocation(Some(""), Some("/usr/bin/clang"), &args).is_err());`
- [lib.rs:97]: `assert!(resolve_invocation(Some("/tmp/execroot"), None, &args).is_err());`

## Side Effects
- [lib.rs:76]: `let err = Command::new(&inv.cc).args(&inv.args).exec();`
- [lib.rs:77]: `eprintln!("exec {}: {err}", inv.cc);`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-courier/libsignal/scripts/src/cc_in_execroot/...`
