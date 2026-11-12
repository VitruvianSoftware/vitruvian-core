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
 * Tests for useMenuState hook
 */

import { renderHook, act } from "@testing-library/react";
import { useMenuState } from "./useMenuState";

describe("useMenuState", () => {
  it("should return default values", () => {
    const { result } = renderHook(() => useMenuState());

    expect(result.current.collapsedSections).toEqual({});
    expect(result.current.openSectionMenuId).toBeNull();
    expect(result.current.spacesMenuOpen).toBe(false);
    expect(result.current.spaceGroupMenuId).toBeNull();
    expect(result.current.colorPickerGroupId).toBeNull();
    expect(result.current.workspaceMenuId).toBeNull();
    expect(result.current.workspaceSectionPickerId).toBeNull();
    expect(result.current.workspaceColorPickerId).toBeNull();
    expect(result.current.isEditingWorkspaceName).toBe(false);
    expect(result.current.editingWorkspaceName).toBe("");
    expect(result.current.editingSectionId).toBeNull();
    expect(result.current.editingSectionName).toBe("");

    expect(result.current.confirmModal).toEqual({
      open: false,
      title: "",
      message: "",
      onConfirm: expect.any(Function),
    });
  });

  describe("Section Collapse", () => {
    it("should toggle section collapse", () => {
      const { result } = renderHook(() => useMenuState());

      act(() => {
        result.current.toggleSectionCollapse("section-1");
      });
      expect(result.current.collapsedSections["section-1"]).toBe(true);

      act(() => {
        result.current.toggleSectionCollapse("section-1");
      });
      expect(result.current.collapsedSections["section-1"]).toBe(false);
    });
  });

  describe("Confirm Modal Helpers", () => {
    it("should show confirm modal with correct details", () => {
      const { result } = renderHook(() => useMenuState());
      const onConfirm = jest.fn();

      act(() => {
        result.current.showConfirm("Delete?", "Are you sure?", onConfirm);
      });

      expect(result.current.confirmModal.open).toBe(true);
      expect(result.current.confirmModal.title).toBe("Delete?");
      expect(result.current.confirmModal.message).toBe("Are you sure?");
      expect(result.current.confirmModal.onConfirm).toBe(onConfirm);
    });

    it("should close confirm modal", () => {
      const { result } = renderHook(() => useMenuState());
      const onConfirm = jest.fn();

      act(() => {
        result.current.showConfirm("Delete?", "Are you sure?", onConfirm);
      });

      act(() => {
        result.current.closeConfirm();
      });

      expect(result.current.confirmModal.open).toBe(false);
    });
  });

  describe("State Setters", () => {
    it("should set open section menu id", () => {
      const { result } = renderHook(() => useMenuState());
      act(() => {
        result.current.setOpenSectionMenuId("section-1");
      });
      expect(result.current.openSectionMenuId).toBe("section-1");
    });

    it("should set spaces menu open", () => {
      const { result } = renderHook(() => useMenuState());
      act(() => {
        result.current.setSpacesMenuOpen(true);
      });
      expect(result.current.spacesMenuOpen).toBe(true);
    });

    it("should set space group menu id", () => {
      const { result } = renderHook(() => useMenuState());
      act(() => {
        result.current.setSpaceGroupMenuId("group-1");
      });
      expect(result.current.spaceGroupMenuId).toBe("group-1");
    });

    it("should set color picker group id", () => {
      const { result } = renderHook(() => useMenuState());
      act(() => {
        result.current.setColorPickerGroupId("color-group-1");
      });
      expect(result.current.colorPickerGroupId).toBe("color-group-1");
    });

    it("should set workspace menu id", () => {
      const { result } = renderHook(() => useMenuState());
      act(() => {
        result.current.setWorkspaceMenuId("workspace-1");
      });
      expect(result.current.workspaceMenuId).toBe("workspace-1");
    });

    it("should set workspace section picker id", () => {
      const { result } = renderHook(() => useMenuState());
      act(() => {
        result.current.setWorkspaceSectionPickerId("section-picker-1");
      });
      expect(result.current.workspaceSectionPickerId).toBe("section-picker-1");
    });

    it("should set workspace color picker id", () => {
      const { result } = renderHook(() => useMenuState());
      act(() => {
        result.current.setWorkspaceColorPickerId("color-picker-1");
      });
      expect(result.current.workspaceColorPickerId).toBe("color-picker-1");
    });

    it("should set editing workspace name", () => {
      const { result } = renderHook(() => useMenuState());
      act(() => {
        result.current.setIsEditingWorkspaceName(true);
        result.current.setEditingWorkspaceName("New Name");
      });
      expect(result.current.isEditingWorkspaceName).toBe(true);
      expect(result.current.editingWorkspaceName).toBe("New Name");
    });

    it("should set editing section id and name", () => {
      const { result } = renderHook(() => useMenuState());
      act(() => {
        result.current.setEditingSectionId("section-1");
        result.current.setEditingSectionName("Section Name");
      });
      expect(result.current.editingSectionId).toBe("section-1");
      expect(result.current.editingSectionName).toBe("Section Name");
    });
  });

  describe("closeAllMenus", () => {
    it("should close all menus when called", () => {
      const { result } = renderHook(() => useMenuState());

      // Open various menus
      act(() => {
        result.current.setSpacesMenuOpen(true);
        result.current.setSpaceGroupMenuId("group-1");
        result.current.setColorPickerGroupId("color-group-1");
        result.current.setWorkspaceMenuId("workspace-1");
        result.current.setWorkspaceSectionPickerId("section-picker-1");
        result.current.setWorkspaceColorPickerId("color-picker-1");
        result.current.setOpenSectionMenuId("section-1");
      });

      // Close all menus
      act(() => {
        result.current.closeAllMenus();
      });

      expect(result.current.spacesMenuOpen).toBe(false);
      expect(result.current.spaceGroupMenuId).toBeNull();
      expect(result.current.colorPickerGroupId).toBeNull();
      expect(result.current.workspaceMenuId).toBeNull();
      expect(result.current.workspaceSectionPickerId).toBeNull();
      expect(result.current.workspaceColorPickerId).toBeNull();
      expect(result.current.openSectionMenuId).toBeNull();
    });

    it("should not affect collapsed sections when closing all menus", () => {
      const { result } = renderHook(() => useMenuState());

      // Collapse a section and open a menu
      act(() => {
        result.current.toggleSectionCollapse("section-1");
        result.current.setSpacesMenuOpen(true);
      });

      expect(result.current.collapsedSections["section-1"]).toBe(true);

      // Close all menus
      act(() => {
        result.current.closeAllMenus();
      });

      // Section should still be collapsed
      expect(result.current.collapsedSections["section-1"]).toBe(true);
    });
  });
});
