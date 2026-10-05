// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import VitruvianCore
import VitruvianDesign

@MainActor
package final class PortManagerService: ObservableObject {
    /// Where a refresh reads processes and listening sockets, and where its
    /// work runs. Tests pass inert process data and a manual queue.
    package struct Scanning: Sendable {
        /// `proc_listallpids`: with no buffer, an estimated count; otherwise
        /// the PIDs written, or a non-positive value on failure.
        package var listPIDs: @Sendable (_ buffer: UnsafeMutableRawPointer?, _ byteCount: Int32) -> Int32
        package var startTime: @Sendable (pid_t) -> UInt64?
        package var listing: @Sendable () -> (status: Int32, output: String)
        package var background: @Sendable (@escaping @Sendable () -> Void) -> Void
        package var main: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void

        package init(listPIDs: @escaping @Sendable (UnsafeMutableRawPointer?, Int32) -> Int32,
                     startTime: @escaping @Sendable (pid_t) -> UInt64?,
                     listing: @escaping @Sendable () -> (status: Int32, output: String),
                     background: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
                     main: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void) {
            self.listPIDs = listPIDs
            self.startTime = startTime
            self.listing = listing
            self.background = background
            self.main = main
        }

        package static let system = Scanning(
            listPIDs: { proc_listallpids($0, $1) },
            startTime: { KillProcessService.startTime(for: $0) },
            listing: { Shell.run("/usr/sbin/lsof", ["-nP", "+c0", "-iTCP", "-sTCP:LISTEN", "-F", "pcnPT"]) },
            background: { DispatchQueue.global(qos: .userInitiated).async(execute: $0) },
            main: { work in DispatchQueue.main.async { work() } })
    }

    package static let shared = PortManagerService()
    @Published package private(set) var entries: [PortManagerEntry] = []
    @Published package var query = ""
    @Published package private(set) var isRefreshing = false
    @Published package private(set) var hasLoadedOnce = false
    @Published package private(set) var refreshFailed = false

    private let scanning: Scanning

    package init(scanning: Scanning = .system) {
        self.scanning = scanning
    }

    package var filteredEntries: [PortManagerEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { "\($0.port) \($0.processName) \($0.pid) \($0.address)".lowercased().contains(q) }
    }

    package func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshFailed = false
        let scanning = scanning
        scanning.background {
            let result = Self.snapshot(scanning)
            scanning.main {
                if let result {
                    self.entries = result
                    self.hasLoadedOnce = true
                }
                self.refreshFailed = result == nil
                self.isRefreshing = false
            }
        }
    }

    package func terminate(_ entry: PortManagerEntry, force: Bool) {
        guard AppFeature.killProcess.isAvailable, let startedAt = entry.startedAt else { return }
        KillProcessService.shared.kill(pid: entry.pid,
                                       name: entry.processName,
                                       startedAt: startedAt,
                                       force: force) { [weak self] in
            self?.refresh()
        }
    }

    nonisolated private static func startTimes(_ scanning: Scanning) -> [pid_t: UInt64] {
        let estimatedCount = max(1, Int(scanning.listPIDs(nil, 0)))
        var pids = [pid_t](repeating: 0, count: estimatedCount + 32)
        let count = pids.withUnsafeMutableBytes { buffer in
            scanning.listPIDs(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [:] }
        var identities: [pid_t: UInt64] = [:]
        for pid in pids.prefix(min(Int(count), pids.count)) where pid > 0 {
            identities[pid] = scanning.startTime(pid)
        }
        return identities
    }

    /// The listening sockets, with a termination identity only for processes
    /// seen unchanged across the whole listing; `nil` when the listing timed out.
    nonisolated package static func snapshot(_ scanning: Scanning) -> [PortManagerEntry]? {
        let identities = startTimes(scanning)
        let result = scanning.listing()
        // Negative status means Shell.run hit its own timeout — always bail.
        guard result.status >= 0 else { return nil }
        let parsed = PortManagerSupport.parseLsof(result.output).map { entry in
            // Only the same process observed across the entire listing may
            // be terminated. New or reused PIDs remain visible without actions
            // until a subsequent refresh can establish their identity.
            let startedAt = identities[entry.pid]
            let stable = startedAt != nil && startedAt == scanning.startTime(entry.pid)
            return PortManagerEntry(port: entry.port,
                             protocolName: entry.protocolName,
                             address: entry.address,
                             pid: entry.pid,
                             processName: entry.processName,
                             startedAt: stable ? startedAt : nil)
        }
        // lsof exits 1 when no listening sockets are found or when it prints a
        // warning. Both cases yield a clean result: an empty list or the parsed rows.
        // A negative status code above (timeout) is the only infrastructure failure.
        return parsed
    }
}
