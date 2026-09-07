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
| GET | `/v1/tools` | – | `{tools:{<name>:{available:bool, path}}}` for agy, claude, docker, kubectl, limactl, ollama, osascript, podman, shortcuts, xcodebuild — `exec.LookPath` on the agent's PATH, so "present" means "the exec endpoint can run it". The gallery uses it to say "not on this Mac" instead of offering Install |
| GET | `/v1/antigravity` | – | `{available, reason, version, models:[{id,label}], agents:[string]}` — `agy --version`, `agy models`, `agy agents`, refreshed every 10 min (models is a network call). agy has no build/eval/queue query; this is what it can honestly report |
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

---

# v1.2 additions

Same rules as above: read endpoints need no auth; act endpoints need the bearer token; every act
call is logged with its kind and the first 80 characters. New agent flags are listed at the end.

## Streaming exec (act)

`POST /v1/exec/stream` — same body as `/v1/exec`, but the reply is `text/event-stream` and lines
arrive as they are produced:

```
event: line
data: {"stream":"stdout","text":"..."}      # one event per line, stderr likewise

: keepalive                                 # comment every 15 s while nothing prints

event: exit
data: {"exit_code":0,"duration_ms":41230}   # always the last event
```

Default timeout 600 s (`claude` kind: 600 s), caller may set up to 3600. If the client disconnects,
the agent kills the process group (this is how the phone cancels). Output is not capped; the client
keeps what it wants. The act log line is written at start and again at exit with the code.

## Claude Code sessions (read + act)

`GET /v1/claude/sessions` →
`{sessions:[{session_id, project, cwd, path, last_active, state, last_role, last_text, last_tool}]}`

Derived from the newest `*.jsonl` per project under `~/.claude/projects/`, reading only its last
64 KiB. Records with `type` `user`/`assistant` carry `message.content` (a list of
`{type:"text"|"tool_use"|"tool_result"|"thinking", ...}`); other record types are ignored.
`state` is a heuristic and the contract says so:

- `waiting_for_permission` — last message is an assistant `tool_use` with no later `tool_result`
  for ≥ 90 s. A permission prompt is one reason; a long command (a build) is the other, and the
  transcript cannot tell them apart — which is why the push says "may be waiting".
- `working` — last message is a `user` record (a tool result just landed) or an assistant
  `tool_use` under 20 s old.
- `idle` — last message is assistant text with no tool call (the turn finished; it is waiting on
  the person).
- `unknown` — nothing parseable.

`last_text` is the last assistant text, trimmed to 300 chars; `last_tool` the tool name when the
last assistant content is a `tool_use`. Sampled every 5 s.

`POST /v1/claude/resume` (act) `{session_id, prompt}` → runs
`claude --resume <session_id> -p <prompt> --output-format text` via the exec machinery, 300 s
bound; reply is the `/v1/exec` shape.

## Pull requests (read + act)

`GET /v1/prs` → `{available, reason, sampled_at, prs:[{repo, number, title, url, author, is_draft,
head_ref, base_ref, merge_state, review_decision, checks:{success, failure, pending, skipped},
auto_merge:bool, updated_at}]}`

Source: `gh search prs --author @me --state open --json number,repository,title,url,updatedAt
--limit 20`, then `gh pr view <n> --repo <r> --json isDraft,headRefName,baseRefName,
mergeStateStatus,reviewDecision,statusCheckRollup,autoMergeRequest,author`. `checks` counts
`statusCheckRollup` entries by `conclusion` (or `state`/`status` when there is no conclusion;
`IN_PROGRESS`/`QUEUED`/`PENDING` → pending). `available:false` when `gh` is missing or not
logged in, with gh's own reason. Sampled every 60 s; `--gh-extra-repos a/b,c/d` adds repos whose
open PRs are listed regardless of author.

`POST /v1/prs/action` (act) `{repo, number, action}`, `action` ∈ `approve` (`gh pr review
--approve`), `merge` (`gh pr merge --merge`), `auto_merge` (`gh pr merge --auto --merge`),
`ready` (`gh pr ready`). Anything else 400. Reply `{ok, output}` with gh's stdout/stderr.

## ArgoCD (read + act)

`GET /v1/argocd` → `{available, reason, apps:[{name, namespace, project, sync, health, revision,
last_synced, message}]}` from `kubectl [--kubeconfig] [--context] get applications -A -o json`
(needs the same flags as `/v1/k8s`). `revision` is the first 8 chars; `message` is
`status.operationState.message` when present. Sampled with the other slow tools.

`POST /v1/argocd/sync` (act) `{name, namespace}` → `kubectl -n <ns> patch application <name>
--type merge -p '{"operation":{"initiatedBy":{"username":"vitruvian-remote"},"sync":{}}}'`.
Reply `{ok, output}`.

## Screen peek (act — a screenshot is as sensitive as the clipboard)

`GET /v1/screen?width=800` → `image/jpeg` of the main display, downscaled to `width` (200–1600,
default 800) with `sips --resampleWidth`; `Cache-Control: no-store`. Captured with
`screencapture -x -t jpg <tmp>`; the file is deleted after sending. Cached for 2 s so a
tapping thumb does not run screencapture ten times. Without Screen Recording granted to the agent
binary macOS refuses; then reply `503 {"available":false,"reason":"Screen Recording is not
granted to the agent — System Settings → Privacy & Security → Screen Recording"}`.

## Notifications (agent → ntfy)

Flags `--ntfy-url` (e.g. `https://ntfy.ipv1337.dev`), `--ntfy-topic`, `--ntfy-token-file`
(bearer, 0600, never logged). Publishes `POST <url>/<topic>` with headers `Title`, `Priority`,
`Tags`, `Click` (a `vitruvian-remote://<screen>` link the phone opens). Events, each sent once per
transition and debounced 30 s per key:

| Key | When | Title / body |
|---|---|---|
| `claude:<session>:permission` | session enters `waiting_for_permission` | "Claude Code may be waiting" / `<project> · <last_tool> · no result for 90 s` |
| `claude:<session>:idle` | session enters `idle` from `working` | "Claude Code finished a turn" / `<project> · <last_text[:120]>` |
| `exec:<id>` | a streamed exec exits | "Command finished · exit N" / first 80 chars |
| `pr:<repo>#<n>:green` / `:red` | checks go all-success / any-failure | "PR #n checks green|failed" / title |
| `agent:start` | agent starts | "Agent online" / hostname |

`POST /v1/notify/test` (act) sends "Test from Vitruvian Remote". `/healthz` gains
`notify:{configured:bool, topic:string}`. Publishing failures are logged and never block the
sampler.

## New flags

`--ntfy-url`, `--ntfy-topic`, `--ntfy-token-file`, `--gh-extra-repos`, `--exec-dir` (the cwd for
`/v1/exec` and `/v1/exec/stream`; under launchd it is otherwise `~`, where `bazel run` has no workspace). `install.sh` passes them
through like the others.

## Phone-only (no agent change)

Multiple hosts (a URL, token, alias and MAC per Mac; the Hosts list switches between them),
phone-local notifications (Mac unreachable / back; a streamed command finished while the app was
in the background), a Quick Settings tile for display-sleep and lock, and dictation into the
prompt and console fields. Deep links `vitruvian-remote://<screen>` open that screen.
