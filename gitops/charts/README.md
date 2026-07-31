# Forked third-party Helm charts

Chart source for a third-party Helm chart we've forked — taken over its
`Chart.yaml`/`templates/`/`values.yaml` and now maintain it divergently from
upstream, because upstream can't do something we need. (The case that prompted
this directory: buzz's Argo Rollouts pilot needs a canary strategy the upstream
`ghcr.io/block/buzz/charts` chart doesn't support — see PRs #1342/#1343 and the
`vitruvian-core-buzz` channel thread they came from.)

**Empty today.** No chart has been forked yet. This directory — and this
README — exist so the location is already settled and discoverable once one
is.

## Why here, not `gitops/argocd/platform/<name>/`

Chart source is a portable Helm artifact, independent of whichever GitOps
controller consumes it. [dev-local-vs-gke.md](../../docs/infrastructure/dev-local-vs-gke.md)
already anticipates ArgoCD *or* Config Sync (ACM) in production — and Config
Sync doesn't read ArgoCD's `Application`/`ApplicationSet`/`AppProject` CRDs at
all, it syncs plain manifest trees via `RootSync`/`RepoSync` + Kustomize. Nesting
a fork inside `gitops/argocd/` would tie it to a controller it has nothing to do
with, and break the "same manifests reconcile" promise across a future
controller swap.

## What does *not* go here

- **Consumed** charts (used as-is, customized only via `helm.values`) stay
  under `gitops/argocd/platform/<name>/applicationset.yaml`.
- **Owned static manifests** that were never chart-templated (CRs, dashboards,
  sealed secrets) go in a distinctly-named sibling — e.g.
  `gitops/argocd/platform/<name>-manifests/` — or a clearly-named
  subdirectory (e.g. `platform/envoy-gateway/gateway/`). Never flat-mixed with
  a consuming `applicationset.yaml`. See
  [application-development-principles.md §3.6](../../docs/engineering/application-development-principles.md).

## Layout, when a chart lands here

```
gitops/charts/<name>/
├── Chart.yaml     # header comment: forked from <repoURL>/<chart> @ <version>, on <date>, why
├── templates/
└── values.yaml
```

The consuming `Application`/`ApplicationSet` (still under
`gitops/argocd/platform/<name>/`, or its future Config Sync equivalent) points
its Helm source at this local path instead of the vendor's `repoURL`.

## Known gap

`tools/ci/gitops-validate.sh` only validates static YAML under
`gitops/argocd/**` via kubeconform today. A forked chart's `templates/*.yaml`
contain unrendered `{{ }}` Go-template syntax, which kubeconform can't parse —
this directory isn't covered by CI yet. Extend `gitops-validate.sh` (`helm
lint` + `helm template | kubeconform`, roughly what `ct lint` does) before the
first chart lands here.
