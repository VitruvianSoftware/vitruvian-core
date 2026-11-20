# android-crash-privacy

## What it gives you

Shared privacy-hardened Sentry initialization, device-field allowlisting (`DeviceField`, `PrivateSentryDevice`), cache clearing (`clearSentryCache`, `disableCrashReporting`), and crash-message address scrubbing (`scrubCrashMessage`) for Android apps in this monorepo.

## When to use it

- Initializing Sentry in any Android or Wear OS app (`vitruvian-remote`, `vitruvian-watch`, `vitruvian-wand`) so auto-breadcrumbs, ANR/NDK/tombstone dumps, screenshots, tracing, profiling, replay, and IP/hostname leaks are suppressed by default.

## When not to use it

- macOS Swift apps or extensions; use [`//packages/swift/SentryLite`](../swift/SentryLite/README.md) instead.
- Rust or Node.js services; use the standard Sentry crates/packages (`sentry` or `@sentry/node`) directly.

## Example

From `apps/mobile/vitruvian-watch/apps/common/src/main/kotlin/com/vitruviansoftware/watch/common/WatchSentry.kt:24-64`:

```kotlin
import dev.vitruvian.crashprivacy.DeviceField
import dev.vitruvian.crashprivacy.configurePrivateSentry
// …
import io.sentry.android.core.SentryAndroidOptions
import java.util.EnumSet

public object WatchSentry {
  // …
  public val KEPT_DEVICE_FIELDS: Set<DeviceField> = EnumSet.of(DeviceField.APP_VERSION)
  // …
  public fun configureOptions(
      options: SentryAndroidOptions,
      appName: String = "vitruvian-watch",
      dsn: String = DEFAULT_DSN,
  ) {
    configurePrivateSentry(
        options = options,
        dsn = dsn,
        keepDeviceFields = KEPT_DEVICE_FIELDS,
        release = "$appName@1.0",
        environment = "production",
    )
  }
}
```

## Depend on it

`//packages/android-crash-privacy:android-crash-privacy`

## Constraints

- Android/Kotlin library depending on `@maven//:io_sentry_sentry` and `@maven//:io_sentry_sentry_android_core` (unit-tested on JVM with `@androidsdk//:platforms/android-35/android.jar`).

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
- **Vitruvian Watch** (`apps/mobile/vitruvian-watch`) and **Vitruvian Wand** (`apps/suites/vitruvian-wand/android`): keep `APP_VERSION` only (`<app>@1.0` / `vitruvian-wand@0.1.0`), stripping all Android device and OS contexts and tags (`MODULE.bazel` currently pins `io.sentry:sentry:8.64.0`; `CrashPrivacyTest.kt:299-301` documents parity against the historical `io.sentry:sentry:7.14.0` baseline).
