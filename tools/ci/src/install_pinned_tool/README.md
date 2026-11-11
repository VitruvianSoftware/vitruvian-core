# Install Pinned Tool

## Overview
Component package providing implementation for `tools/ci/src/install_pinned_tool`.

## Interface
- `[lib.rs:run]`

## Invariants
- [tests.rs:177]: `assert!(o.status.success());`
- [tests.rs:189]: `assert!(st.success());`
- [tests.rs:277]: `assert!(`

## Side Effects
- [lib.rs:166]: `// Byte-for-byte: no prefix, query, fragment or normalisation.`
- [lib.rs:252]: `Command::new("curl")`
- [tests.rs:22]: `//! `curl` first on PATH (it copies fixtures, no network) and the real `tar`,`
- [tests.rs:42]: `/// The fake curl: `curl ... -O <url>` copies `$FIXTURES_DIR/<basename>` into`
- [tests.rs:43]: `/// the working directory, as real curl's -O names the file.`

## Verification
- Run: `bazel test //tools/ci/src/install_pinned_tool/...`
