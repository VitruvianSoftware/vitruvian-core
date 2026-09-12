-- AlterTable
ALTER TABLE "share_links" ADD COLUMN     "relay_id_hash" VARCHAR(64);

-- CreateIndex
CREATE UNIQUE INDEX "share_links_relay_id_hash_key" ON "share_links"("relay_id_hash");
