// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Runs the production refresh and snapshot with inert process data and a
/// manual queue. No real process is inspected, signalled or launched.
enum PortManagerRefreshTests {
    /// The process table and listing the scan sees. The listing swaps the
    /// table to `during`, as if processes changed while lsof ran. Only the
    /// test's own thread touches it.
    nonisolated final class Processes: @unchecked Sendable {
        var current: [pid_t: UInt64] = [:]
        var enumerated: [pid_t] = []
        var enumerationFails = false
        var status: Int32 = 0
        var output = ""
        var during: [pid_t: UInt64] = [:]
        var calls = 0

        func listPIDs(_ buffer: UnsafeMutableRawPointer?, _ byteCount: Int32) -> Int32 {
            guard !enumerationFails else { return -1 }
            guard let buffer else { return Int32(enumerated.count) }
            let count = min(enumerated.count, Int(byteCount) / MemoryLayout<pid_t>.size)
            let pids = buffer.assumingMemoryBound(to: pid_t.self)
            for index in 0..<count { pids[index] = enumerated[index] }
            return Int32(count)
        }

        func listing() -> (status: Int32, output: String) {
            calls += 1
            current = during
            return (status, output)
        }
    }

    /// Background work and main-queue handoffs wait here until drained. Only
    /// the test's own thread touches it.
    nonisolated final class Queue: @unchecked Sendable {
        var jobs: [() -> Void] = []
        func drain() { while !jobs.isEmpty { jobs.removeFirst()() } }
    }

    private static let rows = """
        p123
        cExample Server
        PTCP
        n*:4321
        p124
        cOther Server
        PTCP
        n*:4322
        """

    static func run(_ suite: TestSuite) {
        let processes = Processes()
        let worker = Queue()
        let main = Queue()
        let scanning = PortManagerService.Scanning(
            listPIDs: { processes.listPIDs($0, $1) },
            startTime: { processes.current[$0] },
            listing: { processes.listing() },
            background: { worker.jobs.append($0) },
            main: { work in main.jobs.append { MainActor.assumeIsolated { work() } } })
        func snapshot() -> [PortManagerEntry]? { PortManagerService.snapshot(scanning) }
        func prepare(before: [pid_t: UInt64], after: [pid_t: UInt64], status: Int32 = 0) {
            processes.current = before
            processes.enumerated = before.keys.sorted()
            processes.enumerationFails = false
            processes.during = after
            processes.status = status
            processes.output = rows
        }
        prepare(before: [123: 100, 124: 200], after: [123: 100, 124: 200])
        suite.expect(snapshot()?.map(\.startedAt) == [100, 200],
                     "stable listener identities retain their termination capability")
        prepare(before: [123: 100, 124: 200], after: [123: 300, 124: 200])
        let reused = snapshot()
        suite.expect(reused?.count == 2 && reused?[0].startedAt == nil && reused?[1].startedAt == 200,
                     "a reused PID cannot lend a new process identity to an old listener row")
        prepare(before: [124: 200], after: [123: 100, 124: 200])
        suite.expect(snapshot()?[0].startedAt == nil,
                     "a process first seen during the listing requires a fresh scan before termination")
        prepare(before: [123: 100, 124: 200], after: [124: 200])
        suite.expect(snapshot()?[0].startedAt == nil,
                     "an exited or unreadable process never receives a termination identity")
        prepare(before: [123: 100, 124: 200], after: [123: 100, 124: 200])
        processes.enumerationFails = true
        suite.expect(snapshot()?.allSatisfy { $0.startedAt == nil } == true,
                     "failed identity enumeration keeps the listing read-only")
        prepare(before: [123: 100], after: [123: 100], status: -1)
        suite.expect(snapshot() == nil, "a timed-out listing remains a failure, not an empty result")
        processes.status = 1
        processes.output = ""
        suite.expect(snapshot() == [], "a successful scan with no listeners is genuinely empty")

        let service = PortManagerService(scanning: scanning)
        prepare(before: [:], after: [:], status: -1)
        processes.calls = 0
        service.refresh()
        service.refresh()
        suite.expect(service.isRefreshing && worker.jobs.count == 1,
                     "refresh starts once while a scan is in progress")
        worker.drain()
        suite.expect(service.isRefreshing && !service.refreshFailed,
                     "a completed scan waits for main-queue publication")
        main.drain()
        suite.expect(!service.isRefreshing && service.refreshFailed && !service.hasLoadedOnce,
                     "the first timeout stops loading and reports a retryable failure")
        suite.expect(service.entries.isEmpty && processes.calls == 1,
                     "a failed first scan does not invent data or launch duplicate work")
        prepare(before: [123: 100, 124: 200], after: [123: 100, 124: 200])
        service.refresh()
        suite.expect(service.isRefreshing && !service.refreshFailed,
                     "retry clears the old failure while work runs")
        worker.drain(); main.drain()
        let previous = service.entries
        suite.expect(service.hasLoadedOnce && !service.refreshFailed && previous.count == 2,
                     "a successful retry publishes listeners and clears the error")
        prepare(before: [:], after: [:], status: -1)
        service.refresh()
        worker.drain(); main.drain()
        suite.expect(service.entries == previous && service.hasLoadedOnce && service.refreshFailed,
                     "a later timeout preserves the last successful listing and reports stale data")
        processes.status = 1
        processes.output = ""
        service.refresh()
        worker.drain(); main.drain()
        suite.expect(service.entries.isEmpty && service.hasLoadedOnce && !service.refreshFailed,
                     "a successful empty retry replaces old listeners without claiming a failure")
    }
}
