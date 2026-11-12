# Dmg Image Devices

## Overview
Component package providing implementation for `apps/desktop/vitruvian/bazel/src/dmg_image_devices`.

## Interface
- `[lib.rs:extract_devices]`

## Invariants
- [lib.rs:149]: `assert!(extract_devices(info, "/tmp/w/rw-1.dmg").is_empty());`
- [lib.rs:177]: `assert!(got.is_empty());`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian/bazel/src/dmg_image_devices/...`
