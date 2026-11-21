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

const EXPECTED_IGNORED_PLATFORM_BINARIES = [
  "@anthropic-ai/claude-agent-sdk-darwin-arm64",
  "@anthropic-ai/claude-agent-sdk-darwin-x64",
  "@anthropic-ai/claude-agent-sdk-linux-arm64",
  "@anthropic-ai/claude-agent-sdk-linux-arm64-musl",
  "@anthropic-ai/claude-agent-sdk-linux-x64",
  "@anthropic-ai/claude-agent-sdk-linux-x64-musl",
  "@anthropic-ai/claude-agent-sdk-win32-arm64",
  "@anthropic-ai/claude-agent-sdk-win32-x64",
] as const;

function stripQuotes(value: string): string {
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1);
  }
  return value;
}

function extractTopLevelBlock(yaml: string, blockName: string): string[] {
  const lines = yaml.split(/\r?\n/);
  const blockLines: string[] = [];
  let inBlock = false;

  for (const line of lines) {
    const trimmedStart = line.trimStart();
    if (trimmedStart.length === 0 || trimmedStart.startsWith("#")) {
      continue;
    }

    const isColumnZero = line.length > 0 && !/^\s/.test(line);
    if (isColumnZero) {
      if (line.trim() === `${blockName}:`) {
        inBlock = true;
        continue;
      }
      if (inBlock) {
        break;
      }
      continue;
    }

    if (inBlock) {
      blockLines.push(trimmedStart);
    }
  }

  return blockLines;
}

function parseRootCatalog(yaml: string): Set<string> {
  const names = new Set<string>();
  for (const line of extractTopLevelBlock(yaml, "catalog")) {
    const colonIdx = line.indexOf(":");
    if (colonIdx <= 0) {
      continue;
    }
    const rawKey = line.slice(0, colonIdx).trim();
    const afterColon = line.slice(colonIdx + 1).trim();
    if (afterColon.length === 0) {
      continue;
    }
    const cleanKey = stripQuotes(rawKey);
    if (cleanKey.length > 0) {
      names.add(cleanKey);
    }
  }
  return names;
}

function parseIgnoredOptionalDependencies(yaml: string): string[] {
  const entries: string[] = [];
  for (const line of extractTopLevelBlock(
    yaml,
    "ignoredOptionalDependencies",
  )) {
    const match = /^-\s+(.+)$/.exec(line);
    if (!match) {
      continue;
    }
    let raw = match[1].trim();
    if (raw.startsWith('"') || raw.startsWith("'")) {
      const quote = raw[0];
      const endIdx = raw.indexOf(quote, 1);
      if (endIdx > 1) {
        entries.push(raw.slice(1, endIdx));
      }
      continue;
    }
    const commentIdx = raw.search(/\s+#/);
    if (commentIdx >= 0) {
      raw = raw.slice(0, commentIdx).trim();
    }
    if (raw.length > 0) {
      entries.push(raw);
    }
  }
  return entries;
}

describe("claude-helper workspace configuration", () => {
  const workspaceYaml = readFileSync(
    path.join(REPO_ROOT, "pnpm-workspace.yaml"),
    "utf8",
  );
  const helperPackageJson = JSON.parse(
    readFileSync(path.join(HELPER_DIR, "package.json"), "utf8"),
  ) as {
    dependencies?: Record<string, string>;
    devDependencies?: Record<string, string>;
  };

  test("uses catalog: for every devDependency in the root catalog and exact pins for the rest", () => {
    const catalog = parseRootCatalog(workspaceYaml);
    expect(catalog.has("jest")).toBe(true);

    const devDependencies = helperPackageJson.devDependencies ?? {};
    expect(devDependencies.jest).toBe("catalog:");

    for (const [dep, specifier] of Object.entries(devDependencies)) {
      if (catalog.has(dep)) {
        expect({ dep, specifier }).toEqual({ dep, specifier: "catalog:" });
      } else {
        expect({ dep, specifier }).toEqual({
          dep,
          specifier: expect.stringMatching(/^\d+\.\d+\.\d+/),
        });
        expect(specifier).not.toMatch(/^[~^]/);
      }
    }
  });

  test("ignores all 8 Claude Agent SDK optional platform binaries in root pnpm-workspace.yaml", () => {
    const ignored = parseIgnoredOptionalDependencies(workspaceYaml);
    for (const pkg of EXPECTED_IGNORED_PLATFORM_BINARIES) {
      expect(ignored).toContain(pkg);
    }
  });
});
