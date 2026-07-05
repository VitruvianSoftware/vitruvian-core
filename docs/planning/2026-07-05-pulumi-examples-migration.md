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

| example import | in-tree HEAD |
|---|---|
| `pkg/networking` | `pkg/network` |
| `pkg/project` | `pkg/project_factory` |
| `pkg/group` | `pkg/google_group` |
| `pkg/policy` | `pkg/org_policy` |
| `pkg/logging` | `pkg/centralized_logging` |
| `pkg/vpc_sc` | `pkg/vpc_service_controls` |
| `pkg/security` | `pkg/cai_monitoring` |
| `pkg/storage` (`libstorage`, `NewSimpleBucket`) | `pkg/cloud_storage` |

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
names. Mechanical repoint (`workspace:*` + catalog), mirroring PR1's TS side.

## Deferred (unchanged)

The examples' `replace => ../../../library/...` directives are monorepo-local; the standalone
`.github/workflows` are inert here and reference the old proxy setup. Reconciling them for the
one-way **Copybara** mirror-out (so the public repos stay buildable) is part of the deferred
mirror + **publish-origin** work.
