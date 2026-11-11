# Image Sbom Scan

## Overview
Component package providing implementation for `tools/ci/src/image_sbom_scan`.

## Interface
- `[lib.rs:run]`

## Invariants
- [tests.rs:176]: `Some(std::fs::canonicalize(&p).unwrap_or_else(|e| panic!("JQ_BIN={jq}: {e}")))`
- [tests.rs:184]: `assert!(`
- [tests.rs:190]: `assert!(`

## Side Effects
- [lib.rs:66]: `fn fetch(`
- [lib.rs:85]: `Command::new("curl")`
- [lib.rs:121]: `// `curl ... | jq '.predicate' > out` under pipefail: curl's own error and`
- [tests.rs:22]: `//! registry: a fake `curl` serving an image index, its attestation manifest and`
- [tests.rs:25]: `//! covers the fetch-and-filter flow they cannot, including the jq filters`
- [tests.rs:39]: `/// `curl ... [-o FILE] URL`: the token endpoint prints a token, anything`

## Verification
- Run: `bazel test //tools/ci/src/image_sbom_scan/...`
