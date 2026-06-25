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

## Prerequisites

A Zitadel **machine (service) user** with permission to manage applications in
the target project (e.g. `Org Owner`, or a project-scoped manager role), and a
**JSON key** of type "Key" downloaded from that user. Keep the key out of git.

## Configure

The Zitadel provider reads its connection settings from `zitadel:*` config; the
application settings are under `zitadel-apps:*`:

```bash
cd infrastructure/pulumi/zitadel-apps   # or use the bazel wrappers below
pulumi stack select development --create

# Provider connection (machine-user JWT profile key).
pulumi config set zitadel:domain auth.ipv1337.dev
pulumi config set zitadel:jwtProfileFile /abs/path/to/zitadel-machine-key.json
# (alternatively, store the key inline as a secret:)
#   pulumi config set --secret zitadel:jwtProfileJson "$(cat key.json)"

# Application placement.
pulumi config set zitadel-apps:projectId <zitadel-project-id>
pulumi config set zitadel-apps:orgId     <zitadel-org-id>   # optional; defaults to the service user's org

# Redirect URIs (defaults to https://oauth-inspector.ipv1337.dev/ if unset).
pulumi config set --path zitadel-apps:redirectUris[0] https://oauth-inspector.ipv1337.dev/
```

Per-stack config (`Pulumi.<stack>.yaml`) is git-ignored — it holds the
environment-specific IDs and the credential path. Nothing secret is committed.

## Adopt the existing application (do this first)

The running app reads its `client_id` / `client_secret` from GCP Secret Manager
(`ZITADEL_APP_OAUTH_CLIENT_ID` / `_SECRET`). To keep those valid, **import** the
existing Zitadel application instead of creating a new client:

```bash
pulumi config set zitadel-apps:importId "<org_id>:<project_id>:<app_id>"
bazel run //infrastructure/pulumi/zitadel-apps:preview   # confirm it ADOPTS (not replaces)
bazel run //infrastructure/pulumi/zitadel-apps:up
```

`<app_id>` is the application's resource ID from the Zitadel console (Project →
Applications → the app). If you instead let the program create a **new** client
(leave `importId` unset), read the generated credentials back and update Secret
Manager:

```bash
pulumi stack output clientId
pulumi stack output clientSecret --show-secrets
# then update ZITADEL_APP_OAUTH_CLIENT_ID / _SECRET in GCP Secret Manager
```

## Apply

```bash
bazel run //infrastructure/pulumi/zitadel-apps:preview
bazel run //infrastructure/pulumi/zitadel-apps:up
```

> This stack is applied **deliberately by an operator** holding the Zitadel
> machine-user key; it is intentionally not wired into an automatic CI deploy.
> To change an allowed redirect URI, edit it here and re-apply rather than
> touching the Zitadel console.
