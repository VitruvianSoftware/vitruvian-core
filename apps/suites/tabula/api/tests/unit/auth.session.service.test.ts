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
 * Unit tests for AuthService session/refresh-token methods.
 */
import { AuthService } from "../../src/services/auth.service";
import { prisma } from "../../src/lib/prisma";
import { hashRefreshToken } from "../../src/lib/auth";

jest.mock("../../src/lib/prisma", () => ({
  prisma: {
    session: {
      create: jest.fn(),
      findFirst: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
      deleteMany: jest.fn(),
    },
  },
}));

// WorkOS client requires env at import time; the AuthService module imports it.
jest.mock("../../src/lib/workos", () => ({
  workos: { userManagement: {} },
  WORKOS_CLIENT_ID: "test-client",
}));

describe("AuthService sessions", () => {
  const userId = "user-123";

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("createSession", () => {
    it("stores only the hash of the refresh token and returns the raw token", async () => {
      (prisma.session.create as jest.Mock).mockResolvedValue({ id: "sess-1" });

      const { refreshToken } = await AuthService.createSession(userId, {
        userAgent: "jest",
      });

      expect(refreshToken).toBeTruthy();
      const createArg = (prisma.session.create as jest.Mock).mock.calls[0][0];
      // The raw token must NOT be persisted; only its hash.
      expect(createArg.data.refreshTokenHash).toBe(
        hashRefreshToken(refreshToken),
      );
      expect(createArg.data.refreshTokenHash).not.toBe(refreshToken);
      expect(createArg.data.userId).toBe(userId);
    });
  });

  describe("rotateRefreshToken", () => {
    it("returns null for an unknown token", async () => {
      (prisma.session.findFirst as jest.Mock).mockResolvedValue(null);
      const result = await AuthService.rotateRefreshToken("nope");
      expect(result).toBeNull();
    });

    it("rejects and deletes an expired session", async () => {
      (prisma.session.findFirst as jest.Mock).mockResolvedValue({
        id: "sess-1",
        expiresAt: new Date(Date.now() - 1000),
        user: { id: userId, email: "e@x.com", tier: "free" },
      });
      (prisma.session.delete as jest.Mock).mockResolvedValue({});

      const result = await AuthService.rotateRefreshToken("expired");

      expect(result).toBeNull();
      expect(prisma.session.delete).toHaveBeenCalledWith({
        where: { id: "sess-1" },
      });
    });

    it("rotates the token and re-reads the current tier from the DB", async () => {
      (prisma.session.findFirst as jest.Mock).mockResolvedValue({
        id: "sess-1",
        expiresAt: new Date(Date.now() + 100000),
        user: { id: userId, email: "e@x.com", tier: "pro" },
      });
      (prisma.session.update as jest.Mock).mockResolvedValue({});

      const result = await AuthService.rotateRefreshToken("valid");

      expect(result).not.toBeNull();
      expect(result!.user.tier).toBe("pro");
      // A NEW token is issued (rotation) and its hash persisted.
      const updateArg = (prisma.session.update as jest.Mock).mock.calls[0][0];
      expect(updateArg.data.refreshTokenHash).toBe(
        hashRefreshToken(result!.refreshToken),
      );
      expect(result!.refreshToken).not.toBe("valid");
    });
  });

  describe("revokeRefreshToken", () => {
    it("deletes the matching session and reports success", async () => {
      (prisma.session.deleteMany as jest.Mock).mockResolvedValue({ count: 1 });
      const ok = await AuthService.revokeRefreshToken("valid");
      expect(ok).toBe(true);
      const arg = (prisma.session.deleteMany as jest.Mock).mock.calls[0][0];
      expect(arg.where.refreshTokenHash).toBe(hashRefreshToken("valid"));
    });

    it("returns false when no session matches", async () => {
      (prisma.session.deleteMany as jest.Mock).mockResolvedValue({ count: 0 });
      expect(await AuthService.revokeRefreshToken("unknown")).toBe(false);
    });

    it("returns false for an empty token without touching the DB", async () => {
      expect(await AuthService.revokeRefreshToken("")).toBe(false);
      expect(prisma.session.deleteMany).not.toHaveBeenCalled();
    });
  });
});
