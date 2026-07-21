# Migrating tabula off the personal projects onto foundation bu2

**Status:** in progress, started 2026-07-21.
**Goal:** tabula — the last app deploying from a personal GCP project — moves onto the
vitruviansoftware.dev foundation with its **own** per-env projects in a **new business
unit 2**, and both personal projects are decommissioned.

Reference: the oauth-user-inspector migration and
[`docs/oss-app-onboarding-checklist.md`](../../oss-app-onboarding-checklist.md). That
checklist assumes an app co-tenants bu1's shared `prj-{env}-bu1-oss-floating`; tabula
gets dedicated bu2 projects instead, so Phases 2–5 are adapted below.

---

## What is actually being migrated

Tabula ships five packages but only **one** is a cloud deployable:

| Package | Ships as | Cloud infra? |
| --- | --- | --- |
| `tabula/api` | Cloud Run v2 (`tabula-api-dev`, us-central1) | **yes — the only one** |
| `tabula/extension` | GitHub Releases zip (not on the Web Store) | no — but see the URL weld below |
| `tabula/cli`, `tabula/web`, `tabula` (root) | not published / not built | no |

**Two personal projects**, both owned by `james.nguyen@gmail.com`, both org-less:

| Project | Number | State |
| --- | --- | --- |
| `tabula-dev-0001` | 796264355044 | **live** — the running dev deploy |
| `tabula-prd-0001` | 1050452266780 | **orphan** — referenced by zero repo files, never worked |

`tabula-prd-0001` is dead but was not inert: its Cloud Run revision has never started
(image not found), it has no WIF pool, and it was running **three ENABLED Cloud Scheduler
jobs** POSTing every 5 min at a third, non-existent hostname — `status.code: 5` on every
invocation since Dec 2025. **Paused 2026-07-21** as an immediate mitigation; deleted at
decommission. It still holds real production `DATABASE_URL` / `WORKOS_API_KEY` /
`UPSTASH_REDIS_URL` values.

---

## The five things that make this harder than oauth-user-inspector

1. **Stateful.** The database is **Neon** (external SaaS, org `org-little-shape-81083488`)
   and Redis is **Upstash** — neither is in GCP, and neither moves into the foundation.
   There is no Cloud SQL and every GCS bucket is empty, so **this is not a data
   migration**; what must happen is per-env Neon branches + Upstash databases, because
   today all environments would share one dev database. Both vendors have APIs and their
   keys are already in Secret Manager (`NEON_API_KEY`, `UPSTASH_API_KEY`), so this is
   automatable rather than console work.

2. **Secrets are read the wrong way for a cold deploy.** Tabula uses Cloud Run
   `secretKeyRef` with **bare** names (`DATABASE_URL`, `JWT_SECRET`, …) and
   `lib/workos.ts` **throws at module import**. `secretKeyRef` makes the *revision itself*
   un-creatable when a secret is absent, so the app cannot roll out before its creds land
   — the exact ordering the checklist's Phase 1 exists to preserve. Bare names would also
   collide with any co-tenant. **Requires app-code change**: lazy Secret Manager reads
   behind a `TABULA_` prefix, matching oauth-user-inspector.

3. **The extension is welded to the dev Cloud Run URL.** `tabula/extension/BUILD` bakes
   `API_URL=https://tabula-api-dev-q7dosy3wiq-uc.a.run.app/api/v1` into `host_permissions`
   at build time. Changing the API hostname breaks every installed extension, and an added
   host permission **disables the extension until the user re-accepts**. ⇒ stand up the
   custom domain and repoint the extension at it *before* the project cutover, so the
   hostname never changes again.

4. **Migrations run in the deploy pipeline.** `prisma migrate deploy --phase expand` runs
   as the deploy SA before any traffic shift, gated by the required Squawk
   `migration-safety` check. The deploy SA needs `secretAccessor` on `DATABASE_URL` in each
   new project, and expand/contract discipline must survive the move. Note that blue-green
   protects *traffic*, not *schema* — a rollback does not roll back a migration.

5. **Two decommission targets, and a standing credential path.** The dev WIF pool
   `github-actions-dev-1` has **no `attribute.environment` mapping** and trusts
   `assertion.repository == "BlueCentre/tabula" || "VitruvianSoftware/vitruvian-core"` —
   so any workflow in *either* repo, in any environment, can mint a token for an SA holding
   `secretmanager.admin` + `run.admin` + `iam.serviceAccountAdmin`. It is **load-bearing**
   until cutover, so it dies last, not first.

---

## Phases

Ordering is strict — later phases consume earlier outputs.

| # | Phase | PR | Notes |
| --- | --- | --- | --- |
| 1 | **Foundation stage 4 — bu2** | #973 | `business_unit_2/` leaves, workflow `business_unit` input, gitignore negation. Creates `fldr-{env}-bu2` + `prj-{d,n,p}-bu2-oss-floating-*` + `prj-c-bu2-infra-pipeline-*`. |
| 2 | **App-code: `TABULA_` prefix + lazy SM reads** | | Removes blocker #2. TDD. Must land before any new-project deploy. |
| 3 | **repo_config** | | `tabula-{development,nonproduction,production,build,preview}` environments + per-env WIF vars pointing at the bu2 projects. |
| 4 | **org DRS override** | | bu2 project ids appended to `oss_public_invoker_projects` — tabula is public. Org SA, `foundation-org` gate. Can only be written *after* phase 1 applies (ids carry a random suffix). |
| 5 | **`tabula/infra/{build,identity,app}`** | | Mirrors oauth-user-inspector. Build stack in `prj-c-bu2-infra-pipeline-*`; identity per env with prefix-conditioned `secretAccessor`; app on `pkg/cloud_run` with digest promotion. |
| 6 | **Neon + Upstash per-env** | | Provision via their APIs; write `TABULA_DATABASE_URL` / `TABULA_UPSTASH_REDIS_URL` into each project's Secret Manager. |
| 7 | **Custom domains** | | `tabula-api.{dev.,staging.,}ipv1337.dev`. Needed *before* cutover to break the extension weld. ⚠️ requires the per-project console enable of `siteverification.googleapis.com` — the one step IaC cannot do. |
| 8 | **Deploy pipeline** | | Build once → promote one digest dev→nonprod→prod. `_deploy-cloud-run.yaml` already supports `image-digest`; the caller doesn't use it yet. |
| 9 | **Verify + decommission** | | Both personal projects. WIF pool first, then services/SAs/secrets/AR. |

## Known manual interlocks

- **`siteverification.googleapis.com`** cannot be enabled by IaC (HTTP 403
  `PreconditionFailure` even as project owner) — one console click per new project, and
  only if custom domains are adopted.
- **WorkOS redirect URIs** are dashboard-managed; each env's exact callback URL must be
  registered or auth fails despite valid creds.
- **Reviewer-gated GitHub Environments** (`foundation-proj-*`, `foundation-org`,
  `tabula-production`) require an approval per deploy.

## Decommission checklist (both projects)

Ordered so the standing credential path dies first once it is no longer load-bearing:

1. WIF pool `github-actions-dev-1` (**and** the `BlueCentre/tabula` trust) — `tabula-dev-0001`
2. Cloud Run services, both projects
3. Service accounts, both projects
4. Secret Manager secrets, both projects (after confirming the new envs read their own)
5. Cloud Scheduler jobs (`tabula-prd-0001`, already paused)
6. Artifact Registry: `tabula` 1.4 GB + `gcr.io` 260 MB (dev), `cloud-run-source-deploy`
   838 MB (prd)
7. Dead weight: 8 unused Pub/Sub topics, 4 empty buckets, legacy `terraform/state/default.tfstate`
8. Repo: retire `infrastructure/pulumi/apps/tabula/`, update `gcp-identities.tsv`,
   `EXTRA_PATH_REGEX` in `tabula-deploy.yaml`, and the stale
   `docs/tabula/reference/infrastructure.md` / `workos-configuration.md`
