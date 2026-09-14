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
 * Backup Service - Business logic for workspace backup operations
 *
 * Features:
 * - Create snapshots of workspace state
 * - List backups with filtering/pagination
 * - Restore workspaces from backups
 * - Auto-cleanup based on tier retention policy
 */
import type { Prisma } from "../generated/prisma/client";
import { prisma } from "../lib/prisma";
import { getTierLimits, validateTierLimit } from "../lib/tiers";
import type {
  BackupCreateInput,
  BackupListQuery,
  BackupStats,
} from "../schemas/backup";

interface BackupSnapshot {
  workspace: {
    id: string;
    name: string;
    description: string | null;
    color: string | null;
    icon: string | null;
    position: number;
    settings: Record<string, unknown>;
    groupId: string | null;
  };
  tabs: Array<{
    id: string;
    url: string;
    title: string | null;
    faviconUrl: string | null;
    position: number;
    isPinned: boolean;
    metadata: Record<string, unknown>;
  }>;
  tabGroups: Array<{
    id: string;
    title?: string;
    color: string;
    collapsed: boolean;
  }>;
  sections: Array<{
    id: string;
    title: string;
    position: number;
  }>;
  resources: Array<{
    id: string;
    title: string;
    url: string;
    faviconUrl: string | null;
    position: number;
    sectionId: string | null;
  }>;
  notes: Array<{
    id: string;
    title: string;
    content: string;
    position: number;
  }>;
  tasks: Array<{
    id: string;
    title: string;
    completed: boolean;
    dueDate: Date | null;
    position: number;
  }>;
  createdAt: string;
}

export class BackupService {
  /**
   * Create a backup snapshot of a workspace or all workspaces
   */
  static async createBackup(
    userId: string,
    tier: string,
    input: BackupCreateInput,
  ): Promise<{
    id: string;
    workspaceId: string | null;
    name: string | null;
    type: string;
    sizeBytes: number;
    createdAt: Date;
  }> {
    const backupType = input.type || "manual";

    // Self-healing retention: prune retention-expired backups before counting so
    // a user is never permanently blocked by stale rows (cleanupOldBackups was
    // previously never invoked anywhere).
    await this.cleanupOldBackups(userId, tier);

    // Enforce per-user tier cap.
    let backupCount = await prisma.backup.count({ where: { userId } });
    const validation = validateTierLimit(tier, "maxBackups", backupCount);
    if (!validation.valid) {
      if (backupType === "auto") {
        // Auto backups (fired on every workspace switch) get a rolling window:
        // at cap, evict the oldest auto backup instead of hard-failing, so
        // continuous auto-backup keeps working within the tier limit.
        const oldestAuto = await prisma.backup.findFirst({
          where: { userId, type: "auto" },
          orderBy: { createdAt: "asc" },
          select: { id: true },
        });
        if (oldestAuto) {
          await prisma.backup.delete({ where: { id: oldestAuto.id } });
          backupCount -= 1;
        } else {
          // No auto backup to evict and still at cap -> surface the limit.
          throw new Error(validation.message);
        }
      } else {
        // Manual/scheduled backups keep the hard 403 with actionable detail so
        // the client can prompt to delete old backups or upgrade.
        throw new Error(validation.message);
      }
    }

    // Get workspace data for snapshot
    const whereClause = input.workspaceId
      ? { id: input.workspaceId, userId }
      : { userId };

    const workspaces = await prisma.workspace.findMany({
      where: whereClause,
      include: {
        tabs: true,
        sections: {
          include: { resources: true }, // Include resources nested inside sections
        },
        resources: true, // Top-level resources (if any)
        notes: true,
        tasks: true,
      },
    });

    if (input.workspaceId && workspaces.length === 0) {
      throw new Error("Workspace not found");
    }

    // Create snapshot for each workspace
    const snapshots: BackupSnapshot[] = workspaces.map((ws) => {
      // Extract tabGroups from settings if present
      const settings = ws.settings as Record<string, unknown>;
      const tabGroups = Array.isArray(settings?.tabGroups)
        ? (settings.tabGroups as Array<{
            id: string;
            title?: string;
            color: string;
            collapsed: boolean;
          }>)
        : [];

      return {
        workspace: {
          id: ws.id,
          name: ws.name,
          description: ws.description,
          color: ws.color,
          icon: ws.icon,
          position: ws.position,
          settings: ws.settings as Record<string, unknown>,
          groupId: ws.groupId,
        },
        tabs: ws.tabs.map((t) => ({
          id: t.id,
          url: t.url,
          title: t.title,
          faviconUrl: t.faviconUrl,
          position: t.position,
          isPinned: t.isPinned,
          metadata: t.metadata as Record<string, unknown>,
        })),
        tabGroups,
        sections: ws.sections.map((s) => ({
          id: s.id,
          title: s.title,
          position: s.position,
        })),
        // Capture resources from sections - this is the primary source
        // Use a Set to track IDs we've already captured to prevent duplicates
        resources: (() => {
          const capturedIds = new Set<string>();
          const allResources: Array<{
            id: string;
            title: string;
            url: string;
            faviconUrl: string | null;
            position: number;
            sectionId: string | null;
          }> = [];

          // First, capture resources from inside sections
          ws.sections.forEach((s) => {
            (s.resources || []).forEach((r) => {
              if (!capturedIds.has(r.id)) {
                capturedIds.add(r.id);
                allResources.push({
                  id: r.id,
                  title: r.title,
                  url: r.url,
                  faviconUrl: r.faviconUrl,
                  position: r.position,
                  sectionId: s.id,
                });
              }
            });
          });

          // Then, capture any top-level resources that weren't already captured
          ws.resources.forEach((r) => {
            if (!capturedIds.has(r.id)) {
              capturedIds.add(r.id);
              allResources.push({
                id: r.id,
                title: r.title,
                url: r.url,
                faviconUrl: r.faviconUrl,
                position: r.position,
                sectionId: r.sectionId,
              });
            }
          });

          return allResources;
        })(),
        notes: ws.notes.map((n) => ({
          id: n.id,
          title: n.title,
          content: n.content,
          position: n.position,
        })),
        tasks: ws.tasks.map((t) => ({
          id: t.id,
          title: t.title,
          completed: t.completed,
          dueDate: t.dueDate,
          position: t.position,
        })),
        createdAt: new Date().toISOString(),
      };
    });

    // Calculate snapshot size
    const snapshotJson = JSON.stringify(snapshots);
    const sizeBytes = Buffer.byteLength(snapshotJson, "utf8");

    // Create backup record (name/type are now persisted columns)
    const backup = await prisma.backup.create({
      data: {
        userId,
        workspaceId: input.workspaceId || null,
        name: input.name || null,
        type: backupType,
        snapshot: snapshots as unknown as Prisma.JsonArray,
        sizeBytes,
      },
    });

    return {
      id: backup.id,
      workspaceId: backup.workspaceId,
      name: backup.name ?? null,
      type: backup.type,
      sizeBytes: backup.sizeBytes || 0,
      createdAt: backup.createdAt,
    };
  }

  /**
   * List backups for a user with pagination and filtering
   */
  static async listBackups(
    userId: string,
    query: BackupListQuery,
  ): Promise<{
    backups: Array<{
      id: string;
      workspaceId: string | null;
      name: string | null;
      type: string;
      sizeBytes: number | null;
      createdAt: Date;
      workspaceName?: string;
    }>;
    total: number;
    limit: number;
    offset: number;
  }> {
    const where = {
      userId,
      ...(query.workspaceId && { workspaceId: query.workspaceId }),
      ...(query.type && { type: query.type }),
    };

    const [backups, total] = await Promise.all([
      prisma.backup.findMany({
        where,
        take: query.limit,
        skip: query.offset,
        orderBy: { [query.sortBy]: query.sortOrder },
        include: {
          workspace: {
            select: { name: true },
          },
        },
      }),
      prisma.backup.count({ where }),
    ]);

    return {
      backups: backups.map((b) => ({
        id: b.id,
        workspaceId: b.workspaceId,
        name: b.name ?? null,
        type: b.type,
        sizeBytes: b.sizeBytes,
        createdAt: b.createdAt,
        workspaceName: b.workspace?.name,
      })),
      total,
      limit: query.limit,
      offset: query.offset,
    };
  }

  /**
   * Get a specific backup by ID
   */
  static async getBackup(
    userId: string,
    backupId: string,
  ): Promise<{
    id: string;
    workspaceId: string | null;
    name: string | null;
    type: string;
    snapshot: BackupSnapshot[];
    sizeBytes: number | null;
    createdAt: Date;
  } | null> {
    const backup = await prisma.backup.findFirst({
      where: { id: backupId, userId },
    });

    if (!backup) return null;

    return {
      id: backup.id,
      workspaceId: backup.workspaceId,
      name: backup.name ?? null,
      type: backup.type,
      snapshot: backup.snapshot as unknown as BackupSnapshot[],
      sizeBytes: backup.sizeBytes,
      createdAt: backup.createdAt,
    };
  }

  /**
   * Restore a workspace from backup
   */
  static async restoreBackup(
    userId: string,
    backupId: string,
    options: { targetWorkspaceId?: string; createNew?: boolean } = {},
  ): Promise<{ restoredWorkspaceIds: string[] }> {
    const backup = await this.getBackup(userId, backupId);
    if (!backup) {
      throw new Error("Backup not found");
    }

    const snapshots = backup.snapshot;

    // A full-account backup snapshots every workspace into one array. Restoring
    // such a backup onto a SINGLE target id would collapse all of them into that
    // one workspace (each iteration deletes+recreates the same target, so only
    // the last snapshot survives). Reject the ambiguous combination instead of
    // silently destroying data. Restore without a target (original ids) or use
    // createNew to clone each workspace.
    if (
      options.targetWorkspaceId &&
      !options.createNew &&
      snapshots.length > 1
    ) {
      throw new Error(
        "targetWorkspaceId is not supported for multi-workspace backups; restore without a target or use createNew",
      );
    }

    const restoredWorkspaceIds: string[] = [];

    // Process snapshots sequentially - restore operations must be ordered
    // eslint-disable-next-line no-restricted-syntax
    for (const snapshot of snapshots) {
      const targetId = options.targetWorkspaceId || snapshot.workspace.id;

      if (options.createNew) {
        // Create new workspace from backup
        const newId = `ws_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
        // eslint-disable-next-line no-await-in-loop
        await prisma.$transaction(async (tx) => {
          // Create workspace
          await tx.workspace.create({
            data: {
              id: newId,
              userId,
              name: `${snapshot.workspace.name} (Restored)`,
              description: snapshot.workspace.description,
              color: snapshot.workspace.color,
              icon: snapshot.workspace.icon,
              position: snapshot.workspace.position,
              settings: snapshot.workspace.settings as Prisma.JsonObject,
              groupId: snapshot.workspace.groupId,
            },
          });

          // Create children in the shared table order (sections, notes,
          // tasks, resources, tabs) to match updateWorkspace/restore-to-target.
          const sectionIdMap = new Map<string, string>();
          // eslint-disable-next-line no-restricted-syntax
          for (const section of snapshot.sections) {
            const newSectionId = `sec_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
            sectionIdMap.set(section.id, newSectionId);
            // eslint-disable-next-line no-await-in-loop
            await tx.section.create({
              data: {
                id: newSectionId,
                workspaceId: newId,
                title: section.title,
                position: section.position,
              },
            });
          }

          // Create notes
          if (snapshot.notes.length > 0) {
            await tx.note.createMany({
              data: snapshot.notes.map((n) => ({
                id: `note_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
                workspaceId: newId,
                title: n.title,
                content: n.content,
                position: n.position,
              })),
            });
          }

          // Create tasks
          if (snapshot.tasks.length > 0) {
            await tx.task.createMany({
              data: snapshot.tasks.map((t) => ({
                id: `task_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
                workspaceId: newId,
                title: t.title,
                completed: t.completed,
                dueDate: t.dueDate,
                position: t.position,
              })),
            });
          }

          // Create resources
          // Note: Resources with sectionId should have workspaceId: null
          if (snapshot.resources.length > 0) {
            await tx.resource.createMany({
              data: snapshot.resources.map((r) => {
                const mappedSectionId = r.sectionId
                  ? sectionIdMap.get(r.sectionId)
                  : null;
                return {
                  id: `res_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
                  // Section resources have null workspaceId, direct resources have workspaceId
                  workspaceId: mappedSectionId ? null : newId,
                  sectionId: mappedSectionId,
                  title: r.title,
                  url: r.url,
                  faviconUrl: r.faviconUrl,
                  position: r.position,
                };
              }),
            });
          }

          // Create tabs
          if (snapshot.tabs.length > 0) {
            await tx.tab.createMany({
              data: snapshot.tabs.map((t) => ({
                id: `tab_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
                workspaceId: newId,
                url: t.url,
                title: t.title,
                faviconUrl: t.faviconUrl,
                position: t.position,
                isPinned: t.isPinned,
                metadata: t.metadata as Prisma.JsonObject,
              })),
            });
          }
        });
        restoredWorkspaceIds.push(newId);
      } else {
        // Restore to existing workspace (replace contents).
        // Lock order MUST match WorkspaceService.updateWorkspace (workspace
        // row first via FOR UPDATE, then sections, notes, tasks, resources,
        // tabs) so a restore racing a sync PUT cannot deadlock.
        // eslint-disable-next-line no-await-in-loop
        await prisma.$transaction(async (tx) => {
          // Lock the workspace row (scoped to the owner); this is also the
          // existence check.
          const existingRows = await tx.$queryRaw<
            Array<{ id: string }>
          >`SELECT id FROM workspaces WHERE id = ${targetId} AND user_id = ${userId}::uuid FOR UPDATE`;

          if (existingRows.length > 0) {
            // Update workspace metadata with CURRENT timestamp to win conflict resolution
            await tx.workspace.update({
              where: { id: targetId },
              data: {
                name: snapshot.workspace.name,
                description: snapshot.workspace.description,
                color: snapshot.workspace.color,
                icon: snapshot.workspace.icon,
                settings: snapshot.workspace.settings as Prisma.JsonObject,
                updatedAt: new Date(), // Explicitly set to now to ensure remote wins over local cache
              },
            });

            // Delete existing content (same table order as updateWorkspace)
            await tx.section.deleteMany({ where: { workspaceId: targetId } });
            await tx.note.deleteMany({ where: { workspaceId: targetId } });
            await tx.task.deleteMany({ where: { workspaceId: targetId } });
            await tx.resource.deleteMany({ where: { workspaceId: targetId } });
            await tx.tab.deleteMany({ where: { workspaceId: targetId } });
          } else {
            // Create workspace if it doesn't exist
            await tx.workspace.create({
              data: {
                id: targetId,
                userId,
                name: snapshot.workspace.name,
                description: snapshot.workspace.description,
                color: snapshot.workspace.color,
                icon: snapshot.workspace.icon,
                position: snapshot.workspace.position,
                settings: snapshot.workspace.settings as Prisma.JsonObject,
                groupId: snapshot.workspace.groupId,
              },
            });
          }

          // Recreate sections
          const sectionIdMap = new Map<string, string>();
          // eslint-disable-next-line no-restricted-syntax
          for (const section of snapshot.sections) {
            const newSectionId = `sec_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
            sectionIdMap.set(section.id, newSectionId);
            // eslint-disable-next-line no-await-in-loop
            await tx.section.create({
              data: {
                id: newSectionId,
                workspaceId: targetId,
                title: section.title,
                position: section.position,
              },
            });
          }

          // Recreate notes
          if (snapshot.notes.length > 0) {
            await tx.note.createMany({
              data: snapshot.notes.map((n) => ({
                id: `note_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
                workspaceId: targetId,
                title: n.title,
                content: n.content,
                position: n.position,
              })),
            });
          }

          // Recreate tasks
          if (snapshot.tasks.length > 0) {
            await tx.task.createMany({
              data: snapshot.tasks.map((t) => ({
                id: `task_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
                workspaceId: targetId,
                title: t.title,
                completed: t.completed,
                dueDate: t.dueDate,
                position: t.position,
              })),
            });
          }

          // Recreate resources
          // Note: Resources with sectionId should have workspaceId: null
          // This matches the convention in workspace.service.ts
          if (snapshot.resources.length > 0) {
            await tx.resource.createMany({
              data: snapshot.resources.map((r) => {
                const mappedSectionId = r.sectionId
                  ? sectionIdMap.get(r.sectionId)
                  : null;
                return {
                  id: `res_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
                  // Section resources have null workspaceId, direct resources have workspaceId
                  workspaceId: mappedSectionId ? null : targetId,
                  sectionId: mappedSectionId,
                  title: r.title,
                  url: r.url,
                  faviconUrl: r.faviconUrl,
                  position: r.position,
                };
              }),
            });
          }

          // Recreate tabs
          if (snapshot.tabs.length > 0) {
            await tx.tab.createMany({
              data: snapshot.tabs.map((t) => ({
                id: `tab_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
                workspaceId: targetId,
                url: t.url,
                title: t.title,
                faviconUrl: t.faviconUrl,
                position: t.position,
                isPinned: t.isPinned,
                metadata: t.metadata as Prisma.JsonObject,
              })),
            });
          }
        });
        restoredWorkspaceIds.push(targetId);
      }
    }

    return { restoredWorkspaceIds };
  }

  /**
   * Delete a backup by ID
   */
  static async deleteBackup(
    userId: string,
    backupId: string,
  ): Promise<boolean> {
    const backup = await prisma.backup.findFirst({
      where: { id: backupId, userId },
    });

    if (!backup) return false;

    await prisma.backup.delete({ where: { id: backupId } });
    return true;
  }

  /**
   * Clean up old backups based on tier retention policy
   */
  static async cleanupOldBackups(
    userId: string,
    tier: string,
  ): Promise<{ deleted: number }> {
    const limits = getTierLimits(tier);
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - limits.backupRetentionDays);

    const result = await prisma.backup.deleteMany({
      where: {
        userId,
        createdAt: { lt: cutoffDate },
      },
    });

    return { deleted: result.count };
  }

  /**
   * Get backup statistics for a user
   */
  static async getBackupStats(userId: string): Promise<BackupStats> {
    const backups = await prisma.backup.findMany({
      where: { userId },
      select: {
        id: true,
        workspaceId: true,
        type: true,
        sizeBytes: true,
        createdAt: true,
      },
      orderBy: { createdAt: "asc" },
    });

    const { totalSizeBytes, backupsByWorkspace, autoBackups, manualBackups } =
      backups.reduce(
        (acc, backup) => {
          acc.totalSizeBytes += backup.sizeBytes || 0;
          const wsId = backup.workspaceId || "all";
          acc.backupsByWorkspace[wsId] =
            (acc.backupsByWorkspace[wsId] || 0) + 1;
          // Derive counts from the persisted type. Anything not explicitly 'auto'
          // counts as manual (covers legacy rows defaulted to 'manual' and
          // 'scheduled' which is operator-initiated like manual).
          if (backup.type === "auto") {
            acc.autoBackups += 1;
          } else {
            acc.manualBackups += 1;
          }
          return acc;
        },
        {
          totalSizeBytes: 0,
          backupsByWorkspace: {} as Record<string, number>,
          autoBackups: 0,
          manualBackups: 0,
        },
      );

    return {
      totalBackups: backups.length,
      totalSizeBytes,
      autoBackups,
      manualBackups,
      oldestBackup: backups.length > 0 ? backups[0].createdAt : null,
      newestBackup:
        backups.length > 0 ? backups[backups.length - 1].createdAt : null,
      backupsByWorkspace,
    };
  }
}
