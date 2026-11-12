# 20260614003800 Repair Drifted Sync And Backup Columns

## Overview
Component package providing implementation for `apps/suites/vitruvian-tabs/api/prisma/migrations/20260614003800_repair_drifted_sync_and_backup_columns`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [migration.sql:8]: `-- `prisma migrate deploy` reports "No pending migrations to apply" on every`
- [migration.sql:10]: `-- Prisma P2022 ("column does not exist").`

## Verification
- Run: `bazel test //apps/suites/vitruvian-tabs/api/prisma/migrations/20260614003800_repair_drifted_sync_and_backup_columns/...`
