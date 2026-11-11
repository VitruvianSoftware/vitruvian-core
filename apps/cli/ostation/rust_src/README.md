# Rust Src

## Overview
Component package providing implementation for `apps/cli/ostation/rust_src`.

## Interface
- `[client.rs:CMD_HEARTBEAT]`
- `[client.rs:CMD_STATUS]`
- `[client.rs:DEFAULT_PORT]`
- `[client.rs:fetch_status]`
- `[client.rs:parse_status]`
- `[frame.rs:PREFIX]`
- `[frame.rs:SUFFIX]`
- `[frame.rs:HEADER_LEN]`
- `[frame.rs:Frame]`
- `[frame.rs:gcm_seal]`
- `[frame.rs:pack_frame_with_iv]`
- `[frame.rs:pack_frame]`
- `[frame.rs:open_payload]`
- `[frame.rs:FrameReader]`
- `[lib.rs:Key]`
- `[lib.rs:Error]`
- `[lib.rs:Result]`
- `[lib.rs:parse_key]`
- `[relay.rs:RelayConfig]`
- `[relay.rs:adb_args]`

## Invariants
- [tests.rs:63]: `assert!(matches!(read_one(&s, KEY), Err(Error::Protocol(_))));`
- [tests.rs:70]: `assert!(matches!(read_one(&f, KEY), Err(Error::Auth(_))));`
- [tests.rs:76]: `assert!(matches!(`

## Side Effects
- [client.rs:4]: `//! One-shot status query: connect, negotiate, ask for DPS.`
- [relay.rs:57]: `.spawn()?;`
- [relay.rs:63]: `let up = thread::spawn(move || pump(&mut client_rx, &mut to_dev));`
- [relay.rs:64]: `let down = thread::spawn(move || pump(&mut from_dev, &mut client_tx));`
- [tests.rs:103]: `thread::spawn(move || {`
- [tests.rs:146]: `let dev = thread::spawn(move || {`

## Verification
- Run: `bazel test //apps/cli/ostation/rust_src/...`
