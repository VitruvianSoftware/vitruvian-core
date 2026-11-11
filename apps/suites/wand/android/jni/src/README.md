# Src

## Overview
Component package providing implementation for `apps/suites/wand/android/jni/src`.

## Interface
- `[bridge.rs:PACKET_LEN]`
- `[bridge.rs:PLATFORM_DESKTOP]`
- `[bridge.rs:PLATFORM_ANDROID]`
- `[bridge.rs:PLATFORM_ANDROID_TV]`
- `[bridge.rs:HandleSlot]`
- `[bridge.rs:platform_from_int]`
- `[bridge.rs:error_json]`
- `[bridge.rs:panic_payload_message]`
- `[bridge.rs:catch_to_json]`
- `[bridge.rs:create_handle]`
- `[bridge.rs:Bridge]`

## Invariants
- [bridge.rs:5]: `//! Keeping all JSON marshaling, handle slot management, error formatting, an...`
- [bridge.rs:9]: `use std::panic::{AssertUnwindSafe, catch_unwind};`
- [bridge.rs:46]: `/// Extracts a human-readable message from a panic payload.`
- [lib.rs:8]: `use std::panic::{AssertUnwindSafe, catch_unwind};`
- [lib.rs:65]: `"nativeCreate panic: {}",`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/suites/wand/android/jni/src/...`
