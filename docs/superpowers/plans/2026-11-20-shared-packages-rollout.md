---
status: in-progress
---

# Shared packages rollout: tracker and before/after numbers

Design: `docs/superpowers/specs/2026-11-20-shared-packages-convention.md` (#5240,
approved 2026-11-20). This file tracks the rollout and records the numbers the blog post
uses. Every "before" number is measured at one fixed commit, so it can be measured again
later the same way.

**Baseline commit:** `aaf841f83379bf1f75d7b12b39e897441e3336ac` (`origin/main`,
2026-11-20 10:34 PST).

## Before

### Private copies of shared helpers

Measured with `//tools/dupcheck -- --families --ref aaf841f83379` once that tool exists
(step 8). Until then, the same method was run by hand: for each helper family, every
`<family>.rs` outside `packages/rust/` that is not a one-line re-export, with each file's
`#[cfg(test)]` module and comments left out. "Also in another copy" counts lines that
appear in at least one other copy.

| Helper | Copies | Code lines | Also in another copy |
|---|---|---|---|
| `json` | 16 | 9,246 | 6,617 (71%) |
| `argparse` | 5 | 2,996 | 2,523 (84%) |
| `unicode_tables` | 4 | 4,518 | 2,628 (58%) |
| `pystr` | 10 | 3,298 | 1,707 (51%) |
| `http` | 8 | 3,188 | 1,422 (44%) |
| `jq` | 7 | 2,077 | 1,050 (50%) |
| `pyjson` | 5 | 1,750 | 745 (42%) |
| `pyerr` | 8 | 825 | 543 (65%) |
| `gostd` | 3 | 1,263 | 434 (34%) |
| `goexec` | 2 | 608 | 608 (100%) |
| **Total** | **68** | **29,769** | **18,277 (61%)** |

### Finding a package

- Backstage catalog: 33 components, **3** of type `library` (`design-system-android`,
  `pulumi-library-go`, `pulumi-library-ts`).
- ~~A full-text search of the catalog for `json`, through Backstage's MCP server: 0
  results.~~ Not a valid baseline: that MCP tool's `full_text_search` parameter returns
  nothing even for exact entity names. Use a tag filter or `search_backstage` instead.
- `packages/`: 9 top-level folders, **2** with a `catalog-info.yaml`.
- `packages/README.md`: lists 7 of the 9 folders, each as "Contract for packages/X". It
  leaves out `packages/rust/` and `packages/swift/`.
- `AGENTS.md`: no rule to look for an existing library before writing one.
- CI: no check for new duplicates, and no check that a package is in the catalog.

### Path filter drift

`ci.yaml`'s `detect-macos` list missed three folders that `macos-build`'s targets depend on:
`packages/swift/SentryLite`, `packages/vitruvian-sdk` and `apps/desktop/vitruvian-atrium`.
Presubmit has no Speaker unit, so a change to SentryLite or the SDK could merge without
Speaker being built on a Mac. Fixed by hand in #5244, until step 11 generates the list.

## Rollout

| Step | What | PR | State |
|---|---|---|---|
| 1 | Mac filter gap: confirmed and fixed by hand | #5244 | merged |
| 2 | Catalog entries and README contract for every package and product | #5249, #5272 | merged |
| 3 | Catalog check in CI, new-package initializer template | #5272 | merged |
| 4 | Backstage finds catalog files itself | #5256, #5259 | merged |
| 5 | Generated `packages/README.md` with drift test | #5260 | merged |
| 6 | Reuse-first rule in `AGENTS.md` | #5247 | merged |
| 7 | Backstage MCP for every agent tool | #5269 (draft), #5270 | parked: Backstage cannot delegate a read-only restricted token |
| 8 | Duplicate-code check (warning) | #5252, #5281 | merged; runs on every PR; required since step 11 |
| 9 | Helpers moved into shared packages, one family per PR | #5251, #5255, #5258, #5280, #5282, #5283, #5284, #5267 | eight merged; jq ruled out |
| 10 | Package renames, one per PR, then retire the `packages/rust/` and `packages/swift/` language folders | #5274, #5294, #5314, #5316, #5348 | all four renames merged; both language folders gone |
| 11 | Blocking duplicate check, generated Mac filter | #5281, this PR | generated Mac filter merged; check required by this PR (repo-config ruleset) |

## After

Measured at `e8822d9e2` (`origin/main` after #5267, 2026-11-20 18:30 PST) with
`bazel run //tools/dupcheck -- --families --ref <commit>`. The baseline was re-run with the
same tool at `aaf841f83` and gave the same totals as the hand count above.

| Helper | Copies | Code lines | Also in another copy |
|---|---|---|---|
| `json` | 15 | 8,865 | 6,155 (69%) |
| `argparse` | 2 | 1,118 | 343 (30%) |
| `unicode_tables` | 1 | 913 | 0 (0%) |
| `pystr` | 7 | 2,832 | 1,201 (42%) |
| `http` | 5 | 2,550 | 791 (31%) |
| `jq` | 7 | 2,077 | 1,050 (50%) |
| `pyjson` | 4 | 1,541 | 622 (40%) |
| `pyerr` | 5 | 523 | 232 (44%) |
| `gostd` | 0 | 0 | 0 (0%) |
| `goexec` | 0 | 0 | 0 (0%) |
| **Total** | **46** | **20,419** | **10,394 (50%)** |

- Copies 68 → 46; repeated lines 18,277 → 10,394.
- The eight merged helper PRs: +6,045 / −10,084 lines, net −4,039, tests included.
- Backstage: 54 components (from 33), 13 of type `library` (from 3).
- `packages/`: 13 packages, each with a `catalog-info.yaml` (from 2 of 9 folders).
- `packages/README.md`: generated from the catalog files, with a drift test.
- New-agent acceptance test: found the right package for 4 of 5 needs. The miss (pycompat's
  undocumented HTTP client) is fixed in #5290; a Backstage search for "http curl token" now
  returns `vitruvian-pycompat`.

Known gaps: most of the 15 remaining JSON copies have their own value and error types; the 7 `jq` copies disagree
on 10 behaviours; tools built with plain `rustc` in CI need a workflow change to link shared
crates.
