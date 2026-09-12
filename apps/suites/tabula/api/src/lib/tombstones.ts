/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/**
 * Tombstones for deleted sync entities.
 *
 * When a workspace or space group is deleted via REST we record a tombstone in
 * Redis for 30 days. PUT-as-upsert (and /sync/push) consult the tombstone so a
 * stale offline client replaying a full snapshot cannot resurrect the entity.
 * Creates of never-seen ids are unaffected (no tombstone -> allowed).
 *
 * All Redis operations here FAIL-OPEN: if Redis is temporarily offline,
 * reconnecting, or throws ("Connection is closed"), tombstone checks log a
 * warning and return false so temporary Redis outages never fail workspace
 * writes or block sync requests.
 */
import { redis } from "./redis";

export type TombstoneEntityType = "workspace" | "spaceGroup";

const TOMBSTONE_TTL_SECONDS = 60 * 60 * 24 * 30; // 30 days

function tombstoneKey(
  userId: string,
  type: TombstoneEntityType,
  entityId: string,
): string {
  return `tombstone:${userId}:${type}:${entityId}`;
}

/**
 * Record a tombstone for a deleted entity.
 * Fail-safe: logs on error instead of throwing.
 */
export async function setTombstone(
  userId: string,
  type: TombstoneEntityType,
  entityId: string,
): Promise<void> {
  try {
    await redis.set(
      tombstoneKey(userId, type, entityId),
      new Date().toISOString(),
      "EX",
      TOMBSTONE_TTL_SECONDS,
    );
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn("Failed to record tombstone in Redis:", error);
  }
}

/**
 * Returns true when the entity was deleted recently (tombstone present).
 * Fail-open: returns false if Redis is unreachable or throws.
 */
export async function isTombstoned(
  userId: string,
  type: TombstoneEntityType,
  entityId: string,
): Promise<boolean> {
  try {
    const value = await redis.get(tombstoneKey(userId, type, entityId));
    return value !== null && value !== undefined;
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn("Failed to check tombstone in Redis (failing open):", error);
    return false;
  }
}

/**
 * Delete the per-entity sync bookkeeping keys (version/state) so a deleted
 * entity does not keep a stale version counter around forever.
 * Fail-safe: logs on error instead of throwing.
 */
export async function clearSyncKeys(
  userId: string,
  type: TombstoneEntityType,
  entityId: string,
): Promise<void> {
  try {
    await redis.del(
      `sync:version:${userId}:${type}:${entityId}`,
      `sync:state:${userId}:${type}:${entityId}`,
    );
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn("Failed to clear sync keys in Redis:", error);
  }
}

/**
 * Full delete bookkeeping: tombstone the entity and drop its sync keys.
 */
export async function markEntityDeleted(
  userId: string,
  type: TombstoneEntityType,
  entityId: string,
): Promise<void> {
  await setTombstone(userId, type, entityId);
  await clearSyncKeys(userId, type, entityId);
}
