# SentryLite

## What it gives you

A lightweight, Foundation-only Swift Sentry client (`SentryLite.start`, `SentryLite.capture`) that parses Sentry DSNs, installs an uncaught exception handler, and posts error/message events over `URLSession` without pulling in the full Sentry Cocoa SDK.

## When to use it

- Adding crash and error telemetry to macOS Swift apps or Vitruvian Atrium Swift extensions without adding external Cocoa/SPM dependencies.

## When not to use it

- Android or Kotlin apps; use [`//packages/android-crash-privacy`](../android-crash-privacy/README.md) instead.
- Apps needing full native crash symbolication, session replay, profiling, or distributed tracing (SentryLite captures `NSException`, `Error`, and message events only).

## Example

From `apps/desktop/vitruvian-code/macos/Sources/VitruvianCode/App.swift:21-59`:

```swift
#if canImport(SentryLite)
import SentryLite
#endif
// …
    init() {
#if canImport(SentryLite)
        SentryLite.start(
            dsn: "https://259b457f48de7e350f152674cb029dda@sentry-ingest.ipv1337.dev/8",
            release: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
            tags: ["app": "vitruvian-code", "platform": "macos"]
        )
#endif
    }
```

## Depend on it

`//packages/sentry-lite:SentryLite`

## Constraints

- Apple/macOS toolchain only (`APPLE_TOOLCHAIN_ONLY`), requires `--config=macos-app` when building with Bazel on macOS.
- Foundation-only with zero third-party dependencies; callers that also build via standalone `Package.swift` guard imports with `#if canImport(SentryLite)`.
