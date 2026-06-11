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

import React from "react";
import { render, screen, fireEvent } from "@testing-library/react";
import AppLayout from "@/app/layout";
import AppLoading from "@/app/loading";
import AppError from "@/app/error";
import AnalyticsLoading from "@/app/analytics/loading";
import WorkspacesLoading from "@/app/workspaces/loading";

// Mock Geist font
jest.mock("next/font/google", () => ({
  Geist: () => ({
    variable: "geist-sans",
    className: "geist-sans-class",
  }),
}));

describe("Common Components", () => {
  describe("Layout", () => {
    it("should render children", () => {
      render(
        <AppLayout>
          <div>Test Content</div>
        </AppLayout>,
      );
      expect(screen.getByText("Test Content")).toBeInTheDocument();
    });
  });

  describe("Loading States", () => {
    it("should render root loading spinner", () => {
      render(<AppLoading />);
      expect(screen.getByText("Loading Tabula...")).toBeInTheDocument();
    });

    it("should render analytics loading skeleton", () => {
      const { container } = render(<AnalyticsLoading />);
      expect(container.querySelector("main")).toBeInTheDocument();
      expect(container.querySelector(".animate-pulse")).toBeInTheDocument();
    });

    it("should render workspaces loading skeleton", () => {
      const { container } = render(<WorkspacesLoading />);
      expect(container.querySelector("main")).toBeInTheDocument();
      expect(container.querySelector(".animate-pulse")).toBeInTheDocument();
    });
  });

  describe("Error Boundary", () => {
    it("should render error message and reset button", () => {
      const resetMock = jest.fn();
      const testError = new Error("Test Error Message");
      render(<AppError error={testError} reset={resetMock} />);

      expect(screen.getByText("Something went wrong")).toBeInTheDocument();
      expect(screen.getByText("Test Error Message")).toBeInTheDocument();

      const btn = screen.getByText("Try Again");
      fireEvent.click(btn);
      expect(resetMock).toHaveBeenCalled();
    });

    it("should render default error message when message is empty", () => {
      const resetMock = jest.fn();
      const testError = { message: "", name: "Error" } as Error;
      render(<AppError error={testError} reset={resetMock} />);

      expect(
        screen.getByText(
          "An unexpected error occurred while loading the dashboard.",
        ),
      ).toBeInTheDocument();
    });
  });
});
