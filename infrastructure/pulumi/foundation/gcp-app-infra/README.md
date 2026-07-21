# gcp-app-infra (foundation stage 5)

Live counterpart of upstream `terraform-example-foundation` `5-app-infra`, and of the ported example
at `pulumi/examples/go-foundation/5-app-infra`.

## What this stage owns

Application infrastructure that belongs to the **platform** — see
[Core vs. Application Infrastructure](../../../../docs/engineering/core-vs-application-infrastructure.md).

Today that is the **platform-issued deploy identity**: one deploy service account per app per
environment, its project-level grants, and the WIF binding its GitHub Environment impersonates. An
application may create as many service accounts of its own as it likes; only the foundation may grant
an identity power over a project the app does not own (§4.1).

## Layout

```
modules/                        stage-local modules (module foundation-app-infra/modules)
  app_deploy_identity/          platform-issued deploy SA + grants + WIF binding
  serverless_space/             Cloud Run archetype (ported; not yet instantiated — see below)
business_unit_1/
  development/                  thin leaf, env pinned in main.go, single `production` stack
  nonproduction/
  production/
```

Modules are **stage-local** and consumed via `replace foundation-app-infra/modules => ../../modules`,
exactly as `foundation-4-projects/modules` is. They are deliberately *not* published to
`pulumi/library/go/pkg/` — that would break fidelity with upstream's local-module convention.

There is **no `shared` leaf**; upstream `5-app-infra` has none.

## `serverless_space` is not yet instantiated

The Cloud Run archetype is ported and compiled here, but no app is wired through it yet.
`oauth-user-inspector`'s Cloud Run service is still deployed by `oauth-user-inspector/infra/app`.
Moving it adopts a live, traffic-serving service and is deliberately a separate change so it can be
reverted on its own.

## Deploy

Never `pulumi up` locally. Each leaf deploys through `.github/workflows/foundation-app-deploy.yaml`
against the `foundation-app-<env>` GitHub Environment (dev auto-deploys; nonprod and prod require
reviewers), chained from `foundation-release.yaml` after the stage-4 ladder.

```bash
# PR preview of the representative leaf
bazel run //infrastructure/pulumi/foundation/gcp-app-infra/business_unit_1/development:preview
```

## Ordering

This stage consumes the stage-4 BU leaf (`oss_floating_project`) and `gcp-bootstrap`
(`wif_pool_name`), so a leaf cannot apply before its stage-4 counterpart. The `foundation-app-*` WIF
bindings live in `gcp-bootstrap`'s `build_github.go` and must be applied before the first deploy can
authenticate.
