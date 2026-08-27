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

describe("evaluateScorecard maturity engine", () => {
  it("evaluates a minimal entity as Incomplete if Bronze criteria fail", () => {
    const raw: Entity = {
      apiVersion: "backstage.io/v1alpha1",
      kind: "Component",
      metadata: { name: "raw-app" },
      spec: {},
    };

    const res = evaluateScorecard(raw);
    expect(res.tier).toBe("Incomplete");
    expect(res.scorePercent).toBeLessThan(30);
  });

  it("evaluates a fully configured service as Gold Tier", () => {
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
        owner: "tabula-team",
        lifecycle: "production",
        system: "tabula-platform",
        providesApis: ["tabula-api"],
        dependsOn: ["resource:default/zitadel"],
      },
    };

    const res = evaluateScorecard(goldApp);
    expect(res.tier).toBe("Gold");
    expect(res.scorePercent).toBe(100);
    expect(res.checks.every((c) => c.passed)).toBe(true);
    expect(res.nextSteps).toHaveLength(0);
  });

  it("evaluates a CLI tool without Gold extras as Silver Tier", () => {
    const silverApp: Entity = {
      apiVersion: "backstage.io/v1alpha1",
      kind: "Component",
      metadata: {
        name: "devx",
        description: "Developer experience CLI orchestration for Lima VMs.",
        annotations: {
          "backstage.io/techdocs-ref": "dir:.",
          "vitruvian.dev/release-workflow": "apps-release.yml",
          "vitruvian.dev/release-model": "goreleaser",
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
        owner: "devx-team",
        lifecycle: "production",
        system: "devx-suite",
      },
    };

    const res = evaluateScorecard(silverApp);
    expect(res.tier).toBe("Silver");
    expect(res.scorePercent).toBeGreaterThanOrEqual(60);
    expect(res.nextSteps.length).toBeGreaterThan(0);
  });
});
