# Design: Prometheus HA via Thanos (Full Thanos + MinIO)

Status: **complete** · Owner: James · Started 2026-06-29 · Completed 2026-06-30

## Goal

Make the cluster's single `prometheus-server` highly available so a single node
loss (a sleeping/rebooting laptop) no longer creates a metrics outage, **and**
gain durable long-term metric storage. The current single replica is the last
metrics-path SPOF (Alertmanager went HA in #410; the rest of the platform
control plane in #409/#410/#412).

A plain replica bump is **not** correct here: `prometheus-server` is also a
remote-write *receiver* (the OTel collector and Tempo's metrics-generator write
into it), so two replicas behind one round-robin Service would split-brain the
written data. The canonical fix is Thanos — independent replicas plus a
deduplicating query layer — with sidecar upload to object storage (MinIO) for
durable history.

This is the **Full Thanos + MinIO** shape (vs. a dedup-only variant): we also
get long-term retention and downsampling, not just availability.

## Current state

| Component | Where | Today |
|---|---|---|
| Prometheus | `gitops/argocd/platform/prometheus/applicationset.yaml` | chart `prometheus` 22.6.7, **Deployment**, `replicaCount: 1`, 25Gi local-path PVC, `--web.enable-remote-write-receiver`, no external labels |
| OTel collector | `gitops/argocd/platform/opentelemetry-collector/applicationset.yaml` | `prometheusremotewrite` → `http://prometheus-server.monitoring.svc.cluster.local:80/api/v1/write` |
| Tempo | `gitops/argocd/platform/tempo/applicationset.yaml` | `metricsGenerator.remoteWriteUrl` → same prometheus-server URL |
| Grafana | `gitops/argocd/platform/grafana/applicationset.yaml` | datasources `Prometheus-Data` (default, uid `Prometheus-Data`) + `Prometheus-Fallback-1` (uid `Prometheus`) → same prometheus-server URL |
| MinIO | `gitops/argocd/platform/minio-amd64/applicationset.yaml` | buckets: tempo, grafana-db-backups, cnpg-cluster-backups, zitadel-db-backups |

The appset comment records the deliberate single-replica choice and that the
local TSDB is treated as disposable (re-scraped after a node loss). Thanos
changes that: scraped data stays disposable per-replica, but uploaded blocks in
MinIO become the durable copy.

## Target architecture

```
 scrapers (kube SD, node-exporter, ...)          remote-write writers
        |  (identical scrape config)             (OTel collector, Tempo MG)
        v                                                 |  mirror to BOTH
 +---------------------+   +---------------------+         |
 | prometheus-server-0 |   | prometheus-server-1 |<--------+
 |  replica="...-0"    |   |  replica="...-1"    |
 |  + thanos sidecar   |   |  + thanos sidecar   |
 +----------+----------+   +----------+----------+
   StoreAPI |  upload blocks          | StoreAPI
   (recent) |        \               /  (recent)
            |         v             v
            |     +------------------------+
            |     |   MinIO  s3://thanos    |<--- Compactor (downsample/retention)
            |     +------------------------+
            |                 ^
            v                 | (historical blocks)
      +-----------------------+-----------+
      |        Thanos Querier             |  --query.replica-label=replica
      |  (dedups the two replicas)        |  fans out: sidecars + store gateway
      +-----------------+-----------------+
                        ^
                        |  (single deduped endpoint)
                     Grafana
```

- **Two Prometheus replicas**, each with a unique `replica` external label, run
  identical scrape configs. Dedup happens at the Querier, not at write time.
- **Thanos sidecar** per replica: serves the recent in-memory/local TSDB over the
  gRPC StoreAPI, and uploads completed TSDB blocks to `s3://thanos` in MinIO.
- **Thanos Store Gateway** serves historical blocks from MinIO.
- **Thanos Compactor** compacts/downsamples/applies retention on the MinIO blocks
  (run as a singleton — it must be the only writer to the bucket).
- **Thanos Querier** is the new read endpoint; it fans out to both sidecars
  (recent) and the Store Gateway (historical) and **deduplicates** by the
  `replica` label so the two replicas present as one consistent series.

### Per-replica label (the dedup key)

The plain prometheus chart renders one config for all pods, so the unique
per-replica label is injected at runtime:

- add `--enable-feature=expand-external-labels` to `server.extraFlags`
- set `server.global.external_labels` to `{ cluster: lab, replica: "$(POD_NAME)" }`
- inject `POD_NAME` via `server.env` from `fieldRef: metadata.name`

Prometheus expands `$(POD_NAME)` per pod, so `-0` and `-1` get distinct `replica`
values — exactly what `--query.replica-label=replica` dedups on. (This is the
documented HA pattern for the non-operator chart.)

## Prerequisites

- MinIO `thanos` bucket — **done in this Phase 0 PR** (minio-amd64 appset).
- A `thanos-objstore-creds` SealedSecret in `monitoring` (MinIO access/secret
  key + an `objstore.yml`), mirroring the existing `tempo-minio-creds` /
  `cnpg-cluster-minio-backup-creds` pattern under
  `gitops/argocd/platform/sealed-secrets-manifests/`. Created in Phase 1 via
  `kubeseal` against the live controller (sealed-secrets 2.19.0).
- Chart: Thanos components via the `bitnami/thanos` chart (query / storegateway /
  compactor), pinned in Phase 1. (Sidecar ships with the Prometheus pod, not a
  separate chart.)

## Phased plan

Blue-green: the live single Prometheus keeps serving until the Querier is
validated and Grafana is cut over. Nothing user-facing changes until Phase 2.

### Phase 0 — foundation (this PR, zero live impact)

- This design doc.
- Add the `thanos` bucket to the minio-amd64 appset (additive; empty bucket).

### Phase 1 — stand up the Thanos read path in parallel (no cutover)

- Seal `thanos-objstore-creds` (MinIO creds + `objstore.yml`) into
  sealed-secrets-manifests.
- Prometheus appset: `statefulSet.enabled: true`, `replicaCount: 2`, the
  per-replica `replica` external label (above), and the Thanos **sidecar**
  container with `--objstore.config` → MinIO. Keep the existing remote-write
  receiver flags and the 25Gi local-path PVC (now a volumeClaimTemplate, one per
  replica).
- New `thanos` appset(s): Querier (`--query.replica-label=replica`, stores =
  the sidecars' headless gRPC + the store gateway), Store Gateway, Compactor
  (singleton). All read `s3://thanos`.
- **Do not** touch Grafana or the remote-write writers yet.
- **Validate**: Querier UI shows both replicas as stores; a query that spans a
  single-pod restart returns gap-free, non-doubled series; blocks appear in
  `s3://thanos`; Store Gateway serves historical.

### Phase 2 — cutover

- Grafana: repoint `Prometheus-Data` (and the fallback) datasource URL →
  the Thanos Querier service. Keep the uids stable so dashboards don't break.
- OTel collector: write to **both** replica pods (two `prometheusremotewrite`
  exporters targeting the per-pod headless DNS, or a mirroring fan-out) so both
  replicas hold the remote-written series.
- Tempo: same — `metricsGenerator` remote_write to both replicas (list form,
  not the single `remoteWriteUrl`).
- **Validate**: dashboards render from the Querier; remote-written metrics
  (OTel/Tempo) are present on both replicas and dedup cleanly.

### Phase 3 — cleanup

- Remove any leftover single-server references/aliases.
- Tune Compactor retention + downsampling and Store Gateway resources to the
  homelab's actual volume.

## What this touches

| File / component | Phase | Change |
|---|---|---|
| `docs/design/prometheus-thanos-ha.md` | 0 | this doc |
| `minio-amd64/applicationset.yaml` | 0 | `thanos` bucket |
| `sealed-secrets-manifests/thanos-objstore-creds.sealedsecret.yaml` | 1 | new SealedSecret |
| `prometheus/applicationset.yaml` | 1 | StatefulSet, 2 replicas, replica label, sidecar |
| `thanos/applicationset.yaml` (new) | 1 | Querier + Store Gateway + Compactor |
| `grafana/applicationset.yaml` | 2 | datasource URL → Querier |
| `opentelemetry-collector/applicationset.yaml` | 2 | remote-write to both replicas |
| `tempo/applicationset.yaml` | 2 | metrics-generator remote-write to both replicas |

## Risks & rollback

- **Compactor must be a singleton** writing to `s3://thanos`. Two compactors (or
  a compactor racing another block writer) corrupts blocks. Run exactly one;
  never scale it.
- **PVC conversion**: moving Prometheus Deployment → StatefulSet changes the PVC
  from a static claim to a per-replica volumeClaimTemplate. Pin the 25Gi/local-
  path size so a chart re-render can't request a shrink (local-path can't
  shrink), matching the existing prometheus PVC retention note. The old TSDB is
  disposable (re-scraped), so the cutover does not need a data copy.
- **Remote-write split (pre-Phase-2)**: until Phase 2 mirrors writes, only the
  replica behind the round-robin Service receives OTel/Tempo metrics. Keeping the
  cutover atomic in Phase 2 avoids a window where written metrics are uneven.
- **Rollback**: each phase is independent. Phase 1 adds only parallel components
  (delete the thanos appset + revert the prometheus appset to revert). Phase 2 is
  the only user-visible change — revert the Grafana/OTel/Tempo URLs to the
  prometheus-server Service to fall back to the (still-running) replicas.

## Decisions / defaults

- **Full Thanos + MinIO** (durable long-term storage), not dedup-only — chosen
  2026-06-29.
- **Dedup label**: `replica`, expanded per-pod via Prometheus
  `expand-external-labels` from `${POD_NAME}` (shell-style `os.Expand`, NOT the
  k8s `$(POD_NAME)` form — see the completion note); cluster label `cluster: lab`.
- **Sidecar upload** (not a separate shipper); Compactor owns retention so the
  Prometheus `--storage.tsdb.retention.size=20GB` stays as the local cache bound.
- **Object store**: reuse MinIO (`minio-amd64`), new `thanos` bucket, creds via
  SealedSecret like every other MinIO consumer.

## Completion (2026-06-30)

All phases shipped and verified live:

| Phase | PR(s) | Notes |
|---|---|---|
| 0 — foundation | #413 | design doc + MinIO `thanos` bucket |
| 1a — Querier/Store/Compactor | #416 | objstore SealedSecret + thanos-community chart (NOT bitnami) |
| 1b — Prometheus → StatefulSet + sidecar | #418 | 2 replicas, per-replica `replica` label |
| 2 — cutover | #427 | Grafana → Querier; OTel + Tempo remote-write mirrored to both replicas |
| 3 — retention + Store Gateway HA | #429 | Compactor retention 15d/90d/365d; Store Gateway → 2 replicas |

Deviations / fixes found during rollout (all merged):

- **Dedup label syntax** (#421): the label was first set as `$(POD_NAME)` (k8s
  form), which Prometheus `expand-external-labels` (os.Expand) leaves literal —
  both replicas got identical labels, defeating dedup and risking a Compactor
  halt on overlapping blocks. Fixed to `${POD_NAME}`. Caught by live verification
  before any blocks uploaded.
- **ApplicationSet goTemplate** (#414): a literal backtick in a values-block
  comment closed the Go raw-string early and broke rendering of the prometheus
  appset (which also blocked the Alertmanager HA from #410). No backticks inside
  the `{{` ... `}}` values block.
- **repo-server OOM** (#422): rendering all the platform Helm charts (incl. the
  new thanos chart) exceeded the argocd repo-server's 256Mi limit under a
  concurrent re-render, stalling all reconciliation. Raised to 1Gi.
- **Store Gateway OutOfSync** (#417): ignoreDifferences on StatefulSet
  volumeClaimTemplates (k8s injects defaults the chart doesn't render).

Real-world validation: on 2026-06-30 the `fedora` node (a control-plane voter and
the original SPOF) napped. etcd held 2/3 quorum; Prometheus/Alertmanager/Store
Gateway kept a surviving replica; Thanos Querier dedup masked the gap; MinIO ran
3/4 then self-healed to 4/4 on rejoin. The HA design held under a real node loss.
