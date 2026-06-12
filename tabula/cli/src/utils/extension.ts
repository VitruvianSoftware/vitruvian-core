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

import fs from "fs";
import os from "os";
import path from "path";

/** Fixed tag of the rolling dev prerelease published per main commit. */
export const DEV_LATEST_TAG = "tabula-extension-dev-latest";

/** Default GitHub repository hosting the dev-latest release. */
export const DEFAULT_REPO = "VitruvianSoftware/vitruvian-core";

/** Default load-unpacked install directory. */
export function defaultExtensionDir(): string {
  return path.join(os.homedir(), ".tabula", "extension");
}

/**
 * Models the workflow-stamped build_info.json — keep in sync with BuildInfo in
 * tabula/extension/src/services/updateCheck.ts (duplicated deliberately: the
 * CLI must not depend on extension code).
 */
export interface BundleInfo {
  commit?: string;
  builtAt?: string;
  version?: string;
}

/** Read the bundle's build identity; null when absent/unreadable. */
export function readBundleInfo(dir: string): BundleInfo | null {
  try {
    return JSON.parse(
      fs.readFileSync(path.join(dir, "build_info.json"), "utf-8"),
    ) as BundleInfo;
  } catch {
    return null;
  }
}

/** A bundle dir must at least carry the extension manifest. */
export function validateBundleDir(dir: string): void {
  if (!fs.existsSync(path.join(dir, "manifest.json"))) {
    throw new Error(
      `Downloaded bundle is missing manifest.json (looked in ${dir})`,
    );
  }
}

/**
 * Atomically replace targetDir with stagingDir.
 *
 * Both directories must live on the same filesystem (rename, not copy). On
 * any failure the previous install is left in place: validation happens
 * before anything moves, and a failed final swap renames the old dir back.
 */
export function atomicInstall(stagingDir: string, targetDir: string): void {
  validateBundleDir(stagingDir);
  fs.mkdirSync(path.dirname(targetDir), { recursive: true });

  const oldDir = `${targetDir}.old-${process.pid}`;
  // A previous run killed mid-swap can strand this dir; with a recycled pid
  // the rename below would then fail ENOTEMPTY. Normally a no-op.
  fs.rmSync(oldDir, { recursive: true, force: true });
  const hadPrevious = fs.existsSync(targetDir);
  if (hadPrevious) fs.renameSync(targetDir, oldDir);
  try {
    fs.renameSync(stagingDir, targetDir);
  } catch (err) {
    if (hadPrevious) fs.renameSync(oldDir, targetDir); // roll back
    throw err;
  }
  if (hadPrevious) fs.rmSync(oldDir, { recursive: true, force: true });
}

/**
 * Switchable release channels for the load-unpacked install (M2 of #45).
 * "stable" exists in the UX but is not installable until the Web Store
 * listing ships (M3) — see resolveChannel.
 */
export type InstallChannel = "alpha" | "beta";

/** Tag prefix of release-please's extension releases (beta channel source). */
export const EXTENSION_RELEASE_TAG_PREFIX = "tabula-extension-v";

/** Read the install's channel marker; null when absent/corrupt/unknown. */
export function readInstalledChannel(dir: string): InstallChannel | null {
  try {
    const parsed = JSON.parse(
      fs.readFileSync(path.join(dir, "channel.json"), "utf-8"),
    ) as { channel?: string };
    return parsed.channel === "alpha" || parsed.channel === "beta"
      ? parsed.channel
      : null;
  } catch {
    return null;
  }
}

/** Label the install with the channel it was installed from. */
export function writeInstalledChannel(
  dir: string,
  channel: InstallChannel,
): void {
  fs.writeFileSync(
    path.join(dir, "channel.json"),
    `${JSON.stringify({ channel }, null, 2)}\n`,
  );
}

/** Precedence: explicit flag > installed channel.json > alpha. */
export function resolveChannel(
  flag: string | undefined,
  installed: InstallChannel | null,
): InstallChannel {
  if (flag === "stable") {
    throw new Error(
      "The stable channel arrives with the Chrome Web Store listing (M3) — use --channel alpha or beta for now.",
    );
  }
  if (flag === "alpha" || flag === "beta") return flag;
  if (flag !== undefined) {
    throw new Error(`Unknown channel '${flag}' — valid: alpha, beta, stable.`);
  }
  return installed ?? "alpha";
}

/**
 * Numeric-segment version compare (missing segments are zero).
 * Mirrors compareVersions in tabula/extension/src/services/updateCheck.ts —
 * duplicated deliberately: the CLI must not depend on extension code.
 */
export function compareSemver(a: string, b: string): number {
  const as = a.split(".").map((s) => parseInt(s, 10) || 0);
  const bs = b.split(".").map((s) => parseInt(s, 10) || 0);
  const len = Math.max(as.length, bs.length);
  for (let i = 0; i < len; i += 1) {
    const diff = (as[i] ?? 0) - (bs[i] ?? 0);
    if (diff !== 0) return diff;
  }
  return 0;
}

/**
 * Pick the newest tabula-extension-v* tag from `gh release list --json
 * tagName` output. Pure (takes the JSON text) so it is testable without gh.
 * Null when no extension release exists or the input is unparseable.
 */
export function resolveLatestExtensionTag(
  releaseListJson: string,
): string | null {
  try {
    const releases = JSON.parse(releaseListJson) as { tagName?: string }[];
    const versions = releases
      .map((r) => r.tagName ?? "")
      .filter((t) => t.startsWith(EXTENSION_RELEASE_TAG_PREFIX))
      .map((t) => t.slice(EXTENSION_RELEASE_TAG_PREFIX.length))
      .filter((v) => /^\d+(\.\d+)*$/.test(v));
    if (versions.length === 0) return null;
    versions.sort(compareSemver);
    return `${EXTENSION_RELEASE_TAG_PREFIX}${versions[versions.length - 1]}`;
  } catch {
    return null;
  }
}
