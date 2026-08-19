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
  isDeployWorkflowAvailable,
  mapRun,
  readDeployWorkflow,
  runsUrl,
} from "./deployWorkflowRuns";

const entity = (annotations?: Record<string, string>): Entity => ({
  apiVersion: "backstage.io/v1alpha1",
  kind: "Component",
  metadata: { name: "x", annotations },
  spec: {},
});

describe("isDeployWorkflowAvailable", () => {
  it("requires BOTH annotations", () => {
    expect(
      isDeployWorkflowAvailable(
        entity({
          "vitruvian.dev/deploy-workflow": "tabula-deploy.yaml",
          "github.com/project-slug": "VitruvianSoftware/vitruvian-core",
        }),
      ),
    ).toBe(true);
  });

  it("is false with only a project-slug -- that is the monorepo firehose the upstream card already shows", () => {
    expect(
      isDeployWorkflowAvailable(
        entity({
          "github.com/project-slug": "VitruvianSoftware/vitruvian-core",
        }),
      ),
    ).toBe(false);
  });

  it("is false with only a workflow, and on an entity with no annotations at all", () => {
    expect(
      isDeployWorkflowAvailable(
        entity({ "vitruvian.dev/deploy-workflow": "tabula-deploy.yaml" }),
      ),
    ).toBe(false);
    expect(isDeployWorkflowAvailable(entity())).toBe(false);
    expect(isDeployWorkflowAvailable(entity({}))).toBe(false);
  });

  it("reads the real annotations our entities carry", () => {
    expect(
      readDeployWorkflow(
        entity({
          "vitruvian.dev/deploy-workflow": "oauth-user-inspector-deploy.yaml",
        }),
      ),
    ).toBe("oauth-user-inspector-deploy.yaml");
  });
});

describe("runsUrl", () => {
  it("targets the single workflow, not the repo", () => {
    expect(
      runsUrl("VitruvianSoftware/vitruvian-core", "tabula-deploy.yaml", 5),
    ).toBe(
      "https://api.github.com/repos/VitruvianSoftware/vitruvian-core/actions/workflows/tabula-deploy.yaml/runs?per_page=5",
    );
  });

  it("encodes the workflow name so a path character cannot escape the URL", () => {
    expect(runsUrl("o/r", "a b/../x.yaml", 1)).toContain("a%20b%2F..%2Fx.yaml");
  });
});

describe("mapRun", () => {
  const base = {
    id: 1,
    status: "completed",
    conclusion: "success",
    head_branch: "main",
    created_at: "2026-08-19T00:00:00Z",
    html_url: "https://github.com/x/y/actions/runs/1",
  };

  it("flags a green run whose deploy jobs were ALL skipped as a no-op", () => {
    // This is exactly how tabula-deploy looked while nothing had ever shipped.
    const r = mapRun(base, [
      { name: "gate", conclusion: "success" },
      { name: "deploy-dev-api", conclusion: "skipped" },
      { name: "deploy-prod-api", conclusion: "skipped" },
    ]);
    expect(r.noop).toBe(true);
    expect(r.status).toBe("success");
  });

  it("does not flag a run that actually deployed", () => {
    expect(
      mapRun(base, [
        { name: "deploy-dev-api", conclusion: "success" },
        { name: "deploy-prod-api", conclusion: "skipped" },
      ]).noop,
    ).toBe(false);
  });

  it("does not flag when there are no deploy jobs to judge, or jobs are unknown", () => {
    expect(mapRun(base, [{ name: "gate", conclusion: "success" }]).noop).toBe(
      false,
    );
    expect(mapRun(base).noop).toBe(false);
  });

  it("does not call a failed run a no-op even if its deploy jobs skipped", () => {
    expect(
      mapRun({ ...base, conclusion: "failure" }, [
        { name: "deploy-dev-api", conclusion: "skipped" },
      ]).noop,
    ).toBe(false);
  });

  it("reports an in-flight run as running, and a null conclusion on a completed run as unknown", () => {
    expect(
      mapRun({ ...base, status: "in_progress", conclusion: null }).status,
    ).toBe("running");
    expect(
      mapRun({ ...base, status: "completed", conclusion: null }).status,
    ).toBe("unknown");
  });

  it("tolerates a missing branch", () => {
    expect(mapRun({ ...base, head_branch: null }).branch).toBe("-");
  });
});
