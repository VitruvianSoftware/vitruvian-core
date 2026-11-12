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
@testable import VitruvianSpeakerCore

@Suite("SettingsActions Unified Engine Actions")
struct SettingsActionsTests {

    private struct ScratchRig {
        let root: URL
        let configFile: SpeakerConfigFile
        let secretStore: SecretStore
        let doorFile: DoorFile
        let home: URL
        let appProfile: VitruvianSpeakerProfile
        let extensionProfile: VitruvianSpeakerProfile
        let appProgram: URL
        let extensionProgram: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("vitruvian-speaker-settings-actions-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

            let settingsURL = root.appendingPathComponent("gemini/speaker_broadcast.json")
            let historyURL = root.appendingPathComponent("gemini/speaker_history.json")
            let secretsURL = root.appendingPathComponent("AppSupport/Vitruvian Speaker/secrets.json")
            let doorURL = root.appendingPathComponent("gemini/\(DoorFile.fileName)")
            home = root.appendingPathComponent("home", isDirectory: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

            configFile = SpeakerConfigFile(url: settingsURL)
            secretStore = SecretStore(fileURL: secretsURL)
            doorFile = DoorFile(url: doorURL)

            appProgram = root.appendingPathComponent("Applications/Vitruvian Speaker.app/Contents/MacOS/VitruvianSpeaker")
            try FileManager.default.createDirectory(
                at: appProgram.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: appProgram)

            let vitruvian = root.appendingPathComponent("Vitruvian", isDirectory: true)
            extensionProgram = vitruvian.appendingPathComponent("Tools/dev.vitruvian.speaker/bin/tool")
            let extensionData = vitruvian.appendingPathComponent("ToolData/dev.vitruvian.speaker", isDirectory: true)
            let extensionTool = vitruvian.appendingPathComponent("Tools/dev.vitruvian.speaker", isDirectory: true)
            try FileManager.default.createDirectory(
                at: extensionProgram.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(at: extensionData, withIntermediateDirectories: true)
            try Data().write(to: extensionProgram)

            appProfile = VitruvianSpeakerProfile(
                door: .app,
                settingsURL: settingsURL,
                historyURL: historyURL,
                secretsURL: secretsURL,
                messagePrefix: "test.\(UUID().uuidString).vitruvian-speaker",
                liveLockURL: nil,
                toolFolder: nil
            )
            extensionProfile = .extension(dataFolder: extensionData, toolFolder: extensionTool)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }

        func readConfig() -> SpeakerConfig {
            if case .loaded(let cfg) = configFile.read() { return cfg }
            return SpeakerConfig()
        }
    }

    // MARK: - 1. set(key:value:) Validations, Refusals & Clamping

    @Test("set(key:value:) refuses unknown keys, wrong kinds, invalid choices, malformed times, non-local addresses, and Courier without token")
    func setRefusesInvalidInputs() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }

        let initial = SpeakerConfig(
            defaultTarget: "office",
            structureId: "struct-1",
            targets: ["office": SpeakerDevice(id: "dev-1", type: "SPEAKER", name: "Office", room: "Office")]
        )
        try rig.configFile.write(initial)

        // Unknown key
        #expect(throws: SettingsActions.Refusal.unknownKey("not_a_setting")) {
            try SettingsActions.set(key: "not_a_setting", value: .bool(true), in: rig.configFile)
        }

        // Wrong kind for each catalog kind
        #expect(throws: SettingsActions.Refusal.wrongKind(key: "enabled", expected: .toggle, got: .string("yes"))) {
            try SettingsActions.set(key: "enabled", value: .string("yes"), in: rig.configFile)
        }
        #expect(throws: SettingsActions.Refusal.wrongKind(key: "speech_length", expected: .choice, got: .bool(true))) {
            try SettingsActions.set(key: "speech_length", value: .bool(true), in: rig.configFile)
        }
        #expect(throws: SettingsActions.Refusal.wrongKind(key: "announce_volume", expected: .number, got: .string("60"))) {
            try SettingsActions.set(key: "announce_volume", value: .string("60"), in: rig.configFile)
        }
        #expect(throws: SettingsActions.Refusal.wrongKind(key: "custom_style_prompt", expected: .text, got: .int(42))) {
            try SettingsActions.set(key: "custom_style_prompt", value: .int(42), in: rig.configFile)
        }
        #expect(throws: SettingsActions.Refusal.wrongKind(key: "quiet_hours_start", expected: .time, got: .int(22))) {
            try SettingsActions.set(key: "quiet_hours_start", value: .int(22), in: rig.configFile)
        }

        // Value not in choices
        #expect(
            throws: SettingsActions.Refusal.invalidChoice(
                key: "speech_length",
                value: "essay",
                allowed: ["headline", "summary", "full"]
            )
        ) {
            try SettingsActions.set(key: "speech_length", value: .string("essay"), in: rig.configFile)
        }
        #expect(
            throws: SettingsActions.Refusal.invalidChoice(
                key: "default_target",
                value: "bedroom",
                allowed: ["office"]
            )
        ) {
            try SettingsActions.set(key: "default_target", value: .string("bedroom"), in: rig.configFile)
        }

        // Malformed quiet hour
        #expect(throws: SettingsActions.Refusal.invalidTime(key: "quiet_hours_start", value: "25:99")) {
            try SettingsActions.set(key: "quiet_hours_start", value: .string("25:99"), in: rig.configFile)
        }

        // Non-local Beeper / Courier address
        do {
            _ = try SettingsActions.set(
                key: "beeper_address",
                value: .string("https://example.com:23373"),
                in: rig.configFile
            )
            Issue.record("Expected beeper_address refusal for non-local URL")
        } catch let error as SettingsActions.Refusal {
            if case .invalidAddress(let key, let reason) = error {
                #expect(key == "beeper_address")
                #expect(reason.contains("http://"))
            } else {
                Issue.record("Unexpected refusal case: \(error)")
            }
        }

        // Enabling Courier without a saved Courier token
        #expect(
            throws: SettingsActions.Refusal.missingToken(
                key: "courier_enabled",
                reason: "Save a Courier token first"
            )
        ) {
            try SettingsActions.set(
                key: "courier_enabled",
                value: .bool(true),
                in: rig.configFile,
                secrets: rig.secretStore
            )
        }
    }

    @Test("set(key:value:) applies valid values across all kinds and clamps numbers with warnings")
    func setAppliesValuesAndClampsNumbers() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }

        var initial = SpeakerConfig(
            defaultTarget: "office",
            structureId: "struct-1",
            targets: [
                "office": SpeakerDevice(id: "dev-1", type: "SPEAKER", name: "Office", room: "Office"),
                "kitchen": SpeakerDevice(id: "dev-2", type: "SPEAKER", name: "Kitchen", room: "Kitchen"),
            ]
        )
        initial.customVoices = [CustomVoice(id: "voice_custom_1", name: "Narrator")]
        try rig.configFile.write(initial)
        try rig.secretStore.save(Secrets(courierToken: "courier-tok-\(UUID().uuidString)")) // gitleaks:allow

        let voices = [LocalVoice(id: "com.apple.voice.compact.en-US.Samantha", name: "Samantha", language: "en-US", quality: .standard)]

        // Toggle
        let toggleRes = try SettingsActions.set(key: .pauseMedia, value: .bool(true), in: rig.configFile)
        #expect(toggleRes.appliedValue == .bool(true))
        #expect(!toggleRes.clamped)
        #expect(toggleRes.warning == nil)
        #expect(toggleRes.config.effectivePauseMedia == true)

        // Courier toggle succeeds when token is present
        let courierRes = try SettingsActions.set(
            key: .courierEnabled,
            value: .bool(true),
            in: rig.configFile,
            secrets: rig.secretStore
        )
        #expect(courierRes.config.effectiveChatMonitor.courierEnabled == true)

        // Choices (including cloned Gemini voice and local voice)
        _ = try SettingsActions.set(key: .speechLength, value: .string("full"), in: rig.configFile)
        _ = try SettingsActions.set(key: .announcementStyle, value: .string("custom"), in: rig.configFile)
        _ = try SettingsActions.set(key: .styleModel, value: .string("gemini"), in: rig.configFile)
        _ = try SettingsActions.set(key: .defaultTarget, value: .string("kitchen"), in: rig.configFile)
        _ = try SettingsActions.set(key: .localEngine, value: .string("gemini"), in: rig.configFile)
        _ = try SettingsActions.set(key: .geminiVoice, value: .string("voice_custom_1"), in: rig.configFile)
        _ = try SettingsActions.set(
            key: .localVoice,
            value: .string("com.apple.voice.compact.en-US.Samantha"),
            in: rig.configFile,
            systemVoices: voices
        )
        _ = try SettingsActions.set(key: .googleChatSource, value: .string("gws"), in: rig.configFile)
        _ = try SettingsActions.set(key: .beeperAnnounce, value: .string("all"), in: rig.configFile)
        _ = try SettingsActions.set(key: .courierAnnounce, value: .string("all"), in: rig.configFile)

        // Text & Time
        _ = try SettingsActions.set(key: .customStylePrompt, value: .string("Keep it brief."), in: rig.configFile)
        _ = try SettingsActions.set(key: .gwsAccount, value: .string(" user@example.com "), in: rig.configFile)
        _ = try SettingsActions.set(key: .beeperAddress, value: .string("http://127.0.0.1:23373"), in: rig.configFile)
        _ = try SettingsActions.set(key: .courierAddress, value: .string("http://localhost:23374"), in: rig.configFile)
        _ = try SettingsActions.set(key: .quietHoursStart, value: .string("21:45"), in: rig.configFile)
        _ = try SettingsActions.set(key: .quietHoursEnd, value: .string("06:30"), in: rig.configFile)

        // Numbers: in-range and clamped (low & high)
        let volHigh = try SettingsActions.set(key: .announceVolume, value: .int(150), in: rig.configFile)
        #expect(volHigh.appliedValue == .int(100))
        #expect(volHigh.clamped == true)
        #expect(volHigh.warning?.contains("clamped from 150 to 100") == true)
        #expect(volHigh.config.effectiveAnnounceVolume == 100)

        let pauseLow = try SettingsActions.set(key: .pauseMediaExtraSeconds, value: .int(-5), in: rig.configFile)
        #expect(pauseLow.appliedValue == .int(0))
        #expect(pauseLow.clamped == true)
        #expect(pauseLow.warning?.contains("clamped from -5 to 0") == true)
        #expect(pauseLow.config.effectivePauseMediaExtraSeconds == 0)

        let pollHigh = try SettingsActions.set(key: .pollIntervalSeconds, value: .int(999), in: rig.configFile)
        #expect(pollHigh.appliedValue == .int(300))
        #expect(pollHigh.clamped == true)
        #expect(pollHigh.config.effectiveChatMonitor.pollIntervalSeconds == 300)

        let pollExact = try SettingsActions.set(key: .pollIntervalSeconds, value: .int(30), in: rig.configFile)
        #expect(pollExact.appliedValue == .int(30))
        #expect(pollExact.clamped == false)
        #expect(pollExact.warning == nil)

        guard case .loaded(let saved) = rig.configFile.read() else {
            Issue.record("Expected saved config to load")
            return
        }
        #expect(saved.effectiveSpeechLength == .full)
        #expect(saved.effectiveAnnouncementStyle == .custom)
        #expect(saved.effectiveStyleModel == .gemini)
        #expect(saved.defaultTarget == "kitchen")
        #expect(saved.effectiveLocalEngine == .gemini)
        #expect(saved.effectiveGeminiVoice == "voice_custom_1")
        #expect(saved.effectiveLocalVoice == "com.apple.voice.compact.en-US.Samantha")
        #expect(saved.effectiveCustomStylePrompt == "Keep it brief.")
        #expect(saved.effectiveChatMonitor.gwsAccount == "user@example.com")
        #expect(saved.effectiveChatMonitor.beeperAddress == "http://127.0.0.1:23373")
        #expect(saved.effectiveChatMonitor.courierAddress == "http://localhost:23374")
        #expect(saved.quietHoursStart == "21:45")
        #expect(saved.quietHoursEnd == "06:30")
    }

    // MARK: - 2. removeSpeaker

    @Test("removeSpeaker drops speaker under lock and picks next default by name")
    func removeSpeakerPicksNextDefaultByName() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }

        let config = SpeakerConfig(
            defaultTarget: "office",
            structureId: "struct-1",
            targets: [
                "office": SpeakerDevice(id: "dev-1", type: "SPEAKER", name: "Office", room: "Office"),
                "bedroom": SpeakerDevice(id: "dev-2", type: "SPEAKER", name: "Bedroom", room: "Bedroom"),
                "kitchen": SpeakerDevice(id: "dev-3", type: "SPEAKER", name: "Kitchen", room: "Kitchen"),
            ]
        )
        try rig.configFile.write(config)

        let res1 = try SettingsActions.removeSpeaker("office", in: rig.configFile)
        #expect(res1.wasPresent == true)
        #expect(res1.defaultTarget == "bedroom")
        #expect(res1.config.targets["office"] == nil)

        // Removing a non-default speaker keeps the current default
        let res2 = try SettingsActions.removeSpeaker("kitchen", in: rig.configFile)
        #expect(res2.wasPresent == true)
        #expect(res2.defaultTarget == "bedroom")

        // Removing the last speaker clears defaultTarget
        let res3 = try SettingsActions.removeSpeaker("bedroom", in: rig.configFile)
        #expect(res3.wasPresent == true)
        #expect(res3.defaultTarget == "")
        #expect(res3.config.targets.isEmpty)
    }

    // MARK: - 4. clearChatToken

    @Test("clearChatToken removes token and clearing Courier token also switches courierEnabled off")
    func clearChatTokenSwitchesCourierOff() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }

        try rig.secretStore.save(
            Secrets(
                slackToken: "xoxp-test-\(UUID().uuidString)", // gitleaks:allow
                beeperToken: "beeper-test-\(UUID().uuidString)", // gitleaks:allow
                courierToken: "courier-test-\(UUID().uuidString)" // gitleaks:allow
            )
        )
        var initial = SpeakerConfig()
        initial.chatMonitor = ChatMonitorConfig(
            slackEnabled: true,
            beeperEnabled: true,
            courierEnabled: true
        )
        try rig.configFile.write(initial)

        let slackRes = try SettingsActions.clearChatToken(.slack, in: rig.secretStore, configFile: rig.configFile)
        #expect(!slackRes.courierSwitchedOff)
        #expect(rig.secretStore.load().slackToken == nil)

        let beeperRes = try SettingsActions.clearChatToken(.beeper, in: rig.secretStore, configFile: rig.configFile)
        #expect(!beeperRes.courierSwitchedOff)
        #expect(rig.secretStore.load().beeperToken == nil)

        let courierRes = try SettingsActions.clearChatToken(.courier, in: rig.secretStore, configFile: rig.configFile)
        #expect(courierRes.courierSwitchedOff == true)
        #expect(rig.secretStore.load().courierToken == nil)

        guard case .loaded(let updated) = rig.configFile.read() else {
            Issue.record("Expected config file to load")
            return
        }
        #expect(updated.effectiveChatMonitor.courierEnabled == false)
        #expect(updated.effectiveChatMonitor.slackEnabled == true)
        #expect(updated.effectiveChatMonitor.beeperEnabled == true)
    }

    // MARK: - 5. Switch to the App or the Extension (Recording Fake)

    @Test("Unified switch path to extension and to app executes exact steps in order through RecordingDoorSwitchSeam without touching real processes")
    func switchPathWithRecordingFake() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }

        // Seed app settings, secrets, and a Claude Code hook pointing at the app
        try rig.configFile.write(SpeakerConfig(structureName: "Alpine Cabin"))
        try rig.secretStore.save(Secrets(slackToken: "xoxp-switch-\(UUID().uuidString)")) // gitleaks:allow
        try rig.doorFile.update {
            $0.installedExtension = DoorRecord.ExtensionEntry(
                program: rig.extensionProgram.path,
                dataFolder: rig.extensionProfile.settingsURL.deletingLastPathComponent().path,
                version: "1.19.0",
                door: DoorRecord.ExtensionEntry.runsAlone
            )
        }
        let appIntegration = AgentIntegration(home: rig.home, executablePath: rig.appProgram.path, bootout: { _ in })
        try appIntegration.installHook(for: .claudeCode)

        // 1. Switch from app to extension (with copy + post-switch offers)
        let appSeam = SettingsActions.RecordingDoorSwitchSeam(
            me: .app,
            chosenBy: "Vitruvian Speaker app 1.19.0",
            doorFile: rig.doorFile,
            home: rig.home,
            appProfile: rig.appProfile,
            extensionProfile: rig.extensionProfile,
            appProgram: rig.appProgram.path,
            extensionProgram: rig.extensionProgram.path
        )

        let compareToExt = try #require(
            try SettingsActions.beginSwitch(from: .app, into: .extension, purpose: .choose, seam: appSeam)
        )
        appSeam.resetSteps()

        let extOutcome = SettingsActions.finishSwitch(compare: compareToExt, copy: true, seam: appSeam)
        guard case .extensionChosen(var offers, let extReport) = extOutcome else {
            Issue.record("Expected .extensionChosen outcome, got \(extOutcome)")
            return
        }
        #expect(
            appSeam.steps == [
                "readDoor",
                "copy(app->extension)",
                "credentialsChanged(extension)",
                "writeChoice(extension)",
                "repointHooks(extension)",
                "refreshRole",
            ]
        )
        #expect(extReport.contains("Settings: copied from the app."))
        #expect(rig.doorFile.read()?.chosen == .extension)
        #expect(rig.doorFile.read()?.chosenBy == "Vitruvian Speaker app 1.19.0")
        #expect(appIntegration.status(of: .claudeCode).hookProgram == rig.extensionProgram.path)

        appSeam.resetSteps()
        offers.loginItem = true
        offers.trash = true
        let offersResult = SettingsActions.applySwitchOffers(offers, seam: appSeam)
        #expect(!offersResult.failed)
        #expect(offersResult.report == [DoorWords.loginItemOff, DoorWords.inTheTrash])
        #expect(appSeam.steps == ["turnOffLoginItem", "moveToTrash", "quitSelf"])

        // 2. Switch from extension to app when app is not running (opens app + enables login item)
        let extSeam = SettingsActions.RecordingDoorSwitchSeam(
            me: .extension,
            chosenBy: "Vitruvian Speaker extension 1.19.0",
            doorFile: rig.doorFile,
            home: rig.home,
            appProfile: rig.appProfile,
            extensionProfile: rig.extensionProfile,
            appProgram: rig.appProgram.path,
            extensionProgram: rig.extensionProgram.path,
            otherRunning: false
        )

        let compareToApp = try #require(
            try SettingsActions.beginSwitch(from: .extension, into: .app, purpose: .choose, seam: extSeam)
        )
        extSeam.resetSteps()

        let appOutcome = SettingsActions.finishSwitch(compare: compareToApp, copy: false, seam: extSeam)
        guard case .appChosen(let appReport) = appOutcome else {
            Issue.record("Expected .appChosen outcome, got \(appOutcome)")
            return
        }
        #expect(
            extSeam.steps == [
                "readDoor",
                "writeChoice(app)",
                "repointHooks(app)",
                "openOther",
                "enableLoginItem",
                "refreshRole",
            ]
        )
        #expect(appReport == [DoorWords.loginItemOn])
        #expect(rig.doorFile.read()?.chosen == .app)
        #expect(appIntegration.status(of: .claudeCode).hookProgram == rig.appProgram.path)

        // 3. Switch from extension to extension (asks running app to quit via quitOther)
        let extChooseSelfSeam = SettingsActions.RecordingDoorSwitchSeam(
            me: .extension,
            chosenBy: "Vitruvian Speaker extension 1.19.0",
            doorFile: rig.doorFile,
            home: rig.home,
            appProfile: rig.appProfile,
            extensionProfile: rig.extensionProfile,
            appProgram: rig.appProgram.path,
            extensionProgram: rig.extensionProgram.path,
            otherRunning: true
        )
        let compareExtSelf = try #require(
            try SettingsActions.beginSwitch(from: .app, into: .extension, purpose: .choose, seam: extChooseSelfSeam)
        )
        extChooseSelfSeam.resetSteps()

        let extSelfOutcome = SettingsActions.finishSwitch(compare: compareExtSelf, copy: false, seam: extChooseSelfSeam)
        guard case .extensionChosen = extSelfOutcome else {
            Issue.record("Expected .extensionChosen outcome")
            return
        }
        #expect(
            extChooseSelfSeam.steps == [
                "readDoor",
                "writeChoice(extension)",
                "repointHooks(extension)",
                "quitOther",
                "refreshRole",
            ]
        )
    }

    // MARK: - 6. resetSettings

    @Test("resetSettings restores defaults while preserving discovered home, speakers, custom voices, and unknown JSON keys")
    func resetSettingsPreservesDiscoveryAndForeignKeys() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }

        // Seed raw JSON with foreign keys + customized settings + discovered speakers
        let seedJSON: [String: Any] = [
            "enabled": false,
            "default_target": "office",
            "structure_id": "struct-99",
            "structure_name": "Lake House",
            "speech_length": "full",
            "pause_media": true,
            "announce_volume_enabled": true,
            "announce_volume": 85,
            "quiet_hours_enabled": true,
            "quiet_hours_start": "21:00",
            "quiet_hours_end": "08:00",
            "speak_local": true,
            "speak_phone": true,
            "custom_style_prompt": "Pirate voice",
            "foreign_top_level_key": "keep-me",
            "chat_monitor": [
                "slack_enabled": true,
                "foreign_chat_key": "keep-chat-meta",
            ],
            "custom_voices": [
                [
                    "id": "voice_custom_1",
                    "name": "Clone One",
                    "foreign_voice_field": "keep-voice-meta",
                ]
            ],
            "targets": [
                "office": [
                    "id": "dev-1",
                    "type": "SPEAKER",
                    "name": "Office Speaker",
                    "room": "Office",
                    "foreign_device_field": 123,
                ]
            ],
        ]
        let seedData = try JSONSerialization.data(withJSONObject: seedJSON, options: [.prettyPrinted, .sortedKeys])
        try LocalConfigFileSystem().write(seedData, to: rig.configFile.url)

        let reset = try SettingsActions.resetSettings(in: rig.configFile)
        #expect(reset.enabled == true)
        #expect(reset.defaultTarget == "office")
        #expect(reset.structureId == "struct-99")
        #expect(reset.structureName == "Lake House")
        #expect(reset.targets["office"]?.name == "Office Speaker")
        #expect(reset.effectiveCustomVoices == [CustomVoice(id: "voice_custom_1", name: "Clone One")])
        #expect(reset.effectiveSpeechLength == .summary)
        #expect(reset.effectivePauseMedia == false)
        #expect(reset.effectiveAnnounceVolumeEnabled == false)
        #expect(reset.quietHoursEnabled == false)
        #expect(reset.effectiveSpeakLocal == false)
        #expect(reset.effectiveSpeakPhone == false)
        #expect(reset.effectiveCustomStylePrompt == "")

        let rawAfter = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: rig.configFile.url)) as? [String: Any]
        )
        #expect(rawAfter["foreign_top_level_key"] as? String == "keep-me")
        let chatAfter = rawAfter["chat_monitor"] as? [String: Any]
        #expect(chatAfter?["foreign_chat_key"] as? String == "keep-chat-meta")
        let voicesAfter = rawAfter["custom_voices"] as? [[String: Any]]
        #expect(voicesAfter?.first?["foreign_voice_field"] as? String == "keep-voice-meta")
        let targetsAfter = rawAfter["targets"] as? [String: [String: Any]]
        #expect(targetsAfter?["office"]?["foreign_device_field"] as? Int == 123)
    }

    // MARK: - 7. Edge Cases: OAuth Client, Unclamped Numbers & ConfigManager Rollback

    @Test("saveOAuthClientOverride handles whitespace-only ID and ID change with or without a new secret")
    func oauthClientOverrideEdgeCases() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }

        // Initial client ID + secret
        let first = try SettingsActions.saveOAuthClientOverride(
            id: "  client-a.apps.googleusercontent.com  ",
            secret: "  secret-a-\(UUID().uuidString)  ", // gitleaks:allow
            in: rig.secretStore
        )
        #expect(!first.cleared)
        #expect(first.clientId == "client-a.apps.googleusercontent.com")
        #expect(first.hasClientSecret == true)
        #expect(first.keptExistingSecret == false)

        // Same ID with empty secret keeps the existing secret
        let kept = try SettingsActions.saveOAuthClientOverride(
            id: "client-a.apps.googleusercontent.com",
            secret: "   ",
            in: rig.secretStore
        )
        #expect(!kept.cleared)
        #expect(kept.hasClientSecret == true)
        #expect(kept.keptExistingSecret == true)
        #expect(rig.secretStore.load().oauthClientSecretOverride != nil)

        // Different ID with a new secret saves the new secret
        let newSecret = "secret-b-\(UUID().uuidString)" // gitleaks:allow
        let replacedWithSecret = try SettingsActions.saveOAuthClientOverride(
            id: "client-b.apps.googleusercontent.com",
            secret: newSecret,
            in: rig.secretStore
        )
        #expect(!replacedWithSecret.cleared)
        #expect(replacedWithSecret.clientId == "client-b.apps.googleusercontent.com")
        #expect(replacedWithSecret.hasClientSecret == true)
        #expect(replacedWithSecret.keptExistingSecret == false)
        #expect(rig.secretStore.load().oauthClientSecretOverride == newSecret)

        // Different ID with empty secret drops the previous client's secret
        let replacedWithoutSecret = try SettingsActions.saveOAuthClientOverride(
            id: "client-c.apps.googleusercontent.com",
            secret: "",
            in: rig.secretStore
        )
        #expect(!replacedWithoutSecret.cleared)
        #expect(replacedWithoutSecret.clientId == "client-c.apps.googleusercontent.com")
        #expect(replacedWithoutSecret.hasClientSecret == false)
        #expect(replacedWithoutSecret.keptExistingSecret == false)
        #expect(rig.secretStore.load().oauthClientSecretOverride == nil)

        // Whitespace-only ID clears both ID and secret
        _ = try SettingsActions.saveOAuthClientOverride(
            id: "client-c.apps.googleusercontent.com",
            secret: newSecret,
            in: rig.secretStore
        )
        let cleared = try SettingsActions.saveOAuthClientOverride(
            id: "   \n\t  ",
            secret: newSecret,
            in: rig.secretStore
        )
        #expect(cleared.cleared == true)
        #expect(cleared.clientId == nil)
        #expect(cleared.hasClientSecret == false)
        #expect(rig.secretStore.load().oauthClientIdOverride == nil)
        #expect(rig.secretStore.load().oauthClientSecretOverride == nil)
    }

    @Test("applySet with clampNumbers false refuses out-of-range numbers with extension messages and normalizes quiet hours")
    func unclampedNumbersAndQuietHourNormalization() throws {
        var config = SpeakerConfig()

        let normalized = try SettingsActions.applySet(
            key: .quietHoursStart,
            value: .string("7:05"),
            to: &config,
            clampNumbers: false
        )
        #expect(normalized.appliedValue == .string("07:05"))
        #expect(config.quietHoursStart == "07:05")
        #expect(SpeakerConfig.minutesSinceMidnight("07:05") == 7 * 60 + 5)

        do {
            _ = try SettingsActions.applySet(key: .announceVolume, value: .int(105), to: &config, clampNumbers: false)
            Issue.record("Expected out-of-range announceVolume to throw")
        } catch let error as SettingsActions.Refusal {
            #expect(error == SettingsActions.Refusal.outOfRange(key: "announce_volume", value: 105, min: 0, max: 100))
            #expect(error.errorDescription == "The announcement volume is a whole number from 0 to 100")
        }

        do {
            _ = try SettingsActions.applySet(key: .pauseMediaExtraSeconds, value: .int(11), to: &config, clampNumbers: false)
            Issue.record("Expected out-of-range pauseMediaExtraSeconds to throw")
        } catch let error as SettingsActions.Refusal {
            #expect(error == SettingsActions.Refusal.outOfRange(key: "pause_media_extra_seconds", value: 11, min: 0, max: 10))
            #expect(error.errorDescription == "Resume after is a number of seconds from 0 to 10")
        }

        do {
            _ = try SettingsActions.applySet(key: .pollIntervalSeconds, value: .int(4), to: &config, clampNumbers: false)
            Issue.record("Expected out-of-range pollIntervalSeconds to throw")
        } catch let error as SettingsActions.Refusal {
            #expect(error == SettingsActions.Refusal.outOfRange(key: "poll_interval_seconds", value: 4, min: 5, max: 300))
            #expect(error.errorDescription == "The poll interval is a whole number of seconds from 5 to 300")
        }
    }

    @MainActor
    @Test("ConfigManager.setSetting rolls back in-memory config when save fails and reconciles chat monitor only on monitor changes")
    func configManagerSetSettingRollbackAndMonitorReconciliation() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }

        final class SpyMonitor: ChatMonitorControlling {
            var isRunning = false
            var calls: [String] = []
            func start() { isRunning = true; calls.append("start") }
            func stop() { isRunning = false; calls.append("stop") }
            func restartIfRunning() { if isRunning { calls.append("restart") } }
        }

        try rig.secretStore.save(Secrets(slackToken: "xoxp-cm-\(UUID().uuidString)")) // gitleaks:allow
        let manager = ConfigManager(
            configPath: rig.appProfile.settingsURL,
            historyPath: rig.appProfile.historyURL,
            secrets: rig.secretStore
        )
        let spy = SpyMonitor()
        manager.chatMonitor = spy

        // Non-chat setting does not touch the chat monitor
        _ = try manager.setSetting(.speechLength, value: .string("full"))
        #expect(manager.config.effectiveSpeechLength == .full)
        #expect(spy.calls.isEmpty)

        // Enabling Slack starts the chat monitor; setting it to the same value does not restart
        _ = try manager.setSetting(.slackEnabled, value: .bool(true))
        #expect(spy.calls == ["start"])
        _ = try manager.setSetting(.slackEnabled, value: .bool(true))
        #expect(spy.calls == ["start"])

        // Make the settings directory read-only so atomic write fails, and verify rollback
        let dirPath = rig.appProfile.settingsURL.deletingLastPathComponent().path
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dirPath)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dirPath)
        }

        let applied = manager.applySetting(.speechLength, .string("minimal"))
        #expect(applied == false)
        #expect(manager.config.effectiveSpeechLength == .full)
    }

    // MARK: - 8. PR C1 Actions: setSecret, snooze, setNetwork, setReadAnyway, importAntigravity, performAgentHook

    @Test("setSecret trims values, clears on empty string, and switches Courier off when clearing courier")
    func setSecretActionsAndCourierClear() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }

        let slackVal = "xoxp-action-\(UUID().uuidString)" // gitleaks:allow
        let beeperVal = "beeper-action-\(UUID().uuidString)" // gitleaks:allow
        let courierVal = "courier-action-\(UUID().uuidString)" // gitleaks:allow
        let geminiVal = "AIza-action-\(UUID().uuidString)" // gitleaks:allow

        let rSlack = try SettingsActions.setSecret(.slack, value: "  \(slackVal) \n", in: rig.secretStore, configFile: rig.configFile)
        #expect(rSlack == SettingsActions.SetSecretResult(name: .slack, cleared: false, courierSwitchedOff: false))
        #expect(rig.secretStore.load().slackToken == slackVal)

        let rBeeper = try SettingsActions.setSecret(.beeper, value: " \(beeperVal) ", in: rig.secretStore, configFile: rig.configFile)
        #expect(rBeeper == SettingsActions.SetSecretResult(name: .beeper, cleared: false, courierSwitchedOff: false))
        #expect(rig.secretStore.load().beeperToken == beeperVal)

        let rCourier = try SettingsActions.setSecret(.courier, value: courierVal, in: rig.secretStore, configFile: rig.configFile)
        #expect(rCourier == SettingsActions.SetSecretResult(name: .courier, cleared: false, courierSwitchedOff: false))
        #expect(rig.secretStore.load().courierToken == courierVal)

        let rGemini = try SettingsActions.setSecret(.geminiKey, value: "  \(geminiVal)  ", in: rig.secretStore, configFile: rig.configFile)
        #expect(rGemini == SettingsActions.SetSecretResult(name: .geminiKey, cleared: false, courierSwitchedOff: false))
        #expect(rig.secretStore.load().geminiApiKey == geminiVal)

        // Enable Courier now that a token is present, then clear the Courier secret via setSecret("")
        _ = try SettingsActions.set(key: .courierEnabled, value: .bool(true), in: rig.configFile, secrets: rig.secretStore)
        #expect(rig.readConfig().effectiveChatMonitor.courierEnabled == true)

        let rClearCourier = try SettingsActions.setSecret(.courier, value: "   ", in: rig.secretStore, configFile: rig.configFile)
        #expect(rClearCourier == SettingsActions.SetSecretResult(name: .courier, cleared: true, courierSwitchedOff: true))
        #expect(rig.secretStore.load().courierToken == nil)
        #expect(rig.readConfig().effectiveChatMonitor.courierEnabled == false)

        let rClearGemini = try SettingsActions.setSecret(.geminiKey, value: "", in: rig.secretStore, configFile: rig.configFile)
        #expect(rClearGemini == SettingsActions.SetSecretResult(name: .geminiKey, cleared: true, courierSwitchedOff: false))
        #expect(rig.secretStore.load().geminiApiKey == nil)
    }

    @Test("snooze sets snoozeUntil for 1...240 minutes, clears when nil, and throws outOfRange outside 1...240")
    func snoozeActionValidationAndClear() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }

        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let until30 = try SettingsActions.snooze(minutes: 30, now: now, in: rig.configFile)
        #expect(until30 == now.addingTimeInterval(30 * 60))
        #expect(rig.readConfig().snoozeUntil == now.addingTimeInterval(30 * 60))

        let cleared = try SettingsActions.snooze(minutes: nil, now: now, in: rig.configFile)
        #expect(cleared == nil)
        #expect(rig.readConfig().snoozeUntil == nil)

        for invalid in [0, -1, 241, 1000] {
            var draft = SpeakerConfig()
            #expect(throws: SettingsActions.Refusal.outOfRange(key: "snooze", value: invalid, min: 1, max: 240)) {
                try SettingsActions.applySnooze(minutes: invalid, now: now, to: &draft)
            }
        }
    }

    @Test("setNetwork and setReadAnyway mutate chat_monitor network lists cleanly")
    func setNetworkAndReadAnywayActions() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }

        try SettingsActions.setNetwork(app: .beeper, key: "whatsapp", reading: false, in: rig.configFile)
        try SettingsActions.setNetwork(app: .courier, key: "signal", reading: false, in: rig.configFile)
        try SettingsActions.setReadAnyway(key: "slack", on: true, in: rig.configFile)

        var cfg = rig.readConfig()
        #expect(cfg.effectiveChatMonitor.beeperMutedNetworks == ["whatsapp"])
        #expect(cfg.effectiveChatMonitor.courierMutedNetworks == ["signal"])
        #expect(cfg.effectiveChatMonitor.courierReadAnyway == ["slack"])

        try SettingsActions.setNetwork(app: .beeper, key: "whatsapp", reading: true, in: rig.configFile)
        try SettingsActions.setReadAnyway(key: "slack", on: false, in: rig.configFile)

        cfg = rig.readConfig()
        #expect(cfg.effectiveChatMonitor.beeperMutedNetworks.isEmpty)
        #expect(cfg.effectiveChatMonitor.courierReadAnyway.isEmpty)
    }

    @Test("importAntigravity imports Google Home credentials from a scratch token file and returns false when absent")
    func importAntigravityAction() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }

        let missingURL = rig.root.appendingPathComponent("missing_tokens.json")
        #expect(try SettingsActions.importAntigravity(from: missingURL, in: rig.secretStore) == false)

        let tokenURL = rig.root.appendingPathComponent("mcp_oauth_tokens.json")
        let tokenJSON: [String: Any] = [
            GoogleHomeClient.mcpEndpointString: [
                "client_id": "ag-client.apps.googleusercontent.com",
                "client_secret": "ag-secret-\(UUID().uuidString)", // gitleaks:allow
                "token": [
                    "access_token": "ya29.ag-access-\(UUID().uuidString)", // gitleaks:allow
                    "refresh_token": "1//ag-refresh-\(UUID().uuidString)", // gitleaks:allow
                    "expiry": "2026-12-01T00:00:00Z",
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: tokenJSON, options: [.prettyPrinted, .sortedKeys]).write(to: tokenURL)

        let imported = try SettingsActions.importAntigravity(from: tokenURL, in: rig.secretStore)
        #expect(imported == true)
        #expect(rig.secretStore.load().google?.clientId == "ag-client.apps.googleusercontent.com")
    }

    @Test("performAgentHook installs, removes, and adds broadcast instruction in scratch home")
    func performAgentHookAction() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }

        let appExe = "/Applications/Vitruvian Speaker.app/Contents/MacOS/VitruvianSpeaker"
        #expect(SettingsActions.codingAgent(for: "claude_code") == .claudeCode)
        #expect(SettingsActions.codingAgent(for: "antigravity") == .antigravity)
        #expect(SettingsActions.codingAgent(for: "opencode") == .opencode)
        #expect(SettingsActions.codingAgent(for: "unknown") == nil)

        try SettingsActions.performAgentHook(agent: .claudeCode, action: .install, home: rig.home, executablePath: appExe)
        let integration = AgentIntegration(home: rig.home, executablePath: appExe, bootout: { _ in })
        #expect(integration.status(of: .claudeCode).hook == .installed)

        try SettingsActions.performAgentHook(agent: .claudeCode, action: .addInstruction, home: rig.home, executablePath: appExe)
        #expect(integration.status(of: .claudeCode).configuredByInstruction == true)

        try SettingsActions.performAgentHook(agent: .claudeCode, action: .remove, home: rig.home, executablePath: appExe)
        #expect(integration.status(of: .claudeCode).hook == .notInstalled)
    }
}

extension SettingsActions {
    /// Recording fake implementation of `DoorSwitchSeam` for unit tests.
    /// Records every step in exact order and never quits, opens, or trashes
    /// any real application.
    final class RecordingDoorSwitchSeam: DoorSwitchSeam {
        let me: VitruvianSpeakerProfile.Door
        let chosenBy: String
        let doorFile: DoorFile
        let home: URL
        let appProfile: VitruvianSpeakerProfile
        let extensionProfile: VitruvianSpeakerProfile?
        var appProgram: String?
        var extensionProgram: String?
        var fixedNow: Date
        var callerInTrash: Bool
        var otherIsInstalled: Bool
        var otherRunning: Bool
        var quitOtherResult: Bool
        var openOtherSucceeded: Bool
        var enableLoginItemError: Error?
        var turnOffLoginItemError: Error?
        var moveToTrashError: Error?
        var openVitruvianSucceeded: Bool
        var copyOverride: ((VitruvianSpeakerProfile, VitruvianSpeakerProfile) throws -> CopyReport)?

        /// Every effect recorded in order.
        private(set) var steps: [String] = []

        init(
            me: VitruvianSpeakerProfile.Door = .app,
            chosenBy: String = "Vitruvian Speaker test 1.0",
            doorFile: DoorFile,
            home: URL,
            appProfile: VitruvianSpeakerProfile,
            extensionProfile: VitruvianSpeakerProfile?,
            appProgram: String? = nil,
            extensionProgram: String? = nil,
            now: Date = Date(timeIntervalSince1970: 1_900_000_000),
            callerInTrash: Bool = false,
            otherIsInstalled: Bool = true,
            otherRunning: Bool = false,
            quitOtherResult: Bool = true,
            openOtherSucceeded: Bool = true,
            enableLoginItemError: Error? = nil,
            turnOffLoginItemError: Error? = nil,
            moveToTrashError: Error? = nil,
            openVitruvianSucceeded: Bool = true,
            copyOverride: ((VitruvianSpeakerProfile, VitruvianSpeakerProfile) throws -> CopyReport)? = nil
        ) {
            self.me = me
            self.chosenBy = chosenBy
            self.doorFile = doorFile
            self.home = home
            self.appProfile = appProfile
            self.extensionProfile = extensionProfile
            self.appProgram = appProgram
            self.extensionProgram = extensionProgram
            self.fixedNow = now
            self.callerInTrash = callerInTrash
            self.otherIsInstalled = otherIsInstalled
            self.otherRunning = otherRunning
            self.quitOtherResult = quitOtherResult
            self.openOtherSucceeded = openOtherSucceeded
            self.enableLoginItemError = enableLoginItemError
            self.turnOffLoginItemError = turnOffLoginItemError
            self.moveToTrashError = moveToTrashError
            self.openVitruvianSucceeded = openVitruvianSucceeded
            self.copyOverride = copyOverride
        }

        func resetSteps() {
            steps.removeAll()
        }

        func now() -> Date { fixedNow }

        func inTrash() -> Bool { callerInTrash }

        func readDoor() -> DoorRecord? {
            steps.append("readDoor")
            return doorFile.read()
        }

        func otherInstalled(record: DoorRecord?) -> Bool {
            otherIsInstalled
        }

        func profile(for side: VitruvianSpeakerProfile.Door, record: DoorRecord?) -> VitruvianSpeakerProfile? {
            side == .app ? appProfile : (extensionProfile ?? AppStartup.extensionProfile(record: record))
        }

        func program(for side: VitruvianSpeakerProfile.Door, record: DoorRecord?) -> String? {
            switch side {
            case .app:
                return appProgram
            case .extension:
                return extensionProgram ?? record?.installedExtension?.program
            }
        }

        func copy(from source: VitruvianSpeakerProfile, to destination: VitruvianSpeakerProfile) throws -> CopyReport {
            steps.append("copy(\(source.door.rawValue)->\(destination.door.rawValue))")
            if let copyOverride {
                return try copyOverride(source, destination)
            }
            return try DoorCopy.copy(from: source, to: destination)
        }

        func credentialsChanged(in destination: VitruvianSpeakerProfile) {
            steps.append("credentialsChanged(\(destination.door.rawValue))")
        }

        func writeChoice(_ side: VitruvianSpeakerProfile.Door, at date: Date, chosenBy: String) throws {
            steps.append("writeChoice(\(side.rawValue))")
            try doorFile.update {
                $0.chosen = side
                $0.chosenAt = date
                $0.chosenBy = chosenBy
            }
        }

        func repointHooks(to side: VitruvianSpeakerProfile.Door, program: String) -> [String] {
            steps.append("repointHooks(\(side.rawValue))")
            return SettingsActions.repointStaleHooks(home: home, to: program)
        }

        func refreshRole() {
            steps.append("refreshRole")
        }

        func quitOther() -> Bool {
            steps.append("quitOther")
            return quitOtherResult
        }

        func isOtherRunning() -> Bool {
            otherRunning
        }

        func openOtherAndEnableLoginItem() -> [String] {
            steps.append("openOther")
            var lines: [String] = []
            if !openOtherSucceeded {
                lines.append(DoorWords.couldNotOpen)
            }
            steps.append("enableLoginItem")
            if let enableLoginItemError {
                lines.append(enableLoginItemError.localizedDescription)
            } else {
                lines.append(DoorWords.loginItemOn)
            }
            return lines
        }

        func turnOffLoginItem() throws {
            steps.append("turnOffLoginItem")
            if let turnOffLoginItemError { throw turnOffLoginItemError }
        }

        func moveToTrash() throws {
            steps.append("moveToTrash")
            if let moveToTrashError { throw moveToTrashError }
        }

        func quitSelf() {
            steps.append("quitSelf")
        }

        func openVitruvian() -> Bool {
            steps.append("openVitruvian")
            return openVitruvianSucceeded
        }
    }
}
