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
