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

import {
  UpdateCheckService,
  compareVersions,
  resetBuildInfoCacheForTests,
  resetChannelCacheForTests,
} from "./updateCheck";

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
    getManifest: jest.fn(() => ({ version: "0.1.9" })),
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
    resetChannelCacheForTests();
    process.env.API_URL = "https://api.example.com/api/v1";
    mockChrome.management.getSelf.mockResolvedValue({
      installType: "development",
    });
  });

  afterAll(() => {
    Reflect.deleteProperty(process.env, "API_URL");
  });

  const stubInstall = (opts: {
    commit?: string;
    channel?: string | null; // null => channel.json fetch fails (pre-M2 install)
    apiCommit?: string;
    apiVersion?: string;
  }) => {
    const {
      commit = "abc1234",
      channel = "alpha",
      apiCommit = "serversha",
      apiVersion = "0.1.9",
    } = opts;
    mockFetch.mockImplementation((url: string) => {
      if (url.endsWith("build_info.json")) return jsonResponse({ commit });
      if (url.endsWith("channel.json")) {
        return channel === null
          ? Promise.resolve({ ok: false })
          : jsonResponse({ channel });
      }
      return jsonResponse({ commit: apiCommit, version: apiVersion });
    });
  };

  describe("eligibility", () => {
    it("is eligible for a development install with a CI-built bundle", async () => {
      stubInstall({ commit: "abc1234" });
      await expect(UpdateCheckService.isEligible()).resolves.toEqual({
        eligible: true,
        ownCommit: "abc1234",
      });
    });

    it('is NOT eligible when the bundle commit is "dev" (local build)', async () => {
      stubInstall({ commit: "dev" });
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
      stubInstall({ commit: "abc1234" });
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
      stubInstall({ commit: "abc1234" });
      await UpdateCheckService.checkForUpdate();
      await UpdateCheckService.checkForUpdate();
      const buildInfoCalls = mockFetch.mock.calls.filter(
        ([url]: [string]) =>
          typeof url === "string" && url.endsWith("build_info.json"),
      );
      expect(buildInfoCalls).toHaveLength(1);
    });
  });

  describe("fetchDeployedInfo", () => {
    it("returns the API root's commit and version", async () => {
      mockFetch.mockImplementation(() =>
        jsonResponse({ commit: "serversha", version: "0.2.0" }),
      );
      await expect(UpdateCheckService.fetchDeployedInfo()).resolves.toEqual({
        commit: "serversha",
        version: "0.2.0",
      });
      expect(mockFetch).toHaveBeenCalledWith(
        "https://api.example.com/",
        expect.objectContaining({ cache: "no-store" }),
      );
    });

    it('returns null for an "unknown" commit (no false positives)', async () => {
      mockFetch.mockImplementation(() =>
        jsonResponse({ commit: "unknown", version: "0.2.0" }),
      );
      await expect(UpdateCheckService.fetchDeployedInfo()).resolves.toBeNull();
    });

    it("returns null on network failure", async () => {
      mockFetch.mockRejectedValue(new Error("offline"));
      await expect(UpdateCheckService.fetchDeployedInfo()).resolves.toBeNull();
    });

    it("tolerates a missing version field (alpha can still work)", async () => {
      mockFetch.mockImplementation(() => jsonResponse({ commit: "serversha" }));
      await expect(UpdateCheckService.fetchDeployedInfo()).resolves.toEqual({
        commit: "serversha",
        version: null,
      });
    });
  });

  describe("checkForUpdate — alpha", () => {
    it("reports an update when commits differ", async () => {
      stubInstall({ commit: "abc1234", apiCommit: "serversha" });
      await expect(UpdateCheckService.checkForUpdate()).resolves.toEqual({
        channel: "alpha",
        updateAvailable: true,
        current: "abc1234",
        latest: "serversha",
      });
    });

    it("reports no update when commits match", async () => {
      stubInstall({
        commit: "samesha",
        apiCommit: "samesha",
        apiVersion: "9.9.9", // alpha must ignore versions entirely
      });
      const result = await UpdateCheckService.checkForUpdate();
      expect(result?.updateAvailable).toBe(false);
    });

    it("treats a missing channel.json as alpha (pre-M2 install)", async () => {
      stubInstall({ channel: null, commit: "abc1234", apiCommit: "newsha" });
      const result = await UpdateCheckService.checkForUpdate();
      expect(result?.channel).toBe("alpha");
      expect(result?.updateAvailable).toBe(true);
    });

    it("returns null when ineligible", async () => {
      stubInstall({ commit: "dev" });
      await expect(UpdateCheckService.checkForUpdate()).resolves.toBeNull();
    });
  });

  describe("checkForUpdate — beta", () => {
    it("reports an update when the API version is newer", async () => {
      stubInstall({ channel: "beta", apiVersion: "0.2.0" }); // own manifest 0.1.9
      await expect(UpdateCheckService.checkForUpdate()).resolves.toEqual({
        channel: "beta",
        updateAvailable: true,
        current: "0.1.9",
        latest: "0.2.0",
      });
    });

    it("reports no update when versions match", async () => {
      stubInstall({ channel: "beta", apiVersion: "0.1.9" });
      const result = await UpdateCheckService.checkForUpdate();
      expect(result?.updateAvailable).toBe(false);
    });

    it("does not offer a DOWNGRADE when the API lags the install", async () => {
      stubInstall({ channel: "beta", apiVersion: "0.1.2" });
      const result = await UpdateCheckService.checkForUpdate();
      expect(result?.updateAvailable).toBe(false);
    });

    it("returns null when the API version is missing", async () => {
      mockFetch.mockImplementation((url: string) => {
        if (url.endsWith("build_info.json"))
          return jsonResponse({ commit: "abc1234" });
        if (url.endsWith("channel.json"))
          return jsonResponse({ channel: "beta" });
        return jsonResponse({ commit: "serversha" }); // no version field
      });
      await expect(UpdateCheckService.checkForUpdate()).resolves.toBeNull();
    });
  });

  describe("getOwnChannel", () => {
    it("memoizes the channel read", async () => {
      stubInstall({ channel: "beta" });
      await UpdateCheckService.getOwnChannel();
      await UpdateCheckService.getOwnChannel();
      const channelFetches = mockFetch.mock.calls.filter(([url]) =>
        String(url).endsWith("channel.json"),
      );
      expect(channelFetches).toHaveLength(1);
    });

    it("falls back to alpha on unknown values", async () => {
      stubInstall({ channel: "stable" });
      await expect(UpdateCheckService.getOwnChannel()).resolves.toBe("alpha");
    });
  });

  describe("compareVersions", () => {
    it("orders numerically per segment", () => {
      expect(compareVersions("0.10.0", "0.9.9")).toBeGreaterThan(0);
      expect(compareVersions("1.0.0", "1.0.0")).toBe(0);
      expect(compareVersions("0.1.9", "0.2.0")).toBeLessThan(0);
    });

    it("treats missing segments as zero", () => {
      expect(compareVersions("1.0", "1.0.0")).toBe(0);
    });
  });

  describe("getDisplayIdentity", () => {
    it("returns channel + commit + version for an eligible install", async () => {
      stubInstall({ channel: "beta", commit: "abc1234" });
      await expect(UpdateCheckService.getDisplayIdentity()).resolves.toEqual({
        channel: "beta",
        commit: "abc1234",
        version: "0.1.9", // from the mocked manifest
      });
    });

    it("returns null when ineligible (local/dev or Web Store install)", async () => {
      stubInstall({ commit: "dev" });
      await expect(UpdateCheckService.getDisplayIdentity()).resolves.toBeNull();
    });
  });
});
