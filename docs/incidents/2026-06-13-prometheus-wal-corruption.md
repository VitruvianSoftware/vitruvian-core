# Incident: Prometheus WAL corruption — no metrics persisted (2026-06-13 → 2026-06-21)

|              |                                                                                  |
| ------------ | -------------------------------------------------------------------------------- |
| **Status**   | ✅ Resolved — monitoring for recurrence                                           |
| **Severity** | SEV-2 — full observability outage (all Grafana dashboards empty); homelab, no external user impact |
| **Impact**   | ~8 days with **no metrics stored** (2026-06-13 → 2026-06-21)                      |
| **Detected** | 2026-06-21                                                                        |
| **Resolved** | 2026-06-21 ~03:01 UTC                                                             |
| **Components** | `monitoring/prometheus-server` (Deployment + PVC), Longhorn, ArgoCD app/appset `prometheus` |
| **Cluster**  | dev-local (k3s)                                                                   |

> Living document — keep the **Action items** section below up to date as follow-ups land.

## Summary

Prometheus stopped persisting metrics on 2026-06-13. Its TSDB write-ahead-log segment
`/data/wal/00000010` became unreadable **and** unwritable at the **ext4 filesystem level**
(`input/output error`), while the underlying Longhorn **block** volume reported healthy — so
Longhorn's self-healing never triggered. Every scrape and remote-write failed
(`write to WAL: log samples: write /data/wal/00000010: input/output error`), so no samples
were stored and every Grafana dashboard was empty. The instance held no valuable history, so
we recreated the volume from scratch: suspended ArgoCD self-heal, drained the pod, deleted the
corrupt PVC + Longhorn volume, and let ArgoCD recreate a fresh empty PVC. Prometheus came back
clean and is scraping + persisting normally.

## Impact

- No metrics stored for ~8 days (2026-06-13 → 2026-06-21).
- All Grafana dashboards empty across that window.
- No metric-based alerting (the data — and the alerting that would have caught it — depend on Prometheus, which was the thing that was down).
- No data recovery needed or possible: the WAL was corrupt and the instance had no valuable history.

## Timeline (UTC)

- **2026-06-13** — ext4 corruption of the Prometheus WAL begins; metrics stop persisting. Coincides with the known 2026-06-13 cluster incident (Longhorn cross-node I/O unreliability under load on sleeping laptop nodes).
- **2026-06-21 ~02:45** — Diagnosis confirmed still current: logs flooding with `write /data/wal/00000010: input/output error`; `dd if=/data/wal/00000010 of=/dev/null` also EIO; `/data` mounted `rw`, 2% full; Longhorn volume `pvc-a663f343-…` `attached` / `robustness: healthy` with all replicas up.
- **~02:49** — Remediation begins; a tooling slip (see *What went wrong*) fired the PVC delete early — PVC went `Terminating`, held by the running pod's `pvc-protection` finalizer. No data lost.
- **~02:55** — Suspended ArgoCD self-heal at the **ApplicationSet** level (app-level suspend was reverted in real time by the AppSet controller); scaled `deploy/prometheus-server` to 0; pod released the PVC, which then deleted along with its Longhorn volume `pvc-a663f343-…`.
- **~03:00** — Restored the AppSet; ArgoCD recreated a fresh empty PVC `pvc-1f54d626-…` (new Longhorn volume) and scaled the deployment back up.
- **~03:01** — New pod `prometheus-server-…-ldnkt` 2/2 Running; WAL writing; metrics flowing. **Resolved.**

## Root cause

ext4 **filesystem** corruption on the prometheus-server PVC (Longhorn-backed, 25 Gi). A WAL
segment was unreadable/unwritable, but the corruption lived at the filesystem layer — which
Longhorn (operating at the **block** layer) cannot see or repair. Longhorn reported the volume
`attached` / `healthy` throughout, so nothing auto-recovered. Prometheus cannot self-heal a
corrupt WAL segment, so it failed every sample write indefinitely. The corruption timing lines
up with the 2026-06-13 cluster incident (Longhorn I/O under load + sleeping nodes).

## Detection gap

Undetected for ~8 days because:

- The pod stayed `Running` — it never crashed, it just logged write errors.
- Longhorn reported the volume healthy.
- There was no independent alert for "Prometheus is not ingesting samples" — and any alert that
  *would* catch it depends on Prometheus, which was the component that was down.

## Resolution

Recreated the volume fresh (no history to preserve), all read-only diagnostics via `kubectl`
and all argo operations via the argocd CLI:

1. **Suspend self-heal at the AppSet level.** App-level `argocd app set prometheus --sync-policy none`
   does **not** hold — the (event-driven, no `ignoreApplicationDifferences`) ApplicationSet
   controller reverts it in real time. Instead remove `automated` from the AppSet template:
   `kubectl -n argocd patch applicationset prometheus --type merge -p '{"spec":{"template":{"spec":{"syncPolicy":{"automated":null}}}}}'`
   (There is no `app-of-platform` deployed in this cluster, so nothing reverts the AppSet patch.)
2. **Scale down:** `kubectl -n monitoring scale deploy/prometheus-server --replicas=0` → pod
   terminates and releases the PVC.
3. **Corrupt PVC + Longhorn volume delete** (`prometheus-server` / `pvc-a663f343-…`).
4. **Restore + recreate:** re-add `automated` to the AppSet template → ArgoCD self-heal recreates
   a fresh empty PVC (`pvc-1f54d626-…`) and scales the pod back up.

## What went wrong during remediation (and how we recovered)

- **Suppressed-stderr + a missing tool target masked failures.** The first attempt routed
  mutations through `bazel run //tools/gitops:patch`, but that target **did not exist in the
  working checkout** (the working dir was on a stale branch predating the `:patch` tool that had
  been merged to `main`). The suspend + scale patches errored to suppressed stderr (silent
  no-ops), but the **PVC-delete step — an existing target — ran**, leaving the PVC `Terminating`
  out of order. No data lost (deletion was the intended end state), but it left a half-modified
  state.
  **Lessons:** don't `2>/dev/null` cluster *mutations*; verify each step succeeded before the
  next; confirm tool targets exist in the *current* checkout (or run from `main`/a fresh
  worktree).
- **App-level sync suspend doesn't hold for AppSet-generated apps.** Suspend at the AppSet
  template level (above) — folded into the runbook appendix.

## Verification (2026-06-21)

| Check | Result |
| --- | --- |
| New pod | `prometheus-server-…-ldnkt` 2/2 Running, 0 restarts |
| WAL EIO errors in logs | **0** (was continuous) |
| WAL advancing | `/data/wal/00000000` current timestamp, ~8 MB and growing |
| Live series | `count(up)` = **88**; `count(up == 1)` 14 → 46 → 64, persisting across a range query |
| Dashboard data | node-exporter metrics present from all 10 nodes |
| ArgoCD | app `prometheus` Synced / Healthy |
| Other monitoring storage | alertmanager 0 IO errors, grafana-db (CNPG) 0 IO errors, all Longhorn volumes healthy |

## Action items (living)

- [ ] **Confirm root cause** — `dmesg -T | grep -iE 'ext4|I/O error|longhorn'` on the nodes that
  held replicas (**fedora, james-mbp32, james-mbp16**) to pin the 2026-06-13 ext4 event.
- [ ] **Recurrence decision** — the fresh PVC is back on Longhorn (same storage class that
  corrupted). Decide: keep on Longhorn, move Prometheus to `local-path` (as CNPG was moved after
  the same incident), or shorten retention.
- [ ] **Close the detection gap** — add an independent "Prometheus not ingesting" alert
  (dead-man's-switch / blackbox / `absent()`-style check from a secondary signal) so a multi-day
  silent outage can't recur.
- [ ] **Periodic fsck consideration** — evaluate whether Longhorn volumes backing TSDBs should
  get a scheduled `e2fsck` or filesystem-level health check (block-level health misses ext4
  corruption).

## Appendix — Prometheus volume-recreate runbook (corrected)

Prereqs: `export KUBECONFIG=$HOME/.kube/cluster.yaml`; argocd CLI logged in (`--grpc-web`).

```bash
# 1. Confirm the problem
kubectl -n monitoring logs deploy/prometheus-server -c prometheus-server --tail=20   # expect WAL EIO

# 2. Suspend self-heal at the APPSET level (app-level set is reverted by the AppSet controller)
kubectl -n argocd patch applicationset prometheus --type merge \
  -p '{"spec":{"template":{"spec":{"syncPolicy":{"automated":null}}}}}'
kubectl -n argocd get application prometheus -o jsonpath='{.spec.syncPolicy.automated}'  # must be empty

# 3. Drain + delete the corrupt volume
kubectl -n monitoring scale deploy/prometheus-server --replicas=0      # wait for 0 pods
kubectl -n monitoring delete pvc prometheus-server                     # Longhorn volume reclaimed (Delete policy)

# 4. Restore self-heal -> ArgoCD recreates a fresh PVC + scales back up
kubectl -n argocd patch applicationset prometheus --type merge \
  -p '{"spec":{"template":{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}}}'
argocd app sync prometheus --grpc-web   # or let self-heal do it

# 5. Verify: pod 2/2 Running; no WAL EIO; count(up) > 0; dashboards populate
```
