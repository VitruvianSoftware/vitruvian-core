# Ci Setup Signing

## Overview
Component package providing implementation for `apps/desktop/vitruvian/bazel/src/ci_setup_signing`.

## Interface
- `[lib.rs:KEYCHAIN_PASSWORD]`
- `[lib.rs:KEYCHAIN_FILENAME]`
- `[lib.rs:P12_FILENAME]`
- `[lib.rs:CiSigningConfig]`
- `[lib.rs:parse_keychain_list_output]`
- `[lib.rs:ci_setup_signing]`
- `[lib.rs:run_cli]`

## Invariants
- [lib.rs:185]: `assert!(r.calls.is_empty());`
- [lib.rs:250]: `assert!(!p12.exists(), "the p12 is removed");`
- [lib.rs:271]: `assert!(!cfg.p12().exists());`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian/bazel/src/ci_setup_signing/...`
