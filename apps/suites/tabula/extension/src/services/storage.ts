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
 * Storage service for managing local and sync storage
 */

import type { Workspace, ExtensionSettings, SpaceGroup } from "../types";

export class StorageService {
  private static readonly WORKSPACES_KEY = "tabula_workspaces";

  private static readonly SETTINGS_KEY = "tabula_settings";

  private static readonly ACTIVE_WORKSPACE_KEY = "tabula_active_workspace";

  private static readonly SPACE_GROUPS_KEY = "tabula_space_groups";

  /**
   * Get all workspaces from storage
   */
  static async getWorkspaces(): Promise<Workspace[]> {
    try {
      const result = await chrome.storage.local.get(this.WORKSPACES_KEY);
      return (result[this.WORKSPACES_KEY] as Workspace[] | undefined) || [];
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to get workspaces:", error);
      return [];
    }
  }

  /**
   * Save workspaces to storage
   */
  static async saveWorkspaces(workspaces: Workspace[]): Promise<void> {
    try {
      await chrome.storage.local.set({ [this.WORKSPACES_KEY]: workspaces });
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to save workspaces:", error);
      throw error;
    }
  }

  /**
   * Get workspace by ID
   */
  static async getWorkspaceById(id: string): Promise<Workspace | undefined> {
    const workspaces = await this.getWorkspaces();
    return workspaces.find((w) => w.id === id);
  }

  /**
   * Get active workspace ID
   */
  static async getActiveWorkspaceId(): Promise<string | null> {
    try {
      const result = await chrome.storage.local.get(this.ACTIVE_WORKSPACE_KEY);
      return (result[this.ACTIVE_WORKSPACE_KEY] as string | undefined) || null;
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to get active workspace:", error);
      return null;
    }
  }

  /**
   * Set active workspace ID
   */
  static async setActiveWorkspaceId(id: string | null): Promise<void> {
    try {
      if (id === null) {
        await chrome.storage.local.remove(this.ACTIVE_WORKSPACE_KEY);
      } else {
        await chrome.storage.local.set({ [this.ACTIVE_WORKSPACE_KEY]: id });
      }
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to set active workspace:", error);
      throw error;
    }
  }

  /**
   * Get extension settings
   */
  static async getSettings(): Promise<ExtensionSettings> {
    try {
      const result = await chrome.storage.local.get(this.SETTINGS_KEY);
      return (
        (result[this.SETTINGS_KEY] as ExtensionSettings | undefined) || {
          autoSuspend: false,
          suspendAfterMinutes: 30,
          syncEnabled: false,
          theme: "auto",
          autoSave: true,
          tabCloseMode: "hybrid",
          onboardingCompleted: false,
        }
      );
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to get settings:", error);
      return {
        autoSuspend: false,
        suspendAfterMinutes: 30,
        syncEnabled: false,
        theme: "auto",
        autoSave: true,
        tabCloseMode: "hybrid",
        onboardingCompleted: false,
      };
    }
  }

  /**
   * Save extension settings
   */
  static async saveSettings(settings: ExtensionSettings): Promise<void> {
    try {
      await chrome.storage.local.set({ [this.SETTINGS_KEY]: settings });
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to save settings:", error);
      throw error;
    }
  }

  /**
   * Get all space groups from storage
   */
  static async getSpaceGroups(): Promise<SpaceGroup[]> {
    try {
      const result = await chrome.storage.local.get(this.SPACE_GROUPS_KEY);
      return (result[this.SPACE_GROUPS_KEY] as SpaceGroup[] | undefined) || [];
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to get space groups:", error);
      return [];
    }
  }

  /**
   * Save space groups to storage
   */
  static async saveSpaceGroups(groups: SpaceGroup[]): Promise<void> {
    try {
      await chrome.storage.local.set({ [this.SPACE_GROUPS_KEY]: groups });
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to save space groups:", error);
      throw error;
    }
  }

  /**
   * Clear all storage (for testing/debugging)
   */
  static async clearAll(): Promise<void> {
    try {
      await chrome.storage.local.clear();
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to clear storage:", error);
      throw error;
    }
  }
}
