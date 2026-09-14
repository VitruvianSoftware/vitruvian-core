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

import React, { useState } from "react";
import {
  Box,
  Button,
  Chip,
  FormControl,
  Grid,
  InputLabel,
  MenuItem,
  Paper,
  Select,
  Typography,
  makeStyles,
} from "@material-ui/core";
import OpenInNewIcon from "@material-ui/icons/OpenInNew";
import TimelineIcon from "@material-ui/icons/Timeline";
import SearchIcon from "@material-ui/icons/Search";
import { InfoCard, Table, WarningPanel } from "@backstage/core-components";
import { useEntity } from "@backstage/plugin-catalog-react";
import {
  getOpenTelemetryServiceName,
  getTempoExploreUrl,
} from "./opentelemetry";

const useStyles = makeStyles((theme) => ({
  root: {
    marginTop: theme.spacing(2),
  },
  toolbar: {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "center",
    justifyContent: "space-between",
    padding: theme.spacing(2),
    marginBottom: theme.spacing(2),
    backgroundColor: theme.palette.background.paper,
    borderRadius: theme.shape.borderRadius,
    border: `1px solid ${theme.palette.divider}`,
    gap: theme.spacing(2),
  },
  filterGroup: {
    display: "flex",
    alignItems: "center",
    gap: theme.spacing(2),
    flexWrap: "wrap",
  },
  formControl: {
    minWidth: 120,
  },
  card: {
    marginBottom: theme.spacing(3),
  },
  codeSnippet: {
    padding: theme.spacing(1.5),
    backgroundColor: theme.palette.background.default,
    borderRadius: theme.shape.borderRadius,
    fontFamily: "monospace",
    fontSize: "0.85rem",
    overflowX: "auto",
    border: `1px solid ${theme.palette.divider}`,
  },
}));

export const OpenTelemetryContent = () => {
  const classes = useStyles();
  const { entity } = useEntity();
  const serviceName = getOpenTelemetryServiceName(entity);
  const [timeRange, setTimeRange] = useState("1h");
  const [minDuration, setMinDuration] = useState("");

  if (!serviceName) {
    return (
      <Box mt={2}>
        <WarningPanel
          title="OpenTelemetry Service Not Configured"
          message={`Component '${entity.metadata.name}' does not declare an OpenTelemetry service annotation ('opentelemetry.io/service-name').`}
        />
      </Box>
    );
  }

  const tempoUrl = getTempoExploreUrl(entity, {
    range: timeRange,
    minDuration: minDuration || undefined,
  });

  const topologyRows = [
    {
      component: "OpenTelemetry Collector",
      endpoint:
        "http://opentelemetry-collector.opentelemetry.svc.cluster.local:4318",
      protocol: "OTLP / HTTP & gRPC (4317)",
      status: "Active (In-Cluster)",
    },
    {
      component: "External Trace Ingestion",
      endpoint: "https://otel.lab.ipv1337.dev",
      protocol: "HTTPS OTLP Gateway (Envoy)",
      status: "Active (Internet / Tailnet)",
    },
    {
      component: "Grafana Tempo Storage",
      endpoint: "http://tempo.opentelemetry.svc.cluster.local:3200",
      protocol: "Tempo Query / Parquet S3",
      status: "Active (MinIO / Homelab)",
    },
  ];

  return (
    <Box className={classes.root}>
      <Paper className={classes.toolbar} elevation={0}>
        <Box className={classes.filterGroup}>
          <Box display="flex" alignItems="center">
            <Typography
              variant="subtitle1"
              style={{ fontWeight: 600, marginRight: 8 }}
            >
              Service:
            </Typography>
            <Chip
              icon={<TimelineIcon />}
              label={serviceName}
              color="primary"
              variant="outlined"
            />
          </Box>

          <FormControl
            variant="outlined"
            size="small"
            className={classes.formControl}
          >
            <InputLabel id="time-range-label">Time Window</InputLabel>
            <Select
              labelId="time-range-label"
              value={timeRange}
              onChange={(e) => setTimeRange(e.target.value as string)}
              label="Time Window"
            >
              <MenuItem value="15m">Last 15 minutes</MenuItem>
              <MenuItem value="1h">Last 1 hour</MenuItem>
              <MenuItem value="6h">Last 6 hours</MenuItem>
              <MenuItem value="24h">Last 24 hours</MenuItem>
            </Select>
          </FormControl>

          <FormControl
            variant="outlined"
            size="small"
            className={classes.formControl}
          >
            <InputLabel id="min-duration-label">Min Duration</InputLabel>
            <Select
              labelId="min-duration-label"
              value={minDuration}
              onChange={(e) => setMinDuration(e.target.value as string)}
              label="Min Duration"
            >
              <MenuItem value="">All Durations</MenuItem>
              <MenuItem value="100ms">&gt; 100ms</MenuItem>
              <MenuItem value="500ms">&gt; 500ms</MenuItem>
              <MenuItem value="1s">&gt; 1s</MenuItem>
              <MenuItem value="5s">&gt; 5s (Slow)</MenuItem>
            </Select>
          </FormControl>
        </Box>

        {tempoUrl && (
          <Button
            variant="contained"
            color="primary"
            size="small"
            href={tempoUrl}
            target="_blank"
            rel="noopener noreferrer"
            startIcon={<SearchIcon />}
            endIcon={<OpenInNewIcon />}
          >
            Search Traces in Tempo
          </Button>
        )}
      </Paper>

      <Grid container spacing={3}>
        <Grid item xs={12} md={7}>
          <InfoCard title="Distributed Trace Infrastructure & Routing">
            <Table
              options={{
                search: false,
                paging: false,
                toolbar: false,
                padding: "dense",
              }}
              columns={[
                {
                  title: "Component",
                  field: "component",
                  cellStyle: { fontWeight: 600 },
                },
                { title: "Endpoint", field: "endpoint" },
                { title: "Protocol", field: "protocol" },
                { title: "Status", field: "status" },
              ]}
              data={topologyRows}
            />
          </InfoCard>
        </Grid>

        <Grid item xs={12} md={5}>
          <InfoCard title="Trace Instrumentation Setup">
            <Typography variant="body2" paragraph>
              Configure standard OpenTelemetry environment variables in your
              workload:
            </Typography>
            <Box className={classes.codeSnippet}>
              <div>OTEL_SERVICE_NAME={serviceName}</div>
              <div>
                OTEL_EXPORTER_OTLP_ENDPOINT=http://opentelemetry-collector.opentelemetry.svc.cluster.local:4318
              </div>
              <div>OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf</div>
              <div>OTEL_TRACES_SAMPLER=parentbased_always_on</div>
            </Box>
          </InfoCard>
        </Grid>
      </Grid>
    </Box>
  );
};
