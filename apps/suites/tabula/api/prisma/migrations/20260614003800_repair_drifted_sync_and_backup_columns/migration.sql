-- Repair migration for a corrupted migration ledger.
--
-- On some environments (confirmed on tabula-dev) the 2026-06-10 migrations
-- `20260610000000_add_sync_versioning` and `20260610010000_add_backup_name_type`
-- were recorded in `_prisma_migrations` as applied WITHOUT their `ALTER TABLE`
-- statements ever executing (e.g. from a `migrate resolve --applied`, a
-- `db push`, or a restore/baseline). Because the ledger says they are applied,
-- `prisma migrate deploy` reports "No pending migrations to apply" on every
-- deploy and never adds the columns — so workspace sync and backups fail with
-- Prisma P2022 ("column does not exist").
--
-- This is a normal forward migration: it is NOT in the ledger, so the existing
-- deploy-time `migrate deploy` applies it. `IF NOT EXISTS` makes it idempotent —
-- it adds the missing columns on the drifted database and is a no-op everywhere
-- the original migrations applied correctly. The column definitions match the
-- originals exactly, so the resulting schema is identical to a clean apply.

ALTER TABLE "workspaces"
    ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS "active_device_id" VARCHAR(100),
    ADD COLUMN IF NOT EXISTS "active_device_seen_at" TIMESTAMP(6);

ALTER TABLE "space_groups"
    ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 0;

ALTER TABLE "backups"
    ADD COLUMN IF NOT EXISTS "name" VARCHAR(255),
    ADD COLUMN IF NOT EXISTS "type" VARCHAR(20) NOT NULL DEFAULT 'manual';
