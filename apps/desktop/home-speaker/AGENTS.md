# HomeSpeaker (home-speaker) — agent guide

> Scoped to `apps/desktop/home-speaker/`. Repo-wide rules live in the root
> [`AGENTS.md`](../../../AGENTS.md); the developer SOP is
> [`CONTRIBUTING.md`](../../../CONTRIBUTING.md), which wins on any conflict.

## What this is

A Swift macOS menu-bar app (macOS 14+, universal binary) that reads things aloud on Google Home
speakers and Nest displays through Google's hosted Home API: a one-line summary of each Claude
Code reply, new Slack or Google Chat messages, or typed text. Two modules:
`Sources/HomeSpeakerCore` (logic, unit-tested, no UI) and `Sources/HomeSpeaker` (the app).
It is scriptable — `HomeSpeaker --say`, `--volume`, `--set-volume 0-100`, `--mute`, `--unmute`.

## Build, test, run

- **Inner loop is SwiftPM**, from this directory: `./scripts/test.sh` (wraps `swift test` with
  the swift-testing plugin path the Command Line Tools toolchain needs — bare `swift test`
  fails without Xcode), then `swift build && .build/debug/HomeSpeaker`.
- **What CI actually runs** (`macos-build` lane in `.github/workflows/ci.yaml`, when
  `apps/desktop/home-speaker/**` changes): `bazel build --config=macos-app
  //apps/desktop/home-speaker/... :HomeSpeaker` as a compile check, `./scripts/test.sh` for the
  unit tests, and `bazel test --config=macos-app //apps/desktop/home-speaker:sync_secrets_test`.
  `:HomeSpeakerTests` exists as a Bazel target but CI never runs it.
- **What ships is SwiftPM, not Bazel:** the release workflow runs `scripts/publish.sh`, which
  builds with `swift build -c release --arch arm64 --arch x86_64` and bundles the universal .app.
- **The app, test and `sync_secrets_test` targets are `manual` and macOS-only**, so none of them
  appears in `bazel test //...` or in the Linux presubmit plan (`sync-secrets` and the two
  libraries are ordinary targets). Run the steps above on a Mac before pushing — a green Linux
  sweep proves nothing about this app.
- **Release package exactly as CI does:** `./scripts/publish.sh --dry-run` (universal .app,
  zip, sha256). Slack token onto this Mac from Bitwarden:
  `bazel run //apps/desktop/home-speaker:sync-secrets` for the app, or
  `bazel run //apps/desktop/home-speaker:sync-secrets -- --extension` for the extension's
  `secrets.json` (found through `speaker_door.json`; it stops and writes nothing if that is missing).

## Conventions & landmines

- **Releases** are cut by release-please from conventional commits under this directory
  (tag `home-speaker-vX.Y.Z`, workflow `.github/workflows/home-speaker-release.yaml`, config in
  `release-please-config.json` and `.release-please-manifest.json` here). The version is stamped
  into `Sources/HomeSpeakerCore/Version.swift` and `Resources/Info.plist` together and a test
  fails if they drift — do not bump either by hand outside a release.
- **Secrets never in git.** `HOMESPEAKER_GOOGLE_CLIENT_ID` / `HOMESPEAKER_GOOGLE_CLIENT_SECRET`
  come from the environment locally and from repository secrets in CI; the Slack token lives
  only in the Bitwarden vault and in this Mac's secrets file.
- **`~/.gemini/speaker_broadcast.json` is the app's settings, and a shared contract.** This app
  watches it, the Android remote's HomeSpeaker module rewrites it through `macagent`, and local
  tooling reads it. Changing its schema touches all of them; keep old keys readable. The Vitruvian
  extension does not use it: it has its own `settings.json` with exactly the same schema.
- **The extension's files are in its data folder**, not under `~/.gemini/`:
  `~/Library/Application Support/com.vitruviansoftware.vitruvian/ToolData/dev.vitruvian.homespeaker/`
  holds `settings.json`, `secrets.json` (0600), `history.json` and `speaker_monitor_status.json`,
  in the same formats as the app's files. The same engine reads both, told which set of files to
  use (`Profile`). Never point the extension at the app's files, or the app at the extension's.
- **`~/.gemini/speaker_door.json` is the one file both read.** It records which of the app and the
  extension the person chose (`chosen`), and the extension's program, data folder and version
  (the `extension` block, written by the extension each time it starts). Writers merge under its
  own lock; never replace it blind. Only the chosen one speaks on its own.
- **`~/.gemini/speaker_monitor_status.json` is the app's to write.** The running app reports its
  chat monitor there (`ChatMonitorStatusFile`) and takes Start/Stop over a distributed notification
  (`ChatMonitorControlNotice`, also `HomeSpeaker --chat-monitor start|stop`). A reader must treat
  "running" from an app that is not running as stopped: a crash leaves the file behind.
- **Google's gates are not bugs.** The Home API needs a Google Home Premium Advanced plan — an
  empty speaker list after a successful sign-in is that. Home and Chat refuse a single consent,
  so they are separate sign-ins.
- **Honesty rules hold in code:** an offline speaker shows offline, not its last level;
  "Whole Home" has no single volume; the slider waits for the speaker to confirm; "announce at
  a set volume" only restores the level if nobody changed it meanwhile.
