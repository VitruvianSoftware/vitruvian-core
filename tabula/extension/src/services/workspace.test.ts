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

/* eslint-disable @typescript-eslint/no-explicit-any */
/**
 * Unit tests for WorkspaceService
 */

import { WorkspaceService } from "./workspace";
import { StorageService } from "./storage";
import { TabService } from "./tabs";
import type { Workspace } from "../types";
import { AuthService } from "./auth";
import { ApiService } from "./api";
import { SyncService } from "./sync";

jest.mock("../services/storage");
jest.mock("../services/tabs");
jest.mock("./sync");
jest.mock("./auth", () => ({
  AuthService: {
    getToken: jest.fn().mockResolvedValue(null),
  },
}));
jest.mock("./api", () => ({
  ApiService: {
    saveWorkspace: jest.fn(),
    deleteWorkspace: jest.fn(),
    saveSpaceGroup: jest.fn(),
    deleteSpaceGroup: jest.fn().mockResolvedValue(undefined),
    getWorkspaces: jest.fn(),
    getSpaceGroups: jest.fn(),
  },
}));

// Mock global chrome object
// eslint-disable-next-line @typescript-eslint/no-explicit-any
(globalThis as any).chrome = {
  tabs: {
    query: jest.fn(),
  },
  storage: {
    local: {
      get: jest.fn().mockResolvedValue({}), // No force-remote flag by default
    },
  },
};

describe("WorkspaceService", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    ((globalThis as any).chrome.tabs.query as jest.Mock).mockResolvedValue([]);
    // Mock TabService.getCurrentTabGroups with empty array by default
    (TabService.getCurrentTabGroups as jest.Mock).mockResolvedValue([]);
    (TabService.getCurrentTabGroupsResult as jest.Mock).mockResolvedValue({
      groups: [],
      reliable: true,
    });
  });

  describe("createWorkspace", () => {
    it("should create a new workspace", async () => {
      const mockWorkspaces: Workspace[] = [];
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue(
        mockWorkspaces,
      );
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      const input = { name: "Test Workspace" };
      const result = await WorkspaceService.createWorkspace(input);

      expect(result.name).toBe("Test Workspace");
      expect(result.id).toBeDefined();
      expect(result.tabs).toEqual([]);
      expect(StorageService.saveWorkspaces).toHaveBeenCalled();
    });

    it("should throw error when workspace limit reached", async () => {
      const mockWorkspaces: Workspace[] = Array(10)
        .fill(null)
        .map((_, i) => ({
          id: `ws${i}`,
          name: `Workspace ${i}`,
          tabs: [],
          resources: [],
          sections: [],
          notes: [],
          tasks: [],
          position: 0,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        }));
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue(
        mockWorkspaces,
      );

      await expect(
        WorkspaceService.createWorkspace({ name: "Test" }),
      ).rejects.toThrow("Maximum number of workspaces reached");
    });
  });

  describe("updateWorkspace", () => {
    it("should update an existing workspace", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Old Name",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      const result = await WorkspaceService.updateWorkspace("ws1", {
        name: "New Name",
      });

      expect(result.name).toBe("New Name");
      expect(StorageService.saveWorkspaces).toHaveBeenCalled();
    });

    it("should throw error for non-existent workspace", async () => {
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([]);

      await expect(
        WorkspaceService.updateWorkspace("nonexistent", { name: "Test" }),
      ).rejects.toThrow("Workspace not found");
    });
  });

  describe("deleteWorkspace", () => {
    it("should delete a workspace", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
      (StorageService.getActiveWorkspaceId as jest.Mock).mockResolvedValue(
        null,
      );

      await WorkspaceService.deleteWorkspace("ws1");

      expect(StorageService.saveWorkspaces).toHaveBeenCalledWith([]);
    });

    it("should clear active workspace if deleted", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
      (StorageService.getActiveWorkspaceId as jest.Mock).mockResolvedValue(
        "ws1",
      );
      (StorageService.setActiveWorkspaceId as jest.Mock).mockResolvedValue(
        undefined,
      );

      await WorkspaceService.deleteWorkspace("ws1");

      expect(StorageService.setActiveWorkspaceId).toHaveBeenCalledWith(null);
    });
  });

  describe("saveCurrentTabsToWorkspace", () => {
    it("should save current tabs to workspace", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      const tabs = [
        { url: "https://example.com", title: "Example" },
        { url: "https://test.com", title: "Test" },
      ];

      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue(tabs);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      const result = await WorkspaceService.saveCurrentTabsToWorkspace("ws1");

      expect(result.tabs).toEqual(tabs);
      expect(StorageService.saveWorkspaces).toHaveBeenCalled();
    });

    it("should filter out extension pages and dashboard from saved tabs", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      const tabs = [
        { url: "https://example.com", title: "Example" },
        {
          url: "chrome-extension://some-id/dashboard.html",
          title: "Dashboard",
        },
        {
          url: "chrome-extension://some-id/other.html",
          title: "Other Extension",
        },
        { url: "https://google.com", title: "Google" },
      ];

      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue(tabs);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      const result = await WorkspaceService.saveCurrentTabsToWorkspace("ws1");

      expect(result.tabs).toHaveLength(2);
      expect(result.tabs.map((t) => t.url)).toEqual([
        "https://example.com",
        "https://google.com",
      ]);
      expect(StorageService.saveWorkspaces).toHaveBeenCalled();
    });
  });

  describe("restoreWorkspaceTabs", () => {
    it("should restore tabs and filter out extension pages", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [
          {
            url: "https://example.com",
            title: "Example",
            pinned: false,
            active: false,
            id: 1,
            index: 0,
          },
          {
            url: "chrome-extension://some-id/dashboard.html",
            title: "Dashboard",
            pinned: false,
            active: false,
            id: 2,
            index: 1,
          },
          {
            url: "https://google.com",
            title: "Google",
            pinned: false,
            active: false,
            id: 3,
            index: 2,
          },
        ],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };

      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);
      (StorageService.getWorkspaceById as jest.Mock).mockResolvedValue(
        workspace,
      );
      (TabService.closeTabs as jest.Mock).mockResolvedValue(undefined);
      (TabService.openTabs as jest.Mock).mockResolvedValue({
        windowId: undefined,
        created: [],
      });

      // Mock current tabs to be closed
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      ((globalThis as any).chrome.tabs.query as jest.Mock).mockResolvedValue([
        { id: 101, pinned: false, url: "https://old.com" },
        { id: 102, pinned: true, url: "https://pinned.com" }, // Should keep
        { id: 103, pinned: false, url: "chrome-extension://id/dashboard.html" }, // Should keep
      ]);

      await WorkspaceService.restoreWorkspaceTabs("ws1", {
        closeCurrentTabs: true,
      });

      // Should close unpinned, non-extension tabs
      expect(TabService.closeTabs).toHaveBeenCalledWith([101]);

      // Should filter out the chrome-extension tab from restored tabs
      const expectedTabs = [workspace.tabs[0], workspace.tabs[2]];
      expect(TabService.openTabs).toHaveBeenCalledWith(expectedTabs, {
        inNewWindow: undefined,
      });
    });

    it("should throw error if workspace not found", async () => {
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([]);
      (StorageService.getWorkspaceById as jest.Mock).mockResolvedValue(
        undefined,
      );

      await expect(
        WorkspaceService.restoreWorkspaceTabs("nonexistent"),
      ).rejects.toThrow("Workspace not found");
    });

    it("does NOT mark the workspace active when restoring into a NEW window", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [
          {
            url: "https://example.com",
            title: "Example",
            pinned: false,
            id: 1,
            index: 0,
          },
        ],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);
      (StorageService.getWorkspaceById as jest.Mock).mockResolvedValue(
        workspace,
      );
      (StorageService.setActiveWorkspaceId as jest.Mock).mockResolvedValue(
        undefined,
      );
      // openTabs reports the NEW window id and the created tab
      (TabService.openTabs as jest.Mock).mockResolvedValue({
        windowId: 555,
        created: [{ id: 9001 }],
      });

      await WorkspaceService.restoreWorkspaceTabs("ws1", { inNewWindow: true });

      // The new window must NOT become the shared active workspace (that would
      // bind the current window's tab sync to the wrong window)
      expect(StorageService.setActiveWorkspaceId).not.toHaveBeenCalled();
      // Reconciliation must query the NEW window, not the current one
      expect(TabService.getCurrentTabs).toHaveBeenCalledWith(
        expect.anything(),
        555,
      );
    });

    it("preserves tabs that failed to open instead of dropping them", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [
          {
            url: "https://ok.com",
            title: "OK",
            pinned: false,
            id: 1,
            index: 0,
          },
          {
            url: "about:blank",
            title: "Blank",
            pinned: false,
            id: 2,
            index: 1,
          },
        ],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);
      (StorageService.getWorkspaceById as jest.Mock).mockResolvedValue(
        workspace,
      );
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
      (StorageService.setActiveWorkspaceId as jest.Mock).mockResolvedValue(
        undefined,
      );
      // First tab opened, second failed (null)
      (TabService.openTabs as jest.Mock).mockResolvedValue({
        windowId: undefined,
        created: [{ id: 9001 }, null],
      });
      // Chrome reports only the one tab that actually opened
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([
        {
          url: "https://ok.com",
          title: "OK",
          pinned: false,
          id: 9001,
          index: 0,
        },
      ]);

      await WorkspaceService.restoreWorkspaceTabs("ws1", {
        closeCurrentTabs: true,
      });

      // The failed about:blank tab must still be saved (no silent data loss)
      const saved = (StorageService.saveWorkspaces as jest.Mock).mock.calls.at(
        -1,
      )![0];
      const savedWs = saved.find((w: Workspace) => w.id === "ws1");
      const urls = savedWs.tabs.map((t: { url: string }) => t.url);
      expect(urls).toContain("https://ok.com");
      expect(urls).toContain("about:blank");
    });
  });

  describe("getAllWorkspaces", () => {
    it("should return all workspaces", async () => {
      const mockWorkspaces: Workspace[] = [
        {
          id: "ws1",
          name: "Work",
          tabs: [],
          resources: [],
          sections: [],
          notes: [],
          tasks: [],
          position: 0,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        },
        {
          id: "ws2",
          name: "Personal",
          tabs: [],
          resources: [],
          sections: [],
          notes: [],
          tasks: [],
          position: 1,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        },
      ];
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue(
        mockWorkspaces,
      );

      const result = await WorkspaceService.getAllWorkspaces();

      expect(result).toEqual(mockWorkspaces);
      expect(StorageService.getWorkspaces).toHaveBeenCalled();
    });
  });

  describe("getWorkspaceById", () => {
    it("should return workspace by id", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      (StorageService.getWorkspaceById as jest.Mock).mockResolvedValue(
        workspace,
      );

      const result = await WorkspaceService.getWorkspaceById("ws1");

      expect(result).toEqual(workspace);
    });

    it("should return undefined for non-existent workspace", async () => {
      (StorageService.getWorkspaceById as jest.Mock).mockResolvedValue(
        undefined,
      );

      const result = await WorkspaceService.getWorkspaceById("nonexistent");

      expect(result).toBeUndefined();
    });
  });

  describe("addResource", () => {
    it("should add a resource to workspace sections", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      const result = await WorkspaceService.addResource("ws1", {
        title: "Example",
        url: "https://example.com",
      });

      // addResource adds to sections, not resources array
      expect(result.sections).toHaveLength(1);
      expect(result.sections[0].resources).toHaveLength(1);
      expect(result.sections[0].resources[0].title).toBe("Example");
      expect(StorageService.saveWorkspaces).toHaveBeenCalled();
    });
  });

  describe("addTask", () => {
    it("should add a task to workspace", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      (StorageService.getWorkspaceById as jest.Mock).mockResolvedValue(
        workspace,
      );
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      const result = await WorkspaceService.addTask("ws1", "Complete review");

      expect(result.tasks).toHaveLength(1);
      expect(result.tasks[0].title).toBe("Complete review");
      expect(result.tasks[0].completed).toBe(false);
    });
  });

  describe("toggleTask", () => {
    it("should toggle task completion status", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [
          {
            id: "task1",
            title: "Test task",
            completed: false,
            createdAt: Date.now(),
          },
        ],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      (StorageService.getWorkspaceById as jest.Mock).mockResolvedValue(
        workspace,
      );
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      const result = await WorkspaceService.toggleTask("ws1", "task1");

      expect(result.tasks[0].completed).toBe(true);
    });
  });

  describe("getActiveWorkspace", () => {
    it("should return active workspace", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Active",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      (StorageService.getActiveWorkspaceId as jest.Mock).mockResolvedValue(
        "ws1",
      );
      (StorageService.getWorkspaceById as jest.Mock).mockResolvedValue(
        workspace,
      );

      const result = await WorkspaceService.getActiveWorkspace();

      expect(result).toEqual(workspace);
    });

    it("should return null when no active workspace", async () => {
      (StorageService.getActiveWorkspaceId as jest.Mock).mockResolvedValue(
        null,
      );

      const result = await WorkspaceService.getActiveWorkspace();

      expect(result).toBeNull();
    });
  });

  describe("switchToWorkspace", () => {
    it("should switch to workspace", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [
          {
            id: 1,
            url: "https://example.com",
            title: "Example",
            pinned: false,
            active: false,
            index: 0,
          },
        ],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);
      (StorageService.getWorkspaceById as jest.Mock).mockResolvedValue(
        workspace,
      );
      (StorageService.setActiveWorkspaceId as jest.Mock).mockResolvedValue(
        undefined,
      );
      (TabService.closeAllTabs as jest.Mock).mockResolvedValue(undefined);
      (TabService.openTabs as jest.Mock).mockResolvedValue({
        windowId: undefined,
        created: [],
      });

      await WorkspaceService.switchToWorkspace("ws1");

      expect(StorageService.setActiveWorkspaceId).toHaveBeenCalledWith("ws1");
    });
  });

  describe("removeResource", () => {
    it("should remove resource from workspace", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [
          {
            id: "sec1",
            title: "Section 1",
            resources: [
              {
                id: "res1",
                title: "Resource",
                url: "https://example.com",
                createdAt: Date.now(),
              },
            ],
          },
        ],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      const result = await WorkspaceService.removeResource("ws1", "res1");

      expect(result.sections[0].resources).toHaveLength(0);
    });
  });

  describe("mutator error paths", () => {
    beforeEach(() => {
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([]);
      (StorageService.getSpaceGroups as jest.Mock).mockResolvedValue([]);
    });

    it("addNote throws when the workspace is missing", async () => {
      await expect(
        WorkspaceService.addNote("missing", { title: "t", content: "c" }),
      ).rejects.toThrow("Workspace not found");
    });

    it("updateNote throws when the note is missing", async () => {
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        {
          id: "ws1",
          name: "W",
          tabs: [],
          resources: [],
          sections: [],
          notes: [],
          tasks: [],
          position: 0,
          createdAt: 0,
          updatedAt: 0,
        },
      ]);
      await expect(
        WorkspaceService.updateNote("ws1", "no-note", { title: "x" }),
      ).rejects.toThrow("Note not found");
    });

    it("addTask throws when the workspace is missing", async () => {
      await expect(WorkspaceService.addTask("missing", "task")).rejects.toThrow(
        "Workspace not found",
      );
    });

    it("deleteSection throws when the workspace is missing", async () => {
      await expect(
        WorkspaceService.deleteSection("missing", "sec1"),
      ).rejects.toThrow("Workspace not found");
    });

    it("renameSpaceGroup throws when the group is missing", async () => {
      await expect(
        WorkspaceService.renameSpaceGroup("missing", "New"),
      ).rejects.toThrow("Space group not found");
    });
  });

  describe("addNote", () => {
    it("should add note to workspace", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      const result = await WorkspaceService.addNote("ws1", {
        title: "Test Note",
        content: "Note content",
      });

      expect(result.notes).toHaveLength(1);
      expect(result.notes[0].title).toBe("Test Note");
      expect(result.notes[0].content).toBe("Note content");
    });
  });

  describe("updateNote", () => {
    it("should update note in workspace", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [],
        notes: [
          {
            id: "note1",
            title: "Old Title",
            content: "Old content",
            updatedAt: Date.now(),
          },
        ],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      const result = await WorkspaceService.updateNote("ws1", "note1", {
        title: "New Title",
      });

      expect(result.notes[0].title).toBe("New Title");
    });
  });

  describe("deleteNote", () => {
    it("should delete note from workspace", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [],
        notes: [
          {
            id: "note1",
            title: "Note",
            content: "Content",
            updatedAt: Date.now(),
          },
        ],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      const result = await WorkspaceService.deleteNote("ws1", "note1");

      expect(result.notes).toHaveLength(0);
    });
  });

  describe("Section Management", () => {
    describe("addSection", () => {
      it("should add a new section to workspace", async () => {
        const workspace: Workspace = {
          id: "ws1",
          name: "Test",
          tabs: [],
          resources: [],
          sections: [],
          notes: [],
          tasks: [],
          position: 0,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        };
        (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
          workspace,
        ]);
        (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(
          undefined,
        );

        const result = await WorkspaceService.addSection("ws1", "New Section");

        expect(result.sections).toHaveLength(1);
        expect(result.sections[0].title).toBe("New Section");
        expect(StorageService.saveWorkspaces).toHaveBeenCalled();
      });
    });

    describe("deleteSection", () => {
      it("should delete a section from workspace", async () => {
        const workspace: Workspace = {
          id: "ws1",
          name: "Test",
          tabs: [],
          resources: [],
          sections: [{ id: "sec1", title: "Section 1", resources: [] }],
          notes: [],
          tasks: [],
          position: 0,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        };
        (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
          workspace,
        ]);
        (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(
          undefined,
        );

        const result = await WorkspaceService.deleteSection("ws1", "sec1");

        expect(result.sections).toHaveLength(0);
        expect(StorageService.saveWorkspaces).toHaveBeenCalled();
      });
    });

    describe("renameSection", () => {
      it("should rename a section", async () => {
        const workspace: Workspace = {
          id: "ws1",
          name: "Test",
          tabs: [],
          resources: [],
          sections: [{ id: "sec1", title: "Old Title", resources: [] }],
          notes: [],
          tasks: [],
          position: 0,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        };
        (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
          workspace,
        ]);
        (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(
          undefined,
        );

        const result = await WorkspaceService.renameSection(
          "ws1",
          "sec1",
          "New Title",
        );

        expect(result.sections[0].title).toBe("New Title");
        expect(StorageService.saveWorkspaces).toHaveBeenCalled();
      });
    });

    describe("addResourceToSection", () => {
      it("should add resource to specific section", async () => {
        const workspace: Workspace = {
          id: "ws1",
          name: "Test",
          tabs: [],
          resources: [],
          sections: [{ id: "sec1", title: "Section 1", resources: [] }],
          notes: [],
          tasks: [],
          position: 0,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        };
        (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
          workspace,
        ]);
        (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(
          undefined,
        );

        const resource = { title: "Res", url: "https://ex.com" };
        const result = await WorkspaceService.addResourceToSection(
          "ws1",
          "sec1",
          resource,
        );

        expect(result.sections[0].resources).toHaveLength(1);
        expect(result.sections[0].resources[0].title).toBe("Res");
      });
    });

    describe("removeResourceFromSection", () => {
      it("should remove resource from specific section", async () => {
        const workspace: Workspace = {
          id: "ws1",
          name: "Test",
          tabs: [],
          resources: [],
          sections: [
            {
              id: "sec1",
              title: "Section 1",
              resources: [
                {
                  id: "res1",
                  title: "Res",
                  url: "https://ex.com",
                  createdAt: Date.now(),
                },
              ],
            },
          ],
          notes: [],
          tasks: [],
          position: 0,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        };
        (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
          workspace,
        ]);
        (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(
          undefined,
        );

        const result = await WorkspaceService.removeResourceFromSection(
          "ws1",
          "sec1",
          "res1",
        );

        expect(result.sections[0].resources).toHaveLength(0);
      });
    });
  });

  describe("Space Groups", () => {
    describe("getSpaceGroups", () => {
      it("should return space groups from storage", async () => {
        const groups = [
          {
            id: "sg1",
            title: "Group 1",
            collapsed: false,
            position: 0,
            createdAt: Date.now(),
            updatedAt: Date.now(),
          },
        ];
        (StorageService.getSpaceGroups as jest.Mock).mockResolvedValue(groups);

        const result = await WorkspaceService.getSpaceGroups();

        expect(result).toEqual(groups);
      });

      it("should merge remote groups if available", async () => {
        const localGroup = {
          id: "sg1",
          title: "Local",
          collapsed: false,
          position: 0,
          createdAt: 100,
          updatedAt: 100,
        };
        const remoteGroup = {
          id: "sg2",
          title: "Remote",
          collapsed: false,
          position: 1,
          createdAt: 200,
          updatedAt: 200,
        };

        (StorageService.getSpaceGroups as jest.Mock).mockResolvedValue([
          localGroup,
        ]);
        (AuthService.getToken as jest.Mock).mockResolvedValue("token");
        (ApiService.getSpaceGroups as jest.Mock).mockResolvedValue([
          remoteGroup,
        ]);
        (StorageService.saveSpaceGroups as jest.Mock).mockResolvedValue(
          undefined,
        );

        const result = await WorkspaceService.getSpaceGroups();

        expect(result).toHaveLength(2);
        expect(result.map((g) => g.id)).toContain("sg1");
        expect(result.map((g) => g.id)).toContain("sg2");
        expect(StorageService.saveSpaceGroups).toHaveBeenCalled();
      });

      it("should handle API failure gracefully", async () => {
        (StorageService.getSpaceGroups as jest.Mock).mockResolvedValue([]);
        (AuthService.getToken as jest.Mock).mockResolvedValue("token");
        (ApiService.getSpaceGroups as jest.Mock).mockRejectedValue(
          new Error("Fail"),
        );

        const result = await WorkspaceService.getSpaceGroups();
        expect(result).toEqual([]);
      });
    });

    describe("createSpaceGroup", () => {
      it("should create a new space group", async () => {
        (StorageService.getSpaceGroups as jest.Mock).mockResolvedValue([]);
        (StorageService.saveSpaceGroups as jest.Mock).mockResolvedValue(
          undefined,
        );

        const result = await WorkspaceService.createSpaceGroup("New Group");

        expect(result.title).toBe("New Group");
        expect(StorageService.saveSpaceGroups).toHaveBeenCalled();
      });
    });

    describe("deleteSpaceGroup", () => {
      it("should delete a space group and ungroup associated workspaces", async () => {
        const groups = [
          {
            id: "sg1",
            title: "Group 1",
            collapsed: false,
            position: 0,
            createdAt: Date.now(),
            updatedAt: Date.now(),
          },
        ];
        const workspaces = [
          {
            id: "ws1",
            name: "WS1",
            groupId: "sg1",
            tabs: [],
            resources: [],
            sections: [],
            notes: [],
            tasks: [],
            position: 0,
            createdAt: Date.now(),
            updatedAt: Date.now(),
          },
          {
            id: "ws2",
            name: "WS2",
            // No group
            tabs: [],
            resources: [],
            sections: [],
            notes: [],
            tasks: [],
            position: 1,
            createdAt: Date.now(),
            updatedAt: Date.now(),
          },
        ];

        (StorageService.getSpaceGroups as jest.Mock).mockResolvedValue(groups);
        (StorageService.saveSpaceGroups as jest.Mock).mockResolvedValue(
          undefined,
        );
        (StorageService.getWorkspaces as jest.Mock).mockResolvedValue(
          workspaces,
        );
        (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(
          undefined,
        );
        (AuthService.getToken as jest.Mock).mockResolvedValue("token");
        (SyncService.enqueue as jest.Mock).mockResolvedValue(undefined);

        await WorkspaceService.deleteSpaceGroup("sg1");

        expect(StorageService.saveSpaceGroups).toHaveBeenCalledWith([]);

        // Group deletion goes through the durable sync queue, not a direct
        // fire-and-forget API call
        expect(SyncService.enqueue).toHaveBeenCalledWith(
          expect.objectContaining({
            type: "spaceGroup",
            action: "delete",
            entityId: "sg1",
          }),
        );
        expect(ApiService.deleteSpaceGroup).not.toHaveBeenCalled();

        // Verify workspaces are updated — groupId must be null (not undefined,
        // which JSON.stringify drops so the server would never clear it)
        expect(StorageService.saveWorkspaces).toHaveBeenCalledWith(
          expect.arrayContaining([
            expect.objectContaining({ id: "ws1", groupId: null }),
            expect.objectContaining({ id: "ws2" }),
          ]),
        );

        // Verify sync queue for workspace update
        expect(SyncService.enqueue).toHaveBeenCalledWith(
          expect.objectContaining({
            type: "workspace",
            action: "save",
            entityId: "ws1",
            data: expect.objectContaining({ groupId: null }),
          }),
        );
      });
    });
  });

  describe("renameSpaceGroup", () => {
    it("should rename a space group", async () => {
      const groups = [
        {
          id: "sg1",
          title: "Old Title",
          collapsed: false,
          position: 0,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        },
      ];
      (StorageService.getSpaceGroups as jest.Mock).mockResolvedValue(groups);
      (StorageService.saveSpaceGroups as jest.Mock).mockResolvedValue(
        undefined,
      );

      const result = await WorkspaceService.renameSpaceGroup(
        "sg1",
        "New Title",
      );

      expect(result.title).toBe("New Title");
      expect(StorageService.saveSpaceGroups).toHaveBeenCalled();
    });

    it("should throw if group not found", async () => {
      (StorageService.getSpaceGroups as jest.Mock).mockResolvedValue([]);
      await expect(
        WorkspaceService.renameSpaceGroup("sg1", "Title"),
      ).rejects.toThrow("Space group not found");
    });
  });

  describe("updateSpaceGroup", () => {
    it("should update space group color and title", async () => {
      const groups = [
        {
          id: "sg1",
          title: "Title",
          collapsed: false,
          position: 0,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        },
      ];
      (StorageService.getSpaceGroups as jest.Mock).mockResolvedValue(groups);
      (StorageService.saveSpaceGroups as jest.Mock).mockResolvedValue(
        undefined,
      );

      const result = await WorkspaceService.updateSpaceGroup("sg1", {
        color: "#ff0000",
        title: "New",
      });

      expect(result.color).toBe("#ff0000");
      expect(result.title).toBe("New");
    });

    it("should clear color if null passed", async () => {
      const groups = [
        {
          id: "sg1",
          title: "Title",
          color: "#ff0000",
          collapsed: false,
          position: 0,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        },
      ];
      (StorageService.getSpaceGroups as jest.Mock).mockResolvedValue(groups);

      const result = await WorkspaceService.updateSpaceGroup("sg1", {
        color: null,
      });
      // color is now explicitly null (not undefined) to ensure API sync clears the field
      expect(result.color).toBeNull();
    });
  });

  describe("toggleSpaceGroupCollapse", () => {
    it("should toggle space group collapsed state", async () => {
      const groups = [
        {
          id: "sg1",
          title: "Group 1",
          collapsed: false,
          position: 0,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        },
      ];
      (StorageService.getSpaceGroups as jest.Mock).mockResolvedValue(groups);
      (StorageService.saveSpaceGroups as jest.Mock).mockResolvedValue(
        undefined,
      );

      const result = await WorkspaceService.toggleSpaceGroupCollapse("sg1");

      expect(result.collapsed).toBe(true);
    });
  });
});

describe("updateWorkspaceOrders", () => {
  it("should update workspace positions", async () => {
    const workspaces: Workspace[] = [
      {
        id: "ws1",
        name: "First",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      },
      {
        id: "ws2",
        name: "Second",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 1,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      },
    ];
    (AuthService.getToken as jest.Mock).mockResolvedValue(null);
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue(
      workspaces.map((w) => ({ ...w })),
    );
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

    // Swap positions via a UI snapshot
    const snapshot = [
      { ...workspaces[0], position: 1 },
      { ...workspaces[1], position: 0 },
    ];
    await WorkspaceService.updateWorkspaceOrders(snapshot);

    expect(StorageService.saveWorkspaces).toHaveBeenCalledWith(
      expect.arrayContaining([
        expect.objectContaining({ id: "ws1", position: 1 }),
        expect.objectContaining({ id: "ws2", position: 0 }),
      ]),
    );
  });
  describe("moveResource", () => {
    it("should move resource between sections", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [
          {
            id: "sec1",
            title: "Section 1",
            resources: [
              {
                id: "res1",
                title: "R1",
                url: "https://1.com",
                createdAt: Date.now(),
              },
            ],
          },
          {
            id: "sec2",
            title: "Section 2",
            resources: [],
          },
        ],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      const result = await WorkspaceService.moveResource(
        "ws1",
        "res1",
        { type: "section", sectionId: "sec1" },
        { type: "section", sectionId: "sec2", index: 0 },
      );

      expect(result.sections[0].resources).toHaveLength(0);
      expect(result.sections[1].resources).toHaveLength(1);
      expect(result.sections[1].resources[0].id).toBe("res1");
    });

    it("should throw error if source section not found", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);

      await expect(
        WorkspaceService.moveResource(
          "ws1",
          "res1",
          { type: "section", sectionId: "missing" },
          { type: "section", sectionId: "sec2", index: 0 },
        ),
      ).rejects.toThrow("Source section not found");
    });
  });

  describe("Sync Integration", () => {
    beforeEach(() => {
      (AuthService.getToken as jest.Mock).mockResolvedValue("valid-token");
    });

    it("should enqueue sync on createWorkspace", async () => {
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      const result = await WorkspaceService.createWorkspace({ name: "Synced" });

      expect(SyncService.enqueue).toHaveBeenCalledWith(
        expect.objectContaining({
          type: "workspace",
          action: "save",
          entityId: result.id,
        }),
      );
    });

    it("should enqueue sync on updateWorkspace", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      await WorkspaceService.updateWorkspace("ws1", { name: "Updated" });

      expect(SyncService.enqueue).toHaveBeenCalledWith(
        expect.objectContaining({
          type: "workspace",
          action: "save",
          entityId: "ws1",
        }),
      );
    });

    it("should enqueue sync on deleteWorkspace", async () => {
      const workspace: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
        workspace,
      ]);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

      await WorkspaceService.deleteWorkspace("ws1");

      expect(SyncService.enqueue).toHaveBeenCalledWith(
        expect.objectContaining({
          type: "workspace",
          action: "delete",
          entityId: "ws1",
        }),
      );
    });
  });

  describe("Error Handling", () => {
    it("should handle storage errors gracefully in getAllWorkspaces", async () => {
      (StorageService.getWorkspaces as jest.Mock).mockRejectedValue(
        new Error("Storage failure"),
      );

      // getAllWorkspaces catches error? No, checking code...
      // It calls StorageService.getWorkspaces() at the end outside try/catch if API fails or not used.
      // If mock rejects, it should throw.
      await expect(WorkspaceService.getAllWorkspaces()).rejects.toThrow(
        "Storage failure",
      );
    });

    it("should handle API errors in getAllWorkspaces gracefully", async () => {
      // Mock auth to true
      (AuthService.getToken as jest.Mock).mockResolvedValue("token");
      // Mock API failure
      (ApiService.getWorkspaces as jest.Mock).mockRejectedValue(
        new Error("API fail"),
      );
      // Mock local storage success
      (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([]);

      // Should fall back to local
      const result = await WorkspaceService.getAllWorkspaces();
      expect(result).toEqual([]);
    });

    it("should throw on createWorkspace failure", async () => {
      (StorageService.getWorkspaces as jest.Mock).mockRejectedValue(
        new Error("Fail"),
      );
      await expect(
        WorkspaceService.createWorkspace({ name: "Test" }),
      ).rejects.toThrow("Fail");
    });

    it("should throw on addResource failure", async () => {
      (StorageService.getWorkspaces as jest.Mock).mockRejectedValue(
        new Error("Fail"),
      );
      await expect(
        WorkspaceService.addResource("ws1", { title: "T", url: "u" }),
      ).rejects.toThrow("Fail");
    });

    it("should throw on createSpaceGroup failure", async () => {
      (StorageService.getSpaceGroups as jest.Mock).mockRejectedValue(
        new Error("Fail"),
      );
      await expect(WorkspaceService.createSpaceGroup("Group")).rejects.toThrow(
        "Fail",
      );
    });
  });
});

describe("moveWorkspaceToGroup", () => {
  it("should move workspace to a group", async () => {
    const workspace: Workspace = {
      id: "ws1",
      name: "Test",
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([workspace]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

    const result = await WorkspaceService.moveWorkspaceToGroup("ws1", "sg1");
    expect(result.groupId).toBe("sg1");
  });

  it("should ungroup workspace if groupId is null", async () => {
    const workspace: Workspace = {
      id: "ws1",
      name: "Test",
      groupId: "sg1",
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([workspace]);

    const result = await WorkspaceService.moveWorkspaceToGroup("ws1", null);
    expect(result.groupId == null).toBe(true);
  });

  it("should throw if workspace not found", async () => {
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([]);
    await expect(
      WorkspaceService.moveWorkspaceToGroup("ws1", "sg1"),
    ).rejects.toThrow("Workspace not found");
  });
  it("should enqueue a durable sync op when logged in", async () => {
    const workspace: Workspace = {
      id: "ws1",
      name: "Test",
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    (AuthService.getToken as jest.Mock).mockResolvedValue("token");
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([workspace]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
    (SyncService.enqueue as jest.Mock).mockResolvedValue(undefined);

    const result = await WorkspaceService.moveWorkspaceToGroup("ws1", "sg1");

    expect(result.groupId).toBe("sg1");
    expect(StorageService.saveWorkspaces).toHaveBeenCalled();
    expect(SyncService.enqueue).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "workspace",
        action: "save",
        entityId: "ws1",
        data: expect.objectContaining({ id: "ws1", groupId: "sg1" }),
      }),
    );
    expect(ApiService.saveWorkspace).not.toHaveBeenCalled();
  });
});

describe("getAllWorkspaces with API sync", () => {
  it("should merge remote and local workspaces preferring newer local", async () => {
    const now = Date.now();
    const localWorkspace: Workspace = {
      id: "ws1",
      name: "Local Updated",
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: now - 1000,
      updatedAt: now, // Newer
    };
    const remoteWorkspace: Workspace = {
      id: "ws1",
      name: "Remote Old",
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: now - 1000,
      updatedAt: now - 500, // Older
    };
    (AuthService.getToken as jest.Mock).mockResolvedValue("token");
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
      localWorkspace,
    ]);
    (ApiService.getWorkspaces as jest.Mock).mockResolvedValue([
      remoteWorkspace,
    ]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

    const result = await WorkspaceService.getAllWorkspaces();

    expect(result[0].name).toBe("Local Updated");
  });

  it("should include new local workspaces not in remote", async () => {
    const now = Date.now();
    const localOnlyWorkspace: Workspace = {
      id: "ws-local-only",
      name: "Local Only",
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: now,
      updatedAt: now,
    };
    (AuthService.getToken as jest.Mock).mockResolvedValue("token");
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
      localOnlyWorkspace,
    ]);
    (ApiService.getWorkspaces as jest.Mock).mockResolvedValue([]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

    const result = await WorkspaceService.getAllWorkspaces();

    expect(result).toHaveLength(1);
    expect(result[0].id).toBe("ws-local-only");
  });

  it("should fall back to local on API error", async () => {
    const localWorkspace: Workspace = {
      id: "ws1",
      name: "Local",
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    (AuthService.getToken as jest.Mock).mockResolvedValue("token");
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
      localWorkspace,
    ]);
    (ApiService.getWorkspaces as jest.Mock).mockRejectedValue(
      new Error("API Error"),
    );

    const result = await WorkspaceService.getAllWorkspaces();

    expect(result[0].name).toBe("Local");
  });
});

describe("addResource", () => {
  it("should add resource to first section", async () => {
    const workspace: Workspace = {
      id: "ws1",
      name: "Test",
      tabs: [],
      resources: [],
      sections: [{ id: "sec1", title: "Resources", resources: [] }],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([workspace]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

    const result = await WorkspaceService.addResource("ws1", {
      title: "Google",
      url: "https://google.com",
    });

    expect(result.sections[0].resources).toHaveLength(1);
    expect(result.sections[0].resources[0].title).toBe("Google");
  });

  it("should create section if none exist", async () => {
    const workspace: Workspace = {
      id: "ws1",
      name: "Test",
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([workspace]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

    const result = await WorkspaceService.addResource("ws1", {
      title: "Test",
      url: "https://test.com",
    });

    expect(result.sections).toHaveLength(1);
    expect(result.sections[0].title).toBe("Resources");
  });

  it("should throw if workspace not found", async () => {
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([]);

    await expect(
      WorkspaceService.addResource("nonexistent", {
        title: "Test",
        url: "https://test.com",
      }),
    ).rejects.toThrow("Workspace not found");
  });
});

describe("removeResource", () => {
  it("should remove resource from workspace", async () => {
    const workspace: Workspace = {
      id: "ws1",
      name: "Test",
      tabs: [],
      resources: [
        { id: "res1", title: "R1", url: "u1", createdAt: Date.now() },
      ],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([workspace]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

    const result = await WorkspaceService.removeResource("ws1", "res1");

    expect(result.resources).toHaveLength(0);
  });
});

describe("moveResource", () => {
  it("should move resource between sections", async () => {
    const workspace: Workspace = {
      id: "ws1",
      name: "Test",
      tabs: [],
      resources: [],
      sections: [
        {
          id: "sec1",
          title: "Section 1",
          resources: [
            { id: "res1", title: "R1", url: "u1", createdAt: Date.now() },
          ],
        },
        { id: "sec2", title: "Section 2", resources: [] },
      ],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([workspace]);
    (StorageService.getWorkspaceById as jest.Mock).mockResolvedValue(workspace);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

    const result = await WorkspaceService.moveResource(
      "ws1",
      "res1",
      { type: "section", sectionId: "sec1" },
      { type: "section", sectionId: "sec2", index: 0 },
    );

    expect(result.sections[0].resources).toHaveLength(0);
    expect(result.sections[1].resources).toHaveLength(1);
    expect(result.sections[1].resources[0].id).toBe("res1");
  });
});

describe("updateWorkspaceOrders", () => {
  it("should enqueue changed workspaces via SyncService instead of calling the API directly", async () => {
    const stored: Workspace[] = [
      {
        id: "ws1",
        name: "WS1",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      },
    ];
    (AuthService.getToken as jest.Mock).mockResolvedValue("token");
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue(stored);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
    (SyncService.enqueue as jest.Mock).mockResolvedValue(undefined);

    const snapshot = [{ ...stored[0], position: 1 }];
    await WorkspaceService.updateWorkspaceOrders(snapshot);

    expect(StorageService.saveWorkspaces).toHaveBeenCalledWith(
      expect.arrayContaining([
        expect.objectContaining({ id: "ws1", position: 1 }),
      ]),
    );
    expect(SyncService.enqueue).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "workspace",
        action: "save",
        entityId: "ws1",
        data: expect.objectContaining({ position: 1 }),
      }),
    );
    expect(ApiService.saveWorkspace).not.toHaveBeenCalled();
  });

  it("should not enqueue workspaces whose position and group did not change", async () => {
    const stored: Workspace[] = [
      {
        id: "ws1",
        name: "WS1",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 1,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      },
    ];
    (AuthService.getToken as jest.Mock).mockResolvedValue("token");
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue(stored);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
    (SyncService.enqueue as jest.Mock).mockClear();
    (SyncService.enqueue as jest.Mock).mockResolvedValue(undefined);

    await WorkspaceService.updateWorkspaceOrders([{ ...stored[0] }]);

    expect(SyncService.enqueue).not.toHaveBeenCalled();
  });

  it("should handle sync errors gracefully", async () => {
    const stored: Workspace[] = [
      {
        id: "ws1",
        name: "WS1",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      },
    ];
    (AuthService.getToken as jest.Mock).mockResolvedValue("token");
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue(stored);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
    (SyncService.enqueue as jest.Mock).mockRejectedValue(
      new Error("Sync failed"),
    );

    // Should not throw
    await expect(
      WorkspaceService.updateWorkspaceOrders([{ ...stored[0], position: 1 }]),
    ).resolves.not.toThrow();
  });
});

describe("getActiveWorkspace", () => {
  it("should return active workspace", async () => {
    const workspace: Workspace = {
      id: "ws1",
      name: "Active",
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    (StorageService.getActiveWorkspaceId as jest.Mock).mockResolvedValue("ws1");
    (StorageService.getWorkspaceById as jest.Mock).mockResolvedValue(workspace);

    const result = await WorkspaceService.getActiveWorkspace();

    expect(result?.name).toBe("Active");
  });

  it("should return null if no active workspace", async () => {
    (StorageService.getActiveWorkspaceId as jest.Mock).mockResolvedValue(null);

    const result = await WorkspaceService.getActiveWorkspace();

    expect(result).toBeNull();
  });
});

describe("createWorkspace with auth", () => {
  it("should sync new workspace to API when logged in", async () => {
    (AuthService.getToken as jest.Mock).mockResolvedValue("token");
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
    (SyncService.enqueue as jest.Mock).mockImplementation(() => {});

    const result = await WorkspaceService.createWorkspace({ name: "New WS" });

    expect(SyncService.enqueue).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "workspace",
        action: "save",
        entityId: result.id,
      }),
    );
  });
});

describe("updateResource", () => {
  it("should update a resource title and url", async () => {
    const workspace: Workspace = {
      id: "ws1",
      name: "Test",
      tabs: [],
      resources: [
        { id: "res1", title: "Old", url: "old.com", createdAt: Date.now() },
      ],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([workspace]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

    const result = await WorkspaceService.updateResource("ws1", "res1", {
      title: "New",
      url: "new.com",
    });

    expect(result.resources[0].title).toBe("New");
    expect(result.resources[0].url).toBe("new.com");
    expect(StorageService.saveWorkspaces).toHaveBeenCalled();
  });

  it("should throw if resource not found", async () => {
    const workspace: Workspace = {
      id: "ws1",
      name: "Test",
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([workspace]);

    await expect(
      WorkspaceService.updateResource("ws1", "res1", { title: "New" }),
    ).rejects.toThrow("Resource not found");
  });
});

describe("updateResourceInSection", () => {
  it("should update a resource in a section", async () => {
    const workspace: Workspace = {
      id: "ws1",
      name: "Test",
      tabs: [],
      resources: [],
      sections: [
        {
          id: "sec1",
          title: "Section",
          resources: [
            { id: "res1", title: "Old", url: "old.com", createdAt: Date.now() },
          ],
        },
      ],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([workspace]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

    const result = await WorkspaceService.updateResourceInSection(
      "ws1",
      "sec1",
      "res1",
      {
        title: "New",
      },
    );

    expect(result.sections[0].resources[0].title).toBe("New");
  });
});

describe("updateSpaceGroupOrders", () => {
  it("should update space group orders and sync if logged in", async () => {
    const storedGroups = [
      {
        id: "sg1",
        title: "Group 1",
        collapsed: false,
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      },
    ];

    (StorageService.getSpaceGroups as jest.Mock).mockResolvedValue(
      storedGroups,
    );
    (StorageService.saveSpaceGroups as jest.Mock).mockResolvedValue(undefined);
    (AuthService.getToken as jest.Mock).mockResolvedValue("token");
    (SyncService.enqueue as jest.Mock).mockResolvedValue(undefined);

    // Snapshot with a changed position
    await WorkspaceService.updateSpaceGroupOrders([
      { ...storedGroups[0], position: 1 },
    ]);

    expect(StorageService.saveSpaceGroups).toHaveBeenCalledWith(
      expect.arrayContaining([
        expect.objectContaining({ id: "sg1", position: 1 }),
      ]),
    );
    expect(SyncService.enqueue).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "spaceGroup",
        action: "save",
        entityId: "sg1",
        data: expect.objectContaining({ position: 1 }),
      }),
    );
  });

  it("should only apply position from the snapshot, preserving fresh fields", async () => {
    const storedGroups = [
      {
        id: "sg1",
        title: "Renamed Concurrently", // changed AFTER the snapshot was taken
        collapsed: false,
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      },
    ];

    (StorageService.getSpaceGroups as jest.Mock).mockResolvedValue(
      storedGroups,
    );
    (StorageService.saveSpaceGroups as jest.Mock).mockResolvedValue(undefined);
    (AuthService.getToken as jest.Mock).mockResolvedValue("token");
    (SyncService.enqueue as jest.Mock).mockResolvedValue(undefined);

    // Stale snapshot still carries the old title
    await WorkspaceService.updateSpaceGroupOrders([
      { ...storedGroups[0], title: "Old Title", position: 2 },
    ]);

    expect(StorageService.saveSpaceGroups).toHaveBeenCalledWith(
      expect.arrayContaining([
        expect.objectContaining({
          id: "sg1",
          title: "Renamed Concurrently",
          position: 2,
        }),
      ]),
    );
  });
});

describe("sync operations with auth", () => {
  it("should queue workspace sync when logged in during create", async () => {
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
    (AuthService.getToken as jest.Mock).mockResolvedValue("token");
    (SyncService.enqueue as jest.Mock).mockImplementation(() => {});

    await WorkspaceService.createWorkspace({ name: "Test" });

    expect(SyncService.enqueue).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "workspace",
        action: "save",
      }),
    );
  });

  it("should queue workspace sync when logged in during update", async () => {
    const workspace: Workspace = {
      id: "ws1",
      name: "Test",
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([workspace]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
    (AuthService.getToken as jest.Mock).mockResolvedValue("token");
    (SyncService.enqueue as jest.Mock).mockImplementation(() => {});

    await WorkspaceService.updateWorkspace("ws1", { name: "New Name" });

    expect(SyncService.enqueue).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "workspace",
        action: "save",
        entityId: "ws1",
      }),
    );
  });

  it("should queue delete sync when logged in during delete", async () => {
    const workspace: Workspace = {
      id: "ws1",
      name: "Test",
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([workspace]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
    (StorageService.getActiveWorkspaceId as jest.Mock).mockResolvedValue(null);
    (AuthService.getToken as jest.Mock).mockResolvedValue("token");
    (SyncService.enqueue as jest.Mock).mockImplementation(() => {});

    await WorkspaceService.deleteWorkspace("ws1");

    expect(SyncService.enqueue).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "workspace",
        action: "delete",
        entityId: "ws1",
      }),
    );
  });

  it("should NOT queue sync when not logged in", async () => {
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
    (AuthService.getToken as jest.Mock).mockResolvedValue(null);
    (SyncService.enqueue as jest.Mock).mockClear();

    await WorkspaceService.createWorkspace({ name: "Test" });

    expect(SyncService.enqueue).not.toHaveBeenCalled();
  });
});

describe("workspace creation with options", () => {
  it("should use default color and icon when not provided", async () => {
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
    (AuthService.getToken as jest.Mock).mockResolvedValue(null);

    const result = await WorkspaceService.createWorkspace({ name: "Test" });

    expect(result.color).toBe("#4F46E5");
    expect(result.icon).toBe("📁");
  });

  it("should use provided color and icon", async () => {
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
    (AuthService.getToken as jest.Mock).mockResolvedValue(null);

    const result = await WorkspaceService.createWorkspace({
      name: "Test",
      color: "#FF0000",
      icon: "🚀",
    });

    expect(result.color).toBe("#FF0000");
    expect(result.icon).toBe("🚀");
  });

  it("should set correct position for new workspace", async () => {
    const existingWorkspaces: Workspace[] = [
      {
        id: "ws1",
        name: "First",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: [],
        position: 5,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      },
    ];
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue(
      existingWorkspaces,
    );
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
    (AuthService.getToken as jest.Mock).mockResolvedValue(null);

    const result = await WorkspaceService.createWorkspace({ name: "Second" });

    expect(result.position).toBe(6);
  });
});

describe("deleteTask", () => {
  it("should delete task from workspace", async () => {
    const workspace: Workspace = {
      id: "ws1",
      name: "Test",
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [
        {
          id: "task1",
          title: "Task 1",
          completed: false,
          createdAt: Date.now(),
        },
        {
          id: "task2",
          title: "Task 2",
          completed: true,
          createdAt: Date.now(),
        },
      ],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    (StorageService.getWorkspaceById as jest.Mock).mockResolvedValue(workspace);
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([workspace]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
    (AuthService.getToken as jest.Mock).mockResolvedValue(null);

    const result = await WorkspaceService.deleteTask("ws1", "task1");

    expect(result.tasks).toHaveLength(1);
    expect(result.tasks[0].id).toBe("task2");
  });
});

describe("workspace not found errors", () => {
  it("should throw error when updating non-existent resource in section", async () => {
    const workspace: Workspace = {
      id: "ws1",
      name: "Test",
      tabs: [],
      resources: [],
      sections: [{ id: "sec1", title: "Section", resources: [] }],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([workspace]);

    await expect(
      WorkspaceService.updateResourceInSection("ws1", "sec1", "nonexistent", {
        title: "New",
      }),
    ).rejects.toThrow();
  });

  it("should throw error when deleting non-existent workspace", async () => {
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([]);

    await expect(
      WorkspaceService.deleteWorkspace("nonexistent"),
    ).rejects.toThrow("Workspace not found");
  });
});

describe("saveCurrentTabsToWorkspace special tab filtering", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("should filter out about:blank tabs", async () => {
    const workspace: Workspace = {
      id: "ws1",
      name: "Test",
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    const tabs = [
      { url: "https://example.com", title: "Example" },
      { url: "about:blank", title: "Blank" },
      { url: "about:newtab", title: "New Tab" },
    ];

    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([workspace]);
    (TabService.getCurrentTabs as jest.Mock).mockResolvedValue(tabs);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
    (AuthService.getToken as jest.Mock).mockResolvedValue(null);

    const result = await WorkspaceService.saveCurrentTabsToWorkspace("ws1");

    expect(result.tabs).toHaveLength(1);
    expect(result.tabs[0].url).toBe("https://example.com");
  });

  it("should filter out chrome:// tabs", async () => {
    const workspace: Workspace = {
      id: "ws1",
      name: "Test",
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    const tabs = [
      { url: "https://example.com", title: "Example" },
      { url: "chrome://extensions", title: "Extensions" },
      { url: "chrome://settings", title: "Settings" },
    ];

    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([workspace]);
    (TabService.getCurrentTabs as jest.Mock).mockResolvedValue(tabs);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
    (AuthService.getToken as jest.Mock).mockResolvedValue(null);

    const result = await WorkspaceService.saveCurrentTabsToWorkspace("ws1");

    expect(result.tabs).toHaveLength(1);
    expect(result.tabs[0].url).toBe("https://example.com");
  });

  it("should queue sync when logged in", async () => {
    const workspace: Workspace = {
      id: "ws1",
      name: "Test",
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    const tabs = [{ url: "https://example.com", title: "Example" }];

    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([workspace]);
    (TabService.getCurrentTabs as jest.Mock).mockResolvedValue(tabs);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
    (AuthService.getToken as jest.Mock).mockResolvedValue("token");
    (SyncService.enqueue as jest.Mock).mockImplementation(() => {});

    await WorkspaceService.saveCurrentTabsToWorkspace("ws1");

    expect(SyncService.enqueue).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "workspace",
        action: "save",
        entityId: "ws1",
      }),
    );
  });
});

// ============================================
// CONCURRENCY & MERGE HARDENING
// ============================================

/** Build a minimal valid workspace */
const makeWorkspace = (
  id: string,
  overrides: Partial<Workspace> = {},
): Workspace => ({
  id,
  name: id,
  tabs: [],
  resources: [],
  sections: [],
  notes: [],
  tasks: [],
  position: 0,
  createdAt: Date.now(),
  updatedAt: Date.now(),
  ...overrides,
});

/**
 * Back the StorageService mock with a real in-memory store so concurrent
 * read-modify-write races are observable (deep-cloned like chrome.storage).
 */
const installWorkspaceStore = (
  initial: Workspace[],
): { current: () => Workspace[] } => {
  let store: Workspace[] = JSON.parse(JSON.stringify(initial));
  (StorageService.getWorkspaces as jest.Mock).mockImplementation(async () =>
    JSON.parse(JSON.stringify(store)),
  );
  (StorageService.saveWorkspaces as jest.Mock).mockImplementation(
    async (next: Workspace[]) => {
      store = JSON.parse(JSON.stringify(next));
    },
  );
  return { current: () => store };
};

describe("concurrent mutations (cross-context lock)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (AuthService.getToken as jest.Mock).mockResolvedValue(null);
  });

  it("should not lose either write when two mutators run concurrently on different workspaces", async () => {
    const store = installWorkspaceStore([
      makeWorkspace("wsA"),
      makeWorkspace("wsB", {
        notes: [
          {
            id: "note1",
            title: "Note",
            content: "Original",
            updatedAt: Date.now(),
          },
        ],
      }),
    ]);

    // Start both mutations WITHOUT awaiting in between — both would read the
    // same storage snapshot if the lock did not serialize them
    const addTaskPromise = WorkspaceService.addTask("wsA", "Task A");
    const updateNotePromise = WorkspaceService.updateNote("wsB", "note1", {
      content: "Updated",
    });
    await Promise.all([addTaskPromise, updateNotePromise]);

    const finalState = store.current();
    expect(finalState.find((w) => w.id === "wsA")?.tasks).toHaveLength(1);
    expect(finalState.find((w) => w.id === "wsA")?.tasks[0].title).toBe(
      "Task A",
    );
    expect(finalState.find((w) => w.id === "wsB")?.notes[0].content).toBe(
      "Updated",
    );
  });

  it("should not lose a section added concurrently with a resource removal", async () => {
    const store = installWorkspaceStore([
      makeWorkspace("wsA", {
        sections: [
          {
            id: "sec1",
            title: "Section 1",
            resources: [
              {
                id: "res1",
                title: "R",
                url: "https://r.com",
                createdAt: Date.now(),
              },
            ],
          },
        ],
      }),
    ]);

    const removePromise = WorkspaceService.removeResourceFromSection(
      "wsA",
      "sec1",
      "res1",
    );
    const addSectionPromise = WorkspaceService.addSection("wsA", "Section 2");
    await Promise.all([removePromise, addSectionPromise]);

    const finalWs = store.current().find((w) => w.id === "wsA")!;
    expect(finalWs.sections).toHaveLength(2);
    expect(finalWs.sections[0].resources).toHaveLength(0);
  });
});

describe("updateWorkspaceOrders against fresh storage", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (AuthService.getToken as jest.Mock).mockResolvedValue("token");
    (SyncService.enqueue as jest.Mock).mockResolvedValue(undefined);
  });

  it("should not clobber a section added after the UI snapshot was taken", async () => {
    const before = Date.now() - 10000;
    // The UI snapshot was taken when ws1 had no sections
    const staleSnapshot: Workspace[] = [
      makeWorkspace("ws1", { position: 0, updatedAt: before }),
      makeWorkspace("ws2", { position: 1, updatedAt: before }),
    ];

    // Since then, ws1 gained a section (e.g. from another window)
    const store = installWorkspaceStore([
      makeWorkspace("ws1", {
        position: 0,
        sections: [
          { id: "sec-new", title: "Added After Snapshot", resources: [] },
        ],
      }),
      makeWorkspace("ws2", { position: 1 }),
    ]);

    // Reorder using the stale snapshot
    await WorkspaceService.updateWorkspaceOrders([
      { ...staleSnapshot[0], position: 1 },
      { ...staleSnapshot[1], position: 0 },
    ]);

    const finalState = store.current();
    const ws1 = finalState.find((w) => w.id === "ws1")!;
    const ws2 = finalState.find((w) => w.id === "ws2")!;

    // The concurrently-added section survives...
    expect(ws1.sections).toHaveLength(1);
    expect(ws1.sections[0].id).toBe("sec-new");
    // ...and the positions changed
    expect(ws1.position).toBe(1);
    expect(ws2.position).toBe(0);
    // updatedAt was bumped monotonically on the changed entities
    expect(ws1.updatedAt).toBeGreaterThan(before);

    // Changed workspaces go through the durable queue, never the API directly
    expect(ApiService.saveWorkspace).not.toHaveBeenCalled();
    expect(SyncService.enqueue).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "workspace",
        action: "save",
        entityId: "ws1",
      }),
    );
    expect(SyncService.enqueue).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "workspace",
        action: "save",
        entityId: "ws2",
      }),
    );
  });
});

describe("getAllWorkspaces merge semantics", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (AuthService.getToken as jest.Mock).mockResolvedValue("token");
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (
      (globalThis as any).chrome.storage.local.get as jest.Mock
    ).mockResolvedValue({});
    (SyncService.enqueue as jest.Mock).mockResolvedValue(undefined);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
  });

  it("should drop a local workspace that was deleted remotely (has a server version)", async () => {
    // version !== undefined proves this workspace existed on the server;
    // it being absent from the remote list means it was deleted there
    const deletedRemotely = makeWorkspace("ws-deleted", { version: 3 });
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
      deletedRemotely,
    ]);
    (ApiService.getWorkspaces as jest.Mock).mockResolvedValue([]);

    const result = await WorkspaceService.getAllWorkspaces();

    expect(result).toHaveLength(0);
    expect(StorageService.saveWorkspaces).toHaveBeenCalledWith([]);
  });

  it("should keep a never-synced local-only workspace (no version)", async () => {
    const neverSynced = makeWorkspace("ws-local-only");
    expect(neverSynced.version).toBeUndefined();
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([
      neverSynced,
    ]);
    (ApiService.getWorkspaces as jest.Mock).mockResolvedValue([]);

    const result = await WorkspaceService.getAllWorkspaces();

    expect(result).toHaveLength(1);
    expect(result[0].id).toBe("ws-local-only");
  });

  it("should keep remote sync metadata on a winning local copy and enqueue a push", async () => {
    const now = Date.now();
    const localWs = makeWorkspace("ws1", {
      name: "Local Newer",
      updatedAt: now,
      version: 2, // stale local version
    });
    const remoteWs = makeWorkspace("ws1", {
      name: "Remote Older",
      updatedAt: now - 5000,
      version: 5,
      activeDeviceId: "device-2",
      activeDeviceSeenAt: "2026-06-10T00:00:00.000Z",
    });
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([localWs]);
    (ApiService.getWorkspaces as jest.Mock).mockResolvedValue([remoteWs]);

    const result = await WorkspaceService.getAllWorkspaces();

    // Local content wins...
    expect(result[0].name).toBe("Local Newer");
    // ...but the remote's sync metadata is carried over so the next PUT
    // carries the right baseVersion
    expect(result[0].version).toBe(5);
    expect(result[0].activeDeviceId).toBe("device-2");
    expect(result[0].activeDeviceSeenAt).toBe("2026-06-10T00:00:00.000Z");

    // The strictly-newer local copy is pushed so the server converges
    expect(SyncService.enqueue).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "workspace",
        action: "save",
        entityId: "ws1",
        data: expect.objectContaining({ name: "Local Newer", version: 5 }),
      }),
    );
  });

  it("should NOT enqueue a push when local and remote timestamps tie", async () => {
    const now = Date.now();
    const localWs = makeWorkspace("ws1", { name: "Local", updatedAt: now });
    const remoteWs = makeWorkspace("ws1", {
      name: "Remote",
      updatedAt: now,
      version: 4,
    });
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([localWs]);
    (ApiService.getWorkspaces as jest.Mock).mockResolvedValue([remoteWs]);

    const result = await WorkspaceService.getAllWorkspaces();

    // Tie prefers local content but adopts the remote version
    expect(result[0].name).toBe("Local");
    expect(result[0].version).toBe(4);
    expect(SyncService.enqueue).not.toHaveBeenCalled();
  });

  it("should keep force-remote behavior (tabula_force_remote_until)", async () => {
    const remoteWs = makeWorkspace("ws-remote", { name: "Remote Truth" });
    const localWs = makeWorkspace("ws-local", {
      name: "Local Stale",
      updatedAt: Date.now() + 99,
    });
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([localWs]);
    (ApiService.getWorkspaces as jest.Mock).mockResolvedValue([remoteWs]);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (
      (globalThis as any).chrome.storage.local.get as jest.Mock
    ).mockResolvedValue({
      tabula_force_remote_until: Date.now() + 10000,
    });

    const result = await WorkspaceService.getAllWorkspaces();

    expect(result).toEqual([remoteWs]);
    expect(StorageService.saveWorkspaces).toHaveBeenCalledWith([remoteWs]);
  });
});

describe("getSpaceGroups merge semantics", () => {
  const makeGroup = (id: string, overrides = {}) => ({
    id,
    title: id,
    collapsed: false,
    position: 0,
    createdAt: Date.now(),
    updatedAt: Date.now(),
    ...overrides,
  });

  beforeEach(() => {
    jest.clearAllMocks();
    (AuthService.getToken as jest.Mock).mockResolvedValue("token");
    (SyncService.enqueue as jest.Mock).mockResolvedValue(undefined);
    (StorageService.saveSpaceGroups as jest.Mock).mockResolvedValue(undefined);
  });

  it("should drop a local group deleted remotely (has version) and keep never-synced ones", async () => {
    const deletedRemotely = makeGroup("sg-deleted", { version: 2 });
    const neverSynced = makeGroup("sg-new");
    (StorageService.getSpaceGroups as jest.Mock).mockResolvedValue([
      deletedRemotely,
      neverSynced,
    ]);
    (ApiService.getSpaceGroups as jest.Mock).mockResolvedValue([]);

    const result = await WorkspaceService.getSpaceGroups();

    expect(result.map((g) => g.id)).toEqual(["sg-new"]);
  });

  it("should keep remote version on a winning local group and enqueue a push", async () => {
    const now = Date.now();
    const localGroup = makeGroup("sg1", {
      title: "Local Newer",
      updatedAt: now,
      version: 1,
    });
    const remoteGroup = makeGroup("sg1", {
      title: "Remote Older",
      updatedAt: now - 5000,
      version: 7,
    });
    (StorageService.getSpaceGroups as jest.Mock).mockResolvedValue([
      localGroup,
    ]);
    (ApiService.getSpaceGroups as jest.Mock).mockResolvedValue([remoteGroup]);

    const result = await WorkspaceService.getSpaceGroups();

    expect(result[0].title).toBe("Local Newer");
    expect(result[0].version).toBe(7);
    expect(SyncService.enqueue).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "spaceGroup",
        action: "save",
        entityId: "sg1",
        data: expect.objectContaining({ title: "Local Newer", version: 7 }),
      }),
    );
  });
});

describe("tab-sync durability metadata", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (TabService.getCurrentTabGroups as jest.Mock).mockResolvedValue([]);
    (TabService.getCurrentTabGroupsResult as jest.Mock).mockResolvedValue({
      groups: [],
      reliable: true,
    });
    (AuthService.getToken as jest.Mock).mockResolvedValue("token");
    (SyncService.enqueue as jest.Mock).mockResolvedValue(undefined);
  });

  it("updateWorkspaceTabs should enqueue with source tabSync", async () => {
    const workspace = makeWorkspace("ws1");
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([workspace]);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);

    await WorkspaceService.updateWorkspaceTabs("ws1", [], []);

    expect(SyncService.enqueue).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "workspace",
        action: "save",
        entityId: "ws1",
        meta: { source: "tabSync" },
      }),
    );
  });

  it("restoreWorkspaceTabs should enqueue the fresh tab state with claimActiveDevice", async () => {
    const workspace = makeWorkspace("ws1", {
      tabs: [
        {
          id: 1,
          url: "https://example.com",
          title: "Example",
          pinned: false,
          active: false,
          index: 0,
        },
      ],
    });
    (StorageService.getWorkspaces as jest.Mock).mockResolvedValue([workspace]);
    (StorageService.getWorkspaceById as jest.Mock).mockResolvedValue(workspace);
    (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
    (StorageService.setActiveWorkspaceId as jest.Mock).mockResolvedValue(
      undefined,
    );
    (TabService.openTabs as jest.Mock).mockResolvedValue({
      windowId: undefined,
      created: [],
    });
    (TabService.getCurrentTabs as jest.Mock).mockResolvedValue(workspace.tabs);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    ((globalThis as any).chrome.tabs.query as jest.Mock).mockResolvedValue([]);

    await WorkspaceService.restoreWorkspaceTabs("ws1");

    expect(SyncService.enqueue).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "workspace",
        action: "save",
        entityId: "ws1",
        meta: { claimActiveDevice: true },
      }),
    );
  });
});
