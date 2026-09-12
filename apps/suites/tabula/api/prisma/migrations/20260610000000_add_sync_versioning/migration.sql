-- Add optimistic-concurrency version counters and device-lease columns.
-- version is incremented on every successful PUT; clients send baseVersion for
-- conflict detection. active_device_id/_seen_at form an advisory lease used to
-- gate cross-device tab sync.

-- AlterTable
ALTER TABLE "workspaces" ADD COLUMN "version" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN "active_device_id" VARCHAR(100),
ADD COLUMN "active_device_seen_at" TIMESTAMP(6);

-- AlterTable
ALTER TABLE "space_groups" ADD COLUMN "version" INTEGER NOT NULL DEFAULT 0;
