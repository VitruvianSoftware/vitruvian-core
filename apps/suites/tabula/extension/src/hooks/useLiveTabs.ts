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
 * Hook for live Chrome tab synchronization.
 *
 * This hook provides real-time tab state by:
 * 1. Querying Chrome tabs directly (source of truth)
 * 2. Subscribing to Chrome tab events for updates
 * 3. Never relying on stored tab IDs (they become stale)
 */

import { useState, useEffect, useCallback, useRef } from "react";
import type { Tab } from "../types";
import { TabService } from "../services/tabs";

interface UseLiveTabsOptions {
  /** Whether to auto-refresh on Chrome tab events */
  autoRefresh?: boolean;
  /** Debounce delay for rapid tab changes */
  debounceMs?: number;
  /** Filter out pinned tabs (like the extension dashboard) */
  filterExtensionPages?: boolean;
}

interface UseLiveTabsReturn {
  /** Current browser tabs (live from Chrome) */
  tabs: Tab[];
  /** Loading state */
  loading: boolean;
  /** Manually refresh tabs */
  refresh: () => Promise<void>;
  /** Close a tab by URL (reliable, doesn't use stored IDs) */
  closeTabByUrl: (url: string) => Promise<boolean>;
  /** Focus a tab by URL */
  focusTabByUrl: (url: string) => Promise<boolean>;
}

/**
 * Hook that provides live Chrome tab state.
 * Unlike stored workspace tabs, these are always fresh and accurate.
 */
export const useLiveTabs = ({
  autoRefresh = true,
  debounceMs = 100,
  filterExtensionPages = true,
}: UseLiveTabsOptions = {}): UseLiveTabsReturn => {
  const [tabs, setTabs] = useState<Tab[]>([]);
  const [loading, setLoading] = useState(true);
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | undefined>(
    undefined,
  );

  /**
   * Fetch current tabs from Chrome.
   */
  const refresh = useCallback(async () => {
    try {
      const currentTabs = await TabService.getCurrentTabs();
      // Filter out pinned tabs and extension pages from Active Tabs
      const filteredTabs = filterExtensionPages
        ? currentTabs.filter(
            (tab) => !tab.pinned && !tab.url.startsWith("chrome-extension://"),
          )
        : currentTabs;
      setTabs(filteredTabs);
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error("[useLiveTabs] Failed to fetch tabs:", err);
    } finally {
      setLoading(false);
    }
  }, [filterExtensionPages]);

  /**
   * Debounced refresh for rapid tab changes.
   */
  const debouncedRefresh = useCallback(() => {
    clearTimeout(timeoutRef.current);
    timeoutRef.current = setTimeout(refresh, debounceMs);
  }, [refresh, debounceMs]);

  /**
   * Close a tab by URL - queries Chrome to find current tab ID.
   * Returns true if tab was closed, false if not found.
   */
  const closeTabByUrl = useCallback(
    async (url: string): Promise<boolean> => {
      try {
        const currentTabs = await chrome.tabs.query({ currentWindow: true });
        const matchingTab = currentTabs.find((t) => t.url === url);

        if (matchingTab?.id) {
          await chrome.tabs.remove(matchingTab.id);
          // Refresh to reflect the change
          await refresh();
          return true;
        }
        return false;
      } catch (err) {
        // eslint-disable-next-line no-console
        console.error("[useLiveTabs] Failed to close tab:", err);
        return false;
      }
    },
    [refresh],
  );

  /**
   * Focus a tab by URL - queries Chrome to find current tab ID.
   */
  const focusTabByUrl = useCallback(async (url: string): Promise<boolean> => {
    try {
      const currentTabs = await chrome.tabs.query({ currentWindow: true });
      const matchingTab = currentTabs.find((t) => t.url === url);

      if (matchingTab?.id) {
        await chrome.tabs.update(matchingTab.id, { active: true });
        return true;
      }
      return false;
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error("[useLiveTabs] Failed to focus tab:", err);
      return false;
    }
  }, []);

  // Initial fetch
  useEffect(() => {
    refresh();
  }, [refresh]);

  // Subscribe to Chrome tab events
  useEffect(() => {
    if (!autoRefresh) return;

    chrome.tabs.onCreated.addListener(debouncedRefresh);
    chrome.tabs.onUpdated.addListener(debouncedRefresh);
    chrome.tabs.onRemoved.addListener(debouncedRefresh);
    chrome.tabs.onMoved.addListener(debouncedRefresh);
    chrome.tabs.onActivated.addListener(debouncedRefresh);

    return () => {
      clearTimeout(timeoutRef.current);
      chrome.tabs.onCreated.removeListener(debouncedRefresh);
      chrome.tabs.onUpdated.removeListener(debouncedRefresh);
      chrome.tabs.onRemoved.removeListener(debouncedRefresh);
      chrome.tabs.onMoved.removeListener(debouncedRefresh);
      chrome.tabs.onActivated.removeListener(debouncedRefresh);
    };
  }, [autoRefresh, debouncedRefresh]);

  return {
    tabs,
    loading,
    refresh,
    closeTabByUrl,
    focusTabByUrl,
  };
};

export default useLiveTabs;
