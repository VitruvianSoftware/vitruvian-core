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
 * Unit tests for workspace service
 */
import { WorkspaceService } from "../../src/services/workspace.service";
import { ConflictError, ForbiddenError } from "../../src/lib/errors";
import { PermissionService } from "../../src/services/permission.service";
import { prisma } from "../../src/lib/prisma";

// Mock prisma
jest.mock("../../src/lib/prisma", () => ({
  prisma: {
    workspace: {
      findMany: jest.fn(),
      findFirst: jest.fn(),
      findUnique: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
      count: jest.fn(),
    },
    tab: {
      findMany: jest.fn(),
      findUnique: jest.fn(),
      deleteMany: jest.fn(),
      createMany: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
    },
    section: {
      deleteMany: jest.fn(),
      create: jest.fn(),
    },
    note: {
      deleteMany: jest.fn(),
      createMany: jest.fn(),
    },
    task: {
      deleteMany: jest.fn(),
      createMany: jest.fn(),
    },
    resource: {
      deleteMany: jest.fn(),
      createMany: jest.fn(),
    },
    $transaction: jest.fn(),
  },
}));

// Authorization is delegated to PermissionService; mock it so these unit tests
// exercise WorkspaceService's own logic. Default: the caller is the owner.
jest.mock("../../src/services/permission.service");
const mockPermission = jest.mocked(PermissionService);

describe("WorkspaceService", () => {
  const userId = "user-123";
  const workspaceId = "workspace-456";

  beforeEach(() => {
    jest.clearAllMocks();
    mockPermission.requireRole.mockResolvedValue("owner");
    mockPermission.resolveAccess.mockResolvedValue("owner");
    mockPermission.listAccessUserIds.mockResolvedValue([]);
  });

  describe("getAllWorkspaces", () => {
    it("should return all workspaces for a user", async () => {
      const mockWorkspaces = [
        { id: "ws1", name: "Work", userId, tabs: [] },
        { id: "ws2", name: "Personal", userId, tabs: [] },
      ];
      (prisma.workspace.findMany as jest.Mock).mockResolvedValue(
        mockWorkspaces,
      );

      const result = await WorkspaceService.getAllWorkspaces(userId);

      expect(result).toEqual(mockWorkspaces);
      expect(prisma.workspace.findMany).toHaveBeenCalledWith({
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
    });
  });

  describe("getWorkspaceById", () => {
    it("should return a workspace by ID", async () => {
      const mockWorkspace = { id: workspaceId, name: "Work", userId, tabs: [] };
      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue(
        mockWorkspace,
      );

      const result = await WorkspaceService.getWorkspaceById(
        userId,
        workspaceId,
      );

      expect(result).toEqual(mockWorkspace);
    });

    it("should throw error if workspace not found", async () => {
      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue(null);

      await expect(
        WorkspaceService.getWorkspaceById(userId, workspaceId),
      ).rejects.toThrow("Workspace not found");
    });
  });

  describe("createWorkspace", () => {
    it("should create a workspace for free tier user", async () => {
      const input = {
        name: "New Workspace",
        description: "Test workspace",
        color: "#4F46E5",
        icon: "📁",
        position: 0,
        settings: {},
      };
      const mockWorkspace = { id: "ws-new", ...input, userId, tabs: [] };

      (prisma.workspace.count as jest.Mock).mockResolvedValue(5);
      (prisma.workspace.create as jest.Mock).mockResolvedValue(mockWorkspace);

      const result = await WorkspaceService.createWorkspace(
        userId,
        "free",
        input,
      );

      expect(result).toEqual(mockWorkspace);
      expect(prisma.workspace.count).toHaveBeenCalledWith({
        where: { userId },
      });
    });

    it("should throw error when free tier limit reached", async () => {
      (prisma.workspace.count as jest.Mock).mockResolvedValue(10);

      const input = { name: "Test", position: 0, settings: {} };

      await expect(
        WorkspaceService.createWorkspace(userId, "free", input),
      ).rejects.toThrow("Maximum number of workspaces reached");
    });

    it("should allow creating workspace for paid tier beyond limit", async () => {
      const input = { name: "Test", position: 0, settings: {} };
      const mockWorkspace = { id: "ws-new", ...input, userId, tabs: [] };

      (prisma.workspace.count as jest.Mock).mockResolvedValue(15);
      (prisma.workspace.create as jest.Mock).mockResolvedValue(mockWorkspace);

      const result = await WorkspaceService.createWorkspace(
        userId,
        "pro",
        input,
      );

      expect(result).toEqual(mockWorkspace);
    });
  });

  describe("updateWorkspace", () => {
    /**
     * Mock transaction client matching what updateWorkspace uses: $queryRaw
     * for the FOR UPDATE row lock + version/settings read, then the regular
     * delegate methods.
     */
    const makeTx = () => ({
      $queryRaw: jest.fn().mockResolvedValue([{ version: 0, settings: {} }]),
      workspace: {
        update: jest.fn().mockResolvedValue({}),
        findUnique: jest.fn().mockResolvedValue({}),
      },
      section: {
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
        createMany: jest.fn(),
      },
      note: {
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
        createMany: jest.fn(),
      },
      task: {
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
        createMany: jest.fn(),
      },
      resource: {
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
        createMany: jest.fn(),
      },
      tab: {
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
        createMany: jest.fn(),
      },
    });

    const useTx = (tx: ReturnType<typeof makeTx>) => {
      (prisma.$transaction as jest.Mock).mockImplementation(async (fn) =>
        fn(tx),
      );
    };

    it("should update a workspace", async () => {
      const updatedWorkspace = {
        id: workspaceId,
        name: "New Name",
        userId,
        version: 1,
        tabs: [],
      };
      const tx = makeTx();
      tx.workspace.findUnique.mockResolvedValue(updatedWorkspace);
      useTx(tx);

      const result = await WorkspaceService.updateWorkspace(
        userId,
        workspaceId,
        {
          name: "New Name",
        },
      );

      expect(result).toEqual(updatedWorkspace);
      // Row lock + version read happens before any write
      expect(tx.$queryRaw).toHaveBeenCalled();
      expect(tx.workspace.update).toHaveBeenCalledWith({
        where: { id: workspaceId },
        data: { name: "New Name", version: 1 },
      });
    });

    it("should throw error if workspace not found", async () => {
      const tx = makeTx();
      tx.$queryRaw.mockResolvedValue([]);
      useTx(tx);

      await expect(
        WorkspaceService.updateWorkspace(userId, workspaceId, { name: "X" }),
      ).rejects.toThrow("Workspace not found");
      expect(tx.workspace.update).not.toHaveBeenCalled();
    });

    it("should throw ConflictError when baseVersion is stale", async () => {
      const tx = makeTx();
      tx.$queryRaw.mockResolvedValue([{ version: 5, settings: {} }]);
      useTx(tx);

      await expect(
        WorkspaceService.updateWorkspace(userId, workspaceId, {
          name: "X",
          baseVersion: 3,
        }),
      ).rejects.toBeInstanceOf(ConflictError);
      expect(tx.workspace.update).not.toHaveBeenCalled();
    });

    it("should expose the current version on ConflictError", async () => {
      const tx = makeTx();
      tx.$queryRaw.mockResolvedValue([{ version: 9, settings: {} }]);
      useTx(tx);

      await expect(
        WorkspaceService.updateWorkspace(userId, workspaceId, {
          name: "X",
          baseVersion: 2,
        }),
      ).rejects.toMatchObject({ name: "ConflictError", currentVersion: 9 });
    });

    it("should accept a matching baseVersion and increment version", async () => {
      const tx = makeTx();
      tx.$queryRaw.mockResolvedValue([{ version: 5, settings: {} }]);
      useTx(tx);

      await WorkspaceService.updateWorkspace(userId, workspaceId, {
        name: "X",
        baseVersion: 5,
      });

      expect(tx.workspace.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ version: 6 }),
        }),
      );
    });

    it("should accept updates without baseVersion (legacy clients)", async () => {
      const tx = makeTx();
      tx.$queryRaw.mockResolvedValue([{ version: 7, settings: {} }]);
      useTx(tx);

      await WorkspaceService.updateWorkspace(userId, workspaceId, {
        name: "Legacy",
      });

      expect(tx.workspace.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ name: "Legacy", version: 8 }),
        }),
      );
    });

    it("should only persist provided fields (partial PUT)", async () => {
      const tx = makeTx();
      useTx(tx);

      await WorkspaceService.updateWorkspace(userId, workspaceId, {
        name: "Only Name",
      });

      const { data } = tx.workspace.update.mock.calls[0][0];
      expect(Object.keys(data).sort()).toEqual(["name", "version"]);
    });

    it("should treat groupId null as a meaningful clear", async () => {
      const tx = makeTx();
      useTx(tx);

      await WorkspaceService.updateWorkspace(userId, workspaceId, {
        groupId: null,
      });

      const { data } = tx.workspace.update.mock.calls[0][0];
      expect(data.groupId).toBeNull();
    });

    it("should preserve stored tabGroups when settings provided without tabGroups", async () => {
      const storedTabGroups = [{ id: "g1", color: "blue", collapsed: false }];
      const tx = makeTx();
      tx.$queryRaw.mockResolvedValue([
        { version: 0, settings: { theme: "dark", tabGroups: storedTabGroups } },
      ]);
      useTx(tx);

      await WorkspaceService.updateWorkspace(userId, workspaceId, {
        settings: { theme: "light" },
      });

      const { data } = tx.workspace.update.mock.calls[0][0];
      expect(data.settings).toEqual({
        theme: "light",
        tabGroups: storedTabGroups,
      });
    });

    it("should preserve stored settings when only tabGroups provided", async () => {
      const tx = makeTx();
      tx.$queryRaw.mockResolvedValue([
        { version: 0, settings: { theme: "dark", tabGroups: [] } },
      ]);
      useTx(tx);

      const tabGroups = [{ id: "g2", color: "red", collapsed: true }];
      await WorkspaceService.updateWorkspace(userId, workspaceId, {
        tabGroups,
      });

      const { data } = tx.workspace.update.mock.calls[0][0];
      expect(data.settings).toEqual({ theme: "dark", tabGroups });
    });

    it("should not rewrite settings when neither settings nor tabGroups provided", async () => {
      const tx = makeTx();
      tx.$queryRaw.mockResolvedValue([
        {
          version: 0,
          settings: {
            tabGroups: [{ id: "g1", color: "blue", collapsed: false }],
          },
        },
      ]);
      useTx(tx);

      await WorkspaceService.updateWorkspace(userId, workspaceId, {
        name: "No Settings",
      });

      const { data } = tx.workspace.update.mock.calls[0][0];
      expect(data.settings).toBeUndefined();
    });

    it("should assign the device lease when tabSync is set with a device id", async () => {
      const tx = makeTx();
      useTx(tx);

      await WorkspaceService.updateWorkspace(
        userId,
        workspaceId,
        { name: "X", tabSync: true },
        { deviceId: "device-abc" },
      );

      const { data } = tx.workspace.update.mock.calls[0][0];
      expect(data.activeDeviceId).toBe("device-abc");
      expect(data.activeDeviceSeenAt).toBeInstanceOf(Date);
      // Protocol flags must never be persisted as workspace data
      expect(data.tabSync).toBeUndefined();
      expect(data.claimActiveDevice).toBeUndefined();
    });

    it("should assign the device lease when claimActiveDevice is set", async () => {
      const tx = makeTx();
      useTx(tx);

      await WorkspaceService.updateWorkspace(
        userId,
        workspaceId,
        { claimActiveDevice: true },
        { deviceId: "device-xyz" },
      );

      const { data } = tx.workspace.update.mock.calls[0][0];
      expect(data.activeDeviceId).toBe("device-xyz");
    });

    it("should not assign the device lease without a device id", async () => {
      const tx = makeTx();
      useTx(tx);

      await WorkspaceService.updateWorkspace(userId, workspaceId, {
        name: "X",
        tabSync: true,
      });

      const { data } = tx.workspace.update.mock.calls[0][0];
      expect(data.activeDeviceId).toBeUndefined();
      expect(data.activeDeviceSeenAt).toBeUndefined();
    });

    // --- "one primary session per space": sticky active-device lease ---

    const freshLeaseRow = (deviceId: string, version = 0) => [
      {
        version,
        settings: {},
        active_device_id: deviceId,
        active_device_seen_at: new Date(), // within ACTIVE_DEVICE_STALE_MS
      },
    ];

    it("passive tab-sync (fresh foreign lease) is a no-op: no write, primary tabs preserved", async () => {
      const tx = makeTx();
      tx.$queryRaw.mockResolvedValue(freshLeaseRow("primary-device", 4));
      const current = { id: workspaceId, tabs: [{ id: "t1" }], version: 4 };
      tx.workspace.findUnique.mockResolvedValue(current);
      useTx(tx);

      const result = await WorkspaceService.updateWorkspace(
        userId,
        workspaceId,
        {
          tabs: [
            {
              url: "https://mine.com",
              title: "Mine",
              isPinned: false,
              metadata: {},
            },
          ],
          tabSync: true,
        },
        { deviceId: "other-device" },
      );

      // Returns the authoritative current state, unchanged...
      expect(result).toBe(current);
      // ...without writing anything or clobbering the primary's tab session.
      expect(tx.workspace.update).not.toHaveBeenCalled();
      expect(tx.tab.deleteMany).not.toHaveBeenCalled();
      expect(tx.tab.createMany).not.toHaveBeenCalled();
    });

    it("passive tab-sync short-circuits BEFORE the baseVersion check (no 409 churn for a non-primary capture)", async () => {
      const tx = makeTx();
      tx.$queryRaw.mockResolvedValue(freshLeaseRow("primary-device", 9));
      useTx(tx);

      // A stale baseVersion would normally throw ConflictError — but a passive
      // capture no-ops first, so the non-primary device never even sees a 409.
      await expect(
        WorkspaceService.updateWorkspace(
          userId,
          workspaceId,
          { tabs: [], tabSync: true, baseVersion: 1 },
          { deviceId: "other-device" },
        ),
      ).resolves.toBeDefined();
      expect(tx.workspace.update).not.toHaveBeenCalled();
    });

    it("claimActiveDevice DOES take over a fresh foreign lease (explicit switch)", async () => {
      const tx = makeTx();
      tx.$queryRaw.mockResolvedValue(freshLeaseRow("primary-device"));
      useTx(tx);

      await WorkspaceService.updateWorkspace(
        userId,
        workspaceId,
        { claimActiveDevice: true },
        { deviceId: "taking-over" },
      );

      const { data } = tx.workspace.update.mock.calls[0][0];
      expect(data.activeDeviceId).toBe("taking-over");
    });

    it("renews the lease on a tab-sync from the device that already holds it", async () => {
      const tx = makeTx();
      tx.$queryRaw.mockResolvedValue(freshLeaseRow("me"));
      useTx(tx);

      await WorkspaceService.updateWorkspace(
        userId,
        workspaceId,
        { tabSync: true },
        { deviceId: "me" },
      );

      const { data } = tx.workspace.update.mock.calls[0][0];
      expect(data.activeDeviceId).toBe("me");
      expect(data.activeDeviceSeenAt).toBeInstanceOf(Date);
    });

    it("takes over a STALE foreign lease on a routine tab-sync", async () => {
      const tx = makeTx();
      tx.$queryRaw.mockResolvedValue([
        {
          version: 0,
          settings: {},
          active_device_id: "idle-device",
          active_device_seen_at: new Date(Date.now() - 3 * 60 * 1000), // stale (>2m)
        },
      ]);
      useTx(tx);

      await WorkspaceService.updateWorkspace(
        userId,
        workspaceId,
        { tabSync: true },
        { deviceId: "me" },
      );

      const { data } = tx.workspace.update.mock.calls[0][0];
      // Lease was stale -> not passive -> wrote and took the lease.
      expect(data.activeDeviceId).toBe("me");
    });

    it("should always generate fresh server tab ids and keep the client id in metadata", async () => {
      const tx = makeTx();
      useTx(tx);

      await WorkspaceService.updateWorkspace(userId, workspaceId, {
        tabs: [
          {
            id: 12345,
            url: "https://a.com",
            title: "A",
            isPinned: false,
            metadata: {},
          },
          {
            id: "client-tab",
            url: "https://b.com",
            title: "B",
            isPinned: true,
            groupId: "g1",
            metadata: {},
          },
        ],
      });

      const { data } = tx.tab.createMany.mock.calls[0][0];
      expect(data).toHaveLength(2);
      data.forEach((row: { id: string }) => {
        expect(row.id).toMatch(/^tab_/);
      });
      expect(data[0].id).not.toBe("12345");
      expect(data[0].metadata.clientTabId).toBe("12345");
      expect(data[1].id).not.toBe("client-tab");
      expect(data[1].metadata.clientTabId).toBe("client-tab");
      expect(data[1].metadata.groupId).toBe("g1");
    });

    it("should default tab position to the array index when missing", async () => {
      const tx = makeTx();
      useTx(tx);

      await WorkspaceService.updateWorkspace(userId, workspaceId, {
        tabs: [
          { url: "https://a.com", isPinned: false, metadata: {} },
          { url: "https://b.com", isPinned: false, metadata: {} },
          { url: "https://c.com", position: 9, isPinned: false, metadata: {} },
        ],
      });

      const { data } = tx.tab.createMany.mock.calls[0][0];
      expect(data.map((t: { position: number }) => t.position)).toEqual([
        0, 1, 9,
      ]);
    });

    it("should default note/task/section/resource positions to the array index", async () => {
      const tx = makeTx();
      useTx(tx);

      await WorkspaceService.updateWorkspace(userId, workspaceId, {
        sections: [
          { id: "s1", title: "S1" },
          { id: "s2", title: "S2" },
        ],
        notes: [
          { id: "n1", title: "N1", content: "" },
          { id: "n2", title: "N2", content: "" },
        ],
        tasks: [
          { id: "t1", title: "T1", completed: false },
          { id: "t2", title: "T2", completed: false },
        ],
        resources: [
          { id: "r1", title: "R1", url: "https://r1.com" },
          { id: "r2", title: "R2", url: "https://r2.com" },
        ],
      });

      const positions = (mock: jest.Mock) =>
        mock.mock.calls[0][0].data.map(
          (row: { position: number }) => row.position,
        );
      expect(positions(tx.section.createMany)).toEqual([0, 1]);
      expect(positions(tx.note.createMany)).toEqual([0, 1]);
      expect(positions(tx.task.createMany)).toEqual([0, 1]);
      expect(positions(tx.resource.createMany)).toEqual([0, 1]);
    });

    it("should update workspace with sections and resources", async () => {
      const tx = makeTx();
      useTx(tx);

      await WorkspaceService.updateWorkspace(userId, workspaceId, {
        sections: [
          {
            id: "section-1",
            title: "Test Section",
            position: 0,
            resources: [
              {
                id: "res-1",
                title: "Resource 1",
                url: "https://example.com",
                position: 0,
              },
            ],
          },
        ],
      });

      expect(tx.section.deleteMany).toHaveBeenCalled();
      expect(tx.section.createMany).toHaveBeenCalled();
      expect(tx.resource.createMany).toHaveBeenCalled();
    });

    it("should update workspace with notes", async () => {
      const tx = makeTx();
      useTx(tx);

      await WorkspaceService.updateWorkspace(userId, workspaceId, {
        notes: [
          { id: "note-1", title: "Test Note", content: "Content", position: 0 },
        ],
      });

      expect(tx.note.deleteMany).toHaveBeenCalled();
      expect(tx.note.createMany).toHaveBeenCalled();
    });

    it("should update workspace with tasks", async () => {
      const tx = makeTx();
      useTx(tx);

      await WorkspaceService.updateWorkspace(userId, workspaceId, {
        tasks: [
          { id: "task-1", title: "Test Task", completed: false, position: 0 },
        ],
      });

      expect(tx.task.deleteMany).toHaveBeenCalled();
      expect(tx.task.createMany).toHaveBeenCalled();
    });

    it("should update workspace with resources", async () => {
      const tx = makeTx();
      useTx(tx);

      await WorkspaceService.updateWorkspace(userId, workspaceId, {
        resources: [
          {
            id: "res-1",
            title: "Resource",
            url: "https://example.com",
            position: 0,
          },
        ],
      });

      expect(tx.resource.deleteMany).toHaveBeenCalled();
      expect(tx.resource.createMany).toHaveBeenCalled();
    });

    it("should update workspace with tabs", async () => {
      const tx = makeTx();
      useTx(tx);

      await WorkspaceService.updateWorkspace(userId, workspaceId, {
        tabs: [
          {
            url: "https://example.com",
            title: "Test",
            isPinned: false,
            position: 0,
            metadata: {},
          },
        ],
      });

      expect(tx.tab.deleteMany).toHaveBeenCalled();
      expect(tx.tab.createMany).toHaveBeenCalled();
    });
  });

  describe("deleteWorkspace", () => {
    it("should delete a workspace", async () => {
      const mockWorkspace = { id: workspaceId, name: "Test", userId, tabs: [] };
      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue(
        mockWorkspace,
      );
      (prisma.workspace.delete as jest.Mock).mockResolvedValue(mockWorkspace);

      await WorkspaceService.deleteWorkspace(userId, workspaceId);

      expect(prisma.workspace.delete).toHaveBeenCalledWith({
        where: { id: workspaceId },
      });
    });
  });

  describe("saveTabsToWorkspace", () => {
    it("should save tabs to workspace", async () => {
      const mockWorkspace = { id: workspaceId, name: "Test", userId, tabs: [] };
      const tabs = [
        {
          url: "https://example.com",
          title: "Example",
          position: 0,
          isPinned: false,
          metadata: {},
        },
      ];
      const updatedWorkspace = { ...mockWorkspace, tabs };

      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue(
        mockWorkspace,
      );

      const tabDeleteManyMock = jest.fn().mockResolvedValue({ count: 0 });
      const tabCreateManyMock = jest.fn().mockResolvedValue({ count: 1 });
      const workspaceFindUniqueMock = jest
        .fn()
        .mockResolvedValue(updatedWorkspace);

      (prisma.$transaction as jest.Mock).mockImplementation(async (fn) => {
        return fn({
          tab: {
            deleteMany: tabDeleteManyMock,
            createMany: tabCreateManyMock,
          },
          workspace: { findUnique: workspaceFindUniqueMock },
        });
      });

      const result = await WorkspaceService.saveTabsToWorkspace(
        userId,
        workspaceId,
        tabs,
      );

      expect(result).toEqual(updatedWorkspace);
      expect(tabDeleteManyMock).toHaveBeenCalledWith({
        where: { workspaceId },
      });
      expect(tabCreateManyMock).toHaveBeenCalled();
    });

    it("should generate fresh server tab ids and keep the client id in metadata", async () => {
      const mockWorkspace = { id: workspaceId, name: "Test", userId, tabs: [] };
      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue(
        mockWorkspace,
      );

      const tabCreateManyMock = jest.fn().mockResolvedValue({ count: 1 });
      (prisma.$transaction as jest.Mock).mockImplementation(async (fn) => {
        return fn({
          tab: {
            deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
            createMany: tabCreateManyMock,
          },
          workspace: { findUnique: jest.fn().mockResolvedValue(mockWorkspace) },
        });
      });

      await WorkspaceService.saveTabsToWorkspace(userId, workspaceId, [
        {
          id: 777,
          url: "https://example.com",
          title: "T",
          isPinned: false,
          metadata: {},
        },
      ]);

      const { data } = tabCreateManyMock.mock.calls[0][0];
      expect(data[0].id).toMatch(/^tab_/);
      expect(data[0].id).not.toBe("777");
      expect(data[0].metadata.clientTabId).toBe("777");
    });

    it("should handle empty tabs array", async () => {
      const mockWorkspace = { id: workspaceId, name: "Test", userId, tabs: [] };

      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue(
        mockWorkspace,
      );

      const tabDeleteManyMock = jest.fn().mockResolvedValue({ count: 0 });
      const tabCreateManyMock = jest.fn().mockResolvedValue({ count: 0 });
      const workspaceFindUniqueMock = jest
        .fn()
        .mockResolvedValue(mockWorkspace);

      (prisma.$transaction as jest.Mock).mockImplementation(async (fn) => {
        return fn({
          tab: {
            deleteMany: tabDeleteManyMock,
            createMany: tabCreateManyMock,
          },
          workspace: { findUnique: workspaceFindUniqueMock },
        });
      });

      const result = await WorkspaceService.saveTabsToWorkspace(
        userId,
        workspaceId,
        [],
      );

      expect(result).toEqual(mockWorkspace);
      expect(tabDeleteManyMock).toHaveBeenCalled();
      // createMany should NOT be called for empty array
      expect(tabCreateManyMock).not.toHaveBeenCalled();
    });
  });

  describe("moveTab", () => {
    it("should move tab to another workspace", async () => {
      const tab = {
        id: "tab-1",
        url: "https://example.com",
        workspaceId: "ws-old",
        workspace: { userId },
      };
      const targetWorkspace = { id: "ws-new", userId, tabs: [] };
      const movedTab = { ...tab, workspaceId: "ws-new" };

      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue(
        targetWorkspace,
      );
      (prisma.tab.findUnique as jest.Mock).mockResolvedValue(tab);
      (prisma.tab.update as jest.Mock).mockResolvedValue(movedTab);

      const result = await WorkspaceService.moveTab(userId, "tab-1", "ws-new");

      expect(result.workspaceId).toBe("ws-new");
    });

    it("should throw error if tab not found", async () => {
      (prisma.workspace.findFirst as jest.Mock).mockResolvedValue({
        id: "ws-new",
        userId,
      });
      (prisma.tab.findUnique as jest.Mock).mockResolvedValue(null);

      await expect(
        WorkspaceService.moveTab(userId, "tab-1", "ws-new"),
      ).rejects.toThrow("Tab not found");
    });
  });

  describe("bulkDeleteTabs", () => {
    it("should delete multiple tabs", async () => {
      const tabs = [
        { id: "tab-1", workspace: { userId } },
        { id: "tab-2", workspace: { userId } },
      ];
      (prisma.tab.findMany as jest.Mock).mockResolvedValue(tabs);
      (prisma.tab.deleteMany as jest.Mock).mockResolvedValue({ count: 2 });

      const result = await WorkspaceService.bulkDeleteTabs(userId, [
        "tab-1",
        "tab-2",
      ]);

      expect(result.deleted).toBe(2);
    });

    it("should reject when the caller lacks edit on a tab's workspace", async () => {
      (prisma.tab.findMany as jest.Mock).mockResolvedValue([
        { workspaceId: "ws-other" },
      ]);
      mockPermission.requireRole.mockRejectedValue(new ForbiddenError());

      await expect(
        WorkspaceService.bulkDeleteTabs(userId, ["tab-1"]),
      ).rejects.toBeInstanceOf(ForbiddenError);
    });
  });

  describe("bulkUpdateTabs", () => {
    it("should reject when the caller lacks edit on a tab's workspace", async () => {
      (prisma.tab.findMany as jest.Mock).mockResolvedValue([
        { workspaceId: "ws-other" },
      ]);
      mockPermission.requireRole.mockRejectedValue(new ForbiddenError());

      await expect(
        WorkspaceService.bulkUpdateTabs(userId, ["tab-1"], "pin"),
      ).rejects.toBeInstanceOf(ForbiddenError);
    });

    it("should pin multiple tabs", async () => {
      const tabs = [
        { id: "tab-1", workspace: { userId } },
        { id: "tab-2", workspace: { userId } },
      ];
      (prisma.tab.findMany as jest.Mock).mockResolvedValue(tabs);
      (prisma.tab.updateMany as jest.Mock).mockResolvedValue({ count: 2 });

      const result = await WorkspaceService.bulkUpdateTabs(
        userId,
        ["tab-1", "tab-2"],
        "pin",
      );

      expect(result.updated).toBe(2);
      expect(prisma.tab.updateMany).toHaveBeenCalledWith({
        where: { id: { in: ["tab-1", "tab-2"] } },
        data: { isPinned: true },
      });
    });
  });

  describe("reorderTab", () => {
    it("should reorder a tab within workspace", async () => {
      const tab = {
        id: "tab-1",
        workspace: { userId },
        position: 0,
      };
      const updatedTab = { ...tab, position: 2 };

      (prisma.tab.findUnique as jest.Mock).mockResolvedValue(tab);
      (prisma.tab.update as jest.Mock).mockResolvedValue(updatedTab);

      const result = await WorkspaceService.reorderTab(userId, "tab-1", 2);

      expect(result.position).toBe(2);
      expect(prisma.tab.update).toHaveBeenCalledWith({
        where: { id: "tab-1" },
        data: { position: 2 },
      });
    });

    it("should throw error if tab not found", async () => {
      (prisma.tab.findUnique as jest.Mock).mockResolvedValue(null);

      await expect(
        WorkspaceService.reorderTab(userId, "tab-1", 2),
      ).rejects.toThrow("Tab not found");
    });
  });
});
