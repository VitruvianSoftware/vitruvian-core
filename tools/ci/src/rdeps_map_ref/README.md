# Rdeps Map Ref

## Overview
Component package providing implementation for `tools/ci/src/rdeps_map_ref`.

## Interface
- `[lib.rs:run]`

## Invariants
- None

## Side Effects
- [lib.rs:21]: `//! rdeps-map-ref — store/fetch/prune rdeps maps as git refs.`
- [lib.rs:45]: `b"http.https://github.com/.extraheader=AUTHORIZATION: basic ",`
- [lib.rs:163]: `log(b"usage: fetch <out.json> <base>");`

## Verification
- Run: `bazel test //tools/ci/src/rdeps_map_ref/...`
