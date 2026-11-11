# Src

## Overview
Component package providing implementation for `tools/landed/src`.

## Interface
- `[lib.rs:Env]`
- `[lib.rs:Exit]`
- `[lib.rs:Landed]`
- `[lib.rs:enter_workspace]`

## Invariants
- None

## Side Effects
- [lib.rs:178]: `.args(["fetch", "origin", branch, "-q"])`
- [lib.rs:335]: `"fetch",`
- [lib.rs:342]: `"could not fetch '{a2}' from origin: no such branch there, or no network."`

## Verification
- Run: `bazel test //tools/landed/src/...`
