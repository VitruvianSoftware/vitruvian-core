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
 * ResourceSection Component
 *
 * Renders a single resource section with its header, actions, and list of resources.
 * Handles drag and drop context for resources within the section.
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

export interface ResourceSectionProps {
  section: Workspace["sections"][0];
  activeWorkspace: Workspace;
  collapsedSections: Record<string, boolean>;
  toggleSectionCollapse: (id: string) => void;
  openSectionMenuId: string | null;
  setOpenSectionMenuId: (id: string | null) => void;
  // Add onToggleSectionMenu prop if it's missing from interface but passed from parent, or map it.
  // Wait, the parent uses setOpenSectionMenuId.
  // In Dashboard.tsx:
  // onToggleSectionMenu={(id) => setOpenSectionMenuId(id)}
  // Check typical usage.
  // The error said `onToggleSectionMenu` is missing.
  // I need to add it to props and destructuring.
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
  setOpenSectionMenuId, // Still enabling this just in case, but favouring onToggleSectionMenu
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

  return (
    <DroppableContainer
      key={section.id}
      id={section.id}
      className={`section-container ${collapsedSections[section.id] ? "collapsed" : ""}`}
    >
      <div style={{ marginBottom: "16px" }}>
        <div
          className="collapsible-header"
          onClick={() => toggleSectionCollapse(section.id)}
        >
          <div
            className={`collapse-icon ${collapsedSections[section.id] ? "collapsed" : ""}`}
          >
            <Icon name="expand_more" size="sm" />
          </div>
          {editingSectionId === section.id ? (
            <input
              autoFocus
              className="section-title-input"
              value={editingSectionName}
              onChange={(e) => setEditingSectionName(e.target.value)}
              onClick={(e) => e.stopPropagation()}
              onBlur={async () => {
                if (editingSectionName.trim()) {
                  // Optimistic update
                  const updatedSections = activeWorkspace.sections?.map((s) =>
                    s.id === section.id
                      ? { ...s, title: editingSectionName }
                      : s,
                  );
                  setActiveWorkspaceData({
                    ...activeWorkspace,
                    sections: updatedSections,
                  });

                  await WorkspaceService.renameSection(
                    activeWorkspace.id,
                    section.id,
                    editingSectionName,
                  );
                  // loadWorkspaces();
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
              style={{ cursor: "pointer" }}
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
            {section.resources.length > 0 && (
              <button
                className="btn btn-xxs btn-shaded"
                title="Open all resources"
                onClick={async () => {
                  // Create tab objects from resources
                  const tabsToOpen: Tab[] = section.resources.map((res) => ({
                    id: 0, // Placeholder
                    url: res.url,
                    title: res.title,
                    active: false,
                    pinned: false,
                    index: 0,
                  }));

                  // Open them
                  await TabService.openTabs(tabsToOpen);

                  // Force sync to capture the new tabs
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
            )}
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
            >
              <Icon name="add" size="sm" />
            </button>

            {/* More Menu */}
            <div style={{ position: "relative" }} ref={menuRef}>
              {openSectionMenuId === section.id && (
                <MenuOverlay onClose={() => onToggleSectionMenu(null)} />
              )}
              <button
                className="btn-icon"
                onClick={(e) => {
                  e.stopPropagation();
                  onToggleSectionMenu(
                    openSectionMenuId === section.id ? null : section.id,
                  );
                }}
                title="More options"
                style={{
                  position: "relative",
                  zIndex: 20,
                  color: "#9AA0A6",
                  padding: "2px",
                }}
              >
                <Icon name="more_vert" size="sm" />
              </button>
              {openSectionMenuId === section.id && (
                <div
                  className="dropdown-menu"
                  style={{ right: 0, top: "100%", zIndex: 20 }}
                >
                  <div
                    className="dropdown-item"
                    onClick={() => {
                      // eslint-disable-next-line no-console
                      console.log("[DEBUG] Add resource dropdown item clicked");
                      setTargetSectionId(section.id);
                      // eslint-disable-next-line no-console
                      console.log("[DEBUG] setTargetSectionId done");
                      setShowAddResource(true);
                      // eslint-disable-next-line no-console
                      console.log("[DEBUG] setShowAddResource done");
                      setOpenSectionMenuId(null);
                      // eslint-disable-next-line no-console
                      console.log("[DEBUG] setOpenSectionMenuId done");
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
                          // Optimistic update
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
                          // loadWorkspaces();
                          closeConfirm();
                        },
                      );
                    }}
                    style={{ color: "var(--color-accent-danger)" }}
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
                    // Optimistic update
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
                    // loadWorkspaces(); // Rely on storage listener
                  }}
                />
              ))}
              {section.resources.length === 0 && (
                <EmptyState
                  illustration={<EmptyResourcesIllustration />}
                  title="No resources yet"
                  description="Save links, docs, and files here to keep your project organized."
                  action={
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
