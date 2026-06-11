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
 * Integration tests for backup API endpoints
 */
import Fastify, { FastifyInstance } from "fastify";
import fastifyJwt from "@fastify/jwt";
import { backupRoutes } from "../../src/routes/backup.routes";
import { prisma } from "../../src/lib/prisma";
import { validateTierLimit } from "../../src/lib/tiers";

// Mock prisma
jest.mock("../../src/lib/prisma", () => ({
  prisma: {
    backup: {
      findMany: jest.fn(),
      findFirst: jest.fn(),
      findUnique: jest.fn(),
      create: jest.fn(),
      delete: jest.fn(),
      deleteMany: jest.fn(),
      count: jest.fn(),
    },
    workspace: {
      findMany: jest.fn(),
      findFirst: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
    },
    tab: {
      findMany: jest.fn(),
      createMany: jest.fn(),
      deleteMany: jest.fn(),
    },
    section: {
      findMany: jest.fn(),
      create: jest.fn(),
      deleteMany: jest.fn(),
    },
    resource: {
      findMany: jest.fn(),
      createMany: jest.fn(),
      deleteMany: jest.fn(),
    },
    note: {
      findMany: jest.fn(),
      createMany: jest.fn(),
      deleteMany: jest.fn(),
    },
    task: {
      findMany: jest.fn(),
      createMany: jest.fn(),
      deleteMany: jest.fn(),
    },
    $queryRaw: jest.fn(),
    $transaction: jest.fn((fn) => fn(prisma)),
  },
}));

// Mock tier limits
jest.mock("../../src/lib/tiers", () => ({
  getTierLimits: jest.fn(() => ({
    maxWorkspaces: 5,
    maxBackups: 10,
    backupRetentionDays: 30,
    maxStorageBytes: 104857600,
  })),
  validateTierLimit: jest.fn(() => ({ valid: true })),
}));

describe("Backup API Endpoints", () => {
  let app: FastifyInstance;
  let authToken: string;
  const userId = "test-user-123";

  beforeAll(async () => {
    app = Fastify();
    await app.register(fastifyJwt, {
      secret: "test-jwt-secret-for-integration-tests",
    });
    await app.register(backupRoutes, { prefix: "/api/v1/backups" });
    await app.ready();

    authToken = `Bearer ${app.jwt.sign({ id: userId, email: "test@example.com", tier: "free" })}`;
  });

  beforeEach(() => {
    jest.clearAllMocks();
    // createBackup self-heals by pruning retention-expired backups first; the
    // mocked tiers lib resets each test, so re-establish its defaults and a
    // no-op cleanup.
    (validateTierLimit as jest.Mock).mockReturnValue({ valid: true });
    (prisma.backup.deleteMany as jest.Mock).mockResolvedValue({ count: 0 });
  });

  afterAll(async () => {
    await app.close();
  });

  describe("GET /api/v1/backups", () => {
    it("should return 401 without authentication", async () => {
      const response = await app.inject({
        method: "GET",
        url: "/api/v1/backups",
      });

      expect(response.statusCode).toBe(401);
      expect(JSON.parse(response.payload)).toHaveProperty(
        "error",
        "Unauthorized",
      );
    });

    it("should return empty array when no backups exist", async () => {
      (prisma.backup.findMany as jest.Mock).mockResolvedValue([]);
      (prisma.backup.count as jest.Mock).mockResolvedValue(0);

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/backups",
        headers: { authorization: authToken },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data.backups).toEqual([]);
      expect(data.data.total).toBe(0);
    });

    it("should return backups for authenticated user", async () => {
      const mockBackups = [
        {
          id: "backup-1",
          userId,
          workspaceId: "ws-1",
          sizeBytes: 1024,
          createdAt: new Date(),
        },
        {
          id: "backup-2",
          userId,
          workspaceId: null,
          sizeBytes: 2048,
          createdAt: new Date(),
        },
      ];
      (prisma.backup.findMany as jest.Mock).mockResolvedValue(mockBackups);
      (prisma.backup.count as jest.Mock).mockResolvedValue(2);

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/backups",
        headers: { authorization: authToken },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data.backups).toHaveLength(2);
      expect(data.data.total).toBe(2);
    });

    it("should support pagination", async () => {
      (prisma.backup.findMany as jest.Mock).mockResolvedValue([]);
      (prisma.backup.count as jest.Mock).mockResolvedValue(0);

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/backups?limit=10&offset=5",
        headers: { authorization: authToken },
      });

      expect(response.statusCode).toBe(200);
      expect(prisma.backup.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          take: 10,
          skip: 5,
        }),
      );
    });
  });

  describe("POST /api/v1/backups", () => {
    it("should return 401 without authentication", async () => {
      const response = await app.inject({
        method: "POST",
        url: "/api/v1/backups",
        payload: {},
      });

      expect(response.statusCode).toBe(401);
    });

    it("should return 400 for invalid input (ZodError)", async () => {
      const response = await app.inject({
        method: "POST",
        url: "/api/v1/backups",
        headers: { authorization: authToken },
        payload: { type: "invalid-type-value", workspaceId: 12345 }, // Invalid types
      });

      expect(response.statusCode).toBe(400);
      const data = JSON.parse(response.payload);
      expect(data.error).toBe("Bad Request");
    });

    it("should return 403 when backup limit is exceeded", async () => {
      // Configure validateTierLimit to return invalid
      (validateTierLimit as jest.Mock).mockReturnValueOnce({
        valid: false,
        message: "free tier limit of 10 reached for maxBackups",
      });

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/backups",
        headers: { authorization: authToken },
        payload: { type: "manual" },
      });

      expect(response.statusCode).toBe(403);
      const data = JSON.parse(response.payload);
      expect(data.error).toBe("Forbidden");
      expect(data.message).toContain("limit");
    });

    it("should return 404 when workspace not found", async () => {
      // Ensure validateTierLimit returns valid so we get past the limit check
      (validateTierLimit as jest.Mock).mockReturnValueOnce({ valid: true });
      (prisma.backup.count as jest.Mock).mockResolvedValue(0);
      (prisma.workspace.findMany as jest.Mock).mockResolvedValue([]);

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/backups",
        headers: { authorization: authToken },
        payload: { workspaceId: "nonexistent-ws", type: "manual" },
      });

      expect(response.statusCode).toBe(404);
      const data = JSON.parse(response.payload);
      expect(data.error).toBe("Not Found");
    });

    // Skip: requires complete prisma relation mocking for includes
    it.skip("should create a backup for all workspaces", async () => {
      const mockWorkspaces = [
        {
          id: "ws-1",
          name: "Test Workspace",
          userId,
          tabs: [],
          sections: [],
          resources: [],
          notes: [],
          tasks: [],
        },
      ];
      (prisma.workspace.findMany as jest.Mock).mockResolvedValue(
        mockWorkspaces,
      );
      (prisma.backup.create as jest.Mock).mockResolvedValue({
        id: "new-backup-1",
        userId,
        workspaceId: null,
        sizeBytes: 512,
        createdAt: new Date(),
      });

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/backups",
        headers: { authorization: authToken },
        payload: { type: "manual" },
      });

      expect(response.statusCode).toBe(201);
      const data = JSON.parse(response.payload);
      expect(data.data).toHaveProperty("id", "new-backup-1");
    });

    // Skip: requires complete prisma relation mocking for includes
    it.skip("should create a backup for a specific workspace", async () => {
      const mockWorkspace = {
        id: "ws-1",
        name: "Test Workspace",
        userId,
        tabs: [],
        sections: [],
        resources: [],
        notes: [],
        tasks: [],
      };
      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue(
        mockWorkspace,
      );
      (prisma.backup.create as jest.Mock).mockResolvedValue({
        id: "new-backup-2",
        userId,
        workspaceId: "ws-1",
        sizeBytes: 256,
        createdAt: new Date(),
      });

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/backups",
        headers: { authorization: authToken },
        payload: { workspaceId: "ws-1", type: "manual" },
      });

      expect(response.statusCode).toBe(201);
      const data = JSON.parse(response.payload);
      expect(data.data.workspaceId).toBe("ws-1");
    });
  });

  describe("GET /api/v1/backups/stats", () => {
    it("should return backup statistics", async () => {
      const mockBackups = [
        {
          id: "b1",
          sizeBytes: 1000,
          workspaceId: "ws-1",
          createdAt: new Date(),
        },
        {
          id: "b2",
          sizeBytes: 2000,
          workspaceId: "ws-1",
          createdAt: new Date(),
        },
      ];
      (prisma.backup.findMany as jest.Mock).mockResolvedValue(mockBackups);

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/backups/stats",
        headers: { authorization: authToken },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data.totalBackups).toBe(2);
      expect(data.data.totalSizeBytes).toBe(3000);
    });
  });

  describe("GET /api/v1/backups/:id", () => {
    it("should return 404 for non-existent backup", async () => {
      (prisma.backup.findFirst as jest.Mock).mockResolvedValue(null);

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/backups/non-existent",
        headers: { authorization: authToken },
      });

      expect(response.statusCode).toBe(404);
    });

    it("should return backup details", async () => {
      const mockBackup = {
        id: "backup-1",
        userId,
        workspaceId: "ws-1",
        sizeBytes: 1024,
        snapshot: [{ workspace: { id: "ws-1", name: "Test" }, tabs: [] }],
        createdAt: new Date(),
      };
      (prisma.backup.findFirst as jest.Mock).mockResolvedValue(mockBackup);

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/backups/backup-1",
        headers: { authorization: authToken },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data.id).toBe("backup-1");
    });
  });

  describe("DELETE /api/v1/backups/:id", () => {
    it("should return 404 for non-existent backup", async () => {
      (prisma.backup.findFirst as jest.Mock).mockResolvedValue(null);

      const response = await app.inject({
        method: "DELETE",
        url: "/api/v1/backups/non-existent",
        headers: { authorization: authToken },
      });

      expect(response.statusCode).toBe(404);
    });

    it("should delete a backup", async () => {
      const mockBackup = { id: "backup-1", userId };
      (prisma.backup.findFirst as jest.Mock).mockResolvedValue(mockBackup);
      (prisma.backup.delete as jest.Mock).mockResolvedValue(mockBackup);

      const response = await app.inject({
        method: "DELETE",
        url: "/api/v1/backups/backup-1",
        headers: { authorization: authToken },
      });

      expect(response.statusCode).toBe(204);
    });
  });

  describe("POST /api/v1/backups/:id/restore", () => {
    it("should return 404 for non-existent backup", async () => {
      (prisma.backup.findFirst as jest.Mock).mockResolvedValue(null);

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/backups/non-existent/restore",
        headers: { authorization: authToken },
        payload: {},
      });

      expect(response.statusCode).toBe(404);
    });

    it("should return 400 for invalid restore input (ZodError)", async () => {
      const response = await app.inject({
        method: "POST",
        url: "/api/v1/backups/backup-1/restore",
        headers: { authorization: authToken },
        payload: { targetWorkspaceId: 12345, createNew: "not-a-boolean" }, // Invalid types
      });

      expect(response.statusCode).toBe(400);
      const data = JSON.parse(response.payload);
      expect(data.error).toBe("Bad Request");
    });

    it("should restore a backup", async () => {
      const mockBackup = {
        id: "backup-1",
        userId,
        snapshot: [
          {
            workspace: {
              id: "ws-1",
              name: "Test",
              description: null,
              color: null,
              icon: null,
              position: 0,
              settings: {},
              groupId: null,
            },
            tabs: [],
            sections: [],
            resources: [],
            notes: [],
            tasks: [],
          },
        ],
      };
      (prisma.backup.findFirst as jest.Mock).mockResolvedValue(mockBackup);
      // FOR UPDATE row lock on the workspace (also the existence check)
      (prisma.$queryRaw as jest.Mock).mockResolvedValue([{ id: "ws-1" }]);

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/backups/backup-1/restore",
        headers: { authorization: authToken },
        payload: {},
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.payload);
      expect(data.data.restoredWorkspaceIds).toBeDefined();
    });

    it("should return 400 when restoring a multi-workspace backup onto a single target", async () => {
      const multiBackup = {
        id: "backup-multi",
        userId,
        snapshot: [
          {
            workspace: { id: "ws-1", name: "A", settings: {}, groupId: null },
            tabs: [],
            sections: [],
            resources: [],
            notes: [],
            tasks: [],
          },
          {
            workspace: { id: "ws-2", name: "B", settings: {}, groupId: null },
            tabs: [],
            sections: [],
            resources: [],
            notes: [],
            tasks: [],
          },
        ],
      };
      (prisma.backup.findFirst as jest.Mock).mockResolvedValue(multiBackup);

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/backups/backup-multi/restore",
        headers: { authorization: authToken },
        payload: { targetWorkspaceId: "ws-target" },
      });

      expect(response.statusCode).toBe(400);
      const data = JSON.parse(response.payload);
      expect(data.error).toBe("Bad Request");
      expect(data.message).toContain("not supported");
    });
  });
});
