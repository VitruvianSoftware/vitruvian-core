# Platform (ArgoCD-managed)

Cluster system components, migrated from `infrastructure/pulumi/dev-local` to
ArgoCD (Pulumi→ArgoCD cutover, tracked in issue #170). Pulumi stays the
**bootstrap** for ArgoCD itself; everything here is owned by ArgoCD via the
`app-of-platform` root (`../root-platform.yaml`).

Each component is an `ApplicationSet` (clusters generator) → an upstream Helm
chart, in the `platform-project`. Apply/diff/delete only via bazel:

```sh
bazel run //gitops/argocd/platform/<component>:apply
bazel run //tools/gitops:status
```

## Active (being cut over via adopt-then-release)

- `cert-manager/`, `external-secrets/` — adopt-then-release; their CRDs +
  ClusterIssuer/ClusterSecretStores stay Pulumi-owned (kept out of the AppSet).
- `opentelemetry-operator/`, `opentelemetry-collector/`, `tempo/` — the OTel
  stack; all three share Pulumi's `opentelemetry_enabled` flag, so they release
  together.
- `external-dns/` — see its own notes (Cloudflare-token ExternalSecret coupling).
- `cnpg/` — CloudNativePG operator.

## Parked / disabled (`*.yaml.disabled` — inert)

`datadog/`, `istio/`, `ingress-nginx/`, `telepresence/` are **OFF in Pulumi**, so
they aren't migrations — they're verified, ready-to-use ApplicationSets ported
for later. They're saved as `applicationset.yaml.disabled`: ArgoCD's directory
recurse only picks up `*.yaml`, so a `.disabled` file is **inert** (never synced).

**To enable one later:**
1. `git mv applicationset.yaml.disabled applicationset.yaml`
2. add a `BUILD` with `gitops_manifest(name = "<c>", manifests = ["applicationset.yaml"])`
3. commit — `app-of-platform` then manages it (or `bazel run //…/<c>:apply`).

Caveats baked into each parked file's header: **datadog** needs its `datadog`
Secret (ExternalSecret + store) to exist first; **istio** owns 12 CRDs (protect
from prune before real use); **ingress-nginx** must NOT be made the default
IngressClass (Traefik is). `crossplane/` is similarly optional.

## Excluded / deferred

Longhorn, MinIO (storage) stay in Pulumi. CNPG cluster, Prometheus, Grafana,
MongoDB (stateful) are deferred pending review.
