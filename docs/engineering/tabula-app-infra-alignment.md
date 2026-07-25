# Tabula → gcp-app-infra alignment status

> **Status: ✅ COMPLETE (2026-07-23).** tabula's Cloud Run workload runs through the
> `serverless_space` archetype in **all three** environments. The foundation
> `gcp-app-infra/business_unit_2` leaf owns and deploys each service; the app stack
> (`tabula/infra/app`) reconciles only the custom domain. Zero downtime — every service and
> custom domain served throughout (all on the shared `de662165` promoted digest).
> **Audience:** Anyone extending this pattern or auditing the cutover.

This tracked tabula's move onto the pattern in
[core-vs-application-infrastructure.md](core-vs-application-infrastructure.md) — the same move
oauth-user-inspector made in `business_unit_1`, applied to tabula in `business_unit_2`.

## 0. Cutover outcome (all three envs)

| env | leaf owns service | app stack | custom domain | serving |
|---|---|---|---|---|
| development   | ✅ `tabula-api-development`   | DomainMapping + Record only | tabula-api.dev.vitruviansoftware.dev     | ✅ |
| nonproduction | ✅ `tabula-api-nonproduction` | DomainMapping + Record only | tabula-api.staging.vitruviansoftware.dev | ✅ |
| production    | ✅ `tabula-api-production`    | DomainMapping + Record only | tabula-api.vitruviansoftware.dev         | ✅ |

The per-env §7 runbook that was actually executed — including the two non-obvious dependencies
(re-run `repo_config` after stage-4 so the app-deploy env gets `GCP_SERVICE_ACCOUNT`; the
`component: true` + `logicalName` import file to nest the service under the `pkg:index:CloudRun`
component; the token-free app-stack state-edit that keeps the domain resources clean) — is captured
in the session runbook. Landed via: stage-4 (#1078), repo_config (#1080), app-deploy per-BU
identity (#1081), leaf-no-stage4-deploy-SA fix (#1085), dev (#1083/#1088), nonprod (#1091/#1093),
prod (#1094/#1095), plus the migration-aware deploy and config-hash preflight (#1074).

The three blockers that were open when this doc was first written are all resolved: the revision
config-hash suffix (§3) landed in the leaf (#1064, byte-identical to the app stack); custom-domain
support stayed in the app stack (the leaf never needed it — the app stack keeps the DomainMapping +
Record post-cutover); the deploy-identity stayed app-owned (the leaf reads no stage-4 deploy SA,
#1085). The historical detail below is retained for context.

---

## 1. Done

**Stage-5 bu2 app-infra leaves (#1061).** `gcp-app-infra/business_unit_2/{development,
nonproduction,production}` now mirror the bu1 leaves: each instantiates `modules/serverless_space`
for tabula and ships **inert** (`tabula_workload_enabled: "false"`). The per-app config replicates
tabula's live Cloud Run service (base name `tabula-api`, runtime SA, `TABULA_` prefix, region
`us-central1`, max-instances 10, allUsers invoker, the plain env vars) so a future post-import
preview can be empty — **subject to the blocker in §3.**

A `gcp-app-infra-bu2-development` leg was added to `foundation-preview` so these leaves' `go
vet`/`go test` run in CI and a `pulumi preview` catches a mangled config key before deploy. The
`.gitignore` was fixed to track the bu2 stack configs (they were silently ignored).

`foundation-app-deploy` already accepts a `business_unit` input, so deploying these leaves needs no
workflow change.

---

## 2. Remaining deliberate operations

Neither is a fire-and-forget green PR; both adopt a **live** resource, which a Pulumi stack cannot
do just by declaring it. They follow the §7 model: a local `pulumi import` (the sanctioned
local exception to pipeline-only), then a flip via PR.

### 2.1 Stage-4 deploy-identity adoption

Unlike oauth — whose deploy identity is already minted in `gcp-projects` (bu1) via
`app_deploy_identity` (#999) — tabula's `tabula-deploy` and `tabula-rt` SAs are still minted by
`tabula/infra/identity`. To match the pattern, `gcp-projects/business_unit_2/<env>` must own them.

Because the SAs **already exist**, adding them to stage-4 and applying would fail
`already exists`. The move is therefore: `pulumi import` the existing SAs into the stage-4 bu2
stack → apply (empty diff) → remove from `tabula/infra/identity` with `retainOnDelete` +
`pulumi state delete`. This touches the identity the live tabula deploy pipeline impersonates, so
it is done deliberately, dev-first, verified between environments — not batched.

### 2.2 Workload cutover (§7)

Per env: import the running `tabula-api-<env>` service into the bu2 stage-5 leaf → confirm an
empty preview → flip `tabula_workload_enabled` to `true` → state-delete from `tabula/infra/app`.
**Blocked on §3.**

---

## 2a. Update — naming resolved, import tooling added, real blocker is custom domains

- **Revision naming (§3): RESOLVED (#1064).** The bu2 leaves now compute the config-hash suffix
  themselves (option 1 of §3, applied in the leaf not the shared archetype), byte-identical to
  tabula's app stack. No `serverless_space` change, no oauth impact.
- **Import tooling: ADDED (#1065).** `pulumi import` is now a bazel subcommand
  (`bazel run <project>:import -- …`), so the §7 adoptions run behind a target per principles §2.2.
- **⚠️ NEW hard blocker for BOTH apps: `serverless_space` has no custom-domain support.** The oauth
  bu1 dev cutover was **rolled back** for exactly this (#1060), and the archetype creates no
  DomainMapping / Cloudflare record. tabula serves on `tabula-api.*.vitruviansoftware.dev`
  (created today by `tabula/infra/app`), so cutting the workload onto the archetype as-is would
  **drop tabula's custom domains** — the same wall oauth hit. This is shared-archetype work another
  effort is actively on; adding domain support to `serverless_space` in parallel would collide, so
  tabula's cutover **waits on that capability landing**, then proceeds with the naming + import
  pieces already in place. This is the one genuine "coordinate with the other effort" dependency —
  the identity move and the naming were both resolvable in tabula's own lane.

## 3. ⚠️ Blocker: revision-name format mismatch (tabula-only) — RESOLVED in #1064, kept for context

`serverless_space` names revisions `<serviceName>-<revisionSuffix>`, i.e.
`tabula-api-development-<8 hex of digest>`. Its test `TestRevisionNameMatchesTheAppStackFormat`
pins exactly this (`oauth-user-inspector-development-abc12345`).

tabula's app stack names revisions `<serviceName>-<shortDigest>-<configHash>` (a 6-char sha256 of
the rendered env, added in the revision-name fix that stopped a `409 Revision ... with different
configuration already exists` when one promoted image carried different env across envs).

So the two formats **differ by the config-hash suffix**. On import + flip, the archetype computes a
revision name without that suffix, so the post-import preview is **not empty** — it wants to create
a differently-named revision. That breaks the §7 "adopt with an empty diff" property that makes the
oauth cutover safe. oauth is unaffected: its app stack uses the plain `<service>-<digest>` format
the archetype already matches.

### Options (a decision is needed before 2.2)

1. **Teach `serverless_space` the optional config-hash suffix.** Faithful, and the archetype stays
   the single source of the naming rule — but it edits the shared archetype the bu1/oauth cutover
   is actively using, so it must be coordinated with that work, not churned underneath it.
2. **Drop the config-hash from tabula's app stack.** Reintroduces the 409 the hash fixed, *unless*
   the archetype's per-invocation digest input means one image is never promoted with two different
   env sets — which is plausible under build-once/promote-by-digest but must be proven, with the
   regression test kept.
3. **Accept one revision churn at cutover.** Adopt the service, flip, and let the first archetype
   apply publish a new (archetype-format) revision and shift traffic to it — a normal blue-green
   deploy rather than a zero-diff adoption. Simplest; the cost is that the cutover is a deploy, not
   a silent takeover, so it must run through the blue-green smoke step like any release.

**Recommendation:** option 1 if the bu1 cutover has settled (one naming rule for every app is the
point of an archetype), otherwise option 3 for tabula now with option 1 as the follow-up. Option 2
only if the promote-by-digest invariant is proven and the 409 regression test survives.

---

## 4. Why this is where the autonomous work stopped

The scaffolding (§1) is additive and was merged green. Everything in §2–§3 either adopts a live
resource (so it is a deliberate credentialed op, not a green PR) or needs a design decision that
touches a shared archetype another effort is mid-cutover on. Rushing any of it would risk exactly
the "green after merge" guarantee the work is held to — a mis-sequenced identity move breaks
tabula's deploy pipeline, and an un-decided revision format turns the cutover into an unplanned
redeploy. Those are handed off here rather than forced.
