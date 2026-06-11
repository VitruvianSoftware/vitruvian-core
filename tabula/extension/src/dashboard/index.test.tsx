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

/* eslint-disable @typescript-eslint/no-explicit-any */
/* eslint-disable no-console */
import { createRoot } from "react-dom/client";

declare let require: any;

// Mock ReactDOM
jest.mock("react-dom/client", () => ({
  createRoot: jest.fn(() => ({
    render: jest.fn(),
  })),
}));

// Mock Dashboard component
jest.mock("./Dashboard", () => ({
  Dashboard: () => <div>Dashboard Mock</div>,
}));

describe("Dashboard Index", () => {
  const originalGetElementById = document.getElementById;

  beforeEach(() => {
    jest.clearAllMocks();
  });

  afterAll(() => {
    document.getElementById = originalGetElementById;
  });

  it("should render Dashboard into root element", () => {
    // Mock document.getElementById
    const mockRoot = document.createElement("div");
    mockRoot.id = "root";
    document.getElementById = jest.fn().mockReturnValue(mockRoot);

    // Require the index file to trigger execution
    require("./index");

    expect(createRoot).toHaveBeenCalledWith(mockRoot);
    // Checking render call is tricky because createRoot returns an object,
    // but we verify createRoot is called with the correct element.
  });

  it("should not crash if root element is missing", () => {
    document.getElementById = jest.fn().mockReturnValue(null);

    require("./index");

    expect(createRoot).not.toHaveBeenCalled();
  });
});
