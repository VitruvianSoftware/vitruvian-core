# Platform (ArgoCD-managed)

Cluster system components, migrated from `infrastructure/pulumi/dev-local` to
ArgoCD over time. Pulumi stays the **bootstrap for ArgoCD itself**; everything
here is owned by ArgoCD via the `app-of-platform` root (`../root-platform.yaml`).

Each component mirrors the source pattern: an `ApplicationSet` (clusters
generator) → an upstream Helm chart, in the `platform-project`.

## Components

- `cnpg/` — CloudNativePG **operator** (the cnpg *clusters* migrate with their
  apps, carrying our homelab values — see the storageClass note in the PR).
- `crossplane/` — mirrored from source; optional on the homelab.
- `datadog/`, `backstage/` — stubs (not enabled), mirroring the source.

## Migration (Pulumi → ArgoCD)

Cut over **component-by-component** to avoid dual-management: a component lands
here only once its Pulumi `Deploy*` is disabled in `dev-local`. Sync-wave
annotations order operators (e.g. cnpg) before workloads.
