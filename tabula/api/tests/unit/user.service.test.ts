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
 * Unit tests for UserService
 */
import { UserService } from "../../src/services/user.service";
import { prisma } from "../../src/lib/prisma";

// Mock prisma
jest.mock("../../src/lib/prisma", () => ({
  prisma: {
    user: {
      findUnique: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
    },
  },
}));

describe("UserService", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("getUserById", () => {
    it("should return user by ID", async () => {
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

      (prisma.user.findUnique as jest.Mock).mockResolvedValue(mockUser);

      const result = await UserService.getUserById("user-123");

      expect(result).toEqual(mockUser);
      expect(prisma.user.findUnique).toHaveBeenCalledWith({
        where: { id: "user-123" },
        select: expect.objectContaining({
          id: true,
          email: true,
          name: true,
          passwordHash: false,
        }),
      });
    });

    it("should return null if user not found", async () => {
      (prisma.user.findUnique as jest.Mock).mockResolvedValue(null);

      const result = await UserService.getUserById("nonexistent");

      expect(result).toBeNull();
    });
  });

  describe("updateUser", () => {
    it("should update user profile", async () => {
      const mockUser = {
        id: "user-123",
        email: "test@example.com",
        name: "Updated Name",
        tier: "free",
        createdAt: new Date(),
        updatedAt: new Date(),
        lastLoginAt: new Date(),
        preferences: { theme: "dark" },
      };

      (prisma.user.update as jest.Mock).mockResolvedValue(mockUser);

      const result = await UserService.updateUser("user-123", {
        name: "Updated Name",
        preferences: { theme: "dark" },
      });

      expect(result).toEqual(mockUser);
      expect(prisma.user.update).toHaveBeenCalledWith({
        where: { id: "user-123" },
        data: {
          name: "Updated Name",
          preferences: { theme: "dark" },
          updatedAt: expect.any(Date),
        },
        select: expect.objectContaining({
          id: true,
          email: true,
          name: true,
          passwordHash: false,
        }),
      });
    });
  });

  describe("deleteUser", () => {
    it("should delete user account", async () => {
      (prisma.user.delete as jest.Mock).mockResolvedValue({});

      await UserService.deleteUser("user-123");

      expect(prisma.user.delete).toHaveBeenCalledWith({
        where: { id: "user-123" },
      });
    });
  });

  describe("getPasswordResetUrl", () => {
    it("should return password reset URL", () => {
      const result = UserService.getPasswordResetUrl("test@example.com");

      expect(result).toContain("/api/v1/auth/login");
      expect(result).toContain("action=reset_password");
    });
  });
});
