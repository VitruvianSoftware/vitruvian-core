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
 * Unit tests for SyncService
 */
import { SyncService } from "../../src/services/sync.service";
import { redis } from "../../src/lib/redis";
import { prisma } from "../../src/lib/prisma";

// Mock redis
jest.mock("../../src/lib/redis", () => ({
  redis: {
    get: jest.fn(),
    set: jest.fn(),
    del: jest.fn(),
    eval: jest.fn(),
    sadd: jest.fn(),
    scard: jest.fn(),
    expire: jest.fn(),
    hset: jest.fn(),
    hgetall: jest.fn(),
    zadd: jest.fn(),
    zcard: jest.fn(),
    zrangebyscore: jest.fn(),
    publish: jest.fn(),
    duplicate: jest.fn(() => ({
      subscribe: jest.fn(),
      unsubscribe: jest.fn(),
      quit: jest.fn(),
      on: jest.fn(),
    })),
  },
}));

// Mock prisma
jest.mock("../../src/lib/prisma", () => ({
  prisma: {
    workspace: {
      updateMany: jest.fn(),
      findUnique: jest.fn(),
      create: jest.fn(),
      deleteMany: jest.fn(),
    },
    spaceGroup: {
      updateMany: jest.fn(),
      findUnique: jest.fn(),
      create: jest.fn(),
      deleteMany: jest.fn(),
    },
    $transaction: jest.fn(),
  },
}));

describe("SyncService", () => {
  const userId = "test-user-123";
  const tier = "free";
  const deviceId = "device-123";

  /** Default happy-path redis mocks for pushChanges */
  const mockPushRedisDefaults = () => {
    (redis.get as jest.Mock).mockResolvedValue(null); // no tombstone / no state
    (redis.set as jest.Mock).mockResolvedValue("OK");
    (redis.del as jest.Mock).mockResolvedValue(1);
    (redis.eval as jest.Mock).mockResolvedValue([1, 1]); // accepted, version 1
    (redis.zadd as jest.Mock).mockResolvedValue(1);
    (redis.expire as jest.Mock).mockResolvedValue(1);
    (redis.sadd as jest.Mock).mockResolvedValue(1);
    (redis.hset as jest.Mock).mockResolvedValue(1);
    (redis.publish as jest.Mock).mockResolvedValue(1);
  };

  beforeEach(() => {
    jest.clearAllMocks();
    // handleUpsert wraps its writes in a transaction
    (prisma.$transaction as jest.Mock).mockImplementation(async (fn) =>
      fn(prisma),
    );
  });

  describe("pushChanges", () => {
    it("should accept changes when no conflicts", async () => {
      mockPushRedisDefaults();
      (prisma.workspace.updateMany as jest.Mock).mockResolvedValue({
        count: 1,
      });

      const result = await SyncService.pushChanges(userId, tier, {
        deviceId,
        clientTimestamp: new Date(),
        changes: [
          {
            type: "workspace",
            action: "update",
            entityId: "ws-123",
            data: { name: "Test Workspace" },
            version: 0,
          },
        ],
      });

      expect(result.accepted).toContain("ws-123");
      expect(result.conflicts).toHaveLength(0);
      expect(result.rejected).toHaveLength(0);
      // Update is scoped to the owning user (no cross-tenant writes)
      expect(prisma.workspace.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({ where: { id: "ws-123", userId } }),
      );
    });

    it("should perform the version check atomically via a Lua script", async () => {
      mockPushRedisDefaults();
      (prisma.workspace.updateMany as jest.Mock).mockResolvedValue({
        count: 1,
      });

      await SyncService.pushChanges(userId, tier, {
        deviceId,
        clientTimestamp: new Date(),
        changes: [
          {
            type: "workspace",
            action: "update",
            entityId: "ws-123",
            data: { name: "Test" },
            version: 3,
          },
        ],
      });

      expect(redis.eval).toHaveBeenCalledWith(
        expect.stringContaining("redis.call('GET', KEYS[1])"),
        1,
        `sync:version:${userId}:workspace:ws-123`,
        "3",
      );
      // No separate non-atomic GET/SET of the version key
      expect(redis.set).not.toHaveBeenCalledWith(
        `sync:version:${userId}:workspace:ws-123`,
        expect.anything(),
      );
    });

    it("should detect conflicts when version mismatch", async () => {
      mockPushRedisDefaults();
      (redis.eval as jest.Mock).mockResolvedValue([0, 5]); // conflict, server at 5
      (redis.get as jest.Mock)
        .mockResolvedValueOnce(null) // tombstone check
        .mockResolvedValueOnce(
          JSON.stringify({ updatedAt: new Date().toISOString() }),
        ); // server state

      const result = await SyncService.pushChanges(userId, tier, {
        deviceId,
        clientTimestamp: new Date(),
        changes: [
          {
            type: "workspace",
            action: "update",
            entityId: "ws-123",
            data: { name: "Test Workspace" },
            version: 3, // Client version is 3, server is 5
          },
        ],
      });

      expect(result.conflicts).toHaveLength(1);
      expect(result.conflicts[0].entityId).toBe("ws-123");
      expect(result.conflicts[0].remoteVersion).toBe(5);
      expect(result.accepted).toHaveLength(0);
    });

    it("should handle delete operations", async () => {
      mockPushRedisDefaults();
      (prisma.workspace.deleteMany as jest.Mock).mockResolvedValue({
        count: 1,
      });

      const result = await SyncService.pushChanges(userId, tier, {
        deviceId,
        clientTimestamp: new Date(),
        changes: [
          {
            type: "workspace",
            action: "delete",
            entityId: "ws-123",
            version: 0,
          },
        ],
      });

      expect(result.accepted).toContain("ws-123");
      expect(prisma.workspace.deleteMany).toHaveBeenCalledWith({
        where: { id: "ws-123", userId },
      });
      // Tombstone written and sync keys cleared
      expect(redis.set).toHaveBeenCalledWith(
        `tombstone:${userId}:workspace:ws-123`,
        expect.any(String),
        "EX",
        60 * 60 * 24 * 30,
      );
      expect(redis.del).toHaveBeenCalledWith(
        `sync:version:${userId}:workspace:ws-123`,
        `sync:state:${userId}:workspace:ws-123`,
      );
    });

    it("should reject upserts for tombstoned entities with reason deleted", async () => {
      mockPushRedisDefaults();
      (redis.get as jest.Mock).mockResolvedValueOnce(new Date().toISOString()); // tombstone hit

      const result = await SyncService.pushChanges(userId, tier, {
        deviceId,
        clientTimestamp: new Date(),
        changes: [
          {
            type: "workspace",
            action: "update",
            entityId: "ws-deleted",
            data: { name: "Zombie" },
            version: 0,
          },
        ],
      });

      expect(result.rejected).toEqual([
        { entityId: "ws-deleted", reason: "deleted" },
      ]);
      expect(result.accepted).toHaveLength(0);
      expect(redis.eval).not.toHaveBeenCalled();
      expect(prisma.workspace.updateMany).not.toHaveBeenCalled();
    });

    it("should reject writes to an id owned by another user", async () => {
      mockPushRedisDefaults();
      (prisma.workspace.updateMany as jest.Mock).mockResolvedValue({
        count: 0,
      });
      (prisma.workspace.findUnique as jest.Mock).mockResolvedValue({
        userId: "someone-else",
      });

      const result = await SyncService.pushChanges(userId, tier, {
        deviceId,
        clientTimestamp: new Date(),
        changes: [
          {
            type: "workspace",
            action: "update",
            entityId: "ws-foreign",
            data: { name: "Hijack attempt" },
            version: 0,
          },
        ],
      });

      expect(result.accepted).toHaveLength(0);
      expect(result.rejected).toEqual([
        { entityId: "ws-foreign", reason: "Entity id is already in use" },
      ]);
      expect(prisma.workspace.create).not.toHaveBeenCalled();
    });

    it("should create the entity when the id has never been seen", async () => {
      mockPushRedisDefaults();
      (prisma.workspace.updateMany as jest.Mock).mockResolvedValue({
        count: 0,
      });
      (prisma.workspace.findUnique as jest.Mock).mockResolvedValue(null);
      (prisma.workspace.create as jest.Mock).mockResolvedValue({});

      const result = await SyncService.pushChanges(userId, tier, {
        deviceId,
        clientTimestamp: new Date(),
        changes: [
          {
            type: "workspace",
            action: "create",
            entityId: "ws-new",
            data: { id: "ws-new", name: "New Workspace" },
            version: 0,
          },
        ],
      });

      expect(result.accepted).toContain("ws-new");
      expect(prisma.workspace.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            id: "ws-new",
            userId,
            name: "New Workspace",
          }),
        }),
      );
    });

    it("should handle spaceGroup operations", async () => {
      mockPushRedisDefaults();
      (prisma.spaceGroup.updateMany as jest.Mock).mockResolvedValue({
        count: 1,
      });

      const result = await SyncService.pushChanges(userId, tier, {
        deviceId,
        clientTimestamp: new Date(),
        changes: [
          {
            type: "spaceGroup",
            action: "update",
            entityId: "sg-123",
            data: { name: "Updated Group" },
            version: 0,
          },
        ],
      });

      expect(result.accepted).toContain("sg-123");
      expect(prisma.spaceGroup.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({ where: { id: "sg-123", userId } }),
      );
    });

    it("should handle spaceGroup delete", async () => {
      mockPushRedisDefaults();
      (prisma.spaceGroup.deleteMany as jest.Mock).mockResolvedValue({
        count: 1,
      });

      const result = await SyncService.pushChanges(userId, tier, {
        deviceId,
        clientTimestamp: new Date(),
        changes: [
          {
            type: "spaceGroup",
            action: "delete",
            entityId: "sg-123",
            version: 0,
          },
        ],
      });

      expect(result.accepted).toContain("sg-123");
    });
  });

  describe("pullChanges", () => {
    it("should return changes since last sync", async () => {
      const mockChanges = [
        JSON.stringify({
          type: "workspace",
          action: "update",
          entityId: "ws-123",
          data: { name: "Updated" },
          version: 2,
          updatedAt: new Date().toISOString(),
          fromDevice: "other-device",
        }),
      ];

      (redis.sadd as jest.Mock).mockResolvedValue(1);
      (redis.expire as jest.Mock).mockResolvedValue(1);
      (redis.zrangebyscore as jest.Mock).mockResolvedValue(mockChanges);

      const result = await SyncService.pullChanges(userId, {
        deviceId,
        lastSyncAt: new Date(Date.now() - 60000), // 1 minute ago
        entityTypes: ["workspace", "spaceGroup"],
      });

      expect(result.changes).toHaveLength(1);
      expect(result.changes[0].entityId).toBe("ws-123");
    });

    it("should filter out changes from same device", async () => {
      const mockChanges = [
        JSON.stringify({
          type: "workspace",
          action: "update",
          entityId: "ws-123",
          fromDevice: deviceId, // Same device
        }),
      ];

      (redis.sadd as jest.Mock).mockResolvedValue(1);
      (redis.expire as jest.Mock).mockResolvedValue(1);
      (redis.zrangebyscore as jest.Mock).mockResolvedValue(mockChanges);

      const result = await SyncService.pullChanges(userId, {
        deviceId,
        entityTypes: ["workspace", "spaceGroup"],
      });

      expect(result.changes).toHaveLength(0);
    });
  });

  describe("getSyncStatus", () => {
    it("should return current sync status", async () => {
      const mockState = {
        lastSyncAt: new Date().toISOString(),
        lastDevice: deviceId,
      };

      (redis.hgetall as jest.Mock).mockResolvedValue(mockState);
      (redis.scard as jest.Mock).mockResolvedValue(2);
      (redis.zcard as jest.Mock).mockResolvedValue(5);

      const result = await SyncService.getSyncStatus(userId);

      expect(result.connectedDevices).toBe(2);
      expect(result.pendingChanges).toBe(5);
      expect(result.lastSyncAt).not.toBeNull();
    });

    it("should handle empty state", async () => {
      (redis.hgetall as jest.Mock).mockResolvedValue({});
      (redis.scard as jest.Mock).mockResolvedValue(0);
      (redis.zcard as jest.Mock).mockResolvedValue(0);

      const result = await SyncService.getSyncStatus(userId);

      expect(result.connectedDevices).toBe(0);
      expect(result.pendingChanges).toBe(0);
      expect(result.lastSyncAt).toBeNull();
    });
  });

  describe("subscribeToUpdates", () => {
    const flushAsync = () =>
      new Promise((resolve) => {
        setTimeout(resolve, 20);
      });

    const makeSubscriber = () => {
      const handlers: Record<
        string,
        (channel: string, message: string) => void
      > = {};
      return {
        subscribe: jest.fn().mockResolvedValue(1),
        unsubscribe: jest.fn().mockResolvedValue(1),
        quit: jest.fn().mockResolvedValue("OK"),
        on: jest.fn(
          (
            event: string,
            handler: (channel: string, message: string) => void,
          ) => {
            handlers[event] = handler;
          },
        ),
        emitMessage: (channel: string, message: string) =>
          handlers.message?.(channel, message),
      };
    };

    beforeEach(() => {
      (redis.sadd as jest.Mock).mockResolvedValue(1);
      (redis.expire as jest.Mock).mockResolvedValue(1);
    });

    it("should exit promptly and clean up when the client disconnects", async () => {
      const subscriber = makeSubscriber();
      (redis.duplicate as jest.Mock).mockReturnValue(subscriber);

      const controller = new AbortController();
      const gen = SyncService.subscribeToUpdates(userId, deviceId, {
        signal: controller.signal,
      });

      const first = await gen.next();
      expect(first.value).toEqual(
        expect.objectContaining({ type: "connected" }),
      );

      // Start waiting for the next event, then abort (client disconnect)
      const pending = gen.next();
      await flushAsync();
      controller.abort();

      const result = await pending;
      expect(result.done).toBe(true);
      expect(subscriber.unsubscribe).toHaveBeenCalled();
      expect(subscriber.quit).toHaveBeenCalled();
    });

    it("should yield change events and clear the wait timer when a message arrives", async () => {
      const clearTimeoutSpy = jest.spyOn(global, "clearTimeout");
      const subscriber = makeSubscriber();
      (redis.duplicate as jest.Mock).mockReturnValue(subscriber);

      const gen = SyncService.subscribeToUpdates(userId, deviceId);

      await gen.next(); // connected

      const pending = gen.next();
      await flushAsync();
      const callsBefore = clearTimeoutSpy.mock.calls.length;
      subscriber.emitMessage(
        `sync:updates:${userId}`,
        JSON.stringify({
          type: "workspace",
          action: "save",
          fromDevice: "other-device",
        }),
      );

      const result = await pending;
      expect(result.value).toEqual({
        type: "change",
        data: expect.objectContaining({ fromDevice: "other-device" }),
      });
      // The 60s refresh timer must be cleared when a message wakes the loop
      expect(clearTimeoutSpy.mock.calls.length).toBeGreaterThan(callsBefore);

      await gen.return(undefined);
      expect(subscriber.quit).toHaveBeenCalled();
      clearTimeoutSpy.mockRestore();
    });

    it("should skip messages from the same device", async () => {
      const subscriber = makeSubscriber();
      (redis.duplicate as jest.Mock).mockReturnValue(subscriber);

      const controller = new AbortController();
      const gen = SyncService.subscribeToUpdates(userId, deviceId, {
        signal: controller.signal,
      });

      await gen.next(); // connected

      const pending = gen.next();
      await flushAsync();
      // Own message: must NOT be yielded
      subscriber.emitMessage(
        `sync:updates:${userId}`,
        JSON.stringify({
          type: "workspace",
          action: "save",
          fromDevice: deviceId,
        }),
      );
      await flushAsync();
      // Disconnect to unblock the generator
      controller.abort();

      const result = await pending;
      expect(result.done).toBe(true);
    });
  });
});
