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

export type MaturityTier = "Gold" | "Silver" | "Bronze" | "Incomplete";

export type ScorecardCheck = {
  id: string;
  title: string;
  tier: "Bronze" | "Silver" | "Gold";
  passed: boolean;
  message?: string;
};

export type ScorecardResult = {
  tier: MaturityTier;
  scorePercent: number;
  checks: ScorecardCheck[];
  nextSteps: string[];
};

export function evaluateScorecard(entity: Entity): ScorecardResult {
  const spec = entity.spec as Record<string, any> | undefined;
  const metadata = entity.metadata;
  const annotations = metadata.annotations ?? {};
  const links = (metadata.links ?? []) as Array<{
    url: string;
    title?: string;
  }>;

  // --- BRONZE CRITERIA ---
  const hasOwner = Boolean(spec?.owner);
  const hasLifecycle = Boolean(spec?.lifecycle);
  const hasSystem = Boolean(spec?.system);
  const hasDescription =
    typeof metadata.description === "string" &&
    metadata.description.trim().length > 10;
  const hasTechDocs = Boolean(annotations["backstage.io/techdocs-ref"]);

  const bronzeChecks: ScorecardCheck[] = [
    {
      id: "bronze-owner",
      title: "Assigned Service Owner",
      tier: "Bronze",
      passed: hasOwner,
      message: hasOwner ? `Owner: ${spec?.owner}` : "Missing spec.owner",
    },
    {
      id: "bronze-lifecycle",
      title: "Declared Lifecycle & System",
      tier: "Bronze",
      passed: hasLifecycle && hasSystem,
      message:
        hasLifecycle && hasSystem
          ? `${spec?.lifecycle} in ${spec?.system}`
          : "Missing spec.lifecycle or spec.system",
    },
    {
      id: "bronze-description",
      title: "Descriptive Overview",
      tier: "Bronze",
      passed: hasDescription,
      message: hasDescription
        ? "Clear description provided"
        : "Description missing or under 10 characters",
    },
    {
      id: "bronze-techdocs",
      title: "TechDocs Documentation",
      tier: "Bronze",
      passed: hasTechDocs,
      message: hasTechDocs
        ? "backstage.io/techdocs-ref configured"
        : "Missing backstage.io/techdocs-ref annotation",
    },
  ];

  const bronzePassed = bronzeChecks.every((c) => c.passed);

  // --- SILVER CRITERIA ---
  const hasCicd =
    Boolean(annotations["vitruvian.dev/deploy-workflow"]) ||
    Boolean(annotations["vitruvian.dev/release-workflow"]) ||
    Boolean(annotations["argocd/app-name"]) ||
    Boolean(annotations["vitruvian.dev/cloud-run-services"]);

  const hasRuntimeBinding =
    Boolean(annotations["vitruvian.dev/cloud-run-services"]) ||
    Boolean(annotations["backstage.io/kubernetes-id"]) ||
    Boolean(annotations["vitruvian.dev/release-model"]);

  const hasObservability =
    Boolean(annotations["grafana/dashboard-selector"]) ||
    links.some(
      (l) =>
        l.url.includes("grafana.lab.ipv1337.dev") || l.url.includes("grafana"),
    );

  const hasArtifactLinks = links.some(
    (l) =>
      l.url.includes("pkgs/container") ||
      l.url.includes("npmjs.com") ||
      l.url.includes("releases") ||
      l.url.includes("github.com"),
  );

  const silverChecks: ScorecardCheck[] = [
    {
      id: "silver-cicd",
      title: "CI/CD & Deployment Pipeline",
      tier: "Silver",
      passed: hasCicd,
      message: hasCicd
        ? "Declared pipeline workflow or GitOps sync"
        : "No deploy workflow or GitOps binding found",
    },
    {
      id: "silver-runtime",
      title: "Runtime Environment Binding",
      tier: "Silver",
      passed: hasRuntimeBinding,
      message: hasRuntimeBinding
        ? "Runtime environment or release model bound"
        : "No Kubernetes or Cloud Run binding",
    },
    {
      id: "silver-observability",
      title: "Telemetry & Dashboards",
      tier: "Silver",
      passed: hasObservability,
      message: hasObservability
        ? "Grafana dashboard selector or link present"
        : "No Grafana dashboard linked",
    },
    {
      id: "silver-artifacts",
      title: "Artifact & Package Publishing",
      tier: "Silver",
      passed: hasArtifactLinks,
      message: hasArtifactLinks
        ? "Container image, npm, or GitHub release linked"
        : "No release artifact links found",
    },
  ];

  const silverPassed = bronzePassed && silverChecks.every((c) => c.passed);

  // --- GOLD CRITERIA ---
  const hasRunbook = links.some((l) =>
    l.url.includes("incident-triage-runbook"),
  );
  const hasUptime = links.some(
    (l) =>
      l.url.includes("status.ipv1337.dev") ||
      (l.title && l.title.toLowerCase().includes("uptime")),
  );
  const hasApiContracts =
    (Array.isArray(spec?.providesApis) && spec!.providesApis.length > 0) ||
    (Array.isArray(spec?.consumesApis) && spec!.consumesApis.length > 0);
  const hasDependencyTopology =
    Array.isArray(spec?.dependsOn) && spec!.dependsOn.length > 0;

  const goldChecks: ScorecardCheck[] = [
    {
      id: "gold-runbook",
      title: "Incident Triage Runbook",
      tier: "Gold",
      passed: hasRunbook,
      message: hasRunbook
        ? "Linked to standard incident triage runbook"
        : "Missing link to incident runbook",
    },
    {
      id: "gold-uptime",
      title: "Live Health & Uptime Status",
      tier: "Gold",
      passed: hasUptime,
      message: hasUptime
        ? "Linked to Uptime Kuma monitoring"
        : "Missing Uptime Kuma link",
    },
    {
      id: "gold-apis",
      title: "API Contract Registration",
      tier: "Gold",
      passed: hasApiContracts,
      message: hasApiContracts
        ? "Declared provided or consumed APIs"
        : "No providesApis or consumesApis declared",
    },
    {
      id: "gold-dependencies",
      title: "Infrastructure Topology",
      tier: "Gold",
      passed: hasDependencyTopology,
      message: hasDependencyTopology
        ? "Explicit spec.dependsOn topology declared"
        : "No downstream dependsOn declared",
    },
  ];

  const allChecks = [...bronzeChecks, ...silverChecks, ...goldChecks];
  const passedCount = allChecks.filter((c) => c.passed).length;
  const scorePercent = Math.round((passedCount / allChecks.length) * 100);

  let tier: MaturityTier = "Incomplete";
  if (bronzePassed) {
    tier = "Bronze";
    if (silverPassed) {
      const goldPassed = goldChecks.every((c) => c.passed);
      tier = goldPassed ? "Gold" : "Silver";
    }
  }

  const nextSteps: string[] = [];
  if (tier === "Incomplete" || tier === "Bronze") {
    silverChecks
      .filter((c) => !c.passed)
      .forEach((c) => nextSteps.push(`[Silver] ${c.title}`));
  }
  if (tier === "Silver") {
    goldChecks
      .filter((c) => !c.passed)
      .forEach((c) => nextSteps.push(`[Gold] ${c.title}`));
  }

  return {
    tier,
    scorePercent,
    checks: allChecks,
    nextSteps,
  };
}
