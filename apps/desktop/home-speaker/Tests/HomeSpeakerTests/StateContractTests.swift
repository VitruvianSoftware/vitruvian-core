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

/// Tests `--state --json` and `--apply --json '<changes>'` through the
/// command-line functions (`HomeSpeakerCommandLine.action`, `.state`, `.apply`)
/// over scratch files and injected seams — never spawning a process or
/// touching real user directories.
@Suite("State & Apply CLI Contract")
struct StateContractTests {

    // MARK: - Scratch Rig & Golden Fixture

    private struct ScratchRig {
        let root: URL
        let appDir: URL
        let extDir: URL
        let agentHome: URL
        let configFile: SpeakerConfigFile
        let secrets: SecretStore
        let history: BroadcastHistory
        let monitorStatusFile: ChatMonitorStatusFile
        let doorFile: DoorFile
        let appProfile: HomeSpeakerProfile
        let extProfile: HomeSpeakerProfile
        let hookExecutablePath = "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker"
        let extExecutablePath = "/Users/test/Library/Application Support/Vitruvian/Tools/dev.vitruvian.homespeaker/bin/tool"

        static let systemVoices: [LocalVoice] = [
            LocalVoice(id: "com.apple.voice.premium.en-US.Ava", name: "Ava", language: "en-US", quality: .premium),
            LocalVoice(id: "com.apple.voice.enhanced.en-GB.Daniel", name: "Daniel", language: "en-GB", quality: .enhanced),
        ]

        static let fixedDate: Date = {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(secondsFromGMT: 0)!
            return cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 23, minute: 15, second: 0))!
        }()

        static var utcCalendar: Calendar {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(secondsFromGMT: 0)!
            return cal
        }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("homespeaker-state-contract-\(UUID().uuidString)", isDirectory: true)
            appDir = root.appendingPathComponent("app-data", isDirectory: true)
            extDir = root.appendingPathComponent("ext-data", isDirectory: true)
            agentHome = root.appendingPathComponent("agent-home", isDirectory: true)
            for dir in [appDir, extDir, agentHome] {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            configFile = SpeakerConfigFile(url: appDir.appendingPathComponent("speaker_broadcast.json"))
            secrets = SecretStore(fileURL: appDir.appendingPathComponent("secrets.json"))
            history = BroadcastHistory(fileURL: appDir.appendingPathComponent("speaker_history.json"))
            monitorStatusFile = ChatMonitorStatusFile(url: appDir.appendingPathComponent("speaker_monitor_status.json"))
            doorFile = DoorFile(url: root.appendingPathComponent("speaker_door.json"))

            appProfile = HomeSpeakerProfile(
                door: .app,
                settingsURL: configFile.url,
                historyURL: history.fileURL,
                secretsURL: secrets.fileURL,
                messagePrefix: "com.vitruviansoftware.homespeaker.test.\(UUID().uuidString)",
                liveLockURL: nil,
                toolFolder: nil
            )
            extProfile = HomeSpeakerProfile(
                door: .extension,
                settingsURL: extDir.appendingPathComponent("speaker_broadcast.json"),
                historyURL: extDir.appendingPathComponent("speaker_history.json"),
                secretsURL: extDir.appendingPathComponent("secrets.json"),
                messagePrefix: "com.vitruviansoftware.homespeaker.ext.test.\(UUID().uuidString)",
                liveLockURL: extDir.appendingPathComponent("running.lock"),
                toolFolder: extDir.appendingPathComponent("tool", isDirectory: true)
            )
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }

        func makeSeam(
            program: HomeSpeakerProfile.Door = .app,
            otherInstalled: Bool = true,
            appRunning: Bool = true,
            extensionRunning: Bool = false,
            speakerVolume: Int? = 45,
            speakerOnline: [String: Bool] = ["bedroom": false, "kitchen": true, "office": true],
            gwsInstalled: Bool = true,
            antigravityTokensAvailable: Bool = true,
            doorSwitchSeam: (any SettingsActions.DoorSwitchSeam)? = nil
        ) -> HomeSpeakerStateContract.Seam {
            HomeSpeakerStateContract.Seam(
                program: program,
                homeSpeakerVersion: { "1.19.1" },
                configFile: configFile,
                secrets: secrets,
                history: history,
                monitorStatusFile: monitorStatusFile,
                doorFile: doorFile,
                otherInstalled: { _ in otherInstalled },
                appRunning: { appRunning },
                extensionRunning: { _ in extensionRunning },
                systemVoices: { Self.systemVoices },
                speakerVolume: { speakerVolume },
                speakerOnline: { speakerOnline },
                gwsInstalled: { gwsInstalled },
                antigravityTokensAvailable: { antigravityTokensAvailable },
                shippedOAuthClient: {
                    OAuthClient(clientId: "shipped-client.apps.googleusercontent.com", clientSecret: "SECRET-SHIPPED-DO-NOT-LEAK")
                },
                agentHome: agentHome,
                hookExecutablePath: program == .app ? hookExecutablePath : extExecutablePath,
                doorSwitchSeam: { doorSwitchSeam },
                now: { Self.fixedDate },
                calendar: Self.utcCalendar
            )
        }

        static let secretCanaries: [String] = [
            "SECRET-HOME-CLIENT-DO-NOT-LEAK",
            "SECRET-HOME-ACCESS-DO-NOT-LEAK",
            "SECRET-HOME-REFRESH-DO-NOT-LEAK",
            "SECRET-CHAT-CLIENT-DO-NOT-LEAK",
            "SECRET-CHAT-ACCESS-DO-NOT-LEAK",
            "SECRET-CHAT-REFRESH-DO-NOT-LEAK",
            "SECRET-SLACK-TOKEN-DO-NOT-LEAK",
            "SECRET-BEEPER-TOKEN-DO-NOT-LEAK",
            "SECRET-COURIER-TOKEN-DO-NOT-LEAK",
            "SECRET-GEMINI-KEY-DO-NOT-LEAK",
            "SECRET-CUSTOM-OAUTH-DO-NOT-LEAK",
            "SECRET-SHIPPED-DO-NOT-LEAK",
        ]

        func seedGoldenFixture() throws {
            var config = SpeakerConfig(
                enabled: true,
                defaultTarget: "office",
                structureId: "home-structure-1",
                structureName: "Home",
                targets: [
                    "kitchen": SpeakerDevice(
                        id: "dev-kitchen",
                        type: "sdm.devices.types.SPEAKER",
                        name: "Kitchen Speaker",
                        room: "Kitchen"
                    ),
                    "office": SpeakerDevice(
                        id: "dev-office",
                        type: "sdm.devices.types.SPEAKER",
                        name: "Office Mini",
                        room: "Office"
                    ),
                    "bedroom": SpeakerDevice(
                        id: "dev-bedroom",
                        type: "sdm.devices.types.DISPLAY",
                        name: "Bedroom Hub",
                        room: "Bedroom"
                    ),
                ],
                speechLength: .summary,
                quietHoursEnabled: true,
                quietHoursStart: "22:30",
                quietHoursEnd: "07:00",
                chatMonitor: ChatMonitorConfig(
                    slackEnabled: true,
                    googleChatEnabled: true,
                    pollIntervalSeconds: 30,
                    googleChatSource: .gws,
                    gwsAccount: "ops@example.com",
                    beeperEnabled: true,
                    beeperAnnounce: .directAndMentions,
                    beeperMutedNetworks: ["signal"],
                    beeperAddress: "http://127.0.0.1:23373",
                    courierEnabled: true,
                    courierAnnounce: .all,
                    courierMutedNetworks: [],
                    courierAddress: "http://127.0.0.1:23390",
                    courierReadAnyway: ["slack"]
                )
            )
            config.speakHome = true
            config.homeCastVoice = true
            config.speakLocal = true
            config.speakPhone = true
            config.localVoice = "com.apple.voice.premium.en-US.Ava"
            config.pauseMedia = true
            config.pauseMediaExtraSeconds = 3
            config.announceVolumeEnabled = true
            config.announceVolume = 65
            config.localEngine = .gemini
            config.geminiVoice = "Kore"
            config.customVoices = [CustomVoice(id: "cloned-1", name: "Studio Narrator")]
            config.announcementStyle = .briefing
            config.styleModel = .gemini
            config.announceClaudeCode = true
            config.announceAntigravity = true
            config.announceOpenCode = false
            _ = try configFile.modify { $0 = config }

            try secrets.save(
                Secrets(
                    google: GoogleCredentials(
                        clientId: "123-home.apps.googleusercontent.com",
                        clientSecret: "SECRET-HOME-CLIENT-DO-NOT-LEAK", // gitleaks:allow
                        accessToken: "SECRET-HOME-ACCESS-DO-NOT-LEAK", // gitleaks:allow
                        refreshToken: "SECRET-HOME-REFRESH-DO-NOT-LEAK", // gitleaks:allow
                        scopes: [GoogleAuth.homeScope],
                        email: "owner@example.com"
                    ),
                    googleChat: GoogleCredentials(
                        clientId: "123-home.apps.googleusercontent.com",
                        clientSecret: "SECRET-CHAT-CLIENT-DO-NOT-LEAK", // gitleaks:allow
                        accessToken: "SECRET-CHAT-ACCESS-DO-NOT-LEAK", // gitleaks:allow
                        refreshToken: "SECRET-CHAT-REFRESH-DO-NOT-LEAK", // gitleaks:allow
                        scopes: GoogleAuth.chatScopes,
                        email: "owner@example.com"
                    ),
                    slackToken: "SECRET-SLACK-TOKEN-DO-NOT-LEAK", // gitleaks:allow
                    oauthClientIdOverride: "custom-client-id.apps.googleusercontent.com",
                    oauthClientSecretOverride: "SECRET-CUSTOM-OAUTH-DO-NOT-LEAK", // gitleaks:allow
                    beeperToken: "SECRET-BEEPER-TOKEN-DO-NOT-LEAK", // gitleaks:allow
                    geminiApiKey: "SECRET-GEMINI-KEY-DO-NOT-LEAK", // gitleaks:allow
                    courierToken: "SECRET-COURIER-TOKEN-DO-NOT-LEAK" // gitleaks:allow
                )
            )

            try doorFile.update {
                $0.chosen = .app
                $0.chosenAt = Self.fixedDate.addingTimeInterval(-3600)
                $0.chosenBy = "HomeSpeaker app 1.19.1"
                $0.installedExtension = DoorRecord.ExtensionEntry(
                    program: extExecutablePath,
                    dataFolder: extDir.path,
                    version: "1.19.1",
                    door: DoorRecord.ExtensionEntry.runsAlone
                )
            }

            let pollDate = Self.fixedDate.addingTimeInterval(-10)
            try monitorStatusFile.write(
                ChatMonitorStatus(
                    isRunning: true,
                    lastPollDate: pollDate,
                    lastError: nil,
                    slackIdentity: "owner (Vitruvian)",
                    activeGoogleChatBackend: "gws (ops@example.com)",
                    beeperNetworkStates: [
                        BeeperNetworkState(key: "signal", name: "Signal", state: .muted),
                        BeeperNetworkState(key: "whatsapp", name: "WhatsApp", state: .reading),
                    ],
                    courierNetworkStates: [
                        BeeperNetworkState(key: "imessage", name: "iMessage", state: .reading),
                        BeeperNetworkState(key: "slack", name: "Slack (Vitruvian)", state: .reading),
                    ],
                    pid: 4242
                )
            )

            let historyDate = Self.fixedDate.addingTimeInterval(-60)
            try history.append(
                BroadcastLogItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    timestamp: historyDate,
                    text: "All tests passed on main.",
                    targetName: "Office Mini + this Mac",
                    source: "Claude Code"
                )
            )

            // Install Claude Code hook in the scratch agentHome so hooks.claude_code is "installed".
            let claudeDir = agentHome.appendingPathComponent(".claude", isDirectory: true)
            try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
            let integration = AgentIntegration(
                home: agentHome,
                executablePath: hookExecutablePath,
                bootout: { _ in }
            )
            try integration.installHook(for: .claudeCode)
            _ = config
        }
    }

    private static func testdataURL(_ filename: String) -> URL {
        let env = ProcessInfo.processInfo.environment
        if let runfiles = env["RUNFILES_DIR"] ?? env["TEST_SRCDIR"] {
            let workspace = env["TEST_WORKSPACE"] ?? "_main"
            let bazel = URL(fileURLWithPath: runfiles)
                .appendingPathComponent(workspace)
                .appendingPathComponent("apps/desktop/home-speaker/testdata")
                .appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: bazel.path) {
                return bazel
            }
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("testdata")
            .appendingPathComponent(filename)
    }

    // MARK: - 1. Golden `--state --json` Document & Both Programs Answering

    @Test("Golden --state --json output matches testdata/state_v1.json and runs through HomeSpeakerCommandLine.action")
    @MainActor
    func goldenStateMatchesTestdata() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        let seam = rig.makeSeam(program: .app)
        let engine = HomeSpeakerEngine(profile: rig.appProfile)
        let parts = HomeSpeakerCommandLine.Parts.app(stateSeam: { _ in seam })

        guard case .now(let out) = HomeSpeakerCommandLine.action(
            for: ["--state", "--json"],
            engine: engine,
            parts: parts
        ) else {
            Issue.record("--state --json did not return .now")
            return
        }

        #expect(out.exitCode == 0)
        #expect(out.stderr.isEmpty)
        #expect(out.stdout.count == 1)
        #expect(!engine.configLoaded, "--state reads through its seam without triggering lazy ConfigManager side effects")

        let actualJSON = out.stdout[0]
        let goldenURL = Self.testdataURL("state_v1.json")
        let goldenData = try Data(contentsOf: goldenURL)
        let expectedDict = try #require(
            JSONSerialization.jsonObject(with: goldenData) as? [String: Any]
        )
        let actualDict = try #require(
            JSONSerialization.jsonObject(with: Data(actualJSON.utf8)) as? [String: Any]
        )
        #expect(actualJSON == HomeSpeakerStateContract.encodeJSON(expectedDict))
        #expect(NSDictionary(dictionary: actualDict) == NSDictionary(dictionary: expectedDict))
    }

    @Test("Either program (app or extension) answers --state --json whether chosen or not")
    func eitherProgramAnswersStateWhetherChosenOrNot() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        for chosen in [HomeSpeakerProfile.Door?.some(.app), .some(.extension), nil] {
            try rig.doorFile.update { $0.chosen = chosen }
            for program in [HomeSpeakerProfile.Door.app, .extension] {
                let out = HomeSpeakerCommandLine.state(seam: rig.makeSeam(program: program))
                #expect(out.exitCode == 0)
                let parsed = try #require(
                    JSONSerialization.jsonObject(with: Data(out.stdout[0].utf8)) as? [String: Any]
                )
                #expect(parsed["contract_version"] as? Int == 1)
                #expect(parsed["program"] as? String == program.rawValue)
                #expect(parsed["app_installed"] as? Bool == true)
                #expect(parsed["extension_installed"] as? Bool == true)
                #expect(parsed["other_installed"] as? Bool == true)
                if let chosen {
                    #expect(parsed["chosen"] as? String == chosen.rawValue)
                } else {
                    #expect(parsed["chosen"] is NSNull)
                }
            }
        }
    }

    // MARK: - 2. Secret Redaction

    @Test("No secret value ever appears in --state or --apply output")
    func noSecretValueEverAppearsInOutput() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        let seam = rig.makeSeam()
        let stateOut = HomeSpeakerCommandLine.state(seam: seam)
        let stateText = (stateOut.stdout + stateOut.stderr).joined(separator: "\n")

        for canary in ScratchRig.secretCanaries {
            #expect(!stateText.contains(canary), "Secret canary \(canary) leaked in --state output")
        }

        let applyPayload = #"{"contract_version":1,"operations":[{"op":"set","key":"speech_length","value":"full"}]}"#
        let applyOut = HomeSpeakerCommandLine.apply(applyPayload, seam: seam)
        #expect(applyOut.exitCode == 0)
        let applyText = (applyOut.stdout + applyOut.stderr).joined(separator: "\n")

        for canary in ScratchRig.secretCanaries {
            #expect(!applyText.contains(canary), "Secret canary \(canary) leaked in --apply output")
        }

        // Verify boolean presence flags and public identifiers ARE reported accurately.
        let parsed = try #require(JSONSerialization.jsonObject(with: Data(stateOut.stdout[0].utf8)) as? [String: Any])
        let signIn = try #require(parsed["sign_in"] as? [String: Any])
        #expect(signIn["signed_in"] as? Bool == true)
        #expect(signIn["email"] as? String == "owner@example.com")
        #expect(signIn["client_override_present"] as? Bool == true)
        #expect(signIn["custom_oauth_client_id"] as? String == "custom-client-id.apps.googleusercontent.com")
        #expect(signIn["has_custom_oauth_secret"] as? Bool == true)
        #expect(signIn["has_gemini_key"] as? Bool == true)

        let chat = try #require(parsed["chat"] as? [String: Any])
        #expect(chat["has_slack_token"] as? Bool == true)
        #expect(chat["has_beeper_token"] as? Bool == true)
        #expect(chat["has_courier_token"] as? Bool == true)
        #expect(chat["has_chat_access"] as? Bool == true)
    }

    // MARK: - 3. Every `--apply` Operation

    @Test("Every --apply operation mutates state through SettingsActions and returns updated state + results")
    @MainActor
    func everyApplyOperationWorks() async throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        let switchSeam = SettingsActions.RecordingDoorSwitchSeam(
            me: .app,
            chosenBy: "HomeSpeaker app 1.19.1",
            doorFile: rig.doorFile,
            home: rig.agentHome,
            appProfile: rig.appProfile,
            extensionProfile: rig.extProfile,
            appProgram: rig.hookExecutablePath,
            extensionProgram: rig.extExecutablePath,
            now: ScratchRig.fixedDate,
            otherIsInstalled: true,
            otherRunning: true
        )
        let seam = rig.makeSeam(program: .app, doorSwitchSeam: switchSeam)
        let engine = HomeSpeakerEngine(profile: rig.appProfile)
        let parts = HomeSpeakerCommandLine.Parts.app(stateSeam: { _ in seam })

        // Batch 1: set (bool, choice, number with clamp warning, time, text), setDefaultSpeaker, removeSpeaker, clearChatToken
        let batch1 = """
        {
          "contract_version": 1,
          "operations": [
            {"op": "set", "key": "speak_phone", "value": false},
            {"op": "set", "key": "speech_length", "value": "headline"},
            {"op": "set", "key": "announce_volume", "value": 150},
            {"op": "set", "key": "quiet_hours_start", "value": "21:45"},
            {"op": "set", "key": "gws_account", "value": "team@example.com"},
            {"op": "set", "key": "beeper_address", "value": "http://localhost:23374"},
            {"op": "setDefaultSpeaker", "key": "kitchen"},
            {"op": "removeSpeaker", "key": "kitchen"},
            {"op": "clearChatToken", "token": "courier"}
          ]
        }
        """

        guard case .headless(let timeout, let timedOut, let body1) = HomeSpeakerCommandLine.action(
            for: ["--apply", "--json", batch1],
            engine: engine,
            parts: parts
        ) else {
            Issue.record("--apply --json did not return .headless")
            return
        }
        #expect(timeout == 60)
        #expect(timedOut.exitCode != 0)
        let timedOutParsed = try #require(
            JSONSerialization.jsonObject(with: Data(timedOut.stdout[0].utf8)) as? [String: Any]
        )
        #expect(timedOutParsed["ok"] as? Bool == false)
        let timedOutErr = try #require(timedOutParsed["error"] as? [String: Any])
        #expect(timedOutErr["code"] as? String == "timed_out")

        let out1 = await body1()

        #expect(out1.exitCode == 0)
        let resp1 = try #require(JSONSerialization.jsonObject(with: Data(out1.stdout[0].utf8)) as? [String: Any])
        #expect(resp1["ok"] as? Bool == true)
        let results1 = try #require(resp1["results"] as? [[String: Any]])
        #expect(results1.count == 9)

        // Check clamp warning on announce_volume (op index 2)
        #expect(results1[2]["clamped"] as? Bool == true)
        #expect(results1[2]["value"] as? Int == 100)
        #expect((results1[2]["warning"] as? String)?.contains("clamped") == true)

        // Check removeSpeaker result (removing "kitchen" which was default picks "bedroom" alphabetically by name "Bedroom Hub")
        #expect(results1[7]["op"] as? String == "removeSpeaker")
        #expect(results1[7]["was_present"] as? Bool == true)
        #expect(results1[7]["default_target"] as? String == "bedroom")

        // Check clearChatToken result (clearing courier also switches courier_enabled off)
        #expect(results1[8]["op"] as? String == "clearChatToken")
        #expect(results1[8]["courier_switched_off"] as? Bool == true)
        #expect(rig.secrets.load().courierToken == nil)

        let state1 = try #require(resp1["state"] as? [String: Any])
        let chat1 = try #require(state1["chat"] as? [String: Any])
        #expect(chat1["has_courier_token"] as? Bool == false)
        let speakers1 = try #require(state1["speakers"] as? [[String: Any]])
        #expect(speakers1.map { $0["key"] as? String } == ["bedroom", "office"])

        // Batch 2: saveOAuthClient (keeps secret when ID unchanged) and reset (preserves discovered speakers, resets preferences)
        let batch2 = """
        {
          "contract_version": 1,
          "operations": [
            {"op": "saveOAuthClient", "client_id": "custom-client-id.apps.googleusercontent.com", "client_secret": ""},
            {"op": "reset"}
          ]
        }
        """
        let out2 = HomeSpeakerCommandLine.apply(batch2, seam: seam)
        #expect(out2.exitCode == 0)
        let resp2 = try #require(JSONSerialization.jsonObject(with: Data(out2.stdout[0].utf8)) as? [String: Any])
        #expect(resp2["ok"] as? Bool == true)
        let results2 = try #require(resp2["results"] as? [[String: Any]])
        #expect(results2[0]["kept_existing_secret"] as? Bool == true)
        let state2 = try #require(resp2["state"] as? [String: Any])
        let speakers2 = try #require(state2["speakers"] as? [[String: Any]])
        #expect(speakers2.count == 2, "reset preserves discovered speakers")
        let quiet2 = try #require(state2["quiet_hours"] as? [String: Any])
        #expect(quiet2["enabled"] as? Bool == false, "reset clears quiet_hours_enabled back to default")

        // Batch 3: switchTo sent on its own
        let batch3 = """
        {
          "contract_version": 1,
          "operations": [
            {"op": "switchTo", "side": "extension"}
          ]
        }
        """
        let out3 = HomeSpeakerCommandLine.apply(batch3, seam: seam)
        #expect(out3.exitCode == 0)
        let resp3 = try #require(JSONSerialization.jsonObject(with: Data(out3.stdout[0].utf8)) as? [String: Any])
        #expect(resp3["ok"] as? Bool == true)
        let state3 = try #require(resp3["state"] as? [String: Any])
        #expect(state3["chosen"] as? String == "extension")

        // Verify switchTo re-pointed the Claude Code hook in agentHome to the extension binary.
        let extIntegration = AgentIntegration(
            home: rig.agentHome,
            executablePath: rig.extExecutablePath,
            bootout: { _ in }
        )
        #expect(extIntegration.status(of: .claudeCode).hook == .installed)
    }

    // MARK: - 4. Every Refusal Is Atomic (Nothing Written, Exit 1)

    @Test("Every refused operation writes nothing and reports op_index, code, and message")
    func everyRefusalWritesNothingAndExitsOne() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        // Remove courier token so enabling courier_enabled triggers missing_token.
        try rig.secrets.update { $0.courierToken = nil }
        try rig.configFile.modify { $0.chatMonitor?.courierEnabled = false }

        let switchNotInstalledSeam = SettingsActions.RecordingDoorSwitchSeam(
            me: .app,
            chosenBy: "HomeSpeaker app 1.19.1",
            doorFile: rig.doorFile,
            home: rig.agentHome,
            appProfile: rig.appProfile,
            extensionProfile: nil,
            appProgram: rig.hookExecutablePath,
            extensionProgram: nil,
            now: ScratchRig.fixedDate,
            otherIsInstalled: false,
            otherRunning: false
        )
        let seam = rig.makeSeam(program: .app, otherInstalled: false, doorSwitchSeam: switchNotInstalledSeam)
        let beforeBytes = try Data(contentsOf: rig.configFile.url)

        let refusalCases: [(opJSON: String, expectedCode: String)] = [
            (#"{"op":"set","key":"nonexistent_key","value":true}"#, "unknown_key"),
            (#"{"op":"set","key":"enabled","value":"yes"}"#, "wrong_kind"),
            (#"{"op":"set","key":"speech_length","value":"novel"}"#, "invalid_choice"),
            (#"{"op":"set","key":"announce_volume","value":150,"clamp":false}"#, "out_of_range"),
            (#"{"op":"set","key":"quiet_hours_start","value":"25:99"}"#, "invalid_time"),
            (#"{"op":"set","key":"beeper_address","value":"http://example.com:23373"}"#, "invalid_address"),
            (#"{"op":"set","key":"courier_enabled","value":true}"#, "missing_token"),
            (#"{"op":"switchTo","side":"extension"}"#, "switch_must_be_alone"),
            (#"{"op":"unknownOperation"}"#, "unknown_op"),
        ]

        for (opJSON, expectedCode) in refusalCases {
            // Put a valid operation at index 0 and the failing operation at index 1
            // to prove that index 0 is rolled back and nothing is written to disk.
            let payload = """
            {
              "contract_version": 1,
              "operations": [
                {"op": "set", "key": "enabled", "value": false},
                \(opJSON)
              ]
            }
            """
            let out = HomeSpeakerCommandLine.apply(payload, seam: seam)
            #expect(out.exitCode == 1, "Expected exitCode 1 for \(expectedCode)")
            let parsed = try #require(JSONSerialization.jsonObject(with: Data(out.stdout[0].utf8)) as? [String: Any])
            #expect(parsed["ok"] as? Bool == false)
            let error = try #require(parsed["error"] as? [String: Any])
            #expect(error["op_index"] as? Int == 1, "Expected op_index 1 for \(expectedCode)")
            #expect(error["code"] as? String == expectedCode)
            #expect(!((error["message"] as? String) ?? "").isEmpty)

            let afterBytes = try Data(contentsOf: rig.configFile.url)
            #expect(afterBytes == beforeBytes, "Refused batch (\(expectedCode)) modified settings file on disk")
        }

        // Also verify standalone switchTo when target side is not installed refuses with switch_refused at op_index 0.
        let switchAloneOut = HomeSpeakerCommandLine.apply(
            #"{"contract_version":1,"operations":[{"op":"switchTo","side":"extension"}]}"#,
            seam: seam
        )
        #expect(switchAloneOut.exitCode == 1)
        let switchAloneParsed = try #require(JSONSerialization.jsonObject(with: Data(switchAloneOut.stdout[0].utf8)) as? [String: Any])
        let switchAloneErr = try #require(switchAloneParsed["error"] as? [String: Any])
        #expect(switchAloneErr["op_index"] as? Int == 0)
        #expect(switchAloneErr["code"] as? String == "switch_refused")
        #expect(try Data(contentsOf: rig.configFile.url) == beforeBytes)
    }

    // MARK: - 5. `not_chosen` Refusal on Standby Program

    @Test("Running --apply on the program that is NOT chosen refuses with not_chosen and names the chosen program")
    func notChosenRefusalNamesChosenProgram() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        let beforeBytes = try Data(contentsOf: rig.configFile.url)

        // 1. Extension is chosen in speaker_door.json; running --apply on app refuses.
        try rig.doorFile.update { $0.chosen = .extension }
        let appSeam = rig.makeSeam(program: .app)
        let appOut = HomeSpeakerCommandLine.apply(
            #"{"contract_version":1,"operations":[{"op":"set","key":"enabled","value":false}]}"#,
            seam: appSeam
        )
        #expect(appOut.exitCode == 1)
        let appResp = try #require(JSONSerialization.jsonObject(with: Data(appOut.stdout[0].utf8)) as? [String: Any])
        #expect(appResp["ok"] as? Bool == false)
        let appErr = try #require(appResp["error"] as? [String: Any])
        #expect(appErr["code"] as? String == "not_chosen")
        #expect(appErr["chosen"] as? String == "extension")
        #expect((appErr["message"] as? String)?.contains("extension") == true)
        #expect(try Data(contentsOf: rig.configFile.url) == beforeBytes)

        // 2. App is chosen in speaker_door.json; running --apply on extension refuses.
        try rig.doorFile.update { $0.chosen = .app }
        let extSeam = rig.makeSeam(program: .extension)
        let extOut = HomeSpeakerCommandLine.apply(
            #"{"contract_version":1,"operations":[{"op":"set","key":"enabled","value":false}]}"#,
            seam: extSeam
        )
        #expect(extOut.exitCode == 1)
        let extResp = try #require(JSONSerialization.jsonObject(with: Data(extOut.stdout[0].utf8)) as? [String: Any])
        #expect(extResp["ok"] as? Bool == false)
        let extErr = try #require(extResp["error"] as? [String: Any])
        #expect(extErr["code"] as? String == "not_chosen")
        #expect(extErr["chosen"] as? String == "app")
        #expect((extErr["message"] as? String)?.contains("app") == true)
    }

    // MARK: - 6. Malformed Input & Unknown Contract Version

    @Test("Malformed JSON or unsupported contract_version returns JSON error and non-zero exit")
    func malformedInputAndUnknownContractVersion() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()
        let seam = rig.makeSeam()

        let badInputs: [(input: String, expectedCode: String)] = [
            ("{not valid json", "invalid_json"),
            ("[]", "invalid_json"),
            (#"{"operations":[]}"#, "invalid_contract_version"),
            (#"{"contract_version":"1","operations":[]}"#, "invalid_contract_version"),
            (#"{"contract_version":2,"operations":[]}"#, "unsupported_contract_version"),
            (#"{"contract_version":1}"#, "invalid_operations"),
            (#"{"contract_version":1,"operations":"not-an-array"}"#, "invalid_operations"),
        ]

        for (input, expectedCode) in badInputs {
            let out = HomeSpeakerCommandLine.apply(input, seam: seam)
            #expect(out.exitCode == 1, "Expected exit 1 for \(expectedCode)")
            let parsed = try #require(JSONSerialization.jsonObject(with: Data(out.stdout[0].utf8)) as? [String: Any])
            #expect(parsed["ok"] as? Bool == false)
            let error = try #require(parsed["error"] as? [String: Any])
            #expect(error["code"] as? String == expectedCode)
        }
    }

    // MARK: - 7. Unknown Keys Survive `--apply`

    @Test("Unknown keys at top level, in targets, in chat_monitor, and in custom_voices survive --apply")
    func unknownKeysSurviveApply() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        let rawWithUnknowns: [String: Any] = [
            "enabled": true,
            "default_target": "office",
            "structure_id": "home-structure-1",
            "structure_name": "Home",
            "future_top_level_key": "keep-top-level",
            "future_nested_object": ["alpha": 42, "beta": "keep"],
            "targets": [
                "office": [
                    "id": "dev-office",
                    "type": "sdm.devices.types.SPEAKER",
                    "name": "Office Mini",
                    "room": "Office",
                    "future_device_field": "keep-device-field",
                ],
            ],
            "chat_monitor": [
                "slack_enabled": true,
                "poll_interval_seconds": 30,
                "future_chat_key": "keep-chat-field",
            ],
            "custom_voices": [
                [
                    "id": "cloned-1",
                    "name": "Studio Narrator",
                    "future_voice_field": "keep-voice-field",
                ],
            ],
        ]
        let initialData = try JSONSerialization.data(withJSONObject: rawWithUnknowns, options: [.prettyPrinted, .sortedKeys])
        try initialData.write(to: rig.configFile.url)

        let seam = rig.makeSeam()

        // Apply a set operation
        let setOut = HomeSpeakerCommandLine.apply(
            #"{"contract_version":1,"operations":[{"op":"set","key":"speech_length","value":"headline"}]}"#,
            seam: seam
        )
        #expect(setOut.exitCode == 0)

        let afterSet = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: rig.configFile.url)) as? [String: Any]
        )
        #expect(afterSet["future_top_level_key"] as? String == "keep-top-level")
        #expect((afterSet["future_nested_object"] as? [String: Any])?["beta"] as? String == "keep")
        let officeAfterSet = (afterSet["targets"] as? [String: Any])?["office"] as? [String: Any]
        #expect(officeAfterSet?["future_device_field"] as? String == "keep-device-field")
        let chatAfterSet = afterSet["chat_monitor"] as? [String: Any]
        #expect(chatAfterSet?["future_chat_key"] as? String == "keep-chat-field")
        let voicesAfterSet = afterSet["custom_voices"] as? [[String: Any]]
        #expect(voicesAfterSet?.first?["future_voice_field"] as? String == "keep-voice-field")

        // Apply a reset operation — top-level, target, and chat_monitor unknown keys still survive!
        let resetOut = HomeSpeakerCommandLine.apply(
            #"{"contract_version":1,"operations":[{"op":"reset"}]}"#,
            seam: seam
        )
        #expect(resetOut.exitCode == 0)

        let afterReset = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: rig.configFile.url)) as? [String: Any]
        )
        #expect(afterReset["future_top_level_key"] as? String == "keep-top-level")
        let officeAfterReset = (afterReset["targets"] as? [String: Any])?["office"] as? [String: Any]
        #expect(officeAfterReset?["future_device_field"] as? String == "keep-device-field")
        let chatAfterReset = afterReset["chat_monitor"] as? [String: Any]
        #expect(chatAfterReset?["future_chat_key"] as? String == "keep-chat-field")
    }

    // MARK: - 8. Concurrent Writers Under the Lock

    @Test("Concurrent threads calling --apply on the same scratch files lose no updates across barriered rounds")
    func twoConcurrentWritersUnderLockLoseNoUpdates() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        let seam = rig.makeSeam()
        let rounds = 25

        for round in 1...rounds {
            let expectedVolume = 10 + round
            let expectedSpeakLocal = (round % 2 == 0)
            let expectedPoll = 20 + round
            let expectedQuietStart = String(format: "%02d:%02d", round % 24, round % 60)
            let expectedGws = "round-\(round)@example.com"
            let expectedSpeakPhone = (round % 2 == 1)
            let expectedPrompt = "Prompt round \(round)"
            let expectedExtraSeconds = round % 11

            let payloads = [
                """
                {"contract_version":1,"operations":[
                  {"op":"set","key":"announce_volume","value":\(expectedVolume)},
                  {"op":"set","key":"speak_local","value":\(expectedSpeakLocal)}
                ]}
                """,
                """
                {"contract_version":1,"operations":[
                  {"op":"set","key":"poll_interval_seconds","value":\(expectedPoll)},
                  {"op":"set","key":"quiet_hours_start","value":"\(expectedQuietStart)"}
                ]}
                """,
                """
                {"contract_version":1,"operations":[
                  {"op":"set","key":"gws_account","value":"\(expectedGws)"},
                  {"op":"set","key":"speak_phone","value":\(expectedSpeakPhone)}
                ]}
                """,
                """
                {"contract_version":1,"operations":[
                  {"op":"set","key":"custom_style_prompt","value":"\(expectedPrompt)"},
                  {"op":"set","key":"pause_media_extra_seconds","value":\(expectedExtraSeconds)}
                ]}
                """,
            ]

            // One thread per writer, not `concurrentPerform`: that runs at
            // most one iteration per core, so on a 3-core CI Mac the fourth
            // writer never starts and the other three wait for it forever.
            // Every wait is bounded, so a broken barrier fails the test
            // instead of hanging the whole suite.
            let lock = NSLock()
            nonisolated(unsafe) var ready = 0
            nonisolated(unsafe) var exitCodes = [Int32](repeating: -1, count: payloads.count)
            let startGate = DispatchSemaphore(value: 0)
            let finished = DispatchGroup()
            for idx in payloads.indices {
                finished.enter()
                let writer = Thread {
                    defer { finished.leave() }
                    lock.lock()
                    ready += 1
                    let allReady = (ready == payloads.count)
                    lock.unlock()
                    if allReady {
                        for _ in payloads.indices { startGate.signal() }
                    }
                    guard startGate.wait(timeout: .now() + 10) == .success else { return }
                    let out = HomeSpeakerCommandLine.apply(payloads[idx], seam: seam)
                    lock.lock()
                    exitCodes[idx] = out.exitCode
                    lock.unlock()
                }
                writer.start()
            }
            guard finished.wait(timeout: .now() + 30) == .success else {
                Issue.record("Writers did not finish within 30 s in round \(round)")
                return
            }

            for code in exitCodes {
                #expect(code == 0)
            }

            guard case .loaded(let cfg) = rig.configFile.read() else {
                Issue.record("Config file unreadable after round \(round)")
                return
            }
            #expect(cfg.effectiveAnnounceVolume == expectedVolume, "Lost announce_volume in round \(round)")
            #expect(cfg.effectiveSpeakLocal == expectedSpeakLocal, "Lost speak_local in round \(round)")
            #expect(cfg.effectiveChatMonitor.clampedPollInterval == expectedPoll, "Lost poll_interval_seconds in round \(round)")
            #expect(cfg.quietHoursStart == expectedQuietStart, "Lost quiet_hours_start in round \(round)")
            #expect(cfg.effectiveChatMonitor.gwsAccount == expectedGws, "Lost gws_account in round \(round)")
            #expect(cfg.effectiveSpeakPhone == expectedSpeakPhone, "Lost speak_phone in round \(round)")
            #expect(cfg.customStylePrompt == expectedPrompt, "Lost custom_style_prompt in round \(round)")
            #expect(cfg.effectivePauseMediaExtraSeconds == Double(expectedExtraSeconds), "Lost pause_media_extra_seconds in round \(round)")
        }
    }

    // MARK: - 9. Cleared Keys Are Not Resurrected on `--apply`

    @Test("Cleared keys are not resurrected on --apply while foreign keys survive")
    func clearedKeysAreNotResurrectedOnApply() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        let seededJSON: [String: Any] = [
            "enabled": true,
            "default_target": "office",
            "structure_id": "home-structure-1",
            "structure_name": "Home",
            "custom_style_prompt": "Pirate voice",
            "future_top_level_key": "keep",
            "targets": [
                "office": [
                    "id": "dev-office",
                    "type": "sdm.devices.types.SPEAKER",
                    "name": "Office Mini",
                    "room": "Office",
                ],
            ],
            "chat_monitor": [
                "slack_enabled": true,
                "future_chat_key": "keep",
            ],
        ]
        let seededData = try JSONSerialization.data(withJSONObject: seededJSON, options: [.prettyPrinted, .sortedKeys])
        try seededData.write(to: rig.configFile.url)

        let seam = rig.makeSeam()

        // (a) Apply {"op":"set","key":"custom_style_prompt","value":""}
        let clearPromptOut = HomeSpeakerCommandLine.apply(
            #"{"contract_version":1,"operations":[{"op":"set","key":"custom_style_prompt","value":""}]}"#,
            seam: seam
        )
        #expect(clearPromptOut.exitCode == 0)

        let afterClearPrompt = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: rig.configFile.url)) as? [String: Any]
        )
        let promptOnDisk = afterClearPrompt["custom_style_prompt"] as? String
        #expect(promptOnDisk == nil || promptOnDisk == "")
        #expect(promptOnDisk != "Pirate voice")

        // (b) Apply {"op":"reset"}
        let resetOut = HomeSpeakerCommandLine.apply(
            #"{"contract_version":1,"operations":[{"op":"reset"}]}"#,
            seam: seam
        )
        #expect(resetOut.exitCode == 0)

        let afterReset = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: rig.configFile.url)) as? [String: Any]
        )
        let chatAfterReset = try #require(afterReset["chat_monitor"] as? [String: Any])
        #expect(chatAfterReset["slack_enabled"] == nil, "ours key cleared by reset must not be resurrected")
        #expect(chatAfterReset["future_chat_key"] as? String == "keep")
        #expect(afterReset["future_top_level_key"] as? String == "keep")
        #expect(afterReset["custom_style_prompt"] == nil)
    }

    // MARK: - 10. Huge Numbers Do Not Crash `--apply`

    @Test("Huge numbers in --apply do not crash and return valid JSON with exit 0 or 1")
    func hugeNumbersDoNotCrashApply() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        let seam = rig.makeSeam()
        let keys = ["poll_interval_seconds", "announce_volume"]
        let rawValues = ["1e300", "-1e300", "9223372036854775808"]

        for key in keys {
            for rawVal in rawValues {
                let payload = #"{"contract_version":1,"operations":[{"op":"set","key":"\#(key)","value":\#(rawVal)}]}"#
                let out = HomeSpeakerCommandLine.apply(payload, seam: seam)
                #expect(out.exitCode == 0 || out.exitCode == 1)
                #expect(!out.stdout.isEmpty)
                let parsed = try #require(
                    JSONSerialization.jsonObject(with: Data(out.stdout[0].utf8)) as? [String: Any]
                )
                #expect(parsed["ok"] is Bool)
            }
        }
    }

    // MARK: - 11. Live Command-Line Parts Inject Real DoorSwitchSeam

    @Test("AppStartup.commandLineParts injects a real DoorSwitchSeam that switches and re-points hooks")
    func liveAppCommandLinePartsInjectRealDoorSwitchSeam() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        let check = DoorCheck(
            file: rig.doorFile,
            appInstalled: { true },
            fileExists: { path in path == rig.extExecutablePath }
        )
        let bundleDir = rig.root.appendingPathComponent("HomeSpeaker.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)

        let parts = AppStartup.commandLineParts(
            check: check,
            bundlePath: { bundleDir.path },
            appProgram: { rig.hookExecutablePath },
            home: rig.agentHome,
            now: { ScratchRig.fixedDate }
        )
        let liveSeam = try #require(parts.stateSeam?(rig.appProfile))
        let switchSeam = try #require(
            liveSeam.doorSwitchSeam(),
            "AppStartup.commandLineParts must inject a real DoorSwitchSeam"
        )
        #expect(switchSeam is AppStartup.CommandLineSwitchSeam)
        #expect(!String(describing: type(of: switchSeam)).contains("Recording"))

        // Run --apply switchTo extension with copy: true using the real CommandLineSwitchSeam.
        var testSeam = rig.makeSeam()
        testSeam.doorSwitchSeam = liveSeam.doorSwitchSeam
        let out = HomeSpeakerCommandLine.apply(
            #"{"contract_version":1,"operations":[{"op":"switchTo","side":"extension","copy":true}]}"#,
            seam: testSeam
        )
        #expect(out.exitCode == 0)
        #expect(rig.doorFile.read()?.chosen == .extension)
        #expect(rig.doorFile.read()?.chosenBy == "HomeSpeaker app \(HomeSpeakerVersion.current)")
        let extIntegration = AgentIntegration(home: rig.agentHome, executablePath: rig.extExecutablePath, bootout: { _ in })
        #expect(extIntegration.status(of: .claudeCode).hook == .installed)
    }

    // MARK: - 12. switchTo Must Be Alone in Its Batch & Failed Switch Writes Nothing

    @Test("switchTo must be the only operation in its batch (switch_must_be_alone) and a failed switch writes nothing")
    func atMostOneSwitchPerBatchAndFailedSwitchWritesNothing() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        let switchSeam = SettingsActions.RecordingDoorSwitchSeam(
            me: .app,
            chosenBy: "HomeSpeaker app 1.19.1",
            doorFile: rig.doorFile,
            home: rig.agentHome,
            appProfile: rig.appProfile,
            extensionProfile: rig.extProfile,
            appProgram: rig.hookExecutablePath,
            extensionProgram: rig.extExecutablePath,
            now: ScratchRig.fixedDate,
            otherIsInstalled: true,
            otherRunning: true
        )
        let seam = rig.makeSeam(program: .app, doorSwitchSeam: switchSeam)
        let beforeDoorBytes = try Data(contentsOf: rig.doorFile.url)
        let beforeConfigBytes = try Data(contentsOf: rig.configFile.url)

        // (a) Two switchTo ops in one batch must refuse with switch_must_be_alone and leave speaker_door.json untouched.
        let twoSwitches = """
        {
          "contract_version": 1,
          "operations": [
            {"op": "switchTo", "side": "extension"},
            {"op": "switchTo", "side": "app"}
          ]
        }
        """
        let outTwo = HomeSpeakerCommandLine.apply(twoSwitches, seam: seam)
        #expect(outTwo.exitCode == 1)
        let parsedTwo = try #require(JSONSerialization.jsonObject(with: Data(outTwo.stdout[0].utf8)) as? [String: Any])
        #expect(parsedTwo["ok"] as? Bool == false)
        let errTwo = try #require(parsedTwo["error"] as? [String: Any])
        #expect(errTwo["op_index"] as? Int == 0)
        #expect(errTwo["code"] as? String == "switch_must_be_alone")
        #expect(rig.doorFile.read()?.chosen == .app)
        #expect(try Data(contentsOf: rig.doorFile.url) == beforeDoorBytes)

        // (b) A switchTo combined with a set op in the same batch must refuse with switch_must_be_alone before writing anything.
        let setAndSwitch = """
        {
          "contract_version": 1,
          "operations": [
            {"op": "set", "key": "enabled", "value": false},
            {"op": "switchTo", "side": "extension", "copy": true}
          ]
        }
        """
        let outSetAndSwitch = HomeSpeakerCommandLine.apply(setAndSwitch, seam: seam)
        #expect(outSetAndSwitch.exitCode == 1)
        let parsedSetAndSwitch = try #require(JSONSerialization.jsonObject(with: Data(outSetAndSwitch.stdout[0].utf8)) as? [String: Any])
        #expect(parsedSetAndSwitch["ok"] as? Bool == false)
        let errSetAndSwitch = try #require(parsedSetAndSwitch["error"] as? [String: Any])
        #expect(errSetAndSwitch["op_index"] as? Int == 1)
        #expect(errSetAndSwitch["code"] as? String == "switch_must_be_alone")
        #expect(rig.doorFile.read()?.chosen == .app)
        #expect(try Data(contentsOf: rig.doorFile.url) == beforeDoorBytes)
        #expect(try Data(contentsOf: rig.configFile.url) == beforeConfigBytes)

        // (c) A single-op failing switch writes nothing.
        struct CopyBoom: LocalizedError {
            var errorDescription: String? { "copy failed on purpose" }
        }
        switchSeam.copyOverride = { _, _ in throw CopyBoom() }
        let failingSwitchAlone = """
        {
          "contract_version": 1,
          "operations": [
            {"op": "switchTo", "side": "extension", "copy": true}
          ]
        }
        """
        let outFail = HomeSpeakerCommandLine.apply(failingSwitchAlone, seam: seam)
        #expect(outFail.exitCode == 1)
        let parsedFail = try #require(JSONSerialization.jsonObject(with: Data(outFail.stdout[0].utf8)) as? [String: Any])
        #expect(parsedFail["ok"] as? Bool == false)
        let errFail = try #require(parsedFail["error"] as? [String: Any])
        #expect(errFail["op_index"] as? Int == 0)
        #expect(errFail["code"] as? String == "switch_refused")
        #expect(rig.doorFile.read()?.chosen == .app)
        #expect(try Data(contentsOf: rig.doorFile.url) == beforeDoorBytes)
        #expect(try Data(contentsOf: rig.configFile.url) == beforeConfigBytes)
    }

    // MARK: - 13. Concurrent Secrets Writer Is Not Lost

    @Test("A second writer changing a different secret while a batch's secret op is running is not lost")
    func concurrentSecretsWriterIsNotLost() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        let appSecretsStore = SecretStore(fileURL: rig.secrets.fileURL)
        nonisolated(unsafe) var interleaved = false
        var seam = rig.makeSeam()
        seam.systemVoices = {
            if !interleaved {
                interleaved = true
                try? appSecretsStore.update { secrets in
                    secrets.slackToken = "concurrent-app-slack-token" // gitleaks:allow
                }
            }
            return ScratchRig.systemVoices
        }

        let applyOut = HomeSpeakerCommandLine.apply(
            #"{"contract_version":1,"operations":[{"op":"saveOAuthClient","client_id":"cli-client-id.apps.googleusercontent.com","client_secret":"cli-secret"},{"op":"set","key":"local_voice","value":"com.apple.voice.premium.en-US.Ava"}]}"#,
            seam: seam
        )

        #expect(interleaved, "Seam hook must interleave while batch is running")
        #expect(applyOut.exitCode == 0)
        let finalSecrets = rig.secrets.load()
        #expect(finalSecrets.oauthClientIdOverride == "cli-client-id.apps.googleusercontent.com")
        #expect(finalSecrets.slackToken == "concurrent-app-slack-token")
    }

    // MARK: - 14. QA Probe Tests

    @Test("Probe: switchTo combined with another op (before or after) refuses with switch_must_be_alone and leaves settings, secrets, and door bytes unchanged")
    func probeSwitchWithOtherOpWritesNothing() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        let switchSeam = SettingsActions.RecordingDoorSwitchSeam(
            me: .app,
            chosenBy: "HomeSpeaker app 1.19.1",
            doorFile: rig.doorFile,
            home: rig.agentHome,
            appProfile: rig.appProfile,
            extensionProfile: rig.extProfile,
            appProgram: rig.hookExecutablePath,
            extensionProgram: rig.extExecutablePath,
            now: ScratchRig.fixedDate,
            otherIsInstalled: true,
            otherRunning: true
        )
        let seam = rig.makeSeam(program: .app, doorSwitchSeam: switchSeam)
        let beforeConfigBytes = try Data(contentsOf: rig.configFile.url)
        let beforeSecretsBytes = try Data(contentsOf: rig.secrets.fileURL)
        let beforeDoorBytes = try Data(contentsOf: rig.doorFile.url)

        let batches: [(payload: String, expectedIndex: Int)] = [
            (
                """
                {"contract_version":1,"operations":[
                  {"op":"set","key":"speech_length","value":"full"},
                  {"op":"switchTo","side":"extension","copy":true}
                ]}
                """,
                1
            ),
            (
                """
                {"contract_version":1,"operations":[
                  {"op":"switchTo","side":"extension","copy":true},
                  {"op":"set","key":"speech_length","value":"full"}
                ]}
                """,
                0
            ),
        ]

        for (payload, expectedIndex) in batches {
            let out = HomeSpeakerCommandLine.apply(payload, seam: seam)
            #expect(out.exitCode == 1)
            let parsed = try #require(JSONSerialization.jsonObject(with: Data(out.stdout[0].utf8)) as? [String: Any])
            #expect(parsed["ok"] as? Bool == false)
            let err = try #require(parsed["error"] as? [String: Any])
            #expect(err["op_index"] as? Int == expectedIndex)
            #expect(err["code"] as? String == "switch_must_be_alone")
            #expect(try Data(contentsOf: rig.configFile.url) == beforeConfigBytes)
            #expect(try Data(contentsOf: rig.secrets.fileURL) == beforeSecretsBytes)
            #expect(try Data(contentsOf: rig.doorFile.url) == beforeDoorBytes)
        }
    }

    @Test("Probe: failure after valid set, saveOAuthClient, and clearChatToken writes nothing to settings, secrets, or door")
    func probeFailureInBatchWritesNoSettingsSecretsOrDoor() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        let seam = rig.makeSeam(program: .app)
        let beforeConfigBytes = try Data(contentsOf: rig.configFile.url)
        let beforeSecretsBytes = try Data(contentsOf: rig.secrets.fileURL)
        let beforeDoorBytes = try Data(contentsOf: rig.doorFile.url)

        let payload = """
        {
          "contract_version": 1,
          "operations": [
            {"op": "set", "key": "speech_length", "value": "full"},
            {"op": "saveOAuthClient", "client_id": "new-id.apps.googleusercontent.com", "client_secret": "new-secret"},
            {"op": "clearChatToken", "token": "slack"},
            {"op": "set", "key": "speech_length", "value": "invalid-choice"}
          ]
        }
        """
        let out = HomeSpeakerCommandLine.apply(payload, seam: seam)
        #expect(out.exitCode == 1)
        let parsed = try #require(JSONSerialization.jsonObject(with: Data(out.stdout[0].utf8)) as? [String: Any])
        #expect(parsed["ok"] as? Bool == false)
        let err = try #require(parsed["error"] as? [String: Any])
        #expect(err["op_index"] as? Int == 3)
        #expect(err["code"] as? String == "invalid_choice")
        #expect(try Data(contentsOf: rig.configFile.url) == beforeConfigBytes)
        #expect(try Data(contentsOf: rig.secrets.fileURL) == beforeSecretsBytes)
        #expect(try Data(contentsOf: rig.doorFile.url) == beforeDoorBytes)
    }

    @Test("Probe: secrets never appear in --apply saveOAuthClient output or --apply error messages")
    func probeSecretsNeverAppearInApplyOrErrorOutputs() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        let seam = rig.makeSeam(program: .app)
        let extraSecret = "SECRET-APPLIED-OAUTH-DO-NOT-LEAK"
        let allCanaries = ScratchRig.secretCanaries + [extraSecret]

        let payloads: [(payload: String, expectedExit: Int32)] = [
            (#"{"contract_version":1,"operations":[{"op":"saveOAuthClient","client_id":"new.apps.googleusercontent.com","client_secret":"\#(extraSecret)"}]}"#, 0),
            (#"{"contract_version":1,"operations":[{"op":"clearChatToken","token":"not-a-service"}]}"#, 1),
            (#"{"contract_version":1,"operations":[{"op":"set","key":"speech_length","value":"not-a-choice"}]}"#, 1),
            ("{invalid json", 1),
        ]

        for (payload, expectedExit) in payloads {
            let out = HomeSpeakerCommandLine.apply(payload, seam: seam)
            #expect(out.exitCode == expectedExit)
            let combined = (out.stdout + out.stderr).joined(separator: "\n")
            for canary in allCanaries {
                #expect(!combined.contains(canary), "Secret canary \(canary) leaked in output")
            }
        }
    }

    @Test("Probe: invalid JSON, non-array JSON, and non-object operation entries return JSON error with exit 1 and write nothing")
    func probeNonObjectOperationAndMalformedJsonWriteNothing() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        let seam = rig.makeSeam(program: .app)
        let beforeConfigBytes = try Data(contentsOf: rig.configFile.url)
        let beforeSecretsBytes = try Data(contentsOf: rig.secrets.fileURL)
        let beforeDoorBytes = try Data(contentsOf: rig.doorFile.url)

        let cases: [(input: String, expectedCode: String)] = [
            ("{not valid json", "invalid_json"),
            ("[]", "invalid_json"),
            ("123", "invalid_json"),
            (#"{"contract_version":1,"operations":"not-an-array"}"#, "invalid_operations"),
            (#"{"contract_version":1,"operations":{"op":"reset"}}"#, "invalid_operations"),
            (#"{"contract_version":1,"operations":["not-an-object"]}"#, "invalid_operations"),
            (#"{"contract_version":1,"operations":[123]}"#, "invalid_operations"),
            (#"{"contract_version":1,"operations":[]}"#, "no_operations"),
            (#"{"contract_version":1,"operations":[{"op":"set","key":"enabled","value":false},"not-an-object"]}"#, "invalid_operations"),
        ]

        for (input, expectedCode) in cases {
            let out = HomeSpeakerCommandLine.apply(input, seam: seam)
            #expect(out.exitCode == 1, "Expected exit 1 for \(input)")
            let parsed = try #require(JSONSerialization.jsonObject(with: Data(out.stdout[0].utf8)) as? [String: Any])
            #expect(parsed["ok"] as? Bool == false)
            let err = try #require(parsed["error"] as? [String: Any])
            #expect(err["code"] as? String == expectedCode)
            #expect(try Data(contentsOf: rig.configFile.url) == beforeConfigBytes)
            #expect(try Data(contentsOf: rig.secrets.fileURL) == beforeSecretsBytes)
            #expect(try Data(contentsOf: rig.doorFile.url) == beforeDoorBytes)
        }
    }
}
