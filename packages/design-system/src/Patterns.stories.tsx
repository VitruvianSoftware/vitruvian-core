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
import * as React from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { Nav, Shell, SideGroup, SideItem, Crumbs } from "./Nav.js";
import { Plate, Rule, VMark, Glass } from "./Plate.js";
import { Button } from "./Button.js";
import { Card } from "./Card.js";
import { Tag, Label } from "./Tag.js";
import {
  Status,
  Metric,
  Meter,
  SegBar,
  Spark,
  LogStream,
  Table,
} from "./DataDisplay.js";
import type { LogLevel } from "./DataDisplay.js";
import { Terminal, Code } from "./Terminal.js";
import { Field, Input, Textarea, Segmented, Select, Switch } from "./Form.js";
import { Banner } from "./Overlay.js";

const patternsMeta: Meta = {
  title: "Patterns/Page Layouts",
  parameters: { layout: "fullscreen" },
};
export default patternsMeta;

/** Operations Console — a whole screen composed only from system primitives. */
export const OperationsConsole: StoryObj = {
  render: () => (
    <div style={{ background: "var(--color-bg)", minHeight: "100vh" }}>
      <Nav
        brand="VITRUVIAN · CONSOLE"
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

/** OAuth Inspector — dual-column workspace layout for identity inspection. */
export const OAuthInspector: StoryObj = {
  render: () => (
    <div style={{ background: "var(--color-bg)", minHeight: "100vh" }}>
      <Nav
        brand="VITRUVIAN · INSPECTOR"
        actions={
          <div className="flex items-center gap-3">
            <Tag tone="ok">Safe Mode: ON</Tag>
            <Button size="sm" variant="ghost">
              Sign Out
            </Button>
          </div>
        }
      >
        <a href="#" aria-current="page">
          Token Inspector
        </a>
        <a href="#">API Explorer</a>
        <a href="#">Snippets</a>
      </Nav>
      <Shell
        side={
          <>
            <SideGroup>Identity</SideGroup>
            <SideItem href="#" current>
              Active Session
            </SideItem>
            <SideItem href="#">Stored Credentials</SideItem>
            <SideItem href="#">OAuth Callbacks</SideItem>
            <SideGroup>Tools</SideGroup>
            <SideItem href="#">API Explorer</SideItem>
            <SideItem href="#">Code Generator</SideItem>
          </>
        }
      >
        <Crumbs>
          <a href="#">identity</a> /{" "}
          <span className="dim">token inspection</span>
        </Crumbs>
        <div className="flex items-baseline justify-between mt-4">
          <h2 className="m-0">OAuth Token & Claims Inspector</h2>
          <div className="flex gap-3 items-center">
            <Status signal="ok">Token Valid</Status>
            <Tag tone="accent">JWT / RS256</Tag>
          </div>
        </div>
        <Rule />

        <div className="grid grid-cols-12 gap-5 mt-4">
          {/* Left Column: Decoded Payload & Claims */}
          <div className="col-span-7 space-y-5">
            <Card kicker="JWT Payload" title="Decoded Token Claims">
              <Code className="text-xs p-3">
                {`{
  "iss": "https://auth.vitruvian.dev/",
  "sub": "usr_99812401a",
  "aud": "api.vitruvian.dev",
  "exp": 1770854400,
  "user": {
    "email": "james.nguyen@flyr.com",
    "roles": ["admin", "developer"]
  }
}`}
              </Code>
            </Card>

            <Plate className="p-4 space-y-3">
              <Label accent>Verified Claim Attributes</Label>
              <Table>
                <thead>
                  <tr>
                    <th>Claim</th>
                    <th>Value</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td className="font-mono text-xs">iss</td>
                    <td>https://auth.vitruvian.dev/</td>
                    <td>
                      <Tag tone="ok">Valid</Tag>
                    </td>
                  </tr>
                  <tr>
                    <td className="font-mono text-xs">sub</td>
                    <td>usr_99812401a</td>
                    <td>
                      <Tag tone="neutral">Mapped</Tag>
                    </td>
                  </tr>
                  <tr>
                    <td className="font-mono text-xs">exp</td>
                    <td>2026-08-12 00:00:00 UTC</td>
                    <td>
                      <Tag tone="ok">Active</Tag>
                    </td>
                  </tr>
                </tbody>
              </Table>
            </Plate>
          </div>

          {/* Right Column: User Profile & Quick Actions */}
          <div className="col-span-5 space-y-5">
            <Card
              kicker="Active Identity"
              title="james.nguyen@flyr.com"
              meta="GitHub OAuth2 · Authenticated 4m ago"
            >
              <div className="flex gap-2 my-2">
                <Tag tone="accent">Admin</Tag>
                <Tag tone="ok">SSO Active</Tag>
                <Tag tone="neutral">2FA Verified</Tag>
              </div>
              <p className="text-xs text-steel-dim mt-3">
                Principal tied to organization VitruvianSoftware with write
                permissions across core repos.
              </p>
            </Card>

            <Plate className="p-4 space-y-3">
              <Label>Granted Scopes</Label>
              <div className="flex flex-wrap gap-2">
                <Tag tone="outline">read:user</Tag>
                <Tag tone="outline">user:email</Tag>
                <Tag tone="outline">repo:invite</Tag>
                <Tag tone="outline">org:read</Tag>
              </div>
              <Rule />
              <div className="flex gap-2">
                <Button size="sm" variant="ghost">
                  Copy JWT
                </Button>
                <Button size="sm" variant="danger">
                  Revoke Token
                </Button>
              </div>
            </Plate>
          </div>
        </div>
      </Shell>
    </div>
  ),
};

/** Authentication Portal — centered card layout for login & PAT entry. */
export const AuthenticationPortal: StoryObj = {
  render: function Render() {
    const [provider, setProvider] = React.useState("github");
    return (
      <div
        style={{ background: "var(--color-bg)", minHeight: "100vh" }}
        className="p-8"
      >
        <Plate field="lg" className="max-w-xl mx-auto p-8 my-10">
          <div className="flex items-center gap-3 mb-4">
            <VMark size={28} className="text-steel-text" />
            <div>
              <h2 className="m-0 text-lg font-mono tracking-tight">
                VITRUVIAN CORE
              </h2>
              <Label>Identity & Access Management</Label>
            </div>
          </div>

          <Banner tone="info" className="mb-6">
            Local development mode active. Callback endpoint set to{" "}
            <code className="text-xs">http://localhost:8080/callback</code>
          </Banner>

          <Segmented
            name="auth_provider"
            value={provider}
            onValueChange={setProvider}
            options={[
              { value: "github", label: "GitHub" },
              { value: "google", label: "Google" },
              { value: "auth0", label: "Auth0" },
              { value: "pat", label: "Token PAT" },
            ]}
          />

          <div className="space-y-4 my-6">
            <Field label="Client ID" hint="Registered OAuth application ID">
              <Input defaultValue="gh_app_89f13a02b1c4" />
            </Field>

            <Field
              label="Client Secret"
              hint="Keep confidential — stored in session only"
            >
              <Input type="password" defaultValue="secret_key_placeholder" />
            </Field>

            <Field
              label="Requested Scopes"
              hint="Space-separated OAuth scope list"
            >
              <Input defaultValue="read:user user:email repo:invite" />
            </Field>
          </div>

          <div className="space-y-3">
            <Button variant="primary" block registered>
              Initiate {provider.toUpperCase()} OAuth Flow
            </Button>
            <Button variant="ghost" block>
              Use Stored Session Credentials
            </Button>
          </div>

          <Rule marked />

          <div className="mt-4">
            <Label>Alternative Auth Method</Label>
            <div className="flex gap-2 mt-2">
              <Input
                placeholder="Paste Personal Access Token (ghp_...)"
                className="flex-1"
              />
              <Button variant="secondary" size="sm">
                Auth with PAT
              </Button>
            </div>
          </div>
        </Plate>
      </div>
    );
  },
};

/** Agent Transcript — interactive agent workspace with logs, meters, and terminal execution. */
export const AgentTranscript: StoryObj = {
  render: () => (
    <div style={{ background: "var(--color-bg)", minHeight: "100vh" }}>
      <Nav
        brand="VITRUVIAN · AGENT RUNTIME"
        actions={
          <div className="flex items-center gap-3">
            <Status signal="run">Agent Autonomous Mode</Status>
            <Button size="sm" variant="danger">
              Halt Agent
            </Button>
          </div>
        }
      >
        <a href="#" aria-current="page">
          Exec Transcript
        </a>
        <a href="#">Agent Fleet</a>
        <a href="#">Tool Registry</a>
      </Nav>
      <Shell
        side={
          <>
            <SideGroup>Active Subagents</SideGroup>
            <SideItem href="#" current>
              scout-bot (pro)
            </SideItem>
            <SideItem href="#">builder-agent (pro)</SideItem>
            <SideItem href="#">test-runner (flash)</SideItem>
            <SideGroup>Tasks</SideGroup>
            <SideItem href="#">#1551 PR Monitor</SideItem>
            <SideItem href="#">#1548 Tidy Check</SideItem>
          </>
        }
      >
        <Crumbs>
          <a href="#">agents</a> / <a href="#">scout-bot</a> /{" "}
          <span className="dim">task-8912</span>
        </Crumbs>
        <div className="flex items-baseline justify-between mt-4">
          <h2 className="m-0">Agent Execution Workspace</h2>
          <div className="flex gap-3">
            <Tag tone="accent">pro-model</Tag>
            <Tag tone="ok">3 workers active</Tag>
          </div>
        </div>
        <Rule />

        <div className="grid grid-cols-3 gap-4 my-4">
          <Plate className="card">
            <Metric
              label="Tokens Consumed"
              value="14,210"
              delta="-22% vs limit"
            />
          </Plate>
          <Plate className="card">
            <Metric
              label="Tool Invocations"
              value="48"
              delta="12 files, 4 commands"
            />
          </Plate>
          <Plate className="card">
            <Metric label="Task Completion" value="85%" />
            <Meter value={0.85} />
          </Plate>
        </div>

        <div className="grid grid-cols-12 gap-5 mt-5">
          <div className="col-span-8 space-y-4">
            <Plate className="p-4 space-y-2">
              <Label accent>Execution Transcript</Label>
              <Terminal
                framed={false}
                lines={[
                  {
                    kind: "cmd",
                    text: "bazel build //oauth-user-inspector/...",
                  },
                  {
                    kind: "ok",
                    text: "Target //oauth-user-inspector:app up to date",
                  },
                  { kind: "cmd", text: "gh pr checks 1551 --watch" },
                  {
                    kind: "warn",
                    text: "! tidy-check pending — formatting pass required",
                  },
                  { kind: "cmd", text: "bazel run //:tidy" },
                  {
                    kind: "ok",
                    text: "Formatting complete. 0 lint issues remaining.",
                  },
                ]}
                cursor
              />
            </Plate>

            <Plate className="p-4 space-y-3">
              <Field label="Send Supplemental Instruction to Agent">
                <Textarea
                  placeholder="Type further instructions or tool overrides for scout-bot..."
                  rows={2}
                />
              </Field>
              <div className="flex justify-end gap-3">
                <Button size="sm" variant="ghost">
                  Pause Execution
                </Button>
                <Button size="sm" variant="primary">
                  Submit Prompt
                </Button>
              </div>
            </Plate>
          </div>

          <div className="col-span-4 space-y-4">
            <Plate className="p-4 space-y-3">
              <Label>Real-Time Activity Stream</Label>
              <LogStream
                rows={[
                  {
                    ts: "18:12:01",
                    level: "ok",
                    message: "Subagent scout-bot spawned",
                  },
                  {
                    ts: "18:12:15",
                    level: "warn",
                    message: "Formatting check required tidy run",
                  },
                  {
                    ts: "18:12:30",
                    level: "ok",
                    message: "All 20 CI checks passed green",
                  },
                  {
                    ts: "18:12:45",
                    level: "info",
                    message: "Enqueued in GitHub Merge Queue",
                  },
                ]}
              />
            </Plate>
          </div>
        </div>
      </Shell>
    </div>
  ),
};

/** Data Catalog — tabular data explorer layout for tables, metrics, and schema discovery. */
export const DataCatalog: StoryObj = {
  render: () => (
    <div style={{ background: "var(--color-bg)", minHeight: "100vh" }}>
      <Nav
        brand="VITRUVIAN · TABULA"
        actions={
          <Button size="sm" variant="primary">
            + Register Dataset
          </Button>
        }
      >
        <a href="#" aria-current="page">
          Catalog
        </a>
        <a href="#">Pipelines</a>
        <a href="#">Warehouse</a>
        <a href="#">Lineage</a>
      </Nav>
      <Shell
        side={
          <>
            <SideGroup>Databases</SideGroup>
            <SideItem href="#" current>
              Production Lake
            </SideItem>
            <SideItem href="#">Staging Lake</SideItem>
            <SideItem href="#">Analytics Sandbox</SideItem>
            <SideGroup>Schemas</SideGroup>
            <SideItem href="#">public</SideItem>
            <SideItem href="#">audit_logs</SideItem>
            <SideItem href="#">auth_system</SideItem>
          </>
        }
      >
        <Crumbs>
          <a href="#">warehouse</a> / <a href="#">production</a> /{" "}
          <span className="dim">public</span>
        </Crumbs>
        <div className="flex items-baseline justify-between mt-4">
          <h2 className="m-0">Data Asset Catalog</h2>
          <div className="flex gap-3 items-center">
            <Tag tone="neutral">PostgreSQL 16</Tag>
            <Tag tone="ok">Fresh (2m ago)</Tag>
          </div>
        </div>
        <Rule />

        <div className="flex gap-3 items-center my-4">
          <Input
            placeholder="Search tables, columns, tags..."
            className="max-w-xs"
          />
          <Segmented
            name="catalog_view"
            options={[
              { value: "tables", label: "Tables (4)" },
              { value: "views", label: "Views (12)" },
              { value: "schemas", label: "Schemas (3)" },
            ]}
          />
          <Tag tone="outline">owner: platform</Tag>
          <Button variant="ghost" size="sm" className="ml-auto">
            Export Schema
          </Button>
        </div>

        <Plate className="p-4 mt-4">
          <Table>
            <thead>
              <tr>
                <th>Table Name</th>
                <th>Owner</th>
                <th>Rows</th>
                <th>Size</th>
                <th>Freshness</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td className="font-mono text-xs font-semibold">users</td>
                <td>platform</td>
                <td>1.4M</td>
                <td>240 MB</td>
                <td>2m ago</td>
                <td>
                  <Status signal="ok">Active</Status>
                </td>
              </tr>
              <tr>
                <td className="font-mono text-xs font-semibold">
                  oauth_tokens
                </td>
                <td>security</td>
                <td>48.2k</td>
                <td>18 MB</td>
                <td>1m ago</td>
                <td>
                  <Status signal="ok">Active</Status>
                </td>
              </tr>
              <tr>
                <td className="font-mono text-xs font-semibold">
                  audit_events
                </td>
                <td>secops</td>
                <td>12.8M</td>
                <td>3.2 GB</td>
                <td>Realtime</td>
                <td>
                  <Status signal="run">Streaming</Status>
                </td>
              </tr>
              <tr>
                <td className="font-mono text-xs font-semibold">
                  legacy_sessions
                </td>
                <td>identity</td>
                <td>0</td>
                <td>0 B</td>
                <td>Deprecated</td>
                <td>
                  <Status signal="warn">Stale</Status>
                </td>
              </tr>
            </tbody>
          </Table>
        </Plate>
      </Shell>
    </div>
  ),
};

/* ------------------------------------------------------------------------ */
/* Mobile                                                                    */
/* ------------------------------------------------------------------------ */

/** A phone frame on the board. On a wide canvas (the docs page) it is the
 *  390 x 844 phone with a gutter; under the toolbar's viewport switch it is
 *  fluid, filling the iframe edge to edge so a 320px or 390px viewport shows
 *  the whole shell instead of clipping a fixed 390px plate. The plate is a
 *  container so the shell's grids respond to the frame, not the iframe. */
function PhoneFrame({ children }: { children: React.ReactNode }) {
  return (
    <div
      style={{ background: "var(--color-bg)", minHeight: "100vh" }}
      className="flex items-start justify-center p-0 sm:p-8"
    >
      <Plate className="@container overflow-hidden w-full max-w-[390px] h-[min(844px,100vh)] sm:h-[844px]">
        {children}
      </Plate>
    </div>
  );
}

const remoteTabs = [
  { id: "remote", label: "Remote" },
  { id: "media", label: "Media" },
  { id: "screen", label: "Screen" },
  { id: "agent", label: "Agent" },
];

/** Remote Console — the Android Remote's home tab: the phone as a control
 *  surface for the Mac agent. Mobile shell, status signals, a telemetry grid,
 *  widget plates, and the glass tab bar. The mobile classes (`m-*`) live here. */
export const RemoteConsole: StoryObj = {
  globals: { viewport: { value: "phone", isRotated: false } },
  render: function Render() {
    const [tab, setTab] = React.useState("remote");
    return (
      <PhoneFrame>
        <div className="m-shell" style={{ height: "100%" }}>
          <header className="m-bar">
            <VMark size={18} className="text-steel-text" />
            <h1 className="m-bar-title">Remote · nuc9i9-mac</h1>
            <Status signal="ok">Linked</Status>
          </header>

          <main className="m-body">
            <section className="m-section">
              <div className="flex flex-wrap gap-3">
                <Status signal="ok">Mac reachable</Status>
                <Status signal="run">BLE HID</Status>
                <Status signal="warn">Wi-Fi only</Status>
              </div>
            </section>

            <section className="m-section pt-0">
              <Label accent>Telemetry</Label>
              <div className="grid grid-cols-1 @[360px]:grid-cols-2 gap-3 mt-3">
                <Plate className="card p-4 min-w-0">
                  <Metric label="CPU" value="23%" delta="8 cores · M2" />
                  <Meter value={0.23} />
                </Plate>
                <Plate className="card p-4 min-w-0">
                  <Metric label="Memory" value="18.4 GB" delta="of 32 GB" />
                  <Meter value={0.58} />
                </Plate>
                <Plate className="card p-4 min-w-0">
                  <Metric label="Disk" value="71%" delta="data volume" />
                  <Meter value={0.71} tone="warn" />
                </Plate>
                <Plate className="card p-4 min-w-0">
                  <Metric label="Battery" value="94%" delta="charging" />
                  <Spark points={[3, 4, 4, 5, 6, 6, 7, 8, 8, 9, 9, 9]} />
                </Plate>
              </div>
            </section>

            <section className="m-section pt-0">
              <Label accent>Widgets</Label>
              <div className="stack-tight mt-3">
                <Plate className="card p-4">
                  <div className="flex items-baseline justify-between">
                    <span className="card-kicker">Now playing</span>
                    <Tag tone="ok">Music</Tag>
                  </div>
                  <p className="card-title">Kind of Blue</p>
                  <div className="card-meta">Miles Davis · 04:12 / 09:22</div>
                  <Meter value={0.45} />
                  <div className="flex gap-2 mt-2">
                    <Button size="sm" variant="ghost" className="btn-touch">
                      ‹‹
                    </Button>
                    <Button
                      size="sm"
                      variant="primary"
                      className="btn-touch flex-1"
                    >
                      Pause
                    </Button>
                    <Button size="sm" variant="ghost" className="btn-touch">
                      ››
                    </Button>
                  </div>
                </Plate>

                <Plate className="card p-4">
                  <div className="flex items-baseline justify-between">
                    <span className="card-kicker">Claude sessions</span>
                    <Tag tone="accent">3 live</Tag>
                  </div>
                  <SegBar total={8} filled={3} warn={1} />
                  <div className="card-meta">
                    vitruvian-core ×2 · homespeaker ×1 · 1 idle
                  </div>
                </Plate>

                <Plate className="card p-4">
                  <div className="flex items-baseline justify-between">
                    <span className="card-kicker">Screen</span>
                    <Status signal="idle">Locked</Status>
                  </div>
                  <div className="card-meta">Last input 12m ago</div>
                  <div className="flex gap-2 mt-1">
                    <Button
                      size="sm"
                      variant="secondary"
                      className="btn-touch flex-1"
                    >
                      Wake
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      className="btn-touch flex-1"
                    >
                      Screenshot
                    </Button>
                  </div>
                </Plate>
              </div>
            </section>
          </main>

          <nav className="m-tabbar" aria-label="Remote sections">
            {remoteTabs.map((t) => (
              <button
                key={t.id}
                type="button"
                className="m-tab"
                aria-current={tab === t.id ? "page" : undefined}
                onClick={() => setTab(t.id)}
              >
                <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden>
                  <rect
                    x="1.5"
                    y="1.5"
                    width="15"
                    height="15"
                    fill="none"
                    stroke="currentColor"
                  />
                  <circle
                    cx="9"
                    cy="9"
                    r="4"
                    fill={tab === t.id ? "currentColor" : "none"}
                    stroke="currentColor"
                  />
                </svg>
                {t.label}
              </button>
            ))}
          </nav>
        </div>
      </PhoneFrame>
    );
  },
};

/* ------------------------------------------------------------------------ */
/* Control surface                                                           */
/* ------------------------------------------------------------------------ */

const speakerRooms = [
  "Master Bedroom",
  "Living Room",
  "Kitchen",
  "Dining Room",
  "Guest Room",
  "All",
];

type Transmission = {
  ts: string;
  level: LogLevel;
  message: React.ReactNode;
  isNew?: boolean;
};

/** Cast Controller — the Home Speaker broadcast surface. Every control here is
 *  live: pick a room, arm or disarm broadcasts, set volume, and each send is
 *  appended to the transmission log. Quiet hours surface as a banner, never
 *  as a silently-dropped message. */
export const CastController: StoryObj = {
  render: function Render() {
    const [room, setRoom] = React.useState("Living Room");
    const [enabled, setEnabled] = React.useState(true);
    const [volume, setVolume] = React.useState(40);
    const [quiet, setQuiet] = React.useState(false);
    const [log, setLog] = React.useState<Transmission[]>([
      {
        ts: "17:21:08",
        level: "ok",
        message: "Living Room ← “PR #2513 merged, all databases healthy”",
      },
      {
        ts: "16:58:41",
        level: "ok",
        message: "Kitchen ← “Timer done”",
      },
      {
        ts: "07:02:13",
        level: "warn",
        message: "Master Bedroom — suppressed, quiet hours until 08:00",
      },
    ]);

    const send = () => {
      const ts = new Date().toTimeString().slice(0, 8);
      const row: Transmission = quiet
        ? {
            ts,
            level: "warn",
            message: `${room} — suppressed, quiet hours active`,
            isNew: true,
          }
        : enabled
          ? {
              ts,
              level: "ok",
              message: `${room} ← “Test broadcast at ${volume}% volume”`,
              isNew: true,
            }
          : {
              ts,
              level: "err",
              message: `${room} — broadcasts disabled, nothing sent`,
              isNew: true,
            };
      setLog((rows) => [row, ...rows.map((r) => ({ ...r, isNew: false }))]);
    };

    return (
      <div style={{ background: "var(--color-bg)", minHeight: "100vh" }}>
        <Nav
          brand="VITRUVIAN · HOME SPEAKER"
          actions={
            <div className="flex items-center gap-3">
              <Status signal={enabled ? "ok" : "idle"}>
                {enabled ? "Broadcast armed" : "Broadcast off"}
              </Status>
              <Button size="sm" variant="ghost">
                Sign Out
              </Button>
            </div>
          }
        >
          <a href="#" aria-current="page">
            Cast
          </a>
          <a href="#">Devices</a>
          <a href="#">History</a>
        </Nav>

        <div className="wrap py-6">
          <div className="flex items-baseline justify-between">
            <h2 className="m-0">Cast Controller</h2>
            <div className="flex gap-3 items-center">
              <Tag tone="neutral">{speakerRooms.length - 1} speakers</Tag>
              <Tag tone={quiet ? "warn" : "ok"}>
                {quiet ? "Quiet hours" : "Open hours"}
              </Tag>
            </div>
          </div>
          <Rule />

          {quiet ? (
            <Banner tone="warn" className="mb-5">
              Quiet hours are active (22:00 – 08:00). Broadcasts are logged but
              not spoken until the window closes.
            </Banner>
          ) : null}

          <div className="grid grid-cols-12 gap-5">
            <Plate field="sm" className="col-span-5 p-5 space-y-5">
              <Label accent>Target</Label>
              <Field
                label="Speaker"
                hint="Resolved live from speaker_broadcast.json"
              >
                <Select value={room} onChange={(e) => setRoom(e.target.value)}>
                  {speakerRooms.map((r) => (
                    <option key={r} value={r}>
                      {r}
                    </option>
                  ))}
                </Select>
              </Field>

              <Segmented
                name="cast_mode"
                value={quiet ? "quiet" : "open"}
                onValueChange={(v) => setQuiet(v === "quiet")}
                options={[
                  { value: "open", label: "Open hours" },
                  { value: "quiet", label: "Simulate quiet hours" },
                ]}
              />

              <Rule />

              <Switch
                label="Broadcasts enabled"
                checked={enabled}
                onChange={(e) => setEnabled(e.target.checked)}
              />

              <div>
                <div className="flex items-baseline justify-between">
                  <Label>Volume</Label>
                  <span className="num text-sm">{volume}%</span>
                </div>
                <input
                  type="range"
                  min={0}
                  max={100}
                  value={volume}
                  onChange={(e) => setVolume(Number(e.target.value))}
                  aria-label="Broadcast volume"
                  className="w-full mt-2"
                  style={{ accentColor: "var(--color-accent)" }}
                />
                <Meter
                  value={volume / 100}
                  tone={volume > 80 ? "warn" : undefined}
                />
              </div>

              <div className="flex gap-2">
                <Button variant="primary" registered onClick={send}>
                  Send test broadcast
                </Button>
                <Button variant="ghost" onClick={() => setVolume(40)}>
                  Reset
                </Button>
              </div>
            </Plate>

            <div className="col-span-7 space-y-5">
              <div className="grid grid-cols-3 gap-5">
                <Plate className="card">
                  <Metric
                    label="Sent today"
                    value="14"
                    delta="+3 vs yesterday"
                  />
                </Plate>
                <Plate className="card">
                  <Metric label="Suppressed" value="2" delta="quiet hours" />
                </Plate>
                <Plate className="card">
                  <Metric label="Target" value={room} />
                </Plate>
              </div>

              <Plate className="p-4 space-y-3">
                <div className="flex items-baseline justify-between">
                  <Label>Transmission log</Label>
                  <Tag tone="outline">{log.length} rows</Tag>
                </div>
                <LogStream rows={log} />
              </Plate>
            </div>
          </div>
        </div>
      </div>
    );
  },
};

/* ------------------------------------------------------------------------ */
/* Overlay                                                                   */
/* ------------------------------------------------------------------------ */

type HudContact = {
  id: string;
  x: number;
  y: number;
  label: string;
  signal: "ok" | "warn" | "crit";
};

/** Non-empty by type, so the "selected" fallback is always a real contact. */
const hudContacts: readonly [HudContact, ...HudContact[]] = [
  { id: "c1", x: 62, y: 38, label: "ALPHA", signal: "ok" },
  { id: "c2", x: 31, y: 61, label: "BRAVO", signal: "warn" },
  { id: "c3", x: 78, y: 72, label: "ECHO", signal: "crit" },
];

/** Situational HUD — glass panels floating over a live canvas. Glass is the
 *  only elevation the language permits, and this is the one place several
 *  panes of it share a view. The ground is always the board: a HUD over a
 *  camera or map never inverts to parchment, so the theme is pinned here. */
export const SituationalHUD: StoryObj = {
  render: function Render() {
    const [selected, setSelected] = React.useState("c1");
    const contact =
      hudContacts.find((c) => c.id === selected) ?? hudContacts[0];
    return (
      <div
        data-theme="dark"
        className="relative overflow-hidden"
        style={{
          background: "var(--color-bg)",
          color: "var(--color-text)",
          height: "100vh",
          minHeight: 640,
        }}
      >
        {/* Ground: the ruled field plus a sparse vector canvas. */}
        <div className="absolute inset-0 grid-field-lg" aria-hidden />
        <svg
          className="absolute inset-0 w-full h-full"
          viewBox="0 0 100 100"
          preserveAspectRatio="none"
          aria-hidden
        >
          <circle
            cx="50"
            cy="50"
            r="34"
            fill="none"
            stroke="var(--color-divider)"
            strokeWidth="0.2"
          />
          <circle
            cx="50"
            cy="50"
            r="18"
            fill="none"
            stroke="var(--color-divider)"
            strokeWidth="0.2"
          />
          <line
            x1="50"
            y1="4"
            x2="50"
            y2="96"
            stroke="var(--color-line)"
            strokeWidth="0.15"
          />
          <line
            x1="4"
            y1="50"
            x2="96"
            y2="50"
            stroke="var(--color-line)"
            strokeWidth="0.15"
          />
          <path
            d="M 12 84 L 31 61 L 50 50 L 62 38 L 88 18"
            fill="none"
            stroke="var(--color-accent)"
            strokeWidth="0.25"
            strokeDasharray="1 1"
          />
        </svg>

        {/* Contacts: plain buttons so the canvas stays keyboard-reachable. */}
        {hudContacts.map((c) => (
          <button
            key={c.id}
            type="button"
            onClick={() => setSelected(c.id)}
            aria-pressed={selected === c.id}
            aria-label={`Contact ${c.label}`}
            className="absolute flex items-center gap-2 bg-transparent border-0 p-0 cursor-pointer"
            style={{
              left: `${c.x}%`,
              top: `${c.y}%`,
              transform: "translate(-50%, -50%)",
            }}
          >
            <Status signal={c.signal}>{c.label}</Status>
          </button>
        ))}

        {/* Top-left: mission telemetry. */}
        <Glass className="absolute top-5 left-5 p-4 space-y-3 w-64">
          <div className="flex items-center gap-2">
            <VMark size={14} className="text-steel-text" />
            <Label accent>God's Eye · Irvine</Label>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Metric label="Contacts" value="3" delta="1 critical" down />
            <Metric label="Link" value="42ms" delta="tailnet" />
          </div>
          <Meter value={0.42} />
        </Glass>

        {/* Top-right: progress chips. */}
        <Glass className="absolute top-5 right-5 p-3 space-y-2 w-56">
          <Label>Objectives</Label>
          {[
            { name: "Sweep sector 2", v: 1 },
            { name: "Relay uplink", v: 0.66 },
            { name: "Recover BRAVO", v: 0.2 },
          ].map((o) => (
            <div
              key={o.name}
              className="flex items-center gap-3 border border-hairline px-3 py-2"
            >
              <span className="text-xs flex-1">{o.name}</span>
              <span className="num text-xs dim">{Math.round(o.v * 100)}%</span>
              <div className="w-12">
                <Meter value={o.v} />
              </div>
            </div>
          ))}
        </Glass>

        {/* Bottom-left: the selected contact. */}
        <Glass className="absolute bottom-16 left-5 p-4 space-y-3 w-72">
          <div className="flex items-baseline justify-between">
            <span className="card-kicker">Contact · {contact.label}</span>
            <Status signal={contact.signal}>
              {contact.signal === "ok"
                ? "Nominal"
                : contact.signal === "warn"
                  ? "Degraded"
                  : "Distress"}
            </Status>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div>
              <Label>Bearing</Label>
              <div className="num text-sm">{(contact.x * 3.6).toFixed(0)}°</div>
            </div>
            <div>
              <Label>Range</Label>
              <div className="num text-sm">
                {((contact.y / 10) * 1.3).toFixed(1)} km
              </div>
            </div>
            <div>
              <Label>Last seen</Label>
              <div className="num text-sm">00:04</div>
            </div>
          </div>
          <div className="flex gap-2 flex-wrap">
            <Tag tone="outline">esp32-s3</Tag>
            <Tag tone={contact.signal === "crit" ? "sanguine" : "accent"}>
              {contact.signal === "crit" ? "beacon" : "telemetry"}
            </Tag>
          </div>
          <div className="flex gap-2">
            <Button size="sm" variant="primary">
              Track
            </Button>
            <Button size="sm" variant="ghost">
              Hail
            </Button>
          </div>
        </Glass>

        {/* Bottom: the telemetry strip. */}
        <Glass className="absolute bottom-0 left-0 right-0 flex items-center gap-6 px-5 py-3">
          {[
            ["LAT", "33.6846 N"],
            ["LON", "117.8265 W"],
            ["ALT", "18 m"],
            ["HDG", "042°"],
            ["SPD", "1.4 m/s"],
            ["UTC", "00:41:07"],
          ].map(([k, v]) => (
            <div key={k} className="flex items-baseline gap-2">
              <Label>{k}</Label>
              <span className="num text-sm">{v}</span>
            </div>
          ))}
          <div className="ml-auto flex items-center gap-3">
            <Status signal="run">Recording</Status>
            <Tag tone="ok">GPS 11 sat</Tag>
          </div>
        </Glass>
      </div>
    );
  },
};
