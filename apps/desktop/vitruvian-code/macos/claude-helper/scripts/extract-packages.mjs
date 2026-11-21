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

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

const FORBIDDEN_PLATFORM_SDK_PREFIX = "@anthropic-ai/claude-agent-sdk-";

function extractLicense(pkg) {
  if (typeof pkg.license === "string" && pkg.license.trim().length > 0) {
    return pkg.license.trim();
  }
  if (
    pkg.license &&
    typeof pkg.license === "object" &&
    typeof pkg.license.type === "string" &&
    pkg.license.type.trim().length > 0
  ) {
    return pkg.license.type.trim();
  }
  return "UNKNOWN";
}

function findEnclosingPackageJson(startFile) {
  let dir = path.dirname(path.resolve(process.cwd(), startFile));
  while (true) {
    if (path.basename(dir) === "node_modules") {
      return null;
    }
    const candidate = path.join(dir, "package.json");
    if (existsSync(candidate)) {
      const parsed = JSON.parse(readFileSync(candidate, "utf8"));
      if (
        typeof parsed.name === "string" &&
        parsed.name.trim().length > 0 &&
        typeof parsed.version === "string" &&
        parsed.version.trim().length > 0
      ) {
        return {
          name: parsed.name.trim(),
          version: parsed.version.trim(),
          license: extractLicense(parsed),
        };
      }
    }
    const parent = path.dirname(dir);
    if (parent === dir) {
      return null;
    }
    dir = parent;
  }
}

function comparePackages(a, b) {
  if (a.name < b.name) return -1;
  if (a.name > b.name) return 1;
  if (a.version < b.version) return -1;
  if (a.version > b.version) return 1;
  return 0;
}

function main() {
  const [metafilePath, outputPath] = process.argv.slice(2);
  if (!metafilePath || !outputPath) {
    throw new Error(
      "Usage: extract-packages.mjs <metafile-path> <output-packages-json-path>",
    );
  }

  const metafile = JSON.parse(readFileSync(metafilePath, "utf8"));
  const inputs = Object.keys(metafile.inputs ?? {});
  const byKey = new Map();

  for (const inputPath of inputs) {
    const segments = inputPath.split(/[\\/]/);
    if (!segments.includes("node_modules")) {
      continue;
    }
    const info = findEnclosingPackageJson(inputPath);
    if (!info) {
      throw new Error(
        `Could not resolve package.json with name and version for bundled input: ${inputPath}`,
      );
    }
    if (info.name.startsWith(FORBIDDEN_PLATFORM_SDK_PREFIX)) {
      throw new Error(
        `Forbidden Claude Agent SDK platform package bundled: ${info.name}@${info.version}`,
      );
    }
    byKey.set(`${info.name}@${info.version}`, info);
  }

  if (byKey.size === 0) {
    throw new Error(
      `No npm packages found in esbuild metafile inputs (${metafilePath})`,
    );
  }

  const packages = Array.from(byKey.values()).sort(comparePackages);
  mkdirSync(path.dirname(path.resolve(outputPath)), { recursive: true });
  writeFileSync(
    outputPath,
    `${JSON.stringify({ packages }, null, 2)}\n`,
    "utf8",
  );
}

main();
