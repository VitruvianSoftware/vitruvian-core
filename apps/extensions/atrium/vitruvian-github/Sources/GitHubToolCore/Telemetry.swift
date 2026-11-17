// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
#if canImport(SentryLite)
import SentryLite
#endif

/// Fail-open, non-blocking Sentry telemetry for `vitruvian-github`.
/// Guarded by `#if canImport(SentryLite)` so standalone `Package.swift` builds stay compatible.
public enum GitHubToolTelemetry {
    public static let defaultDSN = "https://466d926919488c1b0dde293066f2cd09@sentry-ingest.ipv1337.dev/19"

    /// Initializes Sentry with `SENTRY_DSN` from the environment or `defaultDSN`.
    /// Never throws or blocks.
    public static func start(dsn: String = defaultDSN, release: String = ToolVersion.current) {
        #if canImport(SentryLite)
        SentryLite.start(
            dsn: dsn,
            release: release,
            tags: ["app": "vitruvian-github", "platform": "macos"]
        )
        #endif
    }

    /// Captures an error asynchronously without throwing or blocking.
    public static func capture(error: Error, tags: [String: String] = [:], extra: [String: String] = [:]) {
        #if canImport(SentryLite)
        SentryLite.capture(error: error, tags: tags, extra: extra)
        #endif
    }
}
