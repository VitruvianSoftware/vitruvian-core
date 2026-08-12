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
import { Plate, Rule, VMark } from "./Plate.js";
import { Button } from "./Button.js";
import { Card } from "./Card.js";
import { Tag, Label } from "./Tag.js";
import { Status, Metric, Meter, LogStream, Table } from "./DataDisplay.js";
import { Terminal, Code } from "./Terminal.js";
import { Field, Input, Textarea, Segmented } from "./Form.js";
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
