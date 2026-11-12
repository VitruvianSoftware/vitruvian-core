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
import Testing
@testable import HomeSpeakerCore

/// Verifies `SettingsCatalog` and the `HomeSpeakerCore` engine against every
/// shared JSON case file in `apps/desktop/home-speaker/testdata/`.
@Suite("Shared Rulebook Cases")
struct SharedRulebookCasesTests {

    // MARK: - Locating testdata/ under Bazel runfiles and SwiftPM

    private static func testdataDir() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let runfiles = env["RUNFILES_DIR"] ?? env["TEST_SRCDIR"] {
            let workspace = env["TEST_WORKSPACE"] ?? "_main"
            let bazel = URL(fileURLWithPath: runfiles)
                .appendingPathComponent(workspace)
                .appendingPathComponent("apps/desktop/home-speaker/testdata")
            if FileManager.default.fileExists(atPath: bazel.path) {
                return bazel
            }
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("testdata")
    }

    private static func loadJSON<T: Decodable>(_ filename: String, as type: T.Type = T.self) throws -> T {
        let url = testdataDir().appendingPathComponent(filename)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Exhaustiveness across testdata/

    @Test("Every JSON case file in testdata/ is accounted for and verified")
    func everyTestdataFileIsRead() throws {
        let dir = Self.testdataDir()
        let entries = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let jsonFiles = Set(entries.filter { $0.hasSuffix(".json") })
        let expectedFiles: Set<String> = [
            "choices.json",
            "limits.json",
            "visibility.json",
            "quiet_hours.json",
            "speakers.json",
            "outputs_label.json",
            "chat_monitor_status.json",
            "oauth_client_override.json",
            "controls.json",
            "state_v1.json",
        ]
        #expect(jsonFiles == expectedFiles)
        #expect(entries.contains("README.md"))
    }

    // MARK: - 1. Choice Lists (choices.json)

    private struct ChoicesSuite: Decodable {
        let suite: String
        let lists: [ChoiceListSpec]
        let gemini_voice_option_cases: [GeminiVoiceOptionCase]
        let local_voice_option_cases: [LocalVoiceOptionCase]
    }

    private struct LocalVoiceOptionCase: Decodable {
        struct SystemVoiceInput: Decodable {
            let id: String
            let name: String
            let language: String
            let quality: String
        }
        struct ExpectedChoice: Decodable, Equatable {
            let value: String
            let label: String
        }
        let name: String
        let local_voice: String?
        let system_voices: [SystemVoiceInput]
        let expected_choices: [ExpectedChoice]
    }

    private struct ChoiceListSpec: Decodable {
        let key: String
        let label: String
        let kind: String
        let default_value: String
        let choices: [ChoiceItemSpec]
    }

    private struct ChoiceItemSpec: Decodable {
        let value: String
        let label: String
        let max_characters: Int?
        let max_sentences: Int?
    }

    private struct GeminiVoiceOptionCase: Decodable {
        struct CustomVoiceInput: Decodable {
            let id: String
            let name: String
        }
        struct ExpectedChoice: Decodable, Equatable {
            let value: String
            let label: String
        }
        let name: String
        let gemini_voice: String?
        let custom_voices: [CustomVoiceInput]
        let expected_first: ExpectedChoice
        let expected_last: ExpectedChoice
        let expected_count: Int
    }

    @Test("Choice lists match engine enums and SettingsCatalog (choices.json)")
    func choiceListsMatchEngineAndCatalog() throws {
        let spec = try Self.loadJSON("choices.json", as: ChoicesSuite.self)
        #expect(spec.suite == "choices")

        let defaultConfig = SpeakerConfig()
        let catalog = SettingsCatalog(config: defaultConfig)

        for list in spec.lists {
            let entry = try #require(catalog.entry(forKey: list.key), "Missing catalog entry for \(list.key)")
            #expect(entry.label == list.label, "Label mismatch for \(list.key)")
            #expect(entry.kind.rawValue == list.kind, "Kind mismatch for \(list.key)")

            let expectedChoices = list.choices.map { SettingsCatalog.Choice(value: $0.value, label: $0.label) }
            #expect(entry.choices == expectedChoices, "Choices mismatch for \(list.key)")

            switch list.key {
            case "speech_length":
                #expect(defaultConfig.effectiveSpeechLength.rawValue == list.default_value)
                for (item, model) in zip(list.choices, SpeechLength.allCases) {
                    #expect(model.rawValue == item.value)
                    #expect(model.label == item.label)
                    #expect(model.maxCharacters == item.max_characters)
                    #expect(model.maxSentences == item.max_sentences)
                }
            case "announcement_style":
                #expect(defaultConfig.effectiveAnnouncementStyle.rawValue == list.default_value)
                #expect(AnnouncementStyle.allCases.map { SettingsCatalog.Choice(value: $0.rawValue, label: $0.label) } == expectedChoices)
            case "style_model":
                #expect(defaultConfig.effectiveStyleModel.rawValue == list.default_value)
                #expect(StyleModel.allCases.map { SettingsCatalog.Choice(value: $0.rawValue, label: $0.label) } == expectedChoices)
            case "local_engine":
                #expect(defaultConfig.effectiveLocalEngine.rawValue == list.default_value)
                #expect(LocalVoiceEngine.allCases.map { SettingsCatalog.Choice(value: $0.rawValue, label: $0.label) } == expectedChoices)
            case "gemini_voice":
                #expect(defaultConfig.effectiveGeminiVoice == list.default_value)
                #expect(GeminiVoice.allCases.map { SettingsCatalog.Choice(value: $0.rawValue, label: $0.label) } == expectedChoices)
            case "beeper_announce":
                #expect(defaultConfig.effectiveChatMonitor.beeperAnnounce.rawValue == list.default_value)
                #expect(ChatMonitorConfig.BeeperAnnounce.allCases.map { SettingsCatalog.Choice(value: $0.rawValue, label: $0.label) } == expectedChoices)
            case "courier_announce":
                #expect(defaultConfig.effectiveChatMonitor.courierAnnounce.rawValue == list.default_value)
                #expect(ChatMonitorConfig.BeeperAnnounce.allCases.map { SettingsCatalog.Choice(value: $0.rawValue, label: $0.label) } == expectedChoices)
            case "google_chat_source":
                #expect(defaultConfig.effectiveChatMonitor.googleChatSource.rawValue == list.default_value)
                #expect(ChatMonitorConfig.GoogleChatSource.allCases.map { SettingsCatalog.Choice(value: $0.rawValue, label: $0.label) } == expectedChoices)
            default:
                Issue.record("Unexpected choice list key in choices.json: \(list.key)")
            }
        }

        for tc in spec.gemini_voice_option_cases {
            var config = SpeakerConfig()
            config.geminiVoice = tc.gemini_voice
            config.customVoices = tc.custom_voices.map { CustomVoice(id: $0.id, name: $0.name) }
            let choices = SettingsCatalog(config: config).entry(.geminiVoice).choices
            #expect(choices.count == tc.expected_count, "Count mismatch in \(tc.name)")
            #expect(choices.first == SettingsCatalog.Choice(value: tc.expected_first.value, label: tc.expected_first.label), "First mismatch in \(tc.name)")
            #expect(choices.last == SettingsCatalog.Choice(value: tc.expected_last.value, label: tc.expected_last.label), "Last mismatch in \(tc.name)")
        }

        for tc in spec.local_voice_option_cases {
            var config = SpeakerConfig()
            config.localVoice = tc.local_voice
            let systemVoices = tc.system_voices.map { voice -> LocalVoice in
                let quality: LocalVoice.Quality = switch voice.quality {
                case "premium": .premium
                case "enhanced": .enhanced
                default: .standard
                }
                return LocalVoice(id: voice.id, name: voice.name, language: voice.language, quality: quality)
            }
            let expected = tc.expected_choices.map { SettingsCatalog.Choice(value: $0.value, label: $0.label) }
            let functionChoices = SettingsCatalog.localVoiceChoices(config: config, systemVoices: systemVoices)
            let catalogChoices = SettingsCatalog(config: config, systemVoices: systemVoices).entry(.localVoice).choices
            #expect(functionChoices == expected, "localVoiceChoices mismatch in \(tc.name)")
            #expect(catalogChoices == functionChoices, "SettingsCatalog.entry(.localVoice).choices mismatch in \(tc.name)")
        }
    }

    // MARK: - 2. Numeric Limits & Steps (limits.json)

    private struct LimitsSuite: Decodable {
        let suite: String
        let settings: [LimitSettingSpec]
    }

    private struct LimitSettingSpec: Decodable {
        struct ClampingCase: Decodable {
            let input: Int
            let expected: Int
        }
        let key: String
        let label: String
        let kind: String
        let min: Int
        let max: Int
        let step: Int
        let default_value: Int
        let discrete_steps: [Int]?
        let clamping_cases: [ClampingCase]
    }

    @Test("Numeric limits, steps, and clamping match engine and SettingsCatalog (limits.json)")
    func numericLimitsMatchEngineAndCatalog() throws {
        let spec = try Self.loadJSON("limits.json", as: LimitsSuite.self)
        #expect(spec.suite == "limits")

        let catalog = SettingsCatalog(config: SpeakerConfig())

        for item in spec.settings {
            let entry = try #require(catalog.entry(forKey: item.key), "Missing catalog entry for \(item.key)")
            #expect(entry.label == item.label, "Label mismatch for \(item.key)")
            #expect(entry.kind.rawValue == item.kind, "Kind mismatch for \(item.key)")
            let limits = try #require(entry.limits, "Missing limits for \(item.key)")
            #expect(limits == SettingsCatalog.Limits(min: item.min, max: item.max, step: item.step, defaultValue: item.default_value))

            switch item.key {
            case "speaker_volume":
                #expect(SettingsCatalog.volumeSteps == item.discrete_steps)
                for clamp in item.clamping_cases {
                    #expect(limits.clamp(clamp.input) == clamp.expected)
                }
            case "announce_volume":
                #expect(SpeakerConfig().effectiveAnnounceVolume == item.default_value)
                for clamp in item.clamping_cases {
                    var c = SpeakerConfig()
                    c.effectiveAnnounceVolume = clamp.input
                    #expect(c.effectiveAnnounceVolume == clamp.expected)
                }
            case "pause_media_extra_seconds":
                #expect(Int(SpeakerConfig().effectivePauseMediaExtraSeconds) == item.default_value)
                for clamp in item.clamping_cases {
                    var c = SpeakerConfig()
                    c.effectivePauseMediaExtraSeconds = Double(clamp.input)
                    #expect(Int(c.effectivePauseMediaExtraSeconds) == clamp.expected)
                }
            case "poll_interval_seconds":
                #expect(ChatMonitorConfig().pollIntervalSeconds == item.default_value)
                for clamp in item.clamping_cases {
                    let chat = ChatMonitorConfig(pollIntervalSeconds: clamp.input)
                    #expect(chat.clampedPollInterval == clamp.expected)
                }
            default:
                Issue.record("Unexpected numeric setting key in limits.json: \(item.key)")
            }
        }
    }

    // MARK: - 3. Visibility Rules (visibility.json)

    private struct VisibilitySuite: Decodable {
        let suite: String
        let cases: [VisibilityCase]
    }

    private struct VisibilityCase: Decodable {
        struct InputConfig: Decodable {
            let enabled: Bool
            let speak_home: Bool
            let home_cast_voice: Bool
            let speak_local: Bool
            let speak_phone: Bool
            let local_engine: String
            let announcement_style: String
            let style_model: String
            let announce_volume_enabled: Bool
            let pause_media: Bool
            let quiet_hours_enabled: Bool
            let announce_claude_code: Bool
            let announce_antigravity: Bool
            let announce_opencode: Bool
            let has_default_speaker: Bool
            let google_chat_enabled: Bool
            let google_chat_source: String
            let beeper_enabled: Bool
            let courier_enabled: Bool
        }
        struct ExpectedVisibility: Decodable {
            let shows_home_controls: Bool
            let shows_home_cast_voice: Bool
            let shows_voice_engine: Bool
            let uses_voice_engine: Bool
            let gemini_speaks: Bool
            let shows_gemini_voice: Bool
            let shows_announcement_style: Bool
            let shows_style_gemini_key: Bool
            let local_voice_label: String
            let shown_keys: [String]
            let hidden_keys: [String]
        }
        let name: String
        let config: InputConfig
        let expected: ExpectedVisibility
    }

    @Test("Visibility rules match SpeakerConfig and SettingsCatalog (visibility.json)")
    func visibilityRulesMatchEngineAndCatalog() throws {
        let spec = try Self.loadJSON("visibility.json", as: VisibilitySuite.self)
        #expect(spec.suite == "visibility")

        for tc in spec.cases {
            var c = SpeakerConfig(
                enabled: tc.config.enabled,
                defaultTarget: tc.config.has_default_speaker ? "kitchen" : "",
                structureId: tc.config.has_default_speaker ? "s1" : "",
                targets: tc.config.has_default_speaker
                    ? ["kitchen": SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen")]
                    : [:]
            )
            c.speakHome = tc.config.speak_home
            c.homeCastVoice = tc.config.home_cast_voice
            c.speakLocal = tc.config.speak_local
            c.speakPhone = tc.config.speak_phone
            c.localEngine = LocalVoiceEngine(rawValue: tc.config.local_engine)
            c.announcementStyle = AnnouncementStyle(rawValue: tc.config.announcement_style)
            c.styleModel = StyleModel(rawValue: tc.config.style_model)
            c.announceVolumeEnabled = tc.config.announce_volume_enabled
            c.pauseMedia = tc.config.pause_media
            c.quietHoursEnabled = tc.config.quiet_hours_enabled
            c.announceClaudeCode = tc.config.announce_claude_code
            c.announceAntigravity = tc.config.announce_antigravity
            c.announceOpenCode = tc.config.announce_opencode
            c.chatMonitor = ChatMonitorConfig(
                googleChatEnabled: tc.config.google_chat_enabled,
                googleChatSource: ChatMonitorConfig.GoogleChatSource(rawValue: tc.config.google_chat_source) ?? .auto,
                beeperEnabled: tc.config.beeper_enabled,
                courierEnabled: tc.config.courier_enabled
            )

            #expect(c.showsHomeControls == tc.expected.shows_home_controls, "\(tc.name): showsHomeControls")
            #expect(c.showsHomeCastVoice == tc.expected.shows_home_cast_voice, "\(tc.name): showsHomeCastVoice")
            #expect(c.showsVoiceEngine == tc.expected.shows_voice_engine, "\(tc.name): showsVoiceEngine")
            #expect(c.usesVoiceEngine == tc.expected.uses_voice_engine, "\(tc.name): usesVoiceEngine")
            #expect(c.geminiSpeaks == tc.expected.gemini_speaks, "\(tc.name): geminiSpeaks")
            #expect(c.showsGeminiVoice == tc.expected.shows_gemini_voice, "\(tc.name): showsGeminiVoice")
            #expect(c.showsAnnouncementStyle == tc.expected.shows_announcement_style, "\(tc.name): showsAnnouncementStyle")
            #expect(c.showsStyleGeminiKey == tc.expected.shows_style_gemini_key, "\(tc.name): showsStyleGeminiKey")

            let catalog = SettingsCatalog(config: c)
            #expect(catalog.entry(.localVoice).label == tc.expected.local_voice_label, "\(tc.name): localVoice label")

            let actualShown = catalog.entries.filter(\.shown).map(\.key)
            let actualHidden = catalog.entries.filter { !$0.shown }.map(\.key)
            #expect(actualShown == tc.expected.shown_keys, "\(tc.name): shown_keys")
            #expect(actualHidden == tc.expected.hidden_keys, "\(tc.name): hidden_keys")
        }
    }

    // MARK: - 4. Quiet Hours (quiet_hours.json)

    private struct QuietHoursSuite: Decodable {
        struct ParsingCase: Decodable {
            let input: String
            let minutes: Int?
            let normalized: String?
        }
        struct WindowCase: Decodable {
            let name: String
            let enabled: Bool
            let start: String
            let end: String
            let time: String
            let expected: Bool
        }
        struct ChoiceCase: Decodable {
            let name: String
            let saved: String
            let expected_count: Int
            let expected_first: String
            let expected_second: String
            let expected_last: String
        }
        let suite: String
        let default_start: String
        let default_end: String
        let half_hours: [String]
        let parsing_cases: [ParsingCase]
        let window_cases: [WindowCase]
        let choice_cases: [ChoiceCase]
    }

    @Test("Quiet hours parsing, overnight window, and off-grid-first choices match engine (quiet_hours.json)")
    func quietHoursMatchEngineAndCatalog() throws {
        let spec = try Self.loadJSON("quiet_hours.json", as: QuietHoursSuite.self)
        #expect(spec.suite == "quiet_hours")
        #expect(SettingsCatalog.defaultQuietHoursStart == spec.default_start)
        #expect(SettingsCatalog.defaultQuietHoursEnd == spec.default_end)
        #expect(SettingsCatalog.halfHours == spec.half_hours)

        for pc in spec.parsing_cases {
            #expect(SpeakerConfig.minutesSinceMidnight(pc.input) == pc.minutes, "minutesSinceMidnight(\(pc.input))")
            #expect(SettingsCatalog.normalizedQuietHour(pc.input) == pc.normalized, "normalizedQuietHour(\(pc.input))")
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        for wc in spec.window_cases {
            let minutes = try #require(SpeakerConfig.minutesSinceMidnight(wc.time))
            let date = try #require(
                calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: minutes / 60, minute: minutes % 60))
            )
            let config = SpeakerConfig(
                enabled: true,
                defaultTarget: "",
                structureId: "",
                targets: [:],
                quietHoursEnabled: wc.enabled,
                quietHoursStart: wc.start,
                quietHoursEnd: wc.end
            )
            #expect(config.isInQuietHours(at: date, calendar: calendar) == wc.expected, "\(wc.name)")
        }

        for cc in spec.choice_cases {
            let values = SettingsCatalog.quietHoursTimeValues(keeping: cc.saved)
            #expect(values.count == cc.expected_count, "\(cc.name): count")
            #expect(values.first == cc.expected_first, "\(cc.name): first")
            #expect(values.dropFirst().first == cc.expected_second, "\(cc.name): second")
            #expect(values.last == cc.expected_last, "\(cc.name): last")
        }
    }

    // MARK: - 5. Speaker Order, Display Line, and Removing Default (speakers.json)

    private struct SpeakersSuite: Decodable {
        struct DisplayLineCase: Decodable {
            let name: String
            let device: SpeakerDevice
            let expected: String
        }
        struct UniqueTargetsCase: Decodable {
            struct ExpectedSpeaker: Decodable, Equatable {
                let key: String
                let id: String
                let name: String
                let display_line: String
            }
            let name: String
            let default_target: String
            let targets: [String: SpeakerDevice]
            let expected_order: [ExpectedSpeaker]
        }
        struct RemoveTargetCase: Decodable {
            let name: String
            let default_target: String
            let remove_key: String
            let targets: [String: SpeakerDevice]
            let expected_default_target: String
            let expected_remaining_keys: [String]
        }
        let suite: String
        let display_line_cases: [DisplayLineCase]
        let unique_targets_cases: [UniqueTargetsCase]
        let remove_target_cases: [RemoveTargetCase]
    }

    @Test("Speaker displayLine, uniqueTargets ordering, and removeTarget match engine (speakers.json)")
    func speakersMatchEngineAndCatalog() throws {
        let spec = try Self.loadJSON("speakers.json", as: SpeakersSuite.self)
        #expect(spec.suite == "speakers")

        for dc in spec.display_line_cases {
            #expect(dc.device.displayLine == dc.expected, "\(dc.name)")
        }

        for uc in spec.unique_targets_cases {
            let config = SpeakerConfig(
                enabled: true,
                defaultTarget: uc.default_target,
                structureId: "s1",
                targets: uc.targets
            )
            let actual = config.uniqueTargets().map {
                SpeakersSuite.UniqueTargetsCase.ExpectedSpeaker(
                    key: $0.key,
                    id: $0.device.id,
                    name: $0.device.name,
                    display_line: $0.device.displayLine
                )
            }
            #expect(actual == uc.expected_order, "\(uc.name)")

            let catalogChoices = SettingsCatalog(config: config).entry(.defaultTarget).choices
            let expectedChoices = uc.expected_order.map { SettingsCatalog.Choice(value: $0.key, label: $0.display_line) }
            #expect(catalogChoices == expectedChoices, "\(uc.name): catalog default_target choices")
        }

        for rc in spec.remove_target_cases {
            var config = SpeakerConfig(
                enabled: true,
                defaultTarget: rc.default_target,
                structureId: "s1",
                targets: rc.targets
            )
            config.removeTarget(rc.remove_key)
            #expect(config.defaultTarget == rc.expected_default_target, "\(rc.name): defaultTarget")
            #expect(config.uniqueTargets().map(\.key) == rc.expected_remaining_keys, "\(rc.name): remaining keys")
        }
    }

    // MARK: - 6. Active Outputs Summary & Phone Substitution (outputs_label.json)

    private struct OutputsLabelSuite: Decodable {
        struct PhoneSubstitution: Decodable {
            let mac: String
            let phone: String
        }
        struct OutputCase: Decodable {
            let name: String
            let speak_home: Bool
            let default_speaker_name: String?
            let speak_local: Bool
            let speak_phone: Bool
            let expected_mac: String
            let expected_phone: String
        }
        let suite: String
        let phone_substitution: PhoneSubstitution
        let cases: [OutputCase]
    }

    @Test("Active outputs summary and phone substitution match engine (outputs_label.json)")
    func activeOutputsLabelMatchesEngine() throws {
        let spec = try Self.loadJSON("outputs_label.json", as: OutputsLabelSuite.self)
        #expect(spec.suite == "outputs_label")
        #expect(SettingsCatalog.macPhoneOutputLabel == spec.phone_substitution.mac)
        #expect(SettingsCatalog.remotePhoneOutputLabel == spec.phone_substitution.phone)

        for tc in spec.cases {
            var targets: [String: SpeakerDevice] = [:]
            var defaultTarget = ""
            if let speakerName = tc.default_speaker_name {
                defaultTarget = "speaker"
                targets["speaker"] = SpeakerDevice(id: "d1", type: "SpeakerDevice", name: speakerName)
            }
            var config = SpeakerConfig(
                enabled: true,
                defaultTarget: defaultTarget,
                structureId: "s1",
                targets: targets
            )
            config.speakHome = tc.speak_home
            config.speakLocal = tc.speak_local
            config.speakPhone = tc.speak_phone

            #expect(config.activeOutputsLabel == tc.expected_mac, "\(tc.name): Mac activeOutputsLabel")
            #expect(SettingsCatalog.activeOutputsLabel(for: config, onPhone: false) == tc.expected_mac, "\(tc.name): catalog Mac")
            #expect(SettingsCatalog.activeOutputsLabel(for: config, onPhone: true) == tc.expected_phone, "\(tc.name): catalog Phone")
        }
    }

    // MARK: - 7. Chat Monitor Status Believed While Owner Runs (chat_monitor_status.json)

    private struct ChatMonitorStatusSuite: Decodable {
        struct StatusFields: Decodable, Equatable {
            let is_running: Bool
            let last_error: String?
            let slack_identity: String?
            let active_google_chat_backend: String?
            let pid: Int32
        }
        struct StatusCase: Decodable {
            let name: String
            let owner_running: Bool
            let input: StatusFields
            let expected: StatusFields
        }
        let suite: String
        let cases: [StatusCase]
    }

    @Test("ChatMonitorStatus.believed(ownerRunning:) clears running and error when owner is gone (chat_monitor_status.json)")
    func chatMonitorStatusBeliefMatchesEngine() throws {
        let spec = try Self.loadJSON("chat_monitor_status.json", as: ChatMonitorStatusSuite.self)
        #expect(spec.suite == "chat_monitor_status")

        for tc in spec.cases {
            let status = ChatMonitorStatus(
                isRunning: tc.input.is_running,
                lastPollDate: Date(timeIntervalSince1970: 1_700_000_000),
                lastError: tc.input.last_error,
                slackIdentity: tc.input.slack_identity,
                activeGoogleChatBackend: tc.input.active_google_chat_backend,
                pid: tc.input.pid
            )
            let believed = status.believed(ownerRunning: tc.owner_running)
            let actual = ChatMonitorStatusSuite.StatusFields(
                is_running: believed.isRunning,
                last_error: believed.lastError,
                slack_identity: believed.slackIdentity,
                active_google_chat_backend: believed.activeGoogleChatBackend,
                pid: believed.pid
            )
            #expect(actual == tc.expected, "\(tc.name)")
        }
    }

    // MARK: - 8. Google Sign-In Client Override Rule (oauth_client_override.json)

    private struct OAuthClientOverrideSuite: Decodable {
        struct OverrideCase: Decodable {
            let name: String
            let initial_id: String?
            let initial_secret: String?
            let input_id: String
            let input_secret: String?
            let expected_id: String?
            let expected_secret: String?
        }
        let suite: String
        let cases: [OverrideCase]
    }

    @Test("Google sign-in client override rule matches shared cases (oauth_client_override.json)")
    func oauthClientOverrideMatchesRule() throws {
        let spec = try Self.loadJSON("oauth_client_override.json", as: OAuthClientOverrideSuite.self)
        #expect(spec.suite == "oauth_client_override")

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("homespeaker-oauth-rule-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        for tc in spec.cases {
            let store = SecretStore(fileURL: scratch.appendingPathComponent("\(tc.name)-secrets.json"))
            try store.save(
                Secrets(
                    oauthClientIdOverride: tc.initial_id,
                    oauthClientSecretOverride: tc.initial_secret
                )
            )
            try SettingsActions.saveOAuthClientOverride(
                id: tc.input_id,
                secret: tc.input_secret,
                in: store
            )
            let secrets = store.load()

            #expect(secrets.oauthClientIdOverride == tc.expected_id, "\(tc.name): client ID")
            #expect(secrets.oauthClientSecretOverride == tc.expected_secret, "\(tc.name): client secret")
        }
    }
}
