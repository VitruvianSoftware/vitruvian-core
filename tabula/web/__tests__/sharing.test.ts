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

import { SharingService, ApiError } from "@/lib/sharing";
import { AuthService } from "@/lib/auth";

jest.mock("@/lib/auth", () => ({
  AuthService: { getToken: jest.fn() },
}));

const mockGetToken = AuthService.getToken as jest.Mock;
const mockFetch = jest.fn();
global.fetch = mockFetch as unknown as typeof fetch;

const ok = (data: unknown, status = 200) => ({
  ok: status >= 200 && status < 300,
  status,
  json: async () => ({ data }),
});

describe("SharingService", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetToken.mockReturnValue("test-token");
  });

  describe("getSpace", () => {
    it("GETs the workspace with a Bearer header and unwraps { data }", async () => {
      mockFetch.mockResolvedValue(ok({ id: "ws_1", name: "Alpha" }));
      const space = await SharingService.getSpace("ws_1");
      expect(space).toEqual({ id: "ws_1", name: "Alpha" });
      const [url, init] = mockFetch.mock.calls[0];
      expect(url).toBe("http://localhost:8080/api/v1/workspaces/ws_1");
      expect(init.headers.Authorization).toBe("Bearer test-token");
    });

    it("throws ApiError(404) for an inaccessible / missing space", async () => {
      mockFetch.mockResolvedValue(ok(null, 404));
      await expect(SharingService.getSpace("ws_x")).rejects.toMatchObject({
        name: "ApiError",
        status: 404,
      });
    });

    it("throws ApiError(401) when there is no token (not logged in)", async () => {
      mockGetToken.mockReturnValue(null);
      await expect(SharingService.getSpace("ws_1")).rejects.toMatchObject({
        status: 401,
      });
      expect(mockFetch).not.toHaveBeenCalled();
    });
  });

  describe("saveSpace", () => {
    it("PUTs the patch + baseVersion and returns the updated space", async () => {
      mockFetch.mockResolvedValue(ok({ id: "ws_1", version: 3 }));
      await SharingService.saveSpace("ws_1", { name: "Renamed" }, 2);
      const [url, init] = mockFetch.mock.calls[0];
      expect(url).toBe("http://localhost:8080/api/v1/workspaces/ws_1");
      expect(init.method).toBe("PUT");
      expect(JSON.parse(init.body)).toEqual({
        name: "Renamed",
        baseVersion: 2,
      });
    });

    it("throws ApiError(409) carrying the server's current copy on a conflict", async () => {
      mockFetch.mockResolvedValue(ok({ id: "ws_1", version: 9 }, 409));
      const err = await SharingService.saveSpace("ws_1", {}, 1).catch((e) => e);
      expect(err).toBeInstanceOf(ApiError);
      expect(err.status).toBe(409);
      expect(err.data).toEqual({ id: "ws_1", version: 9 });
    });

    it("throws ApiError(403) for a view-only collaborator", async () => {
      mockFetch.mockResolvedValue(ok(null, 403));
      await expect(
        SharingService.saveSpace("ws_1", {}, 1),
      ).rejects.toMatchObject({ status: 403 });
    });
  });

  describe("getSharedWithMe", () => {
    it("returns the caller's grants", async () => {
      mockFetch.mockResolvedValue(
        ok([{ workspaceId: "ws_1", role: "edit", name: "Alpha" }]),
      );
      const spaces = await SharingService.getSharedWithMe();
      expect(spaces).toHaveLength(1);
      expect(mockFetch.mock.calls[0][0]).toBe(
        "http://localhost:8080/api/v1/workspaces/shared-with-me",
      );
    });
  });

  describe("acceptShareLink", () => {
    it("POSTs the token in the BODY (not the URL) and returns the grant", async () => {
      mockFetch.mockResolvedValue(
        ok({ workspaceId: "ws_1", workspaceName: "Alpha", role: "view" }),
      );
      const result = await SharingService.acceptShareLink("secret-token");
      expect(result.role).toBe("view");
      const [url, init] = mockFetch.mock.calls[0];
      expect(url).toBe("http://localhost:8080/api/v1/share-links/accept");
      expect(url).not.toContain("secret-token");
      expect(JSON.parse(init.body)).toEqual({ token: "secret-token" });
    });
  });

  describe("relay", () => {
    it("getRelayInfo fetches the public preview WITHOUT an auth header", async () => {
      mockFetch.mockResolvedValue(
        ok({
          workspaceId: "ws_1",
          workspaceName: "Alpha",
          ownerName: "Jane",
          role: "view",
        }),
      );
      const info = await SharingService.getRelayInfo("relay-abc");
      expect(info.ownerName).toBe("Jane");
      const [url, init] = mockFetch.mock.calls[0];
      expect(url).toBe(
        "http://localhost:8080/api/v1/share-links/relay/relay-abc/info",
      );
      // Public endpoint: no Authorization header is sent.
      expect(init?.headers).toBeUndefined();
    });

    it("acceptRelay POSTs to the relay accept endpoint with a Bearer header", async () => {
      mockFetch.mockResolvedValue(
        ok({ workspaceId: "ws_1", workspaceName: "Alpha", role: "edit" }),
      );
      const result = await SharingService.acceptRelay("relay-abc");
      expect(result.role).toBe("edit");
      const [url, init] = mockFetch.mock.calls[0];
      expect(url).toBe(
        "http://localhost:8080/api/v1/share-links/relay/relay-abc/accept",
      );
      expect(init.method).toBe("POST");
      expect(init.headers.Authorization).toBe("Bearer test-token");
    });
  });
});
