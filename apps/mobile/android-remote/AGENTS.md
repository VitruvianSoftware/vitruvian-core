# Vitruvian Remote (android-remote) — agent guide

> Scoped to `apps/mobile/android-remote/`. Repo-wide rules live in the root
> [`AGENTS.md`](../../../AGENTS.md); the developer SOP is
> [`CONTRIBUTING.md`](../../../CONTRIBUTING.md), which wins on any conflict. This app's own
> [`CONTRIBUTING.md`](CONTRIBUTING.md) holds the house rules in full; this file is the short
> version for coding agents.

## What this is

A Kotlin / Jetpack Compose Android app: a remote control and observability console for a Mac,
shaped for a foldable (folded, unfolded and tabletop postures). Two transports: Bluetooth HID
(nothing installed on the Mac) and [`macagent/`](macagent/README.md), a Go daemon on the Mac
reached over Tailscale. The app ↔ daemon contract is [`macagent/API.md`](macagent/API.md).
Every colour, size and font comes from `//packages/design-system-android`; this app defines
no design value of its own.

## Build, test, run

- **Toolchain.** The Android SDK is the one non-hermetic toolchain in the monorepo: set
  `ANDROID_HOME` to a local SDK with the API 35 platform and build-tools.
  `bazel run //apps/mobile/android-remote:doctor` checks bazel and git only — it has no SDK probe;
  `bazel build //apps/mobile/android-remote:app` fails with a clear message when `ANDROID_HOME`
  is unset. The NDK is hermetic (`//tools/android_ndk`).
- **Build and install.** `bazel build //apps/mobile/android-remote:app`, then
  `adb install -r bazel-bin/apps/mobile/android-remote/app.apk`. For wireless debugging's
  ephemeral ports use `bazel run //tools/adb-connect`.
- **Tests.** `bazel test //apps/mobile/android-remote/...` runs the `kt_jvm_test` targets
  (`hid_codes_test`, `format_test`, `derive_test`, `wire_test`, `wake_on_lan_test`,
  `bridge_policy_test`, `tuning_test`) and the `macagent` Go tests. `:boot_smoke` installs the
  APK on an attached device or emulator and launches `MainActivity`; it is `large` and needs
  that device, so run it by explicit label.
- **Daemon.** `macagent/BUILD` carries the Go binary plus its `install` and `pair` helpers;
  the six-digit pairing code gates the macros, console and clipboard endpoints.

## House rules

- **Never hardcode a design value.** No `Color(...)`, no bare `.dp` spacing, no font size off
  the ramp. Missing values go in `packages/design-system/src/tokens.json` and reach Kotlin
  through the generator. The Fibonacci scale (`Space.s1`…`s8`) is the only source of padding.
- **Never edit `VitruvianTokens.kt`.** It is generated;
  `//packages/design-system-android:tokens_are_current` fails the build if you do.
- **New components belong in the design system, not here.** This app is screens, state and
  wiring (`state/`, `shell/`, `screens/`, `overlays/`).
- **Check all three postures** before calling a UI change done.
- **Be honest on screen.** Every number is measured or labelled unavailable; the Home tag is
  `LIVE`, `SIMULATED` (running on `state/MockHost.kt`) or `UNREACHABLE` — never a guess.
- **`BUILD` is hand-authored.** Gazelle has no Kotlin/Android extension in this repo
  (`# gazelle:ignore`), so a new `.kt` file must be added to the right target yourself. The
  package defaults to app-private visibility (inter-app boundary); keep it that way.
- **Cross-workspace contracts.** A change to `macagent/API.md` is a change to the app and the
  daemon in one PR. The HomeSpeaker module reads and rewrites `~/.gemini/speaker_broadcast.json`
  through the daemon, the same file `apps/desktop/home-speaker` watches — keep old keys readable.
- **Not mirrored.** Unlike `devx`, `mcp-slack` and `nexus-agent` there is no Copybara export;
  this directory is the only place the app is edited.

## Docs

`docs/` is a TechDocs site (`mkdocs.yml`: index, macagent API, phone bridge);
`bazel run //tools/techdocs:check` must still compile it after a docs change.
