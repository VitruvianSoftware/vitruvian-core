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
  Link,
  Table,
} from "@backstage/core-components";
import {
  useApi,
  discoveryApiRef,
  fetchApiRef,
} from "@backstage/core-plugin-api";
import { useEntity } from "@backstage/plugin-catalog-react";
import { readCloudRunRefs } from "./cloudRun";

type Row = {
  label: string;
  service: string;
  url?: string;
  revision?: string;
  traffic: { revision: string; percent: number }[];
  ready: boolean;
  message?: string;
};

/**
 * Cloud Run state for the apps that do NOT run in this cluster.
 *
 * The ArgoCD card answers "what version is live and is it healthy" for
 * in-cluster services; this is the same question for tabula and
 * oauth-user-inspector, which deploy to Cloud Run. Data comes from our own
 * backend rather than the browser, because the GCP credential is a federated
 * token exchanged server-side (docs/gcp-cluster-federation.md).
 */
export const CloudRunCard = () => {
  const { entity } = useEntity();
  const discovery = useApi(discoveryApiRef);
  const fetchApi = useApi(fetchApiRef);
  const refs = readCloudRunRefs(entity);

  const { value, loading, error } = useAsync(async () => {
    if (!refs) return { services: [] as Row[], invalid: [] as string[] };
    const base = await discovery.getBaseUrl("cloud-run");
    const res = await fetchApi.fetch(
      `${base}/services?refs=${encodeURIComponent(refs)}`,
    );
    if (!res.ok) {
      throw new Error(`cloud-run backend returned ${res.status}`);
    }
    return (await res.json()) as { services: Row[]; invalid: string[] };
  }, [refs]);

  if (loading) return <Progress />;
  if (error) return <ResponseErrorPanel error={error} />;

  const rows = value?.services ?? [];
  return (
    <InfoCard
      title="Cloud Run"
      subheader={
        value?.invalid?.length
          ? `${value.invalid.length} malformed annotation entry ignored`
          : undefined
      }
    >
      <Table
        options={{
          search: false,
          paging: false,
          toolbar: false,
          padding: "dense",
        }}
        columns={[
          { title: "Environment", field: "label" },
          {
            title: "Status",
            field: "ready",
            render: (r: Row) =>
              r.ready ? (
                <StatusOK>ready</StatusOK>
              ) : (
                <StatusError>{r.message ? "error" : "not ready"}</StatusError>
              ),
          },
          { title: "Revision", field: "revision" },
          {
            title: "Traffic",
            field: "traffic",
            render: (r: Row) =>
              r.traffic.map((t) => `${t.percent}% ${t.revision}`).join(", ") ||
              "-",
          },
          {
            title: "URL",
            field: "url",
            render: (r: Row) => (r.url ? <Link to={r.url}>open</Link> : <>-</>),
          },
        ]}
        data={rows}
      />
    </InfoCard>
  );
};
