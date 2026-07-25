import type { Meta, StoryObj } from "@storybook/react-vite";
import {
  Status,
  Metric,
  Meter,
  SegBar,
  Spark,
  LogStream,
  Table,
} from "./DataDisplay";
import { Plate } from "./Plate";
import { Label } from "./Tag";
import { Button } from "./Button";

const dataDisplayMeta: Meta = {
  title: "Components/Status & metrics",
  parameters: { layout: "padded" },
};
export default dataDisplayMeta;

export const Signals: StoryObj = {
  render: () => (
    <div className="flex flex-wrap gap-6">
      <Status signal="ok">operational</Status>
      <Status signal="run">reconciling</Status>
      <Status signal="warn">degraded</Status>
      <Status signal="crit">unreachable</Status>
      <Status>idle</Status>
    </div>
  ),
};

export const Readouts: StoryObj = {
  render: () => (
    <div className="grid grid-cols-4 gap-5">
      <Plate className="card">
        <Metric label="Uptime" value="99.982%" delta="+0.004 · 30d" />
      </Plate>
      <Plate className="card">
        <Metric label="Cloud spend" value="$41.2k" delta="−9.4% · 30d" />
      </Plate>
      <Plate className="card">
        <Metric label="P95 latency" value="214ms" delta="+18ms · 30d" down />
      </Plate>
      <Plate className="card">
        <Metric label="Reconcile" value="86%" />
        <Meter value={0.86} />
      </Plate>
    </div>
  ),
};

export const Capacity: StoryObj = {
  render: () => (
    <div className="grid grid-cols-2 gap-5">
      <Plate className="card">
        <Label>Node pool · edge-01</Label>
        <SegBar total={12} filled={7} warn={2} />
      </Plate>
      <Plate className="card">
        <div className="flex flex-col gap-3">
          <div>
            <Label>CPU 62%</Label>
            <Meter value={0.62} />
          </div>
          <div>
            <Label>Memory 81%</Label>
            <Meter value={0.81} tone="warn" />
          </div>
          <div>
            <Label>Disk 94%</Label>
            <Meter value={0.94} tone="crit" />
          </div>
        </div>
      </Plate>
    </div>
  ),
};

export const Sparklines: StoryObj = {
  render: () => (
    <div className="grid grid-cols-3 gap-5">
      {[
        ["Build time", "4m 12s"],
        ["Cache hit", "91.4%"],
        ["Flaky tests", "3"],
      ].map(([l, v]) => (
        <Plate className="card" key={l}>
          <Label>{l}</Label>
          <div className="metric-value" style={{ fontSize: 26 }}>
            {v}
          </div>
          <Spark points={[34, 55, 42, 68, 51, 89, 72, 61, 78, 94]} />
        </Plate>
      ))}
    </div>
  ),
};

const rows = [
  ["edge-01", "us-central1", "k3s 1.32.4", "ok", "ready", "3", "98.2"],
  ["edge-02", "us-central1", "k3s 1.32.4", "ok", "ready", "3", "97.4"],
  ["edge-03", "europe-west4", "k3s 1.31.9", "warn", "drifted", "2", "88.1"],
  [
    "edge-04",
    "asia-southeast1",
    "k3s 1.30.2",
    "crit",
    "unreachable",
    "0",
    "0.0",
  ],
] as const;

export const DataTable: StoryObj = {
  render: () => (
    <Plate className="p-4">
      <Table>
        <thead>
          <tr>
            <th>Cluster</th>
            <th>Region</th>
            <th>Version</th>
            <th>Status</th>
            <th className="t-right">Nodes</th>
            <th className="t-right">Uptime %</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r[0]}>
              <td className="mono">{r[0]}</td>
              <td className="dim">{r[1]}</td>
              <td className="mono dim">{r[2]}</td>
              <td>
                <Status signal={r[3] as "ok"}>{r[4]}</Status>
              </td>
              <td className="num t-right">{r[5]}</td>
              <td className="num t-right">{r[6]}</td>
              <td className="t-right">
                <Button variant="ghost" size="sm">
                  Open
                </Button>
              </td>
            </tr>
          ))}
        </tbody>
      </Table>
    </Plate>
  ),
};

export const Events: StoryObj = {
  render: () => (
    <Plate className="card">
      <LogStream
        rows={[
          {
            ts: "04:37:02",
            level: "ok",
            message: "cluster edge-01 reconciled — 3/3 nodes ready",
          },
          {
            ts: "04:37:04",
            level: "info",
            message: "pulumi preview: 12 unchanged, 2 to update",
          },
          {
            ts: "04:36:51",
            level: "warn",
            message: "node edge-03 kubelet version drift (1.31.9 → 1.32.4)",
          },
          {
            ts: "04:36:44",
            level: "err",
            message: "artifact registry auth failed — token expired",
          },
        ]}
      />
    </Plate>
  ),
};
