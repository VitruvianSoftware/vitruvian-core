# Setup Signing

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/bazel/src/setup_signing`.

## Interface
- `[lib.rs:IDENTITY_NAME]`
- `[lib.rs:KEYCHAIN_REL_PATH]`
- `[lib.rs:KEYCHAIN_PASS]`
- `[lib.rs:keychain_path]`
- `[lib.rs:parse_keychain_list_output]`
- `[lib.rs:identity_can_sign]`
- `[lib.rs:openssl_commands]`
- `[lib.rs:setup_signing]`
- `[lib.rs:run_cli]`

## Invariants
- [lib.rs:243]: `assert!(r.calls[0].starts_with("security unlock-keychain -p vitruvian-signing...`
- [lib.rs:244]: `assert!(r.calls[1]`
- [lib.rs:256]: `assert!(!req.args.contains(&"-legacy".to_string()));`

## Side Effects
- [lib.rs:383]: `("openssl", "exec /usr/bin/openssl \"$@\"\n"),`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/bazel/src/setup_signing/...`
