# vitruvian-remote-agent

The Mac half of [Vitruvian Remote](../README.md): a small Go daemon that
serves the machine's vital signs over HTTP so the phone can show real numbers
instead of `MockHost`, and — once you have paired a phone from this Mac's
keyboard — runs commands for it.

The full request/response contract is [API.md](API.md). This file is the
operator's view: what it can do to your machine, and how to turn that on.

## The trust model, stated plainly

There are two tiers, and only one of them is dangerous.

**Reading** needs nothing but reachability. Metrics, host, processes, VMs,
containers, Kubernetes nodes, volume, Claude Code sessions, a PromQL proxy.
Everything there is what Activity Monitor already shows anyone sitting at the
keyboard, so the tailnet is the boundary and there is no token.

**Acting** needs a bearer token: `/v1/exec` and `/v1/exec/stream`, both
clipboard verbs, `POST /v1/audio`, `POST /v1/power`, and the v1.2 additions —
`/v1/claude/resume`, `/v1/prs/action`, `/v1/argocd/sync`, `/v1/screen`,
`/v1/notify/test`. A phone holding that token can run
arbitrary commands as your user. There is no sandbox, no allowlist and no
confirmation prompt — `exec` with `kind: "shell"` is a login `zsh`. That is
the feature; pretending otherwise would be the security problem.

What bounds it:

- The token is 64 hex characters, lives in `~/.config/vitruvian-remote-agent/token`
  at mode `0600`, and is compared in constant time.
- The **only** way to get one is pairing, and pairing needs someone typing a
  code into a terminal on this Mac. A five-minute window, and five wrong
  guesses delete it.
- Every act call is logged with its kind and the first 80 characters of the
  command, so the Mac keeps a record of what the phone did.
- `vitruvian-remote-agent token --rotate` un-pairs every phone, immediately.

v1.0 of this agent was read-only and said so everywhere. v1.1 is not, and
`/healthz` reports `read_only: false` so a client can tell which one it is
talking to.

## Pair a phone

1. Open the app on the phone. It shows a six-digit code with a five-minute
   life.
2. On the Mac:

   ```sh
   bazel run //mobile/android/remote/macagent:pair -- 482917
   ```

   That writes `~/.config/vitruvian-remote-agent/pair.json`. A running agent
   picks it up on its next request — nothing to restart.

3. The phone polls `POST /v1/pair` until it gets a token, then keeps it.

The window is one-shot: the first phone through it closes it, so a second
device that overheard the code gets nothing.

## Endpoints

Read (no auth):

| Method | Path             | What                                                                          |
| ------ | ---------------- | ----------------------------------------------------------------------------- |
| GET    | `/v1/metrics`    | CPU, memory, battery, disk, network, thermal, uptime                          |
| GET    | `/v1/host`       | hostname, model, chip, cores, memory, OS, MAC address, Wake-on-LAN            |
| GET    | `/v1/processes`  | top 8 by CPU                                                                   |
| GET    | `/v1/vms`        | Lima instances                                                                 |
| GET    | `/v1/containers` | Docker, falling back to podman                                                 |
| GET    | `/v1/k8s`        | nodes, when started with `--kube-context`                                      |
| GET    | `/v1/audio`      | output volume and mute                                                         |
| GET    | `/v1/sessions`   | Claude Code projects active in the last 30 min, and live `claude` processes    |
| GET    | `/v1/promql`     | proxies one instant query, when started with `--prometheus-url`               |
| GET    | `/v1/claude/sessions` | every live Claude Code session and what it is doing (v1.2)               |
| GET    | `/v1/prs`        | your open pull requests and their check counts (v1.2)                         |
| GET    | `/v1/argocd`     | ArgoCD Applications, sync and health (v1.2)                                   |
| GET    | `/healthz`       | 200 while readings are fresh (<30 s), 503 otherwise                            |

Act (`Authorization: Bearer <token>`):

| Method | Path                 | What                                                 |
| ------ | -------------------- | ---------------------------------------------------- |
| POST   | `/v1/exec`           | `shell`, `applescript`, `shortcut` or `claude`        |
| POST   | `/v1/exec/stream`    | the same, streamed line by line as SSE (v1.2)         |
| POST   | `/v1/claude/resume`  | `claude --resume <id> -p <prompt>` (v1.2)             |
| POST   | `/v1/prs/action`     | approve, merge, auto\_merge, ready (v1.2)             |
| POST   | `/v1/argocd/sync`    | sync one Application (v1.2)                           |
| GET    | `/v1/screen`         | a JPEG of the main display (v1.2)                     |
| POST   | `/v1/notify/test`    | send a test push (v1.2)                               |
| GET    | `/v1/clipboard`      | `pbpaste`                                             |
| POST   | `/v1/clipboard`      | `pbcopy`                                              |
| POST   | `/v1/audio`          | set output volume, 0–100                              |
| POST   | `/v1/power`          | `sleep` or `restart`                                  |

Plus `POST /v1/pair`, which is unauthenticated because it is how a phone gets
the credential. Anything else is a `405`. Responses carry
`Cache-Control: no-store`, and errors are `{"error": "..."}`.

Reading the clipboard counts as an **act**, despite the verb: it is where
passwords live for thirty seconds at a time, and it is not something anyone
can see from Activity Monitor.

## Flags

| Flag                | Default                            | What                                              |
| ------------------- | ---------------------------------- | ------------------------------------------------- |
| `--listen`          | `127.0.0.1:7411`                   | address to listen on                              |
| `--tailscale`       | `true`                             | also listen on this machine's Tailscale IPv4      |
| `--interval`        | `2s`                               | how often to refresh                              |
| `--config-dir`      | `~/.config/vitruvian-remote-agent` | where the token and pairing live                  |
| `--kubeconfig`      | *(empty)*                          | kubeconfig **file** for `/v1/k8s`; the lab cluster's is `~/.kube/cluster.yaml`, not the default |
| `--kube-context`    | *(empty)*                          | kubeconfig context for `/v1/k8s`                  |
| `--prometheus-url`  | *(empty)*                          | Prometheus base URL for `/v1/promql`; Grafana's datasource proxy works here |
| `--prometheus-token-file` | *(empty)*                    | bearer token file for the upstream, 0600, never logged |
| `--ntfy-url`        | *(empty)*                          | ntfy base URL for push notifications, e.g. `https://ntfy.ipv1337.dev` |
| `--ntfy-topic`      | *(empty)*                          | the topic to publish to — treat it as a secret, anyone who knows it can read it |
| `--ntfy-token-file` | *(empty)*                          | bearer token file for ntfy, 0600, never logged    |
| `--gh-extra-repos`  | *(empty)*                          | comma-separated `owner/repo` whose open PRs are listed whoever wrote them |
| `--exec-dir`        | *(empty = the agent's cwd, `~`)*   | working directory for console commands and macros; point it at the repo so `bazel run //:tidy` finds its workspace |

`install.sh` passes every flag after `--` straight through into the
LaunchAgent plist, so the v1.2 flags are installed the same way the older ones
are (a leading `~` in a value is expanded, because launchd runs no shell):

```sh
bazel run //mobile/android/remote/macagent:install -- \
  --kubeconfig ~/.kube/cluster.yaml --kube-context default \
  --ntfy-url https://ntfy.ipv1337.dev --ntfy-topic vitruvian-remote-xxxxx \
  --ntfy-token-file ~/.config/vitruvian-remote-agent/ntfy-token \
  --gh-extra-repos VitruvianSoftware/vitruvian-core \
  --exec-dir ~/Workspace/gh/application/vitruvian/vitruvian-core
```

An empty `--kube-context` means **not configured**, not "whatever kubectl
currently points at" — otherwise the agent would report a production cluster
to a phone because somebody ran a kubectl command three days ago.

Subcommands: `pair <code>`, and `token [--rotate]`.

## v1.2: what was added, and what it is honestly good for

v1.1 could show you the Mac and run a command on it. v1.2 is about the three
things you actually wait on — a coding agent, a pull request, a deploy — and
about being told rather than having to look.

### Streaming a command — `POST /v1/exec/stream`

The same request body as `/v1/exec`, but the reply is Server-Sent Events and
lines arrive as they are produced: `event: line` per line of stdout or stderr,
`: keepalive` every 15 s while nothing prints, and `event: exit` last with the
code and the duration. Default bound 600 s, up to 3600 if the caller asks.

Two details worth knowing:

- **Cancelling is hanging up.** There is no cancel message. When the client
  disconnects, the agent kills the command's **process group** — not just the
  child. `zsh -lc 'sleep 30'` execs into `sleep`; killing only the shell would
  leave that `sleep` behind, and a phone that walked out of range would leak a
  process per cancelled command.
- **stdout and stderr interleave** in the order they were produced, because
  two goroutines feed one channel. Draining one pipe first would hold every
  error line back until the build finished, which is the moment you no longer
  need it.

### Claude Code sessions — `GET /v1/claude/sessions`, `POST /v1/claude/resume`

One row per project, from the newest transcript under `~/.claude/projects/`,
reading only its **last 64 KiB** — these files reach hundreds of megabytes and
this runs every five seconds. `session_id` is the `.jsonl` filename stem,
which is exactly what `claude --resume` takes.

`state` is a **heuristic and the contract says so.** Claude Code writes no "I
am blocked on a permission prompt" record, so the only evidence is the shape
of the last few entries:

| state                    | what the transcript looks like                              |
| ------------------------ | ------------------------------------------------------------ |
| `waiting_for_permission` | last message is an assistant tool call with no result for ≥ 90 s — a permission prompt, or a long command; the transcript cannot tell, so the push says "may be waiting" |
| `working`                | a tool result just landed, or the tool call is under 90 s old |
| `idle`                   | the turn ended in prose — it is your move                     |
| `unknown`                | nothing parseable in the tail                                 |

The twenty seconds is a guess, and it is the useful guess to make: a tool call
that has produced nothing for that long is usually a permission prompt and
occasionally a slow `grep`. Being told wrongly costs you two seconds; not
being told costs you the afternoon.

`POST /v1/claude/resume {session_id, prompt}` picks a session up where it
stopped, through the same exec machinery (300 s bound, `/v1/exec`'s reply
shape).

### Pull requests — `GET /v1/prs`, `POST /v1/prs/action`

`gh search prs --author @me --state open`, then one `gh pr view` per PR, every
sixty seconds — twenty-one round trips to github.com per refresh, which is why
it is on its own clock. `checks` is a **count**, not a list: a phone has room
for "26 green, 19 skipped", not for forty-five rows. Skipped is its own bucket
because folding it into failure would call every clean PR red.

`gh` missing or logged out is `available:false` with gh's own message —
`gh auth login` is the next step and nothing this agent writes says it better.
`--gh-extra-repos` adds repos whose open PRs are listed whoever wrote them.

Actions are the four in the contract (`approve`, `merge`, `auto_merge`,
`ready`) and nothing else; anything else is a 400 rather than a `gh`
invocation nobody predicted. The reply carries gh's **stdout and stderr**,
because gh writes "Merged pull request #2226" to stderr.

### ArgoCD — `GET /v1/argocd`, `POST /v1/argocd/sync`

Needs the same `--kubeconfig` / `--kube-context` as `/v1/k8s`; without them it
is `available:false, reason:"not configured (--kube-context)"`, never a guess
at kubectl's current context. The cluster's answer is about two megabytes,
nearly all of it the per-app resource inventory, and the agent drops it before
anything crosses a phone network.

Sync is a `kubectl patch` writing an empty sync operation — the same thing the
ArgoCD UI's Sync button writes — because the `argocd` CLI would need a login
this agent has no way to obtain. It records `vitruvian-remote` as the
initiator, so the app's history says who did it.

### Screen peek — `GET /v1/screen?width=800`

A JPEG of the main display: `screencapture -x -t jpg` then `sips
--resampleWidth`, cached for two seconds so a thumb resting on a refreshing
thumbnail does not run `screencapture` ten times a second. `no-store`, and the
temporary file is deleted before the reply is sent.

**This is the endpoint most likely to refuse.** Screen Recording is granted to
a specific *binary* by a person in System Settings, and an agent installed by
`bazel run :install` has never been granted it — so the honest first answer on
most machines is:

```
503 {"available":false,
     "reason":"Screen Recording is not granted to the agent — System Settings → Privacy & Security → Screen Recording"}
```

Grant it to `~/.local/bin/vitruvian-remote-agent` once. A black rectangle
would be worse than the error.

### Notifications — the one thing that goes the other way

Everything else here answers a question the phone asked. This is the agent
telling you something while your phone is asleep, which is the only fix for
"Claude stopped at a permission prompt and nobody noticed for an hour".

ntfy rather than Apple push: a topic is a URL and the ntfy app subscribes to
it — no developer account, no certificate, no per-app registration. The trade
is that **anyone who learns the topic name can read it**, so pick an
unguessable one and treat it as a secret. The token is a 0600 file and is
never logged, never echoed in a response and never quoted in an error.

Five events, each sent once per **transition** and debounced 30 s per key:

| Key                            | When                                          | Title                        |
| ------------------------------ | --------------------------------------------- | ---------------------------- |
| `claude:<session>:permission`  | a session enters `waiting_for_permission`     | Claude Code is waiting       |
| `claude:<session>:idle`        | a session goes `working` → `idle`             | Claude Code finished a turn  |
| `exec:<id>`                    | a streamed command exits                      | Command finished · exit N    |
| `pr:<repo>#<n>:green` / `:red` | a PR's checks settle, either way              | PR #n checks green / failed  |
| `agent:start`                  | the agent starts                              | Agent online                 |

On the transition, not per tick: a session still waiting four seconds later is
not news, and a PR that has been green all day is not either. A state seen for
the **first** time is never announced, or every restart would fire one push per
open PR. `Click` carries a `vitruvian-remote://<screen>` deep link, so tapping
the notification opens the phone where the news is.

`POST /v1/notify/test` proves the path end to end and deliberately bypasses
the debounce — pressing a test button twice should send twice. Without the
flags it answers `400` naming them, rather than "unavailable". `/healthz`
grows a `notify: {configured, topic}` block; the token is not in it.

Publishing failures are logged and dropped. A sampler that stalled because
ntfy was down would take the metrics with it, and the metrics are the point.

## What it reads, and what it honestly cannot

Sampling uses tools an unprivileged process may run: `top`, `vm_stat`,
`sysctl`, `ioreg`, `df`, `netstat`, `route`, `pmset`, `sw_vers`, `ifconfig`,
`ps`, `limactl`, `docker`, `podman`, `kubectl`, `osascript`. Fixed arguments,
no shell, nothing from a request in an argv.

`exec.go` is the **only** file that executes anything, and the only one that
imports `os/exec`. Sampling and acting both go through it; the difference is
that sampling's argv are constants and acting's are not, which is why acting
is behind the token.

An optional tool that is absent or wedged returns `available: false` with a
**reason** — never an empty list. "No containers running" and "the Docker
daemon is down" look identical otherwise, and only one of them needs you.

What macOS will not hand an unprivileged process is reported as absent in
`unavailable`, with the reason, never estimated:

- SoC temperature and fan speed (need an SMC reader). The one temperature
  available is the battery pack's own sensor, in `battery.temperature_c`.
- GPU and Neural Engine load, and package power (need `powermetrics`, which
  needs root). [`ops/macos-power-agent`](../../../../ops/macos-power-agent/README.md)
  went root for exactly this and pushes it to Prometheus — which is what
  `--prometheus-url` and `/v1/promql` are for.

Three figures are easy to misread and are documented in the JSON field names:

- `cpu.ready` is `false` for the first few seconds after start, while `top`
  takes the two samples a real percentage needs. Until then `cpu.*` is zero,
  and zero is not "idle".
- `memory.free_percent` is the **kernel's** number (`kern.memorystatus_level`),
  the one the pressure graph and memory warnings are based on. It is not
  `100 - used_percent`.
- `battery.draw_watts` is the battery's discharge rate, so it reads `0` on AC.
  That is the truth about the battery and says nothing about wall draw.

`/v1/sessions`'s `project` is a **label, not a path**: Claude Code encodes a
project directory by replacing `/` with `-`, which is lossy for any directory
whose own name contains a hyphen.

## Run it

```sh
bazel run //mobile/android/remote/macagent            # foreground, Ctrl-C to stop
curl -s http://127.0.0.1:7411/v1/metrics | jq .
```

Install as a login item for the current user (no sudo):

```sh
bazel run //mobile/android/remote/macagent:install
```

That copies the built binary to `~/.local/bin`, writes a LaunchAgent to
`~/Library/LaunchAgents`, starts it, and **proves it answers** before
reporting success. Logs go to `~/Library/Logs/vitruvian-remote-agent.log` —
including every act call.

## Network posture

Listens on `127.0.0.1:7411` and, if the machine has one, its Tailscale IPv4
(found by looking for an address in `100.64.0.0/10`, so the `tailscale` CLI is
not required). It never binds `0.0.0.0`.

The tailnet is the boundary for reading. It is **not** the boundary for
acting: anything that reaches the port can still only run commands with a
token it does not have. The transport is plain HTTP *inside* the WireGuard
tunnel Tailscale already provides, so there is no TLS to manage and the token
is not cleartext on the wire.

## macOS permissions the agent does not have by default

The agent runs as a plain user process, and macOS gates some things behind
per-app consent that no install script can grant:

- **Screen Recording** — both `GET /v1/screen` and `screencapture` from the
  *Screenshot → clip* macro need it. Until the agent is allowed under System
  Settings → Privacy & Security → Screen Recording, `/v1/screen` answers `503`
  with that exact sentence and the macro shows `could not create image from
  display`. Neither pretends it worked.
- **Automation** — an AppleScript that drives another app (`tell app
  "Finder" …`) prompts the first time and is refused if the prompt is not
  answered on the Mac.

Grant them to `~/.local/bin/vitruvian-remote-agent`. **They do not survive a
reinstall on their own.** macOS keys a grant to the binary's code-signing
requirement, and for an ad-hoc signed Go binary that is the build's hash: after
`:install` the pane still shows the toggle ON while `/v1/screen` keeps answering
503 (found the hard way -- a fresh grant against yesterday's build did nothing
for today's). The installer therefore signs the binary with a self-signed
"Vitruvian Remote Agent" identity when one is in the login keychain, which
makes the requirement *identifier + certificate* and stable across rebuilds.
Create it once (no admin rights, no trust settings needed):

```sh
d=$(mktemp -d) && cd "$d" && printf '%s\n' '[req]' 'distinguished_name=dn' 'x509_extensions=ext' 'prompt=no' \
  '[dn]' 'CN=Vitruvian Remote Agent' '[ext]' 'keyUsage=critical,digitalSignature' \
  'extendedKeyUsage=critical,codeSigning' 'basicConstraints=critical,CA:false' > cs.cnf &&
openssl req -x509 -newkey rsa:2048 -nodes -keyout k.pem -out c.pem -days 3650 -config cs.cnf &&
openssl pkcs12 -export -inkey k.pem -in c.pem -out id.p12 -passout pass:x -name "Vitruvian Remote Agent" -legacy &&
security import id.p12 -k ~/Library/Keychains/login.keychain-db -P x -T /usr/bin/codesign && cd / && rm -rf "$d"
```

`security find-identity` lists it as `CSSMERR_TP_NOT_TRUSTED`; that is fine,
codesign does not need trust. After the first signed install, grant Screen
Recording one more time -- the identity changed, so it is a new client to
macOS -- and it stays granted from then on. The install summary prints which
of the two states you are in.

## Testing

The parsers in `metrics/` are pure functions pinned by fixtures captured from
a real machine, so they run on the Linux CI runner. The pairing and
authorisation tests run there too — they touch a temp directory, not
`~/.config`.

What CI cannot check is the macOS commands themselves. `runAct`'s shell test
skips where there is no `/bin/zsh`, so that assertion is exercised on a Mac
and nowhere else; `bazel run` on a Mac plus `curl` is the rest of that check.
