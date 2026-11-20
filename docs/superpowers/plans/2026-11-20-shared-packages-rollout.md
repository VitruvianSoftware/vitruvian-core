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
- A full-text search of the catalog for `json`, through Backstage's MCP server: **0
  results**, although 16 tools carry a JSON helper.
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
| 1 | Mac filter gap: confirmed and fixed by hand | #5244 | waiting for James's approval |
| 2 | Catalog entries and README contract for every package and product | | |
| 3 | Catalog check in CI, new-package initializer template | | |
| 4 | Backstage finds catalog files itself | | |
| 5 | Generated `packages/README.md` with drift test | | |
| 6 | Reuse-first rule in `AGENTS.md` | | |
| 7 | Backstage MCP for every agent tool | | |
| 8 | Duplicate-code check (warning) | | |
| 9 | Helpers moved into shared packages, one family per PR | | |
| 10 | Package renames, one per PR | | |
| 11 | Blocking duplicate check, generated Mac filter | | |

## After

Filled in when the rollout is done, with the same measurements, at a pinned commit.
