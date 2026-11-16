# android-crash-privacy

Shared privacy-hardened Sentry initialization and crash-report scrubbing for
Android apps in this monorepo (`//packages/android-crash-privacy`).

## What is here

| Symbol | Purpose |
|---|---|
| `DeviceField` | Opt-in allowlist of device and app fields (`MODEL`, `SCREEN`, `MEMORY`, `OS_VERSION`, `APP_VERSION`). |
| `PrivateSentryDevice` | Caller-supplied device metrics kept only for the selected `DeviceField` entries. |
| `configurePrivateSentry` | Configures `SentryAndroidOptions` with all auto-breadcrumbs, ANR/NDK/tombstone, screenshots, tracing, profiling, replay, logs, metrics, OTel, and extra contexts turned off, plus address scrubbing in `beforeSend`. |
| `disableCrashReporting` | Sets `shutdownTimeoutMillis = 0`, closes Sentry, and removes `<cacheDir>/sentry`. |
| `clearSentryCache` | Recursively deletes `<cacheDir>/sentry` without touching sibling cache directories. |
| `scrubCrashMessage` | Replaces URLs, IPv4/IPv6 literals, host:port pairs, and dotted hostnames with `<address>` while leaving Java/Kotlin exception types untouched. |

## Per-app field sets

- **Vitruvian Remote** (`apps/mobile/vitruvian-remote`): keeps `MODEL`, `SCREEN`, `MEMORY`, `OS_VERSION`, and `APP_VERSION` (`vitruvian-remote@<version>`), matching its Privacy notice.
- **Vitruvian Watch** (`apps/mobile/vitruvian-watch`) and **Vitruvian Wand** (`apps/suites/vitruvian-wand/android`): keep `APP_VERSION` only (`<app>@1.0` / `vitruvian-wand@0.1.0`), stripping all Android device and OS contexts and tags so events carry no more than plain Java `io.sentry:sentry:7.14.0` sent on `main`.
