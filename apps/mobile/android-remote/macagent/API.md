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
2. On the **Mac**: `bazel run //apps/mobile/android-remote/macagent:pair -- 482917`
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

Zoom: `GET /v1/screen?width=800&x=0.25&y=0.5&w=0.25&h=0.25` crops that part of the display
(fractions of its width/height, all four or none) from the **native** capture before downscaling, so
a quarter of a 7680-wide desktop at 800 px is readable where the whole desktop at 800 px is not. Each
of `w`,`h` must be in [1/16, 1] and the box must lie inside the display, else `400`. The region is
part of the 2 s cache key.

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

# v1.3 additions: the phone bridge

Design and tool list: `docs/phone-bridge.md`. The agent is a relay; the tools live on the phone.

## Phone link (phone → agent)

`POST /v1/phone/link` — act tier. Body `{"device":{"model":"Pixel Fold","android":"16"},
"tools":[{"name":"sms.list","description":"…","inputSchema":{…},"tier":"read"}, …]}`. The reply
is `text/event-stream`, held open for as long as the phone keeps it. Events:

```
event: hello
data: {"agent_version":"1.3.0"}

event: call
data: {"id":"c-17","tool":"sms.list","arguments":{"n":5}}

event: ping
data: {}
```

`ping` every 20 s. A second link replaces the first (the old stream ends). Tool names are
`[a-z][a-z0-9_.]*`, at most 64 chars; `tier` is `read`, `act` or `outbound`.

`POST /v1/phone/result` — act tier. Body `{"id":"c-17","content":[{"type":"text","text":"…"}],
"is_error":false}`. `content` may also carry `{"type":"image","data":"<base64>","mimeType":"image/jpeg"}`.
`404` for an id that is unknown or already answered; `200 {}` otherwise. A tool name that fails
the pattern, or a `tier` outside the three, is a `400` on the LINK — before the stream starts,
so the phone gets an error it can render rather than a live link that half works.

`GET /v1/phone` — read tier: `{"connected":true,"since":"…","device":{…},"tools":["sms.list",…],
"trust_until":"…"|null}`. `trust_until` is whatever the phone last reported in `phone.status`:
the agent parses each `phone.status` result's text content as JSON and keeps its `trust_until`
field if it has one. A phone whose trust window changes without a status call may also send
`"trust_until"` as a top-level field on `/v1/phone/result` (or on the link body), and that wins.
Everything about it is the phone's claim, not the agent's: the agent enforces no tier, it only
reports what it was told. `trust_until` is `null` while nothing is linked.

## MCP endpoint (agents on the Mac → agent)

`POST /mcp/phone` — JSON-RPC 2.0, MCP Streamable HTTP (a single JSON response per request; no
server-initiated stream, `GET` is 405). Loopback only. Bearer token from
`~/.config/vitruvian-remote-agent/mcp-token`, created 0600 on first start; never logged.

| Method | Reply |
|---|---|
| `initialize` | `{"protocolVersion":"2025-06-18","capabilities":{"tools":{"listChanged":false}},"serverInfo":{"name":"vitruvian-remote-phone","version":"1.3.0"}}` |
| `notifications/initialized` | `202`, empty body |
| `ping` | `{}` |
| `tools/list` | `{"tools":[{name, description, inputSchema}…]}` — the phone's list, without `tier`; empty when no phone is linked |
| `tools/call` | forwarded as a `call` event; the phone's `content`/`is_error` come back as `{"content":[…],"isError":bool}` |

Timeouts: 30 s, 90 s for `outbound` tools (a person has to tap Approve). Phone not linked →
`tools/call` returns `isError:true` with text `phone not connected`. Unknown method → JSON-RPC
`-32601`; an unparseable body → `-32700` with a null id (nothing was parsed, so there is no id to
echo); `tools/call` without a `name` → `-32602`. The agent logs every call as `act mcp: <tool>`;
arguments are not logged.

Two things the code settled that the table does not say. Every `notifications/*` method, not just
`initialized`, answers `202` with an empty body: a JSON-RPC notification carries no id, so there is
nobody to send an error to. And a call that times out, or one whose link drops mid-flight, is a
tool error like "phone not connected" rather than a transport error — an agent that gave up on the
whole server after one slow tap would be worse than one that sees the sentence and retries.

Wrong or missing bearer → `401`. A caller that is not on loopback → `403`, checked before the token
so a tailnet peer learns nothing about whether it guessed one.

---

# v1.4 additions

Same rules as above. One new module: **HomeSpeaker** (`apps/desktop/home-speaker`), the menu bar
app that reads coding-agent replies aloud on Google Home speakers.

The agent never imports HomeSpeaker's code (the inter-app boundary forbids it). The two apps share
one contract already — the config file `~/.gemini/speaker_broadcast.json`, which HomeSpeaker, its
Claude Code hook and the `speaker-broadcast` CLI all read — so the agent reads and atomically
rewrites that file, and HomeSpeaker (1.6+) watches the directory and reloads. Speaking goes through
the app's own binary so it uses HomeSpeaker's sign-in, target resolution and speech cleaning.

## HomeSpeaker (read + act)

`GET /v1/homespeaker` → `{available, reason, installed, app_running, signed_in, enabled,
default_target, speech_length, structure_name, quiet_hours:{enabled,start,end},
targets:[{key, name, room, type, selected}], last?:{text, target, source, at}}`

- `available:false` with `reason` when the config file does not exist (HomeSpeaker was never set
  up on this Mac). `installed` is independent: the bundle at
  `/Applications/HomeSpeaker.app` exists. `app_running` is `pgrep -x HomeSpeaker`. `signed_in` is
  "a Google Home refresh token is present" and nothing about it — the value is never read into a
  response or a log.
- `speech_length` is `headline` | `summary` | `full`; absent in the file means `summary` (the
  app's own default).
- `targets` is the file's map as a list: `Structure` (whole home) first, then by room; exactly one
  has `selected:true` when `default_target` names a real key. One entry per DEVICE, not per alias —
  discovery writes some speakers under two keys (`lake_office` and `lake_office_display` are one
  display), and the same rule the app's own picker uses applies here: the default alias wins,
  otherwise the shortest. The file keeps every alias; only the list is deduped.
- `last` is the newest entry of `~/.gemini/speaker_history.json`, if any. Its timestamp is
  converted from Foundation's default Date encoding (seconds since 2001-01-01).
- `/v1/tools` gains `homespeaker`, resolved by the bundle path rather than PATH, so the gallery
  can say "not on this Mac".

`POST /v1/homespeaker` (act) `{enabled?:bool, default_target?:string, speech_length?:string,
quiet_hours_enabled?:bool}` — every field optional; an omitted field is left alone, an empty body
is 400. `default_target` must be a key of `targets` and `speech_length` one of the three values;
anything else is 400 and the file is untouched. The rewrite keeps every key the agent does not
know about. 409 when HomeSpeaker was never set up. Reply: the `GET` shape, read back from the file.

`POST /v1/homespeaker/say` (act) `{text}` → runs `HomeSpeaker --say <text>` (30 s bound) and
replies `{ok, output}` in the `/v1/argocd/sync` shape. `--say` is deliberate speech: it overrides
quiet hours but honours the master switch, and reports a refusal in `output` with `ok:false`.
409 when the app is not installed.

Act log lines: `act homespeaker: enabled=false default_target=kitchen` and `act homespeaker: say …`.

## v1.4.1: pause media while announcing

`GET /v1/homespeaker` gains `pause_media` (bool) and `pause_media_extra_seconds` (number). When
on, HomeSpeaker 1.8+ pauses what the Mac is playing while it announces and resumes it
`pause_media_extra_seconds` after the estimated end. Absent from the file means the app's own
defaults: `false` and `1`.

`POST /v1/homespeaker` accepts both. `pause_media_extra_seconds` must be 0-10 (the app's own
stepper range); anything else is 400 and the file is untouched -- refused rather than clamped,
because the app would clamp silently and the phone would show a value the Mac is not using.

## v1.5: speaker volume and announce at a set volume

`GET /v1/homespeaker/volume` (read) → `{available, reason?, speaker, percent, muted, online}` — the
default speaker's volume, relayed from HomeSpeaker 1.9's `--volume`. Read, like `/v1/audio`: the
speaker's own buttons show it to anyone in the room. `online:false` means `percent` is only the last
level the speaker had; show it as offline. `available:false` with `reason` for Whole Home, a speaker
with no volume control, or an app older than 1.9.

`POST /v1/homespeaker/volume` (act) — exactly one of `{"percent": 0-100}` or `{"muted": bool}`; both
or neither, or a percent out of range, is 400 and nothing runs. Runs `--set-volume` / `--mute` /
`--unmute` (45 s bound) and answers in the `GET` shape with the level Google reports afterwards.
Google reports a change ~3 s late and HomeSpeaker waits for it, so this takes several seconds.

`GET /v1/homespeaker` gains `announce_volume_enabled` (bool) and `announce_volume` (0-100): when on,
HomeSpeaker sets the speaker to that level for each announcement and puts it back after. Absent from
the file means the app's defaults, `false` and `60`. `POST /v1/homespeaker` accepts both;
`announce_volume` outside 0-100 is 400 with the file untouched.

# v1.5.1 corrections

- `battery.temperature_c` is `null` when macOS does not report one (macOS 27 moved it into a
  child object's `BatteryData`; the agent now reads it from there). It was `0`, which the phone
  printed as "0°".
- `battery.system_watts` (new, nullable): the whole Mac's draw from the power adapter, from
  `PowerTelemetryData.SystemPowerIn`. `draw_watts` stays the battery's own discharge and is 0 on AC.
- `disk` reads the data volume (`/System/Volumes/Data`) and `used_bytes`/`used_percent` are
  total minus available. Reading `/` (the sealed system volume) showed a 90%-full disk as 1%.
- `/v1/processes` leaves out the agent's own `top` and `ps`.

# v1.6 additions: answer Claude Code permission prompts from the phone

**One sentence.** When a Claude Code session on the Mac is about to show a permission dialog, and
"Answer Claude prompts here" is switched on in the phone app, the question goes to the phone
instead; Approve or Deny there becomes Claude Code's answer. Unanswered in time, the normal dialog
shows on the Mac, so nothing is ever lost.

## How it is wired

Claude Code's `PermissionRequest` hook (fires only when Claude Code would ask the user) runs
`vitruvian-remote-agent permission-hook`. That subcommand reads the hook JSON on stdin, POSTs it to
the agent on loopback, and blocks until the agent answers. The agent holds the request until the
phone decides or the wait runs out.

**One switch, and settings.json is it.** The phone's toggle calls
`POST /v1/claude/permissions/enabled`, which adds or removes our entry in `~/.claude/settings.json`.
There is no other on/off state: the feature is on exactly when our hook is in that file, so the
hook running at all means the feature is on. `vitruvian-remote-agent install-claude-hook
[--remove] [--settings PATH]` makes the same edit by hand, with the same code.

The entry the agent writes. The command is the **absolute** path of the running agent binary,
symlinks resolved (under launchd, `~/.local/bin/vitruvian-remote-agent` expanded), because Claude
Code is not promised to expand `~`:

```json
{"hooks":{"PermissionRequest":[{"matcher":"","hooks":[{"type":"command",
  "command":"/Users/you/.local/bin/vitruvian-remote-agent permission-hook","timeout":150}]}]}}
```

Editing rules, the same for the toggle and the subcommand:
- Only our entry is added or removed. Ours = a hook whose command names `vitruvian-remote-agent`
  and ends in `permission-hook`; an older or moved entry of ours is replaced, never duplicated.
  Every other key and hook is preserved; key order may change (the file is re-encoded).
- Idempotent: nothing to do means nothing is written.
- Every write copies the original to `settings.json.bak` first, then replaces the file atomically
  (temp file + rename), keeping its permissions (0600 for a new file). A symlinked settings.json is
  edited through the link.
- A settings.json that cannot be read or parsed (or whose `hooks` / `hooks.PermissionRequest` has
  the wrong shape) is **never** overwritten: the call fails and says the file was left untouched.

## The hook subcommand (Mac, stdin → stdout)

- Reads stdin: Claude Code's hook JSON. The agent uses `session_id`, `cwd`, `tool_name`,
  `tool_input`; `transcript_path` is accepted and not used yet; everything else is ignored.
- `POST http://127.0.0.1:7411/v1/claude/permission/ask` with bearer = contents of
  `<config-dir>/hook-token` (0600, created on agent start, never logged), body = the stdin JSON
  verbatim. Connect timeout 1 s; 145 s overall (above the agent's 140 s maximum wait, below Claude
  Code's 150 s). No proxy.
- Reply `{"decision":"allow"}` → print
  `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`.
- Reply `{"decision":"deny","message":"…"}` → print
  `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"<message or 'Denied from the phone'>"}}}`.
- Reply `{"decision":"ask"}`, any error, agent down, a non-200, no token file, or stdin that is not
  JSON → print nothing, exit 0: Claude Code shows its normal dialog. It never exits non-zero and
  never prints partial JSON. **The hook must never make Claude Code worse than without it.**

## Agent endpoints

`POST /v1/claude/permission/ask` — loopback only AND bearer = hook-token (403 off loopback, checked
first; 401 on a missing or wrong token, the pairing and MCP tokens included; the same rules as
`/mcp/phone`). There is no on/off check here: the hook only runs when the toggle installed it.
Behaviour:
- The body must be JSON with a non-empty `tool_name` (else 400, which the hook treats as "ask").
- Create a pending request `{id:"p-<n>", session_id, project (basename of cwd), cwd, tool,
  summary, detail, created_at, expires_at}`:
  - `summary`, one line for a notification: Bash → the command; Edit/Write/MultiEdit/NotebookEdit
    → `edit <tool_input.file_path or notebook_path>`; WebFetch → the URL; anything else, or a known
    tool missing its field → `<tool> <compact JSON of the input>`. Whitespace runs collapse to one
    space; at most 120 characters, the last being `…` when cut.
  - `detail`, for the phone to show: Bash → the full command; anything else → the input as
    indented JSON. At most 4 KiB, cut on a character boundary, ending in `…` when cut.
- Publish ntfy (key `claude-permission-<id>`, title `Claude wants to: <tool>`, body
  `<project> · <summary>`, priority `high`, tags `question`, click `vitruvian-remote://apps/claude`).
  Fire and forget; the existing ntfy configuration and mute switch apply.
- Wait up to `--permission-wait` (default 120 s, clamped to [5 s, 140 s] so the hook's 150 s
  timeout is never hit). Reply with the decision, or `{"decision":"ask"}` on timeout. If the hook's
  request is cancelled (Claude Code gave up / the user answered on the Mac), drop the pending
  request.
- At most 64 requests wait at once; past that the reply is `{"decision":"ask"}` straight away.

`GET /v1/claude/permissions` — act tier (it shows commands and paths): `{"enabled":bool,
"wait_seconds":N, "pending":[{id, session_id, project, cwd, tool, summary, detail, created_at,
expires_at}]}` oldest first. `enabled` is read from settings.json on every call (false when the
file is missing or cannot be parsed).

`POST /v1/claude/permissions/enabled` — act tier, body `{"enabled":bool}` → installs or removes the
hook as above and replies `{"enabled":bool,"settings_path":"~/.claude/settings.json"}`, the state
read back from the file. `400` when `enabled` is missing; `500 {"error":"…"}` when the file cannot
be read, parsed or written, with a message saying it was left untouched. Turning it off does not
touch pending requests; decide and the timeout still end them.

`POST /v1/claude/permissions/decide` — act tier, body `{"id":"p-3","decision":"allow"|"deny",
"message":"optional, deny only, ≤300 chars (longer is cut)"}` → `200 {}`; `404` unknown or already
answered/expired; `400` bad decision. Logged as `act claude: allow|deny <tool> in <project>`; the
command itself is not logged.

# v1.7 additions: Antigravity parity with Claude Code

Facts measured on agy 1.2.11 (2026-09-25), which this section relies on:
- Sessions: `~/.gemini/antigravity-cli/conversation_summaries.db` (SQLite, table
  `conversation_summaries`: conversation_id, title, preview, step_count, last_modified_time,
  workspace_uris, status e.g. `CASCADE_RUN_STATUS_IDLE`, not_fully_idle, killed, agent_name).
  Read it with `sqlite3 -readonly -json` (agy holds it open in WAL mode).
- agy prompts for `run_command` unless the command's leading words match a `command(<prefix>)` rule
  in `permissions.allow` of `~/.gemini/antigravity-cli/settings.json`. Headless `agy -p` cannot prompt
  and auto-denies such tools.
- A `PreToolUse` hook in agy's `hooks.json` that answers `allow` does NOT skip agy's own "Run this
  command?" prompt: agy reads it as "no objection" and still asks on the Mac, and a headless
  `agy -p` still auto-denies. Only `deny` is honoured. This agent therefore installs no hook in agy.

## Sessions and resume

`GET /v1/antigravity/sessions` (read tier): `{"available":bool,"reason":"…","sessions":[{id, title,
preview, project (basename of first workspace), steps, updated_at, state}]}` newest first, at most 20;
`state` is `killed` when killed, `working` when status is not IDLE or not_fully_idle is true, else
`idle`.

`POST /v1/antigravity/resume` (act tier), body `{"conversation_id":"…"|"" , "prompt":"…"}` → SSE
exactly like `/v1/exec/stream` (events `line`, `exit`), running
`agy -p <prompt> --output-format text [--conversation <id>]` in the conversation's workspace (else
`--exec-dir`). Empty id starts a new conversation.

## Permission prompts: not supported

Approving Antigravity prompts from the phone is not supported: in agy 1.2.11 a hook's 'allow' does
not skip agy's own prompt, and headless runs still refuse commands that need permission. A
phone-sent prompt therefore works for anything agy can do without asking; commands that need
permission are refused, and the reply says so.

`GET /v1/claude/permissions` and the rest of the v1.6 queue are unchanged and hold Claude Code's
prompts only.

# v1.8 additions: speak on this Mac

HomeSpeaker can speak on the Mac it runs on as well as (or instead of) the Google Home speakers.
The contract is [`apps/desktop/home-speaker/docs/local-speech.md`](../../../desktop/home-speaker/docs/local-speech.md).

`GET /v1/homespeaker` gains `speak_home` (bool), `speak_local` (bool), `local_voice` (string, an
`AVSpeechSynthesisVoice` identifier) and `local_voice_name` (string: the identifier's last dotted
component, e.g. `Aaron`; the raw identifier when that is not a plain name). Absent from the file
means today's behaviour: `true`, `false` and `com.apple.siri.natural.Aaron`.

`POST /v1/homespeaker` accepts `speak_home` and `speak_local` (bools). Both `false` is accepted and
written: the user asked for silence, and HomeSpeaker reports it. The voice is not settable here --
which voices are installed is only known on the Mac, so it is chosen there. As before, only the keys
sent are written and every other key in the file is kept.

The phone reads a reply without `speak_home`/`speak_local` as an agent older than v1.8 and hides the
two switches.
