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
 * Integration tests for workspace API endpoints
 */
import Fastify, { FastifyInstance } from "fastify";
import fastifyJwt from "@fastify/jwt";
import { workspaceRoutes } from "../../src/routes/workspace.routes";
import { prisma } from "../../src/lib/prisma";
import { redis } from "../../src/lib/redis";
import { PermissionService } from "../../src/services/permission.service";
import { ForbiddenError, NotFoundError } from "../../src/lib/errors";

// Mock prisma
jest.mock("../../src/lib/prisma", () => ({
  prisma: {
    workspace: {
      findMany: jest.fn(),
      findFirst: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
      count: jest.fn(),
    },
    tab: {
      findMany: jest.fn(),
      findUnique: jest.fn(),
      deleteMany: jest.fn(),
      createMany: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
    },
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

// Mock the authorization chokepoint. This suite verifies that single-OWNER
// behavior is unchanged by the sharing refactor; the real permission logic
// (collaborators, the 403-vs-404 distinction) is covered by
// permission.service.test.ts and the sharing integration tests. Default below:
// the caller is the owner, so every requireRole passes.
jest.mock("../../src/services/permission.service");
const mockPermission = jest.mocked(PermissionService);

/**
 * Mock transaction client for WorkspaceService.updateWorkspace: $queryRaw for
 * the FOR UPDATE row lock + version/settings read, then the delegates.
 */
const makeUpdateTx = (workspace: Record<string, unknown>) => ({
  $queryRaw: jest.fn().mockResolvedValue([{ version: 0, settings: {} }]),
  workspace: {
    update: jest.fn().mockResolvedValue(workspace),
    findUnique: jest.fn().mockResolvedValue(workspace),
  },
  section: {
    deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
    createMany: jest.fn(),
  },
  note: {
    deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
    createMany: jest.fn(),
  },
  task: {
    deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
    createMany: jest.fn(),
  },
  resource: {
    deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
    createMany: jest.fn(),
  },
  tab: {
    deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
    createMany: jest.fn(),
  },
});

describe("Workspace API Endpoints", () => {
  let app: FastifyInstance;
  let authToken: string;
  const userId = "test-user-123";

  beforeAll(async () => {
    app = Fastify();
    // Register JWT plugin for test environment
    await app.register(fastifyJwt, {
      secret: "test-jwt-secret-for-integration-tests",
    });
    await app.register(workspaceRoutes, { prefix: "/api/v1/workspaces" });
    await app.ready();

    // Generate a valid JWT for tests
    authToken = `Bearer ${app.jwt.sign({ id: userId, email: "test@example.com", tier: "free" })}`;
  });

  beforeEach(() => {
    jest.clearAllMocks();
    // Defaults: no tombstones, publish/tombstone writes succeed
    (redis.get as jest.Mock).mockResolvedValue(null);
    (redis.set as jest.Mock).mockResolvedValue("OK");
    (redis.del as jest.Mock).mockResolvedValue(1);
    (redis.publish as jest.Mock).mockResolvedValue(1);
    // Default: the caller is the owner — every role requirement is satisfied.
    mockPermission.requireRole.mockResolvedValue("owner");
    mockPermission.resolveAccess.mockResolvedValue("owner");
    mockPermission.listAccessUserIds.mockResolvedValue([]);
  });

  afterAll(async () => {
    await app.close();
  });

  describe("GET /api/v1/workspaces", () => {
    it("should return 401 without authentication", async () => {
      const response = await app.inject({
        method: "GET",
        url: "/api/v1/workspaces",
      });

      expect(response.statusCode).toBe(401);
      expect(JSON.parse(response.payload)).toHaveProperty(
        "error",
        "Unauthorized",
      );
    });

    it("should return 401 for an expired access token (not 500)", async () => {
      // Access tokens now carry an expiry; an expired token must be rejected by
      // the auth middleware with 401, never accepted or surfaced as a 500. The
      // exp claim is set in the past directly (negative expiresIn is rejected by
      // the signer).
      // exp is a standard JWT claim; the payload type only declares app fields,
      // so cast to set an already-past expiry.
      const expiredPayload = {
        id: userId,
        email: "test@example.com",
        tier: "free",
        exp: Math.floor(Date.now() / 1000) - 60,
      };
      const expiredToken = app.jwt.sign(
        expiredPayload as unknown as Parameters<typeof app.jwt.sign>[0],
      );

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/workspaces",
        headers: { authorization: `Bearer ${expiredToken}` },
      });

      expect(response.statusCode).toBe(401);
      expect(JSON.parse(response.payload)).toHaveProperty(
        "error",
        "Unauthorized",
      );
    });

    it("should return empty array for new user", async () => {
      (prisma.workspace.findMany as jest.Mock).mockResolvedValue([]);

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/workspaces",
        headers: {
          authorization: authToken,
        },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data).toEqual([]);
    });

    it("should return workspaces for authenticated user", async () => {
      const mockWorkspaces = [
        { id: "ws1", name: "Work", userId, tabs: [] },
        { id: "ws2", name: "Personal", userId, tabs: [] },
      ];
      (prisma.workspace.findMany as jest.Mock).mockResolvedValue(
        mockWorkspaces,
      );

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/workspaces",
        headers: {
          authorization: authToken,
        },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data).toHaveLength(2);
    });
  });

  describe("POST /api/v1/workspaces", () => {
    it("should create a new workspace", async () => {
      const input = {
        name: "Test Workspace",
        description: "Test description",
        color: "#4F46E5",
        icon: "📁",
        position: 0,
        settings: {},
      };
      const mockWorkspace = {
        id: "ws-new",
        ...input,
        userId,
        tabs: [],
        createdAt: new Date(),
        updatedAt: new Date(),
      };

      (prisma.workspace.count as jest.Mock).mockResolvedValue(5);
      (prisma.workspace.create as jest.Mock).mockResolvedValue(mockWorkspace);

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/workspaces",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: input,
      });

      expect(response.statusCode).toBe(201);
      const data = JSON.parse(response.payload);
      expect(data.data).toHaveProperty("name", "Test Workspace");
    });

    it("should validate workspace name is required", async () => {
      const response = await app.inject({
        method: "POST",
        url: "/api/v1/workspaces",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { description: "Missing name" },
      });

      expect(response.statusCode).toBe(400);
    });

    it("should enforce workspace limit for free tier", async () => {
      (prisma.workspace.count as jest.Mock).mockResolvedValue(10);

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/workspaces",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { name: "Test", position: 0, settings: {} },
      });

      expect(response.statusCode).toBe(403);
      const data = JSON.parse(response.payload);
      expect(data.message).toContain("Maximum number");
    });
  });

  describe("PUT /api/v1/workspaces/:id", () => {
    it("should update workspace name", async () => {
      const workspaceId = "ws-123";
      const updatedWorkspace = {
        id: workspaceId,
        name: "New Name",
        userId,
        version: 1,
        tabs: [],
      };

      const tx = makeUpdateTx(updatedWorkspace);
      (prisma.$transaction as jest.Mock).mockImplementation(async (fn) =>
        fn(tx),
      );

      const response = await app.inject({
        method: "PUT",
        url: `/api/v1/workspaces/${workspaceId}`,
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { name: "New Name" },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data.name).toBe("New Name");
      // version flows through the response
      expect(data.data.version).toBe(1);
    });

    it("should return 409 with the current server copy when baseVersion is stale", async () => {
      const workspaceId = "ws-123";
      const serverCopy = {
        id: workspaceId,
        name: "Server Copy",
        userId,
        version: 5,
        settings: {},
        tabs: [],
      };

      const tx = makeUpdateTx(serverCopy);
      tx.$queryRaw.mockResolvedValue([{ version: 5, settings: {} }]);
      (prisma.$transaction as jest.Mock).mockImplementation(async (fn) =>
        fn(tx),
      );
      // Route fetches the full current workspace for the 409 body
      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue(serverCopy);

      const response = await app.inject({
        method: "PUT",
        url: `/api/v1/workspaces/${workspaceId}`,
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { name: "Stale Write", baseVersion: 3 },
      });

      expect(response.statusCode).toBe(409);
      const data = JSON.parse(response.payload);
      expect(data.error).toBe("Conflict");
      expect(data.data.name).toBe("Server Copy");
      expect(data.data.version).toBe(5);
      // Nothing was written
      expect(tx.workspace.update).not.toHaveBeenCalled();
    });

    it("should return 410 Gone for a tombstoned workspace id", async () => {
      const tx = makeUpdateTx({});
      tx.$queryRaw.mockResolvedValue([]); // workspace does not exist
      (prisma.$transaction as jest.Mock).mockImplementation(async (fn) =>
        fn(tx),
      );
      // Tombstone present in redis
      (redis.get as jest.Mock).mockResolvedValue(new Date().toISOString());

      const response = await app.inject({
        method: "PUT",
        url: "/api/v1/workspaces/ws-deleted",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { name: "Zombie Workspace" },
      });

      expect(response.statusCode).toBe(410);
      const data = JSON.parse(response.payload);
      expect(data.error).toBe("Gone");
      expect(data.message).toBe("Entity was deleted");
      expect(redis.get).toHaveBeenCalledWith(
        `tombstone:${userId}:workspace:ws-deleted`,
      );
      // No upsert-create happened
      expect(prisma.workspace.create).not.toHaveBeenCalled();
    });

    it("should publish a save event after a successful update", async () => {
      const workspaceId = "ws-123";
      const updatedWorkspace = {
        id: workspaceId,
        name: "New Name",
        userId,
        version: 2,
        updatedAt: new Date(),
        tabs: [],
      };

      const tx = makeUpdateTx(updatedWorkspace);
      tx.$queryRaw.mockResolvedValue([{ version: 1, settings: {} }]);
      (prisma.$transaction as jest.Mock).mockImplementation(async (fn) =>
        fn(tx),
      );

      const response = await app.inject({
        method: "PUT",
        url: `/api/v1/workspaces/${workspaceId}`,
        headers: {
          authorization: authToken,
          "content-type": "application/json",
          "x-device-id": "device-7",
        },
        payload: { name: "New Name", baseVersion: 1 },
      });

      expect(response.statusCode).toBe(200);
      expect(redis.publish).toHaveBeenCalledTimes(1);
      const [channel, message] = (redis.publish as jest.Mock).mock.calls[0];
      expect(channel).toBe(`sync:updates:${userId}`);
      expect(JSON.parse(message)).toEqual(
        expect.objectContaining({
          type: "workspace",
          action: "save",
          entityId: workspaceId,
          version: 2,
          fromDevice: "device-7",
        }),
      );
    });

    it("should publish save events with fromDevice unknown when no x-device-id is sent", async () => {
      const workspaceId = "ws-123";
      const updatedWorkspace = {
        id: workspaceId,
        name: "New Name",
        userId,
        version: 1,
        tabs: [],
      };

      const tx = makeUpdateTx(updatedWorkspace);
      (prisma.$transaction as jest.Mock).mockImplementation(async (fn) =>
        fn(tx),
      );

      const response = await app.inject({
        method: "PUT",
        url: `/api/v1/workspaces/${workspaceId}`,
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { name: "New Name" },
      });

      expect(response.statusCode).toBe(200);
      const [, message] = (redis.publish as jest.Mock).mock.calls[0];
      expect(JSON.parse(message).fromDevice).toBe("unknown");
    });

    it("should upsert (create) non-existent workspace", async () => {
      const input = {
        name: "Upserted Workspace",
        description: "Test",
        color: "#4F46E5",
        icon: "wd",
        position: 0,
        settings: {},
      };

      const createdWorkspace = {
        id: "ws-upsert",
        ...input,
        userId,
        version: 1,
        tabs: [],
        createdAt: new Date(),
        updatedAt: new Date(),
      };

      (prisma.workspace.count as jest.Mock).mockResolvedValue(0);
      // The id is genuinely new, so exists() must report absent — otherwise the
      // route 404-masks instead of taking the upsert-create path.
      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue(null);
      // Mock create for the upsert logic
      (prisma.workspace.create as jest.Mock).mockResolvedValue(
        createdWorkspace,
      );

      const tx = makeUpdateTx(createdWorkspace);
      // First update: workspace missing -> not found; after create it exists
      tx.$queryRaw
        .mockResolvedValueOnce([])
        .mockResolvedValue([{ version: 0, settings: {} }]);
      (prisma.$transaction as jest.Mock).mockImplementation(async (fn) =>
        fn(tx),
      );

      const response = await app.inject({
        method: "PUT",
        url: "/api/v1/workspaces/nonexistent",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: input,
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data.name).toBe("Upserted Workspace");
      // A save event is published for the upsert-create as well
      expect(redis.publish).toHaveBeenCalledTimes(1);
    });
  });

  describe("DELETE /api/v1/workspaces/:id", () => {
    it("should delete a workspace and its tabs", async () => {
      const workspaceId = "ws-123";
      const mockWorkspace = { id: workspaceId, name: "Test", userId, tabs: [] };

      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue(
        mockWorkspace,
      );
      (prisma.workspace.delete as jest.Mock).mockResolvedValue(mockWorkspace);

      const response = await app.inject({
        method: "DELETE",
        url: `/api/v1/workspaces/${workspaceId}`,
        headers: {
          authorization: authToken,
        },
      });

      expect(response.statusCode).toBe(204);
    });

    it("should tombstone the id, clear sync keys, and publish a delete event", async () => {
      const workspaceId = "ws-123";
      const mockWorkspace = { id: workspaceId, name: "Test", userId, tabs: [] };

      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue(
        mockWorkspace,
      );
      (prisma.workspace.delete as jest.Mock).mockResolvedValue(mockWorkspace);

      const response = await app.inject({
        method: "DELETE",
        url: `/api/v1/workspaces/${workspaceId}`,
        headers: {
          authorization: authToken,
          "x-device-id": "device-9",
        },
      });

      expect(response.statusCode).toBe(204);
      // Tombstone with a 30-day TTL
      expect(redis.set).toHaveBeenCalledWith(
        `tombstone:${userId}:workspace:${workspaceId}`,
        expect.any(String),
        "EX",
        60 * 60 * 24 * 30,
      );
      // Sync version/state keys cleared
      expect(redis.del).toHaveBeenCalledWith(
        `sync:version:${userId}:workspace:${workspaceId}`,
        `sync:state:${userId}:workspace:${workspaceId}`,
      );
      // Delete event published
      const [channel, message] = (redis.publish as jest.Mock).mock.calls[0];
      expect(channel).toBe(`sync:updates:${userId}`);
      expect(JSON.parse(message)).toEqual(
        expect.objectContaining({
          type: "workspace",
          action: "delete",
          entityId: workspaceId,
          fromDevice: "device-9",
        }),
      );
    });

    it("should still delete (204) when redis tombstone write fails", async () => {
      const workspaceId = "ws-123";
      const mockWorkspace = { id: workspaceId, name: "Test", userId, tabs: [] };

      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue(
        mockWorkspace,
      );
      (prisma.workspace.delete as jest.Mock).mockResolvedValue(mockWorkspace);
      (redis.set as jest.Mock).mockRejectedValue(new Error("redis down"));

      const response = await app.inject({
        method: "DELETE",
        url: `/api/v1/workspaces/${workspaceId}`,
        headers: { authorization: authToken },
      });

      expect(response.statusCode).toBe(204);
    });

    it("should return 404 for non-existent workspace", async () => {
      // Permission resolution reports no access for a non-existent space.
      mockPermission.requireRole.mockRejectedValueOnce(new NotFoundError());

      const response = await app.inject({
        method: "DELETE",
        url: "/api/v1/workspaces/nonexistent",
        headers: {
          authorization: authToken,
        },
      });

      expect(response.statusCode).toBe(404);
      // No tombstone or event for a failed delete
      expect(redis.set).not.toHaveBeenCalled();
      expect(redis.publish).not.toHaveBeenCalled();
    });
  });

  describe("POST /api/v1/workspaces/:id/tabs", () => {
    it("should save tabs to workspace", async () => {
      const workspaceId = "ws-123";
      const mockWorkspace = { id: workspaceId, name: "Test", userId, tabs: [] };
      const tabs = [
        {
          url: "https://example.com",
          title: "Example",
          position: 0,
          isPinned: false,
          metadata: {},
        },
      ];
      const updatedWorkspace = { ...mockWorkspace, tabs };

      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue(
        mockWorkspace,
      );
      (prisma.$transaction as jest.Mock).mockResolvedValue(updatedWorkspace);

      const response = await app.inject({
        method: "POST",
        url: `/api/v1/workspaces/${workspaceId}/tabs`,
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { tabs },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data.tabs).toHaveLength(1);
    });
  });

  describe("POST /api/v1/workspaces/tabs/bulk", () => {
    it("should bulk delete tabs", async () => {
      const tabId1 = "550e8400-e29b-41d4-a716-446655440000";
      const tabId2 = "550e8400-e29b-41d4-a716-446655440001";
      const tabs = [
        { id: tabId1, workspace: { userId } },
        { id: tabId2, workspace: { userId } },
      ];
      (prisma.tab.findMany as jest.Mock).mockResolvedValue(tabs);
      (prisma.tab.deleteMany as jest.Mock).mockResolvedValue({ count: 2 });

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/workspaces/tabs/bulk",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: {
          tabIds: [tabId1, tabId2],
          operation: "close",
        },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data.deleted).toBe(2);
    });

    it("should bulk pin tabs", async () => {
      const tabId1 = "550e8400-e29b-41d4-a716-446655440000";
      const tabId2 = "550e8400-e29b-41d4-a716-446655440001";
      const tabs = [
        { id: tabId1, workspace: { userId } },
        { id: tabId2, workspace: { userId } },
      ];
      (prisma.tab.findMany as jest.Mock).mockResolvedValue(tabs);
      (prisma.tab.updateMany as jest.Mock).mockResolvedValue({ count: 2 });

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/workspaces/tabs/bulk",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: {
          tabIds: [tabId1, tabId2],
          operation: "pin",
        },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data.updated).toBe(2);
    });

    it("should bulk unpin tabs", async () => {
      const tabId1 = "550e8400-e29b-41d4-a716-446655440000";
      const tabs = [{ id: tabId1, workspace: { userId } }];
      (prisma.tab.findMany as jest.Mock).mockResolvedValue(tabs);
      (prisma.tab.updateMany as jest.Mock).mockResolvedValue({ count: 1 });

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/workspaces/tabs/bulk",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: {
          tabIds: [tabId1],
          operation: "unpin",
        },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data.updated).toBe(1);
    });

    it("should return 400 for invalid operation", async () => {
      const response = await app.inject({
        method: "POST",
        url: "/api/v1/workspaces/tabs/bulk",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: {
          tabIds: ["550e8400-e29b-41d4-a716-446655440000"],
          operation: "invalid",
        },
      });

      expect(response.statusCode).toBe(400);
    });

    it("should return 403 for unauthorized tabs", async () => {
      const tabId1 = "550e8400-e29b-41d4-a716-446655440000";
      const tabs = [{ id: tabId1, workspace: { userId: "different-user" } }];

      (prisma.tab.findMany as jest.Mock).mockResolvedValue(tabs);
      // The caller lacks edit on the tab's workspace.
      mockPermission.requireRole.mockRejectedValue(new ForbiddenError());

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/workspaces/tabs/bulk",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: {
          tabIds: [tabId1],
          operation: "close",
        },
      });

      // Should get 403 because tabs don't belong to user
      expect(response.statusCode).toBe(403);
    });

    it("should return 400 for suspend operation", async () => {
      const tabId1 = "550e8400-e29b-41d4-a716-446655440000";

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/workspaces/tabs/bulk",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: {
          tabIds: [tabId1],
          operation: "suspend",
        },
      });

      expect(response.statusCode).toBe(400);
      const data = JSON.parse(response.payload);
      expect(data.message).toContain("client side");
    });
  });

  describe("POST /api/v1/workspaces/tabs/move", () => {
    it("should move tab to another workspace", async () => {
      const tabId = "550e8400-e29b-41d4-a716-446655440000";
      const targetWorkspaceId = "550e8400-e29b-41d4-a716-446655440001";
      const mockTab = {
        id: tabId,
        workspaceId: "ws-source-123",
        workspace: { userId },
      };
      const mockTargetWorkspace = {
        id: targetWorkspaceId,
        userId,
        name: "Target",
      };
      const updatedTab = { ...mockTab, workspaceId: targetWorkspaceId };

      (prisma.tab.findUnique as jest.Mock).mockResolvedValue(mockTab);
      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue(
        mockTargetWorkspace,
      );
      (prisma.tab.update as jest.Mock).mockResolvedValue(updatedTab);

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/workspaces/tabs/move",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: {
          tabId,
          targetWorkspaceId,
          position: 0,
        },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data.workspaceId).toBe(targetWorkspaceId);
    });

    it("should return 404 for non-existent tab", async () => {
      const tabId = "550e8400-e29b-41d4-a716-446655440000";
      const targetWorkspaceId = "550e8400-e29b-41d4-a716-446655440001";

      (prisma.tab.findUnique as jest.Mock).mockResolvedValue(null);

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/workspaces/tabs/move",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: {
          tabId,
          targetWorkspaceId,
        },
      });

      expect(response.statusCode).toBe(404);
    });

    it("should return 404 for non-existent target workspace", async () => {
      const tabId = "550e8400-e29b-41d4-a716-446655440000";
      const targetWorkspaceId = "550e8400-e29b-41d4-a716-446655440001";
      const mockTab = {
        id: tabId,
        workspaceId: "ws-source-123",
        workspace: { userId },
      };

      (prisma.tab.findUnique as jest.Mock).mockResolvedValue(mockTab);
      // The target workspace does not exist.
      mockPermission.requireRole.mockRejectedValueOnce(new NotFoundError());

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/workspaces/tabs/move",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: {
          tabId,
          targetWorkspaceId,
        },
      });

      expect(response.statusCode).toBe(404);
    });
  });

  describe("POST /api/v1/workspaces/tabs/reorder", () => {
    it("should reorder a tab within workspace", async () => {
      const tabId = "550e8400-e29b-41d4-a716-446655440000";
      const mockTab = {
        id: tabId,
        workspaceId: "ws-123",
        workspace: { userId },
        position: 0,
      };
      const updatedTab = { ...mockTab, position: 2 };

      (prisma.tab.findUnique as jest.Mock).mockResolvedValue(mockTab);
      (prisma.tab.update as jest.Mock).mockResolvedValue(updatedTab);

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/workspaces/tabs/reorder",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: {
          tabId,
          newPosition: 2,
        },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data.position).toBe(2);
    });

    it("should return 404 for non-existent tab", async () => {
      const tabId = "550e8400-e29b-41d4-a716-446655440000";

      (prisma.tab.findUnique as jest.Mock).mockResolvedValue(null);

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/workspaces/tabs/reorder",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: {
          tabId,
          newPosition: 2,
        },
      });

      expect(response.statusCode).toBe(404);
    });
  });

  describe("GET /api/v1/workspaces/:id", () => {
    it("should return workspace with tabs", async () => {
      const workspaceId = "ws-123";
      const seenAt = new Date();
      const mockWorkspace = {
        id: workspaceId,
        name: "Test Workspace",
        userId,
        version: 3,
        activeDeviceId: "device-1",
        activeDeviceSeenAt: seenAt,
        tabs: [
          {
            id: "tab-1",
            url: "https://example.com",
            title: "Example",
            position: 0,
          },
        ],
      };

      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue(
        mockWorkspace,
      );

      const response = await app.inject({
        method: "GET",
        url: `/api/v1/workspaces/${workspaceId}`,
        headers: {
          authorization: authToken,
        },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data.id).toBe(workspaceId);
      expect(data.data.tabs).toHaveLength(1);
      // Concurrency/lease fields flow through GET responses
      expect(data.data.version).toBe(3);
      expect(data.data.activeDeviceId).toBe("device-1");
      expect(data.data.activeDeviceSeenAt).toBe(seenAt.toISOString());
    });

    it("should return 404 for non-existent workspace", async () => {
      const workspaceId = "ws-nonexistent";

      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue(null);

      const response = await app.inject({
        method: "GET",
        url: `/api/v1/workspaces/${workspaceId}`,
        headers: {
          authorization: authToken,
        },
      });

      expect(response.statusCode).toBe(404);
    });
  });

  describe("POST /api/v1/workspaces/:id/tabs - Error Cases", () => {
    it("should return 404 when workspace not found", async () => {
      const workspaceId = "ws-123";
      const tabs = [
        {
          url: "https://example.com",
          title: "Example",
          position: 0,
        },
      ];

      // No access to the target workspace.
      mockPermission.requireRole.mockRejectedValueOnce(new NotFoundError());

      const response = await app.inject({
        method: "POST",
        url: `/api/v1/workspaces/${workspaceId}/tabs`,
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { tabs },
      });

      expect(response.statusCode).toBe(404);
    });

    it("should return 400 with invalid tab data", async () => {
      const workspaceId = "ws-123";

      const response = await app.inject({
        method: "POST",
        url: `/api/v1/workspaces/${workspaceId}/tabs`,
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        // Empty url is invalid; note non-http schemes (about:, chrome:) are
        // intentionally accepted since Chrome emits them
        payload: { tabs: [{ url: "" }] },
      });

      expect(response.statusCode).toBe(400);
    });
  });

  describe("error handling", () => {
    it("should handle upsert failure with Error", async () => {
      // Workspace row is missing -> updateWorkspace throws 'Workspace not found'
      const tx = makeUpdateTx({});
      tx.$queryRaw.mockResolvedValue([]);
      (prisma.$transaction as jest.Mock).mockImplementation(async (fn) =>
        fn(tx),
      );
      // Simulate create failure during upsert
      (prisma.workspace.count as jest.Mock).mockResolvedValue(10); // Exceed limit
      (prisma.workspace.create as jest.Mock).mockRejectedValue(
        new Error("Maximum number of workspaces exceeded"),
      );

      const response = await app.inject({
        method: "PUT",
        url: "/api/v1/workspaces/nonexistent",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { name: "Upsert Test", position: 0, settings: {} },
      });

      expect(response.statusCode).toBe(400);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toContain("Maximum number of workspaces");
    });

    it("should handle upsert failure with non-Error", async () => {
      const tx = makeUpdateTx({});
      tx.$queryRaw.mockResolvedValue([]);
      (prisma.$transaction as jest.Mock).mockImplementation(async (fn) =>
        fn(tx),
      );
      (prisma.workspace.count as jest.Mock).mockResolvedValue(0);
      (prisma.workspace.create as jest.Mock).mockRejectedValue("string error");

      const response = await app.inject({
        method: "PUT",
        url: "/api/v1/workspaces/nonexistent",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { name: "Upsert Test", position: 0, settings: {} },
      });

      expect(response.statusCode).toBe(400);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Invalid input for upsert");
    });

    it("should handle PUT update with non-Error thrown", async () => {
      (prisma.$transaction as jest.Mock).mockRejectedValue("string error");

      const response = await app.inject({
        method: "PUT",
        url: "/api/v1/workspaces/ws-123",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { name: "Updated" },
      });

      expect(response.statusCode).toBe(400);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Invalid input");
    });

    it("should handle tabs/move with non-Error thrown", async () => {
      const tabId = "550e8400-e29b-41d4-a716-446655440000";
      const targetWorkspaceId = "550e8400-e29b-41d4-a716-446655440001";

      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue({
        id: targetWorkspaceId,
        userId,
      });
      (prisma.tab.findUnique as jest.Mock).mockRejectedValue("string error");

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/workspaces/tabs/move",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { tabId, targetWorkspaceId },
      });

      expect(response.statusCode).toBe(400);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Invalid input");
    });

    it("should handle tabs/reorder with non-Error thrown", async () => {
      const tabId = "550e8400-e29b-41d4-a716-446655440000";

      (prisma.tab.findUnique as jest.Mock).mockRejectedValue("string error");

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/workspaces/tabs/reorder",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { tabId, newPosition: 0 },
      });

      expect(response.statusCode).toBe(400);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Invalid input");
    });

    it("should handle tabs/bulk with non-Error thrown", async () => {
      const tabId1 = "550e8400-e29b-41d4-a716-446655440000";
      (prisma.tab.findMany as jest.Mock).mockRejectedValue("string error");

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/workspaces/tabs/bulk",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { tabIds: [tabId1], operation: "close" },
      });

      expect(response.statusCode).toBe(400);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Invalid input");
    });

    it("should handle DELETE with non-Error thrown", async () => {
      (prisma.workspace.delete as jest.Mock).mockRejectedValue("string error");

      const response = await app.inject({
        method: "DELETE",
        url: "/api/v1/workspaces/ws-123",
        headers: { authorization: authToken },
      });

      expect(response.statusCode).toBe(404);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Workspace not found");
    });

    it("should handle GET /:id with non-Error thrown", async () => {
      (prisma.workspace.findFirst as jest.Mock).mockRejectedValue(
        "string error",
      );

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/workspaces/ws-123",
        headers: { authorization: authToken },
      });

      expect(response.statusCode).toBe(404);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Workspace not found");
    });

    it("should handle POST /:id/tabs with non-Error thrown", async () => {
      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue({
        id: "ws-123",
        userId,
      });
      (prisma.$transaction as jest.Mock).mockRejectedValue("string error");

      const tabs = [
        {
          url: "https://example.com",
          title: "Test",
          position: 0,
          isPinned: false,
          metadata: {},
        },
      ];

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/workspaces/ws-123/tabs",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { tabs },
      });

      expect(response.statusCode).toBe(400);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Invalid input");
    });

    it("should handle POST create workspace with non-Error thrown", async () => {
      (prisma.workspace.count as jest.Mock).mockResolvedValue(0);
      (prisma.workspace.create as jest.Mock).mockRejectedValue("string error");

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/workspaces",
        headers: {
          authorization: authToken,
          "content-type": "application/json",
        },
        payload: { name: "Test", position: 0, settings: {} },
      });

      expect(response.statusCode).toBe(400);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Invalid input");
    });
  });
});
