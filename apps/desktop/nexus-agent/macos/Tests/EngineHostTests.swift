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

import XCTest

import NexusAgentCore

/// The shared engine asks the app it runs in for its settings, its text and
/// how the user hears about a turn. These tests give it a host that only
/// records, and an in-memory file system, so nothing real is read, written
/// or launched (apart from the temporary folders two tests need).
@MainActor
final class EngineHostTests: XCTestCase {

    // MARK: - Doubles

    /// A host whose settings are plain values the test can change at any
    /// time, and which remembers what it was told.
    private final class RecordingHost: NexusAgentHost {
        var configuredBotDirectory = ""
        var startsBotAtLaunch = false
        var planMode = false
        var hiddenClaudeSessionIDs: [String] = []
        var chosenProviderID: UUID?
        var savedProviders: [NexusAgentCLIProvider] = []
        var strings = NexusAgentHostStrings()
        var approvals: [NexusAgentTurnNotice] = []
        var finished: [(notice: NexusAgentTurnNotice, isChatVisible: Bool)] = []

        func turnNeedsApproval(_ notice: NexusAgentTurnNotice) { approvals.append(notice) }
        func turnFinished(_ notice: NexusAgentTurnNotice, isChatVisible: Bool) {
            finished.append((notice, isChatVisible))
        }
    }

    /// The engine's outside world, in memory: the same approach as `Rig` in
    /// the Vitruvian tests. `home` is a made-up folder unless a test needs
    /// real files, when it is a temporary one that `tearDown` removes.
    @MainActor
    private final class Rig {
        let domain = "com.vitruviansoftware.nexus-agent.tests.engine-host.\(UUID().uuidString)"
        let defaults: UserDefaults
        let home: String
        let state: String
        let ownsHome: Bool
        var files: [String: String] = [:]
        var agentRuns: [(path: String, arguments: [String], directory: String)] = []
        var agentOutput: (@MainActor @Sendable (Data) -> Void)?
        var agentExit: (@MainActor @Sendable (Int32) -> Void)?
        var listedHidden: [[String]] = []

        init(realHome: Bool = false) {
            defaults = UserDefaults(suiteName: domain)!
            defaults.removePersistentDomain(forName: domain)
            if realHome {
                home = NSTemporaryDirectory() + "nexus-agent-host-tests-\(UUID().uuidString)"
                try? FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
            } else {
                home = "/Users/rig"
            }
            ownsHome = realHome
            state = home + "/Library/Application Support/NexusAgent"
        }

        func tearDown() {
            defaults.removePersistentDomain(forName: domain)
            if ownsHome { try? FileManager.default.removeItem(atPath: home) }
        }

        var defaultBot: String { home + "/.config/nexus-agent" }

        /// Writes a Claude session file where the app's Claude parser looks.
        func writeClaudeSession(id: String, prompt: String) {
            let folder = home + "/.claude/projects/-tmp-nexus-agent-host-tests"
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            let line = #"{"type":"user","message":{"content":"\#(prompt)"}}"# + "\n"
            try? line.write(toFile: folder + "/\(id).jsonl", atomically: true, encoding: .utf8)
        }

        var environment: NexusAgentEngine.Environment {
            NexusAgentEngine.Environment(
                defaults: defaults,
                home: home,
                processEnvironment: ["PATH": "/usr/bin"],
                stateDirectory: state,
                isExecutable: { _ in false },
                fileExists: { [unowned self] in files[$0] != nil },
                readFile: { [unowned self] in files[$0] },
                readTail: { [unowned self] path, _ in files[path] },
                writePrivateFile: { [unowned self] path, content in
                    files[path] = content
                    return true
                },
                removeFile: { [unowned self] in files[$0] = nil },
                isBotProcess: { _ in false },
                signal: { _, _ in },
                launchBot: { _, _, _, _, _ in throw CocoaError(.fileWriteUnknown) },
                schedule: { _, _ in },
                openFile: { _ in },
                launchAgent: { [unowned self] path, arguments, directory, _, onOutput, onExit in
                    agentRuns.append((path, arguments, directory))
                    agentOutput = onOutput
                    agentExit = onExit
                    return NexusAgentRunningAgent(terminate: {})
                },
                // Claude's sessions are read from the files under `home`,
                // with the list the session passes in: that list is what is
                // under test, so it is recorded as well as used.
                listSessions: { [unowned self] directory, provider, hidden in
                    listedHidden.append(hidden)
                    guard provider.id == NexusAgentCLIProvider.claude.id else { return [] }
                    return NexusAgentSessionSummary.parseClaudeSessions(home: home, directory: directory,
                                                                        appHidden: hidden)
                })
        }
    }

    private func claudeConfiguration() -> NexusAgentConfiguration {
        NexusAgentConfiguration(activeProvider: .claude)
    }

    // MARK: - Settings are read from the host, live

    func testBotFolderComesFromTheHost() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let engine = NexusAgentEngine(environment: rig.environment, host: host)

        host.configuredBotDirectory = ""
        XCTAssertEqual(engine.botDirectory, "/Users/rig/.config/nexus-agent")
        XCTAssertEqual(engine.envFilePath, "/Users/rig/.config/nexus-agent/.env")

        // The user edits the setting while the app runs: the same engine
        // follows, so nothing was cached at construction.
        host.configuredBotDirectory = "~/elsewhere"
        XCTAssertEqual(engine.botDirectory, "/Users/rig/elsewhere")
        XCTAssertEqual(engine.envFilePath, "/Users/rig/elsewhere/.env")
    }

    func testEnvFileIsReadFromTheHostsFolder() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        host.configuredBotDirectory = "~/elsewhere"
        // A different token in the standard folder proves the host's folder
        // is the one that was read.
        rig.files[rig.defaultBot + "/.env"] = "TELEGRAM_BOT_TOKEN=9:standard-folder\n"
        rig.files[rig.home + "/elsewhere/.env"] = "TELEGRAM_BOT_TOKEN=1:abc\n"
        let engine = NexusAgentEngine(environment: rig.environment, host: host)

        engine.load()
        XCTAssertEqual(engine.configuration.botToken, "1:abc")

        host.configuredBotDirectory = ""
        engine.load()
        XCTAssertEqual(engine.configuration.botToken, "9:standard-folder")
    }

    func testPlanModeIsTheHosts() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        host.planMode = true
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)

        XCTAssertTrue(session.planMode)
        session.planMode = false
        XCTAssertFalse(host.planMode, "the choice is remembered by the host, not by the session")
        session.planMode = true
        XCTAssertTrue(host.planMode)
    }

    func testStartingWithoutABotReportsTheProblem() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        // The bot is installed in the standard folder only. The host points
        // somewhere else, so if the engine looked in the standard folder
        // (instead of asking the host) it would find a bot and not complain.
        host.configuredBotDirectory = "~/elsewhere"
        rig.files[rig.defaultBot + "/src/bot.js"] = ""
        XCTAssertNil(rig.files[rig.home + "/elsewhere/src/bot.js"])
        let engine = NexusAgentEngine(environment: rig.environment, host: host)

        engine.start()

        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.problem, .missingBot)
    }

    func testStartingAtLaunchIsTheHostsChoice() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let engine = NexusAgentEngine(environment: rig.environment, host: host)

        // With auto-start off the bot is not even tried; with it on the
        // engine tries, and with no bot installed says why.
        engine.startOncePerLaunch()
        XCTAssertNil(engine.problem)

        let optedIn = RecordingHost()
        optedIn.startsBotAtLaunch = true
        let other = NexusAgentEngine(environment: rig.environment, host: optedIn)
        other.startOncePerLaunch()
        XCTAssertEqual(other.problem, .missingBot)
    }

    // MARK: - The chosen provider, and the user's own providers, are the host's

    func testTheActiveProviderIsAntigravityUntilOneIsChosen() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let engine = NexusAgentEngine(environment: rig.environment, host: host)

        XCTAssertEqual(engine.activeProvider, .antigravity)
        engine.load()
        XCTAssertEqual(engine.activeProvider, .antigravity)
        XCTAssertNil(host.chosenProviderID, "reading the choice does not make one")
    }

    func testChoosingAProviderTellsTheHost() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let engine = NexusAgentEngine(environment: rig.environment, host: host)

        engine.updateActiveProvider(.claude)
        XCTAssertEqual(host.chosenProviderID, NexusAgentCLIProvider.claude.id)
        XCTAssertEqual(engine.activeProvider, .claude)

        // The property's setter is the same road.
        engine.activeProvider = .ollama
        XCTAssertEqual(host.chosenProviderID, NexusAgentCLIProvider.ollama.id)
        XCTAssertEqual(engine.configuration.activeProvider, .ollama)
    }

    func testTheChosenProviderSurvivesEveryRereadOfTheFile() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        rig.files[rig.defaultBot] = ""
        rig.files[rig.defaultBot + "/.env"] = "TELEGRAM_BOT_TOKEN=1:abc\n"
        let engine = NexusAgentEngine(environment: rig.environment, host: host)
        engine.updateActiveProvider(.claude)

        engine.load()
        XCTAssertEqual(engine.activeProvider, .claude, "reading the file keeps the choice")
        XCTAssertEqual(engine.configuration.botToken, "1:abc", "and still reads the file")

        var next = engine.configuration
        next.model = "some-model"
        // What a settings page hands back may carry any provider; the host's choice wins.
        next.activeProvider = .antigravity
        XCTAssertTrue(engine.save(next))
        XCTAssertEqual(engine.activeProvider, .claude, "saving keeps the choice")
        XCTAssertEqual(engine.configuration.model, "some-model")
        XCTAssertNil(engine.configuration.botProvider, "the bot's provider is still not read back")

        // Starting reads the file again before it looks for the bot.
        engine.start()
        XCTAssertEqual(engine.problem, .missingBot)
        XCTAssertEqual(engine.activeProvider, .claude, "starting keeps the choice")

        engine.startPolling()
        engine.stopPolling()
        XCTAssertEqual(engine.activeProvider, .claude, "showing the page keeps the choice")

        // The next launch: another engine, the same saved settings.
        let relaunched = NexusAgentEngine(environment: rig.environment, host: host)
        XCTAssertEqual(relaunched.activeProvider, .claude, "a new engine starts on the choice")
        relaunched.load()
        XCTAssertEqual(relaunched.activeProvider, .claude)
    }

    func testAnUnknownChosenProviderFallsBackToAntigravity() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        host.chosenProviderID = UUID(uuidString: "DEADBEEF-0000-0000-0000-000000000000")
        let engine = NexusAgentEngine(environment: rig.environment, host: host)

        XCTAssertEqual(engine.activeProvider, .antigravity)
        engine.load()
        XCTAssertEqual(engine.activeProvider, .antigravity)
    }

    func testAnEditedBuiltInKeepsItsPlace() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        var edited = NexusAgentCLIProvider.claude
        edited.commandTemplate = "claude -p \"{prompt}\" --model {model}"
        host.savedProviders = [edited]
        host.chosenProviderID = edited.id
        let engine = NexusAgentEngine(environment: rig.environment, host: host)

        XCTAssertEqual(engine.providers, [.antigravity, edited, .ollama])
        XCTAssertEqual(engine.activeProvider.commandTemplate, edited.commandTemplate,
                       "the chosen provider is the edited copy, not the built-in")
    }

    func testOwnProvidersComeAfterTheBuiltIns() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let own = NexusAgentCLIProvider(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                                        name: "My script", commandTemplate: "/usr/local/bin/ask {prompt}",
                                        isBuiltIn: false)
        let engine = NexusAgentEngine(environment: rig.environment, host: host)
        XCTAssertEqual(engine.providers, NexusAgentCLIProvider.builtIns, "with nothing saved, the three built in")

        // Read live: the list follows the host without a new engine.
        host.savedProviders = [own]
        XCTAssertEqual(engine.providers, [.antigravity, .claude, .ollama, own])

        engine.updateActiveProvider(own)
        XCTAssertEqual(host.chosenProviderID, own.id)
        engine.load()
        XCTAssertEqual(engine.activeProvider, own, "an own provider is remembered like a built-in")

        // The user deletes it elsewhere: its id is now unknown.
        host.savedProviders = []
        engine.load()
        XCTAssertEqual(engine.activeProvider, .antigravity)
    }

    /// What the standalone app has in its saved settings today, byte for
    /// byte as `JSONEncoder` wrote it from that app's own provider type: one
    /// blob for the built-in providers (all three, edited or not) and one
    /// for the user's own. The shared type must read both and show what
    /// that app's Settings shows.
    func testTheStandalonesStoredProvidersAreRead() throws {
        let builtInBlob = #"""
        [{"id":"00000000-0000-0000-0000-000000000001","name":"Gemini CLI","commandTemplate":"agy -p \"{prompt}\" --effort high","isBuiltIn":true},{"id":"00000000-0000-0000-0000-000000000003","name":"Claude Code","commandTemplate":"claude -p \"{prompt}\"","isBuiltIn":true},{"id":"00000000-0000-0000-0000-000000000002","name":"Ollama (claude)","commandTemplate":"ollama launch claude --model {model} -- -p \"{prompt}\"","isBuiltIn":true}]
        """#
        let customBlob = #"""
        [{"id":"8F2B6C1E-5D0A-4E7B-9C3F-1A2B3C4D5E6F","name":"Local llama","commandTemplate":"llama-cli -m {model} -p \"{prompt}\"","isBuiltIn":false},{"id":"00000000-0000-0000-0000-0000000000AA","name":"Not really built in","commandTemplate":"x","isBuiltIn":true}]
        """#
        let decoder = JSONDecoder()
        let builtIn = try decoder.decode([NexusAgentCLIProvider].self, from: Data(builtInBlob.utf8))
        let custom = try decoder.decode([NexusAgentCLIProvider].self, from: Data(customBlob.utf8))

        var antigravity = NexusAgentCLIProvider.antigravity
        antigravity.commandTemplate = "agy -p \"{prompt}\" --effort high"
        let own = NexusAgentCLIProvider(id: UUID(uuidString: "8F2B6C1E-5D0A-4E7B-9C3F-1A2B3C4D5E6F")!,
                                        name: "Local llama", commandTemplate: "llama-cli -m {model} -p \"{prompt}\"",
                                        isBuiltIn: false)
        // As the standalone's Settings lists them: a built-in keeps today's
        // name and takes only the saved command; an entry marked built-in
        // that is not one of the three is dropped.
        let listed = NexusAgentCLIProvider.available(saved: builtIn + custom)
        XCTAssertEqual(listed, [antigravity, .claude, .ollama, own])
        // That app's choice when none is saved is Antigravity as listed,
        // edited command included; an id it does not know is the built-in.
        XCTAssertEqual(NexusAgentCLIProvider.chosen(id: nil, among: listed), antigravity)
        XCTAssertEqual(NexusAgentCLIProvider.chosen(id: own.id, among: listed), own)
        XCTAssertEqual(NexusAgentCLIProvider.chosen(id: UUID(), among: listed), .antigravity)

        // And written back under the same four names, with the id as the
        // capitals-and-dashes text that app's decoder expects.
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode([own])) as? [[String: Any]]
        XCTAssertEqual(written?.count, 1)
        XCTAssertEqual(written?.first.map { Set($0.keys) }, ["id", "name", "commandTemplate", "isBuiltIn"])
        XCTAssertEqual(written?.first?["id"] as? String, "8F2B6C1E-5D0A-4E7B-9C3F-1A2B3C4D5E6F")
        XCTAssertEqual(written?.first?["isBuiltIn"] as? Bool, false)
        XCTAssertEqual(try decoder.decode([NexusAgentCLIProvider].self, from: JSONEncoder().encode(custom)), custom)
    }

    // MARK: - Archived Claude sessions live in the host

    func testArchivedClaudeSessionsAreKeptByTheHost() {
        // A throwaway home, because archiving a Claude session also looks
        // for VS Code's state under `home`: it must never be the real one.
        let rig = Rig(realHome: true)
        defer { rig.tearDown() }
        let host = RecordingHost()
        let key = "vitruvian.claude.hiddenSessionIds"
        let before = UserDefaults.standard.object(forKey: key) as? [String]
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)
        XCTAssertNil(session.engine, "this is the session built without an engine")
        let summary = NexusAgentSessionSummary(id: "abc-123", title: "t", steps: 1, modified: nil)

        session.archive(summary, configuration: claudeConfiguration())

        XCTAssertEqual(host.hiddenClaudeSessionIDs, ["abc-123"])
        XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? [String], before,
                       "the shared code must not write the Vitruvian app's key")

        session.archive(summary, configuration: claudeConfiguration())
        XCTAssertEqual(host.hiddenClaudeSessionIDs, ["abc-123"], "archiving twice does not list it twice")
        session.unarchive(summary, configuration: claudeConfiguration())
        XCTAssertEqual(host.hiddenClaudeSessionIDs, [])
        XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? [String], before)
    }

    func testAHiddenClaudeSessionComesBackArchived() {
        let rig = Rig(realHome: true)
        defer { rig.tearDown() }
        rig.writeClaudeSession(id: "abc-123", prompt: "hello")
        let host = RecordingHost()
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)

        host.hiddenClaudeSessionIDs = []
        session.refreshSessions(configuration: claudeConfiguration())
        XCTAssertEqual(session.sessions.map(\.id), ["abc-123"], "the fixture session is found")
        XCTAssertEqual(session.sessions.first?.isArchived, false)

        host.hiddenClaudeSessionIDs = ["abc-123"]
        session.refreshSessions(configuration: claudeConfiguration())
        XCTAssertEqual(session.sessions.first?.isArchived, true,
                       "the list is the host's, read at the time of listing")
        XCTAssertEqual(rig.listedHidden.last, ["abc-123"])

        // The drawer takes the same route.
        host.hiddenClaudeSessionIDs = []
        session.toggleSessions(configuration: claudeConfiguration())
        XCTAssertEqual(session.sessions.first?.isArchived, false)
    }

    // MARK: - A turn is reported to the host

    private func finishOneTurn(_ rig: Rig, session: NexusAgentQuickPromptSession,
                               configuration: NexusAgentConfiguration, reply: String, status: Int32) {
        session.send("do it", configuration: configuration, agentPath: "/fake/agy")
        XCTAssertEqual(rig.agentRuns.count, 1)
        let line = #"{"event":"step_update","step_update":{"step_type":"agent_response","text_delta":"\#(reply)"}}"# + "\n"
        rig.agentOutput?(Data(line.utf8))
        rig.agentExit?(status)
        session.stopTranscriptFollower()
    }

    func testAFinishedTurnIsReportedToTheHost() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let engine = NexusAgentEngine(environment: rig.environment, host: host)

        finishOneTurn(rig, session: engine.session, configuration: engine.configuration,
                      reply: "All done.", status: 0)

        XCTAssertEqual(host.finished.count, 1, "exactly one report per turn")
        XCTAssertEqual(host.finished.first?.notice.providerName, NexusAgentCLIProvider.antigravity.name)
        XCTAssertEqual(host.finished.first?.isChatVisible, false,
                       "the base engine has no window, so the chat is never on screen")
        XCTAssertEqual(host.finished.first?.notice.text, "All done.")
        XCTAssertEqual(host.finished.first?.notice.endedCleanly, true)
        XCTAssertEqual(host.finished.first?.notice.failed, false)
        XCTAssertTrue(host.approvals.isEmpty)
    }

    func testAnApprovalIsReportedToTheHost() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let engine = NexusAgentEngine(environment: rig.environment, host: host)

        engine.session.send("do it", configuration: engine.configuration, agentPath: "/fake/agy")
        XCTAssertEqual(rig.agentRuns.count, 1)
        // What Claude Code prints when it starts to use a tool.
        let line = #"{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"tool_use","id":"tool-1","name":"Bash","input":{"command":"ls -la"}}}}"# + "\n"
        rig.agentOutput?(Data(line.utf8))

        // The notice goes out while the turn is still running, not at its end.
        XCTAssertTrue(engine.session.isRunning)
        XCTAssertEqual(host.approvals.count, 1, "exactly one notice for one request")
        XCTAssertEqual(host.approvals.first?.providerName, NexusAgentCLIProvider.antigravity.name)
        XCTAssertEqual(host.approvals.first?.text, "Bash: ls -la")
        XCTAssertEqual(host.approvals.first?.failed, false)
        XCTAssertEqual(host.approvals.first?.endedCleanly, false)
        XCTAssertTrue(host.finished.isEmpty, "the turn has not finished")

        rig.agentExit?(0)
        engine.session.stopTranscriptFollower()
    }

    func testAFailedTurnIsReportedAsFailed() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let engine = NexusAgentEngine(environment: rig.environment, host: host)

        finishOneTurn(rig, session: engine.session, configuration: engine.configuration,
                      reply: "", status: 1)

        XCTAssertEqual(host.finished.count, 1)
        XCTAssertEqual(host.finished.first?.notice.failed, true)
        XCTAssertEqual(host.finished.first?.notice.endedCleanly, false)
    }

    func testASessionWithoutAnEngineReportsAVisibleChat() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)

        finishOneTurn(rig, session: session, configuration: NexusAgentConfiguration(),
                      reply: "ok", status: 0)

        XCTAssertEqual(host.finished.count, 1)
        XCTAssertEqual(host.finished.first?.isChatVisible, true,
                       "with no engine there is no window to be away from")
        XCTAssertEqual(host.finished.first?.notice.providerName, host.strings.fallbackProviderName)
    }

    // MARK: - Text

    func testEveryDefaultTextIsFilledIn() {
        let fields = Mirror(reflecting: NexusAgentHostStrings()).children
        XCTAssertFalse(fields.isEmpty)
        for field in fields {
            guard let value = field.value as? String else {
                XCTFail("\(field.label ?? "?") is not plain text")
                continue
            }
            XCTAssertFalse(value.isEmpty, "\(field.label ?? "?") has no default text")
        }
    }

    func testEveryProblemHasWords() {
        let strings = NexusAgentHostStrings()
        XCTAssertEqual(strings.problemMissingToken, "Add your Telegram bot token in Settings before starting the bot.")
        XCTAssertEqual(strings.problemMissingBot, "The bot is not installed: src/bot.js was not found in the bot folder.")
        XCTAssertEqual(strings.problemMissingNode, "Node.js was not found. Install Node, then start the bot again.")
        XCTAssertEqual(strings.problemStartFailed, "The bot could not be started.")
        XCTAssertEqual(strings.problemSaveFailed, "The settings could not be saved.")
    }

    func testAStartThatCannotHappenSaysWhy() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let engine = NexusAgentEngine(environment: rig.environment, host: host)
        XCTAssertNil(engine.problemDescription, "nothing has gone wrong yet")

        // No bot installed.
        engine.start()
        XCTAssertEqual(engine.problemDescription, host.strings.problemMissingBot)

        // The bot is there but there is no token.
        rig.files[rig.defaultBot + "/src/bot.js"] = ""
        engine.start()
        XCTAssertEqual(engine.problemDescription, host.strings.problemMissingToken)

        // A token, but the rig has no executable Node.
        rig.files[rig.defaultBot + "/.env"] = "TELEGRAM_BOT_TOKEN=1:abc\n"
        engine.start()
        XCTAssertEqual(engine.problemDescription, host.strings.problemMissingNode)

        // The words follow the host's text at the moment they are asked for.
        host.strings.problemMissingNode = "Node fehlt."
        XCTAssertEqual(engine.problemDescription, "Node fehlt.")
    }

    // MARK: - The shared code stays free of any one app

    /// Where the shared sources are on this machine. Bazel runs the test in
    /// a folder of its own, so the sources come from the target's runfiles
    /// (the `shared_sources` data); under SwiftPM or Xcode the test file's
    /// own path leads to them.
    private func sharedSourcesDirectory() -> String? {
        let relative = "apps/desktop/nexus-agent/macos/Sources/NexusAgentCore"
        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append("\(runfiles)/\(workspace)/\(relative)")
            }
        }
        let here = (#filePath as NSString).deletingLastPathComponent
        candidates.append((here as NSString).deletingLastPathComponent + "/Sources/NexusAgentCore")
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func sharedSwiftFiles() -> [(name: String, text: String)] {
        guard let directory = sharedSourcesDirectory() else {
            XCTFail("could not find the NexusAgentCore sources to check")
            return []
        }
        let names = ((try? FileManager.default.subpathsOfDirectory(atPath: directory)) ?? [])
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        let files = names.compactMap { name in
            (try? String(contentsOfFile: directory + "/" + name, encoding: .utf8)).map { (name, $0) }
        }
        // An empty list would let every check below pass without looking.
        XCTAssertFalse(files.isEmpty, "no Swift files found under \(directory)")
        XCTAssertEqual(files.count, names.count, "every source file is readable")
        return files
    }

    func testTheSharedCodeNamesNoAppsKey() {
        let files = sharedSwiftFiles()
        for file in files {
            XCTAssertFalse(file.text.contains("vitruvian."), "\(file.name) names a Vitruvian saved-settings key")
        }
        // The environment still has a `defaults` slot (kept from the code
        // that moved; the live environment fills it with the standard
        // suite). The shared code may hold it, but must not read or write
        // through it: that is how an app's key would creep back in. So the
        // type's name may appear only on the two lines that declare the slot.
        let allowedLines: Set<String> = ["public var defaults: UserDefaults", "public init(defaults: UserDefaults,"]
        for file in files {
            for line in file.text.components(separatedBy: "\n") where line.contains("UserDefaults") {
                XCTAssertTrue(allowedLines.contains(line.trimmingCharacters(in: .whitespaces)),
                              "\(file.name) uses UserDefaults: \(line)")
            }
            XCTAssertFalse(file.text.contains("environment.defaults"), "\(file.name) reads the environment's defaults")
        }
        // The check is looking at the right code: the slot is there.
        XCTAssertTrue(files.contains { $0.text.contains("public var defaults: UserDefaults") })
    }

    func testTheToolsTheEngineShellsOutToExist() {
        // Every absolute path the shared code runs as a subprocess. A lint in
        // the Vitruvian app used to check these names; it cannot any more,
        // because the code lives here.
        var tools = Set<String>()
        let pattern = try! NSRegularExpression(
            pattern: #"executableURL\s*=\s*URL\(fileURLWithPath:\s*"(/[^"]+)"\)"#)
        for file in sharedSwiftFiles() {
            let range = NSRange(file.text.startIndex..., in: file.text)
            for match in pattern.matches(in: file.text, range: range) {
                if let found = Range(match.range(at: 1), in: file.text) { tools.insert(String(file.text[found])) }
            }
        }
        XCTAssertTrue(tools.contains("/usr/bin/sqlite3"), "the scan did not find the sqlite3 call it should")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: "/usr/bin/sqlite3"))
        for tool in tools {
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: tool), "\(tool) is not an executable file")
        }
    }
}
