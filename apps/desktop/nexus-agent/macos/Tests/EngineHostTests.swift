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
/// or launched. The exceptions are a few tests that need the real thing to
/// prove their point, and keep to a temporary folder of their own: Claude's
/// session files, the command launcher run on `/bin/echo` and `/bin/ls`,
/// and deleting from a small SQLite index made for the test.
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
        /// Files that are there but cannot be read (no permission, or
        /// caught in the middle of being rewritten).
        var unreadable: Set<String> = []
        var agentRuns: [(path: String, arguments: [String], directory: String)] = []
        var agentOutput: (@MainActor @Sendable (Data) -> Void)?
        var agentExit: (@MainActor @Sendable (Int32) -> Void)?
        /// While true the agent cannot be started: the launch throws.
        var agentCannotStart = false
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
        /// Every statement the engine asked SQLite to run, the rows the
        /// pretend SQLite gives back to a query, and whether it fails.
        var sqliteRuns: [(database: String, sql: String, readsRows: Bool)] = []
        var sqliteRows = ""
        var sqliteFails = false
        /// When set, a statement that holds this text fails; the rest succeed.
        var sqliteFailsWhenSQLHas: String?
        /// When true the environment also has the SQLite entry that does not
        /// run on the main thread. It records and answers as the other does,
        /// and counts its own runs so a test can tell which one was asked.
        var hasOffMainSqlite = false
        var offMainSqliteRuns = 0
        /// While true a statement given to that entry does not finish until
        /// `finishSqlite` is called, once for each statement, oldest first.
        var holdsSqlite = false
        private var heldSqlite: [CheckedContinuation<Void, Never>] = []

        func finishSqlite() {
            guard !heldSqlite.isEmpty else { return }
            heldSqlite.removeFirst().resume()
        }

        private func sqliteAnswer(_ sql: String, _ readsRows: Bool) -> Data? {
            if sqliteFails { return nil }
            if let marker = sqliteFailsWhenSQLHas, sql.contains(marker) { return nil }
            return Data((readsRows ? sqliteRows : "").utf8)
        }
        /// Every file the engine asked to have removed, in order.
        var removed: [String] = []
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
                readFile: { [unowned self] in unreadable.contains($0) ? nil : files[$0] },
                readTail: { [unowned self] path, _ in files[path] },
                writePrivateFile: { [unowned self] path, content in
                    files[path] = content
                    return true
                },
                removeFile: { [unowned self] in
                    removed.append($0)
                    files[$0] = nil
                },
                isBotProcess: { _ in false },
                signal: { _, _ in },
                launchBot: { _, _, _, _, _ in throw CocoaError(.fileWriteUnknown) },
                schedule: { _, _ in },
                openFile: { _ in },
                launchAgent: { [unowned self] path, arguments, directory, _, onOutput, onExit in
                    if agentCannotStart { throw CocoaError(.fileNoSuchFile) }
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
                },
                runSqlite: { [unowned self] database, sql, readsRows in
                    sqliteRuns.append((database, sql, readsRows))
                    return sqliteAnswer(sql, readsRows)
                },
                runSqliteOffMain: hasOffMainSqlite ? offMainSqlite : nil)
        }

        private var offMainSqlite: @Sendable (String, String, Bool) async -> Data? {
            { @MainActor [unowned self] database, sql, readsRows in
                sqliteRuns.append((database, sql, readsRows))
                offMainSqliteRuns += 1
                if holdsSqlite {
                    await withCheckedContinuation { heldSqlite.append($0) }
                }
                return sqliteAnswer(sql, readsRows)
            }
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

    // MARK: - Settings that cannot be read

    private static let goodEnv = """
        TELEGRAM_BOT_TOKEN=7:good
        ALLOWED_USER_IDS=11,22
        AGY_APPROVAL_MODE=default
        AGY_MODEL=m-good

        """

    /// The four settings a lost file must not take away: without them the
    /// bot is open to anyone and every permission prompt is skipped.
    private func assertHoldsGoodSettings(_ engine: NexusAgentEngine, _ when: String,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let held = engine.configuration
        XCTAssertEqual(held.approvalMode, .standard, "approval mode, \(when)", file: file, line: line)
        XCTAssertEqual(held.botToken, "7:good", "token, \(when)", file: file, line: line)
        XCTAssertEqual(held.allowedUserIDs, "11,22", "whitelist, \(when)", file: file, line: line)
        XCTAssertEqual(held.model, "m-good", "model, \(when)", file: file, line: line)
    }

    /// A settings file that is there but cannot be read, or reads as
    /// blank, says nothing: what was read before is kept. Taking the empty
    /// configuration instead meant approval mode `yolo`, so the chat's next
    /// agy turn skipped every permission prompt.
    func testSettingsThatCannotBeReadKeepTheOnesAlreadyLoaded() {
        let rig = Rig()
        defer { rig.tearDown() }
        let env = rig.defaultBot + "/.env"
        rig.files[env] = Self.goodEnv
        let engine = NexusAgentEngine(environment: rig.environment, host: RecordingHost())
        engine.load()
        assertHoldsGoodSettings(engine, "read from a good file")

        rig.unreadable = [env]
        engine.load()
        assertHoldsGoodSettings(engine, "the file is there but cannot be read")

        rig.unreadable = []
        rig.files[env] = ""
        engine.load()
        assertHoldsGoodSettings(engine, "the file is empty")
        rig.files[env] = "\n  \n\r\n"
        engine.load()
        assertHoldsGoodSettings(engine, "the file is only blank lines")

        // A good file again, with another value: followed.
        rig.files[env] = Self.goodEnv.replacingOccurrences(of: "AGY_MODEL=m-good", with: "AGY_MODEL=m-new")
        engine.load()
        XCTAssertEqual(engine.configuration.model, "m-new")
        XCTAssertEqual(engine.configuration.approvalMode, .standard)
    }

    /// No file at all is not a file that cannot be read: it is a first
    /// launch, or the user removed it, and the bot with no file has no
    /// settings either. The engine holds the empty configuration, as before.
    func testAMissingSettingsFileStillMeansNoSettings() {
        let rig = Rig()
        defer { rig.tearDown() }
        let env = rig.defaultBot + "/.env"
        rig.files[env] = Self.goodEnv
        let engine = NexusAgentEngine(environment: rig.environment, host: RecordingHost())
        engine.load()
        assertHoldsGoodSettings(engine, "read from a good file")

        rig.files[env] = nil
        engine.load()
        XCTAssertEqual(engine.configuration.botToken, "")
        XCTAssertEqual(engine.configuration.allowedUserIDs, "")
        XCTAssertEqual(engine.configuration.model, "")
        XCTAssertEqual(engine.configuration.approvalMode, NexusAgentConfiguration().approvalMode)

        // And once the settings are gone, an unreadable file has nothing
        // to keep: the removed file's settings do not come back.
        rig.files[env] = Self.goodEnv
        rig.unreadable = [env]
        engine.load()
        XCTAssertEqual(engine.configuration.botToken, "")
    }

    /// The very first read has nothing to keep, so a file that cannot be
    /// read, or is blank, gives the empty configuration, as before.
    func testAFirstReadThatFailsHasNothingToKeep() {
        for blank in [false, true] {
            let rig = Rig()
            defer { rig.tearDown() }
            let env = rig.defaultBot + "/.env"
            rig.files[env] = blank ? "\n" : Self.goodEnv
            if !blank { rig.unreadable = [env] }
            let engine = NexusAgentEngine(environment: rig.environment, host: RecordingHost())
            engine.load()
            XCTAssertEqual(engine.configuration.botToken, "", blank ? "blank" : "unreadable")
            XCTAssertEqual(engine.configuration.approvalMode, NexusAgentConfiguration().approvalMode)
        }
    }

    /// What is kept is what THIS file said. When the host points the engine
    /// at another folder whose file cannot be read, the first folder's
    /// token and whitelist are not carried over to it.
    func testSettingsAreNotKeptAcrossFolders() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        rig.files[rig.defaultBot + "/.env"] = Self.goodEnv
        let engine = NexusAgentEngine(environment: rig.environment, host: host)
        engine.load()
        assertHoldsGoodSettings(engine, "read from the standard folder")

        host.configuredBotDirectory = "~/elsewhere"
        rig.files[rig.home + "/elsewhere/.env"] = "TELEGRAM_BOT_TOKEN=1:other\n"
        rig.unreadable = [rig.home + "/elsewhere/.env"]
        engine.load()
        XCTAssertEqual(engine.configuration.botToken, "")
    }

    /// What a save wrote counts as read: the file going unreadable
    /// afterwards does not lose it.
    func testSavedSettingsAreKeptWhenTheFileThenCannotBeRead() {
        let rig = Rig()
        defer { rig.tearDown() }
        let env = rig.defaultBot + "/.env"
        rig.files[rig.defaultBot] = ""
        let engine = NexusAgentEngine(environment: rig.environment, host: RecordingHost())
        engine.load()
        XCTAssertTrue(engine.save(NexusAgentConfiguration(botToken: "7:good", allowedUserIDs: "11,22",
                                                          approvalMode: .standard, model: "m-good")))
        rig.unreadable = [env]
        engine.load()
        assertHoldsGoodSettings(engine, "saved, then the file cannot be read")
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

    /// An edited built-in command is taken only from an entry that is itself
    /// marked built-in, as the standalone reads it from its built-in blob. An
    /// entry that merely carries a built-in's id, but is marked as the user's
    /// own, changes nothing and is not listed a second time.
    func testABuiltInsCommandIsTakenOnlyFromABuiltInEntry() {
        var impostor = NexusAgentCLIProvider.claude
        impostor.commandTemplate = "evil -p \"{prompt}\""
        impostor.isBuiltIn = false
        XCTAssertEqual(NexusAgentCLIProvider.available(saved: [impostor]), NexusAgentCLIProvider.builtIns,
                       "an own entry with a built-in's id leaves the built-in as it is, and is not listed again")

        var edited = NexusAgentCLIProvider.claude
        edited.commandTemplate = "claude -p \"{prompt}\" --model {model}"
        XCTAssertEqual(NexusAgentCLIProvider.available(saved: [impostor, edited]),
                       [.antigravity, edited, .ollama], "the built-in entry still supplies the edit")
        XCTAssertEqual(NexusAgentCLIProvider.available(saved: [edited, impostor]),
                       [.antigravity, edited, .ollama], "whichever comes first")
    }

    /// What the standalone app has in its saved settings today: the same
    /// fields and value shapes its `JSONEncoder` writes from that app's own
    /// provider type (this sample is written by hand, and decoding does not
    /// depend on the order of the keys): one blob for the built-in providers
    /// (all three, edited or not) and one for the user's own. The shared
    /// type must read both and show what that app's Settings shows.
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
    /// standalone app's own chat looked (removed in step 3c; last shipped in
    /// nexus-agent 1.19.0): the usual install folders first, then
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
        XCTAssertEqual(host.finished.map(\.notice.failed), [true],
                       "the turn could not start, and the host is told so once, as of any failed turn")
    }

    /// A command of the user's own that is refused before anything runs:
    /// its program is not installed, its template is empty, or its template
    /// would take the program's name from the prompt. Each says why in an
    /// error bubble, and with the chat out of sight nobody sees a bubble,
    /// so each is a failed turn to the host too, in the bubble's words.
    func testACommandRefusedBeforeItStartsIsAFailedTurn() {
        let refusals: [(why: String, template: String, bubble: String)] = [
            ("the program is not installed", "llm -m {model} \"{prompt}\"",
             "Could not find 'llm' in PATH. Is it installed?"),
            ("the template is empty", "  ", "Invalid command template:   "),
            ("the prompt would name the program", "{prompt} -rf x",
             "Could not find '{prompt}' in PATH. Is it installed?"),
            ("the prompt would be part of the program's name", "my{prompt} x",
             "Could not find 'my{prompt}' in PATH. Is it installed?"),
        ]
        for (why, template, words) in refusals {
            let rig = Rig()
            defer { rig.tearDown() }
            // The program the prompt names is there: it is the template
            // that is refused, not a lookup that failed.
            rig.executables = ["/usr/bin/rm", "/usr/bin/myrm"]
            let host = RecordingHost()
            let engine = NexusAgentEngine(environment: rig.environment, host: host)
            engine.updateActiveProvider(ownProvider(template))

            engine.session.send("rm", configuration: engine.configuration, agentPath: engine.agentPath)

            XCTAssertTrue(rig.commandRuns.isEmpty, why)
            XCTAssertTrue(rig.agentRuns.isEmpty, why)
            XCTAssertFalse(engine.session.isRunning, why)
            let bubble = engine.session.messages.last
            XCTAssertEqual(bubble?.isError, true, why)
            XCTAssertEqual(bubble?.text, words, why)
            XCTAssertEqual(engine.session.lastFailedPrompt, "rm", why)
            XCTAssertEqual(host.finished.count, 1, "\(why): the host is told, once")
            let notice = host.finished.first?.notice
            XCTAssertEqual(notice?.providerName, "My LLM", why)
            XCTAssertEqual(notice?.failed, true, why)
            XCTAssertEqual(notice?.endedCleanly, false, why)
            XCTAssertEqual(notice?.text, "", "\(why): there was no reply")
            XCTAssertEqual(notice?.failureDetail, words, "\(why): the notice carries what the bubble says")
            XCTAssertEqual(announcedOutOfSight(notice),
                           NexusAgentTurnAnnouncement(playsSound: false,
                                                      notificationTitle: "My LLM — Failed",
                                                      notificationBody: words),
                           why)
        }
    }

    /// After a refusal the chat is usable: once the program is installed
    /// the same prompt runs, and that turn is reported as any other.
    func testATurnAfterARefusedCommandIsReportedAsAnyOther() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)
        let configuration = NexusAgentConfiguration(activeProvider: ownProvider("llm {prompt}"))

        session.send("hi", configuration: configuration, agentPath: nil)
        XCTAssertEqual(host.finished.map(\.notice.failed), [true])
        XCTAssertEqual(host.finished.first?.isChatVisible, true,
                       "with no engine there is no window to be away from")

        rig.executables = ["/opt/homebrew/bin/llm"]
        session.send("hi", configuration: configuration, agentPath: nil)
        XCTAssertEqual(rig.commandRuns.count, 1)
        rig.commandOutput?(Data("hello".utf8))
        rig.commandExit?(0)
        XCTAssertEqual(host.finished.map(\.notice.failed), [true, false], "one report per turn")
        XCTAssertNil(host.finished.last?.notice.failureDetail)
        XCTAssertNil(session.lastFailedPrompt)
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

    /// A deliberate departure from the standalone: the prompt may not
    /// become the program's name. It is refused the way a program that is
    /// not installed is, and nothing is launched, even when the prompt names
    /// a program that is installed.
    func testAPromptNamingTheProgramIsRefusedLikeAMissingProgram() {
        let rig = rigWithCommand()
        defer { rig.tearDown() }
        rig.executables.insert("/usr/bin/rm")
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())

        for template in ["{prompt} -rf x", "my{prompt} x"] {
            session.send("rm", configuration: NexusAgentConfiguration(activeProvider: ownProvider(template)),
                         agentPath: "/fake/agy")
            XCTAssertTrue(rig.commandRuns.isEmpty, "nothing is launched for \(template)")
            XCTAssertTrue(rig.agentRuns.isEmpty)
            XCTAssertFalse(session.isRunning)
            XCTAssertTrue(session.messages.last?.text.hasPrefix("Could not find '") == true, template)
            XCTAssertTrue(session.messages.last?.text.hasSuffix("' in PATH. Is it installed?") == true, template)
            XCTAssertEqual(session.messages.last?.isError, true)
            XCTAssertEqual(session.lastFailedPrompt, "rm")
        }

        // The page, too, says there is no program to find.
        let engine = NexusAgentEngine(environment: rig.environment, host: RecordingHost())
        engine.updateActiveProvider(ownProvider("llm {prompt}"))
        XCTAssertEqual(engine.agentPath, "/opt/homebrew/bin/llm")
        engine.updateActiveProvider(ownProvider("{prompt} x"))
        XCTAssertNil(engine.agentPath)

        // A model in the program's name is still the user's own setting.
        let rigWithModelProgram = rigWithCommand("/opt/homebrew/bin/m1")
        defer { rigWithModelProgram.tearDown() }
        let modelSession = NexusAgentQuickPromptSession(environment: rigWithModelProgram.environment, host: RecordingHost())
        modelSession.send("hi", configuration: NexusAgentConfiguration(model: "m1",
                                                                         activeProvider: ownProvider("{model} run {prompt}")),
                          agentPath: nil)
        XCTAssertEqual(rigWithModelProgram.commandRuns.first?.path, "/opt/homebrew/bin/m1")
        XCTAssertEqual(rigWithModelProgram.commandRuns.first?.arguments, ["run", "hi"])
        rigWithModelProgram.commandExit?(0)
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
        XCTAssertEqual(host.finished.last?.notice.failureDetail, "Error: model 'm' not found",
                       "the notice carries the words of the error bubble")
        XCTAssertEqual(announcedOutOfSight(host.finished.last?.notice),
                       NexusAgentTurnAnnouncement(playsSound: false,
                                                  notificationTitle: "Agent — Failed",
                                                  notificationBody: "Error: model 'm' not found"))

        // It said nothing at all: the exit status is the message.
        session.send("two", configuration: configuration, agentPath: nil)
        rig.commandExit?(3)
        XCTAssertEqual(session.messages.last?.text, "Process exited with code 3")
        XCTAssertEqual(session.messages.last?.isError, true)
        XCTAssertEqual(session.lastFailedPrompt, "two")
        XCTAssertEqual(host.finished.last?.notice.failed, true)
        XCTAssertEqual(host.finished.last?.notice.failureDetail, "Process exited with code 3")

        // It succeeded with nothing to say: the standalone calls that an error too.
        session.send("three", configuration: configuration, agentPath: nil)
        rig.commandErrors?(Data("just a warning".utf8))
        rig.commandExit?(0)
        XCTAssertEqual(session.messages.last?.text, "No output from provider")
        XCTAssertEqual(session.messages.last?.isError, true)
        XCTAssertEqual(session.lastFailedPrompt, "three")
        XCTAssertEqual(host.finished.last?.notice.failed, true)
        XCTAssertEqual(host.finished.last?.notice.endedCleanly, false)
        XCTAssertEqual(host.finished.last?.notice.failureDetail, "No output from provider")
        XCTAssertEqual(announcedOutOfSight(host.finished.last?.notice)?.notificationBody, "No output from provider")

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
        XCTAssertNil(host.finished.last?.notice.failureDetail, "no error bubble, so no words for one")
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
        XCTAssertEqual(host.finished.first?.notice.failureDetail, CocoaError(.fileNoSuchFile).localizedDescription,
                       "and the notice carries them")
        XCTAssertEqual(announcedOutOfSight(host.finished.first?.notice)?.notificationBody,
                       CocoaError(.fileNoSuchFile).localizedDescription)
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
        // The user stopped it: nothing failed that has words, and a user
        // who cannot see the chat is not told "Failed".
        XCTAssertNil(host.finished.first?.notice.failureDetail)
        XCTAssertEqual(announcedOutOfSight(host.finished.first?.notice), NexusAgentTurnAnnouncement(playsSound: false))

        // What had arrived before the stop stays.
        session.send("again", configuration: configuration, agentPath: nil)
        rig.commandOutput?(Data("so far".utf8))
        session.stop()
        rig.commandExit?(15)
        XCTAssertEqual(session.messages.last?.text, "so far")
        XCTAssertEqual(host.finished.count, 2)
        XCTAssertEqual(announcedOutOfSight(host.finished.last?.notice),
                       NexusAgentTurnAnnouncement(playsSound: false, notificationTitle: "Agent — Done",
                                                  notificationBody: "so far"))

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

    /// Claude and Ollama are looked for in the shared folders first, in their
    /// order, so every program found before is found at the same path; only
    /// if none is there is the standalone's own lookup tried.
    func testClaudeAndOllamaAreAlsoLookedForWhereTheStandaloneLooks() {
        func find(_ name: String, path: String = "", _ executables: Set<String>) -> String? {
            NexusAgentSupport.locateChatProgram(named: name, environment: ["PATH": path], home: "/Users/rig",
                                                isExecutable: { executables.contains($0) }, fileExists: { _ in false })
        }
        // Only in a folder the standalone adds: found now.
        for folder in ["/opt/homebrew/sbin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"] {
            XCTAssertEqual(find("claude", [folder + "/claude"]), folder + "/claude")
        }
        XCTAssertEqual(find("ollama", path: "/custom/bin", ["/custom/bin/ollama"]), "/custom/bin/ollama", "and PATH")
        // In a shared folder and an extra one: the shared folder, as before.
        XCTAssertEqual(find("claude", ["/usr/bin/claude", "/usr/local/bin/claude"]), "/usr/local/bin/claude")
        XCTAssertEqual(find("claude", ["/opt/homebrew/sbin/claude", "/opt/homebrew/bin/claude"]),
                       "/opt/homebrew/bin/claude")
        XCTAssertEqual(find("claude", path: "/custom/bin", ["/custom/bin/claude", "/usr/local/bin/claude"]),
                       "/usr/local/bin/claude")
        // The shared order is kept even where the standalone's differs.
        XCTAssertEqual(find("claude", ["/opt/homebrew/bin/claude", "/Users/rig/.local/bin/claude"]),
                       "/Users/rig/.local/bin/claude")
        // Nothing anywhere: missing, as before.
        XCTAssertNil(find("claude", path: "/custom/bin", []))
    }

    func testTheEngineFindsClaudeAndOllamaInTheStandalonesExtraFolders() {
        let rig = Rig()
        defer { rig.tearDown() }
        rig.executables = ["/usr/bin/claude", "/opt/homebrew/sbin/ollama"]
        let engine = NexusAgentEngine(environment: rig.environment, host: RecordingHost())

        engine.updateActiveProvider(.claude)
        XCTAssertEqual(engine.agentPath, "/usr/bin/claude")
        engine.updateActiveProvider(.ollama)
        XCTAssertEqual(engine.agentPath, "/opt/homebrew/sbin/ollama")

        rig.executables = ["/usr/bin/claude", "/usr/local/bin/claude"]
        engine.updateActiveProvider(.claude)
        XCTAssertEqual(engine.agentPath, "/usr/local/bin/claude", "a shared folder still wins")
        rig.executables = []
        engine.updateActiveProvider(.claude)
        XCTAssertNil(engine.agentPath, "nothing found is still missing")
        // Antigravity keeps its own lookup: the extra folders are not searched for agy.
        rig.executables = ["/usr/bin/agy"]
        engine.updateActiveProvider(.antigravity)
        XCTAssertNil(engine.agentPath)
    }

    // MARK: - Listing Ollama's models has a time limit

    /// A real but harmless program that runs too long is ended, and the
    /// answer is nil, so the chat falls back to the fixed model name.
    func testAProgramThatRunsTooLongIsEndedAndGivesNothing() async throws {
        let seconds = uniqueSleepSeconds(5, test: 1)
        let started = Date()
        let output = await NexusAgentEngine.runProgram(named: "/bin/sleep", arguments: [seconds], timeLimit: 0.3)
        XCTAssertNil(output)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "it did not wait for the sleep to finish")

        let search = Process()
        search.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        search.arguments = ["-f", "sleep " + seconds]
        search.standardOutput = FileHandle.nullDevice
        try search.run()
        search.waitUntilExit()
        XCTAssertEqual(search.terminationStatus, 1, "no process is left running")
    }

    func testAProgramThatFinishesInTimeGivesItsOutput() async {
        let output = await NexusAgentEngine.runProgram(named: "/bin/echo", arguments: ["hi"], timeLimit: 5)
        XCTAssertEqual(output, "hi\n")
        let defaulted = await NexusAgentEngine.runProgram(named: "/bin/echo", arguments: ["hi"])
        XCTAssertEqual(defaulted, "hi\n", "with the usual limit")
    }

    /// A sleep length of about `seconds` that no other test, no other run of
    /// the suite and no other checkout on this Mac has, so a search for the
    /// process by its command line finds only that test's own. The fraction
    /// is this process's id, a random number and the test's number, always
    /// the same width, so no length is the start of another.
    private func uniqueSleepSeconds(_ seconds: Int, test: Int) -> String {
        let fraction = String(format: "%05d%05d%d", Int(getpid()) % 100_000, Int.random(in: 0..<100_000), test)
        return "\(seconds).\(fraction)"
    }

    /// Whether any process has `marker` in its command line.
    private func processExists(matching marker: String) -> Bool {
        let search = Process()
        search.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        search.arguments = ["-f", marker]
        search.standardOutput = FileHandle.nullDevice
        guard (try? search.run()) != nil else { return false }
        search.waitUntilExit()
        return search.terminationStatus == 0
    }

    /// Waits up to `seconds` for no process to carry `marker` any more.
    private func waitForNoProcess(matching marker: String, seconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while processExists(matching: marker), Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return !processExists(matching: marker)
    }

    /// The limit is a hard one. A program that ignores the polite stop
    /// (SIGTERM) still gives the caller its answer, nil, at the limit; and
    /// it is then killed outright after a short grace, so nothing is left.
    func testAProgramThatIgnoresTheStopStillGivesNothingAtTheLimitAndIsKilled() async {
        let marker = "sleep " + uniqueSleepSeconds(30, test: 2)
        let started = Date()
        let output = await NexusAgentEngine.runProgram(
            named: "/bin/sh", arguments: ["-c", "trap '' TERM; exec \(marker)"], timeLimit: 0.3)
        XCTAssertNil(output)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "the caller did not wait for the program")

        let gone = await waitForNoProcess(matching: marker, seconds: 4)
        if !gone { _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/pkill"), arguments: ["-f", marker]) }
        XCTAssertTrue(gone, "it was killed, not left to run out its 30 seconds")
    }

    /// A grandchild that outlives the program and keeps its output open
    /// must not keep the caller (or the thread reading) waiting either.
    func testAGrandchildHoldingTheOutputOpenDoesNotKeepTheCallerWaiting() async {
        let marker = "sleep " + uniqueSleepSeconds(30, test: 3)
        defer { _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/pkill"), arguments: ["-f", marker]) }
        let started = Date()
        // The shell ends at once; the sleep it started holds the output pipe.
        let output = await NexusAgentEngine.runProgram(
            named: "/bin/sh", arguments: ["-c", "\(marker) & exit 0"], timeLimit: 0.3)
        XCTAssertNil(output)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
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

    // MARK: - Deleting agy conversations

    private func conversation(_ id: String) -> NexusAgentSessionSummary {
        NexusAgentSessionSummary(id: id, title: "T", steps: 1, modified: nil)
    }

    /// A rig with agy's conversation index in the desktop app's folder
    /// and, for each id, the three files agy keeps a conversation in.
    private func rigWithIndex(in folder: String = ".gemini/antigravity", conversations ids: [String] = []) -> Rig {
        let rig = Rig()
        let data = rig.home + "/" + folder
        rig.files[data + "/conversation_summaries.db"] = ""
        for id in ids {
            for suffix in [".db", ".db-wal", ".db-shm"] { rig.files[data + "/conversations/" + id + suffix] = "" }
        }
        return rig
    }

    func testDeletingAConversationRemovesItsRowAndItsThreeFiles() {
        let rig = rigWithIndex(conversations: ["abc-1", "abc-2"])
        defer { rig.tearDown() }
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())
        let data = rig.home + "/.gemini/antigravity"
        let listedBefore = rig.listedHidden.count

        XCTAssertTrue(session.delete(conversation("abc-1"), configuration: NexusAgentConfiguration()))

        XCTAssertEqual(rig.sqliteRuns.count, 1)
        XCTAssertEqual(rig.sqliteRuns.first?.database, data + "/conversation_summaries.db")
        XCTAssertEqual(rig.sqliteRuns.first?.sql, "DELETE FROM conversation_summaries WHERE conversation_id = 'abc-1';")
        XCTAssertEqual(rig.sqliteRuns.first?.readsRows, false)
        XCTAssertEqual(rig.removed, [data + "/conversations/abc-1.db",
                                     data + "/conversations/abc-1.db-wal",
                                     data + "/conversations/abc-1.db-shm"],
                       "its three files, and nothing else")
        XCTAssertNotNil(rig.files[data + "/conversations/abc-2.db"], "the other conversation is untouched")
        XCTAssertNotNil(rig.files[data + "/conversation_summaries.db"])
        XCTAssertEqual(rig.listedHidden.count, listedBefore + 1, "the drawer's list is read again")
    }

    func testAnIdCannotChangeTheStatement() {
        let rig = rigWithIndex()
        defer { rig.tearDown() }
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())

        XCTAssertTrue(session.delete(conversation("it's"), configuration: NexusAgentConfiguration()))
        XCTAssertTrue(session.delete(conversation("x' OR '1'='1"), configuration: NexusAgentConfiguration()))
        XCTAssertTrue(session.delete(conversation("x'; DROP TABLE conversation_summaries; --"),
                                     configuration: NexusAgentConfiguration()))

        XCTAssertEqual(rig.sqliteRuns.map(\.sql), [
            "DELETE FROM conversation_summaries WHERE conversation_id = 'it''s';",
            "DELETE FROM conversation_summaries WHERE conversation_id = 'x'' OR ''1''=''1';",
            "DELETE FROM conversation_summaries WHERE conversation_id = 'x''; DROP TABLE conversation_summaries; --';",
        ], "every quote in the id is doubled, so the id stays inside its quotes")
        XCTAssertEqual(NexusAgentSessionSummary.sqlQuoted("plain"), "'plain'")
        XCTAssertEqual(NexusAgentSessionSummary.sqlQuoted("''"), "''''''")
    }

    func testAnIdThatIsAPathIsRefused() {
        let rig = rigWithIndex()
        defer { rig.tearDown() }
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())

        // The id names files to remove, so one that would leave the
        // conversations folder is not acted on at all. (The standalone has
        // no such check; ids only ever reach it from agy's own index.)
        for id in ["../conversation_summaries", "../../../.ssh/id_ed25519", "a/b", "/etc/passwd", "", ".", ".."] {
            XCTAssertFalse(session.delete(conversation(id), configuration: NexusAgentConfiguration()), id)
        }
        XCTAssertTrue(rig.sqliteRuns.isEmpty)
        XCTAssertTrue(rig.removed.isEmpty)
    }

    /// A control character in an id (a NUL ends a path early in C, a
    /// newline or a tab has no place in a file name) is refused as well.
    func testAnIdWithAControlCharacterIsRefused() {
        let rig = rigWithIndex()
        defer { rig.tearDown() }
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())

        let ids = ["abc\u{0}def", "\u{0}", "abc\n", "abc\ndef", "abc\r", "\tabc", "abc\tdef", "abc\u{1B}[0m",
                   "abc\u{7F}", "abc\u{85}"]
        for id in ids {
            XCTAssertFalse(NexusAgentSessionSummary.isPlainName(id), id.debugDescription)
            XCTAssertFalse(session.delete(conversation(id), configuration: NexusAgentConfiguration()), id.debugDescription)
        }
        XCTAssertTrue(rig.sqliteRuns.isEmpty, "no SQL was run")
        XCTAssertTrue(rig.removed.isEmpty, "and nothing was deleted")
        // Ordinary ids, spaces and non-Latin letters included, are still fine.
        for id in ["abc-1", "a b", "é", "会話-1", "it's"] {
            XCTAssertTrue(NexusAgentSessionSummary.isPlainName(id), id)
        }
    }

    // MARK: - Deleting the conversation that is open

    func testDeletingTheOpenConversationStartsANewChat() {
        let rig = rigWithIndex(conversations: ["open-1", "other-1"])
        defer { rig.tearDown() }
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())
        session.resume(conversation("open-1"))
        defer { session.stopTranscriptFollower() }
        XCTAssertEqual(session.conversationID, "open-1")
        let messages = session.messages
        XCTAssertFalse(messages.isEmpty)

        // Another conversation: the open chat is left as it is.
        XCTAssertTrue(session.delete(conversation("other-1"), configuration: NexusAgentConfiguration()))
        XCTAssertEqual(session.conversationID, "open-1")
        XCTAssertEqual(session.messages, messages)
        XCTAssertEqual(session.mode, .chat)

        // A delete that did not happen leaves it alone too.
        rig.sqliteFails = true
        XCTAssertFalse(session.delete(conversation("open-1"), configuration: NexusAgentConfiguration()))
        XCTAssertEqual(session.conversationID, "open-1")
        rig.sqliteFails = false

        // The open one: the chat is new, so the next prompt cannot resume a conversation that is gone.
        XCTAssertTrue(session.delete(conversation("open-1"), configuration: NexusAgentConfiguration()))
        XCTAssertNil(session.conversationID)
        XCTAssertTrue(session.messages.isEmpty)
        XCTAssertFalse(session.isResumed)
        XCTAssertEqual(session.mode, .compact)
    }

    /// Clears a folder's conversations and waits until that is over.
    private func clearAll(_ session: NexusAgentQuickPromptSession,
                          in configuration: NexusAgentConfiguration) async -> Int {
        await session.deleteAll(in: configuration).value
    }

    func testClearAllStartsANewChatOnlyIfTheOpenConversationWasAmongThem() async {
        let rig = rigWithIndex()
        defer { rig.tearDown() }
        rig.sqliteRows = """
        [{"conversation_id":"open-1","workspace_uris":"[]"},{"conversation_id":"other-1","workspace_uris":"[]"}]
        """
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())
        defer { session.stopTranscriptFollower() }

        // Open, but in no list: untouched.
        session.resume(conversation("elsewhere"))
        let others = await clearAll(session, in: NexusAgentConfiguration())
        XCTAssertEqual(others, 2)
        XCTAssertEqual(session.conversationID, "elsewhere")
        XCTAssertFalse(session.messages.isEmpty)

        // Open and deleted with the rest.
        session.resume(conversation("open-1"))
        let withTheOpenOne = await clearAll(session, in: NexusAgentConfiguration())
        XCTAssertEqual(withTheOpenOne, 2)
        XCTAssertNil(session.conversationID)
        XCTAssertTrue(session.messages.isEmpty)

        // Open and in the list, but nothing could be deleted: it stays.
        session.resume(conversation("open-1"))
        rig.sqliteFails = true
        let none = await clearAll(session, in: NexusAgentConfiguration())
        XCTAssertEqual(none, 0)
        XCTAssertEqual(session.conversationID, "open-1")
        XCTAssertFalse(session.messages.isEmpty)
        rig.sqliteFails = false
    }

    func testOnlyAgyConversationsCanBeDeleted() async {
        let rig = rigWithIndex(conversations: ["abc-1"])
        defer { rig.tearDown() }
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())
        let own = NexusAgentCLIProvider(id: UUID(), name: "Mine", commandTemplate: "agy -p {prompt}", isBuiltIn: false)

        for provider in [NexusAgentCLIProvider.claude, .ollama, own] {
            let configuration = NexusAgentConfiguration(activeProvider: provider)
            XCTAssertFalse(session.delete(conversation("abc-1"), configuration: configuration), provider.name)
            let cleared = await clearAll(session, in: configuration)
            XCTAssertEqual(cleared, 0, provider.name)
        }
        XCTAssertTrue(rig.sqliteRuns.isEmpty, "nothing was asked of the index")
        XCTAssertTrue(rig.removed.isEmpty, "and no file was removed")
    }

    func testNothingIsRemovedWhenTheIndexCannotBeChanged() async {
        // No index at all.
        let bare = Rig()
        defer { bare.tearDown() }
        let onBare = NexusAgentQuickPromptSession(environment: bare.environment, host: RecordingHost())
        XCTAssertFalse(onBare.delete(conversation("abc-1"), configuration: NexusAgentConfiguration()))
        let cleared = await clearAll(onBare, in: NexusAgentConfiguration())
        XCTAssertEqual(cleared, 0)
        XCTAssertTrue(bare.sqliteRuns.isEmpty, "SQLite is not run on a file that is not there: it would create one")
        XCTAssertTrue(bare.removed.isEmpty)

        // An index SQLite cannot change: the row stays, so its files stay.
        let rig = rigWithIndex(conversations: ["abc-1"])
        defer { rig.tearDown() }
        rig.sqliteFails = true
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())
        XCTAssertFalse(session.delete(conversation("abc-1"), configuration: NexusAgentConfiguration()))
        XCTAssertEqual(rig.sqliteRuns.count, 1)
        XCTAssertTrue(rig.removed.isEmpty)
    }

    func testFilesAreRemovedBesideTheIndexThatWasChanged() {
        // Only the CLI's own folder has an index: that is the one used,
        // and the files are looked for beside it.
        let rig = rigWithIndex(in: ".gemini/antigravity-cli", conversations: ["abc-1"])
        defer { rig.tearDown() }
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())
        let data = rig.home + "/.gemini/antigravity-cli"

        XCTAssertTrue(session.delete(conversation("abc-1"), configuration: NexusAgentConfiguration()))
        XCTAssertEqual(rig.sqliteRuns.first?.database, data + "/conversation_summaries.db")
        XCTAssertEqual(rig.removed.first, data + "/conversations/abc-1.db")

        // Both have one: the desktop app's comes first, as it does for the list.
        rig.files[rig.home + "/.gemini/antigravity/conversation_summaries.db"] = ""
        XCTAssertTrue(session.delete(conversation("abc-2"), configuration: NexusAgentConfiguration()))
        XCTAssertEqual(rig.sqliteRuns.last?.database, rig.home + "/.gemini/antigravity/conversation_summaries.db")
        XCTAssertEqual(rig.removed.last, rig.home + "/.gemini/antigravity/conversations/abc-2.db-shm")
    }

    /// What the standalone's "Clear All" reads before it deletes.
    private let clearAllQuery = "SELECT conversation_id, title, preview, step_count, last_modified_time, workspace_uris\n"
        + "FROM conversation_summaries\n"
        + "WHERE nesting_depth = 0 AND killed = 0\n"
        + "ORDER BY last_modified_time DESC LIMIT 200;"

    func testClearAllDeletesTheFoldersOwnConversationsOneByOne() async {
        let rig = rigWithIndex()
        defer { rig.tearDown() }
        rig.files[rig.home + "/work"] = ""
        // What SQLite gives back for the query: it has already left out the
        // nested and the aborted ones, so the folder is all that is left to check.
        rig.sqliteRows = """
        [{"conversation_id":"here-1","workspace_uris":"[\\"file:///Users/rig/work\\"]"},
         {"conversation_id":"elsewhere","workspace_uris":"[\\"file:///Users/rig/other\\"]"},
         {"conversation_id":"inside","workspace_uris":"[\\"file:///Users/rig/work/sub\\"]"},
         {"conversation_id":"above","workspace_uris":"[\\"file:///Users/rig\\"]"},
         {"conversation_id":"both","workspace_uris":"[\\"file:///Users/rig/other\\",\\"file:///Users/rig/work\\"]"},
         {"conversation_id":"nowhere","workspace_uris":"[]"},
         {"conversation_id":"unreadable","workspace_uris":"not json"},
         {"conversation_id":"","workspace_uris":"[]"},
         {"conversation_id":"it's","workspace_uris":"[\\"file:///Users/rig/work\\"]"}]
        """
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())
        let listedBefore = rig.listedHidden.count

        let count = await clearAll(session, in: NexusAgentConfiguration(workingDirectory: "~/work/"))

        XCTAssertEqual(rig.sqliteRuns.first?.sql, clearAllQuery, "the standalone's own query")
        XCTAssertEqual(rig.sqliteRuns.first?.readsRows, true)
        let deleted = ["here-1", "both", "nowhere", "unreadable", "it's"]
        XCTAssertEqual(count, deleted.count)
        XCTAssertEqual(rig.sqliteRuns.dropFirst().map(\.sql), deleted.map {
            "DELETE FROM conversation_summaries WHERE conversation_id = \(NexusAgentSessionSummary.sqlQuoted($0));"
        }, "the folder's own, and those with no folder recorded; not another folder's, not one inside or above it")
        XCTAssertTrue(rig.sqliteRuns.dropFirst().allSatisfy { !$0.readsRows })
        XCTAssertEqual(rig.removed.count, deleted.count * 3)
        XCTAssertEqual(rig.listedHidden.count, listedBefore + 1, "the drawer's list is read again, once")
    }

    /// With the index locked every try waits out the busy timeout on the
    /// main thread, so the first delete that fails ends the run.
    func testClearAllStopsAtTheFirstDeleteThatFails() async {
        let rig = rigWithIndex(conversations: ["c-1", "c-2", "c-3", "c-4"])
        defer { rig.tearDown() }
        rig.sqliteRows = """
        [{"conversation_id":"c-1","workspace_uris":"[]"},{"conversation_id":"c-2","workspace_uris":"[]"},
         {"conversation_id":"c-3","workspace_uris":"[]"},{"conversation_id":"c-4","workspace_uris":"[]"}]
        """
        rig.sqliteFailsWhenSQLHas = "'c-2'"
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())
        let data = rig.home + "/.gemini/antigravity/conversations/"

        let count = await clearAll(session, in: NexusAgentConfiguration())

        XCTAssertEqual(count, 1, "only the one before the failure is counted")
        XCTAssertEqual(rig.sqliteRuns.dropFirst().map(\.sql), [
            "DELETE FROM conversation_summaries WHERE conversation_id = 'c-1';",
            "DELETE FROM conversation_summaries WHERE conversation_id = 'c-2';",
        ], "no delete was tried after the one that failed")
        XCTAssertEqual(rig.removed, [data + "c-1.db", data + "c-1.db-wal", data + "c-1.db-shm"],
                       "the first one's files went; nothing else was removed")
        XCTAssertNotNil(rig.files[data + "c-2.db"])
        XCTAssertNotNil(rig.files[data + "c-3.db"])
    }

    func testClearAllWithNoFolderSetIsTheHomeFolders() async {
        let rig = rigWithIndex()
        defer { rig.tearDown() }
        rig.sqliteRows = """
        [{"conversation_id":"home-1","workspace_uris":"[\\"file:///Users/rig\\"]"},
         {"conversation_id":"work-1","workspace_uris":"[\\"file:///Users/rig/work\\"]"}]
        """
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())

        // The drawer lists every folder's conversations when none is set;
        // "all" still means one folder's, as it does in the standalone.
        let atHome = await clearAll(session, in: NexusAgentConfiguration())
        XCTAssertEqual(atHome, 1)
        XCTAssertEqual(rig.sqliteRuns.last?.sql,
                       "DELETE FROM conversation_summaries WHERE conversation_id = 'home-1';")

        // A folder that is set but gone is still that folder, not home.
        rig.sqliteRuns = []
        let atWork = await clearAll(session, in: NexusAgentConfiguration(workingDirectory: "/Users/rig/work"))
        XCTAssertEqual(atWork, 1)
        XCTAssertEqual(rig.sqliteRuns.last?.sql,
                       "DELETE FROM conversation_summaries WHERE conversation_id = 'work-1';")
    }

    // MARK: Clear All does not hold up the main thread

    private func fourConversations() -> Rig {
        let rig = rigWithIndex(conversations: ["c-1", "c-2", "c-3", "c-4"])
        rig.sqliteRows = """
        [{"conversation_id":"c-1","workspace_uris":"[]"},{"conversation_id":"c-2","workspace_uris":"[]"},
         {"conversation_id":"c-3","workspace_uris":"[]"},{"conversation_id":"c-4","workspace_uris":"[]"}]
        """
        rig.hasOffMainSqlite = true
        return rig
    }

    private func deleteOf(_ id: String) -> String {
        "DELETE FROM conversation_summaries WHERE conversation_id = '\(id)';"
    }

    /// Clear All can be 200 runs of `sqlite3`, each of which may wait two
    /// seconds on a locked index. The call that starts it comes back at
    /// once, with nothing deleted yet, and the session says it is busy.
    func testClearAllComesBackBeforeAnythingIsDeleted() async {
        let rig = fourConversations()
        defer { rig.tearDown() }
        rig.holdsSqlite = true
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())
        let listedBefore = rig.listedHidden.count
        let data = rig.home + "/.gemini/antigravity/conversations/"
        XCTAssertFalse(session.isClearingSessions)

        let clearing = session.deleteAll(in: NexusAgentConfiguration())

        // Back with the caller, on the main actor, and SQLite has not even been asked.
        XCTAssertTrue(session.isClearingSessions, "the session says a clear is under way")
        XCTAssertTrue(rig.sqliteRuns.isEmpty, "the call came back before any statement was run")
        XCTAssertTrue(rig.removed.isEmpty)

        // The query is asked for, and held: the main actor is free meanwhile
        // (this test is running on it), and still nothing is deleted.
        await rig.wait { rig.sqliteRuns.count == 1 }
        XCTAssertEqual(rig.sqliteRuns.map(\.sql), [clearAllQuery])
        XCTAssertTrue(rig.removed.isEmpty)
        XCTAssertTrue(session.isClearingSessions)

        // The deletes come one at a time, in the list's order, each one's
        // files removed only once its row is out.
        for (index, id) in ["c-1", "c-2", "c-3", "c-4"].enumerated() {
            rig.finishSqlite()
            await rig.wait { rig.sqliteRuns.count == index + 2 }
            XCTAssertEqual(rig.sqliteRuns.last?.sql, deleteOf(id))
            XCTAssertEqual(rig.removed.count, index * 3, "\(id) is still there while its delete is running")
            XCTAssertTrue(session.isClearingSessions)
            XCTAssertEqual(rig.listedHidden.count, listedBefore, "the list is not read again until the end")
        }
        rig.finishSqlite()
        let count = await clearing.value

        XCTAssertEqual(count, 4)
        XCTAssertEqual(rig.sqliteRuns.count, 5, "the query and four deletes, and no more")
        XCTAssertEqual(rig.offMainSqliteRuns, 5, "every one through the entry that is off the main thread")
        XCTAssertEqual(rig.removed.count, 12)
        XCTAssertEqual(Array(rig.removed.prefix(3)), [data + "c-1.db", data + "c-1.db-wal", data + "c-1.db-shm"])
        XCTAssertFalse(session.isClearingSessions, "and the session is no longer busy")
        XCTAssertEqual(rig.listedHidden.count, listedBefore + 1, "the drawer's list is read again, once")
    }

    func testASecondClearAllWhileOneIsRunningDoesNothing() async {
        let rig = fourConversations()
        defer { rig.tearDown() }
        rig.holdsSqlite = true
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())
        let listedBefore = rig.listedHidden.count

        let first = session.deleteAll(in: NexusAgentConfiguration())
        await rig.wait { rig.sqliteRuns.count == 1 }
        let second = session.deleteAll(in: NexusAgentConfiguration())
        let secondCount = await second.value
        await rig.settle()

        XCTAssertEqual(secondCount, 0, "the second one deleted nothing")
        XCTAssertEqual(rig.sqliteRuns.count, 1, "and asked nothing of the index")
        XCTAssertTrue(session.isClearingSessions, "the first is still under way")
        XCTAssertEqual(rig.listedHidden.count, listedBefore)

        rig.holdsSqlite = false
        rig.finishSqlite()
        let firstCount = await first.value
        XCTAssertEqual(firstCount, 4)
        XCTAssertEqual(rig.sqliteRuns.count, 5, "the first ran once through, undisturbed")
        XCTAssertFalse(session.isClearingSessions)

        // Once it is over, Clear All can be asked for again.
        let third = await clearAll(session, in: NexusAgentConfiguration())
        XCTAssertEqual(third, 4)
        XCTAssertEqual(rig.listedHidden.count, listedBefore + 2)
    }

    func testClearAllOffTheMainThreadStillStopsAtTheFirstFailure() async {
        let rig = fourConversations()
        defer { rig.tearDown() }
        rig.sqliteFailsWhenSQLHas = "'c-2'"
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())
        let data = rig.home + "/.gemini/antigravity/conversations/"

        let count = await clearAll(session, in: NexusAgentConfiguration())

        XCTAssertEqual(count, 1, "only the one before the failure is counted")
        XCTAssertEqual(rig.sqliteRuns.dropFirst().map(\.sql), [deleteOf("c-1"), deleteOf("c-2")],
                       "no delete was tried after the one that failed")
        XCTAssertEqual(rig.offMainSqliteRuns, 3)
        XCTAssertEqual(rig.removed, [data + "c-1.db", data + "c-1.db-wal", data + "c-1.db-shm"])
        XCTAssertNotNil(rig.files[data + "c-2.db"])
        XCTAssertFalse(session.isClearingSessions, "a clear that failed is over too")

        // A query that fails deletes nothing, and is over as well.
        rig.sqliteFailsWhenSQLHas = nil
        rig.sqliteFails = true
        let nothing = await clearAll(session, in: NexusAgentConfiguration())
        XCTAssertEqual(nothing, 0)
        XCTAssertFalse(session.isClearingSessions)
    }

    func testClearAllOffTheMainThreadStartsANewChatIfTheOpenConversationWent() async {
        let rig = fourConversations()
        defer { rig.tearDown() }
        rig.holdsSqlite = true
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())
        defer { session.stopTranscriptFollower() }
        session.resume(conversation("c-3"))

        let clearing = session.deleteAll(in: NexusAgentConfiguration())
        await rig.wait { rig.sqliteRuns.count == 1 }
        XCTAssertEqual(session.conversationID, "c-3", "the open chat is left alone while the clear runs")
        XCTAssertFalse(session.messages.isEmpty)

        rig.holdsSqlite = false
        rig.finishSqlite()
        let count = await clearing.value

        XCTAssertEqual(count, 4)
        XCTAssertNil(session.conversationID, "the next prompt cannot resume a conversation that is gone")
        XCTAssertTrue(session.messages.isEmpty)
        XCTAssertEqual(session.mode, .compact)
    }

    /// An environment without the off-main entry (every test double written
    /// before it) still clears, through the entry it has.
    func testClearAllUsesThePlainEntryWhenThereIsNoOther() async {
        let rig = fourConversations()
        defer { rig.tearDown() }
        rig.hasOffMainSqlite = false
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())

        let clearing = session.deleteAll(in: NexusAgentConfiguration())
        XCTAssertTrue(rig.sqliteRuns.isEmpty, "even so, the call comes back first")
        let count = await clearing.value

        XCTAssertEqual(count, 4)
        XCTAssertEqual(rig.sqliteRuns.count, 5)
        XCTAssertEqual(rig.offMainSqliteRuns, 0)
    }

    /// An environment without the off-main entry clears on the main thread,
    /// one two-second wait after another. The one both apps run with must
    /// have it.
    func testTheRealEnvironmentHasTheOffMainEntry() {
        XCTAssertNotNil(NexusAgentEngine.Environment.live.runSqliteOffMain,
                        "without it Clear All freezes the app while it runs")
    }

    /// The real entry, on a real index: it answers as the plain one does,
    /// and from a thread that is not the main one.
    func testTheRealOffMainEntryReadsARealIndex() async throws {
        let rig = Rig(realHome: true)
        defer { rig.tearDown() }
        let index = try realIndex(rig)
        let entry = try XCTUnwrap(NexusAgentEngine.Environment.live.runSqliteOffMain,
                                  "the real environment has the off-main entry")

        let rows = await entry(index.database, "SELECT conversation_id FROM conversation_summaries;", true)

        let text = String(data: try XCTUnwrap(rows), encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("busy-1"), text)
        let missing = await entry(rig.home + "/no-such-folder/x.db", "SELECT 1;", true)
        XCTAssertNil(missing, "a statement that fails gives nil, as the plain entry does")
        let onMain = await NexusAgentEngine.offMainThread { Thread.isMainThread }
        XCTAssertFalse(onMain, "the work it is given does not run on the main thread")
    }

    /// Runs SQL against a real database file, for the test below.
    private func sqlite(_ database: String, _ sql: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database, sql]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "could not run sqlite3" }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// The whole road, for real: the engine's own SQLite and file calls
    /// against a small index in a throwaway home folder. Nothing outside
    /// that folder is named anywhere in it.
    func testDeletingAgainstARealIndexInAThrowawayHome() async throws {
        let rig = Rig(realHome: true)
        defer { rig.tearDown() }
        let files = FileManager.default
        let data = rig.home + "/.gemini/antigravity"
        let conversations = data + "/conversations"
        let database = data + "/conversation_summaries.db"
        try files.createDirectory(atPath: conversations, withIntermediateDirectories: true)
        try files.createDirectory(atPath: data + "/annotations", withIntermediateDirectories: true)
        let work = rig.home + "/work"
        try files.createDirectory(atPath: work, withIntermediateDirectories: true)
        // The folder as the engine will name it: /var is a link on macOS.
        let workURI = "file://" + URL(fileURLWithPath: work).standardizedFileURL.path

        // (id, folder, nesting depth, killed)
        let rows: [(String, String, Int, Int)] = [
            ("top-1", "[\"\(workURI)\"]", 0, 0),
            ("top-2", "[\"\(workURI)\"]", 0, 0),
            ("it's", "[\"\(workURI)\"]", 0, 0),
            ("nested", "[\"\(workURI)\"]", 1, 0),
            ("aborted", "[\"\(workURI)\"]", 0, 1),
            ("archived", "[\"\(workURI)\"]", 0, 0),
            ("other-folder", "[\"file:///somewhere/else\"]", 0, 0),
            ("no-folder", "[]", 0, 0),
            ("single", "[\"file:///somewhere/else\"]", 0, 0),
        ]
        var setup = "CREATE TABLE conversation_summaries (conversation_id TEXT PRIMARY KEY, title TEXT, preview TEXT, "
            + "step_count INTEGER, last_modified_time TEXT, workspace_uris TEXT, nesting_depth INTEGER, killed INTEGER);"
        for (index, row) in rows.enumerated() {
            setup += "INSERT INTO conversation_summaries VALUES (\(NexusAgentSessionSummary.sqlQuoted(row.0)), 'T', 'P', 1, "
                + "'2026-10-0\(index + 1)T10:00:00Z', \(NexusAgentSessionSummary.sqlQuoted(row.1)), \(row.2), \(row.3));"
            for suffix in [".db", ".db-wal", ".db-shm"] {
                files.createFile(atPath: conversations + "/" + row.0 + suffix, contents: Data("x".utf8))
            }
        }
        XCTAssertEqual(sqlite(database, setup), "")
        try "archived:true archival_status_timestamp:{seconds:1 nanos:2}"
            .write(toFile: data + "/annotations/archived.pbtxt", atomically: true, encoding: .utf8)
        // Files that must outlive everything below.
        let bystanders = [rig.home + "/keep.txt", work + "/keep.txt", data + "/annotations/top-1.pbtxt",
                          conversations + "/top-1.db.bak", rig.home + "/single.db"]
        for path in bystanders { files.createFile(atPath: path, contents: Data("x".utf8)) }

        func remaining() -> [String] {
            sqlite(database, "SELECT conversation_id FROM conversation_summaries ORDER BY conversation_id;")
                .split(separator: "\n").map(String.init)
        }
        func conversationFiles() -> [String] {
            ((try? files.contentsOfDirectory(atPath: conversations)) ?? []).sorted()
        }
        XCTAssertEqual(remaining().count, rows.count, "the index was built")

        // The real SQLite and file calls, in the throwaway home. The real
        // session list is left out: it is not what is under test here.
        var environment = NexusAgentEngine.Environment.live
        environment.home = rig.home
        environment.listSessions = { _, _, _ in [] }
        let session = NexusAgentQuickPromptSession(environment: environment, host: RecordingHost())

        // One conversation.
        XCTAssertTrue(session.delete(conversation("single"), configuration: NexusAgentConfiguration()))
        XCTAssertEqual(remaining(), ["aborted", "archived", "it's", "nested", "no-folder", "other-folder",
                                     "top-1", "top-2"], "one row is gone, the rest are there")
        XCTAssertFalse(conversationFiles().contains { $0.hasPrefix("single") })
        XCTAssertEqual(conversationFiles().count, (rows.count - 1) * 3 + 1)

        // An id that tries to be more than an id deletes nothing.
        XCTAssertTrue(session.delete(conversation("x' OR '1'='1"), configuration: NexusAgentConfiguration()))
        XCTAssertFalse(session.delete(conversation("../../keep"), configuration: NexusAgentConfiguration()))
        XCTAssertEqual(remaining().count, rows.count - 1)

        // All of one folder's.
        let count = await clearAll(session, in: NexusAgentConfiguration(workingDirectory: work))
        XCTAssertEqual(count, 4)
        XCTAssertEqual(remaining(), ["aborted", "archived", "nested", "other-folder"],
                       "gone: the folder's top-level ones (one with a quote in its id) and the one with no folder. "
                        + "Kept: another folder's, a nested one, an aborted one, an archived one")
        XCTAssertEqual(conversationFiles(), (["aborted", "archived", "nested", "other-folder"].flatMap { id in
            [".db", ".db-shm", ".db-wal"].map { id + $0 }
        } + ["top-1.db.bak"]).sorted())

        for path in bystanders {
            XCTAssertTrue(files.fileExists(atPath: path), "\(path) was not the engine's to remove")
        }
        XCTAssertTrue(files.fileExists(atPath: database))
        XCTAssertTrue(files.fileExists(atPath: data + "/annotations/archived.pbtxt"))
    }

    // MARK: A busy index

    /// Runs `sqlite3` with these arguments and gives its exit status.
    private func sqliteStatus(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// A second `sqlite3` that takes the write lock on `database` and keeps
    /// it until it is ended, as agy does while it has the index open.
    private func holdWriteLock(on database: String) throws -> Process {
        let holder = Process()
        holder.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        holder.arguments = [database]
        let input = Pipe()
        holder.standardInput = input
        holder.standardOutput = FileHandle.nullDevice
        holder.standardError = FileHandle.nullDevice
        try holder.run()
        input.fileHandleForWriting.write(Data(".timeout 5000\nBEGIN IMMEDIATE;\n".utf8))
        // A write that gives up at once fails while the lock is held.
        for _ in 0..<100 {
            if sqliteStatus(["-cmd", ".timeout 0", database, "BEGIN IMMEDIATE; ROLLBACK;"]) != 0 { return holder }
            Thread.sleep(forTimeInterval: 0.05)
        }
        holder.terminate()
        XCTFail("the lock was never taken")
        return holder
    }

    /// An index with one conversation, with its three files, in a throwaway home.
    private func realIndex(_ rig: Rig) throws -> (database: String, conversations: String) {
        let data = rig.home + "/.gemini/antigravity"
        let conversations = data + "/conversations"
        try FileManager.default.createDirectory(atPath: conversations, withIntermediateDirectories: true)
        let database = data + "/conversation_summaries.db"
        XCTAssertEqual(sqlite(database, "CREATE TABLE conversation_summaries (conversation_id TEXT PRIMARY KEY, title TEXT);"
                              + "INSERT INTO conversation_summaries VALUES ('busy-1', 'T');"), "")
        for suffix in [".db", ".db-wal", ".db-shm"] {
            FileManager.default.createFile(atPath: conversations + "/busy-1" + suffix, contents: Data("x".utf8))
        }
        return (database, conversations)
    }

    private func realEnvironment(_ rig: Rig, busyTimeout: TimeInterval) -> NexusAgentEngine.Environment {
        var environment = NexusAgentEngine.Environment.live
        environment.home = rig.home
        environment.listSessions = { _, _, _ in [] }
        environment.runSqlite = { NexusAgentEngine.runSqliteProcess($0, $1, $2, busyTimeout: busyTimeout) }
        return environment
    }

    /// agy has the index locked the whole time: the delete waits for the
    /// busy timeout, then reports failure; the row is still there and so
    /// are the conversation's files.
    func testAnIndexThatStaysLockedKeepsTheConversationAndItsFiles() throws {
        let rig = Rig(realHome: true)
        defer { rig.tearDown() }
        let index = try realIndex(rig)
        let holder = try holdWriteLock(on: index.database)
        defer { holder.terminate() }

        let started = Date()
        let deleted = NexusAgentEngine.deleteSession(id: "busy-1", provider: .antigravity,
                                                     environment: realEnvironment(rig, busyTimeout: 0.4))
        let waited = Date().timeIntervalSince(started)

        XCTAssertFalse(deleted, "the delete reports that it did not happen")
        XCTAssertGreaterThanOrEqual(waited, 0.3, "it waited for the lock before giving up")
        XCTAssertLessThan(waited, 4)
        for suffix in [".db", ".db-wal", ".db-shm"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: index.conversations + "/busy-1" + suffix),
                          "busy-1\(suffix) is still there")
        }
        holder.terminate()
        holder.waitUntilExit()
        XCTAssertEqual(sqlite(index.database, "SELECT conversation_id FROM conversation_summaries;"), "busy-1",
                       "and so is the row")
    }

    /// A lock that is let go of in time is waited for, not failed on.
    func testAnIndexThatIsLockedBrieflyIsWaitedFor() throws {
        let rig = Rig(realHome: true)
        defer { rig.tearDown() }
        let index = try realIndex(rig)
        let holder = try holdWriteLock(on: index.database)
        defer { holder.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { holder.terminate() }

        let deleted = NexusAgentEngine.deleteSession(id: "busy-1", provider: .antigravity,
                                                     environment: realEnvironment(rig, busyTimeout: 5))

        XCTAssertTrue(deleted)
        XCTAssertEqual(sqlite(index.database, "SELECT count(*) FROM conversation_summaries;"), "0")
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: index.conversations)) ?? ["x"], [],
                       "the three files went with the row")
    }

    func testAnIndexThatIsNotLockedIsDeletedFromAtOnce() throws {
        let rig = Rig(realHome: true)
        defer { rig.tearDown() }
        let index = try realIndex(rig)

        let started = Date()
        let deleted = NexusAgentEngine.deleteSession(id: "busy-1", provider: .antigravity,
                                                     environment: realEnvironment(rig, busyTimeout: 2))

        XCTAssertTrue(deleted)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5, "no waiting when there is nothing to wait for")
        XCTAssertEqual(sqlite(index.database, "SELECT count(*) FROM conversation_summaries;"), "0")
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: index.conversations)) ?? ["x"], [])
    }

    func testTheDeleteItemHasWords() {
        XCTAssertEqual(NexusAgentHostStrings().deleteSession, "Delete")
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let engine = NexusAgentEngine(environment: rig.environment, host: host)
        host.strings.deleteSession = "Löschen"
        XCTAssertEqual(engine.hostStrings.deleteSession, "Löschen",
                       "the engine hands on the host's words as they are now")
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

        // What the standalone app makes of that notice: a notification when
        // nobody can see the Allow button, nothing more when they can.
        if let notice = host.approvals.first {
            XCTAssertEqual(NexusAgentTurnAnnouncement.needsApproval(notice, isChatVisible: false,
                                                                    strings: host.strings),
                           NexusAgentTurnAnnouncement(playsSound: false,
                                                      notificationTitle: "Antigravity CLI — Approval Required",
                                                      notificationBody: "Bash: ls -la"))
            XCTAssertEqual(NexusAgentTurnAnnouncement.needsApproval(notice, isChatVisible: true,
                                                                    strings: host.strings),
                           NexusAgentTurnAnnouncement(playsSound: false))
        }

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

    // MARK: A failed turn says why

    /// What the standalone app does with a notice when its chat is out of sight.
    private func announcedOutOfSight(_ notice: NexusAgentTurnNotice?) -> NexusAgentTurnAnnouncement? {
        notice.map { NexusAgentTurnAnnouncement.finished($0, isChatVisible: false, strings: NexusAgentHostStrings()) }
    }

    func testAnAgentThatExitsBadlyReportsTheWordsOfItsErrorBubble() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let engine = NexusAgentEngine(environment: rig.environment, host: host)

        engine.session.send("do it", configuration: engine.configuration, agentPath: "/fake/agy")
        // Not stream JSON: agy's own complaint, which the bubble shows.
        rig.agentOutput?(Data("agy: quota exceeded\n".utf8))
        rig.agentExit?(1)
        engine.session.stopTranscriptFollower()

        let bubble = engine.session.messages.last
        XCTAssertEqual(bubble?.isError, true)
        XCTAssertEqual(bubble?.text, "The agent stopped with an error.\nagy: quota exceeded")
        XCTAssertEqual(host.finished.count, 1)
        let notice = host.finished.first?.notice
        XCTAssertEqual(notice?.failed, true)
        XCTAssertEqual(notice?.text, "", "the reply is still the reply: there was none")
        XCTAssertEqual(notice?.failureDetail, bubble?.text, "the notice carries what the bubble says")
        XCTAssertEqual(announcedOutOfSight(notice),
                       NexusAgentTurnAnnouncement(playsSound: false,
                                                  notificationTitle: "Antigravity CLI — Failed",
                                                  notificationBody: "The agent stopped with an error.\nagy: quota exceeded"))
    }

    // MARK: - A turn that cannot be started is a failed turn

    /// The agent's program is there but starting it fails. The chat says so
    /// in an error bubble; with the chat out of sight that bubble is seen
    /// by nobody, so the host is told too, in the bubble's words. The same
    /// for every provider whose turns are run this way.
    func testAnAgentThatCannotBeStartedIsAFailedTurn() {
        let providers: [(NexusAgentCLIProvider, path: String, model: String)] = [
            (.antigravity, "/fake/agy", ""), (.claude, "/fake/claude", ""), (.ollama, "/fake/ollama", "m"),
        ]
        for (provider, path, model) in providers {
            let rig = Rig()
            defer { rig.tearDown() }
            rig.agentCannotStart = true
            let host = RecordingHost()
            let engine = NexusAgentEngine(environment: rig.environment, host: host)
            engine.updateActiveProvider(provider)
            var configuration = engine.configuration
            configuration.model = model

            engine.session.send("do it", configuration: configuration, agentPath: path)
            engine.session.stopTranscriptFollower()

            XCTAssertFalse(engine.session.isRunning, provider.name)
            XCTAssertTrue(rig.agentRuns.isEmpty, provider.name)
            let bubble = engine.session.messages.last
            XCTAssertEqual(bubble?.isError, true, provider.name)
            XCTAssertEqual(bubble?.text, host.strings.agentFailed, provider.name)
            XCTAssertEqual(host.finished.count, 1, "\(provider.name): the host is told, once")
            let notice = host.finished.first?.notice
            XCTAssertEqual(notice?.providerName, provider.name)
            XCTAssertEqual(notice?.failed, true, provider.name)
            XCTAssertEqual(notice?.endedCleanly, false, provider.name)
            XCTAssertEqual(notice?.text, "", "\(provider.name): there was no reply")
            XCTAssertEqual(notice?.failureDetail, bubble?.text, "\(provider.name): the notice carries what the bubble says")
            XCTAssertEqual(announcedOutOfSight(notice),
                           NexusAgentTurnAnnouncement(playsSound: false,
                                                      notificationTitle: "\(provider.name) — Failed",
                                                      notificationBody: host.strings.agentFailed),
                           provider.name)

            // The chat is usable again, and the next turn is reported as any other.
            rig.agentCannotStart = false
            engine.session.send("again", configuration: configuration, agentPath: path)
            XCTAssertEqual(rig.agentRuns.count, 1, provider.name)
            rig.agentExit?(0)
            engine.session.stopTranscriptFollower()
            XCTAssertEqual(host.finished.count, 2, provider.name)
            XCTAssertEqual(host.finished.last?.notice.failed, false, provider.name)
        }
    }

    /// The agent's program is not installed at all: the same failed turn,
    /// in the words of the bubble that says it is missing.
    func testAnAgentThatIsNotInstalledIsAFailedTurn() {
        for provider in [NexusAgentCLIProvider.antigravity, .claude, .ollama] {
            let rig = Rig()
            defer { rig.tearDown() }
            let host = RecordingHost()
            let engine = NexusAgentEngine(environment: rig.environment, host: host)
            engine.updateActiveProvider(provider)

            engine.session.send("do it", configuration: engine.configuration, agentPath: nil)

            XCTAssertFalse(engine.session.isRunning, provider.name)
            XCTAssertTrue(rig.agentRuns.isEmpty, provider.name)
            XCTAssertTrue(rig.programRuns.isEmpty, "\(provider.name): nothing is asked of a program that is not there")
            let bubble = engine.session.messages.last
            XCTAssertEqual(bubble?.isError, true, provider.name)
            XCTAssertEqual(bubble?.text, wordsForMissing(provider), provider.name)
            XCTAssertEqual(host.finished.count, 1, "\(provider.name): the host is told, once")
            let notice = host.finished.first?.notice
            XCTAssertEqual(notice?.providerName, provider.name)
            XCTAssertEqual(notice?.failed, true, provider.name)
            XCTAssertEqual(notice?.endedCleanly, false, provider.name)
            XCTAssertEqual(notice?.text, "", provider.name)
            XCTAssertEqual(notice?.failureDetail, wordsForMissing(provider), provider.name)
            XCTAssertEqual(announcedOutOfSight(notice)?.notificationBody, wordsForMissing(provider), provider.name)
        }
    }

    /// What the chat says when a built-in provider's program is not
    /// installed: agy's own sentence for agy, and for the others the
    /// sentence a missing command gets, naming the program looked for.
    private func wordsForMissing(_ provider: NexusAgentCLIProvider) -> String {
        switch provider.id {
        case NexusAgentCLIProvider.claude.id: return "Could not find 'claude' in PATH. Is it installed?"
        case NexusAgentCLIProvider.ollama.id: return "Could not find 'ollama' in PATH. Is it installed?"
        default: return "The Antigravity CLI (agy) was not found."
        }
    }

    /// The sentence names the program that was looked for, in the host's
    /// words: agy's is the host's own (a translation is kept word for
    /// word), any other is built around the program's name. The page asks
    /// the engine for the same sentence while the program is missing.
    func testAMissingProgramIsNamed() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        host.strings.missingAgent = "agy fehlt."
        host.strings.commandNotFoundPrefix = "Nicht gefunden: "
        host.strings.commandNotFoundSuffix = "."
        let engine = NexusAgentEngine(environment: rig.environment, host: host)
        let cases: [(NexusAgentCLIProvider, String)] = [
            (.antigravity, "agy fehlt."), (.claude, "Nicht gefunden: claude."), (.ollama, "Nicht gefunden: ollama."),
            (ownProvider(), "Nicht gefunden: llm."),
            (ownProvider("\"/Applications/My Tool/run\" {prompt}"), "Nicht gefunden: /Applications/My Tool/run."),
        ]
        for (provider, words) in cases {
            XCTAssertEqual(host.strings.missingProgram(of: provider), words, provider.commandTemplate)
            engine.updateActiveProvider(provider)
            XCTAssertNil(engine.agentPath, provider.commandTemplate)
            XCTAssertEqual(engine.missingProgramText, words, provider.commandTemplate)
            engine.session.newChat()
            engine.session.send("hi", configuration: engine.configuration, agentPath: engine.agentPath)
            XCTAssertEqual(engine.session.messages.last?.text, words, provider.commandTemplate)
            XCTAssertEqual(host.finished.last?.notice.failureDetail, words, provider.commandTemplate)
        }
        XCTAssertEqual(host.finished.count, cases.count, "one failed notice each")

        // Once the program is there the page has nothing to say.
        rig.executables = ["/opt/homebrew/bin/llm"]
        engine.updateActiveProvider(ownProvider())
        XCTAssertNotNil(engine.agentPath)
        XCTAssertNil(engine.missingProgramText)
    }

    /// A command's program may be written with the model in it
    /// (`{model} run {prompt}`). The page then names the program the chat
    /// looked for and names in its bubble: the model filled in, the
    /// stand-in model when none is set, and never the placeholder.
    func testThePageNamesACommandsProgramAsTheChatDoes() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        rig.files[rig.defaultBot] = ""
        let env = rig.defaultBot + "/.env"
        let engine = NexusAgentEngine(environment: rig.environment, host: host)
        let fallback = NexusAgentSupport.templateFallbackModel
        // The template, the model in the settings file, the program named.
        let cases: [(String, String, String)] = [
            ("llm -m {model} \"{prompt}\"", "gemma3:4b", "llm"),
            ("{model} run {prompt}", "gemma3:4b", "gemma3:4b"),
            ("{model} run {prompt}", "", fallback),
            ("run-{model} {prompt}", "gemma3:4b", "run-gemma3:4b"),
            // A program named by the prompt is no program: named as written.
            ("{prompt} {model}", "gemma3:4b", "{prompt}"),
        ]
        for (template, model, program) in cases {
            let label = "\(template) with model '\(model)'"
            // A file that says nothing is not read, so it always has a line.
            rig.files[env] = "TELEGRAM_BOT_TOKEN=1:abc\n" + (model.isEmpty ? "" : "AGY_MODEL=\(model)\n")
            engine.load()
            XCTAssertEqual(engine.configuration.model, model, label)
            let provider = ownProvider(template)
            engine.updateActiveProvider(provider)
            XCTAssertNil(engine.agentPath, label)
            let words = "Could not find '\(program)' in PATH. Is it installed?"
            XCTAssertEqual(engine.missingProgramText, words, label)
            XCTAssertEqual(host.strings.missingProgram(of: provider, model: model), words, label)
            engine.session.newChat()
            engine.session.send("hi", configuration: engine.configuration, agentPath: engine.agentPath)
            XCTAssertEqual(engine.session.messages.last?.text, words, "the chat's bubble: \(label)")
        }
    }

    /// A turn stopped while it was still waiting to start (Ollama being
    /// asked for its models) never reaches the launch, so it is a stopped
    /// turn and not a failed one, even when the launch would have failed.
    func testATurnStoppedBeforeItStartsIsNotAFailedTurn() async {
        let rig = Rig()
        defer { rig.tearDown() }
        rig.programOutput = ollamaListing
        rig.holdsProgram = true
        rig.agentCannotStart = true
        let host = RecordingHost()
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)

        session.send("hi", configuration: NexusAgentConfiguration(activeProvider: .ollama), agentPath: "/fake/ollama")
        await rig.wait { !rig.programRuns.isEmpty }
        session.stop()
        rig.finishProgram()
        await rig.settle()

        XCTAssertEqual(host.finished.count, 1, "the stop is the only thing reported")
        XCTAssertEqual(host.finished.first?.notice.failed, false)
        XCTAssertNil(host.finished.first?.notice.failureDetail)
        XCTAssertEqual(session.messages.last?.text, host.strings.replyStopped)
        XCTAssertEqual(session.messages.last?.isError, false)

        // Dropped by New chat while waiting: nothing at all is reported.
        rig.holdsProgram = true
        session.send("hi", configuration: NexusAgentConfiguration(activeProvider: .ollama), agentPath: "/fake/ollama")
        await rig.wait { rig.programRuns.count == 2 }
        session.newChat()
        rig.finishProgram()
        await rig.settle()
        XCTAssertEqual(host.finished.count, 1, "a turn dropped by New chat is not reported")
    }

    func testAnErrorTheAgentReportsItselfIsTheFailuresWords() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let engine = NexusAgentEngine(environment: rig.environment, host: host)

        // With no reply: the error has a bubble of its own.
        engine.session.send("one", configuration: engine.configuration, agentPath: "/fake/agy")
        rig.agentOutput?(Data((#"{"event":"result","result":{"status":"error","error":"Quota exceeded"}}"# + "\n").utf8))
        rig.agentExit?(1)
        XCTAssertEqual(engine.session.messages.last?.text, "Quota exceeded")
        XCTAssertEqual(engine.session.messages.last?.isError, true)
        XCTAssertEqual(host.finished.last?.notice.failed, true)
        XCTAssertEqual(host.finished.last?.notice.failureDetail, "Quota exceeded")
        XCTAssertEqual(announcedOutOfSight(host.finished.last?.notice)?.notificationBody, "Quota exceeded")

        // After part of a reply: the notice keeps the reply as its text, and
        // the notification still says what went wrong, not the half reply.
        engine.session.send("two", configuration: engine.configuration, agentPath: "/fake/agy")
        rig.agentOutput?(Data((#"{"event":"step_update","step_update":{"step_type":"agent_response","text_delta":"Half a reply"}}"# + "\n").utf8))
        rig.agentOutput?(Data((#"{"event":"result","result":{"status":"error","error":"Lost the connection"}}"# + "\n").utf8))
        rig.agentExit?(1)
        engine.session.stopTranscriptFollower()
        XCTAssertEqual(host.finished.last?.notice.text, "Half a reply")
        XCTAssertEqual(host.finished.last?.notice.failed, true)
        XCTAssertEqual(host.finished.last?.notice.failureDetail, "Lost the connection")
        XCTAssertEqual(announcedOutOfSight(host.finished.last?.notice),
                       NexusAgentTurnAnnouncement(playsSound: false,
                                                  notificationTitle: "Antigravity CLI — Failed",
                                                  notificationBody: "Lost the connection"))
        XCTAssertEqual(host.finished.count, 2)
    }

    func testATurnThatEndedWellCarriesNoFailureWords() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let engine = NexusAgentEngine(environment: rig.environment, host: host)

        finishOneTurn(rig, session: engine.session, configuration: engine.configuration,
                      reply: "All done.", status: 0)
        XCTAssertNil(host.finished.first?.notice.failureDetail)
    }

    // MARK: A turn the user stopped is not a failure to announce

    func testStoppingATurnBeforeAnythingArrivedAnnouncesNothing() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let engine = NexusAgentEngine(environment: rig.environment, host: host)

        engine.session.send("do it", configuration: engine.configuration, agentPath: "/fake/agy")
        engine.session.stop()
        // The signal ends it; the exit arrives as it does from a real one.
        rig.agentExit?(15)

        XCTAssertEqual(engine.session.messages.last?.text, host.strings.replyStopped)
        XCTAssertEqual(host.finished.count, 1)
        let notice = host.finished.first?.notice
        XCTAssertEqual(notice?.failed, true, "what the session sends is as it was: a bad exit with no reply")
        XCTAssertEqual(notice?.text, "")
        XCTAssertNil(notice?.failureDetail, "nothing went wrong that has words")
        XCTAssertEqual(host.finished.first?.isChatVisible, false)
        XCTAssertEqual(announcedOutOfSight(notice), NexusAgentTurnAnnouncement(playsSound: false),
                       "the user stopped it: no \"Failed\" notification")
    }

    func testStoppingATurnAfterSomeOfItArrivedIsDoneWithItsFirstLine() {
        let rig = Rig()
        defer { rig.tearDown() }
        let host = RecordingHost()
        let engine = NexusAgentEngine(environment: rig.environment, host: host)

        engine.session.send("do it", configuration: engine.configuration, agentPath: "/fake/agy")
        rig.agentOutput?(Data((#"{"event":"step_update","step_update":{"step_type":"agent_response","text_delta":"So far so good\nand more"}}"# + "\n").utf8))
        engine.session.stop()
        rig.agentExit?(15)

        XCTAssertEqual(host.finished.count, 1)
        let notice = host.finished.first?.notice
        XCTAssertEqual(notice?.failed, false)
        XCTAssertEqual(notice?.endedCleanly, false)
        XCTAssertNil(notice?.failureDetail)
        XCTAssertEqual(announcedOutOfSight(notice),
                       NexusAgentTurnAnnouncement(playsSound: false,
                                                  notificationTitle: "Antigravity CLI — Done",
                                                  notificationBody: "So far so good"))
    }

    // MARK: Plan mode is taken when the prompt is sent

    /// Ollama with no model set waits for `ollama list` before it starts.
    /// What the user switches while it waits is for the next turn.
    func testPlanModeSwitchedOffWhileTheModelIsLookedUpStillRunsThatTurnInPlanMode() async {
        let rig = Rig()
        defer { rig.tearDown() }
        rig.programOutput = ollamaListing
        rig.holdsProgram = true
        let host = RecordingHost()
        host.planMode = true
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)
        XCTAssertTrue(session.planMode)

        // Yolo in the settings: without plan mode this turn would skip every prompt.
        session.send("tidy up", configuration: NexusAgentConfiguration(approvalMode: .yolo, activeProvider: .ollama),
                     agentPath: "/fake/ollama")
        await rig.wait { !rig.programRuns.isEmpty }
        XCTAssertTrue(rig.agentRuns.isEmpty, "still waiting for the model")

        session.planMode = false
        rig.finishProgram()
        await rig.wait { !rig.agentRuns.isEmpty }

        let started = rig.agentRuns.first?.arguments ?? []
        XCTAssertEqual(rig.agentRuns.count, 1)
        XCTAssertEqual(PermissionArgumentsTests.permissionArguments(in: started), ["--permission-mode", "plan"],
                       "the turn was sent in plan mode, and runs in it")
        XCTAssertFalse(PermissionArgumentsTests.skipsPermissionPrompts(started))
        XCTAssertTrue(started.contains(NexusAgentSupport.planModePrompt("tidy up")),
                      "with plan mode's words in front of the prompt, as Ollama gets them")
        rig.agentExit?(0)

        // The next turn is sent with plan mode off, and is not in it.
        session.send("again", configuration: NexusAgentConfiguration(approvalMode: .yolo, model: "m", activeProvider: .ollama),
                     agentPath: "/fake/ollama")
        XCTAssertTrue(PermissionArgumentsTests.skipsPermissionPrompts(rig.agentRuns.last?.arguments ?? []))
        rig.agentExit?(0)
        session.stopTranscriptFollower()
    }

    func testPlanModeSwitchedOnWhileTheModelIsLookedUpDoesNotReachThatTurn() async {
        let rig = Rig()
        defer { rig.tearDown() }
        rig.holdsProgram = true
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: RecordingHost())

        session.send("tidy up", configuration: NexusAgentConfiguration(approvalMode: .acceptEdits, activeProvider: .ollama),
                     agentPath: "/fake/ollama")
        await rig.wait { !rig.programRuns.isEmpty }
        session.planMode = true
        rig.finishProgram()
        await rig.wait { !rig.agentRuns.isEmpty }

        let started = rig.agentRuns.first?.arguments ?? []
        XCTAssertEqual(PermissionArgumentsTests.permissionArguments(in: started), ["--permission-mode", "acceptEdits"])
        XCTAssertTrue(started.contains("tidy up"), "the prompt as it was sent")
        rig.agentExit?(0)
        session.stopTranscriptFollower()
    }

    func testWorktreeModeSwitchedWhileTheModelIsLookedUpIsForTheNextTurn() async {
        let rig = Rig()
        defer { rig.tearDown() }
        rig.holdsProgram = true
        let host = RecordingHost()
        host.worktreeMode = true
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)

        session.send("tidy up", configuration: NexusAgentConfiguration(activeProvider: .ollama), agentPath: "/fake/ollama")
        await rig.wait { !rig.programRuns.isEmpty }
        session.worktreeMode = false
        rig.finishProgram()
        await rig.wait { !rig.agentRuns.isEmpty }

        XCTAssertTrue((rig.agentRuns.first?.arguments ?? []).contains("-w"), "sent in a worktree, run in one")
        rig.agentExit?(0)
        session.stopTranscriptFollower()
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
