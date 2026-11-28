// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HELPER_DIR = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const REPO_ROOT = path.resolve(HELPER_DIR, "..", "..", "..", "..", "..");

function parseNodeLock(content: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (line.length === 0 || line.startsWith("#")) {
      continue;
    }
    const eqIdx = line.indexOf("=");
    expect(eqIdx).toBeGreaterThan(0);
    const key = line.slice(0, eqIdx).trim();
    const val = line.slice(eqIdx + 1).trim();
    expect(out[key]).toBeUndefined();
    out[key] = val;
  }
  return out;
}

function parseModuleNodeRepositories(
  moduleBazel: string,
  version: string,
): { "darwin-arm64": string; "darwin-x64": string } | undefined {
  const extractSha = (platform: string): string | undefined => {
    const escaped = `${version}-${platform}`.replace(
      /[.*+?^${}()|[\]\\]/g,
      "\\$&",
    );
    const re = new RegExp(
      `"${escaped}"\\s*:\\s*[\\[(]\\s*"[^"]*"\\s*,\\s*"[^"]*"\\s*,\\s*"([0-9a-f]{64})"`,
    );
    return re.exec(moduleBazel)?.[1];
  };
  const arm64 = extractSha("darwin_arm64");
  const amd64 = extractSha("darwin_amd64");
  if (arm64 !== undefined && amd64 !== undefined) {
    return { "darwin-arm64": arm64, "darwin-x64": amd64 };
  }
  return undefined;
}

describe("claude-helper node.lock", () => {
  test("matches //:.nvmrc and rules_nodejs Darwin SHA-256 sums", () => {
    const nvmrcVersion = readFileSync(
      path.join(REPO_ROOT, ".nvmrc"),
      "utf8",
    ).trim();
    expect(nvmrcVersion).toMatch(/^\d+\.\d+\.\d+$/);

    const lock = parseNodeLock(
      readFileSync(path.join(HELPER_DIR, "node.lock"), "utf8"),
    );
    expect(Object.keys(lock).sort()).toEqual([
      "darwin-arm64",
      "darwin-x64",
      "version",
    ]);
    expect(lock.version).toBe(nvmrcVersion);
    expect(lock["darwin-arm64"]).toMatch(/^[0-9a-f]{64}$/);
    expect(lock["darwin-x64"]).toMatch(/^[0-9a-f]{64}$/);

    const rulesNodejsSums = JSON.parse(
      readFileSync(
        path.join(HELPER_DIR, "rules_nodejs_darwin_sums.json"),
        "utf8",
      ),
    ) as Record<string, { "darwin-arm64": string; "darwin-x64": string }>;

    if (Object.keys(rulesNodejsSums).length === 0) {
      throw new Error(
        "rules_nodejs_darwin_sums.json is empty: node_lock.bzl no longer finds rules_nodejs's Node checksums (it reads the private nodejs/private/node_versions.bzl). See node_lock.bzl.",
      );
    }
    const moduleSums = parseModuleNodeRepositories(
      readFileSync(path.join(REPO_ROOT, "MODULE.bazel"), "utf8"),
      nvmrcVersion,
    );
    const entry = moduleSums ?? rulesNodejsSums[nvmrcVersion];
    if (entry === undefined) {
      throw new Error(
        `Neither MODULE.bazel node_repositories nor rules_nodejs has Darwin arm64+x64 checksums for Node ${nvmrcVersion} (//:.nvmrc). ` +
          "Upgrade rules_nodejs or pin node_repositories in MODULE.bazel, then update node.lock.",
      );
    }
    expect(lock["darwin-arm64"]).toBe(entry["darwin-arm64"]);
    expect(lock["darwin-x64"]).toBe(entry["darwin-x64"]);
  });
});
