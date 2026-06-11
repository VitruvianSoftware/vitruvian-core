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
 * Integration tests for user API endpoints
 */
import Fastify, { FastifyInstance } from "fastify";
import fastifyJwt from "@fastify/jwt";
import { userRoutes } from "../../src/routes/user.routes";
import { UserService } from "../../src/services/user.service";

// Mock UserService
jest.mock("../../src/services/user.service", () => ({
  UserService: {
    getUserById: jest.fn(),
    updateUser: jest.fn(),
    deleteUser: jest.fn(),
    getPasswordResetUrl: jest.fn(),
  },
}));

describe("User API Endpoints", () => {
  let app: FastifyInstance;
  let token: string;

  beforeAll(async () => {
    app = Fastify();
    await app.register(fastifyJwt, {
      secret: "test-jwt-secret-for-tests",
    });
    await app.register(userRoutes, { prefix: "/api/v1/users" });
    await app.ready();

    // Generate test token
    token = app.jwt.sign({
      id: "user-123",
      email: "test@example.com",
      tier: "free",
    });
  });

  beforeEach(() => {
    jest.clearAllMocks();
  });

  afterAll(async () => {
    await app.close();
  });

  describe("GET /api/v1/users/me", () => {
    it("should return current user profile", async () => {
      const mockUser = {
        id: "user-123",
        email: "test@example.com",
        name: "Test User",
        tier: "free",
        createdAt: new Date(),
        updatedAt: new Date(),
        lastLoginAt: new Date(),
        preferences: {},
      };
      (UserService.getUserById as jest.Mock).mockResolvedValue(mockUser);

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/users/me",
        headers: {
          authorization: `Bearer ${token}`,
        },
      });

      expect(response.statusCode).toBe(200);
      const payload = JSON.parse(response.payload);
      expect(payload.data).toHaveProperty("email", "test@example.com");
    });

    it("should return 401 without token", async () => {
      const response = await app.inject({
        method: "GET",
        url: "/api/v1/users/me",
      });

      expect(response.statusCode).toBe(401);
    });

    it("should return 404 if user not found", async () => {
      (UserService.getUserById as jest.Mock).mockResolvedValue(null);

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/users/me",
        headers: {
          authorization: `Bearer ${token}`,
        },
      });

      expect(response.statusCode).toBe(404);
    });
  });

  describe("PATCH /api/v1/users/me", () => {
    it("should update user profile", async () => {
      const mockUpdatedUser = {
        id: "user-123",
        email: "test@example.com",
        name: "Updated Name",
        tier: "free",
        createdAt: new Date(),
        updatedAt: new Date(),
        lastLoginAt: new Date(),
        preferences: { theme: "dark" },
      };
      (UserService.updateUser as jest.Mock).mockResolvedValue(mockUpdatedUser);

      const response = await app.inject({
        method: "PATCH",
        url: "/api/v1/users/me",
        headers: {
          authorization: `Bearer ${token}`,
        },
        payload: {
          name: "Updated Name",
          preferences: { theme: "dark" },
        },
      });

      expect(response.statusCode).toBe(200);
      const payload = JSON.parse(response.payload);
      expect(payload.data.name).toBe("Updated Name");
    });

    it("should return 400 for invalid input", async () => {
      const response = await app.inject({
        method: "PATCH",
        url: "/api/v1/users/me",
        headers: {
          authorization: `Bearer ${token}`,
        },
        payload: {
          name: "", // Invalid: empty name
        },
      });

      expect(response.statusCode).toBe(400);
    });

    it("should return 401 without token", async () => {
      const response = await app.inject({
        method: "PATCH",
        url: "/api/v1/users/me",
        payload: {
          name: "Updated Name",
        },
      });

      expect(response.statusCode).toBe(401);
    });
  });

  describe("DELETE /api/v1/users/me", () => {
    it("should delete user account", async () => {
      (UserService.deleteUser as jest.Mock).mockResolvedValue(undefined);

      const response = await app.inject({
        method: "DELETE",
        url: "/api/v1/users/me",
        headers: {
          authorization: `Bearer ${token}`,
        },
      });

      expect(response.statusCode).toBe(204);
      expect(UserService.deleteUser).toHaveBeenCalledWith("user-123");
    });

    it("should return 401 without token", async () => {
      const response = await app.inject({
        method: "DELETE",
        url: "/api/v1/users/me",
      });

      expect(response.statusCode).toBe(401);
    });
  });

  describe("POST /api/v1/users/password-reset", () => {
    it("should return password reset URL", async () => {
      const mockResetUrl =
        "http://localhost:8080/api/v1/auth/login?action=reset_password";
      (UserService.getPasswordResetUrl as jest.Mock).mockReturnValue(
        mockResetUrl,
      );

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/users/password-reset",
        payload: {
          email: "test@example.com",
        },
      });

      expect(response.statusCode).toBe(200);
      const payload = JSON.parse(response.payload);
      expect(payload.data.resetUrl).toBe(mockResetUrl);
    });

    it("should return 400 for invalid email", async () => {
      const response = await app.inject({
        method: "POST",
        url: "/api/v1/users/password-reset",
        payload: {
          email: "invalid-email",
        },
      });

      expect(response.statusCode).toBe(400);
    });

    it("should return 500 when service throws error", async () => {
      (UserService.getPasswordResetUrl as jest.Mock).mockImplementation(() => {
        throw new Error("Password reset failed");
      });

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/users/password-reset",
        payload: {
          email: "test@example.com",
        },
      });

      expect(response.statusCode).toBe(500);
      const payload = JSON.parse(response.payload);
      // Internal error messages must NOT leak to clients; a generic message is
      // returned and the real error is logged server-side.
      expect(payload.message).toBe("Failed to generate password reset URL");
    });

    it("should handle non-Error thrown objects", async () => {
      (UserService.getPasswordResetUrl as jest.Mock).mockImplementation(() => {
        // eslint-disable-next-line no-throw-literal
        throw "string error";
      });

      const response = await app.inject({
        method: "POST",
        url: "/api/v1/users/password-reset",
        payload: {
          email: "test@example.com",
        },
      });

      expect(response.statusCode).toBe(500);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Failed to generate password reset URL");
    });
  });

  describe("error handling", () => {
    it("should handle getUserById service Error without leaking the message", async () => {
      (UserService.getUserById as jest.Mock).mockRejectedValue(
        new Error("Database error"),
      );

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/users/me",
        headers: { authorization: `Bearer ${token}` },
      });

      expect(response.statusCode).toBe(500);
      const payload = JSON.parse(response.payload);
      // Real internal error ('Database error') must not be echoed to the client.
      expect(payload.message).toBe("Failed to get user profile");
      expect(payload.message).not.toContain("Database error");
    });

    it("should handle getUserById non-Error thrown", async () => {
      (UserService.getUserById as jest.Mock).mockRejectedValue("string error");

      const response = await app.inject({
        method: "GET",
        url: "/api/v1/users/me",
        headers: { authorization: `Bearer ${token}` },
      });

      expect(response.statusCode).toBe(500);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Failed to get user profile");
    });

    it("should handle updateUser service Error without leaking the message", async () => {
      (UserService.updateUser as jest.Mock).mockRejectedValue(
        new Error("Update failed"),
      );

      const response = await app.inject({
        method: "PATCH",
        url: "/api/v1/users/me",
        headers: { authorization: `Bearer ${token}` },
        payload: { name: "Valid Name" },
      });

      expect(response.statusCode).toBe(500);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Failed to update user profile");
      expect(payload.message).not.toContain("Update failed");
    });

    it("should handle updateUser non-Error thrown", async () => {
      (UserService.updateUser as jest.Mock).mockRejectedValue("string error");

      const response = await app.inject({
        method: "PATCH",
        url: "/api/v1/users/me",
        headers: { authorization: `Bearer ${token}` },
        payload: { name: "Valid Name" },
      });

      expect(response.statusCode).toBe(500);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Failed to update user profile");
    });

    it("should handle deleteUser service Error without leaking the message", async () => {
      (UserService.deleteUser as jest.Mock).mockRejectedValue(
        new Error("Delete failed"),
      );

      const response = await app.inject({
        method: "DELETE",
        url: "/api/v1/users/me",
        headers: { authorization: `Bearer ${token}` },
      });

      expect(response.statusCode).toBe(500);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Failed to delete user account");
      expect(payload.message).not.toContain("Delete failed");
    });

    it("should handle deleteUser non-Error thrown", async () => {
      (UserService.deleteUser as jest.Mock).mockRejectedValue("string error");

      const response = await app.inject({
        method: "DELETE",
        url: "/api/v1/users/me",
        headers: { authorization: `Bearer ${token}` },
      });

      expect(response.statusCode).toBe(500);
      const payload = JSON.parse(response.payload);
      expect(payload.message).toBe("Failed to delete user account");
    });
  });
});
