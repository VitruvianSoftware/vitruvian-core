// Copyright (c) 2026 VitruvianSoftware

import Foundation

public struct SpeakerDevice: Codable, Identifiable, Hashable {
    public var id: String
    public var type: String
    public var name: String
    public var room: String?

    public init(id: String, type: String, name: String, room: String? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.room = room
    }

    /// One-line label for pickers and lists: "Name · Room", omitting the room
    /// when the device name already spells it out ("Kitchen Home" / "Kitchen").
    public var displayLine: String {
        guard let room, !room.isEmpty,
              !name.localizedCaseInsensitiveContains(room) else { return name }
        return "\(name) · \(room)"
    }
}

public struct SpeakerConfig: Codable, Equatable {
    public var enabled: Bool
    public var defaultTarget: String
    public var structureId: String
    public var targets: [String: SpeakerDevice]
    public var quietHoursEnabled: Bool?
    public var quietHoursStart: String?
    public var quietHoursEnd: String?
    /// Chat/Slack daemon settings. Optional so configs written before this
    /// key existed still decode; read through `effectiveChatMonitor`.
    public var chatMonitor: ChatMonitorConfig?

    enum CodingKeys: String, CodingKey {
        case enabled
        case defaultTarget = "default_target"
        case structureId = "structure_id"
        case targets
        case quietHoursEnabled = "quiet_hours_enabled"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
        case chatMonitor = "chat_monitor"
    }

    public init(
        enabled: Bool = true,
        defaultTarget: String = "lake_office_display",
        structureId: String = "5219a9d7-d46d-7834-5cb3-19242d447eaf",
        targets: [String: SpeakerDevice] = [:],
        quietHoursEnabled: Bool? = false,
        quietHoursStart: String? = "22:00",
        quietHoursEnd: String? = "07:00",
        chatMonitor: ChatMonitorConfig? = nil
    ) {
        self.enabled = enabled
        self.defaultTarget = defaultTarget
        self.structureId = structureId
        self.targets = targets
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.chatMonitor = chatMonitor
    }

    public var effectiveChatMonitor: ChatMonitorConfig {
        get { chatMonitor ?? ChatMonitorConfig() }
        set { chatMonitor = newValue }
    }

    // MARK: Quiet hours

    /// Parses "HH:mm" (24h, leading zero optional) into minutes since midnight.
    /// Returns nil for anything malformed or out of range.
    public static func minutesSinceMidnight(_ hhmm: String) -> Int? {
        let parts = hhmm.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    /// True when quiet hours are enabled and `date` (local time) falls inside
    /// [start, end). Overnight windows (22:00 -> 07:00) wrap past midnight.
    /// Fails open: a disabled, missing, malformed, or zero-length window is
    /// never quiet, so a typo can't silence the speakers indefinitely.
    public func isInQuietHours(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard quietHoursEnabled == true,
              let startText = quietHoursStart, let endText = quietHoursEnd,
              let start = Self.minutesSinceMidnight(startText),
              let end = Self.minutesSinceMidnight(endText),
              start != end else { return false }
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let now = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if start < end {
            return now >= start && now < end
        }
        return now >= start || now < end
    }

    // MARK: Targets

    /// Targets collapsed to one entry per physical device. Several aliases can
    /// point at the same device id (lake_office / lake_office_display); the
    /// alias currently selected as default wins, otherwise the shortest one.
    /// Sorted by display name so the picker reads top to bottom.
    public func uniqueTargets() -> [(key: String, device: SpeakerDevice)] {
        var byDevice: [String: String] = [:]   // device id -> chosen alias
        for key in targets.keys.sorted() {
            guard let device = targets[key] else { continue }
            if key == defaultTarget {
                byDevice[device.id] = key
            } else if let existing = byDevice[device.id] {
                if existing != defaultTarget && key.count < existing.count {
                    byDevice[device.id] = key
                }
            } else {
                byDevice[device.id] = key
            }
        }
        return byDevice.values
            .compactMap { key in targets[key].map { (key: key, device: $0) } }
            .sorted { $0.device.name.localizedCaseInsensitiveCompare($1.device.name) == .orderedAscending }
    }
}

public struct BroadcastLogItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let text: String
    public let targetName: String
    public let source: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), text: String, targetName: String, source: String) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.targetName = targetName
        self.source = source
    }
}

public struct ChatMonitorConfig: Codable, Equatable {
    public static let minPollInterval = 5
    public static let maxPollInterval = 300

    public var slackEnabled: Bool
    public var googleChatEnabled: Bool
    public var pollIntervalSeconds: Int
    public var muteOwnMessages: Bool
    /// Runtime-only; deliberately excluded from CodingKeys so it is never
    /// written to the plain-text config file.
    public var slackToken: String = ""

    enum CodingKeys: String, CodingKey {
        case slackEnabled = "slack_enabled"
        case googleChatEnabled = "google_chat_enabled"
        case pollIntervalSeconds = "poll_interval_seconds"
        case muteOwnMessages = "mute_own_messages"
    }

    public init(
        slackEnabled: Bool = true,
        googleChatEnabled: Bool = true,
        pollIntervalSeconds: Int = 15,
        muteOwnMessages: Bool = true,
        slackToken: String = ""
    ) {
        self.slackEnabled = slackEnabled
        self.googleChatEnabled = googleChatEnabled
        self.pollIntervalSeconds = pollIntervalSeconds
        self.muteOwnMessages = muteOwnMessages
        self.slackToken = slackToken
    }

    public var clampedPollInterval: Int {
        min(max(pollIntervalSeconds, Self.minPollInterval), Self.maxPollInterval)
    }

    /// Command-line arguments for `~/bin/chat-monitor`, or nil when both
    /// sources are off and the daemon should not be launched at all.
    public var daemonArguments: [String]? {
        guard slackEnabled || googleChatEnabled else { return nil }
        var args = ["--interval", String(clampedPollInterval)]
        if !slackEnabled { args.append("--chat-only") }
        if !googleChatEnabled { args.append("--slack-only") }
        return args
    }
}
