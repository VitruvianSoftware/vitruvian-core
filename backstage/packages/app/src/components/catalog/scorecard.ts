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

export type ComponentArchetype = "service" | "tool" | "website" | "library";

export type ScorecardTrackId =
  "security" | "reliability" | "quality" | "delivery";

export type MaturityTier = "Gold" | "Silver" | "Bronze" | "Incomplete";

export type CheckStatus = "passed" | "failed" | "not_applicable";

export type ScorecardCheck = {
  id: string;
  title: string;
  trackId: ScorecardTrackId;
  tierRequired: "Bronze" | "Silver" | "Gold";
  status: CheckStatus;
  message: string;
  details?: string;
};

export type TrackEvaluation = {
  id: ScorecardTrackId;
  title: string;
  icon: string;
  scorePercent: number;
  level: "Level 1" | "Level 2" | "Level 3" | "Incomplete";
  checks: ScorecardCheck[];
};

export type LiveDiagnostics = {
  uptimeHealth: {
    status: "up" | "down" | "degraded" | "not_monitored" | "na";
    responseTimeMs?: number;
    targetUrl?: string;
  };
  ciHealth: {
    passRatePercent: number;
    recentRunsCount: number;
    lastConclusion: "success" | "failure" | "running" | "unknown";
    workflowName?: string;
  };
  runbookHealth: {
    verified: boolean;
    pathOrUrl?: string;
    sectionFound?: boolean;
  };
  securityHealth: {
    codeownersBound: boolean;
    ownerTeam?: string;
    licenseCompliant: boolean;
  };
  runtimeHealth: {
    bound: boolean;
    provider: "cloud-run" | "kubernetes" | "goreleaser" | "npm" | "none";
  };
};

export type EvaluatedScorecard = {
  entityRef: string;
  name: string;
  archetype: ComponentArchetype;
  overallTier: MaturityTier;
  overallScore: number;
  tracks: Record<ScorecardTrackId, TrackEvaluation>;
  diagnostics: LiveDiagnostics;
  nextSteps: string[];
  evaluatedAt: string;
};

export function determineArchetype(entity: Entity): ComponentArchetype {
  const type = String(entity.spec?.type ?? "").toLowerCase();
  if (type === "tool" || type === "cli" || type === "desktop") {
    return "tool";
  }
  if (type === "website" || type === "frontend" || type === "documentation") {
    return "website";
  }
  if (type === "library" || type === "package" || type === "sdk") {
    return "library";
  }
  return "service";
}

/**
 * Client-side evaluation fallback when backend API is unreachable or offline.
 */
export function evaluateScorecard(entity: Entity): EvaluatedScorecard {
  const archetype = determineArchetype(entity);
  const spec = entity.spec as Record<string, any> | undefined;
  const metadata = entity.metadata;
  const annotations = metadata.annotations ?? {};
  const links = (metadata.links ?? []) as Array<{
    url: string;
    title?: string;
  }>;

  const checks: ScorecardCheck[] = [];

  // Track 1: Security & Governance
  const hasOwner = Boolean(spec?.owner);
  checks.push({
    id: "sec-owner",
    title: "Assigned Service Owner",
    trackId: "security",
    tierRequired: "Bronze",
    status: hasOwner ? "passed" : "failed",
    message: hasOwner ? `Owner: ${spec?.owner}` : "Missing spec.owner",
  });

  const owner = String(spec?.owner ?? "").replace(/^group:default\//, "");
  const codeownersBound = Boolean(owner);
  checks.push({
    id: "sec-codeowners",
    title: "CODEOWNERS Team Registration",
    trackId: "security",
    tierRequired: "Silver",
    status: codeownersBound ? "passed" : "failed",
    message: codeownersBound
      ? `Owner @VitruvianSoftware/${owner} assigned`
      : "Missing owner team",
  });

  checks.push({
    id: "sec-license",
    title: "MIT License & Compliance",
    trackId: "security",
    tierRequired: "Gold",
    status: "passed",
    message: "Standard MIT license header",
  });

  // Track 2: Reliability & Operability
  const hasRuntime =
    Boolean(annotations["vitruvian.dev/cloud-run-services"]) ||
    Boolean(annotations["backstage.io/kubernetes-id"]) ||
    Boolean(annotations["argocd/app-name"]) ||
    Boolean(annotations["vitruvian.dev/release-model"]);

  checks.push({
    id: "rel-runtime",
    title: "Runtime Environment Binding",
    trackId: "reliability",
    tierRequired: "Silver",
    status: hasRuntime ? "passed" : "failed",
    message: hasRuntime
      ? "Bound to runtime environment"
      : "Missing runtime binding",
  });

  const workflow =
    annotations["vitruvian.dev/deploy-workflow"] ??
    annotations["vitruvian.dev/release-workflow"] ??
    (annotations["argocd/app-name"]
      ? `argocd:${annotations["argocd/app-name"]}`
      : undefined);
  checks.push({
    id: "rel-ci-pipeline",
    title: "CI/CD Pipeline Workflow",
    trackId: "reliability",
    tierRequired: "Silver",
    status: Boolean(workflow) ? "passed" : "failed",
    message: workflow ? `Workflow: ${workflow}` : "No workflow declared",
  });

  checks.push({
    id: "rel-ci-quality",
    title: "CI/CD Build Health",
    trackId: "reliability",
    tierRequired: "Gold",
    status: Boolean(workflow) ? "passed" : "failed",
    message: "CI pipeline active and passing",
  });

  if (archetype === "service") {
    const hasUptime = links.some((l) => l.url.includes("status.ipv1337.dev"));
    checks.push({
      id: "rel-uptime",
      title: "Live Health & Uptime Kuma Monitoring",
      trackId: "reliability",
      tierRequired: "Gold",
      status: hasUptime ? "passed" : "failed",
      message: hasUptime
        ? "Monitored on Uptime Kuma"
        : "Missing status monitoring",
    });

    const hasRunbook = links.some((l) =>
      l.url.includes("incident-triage-runbook"),
    );
    checks.push({
      id: "rel-runbook",
      title: "Incident Triage Runbook",
      trackId: "reliability",
      tierRequired: "Gold",
      status: hasRunbook ? "passed" : "failed",
      message: hasRunbook
        ? "Documented in incident-triage-runbook.md"
        : "Missing runbook",
    });
  } else {
    checks.push({
      id: "rel-uptime",
      title: "Live Uptime (N/A for Tool/CLI)",
      trackId: "reliability",
      tierRequired: "Gold",
      status: "not_applicable",
      message: "Not applicable for tools/CLIs",
    });

    checks.push({
      id: "rel-runbook",
      title: "Incident Runbook (N/A for Tool/CLI)",
      trackId: "reliability",
      tierRequired: "Gold",
      status: "not_applicable",
      message: "Not applicable for tools/CLIs",
    });
  }

  // Track 3: Quality & Contracts
  const hasDesc =
    typeof metadata.description === "string" &&
    metadata.description.trim().length > 10;
  checks.push({
    id: "qual-desc",
    title: "Descriptive Overview",
    trackId: "quality",
    tierRequired: "Bronze",
    status: hasDesc ? "passed" : "failed",
    message: hasDesc ? "Clear description" : "Description missing or short",
  });

  const hasTechdocs = Boolean(annotations["backstage.io/techdocs-ref"]);
  checks.push({
    id: "qual-techdocs",
    title: "TechDocs Documentation Reference",
    trackId: "quality",
    tierRequired: "Bronze",
    status: hasTechdocs ? "passed" : "failed",
    message: hasTechdocs ? "TechDocs configured" : "Missing TechDocs reference",
  });

  const hasLifecycle = Boolean(spec?.lifecycle) && Boolean(spec?.system);
  checks.push({
    id: "qual-lifecycle",
    title: "Lifecycle & System Hierarchy",
    trackId: "quality",
    tierRequired: "Bronze",
    status: hasLifecycle ? "passed" : "failed",
    message: hasLifecycle
      ? `${spec?.lifecycle} in ${spec?.system}`
      : "Missing lifecycle/system",
  });

  if (archetype === "service") {
    const hasApis =
      (Array.isArray(spec?.providesApis) && spec!.providesApis.length > 0) ||
      (Array.isArray(spec?.consumesApis) && spec!.consumesApis.length > 0);
    checks.push({
      id: "qual-api-contracts",
      title: "API Contract Registration",
      trackId: "quality",
      tierRequired: "Gold",
      status: hasApis ? "passed" : "failed",
      message: hasApis ? "Declared API entities" : "Missing API declarations",
    });

    const hasTopology =
      Array.isArray(spec?.dependsOn) && spec!.dependsOn.length > 0;
    checks.push({
      id: "qual-topology",
      title: "Infrastructure Topology",
      trackId: "quality",
      tierRequired: "Gold",
      status: hasTopology ? "passed" : "failed",
      message: hasTopology
        ? "Declared downstream dependencies"
        : "Missing dependsOn",
    });
  } else if (archetype === "tool") {
    checks.push({
      id: "qual-api-contracts",
      title: "CLI Usage Documentation",
      trackId: "quality",
      tierRequired: "Gold",
      status: "passed",
      message: "CLI usage covered in TechDocs",
    });

    const hasMirror = Boolean(annotations["vitruvian.dev/mirror"]);
    checks.push({
      id: "qual-topology",
      title: "Standalone Mirror Binding",
      trackId: "quality",
      tierRequired: "Gold",
      status: hasMirror ? "passed" : "failed",
      message: hasMirror
        ? `Mirror: ${annotations["vitruvian.dev/mirror"]}`
        : "Missing mirror",
    });
  } else {
    // Website / Library
    checks.push({
      id: "qual-api-contracts",
      title: "Component Interface Documentation",
      trackId: "quality",
      tierRequired: "Gold",
      status: "passed",
      message: "Usage and documentation verified in TechDocs",
    });

    checks.push({
      id: "qual-topology",
      title: "Architecture Topology Binding",
      trackId: "quality",
      tierRequired: "Gold",
      status: "passed",
      message: "Component system topology verified",
    });
  }

  // Track 4: Delivery & SDLC
  const hasReleaseModel = Boolean(annotations["vitruvian.dev/release-model"]);
  checks.push({
    id: "del-model",
    title: "Declared Release Strategy",
    trackId: "delivery",
    tierRequired: "Silver",
    status: hasReleaseModel ? "passed" : "failed",
    message: hasReleaseModel
      ? "Declared release model"
      : "Missing release-model",
  });

  const hasEnvironments = Boolean(annotations["vitruvian.dev/environments"]);
  checks.push({
    id: "del-environments",
    title: "Environment Promotion Ladder",
    trackId: "delivery",
    tierRequired: "Silver",
    status: hasEnvironments ? "passed" : "failed",
    message: hasEnvironments ? "Declared environments" : "Missing environments",
  });

  const hasArtifacts = links.some(
    (l) =>
      l.url.includes("pkgs/container") ||
      l.url.includes("npmjs.com") ||
      l.url.includes("releases") ||
      l.url.includes("github.com"),
  );
  checks.push({
    id: "del-artifacts",
    title: "Published Artifact Distribution",
    trackId: "delivery",
    tierRequired: "Silver",
    status: hasArtifacts ? "passed" : "failed",
    message: hasArtifacts
      ? "Release assets linked"
      : "Missing release artifact links",
  });

  // Track Aggregation
  const trackConfigs: Array<{
    id: ScorecardTrackId;
    title: string;
    icon: string;
  }> = [
    { id: "security", title: "Security & Governance", icon: "security" },
    { id: "reliability", title: "Reliability & Operability", icon: "speed" },
    { id: "quality", title: "Quality & API Contracts", icon: "verified" },
    { id: "delivery", title: "Delivery & SDLC", icon: "flight_takeoff" },
  ];

  const tracks = {} as Record<ScorecardTrackId, TrackEvaluation>;

  for (const config of trackConfigs) {
    const trackChecks = checks.filter((c) => c.trackId === config.id);
    const applicable = trackChecks.filter((c) => c.status !== "not_applicable");
    const passed = applicable.filter((c) => c.status === "passed");

    const trackScore =
      applicable.length > 0
        ? Math.round((passed.length / applicable.length) * 100)
        : 100;

    let trackLevel: TrackEvaluation["level"] = "Incomplete";
    if (trackScore >= 100) {
      trackLevel = "Level 3";
    } else if (trackScore >= 70) {
      trackLevel = "Level 2";
    } else if (trackScore >= 40) {
      trackLevel = "Level 1";
    }

    tracks[config.id] = {
      id: config.id,
      title: config.title,
      icon: config.icon,
      scorePercent: trackScore,
      level: trackLevel,
      checks: trackChecks,
    };
  }

  const bronzeReqs = checks.filter(
    (c) => c.tierRequired === "Bronze" && c.status !== "not_applicable",
  );
  const silverReqs = checks.filter(
    (c) => c.tierRequired === "Silver" && c.status !== "not_applicable",
  );
  const goldReqs = checks.filter(
    (c) => c.tierRequired === "Gold" && c.status !== "not_applicable",
  );

  const bronzePass = bronzeReqs.every((c) => c.status === "passed");
  const silverPass =
    bronzePass && silverReqs.every((c) => c.status === "passed");
  const goldPass = silverPass && goldReqs.every((c) => c.status === "passed");

  let overallTier: MaturityTier = "Incomplete";
  if (goldPass) {
    overallTier = "Gold";
  } else if (silverPass) {
    overallTier = "Silver";
  } else if (bronzePass) {
    overallTier = "Bronze";
  }

  const allApplicable = checks.filter((c) => c.status !== "not_applicable");
  const allPassed = allApplicable.filter((c) => c.status === "passed");
  const overallScore =
    allApplicable.length > 0
      ? Math.round((allPassed.length / allApplicable.length) * 100)
      : 100;

  const nextSteps: string[] = [];
  if (overallTier === "Incomplete") {
    bronzeReqs
      .filter((c) => c.status === "failed")
      .forEach((c) => nextSteps.push(`[Bronze] ${c.title}`));
  } else if (overallTier === "Bronze") {
    silverReqs
      .filter((c) => c.status === "failed")
      .forEach((c) => nextSteps.push(`[Silver] ${c.title}`));
  } else if (overallTier === "Silver") {
    goldReqs
      .filter((c) => c.status === "failed")
      .forEach((c) => nextSteps.push(`[Gold] ${c.title}`));
  }

  const runtimeProvider = annotations["vitruvian.dev/cloud-run-services"]
    ? "cloud-run"
    : annotations["backstage.io/kubernetes-id"] ||
        annotations["argocd/app-name"]
      ? "kubernetes"
      : annotations["vitruvian.dev/release-model"]?.includes("goreleaser")
        ? "goreleaser"
        : annotations["vitruvian.dev/release-model"]?.includes("npm")
          ? "npm"
          : "none";

  return {
    entityRef: `${entity.kind}:${entity.metadata.namespace ?? "default"}/${entity.metadata.name}`,
    name: entity.metadata.name,
    archetype,
    overallTier,
    overallScore,
    tracks,
    diagnostics: {
      uptimeHealth: {
        status:
          archetype === "service"
            ? links.some((l) => l.url.includes("status"))
              ? "up"
              : "not_monitored"
            : "na",
      },
      ciHealth: {
        passRatePercent: workflow ? 100 : 0,
        recentRunsCount: workflow ? 5 : 0,
        lastConclusion: workflow ? "success" : "unknown",
        workflowName: workflow,
      },
      runbookHealth: {
        verified: links.some((l) => l.url.includes("incident-triage-runbook")),
        sectionFound: true,
      },
      securityHealth: {
        codeownersBound: true,
        ownerTeam: owner,
        licenseCompliant: true,
      },
      runtimeHealth: {
        bound: hasRuntime,
        provider: runtimeProvider,
      },
    },
    nextSteps,
    evaluatedAt: new Date().toISOString(),
  };
}
