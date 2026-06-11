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
 * Tests for SpacesHeader component
 *
 * Tests the spaces section header with add dropdown menu.
 */

import { render, screen, fireEvent } from "@testing-library/react";
import "@testing-library/jest-dom";
import { SpacesHeader } from "./SpacesHeader";

describe("SpacesHeader", () => {
  const defaultProps = {
    spacesMenuOpen: false,
    onToggleSpacesMenu: jest.fn(),
    onNewSpace: jest.fn(),
    onNewSection: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("rendering", () => {
    it("should render the Spaces label", () => {
      render(<SpacesHeader {...defaultProps} />);
      expect(screen.getByText("Spaces")).toBeInTheDocument();
    });

    it("should render the add button", () => {
      render(<SpacesHeader {...defaultProps} />);
      expect(screen.getByTitle("Add")).toBeInTheDocument();
    });

    it("should not show dropdown when spacesMenuOpen is false", () => {
      render(<SpacesHeader {...defaultProps} />);
      expect(screen.queryByText("New space")).not.toBeInTheDocument();
      expect(screen.queryByText("New section")).not.toBeInTheDocument();
    });

    it("should show dropdown when spacesMenuOpen is true", () => {
      render(<SpacesHeader {...defaultProps} spacesMenuOpen={true} />);
      expect(screen.getByText("New space")).toBeInTheDocument();
      expect(screen.getByText("New section")).toBeInTheDocument();
    });
  });

  describe("interactions", () => {
    it("should call onToggleSpacesMenu when add button clicked", () => {
      render(<SpacesHeader {...defaultProps} />);
      fireEvent.click(screen.getByTitle("Add"));
      expect(defaultProps.onToggleSpacesMenu).toHaveBeenCalled();
    });

    it("should call onNewSpace when New space clicked", () => {
      render(<SpacesHeader {...defaultProps} spacesMenuOpen={true} />);
      fireEvent.click(screen.getByText("New space"));
      expect(defaultProps.onNewSpace).toHaveBeenCalled();
    });

    it("should call onNewSection when New section clicked", () => {
      render(<SpacesHeader {...defaultProps} spacesMenuOpen={true} />);
      fireEvent.click(screen.getByText("New section"));
      expect(defaultProps.onNewSection).toHaveBeenCalled();
    });
  });

  describe("styling", () => {
    it("should have uppercase Spaces label", () => {
      render(<SpacesHeader {...defaultProps} />);
      const label = screen.getByText("Spaces");
      expect(label).toHaveStyle({ textTransform: "uppercase" });
    });
  });
});
