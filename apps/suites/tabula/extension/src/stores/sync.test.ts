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
 * Tests for sync Zustand store
 */

import { act } from "@testing-library/react";
import { useSyncStore } from "./sync";
import { SyncService, SyncState } from "../services/sync";

// Mock SyncService
jest.mock("../services/sync");

describe("useSyncStore", () => {
  let subscribeCallback: ((state: SyncState) => void) | null = null;

  beforeEach(() => {
    jest.clearAllMocks();
    subscribeCallback = null;

    // Reset store to initial state
    useSyncStore.setState({
      status: "idle",
      pendingCount: 0,
      lastSyncAt: null,
      lastError: null,
      isOnline: true,
    });

    // Mock SyncService methods
    (SyncService.initialize as jest.Mock).mockResolvedValue(undefined);
    (SyncService.retryAll as jest.Mock).mockResolvedValue(undefined);
    (SyncService.subscribe as jest.Mock).mockImplementation((callback) => {
      subscribeCallback = callback;
      return () => {};
    });
  });

  describe("initial state", () => {
    it("should have idle status", () => {
      expect(useSyncStore.getState().status).toBe("idle");
    });

    it("should have zero pending count", () => {
      expect(useSyncStore.getState().pendingCount).toBe(0);
    });

    it("should have null lastSyncAt", () => {
      expect(useSyncStore.getState().lastSyncAt).toBeNull();
    });

    it("should have null lastError", () => {
      expect(useSyncStore.getState().lastError).toBeNull();
    });

    it("should have isOnline true by default", () => {
      expect(useSyncStore.getState().isOnline).toBe(true);
    });
  });

  describe("initialize", () => {
    it("should call SyncService.initialize", async () => {
      await act(async () => {
        await useSyncStore.getState().initialize();
      });

      expect(SyncService.initialize).toHaveBeenCalled();
    });

    it("should subscribe to SyncService state changes", async () => {
      await act(async () => {
        await useSyncStore.getState().initialize();
      });

      expect(SyncService.subscribe).toHaveBeenCalled();
    });

    it("should update store when SyncService state changes", async () => {
      await act(async () => {
        await useSyncStore.getState().initialize();
      });

      // Simulate SyncService emitting a state change
      const newState: SyncState = {
        status: "syncing",
        pendingCount: 5,
        lastSyncAt: Date.now(),
        lastError: null,
        isOnline: true,
      };

      act(() => {
        if (subscribeCallback) {
          subscribeCallback(newState);
        }
      });

      expect(useSyncStore.getState().status).toBe("syncing");
      expect(useSyncStore.getState().pendingCount).toBe(5);
    });

    it("should reflect offline state from SyncService", async () => {
      await act(async () => {
        await useSyncStore.getState().initialize();
      });

      const offlineState: SyncState = {
        status: "offline",
        pendingCount: 2,
        lastSyncAt: null,
        lastError: null,
        isOnline: false,
      };

      act(() => {
        if (subscribeCallback) {
          subscribeCallback(offlineState);
        }
      });

      expect(useSyncStore.getState().status).toBe("offline");
      expect(useSyncStore.getState().isOnline).toBe(false);
    });

    it("should reflect error state from SyncService", async () => {
      await act(async () => {
        await useSyncStore.getState().initialize();
      });

      const errorState: SyncState = {
        status: "error",
        pendingCount: 1,
        lastSyncAt: null,
        lastError: "Network error",
        isOnline: true,
      };

      act(() => {
        if (subscribeCallback) {
          subscribeCallback(errorState);
        }
      });

      expect(useSyncStore.getState().status).toBe("error");
      expect(useSyncStore.getState().lastError).toBe("Network error");
    });
  });

  describe("retrySync", () => {
    it("should call SyncService.retryAll", async () => {
      await act(async () => {
        await useSyncStore.getState().retrySync();
      });

      expect(SyncService.retryAll).toHaveBeenCalled();
    });
  });
});
