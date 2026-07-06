# pulumi → one-way Copybara mirror-out + publish origin (cutover runbook)

Status: in progress. Date: 2026-07-05. Follows the pulumi migration PRs (#586 library,
#590 go-example, #595 ts-example — all merged to `main`).

## Goal

Make **vitruvian-core the single source of truth** for the three migrated pulumi trees so
development happens in the monorepo, and mirror each subtree **one-way** back out to its existing
public repo (read-only mirror), continuing to publish the library's Go modules + `foundation-*` npm
packages. This mirrors the established internal-first pattern (`docs/copybara-devx-oneway-cutover.md`).

| monorepo subtree                 | public mirror (repo)                             | shape       | publishes         |
| -------------------------------- | ------------------------------------------------ | ----------- | ----------------- |
| `pulumi/library/`                | `VitruvianSoftware/pulumi-library`               | export-only | Go tags + npm     |
| `pulumi/examples/go-foundation/` | `VitruvianSoftware/pulumi_go-example-foundation` | export-only | no (fork-and-own) |
| `pulumi/examples/ts-foundation/` | `VitruvianSoftware/pulumi_ts-example-foundation` | export-only | no (fork-and-own) |

**Development has already shifted** — the code is on `main` and is edited there now. This runbook
covers the remaining _public-facing_ plumbing (mirror-out + publishing), which is a live-operator
cutover (needs Copybara/Bazel + publish credentials + standalone-repo admin that CI/an operator hold,
not this sandbox).

## Publish-origin decision (locked)

**Publish from the monorepo, tag/publish on the mirror.** release-please runs in vitruvian-core
(`.github/workflows/apps-release.yml`, matrix leg `pulumi/library`, config
`pulumi/library/release-please-config.json`) and authors the version-bump + changelog PR. On merge,
the bumped `.release-please-manifest.json` + `CHANGELOG.md` export to the mirror via
`export_pulumi_library`; the **mirror's** publish-on-version-bump workflow tags the exported commit
(Go module tags + `npm publish`) with the mirror's existing tokens. This is the same
single-writable-copy model devx/homelab use — no duplicate release automation, no two-writable-copies
drift. The two examples are **fork-and-own references** and do not publish.

## What is DONE in-repo (this change)

- **`tools/copybara/copy.bara.sky`** — generalized (backward-compatible): components may now set
  `subtree` (monorepo path) ≠ `repo` (standalone name), `export_only` (emit only `export_<repo>`, no
  import path), `origin_only_exclude`, and `export_transformations`. Existing components (where
  name == subtree == repo) are byte-for-byte unchanged. Added the **`pulumi-library`** export-only
  component with `catalog:`→concrete transforms (see below) and a `standalone_only` set.
- **`.github/workflows/copybara-export-pulumi-library.yaml`** — thin export caller (push on
  `pulumi/library/**` + `workflow_dispatch`), keyed to `PULUMI_LIBRARY_SYNC_SSH_KEY`.
- **`.github/workflows/copybara-config-smoketest.yaml`** — NEW guardrail: `copybara validate`s the
  whole config on the pinned image for any PR touching the copybara tooling, so a config load error
  (which would break **all** components' exports) is a red check, not a silent breakage. **Make this a
  required merge-queue check.**
- **`infrastructure/pulumi/pkg/copybara_sync/sync.go`** — `pulumi-library` sync-auth entry
  (`OneWay`: export SSH deploy key only; no import-dispatch creds).
- **`.github/workflows/apps-release.yml`** — added `pulumi/library/**` to the trigger paths (the
  matrix already listed `pulumi/library`, but the workflow never fired on a library-only push).

### The library `catalog:` transform (deterministic)

The monorepo references shared dep versions as `"<dep>": "catalog:"` (JS One-Version Rule). The
standalone has no catalog, so the export rewrites each back to the range it resolves to
(`_LIBRARY_CATALOG_VERSIONS` in `copy.bara.sky`, kept in sync with `//pnpm-workspace.yaml`):

| dep                   | range    |
| --------------------- | -------- |
| `@pulumi/pulumi`      | `^3.0.0` |
| `@pulumi/gcp`         | `^8.0.0` |
| `@pulumi/random`      | `^4.0.0` |
| `@pulumi/command`     | `^1.0.0` |
| `vitest`              | `^4.1.5` |
| `@vitest/coverage-v8` | `^4.1.5` |

`workspace:*` cross-refs are **rewritten to each package's exact concrete floor** (verified against the
live mirror: `bootstrap`→`foundation-project-factory: ^0.3.0`, `cb-private-pool`→`foundation-network: *`).
The mirror builds ts with **npm** and commits concrete ranges, so leaving `workspace:*` would publish a
changed dependency. The export also strips the `pulumi/library/` key prefix from
`.release-please-manifest.json`, and keeps the mirror's `release-please-config.json` + `CHANGELOG.md`s
(`standalone_only`) — the mirror owns the **path-based Go tag format** (`go/pkg/<n>/vX.Y.Z`, required by
`go get`; the monorepo's own config is flat `go-<n>`), the monorepo authors only the version numbers. The
mirror's `release.yml` is converted to a **multi-package publish-on-version-bump** (tag + `npm publish`
each package whose exported manifest version has no tag yet; idempotent, so the seed publishes nothing).

## Library cutover — operator steps (do first; the examples depend on it)

1. **Provision export auth.** Run `Copybara Sync-Auth Apply` (workflow_dispatch) so
   `copybara_sync` creates the `pulumi-library` write deploy key + `PULUMI_LIBRARY_SYNC_SSH_KEY`
   secret. (The shared `vitruvian-copybara-sync` App must be installed on `pulumi-library`.)
2. **Finalize `standalone_only`.** Clone the live `pulumi-library` and diff against
   `pulumi/library/` to confirm the files the standalone owns (its `.github/workflows/**`,
   `ts/pnpm-workspace.yaml`, lockfiles, `go/go.work*`). Adjust `standalone_only` /
   `origin_only_exclude` in `copy.bara.sky` if the diff surfaces anything else the export must not
   clobber or delete.
3. **Add the mirror publish-on-version-bump workflow** to `pulumi-library` (standalone-side), reading
   the version from the exported `.release-please-manifest.json` and tagging Go modules
   (`go/pkg/<name>/vX.Y.Z`) + `npm publish`ing the `foundation-*` packages, using the mirror's
   existing publish tokens. Disable the mirror's own release-please (no double release).
4. **Seed the baseline (manual, inspect).** `Copybara Export (pulumi-library)` via workflow_dispatch
   with `--force --ignore-noop`; review the resulting push to `pulumi-library` — verify `catalog:` is
   gone, `workspace:*` remains, and no standalone-owned file was deleted — before relying on routine
   push-triggered runs.
5. **Lock the standalone read-only (as code, not click-ops).** Every `OneWay` mirror gets classic
   branch protection on `main` (require-a-PR, `EnforceAdmins=false`) provisioned by
   `infrastructure/pulumi/pkg/copybara_sync` and applied by `Copybara Sync-Auth Apply` — so direct
   human pushes are rejected while the export deploy key keeps its admin-context bypass. `EnforceAdmins`
   MUST stay false: a deploy key bypasses branch protection only while "Include administrators" is off
   (GITHUB_TOKEN/App tokens do not), so flipping it true would break the mirror sync and publishing.
   Document that changes land in `pulumi/library/` in the monorepo.

## Example mirrors — GATED on the first library publish

Both example mirrors are **blocked until the library publishes a version containing the renamed Go
packages** (the go example's stage `go.mod`s carry zero pseudo-versions
`v0.0.0-00010101000000-000000000000` resolvable only via the monorepo-local `replace` directives; the
ts example's `foundation-*` deps are `workspace:*`). Neither can build standalone until a real library
version exists on the mirror. Order: **publish the library (steps above) → then wire the examples**,
each as an `export_only` component mirroring the library pattern:

- **go-foundation** (`subtree: pulumi/examples/go-foundation`, `repo: pulumi_go-example-foundation`).
  `export_transformations` per stage `go.mod`:
  1. delete the three `replace github.com/VitruvianSoftware/pulumi-library/go... => ../../../library/...`
     directives, and
  2. rewrite the zero pseudo-version on each `require github.com/VitruvianSoftware/pulumi-library/go...`
     line to the published `${LIBRARY_VERSION}` (the Go module version cut in the library publish).
     Add a `pulumi_go-example-foundation` sync-auth entry + `copybara-export-pulumi-go-example-foundation.yaml`.
- **ts-foundation** (`subtree: pulumi/examples/ts-foundation`, `repo: pulumi_ts-example-foundation`).
  `export_transformations`: rewrite the root `package.json` `"@vitruviansoftware/foundation-*":
"workspace:*"` deps to the published `^${LIBRARY_VERSION}` (the example is a single workspace member,
  not itself published, so `workspace:*` would not resolve when forked). Add the sync-auth entry +
  `copybara-export-pulumi-ts-example-foundation.yaml`. Keep the concrete `@pulumi/*` ranges as-is.

Each example: provision auth → finalize `standalone_only` by diffing the live standalone → seed with
`--force` and inspect. Read-only lockdown is automatic (the `OneWay` branch protection in
`copybara_sync`, step 5 above). No publish-on-version-bump (fork-and-own references).

## Still flagged (unchanged from the migration PRs)

- **e2e (real GCP org deploy).** The examples' gated e2e flow cannot run here (needs a GCP
  org/sandbox). Port it to a monorepo workflow and run it once against a sandbox org before declaring
  the examples' mirrors production-ready.
- **TS-under-Bazel targets** for the library (vitest via `rules_ts`, deferred in #586) — lower
  priority; native `pnpm vitest` + the mirror's npm publish cover correctness meanwhile.
