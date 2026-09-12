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

import { render, screen, fireEvent, act } from "@testing-library/react";
import { Tooltip } from "./Tooltip";

// Mock framer-motion to avoid animation timing issues in tests
jest.mock("framer-motion", () => ({
  AnimatePresence: ({ children }: { children: React.ReactNode }) => (
    <>{children}</>
  ),
  motion: {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    div: ({
      children,
      initial: _initial,
      animate: _animate,
      exit: _exit,
      transition: _transition,
      ...props
    }: React.HTMLAttributes<HTMLDivElement> & { [key: string]: unknown }) => (
      <div {...(props as React.HTMLAttributes<HTMLDivElement>)}>{children}</div>
    ),
  },
}));

describe("Tooltip", () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it("should render children", () => {
    render(
      <Tooltip content="Tooltip Text">
        <button>Trigger</button>
      </Tooltip>,
    );
    expect(screen.getByText("Trigger")).toBeInTheDocument();
  });

  it("should show tooltip on hover after delay", () => {
    render(
      <Tooltip content="Tooltip Text" delay={100}>
        <button>Trigger</button>
      </Tooltip>,
    );

    const trigger = screen.getByText("Trigger");
    fireEvent.mouseEnter(trigger);

    // Should not be visible yet
    expect(screen.queryByText("Tooltip Text")).not.toBeInTheDocument();

    // Fast forward time
    act(() => {
      jest.advanceTimersByTime(100);
    });

    const tooltip = screen.getByText("Tooltip Text");
    expect(tooltip).toBeInTheDocument();
  });

  it("should hide tooltip on mouse leave", () => {
    render(
      <Tooltip content="Tooltip Text" delay={0}>
        <button>Trigger</button>
      </Tooltip>,
    );

    const trigger = screen.getByText("Trigger");
    fireEvent.mouseEnter(trigger);

    act(() => {
      jest.runAllTimers();
    });

    expect(screen.getByText("Tooltip Text")).toBeInTheDocument();

    fireEvent.mouseLeave(trigger);
    expect(screen.queryByText("Tooltip Text")).not.toBeInTheDocument();
  });

  it("should render with correct transform for top placement", () => {
    render(
      <Tooltip content="Text" placement="top" delay={0}>
        <button>Trigger</button>
      </Tooltip>,
    );
    const trigger = screen.getByText("Trigger");
    fireEvent.mouseEnter(trigger);
    act(() => jest.runAllTimers());

    const tooltip = screen.getByText("Text").closest("div");
    // We check style directly because computing styles in jsdom is limited
    expect(tooltip?.style.transform).toContain("translate(-50%, -100%)");
  });

  it("should render with correct transform for bottom placement", () => {
    render(
      <Tooltip content="Text" placement="bottom" delay={0}>
        <button>Trigger</button>
      </Tooltip>,
    );
    const trigger = screen.getByText("Trigger");
    fireEvent.mouseEnter(trigger);
    act(() => jest.runAllTimers());

    const tooltip = screen.getByText("Text").closest("div");
    expect(tooltip?.style.transform).toContain("translate(-50%, 0)");
  });

  it("should render with correct transform for left placement", () => {
    render(
      <Tooltip content="Text" placement="left" delay={0}>
        <button>Trigger</button>
      </Tooltip>,
    );
    const trigger = screen.getByText("Trigger");
    fireEvent.mouseEnter(trigger);
    act(() => jest.runAllTimers());

    const tooltip = screen.getByText("Text").closest("div");
    expect(tooltip?.style.transform).toContain("translate(-100%, -50%)");
  });

  it("should render with correct transform for right placement", () => {
    render(
      <Tooltip content="Text" placement="right" delay={0}>
        <button>Trigger</button>
      </Tooltip>,
    );
    const trigger = screen.getByText("Trigger");
    fireEvent.mouseEnter(trigger);
    act(() => jest.runAllTimers());

    const tooltip = screen.getByText("Text").closest("div");
    expect(tooltip?.style.transform).toContain("translate(0, -50%)");
  });

  it("should cleanup timeout on unmount", () => {
    const { unmount } = render(
      <Tooltip content="Text" delay={100}>
        <button>Trigger</button>
      </Tooltip>,
    );
    const trigger = screen.getByText("Trigger");
    fireEvent.mouseEnter(trigger);
    unmount();
    // No error should occur
  });

  it("should render shortcut if provided", () => {
    render(
      <Tooltip content="Text" shortcut="Cmd+K" delay={0}>
        <button>Trigger</button>
      </Tooltip>,
    );
    const trigger = screen.getByText("Trigger");
    fireEvent.mouseEnter(trigger);
    act(() => jest.runAllTimers());

    expect(screen.getByText("Cmd+K")).toBeInTheDocument();
  });
});
