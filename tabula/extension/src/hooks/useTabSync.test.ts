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
 * Tests for useTabSync hook
 *
 * These tests verify the fixes for:
 * 1. Stale closure bug - workspace ID captured at effect creation time
 * 2. Race condition - loadWorkspaces() overwriting fresh tab data
 * 3. Tab removal - immediate optimistic update
 */

import { renderHook, act } from "@testing-library/react";
import { useTabSync } from "./useTabSync";
import { TabService } from "../services/tabs";
import { WorkspaceService } from "../services/workspace";
import { WindowOwnershipService } from "../services/windowOwnership";
import type { Workspace, Tab } from "../types";

// Mock services
jest.mock("../services/tabs");
jest.mock("../services/workspace");
jest.mock("../services/windowOwnership", () => ({
  WindowOwnershipService: {
    isWorkspaceOwnedByOtherWindow: jest.fn(),
    getWorkspaceOwner: jest.fn(),
  },
}));
jest.mock("../services/deviceId", () => ({
  getDeviceId: jest.fn().mockResolvedValue("device_me"),
}));

// Mock Chrome API
const mockChrome = {
  tabs: {
    onCreated: { addListener: jest.fn(), removeListener: jest.fn() },
    onUpdated: { addListener: jest.fn(), removeListener: jest.fn() },
    onRemoved: { addListener: jest.fn(), removeListener: jest.fn() },
    onMoved: { addListener: jest.fn(), removeListener: jest.fn() },
    onDetached: { addListener: jest.fn(), removeListener: jest.fn() },
    onAttached: { addListener: jest.fn(), removeListener: jest.fn() },
  },
  tabGroups: {
    onCreated: { addListener: jest.fn(), removeListener: jest.fn() },
    onUpdated: { addListener: jest.fn(), removeListener: jest.fn() },
    onRemoved: { addListener: jest.fn(), removeListener: jest.fn() },
  },
  storage: {
    local: {
      get: jest.fn().mockResolvedValue({}), // No force-remote flag by default
    },
  },
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
(globalThis as any).chrome = mockChrome;

// Helper to create mock workspace
const createMockWorkspace = (
  overrides: Partial<Workspace> = {},
): Workspace => ({
  id: "ws-123",
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

// Helper to create mock tab
const createMockTab = (overrides: Partial<Tab> = {}): Tab => ({
  id: 1,
  url: "https://example.com",
  title: "Example",
  pinned: false,
  active: false,
  index: 0,
  ...overrides,
});

describe("useTabSync", () => {
  let activeWorkspaceRef: React.MutableRefObject<Workspace | null>;
  let isSwitchingRef: React.MutableRefObject<boolean>;
  let setActiveWorkspaceData: jest.Mock;

  beforeEach(() => {
    jest.clearAllMocks();
    jest.useFakeTimers();

    // Reset refs for each test
    activeWorkspaceRef = { current: createMockWorkspace() };
    isSwitchingRef = { current: false };
    setActiveWorkspaceData = jest.fn();

    // Reset mock implementations
    (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([]);
    (TabService.getCurrentTabGroups as jest.Mock).mockResolvedValue([]);
    (TabService.getCurrentTabGroupsResult as jest.Mock).mockResolvedValue({
      groups: [],
      reliable: true,
    });
    (WorkspaceService.updateWorkspace as jest.Mock).mockResolvedValue(
      undefined,
    );
    (WorkspaceService.updateWorkspaceTabs as jest.Mock).mockResolvedValue(
      undefined,
    );
    (
      WindowOwnershipService.isWorkspaceOwnedByOtherWindow as jest.Mock
    ).mockResolvedValue(null);
    (WindowOwnershipService.getWorkspaceOwner as jest.Mock).mockResolvedValue(
      null,
    );
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  describe("Chrome event listeners", () => {
    it("should register all tab event listeners on mount", async () => {
      renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
        }),
      );

      // Advance past the 500ms init delay
      await act(async () => {
        jest.advanceTimersByTime(600);
      });

      expect(mockChrome.tabs.onCreated.addListener).toHaveBeenCalled();
      expect(mockChrome.tabs.onUpdated.addListener).toHaveBeenCalled();
      expect(mockChrome.tabs.onRemoved.addListener).toHaveBeenCalled();
      expect(mockChrome.tabs.onMoved.addListener).toHaveBeenCalled();
      expect(mockChrome.tabs.onDetached.addListener).toHaveBeenCalled();
      expect(mockChrome.tabs.onAttached.addListener).toHaveBeenCalled();
    });

    it("should remove all listeners on unmount", () => {
      const { unmount } = renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
        }),
      );

      unmount();

      expect(mockChrome.tabs.onCreated.removeListener).toHaveBeenCalled();
      expect(mockChrome.tabs.onUpdated.removeListener).toHaveBeenCalled();
      expect(mockChrome.tabs.onRemoved.removeListener).toHaveBeenCalled();
      expect(mockChrome.tabs.onMoved.removeListener).toHaveBeenCalled();
      expect(mockChrome.tabs.onDetached.removeListener).toHaveBeenCalled();
      expect(mockChrome.tabs.onAttached.removeListener).toHaveBeenCalled();
    });

    it("should not register listeners when disabled", () => {
      renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
          enabled: false,
        }),
      );

      expect(mockChrome.tabs.onCreated.addListener).not.toHaveBeenCalled();
    });
  });

  describe("syncTabs - stale closure prevention", () => {
    it("should use current workspace ID from ref, not stale closure", async () => {
      const workspace1 = createMockWorkspace({ id: "ws-old" });
      const workspace2 = createMockWorkspace({ id: "ws-new" });

      activeWorkspaceRef = { current: workspace1 };

      const { result } = renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
        }),
      );

      // Simulate workspace switch by updating the ref (as would happen in real app)
      activeWorkspaceRef.current = workspace2;

      // Now call syncTabs - should use ws-new, not ws-old
      await act(async () => {
        await result.current.syncTabs();
      });

      // Verify the NEW workspace ID was used
      expect(WorkspaceService.updateWorkspaceTabs).toHaveBeenCalledWith(
        "ws-new",
        expect.any(Array),
        expect.any(Array),
      );
    });

    it("should not sync when workspace ref is null", async () => {
      activeWorkspaceRef = { current: null };

      const { result } = renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
        }),
      );

      await act(async () => {
        await result.current.syncTabs();
      });

      expect(TabService.getCurrentTabs).not.toHaveBeenCalled();
      expect(setActiveWorkspaceData).not.toHaveBeenCalled();
    });

    it("should not sync when switching workspaces", async () => {
      isSwitchingRef = { current: true };

      const { result } = renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
        }),
      );

      await act(async () => {
        await result.current.syncTabs();
      });

      expect(TabService.getCurrentTabs).not.toHaveBeenCalled();
    });
  });

  describe("syncTabs - race condition prevention", () => {
    it("should update state with fresh tabs from Chrome", async () => {
      const workspace = createMockWorkspace();
      activeWorkspaceRef = { current: workspace };

      const freshTabs = [
        createMockTab({ id: 1, title: "Tab 1" }),
        createMockTab({ id: 2, title: "Tab 2" }),
      ];
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue(freshTabs);

      const { result } = renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
        }),
      );

      await act(async () => {
        await result.current.syncTabs();
      });

      // Should set state with fresh tabs
      expect(setActiveWorkspaceData).toHaveBeenCalledWith(
        expect.objectContaining({ tabs: freshTabs }),
      );
    });

    it("should filter out pinned tabs from active tabs", async () => {
      const workspace = createMockWorkspace();
      activeWorkspaceRef = { current: workspace };

      const mixedTabs = [
        createMockTab({
          id: 1,
          url: "https://example.com",
          title: "Regular Tab",
          pinned: false,
        }),
        createMockTab({
          id: 2,
          url: "http://localhost:3000",
          title: "Tabula Dashboard",
          pinned: true,
        }),
        createMockTab({
          id: 3,
          url: "https://google.com",
          title: "Google",
          pinned: false,
        }),
      ];
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue(mixedTabs);

      const { result } = renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
        }),
      );

      await act(async () => {
        await result.current.syncTabs();
      });

      // Should only have non-pinned, non-extension tabs
      const callArg = setActiveWorkspaceData.mock.calls[0][0];
      expect(callArg.tabs).toHaveLength(2);
      expect(callArg.tabs.map((t: Tab) => t.url)).toEqual([
        "https://example.com",
        "https://google.com",
      ]);
    });

    it("should persist tabs to storage after state update", async () => {
      const workspace = createMockWorkspace({ id: "ws-persist" });
      activeWorkspaceRef = { current: workspace };
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([
        createMockTab(),
      ]);

      const { result } = renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
        }),
      );

      await act(async () => {
        await result.current.syncTabs();
      });

      // State should be updated first
      expect(setActiveWorkspaceData).toHaveBeenCalled();
      // Then persisted to storage
      expect(WorkspaceService.updateWorkspaceTabs).toHaveBeenCalledWith(
        "ws-persist",
        expect.any(Array),
        expect.any(Array),
      );
    });
  });

  describe("handleTabRemoved - optimistic update", () => {
    it("should immediately remove closed tab from UI", async () => {
      const existingTabs = [
        createMockTab({ id: 100, title: "Tab to remove" }),
        createMockTab({ id: 200, title: "Tab to keep" }),
      ];
      const workspace = createMockWorkspace({ tabs: existingTabs });
      activeWorkspaceRef = { current: workspace };

      const { result } = renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
        }),
      );

      // Simulate tab removal
      act(() => {
        result.current.handleTabRemoved(100);
      });

      // Should immediately update state with tab removed
      expect(setActiveWorkspaceData).toHaveBeenCalledWith(
        expect.objectContaining({
          tabs: [expect.objectContaining({ id: 200, title: "Tab to keep" })],
        }),
      );
    });

    it("should trigger debounced sync after removal", async () => {
      const workspace = createMockWorkspace({
        tabs: [createMockTab({ id: 100 })],
      });
      activeWorkspaceRef = { current: workspace };
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([]);

      const { result } = renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
          debounceMs: 100,
        }),
      );

      act(() => {
        result.current.handleTabRemoved(100);
      });

      // Fast-forward past debounce
      await act(async () => {
        jest.advanceTimersByTime(150);
      });

      // Should have synced to storage
      expect(WorkspaceService.updateWorkspaceTabs).toHaveBeenCalled();
    });

    it("should handle removal when workspace is null gracefully", () => {
      activeWorkspaceRef = { current: null };

      const { result } = renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
        }),
      );

      // Should not throw
      expect(() => {
        act(() => {
          result.current.handleTabRemoved(100);
        });
      }).not.toThrow();

      // Should not update state when no workspace
      expect(setActiveWorkspaceData).not.toHaveBeenCalled();
    });
  });

  describe("debouncedSync", () => {
    it("should debounce rapid tab changes", async () => {
      const workspace = createMockWorkspace();
      activeWorkspaceRef = { current: workspace };
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([
        createMockTab(),
      ]);

      const { result } = renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
          debounceMs: 100,
        }),
      );

      // Call debouncedSync multiple times rapidly
      act(() => {
        result.current.debouncedSync();
        result.current.debouncedSync();
        result.current.debouncedSync();
      });

      // Fast-forward before debounce completes
      await act(async () => {
        jest.advanceTimersByTime(50);
      });

      // Should not have synced yet
      expect(TabService.getCurrentTabs).not.toHaveBeenCalled();

      // Fast-forward past debounce
      await act(async () => {
        jest.advanceTimersByTime(100);
      });

      // Should have synced only once
      expect(TabService.getCurrentTabs).toHaveBeenCalledTimes(1);
    });

    it("should not sync when switching workspaces", () => {
      isSwitchingRef = { current: true };

      const { result } = renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
        }),
      );

      act(() => {
        result.current.debouncedSync();
      });

      // Fast-forward
      act(() => {
        jest.advanceTimersByTime(200);
      });

      // Should not have scheduled sync
      expect(TabService.getCurrentTabs).not.toHaveBeenCalled();
    });
  });

  describe("handleTabUpdate - tab change info filtering", () => {
    it("should sync when tab URL changes", async () => {
      const workspace = createMockWorkspace();
      activeWorkspaceRef = { current: workspace };
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([
        createMockTab(),
      ]);

      renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
          debounceMs: 50,
        }),
      );

      // Advance past the 500ms init delay so listeners are registered
      await act(async () => {
        jest.advanceTimersByTime(600);
      });

      // Get the handleTabUpdate callback that was registered
      const handleTabUpdate =
        mockChrome.tabs.onUpdated.addListener.mock.calls[0][0];

      // Simulate URL change
      act(() => {
        handleTabUpdate(
          1,
          { url: "https://new-url.com" },
          {} as chrome.tabs.Tab,
        );
      });

      // Fast-forward past debounce
      await act(async () => {
        jest.advanceTimersByTime(100);
      });

      expect(TabService.getCurrentTabs).toHaveBeenCalled();
    });

    it("should sync when tab title changes", async () => {
      const workspace = createMockWorkspace();
      activeWorkspaceRef = { current: workspace };
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([
        createMockTab(),
      ]);

      renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
          debounceMs: 50,
        }),
      );

      // Advance past the 500ms init delay
      await act(async () => {
        jest.advanceTimersByTime(600);
      });

      const handleTabUpdate =
        mockChrome.tabs.onUpdated.addListener.mock.calls[0][0];

      // Simulate title change
      act(() => {
        handleTabUpdate(1, { title: "New Title" }, {} as chrome.tabs.Tab);
      });

      await act(async () => {
        jest.advanceTimersByTime(100);
      });

      expect(TabService.getCurrentTabs).toHaveBeenCalled();
    });

    it("should sync when tab status becomes complete", async () => {
      const workspace = createMockWorkspace();
      activeWorkspaceRef = { current: workspace };
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([
        createMockTab(),
      ]);

      renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
          debounceMs: 50,
        }),
      );

      // Advance past the 500ms init delay
      await act(async () => {
        jest.advanceTimersByTime(600);
      });

      const handleTabUpdate =
        mockChrome.tabs.onUpdated.addListener.mock.calls[0][0];

      // Simulate status complete
      act(() => {
        handleTabUpdate(1, { status: "complete" }, {} as chrome.tabs.Tab);
      });

      await act(async () => {
        jest.advanceTimersByTime(100);
      });

      expect(TabService.getCurrentTabs).toHaveBeenCalled();
    });

    it("should NOT sync for irrelevant changes like favIconUrl only", async () => {
      const workspace = createMockWorkspace();
      activeWorkspaceRef = { current: workspace };

      renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
          debounceMs: 50,
        }),
      );

      // Advance past the 500ms init delay
      await act(async () => {
        jest.advanceTimersByTime(600);
      });

      // Clear mock calls from the initial sync triggered by the delay
      (TabService.getCurrentTabs as jest.Mock).mockClear();

      const handleTabUpdate =
        mockChrome.tabs.onUpdated.addListener.mock.calls[0][0];

      // Simulate only favIconUrl change (not URL, title, or status=complete)
      act(() => {
        handleTabUpdate(
          1,
          { favIconUrl: "https://example.com/icon.png" },
          {} as chrome.tabs.Tab,
        );
      });

      await act(async () => {
        jest.advanceTimersByTime(100);
      });

      // Should NOT have synced for non-meaningful change
      expect(TabService.getCurrentTabs).not.toHaveBeenCalled();
    });

    it("should NOT sync for loading status", async () => {
      const workspace = createMockWorkspace();
      activeWorkspaceRef = { current: workspace };

      renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
          debounceMs: 50,
        }),
      );

      // Advance past the 500ms init delay
      await act(async () => {
        jest.advanceTimersByTime(600);
      });

      // Clear mock calls from the initial sync triggered by the delay
      (TabService.getCurrentTabs as jest.Mock).mockClear();

      const handleTabUpdate =
        mockChrome.tabs.onUpdated.addListener.mock.calls[0][0];

      // Simulate loading status only (not complete)
      act(() => {
        handleTabUpdate(1, { status: "loading" }, {} as chrome.tabs.Tab);
      });

      await act(async () => {
        jest.advanceTimersByTime(100);
      });

      // Should NOT have synced for loading status
      expect(TabService.getCurrentTabs).not.toHaveBeenCalled();
    });

    it("should sync when tab pinned state changes", async () => {
      const workspace = createMockWorkspace();
      activeWorkspaceRef = { current: workspace };
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([
        createMockTab(),
      ]);

      renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
          debounceMs: 50,
        }),
      );

      // Advance past the 500ms init delay
      await act(async () => {
        jest.advanceTimersByTime(600);
      });

      // Clear mock calls from any initial sync
      (TabService.getCurrentTabs as jest.Mock).mockClear();

      const handleTabUpdate =
        mockChrome.tabs.onUpdated.addListener.mock.calls[0][0];

      // Simulate tab being pinned
      act(() => {
        handleTabUpdate(1, { pinned: true }, {} as chrome.tabs.Tab);
      });

      await act(async () => {
        jest.advanceTimersByTime(100);
      });

      // Should sync when pinned state changes
      expect(TabService.getCurrentTabs).toHaveBeenCalled();
    });

    it("should sync when tab groupId changes", async () => {
      const workspace = createMockWorkspace();
      activeWorkspaceRef = { current: workspace };
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([
        createMockTab(),
      ]);

      renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
          debounceMs: 50,
        }),
      );

      // Advance past the 500ms init delay
      await act(async () => {
        jest.advanceTimersByTime(600);
      });

      // Clear mock calls from any initial sync
      (TabService.getCurrentTabs as jest.Mock).mockClear();

      const handleTabUpdate =
        mockChrome.tabs.onUpdated.addListener.mock.calls[0][0];

      // Simulate tab being added to a group
      act(() => {
        handleTabUpdate(1, { groupId: 123 }, {} as chrome.tabs.Tab);
      });

      await act(async () => {
        jest.advanceTimersByTime(100);
      });

      // Should sync when groupId changes
      expect(TabService.getCurrentTabs).toHaveBeenCalled();
    });
  });

  describe("handleTabRemoved - during switching", () => {
    it("should not remove tab when switching workspaces", () => {
      const workspace = createMockWorkspace({
        tabs: [createMockTab({ id: 100 })],
      });
      activeWorkspaceRef = { current: workspace };
      isSwitchingRef = { current: true };

      const { result } = renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
        }),
      );

      act(() => {
        result.current.handleTabRemoved(100);
      });

      // Should not update state when switching
      expect(setActiveWorkspaceData).not.toHaveBeenCalled();
    });
  });

  describe("syncTabs - ungrouping behavior", () => {
    it("persists a genuine ungroup-all even when the workspace had stored groups (wedge fix)", async () => {
      // Workspace HAD groups in storage; user ungrouped every tab in Chrome.
      // Chrome authoritatively reports zero groups (reliable: true). The fix
      // must persist tabGroups: [] instead of resurrecting the stored group
      // and then wedging on the "groups but no groupIds" guard.
      const storedTabs = [
        createMockTab({ id: 1, url: "https://a.com", groupId: "group-1" }),
      ];
      const workspace = createMockWorkspace({
        tabs: storedTabs,
        tabGroups: [{ id: "group-1", color: "blue", collapsed: false }],
      });
      activeWorkspaceRef = { current: workspace };
      (WorkspaceService.getWorkspaceById as jest.Mock).mockResolvedValue(
        workspace,
      );

      // Chrome: tab is now ungrouped, and the groups query is RELIABLE + empty
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([
        createMockTab({ id: 1, url: "https://a.com", groupId: undefined }),
      ]);
      (TabService.getCurrentTabGroupsResult as jest.Mock).mockResolvedValue({
        groups: [],
        reliable: true,
      });

      renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
          debounceMs: 50,
        }),
      );
      await act(async () => {
        jest.advanceTimersByTime(600);
      });

      // The write must go through (not be blocked by the stale-group guard)...
      expect(WorkspaceService.updateWorkspaceTabs).toHaveBeenCalled();
      // ...and it must persist an EMPTY group list (the real ungroup)
      const call = (
        WorkspaceService.updateWorkspaceTabs as jest.Mock
      ).mock.calls.at(-1)!;
      expect(call[2]).toEqual([]);
    });

    it("preserves stored groups when the Chrome groups query is UNRELIABLE", async () => {
      // Same setup, but the groups query failed (reliable: false) — we must
      // NOT treat that as a real ungroup; keep the stored groups.
      const storedTabs = [
        createMockTab({ id: 1, url: "https://a.com", groupId: "group-1" }),
      ];
      const storedGroups = [{ id: "group-1", color: "blue", collapsed: false }];
      const workspace = createMockWorkspace({
        tabs: storedTabs,
        tabGroups: storedGroups,
      });
      activeWorkspaceRef = { current: workspace };
      (WorkspaceService.getWorkspaceById as jest.Mock).mockResolvedValue(
        workspace,
      );

      // Tab still claims membership (groupId present), query unreliable
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([
        createMockTab({ id: 1, url: "https://a.com", groupId: "group-1" }),
      ]);
      (TabService.getCurrentTabGroupsResult as jest.Mock).mockResolvedValue({
        groups: [],
        reliable: false,
      });

      renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
          debounceMs: 50,
        }),
      );
      await act(async () => {
        jest.advanceTimersByTime(600);
      });

      expect(WorkspaceService.updateWorkspaceTabs).toHaveBeenCalled();
      const call = (
        WorkspaceService.updateWorkspaceTabs as jest.Mock
      ).mock.calls.at(-1)!;
      // Stored groups preserved (not wiped) because the query was unreliable
      expect(call[2]).toEqual(storedGroups);
    });

    it("should clear groupId when Chrome says tab is ungrouped (not preserve stale state)", async () => {
      // Scenario: Tab was in group 'G1' in storage, but Chrome now returns groupId: undefined
      // The fix ensures we DON'T preserve the old groupId for tabs already in storage

      const storedTabs = [
        createMockTab({
          id: 1,
          url: "https://example.com/existing",
          groupId: "group-1",
        }),
      ];

      // Workspace has tab with groupId but no tabGroups (simulating group was removed)
      const workspace = createMockWorkspace({
        tabs: storedTabs,
        tabGroups: [], // Empty to avoid sync guard
      });

      activeWorkspaceRef = { current: workspace };

      // Mock storage returns the workspace with grouped tab
      (WorkspaceService.getWorkspaceById as jest.Mock).mockResolvedValue(
        workspace,
      );

      // Chrome API returns the SAME tab but WITHOUT groupId (it was ungrouped)
      const chromeTabs = [
        createMockTab({
          id: 1,
          url: "https://example.com/existing",
          groupId: undefined,
        }),
      ];
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue(chromeTabs);
      (TabService.getCurrentTabGroups as jest.Mock).mockResolvedValue([]);
      (TabService.getCurrentTabGroupsResult as jest.Mock).mockResolvedValue({
        groups: [],
        reliable: true,
      });

      renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
          debounceMs: 50,
        }),
      );

      // Advance past the init delay and debounce
      await act(async () => {
        jest.advanceTimersByTime(600);
      });

      // Verify setActiveWorkspaceData was called with the tab having NO groupId
      // (Chrome's state takes precedence for existing tabs)
      expect(setActiveWorkspaceData).toHaveBeenCalled();
      const calledWith =
        setActiveWorkspaceData.mock.calls[
          setActiveWorkspaceData.mock.calls.length - 1
        ][0];
      const updatedTab = calledWith.tabs?.find(
        (t: Tab) => t.url === "https://example.com/existing",
      );

      // The tab should NOT have the old groupId preserved - Chrome said it's ungrouped
      expect(updatedTab?.groupId).toBeUndefined();
    });

    it("should not preserve groupId for tabs that exist in storage (Chrome state takes precedence)", async () => {
      // Scenario: Storage has a tab with groupId, but Chrome now returns it WITHOUT groupId
      // This is the key test for the ungrouping fix - Chrome's state must win

      // Storage has an older tab with a groupId
      const storedTabs = [
        createMockTab({
          id: 1,
          url: "https://example.com/a-tab",
          groupId: "group-1",
        }),
      ];

      // No tabGroups in stored workspace (group was deleted or all tabs ungrouped)
      const workspace = createMockWorkspace({
        tabs: storedTabs,
        tabGroups: [], // Empty - no groups
      });

      activeWorkspaceRef = { current: workspace };

      (WorkspaceService.getWorkspaceById as jest.Mock).mockResolvedValue(
        workspace,
      );

      // Chrome returns the same tab but now without groupId (tab was ungrouped)
      const chromeTabs = [
        createMockTab({
          id: 1,
          url: "https://example.com/a-tab",
          groupId: undefined,
        }),
      ];
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue(chromeTabs);
      (TabService.getCurrentTabGroups as jest.Mock).mockResolvedValue([]);
      (TabService.getCurrentTabGroupsResult as jest.Mock).mockResolvedValue({
        groups: [],
        reliable: true,
      });

      renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
          debounceMs: 50,
        }),
      );

      await act(async () => {
        jest.advanceTimersByTime(600);
      });

      // Should have synced - verify the tab has NO groupId (Chrome's state won)
      expect(setActiveWorkspaceData).toHaveBeenCalled();
      const calledWith =
        setActiveWorkspaceData.mock.calls[
          setActiveWorkspaceData.mock.calls.length - 1
        ][0];
      const updatedTab = calledWith.tabs?.find(
        (t: Tab) => t.url === "https://example.com/a-tab",
      );

      // Key assertion: the tab should NOT have preserved the old groupId
      expect(updatedTab?.groupId).toBeUndefined();
    });
  });

  describe("ownership guard (multi-window)", () => {
    it("fails closed: does not write when currentWindowId is not yet resolved", async () => {
      const { result } = renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          // currentWindowId intentionally omitted (pre-mount state)
        }),
      );

      await act(async () => {
        await result.current.syncTabs();
      });

      expect(WorkspaceService.updateWorkspaceTabs).not.toHaveBeenCalled();
    });

    it("uses a fresh window id even though syncTabs was memoized before it resolved", async () => {
      // First render without a window id (chrome.windows.getCurrent pending)
      const { result, rerender } = renderHook(
        ({ windowId }: { windowId?: number }) =>
          useTabSync({
            activeWorkspaceRef,
            isSwitchingRef,
            setActiveWorkspaceData,
            currentWindowId: windowId,
          }),
        { initialProps: { windowId: undefined as number | undefined } },
      );

      // Window id resolves later — another window owns the workspace
      (
        WindowOwnershipService.isWorkspaceOwnedByOtherWindow as jest.Mock
      ).mockResolvedValue({
        workspaceId: "ws-123",
        windowId: 999,
        tabId: 1,
        lastActive: Date.now(),
      });
      rerender({ windowId: 123 });

      await act(async () => {
        await result.current.syncTabs();
      });

      // Guard must have consulted ownership with the fresh id and blocked
      expect(
        WindowOwnershipService.isWorkspaceOwnedByOtherWindow,
      ).toHaveBeenCalledWith("ws-123", 123);
      expect(WorkspaceService.updateWorkspaceTabs).not.toHaveBeenCalled();
    });
  });

  describe("active-device lease (multi-device)", () => {
    it("skips automatic capture when another device holds a fresh lease", async () => {
      (WorkspaceService.getWorkspaceById as jest.Mock).mockResolvedValue(
        createMockWorkspace({
          activeDeviceId: "device_other",
          activeDeviceSeenAt: new Date().toISOString(),
        }),
      );

      const { result } = renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
        }),
      );

      await act(async () => {
        await result.current.syncTabs();
      });

      expect(WorkspaceService.updateWorkspaceTabs).not.toHaveBeenCalled();
    });

    it("syncs normally when the foreign lease is stale", async () => {
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([
        createMockTab(),
      ]);
      (WorkspaceService.getWorkspaceById as jest.Mock).mockResolvedValue(
        createMockWorkspace({
          activeDeviceId: "device_other",
          activeDeviceSeenAt: new Date(
            Date.now() - 10 * 60 * 1000,
          ).toISOString(),
        }),
      );

      const { result } = renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
        }),
      );

      await act(async () => {
        await result.current.syncTabs();
      });

      expect(WorkspaceService.updateWorkspaceTabs).toHaveBeenCalled();
    });

    it("syncs normally when this device holds the lease", async () => {
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([
        createMockTab(),
      ]);
      (WorkspaceService.getWorkspaceById as jest.Mock).mockResolvedValue(
        createMockWorkspace({
          activeDeviceId: "device_me",
          activeDeviceSeenAt: new Date().toISOString(),
        }),
      );

      const { result } = renderHook(() =>
        useTabSync({
          activeWorkspaceRef,
          isSwitchingRef,
          setActiveWorkspaceData,
          currentWindowId: 123,
        }),
      );

      await act(async () => {
        await result.current.syncTabs();
      });

      expect(WorkspaceService.updateWorkspaceTabs).toHaveBeenCalled();
    });
  });
});
