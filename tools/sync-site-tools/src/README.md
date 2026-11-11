# Src

## Overview
Component package providing implementation for `tools/sync-site-tools/src`.

## Interface
- `[catalogue.rs:CATALOG]`
- `[catalogue.rs:PUBLIC_KEY]`
- `[catalogue.rs:DATA]`
- `[catalogue.rs:USES]`
- `[catalogue.rs:size]`
- `[catalogue.rs:scalar]`
- `[catalogue.rs:render]`
- `[catalogue.rs:outputs]`
- `[json.rs:BigInt]`
- `[json.rs:Value]`
- `[json.rs:s]`
- `[json.rs:obj]`
- `[json.rs:list_of_str]`
- `[json.rs:float_repr]`
- `[json.rs:format_fixed1]`
- `[json.rs:loads]`
- `[json.rs:dumps]`
- `[pyerr.rs:PyErr]`
- `[pyfs.rs:join]`
- `[pyfs.rs:join_s]`

## Invariants
- [catalogue.rs:242]: `assert!(text.contains("tools: []"));`
- [lib.rs:88]: `assert!(!extra.is_empty());`
- [lib.rs:98]: `assert!(`
- [lib.rs:131]: `assert!(ids.iter().any(|id| id == expected), "{}", expected);`
- [pyfs.rs:393]: `assert!(!is_file(&missing).unwrap());`

## Side Effects
- [registry.rs:193]: `"Portable SKILL.md agent workflows and standard stdio/HTTP Model Context Prot...`

## Verification
- Run: `bazel test //tools/sync-site-tools/src/...`
