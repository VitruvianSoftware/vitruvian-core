# Neon + Upstash as code — reusable modules and the tabula cutover

**Status:** planned, 2026-07-22
**Prompted by:** minting fresh Neon/Upstash API keys revealed the keys now point at
*new, empty* accounts while the live databases sit in the *old* ones — and that
**no IaC exists for either service at all.**

---

## The gap

Tabula's stateful tier is entirely outside GCP: Postgres is Neon (three projects,
one per env) and the cache is Upstash Redis (one instance, shared across all
three envs). Every one of those resources was **created by hand**, two of them
during the bu2 migration. A repo-wide search finds no Neon or Upstash resource
anywhere — only comments.

Consequences:

- **A from-scratch rebuild is impossible without manual clicking.** The GCP side
  of tabula can be destroyed and reapplied from code; its database cannot.
- **No drift detection.** Nothing notices if a database's size, region, retention
  or role changes underneath us.
- **Credentials and data have drifted apart.** The management keys now in
  `prj-c-bu2-infra-pipeline-3d09` belong to new accounts; the live data belongs
  to the old ones. Automation driven by those keys would provision into the wrong
  place.

Nothing is *broken*: the app authenticates with connection strings, not the
management keys, and all three envs serve `HTTP 200` with `redis: connected`.
This is a resilience and reproducibility gap, not an outage.

## Decisions

### 1. Bridge the Terraform providers — NOT new tooling

Neither service has a native Pulumi provider, and **Pulumi has no dynamic
providers in Go**, so a pure-Go implementation would mean writing and maintaining
two full providers for ~6 resources.

Principle §126 ("Pulumi-in-Go for all IaC (never Terraform/OpenTofu/CDK)")
demands sign-off before a new IaC system lands. Sign-off given — and the premise
turns out to be weaker than it looked: **the repo already ships two bridged
providers**, `pulumiverse/pulumi-zitadel` and `pulumiverse/pulumi-time`.
Pulumiverse packages *are* TF bridges. So this is the existing pattern, not a new
one; the only difference is that we generate the SDK ourselves because nobody has
published these two.

Verified by spike (`pulumi v3.229.0`):

| provider | result |
| --- | --- |
| `upstash/upstash` (official) | SDK generated, `redisDatabase.go` present, 240K / 24 files |
| `kislerdm/neon` (community) | SDK generated; `project`, `branch`, `database`, `role`, `endpoint` present |

Neither generated SDK is published to `proxy.golang.org`, so both are **vendored**
— the standard `pulumi package add` workflow, and small enough to review.

⚠️ The Neon provider is **community-maintained; Neon ships no official one**. That
is a real supply-chain consideration for a production database: pin the version,
vendor the SDK (which we are doing anyway), and treat a provider bump as a
reviewed change rather than a dependabot automerge.

### 2. Placement — reusable modules in the published library

Grounded in the three layers the repo already has:

| layer | holds | scope |
| --- | --- | --- |
| `pulumi/library/go/pkg/<name>` | published, reusable primitives, each its own Go module, publicly mirrored | cross-project |
| `foundation/gcp-app-infra/business_unit_N/<env>` | the per-BU shared serverless space | BU-wide, foundation-owned |
| `<app>/infra/{build,identity,app}` | one app's composition | that app |

- **`pulumi/library/go/pkg/neon`** and **`pulumi/library/go/pkg/upstash`** — the
  reusable modules. This makes the library no longer strictly GCP; acceptable
  because it is named `pulumi-library` (not `gcp-library`) and its per-package
  module layout means GCP consumers pull nothing extra.
- **`tabula/infra/data`** — tabula's per-env composition: sizes, names, region,
  and writing the resulting connection strings into that env's Secret Manager as
  `TABULA_DATABASE_URL` / `TABULA_UPSTASH_REDIS_URL`.

**Not** `gcp-app-infra`: that is foundation-owned, BU-scoped, and GCP. Per-app
SaaS is app-specific — the same reasoning that put `tabula/infra/app` beside the
app.

## Build

1. `pkg/upstash` — vendored SDK + a component wrapping `RedisDatabase`
   (per-env name, region, eviction, TLS), exporting the connection URL as a
   **secret** output.
2. `pkg/neon` — vendored SDK + a component composing project → branch → database
   → role, exporting the connection string as a **secret** output.
3. `tabula/infra/data` — per-env stack composing both and writing the two secrets.
   Consumes the management keys already seeded in the infra-pipeline project.
4. `tabula-data-stack.yaml` + `infrastructure/gcp-identities.tsv` entries, so the
   stack applies through CI and never a laptop (§2.3).
5. Cutover, expand/contract per §2.15 — see below.

Outputs are marked secret so a connection string never lands in a plan diff or
CI log.

## Cutover (§2.15 expand → deploy → contract)

1. **Expand** — apply `tabula/infra/data` against the NEW accounts, creating the
   per-env Neon projects and Redis. Nothing points at them yet.
2. **Copy** — `pg_dump` / `pg_restore` per env, old → new. Dev first, verified,
   then nonprod, then prod.
3. **Deploy** — swap `TABULA_DATABASE_URL` / `TABULA_UPSTASH_REDIS_URL` to the new
   values and redeploy. Blue-green already protects the rollover; the old
   databases stay intact and are the rollback.
4. **Contract** — only after prod has soaked, delete the old projects and close
   the old accounts.

Never contract ahead of the rollover: until step 4 the old databases are the only
rollback path, exactly as the old dev Cloud Run service was during the bu2 move.

## Blockers

- **Upstash per-env Redis still needs a payment method.** The account caps the
  free tier at **one** database (`You cannot have more than 1 database(s)`), so
  until that is added the data stack can only manage a single shared instance —
  the isolation gap stays. Postgres is unaffected (already per-env).
- **The prod copy is a real data migration** with a write-freeze window, however
  short. Worth scheduling rather than doing opportunistically.

## Open question

Do the new accounts become the permanent home (assumed here), or should the old
Neon org be **transferred** instead? Neon supports org transfer, which would move
the existing projects wholesale and skip the dump/restore entirely — worth
checking before step 2, because it would make the riskiest step disappear.
