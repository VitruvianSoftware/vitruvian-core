# vitruvian-core — Monorepo Foundation (Spec 1 of 3)

**Status:** Draft for review · 2026-05-24

**Initiative:** Consolidate VitruvianSoftware open-source repos into a Bazel monorepo (`vitruvian-core`) built from the `kitchen-sink` template, then add Swift support and Copybara bidirectional sync.

**This spec covers Spec 1 only:** stand up `vitruvian-core` and bring the three Bazel-friendly projects — `devx`, `homelab`, `mcp-slack` — to a green build with full history preserved.

- **Spec 2 (later):** add Swift support (`rules_swift`/`rules_apple`, `swift`/`backstage-swift` presets) to the template on `platform-v2.0`, and use it to bring `nexus-agent` into the monorepo.
- **Spec 3 (later):** Copybara bidirectional sync between monorepo folders and the standalone repos.

## Goal & success criteria

1. A new repo `VitruvianSoftware/vitruvian-core`, created **from** the `kitchen-sink` template, with `devx/`, `homelab/`, `mcp-slack/` as top-level folders, **full upstream git history preserved**.
2. `bazel build //...` and `bazel test //...` pass on Linux CI (the kitchen-sink ubuntu workflow) for all three projects.
3. Each project's module identity / import paths are **left intact**, so Spec 3 (Copybara) can round-trip to the standalone repos cleanly.

## Out of scope (this spec)

- `nexus-agent` and any Swift support — Spec 2.
- Copybara sync — Spec 3.
- Trimming unused template languages — decided against (keeping all infra).

## Decisions (locked during brainstorming)

- **Creation:** `gh repo create VitruvianSoftware/vitruvian-core --template VitruvianSoftware/kitchen-sink` — a new repo with its own identity, seeded from the template (NOT a clone of kitchen-sink, NOT a fork). Then clone `vitruvian-core` locally to do the work.
- **Layout:** one top-level folder per project, 1:1 with each standalone repo. This is the pragmatic polyrepo-consolidation layout that makes Copybara mappings trivial. It is deliberately **not** Google's internal functional hierarchy (`//area/team/project`), which would be over-engineering for four repos; we can regroup later if the monorepo grows.
- **Infra:** keep **all** kitchen-sink build/dev infrastructure — that batteries-included setup is the whole reason for using the template. No trimming.
- **History:** preserve full per-project history via `git-filter-repo --to-subdirectory-filter <name>/` then merge.

## Target layout

```
vitruvian-core/
├── MODULE.bazel, .bazelrc, .aspect/, tools/, githooks/,
│   .github/, .devcontainer/, .vscode/, ...   ← kept from kitchen-sink
├── devx/         # Go (+ minor Python / TS / Dockerfile)
├── homelab/      # Go
└── mcp-slack/    # JavaScript
```

(`nexus-agent/` is added in Spec 2.)

## Approach

1. **Create & seed.** Create `vitruvian-core` from the template; clone it. Remove any sample/demo source the template ships while keeping all build/dev infra. Confirm the bare monorepo is `bazel build //...` clean before touching it further.
2. **Graft projects (history-preserving).** For each of `devx`, `homelab`, `mcp-slack`: clone a fresh copy, run `git-filter-repo --to-subdirectory-filter <name>/`, then merge into `vitruvian-core` with `--allow-unrelated-histories`. Result: a unified history where every grafted commit is pathed under its folder.
3. **Integrate dependencies.**
   - **Go (`devx`, `homelab`):** keep a **multi-module** layout — each project retains its own `go.mod` and module path (`github.com/VitruvianSoftware/devx`, `.../homelab`) so the standalone repos stay valid for Copybara. Wire them into bzlmod (via `go.work` and/or per-module `go_deps.from_file`) and set per-folder Gazelle prefixes. Do **not** rewrite import paths into a single root module.
   - **JS (`mcp-slack`):** fold its `package.json` into the monorepo's pnpm workspace (rules_js).
4. **Generate BUILD files.** `bazel run //:gazelle` for Go and JS; iterate.
5. **Green the build.** Resolve dependency-version conflicts, missing rules, and any project-specific build steps until `bazel build //...` and `bazel test //...` pass.
6. **CI.** Confirm the inherited ubuntu CI builds `//...`; adjust targets/matrix as needed.

## Key risks & unknowns

- **Go multi-module integration is the fiddliest part:** two `go.mod` files in one bzlmod workspace, dependency-version reconciliation, and Gazelle prefixes. *Mitigation:* graft one Go project first (`homelab`, the smaller one) to prove the pattern before `devx`.
- **mcp-slack** may rely on npm scripts / a JS build step that needs Bazel-ization under `rules_js`; its tests (if any) need wiring.
- **devx** carries minor Python/TS/Dockerfile content; the in-scope code is Go. Non-Go bits may be best-effort or deferred without blocking the green build.
- The projects currently have **no Bazel setup**, so all BUILD files are generated fresh — expect iteration.
- **History graft** merges unrelated histories (`--allow-unrelated-histories`); verify attribution afterward.

## Verification

- `bazel build //...` and `bazel test //...` green locally and in ubuntu CI.
- Per-project smoke check: each project's primary binary/library target builds, and any existing tests run under `bazel test`.
- `git log --follow` shows preserved history for a sample file in each grafted folder.
