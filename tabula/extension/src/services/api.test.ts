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

import { ApiService } from "./api";
import { AuthService } from "./auth";
import { Workspace } from "../types";

// Mock AuthService
jest.mock("./auth", () => ({
  AuthService: {
    getToken: jest.fn(),
    refreshAccessToken: jest.fn(),
    getUser: jest.fn(),
    setCachedUser: jest.fn(),
  },
}));
// Mock device id (best-effort header)
jest.mock("./deviceId", () => ({
  getDeviceId: jest.fn().mockResolvedValue("device_test"),
}));

// Mock global fetch
globalThis.fetch = jest.fn();

describe("ApiService", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (AuthService.refreshAccessToken as jest.Mock).mockResolvedValue(null);
  });

  describe("request", () => {
    it("should add Authorization header when token exists", async () => {
      (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        json: async () => ({ data: [] }),
      });

      await ApiService.getWorkspaces();

      await ApiService.getWorkspaces();

      const callArgs = (globalThis.fetch as jest.Mock).mock.calls[0];
      const headers = callArgs[1].headers as Headers;
      expect(headers.get("Authorization")).toBe("Bearer test-token");
      expect(headers.get("Content-Type")).toBe("application/json");
      expect(callArgs[0]).toContain("/workspaces");
    });

    it("should not add Authorization header when token is missing", async () => {
      (AuthService.getToken as jest.Mock).mockResolvedValue(null);
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        json: async () => ({ data: [] }),
      });

      await ApiService.getWorkspaces();

      expect(globalThis.fetch).toHaveBeenCalledWith(
        expect.stringContaining("/workspaces"),
        expect.not.objectContaining({
          headers: expect.objectContaining({
            Authorization: expect.any(String),
          }),
        }),
      );
    });

    it("should throw error on failed request", async () => {
      (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: false,
        statusText: "Unauthorized",
        json: async () => ({ message: "Invalid token" }),
      });

      await expect(ApiService.getWorkspaces()).rejects.toThrow("Invalid token");
    });

    it("refreshes the access token once on 401 and retries the request", async () => {
      (AuthService.getToken as jest.Mock).mockResolvedValue("expired-token");
      (AuthService.refreshAccessToken as jest.Mock).mockResolvedValue(
        "fresh-token",
      );
      (globalThis.fetch as jest.Mock)
        .mockResolvedValueOnce({
          ok: false,
          status: 401,
          json: async () => ({ message: "expired" }),
        })
        .mockResolvedValueOnce({ ok: true, json: async () => ({ data: [] }) });

      const result = await ApiService.getWorkspaces();

      expect(AuthService.refreshAccessToken).toHaveBeenCalledTimes(1);
      expect(globalThis.fetch).toHaveBeenCalledTimes(2);
      expect(result).toEqual([]);
    });

    it("does NOT retry when refresh fails (surfaces the 401)", async () => {
      (AuthService.getToken as jest.Mock).mockResolvedValue("expired-token");
      (AuthService.refreshAccessToken as jest.Mock).mockResolvedValue(null);
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: false,
        status: 401,
        statusText: "Unauthorized",
        json: async () => ({ message: "expired" }),
      });

      await expect(ApiService.getWorkspaces()).rejects.toThrow("expired");
      // One refresh attempt, no infinite loop
      expect(AuthService.refreshAccessToken).toHaveBeenCalledTimes(1);
      expect(globalThis.fetch).toHaveBeenCalledTimes(1);
    });
  });

  describe("Workspaces CRUD", () => {
    const mockWorkspace = { id: "1", name: "Test WS" };

    beforeEach(() => {
      (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
    });

    it("getWorkspaces should return data", async () => {
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        json: async () => ({ data: [mockWorkspace] }),
      });

      const result = await ApiService.getWorkspaces();
      expect(result).toEqual([mockWorkspace]);
    });

    it("saveWorkspace should make PUT request", async () => {
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        json: async () => ({ data: mockWorkspace }),
      });

      await ApiService.saveWorkspace(mockWorkspace as unknown as Workspace);

      expect(globalThis.fetch).toHaveBeenCalledWith(
        expect.stringContaining("/workspaces/1"),
        expect.objectContaining({
          method: "PUT",
          body: JSON.stringify(mockWorkspace),
        }),
      );
    });

    it("deleteWorkspace should make DELETE request", async () => {
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        status: 204,
        json: async () => ({}),
      });

      await ApiService.deleteWorkspace("1");

      expect(globalThis.fetch).toHaveBeenCalledWith(
        expect.stringContaining("/workspaces/1"),
        expect.objectContaining({
          method: "DELETE",
        }),
      );
    });

    it("getWorkspace should return single workspace", async () => {
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        json: async () => ({ data: mockWorkspace }),
      });

      const result = await ApiService.getWorkspace("1");
      expect(result).toEqual(mockWorkspace);
      expect(globalThis.fetch).toHaveBeenCalledWith(
        expect.stringContaining("/workspaces/1"),
        expect.any(Object),
      );
    });
  });

  describe("Space Groups CRUD", () => {
    const mockSpaceGroup = {
      id: "sg-1",
      title: "Test Group",
      collapsed: false,
      position: 0,
    };

    beforeEach(() => {
      (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
    });

    it("getSpaceGroups should return data", async () => {
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        json: async () => ({ data: [mockSpaceGroup] }),
      });

      const result = await ApiService.getSpaceGroups();
      expect(result).toEqual([mockSpaceGroup]);
    });

    it("saveSpaceGroup should make PUT request", async () => {
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        json: async () => ({ data: mockSpaceGroup }),
      });

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await ApiService.saveSpaceGroup(mockSpaceGroup as any);

      expect(globalThis.fetch).toHaveBeenCalledWith(
        expect.stringContaining("/space-groups/sg-1"),
        expect.objectContaining({
          method: "PUT",
          body: JSON.stringify(mockSpaceGroup),
        }),
      );
    });

    it("deleteSpaceGroup should make DELETE request", async () => {
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        status: 204,
        json: async () => ({}),
      });

      await ApiService.deleteSpaceGroup("sg-1");

      expect(globalThis.fetch).toHaveBeenCalledWith(
        expect.stringContaining("/space-groups/sg-1"),
        expect.objectContaining({
          method: "DELETE",
        }),
      );
    });
  });

  describe("User Profile", () => {
    const mockProfile = {
      id: "user-1",
      name: "Test User",
      email: "test@example.com",
    };

    beforeEach(() => {
      (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
    });

    it("getUserProfile should return user data", async () => {
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        json: async () => ({ data: mockProfile }),
      });

      const result = await ApiService.getUserProfile();
      expect(result).toEqual(mockProfile);
      expect(globalThis.fetch).toHaveBeenCalledWith(
        expect.stringContaining("/users/me"),
        expect.any(Object),
      );
    });

    it("updateUserProfile should make PATCH request", async () => {
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        json: async () => ({ data: mockProfile }),
      });

      await ApiService.updateUserProfile({ name: "New Name" });

      expect(globalThis.fetch).toHaveBeenCalledWith(
        expect.stringContaining("/users/me"),
        expect.objectContaining({
          method: "PATCH",
          body: JSON.stringify({ name: "New Name" }),
        }),
      );
    });

    it("deleteUserAccount should make DELETE request", async () => {
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        status: 204,
        json: async () => ({}),
      });

      await ApiService.deleteUserAccount();

      expect(globalThis.fetch).toHaveBeenCalledWith(
        expect.stringContaining("/users/me"),
        expect.objectContaining({
          method: "DELETE",
        }),
      );
    });

    it("getPasswordResetUrl should return reset URL", async () => {
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        json: async () => ({ data: { resetUrl: "https://example.com/reset" } }),
      });

      const result = await ApiService.getPasswordResetUrl("test@example.com");
      expect(result).toBe("https://example.com/reset");
      expect(globalThis.fetch).toHaveBeenCalledWith(
        expect.stringContaining("/users/password-reset"),
        expect.objectContaining({
          method: "POST",
          body: JSON.stringify({ email: "test@example.com" }),
        }),
      );
    });
  });

  describe("refreshCachedUser", () => {
    it("re-projects the server profile over the cache, preserving the avatar", async () => {
      // Cached name was mojibaked by an older mis-encoded login; the avatar URL
      // is cache-only (the server never returns it).
      (AuthService.getUser as jest.Mock).mockResolvedValue({
        id: "user-1",
        name: "James Nguyá»…n",
        email: "james@example.com",
        tier: "free",
        picture: "https://cdn.example.com/avatar.png",
      });
      (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        json: async () => ({
          data: {
            id: "user-1",
            name: "James Nguyễn",
            email: "james@example.com",
            tier: "pro",
          },
        }),
      });

      const result = await ApiService.refreshCachedUser();

      const expected = {
        id: "user-1",
        name: "James Nguyễn",
        email: "james@example.com",
        tier: "pro",
        picture: "https://cdn.example.com/avatar.png",
      };
      expect(result).toEqual(expected);
      expect(AuthService.setCachedUser).toHaveBeenCalledWith(expected);
    });

    it("returns the cache without fetching or writing when signed out", async () => {
      const cached = {
        id: "user-1",
        name: "James Nguyá»…n",
        email: "james@example.com",
        tier: "free",
      };
      (AuthService.getUser as jest.Mock).mockResolvedValue(cached);
      (AuthService.getToken as jest.Mock).mockResolvedValue(null);

      const result = await ApiService.refreshCachedUser();

      expect(result).toEqual(cached);
      expect(globalThis.fetch).not.toHaveBeenCalled();
      expect(AuthService.setCachedUser).not.toHaveBeenCalled();
    });

    it("does not rewrite the cache when it already matches the server", async () => {
      const cached = {
        id: "user-1",
        name: "James Nguyễn",
        email: "james@example.com",
        tier: "free",
      };
      (AuthService.getUser as jest.Mock).mockResolvedValue(cached);
      (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        json: async () => ({ data: { ...cached } }),
      });

      const result = await ApiService.refreshCachedUser();

      expect(result).toEqual(cached);
      expect(AuthService.setCachedUser).not.toHaveBeenCalled();
    });

    it("falls back to the cache (never throws) when the profile fetch fails", async () => {
      const cached = {
        id: "user-1",
        name: "James Nguyá»…n",
        email: "james@example.com",
        tier: "free",
      };
      (AuthService.getUser as jest.Mock).mockResolvedValue(cached);
      (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
      (AuthService.refreshAccessToken as jest.Mock).mockResolvedValue(null);
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: false,
        status: 500,
        statusText: "Server Error",
        json: async () => ({ message: "boom" }),
      });

      const result = await ApiService.refreshCachedUser();

      expect(result).toEqual(cached);
      expect(AuthService.setCachedUser).not.toHaveBeenCalled();
    });
  });

  describe("Error handling edge cases", () => {
    beforeEach(() => {
      (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
    });

    it("should handle error response without message", async () => {
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: false,
        statusText: "Not Found",
        json: async () => ({}),
      });

      await expect(ApiService.getWorkspaces()).rejects.toThrow(
        "API Error: Not Found",
      );
    });

    it("should handle non-JSON error response", async () => {
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: false,
        statusText: "Server Error",
        json: async () => {
          throw new Error("Not JSON");
        },
      });

      await expect(ApiService.getWorkspaces()).rejects.toThrow("Unknown error");
    });
  });

  describe("Backups", () => {
    beforeEach(() => {
      (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
    });

    describe("getBackups", () => {
      it("should fetch backups without query params", async () => {
        const mockBackups = { backups: [{ id: "b1" }], total: 1 };
        (globalThis.fetch as jest.Mock).mockResolvedValue({
          ok: true,
          json: async () => ({ data: mockBackups }),
        });

        const result = await ApiService.getBackups();

        expect(result).toEqual(mockBackups);
        expect(globalThis.fetch).toHaveBeenCalledWith(
          expect.stringContaining("/backups"),
          expect.any(Object),
        );
      });

      it("should fetch backups with limit parameter", async () => {
        const mockBackups = { backups: [], total: 0 };
        (globalThis.fetch as jest.Mock).mockResolvedValue({
          ok: true,
          json: async () => ({ data: mockBackups }),
        });

        await ApiService.getBackups({ limit: 10 });

        expect(globalThis.fetch).toHaveBeenCalledWith(
          expect.stringContaining("limit=10"),
          expect.any(Object),
        );
      });

      it("should fetch backups with offset parameter", async () => {
        const mockBackups = { backups: [], total: 0 };
        (globalThis.fetch as jest.Mock).mockResolvedValue({
          ok: true,
          json: async () => ({ data: mockBackups }),
        });

        await ApiService.getBackups({ offset: 5 });

        expect(globalThis.fetch).toHaveBeenCalledWith(
          expect.stringContaining("offset=5"),
          expect.any(Object),
        );
      });

      it("should fetch backups with workspaceId parameter", async () => {
        const mockBackups = { backups: [], total: 0 };
        (globalThis.fetch as jest.Mock).mockResolvedValue({
          ok: true,
          json: async () => ({ data: mockBackups }),
        });

        await ApiService.getBackups({ workspaceId: "ws1" });

        expect(globalThis.fetch).toHaveBeenCalledWith(
          expect.stringContaining("workspaceId=ws1"),
          expect.any(Object),
        );
      });

      it("should fetch backups with all query parameters", async () => {
        const mockBackups = { backups: [], total: 0 };
        (globalThis.fetch as jest.Mock).mockResolvedValue({
          ok: true,
          json: async () => ({ data: mockBackups }),
        });

        await ApiService.getBackups({
          limit: 10,
          offset: 5,
          workspaceId: "ws1",
        });

        const url = (globalThis.fetch as jest.Mock).mock.calls[0][0];
        expect(url).toContain("limit=10");
        expect(url).toContain("offset=5");
        expect(url).toContain("workspaceId=ws1");
      });
    });

    describe("createBackup", () => {
      it("should create backup without options", async () => {
        const mockBackup = {
          id: "b1",
          workspaceId: null,
          sizeBytes: 100,
          createdAt: "2024-01-01",
        };
        (globalThis.fetch as jest.Mock).mockResolvedValue({
          ok: true,
          json: async () => ({ data: mockBackup }),
        });

        const result = await ApiService.createBackup();

        expect(result).toEqual(mockBackup);
        expect(globalThis.fetch).toHaveBeenCalledWith(
          expect.stringContaining("/backups"),
          expect.objectContaining({
            method: "POST",
            body: JSON.stringify({}),
          }),
        );
      });

      it("should create backup with workspaceId", async () => {
        const mockBackup = {
          id: "b1",
          workspaceId: "ws1",
          sizeBytes: 100,
          createdAt: "2024-01-01",
        };
        (globalThis.fetch as jest.Mock).mockResolvedValue({
          ok: true,
          json: async () => ({ data: mockBackup }),
        });

        await ApiService.createBackup({ workspaceId: "ws1" });

        expect(globalThis.fetch).toHaveBeenCalledWith(
          expect.stringContaining("/backups"),
          expect.objectContaining({
            method: "POST",
            body: JSON.stringify({ workspaceId: "ws1" }),
          }),
        );
      });

      it("should create backup with name and type", async () => {
        const mockBackup = {
          id: "b1",
          workspaceId: null,
          sizeBytes: 100,
          createdAt: "2024-01-01",
        };
        (globalThis.fetch as jest.Mock).mockResolvedValue({
          ok: true,
          json: async () => ({ data: mockBackup }),
        });

        await ApiService.createBackup({ name: "My Backup", type: "manual" });

        expect(globalThis.fetch).toHaveBeenCalledWith(
          expect.stringContaining("/backups"),
          expect.objectContaining({
            method: "POST",
            body: JSON.stringify({ name: "My Backup", type: "manual" }),
          }),
        );
      });
    });

    describe("getBackupStats", () => {
      it("should fetch backup stats", async () => {
        const mockStats = {
          totalBackups: 10,
          totalSizeBytes: 1024,
          autoBackups: 5,
          manualBackups: 5,
          oldestBackup: "2024-01-01",
          newestBackup: "2024-06-01",
          backupsByWorkspace: { ws1: 3 },
        };
        (globalThis.fetch as jest.Mock).mockResolvedValue({
          ok: true,
          json: async () => ({ data: mockStats }),
        });

        const result = await ApiService.getBackupStats();

        expect(result).toEqual(mockStats);
        expect(globalThis.fetch).toHaveBeenCalledWith(
          expect.stringContaining("/backups/stats"),
          expect.any(Object),
        );
      });
    });

    describe("restoreBackup", () => {
      it("should restore backup without options", async () => {
        const mockRestore = { restoredWorkspaceIds: ["ws1"] };
        (globalThis.fetch as jest.Mock).mockResolvedValue({
          ok: true,
          json: async () => ({ data: mockRestore }),
        });

        const result = await ApiService.restoreBackup("b1");

        expect(result).toEqual(mockRestore);
        expect(globalThis.fetch).toHaveBeenCalledWith(
          expect.stringContaining("/backups/b1/restore"),
          expect.objectContaining({
            method: "POST",
            body: JSON.stringify({}),
          }),
        );
      });

      it("should restore backup with targetWorkspaceId", async () => {
        const mockRestore = { restoredWorkspaceIds: ["ws2"] };
        (globalThis.fetch as jest.Mock).mockResolvedValue({
          ok: true,
          json: async () => ({ data: mockRestore }),
        });

        await ApiService.restoreBackup("b1", { targetWorkspaceId: "ws2" });

        expect(globalThis.fetch).toHaveBeenCalledWith(
          expect.stringContaining("/backups/b1/restore"),
          expect.objectContaining({
            method: "POST",
            body: JSON.stringify({ targetWorkspaceId: "ws2" }),
          }),
        );
      });

      it("should restore backup with createNew option", async () => {
        const mockRestore = { restoredWorkspaceIds: ["ws-new"] };
        (globalThis.fetch as jest.Mock).mockResolvedValue({
          ok: true,
          json: async () => ({ data: mockRestore }),
        });

        await ApiService.restoreBackup("b1", { createNew: true });

        expect(globalThis.fetch).toHaveBeenCalledWith(
          expect.stringContaining("/backups/b1/restore"),
          expect.objectContaining({
            method: "POST",
            body: JSON.stringify({ createNew: true }),
          }),
        );
      });
    });

    describe("deleteBackup", () => {
      it("should delete backup", async () => {
        (globalThis.fetch as jest.Mock).mockResolvedValue({
          ok: true,
          status: 204,
          json: async () => ({}),
        });

        await ApiService.deleteBackup("b1");

        expect(globalThis.fetch).toHaveBeenCalledWith(
          expect.stringContaining("/backups/b1"),
          expect.objectContaining({
            method: "DELETE",
          }),
        );
      });
    });
  });

  describe("204 status handling", () => {
    beforeEach(() => {
      (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
    });

    it("should handle 204 No Content response", async () => {
      (globalThis.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        status: 204,
      });

      const result = await ApiService.deleteWorkspace("ws1");

      expect(result).toEqual({});
    });
  });
});
