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
 * Custom hook for Menu State management in the Dashboard
 *
 * Consolidates all menu dropdown and collapse state into one place.
 */

import { useState } from "react";

export interface UseMenuStateReturn {
  // Section collapse state
  collapsedSections: Record<string, boolean>;
  toggleSectionCollapse: (sectionId: string) => void;
  // Section menu state
  openSectionMenuId: string | null;
  setOpenSectionMenuId: (id: string | null) => void;
  // Spaces dropdown menu state
  spacesMenuOpen: boolean;
  setSpacesMenuOpen: (open: boolean) => void;
  // Space group menu state
  spaceGroupMenuId: string | null;
  setSpaceGroupMenuId: (id: string | null) => void;
  colorPickerGroupId: string | null;
  setColorPickerGroupId: (id: string | null) => void;
  // Workspace menu state
  workspaceMenuId: string | null;
  setWorkspaceMenuId: (id: string | null) => void;
  workspaceSectionPickerId: string | null;
  setWorkspaceSectionPickerId: (id: string | null) => void;
  workspaceColorPickerId: string | null;
  setWorkspaceColorPickerId: (id: string | null) => void;
  // Workspace inline editing
  isEditingWorkspaceName: boolean;
  setIsEditingWorkspaceName: (editing: boolean) => void;
  editingWorkspaceName: string;
  setEditingWorkspaceName: (name: string) => void;
  editingSectionId: string | null;
  setEditingSectionId: (id: string | null) => void;
  editingSectionName: string;
  setEditingSectionName: (name: string) => void;
  // Confirm modal state
  confirmModal: {
    open: boolean;
    title: string;
    message: string;
    onConfirm: () => void;
  };
  showConfirm: (title: string, message: string, onConfirm: () => void) => void;
  closeConfirm: () => void;
  closeAllMenus: () => void;
}

export const useMenuState = (): UseMenuStateReturn => {
  // Section collapse state
  const [collapsedSections, setCollapsedSections] = useState<
    Record<string, boolean>
  >({});

  const toggleSectionCollapse = (sectionId: string) => {
    setCollapsedSections((prev) => ({
      ...prev,
      [sectionId]: !prev[sectionId],
    }));
  };

  // Section menu state
  const [openSectionMenuId, setOpenSectionMenuId] = useState<string | null>(
    null,
  );

  // Spaces dropdown menu state
  const [spacesMenuOpen, setSpacesMenuOpen] = useState(false);

  // Space group menu state
  const [spaceGroupMenuId, setSpaceGroupMenuId] = useState<string | null>(null);
  const [colorPickerGroupId, setColorPickerGroupId] = useState<string | null>(
    null,
  );

  // Workspace menu state
  const [workspaceMenuId, setWorkspaceMenuId] = useState<string | null>(null);
  const [workspaceSectionPickerId, setWorkspaceSectionPickerId] = useState<
    string | null
  >(null);
  const [workspaceColorPickerId, setWorkspaceColorPickerId] = useState<
    string | null
  >(null);

  // Workspace inline editing
  const [isEditingWorkspaceName, setIsEditingWorkspaceName] = useState(false);
  const [editingWorkspaceName, setEditingWorkspaceName] = useState("");
  const [editingSectionId, setEditingSectionId] = useState<string | null>(null);
  const [editingSectionName, setEditingSectionName] = useState("");

  // Confirm modal state
  const [confirmModal, setConfirmModal] = useState<{
    open: boolean;
    title: string;
    message: string;
    onConfirm: () => void;
  }>({ open: false, title: "", message: "", onConfirm: () => {} });

  const showConfirm = (title: string, message: string, onConfirm: () => void) =>
    setConfirmModal({ open: true, title, message, onConfirm });

  const closeConfirm = () =>
    setConfirmModal((prev) => ({ ...prev, open: false }));

  const closeAllMenus = () => {
    setSpacesMenuOpen(false);
    setSpaceGroupMenuId(null);
    setColorPickerGroupId(null);
    setWorkspaceMenuId(null);
    setWorkspaceSectionPickerId(null);
    setWorkspaceColorPickerId(null);
    setOpenSectionMenuId(null);
    // We don't close collapsed sections or clear new item inputs
  };

  return {
    // Section collapse
    collapsedSections,
    toggleSectionCollapse,
    // Section menu
    openSectionMenuId,
    setOpenSectionMenuId,
    // Spaces dropdown
    spacesMenuOpen,
    setSpacesMenuOpen,
    // Space group menu
    spaceGroupMenuId,
    setSpaceGroupMenuId,
    colorPickerGroupId,
    setColorPickerGroupId,
    // Workspace menu
    workspaceMenuId,
    setWorkspaceMenuId,
    workspaceSectionPickerId,
    setWorkspaceSectionPickerId,
    workspaceColorPickerId,
    setWorkspaceColorPickerId,
    // Workspace inline editing
    isEditingWorkspaceName,
    setIsEditingWorkspaceName,
    editingWorkspaceName,
    setEditingWorkspaceName,
    editingSectionId,
    setEditingSectionId,
    editingSectionName,
    setEditingSectionName,
    // Confirm modal
    confirmModal,
    showConfirm,
    closeConfirm,
    closeAllMenus,
  };
};
