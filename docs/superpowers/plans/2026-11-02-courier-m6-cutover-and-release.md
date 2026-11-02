---
status: in-progress
---

# Courier milestone 6: cutover and release — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Courier ships as a Developer ID-signed, notarised release through the desktop pipeline, and James has a short guide to move his accounts onto it and to go back if he must.

**Done when (spec, milestone 6):** Google Messages moved, the reference app logged out, a release through the desktop pipeline (`//tools/desktop-package`). The account steps are James's, by hand. This plan builds everything they need.

**Architecture:** Courier copies HomeSpeaker's release shape, the one `apps/desktop/AGENTS.md` §6 describes for a new desktop app: a release-please config in the app folder, one `.github/workflows/courier-release.yaml` that runs release-please and, when the release PR merges, a publishing job on the Mac runner. The job runs `bazel run //apps/desktop/courier/app:publish`, which builds the universal app, adds Courier's Telegram app ID, and hands the app to `//tools/desktop-package` to sign, notarise, package, upload, write the Homebrew cask and sync the downloads catalog. HomeSpeaker is not notarised, so the signing step is the one Vitruvian's release uses (`//apps/desktop/vitruvian:ci_setup_signing` and the `VITRUVIAN_*` signing and notary secrets: one Developer ID for every Mac app).

**Spec:** `docs/superpowers/specs/2026-10-15-courier-iteration-1-design.md` (milestone 6; "Sold directly").

## Global Constraints

- No beta channel. Nothing is published on a push to main; only a merged release PR publishes.
- The first release must not carry Courier's whole history in its changelog: `bootstrap-sha` is the commit this work branched from.
- One version: `app/version.bzl` (`COURIER_VERSION`) stays the only place it is written. release-please updates it through an `x-release-please-version` marker.
- The release app holds a universal engine (`Contents/Helpers/courier-engine`, arm64 and x86_64). The publish step refuses an app whose app binary or engine lacks either architecture.
- A real release refuses to ship without Courier's Telegram app ID (`COURIER_TELEGRAM_API_ID`, `COURIER_TELEGRAM_API_HASH`, from repository secrets). A dry run goes on without it and says so.
- The engine and the app are signed with the hardened runtime, the app with `Resources/Courier.entitlements`.
- Never launch Courier, never touch `/Applications/Courier.app` or Courier's data, never publish, tag or run a release workflow while building this.
- Visible app text never says "Beeper". The guides for James may.

## Review Focus

1. What happens on GitHub when this merges: a release PR opens and, through `release-pr-automerge.yaml`, merges on green CI; the merged release then publishes on its own. James holds it with `pr-hold` if he wants to look first.
2. The publish step's refusals: wrong tag, version.bzl not matching the tag, a single-architecture app or engine, missing Telegram credentials on a real release.
3. `--dry-run` never uploads, never pushes the cask, never needs a secret.

---

### Task 1: Release config

**Files:** create `apps/desktop/courier/release-please-config.json`, `.release-please-manifest.json` (`0.3.0`), `CHANGELOG.md`; mark `app/version.bzl`.

- [ ] Component `courier`, tag `courier-vX.Y.Z`, the same options as HomeSpeaker's, `bootstrap-sha` set, `extra-files` the generic updater on `app/version.bzl`.
- [ ] `bazel test //tools/release-scope/...` passes, and a title scoped `courier` is recognised.

### Task 2: The publish step

**Files:** create `app/scripts/src/publish.rs` (in `courier_scripts_lib`), `app/scripts/src/bin/publish.rs`; `app/BUILD` (`:publish`); make the engine helper universal if it is not.

- [ ] Tests first: tag and version parsing (`courier-v1.2.3` → `1.2.3`; anything else refused), the version.bzl reader, the package-desktop argument list (dry run, real release), the architecture check against `lipo -archs` output, the refusal without Telegram credentials on a real release, and the dist check.
- [ ] `bazel run --config=macos-app //apps/desktop/courier/app:publish -- --dry-run` builds the universal app, signs it with the local Developer ID if there is one, and leaves every DMG, the ZIP, their checksums and the cask in `dist`.
- [ ] `codesign --verify --deep --strict` and `spctl -a -t exec` on the packaged app; `lipo -archs` on the engine in each DMG.

### Task 3: The workflow

**Files:** create `.github/workflows/courier-release.yaml`; update the macOS `pipeline_unit` if its tests change.

- [ ] Copy `home-speaker-release.yaml`: release-please job, then `publish-package` on `xcode-27` only when a release was created (or a tag is dispatched), then `--verify-only`.
- [ ] The signing import step and notary secrets as in `delivery-vitruvian.yaml`'s production rung; the Telegram secrets; BuildBuddy cache.
- [ ] `bazel run //tools/ci:actionlint`; regenerate anything generated (`bazel run //tools/ci:gen`), and its tidy check passes.

### Task 4: Downloads catalog

**Files:** `tools/sync-downloads/src/sync.rs`.

- [ ] A Courier block like HomeSpeaker's, with a test. It does nothing until the catalog has a `courier` entry, which is added after the first release exists (a listing with no files would be broken).

### Task 5: Cutover guide and acceptance list

**Files:** create `apps/desktop/courier/docs/cutover.md`, `apps/desktop/courier/docs/m6-acceptance.md`.

- [ ] Cutover: install the release; move Google Messages (unpair the reference app's web session, pair Courier); check each network receives; switch Claude Code's MCP from `mcpServers.beeper` (port 23373) to Courier (port 23390, `/v0/mcp`, a token from Settings ▸ Integrations ▸ New connection…); log out of the reference app; rollback.
- [ ] Acceptance: the by-hand list, like `m5-acceptance.md`.

### Task 6: Gaps the cutover needs

- [ ] Check Settings can unlink and re-link each network, and that the version is visible. Fix only what blocks the guide, with tests; list the rest.

### Task 7: Verify

- [ ] `bazel query 'tests(//apps/desktop/courier/...)' | xargs bazel test --config=macos-app`, actionlint, release-scope and sync-downloads tests.
