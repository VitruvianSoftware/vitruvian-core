-- Persist backup name and type. Previously the API accepted name/type in the
-- create payload but silently dropped them (no columns existed), so list/get
-- never returned a name and stats could not distinguish auto vs manual backups.
-- type defaults to 'manual' to match existing rows' assumed kind.

-- AlterTable
ALTER TABLE "backups" ADD COLUMN "name" VARCHAR(255),
ADD COLUMN "type" VARCHAR(20) NOT NULL DEFAULT 'manual';
