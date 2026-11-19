// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Cheap counters the scroll benchmark (`ScrollBenchmarkTests`) reads: how many timeline rows had their body
/// evaluated, and how many per-row geometry callbacks ran. Off (a single Bool test per use) unless a test turns
/// `enabled` on, so the app pays nothing.
@MainActor
enum ScrollPerfCounters {
    static var enabled = false
    static var rowBodies = 0
    static var geometryCallbacks = 0

    @inline(__always)
    static func rowBody() {
        if enabled { rowBodies += 1 }
    }

    @inline(__always)
    static func geometryCallback() {
        if enabled { geometryCallbacks += 1 }
    }

    static func reset() {
        rowBodies = 0
        geometryCallbacks = 0
    }
}
