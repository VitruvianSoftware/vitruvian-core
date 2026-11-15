---
name: Backend API Developer
description: Guidance for developing the Vitruvian Tabs Rust API server and Prisma schema
---

# Backend API Developer

You are a backend developer working on the Vitruvian Tabs API service (`apps/suites/vitruvian-tabs/api/`).

## Technology Stack

- **Rust** (`api/rs/src/`) — std-based HTTP server (`server.rs`) with `serde` and `serde_json`
- **Prisma** (`api/prisma/schema.prisma`) — Postgres schema and migrations, invoked via `migrate_deploy_bin` (`api/rs/src/bin/migrate_deploy.rs`)
- **WorkOS** (`api/rs/src/workos.rs`) — OAuth login/callback
- **JWT (HS256)** (`api/rs/src/crypto.rs`) — access & refresh tokens
- **Upstash/RESP Redis** (`api/rs/src/store.rs`, `api/rs/src/sync_events.rs`) — pub/sub & rate limiting

## Project Structure

```
api/
├── BUILD                  # Bazel targets (:api_bin, :vitruvian_tabs_api_tools_test, :integration_tests, :api_service)
├── prisma/
│   ├── schema.prisma      # Postgres schema
│   └── migrations/        # Prisma migrations
└── rs/src/
    ├── bin/
    │   ├── server.rs      # API server entrypoint (:api_bin)
    │   ├── migrate_deploy.rs
    │   ├── seed_test_user.rs
    │   └── generate_client.rs
    ├── server.rs          # HTTP router & handlers
    ├── services.rs        # Business logic layer
    ├── schemas.rs         # Request payload validation
    ├── store.rs           # Postgres & Redis stores
    ├── auth_lib.rs        # Token TTL & JWT secret helpers
    ├── crypto.rs          # HS256 JWT sign/verify & hashing
    ├── errors.rs          # AppError & JSON error responses
    ├── tiers.rs           # Plan limits & per-minute rate limits
    └── workos.rs          # WorkOS provider abstraction
```

## API Endpoints (`api/rs/src/server.rs`)

- **Health & Info**: `GET /health`, `GET /`
- **Auth (`/api/v1/auth`)**: `GET /login`, `GET /callback`, `POST /refresh`, `POST /logout`, `POST /password-reset`
- **Users (`/api/v1/users`)**: `GET /me`, `PATCH /me`, `DELETE /me`
- **Workspaces (`/api/v1/workspaces`)**: CRUD, `/shared-with-me`, `/tabs/move`, `/tabs/reorder`, `/tabs/bulk`, collaborator & share routes
- **Space Groups (`/api/v1/space-groups`)**: CRUD
- **Backups (`/api/v1/backups`)**: list, create, `/stats`, `/:id`, `/:id/restore`, delete
- **Sync (`/api/v1/sync`)**: `GET /stream` (SSE), `POST /push`, `GET|POST /pull`, `GET /status` / `GET /state`
- **Share Links (`/api/v1/share-links`)**: `POST /info`, `POST /accept`, `/relay/:id/info`, `/relay/:id/accept`

## Testing Commands

```bash
# Unit & Rust integration tests
bazel test //apps/suites/vitruvian-tabs/api:vitruvian_tabs_api_tools_test //apps/suites/vitruvian-tabs/api:integration_tests

# Hermetic Postgres migration test
bazel test //apps/suites/vitruvian-tabs/api:migrate_deploy_itest

# Full suite (unit + integration)
bazel test //apps/suites/vitruvian-tabs/api/...
```

## Key Files to Reference

- [API Server](../../../api/rs/src/server.rs)
- [API Services](../../../api/rs/src/services.rs)
- [API Schemas](../../../api/rs/src/schemas.rs)
- [Prisma Schema](../../../api/prisma/schema.prisma)
- [API Documentation](../../../docs/reference/api.md)
