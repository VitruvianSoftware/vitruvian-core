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
 * Unit tests for BackupService
 */
import { BackupService } from "../../src/services/backup.service";
import { prisma } from "../../src/lib/prisma";

// Mock prisma
jest.mock("../../src/lib/prisma", () => ({
  prisma: {
    backup: {
      count: jest.fn(),
      create: jest.fn(),
      findMany: jest.fn(),
      findFirst: jest.fn(),
      delete: jest.fn(),
      deleteMany: jest.fn(),
    },
    workspace: {
      findMany: jest.fn(),
      findFirst: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
    },
    tab: {
      createMany: jest.fn(),
      deleteMany: jest.fn(),
    },
    section: {
      create: jest.fn(),
      deleteMany: jest.fn(),
    },
    resource: {
      createMany: jest.fn(),
      deleteMany: jest.fn(),
    },
    note: {
      createMany: jest.fn(),
      deleteMany: jest.fn(),
    },
    task: {
      createMany: jest.fn(),
      deleteMany: jest.fn(),
    },
    $transaction: jest.fn(),
  },
}));

describe("BackupService", () => {
  const userId = "test-user-123";
  const tier = "free";

  beforeEach(() => {
    jest.clearAllMocks();
    // createBackup now self-heals by pruning retention-expired backups first;
    // default that call to a no-op so existing tests don't need to know about it.
    (prisma.backup.deleteMany as jest.Mock).mockResolvedValue({ count: 0 });
  });

  describe("createBackup", () => {
    it("should create a backup for a specific workspace", async () => {
      const workspaceId = "ws-123";
      const mockWorkspace = {
        id: workspaceId,
        name: "Test Workspace",
        description: "Test Description",
        color: "#4F46E5",
        icon: "📁",
        position: 0,
        settings: {},
        groupId: null,
        tabs: [
          {
            id: "tab-1",
            url: "https://example.com",
            title: "Example",
            faviconUrl: null,
            position: 0,
            isPinned: false,
            metadata: {},
          },
        ],
        sections: [],
        resources: [],
        notes: [],
        tasks: [],
      };

      (prisma.backup.count as jest.Mock).mockResolvedValue(0);
      (prisma.workspace.findMany as jest.Mock).mockResolvedValue([
        mockWorkspace,
      ]);
      (prisma.backup.create as jest.Mock).mockResolvedValue({
        id: "backup-123",
        userId,
        workspaceId,
        snapshot: [mockWorkspace],
        sizeBytes: 500,
        createdAt: new Date(),
      });

      const result = await BackupService.createBackup(userId, tier, {
        workspaceId,
        name: "Test Backup",
        type: "manual",
      });

      expect(result.id).toBe("backup-123");
      expect(result.workspaceId).toBe(workspaceId);
      expect(result.sizeBytes).toBeGreaterThan(0);
      expect(prisma.backup.create).toHaveBeenCalled();
    });

    it("should enforce tier limit on backups", async () => {
      (prisma.backup.deleteMany as jest.Mock).mockResolvedValue({ count: 0 });
      (prisma.backup.count as jest.Mock).mockResolvedValue(10); // At limit for free tier

      await expect(
        BackupService.createBackup(userId, tier, { type: "manual" }),
      ).rejects.toThrow("limit");
    });

    it("should prune retention-expired backups before the count check (self-healing)", async () => {
      // cleanupOldBackups runs first; after pruning the user is under the cap.
      (prisma.backup.deleteMany as jest.Mock).mockResolvedValue({ count: 3 });
      (prisma.backup.count as jest.Mock).mockResolvedValue(0);
      (prisma.workspace.findMany as jest.Mock).mockResolvedValue([]);
      (prisma.backup.create as jest.Mock).mockResolvedValue({
        id: "b-new",
        workspaceId: null,
        name: null,
        type: "manual",
        sizeBytes: 10,
        createdAt: new Date(),
      });

      await BackupService.createBackup(userId, tier, { type: "manual" });

      expect(prisma.backup.deleteMany).toHaveBeenCalled();
      expect(prisma.backup.create).toHaveBeenCalled();
    });

    it("should evict the oldest auto backup instead of failing when an auto backup hits the cap", async () => {
      (prisma.backup.deleteMany as jest.Mock).mockResolvedValue({ count: 0 });
      (prisma.backup.count as jest.Mock).mockResolvedValue(10); // at free cap
      (prisma.backup.findFirst as jest.Mock).mockResolvedValue({
        id: "oldest-auto",
      });
      (prisma.backup.delete as jest.Mock).mockResolvedValue({});
      (prisma.workspace.findMany as jest.Mock).mockResolvedValue([]);
      (prisma.backup.create as jest.Mock).mockResolvedValue({
        id: "b-auto",
        workspaceId: null,
        name: null,
        type: "auto",
        sizeBytes: 10,
        createdAt: new Date(),
      });

      const result = await BackupService.createBackup(userId, tier, {
        type: "auto",
      });

      // Oldest auto backup is deleted to make room (rolling window), no throw.
      expect(prisma.backup.findFirst).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { userId, type: "auto" },
          orderBy: { createdAt: "asc" },
        }),
      );
      expect(prisma.backup.delete).toHaveBeenCalledWith({
        where: { id: "oldest-auto" },
      });
      expect(result.type).toBe("auto");
    });

    it("should still throw for an auto backup at cap when there is no auto backup to evict", async () => {
      (prisma.backup.deleteMany as jest.Mock).mockResolvedValue({ count: 0 });
      (prisma.backup.count as jest.Mock).mockResolvedValue(10);
      (prisma.backup.findFirst as jest.Mock).mockResolvedValue(null);

      await expect(
        BackupService.createBackup(userId, tier, { type: "auto" }),
      ).rejects.toThrow("limit");
    });

    it("should persist name and type and return the persisted values", async () => {
      (prisma.backup.deleteMany as jest.Mock).mockResolvedValue({ count: 0 });
      (prisma.backup.count as jest.Mock).mockResolvedValue(0);
      (prisma.workspace.findMany as jest.Mock).mockResolvedValue([]);
      (prisma.backup.create as jest.Mock).mockResolvedValue({
        id: "b-named",
        workspaceId: null,
        name: "My Snapshot",
        type: "manual",
        sizeBytes: 42,
        createdAt: new Date(),
      });

      const result = await BackupService.createBackup(userId, tier, {
        name: "My Snapshot",
        type: "manual",
      });

      // name/type must be written to the DB, not silently dropped.
      expect(prisma.backup.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            name: "My Snapshot",
            type: "manual",
          }),
        }),
      );
      expect(result.name).toBe("My Snapshot");
      expect(result.type).toBe("manual");
    });

    it("should throw error for non-existent workspace", async () => {
      (prisma.backup.count as jest.Mock).mockResolvedValue(0);
      (prisma.workspace.findMany as jest.Mock).mockResolvedValue([]);

      await expect(
        BackupService.createBackup(userId, tier, {
          workspaceId: "nonexistent",
          type: "manual",
        }),
      ).rejects.toThrow("Workspace not found");
    });

    it("should create a backup with sections containing resources", async () => {
      const workspaceWithSectionResources = {
        id: "ws-sections",
        name: "Workspace with Sections",
        description: null,
        color: null,
        icon: null,
        position: 0,
        settings: {},
        groupId: null,
        tabs: [],
        sections: [
          {
            id: "section-1",
            title: "My Resources",
            position: 0,
            resources: [
              {
                id: "res-1",
                title: "Section Resource 1",
                url: "https://section-resource.com",
                faviconUrl: null,
                position: 0,
              },
              {
                id: "res-2",
                title: "Section Resource 2",
                url: "https://section-resource2.com",
                faviconUrl: "https://icon.com/fav.ico",
                position: 1,
              },
            ],
          },
        ],
        resources: [
          {
            id: "res-3",
            title: "Top Level Resource",
            url: "https://top-level.com",
            faviconUrl: null,
            position: 2,
            sectionId: null,
          },
        ],
        notes: [
          {
            id: "note-1",
            title: "My Note",
            content: "Note content",
            position: 0,
          },
        ],
        tasks: [
          {
            id: "task-1",
            title: "My Task",
            completed: false,
            dueDate: new Date(),
            position: 0,
          },
        ],
      };

      (prisma.backup.count as jest.Mock).mockResolvedValue(0);
      (prisma.workspace.findMany as jest.Mock).mockResolvedValue([
        workspaceWithSectionResources,
      ]);
      (prisma.backup.create as jest.Mock).mockResolvedValue({
        id: "backup-with-sections",
        userId,
        workspaceId: "ws-sections",
        snapshot: [],
        sizeBytes: 1000,
        createdAt: new Date(),
      });

      const result = await BackupService.createBackup(userId, tier, {
        workspaceId: "ws-sections",
        type: "manual",
      });

      expect(result.id).toBe("backup-with-sections");
      expect(prisma.backup.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            snapshot: expect.arrayContaining([
              expect.objectContaining({
                resources: expect.arrayContaining([
                  expect.objectContaining({
                    id: "res-1",
                    sectionId: "section-1",
                  }),
                  expect.objectContaining({
                    id: "res-2",
                    sectionId: "section-1",
                  }),
                  expect.objectContaining({ id: "res-3" }),
                ]),
              }),
            ]),
          }),
        }),
      );
    });
  });

  describe("listBackups", () => {
    it("should list backups with pagination", async () => {
      const mockBackups = [
        {
          id: "backup-1",
          workspaceId: "ws-1",
          sizeBytes: 100,
          createdAt: new Date(),
          workspace: { name: "Workspace 1" },
        },
        {
          id: "backup-2",
          workspaceId: "ws-2",
          sizeBytes: 200,
          createdAt: new Date(),
          workspace: { name: "Workspace 2" },
        },
      ];

      (prisma.backup.findMany as jest.Mock).mockResolvedValue(mockBackups);
      (prisma.backup.count as jest.Mock).mockResolvedValue(2);

      const result = await BackupService.listBackups(userId, {
        limit: 20,
        offset: 0,
        sortBy: "createdAt",
        sortOrder: "desc",
      });

      expect(result.backups).toHaveLength(2);
      expect(result.total).toBe(2);
      expect(result.backups[0].workspaceName).toBe("Workspace 1");
    });
  });

  describe("getBackup", () => {
    it("should return backup by ID", async () => {
      const mockBackup = {
        id: "backup-123",
        userId,
        workspaceId: "ws-123",
        snapshot: [{ workspace: { id: "ws-123", name: "Test" } }],
        sizeBytes: 100,
        createdAt: new Date(),
      };

      (prisma.backup.findFirst as jest.Mock).mockResolvedValue(mockBackup);

      const result = await BackupService.getBackup(userId, "backup-123");

      expect(result).not.toBeNull();
      expect(result!.id).toBe("backup-123");
      expect(result!.snapshot).toHaveLength(1);
    });

    it("should return null for non-existent backup", async () => {
      (prisma.backup.findFirst as jest.Mock).mockResolvedValue(null);

      const result = await BackupService.getBackup(userId, "nonexistent");

      expect(result).toBeNull();
    });
  });

  describe("deleteBackup", () => {
    it("should delete backup and return true", async () => {
      (prisma.backup.findFirst as jest.Mock).mockResolvedValue({
        id: "backup-123",
        userId,
      });
      (prisma.backup.delete as jest.Mock).mockResolvedValue({});

      const result = await BackupService.deleteBackup(userId, "backup-123");

      expect(result).toBe(true);
      expect(prisma.backup.delete).toHaveBeenCalledWith({
        where: { id: "backup-123" },
      });
    });

    it("should return false for non-existent backup", async () => {
      (prisma.backup.findFirst as jest.Mock).mockResolvedValue(null);

      const result = await BackupService.deleteBackup(userId, "nonexistent");

      expect(result).toBe(false);
      expect(prisma.backup.delete).not.toHaveBeenCalled();
    });
  });

  describe("cleanupOldBackups", () => {
    it("should delete backups older than retention period", async () => {
      (prisma.backup.deleteMany as jest.Mock).mockResolvedValue({ count: 5 });

      const result = await BackupService.cleanupOldBackups(userId, "free");

      expect(result.deleted).toBe(5);
      expect(prisma.backup.deleteMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            userId,
            createdAt: expect.any(Object),
          }),
        }),
      );
    });
  });

  describe("getBackupStats", () => {
    it("should return backup statistics with real auto/manual counts", async () => {
      const mockBackups = [
        {
          id: "b1",
          workspaceId: "ws-1",
          type: "manual",
          sizeBytes: 100,
          createdAt: new Date("2024-01-01"),
        },
        {
          id: "b2",
          workspaceId: "ws-1",
          type: "auto",
          sizeBytes: 200,
          createdAt: new Date("2024-01-02"),
        },
        {
          id: "b3",
          workspaceId: "ws-2",
          type: "auto",
          sizeBytes: 150,
          createdAt: new Date("2024-01-03"),
        },
      ];

      (prisma.backup.findMany as jest.Mock).mockResolvedValue(mockBackups);

      const result = await BackupService.getBackupStats(userId);

      expect(result.totalBackups).toBe(3);
      expect(result.totalSizeBytes).toBe(450);
      expect(result.backupsByWorkspace["ws-1"]).toBe(2);
      expect(result.backupsByWorkspace["ws-2"]).toBe(1);
      // Counts are now derived from the persisted type, not hardcoded.
      expect(result.autoBackups).toBe(2);
      expect(result.manualBackups).toBe(1);
    });

    it("should handle empty backups", async () => {
      (prisma.backup.findMany as jest.Mock).mockResolvedValue([]);

      const result = await BackupService.getBackupStats(userId);

      expect(result.totalBackups).toBe(0);
      expect(result.totalSizeBytes).toBe(0);
      expect(result.backupsByWorkspace).toEqual({});
    });
  });

  describe("restoreBackup", () => {
    it("should throw error if backup not found", async () => {
      (prisma.backup.findFirst as jest.Mock).mockResolvedValue(null);

      await expect(
        BackupService.restoreBackup(userId, "nonexistent"),
      ).rejects.toThrow("Backup not found");
    });

    it("should reject restoring a multi-workspace backup onto a single target", async () => {
      // A full-account backup has many snapshots. Restoring onto one target id
      // would collapse them all into that workspace (only the last survives), so
      // the operation must be rejected, not silently lossy.
      const multiBackup = {
        id: "backup-multi",
        userId,
        snapshot: [
          {
            workspace: { id: "ws-1", name: "A", settings: {}, groupId: null },
            tabs: [],
            sections: [],
            resources: [],
            notes: [],
            tasks: [],
          },
          {
            workspace: { id: "ws-2", name: "B", settings: {}, groupId: null },
            tabs: [],
            sections: [],
            resources: [],
            notes: [],
            tasks: [],
          },
        ],
      };
      (prisma.backup.findFirst as jest.Mock).mockResolvedValue(multiBackup);

      await expect(
        BackupService.restoreBackup(userId, "backup-multi", {
          targetWorkspaceId: "ws-x",
        }),
      ).rejects.toThrow("not supported");

      // No destructive work should have started.
      expect(prisma.$transaction).not.toHaveBeenCalled();
    });

    it("should allow a multi-workspace backup restore with createNew", async () => {
      const multiBackup = {
        id: "backup-multi",
        userId,
        snapshot: [
          {
            workspace: {
              id: "ws-1",
              name: "A",
              settings: {},
              groupId: null,
              position: 0,
            },
            tabs: [],
            sections: [],
            resources: [],
            notes: [],
            tasks: [],
          },
          {
            workspace: {
              id: "ws-2",
              name: "B",
              settings: {},
              groupId: null,
              position: 1,
            },
            tabs: [],
            sections: [],
            resources: [],
            notes: [],
            tasks: [],
          },
        ],
      };
      (prisma.backup.findFirst as jest.Mock).mockResolvedValue(multiBackup);
      (prisma.$transaction as jest.Mock).mockImplementation((fn) =>
        fn({
          workspace: { create: jest.fn() },
          tab: { createMany: jest.fn() },
          section: { create: jest.fn() },
          resource: { createMany: jest.fn() },
          note: { createMany: jest.fn() },
          task: { createMany: jest.fn() },
        }),
      );

      const result = await BackupService.restoreBackup(userId, "backup-multi", {
        targetWorkspaceId: "ws-x",
        createNew: true,
      });

      // Both workspaces are cloned, none collapsed.
      expect(result.restoredWorkspaceIds).toHaveLength(2);
    });

    it("should restore backup to existing workspace", async () => {
      const mockBackup = {
        id: "backup-123",
        userId,
        snapshot: [
          {
            workspace: {
              id: "ws-123",
              name: "Test Workspace",
              description: null,
              color: null,
              icon: null,
              position: 0,
              settings: {},
              groupId: null,
            },
            tabs: [],
            sections: [],
            resources: [],
            notes: [],
            tasks: [],
          },
        ],
      };

      (prisma.backup.findFirst as jest.Mock).mockResolvedValue(mockBackup);
      const workspaceUpdateMock = jest.fn();
      const queryRawMock = jest.fn().mockResolvedValue([{ id: "ws-123" }]);
      (prisma.$transaction as jest.Mock).mockImplementation((fn) =>
        fn({
          // FOR UPDATE row lock on the workspace (also the existence check)
          $queryRaw: queryRawMock,
          workspace: {
            update: workspaceUpdateMock,
          },
          tab: { deleteMany: jest.fn(), createMany: jest.fn() },
          section: { deleteMany: jest.fn(), create: jest.fn() },
          resource: { deleteMany: jest.fn(), createMany: jest.fn() },
          note: { deleteMany: jest.fn(), createMany: jest.fn() },
          task: { deleteMany: jest.fn(), createMany: jest.fn() },
        }),
      );

      const result = await BackupService.restoreBackup(userId, "backup-123");

      expect(result.restoredWorkspaceIds).toContain("ws-123");
      expect(queryRawMock).toHaveBeenCalled();
      expect(workspaceUpdateMock).toHaveBeenCalled();
    });

    it("should restore backup as new workspace with createNew option", async () => {
      const mockBackup = {
        id: "backup-123",
        userId,
        snapshot: [
          {
            workspace: {
              id: "ws-123",
              name: "Test Workspace",
              description: "Desc",
              color: "#4F46E5",
              icon: "📁",
              position: 0,
              settings: {},
              groupId: null,
            },
            tabs: [
              {
                id: "t1",
                url: "https://example.com",
                title: "Test",
                faviconUrl: null,
                position: 0,
                isPinned: false,
                metadata: {},
              },
            ],
            sections: [{ id: "s1", title: "Section 1", position: 0 }],
            resources: [
              {
                id: "r1",
                title: "Resource",
                url: "https://res.com",
                faviconUrl: null,
                position: 0,
                sectionId: "s1",
              },
            ],
            notes: [
              { id: "n1", title: "Note", content: "Content", position: 0 },
            ],
            tasks: [
              {
                id: "t1",
                title: "Task",
                completed: false,
                dueDate: null,
                position: 0,
              },
            ],
          },
        ],
      };

      (prisma.backup.findFirst as jest.Mock).mockResolvedValue(mockBackup);
      (prisma.$transaction as jest.Mock).mockImplementation((fn) =>
        fn({
          workspace: { create: jest.fn() },
          tab: { createMany: jest.fn() },
          section: { create: jest.fn() },
          resource: { createMany: jest.fn() },
          note: { createMany: jest.fn() },
          task: { createMany: jest.fn() },
        }),
      );

      const result = await BackupService.restoreBackup(userId, "backup-123", {
        createNew: true,
      });

      expect(result.restoredWorkspaceIds).toHaveLength(1);
      expect(result.restoredWorkspaceIds[0]).toMatch(/^ws_/);
    });
  });
});
