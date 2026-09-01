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

# Antigravity & `agy` Observability Guide

This guide documents the architecture, ingestion pipeline, and Grafana visualization for Antigravity IDE and `agy` CLI telemetry in the Vitruvian homelab.

---

## 1. End-to-End Telemetry Pipeline

```mermaid
flowchart TD
    subgraph Client["Developer Workstations (Option 2 Default)"]
        AGY["Antigravity IDE / agy CLI"]
        Loader["Self-Updating Loader Hook<br/>(~/.gemini/hooks/telemetry_hook.py)"]
        Engine["Cached Engine<br/>(~/.gemini/hooks/.engine.py)"]
        
        AGY --> Loader
        Loader -->|"1. Run fast cached engine"| Engine
        Loader -.->|"2. Background 24h auto-refresh"| GH["GitHub Raw (main branch)"]
    end

    subgraph Homelab["Homelab Kubernetes Cluster (Option 1 Server-Side)"]
        OTel["OTel Collector Contrib"]
        SpanMetrics["spanmetrics connector<br/>(Calculates Latencies & Call Rates)"]
        Tempo[("Tempo<br/>Traces")]
        Prom[("Prometheus / Thanos<br/>Metrics")]
        Grafana["Grafana: Antigravity & AGY Telemetry"]

        Engine -->|"OTLP Events (Tailnet)"| OTel
        AGY -.->|"Direct OTLP Traces (Zero Hook)"| OTel
        OTel -->|"Traces Pipeline"| Tempo
        OTel -->|"Traces Pipeline"| SpanMetrics
        SpanMetrics -->|"Synthesized Metrics"| Prom
        OTel -->|"Metrics Remote-Write"| Prom
        Prom --> Grafana
        Tempo --> Grafana
    end
```

---

## 2. Grafana Dashboard Architecture

```mermaid
flowchart TB
    subgraph Dashboard["Grafana Dashboard: Antigravity and AGY Telemetry (UID: antigravity)"]
        direction TB
        HostSelector["Top Filter: Host Dropdown ($host: All, james-mbp32, fedora)"]

        subgraph Section1["1. Token Economy"]
            T1["Cumulative Input Tokens"]
            T2["Cumulative Output Tokens"]
            T3["Cumulative Thinking Tokens"]
            T4["Cumulative Cached Tokens"]
            T5["Token Consumption Rate (tokens/sec)"]
        end

        subgraph Section2["2. Model and Cost Distribution"]
            M1["Token Usage by Model (Donut)"]
            M2["Model API Invocations (Timeseries)"]
        end

        subgraph Section3["3. Tool and MCP Execution"]
            L1["Tool Execution Throughput (calls/min)"]
            L2["P50 / P95 / P99 Latency per Tool (ms)"]
            L3["Tool Success vs Failure Rates"]
        end

        subgraph Section4["4. Session and Multi-Agent Activity"]
            S1["Active and Completed Sessions"]
            S2["Turn Duration and Concurrency"]
        end

        subgraph Section5["5. Distributed Tracing (Tempo TraceQL)"]
            Tr1["Live Trace Waterfall Table (service.name: antigravity, agy)"]
        end

        HostSelector --> T1
        HostSelector --> M1
        HostSelector --> L1
        HostSelector --> S1
        HostSelector --> Tr1
    end
```

---

## 3. Multi-Host Configuration (Repository Checkout)

To enable telemetry on any machine with `vitruvian-core` checked out:

```bash
# 1. Register lifecycle hooks, loader, and OTLP endpoint
bazel run //tools/antigravity-telemetry -- setup

# 2. Check health and connectivity
bazel run //tools/antigravity-telemetry -- status
```

---

## 4. Zero-Clone Setup Prompts for Agents

Choose the architecture that best fits your requirements:

### Architecture Comparison & Decision Guide

| Criteria | Option 2 (Default / Recommended) | Option 1 (Zero-Script Minimalist) |
| :--- | :--- | :--- |
| **Ingestion Mechanism** | Self-Updating Remote Loader Hook | Native OTLP Traces in `settings.json` |
| **Client Files on Disk** | 15-line loader script + local engine cache | **Zero scripts (pure JSON settings)** |
| **Token Breakdown Metrics** | **Full** (input, output, thinking, cached) | Not exported natively |
| **Tool Latency & Quantiles** | **Full** (P50, P95, P99 per tool) | Span-derived via `spanmetrics` |
| **Subagent Concurrency** | **Full** (tracks spawns & active agents) | Trace span count |
| **Auto-Update Behavior** | Non-blocking background sync (24h TTL) | Instant (100% server-side in K8s) |

---

### 4.1 Option 2 Prompt (Default): Self-Updating Remote Loader Hook

Copy and paste this prompt into an `agy` or Antigravity session on a new or unconfigured host. The agent will autonomously install the loader, pre-seed the engine cache, configure settings, and self-verify:

````markdown
Configure this machine to automatically stream Antigravity / `agy` session and token telemetry to our homelab OpenTelemetry collector using the self-updating loader architecture.

Execute all of the following autonomously:
1. Create `~/.gemini/hooks/telemetry_hook.py` (executable with `chmod +x`) as the self-updating loader shim:

```python
#!/usr/bin/env python3
"""Self-Updating Remote Loader Shim for Antigravity & agy Telemetry Hooks."""
import os
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

RAW_HOOK_URL = os.environ.get(
    "ANTIGRAVITY_HOOK_SOURCE_URL",
    "https://raw.githubusercontent.com/VitruvianSoftware/vitruvian-core/main/tools/antigravity-telemetry/telemetry_hook.py",
)
CACHE_DIR = os.path.expanduser("~/.gemini/hooks")
CACHE_FILE = os.path.join(CACHE_DIR, ".engine.py")
CACHE_TTL_SECONDS = 86400  # 24 hours

def _download_engine(target_path: str, timeout: float = 2.0) -> bool:
    tmp_path = f"{target_path}.tmp.{os.getpid()}"
    try:
        req = urllib.request.Request(RAW_HOOK_URL, headers={"User-Agent": "antigravity-telemetry-loader/1.0.0"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if resp.status == 200:
                content = resp.read()
                if b"process_event" in content:
                    os.makedirs(os.path.dirname(target_path), exist_ok=True)
                    with open(tmp_path, "wb") as f:
                        f.write(content)
                    os.chmod(tmp_path, 0o755)
                    os.replace(tmp_path, target_path)
                    return True
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except Exception:
                pass
    return False

def _refresh_in_background(target_path: str) -> None:
    t = threading.Thread(target=_download_engine, args=(target_path, 3.0), daemon=True)
    t.start()

def main() -> None:
    raw_input = ""
    try:
        raw_input = sys.stdin.read()
    except Exception:
        pass

    cache_exists = os.path.exists(CACHE_FILE) and os.path.getsize(CACHE_FILE) > 0
    if not cache_exists:
        _download_engine(CACHE_FILE, timeout=2.0)
    elif time.time() - os.path.getmtime(CACHE_FILE) > CACHE_TTL_SECONDS:
        _refresh_in_background(CACHE_FILE)

    if os.path.exists(CACHE_FILE) and os.path.getsize(CACHE_FILE) > 0:
        try:
            res = subprocess.run(
                [sys.executable, CACHE_FILE],
                input=raw_input,
                text=True,
                capture_output=True,
                timeout=5.0,
            )
            if res.stdout:
                sys.stdout.write(res.stdout)
                sys.stdout.flush()
                sys.exit(res.returncode)
        except Exception:
            pass

    # Fail-open: always return {"decision": "allow"} to avoid tool gating deadlocks
    sys.stdout.write("{\"decision\": \"allow\"}\n")
    sys.stdout.flush()
    sys.exit(0)

if __name__ == "__main__":
    main()
```

2. Pre-seed `~/.gemini/hooks/.engine.py` immediately from GitHub raw:
   Download `https://raw.githubusercontent.com/VitruvianSoftware/vitruvian-core/main/tools/antigravity-telemetry/telemetry_hook.py` to `~/.gemini/hooks/.engine.py` (`chmod +x`).

3. Update `~/.gemini/settings.json` (preserve existing settings):
   - Set `"telemetry": { "enabled": true, "useCollector": true, "otlpEndpoint": "https://otel.lab.ipv1337.dev", "otlpProtocol": "http", "traces": true }`.
   - Register `"~/.gemini/hooks/telemetry_hook.py"` under `"hooks"` ONLY for post-execution events: `AfterModel`, `AfterTool`, and `AfterAgent` (or `PostInvocation`, `PostToolUse`, `Stop`). Ensure `BeforeTool` / `PreToolUse` is not registered.

4. Self-verify:
   - Check that `~/.gemini/hooks/telemetry_hook.py` and `~/.gemini/hooks/.engine.py` exist and are executable.
   - Run `printf '{"hook_event":"AfterAgent","status":"completed"}' | ~/.gemini/hooks/telemetry_hook.py` and verify it exits 0 and outputs `{"decision": "allow"}`.
   - Verify connectivity to `https://otel.lab.ipv1337.dev/v1/metrics` returning HTTP 200.

5. Report back the verification results and remind me if I need to restart `agy` or reload the IDE window.
````

---

### 4.2 Option 1 Prompt: Zero-Script Pure Native OTLP Configuration

Copy and paste this prompt into an `agy` or Antigravity session if you want a **pure configuration-only setup with zero local hook files on disk**:

````markdown
Configure this machine to stream native Antigravity / `agy` OTLP traces and events directly to our homelab OpenTelemetry collector without any local hook scripts.

Execute all of the following autonomously:
1. Clean up any local telemetry hook scripts:
   - Remove `~/.gemini/hooks/telemetry_hook.py` and `~/.gemini/hooks/.engine.py` if they exist.

2. Update `~/.gemini/settings.json` (preserve existing settings):
   - Set `"telemetry": { "enabled": true, "useCollector": true, "otlpEndpoint": "https://otel.lab.ipv1337.dev", "otlpProtocol": "http", "traces": true }`.
   - Remove any `"telemetry-hook"` entries or telemetry references from `"hooks"`.

3. Self-verify:
   - Verify `~/.gemini/settings.json` is valid JSON and contains the `otlpEndpoint`.
   - Verify connectivity by running a test HTTP POST to `https://otel.lab.ipv1337.dev/v1/traces` returning HTTP 200.

4. Report back the verification results and remind me if I need to restart `agy` or reload the IDE window.
````

---

### 4.3 Upgrade Prompt for Previously Configured Hosts

If a host was previously configured with legacy static hook scripts (e.g. `james-mbp32`, `james-mbp`), paste this prompt to seamlessly upgrade it to Option 2 without breaking active sessions:

````markdown
Upgrade our Antigravity / `agy` telemetry configuration on this machine to the new self-updating remote loader architecture.

Execute all of the following autonomously:
1. Overwrite `~/.gemini/hooks/telemetry_hook.py` with the self-updating loader shim (`chmod +x`):

```python
#!/usr/bin/env python3
"""Self-Updating Remote Loader Shim for Antigravity & agy Telemetry Hooks."""
import os
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

RAW_HOOK_URL = os.environ.get(
    "ANTIGRAVITY_HOOK_SOURCE_URL",
    "https://raw.githubusercontent.com/VitruvianSoftware/vitruvian-core/main/tools/antigravity-telemetry/telemetry_hook.py",
)
CACHE_DIR = os.path.expanduser("~/.gemini/hooks")
CACHE_FILE = os.path.join(CACHE_DIR, ".engine.py")
CACHE_TTL_SECONDS = 86400  # 24 hours

def _download_engine(target_path: str, timeout: float = 2.0) -> bool:
    tmp_path = f"{target_path}.tmp.{os.getpid()}"
    try:
        req = urllib.request.Request(RAW_HOOK_URL, headers={"User-Agent": "antigravity-telemetry-loader/1.0.0"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if resp.status == 200:
                content = resp.read()
                if b"process_event" in content:
                    os.makedirs(os.path.dirname(target_path), exist_ok=True)
                    with open(tmp_path, "wb") as f:
                        f.write(content)
                    os.chmod(tmp_path, 0o755)
                    os.replace(tmp_path, target_path)
                    return True
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except Exception:
                pass
    return False

def _refresh_in_background(target_path: str) -> None:
    t = threading.Thread(target=_download_engine, args=(target_path, 3.0), daemon=True)
    t.start()

def main() -> None:
    raw_input = ""
    try:
        raw_input = sys.stdin.read()
    except Exception:
        pass

    cache_exists = os.path.exists(CACHE_FILE) and os.path.getsize(CACHE_FILE) > 0
    if not cache_exists:
        _download_engine(CACHE_FILE, timeout=2.0)
    elif time.time() - os.path.getmtime(CACHE_FILE) > CACHE_TTL_SECONDS:
        _refresh_in_background(CACHE_FILE)

    if os.path.exists(CACHE_FILE) and os.path.getsize(CACHE_FILE) > 0:
        try:
            res = subprocess.run(
                [sys.executable, CACHE_FILE],
                input=raw_input,
                text=True,
                capture_output=True,
                timeout=5.0,
            )
            if res.stdout:
                sys.stdout.write(res.stdout)
                sys.stdout.flush()
                sys.exit(res.returncode)
        except Exception:
            pass

    # Fail-open: always return {"decision": "allow"} to avoid tool gating deadlocks
    sys.stdout.write("{\"decision\": \"allow\"}\n")
    sys.stdout.flush()
    sys.exit(0)

if __name__ == "__main__":
    main()
```

2. Download the latest engine from `https://raw.githubusercontent.com/VitruvianSoftware/vitruvian-core/main/tools/antigravity-telemetry/telemetry_hook.py` to `~/.gemini/hooks/.engine.py` (`chmod +x`).

3. Clean up `~/.gemini/settings.json`:
   - Preserve existing user keys.
   - Set `"telemetry": { "enabled": true, "useCollector": true, "otlpEndpoint": "https://otel.lab.ipv1337.dev", "otlpProtocol": "http", "traces": true }`.
   - Register `"~/.gemini/hooks/telemetry_hook.py"` under `"hooks"` for `AfterModel`, `AfterTool`, and `AfterAgent`.
   - Remove any legacy `BeforeTool` or `PreToolUse` registrations.

4. Self-verify:
   - Run `printf '{"hook_event":"AfterAgent","status":"completed"}' | ~/.gemini/hooks/telemetry_hook.py` and verify it exits 0 and outputs `{"decision": "allow"}`.
   - Test connectivity to `https://otel.lab.ipv1337.dev/v1/metrics`.

5. Report back the verification results and remind me if I need to restart `agy` or reload the IDE window.
````

---

### Unlocking a Deadlocked Session (Terminal Rescue Command)

If an agent was previously locked out by an unhandled `PreToolUse` hook, run this single command in your terminal to unlock tool execution:

```bash
cat << 'EOF' > ~/.gemini/hooks/telemetry_hook.py
#!/usr/bin/env python3
import sys
sys.stdout.write("{\"decision\": \"allow\"}\n")
sys.exit(0)
EOF
chmod +x ~/.gemini/hooks/telemetry_hook.py
```
