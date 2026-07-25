# pulumi foundation examples → monorepo migration (PR2/PR3)

Status: follow-on to the library migration (PR #586). Date: 2026-07-05.

## Context

With `pulumi-library` in-tree (`pulumi/library/`), the two reference foundation examples move in
next so they **consume the in-tree library** rather than published packages. PR2 is the **go**
example (`pulumi/examples/go-foundation/`); PR3 is the **ts** example.

## PR2 — go-example-foundation

History-preserving graft into `pulumi/examples/go-foundation/` (54 commits preserved).

**Library drift ported.** The example was pinned to the library at **v0.4.0 (pre-rename)**. HEAD has
the `feat!: rename Go library packages…` refactor, so the example's imports had to be repointed:

| example import                                  | in-tree HEAD               |
| ----------------------------------------------- | -------------------------- |
| `pkg/networking`                                | `pkg/network`              |
| `pkg/project`                                   | `pkg/project_factory`      |
| `pkg/group`                                     | `pkg/google_group`         |
| `pkg/policy`                                    | `pkg/org_policy`           |
| `pkg/logging`                                   | `pkg/centralized_logging`  |
| `pkg/vpc_sc`                                    | `pkg/vpc_service_controls` |
| `pkg/security`                                  | `pkg/cai_monitoring`       |
| `pkg/storage` (`libstorage`, `NewSimpleBucket`) | `pkg/cloud_storage`        |

Repointing is done by **import aliasing** — the import path changes, the local qualifier (and every
call site) stays — so no scattered `storage.`→ edits that would corrupt e.g. `roles/storage.admin`
strings. The bare `storage.NewBucket`/`BucketArgs` calls were always the **gcp provider**
(`gcp/storage`), not the library, so they were untouched. Net: no true API break to adapt.

**In-tree resolution.** Each stage `go.mod` gets `replace <lib pkg> => ../../../library/go/pkg/<name>`
(+ a root `…/go` replace for the packages' test-util); the example's own `go.work` is deleted. Stages
stay **out of `//:go.work`** and are **gazelle-excluded** — the `infrastructure/pulumi` convention.

**Bazel**: a `pulumi_project(name, dir)` BUILD per stage (`//tools/pulumi:defs.bzl`) →
`bazel run //pulumi/examples/go-foundation/<stage>:preview|up|…`.

**Verified natively**: `go build ./...` + `go test ./...` pass across all 8 modules (7 stages +
`helpers/iam-validate`) with the in-tree library. **e2e (real GCP org deploy) is not verifiable
here** — flagged.

**Gates**: `pulumi/examples/**` added to the license Apache-2.0 exemption + `.prettierignore`;
gofumpt/prettier/buildifier clean; dependabot gomod coverage added; `/pulumi/` CODEOWNERS already
covers it.

## PR3 — ts-example-foundation

**No rename drift** — the example's `@vitruviansoftware/foundation-*` deps all match HEAD package
names, so it's a repoint rather than a port.

Structural note: the `foundation-*` deps live only in the **root** `package.json` (stages consume
them via hoisting), and 19 of the per-env `package.json` files share the name `"0-bootstrap"` — so
they can't all be pnpm workspace members. Approach:

- Register **only the root** `pulumi/examples/ts-foundation` as the pnpm workspace member; convert its
  `foundation-*` deps to `workspace:*` so they resolve in-tree (verified: node_modules links
  `foundation-network → ../../../../library/ts/packages/network`). The per-env Pulumi project dirs
  share this hoisted install.
- Keep concrete `@pulumi/*` ranges and add `pulumi/examples/ts-foundation` to `CATALOG_EXEMPT` — a
  fork-and-own reference builds standalone when forked, so `catalog:` would break it (same class as
  `oauth-user-inspector` / the go example's `policy-library`).
- `pulumi_project` BUILD per Pulumi project (20 `envs/*`/stage dirs); regenerate `pnpm-lock.yaml`;
  align the go helper's go directive (1.26.2) and the bootstrap Dockerfile (node 22) to canonical.
- Format-clean (prettier/buildifier/shfmt); `pulumi/examples` is already gazelle-excluded and
  license-exempt (PR2). Conformance passes locally (0 fail).

## Deferred → now specified: one-way mirror-out + publish origin

Development has shifted to the monorepo (code is on `main`, edited there). The remaining
public-facing plumbing — one-way **Copybara** mirror-out of the three subtrees + the **publish
origin** — is captured as an execution-ready runbook in
[`docs/copybara-pulumi-oneway-cutover.md`](../copybara/copybara-pulumi-oneway-cutover.md).

Landed in-repo with that runbook: a backward-compatible `copy.bara.sky` generalization
(`subtree`≠`repo`, `export_only`, `export_transformations`) + the **library** export mirror
(`export_pulumi_library`, with `catalog:`→concrete transforms), a config-load smoke-test guardrail,
the library sync-auth entry, and the `apps-release` trigger fix (monorepo = library publish origin
via release-please → mirror publish-on-version-bump).

Gated next step: the two **example** mirrors are blocked on the _first library publish_ — the go
example's stage `go.mod`s carry zero pseudo-versions (`v0.0.0-0001…`) resolvable only via the
monorepo-local `replace` directives, and the ts example's `foundation-*` deps are `workspace:*`, so
neither builds standalone until a real published library version exists. The runbook specifies their
`export_transformations` (strip `replace` + repoint to `${LIBRARY_VERSION}`; `workspace:*` →
`^${LIBRARY_VERSION}`) to apply once the library publishes. e2e (real GCP org deploy) remains flagged.
