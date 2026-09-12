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
 * Custom hook for Resource and Section management in the Dashboard
 *
 * Handles CRUD operations for resources and sections with optimistic updates.
 */

import { useState } from "react";
import type { Workspace } from "../../types";
import { TabService } from "../../services/tabs";
import { WorkspaceService } from "../../services/workspace";
import { StorageService } from "../../services/storage";

export interface UseResourceHandlersProps {
  activeWorkspace: Workspace | null;
  setActiveWorkspaceData: (ws: Workspace) => void;
  loadWorkspaces: () => void;
}

export interface UseResourceHandlersReturn {
  // Resource state
  showAddResource: boolean;
  setShowAddResource: (show: boolean) => void;
  newResourceUrl: string;
  setNewResourceUrl: (url: string) => void;
  newResourceTitle: string;
  setNewResourceTitle: (title: string) => void;
  targetSectionId: string | null;
  setTargetSectionId: (id: string | null) => void;
  // Section state
  showAddSection: boolean;
  setShowAddSection: (show: boolean) => void;
  newSectionTitle: string;
  setNewSectionTitle: (title: string) => void;
  // Handlers
  handleCreateSection: () => Promise<void>;
  handleAddResource: () => Promise<void>;
  handleOpenResource: (url: string) => Promise<void>;
  handleCloseTab: (tabId: number, tabUrl: string) => Promise<void>;
}

export const useResourceHandlers = ({
  activeWorkspace,
  setActiveWorkspaceData,
  loadWorkspaces,
}: UseResourceHandlersProps): UseResourceHandlersReturn => {
  // Resource state
  const [showAddResource, setShowAddResource] = useState(false);
  const [newResourceUrl, setNewResourceUrl] = useState("");
  const [newResourceTitle, setNewResourceTitle] = useState("");
  const [targetSectionId, setTargetSectionId] = useState<string | null>(null);

  // Section state
  const [showAddSection, setShowAddSection] = useState(false);
  const [newSectionTitle, setNewSectionTitle] = useState("");

  const handleCreateSection = async () => {
    if (activeWorkspace && newSectionTitle) {
      // Optimistic update
      const newSection = {
        id: `section_${Date.now()}`,
        title: newSectionTitle,
        resources: [],
      };

      const updatedWorkspace = {
        ...activeWorkspace,
        sections: [...(activeWorkspace.sections || []), newSection],
      };
      setActiveWorkspaceData(updatedWorkspace);

      const updatedWs = await WorkspaceService.addSection(
        activeWorkspace.id,
        newSectionTitle,
      );
      setActiveWorkspaceData(updatedWs);
      setNewSectionTitle("");
      setShowAddSection(false);
    }
  };

  const handleAddResource = async () => {
    if (activeWorkspace && newResourceUrl) {
      const resourceData = {
        title: newResourceTitle || "New Resource",
        url: newResourceUrl,
      };

      if (targetSectionId) {
        await WorkspaceService.addResourceToSection(
          activeWorkspace.id,
          targetSectionId,
          resourceData,
        );
      } else {
        await WorkspaceService.addResource(activeWorkspace.id, resourceData);
      }

      setShowAddResource(false);
      setNewResourceTitle("");
      setNewResourceUrl("");
      setTargetSectionId(null);
      loadWorkspaces();
    }
  };

  const handleOpenResource = async (url: string) => {
    // Check if tab is already open with this URL
    const tabs = await TabService.getCurrentTabs();
    const existingTab = tabs.find((t) => t.url === url || t.url === `${url}/`);
    if (existingTab && existingTab.id) {
      await TabService.activateTab(existingTab.id);
    } else {
      // Create and activate
      const newTab = await chrome.tabs.create({ url, active: true });

      // Optimistic update for Active Tabs list
      if (activeWorkspace && newTab.id) {
        let optimisticTitle = "Untitled";
        try {
          optimisticTitle = new URL(url).hostname;
        } catch {
          /* ignore invalid url */
        }

        const optimisticTab = {
          id: newTab.id,
          url: newTab.url || url,
          title:
            newTab.title && newTab.title !== "Untitled"
              ? newTab.title
              : optimisticTitle,
          favIconUrl: newTab.favIconUrl,
          active: true,
          pinned: false,
          index: newTab.index,
        };

        const updatedTabs = [...activeWorkspace.tabs, optimisticTab];
        setActiveWorkspaceData({ ...activeWorkspace, tabs: updatedTabs });

        // Force a sync from the actual browser state
        await WorkspaceService.saveCurrentTabsToWorkspace(activeWorkspace.id);
      }
    }
  };

  const handleCloseTab = async (tabId: number, tabUrl: string) => {
    if (!activeWorkspace) return;

    // eslint-disable-next-line no-console
    console.log("[handleCloseTab] START", { tabId, tabUrl });

    const settings = await StorageService.getSettings();
    // eslint-disable-next-line no-console
    console.log("[handleCloseTab] Settings:", {
      tabCloseMode: settings.tabCloseMode,
    });

    // Optimistic UI update - remove tab from workspace data immediately
    const newTabs = activeWorkspace.tabs.filter((t) => t.id !== tabId);
    setActiveWorkspaceData({ ...activeWorkspace, tabs: newTabs });

    let closed = false;

    // In hybrid mode: ALWAYS use URL matching (stored IDs are unreliable)
    if (settings.tabCloseMode === "hybrid" && tabUrl) {
      // eslint-disable-next-line no-console
      console.log("[handleCloseTab] Using URL-first approach for:", tabUrl);
      try {
        const currentTabs = await chrome.tabs.query({ currentWindow: true });
        // eslint-disable-next-line no-console
        console.log(
          "[handleCloseTab] Current tabs:",
          currentTabs.map((t) => ({ id: t.id, url: t.url?.substring(0, 50) })),
        );
        const matchingTabs = currentTabs.filter((t) => t.url === tabUrl);
        // eslint-disable-next-line no-console
        console.log("[handleCloseTab] Matching tabs:", matchingTabs.length);

        if (matchingTabs.length >= 1 && matchingTabs[0].id) {
          // eslint-disable-next-line no-console
          console.log(
            "[handleCloseTab] Closing tab by URL:",
            matchingTabs[0].id,
          );
          await TabService.closeTabs([matchingTabs[0].id]);
          closed = true;
          if (matchingTabs.length > 1) {
            // eslint-disable-next-line no-console
            console.warn(
              `[handleCloseTab] Multiple tabs (${matchingTabs.length}) with URL, closed first match`,
            );
          }
        } else {
          // eslint-disable-next-line no-console
          console.log(
            "[handleCloseTab] No matching tabs found for URL, tab may be closed",
          );
        }
      } catch (err) {
        // eslint-disable-next-line no-console
        console.error("[handleCloseTab] URL matching failed:", err);
      }
    } else {
      // In id-only mode: use stored tab ID directly
      // eslint-disable-next-line no-console
      console.log("[handleCloseTab] Using ID-only approach:", tabId);
      try {
        await TabService.closeTabs([tabId]);
        closed = true;
        // eslint-disable-next-line no-console
        console.log("[handleCloseTab] Closed using stored ID");
      } catch (err) {
        // eslint-disable-next-line no-console
        console.log("[handleCloseTab] Stored ID failed:", err);
      }
    }

    // eslint-disable-next-line no-console
    console.log("[handleCloseTab] END", { closed });

    // Persist workspace data update
    await WorkspaceService.updateWorkspace(activeWorkspace.id, {
      tabs: newTabs,
    });
  };

  return {
    // Resource state
    showAddResource,
    setShowAddResource,
    newResourceUrl,
    setNewResourceUrl,
    newResourceTitle,
    setNewResourceTitle,
    targetSectionId,
    setTargetSectionId,
    // Section state
    showAddSection,
    setShowAddSection,
    newSectionTitle,
    setNewSectionTitle,
    // Handlers
    handleCreateSection,
    handleAddResource,
    handleOpenResource,
    handleCloseTab,
  };
};
