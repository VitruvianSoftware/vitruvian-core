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

const REPO_ROOT = resolve(__dirname, "../../../../..");
const APP_CONFIG = resolve(REPO_ROOT, "backstage/app-config.yaml");
const GITOPS_VALUES = resolve(
  REPO_ROOT,
  "gitops/argocd/platform/backstage/values.yaml",
);
const CATALOG_FILES = [
  resolve(REPO_ROOT, "backstage/catalog-info.yaml"),
  resolve(REPO_ROOT, "gitops/catalog-info.yaml"),
  resolve(REPO_ROOT, "tabula/catalog-info.yaml"),
  resolve(REPO_ROOT, "oauth-user-inspector/catalog-info.yaml"),
  resolve(REPO_ROOT, "mcp-slack/catalog-info.yaml"),
];

const readYaml = (path: string): any => {
  const parsed = load(readFileSync(path, "utf8"));
  if (!parsed || typeof parsed !== "object") {
    throw new Error(`${path} did not parse to an object`);
  }
  return parsed;
};

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

const prometheusEndpointOf = (path: string): any =>
  findKey(readYaml(path), "proxy").endpoints["/prometheus/api"];

const jaegerEndpointOf = (path: string): any =>
  findKey(readYaml(path), "proxy").endpoints["/jaeger/api"];

const opentelemetryEndpointOf = (path: string): any =>
  findKey(readYaml(path), "proxy").endpoints["/opentelemetry/api"];

const configs: Array<[string, string]> = [
  ["repo app-config", APP_CONFIG],
  ["deployed gitops values", GITOPS_VALUES],
];

describe("proxy endpoint /prometheus/api", () => {
  it.each(configs)("is declared in the %s", (_label, path) => {
    expect(prometheusEndpointOf(path)).toBeDefined();
  });

  it.each(configs)("is GET-only in the %s", (_label, path) => {
    expect(prometheusEndpointOf(path).allowedMethods).toEqual(["GET"]);
  });

  it.each(configs)(
    "targets the in-cluster Thanos/Prometheus Service in the %s",
    (_label, path) => {
      expect(prometheusEndpointOf(path).target).toMatch(
        /^http:\/\/(thanos-query|prometheus-server)\.monitoring\.svc\.cluster\.local/,
      );
    },
  );

  it.each(configs)(
    "does not forward a browser-supplied Authorization header in the %s",
    (_label, path) => {
      const allowed: string[] = prometheusEndpointOf(path).allowedHeaders ?? [];
      expect(allowed.map((h) => h.toLowerCase())).not.toContain(
        "authorization",
      );
    },
  );

  it("does not drift between the repo config and the deployed config", () => {
    expect(prometheusEndpointOf(GITOPS_VALUES)).toEqual(
      prometheusEndpointOf(APP_CONFIG),
    );
  });
});

describe("proxy endpoints for OpenTelemetry / Jaeger / Tempo", () => {
  it.each(configs)("declares /jaeger/api in the %s", (_label, path) => {
    expect(jaegerEndpointOf(path)).toBeDefined();
    expect(jaegerEndpointOf(path).allowedMethods).toEqual(["GET"]);
    expect(jaegerEndpointOf(path).target).toMatch(
      /^http:\/\/tempo\.opentelemetry\.svc\.cluster\.local/,
    );
  });

  it.each(configs)("declares /opentelemetry/api in the %s", (_label, path) => {
    expect(opentelemetryEndpointOf(path)).toBeDefined();
    expect(opentelemetryEndpointOf(path).allowedMethods).toEqual(["GET"]);
    expect(opentelemetryEndpointOf(path).target).toMatch(
      /^http:\/\/tempo\.opentelemetry\.svc\.cluster\.local/,
    );
  });

  it("does not drift between repo config and deployed config for jaeger/tempo", () => {
    expect(jaegerEndpointOf(GITOPS_VALUES)).toEqual(
      jaegerEndpointOf(APP_CONFIG),
    );
    expect(opentelemetryEndpointOf(GITOPS_VALUES)).toEqual(
      opentelemetryEndpointOf(APP_CONFIG),
    );
  });
});

describe("observability catalog annotations", () => {
  const prometheusAnnotated: Array<[string, string, string]> = [];
  const otelAnnotated: Array<[string, string, string]> = [];
  const storybookAnnotated: Array<[string, string, string]> = [];

  for (const file of CATALOG_FILES) {
    for (const doc of loadAll(readFileSync(file, "utf8")) as any[]) {
      if (!doc?.metadata) continue;
      for (const [k, v] of Object.entries(doc.metadata.annotations ?? {})) {
        if (k.startsWith("prometheus.io/")) {
          prometheusAnnotated.push([doc.metadata.name, k, v as string]);
        }
        if (k.startsWith("opentelemetry.io/") || k.startsWith("otel.io/")) {
          otelAnnotated.push([doc.metadata.name, k, v as string]);
        }
        if (k.startsWith("storybook.io/") || k.startsWith("storybook/")) {
          storybookAnnotated.push([doc.metadata.name, k, v as string]);
        }
      }
    }
  }

  it("annotates entities with Prometheus annotations", () => {
    expect(prometheusAnnotated.length).toBeGreaterThan(0);
  });

  it("annotates entities with OpenTelemetry annotations", () => {
    expect(otelAnnotated.length).toBeGreaterThan(0);
  });

  it("annotates entities with Storybook annotations", () => {
    expect(storybookAnnotated.length).toBeGreaterThan(0);
  });
});
