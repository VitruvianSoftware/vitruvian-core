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
 * Integration tests for sync API endpoints
 */
import Fastify, { FastifyInstance } from "fastify";
import fastifyJwt from "@fastify/jwt";
import { syncRoutes } from "../../src/routes/sync.routes";
import { SyncService } from "../../src/services/sync.service";
import {
  authenticateUser,
  authenticateUserAllowQueryToken,
} from "../../src/middleware/auth";

// Mock SyncService
jest.mock("../../src/services/sync.service", () => ({
  SyncService: {
    getSyncStatus: jest.fn(),
    pushChanges: jest.fn(),
    pullChanges: jest.fn(),
    subscribeToUpdates: jest.fn(),
  },
}));

// Mock the auth middleware (both variants used by the sync routes)
jest.mock("../../src/middleware/auth", () => ({
  authenticateUser: jest.fn(async (request: { user: unknown }) => {
    request.user = { id: "user-123", tier: "pro", email: "test@example.com" };
  }),
  authenticateUserAllowQueryToken: jest.fn(
    async (request: { user: unknown }) => {
      request.user = { id: "user-123", tier: "pro", email: "test@example.com" };
    },
  ),
}));

describe("Sync API Endpoints", () => {
  let app: FastifyInstance;

  beforeAll(async () => {
    app = Fastify();
    await app.register(fastifyJwt, {
      secret: "test-jwt-secret-for-tests",
    });

    // Decorate request with user (the mock auth middleware will set this)
    if (!app.hasRequestDecorator("user")) {
      app.decorateRequest("user", null);
    }

    await app.register(syncRoutes, { prefix: "/api/v1/sync" });
    await app.ready();
  });

  beforeEach(() => {
    jest.clearAllMocks();
  });

  afterAll(async () => {
    await app.close();
  });

  describe("GET /api/v1/sync/state", () => {
    it("should return sync status", async () => {
      const mockStatus = {
        lastSync: new Date().toISOString(),
        pendingChanges: 0,
      };
      (SyncService.getSyncStatus as jest.Mock).mockResolvedValue(mockStatus);

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/sync/state",
      });

      expect(response.statusCode).toBe(200);
      const payload = JSON.parse(response.payload);
      expect(payload).toHaveProperty("data");
      expect(payload.data).toEqual(mockStatus);
      expect(SyncService.getSyncStatus).toHaveBeenCalledWith("user-123");
    });
  });

  describe("POST /api/v1/sync/push", () => {
    it("should push changes successfully", async () => {
      const mockResult = { success: true, syncedAt: new Date().toISOString() };
      (SyncService.pushChanges as jest.Mock).mockResolvedValue(mockResult);

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/sync/push",
        payload: {
          deviceId: "test-device-123",
          clientTimestamp: new Date().toISOString(),
          changes: [],
        },
      });

      expect(response.statusCode).toBe(200);
      const payload = JSON.parse(response.payload);
      expect(payload).toHaveProperty("data");
      expect(SyncService.pushChanges).toHaveBeenCalled();
    });

    it("should return 400 for invalid input", async () => {
      const response = await app.inject({
        method: "POST",
        url: "/api/v1/sync/push",
        payload: { invalid: "data" },
      });

      expect(response.statusCode).toBe(400);
      const payload = JSON.parse(response.payload);
      expect(payload).toHaveProperty("error", "Bad Request");
    });

    it("should throw non-Zod errors", async () => {
      (SyncService.pushChanges as jest.Mock).mockRejectedValue(
        new Error("Database error"),
      );

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/sync/push",
        payload: {
          deviceId: "test-device-123",
          clientTimestamp: new Date().toISOString(),
          changes: [],
        },
      });

      expect(response.statusCode).toBe(500);
    });
  });

  describe("GET /api/v1/sync/pull", () => {
    it("should pull changes successfully", async () => {
      const mockResult = {
        workspaces: [{ id: "ws-1", name: "Test" }],
        spaceGroups: [],
      };
      (SyncService.pullChanges as jest.Mock).mockResolvedValue(mockResult);

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/sync/pull?deviceId=test-device-123",
      });

      expect(response.statusCode).toBe(200);
      const payload = JSON.parse(response.payload);
      expect(payload).toHaveProperty("data");
      expect(SyncService.pullChanges).toHaveBeenCalled();
    });

    it("should throw non-Zod errors for pull", async () => {
      (SyncService.pullChanges as jest.Mock).mockRejectedValue(
        new Error("Network error"),
      );

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/sync/pull?deviceId=test-device-123",
      });

      expect(response.statusCode).toBe(500);
    });
  });

  describe("GET /api/v1/sync/stream", () => {
    it("should set up SSE stream", async () => {
      // Mock an async iterator that yields one update then ends
      const mockIterator = {
        *[Symbol.asyncIterator]() {
          yield { type: "workspace_updated", data: { id: "ws-1" } };
        },
      };
      (SyncService.subscribeToUpdates as jest.Mock).mockReturnValue(
        mockIterator,
      );

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/sync/stream?deviceId=test-device",
      });

      expect(response.statusCode).toBe(200);
      expect(response.headers["content-type"]).toBe("text/event-stream");
      expect(response.payload).toContain("event: connected");
    });

    it("should generate deviceId if not provided", async () => {
      // Use a simple empty array as async iterable
      const mockIterator = {
        // eslint-disable-next-line require-yield
        *[Symbol.asyncIterator]() {
          // Empty generator
        },
      };
      (SyncService.subscribeToUpdates as jest.Mock).mockReturnValue(
        mockIterator,
      );

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/sync/stream",
      });

      expect(response.statusCode).toBe(200);
      expect(SyncService.subscribeToUpdates).toHaveBeenCalled();
    });

    it("should handle stream errors gracefully", async () => {
      // Create a mock async iterator that throws
      // eslint-disable-next-line require-yield
      async function* errorIterator() {
        throw new Error("Stream error");
      }
      (SyncService.subscribeToUpdates as jest.Mock).mockReturnValue(
        errorIterator(),
      );

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/sync/stream",
      });

      expect(response.statusCode).toBe(200);
      expect(response.headers["content-type"]).toBe("text/event-stream");
    });

    it("should use query-token-capable auth for /stream only", async () => {
      const mockIterator = {
        // eslint-disable-next-line require-yield
        *[Symbol.asyncIterator]() {
          // Empty generator
        },
      };
      (SyncService.subscribeToUpdates as jest.Mock).mockReturnValue(
        mockIterator,
      );
      (SyncService.pullChanges as jest.Mock).mockResolvedValue({ changes: [] });

      await app.inject({ method: "GET", url: "/api/v1/sync/stream" });
      expect(authenticateUserAllowQueryToken).toHaveBeenCalledTimes(1);
      expect(authenticateUser).not.toHaveBeenCalled();

      // All other sync routes remain header-only
      await app.inject({
        method: "GET",
        url: "/api/v1/sync/pull?deviceId=test-device",
      });
      expect(authenticateUser).toHaveBeenCalledTimes(1);
      expect(authenticateUserAllowQueryToken).toHaveBeenCalledTimes(1);
    });

    it("should pass the AbortSignal for disconnect handling to the subscription", async () => {
      const mockIterator = {
        // eslint-disable-next-line require-yield
        *[Symbol.asyncIterator]() {
          // Empty generator
        },
      };
      (SyncService.subscribeToUpdates as jest.Mock).mockReturnValue(
        mockIterator,
      );

      await app.inject({
        method: "GET",
        url: "/api/v1/sync/stream?deviceId=test-device",
      });

      expect(SyncService.subscribeToUpdates).toHaveBeenCalledWith(
        "user-123",
        "test-device",
        expect.objectContaining({ signal: expect.any(AbortSignal) }),
      );
    });
  });

  describe("GET /api/v1/sync/stream auth via ?token=", () => {
    // Uses the REAL middleware (jest.requireActual) with a real JWT plugin to
    // verify that the stream route's auth accepts a query-string token.
    let realApp: FastifyInstance;
    let validToken: string;

    beforeAll(async () => {
      const realAuth = jest.requireActual("../../src/middleware/auth");

      realApp = Fastify();
      await realApp.register(fastifyJwt, {
        secret: "test-jwt-secret-for-tests",
      });
      realApp.get(
        "/query-auth",
        { preHandler: realAuth.authenticateUserAllowQueryToken },
        async (request) => ({ user: request.user }),
      );
      realApp.get(
        "/header-auth",
        { preHandler: realAuth.authenticateUser },
        async (request) => ({
          user: request.user,
        }),
      );
      await realApp.ready();

      validToken = realApp.jwt.sign({
        id: "user-456",
        email: "t@example.com",
        tier: "free",
      });
    });

    afterAll(async () => {
      await realApp.close();
    });

    it("should authenticate with a valid ?token= when no Authorization header", async () => {
      const response = await realApp.inject({
        method: "GET",
        url: `/query-auth?token=${validToken}`,
      });

      expect(response.statusCode).toBe(200);
      expect(JSON.parse(response.payload).user.id).toBe("user-456");
    });

    it("should still accept the Authorization header", async () => {
      const response = await realApp.inject({
        method: "GET",
        url: "/query-auth",
        headers: { authorization: `Bearer ${validToken}` },
      });

      expect(response.statusCode).toBe(200);
    });

    it("should reject an invalid query token", async () => {
      const response = await realApp.inject({
        method: "GET",
        url: "/query-auth?token=not-a-jwt",
      });

      expect(response.statusCode).toBe(401);
    });

    it("should reject when neither header nor token is provided", async () => {
      const response = await realApp.inject({
        method: "GET",
        url: "/query-auth",
      });

      expect(response.statusCode).toBe(401);
    });

    it("should NOT allow query tokens on header-only routes", async () => {
      const response = await realApp.inject({
        method: "GET",
        url: `/header-auth?token=${validToken}`,
      });

      expect(response.statusCode).toBe(401);
    });
  });
});
