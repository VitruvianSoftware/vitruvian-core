# GitOps (ArgoCD)

App-of-Apps GitOps for the homelab cluster. ArgoCD is installed by Pulumi
(`infrastructure/pulumi/platform/dev-local`, `argocd_enabled: true`); from there it syncs
this directory.

## Layout

- `argocd/root-*.yaml` — app-of-apps roots. Point ArgoCD at the `projects/`,
  `platform/`, and `applications/` dirs (recurse) in this monorepo.
- `argocd/projects/` — `AppProject` CRDs (guardrails per app group).
- `argocd/platform/` — platform Applications (cnpg, etc.) — placeholder for now.
- `argocd/applications/` — one ArgoCD `Application` per first-party app, each
  deploying that app's Helm chart from GHCR by version.
- `charts/` — source for **forked** third-party Helm charts (chart source we've
  taken over from a vendor, not consumed as-is). Controller-agnostic by design
  — see [`charts/README.md`](charts/README.md).

## Flow

1. App Helm charts live next to each app: `<app>/deploy/chart` (e.g.
   `tabula/deploy/chart`).
2. `.github/workflows/charts-publish.yml` packages changed charts and pushes them
   as OCI artifacts to `oci://ghcr.io/vitruviansoftware/charts/<name>`.
3. The `Application` in `argocd/applications/<app>.yaml` references that chart by
   version; ArgoCD pulls and syncs it.

## Bootstrap (once ArgoCD is running)

```sh
kubectl apply -f gitops/argocd/root-projects.yaml
kubectl apply -f gitops/argocd/root-applications.yaml
# kubectl apply -f gitops/argocd/root-platform.yaml   # when platform/ is populated
```

Container **images** continue to publish to GCP Artifact Registry (see
`tabula/api/BUILD`); only the **charts** live in GHCR.
