# Src

## Overview
Component package providing implementation for `tools/github-app-key/src`.

## Interface
- `[lib.rs:APPS]`
- `[lib.rs:Exit]`
- `[lib.rs:App]`
- `[lib.rs:lookup]`
- `[lib.rs:list]`
- `[lib.rs:usage]`
- `[lib.rs:manifest]`
- `[lib.rs:b64url]`
- `[lib.rs:unsigned_jwt]`
- `[lib.rs:run]`

## Invariants
- None

## Side Effects
- [lib.rs:215]: `redirect_url: "http://localhost:8723/cb",`

## Verification
- Run: `bazel test //tools/github-app-key/src/...`
