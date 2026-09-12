-- AlterTable
ALTER TABLE "workspaces" ADD COLUMN     "group_id" VARCHAR(100);

-- CreateTable
CREATE TABLE "sections" (
    "id" UUID NOT NULL,
    "workspace_id" UUID NOT NULL,
    "title" VARCHAR(255) NOT NULL,
    "position" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "sections_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "resources" (
    "id" UUID NOT NULL,
    "workspace_id" UUID,
    "section_id" UUID,
    "title" VARCHAR(500) NOT NULL,
    "url" TEXT NOT NULL,
    "favicon_url" TEXT,
    "position" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "resources_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notes" (
    "id" UUID NOT NULL,
    "workspace_id" UUID NOT NULL,
    "title" VARCHAR(255) NOT NULL,
    "content" TEXT NOT NULL,
    "position" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "notes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "tasks" (
    "id" UUID NOT NULL,
    "workspace_id" UUID NOT NULL,
    "title" VARCHAR(500) NOT NULL,
    "completed" BOOLEAN NOT NULL DEFAULT false,
    "due_date" TIMESTAMP(6),
    "position" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "tasks_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "idx_sections_workspace" ON "sections"("workspace_id");

-- CreateIndex
CREATE INDEX "idx_resources_workspace" ON "resources"("workspace_id");

-- CreateIndex
CREATE INDEX "idx_resources_section" ON "resources"("section_id");

-- CreateIndex
CREATE INDEX "idx_notes_workspace" ON "notes"("workspace_id");

-- CreateIndex
CREATE INDEX "idx_tasks_workspace" ON "tasks"("workspace_id");

-- CreateIndex
CREATE INDEX "idx_workspaces_group" ON "workspaces"("group_id");

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
