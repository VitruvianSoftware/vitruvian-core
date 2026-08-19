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

import { createBackend } from "@backstage/backend-defaults";

import { authModuleGithubOrgProvider } from "./auth/module";
import { permissionModuleVitruvianPolicy } from "./permissions/module";
import { cloudRunPlugin } from "./cloudRun/plugin";

const backend = createBackend();

backend.add(import("@backstage/plugin-app-backend"));
backend.add(import("@backstage/plugin-proxy-backend"));
backend.add(import("@backstage/plugin-scaffolder-backend"));
// Supplies publish:github (plus github:repo:create and friends). Without it the
// generated bazel-* templates fail mid-run: fetch:template renders the project
// into a temp dir, then the "Create GitHub repo" step aborts with an unknown
// action and catalog:register never happens.
backend.add(import("@backstage/plugin-scaffolder-backend-module-github"));
backend.add(import("@backstage/plugin-techdocs-backend"));

// Auth plugin & providers
// GitHub SSO only — the guest provider is deliberately absent because this
// portal is internet-facing and anonymous sign-in exposed the whole catalog.
backend.add(import("@backstage/plugin-auth-backend"));
// Replaces the stock GitHub provider with one that also proves active
// membership of the GitHub org, using the signing-in user's own token.
backend.add(authModuleGithubOrgProvider);

// Catalog plugin & modules
backend.add(import("@backstage/plugin-catalog-backend"));
backend.add(
  import("@backstage/plugin-catalog-backend-module-scaffolder-entity-model"),
);
backend.add(import("@backstage/plugin-catalog-backend-module-github"));
// Ingests VitruvianSoftware members and teams as User/Group entities, replacing
// the hand-maintained copies in catalog-info.yaml. GitHub already mirrors them
// exactly -- seven teams whose slugs match the declared group names, with
// ipv1337 in all seven -- so every `owner:` reference keeps resolving.
//
// Lands with the hand-declared entities still in place, on purpose. The sign-in
// resolver ends in signInWithCatalogUser, so a User entity that fails to appear
// is not a degraded catalog, it is nobody being able to sign in. The duplicates
// are removed in a follow-up once ingestion is observed working.
backend.add(import("@backstage/plugin-catalog-backend-module-github-org"));

// Permissions — the Vitruvian policy replaces the upstream allow-all reference
// policy. Requires `permission.enabled: true` in app-config to be consulted.
backend.add(import("@backstage/plugin-permission-backend"));
backend.add(permissionModuleVitruvianPolicy);

// Search
// Kubernetes: surfaces live workload state (pods, health, images, events) on the
// entity page. Authenticates with Backstage's OWN in-cluster ServiceAccount
// token, so there is no credential to store or rotate -- see the read-only
// ClusterRole in gitops/argocd/platform/backstage/rbac.yaml.
backend.add(import("@backstage/plugin-kubernetes-backend"));

// Cloud Run status for the apps that do NOT run in this cluster (tabula,
// oauth-user-inspector). The Kubernetes plugin above covers the ones that do.
backend.add(cloudRunPlugin);

backend.add(import("@backstage/plugin-search-backend"));
backend.add(import("@backstage/plugin-search-backend-module-catalog"));
backend.add(import("@backstage/plugin-search-backend-module-techdocs"));

backend.start();
