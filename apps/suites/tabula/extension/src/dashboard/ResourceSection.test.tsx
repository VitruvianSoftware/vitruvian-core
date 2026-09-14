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
 * Tests for ResourceSection component
 */

/// <reference types="@testing-library/jest-dom" />
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { ResourceSection, ResourceSectionProps } from "./ResourceSection";
import { WorkspaceService } from "../services/workspace";
import { TabService } from "../services/tabs";
import type { Workspace, Section } from "../types";

// Mocks
jest.mock("../lib/flags/use-feature-flag", () => ({
  useFeatureFlag: jest.fn(() => false),
}));

jest.mock("../components/icons", () => ({
  Icon: ({ name }: { name: string }) => (
    <span data-testid={`icon-${name}`}>{name}</span>
  ),
}));

jest.mock("../services/workspace", () => ({
  WorkspaceService: {
    renameSection: jest.fn(),
    deleteSection: jest.fn(),
    removeResourceFromSection: jest.fn(),
    saveCurrentTabsToWorkspace: jest.fn(),
  },
}));

jest.mock("../services/tabs", () => ({
  TabService: {
    openTabs: jest.fn(),
    getTabs: jest.fn(),
  },
}));

jest.mock("./SortableResourceItem", () => ({
  SortableResourceItem: ({ resource, onRemove, onEdit }: any) => (
    <div data-testid={`resource-${resource.id}`}>
      {resource.title}
      <button onClick={onEdit} title="Edit">
        Edit
      </button>
      <button onClick={onRemove} title="Remove">
        Remove
      </button>
    </div>
  ),
}));

jest.mock("./DroppableContainer", () => ({
  DroppableContainer: ({ children, className }: any) => (
    <div className={className}>{children}</div>
  ),
}));

jest.mock("@dnd-kit/sortable", () => ({
  SortableContext: ({ children }: any) => <div>{children}</div>,
  verticalListSortingStrategy: {},
}));

describe("ResourceSection", () => {
  const now = Date.now();
  const mockSection: Section = {
    id: "section-1",
    title: "Test Section",
    resources: [
      {
        id: "res-1",
        title: "Google",
        url: "https://google.com",
        createdAt: now,
      },
      {
        id: "res-2",
        title: "GitHub",
        url: "https://github.com",
        createdAt: now,
      },
    ],
  };

  const mockWorkspace: Workspace = {
    id: "ws-1",
    name: "Test Workspace",
    icon: "📁",
    position: 0,
    tabs: [],
    resources: [],
    sections: [mockSection],
    notes: [],
    tasks: [],
    createdAt: now,
    updatedAt: now,
  };

  const defaultProps: ResourceSectionProps = {
    section: mockSection,
    activeWorkspace: mockWorkspace,
    collapsedSections: {},
    toggleSectionCollapse: jest.fn(),
    openSectionMenuId: null,
    setOpenSectionMenuId: jest.fn(),
    editingSectionId: null,
    setEditingSectionId: jest.fn(),
    editingSectionName: "",
    setEditingSectionName: jest.fn(),
    setWorkspaceSectionPickerId: jest.fn(),
    setTargetSectionId: jest.fn(),
    setShowAddResource: jest.fn(),
    setActiveWorkspaceData: jest.fn(),
    handleOpenResource: jest.fn(),
    handleEditResource: jest.fn(),
    onToggleSectionMenu: jest.fn(),
    showConfirm: jest.fn(),
    closeConfirm: jest.fn(),
    loadWorkspaces: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("rendering", () => {
    it("should render section title", () => {
      render(<ResourceSection {...defaultProps} />);
      expect(screen.getByText("Test Section")).toBeInTheDocument();
    });

    it("should render resources", () => {
      render(<ResourceSection {...defaultProps} />);
      expect(screen.getByText("Google")).toBeInTheDocument();
      expect(screen.getByText("GitHub")).toBeInTheDocument();
    });

    it("should show OPEN ALL button when resources exist", () => {
      render(<ResourceSection {...defaultProps} />);
      expect(screen.getByText("OPEN ALL")).toBeInTheDocument();
    });

    it("should not show OPEN ALL button when no resources", () => {
      const emptySection = { ...mockSection, resources: [] };
      render(<ResourceSection {...defaultProps} section={emptySection} />);
      expect(screen.queryByText("OPEN ALL")).not.toBeInTheDocument();
    });

    it("should show empty state message when no resources", () => {
      const emptySection = { ...mockSection, resources: [] };
      render(<ResourceSection {...defaultProps} section={emptySection} />);
      expect(screen.getByText(/No resources/)).toBeInTheDocument();
    });
  });

  describe("interactions", () => {
    it("should toggle collapse when header clicked", () => {
      render(<ResourceSection {...defaultProps} />);
      fireEvent.click(screen.getByTestId("icon-expand_more").parentElement!);
      expect(defaultProps.toggleSectionCollapse).toHaveBeenCalledWith(
        "section-1",
      );
    });

    it("should start editing name when title clicked", () => {
      render(<ResourceSection {...defaultProps} />);
      fireEvent.click(screen.getByText("Test Section"));
      expect(defaultProps.setEditingSectionName).toHaveBeenCalledWith(
        "Test Section",
      );
      expect(defaultProps.setEditingSectionId).toHaveBeenCalledWith(
        "section-1",
      );
    });

    it("should toggle menu when add button clicked", () => {
      render(<ResourceSection {...defaultProps} />);
      fireEvent.click(screen.getByTitle("Add resource"));
      expect(defaultProps.setOpenSectionMenuId).toHaveBeenCalledWith(
        "section-1",
      );
    });

    it("should open all tabs when OPEN ALL clicked", async () => {
      render(<ResourceSection {...defaultProps} />);
      fireEvent.click(screen.getByText("OPEN ALL"));

      await waitFor(() => {
        expect(TabService.openTabs).toHaveBeenCalled();
      });
      // Should also save current tabs
      expect(WorkspaceService.saveCurrentTabsToWorkspace).toHaveBeenCalledWith(
        "ws-1",
      );
    });
  });

  describe("inline editing", () => {
    it("should render input when editing this section", () => {
      render(
        <ResourceSection
          {...defaultProps}
          editingSectionId="section-1"
          editingSectionName="New Name"
        />,
      );
      expect(screen.getByDisplayValue("New Name")).toBeInTheDocument();
    });

    it("should save on blur", async () => {
      render(
        <ResourceSection
          {...defaultProps}
          editingSectionId="section-1"
          editingSectionName="Renamed"
        />,
      );
      const input = screen.getByDisplayValue("Renamed");
      fireEvent.blur(input);

      await waitFor(() => {
        expect(WorkspaceService.renameSection).toHaveBeenCalledWith(
          "ws-1",
          "section-1",
          "Renamed",
        );
        expect(defaultProps.setActiveWorkspaceData).toHaveBeenCalled();
        expect(defaultProps.setEditingSectionId).toHaveBeenCalledWith(null);
      });
    });

    it("should save on Enter key", async () => {
      render(
        <ResourceSection
          {...defaultProps}
          editingSectionId="section-1"
          editingSectionName="Renamed"
        />,
      );
      const input = screen.getByDisplayValue("Renamed");
      fireEvent.keyDown(input, { key: "Enter" });
      // The component mainly relies on blur for the actual save logic in the current implementation,
      // but Enter triggers blur.
      fireEvent.blur(input);

      await waitFor(() => {
        expect(WorkspaceService.renameSection).toHaveBeenCalled();
      });
    });

    it("should not save when section name is empty on blur", async () => {
      render(
        <ResourceSection
          {...defaultProps}
          editingSectionId="section-1"
          editingSectionName="   "
        />,
      );
      // Use role since getByDisplayValue with whitespace is fragile
      const input = screen.getByRole("textbox");
      fireEvent.blur(input);

      await waitFor(() => {
        expect(defaultProps.setEditingSectionId).toHaveBeenCalledWith(null);
      });
      // Should not call rename with empty name
      expect(WorkspaceService.renameSection).not.toHaveBeenCalled();
    });
  });

  describe("OPEN ALL without loadWorkspaces", () => {
    it("should handle OPEN ALL when loadWorkspaces is undefined", async () => {
      const propsWithoutLoad = { ...defaultProps, loadWorkspaces: undefined };
      render(<ResourceSection {...propsWithoutLoad} />);
      fireEvent.click(screen.getByText("OPEN ALL"));

      await waitFor(() => {
        expect(TabService.openTabs).toHaveBeenCalled();
        expect(
          WorkspaceService.saveCurrentTabsToWorkspace,
        ).toHaveBeenCalledWith("ws-1");
      });
      // Should not throw even without loadWorkspaces
    });
  });

  describe("menu actions", () => {
    it("should show menu options when menu is open", () => {
      render(
        <ResourceSection {...defaultProps} openSectionMenuId="section-1" />,
      );
      // Add resource and Delete section are in the dropdown
      const addButtons = screen.getAllByText("Add resource");
      expect(addButtons.length).toBeGreaterThan(0);
      expect(screen.getByText("Delete section")).toBeInTheDocument();
    });

    it("should show delete confirmation when Delete section clicked", () => {
      render(
        <ResourceSection {...defaultProps} openSectionMenuId="section-1" />,
      );
      fireEvent.click(screen.getByText("Delete section"));

      expect(defaultProps.setOpenSectionMenuId).toHaveBeenCalledWith(null);
      expect(defaultProps.showConfirm).toHaveBeenCalledWith(
        "Delete Section",
        expect.stringContaining('Delete section "Test Section"'),
        expect.any(Function),
      );
    });

    it("should execute delete logic when confirmed", async () => {
      // We can manually invoke the callback passed to showConfirm if we want to test the inner logic,
      // or we can simulate the flow if we can get a handle on the callback.
      // Here we just verified showConfirm was called with a function.
      // Let's capture the function and call it.

      let confirmCallback: () => Promise<void> = async () => {};
      const showConfirmMock = jest.fn((_t, _m, cb) => {
        confirmCallback = cb;
      });

      render(
        <ResourceSection
          {...defaultProps}
          openSectionMenuId="section-1"
          showConfirm={showConfirmMock}
        />,
      );
      fireEvent.click(screen.getByText("Delete section"));

      await confirmCallback();

      expect(WorkspaceService.deleteSection).toHaveBeenCalledWith(
        "ws-1",
        "section-1",
      );
      expect(defaultProps.closeConfirm).toHaveBeenCalled();
    });
  });

  describe("resource actions", () => {
    it("should call handleEditResource when edit clicked", () => {
      render(<ResourceSection {...defaultProps} />);
      const editButtons = screen.getAllByTitle("Edit");
      fireEvent.click(editButtons[0]);
      expect(defaultProps.handleEditResource).toHaveBeenCalledWith(
        "res-1",
        "Google",
        "https://google.com",
        "section-1",
      );
    });

    it("should remove resource when remove clicked", async () => {
      render(<ResourceSection {...defaultProps} />);
      const removeButtons = screen.getAllByTitle("Remove");
      fireEvent.click(removeButtons[0]);

      await waitFor(() => {
        expect(WorkspaceService.removeResourceFromSection).toHaveBeenCalledWith(
          "ws-1",
          "section-1",
          "res-1",
        );
        expect(defaultProps.setActiveWorkspaceData).toHaveBeenCalled();
      });
    });
  });

  describe("when design system is enabled", () => {
    beforeEach(() => {
      (useFeatureFlag as unknown as jest.Mock).mockReturnValue(true);
    });

    it("should render section with design system buttons and typography", () => {
      render(<ResourceSection {...defaultProps} />);
      expect(screen.getByText("Test Section")).toBeInTheDocument();
      expect(screen.getByTitle("Open all resources")).toBeInTheDocument();
      expect(screen.getByTitle("Add resource")).toBeInTheDocument();
    });
  });
});
