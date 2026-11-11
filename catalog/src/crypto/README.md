# Crypto

## Overview
Component package providing implementation for `catalog/src/crypto`.

## Interface
- `[ed25519.rs:public_key]`
- `[ed25519.rs:sign]`
- `[ed25519.rs:verify]`
- `[sha256.rs:digest]`
- `[sha256.rs:hexdigest]`
- `[sha512.rs:digest_parts]`
- `[sha512.rs:digest]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //catalog/src/crypto/...`
