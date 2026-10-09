// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Darwin
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Nexus Agent: the bot's `.env` rules, the agent's arguments and stream,
/// the catalog wiring, and the service and Quick Prompt over a fake Mac.
enum NexusAgentTests {
    static func run(_ suite: TestSuite) {
        envFile(suite)
        modes(suite)
        locations(suite)
        stream(suite)
        wiring(suite)
        botLifecycle(suite)
        autoStart(suite)
        configurationSaving(suite)
        quickPrompt(suite)
        quickPromptLayout(suite)
        quickPromptModes(suite)
        sessionIndex(suite)
        transcriptParsing(suite)
        replyBlocks(suite)
        markdownBlocks(suite)
        cliProviders(suite)
        turnMetrics(suite)
        pinningAndRetry(suite)
        liveTranscriptAndSubagents(suite)
        sessionArchiving(suite)
        claudeSessionTitles(suite)
        claudeEnhancementsAndApprovals(suite)
        notchIntegration(suite)
        antigravityTelemetry(suite)
    }

    // MARK: - .env

    private static func envFile(_ suite: TestSuite) {
        let legacy = """
        # Telegram Bot Token
        export TELEGRAM_BOT_TOKEN="123:abc"
        ALLOWED_USER_IDS= 1, 2 ,,3 # me
        GEMINI_WORKING_DIR=~/code
        GEMINI_APPROVAL_MODE=auto_edit
        GEMINI_MODEL=gemini-x
        GEMINI_THINKING=true
        CUSTOM=keep\r
        """
        let parsed = NexusAgentEnvFile.parse(legacy)
        suite.expect(parsed.botToken == "123:abc" && parsed.allowedUserIDList == ["1", "2", "3"]
                     && parsed.workingDirectory == "~/code" && parsed.approvalMode == .acceptEdits
                     && parsed.model == "gemini-x" && parsed.effort == .high,
                     "the .env reads as dotenv does, with the Gemini names as fallbacks: \(parsed)")
        suite.expect(NexusAgentEnvFile.values(in: legacy)["CUSTOM"] == "keep",
                     "a CRLF line ending is not part of the value")

        let both = "AGY_MODEL=new\nGEMINI_MODEL=old\nAGY_EFFORT=low\nGEMINI_THINKING=true\n"
        let preferred = NexusAgentEnvFile.parse(both)
        suite.expect(preferred.model == "new" && preferred.effort == .low,
                     "an AGY_ key beats its Gemini fallback, and an explicit effort beats GEMINI_THINKING")
        suite.expect(NexusAgentEnvFile.parse("AGY_MODEL=a\nAGY_MODEL=b\n").model == "b",
                     "the last copy of a key wins, as dotenv reads it")

        var edited = parsed
        edited.botToken = "999:zzz"
        edited.approvalMode = .plan
        edited.effort = .medium
        edited.model = "model #2"
        let rendered = NexusAgentEnvFile.render(edited, over: legacy)
        let reread = NexusAgentEnvFile.parse(rendered)
        var expected = edited
        expected.allowedUserIDs = "1,2,3"
        suite.expect(reread == expected, "a saved .env reads back as written, the user list tidied: \(reread)")
        suite.expect(rendered.hasPrefix("# Telegram Bot Token\n") && rendered.contains("CUSTOM=keep"),
                     "saving keeps comments and keys the page does not own")
        suite.expect(!rendered.contains("GEMINI_"), "saving drops the superseded Gemini names")
        suite.expect(rendered.hasSuffix("\n") && !rendered.hasSuffix("\n\n\n"), "the file ends with one newline")

        let twice = NexusAgentEnvFile.render(NexusAgentConfiguration(botToken: "t"),
                                             over: "TELEGRAM_BOT_TOKEN=a\nOTHER=1\nTELEGRAM_BOT_TOKEN=b\n")
        suite.expect(twice.components(separatedBy: "TELEGRAM_BOT_TOKEN=t").count == 3
                     && !twice.contains("=a") && !twice.contains("=b"),
                     "every copy of an owned key gets the new value")

        var injected = NexusAgentConfiguration(botToken: "a\nCUSTOM=evil", allowedUserIDs: "1\r\n2")
        injected.model = " padded "
        let guarded = NexusAgentEnvFile.render(injected, over: "CUSTOM=keep\n")
        let guardedValues = NexusAgentEnvFile.values(in: guarded)
        suite.expect(guardedValues["CUSTOM"] == "keep" && guardedValues[NexusAgentEnvFile.tokenKey] == "aCUSTOM=evil",
                     "a pasted line break can never smuggle in another assignment: \(guarded)")
        suite.expect(guardedValues[NexusAgentEnvFile.modelKey] == "padded",
                     "values are trimmed before they are written")

        let fresh = NexusAgentEnvFile.render(NexusAgentConfiguration(botToken: "x"), over: nil)
        suite.expect(fresh.contains("AGY_TIMEOUT_MS=300000") && fresh.contains("CLI_PROVIDER=agy")
                     && NexusAgentEnvFile.parse(fresh) == NexusAgentConfiguration(botToken: "x"),
                     "a first save writes the bot's template with the page's values")
        suite.expect(NexusAgentEnvFile.render(NexusAgentConfiguration(), over: "  \n") == NexusAgentEnvFile.render(NexusAgentConfiguration(), over: nil),
                     "a blank file is treated as no file")
        suite.expect(NexusAgentEnvFile.encoded("it's #1") == "\"it's #1\"" && NexusAgentEnvFile.encoded("a#b") == "'a#b'"
                     && NexusAgentEnvFile.encoded("plain") == "plain",
                     "a value dotenv would cut is quoted, in quotes it keeps")
        suite.expect(NexusAgentEnvFile.assignment(in: "# KEY=value") == nil
                     && NexusAgentEnvFile.assignment(in: "not an assignment") == nil
                     && NexusAgentEnvFile.assignment(in: "=value") == nil,
                     "comments, prose and keyless lines are not assignments")
    }

    // MARK: - Modes

    private static func modes(_ suite: TestSuite) {
        suite.expect(NexusAgentApprovalMode.parse(nil) == .yolo && NexusAgentApprovalMode.parse("") == .standard
                     && NexusAgentApprovalMode.parse(" PLAN ") == .plan
                     && NexusAgentApprovalMode.parse("accept_edits") == .acceptEdits
                     && NexusAgentApprovalMode.parse("auto_edit") == .acceptEdits
                     && NexusAgentApprovalMode.parse("bogus") == .standard,
                     "approval modes parse as the bot reads them")
        suite.expect(NexusAgentApprovalMode.yolo.agyArguments == ["--dangerously-skip-permissions"]
                     && NexusAgentApprovalMode.acceptEdits.agyArguments == ["--mode", "accept-edits"]
                     && NexusAgentApprovalMode.standard.agyArguments.isEmpty,
                     "each approval mode passes agy the bot's flags")
        suite.expect(NexusAgentEffort.parse("HIGH") == .high && NexusAgentEffort.parse(nil) == .automatic
                     && NexusAgentEffort.parse("max") == .automatic,
                     "effort parses, unknown values leaving the choice to agy")
        suite.expect(!NexusAgentConfiguration().isConfigured
                     && !NexusAgentConfiguration(botToken: NexusAgentConfiguration.placeholderToken).isConfigured
                     && !NexusAgentConfiguration(botToken: "   ").isConfigured
                     && NexusAgentConfiguration(botToken: "1:a").isConfigured,
                     "only a real token counts as configured")

        let configuration = NexusAgentConfiguration(approvalMode: .plan, model: " m ", effort: .low)
        suite.expect(NexusAgentSupport.agentArguments(prompt: "hi", configuration: configuration, conversationID: "c1")
                     == ["-p", "hi", "--output-format", "stream-json", "--mode", "plan", "--model", "m",
                         "--effort", "low", "--conversation", "c1"],
                     "a turn passes the prompt, streamed JSON, the bot's settings and the conversation")
        suite.expect(NexusAgentSupport.agentArguments(prompt: "hi", configuration: NexusAgentConfiguration(approvalMode: .standard),
                                                      conversationID: "")
                     == ["-p", "hi", "--output-format", "stream-json"],
                     "a first turn with agy defaults passes nothing else")
    }

    // MARK: - Locations

    private static func locations(_ suite: TestSuite) {
        let home = "/Users/test"
        suite.expect(NexusAgentSupport.botDirectory(configured: "", home: home) == "/Users/test/.config/nexus-agent"
                     && NexusAgentSupport.botDirectory(configured: "~", home: home) == home
                     && NexusAgentSupport.botDirectory(configured: " ~/bots/nexus ", home: home) == "/Users/test/bots/nexus"
                     && NexusAgentSupport.botDirectory(configured: "/opt/nexus", home: home) == "/opt/nexus",
                     "the bot folder defaults to the standalone app's and expands ~")
        let installed: Set<String> = ["/opt/homebrew/bin/agy", "/custom/agy", "/usr/local/bin/node"]
        suite.expect(NexusAgentSupport.locateAgent(environment: ["AGY_BIN": "/custom/agy"], home: home,
                                                   isExecutable: installed.contains) == "/custom/agy"
                     && NexusAgentSupport.locateAgent(environment: ["AGY_BIN": "/missing/agy"], home: home,
                                                      isExecutable: installed.contains) == "/opt/homebrew/bin/agy"
                     && NexusAgentSupport.locateAgent(environment: [:], home: home, isExecutable: { _ in false }) == nil,
                     "AGY_BIN wins when it runs; otherwise the usual install folders, or nothing")
        suite.expect(NexusAgentSupport.locateNode(home: home, isExecutable: installed.contains) == "/usr/local/bin/node"
                     && NexusAgentSupport.locateNode(home: home, isExecutable: { _ in false }) == nil,
                     "Node is found where Homebrew or its installer put it")
        let child = NexusAgentSupport.childEnvironment(base: ["PATH": "/opt/homebrew/bin:/usr/bin", "KEEP": "1"], home: home)
        suite.expect(child["PATH"] == "/Users/test/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin"
                     && child["NO_COLOR"] == "1" && child["KEEP"] == "1",
                     "the child gets the install folders in front of PATH, once each: \(child["PATH"] ?? "")")
        suite.expect(NexusAgentSupport.childEnvironment(base: [:], home: home)["PATH"]?.hasSuffix(":/usr/bin:/bin:/usr/sbin:/sbin") == true,
                     "an app with no PATH still gives the child the system folders")
        suite.expect(NexusAgentSupport.tail("a\n\nb\nc\n", count: 2) == ["b", "c"]
                     && NexusAgentSupport.tail("x", count: 0).isEmpty,
                     "the log tail keeps the last non-empty lines")
        suite.expect(NexusAgentSupport.processID(fromPIDFile: " 42\n") == 42
                     && NexusAgentSupport.processID(fromPIDFile: "0") == nil
                     && NexusAgentSupport.processID(fromPIDFile: "-5") == nil
                     && NexusAgentSupport.processID(fromPIDFile: "abc") == nil,
                     "a PID file names a positive process id or nothing")
        let models = NexusAgentSupport.parseModels("Fetching models…\ngemini-3\tGemini 3\nsolo\n\n")
        suite.expect(models.map(\.id) == ["gemini-3", "solo"] && models.map(\.name) == ["Gemini 3", "solo"],
                     "agy models reads id and name rows")
    }

    // MARK: - Stream

    private static func stream(_ suite: TestSuite) {
        suite.expect(NexusAgentStreamEvent.parse(#"{"event":"init","conversation_id":"c9"}"#) == .started(conversationID: "c9"),
                     "init carries the conversation id")
        suite.expect(NexusAgentStreamEvent.parse(#"{"event":"step_update","step_update":{"step_type":"agent_response","text_delta":"Hi"}}"#) == .text("Hi"),
                     "a response step carries its text delta")
        suite.expect(NexusAgentStreamEvent.parse(#"{"event":"step_update","step_update":{"step_type":"tool","tool_name":"grep","state":"RUNNING"}}"#)
                        == .tool(name: "grep", finished: false)
                     && NexusAgentStreamEvent.parse(#"{"event":"step_update","step_update":{"step_type":"tool","state":"done"}}"#)
                        == .tool(name: "tool", finished: true),
                     "a tool step says which tool runs and when it is done")
        suite.expect(NexusAgentStreamEvent.parse(#"{"event":"result","result":{"status":"ok","response":"All","conversation_id":"c9"}}"#)
                     == .finished(status: "ok", response: "All", error: nil, conversationID: "c9"),
                     "the result carries the status, the whole reply and the id")
        suite.expect(NexusAgentStreamEvent.parse("") == nil && NexusAgentStreamEvent.parse("Error: boom") == nil
                     && NexusAgentStreamEvent.parse(#"{"event":"heartbeat"}"#) == nil
                     && NexusAgentStreamEvent.parse(#"{"event":"step_update","step_update":{"step_type":"agent_response","text_delta":""}}"#) == nil,
                     "noise, unknown events and empty deltas are skipped")

        var buffer = NexusAgentLineBuffer()
        let bytes = Array("first\nsé".utf8)
        let cut = bytes.count - 1 // inside the two bytes of é
        let firstLines = buffer.append(Data(bytes[..<cut]))
        let secondLines = buffer.append(Data(bytes[cut...]) + Data("cond\nthird".utf8))
        suite.expect(firstLines == ["first"] && secondLines == ["sécond"] && buffer.finish() == "third"
                     && buffer.finish() == nil,
                     "lines split only at newlines, a character cut between reads comes out whole")
    }

    // MARK: - Wiring

    private static func wiring(_ suite: TestSuite) {
        let feature = AppFeature.nexusAgent
        suite.expect(feature.group == .tools && !feature.installedByDefault && feature.enabledKeys.isEmpty
                     && feature.permissions.isEmpty,
                     "Nexus Agent is an opt-in tool that needs no permission up front")
        suite.expect(GlobalShortcutRole.nexusAgent.feature == .nexusAgent
                     && GlobalShortcutRole.nexusAgent.storageKey == DefaultsKey.nexusAgentShortcut
                     && GlobalShortcutRole.nexusAgent.requiredEnableKeys == [DefaultsKey.nexusAgentShortcutEnabled],
                     "the Quick Prompt shortcut belongs to the feature and its own switch")
        let registered = Defaults.registeredDefaults
        suite.expect(registered[DefaultsKey.nexusAgentShortcutEnabled] as? Bool == false
                     && registered[DefaultsKey.nexusAgentAutoStart] as? Bool == false
                     && registered[DefaultsKey.nexusAgentBotDirectory] as? String == ""
                     && registered[DefaultsKey.panelUtilityNexusAgent] as? Bool == true
                     && registered[DefaultsKey.nexusAgentShortcut] as? String == GlobalShortcut.nexusAgentDefault.storageValue,
                     "the shortcut and auto-start start off; the panel tile shows once installed")
        suite.expect(SettingsBackupSupport.machineStateKeys.contains(DefaultsKey.nexusAgentBotDirectory),
                     "the bot folder is this Mac's, so a backup does not carry it")
        suite.expect(!registered.keys.contains { $0.lowercased().contains("token") && $0.lowercased().contains("nexus") },
                     "the bot token never lives in preferences")
        suite.expect(FeatureRuntime.actions(for: .nexusAgent, in: UserDefaults(suiteName: "com.vitruviansoftware.vitruvian.tests.nexus-wiring")!)
                     == [.nexusAgent],
                     "installing or removing the feature resyncs its service")
        UserDefaults.standard.removePersistentDomain(forName: "com.vitruviansoftware.vitruvian.tests.nexus-wiring")
        suite.expect(MenuPanelRowFeatures.utilities.contains(.nexusAgent)
                     && PanelSectionID.utilities.featureGate.contains(.nexusAgent),
                     "the panel tile and its section follow the feature")
    }

    // MARK: - Service

    /// A Mac in memory: files, the processes alive, what was signalled and
    /// launched, and the delayed work, run by hand.
    @MainActor
    private final class Rig {
        let domain: String
        let defaults: UserDefaults
        var files: [String: String] = [:]
        var executables: Set<String> = []
        var aliveNode: Set<Int32> = []
        var signals: [(Int32, Int32)] = []
        var launches: [(node: String, directory: String, log: String)] = []
        var exitHandlers: [Int32: @MainActor @Sendable (Int32) -> Void] = [:]
        var nextPID: Int32 = 500
        var launchFails = false
        var pending: [@MainActor () -> Void] = []
        var opened: [String] = []
        var agentRuns: [(path: String, arguments: [String], directory: String)] = []
        var agentOutput: (@MainActor @Sendable (Data) -> Void)?
        var agentExit: (@MainActor @Sendable (Int32) -> Void)?
        var agentTerminations = 0
        var sessionList: [NexusAgentSessionSummary] = []
        var listedDirectories: [String] = []
        var listedProviders: [NexusAgentCLIProvider] = []
        let home = "/Users/rig"
        let state = "/Users/rig/Library/Application Support/NexusAgent"
        var bot: String { home + "/.config/nexus-agent" }

        /// One literal suite for every rig, so `PreferenceNamespaceTests` can
        /// prove the sweep takes it; the rigs run one after another and each
        /// starts by clearing it.
        init() {
            let domain = "com.vitruviansoftware.vitruvian.tests.nexus-agent"
            self.domain = domain
            defaults = UserDefaults(suiteName: domain)!
            defaults.removePersistentDomain(forName: domain)
            defaults.set(true, forKey: AppFeature.nexusAgent.availabilityKey)
            defaults.set(false, forKey: DefaultsKey.nexusAgentShortcutEnabled)
        }

        func tearDown() { defaults.removePersistentDomain(forName: domain) }

        func installBot(token: String = "1:real") {
            files[bot] = ""
            files[bot + "/src/bot.js"] = "// bot"
            files[bot + "/.env"] = "TELEGRAM_BOT_TOKEN=\(token)\nAGY_TIMEOUT_MS=1\n"
            executables.insert("/opt/homebrew/bin/node")
        }

        func drain() {
            while !pending.isEmpty { pending.removeFirst()() }
        }

        var environment: NexusAgentService.Environment {
            NexusAgentService.Environment(
                defaults: defaults,
                home: home,
                processEnvironment: ["PATH": "/usr/bin"],
                stateDirectory: state,
                isExecutable: { [unowned self] in executables.contains($0) },
                fileExists: { [unowned self] in files[$0] != nil },
                readFile: { [unowned self] in files[$0] },
                readTail: { [unowned self] path, _ in files[path] },
                writePrivateFile: { [unowned self] path, content in
                    guard files[(path as NSString).deletingLastPathComponent] != nil
                            || path.hasPrefix(state) else { return false }
                    files[path] = content
                    return true
                },
                removeFile: { [unowned self] in files[$0] = nil },
                isBotProcess: { [unowned self] in aliveNode.contains($0) },
                signal: { [unowned self] pid, signal in
                    signals.append((pid, signal))
                    if signal == SIGKILL { aliveNode.remove(pid) }
                },
                launchBot: { [unowned self] node, directory, log, _, onExit in
                    if launchFails { throw CocoaError(.fileWriteUnknown) }
                    nextPID += 1
                    launches.append((node, directory, log))
                    aliveNode.insert(nextPID)
                    exitHandlers[nextPID] = onExit
                    return nextPID
                },
                schedule: { [unowned self] _, work in pending.append(work) },
                openFile: { [unowned self] in opened.append($0) },
                launchAgent: { [unowned self] path, arguments, directory, _, onOutput, onExit in
                    agentRuns.append((path, arguments, directory))
                    agentOutput = onOutput
                    agentExit = onExit
                    return NexusAgentRunningAgent(terminate: { [unowned self] in agentTerminations += 1 })
                },
                listSessions: { [unowned self] directory, provider in
                    listedDirectories.append(directory)
                    listedProviders.append(provider)
                    return sessionList
                },
                readTranscript: { [unowned self] id, _ in
                    let path = (state as NSString).appendingPathComponent("transcripts/\(id).jsonl")
                    if let raw = files[path] {
                        return NexusAgentService.parseTranscript(raw)
                    }
                    return nil
                },
                transcriptPath: { [unowned self] id, _ in
                    let path = (state as NSString).appendingPathComponent("transcripts/\(id).jsonl")
                    return files[path] != nil ? path : nil
                },
                readTranscriptRaw: { [unowned self] id, _ in
                    let path = (state as NSString).appendingPathComponent("transcripts/\(id).jsonl")
                    return files[path]
                })
        }
    }

    private static func botLifecycle(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.tearDown() }
        let service = NexusAgentService(environment: rig.environment)

        service.start()
        suite.expect(service.problem == .missingBot && rig.launches.isEmpty, "no bot folder, no start")
        rig.installBot(token: NexusAgentConfiguration.placeholderToken)
        service.start()
        suite.expect(service.problem == .missingToken && rig.launches.isEmpty, "the placeholder token does not start the bot")
        rig.installBot()
        rig.executables.removeAll()
        service.start()
        suite.expect(service.problem == .missingNode && rig.launches.isEmpty, "without Node the page says so")
        rig.executables.insert("/opt/homebrew/bin/node")
        rig.launchFails = true
        service.start()
        suite.expect(service.problem == .startFailed && !service.isRunning, "a failed launch is reported")
        rig.launchFails = false

        service.start()
        let pid = rig.nextPID
        suite.expect(service.isRunning && service.pid == pid && service.problem == nil
                     && rig.launches.last?.directory == rig.bot
                     && rig.launches.last?.log == rig.state + "/bot.log"
                     && rig.files[rig.state + "/.bot.pid"] == "\(pid)",
                     "start runs Node in the bot folder, logs where the standalone app does and records the PID")
        service.start()
        suite.expect(rig.launches.count == 1, "a running bot is not started twice")

        rig.aliveNode.remove(pid)
        rig.exitHandlers[pid]?(pid)
        suite.expect(!service.isRunning && rig.files[rig.state + "/.bot.pid"] == nil,
                     "when the bot exits, the page shows it stopped and the PID file goes")

        // A bot another app started is adopted, a stale PID file cleared.
        rig.files[rig.state + "/.bot.pid"] = "777"
        rig.aliveNode.insert(777)
        service.refreshStatus()
        suite.expect(service.isRunning && service.pid == 777, "a live bot in the PID file is adopted")
        rig.aliveNode.remove(777)
        service.refreshStatus()
        suite.expect(!service.isRunning && rig.files[rig.state + "/.bot.pid"] == nil,
                     "a PID file naming nothing alive (or not Node) is cleared, never signalled")
        suite.expect(!rig.signals.contains { $0.0 == 777 }, "a stale PID is never signalled")

        // Stop: SIGTERM, then SIGKILL only if the bot outlives the grace period.
        rig.files[rig.state + "/.bot.pid"] = "778"
        rig.aliveNode.insert(778)
        service.stop()
        suite.expect(rig.signals.last.map { $0 == (778, SIGTERM) } == true && !service.isRunning,
                     "stop asks the recorded bot to quit")
        rig.drain()
        suite.expect(rig.signals.last.map { $0 == (778, SIGKILL) } == true,
                     "a bot still there after the grace period is killed")
        rig.signals.removeAll()
        rig.files[rig.state + "/.bot.pid"] = "779"
        rig.aliveNode.insert(779)
        service.stop()
        rig.aliveNode.remove(779)
        rig.drain()
        suite.expect(rig.signals.count == 1 && rig.signals[0] == (779, SIGTERM),
                     "a bot that quits in time is not killed")

        // Restart waits for the old bot before starting the new one.
        service.start()
        let first = rig.nextPID
        let launchesBeforeRestart = rig.launches.count
        service.restart()
        suite.expect(rig.launches.count == launchesBeforeRestart,
                     "restart does not launch before the old bot is gone")
        rig.aliveNode.remove(first)
        rig.drain()
        suite.expect(rig.launches.count == launchesBeforeRestart + 1 && service.isRunning && service.pid == rig.nextPID,
                     "restart starts the bot again once the old one has exited")

        // Uninstalling stops the bot; nothing stays resident.
        rig.defaults.set(false, forKey: AppFeature.nexusAgent.availabilityKey)
        let running = rig.nextPID
        service.syncWithPreferences()
        suite.expect(rig.signals.contains { $0 == (running, SIGTERM) } && !service.isRunning,
                     "uninstalling the feature stops the bot")

        service.openLog()
        suite.expect(rig.opened.isEmpty, "there is no log to open before one exists")
        rig.files[rig.state + "/bot.log"] = "line one\nline two\n"
        service.openLog()
        service.startPolling()
        service.stopPolling()
        suite.expect(rig.opened == [rig.state + "/bot.log"] && service.logLines == ["line one", "line two"],
                     "the log opens and its tail shows on the page")
    }

    /// Auto-start runs once per launch, and only when asked.
    private static func autoStart(_ suite: TestSuite) {
        let auto = Rig()
        defer { auto.tearDown() }
        auto.installBot()
        let quiet = NexusAgentService(environment: auto.environment)
        quiet.syncWithPreferences()
        suite.expect(auto.launches.isEmpty, "the bot does not start with the app unless asked")
        auto.defaults.set(true, forKey: DefaultsKey.nexusAgentAutoStart)
        let eager = NexusAgentService(environment: auto.environment)
        eager.syncWithPreferences()
        eager.syncWithPreferences()
        suite.expect(auto.launches.count == 1 && eager.isRunning, "auto-start starts the bot once")
    }

    private static func configurationSaving(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.tearDown() }
        let service = NexusAgentService(environment: rig.environment)
        suite.expect(!service.save(NexusAgentConfiguration(botToken: "x")) && service.problem == .missingBot,
                     "saving with no bot folder writes nothing")
        rig.installBot()
        rig.files[rig.bot + "/.env"] = "# keep me\nTELEGRAM_BOT_TOKEN=old\nCLI_PROVIDER=custom\n"
        service.load()
        suite.expect(service.configuration.botToken == "old", "the page reads the bot's .env")
        var next = service.configuration
        next.botToken = "new"
        next.allowedUserIDs = "42"
        suite.expect(service.save(next) && !service.needsRestart, "saving while stopped needs no restart")
        let written = rig.files[rig.bot + "/.env"] ?? ""
        suite.expect(written.hasPrefix("# keep me\n") && written.contains("CLI_PROVIDER=custom")
                     && NexusAgentEnvFile.parse(written).allowedUserIDList == ["42"],
                     "saving keeps the rest of the file: \(written)")
        service.start()
        next.model = "m"
        service.save(next)
        suite.expect(service.needsRestart, "saving while the bot runs asks for a restart")
        service.restart()
        rig.aliveNode.removeAll()
        rig.drain()
        suite.expect(!service.needsRestart && service.isRunning, "the restart clears the hint")
    }

    // MARK: - Quick Prompt

    private static func quickPrompt(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.tearDown() }
        let session = NexusAgentQuickPromptSession(environment: rig.environment)
        let strings = FeatureStrings.nexusAgent(L10n.shared.language)

        session.send("hello", configuration: NexusAgentConfiguration(), agentPath: nil)
        suite.expect(session.messages.count == 2 && session.messages[1].isError
                     && session.messages[1].text == strings.missingAgent && rig.agentRuns.isEmpty,
                     "without agy the prompt says so instead of running")
        session.newChat()

        let configuration = NexusAgentConfiguration(workingDirectory: "~/missing", approvalMode: .plan)
        session.draft = "  first  "
        session.send(session.draft, configuration: configuration, agentPath: "/opt/agy-test/agy")
        suite.expect(session.isRunning && session.draft.isEmpty && rig.agentRuns.count == 1
                     && rig.agentRuns[0].directory == rig.home
                     && rig.agentRuns[0].arguments.prefix(2) == ["-p", "first"]
                     && !rig.agentRuns[0].arguments.contains("--conversation"),
                     "a first turn runs agy in home when the folder is gone, with no conversation yet")
        rig.agentOutput?(Data(#"{"event":"init","conversation_id":"conv-1"}"#.utf8 + [0x0A]))
        rig.agentOutput?(Data(#"{"event":"step_update","step_update":{"step_type":"tool","tool_name":"ls","state":"RUNNING"}}"#.utf8 + [0x0A]))
        suite.expect(session.activity == "ls", "the tool in use shows while it runs")
        rig.agentOutput?(Data(#"{"event":"step_update","step_update":{"step_type":"agent_response","text_delta":"Hel"}}"#.utf8 + [0x0A]))
        rig.agentOutput?(Data(#"{"event":"step_update","step_update":{"step_type":"agent_response","text_delta":"lo"}}"#.utf8))
        rig.agentOutput?(Data([0x0A]) + Data(#"{"event":"result","result":{"status":"ok","response":"Hello"}}"#.utf8))
        rig.agentExit?(0)
        suite.expect(!session.isRunning && session.messages.map(\.text) == ["first", "Hello"]
                     && session.conversationID == "conv-1" && session.activity == nil,
                     "deltas stream into one reply and the final result is not doubled: \(session.messages.map(\.text))")

        rig.files[rig.home + "/work"] = ""
        session.send("second", configuration: NexusAgentConfiguration(workingDirectory: "~/work"), agentPath: "/opt/agy-test/agy")
        suite.expect(rig.agentRuns.last?.arguments.suffix(2) == ["--conversation", "conv-1"]
                     && rig.agentRuns.last?.directory == rig.home + "/work",
                     "the next turn continues the conversation in the bot's folder")
        session.stop()
        rig.agentExit?(15)
        suite.expect(rig.agentTerminations == 1 && session.messages.last?.text == strings.replyStopped
                     && session.messages.last?.isError == false,
                     "stopping ends agy and says the reply stopped")

        session.send("third", configuration: NexusAgentConfiguration(), agentPath: "/opt/agy-test/agy")
        rig.agentOutput?(Data("agy: not logged in\n".utf8))
        rig.agentExit?(1)
        suite.expect(session.messages.last?.isError == true
                     && session.messages.last?.text == strings.agentFailed + "\nagy: not logged in",
                     "a failed run shows agy's own words")

        session.send("fourth", configuration: NexusAgentConfiguration(), agentPath: "/opt/agy-test/agy")
        rig.agentOutput?(Data(#"{"event":"result","result":{"status":"error","error":"quota"}}"#.utf8 + [0x0A]))
        rig.agentExit?(1)
        suite.expect(session.messages.last?.text == "quota" && session.messages.last?.isError == true
                     && session.messages.filter { $0.text.isEmpty }.isEmpty,
                     "an error agy reports replaces the empty reply")

        session.send("fifth", configuration: NexusAgentConfiguration(), agentPath: "/opt/agy-test/agy")
        let staleExit = rig.agentExit
        session.newChat()
        staleExit?(0)
        suite.expect(session.messages.isEmpty && session.conversationID == nil && !session.isRunning,
                     "new chat forgets the conversation, and the stopped turn cannot write into it")

        session.send("sixth", configuration: NexusAgentConfiguration(), agentPath: "/opt/agy-test/agy")
        rig.agentExit?(0)
        suite.expect(session.messages.last?.text == strings.emptyReply, "a run with no reply says so")
    }

    // MARK: - Quick Prompt pill, drawer and chat

    private static func quickPromptLayout(_ suite: TestSuite) {
        typealias Layout = NexusAgentQuickPromptLayout
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let pill = Layout.initialFrame(for: .compact, screen: screen)
        suite.expect(pill.size == CGSize(width: 680, height: 72) && Layout.cornerRadius == 22,
                     "the pill is 680 by 72 with 22 pt corners: \(pill)")
        suite.expect(pill.midX == screen.midX && pill.maxY < screen.maxY
                     && pill.minY > screen.minY + screen.height * 2 / 3
                     && abs((screen.maxY - pill.maxY) - screen.height * 0.18) < 0.5,
                     "the pill sits centred in the upper third, 18% below the top: \(pill)")
        let offset = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let other = Layout.initialFrame(for: .compact, screen: offset)
        suite.expect(offset.contains(other) && other.midX == offset.midX,
                     "on a second screen the pill opens on that screen: \(other)")

        let drawer = Layout.frame(for: .sessions, from: pill, screen: screen)
        suite.expect(drawer.size == CGSize(width: 680, height: 340) && drawer.maxY == pill.maxY
                     && drawer.midX == pill.midX,
                     "the drawer grows the panel to 680 by 340 downward, keeping its top: \(drawer)")
        let chat = Layout.frame(for: .chat, from: drawer, screen: screen)
        suite.expect(chat.size == CGSize(width: 680, height: 500) && chat.maxY == pill.maxY,
                     "the chat grows the panel to 680 by 500, keeping its top: \(chat)")
        let back = Layout.frame(for: .compact, from: chat, screen: screen)
        suite.expect(back == pill, "back to the pill returns to the same frame: \(back)")
        suite.expect(Layout.isResizable(.chat) && !Layout.isResizable(.compact) && !Layout.isResizable(.sessions)
                     && Layout.chatMinimumSize.width < 680 && Layout.chatMaximumSize.height > 500,
                     "only the chat can be resized, around its 680 by 500 size")

        let low = CGRect(x: 0, y: 0, width: 800, height: 500)
        let lowChat = Layout.frame(for: .chat, from: Layout.initialFrame(for: .compact, screen: low), screen: low)
        suite.expect(low.contains(lowChat), "on a short screen the chat stays on screen: \(lowChat)")
    }

    private static func quickPromptModes(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.tearDown() }
        let session = NexusAgentQuickPromptSession(environment: rig.environment)
        let agy = "/opt/agy-test/agy"
        suite.expect(session.mode == .compact && !session.planMode, "the prompt opens as the pill, plan mode off")

        session.draft = "   "
        suite.expect(!session.canSend, "send is off for a blank prompt")
        session.draft = "hi"
        suite.expect(session.canSend, "send is on once there is text")

        rig.files[rig.home + "/work"] = ""
        rig.sessionList = [
            NexusAgentSessionSummary(id: "a", title: "Fix the build", preview: "Please fix the build", steps: 4, modified: nil),
            NexusAgentSessionSummary(id: "b", title: "Write release notes", preview: "Write notes for v1.0", steps: 2, modified: nil),
        ]
        session.toggleSessions(configuration: NexusAgentConfiguration(workingDirectory: "~/work"))
        suite.expect(session.mode == .sessions && session.sessions.count == 2
                     && rig.listedDirectories == [rig.home + "/work"],
                     "the sessions button opens the drawer with agy's sessions for the bot's folder")
        session.sessionFilter = "BUILD"
        suite.expect(session.filteredSessions.map(\.id) == ["a"], "the filter narrows the drawer by title")
        session.toggleSessions(configuration: NexusAgentConfiguration())
        suite.expect(session.mode == .compact, "the sessions button closes the drawer again")

        session.planMode = true
        suite.expect(rig.defaults[Preferences.nexusAgentPlanMode],
                     "plan mode is remembered")
        suite.expect(NexusAgentQuickPromptSession(environment: rig.environment).planMode,
                     "a new prompt starts with the remembered plan mode")
        session.send("plan it", configuration: NexusAgentConfiguration(approvalMode: .yolo), agentPath: agy)
        let planned = rig.agentRuns.last?.arguments ?? []
        suite.expect(session.mode == .chat && planned.contains("plan")
                     && !planned.contains("--dangerously-skip-permissions"),
                     "sending opens the chat, and plan mode runs agy with --mode plan: \(planned)")
        suite.expect(!session.canSend, "send is off while a reply streams")
        rig.agentOutput?(Data(#"{"event":"init","conversation_id":"conv-9"}"#.utf8 + [0x0A]))
        rig.agentExit?(0)

        session.planMode = false
        session.draft = "and then?"
        session.send(session.draft, configuration: NexusAgentConfiguration(approvalMode: .yolo), agentPath: agy)
        let followUp = rig.agentRuns.last?.arguments ?? []
        suite.expect(session.mode == .chat && followUp.prefix(2) == ["-p", "and then?"]
                     && followUp.suffix(2) == ["--conversation", "conv-9"]
                     && followUp.contains("--dangerously-skip-permissions") && !followUp.contains("plan"),
                     "a follow-up continues the chat, back on the bot's own approval mode: \(followUp)")
        rig.agentExit?(0)

        session.newChat()
        suite.expect(session.mode == .compact && session.conversationID == nil
                     && session.sessionTitle == nil && !session.isResumed,
                     "new chat goes back to the pill and resets session title")
        session.toggleSessions(configuration: NexusAgentConfiguration())
        session.resume(rig.sessionList[1])
        suite.expect(session.mode == .chat && session.conversationID == "b"
                     && session.sessionTitle == "Write release notes"
                     && session.isResumed
                     && session.messages.count == 2
                     && session.messages.first?.text == "Write notes for v1.0"
                     && (session.messages.last?.text.contains("Resumed") ?? false),
                     "picking a session restores the conversation preview and title")
        session.send("more", configuration: NexusAgentConfiguration(), agentPath: agy)
        suite.expect(rig.agentRuns.last?.arguments.suffix(2) == ["--conversation", "b"],
                     "the next turn continues the picked session")
        rig.agentExit?(0)
        session.toggleSessions(configuration: NexusAgentConfiguration())
        session.toggleSessions(configuration: NexusAgentConfiguration())
        suite.expect(session.mode == .chat, "closing the drawer over a conversation returns to the chat")
    }

    private static func sessionIndex(_ suite: TestSuite) {
        let rows = """
        [{"conversation_id":"c1","title":"","preview":"Deploy the site\\nmore","step_count":7,
          "last_modified_time":"2026-10-01T09:30:00.250Z","workspace_uris":"[\\"file:///Users/me/work\\"]"},
          {"conversation_id":"c2","title":"Elsewhere","step_count":1,"workspace_uris":"[\\"file:///tmp/other\\"]"},
          {"conversation_id":"c3","title":"Anywhere","step_count":2,"last_modified_time":"2026-10-01T09:30:00Z"},
          {"conversation_id":"","title":"broken"}]
        """
        let sessions = NexusAgentSessionSummary.parse(Data(rows.utf8), directory: "/Users/me/work/")
        suite.expect(sessions.map(\.id) == ["c1", "c3"], "the drawer keeps this folder's and folderless sessions: \(sessions.map(\.id))")
        suite.expect(sessions.first?.title == "Deploy the site" && sessions.first?.steps == 7
                     && sessions.first?.preview == "Deploy the site\nmore"
                     && sessions.first?.modified != nil && sessions.last?.modified != nil,
                     "an untitled session shows its first prompt line, preview, and both date forms parse")
        suite.expect(NexusAgentSessionSummary.parse(Data("not json".utf8), directory: "/").isEmpty,
                     "an unreadable index lists nothing")
        suite.expect(NexusAgentSessionSummary.filter(sessions, by: "  ").count == 2
                     && NexusAgentSessionSummary.filter(sessions, by: "site deploy").map(\.id) == ["c1"],
                     "a blank filter keeps all; words match in any order")
        let allSessions = NexusAgentSessionSummary.parse(Data(rows.utf8), directory: "")
        suite.expect(allSessions.map(\.id) == ["c1", "c2", "c3"],
                     "an empty directory keeps all sessions across workspaces: \(allSessions.map(\.id))")

        // Project slug conversion for Claude Code projects
        suite.expect(NexusAgentSessionSummary.projectSlug(for: "/Users/james/Workspace/gh/application/vitruvian/vitruvian-core")
                     == "-Users-james-Workspace-gh-application-vitruvian-vitruvian-core",
                     "projectSlug converts monorepo path to slug")
        suite.expect(NexusAgentSessionSummary.projectSlug(for: "/Users/james/.buzz")
                     == "-Users-james--buzz",
                     "projectSlug converts dot paths to slug")
        suite.expect(NexusAgentSessionSummary.projectSlug(for: "/Users/james")
                     == "-Users-james",
                     "projectSlug converts simple path to slug")
    }

    private static func transcriptParsing(_ suite: TestSuite) {
        let sample = """
        {"step_index":0,"type":"USER_INPUT","content":"<USER_REQUEST>\\nHello agent\\n</USER_REQUEST>"}
        {"step_index":1,"type":"PLANNER_RESPONSE","content":"Hello! How can I help?"}
        """
        let messages = NexusAgentService.parseTranscript(sample)
        suite.expect(messages?.count == 2
                     && messages?.first?.role == .user && messages?.first?.text == "Hello agent"
                     && messages?.last?.role == .agent && messages?.last?.text == "Hello! How can I help?",
                     "transcript parses user request and agent response")

        let claudeJsonl = """
        {"type":"queue-operation","operation":"enqueue","content":"Initial prompt"}
        {"type":"user","message":{"content":"Explain the architecture"}}
        {"type":"assistant","message":{"content":[{"type":"text","text":"Here is the architecture breakdown."}]}}
        """
        let claudeMessages = NexusAgentService.parseClaudeTranscript(claudeJsonl)
        suite.expect(claudeMessages?.count == 2
                     && claudeMessages?[0].role == .user && claudeMessages?[0].text == "Explain the architecture"
                     && claudeMessages?[1].role == .agent && claudeMessages?[1].text == "Here is the architecture breakdown.",
                     "parseClaudeTranscript extracts user and assistant messages")
    }

    private static func replyBlocks(_ suite: TestSuite) {
        let reply = "Run **this**:\n```swift\nlet x = 1\n\nprint(x)\n```\nDone."
        suite.expect(NexusAgentReplyBlock.parse(reply) == [
            .text("Run **this**:"), .code(language: "swift", body: "let x = 1\n\nprint(x)"), .text("Done."),
        ], "prose and fenced code split apart, blank lines kept inside code: \(NexusAgentReplyBlock.parse(reply))")
        suite.expect(NexusAgentReplyBlock.parse("Partial\n```\nstill streaming") == [
            .text("Partial"), .code(language: nil, body: "still streaming"),
        ], "an unclosed fence while streaming is code to the end")
        suite.expect(NexusAgentReplyBlock.parse("") == [], "an empty reply has no blocks")
    }

    private static func markdownBlocks(_ suite: TestSuite) {
        // Headings
        suite.expect(NexusAgentMarkdownBlock.parse("# Heading 1") == [.heading(level: 1, text: "Heading 1")],
                     "heading 1 parses correctly")
        suite.expect(NexusAgentMarkdownBlock.parse("## Heading 2") == [.heading(level: 2, text: "Heading 2")],
                     "heading 2 parses correctly")
        suite.expect(NexusAgentMarkdownBlock.parse("### Heading 3") == [.heading(level: 3, text: "Heading 3")],
                     "heading 3 parses correctly")
        suite.expect(NexusAgentMarkdownBlock.parse("#NotAHeading") == [.paragraph(text: "#NotAHeading")],
                     "hash without space is treated as paragraph")

        // Bullet list items
        suite.expect(NexusAgentMarkdownBlock.parse("* item") == [.bulletItem(text: "item")],
                     "asterisk bullet item parses")
        suite.expect(NexusAgentMarkdownBlock.parse("- item") == [.bulletItem(text: "item")],
                     "dash bullet item parses")
        suite.expect(NexusAgentMarkdownBlock.parse("+ item") == [.bulletItem(text: "item")],
                     "plus bullet item parses")

        // Numbered list items
        suite.expect(NexusAgentMarkdownBlock.parse("1. item") == [.numberedItem(number: "1", text: "item")],
                     "numbered item 1. parses")
        suite.expect(NexusAgentMarkdownBlock.parse("2. item") == [.numberedItem(number: "2", text: "item")],
                     "numbered item 2. parses")
        suite.expect(NexusAgentMarkdownBlock.parse("1) item") == [.numberedItem(number: "1", text: "item")],
                     "numbered item 1) parses")

        // Blockquotes
        suite.expect(NexusAgentMarkdownBlock.parse("> quote line 1\n> quote line 2") == [
            .blockquote(text: "quote line 1\nquote line 2"),
        ], "contiguous quote lines merge into a single blockquote")

        // Dividers
        suite.expect(NexusAgentMarkdownBlock.parse("---") == [.divider],
                     "dash divider parses")
        suite.expect(NexusAgentMarkdownBlock.parse("***") == [.divider],
                     "asterisk divider parses")

        // Whitespace and empty
        suite.expect(NexusAgentMarkdownBlock.parse("").isEmpty, "empty text produces no blocks")
        suite.expect(NexusAgentMarkdownBlock.parse("   \n\n\t  ").isEmpty, "whitespace produces no blocks")

        // Mixed document
        let doc = """
        # Title

        Body paragraph.

        - Bullet A
        - Bullet B

        > A quoted notice

        ---
        1. First
        2. Second
        """
        let parsed = NexusAgentMarkdownBlock.parse(doc)
        suite.expect(parsed == [
            .heading(level: 1, text: "Title"),
            .paragraph(text: "Body paragraph."),
            .bulletItem(text: "Bullet A"),
            .bulletItem(text: "Bullet B"),
            .blockquote(text: "A quoted notice"),
            .divider,
            .numberedItem(number: "1", text: "First"),
            .numberedItem(number: "2", text: "Second"),
        ], "mixed document parses into structured blocks: \(parsed)")

        // Mermaid detection in reply blocks
        let reply = "```mermaid\ngraph TD\nA --> B\n```"
        suite.expect(NexusAgentReplyBlock.parse(reply) == [
            .code(language: "mermaid", body: "graph TD\nA --> B"),
        ], "mermaid code fence retains mermaid language")
    }

    // MARK: - Parity: CLI Providers & Arguments

    private static func cliProviders(_ suite: TestSuite) {
        let agy = NexusAgentCLIProvider.antigravity
        let claude = NexusAgentCLIProvider.claude
        let ollama = NexusAgentCLIProvider.ollama
        suite.expect(agy.executableName == "agy", "agy executable is agy")
        suite.expect(claude.executableName == "claude", "claude executable is claude")
        suite.expect(ollama.executableName == "ollama", "ollama executable is ollama")
        suite.expect(NexusAgentCLIProvider.builtIns.count == 3, "there are 3 built-in providers")

        // Provider arguments
        var config = NexusAgentConfiguration()
        config.activeProvider = claude
        let claudeArgs = NexusAgentSupport.agentArguments(prompt: "hello", configuration: config, conversationID: "c1", planMode: true, worktreeMode: true)
        suite.expect(claudeArgs.contains("-p") && claudeArgs.contains("hello") && claudeArgs.contains("--permission-mode") && claudeArgs.contains("-w") && claudeArgs.contains("--resume"),
                     "claude arguments include plan, worktree, and resume")

        config.activeProvider = ollama
        config.model = "qwen2.5-coder:7b"
        let ollamaArgs = NexusAgentSupport.agentArguments(prompt: "build", configuration: config, conversationID: nil, planMode: true, worktreeMode: false)
        suite.expect(ollamaArgs.contains("launch") && ollamaArgs.contains("claude") && ollamaArgs.contains("--model") && ollamaArgs.contains("qwen2.5-coder:7b") && ollamaArgs.contains("--permission-mode"),
                     "ollama arguments launch claude with model and inner flags")

        // Provider switching triggers session refresh with selected provider
        let serviceRig = Rig()
        defer { serviceRig.tearDown() }
        let service = NexusAgentService(environment: serviceRig.environment)
        service.updateActiveProvider(.claude)
        suite.expect(serviceRig.listedProviders.last?.id == NexusAgentCLIProvider.claude.id,
                     "switching active provider refreshes sessions with the selected provider")
    }

    // MARK: - Parity: Metrics & Stream Parsing

    private static func turnMetrics(_ suite: TestSuite) {
        let metrics = NexusAgentTurnMetrics(durationMs: 1250, inputTokens: 500, outputTokens: 150, cachedTokens: 50, numTurns: 2, toolCalls: 3)
        suite.expect(metrics.durationMs == 1250 && metrics.inputTokens == 500 && metrics.outputTokens == 150, "metrics preserve values")

        let resultJson = """
        {"event":"result","result":{"status":"ok","duration_ms":3400,"input_tokens":1200,"output_tokens":450,"cached_tokens":100,"num_turns":1,"tool_calls":2,"response":"Done."}}
        """
        let event = NexusAgentStreamEvent.parse(resultJson)
        if case .finished(_, _, _, _, let parsedMetrics) = event {
            suite.expect(parsedMetrics?.durationMs == 3400 && parsedMetrics?.outputTokens == 450, "result event parsed into finished with metrics")
        } else {
            suite.expect(false, "expected .finished event with metrics: \(String(describing: event))")
        }
    }

    // MARK: - Parity: Pinning & Session Retry

    private static func pinningAndRetry(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.tearDown() }
        let service = NexusAgentService(environment: rig.environment)
        suite.expect(!service.isPinned, "window starts unpinned")
        service.isPinned = true
        suite.expect(service.isPinned, "window can be pinned")

        // Retry tracking
        service.session.lastFailedPrompt = "failed prompt"
        suite.expect(service.session.lastFailedPrompt == "failed prompt", "last failed prompt is retained")
    }

    // MARK: - Live Transcript & Subagents

    private static func liveTranscriptAndSubagents(_ suite: TestSuite) {
        let transcriptRunning = """
        {"step_index":0,"type":"USER_INPUT","content":"Start subagent"}
        {"step_index":1,"type":"PLANNER_RESPONSE","content":"Starting scout","tool_calls":[{"name":"invoke_subagent","args":{"Subagents":"[{\\"Model\\":\\"flash\\",\\"Prompt\\":\\"Monitor CI\\",\\"Role\\":\\"CI Watchdog\\",\\"TypeName\\":\\"scout\\"}]"}}]}
        """
        let active = NexusAgentService.parseActiveSubagents(from: transcriptRunning)
        suite.expect(active.count == 1
                     && active.first?.typeName == "scout"
                     && active.first?.role == "CI Watchdog"
                     && active.first?.prompt == "Monitor CI"
                     && active.first?.model == "flash"
                     && active.first?.isRunning == true,
                     "parseActiveSubagents extracts active subagents from invoke_subagent")

        let transcriptCompleted = """
        {"step_index":0,"type":"USER_INPUT","content":"Start subagent"}
        {"step_index":1,"type":"PLANNER_RESPONSE","content":"Starting scout","tool_calls":[{"name":"invoke_subagent","args":{"Subagents":"[{\\"Model\\":\\"flash\\",\\"Prompt\\":\\"Monitor CI\\",\\"Role\\":\\"CI Watchdog\\",\\"TypeName\\":\\"scout\\"}]"}}]}
        {"step_index":2,"type":"SYSTEM_MESSAGE","content":"[Message] timestamp=2026-10-07T01:54:53Z sender=scout priority=MESSAGE_PRIORITY_HIGH content=Done"}
        """
        let cleared = NexusAgentService.parseActiveSubagents(from: transcriptCompleted)
        suite.expect(cleared.isEmpty,
                     "subagent is marked completed and cleared when completion message arrives")

        let rig = Rig()
        defer { rig.tearDown() }
        let session = NexusAgentQuickPromptSession(environment: rig.environment)
        let convID = "live-test-1"
        let transcriptPath = rig.state + "/transcripts/\(convID).jsonl"
        rig.files[transcriptPath] = transcriptRunning

        session.resume(NexusAgentSessionSummary(id: convID, title: "Live Session", preview: "Start subagent", steps: 2, modified: nil))
        suite.expect(session.isFollowerActive, "resuming in chat mode activates transcript follower")

        session.checkTranscriptUpdates()
        suite.expect(session.activeSubagents.count == 1 && session.activeSubagents.first?.typeName == "scout",
                     "follower updates activeSubagents from transcript")

        rig.files[transcriptPath] = transcriptCompleted
        session.checkTranscriptUpdates()
        suite.expect(session.activeSubagents.isEmpty,
                     "follower clears activeSubagents when transcript changes on disk")

        session.stopTranscriptFollower()
        suite.expect(!session.isFollowerActive, "stopping follower deactivates it")

        // Claude Code tool_use and thinking extraction
        let claudeTranscriptWithTools = """
        {"type":"user","message":{"role":"user","content":"Run tests and monitor CI"}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"I should run git status then launch scout subagent"},{"type":"tool_use","id":"toolu_bash_1","name":"Bash","input":{"command":"git status --porcelain"}},{"type":"tool_use","id":"toolu_task_1","name":"Task","input":{"subagent_type":"scout","description":"Monitor CI checks","prompt":"Watch the CI workflow"}},{"type":"text","text":"I have started the checks."}]}}
        """
        let parsedClaude = NexusAgentService.parseClaudeTranscript(claudeTranscriptWithTools)
        suite.expect(parsedClaude?.count == 2, "claude transcript parses user and assistant turns")
        let assistantMsg = parsedClaude?.last
        suite.expect(assistantMsg?.role == .agent, "second message is agent role")
        suite.expect(assistantMsg?.text == "I have started the checks.", "assistant text extracted")
        suite.expect(assistantMsg?.thinkingText == "I should run git status then launch scout subagent", "thinking block extracted")
        suite.expect(assistantMsg?.toolSteps?.count == 2, "two tool steps extracted")
        suite.expect(assistantMsg?.toolSteps?.first?.title == "git status --porcelain" && assistantMsg?.toolSteps?.first?.detail == "Bash",
                     "Bash tool step extracted with command title and Bash detail")
        suite.expect(assistantMsg?.toolSteps?.last?.title == "Monitor CI checks" && assistantMsg?.toolSteps?.last?.detail == "Task",
                     "Task tool step extracted with description title and Task detail")

        // Claude Code active subagent tracking and clearance
        let claudeSubagentRunning = """
        {"type":"user","message":{"role":"user","content":"Launch subagent"}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_task_42","name":"Task","input":{"subagent_type":"scout","description":"Watch CI Checks","prompt":"Keep polling checks until green"}}]}}
        """
        let activeClaude = NexusAgentService.parseActiveSubagents(from: claudeSubagentRunning)
        suite.expect(activeClaude.count == 1
                     && activeClaude.first?.id == "toolu_task_42"
                     && activeClaude.first?.typeName == "scout"
                     && activeClaude.first?.role == "Watch CI Checks"
                     && activeClaude.first?.prompt == "Keep polling checks until green"
                     && activeClaude.first?.model == "claude"
                     && activeClaude.first?.isRunning == true,
                     "parseActiveSubagents extracts active subagent from Claude Task tool_use")

        let claudeSubagentCompleted = """
        {"type":"user","message":{"role":"user","content":"Launch subagent"}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_task_42","name":"Task","input":{"subagent_type":"scout","description":"Watch CI Checks","prompt":"Keep polling checks until green"}}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_task_42","content":"All checks succeeded!"}]}}
        """
        let clearedClaude = NexusAgentService.parseActiveSubagents(from: claudeSubagentCompleted)
        suite.expect(clearedClaude.isEmpty,
                     "Claude subagent is cleared when matching tool_result arrives")
    }

    // MARK: - Session Archiving Parity

    private static func sessionArchiving(_ suite: TestSuite) {
        defer {
            UserDefaults.standard.removeObject(forKey: "vitruvian.claude.hiddenSessionIds")
        }

        // 1. Antigravity parse: archived comes from the annotations, never from `killed`
        let rows = """
        [
          {"conversation_id":"active-1","title":"Active task","preview":"Working on bug","step_count":3,"last_modified_time":"2026-10-06T10:00:00Z","killed":0},
          {"conversation_id":"archived-1","title":"Old task","preview":"Old completed work","step_count":10,"last_modified_time":"2026-10-05T08:00:00Z","killed":0},
          {"conversation_id":"default-1","title":"Aborted task","preview":"Fresh task","step_count":1,"last_modified_time":"2026-10-06T12:00:00Z","killed":1}
        ]
        """
        let parsed = NexusAgentSessionSummary.parse(Data(rows.utf8), directory: "", archivedIds: ["archived-1"])
        suite.expect(parsed.count == 3, "parses all 3 sessions regardless of archive status")

        let activeSession = parsed.first { $0.id == "active-1" }
        let archivedSession = parsed.first { $0.id == "archived-1" }
        let defaultSession = parsed.first { $0.id == "default-1" }

        suite.expect(activeSession?.isArchived == false, "a session with no archived annotation is active")
        suite.expect(archivedSession?.isArchived == true, "an archived annotation sets isArchived with killed = 0")
        suite.expect(defaultSession?.isArchived == false, "killed = 1 is an aborted run, not an archived one")
        suite.expect(NexusAgentSessionSummary.parse(Data(rows.utf8), directory: "").allSatisfy { !$0.isArchived },
                     "nothing is archived without annotations")
        suite.expect(!NexusAgentSessionSummary.query.contains("killed"), "the drawer's query no longer reads killed")

        // 2. Active vs Archived partitioning
        let activeList = parsed.filter { !$0.isArchived }
        let archivedList = parsed.filter { $0.isArchived }
        suite.expect(activeList.map(\.id) == ["active-1", "default-1"], "active list filters out archived sessions")
        suite.expect(archivedList.map(\.id) == ["archived-1"], "archived list contains only archived sessions")

        // 3. Claude Code hidden session IDs discovery via UserDefaults
        let testClaudeID = "test-claude-session-\(UUID().uuidString)"
        var initialHidden = UserDefaults.standard.stringArray(forKey: "vitruvian.claude.hiddenSessionIds") ?? []
        initialHidden.append(testClaudeID)
        UserDefaults.standard.set(initialHidden, forKey: "vitruvian.claude.hiddenSessionIds")

        let detectedHidden = NexusAgentSessionSummary.claudeHiddenSessionIds(home: "/nonexistent-home")
        suite.expect(detectedHidden.contains(testClaudeID), "claudeHiddenSessionIds includes IDs stored in UserDefaults")

        // 4. Claude Code archiving & unarchiving via service
        let newSessionID = "claude-archive-test-\(UUID().uuidString)"
        NexusAgentService.archiveSession(home: "/nonexistent-home", id: newSessionID, provider: .claude)
        let hiddenAfterArchive = UserDefaults.standard.stringArray(forKey: "vitruvian.claude.hiddenSessionIds") ?? []
        suite.expect(hiddenAfterArchive.contains(newSessionID), "archiveSession adds ID to UserDefaults hiddenSessionIds for claude")

        NexusAgentService.unarchiveSession(home: "/nonexistent-home", id: newSessionID, provider: .claude)
        let hiddenAfterUnarchive = UserDefaults.standard.stringArray(forKey: "vitruvian.claude.hiddenSessionIds") ?? []
        suite.expect(!hiddenAfterUnarchive.contains(newSessionID), "unarchiveSession removes ID from UserDefaults hiddenSessionIds for claude")

        // Clean up test key
        UserDefaults.standard.removeObject(forKey: "vitruvian.claude.hiddenSessionIds")

        // 5. Antigravity annotations, in the shapes agy writes them
        let isArchived = NexusAgentSessionSummary.antigravityAnnotationIsArchived
        suite.expect(isArchived("archived:true archival_status_timestamp:{seconds:1787464769 nanos:503730000} marked_as_unread:false"),
                     "archived:true is archived")
        suite.expect(isArchived("title:\"Daily Briefing\"  archived: true  last_user_view_time:{seconds:1  nanos:2}"),
                     "archived: true is archived")
        suite.expect(!isArchived("last_user_view_time:{seconds:1790974412  nanos:316000000}"), "no archived field is active")
        suite.expect(!isArchived("archived:false pinned:true"), "archived:false is active")
        suite.expect(!isArchived("title:\"why is archived:true ignored\" pinned:true"), "a title cannot pass for the field")
        suite.expect(!isArchived(""), "an empty annotation is active")

        let stamp = Date(timeIntervalSince1970: 1_790_000_000.25)
        let annotated = NexusAgentSessionSummary.antigravityAnnotation(
            "title:\"T\"  last_user_view_time:{seconds:5  nanos:6}", archived: true, now: stamp)
        suite.expect(annotated == "archived:true archival_status_timestamp:{seconds:1790000000 nanos:250000000} "
                        + "title:\"T\"  last_user_view_time:{seconds:5  nanos:6}",
                     "archiving adds archived and its timestamp and keeps the other fields")
        suite.expect(NexusAgentSessionSummary.antigravityAnnotation(annotated, archived: true, now: stamp) == annotated,
                     "archiving twice does not repeat the fields")
        suite.expect(NexusAgentSessionSummary.antigravityAnnotation(annotated, archived: false, now: stamp)
                        == "title:\"T\"  last_user_view_time:{seconds:5  nanos:6}",
                     "unarchiving drops both archive fields and keeps the rest")

        // 6. Antigravity archiving & unarchiving via service, against a throwaway home
        let home = FileManager.default.temporaryDirectory.appending(path: "agy-archive-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let appData = home.appending(path: ".gemini/antigravity")
        let cliData = home.appending(path: ".gemini/antigravity-cli")
        for folder in [appData.appending(path: "annotations"), cliData.appending(path: "conversations")] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try? "archived:true archival_status_timestamp:{seconds:1 nanos:2}"
            .write(to: appData.appending(path: "annotations/was-archived.pbtxt"), atomically: true, encoding: .utf8)
        try? "pinned:true".write(to: appData.appending(path: "annotations/seen.pbtxt"), atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: cliData.appending(path: "conversations/cli-1.db").path, contents: nil)
        let archivedIds = { NexusAgentSessionSummary.antigravityArchivedSessionIds(home: home.path) }
        suite.expect(archivedIds() == ["was-archived"], "only annotations marked archived count")

        NexusAgentService.archiveSession(home: home.path, id: "seen", provider: .antigravity)
        NexusAgentService.archiveSession(home: home.path, id: "brand-new", provider: .antigravity)
        NexusAgentService.archiveSession(home: home.path, id: "cli-1", provider: .antigravity)
        NexusAgentService.archiveSession(home: home.path, id: "../escape", provider: .antigravity)
        suite.expect(archivedIds() == ["was-archived", "seen", "brand-new", "cli-1"],
                     "archiveSession updates or creates the annotation")
        let seen = (try? String(contentsOf: appData.appending(path: "annotations/seen.pbtxt"), encoding: .utf8)) ?? ""
        suite.expect(seen.hasPrefix("archived:true archival_status_timestamp:{seconds:") && seen.hasSuffix(" pinned:true"),
                     "archiveSession keeps the fields agy already wrote")
        suite.expect(FileManager.default.fileExists(atPath: cliData.appending(path: "annotations/cli-1.pbtxt").path),
                     "a CLI conversation is annotated beside its own data")
        suite.expect(!FileManager.default.fileExists(atPath: home.appending(path: ".gemini/antigravity/escape.pbtxt").path),
                     "an id cannot write outside the annotations folder")

        for id in ["seen", "cli-1", "was-archived", "never-annotated"] {
            NexusAgentService.unarchiveSession(home: home.path, id: id, provider: .antigravity)
        }
        suite.expect(archivedIds() == ["brand-new"], "unarchiveSession clears the annotation")
        suite.expect((try? String(contentsOf: appData.appending(path: "annotations/seen.pbtxt"), encoding: .utf8)) == "pinned:true",
                     "unarchiveSession leaves the other fields as they were")
        suite.expect(!FileManager.default.fileExists(atPath: appData.appending(path: "annotations/never-annotated.pbtxt").path),
                     "unarchiving a session with no annotation writes nothing")

        // 7. Session summary struct init
        let explicitArchived = NexusAgentSessionSummary(id: "s-archived", title: "T", preview: "P", steps: 1, modified: nil, isArchived: true)
        let explicitActive = NexusAgentSessionSummary(id: "s-active", title: "T", preview: "P", steps: 1, modified: nil, isArchived: false)
        let defaultActive = NexusAgentSessionSummary(id: "s-default", title: "T", preview: "P", steps: 1, modified: nil)
        suite.expect(explicitArchived.isArchived, "explicitly archived summary has isArchived = true")
        suite.expect(!explicitActive.isArchived, "explicitly active summary has isArchived = false")
        suite.expect(!defaultActive.isArchived, "default summary has isArchived = false")
    }

    // MARK: - Claude Session Titles & Scheduled Task Parity

    private static func claudeSessionTitles(_ suite: TestSuite) {
        // 1. Task name formatting
        suite.expect(NexusAgentSessionSummary.formatTaskName("track-zitadel-login-2fa-fix") == "Track zitadel login 2fa fix",
                     "formatTaskName converts hyphens to spaces and capitalizes first word")
        suite.expect(NexusAgentSessionSummary.formatTaskName("daily_ci_pipeline_hygiene") == "Daily ci pipeline hygiene",
                     "formatTaskName converts underscores to spaces and capitalizes first word")

        // 2. Extract scheduled task name from XML tags
        let taskXMLDoubleQuote = "<scheduled-task name=\"track-zitadel-login-2fa-fix\" file=\"/path/to/task.md\">\nTask content\n</scheduled-task>"
        suite.expect(NexusAgentSessionSummary.extractScheduledTaskName(taskXMLDoubleQuote) == "Track zitadel login 2fa fix",
                     "extractScheduledTaskName extracts double-quoted task name")

        let taskXMLSingleQuote = "<scheduled-task name='daily-ci-pipeline-hygiene'>\nCheck pipeline\n</scheduled-task>"
        suite.expect(NexusAgentSessionSummary.extractScheduledTaskName(taskXMLSingleQuote) == "Daily ci pipeline hygiene",
                     "extractScheduledTaskName extracts single-quoted task name")

        suite.expect(NexusAgentSessionSummary.extractScheduledTaskName("No scheduled task here") == nil,
                     "extractScheduledTaskName returns nil when no scheduled task tag is present")

        // 3. User prompt sanitization (XML stripping)
        let rawPromptWithTaskAndReminder = """
        <system-reminder>
        UserPromptSubmit hook success
        </system-reminder>
        <scheduled-task name="track-zitadel-login-2fa-fix" file="/some/path">
        Please investigate the Zitadel 2FA issue.
        </scheduled-task>
        """
        let cleanedPrompt = NexusAgentSessionSummary.extractUserPrompt(rawPromptWithTaskAndReminder)
        suite.expect(cleanedPrompt == "Please investigate the Zitadel 2FA issue.",
                     "extractUserPrompt strips both system-reminder and scheduled-task tags, preserving body text")

        // 4. File-based Claude session title discovery
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-titles-test-\(UUID().uuidString)")
        let projectsDir = tmpDir.appendingPathComponent(".claude/projects/-test-project")
        try? FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }

        // Case A: Custom title from companion custom-title.json
        let sessionADir = projectsDir.appendingPathComponent("session-a")
        try? FileManager.default.createDirectory(at: sessionADir, withIntermediateDirectories: true)
        let customTitleJSON = "{\"customTitle\": \"Companion File Title\"}"
        try? customTitleJSON.write(to: sessionADir.appendingPathComponent("custom-title.json"), atomically: true, encoding: .utf8)
        let sessionAJSONL = "{\"type\":\"user\",\"content\":\"some user content\"}\n"
        try? sessionAJSONL.write(to: projectsDir.appendingPathComponent("session-a.jsonl"), atomically: true, encoding: .utf8)

        // Case B: In-stream custom-title event
        let sessionBJSONL = """
        {"type":"custom-title","customTitle":"Stream Custom Title"}
        {"type":"user","content":"User prompt for stream test"}
        """
        try? sessionBJSONL.write(to: projectsDir.appendingPathComponent("session-b.jsonl"), atomically: true, encoding: .utf8)

        // Case C: In-stream agent-name event
        let sessionCJSONL = """
        {"type":"agent-name","agentName":"Agent Name Title"}
        {"type":"user","content":"User prompt for agent name"}
        """
        try? sessionCJSONL.write(to: projectsDir.appendingPathComponent("session-c.jsonl"), atomically: true, encoding: .utf8)

        // Case D: Scheduled task fallback title and clean preview
        let sessionDJSONL = """
        {"type":"queue-operation","operation":"enqueue","content":"<scheduled-task name=\\"track-zitadel-login-2fa-fix\\">Check Zitadel 2FA issue</scheduled-task>"}
        {"type":"user","message":{"role":"user","content":"<scheduled-task name=\\"track-zitadel-login-2fa-fix\\">Check Zitadel 2FA issue</scheduled-task>"}}
        """
        try? sessionDJSONL.write(to: projectsDir.appendingPathComponent("session-d.jsonl"), atomically: true, encoding: .utf8)

        // Case E: Regular fallback prompt
        let sessionEJSONL = """
        {"type":"user","message":{"role":"user","content":"Regular user question without title"}}
        """
        try? sessionEJSONL.write(to: projectsDir.appendingPathComponent("session-e.jsonl"), atomically: true, encoding: .utf8)

        let sessions = NexusAgentSessionSummary.parseClaudeSessions(home: tmpDir.path, directory: "/test/project")
        let summaryA = sessions.first { $0.id == "session-a" }
        let summaryB = sessions.first { $0.id == "session-b" }
        let summaryC = sessions.first { $0.id == "session-c" }
        let summaryD = sessions.first { $0.id == "session-d" }
        let summaryE = sessions.first { $0.id == "session-e" }

        suite.expect(summaryA?.title == "Companion File Title",
                     "Session A resolves title from companion custom-title.json")
        suite.expect(summaryB?.title == "Stream Custom Title",
                     "Session B resolves title from in-stream custom-title event")
        suite.expect(summaryC?.title == "Agent Name Title",
                     "Session C resolves title from in-stream agent-name event")
        suite.expect(summaryD?.title == "Track zitadel login 2fa fix",
                     "Session D resolves title from scheduled-task name attribute")
        suite.expect(summaryD?.preview == "Check Zitadel 2FA issue",
                     "Session D preview is sanitized to exclude scheduled-task XML tags")
        suite.expect(summaryE?.title == "Regular user question without title",
                     "Session E falls back to first line of preview")
    }

    // MARK: - Claude Enhancements & Interactive Approvals

    private static func claudeEnhancementsAndApprovals(_ suite: TestSuite) {
        // Option A: Plan mode uses --append-system-prompt and --permission-mode plan
        var config = NexusAgentConfiguration()
        config.activeProvider = NexusAgentCLIProvider.claude
        let claudePlanArgs = NexusAgentSupport.agentArguments(prompt: "Review architecture", configuration: config, conversationID: "c1", planMode: true)
        suite.expect(claudePlanArgs.contains("--append-system-prompt"), "Claude plan mode uses --append-system-prompt")
        suite.expect(!claudePlanArgs.contains("--system-prompt"), "Claude plan mode does not overwrite system prompt")
        suite.expect(claudePlanArgs.contains("--permission-mode") && claudePlanArgs.contains("plan"), "Claude plan mode passes permission-mode plan")
        suite.expect(claudePlanArgs.contains("--output-format") && claudePlanArgs.contains("stream-json") && claudePlanArgs.contains("--include-partial-messages"), "Claude includes partial messages for real-time streaming")

        // Option B: Real-time token streaming and result metrics parsing
        let deltaJson = #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Streaming token"}}}"#
        let deltaEvent = NexusAgentStreamEvent.parse(deltaJson)
        suite.expect(deltaEvent == .text("Streaming token"), "Claude content_block_delta parses into .text stream event")

        let toolUseJson = #"{"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"tool_use","id":"tool_call_1","name":"Bash","input":{"command":"git status"}}}}"#
        let toolEvent = NexusAgentStreamEvent.parse(toolUseJson)
        if case .approval(let req) = toolEvent {
            suite.expect(req.id == "tool_call_1" && req.toolName == "Bash" && req.commandOrPath == "git status" && req.status == .pending,
                         "Claude tool_use parses into pending approval request")
        } else {
            suite.expect(false, "Expected .approval event from tool_use block")
        }

        let resultJson = """
        {"type":"result","duration_ms":2200,"total_cost_usd":0.045,"usage":{"input_tokens":850,"output_tokens":320,"cache_read_input_tokens":120},"num_turns":1,"stop_reason":"end_turn","result":"Task completed successfully."}
        """
        let resultEvent = NexusAgentStreamEvent.parse(resultJson)
        if case .finished(let status, let response, _, _, let metrics) = resultEvent {
            suite.expect(status == "end_turn" && response == "Task completed successfully.", "Claude result event parsed correctly")
            suite.expect(metrics?.durationMs == 2200 && metrics?.inputTokens == 850 && metrics?.outputTokens == 320 && metrics?.cachedTokens == 120 && metrics?.totalCostUSD == 0.045,
                         "Claude result metrics parse duration, tokens, and USD cost")
        } else {
            suite.expect(false, "Expected .finished event with metrics from Claude result JSON")
        }

        // Option C: Interactive approval state transitions
        let rig = Rig()
        defer { rig.tearDown() }
        let service = NexusAgentService(environment: rig.environment)
        let initialReq = NexusAgentApprovalRequest(id: "req_1", toolName: "Bash", commandOrPath: "rm -rf /tmp/cache", status: .pending)
        let msg = NexusAgentChatMessage(role: .agent, text: "", approvalRequest: initialReq)
        service.session.messages = [msg]

        service.session.decideApproval(messageID: msg.id, decision: .approved)
        suite.expect(service.session.messages.first?.approvalRequest?.status == .approved, "decideApproval updates status to approved")

        service.session.decideApproval(messageID: msg.id, decision: .denied)
        suite.expect(service.session.messages.first?.approvalRequest?.status == .denied, "decideApproval updates status to denied")

        service.session.decideApproval(messageID: msg.id, decision: .sessionAllowed)
        suite.expect(service.session.messages.first?.approvalRequest?.status == .sessionAllowed, "decideApproval updates status to sessionAllowed")
    }

    // MARK: - Notch Integration

    private static func notchIntegration(_ suite: TestSuite) {
        // 1. NotchAgentTab enum cases
        suite.expect(NotchAgentTab.allCases == [.chat, .telemetry], "NotchAgentTab supports chat and telemetry")
        suite.expect(NotchAgentTab.chat.id == "chat" && NotchAgentTab.telemetry.id == "telemetry", "NotchAgentTab ids match raw values")

        // 2. NotchService agentTab default and mutations
        let notchService = NotchService.shared
        let originalTab = notchService.agentTab
        defer { notchService.agentTab = originalTab }

        notchService.agentTab = .telemetry
        suite.expect(notchService.agentTab == .telemetry, "NotchService agentTab can be set to telemetry")
        notchService.agentTab = .chat
        suite.expect(notchService.agentTab == .chat, "NotchService agentTab can be set to chat")

        // 3. NotchNotice creation for agent events
        let notice = NotchNotice(
            event: .agents,
            title: "Agent — Done",
            detail: "Task completed",
            symbol: "sparkles"
        )
        suite.expect(notice.event == .agents, "NotchNotice event is .agents")
        suite.expect(notice.title == "Agent — Done", "NotchNotice title is preserved")
        suite.expect(notice.symbol == "sparkles", "NotchNotice symbol is preserved")

        // 4. NexusAgentQuickPromptSession live activity & running state
        let rig = Rig()
        defer { rig.tearDown() }
        let service = NexusAgentService(environment: rig.environment)
        suite.expect(!service.session.isRunning, "Session is initially not running")
        suite.expect(service.session.activity == nil, "Initial activity is nil")

        // 5. Pop out and dock navigation
        notchService.popOutToQuickPrompt()
        suite.expect(service.session.mode == .compact || service.session.mode == .chat, "popOutToQuickPrompt initiates quick prompt presentation")

        service.dockToNotch()
        suite.expect(notchService.agentTab == .chat, "dockToNotch sets agentTab to chat")

        // 6. Title is AI Agents
        suite.expect(FeatureStrings.notchAgents(.enUS).title == "AI Agents", "enUS title is AI Agents")
    }

    // MARK: - Antigravity Telemetry & Quota

    private static func antigravityTelemetry(_ suite: TestSuite) {
        // 1. AgentProvider metadata
        suite.expect(AgentProvider.antigravity.displayName == "Antigravity", "displayName is Antigravity")
        suite.expect(AgentProvider.antigravity.symbol == "sparkles", "symbol is sparkles")
        suite.expect(AgentProvider.antigravity.reportsLimits == true, "reportsLimits is true")

        // 2. Pricing and model display names
        suite.expect(AgentPricing.displayName("gemini-3.8-flash") == "Gemini 3.8 Flash", "gemini-3.8-flash formats correctly")
        suite.expect(AgentPricing.displayName("gemini-3-pro") == "Gemini 3 Pro", "gemini-3-pro formats correctly")
        suite.expect(AgentPricing.displayName("gemini-3.7-flash") == "Gemini 3.7 Flash", "gemini-3.7-flash formats correctly")
        suite.expect(AgentPricing.price(for: "gemini-3.8-flash") != nil, "gemini-3.8-flash price exists")
        suite.expect(AgentPricing.price(for: "gemini-3-pro") != nil, "gemini-3-pro price exists")

        // 3. Telemetry State JSON Parsing
        let telemetryJson = """
        {
          "/Users/james/.gemini/antigravity/brain/test-conv-123/.system_generated/logs/transcript.jsonl": {
            "turns": 5,
            "tokens": {
              "input": 20000,
              "output": 1000,
              "cached": 50000,
              "thinking": 100
            },
            "mtime": 1783527878.0,
            "model": "gemini-3.7-flash"
          }
        }
        """
        let records = AgentAntigravityReader.parseTelemetryState(Data(telemetryJson.utf8), projects: ["test-conv-123": "vitruvian-core"])
        suite.expect(records.count == 1, "parseTelemetryState produces 1 record")
        if let r = records.first {
            suite.expect(r.provider == .antigravity, "provider is antigravity")
            suite.expect(r.model == "gemini-3.7-flash", "model matches")
            suite.expect(r.project == "vitruvian-core", "project matches lookup")
            suite.expect(r.session == "test-conv-123", "session is conversation id")
            suite.expect(r.tokens.input == 20000 && r.tokens.output == 1000 && r.tokens.cacheRead == 50000 && r.tokens.reasoning == 100, "tokens match")
            suite.expect(r.cost != nil && r.cost! > 0, "cost is computed from Gemini pricing")
        }

        // 4. Quota Response JSON Parsing
        let quotaJson = """
        {
          "groups": [
            {
              "displayName": "Gemini Models",
              "buckets": [
                {
                  "bucketId": "gemini-weekly",
                  "remainingFraction": 0.85,
                  "resetTime": "2026-10-15T00:00:00Z"
                },
                {
                  "bucketId": "gemini-5h",
                  "remainingFraction": 0.60,
                  "resetTime": "2026-10-08T06:00:00Z"
                }
              ]
            },
            {
              "displayName": "Claude and GPT models",
              "buckets": [
                {
                  "bucketId": "3p-weekly",
                  "remainingFraction": 0.50,
                  "resetTime": "2026-10-15T00:00:00Z"
                }
              ]
            }
          ]
        }
        """
        let limits = AgentAntigravityReader.parseQuotaResponse(Data(quotaJson.utf8), observed: Date())
        suite.expect(limits != nil, "parseQuotaResponse succeeds")
        suite.expect(limits?.provider == .antigravity, "provider is antigravity")
        suite.expect(limits?.windows.count == 3, "parsed 3 limit windows")
        if let weekly = limits?.windows.first(where: { $0.id == "gemini-weekly" }) {
            suite.expect(weekly.kind == .weekly, "gemini-weekly kind is weekly")
            suite.expect(weekly.minutes == 10080, "weekly minutes is 10080")
            suite.expect(abs(weekly.usedPercent - 15.0) < 0.001, "usedPercent is 15%")
            suite.expect(weekly.scope == nil, "gemini-weekly scope is nil for plan-wide focus")
        }
        if let session = limits?.windows.first(where: { $0.id == "gemini-5h" }) {
            suite.expect(session.kind == .session, "gemini-5h kind is session")
            suite.expect(session.minutes == 300, "session minutes is 300")
            suite.expect(abs(session.usedPercent - 40.0) < 0.001, "usedPercent is 40%")
            suite.expect(session.scope == nil, "gemini-5h scope is nil for plan-wide focus")
        }
        if let tpWeekly = limits?.windows.first(where: { $0.id == "3p-weekly" }) {
            suite.expect(tpWeekly.scope == "Claude and GPT models", "3p-weekly scope is preserved")
        }

        // Connect-RPC Response Wrapper
        let wrappedJson = "{\"response\": \(quotaJson)}"
        let wrappedLimits = AgentAntigravityReader.parseQuotaResponse(Data(wrappedJson.utf8), observed: Date())
        suite.expect(wrappedLimits != nil && wrappedLimits?.windows.count == 3, "parseQuotaResponse parses Connect-RPC response wrapper")

        // 5. File Stat Caching & Incremental Reading
        AgentAntigravityReader.resetCache()
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "antigravity-test-\(UUID().uuidString)")
        let geminiDir = tempDir.appending(path: ".gemini/antigravity")
        try? FileManager.default.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateFile = geminiDir.appending(path: ".telemetry_state.json")
        try? Data(telemetryJson.utf8).write(to: stateFile)
        let store = AgentUsageStore()
        let didReadFirst = AgentAntigravityReader.read(store: store, enabled: [.antigravity], home: tempDir, now: Date())
        suite.expect(didReadFirst, "first read returns true and applies records")
        suite.expect(store.records.count == 1, "store contains 1 record after first read")

        let didReadSecond = AgentAntigravityReader.read(store: store, enabled: [.antigravity], home: tempDir, now: Date())
        suite.expect(!didReadSecond, "second read without file modification returns false immediately")

        // 6. Quota Probe Throttle Window
        let probe1 = AgentAntigravityReader.probeQuota()
        let probe2 = AgentAntigravityReader.probeQuota()
        suite.expect(probe1 == probe2, "repeated probeQuota within throttle window returns cached value")

        // 7. Store limits change detection
        let sampleLimits = AgentAntigravityReader.parseQuotaResponse(Data(quotaJson.utf8), observed: Date())!
        store.updateLimits(sampleLimits)
        suite.expect(store.limits[.antigravity] == sampleLimits, "store retains applied limits")
        suite.expect(store.limits[.antigravity] == sampleLimits, "store limit equality matches")
    }
}

