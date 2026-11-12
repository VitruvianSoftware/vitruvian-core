/*
  Warnings:

  - The primary key for the `notes` table will be changed. If it partially fails, the table could be left without primary key constraint.
  - The primary key for the `resources` table will be changed. If it partially fails, the table could be left without primary key constraint.
  - The primary key for the `sections` table will be changed. If it partially fails, the table could be left without primary key constraint.
  - The primary key for the `tabs` table will be changed. If it partially fails, the table could be left without primary key constraint.
  - The primary key for the `tasks` table will be changed. If it partially fails, the table could be left without primary key constraint.
  - The primary key for the `workspaces` table will be changed. If it partially fails, the table could be left without primary key constraint.

*/
-- DropForeignKey
ALTER TABLE "backups" DROP CONSTRAINT "backups_workspace_id_fkey";

-- DropForeignKey
ALTER TABLE "notes" DROP CONSTRAINT "notes_workspace_id_fkey";

-- DropForeignKey
ALTER TABLE "resources" DROP CONSTRAINT "resources_section_id_fkey";

-- DropForeignKey
ALTER TABLE "resources" DROP CONSTRAINT "resources_workspace_id_fkey";

-- DropForeignKey
ALTER TABLE "sections" DROP CONSTRAINT "sections_workspace_id_fkey";

-- DropForeignKey
ALTER TABLE "tabs" DROP CONSTRAINT "tabs_workspace_id_fkey";

-- DropForeignKey
ALTER TABLE "tasks" DROP CONSTRAINT "tasks_workspace_id_fkey";

-- AlterTable
ALTER TABLE "backups" ALTER COLUMN "workspace_id" SET DATA TYPE VARCHAR(100);

-- AlterTable
ALTER TABLE "notes" DROP CONSTRAINT "notes_pkey",
ALTER COLUMN "id" SET DATA TYPE VARCHAR(100),
ALTER COLUMN "workspace_id" SET DATA TYPE VARCHAR(100),
ADD CONSTRAINT "notes_pkey" PRIMARY KEY ("id");

-- AlterTable
ALTER TABLE "resources" DROP CONSTRAINT "resources_pkey",
ALTER COLUMN "id" SET DATA TYPE VARCHAR(100),
ALTER COLUMN "workspace_id" SET DATA TYPE VARCHAR(100),
ALTER COLUMN "section_id" SET DATA TYPE VARCHAR(100),
ADD CONSTRAINT "resources_pkey" PRIMARY KEY ("id");

-- AlterTable
ALTER TABLE "sections" DROP CONSTRAINT "sections_pkey",
ALTER COLUMN "id" SET DATA TYPE VARCHAR(100),
ALTER COLUMN "workspace_id" SET DATA TYPE VARCHAR(100),
ADD CONSTRAINT "sections_pkey" PRIMARY KEY ("id");

-- AlterTable
ALTER TABLE "tabs" DROP CONSTRAINT "tabs_pkey",
ALTER COLUMN "id" SET DATA TYPE VARCHAR(100),
ALTER COLUMN "workspace_id" SET DATA TYPE VARCHAR(100),
ADD CONSTRAINT "tabs_pkey" PRIMARY KEY ("id");

-- AlterTable
ALTER TABLE "tasks" DROP CONSTRAINT "tasks_pkey",
ALTER COLUMN "id" SET DATA TYPE VARCHAR(100),
ALTER COLUMN "workspace_id" SET DATA TYPE VARCHAR(100),
ADD CONSTRAINT "tasks_pkey" PRIMARY KEY ("id");

-- AlterTable
ALTER TABLE "workspaces" DROP CONSTRAINT "workspaces_pkey",
ALTER COLUMN "id" SET DATA TYPE VARCHAR(100),
ADD CONSTRAINT "workspaces_pkey" PRIMARY KEY ("id");

-- AddForeignKey
ALTER TABLE "tabs" ADD CONSTRAINT "tabs_workspace_id_fkey" FOREIGN KEY ("workspace_id") REFERENCES "workspaces"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "backups" ADD CONSTRAINT "backups_workspace_id_fkey" FOREIGN KEY ("workspace_id") REFERENCES "workspaces"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sections" ADD CONSTRAINT "sections_workspace_id_fkey" FOREIGN KEY ("workspace_id") REFERENCES "workspaces"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "resources" ADD CONSTRAINT "resources_workspace_id_fkey" FOREIGN KEY ("workspace_id") REFERENCES "workspaces"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "resources" ADD CONSTRAINT "resources_section_id_fkey" FOREIGN KEY ("section_id") REFERENCES "sections"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notes" ADD CONSTRAINT "notes_workspace_id_fkey" FOREIGN KEY ("workspace_id") REFERENCES "workspaces"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "tasks" ADD CONSTRAINT "tasks_workspace_id_fkey" FOREIGN KEY ("workspace_id") REFERENCES "workspaces"("id") ON DELETE CASCADE ON UPDATE CASCADE;
