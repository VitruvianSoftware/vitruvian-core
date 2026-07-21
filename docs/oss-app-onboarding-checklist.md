# Onboarding a new OSS app onto the foundation

A step-by-step checklist for deploying a new OSS application across
dev → nonproduction → production on the `prj-{env}-bu1-oss-floating` projects —
the **OSS application stage** (foundation stage 5).

Distilled from migrating the reference app **oauth-user-inspector** off a
personal single-project deploy onto the live foundation. Every step here was a
lesson; the "⚠️ Why" notes are the ones that bit us.

- **Worked example / source of truth:** `oauth-user-inspector/infra/`,
  `infrastructure/pulumi/apps/oauth-user-inspector-build/`, and
  [`oauth-user-inspector/docs/OPERATIONS.md`](../oauth-user-inspector/docs/OPERATIONS.md).
- **Design:** `docs/superpowers/specs/2026-07-10-oss-application-stage-design.md`.
- **Reusable module:** `pulumi/examples/go-foundation/5-app-infra/modules/serverless_space` +
  the published `pkg/cloud_run` primitive.

Throughout, replace `myapp` with your app's slug and `MYAPP_` with its
uppercased secret prefix.

---

## Phase 0 — Inventory before you touch code

> ⚠️ **The single biggest lesson: a migration is a secret + allow-list
> inventory, not a deploy change.** Moving the code is ~20% of the work. We
> shipped oauth-user-inspector with five hosted providers silently broken
> (`available:false`) because only one provider's creds were carried over.

- [ ] **List every runtime secret** the app reads (client ids/secrets, API
      tokens, signing keys). For each: where does it live today, and what is its
      new name under the `MYAPP_` prefix?
- [ ] **List every external allow-list entry** the app depends on — OAuth
      redirect URIs, API-key origin allow-lists, webhook URLs. Each env gets a
      *different* public URL, so each needs its own entry.
- [ ] **Decide the public exposure**: is this a public (`allUsers` invoker) app
      or internal? Public apps need the org DRS override (Phase 2).
- [ ] **Decide the custom-domain hostnames** per env (e.g.
      `myapp.dev.ipv1337.dev`, `myapp.staging.ipv1337.dev`, `myapp.ipv1337.dev`),
      or skip domains and serve on the `run.app` URL.
- [ ] **Pick the secret prefix** `MYAPP_` — it must be unique among co-tenants
      in the shared oss projects.

---

## Phase 1 — Make the app deploy-ready

- [ ] **Read runtime secrets lazily from Secret Manager**, prefixed by a
      `SECRET_PREFIX` env var — *not* via Cloud Run `secretKeyRef`.
      > ⚠️ **Why:** lazy reads decouple the deploy from the secret existing yet,
      > so the service can roll out before creds land (essential when secrets
      > trickle in per env during a migration). The prefix is what makes several
      > apps co-tenant one project without secret-name collisions.
- [ ] **Containerize** with a multi-stage Dockerfile, non-root user, `PORT`
      from env (default 8080), and a `HEALTHCHECK`. Build must be self-contained
      (neutralize any monorepo `catalog:` version refs).
- [ ] **Add a `catalog-info.yaml`** (Backstage) with the deploy-workflow +
      owner annotations; the declared owner must match `.github/CODEOWNERS`
      (conformance enforces it).
- [ ] **CI test target** (`bazel test //myapp:unit_tests`) green.

---

## Phase 2 — Foundation prerequisites (one-time per app)

These are edits to shared foundation stacks; each applies through its own CI
workflow (**never** a local `pulumi up`).

- [ ] **repo_config** (`infrastructure/pulumi/platform/repo_config`): add the
      five GitHub Environments `myapp-{development,nonproduction,production,build,preview}`.
      Gate nonproduction/production with protected-branches + reviewers; leave
      development/build/preview ungated. Publish the per-env **non-secret**
      Actions variables: `GCP_PROJECT_ID`, `GCP_REGION`,
      `GCP_WORKLOAD_IDENTITY_PROVIDER` (the shared `foundation-pool` provider),
      `GCP_DEPLOY_SERVICE_ACCOUNT`.
- [ ] **gcp-org DRS override** (only if the app is public): add the app's oss
      projects to the project-scoped domain-restricted-sharing allow-list so
      `allUsers` `run.invoker` is permitted. Applied by the org SA.
      > ⚠️ **Why:** the org default forbids `allUsers`; without the per-project
      > override the public invoker binding fails.
- [ ] Confirm the `foundation-pool` WIF provider maps `attribute.environment`
      (it does since the bootstrap change) — least-privilege binds each stage's
      SA to its GitHub Environment on the single repo.

---

## Phase 3 — Shared build stack (build once, promote the digest)

- [ ] Create `infrastructure/pulumi/apps/myapp-build/` (production-only stack) in
      the shared infra-pipeline project: an Artifact Registry repo, the
      `myapp-build` SA + its WIF binding (`attribute.environment/myapp-build`) +
      AR-writer grant, and **per-env AR reader grants for BOTH**:
  - the Cloud Run service agent `service-<projnum>@serverless-robot-prod.iam.gserviceaccount.com`, and
  - the per-env deploy SA `myapp-deploy@prj-{env}-bu1-oss-floating-*`.
      > ⚠️ **Why (the one live bug we hit):** a cross-project image pull needs
      > the runtime service agent as reader *and* the **deploying SA** as reader
      > — Cloud Run validates image access as the deploying principal at create
      > time. Missing the deployer grant is a 403 that looks like a runtime
      > problem.
- [ ] Apply via a `myapp-build-stack.yaml` workflow as `sa-terraform-proj` under
      the reviewer-gated `foundation-proj-shared` environment.

---

## Phase 4 — Per-env identity stack

- [ ] Create `myapp/infra/identity/` (per-env): the `myapp-deploy` and
      `myapp-rt` service accounts, the WIF binding
      (`attribute.environment/myapp-<env>`), the deploy SA's project IAM
      (`run.admin`, `iam.serviceAccountUser`, `serviceusage.serviceUsageConsumer`,
      `logging.viewer`), and the runtime SA's **`secretmanager.secretAccessor`
      conditioned to `resource.name.startsWith("projects/<projNum>/secrets/MYAPP_")`**.
      > ⚠️ **Why the condition:** in a shared project, an unconditioned accessor
      > would let one app read a co-tenant's secrets. Scope it to the prefix.
- [ ] Federate against the **shared** `foundation-pool` — do not stand up a
      per-app WIF pool. Apply as `sa-terraform-proj`.

---

## Phase 5 — App stack

- [ ] Create `myapp/infra/app/` (per-env) on the `pkg/cloud_run` primitive:
      Cloud Run v2 service `myapp-<env>`, `SECRET_PREFIX=MYAPP_`,
      `GOOGLE_CLOUD_PROJECT`, the runtime SA, `allUsers` invoker if public.
- [ ] **Consume an immutable image digest** via `MYAPP_IMAGE_DIGEST` (no mutable
      tag). On preview/DryRun, substitute a placeholder digest so token-less
      previews work.
      > ⚠️ **Why:** the same `@sha256` flows dev→nonprod→prod, so the artifact
      > that reaches prod is byte-identical to the one smoke-tested in dev.
- [ ] Implement **blue-green** traffic (new revision at 0% behind a `candidate`
      tag → smoke → promote to 100%), driven by `MYAPP_PROMOTE` /
      `MYAPP_STABLE_REVISION`.

---

## Phase 6 — Seed secrets (all three homes)

Keep the three homes straight; never commit a secret, not even Pulumi-encrypted.

- [ ] **GCP Secret Manager (app runtime):** seed the `MYAPP_`-prefixed creds into
      each env's oss project. To migrate from an existing project, use a one-time
      `workflow_dispatch` job that copies secrets keyless as the env deploy SA,
      piping `gcloud secrets versions access | versions add` (value never
      printed). Worked example: `oauth-user-inspector-migrate-hosted-creds.yaml`
      in PR #963 — deleted after `gen-lang` was decommissioned, so read it from
      the git history. **Delete the job once the source project is retired**: a
      dispatchable workflow pointing at a dead project only fails confusingly.
- [ ] **GitHub Environment secrets (CI-only):** any secret CI itself consumes
      that is *not* in Secret Manager (e.g. a Zitadel machine key, Tailscale
      on-ramp) → manage via `tools/sync-env-secrets`
      (`bazel run //tools/sync-env-secrets:apply -- myapp-<env>`), sourced from
      Bitwarden. Seed these **before** the first CI run that needs them.
- [ ] **Register redirect URIs / allow-list entries** for each env in every
      external console (OAuth providers, etc.).
      > ⚠️ **Why:** seeding the creds flips availability, but the provider still
      > rejects the authorize request unless the env's exact redirect URI
      > (trailing slash included — providers match byte-for-byte) is registered.

---

## Phase 7 — Custom domains (if used)

- [ ] In the app stack, declare a Cloud Run `DomainMapping` with
      **`ForceOverride: true`** and a grey-cloud Cloudflare `CNAME`
      (**`Proxied: false`**, TTL 300) → the mapping target (fallback
      `ghs.googlehosted.com`).
      > ⚠️ **Why grey cloud:** Google's managed cert can't validate behind
      > Cloudflare's proxy. **Why ForceOverride:** to take a hostname over from a
      > mapping in the retired project during cutover.
- [ ] **Pin `cloudflareZoneId`** (don't `LookupZone` in preview) and gate any
      live Cloudflare call on a *real* token, not `ctx.DryRun()`.
      > ⚠️ **Why:** a deploy's own preview pass is also `DryRun`, so gating on
      > `DryRun()` caused a phantom `~zoneId` replace. Pin the id + use a
      > placeholder token for token-less previews.
- [ ] **Enable the Site Verification API by hand, once, per oss project** in the
      console (`.../siteverification.googleapis.com?project=<PROJECT_ID>`).
      > ⚠️ **Why:** it cannot be enabled via `serviceusage`/IaC — even a
      > project-owner SA gets HTTP 403 `PRECONDITION_FAILURE`. Per-env ownership
      > is self-verified in CI (`tools/ci/ensure-site-verification.sh`).

---

## Phase 8 — Hosted IdP login (if the app offers "sign in with our app")

- [ ] Manage the OIDC client as code (e.g. `zitadel-apps`), **creating and
      owning** it — never `pulumi.Import` an existing client.
      > ⚠️ **Why:** the Zitadel provider's import plans a force-new replace that
      > *deletes* the live client (a real incident). Create + own; sync the
      > minted id/secret into each env's Secret Manager (`ossProject`-gated).
- [ ] If CI must reach a self-hosted IdP on the cluster, target the gateway
      **NodePort on a node's tailscale IP**, not the LB VIP over the subnet
      router, and not the public edge.
      > ⚠️ **Why:** `externalTrafficPolicy: Local` drops subnet-router-forwarded
      > traffic on nodes with no local backend; the public edge returns
      > bot-protection 1010.

---

## Phase 9 — Deploy pipeline

- [ ] Wire `myapp-deploy.yaml`: a `build` job (push image, resolve the immutable
      digest) → per-env `deploy-<env>` jobs consuming that **same** digest via
      the reusable `_deploy-cloud-run.yaml`, chained
      development(auto) → nonproduction(gated) → production(gated).
- [ ] Add a **smoke check** per env (curl 2xx + a DOM/marker assertion) and keep
      the "don't smoke the stable revision on a non-first deploy" false-green
      guard.
- [ ] Add a PR `pulumi-preview` leg (advisory, token-less) for the dev app stack.
- [ ] Everything — including state resets during cutover — goes through CI
      (`pulumi-stack-reset.yaml`), never a local `pulumi up`/`stack rm`.

---

## Cold-deploy ordering (first time)

Later steps depend on earlier outputs:

```
repo_config (envs + WIF vars)
  → build stack (AR + build SA + WIF binding)
  → identity stack (deploy/runtime SAs)
  → enable Site Verification API in the console (manual, per project)
  → seed CI secrets (sync-env-secrets:apply)   # before the first IdP job
  → deploy workflow: build → deploy-dev → deploy-nonprod → deploy-prod
```

## Verify & decommission

- [ ] Each env serves 2xx on its `run.app` URL and its custom domain.
- [ ] `GET /…/availability` (or equivalent) reports every provider/feature ready.
- [ ] Confirm your commits actually landed on `origin/main`
      (`git merge-base --is-ancestor <sha> origin/main`) and that your working
      checkout is not stale before declaring done.
      > ⚠️ **Why:** "pushed to a PR" ≠ "in main", and a stale local checkout will
      > happily show you a false reality. Reconcile against `origin/main`; do
      > isolated work in a worktree.
- [ ] Leave the old single-project deploy orphaned only with the owner's
      explicit OK; don't delete anything that isn't yours.

## The gotchas, in one place

| Trap | Guard |
| --- | --- |
| Only some secrets migrated | Inventory **all** runtime secrets + external allow-list entries in Phase 0 |
| Cross-project image 403 | Grant AR reader to **both** the service agent **and** the deploy SA |
| `allUsers` invoker rejected | Add the oss projects to the org DRS override |
| Co-tenant secret leakage | Prefix-conditioned `secretAccessor` on the runtime SA |
| Phantom `~zoneId` replace | Pin `cloudflareZoneId`; gate on a real token, not `DryRun()` |
| Managed cert won't validate | Grey-cloud (`Proxied: false`) Cloudflare record |
| Site Verification 403 from IaC | Enable the API by hand in the console, once per project |
| OIDC client deleted on apply | **Create + own** the client; never import |
| CI can't reach the IdP | NodePort on a node's tailscale IP (not the LB VIP / public edge) |
| Redirect rejected despite creds | Register each env's exact redirect URI (trailing slash) in the provider console |
| "Done" but not really | Verify the sha is an ancestor of `origin/main`; refresh your checkout |
