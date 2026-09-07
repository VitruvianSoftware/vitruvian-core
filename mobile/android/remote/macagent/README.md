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

**Acting** needs a bearer token: `/v1/exec`, both clipboard verbs,
`POST /v1/audio`, `POST /v1/power`. A phone holding that token can run
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
| GET    | `/healthz`       | 200 while readings are fresh (<30 s), 503 otherwise                            |

Act (`Authorization: Bearer <token>`):

| Method | Path            | What                                                     |
| ------ | --------------- | -------------------------------------------------------- |
| POST   | `/v1/exec`      | `shell`, `applescript`, `shortcut` or `claude`            |
| GET    | `/v1/clipboard` | `pbpaste`                                                 |
| POST   | `/v1/clipboard` | `pbcopy`                                                  |
| POST   | `/v1/audio`     | set output volume, 0–100                                  |
| POST   | `/v1/power`     | `sleep` or `restart`                                      |

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
| `--kube-context`    | *(empty)*                          | kubeconfig context for `/v1/k8s`                  |
| `--prometheus-url`  | *(empty)*                          | Prometheus base URL for `/v1/promql`              |

An empty `--kube-context` means **not configured**, not "whatever kubectl
currently points at" — otherwise the agent would report a production cluster
to a phone because somebody ran a kubectl command three days ago.

Subcommands: `pair <code>`, and `token [--rotate]`.

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

## Testing

The parsers in `metrics/` are pure functions pinned by fixtures captured from
a real machine, so they run on the Linux CI runner. The pairing and
authorisation tests run there too — they touch a temp directory, not
`~/.config`.

What CI cannot check is the macOS commands themselves. `runAct`'s shell test
skips where there is no `/bin/zsh`, so that assertion is exercised on a Mac
and nowhere else; `bazel run` on a Mac plus `curl` is the rest of that check.
