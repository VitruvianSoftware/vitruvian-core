# dev-local GitOps (ArgoCD)

The dev-local platform is a **closed GitOps loop**: everything in the cluster
reconciles from this directory via ArgoCD. **git is the single source of truth.**
You change the cluster by changing git — never by hand.

## How it reconciles (the app-of-apps roots)

Three root `Application`s are applied once at bootstrap; everything else flows from
git through them. After bootstrap you should never `kubectl apply` an AppSet or
`argocd app create` by hand again.

| Root | File | Watches | Manages |
| --- | --- | --- | --- |
| `app-of-projects` | `root-projects.yaml` | `projects/` | the `AppProject`s |
| `app-of-platform` | `root-platform.yaml` | `platform/*/applicationset*.yaml` | the platform **ApplicationSets** (cert-manager, cnpg, longhorn, prometheus, …) |
| `app-of-applications` | `root-applications.yaml` | `applications/` | the application-layer `Application`s (incl. the shared-manifest git-source apps: platform-config, grafana-dashboards, sealed-secrets-manifests, platform-crds) |

Each ApplicationSet then generates a child `Application` with
`automated{prune,selfHeal}`, which continuously deploys its Helm chart / manifests
from git. So a change flows: **git → (root) → ApplicationSet → Application → cluster**,
fully automatically.

> **Why all three roots must stay deployed:** if a root is missing, the objects it
> would manage have to be applied by hand — which is exactly the gap that caused
> the 2026-06-21 confusion (the `app-of-platform` root was authored but never
> deployed, so AppSet changes silently required `bazel run …:apply`). See
> `docs/operations/incidents/2026-06-21-fedora-freeze-cluster-cascade.md`.

## Making a change

1. Edit the AppSet / manifest in this directory.
2. Open a PR; on merge to `main`, the relevant root's `selfHeal` reconciles it —
   **no manual apply.**
3. Verify in ArgoCD (`argocd app get <app> --grpc-web`) or `bazel run //tools/gitops:get`.

## Rules (do not break without explicit approval)

- **No out-of-band cluster changes.** No `kubectl apply/edit/scale/patch`, no
  `argocd app set/sync/create`, no UI click-ops to *change desired state*. `selfHeal`
  will revert them anyway, and they bypass review/audit.
- **Read-only is fine:** `kubectl get/describe/logs`, `argocd app get/diff`.
- **Break-glass (incidents) is the only exception**, and it needs **explicit,
  per-instance approval from the maintainer** — then immediately fold the fix back
  into git so the loop owns it. ("GitOps violations need explicit approval; rare
  situations only.")
- **All allowed cluster ops go through the bazel wrappers** (`//tools/gitops`,
  `//tools/pulumi`) — no ad-hoc CLIs.
- **Parking a component:** rename its manifest to `*.disabled` (e.g.
  `applicationset.yaml.disabled`). The roots skip `.disabled` files, so parked
  components (crossplane, datadog, istio, ingress-nginx, telepresence, tabula
  until its chart is published) stay out of the cluster while remaining in git.

## Bootstrap (the one manual layer, by design)

ArgoCD itself is bootstrapped by Pulumi (`infrastructure/pulumi/platform/dev-local`, the only
remaining Pulumi module). The three roots above are applied once at bootstrap. That
single bootstrap step is the *only* sanctioned manual apply — everything downstream
is GitOps.
