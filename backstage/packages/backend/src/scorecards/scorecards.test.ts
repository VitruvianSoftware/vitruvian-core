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

import { resolve } from "path";
import type { Entity } from "@backstage/catalog-model";
import {
  determineArchetype,
  collectRunbookFacts,
  collectSecurityFacts,
  collectRuntimeFacts,
} from "./factCollectors";
import { evaluateEntityScorecard } from "./evaluator";
import { createScorecardRouter } from "./router";

const REPO_ROOT = resolve(__dirname, "../../../../..");

describe("Level 3 Fact Collectors", () => {
  it("accurately categorizes component archetypes", () => {
    expect(
      determineArchetype({
        apiVersion: "v1",
        kind: "Component",
        metadata: { name: "a" },
        spec: { type: "service" },
      }),
    ).toBe("service");
    expect(
      determineArchetype({
        apiVersion: "v1",
        kind: "Component",
        metadata: { name: "b" },
        spec: { type: "tool" },
      }),
    ).toBe("tool");
    expect(
      determineArchetype({
        apiVersion: "v1",
        kind: "Component",
        metadata: { name: "c" },
        spec: { type: "website" },
      }),
    ).toBe("website");
    expect(
      determineArchetype({
        apiVersion: "v1",
        kind: "Component",
        metadata: { name: "d" },
        spec: { type: "library" },
      }),
    ).toBe("library");
  });

  it("verifies in-repo incident runbook section for buzz and tabula", async () => {
    const buzzEntity: Entity = {
      apiVersion: "backstage.io/v1alpha1",
      kind: "Component",
      metadata: {
        name: "buzz",
        links: [
          {
            url: "https://github.com/VitruvianSoftware/vitruvian-core/blob/main/docs/operations/incident-triage-runbook.md",
            title: "Runbook",
          },
        ],
      },
      spec: {},
    };

    const facts = await collectRunbookFacts(buzzEntity, REPO_ROOT);
    expect(facts.verified).toBe(true);
    expect(facts.sectionFound).toBe(true);
  });

  it("verifies team registration in .github/CODEOWNERS", async () => {
    const tabulaEntity: Entity = {
      apiVersion: "backstage.io/v1alpha1",
      kind: "Component",
      metadata: { name: "tabula" },
      spec: { owner: "group:default/tabula-team" },
    };

    const facts = await collectSecurityFacts(tabulaEntity, REPO_ROOT);
    expect(facts.codeownersBound).toBe(true);
    expect(facts.ownerTeam).toBe("tabula-team");
  });

  it("identifies runtime bindings for Cloud Run and Kubernetes", () => {
    expect(
      collectRuntimeFacts({
        apiVersion: "v1",
        kind: "Component",
        metadata: {
          name: "x",
          annotations: { "vitruvian.dev/cloud-run-services": "dev=..." },
        },
        spec: {},
      }),
    ).toEqual({ bound: true, provider: "cloud-run" });

    expect(
      collectRuntimeFacts({
        apiVersion: "v1",
        kind: "Component",
        metadata: {
          name: "y",
          annotations: { "backstage.io/kubernetes-id": "buzz" },
        },
        spec: {},
      }),
    ).toEqual({ bound: true, provider: "kubernetes" });
  });
});

describe("Level 3 Multi-Track Scorecard Evaluator", () => {
  it("evaluates a microservice entity with live facts and 4 tracks", async () => {
    const tabula: Entity = {
      apiVersion: "backstage.io/v1alpha1",
      kind: "Component",
      metadata: {
        name: "tabula",
        description: "SaaS tab management platform on Cloud Run",
        annotations: {
          "backstage.io/techdocs-ref": "dir:.",
          "vitruvian.dev/cloud-run-services": "development=...",
          "vitruvian.dev/deploy-workflow": "delivery.yaml",
          "vitruvian.dev/release-model": "continuous-deploy",
          "vitruvian.dev/environments": "development nonproduction production",
          "grafana/dashboard-selector": "tabula",
        },
        links: [
          { url: "https://status.ipv1337.dev", title: "Uptime Status" },
          {
            url: "https://github.com/VitruvianSoftware/vitruvian-core/blob/main/docs/operations/incident-triage-runbook.md",
            title: "Runbook",
          },
          {
            url: "https://github.com/VitruvianSoftware/vitruvian-core/pkgs/container/tabula-api",
            title: "Container",
          },
        ],
      },
      spec: {
        type: "service",
        owner: "group:default/tabula-team",
        lifecycle: "production",
        system: "tabula-platform",
        providesApis: ["tabula-api"],
        dependsOn: ["resource:default/zitadel"],
      },
    };

    const scorecard = await evaluateEntityScorecard(tabula, REPO_ROOT);
    expect(scorecard.archetype).toBe("service");
    expect(scorecard.overallTier).toBe("Gold");
    expect(scorecard.overallScore).toBe(100);
    expect(scorecard.tracks.security.level).toBe("Level 3");
    expect(scorecard.tracks.reliability.level).toBe("Level 3");
    expect(scorecard.tracks.quality.level).toBe("Level 3");
    expect(scorecard.tracks.delivery.level).toBe("Level 3");
    expect(scorecard.diagnostics.runbookHealth.sectionFound).toBe(true);
    expect(scorecard.diagnostics.securityHealth.codeownersBound).toBe(true);
  });

  it("does not penalize CLI tools for missing microservice runbooks", async () => {
    const devx: Entity = {
      apiVersion: "backstage.io/v1alpha1",
      kind: "Component",
      metadata: {
        name: "devx",
        description: "Developer experience orchestration CLI for Lima VMs",
        annotations: {
          "backstage.io/techdocs-ref": "dir:.",
          "vitruvian.dev/release-workflow": "apps-release.yml",
          "vitruvian.dev/release-model": "goreleaser",
          "vitruvian.dev/environments": "production",
          "vitruvian.dev/mirror": "VitruvianSoftware/devx",
        },
        links: [
          {
            url: "https://github.com/VitruvianSoftware/devx/releases",
            title: "Releases",
          },
        ],
      },
      spec: {
        type: "tool",
        owner: "group:default/devx-team",
        lifecycle: "production",
        system: "devx-suite",
      },
    };

    const scorecard = await evaluateEntityScorecard(devx, REPO_ROOT);
    expect(scorecard.archetype).toBe("tool");
    expect(scorecard.overallTier).toBe("Gold");
    expect(
      scorecard.tracks.reliability.checks.find((c) => c.id === "rel-runbook")
        ?.status,
    ).toBe("not_applicable");
    expect(
      scorecard.tracks.reliability.checks.find((c) => c.id === "rel-uptime")
        ?.status,
    ).toBe("not_applicable");
  });

  it("initializes createScorecardRouter correctly without invalid config key errors", async () => {
    const mockConfig = {
      has: jest.fn().mockReturnValue(true),
      getOptionalConfigArray: jest.fn().mockReturnValue([
        {
          getOptionalString: jest.fn().mockReturnValue("ghp_test_token"),
        },
      ]),
      getOptionalString: jest.fn(),
    };
    const mockLogger = {
      info: jest.fn(),
      error: jest.fn(),
      warn: jest.fn(),
      debug: jest.fn(),
      child: jest.fn(),
    };

    const router = await createScorecardRouter({
      logger: mockLogger as any,
      config: mockConfig as any,
      repoRoot: REPO_ROOT,
    });

    expect(router).toBeDefined();

    // Also verify when config throws (e.g. strict schema validator in smoke test)
    const throwingConfig = {
      has: jest.fn().mockImplementation(() => {
        throw new Error("Invalid config key 'integrations.github.0.token'");
      }),
    };
    const smokeRouter = await createScorecardRouter({
      logger: mockLogger as any,
      config: throwingConfig as any,
      repoRoot: REPO_ROOT,
    });
    expect(smokeRouter).toBeDefined();
  });
});
