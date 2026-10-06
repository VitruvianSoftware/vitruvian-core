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
}
