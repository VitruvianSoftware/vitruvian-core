# Cloud Bootstrap

## Overview
Component package providing implementation for `tools/cloud-bootstrap/src/cloud_bootstrap`.

## Interface
- `[creds.rs:AuthState]`
- `[creds.rs:decode_key]`
- `[creds.rs:key_client_email]`
- `[creds.rs:tokeninfo_email]`
- `[creds.rs:pulumi_reason]`
- `[creds.rs:parse_delay]`
- `[install.rs:Installer]`
- `[main.rs:warn]`
- `[main.rs:note]`
- `[main.rs:err_bytes]`
- `[main.rs:Ctx]`
- `[manifest.rs:Profile]`
- `[manifest.rs:load]`
- `[manifest.rs:list]`
- `[manifest.rs:known_credential_vars]`
- `[manifest.rs:words]`
- `[manifest.rs:split_pair]`
- `[sh.rs:env]`
- `[sh.rs:env_or_empty]`
- `[sh.rs:env_or]`

## Invariants
- [tests.rs:79]: `fs::canonicalize(&rel).unwrap_or_else(|e| panic!("BIN={rel:?}: {e}"))`
- [tests.rs:84]: `fs::canonicalize(&rel).unwrap_or_else(|e| panic!("SHIPPED_PROFILES={rel:?}: {...`
- [tests.rs:93]: `assert!(has(hay, needle), "{what}: {needle:?} not found in:\n{hay}");`

## Side Effects
- [creds.rs:205]: `// expected account. The token goes to curl on stdin, never argv.`
- [creds.rs:209]: `Command::new("curl")`
- [install.rs:113]: `Command::new("curl")`
- [install.rs:322]: `Command::new("curl")`
- [sh.rs:171]: `let mut child = match cmd.spawn() {`
- [tests.rs:23]: `//! pulumi/curl/cache configurator) that record every invocation, so the`
- [tests.rs:241]: `/// Fake pulumi (ok | fail | flaky: fails the first call only) and a curl`
- [tests.rs:254]: `fail) echo "error: boom token exchange refused (HTTP 503)" >&2; exit 1 ;;`

## Verification
- Run: `bazel test //tools/cloud-bootstrap/src/cloud_bootstrap/...`
