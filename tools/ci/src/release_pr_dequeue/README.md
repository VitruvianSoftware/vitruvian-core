# Release Pr Dequeue

## Overview
Component package providing implementation for `tools/ci/src/release_pr_dequeue`.

## Interface
- `[lib.rs:run]`

## Invariants
- [lib.rs:36]: `fn require(name: &str) -> Result<Vec<u8>, i32> {`
- [lib.rs:76]: `let repo = match require("REPO") {`
- [lib.rs:80]: `let component = match require("COMPONENT") {`
- [tests.rs:113]: `assert!(cond, "{what}\n{}", self.show());`
- [tests.rs:395]: `panic!(`
- [tests.rs:403]: `assert!(`

## Side Effects
- [lib.rs:104]: `let query = b"query($owner:String!,$name:String!,$branch:String!){repository(...`
- [lib.rs:119]: `.arg(shell_compat::os(&cat(&[b"query=", query])))`
- [lib.rs:269]: `.arg(shell_compat::os(&cat(&[b"query=", dequeue_query]))),`
- [tests.rs:27]: `//! arguments, a malformed PR row, a fork's PR filtered by the query).`
- [tests.rs:33]: `/// GraphQL query is multi-word, so a flat `$*` would hide argument bounds).`
- [tests.rs:39]: `if [ -f "${FX}/$1.rc" ]; then echo "gh: HTTP 502" >&2; exit 1; fi`

## Verification
- Run: `bazel test //tools/ci/src/release_pr_dequeue/...`
