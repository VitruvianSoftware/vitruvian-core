# Scoping: Argo Rollouts pilot for buzz (progressive delivery)

**Date:** 2026-07-31
**Status:** Scoping — exploratory, not yet approved for implementation
**Branch:** `atlas/argo-rollouts-pilot-scoping`
**Requested by:** James Nguyen, via Beacon (2026-07-31 04:01 UTC, vitruvian-core-buzz channel)
**Reference app:** `buzz` (relay) — chosen because it already has working metrics
(`up{namespace="buzz"}`, post-#1340) and routes via Envoy Gateway/Gateway API HTTPRoute.

## 1. Context & motivation

PR #1340 (stale `REDIS_URL` fix) required a manual relay rollout, which surfaced a
pre-existing gap: the relay's `startupProbe` budget was too tight for MinIO transport
jitter, causing a ~21-minute 503 window until PR #1341 landed. James asked whether a
canary release process would have caught this without the outage — see thread root
`01017a6d955c0dd1e0e9ba394496b99d959fc38597c3801f00ba976440975678` in
`vitruvian-core-buzz`. The honest answer: **a canary would not have prevented this
specific outage** (the 503s came from old pods flapping on the stale Redis URL while the
fix rolled out slowly, not from the new pod's crash-loop — non-ready pods never take
traffic). What canary infrastructure **would** buy going forward is a small, automated
blast radius and gating for the *next* startup-probe-class regression, which matters
more now that this cluster hosts increasingly critical apps.

This doc scopes what adopting Argo Rollouts for buzz specifically would take, per
Beacon's five-point ask. It is investigation only — no code changes.

## 2. Current state (as of this repo, verified by direct file reads)

### 2.1 Buzz is not a local Deployment template — it's an external OCI Helm chart

`gitops/argocd/applications/buzz.yaml` is a **multi-source** ArgoCD `Application`:

- **Source 1** (lines 27-32): OCI chart `ghcr.io/block/buzz/charts`, chart `buzz`,
  `targetRevision: 0.1.7` — block/buzz's own published chart. This repo does not vendor
  or fork its templates; all customization is the inline `helm.values:` block
  (lines 33-181).
- **Source 2** (lines 173-179): this repo's own `gitops/argocd/platform/buzz/` path
  (plain manifests: CNPG `Cluster`/`Pooler`, Valkey, DNSEndpoint) — unrelated to the
  relay Deployment itself.

Key current values: `replicaCount: 3` (line 41), `image.tag: "main"` (line 34),
`startupProbe.failureThreshold: 150` (line 91, ~300s budget post-#1341),
`topologySpreadConstraints` (lines 92-99). No explicit `resources:` override (falls
back to chart defaults, not inspectable from this repo).

**This is the central constraint on the whole pilot.** The relay's Deployment is
rendered by an upstream chart we don't control. Converting it to an
`argoproj.io/Rollout` has two real options, not one:

- **(a) Upstream support** — block/buzz's chart would need to expose a
  `controller.kind: rollout` (or similar) toggle that renders a `Rollout` instead of a
  `Deployment`, the way many charts added Argo Rollouts support.
- **(b) Fork the workload out of the chart** — stop letting the chart render the
  relay's Deployment, and own a local `Rollout` manifest (under
  `gitops/argocd/platform/buzz/`) that reads the same values (image tag, env, probes)
  this repo already sets. This trades chart convenience for control, and duplicates
  logic the chart currently owns (env wiring, service, etc. — need to check how much).

**Resolved — no upstream support exists.** Pulled the chart directly
(`helm pull oci://ghcr.io/block/buzz/charts/buzz --version 0.1.7 --untar`) and inspected
every template. `templates/deployment.yaml` hardcodes `kind: Deployment` with no
conditional toggle — no `controller.kind`, no `strategy.canary`-style value anywhere in
`values.yaml`/`values.schema.json`, and no `argoproj.io`/Argo Rollouts dependency in
`Chart.yaml`. A repo-wide grep for `rollout|argoproj|canary` across every template in
the chart (including the `postgres`/`redis` subcharts) turns up exactly one hit —
`kubectl -n {{ .Release.Namespace }} rollout status deployment/...` in `NOTES.txt`,
which is the generic `kubectl rollout status` command, unrelated to Argo Rollouts. So
**option (a) is closed**: this is option (b) only — forking the Deployment/HTTPRoute
rendering out of the chart into a locally-owned `Rollout` manifest, or no canary for
buzz specifically. This also settles §4's first open question below.

### 2.2 ArgoCD app-of-apps onboarding pattern

Three root Applications bootstrap everything: `root-applications.yaml` (→
`gitops/argocd/applications/`, leaf apps like buzz), `root-platform.yaml` (→
`gitops/argocd/platform/*/applicationset.yaml`), `root-projects.yaml` (→
`gitops/argocd/projects/`, AppProjects).

Platform services are onboarded as **ApplicationSets**
(`generators: [clusters: {}]`, `goTemplate: true`), each with `project: platform-project`,
its own namespace, `syncPolicy.automated.{prune,selfHeal}: true`,
`syncOptions: [CreateNamespace=true]`. Reference examples already in the repo:
`platform/cert-manager/applicationset.yaml` (CRD/webhook-bearing, `sync-wave: "-3"` so
it lands before consumers), `platform/external-dns/applicationset.yaml`,
`platform/envoy-gateway/applicationset.yaml` (OCI chart, `sync-wave: "-1"`).

Onboarding the Argo Rollouts **controller** is a same-shape addition:
`gitops/argocd/platform/argo-rollouts/applicationset.yaml`, chart
`https://argoproj.github.io/argo-helm` → `argo-rollouts`, namespace `argo-rollouts`,
negative `sync-wave` (it must exist before buzz's `Rollout` can be admitted), and
`prometheus.io/scrape`-style pod annotations to match this repo's established
"no Prometheus Operator" scrape convention (see §2.4). Controller footprint per
upstream chart defaults: single-replica Deployment, ~100m CPU / 128Mi memory — in line
with cert-manager/external-dns already running here.

### 2.3 Envoy Gateway / HTTPRoute for buzz

No standalone HTTPRoute manifest — it's chart-rendered via the `httproute:` values
block in `gitops/argocd/applications/buzz.yaml` lines 100-127:

```yaml
httproute:
  enabled: true
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: platform
      namespace: envoy-gateway-system
  rules:
    - matches: [{path: {type: PathPrefix, value: /pair}}]
      backendRefs: [{group: "", kind: Service, name: buzz-pairing, port: 5000, weight: 1}]
    - matches: [{path: {type: PathPrefix, value: /}}]
      backendRefs: [{group: "", kind: Service, name: buzz, port: 3000, weight: 1}]
```

No traffic splitting today (single `backendRef`, `weight: 1` per rule). This confirms
Beacon's read: Argo Rollouts' native **Gateway API traffic-router plugin** can drive
weighted shifting against this exact HTTPRoute/Gateway pair — no Istio, no new mesh.
But note: if the relay's Deployment stays chart-owned (option 2.1a doesn't materialize),
the HTTPRoute is *also* chart-owned, and the Rollout controller needs write access to a
resource the chart currently renders — another point favoring resolving 2.1 first.

### 2.4 Prometheus / metrics gap

Confirmed: this cluster runs the community `prometheus-community/prometheus` chart
(`gitops/argocd/platform/prometheus/applicationset.yaml`, chart `prometheus-22.6.7`),
**not** the Prometheus Operator — so `ServiceMonitor` CRs are inert here, as already
documented inline at `gitops/argocd/applications/buzz.yaml` lines 149-158. Buzz's
`up{namespace="buzz"}` scrape works via the chart's default
`kubernetes-service-endpoints` job honoring `prometheus.io/scrape`/`port`/`path`
Service annotations (`"true"` / `"9102"` / `"/metrics"`).

**Real gap for canary analysis**: no buzz-specific HTTP request-rate/error-rate/status-
code metric or Grafana dashboard exists anywhere in this repo
(`gitops/argocd/platform/grafana-dashboards/` covers cert-manager, CNPG, external-dns,
MinIO, traefik, node-exporter — nothing for buzz), and buzz's source isn't vendored
here, so what block/buzz's relay actually exports on `:9102/metrics` is unknown from
this repo alone. Before writing an `AnalysisTemplate` with an error-rate threshold, we
need to either (a) confirm buzz exports an HTTP-level metric (e.g. a `*_requests_total`
counter with a status label) on that port, or (b) fall back to weaker k8s-level
signals (`kube_pod_container_status_restarts_total`, readiness flips) which are a much
blunter canary gate. This should be checked against the actual `/metrics` output on a
running pod before the pilot's AnalysisTemplate task is scoped further.

### 2.5 AppProject / CRD whitelist conventions

Per-app AppProjects (`gitops/argocd/projects/buzz-project.yaml`, pattern from the
`whoami-project`, issue #459) use `namespaceResourceWhitelist` to enumerate exact
`group/kind` pairs the app's chart+manifests are allowed to manage.
PR #1338 is the precedent: it added

```yaml
    - group: postgresql.cnpg.io
      kind: Pooler
```

after CNPG's `Cluster` entry — needed because ArgoCD validates every resource in a sync
before applying any; one unlisted kind blocks the whole sync (this bit PR #1336 when the
Pooler resource was added without its whitelist entry).

For the pilot, buzz's `Rollout`/`AnalysisTemplate`/`AnalysisRun` (and possibly
`Experiment`) kinds under `group: argoproj.io` need the same treatment in
`buzz-project.yaml`. Separately, the Rollouts controller's own CRDs need a
`clusterResourceWhitelist` entry in `platform-project.yaml`, which is a curated,
non-wildcard list per issue #459 — not a rubber stamp, so this needs explicit review
when the controller Application PR goes up.

### 2.6 Prior art in this repo

None. Searched `docs/`, `docs/archive/planning/`, `docs/superpowers/` for "argo
rollouts", "canary", "progressive delivery" — the only hits use "canary" in the
release-train/Chrome-Canary sense (tabula release channels, monorepo pipeline
authority), unrelated to Kubernetes canary deployments. This is a clean-slate pilot.

## 3. Effort estimate and sequencing

Rough sizing, now that §2.1 is resolved to option (b) (owning the Rollout manifest
locally — confirmed, not assumed: block/buzz's chart has no Rollouts support to fork
into):

1. **Scope the local fork** — confirm how much of the chart's Deployment/Service/
   HTTPRoute rendering needs reproducing locally to own a `Rollout` instead (env wiring,
   probes, topologySpreadConstraints, the `httproute:` values block). *Half a day, blocks
   step 3.*
2. **Controller onboarding** — done. PR #1343 (merged, `2026-07-31T05:08:24Z`) installed
   the `argo-rollouts` ApplicationSet — controller + all 5 CRDs (`Rollout`,
   `AnalysisTemplate`, `ClusterAnalysisTemplate`, `AnalysisRun`, `Experiment`), verified
   Synced/Healthy live on-cluster, zero consumers yet, zero effect on any existing
   Deployment.
3. **Convert buzz's relay to a `Rollout`** — new local manifest, `buzz-project.yaml`
   namespaceResourceWhitelist entries, remove/disable the chart's Deployment+HTTPRoute
   rendering if still sourced from Source 1, wire the Gateway API traffic-router plugin
   against the existing `platform` Gateway. *Moderate — this is the real work, and
   depends on how cleanly buzz's chart values let us disable just the Deployment.*
4. **Confirm/expose an analyzable metric** — check buzz's actual `/metrics` output;
   if no HTTP-level metric exists, this either needs an upstream buzz change (out of
   scope for infra) or the pilot ships with a weaker restart/readiness-based
   `AnalysisTemplate` as a first cut. *Unknown size until checked — flag as a risk.*
5. **Write the `AnalysisTemplate`(s)** — Prometheus queries + thresholds gating
   promotion, using whatever metric 4 confirms. *Small once 4 is resolved.*
6. **Dry-run and validate** — force a canary deploy (e.g. a no-op image bump) and watch
   the analysis run/promote/rollback in practice before calling the pilot done.

**Net: moderate one-time setup, most of the uncertainty is in steps 1 and 4, not the
controller or Gateway API wiring** (which Beacon's read confirms is straightforward —
already-live infra, no new networking layer). Recommend resolving step 1 and 4 as small
spikes before committing to a full implementation plan, since either could change the
shape of steps 3 and 5 materially.

## 4. Open questions for James / Beacon before implementation

- **Resolved:** block/buzz's chart has no Rollout/canary support (confirmed by pulling
  and inspecting chart 0.1.7 — see §2.1). Forking the Deployment/HTTPRoute rendering
  out locally is therefore the only path to a buzz canary. Still need sign-off on that
  fork, since it loses upstream chart convenience going forward — every future
  `ghcr.io/block/buzz/charts` bump would need its Deployment/Service/HTTPRoute changes
  manually ported into the local fork instead of picked up automatically.
- Is a restart/readiness-based `AnalysisTemplate` (weaker signal) an acceptable first
  cut if buzz doesn't export HTTP-level metrics, or should this wait until buzz exposes
  one?
- Confirm buzz is still the right first pilot app given the chart-ownership wrinkle in
  §2.1 — an app with a locally-owned Deployment (no external OCI chart) would be a
  cleaner first Rollouts conversion, if one exists among the platform services.
