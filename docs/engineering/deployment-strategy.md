# Deployment strategy

**Applies to every deployable in this monorepo** — apps (oauth-user-inspector,
tabula, …) and the foundation stacks. One model, so "is it in production?"
always has the same answer shape.

## The rule

| Trigger | Deploys to |
| --- | --- |
| Merge to `main` | **development** only |
| The component's **release-please PR merges** (a release is cut) | **nonproduction → production** |
| `workflow_dispatch` | a single chosen environment (break-glass) |

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
  merges; that fires the deploy workflow's nonprod→prod ladder.
- **Foundation** gates its in-line deploy jobs on the release-please action's
  `release_created` output in the same run.

Either way the signal is "a release was cut", never "a commit landed".

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
  patch PR immediately). For a genuine emergency that cannot wait, `workflow_dispatch`
  redeploys a single environment directly.
