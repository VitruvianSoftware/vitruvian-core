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
 * Unit tests for AuthService
 */
import { AuthService } from "./auth";

// Mock chrome API (local + session storage areas)
const mockChrome = {
  storage: {
    local: {
      get: jest.fn(),
      set: jest.fn(),
      remove: jest.fn(),
    },
    session: {
      get: jest.fn(),
      set: jest.fn(),
      remove: jest.fn(),
    },
  },
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
(globalThis as any).chrome = mockChrome;

// Mock window interactions
const mockWindowOpen = jest.fn();
const mockAddEventListener = jest.fn();
const mockRemoveEventListener = jest.fn();

// eslint-disable-next-line @typescript-eslint/no-explicit-any
(globalThis as any).open = mockWindowOpen;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
(globalThis as any).addEventListener = mockAddEventListener;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
(globalThis as any).removeEventListener = mockRemoveEventListener;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
(globalThis as any).screen = { width: 1920, height: 1080 };

describe("AuthService", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockChrome.storage.local.get.mockResolvedValue({});
    mockChrome.storage.local.set.mockResolvedValue(undefined);
    mockChrome.storage.local.remove.mockResolvedValue(undefined);
    mockChrome.storage.session.get.mockResolvedValue({});
    mockChrome.storage.session.set.mockResolvedValue(undefined);
    mockChrome.storage.session.remove.mockResolvedValue(undefined);
  });

  describe("login", () => {
    it("should open auth window and resolve user on a valid success message", async () => {
      const mockAuthWindow = { closed: false, close: jest.fn() };
      mockWindowOpen.mockReturnValue(mockAuthWindow);

      let messageHandler: ((event: Partial<MessageEvent>) => void) | null =
        null;
      mockAddEventListener.mockImplementation((event, handler) => {
        if (event === "message") messageHandler = handler;
      });

      const loginPromise = AuthService.login();

      expect(mockWindowOpen).toHaveBeenCalledWith(
        expect.stringContaining("/auth/login"),
        "tabula_auth",
        expect.stringContaining("width=600"),
      );

      const mockUser = {
        id: "user-123",
        email: "test@example.com",
        name: "Test User",
        tier: "free",
      };

      // Message must originate from the auth window we opened
      messageHandler!({
        source: mockAuthWindow as unknown as Window,
        origin: "",
        data: {
          type: "TABULA_AUTH_SUCCESS",
          payload: { token: "mock-jwt-token", user: mockUser },
        },
      });

      const result = await loginPromise;

      expect(result).toEqual(mockUser);
      // Token goes to session storage (in-memory), not disk
      expect(mockChrome.storage.session.set).toHaveBeenCalledWith({
        tabula_access_token: "mock-jwt-token",
      });
      // User + owner go to local
      expect(mockChrome.storage.local.set).toHaveBeenCalledWith({
        tabula_user: mockUser,
        tabula_data_owner: "user-123",
      });
      expect(mockRemoveEventListener).toHaveBeenCalledWith(
        "message",
        expect.any(Function),
      );
    });

    it("should reject if window fails to open", async () => {
      mockWindowOpen.mockReturnValue(null);
      await expect(AuthService.login()).rejects.toThrow(
        "Failed to open authentication window",
      );
    });

    it("should ignore a forged message from a different source window", async () => {
      const mockAuthWindow = { closed: false, close: jest.fn() };
      mockWindowOpen.mockReturnValue(mockAuthWindow);

      let messageHandler: ((event: Partial<MessageEvent>) => void) | null =
        null;
      mockAddEventListener.mockImplementation((event, handler) => {
        if (event === "message") messageHandler = handler;
      });

      const loginPromise = AuthService.login();

      // Attacker window posts a forged success — different source, must be ignored
      messageHandler!({
        source: { other: true } as unknown as Window,
        origin: "https://evil.example",
        data: {
          type: "TABULA_AUTH_SUCCESS",
          payload: { token: "evil", user: { id: "attacker" } },
        },
      });

      expect(mockChrome.storage.session.set).not.toHaveBeenCalled();

      // The legitimate message then completes login
      const mockUser = { id: "u1", email: "a@a.com", name: "A", tier: "free" };
      messageHandler!({
        source: mockAuthWindow as unknown as Window,
        origin: "",
        data: {
          type: "TABULA_AUTH_SUCCESS",
          payload: { token: "tok", user: mockUser },
        },
      });

      await loginPromise;
      expect(mockChrome.storage.session.set).toHaveBeenCalled();
    });

    it("should ignore messages with the wrong type", async () => {
      const mockAuthWindow = { closed: false, close: jest.fn() };
      mockWindowOpen.mockReturnValue(mockAuthWindow);

      let messageHandler: ((event: Partial<MessageEvent>) => void) | null =
        null;
      mockAddEventListener.mockImplementation((event, handler) => {
        if (event === "message") messageHandler = handler;
      });

      const loginPromise = AuthService.login();

      messageHandler!({
        source: mockAuthWindow as unknown as Window,
        origin: "",
        data: { type: "SOME_OTHER_MESSAGE" },
      });
      expect(mockChrome.storage.session.set).not.toHaveBeenCalled();

      const mockUser = { id: "u1", email: "a@a.com", name: "A", tier: "free" };
      messageHandler!({
        source: mockAuthWindow as unknown as Window,
        origin: "",
        data: {
          type: "TABULA_AUTH_SUCCESS",
          payload: { token: "tok", user: mockUser },
        },
      });

      await loginPromise;
      expect(mockChrome.storage.session.set).toHaveBeenCalled();
    });

    it("should reject when the auth window is closed before completing", async () => {
      jest.useFakeTimers();
      const mockAuthWindow = { closed: false, close: jest.fn() };
      mockWindowOpen.mockReturnValue(mockAuthWindow);
      mockAddEventListener.mockImplementation(() => {});

      const loginPromise = AuthService.login();
      // Assert rejection before advancing timers (avoids unhandled rejection)
      const expectation = expect(loginPromise).rejects.toThrow(
        "Authentication window was closed",
      );

      mockAuthWindow.closed = true;
      await jest.advanceTimersByTimeAsync(1000);

      await expectation;
      jest.useRealTimers();
    });
  });

  describe("logout", () => {
    it("should clear all per-user keys from local and the token from session", async () => {
      await AuthService.logout();

      expect(mockChrome.storage.local.remove).toHaveBeenCalledWith(
        expect.arrayContaining([
          "tabula_access_token",
          "tabula_user",
          "tabula_workspaces",
          "tabula_space_groups",
          "tabula_active_workspace",
          "tabula_sync_queue",
          "tabula_window_ownership",
          "tabula_data_owner",
        ]),
      );
      expect(mockChrome.storage.session.remove).toHaveBeenCalledWith(
        "tabula_access_token",
      );
    });

    it("should NOT remove device-level settings", async () => {
      await AuthService.logout();
      const removedKeys = mockChrome.storage.local.remove.mock
        .calls[0][0] as string[];
      expect(removedKeys).not.toContain("tabula_settings");
    });
  });

  describe("account switch guard", () => {
    it("purges cached data when a different user logs in", async () => {
      const mockAuthWindow = { closed: false, close: jest.fn() };
      mockWindowOpen.mockReturnValue(mockAuthWindow);
      // Previous owner differs from the new user
      mockChrome.storage.local.get.mockResolvedValue({
        tabula_data_owner: "old-user",
      });

      let messageHandler: ((event: Partial<MessageEvent>) => void) | null =
        null;
      mockAddEventListener.mockImplementation((event, handler) => {
        if (event === "message") messageHandler = handler;
      });

      const loginPromise = AuthService.login();
      messageHandler!({
        source: mockAuthWindow as unknown as Window,
        origin: "",
        data: {
          type: "TABULA_AUTH_SUCCESS",
          payload: {
            token: "tok",
            user: { id: "new-user", email: "n@n.com", name: "N", tier: "free" },
          },
        },
      });
      await loginPromise;

      // The stale account's data was purged before the new session took over
      expect(mockChrome.storage.local.remove).toHaveBeenCalledWith(
        expect.arrayContaining([
          "tabula_workspaces",
          "tabula_space_groups",
          "tabula_sync_queue",
        ]),
      );
    });
  });

  describe("getUser", () => {
    it("should return user from storage", async () => {
      const mockUser = {
        id: "user-123",
        email: "test@example.com",
        name: "Test User",
      };
      mockChrome.storage.local.get.mockResolvedValue({ tabula_user: mockUser });

      const result = await AuthService.getUser();
      expect(result).toEqual(mockUser);
    });

    it("should return null if no user in storage", async () => {
      mockChrome.storage.local.get.mockResolvedValue({});
      const result = await AuthService.getUser();
      expect(result).toBeNull();
    });
  });

  describe("setCachedUser", () => {
    it("overwrites the cached user record under tabula_user", async () => {
      const user = {
        id: "user-123",
        email: "james@example.com",
        name: "James Nguyễn",
        tier: "free",
      };

      await AuthService.setCachedUser(user);

      expect(mockChrome.storage.local.set).toHaveBeenCalledWith({
        tabula_user: user,
      });
    });
  });

  describe("getToken", () => {
    it("should return token from session storage", async () => {
      mockChrome.storage.session.get.mockResolvedValue({
        tabula_access_token: "my-token",
      });
      const result = await AuthService.getToken();
      expect(result).toBe("my-token");
    });

    it("should fall back to local storage when session has none", async () => {
      mockChrome.storage.session.get.mockResolvedValue({});
      mockChrome.storage.local.get.mockResolvedValue({
        tabula_access_token: "legacy-token",
      });
      const result = await AuthService.getToken();
      expect(result).toBe("legacy-token");
    });

    it("should return null if no token anywhere", async () => {
      mockChrome.storage.session.get.mockResolvedValue({});
      mockChrome.storage.local.get.mockResolvedValue({});
      const result = await AuthService.getToken();
      expect(result).toBeNull();
    });
  });

  describe("hasSession", () => {
    it("is true when an access token exists", async () => {
      mockChrome.storage.session.get.mockResolvedValue({
        tabula_access_token: "tok",
      });
      expect(await AuthService.hasSession()).toBe(true);
    });

    it("is true when only a persisted refresh token exists (post-restart)", async () => {
      // Access token wiped (session empty) but the refresh token survives.
      mockChrome.storage.session.get.mockResolvedValue({});
      mockChrome.storage.local.get.mockResolvedValue({
        tabula_refresh_token: "refresh",
      });
      expect(await AuthService.hasSession()).toBe(true);
    });

    it("is false when neither token exists", async () => {
      mockChrome.storage.session.get.mockResolvedValue({});
      mockChrome.storage.local.get.mockResolvedValue({});
      expect(await AuthService.hasSession()).toBe(false);
    });
  });

  describe("refreshAccessToken", () => {
    beforeEach(() => {
      (globalThis as unknown as { fetch: jest.Mock }).fetch = jest.fn();
    });

    it("returns null when there is no refresh token", async () => {
      mockChrome.storage.local.get.mockResolvedValue({});
      const result = await AuthService.refreshAccessToken();
      expect(result).toBeNull();
      expect(
        (globalThis as unknown as { fetch: jest.Mock }).fetch,
      ).not.toHaveBeenCalled();
    });

    it("rotates tokens on success and stores the new access + refresh token", async () => {
      mockChrome.storage.local.get.mockResolvedValue({
        tabula_refresh_token: "rt-old",
      });
      (globalThis as unknown as { fetch: jest.Mock }).fetch.mockResolvedValue({
        ok: true,
        json: async () => ({
          data: { token: "at-new", refreshToken: "rt-new" },
        }),
      });

      const result = await AuthService.refreshAccessToken();

      expect(result).toBe("at-new");
      expect(mockChrome.storage.session.set).toHaveBeenCalledWith({
        tabula_access_token: "at-new",
      });
      expect(mockChrome.storage.local.set).toHaveBeenCalledWith({
        tabula_refresh_token: "rt-new",
      });
    });

    it("single-flights concurrent refreshes into one network call", async () => {
      mockChrome.storage.local.get.mockResolvedValue({
        tabula_refresh_token: "rt",
      });
      (globalThis as unknown as { fetch: jest.Mock }).fetch.mockResolvedValue({
        ok: true,
        json: async () => ({ data: { token: "at", refreshToken: "rt2" } }),
      });

      const [a, b] = await Promise.all([
        AuthService.refreshAccessToken(),
        AuthService.refreshAccessToken(),
      ]);

      expect(a).toBe("at");
      expect(b).toBe("at");
      expect(
        (globalThis as unknown as { fetch: jest.Mock }).fetch,
      ).toHaveBeenCalledTimes(1);
    });

    it("clears tokens and returns null when the refresh token is rejected (401)", async () => {
      mockChrome.storage.local.get.mockResolvedValue({
        tabula_refresh_token: "rt-dead",
      });
      (globalThis as unknown as { fetch: jest.Mock }).fetch.mockResolvedValue({
        ok: false,
        status: 401,
        json: async () => ({ message: "invalid" }),
      });

      const result = await AuthService.refreshAccessToken();

      expect(result).toBeNull();
      expect(mockChrome.storage.local.remove).toHaveBeenCalledWith([
        "tabula_access_token",
        "tabula_refresh_token",
      ]);
    });

    it("returns null on a network error without throwing", async () => {
      mockChrome.storage.local.get.mockResolvedValue({
        tabula_refresh_token: "rt",
      });
      (globalThis as unknown as { fetch: jest.Mock }).fetch.mockRejectedValue(
        new Error("offline"),
      );
      const result = await AuthService.refreshAccessToken();
      expect(result).toBeNull();
    });
  });

  describe("logout server revocation", () => {
    beforeEach(() => {
      (globalThis as unknown as { fetch: jest.Mock }).fetch = jest
        .fn()
        .mockResolvedValue({ ok: true });
    });

    it("calls the server logout endpoint with the refresh token before clearing", async () => {
      mockChrome.storage.local.get.mockResolvedValue({
        tabula_refresh_token: "rt",
      });
      await AuthService.logout();
      expect(
        (globalThis as unknown as { fetch: jest.Mock }).fetch,
      ).toHaveBeenCalledWith(
        expect.stringContaining("/auth/logout"),
        expect.objectContaining({ method: "POST" }),
      );
      expect(mockChrome.storage.local.remove).toHaveBeenCalled();
    });

    it("still clears local state when the server logout call fails", async () => {
      mockChrome.storage.local.get.mockResolvedValue({
        tabula_refresh_token: "rt",
      });
      (globalThis as unknown as { fetch: jest.Mock }).fetch.mockRejectedValue(
        new Error("offline"),
      );
      await AuthService.logout();
      expect(mockChrome.storage.local.remove).toHaveBeenCalled();
    });
  });
});
