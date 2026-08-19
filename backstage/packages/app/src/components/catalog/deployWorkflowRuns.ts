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

/** Names the single workflow that deploys this component. */
export const DEPLOY_WORKFLOW_ANNOTATION = "vitruvian.dev/deploy-workflow";
/** Same annotation the upstream GitHub Actions plugin keys off. */
export const PROJECT_SLUG_ANNOTATION = "github.com/project-slug";

export type DeployRun = {
  id: number;
  /** GitHub's own conclusion, or "running" while still in progress. */
  status: string;
  branch: string;
  createdAt: string;
  url: string;
  /** True when the run reported success but every deploy job was gated out. */
  noop: boolean;
};

export function readDeployWorkflow(entity: Entity): string | undefined {
  return entity.metadata.annotations?.[DEPLOY_WORKFLOW_ANNOTATION];
}

export function readProjectSlug(entity: Entity): string | undefined {
  return entity.metadata.annotations?.[PROJECT_SLUG_ANNOTATION];
}

/**
 * The card is only worth rendering when BOTH annotations are present: the slug
 * says which repo to query, the workflow says which runs are actually this
 * component's. With only the slug we would be back to the upstream card's
 * monorepo firehose -- every component showing the same unrelated runs.
 */
export function isDeployWorkflowAvailable(entity: Entity): boolean {
  return Boolean(readDeployWorkflow(entity) && readProjectSlug(entity));
}

export function runsUrl(slug: string, workflow: string, limit: number): string {
  // Workflow file names can contain characters that are path-significant.
  return `https://api.github.com/repos/${slug}/actions/workflows/${encodeURIComponent(
    workflow,
  )}/runs?per_page=${limit}`;
}

type ApiJob = { conclusion: string | null; name: string };
type ApiRun = {
  id: number;
  status: string;
  conclusion: string | null;
  head_branch: string | null;
  created_at: string;
  html_url: string;
};

/**
 * A deploy workflow in this repo reports `success` even when every deploy job
 * was skipped, because the affected-targets gate is a separate job that itself
 * succeeded. Reporting that as a green deploy is actively misleading -- it is
 * how tabula and oauth-user-inspector looked "deployed daily" while nothing had
 * ever shipped. When we have the run's jobs, flag that case explicitly.
 */
export function mapRun(run: ApiRun, jobs?: ApiJob[]): DeployRun {
  const deployJobs = (jobs ?? []).filter((j) => j.name.startsWith("deploy-"));
  const noop =
    run.conclusion === "success" &&
    deployJobs.length > 0 &&
    deployJobs.every((j) => j.conclusion === "skipped");
  return {
    id: run.id,
    status:
      run.conclusion ?? (run.status === "completed" ? "unknown" : "running"),
    branch: run.head_branch ?? "-",
    createdAt: run.created_at,
    url: run.html_url,
    noop,
  };
}
