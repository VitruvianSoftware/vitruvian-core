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

import React, { useRef } from "react";
import {
  SortableContext,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { Workspace, Tab } from "../types";
import { Icon } from "../components/icons";
import { SortableResourceItem } from "./SortableResourceItem";
import { DroppableContainer } from "./DroppableContainer";
import { WorkspaceService } from "../services/workspace";
import { TabService } from "../services/tabs";
import { MenuOverlay } from "./MenuOverlay";
import { EmptyState } from "../components/EmptyState";
import { EmptyResourcesIllustration } from "../components/illustrations/EmptyResources";
import { Button } from "@vitruviansoftware/design-system";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { FEATURE_FLAGS } from "../constants/features";

export interface ResourceSectionProps {
  section: Workspace["sections"][0];
  activeWorkspace: Workspace;
  collapsedSections: Record<string, boolean>;
  toggleSectionCollapse: (id: string) => void;
  openSectionMenuId: string | null;
  setOpenSectionMenuId: (id: string | null) => void;
  onToggleSectionMenu: (id: string | null) => void;
  editingSectionId: string | null;
  setEditingSectionId: (id: string | null) => void;
  editingSectionName: string;
  setEditingSectionName: (name: string) => void;
  setWorkspaceSectionPickerId: (id: string | null) => void;
  setTargetSectionId: (id: string) => void;
  setShowAddResource: (show: boolean) => void;
  setActiveWorkspaceData: (ws: Workspace) => void;
  handleOpenResource: (url: string) => Promise<void>;
  handleEditResource: (
    resourceId: string,
    currentTitle: string,
    currentUrl: string,
    sectionId?: string,
  ) => void;
  showConfirm: (title: string, message: string, onConfirm: () => void) => void;
  closeConfirm: () => void;
  loadWorkspaces?: () => void;
}

export const ResourceSection: React.FC<ResourceSectionProps> = ({
  section,
  activeWorkspace,
  collapsedSections,
  toggleSectionCollapse,
  openSectionMenuId,
  setOpenSectionMenuId,
  onToggleSectionMenu,
  editingSectionId,
  setEditingSectionId,
  editingSectionName,
  setEditingSectionName,
  setWorkspaceSectionPickerId,
  setTargetSectionId,
  setShowAddResource,
  setActiveWorkspaceData,
  handleOpenResource,
  handleEditResource,
  showConfirm,
  closeConfirm,
  loadWorkspaces,
}) => {
  const menuRef = useRef<HTMLDivElement>(null);
  const useDesignSystem = useFeatureFlag(
    FEATURE_FLAGS.USE_DESIGN_SYSTEM,
    false,
  );

  return (
    <DroppableContainer
      key={section.id}
      id={section.id}
      containerType="section"
      className={`section-container card-section ${collapsedSections[section.id] ? "collapsed" : ""}`}
      data-testid="resource-section"
    >
      <div
        className="section-content"
        style={{ width: "100%", overflow: "visible" }}
      >
        <div
          className="section-header collapsible-header"
          style={{
            cursor: "pointer",
            userSelect: "none",
            display: "flex",
            alignItems: "center",
          }}
          onClick={() => toggleSectionCollapse(section.id)}
        >
          <div
            className={`collapse-icon ${collapsedSections[section.id] ? "collapsed" : ""}`}
            style={{ display: "inline-flex", alignItems: "center" }}
          >
            <Icon
              name={
                collapsedSections[section.id] ? "chevron_right" : "expand_more"
              }
              size="sm"
              style={{
                marginRight: "8px",
                color: useDesignSystem
                  ? "var(--color-text-secondary)"
                  : "var(--color-text-muted)",
              }}
            />
          </div>
          {editingSectionId === section.id ? (
            <input
              type="text"
              className="section-title-input input input-sm"
              style={
                useDesignSystem
                  ? {
                      flex: 1,
                      fontFamily: "var(--font-mono, monospace)",
                      fontSize: "13px",
                      fontWeight: 600,
                      padding: "4px 8px",
                      border: "1px solid var(--color-border)",
                      backgroundColor: "var(--color-bg-card)",
                      color: "var(--color-text-primary)",
                    }
                  : { flex: 1 }
              }
              value={editingSectionName}
              autoFocus
              onClick={(e) => e.stopPropagation()}
              onChange={(e) => setEditingSectionName(e.target.value)}
              onBlur={async () => {
                if (editingSectionName.trim()) {
                  const updatedSections = activeWorkspace.sections?.map((s) => {
                    if (s.id === section.id) {
                      return { ...s, title: editingSectionName.trim() };
                    }
                    return s;
                  });
                  setActiveWorkspaceData({
                    ...activeWorkspace,
                    sections: updatedSections,
                  });
                  await WorkspaceService.renameSection(
                    activeWorkspace.id,
                    section.id,
                    editingSectionName.trim(),
                  );
                }
                setEditingSectionId(null);
              }}
              onKeyDown={async (e) => {
                if (e.key === "Enter") {
                  e.currentTarget.blur();
                }
              }}
            />
          ) : (
            <span
              className="section-title"
              onClick={(e) => {
                e.stopPropagation();
                setEditingSectionName(section.title);
                setEditingSectionId(section.id);
              }}
              style={{
                cursor: "pointer",
                fontFamily: useDesignSystem
                  ? "var(--font-mono, monospace)"
                  : undefined,
                fontSize: useDesignSystem ? "13px" : undefined,
                fontWeight: useDesignSystem ? 600 : undefined,
                color: useDesignSystem
                  ? "var(--color-text-primary)"
                  : undefined,
              }}
              title="Click to rename"
            >
              {section.title}
            </span>
          )}
          <div
            className="icon-actions"
            style={{ marginLeft: "auto" }}
            onClick={(e) => e.stopPropagation()}
          >
            {/* OPEN ALL Button */}
            {section.resources.length > 0 &&
              (useDesignSystem ? (
                <Button
                  variant="ghost"
                  size="xs"
                  title="Open all resources"
                  onClick={async () => {
                    const tabsToOpen: Tab[] = section.resources.map((res) => ({
                      id: 0,
                      url: res.url,
                      title: res.title,
                      active: false,
                      pinned: false,
                      index: 0,
                    }));
                    await TabService.openTabs(tabsToOpen);
                    if (activeWorkspace) {
                      await WorkspaceService.saveCurrentTabsToWorkspace(
                        activeWorkspace.id,
                      );
                      if (loadWorkspaces) loadWorkspaces();
                    }
                  }}
                >
                  OPEN ALL
                </Button>
              ) : (
                <button
                  className="btn btn-xxs btn-shaded"
                  title="Open all resources"
                  onClick={async () => {
                    const tabsToOpen: Tab[] = section.resources.map((res) => ({
                      id: 0,
                      url: res.url,
                      title: res.title,
                      active: false,
                      pinned: false,
                      index: 0,
                    }));
                    await TabService.openTabs(tabsToOpen);
                    if (activeWorkspace) {
                      await WorkspaceService.saveCurrentTabsToWorkspace(
                        activeWorkspace.id,
                      );
                      if (loadWorkspaces) loadWorkspaces();
                    }
                  }}
                >
                  OPEN ALL
                </button>
              ))}
            {/* Add Resource */}
            <button
              className="btn-icon"
              title="Add resource"
              onClick={() => {
                setWorkspaceSectionPickerId(null);
                if (openSectionMenuId === section.id) {
                  setOpenSectionMenuId(null);
                } else {
                  setOpenSectionMenuId(section.id);
                }
              }}
              style={
                useDesignSystem
                  ? { color: "var(--color-text-secondary)" }
                  : undefined
              }
            >
              <Icon name="add" size="sm" />
            </button>
            <span
              style={{
                fontSize: "11px",
                fontFamily: useDesignSystem
                  ? "var(--font-mono, monospace)"
                  : undefined,
                color: useDesignSystem
                  ? "var(--color-text-secondary)"
                  : "var(--color-text-muted)",
              }}
            >
              {section.resources.length}
            </span>
            {/* More Menu */}
            <div style={{ position: "relative" }} ref={menuRef}>
              {openSectionMenuId === section.id && (
                <MenuOverlay onClose={() => onToggleSectionMenu(null)} />
              )}
              <button
                className="btn-icon"
                title="Section Options"
                onClick={(e) => {
                  e.stopPropagation();
                  onToggleSectionMenu(
                    openSectionMenuId === section.id ? null : section.id,
                  );
                }}
                style={{
                  position: "relative",
                  zIndex: 20,
                  color: useDesignSystem
                    ? "var(--color-text-secondary)"
                    : "#9AA0A6",
                  padding: "2px",
                }}
              >
                <Icon name="more_vert" size="sm" />
              </button>
              {openSectionMenuId === section.id && (
                <div
                  className="dropdown-menu glass-menu"
                  style={{
                    right: 0,
                    top: "100%",
                    zIndex: 20,
                    position: "absolute",
                    borderRadius: useDesignSystem ? "0" : undefined,
                    border: useDesignSystem
                      ? "1px solid var(--glass-border)"
                      : undefined,
                    fontFamily: useDesignSystem
                      ? "var(--font-mono, monospace)"
                      : undefined,
                  }}
                >
                  <div
                    className="dropdown-item"
                    onClick={() => {
                      setTargetSectionId(section.id);
                      setShowAddResource(true);
                      setOpenSectionMenuId(null);
                    }}
                  >
                    <Icon name="add" size="sm" />
                    Add resource
                  </div>
                  <div className="dropdown-divider" />
                  <div
                    className="dropdown-item"
                    onClick={() => {
                      setOpenSectionMenuId(null);
                      showConfirm(
                        "Delete Section",
                        `Delete section "${section.title}" and its resources?`,
                        async () => {
                          const updatedSections =
                            activeWorkspace.sections?.filter(
                              (s) => s.id !== section.id,
                            );
                          setActiveWorkspaceData({
                            ...activeWorkspace,
                            sections: updatedSections,
                          });

                          await WorkspaceService.deleteSection(
                            activeWorkspace.id,
                            section.id,
                          );
                          closeConfirm();
                        },
                      );
                    }}
                    style={{
                      color: "var(--color-accent-danger)",
                    }}
                  >
                    <Icon name="delete" size="sm" />
                    Delete section
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Collapsible Content */}
        {!collapsedSections[section.id] && (
          <SortableContext
            id={section.id}
            items={section.resources.map((r) => r.id)}
            strategy={verticalListSortingStrategy}
          >
            <DroppableContainer
              id={section.id}
              className="resource-list"
              data-testid="resource-section-list"
            >
              {section.resources.map((res) => (
                <SortableResourceItem
                  key={res.id}
                  resource={res}
                  onActivate={() => handleOpenResource(res.url)}
                  onEdit={() =>
                    handleEditResource(res.id, res.title, res.url, section.id)
                  }
                  onRemove={async (e) => {
                    e.stopPropagation();
                    const updatedSections = activeWorkspace.sections?.map(
                      (s) => {
                        if (s.id === section.id) {
                          return {
                            ...s,
                            resources: s.resources.filter(
                              (r) => r.id !== res.id,
                            ),
                          };
                        }
                        return s;
                      },
                    );
                    setActiveWorkspaceData({
                      ...activeWorkspace,
                      sections: updatedSections,
                    });

                    await WorkspaceService.removeResourceFromSection(
                      activeWorkspace.id,
                      section.id,
                      res.id,
                    );
                  }}
                />
              ))}
              {section.resources.length === 0 && (
                <EmptyState
                  illustration={<EmptyResourcesIllustration />}
                  title="No resources yet"
                  description="Save links, docs, and files here to keep your project organized."
                  action={
                    useDesignSystem ? (
                      <Button
                        variant="solid"
                        size="sm"
                        onClick={() => {
                          setTargetSectionId(section.id);
                          setShowAddResource(true);
                          setOpenSectionMenuId(null);
                        }}
                      >
                        <Icon
                          name="add"
                          size="sm"
                          style={{ marginRight: "6px" }}
                        />
                        Add Resource
                      </Button>
                    ) : (
                      <button
                        className="btn btn-primary"
                        onClick={() => {
                          setTargetSectionId(section.id);
                          setShowAddResource(true);
                          setOpenSectionMenuId(null);
                        }}
                      >
                        <Icon
                          name="add"
                          size="sm"
                          style={{ marginRight: "6px" }}
                        />
                        Add Resource
                      </button>
                    )
                  }
                />
              )}
            </DroppableContainer>
          </SortableContext>
        )}
      </div>
    </DroppableContainer>
  );
};
