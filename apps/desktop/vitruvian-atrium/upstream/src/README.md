# Src

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/upstream/src`.

## Interface
- `[lib.rs:UPSTREAM_URL]`
- `[lib.rs:UPSTREAM_BRANCH]`
- `[lib.rs:IMPORT_COMMIT]`
- `[lib.rs:APP_DIR]`
- `[lib.rs:LEDGER]`
- `[lib.rs:UPSTREAM_ONLY]`
- `[lib.rs:FORK_RETIRED]`
- `[lib.rs:STATUSES]`
- `[lib.rs:COLUMNS]`
- `[lib.rs:LEDGER_PREAMBLE]`
- `[lib.rs:BRAND_SUBSTITUTIONS]`
- `[lib.rs:fork_split]`
- `[lib.rs:git]`
- `[lib.rs:out]`
- `[lib.rs:to_fork_line]`
- `[lib.rs:to_fork]`
- `[lib.rs:to_fork_bytes]`
- `[lib.rs:brand_review]`
- `[lib.rs:LedgerRow]`
- `[lib.rs:Ledger]`

## Invariants
- None

## Side Effects
- [lib.rs:95]: `.spawn()`
- [lib.rs:96]: `.map_err(|e| format!("git {} spawn failed: {}", args.join(" "), e))?;`
- [lib.rs:394]: `pub fn new(url: &str, cache_dir: &Path, fetch: bool) -> Result<Self, String> {`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/upstream/src/...`
