# vitruvian-remote-agent

The Mac half of [Vitruvian Remote](../README.md): a small, **read-only** Go
daemon that serves the machine's vital signs over HTTP so the phone can show
real numbers instead of `MockHost`.

## Why read-only, and why an agent at all

Bluetooth HID already gives the phone control of the Mac with nothing
installed — it pairs as a keyboard and mouse. What HID cannot do is ask a
question: it is a one-way channel. Every dashboard in the app was invented
because there was nothing to read from.

This answers questions and does nothing else. It runs **no commands on a
client's behalf**, has **no write path**, binds only to loopback and the
Tailscale interface, and needs **no root**. Kill it and the app falls back to
simulated data. Exec (macros, clipboard) is a deliberate later slice with its
own auth, not a feature this one is missing.

## Endpoints

| Method | Path          | What                                                          |
| ------ | ------------- | ------------------------------------------------------------- |
| GET    | `/v1/metrics` | The latest reading: CPU, memory, battery, disk, network, thermal, uptime |
| GET    | `/v1/host`    | Slow-changing: hostname, model, chip, cores, memory, OS, agent version |
| GET    | `/healthz`    | 200 while readings are fresh (<30 s), 503 otherwise           |

Anything else is a `405`. Responses carry `Cache-Control: no-store`.

## What it reads, and what it honestly cannot

Everything comes from tools an unprivileged process may run: `top`, `vm_stat`,
`sysctl`, `ioreg`, `df`, `netstat`, `route`, `pmset`, `sw_vers`. The exact
command lines are in `sampler.go`, which is the **only** file that executes
anything, with fixed arguments and no shell.

What macOS will not hand an unprivileged process is reported as **absent**
in `unavailable`, with the reason — never estimated:

- SoC temperature and fan speed (need an SMC reader). The one temperature
  available is the battery pack's own sensor, in `battery.temperature_c`.
- GPU and Neural Engine load, and package power (need `powermetrics`, which
  needs root). [`ops/macos-power-agent`](../../../../ops/macos-power-agent/README.md)
  went root for exactly this and pushes it to Prometheus; a PromQL proxy is
  the honest way to get it onto the phone later.

Three figures are easy to misread and are documented in the JSON field names:

- `cpu.ready` is `false` for the first few seconds after start, while `top`
  takes the two samples a real percentage needs. Until then `cpu.*` is zero,
  and zero is not "idle".

- `memory.free_percent` is the **kernel's** number (`kern.memorystatus_level`),
  the one the pressure graph and memory warnings are based on. It is not
  `100 - used_percent`.
- `battery.draw_watts` is the battery's discharge rate, so it reads `0` on AC.
  That is the truth about the battery and says nothing about wall draw.

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
reporting success. Logs go to `~/Library/Logs/vitruvian-remote-agent.log`.

## Network posture

Listens on `127.0.0.1:7411` and, if the machine has one, its Tailscale IPv4
(found by looking for an address in `100.64.0.0/10`, so the `tailscale` CLI
is not required). It never binds `0.0.0.0`. The tailnet is the boundary: a
device that is not on it cannot reach the agent at all, and a device that is
gets read-only numbers. That is the intended trust model for this slice; the
exec slice will add a token on top.

The transport is plain HTTP *inside* the WireGuard tunnel Tailscale already
provides, so there is no TLS to manage and nothing is cleartext on the wire.

## Testing

The parsers in `metrics/` are pure functions pinned by fixtures captured from a
real machine, so they run on the Linux CI runner. What CI cannot check is the
commands themselves; `bazel run` on a Mac and `curl` is that check.
