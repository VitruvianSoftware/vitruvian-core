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

/// One settings catalog for the Home Speaker macOS app, the Vitruvian extension,
/// and the Android remote.
///
/// Every choice list, numeric range, and visibility rule comes from the
/// existing `HomeSpeakerCore` model types (`SpeechLength`, `AnnouncementStyle`,
/// `StyleModel`, `LocalVoiceEngine`, `GeminiVoice`, `CodingAgent`,
/// `ChatMonitorConfig`, and `SpeakerConfig`) so there is one place that defines
/// what each setting is called, what values it accepts, and when it appears.
public struct SettingsCatalog: Sendable, Equatable {
    /// What kind of control a setting uses.
    public enum Kind: String, Codable, CaseIterable, Sendable, Equatable {
        case toggle
        case choice
        case number
        case text
        case time
    }

    /// One selectable option in a `.choice` or `.time` setting.
    public struct Choice: Codable, Sendable, Equatable {
        public let value: String
        public let label: String

        public init(value: String, label: String) {
            self.value = value
            self.label = label
        }
    }

    /// Numeric bounds, step, and default for a `.number` setting.
    public struct Limits: Codable, Sendable, Equatable {
        public let min: Int
        public let max: Int
        public let step: Int
        public let defaultValue: Int

        public init(min: Int, max: Int, step: Int, defaultValue: Int) {
            self.min = min
            self.max = max
            self.step = step
            self.defaultValue = defaultValue
        }

        public func clamp(_ value: Int) -> Int {
            Swift.min(Swift.max(value, min), max)
        }

        public func contains(_ value: Int) -> Bool {
            value >= min && value <= max
        }
    }

    /// Canonical keys for every setting shown across the app's Settings window,
    /// the extension's pages, and the Android remote.
    public enum Key: String, Codable, CaseIterable, Sendable, Equatable {
        case enabled = "enabled"
        case speechLength = "speech_length"
        case announcementStyle = "announcement_style"
        case customStylePrompt = "custom_style_prompt"
        case styleModel = "style_model"
        case speakerVolume = "speaker_volume"
        case announceVolumeEnabled = "announce_volume_enabled"
        case announceVolume = "announce_volume"
        case pauseMedia = "pause_media"
        case pauseMediaExtraSeconds = "pause_media_extra_seconds"
        case quietHoursEnabled = "quiet_hours_enabled"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
        case speakHome = "speak_home"
        case homeCastVoice = "home_cast_voice"
        case defaultTarget = "default_target"
        case speakLocal = "speak_local"
        case speakPhone = "speak_phone"
        case localEngine = "local_engine"
        case geminiVoice = "gemini_voice"
        case localVoice = "local_voice"
        case phonePauseMedia = "phone_pause_media"
        case phoneHeadphonesOnly = "phone_headphones_only"
        case announceClaudeCode = "announce_claude_code"
        case announceAntigravity = "announce_antigravity"
        case announceOpenCode = "announce_opencode"
        case announceSource = "announce_source"
        case slackEnabled = "slack_enabled"
        case googleChatEnabled = "google_chat_enabled"
        case googleChatSource = "google_chat_source"
        case gwsAccount = "gws_account"
        case beeperEnabled = "beeper_enabled"
        case beeperAnnounce = "beeper_announce"
        case beeperAddress = "beeper_address"
        case courierEnabled = "courier_enabled"
        case courierAnnounce = "courier_announce"
        case courierAddress = "courier_address"
        case muteOwnMessages = "mute_own_messages"
        case pollIntervalSeconds = "poll_interval_seconds"

        /// The catalog key for a coding agent's announcement toggle.
        public static func forAgent(_ agent: CodingAgent) -> Key {
            switch agent {
            case .claudeCode: return .announceClaudeCode
            case .antigravity: return .announceAntigravity
            case .opencode: return .announceOpenCode
            }
        }

        /// The catalog label for this setting under `config`.
        public func label(config: SpeakerConfig = SpeakerConfig()) -> String {
            SettingsCatalog(config: config).entry(self).label
        }

        /// Whether this setting is visible under `config`.
        public func shown(config: SpeakerConfig) -> Bool {
            SettingsCatalog(config: config).entry(self).shown
        }
    }

    /// Description of one setting evaluated against a `SpeakerConfig`.
    public struct Entry: Codable, Sendable, Equatable {
        public let id: Key
        public var key: String { id.rawValue }
        public let label: String
        public let kind: Kind
        public let choices: [Choice]
        public let limits: Limits?
        public let shown: Bool

        public init(
            id: Key,
            label: String,
            kind: Kind,
            choices: [Choice] = [],
            limits: Limits? = nil,
            shown: Bool
        ) {
            self.id = id
            self.label = label
            self.kind = kind
            self.choices = choices
            self.limits = limits
            self.shown = shown
        }
    }

    // MARK: - Choice Lists (from model enums)

    public static var announceSourceChoices: [Choice] {
        AnnounceSourceLabel.allCases.map { Choice(value: $0.rawValue, label: $0.label) }
    }

    public static var speechLengthChoices: [Choice] {
        SpeechLength.allCases.map { Choice(value: $0.rawValue, label: $0.label) }
    }

    public static var announcementStyleChoices: [Choice] {
        AnnouncementStyle.allCases.map { Choice(value: $0.rawValue, label: $0.label) }
    }

    public static var styleModelChoices: [Choice] {
        StyleModel.allCases.map { Choice(value: $0.rawValue, label: $0.label) }
    }

    public static var voiceEngineChoices: [Choice] {
        LocalVoiceEngine.allCases.map { Choice(value: $0.rawValue, label: $0.label) }
    }

    public static var prebuiltGeminiVoiceChoices: [Choice] {
        GeminiVoice.allCases.map { Choice(value: $0.rawValue, label: $0.label) }
    }

    public static func geminiVoiceChoices(for config: SpeakerConfig) -> [Choice] {
        config.geminiVoiceOptions().map { Choice(value: $0.value, label: $0.label) }
    }

    public static func localVoiceChoices(config: SpeakerConfig, systemVoices: [LocalVoice]) -> [Choice] {
        let saved = config.effectiveLocalVoice
        var choices = systemVoices.map { Choice(value: $0.id, label: $0.pickerLabel) }
        if !saved.isEmpty, !systemVoices.contains(where: { $0.id == saved }) {
            choices.insert(Choice(value: saved, label: missingVoiceLabel(saved, voices: systemVoices)), at: 0)
        }
        return choices
    }

    public static func missingVoiceLabel(_ id: String, voices: [LocalVoice]) -> String {
        let name = id.split(separator: ".").last.map(String.init) ?? id
        let fallback = LocalSpeaker.chooseVoice(requested: id, from: voices).voice?.name ?? "the system voice"
        return "\(name) (not installed; using \(fallback))"
    }

    public static var chatAnnounceChoices: [Choice] {
        ChatMonitorConfig.BeeperAnnounce.allCases.map { Choice(value: $0.rawValue, label: $0.label) }
    }

    public static var googleChatSourceChoices: [Choice] {
        ChatMonitorConfig.GoogleChatSource.allCases.map { Choice(value: $0.rawValue, label: $0.label) }
    }

    // MARK: - Numeric Limits & Steps

    public static let volumeSteps: [Int] = Array(
        stride(from: SpeakerConfig.minVolume, through: SpeakerConfig.maxVolume, by: SpeakerConfig.speakerVolumeStep)
    )

    public static let speakerVolumeLimits = Limits(
        min: SpeakerConfig.minVolume,
        max: SpeakerConfig.maxVolume,
        step: SpeakerConfig.speakerVolumeStep,
        defaultValue: SpeakerConfig.defaultAnnounceVolume
    )

    public static let announceVolumeLimits = Limits(
        min: SpeakerConfig.minVolume,
        max: SpeakerConfig.maxVolume,
        step: SpeakerConfig.announceVolumeStep,
        defaultValue: SpeakerConfig.defaultAnnounceVolume
    )

    public static let pauseMarginLimits = Limits(
        min: SpeakerConfig.minPauseMediaExtraSeconds,
        max: SpeakerConfig.maxPauseMediaExtraSeconds,
        step: SpeakerConfig.pauseMediaExtraSecondsStep,
        defaultValue: SpeakerConfig.defaultPauseMediaExtraSeconds
    )

    public static let chatPollIntervalLimits = Limits(
        min: ChatMonitorConfig.minPollInterval,
        max: ChatMonitorConfig.maxPollInterval,
        step: ChatMonitorConfig.pollIntervalStep,
        defaultValue: ChatMonitorConfig.defaultPollInterval
    )

    // MARK: - Quiet Hours Choices

    public static let defaultQuietHoursStart = "22:00"
    public static let defaultQuietHoursEnd = "07:00"

    /// Every half hour of the day (`00:00` through `23:30`).
    public static let halfHours: [String] = (0..<48).map {
        String(format: "%02d:%02d", $0 / 2, ($0 % 2) * 30)
    }

    /// Half-hour times for the Quiet Hours pickers. When `saved` is a non-empty
    /// time off the half-hour grid (such as `"07:15"`), it appears first
    /// followed by the 48 half hours so a hand-edited time stays visible
    /// without re-sorting the clock.
    public static func quietHoursTimeValues(keeping saved: String?) -> [String] {
        guard let raw = saved?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return halfHours
        }
        return halfHours.contains(raw) ? halfHours : [raw] + halfHours
    }

    public static func quietHoursChoices(keeping saved: String?) -> [Choice] {
        quietHoursTimeValues(keeping: saved).map { Choice(value: $0, label: $0) }
    }

    /// Normalises a `HH:mm` time string (`"7:05"` → `"07:05"`), or returns `nil`
    /// when `text` is not a valid 24-hour time.
    public static func normalizedQuietHour(_ text: String) -> String? {
        guard let minutes = SpeakerConfig.minutesSinceMidnight(text) else { return nil }
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    // MARK: - Outputs Summary

    public static let macPhoneOutputLabel = "Your phone"
    public static let remotePhoneOutputLabel = "This phone"

    /// The active outputs summary (`"Living Room + This Mac + Your phone"` on the
    /// Mac, substituting `"Your phone"` → `"This phone"` on the phone).
    public static func activeOutputsLabel(for config: SpeakerConfig, onPhone: Bool = false) -> String {
        config.activeOutputsLabel(phoneLabel: onPhone ? remotePhoneOutputLabel : macPhoneOutputLabel)
    }

    // MARK: - Catalog Entries for a Config

    public let entries: [Entry]
    private let byKey: [Key: Entry]

    public init(config: SpeakerConfig, systemVoices: [LocalVoice] = []) {
        let chat = config.effectiveChatMonitor
        let quietHoursOn = config.quietHoursEnabled == true
        let quietStart = config.quietHoursStart.flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultQuietHoursStart
        let quietEnd = config.quietHoursEnd.flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultQuietHoursEnd

        let speakerChoices = config.uniqueTargets().map {
            Choice(value: $0.key, label: $0.device.displayLine)
        }
        let volumeChoices = Self.volumeSteps.map {
            Choice(value: "\($0)", label: "\($0)%")
        }
        let localVoiceChoices = Self.localVoiceChoices(config: config, systemVoices: systemVoices)
        let localVoiceLabel = config.effectiveLocalEngine == .gemini ? "Fallback Mac voice" : "Voice"

        let built: [Entry] = [
            Entry(
                id: .enabled,
                label: "Enable Voice Broadcasting",
                kind: .toggle,
                shown: true
            ),
            Entry(
                id: .speechLength,
                label: "Speak",
                kind: .choice,
                choices: Self.speechLengthChoices,
                shown: true
            ),
            Entry(
                id: .announcementStyle,
                label: "Style",
                kind: .choice,
                choices: Self.announcementStyleChoices,
                shown: config.showsAnnouncementStyle
            ),
            Entry(
                id: .customStylePrompt,
                label: "Custom style",
                kind: .text,
                shown: config.showsAnnouncementStyle && config.effectiveAnnouncementStyle == .custom
            ),
            Entry(
                id: .styleModel,
                label: "Style with",
                kind: .choice,
                choices: Self.styleModelChoices,
                shown: config.showsAnnouncementStyle && config.effectiveAnnouncementStyle != .verbatim
            ),
            Entry(
                id: .speakerVolume,
                label: "Volume",
                kind: .number,
                choices: volumeChoices,
                limits: Self.speakerVolumeLimits,
                shown: config.showsHomeControls && config.defaultDevice != nil
            ),
            Entry(
                id: .announceVolumeEnabled,
                label: "Announce at a set volume",
                kind: .toggle,
                shown: config.showsHomeControls
            ),
            Entry(
                id: .announceVolume,
                label: "Announcement volume",
                kind: .number,
                limits: Self.announceVolumeLimits,
                shown: config.showsHomeControls && config.effectiveAnnounceVolumeEnabled
            ),
            Entry(
                id: .pauseMedia,
                label: "Pause media while announcing",
                kind: .toggle,
                shown: true
            ),
            Entry(
                id: .pauseMediaExtraSeconds,
                label: "Resume after",
                kind: .number,
                limits: Self.pauseMarginLimits,
                shown: config.effectivePauseMedia
            ),
            Entry(
                id: .quietHoursEnabled,
                label: "Enable Quiet Hours",
                kind: .toggle,
                shown: true
            ),
            Entry(
                id: .quietHoursStart,
                label: "Start",
                kind: .time,
                choices: Self.quietHoursChoices(keeping: quietStart),
                shown: quietHoursOn
            ),
            Entry(
                id: .quietHoursEnd,
                label: "End",
                kind: .time,
                choices: Self.quietHoursChoices(keeping: quietEnd),
                shown: quietHoursOn
            ),
            Entry(
                id: .speakHome,
                label: "Home speakers",
                kind: .toggle,
                shown: true
            ),
            Entry(
                id: .homeCastVoice,
                label: "Use selected voice on Home speakers (Cast)",
                kind: .toggle,
                shown: config.showsHomeCastVoice
            ),
            Entry(
                id: .defaultTarget,
                label: "Default speaker",
                kind: .choice,
                choices: speakerChoices,
                shown: config.showsHomeControls && !config.targets.isEmpty
            ),
            Entry(
                id: .speakLocal,
                label: "This Mac",
                kind: .toggle,
                shown: true
            ),
            Entry(
                id: .speakPhone,
                label: "Your phone",
                kind: .toggle,
                shown: true
            ),
            Entry(
                id: .localEngine,
                label: "Voice engine",
                kind: .choice,
                choices: Self.voiceEngineChoices,
                shown: config.showsVoiceEngine
            ),
            Entry(
                id: .geminiVoice,
                label: "Gemini voice",
                kind: .choice,
                choices: Self.geminiVoiceChoices(for: config),
                shown: config.showsGeminiVoice
            ),
            Entry(
                id: .localVoice,
                label: localVoiceLabel,
                kind: .choice,
                choices: localVoiceChoices,
                shown: config.effectiveSpeakLocal
            ),
            Entry(
                id: .phonePauseMedia,
                label: "Pause phone media while announcing",
                kind: .toggle,
                shown: config.effectiveSpeakPhone
            ),
            Entry(
                id: .phoneHeadphonesOnly,
                label: "Only announce on phone when headphones are connected",
                kind: .toggle,
                shown: config.effectiveSpeakPhone
            ),
            Entry(
                id: .announceClaudeCode,
                label: "Announce \(CodingAgent.claudeCode.displayName) replies",
                kind: .toggle,
                shown: true
            ),
            Entry(
                id: .announceAntigravity,
                label: "Announce \(CodingAgent.antigravity.displayName) replies",
                kind: .toggle,
                shown: true
            ),
            Entry(
                id: .announceOpenCode,
                label: "Announce \(CodingAgent.opencode.displayName) replies",
                kind: .toggle,
                shown: true
            ),
            Entry(
                id: .announceSource,
                label: "Say who it's from",
                kind: .choice,
                choices: Self.announceSourceChoices,
                shown: true
            ),
            Entry(
                id: .slackEnabled,
                label: "Announce Slack messages",
                kind: .toggle,
                shown: true
            ),
            Entry(
                id: .googleChatEnabled,
                label: "Announce Google Chat messages",
                kind: .toggle,
                shown: true
            ),
            Entry(
                id: .googleChatSource,
                label: "Read Google Chat via",
                kind: .choice,
                choices: Self.googleChatSourceChoices,
                shown: chat.googleChatEnabled
            ),
            Entry(
                id: .gwsAccount,
                label: "gws account (optional, e.g. you@gmail.com)",
                kind: .text,
                shown: chat.googleChatEnabled && chat.googleChatSource != .api
            ),
            Entry(
                id: .beeperEnabled,
                label: "Announce Beeper messages",
                kind: .toggle,
                shown: true
            ),
            Entry(
                id: .beeperAnnounce,
                label: "Announce",
                kind: .choice,
                choices: Self.chatAnnounceChoices,
                shown: chat.beeperEnabled
            ),
            Entry(
                id: .beeperAddress,
                label: "Address",
                kind: .text,
                shown: chat.beeperEnabled
            ),
            Entry(
                id: .courierEnabled,
                label: "Announce Courier messages",
                kind: .toggle,
                shown: true
            ),
            Entry(
                id: .courierAnnounce,
                label: "Announce",
                kind: .choice,
                choices: Self.chatAnnounceChoices,
                shown: chat.courierEnabled
            ),
            Entry(
                id: .courierAddress,
                label: "Address",
                kind: .text,
                shown: chat.courierEnabled
            ),
            Entry(
                id: .muteOwnMessages,
                label: "Skip messages I sent",
                kind: .toggle,
                shown: true
            ),
            Entry(
                id: .pollIntervalSeconds,
                label: "Poll Interval",
                kind: .number,
                limits: Self.chatPollIntervalLimits,
                shown: true
            ),
        ]

        self.entries = built
        self.byKey = Dictionary(uniqueKeysWithValues: built.map { ($0.id, $0) })
    }

    public func entry(_ key: Key) -> Entry {
        byKey[key]!
    }

    public func entry(forKey rawKey: String) -> Entry? {
        guard let key = Key(rawValue: rawKey) else { return nil }
        return byKey[key]
    }
}
