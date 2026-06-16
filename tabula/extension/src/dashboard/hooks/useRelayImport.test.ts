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
import { renderHook, waitFor } from "@testing-library/react";
import { useRelayImport } from "./useRelayImport";
import { AuthService } from "../../services/auth";
import { ApiService } from "../../services/api";
import { getRelayIdFromUrl, clearRelayIdFromUrl } from "../../utils/router";

jest.mock("../../services/auth", () => ({
  AuthService: { hasSession: jest.fn() },
}));
jest.mock("../../services/api", () => ({
  ApiService: { acceptRelay: jest.fn() },
}));
jest.mock("../../utils/router", () => ({
  getRelayIdFromUrl: jest.fn(),
  clearRelayIdFromUrl: jest.fn(),
}));

const mockHasSession = AuthService.hasSession as jest.Mock;
const mockAcceptRelay = ApiService.acceptRelay as jest.Mock;
const mockGetRelayId = getRelayIdFromUrl as jest.Mock;
const mockClearRelayId = clearRelayIdFromUrl as jest.Mock;

describe("useRelayImport", () => {
  let loadWorkspaces: jest.Mock;
  let setLocalActiveWorkspaceId: jest.Mock;

  const render = () =>
    renderHook(() =>
      useRelayImport({ loadWorkspaces, setLocalActiveWorkspaceId }),
    );

  beforeEach(() => {
    jest.clearAllMocks();
    loadWorkspaces = jest.fn().mockResolvedValue(undefined);
    setLocalActiveWorkspaceId = jest.fn();
    mockHasSession.mockResolvedValue(true);
    mockAcceptRelay.mockResolvedValue({
      workspaceId: "ws_1",
      workspaceName: "Alpha",
      role: "view",
    });
  });

  it("does nothing when the dashboard was not opened from a relay link", async () => {
    mockGetRelayId.mockReturnValue(null);

    render();
    await Promise.resolve();

    expect(mockAcceptRelay).not.toHaveBeenCalled();
    expect(loadWorkspaces).not.toHaveBeenCalled();
    expect(setLocalActiveWorkspaceId).not.toHaveBeenCalled();
  });

  it("redeems the relay, reloads workspaces, and pins this window to the space", async () => {
    mockGetRelayId.mockReturnValue("relay-abc");

    render();

    await waitFor(() =>
      expect(setLocalActiveWorkspaceId).toHaveBeenCalledWith("ws_1"),
    );
    expect(mockAcceptRelay).toHaveBeenCalledWith("relay-abc");
    expect(loadWorkspaces).toHaveBeenCalled();
    // The relayId is always stripped so a reload won't re-redeem a dead link.
    expect(mockClearRelayId).toHaveBeenCalled();
  });

  it("does not redeem when the user is signed out, but still clears the link", async () => {
    mockGetRelayId.mockReturnValue("relay-abc");
    mockHasSession.mockResolvedValue(false);

    render();

    await waitFor(() => expect(mockClearRelayId).toHaveBeenCalled());
    expect(mockAcceptRelay).not.toHaveBeenCalled();
    expect(setLocalActiveWorkspaceId).not.toHaveBeenCalled();
  });

  it("fails silently and clears the link when the relay is invalid", async () => {
    mockGetRelayId.mockReturnValue("dead");
    mockAcceptRelay.mockRejectedValue(new Error("404"));

    render();

    await waitFor(() => expect(mockClearRelayId).toHaveBeenCalled());
    expect(setLocalActiveWorkspaceId).not.toHaveBeenCalled();
  });

  it("redeems only once across re-renders", async () => {
    mockGetRelayId.mockReturnValue("relay-abc");

    const { rerender } = render();
    await waitFor(() => expect(mockAcceptRelay).toHaveBeenCalledTimes(1));

    rerender();
    rerender();
    await Promise.resolve();

    expect(mockAcceptRelay).toHaveBeenCalledTimes(1);
  });
});
