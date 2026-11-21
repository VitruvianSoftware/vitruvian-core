# Release Pr Dequeue

## Overview
Component package providing implementation for `tools/ci/src/release_pr_dequeue`.

Run with no argument before release-please: takes a component's release PR out of the merge queue when main gained a change under its code path that the PR does not list (GitHub refuses release-please's push to a queued PR's branch, so the release would ship stale notes). Run as `release_pr_dequeue rearm` after release-please: puts the PR back (auto-merge, squash) if it is out of the queue, not held (`do-not-automerge`), not a draft and not already armed; release-please pushes only when the PR's text changes, so without this a PR dequeued for a chore would stay out. Every workflow that runs `googleapis/release-please-action` must do both; `bazel run //tools/conformance:check` (group RELEASEDEQ) enforces it.

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
