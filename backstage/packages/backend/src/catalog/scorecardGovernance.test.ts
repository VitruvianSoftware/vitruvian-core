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

import { existsSync, readFileSync } from "fs";
import { resolve } from "path";

import { load } from "js-yaml";

const REPO_ROOT = resolve(__dirname, "../../../../..");

describe("Service Maturity Scorecards & Governance", () => {
  const componentPaths = [
    "backstage/catalog-info.yaml",
    "tabula/catalog-info.yaml",
    "oauth-user-inspector/catalog-info.yaml",
    "devx/catalog-info.yaml",
    "homelab/catalog-info.yaml",
    "mcp-slack/catalog-info.yaml",
    "nexus-agent/catalog-info.yaml",
  ];

  it.each(componentPaths)(
    "satisfies Bronze Tier operational standards for %s",
    (relPath) => {
      const fullPath = resolve(REPO_ROOT, relPath);
      expect(existsSync(fullPath)).toBe(true);

      const content = readFileSync(fullPath, "utf8");
      const doc = load(content) as Record<string, any>;

      expect(doc.apiVersion).toBe("backstage.io/v1alpha1");
      expect(doc.kind).toBe("Component");
      expect(doc.metadata?.name).toBeDefined();
      expect(typeof doc.metadata?.description).toBe("string");
      expect(doc.metadata.description.length).toBeGreaterThan(10);
      expect(
        doc.metadata.annotations?.["backstage.io/techdocs-ref"],
      ).toBeDefined();
      expect(doc.spec?.owner).toBeDefined();
      expect(doc.spec?.lifecycle).toBe("production");
      expect(doc.spec?.system).toBeDefined();
    },
  );

  it.each(componentPaths)(
    "satisfies Silver Tier operational links for %s",
    (relPath) => {
      const fullPath = resolve(REPO_ROOT, relPath);
      const content = readFileSync(fullPath, "utf8");
      const doc = load(content) as Record<string, any>;

      expect(Array.isArray(doc.metadata?.links)).toBe(true);
      expect(doc.metadata.links.length).toBeGreaterThan(0);
      for (const link of doc.metadata.links) {
        expect(link.url).toMatch(/^https?:\/\//);
        expect(link.title).toBeDefined();
      }
    },
  );
});
