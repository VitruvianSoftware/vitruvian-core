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
import "@testing-library/jest-dom";
import {
  CrossDeviceSessionPopover,
  type CrossDeviceTab,
} from "./CrossDeviceSessionPopover";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";

jest.mock("../lib/flags/use-feature-flag", () => ({
  useFeatureFlag: jest.fn(() => false),
}));

const tabs: CrossDeviceTab[] = [
  { url: "https://google.com", title: "Google" },
  { url: "https://github.com", title: "GitHub" },
  { url: "https://mdn.com", title: "MDN" },
];

describe("CrossDeviceSessionPopover", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (useFeatureFlag as unknown as jest.Mock).mockReturnValue(false);
  });

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

    fireEvent.click(screen.getByRole("button", { name: /Apply 3 tabs/ }));
    expect(onApply).toHaveBeenCalledWith(tabs);
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

    fireEvent.click(screen.getByText("GitHub"));
    fireEvent.click(screen.getByRole("button", { name: /Apply 2 tabs/ }));

    expect(onApply).toHaveBeenCalledWith([tabs[0], tabs[2]]);
  });

  it("unchecking all tabs disables Apply", () => {
    render(
      <CrossDeviceSessionPopover
        serverTabs={tabs}
        onApply={jest.fn()}
        onKeepMine={jest.fn()}
      />,
    );

    fireEvent.click(screen.getByText("Google"));
    fireEvent.click(screen.getByText("GitHub"));
    fireEvent.click(screen.getByText("MDN"));

    const btn = screen.getByRole("button", { name: /Apply 0 tabs/ });
    expect(btn).toBeDisabled();
  });

  it("Keep mine invokes onKeepMine without applying", () => {
    const onKeepMine = jest.fn();
    const onApply = jest.fn();
    render(
      <CrossDeviceSessionPopover
        serverTabs={tabs}
        onApply={onApply}
        onKeepMine={onKeepMine}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: /Keep my tabs/ }));
    expect(onKeepMine).toHaveBeenCalled();
    expect(onApply).not.toHaveBeenCalled();
  });

  it("uses the optional device label in the subtitle", () => {
    render(
      <CrossDeviceSessionPopover
        serverTabs={tabs}
        otherDeviceLabel="MacBook Pro"
        onApply={jest.fn()}
        onKeepMine={jest.fn()}
      />,
    );

    expect(
      screen.getByText(/This space is active on MacBook Pro/),
    ).toBeInTheDocument();
  });

  describe("when design system is enabled", () => {
    beforeEach(() => {
      (useFeatureFlag as unknown as jest.Mock).mockReturnValue(true);
    });

    it("renders design system cross device popover", () => {
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
      expect(
        screen.getByRole("button", { name: /Apply 3 tabs/ }),
      ).toBeInTheDocument();
    });
  });
});
