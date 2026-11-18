// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

/// One automated announcement held while snooze was active and `snooze_queue`
/// was enabled. Stored oldest-first in the profile's queue file.
public struct SnoozeQueueItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let source: String
    public let timestamp: Date
    public let restyle: Bool
    public let lead: String?
    public let session: SessionOrigin?

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case source
        case timestamp
        case restyle
        case lead
        case session
        case sessionName = "session_name"
    }

    public init(
        id: UUID = UUID(),
        text: String,
        source: String,
        timestamp: Date = Date(),
        restyle: Bool = false,
        lead: String? = nil,
        session: SessionOrigin? = nil
    ) {
        self.id = id
        self.text = text
        self.source = source
        self.timestamp = timestamp
        self.restyle = restyle
        self.lead = lead
        self.session = session
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.text = try container.decode(String.self, forKey: .text)
        self.source = try container.decode(String.self, forKey: .source)
        if let raw = try? container.decode(String.self, forKey: .timestamp),
           let parsed = SpeakerConfig.parseISO8601(raw) {
            self.timestamp = parsed
        } else {
            self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        }
        self.restyle = try container.decodeIfPresent(Bool.self, forKey: .restyle) ?? false
        self.lead = try container.decodeIfPresent(String.self, forKey: .lead)
        let sessionId = try container.decodeIfPresent(String.self, forKey: .session)
        let sessionName = try container.decodeIfPresent(String.self, forKey: .sessionName)
        self.session = sessionId.map { SessionOrigin(id: $0, name: sessionName) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(source, forKey: .source)
        try container.encode(SpeakerConfig.formatISO8601UTC(timestamp), forKey: .timestamp)
        if restyle {
            try container.encode(true, forKey: .restyle)
        }
        try container.encodeIfPresent(lead, forKey: .lead)
        try container.encodeIfPresent(session?.id, forKey: .session)
        try container.encodeIfPresent(session?.name, forKey: .sessionName)
    }
}

/// Persistent FIFO queue of announcements held while snoozed.
///
/// Both short-lived CLI processes and long-running app/extension processes read
/// and mutate this file under an exclusive BSD `flock` on `lockURL` and write
/// updates atomically. Only the long-running app or extension flushes the queue
/// once snooze ends.
public final class SnoozeQueue: Sendable {
    public static let shared = SnoozeQueue(fileURL: VitruvianSpeakerProfile.app().snoozeQueueURL)
    /// Maximum items retained in the queue; adding beyond this drops the oldest.
    public static let maxItems = 50
    /// Items older than 12 hours are dropped when delivery begins.
    public static let maxAgeSeconds: TimeInterval = 12 * 3600
    /// Spoken once before the first delivered item after snooze ends.
    public static let leadIn = "While you were snoozed: "

    public let fileURL: URL
    public var lockURL: URL { fileURL.appendingPathExtension("lock") }

    public enum HoldReason: Equatable, Sendable {
        case disabled
        case snoozed(until: Date)
        case quietHours(until: String)
        case noOutputs
    }

    public enum DrainDisposition: Equatable, Sendable {
        case empty
        case held(reason: HoldReason)
        case drained(spokenCount: Int, droppedExpiredCount: Int)
    }

    public init(fileURL: URL = VitruvianSpeakerProfile.app().snoozeQueueURL) {
        self.fileURL = fileURL
    }

    /// Pending items in oldest-first FIFO order; empty when missing or unreadable.
    public func load() -> [SnoozeQueueItem] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([SnoozeQueueItem].self, from: data) else {
            return []
        }
        return items
    }

    public func count() -> Int {
        load().count
    }

    /// Appends `item`, dropping the oldest entries past `maxItems`, and writes atomically.
    @discardableResult
    public func append(_ item: SnoozeQueueItem) throws -> [SnoozeQueueItem] {
        try FileLock.withExclusiveLock(at: lockURL) {
            var items = load()
            items.append(item)
            if items.count > Self.maxItems {
                items.removeFirst(items.count - Self.maxItems)
            }
            try writeUnlocked(items)
            return items
        }
    }

    /// Removes the item with `id` under `lockURL` and returns the remaining items.
    @discardableResult
    public func remove(id: UUID) throws -> [SnoozeQueueItem] {
        try remove(ids: [id])
    }

    /// Removes every item whose `id` is in `ids` under `lockURL` and returns the remaining items.
    @discardableResult
    public func remove(ids: Set<UUID>) throws -> [SnoozeQueueItem] {
        guard !ids.isEmpty else { return load() }
        return try FileLock.withExclusiveLock(at: lockURL) {
            let remaining = load().filter { !ids.contains($0.id) }
            try writeUnlocked(remaining)
            return remaining
        }
    }

    /// Empties the queue under `lockURL`.
    public func clear() throws {
        try FileLock.withExclusiveLock(at: lockURL) {
            try writeUnlocked([])
        }
    }

    private func writeUnlocked(_ items: [SnoozeQueueItem]) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(items)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Returns why delivery must stay paused under `config` at `now`, or `nil` when ready.
    public static func canDeliver(config: SpeakerConfig, at now: Date = Date()) -> HoldReason? {
        guard config.enabled else { return .disabled }
        if config.isSnoozed(at: now), let until = config.snoozeUntil {
            return .snoozed(until: until)
        }
        if config.isInQuietHours(at: now) {
            return .quietHours(until: config.quietHoursEnd ?? "")
        }
        if !config.effectiveSpeakHome && !config.effectiveSpeakLocal && !config.effectiveSpeakPhone {
            return .noOutputs
        }
        return nil
    }

    /// True when `item` is strictly older than 12 hours at `now`.
    public static func isExpired(_ item: SnoozeQueueItem, at now: Date) -> Bool {
        now.timeIntervalSince(item.timestamp) > maxAgeSeconds
    }

    /// Flushes queued items in FIFO order when rules allow.
    ///
    /// Items older than 12 hours are dropped when delivery starts. Each item is
    /// removed from disk only after it is handed to delivery, so a pause by
    /// quiet hours, broadcasting off, or a renewed snooze leaves any remaining
    /// items safely in the queue for the next retry.
    @discardableResult
    public func drainIfReady(
        configProvider: @Sendable () async -> SpeakerConfig,
        now: @Sendable () -> Date = { Date() },
        announcer: Announcer,
        history: BroadcastHistory? = nil,
        onDeliveredItem: (@Sendable (BroadcastLogItem) async -> Void)? = nil
    ) async -> DrainDisposition {
        let snapshot = load()
        guard !snapshot.isEmpty else { return .empty }

        let initialTime = now()
        let initialConfig = await configProvider()
        if let hold = Self.canDeliver(config: initialConfig, at: initialTime) {
            return .held(reason: hold)
        }

        let expiredIDs = Set(snapshot.filter { Self.isExpired($0, at: initialTime) }.map(\.id))
        if !expiredIDs.isEmpty {
            _ = try? remove(ids: expiredIDs)
        }
        let fresh = snapshot.filter { !expiredIDs.contains($0.id) }
        guard !fresh.isEmpty else {
            return .drained(spokenCount: 0, droppedExpiredCount: expiredIDs.count)
        }

        var spokeAnyInBatch = false
        var spokenCount = 0
        var extraDropped = 0

        for item in fresh {
            let stepNow = now()
            let currentConfig = await configProvider()
            if let hold = Self.canDeliver(config: currentConfig, at: stepNow) {
                if spokenCount > 0 || !expiredIDs.isEmpty || extraDropped > 0 {
                    return .drained(spokenCount: spokenCount, droppedExpiredCount: expiredIDs.count + extraDropped)
                }
                return .held(reason: hold)
            }
            if Self.isExpired(item, at: stepNow) {
                _ = try? remove(id: item.id)
                extraDropped += 1
                continue
            }

            let combinedLead: String?
            if !spokeAnyInBatch {
                combinedLead = Self.leadIn + (item.lead ?? "")
            } else {
                combinedLead = item.lead
            }

            let (outcome, spoken) = await announcer.announceReporting(
                item.text,
                config: currentConfig,
                force: false,
                restyle: item.restyle,
                lead: combinedLead,
                source: item.source,
                session: item.session,
                bypassSnoozeQueue: true,
                at: stepNow
            )

            switch outcome {
            case .disabled, .quietHours, .snoozed, .noOutputs, .queued:
                if spokenCount > 0 || !expiredIDs.isEmpty || extraDropped > 0 {
                    return .drained(spokenCount: spokenCount, droppedExpiredCount: expiredIDs.count + extraDropped)
                }
                let reason = Self.canDeliver(config: currentConfig, at: stepNow) ?? .disabled
                return .held(reason: reason)

            case .nothingToSay:
                _ = try? remove(id: item.id)

            case .announced:
                _ = try? remove(id: item.id)
                if outcome.anySpoke {
                    spokeAnyInBatch = true
                    spokenCount += 1
                    let targetLabel = outcome.spokenLabel(homeName: currentConfig.defaultDevice?.name ?? "Home speakers")
                    let logItem = BroadcastLogItem(
                        text: spoken ?? item.text,
                        targetName: targetLabel,
                        source: item.source,
                        session: item.session
                    )
                    if let history {
                        _ = try? history.append(logItem)
                    }
                    if let onDeliveredItem {
                        await onDeliveredItem(logItem)
                    }
                }
            }
        }

        return .drained(spokenCount: spokenCount, droppedExpiredCount: expiredIDs.count + extraDropped)
    }
}

/// Long-running coordinator used by the menu-bar app and Atrium extension tool
/// to flush queued announcements when snooze expires, on Resume now, and once
/// quiet hours or disabled state clear. Never started in CLI runs.
@MainActor
public final class SnoozeQueueCoordinator {
    private let snoozeQueue: SnoozeQueue
    private let announcer: Announcer
    private let history: BroadcastHistory
    private let configProvider: @MainActor () -> SpeakerConfig
    private let onQueueChanged: @MainActor () -> Void
    private let onDeliveredLog: @MainActor (BroadcastLogItem) -> Void
    private let now: @Sendable () -> Date

    private var isRunning = false
    private var isDraining = false
    private var needsRedrain = false
    private var wakeupTask: Task<Void, Never>?

    public init(
        snoozeQueue: SnoozeQueue,
        announcer: Announcer,
        history: BroadcastHistory,
        configProvider: @escaping @MainActor () -> SpeakerConfig,
        onQueueChanged: @escaping @MainActor () -> Void = {},
        onDeliveredLog: @escaping @MainActor (BroadcastLogItem) -> Void = { _ in },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.snoozeQueue = snoozeQueue
        self.announcer = announcer
        self.history = history
        self.configProvider = configProvider
        self.onQueueChanged = onQueueChanged
        self.onDeliveredLog = onDeliveredLog
        self.now = now
    }

    public func start() {
        guard !isRunning else {
            poke()
            return
        }
        isRunning = true
        poke()
    }

    public func stop() {
        isRunning = false
        wakeupTask?.cancel()
        wakeupTask = nil
    }

    /// Re-evaluates the queue and triggers delivery when rules allow, or
    /// schedules the next check when snooze or quiet hours end.
    public func poke() {
        onQueueChanged()
        guard isRunning else { return }
        scheduleNextCheck()
        guard !snoozeQueue.load().isEmpty else { return }
        guard SnoozeQueue.canDeliver(config: configProvider(), at: now()) == nil else { return }
        if isDraining {
            needsRedrain = true
            return
        }
        startDrain()
    }

    private func startDrain() {
        isDraining = true
        Task { [weak self] in
            guard let self else { return }
            repeat {
                self.needsRedrain = false
                let provider = self.configProvider
                _ = await self.snoozeQueue.drainIfReady(
                    configProvider: { await MainActor.run { provider() } },
                    now: self.now,
                    announcer: self.announcer,
                    history: self.history,
                    onDeliveredItem: { item in
                        await MainActor.run { self.onDeliveredLog(item) }
                    }
                )
                await MainActor.run { self.onQueueChanged() }
            } while self.isRunning && self.needsRedrain && !self.snoozeQueue.load().isEmpty
            self.isDraining = false
            if self.isRunning {
                self.scheduleNextCheck()
            }
        }
    }

    private func scheduleNextCheck() {
        wakeupTask?.cancel()
        wakeupTask = nil
        guard isRunning else { return }
        let itemsEmpty = snoozeQueue.load().isEmpty
        let currentNow = now()
        let config = configProvider()
        let delay: TimeInterval?
        if let until = config.snoozeUntil, config.isSnoozed(at: currentNow) {
            delay = max(0.1, min(60, until.timeIntervalSince(currentNow) + 0.05))
        } else if !itemsEmpty {
            delay = 15
        } else {
            delay = nil
        }
        guard let delay else { return }
        wakeupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.poke()
        }
    }
}
