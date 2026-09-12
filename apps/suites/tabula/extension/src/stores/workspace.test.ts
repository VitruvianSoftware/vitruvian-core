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
import { act } from "@testing-library/react";
import { useWorkspaceStore } from "./workspace";
import { WorkspaceService } from "../services/workspace";
import type { Workspace, SpaceGroup } from "../types";

// Mock WorkspaceService
jest.mock("../services/workspace", () => ({
  WorkspaceService: {
    getAllWorkspaces: jest.fn(),
    getActiveWorkspace: jest.fn(),
    getSpaceGroups: jest.fn(),
    createWorkspace: jest.fn(),
    updateWorkspace: jest.fn(),
    deleteWorkspace: jest.fn(),
    saveCurrentTabsToWorkspace: jest.fn(),
    restoreWorkspaceTabs: jest.fn(),
    switchToWorkspace: jest.fn(),
    createSpaceGroup: jest.fn(),
    deleteSpaceGroup: jest.fn(),
    updateSpaceGroup: jest.fn(),
    toggleSpaceGroupCollapse: jest.fn(),
    updateWorkspaceOrders: jest.fn(),
    updateSpaceGroupOrders: jest.fn(),
    moveWorkspaceToGroup: jest.fn(),
  },
}));

// Mock StorageService (used by setActiveWorkspace to persist to Chrome storage)
jest.mock("../services/storage", () => ({
  StorageService: {
    setActiveWorkspaceId: jest.fn().mockResolvedValue(undefined),
  },
}));

describe("useWorkspaceStore", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    useWorkspaceStore.setState({
      workspaces: [],
      spaceGroups: [],
      activeWorkspaceId: null,
      loading: false,
      error: null,
    });
  });

  it("should load workspaces successfully", async () => {
    const workspaces: Workspace[] = [
      { id: "ws1", name: "Work", position: 1 } as any,
    ];
    const spaceGroups: SpaceGroup[] = [{ id: "sg1", title: "Group" } as any];
    const activeWorkspace = { id: "ws1" } as any;

    (WorkspaceService.getAllWorkspaces as jest.Mock).mockResolvedValue(
      workspaces,
    );
    (WorkspaceService.getSpaceGroups as jest.Mock).mockResolvedValue(
      spaceGroups,
    );
    (WorkspaceService.getActiveWorkspace as jest.Mock).mockResolvedValue(
      activeWorkspace,
    );

    await act(async () => {
      await useWorkspaceStore.getState().loadWorkspaces();
    });

    const state = useWorkspaceStore.getState();
    expect(state.workspaces).toEqual(workspaces);
    expect(state.spaceGroups).toEqual(spaceGroups);
    expect(state.activeWorkspaceId).toBe("ws1");
    expect(state.loading).toBe(false);
    expect(state.error).toBeNull();
  });

  it("should handle load error", async () => {
    (WorkspaceService.getAllWorkspaces as jest.Mock).mockRejectedValue(
      new Error("Load failed"),
    );

    await act(async () => {
      await useWorkspaceStore.getState().loadWorkspaces();
    });

    const state = useWorkspaceStore.getState();
    expect(state.error).toBe("Load failed");
    expect(state.loading).toBe(false);
  });

  it("should create workspace", async () => {
    const newWorkspace = { id: "ws2", name: "New" } as any;
    (WorkspaceService.createWorkspace as jest.Mock).mockResolvedValue(
      newWorkspace,
    );

    await act(async () => {
      await useWorkspaceStore.getState().createWorkspace({ name: "New" });
    });

    const state = useWorkspaceStore.getState();
    expect(state.workspaces).toContainEqual(newWorkspace);
    expect(state.loading).toBe(false);
  });

  it("should update workspace", async () => {
    const initial = { id: "ws1", name: "Old" } as any;
    useWorkspaceStore.setState({ workspaces: [initial] });

    const updated = { id: "ws1", name: "New" } as any;
    (WorkspaceService.updateWorkspace as jest.Mock).mockResolvedValue(updated);

    await act(async () => {
      await useWorkspaceStore
        .getState()
        .updateWorkspace("ws1", { name: "New" });
    });

    const state = useWorkspaceStore.getState();
    expect(state.workspaces[0]).toEqual(updated);
  });

  it("should delete workspace", async () => {
    const initial = { id: "ws1", name: "To Delete" } as any;
    useWorkspaceStore.setState({
      workspaces: [initial],
      activeWorkspaceId: "ws1",
    });

    (WorkspaceService.deleteWorkspace as jest.Mock).mockResolvedValue(
      undefined,
    );

    await act(async () => {
      await useWorkspaceStore.getState().deleteWorkspace("ws1");
    });

    const state = useWorkspaceStore.getState();
    expect(state.workspaces).toHaveLength(0);
    expect(state.activeWorkspaceId).toBeNull();
  });

  it("should save current tabs", async () => {
    const initial = { id: "ws1", tabs: [] } as any;
    useWorkspaceStore.setState({ workspaces: [initial] });

    const updated = { id: "ws1", tabs: [{ id: 1 }] } as any;
    (
      WorkspaceService.saveCurrentTabsToWorkspace as jest.Mock
    ).mockResolvedValue(updated);

    await act(async () => {
      await useWorkspaceStore.getState().saveCurrentTabs("ws1");
    });

    const state = useWorkspaceStore.getState();
    expect(state.workspaces[0]).toEqual(updated);
  });

  it("should switch workspace", async () => {
    (WorkspaceService.switchToWorkspace as jest.Mock).mockResolvedValue(
      undefined,
    );

    await act(async () => {
      await useWorkspaceStore.getState().switchWorkspace("ws1");
    });

    expect(useWorkspaceStore.getState().activeWorkspaceId).toBe("ws1");
  });

  it("should restore tabs", async () => {
    (WorkspaceService.restoreWorkspaceTabs as jest.Mock).mockResolvedValue(
      undefined,
    );

    await act(async () => {
      await useWorkspaceStore.getState().restoreTabs("ws1");
    });

    expect(useWorkspaceStore.getState().activeWorkspaceId).toBe("ws1");
  });

  it("should create space group", async () => {
    const group = { id: "sg1", title: "Group" } as any;
    (WorkspaceService.createSpaceGroup as jest.Mock).mockResolvedValue(group);

    await act(async () => {
      await useWorkspaceStore.getState().createSpaceGroup("Group");
    });

    expect(useWorkspaceStore.getState().spaceGroups).toContainEqual(group);
  });

  it("should delete space group", async () => {
    const group = { id: "sg1", title: "Group" } as any;
    useWorkspaceStore.setState({ spaceGroups: [group] });

    (WorkspaceService.deleteSpaceGroup as jest.Mock).mockResolvedValue(
      undefined,
    );
    (WorkspaceService.getAllWorkspaces as jest.Mock).mockResolvedValue([]);

    await act(async () => {
      await useWorkspaceStore.getState().deleteSpaceGroup("sg1");
    });

    expect(useWorkspaceStore.getState().spaceGroups).toHaveLength(0);
  });

  it("should update space group", async () => {
    const group = { id: "sg1", title: "Old" } as any;
    useWorkspaceStore.setState({ spaceGroups: [group] });

    const updated = { id: "sg1", title: "New" } as any;
    (WorkspaceService.updateSpaceGroup as jest.Mock).mockResolvedValue(updated);

    await act(async () => {
      await useWorkspaceStore
        .getState()
        .updateSpaceGroup("sg1", { title: "New" });
    });

    expect(useWorkspaceStore.getState().spaceGroups[0]).toEqual(updated);
  });

  it("should toggle space group collapse", async () => {
    const group = { id: "sg1", collapsed: false } as any;
    useWorkspaceStore.setState({ spaceGroups: [group] });

    const updated = { id: "sg1", collapsed: true } as any;
    (WorkspaceService.toggleSpaceGroupCollapse as jest.Mock).mockResolvedValue(
      updated,
    );

    await act(async () => {
      await useWorkspaceStore.getState().toggleSpaceGroupCollapse("sg1");
    });

    expect(useWorkspaceStore.getState().spaceGroups[0]).toEqual(updated);
  });

  it("should move workspace to group", async () => {
    (WorkspaceService.moveWorkspaceToGroup as jest.Mock).mockResolvedValue(
      undefined,
    );
    (WorkspaceService.getAllWorkspaces as jest.Mock).mockResolvedValue([]);

    await act(async () => {
      await useWorkspaceStore.getState().moveWorkspaceToGroup("ws1", "sg1");
    });

    expect(WorkspaceService.moveWorkspaceToGroup).toHaveBeenCalledWith(
      "ws1",
      "sg1",
    );
  });

  it("should reorder workspaces", async () => {
    const workspaces = [{ id: "ws1" }] as any;
    (WorkspaceService.updateWorkspaceOrders as jest.Mock).mockResolvedValue(
      undefined,
    );

    await act(async () => {
      await useWorkspaceStore.getState().reorderWorkspaces(workspaces);
    });

    expect(useWorkspaceStore.getState().workspaces).toEqual(workspaces);
  });

  it("should handle reorder error by reloading", async () => {
    const workspaces = [{ id: "ws1" }] as any;
    (WorkspaceService.updateWorkspaceOrders as jest.Mock).mockRejectedValue(
      new Error("Fail"),
    );
    (WorkspaceService.getAllWorkspaces as jest.Mock).mockResolvedValue([]);

    await act(async () => {
      await useWorkspaceStore.getState().reorderWorkspaces(workspaces);
    });

    expect(WorkspaceService.getAllWorkspaces).toHaveBeenCalled();
  });

  it("should handle loadSpaceGroups error", async () => {
    (WorkspaceService.getSpaceGroups as jest.Mock).mockRejectedValue(
      new Error("Fail"),
    );

    await act(async () => {
      await useWorkspaceStore.getState().loadSpaceGroups();
    });

    // Should not crash, just log error
    expect(useWorkspaceStore.getState().spaceGroups).toEqual([]);
  });

  it("should handle create workspace error", async () => {
    (WorkspaceService.createWorkspace as jest.Mock).mockRejectedValue(
      new Error("Create failed"),
    );

    await expect(
      act(async () => {
        await useWorkspaceStore.getState().createWorkspace({ name: "Test" });
      }),
    ).rejects.toThrow();

    expect(useWorkspaceStore.getState().error).toBe("Create failed");
    expect(useWorkspaceStore.getState().loading).toBe(false);
  });

  it("should handle update workspace error", async () => {
    (WorkspaceService.updateWorkspace as jest.Mock).mockRejectedValue(
      new Error("Update failed"),
    );

    await expect(
      act(async () => {
        await useWorkspaceStore
          .getState()
          .updateWorkspace("ws1", { name: "Test" });
      }),
    ).rejects.toThrow();

    expect(useWorkspaceStore.getState().error).toBe("Update failed");
    expect(useWorkspaceStore.getState().loading).toBe(false);
  });

  it("should handle delete workspace error", async () => {
    (WorkspaceService.deleteWorkspace as jest.Mock).mockRejectedValue(
      new Error("Delete failed"),
    );

    await expect(
      act(async () => {
        await useWorkspaceStore.getState().deleteWorkspace("ws1");
      }),
    ).rejects.toThrow();

    expect(useWorkspaceStore.getState().error).toBe("Delete failed");
    expect(useWorkspaceStore.getState().loading).toBe(false);
  });

  it("should handle save current tabs error", async () => {
    (
      WorkspaceService.saveCurrentTabsToWorkspace as jest.Mock
    ).mockRejectedValue(new Error("Save tabs failed"));

    await expect(
      act(async () => {
        await useWorkspaceStore.getState().saveCurrentTabs("ws1");
      }),
    ).rejects.toThrow();

    expect(useWorkspaceStore.getState().error).toBe("Save tabs failed");
  });

  it("should handle restore tabs error", async () => {
    (WorkspaceService.restoreWorkspaceTabs as jest.Mock).mockRejectedValue(
      new Error("Restore failed"),
    );

    await expect(
      act(async () => {
        await useWorkspaceStore.getState().restoreTabs("ws1");
      }),
    ).rejects.toThrow();

    expect(useWorkspaceStore.getState().error).toBe("Restore failed");
  });

  it("should handle switch workspace error", async () => {
    (WorkspaceService.switchToWorkspace as jest.Mock).mockRejectedValue(
      new Error("Switch failed"),
    );

    await expect(
      act(async () => {
        await useWorkspaceStore.getState().switchWorkspace("ws1");
      }),
    ).rejects.toThrow();

    expect(useWorkspaceStore.getState().error).toBe("Switch failed");
  });

  it("should handle create space group error", async () => {
    (WorkspaceService.createSpaceGroup as jest.Mock).mockRejectedValue(
      new Error("Create group failed"),
    );

    await expect(
      act(async () => {
        await useWorkspaceStore.getState().createSpaceGroup("Group");
      }),
    ).rejects.toThrow();
  });

  it("should handle delete space group error", async () => {
    (WorkspaceService.deleteSpaceGroup as jest.Mock).mockRejectedValue(
      new Error("Delete group failed"),
    );

    await expect(
      act(async () => {
        await useWorkspaceStore.getState().deleteSpaceGroup("sg1");
      }),
    ).rejects.toThrow();
  });

  it("should handle update space group error", async () => {
    (WorkspaceService.updateSpaceGroup as jest.Mock).mockRejectedValue(
      new Error("Update group failed"),
    );

    await expect(
      act(async () => {
        await useWorkspaceStore
          .getState()
          .updateSpaceGroup("sg1", { title: "New" });
      }),
    ).rejects.toThrow();
  });

  it("should handle toggle space group collapse error", async () => {
    (WorkspaceService.toggleSpaceGroupCollapse as jest.Mock).mockRejectedValue(
      new Error("Toggle failed"),
    );

    await expect(
      act(async () => {
        await useWorkspaceStore.getState().toggleSpaceGroupCollapse("sg1");
      }),
    ).rejects.toThrow();
  });

  it("should handle move workspace to group error", async () => {
    (WorkspaceService.moveWorkspaceToGroup as jest.Mock).mockRejectedValue(
      new Error("Move failed"),
    );

    await expect(
      act(async () => {
        await useWorkspaceStore.getState().moveWorkspaceToGroup("ws1", "sg1");
      }),
    ).rejects.toThrow();
  });

  it("should set active workspace", async () => {
    await act(async () => {
      await useWorkspaceStore.getState().setActiveWorkspace("ws2");
    });
    expect(useWorkspaceStore.getState().activeWorkspaceId).toBe("ws2");
  });

  it("should handle non-Error object in loadWorkspaces error", async () => {
    (WorkspaceService.getAllWorkspaces as jest.Mock).mockRejectedValue(
      "string error",
    );

    await act(async () => {
      await useWorkspaceStore.getState().loadWorkspaces();
    });

    expect(useWorkspaceStore.getState().error).toBe("Failed to load");
  });

  it("should sort workspaces without position", async () => {
    const workspaces = [
      { id: "ws1", name: "Work" },
      { id: "ws2", name: "Work2" },
    ] as any;
    (WorkspaceService.getAllWorkspaces as jest.Mock).mockResolvedValue(
      workspaces,
    );
    (WorkspaceService.getSpaceGroups as jest.Mock).mockResolvedValue([]);
    (WorkspaceService.getActiveWorkspace as jest.Mock).mockResolvedValue(null);

    await act(async () => {
      await useWorkspaceStore.getState().loadWorkspaces();
    });

    expect(useWorkspaceStore.getState().workspaces).toHaveLength(2);
  });

  it("should handle duplicate workspace creation", async () => {
    const existing = { id: "ws1", name: "Existing" } as any;
    useWorkspaceStore.setState({ workspaces: [existing] });

    (WorkspaceService.createWorkspace as jest.Mock).mockResolvedValue(existing);

    await act(async () => {
      await useWorkspaceStore.getState().createWorkspace({ name: "Existing" });
    });

    // Should not add duplicate
    expect(useWorkspaceStore.getState().workspaces).toHaveLength(1);
  });

  it("should reorder space groups", async () => {
    const groups = [{ id: "sg1" }] as any;
    (WorkspaceService.updateSpaceGroupOrders as jest.Mock).mockResolvedValue(
      undefined,
    );

    await act(async () => {
      await useWorkspaceStore.getState().reorderSpaceGroups(groups);
    });

    expect(useWorkspaceStore.getState().spaceGroups).toEqual(groups);
  });

  it("should handle reorder space groups error by reloading", async () => {
    const groups = [{ id: "sg1" }] as any;
    (WorkspaceService.updateSpaceGroupOrders as jest.Mock).mockRejectedValue(
      new Error("Fail"),
    );
    (WorkspaceService.getSpaceGroups as jest.Mock).mockResolvedValue([]);

    await act(async () => {
      await useWorkspaceStore.getState().reorderSpaceGroups(groups);
    });

    expect(WorkspaceService.getSpaceGroups).toHaveBeenCalled();
  });

  it("should reorder sections", async () => {
    const workspace = { id: "ws1", sections: [] } as any;
    useWorkspaceStore.setState({ workspaces: [workspace] });

    const newSections = [{ id: "s1" }] as any;
    (WorkspaceService.updateWorkspace as jest.Mock).mockResolvedValue({
      ...workspace,
      sections: newSections,
    });

    await act(async () => {
      await useWorkspaceStore.getState().reorderSections("ws1", newSections);
    });

    expect(useWorkspaceStore.getState().workspaces[0].sections).toEqual(
      newSections,
    );
  });

  it("should handle reorder sections for non-existent workspace", async () => {
    useWorkspaceStore.setState({ workspaces: [] });

    const newSections = [{ id: "s1" }] as any;

    await act(async () => {
      await useWorkspaceStore.getState().reorderSections("ws1", newSections);
    });

    // Should not crash
    expect(useWorkspaceStore.getState().workspaces).toEqual([]);
  });

  it("should handle reorder sections error by reloading", async () => {
    const workspace = { id: "ws1", sections: [] } as any;
    useWorkspaceStore.setState({ workspaces: [workspace] });

    (WorkspaceService.updateWorkspace as jest.Mock).mockRejectedValue(
      new Error("Fail"),
    );
    (WorkspaceService.getAllWorkspaces as jest.Mock).mockResolvedValue([]);

    await act(async () => {
      await useWorkspaceStore.getState().reorderSections("ws1", []);
    });

    expect(WorkspaceService.getAllWorkspaces).toHaveBeenCalled();
  });

  it("should handle delete workspace when not active", async () => {
    const initial = { id: "ws1", name: "To Delete" } as any;
    useWorkspaceStore.setState({
      workspaces: [initial],
      activeWorkspaceId: "ws2",
    });

    (WorkspaceService.deleteWorkspace as jest.Mock).mockResolvedValue(
      undefined,
    );

    await act(async () => {
      await useWorkspaceStore.getState().deleteWorkspace("ws1");
    });

    expect(useWorkspaceStore.getState().activeWorkspaceId).toBe("ws2");
  });

  it("should handle reorderWorkspaces error by reloading", async () => {
    const workspace = { id: "ws1", name: "Test" } as any;
    useWorkspaceStore.setState({ workspaces: [workspace] });

    (WorkspaceService.updateWorkspaceOrders as jest.Mock).mockRejectedValue(
      new Error("Fail"),
    );
    (WorkspaceService.getAllWorkspaces as jest.Mock).mockResolvedValue([]);
    (WorkspaceService.getActiveWorkspace as jest.Mock).mockResolvedValue(null);
    (WorkspaceService.getSpaceGroups as jest.Mock).mockResolvedValue([]);

    await act(async () => {
      await useWorkspaceStore.getState().reorderWorkspaces([]);
    });

    // Should reload workspaces on error
    expect(WorkspaceService.getAllWorkspaces).toHaveBeenCalled();
  });

  it("should handle reorderSpaceGroups error by reloading", async () => {
    const group = { id: "sg1", title: "Test" } as any;
    useWorkspaceStore.setState({ spaceGroups: [group] });

    (WorkspaceService.updateSpaceGroupOrders as jest.Mock).mockRejectedValue(
      new Error("Fail"),
    );
    (WorkspaceService.getSpaceGroups as jest.Mock).mockResolvedValue([]);

    await act(async () => {
      await useWorkspaceStore.getState().reorderSpaceGroups([]);
    });

    // Should reload space groups on error
    expect(WorkspaceService.getSpaceGroups).toHaveBeenCalled();
  });

  it("should handle update error for workspace", async () => {
    const workspace = { id: "ws1", name: "Test" } as any;
    useWorkspaceStore.setState({ workspaces: [workspace] });

    (WorkspaceService.updateWorkspace as jest.Mock).mockRejectedValue(
      new Error("Update failed"),
    );

    await expect(
      act(async () => {
        await useWorkspaceStore
          .getState()
          .updateWorkspace("ws1", { name: "New" });
      }),
    ).rejects.toThrow();

    expect(useWorkspaceStore.getState().error).toBe("Update failed");
    expect(useWorkspaceStore.getState().loading).toBe(false);
  });

  it("should handle restore tabs error", async () => {
    (WorkspaceService.restoreWorkspaceTabs as jest.Mock).mockRejectedValue(
      new Error("Restore failed"),
    );

    await expect(
      act(async () => {
        await useWorkspaceStore.getState().restoreTabs("ws1");
      }),
    ).rejects.toThrow();

    expect(useWorkspaceStore.getState().error).toBe("Restore failed");
    expect(useWorkspaceStore.getState().loading).toBe(false);
  });

  it("should handle update space group error", async () => {
    const group = { id: "sg1", title: "Test" } as any;
    useWorkspaceStore.setState({ spaceGroups: [group] });

    (WorkspaceService.updateSpaceGroup as jest.Mock).mockRejectedValue(
      new Error("Update group failed"),
    );

    await expect(
      act(async () => {
        await useWorkspaceStore
          .getState()
          .updateSpaceGroup("sg1", { title: "New" });
      }),
    ).rejects.toThrow();
  });

  it("should set active workspace to null", async () => {
    await act(async () => {
      await useWorkspaceStore.getState().setActiveWorkspace("ws123");
    });
    expect(useWorkspaceStore.getState().activeWorkspaceId).toBe("ws123");

    await act(async () => {
      await useWorkspaceStore.getState().setActiveWorkspace(null);
    });
    expect(useWorkspaceStore.getState().activeWorkspaceId).toBeNull();
  });

  it("should handle null workspaces and space groups from service", async () => {
    (WorkspaceService.getAllWorkspaces as jest.Mock).mockResolvedValue(null);
    (WorkspaceService.getSpaceGroups as jest.Mock).mockResolvedValue(null);
    (WorkspaceService.getActiveWorkspace as jest.Mock).mockResolvedValue(null);

    await act(async () => {
      await useWorkspaceStore.getState().loadWorkspaces();
    });

    const state = useWorkspaceStore.getState();
    expect(state.workspaces).toEqual([]);
    expect(state.spaceGroups).toEqual([]);
    expect(state.activeWorkspaceId).toBeNull();
  });

  it("should not add duplicate workspace when already exists", async () => {
    const existingWorkspace = { id: "ws1", name: "Existing" } as any;
    useWorkspaceStore.setState({ workspaces: [existingWorkspace] });

    // Return same workspace id from service
    (WorkspaceService.createWorkspace as jest.Mock).mockResolvedValue(
      existingWorkspace,
    );

    await act(async () => {
      await useWorkspaceStore.getState().createWorkspace({ name: "Existing" });
    });

    const state = useWorkspaceStore.getState();
    // Should not have duplicates
    expect(state.workspaces.filter((w: any) => w.id === "ws1").length).toBe(1);
  });

  it("should handle workspaces without position", async () => {
    const workspaces = [
      { id: "ws1", name: "No Position" } as any,
      { id: "ws2", name: "Has Position", position: 1 } as any,
    ];
    (WorkspaceService.getAllWorkspaces as jest.Mock).mockResolvedValue(
      workspaces,
    );
    (WorkspaceService.getSpaceGroups as jest.Mock).mockResolvedValue([]);
    (WorkspaceService.getActiveWorkspace as jest.Mock).mockResolvedValue(null);

    await act(async () => {
      await useWorkspaceStore.getState().loadWorkspaces();
    });

    const state = useWorkspaceStore.getState();
    expect(state.workspaces.length).toBe(2);
  });

  it("should handle load error with non-Error object", async () => {
    (WorkspaceService.getAllWorkspaces as jest.Mock).mockRejectedValue(
      "String error",
    );

    await act(async () => {
      await useWorkspaceStore.getState().loadWorkspaces();
    });

    const state = useWorkspaceStore.getState();
    expect(state.error).toBe("Failed to load");
    expect(state.loading).toBe(false);
  });

  it("should handle loadSpaceGroups error", async () => {
    const consoleSpy = jest
      .spyOn(console, "error")
      .mockImplementation(() => {});
    (WorkspaceService.getSpaceGroups as jest.Mock).mockRejectedValue(
      new Error("Load failed"),
    );

    await act(async () => {
      await useWorkspaceStore.getState().loadSpaceGroups();
    });

    expect(consoleSpy).toHaveBeenCalled();
    consoleSpy.mockRestore();
  });
});
