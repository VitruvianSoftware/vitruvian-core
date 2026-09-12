# macos-power-agent

A tiny LaunchDaemon that samples a Mac's **compute power** (Apple Silicon SoC or
Intel package power, via `powermetrics`) and **battery state** (via `pmset` /
`ioreg`), and pushes them to the homelab Prometheus **Pushgateway**. It powers
the **Node Power** Grafana dashboard.

## Why this exists

The homelab's "laptop" k8s nodes are **Lima VMs** running on these Macs. A VM
can't see its host's battery or read Apple's SoC power counters, so power for the
Mac hosts can't come from `node-exporter` inside the cluster — it has to be
collected on the macOS host itself and pushed in. (The bare-metal Intel NUCs are
handled separately: `node-exporter` runs as root there and exports Intel RAPL
`node_rapl_*_joules_total`, which the dashboard reads directly.)

These figures are **silicon/package power, not whole-system wall draw** — the
honest number macOS exposes without extra hardware. Good for trends and
comparison, not a substitute for a smart plug.

## What it reports

Gauges, labelled `job="mac_power"`, `instance="<host>"`:

| Metric                                                                | Meaning                                                                    |
| --------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `mac_soc_power_watts`                                                 | SoC package power (AS: CPU+GPU+ANE combined; Intel: derived package power) |
| `mac_cpu_power_watts` / `mac_gpu_power_watts` / `mac_ane_power_watts` | per-domain power (Apple Silicon only)                                      |
| `mac_battery_percent`                                                 | charge %                                                                   |
| `mac_ac_online`                                                       | `1` on AC, else `0`                                                        |
| `mac_battery_charging`                                                | `1` if charging                                                            |
| `mac_battery_discharge_watts`                                         | battery draw (`>0` only off AC)                                            |
| `mac_power_agent_last_push_seconds`                                   | unix ts of the last push (staleness probe)                                 |

## How it reaches Prometheus

```
powermetrics/pmset ──> power-agent.sh ──HTTPS push──> pushgateway.lab.ipv1337.dev
                                                          │ (Traefik ingress, tailnet-only)
                                                          ▼
                                          Prometheus scrape job `prometheus-pushgateway`
                                                  (honor_labels: true)
```

The push target is the in-cluster Pushgateway exposed via a Traefik ingress
(`gitops/argocd/platform/prometheus/applicationset.yaml`). The lab DNS record
resolves to the cluster's internal Traefik LB, so it's reachable only from
tailnet devices.

## Install (per Mac)

Runs as a system LaunchDaemon (root) so `powermetrics` needs no `sudo`.

```bash
# copy this directory to the Mac (or run from a tailnet checkout), then:
sudo ./install.sh                 # instance = lowercased short hostname
# or pin the instance name explicitly:
sudo ./install.sh james-macbook-pro
```

The installer drops `power-agent.sh` at `/usr/local/bin/vitruvian-power-agent`,
writes `/usr/local/etc/vitruvian-power-agent.conf`, installs the plist to
`/Library/LaunchDaemons/`, and (re)bootstraps the daemon. First push lands within
~30s. Logs: `/var/log/vitruvian-power-agent.log`.

### Configuration

`/usr/local/etc/vitruvian-power-agent.conf` (sourced by the script):

```sh
INSTANCE="james-macbook-pro"
PUSHGATEWAY_URL="https://pushgateway.lab.ipv1337.dev"
JOB="mac_power"
```

## Uninstall

```bash
sudo launchctl bootout system/com.vitruvian.power-agent
sudo rm -f /Library/LaunchDaemons/com.vitruvian.power-agent.plist \
           /usr/local/bin/vitruvian-power-agent \
           /usr/local/etc/vitruvian-power-agent.conf
```

To also clear the last-pushed series from the Pushgateway (so the dashboard stops
showing a stale flat line):

```bash
curl -X DELETE https://pushgateway.lab.ipv1337.dev/metrics/job/mac_power/instance/<host>
```

## Notes & caveats

- **Pushgateway holds the last value forever.** If a Mac sleeps or goes offline,
  its last reading stays until overwritten or deleted. The dashboard uses
  `mac_power_agent_last_push_seconds` to spot staleness; delete the group (above)
  to remove a retired host.
- **Sample cost:** one ~0.7s `powermetrics` run every 30s; negligible.
- **Intel Macs** report only `mac_soc_power_watts` (no CPU/GPU/ANE split).
