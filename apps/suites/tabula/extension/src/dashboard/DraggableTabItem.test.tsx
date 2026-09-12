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
 * Tests for DraggableTabItem component
 *
 * Tests the draggable tab item with action buttons.
 */

/// <reference types="@testing-library/jest-dom" />
import { render, screen, fireEvent } from "@testing-library/react";
import { DndContext } from "@dnd-kit/core";
import {
  SortableContext,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { DraggableTabItem } from "./DraggableTabItem";
import type { Tab } from "../types";

jest.mock("../lib/flags/use-feature-flag", () => ({
  useFeatureFlag: jest.fn(() => false),
}));

// Wrap component with required contexts for testing
const renderWithContexts = (
  ui: React.ReactElement,
  items: string[] = ["tab-1"],
) => {
  return render(
    <DndContext>
      <SortableContext items={items} strategy={verticalListSortingStrategy}>
        {ui}
      </SortableContext>
    </DndContext>,
  );
};

describe("DraggableTabItem", () => {
  const mockTab: Tab = {
    id: 1,
    title: "Test Tab",
    url: "https://example.com",
    favIconUrl: "https://example.com/favicon.ico",
  };

  const defaultProps = {
    tab: mockTab,
    onClose: jest.fn(),
    onEdit: jest.fn(),
    onActivate: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (useFeatureFlag as unknown as jest.Mock).mockReturnValue(false);
  });

  describe("rendering", () => {
    it("should render tab title", () => {
      renderWithContexts(<DraggableTabItem {...defaultProps} />);
      expect(screen.getByText("Test Tab")).toBeInTheDocument();
    });

    it("should render tab url", () => {
      renderWithContexts(<DraggableTabItem {...defaultProps} />);
      expect(screen.getByText("https://example.com")).toBeInTheDocument();
    });

    it("should render favicon image", () => {
      const { container } = renderWithContexts(
        <DraggableTabItem {...defaultProps} />,
      );
      const img = container.querySelector("img");
      expect(img).toHaveAttribute("src", "https://example.com/favicon.ico");
    });

    // Note: Google favicon fallback test skipped - DOM query with empty alt is unreliable
    //       The fallback logic is tested implicitly when the component renders
  });

  describe("action buttons", () => {
    it("should render Focus Tab button", () => {
      renderWithContexts(<DraggableTabItem {...defaultProps} />);
      expect(screen.getByTitle("Focus Tab")).toBeInTheDocument();
    });

    it("should render Edit button", () => {
      renderWithContexts(<DraggableTabItem {...defaultProps} />);
      expect(screen.getByTitle("Edit")).toBeInTheDocument();
    });

    it("should render Close Tab button", () => {
      renderWithContexts(<DraggableTabItem {...defaultProps} />);
      expect(screen.getByTitle("Close Tab")).toBeInTheDocument();
    });

    it("should call onActivate when Focus Tab clicked", () => {
      renderWithContexts(<DraggableTabItem {...defaultProps} />);
      fireEvent.click(screen.getByTitle("Focus Tab"));
      expect(defaultProps.onActivate).toHaveBeenCalled();
    });

    it("should call onEdit when Edit clicked", () => {
      renderWithContexts(<DraggableTabItem {...defaultProps} />);
      fireEvent.click(screen.getByTitle("Edit"));
      expect(defaultProps.onEdit).toHaveBeenCalled();
    });

    it("should call onClose when Close Tab clicked", () => {
      renderWithContexts(<DraggableTabItem {...defaultProps} />);
      fireEvent.click(screen.getByTitle("Close Tab"));
      expect(defaultProps.onClose).toHaveBeenCalled();
    });
  });

  describe("favicon fallback", () => {
    it("should use Google favicon service when favIconUrl is undefined", () => {
      const tabWithoutFavicon: Tab = {
        ...mockTab,
        favIconUrl: undefined,
      };
      const { container } = renderWithContexts(
        <DraggableTabItem {...defaultProps} tab={tabWithoutFavicon} />,
      );
      const img = container.querySelector("img");
      expect(img).toHaveAttribute(
        "src",
        "https://www.google.com/s2/favicons?domain=https%3A%2F%2Fexample.com&sz=32",
      );
    });

    it("should use Google favicon service when favIconUrl is empty", () => {
      const tabWithEmptyFavicon: Tab = {
        ...mockTab,
        favIconUrl: "",
      };
      const { container } = renderWithContexts(
        <DraggableTabItem {...defaultProps} tab={tabWithEmptyFavicon} />,
      );
      const img = container.querySelector("img");
      expect(img).toHaveAttribute(
        "src",
        "https://www.google.com/s2/favicons?domain=https%3A%2F%2Fexample.com&sz=32",
      );
    });
  });

  describe("when design system is enabled", () => {
    beforeEach(() => {
      (useFeatureFlag as unknown as jest.Mock).mockReturnValue(true);
    });

    it("should render tab with design system structure", () => {
      renderWithContexts(<DraggableTabItem {...defaultProps} />);
      expect(screen.getByText("Test Tab")).toBeInTheDocument();
      expect(screen.getByText("https://example.com")).toBeInTheDocument();
      expect(screen.getByTitle("Focus Tab")).toBeInTheDocument();
      expect(screen.getByTitle("Edit")).toBeInTheDocument();
      expect(screen.getByTitle("Close Tab")).toBeInTheDocument();
    });
  });
});
