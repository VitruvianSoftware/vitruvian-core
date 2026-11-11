# Install

## Overview
Component package providing implementation for `apps/mobile/android-remote/macmenu/scripts/src/install`.

## Interface
- `[lib.rs:DEFAULT_DEST]`
- `[lib.rs:APP_BUNDLE_NAME]`
- `[lib.rs:APP_PROCESS_NAME]`
- `[lib.rs:BUNDLE_ID]`
- `[lib.rs:ZIP_RUNFILES_REL]`
- `[lib.rs:AGENT_RUNFILES_REL]`
- `[lib.rs:InstallPaths]`
- `[lib.rs:resolve_install_paths]`
- `[lib.rs:staged_agent_dest]`
- `[lib.rs:run]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/mobile/android-remote/macmenu/scripts/src/install/...`
