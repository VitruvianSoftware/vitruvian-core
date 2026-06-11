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

import { render, fireEvent, screen } from "@testing-library/react";
import { MenuOverlay } from "./MenuOverlay";

describe("MenuOverlay", () => {
  const mockOnClose = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("should render with default zIndex", () => {
    render(<MenuOverlay onClose={mockOnClose} />);

    const overlay = screen.getByTestId("menu-overlay");
    expect(overlay).toBeDefined();
    expect(overlay.style.zIndex).toBe("10");
  });

  it("should render with custom zIndex", () => {
    render(<MenuOverlay onClose={mockOnClose} zIndex={20} />);

    const overlay = screen.getByTestId("menu-overlay");
    expect(overlay.style.zIndex).toBe("20");
  });

  it("should call onClose when clicked", () => {
    render(<MenuOverlay onClose={mockOnClose} />);

    const overlay = screen.getByTestId("menu-overlay");
    expect(overlay).not.toBeNull();

    fireEvent.click(overlay);

    expect(mockOnClose).toHaveBeenCalledTimes(1);
  });

  it("should call onClose on right-click (context menu)", () => {
    render(<MenuOverlay onClose={mockOnClose} />);

    const overlay = screen.getByTestId("menu-overlay");
    expect(overlay).not.toBeNull();

    fireEvent.contextMenu(overlay);

    expect(mockOnClose).toHaveBeenCalledTimes(1);
  });

  it("should prevent default and stop propagation on click", () => {
    render(<MenuOverlay onClose={mockOnClose} />);

    const overlay = screen.getByTestId("menu-overlay");
    expect(overlay).not.toBeNull();

    const clickEvent = new MouseEvent("click", {
      bubbles: true,
      cancelable: true,
    });
    const preventDefaultSpy = jest.spyOn(clickEvent, "preventDefault");
    const stopPropagationSpy = jest.spyOn(clickEvent, "stopPropagation");

    overlay.dispatchEvent(clickEvent);

    expect(preventDefaultSpy).toHaveBeenCalled();
    expect(stopPropagationSpy).toHaveBeenCalled();
  });

  it("should prevent default and stop propagation on context menu", () => {
    render(<MenuOverlay onClose={mockOnClose} />);

    const overlay = screen.getByTestId("menu-overlay");
    expect(overlay).not.toBeNull();

    const contextMenuEvent = new MouseEvent("contextmenu", {
      bubbles: true,
      cancelable: true,
    });
    const preventDefaultSpy = jest.spyOn(contextMenuEvent, "preventDefault");
    const stopPropagationSpy = jest.spyOn(contextMenuEvent, "stopPropagation");

    overlay.dispatchEvent(contextMenuEvent);

    expect(preventDefaultSpy).toHaveBeenCalled();
    expect(stopPropagationSpy).toHaveBeenCalled();
  });
});
