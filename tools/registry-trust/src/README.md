# Src

## Overview
Component package providing implementation for `tools/registry-trust/src`.

## Interface
- `[check.rs:LEDGER]`
- `[check.rs:Fetch]`
- `[check.rs:called]`
- `[check.rs:Row]`
- `[check.rs:Version]`
- `[check.rs:Outcome]`
- `[check.rs:parse_ledger]`
- `[check.rs:unknown_rows]`
- `[check.rs:Fail]`
- `[check.rs:fromisoformat]`
- `[check.rs:when]`
- `[check.rs:npm_versions]`
- `[check.rs:crates_versions]`
- `[check.rs:pypi_versions]`
- `[check.rs:check_one]`
- `[check.rs:check]`
- `[check.rs:report]`
- `[check.rs:main]`
- `[cli.rs:USAGE]`
- `[cli.rs:run]`

## Invariants
- [cli.rs:142]: `assert!(err.contains("usage:"));`
- [cli.rs:161]: `assert!(err.contains("unknown flag: --force"));`
- [cli.rs:172]: `assert!(err.contains("only under bazel test"));`
- [http.rs:310]: `assert!(agent.contains("VitruvianSoftware/vitruvian-core"));`
- [http.rs:311]: `assert!(agent.contains("registry-trust"));`
- [http.rs:314]: `assert!(request.body.is_none());`

## Side Effects
- [check.rs:33]: `use crate::http::{Answer, RegistryError};`
- [check.rs:40]: `pub type Fetch<'a> = dyn FnMut(&str) -> Result<Answer, RegistryError> + 'a;`
- [check.rs:185]: `fn get(fetch: &mut Fetch, url: &str, absent_ok: bool) -> Result<Option<Value>...`
- [cli.rs:31]: `use crate::http::{self, Recorded};`
- [cli.rs:92]: `let mut fetch = |url: &str| match &recorded {`
- [cli.rs:93]: `Some(r) => r.fetch(url),`
- [http.rs:22]: `//! is made by `curl`, given everything on its standard input (`--config -`):`
- [http.rs:131]: `/// A value inside double quotes in a curl config file.`
- [http.rs:148]: `/// The curl config that makes one request: what goes on its stdin.`
- [lib.rs:31]: `//! `urllib.parse` that reach the output. HTTPS goes through `curl`.`

## Verification
- Run: `bazel test //tools/registry-trust/src/...`
