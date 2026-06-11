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
 * Integration tests for SpaceGroup API endpoints
 */
import Fastify, { FastifyInstance } from "fastify";
import fastifyJwt from "@fastify/jwt";
import { spaceGroupRoutes } from "../../src/routes/spacegroup.routes";
import { prisma } from "../../src/lib/prisma";
import { redis } from "../../src/lib/redis";

// Mock prisma
jest.mock("../../src/lib/prisma", () => ({
  prisma: {
    spaceGroup: {
      findMany: jest.fn(),
      findFirst: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
    },
    $queryRaw: jest.fn(),
    $transaction: jest.fn(),
  },
}));

// Mock redis (tombstones + sync event publishing)
jest.mock("../../src/lib/redis", () => ({
  redis: {
    get: jest.fn(),
    set: jest.fn(),
    del: jest.fn(),
    publish: jest.fn(),
  },
}));

describe("SpaceGroup API Endpoints", () => {
  let app: FastifyInstance;
  let authToken: string;
  const userId = "test-user-123";

  beforeAll(async () => {
    app = Fastify();
    // Register JWT plugin for test environment
    await app.register(fastifyJwt, {
      secret: "test-jwt-secret-for-integration-tests",
    });
    await app.register(spaceGroupRoutes, { prefix: "/api/v1/space-groups" });
    await app.ready();

    // Generate a valid JWT for tests
    authToken = `Bearer ${app.jwt.sign({ id: userId, email: "test@example.com", tier: "free" })}`;
  });

  beforeEach(() => {
    jest.clearAllMocks();
    // updateSpaceGroup runs in a transaction that starts with a FOR UPDATE
    // row lock + version read via $queryRaw
    (prisma.$transaction as jest.Mock).mockImplementation(async (fn) =>
      fn(prisma),
    );
    (prisma.$queryRaw as jest.Mock).mockResolvedValue([{ version: 0 }]);
    // Defaults: no tombstones, publish/tombstone writes succeed
    (redis.get as jest.Mock).mockResolvedValue(null);
    (redis.set as jest.Mock).mockResolvedValue("OK");
    (redis.del as jest.Mock).mockResolvedValue(1);
    (redis.publish as jest.Mock).mockResolvedValue(1);
  });

  afterAll(async () => {
    await app.close();
  });

  describe("GET /api/v1/space-groups", () => {
    it("should return 401 without authentication", async () => {
      const response = await app.inject({
        method: "GET",
        url: "/api/v1/space-groups",
      });

      expect(response.statusCode).toBe(401);
      expect(JSON.parse(response.payload)).toHaveProperty(
        "error",
        "Unauthorized",
      );
    });

    it("should return empty array for new user", async () => {
      (prisma.spaceGroup.findMany as jest.Mock).mockResolvedValue([]);

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/space-groups",
        headers: { authorization: authToken },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data).toEqual([]);
    });

    it("should return space groups for authenticated user", async () => {
      const mockGroups = [
        { id: "sg1", title: "Work", userId, position: 0, collapsed: false },
        { id: "sg2", title: "Personal", userId, position: 1, collapsed: true },
      ];
      (prisma.spaceGroup.findMany as jest.Mock).mockResolvedValue(mockGroups);

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/space-groups",
        headers: { authorization: authToken },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data).toHaveLength(2);
    });
  });

  describe("GET /api/v1/space-groups/:id", () => {
    it("should return a space group by ID", async () => {
      const groupId = "sg-123";
      const mockGroup = {
        id: groupId,
        title: "Work",
        userId,
        position: 0,
        collapsed: false,
      };
      (prisma.spaceGroup.findFirst as jest.Mock).mockResolvedValue(mockGroup);

      const response = await app.inject({
        method: "GET",
        url: `/api/v1/space-groups/${groupId}`,
        headers: { authorization: authToken },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data.id).toBe(groupId);
    });

    it("should return 404 for non-existent space group", async () => {
      (prisma.spaceGroup.findFirst as jest.Mock).mockResolvedValue(null);

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/space-groups/nonexistent",
        headers: { authorization: authToken },
      });

      expect(response.statusCode).toBe(404);
    });
  });

  describe("POST /api/v1/space-groups", () => {
    it("should create a new space group", async () => {
      const input = {
        title: "New Group",
        collapsed: false,
        position: 0,
        color: "#4F46E5",
      };
      const mockGroup = {
        id: "sg-new",
        ...input,
        userId,
        createdAt: new Date(),
        updatedAt: new Date(),
      };

      (prisma.spaceGroup.create as jest.Mock).mockResolvedValue(mockGroup);

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/space-groups",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: input,
      });

      expect(response.statusCode).toBe(201);
      const data = JSON.parse(response.payload);
      expect(data.data).toHaveProperty("title", "New Group");
    });

    it("should return 400 for invalid input", async () => {
      const response = await app.inject({
        method: "POST",
        url: "/api/v1/space-groups",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { invalid: "data" },
      });

      expect(response.statusCode).toBe(400);
    });
  });

  describe("PUT /api/v1/space-groups/:id", () => {
    it("should update a space group", async () => {
      const groupId = "sg-123";
      const updatedGroup = {
        id: groupId,
        title: "New Title",
        userId,
        position: 0,
        collapsed: false,
        version: 1,
      };

      (prisma.spaceGroup.update as jest.Mock).mockResolvedValue(updatedGroup);

      const response = await app.inject({
        method: "PUT",
        url: `/api/v1/space-groups/${groupId}`,
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { title: "New Title" },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data.title).toBe("New Title");
      // version flows through the response
      expect(data.data.version).toBe(1);
    });

    it("should return 409 with the current server copy when baseVersion is stale", async () => {
      const groupId = "sg-123";
      const serverCopy = {
        id: groupId,
        title: "Server Copy",
        userId,
        version: 4,
      };

      (prisma.$queryRaw as jest.Mock).mockResolvedValue([{ version: 4 }]);
      // Route fetches the full current group for the 409 body
      (prisma.spaceGroup.findFirst as jest.Mock).mockResolvedValue(serverCopy);

      const response = await app.inject({
        method: "PUT",
        url: `/api/v1/space-groups/${groupId}`,
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { title: "Stale Write", baseVersion: 2 },
      });

      expect(response.statusCode).toBe(409);
      const data = JSON.parse(response.payload);
      expect(data.error).toBe("Conflict");
      expect(data.data.title).toBe("Server Copy");
      expect(data.data.version).toBe(4);
      expect(prisma.spaceGroup.update).not.toHaveBeenCalled();
    });

    it("should return 410 Gone for a tombstoned space group id", async () => {
      (prisma.$queryRaw as jest.Mock).mockResolvedValue([]); // group does not exist
      (redis.get as jest.Mock).mockResolvedValue(new Date().toISOString()); // tombstone

      const response = await app.inject({
        method: "PUT",
        url: "/api/v1/space-groups/sg-deleted",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { title: "Zombie Group" },
      });

      expect(response.statusCode).toBe(410);
      const data = JSON.parse(response.payload);
      expect(data.error).toBe("Gone");
      expect(data.message).toBe("Entity was deleted");
      expect(redis.get).toHaveBeenCalledWith(
        `tombstone:${userId}:spaceGroup:sg-deleted`,
      );
      expect(prisma.spaceGroup.create).not.toHaveBeenCalled();
    });

    it("should publish a save event after a successful update", async () => {
      const groupId = "sg-123";
      const updatedGroup = {
        id: groupId,
        title: "New Title",
        userId,
        version: 3,
        updatedAt: new Date(),
      };
      (prisma.$queryRaw as jest.Mock).mockResolvedValue([{ version: 2 }]);
      (prisma.spaceGroup.update as jest.Mock).mockResolvedValue(updatedGroup);

      const response = await app.inject({
        method: "PUT",
        url: `/api/v1/space-groups/${groupId}`,
        headers: {
          authorization: authToken,
          "content-type": "application/json",
          "x-device-id": "device-3",
        },
        payload: { title: "New Title", baseVersion: 2 },
      });

      expect(response.statusCode).toBe(200);
      const [channel, message] = (redis.publish as jest.Mock).mock.calls[0];
      expect(channel).toBe(`sync:updates:${userId}`);
      expect(JSON.parse(message)).toEqual(
        expect.objectContaining({
          type: "spaceGroup",
          action: "save",
          entityId: groupId,
          version: 3,
          fromDevice: "device-3",
        }),
      );
    });

    it("should upsert (create) non-existent space group", async () => {
      const input = {
        title: "Upserted Group",
        collapsed: false,
        position: 0,
        color: "#4F46E5",
      };

      const createdGroup = {
        id: "sg-upsert",
        ...input,
        userId,
        version: 1,
        createdAt: new Date(),
        updatedAt: new Date(),
      };

      // First update: row missing -> not found; after create it exists
      (prisma.$queryRaw as jest.Mock)
        .mockResolvedValueOnce([])
        .mockResolvedValue([{ version: 0 }]);

      // Mock create for the upsert logic
      (prisma.spaceGroup.create as jest.Mock).mockResolvedValue(createdGroup);
      // Mock update called after create in upsert flow
      (prisma.spaceGroup.update as jest.Mock).mockResolvedValue(createdGroup);

      const response = await app.inject({
        method: "PUT",
        url: "/api/v1/space-groups/nonexistent",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: input,
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data.title).toBe("Upserted Group");
      // A save event is published for the upsert-create as well
      expect(redis.publish).toHaveBeenCalledTimes(1);
    });
  });

  describe("DELETE /api/v1/space-groups/:id", () => {
    it("should delete a space group", async () => {
      const groupId = "sg-123";
      const mockGroup = { id: groupId, title: "Test", userId };

      (prisma.spaceGroup.findFirst as jest.Mock).mockResolvedValue(mockGroup);
      (prisma.spaceGroup.delete as jest.Mock).mockResolvedValue(mockGroup);

      const response = await app.inject({
        method: "DELETE",
        url: `/api/v1/space-groups/${groupId}`,
        headers: { authorization: authToken },
      });

      expect(response.statusCode).toBe(204);
    });

    it("should tombstone the id, clear sync keys, and publish a delete event", async () => {
      const groupId = "sg-123";
      const mockGroup = { id: groupId, title: "Test", userId };

      (prisma.spaceGroup.findFirst as jest.Mock).mockResolvedValue(mockGroup);
      (prisma.spaceGroup.delete as jest.Mock).mockResolvedValue(mockGroup);

      const response = await app.inject({
        method: "DELETE",
        url: `/api/v1/space-groups/${groupId}`,
        headers: { authorization: authToken, "x-device-id": "device-5" },
      });

      expect(response.statusCode).toBe(204);
      expect(redis.set).toHaveBeenCalledWith(
        `tombstone:${userId}:spaceGroup:${groupId}`,
        expect.any(String),
        "EX",
        60 * 60 * 24 * 30,
      );
      expect(redis.del).toHaveBeenCalledWith(
        `sync:version:${userId}:spaceGroup:${groupId}`,
        `sync:state:${userId}:spaceGroup:${groupId}`,
      );
      const [channel, message] = (redis.publish as jest.Mock).mock.calls[0];
      expect(channel).toBe(`sync:updates:${userId}`);
      expect(JSON.parse(message)).toEqual(
        expect.objectContaining({
          type: "spaceGroup",
          action: "delete",
          entityId: groupId,
          fromDevice: "device-5",
        }),
      );
    });

    it("should return 404 for non-existent space group", async () => {
      (prisma.spaceGroup.findFirst as jest.Mock).mockResolvedValue(null);

      const response = await app.inject({
        method: "DELETE",
        url: "/api/v1/space-groups/nonexistent",
        headers: { authorization: authToken },
      });

      expect(response.statusCode).toBe(404);
    });

    it("should handle non-Error thrown in delete", async () => {
      (prisma.spaceGroup.findFirst as jest.Mock).mockRejectedValue(
        "string error",
      );

      const response = await app.inject({
        method: "DELETE",
        url: "/api/v1/space-groups/nonexistent",
        headers: { authorization: authToken },
      });

      expect(response.statusCode).toBe(404);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Space group not found");
    });
  });

  describe("error handling", () => {
    it("should handle non-Error thrown in GET /:id", async () => {
      (prisma.spaceGroup.findFirst as jest.Mock).mockRejectedValue(
        "string error",
      );

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/space-groups/test-id",
        headers: { authorization: authToken },
      });

      expect(response.statusCode).toBe(404);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Space group not found");
    });

    it("should handle non-Error thrown in POST", async () => {
      (prisma.spaceGroup.create as jest.Mock).mockRejectedValue("string error");

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/space-groups",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { title: "Test", collapsed: false, position: 0 },
      });

      expect(response.statusCode).toBe(400);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Invalid input");
    });

    it("should handle non-Error thrown in PUT", async () => {
      (prisma.spaceGroup.findFirst as jest.Mock).mockResolvedValue({
        id: "test",
        userId,
      });
      (prisma.spaceGroup.update as jest.Mock).mockRejectedValue("string error");

      const response = await app.inject({
        method: "PUT",
        url: "/api/v1/space-groups/test-id",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { title: "Updated" },
      });

      expect(response.statusCode).toBe(400);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Invalid input");
    });

    it("should handle upsert creation failure with non-Error", async () => {
      // Row missing -> updateSpaceGroup throws 'Space group not found' (upsert path)
      (prisma.$queryRaw as jest.Mock).mockResolvedValue([]);
      // Create throws non-Error during upsert
      (prisma.spaceGroup.create as jest.Mock).mockRejectedValue("string error");

      const response = await app.inject({
        method: "PUT",
        url: "/api/v1/space-groups/nonexistent",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { title: "Upsert Test", collapsed: false, position: 0 },
      });

      expect(response.statusCode).toBe(400);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Invalid input for upsert");
    });

    it("should handle upsert creation failure with Error", async () => {
      (prisma.$queryRaw as jest.Mock).mockResolvedValue([]);
      (prisma.spaceGroup.create as jest.Mock).mockRejectedValue(
        new Error("Create during upsert failed"),
      );

      const response = await app.inject({
        method: "PUT",
        url: "/api/v1/space-groups/nonexistent",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { title: "Upsert Test", collapsed: false, position: 0 },
      });

      expect(response.statusCode).toBe(400);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Create during upsert failed");
    });
  });
});
