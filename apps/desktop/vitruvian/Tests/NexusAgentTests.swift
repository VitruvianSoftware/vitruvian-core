// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Combine
import Darwin
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Nexus Agent: the catalog wiring, and the service and Quick Prompt over a
/// fake Mac. The pure rules (the `.env`, the agent's arguments and stream,
/// the Quick Prompt layout, session titles) are tested beside the shared code,
/// in `apps/desktop/nexus-agent/macos/Tests/PortedRulesTests.swift`.
enum NexusAgentTests {
    static func run(_ suite: TestSuite) {
        wiring(suite)
        botLifecycle(suite)
        autoStart(suite)
        configurationSaving(suite)
        quickPrompt(suite)
        quickPromptModes(suite)
        transcriptParsing(suite)
        cliProviders(suite)
        pinningAndRetry(suite)
        liveTranscriptAndSubagents(suite)
        sessionArchiving(suite)
        sessionDeleting(suite)
        claudeEnhancementsAndApprovals(suite)
        notchIntegration(suite)
        antigravityTelemetry(suite)
        hostReadsLive(suite)
        hostRemembersProviders(suite)
        hostRemembersHistoryAndWorktreeMode(suite)
        backupDoesNotCarryProviderCommands(suite)
        hostTurnNotices(suite)
        changesReachTheViews(suite)
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
        /// The SQL the service asked SQLite to run, and the files it asked to have removed.
        var sqliteRuns: [String] = []
        var removed: [String] = []
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
                removeFile: { [unowned self] in
                    removed.append($0)
                    files[$0] = nil
                },
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
                listSessions: { [unowned self] directory, provider, _ in
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
                },
                runSqlite: { [unowned self] _, sql, _ in
                    sqliteRuns.append(sql)
                    return Data()
                })
        }
    }

    // MARK: - Deleting agy conversations

    /// The drawer's Delete item goes through the shared session. The rules
    /// are tested beside the shared code; here, that this app's service
    /// does it in its own environment, refuses a Claude session, and that
    /// the item has a label.
    private static func sessionDeleting(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.tearDown() }
        let data = rig.home + "/.gemini/antigravity"
        rig.files[data + "/conversation_summaries.db"] = ""
        let service = NexusAgentService(environment: rig.environment)
        let summary = NexusAgentSessionSummary(id: "abc-1", title: "T", steps: 1, modified: nil)
        let removedBefore = rig.removed.count
        let listedBefore = rig.listedProviders.count

        let deleted = service.session.delete(summary, configuration: service.configuration)
        suite.expect(deleted
                     && rig.sqliteRuns == ["DELETE FROM conversation_summaries WHERE conversation_id = 'abc-1';"]
                     && Array(rig.removed.dropFirst(removedBefore)) == [data + "/conversations/abc-1.db",
                                                                        data + "/conversations/abc-1.db-wal",
                                                                        data + "/conversations/abc-1.db-shm"],
                     "deleting an agy conversation takes its row out of the index and removes its three files")
        suite.expect(rig.listedProviders.count == listedBefore + 1, "the drawer's list is read again after a delete")

        service.updateActiveProvider(.claude)
        let refused = !service.session.delete(summary, configuration: service.configuration)
        suite.expect(refused && rig.sqliteRuns.count == 1 && rig.removed.count == removedBefore + 3,
                     "a Claude session is not deleted")
        suite.expect(service.hostStrings.deleteSession == "Delete", "the Delete item has a label")
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
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: VitruvianNexusAgentHost(defaults: rig.defaults))
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

    private static func quickPromptModes(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.tearDown() }
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: VitruvianNexusAgentHost(defaults: rig.defaults))
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
        suite.expect(NexusAgentQuickPromptSession(environment: rig.environment, host: VitruvianNexusAgentHost(defaults: rig.defaults)).planMode,
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
        config.model = ""
        let lookedUp = NexusAgentSupport.agentArguments(prompt: "build", configuration: config, conversationID: nil,
                                                        ollamaDefaultModel: "llama3.2:latest")
        let notLookedUp = NexusAgentSupport.agentArguments(prompt: "build", configuration: config, conversationID: nil)
        suite.expect(Array(lookedUp.prefix(4)) == ["launch", "claude", "--model", "llama3.2:latest"]
                     && Array(notLookedUp.prefix(4)) == ["launch", "claude", "--model", "qwen3"],
                     "ollama with no model set runs the model it was found to have, or a fixed one, never \"default\"")

        // Provider switching triggers session refresh with selected provider
        let serviceRig = Rig()
        defer { serviceRig.tearDown() }
        let service = NexusAgentService(environment: serviceRig.environment)
        service.updateActiveProvider(.claude)
        suite.expect(serviceRig.listedProviders.last?.id == NexusAgentCLIProvider.claude.id,
                     "switching active provider refreshes sessions with the selected provider")
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
        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: VitruvianNexusAgentHost(defaults: rig.defaults))
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

        let detectedHidden = NexusAgentSessionSummary.claudeHiddenSessionIds(
            home: "/nonexistent-home", appHidden: VitruvianNexusAgentHost.savedHiddenClaudeSessionIDs)
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

    // MARK: - The engine's host

    /// The host answers from the saved settings at the moment it is asked.
    /// The suite's name is a literal in the swept namespace, as
    /// `PreferenceNamespaceTests` requires, and is emptied before use.
    private static func hostReadsLive(_ suite: TestSuite) {
        let name = "com.vitruviansoftware.vitruvian.tests.nexus-agent-host"
        guard let defaults = UserDefaults(suiteName: name) else {
            suite.expect(false, "a private defaults suite can be made")
            return
        }
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let host = VitruvianNexusAgentHost(defaults: defaults)

        defaults[Preferences.nexusAgentBotDirectory] = "~/one"
        suite.expect(host.configuredBotDirectory == "~/one", "the host reads the bot folder")
        defaults[Preferences.nexusAgentBotDirectory] = "~/two"
        suite.expect(host.configuredBotDirectory == "~/two", "a changed bot folder is seen without a restart")

        defaults[Preferences.nexusAgentAutoStart] = true
        suite.expect(host.startsBotAtLaunch, "the host reads start-with-app")
        defaults[Preferences.nexusAgentAutoStart] = false
        suite.expect(!host.startsBotAtLaunch, "a changed start-with-app is seen without a restart")

        host.planMode = true
        suite.expect(defaults[Preferences.nexusAgentPlanMode], "plan mode is saved through the host")
        suite.expect(host.strings.untitledSession
                     == FeatureStrings.nexusAgent(L10n.shared.language).untitledSession,
                     "text comes from the app's translations")
    }

    /// The provider the user chose, and any providers of their own, are
    /// saved settings of this app: the host stores and returns both, live,
    /// and a service built later starts on the same choice.
    private static func hostRemembersProviders(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.tearDown() }
        let defaults = rig.defaults
        let host = VitruvianNexusAgentHost(defaults: defaults)
        suite.expect(host.chosenProviderID == nil && host.savedProviders.isEmpty,
                     "nothing is chosen or saved to begin with")

        host.chosenProviderID = NexusAgentCLIProvider.claude.id
        suite.expect(defaults[Preferences.nexusAgentChosenProvider] == NexusAgentCLIProvider.claude.id.uuidString,
                     "the chosen provider is saved as its id")
        defaults[Preferences.nexusAgentChosenProvider] = NexusAgentCLIProvider.ollama.id.uuidString
        suite.expect(host.chosenProviderID == NexusAgentCLIProvider.ollama.id,
                     "a changed choice is seen without a restart")
        host.chosenProviderID = nil
        suite.expect(defaults[Preferences.nexusAgentChosenProvider].isEmpty && host.chosenProviderID == nil,
                     "no choice is saved as nothing")

        let own = NexusAgentCLIProvider(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                                        name: "My script", commandTemplate: "ask {prompt}", isBuiltIn: false)
        host.savedProviders = [own]
        suite.expect(VitruvianNexusAgentHost(defaults: defaults).savedProviders == [own],
                     "the user's own providers are saved and read back")
        defaults[Preferences.nexusAgentSavedProviders] = Data("not json".utf8)
        suite.expect(host.savedProviders.isEmpty, "saved providers that cannot be read are none")
        host.savedProviders = [own]

        let service = NexusAgentService(environment: rig.environment)
        suite.expect(service.activeProvider == .antigravity && service.providers == NexusAgentCLIProvider.builtIns + [own],
                     "the service offers the built-in providers, then the user's own")
        service.updateActiveProvider(.claude)
        suite.expect(defaults[Preferences.nexusAgentChosenProvider] == NexusAgentCLIProvider.claude.id.uuidString,
                     "choosing a provider in the chat saves it")
        rig.installBot()
        service.load()
        suite.expect(service.activeProvider == .claude, "the choice survives reading the bot's settings again")
        var next = service.configuration
        next.model = "m"
        suite.expect(service.save(next) && service.activeProvider == .claude, "and saving them")
        suite.expect(NexusAgentService(environment: rig.environment).activeProvider == .claude,
                     "the next launch starts on the chosen provider")
    }

    /// The prompts the arrows walk through and worktree mode outlive the
    /// app: the host stores both, live, and the next Quick Prompt starts
    /// with them. The prompts stay on this Mac.
    private static func hostRemembersHistoryAndWorktreeMode(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.tearDown() }
        let defaults = rig.defaults
        let host = VitruvianNexusAgentHost(defaults: defaults)
        suite.expect(host.promptHistory.isEmpty && !host.worktreeMode, "no history and no worktree mode to begin with")

        host.promptHistory = ["one", "two"]
        suite.expect(defaults[Preferences.nexusAgentPromptHistory] == ["one", "two"], "prompt history is saved through the host")
        defaults[Preferences.nexusAgentPromptHistory] = ["three"]
        suite.expect(host.promptHistory == ["three"], "changed history is seen without a restart")
        host.worktreeMode = true
        suite.expect(defaults[Preferences.nexusAgentWorktreeMode], "worktree mode is saved through the host")
        defaults[Preferences.nexusAgentWorktreeMode] = false
        suite.expect(!host.worktreeMode, "a changed worktree mode is seen without a restart")

        let session = NexusAgentQuickPromptSession(environment: rig.environment, host: host)
        suite.expect(session.promptHistory == ["three"] && !session.worktreeMode,
                     "a new prompt starts with the remembered history")
        session.send("four", configuration: NexusAgentConfiguration(), agentPath: nil)
        session.send("three", configuration: NexusAgentConfiguration(), agentPath: nil)
        session.worktreeMode = true
        suite.expect(defaults[Preferences.nexusAgentPromptHistory] == ["three", "four"]
                     && defaults[Preferences.nexusAgentWorktreeMode],
                     "a sent prompt is remembered once, and worktree mode when it changes")
        let later = NexusAgentQuickPromptSession(environment: rig.environment,
                                                 host: VitruvianNexusAgentHost(defaults: defaults))
        suite.expect(later.promptHistory == ["three", "four"] && later.worktreeMode,
                     "the next launch has both")

        suite.expect(SettingsBackupSupport.machineStateKeys.contains(DefaultsKey.nexusAgentPromptHistory)
                     && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.nexusAgentPromptHistory),
                     "what the user typed to the agent is not carried by a backup")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.nexusAgentWorktreeMode)
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.nexusAgentChosenProvider),
                     "worktree mode and the chosen provider are settings a backup carries")
    }

    /// A saved provider's command is run as a program, so importing someone
    /// else's backup must never be a way to install one. The choice of
    /// provider (an id) is harmless and still travels.
    private static func backupDoesNotCarryProviderCommands(_ suite: TestSuite) {
        suite.expect(SettingsBackupSupport.machineStateKeys.contains(DefaultsKey.nexusAgentSavedProviders)
                     && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.nexusAgentSavedProviders),
                     "saved provider commands are not carried by a backup")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.nexusAgentChosenProvider),
                     "the chosen provider still is")

        // The way in matters as much as the way out: a file someone edited
        // by hand can name saved providers, and those must not be restored.
        let chosen = "AAAAAAAA-0000-0000-0000-00000000000A"
        let hostile = Data(#"[{"id":"\#(chosen)","name":"x","commandTemplate":"sh -c {prompt}","isBuiltIn":false}]"#.utf8)
        let incoming: [String: Any] = [
            SettingsBackupSupport.formatVersionKey: SettingsBackupSupport.formatVersion,
            SettingsBackupSupport.settingsKey: [
                DefaultsKey.nexusAgentSavedProviders: hostile,
                DefaultsKey.nexusAgentChosenProvider: chosen,
            ] as [String: Any],
        ]
        let restored = SettingsBackupSupport.sanitizedSettings(from: incoming)
        suite.expect(restored != nil && restored?[DefaultsKey.nexusAgentSavedProviders] == nil,
                     "saved provider commands in an incoming backup are dropped")
        suite.expect(restored?[DefaultsKey.nexusAgentChosenProvider] as? String == chosen,
                     "the chosen provider in an incoming backup is kept")
    }

    /// What Vitruvian tells the user when a turn ends or waits: the notch
    /// notice always, the notification only away from the chat.
    private static func hostTurnNotices(_ suite: TestSuite) {
        typealias Host = VitruvianNexusAgentHost
        let strings = NexusAgentHostStrings()
        let long = String(repeating: "a", count: 300)

        let failed = Host.announcement(
            finished: NexusAgentTurnNotice(providerName: "Claude", text: long, failed: true, endedCleanly: false),
            isChatVisible: false, strings: strings)
        suite.expect(failed.notificationTitle == "Claude — Failed" && failed.notificationBody == String(long.prefix(200))
                     && failed.notificationBody?.count == 200,
                     "a failed turn away from the chat notifies with the reply cut to 200 characters")
        suite.expect(failed.notchTitle == "Claude — Failed" && failed.notchSymbol == "exclamationmark.triangle.fill"
                     && !failed.playsSound,
                     "a failed turn shows a warning in the notch and plays no sound")

        let reply = "\n   \n" + long + "\nsecond line"
        let done = NexusAgentTurnNotice(providerName: "Claude", text: reply, failed: false, endedCleanly: true)
        let hidden = Host.announcement(finished: done, isChatVisible: false, strings: strings)
        suite.expect(hidden.notificationTitle == "Claude — Done" && hidden.notificationBody == String(long.prefix(200)),
                     "a finished turn away from the chat notifies with its first non-blank line cut to 200 characters")
        suite.expect(hidden.notchTitle == "Claude — Done" && hidden.notchDetail == String(long.prefix(80))
                     && hidden.notchDetail.count == 80 && hidden.notchSymbol == "sparkles" && hidden.playsSound,
                     "the notch shows the first non-blank line cut to 80 characters, and a clean turn plays the sound")

        let visible = Host.announcement(finished: done, isChatVisible: true, strings: strings)
        suite.expect(visible.notificationTitle == nil && visible.notificationBody == nil
                     && visible.notchTitle == hidden.notchTitle && visible.notchDetail == hidden.notchDetail
                     && visible.playsSound,
                     "with the chat on screen there is no notification, only the notch and the sound")

        let empty = Host.announcement(
            finished: NexusAgentTurnNotice(providerName: "Claude", text: "", failed: false, endedCleanly: true),
            isChatVisible: false, strings: strings)
        suite.expect(empty.notificationTitle == nil && empty.notificationBody == nil && empty.notchTitle == "Claude — Done",
                     "a turn that ended with no reply and no error does not notify")

        let approval = Host.announcement(
            needingApproval: NexusAgentTurnNotice(providerName: "Claude", text: "Bash: rm -rf /tmp/cache",
                                                  failed: false, endedCleanly: false),
            strings: strings)
        suite.expect(approval.notchTitle == "Claude — Approval Required" && approval.notchDetail == "Bash: rm -rf /tmp/cache"
                     && approval.notchSymbol == "hand.raised.fill" && !approval.playsSound
                     && approval.notificationTitle == nil,
                     "a turn waiting on approval shows the tool in the notch, named for its provider")
    }

    /// The service is an engine from another module with its own published
    /// values added. SwiftUI redraws from `objectWillChange`, so a change to
    /// either half, and to the chat session, has to reach it.
    private static func changesReachTheViews(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.tearDown() }
        rig.installBot()
        let service = NexusAgentService(environment: rig.environment)
        var serviceChanges = 0
        var sessionChanges = 0
        // Held until the end so the subscriptions last for every check.
        let subscriptions: [AnyCancellable] = [
            service.objectWillChange.sink { _ in serviceChanges += 1 },
            service.session.objectWillChange.sink { _ in sessionChanges += 1 }
        ]
        defer { subscriptions.forEach { $0.cancel() } }

        var before = serviceChanges
        service.isPinned = true
        suite.expect(serviceChanges > before,
                     "a value the Vitruvian service adds (the pin) tells the views it changed")

        before = serviceChanges
        suite.expect(service.configuration.botToken.isEmpty, "the token is not read until the page loads")
        service.load()
        suite.expect(service.configuration.botToken == "1:real" && serviceChanges > before,
                     "a value the shared engine owns (the settings) tells the views it changed")

        before = sessionChanges
        service.session.draft = "hello"
        suite.expect(sessionChanges > before, "typing in the chat tells the views the session changed")
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

