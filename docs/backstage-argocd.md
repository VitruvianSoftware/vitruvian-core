# ArgoCD in Backstage

Every catalog entity that ArgoCD deploys shows its live deployment state in the
portal: sync status and health on the Overview tab, and a **Deployments** tab
with sync history, the git revision actually running, and deep links into the
ArgoCD UI.

This closes the loop the catalog was missing. Backstage already showed what a
component *is* (owner, docs, repo), what its CI did (GitHub Actions), and what it
is *doing* (Kubernetes pods, Grafana dashboards). It could not show what was
actually **deployed** — the step between a merged commit and a running pod.

## How it is wired

The frontend plugin is [`@roadiehq/backstage-plugin-argo-cd`][plugin]. It talks
to ArgoCD through the Backstage **backend proxy**, never from the browser:

```
browser → backstage backend → /api/proxy/argocd/api → argocd-server.argocd.svc
```

The proxy endpoint is declared in two files that must stay identical:

| File | Role |
| --- | --- |
| `backstage/app-config.yaml` | local development |
| `gitops/argocd/platform/backstage/values.yaml` | **what actually runs** |

The container starts with `--config /app/app-config-from-configmap.yaml`, rendered
from the Helm values — so a change made only in `backstage/app-config.yaml` looks
correct in review and does nothing in production. `argocdProxyConfig.test.ts`
fails the build when the two drift.

Four properties of that endpoint are load-bearing, and each has a test:

- **`allowedMethods: ["GET"]`.** The proxy holds a bearer token. If it forwarded
  `POST`/`DELETE`, any portal user could sync or delete an Application through it
  regardless of that token's own RBAC.
- **Target is `http://argocd-server.argocd.svc.cluster.local`**, the in-cluster
  Service — the token's traffic never leaves the cluster and does not depend on
  ingress, DNS or TLS.
- **`allowedHeaders` excludes `Authorization`**, so a caller cannot substitute
  their own credential.
- **`argocd.baseUrl`** is used only to build click-through links to the UI; the
  data itself comes through the proxy.

## Credentials

The token is a **project role** on `platform-project`, declared in
`gitops/argocd/projects/platform.yaml`, and stored as the SealedSecret
`argocd-backstage-token` (key `ARGOCD_TOKEN`) in the `backstage` namespace.

### Why a project role and not a local account

An ArgoCD local account (`accounts.<name>: apiKey` + an RBAC binding) would be the
obvious choice, and it is what the existing `mcp` account uses. It is not
available here: those keys live in `argocd-cm`, which is **Helm-managed by the
Pulumi `dev-local` stack**, and no CI workflow applies that stack. A project role
is declarative in git and reaches the cluster the same way every other change
does.

Reusing the `mcp` account was rejected outright — it is bound to `role:admin`.

### Two behaviours that were verified, not assumed

Both were checked against the live server (v3.4.4) because the design fails
silently if either is wrong:

1. **The token survives `selfHeal`.** Minting writes the token id to *both*
   `.spec.roles[].jwtTokens` and `.status.jwtTokensByRole`. `app-of-projects`
   runs `selfHeal: true`, so the **spec copy is stripped** back to what git says
   (this file lists no tokens). Validation reads `.status`, which is not part of
   the desired state, so the token keeps working. Confirmed by stripping the spec
   copy and re-issuing a request: still `200`.
   **Do not "fix" this by committing `jwtTokens` into git.**

2. **The read scope is cluster-wide, and does not come from the role's policy.**
   `argocd-rbac-cm` sets `policy.default: role:readonly`, so any authenticated
   subject can already read every Application. The token therefore sees all
   Applications across **all** projects — which is what makes one token enough for
   a card that must also cover `buzz`, `storybook` and `whoami`, each in its own
   project. The explicit policy on the role is the floor that survives someone
   tightening `policy.default`; it is not what grants today's visibility.

Writes are denied. Syncing with this token returns:

```
403 permission denied: applications, sync, buzz-project/buzz,
    sub: proj:platform-project:backstage
```

### Minting and rotating

```bash
bazel run //tools/gitops:seal-argocd-backstage-token
```

Mints the token and seals it in one step — the credential is piped straight into
`kubeseal` and never passes through a clipboard, shell history or `argv`. Commit
the generated file and ArgoCD applies it; add `--apply` to apply immediately.

The `backstage` role must already exist server-side, so
`gitops/argocd/projects/platform.yaml` has to be merged and synced first. The
script says so explicitly rather than failing with a bare HTTP 404.

No expiry by default, matching `grafana-backstage-token`: an expiring token
breaks the cards months later with no failing gate to catch it. Pass
`--expires-in 8760h` to opt into rotation.

**The pod does not restart when the secret changes.** The deployment's
`checksum/app-config` annotation covers the ConfigMap, not the Secret, so a newly
applied or rotated token is not picked up by the running container — the cards
keep failing against the old value (or, on first install, against no value at
all) with nothing in the logs to explain it. Roll the pod after the SealedSecret
lands:

```bash
kubectl delete pod -n backstage -l app.kubernetes.io/name=backstage
```

Delete rather than `kubectl rollout restart`: the latter stamps
`kubectl.kubernetes.io/restartedAt` onto the pod template, which ArgoCD's
`selfHeal` then reverts — costing a second, pointless rollout. Deleting the pod
introduces no manifest drift; the ReplicaSet recreates it immediately.

`ARGOCD_TOKEN` is deliberately mounted with `optional: true`. A missing secret
must degrade the cards, not block startup — without it the pod sits in
`CreateContainerConfigError` and the **whole portal** is down, and the token is
necessarily absent in the window between this shipping and the secret landing.

## Adding the card to an entity

Annotate the entity. Any one of these makes the card and tab appear
(`isArgocdAvailable`):

```yaml
metadata:
  annotations:
    argocd/app-name: cert-manager        # one Application
    # or
    argocd/app-selector: app=cnpg        # every Application matching a label
```

Use `app-name` for a single Application and `app-selector` when one catalog
entity maps to several. Currently annotated:

| Entity | Annotation | Why |
| --- | --- | --- |
| `backstage` | `argocd/app-name: backstage` | `backstage-db` is labelled `app=backstage-db`, so a selector would fold an independently-synced Postgres cluster into this component's deploy history |
| `cert-manager` | `argocd/app-name: cert-manager` | one Application |
| `external-dns` | `argocd/app-name: external-dns` | one Application |
| `minio` | `argocd/app-name: minio-amd64` | the Application kept the `-amd64` suffix from pinning the StatefulSet to AMD64 nodes |
| `cloudnative-pg` | `argocd/app-selector: app=cnpg` | `cnpg-operator` and `cnpg-cluster` share that label, and "is CloudNativePG healthy" means both |

A typo such as `argocd/app_name` is **silently inert** — `isArgocdAvailable`
returns false, the card never renders, and nothing is logged. The annotation keys
are therefore checked by a test.

### What is deliberately not wired

- **`traefik`** carries no annotation. It is the k3s-bundled ingress in
  `kube-system`, not an ArgoCD Application, so a card could only ever show
  "not found".
- **No sync / rollback controls.** The plugin can render them, but the proxy is
  GET-only and the token cannot write. Deployment is driven from git through the
  merge queue; a sync button in a portal is a second, unreviewed path to
  production.
- **`buzz`, `storybook`, `whoami`** have ArgoCD Applications but no catalog
  entity yet. The token can already read them, so annotating costs nothing once
  the entities exist.

[plugin]: https://github.com/RoadieHQ/backstage-plugin-argo-cd
