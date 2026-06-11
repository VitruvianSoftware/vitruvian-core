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
 * Integration tests for auth API endpoints
 */
import Fastify, { FastifyInstance } from "fastify";
import fastifyJwt from "@fastify/jwt";
import { authRoutes } from "../../src/routes/auth.routes";
import { AuthService } from "../../src/services/auth.service";

// Mock AuthService
jest.mock("../../src/services/auth.service", () => ({
  AuthService: {
    getAuthorizationUrl: jest.fn(),
    authenticateAndSyncUser: jest.fn(),
    createSession: jest.fn(),
    rotateRefreshToken: jest.fn(),
    revokeRefreshToken: jest.fn(),
  },
}));

describe("Auth API Endpoints", () => {
  let app: FastifyInstance;

  beforeAll(async () => {
    app = Fastify();
    await app.register(fastifyJwt, {
      secret: "test-jwt-secret-for-tests",
    });
    await app.register(authRoutes, { prefix: "/api/v1/auth" });
    await app.ready();
  });

  beforeEach(() => {
    jest.clearAllMocks();
    // Default: createSession returns a refresh token so the callback succeeds.
    (AuthService.createSession as jest.Mock).mockResolvedValue({
      refreshToken: "refresh-token-abc",
      expiresAt: new Date(Date.now() + 86400000),
    });
  });

  afterAll(async () => {
    await app.close();
  });

  describe("GET /api/v1/auth/login", () => {
    it("should redirect to WorkOS authorization URL", async () => {
      const mockUrl =
        "https://api.workos.com/user_management/authorize?client_id=test";
      (AuthService.getAuthorizationUrl as jest.Mock).mockReturnValue(mockUrl);

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/auth/login",
      });

      expect(response.statusCode).toBe(302);
      expect(response.headers.location).toBe(mockUrl);
    });
  });

  describe("GET /api/v1/auth/callback", () => {
    it("should return 400 when code is missing", async () => {
      const response = await app.inject({
        method: "GET",
        url: "/api/v1/auth/callback",
      });

      expect(response.statusCode).toBe(400);
      expect(JSON.parse(response.payload)).toHaveProperty(
        "error",
        "Missing code parameter",
      );
    });

    it("should return JWT token on successful authentication (JSON)", async () => {
      const mockUser = {
        id: "user-123",
        email: "test@example.com",
        name: "Test User",
        tier: "free",
      };
      (AuthService.authenticateAndSyncUser as jest.Mock).mockResolvedValue(
        mockUser,
      );

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/auth/callback?code=valid-code",
        headers: {
          accept: "application/json",
        },
      });

      expect(response.statusCode).toBe(200);
      const payload = JSON.parse(response.payload);
      expect(payload).toHaveProperty("token");
      expect(payload).toHaveProperty("refreshToken", "refresh-token-abc");
      expect(payload).toHaveProperty("user");
      expect(payload.user.email).toBe("test@example.com");
      expect(AuthService.createSession).toHaveBeenCalledWith(
        "user-123",
        expect.any(Object),
      );
    });

    it("should escape user-controlled values in the HTML callback (XSS guard)", async () => {
      // A WorkOS display name containing a </script> breakout attempt must be
      // neutralized so it cannot terminate the inline script element.
      const mockUser = {
        id: "user-xss",
        email: "evil@example.com",
        name: "</script><img src=x onerror=alert(1)>",
        tier: "free",
      };
      (AuthService.authenticateAndSyncUser as jest.Mock).mockResolvedValue(
        mockUser,
      );

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/auth/callback?code=valid-code",
        headers: { accept: "text/html" },
      });

      expect(response.statusCode).toBe(200);
      // The raw closing-script sequence must NOT appear; it is escaped to <.
      expect(response.payload).not.toContain("</script><img");
      expect(response.payload).toContain("\\u003c/script");
      // postMessage must target a concrete origin, never the wildcard '*'.
      // The targetOrigin is rendered as a JSON string argument to postMessage.
      expect(response.payload).toContain('"http://localhost:3000"');
      expect(response.payload).not.toMatch(/postMessage\([^)]*['"]\*['"]/);
    });

    it("should return HTML for browser requests", async () => {
      const mockUser = {
        id: "user-123",
        email: "test@example.com",
        name: "Test User",
        tier: "free",
      };
      (AuthService.authenticateAndSyncUser as jest.Mock).mockResolvedValue(
        mockUser,
      );

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/auth/callback?code=valid-code",
        headers: {
          accept: "text/html",
        },
      });

      expect(response.statusCode).toBe(200);
      expect(response.headers["content-type"]).toContain("text/html");
      expect(response.payload).toContain("Authentication Successful");
      expect(response.payload).toContain("TABULA_AUTH_SUCCESS");
    });

    it("should return 500 on authentication failure (JSON)", async () => {
      (AuthService.authenticateAndSyncUser as jest.Mock).mockRejectedValue(
        new Error("Invalid code"),
      );

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/auth/callback?code=invalid-code",
        headers: {
          accept: "application/json",
        },
      });

      expect(response.statusCode).toBe(500);
      const payload = JSON.parse(response.payload);
      expect(payload).toHaveProperty("error", "Authentication failed");
      expect(payload.message).toBe("Invalid code");
    });

    it("should return HTML error for browser on authentication failure", async () => {
      (AuthService.authenticateAndSyncUser as jest.Mock).mockRejectedValue(
        new Error("Authentication error"),
      );

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/auth/callback?code=invalid-code",
        headers: {
          accept: "text/html",
        },
      });

      expect(response.statusCode).toBe(200); // HTML errors return 200 with error content
      expect(response.headers["content-type"]).toContain("text/html");
      expect(response.payload).toContain("Authentication Failed");
    });

    it("should HTML-escape the error message in the browser error page", async () => {
      (AuthService.authenticateAndSyncUser as jest.Mock).mockRejectedValue(
        new Error("<script>alert(1)</script>"),
      );

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/auth/callback?code=invalid-code",
        headers: { accept: "text/html" },
      });

      expect(response.statusCode).toBe(200);
      expect(response.payload).not.toContain("<script>alert(1)</script>");
      expect(response.payload).toContain("&lt;script&gt;");
    });
  });

  describe("POST /api/v1/auth/refresh", () => {
    it("should return 400 when refreshToken is missing", async () => {
      const response = await app.inject({
        method: "POST",
        url: "/api/v1/auth/refresh",
        payload: {},
      });

      expect(response.statusCode).toBe(400);
    });

    it("should return 401 for an invalid/expired refresh token", async () => {
      (AuthService.rotateRefreshToken as jest.Mock).mockResolvedValue(null);

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/auth/refresh",
        payload: { refreshToken: "bad-token" },
      });

      expect(response.statusCode).toBe(401);
      expect(JSON.parse(response.payload)).toHaveProperty(
        "error",
        "Unauthorized",
      );
    });

    it("should issue a fresh access token and rotated refresh token", async () => {
      (AuthService.rotateRefreshToken as jest.Mock).mockResolvedValue({
        user: { id: "user-123", email: "test@example.com", tier: "pro" },
        refreshToken: "rotated-token-xyz",
        expiresAt: new Date(Date.now() + 86400000),
      });

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/auth/refresh",
        payload: { refreshToken: "valid-token" },
      });

      expect(response.statusCode).toBe(200);
      const payload = JSON.parse(response.payload);
      expect(payload).toHaveProperty("token");
      expect(payload).toHaveProperty("refreshToken", "rotated-token-xyz");
      // The new access token should carry the CURRENT tier from the DB (pro),
      // not a stale claim.
      const decoded = app.jwt.decode<{ tier: string }>(payload.token);
      expect(decoded?.tier).toBe("pro");
    });
  });

  describe("POST /api/v1/auth/logout", () => {
    it("should revoke the session and return success", async () => {
      (AuthService.revokeRefreshToken as jest.Mock).mockResolvedValue(true);

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/auth/logout",
        payload: { refreshToken: "valid-token" },
      });

      expect(response.statusCode).toBe(200);
      expect(JSON.parse(response.payload)).toHaveProperty("success", true);
      expect(AuthService.revokeRefreshToken).toHaveBeenCalledWith(
        "valid-token",
      );
    });

    it("should succeed even when no refreshToken is provided (idempotent)", async () => {
      const response = await app.inject({
        method: "POST",
        url: "/api/v1/auth/logout",
        payload: {},
      });

      expect(response.statusCode).toBe(200);
      expect(AuthService.revokeRefreshToken).not.toHaveBeenCalled();
    });
  });
});
