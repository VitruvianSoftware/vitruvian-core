# Deployment strategy

**Applies to every deployable in this monorepo** — apps (oauth-user-inspector,
tabula, …) and the foundation stacks. One model, so "is it in production?"
always has the same answer shape.

## The rule

| Trigger | Deploys to |
| --- | --- |
| Merge to `main` | **development** only |
| The component's **release-please PR merges** (a release is cut) | **nonproduction → production** |
| `workflow_dispatch` | one chosen unit into one chosen environment (break-glass) |

Development is the continuous-integration surface: every merge lands there.
Promotion beyond development is gated on **cutting a release** — merging the
release-please PR for that component. A bare merge never touches nonprod or prod.

## Why release-please is the gate

Merging a component's release-please PR is already a deliberate, reviewable act:
it bumps the version and publishes the curated changelog. Keying promotion off
that same act means the deployed version is always tied to a semver + changelog
entry — auditable, and decoupled from merge frequency. The foundation stacks
have worked this way from the start (`foundation-release.yaml` gates its deploy
jobs on `release_created`); this document is that pattern made repo-wide.

## Mechanism

- **Apps** trigger promotion on the GitHub **Release** event, filtered to the
  component's tag (e.g. `oauth-user-inspector-v*`). release-please
  (`apps-release.yml`, `tabula-release.yml`) publishes the release when the PR
  merges; that fires the generated `delivery.yaml`'s nonprod→prod rungs for
  the unit whose tag prefix matches.
- **Foundation** gates its in-line deploy jobs on the release-please action's
  `release_created` output in the same run.

Either way the signal is "a release was cut", never "a commit landed".

### Why the `on: release` trigger fires (and when it wouldn't)

release-please publishes the GitHub Release using a **GitHub App installation
token** (`apps-release.yml` / `tabula-release.yml` mint one via
`create-github-app-token`), not the workflow's `GITHUB_TOKEN`. GitHub suppresses
downstream workflow runs only for events raised by `GITHUB_TOKEN`; events raised
by an App/PAT token **do** trigger workflows. So the published release fires the
deploy workflow's `on: release` promotion. If a component's releases were ever
switched to `GITHUB_TOKEN`, or `skip-github-release` were set in its
release-please config, promotion would silently stop — that is the one wire to
check first if a release lands but nonprod/prod do not move.

**Fallback / break-glass.** The failure mode is benign: no auto-promotion, never
a broken deploy. Promote any single environment directly with
`.github/workflows/delivery.yaml`'s `workflow_dispatch` — it takes a `unit`, an
`environment` and an `allow-unsoaked` override, so one dispatch delivers exactly
one thing — whenever the release path is unavailable or you need an
out-of-band deploy. (Before the delivery orchestrator each app had its own
dispatch; those per-app workflows are gone.)

> First-run note: `oauth-user-inspector-v*` releases are already published in
> this repo, so oauth's `on: release` path is exercised. tabula has not merged a
> `tabula-api` release under this flow yet — confirm the **first** tabula-api
> release auto-promotes (or dispatch it) rather than assuming it.

## Ladder and gates

Even though one release event triggers both, **nonproduction deploys first and
prod is laddered behind its success** — nonprod still smoke-gates prod within the
release.

Environment reviewers (managed as code in `repo_config`):

- **nonproduction** — protected-branch policy, **no reviewer**. The release-PR
  merge is the human gate; a second per-deploy approval would only reintroduce
  the fatigue this model removes.
- **production** — protected-branch policy **and** a required reviewer: the one
  deliberate checkpoint before prod.

## Build once, promote by digest

A release-please PR is version-bump + changelog only, so the release commit is
code-identical to what already soaked on development. The deploy run builds the
image once and promotes that single immutable `@sha256` digest across
nonprod+prod — nothing is rebuilt per environment, and prod runs the exact
artifact nonprod smoke-tested.

## Consequences to keep in mind

- **nonprod/prod lag `main`** between releases — they are no longer continuous
  mirrors of dev. That is the point of release-gating, but it means "is X in
  prod?" is "was X in a merged release?", not "is X on main?".
- **Hotfixes** cut a release like anything else (release-please will open a
  patch PR immediately). For a genuine emergency that cannot wait, `delivery.yaml`'s
  `workflow_dispatch` redeploys a single unit + environment directly.
- **Releasing is not the same as publishing.** This page covers the *deploy*
  half — release-please cuts a release and the artifact rolls to Cloud Run. The
  library and MCP packages additionally **publish to npm**, from the exported
  mirrors rather than from here, and that half has its own failure modes and its
  own auth model (OIDC, no token). See
  [npm trusted publishing](npm-trusted-publishing.md). A release can succeed
  here while nothing reaches the registry — that went unnoticed for three months
  and is why `bazel run //tools/npm-publish-audit:check` exists.
- **Two Pulumi deploys cannot overlap.** Our Pulumi Cloud individual account
  allows one update account-wide, so an unrelated stack's deploy can reject
  this one with a 409. `tools/pulumi/pulumi_cmd.sh` retries that specific error;
  see [Pulumi concurrent updates](pulumi-concurrent-updates.md) for why it cost
  a production promotion and what the root fix is.
