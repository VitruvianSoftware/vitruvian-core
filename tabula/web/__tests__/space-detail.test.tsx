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

import { render, screen, waitFor } from "@testing-library/react";
import SpaceDetailPage from "@/app/workspaces/[id]/page";
import { SharingService, ApiError } from "@/lib/sharing";

jest.mock("next/navigation", () => ({
  useParams: () => ({ id: "ws_1" }),
}));

jest.mock("@/lib/sharing", () => {
  class MockApiError extends Error {
    status: number;
    constructor(status: number, message: string) {
      super(message);
      this.name = "ApiError";
      this.status = status;
    }
  }
  return {
    ApiError: MockApiError,
    SharingService: { getSpace: jest.fn() },
  };
});

const mockGetSpace = SharingService.getSpace as jest.Mock;

const fullSpace = {
  id: "ws_1",
  name: "Alpha",
  position: 0,
  tabs: [],
  resources: [],
  sections: [],
  notes: [],
  tasks: [],
  createdAt: 0,
  updatedAt: 0,
};

describe("SpaceDetailPage", () => {
  beforeEach(() => jest.clearAllMocks());

  it("shows a loading state, then the space on success", async () => {
    mockGetSpace.mockResolvedValue(fullSpace);
    render(<SpaceDetailPage />);
    expect(screen.getByText(/Loading space/)).toBeInTheDocument();
    await waitFor(() => expect(screen.getByText("Alpha")).toBeInTheDocument());
    expect(mockGetSpace).toHaveBeenCalledWith("ws_1");
  });

  it("renders an existence-masked message on 404 (no access vs missing are identical)", async () => {
    mockGetSpace.mockRejectedValue(new ApiError(404, "nope"));
    render(<SpaceDetailPage />);
    await waitFor(() =>
      expect(screen.getByText(/was not found, or you/)).toBeInTheDocument(),
    );
  });

  it("prompts login on 401", async () => {
    mockGetSpace.mockRejectedValue(new ApiError(401, "nope"));
    render(<SpaceDetailPage />);
    await waitFor(() =>
      expect(screen.getByText(/log in to view/)).toBeInTheDocument(),
    );
  });

  it("shows a generic error otherwise", async () => {
    mockGetSpace.mockRejectedValue(new Error("network"));
    render(<SpaceDetailPage />);
    await waitFor(() =>
      expect(screen.getByText(/Something went wrong/)).toBeInTheDocument(),
    );
  });
});
