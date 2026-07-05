# pulumi-library → monorepo migration

Status: PR1 of the Pulumi monorepo initiative. Date: 2026-07-05.

## Context

The standalone Pulumi repos (`pulumi-library`, `pulumi_go-example-foundation`,
`pulumi_ts-example-foundation`) are being folded into `vitruvian-core`, adhering
to the practices already established here (history-preserving grafts, Bazel +
Gazelle, the pnpm catalog / go.work One Version Rule, release-please, Copybara
internal-first mirrors). The library lands first because the two foundation
examples consume it; they follow as PR2/PR3.

This document records PR1: the **pulumi-library** graft and integration.

## Layout

The initiative lives under a cohesive `pulumi/` tree:

```
pulumi/
  library/
    go/    pkg/<component>/ …   (26 Go modules: root + 25 components)
    ts/    packages/<component>/ … (31 published @vitruviansoftware/foundation-* packages)
  examples/   (PR2/PR3 — go-foundation, ts-foundation)
```

## What PR1 does

1. **History-preserving graft.** `git filter-repo --to-subdirectory-filter
pulumi/library/` on a fresh clone of `pulumi-library`, then
   `git merge --allow-unrelated-histories`. All 51 upstream commits are
   preserved (`git log --oneline -- pulumi/library/`).

2. **Go → Bazel workspace.** All 26 library modules are added to `//:go.work`
   (the library's own `go.work` is dropped); a single
   `go_deps.from_file(go_work=...)` covers them. `go work sync` unified shared
   indirect deps across the workspace (minor forward bumps in devx/homelab under
   the One Version Rule). `go_library`/`go_test` BUILD files were generated with
   `gazelle:prefix` directives and gazelle-style labels; the library's direct
   external deps are registered in `use_repo(go_deps, ...)`.

3. **TS → pnpm workspace.** `pulumi/library/ts` (+ `packages/*`) registered in
   `pnpm-workspace.yaml`; `@pulumi/*` SDKs and the vitest toolchain moved to the
   pnpm **catalog** (`catalog:`); cross-package deps repointed to `workspace:*`;
   `ignoreDeprecations: "6.0"` added to the base tsconfig so the library builds
   under the monorepo's TypeScript 6.0.3; root `pnpm-lock.yaml` regenerated.
   Published package names and versions are unchanged. TS packages build/test
   natively (vitest); their Bazel `ts_project` targets are deferred (see below).

4. **Release / license / ownership / dependabot.** release-please paths
   prefixed with `pulumi/library/` and `pulumi/library` registered in the
   apps-release matrix. `pulumi/library/**` exempted from MIT header enforcement
   (the library stays Apache-2.0 for the public mirror). `/pulumi/` routed to
   `@VitruvianSoftware/platform-team` in CODEOWNERS. dependabot gomod coverage
   added for the library modules.

## Verified natively

- Go: `go build` + `go test` pass across all 26 modules; `go work sync` clean.
- TS: `tsc --noEmit` clean, `tsc` build clean under TS 6, **vitest 71/71**.
- `license-check` header scan passes (0 offenders; library excluded).

## Deferred to CI / follow-up

Bazel could not be bootstrapped in the migration environment (org egress
policy blocks GitHub-release toolchain downloads), so Bazel-level verification
runs in CI:

- **`bazel run //:tidy` (gazelle) is the source of truth** for BUILD files and
  will reconcile anything the hand/standalone-gazelle generation got subtly
  wrong, and regenerate `MODULE.bazel.lock` under the One Version Rule.
- **TS Bazel targets** (`ts_project`/`npm_package` + vitest test targets) are a
  follow-up. `pulumi/library` is `# gazelle:exclude`-d (like `tabula` and
  `infrastructure`): the Go BUILD files are hand-authored, and the TS packages
  have no Bazel targets yet — they build/test natively via pnpm+vitest and are
  available in the pnpm workspace. Generating the TS targets needs a
  Bazel-capable environment to run aspect's JS gazelle (it could not run in the
  migration sandbox). The monorepo test standard is `aspect_rules_jest`.
- **Copybara mirror-out** + the **publish-origin** decision (version/publish from
  the monorepo apps-release vs the mirror's own `release.yml`) are a follow-up;
  the library's standalone `.github/workflows/` are retained (inert in the
  monorepo) pending that decision.
