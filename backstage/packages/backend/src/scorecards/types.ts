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

export type ScorecardTier = "Gold" | "Silver" | "Bronze" | "Incomplete";

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
    status: "up" | "down" | "degraded" | "not_monitored" | "unknown" | "na";
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
    provider:
      | "cloud-run"
      | "kubernetes"
      | "goreleaser"
      | "npm"
      | "monorepo-bazel"
      | "cloudflare-pages"
      | "none";
  };
};

export type EvaluatedScorecard = {
  entityRef: string;
  name: string;
  archetype: ComponentArchetype;
  overallTier: ScorecardTier;
  overallScore: number;
  tracks: Record<ScorecardTrackId, TrackEvaluation>;
  diagnostics: LiveDiagnostics;
  nextSteps: string[];
  evaluatedAt: string;
};
