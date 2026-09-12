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
 * Workspace store using Zustand
 */

import { create } from "zustand";
import type {
  Workspace,
  WorkspaceCreateInput,
  WorkspaceUpdateInput,
  SpaceGroup,
} from "../types";
import { WorkspaceService } from "../services/workspace";

interface WorkspaceStore {
  workspaces: Workspace[];
  spaceGroups: SpaceGroup[];
  activeWorkspaceId: string | null;
  loading: boolean;
  error: string | null;

  // Actions
  loadWorkspaces: () => Promise<void>;
  loadSpaceGroups: () => Promise<void>;
  createWorkspace: (input: WorkspaceCreateInput) => Promise<Workspace>;
  updateWorkspace: (
    id: string,
    input: WorkspaceUpdateInput,
  ) => Promise<Workspace>;
  deleteWorkspace: (id: string) => Promise<void>;
  saveCurrentTabs: (id: string) => Promise<void>;
  restoreTabs: (
    id: string,
    options?: { inNewWindow?: boolean; closeCurrentTabs?: boolean },
  ) => Promise<void>;
  switchWorkspace: (id: string) => Promise<void>;
  setActiveWorkspace: (id: string | null) => void;
  createSpaceGroup: (title: string) => Promise<SpaceGroup>;
  deleteSpaceGroup: (groupId: string) => Promise<void>;
  updateSpaceGroup: (
    groupId: string,
    updates: { title?: string; color?: string | null },
  ) => Promise<void>;
  toggleSpaceGroupCollapse: (groupId: string) => Promise<void>;
  reorderWorkspaces: (workspaces: Workspace[]) => Promise<void>;
  moveWorkspaceToGroup: (
    workspaceId: string,
    groupId: string | null,
  ) => Promise<void>;
  reorderSpaceGroups: (groups: SpaceGroup[]) => Promise<void>;
  reorderSections: (
    workspaceId: string,
    sections: Workspace["sections"],
  ) => Promise<void>;
}

export const useWorkspaceStore = create<WorkspaceStore>((set, get) => ({
  workspaces: [],
  spaceGroups: [],
  activeWorkspaceId: null,
  loading: false,
  error: null,

  loadWorkspaces: async () => {
    set({ loading: true, error: null });
    try {
      const workspaces = await WorkspaceService.getAllWorkspaces();
      // Sort workspaces by position (with defensive check for undefined)
      const sortedWorkspaces = (workspaces || []).sort(
        (a, b) => (a.position || 0) - (b.position || 0),
      );

      const activeWorkspace = await WorkspaceService.getActiveWorkspace();
      const spaceGroups = await WorkspaceService.getSpaceGroups();
      // Sort space groups by position (with defensive check for undefined)
      const sortedSpaceGroups = (spaceGroups || []).sort(
        (a, b) => (a.position || 0) - (b.position || 0),
      );

      set({
        workspaces: sortedWorkspaces,
        spaceGroups: sortedSpaceGroups,
        activeWorkspaceId: activeWorkspace?.id || null,
        loading: false,
      });
    } catch (error) {
      set({
        error: error instanceof Error ? error.message : "Failed to load",
        loading: false,
      });
    }
  },

  loadSpaceGroups: async () => {
    try {
      const spaceGroups = await WorkspaceService.getSpaceGroups();
      spaceGroups.sort((a, b) => (a.position || 0) - (b.position || 0));
      set({ spaceGroups });
    } catch (error) {
      console.error("Failed to load space groups:", error);
    }
  },

  createWorkspace: async (input: WorkspaceCreateInput) => {
    set({ loading: true, error: null });
    try {
      const workspace = await WorkspaceService.createWorkspace(input);
      // Check if workspace already exists to prevent duplicates from race condition with storage listener
      const exists = get().workspaces.some((w) => w.id === workspace.id);

      if (!exists) {
        set({
          workspaces: [...get().workspaces, workspace],
          loading: false,
        });
      } else {
        set({ loading: false });
      }
      return workspace;
    } catch (error) {
      set({
        error: error instanceof Error ? error.message : "Failed to create",
        loading: false,
      });
      throw error;
    }
  },

  updateWorkspace: async (id: string, input: WorkspaceUpdateInput) => {
    set({ loading: true, error: null });
    try {
      const updated = await WorkspaceService.updateWorkspace(id, input);
      set({
        workspaces: get().workspaces.map((w) => (w.id === id ? updated : w)),
        loading: false,
      });
      return updated;
    } catch (error) {
      set({
        error: error instanceof Error ? error.message : "Failed to update",
        loading: false,
      });
      throw error;
    }
  },

  deleteWorkspace: async (id: string) => {
    set({ loading: true, error: null });
    try {
      await WorkspaceService.deleteWorkspace(id);
      set({
        workspaces: get().workspaces.filter((w) => w.id !== id),
        activeWorkspaceId:
          get().activeWorkspaceId === id ? null : get().activeWorkspaceId,
        loading: false,
      });
    } catch (error) {
      set({
        error: error instanceof Error ? error.message : "Failed to delete",
        loading: false,
      });
      throw error;
    }
  },

  saveCurrentTabs: async (id: string) => {
    set({ loading: true, error: null });
    try {
      const updated = await WorkspaceService.saveCurrentTabsToWorkspace(id);
      set({
        workspaces: get().workspaces.map((w) => (w.id === id ? updated : w)),
        loading: false,
      });
    } catch (error) {
      set({
        error: error instanceof Error ? error.message : "Failed to save tabs",
        loading: false,
      });
      throw error;
    }
  },

  restoreTabs: async (id: string, options = {}) => {
    set({ loading: true, error: null });
    try {
      await WorkspaceService.restoreWorkspaceTabs(id, options);
      set({ activeWorkspaceId: id, loading: false });
    } catch (error) {
      set({
        error:
          error instanceof Error ? error.message : "Failed to restore tabs",
        loading: false,
      });
      throw error;
    }
  },

  switchWorkspace: async (id: string) => {
    set({ loading: true, error: null });
    try {
      await WorkspaceService.switchToWorkspace(id);
      set({ activeWorkspaceId: id, loading: false });
    } catch (error) {
      set({
        error: error instanceof Error ? error.message : "Failed to switch",
        loading: false,
      });
      throw error;
    }
  },

  setActiveWorkspace: (id: string | null) => {
    set({ activeWorkspaceId: id });
    // NOTE: We intentionally do NOT persist to storage here.
    // This allows multi-window independence: each window can have its own
    // active workspace based on its URL, without affecting other windows.
    // Full workspace switches (with tab restore) still persist via switchWorkspace.
  },

  createSpaceGroup: async (title: string) => {
    try {
      const group = await WorkspaceService.createSpaceGroup(title);
      set({ spaceGroups: [...get().spaceGroups, group] });
      return group;
    } catch (error) {
      console.error("Failed to create space group:", error);
      throw error;
    }
  },

  deleteSpaceGroup: async (groupId: string) => {
    try {
      await WorkspaceService.deleteSpaceGroup(groupId);
      set({ spaceGroups: get().spaceGroups.filter((g) => g.id !== groupId) });
      // Reload workspaces to reflect ungrouped status
      const workspaces = await WorkspaceService.getAllWorkspaces();
      set({ workspaces });
    } catch (error) {
      console.error("Failed to delete space group:", error);
      throw error;
    }
  },

  toggleSpaceGroupCollapse: async (groupId: string) => {
    try {
      const updatedGroup =
        await WorkspaceService.toggleSpaceGroupCollapse(groupId);
      set({
        spaceGroups: get().spaceGroups.map((g) =>
          g.id === groupId ? updatedGroup : g,
        ),
      });
    } catch (error) {
      console.error("Failed to toggle space group:", error);
      throw error;
    }
  },

  updateSpaceGroup: async (
    groupId: string,
    updates: { title?: string; color?: string | null },
  ) => {
    try {
      const updatedGroup = await WorkspaceService.updateSpaceGroup(
        groupId,
        updates,
      );
      set({
        spaceGroups: get().spaceGroups.map((g) =>
          g.id === groupId ? updatedGroup : g,
        ),
      });
    } catch (error) {
      console.error("Failed to update space group:", error);
      throw error;
    }
  },

  reorderWorkspaces: async (workspaces: Workspace[]) => {
    // Optimistic update
    set({ workspaces });
    try {
      await WorkspaceService.updateWorkspaceOrders(workspaces);
    } catch (error) {
      console.error("Failed to save workspace order:", error);
      // Revert or reload? Reloading is safer
      await get().loadWorkspaces();
    }
  },

  moveWorkspaceToGroup: async (workspaceId: string, groupId: string | null) => {
    try {
      await WorkspaceService.moveWorkspaceToGroup(workspaceId, groupId);
      // Reload to get updated order/groups
      await get().loadWorkspaces();
    } catch (error: unknown) {
      console.error("Failed to move workspace:", error);
      throw error;
    }
  },

  reorderSpaceGroups: async (groups: SpaceGroup[]) => {
    // Optimistic update
    set({ spaceGroups: groups });
    try {
      await WorkspaceService.updateSpaceGroupOrders(groups);
    } catch (error: unknown) {
      console.error("Failed to save space group order:", error);
      await get().loadSpaceGroups();
    }
  },

  reorderSections: async (
    workspaceId: string,
    sections: Workspace["sections"],
  ) => {
    // Optimistic update
    const { workspaces } = get();
    const wsIndex = workspaces.findIndex((w) => w.id === workspaceId);
    if (wsIndex !== -1) {
      const updatedWorkspace = { ...workspaces[wsIndex], sections };
      const updatedWorkspaces = [...workspaces];
      updatedWorkspaces[wsIndex] = updatedWorkspace;
      set({ workspaces: updatedWorkspaces });
    }

    try {
      await WorkspaceService.updateWorkspace(workspaceId, { sections });
    } catch (error: unknown) {
      console.error("Failed to save section order:", error);
      await get().loadWorkspaces();
    }
  },
}));
