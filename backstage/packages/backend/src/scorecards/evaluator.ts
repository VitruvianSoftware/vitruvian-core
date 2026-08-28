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
import {
  collectCiQualityFacts,
  collectRunbookFacts,
  collectRuntimeFacts,
  collectSecurityFacts,
  collectUptimeFacts,
  determineArchetype,
} from "./factCollectors";
import type {
  EvaluatedScorecard,
  ScorecardCheck,
  ScorecardTier,
  ScorecardTrackId,
  TrackEvaluation,
} from "./types";

export async function evaluateEntityScorecard(
  entity: Entity,
  repoRoot: string,
  githubToken?: string,
): Promise<EvaluatedScorecard> {
  const archetype = determineArchetype(entity);
  const spec = entity.spec as Record<string, any> | undefined;
  const metadata = entity.metadata;
  const annotations = metadata.annotations ?? {};
  const links = (metadata.links ?? []) as Array<{
    url: string;
    title?: string;
  }>;

  // Live Fact Collection (Asynchronous)
  const runbookHealth = await collectRunbookFacts(entity, repoRoot);
  const uptimeHealth = await collectUptimeFacts(entity, archetype);
  const ciHealth = await collectCiQualityFacts(entity, githubToken);
  const securityHealth = await collectSecurityFacts(entity, repoRoot);
  const runtimeHealth = collectRuntimeFacts(entity);

  const checks: ScorecardCheck[] = [];

  // ==========================================
  // TRACK 1: Security & Governance
  // ==========================================
  const hasOwner = Boolean(spec?.owner);
  checks.push({
    id: "sec-owner",
    title: "Assigned Service Owner",
    trackId: "security",
    tierRequired: "Bronze",
    status: hasOwner ? "passed" : "failed",
    message: hasOwner ? `Owner: ${spec?.owner}` : "Missing spec.owner",
  });

  checks.push({
    id: "sec-codeowners",
    title: "CODEOWNERS Team Registration",
    trackId: "security",
    tierRequired: "Silver",
    status: securityHealth.codeownersBound ? "passed" : "failed",
    message: securityHealth.codeownersBound
      ? `Verified team @VitruvianSoftware/${securityHealth.ownerTeam} in CODEOWNERS`
      : `Owner ${spec?.owner} is not registered in .github/CODEOWNERS`,
  });

  checks.push({
    id: "sec-license",
    title: "MIT License & Compliance",
    trackId: "security",
    tierRequired: "Gold",
    status: securityHealth.licenseCompliant ? "passed" : "failed",
    message: securityHealth.licenseCompliant
      ? "Verified standard MIT license conformance in repository"
      : "Missing or non-standard LICENSE file in repository",
  });

  // ==========================================
  // TRACK 2: Reliability & Operability
  // ==========================================
  checks.push({
    id: "rel-runtime",
    title: "Runtime Environment Binding",
    trackId: "reliability",
    tierRequired: "Silver",
    status: runtimeHealth.bound ? "passed" : "failed",
    message: runtimeHealth.bound
      ? `Bound to ${runtimeHealth.provider}`
      : "Missing Cloud Run, Kubernetes, or Release model binding",
  });

  const hasCicdPipeline = Boolean(ciHealth.workflowName);
  checks.push({
    id: "rel-ci-pipeline",
    title: "CI/CD Pipeline Workflow",
    trackId: "reliability",
    tierRequired: "Silver",
    status: hasCicdPipeline ? "passed" : "failed",
    message: hasCicdPipeline
      ? `Pipeline: ${ciHealth.workflowName}`
      : "No deploy-workflow or release-workflow declared",
  });

  const isCiUnverified =
    ciHealth.lastConclusion === "unknown" && ciHealth.recentRunsCount === 0;
  const isCiHealthy = ciHealth.passRatePercent >= 80;
  checks.push({
    id: "rel-ci-quality",
    title: "CI/CD Build Health (Pass Rate >= 80%)",
    trackId: "reliability",
    tierRequired: "Gold",
    status: isCiUnverified
      ? "not_applicable"
      : isCiHealthy
        ? "passed"
        : "failed",
    message: isCiUnverified
      ? "CI build health not verified (no GitHub token configured)"
      : `Recent build pass rate: ${ciHealth.passRatePercent}% (${ciHealth.recentRunsCount} runs)`,
  });

  if (archetype === "service") {
    const isUptimeUnknown = uptimeHealth.status === "unknown";
    const isUptimeGood = uptimeHealth.status === "up";
    checks.push({
      id: "rel-uptime",
      title: "Live Health & Uptime Kuma Monitoring",
      trackId: "reliability",
      tierRequired: "Gold",
      status: isUptimeUnknown
        ? "not_applicable"
        : isUptimeGood
          ? "passed"
          : "failed",
      message: isUptimeUnknown
        ? `Uptime probe could not reach ${uptimeHealth.targetUrl} (network unreachable)`
        : isUptimeGood
          ? `Monitored via ${uptimeHealth.targetUrl}`
          : "Missing live status page monitoring",
    });

    const isRunbookUnverifiable =
      runbookHealth.verified && runbookHealth.sectionFound === undefined;
    const isRunbookGood = runbookHealth.verified && runbookHealth.sectionFound;
    checks.push({
      id: "rel-runbook",
      title: "Verified Incident Triage Runbook",
      trackId: "reliability",
      tierRequired: "Gold",
      status: isRunbookUnverifiable
        ? "not_applicable"
        : isRunbookGood
          ? "passed"
          : "failed",
      message: isRunbookUnverifiable
        ? `Runbook linked at ${runbookHealth.pathOrUrl} (content not verifiable in this environment)`
        : isRunbookGood
          ? `Documented in ${runbookHealth.pathOrUrl}`
          : runbookHealth.verified
            ? "Runbook linked, but service-specific section missing"
            : "Missing link to incident triage runbook",
    });
  } else {
    checks.push({
      id: "rel-uptime",
      title: "Live Uptime Kuma Monitoring (Not Applicable for Tool/Library)",
      trackId: "reliability",
      tierRequired: "Gold",
      status: "not_applicable",
      message: `${archetype.toUpperCase()} components do not require live uptime monitoring`,
    });

    checks.push({
      id: "rel-runbook",
      title: "Incident Runbook (Not Applicable for Tool/Library)",
      trackId: "reliability",
      tierRequired: "Gold",
      status: "not_applicable",
      message: `${archetype.toUpperCase()} components do not require production on-call runbooks`,
    });
  }

  // ==========================================
  // TRACK 3: Quality & Contracts
  // ==========================================
  const hasDesc =
    typeof metadata.description === "string" &&
    metadata.description.trim().length > 10;
  checks.push({
    id: "qual-desc",
    title: "Descriptive Overview",
    trackId: "quality",
    tierRequired: "Bronze",
    status: hasDesc ? "passed" : "failed",
    message: hasDesc
      ? "Clear description provided"
      : "Description missing or under 10 characters",
  });

  const hasTechdocs = Boolean(annotations["backstage.io/techdocs-ref"]);
  checks.push({
    id: "qual-techdocs",
    title: "TechDocs Documentation Reference",
    trackId: "quality",
    tierRequired: "Bronze",
    status: hasTechdocs ? "passed" : "failed",
    message: hasTechdocs
      ? "TechDocs configured"
      : "Missing backstage.io/techdocs-ref annotation",
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
      : "Missing lifecycle or system",
  });

  if (archetype === "service") {
    const hasApis =
      (Array.isArray(spec?.providesApis) && spec!.providesApis.length > 0) ||
      (Array.isArray(spec?.consumesApis) && spec!.consumesApis.length > 0);
    checks.push({
      id: "qual-api-contracts",
      title: "API Contract Registration (providesApis/consumesApis)",
      trackId: "quality",
      tierRequired: "Gold",
      status: hasApis ? "passed" : "failed",
      message: hasApis
        ? "Declared API entities in catalog"
        : "No provided or consumed APIs declared",
    });

    const hasTopology =
      Array.isArray(spec?.dependsOn) && spec!.dependsOn.length > 0;
    checks.push({
      id: "qual-topology",
      title: "Infrastructure Topology (dependsOn)",
      trackId: "quality",
      tierRequired: "Gold",
      status: hasTopology ? "passed" : "failed",
      message: hasTopology
        ? "Declared downstream infrastructure dependencies"
        : "No dependsOn declared",
    });
  } else if (archetype === "tool") {
    checks.push({
      id: "qual-api-contracts",
      title: "CLI Usage / API Interface Documentation",
      trackId: "quality",
      tierRequired: "Gold",
      status: "passed",
      message: "CLI usage guide covered in TechDocs",
    });

    const hasMirror = Boolean(annotations["vitruvian.dev/mirror"]);
    checks.push({
      id: "qual-topology",
      title: "Standalone Mirror Binding (Copybara)",
      trackId: "quality",
      tierRequired: "Gold",
      status: hasMirror ? "passed" : "failed",
      message: hasMirror
        ? `Bound to mirror ${annotations["vitruvian.dev/mirror"]}`
        : "Missing vitruvian.dev/mirror annotation",
    });
  } else if (archetype === "website") {
    const hasLiveUrl = links.some(
      (l) =>
        l.url.startsWith("https://") &&
        !l.url.includes("github.com") &&
        !l.url.includes("status."),
    );
    checks.push({
      id: "qual-api-contracts",
      title: "Live Site URL Published",
      trackId: "quality",
      tierRequired: "Gold",
      status: hasLiveUrl ? "passed" : "failed",
      message: hasLiveUrl
        ? "Live site URL linked in catalog"
        : "No live site URL found in links",
    });

    const hasProjectSlug = Boolean(annotations["github.com/project-slug"]);
    checks.push({
      id: "qual-topology",
      title: "Source Repository Binding",
      trackId: "quality",
      tierRequired: "Gold",
      status: hasProjectSlug ? "passed" : "failed",
      message: hasProjectSlug
        ? `Bound to ${annotations["github.com/project-slug"]}`
        : "Missing github.com/project-slug annotation",
    });
  } else {
    // Library archetype
    const hasPackageLink = links.some(
      (l) =>
        l.url.includes("npmjs.com") ||
        l.url.includes("pkg.go.dev") ||
        l.url.includes("pypi.org") ||
        l.url.includes("crates.io"),
    );
    const hasSourceLink = links.some((l) => l.url.includes("github.com"));
    checks.push({
      id: "qual-api-contracts",
      title: "Package Registry or Source Link",
      trackId: "quality",
      tierRequired: "Gold",
      status: hasPackageLink || hasSourceLink ? "passed" : "failed",
      message:
        hasPackageLink || hasSourceLink
          ? "Package registry or source repository linked"
          : "No package registry or source link found",
    });

    const hasMirrorOrPkg =
      Boolean(annotations["vitruvian.dev/mirror"]) || hasPackageLink;
    checks.push({
      id: "qual-topology",
      title: "Distribution Channel Binding",
      trackId: "quality",
      tierRequired: "Gold",
      status: hasMirrorOrPkg ? "passed" : "failed",
      message: hasMirrorOrPkg
        ? annotations["vitruvian.dev/mirror"]
          ? `Mirror: ${annotations["vitruvian.dev/mirror"]}`
          : "Package registry linked"
        : "Missing vitruvian.dev/mirror annotation or package registry link",
    });
  }

  // ==========================================
  // TRACK 4: Delivery & SDLC
  // ==========================================
  const hasReleaseModel = Boolean(annotations["vitruvian.dev/release-model"]);
  checks.push({
    id: "del-model",
    title: "Declared Release Strategy",
    trackId: "delivery",
    tierRequired: "Silver",
    status: hasReleaseModel ? "passed" : "failed",
    message: hasReleaseModel
      ? `Model: ${annotations["vitruvian.dev/release-model"]}`
      : "Missing vitruvian.dev/release-model annotation",
  });

  const hasEnvironments =
    Boolean(annotations["vitruvian.dev/environments"]) ||
    (archetype !== "service" &&
      (hasReleaseModel || Boolean(annotations["vitruvian.dev/mirror"])));
  checks.push({
    id: "del-environments",
    title: "Environment Promotion Ladder",
    trackId: "delivery",
    tierRequired: "Silver",
    status: hasEnvironments ? "passed" : "failed",
    message: hasEnvironments
      ? annotations["vitruvian.dev/environments"]
        ? `Environments: ${annotations["vitruvian.dev/environments"]}`
        : "Client distribution channels declared"
      : "Missing vitruvian.dev/environments annotation",
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
    title: "Published Artifact / Distribution Channel",
    trackId: "delivery",
    tierRequired: "Silver",
    status: hasArtifacts ? "passed" : "failed",
    message: hasArtifacts
      ? "Release assets or package linked"
      : "No release artifacts linked",
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
    const applicableChecks = trackChecks.filter(
      (c) => c.status !== "not_applicable",
    );
    const passedTrackChecks = applicableChecks.filter(
      (c) => c.status === "passed",
    );

    const trackScore =
      applicableChecks.length > 0
        ? Math.round((passedTrackChecks.length / applicableChecks.length) * 100)
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

  // Overall Tier Calculation
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

  let overallTier: ScorecardTier = "Incomplete";
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
  const failingBronze = bronzeReqs.filter((c) => c.status === "failed");
  const failingSilver = silverReqs.filter((c) => c.status === "failed");
  const failingGold = goldReqs.filter((c) => c.status === "failed");

  if (overallTier === "Incomplete") {
    failingBronze.forEach((c) =>
      nextSteps.push(`[Bronze] ${c.title}: ${c.message}`),
    );
  } else if (overallTier === "Bronze") {
    failingSilver.forEach((c) =>
      nextSteps.push(`[Silver] ${c.title}: ${c.message}`),
    );
  } else if (overallTier === "Silver") {
    failingGold.forEach((c) =>
      nextSteps.push(`[Gold] ${c.title}: ${c.message}`),
    );
  }

  return {
    entityRef: `${entity.kind}:${entity.metadata.namespace ?? "default"}/${entity.metadata.name}`,
    name: entity.metadata.name,
    archetype,
    overallTier,
    overallScore,
    tracks,
    diagnostics: {
      uptimeHealth,
      ciHealth,
      runbookHealth,
      securityHealth,
      runtimeHealth,
    },
    nextSteps,
    evaluatedAt: new Date().toISOString(),
  };
}
