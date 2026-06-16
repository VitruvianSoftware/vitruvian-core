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

import { render, screen, waitFor, fireEvent } from "@testing-library/react";
import RelayLandingPage from "@/app/s/[relayId]/page";
import { SharingService, ApiError } from "@/lib/sharing";
import { AuthService } from "@/lib/auth";

const push = jest.fn();
jest.mock("next/navigation", () => ({
  useParams: () => ({ relayId: "relay-abc" }),
  useRouter: () => ({ push }),
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
    SharingService: { getRelayInfo: jest.fn(), acceptRelay: jest.fn() },
  };
});

jest.mock("@/lib/auth", () => ({
  AuthService: { getToken: jest.fn(), login: jest.fn() },
}));

const mockInfo = SharingService.getRelayInfo as jest.Mock;
const mockAccept = SharingService.acceptRelay as jest.Mock;
const mockToken = AuthService.getToken as jest.Mock;

const info = (role: "view" | "edit" = "view") => ({
  workspaceId: "ws_1",
  workspaceName: "Alpha",
  ownerName: "Jane",
  role,
});

describe("RelayLandingPage", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockToken.mockReturnValue(null);
  });

  it("shows an invalid-link message for an unknown / revoked relay id", async () => {
    mockInfo.mockRejectedValue(new ApiError(404, "nope"));
    render(<RelayLandingPage />);
    await waitFor(() =>
      expect(
        screen.getByText(/invalid, revoked, or expired/),
      ).toBeInTheDocument(),
    );
  });

  it("previews the space with Install + Log in for a logged-out stranger", async () => {
    mockInfo.mockResolvedValue(info("view"));
    render(<RelayLandingPage />);
    await waitFor(() => expect(screen.getByText("Alpha")).toBeInTheDocument());
    expect(screen.getByText(/Jane shared a space/)).toBeInTheDocument();
    expect(screen.getByText("Install Tabula")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Log in/ })).toBeInTheDocument();
  });

  it("offers 'View in browser' for a logged-in viewer, then accepts + navigates", async () => {
    mockToken.mockReturnValue("tok");
    mockInfo.mockResolvedValue(info("view"));
    mockAccept.mockResolvedValue({
      workspaceId: "ws_1",
      workspaceName: "Alpha",
      role: "view",
    });
    render(<RelayLandingPage />);
    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: /View in browser/ }),
      ).toBeInTheDocument(),
    );
    fireEvent.click(screen.getByRole("button", { name: /View in browser/ }));
    await waitFor(() => expect(mockAccept).toHaveBeenCalledWith("relay-abc"));
    expect(push).toHaveBeenCalledWith("/workspaces/ws_1");
  });

  it("offers 'Edit in browser' for a logged-in editor", async () => {
    mockToken.mockReturnValue("tok");
    mockInfo.mockResolvedValue(info("edit"));
    render(<RelayLandingPage />);
    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: /Edit in browser/ }),
      ).toBeInTheDocument(),
    );
  });
});
