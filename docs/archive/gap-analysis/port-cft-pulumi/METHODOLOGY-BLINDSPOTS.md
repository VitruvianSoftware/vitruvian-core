# Foundation Audit — Methodology Blind Spots ("what should have been compared")

The original gap analysis ([`GAPREPORT.md`](GAPREPORT.md)) and its
[re-verification](REVERIFICATION-2026-07-24.md) compared **example-port code vs
Terraform** — functional and structural fidelity. That surface is now triple-checked
(example-vs-TF, library parity, stub sweeps) and is in reasonable shape.

But the `us-south1` secondary-region drift — a wrong value that was *silently valid*,
duplicated per-stage, and found only because someone asked to look at the region
consumption chain — proved the real risk lives in **values and wiring**, on planes the
functional audit never touched. This doc records the dimensions that were **never
compared**, so future audits close them instead of rediscovering landmines by accident.

## Meta-lesson: run the audit against the DEPLOYED ref, with absolute paths

Before the findings, the process lesson (learned the hard way — two of three re-run
attempts were contaminated):

- **Compare against `origin/main` (the deployed ref), not a local checkout.** The main
  working tree was 28 commits stale; finder agents defaulted to **relative-path** greps
  against their (stale) cwd and manufactured already-fixed "critical" findings (the
  region drift, a 5-app-infra compile error) that had merged days earlier. Reset the
  tree to the deployed commit, or point every agent at an absolute path rooted at it,
  and **verify the agent read the intended tree** (spot-check one known-fixed value).
- A "finding" on a path that changed since the audit ran is worthless until reconciled
  against the deployed ref. Budget for that reconciliation.

## The dimensions never compared

| # | Dimension | Why it hides landmines | Status |
|---|---|---|---|
| 1 | **CI/CD variable surface** (repo_config Actions vars + GitHub Environments) | Deploy region/project/identity live here, outside every Pulumi yaml; `\|\| 'us-central1'` fallbacks mask a missing/wrong var | **audited 2026-07-24** ([results below](#cicd-variable-surface-audit-blind-spot-1)) |
| 2 | **Guard/test coverage-surface** — does each guard read the DEPLOYED layer? | A green regression test can pass on the broken state if it asserts the wrong layer (code default vs committed yaml vs Environment var vs live resource) | one instance fixed (#1128); **class open** |
| 3 | **Cross-stack StackReference contract** (producer output-set vs consumer read-set) | Outputs read by string key across stage boundaries; a renamed/dropped/conditionally-omitted output silently yields empty string or a deploy failure | open |
| 4 | **Pulumi STATE vs code drift** on adopted/imported resources | The live foundation was built via import + direct state edits + `retainOnDelete`/`ignoreChanges`; state can hold attributes the code doesn't represent | open |
| 5 | **Deploy-time ORDERING / replace-race** | Ordering is encoded in prose + config, not `dependsOn`; a force-new replace with `deletion_protection` on a dependent deletes-then-fails, half-applied | open (partly realized — see the CIDR create-before-delete incident) |
| 6 | **Org-policy / flag EFFECT vs declaration** (silently-inert keys) | The code may read a config key the yaml never sets under that name → the flag no-ops silently (the SCC key case) | one instance fixed (#1128); **class open** |
| 7 | **Upstream changes AFTER the ports' last sync** (post-`ed07500` / 2026-05-06) | Every finding was measured against a frozen baseline; anything upstream fixed since is outside the comparison by construction | open (one-time delta, cheap) |
| 8 | **Live-config-drift coverage is itself incomplete** | The new value-drift dimension ran on only 4 of 7 live stacks; `gcp-environments`, `org-folders`, and the full 8-yaml `gcp-projects` BU matrix were under-sampled | open |

### 1. CI/CD variable surface — the most likely home of the next drift

Deploy behaviour is driven by GitHub Actions **variables** repo_config provisions per
Environment (`GCP_REGION`, `GCP_PROJECT_ID`, `GCP_(DEPLOY_)SERVICE_ACCOUNT`,
`GCP_WORKLOAD_IDENTITY_PROVIDER`). These never appear in a stack yaml and were never
compared to what the stacks/workflows assume. Worse, workflows use
`${{ vars.GCP_REGION || 'us-central1' }}` — a **missing** var silently resolves to a
default instead of failing. That is the `us-south1` split exactly, one plane over: the
deploy + AR docker path retargets `us-central1` while the app-infra stack provisions the
AR repo in the intended region.

**How to check:** enumerate every `vars.*`/`secrets.*` in `.github/workflows/*`; diff
against what `repo_config/main.go` declares (`NewActionsVariable` /
`NewActionsEnvironmentVariable`) per Environment. Flag (a) any var read but not declared
(relies on the `||` fallback), (b) any Environment whose `GCP_REGION`/`GCP_PROJECT_ID`
disagrees with the matching stack, (c) SA/WIF name mismatches.

### 2. Guard/test coverage-surface mismatch

The [major] networks finding is the template: `config_test` validated the code-level
region *default*, but the value that deploys is the committed `Pulumi.production.yaml`
override the test never loads — so the guard that "closed" the original landmine did not
cover the file that caused it. **Fixed for networks in #1128**, but the **class is open**:
for every "we added a test / it's fixed" claim, confirm the guard reads the *same layer
that reaches production*, and prove it FAILS when that layer is mutated to the bad value.

### 3. Cross-stack StackReference contract

Consumers read producer outputs by string key (`GetStringOutput("wif_pool_name")`,
`"access_context_manager_policy_id"`, `fmt.Sprintf("%s_network_project_id")`). Nothing
type-checks these across the boundary. If a producer renames/drops/conditionally-omits
an output, the consumer gets `""` or a deploy failure no single-stack test catches.
**Check:** per stage boundary, diff the set of `ctx.Export` keys a producer emits against
the `GetOutput` keys consumers read; flag any consumed key not *unconditionally* exported
(e.g. an output gated behind a config flag whose default changed — ACM policy, SCC).

### 4. Pulumi state vs code drift

Every dimension so far reads code (or committed yaml); **none reads the actual Pulumi
state.** The live foundation was adopted via import + direct state edits with
`retainOnDelete`/`ignoreChanges`, so state can hold attributes the code doesn't represent,
and `ignoreChanges` masks real divergence. **Check:** per stack, read-only `pulumi stack
export` (or `preview --diff` in a scratch copy); enumerate every
`ignoreChanges`/`retainOnDelete`/`deletion_protection` and confirm the ignored attribute
isn't hiding drift; flag any in-state resource with no code declaration (orphan adoption).

### 5. Deploy-time ordering / replace-race

Ordering is partly prose + config, not `dependsOn` (gcp-projects `config.go` literally
comments "the shared leaf applies BEFORE this … are config rather than a StackReference").
This class is **already partly realized**: the region correction to the networks subnets
was a force-new replace that, because it reused the same CIDR, hit a create-before-delete
conflict and had to be unblocked by deleting the old subnets first. **Check:** per stack,
map the dependency graph; find replace-triggering changes (region, name, force-new fields)
that lack create-before-delete or a guarding `dependsOn`; confirm the cross-stage order is
enforced by the pipeline/StackReference, not just a comment.

### 6. Org-policy / flag effect vs declaration

Declaration ≠ effect. The SCC case: live read `enable_scc_resources` while the yaml/example
key is `enable_scc_resources_in_pulumi` → read as unset → feature silently no-ops (same
failure mode as [Helm dropping unknown keys](../../../..)). **Fixed for SCC in #1128**; class
open. **Check:** diff the exact config-key STRINGS the code reads (`cfg.Get/Require`) against
the keys present in each committed yaml — any yaml key never read (or read under a different
name) is inert. For org policies/SCC/ACM, verify enforced *effect*, not just declaration.

### 7. Upstream drift after the last port sync

Everything was measured against `ed07500` (2026-07-01); the ports last synced ~2026-05-06.
Anything upstream fixed/added since is outside the comparison — the port can be a faithful
copy of a now-stale upstream and still be wrong vs current best practice. **Check (cheap,
one-time):** `git diff ed07500..<latest-tag>` restricted to the covered stage dirs; triage
each changed default/resource for security/correctness; decide port-forward vs documented
divergence.

### 8. Live-config-drift coverage is incomplete

The value-drift dimension only produced findings for bootstrap/org/networks/app-infra.
`gcp-environments` (3 yamls), `org-folders`, and the full `gcp-projects` per-BU matrix (8
yamls) were under-sampled — and the `us-south1` bug lived in exactly that kind of per-env
value. **Check:** diff EVERY committed `Pulumi.<env>.yaml` value against (a) the example
port's expected value and (b) its sibling envs — a per-env value differing from its
siblings without a documented reason is the drift signature.

## Residual risk (from the completeness critic)

> Moderate confidence that the functional/structural port is faithful. **Low confidence
> that all value/wiring landmines are found.** The remaining landmines cluster in three
> surfaces none of the passes fully covered: (1) the **CI/CD variable plane** —
> repo_config-managed Environment vars with silent `|| default` fallbacks, the most likely
> home of the next region/identity split; (2) **Pulumi state** on adopted/imported resources
> — code+yaml review cannot see attributes that live only in state or are masked by
> `ignoreChanges`; (3) the **un-sampled corners** of the live-config dimension itself.

## <a name="cicd-variable-surface-audit-blind-spot-1"></a>CI/CD variable-surface audit (blind spot #1)

Ran the dimension-1 audit (`scratchpad/audit/cicd-var-surface.js`: a finder per
app/domain — oauth, tabula, foundation — diffing every `vars.*`/`secrets.*` consumed in
the workflows against what `repo_config` declares, then adversarial verify). **12 findings,
3 confirmed, 9 refuted.**

**The headline is reassuring: no ACTIVE value drift.** Every declared `GCP_REGION`,
`GCP_PROJECT_ID`, deploy-SA and WIF-provider value is correct — the oauth/networks/repo_config
region-consistency work aligned them. Notably the `${{ vars.GCP_REGION || 'us-central1' }}`
fallbacks (`tabula-deploy.yaml:148`, `oauth-user-inspector-deploy.yaml:149`,
`_deploy-cloud-run.yaml:209`) were **refuted as a live bug**: the values behind them are
correct, so nothing is mis-deploying. The next `us-south1` is **not** sitting here today.
(The fallback fragility is still worth removing — a missing var would default silently rather
than fail — but it is a hardening, not a defect.)

The **3 confirmed** findings are doc/hygiene traps whose danger is that they *invite* a future
drift of exactly the class we care about:

1. **[fixed here] Stale reusable-workflow comment claims oauth-user-inspector lives in
   us-west1** (`_deploy-cloud-run.yaml:88-95` — the only `us-west1` string in all of
   `.github/workflows/`). oauth is `us-central1` everywhere (app stack default, all 3 env
   configs, the build target, the app-infra leaf's inherited `default_region`, and repo_config's
   declared `GCP_REGION`); `us-west1` is the fleet's *secondary* region. The comment conflated
   them. **This is the sharpest landmine of the audit** — it literally invites someone to
   "reconcile" `repo_config`'s `GCP_REGION` to `us-west1` to match, which would relocate the
   Artifact Registry push and the DomainMapping and break the deploy (the `us-south1` hazard).
   → **comment corrected to `us-central1` in this PR.**
2. **[fixed here] repo_config godoc example names `GCP_SERVICE_ACCOUNT` for tabula**, but the
   tabula workflows read `GCP_DEPLOY_SERVICE_ACCOUNT` (and the yaml correctly declares that).
   No live bug, but a naming trap: an editor following the stale example would declare an unread
   `GCP_SERVICE_ACCOUNT` while `GCP_DEPLOY_SERVICE_ACCOUNT` goes missing. → **docstring corrected
   in this PR.** (Unlike region, the SA has no `|| default`, so this would fail *loudly* at auth —
   which is why it's info, not a silent landmine.)
3. **Declared-but-unread `GCP_PROJECT_ID` on every foundation Environment** (all set to the seed
   project `prj-b-seed-c010`), consumed by no foundation workflow — dead config. Latent hazard:
   the stage-5 loop copies the foundation-proj var map (incl. `GCP_PROJECT_ID=<seed>`) into every
   `foundation-app-<env>` Environment; if a future stage-5 step ever reads `vars.GCP_PROJECT_ID`
   it would target the *seed* project, not the env's oss-floating app project. **Left as a
   documented finding** (removing it touches repo_config's stage-5 var logic; currently inert).

**Also noted (info, refuted-as-not-urgent):** `foundation-app-preview` (ungated, PR-triggered)
authenticates as the privileged `sa-terraform-proj`; read-only `pulumi preview`, but the one
place an untrusted PR touches a privileged identity — worth a later least-privilege pass.

**Verdict on blind spot #1:** the highest-residual-risk plane is **clean on values today**.
The real risks are (a) the *documentation* traps that could induce a drift (2 fixed here), and
(b) the *fragility* of silent `|| default` region fallbacks (recommended hardening). The class
that produced `us-south1` is now audited on the CI plane and found not active.
