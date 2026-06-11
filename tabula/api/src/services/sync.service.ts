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
 * Sync Service - Real-time synchronization across devices
 *
 * Features:
 * - Push/pull sync state using Redis
 * - Delta detection for efficient updates
 * - Conflict resolution (last-write-wins)
 * - SSE stream for real-time notifications
 */
import type { Prisma } from "../generated/prisma/client";
import { redis } from "../lib/redis";
import { prisma } from "../lib/prisma";
import { isTombstoned, markEntityDeleted } from "../lib/tombstones";
import type {
  SyncPushInput,
  SyncPullInput,
  SyncPushResponse,
  SyncPullResponse,
  SyncStatus,
  SyncConflict,
} from "../schemas/sync";

// Redis key prefixes
const SYNC_STATE_PREFIX = "sync:state:";
const SYNC_VERSION_PREFIX = "sync:version:";
const SYNC_DEVICES_PREFIX = "sync:devices:";
const SYNC_CHANGES_PREFIX = "sync:changes:";

// TTLs in seconds
const DEVICE_TTL = 60 * 60; // 1 hour
const CHANGE_TTL = 60 * 60 * 24; // 24 hours

/**
 * Atomic version check-and-increment. Compares the client's version against
 * the stored one and increments in a single Redis round-trip so two
 * concurrent pushes can never both pass the check or be assigned the same
 * version. Returns {1, newVersion} when accepted, {0, currentVersion} on
 * conflict.
 */
const VERSION_CHECK_AND_INCR_LUA = `
local current = tonumber(redis.call('GET', KEYS[1]) or '0')
local client = tonumber(ARGV[1])
if client < current then
  return {0, current}
end
local new = current + 1
redis.call('SET', KEYS[1], tostring(new))
return {1, new}
`;

export class SyncService {
  /**
   * Push local changes to the server
   */
  static async pushChanges(
    userId: string,
    _tier: string,
    input: SyncPushInput,
  ): Promise<SyncPushResponse> {
    // Note: tier-based limits can be added here in the future
    const accepted: string[] = [];
    const rejected: Array<{ entityId: string; reason: string }> = [];
    const conflicts: SyncConflict[] = [];

    // Register device
    await this.registerDevice(userId, input.deviceId);

    // Process changes sequentially - order matters for conflict detection
    // eslint-disable-next-line no-restricted-syntax
    for (const change of input.changes) {
      try {
        // Tombstones: a deleted entity must not be resurrected via push.
        if (change.action !== "delete") {
          // eslint-disable-next-line no-await-in-loop
          const tombstoned = await isTombstoned(
            userId,
            change.type,
            change.entityId,
          );
          if (tombstoned) {
            rejected.push({ entityId: change.entityId, reason: "deleted" });
            // eslint-disable-next-line no-continue
            continue;
          }
        }

        // Atomically compare the client version with the stored one and
        // increment (single Lua EVAL - no check-then-act race).
        const versionKey = `${SYNC_VERSION_PREFIX}${userId}:${change.type}:${change.entityId}`;
        // eslint-disable-next-line no-await-in-loop
        const [versionOk, version] = (await redis.eval(
          VERSION_CHECK_AND_INCR_LUA,
          1,
          versionKey,
          change.version.toString(),
        )) as [number, number];

        if (versionOk === 0) {
          // Conflict detected - get server data for conflict resolution
          const serverDataKey = `${SYNC_STATE_PREFIX}${userId}:${change.type}:${change.entityId}`;
          // eslint-disable-next-line no-await-in-loop
          const serverDataStr = await redis.get(serverDataKey);
          const serverData = serverDataStr ? JSON.parse(serverDataStr) : null;

          conflicts.push({
            entityId: change.entityId,
            entityType: change.type,
            localVersion: change.version,
            remoteVersion: version,
            localUpdatedAt: input.clientTimestamp,
            remoteUpdatedAt: serverData?.updatedAt || new Date(),
          });
          // eslint-disable-next-line no-continue
          continue;
        }

        const newVersion = version;

        // Apply change based on action
        if (change.action === "delete") {
          // eslint-disable-next-line no-await-in-loop
          await this.handleDelete(userId, change.type, change.entityId);
        } else {
          // eslint-disable-next-line no-await-in-loop
          await this.handleUpsert(
            userId,
            change.type,
            change.entityId,
            change.data || {},
          );
        }

        // Store change for other devices to pull
        const changeData = {
          type: change.type,
          action: change.action,
          entityId: change.entityId,
          data: change.data,
          version: newVersion,
          updatedAt: new Date().toISOString(),
          fromDevice: input.deviceId,
        };
        // eslint-disable-next-line no-await-in-loop
        await redis.zadd(
          `${SYNC_CHANGES_PREFIX}${userId}`,
          Date.now(),
          JSON.stringify(changeData),
        );
        // eslint-disable-next-line no-await-in-loop
        await redis.expire(`${SYNC_CHANGES_PREFIX}${userId}`, CHANGE_TTL);

        // Publish to subscribers
        // eslint-disable-next-line no-await-in-loop
        await this.publishChange(userId, input.deviceId, changeData);

        accepted.push(change.entityId);
      } catch (error) {
        rejected.push({
          entityId: change.entityId,
          reason: error instanceof Error ? error.message : "Unknown error",
        });
      }
    }

    // Update last sync time
    await redis.hset(`${SYNC_STATE_PREFIX}${userId}`, {
      lastSyncAt: new Date().toISOString(),
      lastDevice: input.deviceId,
    });

    return {
      accepted,
      rejected,
      conflicts,
      serverTimestamp: new Date(),
    };
  }

  /**
   * Pull remote changes since last sync
   */
  static async pullChanges(
    userId: string,
    input: SyncPullInput,
  ): Promise<SyncPullResponse> {
    // Register device
    await this.registerDevice(userId, input.deviceId);

    // Get changes since last sync
    const lastSyncMs = input.lastSyncAt
      ? new Date(input.lastSyncAt).getTime()
      : 0;
    const changesRaw = await redis.zrangebyscore(
      `${SYNC_CHANGES_PREFIX}${userId}`,
      lastSyncMs + 1,
      "+inf",
    );

    const changes: SyncPullResponse["changes"] = changesRaw
      .map((changeStr) => {
        try {
          return JSON.parse(changeStr);
        } catch {
          return null;
        }
      })
      .filter(
        (change) =>
          change !== null &&
          (!input.entityTypes || input.entityTypes.includes(change.type)) &&
          change.fromDevice !== input.deviceId,
      )
      .map((change) => ({
        type: change.type,
        action: change.action,
        entityId: change.entityId,
        data: change.data,
        version: change.version,
        updatedAt: new Date(change.updatedAt),
      }));

    return {
      changes,
      serverTimestamp: new Date(),
      hasMore: false,
    };
  }

  /**
   * Get current sync status
   */
  static async getSyncStatus(userId: string): Promise<SyncStatus> {
    const state = await redis.hgetall(`${SYNC_STATE_PREFIX}${userId}`);
    const deviceCount = await redis.scard(`${SYNC_DEVICES_PREFIX}${userId}`);
    const pendingCount = await redis.zcard(`${SYNC_CHANGES_PREFIX}${userId}`);

    return {
      lastSyncAt: state.lastSyncAt ? new Date(state.lastSyncAt) : null,
      pendingChanges: pendingCount || 0,
      conflictsCount: 0, // Would need to track separately
      connectedDevices: deviceCount || 0,
    };
  }

  /**
   * Register a device as active
   */
  private static async registerDevice(
    userId: string,
    deviceId: string,
  ): Promise<void> {
    const key = `${SYNC_DEVICES_PREFIX}${userId}`;
    await redis.sadd(key, deviceId);
    await redis.expire(key, DEVICE_TTL);
  }

  /**
   * Publish change to all connected devices via Redis pub/sub
   */
  private static async publishChange(
    userId: string,
    fromDeviceId: string,
    change: Record<string, unknown>,
  ): Promise<void> {
    const channel = `sync:updates:${userId}`;
    await redis.publish(
      channel,
      JSON.stringify({
        ...change,
        fromDevice: fromDeviceId,
      }),
    );
  }

  /**
   * Handle delete operation
   */
  private static async handleDelete(
    userId: string,
    entityType: "workspace" | "spaceGroup",
    entityId: string,
  ): Promise<void> {
    if (entityType === "workspace") {
      await prisma.workspace.deleteMany({
        where: { id: entityId, userId },
      });
    } else if (entityType === "spaceGroup") {
      await prisma.spaceGroup.deleteMany({
        where: { id: entityId, userId },
      });
    }

    // Tombstone the id and clear its sync version/state keys so the entity
    // cannot be resurrected and the keys do not grow without bound.
    await markEntityDeleted(userId, entityType, entityId);
  }

  /**
   * Handle create/update operation.
   *
   * Writes are scoped to the owner: updateMany({ id, userId }) + create when
   * no row matched. An id that exists but belongs to another user is rejected
   * (a bare upsert keyed on id alone would be a cross-tenant write).
   */
  private static async handleUpsert(
    userId: string,
    entityType: "workspace" | "spaceGroup",
    entityId: string,
    data: Record<string, unknown>,
  ): Promise<void> {
    if (entityType === "workspace") {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await prisma.$transaction(async (tx: any) => {
        const updated = await tx.workspace.updateMany({
          where: { id: entityId, userId },
          data: {
            name: data.name as string,
            description: data.description as string | null,
            color: data.color as string | null,
            icon: data.icon as string | null,
            position: data.position as number,
            settings: data.settings as Prisma.JsonObject,
            groupId: data.groupId as string | null,
          },
        });

        if (updated.count === 0) {
          const existing = await tx.workspace.findUnique({
            where: { id: entityId },
            select: { userId: true },
          });
          if (existing) {
            throw new Error("Entity id is already in use");
          }
          await tx.workspace.create({
            data: {
              id: entityId,
              userId,
              name: (data.name as string) || "Untitled",
              description: data.description as string | null,
              color: data.color as string | null,
              icon: data.icon as string | null,
              position: (data.position as number) || 0,
              settings: (data.settings as Prisma.JsonObject) || {},
              groupId: data.groupId as string | null,
            },
          });
        }
      });
    } else if (entityType === "spaceGroup") {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await prisma.$transaction(async (tx: any) => {
        const updated = await tx.spaceGroup.updateMany({
          where: { id: entityId, userId },
          data: {
            title: data.title as string,
            collapsed: data.collapsed as boolean,
            position: data.position as number,
            color: data.color as string | null,
          },
        });

        if (updated.count === 0) {
          const existing = await tx.spaceGroup.findUnique({
            where: { id: entityId },
            select: { userId: true },
          });
          if (existing) {
            throw new Error("Entity id is already in use");
          }
          await tx.spaceGroup.create({
            data: {
              id: entityId,
              userId,
              title: (data.title as string) || "Untitled",
              collapsed: (data.collapsed as boolean) || false,
              position: (data.position as number) || 0,
              color: data.color as string | null,
            },
          });
        }
      });
    }

    // Cache in Redis for quick access
    const stateKey = `${SYNC_STATE_PREFIX}${userId}:${entityType}:${entityId}`;
    await redis.set(
      stateKey,
      JSON.stringify({
        ...data,
        updatedAt: new Date().toISOString(),
      }),
      "EX",
      CHANGE_TTL,
    );
  }

  /**
   * Subscribe to sync updates (for SSE)
   * Returns an async generator for streaming updates.
   *
   * Pass an AbortSignal (wired to the request's close event) so the generator
   * wakes and exits promptly when the client disconnects instead of waiting
   * out the current heartbeat/timeout cycle. The 60s refresh timer is cleared
   * whenever something else wakes the loop, so timers cannot leak.
   */
  static async *subscribeToUpdates(
    userId: string,
    deviceId: string,
    options: { signal?: AbortSignal } = {},
  ): AsyncGenerator<{ type: string; data: unknown }> {
    // Register device
    await this.registerDevice(userId, deviceId);

    // Create a Redis subscriber
    const subscriber = redis.duplicate();
    const channel = `sync:updates:${userId}`;

    await subscriber.subscribe(channel);

    try {
      // Initial connection message
      yield {
        type: "connected",
        data: { timestamp: new Date().toISOString() },
      };

      // Listen for messages using an event-based approach
      const messageQueue: string[] = [];
      let closed = options.signal?.aborted ?? false;
      let wake: (() => void) | null = null;

      const wakeUp = () => {
        if (wake) {
          wake();
          wake = null;
        }
      };

      subscriber.on("message", (_channel: string, message: string) => {
        messageQueue.push(message);
        wakeUp();
      });

      const onAbort = () => {
        closed = true;
        wakeUp();
      };
      options.signal?.addEventListener("abort", onAbort);

      // Heartbeat every 30 seconds
      const heartbeatInterval = setInterval(() => {
        messageQueue.push(
          JSON.stringify({
            type: "heartbeat",
            timestamp: new Date().toISOString(),
          }),
        );
        wakeUp();
      }, 30000);

      try {
        while (!closed) {
          // Wait for a message, disconnect, or the 60s refresh timeout. The
          // timer is cleared when anything else wakes the loop.
          if (messageQueue.length === 0) {
            // eslint-disable-next-line no-await-in-loop, no-loop-func
            await new Promise<void>((resolve) => {
              const timer = setTimeout(() => {
                wake = null;
                resolve();
              }, 60000);
              wake = () => {
                clearTimeout(timer);
                resolve();
              };
            });
          }

          if (closed) break;

          while (messageQueue.length > 0) {
            const message = messageQueue.shift()!;
            try {
              const parsed = JSON.parse(message);
              // Skip messages from same device
              if (parsed.fromDevice !== deviceId) {
                yield { type: "change", data: parsed };
              }
            } catch {
              // Skip invalid JSON
            }
          }
        }
      } finally {
        clearInterval(heartbeatInterval);
        options.signal?.removeEventListener("abort", onAbort);
      }
    } finally {
      await subscriber.unsubscribe(channel);
      await subscriber.quit();
    }
  }
}
