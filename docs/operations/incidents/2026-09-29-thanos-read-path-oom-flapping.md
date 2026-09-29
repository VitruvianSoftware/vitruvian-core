# Incident: Thanos read path OOM-flapping (2026-09-29)

|              |                                                                                  |
| ------------ | -------------------------------------------------------------------------------- |
| **Status**   | ✅ Mitigated — guardrails + alert live (PR #2605, 2026-09-29); follow-ups open     |
| **Severity** | SEV-3 — internal observability degraded; homelab, no external user impact        |
| **Impact**   | Grafana's default datasource (Thanos Query) briefly unavailable on each OOM; ~75 container restarts across the Thanos tier |
| **Detected** | 2026-09-29 ~22:10 UTC, by a scheduled health check — **no alert fired**          |
| **Components** | `monitoring/thanos-query`, `monitoring/thanos-storegateway`, `thanos-sidecar` in `monitoring/prometheus-server` |
| **Cluster**  | dev-local (k3s)                                                                   |

> Living document — keep the **Action items** section below up to date as follow-ups land.

## Summary

Some queries selected a very large share of all series at once. For each one, the
Thanos Querier, both Store Gateways and the Prometheus sidecars all tried to hold
those series in memory together, and were OOM-killed together. Raising every limit
to 2Gi (#2600) stopped the steady flapping but not the root cause: two more
tier-wide OOMs followed at the new limits (21:04 and 21:44 UTC). Nothing capped how
much one query may pull, and the existing crash-loop alert (>3 restarts in 15m)
never fires for 1–2 kills an hour, so it ran silent.

Prometheus itself (scraping, rule evaluation, alerting) never restarted — only the
read path through Thanos was affected.

## Timeline (UTC)

- **~17:10–19:30** — ~65 OOM restarts across sidecars, queriers and store gateways.
- **19:26** — #2600 merged: Thanos sidecar/query/storegateway limits raised to 2Gi. Steady flapping stops.
- **21:04** — `prometheus-server-1/thanos-sidecar` and `thanos-storegateway-0` OOMKilled together.
- **21:44** — both `thanos-query` pods and both store gateways OOMKilled within 15s of each other.
- **~22:10** — found by a cluster health check; only `Watchdog` firing.

## Root cause

1. **No per-query guardrail.** `--store.limits.request-series` defaulted to 0 (unlimited)
   on the sidecars, store gateways and querier; the query-frontend is disabled. One wide
   selector fans out to every store and each loads the full result.
2. **Series count grew ~17% in two days** (~555k → ~643k head series), almost all from
   the CI telemetry span metrics (`cicd_duration_seconds_bucket` ≈ 95k series; ~110k
   series carry `collector_instance_id`). Scraped series were flat. The baseline is
   dominated by API-server/etcd/kubelet histograms (~400k).
3. **Detection gap.** Sporadic OOM kills don't meet `KubePodCrashLooping`, and Thanos
   components aren't scraped, so there was no Thanos-side signal either.

The triggering queries were ad hoc (no committed dashboard contains an all-series
selector); Thanos has no query log enabled, so the exact query isn't recoverable.

## What changed

- Querier: `--store.limits.request-series=300000`, `--query.max-concurrent=8`.
- Store gateways and sidecars: `--store.limits.request-series=150000` — above the
  largest single metric (~95k), well below an all-series select (~640k).
- New alert `KubeContainerOOMKilledRepeatedly`: ≥2 restarts in 6h with last exit
  `OOMKilled`. Evaluated against live data it fires for exactly the three affected
  containers.
- Regression tests pin the flags and the alert.

## Action items

- [x] After merge: run a deliberately wide query through Thanos Query and confirm it
      is refused with no pod restarts. Done 2026-09-29 ~22:40 UTC: `count({__name__=~".+"})`
      was refused by both sidecars (`limit 150000 violated`); zero restarts afterwards.
      `count(apiserver_request_duration_seconds_bucket)` (87,504) still succeeds.

> **Caveat — truncated, not failed.** The Querier runs with partial response on (the
> default), so an over-limit query returns HTTP `success` with a *truncated* result
> (the test returned `150000`) plus a warning, rather than an error. Grafana shows the
> warning on the panel, but the number itself is wrong. Partial response stays on
> deliberately: turning it off would fail every query whenever one Prometheus replica
> is down, which defeats the HA pair. Treat any panel carrying a
> `limit … violated` warning as wrong, not just slow.
- [ ] Reduce CI-telemetry cardinality (histogram buckets / dimensions on `cicd_duration_seconds`). (issue #2606)
- [ ] Drop unused API-server/etcd histogram series at scrape (relabel), after checking no dashboard or rule reads them. (issue #2607)
- [ ] Scrape Thanos components' own metrics so the read path has its own signals. (issue #2608)
- [ ] Upgrade Thanos v0.39.2 → v0.42.4 (the chart's appVersion) as a separate change. (issue #2609)
