# nexus-agent (Swift macOS app) Implementation Plan — Spec 2B

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Graft `nexus-agent` into `vitruvian-core` (full history) and build its three parts — the Swift macOS `.app` (ad-hoc) on macOS CI, the Node ESM bridge, and `bot.sh` — while keeping the ubuntu `bazel build //...` green.

**Architecture:** History-preserving graft into `nexus-agent/`. The dep-free SwiftPM app becomes `swift_library` + `macos_application` (`rules_swift 3.6.1` + `rules_apple`); the Swift targets are constrained to macOS so the ubuntu CI skips them, and a new `macos-latest` CI job builds them. The Node bridge joins the pnpm workspace via `rules_js`. Ad-hoc/unsigned — builds, not runs.

**Tech Stack:** Bazel/bzlmod, `rules_swift`, `rules_apple`, `rules_js` + pnpm, `rules_shell`, git-filter-repo, GitHub Actions (ubuntu + macos-latest).

**Prerequisites:** in the `vitruvian-core` checkout (`/Users/james/Workspace/gh/application/vitruvian/vitruvian-core`), on `main`; `git-filter-repo` installed; confirm the current `rules_apple` BCR version + `macos_application` API at <https://registry.bazel.build/modules/rules_apple>.

---

### Task 1: Graft nexus-agent (history-preserving)

**Files:** Create `nexus-agent/` (grafted tree)

- [ ] **Step 1:** Rewrite history under `nexus-agent/`:
```bash
cd /tmp && rm -rf nexus-agent-graft
git clone https://github.com/VitruvianSoftware/nexus-agent nexus-agent-graft
cd nexus-agent-graft && git filter-repo --to-subdirectory-filter nexus-agent/
```
- [ ] **Step 2:** Merge into vitruvian-core:
```bash
cd /Users/james/Workspace/gh/application/vitruvian/vitruvian-core
git remote add nexus-agent-graft /tmp/nexus-agent-graft
git fetch nexus-agent-graft
git merge --allow-unrelated-histories nexus-agent-graft/main -m "feat: graft nexus-agent into monorepo (history-preserving)"
git remote remove nexus-agent-graft
```
(Use the real default branch if not `main`.) Verify `nexus-agent/macos/Package.swift`, `nexus-agent/src/`, `nexus-agent/package.json`, `nexus-agent/bot.sh` exist and `git log -- nexus-agent/` shows original commits.

### Task 2: Add rules_swift + rules_apple to MODULE.bazel

**Files:** Modify `MODULE.bazel`

- [ ] **Step 1:** Add (ungated — vitruvian-core is a real repo) near the other `bazel_dep`s:
```python
bazel_dep(name = "rules_swift", version = "3.6.1", repo_name = "build_bazel_rules_swift")
bazel_dep(name = "rules_apple", version = "<current BCR version>", repo_name = "build_bazel_rules_apple")
```
Verify the current `rules_apple` version + whether any extension/toolchain registration is needed at the BCR registry page; rules_swift 3.6.1 self-registers its toolchain (matches Spec 2A).
- [ ] **Step 2:** `bazel mod deps | grep -E 'rules_swift|rules_apple'` shows both resolve.
- [ ] **Step 3:** Commit: `feat(module): add rules_swift + rules_apple for nexus-agent`.

### Task 3: Build the Swift .app (swift_library + macos_application)

**Files:** Create `nexus-agent/macos/BUILD`

- [ ] **Step 1:** Hand-write `nexus-agent/macos/BUILD` (Swift has no Gazelle):
```python
load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:macos.bzl", "macos_application")

swift_library(
    name = "NexusAgent_lib",
    srcs = glob(["Sources/NexusAgent/**/*.swift"]),
    module_name = "NexusAgent",
    target_compatible_with = ["@platforms//os:macos"],
)

macos_application(
    name = "NexusAgent",
    bundle_id = "com.vitruviansoftware.nexusagent",
    infoplists = ["Resources/Info.plist"],
    minimum_os_version = "14.0",
    resources = ["Resources/AppIcon.icns"],
    deps = [":NexusAgent_lib"],
)
```
Verify against the pinned `rules_apple`: the exact load labels, the **ad-hoc/unsigned** behavior (no `provisioning_profile`/cert → ad-hoc by default on macOS — confirm), and whether `AppIcon.icns` belongs in `resources` (with `CFBundleIconFile` in Info.plist) or an `app_icons` asset catalog. (`Package.swift` stays in place for SwiftPM/Xcode users; Bazel uses this BUILD.)
- [ ] **Step 2 (macOS only):** `bazel build //nexus-agent/macos:NexusAgent` → produces `bazel-bin/nexus-agent/macos/NexusAgent.app`. Iterate on rules_apple errors (use `superpowers:systematic-debugging`). Confirm ad-hoc signing: `codesign -dv bazel-bin/nexus-agent/macos/NexusAgent.app` shows an ad-hoc signature.
- [ ] **Step 3:** Commit: `feat(nexus-agent): build macОS .app (swift_library + macos_application, ad-hoc)`.

### Task 4: Node bridge + shell

**Files:** Modify `pnpm-workspace.yaml`; create `nexus-agent/src/BUILD` (via Gazelle) and `nexus-agent/BUILD` (sh_binary)

- [ ] **Step 1:** Add `nexus-agent` to `pnpm-workspace.yaml`'s `packages:`. Remove `nexus-agent/package-lock.json` (npm lock; the monorepo uses pnpm). Regenerate the root lockfile: `bazel run -- @pnpm//:pnpm install --lockfile-only` (copy the result back from the execroot if needed, as in the mcp-slack graft).
- [ ] **Step 2:** `bazel run //:gazelle` to generate `js_library`/`js_binary` for the ESM bridge (telegraf/dotenv; no `ts_project` — it's plain JS).
- [ ] **Step 3:** Add a `sh_binary` for `bot.sh` in `nexus-agent/BUILD`:
```python
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
sh_binary(name = "bot", srcs = ["bot.sh"])
```
- [ ] **Step 4:** `bazel build //nexus-agent/src/... //nexus-agent:bot` (Linux-ok) → green. The bridge builds; it is NOT run (needs a Telegram token).
- [ ] **Step 5:** Commit: `feat(nexus-agent): node bridge into pnpm workspace + bot.sh sh_binary`.

### Task 5: macOS CI leg + confirm ubuntu skips Swift

**Files:** Modify `.github/workflows/ci.yaml`

- [ ] **Step 1:** Confirm the existing ubuntu `build-test` job's `bazel build //...` still passes by **skipping** the macOS-only Swift targets. If `bazel build //...` errors (instead of skipping) on the incompatible Swift targets, add `--skip_incompatible_explicit_targets` is not needed for `//...` (wildcards auto-skip incompatible) — but verify; if needed, scope the ubuntu build to `bazel build //... --build_tag_filters=-requires-macos` or rely on `target_compatible_with` auto-skip.
- [ ] **Step 2:** Add a second job `build-macos` to `ci.yaml`:
```yaml
  build-macos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v6
      - uses: bazel-contrib/setup-bazel@c5acdfb288317d0b5c0bbd7a396a3dc868bb0f86 # 0.19.0
        with:
          bazelisk-cache: true
          repository-cache: true
      - run: bazel build //nexus-agent/...
```
(Swift/Xcode are native on macos-latest — no setup-swift or `CC=clang` needed.)
- [ ] **Step 3:** Commit, push `main`, watch both CI jobs (`gh run watch ... --exit-status`) until green. Per the standing always-watch preference.

### Task 6: Whole-tree verification + commit planning docs

**Files:** (verification); commit `docs/planning/2026-05-25-nexus-agent-swift-*.md`

- [ ] **Step 1:** Local (macOS): `bazel build //...` builds everything incl. `//nexus-agent/macos:NexusAgent`; `bazel test //...` still green for the other projects.
- [ ] **Step 2:** Confirm history: `git log --oneline -- nexus-agent/ | tail -3` shows original commits.
- [ ] **Step 3:** Commit the 2B spec + this plan (`docs: add Spec 2B (nexus-agent) spec + plan`). Push; watch CI.

---

## Notes on iteration

The uncertain pieces (flagged inline): the current `rules_apple` version + `macos_application` API, the ad-hoc/unsigned default, and the `AppIcon.icns` placement — verify against rules_apple docs, don't guess. The graft + Node-into-pnpm steps faithfully mirror the Spec 1 grafts (esp. `mcp-slack`). The `target_compatible_with` macOS skip is the key trick keeping ubuntu green.

## Outcome (2026-05-25) — COMPLETE

All success criteria met. CI run `26394005090` on `main` is green on both legs:
the ubuntu `build-test` (`bazel build/test //...`) and the new macOS `build-macos`
(`bazel build --config=macos-app //nexus-agent/... //nexus-agent/macos:NexusAgent`).
The `.app` builds on the macOS runner (ad-hoc signed — no identity configured), the
Node bridge + `bot.sh` build, and the full nexus-agent history (85 commits, back to
the original `Initial commit`) is preserved under `nexus-agent/`.

Both risks the spec flagged materialized as a single root cause: a toolchain-resolution
conflict between the template's hermetic `@llvm_toolchain` (the f7c1ecd Rust/macOS
linker fix) and the Apple CC toolchain `rules_apple` needs. Diagnosed with
`--toolchain_resolution_debug`, not guesswork. Resolution differed from the plan's
literal steps:

- **macOS link (`objc-executable`):** Apple's CC toolchain wasn't registered, so LLVM
  (no `objc-executable` action_config) won resolution on the apple platform. Fixed by
  making the Apple toolchain available (`apple_cc_configure` extension) and opting the
  app build into it via a `macos-app` bazelrc config (`--extra_toolchains`), **not** a
  global `register_toolchains`. On macOS the host platform is constraint-identical to
  the apple `darwin_*` platform, so a global registration would shadow LLVM for all C++
  and silently make plain C++/Rust/cgo non-hermetic. The hermetic LLVM toolchain stays
  the default everywhere else (verified locally).
- **ubuntu skip:** `target_compatible_with` could **not** skip the app (the spec's
  "key trick" was wrong here): `macos_application`'s incoming platform transition makes
  the macOS constraint satisfied post-transition, so the target is never skipped on
  Linux and instead errors with "No matching toolchains found". Fixed with
  `tags = ["manual"]`, which excludes it from the `//...` wildcard; the macOS leg builds
  it by explicit label.

Local builds of the Swift targets need a full Xcode (this dev machine has only Command
Line Tools), so the Swift `.app`/`swift_library` are verified via the macOS CI runner,
not locally.

## Deferred (not this plan)

- **Real Developer ID signing + notarization** for distribution.
- **Hermetic Swift toolchain** (shared follow-up with 2A).
- **Spec 3:** Copybara bidirectional sync (now that all four projects are consolidated).
