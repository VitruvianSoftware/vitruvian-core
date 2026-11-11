# Src

## Overview
Component package providing implementation for `tools/gcp-cloudrun/src`.

## Interface
- `[lib.rs:ALLOWED_VERBS]`
- `[lib.rs:DEFAULT_REGION]`
- `[lib.rs:DEFAULT_SINCE]`
- `[lib.rs:DEFAULT_LIMIT]`
- `[lib.rs:DEFAULT_OPERATOR_ACCOUNT]`
- `[lib.rs:IDENTITY_MAP]`
- `[lib.rs:USAGE]`
- `[lib.rs:GcloudCmd]`
- `[lib.rs:guard]`
- `[lib.rs:gcloud]`
- `[lib.rs:IdentityRow]`
- `[lib.rs:parse_identity_map]`
- `[lib.rs:lookup]`
- `[lib.rs:is_service_account]`
- `[lib.rs:operator_account]`
- `[lib.rs:normalize_env]`
- `[lib.rs:pulumi_stack_project]`
- `[lib.rs:resolve_app_infra]`
- `[lib.rs:Args]`
- `[lib.rs:parse_args]`

## Invariants
- [tests.rs:86]: `assert!(lookup(&rows, "apps/web/nope/infra/app").is_none());`
- [tests.rs:105]: `assert!(resolve(&ws, &a).is_err(), "a '-' project is refused");`
- [tests.rs:107]: `assert!(resolve(&ws, &a).is_err());`

## Side Effects
- [tests.rs:180]: `vec!["--project", "p", "--revision", "--log-http"], // a name that is a flag`

## Verification
- Run: `bazel test //tools/gcp-cloudrun/src/...`
