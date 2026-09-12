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
import { Button, Chip, Typography } from "@material-ui/core";
import OpenInNewIcon from "@material-ui/icons/OpenInNew";
import TimelineIcon from "@material-ui/icons/Timeline";
import { InfoCard, Table, WarningPanel } from "@backstage/core-components";
import { useEntity } from "@backstage/plugin-catalog-react";
import {
  getOpenTelemetryServiceName,
  getTempoExploreUrl,
} from "./opentelemetry";

export const EntityOpenTelemetryCard = () => {
  const { entity } = useEntity();
  const serviceName = getOpenTelemetryServiceName(entity);
  const tempoUrl = getTempoExploreUrl(entity);

  if (!serviceName) {
    return (
      <InfoCard title="Distributed Tracing">
        <WarningPanel
          title="OpenTelemetry Service Not Configured"
          message="This entity does not declare an 'opentelemetry.io/service-name' annotation."
        />
      </InfoCard>
    );
  }

  const rows = [
    {
      property: "Service Name",
      value: (
        <Chip
          icon={<TimelineIcon />}
          label={serviceName}
          size="small"
          color="primary"
          variant="outlined"
        />
      ),
    },
    {
      property: "Trace Storage",
      value: <Typography variant="body2">Grafana Tempo (MinIO S3)</Typography>,
    },
    {
      property: "OTLP Ingestion Endpoint",
      value: (
        <Typography variant="body2">
          http://opentelemetry-collector.opentelemetry.svc.cluster.local:4318
        </Typography>
      ),
    },
    {
      property: "External OTLP Gateway",
      value: (
        <Typography variant="body2">https://otel.lab.ipv1337.dev</Typography>
      ),
    },
  ];

  return (
    <InfoCard
      title="Distributed Tracing"
      action={
        tempoUrl && (
          <Button
            color="primary"
            href={tempoUrl}
            target="_blank"
            rel="noopener noreferrer"
            endIcon={<OpenInNewIcon />}
            size="small"
          >
            Explore in Tempo
          </Button>
        )
      }
    >
      <Table
        options={{
          search: false,
          paging: false,
          toolbar: false,
          padding: "dense",
          header: false,
        }}
        columns={[
          {
            title: "Property",
            field: "property",
            cellStyle: { fontWeight: 600, width: "35%" },
          },
          { title: "Value", field: "value" },
        ]}
        data={rows}
      />
    </InfoCard>
  );
};
