# nexus-agent into vitruvian-core (Spec 2B)

**Status:** Draft for review · 2026-05-25

**Initiative:** Consolidate VitruvianSoftware open-source repos into `vitruvian-core`. Spec 1 brought in devx/homelab/mcp-slack; Spec 2A added Swift to the template. **Spec 2B (this, the final consolidation piece):** graft `nexus-agent` into `vitruvian-core` and build its three parts — the Swift macOS `.app`, the Node bridge, and the shell script.

## Goal & success criteria

1. `nexus-agent` grafted into `vitruvian-core/nexus-agent/` with **full git history preserved**.
2. `bazel build //nexus-agent/...` on **macOS CI** produces a `NexusAgent.app` bundle (**ad-hoc signed**).
3. `bazel build //...` on the existing **ubuntu CI stays green** — the macOS-only Swift targets are skipped via `target_compatible_with`.
4. The Node bridge builds under Bazel; `bot.sh` is present (as a `sh_binary` or tracked file).

## Out of scope (2B)

- Real Developer ID signing + notarization — **ad-hoc/unsigned only** (separate follow-up if/when the app is distributed).
- *Running* the app or the Telegram bot in CI (they need a GUI / a Telegram token) — this spec verifies **builds**, not runs.
- Copybara bidirectional sync — Spec 3.

## Decisions (from brainstorming)

- **Ad-hoc/unsigned `.app` build.**
- The Swift app is **dependency-free SwiftPM** (one `executableTarget`, system frameworks only) → `swift_library` + `macos_application` (`rules_swift 3.6.1` + `rules_apple`). No SwiftPM-dependency translation needed.
- The Swift targets are **macOS-only** (`target_compatible_with = ["@platforms//os:macos"]`) so ubuntu `bazel build //...` skips them; a new **macOS CI leg** builds them.
- The Node bridge → vitruvian-core's **pnpm workspace + `rules_js`** (plain ESM: telegraf/dotenv; no TS build).
- Add `rules_swift` + `rules_apple` to `vitruvian-core/MODULE.bazel` **ungated** (it's a real repo, not the template).

## Target layout

```
vitruvian-core/
├── … (homelab, devx, mcp-slack, template infra)
└── nexus-agent/
    ├── macos/          # Swift menu-bar .app (SwiftPM sources → swift_library + macos_application)
    │   ├── Package.swift            # left in place for SwiftPM/Xcode users; Bazel uses the BUILD
    │   ├── Sources/NexusAgent/*.swift
    │   ├── Resources/{Info.plist, AppIcon.icns}
    │   └── BUILD                    # hand-written (Swift has no Gazelle)
    ├── src/            # Node/ESM Telegram bridge
    ├── package.json    # telegraf, dotenv
    └── bot.sh          # shell
```

## Approach

1. **Graft (history-preserving):** clone nexus-agent, `git filter-repo --to-subdirectory-filter nexus-agent/`, merge into vitruvian-core with `--allow-unrelated-histories`.
2. **`MODULE.bazel`:** add `bazel_dep(name = "rules_swift", version = "3.6.1", repo_name = "build_bazel_rules_swift")` (matching Spec 2A) and `bazel_dep(name = "rules_apple", version = "<current BCR>")` + any required apple/swift toolchain registration. Verify versions on the BCR registry.
3. **Swift `.app`** — hand-written `nexus-agent/macos/BUILD`:
   - `swift_library` over `Sources/NexusAgent/*.swift`, with `target_compatible_with = ["@platforms//os:macos"]`.
   - `macos_application`: `bundle_id = "com.vitruviansoftware.nexusagent"`, `minimum_os_version = "14.0"`, `infoplists = ["Resources/Info.plist"]`, the `AppIcon.icns` as a resource (with `CFBundleIconFile` in Info.plist) or an asset catalog, `deps = [":NexusAgent_lib"]`, and **ad-hoc/unsigned** (no provisioning profile). Verify rules_apple's unsigned/ad-hoc mechanism for the version pinned.
4. **Node bridge:** add `nexus-agent` to vitruvian-core's `pnpm-workspace.yaml`; integrate `package.json` (telegraf/dotenv); `bazel run //:gazelle` generates `js_library`/`js_binary`. Plain ESM — no `ts_project`. Builds/typechecks; not run.
5. **Shell:** `bot.sh` as a `sh_binary` (rules_shell) or a tracked file if not worth a target.
6. **CI:** the existing ubuntu `ci.yaml` `bazel build //...` skips the macOS-only Swift targets (incompatible-target skipping). **Add a `macos-latest` job** that runs `bazel build //nexus-agent/...` (Swift/Xcode are native on macos-latest — no `setup-swift`/`CC=clang` needed).

## Risks & unknowns

- **`macos_application` config:** the exact unsigned/ad-hoc flag, and `AppIcon.icns`-as-loose-resource vs asset catalog — verify against the pinned `rules_apple` version.
- **`rules_apple` BCR version:** verify current (the contributor guide's `3.2.0` is likely stale).
- **`target_compatible_with` skipping:** confirm ubuntu `bazel build //...` cleanly *skips* (not errors on) the Swift targets.
- **macOS runner:** cost/availability for the new CI leg; first build downloads the Swift/Bazel toolchains.
- The `swift_library` compiles SwiftUI/AppKit — needs the macOS SDK (native on `macos-latest`).

## Verification

- **macOS CI:** `bazel build //nexus-agent/...` produces a valid `NexusAgent.app` bundle (ad-hoc signed; `codesign -dv` shows ad-hoc).
- **ubuntu CI:** `bazel build //...` stays green (Swift targets skipped); the Node bridge builds.
- `git log --follow` shows preserved nexus-agent history under `nexus-agent/`.
