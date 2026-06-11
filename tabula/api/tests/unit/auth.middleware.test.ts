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
 * Unit tests for auth middleware
 */
import { FastifyRequest, FastifyReply } from "fastify";
import {
  authenticateUser,
  authenticateUserAllowQueryToken,
} from "../../src/middleware/auth";

describe("Auth Middleware", () => {
  let mockRequest: Partial<FastifyRequest>;
  let mockReply: Partial<FastifyReply>;

  beforeEach(() => {
    mockRequest = {
      headers: {},
      jwtVerify: jest.fn(),
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      log: { debug: jest.fn(), warn: jest.fn() } as any,
    };
    mockReply = {
      code: jest.fn().mockReturnThis(),
      send: jest.fn(),
    };
  });

  describe("authenticateUser", () => {
    it("should set user from valid JWT", async () => {
      const mockUser = {
        id: "user-123",
        email: "test@example.com",
        tier: "free",
      };
      (mockRequest.jwtVerify as jest.Mock).mockResolvedValue(undefined);
      mockRequest.headers = { authorization: "Bearer valid-jwt-token" };
      // Simulate jwtVerify setting user on request
      Object.defineProperty(mockRequest, "user", {
        value: mockUser,
        writable: true,
        configurable: true,
      });

      await authenticateUser(
        mockRequest as FastifyRequest,
        mockReply as FastifyReply,
      );

      expect(mockRequest.jwtVerify).toHaveBeenCalled();
      expect(mockReply.code).not.toHaveBeenCalled();
      expect(mockReply.send).not.toHaveBeenCalled();
    });

    it("should return 401 when authorization header is missing", async () => {
      mockRequest.headers = {};
      // jwtVerify throws when no auth header
      (mockRequest.jwtVerify as jest.Mock).mockRejectedValue(
        new Error("No Authorization was found"),
      );

      await authenticateUser(
        mockRequest as FastifyRequest,
        mockReply as FastifyReply,
      );

      expect(mockReply.code).toHaveBeenCalledWith(401);
      expect(mockReply.send).toHaveBeenCalledWith({
        error: "Unauthorized",
        message: "Authentication failed",
      });
    });

    it("should return 401 when Bearer prefix is missing", async () => {
      mockRequest.headers = { authorization: "InvalidToken" };
      (mockRequest.jwtVerify as jest.Mock).mockRejectedValue(
        new Error("Invalid authorization header"),
      );

      await authenticateUser(
        mockRequest as FastifyRequest,
        mockReply as FastifyReply,
      );

      expect(mockReply.code).toHaveBeenCalledWith(401);
      expect(mockReply.send).toHaveBeenCalledWith({
        error: "Unauthorized",
        message: "Authentication failed",
      });
    });

    it("should return 401 when JWT verification fails", async () => {
      mockRequest.headers = { authorization: "Bearer invalid-jwt" };
      (mockRequest.jwtVerify as jest.Mock).mockRejectedValue(
        new Error("Invalid token"),
      );

      await authenticateUser(
        mockRequest as FastifyRequest,
        mockReply as FastifyReply,
      );

      expect(mockReply.code).toHaveBeenCalledWith(401);
      expect(mockReply.send).toHaveBeenCalledWith({
        error: "Unauthorized",
        message: "Authentication failed",
      });
    });

    it("should return 401 when token is empty", async () => {
      mockRequest.headers = { authorization: "Bearer " };
      (mockRequest.jwtVerify as jest.Mock).mockRejectedValue(
        new Error("Not a valid token"),
      );

      await authenticateUser(
        mockRequest as FastifyRequest,
        mockReply as FastifyReply,
      );

      expect(mockReply.code).toHaveBeenCalledWith(401);
      expect(mockReply.send).toHaveBeenCalledWith({
        error: "Unauthorized",
        message: "Authentication failed",
      });
    });
  });

  describe("authenticateUserAllowQueryToken", () => {
    it("should promote a query token to the Authorization header when header absent", async () => {
      mockRequest.headers = {};
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (mockRequest as any).query = { token: "query-jwt-token" };
      (mockRequest.jwtVerify as jest.Mock).mockResolvedValue(undefined);

      await authenticateUserAllowQueryToken(
        mockRequest as FastifyRequest,
        mockReply as FastifyReply,
      );

      expect(mockRequest.headers?.authorization).toBe("Bearer query-jwt-token");
      expect(mockRequest.jwtVerify).toHaveBeenCalled();
      expect(mockReply.code).not.toHaveBeenCalled();
    });

    it("should prefer the Authorization header over a query token", async () => {
      mockRequest.headers = { authorization: "Bearer header-token" };
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (mockRequest as any).query = { token: "query-token" };
      (mockRequest.jwtVerify as jest.Mock).mockResolvedValue(undefined);

      await authenticateUserAllowQueryToken(
        mockRequest as FastifyRequest,
        mockReply as FastifyReply,
      );

      expect(mockRequest.headers?.authorization).toBe("Bearer header-token");
    });

    it("should return 401 when neither header nor query token is present", async () => {
      mockRequest.headers = {};
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (mockRequest as any).query = {};
      (mockRequest.jwtVerify as jest.Mock).mockRejectedValue(
        new Error("No Authorization was found"),
      );

      await authenticateUserAllowQueryToken(
        mockRequest as FastifyRequest,
        mockReply as FastifyReply,
      );

      expect(mockReply.code).toHaveBeenCalledWith(401);
    });

    it("should return 401 when the query token is invalid", async () => {
      mockRequest.headers = {};
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (mockRequest as any).query = { token: "bad-token" };
      (mockRequest.jwtVerify as jest.Mock).mockRejectedValue(
        new Error("Invalid token"),
      );

      await authenticateUserAllowQueryToken(
        mockRequest as FastifyRequest,
        mockReply as FastifyReply,
      );

      expect(mockReply.code).toHaveBeenCalledWith(401);
    });
  });

  describe("optionalAuth", () => {
    // Import the function
    let optionalAuth: typeof import("../../src/middleware/auth").optionalAuth;

    beforeAll(async () => {
      const module = await import("../../src/middleware/auth");
      optionalAuth = module.optionalAuth;
    });

    it("should verify user if authorization header is present", async () => {
      mockRequest.headers = { authorization: "Bearer valid-token" };
      (mockRequest.jwtVerify as jest.Mock).mockResolvedValue(undefined);

      await optionalAuth(mockRequest as FastifyRequest);

      expect(mockRequest.jwtVerify).toHaveBeenCalled();
    });

    it("should not verify if authorization header is missing", async () => {
      mockRequest.headers = {};

      await optionalAuth(mockRequest as FastifyRequest);

      expect(mockRequest.jwtVerify).not.toHaveBeenCalled();
    });

    it("should silently catch verification errors", async () => {
      mockRequest.headers = { authorization: "Bearer invalid-token" };
      (mockRequest.jwtVerify as jest.Mock).mockRejectedValue(
        new Error("Invalid token"),
      );

      // Should not throw
      await expect(
        optionalAuth(mockRequest as FastifyRequest),
      ).resolves.toBeUndefined();
      expect(mockRequest.log?.debug).toHaveBeenCalled();
    });
  });
});
