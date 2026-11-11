# Src

## Overview
Component package providing implementation for `tools/preview/src`.

## Interface
- `[common.rs:prog]`
- `[common.rs:prog_name]`
- `[common.rs:unbound]`
- `[common.rs:echo]`
- `[common.rs:captured]`
- `[common.rs:discarded]`
- `[common.rs:inherited]`
- `[common.rs:pipeline]`
- `[common.rs:log]`
- `[jq.rs:J]`
- `[jq.rs:pretty]`
- `[jq.rs:compact]`
- `[jq.rs:trunc]`
- `[jq.rs:Run]`
- `[jq.rs:Produced]`
- `[jq.rs:run]`
- `[jq.rs:each]`
- `[jq.rs:one]`
- `[jq.rs:arg]`
- `[jq.rs:head1]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- [jq.rs:470]: `assert!(r.stderr.starts_with(b"jq: error (at <stdin>:1)"));`
- [jq.rs:472]: `assert!(r.stderr.starts_with(b"jq: error (at <stdin>:4)"));`
- [neon_branch.rs:260]: `b"\",\n  \"database_url\": \"postgresql://neondb_owner:mock_password@ep-dry-r...`
- [neon_branch.rs:302]: `b"/neondb?sslmode=require",`
- [pr_comment.rs:302]: `assert!(render(b"bogus", b"a", b"1", b"", b"", b"", b"t").is_none());`
- [pr_comment.rs:308]: `assert!(b.ends_with(b"\n\n<!-- vitruvian-preview-bot: tabula -->"));`
- [pr_comment.rs:309]: `assert!(b.starts_with("### ❌".as_bytes()));`
- [provision_preview.rs:192]: `b"postgresql://neondb_owner:mock@ep-mock.neon.tech/neondb?sslmode=require".to...`

## Side Effects
- [common.rs:71]: `cmd.spawn().map_err(|e| {`
- [lib.rs:26]: `//! lines, the commands run (curl, gcloud, kubectl, gh) and their argv,`
- [neon_branch.rs:22]: `//! copy-on-write branches through the Neon API with `curl`, exactly as the`
- [neon_branch.rs:23]: `//! script does -- same curl argv, same output, same exit codes. The jq the`
- [neon_branch.rs:27]: `//! - Its helpers run inside `$(...)`, where bash clears `set -e`. So a curl`
- [pr_comment.rs:121]: `"` (Neon copy-on-write) |\n| **Access Gating** | 🔒 Zero-Trust SSO (`@vitruvia...`
- [provision_preview.rs:23]: `//! or kubectl), smokes it with curl and prints the preview's JSON -- the same`
- [provision_preview.rs:323]: `b"   [DRY-RUN] Smoke check HTTP GET ",`
- [provision_preview.rs:334]: `let mut c = Command::new("curl");`

## Verification
- Run: `bazel test //tools/preview/src/...`
