# vitruvian-remote-agent · HTTP API (v1.1 contract)

Both halves of Vitruvian Remote are built against this document: the Rust agent
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
| GET | `/healthz` | – | `{ok, sample_age_ms, agent_version, read_only:false, paired:bool, sampled_at}` — `agent_version` reports the version of the installed release |
| GET | `/v1/host` | – | `{hostname, model, chip, cores, memory_bytes, os_version, agent_version, mac_address, wake_on_lan:bool}` — `agent_version` reports the version of the installed release; `mac_address` is en0's, for the phone to send a Wake-on-LAN packet; `wake_on_lan` is `pmset womp` |
| GET | `/v1/metrics` | – | unchanged from v1.0 (cpu/memory/battery/disk/network/thermal/uptime/unavailable) |
| GET | `/v1/processes` | – | `{sampled_at, processes:[{name, cpu_percent:float, memory_bytes:int}]}` — top 8 by CPU from `ps -Aceo pcpu,rss,comm -r` |
| GET | `/v1/vms` | – | `{available:bool, reason:string, vms:[{name, status, vm_type, cpus:int, memory_bytes:int, disk_bytes:int, arch}]}` — `limactl list --json` (one object per line). `available:false` with a reason when limactl is absent or fails |
| GET | `/v1/containers` | – | `{available, reason, runtime:"docker"|"podman"|"", containers:[{name, image, status}]}` — `docker ps --format '{{json .}}'`, then `podman ps --format json`; daemon down ⇒ `available:false`, reason = the tool's first stderr line |
| GET | `/v1/k8s` | – | `{available, reason, context, nodes:[{name, ready:bool, version, roles:[string]}]}` — only when the agent was started with `--kube-context` (and optionally `--kubeconfig <file>`, since the lab cluster's config is not `~/.kube/config`); else `available:false, reason:"not configured (--kube-context)"`. Uses `kubectl [--kubeconfig F] --context X get nodes -o json` with a 5 s bound |
| GET | `/v1/tools` | – | `{tools:{<name>:{available:bool, path}}}` for adb, agy, claude, docker, homespeaker, kubectl, limactl, ollama, osascript, podman, shortcuts, xcodebuild — PATH lookup on the agent's PATH, so "present" means "the exec endpoint can run it". The gallery uses it to say "not on this Mac" instead of offering Install |
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
   `200 {"token":"<64 hex>"}`. Wrong or expired code ⇒ 403; after 5 different wrong codes (a repeated code is not counted)
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

Flags `--ntfy-url` (e.g. `https://ntfy.example.com`), `--ntfy-topic`, `--ntfy-token-file`
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
`/v1/exec` and `/v1/exec/stream`; under launchd it is otherwise `~`, where `bazel run` has no workspace). `bazel run //apps/mobile/android-remote/macagent:install` passes them
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
app (or Vitruvian extension) that reads coding-agent replies aloud on Google Home speakers.

The agent never imports HomeSpeaker's code (the inter-app boundary forbids it) and **never reads or
writes HomeSpeaker's settings, secrets, history, monitor-status, door or coding-agent hook files**.
It asks the HomeSpeaker program instead, so the rules for a value (its choices, ranges and clamps)
live in one place, HomeSpeaker, and the agent only carries them.

- **Which program.** The only file the agent still reads is the choice file
  `~/.gemini/speaker_door.json`, to learn which program is chosen: the app
  (`/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker`) or the Vitruvian extension's
  `bin/tool` (same flags). The choice file is read on every request, never written.
- **Minimum version.** `--version` counts only on exit 0 with a `major.minor[.patch]` version; `--state` only on exit 0 with valid JSON; an `--apply` refusal (exit 1, JSON error) is a valid answer, a non-zero exit without JSON is an error. A replay is gated too (`--no-history` needs 1.41.0); plain say is not. Before the first `--state` or `--apply` of a request the agent runs
  `<program> --version` (15 s bound). Below `1.41.0` (`MIN_HOME_SPEAKER_VERSION`) it never runs
  `--state` or `--apply` (an older program would take them for unknown arguments and start its
  menu-bar app) and answers the **update sentence**:
  `Update Home Speaker on <this Mac's name> (have X, need 1.41.0)`. `GET` returns it as
  `{available:false, installed:true, reason:<sentence>}`; `POST` returns it as `409`.
- **Not installed.** When the chosen program is missing, `GET` answers `installed:false,
  available:false` with `reason:"HomeSpeaker is not installed at <path>"` and nothing is run;
  `POST` returns `409` with the same sentence.

`GET /v1/homespeaker` → `{available, reason, installed, app_running, signed_in, enabled,
default_target, speech_length, structure_name, quiet_hours:{enabled,start,end,active},
targets:[{key, name, room, type, selected}], last?:{text, target, source, at}, …}`

The answer is the program's `--state --json` document (contract version 1, 15 s bound), mapped onto
the fields below and the ones in the sections that follow; every field the phone reads keeps its
name and meaning. A `--state` that times out, prints something that is not JSON, or has another
contract version answers `{available:false, reason:"…"}` with the cause, not an error status.

- `available` is the document's `config_initialized`; `false` carries Home Speaker's own
  `config_problem`, or "has not been set up on this Mac". `installed` means the chosen program is
  there. `app_running` is `chosen_running`. `signed_in` is `sign_in.signed_in`; no token or key is
  ever in the document, only whether one is saved.
- Every setting comes from `settings[]` by its key (`enabled`, `speech_length`,
  `announce_volume`, `speak_phone`, …; the phone's `poll_interval` is the program's
  `poll_interval_seconds`). `targets` is `speakers` (`selected` is `is_default`); `quiet_hours`,
  `snooze_until`, `structure_*`, `homes` (`id`, `name`, `selected`), `available_voices` (`language` → `lang`),
  `custom_voices`, `local_voice_name`, `agents` (from `hooks`, including `stale_command` and `hook_program`), `legacy_launch_agent`,
  `home_speaker_version`, `app_installed`, `owner_running`, `generic_settings` (`true` when `--state` carries a non-empty `settings[]` catalog), the `has_*` flags and monitor fields (from `sign_in` and `chat`) and
  `recent` (the newest 5) / `last` come from the document under the same names.
- `warnings` (`[string]`) is the program's own list of setup problems. It is new; older phones
  ignore it.
- `/v1/tools` gains `homespeaker`, resolved by the bundle path (or the chosen extension) rather
  than PATH, so the gallery can say "not on this Mac".

`POST /v1/homespeaker` (act) turns the requested fields into `--apply --json` operations
(`{"contract_version":1,"operations":[…]}`) on the chosen program. The agent does no checking of
its own: Home Speaker's rules are the one rule, so a value outside a range is clamped or refused
by HomeSpeaker, not by the agent, and the reply is the `GET` shape read back afterwards.

| Request field | Operation |
|---|---|
| `settings` (`{ "<catalog key>": <value>, … }`) | `set` for each entry after verifying the key exists in the current `--state` `settings[]` (unknown key → `400`) |
| any setting (`enabled`, `speech_length`, `quiet_hours_*`, `pause_media*`, `announce_volume*`, `speak_*`, `phone_*`, `local_*`, `gemini_voice`, `announcement_style`, `style_model`, `home_cast_voice`, `announce_*`, `*_enabled`, `*_announce`, `google_chat_source`, `gws_account`, `mute_own_messages`, `custom_style_prompt`, `poll_interval`) | `set` with the program's key (`poll_interval` → `poll_interval_seconds`) |
| `default_target` / `remove_target` | `setDefaultSpeaker` / `removeSpeaker` |
| `reset_settings` | `reset` |
| `oauth_client_id` (+ `oauth_client_secret`) | one `saveOAuthClient`; a secret without an id uses the custom client id from `--state` (none saved: 400 "Enter the client ID first.") |
| `slack_token`, `beeper_token`, `courier_token`, `gemini_api_key` | `setSecret` `slack` / `beeper` / `courier` / `geminiKey` (empty chat token sends `clearChatToken`; empty `gemini_api_key` sends `setSecret` `""`) |
| `snooze_minutes`, `snooze_until` | `snooze` (`minutes`, or `clear` for `""`; a future `snooze_until` is counted in minutes) |
| `beeper_network`, `courier_network` | `setNetwork` |
| `courier_read_anyway` | `setReadAnyway` |
| `import_antigravity` | `importAntigravity` |
| `agent_hook_action` `install:` / `remove:` / `add-instruction:` + agent | `agentHook` (`install`, `remove`, `addInstruction`) |
| `active_door` (+ optional `copy: true`) | `switchTo` (`copy: true` copies settings from the current door) |

The program refuses a batch that mixes `switchTo` or `agentHook` with anything else, so an update
that carries several kinds is sent as **separate `--apply` calls, in this order: the plain batch,
then `agentHook`, then `switchTo` last** (a switch changes which program is chosen). The first
failure stops the rest and is reported. The program's flag commands (`--sign-in [--chat]`,
`--sign-out [--chat]`, `--discover --save [--home <id>]`, `--chat-monitor start|stop`,
`--test-media-pause`) run after the plain batch, before the hook and the switch.

A refusal from `--apply` (`{"ok":false,"error":{code,message,…}}`) returns `400 {"error":"<the
program's message>"}`; `timed_out`, `apply_failed` and `config_unreadable` return `500`. A
`not_chosen` refusal means the choice file the agent read was stale: it reads the file again and
retries once on the program the refusal names (a second `not_chosen` is `409`). `agent_hook_action`
`disable-rival…` is `agentHook` `disableRival` (agent `claude_code`) and `remove-legacy-agent` is
`removeLegacyAgent`; both go alone, in the hook slot.

Helper actions that do not touch Home Speaker's files run as before: clipboard speech
(`speak_clipboard` → `--say`) and the voice preview (`preview_voice`, macOS `say` with the Mac voice
`--state` reports).

`POST /v1/homespeaker/say` (act) `{text}` → runs `HomeSpeaker --say <text>` (30 s bound) and
replies `{ok, output}` in the `/v1/argocd/sync` shape. `--say` is deliberate speech: it overrides
quiet hours but honours the master switch, and reports a refusal in `output` with `ok:false`.
409 when the app is not installed.

Act log lines: `act homespeaker: enabled=false default_target=kitchen` and `act homespeaker: say …`.

## v1.4.1: pause media while announcing

`GET /v1/homespeaker` maps `pause_media` (bool) and `pause_media_extra_seconds` (number) from
`--state --json`. `POST /v1/homespeaker` forwards both as `set` operations in `--apply --json`;
HomeSpeaker validates the range and returns a refusal (400) if out of range.

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

`GET /v1/homespeaker` maps `announce_volume_enabled` (bool) and `announce_volume` (0-100) from
`--state --json`, and `POST /v1/homespeaker` forwards both as `set` operations in `--apply --json`.

# v1.5.1 corrections

- `battery.temperature_c` is `null` when macOS does not report one (macOS 27 moved it into a
  child object's `BatteryData`; the agent now reads it from there). It was `0`, which the phone
  printed as "0°".
- `battery.system_watts` (new, nullable): the whole Mac's draw from the power adapter, from
  `PowerTelemetryData.SystemPowerIn`. `draw_watts` stays the battery's own discharge and is 0 on AC.
- `disk` reads the data volume (`/System/Volumes/Data`) and `used_bytes`/`used_percent` are
  total minus available. Reading `/` (the sealed system volume) showed a 90%-full disk as 1%.
- `/v1/processes` leaves out the agent's own `ps`. (It also left out `top` while the agent ran
  `top` for CPU usage; it now reads the kernel's counters instead, so a `top` you run yourself
  shows up like any other process.)

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
means today's behaviour: `true`, `false` and `com.apple.ttsbundle.siri_Aaron_en-US_premium`.

`POST /v1/homespeaker` accepts `speak_home` and `speak_local` (bools). Both `false` is accepted and
written: the user asked for silence, and HomeSpeaker reports it. The voice is not settable here --
which voices are installed is only known on the Mac, so it is chosen there. As before, only the keys
sent are written and every other key in the file is kept.

The phone reads a reply without `speak_home`/`speak_local` as an agent older than v1.8 and hides the
two switches.

# v1.9 additions: pairing by QR code

`GET /pair?code=NNNNNN` (read, no token) returns a small HTML page, the target of the QR code the
menu bar app shows. It never checks the code, so it cannot be used to guess one; `POST /v1/pair`
remains the only judge. Its button is the app link
`vitruvian-remote://pair?code=NNNNNN&name=<short hostname>&url=http%3A%2F%2F<Host>`, as a Chrome
`intent:` URL with `package=dev.vitruvian.remote`. `<Host>` is the request's own `Host` header,
the address the phone already reached, and must be a bare `host[:port]` or the page is a 400. A
code that is not six digits is a 400. The page sends `Content-Security-Policy: default-src 'none'`.

# v1.10 additions: HomeSpeaker sources and replay

HomeSpeaker 1.23 can switch each sender on and off under its master switch (`enabled`): the two
coding agents, and the chat apps it watches. The phone gets the same switches, and a list of recent
broadcasts it can replay with a tap.

`GET /v1/homespeaker` gains `announce_claude_code`, `announce_antigravity`, `announce_opencode`,
`slack_enabled`, `google_chat_enabled` and `beeper_enabled` (bool; the program's setting of the same
name) and `recent` (`[{text, target, source, at}]`, the newest 5 of the program's history, newest
first). `last` stays, and is `recent[0]` whenever both are present.

`POST /v1/homespeaker` accepts the six switches as optional bools; each is a `set` operation. A body
with none of the recognised fields is 400.

**Replay** is `POST /v1/homespeaker/say` with the broadcast's `text`; no new endpoint. Two notes:

- The agent runs `--say` with `CLAUDECODE`, `ANTIGRAVITY_AGENT` and `AI_AGENT` removed from the
  child's environment. HomeSpeaker 1.23 infers who is speaking from those, so an agent started
  from a coding agent's shell would otherwise have a replay held by that agent's switch. Removing
  them works on every HomeSpeaker version; passing `--source user` would be refused by one older
  than 1.23.
- A replay runs `--say <text> --no-history` (Home Speaker 1.41+), so it is not listed again. The
  agent no longer snapshots and restores a history file.

The phone reads a reply without the five switches as an agent older than v1.10 and hides them. With
no `recent` it falls back to `last` as a one-row list.

---

## v1.11 — HomeSpeaker door routing, Gemini TTS & announcement style

HomeSpeaker ships through two doors (`apps/desktop/home-speaker/Sources/HomeSpeakerCore/Door.swift`):
the standalone `/Applications/HomeSpeaker.app` bundle (`"app"`) and the Vitruvian extension under
`~/Library/Application Support/Vitruvian/Tools/dev.vitruvian.homespeaker` (`"extension"`). Which
door is chosen is recorded in `~/.gemini/speaker_door.json`, which the agent reads (and never writes)
to pick the program. `active_door` is the document's `active_door`; `active_door` in a POST is a
`switchTo` operation, which Home Speaker refuses if that side is not installed (400).

When the choice file chooses `"extension"` (or records no choice and the standalone `.app` is
absent) and the extension's `bin/tool` exists outside `.Trash`, every request goes to that program
(`--version`, `--state`, `--apply`, `--say`, `--volume`, ...).

`GET /v1/homespeaker` adds nine fields: `active_door` (`"app"` \| `"extension"`), `local_engine`,
`gemini_voice`, `has_gemini_key` (bool, the value never leaves the Mac), `announcement_style`,
`style_model`, `beeper_announce`, `beeper_networks` (`[{key, name, state}]`; `state` is `"reading"`,
`"muted"` or `"skipped"`, from `chat.beeper_networks`) and `mute_own_messages`. Each is the
program's setting of that name (or its `sign_in` / `chat` entry).

`POST /v1/homespeaker` accepts `local_engine`, `gemini_voice`, `announcement_style`, `style_model`
and `beeper_announce` as optional strings and `mute_own_messages` as an optional bool (each a `set`;
Home Speaker refuses an unknown value with 400), and `beeper_network` as an optional
`{"key": string, "reading": bool}` object (`setNetwork`).

---

## v1.12 — Phone announcements (`This phone`)

HomeSpeaker can speak announcements on the paired Android phone over the phone bridge in addition to
(or instead of) the Google Home speakers and the Mac itself.

`GET /v1/homespeaker` adds `speak_phone`, `phone_pause_media` and `phone_headphones_only` (the
program's settings) and `phone_connected` (bool): whether the phone bridge currently holds an open
`/v1/phone/link` stream.

`POST /v1/homespeaker` accepts `speak_phone`, `phone_pause_media` and `phone_headphones_only` as
optional bools; each is a `set` operation.

`POST /v1/homespeaker/phone-say` — loopback (no bearer required from local processes on the Mac) or
act tier (pairing bearer token required from non-loopback peers), body up to 8 MiB:
`{"text": string, "wav_base64"?: string, "pause_media"?: bool, "headphones_only"?: bool}`.
- Blank `text` returns `400`.
- When `pause_media` or `headphones_only` is omitted, defaults are the `phone_pause_media` and
  `phone_headphones_only` settings in the chosen program's `--state`.
- Loopback requests without a bearer token must send `Content-Type: application/json` (`415` otherwise).
- When no phone link is open, replies `200 {"ok": false, "spoken": false, "reason": "no phone connected"}`.
- Otherwise dispatches `phone.speak` (`read` tier, 60 s timeout) over the phone bridge and returns
  `200 {"ok": true, "spoken": bool, "skipped"?: bool, "reason"?: string, "engine"?: "gemini"|"android_tts"}`.

---

## Cast voice, cloned voices and a custom announcement style

`GET /v1/homespeaker` adds `home_cast_voice` (bool: Google Home plays the selected local (Gemini)
voice cast to it instead of its own cloud voice), `custom_voices` (`[{id, name}]`, from the
document's `custom_voices`) and `custom_style_prompt` (the instruction used when `announcement_style`
is `"custom"`, omitted when empty).

`announcement_style` also accepts `"custom"`. `gemini_voice` is one of the prebuilt voices **or**
the `id` of any entry in `custom_voices`; a stored value that is neither reads as `"Kore"`.

`POST /v1/homespeaker` accepts `home_cast_voice` as an optional bool, `announcement_style:
"custom"`, and a `gemini_voice` matching a custom voice `id`; an unknown `gemini_voice` is refused by
Home Speaker (400). `custom_voices` is read-only here; `custom_style_prompt` can be set or cleared
via POST.

---

## Full Desktop HomeSpeaker parity

### `GET /v1/homespeaker` parity extensions

The following status and diagnostic fields bring `/v1/homespeaker` to full parity with desktop `HomeSpeakerToolCore`:

| Field | Type | Description |
|---|---|---|
| `quiet_hours.active` | bool | Whether quiet hours are currently silencing announcements |
| `snooze_until` | string \| null | ISO-8601 UTC timestamp until which announcements are snoozed, or `null` when not snoozed |
| `available_voices` | `[{id, name, lang}]` | Installed macOS voices, as Home Speaker lists them (`language` → `lang`) |
| `structure_id` | string | Google Home structure ID |
| `homes` | `[{id, name}]` | Available Google Home structures discovered from targets |
| `account_email` | string | Google account email address (`sign_in.email`) |
| `has_oauth_client` | bool | Whether custom Google Cloud OAuth client credentials exist |
| `has_antigravity_tokens` | bool | Whether local Antigravity OAuth tokens file is available to import |
| `monitor_running` | bool | Whether the chat-monitor background monitoring process is active |
| `last_poll_at` | string | Timestamp of the last chat monitor poll cycle |
| `slack_identity` | string | Authenticated Slack identity |
| `active_google_chat_backend` | string | Active Google Chat backend (`"api"` or `"gws"`) |
| `chat_runtime_error` | string | Recent runtime error reported by chat monitor |
| `has_slack_token` | bool | Whether Slack token is stored in secrets |
| `has_beeper_token` | bool | Whether Beeper access token is stored in secrets |
| `has_google_chat_token` | bool | Whether Google Chat OAuth refresh token is stored in secrets |
| `has_chat_access` | bool | Whether Google Chat consent has been granted (Google Chat only; equal to `has_google_chat_token`) |
| `gws_installed` | bool | Whether `gws` CLI executable is installed on the Mac |
| `gws_account` | string | Google Workspace account email configured for chat monitor |
| `google_chat_source` | string | Backend for Google Chat (`"auto"`, `"api"`, or `"gws"`) |
| `poll_interval` | int | Polling frequency in seconds (`poll_interval_seconds`; Home Speaker owns the default and range) |
| `agents` | `[{agent, hook_state, speaks_twice, configured_by_instruction}]` | Integration status for `claude-code`, `antigravity`, and `opencode` (phone can install, update, or remove hooks for all three) |
| `legacy_launch_agent` | bool | Whether Home Speaker reports the legacy chat-monitor launch agent |
| `custom_oauth_client_id` | string | Saved Google Cloud OAuth client ID (always shown on phone) |
| `has_custom_oauth_secret` | bool | Whether custom OAuth client secret is saved |
| `home_speaker_version` | string | Version of the installed HomeSpeaker application |
| `settings` | `[{key, kind, label, value, shown, choices?:[{value, label}], limits?:{min, max, step, default_value}}]` | Home Speaker's own `--state --json` catalog passed through verbatim when `available: true` (omitted when unavailable). Current phones read labels, choice lists, limits, and visibility rules directly from this array; top-level fields remain for older phones |
| `outputs_label` | string | Home Speaker's summary of active outputs (`outputs_label` from `--state --json`), omitted when unavailable |
| `outputs_footer` | string | Home Speaker's explanation of active outputs (`outputs_footer` from `--state --json`), omitted when unavailable |
| `targets[].display_line` | string | Home Speaker's formatted label for each speaker (`speakers[].display_line` from `--state --json`) alongside `key`, `name`, `room`, `type`, and `selected` |

`available_voices` comes from Home Speaker's `--state` (the agent no longer runs `say -v '?'` or caches a
listing), so it follows whatever Home Speaker lists.

### `POST /v1/homespeaker` parity updates

The update endpoint supports these additional configuration actions and secret updates:

| Field | Type | Behavior |
|---|---|---|
| `quiet_hours_start`, `quiet_hours_end` | string (`HH:MM`) | `set`; Home Speaker refuses invalid times (400) |
| `snooze_until` | string \| null | `""` or `null` clears the snooze (`snooze` with `clear`); a future ISO-8601 time is sent as the minutes to it (the program snoozes for `1`–`240` minutes); a time in the past or an unparseable one is 400 |
| `snooze_minutes` | int | `snooze` with `minutes`; Home Speaker refuses values outside `1`–`240` (400) |
| `custom_style_prompt` | string | Updates or clears phrasing rewrite instruction |
| `local_voice` | string | `set` the macOS system voice identifier |
| `preview_voice` | bool | Previews the Mac voice (the program's `local_voice`) locally via macOS `say` (never broadcasts to speakers) |
| `test_media_pause` | bool | Executes `HomeSpeaker --test-media-pause` |
| `active_door` | `"app"` \| `"extension"` | `switchTo`, sent last and alone; Home Speaker changes the choice file, not the agent |
| `discover` | bool | Executes `HomeSpeaker --discover` to refresh targets |
| `structure_id` | string | Switches the active home via `HomeSpeaker --discover --save --home <id>` |
| `remove_target` | string | `removeSpeaker` |
| `sign_in` | bool | Launches `HomeSpeaker --sign-in` detached on the Mac so the user can complete Google Home OAuth in the Mac browser |
| `sign_out` | bool | Runs `HomeSpeaker --sign-out` (the program clears its own tokens) |
| `import_antigravity` | bool | `importAntigravity` |
| `grant_chat` | bool | Launches `HomeSpeaker --sign-in --chat` detached on the Mac so the user can grant Google Chat OAuth consent |
| `disconnect_chat` | bool | Runs `HomeSpeaker --sign-out --chat` |
| `speak_clipboard` | bool | Reads text from the macOS clipboard and announces it |
| `google_chat_source` | `"auto"` \| `"api"` \| `"gws"` | `set` |
| `gws_account` | string | Configures GWS account email for chat monitor |
| `poll_interval` | int | `set` `poll_interval_seconds` (Home Speaker clamps or refuses out-of-range values) |
| `slack_token` | string | `setSecret` `slack` (empty string clears) |
| `beeper_token` | string | `setSecret` `beeper` (empty string clears) |
| `gemini_api_key` | string | `setSecret` `geminiKey` (empty string clears) |
| `oauth_client_id`, `oauth_client_secret` | string | one `saveOAuthClient` (a secret alone uses the saved custom client id; none saved is 400 "Enter the client ID first.") |
| `agent_hook_action` | string | `agentHook` for `"install:<agent>"`, `"remove:<agent>"`, `"add-instruction:<agent>"` (`claude-code`, `antigravity`, `opencode`), sent alone after the plain batch. `"disable-rival…"` is `agentHook` `disableRival` and `"remove-legacy-agent"` is `removeLegacyAgent`, each alone |
| `chat_monitor_action` | `"start"` \| `"stop"` | Starts or stops the chat monitor daemon |
| `reset_settings` | bool | `reset` |

### Courier beside Beeper

HomeSpeaker 1.37 reads chats from Courier as well as Beeper: the same local API on its own port,
with its own token and its own switch, Announce choice and network list. The agent mirrors them the
way it mirrors Beeper's.

`GET /v1/homespeaker` adds `courier_enabled`, `courier_announce` (`"direct_and_mentions"` \| `"all"`),
`courier_networks` (`[{key, name, state, read_anyway?}]`; `read_anyway: true`, sent only when true,
marks a network read through Courier although Home Speaker's own Slack or Google Chat reader covers
it), `courier_networks_listed` / `beeper_networks_listed` (bool: whether the running monitor has
listed that app's networks; until it has, only the saved mutes are known) and `has_courier_token`
(bool, the value never leaves the Mac). All come from the document's settings and `chat` entry.

`POST /v1/homespeaker` accepts:

| Field | Type | Operation |
|---|---|---|
| `courier_enabled` | bool | `set`. Home Speaker refuses turning it on while no Courier token is saved (400) |
| `courier_announce` | `"direct_and_mentions"` \| `"all"` | `set` |
| `courier_network` | `{"key": string, "reading": bool}` | `setNetwork` (app `courier`), as `beeper_network` does Beeper's |
| `courier_read_anyway` | `{"key": string, "on": bool}` | `setReadAnyway`: a network Home Speaker's own reader covers is read through Courier as well, which is how a second Slack workspace is heard |
| `courier_token` | string | `setSecret` `courier` (never logged or echoed); an empty string clears it, and Home Speaker turns Courier off |

### `POST /v1/homespeaker/say` replay support

Accepts `replay: true` or `replay_id: "<id>"`. A `replay_id` is looked up in the `recent` list of
the program's `--state` (the agent reads no history file) and its text is said with
`--say <text> --no-history`, so a replay is not recorded again; an id that is no longer there is
400. Plain `POST /v1/homespeaker/say` stays plain `--say <text>`.

---

## Say who an announcement is from

Home Speaker can start each announcement with the app it came from ("Claude: …"), or the app and
the session when several sessions of one app are talking ("Claude, Courier: …"). It is one choice
setting, `announce_source`, off by default.

`GET /v1/homespeaker` adds `announce_source` (`"off"` \| `"app"` \| `"app_and_session"`), read
from the document's settings. An older Home Speaker sends nothing; the phone reads that as off and
hides the row, because the catalog has no `announce_source` entry.

`POST /v1/homespeaker` accepts `announce_source` with the same values; it is a `set` operation, and
Home Speaker rejects any other value.

---

# Sony Google TV (`/v1/tv`)

Drives a Sony Google TV over wireless ADB from the Mac.

### `GET /v1/tv` (read)

Connects to the configured TV (`adb connect <address>`) and runs a single combined shell query (`dumpsys power`, `dumpsys window displays`, `/proc/meminfo`) with a 5 s timeout.

```json
{
  "available": true,
  "reason": "",
  "connected": true,
  "awake": true,
  "dreaming": false,
  "foreground": "Projectivy Home",
  "mem_available_mb": 1024,
  "address": "192.168.86.31:5555"
}
```

- `available`: `true` when `adb` is found on the Mac (`/opt/homebrew/bin/adb`, `/usr/local/bin/adb`, `~/Library/Android/sdk/platform-tools/adb`, or `PATH`).
- `foreground`: one of `"Projectivy Home"`, `"SmartTube 4K"`, `"AerialViews 4K"`, `"Disney+"`, `"Netflix"`, `"Awake"`, or `"Standby"`.
- `address`: read from `~/.config/vitruvian/tv.json` (`address` or `tvAddress`), falling back to `~/Library/Application Support/com.vitruviansoftware.vitruvian/ToolData/dev.vitruvian.tv/storage.json`, then `"192.168.86.31:5555"`.

### `POST /v1/tv/act` (act — Bearer token)

Accepts `{"action": "<action>", "target": "<target>", "url": "<url>", "address": "<address>"}` and replies with the refreshed `GET /v1/tv` state JSON.

| `action` | `target` / `url` / `address` | Behavior |
|---|---|---|
| `toggle_power` | – | Atomically checks `mWakefulness` and sends `KEYCODE_SLEEP` when awake/dreaming or `KEYCODE_WAKEUP` when asleep |
| `start_aerial` | – | Wakes the TV and starts AerialViews 4K daydream (`com.android.systemui/.Somnambulator`) |
| `launch_app` | `projectivy` \| `smarttube` \| `disney` \| `netflix` | Wakes the TV and launches the app via `monkey` |
| `hdmi` | `1` \| `2` \| `3` \| `4` | Wakes the TV and switches to the Sony external HDMI passthrough input (`HW1`–`HW4`) |
| `key` | `volume_up` \| `volume_down` \| `mute` \| `play_pause` \| `home` \| `back` \| `up` \| `down` \| `left` \| `right` \| `select` | Sends the corresponding Android `input keyevent` code |
| `cast_url` | `url`: `http://...` or `https://...` | Validates and safely quotes the URL, then opens it in SmartTube (`com.liskovsoft.smarttubetv.beta`) |
| `trim_caches` | – | Runs `pm trim-caches 999999999999999999` |
| `reconnect` | optional `address`: `<host>:<port>` | Runs `adb disconnect <address>` followed by `adb connect <address>` to reset stale TCP transports and re-trigger the TV's USB debugging authorization prompt |
| `set_address` | `address`: `<host>:<port>` | Validates `host:port`, persists it to `~/.config/vitruvian/tv.json`, and reconnects ADB to the new address |


