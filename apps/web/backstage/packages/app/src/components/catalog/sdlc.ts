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

import type { Entity } from "@backstage/catalog-model";

export const RELEASE_MODEL_ANNOTATION = "vitruvian.dev/release-model";
export const ENVIRONMENTS_ANNOTATION = "vitruvian.dev/environments";
export const DEPLOY_WORKFLOW_ANNOTATION = "vitruvian.dev/deploy-workflow";
export const RELEASE_WORKFLOW_ANNOTATION = "vitruvian.dev/release-workflow";
export const DEPLOY_TARGETS_ANNOTATION = "vitruvian.dev/deploy-targets";
export const MIRROR_ANNOTATION = "vitruvian.dev/mirror";

export type SdlcReleaseStrategy = {
  key: string;
  label: string;
  description: string;
  category: "cloud-run" | "gitops" | "release-please" | "custom";
};

const STRATEGY_DEFINITIONS: Record<string, Omit<SdlcReleaseStrategy, "key">> = {
  "continuous-deploy": {
    label: "Continuous Delivery (Cloud Run)",
    description:
      "Automated container builds, multi-environment promotion ladder, and blue-green revision traffic splitting.",
    category: "cloud-run",
  },
  "gitops-argocd": {
    label: "GitOps Continuous Deployment (ArgoCD)",
    description:
      "Declarative cluster reconciliation via ArgoCD with automated image updater write-back to values.yaml.",
    category: "gitops",
  },
  "gitops-helm": {
    label: "GitOps Helm Release (ArgoCD)",
    description:
      "Helm chart deployment reconciled by ArgoCD in the homelab k3s cluster.",
    category: "gitops",
  },
  "gitops-argo-rollouts": {
    label: "Argo Rollouts Progressive Delivery",
    description:
      "Canary rollouts with metric AnalysisTemplates and automated rollback on regression.",
    category: "gitops",
  },
  goreleaser: {
    label: "GoReleaser Cross-Platform Binaries",
    description:
      "Multi-architecture binary compilation and distribution via GitHub Releases on semantic tag pushes.",
    category: "release-please",
  },
  "npm-publish": {
    label: "npm Registry Distribution",
    description:
      "Automated semantic versioning, packaging, and npm registry publishing.",
    category: "release-please",
  },
  "dmg-github-releases": {
    label: "macOS DMG Release Package",
    description:
      "Signed macOS application bundling and asset attachment to GitHub Releases.",
    category: "release-please",
  },
};

export type SdlcInfo = {
  releaseModels: SdlcReleaseStrategy[];
  environments: string[];
  workflow?: { name: string; type: "deploy" | "release" };
  deployTargets: string[];
  mirror?: string;
};

export function readSdlcInfo(entity: Entity): SdlcInfo | undefined {
  const annotations = entity.metadata.annotations ?? {};
  const rawReleaseModel = annotations[RELEASE_MODEL_ANNOTATION];
  const rawEnvironments = annotations[ENVIRONMENTS_ANNOTATION];
  const deployWorkflow = annotations[DEPLOY_WORKFLOW_ANNOTATION];
  const releaseWorkflow = annotations[RELEASE_WORKFLOW_ANNOTATION];
  const rawTargets = annotations[DEPLOY_TARGETS_ANNOTATION];
  const mirror = annotations[MIRROR_ANNOTATION];

  if (
    !rawReleaseModel &&
    !rawEnvironments &&
    !deployWorkflow &&
    !releaseWorkflow &&
    !rawTargets &&
    !mirror
  ) {
    return undefined;
  }

  const releaseKeys = rawReleaseModel
    ? rawReleaseModel.split(/\s+/).filter(Boolean)
    : [];

  const releaseModels: SdlcReleaseStrategy[] = releaseKeys.map((key) => {
    const found = STRATEGY_DEFINITIONS[key];
    if (found) {
      return { key, ...found };
    }
    return {
      key,
      label: key,
      description: "Custom delivery or packaging strategy.",
      category: "custom",
    };
  });

  const environments = rawEnvironments
    ? rawEnvironments.split(/\s+/).filter(Boolean)
    : [];

  const deployTargets = rawTargets
    ? rawTargets.split(/\s+/).filter(Boolean)
    : [];

  let workflow: SdlcInfo["workflow"] | undefined;
  if (deployWorkflow) {
    workflow = { name: deployWorkflow, type: "deploy" };
  } else if (releaseWorkflow) {
    workflow = { name: releaseWorkflow, type: "release" };
  }

  return {
    releaseModels,
    environments,
    workflow,
    deployTargets,
    mirror,
  };
}

export function isSdlcAvailable(entity: Entity): boolean {
  return readSdlcInfo(entity) !== undefined;
}
