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
 * Tests for SidebarHeader component
 *
 * Tests the sidebar header with logo and children slot.
 */

import { render, screen } from "@testing-library/react";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { SidebarHeader } from "./SidebarHeader";

jest.mock("../lib/flags/use-feature-flag", () => ({
  useFeatureFlag: jest.fn(() => false),
}));

describe("SidebarHeader", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (useFeatureFlag as unknown as jest.Mock).mockReturnValue(false);
  });

  it("should render the Tabula title", () => {
    render(
      <SidebarHeader>
        <div>Placeholder</div>
      </SidebarHeader>,
    );
    expect(screen.getByText("Tabula")).toBeInTheDocument();
  });

  it("should render children", () => {
    render(
      <SidebarHeader>
        <div data-testid="child-element">User Menu</div>
      </SidebarHeader>,
    );
    expect(screen.getByTestId("child-element")).toBeInTheDocument();
    expect(screen.getByText("User Menu")).toBeInTheDocument();
  });

  it("should have proper styling for the header title", () => {
    render(
      <SidebarHeader>
        <div>Placeholder</div>
      </SidebarHeader>,
    );
    const title = screen.getByText("Tabula");
    expect(title).toHaveStyle({
      fontWeight: "700",
      fontSize: "18px",
    });
  });

  it("should render the dashboard icon", () => {
    render(
      <SidebarHeader>
        <div>Placeholder</div>
      </SidebarHeader>,
    );
    // The Icon component renders an i tag with material-icons class
    const icon = document.querySelector(".material-icons");
    expect(icon).toBeInTheDocument();
  });

  describe("when design system is enabled", () => {
    beforeEach(() => {
      (useFeatureFlag as unknown as jest.Mock).mockReturnValue(true);
    });

    it("should render Tabula title with design system styling", () => {
      render(
        <SidebarHeader>
          <div data-testid="user-menu-ds">User Menu</div>
        </SidebarHeader>,
      );
      const title = screen.getByText("Tabula");
      expect(title).toBeInTheDocument();
      expect(title).toHaveStyle({
        fontWeight: "700",
        fontSize: "15px",
        textTransform: "uppercase",
      });
      expect(screen.getByTestId("user-menu-ds")).toBeInTheDocument();
    });
  });
});
