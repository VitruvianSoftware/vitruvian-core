# Operations

How OAuth User Inspector is built, deployed, and maintained. For how it's
*designed*, see [ARCHITECTURE.md](ARCHITECTURE.md).

This app is the reference tenant of the foundation's **OSS application stage**
(stage 5). It deploys to three environments, each in its own GCP project, from a
single image built once and promoted by digest. **Everything reaches production
through CI/CD** — there is no sanctioned local `pulumi up` for these stacks.

- [Environments & projects](#environments--projects)
- [The moving parts](#the-moving-parts)
- [Deploy pipeline](#deploy-pipeline)
- [Identity & keyless auth](#identity--keyless-auth)
- [Secrets](#secrets)
- [Custom domains](#custom-domains)
- [Zitadel hosted-login](#zitadel-hosted-login)
- [Runbooks](#runbooks)
- [Pointers](#pointers)

## Environments & projects

| Env | GCP project | Public URL | Gate |
| --- | --- | --- | --- |
| development | `prj-d-bu1-oss-floating-648a` | `oauth-inspector.dev.ipv1337.dev` | auto (on push to `main`) |
| nonproduction | `prj-n-bu1-oss-floating-630b` | `oauth-inspector.staging.ipv1337.dev` | reviewer-gated |
| production | `prj-p-bu1-oss-floating-16e0` | `oauth-inspector.ipv1337.dev` | reviewer-gated |
| build (shared) | `prj-c-bu1-infra-pipeline-4b48` | — | Artifact Registry + build SA only |

The three app projects are per-environment **`prj-{env}-bu1-oss-floating`**
projects shared by OSS apps; co-tenancy is why the app namespaces its Secret
Manager entries with `SECRET_PREFIX=OAUTH_USER_INSPECTOR_`. The `run.app` URL
still works in every env; the custom domain is an added mapping, not a
replacement.

## The moving parts

Three Pulumi stacks plus one platform stack own this app's infrastructure:

| Stack | Path | Scope | Applied by |
| --- | --- | --- | --- |
| **app** | `oauth-user-inspector/infra/app` | per-env | env's `oauth-user-inspector-deploy` SA |
| **identity** | `oauth-user-inspector/infra/identity` | per-env | `sa-terraform-proj` |
| **build** | `oauth-user-inspector/infra/build` | shared (prod-only) | `sa-terraform-proj` |
| **zitadel-apps** | `infrastructure/pulumi/platform/zitadel-apps` | per-env | env's deploy SA (over the tailnet) |

- **app** (`pulumi_oauth_user_inspector`, config namespace `oauth-user-inspector`)
  — the Cloud Run v2 service, built on the `pkg/cloud_run` library primitive.
  Sets the runtime env (`NODE_ENV`, `GOOGLE_CLOUD_PROJECT`, `SECRET_PREFIX`),
  binds `allUsers` as `run.invoker` (public demo — relies on the org's
  project-scoped domain-restricted-sharing override on the oss projects),
  implements build-once/promote-by-digest + blue-green traffic, and declares the
  [custom domain](#custom-domains). Consumes an immutable image digest via
  `OAUTH_USER_INSPECTOR_IMAGE_DIGEST`.
- **identity** (`pulumi_oauth_user_inspector_deploy_identity`) — the per-env
  `oauth-user-inspector-deploy` and `oauth-user-inspector-rt` service accounts,
  their project IAM, and the WIF binding to the shared foundation pool. The
  runtime SA's `secretmanager.secretAccessor` is **conditioned** to secrets
  whose name starts with `OAUTH_USER_INSPECTOR_`. It also holds the dev-only
  domain-verification IAM anchor (see [Custom domains](#custom-domains)).
- **build** (`pulumi_oauth_user_inspector_build`) — the cross-env singletons in
  the infra-pipeline project: the `oauth-user-inspector` Artifact Registry repo,
  the `oauth-user-inspector-build` SA (+ its WIF binding and AR-writer grant),
  and per-env AR **reader** grants for *both* each env's Cloud Run service agent
  (`service-<projnum>@serverless-robot-prod.iam.gserviceaccount.com`) *and* each
  env's deploy SA (Cloud Run validates image access as the deploying principal
  at create time — this reader grant is easy to forget and a common 403 source).
- **zitadel-apps** — the per-env OIDC client on the self-hosted Zitadel, and the
  sync of its client id/secret into the env's Secret Manager. See
  [Zitadel hosted-login](#zitadel-hosted-login).

## Deploy pipeline

Workflow: [`.github/workflows/oauth-user-inspector-deploy.yaml`](../../.github/workflows/oauth-user-inspector-deploy.yaml).

**Trigger.** Push to `main` touching `oauth-user-inspector/**` (excluding the
identity stack), the zitadel-apps stack, or the workflow files; plus
`workflow_dispatch` with a single-env choice.

**Shape — build once, promote by digest:**

```
build ──▶ (zitadel-dev) ──▶ deploy-dev ──▶ (zitadel-nonprod) ──▶ deploy-nonprod ──▶ (zitadel-prod) ──▶ deploy-prod
  │           gated                auto             gated               reviewer            gated              reviewer
  └─ docker buildx build+push to the shared AR, then resolve the IMMUTABLE @sha256 digest → output image-digest
```

- The `build` job runs in the ungated `oauth-user-inspector-build` GitHub
  Environment, pushes `…/oauth-user-inspector/app:<sha>`, then resolves the
  digest with `gcloud artifacts docker images describe`. **Every** `deploy-*`
  job consumes that same `image-digest` — the image is never rebuilt per env.
- Each `deploy-*` calls the reusable
  [`_deploy-cloud-run.yaml`](../../.github/workflows/_deploy-cloud-run.yaml),
  which does **blue-green**: `pulumi up` publishes the new revision at 0% behind
  the `candidate` tag (`_PROMOTE=false`), smoke-checks the candidate URL (curl +
  headless-Chrome DOM assert of the string `"Select a provider"`), then
  `pulumi up` again to shift 100% (`_PROMOTE=true`). It refuses to smoke the
  *stable* revision on a non-first deploy (a false-green guard).
- `deploy-nonprod` and `deploy-prod` run in the **reviewer-gated** GitHub
  Environments `oauth-user-inspector-{nonproduction,production}` — promotion
  pauses for human approval. `deploy-dev` is ungated.
- Each env is preceded by a `zitadel-<env>` job (see
  [Zitadel hosted-login](#zitadel-hosted-login)); those are gated on the
  `ZITADEL_APPS_AUTO_APPLY` repo variable and a deploy tolerates its zitadel job
  being *skipped* but not *failed*.

**PR preview.** [`pulumi-preview.yaml`](../../.github/workflows/pulumi-preview.yaml)
runs an advisory, token-less `pulumi preview` of the dev app stack on PRs
touching it (gated on `PULUMI_PREVIEW_ENABLED`). It passes the placeholder
`CLOUDFLARE_API_TOKEN=preview-only-not-a-real-cloudflare-token` so the preview
never needs a real Cloudflare credential.

The shared **build** stack is applied by its own workflow
[`oauth-user-inspector-build-stack.yaml`](../../.github/workflows/oauth-user-inspector-build-stack.yaml)
(reviewer-gated `foundation-proj-shared` env, runs as `sa-terraform-proj`).

## Identity & keyless auth

No long-lived service-account keys. CI authenticates to GCP via **Workload
Identity Federation** against the shared foundation pool:

```
projects/1064807322707/locations/global/workloadIdentityPools/foundation-pool/providers/foundation-gh-provider
```

Each GitHub Environment carries the identity as **non-secret Actions variables**
(`GCP_PROJECT_ID`, `GCP_REGION`, `GCP_WORKLOAD_IDENTITY_PROVIDER`,
`GCP_DEPLOY_SERVICE_ACCOUNT`), published as code by
[`repo_config`](../../infrastructure/pulumi/platform/repo_config). The WIF
binding is scoped by `attribute.environment` so a workflow running in the
`oauth-user-inspector-<env>` environment can impersonate only that env's SA.

| Principal | Identity | Used for |
| --- | --- | --- |
| build SA | `oauth-user-inspector-build@prj-c-bu1-infra-pipeline-4b48` | push image to the shared AR |
| deploy SA (per env) | `oauth-user-inspector-deploy@prj-{d,n,p}-bu1-oss-floating-*` | `pulumi up` the app stack |
| runtime SA (per env) | `oauth-user-inspector-rt@prj-{d,n,p}-bu1-oss-floating-*` | the Cloud Run service identity |

Environments/vars are defined in
`infrastructure/pulumi/platform/repo_config/main.go` (`oauthEnvironment()`); the
SAs, IAM, and WIF bindings are the [identity stack](#the-moving-parts).

## Secrets

Three homes, deliberately separated. **Never commit a secret** — not even a
Pulumi-encrypted one.

1. **GCP Secret Manager — app runtime.** The `OAUTH_USER_INSPECTOR_`-prefixed
   entries the server reads at request time: the hosted provider creds
   (`*_APP_OAUTH_CLIENT_ID/_SECRET`, Auth0 also `_DOMAIN`), the Zitadel client
   id/secret, and (in the dev project) `CLOUDFLARE_API_TOKEN` used at deploy time
   for the DNS record. The runtime SA can read only the prefixed set.
2. **GitHub Environment secrets — CI-only.** Secrets CI itself consumes that are
   *not* in Secret Manager: `ZITADEL_MACHINE_KEY_JSON` (the Zitadel machine-user
   key for the Pulumi provider) and `TS_OAUTH_CLIENT_ID` / `TS_OAUTH_SECRET` (the
   Tailscale on-ramp so CI can reach Zitadel over the tailnet). These are managed
   by [`tools/sync-env-secrets`](../../tools/sync-env-secrets), **not** by
   repo_config.
3. **Bitwarden — source of truth for the GitHub-secret class.** `sync-env-secrets`
   is a Bazel-wrapped, Bitwarden-backed tool. The on-disk store lives at
   `tools/sync-env-secrets/secrets/<github-environment>/<SECRET_NAME>` (one file
   per secret, gitignored). Targets: `unlock`, `lock`, `bw-pull` (Bitwarden →
   local), `apply -- <env>` (local → GitHub, upsert; needs no Bitwarden),
   `bw-push` (local → Bitwarden).

See [Runbooks → rotate a secret](#rotate-a-secret) for the mechanics.

## Custom domains

Each env's app stack (`oauth-user-inspector/infra/app`, gated on the
`customDomain` config key) declares:

- a **Cloud Run `DomainMapping`** (v1 API) with **`ForceOverride: true`** — set
  in every env; production needs it to take the hostname over from the retired
  personal `gen-lang` mapping;
- a **grey-cloud Cloudflare `CNAME`** → the mapping's target (fallback
  `ghs.googlehosted.com`), **`Proxied: false`** and **TTL 300**. DNS-only
  (grey cloud) is required so Google's managed certificate can validate.

Zone is pinned by `cloudflareZoneId: a346c14c429c7356c0e4e3a9b623a104`
(`ipv1337.dev`) to avoid a phantom-replace on deploy. Hostnames per env are in
the table at the [top](#environments--projects).

**Domain ownership** is self-verified per environment in CI
(`tools/ci/ensure-site-verification.sh`, invoked from `_deploy-cloud-run.yaml`),
because Site Verification ownership is per-caller — each env's deploy SA verifies
its own domain. The IAM anchor that lets each deploy SA read the shared
`CLOUDFLARE_API_TOKEN` is the dev-only block in the identity stack
(`cloudflareTokenAccessorProjects`).

> ⚠️ **One manual, one-time step per project.** The **Site Verification API**
> cannot be enabled via `serviceusage`/IaC (even a project-owner SA gets HTTP 403
> `PRECONDITION_FAILURE`). It must be enabled by hand, once, per oss project, in
> the console:
> `https://console.cloud.google.com/apis/library/siteverification.googleapis.com?project=<PROJECT_ID>`.
> Track status in the app [README](../README.md#hosted-oauth--redirect-uris).

## Zitadel hosted-login

The self-hosted Zitadel instance (`auth.ipv1337.dev`) is GitOps-managed
(`gitops/argocd/platform/zitadel/`). The per-env **OIDC client** for this app is
managed as code in
[`infrastructure/pulumi/platform/zitadel-apps`](../../infrastructure/pulumi/platform/zitadel-apps):

- one `ApplicationOidc` per env (`oauth-user-inspector-web`,
  `-web-nonproduction`, `-web-production`), web app, `client_secret_post`, auth
  code + refresh grants. **Never imported** — this provider's import plans a
  destructive replace that *deletes* the live client (a real incident on
  2026-06-26); the stack owns and creates it.
- the client id/secret are synced into the env's Secret Manager as
  `OAUTH_USER_INSPECTOR_ZITADEL_APP_OAUTH_CLIENT_ID/_SECRET` (gated on the
  `ossProject` config), which is exactly what the server reads at runtime.
- redirect URIs are committed per env in the stack's `Pulumi.<env>.yaml`; the
  live `run.app` URL is appended automatically via a stack reference.

The `zitadel-<env>` CI jobs (reusable
[`_zitadel-apps-apply.yaml`](../../.github/workflows/_zitadel-apps-apply.yaml))
join the tailnet with `TS_OAUTH_*` and reach the Zitadel management API through
the Envoy gateway NodePort on a node's tailscale IP
(`nuc9i9.coati-koi.ts.net:30265`) — **not** the public Cloudflare edge (which
returns bot-protection 1010) and **not** the LB VIP over the subnet router. They
are gated on the repo variable `ZITADEL_APPS_AUTO_APPLY` (currently `"true"`).

### Redirect URIs

In every mode the app sends its **own origin** as `redirect_uri`, and providers
match it exactly (trailing slash included). So:

- every **hosted** provider application (github.com, Google, Zitadel, …) must
  have the env's exact URL registered — `https://oauth-inspector.ipv1337.dev/`
  for prod, `…dev.ipv1337.dev/` for dev, `…staging.ipv1337.dev/` for nonprod,
  plus `http://localhost:8080/` for local. For **Zitadel** these are managed in
  `zitadel-apps`; for the **other providers** they are registered in each
  provider's own console (external, manual).
- register the **decoded** form (with the slash), not a percent-encoded one.

## Runbooks

### Deploy a code change

1. Merge the change to `main` (via the merge queue). The push triggers
   `oauth-user-inspector-deploy.yaml`: `build` → `deploy-dev` runs automatically.
2. Approve `deploy-nonprod`, then `deploy-prod` in the GitHub Actions UI when you
   want to promote. The **same digest** flows through all three — nonprod and
   prod are not rebuilt.
3. Watch the per-env smoke step; a failed smoke fails the job before traffic
   shifts.

### Redeploy a single environment

Run the workflow via **`workflow_dispatch`** and pick the `environment`. Useful
to re-roll prod without a code change (it rebuilds the image and redeploys that
one env).

### Roll back

Blue-green keeps the previous revision addressable. To put traffic back on the
prior revision, redeploy with the previous image digest — dispatch the deploy
workflow for that env after reverting the commit, or drive the app stack's
`OAUTH_USER_INSPECTOR_STABLE_REVISION` / `_PROMOTE` inputs through CI. Because
the promote step is a separate `pulumi up`, a bad candidate that fails smoke
never receives traffic in the first place.

### Rotate a secret

- **App runtime secret** (a hosted provider client secret, the Zitadel secret):
  add a new version in Secret Manager for the env's project under the
  `OAUTH_USER_INSPECTOR_`-prefixed name. The server caches for 60 s, so the new
  value takes effect within a minute — no redeploy needed. For the Zitadel
  secret, re-apply `zitadel-apps` (it re-syncs id/secret to SM).
- **CI secret** (`ZITADEL_MACHINE_KEY_JSON`, `TS_OAUTH_*`): update the Bitwarden
  item, then:
  ```bash
  # from the repo root
  bazel run //tools/sync-env-secrets:unlock          # once; caches a BW session
  bazel run //tools/sync-env-secrets:bw-pull          # Bitwarden → local store
  bazel run //tools/sync-env-secrets:apply -- oauth-user-inspector-development
  bazel run //tools/sync-env-secrets:apply -- oauth-user-inspector-nonproduction
  bazel run //tools/sync-env-secrets:apply -- oauth-user-inspector-production
  ```
  (`apply` upserts the on-disk store into that GitHub Environment's secrets.)

### Add / enable a hosted provider

1. Register (or reuse) an OAuth application at the provider, allowing every env's
   exact redirect URI.
2. Seed the creds into each env's Secret Manager by hand with `gcloud secrets
   versions add` under the `OAUTH_USER_INSPECTOR_` prefix.

   > The original 11 non-Zitadel provider secrets were copied out of the personal
   > `gen-lang` project by a one-time `workflow_dispatch` job (PR #963), keyless as
   > the env deploy SA with the value piped `access | versions add` so it was never
   > printed. That workflow was removed once `gen-lang` was decommissioned
   > (2026-07-20); see the git history if you need the pattern for another app.
3. `GET /api/oauth-hosted/availability` should now report the provider `true`.

### Add / change a redirect URI

- **Zitadel:** edit `redirectUris` in `zitadel-apps/Pulumi.<env>.yaml` and let CI
  re-apply — do not edit the Zitadel console by hand.
- **Other providers:** add it in that provider's own developer console
  (external, manual).

### First-time / cold deploy ordering

For a brand-new env the order matters (later steps depend on earlier outputs):
`repo_config` (creates the GitHub Environments + WIF vars) → **build** stack
(AR + build SA + WIF binding) → **identity** stack (deploy/runtime SAs) →
enable the Site Verification API in the console → the deploy workflow's `build`
+ `deploy-<env>` jobs. Seed the CI secrets with `sync-env-secrets:apply` before
the first `zitadel-<env>` job.

### Local development

```bash
pnpm install
pnpm dev        # Vite dev server (frontend) + nodemon-rebuilt Express server
pnpm test       # jest (or: bazel test //oauth-user-inspector:unit_tests)
```

Set `GOOGLE_CLOUD_PROJECT` and use Application Default Credentials if you want to
exercise the hosted-login paths against real Secret Manager; otherwise the BYO
and PAT paths work without any GCP access. A local `pulumi up` of these stacks is
**not** sanctioned — infra changes go through CI. If you must break-glass, the
app stack accepts an `imageDigest` config key and a real `CLOUDFLARE_API_TOKEN`.

## Pointers

| Thing | Where |
| --- | --- |
| App stack (Cloud Run + custom domain) | `oauth-user-inspector/infra/app/main.go` |
| Identity stack (SAs + WIF) | `oauth-user-inspector/infra/identity/main.go` |
| Build stack (shared AR) | `oauth-user-inspector/infra/build/main.go` |
| Zitadel OIDC client + SM sync | `infrastructure/pulumi/platform/zitadel-apps/main.go` |
| GitHub Environments + WIF vars | `infrastructure/pulumi/platform/repo_config/main.go` (`oauthEnvironment`) |
| Deploy pipeline | `.github/workflows/oauth-user-inspector-deploy.yaml` |
| Reusable blue-green deploy | `.github/workflows/_deploy-cloud-run.yaml` |
| Reusable Zitadel apply | `.github/workflows/_zitadel-apps-apply.yaml` |
| CI secret sync tool | `tools/sync-env-secrets/` |
| Site-verification helper | `tools/ci/ensure-site-verification.sh` |
| Design spec (stage 5) | `docs/superpowers/specs/2026-07-10-oss-application-stage-design.md` |
