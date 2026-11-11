# Prune Pr Caches

## Overview
Component package providing implementation for `tools/ci/src/prune_pr_caches`.

## Interface
- `[lib.rs:run]`

## Invariants
- None

## Side Effects
- [lib.rs:116]: `// gh reports an API error as "gh: <message> (HTTP <status>)".`
- [lib.rs:121]: `if shell_compat::contains(&lower, b"(http 404)") {`
- [tests.rs:57]: `gone) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;`
- [tests.rs:60]: `err5xx) echo "gh: Bad Gateway (HTTP 502): https://api.github.com/repos/o/r/br...`
- [tests.rs:408]: `// "(HTTP 404)" status means the branch is gone.`

## Verification
- Run: `bazel test //tools/ci/src/prune_pr_caches/...`
