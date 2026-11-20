# zitadel-apps

First-party **Zitadel OAuth applications**, managed as code against the
self-hosted Zitadel instance (`gitops/argocd/platform/zitadel`, public at
`https://auth.ipv1337.dev`).

The Zitadel **instance** is GitOps-managed (the ArgoCD `ApplicationSet`). The
OAuth **applications** it hosts for our own apps live *here* so their client
settings — most importantly the **redirect URIs** — are version-controlled
rather than hand-edited in the Zitadel console.

Currently manages:

- **OAuth User Inspector** hosted OIDC client. Its `redirect_uris` must exactly
  match the app's own origin (`https://oauth-inspector.ipv1337.dev/`, trailing
  slash included), or Zitadel rejects the authorize request with
  `invalid_request` / _"The requested redirect_uri is missing in the client
  configuration."_

## How it applies (pipeline-triggered)

Per principle §2.14 (the pipeline is the only trigger) and §2.15 (infra lands
before the app), this stack is applied **by CI as the "expand" step of the
`oauth-user-inspector-deploy` workflow** — it runs before the app revision so
the redirect URIs are registered before the hosted login needs them. The Bazel
wrappers (`bazel run //infrastructure/pulumi/platform/zitadel-apps:preview` / `:up`) are
for local **preview / break-glass only**, never the path to prod.

The apply job is **gated** on the `ZITADEL_APPS_AUTO_APPLY` repo/environment
variable so it cleanly no-ops until the one-time bootstrap below is done.

> **Before enabling `ZITADEL_APPS_AUTO_APPLY`:** the apply must reach the Zitadel
> management API over an **internal** path — Cloudflare's edge bot-protection
> intermittently blocks the provider on the public `auth.ipv1337.dev` (HTTP 1010).
> See [APPLYING-FROM-CI.md](APPLYING-FROM-CI.md) for the chosen approach (tailnet
> internal routing, option **a**) and the future alternatives (b, c).

## Deletes and replaces need a reviewed approval

Every apply runs through the plan guard (`//tools/pulumi:guarded-up`). If the
plan deletes or replaces anything, the apply stops before changing a thing,
unless a reviewed commit names that exact resource:

```
Allow-destroy: urn:pulumi:production::zitadel-apps::zitadel:index/applicationOidc:ApplicationOidc::oauth-user-inspector
```

This matters most here: on this provider a replace of an OIDC app **deletes the
live client**, and hosted login breaks until it is recreated and its new
credentials synced (2026-06-26).

- **development** applies on a push to `main`, and reads approvals from the
  commits in that push.
- **nonproduction** and **production** apply on an `oauth-user-inspector`
  release, and read approvals from every commit since that product's previous
  release (`tools/pulumi/release_approvals.sh`). The URN names the stack, so a
  change you mean to apply in all three environments needs three lines, one per
  URN.
- A manual dispatch never applies a delete or replace.
- If the release range can't be read in full, nothing is approved and the
  delete is refused; a safe plan still applies. To recover from a refused
  release, merge a new commit with the `Allow-destroy` line and cut a release.

## One-time bootstrap (seed, then it's automated)

1. **Machine user + key.** In the Zitadel console create a service (machine)
   user with permission to manage applications in the target project (e.g.
   `Org Owner`), add a JSON **Key**, and store its contents as the
   **`ZITADEL_MACHINE_KEY_JSON`** GitHub Actions secret on the
   `oauth-user-inspector-development` environment. (This is the one root
   credential seeded out-of-band; the pipeline uses it from then on.)
2. **Org / project IDs.** Fill `zitadel-apps:projectId` (and optionally `orgId`)
   in `Pulumi.development.yaml` (read from the Zitadel console: Project → your
   project). The stack **creates and owns** the OIDC client.
3. **Enable.** Set the `ZITADEL_APPS_AUTO_APPLY` variable to `true`.

From then on, every change to `infrastructure/pulumi/platform/zitadel-apps/**` (or an
oauth-user-inspector deploy) re-applies the stack automatically; redirect-URI
changes are a code edit + merge, never a console click.

> **Do NOT adopt an existing client via `pulumi.Import` / `importId`.** The
> pulumiverse/zitadel provider marks `appType`/`version`/`accessTokenType`/… as
> force-new and its import does not populate them, so an import plans a
> *replacement* — which for this resource is "import replacement + delete
> original" against the **same** app, i.e. it **deletes the live client**. (This
> is exactly what broke hosted login on 2026-06-26: app `378961731390539356` was
> replaced+deleted → `Errors.App.NotFound`.) There is no non-destructive adopt.
>
> **When the stack mints a new client** (first create, or any recreate), read
> `pulumi stack output clientId` / `clientSecret --show-secrets` and update
> `ZITADEL_APP_OAUTH_CLIENT_ID` / `_SECRET` in GCP Secret Manager to match (the
> app reads them per-request, so no redeploy is needed).

## Break-glass / local preview

```bash
# Preview only — requires the machine-user key locally; not the path to prod.
ZITADEL_MACHINE_KEY_JSON="$(cat key.json)"
# (set provider creds for a local run)
#   pulumi config set --secret zitadel:jwtProfileJson "$ZITADEL_MACHINE_KEY_JSON"
bazel run //infrastructure/pulumi/platform/zitadel-apps:preview
```

## Interface
- Internal implementation components

## Invariants
- [main.go:80]: `projectID := cfg.Require("projectId")`

## Side Effects
- [main.go:145]: `// devMode allows the http://localhost dev redirect; every env keeps the`

## Verification
- Run: `bazel test //infrastructure/pulumi/platform/zitadel-apps/...`
