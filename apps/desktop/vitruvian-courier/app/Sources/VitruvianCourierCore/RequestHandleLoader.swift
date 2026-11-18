// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Finds the handle (username, number or email) of each message request the bridge gave a placeholder name.
///
/// Only answers the engine really gave are kept, an empty answer ("nobody here has a handle") included. A lookup
/// that fails is not kept: it is tried again later, after 30 seconds, then 60, doubling up to 10 minutes.
/// At most four lookups run at once, and they run off the main actor.
@MainActor
public final class RequestHandleLoader {
    public static let maxInFlight = 4
    public static let firstRetry: TimeInterval = 30
    public static let longestRetry: TimeInterval = 600

    /// The members of a chat, as the engine says (it throws when it cannot).
    public typealias Fetch = @Sendable (_ roomID: String) async throws -> [Member]

    /// What the engine answered, by chat. "" means it answered and there is no handle.
    public private(set) var handles: [String: String] = [:]
    private var failures: [String: (count: Int, retryAt: Date)] = [:]
    private var running = false
    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// The requests worth a lookup: a message request whose name is a placeholder. Anyone with a real name is
    /// never looked up.
    public static func candidates(in rows: [InboxRow]) -> [String] {
        rows.filter { $0.request && RequestPresentation.isPlaceholderName($0.displayTitle) }.map(\.roomID)
    }

    /// Forgets everything (a new engine connection).
    public func reset() {
        handles = [:]
        failures = [:]
    }

    /// Seconds to wait after the `count`th failure in a row.
    public static func delay(afterFailures count: Int) -> TimeInterval {
        min(longestRetry, firstRetry * pow(2, Double(max(0, count - 1))))
    }

    /// Looks up every candidate not answered yet and not waiting out a failure, four at a time, until none is left.
    /// Returns how long until the soonest failed lookup may be tried again; nil when none is waiting. Called while
    /// a run is going, it returns nil: that run asks `candidates` again before it ends.
    @discardableResult
    public func run(candidates: @MainActor () -> [String], fetch: @escaping Fetch,
                    onUpdate: @MainActor () -> Void = {}) async -> TimeInterval? {
        guard !running else { return nil }
        running = true
        defer { running = false }
        while true {
            let batch = Array(Set(candidates())).sorted().filter(isDue)
            if batch.isEmpty { break }
            await lookUp(batch, fetch: fetch, onUpdate: onUpdate)
        }
        let waiting = candidates().compactMap { failures[$0]?.retryAt }
        guard let soonest = waiting.min() else { return nil }
        return max(1, soonest.timeIntervalSince(now()))
    }

    private func isDue(_ roomID: String) -> Bool {
        if handles[roomID] != nil { return false }
        guard let failure = failures[roomID] else { return true }
        return failure.retryAt <= now()
    }

    private func lookUp(_ batch: [String], fetch: @escaping Fetch, onUpdate: @MainActor () -> Void) async {
        await withTaskGroup(of: (String, String?).self) { group in
            func add(_ roomID: String) {
                group.addTask {
                    do {
                        return (roomID, RequestPresentation.handle(from: try await fetch(roomID)))
                    } catch {
                        return (roomID, nil)
                    }
                }
            }
            var next = 0
            while next < min(Self.maxInFlight, batch.count) {
                add(batch[next])
                next += 1
            }
            while let (roomID, handle) = await group.next() {
                if let handle {
                    handles[roomID] = handle
                    failures[roomID] = nil
                } else {
                    let count = (failures[roomID]?.count ?? 0) + 1
                    failures[roomID] = (count, now().addingTimeInterval(Self.delay(afterFailures: count)))
                }
                onUpdate()
                if next < batch.count {
                    add(batch[next])
                    next += 1
                }
            }
        }
    }
}
