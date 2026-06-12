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
import { render, screen, fireEvent, act } from "@testing-library/react";
import "@testing-library/jest-dom";
import { UpdateBanner } from "./UpdateBanner";
import { UpdateCheckService } from "../services/updateCheck";

jest.mock("../services/updateCheck");

const mockReload = jest.fn();
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const g = globalThis as any;
g.chrome = { ...(g.chrome ?? {}), runtime: { reload: mockReload } };

const checkForUpdate = UpdateCheckService.checkForUpdate as jest.Mock;

describe("UpdateBanner", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("renders nothing when no update is available", async () => {
    checkForUpdate.mockResolvedValue({
      updateAvailable: false,
      ownCommit: "a",
      deployedCommit: "a",
    });
    render(<UpdateBanner />);
    await act(async () => {
      await Promise.resolve();
    });
    expect(screen.queryByRole("status")).not.toBeInTheDocument();
  });

  it("renders nothing when the check is ineligible (null)", async () => {
    checkForUpdate.mockResolvedValue(null);
    render(<UpdateBanner />);
    await act(async () => {
      await Promise.resolve();
    });
    expect(screen.queryByRole("status")).not.toBeInTheDocument();
  });

  it("shows the deployed short-sha and reloads on click", async () => {
    checkForUpdate.mockResolvedValue({
      updateAvailable: true,
      ownCommit: "oldsha12",
      deployedCommit: "newsha9876",
    });
    render(<UpdateBanner />);
    expect(await screen.findByRole("status")).toBeInTheDocument();

    expect(screen.getByRole("status")).toHaveTextContent("newsha9");
    expect(screen.getByRole("status")).toHaveTextContent("tabcli ext update");

    fireEvent.click(screen.getByRole("button", { name: /reload/i }));
    expect(mockReload).toHaveBeenCalled();
  });

  it("dismiss hides the banner for that deployed commit", async () => {
    checkForUpdate.mockResolvedValue({
      updateAvailable: true,
      ownCommit: "oldsha12",
      deployedCommit: "newsha9876",
    });
    render(<UpdateBanner />);
    expect(await screen.findByRole("status")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: /dismiss/i }));
    expect(screen.queryByRole("status")).not.toBeInTheDocument();
  });

  it("keeps the banner when a later poll fails (null)", async () => {
    jest.useFakeTimers();
    try {
      checkForUpdate.mockResolvedValueOnce({
        updateAvailable: true,
        ownCommit: "oldsha12",
        deployedCommit: "newsha9876",
      });
      checkForUpdate.mockResolvedValue(null);
      render(<UpdateBanner />);
      expect(await screen.findByRole("status")).toBeInTheDocument();

      await act(async () => {
        jest.advanceTimersByTime(15 * 60 * 1000);
      });
      expect(screen.getByRole("status")).toBeInTheDocument();
      expect(checkForUpdate).toHaveBeenCalledTimes(2);
    } finally {
      jest.useRealTimers();
    }
  });
});
