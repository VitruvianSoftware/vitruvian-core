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

import { AuthService } from "./auth";

// Mock localStorage
const localStorageMock = (function createLocalStorageMock() {
  let store: Record<string, string> = {};
  return {
    getItem: jest.fn((key: string) => store[key] || null),
    setItem: jest.fn((key: string, value: string) => {
      store[key] = value.toString();
    }),
    removeItem: jest.fn((key: string) => {
      delete store[key];
    }),
    clear: jest.fn(() => {
      store = {};
    }),
  };
})();

Object.defineProperty(window, "localStorage", {
  value: localStorageMock,
});

describe("AuthService", () => {
  beforeEach(() => {
    localStorageMock.clear();
    jest.clearAllMocks();
  });

  describe("getToken", () => {
    it("should return token from localStorage", () => {
      localStorageMock.setItem("tabula_token", "test-token");
      expect(AuthService.getToken()).toBe("test-token");
    });

    it("should return null if no token", () => {
      expect(AuthService.getToken()).toBeNull();
    });
  });

  describe("getUser", () => {
    it("should return user from localStorage", () => {
      const user = {
        id: "1",
        name: "Test",
        email: "test@example.com",
        tier: "free",
      };
      localStorageMock.setItem("tabula_user", JSON.stringify(user));
      expect(AuthService.getUser()).toEqual(user);
    });

    it("should return null if no user", () => {
      expect(AuthService.getUser()).toBeNull();
    });
  });

  describe("logout", () => {
    it("should remove token and user from localStorage", () => {
      localStorageMock.setItem("tabula_token", "token");
      localStorageMock.setItem("tabula_user", "{}");

      AuthService.logout();

      expect(localStorageMock.removeItem).toHaveBeenCalledWith("tabula_token");
      expect(localStorageMock.removeItem).toHaveBeenCalledWith("tabula_user");
    });
  });

  describe("login", () => {
    let windowOpenSpy: jest.SpyInstance;

    beforeEach(() => {
      windowOpenSpy = jest
        .spyOn(window, "open")
        .mockReturnValue({ closed: false } as Window);
      jest.spyOn(window, "removeEventListener");

      // Use fake timers to control setInterval
      jest.useFakeTimers();
    });

    afterEach(() => {
      jest.useRealTimers();
    });

    it("should resolve with token and user on success message", async () => {
      const mockUser = { id: "1", name: "New User" };
      const windowAddEventListenerSpy = jest.spyOn(window, "addEventListener");

      const loginPromise = AuthService.login();

      // Simulate successful auth message
      const call = windowAddEventListenerSpy.mock.calls.find(
        (c) => c[0] === "message",
      );
      expect(call).toBeDefined();
      const messageHandler = call![1] as EventListener;
      const messageEvent = new MessageEvent("message", {
        data: {
          type: "TABULA_AUTH_SUCCESS",
          payload: {
            token: "test-token",
            user: mockUser,
          },
        },
        // The auth popup's own origin (AuthService.API_URL). Required by the
        // postMessage origin check that guards against token fixation.
        origin: "http://localhost:8080",
      });

      messageHandler(messageEvent);

      const result = await loginPromise;
      expect(result.token).toBe("test-token");
      expect(result.user).toEqual(mockUser);
      expect(localStorageMock.setItem).toHaveBeenCalledWith(
        "tabula_token",
        "test-token",
      );
      expect(localStorageMock.setItem).toHaveBeenCalledWith(
        "tabula_user",
        JSON.stringify(mockUser),
      );
      expect(windowAddEventListenerSpy).toHaveBeenCalledWith(
        "message",
        expect.any(Function),
      );
    });

    it("should reject if popup is blocked", async () => {
      windowOpenSpy.mockReturnValue(null);
      await expect(AuthService.login()).rejects.toThrow("Popup blocked");
    });

    it("should reject if popup is closed by user", async () => {
      const popupMock = { closed: false };
      windowOpenSpy.mockReturnValue(popupMock as Window);

      const promise = AuthService.login();

      // Simulate popup closing
      popupMock.closed = true;
      jest.advanceTimersByTime(1000);

      await expect(promise).rejects.toThrow("Login cancelled");
    });

    it("should ignore irrelevant messages", async () => {
      const windowAddEventListenerSpy = jest.spyOn(window, "addEventListener");
      AuthService.login();

      const call = windowAddEventListenerSpy.mock.calls.find(
        (c) => c[0] === "message",
      );
      expect(call).toBeDefined();
      const messageHandler = call![1] as EventListener;

      // Simulate irrelevant message
      const messageEvent = new MessageEvent("message", {
        data: { type: "OTHER_MESSAGE" },
      });

      // Should not throw or resolve
      messageHandler(messageEvent);
    });
  });

  describe("edge cases", () => {
    it("should return null if window is undefined (getToken)", () => {
      const originalWindow = global.window;
      // @ts-expect-error Mocking window
      delete global.window;

      expect(AuthService.getToken()).toBeNull();

      global.window = originalWindow;
    });

    it("should return null if window is undefined (getUser)", () => {
      const originalWindow = global.window;
      // @ts-expect-error Mocking window
      delete global.window;

      expect(AuthService.getUser()).toBeNull();

      global.window = originalWindow;
    });
  });
});
