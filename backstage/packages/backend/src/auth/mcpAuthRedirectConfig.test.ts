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

// Guards against drift between backstage/app-config.yaml and the deployed gitops
// Helm values (gitops/argocd/platform/backstage/values.yaml) for MCP OAuth dynamic
// client registration and client ID metadata documents.
//
// In particular, verifies that localhost and 127.0.0.1 redirect URI patterns include
// recursive wildcard subpaths ('http://localhost:*/**' and 'http://127.0.0.1:*/**') so
// that CLI tools like mcp-remote using ephemeral callback ports with subpaths
// (e.g. 'http://localhost:15466/oauth/callback') are accepted.

const REPO_ROOT = resolve(__dirname, "../../../../..");
const APP_CONFIG = resolve(REPO_ROOT, "backstage/app-config.yaml");
const GITOPS_VALUES = resolve(
  REPO_ROOT,
  "gitops/argocd/platform/backstage/values.yaml",
);

const readYaml = (path: string): any => {
  const parsed = load(readFileSync(path, "utf8"));
  if (!parsed || typeof parsed !== "object") {
    throw new Error(`${path} did not parse to an object`);
  }
  return parsed;
};

describe("MCP auth & redirect URI configuration parity", () => {
  const appConfig = readYaml(APP_CONFIG);
  const gitopsValues = readYaml(GITOPS_VALUES);

  const appAuthConfig = appConfig.auth;
  const deployedAuthConfig = gitopsValues.backstage.appConfig.auth;

  it("enables experimentalRefreshToken in both app-config and gitops values", () => {
    expect(appAuthConfig.experimentalRefreshToken?.enabled).toBe(true);
    expect(deployedAuthConfig.experimentalRefreshToken?.enabled).toBe(true);
  });

  it("enables clientIdMetadataDocuments in both app-config and gitops values", () => {
    expect(appAuthConfig.clientIdMetadataDocuments?.enabled).toBe(true);
    expect(deployedAuthConfig.clientIdMetadataDocuments?.enabled).toBe(true);
  });

  it("enables experimentalDynamicClientRegistration in both app-config and gitops values", () => {
    expect(appAuthConfig.experimentalDynamicClientRegistration?.enabled).toBe(
      true,
    );
    expect(
      deployedAuthConfig.experimentalDynamicClientRegistration?.enabled,
    ).toBe(true);
  });

  it("includes recursive localhost and 127.0.0.1 redirect URI patterns in app-config", () => {
    const cimdRedirects: string[] =
      appAuthConfig.clientIdMetadataDocuments.allowedRedirectUriPatterns;
    const dcrRedirects: string[] =
      appAuthConfig.experimentalDynamicClientRegistration
        .allowedRedirectUriPatterns;

    expect(cimdRedirects).toContain("http://localhost:*/**");
    expect(cimdRedirects).toContain("http://127.0.0.1:*/**");
    expect(dcrRedirects).toContain("http://localhost:*/**");
    expect(dcrRedirects).toContain("http://127.0.0.1:*/**");
  });

  it("includes recursive localhost and 127.0.0.1 redirect URI patterns in gitops values", () => {
    const cimdRedirects: string[] =
      deployedAuthConfig.clientIdMetadataDocuments.allowedRedirectUriPatterns;
    const dcrRedirects: string[] =
      deployedAuthConfig.experimentalDynamicClientRegistration
        .allowedRedirectUriPatterns;

    expect(cimdRedirects).toContain("http://localhost:*/**");
    expect(cimdRedirects).toContain("http://127.0.0.1:*/**");
    expect(dcrRedirects).toContain("http://localhost:*/**");
    expect(dcrRedirects).toContain("http://127.0.0.1:*/**");
  });

  it("has exact parity between app-config and gitops values for allowedRedirectUriPatterns", () => {
    expect(
      deployedAuthConfig.clientIdMetadataDocuments.allowedRedirectUriPatterns,
    ).toEqual(
      appAuthConfig.clientIdMetadataDocuments.allowedRedirectUriPatterns,
    );
    expect(
      deployedAuthConfig.experimentalDynamicClientRegistration
        .allowedRedirectUriPatterns,
    ).toEqual(
      appAuthConfig.experimentalDynamicClientRegistration
        .allowedRedirectUriPatterns,
    );
  });
});
