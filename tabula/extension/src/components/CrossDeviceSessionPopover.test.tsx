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

import { render, screen, fireEvent } from "@testing-library/react";
import {
  CrossDeviceSessionPopover,
  type CrossDeviceTab,
} from "./CrossDeviceSessionPopover";

const tabs: CrossDeviceTab[] = [
  { url: "https://google.com", title: "Google" },
  { url: "https://github.com", title: "GitHub" },
  { url: "https://mdn.com", title: "MDN" },
];

describe("CrossDeviceSessionPopover", () => {
  it("renders the prompt with all incoming tabs", () => {
    render(
      <CrossDeviceSessionPopover
        serverTabs={tabs}
        onApply={jest.fn()}
        onKeepMine={jest.fn()}
      />,
    );
    expect(
      screen.getByText("Changes from your other device"),
    ).toBeInTheDocument();
    expect(screen.getByText("Google")).toBeInTheDocument();
    expect(screen.getByText("GitHub")).toBeInTheDocument();
    expect(screen.getByText("MDN")).toBeInTheDocument();
  });

  it("selects all tabs by default and Apply sends them all", () => {
    const onApply = jest.fn();
    render(
      <CrossDeviceSessionPopover
        serverTabs={tabs}
        onApply={onApply}
        onKeepMine={jest.fn()}
      />,
    );
    fireEvent.click(screen.getByText(/Apply 3 tabs/));
    expect(onApply).toHaveBeenCalledTimes(1);
    expect(onApply.mock.calls[0][0]).toHaveLength(3);
  });

  it("unchecking a tab excludes it from Apply", () => {
    const onApply = jest.fn();
    render(
      <CrossDeviceSessionPopover
        serverTabs={tabs}
        onApply={onApply}
        onKeepMine={jest.fn()}
      />,
    );
    // Toggle "GitHub" off, then apply the remaining two.
    fireEvent.click(screen.getByText("GitHub"));
    expect(screen.getByText(/Apply 2 tabs/)).toBeInTheDocument();
    fireEvent.click(screen.getByText(/Apply 2 tabs/));
    const applied = onApply.mock.calls[0][0] as CrossDeviceTab[];
    expect(applied.map((t) => t.url)).toEqual([
      "https://google.com",
      "https://mdn.com",
    ]);
  });

  it("'Keep my tabs' triggers onKeepMine and never applies", () => {
    const onApply = jest.fn();
    const onKeepMine = jest.fn();
    render(
      <CrossDeviceSessionPopover
        serverTabs={tabs}
        onApply={onApply}
        onKeepMine={onKeepMine}
      />,
    );
    fireEvent.click(screen.getByText("Keep my tabs"));
    expect(onKeepMine).toHaveBeenCalledTimes(1);
    expect(onApply).not.toHaveBeenCalled();
  });

  it("disables Apply when nothing is selected", () => {
    const onApply = jest.fn();
    render(
      <CrossDeviceSessionPopover
        serverTabs={[{ url: "https://only.com", title: "Only" }]}
        onApply={onApply}
        onKeepMine={jest.fn()}
      />,
    );
    fireEvent.click(screen.getByText("Only")); // uncheck the single tab
    // The disabled button does not fire its click handler.
    fireEvent.click(screen.getByText(/Apply 0 tabs/));
    expect(onApply).not.toHaveBeenCalled();
  });

  it("singularizes the Apply label for one selected tab", () => {
    render(
      <CrossDeviceSessionPopover
        serverTabs={[{ url: "https://only.com", title: "Only" }]}
        onApply={jest.fn()}
        onKeepMine={jest.fn()}
      />,
    );
    expect(screen.getByText("Apply 1 tab")).toBeInTheDocument();
  });
});
