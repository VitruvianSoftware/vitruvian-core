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
 * Workspace management service for CRUD operations
 *
 * Concurrency model:
 * - 'tabula_workspace_lock' (Web Locks) guards EVERY read-modify-write of the
 *   workspaces array and the space-groups array in chrome.storage.local.
 *   chrome.storage.local is shared across extension contexts (multiple
 *   dashboard windows, popup, background worker), so unlocked writes lose
 *   concurrent updates.
 * - withLock is NOT reentrant: a locked method must never call another locked
 *   method. Each public mutator takes the lock exactly once.
 * - Lock ordering: the workspace lock MAY be held while acquiring
 *   SyncService's queue lock (workspace -> queue); NEVER the reverse.
 * - SyncService.enqueue is durable once awaited — every enqueue here is
 *   awaited so a mutation does not resolve until its sync op is persisted.
 */

import type {
  Workspace,
  WorkspaceCreateInput,
  WorkspaceUpdateInput,
  SpaceGroup,
  Tab,
  TabGroup,
} from "../types";
import { StorageService } from "./storage";
import { TabService } from "./tabs";
import { ApiService } from "./api";
import { AuthService } from "./auth";
import { SyncService } from "./sync";
import type { SyncOperationMeta } from "./sync";
import { extractLeadingEmoji } from "../utils/emoji";

/**
 * Configuration constants - can be overridden via settings in future
 */
const WORKSPACE_CONFIG = {
  /** Maximum number of workspaces allowed (free tier) */
  MAX_WORKSPACES: 10,
};

/**
 * Normalize a user-entered resource URL into an absolute URL.
 *
 * The "Add resource" field is free text, so a user readily types a bare host
 * ("example.com") or pads it with whitespace. That is not a valid absolute URL:
 * `new URL()` throws on it (breaking the resource's title/"open" action) and the
 * API's resource schema would reject it — 400-ing the ENTIRE workspace PUT and
 * wedging sync for every item in the workspace. Trim, and prepend https:// when
 * no scheme is present, so every stored resource is a valid, openable URL.
 * Values that already carry a scheme (http:, https:, chrome:, about:, ...) are
 * left untouched.
 */
export function normalizeResourceUrl(url: string): string {
  const trimmed = url.trim();
  if (!trimmed) return trimmed;
  // RFC 3986 scheme: ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ) ":"
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(trimmed)) return trimmed;
  return `https://${trimmed}`;
}

export class WorkspaceService {
  /**
   * Generate a unique workspace ID
   */
  private static generateId(): string {
    return `ws_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * Queue a workspace save operation via SyncService.
   * Durable once awaited — callers must await.
   */
  private static async queueWorkspaceSync(
    workspace: Workspace,
    meta?: SyncOperationMeta,
  ): Promise<void> {
    if (await AuthService.getToken()) {
      await SyncService.enqueue({
        type: "workspace",
        action: "save",
        entityId: workspace.id,
        data: workspace,
        meta,
      });
    }
  }

  /**
   * Queue a spaceGroup save operation via SyncService.
   * Durable once awaited — callers must await.
   */
  private static async queueSpaceGroupSync(group: SpaceGroup): Promise<void> {
    if (await AuthService.getToken()) {
      await SyncService.enqueue({
        type: "spaceGroup",
        action: "save",
        entityId: group.id,
        data: group,
      });
    }
  }

  /**
   * Execute a callback under a lock to prevent race conditions.
   * NOT reentrant — never call a locked method from inside the callback.
   */
  private static async withLock<T>(callback: () => Promise<T>): Promise<T> {
    if (typeof navigator !== "undefined" && "locks" in navigator) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      return (navigator as any).locks.request(
        "tabula_workspace_lock",
        callback,
      );
    }
    return callback();
  }

  /**
   * Create a new workspace
   */
  static async createWorkspace(
    input: WorkspaceCreateInput,
  ): Promise<Workspace> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();

        // Check workspace limit
        if (workspaces.length >= WORKSPACE_CONFIG.MAX_WORKSPACES) {
          throw new Error(
            `Maximum number of workspaces reached (${WORKSPACE_CONFIG.MAX_WORKSPACES})`,
          );
        }

        const now = Date.now();
        const nextPosition =
          workspaces.length > 0
            ? Math.max(...workspaces.map((w) => w.position || 0)) + 1
            : 0;

        // Auto-detect emoji in title if icon logic allows
        const { name: inputName, icon: inputIcon } = input;
        let name = inputName;
        let icon = inputIcon || "📁";

        // If the icon is the default folder, we try to extract an emoji from the name
        if (icon === "📁") {
          const extracted = extractLeadingEmoji(name);
          if (extracted.emoji) {
            name = extracted.cleanTitle;
            icon = extracted.emoji;
          }
        }

        const newWorkspace: Workspace = {
          id: this.generateId(),
          name,
          description: input.description,
          color: input.color || "#4F46E5",
          icon,
          position: nextPosition,
          tabs: [],
          tabGroups: [],
          resources: [], // Keep for backward compatibility
          sections: [
            {
              id: this.generateId(),
              title: "Resources",
              resources: [],
            },
          ],
          notes: [],
          tasks: [],
          createdAt: now,
          updatedAt: now,
        };

        workspaces.push(newWorkspace);
        await StorageService.saveWorkspaces(workspaces);

        // Queue sync to API if logged in
        if (await AuthService.getToken()) {
          await SyncService.enqueue({
            type: "workspace",
            action: "save",
            entityId: newWorkspace.id,
            data: newWorkspace,
          });
        }

        return newWorkspace;
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error("Failed to create workspace:", error);
        throw error;
      }
    });
  }

  /**
   * Update a workspace
   */
  static async updateWorkspace(
    id: string,
    input: WorkspaceUpdateInput,
  ): Promise<Workspace> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();
        const index = workspaces.findIndex((w) => w.id === id);

        if (index === -1) {
          throw new Error("Workspace not found");
        }

        const currentWorkspace = workspaces[index];
        let { name, icon } = input;

        // Auto-detect emoji if name is being updated
        if (name && name !== currentWorkspace.name) {
          // If icon is NOT provided (undefined), check if we should extract from name
          // Logic: If user provides a name with emoji, they likely want it as icon,
          // UNLESS they also explicitly provided an icon in this update.
          if (icon === undefined) {
            const extracted = extractLeadingEmoji(name);
            if (extracted.emoji) {
              name = extracted.cleanTitle;
              icon = extracted.emoji;
            }
          }
        }

        const updatedWorkspace: Workspace = {
          ...currentWorkspace,
          ...input, // specific overrides
          name: name ?? currentWorkspace.name, // use processed name or existing
          icon: icon ?? currentWorkspace.icon, // use processed icon or existing
          updatedAt: Math.max(
            Date.now(),
            (currentWorkspace.updatedAt || 0) + 1,
          ),
        };

        workspaces[index] = updatedWorkspace;
        await StorageService.saveWorkspaces(workspaces);

        // Queue sync to API if logged in
        if (await AuthService.getToken()) {
          await SyncService.enqueue({
            type: "workspace",
            action: "save",
            entityId: updatedWorkspace.id,
            data: updatedWorkspace,
          });
        }

        return updatedWorkspace;
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error("Failed to update workspace:", error);
        throw error;
      }
    });
  }

  /**
   * Update workspace tabs and tab groups (for real-time sync)
   * This is a specialized method for the useTabSync hook to update tabs and groups efficiently.
   */
  static async updateWorkspaceTabs(
    id: string,
    tabs: Tab[],
    tabGroups: TabGroup[],
  ): Promise<void> {
    return this.withLock(async () => {
      try {
        // eslint-disable-next-line no-console
        console.log("[WorkspaceService.updateWorkspaceTabs] Received:", {
          workspaceId: id,
          tabsCount: tabs.length,
          tabGroupsCount: tabGroups.length,
          tabGroupsData: tabGroups.map((g) => ({ id: g.id, title: g.title })),
          tabsWithGroupId: tabs.filter((t) => t.groupId).length,
        });

        const workspaces = await StorageService.getWorkspaces();
        const index = workspaces.findIndex((w) => w.id === id);

        if (index === -1) {
          // Workspace might be deleted, silently ignore
          return;
        }

        workspaces[index] = {
          ...workspaces[index],
          tabs,
          tabGroups,
          updatedAt: Math.max(
            Date.now(),
            (workspaces[index].updatedAt || 0) + 1,
          ),
        };

        // eslint-disable-next-line no-console
        console.log(
          "[WorkspaceService.updateWorkspaceTabs] Saving workspace:",
          {
            name: workspaces[index].name,
            tabsCount: workspaces[index].tabs?.length,
            tabGroupsCount: workspaces[index].tabGroups?.length,
          },
        );

        await StorageService.saveWorkspaces(workspaces);

        // Queue sync to API if logged in. 'tabSync' source renews the
        // server-side active-device lease instead of claiming it.
        if (await AuthService.getToken()) {
          await SyncService.enqueue({
            type: "workspace",
            action: "save",
            entityId: workspaces[index].id,
            data: workspaces[index],
            meta: { source: "tabSync" },
          });
        }
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error("Failed to update workspace tabs:", error);
        // Don't throw - tab sync errors shouldn't crash the UI
      }
    });
  }

  /**
   * Delete a workspace
   */
  static async deleteWorkspace(id: string): Promise<void> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();
        const filtered = workspaces.filter((w) => w.id !== id);

        if (filtered.length === workspaces.length) {
          throw new Error("Workspace not found");
        }

        await StorageService.saveWorkspaces(filtered);

        // Queue delete sync to API if logged in
        if (await AuthService.getToken()) {
          await SyncService.enqueue({
            type: "workspace",
            action: "delete",
            entityId: id,
          });
        }

        // Clear active workspace if it was deleted
        const activeId = await StorageService.getActiveWorkspaceId();
        if (activeId === id) {
          await StorageService.setActiveWorkspaceId(null);
        }
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error("Failed to delete workspace:", error);
        throw error;
      }
    });
  }

  /**
   * Get all workspaces
   *
   * The remote fetch happens OUTSIDE the lock (never hold the workspace lock
   * across network I/O); the merge+save runs UNDER the lock against
   * freshly-loaded local state so concurrent mutations are never clobbered.
   */
  static async getAllWorkspaces(): Promise<Workspace[]> {
    // Try to fetch from API if logged in
    try {
      if (await AuthService.getToken()) {
        const remoteWorkspaces = (await ApiService.getWorkspaces()) || [];

        // Check if we should force using remote data (set after backup restore)
        // The flag stores a timestamp - force remote if within 10 seconds of that timestamp
        const forceRemoteResult = await chrome.storage.local.get(
          "tabula_force_remote_until",
        );
        const forceRemoteUntil = forceRemoteResult.tabula_force_remote_until as
          | number
          | undefined;
        const now = Date.now();
        const forceRemote = forceRemoteUntil && now < forceRemoteUntil;

        if (forceRemote) {
          // Use remote data directly, skip conflict resolution
          await this.withLock(() =>
            StorageService.saveWorkspaces(remoteWorkspaces),
          );
          return remoteWorkspaces;
        }

        return await this.withLock(async () => {
          // Re-read local state under the lock — it may have changed since
          // the network round-trip started
          const localWorkspaces = await StorageService.getWorkspaces();
          const localWinners: Workspace[] = [];

          // Workspaces with an un-acked local save queued. They must NOT lose to
          // a remote copy that only looks "newer" because the server
          // auto-stamps updated_at on every write (Prisma @updatedAt): a PUT
          // for an EARLIER edit that lands first can outrank the client clock
          // for a LATER local edit the server hasn't seen yet, dropping it
          // (#51). updatedAt/version can't distinguish this from a genuine
          // remote edit — only the pending-save signal can.
          const pendingSaves =
            (await SyncService.getPendingSaveIds("workspace")) ??
            new Set<string>();

          // Conflict Resolution: per-entity Last Write Wins, except un-acked
          // local edits always win their own content (the queued PUT converges
          // the server).
          const mergedWorkspaces = remoteWorkspaces.map((remoteWs) => {
            const localWs = localWorkspaces.find((l) => l.id === remoteWs.id);

            // Normalize timestamps to handle potential string/ISO formats from API
            const localTime = new Date(localWs?.updatedAt || 0).getTime();
            const remoteTime = new Date(remoteWs.updatedAt || 0).getTime();
            const localHasUnsyncedEdits =
              !!localWs && pendingSaves.has(remoteWs.id);

            // Prefer local when it is newer/equal OR has un-acked edits queued —
            // but keep the server's sync metadata so the next PUT carries the
            // right baseVersion.
            if (localWs && (localTime >= remoteTime || localHasUnsyncedEdits)) {
              const kept: Workspace = {
                ...localWs,
                version: remoteWs.version,
                activeDeviceId: remoteWs.activeDeviceId,
                activeDeviceSeenAt: remoteWs.activeDeviceSeenAt,
              };
              // Push when local content the server hasn't got must converge:
              // strictly-newer local, or un-acked edits. Re-pushing also
              // refreshes the queued op's baseVersion to the server's current
              // version, so it lands cleanly instead of 409-ing and rebasing
              // back into the same clobber.
              if (localTime > remoteTime || localHasUnsyncedEdits) {
                localWinners.push(kept);
              }
              return kept;
            }
            return remoteWs;
          });

          // Local-only workspaces: a defined `version` proves the workspace
          // existed on the server — missing remotely means it was deleted
          // there, so drop it locally (no resurrection). No `version` means
          // it never synced — keep it.
          const newLocalWorkspaces = localWorkspaces.filter(
            (l) =>
              !remoteWorkspaces.find((r) => r.id === l.id) &&
              l.version === undefined,
          );
          const finalWorkspaces = [...mergedWorkspaces, ...newLocalWorkspaces];

          // Update local cache
          await StorageService.saveWorkspaces(finalWorkspaces);

          // Lock ordering: workspace lock may be held while taking the sync
          // queue lock (workspace -> queue), never the reverse
          await Promise.all(
            localWinners.map((w) => this.queueWorkspaceSync(w)),
          );

          return finalWorkspaces;
        });
      }
    } catch (error) {
      console.error(
        "Failed to fetch workspaces from API, falling back to local:",
        error,
      );
    }
    return StorageService.getWorkspaces();
  }

  /**
   * Get workspace by ID
   */
  static async getWorkspaceById(id: string): Promise<Workspace | undefined> {
    return StorageService.getWorkspaceById(id);
  }

  /**
   * Bulk update workspace orders/groups.
   *
   * The passed array is a UI snapshot that may be stale — apply ONLY the
   * ordering fields (position, groupId) onto freshly-loaded storage state so
   * concurrent changes (new sections, notes, tabs...) are never clobbered.
   */
  static async updateWorkspaceOrders(workspaces: Workspace[]): Promise<void> {
    return this.withLock(async () => {
      try {
        const freshWorkspaces = await StorageService.getWorkspaces();
        const changed: Workspace[] = [];

        workspaces.forEach((incoming) => {
          const index = freshWorkspaces.findIndex((w) => w.id === incoming.id);
          if (index === -1) return;
          const current = freshWorkspaces[index];
          if (
            current.position === incoming.position &&
            current.groupId === incoming.groupId
          ) {
            return;
          }
          freshWorkspaces[index] = {
            ...current,
            position: incoming.position,
            groupId: incoming.groupId,
            updatedAt: Math.max(Date.now(), (current.updatedAt || 0) + 1),
          };
          changed.push(freshWorkspaces[index]);
        });

        await StorageService.saveWorkspaces(freshWorkspaces);

        try {
          await Promise.all(changed.map((w) => this.queueWorkspaceSync(w)));
        } catch (err) {
          console.error("Failed to sync workspace orders:", err);
        }
      } catch (error) {
        console.error("Failed to update workspace orders:", error);
        throw error;
      }
    });
  }

  /**
   * Save current tabs to a workspace
   */
  static async saveCurrentTabsToWorkspace(
    id: string,
    options: { claim?: boolean } = {},
  ): Promise<Workspace> {
    return this.withLock(() => this._saveCurrentTabsToWorkspace(id, options));
  }

  private static async _saveCurrentTabsToWorkspace(
    id: string,
    options: { claim?: boolean } = {},
  ): Promise<Workspace> {
    try {
      const workspaces = await StorageService.getWorkspaces();
      const index = workspaces.findIndex((w) => w.id === id);

      if (index === -1) {
        throw new Error("Workspace not found");
      }

      // Get tab groups first (reuse existing UUIDs when possible)
      const existingTabGroups = workspaces[index].tabGroups || [];
      const currentTabGroups =
        await TabService.getCurrentTabGroups(existingTabGroups);

      // Get tabs with groups passed for proper stable groupId mapping
      const currentTabs = await TabService.getCurrentTabs(currentTabGroups);

      // eslint-disable-next-line no-console
      console.log(
        "[_saveCurrentTabsToWorkspace] Current tabs:",
        currentTabs.map((t) => ({
          id: t.id,
          url: t.url?.substring(0, 50),
          groupId: t.groupId,
        })),
      );

      // Filter out pinned tabs, extension pages, and special pages
      const cleanTabs = currentTabs.filter((tab) => {
        // Skip pinned tabs (like the extension dashboard in production)
        if (tab.pinned) return false;
        // Skip extension pages (like the dashboard in E2E tests)
        if (tab.url.startsWith("chrome-extension://")) return false;
        // Skip about:blank and other special pages that shouldn't be saved
        if (tab.url === "about:blank" || tab.url.startsWith("about:"))
          return false;
        // Skip chrome:// pages
        if (tab.url.startsWith("chrome://")) return false;
        return true;
      });

      // eslint-disable-next-line no-console
      console.log(
        `[_saveCurrentTabsToWorkspace] Saving ${cleanTabs.length} tabs to workspace ${workspaces[index].name}:`,
        cleanTabs.map((t) => t.url?.substring(0, 50)),
      );

      // eslint-disable-next-line no-console
      console.log(
        `[_saveCurrentTabsToWorkspace] Saving ${currentTabGroups.length} tab groups to workspace ${workspaces[index].name}`,
      );

      // Defensive: If we detected groups but tabs have no groupIds, Chrome hasn't finished
      // assigning tabs to groups yet. Skip this save to avoid corrupting storage.
      const tabsWithGroupIds = cleanTabs.filter((t) => t.groupId).length;
      if (currentTabGroups.length > 0 && tabsWithGroupIds === 0) {
        // eslint-disable-next-line no-console
        console.log(
          "[_saveCurrentTabsToWorkspace] Skipping - groups detected but tabs have no groupIds yet",
        );
        return workspaces[index]; // Return current workspace without saving
      }

      workspaces[index].tabs = cleanTabs;
      workspaces[index].tabGroups = currentTabGroups;
      workspaces[index].updatedAt = Math.max(
        Date.now(),
        (workspaces[index].updatedAt || 0) + 1,
      );
      await StorageService.saveWorkspaces(workspaces);

      if (await AuthService.getToken()) {
        await SyncService.enqueue({
          type: "workspace",
          action: "save",
          entityId: workspaces[index].id,
          data: workspaces[index],
          // claim: become the primary device for this space. Without it a
          // tab-save from a non-primary device no-ops against the holder's
          // sticky lease (see WorkspaceService.updateWorkspace, server side).
          meta: options.claim ? { claimActiveDevice: true } : undefined,
        });
      }
      return workspaces[index];
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("Failed to save tabs to workspace:", error);
      throw error;
    }
  }

  /**
   * Add a resource to a workspace
   */
  static async addResource(
    workspaceId: string,
    resource: { title: string; url: string; faviconUrl?: string },
  ): Promise<Workspace> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();
        const index = workspaces.findIndex((w) => w.id === workspaceId);

        if (index === -1) {
          throw new Error("Workspace not found");
        }

        const newResource = {
          id: `res_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
          title: resource.title,
          url: normalizeResourceUrl(resource.url),
          faviconUrl: resource.faviconUrl,
          createdAt: Date.now(),
        };

        // Add to first section, or create one if none exist
        if (
          !workspaces[index].sections ||
          workspaces[index].sections.length === 0
        ) {
          workspaces[index].sections = [
            {
              id: this.generateId(),
              title: "Resources",
              resources: [newResource],
            },
          ];
        } else {
          workspaces[index].sections[0].resources.push(newResource);
        }

        workspaces[index].updatedAt = Math.max(
          Date.now(),
          (workspaces[index].updatedAt || 0) + 1,
        );
        await StorageService.saveWorkspaces(workspaces);

        await this.queueWorkspaceSync(workspaces[index]);
        return workspaces[index];
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error("Failed to add resource:", error);
        throw error;
      }
    });
  }

  /**
   * Remove a resource from a workspace
   */
  static async removeResource(
    workspaceId: string,
    resourceId: string,
  ): Promise<Workspace> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();
        const index = workspaces.findIndex((w) => w.id === workspaceId);

        if (index === -1) {
          throw new Error("Workspace not found");
        }

        // Remove from legacy resources array if present
        if (workspaces[index].resources) {
          workspaces[index].resources = workspaces[index].resources.filter(
            (r) => r.id !== resourceId,
          );
        }

        // Remove from sections
        if (workspaces[index].sections) {
          workspaces[index].sections = workspaces[index].sections.map(
            (section) => {
              if (section.resources) {
                return {
                  ...section,
                  resources: section.resources.filter(
                    (r) => r.id !== resourceId,
                  ),
                };
              }
              return section;
            },
          );
        }

        workspaces[index].updatedAt = Math.max(
          Date.now(),
          (workspaces[index].updatedAt || 0) + 1,
        );
        await StorageService.saveWorkspaces(workspaces);

        await this.queueWorkspaceSync(workspaces[index]);

        return workspaces[index];
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error("Failed to remove resource:", error);
        throw error;
      }
    });
  }

  /**
   * Restore tabs from a workspace
   */
  static async restoreWorkspaceTabs(
    id: string,
    options: {
      inNewWindow?: boolean;
      closeCurrentTabs?: boolean;
      /**
       * Restore this explicit set of tabs instead of the workspace's stored
       * session. Used by the cross-device "Apply" action to open only the
       * subset of the primary device's tabs the user selected.
       */
      tabs?: Tab[];
    } = {},
  ): Promise<void> {
    return this.withLock(async () => {
      try {
        // eslint-disable-next-line no-console
        console.log("[restoreWorkspaceTabs] START", { id, options });

        const workspace = await this.getWorkspaceById(id);
        if (!workspace) {
          throw new Error("Workspace not found");
        }

        // eslint-disable-next-line no-console
        console.log("[restoreWorkspaceTabs] Workspace found:", workspace.name);

        // 1. Identify tabs to close/hide (everything currently open except dashboard/extension)
        let tabsToClose: number[] = [];
        if (options.closeCurrentTabs && !options.inNewWindow) {
          // We query tabs manually here to get their IDs BEFORE opening new ones
          const currentTabs = await chrome.tabs.query({ currentWindow: true });

          // eslint-disable-next-line no-console
          console.log(
            "[restoreWorkspaceTabs] Current tabs:",
            currentTabs.map((t) => ({
              id: t.id,
              url: t.url,
              pinned: t.pinned,
            })),
          );

          tabsToClose = currentTabs
            .filter((t) => {
              // Only close tabs with valid IDs, not pinned, with a defined URL that's not an extension page
              if (!t.id || t.pinned) return false;
              if (!t.url) return false; // Don't close tabs without URLs (safety)
              const shouldClose = !t.url.startsWith("chrome-extension://");
              // eslint-disable-next-line no-console
              console.log(
                `[restoreWorkspaceTabs] Tab ${t.id} (${t.url?.substring(0, 50)}): shouldClose=${shouldClose}`,
              );
              return shouldClose;
            })
            .map((t) => t.id!);

          // eslint-disable-next-line no-console
          console.log("[restoreWorkspaceTabs] Tabs to close:", tabsToClose);
        }

        // 2. Open new tabs from the workspace (or an explicit override set, e.g.
        // the subset chosen in the cross-device "Apply" prompt).
        // Filter out extension pages (like the dashboard) to prevent duplication/loops
        const cleanTabs = (options.tabs ?? workspace.tabs ?? []).filter((tab) => {
          const url = tab.url || "";
          return (
            !url.startsWith("chrome-extension://") &&
            !url.includes("dashboard.html")
          );
        });

        // eslint-disable-next-line no-console
        console.log("[restoreWorkspaceTabs] Opening tabs:", cleanTabs.length);

        // We capture the openTabs result so we can (a) restore groups against the
        // exact created tabs (no index drift), (b) target the correct window for
        // the new-window case, and (c) preserve tabs that failed to open.
        const openResult = await TabService.openTabs(cleanTabs, {
          inNewWindow: options.inNewWindow,
        });
        // For the current-window case the target IS the current window
        const targetWindowId = openResult.windowId;

        // eslint-disable-next-line no-console
        console.log(
          "[restoreWorkspaceTabs] Opened new tabs, now closing old tabs",
        );

        // 3. Close the old tabs (now that new ones are open)
        // ALWAYS close tabs when switching workspaces for proper isolation
        // Even if switching to an empty workspace, we should close the previous workspace's tabs
        if (tabsToClose.length > 0) {
          // eslint-disable-next-line no-console
          console.log(
            "[restoreWorkspaceTabs] Calling TabService.closeTabs with:",
            tabsToClose,
          );
          await TabService.closeTabs(tabsToClose);
          // eslint-disable-next-line no-console
          console.log("[restoreWorkspaceTabs] Closed tabs successfully");
        }

        // 4. Restore tab groups using the EXACT tabs openTabs created (matched by
        // index, null where a tab failed) — no re-query, so a failed tab can't
        // shift every later index into the wrong group.
        const savedTabGroups = workspace.tabGroups || [];
        if (savedTabGroups.length > 0 && cleanTabs.length > 0) {
          // eslint-disable-next-line no-console
          console.log(
            "[restoreWorkspaceTabs] Restoring tab groups:",
            savedTabGroups.length,
          );
          await TabService.restoreTabGroupsFromCreated(
            cleanTabs,
            savedTabGroups,
            openResult.created,
          );
          // eslint-disable-next-line no-console
          console.log("[restoreWorkspaceTabs] Tab groups restored");
        }

        // 5. Reconcile the saved workspace with fresh Chrome tab IDs.
        // For the new-window case we MUST query the new window, not the current
        // one — otherwise we'd overwrite the workspace with the dashboard
        // window's tabs.
        const freshTabGroups = await TabService.getCurrentTabGroups(
          savedTabGroups,
          targetWindowId,
        );
        const freshTabs = await TabService.getCurrentTabs(
          freshTabGroups,
          targetWindowId,
        );
        const openedTabs = freshTabs.filter(
          (t) =>
            !t.pinned &&
            !t.url.startsWith("chrome-extension://") &&
            t.url !== "",
        );

        // Preserve tabs that failed to open so the workspace doesn't silently
        // lose them (the saved data is the whole point of the workspace). A
        // failed tab keeps its saved entry but drops its stale Chrome id.
        const failedSavedTabs = cleanTabs
          .filter((_, i) => openResult.created[i] === null)
          .map((t) => ({ ...t, id: undefined }));
        const updatedTabs = [...openedTabs, ...failedSavedTabs];

        // eslint-disable-next-line no-console
        console.log("[restoreWorkspaceTabs] Updated workspace tabs:", {
          opened: openedTabs.length,
          failed: failedSavedTabs.length,
        });

        // Update the workspace in storage with fresh tab IDs and groups
        // NOTE: We call StorageService directly instead of this.updateWorkspace()
        // because we're already inside a withLock() and nesting would cause deadlock
        //
        // IMPORTANT: We re-read workspaces here to get the LATEST data, including
        // any sections/resources that may have been added concurrently. This prevents
        // a race condition where we would overwrite recent changes.
        const workspaces = await StorageService.getWorkspaces();
        const wsIndex = workspaces.findIndex((w) => w.id === id);
        if (wsIndex !== -1) {
          // Only update tabs and tabGroups, preserve everything else (sections, resources, etc.)
          workspaces[wsIndex] = {
            ...workspaces[wsIndex],
            tabs: updatedTabs,
            tabGroups: freshTabGroups,
            updatedAt: Date.now(),
          };
          await StorageService.saveWorkspaces(workspaces);

          // Push the fresh tab state and claim the active-device lease — the
          // user just switched to this workspace on this device
          await this.queueWorkspaceSync(workspaces[wsIndex], {
            claimActiveDevice: true,
          });
        }

        // Set as active workspace — but NOT for a new-window restore: that
        // window is separate, and binding the shared active workspace to it
        // would make the current window's tab sync feed the wrong window.
        if (!options.inNewWindow) {
          await StorageService.setActiveWorkspaceId(id);
        }

        // eslint-disable-next-line no-console
        console.log("[restoreWorkspaceTabs] END - restored workspace:", id);
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error("Failed to restore workspace tabs:", error);
        throw error;
      }
    });
  }

  /**
   * Switch to a workspace (close current tabs and open workspace tabs)
   * Automatically creates a backup of the current workspace before switching
   */
  static async switchToWorkspace(id: string): Promise<void> {
    // Auto-backup current workspace before switching (non-blocking)
    try {
      const activeWorkspaceId = await StorageService.getActiveWorkspaceId();
      if (
        activeWorkspaceId &&
        activeWorkspaceId !== id &&
        (await AuthService.getToken())
      ) {
        await ApiService.createBackup({
          workspaceId: activeWorkspaceId,
          type: "auto",
        });
      }
    } catch (err) {
      // Non-blocking - log warning but continue with switch
      // eslint-disable-next-line no-console
      console.warn("[switchToWorkspace] Auto-backup failed:", err);
    }

    return this.restoreWorkspaceTabs(id, {
      closeCurrentTabs: true,
      inNewWindow: false,
    });
  }

  /**
   * Get active workspace
   */
  static async getActiveWorkspace(): Promise<Workspace | null> {
    const activeId = await StorageService.getActiveWorkspaceId();
    if (!activeId) return null;
    const workspace = await this.getWorkspaceById(activeId);
    return workspace || null;
  }

  /**
   * Add a section to a workspace
   */
  static async addSection(
    workspaceId: string,
    title: string,
  ): Promise<Workspace> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();
        const index = workspaces.findIndex((w) => w.id === workspaceId);

        if (index === -1) {
          throw new Error("Workspace not found");
        }

        if (!workspaces[index].sections) {
          workspaces[index].sections = [];
        }

        const newSection = {
          id: `sec_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
          title,
          resources: [],
        };

        workspaces[index].sections.push(newSection);
        workspaces[index].updatedAt = Math.max(
          Date.now(),
          (workspaces[index].updatedAt || 0) + 1,
        );
        await StorageService.saveWorkspaces(workspaces);

        await this.queueWorkspaceSync(workspaces[index]);
        return workspaces[index];
      } catch (error) {
        console.error("Failed to add section:", error);
        throw error;
      }
    });
  }

  /**
   * Delete a section from a workspace
   */
  static async deleteSection(
    workspaceId: string,
    sectionId: string,
  ): Promise<Workspace> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();
        const index = workspaces.findIndex((w) => w.id === workspaceId);

        if (index === -1) {
          throw new Error("Workspace not found");
        }

        if (workspaces[index].sections) {
          workspaces[index].sections = workspaces[index].sections.filter(
            (s) => s.id !== sectionId,
          );
          workspaces[index].updatedAt = Math.max(
            Date.now(),
            (workspaces[index].updatedAt || 0) + 1,
          );
          await StorageService.saveWorkspaces(workspaces);

          await this.queueWorkspaceSync(workspaces[index]);
        }

        return workspaces[index];
      } catch (error) {
        console.error("Failed to delete section:", error);
        throw error;
      }
    });
  }

  /**
   * Rename a section in a workspace
   */
  static async renameSection(
    workspaceId: string,
    sectionId: string,
    newTitle: string,
  ): Promise<Workspace> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();
        const index = workspaces.findIndex((w) => w.id === workspaceId);

        if (index === -1) {
          throw new Error("Workspace not found");
        }

        if (workspaces[index].sections) {
          const sectionIndex = workspaces[index].sections.findIndex(
            (s) => s.id === sectionId,
          );
          if (sectionIndex !== -1) {
            workspaces[index].sections[sectionIndex].title = newTitle;
            workspaces[index].updatedAt = Math.max(
              Date.now(),
              (workspaces[index].updatedAt || 0) + 1,
            );
            await StorageService.saveWorkspaces(workspaces);

            await this.queueWorkspaceSync(workspaces[index]);
          }
        }

        return workspaces[index];
      } catch (error) {
        console.error("Failed to rename section:", error);
        throw error;
      }
    });
  }

  /**
   * Add a resource to a specific section
   */
  static async addResourceToSection(
    workspaceId: string,
    sectionId: string,
    resource: { title: string; url: string; faviconUrl?: string },
  ): Promise<Workspace> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();

        const wsIndex = workspaces.findIndex((w) => w.id === workspaceId);

        if (wsIndex === -1) {
          throw new Error("Workspace not found");
        }

        const sectionIndex = workspaces[wsIndex].sections?.findIndex(
          (s) => s.id === sectionId,
        );

        if (sectionIndex === undefined || sectionIndex === -1) {
          throw new Error("Section not found");
        }

        const newResource = {
          id: `res_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
          title: resource.title,
          url: normalizeResourceUrl(resource.url),
          faviconUrl: resource.faviconUrl,
          createdAt: Date.now(),
        };

        workspaces[wsIndex].sections[sectionIndex].resources.push(newResource);
        workspaces[wsIndex].updatedAt = Math.max(
          Date.now(),
          (workspaces[wsIndex].updatedAt || 0) + 1,
        );
        await StorageService.saveWorkspaces(workspaces);

        await this.queueWorkspaceSync(workspaces[wsIndex]);
        return workspaces[wsIndex];
      } catch (error) {
        console.error("Failed to add resource to section:", error);
        throw error;
      }
    });
  }

  /**
   * Remove a resource from a section
   */
  static async removeResourceFromSection(
    workspaceId: string,
    sectionId: string,
    resourceId: string,
  ): Promise<Workspace> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();
        const wsIndex = workspaces.findIndex((w) => w.id === workspaceId);

        if (wsIndex === -1) {
          throw new Error("Workspace not found");
        }

        const sectionIndex = workspaces[wsIndex].sections?.findIndex(
          (s) => s.id === sectionId,
        );

        if (sectionIndex === undefined || sectionIndex === -1) {
          throw new Error("Section not found");
        }

        workspaces[wsIndex].sections[sectionIndex].resources = workspaces[
          wsIndex
        ].sections[sectionIndex].resources.filter((r) => r.id !== resourceId);
        workspaces[wsIndex].updatedAt = Math.max(
          Date.now(),
          (workspaces[wsIndex].updatedAt || 0) + 1,
        );
        await StorageService.saveWorkspaces(workspaces);

        await this.queueWorkspaceSync(workspaces[wsIndex]);
        return workspaces[wsIndex];
      } catch (error) {
        console.error("Failed to remove resource from section:", error);
        throw error;
      }
    });
  }

  /**
   * Add a note to a workspace
   */
  static async addNote(
    workspaceId: string,
    note: { id?: string; title: string; content: string },
  ): Promise<Workspace> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();
        const index = workspaces.findIndex((w) => w.id === workspaceId);

        if (index === -1) {
          throw new Error("Workspace not found");
        }

        if (!workspaces[index].notes) {
          workspaces[index].notes = [];
        }

        const newNote = {
          // Honor a caller-supplied id so the optimistic UI note, its update
          // routing, and the popout URL all reference the persisted id
          id:
            note.id ??
            `note_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
          title: note.title,
          content: note.content,
          updatedAt: Date.now(),
        };

        // Prepend to match the optimistic prepend (and addTask) — avoids the
        // note visibly jumping from top to bottom when the echo lands
        workspaces[index].notes.unshift(newNote);
        workspaces[index].updatedAt = Math.max(
          Date.now(),
          (workspaces[index].updatedAt || 0) + 1,
        );
        await StorageService.saveWorkspaces(workspaces);

        await this.queueWorkspaceSync(workspaces[index]);
        return workspaces[index];
      } catch (error) {
        console.error("Failed to add note:", error);
        throw error;
      }
    });
  }

  /**
   * Update a note
   */
  static async updateNote(
    workspaceId: string,
    noteId: string,
    updates: { title?: string; content?: string },
  ): Promise<Workspace> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();
        const wsIndex = workspaces.findIndex((w) => w.id === workspaceId);

        if (wsIndex === -1) {
          throw new Error("Workspace not found");
        }

        const noteIndex = workspaces[wsIndex].notes?.findIndex(
          (n) => n.id === noteId,
        );

        if (noteIndex === undefined || noteIndex === -1) {
          throw new Error("Note not found");
        }

        workspaces[wsIndex].notes[noteIndex] = {
          ...workspaces[wsIndex].notes[noteIndex],
          ...updates,
          updatedAt: Date.now(),
        };

        workspaces[wsIndex].updatedAt = Math.max(
          Date.now(),
          (workspaces[wsIndex].updatedAt || 0) + 1,
        );
        await StorageService.saveWorkspaces(workspaces);

        await this.queueWorkspaceSync(workspaces[wsIndex]);
        return workspaces[wsIndex];
      } catch (error) {
        console.error("Failed to update note:", error);
        throw error;
      }
    });
  }

  /**
   * Delete a note
   */
  static async deleteNote(
    workspaceId: string,
    noteId: string,
  ): Promise<Workspace> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();
        const index = workspaces.findIndex((w) => w.id === workspaceId);

        if (index === -1) {
          throw new Error("Workspace not found");
        }

        if (workspaces[index].notes) {
          workspaces[index].notes = workspaces[index].notes.filter(
            (n) => n.id !== noteId,
          );
          workspaces[index].updatedAt = Math.max(
            Date.now(),
            (workspaces[index].updatedAt || 0) + 1,
          );
          await StorageService.saveWorkspaces(workspaces);

          await this.queueWorkspaceSync(workspaces[index]);
        }

        return workspaces[index];
      } catch (error) {
        console.error("Failed to delete note:", error);
        throw error;
      }
    });
  }

  /**
   * Move a resource between lists or reorder within a list
   */
  static async moveResource(
    workspaceId: string,
    resourceId: string,
    source: { type: "uncategorized" | "section"; sectionId?: string },
    destination: {
      type: "uncategorized" | "section";
      sectionId?: string;
      index: number;
    },
  ): Promise<Workspace> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();
        const wsIndex = workspaces.findIndex((w) => w.id === workspaceId);

        if (wsIndex === -1) {
          throw new Error("Workspace not found");
        }

        const workspace = workspaces[wsIndex];
        let resource;

        // 1. Remove from source
        if (source.type === "uncategorized") {
          const resIndex = workspace.resources.findIndex(
            (r) => r.id === resourceId,
          );
          if (resIndex === -1) throw new Error("Resource not found in source");
          [resource] = workspace.resources.splice(resIndex, 1);
        } else {
          const section = workspace.sections?.find(
            (s) => s.id === source.sectionId,
          );
          if (!section) throw new Error("Source section not found");
          const resIndex = section.resources.findIndex(
            (r) => r.id === resourceId,
          );
          if (resIndex === -1)
            throw new Error("Resource not found in source section");
          [resource] = section.resources.splice(resIndex, 1);
        }

        // 2. Add to destination
        if (destination.type === "uncategorized") {
          workspace.resources.splice(destination.index, 0, resource);
        } else {
          const section = workspace.sections?.find(
            (s) => s.id === destination.sectionId,
          );
          if (!section) throw new Error("Destination section not found");
          section.resources.splice(destination.index, 0, resource);
        }

        workspace.updatedAt = Math.max(
          Date.now(),
          (workspace.updatedAt || 0) + 1,
        );
        await StorageService.saveWorkspaces(workspaces);

        await this.queueWorkspaceSync(workspace);
        return workspace;
      } catch (error) {
        console.error("Failed to move resource:", error);
        throw error;
      }
    });
  }

  /**
   * Add a task to a workspace
   */
  static async addTask(
    workspaceId: string,
    title: string,
    id?: string,
  ): Promise<Workspace> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();
        const index = workspaces.findIndex((w) => w.id === workspaceId);

        if (index === -1) {
          throw new Error("Workspace not found");
        }

        if (!workspaces[index].tasks) {
          workspaces[index].tasks = [];
        }

        const newTask = {
          // Honor a caller-supplied id so the optimistic task and its toggle/
          // delete routing reference the persisted id (no phantom-id remount)
          id:
            id ??
            `task_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
          title,
          completed: false,
          createdAt: Date.now(),
        };

        workspaces[index].tasks.unshift(newTask); // Add to top
        workspaces[index].updatedAt = Math.max(
          Date.now(),
          (workspaces[index].updatedAt || 0) + 1,
        );
        await StorageService.saveWorkspaces(workspaces);

        await this.queueWorkspaceSync(workspaces[index]);
        return workspaces[index];
      } catch (error) {
        console.error("Failed to add task:", error);
        throw error;
      }
    });
  }

  /**
   * Toggle task completion status
   */
  static async toggleTask(
    workspaceId: string,
    taskId: string,
  ): Promise<Workspace> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();
        const wsIndex = workspaces.findIndex((w) => w.id === workspaceId);

        if (wsIndex === -1) {
          throw new Error("Workspace not found");
        }

        const taskIndex = workspaces[wsIndex].tasks?.findIndex(
          (t) => t.id === taskId,
        );

        if (taskIndex === undefined || taskIndex === -1) {
          throw new Error("Task not found");
        }

        workspaces[wsIndex].tasks[taskIndex].completed =
          !workspaces[wsIndex].tasks[taskIndex].completed;
        workspaces[wsIndex].updatedAt = Math.max(
          Date.now(),
          (workspaces[wsIndex].updatedAt || 0) + 1,
        );
        await StorageService.saveWorkspaces(workspaces);

        await this.queueWorkspaceSync(workspaces[wsIndex]);
        return workspaces[wsIndex];
      } catch (error) {
        console.error("Failed to toggle task:", error);
        throw error;
      }
    });
  }

  /**
   * Delete a task
   */
  static async deleteTask(
    workspaceId: string,
    taskId: string,
  ): Promise<Workspace> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();
        const index = workspaces.findIndex((w) => w.id === workspaceId);

        if (index === -1) {
          throw new Error("Workspace not found");
        }

        if (workspaces[index].tasks) {
          workspaces[index].tasks = workspaces[index].tasks.filter(
            (t) => t.id !== taskId,
          );
          workspaces[index].updatedAt = Math.max(
            Date.now(),
            (workspaces[index].updatedAt || 0) + 1,
          );
          await StorageService.saveWorkspaces(workspaces);

          await this.queueWorkspaceSync(workspaces[index]);
        }

        return workspaces[index];
      } catch (error) {
        console.error("Failed to delete task:", error);
        throw error;
      }
    });
  }

  /**
   * Update a resource in uncategorized
   */
  static async updateResource(
    workspaceId: string,
    resourceId: string,
    updates: { title?: string; url?: string },
  ): Promise<Workspace> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();
        const wsIndex = workspaces.findIndex((w) => w.id === workspaceId);

        if (wsIndex === -1) {
          throw new Error("Workspace not found");
        }

        const resIndex = workspaces[wsIndex].resources?.findIndex(
          (r) => r.id === resourceId,
        );

        if (resIndex === undefined || resIndex === -1) {
          throw new Error("Resource not found");
        }

        workspaces[wsIndex].resources[resIndex] = {
          ...workspaces[wsIndex].resources[resIndex],
          ...updates,
        };

        workspaces[wsIndex].updatedAt = Math.max(
          Date.now(),
          (workspaces[wsIndex].updatedAt || 0) + 1,
        );
        await StorageService.saveWorkspaces(workspaces);

        await this.queueWorkspaceSync(workspaces[wsIndex]);
        return workspaces[wsIndex];
      } catch (error) {
        console.error("Failed to update resource:", error);
        throw error;
      }
    });
  }

  /**
   * Update a resource in a section
   */
  static async updateResourceInSection(
    workspaceId: string,
    sectionId: string,
    resourceId: string,
    updates: { title?: string; url?: string },
  ): Promise<Workspace> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();
        const wsIndex = workspaces.findIndex((w) => w.id === workspaceId);

        if (wsIndex === -1) {
          throw new Error("Workspace not found");
        }

        const sectionIndex = workspaces[wsIndex].sections?.findIndex(
          (s) => s.id === sectionId,
        );

        if (sectionIndex === undefined || sectionIndex === -1) {
          throw new Error("Section not found");
        }

        const resIndex = workspaces[wsIndex].sections[
          sectionIndex
        ].resources.findIndex((r) => r.id === resourceId);

        if (resIndex === -1) {
          throw new Error("Resource not found in section");
        }

        workspaces[wsIndex].sections[sectionIndex].resources[resIndex] = {
          ...workspaces[wsIndex].sections[sectionIndex].resources[resIndex],
          ...updates,
        };

        workspaces[wsIndex].updatedAt = Math.max(
          Date.now(),
          (workspaces[wsIndex].updatedAt || 0) + 1,
        );
        await StorageService.saveWorkspaces(workspaces);

        await this.queueWorkspaceSync(workspaces[wsIndex]);
        return workspaces[wsIndex];
      } catch (error) {
        console.error("Failed to update resource in section:", error);
        throw error;
      }
    });
  }

  // ============================================
  // SPACE GROUP METHODS
  // ============================================

  /**
   * Get all space groups
   * Merges remote data with local storage using Last Write Wins (timestamp-based).
   *
   * Same as getAllWorkspaces: network fetch outside the lock, merge+save under
   * the lock against freshly-loaded local state.
   */
  static async getSpaceGroups(): Promise<SpaceGroup[]> {
    try {
      if (await AuthService.getToken()) {
        const remoteGroups = (await ApiService.getSpaceGroups()) || [];

        return await this.withLock(async () => {
          const localGroups = await StorageService.getSpaceGroups();
          const localMap = new Map(localGroups.map((g) => [g.id, g]));
          const localWinners: SpaceGroup[] = [];

          // Merge: prefer local if it has a newer-or-equal timestamp, but keep
          // the server's version so the next PUT carries the right baseVersion
          const mergedGroups = remoteGroups.map((remoteGroup) => {
            const localGroup = localMap.get(remoteGroup.id);
            if (localGroup) {
              // Normalize timestamps to handle potential string/ISO formats from API
              const localTime = new Date(localGroup.updatedAt || 0).getTime();
              const remoteTime = new Date(remoteGroup.updatedAt || 0).getTime();
              if (localTime >= remoteTime) {
                const kept: SpaceGroup = {
                  ...localGroup,
                  version: remoteGroup.version,
                };
                // Strictly-newer local content must be pushed so the server converges
                if (localTime > remoteTime) {
                  localWinners.push(kept);
                }
                return kept;
              }
            }
            return remoteGroup;
          });

          // Local-only groups: a defined `version` proves the group existed on
          // the server — missing remotely means deleted there, so drop it (no
          // resurrection). No `version` means never synced — keep it.
          const remoteIds = new Set(remoteGroups.map((g) => g.id));
          const localOnlyGroups = localGroups.filter(
            (g) => !remoteIds.has(g.id) && g.version === undefined,
          );
          const finalGroups = [...mergedGroups, ...localOnlyGroups];

          // Save merged result to local storage
          await StorageService.saveSpaceGroups(finalGroups);

          await Promise.all(
            localWinners.map((g) => this.queueSpaceGroupSync(g)),
          );

          return finalGroups;
        });
      }
    } catch (error) {
      console.error("Failed to fetch space groups from API:", error);
    }

    // Not logged in or error: use local storage
    return StorageService.getSpaceGroups();
  }

  /**
   * Create a new space group
   */
  static async createSpaceGroup(title: string): Promise<SpaceGroup> {
    return this.withLock(async () => {
      try {
        const groups = await StorageService.getSpaceGroups();
        const newGroup: SpaceGroup = {
          id: `sg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
          title,
          collapsed: false,
          position: groups.length,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        };
        groups.push(newGroup);
        await StorageService.saveSpaceGroups(groups);

        await this.queueSpaceGroupSync(newGroup);

        return newGroup;
      } catch (error) {
        console.error("Failed to create space group:", error);
        throw error;
      }
    });
  }

  /**
   * Delete a space group (workspaces become ungrouped).
   *
   * Groups and member workspaces are mutated inside ONE withLock — withLock is
   * not reentrant, so this method must not call other locked methods.
   */
  static async deleteSpaceGroup(groupId: string): Promise<void> {
    return this.withLock(async () => {
      try {
        // Remove group
        const groups = await StorageService.getSpaceGroups();
        const filteredGroups = groups.filter((g) => g.id !== groupId);
        await StorageService.saveSpaceGroups(filteredGroups);

        // Durable delete op — survives restarts/offline, unlike a
        // fire-and-forget API call
        if (await AuthService.getToken()) {
          await SyncService.enqueue({
            type: "spaceGroup",
            action: "delete",
            entityId: groupId,
          });
        }

        // Ungroup workspaces that were in this group
        const workspaces = await StorageService.getWorkspaces();
        const changedWorkspaces: Workspace[] = [];
        const updatedWorkspaces = workspaces.map((ws) => {
          if (ws.groupId === groupId) {
            const updated: Workspace = {
              ...ws,
              // Explicitly null (not undefined): undefined is dropped by
              // JSON.stringify so the server would never clear the field
              // eslint-disable-next-line @typescript-eslint/no-explicit-any
              groupId: null as any,
              updatedAt: Math.max(Date.now(), (ws.updatedAt || 0) + 1),
            };
            changedWorkspaces.push(updated);
            return updated;
          }
          return ws;
        });
        await StorageService.saveWorkspaces(updatedWorkspaces);

        await Promise.all(
          changedWorkspaces.map((ws) => this.queueWorkspaceSync(ws)),
        );
      } catch (error) {
        console.error("Failed to delete space group:", error);
        throw error;
      }
    });
  }

  /**
   * Rename a space group
   */
  static async renameSpaceGroup(
    groupId: string,
    title: string,
  ): Promise<SpaceGroup> {
    return this.withLock(async () => {
      try {
        const groups = await StorageService.getSpaceGroups();
        const groupIndex = groups.findIndex((g) => g.id === groupId);
        if (groupIndex === -1) {
          throw new Error("Space group not found");
        }
        groups[groupIndex].title = title;
        await StorageService.saveSpaceGroups(groups);

        await this.queueSpaceGroupSync(groups[groupIndex]);
        return groups[groupIndex];
      } catch (error) {
        console.error("Failed to rename space group:", error);
        throw error;
      }
    });
  }

  /**
   * Update a space group (title, color)
   */
  static async updateSpaceGroup(
    groupId: string,
    updates: { title?: string; color?: string | null },
  ): Promise<SpaceGroup> {
    return this.withLock(async () => {
      try {
        const groups = await StorageService.getSpaceGroups();
        const groupIndex = groups.findIndex((g) => g.id === groupId);
        if (groupIndex === -1) {
          throw new Error("Space group not found");
        }
        if (updates.title !== undefined) {
          groups[groupIndex].title = updates.title;
        }
        // Handle color: explicitly set to null for API sync (JSON.stringify includes null but omits undefined)
        if (updates.color !== undefined) {
          // Keep null as null (not undefined) to ensure API clears the field
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          (groups[groupIndex] as any).color = updates.color;
        }
        // Use monotonic timestamp to prevent clock skew issues causing remote state to revert local changes
        groups[groupIndex].updatedAt = Math.max(
          Date.now(),
          (groups[groupIndex].updatedAt || 0) + 1,
        );
        await StorageService.saveSpaceGroups(groups);

        await this.queueSpaceGroupSync(groups[groupIndex]);
        return groups[groupIndex];
      } catch (error) {
        console.error("Failed to update space group:", error);
        throw error;
      }
    });
  }

  /**
   * Bulk update space group orders.
   *
   * Like updateWorkspaceOrders: the passed array is a UI snapshot — apply ONLY
   * `position` onto freshly-loaded storage state.
   */
  static async updateSpaceGroupOrders(groups: SpaceGroup[]): Promise<void> {
    return this.withLock(async () => {
      try {
        const freshGroups = await StorageService.getSpaceGroups();
        const changed: SpaceGroup[] = [];

        groups.forEach((incoming) => {
          const index = freshGroups.findIndex((g) => g.id === incoming.id);
          if (index === -1) return;
          const current = freshGroups[index];
          if (current.position === incoming.position) return;
          freshGroups[index] = {
            ...current,
            position: incoming.position,
            updatedAt: Math.max(Date.now(), (current.updatedAt || 0) + 1),
          };
          changed.push(freshGroups[index]);
        });

        await StorageService.saveSpaceGroups(freshGroups);

        try {
          await Promise.all(changed.map((g) => this.queueSpaceGroupSync(g)));
        } catch (err) {
          console.error("Failed to sync space group orders:", err);
        }
      } catch (error) {
        console.error("Failed to update space group orders:", error);
        throw error;
      }
    });
  }

  /**
   * Toggle space group collapsed state
   */
  static async toggleSpaceGroupCollapse(groupId: string): Promise<SpaceGroup> {
    return this.withLock(async () => {
      try {
        const groups = await StorageService.getSpaceGroups();
        const groupIndex = groups.findIndex((g) => g.id === groupId);
        if (groupIndex === -1) {
          throw new Error("Space group not found");
        }
        groups[groupIndex].collapsed = !groups[groupIndex].collapsed;
        await StorageService.saveSpaceGroups(groups);

        await this.queueSpaceGroupSync(groups[groupIndex]);

        return groups[groupIndex];
      } catch (error) {
        console.error("Failed to toggle space group collapse:", error);
        throw error;
      }
    });
  }

  /**
   * Move a workspace to a group (or ungroup if groupId is null)
   */
  static async moveWorkspaceToGroup(
    workspaceId: string,
    groupId: string | null,
  ): Promise<Workspace> {
    return this.withLock(async () => {
      try {
        const workspaces = await StorageService.getWorkspaces();
        const wsIndex = workspaces.findIndex((ws) => ws.id === workspaceId);
        if (wsIndex === -1) {
          throw new Error("Workspace not found");
        }

        const updatedWorkspace = { ...workspaces[wsIndex] };
        if (groupId) {
          updatedWorkspace.groupId = groupId;
        } else {
          // Explicitly set to null to ensure API clears the field (JSON.stringify includes null but omits undefined)
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          (updatedWorkspace as any).groupId = null;
        }

        // Use monotonic timestamp to prevent clock skew issues causing remote state to revert local changes
        updatedWorkspace.updatedAt = Math.max(
          Date.now(),
          (workspaces[wsIndex].updatedAt || 0) + 1,
        );

        workspaces[wsIndex] = updatedWorkspace;

        await StorageService.saveWorkspaces(workspaces);

        // Durable queue instead of a direct (lossy) API call
        await this.queueWorkspaceSync(workspaces[wsIndex]);

        return workspaces[wsIndex];
      } catch (error) {
        console.error("Failed to move workspace to group:", error);
        throw error;
      }
    });
  }
}
