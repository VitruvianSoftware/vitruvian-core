-- CreateTable
CREATE TABLE "space_groups" (
    "id" VARCHAR(100) NOT NULL,
    "user_id" UUID NOT NULL,
    "title" VARCHAR(255) NOT NULL,
    "collapsed" BOOLEAN NOT NULL DEFAULT false,
    "position" INTEGER NOT NULL DEFAULT 0,
    "color" VARCHAR(20),
    "created_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "space_groups_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "idx_space_groups_user" ON "space_groups"("user_id");
