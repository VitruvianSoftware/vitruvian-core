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

  it("on a 401 from accept, prompts login and re-enables the button without navigating", async () => {
    mockToken.mockReturnValue("tok");
    mockInfo.mockResolvedValue(info("view"));
    mockAccept.mockRejectedValue(new ApiError(401, "unauthorized"));
    (AuthService.login as jest.Mock).mockResolvedValue(undefined);
    render(<RelayLandingPage />);
    const btn = await screen.findByRole("button", { name: /View in browser/ });
    fireEvent.click(btn);
    await waitFor(() => expect(AuthService.login).toHaveBeenCalled());
    expect(push).not.toHaveBeenCalled();
    expect(
      await screen.findByRole("button", { name: /View in browser/ }),
    ).toBeEnabled();
  });

  it("on a non-401 accept failure, clears busy without logging in or navigating", async () => {
    mockToken.mockReturnValue("tok");
    mockInfo.mockResolvedValue(info("view"));
    mockAccept.mockRejectedValue(new ApiError(404, "gone"));
    render(<RelayLandingPage />);
    const btn = await screen.findByRole("button", { name: /View in browser/ });
    fireEvent.click(btn);
    await waitFor(() => expect(btn).toBeEnabled());
    expect(AuthService.login).not.toHaveBeenCalled();
    expect(push).not.toHaveBeenCalled();
  });

  it("logged-out 'Log in to open in browser' triggers the login flow", async () => {
    mockInfo.mockResolvedValue(info("view"));
    (AuthService.login as jest.Mock).mockResolvedValue(undefined);
    render(<RelayLandingPage />);
    const btn = await screen.findByRole("button", {
      name: /Log in to open in browser/,
    });
    fireEvent.click(btn);
    await waitFor(() => expect(AuthService.login).toHaveBeenCalled());
  });
});

// The extension-installed path depends on a non-empty extension id (read at
// call time) plus a chrome stub, so it gets its own setup. Detection must only
// pick the CTA — it must never auto-redeem or auto-deep-link (consent gate).
describe("RelayLandingPage — extension installed", () => {
  const origId = process.env.NEXT_PUBLIC_TABULA_EXTENSION_ID;
  let sendMessage: jest.Mock;

  const installChrome = (
    opts: { respond?: boolean; lastError?: unknown } = {},
  ) => {
    const { respond = true, lastError = undefined } = opts;
    sendMessage = jest.fn(
      (_id: string, msg: unknown, cb?: (r: unknown) => void) => {
        if (cb && (msg as { type?: string })?.type === "PING") {
          cb(respond ? { ok: true } : undefined);
        }
      },
    );
    (globalThis as unknown as { chrome: unknown }).chrome = {
      runtime: { lastError, sendMessage },
    };
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockToken.mockReturnValue(null);
    process.env.NEXT_PUBLIC_TABULA_EXTENSION_ID = "ext-id";
  });

  afterEach(() => {
    process.env.NEXT_PUBLIC_TABULA_EXTENSION_ID = origId;
    delete (globalThis as unknown as { chrome?: unknown }).chrome;
  });

  it("shows 'Open in Tabula' on PING success and deep-links the relay only on click", async () => {
    installChrome({ respond: true });
    mockInfo.mockResolvedValue(info("view"));
    render(<RelayLandingPage />);

    const openBtn = await screen.findByRole("button", {
      name: /Open in Tabula/,
    });
    expect(screen.queryByText("Install Tabula")).not.toBeInTheDocument();
    // PING fired during detection, but IMPORT_SPACE must NOT fire without a click.
    expect(sendMessage).not.toHaveBeenCalledWith(
      "ext-id",
      expect.objectContaining({ type: "IMPORT_SPACE" }),
    );

    fireEvent.click(openBtn);
    expect(sendMessage).toHaveBeenCalledWith("ext-id", {
      type: "IMPORT_SPACE",
      spaceId: "ws_1",
      relayId: "relay-abc",
    });
    await waitFor(() =>
      expect(screen.getByText(/Opening in Tabula/)).toBeInTheDocument(),
    );
  });

  it("falls back to the Install preview when PING reports a lastError", async () => {
    installChrome({ respond: true, lastError: { message: "no" } });
    mockInfo.mockResolvedValue(info("view"));
    render(<RelayLandingPage />);
    await waitFor(() =>
      expect(screen.getByText("Install Tabula")).toBeInTheDocument(),
    );
    expect(
      screen.queryByRole("button", { name: /Open in Tabula/ }),
    ).not.toBeInTheDocument();
  });

  it("falls back to the Install preview when the extension never answers (timeout)", async () => {
    sendMessage = jest.fn(); // never invokes the PING callback
    (globalThis as unknown as { chrome: unknown }).chrome = {
      runtime: { sendMessage },
    };
    mockInfo.mockResolvedValue(info("view"));
    render(<RelayLandingPage />);
    await waitFor(
      () => expect(screen.getByText("Install Tabula")).toBeInTheDocument(),
      { timeout: 2000 },
    );
  });
});
