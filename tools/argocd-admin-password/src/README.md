# Src

## Overview
Component package providing implementation for `tools/argocd-admin-password/src`.

## Interface
- `[jq.rs:Jv]`
- `[jq.rs:dump_string]`
- `[jq.rs:dump_compact]`
- `[jq.rs:dump_pretty]`
- `[jq.rs:raw]`
- `[jq.rs:dump_trunc]`
- `[jq.rs:Run]`
- `[jq.rs:values]`
- `[jq.rs:run]`
- `[jq.rs:status]`
- `[jq.rs:select_item]`
- `[jq.rs:password]`
- `[lib.rs:ITEM]`
- `[lib.rs:URL]`
- `[lib.rs:PROJECT_DIR]`
- `[lib.rs:Exit]`
- `[lib.rs:b64_decode]`
- `[lib.rs:b64_encode]`
- `[lib.rs:item_doc]`
- `[lib.rs:utc_now]`

## Invariants
- [jq.rs:398]: `assert!(n("\"s\"\n").contains("<stdin>:1"));`
- [jq.rs:399]: `assert!(n("\n\n\"s\"").contains("<stdin>:2"));`
- [jq.rs:400]: `assert!(n("\"s\"\n\n\n").contains("<stdin>:1"));`

## Side Effects
- [lib.rs:262]: `let mut child = match cmd.spawn() {`

## Verification
- Run: `bazel test //tools/argocd-admin-password/src/...`
