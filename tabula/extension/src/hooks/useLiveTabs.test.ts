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

import { renderHook, act, waitFor } from "@testing-library/react";
import { useLiveTabs } from "./useLiveTabs";
import { TabService } from "../services/tabs";

// Mock Chrome API
const mockChrome = {
  tabs: {
    query: jest.fn(),
    remove: jest.fn(),
    update: jest.fn(),
    onCreated: { addListener: jest.fn(), removeListener: jest.fn() },
    onUpdated: { addListener: jest.fn(), removeListener: jest.fn() },
    onRemoved: { addListener: jest.fn(), removeListener: jest.fn() },
    onMoved: { addListener: jest.fn(), removeListener: jest.fn() },
    onActivated: { addListener: jest.fn(), removeListener: jest.fn() },
  },
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
(globalThis as any).chrome = mockChrome;

// Mock TabService
jest.mock("../services/tabs", () => ({
  TabService: {
    getCurrentTabs: jest.fn(),
  },
}));

describe("useLiveTabs", () => {
  const mockTabs = [
    { id: 1, url: "https://google.com", title: "Google", pinned: false },
    { id: 2, url: "https://example.com", title: "Example", pinned: false },
    {
      id: 3,
      url: "chrome-extension://some-id/dashboard.html",
      title: "Dashboard",
      pinned: true,
    },
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([...mockTabs]);
    mockChrome.tabs.query.mockResolvedValue([...mockTabs]);
  });

  it("should fetch and filter out pinned tabs and extension pages on mount", async () => {
    const { result } = renderHook(() => useLiveTabs());

    // Initially loading
    expect(result.current.loading).toBe(true);

    // Wait for data
    await waitFor(() => expect(result.current.loading).toBe(false));

    // Should filter out pinned tabs AND extension pages by default
    expect(result.current.tabs).toHaveLength(2);
    expect(result.current.tabs.map((t) => t.url)).toEqual([
      "https://google.com",
      "https://example.com",
    ]);
  });

  it("should include pinned tabs when filterExtensionPages is false", async () => {
    const { result } = renderHook(() =>
      useLiveTabs({ filterExtensionPages: false }),
    );

    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.tabs).toHaveLength(3);
  });

  it("should close tab by URL", async () => {
    const { result } = renderHook(() => useLiveTabs());
    await waitFor(() => expect(result.current.loading).toBe(false));

    await act(async () => {
      const success = await result.current.closeTabByUrl("https://google.com");
      expect(success).toBe(true);
    });

    expect(mockChrome.tabs.remove).toHaveBeenCalledWith(1);
    // Should refresh after closing
    expect(TabService.getCurrentTabs).toHaveBeenCalledTimes(2); // Mount + Close
  });

  it("should return false if closing non-existent URL", async () => {
    const { result } = renderHook(() => useLiveTabs());
    await waitFor(() => expect(result.current.loading).toBe(false));

    await act(async () => {
      const success = await result.current.closeTabByUrl(
        "https://not-found.com",
      );
      expect(success).toBe(false);
    });

    expect(mockChrome.tabs.remove).not.toHaveBeenCalled();
  });

  it("should focus tab by URL", async () => {
    const { result } = renderHook(() => useLiveTabs());
    await waitFor(() => expect(result.current.loading).toBe(false));

    await act(async () => {
      const success = await result.current.focusTabByUrl("https://example.com");
      expect(success).toBe(true);
    });

    expect(mockChrome.tabs.update).toHaveBeenCalledWith(2, { active: true });
  });

  it("should subscribe to chrome tab events when autoRefresh is true", () => {
    renderHook(() => useLiveTabs({ autoRefresh: true }));

    expect(mockChrome.tabs.onCreated.addListener).toHaveBeenCalled();
    expect(mockChrome.tabs.onUpdated.addListener).toHaveBeenCalled();
    expect(mockChrome.tabs.onRemoved.addListener).toHaveBeenCalled();
  });

  it("should NOT subscribe to chrome tab events when autoRefresh is false", () => {
    renderHook(() => useLiveTabs({ autoRefresh: false }));

    expect(mockChrome.tabs.onCreated.addListener).not.toHaveBeenCalled();
  });

  it("should cleanup listeners on unmount", () => {
    const { unmount } = renderHook(() => useLiveTabs({ autoRefresh: true }));
    unmount();

    expect(mockChrome.tabs.onCreated.removeListener).toHaveBeenCalled();
    expect(mockChrome.tabs.onUpdated.removeListener).toHaveBeenCalled();
  });

  it("should debounce refresh calls", async () => {
    jest.useFakeTimers();
    const listeners: Record<string, () => void> = {};

    // Capture the listener
    mockChrome.tabs.onCreated.addListener.mockImplementation(
      (fn: () => void) => {
        listeners.onCreated = fn;
      },
    );

    renderHook(() => useLiveTabs({ autoRefresh: true, debounceMs: 100 }));

    expect(listeners.onCreated).toBeDefined();

    // Trigger multiple times
    act(() => {
      listeners.onCreated();
      listeners.onCreated();
      listeners.onCreated();
    });

    // Should not have refreshed yet (beyond initial mount refresh)
    expect(TabService.getCurrentTabs).toHaveBeenCalledTimes(1);

    // Fast forward
    act(() => {
      jest.advanceTimersByTime(100);
    });

    // Should have refreshed exactly once more
    expect(TabService.getCurrentTabs).toHaveBeenCalledTimes(2);

    jest.useRealTimers();
  });

  it("should handle error when closing tab", async () => {
    // Force query to fail
    mockChrome.tabs.query.mockRejectedValue(new Error("Close failed"));
    const consoleSpy = jest
      .spyOn(console, "error")
      .mockImplementation(() => {});

    const { result } = renderHook(() => useLiveTabs());
    await waitFor(() => expect(result.current.loading).toBe(false));

    let success;
    await act(async () => {
      success = await result.current.closeTabByUrl("https://google.com");
    });

    expect(success).toBe(false);
    expect(consoleSpy).toHaveBeenCalledWith(
      "[useLiveTabs] Failed to close tab:",
      expect.any(Error),
    );
    consoleSpy.mockRestore();
  });

  it("should handle error during refresh", async () => {
    // Force an error
    (TabService.getCurrentTabs as jest.Mock).mockRejectedValue(
      new Error("Refresh failed"),
    );

    // Spy on console.error to keep output clean
    const consoleSpy = jest
      .spyOn(console, "error")
      .mockImplementation(() => {});

    const { result } = renderHook(() => useLiveTabs());

    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(consoleSpy).toHaveBeenCalledWith(
      "[useLiveTabs] Failed to fetch tabs:",
      expect.any(Error),
    );
    consoleSpy.mockRestore();
  });

  it("should return false if focusTabByUrl fails", async () => {
    // Force an error in chrome.tabs.query
    mockChrome.tabs.query.mockRejectedValue(new Error("Query failed"));
    const consoleSpy = jest
      .spyOn(console, "error")
      .mockImplementation(() => {});

    const { result } = renderHook(() => useLiveTabs());
    // Wait for initial load (which might also fail, but we care about the helper)
    await waitFor(() => expect(result.current.loading).toBe(false));

    let success;
    await act(async () => {
      success = await result.current.focusTabByUrl("https://example.com");
    });

    expect(success).toBe(false);
    consoleSpy.mockRestore();
  });

  it("should return false if focus tab is not found", async () => {
    const { result } = renderHook(() => useLiveTabs());
    await waitFor(() => expect(result.current.loading).toBe(false));

    let success;
    await act(async () => {
      success = await result.current.focusTabByUrl("https://non-existent.com");
    });

    expect(success).toBe(false);
  });
});
