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
import { evaluateScorecard } from "./scorecard";

describe("evaluateScorecard Level 3 Multi-Track engine", () => {
  it("evaluates a minimal entity as Incomplete if Bronze criteria fail", () => {
    const raw: Entity = {
      apiVersion: "backstage.io/v1alpha1",
      kind: "Component",
      metadata: { name: "raw-app" },
      spec: {},
    };

    const res = evaluateScorecard(raw);
    expect(res.overallTier).toBe("Incomplete");
    expect(res.overallScore).toBeLessThan(30);
    expect(res.tracks.security.level).toBe("Incomplete");
  });

  it("evaluates a fully configured microservice as Gold Tier with Level 3 tracks", () => {
    const goldApp: Entity = {
      apiVersion: "backstage.io/v1alpha1",
      kind: "Component",
      metadata: {
        name: "tabula",
        description:
          "SaaS tab and workspace platform with blue-green Cloud Run.",
        annotations: {
          "backstage.io/techdocs-ref": "dir:.",
          "vitruvian.dev/cloud-run-services": "development=...",
          "vitruvian.dev/deploy-workflow": "delivery.yaml",
          "vitruvian.dev/release-model": "continuous-deploy",
          "vitruvian.dev/environments": "development nonproduction production",
          "grafana/dashboard-selector": "tabula",
        },
        links: [
          {
            url: "https://github.com/VitruvianSoftware/tabula",
            title: "GitHub",
          },
          { url: "https://status.ipv1337.dev", title: "Uptime Status" },
          {
            url: "https://github.com/VitruvianSoftware/vitruvian-core/blob/main/docs/operations/incident-triage-runbook.md",
            title: "Incident Triage Runbook",
          },
          {
            url: "https://github.com/VitruvianSoftware/vitruvian-core/pkgs/container/tabula-api",
            title: "Container Image",
          },
        ],
      },
      spec: {
        type: "service",
        owner: "tabula-team",
        lifecycle: "production",
        system: "tabula-platform",
        providesApis: ["tabula-api"],
        dependsOn: ["resource:default/zitadel"],
      },
    };

    const res = evaluateScorecard(goldApp);
    expect(res.archetype).toBe("service");
    expect(res.overallTier).toBe("Gold");
    expect(res.overallScore).toBe(100);
    expect(res.tracks.security.level).toBe("Level 3");
    expect(res.tracks.reliability.level).toBe("Level 3");
    expect(res.tracks.quality.level).toBe("Level 3");
    expect(res.tracks.delivery.level).toBe("Level 3");
    expect(res.nextSteps).toHaveLength(0);
  });

  it("evaluates CLI tools without microservice penalties as Gold", () => {
    const devx: Entity = {
      apiVersion: "backstage.io/v1alpha1",
      kind: "Component",
      metadata: {
        name: "devx",
        description: "Developer experience CLI orchestration for Lima VMs.",
        annotations: {
          "backstage.io/techdocs-ref": "dir:.",
          "vitruvian.dev/release-workflow": "apps-release.yaml",
          "vitruvian.dev/release-model": "goreleaser",
          "vitruvian.dev/environments": "production",
          "vitruvian.dev/mirror": "VitruvianSoftware/devx",
          "grafana/dashboard-selector": "devx",
        },
        links: [
          { url: "https://github.com/VitruvianSoftware/devx", title: "GitHub" },
          {
            url: "https://github.com/VitruvianSoftware/devx/releases",
            title: "Releases",
          },
        ],
      },
      spec: {
        type: "tool",
        owner: "devx-team",
        lifecycle: "production",
        system: "devx-suite",
      },
    };

    const res = evaluateScorecard(devx);
    expect(res.archetype).toBe("tool");
    expect(res.overallTier).toBe("Gold");
    expect(
      res.tracks.reliability.checks.find((c) => c.id === "rel-runbook")?.status,
    ).toBe("not_applicable");
  });
});
