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
import { load, loadAll } from "js-yaml";

// The ArgoCD cards reach ArgoCD through the backend proxy, which means the
// security properties of this integration live entirely in YAML -- there is no
// code to review. These assertions pin the four that matter:
//
//  1. The endpoint exists in BOTH configs. The container runs the ConfigMap the
//     Helm values render, not backstage/app-config.yaml, so an endpoint added to
//     only one file reads as correct and does nothing in production. That drift
//     has caused incidents twice (githubOrg, and the CSP connect-src fix).
//  2. It is GET-only. The proxy holds a bearer token; if it forwarded POST/DELETE
//     then any portal user could sync or delete an Application through it,
//     regardless of what that token's own RBAC allows.
//  3. It targets the in-cluster Service, not the public ingress -- keeping the
//     token's traffic off the internet and independent of DNS/TLS.
//  4. It never forwards a browser-supplied Authorization header, which would let
//     a caller substitute their own credential.
//
// Also guards the annotation keys, because a typo like `argocd/app_name` is
// silently inert: isArgocdAvailable just returns false and the card never
// renders, with nothing logged anywhere.

const REPO_ROOT = resolve(__dirname, "../../../../..");
const APP_CONFIG = resolve(REPO_ROOT, "backstage/app-config.yaml");
const GITOPS_VALUES = resolve(
  REPO_ROOT,
  "gitops/argocd/platform/backstage/values.yaml",
);
const CATALOG_FILES = [
  resolve(REPO_ROOT, "backstage/catalog-info.yaml"),
  resolve(REPO_ROOT, "gitops/catalog-info.yaml"),
];

// Mirrors the constants exported by @roadiehq/backstage-plugin-argo-cd
// (ARGOCD_ANNOTATION_*). Hard-coded rather than imported: that is a frontend
// package and pulling it into the backend's node test environment drags in React.
const VALID_ARGOCD_ANNOTATIONS = new Set([
  "argocd/app-name",
  "argocd/app-selector",
  "argocd/app-namespace",
  "argocd/project-name",
  "argocd/proxy-url",
]);

const readYaml = (path: string): any => {
  const parsed = load(readFileSync(path, "utf8"));
  if (!parsed || typeof parsed !== "object") {
    throw new Error(`${path} did not parse to an object`);
  }
  return parsed;
};

// The chart nests the app-config under `backstage.appConfig`; the repo file is
// the app-config itself. Search for the block rather than hard-coding a path a
// chart upgrade could move (same approach as githubOrgProviderConfig.test.ts).
const findKey = (root: any, key: string): any => {
  const stack = [root];
  while (stack.length) {
    const node = stack.pop();
    if (!node || typeof node !== "object") continue;
    if (node[key] && typeof node[key] === "object") return node[key];
    stack.push(...Object.values(node));
  }
  throw new Error(`no '${key}' block found`);
};

const argocdEndpointOf = (path: string): any =>
  findKey(readYaml(path), "proxy").endpoints["/argocd/api"];

const configs: Array<[string, string]> = [
  ["repo app-config", APP_CONFIG],
  ["deployed gitops values", GITOPS_VALUES],
];

describe("proxy endpoint /argocd/api", () => {
  it.each(configs)("is declared in the %s", (_label, path) => {
    expect(argocdEndpointOf(path)).toBeDefined();
  });

  it.each(configs)(
    "is GET-only in the %s, so the proxy's token cannot be used to mutate",
    (_label, path) => {
      expect(argocdEndpointOf(path).allowedMethods).toEqual(["GET"]);
    },
  );

  it.each(configs)(
    "targets the in-cluster Service in the %s, not the public ingress",
    (_label, path) => {
      expect(argocdEndpointOf(path).target).toBe(
        "http://argocd-server.argocd.svc.cluster.local",
      );
    },
  );

  it.each(configs)(
    "does not forward a browser-supplied Authorization header in the %s",
    (_label, path) => {
      const allowed: string[] = argocdEndpointOf(path).allowedHeaders ?? [];
      expect(allowed.map((h) => h.toLowerCase())).not.toContain(
        "authorization",
      );
    },
  );

  it.each(configs)(
    "authenticates with the ARGOCD_TOKEN env var in the %s",
    (_label, path) => {
      expect(argocdEndpointOf(path).headers.Authorization).toBe(
        "Bearer ${ARGOCD_TOKEN}",
      );
    },
  );

  it("does not drift between the repo config and the deployed config", () => {
    expect(argocdEndpointOf(GITOPS_VALUES)).toEqual(
      argocdEndpointOf(APP_CONFIG),
    );
  });

  it.each(configs)("declares argocd.baseUrl in the %s", (_label, path) => {
    expect(findKey(readYaml(path), "argocd").baseUrl).toBe(
      "https://argocd.lab.ipv1337.dev",
    );
  });
});

describe("ARGOCD_TOKEN wiring", () => {
  // A proxy header referencing ${ARGOCD_TOKEN} is inert unless the deployment
  // actually supplies that variable -- Backstage substitutes an empty string and
  // ArgoCD answers 401, which surfaces only as a broken card at runtime.
  const env = (readYaml(GITOPS_VALUES) as any).backstage.extraEnvVars.find(
    (e: any) => e.name === "ARGOCD_TOKEN",
  );

  it("is supplied to the container", () => {
    expect(env).toBeDefined();
    expect(env.valueFrom.secretKeyRef).toMatchObject({
      name: "argocd-backstage-token",
      key: "ARGOCD_TOKEN",
    });
  });

  it("is optional, so a missing secret degrades the cards instead of blocking startup", () => {
    // Without this the pod sits in CreateContainerConfigError and the entire
    // portal is down -- and the token is necessarily absent until it is minted
    // against a role that only exists after this change ships.
    expect(env.valueFrom.secretKeyRef.optional).toBe(true);
  });
});

describe("catalog argocd/* annotations", () => {
  const annotated: Array<[string, string, string]> = [];
  for (const file of CATALOG_FILES) {
    for (const doc of loadAll(readFileSync(file, "utf8")) as any[]) {
      if (!doc?.metadata) continue;
      for (const [k, v] of Object.entries(doc.metadata.annotations ?? {})) {
        if (k.startsWith("argocd/")) {
          annotated.push([doc.metadata.name, k, v as string]);
        }
      }
    }
  }

  it("annotates at least one entity", () => {
    expect(annotated.length).toBeGreaterThan(0);
  });

  it.each(annotated)(
    "%s uses a recognised annotation key (%s)",
    (_name, key, _value) => {
      expect(VALID_ARGOCD_ANNOTATIONS.has(key)).toBe(true);
    },
  );

  it.each(annotated)("%s has a non-empty %s", (_name, _key, value) => {
    expect(value.trim()).not.toBe("");
  });

  it.each(annotated.filter(([, k]) => k === "argocd/app-selector"))(
    "%s declares %s as a k=v label selector",
    (_name, _key, value) => {
      expect(value).toMatch(/^[^=,\s]+=[^=,\s]+$/);
    },
  );
});
