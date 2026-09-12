-- CreateTable
CREATE TABLE "space_collaborators" (
    "id" VARCHAR(100) NOT NULL,
    "workspace_id" VARCHAR(100) NOT NULL,
    "user_id" UUID,
    "invitee_email" VARCHAR(255) NOT NULL,
    "role" VARCHAR(20) NOT NULL DEFAULT 'view',
    "invited_by_user_id" UUID NOT NULL,
    "status" VARCHAR(20) NOT NULL DEFAULT 'active',
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "space_collaborators_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "share_links" (
    "id" VARCHAR(100) NOT NULL,
    "workspace_id" VARCHAR(100) NOT NULL,
    "token_hash" VARCHAR(64) NOT NULL,
    "role" VARCHAR(20) NOT NULL DEFAULT 'view',
    "created_by_user_id" UUID NOT NULL,
    "label" VARCHAR(255),
    "revoked_at" TIMESTAMP(6),
    "expires_at" TIMESTAMP(6),
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "share_links_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "uq_collaborator_ws_email" ON "space_collaborators"("workspace_id", "invitee_email");

-- CreateIndex
CREATE INDEX "idx_collaborators_user" ON "space_collaborators"("user_id");

-- CreateIndex
CREATE INDEX "idx_collaborators_workspace" ON "space_collaborators"("workspace_id");

-- CreateIndex
CREATE UNIQUE INDEX "share_links_token_hash_key" ON "share_links"("token_hash");

-- CreateIndex
CREATE INDEX "idx_share_links_workspace" ON "share_links"("workspace_id");

-- AddForeignKey
ALTER TABLE "space_collaborators" ADD CONSTRAINT "space_collaborators_workspace_id_fkey" FOREIGN KEY ("workspace_id") REFERENCES "workspaces"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "space_collaborators" ADD CONSTRAINT "space_collaborators_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "share_links" ADD CONSTRAINT "share_links_workspace_id_fkey" FOREIGN KEY ("workspace_id") REFERENCES "workspaces"("id") ON DELETE CASCADE ON UPDATE CASCADE;
