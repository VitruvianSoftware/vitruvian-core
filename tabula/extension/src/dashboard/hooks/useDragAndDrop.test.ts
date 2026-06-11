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
import { renderHook, act } from "@testing-library/react";
import { useDragAndDrop } from "./useDragAndDrop";
import { WorkspaceService } from "../../services/workspace";
import { TabService } from "../../services/tabs";
import { TabSyncService } from "../../services/tabSync";
import { Workspace, SpaceGroup } from "../../types";

// Mock services
jest.mock("../../services/workspace");
jest.mock("../../services/tabs");
jest.mock("../../services/tabSync");

// Mock dnd-kit
jest.mock("@dnd-kit/core", () => ({
  useSensor: jest.fn(),
  useSensors: jest.fn(),
  PointerSensor: jest.fn(),
  KeyboardSensor: jest.fn(),
}));

jest.mock("@dnd-kit/sortable", () => ({
  arrayMove: jest.fn((array, from, to) => {
    const newArray = [...array];
    const [moved] = newArray.splice(from, 1);
    newArray.splice(to, 0, moved);
    return newArray;
  }),
  sortableKeyboardCoordinates: jest.fn(),
}));

describe("useDragAndDrop", () => {
  const mockSetActiveWorkspaceData = jest.fn();
  const mockReorderWorkspaces = jest.fn();
  const mockLoadWorkspaces = jest.fn();
  const mockReorderSpaceGroups = jest.fn();
  const mockReorderSections = jest.fn();

  const mockWorkspace: Workspace = {
    id: "ws1",
    name: "Test Workspace",
    tabs: [],
    resources: [],
    sections: [
      {
        id: "sec1",
        title: "Section 1",
        resources: [{ id: "res1", title: "R1", url: "u1", createdAt: 0 }],
      },
      { id: "sec2", title: "Section 2", resources: [] },
    ],
    notes: [],
    tasks: [],
    position: 0,
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };

  const mockWorkspaces: Workspace[] = [
    { ...mockWorkspace, position: 0 },
    { ...mockWorkspace, id: "ws2", name: "WS 2", position: 1 },
  ];

  const mockSpaceGroups: SpaceGroup[] = [];

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("Drag Start", () => {
    it("should set activeId on drag start", () => {
      const { result } = renderHook(() =>
        useDragAndDrop({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
          workspaces: mockWorkspaces,
          spaceGroups: mockSpaceGroups,
          reorderWorkspaces: mockReorderWorkspaces,
          loadWorkspaces: mockLoadWorkspaces,
          reorderSpaceGroups: mockReorderSpaceGroups,
          reorderSections: mockReorderSections,
        }),
      );

      act(() => {
        result.current.handleDragStart({ active: { id: "test-id" } } as any);
      });

      expect(result.current.activeId).toBe("test-id");
    });
  });

  describe("Sidebar Drag End", () => {
    it("should reorder workspaces", async () => {
      const { result } = renderHook(() =>
        useDragAndDrop({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
          workspaces: mockWorkspaces,
          spaceGroups: mockSpaceGroups,
          reorderWorkspaces: mockReorderWorkspaces,
          loadWorkspaces: mockLoadWorkspaces,
          reorderSpaceGroups: mockReorderSpaceGroups,
          reorderSections: mockReorderSections,
        }),
      );

      await act(async () => {
        await result.current.handleSidebarDragEnd({
          active: { id: "ws1" },
          over: { id: "ws2" },
        } as any);
      });

      expect(mockReorderWorkspaces).toHaveBeenCalled();
    });

    it("should not reorder if dropped on self", async () => {
      const { result } = renderHook(() =>
        useDragAndDrop({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
          workspaces: mockWorkspaces,
          spaceGroups: mockSpaceGroups,
          reorderWorkspaces: mockReorderWorkspaces,
          loadWorkspaces: mockLoadWorkspaces,
          reorderSpaceGroups: mockReorderSpaceGroups,
          reorderSections: mockReorderSections,
        }),
      );

      await act(async () => {
        await result.current.handleSidebarDragEnd({
          active: { id: "ws1" },
          over: { id: "ws1" },
        } as any);
      });

      expect(mockReorderWorkspaces).not.toHaveBeenCalled();
    });
  });

  describe("Resource Drag End", () => {
    it("should move resource between sections", async () => {
      (WorkspaceService.moveResource as jest.Mock).mockResolvedValue(true);

      const { result } = renderHook(() =>
        useDragAndDrop({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
          workspaces: mockWorkspaces,
          spaceGroups: mockSpaceGroups,
          reorderWorkspaces: mockReorderWorkspaces,
          loadWorkspaces: mockLoadWorkspaces,
          reorderSpaceGroups: mockReorderSpaceGroups,
          reorderSections: mockReorderSections,
        }),
      );

      // Start drag to set activeId (needed for some logic inside finding containers)
      act(() => {
        result.current.handleDragStart({ active: { id: "res1" } } as any);
      });

      await act(async () => {
        await result.current.handleDragEnd({
          active: { id: "res1", data: { current: { type: "resource" } } },
          over: {
            id: "sec2",
            data: { current: { type: "section", sectionId: "sec2" } },
          },
        } as any);
      });

      expect(WorkspaceService.moveResource).toHaveBeenCalledWith(
        "ws1",
        "res1",
        expect.objectContaining({ sectionId: "sec1" }),
        expect.objectContaining({ sectionId: "sec2" }),
      );
    });

    it("should not move if no active workspace", async () => {
      const { result } = renderHook(() =>
        useDragAndDrop({
          activeWorkspace: null,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
          workspaces: mockWorkspaces,
          spaceGroups: mockSpaceGroups,
          reorderWorkspaces: mockReorderWorkspaces,
          loadWorkspaces: mockLoadWorkspaces,
          reorderSpaceGroups: mockReorderSpaceGroups,
          reorderSections: mockReorderSections,
        }),
      );

      await act(async () => {
        await result.current.handleDragEnd({
          active: { id: "res1" },
          over: { id: "sec2" },
        } as any);
      });

      expect(WorkspaceService.moveResource).not.toHaveBeenCalled();
    });
  });

  describe("Tab Drag End", () => {
    it("should create new resource from tab drop on section", async () => {
      (WorkspaceService.addResourceToSection as jest.Mock).mockResolvedValue(
        true,
      );

      const { result } = renderHook(() =>
        useDragAndDrop({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
          workspaces: mockWorkspaces,
          spaceGroups: mockSpaceGroups,
          reorderWorkspaces: mockReorderWorkspaces,
          loadWorkspaces: mockLoadWorkspaces,
          reorderSpaceGroups: mockReorderSpaceGroups,
          reorderSections: mockReorderSections,
        }),
      );

      await act(async () => {
        await result.current.handleDragEnd({
          active: {
            id: "tab-1",
            data: {
              current: {
                type: "tab",
                tab: { title: "New", url: "http://test.com" },
              },
            },
          },
          over: { id: "sec1", data: { current: { type: "section" } } },
        } as any);
      });

      expect(WorkspaceService.addResourceToSection).toHaveBeenCalledWith(
        "ws1",
        "sec1",
        expect.objectContaining({ title: "New", url: "http://test.com" }),
      );
    });
  });
  describe("Drag Over", () => {
    it("should reorder tabs when dragging tab over tab", async () => {
      const mockTabs = [
        {
          id: 1,
          title: "T1",
          url: "u1",
          favIconUrl: "",
          active: false,
          index: 0,
          windowId: 1,
        },
        {
          id: 2,
          title: "T2",
          url: "u2",
          favIconUrl: "",
          active: false,
          index: 1,
          windowId: 1,
        },
      ];
      const workspaceWithTabs = { ...mockWorkspace, tabs: mockTabs };

      // Mock TabService.getTab to return the target tab's index
      (TabService.getTab as jest.Mock).mockResolvedValue({ id: 2, index: 1 });
      (TabSyncService.moveTab as jest.Mock).mockResolvedValue(undefined);

      const { result } = renderHook(() =>
        useDragAndDrop({
          activeWorkspace: workspaceWithTabs as any,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
          workspaces: mockWorkspaces,
          spaceGroups: mockSpaceGroups,
          reorderWorkspaces: mockReorderWorkspaces,
          loadWorkspaces: mockLoadWorkspaces,
          reorderSpaceGroups: mockReorderSpaceGroups,
          reorderSections: mockReorderSections,
        }),
      );

      // Start drag
      act(() => {
        result.current.handleDragStart({
          active: {
            id: "tab-1",
            data: { current: { type: "tab", tab: mockTabs[0] } },
          },
        } as any);
      });

      // Drag end - now uses Chrome API directly
      await act(async () => {
        await result.current.handleDragEnd({
          active: {
            id: "tab-1",
            data: { current: { type: "tab", tab: mockTabs[0] } },
          },
          over: {
            id: "tab-2",
            data: { current: { type: "tab", tab: mockTabs[1] } },
          },
        } as any);
      });

      // With new event-driven pattern, we call Chrome API directly
      // and let Chrome events update the workspace state
      expect(TabSyncService.moveTab).toHaveBeenCalledWith(1, 1);
    });
  });

  describe("Edge Cases", () => {
    it("should handle no over target on sidebar drag end", async () => {
      const { result } = renderHook(() =>
        useDragAndDrop({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
          workspaces: mockWorkspaces,
          spaceGroups: mockSpaceGroups,
          reorderWorkspaces: mockReorderWorkspaces,
          loadWorkspaces: mockLoadWorkspaces,
          reorderSpaceGroups: mockReorderSpaceGroups,
          reorderSections: mockReorderSections,
        }),
      );

      await act(async () => {
        await result.current.handleSidebarDragEnd({
          active: { id: "ws1" },
          over: null,
        } as any);
      });

      expect(mockReorderWorkspaces).not.toHaveBeenCalled();
    });

    it("should handle no over target on drag end", async () => {
      const { result } = renderHook(() =>
        useDragAndDrop({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
          workspaces: mockWorkspaces,
          spaceGroups: mockSpaceGroups,
          reorderWorkspaces: mockReorderWorkspaces,
          loadWorkspaces: mockLoadWorkspaces,
          reorderSpaceGroups: mockReorderSpaceGroups,
          reorderSections: mockReorderSections,
        }),
      );

      await act(async () => {
        await result.current.handleDragEnd({
          active: { id: "res1" },
          over: null,
        } as any);
      });

      expect(WorkspaceService.moveResource).not.toHaveBeenCalled();
    });

    it("should handle missing workspace on sidebar drag", async () => {
      const { result } = renderHook(() =>
        useDragAndDrop({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
          workspaces: mockWorkspaces,
          spaceGroups: mockSpaceGroups,
          reorderWorkspaces: mockReorderWorkspaces,
          loadWorkspaces: mockLoadWorkspaces,
          reorderSpaceGroups: mockReorderSpaceGroups,
          reorderSections: mockReorderSections,
        }),
      );

      await act(async () => {
        await result.current.handleSidebarDragEnd({
          active: { id: "nonexistent-ws" },
          over: { id: "ws2" },
        } as any);
      });

      expect(mockReorderWorkspaces).not.toHaveBeenCalled();
    });
  });

  describe("Section Reordering", () => {
    it("should reorder sections within workspace", async () => {
      const workspaceWithSections = {
        ...mockWorkspace,
        sections: [
          { id: "sec1", title: "Section 1", resources: [] },
          { id: "sec2", title: "Section 2", resources: [] },
          { id: "sec3", title: "Section 3", resources: [] },
        ],
      };

      const { result } = renderHook(() =>
        useDragAndDrop({
          activeWorkspace: workspaceWithSections,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
          workspaces: mockWorkspaces,
          spaceGroups: mockSpaceGroups,
          reorderWorkspaces: mockReorderWorkspaces,
          loadWorkspaces: mockLoadWorkspaces,
          reorderSpaceGroups: mockReorderSpaceGroups,
          reorderSections: mockReorderSections,
        }),
      );

      await act(async () => {
        await result.current.handleDragEnd({
          active: { id: "sec1", data: { current: { type: "Section" } } },
          over: { id: "sec3", data: { current: { type: "Section" } } },
        } as any);
      });

      expect(mockReorderSections).toHaveBeenCalledWith(
        "ws1",
        expect.arrayContaining([
          expect.objectContaining({ id: "sec2" }),
          expect.objectContaining({ id: "sec3" }),
          expect.objectContaining({ id: "sec1" }),
        ]),
      );
    });

    it("should not reorder sections if indices are the same", async () => {
      const { result } = renderHook(() =>
        useDragAndDrop({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
          workspaces: mockWorkspaces,
          spaceGroups: mockSpaceGroups,
          reorderWorkspaces: mockReorderWorkspaces,
          loadWorkspaces: mockLoadWorkspaces,
          reorderSpaceGroups: mockReorderSpaceGroups,
          reorderSections: mockReorderSections,
        }),
      );

      await act(async () => {
        await result.current.handleDragEnd({
          active: { id: "sec1", data: { current: { type: "Section" } } },
          over: { id: "sec1", data: { current: { type: "Section" } } },
        } as any);
      });

      expect(mockReorderSections).not.toHaveBeenCalled();
    });
  });

  describe("Space Group Reordering", () => {
    it("should reorder space groups", async () => {
      const spaceGroupsForTest: SpaceGroup[] = [
        {
          id: "sg1",
          title: "Group 1",
          position: 0,
          collapsed: false,
          createdAt: 0,
          updatedAt: 0,
        },
        {
          id: "sg2",
          title: "Group 2",
          position: 1,
          collapsed: false,
          createdAt: 0,
          updatedAt: 0,
        },
      ];

      const { result } = renderHook(() =>
        useDragAndDrop({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
          workspaces: mockWorkspaces,
          spaceGroups: spaceGroupsForTest,
          reorderWorkspaces: mockReorderWorkspaces,
          loadWorkspaces: mockLoadWorkspaces,
          reorderSpaceGroups: mockReorderSpaceGroups,
          reorderSections: mockReorderSections,
        }),
      );

      await act(async () => {
        await result.current.handleSidebarDragEnd({
          active: { id: "sg1", data: { current: { type: "SpaceGroup" } } },
          over: { id: "sg2", data: { current: { type: "SpaceGroup" } } },
        } as any);
      });

      expect(mockReorderSpaceGroups).toHaveBeenCalled();
    });

    it("should not reorder space groups when indices not found", async () => {
      const spaceGroupsForTest: SpaceGroup[] = [
        {
          id: "sg1",
          title: "Group 1",
          position: 0,
          collapsed: false,
          createdAt: 0,
          updatedAt: 0,
        },
      ];

      const { result } = renderHook(() =>
        useDragAndDrop({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
          workspaces: mockWorkspaces,
          spaceGroups: spaceGroupsForTest,
          reorderWorkspaces: mockReorderWorkspaces,
          loadWorkspaces: mockLoadWorkspaces,
          reorderSpaceGroups: mockReorderSpaceGroups,
          reorderSections: mockReorderSections,
        }),
      );

      await act(async () => {
        await result.current.handleSidebarDragEnd({
          active: { id: "sg1", data: { current: { type: "SpaceGroup" } } },
          over: {
            id: "nonexistent",
            data: { current: { type: "SpaceGroup" } },
          },
        } as any);
      });

      expect(mockReorderSpaceGroups).not.toHaveBeenCalled();
    });
  });

  describe("Tab Drop to Workspace", () => {
    it("should add resource to workspace when tab dropped on workspace", async () => {
      const workspacesWithSection: Workspace[] = [
        {
          ...mockWorkspace,
          sections: [{ id: "res-sec", title: "Resources", resources: [] }],
        },
        { ...mockWorkspace, id: "ws2", name: "WS 2", position: 1 },
      ];

      (WorkspaceService.addResourceToSection as jest.Mock).mockResolvedValue(
        true,
      );

      const { result } = renderHook(() =>
        useDragAndDrop({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
          workspaces: workspacesWithSection,
          spaceGroups: mockSpaceGroups,
          reorderWorkspaces: mockReorderWorkspaces,
          loadWorkspaces: mockLoadWorkspaces,
          reorderSpaceGroups: mockReorderSpaceGroups,
          reorderSections: mockReorderSections,
        }),
      );

      await act(async () => {
        await result.current.handleDragEnd({
          active: {
            id: "tab-1",
            data: {
              current: {
                type: "tab",
                tab: {
                  title: "Tab Title",
                  url: "http://example.com",
                  favIconUrl: "favicon.ico",
                },
              },
            },
          },
          over: {
            id: "ws1",
            data: { current: { type: "workspace", workspaceId: "ws1" } },
          },
        } as any);
      });

      expect(WorkspaceService.addResourceToSection).toHaveBeenCalled();
      expect(mockLoadWorkspaces).toHaveBeenCalled();
    });
  });

  describe("Workspace Drop to Ungrouped", () => {
    it("should move workspace to ungrouped when dropped on ungrouped-list", async () => {
      const groupedWorkspaces: Workspace[] = [
        { ...mockWorkspace, groupId: "group1", position: 0 },
        { ...mockWorkspace, id: "ws2", name: "WS 2", position: 1 },
      ];

      const { result } = renderHook(() =>
        useDragAndDrop({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
          workspaces: groupedWorkspaces,
          spaceGroups: mockSpaceGroups,
          reorderWorkspaces: mockReorderWorkspaces,
          loadWorkspaces: mockLoadWorkspaces,
          reorderSpaceGroups: mockReorderSpaceGroups,
          reorderSections: mockReorderSections,
        }),
      );

      await act(async () => {
        await result.current.handleSidebarDragEnd({
          active: { id: "ws1" },
          over: { id: "ungrouped-list" },
        } as any);
      });

      expect(mockReorderWorkspaces).toHaveBeenCalledWith(
        expect.arrayContaining([
          expect.objectContaining({ id: "ws1", groupId: undefined }),
        ]),
      );
    });
  });

  describe("Resource Reordering Within Same Section", () => {
    it("should reorder resources within the same section", async () => {
      const workspaceWithResources = {
        ...mockWorkspace,
        sections: [
          {
            id: "sec1",
            title: "Section 1",
            resources: [
              { id: "res1", title: "R1", url: "u1", createdAt: 0 },
              { id: "res2", title: "R2", url: "u2", createdAt: 0 },
              { id: "res3", title: "R3", url: "u3", createdAt: 0 },
            ],
          },
        ],
      };

      (WorkspaceService.moveResource as jest.Mock).mockResolvedValue(true);

      const { result } = renderHook(() =>
        useDragAndDrop({
          activeWorkspace: workspaceWithResources,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
          workspaces: mockWorkspaces,
          spaceGroups: mockSpaceGroups,
          reorderWorkspaces: mockReorderWorkspaces,
          loadWorkspaces: mockLoadWorkspaces,
          reorderSpaceGroups: mockReorderSpaceGroups,
          reorderSections: mockReorderSections,
        }),
      );

      await act(async () => {
        await result.current.handleDragEnd({
          active: { id: "res1", data: { current: { type: "resource" } } },
          over: { id: "res3", data: { current: { type: "resource" } } },
        } as any);
      });

      expect(mockSetActiveWorkspaceData).toHaveBeenCalled();
      expect(WorkspaceService.moveResource).toHaveBeenCalledWith(
        "ws1",
        "res1",
        expect.objectContaining({ sectionId: "sec1" }),
        expect.objectContaining({ sectionId: "sec1" }),
      );
    });
  });
  describe("Tab Grouping Drop", () => {
    it("should add tab to group when dropped on group container", async () => {
      const mockTabGroup = {
        id: "tg1",
        chromeGroupId: 123,
        title: "G1",
        color: "blue",
        collapsed: false,
      };
      const workspaceWithGroups = {
        ...mockWorkspace,
        tabGroups: [mockTabGroup],
      };

      const { result } = renderHook(() =>
        useDragAndDrop({
          activeWorkspace: workspaceWithGroups as any,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
          workspaces: mockWorkspaces,
          spaceGroups: mockSpaceGroups,
          reorderWorkspaces: mockReorderWorkspaces,
          loadWorkspaces: mockLoadWorkspaces,
          reorderSpaceGroups: mockReorderSpaceGroups,
          reorderSections: mockReorderSections,
        }),
      );

      await act(async () => {
        await result.current.handleDragEnd({
          active: {
            id: "tab-1",
            data: { current: { type: "tab", tab: { id: 1 } } },
          },
          over: {
            id: "tg1",
            data: { current: { type: "group", groupId: "tg1" } },
          },
        } as any);
      });

      expect(TabSyncService.addTabToGroup).toHaveBeenCalledWith(1, 123);
    });

    it("should ungroup tab when dropped on active-tabs-root", async () => {
      const { result } = renderHook(() =>
        useDragAndDrop({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
          workspaces: mockWorkspaces,
          spaceGroups: mockSpaceGroups,
          reorderWorkspaces: mockReorderWorkspaces,
          loadWorkspaces: mockLoadWorkspaces,
          reorderSpaceGroups: mockReorderSpaceGroups,
          reorderSections: mockReorderSections,
        }),
      );

      await act(async () => {
        await result.current.handleDragEnd({
          active: {
            id: "tab-1",
            data: { current: { type: "tab", tab: { id: 1 } } },
          },
          over: { id: "active-tabs-root" },
        } as any);
      });

      expect(TabSyncService.removeTabFromGroup).toHaveBeenCalledWith(1);
    });
  });
});
