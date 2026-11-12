# Release Exec

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/bazel/src/release_exec`.

## Interface
- `[lib.rs:Cmd]`
- `[lib.rs:Out]`
- `[lib.rs:Runner]`
- `[lib.rs:SystemRunner]`
- `[lib.rs:FakeRunner]`
- `[lib.rs:run]`
- `[lib.rs:capture]`
- `[lib.rs:report_redacted]`
- `[lib.rs:REDACTED]`
- `[lib.rs:is_secret_name]`
- `[lib.rs:env_secrets]`
- `[lib.rs:redact_known]`
- `[lib.rs:MIN_SECRET_LINE]`
- `[lib.rs:redact_urls_in_text]`
- `[lib.rs:redact_args]`
- `[lib.rs:redact_json_secrets]`
- `[lib.rs:redact_xml_secrets]`
- `[lib.rs:redact_github_tokens]`
- `[lib.rs:MIN_BEARER_TOKEN]`
- `[lib.rs:redact_credentials_in_text]`

## Invariants
- None

## Side Effects
- [lib.rs:210]: `match c.spawn() {`
- [lib.rs:230]: `match c.spawn() {`
- [lib.rs:251]: `let mut child = match c.spawn() {`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/bazel/src/release_exec/...`
