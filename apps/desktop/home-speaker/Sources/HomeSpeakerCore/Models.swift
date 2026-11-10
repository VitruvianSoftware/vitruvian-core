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

public struct SpeakerDevice: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var type: String
    public var name: String
    public var room: String?

    /// Spelled out (not synthesized) so the config writer knows which keys of
    /// a device are this app's and which belong to someone else.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, type, name, room
    }

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

/// How an announcement is worded before it is spoken. `verbatim` reads the
/// reply as written, cleaned for speech, exactly as before this setting
/// existed; the others have a language model say it again in a sentence or
/// two (`AnnouncementStylist`).
public enum AnnouncementStyle: String, Codable, CaseIterable, Sendable {
    case verbatim
    case plain
    case briefing
    case casual
    case custom

    public var label: String {
        switch self {
        case .verbatim: return "As written"
        case .plain: return "Plain summary"
        case .briefing: return "Status update"
        case .casual: return "Conversational"
        case .custom: return "Custom…"
        }
    }

    /// A value this version does not know reads as `verbatim`, so a newer
    /// settings file never stops the settings reading.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AnnouncementStyle(rawValue: raw) ?? .verbatim
    }
}

/// Which model rewrites an announcement in its style.
public enum StyleModel: String, Codable, CaseIterable, Sendable {
    /// Apple's on-device model (FoundationModels): private and free.
    case apple
    /// Gemini, with the saved Gemini API key; Apple's model when that fails.
    case gemini

    public var label: String {
        switch self {
        case .apple: return "Apple (on this Mac)"
        case .gemini: return "Gemini"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StyleModel(rawValue: raw) ?? .apple
    }
}

/// What speaks on this Mac.
public enum LocalVoiceEngine: String, Codable, CaseIterable, Sendable {
    /// A system voice (`local_voice`).
    case apple
    /// Gemini's speech model (`gemini_voice`), with the system voice when
    /// there is no key or Gemini fails.
    case gemini

    public var label: String {
        switch self {
        case .apple: return "Apple (System)"
        case .gemini: return "Gemini TTS"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LocalVoiceEngine(rawValue: raw) ?? .apple
    }
}

/// The prebuilt Gemini voices offered in Settings. Gemini has more; the
/// stored value is the voice's name, so one set by hand still works.
public enum GeminiVoice: String, Codable, CaseIterable, Sendable {
    case kore = "Kore"
    case puck = "Puck"
    case aoede = "Aoede"
    case charon = "Charon"
    case zephyr = "Zephyr"
    case fenrir = "Fenrir"
    case leda = "Leda"
    case orus = "Orus"
    case freeman = "voice_vaoo7ayczx69"
    case james = "voice_o1be80ujj8bb"

    public static let defaultVoice: GeminiVoice = .kore

    public var label: String {
        switch self {
        case .kore: return "Kore · Warm & clear"
        case .puck: return "Puck · Upbeat"
        case .aoede: return "Aoede · Natural"
        case .charon: return "Charon · Calm & steady"
        case .zephyr: return "Zephyr · Bright"
        case .fenrir: return "Fenrir · Deep"
        case .leda: return "Leda · Composed"
        case .orus: return "Orus · Crisp"
        case .freeman: return "Freeman · Custom"
        case .james: return "James · Custom"
        }
    }
}

/// A cloned custom voice available in Gemini TTS, configured from the Android app
/// or Vitruvian remote agent.
public struct CustomVoice: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var audioPath: String?
    public var transcript: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case audioPath = "audio_path"
        case transcript
        case createdAt = "created_at"
    }

    public init(id: String, name: String, audioPath: String? = nil, transcript: String? = nil, createdAt: String? = nil) {
        self.id = id
        self.name = name
        self.audioPath = audioPath
        self.transcript = transcript
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? self.id
        self.audioPath = try? container.decodeIfPresent(String.self, forKey: .audioPath)
        self.transcript = try? container.decodeIfPresent(String.self, forKey: .transcript)
        self.createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

public struct SpeakerConfig: Codable, Equatable {
    public var enabled: Bool
    public var isEnabled: Bool {
        get { enabled }
        set { enabled = newValue }
    }
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
    /// Announce at a set volume: raise or lower the speaker to
    /// `announceVolume` for each announcement, then put it back.
    public var announceVolumeEnabled: Bool?
    public var announceVolume: Int?
    public var quietHoursEnabled: Bool?
    public var quietHoursStart: String?
    public var quietHoursEnd: String?
    public var snoozeUntil: Date?
    /// Chat/Slack monitor settings. Optional so configs written before this
    /// key existed still decode; read through `effectiveChatMonitor`.
    public var chatMonitor: ChatMonitorConfig?
    /// Where announcements play (docs/local-speech.md). All three are
    /// optional so an older config, or an older phone app, changes nothing:
    /// absent means the Google Home speakers only, as before. Read through
    /// the `effective…` accessors.
    public var speakHome: Bool?
    public var speakLocal: Bool?
    public var speakPhone: Bool?
    public var phonePauseMedia: Bool?
    public var phoneHeadphonesOnly: Bool?
    /// `AVSpeechSynthesisVoice` identifier used on this Mac.
    public var localVoice: String?
    /// Speak what each coding agent sends, under the master switch
    /// (`enabled`). Optional so a config written before these keys existed
    /// still speaks for all of them, as it did: read through `announces(_:)`.
    public var announceClaudeCode: Bool?
    public var announceAntigravity: Bool?
    public var announceOpenCode: Bool?
    /// How announcements are worded (`AnnouncementStylist`). All five are
    /// optional so an older file speaks as written, in the system voice:
    /// read through the `effective…` accessors.
    public var announcementStyle: AnnouncementStyle?
    /// The instruction for `.custom`.
    public var customStylePrompt: String?
    public var styleModel: StyleModel?
    /// What speaks on this Mac, and the Gemini voice when that is Gemini.
    public var localEngine: LocalVoiceEngine?
    public var geminiVoice: String?
    /// Cloned custom voices, configured via Android or remote agent.
    public var customVoices: [CustomVoice]?
    /// Play the Gemini voice on the Home speakers too, cast over the local
    /// network (`CastSpeaker`), with Google Assistant Broadcast whenever
    /// that cannot be done. Optional so older configs broadcast as before.
    public var homeCastVoice: Bool?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case enabled
        case defaultTarget = "default_target"
        case structureId = "structure_id"
        case structureName = "structure_name"
        case targets
        case speechLength = "speech_length"
        case pauseMedia = "pause_media"
        case pauseMediaExtraSeconds = "pause_media_extra_seconds"
        case announceVolumeEnabled = "announce_volume_enabled"
        case announceVolume = "announce_volume"
        case quietHoursEnabled = "quiet_hours_enabled"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
        case snoozeUntil = "snooze_until"
        case chatMonitor = "chat_monitor"
        case speakHome = "speak_home"
        case speakLocal = "speak_local"
        case speakPhone = "speak_phone"
        case phonePauseMedia = "phone_pause_media"
        case phoneHeadphonesOnly = "phone_headphones_only"
        case localVoice = "local_voice"
        case announceClaudeCode = "announce_claude_code"
        case announceAntigravity = "announce_antigravity"
        case announceOpenCode = "announce_opencode"
        case announcementStyle = "announcement_style"
        case customStylePrompt = "custom_style_prompt"
        case styleModel = "style_model"
        case localEngine = "local_engine"
        case geminiVoice = "gemini_voice"
        case customVoices = "custom_voices"
        case homeCastVoice = "home_cast_voice"
    }

    /// The Mac voice when `local_voice` is absent: a natural Siri voice.
    /// "Aaron (Enhanced)": the Siri Aaron voice as an installable bundle. The
    /// Siri-only `com.apple.siri.natural.Aaron` is reserved for Apple-signed
    /// processes -- HomeSpeaker cannot see it and fell back to a novelty voice.
    public static let defaultLocalVoice = "com.apple.ttsbundle.siri_Aaron_en-US_premium"

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
        snoozeUntil: Date? = nil,
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
        self.snoozeUntil = snoozeUntil
        self.chatMonitor = chatMonitor
    }

    public static let minVolume = 0
    public static let maxVolume = 100
    public static let speakerVolumeStep = 10
    public static let announceVolumeStep = 5
    public static let defaultAnnounceVolume = 60

    public static let minPauseMediaExtraSeconds = 0
    public static let maxPauseMediaExtraSeconds = 10
    public static let pauseMediaExtraSecondsStep = 1
    public static let defaultPauseMediaExtraSeconds = 1

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decode(Bool.self, forKey: .enabled)
        self.defaultTarget = try container.decode(String.self, forKey: .defaultTarget)
        self.structureId = try container.decode(String.self, forKey: .structureId)
        self.structureName = try container.decodeIfPresent(String.self, forKey: .structureName)
        self.targets = try container.decode([String: SpeakerDevice].self, forKey: .targets)
        self.speechLength = try container.decodeIfPresent(SpeechLength.self, forKey: .speechLength)
        self.pauseMedia = try container.decodeIfPresent(Bool.self, forKey: .pauseMedia)
        self.pauseMediaExtraSeconds = try container.decodeIfPresent(Double.self, forKey: .pauseMediaExtraSeconds)
        self.announceVolumeEnabled = try container.decodeIfPresent(Bool.self, forKey: .announceVolumeEnabled)
        self.announceVolume = try container.decodeIfPresent(Int.self, forKey: .announceVolume)
        self.quietHoursEnabled = try container.decodeIfPresent(Bool.self, forKey: .quietHoursEnabled)
        self.quietHoursStart = try container.decodeIfPresent(String.self, forKey: .quietHoursStart)
        self.quietHoursEnd = try container.decodeIfPresent(String.self, forKey: .quietHoursEnd)
        if let raw = try? container.decodeIfPresent(String.self, forKey: .snoozeUntil) {
            self.snoozeUntil = Self.parseISO8601(raw)
        } else {
            self.snoozeUntil = nil
        }
        self.chatMonitor = try container.decodeIfPresent(ChatMonitorConfig.self, forKey: .chatMonitor)
        self.speakHome = try container.decodeIfPresent(Bool.self, forKey: .speakHome)
        self.speakLocal = try container.decodeIfPresent(Bool.self, forKey: .speakLocal)
        self.speakPhone = try container.decodeIfPresent(Bool.self, forKey: .speakPhone)
        self.phonePauseMedia = try container.decodeIfPresent(Bool.self, forKey: .phonePauseMedia)
        self.phoneHeadphonesOnly = try container.decodeIfPresent(Bool.self, forKey: .phoneHeadphonesOnly)
        self.localVoice = try container.decodeIfPresent(String.self, forKey: .localVoice)
        self.announceClaudeCode = try container.decodeIfPresent(Bool.self, forKey: .announceClaudeCode)
        self.announceAntigravity = try container.decodeIfPresent(Bool.self, forKey: .announceAntigravity)
        self.announceOpenCode = try container.decodeIfPresent(Bool.self, forKey: .announceOpenCode)
        self.announcementStyle = try container.decodeIfPresent(AnnouncementStyle.self, forKey: .announcementStyle)
        self.customStylePrompt = try container.decodeIfPresent(String.self, forKey: .customStylePrompt)
        self.styleModel = try container.decodeIfPresent(StyleModel.self, forKey: .styleModel)
        self.localEngine = try container.decodeIfPresent(LocalVoiceEngine.self, forKey: .localEngine)
        self.geminiVoice = try container.decodeIfPresent(String.self, forKey: .geminiVoice)
        self.customVoices = try container.decodeIfPresent([CustomVoice].self, forKey: .customVoices)
        self.homeCastVoice = try container.decodeIfPresent(Bool.self, forKey: .homeCastVoice)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(defaultTarget, forKey: .defaultTarget)
        try container.encode(structureId, forKey: .structureId)
        try container.encodeIfPresent(structureName, forKey: .structureName)
        try container.encode(targets, forKey: .targets)
        try container.encodeIfPresent(speechLength, forKey: .speechLength)
        try container.encodeIfPresent(pauseMedia, forKey: .pauseMedia)
        try container.encodeIfPresent(pauseMediaExtraSeconds, forKey: .pauseMediaExtraSeconds)
        try container.encodeIfPresent(announceVolumeEnabled, forKey: .announceVolumeEnabled)
        try container.encodeIfPresent(announceVolume, forKey: .announceVolume)
        try container.encodeIfPresent(quietHoursEnabled, forKey: .quietHoursEnabled)
        try container.encodeIfPresent(quietHoursStart, forKey: .quietHoursStart)
        try container.encodeIfPresent(quietHoursEnd, forKey: .quietHoursEnd)
        if let snoozeUntil {
            try container.encode(Self.formatISO8601UTC(snoozeUntil), forKey: .snoozeUntil)
        }
        try container.encodeIfPresent(chatMonitor, forKey: .chatMonitor)
        try container.encodeIfPresent(speakHome, forKey: .speakHome)
        try container.encodeIfPresent(speakLocal, forKey: .speakLocal)
        try container.encodeIfPresent(speakPhone, forKey: .speakPhone)
        try container.encodeIfPresent(phonePauseMedia, forKey: .phonePauseMedia)
        try container.encodeIfPresent(phoneHeadphonesOnly, forKey: .phoneHeadphonesOnly)
        try container.encodeIfPresent(localVoice, forKey: .localVoice)
        try container.encodeIfPresent(announceClaudeCode, forKey: .announceClaudeCode)
        try container.encodeIfPresent(announceAntigravity, forKey: .announceAntigravity)
        try container.encodeIfPresent(announceOpenCode, forKey: .announceOpenCode)
        try container.encodeIfPresent(announcementStyle, forKey: .announcementStyle)
        try container.encodeIfPresent(customStylePrompt, forKey: .customStylePrompt)
        try container.encodeIfPresent(styleModel, forKey: .styleModel)
        try container.encodeIfPresent(localEngine, forKey: .localEngine)
        try container.encodeIfPresent(geminiVoice, forKey: .geminiVoice)
        try container.encodeIfPresent(customVoices, forKey: .customVoices)
        try container.encodeIfPresent(homeCastVoice, forKey: .homeCastVoice)
    }

    /// Summary, not headline: a config written before this key existed was
    /// silently cutting replies after two sentences.
    public var effectiveAnnounceVolumeEnabled: Bool {
        get { announceVolumeEnabled ?? false }
        set { announceVolumeEnabled = newValue }
    }

    /// 60 % unless chosen: audible across a room without startling anyone.
    public var effectiveAnnounceVolume: Int {
        get { min(max(announceVolume ?? Self.defaultAnnounceVolume, Self.minVolume), Self.maxVolume) }
        set { announceVolume = min(max(newValue, Self.minVolume), Self.maxVolume) }
    }

    public var effectivePauseMedia: Bool {
        get { pauseMedia ?? false }
        set { pauseMedia = newValue }
    }

    public var effectivePauseMediaExtraSeconds: Double {
        get { pauseMediaExtraSeconds ?? Double(Self.defaultPauseMediaExtraSeconds) }
        set { pauseMediaExtraSeconds = min(max(newValue, Double(Self.minPauseMediaExtraSeconds)), Double(Self.maxPauseMediaExtraSeconds)) }
    }

    public var effectiveSpeechLength: SpeechLength {
        get { speechLength ?? .summary }
        set { speechLength = newValue }
    }

    public var effectiveChatMonitor: ChatMonitorConfig {
        get { chatMonitor ?? ChatMonitorConfig() }
        set { chatMonitor = newValue }
    }

    /// Announce on the Google Home target. On unless switched off.
    public var effectiveSpeakHome: Bool {
        get { speakHome ?? true }
        set { speakHome = newValue }
    }

    /// Also speak on this Mac. Off unless switched on.
    public var effectiveSpeakLocal: Bool {
        get { speakLocal ?? false }
        set { speakLocal = newValue }
    }

    /// Also speak on the paired phone (via vitruvian-remote-agent). Off unless switched on.
    public var effectiveSpeakPhone: Bool {
        get { speakPhone ?? false }
        set { speakPhone = newValue }
    }

    /// Pause media on the phone while announcing on the phone. Off unless switched on.
    public var effectivePhonePauseMedia: Bool {
        get { phonePauseMedia ?? false }
        set { phonePauseMedia = newValue }
    }

    /// Only announce on the phone when headphones are connected to the phone. Off unless switched on.
    public var effectivePhoneHeadphonesOnly: Bool {
        get { phoneHeadphonesOnly ?? false }
        set { phoneHeadphonesOnly = newValue }
    }

    /// The voice asked for on this Mac; an empty string counts as absent.
    public var effectiveLocalVoice: String {
        get {
            let v = localVoice?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return v.isEmpty ? Self.defaultLocalVoice : v
        }
        set { localVoice = newValue }
    }

    /// As written unless chosen: the rewrite is opt-in.
    public var effectiveAnnouncementStyle: AnnouncementStyle {
        get { announcementStyle ?? .verbatim }
        set { announcementStyle = newValue }
    }

    /// The custom instruction, trimmed; empty when there is none.
    public var effectiveCustomStylePrompt: String {
        get { customStylePrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        set { customStylePrompt = newValue }
    }

    /// Apple's on-device model unless chosen.
    public var effectiveStyleModel: StyleModel {
        get { styleModel ?? .apple }
        set { styleModel = newValue }
    }

    /// The system voice unless chosen.
    public var effectiveLocalEngine: LocalVoiceEngine {
        get { localEngine ?? .apple }
        set { localEngine = newValue }
    }

    /// The Gemini voice's name; an empty string counts as absent.
    public var effectiveGeminiVoice: String {
        get {
            let v = geminiVoice?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return v.isEmpty ? GeminiVoice.defaultVoice.rawValue : v
        }
        set { geminiVoice = newValue }
    }

    /// Cloned custom voices configured on Android or remote devices, deduplicated by id.
    public var effectiveCustomVoices: [CustomVoice] {
        guard let voices = customVoices else { return [] }
        var seen = Set<String>()
        var result: [CustomVoice] = []
        for v in voices {
            if seen.insert(v.id).inserted {
                result.append(v)
            }
        }
        return result
    }

    /// Display label for a Gemini voice identifier (prebuilt, cloned, or raw).
    public func geminiVoiceDisplayName(_ id: String? = nil) -> String {
        let target = id ?? effectiveGeminiVoice
        if let prebuilt = GeminiVoice(rawValue: target) {
            return prebuilt.label
        }
        if let custom = effectiveCustomVoices.first(where: { $0.id == target }) {
            return "\(custom.name) (cloned)"
        }
        return target
    }

    /// Available Gemini voice choices: prebuilt voices followed by cloned custom voices.
    /// If an unknown active voice is set, it is included as the first entry.
    public func geminiVoiceOptions() -> [(value: String, label: String)] {
        var options: [(value: String, label: String)] = GeminiVoice.allCases.map { ($0.rawValue, $0.label) }
        for voice in effectiveCustomVoices where !options.contains(where: { $0.value == voice.id }) {
            options.append((value: voice.id, label: "\(voice.name) (cloned)"))
        }
        let current = effectiveGeminiVoice
        if !options.contains(where: { $0.value == current }) {
            options.insert((value: current, label: current), at: 0)
        }
        return options
    }

    /// Cast the selected voice to the Home speakers. Off unless switched on,
    /// and only used while the voice engine is Gemini.
    public var effectiveHomeCastVoice: Bool {
        get { homeCastVoice ?? false }
        set { homeCastVoice = newValue }
    }

    /// Whether the voice engine choice matters anywhere: this Mac, the
    /// phone, or the Home speakers when they cast the selected voice.
    public var usesVoiceEngine: Bool {
        effectiveSpeakLocal || effectiveSpeakPhone || (effectiveSpeakHome && effectiveHomeCastVoice)
    }

    // MARK: What the settings surfaces show
    //
    // One answer for the menu bar, both Settings and the extension's island,
    // so a control is never shown on one and hidden on another. Hidden is
    // not reset: each value stays saved, and comes back as it was.

    /// Under the Broadcasting switch while it is off, on the menu bar and
    /// the island, where it is then the only control: what off means.
    public static let broadcastingOffLine = "Broadcasting is off — automatic announcements are paused."

    /// True when at least one coding agent has announcements enabled.
    public var anyCodingAgentEnabled: Bool { CodingAgent.allCases.contains(where: announces) }

    /// The Home speakers' own controls (the speaker, its volume, announce
    /// at a set volume): only while the Home speakers speak.
    public var showsHomeControls: Bool { effectiveSpeakHome }

    /// Casting the selected voice: only with the Home speakers on and the
    /// Gemini engine chosen, the one engine a Home speaker can cast.
    public var showsHomeCastVoice: Bool { effectiveSpeakHome && effectiveLocalEngine == .gemini }

    /// The voice engine picker: while an output it could drive is on. That
    /// includes the Home speakers on their own, since picking Gemini there is
    /// what offers casting; otherwise casting could never be reached.
    public var showsVoiceEngine: Bool { effectiveSpeakLocal || effectiveSpeakPhone || effectiveSpeakHome }

    /// The Gemini voice (and its key): only where Gemini actually speaks.
    public var showsGeminiVoice: Bool { geminiSpeaks }

    /// The style and the model that applies it reword coding agents' replies
    /// only (chat and typed text are read as written): shown while at least
    /// one agent announces. How much is said is not among them: it cuts
    /// every announcement, chat and typed text too.
    public var showsAnnouncementStyle: Bool { CodingAgent.allCases.contains(where: announces) }

    /// Whether the Gemini API key field belongs under the style controls:
    /// a coding agent announces, the style rewords with Gemini, and the key is
    /// not already shown under the Gemini voice controls (`!geminiSpeaks`).
    public var showsStyleGeminiKey: Bool {
        showsAnnouncementStyle && effectiveAnnouncementStyle != .verbatim && effectiveStyleModel == .gemini && !geminiSpeaks
    }

    /// What the Home speakers' Cast voice adds up to, for both Settings'
    /// "Where to speak" footer; nil when it is off.
    public static func homeCastFooter(_ c: SpeakerConfig) -> String? {
        guard c.effectiveSpeakHome && c.effectiveHomeCastVoice else { return nil }
        guard c.effectiveLocalEngine == .gemini else {
            return "The Home speakers use Google Assistant's voice: casting the selected voice needs the Gemini voice engine."
        }
        return "The Home speakers play the Gemini voice over this Wi-Fi network, falling back to Google Assistant Broadcast when they can't."
    }

    /// What the outputs mean together, as HomeSpeaker's Settings says it.
    public static func outputsFooter(_ c: SpeakerConfig) -> String {
        if !c.effectiveSpeakHome && !c.effectiveSpeakLocal && !c.effectiveSpeakPhone {
            return "All outputs are off, so nothing is spoken anywhere."
        }
        var lines: [String] = []
        if (c.effectiveSpeakLocal || c.effectiveSpeakPhone) && c.effectiveLocalEngine == .gemini {
            lines.append("Gemini TTS sends what this Mac says to Google to be spoken; with no key, or when Gemini fails, the Mac voice speaks instead.")
        }
        if let cast = homeCastFooter(c) { lines.append(cast) }
        if c.effectiveSpeakLocal {
            lines.append("This Mac speaks at its own volume. More voices: System Settings › Accessibility › Read & Speak › System voice › ⓘ › Voice, then download an \"(Enhanced)\" voice.")
        }
        if c.effectiveSpeakPhone {
            lines.append(c.effectiveLocalEngine == .gemini
                ? "Your phone plays the Gemini voice (or Android's on-device voice when Gemini is unavailable) via Vitruvian Remote."
                : "Your phone speaks with Android's on-device voice via Vitruvian Remote.")
        }
        if c.effectiveSpeakHome && c.effectiveSpeakLocal {
            lines.append("Both speak at the same time. Quiet hours and pausing media cover both.")
        }
        return lines.joined(separator: " ")
    }

    /// The canonical "Where to speak" footer for this configuration.
    public var outputsFooter: String { Self.outputsFooter(self) }

    /// Whether Gemini speaks somewhere, so its key is asked for.
    public var geminiSpeaks: Bool {
        usesVoiceEngine && effectiveLocalEngine == .gemini
    }

    /// Where chat messages go once read, for the chat monitor's privacy
    /// line in both Settings: Google Home, and Gemini while it speaks on
    /// the Home speakers, this Mac or this phone. (The rewording is for
    /// coding agents' replies only.)
    public var chatMessagesSentTo: String {
        if effectiveLocalEngine == .gemini {
            var places: [String] = []
            if effectiveSpeakHome && effectiveHomeCastVoice { places.append("your Home speakers") }
            if effectiveSpeakLocal { places.append("this Mac") }
            if effectiveSpeakPhone { places.append("your phone") }
            if !places.isEmpty {
                let joined = places.count == 1
                    ? places[0]
                    : places.dropLast().joined(separator: ", ") + " and " + places.last!
                return "Messages are sent to Google Home, and to Gemini to be spoken on \(joined) (Gemini TTS); nowhere else."
            }
        }
        return "Nothing is sent anywhere except to Google Home."
    }

    /// Whether `agent`'s announcements are spoken, the master switch
    /// aside: on unless switched off.
    public func announces(_ agent: CodingAgent) -> Bool {
        switch agent {
        case .claudeCode: return announceClaudeCode ?? true
        case .antigravity: return announceAntigravity ?? true
        case .opencode: return announceOpenCode ?? true
        }
    }

    public mutating func setAnnounces(_ agent: CodingAgent, _ isOn: Bool) {
        switch agent {
        case .claudeCode: announceClaudeCode = isOn
        case .antigravity: announceAntigravity = isOn
        case .opencode: announceOpenCode = isOn
        }
    }

    /// Where announcements go, for the menu bar: "Lake Office + This Mac + Your phone";
    /// empty when all outputs are off.
    public var activeOutputsLabel: String {
        activeOutputsLabel(phoneLabel: "Your phone")
    }

    /// Where announcements go, using `phoneLabel` for the phone output
    /// (`"Your phone"` on the Mac, `"This phone"` on the phone).
    public func activeOutputsLabel(phoneLabel: String) -> String {
        var parts: [String] = []
        if effectiveSpeakHome { parts.append(defaultDevice?.name ?? "No speaker picked") }
        if effectiveSpeakLocal { parts.append("This Mac") }
        if effectiveSpeakPhone { parts.append(phoneLabel) }
        return parts.joined(separator: " + ")
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
    /// Returns false with nothing changed if discovered is empty.
    @discardableResult
    public mutating func applyDiscovery(structureId: String, structureName: String?, targets discovered: [String: SpeakerDevice]) -> Bool {
        guard !discovered.isEmpty else { return false }
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
        return true
    }

    /// Drops one alias. When it was the default, the first remaining
    /// speaker by name (one alias per device, as `uniqueTargets` gives
    /// them) becomes the default, or none when the list is now empty.
    public mutating func removeTarget(_ key: String) {
        targets.removeValue(forKey: key)
        if defaultTarget == key {
            defaultTarget = uniqueTargets().first?.key ?? ""
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

    /// True when `snoozeUntil` is set and lies strictly after `date`.
    public func isSnoozed(at date: Date = Date()) -> Bool {
        guard let snoozeUntil else { return false }
        return snoozeUntil > date
    }

    /// Encodes `date` as an ISO-8601 UTC string (`"2026-11-10T06:30:00Z"`).
    public static func formatISO8601UTC(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// Parses an ISO-8601 timestamp string (with or without fractional seconds).
    public static func parseISO8601(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: trimmed) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: trimmed)
    }

    /// Local time `"HH:mm"` (24h) for `date` in `calendar`.
    public static func localTimeHHmm(_ date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    /// `"Snoozed until HH:mm"` in local time.
    public static func snoozedUntilLine(_ date: Date, calendar: Calendar = .current) -> String {
        "Snoozed until \(localTimeHHmm(date, calendar: calendar))"
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

/// Settings for the in-app chat monitor. Every source is OFF by default:
/// reading someone's Slack, Google Chat, Beeper or Courier is opt-in, never a
/// surprise on first launch. Tokens never live here — see `SecretStore`.
public struct ChatMonitorConfig: Codable, Equatable {
    public static let minPollInterval = 5
    public static let maxPollInterval = 300
    public static let defaultPollInterval = 15
    public static let pollIntervalStep = 5

    /// How Google Chat is read. `api` uses the app's own Google login (needs
    /// Chat permission granted once); `gws` shells out to the Google Workspace
    /// CLI when the user already has it installed and signed in; `auto` picks
    /// the API when its permission is present, otherwise gws when installed.
    public enum GoogleChatSource: String, Codable, CaseIterable, Sendable {
        case auto, api, gws

        public var label: String {
            switch self {
            case .auto: return "Automatic"
            case .api: return "Google API (this app's login)"
            case .gws: return "gws command-line tool"
            }
        }
    }

    /// Which Beeper (or Courier) messages are spoken: direct messages and
    /// group messages that mention you, or every message.
    public enum BeeperAnnounce: String, Codable, CaseIterable, Sendable {
        case directAndMentions = "direct_and_mentions"
        case all

        /// What the app's and the Vitruvian tool's Settings call it.
        public var title: String {
            switch self {
            case .directAndMentions: return "Direct messages and mentions"
            case .all: return "Every message"
            }
        }

        public var label: String { title }
    }

    public var slackEnabled: Bool
    public var googleChatEnabled: Bool
    public var pollIntervalSeconds: Int
    public var muteOwnMessages: Bool
    public var googleChatSource: GoogleChatSource
    /// `--account` passed to gws; empty means gws's default account.
    public var gwsAccount: String
    /// Read Beeper Desktop's local API on this Mac (ChatAppClient).
    public var beeperEnabled: Bool
    public var beeperAnnounce: BeeperAnnounce
    /// The Beeper networks not spoken, by `ChatAppClient.networkKey`
    /// ("whatsapp", "telegram"). Read at each poll, so muting one never
    /// restarts the monitor (`ChatMonitorReconciliation`).
    public var beeperMutedNetworks: [String]
    /// Where Beeper's API is, as typed in Settings; empty is its default
    /// (`ChatApp.defaultBaseURL`). Only an http address on this Mac is used.
    public var beeperAddress: String
    /// Read Courier's local API on this Mac: the same API as Beeper's, with
    /// its own address, token, Announce choice and network switches. Off
    /// until switched on, which Settings allows once a token is saved.
    public var courierEnabled: Bool
    public var courierAnnounce: BeeperAnnounce
    /// The Courier networks not spoken, by `ChatAppClient.networkKey`;
    /// Courier's own list, apart from Beeper's.
    public var courierMutedNetworks: [String]
    /// Where Courier's API is; empty is its default.
    public var courierAddress: String
    /// Courier networks read through Courier even while HomeSpeaker's own
    /// Slack or Google Chat reader is on, by `ChatAppClient.networkKey`
    /// ("slack"). Courier cannot say which Slack workspace an account is,
    /// so without this every Courier Slack account is left to that reader.
    public var courierReadAnyway: [String]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case slackEnabled = "slack_enabled"
        case googleChatEnabled = "google_chat_enabled"
        case pollIntervalSeconds = "poll_interval_seconds"
        case muteOwnMessages = "mute_own_messages"
        case googleChatSource = "google_chat_source"
        case gwsAccount = "gws_account"
        case beeperEnabled = "beeper_enabled"
        case beeperAnnounce = "beeper_announce"
        case beeperMutedNetworks = "beeper_muted_networks"
        case beeperAddress = "beeper_address"
        case courierEnabled = "courier_enabled"
        case courierAnnounce = "courier_announce"
        case courierMutedNetworks = "courier_muted_networks"
        case courierAddress = "courier_address"
        case courierReadAnyway = "courier_read_anyway"
    }

    public init(
        slackEnabled: Bool = false,
        googleChatEnabled: Bool = false,
        pollIntervalSeconds: Int = 15,
        muteOwnMessages: Bool = true,
        googleChatSource: GoogleChatSource = .auto,
        gwsAccount: String = "",
        beeperEnabled: Bool = false,
        beeperAnnounce: BeeperAnnounce = .directAndMentions,
        beeperMutedNetworks: [String] = [],
        beeperAddress: String = "",
        courierEnabled: Bool = false,
        courierAnnounce: BeeperAnnounce = .directAndMentions,
        courierMutedNetworks: [String] = [],
        courierAddress: String = "",
        courierReadAnyway: [String] = []
    ) {
        self.slackEnabled = slackEnabled
        self.googleChatEnabled = googleChatEnabled
        self.pollIntervalSeconds = pollIntervalSeconds
        self.muteOwnMessages = muteOwnMessages
        self.googleChatSource = googleChatSource
        self.gwsAccount = gwsAccount
        self.beeperEnabled = beeperEnabled
        self.beeperAnnounce = beeperAnnounce
        self.beeperMutedNetworks = beeperMutedNetworks
        self.beeperAddress = beeperAddress
        self.courierEnabled = courierEnabled
        self.courierAnnounce = courierAnnounce
        self.courierMutedNetworks = courierMutedNetworks
        self.courierAddress = courierAddress
        self.courierReadAnyway = courierReadAnyway
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slackEnabled = try c.decodeIfPresent(Bool.self, forKey: .slackEnabled) ?? false
        googleChatEnabled = try c.decodeIfPresent(Bool.self, forKey: .googleChatEnabled) ?? false
        pollIntervalSeconds = try c.decodeIfPresent(Int.self, forKey: .pollIntervalSeconds) ?? 15
        muteOwnMessages = try c.decodeIfPresent(Bool.self, forKey: .muteOwnMessages) ?? true
        googleChatSource = try c.decodeIfPresent(GoogleChatSource.self, forKey: .googleChatSource) ?? .auto
        gwsAccount = try c.decodeIfPresent(String.self, forKey: .gwsAccount) ?? ""
        beeperEnabled = try c.decodeIfPresent(Bool.self, forKey: .beeperEnabled) ?? false
        // A choice this version does not know reads as the default, so a
        // newer file never stops the settings reading.
        beeperAnnounce = (try? c.decodeIfPresent(BeeperAnnounce.self, forKey: .beeperAnnounce)) ?? .directAndMentions
        beeperMutedNetworks = try c.decodeIfPresent([String].self, forKey: .beeperMutedNetworks) ?? []
        beeperAddress = try c.decodeIfPresent(String.self, forKey: .beeperAddress) ?? ""
        courierEnabled = try c.decodeIfPresent(Bool.self, forKey: .courierEnabled) ?? false
        courierAnnounce = (try? c.decodeIfPresent(BeeperAnnounce.self, forKey: .courierAnnounce)) ?? .directAndMentions
        courierMutedNetworks = try c.decodeIfPresent([String].self, forKey: .courierMutedNetworks) ?? []
        courierAddress = try c.decodeIfPresent(String.self, forKey: .courierAddress) ?? ""
        courierReadAnyway = try c.decodeIfPresent([String].self, forKey: .courierReadAnyway) ?? []
    }

    public var clampedPollInterval: Int {
        min(max(pollIntervalSeconds, Self.minPollInterval), Self.maxPollInterval)
    }

    /// True when at least one source is switched on.
    public var anySourceEnabled: Bool { slackEnabled || googleChatEnabled || beeperEnabled || courierEnabled }

    /// A Beeper network's switch: off mutes the network (by its
    /// `ChatAppClient.networkKey`), on reads it again. The extension's
    /// pages and the app's Settings window both save through this. Muting
    /// a muted network, or reading one already read, changes nothing, so
    /// the saved order stays and a caller can tell nothing changed.
    public mutating func setBeeperNetwork(_ key: String, reading: Bool) {
        setNetwork(key, of: .beeper, reading: reading)
    }

    /// The same switch in `app`'s own list.
    public mutating func setNetwork(_ key: String, of app: ChatApp, reading: Bool) {
        var muted = mutedNetworks(for: app)
        if reading {
            muted.removeAll { $0 == key }
        } else if !muted.contains(key) {
            muted.append(key)
        }
        self[keyPath: Self.mutedNetworksKey(app)] = muted
    }

    // MARK: Each chat app's settings, by app

    /// The switch that turns `app` on.
    public static func enabledKey(_ app: ChatApp) -> WritableKeyPath<ChatMonitorConfig, Bool> {
        switch app {
        case .beeper: return \.beeperEnabled
        case .courier: return \.courierEnabled
        }
    }

    public static func announceKey(_ app: ChatApp) -> WritableKeyPath<ChatMonitorConfig, BeeperAnnounce> {
        switch app {
        case .beeper: return \.beeperAnnounce
        case .courier: return \.courierAnnounce
        }
    }

    public static func mutedNetworksKey(_ app: ChatApp) -> WritableKeyPath<ChatMonitorConfig, [String]> {
        switch app {
        case .beeper: return \.beeperMutedNetworks
        case .courier: return \.courierMutedNetworks
        }
    }

    public static func addressKey(_ app: ChatApp) -> WritableKeyPath<ChatMonitorConfig, String> {
        switch app {
        case .beeper: return \.beeperAddress
        case .courier: return \.courierAddress
        }
    }

    public func isEnabled(_ app: ChatApp) -> Bool { self[keyPath: Self.enabledKey(app)] }
    public func announce(for app: ChatApp) -> BeeperAnnounce { self[keyPath: Self.announceKey(app)] }
    public func mutedNetworks(for app: ChatApp) -> [String] { self[keyPath: Self.mutedNetworksKey(app)] }
    public func address(for app: ChatApp) -> String { self[keyPath: Self.addressKey(app)] }

    /// The networks `app` reads although HomeSpeaker reads them itself:
    /// Courier's choice; Beeper, which can tell Slack workspaces apart,
    /// has none.
    public func readsAnyway(_ app: ChatApp) -> [String] {
        app == .courier ? courierReadAnyway : []
    }

    /// Reads one of Courier's networks although HomeSpeaker's own reader
    /// covers it (`isOn`), or leaves it to that reader again.
    public mutating func setReadAnyway(_ key: String, _ isOn: Bool) {
        if isOn {
            if !courierReadAnyway.contains(key) { courierReadAnyway.append(key) }
        } else {
            courierReadAnyway.removeAll { $0 == key }
        }
    }
}
