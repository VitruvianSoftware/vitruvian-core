# Make Dmg

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/bazel/src/make_dmg`.

## Interface
- `[lib.rs:APP_NAME]`
- `[lib.rs:VOLUME]`
- `[lib.rs:STYLE_LIMIT]`
- `[lib.rs:DmgRequest]`
- `[lib.rs:usage]`
- `[lib.rs:parse_cli_args]`
- `[lib.rs:parse_mount_point]`
- `[lib.rs:render_finder_applescript]`
- `[lib.rs:make_dmg]`
- `[lib.rs:run_cli]`

## Invariants
- None

## Side Effects
- [lib.rs:107]: `.args(["-exec", "xattr", "-c", "{}", "+"]),`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/bazel/src/make_dmg/...`
