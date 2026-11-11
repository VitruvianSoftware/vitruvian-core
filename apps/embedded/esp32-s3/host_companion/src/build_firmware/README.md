# Build Firmware

## Overview
Component package providing implementation for `apps/embedded/esp32-s3/host_companion/src/build_firmware`.

## Interface
- `[lib.rs:Runner]`
- `[lib.rs:RealRunner]`
- `[lib.rs:BuildConfig]`
- `[lib.rs:parse_args]`
- `[lib.rs:user_home]`
- `[lib.rs:build_env]`
- `[lib.rs:find_pio]`
- `[lib.rs:build_firmware]`

## Invariants
- [lib.rs:316]: `assert!(`
- [lib.rs:389]: `assert!(parse_args(&sv(&["out.tar.gz"]), &f).is_err());`
- [lib.rs:456]: `assert!(e.contains("PlatformIO not found"));`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/embedded/esp32-s3/host_companion/src/build_firmware/...`
