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

import { UpdateCheckService, resetBuildInfoCacheForTests } from "./updateCheck";

if (typeof AbortSignal.timeout !== "function") {
  // jsdom does not implement AbortSignal.timeout — provide a minimal stub
  (AbortSignal as unknown as Record<string, unknown>).timeout = () =>
    new AbortController().signal;
}

// process.env.API_URL is statically replaced by webpack DefinePlugin in real
// builds; under jest it is plain process.env (set in beforeEach).

const mockChrome = {
  runtime: {
    getURL: jest.fn((p: string) => `chrome-extension://abc/${p}`),
  },
  management: {
    getSelf: jest.fn(),
  },
};
// eslint-disable-next-line @typescript-eslint/no-explicit-any
(globalThis as any).chrome = mockChrome;

const mockFetch = jest.fn();
// eslint-disable-next-line @typescript-eslint/no-explicit-any
(globalThis as any).fetch = mockFetch;

const jsonResponse = (body: unknown, ok = true) =>
  Promise.resolve({ ok, json: () => Promise.resolve(body) });

describe("UpdateCheckService", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    resetBuildInfoCacheForTests();
    process.env.API_URL = "https://api.example.com/api/v1";
    mockChrome.management.getSelf.mockResolvedValue({
      installType: "development",
    });
  });

  afterAll(() => {
    delete process.env.API_URL;
  });

  const stubOwnBuild = (commit: string) => {
    mockFetch.mockImplementation((url: string) =>
      url.startsWith("chrome-extension://")
        ? jsonResponse({ commit })
        : jsonResponse({ commit: "serversha" }),
    );
  };

  describe("eligibility", () => {
    it("is eligible for a development install with a CI-built bundle", async () => {
      stubOwnBuild("abc1234");
      await expect(UpdateCheckService.isEligible()).resolves.toEqual({
        eligible: true,
        ownCommit: "abc1234",
      });
    });

    it('is NOT eligible when the bundle commit is "dev" (local build)', async () => {
      stubOwnBuild("dev");
      await expect(UpdateCheckService.isEligible()).resolves.toEqual({
        eligible: false,
        ownCommit: "dev",
      });
    });

    it("is NOT eligible when build_info.json cannot be read", async () => {
      mockFetch.mockResolvedValue({ ok: false });
      const result = await UpdateCheckService.isEligible();
      expect(result.eligible).toBe(false);
    });

    it("is NOT eligible for non-development installs (Web Store)", async () => {
      stubOwnBuild("abc1234");
      mockChrome.management.getSelf.mockResolvedValue({
        installType: "normal",
      });
      const result = await UpdateCheckService.isEligible();
      expect(result.eligible).toBe(false);
    });

    it("is NOT eligible when build_info.json fetch throws", async () => {
      mockFetch.mockRejectedValue(new Error("network error"));
      const result = await UpdateCheckService.isEligible();
      expect(result.eligible).toBe(false);
    });

    it("memoizes getOwnBuildInfo — the chrome-extension:// URL is fetched exactly once across two checkForUpdate calls", async () => {
      stubOwnBuild("abc1234");
      await UpdateCheckService.checkForUpdate();
      await UpdateCheckService.checkForUpdate();
      const buildInfoCalls = mockFetch.mock.calls.filter(
        ([url]: [string]) =>
          typeof url === "string" && url.startsWith("chrome-extension://"),
      );
      expect(buildInfoCalls).toHaveLength(1);
    });
  });

  describe("fetchDeployedCommit", () => {
    it("returns the API root's commit", async () => {
      mockFetch.mockImplementation(() => jsonResponse({ commit: "serversha" }));
      await expect(UpdateCheckService.fetchDeployedCommit()).resolves.toBe(
        "serversha",
      );
      // polls the ORIGIN root, not under /api/v1
      expect(mockFetch).toHaveBeenCalledWith(
        "https://api.example.com/",
        expect.objectContaining({ cache: "no-store" }),
      );
    });

    it('returns null for "unknown" (no false positives)', async () => {
      mockFetch.mockImplementation(() => jsonResponse({ commit: "unknown" }));
      await expect(
        UpdateCheckService.fetchDeployedCommit(),
      ).resolves.toBeNull();
    });

    it("returns null on network failure", async () => {
      mockFetch.mockRejectedValue(new Error("offline"));
      await expect(
        UpdateCheckService.fetchDeployedCommit(),
      ).resolves.toBeNull();
    });
  });

  describe("checkForUpdate", () => {
    it("reports an update when commits differ", async () => {
      stubOwnBuild("abc1234");
      await expect(UpdateCheckService.checkForUpdate()).resolves.toEqual({
        updateAvailable: true,
        ownCommit: "abc1234",
        deployedCommit: "serversha",
      });
    });

    it("reports no update when commits match", async () => {
      mockFetch.mockImplementation((url: string) =>
        url.startsWith("chrome-extension://")
          ? jsonResponse({ commit: "samesha" })
          : jsonResponse({ commit: "samesha" }),
      );
      const result = await UpdateCheckService.checkForUpdate();
      expect(result?.updateAvailable).toBe(false);
    });

    it("returns null when ineligible", async () => {
      stubOwnBuild("dev");
      await expect(UpdateCheckService.checkForUpdate()).resolves.toBeNull();
    });
  });
});
