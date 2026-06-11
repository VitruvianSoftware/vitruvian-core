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
 * Unit tests for Window Ownership Service
 */

import {
  WindowOwnershipService,
  WindowOwnershipRecord,
} from "./windowOwnership";
import { crossWindowSync } from "./CrossWindowSyncService";

jest.mock("./CrossWindowSyncService", () => ({
  crossWindowSync: {
    broadcastClaim: jest.fn(),
    broadcastRelease: jest.fn(),
    broadcastPing: jest.fn(),
    broadcastPong: jest.fn(),
    subscribe: jest.fn(() => () => {}),
  },
}));

// Mock chrome APIs at module level
const mockStorage: { tabula_window_ownership?: WindowOwnershipRecord[] } = {};
const mockChromeStorage = {
  get: jest.fn((key: string) =>
    Promise.resolve({ [key]: mockStorage[key as keyof typeof mockStorage] }),
  ),
  set: jest.fn((data: Record<string, unknown>) => {
    Object.assign(mockStorage, data);
    return Promise.resolve();
  }),
  remove: jest.fn((key: string) => {
    delete mockStorage[key as keyof typeof mockStorage];
    return Promise.resolve();
  }),
};

const mockWindows: Map<number, { id: number }> = new Map();
const mockChromeWindows = {
  get: jest.fn((windowId: number) => {
    if (mockWindows.has(windowId)) {
      return Promise.resolve(mockWindows.get(windowId));
    }
    return Promise.reject(new Error("Window not found"));
  }),
  update: jest.fn(() => Promise.resolve({})),
};

const mockTabs: chrome.tabs.Tab[] = [];
const mockChromeTabs = {
  query: jest.fn(() => Promise.resolve(mockTabs)),
  update: jest.fn(() => Promise.resolve({})),
  move: jest.fn(() => Promise.resolve([])),
};

// Install chrome mock globally
Object.assign(globalThis, {
  chrome: {
    storage: { local: mockChromeStorage },
    windows: mockChromeWindows,
    tabs: mockChromeTabs,
  },
});

describe("WindowOwnershipService", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // Clear mock storage
    delete mockStorage.tabula_window_ownership;
    mockWindows.clear();
    mockTabs.length = 0;
  });

  describe("getWindowOwnership", () => {
    it("should return empty array when no ownership records exist", async () => {
      const result = await WindowOwnershipService.getWindowOwnership();
      expect(result).toEqual([]);
    });

    it("should return existing ownership records", async () => {
      const records: WindowOwnershipRecord[] = [
        { workspaceId: "ws1", windowId: 1, tabId: 100, lastActive: Date.now() },
      ];
      mockStorage.tabula_window_ownership = records;

      const result = await WindowOwnershipService.getWindowOwnership();
      expect(result).toEqual(records);
    });
  });

  describe("getWorkspaceOwner", () => {
    it("should return null when workspace has no owner", async () => {
      const result = await WindowOwnershipService.getWorkspaceOwner("ws1");
      expect(result).toBeNull();
    });

    it("should return owner record when workspace is owned", async () => {
      const record: WindowOwnershipRecord = {
        workspaceId: "ws1",
        windowId: 1,
        tabId: 100,
        lastActive: Date.now(),
      };
      mockStorage.tabula_window_ownership = [record];

      const result = await WindowOwnershipService.getWorkspaceOwner("ws1");
      expect(result).toEqual(record);
    });
  });

  describe("isWorkspaceOwnedByOtherWindow", () => {
    it("should return null when workspace has no owner", async () => {
      const result = await WindowOwnershipService.isWorkspaceOwnedByOtherWindow(
        "ws1",
        1,
      );
      expect(result).toBeNull();
    });

    it("should return null when current window owns the workspace", async () => {
      const record: WindowOwnershipRecord = {
        workspaceId: "ws1",
        windowId: 1,
        tabId: 100,
        lastActive: Date.now(),
      };
      mockStorage.tabula_window_ownership = [record];

      const result = await WindowOwnershipService.isWorkspaceOwnedByOtherWindow(
        "ws1",
        1,
      );
      expect(result).toBeNull();
    });

    it("should return owner record when different window owns workspace", async () => {
      const record: WindowOwnershipRecord = {
        workspaceId: "ws1",
        windowId: 2,
        tabId: 200,
        lastActive: Date.now(),
      };
      mockStorage.tabula_window_ownership = [record];
      mockWindows.set(2, { id: 2 });

      const result = await WindowOwnershipService.isWorkspaceOwnedByOtherWindow(
        "ws1",
        1,
      );
      expect(result).toEqual(record);
    });

    it("should clean up stale ownership when owner window no longer exists", async () => {
      const record: WindowOwnershipRecord = {
        workspaceId: "ws1",
        windowId: 999, // Window doesn't exist
        tabId: 100,
        lastActive: Date.now(),
      };
      mockStorage.tabula_window_ownership = [record];

      const result = await WindowOwnershipService.isWorkspaceOwnedByOtherWindow(
        "ws1",
        1,
      );
      expect(result).toBeNull();
      expect(mockChromeStorage.set).toHaveBeenCalledWith({
        tabula_window_ownership: [],
      });
    });
  });

  describe("registerWorkspaceOwnership", () => {
    it("should register new ownership", async () => {
      await WindowOwnershipService.registerWorkspaceOwnership("ws1", 1, 100);

      expect(mockChromeStorage.set).toHaveBeenCalled();
      const setCall = mockChromeStorage.set.mock.calls[0][0] as {
        tabula_window_ownership: WindowOwnershipRecord[];
      };
      expect(setCall.tabula_window_ownership).toHaveLength(1);
      expect(setCall.tabula_window_ownership[0]).toMatchObject({
        workspaceId: "ws1",
        windowId: 1,
        tabId: 100,
      });
    });

    it("should replace existing ownership for same workspace", async () => {
      const existingRecord: WindowOwnershipRecord = {
        workspaceId: "ws1",
        windowId: 2,
        tabId: 200,
        lastActive: Date.now() - 1000,
      };
      mockStorage.tabula_window_ownership = [existingRecord];

      await WindowOwnershipService.registerWorkspaceOwnership("ws1", 1, 100);

      const setCall = mockChromeStorage.set.mock.calls[0][0] as {
        tabula_window_ownership: WindowOwnershipRecord[];
      };
      expect(setCall.tabula_window_ownership).toHaveLength(1);
      expect(setCall.tabula_window_ownership[0].windowId).toBe(1);
    });
  });

  describe("clearWorkspaceOwnership", () => {
    it("should remove ownership for specific workspace", async () => {
      const records: WindowOwnershipRecord[] = [
        { workspaceId: "ws1", windowId: 1, tabId: 100, lastActive: Date.now() },
        { workspaceId: "ws2", windowId: 2, tabId: 200, lastActive: Date.now() },
      ];
      mockStorage.tabula_window_ownership = records;

      await WindowOwnershipService.clearWorkspaceOwnership("ws1");

      const setCall = mockChromeStorage.set.mock.calls[0][0] as {
        tabula_window_ownership: WindowOwnershipRecord[];
      };
      expect(setCall.tabula_window_ownership).toHaveLength(1);
      expect(setCall.tabula_window_ownership[0].workspaceId).toBe("ws2");
    });
  });

  describe("clearWindowOwnership", () => {
    it("should remove all ownership for specific window", async () => {
      const records: WindowOwnershipRecord[] = [
        { workspaceId: "ws1", windowId: 1, tabId: 100, lastActive: Date.now() },
        { workspaceId: "ws2", windowId: 1, tabId: 101, lastActive: Date.now() },
        { workspaceId: "ws3", windowId: 2, tabId: 200, lastActive: Date.now() },
      ];
      mockStorage.tabula_window_ownership = records;

      await WindowOwnershipService.clearWindowOwnership(1);

      const setCall = mockChromeStorage.set.mock.calls[0][0] as {
        tabula_window_ownership: WindowOwnershipRecord[];
      };
      expect(setCall.tabula_window_ownership).toHaveLength(1);
      expect(setCall.tabula_window_ownership[0].workspaceId).toBe("ws3");
    });
  });

  describe("updateOwnershipActivity", () => {
    it("should update lastActive timestamp", async () => {
      const oldTimestamp = Date.now() - 10000;
      const record: WindowOwnershipRecord = {
        workspaceId: "ws1",
        windowId: 1,
        tabId: 100,
        lastActive: oldTimestamp,
      };
      mockStorage.tabula_window_ownership = [record];

      await WindowOwnershipService.updateOwnershipActivity("ws1");

      const setCall = mockChromeStorage.set.mock.calls[0][0] as {
        tabula_window_ownership: WindowOwnershipRecord[];
      };
      expect(setCall.tabula_window_ownership[0].lastActive).toBeGreaterThan(
        oldTimestamp,
      );
    });

    it("should do nothing if workspace not found", async () => {
      mockStorage.tabula_window_ownership = [];

      await WindowOwnershipService.updateOwnershipActivity("ws1");

      expect(mockChromeStorage.set).not.toHaveBeenCalled();
    });
  });

  describe("tryClaimWorkspace (atomic check-and-claim)", () => {
    it("claims an unowned workspace and broadcasts the claim", async () => {
      const result = await WindowOwnershipService.tryClaimWorkspace(
        "ws1",
        1,
        100,
      );

      expect(result).toEqual({ claimed: true });
      expect(mockStorage.tabula_window_ownership).toHaveLength(1);
      expect(mockStorage.tabula_window_ownership![0]).toMatchObject({
        workspaceId: "ws1",
        windowId: 1,
        tabId: 100,
      });
      expect(crossWindowSync.broadcastClaim).toHaveBeenCalledWith(
        "ws1",
        1,
        100,
      );
    });

    it("rejects the claim when a LIVE window owns the workspace", async () => {
      const owner: WindowOwnershipRecord = {
        workspaceId: "ws1",
        windowId: 2,
        tabId: 200,
        lastActive: Date.now(),
      };
      mockStorage.tabula_window_ownership = [owner];
      mockWindows.set(2, { id: 2 });

      const result = await WindowOwnershipService.tryClaimWorkspace(
        "ws1",
        1,
        100,
      );

      expect(result).toEqual({ claimed: false, owner });
      // Record untouched, no claim broadcast
      expect(mockStorage.tabula_window_ownership![0].windowId).toBe(2);
      expect(crossWindowSync.broadcastClaim).not.toHaveBeenCalled();
    });

    it("takes over from a DEAD owner window and releases it", async () => {
      const deadOwner: WindowOwnershipRecord = {
        workspaceId: "ws1",
        windowId: 999, // not in mockWindows -> chrome.windows.get rejects
        tabId: 200,
        lastActive: Date.now(),
      };
      mockStorage.tabula_window_ownership = [deadOwner];

      const result = await WindowOwnershipService.tryClaimWorkspace(
        "ws1",
        1,
        100,
      );

      expect(result).toEqual({ claimed: true });
      expect(mockStorage.tabula_window_ownership).toHaveLength(1);
      expect(mockStorage.tabula_window_ownership![0].windowId).toBe(1);
      expect(crossWindowSync.broadcastRelease).toHaveBeenCalledWith("ws1", 999);
    });

    it("releases this window’s previous workspace when claiming a new one", async () => {
      mockStorage.tabula_window_ownership = [
        {
          workspaceId: "ws-old",
          windowId: 1,
          tabId: 100,
          lastActive: Date.now(),
        },
      ];

      const result = await WindowOwnershipService.tryClaimWorkspace(
        "ws-new",
        1,
        100,
      );

      expect(result).toEqual({ claimed: true });
      expect(crossWindowSync.broadcastRelease).toHaveBeenCalledWith(
        "ws-old",
        1,
      );
    });
  });

  describe("clearWorkspaceOwnership with attributed window", () => {
    it("removes only the record held by the released window", async () => {
      // A third window re-claimed ws1 between the dead-check and the clear
      mockStorage.tabula_window_ownership = [
        { workspaceId: "ws1", windowId: 3, tabId: 300, lastActive: Date.now() },
      ];

      await WindowOwnershipService.clearWorkspaceOwnership("ws1", 999);

      // Window 3's fresh claim must survive
      expect(mockStorage.tabula_window_ownership).toHaveLength(1);
      expect(mockStorage.tabula_window_ownership![0].windowId).toBe(3);
    });

    it("broadcasts the release attributed to the dead owner", async () => {
      mockStorage.tabula_window_ownership = [
        {
          workspaceId: "ws1",
          windowId: 999,
          tabId: 100,
          lastActive: Date.now(),
        },
      ];

      await WindowOwnershipService.clearWorkspaceOwnership("ws1", 999);

      expect(mockStorage.tabula_window_ownership).toHaveLength(0);
      expect(crossWindowSync.broadcastRelease).toHaveBeenCalledWith("ws1", 999);
    });
  });

  describe("clearWindowOwnership broadcasts", () => {
    it("broadcasts a release for each workspace the closed window held", async () => {
      mockStorage.tabula_window_ownership = [
        { workspaceId: "ws1", windowId: 1, tabId: 100, lastActive: Date.now() },
        { workspaceId: "ws2", windowId: 1, tabId: 101, lastActive: Date.now() },
        { workspaceId: "ws3", windowId: 2, tabId: 200, lastActive: Date.now() },
      ];

      await WindowOwnershipService.clearWindowOwnership(1);

      expect(crossWindowSync.broadcastRelease).toHaveBeenCalledWith("ws1", 1);
      expect(crossWindowSync.broadcastRelease).toHaveBeenCalledWith("ws2", 1);
      expect(crossWindowSync.broadcastRelease).not.toHaveBeenCalledWith(
        "ws3",
        expect.anything(),
      );
    });
  });

  describe("clearAllWindowOwnership", () => {
    it("wipes the ownership storage key", async () => {
      mockStorage.tabula_window_ownership = [
        { workspaceId: "ws1", windowId: 1, tabId: 100, lastActive: Date.now() },
      ];

      await WindowOwnershipService.clearAllWindowOwnership();

      expect(mockChromeStorage.remove).toHaveBeenCalledWith(
        "tabula_window_ownership",
      );
    });
  });

  describe("getOwnerWindowTabs", () => {
    it("should return tabs from owner window excluding dashboard tab", async () => {
      const ownerRecord: WindowOwnershipRecord = {
        workspaceId: "ws1",
        windowId: 1,
        tabId: 100,
        lastActive: Date.now(),
      };
      mockTabs.push(
        { id: 100, windowId: 1, url: "dashboard.html" } as chrome.tabs.Tab,
        { id: 101, windowId: 1, url: "https://example.com" } as chrome.tabs.Tab,
        { id: 102, windowId: 1, url: "https://google.com" } as chrome.tabs.Tab,
      );

      const result =
        await WindowOwnershipService.getOwnerWindowTabs(ownerRecord);

      expect(result).toHaveLength(2);
      expect(result.map((t) => t.id)).toEqual([101, 102]);
    });

    it("should return empty array on error", async () => {
      const ownerRecord: WindowOwnershipRecord = {
        workspaceId: "ws1",
        windowId: 999,
        tabId: 100,
        lastActive: Date.now(),
      };
      mockChromeTabs.query.mockRejectedValueOnce(new Error("Window not found"));

      const result =
        await WindowOwnershipService.getOwnerWindowTabs(ownerRecord);

      expect(result).toEqual([]);
    });
  });

  describe("focusOwnerWindow", () => {
    it("should focus owner window and tab", async () => {
      const ownerRecord: WindowOwnershipRecord = {
        workspaceId: "ws1",
        windowId: 1,
        tabId: 100,
        lastActive: Date.now(),
      };

      await WindowOwnershipService.focusOwnerWindow(ownerRecord);

      expect(mockChromeWindows.update).toHaveBeenCalledWith(1, {
        focused: true,
      });
      expect(mockChromeTabs.update).toHaveBeenCalledWith(100, { active: true });
    });
  });

  describe("moveTabsToCurrentWindow", () => {
    it("should move tabs to current window", async () => {
      await WindowOwnershipService.moveTabsToCurrentWindow([101, 102], 2);

      expect(mockChromeTabs.move).toHaveBeenCalledWith([101, 102], {
        windowId: 2,
        index: -1,
      });
    });

    it("should do nothing when no tabs provided", async () => {
      await WindowOwnershipService.moveTabsToCurrentWindow([], 2);

      expect(mockChromeTabs.move).not.toHaveBeenCalled();
    });
  });
});
