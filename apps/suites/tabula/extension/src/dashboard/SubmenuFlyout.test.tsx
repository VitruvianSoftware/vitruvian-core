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

import React, { useRef } from "react";
import { render, screen } from "@testing-library/react";
import "@testing-library/jest-dom";
import { SubmenuFlyout } from "./SubmenuFlyout";

/** Anchor + flyout, mirroring how the menu items use it. */
const Harness: React.FC<{ open: boolean }> = ({ open }) => {
  const anchorRef = useRef<HTMLButtonElement>(null);
  return (
    <div className="dropdown-menu" data-testid="parent-menu">
      <button ref={anchorRef}>Change color</button>
      <SubmenuFlyout anchorRef={anchorRef} open={open} minWidth={120}>
        <div className="dropdown-item">Red</div>
      </SubmenuFlyout>
    </div>
  );
};

describe("SubmenuFlyout", () => {
  it("renders nothing while closed", () => {
    render(<Harness open={false} />);
    expect(screen.queryByText("Red")).not.toBeInTheDocument();
  });

  it("renders its children when open", () => {
    render(<Harness open />);
    expect(screen.getByText("Red")).toBeInTheDocument();
  });

  it("portals to document.body so it escapes the parent menu's containing block", () => {
    // Regression guard: the submenu must NOT render as a nested child of the
    // parent `.dropdown-menu` (which carries backdrop-filter and lives inside the
    // overflow-clipped sidebar). It must portal to <body> and use fixed
    // positioning, or it lands off-screen / clipped — the original bug.
    render(<Harness open />);
    const flyout = screen.getByText("Red").closest(".dropdown-menu");
    expect(flyout).not.toBeNull();
    expect(flyout?.parentElement).toBe(document.body);
    expect((flyout as HTMLElement).style.position).toBe("fixed");

    // And it is genuinely outside the parent menu in the tree.
    const parentMenu = screen.getByTestId("parent-menu");
    expect(parentMenu.contains(flyout)).toBe(false);
  });
});
