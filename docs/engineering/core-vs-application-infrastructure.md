# Core vs. Application Infrastructure

> **Status:** Authoritative standard for where infrastructure-as-code lives in this monorepo. The
> **archetype catalog** (§4) and the live `gcp-app-infra` stage it describes are **(target)** — the catalog
> exists today only in the ported example (`pulumi/examples/go-foundation/5-app-infra/modules/`); the live
> stage is not yet built. §7 tracks the open calls and the current-state deltas.
>
> **Audience:** Anyone adding infrastructure for an application, extending the foundation, or reviewing
> such a change.

---

## 1. Purpose

Every piece of infrastructure in this repo belongs in exactly one of three places. This doc says which,
and gives a rule that decides the ambiguous cases without a debate each time.

The short version:

- **Core infrastructure lives in the foundation.** It exists whether or not any given application does,
  and it is what *hands out* permission.
- **Application infrastructure lives next to the application that uses it.** It dies with the app and only
  *consumes* permission already granted.
- **Between them sits a catalog of application archetypes** — the sanctioned tech stacks, expressed as
  local modules in the foundation's app-infra stage. Apps pick an archetype rather than inventing a stack.

### Related docs

| Doc | Role |
|---|---|
| **Core vs. Application Infrastructure** (this doc) | *Where* a resource's IaC lives, and who owns it. |
| [Application Development Guiding Principles](application-development-principles.md) | *What good looks like* for an application overall — stack, build, deploy, secrets, observability. |
| [OSS App Onboarding Checklist](../oss-app-onboarding-checklist.md) | The *sequence* for standing a new app up end to end. |

---

## 2. The three layers

```
 ┌─────────────────────────────────────────────────────────────────────┐
 │ 1. CORE — infrastructure/pulumi/foundation/                         │
 │    gcp-bootstrap → gcp-org → gcp-environments → gcp-networks →      │
 │    gcp-projects                                                     │
 │    Org policies, folders, projects, enabled APIs, VPCs, KMS,        │
 │    log sinks, WIF pool, the infra-pipeline project + shared AR.     │
 └─────────────────────────────────────────────────────────────────────┘
                                   ▼  stack references / outputs
 ┌─────────────────────────────────────────────────────────────────────┐
 │ 2. ARCHETYPE CATALOG — foundation/gcp-app-infra/modules/  (target)  │
 │    env_base │ confidential_space │ serverless_space │ …             │
 │    The platform's blueprints: a sanctioned application type, wired  │
 │    to the core layer, instantiated per business unit per env.       │
 └─────────────────────────────────────────────────────────────────────┘
                                   ▼  archetype outputs
 ┌─────────────────────────────────────────────────────────────────────┐
 │ 3. APPLICATION — <app>/infra/                                       │
 │    The app's own resources: its service, datasets, topics, secrets, │
 │    DNS records, runtime identity. Ships in the app's PR.            │
 └─────────────────────────────────────────────────────────────────────┘
```

Layers 1 and 2 mirror upstream `terraform-example-foundation` (stages 0–4 and `5-app-infra`
respectively). **Layer 3 is our deliberate extension**: upstream keeps all application infrastructure
inside stage 5, whereas we let an application provision its own app-specific resources next to its code.
Everything else about the layout stays faithful to upstream — in particular, archetypes are **stage-local
modules** consumed via a `replace` directive, exactly like `foundation-4-projects/modules`, **not**
packages published to `pulumi/library/go/pkg/`.

---

## 3. The decision rule

Four tests, in priority order. The first that gives a clear answer wins.

| # | Test | Core | Application |
|---|---|---|---|
| 1 | **Lifecycle** — does it survive deleting the app? | Yes | No |
| 2 | **Cardinality** — one per org/env, or one per app? | Per org/env | Per app |
| 3 | **Blast radius** — can a bad change break a *second* app? | Yes | No |
| 4 | **Privilege** — does creating it *grant* power, or *consume* power already granted? | Grants | Consumes |

Test 4 is the one that does the real work:

> **An application may create its own identities and grant on resources it owns.
> Only the foundation may grant an identity power over resources the foundation owns.**

**Why:** if an app can widen its own permissions by editing its own repo, the review boundary and the
trust boundary have come apart — the app's reviewers become the de facto approvers of org-level access.
Keeping grants in the foundation means privilege changes are reviewed by the people accountable for the
org, under the foundation's gated environments.

**In practice:** an app freely creates its runtime service account and grants that SA `secretAccessor` on
its *own* secrets. It does **not** grant itself a role on the shared VPC, another team's dataset, or the
project itself — those bindings are authored in the foundation.

---

## 4. The archetype catalog

The catalog is how the platform keeps "core owns the permissions" from becoming a bottleneck.

An archetype is a local module in the app-infra stage that encodes one **sanctioned application type**:
the resources that type always needs, wired to the core layer, with the naming, IAM, and hardening
already decided. Today's catalog — in the ported example, pending the live stage:

| Archetype | Application type | Deploys |
|---|---|---|
| `env_base` | Base compute workload | Service account + Compute Instance on the shared-VPC subnet |
| `confidential_space` | Attested / confidential workload | Confidential Space VM, dedicated WIF pool + provider for attestation |
| `serverless_space` | Serverless HTTP service | Runtime SA, Cloud Run service from a promoted digest, `SECRET_PREFIX` partition, blue-green revision + traffic split, optional `allUsers` invoker |

`serverless_space` has no upstream counterpart — it is our serverless peer to `env_base`, and it is the
archetype `oauth-user-inspector` fits today.

### Why this answers the friction problem

Without a catalog, "my app needs BigQuery" is a bespoke foundation PR each time, and the app team waits.
With one, the question becomes **which archetype covers this**, and there are only three answers:

1. **An existing archetype already covers it** — instantiate it. No foundation change; the app ships.
2. **An existing archetype nearly covers it** — extend that archetype once, and *every* app of that type
   gains the capability. The cost is paid a single time, by the platform, deliberately.
3. **Nothing covers it** — that is a genuinely new application type, and it *should* be a deliberate
   platform decision with a design conversation, not a one-off grant bolted onto one app's stack.

The catalog converts recurring per-app friction into a one-time platform decision. That is the point of
upstream's module layout, and the reason archetypes stay stage-local: they are the platform's opinion
about how applications are built here, versioned with the foundation that supports them.

### Adding to the catalog

A new archetype is a maintainer-approved change. It must state the application type it serves, the core
resources it depends on (by stack reference, never by hardcoded ID), the IAM it grants and why that is
the least privilege for the type, and at minimum one real app that will consume it. An archetype with no
consumer is documentation, not platform — the current `serverless_space` situation, which §7 tracks.

---

## 5. Core infrastructure — the list

Lives in `infrastructure/pulumi/foundation/`. Deployed by the foundation's service accounts through
env-gated CI workflows.

| Resource | Owning stage |
|---|---|
| Org policies; the DRS override (`constraints/iam.allowedPolicyMemberDomains`) | `gcp-org` |
| Folders; tag keys, values, and bindings | `gcp-environments` |
| **Projects themselves**, including the `prj-{env}-bu1-oss-floating` app hosts | `gcp-projects` |
| **Service/API enablement** on a project (`run`, `secretmanager`, `bigquery`, …) | `gcp-projects` (`base_env`) |
| Shared VPC + subnets, firewall policies, peering, interconnect, VPN, transitivity | `gcp-networks` |
| KMS key rings and crypto keys (the CMEK an app's data sits under) | `gcp-projects` |
| Log sinks, centralized logging, CAI monitoring, VPC-SC perimeters | `gcp-org` |
| The infra-pipeline project and the shared Artifact Registry (build-once home) | `gcp-projects` (`infra_pipelines`) |
| The WIF pool and provider (`foundation-pool`) — the CI trust anchor | `gcp-bootstrap` |
| Billing budgets | `gcp-projects` |

Note the pattern: **enabling a service is core; using it is not.** `bigquery.googleapis.com` on the
project is core. The datasets are the app's.

---

## 6. Application infrastructure — the list

Lives in `<app>/infra/`, ships in the app's own PR, deployed by the app's deploy SA via WIF.

| Resource | Example |
|---|---|
| The workload itself — Cloud Run service, revisions, traffic split | `oauth-user-inspector/infra/app` |
| IAM on resources the app owns — e.g. `allUsers` invoker on *its own* service | `oauth-user-inspector/infra/app` |
| Custom domain mapping and the DNS record that points at it | `oauth-user-inspector/infra/app` |
| The app's **runtime** service account | `oauth-user-inspector/infra/identity` (`oauth-user-inspector-rt`) |
| Secret Manager **secrets** the app owns, and accessor bindings on those secrets | `infrastructure/pulumi/apps/tabula` |
| BigQuery **datasets/tables/views**, Pub/Sub topics and subscriptions, app-owned buckets | — |
| App-level alerts, SLOs, dashboards | — |
| Identity-provider application registrations (e.g. a Zitadel OIDC app) | `infrastructure/pulumi/platform/zitadel-apps` |

Secret **values** are never in IaC in any layer — the app declares the container; the value arrives
through the pipeline's secret injection.

---

## 7. Open calls and current-state deltas

Four boundary cases are **not yet ruled on**. Two of them describe code that exists today and would move
under the rule in §3. Nothing here should be treated as settled.

| # | Case | Current state | Proposal |
|---|---|---|---|
| 1 | **Deploy service account** | `oauth-user-inspector/infra/identity` creates `oauth-user-inspector-deploy` *and* its project-level grants — the app granting itself power over a project it does not own. | Move creation + grants to the foundation; the app consumes the SA email by stack reference. Fails test 4 as written. |
| 2 | **Per-app Artifact Registry repo** | Lives in the shared infra-pipeline project (core), created outside the foundation. | Foundation declares the repo (naming, retention, immutable tags); the app only pushes to it. |
| 3 | **Secret containers** | Inconsistent — `tabula` creates its own secrets, while `oauth-user-inspector/infra/identity` notes that `secretmanager.secrets.CREATE` runs as the folder-scoped `sa-terraform-proj`. | App owns containers in its own project; values stay out of IaC. Pick one and make both apps match. |
| 4 | **Databases** | Not yet exercised on this split. | Instance/cluster is core; database and schema are the app's. |

Structural deltas, tracked separately:

- **The live `gcp-app-infra` stage does not exist.** `infrastructure/pulumi/foundation/` stops at
  `gcp-projects`. The catalog in §4 is therefore example-only today.
- **`serverless_space` has no live consumer.** `oauth-user-inspector/infra/app` re-implements the
  archetype's shape by hand against `pkg/cloud_run` — runtime SA, `SECRET_PREFIX`, blue-green traffic
  split, and the optional public invoker all exist in both places and are free to drift. The app has
  since grown custom-domain support the archetype does not have.
- The earlier design decision that there would be "no separate stage-5 tree"
  (`docs/superpowers/specs/2026-07-10-oss-application-stage-design.md` §4.1) predates this doc. Where the
  two conflict, this doc states the intended target and that spec records why the current state differs.
