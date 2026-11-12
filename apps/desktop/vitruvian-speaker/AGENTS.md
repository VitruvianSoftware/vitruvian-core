# Vitruvian Speaker (vitruvian-speaker) — agent guide

> Scoped to `apps/desktop/vitruvian-speaker/`. Repo-wide rules live in the root
> [`AGENTS.md`](../../../AGENTS.md); the developer SOP is
> [`CONTRIBUTING.md`](../../../CONTRIBUTING.md), which wins on any conflict.

## What this is

A Swift macOS menu-bar app (macOS 14+, universal binary) that reads things aloud on Google Home
speakers and Nest displays through Google's hosted Home API: a one-line summary of each Claude
Code reply, new Slack or Google Chat messages, or typed text. Two modules:
`Sources/VitruvianSpeakerCore` (logic, unit-tested, no UI) and `Sources/VitruvianSpeaker` (the app).
It is scriptable — `VitruvianSpeaker --say`, `--volume`, `--set-volume 0-100`, `--mute`, `--unmute`.

## Build, test, run

- **Build and test with Bazel**, from the repo root. Build with
  `bazel build --config=macos-app //apps/desktop/vitruvian-speaker/...`.
  Run tests with:
  `bazel test --config=macos-app //apps/desktop/vitruvian-speaker:VitruvianSpeakerTests //apps/desktop/vitruvian-speaker:VitruvianSpeakerToolTests //apps/desktop/vitruvian-speaker:VitruvianSpeakerViewTests //apps/desktop/vitruvian-speaker:tool_conformance_test //apps/desktop/vitruvian-speaker:tool_version_test`.
- **What CI actually runs** (`macos-build` lane in `.github/workflows/ci.yaml`, when
  `apps/desktop/vitruvian-speaker/**` changes): `bazel build --config=macos-app
  //apps/desktop/vitruvian-speaker/... :VitruvianSpeaker` as a compile check, then `:VitruvianSpeakerTests`,
  `:sync_secrets_test`, `:VitruvianSpeakerToolTests`, `:tool_conformance_test`, `:tool_version_test`,
  `:zip_tool_test` and `:publish_test`, and `bazel run //apps/desktop/vitruvian-speaker:publish -- --dry-run`.
  It does not run `:VitruvianSpeakerViewTests` (the view snapshots): run those yourself.
- **What ships is SwiftPM, not Bazel:** the release workflow runs `bazel run //apps/desktop/vitruvian-speaker:publish`, which
  builds with `swift build -c release --arch arm64 --arch x86_64` and bundles the universal .app.
- **The app, test and `sync_secrets_test` targets are `manual` and macOS-only**, so none of them
  appears in `bazel test //...` or in the Linux presubmit plan (`sync-secrets` and the two
  libraries are ordinary targets). Run the steps above on a Mac before pushing — a green Linux
  sweep proves nothing about this app.
- **Release package exactly as CI does:** `bazel run //apps/desktop/vitruvian-speaker:publish -- --dry-run` (universal .app,
  zip, sha256). Slack token onto this Mac from Bitwarden:
  `bazel run //apps/desktop/vitruvian-speaker:sync-secrets` for the app, or
  `bazel run //apps/desktop/vitruvian-speaker:sync-secrets -- --extension` for the extension's
  `secrets.json` (found through `speaker_door.json`; it stops and writes nothing if that is missing).

## Conventions & landmines

- **Releases** are cut by release-please from conventional commits under this directory
  (tag `vitruvian-speaker-vX.Y.Z`, workflow `.github/workflows/vitruvian-speaker-release.yaml`, config in
  `release-please-config.json` and `.release-please-manifest.json` here). The version is stamped
  into `Sources/VitruvianSpeakerCore/Version.swift` and `Resources/Info.plist` together and a test
  fails if they drift — do not bump either by hand outside a release.
- **Secrets never in git.** `VITRUVIAN_SPEAKER_GOOGLE_CLIENT_ID` / `VITRUVIAN_SPEAKER_GOOGLE_CLIENT_SECRET`
  come from the environment locally and from repository secrets in CI; the Slack token lives
  only in the Bitwarden vault and in this Mac's secrets file.
- **`~/.gemini/speaker_broadcast.json` is the app's settings, and a shared contract.** This app
  watches it, the Android remote's Mac helper asks the chosen program via `--state`/`--apply` (and no
  longer reads or writes this file directly), and local tooling reads it. Changing its schema touches
  all of them; keep old keys readable. The Vitruvian extension does not use it: it has its own
  `settings.json` with exactly the same schema.
- **The extension's files are in its data folder**, not under `~/.gemini/`:
  `~/Library/Application Support/com.vitruviansoftware.vitruvian/ToolData/dev.vitruvian.speaker/`
  holds `settings.json`, `secrets.json` (0600), `history.json` and `speaker_monitor_status.json`,
  in the same formats as the app's files. The same engine reads both, told which set of files to
  use (`Profile`). Do not point the extension at the app's files, or the app at the extension's; the only
  crossing is the copy the person asks for in the choice (`DoorCopy`).
- **`~/.gemini/speaker_door.json` is the one file both read.** It records which of the app and the
  extension the person chose (`chosen`), and the extension's program, data folder and version
  (the `extension` block, written by the extension each time it starts). Writers merge under its
  own lock; never replace it blind. Until someone picks, the app runs as today and the extension
  waits. After a pick, only the chosen one speaks, reads chat and answers the Claude Code hook.
- **`~/.gemini/speaker_monitor_status.json` is the app's to write.** The running app reports its
  chat monitor there (`ChatMonitorStatusFile`) and takes Start/Stop over a distributed notification
  (`ChatMonitorControlNotice`, also `VitruvianSpeaker --chat-monitor start|stop`). The extension writes
  its own `speaker_monitor_status.json` in its data folder, and its tool reads only that one. A
  reader must treat "running" from an app that is not running as stopped: a crash leaves the file
  behind.
- **Google's gates are not bugs.** The Home API needs a Google Home Premium Advanced plan — an
  empty speaker list after a successful sign-in is that. Home and Chat refuse a single consent,
  so they are separate sign-ins.
- **Honesty rules hold in code:** an offline speaker shows offline, not its last level;
  "Whole Home" has no single volume; the slider waits for the speaker to confirm; "announce at
  a set volume" only restores the level if nobody changed it meanwhile.
- **`testdata/` holds shared rulebook test cases and the golden state fixture.**
  - **What is in it:** It holds shared JSON cases for catalog rules and the golden `state_v1.json` fixture; see `apps/desktop/vitruvian-speaker/testdata/README.md` for the file list.
  - **Who reads it:** Swift engine tests (`//apps/desktop/vitruvian-speaker:VitruvianSpeakerTests` via `SharedRulebookCasesTests.swift`) load every case file, while the Rust Mac helper tests (`//apps/mobile/android-remote/macagent:macagent_test`) read only `state_v1.json`. Having Android remote Kotlin tests (`//apps/mobile/android-remote:derive_test` and `//apps/mobile/android-remote:wire_test`) read testdata is follow-up work. A changed rule changes its case first.

## Distribution & Parity Touchpoints Checklist

Vitruvian Speaker spans both local macOS runtimes and remote clients. The rule now lives in ONE place: a new setting is added to `SettingsCatalog` (label, kind, choices, limits, visibility) and changed through `SettingsActions`; the app's SwiftUI screens and the extension's pages only lay it out. Whenever adding or modifying a setting, secret (`SecretStore.swift`), door path (`Door.swift` / `Profile.swift`), or CLI flag, verify parity across **all** touchpoints below before declaring the work complete:

1. **Core Engine (`Sources/VitruvianSpeakerCore/`)** — The rule lives in one place: add the setting to `SettingsCatalog.swift` (label, kind, choices, limits, visibility), change it through `SettingsActions.swift`, and expose it on the machine-readable `--state --json` / `--apply --json '<changes>'` CLI contract in `StateContract.swift` (operations: `set`, `setDefaultSpeaker`, `removeSpeaker`, `setSecret`, `snooze`, `setNetwork`, `setReadAnyway`, `importAntigravity`, `agentHook`, `saveOAuthClient`, `clearChatToken`, `reset`, `switchTo`). `testdata/` holds shared JSON cases read by `Tests/VitruvianSpeakerTests/SharedRulebookCasesTests.swift` plus the golden state fixture `testdata/state_v1.json`; a changed rule changes its case first. Also covers `Models.swift` (`SpeakerConfig`, including `speak_phone`, `phone_pause_media`, `phone_headphones_only`), `SecretStore.swift`, `GeminiSpeaker.swift`, `LocalSpeaker.swift`, `PhoneSpeaker.swift`, `Announcer.swift`, `AnnouncementStylist.swift`, `CommandLine.swift`, `AgentIntegration.swift`, `AgentPlugins.swift`, `AgentHooks.swift`, `AppStartup.swift`, `AppSwitch.swift`, `Door.swift`, `DoorCopy.swift`, and `Profile.swift`.
2. **Standalone macOS Menu-Bar App (`Sources/VitruvianSpeaker/`)** — The SwiftUI screens only lay out what `SettingsCatalog` defines; no rules live here. `App.swift`, `MenuBarView.swift`, `SettingsView.swift`, `DoorWindow.swift` (packaged via `bazel run //apps/desktop/vitruvian-speaker:publish` to `/Applications/Vitruvian Speaker.app`, data in `~/.gemini/` and `~/Library/Application Support/Vitruvian Speaker/secrets.json`).
3. **Vitruvian Extension / Daemon (`Sources/VitruvianSpeakerToolCore/` & `Sources/VitruvianSpeakerTool/`)** — The extension's pages only lay out what `SettingsCatalog` defines; no rules live here. `VitruvianSpeakerTool.swift`, `Pages.swift`, `ExtensionSide.swift`, `main.swift`, `tool/vitruvian-tool.json` (packaged via `bazel run //apps/desktop/vitruvian-speaker:zip-tool` to `~/Library/Application Support/com.vitruviansoftware.vitruvian/Tools/dev.vitruvian.speaker/bin/tool`, data in `ToolData/dev.vitruvian.speaker/`).
4. **Vitruvian Host External Tool Store (`apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/Platform/External/`)** — `ExternalToolStore.swift`, `ToolHost.swift`, `CatalogueWatch.swift`, and tool protocol (`packages/vitruvian-sdk/`).
5. **Android Remote — Mac Daemon (`apps/mobile/android-remote/macagent/`)** — `rs/src/vitruvian-speaker.rs`, `macagent_test`, and `API.md` (resolves active door from `~/.gemini/speaker_door.json` and exposes `/v1/speaker`, `/v1/speaker/volume`, `/v1/speaker/say`, and `/v1/speaker/phone-say`). The helper maps `--state` and `--apply` on the chosen program (minimum Vitruvian Speaker 1.41.0) and its tests check the mapping against `testdata/state_v1.json`. A new setting reaches the helper with no helper change when it is a catalog setting.
6. **Android Remote — Mobile App (`apps/mobile/android-remote/src/main/kotlin/dev/vitruvian/remote/state/`)** — `Wire.kt` (`VitruvianSpeakerWire`), `AgentClient.kt` (`AgentVitruvianSpeaker`), `Derive.kt`, `RemoteState.kt` (`vitruvianSpeakerRows`), `MockHost.kt`, `DeriveTest.kt`, and `WireTest.kt`. Takes every Vitruvian Speaker label, choice, limit and show/hide rule from the catalog the helper passes through (`settings[]` in `GET /v1/speaker`), so a new catalog setting needs no phone change. The phone's only rewording is "Your phone" → "This phone"; a guard test in `DeriveTest.kt` fails if a local copy of a Vitruvian Speaker list or label comes back. With no catalog (helper or Vitruvian Speaker too old) it shows one sentence and no settings. A catalog setting the phone hasn't given a hand-made row is drawn automatically under "Other settings" (`placed(key)` records hand-drawn keys; `Derive.genericKeys` draws the rest), so a new setting shows on the phone with no phone release.

**Adding a control that is not a catalog setting** (a new `--apply` op, CLI flag or helper action): add it to `testdata/controls.json` with `"phone": "supported"` or `"excluded"` plus a `reason`. Three tests enforce it: `ControlsManifestTests` (every `supportedOperations` op is listed), `macagent_test` (every supported entry is reachable through a real phone request) and `derive_test` (every supported entry has a phone control, `VitruvianSpeakerControls`). Design: `docs/superpowers/specs/2026-11-11-speaker-phone-parity.md`.
7. **Coding Agent Integrations, Packaging & Registries** — Claude Code (`~/.claude/settings.json`), Antigravity (`~/.gemini/antigravity/plugins/vitruvian-speaker/`), OpenCode (`~/.config/opencode/plugins/vitruvian-speaker.ts`), `bazel run //apps/desktop/vitruvian-speaker:sync-secrets`, version lockstep (`tool_version_test` across `Version.swift`, `Info.plist`, `tool/vitruvian-tool.json`, `release-please-config.json`), and external distribution (`vitruvian-extensions` & `homebrew-tap`).
8. **Cross-component PR scope (`release-scope` CI check)** — `release-please` maps each directory to a separate component (`vitruvian-speaker`, `vitruvian`, `android-remote`, `vitruvian-sdk`). Split changes touching `apps/desktop/vitruvian-speaker/`, `apps/desktop/vitruvian-atrium/`, and `apps/mobile/android-remote/` into per-component PRs (or declare `Releases:`) so `release-scope` passes.


