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

/**
 * Pins the three-way agreement that makes keyless GCP auth work.
 *
 * The audience, the token path and the credentials path are written in FOUR
 * places across three files, and every mismatch fails the same way: an opaque
 * 400 from STS at request time, long after deploy, with nothing in the
 * manifests looking wrong. Nothing else in CI compares them.
 *
 * See docs/gcp-cluster-federation.md.
 */
const REPO_ROOT = resolve(__dirname, "../../../../..");
const BOOTSTRAP_CONFIG = resolve(
  REPO_ROOT,
  "infrastructure/pulumi/foundation/gcp-bootstrap/Pulumi.production.yaml",
);
const GITOPS_VALUES = resolve(
  REPO_ROOT,
  "gitops/argocd/platform/backstage/values.yaml",
);
const ADC_CONFIGMAP = resolve(
  REPO_ROOT,
  "gitops/argocd/platform/backstage/gcp-adc-configmap.yaml",
);

const readYaml = (p: string) => load(readFileSync(p, "utf8")) as any;

describe("keyless GCP credentials wiring", () => {
  const bootstrap = readYaml(BOOTSTRAP_CONFIG).config;
  const backstage = readYaml(GITOPS_VALUES).backstage;
  const configMap = readYaml(ADC_CONFIGMAP);
  const creds = JSON.parse(configMap.data["credentials.json"]);

  const tokenVolume = backstage.extraVolumes.find(
    (v: any) => v.name === "gcp-workload-identity-token",
  );
  const tokenMount = backstage.extraVolumeMounts.find(
    (m: any) => m.name === "gcp-workload-identity-token",
  );
  const configMount = backstage.extraVolumeMounts.find(
    (m: any) => m.name === "gcp-workload-identity-config",
  );

  it("the projected token audience matches the WIF provider's allowed audience", () => {
    const projected =
      tokenVolume.projected.sources[0].serviceAccountToken.audience;
    expect(projected).toBe(bootstrap["foundation-bootstrap:cluster_audience"]);
  });

  it("credential_source.file is where the token volume is actually mounted", () => {
    const path = tokenVolume.projected.sources[0].serviceAccountToken.path;
    expect(creds.credential_source.file).toBe(
      `${tokenMount.mountPath}/${path}`,
    );
  });

  it("GOOGLE_APPLICATION_CREDENTIALS points into the mounted ConfigMap", () => {
    const env = backstage.extraEnvVars.find(
      (e: any) => e.name === "GOOGLE_APPLICATION_CREDENTIALS",
    );
    expect(env.value).toBe(`${configMount.mountPath}/credentials.json`);
    // The key inside the ConfigMap must match the file name it is mounted as.
    expect(Object.keys(configMap.data)).toContain("credentials.json");
  });

  it("the STS audience names the pool and provider the bootstrap stack builds", () => {
    // Not a literal-string assertion: the ids are configurable, so read them.
    const pool =
      bootstrap["foundation-bootstrap:cluster_pool_id"] ??
      "homelab-cluster-pool";
    const provider =
      bootstrap["foundation-bootstrap:cluster_provider_id"] ??
      "homelab-cluster-provider";
    expect(creds.audience).toContain(`/workloadIdentityPools/${pool}`);
    expect(creds.audience).toContain(`/providers/${provider}`);
  });

  it("impersonates the service account the bootstrap stack creates", () => {
    const sa =
      bootstrap["foundation-bootstrap:cluster_sa_id"] ?? "sa-homelab-cluster";
    expect(creds.service_account_impersonation_url).toContain(`${sa}@`);
  });

  it("holds no key material -- it is a recipe, not a secret", () => {
    expect(creds.type).toBe("external_account");
    expect(JSON.stringify(creds)).not.toMatch(
      /private_key|BEGIN [A-Z ]*PRIVATE KEY/,
    );
    expect(configMap.kind).toBe("ConfigMap");
  });
});
