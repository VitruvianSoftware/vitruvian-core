# App Profiles

## Overview
Component package providing implementation for `apps/embedded/esp32-s3/host_companion/src/app_profiles`.

## Interface
- `[lib.rs:MOD_NONE]`
- `[lib.rs:MOD_CTRL]`
- `[lib.rs:MOD_SHIFT]`
- `[lib.rs:MOD_ALT]`
- `[lib.rs:MOD_CMD]`
- `[lib.rs:KEY_UP_ARROW]`
- `[lib.rs:KEY_DOWN_ARROW]`
- `[lib.rs:KEY_LEFT_ARROW]`
- `[lib.rs:KEY_RIGHT_ARROW]`
- `[lib.rs:KEY_RETURN]`
- `[lib.rs:KEY_ESC]`
- `[lib.rs:KEY_TAB]`
- `[lib.rs:KEY_BACKSPACE]`
- `[lib.rs:KEY_F11]`
- `[lib.rs:CONS_NONE]`
- `[lib.rs:CONS_MUTE]`
- `[lib.rs:CONS_VOL_UP]`
- `[lib.rs:CONS_VOL_DOWN]`
- `[lib.rs:CONS_PLAY_PAUSE]`
- `[lib.rs:MacroKey]`

## Invariants
- None

## Side Effects
- [lib.rs:185]: `"net.kovidgoyal.kitty",`

## Verification
- Run: `bazel test //apps/embedded/esp32-s3/host_companion/src/app_profiles/...`
