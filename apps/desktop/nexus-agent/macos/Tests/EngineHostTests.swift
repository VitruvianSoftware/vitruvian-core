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
        var promptHistory: [String] = [] {
            didSet { promptHistoryWrites += 1 }
        }
        var promptHistoryWrites = 0
        var worktreeMode = false
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
        /// Programs the rig says can be run, for the lookups that ask.
        var executables: Set<String> = []
        /// A provider's own command, as the session asked for it to be run,
        /// and the three ways the pretend command talks back.
        var commandRuns: [(path: String, arguments: [String], directory: String, environment: [String: String])] = []
        var commandOutput: (@MainActor @Sendable (Data) -> Void)?
        var commandErrors: (@MainActor @Sendable (Data) -> Void)?
        var commandExit: (@MainActor @Sendable (Int32) -> Void)?
        var commandTerminations = 0
        var commandCannotStart = false
        var listedHidden: [[String]] = []
        /// Every program the engine asked to run for its output, and what
        /// the pretend program prints (nil: it could not be started).
        var programRuns: [(name: String, arguments: [String])] = []
        var programOutput: String?
        /// While true the pretend program does not finish until `finishProgram` is called.
        var holdsProgram = false
        private var heldProgram: CheckedContinuation<Void, Never>?

        func finishProgram() {
            holdsProgram = false
            heldProgram?.resume()
            heldProgram = nil
        }

        /// Lets work queued on the main actor run until `done`, or for about two seconds.
        func wait(until done: () -> Bool) async {
            for _ in 0..<2000 where !done() {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }

        /// Gives work that should NOT happen the time to happen, so a test can see that it did not.
        func settle() async {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

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
                isExecutable: { [unowned self] in executables.contains($0) },
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
                },
                runProgram: { @MainActor [unowned self] name, arguments in
                    programRuns.append((name, arguments))
                    if holdsProgram {
                        await withCheckedContinuation { heldProgram = $0 }
                    }
                    return programOutput
                },
                launchCommand: { [unowned self] path, arguments, directory, environment, onOutput, onErrors, onExit in
                    if commandCannotStart { throw CocoaError(.fileNoSuchFile) }
                    commandRuns.append((path, arguments, directory, environment))
                    commandOutput = onOutput
                    commandErrors = onErrors
                    commandExit = onExit
                    return NexusAgentRunningAgent(terminate: { [unowned self] in commandTerminations += 1 })
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

    // MARK: - Prompt history and worktree mode are kept by the host

    /// Sends with no agent installed: the prompt is recorded and the turn
    /// ends at once, so a test can send many in a row.
    private func send(_ prompt: String, in session: NexusAgentQuickPromptSession) {
        session.send(prompt, configuration: NexusAgentConfiguration(), agentPath: nil)
    }

    func testASessionStartsWithWhatTheHostKept() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        host.promptHistory = ["oldest", "newest"]
        host.worktreeMode = true
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)

        XCTAssertEqual(session.promptHistory, ["oldest", "newest"])
        XCTAssertEqual(session.historyIndex, -1, "no entry is selected until the user presses up")
        XCTAssertTrue(session.worktreeMode)
        XCTAssertEqual(host.promptHistoryWrites, 1, "loading writes nothing back")
    }

    func testASentPromptGoesToTheEndOfTheHistoryAndIsSaved() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)

        send("one", in: session)
        send("  two  ", in: session)
        // Oldest first, newest last: the order the standalone app stores,
        // and the order the up arrow walks back through from the end.
        XCTAssertEqual(session.promptHistory, ["one", "two"])
        XCTAssertEqual(host.promptHistory, ["one", "two"])
        XCTAssertEqual(session.historyIndex, -1)

        // The next launch.
        let later = NexusAgentQuickPromptSession(environment: rig.environment, host: host)
        XCTAssertEqual(later.promptHistory, ["one", "two"])
    }

    func testAPromptAlreadyInTheHistoryIsNotAddedAgain() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        host.promptHistory = ["one", "two"]
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)
        let writes = host.promptHistoryWrites

        // A repeat of the latest, and a repeat of an older one: neither is
        // added, and neither moves to the end.
        send("two", in: session)
        send("one", in: session)
        XCTAssertEqual(session.promptHistory, ["one", "two"])
        XCTAssertEqual(host.promptHistory, ["one", "two"])
        XCTAssertEqual(host.promptHistoryWrites, writes, "nothing changed, so nothing is written")

        // Text that differs only by capitals is a different prompt.
        send("One", in: session)
        XCTAssertEqual(host.promptHistory, ["one", "two", "One"])
    }

    func testOnlyTheLastTwentyPromptsAreKept() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        host.promptHistory = (1...20).map { "p\($0)" }
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)

        send("new", in: session)
        XCTAssertEqual(host.promptHistory.count, 20)
        XCTAssertEqual(host.promptHistory, (2...20).map { "p\($0)" } + ["new"], "the oldest is the one dropped")
        // As in the standalone app, the running chat still has the dropped
        // one until it is closed; only what is saved is cut to twenty.
        XCTAssertEqual(session.promptHistory.count, 21)
        XCTAssertEqual(NexusAgentQuickPromptSession(environment: rig.environment, host: host).promptHistory.count, 20)

        send("newer", in: session)
        XCTAssertEqual(host.promptHistory, (3...20).map { "p\($0)" } + ["new", "newer"])
    }

    func testWorktreeModeIsTheHosts() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)

        XCTAssertFalse(session.worktreeMode)
        session.worktreeMode = true
        XCTAssertTrue(host.worktreeMode, "the choice is remembered by the host, not by the session")
        XCTAssertTrue(NexusAgentQuickPromptSession(environment: rig.environment, host: host).worktreeMode)
        session.worktreeMode = false
        XCTAssertFalse(host.worktreeMode)
    }

    // MARK: - Ollama's model when none is set

    /// What `ollama list` prints: a header row, then one model a row.
    private let ollamaListing = """
        NAME               ID              SIZE      MODIFIED
        llama3.2:latest    a80c4f17acd5    2.0 GB    3 days ago
        qwen3:8b           500a1f067a9f    5.2 GB    2 weeks ago

        """

    func testTheFirstModelOllamaListsIsItsDefault() {
        XCTAssertEqual(NexusAgentSupport.ollamaDefaultModel(fromList: ollamaListing), "llama3.2:latest")
        XCTAssertEqual(NexusAgentSupport.ollamaFallbackModel, "qwen3")

        // Nothing to choose from: the fixed name the standalone app falls back to.
        let fallback = NexusAgentSupport.ollamaFallbackModel
        XCTAssertEqual(NexusAgentSupport.ollamaDefaultModel(fromList: nil), fallback, "ollama could not be run")
        XCTAssertEqual(NexusAgentSupport.ollamaDefaultModel(fromList: ""), fallback, "it printed nothing")
        XCTAssertEqual(NexusAgentSupport.ollamaDefaultModel(
            fromList: "NAME    ID    SIZE    MODIFIED\n"), fallback, "it has no models")
        XCTAssertEqual(NexusAgentSupport.ollamaDefaultModel(
            fromList: "NAME    ID    SIZE    MODIFIED\n\n\nmistral:7b    f974a74358d6    4.1 GB    1 day ago\n"),
                       "mistral:7b", "blank rows before the first model are passed over")
        XCTAssertEqual(NexusAgentSupport.ollamaDefaultModel(fromList: "NAME\nphi3\tabc\n"), "phi3",
                       "a name ends at a tab as well as at a space")
    }

    /// Ported as the standalone app has it, though each looks like a
    /// mistake: the first row is dropped whatever it holds, and a first
    /// model row that begins with a space gives up instead of reading on.
    func testTheOllamaListingIsReadAsTheStandaloneReadsIt() {
        XCTAssertEqual(NexusAgentSupport.ollamaDefaultModel(fromList: "llama3.2:latest a80c\nqwen3:8b 500a\n"),
                       "qwen3:8b", "with no header row the first model is the one passed over")
        XCTAssertEqual(NexusAgentSupport.ollamaDefaultModel(fromList: "NAME ID\n llama3.2:latest a80c\nqwen3:8b 500a\n"),
                       NexusAgentSupport.ollamaFallbackModel,
                       "a row that begins with a space has no name, and the rows after it are not tried")
    }

    func testOllamaArgumentsNeverNameAModelCalledDefault() {
        var configuration = NexusAgentConfiguration(activeProvider: .ollama)
        // The caller looked a model up.
        XCTAssertEqual(Array(NexusAgentSupport.agentArguments(prompt: "hi", configuration: configuration,
                                                              conversationID: nil,
                                                              ollamaDefaultModel: "llama3.2:latest").prefix(5)),
                       ["launch", "claude", "--model", "llama3.2:latest", "--"])
        // The caller did not: the fixed fallback, never the word "default".
        let plain = NexusAgentSupport.agentArguments(prompt: "hi", configuration: configuration, conversationID: nil)
        XCTAssertEqual(Array(plain.prefix(5)), ["launch", "claude", "--model", "qwen3", "--"])
        // A model in the settings always wins, spaces around it removed.
        configuration.model = "  gemma3:4b "
        XCTAssertEqual(Array(NexusAgentSupport.agentArguments(prompt: "hi", configuration: configuration,
                                                              conversationID: nil,
                                                              ollamaDefaultModel: "llama3.2:latest").prefix(5)),
                       ["launch", "claude", "--model", "gemma3:4b", "--"])
    }

    func testOllamaWithNoModelSetRunsTheFirstModelItHas() async {
        let rig = Rig()
        defer { rig.tearDown() }
        rig.programOutput = ollamaListing
        let host = RecordingHost()
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)

        session.send("hi", configuration: NexusAgentConfiguration(activeProvider: .ollama), agentPath: "/fake/ollama")
        XCTAssertTrue(session.isRunning, "the turn has begun while the model is looked up")
        XCTAssertEqual(session.messages.map(\.role), [.user, .agent])
        await rig.wait { !rig.agentRuns.isEmpty }

        XCTAssertEqual(rig.programRuns.map(\.name), ["ollama"])
        XCTAssertEqual(rig.programRuns.first?.arguments, ["list"])
        XCTAssertEqual(rig.agentRuns.count, 1)
        XCTAssertEqual(rig.agentRuns.first?.path, "/fake/ollama")
        XCTAssertEqual(Array((rig.agentRuns.first?.arguments ?? []).prefix(7)),
                       ["launch", "claude", "--model", "llama3.2:latest", "--", "-p", "hi"])

        rig.agentExit?(0)
        session.stopTranscriptFollower()
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(host.finished.count, 1)
    }

    func testOllamaFallsBackWhenItsModelsCannotBeListed() async {
        let rig = Rig()
        defer { rig.tearDown() }
        rig.programOutput = nil
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())

        session.send("hi", configuration: NexusAgentConfiguration(activeProvider: .ollama), agentPath: "/fake/ollama")
        await rig.wait { !rig.agentRuns.isEmpty }

        XCTAssertEqual(rig.programRuns.count, 1)
        XCTAssertEqual(Array((rig.agentRuns.first?.arguments ?? []).prefix(5)),
                       ["launch", "claude", "--model", "qwen3", "--"])
        rig.agentExit?(0)
        session.stopTranscriptFollower()
    }

    func testAModelThatIsSetIsUsedWithoutAskingOllama() {
        let rig = Rig()
        defer { rig.tearDown() }
        rig.programOutput = ollamaListing
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())

        session.send("hi", configuration: NexusAgentConfiguration(model: "gemma3:4b", activeProvider: .ollama),
                     agentPath: "/fake/ollama")
        // No waiting: with nothing to look up the turn starts at once.
        XCTAssertEqual(rig.agentRuns.count, 1)
        XCTAssertEqual(Array((rig.agentRuns.first?.arguments ?? []).prefix(5)),
                       ["launch", "claude", "--model", "gemma3:4b", "--"])
        XCTAssertTrue(rig.programRuns.isEmpty)
        rig.agentExit?(0)
        session.stopTranscriptFollower()
    }

    func testOtherProvidersNeverAskOllama() {
        let rig = Rig()
        defer { rig.tearDown() }
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())

        for provider in [NexusAgentCLIProvider.antigravity, .claude] {
            session.send("hi", configuration: NexusAgentConfiguration(activeProvider: provider), agentPath: "/fake/cli")
            rig.agentExit?(0)
            session.stopTranscriptFollower()
        }
        XCTAssertEqual(rig.agentRuns.count, 2, "each turn started at once")
        XCTAssertTrue(rig.programRuns.isEmpty)
    }

    func testStoppingWhileTheModelIsLookedUpEndsTheTurn() async {
        let rig = Rig()
        defer { rig.tearDown() }
        rig.programOutput = ollamaListing
        rig.holdsProgram = true
        let host = RecordingHost()
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)

        session.send("hi", configuration: NexusAgentConfiguration(activeProvider: .ollama), agentPath: "/fake/ollama")
        await rig.wait { !rig.programRuns.isEmpty }
        XCTAssertTrue(session.isRunning)
        XCTAssertTrue(rig.agentRuns.isEmpty)

        // Nothing is running that could report an exit, so stopping ends the turn itself.
        session.stop()
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.messages.last?.text, host.strings.replyStopped)
        XCTAssertEqual(host.finished.count, 1)

        // The answer arrives late: the stopped turn must not start the agent.
        rig.finishProgram()
        await rig.settle()
        XCTAssertTrue(rig.agentRuns.isEmpty)
        XCTAssertEqual(host.finished.count, 1)

        // And the chat is usable again.
        session.send("again", configuration: NexusAgentConfiguration(model: "m", activeProvider: .ollama),
                     agentPath: "/fake/ollama")
        XCTAssertEqual(rig.agentRuns.count, 1)
        rig.agentExit?(0)
        session.stopTranscriptFollower()
    }

    func testANewChatWhileTheModelIsLookedUpDropsTheTurn() async {
        let rig = Rig()
        defer { rig.tearDown() }
        rig.holdsProgram = true
        let host = RecordingHost()
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)

        session.send("hi", configuration: NexusAgentConfiguration(activeProvider: .ollama), agentPath: "/fake/ollama")
        await rig.wait { !rig.programRuns.isEmpty }
        session.newChat()
        XCTAssertFalse(session.isRunning)
        XCTAssertTrue(session.messages.isEmpty)

        rig.finishProgram()
        await rig.settle()
        XCTAssertTrue(rig.agentRuns.isEmpty, "the dropped turn never starts the agent")
        XCTAssertTrue(session.messages.isEmpty)
        XCTAssertTrue(host.finished.isEmpty, "a turn dropped by New chat is not reported, as before")
    }

    /// Where a program named without a folder is looked for, as the
    /// standalone app's chat looks: the usual install folders first, then
    /// the folders on PATH, the first executable one winning.
    func testAProgramIsFoundWhereTheStandaloneLooks() {
        func find(_ name: String, path: String, executables: Set<String>, files: Set<String> = []) -> String? {
            NexusAgentSupport.executablePath(named: name, pathVariable: path,
                                             isExecutable: { executables.contains($0) },
                                             fileExists: { files.contains($0) })
        }
        let folders = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin",
                       "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        // Each folder is found when it is the only one that has the program…
        for folder in folders {
            XCTAssertEqual(find("ollama", path: "", executables: [folder + "/ollama"]), folder + "/ollama")
        }
        // …and an earlier folder wins over every later one.
        for (index, folder) in folders.enumerated() {
            let present = Set(folders[index...].map { $0 + "/ollama" } + ["/custom/bin/ollama"])
            XCTAssertEqual(find("ollama", path: "/custom/bin", executables: present), folder + "/ollama")
        }
        XCTAssertEqual(find("ollama", path: "/a:/custom/bin:/b", executables: ["/custom/bin/ollama", "/b/ollama"]),
                       "/custom/bin/ollama", "then PATH, in its order")
        XCTAssertNil(find("ollama", path: "/custom/bin", executables: []))
        XCTAssertNil(find("ollama", path: "/custom/bin", executables: [], files: ["/custom/bin/ollama"]),
                     "a file that cannot be run is not the program")
        // A full path is taken as given if something is there, executable or not.
        XCTAssertEqual(find("/opt/x/ollama", path: "", executables: [], files: ["/opt/x/ollama"]), "/opt/x/ollama")
        XCTAssertNil(find("/opt/x/ollama", path: "", executables: ["/opt/x/ollama"]))
    }

    // MARK: - A provider's own command is run as written

    /// A provider the user added: a command with the prompt and model in it.
    private func ownProvider(_ template: String = "llm -m {model} \"{prompt}\"") -> NexusAgentCLIProvider {
        NexusAgentCLIProvider(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-00000000000A")!,
                              name: "My LLM", commandTemplate: template, isBuiltIn: false)
    }

    /// A rig where `llm` is installed in the first folder the lookup tries.
    private func rigWithCommand(_ path: String = "/opt/homebrew/bin/llm") -> Rig {
        let rig = Rig()
        rig.executables = [path]
        return rig
    }

    func testAnOwnProvidersCommandIsRunWithThePromptAsOneArgument() {
        let rig = rigWithCommand()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let engine = NexusAgentEngine(environment: rig.environment, host: host)
        engine.updateActiveProvider(ownProvider())
        var configuration = engine.configuration
        configuration.model = "m1"
        let prompt = "say \"hi\"; $(rm -rf x) && echo `id`\nsecond line {model}"

        // The path handed in is agy's; an own command finds its own program.
        engine.session.send(prompt, configuration: configuration, agentPath: "/fake/agy")

        XCTAssertTrue(rig.agentRuns.isEmpty, "it is not run as agy")
        XCTAssertTrue(rig.programRuns.isEmpty, "and nothing is asked of Ollama")
        XCTAssertEqual(rig.commandRuns.count, 1)
        XCTAssertEqual(rig.commandRuns.first?.path, "/opt/homebrew/bin/llm")
        XCTAssertEqual(rig.commandRuns.first?.arguments, ["-m", "m1", prompt],
                       "three arguments: the prompt is the third, whole and unchanged")
        XCTAssertEqual(rig.commandRuns.first?.directory, rig.home)
        XCTAssertEqual(rig.commandRuns.first?.environment["NO_COLOR"], "1")
        XCTAssertEqual(rig.commandRuns.first?.environment["PATH"], "/usr/bin",
                       "none of the install folders exists in the rig, so PATH is the app's own")
        XCTAssertTrue(engine.session.isRunning)
        XCTAssertEqual(engine.session.messages.first?.text, prompt, "the bubble shows what was typed")

        // It prints plain text, in pieces; the reply grows as they arrive.
        rig.commandOutput?(Data("The answer".utf8))
        XCTAssertEqual(engine.session.messages.last?.text, "The answer")
        rig.commandErrors?(Data("a warning on the side\n".utf8))
        rig.commandOutput?(Data(" is 42.\n\n".utf8))
        XCTAssertTrue(host.finished.isEmpty)
        rig.commandExit?(0)

        XCTAssertFalse(engine.session.isRunning)
        XCTAssertEqual(engine.session.messages.count, 2)
        XCTAssertEqual(engine.session.messages.last?.role, .agent)
        XCTAssertEqual(engine.session.messages.last?.text, "The answer is 42.", "trimmed, and without the warning")
        XCTAssertEqual(engine.session.messages.last?.isError, false)
        XCTAssertEqual(engine.session.messages.last?.modelName, "m1")
        XCTAssertNil(engine.session.lastFailedPrompt)
        XCTAssertEqual(engine.session.elapsedSeconds, 0)
        XCTAssertEqual(host.finished.count, 1, "exactly one report per turn")
        XCTAssertEqual(host.finished.first?.notice.providerName, "My LLM")
        XCTAssertEqual(host.finished.first?.notice.text, "The answer is 42.")
        XCTAssertEqual(host.finished.first?.notice.failed, false)
        XCTAssertEqual(host.finished.first?.notice.endedCleanly, true)
        XCTAssertNil(engine.session.conversationID, "a plain command has no conversation to continue")
    }

    func testOutputSplitInTheMiddleOfALetterIsStillRead() {
        let rig = rigWithCommand()
        defer { rig.tearDown() }
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())
        session.send("hi", configuration: NexusAgentConfiguration(activeProvider: ownProvider()), agentPath: nil)

        let bytes = Array("né 🙂".utf8)
        rig.commandOutput?(Data(bytes[..<2]))
        XCTAssertEqual(session.messages.last?.text, "", "half a letter is not shown; the whole is, once it is whole")
        rig.commandOutput?(Data(bytes[2...]))
        XCTAssertEqual(session.messages.last?.text, "né 🙂")
        rig.commandExit?(0)
        XCTAssertEqual(session.messages.last?.text, "né 🙂")
    }

    func testPlanModeGoesInFrontOfThePromptForAnOwnCommandOnly() {
        let rig = rigWithCommand()
        defer { rig.tearDown() }
        let host = RecordingHost()
        host.planMode = true
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)

        session.send("add a test", configuration: NexusAgentConfiguration(model: "m1", activeProvider: ownProvider()),
                     agentPath: nil)
        XCTAssertEqual(rig.commandRuns.first?.arguments,
                       ["-m", "m1", NexusAgentSupport.planModePrompt("add a test")],
                       "a plain command has no plan flag, so it is told in words, still as one argument")
        XCTAssertEqual(session.messages.first?.text, "add a test", "the bubble shows only what was typed")
        rig.commandOutput?(Data("a plan".utf8))
        rig.commandExit?(0)

        session.send("add a test", configuration: NexusAgentConfiguration(), agentPath: "/fake/agy")
        XCTAssertEqual(rig.agentRuns.first?.arguments.prefix(2).map { $0 }, ["-p", "add a test"],
                       "agy is told with its flag; its prompt is left alone")
        XCTAssertEqual(rig.agentRuns.first?.arguments.contains("plan"), true)
        rig.agentExit?(0)
        session.stopTranscriptFollower()
    }

    func testACommandThatIsNotInstalledSaysSoAndRunsNothing() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)

        session.send("hi", configuration: NexusAgentConfiguration(activeProvider: ownProvider()), agentPath: "/fake/agy")

        XCTAssertTrue(rig.commandRuns.isEmpty)
        XCTAssertTrue(rig.agentRuns.isEmpty, "it does not fall back to agy")
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.messages.count, 2)
        XCTAssertEqual(session.messages.last?.text, "Could not find 'llm' in PATH. Is it installed?")
        XCTAssertEqual(session.messages.last?.isError, true)
        XCTAssertEqual(session.lastFailedPrompt, "hi", "it can be tried again once the program is there")
        XCTAssertTrue(host.finished.isEmpty, "no turn ran, so none is reported")
    }

    func testACommandIsLookedForWhereTheStandaloneLooks() {
        // The same lookup the Ollama model uses, with the rig's files: the
        // install folders in order, then the app's PATH (here /usr/bin).
        for (installed, found) in [(["/usr/bin/llm", "/sbin/llm"], "/usr/bin/llm"),
                                   (["/sbin/llm"], "/sbin/llm"),
                                   (["/usr/local/bin/llm", "/opt/homebrew/sbin/llm"], "/opt/homebrew/sbin/llm")] {
            let rig = Rig()
            defer { rig.tearDown() }
            rig.executables = Set(installed)
            let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())
            session.send("hi", configuration: NexusAgentConfiguration(activeProvider: ownProvider()), agentPath: nil)
            XCTAssertEqual(rig.commandRuns.first?.path, found)
            rig.commandExit?(0)
        }

        // A full path in the template is taken as given when something is there.
        let rig = Rig()
        defer { rig.tearDown() }
        rig.files["/Applications/My Tool/run"] = ""
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())
        session.send("hi", configuration: NexusAgentConfiguration(
            activeProvider: ownProvider("\"/Applications/My Tool/run\" {prompt}")), agentPath: nil)
        XCTAssertEqual(rig.commandRuns.first?.path, "/Applications/My Tool/run")
        XCTAssertEqual(rig.commandRuns.first?.arguments, ["hi"])
        rig.commandExit?(0)
    }

    func testAnEmptyTemplateIsNotRun() {
        let rig = rigWithCommand()
        defer { rig.tearDown() }
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())

        session.send("hi", configuration: NexusAgentConfiguration(activeProvider: ownProvider("  ")), agentPath: "/fake/agy")

        XCTAssertTrue(rig.commandRuns.isEmpty)
        XCTAssertTrue(rig.agentRuns.isEmpty)
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.messages.last?.text, "Invalid command template:   ")
        XCTAssertEqual(session.messages.last?.isError, true)
        XCTAssertEqual(session.lastFailedPrompt, "hi")
    }

    func testACommandThatFailsIsAFailedTurn() {
        let rig = rigWithCommand()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)
        let configuration = NexusAgentConfiguration(activeProvider: ownProvider())

        // It complained and printed no answer: the complaint is the message.
        session.send("one", configuration: configuration, agentPath: nil)
        rig.commandErrors?(Data("Error: model 'm' not found\n".utf8))
        rig.commandExit?(1)
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.messages.last?.text, "Error: model 'm' not found")
        XCTAssertEqual(session.messages.last?.isError, true)
        XCTAssertEqual(session.lastFailedPrompt, "one", "a failed turn can be retried")
        XCTAssertEqual(host.finished.count, 1)
        XCTAssertEqual(host.finished.last?.notice.failed, true)
        XCTAssertEqual(host.finished.last?.notice.endedCleanly, false)
        XCTAssertEqual(host.finished.last?.notice.text, "")

        // It said nothing at all: the exit status is the message.
        session.send("two", configuration: configuration, agentPath: nil)
        rig.commandExit?(3)
        XCTAssertEqual(session.messages.last?.text, "Process exited with code 3")
        XCTAssertEqual(session.messages.last?.isError, true)
        XCTAssertEqual(session.lastFailedPrompt, "two")
        XCTAssertEqual(host.finished.last?.notice.failed, true)

        // It succeeded with nothing to say: the standalone calls that an error too.
        session.send("three", configuration: configuration, agentPath: nil)
        rig.commandErrors?(Data("just a warning".utf8))
        rig.commandExit?(0)
        XCTAssertEqual(session.messages.last?.text, "No output from provider")
        XCTAssertEqual(session.messages.last?.isError, true)
        XCTAssertEqual(session.lastFailedPrompt, "three")
        XCTAssertEqual(host.finished.last?.notice.failed, true)
        XCTAssertEqual(host.finished.last?.notice.endedCleanly, false)

        // It answered and THEN failed: the standalone shows the answer and no error.
        session.send("four", configuration: configuration, agentPath: nil)
        rig.commandOutput?(Data("half an answer\n".utf8))
        rig.commandErrors?(Data("then it broke".utf8))
        rig.commandExit?(2)
        XCTAssertEqual(session.messages.last?.text, "half an answer")
        XCTAssertEqual(session.messages.last?.isError, false)
        XCTAssertNil(session.lastFailedPrompt)
        XCTAssertEqual(host.finished.last?.notice.failed, false)
        XCTAssertEqual(host.finished.last?.notice.endedCleanly, true)
        XCTAssertEqual(host.finished.count, 4, "one report per turn")
        XCTAssertEqual(session.messages.count, 8, "one question and one answer per turn")
    }

    func testACommandThatCannotBeStartedSaysWhy() {
        let rig = rigWithCommand()
        defer { rig.tearDown() }
        rig.commandCannotStart = true
        let host = RecordingHost()
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)

        session.send("hi", configuration: NexusAgentConfiguration(activeProvider: ownProvider()), agentPath: nil)

        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.messages.count, 2)
        XCTAssertEqual(session.messages.last?.text, CocoaError(.fileNoSuchFile).localizedDescription,
                       "the system's own words, as the standalone shows them")
        XCTAssertEqual(session.messages.last?.isError, true)
        XCTAssertEqual(session.lastFailedPrompt, "hi")
        XCTAssertEqual(host.finished.count, 1)
        XCTAssertEqual(host.finished.first?.notice.failed, true)
    }

    func testStoppingAnOwnCommandEndsIt() {
        let rig = rigWithCommand()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)
        let configuration = NexusAgentConfiguration(activeProvider: ownProvider())

        session.send("hi", configuration: configuration, agentPath: nil)
        session.stop()
        XCTAssertEqual(rig.commandTerminations, 1)
        // The signal ends it; the exit arrives as it does from a real one.
        rig.commandExit?(15)
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.messages.last?.text, host.strings.replyStopped)
        XCTAssertEqual(session.messages.last?.isError, false)
        XCTAssertEqual(host.finished.count, 1)
        XCTAssertEqual(host.finished.first?.notice.endedCleanly, false)

        // What had arrived before the stop stays.
        session.send("again", configuration: configuration, agentPath: nil)
        rig.commandOutput?(Data("so far".utf8))
        session.stop()
        rig.commandExit?(15)
        XCTAssertEqual(session.messages.last?.text, "so far")
        XCTAssertEqual(host.finished.count, 2)

        // A turn replaced by a new chat is not heard from again.
        session.send("third", configuration: configuration, agentPath: nil)
        let staleOutput = rig.commandOutput
        let staleExit = rig.commandExit
        session.newChat()
        staleOutput?(Data("late".utf8))
        staleExit?(0)
        XCTAssertTrue(session.messages.isEmpty)
        XCTAssertEqual(host.finished.count, 2)
    }

    func testAnOwnProviderThatStartsWithOllamaIsRunAsOllama() async {
        let rig = Rig()
        defer { rig.tearDown() }
        rig.programOutput = ollamaListing
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())

        // No model is set, so Ollama is asked for one exactly as the
        // built-in Ollama provider asks: the routing and the lookup agree.
        session.send("hi", configuration: NexusAgentConfiguration(
            activeProvider: ownProvider("ollama run {model} {prompt}")), agentPath: "/fake/ollama")
        await rig.wait { !rig.agentRuns.isEmpty }

        XCTAssertTrue(rig.commandRuns.isEmpty, "its template is not run")
        XCTAssertEqual(rig.programRuns.map(\.name), ["ollama"])
        XCTAssertEqual(rig.agentRuns.first?.path, "/fake/ollama")
        XCTAssertEqual(rig.agentRuns.first?.arguments.prefix(5).map { $0 },
                       ["launch", "claude", "--model", "llama3.2:latest", "--"])
        rig.agentExit?(0)
        session.stopTranscriptFollower()
    }

    func testAnOwnProviderThatStartsWithClaudeIsRunAsClaude() {
        let rig = Rig()
        defer { rig.tearDown() }
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())

        session.send("hi", configuration: NexusAgentConfiguration(
            activeProvider: ownProvider("claude --print {prompt}")), agentPath: "/fake/claude")

        XCTAssertTrue(rig.commandRuns.isEmpty)
        XCTAssertTrue(rig.programRuns.isEmpty)
        XCTAssertEqual(rig.agentRuns.first?.arguments, NexusAgentSupport.agentArguments(
            prompt: "hi", configuration: NexusAgentConfiguration(activeProvider: .claude), conversationID: nil))
        rig.agentExit?(0)
        session.stopTranscriptFollower()
    }

    func testAnEditedBuiltInProviderStillRunsItsOwnWay() {
        let rig = rigWithCommand()
        defer { rig.tearDown() }
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())
        var agy = NexusAgentCLIProvider.antigravity
        agy.commandTemplate = "llm {prompt}"

        session.send("hi", configuration: NexusAgentConfiguration(activeProvider: agy), agentPath: "/fake/agy")

        XCTAssertTrue(rig.commandRuns.isEmpty, "the edited template is not run, as in the standalone")
        XCTAssertEqual(rig.agentRuns.first?.path, "/fake/agy")
        XCTAssertEqual(rig.agentRuns.first?.arguments.prefix(4).map { $0 }, ["-p", "hi", "--output-format", "stream-json"])
        rig.agentExit?(0)
        session.stopTranscriptFollower()
    }

    func testTheEngineFindsTheProgramOfTheChosenProvider() {
        let rig = Rig()
        defer { rig.tearDown() }
        rig.executables = ["/usr/local/bin/llm", "/opt/homebrew/bin/ollama", "/Users/rig/.local/bin/claude"]
        let host = RecordingHost()
        host.savedProviders = [ownProvider()]
        let engine = NexusAgentEngine(environment: rig.environment, host: host)

        engine.updateActiveProvider(ownProvider())
        XCTAssertEqual(engine.agentPath, "/usr/local/bin/llm", "an own command: the first word of its template")
        engine.load()
        XCTAssertEqual(engine.agentPath, "/usr/local/bin/llm", "and again after the settings are read")

        engine.updateActiveProvider(ownProvider("missing-tool {prompt}"))
        XCTAssertNil(engine.agentPath, "so the page can say it is not installed")
        engine.updateActiveProvider(ownProvider(""))
        XCTAssertNil(engine.agentPath)

        engine.updateActiveProvider(ownProvider("my-ollama run {model}"))
        XCTAssertEqual(engine.agentPath, "/opt/homebrew/bin/ollama", "run as Ollama, so Ollama is what is looked for")
        engine.updateActiveProvider(ownProvider("claude -p {prompt}"))
        XCTAssertEqual(engine.agentPath, "/Users/rig/.local/bin/claude")
    }

    /// The real launcher, with a harmless real program: `/bin/echo` prints
    /// its arguments back. If the command went through a shell, the `;`,
    /// the `$(…)` and the quotes below would be acted on instead of printed.
    func testTheRealLauncherPassesArgumentsWithoutAShell() async {
        let rig = Rig(realHome: true)
        defer { rig.tearDown() }
        let marker = rig.home + "/made-by-a-shell"
        let hostile = "a  b; touch '\(marker)' $(touch '\(marker)') `touch '\(marker)'` \"q\" $HOME *"
        let heard = Heard()

        _ = try? NexusAgentEngine.Environment.live.launchCommand(
            "/bin/echo", [hostile, "second"], rig.home, ["PATH": "/usr/bin:/bin"],
            { heard.output.append($0) }, { heard.errors.append($0) }, { heard.status = $0 })
        await rig.wait { heard.status != nil }

        XCTAssertEqual(heard.status, 0)
        XCTAssertEqual(String(data: heard.output, encoding: .utf8), hostile + " second\n")
        XCTAssertTrue(heard.errors.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker), "nothing in the prompt was run")
    }

    func testTheRealLauncherKeepsComplaintsApartFromOutput() async {
        let rig = Rig(realHome: true)
        defer { rig.tearDown() }
        let heard = Heard()

        // `ls` of a file that is not there: nothing printed, a complaint, a bad exit.
        _ = try? NexusAgentEngine.Environment.live.launchCommand(
            "/bin/ls", [rig.home + "/not-there"], rig.home, ["PATH": "/usr/bin:/bin"],
            { heard.output.append($0) }, { heard.errors.append($0) }, { heard.status = $0 })
        await rig.wait { heard.status != nil }

        XCTAssertNotNil(heard.status)
        XCTAssertNotEqual(heard.status, 0)
        XCTAssertTrue(heard.output.isEmpty)
        XCTAssertTrue(String(data: heard.errors, encoding: .utf8)?.contains("not-there") == true)
    }

    /// What a real command sent back, gathered on the main actor.
    @MainActor
    private final class Heard {
        var output = Data()
        var errors = Data()
        var status: Int32?
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
