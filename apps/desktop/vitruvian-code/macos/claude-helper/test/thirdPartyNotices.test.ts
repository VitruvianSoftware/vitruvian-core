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
const APP_DIR = path.resolve(HELPER_DIR, "..", "..");

interface BundledPackage {
  readonly name: string;
  readonly version: string;
  readonly license: string;
}

const ANTHROPIC_SDK_NOTICE =
  "© Anthropic PBC. All rights reserved. Use is subject to the Legal Agreements outlined here: https://code.claude.com/docs/en/legal-and-compliance.";

function extractSection(
  markdown: string,
  headingPrefix: string,
  heading: string,
): string | null {
  const lines = markdown.split(/\r?\n/);
  const target = `${headingPrefix} ${heading}`;
  const startIdx = lines.findIndex((l) => l.trim() === target);
  if (startIdx < 0) {
    return null;
  }
  let endIdx = lines.length;
  for (let i = startIdx + 1; i < lines.length; i += 1) {
    const trimmed = lines[i].trim();
    if (headingPrefix === "##") {
      if (/^##\s+/.test(trimmed)) {
        endIdx = i;
        break;
      }
    } else if (/^#{2,3}\s+/.test(trimmed)) {
      endIdx = i;
      break;
    }
  }
  return lines.slice(startIdx + 1, endIdx).join("\n");
}

function extractCodeBlocks(section: string): string[] {
  const blocks: string[] = [];
  const regex = /```[^\n]*\n([\s\S]*?)```/g;
  for (const match of section.matchAll(regex)) {
    const body = match[1].trim();
    if (body.length > 0) {
      blocks.push(body);
    }
  }
  return blocks;
}

export function validateThirdPartyNotices(params: {
  readonly noticesMarkdown: string;
  readonly packages: readonly BundledPackage[];
  readonly nodeVersion: string;
}): string[] {
  const problems: string[] = [];

  const nodeSection = extractSection(params.noticesMarkdown, "##", "Node.js");
  if (!nodeSection) {
    problems.push("THIRD_PARTY_NOTICES.md is missing a `## Node.js` section");
  } else {
    if (!nodeSection.includes(params.nodeVersion)) {
      problems.push(
        `THIRD_PARTY_NOTICES.md ## Node.js does not mention version ${params.nodeVersion}`,
      );
    }
    const nodeCodeBlocks = extractCodeBlocks(nodeSection);
    if (
      !nodeCodeBlocks.some((b) => b.includes("Copyright Node.js contributors"))
    ) {
      problems.push(
        "THIRD_PARTY_NOTICES.md ## Node.js is missing the Node.js MIT license text",
      );
    }
  }

  for (const pkg of params.packages) {
    const section = extractSection(params.noticesMarkdown, "###", pkg.name);
    if (!section) {
      problems.push(
        `THIRD_PARTY_NOTICES.md is missing a \`### ${pkg.name}\` notice section`,
      );
      continue;
    }
    if (!section.includes(pkg.version)) {
      problems.push(
        `THIRD_PARTY_NOTICES.md ### ${pkg.name} does not mention version ${pkg.version}`,
      );
    }
    const blocks = extractCodeBlocks(section);
    const hasNoticeBlock = blocks.some((b) => b.length >= 30);
    if (!hasNoticeBlock) {
      problems.push(
        `THIRD_PARTY_NOTICES.md ### ${pkg.name} is missing a verbatim license/notice text block`,
      );
    }

    // T3 third-party-licenses rule: reject UNLICENSED / proprietary / unknown
    // packages unless an explicit non-empty license notice block is provided.
    const normalizedLicense = pkg.license.trim();
    const isRestrictedOrCustom =
      normalizedLicense.length === 0 ||
      /^(unlicensed|proprietary|unknown)$/i.test(normalizedLicense) ||
      /^see license in /i.test(normalizedLicense);
    if (isRestrictedOrCustom && !hasNoticeBlock) {
      problems.push(
        `Package ${pkg.name}@${pkg.version} declares ${normalizedLicense || "empty"} without a notice in THIRD_PARTY_NOTICES.md`,
      );
    }

    if (pkg.name === "@anthropic-ai/claude-agent-sdk") {
      if (!section.includes(ANTHROPIC_SDK_NOTICE)) {
        problems.push(
          "THIRD_PARTY_NOTICES.md ### @anthropic-ai/claude-agent-sdk must include the SDK's LICENSE.md notice verbatim",
        );
      }
    }
  }

  return problems;
}

function readNodeLockVersion(): string {
  const raw = readFileSync(path.join(HELPER_DIR, "node.lock"), "utf8");
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (trimmed.startsWith("version=")) {
      return trimmed.slice("version=".length).trim();
    }
  }
  throw new Error("node.lock is missing version=");
}

describe("THIRD_PARTY_NOTICES.md completeness", () => {
  test("covers Node.js and every package in bundle/packages.json", () => {
    const noticesMarkdown = readFileSync(
      path.join(APP_DIR, "THIRD_PARTY_NOTICES.md"),
      "utf8",
    );
    const manifest = JSON.parse(
      readFileSync(path.join(HELPER_DIR, "bundle", "packages.json"), "utf8"),
    ) as { packages: BundledPackage[] };
    const nodeVersion = readNodeLockVersion();

    const problems = validateThirdPartyNotices({
      noticesMarkdown,
      packages: manifest.packages,
      nodeVersion,
    });
    expect(problems).toEqual([]);
  });

  test("validator fails when a package notice is missing or UNLICENSED/proprietary lacks a notice", () => {
    const noticesMarkdown = readFileSync(
      path.join(APP_DIR, "THIRD_PARTY_NOTICES.md"),
      "utf8",
    );
    const nodeVersion = readNodeLockVersion();

    const missingNoticeProblems = validateThirdPartyNotices({
      noticesMarkdown,
      packages: [{ name: "missing-pkg", version: "1.2.3", license: "MIT" }],
      nodeVersion,
    });
    expect(missingNoticeProblems.length).toBeGreaterThan(0);

    for (const badLicense of ["UNLICENSED", "proprietary"]) {
      const restrictedProblems = validateThirdPartyNotices({
        noticesMarkdown: `${noticesMarkdown}\n\n### custom-pkg\n\n- **Version:** \`1.0.0\`\n- **Licence:** \`${badLicense}\`\n`,
        packages: [
          { name: "custom-pkg", version: "1.0.0", license: badLicense },
        ],
        nodeVersion,
      });
      expect(restrictedProblems.length).toBeGreaterThan(0);
    }
  });
});
