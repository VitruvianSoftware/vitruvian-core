<!--
Copyright 2026 VitruvianSoftware
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Courier.app

The SwiftUI app. It runs and supervises the Go engine (`../engine`, bundled as `Contents/Helpers/courier-engine`) and talks to it over the protocol in `../protocol`. `BUILD` and `Package.swift` list the same targets; `scripts/test.sh` runs the tests under SwiftPM.

## Trying a change in a running app: the test copy

Unit tests can't show that a window really opens or a column really hides. To check that by hand, or with a script, run the test copy:

```sh
bazel run --config=macos-app //apps/desktop/courier/app:run_test_copy            # its data in $TMPDIR/courier-test-copy/data
bazel run --config=macos-app //apps/desktop/courier/app:run_test_copy -- --data DIR
bazel run --config=macos-app //apps/desktop/courier/app:run_test_copy -- --seed group-threads   # full of made-up chats
```

It is the same app, built as `:CourierTestCopy` with its own bundle identifier (`com.vitruviansoftware.courier.dev`) and name ("Courier Test Copy"), so it stays apart from the Courier you use:

- **Settings** (UserDefaults), the notification permission and the Login Items entry are its own, because macOS keys them by bundle identifier.
- **Data.** `run_test_copy` opens it with `COURIER_DATA_DIR` set, which the app hands to its engine. It refuses `~/Library/Application Support/Courier` as the folder. Even started some other way, the test copy never falls back to that folder: without `COURIER_DATA_DIR` it uses `~/Library/Application Support/Courier Test Copy` (`TestCopy` in `EngineLocation.swift`).
- **Keychain.** It keeps its Telegram keys under its own service, `com.vitruviansoftware.courier.dev.telegram`, so it never reads the installed app's.
- **The installed app** in `/Applications` is never touched: the copy is unpacked under `$TMPDIR/courier-test-copy/app`, and `run_test_copy` refuses an app whose bundle identifier isn't the test copy's. Both can run at once.

Without `--seed` it has no networks until you add one, so the Chat and Message items that need a chat are greyed out.

**Opening it full of chats.** `--seed NAME` opens it with the made-up chats of `../seed/scenarios/NAME.json`
(`group-threads`, `direct`, `long-content`, `multi-network`, `empty`; an unknown name lists them), so a change to how
chats look can be checked by hand or by screenshot without signing in to anything. Its data folder is
`$TMPDIR/courier-test-copy/seed-NAME`, emptied on every run, so each run starts from the scenario as written (with
`--data DIR` the folder is yours, and a scenario already played into it is not played again). The test copy bundles
`courier-engine-seeded`, the engine built with the `courierseed` tag: given `COURIER_SEED` (which `run_test_copy`
passes), it runs fake networks under the scenario's real network names instead of the real bridges, and plays the
scenario once. Without `COURIER_SEED` it is the ordinary engine. The released `:Courier` bundles the plain engine,
which holds none of this code: `:release_engine_has_no_seed_test` checks both apps. The scenario format is in
`../seed/README.md`, and the view tests draw the same files (`SeedScenarioSnapshotTests`).

Quit it from its menu, or `osascript -e 'tell application id "com.vitruviansoftware.courier.dev" to quit'`. Its menus can be driven by System Events (`click menu item "Settings…" of menu 1 of menu bar item "Courier Test Copy" of menu bar 1 of process "Courier Test Copy"`), which is how the menu bar was checked item by item.

## AI providers

Courier can draft replies, rewrite text in different tones, translate messages inline, and summarize chats (including the `/draft`, `/translate`, `/summarize`, and `/ai` slash commands). AI is turned off by default. Nothing leaves your Mac until you turn it on, and Courier never sends AI output on your behalf—everything lands in the composer or AI pane for you to review, edit, or discard.

Where each action lives:

- **Draft a reply** and **Rewrite…** (tones): the **+** menu in the message box, or type `/draft`. The result shows above your text with **Replace**, **Insert** and **Discard**.
- **Translate**: right-click a message. It uses *Preferred response language*; a submenu offers your other enabled languages.
- **Summarize**: the chat's ⓘ menu or the command bar (⌘J). The summary opens in the AI pane.
- **Talk to Type**: `⌘⇧D`, the **+** menu in the message box, or the command bar (⌘J). Words go in at the cursor.
- **Transcribe a voice note**: right-click the voice note or click **Transcribe** next to its waveform.

### Providers and setup

Pick a provider in **Settings ▸ AI**. Choosing one turns AI on; choosing **Off** turns it off.

- **On this Mac (stays local):**
  - **Apple Intelligence:** Built-in on macOS 26 or later on supported Macs.
  - **Ollama:** Install and run Ollama; Courier detects it automatically.
  - **LM Studio:** Install LM Studio, start its local server, and Courier detects it.
  - **Unsloth Studio:** Start Unsloth Studio and paste its API key in Settings ▸ AI.
- **Cloud (bring your own key):**
  - **Anthropic:** Create an API key at [console.anthropic.com](https://console.anthropic.com).
  - **Google AI Studio:** Create an API key at [aistudio.google.com](https://aistudio.google.com).
  - **OpenAI:** Create an API key at [platform.openai.com](https://platform.openai.com).
  - **OpenAI-compatible:** Enter your endpoint base URL and optional API key.

### Talk to Type and voice notes

Speak into the message box instead of typing (Talk to Type). Start it with `⌘⇧D`, the **+** menu in the message box, or the command bar (⌘J). Press **Stop** or `⌘⇧D` again to finish, or press `Esc` to cancel. Spoken text is inserted at the cursor without replacing your draft. Nothing is ever sent automatically.

Turn voice notes into readable text. Right-click any voice note or click **Transcribe** next to its waveform. You can also turn on automatic transcription in **Settings ▸ AI** (off by default). When enabled, Courier automatically transcribes voice notes sent by other people as they appear on screen.

Where audio goes:
- **On this Mac by default:** Speech is recognized locally using Apple speech recognition. Audio never leaves your Mac and is never sent to Apple's servers. This works even when AI providers are turned off.
- **OpenAI Whisper (optional):** Turn on the Whisper toggle in **Settings ▸ AI** to transcribe audio using OpenAI. This requires an OpenAI API key. Audio is sent to OpenAI only when this toggle is on.

### Privacy and key storage

- **Keys in Keychain only:** API keys are stored exclusively in the macOS Keychain, never in config files or logs. The test copy keeps its own separate Keychain store.
- **Minimal text only:** Courier sends only the text messages needed for the immediate action (for example, the last 30 text messages for drafting a reply or the last 100 for a summary). Attachments, photos, and files are never sent.
- **No background queries:** Courier never queries an AI model automatically. Every request happens only when you explicitly invoke an AI action. The one exception is *Automatically transcribe incoming voice notes*, which you turn on yourself: with Whisper off it stays on this Mac; with Whisper on, those voice notes are sent to OpenAI.

### Troubleshooting

| Issue | What to check |
|---|---|
| **Not running** | Start the local app. Ollama listens on `127.0.0.1:11434`, LM Studio on port `1234` with its local server turned on, and Unsloth Studio on ports `8888`–`8908`. Courier only treats a port as Unsloth Studio when Studio's own file for it exists in `~/.unsloth/studio` (or `$UNSLOTH_STUDIO_HOME`), so start Studio normally rather than serving a model some other way. Click **Refresh** in Settings ▸ AI. |
| **Needs key** | Enter and save your API key in Settings ▸ AI. Cloud providers and Unsloth Studio require a key before use. |
| **Bad key** | Verify the API key pasted into Settings ▸ AI is correct, active, and has not expired or been revoked. |
| **Rate limited** | You reached your provider's rate or quota limits. Wait a few moments or verify billing on your provider console. |
| **No network** | Check your Mac's internet connection for cloud models, or confirm localhost server connectivity for local models. |

## Courier's Telegram app ID

Telegram wants every app to register its own `api_id` and `api_hash`. Courier is built for people who will never type them, so a finished app carries Courier's own, and Telegram goes straight to its QR code.

**Where it lives.** Two files in the gitignored secret store (`tools/sync-env-secrets/README.md`), which is backed up in Bitwarden:

```
tools/sync-env-secrets/secrets/courier-release/COURIER_TELEGRAM_API_ID
tools/sync-env-secrets/secrets/courier-release/COURIER_TELEGRAM_API_HASH
```

The release uses the same two names as secrets of the `courier-release` GitHub Environment, which `infrastructure/pulumi/platform/repo-config` declares (only `main` and `courier-v*` tags may deploy to it) and `bazel run //tools/sync-env-secrets:apply -- courier-release` fills from this store.

**How to set them.** Register Courier's app at my.telegram.org (API development tools), then put each value in the store. The safe way, which fetches the store first so nothing already in Bitwarden is lost, is:

```sh
bazel run //tools/sync-env-secrets:set -- courier-release COURIER_TELEGRAM_API_ID
bazel run //tools/sync-env-secrets:set -- courier-release COURIER_TELEGRAM_API_HASH
```

Or create the two files by hand and run `bazel run //tools/sync-env-secrets:bw-push`. On another Mac, `bazel run //tools/sync-env-secrets:bw-pull` brings them down.

**How they get into the app.** Not through Bazel: a Bazel output can land in the remote cache, and the ID must not. Bazel builds an app with no ID in it. `scripts/inject-app-credentials.sh <path/to/Courier.app>` then writes `Contents/Resources/TelegramApp.plist` (`api_id` an integer, `api_hash` a string) into the built app and signs the app again. It takes the values from `COURIER_TELEGRAM_API_ID` and `COURIER_TELEGRAM_API_HASH` in the environment if both are set, else from the store files above (`COURIER_SECRETS_DIR` names another folder). It checks them as the engine does and never prints them. With none, it says so and exits 1, unless `--allow-missing` is given: then it leaves the plist out and still signs the app.

Keeping the ID out of Bazel is about the build pipeline (no remote-cache entry holding it), not about hiding it from users: the `api_hash` of an app that ships is not a secret, and anyone can read it out of the app.

### Signing

The injector signs the app after it writes the plist, and it signs it the way the Vitruvian desktop app is signed. The point in practice: a Courier installed on this Mac has the same signature every time it is rebuilt, so macOS treats each new build as the same app. Keychain items (the saved sign-ins) and the privacy approvals you gave it carry over, and Gatekeeper sees a real developer's name instead of an unsigned app.

- **Which identity.** `COURIER_SIGN_IDENTITY` if it is set (`-` forces an ad hoc signature). Otherwise the first "Developer ID Application" identity in the login keychain. Otherwise ad hoc, which is what CI has. The script prints which one it used ("Signed ... with Developer ID (team ...)" or "Signed ... ad hoc"), and nothing secret.
- **Inside out.** The engine (`Contents/Helpers/courier-engine`, identifier `com.vitruviansoftware.courier.engine`) is signed first, then the app with `Resources/Courier.entitlements`. No `--deep` is used to sign (`codesign --verify --deep --strict` still checks the result). Extended attributes are stripped first.
- **Hardened runtime and timestamp.** With an identity, both signatures carry `--options runtime --timestamp`, which notarization needs. The timestamp comes from Apple's server, so a failed signing is tried up to three times. Ad hoc gets neither.
- **Attributes.** Both signatures also pass `--strip-disallowed-xattrs`, so an attribute that cannot be sealed (a download's quarantine flag, say) is dropped instead of failing the signing or, later, notarization.
- **Extra flags.** `COURIER_SIGN_FLAGS` adds flags to both signatures, split on spaces.
- **Entitlements.** `Resources/Courier.entitlements` holds only what the hardened runtime needs before macOS will even ask the person. Courier is not sandboxed (it ships directly, not through the Mac App Store), and its engine, a Go program with Signal's Rust library linked in, runs under the hardened runtime without any exception. Without these, the hardened runtime refuses the resource silently, with no prompt:
  - `com.apple.security.device.audio-input`: recording voice notes (milestone 4.5b) and Talk to Type. macOS still asks the person first.
  - `com.apple.security.personal-information.addressbook`: matching people with your Contacts and "Save to Contacts" (4.5a). macOS still asks first.
  - `com.apple.security.personal-information.calendars`: the Calendar pane and "Add to Calendar" (4.5a). macOS still asks first.
  `inject_app_credentials_test` fails if any of the three goes missing. A new entitlement goes in that file and one line here: what it is and why.

**First install after ad hoc builds.** Keychain items saved by earlier ad hoc builds had an access rule tied to that build's binary. The first Developer ID-signed Courier may ask once for permission to read them; click Always Allow. From then on, rebuilds carry the same team signature and do not ask.

Notarization and the DMG are the release's, below.

### Releases

A release goes through the desktop pipeline, the same way as HomeSpeaker. release-please opens a release PR from conventional commits under `apps/desktop/courier/` (config: `../release-please-config.json`; the version lives in `version.bzl`). When that PR merges, `.github/workflows/courier-release.yaml` runs, on a Mac:

```sh
bazel run //apps/desktop/courier/app:publish              # with RELEASE_TAG=courier-vX.Y.Z, in CI
bazel run //apps/desktop/courier/app:publish -- --dry-run # locally: package and check, publish nothing
```

It builds the app and the engine for arm64 and x86_64 (`--macos_cpus=arm64,x86_64`; a plain build stays one-CPU), refuses an app or engine that lacks either, adds the Telegram app ID, and hands the app to `//tools/desktop-package`: Developer ID signing (engine, then app, hardened runtime, `Resources/Courier.entitlements`), notarization, the universal, arm64 and x86_64 DMGs, the ZIP, checksums, the GitHub Release upload and the Homebrew cask (`vitruviansoftware/tap/courier`). The publishing job runs in the `courier-release` environment, for the Telegram app ID; the Developer ID and notary key are repository secrets. A real release refuses to start without the Telegram app ID or the notary key; a dry run needs neither and leaves everything in `../dist/`. `scripts/src/publish.rs` lists what it reads.

```sh
bazel run --config=macos-app //apps/desktop/courier/app:install               # into /Applications
bazel run --config=macos-app //apps/desktop/courier/app:install -- --dest DIR # or somewhere else
```

`:install` unpacks `Courier.zip`, runs the injector with `--allow-missing`, quits the Courier installed at the destination (matched by its exact path; if it has not quit in ten seconds its processes get SIGTERM, and after thirty the install gives up), moves the old app aside, puts the new one in, and checks it with `codesign --verify --deep --strict`. If anything fails, or the install is interrupted (Ctrl-C, SIGTERM), the old app is put back; and if an install was killed outright and left it aside, the next run puts it back first. The injector finds the store from the checkout you ran the command in (`BUILD_WORKSPACE_DIRECTORY`), and from a git worktree it uses the main checkout's store.

**What the app does with it.** At launch the engine gets, in order: the built-in `TelegramApp.plist` if it is there and fits, else a pair the person saved in the Keychain, else nothing. A development build without the plist shows a keys screen as the first step of linking Telegram, saves what is typed to the Keychain, restarts the engine, waits for Telegram to start, and goes on to the QR code. A build with the plist never shows that screen.

Out of scope for now: a saved pair that Telegram itself later rejects shows as an ordinary Telegram failure, not as a prompt for new keys.

### Updates

A released Courier updates itself (Settings ▸ About ▸ Updates; Courier ▸ Check for Updates…). It checks when it opens and once a day, unless that is turned off there. The check lists the `courier-v*` tags the way `git ls-remote` does, not through GitHub's rate-limited API, and offers the newest plain release newer than the one running. Installing downloads the universal DMG and refuses it unless it matches the `.sha256` the release publishes beside it, the DMG and the app inside carry Courier's Developer ID (bundle ID `com.vitruviansoftware.courier`, team `Q5MH753M3F`), Gatekeeper accepts the app as notarized, and its version is the tag's. The new app is copied beside the old one; a small script waits for Courier to quit, swaps them (putting the old one back if that fails) and opens Courier again. `Sources/CourierCore/Updates.swift` has the details; its tests answer from a fake, so none reaches the network. A Courier in a folder the user can't write to says so and points at the release page instead.
