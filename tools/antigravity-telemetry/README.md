<!--
Copyright (c) 2026 VitruvianSoftware

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
-->

# Antigravity & \`agy\` Telemetry System

A zero-dependency Python 3 telemetry exporter and lifecycle hook suite that streams real-time AI development metrics and distributed traces from Antigravity and the \`agy\` CLI to the homelab Kubernetes cluster.

---

## Architecture Overview

\`\`\`mermaid
flowchart TD
    subgraph Local["Local Machine (macOS / Linux)"]
        AGY["Antigravity IDE / agy CLI"]
        Hooks["Lifecycle Hooks / OTLP Exporter<br/>(tools/antigravity-telemetry)"]
        Settings["~/.gemini/settings.json"]
        AGY --> Settings
        Settings --> Hooks
    end

    subgraph Homelab["Homelab K3s Cluster"]
        OTel["OTel Collector<br/>(https://otel.lab.ipv1337.dev)"]
        Tempo[("Tempo<br/>Traces")]
        Prom[("Prometheus / Thanos<br/>Metrics")]
        Grafana["Grafana: Antigravity & AGY Telemetry<br/>(UID: antigravity)"]

        Hooks -->|"OTLP HTTP/JSON (Tailnet)"| OTel
        OTel -->|"Traces Pipeline"| Tempo
        OTel -->|"Prometheus Remote-Write"| Prom
        Prom --> Grafana
        Tempo --> Grafana
    end
\`\`\`

---

## Grafana Dashboard Layout

\`\`\`mermaid
flowchart TB
    subgraph Dashboard["Grafana Dashboard: Antigravity & AGY Telemetry (UID: antigravity)"]
        direction TB
        HostSelector["Top Filter: Host Dropdown (\$host: All | james-mbp32 | fedora | ...)"]

        subgraph Section1["1. Token Economy"]
            T1["Cumulative Input Tokens"]
            T2["Cumulative Output Tokens"]
            T3["Cumulative Thinking Tokens"]
            T4["Cumulative Cached Tokens"]
            T5["Token Consumption Rate (tokens/sec)"]
        end

        subgraph Section2["2. Model & Cost Distribution"]
            M1["Token Usage by Model (Donut)"]
            M2["Model API Invocations (Timeseries)"]
        end

        subgraph Section3["3. Tool & MCP Execution"]
            L1["Tool Execution Throughput (calls/min)"]
            L2["P50 / P95 / P99 Latency per Tool (ms)"]
            L3["Tool Success vs Failure Rates"]
        end

        subgraph Section4["4. Session & Multi-Agent Activity"]
            S1["Active & Completed Sessions"]
            S2["Turn Duration & Concurrency"]
        end

        subgraph Section5["5. Distributed Tracing (Tempo TraceQL)"]
            Tr1["Live Trace Waterfall Table: {resource.service.name=~'antigravity|agy'}"]
        end

        HostSelector --> Section1
        HostSelector --> Section2
        HostSelector --> Section3
        HostSelector --> Section4
        HostSelector --> Section5
    end
\`\`\`

---

## Quickstart

### 1. Configure Host Telemetry
Run \`setup\` on any developer host running Antigravity or \`agy\`:
\`\`\`bash
bazel run //tools/antigravity-telemetry -- setup
\`\`\`
This performs:
- Configures \`otlpEndpoint: "https://otel.lab.ipv1337.dev"\` in \`~/.gemini/settings.json\`.
- Installs and registers fail-open lifecycle hooks for \`AfterModel\`, \`BeforeTool\`, \`AfterTool\`, and \`AfterAgent\` in \`~/.gemini/hooks/telemetry_hook.py\`.

### 2. Verify Telemetry Health
Check network connectivity and endpoint status:
\`\`\`bash
bazel run //tools/antigravity-telemetry -- status
\`\`\`

### 3. Emit Test Telemetry
\`\`\`bash
bazel run //tools/antigravity-telemetry -- emit \\
  --tokens-input 10000 \\
  --tokens-output 2500 \\
  --tokens-thinking 600 \\
  --tokens-cached 40000 \\
  --model gemini-3.7-flash \\
  --tool run_command \\
  --tool-latency-ms 180
\`\`\`

---

## Metrics Reference

| Metric Name | Type | Labels | Description |
| :--- | :--- | :--- | :--- |
| \`antigravity_token_usage_total\` | Counter | \`host\`, \`model\`, \`token_type\` (\`input\`, \`output\`, \`thinking\`, \`cached\`) | Cumulative tokens consumed |
| \`antigravity_tool_calls_total\` | Counter | \`host\`, \`tool_name\`, \`status\` (\`success\`, \`error\`) | Total tool executions |
| \`antigravity_tool_latency_ms_bucket\` | Histogram | \`host\`, \`tool_name\`, \`le\` | Tool execution latency in milliseconds |
| \`antigravity_sessions_total\` | Counter | \`host\`, \`status\` (\`started\`, \`completed\`, \`error\`) | Antigravity / \`agy\` sessions |
| \`antigravity_subagents_spawned_total\` | Counter | \`host\`, \`role\`, \`model\` | Spawned subagents count |
