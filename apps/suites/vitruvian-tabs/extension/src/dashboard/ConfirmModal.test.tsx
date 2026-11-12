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
 * Tests for ConfirmModal component
 */

/// <reference types="@testing-library/jest-dom" />
import { render, screen, fireEvent } from "@testing-library/react";
import { ConfirmModal, ConfirmModalProps } from "./ConfirmModal";

// Mock framer-motion to avoid animation complexities in tests
/* eslint-disable @typescript-eslint/no-explicit-any */
jest.mock("framer-motion", () => ({
  motion: {
    div: (props: any) => {
      const {
        children,
        onClick,
        style,
        className,
        _initial,
        _animate,
        _exit,
        _transition,
        ...restProps
      } = props;
      return (
        <div
          onClick={onClick}
          style={style}
          className={className}
          {...restProps}
        >
          {children}
        </div>
      );
    },
  },
  AnimatePresence: ({ children }: any) => <>{children}</>,
}));
/* eslint-enable @typescript-eslint/no-explicit-any */

jest.mock("../lib/flags/use-feature-flag", () => ({
  useFeatureFlag: jest.fn(() => false),
}));

import { useFeatureFlag } from "../lib/flags/use-feature-flag";

describe("ConfirmModal", () => {
  const defaultProps: ConfirmModalProps = {
    open: true,
    title: "Confirm Action",
    message: "Are you sure you want to proceed?",
    onConfirm: jest.fn(),
    onCancel: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (useFeatureFlag as unknown as jest.Mock).mockReturnValue(false);
  });

  describe("rendering", () => {
    it("should not render when open is false", () => {
      render(<ConfirmModal {...defaultProps} open={false} />);
      expect(screen.queryByText("Confirm Action")).not.toBeInTheDocument();
    });

    it("should render when open is true", () => {
      render(<ConfirmModal {...defaultProps} />);
      expect(screen.getByText("Confirm Action")).toBeInTheDocument();
      expect(
        screen.getByText("Are you sure you want to proceed?"),
      ).toBeInTheDocument();
    });

    it("should render cancel and delete buttons", () => {
      render(<ConfirmModal {...defaultProps} />);
      expect(screen.getByText("Cancel")).toBeInTheDocument();
      // The button text is hardcoded as "Delete" in the component currently
      expect(screen.getByText("Delete")).toBeInTheDocument();
    });
  });

  describe("interactions", () => {
    it("should call onCancel when clicking cancel button", () => {
      render(<ConfirmModal {...defaultProps} />);
      fireEvent.click(screen.getByText("Cancel"));
      expect(defaultProps.onCancel).toHaveBeenCalled();
    });

    it("should call onConfirm when clicking delete button", () => {
      render(<ConfirmModal {...defaultProps} />);
      fireEvent.click(screen.getByText("Delete"));
      expect(defaultProps.onConfirm).toHaveBeenCalled();
    });

    it("should call onCancel when clicking backdrop", () => {
      const { container } = render(<ConfirmModal {...defaultProps} />);
      // Get the first child (the overlay/backdrop)
      const backdrop = container.firstChild as HTMLElement;
      fireEvent.click(backdrop);
      expect(defaultProps.onCancel).toHaveBeenCalled();
    });

    it("should not call onCancel when clicking modal content", () => {
      render(<ConfirmModal {...defaultProps} />);
      fireEvent.click(screen.getByText("Confirm Action"));
      expect(defaultProps.onCancel).not.toHaveBeenCalled();
    });
  });

  describe("when design system is enabled", () => {
    beforeEach(() => {
      (useFeatureFlag as unknown as jest.Mock).mockReturnValue(true);
    });

    it("should render with design system components", () => {
      render(<ConfirmModal {...defaultProps} />);
      expect(screen.getByText("Confirm Action")).toBeInTheDocument();
      expect(
        screen.getByText("Are you sure you want to proceed?"),
      ).toBeInTheDocument();
      expect(screen.getByText("WARN")).toBeInTheDocument();
      expect(screen.getByText("Cancel")).toBeInTheDocument();
      expect(screen.getByText("Delete")).toBeInTheDocument();
    });

    it("should handle confirm and cancel in design system mode", () => {
      render(<ConfirmModal {...defaultProps} />);
      fireEvent.click(screen.getByText("Delete"));
      expect(defaultProps.onConfirm).toHaveBeenCalled();

      fireEvent.click(screen.getByText("Cancel"));
      expect(defaultProps.onCancel).toHaveBeenCalled();
    });
  });
});
