# Src

## Overview
Component package providing implementation for `tools/github-security/src`.

## Interface
- `[lib.rs:ORG]`
- `[lib.rs:REPO]`
- `[lib.rs:CONFIG_NAME]`
- `[lib.rs:SETTINGS]`
- `[lib.rs:Exit]`
- `[lib.rs:scopes_from_headers]`
- `[lib.rs:has_admin_org]`
- `[lib.rs:run]`

## Invariants
- [lib.rs:324]: `assert!(SETTINGS`
- [lib.rs:341]: `assert!(has_admin_org(b"gist, admin:org, repo"));`
- [lib.rs:342]: `assert!(has_admin_org(b"admin:org"));`

## Side Effects
- [lib.rs:332]: `let raw = b"HTTP/2.0 200 OK\r\nX-OAuth-Scopes: gist, read:org, repo\r\nx-acce...`

## Verification
- Run: `bazel test //tools/github-security/src/...`
