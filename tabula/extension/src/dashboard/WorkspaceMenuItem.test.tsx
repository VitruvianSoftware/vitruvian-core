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
 * Tests for WorkspaceMenuItem component
 *
 * Tests the workspace menu item with context menu options.
 */

/// <reference types="@testing-library/jest-dom" />
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { WorkspaceMenuItem } from "./WorkspaceMenuItem";
import type { Workspace, SpaceGroup } from "../types";

describe("WorkspaceMenuItem", () => {
  const now = Date.now();
  const mockWorkspace: Workspace = {
    id: "ws-1",
    name: "Test Workspace",
    icon: "📁",
    position: 0,
    tabs: [],
    resources: [],
    sections: [],
    notes: [],
    tasks: [],
    createdAt: now,
    updatedAt: now,
  };

  const mockSpaceGroups: SpaceGroup[] = [
    {
      id: "group-1",
      title: "Group One",
      position: 0,
      collapsed: false,
      createdAt: now,
      updatedAt: now,
    },
    {
      id: "group-2",
      title: "Group Two",
      position: 1,
      collapsed: false,
      color: "#FF0000",
      createdAt: now,
      updatedAt: now,
    },
  ];

  const defaultProps = {
    workspace: mockWorkspace,
    isActive: false,
    isMenuOpen: false,
    colorPickerOpen: false,
    sectionPickerOpen: false,
    spaceGroups: mockSpaceGroups,
    onSwitch: jest.fn(),
    onToggleMenu: jest.fn(),
    onRename: jest.fn(),
    onDelete: jest.fn(),
    onToggleColorPicker: jest.fn(),
    onToggleSectionPicker: jest.fn(),
    onChangeColor: jest.fn().mockResolvedValue(undefined),
    onMoveToSection: jest.fn().mockResolvedValue(undefined),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("rendering", () => {
    it("should render workspace name", () => {
      render(<WorkspaceMenuItem {...defaultProps} />);
      expect(screen.getByText("Test Workspace")).toBeInTheDocument();
    });

    it("should render workspace icon", () => {
      render(<WorkspaceMenuItem {...defaultProps} />);
      expect(screen.getByText("📁")).toBeInTheDocument();
    });

    it("should use default icon when no icon set", () => {
      render(
        <WorkspaceMenuItem
          {...defaultProps}
          workspace={{ ...mockWorkspace, icon: undefined }}
        />,
      );
      expect(screen.getByText("📁")).toBeInTheDocument(); // Default icon
    });

    it("should apply active class when isActive is true", () => {
      render(<WorkspaceMenuItem {...defaultProps} isActive={true} />);
      const navItem = screen.getByText("Test Workspace").closest(".nav-item");
      expect(navItem).toHaveClass("active");
    });

    it("should not apply active class when isActive is false", () => {
      render(<WorkspaceMenuItem {...defaultProps} isActive={false} />);
      const navItem = screen.getByText("Test Workspace").closest(".nav-item");
      expect(navItem).not.toHaveClass("active");
    });
  });

  describe("menu toggle", () => {
    it("should call onSwitch when workspace name clicked", () => {
      render(<WorkspaceMenuItem {...defaultProps} />);
      fireEvent.click(screen.getByText("Test Workspace"));
      expect(defaultProps.onSwitch).toHaveBeenCalled();
    });

    it("should call onToggleMenu when menu button clicked", () => {
      render(<WorkspaceMenuItem {...defaultProps} />);
      fireEvent.click(screen.getByRole("button", { name: "Space options" }));
      expect(defaultProps.onToggleMenu).toHaveBeenCalled();
    });
  });

  describe("dropdown menu", () => {
    it("should not show menu when isMenuOpen is false", () => {
      render(<WorkspaceMenuItem {...defaultProps} />);
      expect(screen.queryByText("Rename")).not.toBeInTheDocument();
    });

    it("should show menu when isMenuOpen is true", () => {
      render(<WorkspaceMenuItem {...defaultProps} isMenuOpen={true} />);
      expect(screen.getByText("Rename")).toBeInTheDocument();
      expect(screen.getByText("Delete")).toBeInTheDocument();
      expect(screen.getByText("Change color")).toBeInTheDocument();
      expect(screen.getByText("Move to section")).toBeInTheDocument();
    });

    it("should not render the Share menu item while sharing is disabled (#137)", () => {
      render(<WorkspaceMenuItem {...defaultProps} isMenuOpen={true} />);
      // Real sharing lands in M2 (#139/#140); until then the placeholder must
      // not be visible. Other items confirm the menu itself still renders.
      expect(screen.queryByText("Share")).not.toBeInTheDocument();
      expect(screen.getByText("Rename")).toBeInTheDocument();
    });

    it("should call onRename when Rename clicked", () => {
      render(<WorkspaceMenuItem {...defaultProps} isMenuOpen={true} />);
      fireEvent.click(screen.getByText("Rename"));
      expect(defaultProps.onRename).toHaveBeenCalled();
    });

    it("should call onDelete when Delete clicked", () => {
      render(<WorkspaceMenuItem {...defaultProps} isMenuOpen={true} />);
      fireEvent.click(screen.getByText("Delete"));
      expect(defaultProps.onDelete).toHaveBeenCalled();
    });

    it("should call onToggleColorPicker when Change color clicked", () => {
      render(<WorkspaceMenuItem {...defaultProps} isMenuOpen={true} />);
      fireEvent.click(screen.getByText("Change color"));
      expect(defaultProps.onToggleColorPicker).toHaveBeenCalled();
    });

    it("should call onToggleSectionPicker when Move to section clicked", () => {
      render(<WorkspaceMenuItem {...defaultProps} isMenuOpen={true} />);
      fireEvent.click(screen.getByText("Move to section"));
      expect(defaultProps.onToggleSectionPicker).toHaveBeenCalled();
    });
  });

  describe("color picker submenu", () => {
    it("should show color options when colorPickerOpen is true", () => {
      render(
        <WorkspaceMenuItem
          {...defaultProps}
          isMenuOpen={true}
          colorPickerOpen={true}
        />,
      );
      expect(screen.getByText("None")).toBeInTheDocument();
      expect(screen.getByText("Red")).toBeInTheDocument();
      expect(screen.getByText("Blue")).toBeInTheDocument();
    });

    it("should call onChangeColor when color selected", async () => {
      render(
        <WorkspaceMenuItem
          {...defaultProps}
          isMenuOpen={true}
          colorPickerOpen={true}
        />,
      );
      fireEvent.click(screen.getByText("Red"));
      await waitFor(() => {
        expect(defaultProps.onChangeColor).toHaveBeenCalledWith("#EF4444");
      });
    });

    it("should call onChangeColor with null when None selected", async () => {
      render(
        <WorkspaceMenuItem
          {...defaultProps}
          isMenuOpen={true}
          colorPickerOpen={true}
        />,
      );
      fireEvent.click(screen.getByText("None"));
      await waitFor(() => {
        expect(defaultProps.onChangeColor).toHaveBeenCalledWith(null);
      });
    });
  });

  describe("section picker submenu", () => {
    it("should show section options when sectionPickerOpen is true", () => {
      render(
        <WorkspaceMenuItem
          {...defaultProps}
          isMenuOpen={true}
          sectionPickerOpen={true}
        />,
      );
      expect(screen.getByText("No section")).toBeInTheDocument();
      expect(screen.getByText("Group One")).toBeInTheDocument();
      expect(screen.getByText("Group Two")).toBeInTheDocument();
    });

    it("should call onMoveToSection when section selected", async () => {
      render(
        <WorkspaceMenuItem
          {...defaultProps}
          isMenuOpen={true}
          sectionPickerOpen={true}
        />,
      );
      fireEvent.click(screen.getByText("Group One"));
      await waitFor(() => {
        expect(defaultProps.onMoveToSection).toHaveBeenCalledWith("group-1");
      });
    });

    it("should call onMoveToSection with null when No section selected", async () => {
      render(
        <WorkspaceMenuItem
          {...defaultProps}
          isMenuOpen={true}
          sectionPickerOpen={true}
        />,
      );
      fireEvent.click(screen.getByText("No section"));
      await waitFor(() => {
        expect(defaultProps.onMoveToSection).toHaveBeenCalledWith(null);
      });
    });
  });

  describe("effective accent color", () => {
    it("should use workspace color for accent when workspace has a color", () => {
      const workspaceWithColor = { ...mockWorkspace, color: "#22C55E" };
      render(
        <WorkspaceMenuItem
          {...defaultProps}
          workspace={workspaceWithColor}
          isActive={true}
        />,
      );

      const navItem = screen.getByText("Test Workspace").closest(".nav-item");
      expect(navItem).toHaveStyle({ "--workspace-accent-color": "#22C55E" });
    });

    it("should use group color for accent when workspace has no color but group does", () => {
      // Workspace in group-2 which has color #FF0000
      const workspaceInColoredGroup = {
        ...mockWorkspace,
        groupId: "group-2",
        color: undefined,
      };
      render(
        <WorkspaceMenuItem
          {...defaultProps}
          workspace={workspaceInColoredGroup}
          isActive={true}
        />,
      );

      const navItem = screen.getByText("Test Workspace").closest(".nav-item");
      expect(navItem).toHaveStyle({ "--workspace-accent-color": "#FF0000" });
    });

    it("should use default accent when neither workspace nor group has a color", () => {
      // Workspace in group-1 which has no color
      const workspaceInUncoloredGroup = {
        ...mockWorkspace,
        groupId: "group-1",
        color: undefined,
      };
      render(
        <WorkspaceMenuItem
          {...defaultProps}
          workspace={workspaceInUncoloredGroup}
          isActive={true}
        />,
      );

      const navItem = screen.getByText("Test Workspace").closest(".nav-item");
      expect(navItem).toHaveStyle({
        "--workspace-accent-color": "var(--color-accent-primary)",
      });
    });

    it("should use default accent when workspace has no group and no color", () => {
      const ungroupedWorkspace = {
        ...mockWorkspace,
        groupId: undefined,
        color: undefined,
      };
      render(
        <WorkspaceMenuItem
          {...defaultProps}
          workspace={ungroupedWorkspace}
          isActive={true}
        />,
      );

      const navItem = screen.getByText("Test Workspace").closest(".nav-item");
      expect(navItem).toHaveStyle({
        "--workspace-accent-color": "var(--color-accent-primary)",
      });
    });

    it("should prioritize workspace color over group color", () => {
      // Workspace has its own color but is also in a colored group
      const workspaceWithOwnColor = {
        ...mockWorkspace,
        groupId: "group-2", // group-2 has color #FF0000
        color: "#8B5CF6", // workspace has purple
      };
      render(
        <WorkspaceMenuItem
          {...defaultProps}
          workspace={workspaceWithOwnColor}
          isActive={true}
        />,
      );

      const navItem = screen.getByText("Test Workspace").closest(".nav-item");
      // Should use workspace color, not group color
      expect(navItem).toHaveStyle({ "--workspace-accent-color": "#8B5CF6" });
    });
  });
});
