import type { Meta, StoryObj } from "@storybook/react-vite";
import { Nav, Shell, SideGroup, SideItem, Crumbs } from "./Nav";
import { Plate, Rule } from "./Plate";
import { Button } from "./Button";
import { Card } from "./Card";
import { Tag, Label } from "./Tag";
import { Status, Metric, Meter, LogStream } from "./DataDisplay";
import { Terminal } from "./Terminal";

const patternsMeta: Meta = {
  title: "Patterns/Operations console",
  parameters: { layout: "fullscreen" },
};
export default patternsMeta;

/** A whole screen composed only from the system — the adherence reference. */
export const Console: StoryObj = {
  render: () => (
    <div style={{ background: "var(--color-bg)", minHeight: "100vh" }}>
      <Nav
        actions={
          <Button size="sm" variant="primary">
            Deploy
          </Button>
        }
      >
        <a href="#" aria-current="page">
          Platform
        </a>
        <a href="#">Delivery</a>
        <a href="#">Governance</a>
      </Nav>
      <Shell
        side={
          <>
            <SideGroup>Platform</SideGroup>
            <SideItem href="#" current>
              Overview
            </SideItem>
            <SideItem href="#">Clusters</SideItem>
            <SideItem href="#">Workloads</SideItem>
            <SideGroup>Delivery</SideGroup>
            <SideItem href="#">Pipelines</SideItem>
            <SideItem href="#">Releases</SideItem>
          </>
        }
      >
        <Crumbs>
          <a href="#">platform</a> / <span className="dim">overview</span>
        </Crumbs>
        <div className="flex items-baseline justify-between mt-4">
          <h2 className="m-0">Fleet</h2>
          <div className="flex gap-5">
            <Status signal="ok">4/5 operational</Status>
            <Tag tone="accent">prod</Tag>
          </div>
        </div>
        <Rule />
        <div className="grid grid-cols-4 gap-5">
          <Plate className="card">
            <Metric label="Uptime" value="99.982%" delta="+0.004 · 30d" />
          </Plate>
          <Plate className="card">
            <Metric label="Cloud spend" value="$41.2k" delta="−9.4% · 30d" />
          </Plate>
          <Plate className="card">
            <Metric label="P95" value="214ms" delta="+18ms · 30d" down />
          </Plate>
          <Plate className="card">
            <Metric label="Reconcile" value="86%" />
            <Meter value={0.86} />
          </Plate>
        </div>
        <div className="grid grid-cols-3 gap-5 mt-5">
          <Card
            kicker="01 · cluster"
            title="edge-01"
            meta="us-central1 · k3s 1.32.4"
          >
            Three nodes ready, no drift.
          </Card>
          <Card
            kicker="02 · cluster"
            title="edge-03"
            meta="europe-west4 · k3s 1.31.9"
          >
            Kubelet drift; reconcile queued behind a maintenance window.
          </Card>
          <Plate className="card">
            <Label>Last apply</Label>
            <Terminal
              framed={false}
              lines={[
                { kind: "cmd", text: "devx cluster reconcile edge-03" },
                { kind: "warn", text: "! blocked — maintenance window" },
              ]}
            />
          </Plate>
        </div>
        <div className="mt-5">
          <Plate className="card">
            <Label>Event stream</Label>
            <LogStream
              rows={[
                {
                  ts: "04:37:02",
                  level: "ok",
                  message: "cluster edge-01 reconciled — 3/3 nodes ready",
                },
                {
                  ts: "04:36:51",
                  level: "warn",
                  message: "node edge-03 kubelet version drift",
                },
                {
                  ts: "04:36:44",
                  level: "err",
                  message: "artifact registry auth failed — token expired",
                },
              ]}
            />
          </Plate>
        </div>
      </Shell>
    </div>
  ),
};
