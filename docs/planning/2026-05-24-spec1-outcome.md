# vitruvian-core — Spec 1 Outcome (Foundation)

**Status: COMPLETE — 2026-05-24.** The monorepo is stood up and verified (local macOS + Linux CI).

## Delivered

- `VitruvianSoftware/vitruvian-core` created from the `kitchen-sink` template (private).
- Three projects grafted as top-level folders, with **full git history preserved** (`git-filter-repo --to-subdirectory-filter` + `--allow-unrelated-histories` merge):
  - `homelab/` (Go) — builds + tests green.
  - `devx/` (Go) — builds + 29 test targets green (1 quarantined, see below).
  - `mcp-slack/` (TypeScript) — builds via `ts_project` in the pnpm workspace.
- Go projects form a **multi-module `go.work`** workspace; each keeps its own `go.mod`/module path (kept intact for the Spec 3 Copybara round-trip).
- `bazel build //...` + `bazel test //...` green locally (macOS) **and on Linux CI** (`.github/workflows/ci.yaml`, ubuntu).
- `scaffold` codegen CLI available as a prebuilt `rules_multitool` binary: `@multitool//tools/scaffold` (v0.12.1).

## Notable decisions made during execution

- **Rust on macOS:** bumped `darwin-aarch64` LLVM `15.0.7 → 17.0.6` in `MODULE.bazel` — the LLVM-15 `ld64.lld` cannot link against the macOS 26 SDK's `.tbd` libSystem stubs (surfaced as undefined `_mmap`/`_pthread_*`). Linux/Intel-mac unchanged.
- **`huh` dependency conflict:** `devx`'s `huh v1.0.0` vs the template's scaffold Go-source tool's `huh v0.6.0` (the single-version `go.work` rule forces one version). Resolved by providing `scaffold` as a **prebuilt multitool binary** (zero Go-source deps) rather than a source `tool` directive — keeps apps single-version while decoupling the tool.
- **Gazelle:** removed `kotlin` from `ENABLE_LANGUAGES` in the root `BUILD` (no Kotlin sources; the Kotlin plugin emitted `kt_jvm_library` targets that collided with the grafted Go/TS targets, aborting repo-wide `gazelle`).
- **Quarantined test:** `//devx/internal/provider:provider_test` is `tags=["manual"]` — it shells out to docker/podman/colima/lima, unavailable in the Bazel sandbox.

## Deferred follow-ups

- **Backport the Rust/macOS LLVM-17 fix** to `aspect-workflows-template` (`{{ .ProjectSnake }}/MODULE.bazel`) — the same defect breaks `kitchen-sink` and the `rust`/`backstage-rust` starters on recent macOS.
- **Spec 2:** bring in `nexus-agent` (Swift) — add `rules_swift`/`rules_apple` + `swift`/`backstage-swift` presets to the template; requires a macOS CI runner for the `.app`.
- **Spec 3:** Copybara bidirectional sync between vitruvian-core's top-level folders and the standalone repos.
- Run the quarantined `provider_test` in an environment with container-runtime binaries.
