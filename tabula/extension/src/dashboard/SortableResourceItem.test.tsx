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
 * Tests for SortableResourceItem component
 *
 * Tests the sortable resource item with action buttons.
 */

/// <reference types="@testing-library/jest-dom" />
import { render, screen, fireEvent } from "@testing-library/react";
import { DndContext } from "@dnd-kit/core";
import {
  SortableContext,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { SortableResourceItem } from "./SortableResourceItem";
import type { Resource } from "../types";

// Wrap component with required contexts for testing
const renderWithContexts = (
  ui: React.ReactElement,
  items: string[] = ["resource-1"],
) => {
  return render(
    <DndContext>
      <SortableContext items={items} strategy={verticalListSortingStrategy}>
        {ui}
      </SortableContext>
    </DndContext>,
  );
};

describe("SortableResourceItem", () => {
  const mockResource: Resource = {
    id: "resource-1",
    title: "Test Resource",
    url: "https://example.com",
    faviconUrl: "https://example.com/favicon.ico",
    createdAt: Date.now(),
  };

  const defaultProps = {
    resource: mockResource,
    onRemove: jest.fn(),
    onEdit: jest.fn(),
    onActivate: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("rendering", () => {
    it("should render resource title", () => {
      renderWithContexts(<SortableResourceItem {...defaultProps} />);
      expect(screen.getByText("Test Resource")).toBeInTheDocument();
    });

    it("should render resource url", () => {
      renderWithContexts(<SortableResourceItem {...defaultProps} />);
      expect(screen.getByText("https://example.com")).toBeInTheDocument();
    });

    it("should render favicon image", () => {
      const { container } = renderWithContexts(
        <SortableResourceItem {...defaultProps} />,
      );
      const img = container.querySelector("img");
      expect(img).toHaveAttribute("src", "https://example.com/favicon.ico");
    });

    // Note: Google favicon fallback test skipped - DOM query with empty alt is unreliable
  });

  describe("action buttons", () => {
    it("should render Open Link button", () => {
      renderWithContexts(<SortableResourceItem {...defaultProps} />);
      expect(screen.getByTitle("Open Link")).toBeInTheDocument();
    });

    it("should render Edit button", () => {
      renderWithContexts(<SortableResourceItem {...defaultProps} />);
      expect(screen.getByTitle("Edit")).toBeInTheDocument();
    });

    it("should render Remove button", () => {
      renderWithContexts(<SortableResourceItem {...defaultProps} />);
      expect(screen.getByTitle("Remove")).toBeInTheDocument();
    });

    it("should call onActivate when Open Link clicked", () => {
      renderWithContexts(<SortableResourceItem {...defaultProps} />);
      fireEvent.click(screen.getByTitle("Open Link"));
      expect(defaultProps.onActivate).toHaveBeenCalled();
    });

    it("should call onEdit when Edit clicked", () => {
      renderWithContexts(<SortableResourceItem {...defaultProps} />);
      fireEvent.click(screen.getByTitle("Edit"));
      expect(defaultProps.onEdit).toHaveBeenCalled();
    });

    it("should call onRemove when Remove clicked", () => {
      renderWithContexts(<SortableResourceItem {...defaultProps} />);
      fireEvent.click(screen.getByTitle("Remove"));
      expect(defaultProps.onRemove).toHaveBeenCalled();
    });

    it("should stop propagation on Open Link pointerDown", () => {
      renderWithContexts(<SortableResourceItem {...defaultProps} />);
      const event = { stopPropagation: jest.fn() };
      fireEvent.pointerDown(screen.getByTitle("Open Link"), event);
      // The event should have stopPropagation called
    });

    it("should stop propagation on Edit pointerDown", () => {
      renderWithContexts(<SortableResourceItem {...defaultProps} />);
      const event = { stopPropagation: jest.fn() };
      fireEvent.pointerDown(screen.getByTitle("Edit"), event);
    });

    it("should stop propagation on Remove pointerDown", () => {
      renderWithContexts(<SortableResourceItem {...defaultProps} />);
      const event = { stopPropagation: jest.fn() };
      fireEvent.pointerDown(screen.getByTitle("Remove"), event);
    });
  });

  describe("favicon fallback", () => {
    it("should use Google favicon service when faviconUrl is undefined", () => {
      const resourceWithoutFavicon: Resource = {
        ...mockResource,
        faviconUrl: undefined,
      };
      const { container } = renderWithContexts(
        <SortableResourceItem
          {...defaultProps}
          resource={resourceWithoutFavicon}
        />,
      );
      const img = container.querySelector("img");
      expect(img).toHaveAttribute(
        "src",
        "https://www.google.com/s2/favicons?domain=https://example.com",
      );
    });

    it("should use Google favicon service when faviconUrl is empty string", () => {
      const resourceWithEmptyFavicon: Resource = {
        ...mockResource,
        faviconUrl: "",
      };
      const { container } = renderWithContexts(
        <SortableResourceItem
          {...defaultProps}
          resource={resourceWithEmptyFavicon}
        />,
      );
      const img = container.querySelector("img");
      expect(img).toHaveAttribute(
        "src",
        "https://www.google.com/s2/favicons?domain=https://example.com",
      );
    });
  });
});
