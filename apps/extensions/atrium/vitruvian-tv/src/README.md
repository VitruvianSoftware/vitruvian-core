# Src

## Overview
Component package providing implementation for `apps/extensions/atrium/vitruvian-tv/src`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [main.rs:203]: `.spawn()`
- [main.rs:208]: `thread::spawn(move || {`
- [main.rs:327]: `/// True for an http(s) URL with a host and no whitespace or control`

## Verification
- Run: `bazel test //apps/extensions/atrium/vitruvian-tv/src/...`
