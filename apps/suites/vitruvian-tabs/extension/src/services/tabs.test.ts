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
 * Unit tests for TabService
 */
import { TabService } from "./tabs";

// Mock chrome API
const mockChrome = {
  tabs: {
    query: jest.fn(),
    create: jest.fn(),
    remove: jest.fn(),
    discard: jest.fn(),
    update: jest.fn(),
    move: jest.fn(),
    get: jest.fn(),
    duplicate: jest.fn(),
    group: jest.fn(),
    ungroup: jest.fn(),
  },
  windows: {
    create: jest.fn(),
    update: jest.fn(),
    getAll: jest.fn(),
    getCurrent: jest.fn(),
  },
  tabGroups: {
    query: jest.fn(),
    update: jest.fn(),
  },
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
(globalThis as any).chrome = mockChrome;

describe("TabService", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("getCurrentTabs", () => {
    it("should return current window tabs", async () => {
      const mockTabs = [
        {
          id: 1,
          url: "https://example.com",
          title: "Example",
          pinned: false,
          active: true,
          index: 0,
        },
        {
          id: 2,
          url: "https://test.com",
          title: "Test",
          pinned: true,
          active: false,
          index: 1,
        },
      ];
      mockChrome.tabs.query.mockResolvedValue(mockTabs);

      const result = await TabService.getCurrentTabs();

      expect(mockChrome.tabs.query).toHaveBeenCalledWith({
        currentWindow: true,
      });
      expect(result).toHaveLength(2);
      expect(result[0].url).toBe("https://example.com");
    });

    it("should handle tabs with pendingUrl", async () => {
      const mockTabs = [
        {
          id: 1,
          pendingUrl: "https://loading.com",
          title: "Loading",
          pinned: false,
          index: 0,
        },
      ];
      mockChrome.tabs.query.mockResolvedValue(mockTabs);

      const result = await TabService.getCurrentTabs();

      expect(result[0].url).toBe("https://loading.com");
    });

    it("should return empty array on error", async () => {
      mockChrome.tabs.query.mockRejectedValue(new Error("API error"));

      const result = await TabService.getCurrentTabs();

      expect(result).toEqual([]);
    });
  });

  describe("openTabs", () => {
    it("should open tabs in current window", async () => {
      const tabs = [
        { url: "https://example.com", title: "Example", pinned: false },
        { url: "https://test.com", title: "Test", pinned: true },
      ];
      mockChrome.tabs.create.mockResolvedValue({});

      await TabService.openTabs(tabs);

      expect(mockChrome.tabs.create).toHaveBeenCalledTimes(2);
    });

    it("should open tabs in new window", async () => {
      const tabs = [
        { url: "https://example.com", title: "Example", pinned: false },
        { url: "https://test.com", title: "Test", pinned: true },
      ];
      mockChrome.windows.create.mockResolvedValue({ id: 123 });
      mockChrome.tabs.create.mockResolvedValue({});

      await TabService.openTabs(tabs, { inNewWindow: true });

      expect(mockChrome.windows.create).toHaveBeenCalledWith({
        url: "https://example.com",
        focused: true,
      });
      expect(mockChrome.tabs.create).toHaveBeenCalledTimes(1);
    });

    it("should handle empty tabs array", async () => {
      await TabService.openTabs([], { inNewWindow: true });

      expect(mockChrome.windows.create).not.toHaveBeenCalled();
    });

    it("should handle tab creation errors gracefully", async () => {
      const tabs = [
        { url: "https://example.com", title: "Example", pinned: false },
      ];
      mockChrome.tabs.create.mockRejectedValue(new Error("Tab error"));

      // Should not throw
      await expect(TabService.openTabs(tabs)).resolves.not.toThrow();
    });
  });

  describe("closeAllTabs", () => {
    it("should close non-pinned tabs", async () => {
      const mockTabs = [
        { id: 1, url: "https://example.com", pinned: false },
        { id: 2, url: "https://test.com", pinned: true },
      ];
      mockChrome.tabs.query.mockResolvedValue(mockTabs);
      mockChrome.tabs.remove.mockResolvedValue(undefined);

      await TabService.closeAllTabs();

      expect(mockChrome.tabs.remove).toHaveBeenCalledWith([1]);
    });

    it("should close pinned tabs when includePinned is true", async () => {
      const mockTabs = [
        { id: 1, url: "https://example.com", pinned: false },
        { id: 2, url: "https://test.com", pinned: true },
      ];
      mockChrome.tabs.query.mockResolvedValue(mockTabs);
      mockChrome.tabs.remove.mockResolvedValue(undefined);

      await TabService.closeAllTabs(true);

      expect(mockChrome.tabs.remove).toHaveBeenCalledWith([1, 2]);
    });

    it("should not close extension pages", async () => {
      const mockTabs = [
        { id: 1, url: "chrome-extension://abc/dashboard.html", pinned: false },
        { id: 2, url: "https://test.com", pinned: false },
      ];
      mockChrome.tabs.query.mockResolvedValue(mockTabs);
      mockChrome.tabs.remove.mockResolvedValue(undefined);

      await TabService.closeAllTabs();

      expect(mockChrome.tabs.remove).toHaveBeenCalledWith([2]);
    });

    it("should NOT throw on error", async () => {
      mockChrome.tabs.query.mockRejectedValue(new Error("API error"));

      await expect(TabService.closeAllTabs()).resolves.not.toThrow();
    });
  });

  describe("suspendTab", () => {
    it("should discard a tab", async () => {
      mockChrome.tabs.discard.mockResolvedValue(undefined);

      await TabService.suspendTab(123);

      expect(mockChrome.tabs.discard).toHaveBeenCalledWith(123);
    });

    it("should throw on error", async () => {
      mockChrome.tabs.discard.mockRejectedValue(new Error("Discard failed"));

      await expect(TabService.suspendTab(123)).rejects.toThrow(
        "Discard failed",
      );
    });
  });

  describe("suspendInactiveTabs", () => {
    it("should suspend non-active, non-pinned tabs", async () => {
      const mockTabs = [
        { id: 1, discarded: false },
        { id: 2, discarded: true },
      ];
      mockChrome.tabs.query.mockResolvedValue(mockTabs);
      mockChrome.tabs.discard.mockResolvedValue(undefined);

      await TabService.suspendInactiveTabs();

      expect(mockChrome.tabs.query).toHaveBeenCalledWith({
        currentWindow: true,
        pinned: false,
        active: false,
      });
      expect(mockChrome.tabs.discard).toHaveBeenCalledTimes(1);
      expect(mockChrome.tabs.discard).toHaveBeenCalledWith(1);
    });
  });

  describe("getMemoryStats", () => {
    it("should return memory statistics", async () => {
      const mockTabs = [
        { id: 1, discarded: true },
        { id: 2, discarded: false },
        { id: 3, discarded: false },
      ];
      mockChrome.tabs.query.mockResolvedValue(mockTabs);

      const result = await TabService.getMemoryStats();

      expect(result).toEqual({
        totalTabs: 3,
        suspendedTabs: 1,
        activeTabs: 2,
      });
    });

    it("should return zeros on error", async () => {
      mockChrome.tabs.query.mockRejectedValue(new Error("API error"));

      const result = await TabService.getMemoryStats();

      expect(result).toEqual({
        totalTabs: 0,
        suspendedTabs: 0,
        activeTabs: 0,
      });
    });
  });

  describe("closeTabs", () => {
    it("should close specific tabs by IDs", async () => {
      mockChrome.tabs.remove.mockResolvedValue(undefined);

      await TabService.closeTabs([1, 2, 3]);

      expect(mockChrome.tabs.remove).toHaveBeenCalledWith([1, 2, 3]);
    });

    it("should not call remove for empty array", async () => {
      await TabService.closeTabs([]);

      expect(mockChrome.tabs.remove).not.toHaveBeenCalled();
    });
  });

  describe("suspendTabs", () => {
    it("should suspend multiple tabs", async () => {
      mockChrome.tabs.discard.mockResolvedValue(undefined);

      await TabService.suspendTabs([1, 2]);

      expect(mockChrome.tabs.discard).toHaveBeenCalledTimes(2);
    });
  });

  describe("setPinned", () => {
    it("should pin tabs", async () => {
      mockChrome.tabs.update.mockResolvedValue({});

      await TabService.setPinned([1, 2], true);

      expect(mockChrome.tabs.update).toHaveBeenCalledWith(1, { pinned: true });
      expect(mockChrome.tabs.update).toHaveBeenCalledWith(2, { pinned: true });
    });
  });

  describe("moveTab", () => {
    it("should move a tab to new index", async () => {
      mockChrome.tabs.move.mockResolvedValue({});

      await TabService.moveTab(123, 5);

      expect(mockChrome.tabs.move).toHaveBeenCalledWith(123, { index: 5 });
    });

    it("should NOT throw on error", async () => {
      mockChrome.tabs.move.mockRejectedValue(new Error("Move failed"));

      await expect(TabService.moveTab(123, 5)).resolves.not.toThrow();
    });

    it("should handle invalid input gracefully", async () => {
      // Should not throw and not call chrome.tabs.move
      // @ts-expect-error - Testing invalid input
      await TabService.moveTab(undefined, 5);
      expect(mockChrome.tabs.move).not.toHaveBeenCalled();
    });

    it("should catch validation errors", async () => {
      mockChrome.tabs.move.mockRejectedValue(new Error("Invalid tab"));

      // Should not throw
      await expect(TabService.moveTab(123, 99)).resolves.not.toThrow();
    });
  });

  describe("getTab", () => {
    it("should get a tab by ID", async () => {
      mockChrome.tabs.get.mockResolvedValue({
        id: 123,
        url: "https://example.com",
        title: "Example",
        pinned: false,
        index: 0,
      });

      const result = await TabService.getTab(123);

      expect(result).toEqual({
        id: 123,
        url: "https://example.com",
        title: "Example",
        favIconUrl: undefined,
        pinned: false,
        index: 0,
      });
    });

    it("should return null on error", async () => {
      mockChrome.tabs.get.mockRejectedValue(new Error("Tab not found"));

      const result = await TabService.getTab(999);

      expect(result).toBeNull();
    });
  });

  describe("duplicateTab", () => {
    it("should duplicate a tab", async () => {
      mockChrome.tabs.duplicate.mockResolvedValue({
        id: 456,
        url: "https://example.com",
        title: "Example",
        pinned: false,
        index: 1,
      });

      const result = await TabService.duplicateTab(123);

      expect(result).toEqual({
        id: 456,
        url: "https://example.com",
        title: "Example",
        favIconUrl: undefined,
        pinned: false,
        index: 1,
      });
    });

    it("should return null on error", async () => {
      mockChrome.tabs.duplicate.mockRejectedValue(new Error("Failed"));

      const result = await TabService.duplicateTab(123);

      expect(result).toBeNull();
    });
  });

  describe("activateTab", () => {
    it("should activate and focus a tab", async () => {
      mockChrome.tabs.update.mockResolvedValue({});
      mockChrome.tabs.get.mockResolvedValue({ windowId: 789 });
      mockChrome.windows.update.mockResolvedValue({});

      await TabService.activateTab(123);

      expect(mockChrome.tabs.update).toHaveBeenCalledWith(123, {
        active: true,
      });
      expect(mockChrome.windows.update).toHaveBeenCalledWith(789, {
        focused: true,
      });
    });

    it("should throw error on failure", async () => {
      mockChrome.tabs.update.mockRejectedValue(
        new Error("Tab activation failed"),
      );

      await expect(TabService.activateTab(123)).rejects.toThrow(
        "Tab activation failed",
      );
    });

    it("should handle tab without windowId", async () => {
      mockChrome.tabs.update.mockResolvedValue({});
      mockChrome.tabs.get.mockResolvedValue({ id: 123 }); // No windowId

      await TabService.activateTab(123);

      expect(mockChrome.tabs.update).toHaveBeenCalledWith(123, {
        active: true,
      });
      expect(mockChrome.windows.update).not.toHaveBeenCalled();
    });
  });

  describe("closeTabs - additional cases", () => {
    it("should handle string tab IDs", async () => {
      mockChrome.tabs.remove.mockResolvedValue(undefined);

      await TabService.closeTabs(["1", "2", 3]);

      expect(mockChrome.tabs.remove).toHaveBeenCalledWith([1, 2, 3]);
    });

    it("should filter out NaN values from string parsing", async () => {
      mockChrome.tabs.remove.mockResolvedValue(undefined);

      await TabService.closeTabs(["abc", "123", 456]);

      expect(mockChrome.tabs.remove).toHaveBeenCalledWith([123, 456]);
    });

    it("should NOT throw on error", async () => {
      mockChrome.tabs.remove.mockRejectedValue(new Error("Remove failed"));

      await expect(TabService.closeTabs([1, 2])).resolves.not.toThrow();
    });
  });

  describe("getCurrentTabs - title fallbacks", () => {
    it("should use hostname as title when title is Untitled", async () => {
      const mockTabs = [
        {
          id: 1,
          url: "https://example.com/path",
          title: "Untitled",
          pinned: false,
          index: 0,
        },
      ];
      mockChrome.tabs.query.mockResolvedValue(mockTabs);

      const result = await TabService.getCurrentTabs();

      expect(result[0].title).toBe("example.com");
    });

    it("should use hostname when title is empty", async () => {
      const mockTabs = [
        { id: 1, url: "https://test.com", title: "", pinned: false, index: 0 },
      ];
      mockChrome.tabs.query.mockResolvedValue(mockTabs);

      const result = await TabService.getCurrentTabs();

      expect(result[0].title).toBe("test.com");
    });

    it("should use Untitled when URL is invalid", async () => {
      const mockTabs = [
        { id: 1, url: "invalid-url", title: "", pinned: false, index: 0 },
      ];
      mockChrome.tabs.query.mockResolvedValue(mockTabs);

      const result = await TabService.getCurrentTabs();

      expect(result[0].title).toBe("Untitled");
    });

    it("should use Untitled when no URL", async () => {
      const mockTabs = [{ id: 1, title: "", pinned: false, index: 0 }];
      mockChrome.tabs.query.mockResolvedValue(mockTabs);

      const result = await TabService.getCurrentTabs();

      expect(result[0].title).toBe("Untitled");
    });
  });

  describe("openTabs - additional cases", () => {
    it("should handle tab creation error in new window", async () => {
      const tabs = [
        { url: "https://example.com", title: "Example", pinned: false },
        { url: "https://error-tab.com", title: "Error", pinned: false },
      ];
      mockChrome.windows.create.mockResolvedValue({ id: 123 });
      mockChrome.tabs.create.mockRejectedValue(new Error("Tab error"));

      // Should not throw
      await expect(
        TabService.openTabs(tabs, { inNewWindow: true }),
      ).resolves.not.toThrow();
    });
  });

  describe("getTab - additional cases", () => {
    it("should handle string tab ID", async () => {
      mockChrome.tabs.get.mockResolvedValue({
        id: 123,
        url: "https://example.com",
        title: "Example",
        pinned: false,
        index: 0,
      });

      const result = await TabService.getTab("123");

      expect(result?.id).toBe(123);
    });

    it("should return null for NaN string ID", async () => {
      const result = await TabService.getTab("not-a-number");

      expect(result).toBeNull();
    });
  });

  describe("moveTab - string ID handling", () => {
    it("should handle string tab ID", async () => {
      mockChrome.tabs.move.mockResolvedValue({});

      await TabService.moveTab("123", 5);

      expect(mockChrome.tabs.move).toHaveBeenCalledWith(123, { index: 5 });
    });

    it("should not move if newIndex is not a number", async () => {
      // @ts-expect-error - Testing invalid input
      await TabService.moveTab(123, undefined);

      expect(mockChrome.tabs.move).not.toHaveBeenCalled();
    });

    it("should not move if tabId string is NaN", async () => {
      await TabService.moveTab("not-a-number", 5);

      expect(mockChrome.tabs.move).not.toHaveBeenCalled();
    });
  });

  describe("duplicateTab - additional cases", () => {
    it("should return null if duplicate returns undefined", async () => {
      mockChrome.tabs.duplicate.mockResolvedValue(undefined);

      const result = await TabService.duplicateTab(123);

      expect(result).toBeNull();
    });
  });
  describe("getCurrentTabGroups", () => {
    it("should return tab groups from active window with stable UUIDs", async () => {
      mockChrome.windows.getCurrent.mockResolvedValue({ id: 123 });
      mockChrome.tabGroups.query.mockResolvedValue([
        { id: 1, title: "Group 1", color: "blue", collapsed: false },
        { id: 2, title: "Group 2", color: "red", collapsed: true },
      ]);

      const result = await TabService.getCurrentTabGroups();

      expect(mockChrome.windows.getCurrent).toHaveBeenCalled();
      expect(mockChrome.tabGroups.query).toHaveBeenCalledWith({
        windowId: 123,
      });
      expect(result).toHaveLength(2);

      // Verify structure has stable UUID and chromeGroupId
      expect(result[0].id).toMatch(/^tg_\d+_[a-z0-9]+$/); // Stable UUID format
      expect(result[0].chromeGroupId).toBe(1);
      expect(result[0].title).toBe("Group 1");
      expect(result[0].color).toBe("blue");
      expect(result[0].collapsed).toBe(false);

      expect(result[1].chromeGroupId).toBe(2);
      expect(result[1].title).toBe("Group 2");
    });

    it("should return empty array if no active window", async () => {
      mockChrome.windows.getCurrent.mockResolvedValue(null);

      const result = await TabService.getCurrentTabGroups();

      expect(result).toEqual([]);
      expect(mockChrome.tabGroups.query).not.toHaveBeenCalled();
    });

    it("should handle API errors gracefully", async () => {
      mockChrome.windows.getCurrent.mockRejectedValue(new Error("API Error"));

      const result = await TabService.getCurrentTabGroups();

      expect(result).toEqual([]);
    });
  });

  // Issue #47: readiness probe used by useTabSync to replace the blind 500ms
  // startup delay. Ready == Chrome's tabs.query() and tabGroups.query() agree.
  describe("areTabGroupsConsistent", () => {
    it("is consistent when there are no groups (nothing to wait for)", async () => {
      mockChrome.windows.getCurrent.mockResolvedValue({ id: 123 });
      mockChrome.tabGroups.query.mockResolvedValue([]);
      mockChrome.tabs.query.mockResolvedValue([
        { id: 1, url: "https://a.com", groupId: -1 },
      ]);

      await expect(TabService.areTabGroupsConsistent()).resolves.toBe(true);
    });

    it("is NOT consistent when groups exist but no tab has a groupId yet", async () => {
      // The transient post-soft-refresh window: groups reported, tabs still -1.
      mockChrome.windows.getCurrent.mockResolvedValue({ id: 123 });
      mockChrome.tabGroups.query.mockResolvedValue([
        { id: 1, title: "G", color: "blue", collapsed: false },
      ]);
      mockChrome.tabs.query.mockResolvedValue([
        { id: 1, url: "https://a.com", groupId: -1 },
        { id: 2, url: "https://b.com", groupId: -1 },
      ]);

      await expect(TabService.areTabGroupsConsistent()).resolves.toBe(false);
    });

    it("is consistent once a grouped tab reports a real groupId", async () => {
      mockChrome.windows.getCurrent.mockResolvedValue({ id: 123 });
      mockChrome.tabGroups.query.mockResolvedValue([
        { id: 1, title: "G", color: "blue", collapsed: false },
      ]);
      mockChrome.tabs.query.mockResolvedValue([
        { id: 1, url: "https://a.com", groupId: 1 },
        { id: 2, url: "https://b.com", groupId: -1 },
      ]);

      await expect(TabService.areTabGroupsConsistent()).resolves.toBe(true);
    });

    it("fails open (true) on query error so startup never wedges", async () => {
      mockChrome.windows.getCurrent.mockRejectedValue(new Error("API Error"));

      await expect(TabService.areTabGroupsConsistent()).resolves.toBe(true);
    });
  });

  describe("restoreTabGroups", () => {
    // Use stable UUIDs instead of numbers for group IDs
    const savedTabs = [
      {
        id: "t1",
        url: "https://a.com",
        title: "A",
        pinned: false,
        groupId: "tg_001",
      },
      {
        id: "t2",
        url: "https://b.com",
        title: "B",
        pinned: false,
        groupId: "tg_001",
      },
      {
        id: "t3",
        url: "https://c.com",
        title: "C",
        pinned: false,
        groupId: "tg_002",
      },
    ] as any[];

    const savedGroups = [
      {
        id: "tg_001",
        chromeGroupId: 1,
        title: "Project A",
        color: "blue",
        collapsed: false,
      },
      {
        id: "tg_002",
        chromeGroupId: 2,
        title: "Project B",
        color: "red",
        collapsed: true,
      },
    ] as any[];

    const newTabs = [
      { id: 101, url: "https://a.com" },
      { id: 102, url: "https://b.com" },
      { id: 103, url: "https://c.com" },
    ] as any[];

    it("should restore groups based on position matching", async () => {
      // Mock group creation
      mockChrome.tabs.group
        .mockResolvedValueOnce(1001) // First group
        .mockResolvedValueOnce(1002); // Second group

      mockChrome.tabGroups.update.mockResolvedValue({});

      await TabService.restoreTabGroups(savedTabs, savedGroups, newTabs);

      // Verify groups were created
      expect(mockChrome.tabs.group).toHaveBeenCalledTimes(2);

      // First group should contain tabs 101 and 102 (indices 0 and 1)
      expect(mockChrome.tabs.group).toHaveBeenCalledWith({
        tabIds: [101, 102],
      });
      expect(mockChrome.tabGroups.update).toHaveBeenCalledWith(1001, {
        title: "Project A",
        color: "blue",
        collapsed: false,
      });

      // Second group should contain tab 103 (index 2)
      expect(mockChrome.tabs.group).toHaveBeenCalledWith({ tabIds: [103] });
      expect(mockChrome.tabGroups.update).toHaveBeenCalledWith(1002, {
        title: "Project B",
        color: "red",
        collapsed: true,
      });
    });

    it("should ignore non-grouped tabs", async () => {
      // Helper defined here to avoid scope issues
      const passedGroups = [
        {
          id: "tg_g1",
          chromeGroupId: 1,
          title: "G1",
          color: "blue",
          collapsed: false,
        },
      ] as any[];

      const mixedSavedTabs = [
        { url: "https://a.com", groupId: "tg_g1" },
        { url: "https://unguided.com" }, // No groupId
      ] as any[];
      const mixedNewTabs = [{ id: 101 }, { id: 102 }] as any[];

      mockChrome.tabs.group.mockResolvedValue(1001);

      await TabService.restoreTabGroups(
        mixedSavedTabs,
        passedGroups,
        mixedNewTabs,
      );

      // Should only group the first tab
      expect(mockChrome.tabs.group).toHaveBeenCalledWith({ tabIds: [101] });
    });

    it("should handle missing metadata gracefully", async () => {
      const tabs = [
        { url: "https://a.com", groupId: "tg_nonexistent" },
      ] as any[]; // groupId doesn't exist in groups
      const groups = [] as any[];
      const nTabs = [{ id: 101 }] as any[];

      await TabService.restoreTabGroups(tabs, groups, nTabs);

      expect(mockChrome.tabs.group).not.toHaveBeenCalled();
    });

    it("should filter out extension and pinned tabs from newTabs before matching", async () => {
      const sTabs = [{ url: "https://a.com", groupId: "tg_g1" }] as any[];
      const sGroups = [
        {
          id: "tg_g1",
          chromeGroupId: 1,
          title: "G1",
          color: "blue",
          collapsed: false,
        },
      ] as any[];

      const nTabsWithExtras = [
        { id: 900, url: "chrome-extension://dashboard", pinned: false }, // Should be ignored
        { id: 901, url: "https://pinned.com", pinned: true }, // Should be ignored
        { id: 101, url: "https://a.com", pinned: false }, // Target
      ] as any[];

      mockChrome.tabs.group.mockResolvedValue(1001);

      await TabService.restoreTabGroups(sTabs, sGroups, nTabsWithExtras);

      // Should match index 0 of savedTabs to index 0 of *relevant* newTabs (which is id 101)
      expect(mockChrome.tabs.group).toHaveBeenCalledWith({ tabIds: [101] });
    });

    it("should handle errors gracefully", async () => {
      mockChrome.tabs.group.mockRejectedValue(new Error("Grouping failed"));

      // Should not throw
      await expect(
        TabService.restoreTabGroups(savedTabs, savedGroups, newTabs),
      ).resolves.not.toThrow();
    });
  });

  describe("restoreTabGroupsFromCreated", () => {
    const savedTabs = [
      { id: "t1", url: "https://a.com", groupId: "tg_001" },
      { id: "t2", url: "https://b.com", groupId: "tg_001" },
      { id: "t3", url: "https://c.com", groupId: "tg_002" },
    ] as any[];
    const savedGroups = [
      {
        id: "tg_001",
        chromeGroupId: 1,
        title: "A",
        color: "blue",
        collapsed: false,
      },
      {
        id: "tg_002",
        chromeGroupId: 2,
        title: "B",
        color: "red",
        collapsed: true,
      },
    ] as any[];

    it("matches saved tabs to created tabs by index without re-querying", async () => {
      const created = [{ id: 101 }, { id: 102 }, { id: 103 }] as any[];
      mockChrome.tabs.group
        .mockResolvedValueOnce(1001)
        .mockResolvedValueOnce(1002);
      mockChrome.tabGroups.update.mockResolvedValue({});

      await TabService.restoreTabGroupsFromCreated(
        savedTabs,
        savedGroups,
        created,
      );

      expect(mockChrome.tabs.group).toHaveBeenCalledWith({
        tabIds: [101, 102],
      });
      expect(mockChrome.tabs.group).toHaveBeenCalledWith({ tabIds: [103] });
    });

    it("does NOT drift groups when a tab failed to open (null entry)", async () => {
      // Second tab failed → its slot is null; the third must NOT be pulled into group A
      const created = [{ id: 101 }, null, { id: 103 }] as any[];
      mockChrome.tabs.group
        .mockResolvedValueOnce(1001)
        .mockResolvedValueOnce(1002);
      mockChrome.tabGroups.update.mockResolvedValue({});

      await TabService.restoreTabGroupsFromCreated(
        savedTabs,
        savedGroups,
        created,
      );

      // Group A keeps only the tab that actually opened (101), NOT 103
      expect(mockChrome.tabs.group).toHaveBeenCalledWith({ tabIds: [101] });
      // Group B correctly gets 103 (its own group), proving no index drift
      expect(mockChrome.tabs.group).toHaveBeenCalledWith({ tabIds: [103] });
    });
  });

  describe("moveTabGroup", () => {
    it("should move all tabs in a group and preserve grouping", async () => {
      mockChrome.tabs.get.mockResolvedValue({ id: 1, groupId: 5 });
      mockChrome.tabs.move.mockResolvedValue({});
      mockChrome.tabs.group.mockResolvedValue(5);

      await TabService.moveTabGroup([1, 2, 3], 10);

      expect(mockChrome.tabs.move).toHaveBeenCalledWith([1, 2, 3], {
        index: 10,
      });
      expect(mockChrome.tabs.group).toHaveBeenCalledWith({
        tabIds: [1, 2, 3],
        groupId: 5,
      });
    });

    it("should not re-group if tabs were not in a group", async () => {
      mockChrome.tabs.get.mockResolvedValue({ id: 1, groupId: -1 });
      mockChrome.tabs.move.mockResolvedValue({});

      await TabService.moveTabGroup([1, 2], 5);

      expect(mockChrome.tabs.move).toHaveBeenCalled();
      expect(mockChrome.tabs.group).not.toHaveBeenCalled();
    });

    it("should not re-group if groupId is zero", async () => {
      mockChrome.tabs.get.mockResolvedValue({ id: 1, groupId: 0 });
      mockChrome.tabs.move.mockResolvedValue({});

      await TabService.moveTabGroup([1], 5);

      expect(mockChrome.tabs.move).toHaveBeenCalled();
      expect(mockChrome.tabs.group).not.toHaveBeenCalled();
    });

    it("should handle empty tabIds array", async () => {
      await TabService.moveTabGroup([], 5);

      expect(mockChrome.tabs.get).not.toHaveBeenCalled();
      expect(mockChrome.tabs.move).not.toHaveBeenCalled();
    });

    it("should handle undefined tabIds", async () => {
      await TabService.moveTabGroup(undefined as any, 5);

      expect(mockChrome.tabs.get).not.toHaveBeenCalled();
    });

    it("should handle invalid newIndex", async () => {
      await TabService.moveTabGroup([1, 2], undefined as any);

      expect(mockChrome.tabs.get).not.toHaveBeenCalled();
    });

    it("should handle errors gracefully", async () => {
      mockChrome.tabs.get.mockRejectedValue(new Error("Tab not found"));

      await expect(TabService.moveTabGroup([1, 2], 5)).resolves.not.toThrow();
    });
  });

  describe("setTabGroupCollapsed", () => {
    it("should update group collapsed state to true", async () => {
      mockChrome.tabGroups.update.mockResolvedValue({});

      await TabService.setTabGroupCollapsed(123, true);

      expect(mockChrome.tabGroups.update).toHaveBeenCalledWith(123, {
        collapsed: true,
      });
    });

    it("should update group collapsed state to false", async () => {
      mockChrome.tabGroups.update.mockResolvedValue({});

      await TabService.setTabGroupCollapsed(456, false);

      expect(mockChrome.tabGroups.update).toHaveBeenCalledWith(456, {
        collapsed: false,
      });
    });

    it("should handle errors gracefully", async () => {
      mockChrome.tabGroups.update.mockRejectedValue(new Error("Update failed"));

      await expect(
        TabService.setTabGroupCollapsed(123, true),
      ).resolves.not.toThrow();
    });
  });

  describe("getCurrentTabs with chromeGroupId mapping", () => {
    it("should map chrome groupId to stable groupId using existingGroups", async () => {
      const existingGroups = [
        {
          id: "tg_stable_001",
          chromeGroupId: 5,
          title: "Group 1",
          color: "blue",
          collapsed: false,
        },
        {
          id: "tg_stable_002",
          chromeGroupId: 10,
          title: "Group 2",
          color: "red",
          collapsed: true,
        },
      ] as any[];

      mockChrome.tabs.query.mockResolvedValue([
        {
          id: 1,
          url: "https://a.com",
          title: "A",
          pinned: false,
          index: 0,
          groupId: 5,
        },
        {
          id: 2,
          url: "https://b.com",
          title: "B",
          pinned: false,
          index: 1,
          groupId: 10,
        },
        {
          id: 3,
          url: "https://c.com",
          title: "C",
          pinned: false,
          index: 2,
          groupId: -1,
        },
      ]);

      const result = await TabService.getCurrentTabs(existingGroups);

      expect(result[0].groupId).toBe("tg_stable_001");
      expect(result[0].chromeGroupId).toBe(5);
      expect(result[1].groupId).toBe("tg_stable_002");
      expect(result[1].chromeGroupId).toBe(10);
      expect(result[2].groupId).toBeUndefined();
      expect(result[2].chromeGroupId).toBeUndefined();
    });

    it("should handle tabs with chrome groupId not in existingGroups", async () => {
      const existingGroups = [
        {
          id: "tg_stable_001",
          chromeGroupId: 5,
          title: "Group 1",
          color: "blue",
          collapsed: false,
        },
      ] as any[];

      mockChrome.tabs.query.mockResolvedValue([
        {
          id: 1,
          url: "https://a.com",
          title: "A",
          pinned: false,
          index: 0,
          groupId: 999,
        },
      ]);

      const result = await TabService.getCurrentTabs(existingGroups);

      // chromeGroupId exists but no stable mapping found
      expect(result[0].groupId).toBeUndefined();
      expect(result[0].chromeGroupId).toBe(999);
    });

    it("should handle existingGroups without chromeGroupId", async () => {
      const existingGroups = [
        {
          id: "tg_stable_001",
          title: "Group 1",
          color: "blue",
          collapsed: false,
        }, // no chromeGroupId
      ] as any[];

      mockChrome.tabs.query.mockResolvedValue([
        {
          id: 1,
          url: "https://a.com",
          title: "A",
          pinned: false,
          index: 0,
          groupId: 5,
        },
      ]);

      const result = await TabService.getCurrentTabs(existingGroups);

      // No mapping should be found
      expect(result[0].groupId).toBeUndefined();
      expect(result[0].chromeGroupId).toBe(5);
    });
  });

  describe("addTabToGroup", () => {
    it("should add a tab to an existing group", async () => {
      mockChrome.tabs.group.mockResolvedValue(123);

      await TabService.addTabToGroup(456, 123);

      expect(mockChrome.tabs.group).toHaveBeenCalledWith({
        tabIds: [456],
        groupId: 123,
      });
    });

    it("should handle errors gracefully", async () => {
      mockChrome.tabs.group.mockRejectedValue(
        new Error("Failed to add to group"),
      );

      await expect(TabService.addTabToGroup(456, 123)).resolves.not.toThrow();
    });
  });

  describe("removeTabFromGroup", () => {
    it("should remove a tab from its group", async () => {
      mockChrome.tabs.ungroup.mockResolvedValue(undefined);

      await TabService.removeTabFromGroup(456);

      expect(mockChrome.tabs.ungroup).toHaveBeenCalledWith(456);
    });

    it("should handle errors gracefully", async () => {
      mockChrome.tabs.ungroup.mockRejectedValue(new Error("Failed to ungroup"));

      await expect(TabService.removeTabFromGroup(456)).resolves.not.toThrow();
    });
  });
});
