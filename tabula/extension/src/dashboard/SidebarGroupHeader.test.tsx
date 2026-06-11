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
 * Tests for SidebarGroupHeader component
 */

/// <reference types="@testing-library/jest-dom" />
import { render, screen, fireEvent } from "@testing-library/react";
import {
  SidebarGroupHeader,
  SidebarGroupHeaderProps,
} from "./SidebarGroupHeader";
import type { SpaceGroup } from "../types";

// Mock the Icon component
jest.mock("../components/icons", () => ({
  Icon: ({ name }: { name: string }) => (
    <span data-testid={`icon-${name}`}>{name}</span>
  ),
}));

describe("SidebarGroupHeader", () => {
  const now = Date.now();
  const mockGroup: SpaceGroup = {
    id: "group-1",
    title: "Test Group",
    position: 0,
    collapsed: false,
    color: "#EF4444",
    createdAt: now,
    updatedAt: now,
  };

  const defaultProps: SidebarGroupHeaderProps = {
    group: mockGroup,
    isMenuOpen: false,
    colorPickerOpen: false,
    onToggleCollapse: jest.fn(),
    onToggleMenu: jest.fn(),
    onToggleColorPicker: jest.fn(),
    onRename: jest.fn(),
    onChangeColor: jest.fn().mockResolvedValue(undefined),
    onDelete: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("rendering", () => {
    it("should render group title", () => {
      render(<SidebarGroupHeader {...defaultProps} />);
      expect(screen.getByText("Test Group")).toBeInTheDocument();
    });

    it("should render color indicator when color is present", () => {
      render(<SidebarGroupHeader {...defaultProps} />);
      // Check for the color bar by its style
      // Since it's an inline style div, we can't easily query by role, so we check container HTML or style presence
      // Another way is to assume it's the first child div of the click area
      expect(screen.getByTestId("group-color-indicator")).toBeInTheDocument();
    });

    it("should not render color indicator when group has no color", () => {
      render(
        <SidebarGroupHeader
          {...defaultProps}
          group={{ ...mockGroup, color: undefined }}
        />,
      );
      expect(
        screen.queryByTestId("group-color-indicator"),
      ).not.toBeInTheDocument();
    });

    it("should render collapse icon correctly when expanded", () => {
      render(<SidebarGroupHeader {...defaultProps} />);
      expect(
        screen.getByTestId("icon-keyboard_arrow_down"),
      ).toBeInTheDocument();
    });

    it("should render collapse icon correctly when collapsed", () => {
      render(
        <SidebarGroupHeader
          {...defaultProps}
          group={{ ...mockGroup, collapsed: true }}
        />,
      );
      expect(
        screen.getByTestId("icon-keyboard_arrow_right"),
      ).toBeInTheDocument();
    });
  });

  describe("interactions", () => {
    it("should call onToggleCollapse when clicking the main area", () => {
      render(<SidebarGroupHeader {...defaultProps} />);
      fireEvent.click(screen.getByText("Test Group"));
      expect(defaultProps.onToggleCollapse).toHaveBeenCalled();
    });

    it("should call onToggleMenu when clicking the menu button", () => {
      render(<SidebarGroupHeader {...defaultProps} />);
      fireEvent.click(screen.getByRole("button", { name: "Section options" }));
      expect(defaultProps.onToggleMenu).toHaveBeenCalled();
    });
  });

  describe("dropdown menu", () => {
    it("should not show menu when isMenuOpen is false", () => {
      render(<SidebarGroupHeader {...defaultProps} />);
      expect(screen.queryByText("Rename")).not.toBeInTheDocument();
    });

    it("should show menu when isMenuOpen is true", () => {
      render(<SidebarGroupHeader {...defaultProps} isMenuOpen={true} />);
      expect(screen.getByText("Rename")).toBeInTheDocument();
      expect(screen.getByText("Change color")).toBeInTheDocument();
      expect(screen.getByText("Delete")).toBeInTheDocument();
    });

    it("should call onRename when Rename clicked", () => {
      render(<SidebarGroupHeader {...defaultProps} isMenuOpen={true} />);
      fireEvent.click(screen.getByText("Rename"));
      expect(defaultProps.onRename).toHaveBeenCalled();
    });

    it("should call onDelete when Delete clicked", () => {
      render(<SidebarGroupHeader {...defaultProps} isMenuOpen={true} />);
      fireEvent.click(screen.getByText("Delete"));
      expect(defaultProps.onDelete).toHaveBeenCalled();
    });

    it("should call onToggleColorPicker when Change color clicked", () => {
      render(<SidebarGroupHeader {...defaultProps} isMenuOpen={true} />);
      fireEvent.click(screen.getByText("Change color"));
      expect(defaultProps.onToggleColorPicker).toHaveBeenCalled();
    });
  });

  describe("color picker submenu", () => {
    it("should show color options when isMenuOpen and colorPickerOpen are true", () => {
      render(
        <SidebarGroupHeader
          {...defaultProps}
          isMenuOpen={true}
          colorPickerOpen={true}
        />,
      );
      expect(screen.getByText("None")).toBeInTheDocument();
      expect(screen.getByText("Red")).toBeInTheDocument();
      expect(screen.getByText("Blue")).toBeInTheDocument();
    });

    it("should call onChangeColor when a color is selected", () => {
      render(
        <SidebarGroupHeader
          {...defaultProps}
          isMenuOpen={true}
          colorPickerOpen={true}
        />,
      );
      fireEvent.click(screen.getByText("Blue"));
      expect(defaultProps.onChangeColor).toHaveBeenCalledWith("#3B82F6");
    });

    it("should call onChangeColor with null when None is selected", () => {
      render(
        <SidebarGroupHeader
          {...defaultProps}
          isMenuOpen={true}
          colorPickerOpen={true}
        />,
      );
      fireEvent.click(screen.getByText("None"));
      expect(defaultProps.onChangeColor).toHaveBeenCalledWith(null);
    });
  });
});
