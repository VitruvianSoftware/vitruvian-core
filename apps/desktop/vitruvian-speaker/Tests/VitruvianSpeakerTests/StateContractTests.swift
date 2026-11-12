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

        func readConfig() -> SpeakerConfig? {
            if case .loaded(let cfg) = configFile.read() { return cfg }
            return nil
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
            doorSwitchSeam: (any SettingsActions.DoorSwitchSeam)? = nil,
            credentialsChanged: @escaping @Sendable () -> Void = {},
            launchctlBootout: @escaping @Sendable (String) -> Void = { _ in }
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
                calendar: Self.utcCalendar,
                credentialsChanged: credentialsChanged,
                launchctlBootout: launchctlBootout
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

            let readyGate = DispatchSemaphore(value: 0)
            let startGate = DispatchSemaphore(value: 0)
            let group = DispatchGroup()
            let lock = NSLock()
            nonisolated(unsafe) var exitCodes = [Int32](repeating: -1, count: payloads.count)
            nonisolated(unsafe) var workerTimedOut = false

            for idx in 0..<payloads.count {
                let payload = payloads[idx]
                group.enter()
                Thread {
                    defer { group.leave() }
                    readyGate.signal()
                    if startGate.wait(timeout: .now() + .seconds(5)) == .timedOut {
                        lock.lock()
                        workerTimedOut = true
                        lock.unlock()
                        return
                    }
                    let out = HomeSpeakerCommandLine.apply(payload, seam: seam)
                    lock.lock()
                    exitCodes[idx] = out.exitCode
                    lock.unlock()
                }.start()
            }

            var readyTimedOut = false
            for _ in 0..<payloads.count {
                if readyGate.wait(timeout: .now() + .seconds(5)) == .timedOut {
                    readyTimedOut = true
                    break
                }
            }
            for _ in 0..<payloads.count {
                startGate.signal()
            }
            if readyTimedOut {
                Issue.record("Timed out waiting for workers to become ready in round \(round)")
                _ = group.wait(timeout: .now() + .seconds(5))
                return
            }
            if group.wait(timeout: .now() + .seconds(10)) == .timedOut {
                Issue.record("Timed out waiting for concurrent --apply workers to finish in round \(round)")
                return
            }
            if workerTimedOut {
                Issue.record("Worker timed out waiting for startGate in round \(round)")
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

    @Test("A live seam built for another home reads that home's Antigravity tokens, never this account's")
    func liveSeamTakesAntigravityTokensFromItsAgentHome() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        let seam = HomeSpeakerStateContract.Seam.live(
            for: rig.appProfile, agentHome: rig.agentHome, doorSwitchSeam: { nil })
        #expect(seam.antigravityTokensURL.path.hasPrefix(rig.agentHome.path))
    }

    @Test("agentHook combined with another op refuses with hook_must_be_alone and writes no settings, secrets or hook file")
    func agentHookWithOtherOpWritesNothing() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()
        let seam = rig.makeSeam(program: .app)
        let claudeSettings = rig.agentHome.appendingPathComponent(".claude/settings.json")
        let snapshot: () -> [Data?] = {
            [rig.configFile.url, rig.secrets.fileURL, claudeSettings].map { try? Data(contentsOf: $0) }
        }
        let before = snapshot()

        // A hook writes another program's file, outside the settings
        // transaction, so it cannot be undone if a later op fails: it goes alone.
        let payloads = [
            """
            {"contract_version":1,"operations":[
              {"op":"setSecret","name":"slack","value":"xoxp-hook-probe"},
              {"op":"agentHook","agent":"claude_code","action":"remove"}
            ]}
            """,
            """
            {"contract_version":1,"operations":[
              {"op":"agentHook","agent":"claude_code","action":"remove"},
              {"op":"set","key":"speech_length","value":"full"}
            ]}
            """,
        ]
        for payload in payloads {
            let out = HomeSpeakerCommandLine.apply(payload, seam: seam)
            #expect(out.exitCode == 1)
            let parsed = try #require(JSONSerialization.jsonObject(with: Data(out.stdout[0].utf8)) as? [String: Any])
            let err = try #require(parsed["error"] as? [String: Any])
            #expect(err["code"] as? String == "hook_must_be_alone")
            #expect(snapshot() == before)
        }
    }

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

    // MARK: - 15. PR C1 Operations: setSecret, snooze, setNetwork, setReadAnyway, importAntigravity, agentHook

    @Test("setSecret sets and clears slack, beeper, courier, and geminiKey, switches Courier off when cleared, and never leaks secret values")
    func applySetSecretSuccessClearAndRedaction() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        let seam = rig.makeSeam(program: .app)
        let slackCanary = "xoxp-SECRET-SLACK-APPLY-CANARY" // gitleaks:allow
        let beeperCanary = "beeper-SECRET-BEEPER-APPLY-CANARY" // gitleaks:allow
        let courierCanary = "courier-SECRET-COURIER-APPLY-CANARY" // gitleaks:allow
        let geminiCanary = "AIza-SECRET-GEMINI-APPLY-CANARY" // gitleaks:allow
        let canaries = ScratchRig.secretCanaries + [slackCanary, beeperCanary, courierCanary, geminiCanary]

        let setPayload = """
        {
          "contract_version": 1,
          "operations": [
            {"op": "setSecret", "name": "slack", "value": "  \(slackCanary)  "},
            {"op": "setSecret", "name": "beeper", "value": "  \(beeperCanary)\\n"},
            {"op": "setSecret", "name": "courier", "value": "\(courierCanary)"},
            {"op": "setSecret", "name": "geminiKey", "value": "  \(geminiCanary)  "},
            {"op": "set", "key": "courier_enabled", "value": true}
          ]
        }
        """
        let outSet = HomeSpeakerCommandLine.apply(setPayload, seam: seam)
        #expect(outSet.exitCode == 0)
        let combinedSet = (outSet.stdout + outSet.stderr).joined(separator: "\n")
        for canary in canaries {
            #expect(!combinedSet.contains(canary), "Secret canary \(canary) leaked in setSecret output")
        }

        let savedSecrets = rig.secrets.load()
        #expect(savedSecrets.slackToken == slackCanary)
        #expect(savedSecrets.beeperToken == beeperCanary)
        #expect(savedSecrets.courierToken == courierCanary)
        #expect(savedSecrets.geminiApiKey == geminiCanary)
        #expect(rig.readConfig()?.effectiveChatMonitor.courierEnabled == true)

        let parsedSet = try #require(JSONSerialization.jsonObject(with: Data(outSet.stdout[0].utf8)) as? [String: Any])
        let stateAfterSet = try #require(parsedSet["state"] as? [String: Any])
        let chatState = try #require(stateAfterSet["chat"] as? [String: Any])
        let signInState = try #require(stateAfterSet["sign_in"] as? [String: Any])
        #expect(chatState["has_slack_token"] as? Bool == true)
        #expect(chatState["has_beeper_token"] as? Bool == true)
        #expect(chatState["has_courier_token"] as? Bool == true)
        #expect(signInState["has_gemini_key"] as? Bool == true)

        // Clearing courier via empty/whitespace string also switches courier_enabled off
        let clearPayload = """
        {
          "contract_version": 1,
          "operations": [
            {"op": "setSecret", "name": "courier", "value": "   "},
            {"op": "setSecret", "name": "geminiKey", "value": ""}
          ]
        }
        """
        let outClear = HomeSpeakerCommandLine.apply(clearPayload, seam: seam)
        #expect(outClear.exitCode == 0)
        let combinedClear = (outClear.stdout + outClear.stderr).joined(separator: "\n")
        for canary in canaries {
            #expect(!combinedClear.contains(canary), "Secret canary \(canary) leaked in setSecret clear output")
        }
        #expect(rig.secrets.load().courierToken == nil)
        #expect(rig.secrets.load().geminiApiKey == nil)
        #expect(rig.readConfig()?.effectiveChatMonitor.courierEnabled == false)

        let parsedClear = try #require(JSONSerialization.jsonObject(with: Data(outClear.stdout[0].utf8)) as? [String: Any])
        let clearResults = try #require(parsedClear["results"] as? [[String: Any]])
        #expect(clearResults.count == 2)
        #expect(clearResults[0]["op"] as? String == "setSecret")
        #expect(clearResults[0]["name"] as? String == "courier")
        #expect(clearResults[0]["cleared"] as? Bool == true)
        #expect(clearResults[0]["courier_switched_off"] as? Bool == true)

        // Refusals: unknown secret name and missing/non-string value, ensuring secret value never appears in error
        let refusalCases: [(payload: String, expectedCode: String)] = [
            (#"{"contract_version":1,"operations":[{"op":"setSecret","name":"unknown","value":"\#(slackCanary)"}]}"#, "invalid_secret_name"),
            (#"{"contract_version":1,"operations":[{"op":"setSecret","value":"\#(slackCanary)"}]}"#, "invalid_secret_name"),
            (#"{"contract_version":1,"operations":[{"op":"setSecret","name":"slack"}]}"#, "missing_value"),
            (#"{"contract_version":1,"operations":[{"op":"setSecret","name":"slack","value":123}]}"#, "missing_value"),
        ]
        for (payload, expectedCode) in refusalCases {
            let out = HomeSpeakerCommandLine.apply(payload, seam: seam)
            #expect(out.exitCode == 1)
            let combined = (out.stdout + out.stderr).joined(separator: "\n")
            for canary in canaries {
                #expect(!combined.contains(canary), "Secret canary \(canary) leaked in error output")
            }
            let parsed = try #require(JSONSerialization.jsonObject(with: Data(out.stdout[0].utf8)) as? [String: Any])
            let err = try #require(parsed["error"] as? [String: Any])
            #expect(err["code"] as? String == expectedCode)
        }
    }

    @Test("setSecret + set in one batch lands both when valid, or neither when either fails")
    func applySetSecretAndSetBatchAtomicity() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()
        // Start with no courier token and courier_enabled == false
        try rig.secrets.update { $0.courierToken = nil }
        try rig.configFile.modify { $0.effectiveChatMonitor.courierEnabled = false }

        let seam = rig.makeSeam(program: .app)
        let beforeConfigBytes = try Data(contentsOf: rig.configFile.url)
        let beforeSecretsBytes = try Data(contentsOf: rig.secrets.fileURL)

        // 1. Valid setSecret followed by invalid set -> neither lands
        let failSecond = """
        {
          "contract_version": 1,
          "operations": [
            {"op": "setSecret", "name": "courier", "value": "SECRET-BATCH-COURIER-1"},
            {"op": "set", "key": "speech_length", "value": "not-a-valid-length"}
          ]
        }
        """
        let outFailSecond = HomeSpeakerCommandLine.apply(failSecond, seam: seam)
        #expect(outFailSecond.exitCode == 1)
        #expect(!(outFailSecond.stdout + outFailSecond.stderr).joined(separator: "\n").contains("SECRET-BATCH-COURIER-1"))
        #expect(try Data(contentsOf: rig.configFile.url) == beforeConfigBytes)
        #expect(try Data(contentsOf: rig.secrets.fileURL) == beforeSecretsBytes)

        // 2. Valid set followed by invalid setSecret -> neither lands
        let failSecret = """
        {
          "contract_version": 1,
          "operations": [
            {"op": "set", "key": "speech_length", "value": "full"},
            {"op": "setSecret", "name": "not_a_secret", "value": "SECRET-BATCH-COURIER-2"}
          ]
        }
        """
        let outFailSecret = HomeSpeakerCommandLine.apply(failSecret, seam: seam)
        #expect(outFailSecret.exitCode == 1)
        #expect(!(outFailSecret.stdout + outFailSecret.stderr).joined(separator: "\n").contains("SECRET-BATCH-COURIER-2"))
        #expect(try Data(contentsOf: rig.configFile.url) == beforeConfigBytes)
        #expect(try Data(contentsOf: rig.secrets.fileURL) == beforeSecretsBytes)

        // 3. Both valid (setSecret sets courier token, then set enables courier in same batch) -> both land!
        let succeedBoth = """
        {
          "contract_version": 1,
          "operations": [
            {"op": "setSecret", "name": "courier", "value": "SECRET-BATCH-COURIER-OK"},
            {"op": "set", "key": "courier_enabled", "value": true}
          ]
        }
        """
        let outBoth = HomeSpeakerCommandLine.apply(succeedBoth, seam: seam)
        #expect(outBoth.exitCode == 0)
        #expect(!(outBoth.stdout + outBoth.stderr).joined(separator: "\n").contains("SECRET-BATCH-COURIER-OK"))
        #expect(rig.secrets.load().courierToken == "SECRET-BATCH-COURIER-OK")
        #expect(rig.readConfig()?.effectiveChatMonitor.courierEnabled == true)
    }

    @Test("snooze sets snooze_until for 1...240 minutes, clears with clear:true, and refuses out_of_range or malformed inputs")
    func applySnoozeSuccessClearAndRefusals() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        let seam = rig.makeSeam(program: .app)

        // Set snooze for 45 minutes from fixedDate (2026-11-10T23:15:00Z -> 2026-11-11T00:00:00Z)
        let outSnooze = HomeSpeakerCommandLine.apply(
            #"{"contract_version":1,"operations":[{"op":"snooze","minutes":45}]}"#,
            seam: seam
        )
        #expect(outSnooze.exitCode == 0)
        let parsedSnooze = try #require(JSONSerialization.jsonObject(with: Data(outSnooze.stdout[0].utf8)) as? [String: Any])
        let stateSnooze = try #require(parsedSnooze["state"] as? [String: Any])
        #expect(stateSnooze["snooze_until"] as? String == "2026-11-11T00:00:00Z")
        #expect(rig.readConfig()?.snoozeUntil == ScratchRig.fixedDate.addingTimeInterval(45 * 60))

        // Clear snooze
        let outClear = HomeSpeakerCommandLine.apply(
            #"{"contract_version":1,"operations":[{"op":"snooze","clear":true}]}"#,
            seam: seam
        )
        #expect(outClear.exitCode == 0)
        let parsedClear = try #require(JSONSerialization.jsonObject(with: Data(outClear.stdout[0].utf8)) as? [String: Any])
        let stateClear = try #require(parsedClear["state"] as? [String: Any])
        #expect(stateClear["snooze_until"] is NSNull)
        #expect(rig.readConfig()?.snoozeUntil == nil)

        // Out of range & malformed refusals
        let refusalCases: [(payload: String, expectedCode: String)] = [
            (#"{"contract_version":1,"operations":[{"op":"snooze","minutes":0}]}"#, "out_of_range"),
            (#"{"contract_version":1,"operations":[{"op":"snooze","minutes":-5}]}"#, "out_of_range"),
            (#"{"contract_version":1,"operations":[{"op":"snooze","minutes":241}]}"#, "out_of_range"),
            (#"{"contract_version":1,"operations":[{"op":"snooze","minutes":true}]}"#, "wrong_kind"),
            (#"{"contract_version":1,"operations":[{"op":"snooze","minutes":15.5}]}"#, "wrong_kind"),
            (#"{"contract_version":1,"operations":[{"op":"snooze"}]}"#, "invalid_snooze"),
            (#"{"contract_version":1,"operations":[{"op":"snooze","clear":false}]}"#, "invalid_snooze"),
            (#"{"contract_version":1,"operations":[{"op":"snooze","clear":true,"minutes":30}]}"#, "invalid_snooze"),
        ]
        for (payload, expectedCode) in refusalCases {
            let out = HomeSpeakerCommandLine.apply(payload, seam: seam)
            #expect(out.exitCode == 1, "Expected exit 1 for \(payload)")
            let parsed = try #require(JSONSerialization.jsonObject(with: Data(out.stdout[0].utf8)) as? [String: Any])
            let err = try #require(parsed["error"] as? [String: Any])
            #expect(err["code"] as? String == expectedCode, "Expected \(expectedCode) for \(payload), got \(err)")
        }
    }

    @Test("setNetwork and setReadAnyway update Beeper/Courier muted networks and Courier read-anyway lists and refuse invalid inputs")
    func applySetNetworkAndSetReadAnyway() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        let seam = rig.makeSeam(program: .app)
        let payload = """
        {
          "contract_version": 1,
          "operations": [
            {"op": "setNetwork", "app": "beeper", "key": "signal", "reading": true},
            {"op": "setNetwork", "app": "beeper", "key": "whatsapp", "reading": false},
            {"op": "setNetwork", "app": "courier", "key": "imessage", "reading": false},
            {"op": "setReadAnyway", "key": "imessage", "on": true},
            {"op": "setReadAnyway", "key": "slack", "on": false}
          ]
        }
        """
        let out = HomeSpeakerCommandLine.apply(payload, seam: seam)
        #expect(out.exitCode == 0)
        let cfg = try #require(rig.readConfig())
        #expect(cfg.effectiveChatMonitor.beeperMutedNetworks == ["whatsapp"])
        #expect(cfg.effectiveChatMonitor.courierMutedNetworks == ["imessage"])
        #expect(cfg.effectiveChatMonitor.courierReadAnyway == ["imessage"])

        let parsed = try #require(JSONSerialization.jsonObject(with: Data(out.stdout[0].utf8)) as? [String: Any])
        let state = try #require(parsed["state"] as? [String: Any])
        let chat = try #require(state["chat"] as? [String: Any])
        let beeperNets = try #require(chat["beeper_networks"] as? [[String: Any]])
        let courierNets = try #require(chat["courier_networks"] as? [[String: Any]])
        #expect(beeperNets.first(where: { $0["key"] as? String == "signal" })?["state"] as? String == "reading")
        #expect(beeperNets.first(where: { $0["key"] as? String == "whatsapp" })?["state"] as? String == "muted")
        #expect(courierNets.first(where: { $0["key"] as? String == "imessage" })?["state"] as? String == "muted")
        #expect(courierNets.first(where: { $0["key"] as? String == "imessage" })?["read_anyway"] as? Bool == true)
        #expect(courierNets.first(where: { $0["key"] as? String == "slack" })?["read_anyway"] == nil)

        let refusalCases: [(payload: String, expectedCode: String)] = [
            (#"{"contract_version":1,"operations":[{"op":"setNetwork","app":"slack","key":"whatsapp","reading":true}]}"#, "invalid_app"),
            (#"{"contract_version":1,"operations":[{"op":"setNetwork","app":"beeper","key":"  ","reading":true}]}"#, "missing_key"),
            (#"{"contract_version":1,"operations":[{"op":"setNetwork","app":"beeper","key":"whatsapp","reading":"yes"}]}"#, "wrong_kind"),
            (#"{"contract_version":1,"operations":[{"op":"setReadAnyway","key":"","on":true}]}"#, "missing_key"),
            (#"{"contract_version":1,"operations":[{"op":"setReadAnyway","key":"slack","on":1}]}"#, "wrong_kind"),
        ]
        for (payload, expectedCode) in refusalCases {
            let outRefusal = HomeSpeakerCommandLine.apply(payload, seam: seam)
            #expect(outRefusal.exitCode == 1)
            let parsedRefusal = try #require(JSONSerialization.jsonObject(with: Data(outRefusal.stdout[0].utf8)) as? [String: Any])
            let err = try #require(parsedRefusal["error"] as? [String: Any])
            #expect(err["code"] as? String == expectedCode)
        }
    }

    @Test("importAntigravity imports tokens from injectable seam path without leaking secrets, and refuses with no_antigravity_tokens when absent")
    func applyImportAntigravitySuccessAndRefusal() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()
        try rig.secrets.update { $0.google = nil }

        var seam = rig.makeSeam(program: .app)
        let tokensURL = rig.agentHome.appendingPathComponent(".gemini/antigravity/mcp_oauth_tokens.json")
        seam.antigravityTokensURL = tokensURL

        // 1. Missing token file -> refuse with no_antigravity_tokens
        let outMissing = HomeSpeakerCommandLine.apply(
            #"{"contract_version":1,"operations":[{"op":"importAntigravity"}]}"#,
            seam: seam
        )
        #expect(outMissing.exitCode == 1)
        let parsedMissing = try #require(JSONSerialization.jsonObject(with: Data(outMissing.stdout[0].utf8)) as? [String: Any])
        let errMissing = try #require(parsedMissing["error"] as? [String: Any])
        #expect(errMissing["code"] as? String == "no_antigravity_tokens")

        // 2. Write valid Antigravity token file in scratch folder -> import succeeds & secrets never leak
        let clientSecretCanary = "SECRET-AG-IMPORT-CLIENT-SECRET" // gitleaks:allow
        let accessTokenCanary = "SECRET-AG-IMPORT-ACCESS-TOKEN" // gitleaks:allow
        let refreshTokenCanary = "SECRET-AG-IMPORT-REFRESH-TOKEN" // gitleaks:allow
        try FileManager.default.createDirectory(at: tokensURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tokenJSON: [String: Any] = [
            GoogleHomeClient.mcpEndpointString: [
                "client_id": "ag-imported.apps.googleusercontent.com",
                "client_secret": clientSecretCanary,
                "token": [
                    "access_token": accessTokenCanary,
                    "refresh_token": refreshTokenCanary,
                    "expiry": "2026-12-01T00:00:00Z",
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: tokenJSON, options: [.prettyPrinted, .sortedKeys]).write(to: tokensURL)

        let outImport = HomeSpeakerCommandLine.apply(
            #"{"contract_version":1,"operations":[{"op":"importAntigravity"}]}"#,
            seam: seam
        )
        #expect(outImport.exitCode == 0)
        let combined = (outImport.stdout + outImport.stderr).joined(separator: "\n")
        for canary in ScratchRig.secretCanaries + [clientSecretCanary, accessTokenCanary, refreshTokenCanary] {
            #expect(!combined.contains(canary), "Secret canary \(canary) leaked in importAntigravity output")
        }

        #expect(rig.secrets.load().google?.refreshToken == refreshTokenCanary)
        let parsedImport = try #require(JSONSerialization.jsonObject(with: Data(outImport.stdout[0].utf8)) as? [String: Any])
        let stateImport = try #require(parsedImport["state"] as? [String: Any])
        let signIn = try #require(stateImport["sign_in"] as? [String: Any])
        #expect(signIn["signed_in"] as? Bool == true)
    }

    @Test("agentHook install then remove leaves scratch settings.json byte-for-byte as before for unrelated keys and installs the chosen program's command")
    func applyAgentHookInstallRemoveByteForByteAndChosenProgram() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        // Seed scratch ~/.claude/settings.json with unrelated keys and an unrelated Stop hook
        let claudeDir = rig.agentHome.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let claudeSettingsURL = claudeDir.appendingPathComponent("settings.json")
        let initialClaudeSettings: [String: Any] = [
            "env": ["CLAUDE_CUSTOM": "keep-me"],
            "hooks": [
                "PreToolUse": [
                    ["hooks": [["command": "/usr/local/bin/other-pre-hook", "type": "command"]]]
                ],
                "Stop": [
                    ["hooks": [["command": "/usr/local/bin/other-stop-hook", "type": "command"]]]
                ],
            ],
            "model": "claude-sonnet-4-6",
        ]
        let beforeBytes = try JSONSerialization.data(withJSONObject: initialClaudeSettings, options: [.prettyPrinted, .sortedKeys])
        try beforeBytes.write(to: claudeSettingsURL, options: .atomic)

        // 1. With app chosen, install claude_code, antigravity, and opencode hooks + addInstruction
        let appSeam = rig.makeSeam(program: .app)
        // A hook goes alone in its batch, so each is its own --apply.
        let installOps = [
            #"{"op": "agentHook", "agent": "claude_code", "action": "install"}"#,
            #"{"op": "agentHook", "agent": "antigravity", "action": "install"}"#,
            #"{"op": "agentHook", "agent": "opencode", "action": "install"}"#,
            #"{"op": "agentHook", "agent": "opencode", "action": "addInstruction"}"#,
        ]
        var outInstall = CLIOutput(stdout: [], exitCode: -1)
        for op in installOps {
            outInstall = HomeSpeakerCommandLine.apply(#"{"contract_version": 1, "operations": ["# + op + "]}", seam: appSeam)
            #expect(outInstall.exitCode == 0, "install failed: \(op)")
        }
        #expect(outInstall.exitCode == 0)
        let parsedInstall = try #require(JSONSerialization.jsonObject(with: Data(outInstall.stdout[0].utf8)) as? [String: Any])
        let stateAfterInstall = try #require(parsedInstall["state"] as? [String: Any])
        let hooksAfterInstall = try #require(stateAfterInstall["hooks"] as? [String: Any])
        let ccAfterInstall = try #require(hooksAfterInstall["claude_code"] as? [String: Any])
        let agAfterInstall = try #require(hooksAfterInstall["antigravity"] as? [String: Any])
        let ocAfterInstall = try #require(hooksAfterInstall["opencode"] as? [String: Any])
        #expect(ccAfterInstall["hook_state"] as? String == "installed")
        #expect(ccAfterInstall["hook_program"] as? String == rig.hookExecutablePath)
        #expect(agAfterInstall["hook_state"] as? String == "installed")
        #expect(agAfterInstall["hook_program"] as? String == rig.hookExecutablePath)
        #expect(ocAfterInstall["hook_state"] as? String == "installed")
        #expect(ocAfterInstall["hook_program"] as? String == rig.hookExecutablePath)
        #expect(ocAfterInstall["configured_by_instruction"] as? Bool == true)

        // 2. Remove claude_code hook and verify settings.json is byte-for-byte identical to beforeBytes!
        let outRemove = HomeSpeakerCommandLine.apply(
            #"{"contract_version":1,"operations":[{"op":"agentHook","agent":"claude_code","action":"remove"}]}"#,
            seam: appSeam
        )
        #expect(outRemove.exitCode == 0)
        let afterRemoveBytes = try Data(contentsOf: claudeSettingsURL)
        #expect(afterRemoveBytes == beforeBytes)

        // 3. Switch chosen door to extension and verify agentHook install writes the extension's command
        try rig.doorFile.update {
            $0.chosen = .extension
            $0.chosenAt = ScratchRig.fixedDate
            $0.chosenBy = "test"
        }
        let extSeam = rig.makeSeam(program: .extension)
        let outExtInstall = HomeSpeakerCommandLine.apply(
            #"{"contract_version":1,"operations":[{"op":"agentHook","agent":"claude_code","action":"install"}]}"#,
            seam: extSeam
        )
        #expect(outExtInstall.exitCode == 0)
        let parsedExt = try #require(JSONSerialization.jsonObject(with: Data(outExtInstall.stdout[0].utf8)) as? [String: Any])
        let stateExt = try #require(parsedExt["state"] as? [String: Any])
        let hooksExt = try #require(stateExt["hooks"] as? [String: Any])
        let ccExt = try #require(hooksExt["claude_code"] as? [String: Any])
        #expect(ccExt["hook_state"] as? String == "installed")
        #expect(ccExt["hook_program"] as? String == rig.extExecutablePath)

        // Remove again -> still byte-for-byte identical to beforeBytes
        let outExtRemove = HomeSpeakerCommandLine.apply(
            #"{"contract_version":1,"operations":[{"op":"agentHook","agent":"claude_code","action":"remove"}]}"#,
            seam: extSeam
        )
        #expect(outExtRemove.exitCode == 0)
        #expect(try Data(contentsOf: claudeSettingsURL) == beforeBytes)

        // 4. Refusals: invalid agent, invalid action, non-HomeSpeaker executable
        let refusalCases: [(payload: String, expectedCode: String)] = [
            (#"{"contract_version":1,"operations":[{"op":"agentHook","agent":"cursor","action":"install"}]}"#, "invalid_agent"),
            (#"{"contract_version":1,"operations":[{"op":"agentHook","agent":"claude_code","action":"toggle"}]}"#, "invalid_action"),
        ]
        for (payload, expectedCode) in refusalCases {
            let outRef = HomeSpeakerCommandLine.apply(payload, seam: extSeam)
            #expect(outRef.exitCode == 1)
            let parsedRef = try #require(JSONSerialization.jsonObject(with: Data(outRef.stdout[0].utf8)) as? [String: Any])
            let errRef = try #require(parsedRef["error"] as? [String: Any])
            #expect(errRef["code"] as? String == expectedCode)
        }

        var badExeSeam = extSeam
        badExeSeam.hookExecutablePath = "/usr/bin/true"
        let outBadExe = HomeSpeakerCommandLine.apply(
            #"{"contract_version":1,"operations":[{"op":"agentHook","agent":"claude_code","action":"install"}]}"#,
            seam: badExeSeam
        )
        #expect(outBadExe.exitCode == 1)
        let parsedBadExe = try #require(JSONSerialization.jsonObject(with: Data(outBadExe.stdout[0].utf8)) as? [String: Any])
        let errBadExe = try #require(parsedBadExe["error"] as? [String: Any])
        #expect(errBadExe["code"] as? String == "invalid_hook_program")
    }

    @Test("Every new op is refused with not_chosen on the program that is not the chosen one")
    func applyNewOpsRefusedWhenNotChosen() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        // Fixture has chosen == .app; run on .extension
        let unchosenSeam = rig.makeSeam(program: .extension)
        let ops: [String] = [
            #"{"op":"setSecret","name":"slack","value":"xoxp-test"}"#,
            #"{"op":"snooze","minutes":30}"#,
            #"{"op":"setNetwork","app":"beeper","key":"whatsapp","reading":false}"#,
            #"{"op":"setReadAnyway","key":"slack","on":true}"#,
            #"{"op":"importAntigravity"}"#,
            #"{"op":"agentHook","agent":"claude_code","action":"install"}"#,
            #"{"op":"agentHook","agent":"claude_code","action":"disableRival"}"#,
            #"{"op":"removeLegacyAgent"}"#,
        ]
        for op in ops {
            let out = HomeSpeakerCommandLine.apply(
                #"{"contract_version":1,"operations":[\#(op)]}"#,
                seam: unchosenSeam
            )
            #expect(out.exitCode == 1)
            let parsed = try #require(JSONSerialization.jsonObject(with: Data(out.stdout[0].utf8)) as? [String: Any])
            #expect(parsed["ok"] as? Bool == false)
            let err = try #require(parsed["error"] as? [String: Any])
            #expect(err["code"] as? String == "not_chosen")
            #expect(err["chosen"] as? String == "app")
        }
    }

    // MARK: - Running Home Speaker notices secret changes; rival hook; legacy agent

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String = "") { lock.lock(); items.append(item); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private func applyJSON(_ ops: [String], seam: HomeSpeakerStateContract.Seam) -> CLIOutput {
        HomeSpeakerCommandLine.apply(#"{"contract_version":1,"operations":[\#(ops.joined(separator: ","))]}"#, seam: seam)
    }

    @Test("A successful batch that changed a secret tells the running app once; failed or secret-free batches stay silent")
    func credentialsChangedFiresOnceOnlyAfterASuccessfulSecretBatch() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()
        let tokensURL = rig.agentHome.appendingPathComponent(".gemini/antigravity/mcp_oauth_tokens.json")
        try FileManager.default.createDirectory(at: tokensURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tokenJSON: [String: Any] = [
            GoogleHomeClient.mcpEndpointString: [
                "client_id": "n-client.apps.googleusercontent.com",
                "client_secret": "SECRET-N-CLIENT", // gitleaks:allow
                "token": ["access_token": "SECRET-N-ACCESS", "refresh_token": "SECRET-N-REFRESH"], // gitleaks:allow
            ],
        ]
        try JSONSerialization.data(withJSONObject: tokenJSON).write(to: tokensURL)

        let rec = Recorder()
        var seam = rig.makeSeam(program: .app, credentialsChanged: { rec.add() })
        seam.antigravityTokensURL = tokensURL

        // Secret-free batch: silent.
        #expect(applyJSON([#"{"op":"snooze","minutes":15}"#], seam: seam).exitCode == 0)
        #expect(rec.all.isEmpty, "a secret-free batch told the app")

        // A failed batch (secret first, bad op after): silent, nothing written.
        let failed = applyJSON([#"{"op":"setSecret","name":"slack","value":"xoxp-n"}"#, #"{"op":"nope"}"#], seam: seam)
        #expect(failed.exitCode == 1)
        #expect(rec.all.isEmpty, "a failed batch told the app")

        // Each secret-changing op, in a batch of several: once per batch.
        let batch = applyJSON([
            #"{"op":"setSecret","name":"slack","value":"xoxp-n"}"#,
            #"{"op":"setSecret","name":"beeper","value":"b-n"}"#,
            #"{"op":"clearChatToken","token":"courier"}"#,
            #"{"op":"saveOAuthClient","client_id":"n.apps.googleusercontent.com","client_secret":"n-secret"}"#,
            #"{"op":"importAntigravity"}"#,
        ], seam: seam)
        #expect(batch.exitCode == 0, "\(batch.stdout)")
        #expect(rec.all.count == 1, "expected exactly one notice per batch, got \(rec.all.count)")

        for op in [#"{"op":"clearChatToken","token":"slack"}"#,
                   #"{"op":"saveOAuthClient","client_id":"m.apps.googleusercontent.com"}"#,
                   #"{"op":"importAntigravity"}"#] {
            let before = rec.all.count
            #expect(applyJSON([op], seam: seam).exitCode == 0)
            #expect(rec.all.count == before + 1, "\(op) did not tell the app")
        }

        // A config-only batch afterwards still stays silent.
        let before = rec.all.count
        #expect(applyJSON([#"{"op":"set","key":"speech_length","value":"full"}"#], seam: seam).exitCode == 0)
        #expect(rec.all.count == before)
    }

    @Test("A Seam built without credentialsChanged or launchctlBootout is silent: tests never post or call launchctl")
    func seamDefaultsAreNoOps() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()
        let seam = HomeSpeakerStateContract.Seam(
            program: .app, configFile: rig.configFile, secrets: rig.secrets, history: rig.history,
            monitorStatusFile: rig.monitorStatusFile, doorFile: rig.doorFile,
            otherInstalled: { _ in true }, appRunning: { true }, extensionRunning: { _ in false },
            agentHome: rig.agentHome, hookExecutablePath: rig.hookExecutablePath)
        seam.credentialsChanged()
        seam.launchctlBootout("gui/0/never")
        #expect(applyJSON([#"{"op":"setSecret","name":"slack","value":"x"}"#], seam: seam).exitCode == 0)
    }

    @Test("agentHook disableRival renames the rival hook file; with no rival it succeeds; it must be alone")
    func agentHookDisableRival() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()
        let seam = rig.makeSeam(program: .app)
        let disableRival = #"{"op":"agentHook","agent":"claude_code","action":"disableRival"}"#

        let hooksDir = rig.agentHome.appendingPathComponent(".claude/skills/google-home/hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        let rival = hooksDir.appendingPathComponent("hooks.json")
        try #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"python3 stop_broadcast.py"}]}]}}"#
            .write(to: rival, atomically: true, encoding: .utf8)

        // Not alone: refused, and the file stays.
        let together = applyJSON([disableRival, #"{"op":"snooze","minutes":5}"#], seam: seam)
        #expect(together.exitCode == 1)
        #expect(FileManager.default.fileExists(atPath: rival.path))
        let togetherErr = try #require((try JSONSerialization.jsonObject(with: Data(together.stdout[0].utf8)) as? [String: Any])?["error"] as? [String: Any])
        #expect(togetherErr["code"] as? String == "hook_must_be_alone")

        let out = applyJSON([disableRival], seam: seam)
        #expect(out.exitCode == 0, "\(out.stdout)")
        #expect(!FileManager.default.fileExists(atPath: rival.path))
        #expect(FileManager.default.fileExists(atPath: rival.path + ".disabled-by-homespeaker"))
        let parsed = try #require(JSONSerialization.jsonObject(with: Data(out.stdout[0].utf8)) as? [String: Any])
        let results = try #require(parsed["results"] as? [[String: Any]])
        #expect(results[0]["action"] as? String == "disableRival")

        // Nothing to disable now: still ok.
        #expect(applyJSON([disableRival], seam: seam).exitCode == 0)
    }

    @Test("removeLegacyAgent removes the old launch agent, boots it out by gui/<uid>/<label>, turns --state's legacy_launch_agent false, and is alone")
    func removeLegacyAgentRemovesPlistAndBootsOut() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()
        let boots = Recorder()
        let seam = rig.makeSeam(program: .app, launchctlBootout: { boots.add($0) })

        let plist = rig.agentHome.appendingPathComponent("Library/LaunchAgents/\(AgentIntegration.legacyLaunchAgentLabel).plist")
        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "<plist/>".write(to: plist, atomically: true, encoding: .utf8)
        func legacyFlag() throws -> Bool? {
            let state = HomeSpeakerStateContract.stateObject(seam: seam)
            return (state["hooks"] as? [String: Any])?["legacy_launch_agent"] as? Bool
                ?? (state["legacy_launch_agent"] as? Bool)
        }
        #expect(try legacyFlag() == true)

        // Not alone: refused, nothing removed, nothing booted out.
        let together = applyJSON([#"{"op":"removeLegacyAgent"}"#, #"{"op":"snooze","minutes":5}"#], seam: seam)
        #expect(together.exitCode == 1)
        let err = try #require((try JSONSerialization.jsonObject(with: Data(together.stdout[0].utf8)) as? [String: Any])?["error"] as? [String: Any])
        #expect(err["code"] as? String == "legacy_must_be_alone")
        #expect(FileManager.default.fileExists(atPath: plist.path))
        #expect(boots.all.isEmpty)

        let out = applyJSON([#"{"op":"removeLegacyAgent"}"#], seam: seam)
        #expect(out.exitCode == 0, "\(out.stdout)")
        #expect(!FileManager.default.fileExists(atPath: plist.path))
        #expect(boots.all == ["gui/\(getuid())/\(AgentIntegration.legacyLaunchAgentLabel)"])
        #expect(try legacyFlag() == false)

        // No legacy agent installed any more: succeeds and does nothing.
        let again = applyJSON([#"{"op":"removeLegacyAgent"}"#], seam: seam)
        #expect(again.exitCode == 0, "\(again.stdout)")
        #expect(boots.all.count == 1, "bootout ran with no legacy agent installed")
    }

    @Test("Table of every operation --apply accepts matches HomeSpeakerStateContract.supportedOperations and each row executes")
    func applySupportedOperationsTableCompleteness() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        // Seed Antigravity token file in scratch home for the importAntigravity row
        let tokensURL = rig.agentHome.appendingPathComponent(".gemini/antigravity/mcp_oauth_tokens.json")
        try FileManager.default.createDirectory(at: tokensURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tokenJSON: [String: Any] = [
            GoogleHomeClient.mcpEndpointString: [
                "client_id": "table-client.apps.googleusercontent.com",
                "client_secret": "SECRET-TABLE-AG-CLIENT", // gitleaks:allow
                "token": [
                    "access_token": "SECRET-TABLE-AG-ACCESS", // gitleaks:allow
                    "refresh_token": "SECRET-TABLE-AG-REFRESH", // gitleaks:allow
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: tokenJSON, options: [.prettyPrinted, .sortedKeys]).write(to: tokensURL)

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
            otherRunning: false
        )
        var seam = rig.makeSeam(program: .app, doorSwitchSeam: switchSeam)
        seam.antigravityTokensURL = tokensURL

        // Every op `--apply` accepts must have a row in this table; adding an op to
        // HomeSpeakerStateContract.supportedOperations without a row here fails the test.
        let rows: [(op: String, payload: String)] = [
            ("set", #"{"op":"set","key":"speech_length","value":"full"}"#),
            ("setDefaultSpeaker", #"{"op":"setDefaultSpeaker","key":"kitchen"}"#),
            ("removeSpeaker", #"{"op":"removeSpeaker","key":"bedroom"}"#),
            ("setSecret", #"{"op":"setSecret","name":"slack","value":"xoxp-table-secret"}"#),
            ("snooze", #"{"op":"snooze","minutes":15}"#),
            ("setNetwork", #"{"op":"setNetwork","app":"beeper","key":"whatsapp","reading":false}"#),
            ("setReadAnyway", #"{"op":"setReadAnyway","key":"slack","on":true}"#),
            ("importAntigravity", #"{"op":"importAntigravity"}"#),
            ("agentHook", #"{"op":"agentHook","agent":"claude_code","action":"install"}"#),
            ("removeLegacyAgent", #"{"op":"removeLegacyAgent"}"#),
            ("clearChatToken", #"{"op":"clearChatToken","token":"slack"}"#),
            ("saveOAuthClient", #"{"op":"saveOAuthClient","client_id":"table.apps.googleusercontent.com","client_secret":"table-secret"}"#),
            ("reset", #"{"op":"reset"}"#),
            ("switchTo", #"{"op":"switchTo","side":"app","copy":false}"#),
        ]

        let testedOps = Set(rows.map(\.op))
        let declaredOps = Set(HomeSpeakerStateContract.supportedOperations)
        #expect(testedOps == declaredOps, "Every op in HomeSpeakerStateContract.supportedOperations must have a test row")
        #expect(rows.count == HomeSpeakerStateContract.supportedOperations.count)

        for row in rows {
            let out = HomeSpeakerCommandLine.apply(
                #"{"contract_version":1,"operations":[\#(row.payload)]}"#,
                seam: seam
            )
            #expect(out.exitCode == 0, "Expected op \(row.op) to succeed, got \(out.stdout)")
            let parsed = try #require(JSONSerialization.jsonObject(with: Data(out.stdout[0].utf8)) as? [String: Any])
            #expect(parsed["ok"] as? Bool == true)
            let results = try #require(parsed["results"] as? [[String: Any]])
            #expect(results.count == 1)
            #expect(results[0]["op"] as? String == row.op)
            #expect(parsed["state"] as? [String: Any] != nil)
        }
    }

    @Test("Probe: setSecret distinctive values never appear in output/state/error and clearing non-courier secrets leaves config bytes identical")
    func probeSetSecretDistinctiveValuesNeverLeakAndNonCourierClearLeavesConfigBytesIdentical() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()
        let seam = rig.makeSeam(program: .app)

        let needles: [(name: String, value: String)] = [
            ("slack", "DISTINCTIVE-SLACK-CANARY-9911"), // gitleaks:allow
            ("beeper", "DISTINCTIVE-BEEPER-CANARY-9922"), // gitleaks:allow
            ("courier", "DISTINCTIVE-COURIER-CANARY-9933"), // gitleaks:allow
            ("geminiKey", "DISTINCTIVE-GEMINI-CANARY-9944"), // gitleaks:allow
        ]

        let setBatch = """
        {"contract_version":1,"operations":[
            {"op":"setSecret","name":"slack","value":"\(needles[0].value)"},
            {"op":"setSecret","name":"beeper","value":"\(needles[1].value)"},
            {"op":"setSecret","name":"courier","value":"\(needles[2].value)"},
            {"op":"setSecret","name":"geminiKey","value":"\(needles[3].value)"}
        ]}
        """
        let setOut = HomeSpeakerCommandLine.apply(setBatch, seam: seam)
        #expect(setOut.exitCode == 0)
        let stateOut = HomeSpeakerCommandLine.state(seam: seam)
        #expect(stateOut.exitCode == 0)

        let errorBatch = """
        {"contract_version":1,"operations":[
            {"op":"setSecret","name":"slack","value":"\(needles[0].value)"},
            {"op":"setSecret","name":"unknown","value":"\(needles[1].value)"}
        ]}
        """
        let errOut = HomeSpeakerCommandLine.apply(errorBatch, seam: seam)
        #expect(errOut.exitCode == 1)

        let allOutputs = (setOut.stdout + setOut.stderr + stateOut.stdout + stateOut.stderr + errOut.stdout + errOut.stderr)
            .joined(separator: "\n")
        for needle in needles {
            #expect(!allOutputs.contains(needle.value), "Secret for \(needle.name) leaked into CLI output")
        }

        // Clearing slack, beeper, and geminiKey must NOT modify config.json bytes
        let configBeforeNonCourierClear = try Data(contentsOf: rig.configFile.url)
        let clearNonCourier = """
        {"contract_version":1,"operations":[
            {"op":"setSecret","name":"slack","value":""},
            {"op":"setSecret","name":"beeper","value":""},
            {"op":"setSecret","name":"geminiKey","value":""}
        ]}
        """
        let clearNonCourierOut = HomeSpeakerCommandLine.apply(clearNonCourier, seam: seam)
        #expect(clearNonCourierOut.exitCode == 0)
        let configAfterNonCourierClear = try Data(contentsOf: rig.configFile.url)
        #expect(configAfterNonCourierClear == configBeforeNonCourierClear)
    }

    @Test("Probe: batch with valid set + setSecret + snooze followed by invalid op leaves config and secrets byte-identical")
    func probeBatchWithSetSetSecretAndSnoozeFollowedByInvalidOpLeavesFilesByteIdentical() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()
        let seam = rig.makeSeam(program: .app)

        let configBefore = try Data(contentsOf: rig.configFile.url)
        let secretsBefore = try Data(contentsOf: rig.secrets.fileURL)
        let canary = "DISTINCTIVE-BATCH-ROLLBACK-SECRET-7788" // gitleaks:allow

        let payload = """
        {"contract_version":1,"operations":[
            {"op":"set","key":"speech_length","value":"full"},
            {"op":"setSecret","name":"slack","value":"\(canary)"},
            {"op":"snooze","minutes":30},
            {"op":"snooze","minutes":241}
        ]}
        """
        let out = HomeSpeakerCommandLine.apply(payload, seam: seam)
        #expect(out.exitCode == 1)
        let joined = (out.stdout + out.stderr).joined(separator: "\n")
        #expect(!joined.contains(canary))

        let parsed = try #require(JSONSerialization.jsonObject(with: Data(out.stdout[0].utf8)) as? [String: Any])
        #expect(parsed["ok"] as? Bool == false)
        let error = try #require(parsed["error"] as? [String: Any])
        #expect(error["code"] as? String == "out_of_range")
        #expect(error["op_index"] as? Int == 3)

        let configAfter = try Data(contentsOf: rig.configFile.url)
        let secretsAfter = try Data(contentsOf: rig.secrets.fileURL)
        #expect(configAfter == configBefore)
        #expect(secretsAfter == secretsBefore)
    }

    @Test("Probe: snooze accepts exact boundaries 1 and 240 in --state and importAntigravity refuses unparseable files")
    func probeSnoozeBoundariesOneAndTwoFortyAndImportAntigravityUnparseable() throws {
        let rig = try ScratchRig()
        defer { rig.cleanup() }
        try rig.seedGoldenFixture()

        let tokensURL = rig.agentHome.appendingPathComponent(".gemini/antigravity/mcp_oauth_tokens.json")
        try FileManager.default.createDirectory(at: tokensURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var seam = rig.makeSeam(program: .app)
        seam.antigravityTokensURL = tokensURL

        // Boundary 1 minute -> 2026-11-10T23:16:00Z
        let s1 = HomeSpeakerCommandLine.apply(#"{"contract_version":1,"operations":[{"op":"snooze","minutes":1}]}"#, seam: seam)
        #expect(s1.exitCode == 0)
        let st1 = try #require(JSONSerialization.jsonObject(with: Data(HomeSpeakerCommandLine.state(seam: seam).stdout[0].utf8)) as? [String: Any])
        #expect(st1["snooze_until"] as? String == "2026-11-10T23:16:00Z")

        // Boundary 240 minutes -> 2026-11-11T03:15:00Z
        let s240 = HomeSpeakerCommandLine.apply(#"{"contract_version":1,"operations":[{"op":"snooze","minutes":240}]}"#, seam: seam)
        #expect(s240.exitCode == 0)
        let st240 = try #require(JSONSerialization.jsonObject(with: Data(HomeSpeakerCommandLine.state(seam: seam).stdout[0].utf8)) as? [String: Any])
        #expect(st240["snooze_until"] as? String == "2026-11-11T03:15:00Z")

        // Corrupt JSON token file -> no_antigravity_tokens, secrets.json untouched
        try Data("{not valid json".utf8).write(to: tokensURL)
        let secretsBefore = try Data(contentsOf: rig.secrets.fileURL)
        let badJSONOut = HomeSpeakerCommandLine.apply(#"{"contract_version":1,"operations":[{"op":"importAntigravity"}]}"#, seam: seam)
        #expect(badJSONOut.exitCode == 1)
        let badErr = try #require((JSONSerialization.jsonObject(with: Data(badJSONOut.stdout[0].utf8)) as? [String: Any])?["error"] as? [String: Any])
        #expect(badErr["code"] as? String == "no_antigravity_tokens")
        #expect(try Data(contentsOf: rig.secrets.fileURL) == secretsBefore)

        // Valid JSON missing Google Home MCP entry -> no_antigravity_tokens
        try Data(#"{"https://other.example.com/mcp":{}}"#.utf8).write(to: tokensURL)
        let missingKeyOut = HomeSpeakerCommandLine.apply(#"{"contract_version":1,"operations":[{"op":"importAntigravity"}]}"#, seam: seam)
        #expect(missingKeyOut.exitCode == 1)
        let missingErr = try #require((JSONSerialization.jsonObject(with: Data(missingKeyOut.stdout[0].utf8)) as? [String: Any])?["error"] as? [String: Any])
        #expect(missingErr["code"] as? String == "no_antigravity_tokens")
        #expect(try Data(contentsOf: rig.secrets.fileURL) == secretsBefore)
    }
}
