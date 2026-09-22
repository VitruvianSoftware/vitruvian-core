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

    /// The whole-home target: a `structure@…` id broadcasts to every speaker.
    public var isWholeHome: Bool { id.hasPrefix("structure@") }

    /// One-line label for pickers and lists: "Name · Room", omitting the room
    /// when the device name already spells it out ("Kitchen Home" / "Kitchen").
    public var displayLine: String {
        guard let room, !room.isEmpty,
              !name.localizedCaseInsensitiveContains(room) else { return name }
        return "\(name) · \(room)"
    }

    /// Stable config key derived from the display name: "Lake Office display"
    /// -> "lake_office_display". Only [a-z0-9_] survive so the key is safe as
    /// a JSON key, a CLI argument, and a SwiftUI tag.
    public static func alias(for name: String) -> String {
        let lowered = name.lowercased()
        var out = ""
        var lastWasSep = true
        for ch in lowered {
            if ch.isLetter || ch.isNumber, ch.isASCII {
                out.append(ch)
                lastWasSep = false
            } else if !lastWasSep {
                out.append("_")
                lastWasSep = true
            }
        }
        while out.hasSuffix("_") { out.removeLast() }
        return out.isEmpty ? "speaker" : out
    }
}

/// How much of a reply is read out. Two sentences is right for a quick
/// "did it work?", but it cuts the middle out of anything with reasoning in
/// it, so the length is the user's choice rather than a constant.
public enum SpeechLength: String, Codable, CaseIterable, Sendable {
    /// The first sentence or two — roughly a notification.
    case headline
    /// Whole sentences up to about four lines of speech. The default.
    case summary
    /// The whole reply, capped only so a runaway answer cannot monologue.
    case full

    public var maxCharacters: Int {
        switch self {
        case .headline: return 200
        case .summary: return 600
        case .full: return 1500
        }
    }

    /// Headline stops after two sentences however short they are; the longer
    /// styles keep adding whole sentences until the character cap.
    public var maxSentences: Int? { self == .headline ? 2 : nil }

    public var label: String {
        switch self {
        case .headline: return "Headline (1-2 sentences)"
        case .summary: return "Summary (about 4 lines)"
        case .full: return "Full reply"
        }
    }
}

public struct SpeakerConfig: Codable, Equatable {
    public var enabled: Bool
    public var defaultTarget: String
    /// Google Home structure id. Empty until the user signs in and picks a
    /// home; never a baked-in default, because every user has their own.
    public var structureId: String
    public var structureName: String?
    public var targets: [String: SpeakerDevice]
    /// How much of the reply to speak. Optional so older config files decode;
    /// read through `effectiveSpeechLength`.
    public var speechLength: SpeechLength?
    /// Pause whatever this Mac is playing while an announcement plays. Off
    /// unless the user turns it on: it drives other apps.
    public var pauseMedia: Bool?
    /// Seconds to stay paused after the estimated end of the announcement.
    public var pauseMediaExtraSeconds: Double?
    public var quietHoursEnabled: Bool?
    public var quietHoursStart: String?
    public var quietHoursEnd: String?
    /// Chat/Slack monitor settings. Optional so configs written before this
    /// key existed still decode; read through `effectiveChatMonitor`.
    public var chatMonitor: ChatMonitorConfig?

    enum CodingKeys: String, CodingKey {
        case enabled
        case defaultTarget = "default_target"
        case structureId = "structure_id"
        case structureName = "structure_name"
        case targets
        case speechLength = "speech_length"
        case pauseMedia = "pause_media"
        case pauseMediaExtraSeconds = "pause_media_extra_seconds"
        case quietHoursEnabled = "quiet_hours_enabled"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
        case chatMonitor = "chat_monitor"
    }

    public init(
        enabled: Bool = true,
        defaultTarget: String = "",
        structureId: String = "",
        structureName: String? = nil,
        targets: [String: SpeakerDevice] = [:],
        speechLength: SpeechLength? = nil,
        quietHoursEnabled: Bool? = false,
        quietHoursStart: String? = "22:00",
        quietHoursEnd: String? = "07:00",
        chatMonitor: ChatMonitorConfig? = nil
    ) {
        self.enabled = enabled
        self.defaultTarget = defaultTarget
        self.structureId = structureId
        self.structureName = structureName
        self.targets = targets
        self.speechLength = speechLength
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.chatMonitor = chatMonitor
    }

    /// Summary, not headline: a config written before this key existed was
    /// silently cutting replies after two sentences.
    public var effectivePauseMedia: Bool {
        get { pauseMedia ?? false }
        set { pauseMedia = newValue }
    }

    public var effectivePauseMediaExtraSeconds: Double {
        get { pauseMediaExtraSeconds ?? 1 }
        set { pauseMediaExtraSeconds = min(max(newValue, 0), 10) }
    }

    public var effectiveSpeechLength: SpeechLength {
        get { speechLength ?? .summary }
        set { speechLength = newValue }
    }

    public var effectiveChatMonitor: ChatMonitorConfig {
        get { chatMonitor ?? ChatMonitorConfig() }
        set { chatMonitor = newValue }
    }

    /// The device broadcasts go to, or nil when nothing usable is selected.
    public var defaultDevice: SpeakerDevice? { targets[defaultTarget] }

    /// True once a home and at least one speaker are known.
    public var hasSpeakers: Bool { !structureId.isEmpty && !targets.isEmpty }

    /// Merges a fresh discovery result into the speaker list:
    /// - devices that vanished from the home are dropped,
    /// - new devices are added under their generated alias,
    /// - aliases the user already has for a device that still exists are
    ///   kept (so a hand-made "lake_office" survives a refresh).
    /// The current default is kept when its device still exists; otherwise
    /// the first non-whole-home device by name is chosen, so the picker is
    /// never left pointing at a key that no longer exists.
    public mutating func applyDiscovery(structureId: String, structureName: String?, targets discovered: [String: SpeakerDevice]) {
        let sameHome = self.structureId.isEmpty || self.structureId == structureId
        self.structureId = structureId
        self.structureName = structureName

        let liveIds = Set(discovered.values.map(\.id))
        var merged: [String: SpeakerDevice] = [:]
        if sameHome {
            for (alias, device) in targets where liveIds.contains(device.id) {
                // Refresh name/room from the live record, keep the alias.
                merged[alias] = discovered.values.first(where: { $0.id == device.id }) ?? device
            }
        }
        for (alias, device) in discovered where !merged.values.contains(where: { $0.id == device.id }) {
            merged[alias] = device
        }
        self.targets = merged

        if targets[defaultTarget] == nil {
            let ordered = uniqueTargets()
            defaultTarget = ordered.first(where: { !$0.device.isWholeHome })?.key ?? ordered.first?.key ?? ""
        }
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

/// Settings for the in-app chat monitor. Both sources are OFF by default:
/// reading someone's Slack and Google Chat is opt-in, never a surprise on
/// first launch. Tokens never live here — see `SecretStore`.
public struct ChatMonitorConfig: Codable, Equatable {
    public static let minPollInterval = 5
    public static let maxPollInterval = 300

    /// How Google Chat is read. `api` uses the app's own Google login (needs
    /// Chat permission granted once); `gws` shells out to the Google Workspace
    /// CLI when the user already has it installed and signed in; `auto` picks
    /// the API when its permission is present, otherwise gws when installed.
    public enum GoogleChatSource: String, Codable, CaseIterable {
        case auto, api, gws
    }

    public var slackEnabled: Bool
    public var googleChatEnabled: Bool
    public var pollIntervalSeconds: Int
    public var muteOwnMessages: Bool
    public var googleChatSource: GoogleChatSource
    /// `--account` passed to gws; empty means gws's default account.
    public var gwsAccount: String

    enum CodingKeys: String, CodingKey {
        case slackEnabled = "slack_enabled"
        case googleChatEnabled = "google_chat_enabled"
        case pollIntervalSeconds = "poll_interval_seconds"
        case muteOwnMessages = "mute_own_messages"
        case googleChatSource = "google_chat_source"
        case gwsAccount = "gws_account"
    }

    public init(
        slackEnabled: Bool = false,
        googleChatEnabled: Bool = false,
        pollIntervalSeconds: Int = 15,
        muteOwnMessages: Bool = true,
        googleChatSource: GoogleChatSource = .auto,
        gwsAccount: String = ""
    ) {
        self.slackEnabled = slackEnabled
        self.googleChatEnabled = googleChatEnabled
        self.pollIntervalSeconds = pollIntervalSeconds
        self.muteOwnMessages = muteOwnMessages
        self.googleChatSource = googleChatSource
        self.gwsAccount = gwsAccount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slackEnabled = try c.decodeIfPresent(Bool.self, forKey: .slackEnabled) ?? false
        googleChatEnabled = try c.decodeIfPresent(Bool.self, forKey: .googleChatEnabled) ?? false
        pollIntervalSeconds = try c.decodeIfPresent(Int.self, forKey: .pollIntervalSeconds) ?? 15
        muteOwnMessages = try c.decodeIfPresent(Bool.self, forKey: .muteOwnMessages) ?? true
        googleChatSource = try c.decodeIfPresent(GoogleChatSource.self, forKey: .googleChatSource) ?? .auto
        gwsAccount = try c.decodeIfPresent(String.self, forKey: .gwsAccount) ?? ""
    }

    public var clampedPollInterval: Int {
        min(max(pollIntervalSeconds, Self.minPollInterval), Self.maxPollInterval)
    }

    /// True when at least one source is switched on.
    public var anySourceEnabled: Bool { slackEnabled || googleChatEnabled }
}
