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
 * Workspace service - Business logic for workspace operations
 */
import { prisma } from "../lib/prisma";
import { ConflictError, NotFoundError } from "../lib/errors";
import { PermissionService } from "./permission.service";
import type {
  WorkspaceCreateInput,
  WorkspaceUpdateInput,
  TabInput,
} from "../schemas/workspace";

/**
 * Active-device lease freshness window. MUST match the extension's
 * ACTIVE_DEVICE_STALE_MS (tabula/extension/src/hooks/useTabSync.ts) so client
 * and server agree on when a lease is stale and another device may take over a
 * workspace's live tab session.
 */
const ACTIVE_DEVICE_STALE_MS = 2 * 60 * 1000; // 2 minutes

export class WorkspaceService {
  /**
   * Generate a unique ID with a given prefix
   */
  static generateId(prefix: string): string {
    return `${prefix}_${Date.now().toString(36)}_${Math.random().toString(36).substring(2, 11)}`;
  }

  /**
   * Build tab rows for persistence. Tab ids are ALWAYS generated server-side:
   * client-supplied ids are per-browser chrome tab integers, which are neither
   * globally unique nor safe to trust (cross-user id squatting). The original
   * client id is preserved in metadata.clientTabId so nothing is lost.
   */
  private static buildTabRows(workspaceId: string, tabs: TabInput[]) {
    return tabs.map((t, idx) => {
      // Store groupId in metadata since Prisma schema uses metadata JSON
      const metadata: Record<string, unknown> = {
        ...(t.metadata || {}),
        groupId: t.groupId || null,
      };
      if (t.id !== undefined && t.id !== null) {
        metadata.clientTabId = t.id.toString();
      }

      return {
        id: WorkspaceService.generateId("tab"),
        workspaceId,
        url: t.url,
        title: t.title,
        faviconUrl: t.faviconUrl,
        position: t.position ?? idx,
        isPinned: t.isPinned,
        metadata,
      };
    });
  }

  /**
   * Get all workspaces for a user
   */
  static async getAllWorkspaces(userId: string) {
    return prisma.workspace.findMany({
      where: { userId },
      include: {
        tabs: { orderBy: { position: "asc" } },
        sections: {
          include: { resources: { orderBy: { position: "asc" } } },
          orderBy: { position: "asc" },
        },
        notes: { orderBy: { position: "asc" } },
        tasks: { orderBy: { position: "asc" } },
        resources: { orderBy: { position: "asc" } },
      },
      orderBy: { position: "asc" },
    });
  }

  /**
   * Get a single workspace by ID. Requires VIEW access (owner or any active
   * collaborator); a caller with no access gets NotFoundError (existence-masked).
   */
  static async getWorkspaceById(userId: string, workspaceId: string) {
    await PermissionService.requireRole(userId, workspaceId, "view");

    const workspace = await prisma.workspace.findFirst({
      where: { id: workspaceId },
      include: {
        tabs: { orderBy: { position: "asc" } },
        sections: {
          include: { resources: { orderBy: { position: "asc" } } },
          orderBy: { position: "asc" },
        },
        notes: { orderBy: { position: "asc" } },
        tasks: { orderBy: { position: "asc" } },
        resources: { orderBy: { position: "asc" } },
      },
    });

    // Deleted between the permission check and the read — treat as not found.
    if (!workspace) {
      throw new NotFoundError();
    }

    return workspace;
  }

  /**
   * Whether a workspace row exists at all, ignoring access. Used by the PUT
   * upsert path to tell "this id is genuinely new" (create it, owned by the
   * caller) from "it exists but the caller has no access" (404-mask, never
   * create over someone else's space).
   */
  static async exists(workspaceId: string): Promise<boolean> {
    const row = await prisma.workspace.findFirst({
      where: { id: workspaceId },
      select: { id: true },
    });
    return row !== null;
  }

  /**
   * Create a new workspace
   */
  static async createWorkspace(
    userId: string,
    tier: string,
    input: WorkspaceCreateInput,
    id?: string,
  ) {
    // Check workspace limit for free tier
    if (tier === "free") {
      const workspaceCount = await prisma.workspace.count({
        where: { userId },
      });

      if (workspaceCount >= 10) {
        throw new Error(
          "Maximum number of workspaces reached for free tier (10)",
        );
      }
    }

    return prisma.workspace.create({
      data: {
        id: id || this.generateId("ws"),
        userId,
        name: input.name,
        description: input.description,
        color: input.color,
        icon: input.icon,
        position: input.position,
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        settings: input.settings as any,
      },
      include: {
        tabs: true,
      },
    });
  }

  /**
   * Update a workspace.
   *
   * Concurrency model:
   * - The whole update (field write + child delete/recreate) runs inside one
   *   transaction that starts by taking a FOR UPDATE row lock on the workspace,
   *   so concurrent PUTs serialize instead of interleaving child writes.
   * - Optimistic concurrency: when the client supplies `baseVersion` and it is
   *   older than the stored `version`, a ConflictError is thrown (routes map it
   *   to 409 with the current server copy). Legacy clients that omit
   *   baseVersion are accepted unconditionally.
   * - Every successful update increments `version` by exactly 1.
   *
   * Lock order (keep in sync with BackupService.restoreBackup): workspace row
   * first, then sections, notes, tasks, resources, tabs.
   */
  static async updateWorkspace(
    userId: string,
    workspaceId: string,
    input: WorkspaceUpdateInput,
    options: { deviceId?: string } = {},
  ) {
    // Writes require EDIT (owner or an active edit collaborator). A VIEW
    // collaborator gets ForbiddenError (403); no access gets NotFoundError (404).
    // Authorization happens here, NOT via a user_id predicate on the lock below,
    // so an edit collaborator (who does not own the row) is allowed through.
    const role = await PermissionService.requireRole(
      userId,
      workspaceId,
      "edit",
    );

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return prisma.$transaction(async (tx: any) => {
      // Lock the workspace row by id (authorization already checked above) and
      // read the current version + settings.
      const rows: {
        version: number | null;
        settings: Record<string, unknown> | null;
        active_device_id: string | null;
        active_device_seen_at: Date | null;
      }[] =
        await tx.$queryRaw`SELECT version, settings, active_device_id, active_device_seen_at FROM workspaces WHERE id = ${workspaceId} FOR UPDATE`;

      if (!rows || rows.length === 0) {
        // Authorized above, so an empty lock means the row was deleted between
        // the permission check and the lock — treat as not found.
        throw new NotFoundError();
      }

      const currentVersion = rows[0].version ?? 0;
      const existingSettings = rows[0].settings ?? {};

      // Active-device lease state. "One primary session per space": at most one
      // device live-syncs a workspace's tabs at a time. A FRESH lease held by a
      // DIFFERENT device makes this device a non-primary (passive) viewer.
      const deviceId = options.deviceId;
      const leaseSeenAt = rows[0].active_device_seen_at;
      const leaseFresh = leaseSeenAt
        ? Date.now() - new Date(leaseSeenAt).getTime() < ACTIVE_DEVICE_STALE_MS
        : false;
      const foreignFreshLease = Boolean(
        rows[0].active_device_id &&
        deviceId &&
        rows[0].active_device_id !== deviceId &&
        leaseFresh,
      );

      // Passive tab-sync: a routine tab capture (tabSync, not an explicit
      // claim) from a non-primary device is a NO-OP. It must not bump the
      // version, take the lease, or overwrite the primary's live tab session —
      // return the authoritative state unchanged. This is what stops two live
      // devices from ping-ponging 409 version conflicts and clobbering each
      // other's tabs; the caller adopts the lease, goes passive, and can surface
      // "Changes from your other device". Runs BEFORE the baseVersion check so a
      // non-primary device never even sees a 409 for its automatic captures.
      if (
        input.tabSync === true &&
        input.claimActiveDevice !== true &&
        foreignFreshLease
      ) {
        return tx.workspace.findUnique({
          where: { id: workspaceId },
          include: {
            tabs: { orderBy: { position: "asc" } },
            sections: {
              include: { resources: { orderBy: { position: "asc" } } },
              orderBy: { position: "asc" },
            },
            notes: { orderBy: { position: "asc" } },
            tasks: { orderBy: { position: "asc" } },
            resources: { orderBy: { position: "asc" } },
          },
        });
      }

      if (
        input.baseVersion !== undefined &&
        input.baseVersion < currentVersion
      ) {
        throw new ConflictError(
          "Workspace was modified by another device",
          currentVersion,
        );
      }

      // 1. Update workspace fields - only the ones actually provided.
      // undefined means "leave untouched"; null is a meaningful clear for
      // nullable fields (e.g. groupId: null detaches from a space group).
      const data: Record<string, unknown> = { version: currentVersion + 1 };
      if (input.name !== undefined) data.name = input.name;
      if (input.description !== undefined) data.description = input.description;
      if (input.color !== undefined) data.color = input.color;
      if (input.icon !== undefined) data.icon = input.icon;
      if (input.position !== undefined) data.position = input.position;
      if (input.groupId !== undefined) data.groupId = input.groupId;

      // tabGroups is persisted inside settings.tabGroups. Only rewrite settings
      // when either half is provided, preserving the missing half from the
      // stored row so a partial PUT cannot wipe tabGroups or settings.
      if (input.settings !== undefined || input.tabGroups !== undefined) {
        const baseSettings =
          input.settings !== undefined ? input.settings : existingSettings;
        const tabGroups =
          input.tabGroups !== undefined
            ? input.tabGroups
            : ((existingSettings as Record<string, unknown>).tabGroups ?? []);
        data.settings = { ...baseSettings, tabGroups };
      }

      // Advisory device lease (sticky). Assign it to this device on:
      //  - an explicit claim (user switched INTO the space — may take over a
      //    fresh lease held by another device), or
      //  - a tab-sync NOT blocked by a fresh foreign lease (no lease yet, this
      //    device already holds it, or the lease has gone stale).
      // A passive tab-sync (fresh foreign lease, no claim) already returned
      // above, so reaching here with tabSync=true means this device is allowed
      // to become/remain the primary. The lease is NOT stolen by a routine
      // capture — only an explicit claim takes it from a live device.
      // Only the OWNER's devices participate in the advisory active-device
      // lease, so an edit collaborator cannot steal the owner's live primary tab
      // session via a client-controlled x-device-id. Collaborators still write
      // content normally; they just never claim the lease.
      if (
        role === "owner" &&
        deviceId &&
        (input.claimActiveDevice === true ||
          (input.tabSync === true && !foreignFreshLease))
      ) {
        data.activeDeviceId = deviceId;
        data.activeDeviceSeenAt = new Date();
      }

      await tx.workspace.update({
        where: { id: workspaceId },
        data,
      });

      // 2. Handle nested collections if provided.
      // Strategy: delete all existing nested items and recreate them so the
      // stored state exactly matches the client snapshot. The FOR UPDATE lock
      // above keeps two concurrent PUTs from interleaving these statements.

      if (input.sections) {
        await tx.section.deleteMany({ where: { workspaceId } });
        if (input.sections.length > 0) {
          // Create sections first
          await tx.section.createMany({
            data: input.sections.map((s, idx) => ({
              id: s.id,
              workspaceId,
              title: s.title,
              position: s.position ?? idx,
            })),
          });

          // Handle resources within sections
          // Use Promise.all for concurrent processing
          await Promise.all(
            input.sections.map(async (section) => {
              if (section.resources && section.resources.length > 0) {
                // Section ids come from the client; resources can only be
                // linked when the section id is present.
                if (!section.id) return; // Should not happen if client syncs state properly with IDs

                await tx.resource.createMany({
                  data: section.resources.map((r, idx) => ({
                    id: r.id,
                    workspaceId: null,
                    sectionId: section.id,
                    title: r.title,
                    url: r.url,
                    faviconUrl: r.faviconUrl,
                    position: r.position ?? idx,
                  })),
                });
              }
            }),
          );
        }
      }

      if (input.notes) {
        await tx.note.deleteMany({ where: { workspaceId } });
        if (input.notes.length > 0) {
          await tx.note.createMany({
            data: input.notes.map((n, idx) => ({
              id: n.id,
              workspaceId,
              title: n.title,
              content: n.content,
              position: n.position ?? idx,
            })),
          });
        }
      }

      if (input.tasks) {
        await tx.task.deleteMany({ where: { workspaceId } });
        if (input.tasks.length > 0) {
          await tx.task.createMany({
            data: input.tasks.map((t, idx) => ({
              id: t.id,
              workspaceId,
              title: t.title,
              completed: t.completed,
              position: t.position ?? idx,
            })),
          });
        }
      }

      // Uncategorized resources (sectionId null). Section resources are stored
      // with workspaceId null, so deleting where workspaceId matches only
      // targets direct resources.
      if (input.resources) {
        await tx.resource.deleteMany({ where: { workspaceId } });

        if (input.resources.length > 0) {
          await tx.resource.createMany({
            data: input.resources.map((r, idx) => ({
              id: r.id,
              workspaceId,
              sectionId: null,
              title: r.title,
              url: r.url,
              faviconUrl: r.faviconUrl,
              position: r.position ?? idx,
            })),
          });
        }
      }

      // Tabs: always recreated with fresh server-generated ids (see buildTabRows)
      if (input.tabs) {
        await tx.tab.deleteMany({ where: { workspaceId } });
        if (input.tabs.length > 0) {
          await tx.tab.createMany({
            data: WorkspaceService.buildTabRows(workspaceId, input.tabs),
          });
        }
      }

      // Return fully populated workspace
      return tx.workspace.findUnique({
        where: { id: workspaceId },
        include: {
          tabs: { orderBy: { position: "asc" } },
          sections: {
            include: { resources: { orderBy: { position: "asc" } } },
            orderBy: { position: "asc" },
          },
          notes: { orderBy: { position: "asc" } },
          tasks: { orderBy: { position: "asc" } },
          resources: { orderBy: { position: "asc" } },
        },
      });
    });
  }

  /**
   * Delete a workspace
   */
  static async deleteWorkspace(userId: string, workspaceId: string) {
    // Only the owner may delete a shared space — collaborators can edit content
    // but not destroy the space.
    await PermissionService.requireRole(userId, workspaceId, "owner");

    // Delete workspace (cascade will delete tabs)
    await prisma.workspace.delete({
      where: {
        id: workspaceId,
      },
    });
  }

  /**
   * Save tabs to a workspace
   */
  static async saveTabsToWorkspace(
    userId: string,
    workspaceId: string,
    tabs: TabInput[],
  ) {
    // Writing tabs requires EDIT (owner or an active edit collaborator).
    await PermissionService.requireRole(userId, workspaceId, "edit");

    // Delete existing tabs and create new ones in a transaction
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return prisma.$transaction(async (tx: any) => {
      // Delete existing tabs
      await tx.tab.deleteMany({
        where: { workspaceId },
      });

      // Create new tabs with fresh server-generated ids (see buildTabRows)
      if (tabs.length > 0) {
        await tx.tab.createMany({
          data: WorkspaceService.buildTabRows(workspaceId, tabs),
        });
      }

      // Return updated workspace
      return tx.workspace.findUnique({
        where: { id: workspaceId },
        include: {
          tabs: {
            orderBy: { position: "asc" },
          },
        },
      });
    });
  }

  /**
   * Move a tab to another workspace
   */
  static async moveTab(
    userId: string,
    tabId: string,
    targetWorkspaceId: string,
    position?: number,
  ) {
    // Adding a tab to the target space requires EDIT there.
    await PermissionService.requireRole(userId, targetWorkspaceId, "edit");

    const tab = await prisma.tab.findUnique({
      where: { id: tabId },
      select: { id: true, workspaceId: true },
    });
    if (!tab) {
      throw new NotFoundError("Tab not found");
    }

    if (tab.workspaceId === targetWorkspaceId) {
      // Same-space move: EDIT on the space is sufficient.
      await PermissionService.requireRole(userId, tab.workspaceId, "edit");
    } else {
      // Cross-space move REMOVES the tab from its source space. Require OWNER of
      // the source so an edit collaborator cannot relocate (exfiltrate) a tab out
      // of a space that was shared with them.
      await PermissionService.requireRole(userId, tab.workspaceId, "owner");
    }

    return prisma.tab.update({
      where: { id: tabId },
      data: {
        workspaceId: targetWorkspaceId,
        position: position ?? 0,
      },
    });
  }

  /**
   * Reorder a tab within a workspace
   */
  static async reorderTab(userId: string, tabId: string, newPosition: number) {
    const tab = await prisma.tab.findUnique({
      where: { id: tabId },
      select: { id: true, workspaceId: true },
    });
    if (!tab) {
      throw new NotFoundError("Tab not found");
    }
    // Reordering a tab within its space requires EDIT.
    await PermissionService.requireRole(userId, tab.workspaceId, "edit");

    return prisma.tab.update({
      where: { id: tabId },
      data: { position: newPosition },
    });
  }

  /**
   * Bulk delete tabs
   */
  static async bulkDeleteTabs(userId: string, tabIds: string[]) {
    const tabs = await prisma.tab.findMany({
      where: { id: { in: tabIds } },
      select: { workspaceId: true },
    });
    // EDIT must be held on every distinct space the tabs belong to.
    await this.requireEditOnTabWorkspaces(userId, tabs);

    await prisma.tab.deleteMany({
      where: { id: { in: tabIds } },
    });

    return { deleted: tabIds.length };
  }

  /**
   * Bulk update tabs (pin/unpin)
   */
  static async bulkUpdateTabs(
    userId: string,
    tabIds: string[],
    operation: "pin" | "unpin",
  ) {
    const tabs = await prisma.tab.findMany({
      where: { id: { in: tabIds } },
      select: { workspaceId: true },
    });
    // EDIT must be held on every distinct space the tabs belong to.
    await this.requireEditOnTabWorkspaces(userId, tabs);

    await prisma.tab.updateMany({
      where: { id: { in: tabIds } },
      data: { isPinned: operation === "pin" },
    });

    return { updated: tabIds.length };
  }

  /**
   * Assert the caller holds EDIT on every distinct workspace the given tabs
   * belong to. Throws NotFoundError / ForbiddenError on the first failure, so a
   * bulk op touching any space the caller cannot edit rejects as a whole.
   */
  private static async requireEditOnTabWorkspaces(
    userId: string,
    tabs: { workspaceId: string }[],
  ): Promise<void> {
    const workspaceIds = [...new Set(tabs.map((t) => t.workspaceId))];
    for (const workspaceId of workspaceIds) {
      await PermissionService.requireRole(userId, workspaceId, "edit");
    }
  }
}
