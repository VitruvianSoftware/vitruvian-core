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

**How they get into the app.** Not through Bazel: a Bazel output can land in the remote cache, and the ID must not. Bazel builds an app with no ID in it. `scripts/inject-app-credentials.sh <path/to/Courier.app>` then writes `Contents/Resources/TelegramApp.plist` (`api_id` an integer, `api_hash` a string) into the built app and signs the app again. It takes the values from `COURIER_TELEGRAM_API_ID` and `COURIER_TELEGRAM_API_HASH` in the environment if both are set, else from the store files above (`COURIER_SECRETS_DIR` names another folder). It checks them as the engine does and never prints them. With none, it says so and exits 1, unless `--allow-missing` is given: then it leaves the plist out and still signs the app. The signature is ad hoc, or the identity in `COURIER_SIGN_IDENTITY`.

```sh
bazel run --config=macos-app //apps/desktop/courier/app:install               # into /Applications
bazel run --config=macos-app //apps/desktop/courier/app:install -- --dest DIR # or somewhere else
```

`:install` unpacks `Courier.zip`, runs the injector with `--allow-missing`, quits the Courier installed at the destination, replaces it, and checks the result with `codesign --verify --deep --strict`.

**What the app does with it.** At launch the engine gets, in order: the built-in `TelegramApp.plist` if it is there and fits, else a pair the person saved in the Keychain, else nothing. A development build without the plist shows a keys screen as the first step of linking Telegram, saves what is typed to the Keychain, restarts the engine, waits for Telegram to start, and goes on to the QR code. A build with the plist never shows that screen.

Out of scope for now: a saved pair that Telegram itself later rejects shows as an ordinary Telegram failure, not as a prompt for new keys.
