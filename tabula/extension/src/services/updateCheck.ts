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

/**
 * Channel-aware update detection (issue #45, M2).
 *
 * Alpha channel: a load-unpacked CI-built install compares its own baked-in
 * commit (build_info.json) against the deployed dev API's GET / provenance
 * (#32). A commit mismatch means a newer bundle is published.
 *
 * Beta channel: tracks release cuts via lockstep versioning. The install's
 * manifest version is compared against the API's reported version; strictly
 * newer API version = update available (never triggers on a downgrade).
 *
 * Never active for Web Store installs (installType !== "development") or
 * local ad-hoc builds (commit === "dev"). chrome.management.getSelf() is
 * exempt from the "management" permission.
 */

/**
 * Models the workflow-stamped build_info.json — keep in sync with BundleInfo
 * in tabula/cli/src/utils/extension.ts (duplicated deliberately: the CLI must
 * not depend on extension code).
 */
export interface BuildInfo {
  commit: string;
  builtAt?: string;
  version?: string;
}

/** Release channel of this install (channel.json, written by tabcli). */
export type Channel = "alpha" | "beta";

/**
 * Numeric-segment version compare (missing segments are zero). Mirrors
 * compareSemver in tabula/cli/src/utils/extension.ts — duplicated
 * deliberately: the CLI must not depend on extension code.
 */
export function compareVersions(a: string, b: string): number {
  const as = a.split(".").map((s) => parseInt(s, 10) || 0);
  const bs = b.split(".").map((s) => parseInt(s, 10) || 0);
  const len = Math.max(as.length, bs.length);
  for (let i = 0; i < len; i += 1) {
    const diff = (as[i] ?? 0) - (bs[i] ?? 0);
    if (diff !== 0) return diff;
  }
  return 0;
}

export interface UpdateCheckResult {
  channel: Channel;
  updateAvailable: boolean;
  /** Own commit (alpha) or own version (beta). */
  current: string;
  /** Deployed commit (alpha) or deployed version (beta). */
  latest: string;
}

// The running code's identity is immutable, but the on-disk file is swapped
// by `tabcli ext update` before the reload — re-reading it then would hide
// the reload nudge. Read once per extension context.
let buildInfoPromise: Promise<BuildInfo | null> | undefined;

export function resetBuildInfoCacheForTests(): void {
  buildInfoPromise = undefined;
}

// Same lifetime rule as the build-info read: the running context's channel
// is immutable even though tabcli may swap channel.json before the reload.
let channelPromise: Promise<Channel> | undefined;

export function resetChannelCacheForTests(): void {
  channelPromise = undefined;
}

export class UpdateCheckService {
  /** Read this build's identity from the packaged build_info.json. */
  static async getOwnBuildInfo(): Promise<BuildInfo | null> {
    if (buildInfoPromise !== undefined) return buildInfoPromise;
    buildInfoPromise = (async () => {
      try {
        const res = await fetch(chrome.runtime.getURL("build_info.json"));
        if (!res.ok) return null;
        return (await res.json()) as BuildInfo;
      } catch {
        return null;
      }
    })();
    return buildInfoPromise;
  }

  /** This install's channel (channel.json); absent/unknown → alpha. */
  static async getOwnChannel(): Promise<Channel> {
    if (channelPromise !== undefined) return channelPromise;
    channelPromise = (async () => {
      try {
        const res = await fetch(chrome.runtime.getURL("channel.json"));
        if (!res.ok) return "alpha";
        const body = (await res.json()) as { channel?: string };
        return body.channel === "beta" ? "beta" : "alpha";
      } catch {
        return "alpha";
      }
    })();
    return channelPromise;
  }

  /** Dev installs of CI-built bundles only. */
  static async isEligible(): Promise<{
    eligible: boolean;
    ownCommit: string | null;
  }> {
    const info = await this.getOwnBuildInfo();
    const ownCommit = info?.commit ?? null;
    if (!ownCommit || ownCommit === "dev") {
      return { eligible: false, ownCommit };
    }
    try {
      const self = await chrome.management.getSelf();
      if (self.installType !== "development") {
        return { eligible: false, ownCommit };
      }
    } catch {
      return { eligible: false, ownCommit };
    }
    return { eligible: true, ownCommit };
  }

  /** The deployed dev API's identity, from its GET / provenance endpoint. */
  static async fetchDeployedInfo(): Promise<{
    commit: string;
    version: string | null;
  } | null> {
    const apiUrl = process.env.API_URL;
    if (!apiUrl) return null;
    try {
      const origin = new URL(apiUrl).origin;
      // banner must never trust a cached provenance; hung polls shouldn't stall
      const res = await fetch(`${origin}/`, {
        cache: "no-store",
        signal: AbortSignal.timeout(10_000),
      });
      if (!res.ok) return null;
      const body = (await res.json()) as { commit?: string; version?: string };
      if (!body.commit || body.commit === "unknown") return null;
      return { commit: body.commit, version: body.version ?? null };
    } catch {
      return null;
    }
  }

  /**
   * Identity for display surfaces (Settings, dashboard footer). Null unless
   * this is an eligible dev install of a CI-built bundle — Web Store users
   * and local ad-hoc builds never see channel/commit chrome.
   */
  static async getDisplayIdentity(): Promise<{
    channel: Channel;
    commit: string;
    version: string;
  } | null> {
    const { eligible, ownCommit } = await this.isEligible();
    if (!eligible || !ownCommit) return null;
    return {
      channel: await this.getOwnChannel(),
      commit: ownCommit,
      version: chrome.runtime.getManifest().version,
    };
  }

  /** null = ineligible or no reliable answer (failures stay silent). */
  static async checkForUpdate(): Promise<UpdateCheckResult | null> {
    const { eligible, ownCommit } = await this.isEligible();
    if (!eligible || !ownCommit) return null;
    const deployed = await this.fetchDeployedInfo();
    if (!deployed) return null;

    const channel = await this.getOwnChannel();
    if (channel === "beta") {
      // Beta tracks release cuts: lockstep versioning makes the API's
      // version the latest cut. Strictly-newer only — never a downgrade.
      if (!deployed.version) return null;
      const own = chrome.runtime.getManifest().version;
      return {
        channel,
        updateAvailable: compareVersions(deployed.version, own) > 0,
        current: own,
        latest: deployed.version,
      };
    }
    return {
      channel,
      updateAvailable: deployed.commit !== ownCommit,
      current: ownCommit,
      latest: deployed.commit,
    };
  }
}
