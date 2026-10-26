<!--
Copyright 2026 VitruvianSoftware
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Courier.app

The SwiftUI app. It runs and supervises the Go engine (`../engine`, bundled as `Contents/Helpers/courier-engine`) and talks to it over the protocol in `../protocol`. `BUILD` and `Package.swift` list the same targets; `scripts/test.sh` runs the tests under SwiftPM.

## Courier's Telegram app ID

Telegram wants every app to register its own `api_id` and `api_hash`. Courier is built for people who will never type them, so a finished app carries Courier's own, and Telegram goes straight to its QR code.

**Where it lives.** Two files in the gitignored secret store (`tools/sync-env-secrets/README.md`), which is backed up in Bitwarden:

```
tools/sync-env-secrets/secrets/courier-release/COURIER_TELEGRAM_API_ID
tools/sync-env-secrets/secrets/courier-release/COURIER_TELEGRAM_API_HASH
```

The release uses the same two names as secrets of the `courier-release` GitHub Environment.

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
  - `com.apple.security.device.audio-input`: recording voice notes (milestone 4.5b). macOS still asks the person first.
  - `com.apple.security.personal-information.addressbook`: matching people with your Contacts and "Save to Contacts" (4.5a). macOS still asks first.
  - `com.apple.security.personal-information.calendars`: the Calendar pane and "Add to Calendar" (4.5a). macOS still asks first.
  `inject_app_credentials_test` fails if any of the three goes missing. A new entitlement goes in that file and one line here: what it is and why.

**First install after ad hoc builds.** Keychain items saved by earlier ad hoc builds had an access rule tied to that build's binary. The first Developer ID-signed Courier may ask once for permission to read them; click Always Allow. From then on, rebuilds carry the same team signature and do not ask.

Not done here: notarization, and the DMG. Those are milestone 6's, through the desktop pipeline (`--options runtime --timestamp` and the nested signing above are what it will build on).

```sh
bazel run --config=macos-app //apps/desktop/courier/app:install               # into /Applications
bazel run --config=macos-app //apps/desktop/courier/app:install -- --dest DIR # or somewhere else
```

`:install` unpacks `Courier.zip`, runs the injector with `--allow-missing`, quits the Courier installed at the destination (matched by its exact path; if it has not quit in ten seconds its processes get SIGTERM, and after thirty the install gives up), moves the old app aside, puts the new one in, and checks it with `codesign --verify --deep --strict`. If anything fails, or the install is interrupted (Ctrl-C, SIGTERM), the old app is put back; and if an install was killed outright and left it aside, the next run puts it back first. The injector finds the store from the checkout you ran the command in (`BUILD_WORKSPACE_DIRECTORY`), and from a git worktree it uses the main checkout's store.

**What the app does with it.** At launch the engine gets, in order: the built-in `TelegramApp.plist` if it is there and fits, else a pair the person saved in the Keychain, else nothing. A development build without the plist shows a keys screen as the first step of linking Telegram, saves what is typed to the Keychain, restarts the engine, waits for Telegram to start, and goes on to the QR code. A build with the plist never shows that screen.

Out of scope for now: a saved pair that Telegram itself later rejects shows as an ordinary Telegram failure, not as a prompt for new keys.
