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
 * Unit tests for WorkOS AuthService
 */
import { AuthService } from "../../src/services/auth.service";
import { workos, WORKOS_CLIENT_ID } from "../../src/lib/workos";
import { prisma } from "../../src/lib/prisma";

// Mock workos
jest.mock("../../src/lib/workos", () => ({
  workos: {
    userManagement: {
      getAuthorizationUrl: jest.fn(),
      authenticateWithCode: jest.fn(),
    },
  },
  WORKOS_CLIENT_ID: "test-client-id",
}));

// Mock prisma
jest.mock("../../src/lib/prisma", () => ({
  prisma: {
    user: {
      upsert: jest.fn(),
    },
  },
}));

describe("AuthService - WorkOS", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("getAuthorizationUrl", () => {
    it("should return WorkOS authorization URL", () => {
      const mockUrl = "https://api.workos.com/user_management/authorize?...";
      (workos.userManagement.getAuthorizationUrl as jest.Mock).mockReturnValue(
        mockUrl,
      );

      const result = AuthService.getAuthorizationUrl();

      expect(result).toBe(mockUrl);
      expect(workos.userManagement.getAuthorizationUrl).toHaveBeenCalledWith({
        clientId: WORKOS_CLIENT_ID,
        provider: "authkit",
        redirectUri: expect.stringContaining("/api/v1/auth/callback"),
      });
    });
  });

  describe("authenticateAndSyncUser", () => {
    it("should authenticate and create new user", async () => {
      const mockWorkosUser = {
        email: "test@example.com",
        firstName: "Test",
        lastName: "User",
      };
      const mockDbUser = {
        id: "user-123",
        email: "test@example.com",
        name: "Test User",
        tier: "free",
        lastLoginAt: new Date(),
      };

      (
        workos.userManagement.authenticateWithCode as jest.Mock
      ).mockResolvedValue({
        user: mockWorkosUser,
      });
      (prisma.user.upsert as jest.Mock).mockResolvedValue(mockDbUser);

      const result = await AuthService.authenticateAndSyncUser("test-code");

      expect(result).toEqual(mockDbUser);
      expect(workos.userManagement.authenticateWithCode).toHaveBeenCalledWith({
        clientId: WORKOS_CLIENT_ID,
        code: "test-code",
      });
      expect(prisma.user.upsert).toHaveBeenCalledWith({
        where: { email: "test@example.com" },
        update: { lastLoginAt: expect.any(Date) },
        create: {
          email: "test@example.com",
          name: "Test User",
          lastLoginAt: expect.any(Date),
        },
      });
    });

    it("should use firstName only when lastName is missing", async () => {
      const mockWorkosUser = {
        email: "john@example.com",
        firstName: "John",
        lastName: null,
      };
      const mockDbUser = {
        id: "user-456",
        email: "john@example.com",
        name: "John",
        tier: "free",
        lastLoginAt: new Date(),
      };

      (
        workos.userManagement.authenticateWithCode as jest.Mock
      ).mockResolvedValue({
        user: mockWorkosUser,
      });
      (prisma.user.upsert as jest.Mock).mockResolvedValue(mockDbUser);

      const result = await AuthService.authenticateAndSyncUser("test-code");

      expect(result.name).toBe("John");
      expect(prisma.user.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          create: expect.objectContaining({ name: "John" }),
        }),
      );
    });

    it("should use email prefix when no name provided", async () => {
      const mockWorkosUser = {
        email: "alice@company.com",
        firstName: null,
        lastName: null,
      };
      const mockDbUser = {
        id: "user-789",
        email: "alice@company.com",
        name: "alice",
        tier: "free",
        lastLoginAt: new Date(),
      };

      (
        workos.userManagement.authenticateWithCode as jest.Mock
      ).mockResolvedValue({
        user: mockWorkosUser,
      });
      (prisma.user.upsert as jest.Mock).mockResolvedValue(mockDbUser);

      await AuthService.authenticateAndSyncUser("test-code");

      expect(prisma.user.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          create: expect.objectContaining({ name: "alice" }),
        }),
      );
    });

    it("should throw error when email is missing", async () => {
      const mockWorkosUser = {
        email: null,
        firstName: "Test",
        lastName: "User",
      };

      (
        workos.userManagement.authenticateWithCode as jest.Mock
      ).mockResolvedValue({
        user: mockWorkosUser,
      });

      await expect(
        AuthService.authenticateAndSyncUser("test-code"),
      ).rejects.toThrow("User email not provided by WorkOS");
    });
  });
});
