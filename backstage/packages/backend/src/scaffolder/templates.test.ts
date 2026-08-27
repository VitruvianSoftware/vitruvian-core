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

describe("Scaffolder Software Templates", () => {
  const templates = [
    "backstage/templates/stamp-application/template.yaml",
    "backstage/templates/cloud-run-service/template.yaml",
    "backstage/templates/mcp-server/template.yaml",
    "backstage/templates/k8s-canary-microservice/template.yaml",
  ];

  it.each(templates)("validates template schema for %s", (relPath) => {
    const fullPath = resolve(REPO_ROOT, relPath);
    expect(existsSync(fullPath)).toBe(true);

    const content = readFileSync(fullPath, "utf8");
    const doc = load(content) as Record<string, any>;

    expect(doc.apiVersion).toBe("scaffolder.backstage.io/v1beta3");
    expect(doc.kind).toBe("Template");
    expect(doc.metadata?.name).toBeDefined();
    expect(doc.metadata?.title).toBeDefined();
    expect(doc.metadata?.description).toBeDefined();
    expect(doc.spec?.owner).toBeDefined();
    expect(doc.spec?.type).toBe("service");
    expect(Array.isArray(doc.spec?.parameters)).toBe(true);
    expect(Array.isArray(doc.spec?.steps)).toBe(true);
  });
});
