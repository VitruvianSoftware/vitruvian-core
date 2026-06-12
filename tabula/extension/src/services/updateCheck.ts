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
 * Dev-channel update detection (issue #45, M1).
 *
 * A load-unpacked CI-built install compares its own baked-in commit
 * (build_info.json, injected by the dev-latest workflow) against the deployed
 * dev API's GET / provenance (#32). A mismatch means a newer bundle is
 * published: the user runs `tabcli ext update`, then reloads.
 *
 * Never active for Web Store installs (installType !== "development") or
 * local ad-hoc builds (commit === "dev"). chrome.management.getSelf() is
 * exempt from the "management" permission.
 */

export interface BuildInfo {
  commit: string;
  builtAt?: string;
  version?: string;
}

export interface UpdateCheckResult {
  updateAvailable: boolean;
  ownCommit: string;
  deployedCommit: string;
}

// The running code's identity is immutable, but the on-disk file is swapped
// by `tabcli ext update` before the reload — re-reading it then would hide
// the reload nudge. Read once per extension context.
let buildInfoPromise: Promise<BuildInfo | null> | undefined;

export function resetBuildInfoCacheForTests(): void {
  buildInfoPromise = undefined;
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

  /** The deployed dev API's commit, from its GET / provenance endpoint. */
  static async fetchDeployedCommit(): Promise<string | null> {
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
      const body = (await res.json()) as { commit?: string };
      if (!body.commit || body.commit === "unknown") return null;
      return body.commit;
    } catch {
      return null;
    }
  }

  /** null = ineligible or no reliable answer (failures stay silent). */
  static async checkForUpdate(): Promise<UpdateCheckResult | null> {
    const { eligible, ownCommit } = await this.isEligible();
    if (!eligible || !ownCommit) return null;
    const deployedCommit = await this.fetchDeployedCommit();
    if (!deployedCommit) return null;
    return {
      updateAvailable: deployedCommit !== ownCommit,
      ownCommit,
      deployedCommit,
    };
  }
}
