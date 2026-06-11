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
/* eslint-disable no-console */
/**
 * Tests for OpenTabsPanel component
 *
 * Tests the active tabs panel with sortable tab list.
 */

/// <reference types="@testing-library/jest-dom" />
import { render, screen, fireEvent } from "@testing-library/react";
import { DndContext } from "@dnd-kit/core";
import { OpenTabsPanel } from "./OpenTabsPanel";
import type { Tab } from "../types";

// Wrap component with DndContext for testing
const renderWithContext = (ui: React.ReactElement) => {
  return render(<DndContext>{ui}</DndContext>);
};

describe("OpenTabsPanel", () => {
  const mockTabs: Tab[] = [
    {
      id: 1,
      title: "First Tab",
      url: "https://first.com",
    },
    {
      id: 2,
      title: "Second Tab",
      url: "https://second.com",
    },
  ];

  const defaultProps = {
    activeTabs: mockTabs,
    onCloseTab: jest.fn(),
    onEditTab: jest.fn(),
    onActivateTab: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("rendering", () => {
    it("should render Active Tabs heading", () => {
      renderWithContext(<OpenTabsPanel {...defaultProps} />);
      expect(screen.getByText("Active Tabs")).toBeInTheDocument();
    });

    it("should render all tabs", () => {
      renderWithContext(<OpenTabsPanel {...defaultProps} />);
      expect(screen.getByText("First Tab")).toBeInTheDocument();
      expect(screen.getByText("Second Tab")).toBeInTheDocument();
    });

    it("should render tab urls", () => {
      renderWithContext(<OpenTabsPanel {...defaultProps} />);
      expect(screen.getByText("https://first.com")).toBeInTheDocument();
      expect(screen.getByText("https://second.com")).toBeInTheDocument();
    });

    it("should render empty list when no tabs", () => {
      renderWithContext(<OpenTabsPanel {...defaultProps} activeTabs={[]} />);
      expect(screen.getByText("Active Tabs")).toBeInTheDocument();
      // Tab list should be empty
      expect(screen.queryByText("First Tab")).not.toBeInTheDocument();
    });
  });

  describe("interactions", () => {
    it("should call onCloseTab when close button clicked", () => {
      renderWithContext(<OpenTabsPanel {...defaultProps} />);
      const closeButtons = screen.getAllByTitle("Close Tab");
      fireEvent.click(closeButtons[0]);
      expect(defaultProps.onCloseTab).toHaveBeenCalledWith(
        1,
        "https://first.com",
      );
    });

    it("should call onEditTab when edit button clicked", () => {
      renderWithContext(<OpenTabsPanel {...defaultProps} />);
      const editButtons = screen.getAllByTitle("Edit");
      fireEvent.click(editButtons[0]);
      expect(defaultProps.onEditTab).toHaveBeenCalledWith(mockTabs[0]);
    });

    it("should call onActivateTab when focus button clicked", () => {
      renderWithContext(<OpenTabsPanel {...defaultProps} />);
      const focusButtons = screen.getAllByTitle("Focus Tab");
      fireEvent.click(focusButtons[0]);
      expect(defaultProps.onActivateTab).toHaveBeenCalledWith(1, mockTabs[0]);
    });

    it("should NOT call onCloseTab when tab has no id", () => {
      const tabWithoutId: Tab = {
        id: undefined as any,
        title: "No ID Tab",
        url: "https://noid.com",
      };
      renderWithContext(
        <OpenTabsPanel {...defaultProps} activeTabs={[tabWithoutId]} />,
      );
      const closeButtons = screen.getAllByTitle("Close Tab");
      fireEvent.click(closeButtons[0]);
      expect(defaultProps.onCloseTab).not.toHaveBeenCalled();
    });

    it("should NOT call onActivateTab when tab has no id", () => {
      const tabWithoutId: Tab = {
        id: undefined as any,
        title: "No ID Tab",
        url: "https://noid.com",
      };
      renderWithContext(
        <OpenTabsPanel {...defaultProps} activeTabs={[tabWithoutId]} />,
      );
      const focusButtons = screen.getAllByTitle("Focus Tab");
      fireEvent.click(focusButtons[0]);
      expect(defaultProps.onActivateTab).not.toHaveBeenCalled();
    });
  });

  describe("tab groups", () => {
    it("should render group header when tabs have groupId", () => {
      const tabsWithGroup: Tab[] = [
        { id: 1, title: "Tab 1", url: "https://a.com", groupId: "tg_001" },
        { id: 2, title: "Tab 2", url: "https://b.com", groupId: "tg_001" },
      ];
      const tabGroups = [
        { id: "tg_001", title: "My Group", color: "blue", collapsed: false },
      ];
      renderWithContext(
        <OpenTabsPanel
          {...defaultProps}
          activeTabs={tabsWithGroup}
          tabGroups={tabGroups as any}
        />,
      );
      expect(screen.getByText("My Group")).toBeInTheDocument();
      expect(screen.getByText("2")).toBeInTheDocument(); // tab count
    });

    it("should hide tabs when group is collapsed in Chrome state", () => {
      const tabsWithGroup: Tab[] = [
        { id: 1, title: "Tab 1", url: "https://a.com", groupId: "tg_001" },
      ];
      // Group is collapsed in Chrome state
      const tabGroups = [
        { id: "tg_001", title: "My Group", color: "blue", collapsed: true },
      ];
      renderWithContext(
        <OpenTabsPanel
          {...defaultProps}
          activeTabs={tabsWithGroup}
          tabGroups={tabGroups as any}
        />,
      );

      // Group header should still be visible
      expect(screen.getByText("My Group")).toBeInTheDocument();

      // But tab should be hidden since group is collapsed
      expect(screen.queryByText("Tab 1")).not.toBeInTheDocument();
    });

    it("should show tabs when group is expanded in Chrome state", () => {
      const tabsWithGroup: Tab[] = [
        { id: 1, title: "Tab 1", url: "https://a.com", groupId: "tg_001" },
      ];
      // Group is expanded in Chrome state
      const tabGroups = [
        { id: "tg_001", title: "My Group", color: "blue", collapsed: false },
      ];
      renderWithContext(
        <OpenTabsPanel
          {...defaultProps}
          activeTabs={tabsWithGroup}
          tabGroups={tabGroups as any}
        />,
      );

      // Tab should be visible
      expect(screen.getByText("Tab 1")).toBeInTheDocument();
    });

    it("should show ungrouped tabs separately", () => {
      const mixedTabs: Tab[] = [
        { id: 1, title: "Grouped", url: "https://a.com", groupId: "tg_001" },
        { id: 2, title: "Ungrouped", url: "https://b.com" },
      ];
      const tabGroups = [
        { id: "tg_001", title: "My Group", color: "blue", collapsed: false },
      ];
      renderWithContext(
        <OpenTabsPanel
          {...defaultProps}
          activeTabs={mixedTabs}
          tabGroups={tabGroups as any}
        />,
      );
      expect(screen.getByText("My Group")).toBeInTheDocument();
      expect(screen.getByText("Grouped")).toBeInTheDocument();
      expect(screen.getByText("Ungrouped")).toBeInTheDocument();
    });

    it("should show Untitled for group without title", () => {
      const tabsWithGroup: Tab[] = [
        { id: 1, title: "Tab 1", url: "https://a.com", groupId: "tg_001" },
      ];
      const tabGroups = [
        { id: "tg_001", title: "", color: "red", collapsed: false },
      ];
      renderWithContext(
        <OpenTabsPanel
          {...defaultProps}
          activeTabs={tabsWithGroup}
          tabGroups={tabGroups as any}
        />,
      );
      expect(screen.getByText("Untitled")).toBeInTheDocument();
    });
  });
});
