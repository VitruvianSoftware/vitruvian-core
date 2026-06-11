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
 * Custom hook for drag-and-drop functionality in the Dashboard
 *
 * Handles:
 * - Resource drag between sections
 * - Tab drag to sections (creating resources)
 * - Workspace reordering in sidebar
 */

import { useState } from "react";
import {
  KeyboardSensor,
  PointerSensor,
  useSensor,
  useSensors,
  DragStartEvent,
  DragEndEvent,
} from "@dnd-kit/core";
import { arrayMove, sortableKeyboardCoordinates } from "@dnd-kit/sortable";
import type { Workspace, SpaceGroup } from "../../types";
import { TabService } from "../../services/tabs";
import { TabSyncService } from "../../services/tabSync";
import { WorkspaceService } from "../../services/workspace";

export interface UseDragAndDropProps {
  activeWorkspace: Workspace | null;
  setActiveWorkspaceData: (ws: Workspace) => void;
  workspaces: Workspace[];
  spaceGroups: SpaceGroup[];
  reorderWorkspaces: (workspaces: Workspace[]) => Promise<void>;
  reorderSpaceGroups: (groups: SpaceGroup[]) => Promise<void>;
  reorderSections: (
    workspaceId: string,
    sections: Workspace["sections"],
  ) => Promise<void>;
  loadWorkspaces: () => void;
}

export interface UseDragAndDropReturn {
  activeId: string | null;
  sensors: ReturnType<typeof useSensors>;
  sidebarSensors: ReturnType<typeof useSensors>;
  handleDragStart: (event: DragStartEvent) => void;
  handleDragEnd: (event: DragEndEvent) => Promise<void>;
  handleSidebarDragEnd: (event: DragEndEvent) => Promise<void>;
}

export const useDragAndDrop = ({
  activeWorkspace,
  setActiveWorkspaceData,
  workspaces,
  spaceGroups,
  reorderWorkspaces,
  reorderSpaceGroups,
  reorderSections,
  loadWorkspaces,
}: UseDragAndDropProps): UseDragAndDropReturn => {
  const [activeId, setActiveId] = useState<string | null>(null);

  const sensors = useSensors(
    useSensor(PointerSensor, {
      activationConstraint: {
        distance: 10, // Require 10px movement before drag starts
      },
    }),
    useSensor(KeyboardSensor, {
      coordinateGetter: sortableKeyboardCoordinates,
    }),
  );

  const sidebarSensors = useSensors(
    useSensor(PointerSensor, {
      activationConstraint: {
        distance: 5,
      },
    }),
    useSensor(KeyboardSensor, {
      coordinateGetter: sortableKeyboardCoordinates,
    }),
  );

  const findContainer = (id: string): string | undefined => {
    if (!activeWorkspace) return undefined;

    const foundSection = (activeWorkspace.sections || []).find((section) =>
      section.resources.some((r) => r.id === id),
    );
    if (foundSection) return foundSection.id;
    return undefined;
  };

  const handleDragStart = (event: DragStartEvent) => {
    setActiveId(event.active.id as string);
  };

  const handleSidebarDragEnd = async (event: DragEndEvent) => {
    const { active, over } = event;
    if (!over || active.id === over.id) return;

    // Check if reordering space groups
    if (
      active.data?.current?.type === "SpaceGroup" &&
      over.data?.current?.type === "SpaceGroup"
    ) {
      const oldIndex = spaceGroups.findIndex((g) => g.id === active.id);
      const newIndex = spaceGroups.findIndex((g) => g.id === over.id);

      if (oldIndex !== -1 && newIndex !== -1) {
        const newGroups = arrayMove(spaceGroups, oldIndex, newIndex).map(
          (g, index) => ({
            ...g,
            position: index,
            updatedAt: Date.now(), // Update timestamp to ensure persistence
          }),
        );
        reorderSpaceGroups(newGroups);
      }
      return;
    }

    const draggedId = active.id as string;
    const overId = over.id as string;

    const draggedWorkspace = workspaces.find((w) => w.id === draggedId);
    if (!draggedWorkspace) return;

    // Determine target group
    let targetGroupId: string | undefined = draggedWorkspace.groupId;

    const overGroup = spaceGroups.find((g) => g.id === overId);
    const overWorkspace = workspaces.find((w) => w.id === overId);
    const isUngroupedContainer = overId === "ungrouped-list";

    if (overGroup || (overId && spaceGroups.some((g) => g.id === overId))) {
      targetGroupId = overId;
    } else if (overWorkspace) {
      targetGroupId = overWorkspace.groupId;
    } else if (isUngroupedContainer) {
      targetGroupId = undefined;
    }

    // Capture original indices for direction detection
    const originalActiveIndex = workspaces.findIndex((w) => w.id === draggedId);
    const originalOverIndex = workspaces.findIndex((w) => w.id === overId);

    // Construct new array
    const currentWorkspaces = [...workspaces];
    currentWorkspaces.sort((a, b) => (a.position || 0) - (b.position || 0));

    const activeIndex = currentWorkspaces.findIndex((w) => w.id === draggedId);
    if (activeIndex === -1) return;

    currentWorkspaces.splice(activeIndex, 1);

    const updatedActive = {
      ...draggedWorkspace,
      groupId: targetGroupId,
    };

    let insertIndex = 0;
    if (overWorkspace) {
      const overIndex = currentWorkspaces.findIndex((w) => w.id === overId);
      const isDragDown =
        originalActiveIndex !== -1 &&
        originalOverIndex !== -1 &&
        originalActiveIndex < originalOverIndex;

      if (overIndex >= 0) {
        insertIndex = isDragDown ? overIndex + 1 : overIndex;
      } else {
        insertIndex = currentWorkspaces.length;
      }
    } else if (overGroup || overId === "ungrouped-list") {
      insertIndex = currentWorkspaces.length;
    }

    currentWorkspaces.splice(insertIndex, 0, updatedActive);

    // Reassign positions and update timestamps for CHANGED items
    const reordered = currentWorkspaces.map((w, index) => {
      const positionChanged = w.position !== index;
      const groupChanged =
        w.id === draggedId && w.groupId !== draggedWorkspace.groupId;

      if (positionChanged || groupChanged) {
        return {
          ...w,
          position: index,
          updatedAt: Date.now(),
        };
      }
      return w;
    });

    await reorderWorkspaces(reordered);
  };

  const handleDragEnd = async (event: DragEndEvent) => {
    const { active, over } = event;

    setActiveId(null);

    if (!over || !activeWorkspace) {
      return;
    }

    // Hande Section Reordering
    if (
      active.data?.current?.type === "Section" &&
      over.data?.current?.type === "Section"
    ) {
      const sections = activeWorkspace.sections || [];
      const oldIndex = sections.findIndex((s) => s.id === active.id);
      const newIndex = sections.findIndex((s) => s.id === over.id);

      if (oldIndex !== -1 && newIndex !== -1 && oldIndex !== newIndex) {
        const newSections = arrayMove(sections, oldIndex, newIndex);
        await reorderSections(activeWorkspace.id, newSections);
      }
      return;
    }

    // Check if dragging from tabs
    const isTabDrag = active.data?.current?.type === "tab";
    const isTabGroupDrag = active.data?.current?.type === "tab-group";

    // Handle tab group drag (moving entire group)
    if (isTabGroupDrag) {
      const tabIds = active.data?.current?.tabIds as number[] | undefined;

      if (over.data?.current?.type === "tab") {
        // Dropped on a tab - move group to that tab's position
        const overTab = over.data?.current?.tab;
        if (overTab?.id && tabIds?.length) {
          const targetTab = await TabService.getTab(overTab.id);
          if (targetTab && typeof targetTab.index === "number") {
            await TabSyncService.moveTabGroup(tabIds, targetTab.index);
          }
        }
      } else if (over.data?.current?.type === "tab-group") {
        // Dropped on another group - move to that group's first tab position
        const overTabIds = over.data?.current?.tabIds as number[] | undefined;
        if (overTabIds?.length && tabIds?.length) {
          const firstOverTab = await TabService.getTab(overTabIds[0]);
          if (firstOverTab && typeof firstOverTab.index === "number") {
            await TabSyncService.moveTabGroup(tabIds, firstOverTab.index);
          }
        }
      }
      return;
    }

    if (isTabDrag) {
      if (over.data?.current?.type === "tab") {
        const movingTabId = active.data?.current?.tab?.id;
        const overTabId = over.data?.current?.tab?.id;

        // Handle tab reordering - call Chrome API, let events update state
        if (movingTabId && overTabId) {
          const overTab = await TabService.getTab(overTabId);
          if (overTab && typeof overTab.index === "number") {
            await TabSyncService.moveTab(movingTabId, overTab.index);
          }
        }

        // Handle cross-container moves (grouping/ungrouping)
        const activeTab = active.data?.current?.tab;
        const overTab = over.data?.current?.tab;
        const activeGroupId = activeTab?.groupId; // Stable UUID
        const overGroupId = overTab?.groupId; // Stable UUID
        const targetChromeGroupId = overTab?.chromeGroupId;

        if (movingTabId && activeGroupId !== overGroupId) {
          if (overGroupId && targetChromeGroupId) {
            // Moving INTO a group - Chrome event will update workspace
            await TabSyncService.addTabToGroup(
              movingTabId,
              targetChromeGroupId,
            );
          } else if (activeGroupId && !overGroupId) {
            // Moving OUT of a group - Chrome event will update workspace
            await TabSyncService.removeTabFromGroup(movingTabId);
          }
        }
        return;
      }

      // Handle dropping onto a group header (add to that group)
      if (over.data?.current?.type === "tab-group") {
        const movingTabId = active.data?.current?.tab?.id;
        const overTabIds = over.data?.current?.tabIds as number[] | undefined;

        if (movingTabId && overTabIds?.length) {
          // Get the chrome group ID from one of the group's tabs
          const firstGroupTab = await TabService.getTab(overTabIds[0]);
          if (firstGroupTab?.chromeGroupId) {
            // Chrome event will update workspace
            await TabSyncService.addTabToGroup(
              movingTabId,
              firstGroupTab.chromeGroupId,
            );
          }
        }
        return;
      }

      // Handle dropping onto a group container (distinct from header)
      if (over.data?.current?.type === "group") {
        const movingTabId = active.data?.current?.tab?.id;
        const targetGroupId = over.data?.current?.groupId;

        if (movingTabId && targetGroupId && activeWorkspace?.tabGroups) {
          const targetGroup = activeWorkspace.tabGroups.find(
            (g) => g.id === targetGroupId,
          );
          if (targetGroup?.chromeGroupId) {
            await TabSyncService.addTabToGroup(
              movingTabId,
              targetGroup.chromeGroupId,
            );
          }
        }
        return;
      }

      // Handle dropping on Active Tabs panel background (ungroup)
      if (over.id === "active-tabs-root") {
        const movingTabId = active.data?.current?.tab?.id;
        if (movingTabId) {
          // Ungroup the tab (Chrome will place it at the end of the window or appropriate ungrouped spot)
          await TabSyncService.removeTabFromGroup(movingTabId);
        }
        return;
      }

      const tabData = active.data?.current?.tab;
      let overContainer: string | undefined;

      if (over.data?.current?.type === "section") {
        overContainer = over.data?.current?.sectionId || (over.id as string);
      }

      if (
        !overContainer &&
        activeWorkspace.sections?.some((s) => s.id === over.id)
      ) {
        overContainer = over.id as string;
      }

      if (!overContainer) {
        overContainer = findContainer(over.id as string);
      }

      if (overContainer && tabData) {
        const resourceData = {
          title: tabData.title,
          url: tabData.url,
          faviconUrl: tabData.favIconUrl,
        };

        try {
          const newResource = {
            id: `res_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
            title: resourceData.title,
            url: resourceData.url,
            faviconUrl: resourceData.faviconUrl,
            createdAt: Date.now(),
          };

          const updatedSections =
            activeWorkspace.sections?.map((s) => {
              if (s.id === overContainer) {
                return { ...s, resources: [...s.resources, newResource] };
              }
              return s;
            }) || [];

          setActiveWorkspaceData({
            ...activeWorkspace,
            sections: updatedSections,
          });

          await WorkspaceService.addResourceToSection(
            activeWorkspace.id,
            overContainer,
            resourceData,
          );
        } catch (error) {
          console.error("[handleDragEnd] addResourceToSection FAILED:", error);
        }
      } else if (over.data?.current?.type === "workspace" && tabData) {
        const targetWorkspaceId = over.data?.current.workspaceId;
        const targetWorkspace = workspaces.find(
          (w) => w.id === targetWorkspaceId,
        );

        const targetSection =
          targetWorkspace?.sections?.find((s) => s.title === "Resources") ||
          targetWorkspace?.sections?.[0];

        if (targetWorkspace && targetSection) {
          const resourceData = {
            title: tabData.title,
            url: tabData.url,
            faviconUrl: tabData.favIconUrl,
          };

          try {
            await WorkspaceService.addResourceToSection(
              targetWorkspace.id,
              targetSection.id,
              resourceData,
            );

            loadWorkspaces();
          } catch (error) {
            console.error(
              "[handleDragEnd] Failed to add resource to sidebar workspace:",
              error,
            );
          }
        }
      }
      return;
    }

    const activeContainer = findContainer(active.id as string);
    const overContainer = activeWorkspace.sections?.some(
      (s) => s.id === over.id,
    )
      ? (over.id as string)
      : findContainer(over.id as string);

    if (!activeContainer || !overContainer) return;

    const getItems = (containerId: string) => {
      return (
        activeWorkspace.sections?.find((s) => s.id === containerId)
          ?.resources || []
      );
    };

    const overItems = getItems(overContainer);

    const overIndex =
      over.id === overContainer
        ? overItems.length + 1
        : overItems.findIndex((r) => r.id === over.id);

    // Optimistic Update
    if (activeWorkspace.sections) {
      const activeSection = activeWorkspace.sections.find(
        (s) => s.id === activeContainer,
      );
      const overSection = activeWorkspace.sections.find(
        (s) => s.id === overContainer,
      );
      const resource = activeSection?.resources.find((r) => r.id === active.id);

      if (activeSection && overSection && resource) {
        const newSections = activeWorkspace.sections.map((section) => {
          if (
            activeContainer === overContainer &&
            section.id === activeContainer
          ) {
            const newResources = [...section.resources];
            const sourceIndex = newResources.findIndex(
              (r) => r.id === active.id,
            );

            if (sourceIndex !== -1) {
              newResources.splice(sourceIndex, 1);
            }

            newResources.splice(overIndex, 0, resource);
            return { ...section, resources: newResources };
          }

          if (section.id === activeContainer) {
            return {
              ...section,
              resources: section.resources.filter((r) => r.id !== active.id),
            };
          }
          if (section.id === overContainer) {
            const newResources = [...section.resources];
            newResources.splice(overIndex, 0, resource);
            return {
              ...section,
              resources: newResources,
            };
          }
          return section;
        });
        setActiveWorkspaceData({ ...activeWorkspace, sections: newSections });
      }
    }

    await WorkspaceService.moveResource(
      activeWorkspace.id,
      active.id as string,
      {
        type: "section",
        sectionId: activeContainer,
      },
      {
        type: "section",
        sectionId: overContainer,
        index: overIndex,
      },
    );
  };

  return {
    activeId,
    sensors,
    sidebarSensors,
    handleDragStart,
    handleDragEnd,
    handleSidebarDragEnd,
  };
};
