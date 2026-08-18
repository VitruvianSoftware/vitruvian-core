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

import { readFileSync } from "fs";
import { resolve } from "path";
import { load } from "js-yaml";

// Guards two things that are invisible at review time and only fail in
// production.
//
// 1. The single-org invariant. The module sets alwaysUseDefaultNamespace only
//    when there is exactly one definition with exactly one org. With two orgs
//    it namespaces entities per-org -- group:vitruviansoftware/tabula-team
//    instead of group:default/tabula-team -- and every `owner:` reference in
//    the catalog silently stops resolving.
//
// 2. Drift between the repo config and the deployed config. The container runs
//    the ConfigMap the Helm values render, NOT backstage/app-config.yaml, so a
//    provider added to only one file looks correct in review and does nothing
//    (or nothing in production). That drift has already caused two incidents.

const REPO_ROOT = resolve(__dirname, "../../../../..");
const APP_CONFIG = resolve(REPO_ROOT, "backstage/app-config.yaml");
const GITOPS_VALUES = resolve(
  REPO_ROOT,
  "gitops/argocd/platform/backstage/values.yaml",
);

type GithubOrgConfig = {
  id: string;
  githubUrl: string;
  orgs?: string[];
  schedule?: Record<string, unknown>;
};

const readYaml = (path: string): any => {
  const parsed = load(readFileSync(path, "utf8"));
  if (!parsed || typeof parsed !== "object") {
    throw new Error(`${path} did not parse to an object`);
  }
  return parsed;
};

// The chart nests the whole app-config under `backstage.appConfig`; the repo
// file is the app-config itself. Find the catalog block either way rather than
// hard-coding a path that a chart upgrade could move.
const findCatalog = (root: any): any => {
  const stack = [root];
  while (stack.length) {
    const node = stack.pop();
    if (!node || typeof node !== "object") continue;
    if (node.catalog && typeof node.catalog === "object") return node.catalog;
    stack.push(...Object.values(node));
  }
  throw new Error("no catalog block found");
};

const githubOrgOf = (path: string): GithubOrgConfig => {
  const providers = findCatalog(readYaml(path)).providers;
  expect(providers).toBeDefined();
  return providers.githubOrg;
};

describe("catalog.providers.githubOrg", () => {
  const configs: Array<[string, string]> = [
    ["repo app-config", APP_CONFIG],
    ["deployed gitops values", GITOPS_VALUES],
  ];

  it.each(configs)("is declared in the %s", (_label, path) => {
    expect(githubOrgOf(path)).toBeDefined();
  });

  it.each(configs)(
    "declares exactly one org in the %s, so entities stay in the default namespace",
    (_label, path) => {
      const cfg = githubOrgOf(path);
      // An array of definitions would also defeat alwaysUseDefaultNamespace.
      expect(Array.isArray(cfg)).toBe(false);
      expect(cfg.orgs).toEqual(["VitruvianSoftware"]);
    },
  );

  it.each(configs)("carries the required fields in the %s", (_label, path) => {
    const cfg = githubOrgOf(path);
    expect(typeof cfg.id).toBe("string");
    expect(cfg.githubUrl).toBe("https://github.com");
    // readSchedulerServiceTaskScheduleDefinitionFromConfig throws at startup
    // without this, which fails the whole backend, not just the provider.
    expect(cfg.schedule).toBeDefined();
  });

  it("does not drift between the repo config and the deployed config", () => {
    expect(githubOrgOf(GITOPS_VALUES)).toEqual(githubOrgOf(APP_CONFIG));
  });
});
