# Flash

## Overview
Component package providing implementation for `apps/embedded/esp32-s3/host_companion/src/flash`.

## Interface
- `[lib.rs:Runner]`
- `[lib.rs:RealRunner]`
- `[lib.rs:FlashArgs]`
- `[lib.rs:parse_args]`
- `[lib.rs:usage]`
- `[lib.rs:detect_port]`
- `[lib.rs:find_bundle_dir]`
- `[lib.rs:find_esptool]`
- `[lib.rs:find_pio]`
- `[lib.rs:Env]`
- `[lib.rs:flash]`

## Invariants
- [lib.rs:334]: `assert!(parse_args(&s(&["--help"])).unwrap().help);`
- [lib.rs:335]: `assert!(parse_args(&s(&["-h"])).unwrap().help);`
- [lib.rs:336]: `assert!(parse_args(&[]).unwrap().port.is_none());`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/embedded/esp32-s3/host_companion/src/flash/...`
