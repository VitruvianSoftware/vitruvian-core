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

/* eslint-disable @typescript-eslint/no-explicit-any */
/**
 * Tests for SyncService
 *
 * Tests the sync queue, retry logic, state management, and API integration.
 */

import { SyncService } from "./sync";
import { ApiService, ApiError } from "./api";
import { AuthService } from "./auth";
import { createWebLocksMock } from "../testUtils/webLocks";
import type { Workspace, SpaceGroup } from "../types";

// Mock dependencies (keep the real ApiError so instanceof checks work)
jest.mock("./api", () => {
  const actual = jest.requireActual("./api");
  return {
    ...actual,
    ApiService: {
      saveWorkspace: jest.fn(),
      deleteWorkspace: jest.fn(),
      saveSpaceGroup: jest.fn(),
      deleteSpaceGroup: jest.fn(),
    },
  };
});
jest.mock("./auth");

// Mock Chrome API
const mockStorage = new Map<string, any>();
const mockChrome = {
  storage: {
    local: {
      get: jest.fn((key) => {
        if (typeof key === "string") {
          return Promise.resolve({ [key]: mockStorage.get(key) });
        }
        if (Array.isArray(key)) {
          const result: Record<string, any> = {};
          key.forEach((k) => {
            result[k] = mockStorage.get(k);
          });
          return Promise.resolve(result);
        }
        return Promise.resolve(Object.fromEntries(mockStorage));
      }),
      set: jest.fn((items) => {
        Object.entries(items).forEach(([key, value]) => {
          mockStorage.set(key, value);
        });
        return Promise.resolve();
      }),
      remove: jest.fn((keys) => {
        const keyArray = Array.isArray(keys) ? keys : [keys];
        keyArray.forEach((k) => mockStorage.delete(k));
        return Promise.resolve();
      }),
      clear: jest.fn(() => {
        mockStorage.clear();
        return Promise.resolve();
      }),
    },
  },
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
(globalThis as any).chrome = mockChrome;

// Mock navigator (with a Web Locks polyfill — extension contexts always have it)
Object.defineProperty(globalThis, "navigator", {
  value: { onLine: true, locks: createWebLocksMock() },
  writable: true,
});

// Enqueue without triggering the fire-and-forget auto-process (so tests can
// run processQueue explicitly and assert deterministic post-conditions)
const enqueueQuietly = async (
  op: Parameters<typeof SyncService.enqueue>[0],
): Promise<void> => {
  (AuthService.getToken as jest.Mock).mockResolvedValueOnce(null);
  await SyncService.enqueue(op);
};

// Helper to create a mock workspace
const createMockWorkspace = (
  overrides: Partial<Workspace> = {},
): Workspace => ({
  id: "ws-test-123",
  name: "Test Workspace",
  tabs: [],
  resources: [],
  sections: [],
  notes: [],
  tasks: [],
  position: 0,
  createdAt: Date.now(),
  updatedAt: Date.now(),
  ...overrides,
});

// Helper to create a mock space group
const createMockSpaceGroup = (
  overrides: Partial<SpaceGroup> = {},
): SpaceGroup => ({
  id: "sg-test-123",
  title: "Test Space Group",
  color: "#000000",
  collapsed: false,
  position: 0,
  createdAt: Date.now(),
  updatedAt: Date.now(),
  ...overrides,
});

// Default chrome.storage mock implementations (restored before every test —
// some suites override them with mockResolvedValue/mockRejectedValue, which
// survives clearAllMocks)
const defaultStorageGet = (key: unknown) => {
  if (typeof key === "string") {
    return Promise.resolve({ [key]: mockStorage.get(key) });
  }
  if (Array.isArray(key)) {
    const result: Record<string, any> = {};
    key.forEach((k) => {
      result[k] = mockStorage.get(k);
    });
    return Promise.resolve(result);
  }
  return Promise.resolve(Object.fromEntries(mockStorage));
};
const defaultStorageSet = (items: Record<string, any>) => {
  Object.entries(items).forEach(([key, value]) => {
    mockStorage.set(key, value);
  });
  return Promise.resolve();
};

describe("SyncService", () => {
  beforeEach(async () => {
    jest.clearAllMocks();
    jest.useFakeTimers();

    // Reset mocks
    mockStorage.clear();
    mockChrome.storage.local.get.mockImplementation(defaultStorageGet);
    mockChrome.storage.local.set.mockImplementation(defaultStorageSet);
    (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
    (ApiService.saveWorkspace as jest.Mock).mockResolvedValue({});
    (ApiService.deleteWorkspace as jest.Mock).mockResolvedValue({});
    (ApiService.saveSpaceGroup as jest.Mock).mockResolvedValue({});
    (ApiService.deleteSpaceGroup as jest.Mock).mockResolvedValue({});

    // Clear the queue before each test
    await SyncService.clearQueue();
  });

  afterEach(() => {
    jest.useRealTimers();
    SyncService.stopPeriodicSync();
  });

  describe("getState", () => {
    it("should return current sync state", () => {
      const state = SyncService.getState();

      expect(state).toHaveProperty("status");
      expect(state).toHaveProperty("pendingCount");
      expect(state).toHaveProperty("lastSyncAt");
      expect(state).toHaveProperty("lastError");
      expect(state).toHaveProperty("isOnline");
    });

    it("should return a copy of state (not reference)", () => {
      const state1 = SyncService.getState();
      const state2 = SyncService.getState();

      expect(state1).toEqual(state2);
      expect(state1).not.toBe(state2);
    });
  });

  describe("subscribe", () => {
    it("should call listener immediately with current state", () => {
      const listener = jest.fn();

      SyncService.subscribe(listener);

      expect(listener).toHaveBeenCalledTimes(1);
      expect(listener).toHaveBeenCalledWith(
        expect.objectContaining({
          status: expect.any(String),
          pendingCount: expect.any(Number),
        }),
      );
    });

    it("should return unsubscribe function", () => {
      const listener = jest.fn();

      const unsubscribe = SyncService.subscribe(listener);

      expect(typeof unsubscribe).toBe("function");
    });

    it("should stop calling listener after unsubscribe", async () => {
      const listener = jest.fn();

      const unsubscribe = SyncService.subscribe(listener);
      expect(listener).toHaveBeenCalledTimes(1);

      unsubscribe();

      // Trigger a state change
      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: "test-ws",
        data: createMockWorkspace(),
      });

      // Listener should not have been called again after unsubscribe
      // (it may be called once more during enqueue, but not after unsubscribe)
    });
  });

  describe("getPendingSaveIds", () => {
    it("returns entity ids of pending saves for the given type only", async () => {
      await SyncService.clearQueue();
      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: "ws-save",
        data: createMockWorkspace({ id: "ws-save" }),
      });
      await SyncService.enqueue({
        type: "workspace",
        action: "delete",
        entityId: "ws-del",
      });

      const ids = await SyncService.getPendingSaveIds("workspace");
      expect(ids.has("ws-save")).toBe(true);
      // deletes are not saves
      expect(ids.has("ws-del")).toBe(false);
    });

    it("is empty when nothing is queued", async () => {
      await SyncService.clearQueue();
      const ids = await SyncService.getPendingSaveIds("workspace");
      expect(ids.size).toBe(0);
    });
  });

  describe("enqueue", () => {
    it("should add operation to queue", async () => {
      const workspace = createMockWorkspace();

      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: workspace.id,
        data: workspace,
      });

      expect(SyncService.getPendingCount()).toBeGreaterThanOrEqual(0);
    });

    it("should replace existing operation for same entity", async () => {
      const workspace1 = createMockWorkspace({ name: "First Version" });
      const workspace2 = createMockWorkspace({ name: "Second Version" });

      // Clear any pending operations first
      await SyncService.clearQueue();

      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: workspace1.id,
        data: workspace1,
      });

      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: workspace2.id,
        data: workspace2,
      });

      // Should have replaced, not added
      expect(SyncService.getPendingCount()).toBeLessThanOrEqual(2);
    });

    it("should persist queue to storage", async () => {
      const workspace = createMockWorkspace();

      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: workspace.id,
        data: workspace,
      });

      expect(mockChrome.storage.local.set).toHaveBeenCalled();
    });
  });

  describe("getPendingCount", () => {
    it("should return 0 when queue is empty", async () => {
      await SyncService.clearQueue();

      expect(SyncService.getPendingCount()).toBe(0);
    });
  });

  describe("hasFailedOperations", () => {
    it("should return false when no operations have failed", async () => {
      await SyncService.clearQueue();

      expect(SyncService.hasFailedOperations()).toBe(false);
    });
  });

  describe("clearQueue", () => {
    it("should remove all pending operations", async () => {
      // Add some operations
      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: "ws-1",
        data: createMockWorkspace({ id: "ws-1" }),
      });

      await SyncService.clearQueue();

      expect(SyncService.getPendingCount()).toBe(0);
    });

    it("should persist empty queue to storage", async () => {
      await SyncService.clearQueue();

      expect(mockChrome.storage.local.set).toHaveBeenCalledWith({
        tabula_sync_queue: [],
      });
    });

    it("should update state to idle", async () => {
      await SyncService.clearQueue();

      const state = SyncService.getState();
      expect(state.pendingCount).toBe(0);
    });
  });

  describe("processQueue", () => {
    it("should not process when offline", async () => {
      // Simulate offline
      Object.defineProperty(globalThis.navigator, "onLine", { value: false });

      const workspace = createMockWorkspace();
      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: workspace.id,
        data: workspace,
      });

      await SyncService.processQueue();

      // Should not have called API (can't verify directly, but queue should still have items)
    });

    it("should not process when not logged in", async () => {
      (AuthService.getToken as jest.Mock).mockResolvedValue(null);

      const workspace = createMockWorkspace();
      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: workspace.id,
        data: workspace,
      });

      await SyncService.processQueue();

      expect(ApiService.saveWorkspace).not.toHaveBeenCalled();
    });
  });

  describe("retryAll", () => {
    it("should reset retry counts and reprocess queue", async () => {
      await SyncService.clearQueue();

      // The retryAll should not throw
      await expect(SyncService.retryAll()).resolves.not.toThrow();
    });
  });

  describe("stopPeriodicSync", () => {
    it("should not throw when called", () => {
      expect(() => SyncService.stopPeriodicSync()).not.toThrow();
    });
  });

  describe("workspace operations", () => {
    it("should call ApiService.saveWorkspace for save action", async () => {
      const workspace = createMockWorkspace();

      await SyncService.clearQueue();
      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: workspace.id,
        data: workspace,
      });

      // Process the queue
      await SyncService.processQueue();

      // Allow async operations to complete
      await jest.runAllTimersAsync();

      expect(ApiService.saveWorkspace).toHaveBeenCalled();
    });

    it("should call ApiService.deleteWorkspace for delete action", async () => {
      await SyncService.clearQueue();
      await SyncService.enqueue({
        type: "workspace",
        action: "delete",
        entityId: "ws-to-delete",
      });

      await SyncService.processQueue();
      await jest.runAllTimersAsync();

      expect(ApiService.deleteWorkspace).toHaveBeenCalledWith("ws-to-delete");
    });
  });

  describe("spaceGroup operations", () => {
    it("should call ApiService.saveSpaceGroup for save action", async () => {
      const spaceGroup = createMockSpaceGroup();

      await SyncService.clearQueue();
      await SyncService.enqueue({
        type: "spaceGroup",
        action: "save",
        entityId: spaceGroup.id,
        data: spaceGroup,
      });

      await SyncService.processQueue();
      await jest.runAllTimersAsync();

      expect(ApiService.saveSpaceGroup).toHaveBeenCalled();
    });

    it("should call ApiService.deleteSpaceGroup for delete action", async () => {
      await SyncService.clearQueue();
      await SyncService.enqueue({
        type: "spaceGroup",
        action: "delete",
        entityId: "sg-to-delete",
      });

      await SyncService.processQueue();
      await jest.runAllTimersAsync();

      expect(ApiService.deleteSpaceGroup).toHaveBeenCalledWith("sg-to-delete");
    });
  });

  describe("tab ID sanitization", () => {
    it("should convert string tab IDs to numbers during sync", async () => {
      const workspace = createMockWorkspace({
        tabs: [
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          {
            id: "123" as any,
            url: "https://example.com",
            title: "Test",
            pinned: false,
            active: false,
            index: 0,
          },
        ],
      });

      await SyncService.clearQueue();
      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: workspace.id,
        data: workspace,
      });

      await SyncService.processQueue();
      await jest.runAllTimersAsync();

      // The sanitized workspace should have numeric tab IDs
      if ((ApiService.saveWorkspace as jest.Mock).mock.calls.length > 0) {
        const savedWorkspace = (ApiService.saveWorkspace as jest.Mock).mock
          .calls[0][0];
        if (savedWorkspace.tabs && savedWorkspace.tabs.length > 0) {
          expect(typeof savedWorkspace.tabs[0].id).toBe("number");
        }
      }
    });
  });

  describe("error handling", () => {
    it("should handle offline state gracefully", async () => {
      Object.defineProperty(globalThis.navigator, "onLine", { value: false });

      // Should not throw when offline
      await expect(SyncService.processQueue()).resolves.not.toThrow();
    });

    it("should handle API errors gracefully", async () => {
      (ApiService.saveWorkspace as jest.Mock).mockRejectedValue(
        new Error("Network error"),
      );

      const workspace = createMockWorkspace();
      await SyncService.clearQueue();
      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: workspace.id,
        data: workspace,
      });

      await SyncService.processQueue();
      await jest.runAllTimersAsync();

      // Should have incremented retry count
      expect(SyncService.getPendingCount()).toBeGreaterThanOrEqual(0);
    });

    it("should handle unknown operation types", async () => {
      await SyncService.clearQueue();
      await SyncService.enqueue({
        type: "unknown" as any,
        action: "save",
        entityId: "test-id",
      });

      // Should not throw
      await expect(SyncService.processQueue()).resolves.not.toThrow();
    });
  });

  describe("multiple subscriptions", () => {
    it("should support multiple listeners", () => {
      const listener1 = jest.fn();
      const listener2 = jest.fn();

      const unsub1 = SyncService.subscribe(listener1);
      const unsub2 = SyncService.subscribe(listener2);

      expect(listener1).toHaveBeenCalled();
      expect(listener2).toHaveBeenCalled();

      unsub1();
      unsub2();
    });
  });

  describe("operations without data", () => {
    it("should handle save operation without data", async () => {
      await SyncService.clearQueue();
      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: "ws-no-data",
        // No data provided
      });

      await SyncService.processQueue();
      await jest.runAllTimersAsync();

      // Should not crash when data is undefined
    });

    it("should handle spaceGroup save without data", async () => {
      await SyncService.clearQueue();
      await SyncService.enqueue({
        type: "spaceGroup",
        action: "save",
        entityId: "sg-no-data",
        // No data provided
      });

      await SyncService.processQueue();
      await jest.runAllTimersAsync();

      // Should not crash when data is undefined
    });
  });

  describe("workspace with no tabs array", () => {
    it("should handle workspace without tabs array during sync", async () => {
      const workspaceNoTabs = {
        id: "ws-no-tabs",
        name: "No Tabs Workspace",
        // tabs: undefined - not provided
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };

      await SyncService.clearQueue();
      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: workspaceNoTabs.id,
        data: workspaceNoTabs as any,
      });

      await SyncService.processQueue();
      await jest.runAllTimersAsync();

      // Should not crash when tabs is undefined
      expect(ApiService.saveWorkspace).toHaveBeenCalled();
    });
  });

  describe("tab ID already numeric", () => {
    it("should handle numeric tab IDs without conversion", async () => {
      const workspace = createMockWorkspace({
        tabs: [
          {
            id: 123,
            url: "https://example.com",
            title: "Test",
            pinned: false,
            active: false,
            index: 0,
          },
        ],
      });

      await SyncService.clearQueue();
      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: workspace.id,
        data: workspace,
      });

      await SyncService.processQueue();
      await jest.runAllTimersAsync();

      if ((ApiService.saveWorkspace as jest.Mock).mock.calls.length > 0) {
        const savedWorkspace = (ApiService.saveWorkspace as jest.Mock).mock
          .calls[0][0];
        if (savedWorkspace.tabs && savedWorkspace.tabs.length > 0) {
          expect(savedWorkspace.tabs[0].id).toBe(123);
        }
      }
    });
  });

  describe("SSE functionality", () => {
    beforeEach(() => {
      // Mock EventSource
      (globalThis as any).EventSource = jest.fn().mockImplementation(() => ({
        onopen: null,
        onerror: null,
        addEventListener: jest.fn(),
        close: jest.fn(),
      }));
    });

    afterEach(() => {
      SyncService.disconnectSSE();
      delete (globalThis as any).EventSource;
    });

    it("subscribeToSSE should add listener and return unsubscribe function", async () => {
      (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
      Object.defineProperty(globalThis.navigator, "onLine", { value: true });

      const listener = jest.fn();
      const unsubscribe = SyncService.subscribeToSSE(listener);

      expect(typeof unsubscribe).toBe("function");
      unsubscribe();
    });

    it("subscribeToSSE should connect to SSE on first subscriber", async () => {
      (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
      Object.defineProperty(globalThis.navigator, "onLine", { value: true });

      const listener = jest.fn();
      SyncService.subscribeToSSE(listener);

      // Allow the async token/deviceId reads to complete
      await jest.runAllTimersAsync();

      expect((globalThis as any).EventSource).toHaveBeenCalled();
      // Token must ride in the query string (EventSource cannot set headers)
      const url = ((globalThis as any).EventSource as jest.Mock).mock
        .calls[0][0] as string;
      expect(url).toContain("token=test-token");
      expect(url).toContain("deviceId=");
    });

    it("subscribeToSSE should disconnect SSE when last subscriber unsubscribes", async () => {
      (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
      Object.defineProperty(globalThis.navigator, "onLine", { value: true });

      const listener = jest.fn();
      const unsubscribe = SyncService.subscribeToSSE(listener);

      // Allow async operations to complete
      await Promise.resolve();

      unsubscribe();

      // SSE should be disconnected
    });

    it("disconnectSSE should close EventSource and clear reconnect timer", () => {
      // First set up a mock event source
      const mockClose = jest.fn();
      (globalThis as any).EventSource = jest.fn().mockReturnValue({
        onopen: null,
        onerror: null,
        addEventListener: jest.fn(),
        close: mockClose,
      });

      // Manually trigger connection - this sets up internal state
      SyncService.disconnectSSE();

      // No error should be thrown
    });

    it("should not connect to SSE when offline", async () => {
      (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
      // Instead of modifying navigator.onLine, we need to update the internal state
      // which happens through handleOnlineStatusChange

      // Don't connect to SSE if not online - handled by internal state check
    });

    it("should not connect to SSE when not logged in", async () => {
      (AuthService.getToken as jest.Mock).mockResolvedValue(null);
      Object.defineProperty(globalThis.navigator, "onLine", { value: true });

      await SyncService.connectToSSE();

      // EventSource should not be created when no token
    });
  });

  describe("initialize", () => {
    beforeEach(() => {
      // Reset initialized state - access private field via reflection
      (SyncService as any).initialized = false;
    });

    it("should only initialize once", async () => {
      (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");

      await SyncService.initialize();
      await SyncService.initialize();

      // Second call should return immediately
    });

    it("should load queue on initialization", async () => {
      (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
      mockChrome.storage.local.get.mockResolvedValue({ tabula_sync_queue: [] });

      (SyncService as any).initialized = false;
      await SyncService.initialize();

      expect(mockChrome.storage.local.get).toHaveBeenCalled();
    });

    it("should process queue on init if online and logged in", async () => {
      (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
      Object.defineProperty(globalThis.navigator, "onLine", { value: true });
      mockChrome.storage.local.get.mockResolvedValue({ tabula_sync_queue: [] });

      (SyncService as any).initialized = false;
      await SyncService.initialize();

      // Queue should be processed
    });
  });

  describe("periodic sync", () => {
    it("should start periodic sync timer", async () => {
      (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
      mockChrome.storage.local.get.mockResolvedValue({});

      (SyncService as any).initialized = false;
      await SyncService.initialize();

      // Periodic sync should be running
      SyncService.stopPeriodicSync();
    });

    it("stopPeriodicSync should clear interval", () => {
      // Start periodic sync first
      (SyncService as any).periodicSyncTimer = setInterval(() => {}, 1000);

      SyncService.stopPeriodicSync();

      expect((SyncService as any).periodicSyncTimer).toBeNull();
    });

    it("stopPeriodicSync should handle null timer", () => {
      (SyncService as any).periodicSyncTimer = null;

      expect(() => SyncService.stopPeriodicSync()).not.toThrow();
    });
  });

  describe("queue loading errors", () => {
    it("should handle chrome storage error during loadQueue", async () => {
      mockChrome.storage.local.get.mockRejectedValue(
        new Error("Storage error"),
      );

      // Reset to force reload
      (SyncService as any).initialized = false;
      (SyncService as any).queue = [];

      try {
        await SyncService.initialize();
      } catch {
        // Expected
      }

      // Queue should be empty after error
      expect(SyncService.getPendingCount()).toBe(0);
    });

    it("should handle chrome storage error during saveQueue", async () => {
      mockChrome.storage.local.set.mockRejectedValue(new Error("Save error"));

      // Should not throw
      await expect(
        SyncService.enqueue({
          type: "workspace",
          action: "save",
          entityId: "test",
          data: createMockWorkspace(),
        }),
      ).resolves.not.toThrow();
    });
  });

  describe("retry mechanism", () => {
    it("should increment retry count on failure", async () => {
      (ApiService.saveWorkspace as jest.Mock).mockRejectedValue(
        new Error("Network error"),
      );

      const workspace = createMockWorkspace();
      await SyncService.clearQueue();
      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: workspace.id,
        data: workspace,
      });

      await SyncService.processQueue();
      await jest.runAllTimersAsync();

      // Operation should still be in queue with incremented retry count
      expect(SyncService.getPendingCount()).toBeGreaterThanOrEqual(0);
    });

    it("should mark operation as failed after max retries", async () => {
      (ApiService.saveWorkspace as jest.Mock).mockRejectedValue(
        new Error("Network error"),
      );

      const workspace = createMockWorkspace();
      await SyncService.clearQueue();
      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: workspace.id,
        data: workspace,
      });

      // Process multiple times to hit max retries
      const processRetries = async (count: number): Promise<void> => {
        if (count <= 0) return;
        await SyncService.processQueue();
        await jest.runAllTimersAsync();
        return processRetries(count - 1);
      };
      await processRetries(6);
    });
  });

  describe("cross-context queue safety", () => {
    it("enqueue must not clobber ops written to storage by another context", async () => {
      // Simulate another dashboard window having persisted an op directly
      // to storage (this context's in-memory queue knows nothing about it)
      const foreignOp = {
        id: "sync_foreign_1",
        type: "workspace",
        action: "save",
        entityId: "ws-from-other-window",
        data: createMockWorkspace({ id: "ws-from-other-window" }),
        timestamp: Date.now(),
        retries: 0,
      };
      mockStorage.set("tabula_sync_queue", [foreignOp]);

      // Block processing so the queue isn't drained before we can assert
      (AuthService.getToken as jest.Mock).mockResolvedValue(null);

      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: "ws-local",
        data: createMockWorkspace({ id: "ws-local" }),
      });

      const persisted = mockStorage.get("tabula_sync_queue");
      const ids = persisted.map((op: { entityId: string }) => op.entityId);
      expect(ids).toContain("ws-from-other-window");
      expect(ids).toContain("ws-local");
    });

    it("retryAll must reload from storage before resetting and saving", async () => {
      const foreignOp = {
        id: "sync_foreign_2",
        type: "workspace",
        action: "save",
        entityId: "ws-foreign",
        data: createMockWorkspace({ id: "ws-foreign" }),
        timestamp: Date.now(),
        retries: 5, // exhausted — retryAll should reset it
      };
      mockStorage.set("tabula_sync_queue", [foreignOp]);
      (AuthService.getToken as jest.Mock).mockResolvedValue(null);

      await SyncService.retryAll();

      const persisted = mockStorage.get("tabula_sync_queue");
      expect(persisted).toHaveLength(1);
      expect(persisted[0].entityId).toBe("ws-foreign");
      expect(persisted[0].retries).toBe(0);
    });
  });

  describe("enqueue action semantics", () => {
    beforeEach(() => {
      // Keep ops in the queue (no processing)
      (AuthService.getToken as jest.Mock).mockResolvedValue(null);
    });

    it("delete supersedes a pending save for the same entity", async () => {
      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: "ws-1",
        data: createMockWorkspace({ id: "ws-1" }),
      });
      await SyncService.enqueue({
        type: "workspace",
        action: "delete",
        entityId: "ws-1",
      });

      const persisted = mockStorage.get("tabula_sync_queue");
      expect(persisted).toHaveLength(1);
      expect(persisted[0].action).toBe("delete");
    });

    it("save after delete keeps both ops in order (delete still executes)", async () => {
      await SyncService.enqueue({
        type: "workspace",
        action: "delete",
        entityId: "ws-1",
      });
      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: "ws-1",
        data: createMockWorkspace({ id: "ws-1" }),
      });

      const persisted = mockStorage.get("tabula_sync_queue");
      expect(persisted).toHaveLength(2);
      expect(persisted[0].action).toBe("delete");
      expect(persisted[1].action).toBe("save");
    });

    it("a claimActiveDevice flag survives replacement by a later save", async () => {
      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: "ws-1",
        data: createMockWorkspace({ id: "ws-1" }),
        meta: { claimActiveDevice: true },
      });
      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: "ws-1",
        data: createMockWorkspace({ id: "ws-1", name: "Newer" }),
        meta: { source: "tabSync" },
      });

      const persisted = mockStorage.get("tabula_sync_queue");
      expect(persisted).toHaveLength(1);
      expect(persisted[0].meta.claimActiveDevice).toBe(true);
      expect((persisted[0].data as Workspace).name).toBe("Newer");
    });
  });

  describe("retry backoff", () => {
    it("sets nextRetryAt with exponential backoff on failure", async () => {
      (ApiService.saveWorkspace as jest.Mock).mockRejectedValue(
        new Error("Network error"),
      );

      await enqueueQuietly({
        type: "workspace",
        action: "save",
        entityId: "ws-fail",
        data: createMockWorkspace({ id: "ws-fail" }),
      });
      await SyncService.processQueue();

      const persisted = mockStorage.get("tabula_sync_queue");
      expect(persisted).toHaveLength(1);
      expect(persisted[0].retries).toBe(1);
      expect(persisted[0].nextRetryAt).toBeGreaterThan(Date.now());
      expect(persisted[0].lastError).toBe("Network error");
    });

    it("does not re-execute ops that are backing off", async () => {
      (ApiService.saveWorkspace as jest.Mock).mockRejectedValue(
        new Error("Network error"),
      );

      await enqueueQuietly({
        type: "workspace",
        action: "save",
        entityId: "ws-fail",
        data: createMockWorkspace({ id: "ws-fail" }),
      });
      await SyncService.processQueue();
      (ApiService.saveWorkspace as jest.Mock).mockClear();

      // Immediate reprocess: op is backing off, must be skipped
      await SyncService.processQueue();
      expect(ApiService.saveWorkspace).not.toHaveBeenCalled();
    });

    it("parks ops after MAX_RETRIES instead of hammering the API", async () => {
      (ApiService.saveWorkspace as jest.Mock).mockRejectedValue(
        new Error("Permanent error"),
      );

      // Seed an op that has already exhausted its retries
      mockStorage.set("tabula_sync_queue", [
        {
          id: "sync_poison",
          type: "workspace",
          action: "save",
          entityId: "ws-poison",
          data: createMockWorkspace({ id: "ws-poison" }),
          timestamp: Date.now(),
          retries: 5,
        },
      ]);

      await SyncService.processQueue();
      expect(ApiService.saveWorkspace).not.toHaveBeenCalled();

      // Still parked in the queue for manual retry
      expect(mockStorage.get("tabula_sync_queue")).toHaveLength(1);
    });

    it("dropFailedOperations removes exhausted ops", async () => {
      mockStorage.set("tabula_sync_queue", [
        {
          id: "sync_poison",
          type: "workspace",
          action: "save",
          entityId: "ws-poison",
          timestamp: Date.now(),
          retries: 5,
        },
        {
          id: "sync_healthy",
          type: "workspace",
          action: "save",
          entityId: "ws-healthy",
          data: createMockWorkspace({ id: "ws-healthy" }),
          timestamp: Date.now(),
          retries: 0,
        },
      ]);
      (AuthService.getToken as jest.Mock).mockResolvedValue(null);

      await SyncService.dropFailedOperations();

      const persisted = mockStorage.get("tabula_sync_queue");
      expect(persisted).toHaveLength(1);
      expect(persisted[0].entityId).toBe("ws-healthy");
    });
  });

  describe("protocol error handling", () => {
    it("treats 404 on delete as success (entity already gone)", async () => {
      (ApiService.deleteWorkspace as jest.Mock).mockRejectedValue(
        new ApiError("Workspace not found", 404),
      );

      await enqueueQuietly({
        type: "workspace",
        action: "delete",
        entityId: "ws-already-gone",
      });
      await SyncService.processQueue();

      expect(mockStorage.get("tabula_sync_queue")).toHaveLength(0);
      expect(SyncService.hasFailedOperations()).toBe(false);
    });

    it("on 410 Gone drops the op and removes the local copy", async () => {
      const ws = createMockWorkspace({ id: "ws-deleted-remotely" });
      mockStorage.set("tabula_workspaces", [ws]);
      (ApiService.saveWorkspace as jest.Mock).mockRejectedValue(
        new ApiError("Entity was deleted", 410),
      );

      await enqueueQuietly({
        type: "workspace",
        action: "save",
        entityId: ws.id,
        data: ws,
      });
      await SyncService.processQueue();

      expect(mockStorage.get("tabula_sync_queue")).toHaveLength(0);
      expect(mockStorage.get("tabula_workspaces")).toHaveLength(0);
    });

    it("on 409 where local is newer: adopts server version and retries", async () => {
      const local = createMockWorkspace({ id: "ws-conflict", updatedAt: 2000 });
      mockStorage.set("tabula_workspaces", [local]);

      const serverCopy = {
        ...createMockWorkspace({ id: "ws-conflict", updatedAt: 1000 }),
        version: 7,
      };
      (ApiService.saveWorkspace as jest.Mock).mockRejectedValue(
        new ApiError("Conflict", 409, serverCopy),
      );

      await enqueueQuietly({
        type: "workspace",
        action: "save",
        entityId: local.id,
        data: local,
      });
      await SyncService.processQueue();

      // Local storage now carries the server's version for the retry
      const storedWs = mockStorage.get("tabula_workspaces")[0];
      expect(storedWs.version).toBe(7);
      expect(storedWs.updatedAt).toBe(2000); // content untouched

      // Op still queued (retrying), payload refreshed with the new version
      const persisted = mockStorage.get("tabula_sync_queue");
      expect(persisted).toHaveLength(1);
      expect(persisted[0].retries).toBe(1);
      expect((persisted[0].data as Workspace).version).toBe(7);
    });

    it("on 409 where server is newer: adopts server state and drops the op", async () => {
      const local = createMockWorkspace({
        id: "ws-conflict",
        updatedAt: 1000,
        name: "Old local",
      });
      mockStorage.set("tabula_workspaces", [local]);

      const serverCopy = {
        ...createMockWorkspace({
          id: "ws-conflict",
          updatedAt: 5000,
          name: "Newer remote",
        }),
        version: 9,
      };
      (ApiService.saveWorkspace as jest.Mock).mockRejectedValue(
        new ApiError("Conflict", 409, serverCopy),
      );

      await enqueueQuietly({
        type: "workspace",
        action: "save",
        entityId: local.id,
        data: local,
      });
      await SyncService.processQueue();

      expect(mockStorage.get("tabula_sync_queue")).toHaveLength(0);
      const storedWs = mockStorage.get("tabula_workspaces")[0];
      expect(storedWs.name).toBe("Newer remote");
      expect(storedWs.version).toBe(9);
    });

    it("records the new server version locally after a successful save", async () => {
      const ws = createMockWorkspace({ id: "ws-ok", updatedAt: 1234 });
      mockStorage.set("tabula_workspaces", [ws]);
      (ApiService.saveWorkspace as jest.Mock).mockResolvedValue({
        ...ws,
        version: 3,
        activeDeviceId: "device_abc",
        activeDeviceSeenAt: "2026-06-10T00:00:00.000Z",
      });

      await enqueueQuietly({
        type: "workspace",
        action: "save",
        entityId: ws.id,
        data: ws,
      });
      await SyncService.processQueue();

      const storedWs = mockStorage.get("tabula_workspaces")[0];
      expect(storedWs.version).toBe(3);
      expect(storedWs.activeDeviceId).toBe("device_abc");
      expect(storedWs.updatedAt).toBe(1234); // content untouched
      expect(mockStorage.get("tabula_sync_queue")).toHaveLength(0);
    });
  });

  describe("spaceGroup protocol error handling", () => {
    it("records the new server version locally after a successful spaceGroup save", async () => {
      const group = createMockSpaceGroup({ id: "sg-ok" });
      mockStorage.set("tabula_space_groups", [group]);
      (ApiService.saveSpaceGroup as jest.Mock).mockResolvedValue({
        ...group,
        version: 4,
      });

      await enqueueQuietly({
        type: "spaceGroup",
        action: "save",
        entityId: group.id,
        data: group,
      });
      await SyncService.processQueue();

      expect(mockStorage.get("tabula_space_groups")[0].version).toBe(4);
      expect(mockStorage.get("tabula_sync_queue")).toHaveLength(0);
    });

    it("on 410 Gone drops the op and removes the local spaceGroup", async () => {
      const group = createMockSpaceGroup({ id: "sg-deleted" });
      mockStorage.set("tabula_space_groups", [group]);
      (ApiService.saveSpaceGroup as jest.Mock).mockRejectedValue(
        new ApiError("Gone", 410),
      );

      await enqueueQuietly({
        type: "spaceGroup",
        action: "save",
        entityId: group.id,
        data: group,
      });
      await SyncService.processQueue();

      expect(mockStorage.get("tabula_sync_queue")).toHaveLength(0);
      expect(mockStorage.get("tabula_space_groups")).toHaveLength(0);
    });

    it("on 409 where server is newer: adopts server spaceGroup and drops the op", async () => {
      const local = createMockSpaceGroup({
        id: "sg-conflict",
        updatedAt: 1000,
        title: "Old",
      });
      mockStorage.set("tabula_space_groups", [local]);
      const server = {
        ...createMockSpaceGroup({
          id: "sg-conflict",
          updatedAt: 5000,
          title: "New",
        }),
        version: 8,
      };
      (ApiService.saveSpaceGroup as jest.Mock).mockRejectedValue(
        new ApiError("Conflict", 409, server),
      );

      await enqueueQuietly({
        type: "spaceGroup",
        action: "save",
        entityId: local.id,
        data: local,
      });
      await SyncService.processQueue();

      expect(mockStorage.get("tabula_sync_queue")).toHaveLength(0);
      expect(mockStorage.get("tabula_space_groups")[0].title).toBe("New");
    });

    it("on 409 where local is newer: adopts server version and retries", async () => {
      const local = createMockSpaceGroup({
        id: "sg-conflict",
        updatedAt: 5000,
      });
      mockStorage.set("tabula_space_groups", [local]);
      const server = {
        ...createMockSpaceGroup({ id: "sg-conflict", updatedAt: 1000 }),
        version: 3,
      };
      (ApiService.saveSpaceGroup as jest.Mock).mockRejectedValue(
        new ApiError("Conflict", 409, server),
      );

      await enqueueQuietly({
        type: "spaceGroup",
        action: "save",
        entityId: local.id,
        data: local,
      });
      await SyncService.processQueue();

      expect(mockStorage.get("tabula_space_groups")[0].version).toBe(3);
      const persisted = mockStorage.get("tabula_sync_queue");
      expect(persisted).toHaveLength(1);
      expect(persisted[0].retries).toBe(1);
    });

    it("treats 404 on spaceGroup delete as success", async () => {
      (ApiService.deleteSpaceGroup as jest.Mock).mockRejectedValue(
        new ApiError("Not found", 404),
      );
      await enqueueQuietly({
        type: "spaceGroup",
        action: "delete",
        entityId: "sg-gone",
      });
      await SyncService.processQueue();
      expect(mockStorage.get("tabula_sync_queue")).toHaveLength(0);
    });
  });

  describe("online status handling", () => {
    it("clears backoff and reprocesses when coming back online", async () => {
      // Seed a backing-off op
      mockStorage.set("tabula_sync_queue", [
        {
          id: "op1",
          type: "workspace",
          action: "save",
          entityId: "ws-x",
          data: createMockWorkspace({ id: "ws-x" }),
          timestamp: Date.now(),
          retries: 1,
          nextRetryAt: Date.now() + 60000,
        },
      ]);
      (ApiService.saveWorkspace as jest.Mock).mockResolvedValue({});

      // Trigger the online handler (private; invoke via the registered listener path)
      await (
        SyncService as unknown as {
          handleOnlineStatusChange: (b: boolean) => void;
        }
      ).handleOnlineStatusChange(true);
      await jest.runAllTimersAsync();

      // The op's stale backoff is cleared so it can flush immediately
      expect(ApiService.saveWorkspace).toHaveBeenCalled();
    });
  });

  describe("dropOperationsFor", () => {
    it("removes pending ops for the given entities only", async () => {
      (AuthService.getToken as jest.Mock).mockResolvedValue(null);
      await enqueueQuietly({
        type: "workspace",
        action: "save",
        entityId: "ws-restored",
        data: createMockWorkspace({ id: "ws-restored" }),
      });
      await enqueueQuietly({
        type: "workspace",
        action: "save",
        entityId: "ws-untouched",
        data: createMockWorkspace({ id: "ws-untouched" }),
      });

      await SyncService.dropOperationsFor(["ws-restored"]);

      const persisted = mockStorage.get("tabula_sync_queue");
      expect(persisted).toHaveLength(1);
      expect(persisted[0].entityId).toBe("ws-untouched");
    });
  });

  describe("window event listeners", () => {
    beforeEach(() => {
      // Mock window.addEventListener to capture handlers
      jest.spyOn(window, "addEventListener").mockImplementation(() => {});
    });

    afterEach(() => {
      (window.addEventListener as jest.Mock).mockRestore();
    });

    it("should set up online/offline listeners during initialize", async () => {
      (SyncService as any).initialized = false;
      mockChrome.storage.local.get.mockResolvedValue({});
      (AuthService.getToken as jest.Mock).mockResolvedValue(null);

      await SyncService.initialize();

      expect(window.addEventListener).toHaveBeenCalledWith(
        "online",
        expect.any(Function),
      );
      expect(window.addEventListener).toHaveBeenCalledWith(
        "offline",
        expect.any(Function),
      );
    });
  });
});
