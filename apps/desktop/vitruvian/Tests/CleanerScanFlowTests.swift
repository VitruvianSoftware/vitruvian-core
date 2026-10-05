// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The production cleaner scans and resets with recorded category scans and
/// a manual queue for both its background work and what it hands back. No
/// file system locations are read.
enum CleanerScanFlowTests {
    /// Background work and main-queue handoffs wait here until drained, in
    /// the order they were queued. Only the test's own thread touches it.
    nonisolated final class Queue: @unchecked Sendable {
        var pending: [() -> Void] = []
        func drain() {
            while !pending.isEmpty { pending.removeFirst()() }
        }
    }

    /// The categories scanned, in order. Only the test's own thread touches it.
    nonisolated final class Record: @unchecked Sendable {
        var scanned: [CleanerSupport.Category] = []
        var onScan: (@MainActor (CleanerSupport.Category) -> Void)?
    }

    static func run(_ suite: TestSuite) {
        let queue = Queue()
        let record = Record()
        let scanning = JunkCleaner.Scanning(
            installed: { [] },
            screenshotSearch: { ([], 30) },
            category: { category, _, _, _ in
                record.scanned.append(category)
                // The manual queue runs this on the test's thread.
                MainActor.assumeIsolated { record.onScan?(category) }
                return [JunkCleaner.Item(url: URL(fileURLWithPath: "/fixture/\(category.rawValue)"),
                                         category: category, size: 1, detail: "", recommended: false)]
            },
            background: { work in queue.pending.append(work) },
            main: { work in queue.pending.append { MainActor.assumeIsolated { work() } } })
        let cleaner = JunkCleaner(scanning: scanning)
        let all = CleanerSupport.Category.allCases
        defer {
            queue.pending = []
            record.onScan = nil
            record.scanned = []
            cleaner.reset()
        }

        cleaner.scan(attended: true)
        queue.drain()
        suite.expect(record.scanned == all && cleaner.phase == .results && cleaner.items.count == all.count,
                     "an uninterrupted scan visits every category and delivers its results")

        cleaner.reset()
        record.scanned = []
        cleaner.scan(attended: true)
        cleaner.reset()
        queue.drain()
        suite.expect(record.scanned.isEmpty && cleaner.phase == .idle,
                     "canceling before the scan starts skips every category")

        record.scanned = []
        record.onScan = { if $0 == .caches { cleaner.reset() } }
        cleaner.scan(attended: true)
        queue.drain()
        record.onScan = nil
        suite.expect(record.scanned == [.leftovers, .loginItems, .caches]
                     && cleaner.phase == .idle && cleaner.items.isEmpty,
                     "canceling mid-scan stops at the next category and delivers nothing")

        record.scanned = []
        cleaner.scan(attended: true)
        cleaner.reset()
        cleaner.scan(attended: true)
        queue.drain()
        suite.expect(record.scanned == all && cleaner.phase == .results && cleaner.items.count == all.count,
                     "a scan started right after a cancel runs alone, without the canceled one")

        cleaner.reset()
        record.scanned = []
        cleaner.scan(attended: false)
        queue.drain()
        suite.expect(record.scanned == all.filter { $0 != .screenshots } && cleaner.phase == .results,
                     "an unattended scan never reads the screenshot folders")
    }
}
