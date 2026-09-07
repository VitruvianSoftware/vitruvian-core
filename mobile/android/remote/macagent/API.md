# vitruvian-remote-agent · HTTP API (v1.1 contract)

Both halves of Vitruvian Remote are built against this document: the Go agent
(`macagent/`) serves it, the Android app (`state/AgentClient.kt`) consumes it.
Change it here first.

All responses are JSON with `Cache-Control: no-store`. Timestamps are RFC3339.
Errors are `{"error": "<message>"}` with a 4xx/5xx status.

## Trust model

Two tiers:

- **Read** endpoints need no auth. The tailnet is the boundary.
- **Act** endpoints need `Authorization: Bearer <token>`. The token is issued
  once by **pairing** and stored on both sides. 401 without it, 403 with a wrong
  one. Comparison is constant-time.

Everything an act endpoint runs is logged to the agent log with its kind and
the first 80 characters, so the Mac has a record of what the phone did.

## Read (no auth)

| Method | Path | Body / query | Response |
|---|---|---|---|
| GET | `/healthz` | – | `{ok, sample_age_ms, agent_version, read_only:false, paired:bool, sampled_at}` |
| GET | `/v1/host` | – | `{hostname, model, chip, cores, memory_bytes, os_version, agent_version, mac_address, wake_on_lan:bool}` — `mac_address` is en0's, for the phone to send a Wake-on-LAN packet; `wake_on_lan` is `pmset womp` |
| GET | `/v1/metrics` | – | unchanged from v1.0 (cpu/memory/battery/disk/network/thermal/uptime/unavailable) |
| GET | `/v1/processes` | – | `{sampled_at, processes:[{name, cpu_percent:float, memory_bytes:int}]}` — top 8 by CPU from `ps -Aceo pcpu,rss,comm -r` |
| GET | `/v1/vms` | – | `{available:bool, reason:string, vms:[{name, status, vm_type, cpus:int, memory_bytes:int, disk_bytes:int, arch}]}` — `limactl list --json` (one object per line). `available:false` with a reason when limactl is absent or fails |
| GET | `/v1/containers` | – | `{available, reason, runtime:"docker"|"podman"|"", containers:[{name, image, status}]}` — `docker ps --format '{{json .}}'`, then `podman ps --format json`; daemon down ⇒ `available:false`, reason = the tool's first stderr line |
| GET | `/v1/k8s` | – | `{available, reason, context, nodes:[{name, ready:bool, version, roles:[string]}]}` — only when the agent was started with `--kube-context` (and optionally `--kubeconfig <file>`, since the lab cluster's config is not `~/.kube/config`); else `available:false, reason:"not configured (--kube-context)"`. Uses `kubectl [--kubeconfig F] --context X get nodes -o json` with a 5 s bound |
| GET | `/v1/ollama` | – | `{available, reason, models:[{name, id, size_bytes, modified}], running:[{name, id, size_bytes, processor, context, until}]}` — `ollama list` + `ollama ps`; daemon down ⇒ `available:false` with ollama's message. An idle daemon has `running:[]`, which is not an error |
| GET | `/v1/audio` | – | `{volume_percent:int, muted:bool}` — `osascript -e 'get volume settings'` |
| GET | `/v1/sessions` | – | `{sessions:[{project, last_active, path}], running_processes:int}` — Claude Code: `*.jsonl` under `~/.claude/projects/*/` modified in the last 30 min (project = dir name with leading `-` stripped and `-`→`/`), plus the count of processes whose argv[0] basename is `claude` |
| GET | `/v1/promql` | `?q=<expr>` | proxies `GET <prometheus-url>/api/v1/query?query=<q>` verbatim when `--prometheus-url` is set, adding `Authorization: Bearer` from `--prometheus-token-file` if given (Grafana's datasource proxy `…/api/datasources/proxy/uid/<uid>` is the reachable path from off-network and needs one); else `{available:false, reason:"not configured (--prometheus-url)"}` |

## Pairing

1. The **phone** shows a random six-digit code with a five-minute TTL.
2. On the **Mac**: `bazel run //mobile/android/remote/macagent:pair -- 482917`
   (the binary's `pair` subcommand). Writes `~/.config/vitruvian-remote-agent/pair.json`
   `{"code":"482917","expires":"<RFC3339 +5m>","attempts":0}`.
3. The phone polls `POST /v1/pair {"code":"482917"}` every tick until it gets
   `200 {"token":"<64 hex>"}`. Wrong or expired code ⇒ 403; after 5 wrong attempts
   the pair file is deleted (⇒ 403 until re-paired). Success deletes the pair file.
4. The token lives in `~/.config/vitruvian-remote-agent/token` (mode 0600), created
   at first start if absent. Pairing does not rotate it; `vitruvian-remote-agent
   token --rotate` does (and un-pairs every phone).

The agent's `pair` subcommand and the server share the config dir; the server
re-reads `pair.json` on each `POST /v1/pair`, so no restart is needed.

## Act (Bearer token)

| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/v1/exec` | `{kind:"shell"|"applescript"|"shortcut"|"claude", command:string, timeout_seconds?:int}` | `{exit_code:int, stdout, stderr, duration_ms:int, truncated:bool}` |
| GET | `/v1/clipboard` | – | `{text}` — `pbpaste` |
| POST | `/v1/clipboard` | `{text}` | `{ok:true}` — `pbcopy` |
| POST | `/v1/audio` | `{volume_percent:int}` | `{volume_percent, muted}` — `osascript -e "set volume output volume N"`, clamped 0–100 |
| POST | `/v1/power` | `{action:"sleep"|"restart"}` | `{ok:true}` — `pmset sleepnow` / `osascript -e 'tell app "System Events" to restart'`; any other action ⇒ 400 |

`exec` kinds:

- `shell` → `/bin/zsh -lc <command>` (login shell so PATH matches the user's terminal)
- `applescript` → `osascript -e <command>`
- `shortcut` → `shortcuts run <command>` (command is the shortcut's name)
- `claude` → `claude -p <command> --output-format text` (command is the prompt)

Default timeout 60 s (`claude`: 180 s); the caller may lower it, not raise it
past 300. stdout and stderr are each capped at 64 KiB (`truncated:true`).
Non-zero exit is a 200 with `exit_code` set — the phone shows it; it is not
an HTTP error.

## Errors the phone must render, not hide

- `available:false` ⇒ show `reason` in place of the list. Never an empty list
  that looks like "nothing running".
- `/v1/metrics` `cpu.ready:false` ⇒ "sampling…", not 0%.
- 401/403 on an act endpoint ⇒ "not paired" and offer pairing.
- Connection failure ⇒ freeze the last values and say `unreachable`.
