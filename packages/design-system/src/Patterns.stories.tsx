/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
import type { Meta, StoryObj } from "@storybook/react-vite";
import { Nav, Shell, SideGroup, SideItem, Crumbs } from "./Nav.js";
import { Plate, Rule } from "./Plate.js";
import { Button } from "./Button.js";
import { Card } from "./Card.js";
import { Tag, Label } from "./Tag.js";
import { Status, Metric, Meter, LogStream } from "./DataDisplay.js";
import { Terminal } from "./Terminal.js";

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
