# Src

## Overview
Component package providing implementation for `apps/suites/vitruvian-tabs/api/rs/src`.

## Interface
- `[auth_lib.rs:ACCESS_TOKEN_TTL]`
- `[auth_lib.rs:ACCESS_TOKEN_TTL_SECS]`
- `[auth_lib.rs:REFRESH_TOKEN_TTL_DAYS]`
- `[auth_lib.rs:resolve_jwt_secret]`
- `[auth_lib.rs:resolve_jwt_secret_from_process_env]`
- `[auth_lib.rs:generate_refresh_token]`
- `[auth_lib.rs:hash_refresh_token]`
- `[auth_lib.rs:refresh_token_expiry]`
- `[crypto.rs:hex_encode]`
- `[crypto.rs:random_bytes]`
- `[crypto.rs:uuid_v4]`
- `[crypto.rs:is_valid_uuid]`
- `[crypto.rs:is_valid_email]`
- `[crypto.rs:is_valid_hex_color]`
- `[crypto.rs:base64_decode]`
- `[crypto.rs:base64url_decode]`
- `[crypto.rs:constant_time_eq]`
- `[crypto.rs:jwt_sign]`
- `[crypto.rs:jwt_decode]`
- `[crypto.rs:jwt_verify]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- [tests_integration.rs:207]: `assert!(loc.contains("https://api.workos.com/sso/authorize"));`
- [tests_integration.rs:208]: `assert!(loc.contains("http://localhost:3001"));`
- [tests_integration.rs:221]: `assert!(body["token"].as_str().is_some());`
- [tests_unit.rs:76]: `assert!(resolve_jwt_secret(&prod_env)`
- [tests_unit.rs:83]: `assert!(resolve_jwt_secret(&prod_empty).is_err());`
- [tests_unit.rs:87]: `assert!(!dev_secret.is_empty());`

## Side Effects
- [errors.rs:24]: `/// Typed HTTP errors matching `src/lib/errors.ts` and `src/lib/errorHandler....`
- [errors.rs:192]: `/// Detect Prisma schema-drift error shapes (P2021 missing table, P2022 missi...`
- [lib.rs:51]: `// 1. Prisma Client Generation & Post-Processing (`generate-client.cjs`)`
- [lib.rs:54]: `pub const GENERATED_DIR: &str = "src/generated/prisma";`
- [lib.rs:55]: `pub const DEFAULT_PRISMA_SCHEMA: &str = "prisma/schema.prisma";`
- [migration_guard.rs:111]: `(from migration(s): {}). Run `prisma migrate deploy` against DATABASE_URL \`
- [migration_guard.rs:206]: `"Database migration guard could not query information_schema after retries ({...`
- [secrets.rs:49]: `let output = std::process::Command::new("curl")`
- [secrets.rs:57]: `"http://metadata.google.internal/computeMetadata/v1/instance/service-accounts...`
- [secrets.rs:60]: `.map_err(|e| format!("Failed to query GCE metadata server: {e}"))?;`

## Verification
- Run: `bazel test //apps/suites/vitruvian-tabs/api/rs/src/...`
