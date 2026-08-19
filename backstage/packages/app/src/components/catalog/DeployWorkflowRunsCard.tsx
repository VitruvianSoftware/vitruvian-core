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

import React from "react";
import useAsync from "react-use/lib/useAsync";
import {
  InfoCard,
  Progress,
  ResponseErrorPanel,
  StatusOK,
  StatusError,
  StatusPending,
  StatusAborted,
  Link,
  Table,
} from "@backstage/core-components";
import { useApi, githubAuthApiRef } from "@backstage/core-plugin-api";
import { useEntity } from "@backstage/plugin-catalog-react";
import {
  mapRun,
  readDeployWorkflow,
  readProjectSlug,
  runsUrl,
  type DeployRun,
} from "./deployWorkflowRuns";

const StatusIcon = ({ run }: { run: DeployRun }) => {
  if (run.noop) return <StatusAborted>no-op</StatusAborted>;
  switch (run.status) {
    case "success":
      return <StatusOK>success</StatusOK>;
    case "running":
      return <StatusPending>running</StatusPending>;
    case "skipped":
      return <StatusAborted>skipped</StatusAborted>;
    default:
      return <StatusError>{run.status}</StatusError>;
  }
};

/**
 * Recent runs of the ONE workflow that deploys this component.
 *
 * The upstream EntityRecentGithubActionsRunsCard cannot do this: it accepts
 * only `{ limit }` and keys solely off github.com/project-slug, so in a
 * monorepo every component renders the identical firehose of unrelated runs.
 *
 * Authenticates as the signed-in user via githubAuthApiRef rather than a stored
 * token -- the browser reaches api.github.com directly, which works because
 * backend.csp.connect-src permits it (see #1749).
 */
export const DeployWorkflowRunsCard = ({ limit = 5 }: { limit?: number }) => {
  const { entity } = useEntity();
  const auth = useApi(githubAuthApiRef);
  const workflow = readDeployWorkflow(entity);
  const slug = readProjectSlug(entity);

  const { value, loading, error } = useAsync(async () => {
    if (!workflow || !slug) return [];
    const token = await auth.getAccessToken(["repo"]);
    const headers = {
      Authorization: `Bearer ${token}`,
      Accept: "application/vnd.github+json",
    };
    const res = await fetch(runsUrl(slug, workflow, limit), { headers });
    if (!res.ok) {
      throw new Error(`GitHub returned ${res.status} for ${workflow}`);
    }
    const runs = (await res.json()).workflow_runs ?? [];
    // Fetch each run's jobs so a green-but-entirely-skipped deploy can be
    // labelled a no-op instead of reading as a successful deployment.
    return Promise.all(
      runs.map(async (run: Parameters<typeof mapRun>[0]) => {
        try {
          const jr = await fetch(
            `https://api.github.com/repos/${slug}/actions/runs/${run.id}/jobs`,
            { headers },
          );
          const jobs = jr.ok ? ((await jr.json()).jobs ?? []) : undefined;
          return mapRun(run, jobs);
        } catch {
          // The run itself is still worth showing without the no-op verdict.
          return mapRun(run);
        }
      }),
    );
  }, [workflow, slug, limit]);

  if (loading) return <Progress />;
  if (error) return <ResponseErrorPanel error={error} />;

  return (
    <InfoCard title="Deployments" subheader={workflow}>
      <Table
        options={{
          search: false,
          paging: false,
          toolbar: false,
          padding: "dense",
        }}
        columns={[
          {
            title: "Status",
            field: "status",
            render: (row: DeployRun) => <StatusIcon run={row} />,
          },
          { title: "Branch", field: "branch" },
          {
            title: "When",
            field: "createdAt",
            render: (row: DeployRun) =>
              new Date(row.createdAt).toLocaleString(),
          },
          {
            title: "Run",
            field: "url",
            render: (row: DeployRun) => <Link to={row.url}>#{row.id}</Link>,
          },
        ]}
        data={value ?? []}
      />
    </InfoCard>
  );
};
