# Site Pr Automerge

## Overview
Component package providing implementation for `tools/ci/src/site_pr_automerge`.

## Interface
- `[lib.rs:run]`

## Invariants
- [tests.rs:121]: `assert!(c.armed_at("sha1"), "log: {}", c.log);`
- [tests.rs:122]: `assert!(`
- [tests.rs:133]: `assert!(!c.any_arm() && !c.disabled(), "log: {}", c.log);`

## Side Effects
- [tests.rs:35]: `[ "${FAKE_LIST_RC:-0}" = "0" ] || { echo "gh: HTTP 502" >&2; exit 1; }`
- [tests.rs:39]: `[ "${FAKE_VIEW_RC:-0}" = "0" ] || { echo "gh: HTTP 500" >&2; exit 1; }`
- [tests.rs:47]: `*--disable-auto*) [ "${FAKE_DISABLE_RC:-0}" = "0" ] || { echo "gh: HTTP 422" ...`

## Verification
- Run: `bazel test //tools/ci/src/site_pr_automerge/...`
