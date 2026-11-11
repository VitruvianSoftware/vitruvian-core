# Src

## Overview
Component package providing implementation for `tools/pipeline/plan/src`.

## Interface
- `[cli.rs:main_with]`
- `[gates.rs:INERT_TOOLS]`
- `[gates.rs:is_docs_only]`
- `[gates.rs:check_global_impact]`
- `[gates.rs:classify_persona_and_operation]`
- `[gates.rs:resolve_packages]`
- `[git.rs:DiffOptions]`
- `[git.rs:resolve_diff_base]`
- `[git.rs:extract_changed_files]`
- `[git.rs:rev_parse]`
- `[git.rs:GitRevGraph]`
- `[lib.rs:SCHEMA_VERSION]`
- `[lib.rs:PLAN_SOURCE_MAP]`
- `[lib.rs:PLAN_SOURCE_LIVE]`
- `[lib.rs:MatrixEntry]`
- `[lib.rs:Plan]`
- `[lib.rs:QueryRunner]`
- `[lib.rs:RevGraph]`
- `[lib.rs:UnitDef]`
- `[lib.rs:parse_pipeline_units_from_build]`

## Invariants
- [tests.rs:215]: `assert!(`
- [tests.rs:404]: `assert!(docs.is_docs_only);`
- [tests.rs:412]: `assert!(p.is_global_impact);`

## Side Effects
- [cli.rs:29]: `use unitfile::gocompat::exec::{eprint, print, Ctx};`
- [cli.rs:35]: `use crate::query::{self, BazelQueryRunner};`
- [cli.rs:64]: `usage: "Timeout in seconds for analysis and query execution",`
- [gates.rs:211]: `|| clean.contains("prisma/schema.prisma")`
- [git.rs:24]: `use unitfile::gocompat::exec::{self, Cmd, Ctx, Io};`
- [git.rs:50]: `let (r, out) = exec::run(&c, ctx);`
- [git.rs:52]: `let base = exec::trim_space(&out.stdout);`
- [lib.rs:32]: `pub mod query;`
- [lib.rs:38]: `pub use query::{`
- [lib.rs:50]: `pub const PLAN_SOURCE_LIVE: &str = "live-query";`

## Verification
- Run: `bazel test //tools/pipeline/plan/src/...`
