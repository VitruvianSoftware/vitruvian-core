# Bin

## Overview
Component package providing implementation for `apps/suites/vitruvian-tabs/api/rs/src/bin`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [migrate_deploy.rs:21]: `//! `migrate_deploy_bin`: hermetic `prisma migrate deploy` with the`
- [migrate_deploy.rs:24]: `//! Prisma CLI in its Bazel runfiles and hands over the process environment.`
- [migrate_deploy.rs:26]: `//! The Prisma CLI is `//apps/suites/vitruvian-tabs/api:prisma_cli`, a `js_binary` on...`
- [server.rs:84]: `api_url: std::env::var("API_URL").unwrap_or_else(|_| format!("http://localhos...`
- [server.rs:91]: `println!("Vitruvian Tabs API (Rust) listening on http://{bind_addr}");`

## Verification
- Run: `bazel test //apps/suites/vitruvian-tabs/api/rs/src/bin/...`
