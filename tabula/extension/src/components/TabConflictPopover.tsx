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

import { useState, useEffect } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  WindowOwnershipRecord,
  WindowOwnershipService,
} from "../services/windowOwnership";
import { getFaviconSrc } from "../utils/favicon";

interface TabItemProps {
  tab: chrome.tabs.Tab;
  selected: boolean;
  onToggle: () => void;
}

function TabItem({ tab, selected, onToggle }: TabItemProps) {
  return (
    <motion.div
      onClick={onToggle}
      whileHover={{ backgroundColor: "rgba(255, 255, 255, 0.05)" }}
      whileTap={{ scale: 0.99 }}
      style={{
        display: "flex",
        alignItems: "center",
        gap: "12px",
        padding: "10px 16px",
        cursor: "pointer",
        backgroundColor: selected ? "rgba(51, 112, 255, 0.15)" : "transparent",
        borderRadius: "12px",
        margin: "2px 8px",
        transition: "background-color 0.2s ease",
      }}
      role="checkbox"
      aria-checked={selected}
      tabIndex={0}
      onKeyDown={(e: React.KeyboardEvent) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onToggle();
        }
      }}
    >
      {/* Checkbox */}
      <div
        style={{
          width: "20px",
          height: "20px",
          border: `2px solid ${selected ? "var(--color-primary)" : "rgba(255, 255, 255, 0.2)"}`,
          borderRadius: "6px",
          backgroundColor: selected ? "var(--color-primary)" : "transparent",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          transition: "all 0.2s ease",
        }}
      >
        {selected && (
          <svg width="12" height="12" viewBox="0 0 12 12" fill="white">
            <path
              d="M10 3L4.5 8.5L2 6"
              stroke="white"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        )}
      </div>

      {/* Favicon */}
      <img
        src={getFaviconSrc(tab)}
        alt=""
        style={{ width: "18px", height: "18px", borderRadius: "4px" }}
        onError={(e) => {
          // Swap to the domain fallback once; clearing onerror prevents a loop
          const img = e.currentTarget;
          img.onerror = null;
          img.src = getFaviconSrc({ favIconUrl: null, url: tab.url });
        }}
      />

      {/* Title */}
      <span
        style={{
          flex: 1,
          overflow: "hidden",
          textOverflow: "ellipsis",
          whiteSpace: "nowrap",
          fontSize: "14px",
          fontWeight: 400,
          color: selected ? "white" : "rgba(255, 255, 255, 0.8)",
        }}
      >
        {tab.title || "Untitled"}
      </span>
    </motion.div>
  );
}

export interface TabConflictPopoverProps {
  /** The ownership record of the conflicting window */
  ownerRecord: WindowOwnershipRecord;
  /** Current window ID */
  currentWindowId: number;
  /** Callback when user ignores the conflict */
  onIgnore: () => void;
  /** Callback when user successfully moves tabs (popover should close) */
  onMoveComplete: () => void;
  /** Position offset from anchor - IGNORED in favor of centered modal */
  anchorRect?: DOMRect;
}

export function TabConflictPopover({
  ownerRecord,
  currentWindowId,
  onIgnore,
  onMoveComplete,
}: TabConflictPopoverProps) {
  const [tabs, setTabs] = useState<chrome.tabs.Tab[]>([]);
  const [selectedTabIds, setSelectedTabIds] = useState<Set<number>>(new Set());
  const [loading, setLoading] = useState(true);

  // Load tabs from the owner window
  useEffect(() => {
    async function loadTabs() {
      setLoading(true);
      const windowTabs =
        await WindowOwnershipService.getOwnerWindowTabs(ownerRecord);
      setTabs(windowTabs);
      // Select all by default
      setSelectedTabIds(new Set(windowTabs.map((t) => t.id!).filter(Boolean)));
      setLoading(false);
    }
    loadTabs();
  }, [ownerRecord]);

  // Handle "Go to window" action
  const handleGoToWindow = async () => {
    await WindowOwnershipService.focusOwnerWindow(ownerRecord);
    onIgnore(); // Close the popover
  };

  // Handle tab selection toggle
  const toggleTabSelection = (tabId: number) => {
    setSelectedTabIds((prev) => {
      const next = new Set(prev);
      if (next.has(tabId)) {
        next.delete(tabId);
      } else {
        next.add(tabId);
      }
      return next;
    });
  };

  const handleMoveTabs = async () => {
    const tabIds = Array.from(selectedTabIds);

    // 1. Take ownership FIRST to prevent race condition where the old window
    // syncs "empty state" when it detects tabs leaving.
    // By claiming ownership first, the old window's useTabSync guard will kick in.
    const currentTab = await chrome.tabs.getCurrent();
    if (currentTab?.id) {
      await WindowOwnershipService.registerWorkspaceOwnership(
        ownerRecord.workspaceId,
        currentWindowId,
        currentTab.id,
      );
    }

    // 2. Move tabs to this window
    if (tabIds.length > 0) {
      await WindowOwnershipService.moveTabsToCurrentWindow(
        tabIds,
        currentWindowId,
      );
    }

    // 3. Trigger Adopt Mode switch to save the new state
    onMoveComplete();
  };

  const renderTabList = () => {
    // eslint-disable-next-line no-console
    console.log("Rendering", { loading, tabs: tabs.length });
    if (loading) {
      return (
        <div
          style={{
            padding: "32px",
            textAlign: "center",
            color: "rgba(255, 255, 255, 0.5)",
          }}
        >
          Loading tabs...
        </div>
      );
    }
    if (tabs.length === 0) {
      return (
        <div
          style={{
            padding: "32px",
            textAlign: "center",
            color: "rgba(255, 255, 255, 0.5)",
          }}
        >
          No tabs to move
        </div>
      );
    }
    return tabs.map((tab) => (
      <TabItem
        key={tab.id}
        tab={tab}
        selected={selectedTabIds.has(tab.id!)}
        onToggle={() => toggleTabSelection(tab.id!)}
      />
    ));
  };

  return (
    <AnimatePresence>
      <motion.div
        className="tab-conflict-backdrop"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
        style={{
          position: "fixed",
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          backgroundColor: "rgba(10, 14, 30, 0.32)",
          backdropFilter: "blur(4px)",
          zIndex: 9999,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
        onClick={onIgnore}
      >
        <motion.div
          className="tab-conflict-popover glass-menu"
          initial={{ opacity: 0, y: 20, scale: 0.95 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, scale: 0.95 }}
          transition={{ duration: 0.2, ease: "easeOut" }}
          onClick={(e: React.MouseEvent) => e.stopPropagation()}
          style={{
            width: "400px",
            // Dark-pinned surface so the popover's white text stays legible
            // regardless of theme (the dashboard is light-themed; .glass-menu's
            // --glass-bg-strong would otherwise resolve light here). The class
            // still supplies the blur, border, and tinted shadow.
            backgroundColor: "rgba(20, 23, 30, 0.62)",
            borderRadius: "18px", // Workona Pill Radius
            overflow: "hidden",
          }}
          role="dialog"
          aria-label="Tabs from another window"
        >
          {/* Header */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              padding: "20px 24px",
              borderBottom: "1px solid rgba(255, 255, 255, 0.1)",
            }}
          >
            <div
              style={{ display: "flex", flexDirection: "column", gap: "4px" }}
            >
              <span
                style={{ fontWeight: 600, fontSize: "16px", color: "white" }}
              >
                Tabs from another window
              </span>
              <span
                style={{ fontSize: "12px", color: "rgba(255, 255, 255, 0.5)" }}
              >
                Select tabs to move to this window
              </span>
            </div>

            <button
              onClick={handleGoToWindow}
              style={{
                background: "rgba(255, 255, 255, 0.05)",
                border: "none",
                borderRadius: "8px",
                padding: "6px 10px",
                color: "rgba(255, 255, 255, 0.7)",
                cursor: "pointer",
                display: "flex",
                alignItems: "center",
                gap: "6px",
                fontSize: "12px",
                fontWeight: 500,
                transition: "background 0.2s",
              }}
              title="Focus the other window"
            >
              Go to window
              <svg
                width="12"
                height="12"
                viewBox="0 0 12 12"
                fill="currentColor"
              >
                <path d="M10 2v5h-1V3.7l-5.6 5.6-.7-.7L8.3 3H5V2h5z" />
              </svg>
            </button>
          </div>

          {/* Tab list */}
          <div
            style={{
              maxHeight: "280px",
              overflowY: "auto",
              padding: "12px 8px",
            }}
          >
            {renderTabList()}
          </div>

          {/* Footer */}
          <div
            style={{
              display: "flex",
              justifyContent: "flex-end",
              gap: "12px",
              padding: "16px 24px",
              borderTop: "1px solid rgba(255, 255, 255, 0.1)",
              backgroundColor: "rgba(0, 0, 0, 0.2)",
            }}
          >
            <button
              onClick={onIgnore}
              style={{
                padding: "10px 20px",
                background: "transparent",
                border: "none",
                color: "rgba(255, 255, 255, 0.7)",
                cursor: "pointer",
                fontSize: "14px",
                fontWeight: 500,
              }}
            >
              Ignore
            </button>
            <motion.button
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.98 }}
              onClick={handleMoveTabs}
              disabled={selectedTabIds.size === 0}
              style={{
                padding: "10px 24px",
                border: "none",
                borderRadius: "18px", // Workona Pill Radius
                background: "var(--color-primary)",
                color: "white",
                cursor: selectedTabIds.size === 0 ? "not-allowed" : "pointer",
                fontSize: "14px",
                fontWeight: 600,
                opacity: selectedTabIds.size === 0 ? 0.5 : 1,
                boxShadow: "0 4px 12px rgba(51, 112, 255, 0.3)",
              }}
            >
              Move {selectedTabIds.size} tab
              {selectedTabIds.size !== 1 ? "s" : ""} here
            </motion.button>
          </div>
        </motion.div>
      </motion.div>
    </AnimatePresence>
  );
}

export default TabConflictPopover;
