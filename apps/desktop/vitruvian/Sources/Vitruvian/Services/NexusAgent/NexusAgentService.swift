// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware
//
// Adapted from the standalone Nexus Agent app (apps/desktop/nexus-agent,
// MIT, Copyright (c) 2026 VitruvianSoftware): its BotManager, ConfigManager
// and Quick Prompt window, folded into one service with injected effects.

import AppKit
import Carbon.HIToolbox
import Combine
import Darwin
import SwiftUI
import VitruvianCore
import VitruvianDesign

/// Runs the Nexus Agent Telegram bot from its folder, edits the part of its
/// `.env` the Settings page shows, and summons the Quick Prompt: a floating
/// chat with the Antigravity CLI. Nothing runs at rest unless the user starts
/// the bot or asks for it to start with the app. The bot shares its PID file
/// and log with the standalone app, so either one sees a bot the other started.
@MainActor
package final class NexusAgentService: NSObject, ObservableObject, NSWindowDelegate {
    package static let shared = NexusAgentService(environment: .live)

    /// Why the last start or save did not happen, as the page reports it.
    package enum Problem: Equatable {
        case missingToken, missingBot, missingNode, startFailed, saveFailed
    }

    /// Everything the service touches outside itself. `live` is the real
    /// file system, processes and preferences; tests pass doubles.
    @MainActor
    package struct Environment {
        package var defaults: UserDefaults
        package var home: String
        package var processEnvironment: [String: String]
        /// Shared with the standalone app: its PID file and log live here.
        package var stateDirectory: String
        package var isExecutable: (String) -> Bool
        package var fileExists: (String) -> Bool
        package var readFile: (String) -> String?
        /// The last `limit` bytes of a file, for the log.
        package var readTail: (_ path: String, _ limit: Int) -> String?
        /// Writes atomically, readable by the user alone: the file holds a token.
        package var writePrivateFile: (_ path: String, _ content: String) -> Bool
        package var removeFile: (String) -> Void
        /// True only for a live process whose executable is Node, so a stale
        /// PID file reused by another program is never signalled.
        package var isBotProcess: (Int32) -> Bool
        package var signal: (_ pid: Int32, _ signal: Int32) -> Void
        /// Starts Node on the bot with its output appended to the log, and
        /// reports the exit on the main actor. Returns the process id.
        package var launchBot: (_ node: String, _ directory: String, _ logPath: String,
                                _ environment: [String: String],
                                _ onExit: @escaping @MainActor @Sendable (Int32) -> Void) throws -> Int32
        package var schedule: (_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> Void
        package var openFile: (String) -> Void
        /// Runs one agy turn in `directory`, delivering its output in order and
        /// then its exit status, both on the main actor.
        package var launchAgent: (_ path: String, _ arguments: [String], _ directory: String,
                                  _ environment: [String: String],
                                  _ onOutput: @escaping @MainActor @Sendable (Data) -> Void,
                                  _ onExit: @escaping @MainActor @Sendable (Int32) -> Void) throws -> NexusAgentRunningAgent
        /// agy's or claude's recent conversations for a folder, newest first.
        package var listSessions: (_ directory: String, _ provider: NexusAgentCLIProvider) -> [NexusAgentSessionSummary]
        /// Reads past conversation turns, if present.
        package var readTranscript: (_ id: String, _ provider: NexusAgentCLIProvider) -> [NexusAgentChatMessage]?
        /// Resolves the absolute path to a transcript file if it exists.
        package var transcriptPath: (_ id: String, _ provider: NexusAgentCLIProvider) -> String?
        /// Reads the full raw content of a transcript file.
        package var readTranscriptRaw: (_ id: String, _ provider: NexusAgentCLIProvider) -> String?

        package init(defaults: UserDefaults,
                     home: String,
                     processEnvironment: [String: String],
                     stateDirectory: String,
                     isExecutable: @escaping (String) -> Bool,
                     fileExists: @escaping (String) -> Bool,
                     readFile: @escaping (String) -> String?,
                     readTail: @escaping (String, Int) -> String?,
                     writePrivateFile: @escaping (String, String) -> Bool,
                     removeFile: @escaping (String) -> Void,
                     isBotProcess: @escaping (Int32) -> Bool,
                     signal: @escaping (Int32, Int32) -> Void,
                     launchBot: @escaping (String, String, String, [String: String],
                                           @escaping @MainActor @Sendable (Int32) -> Void) throws -> Int32,
                     schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void,
                     openFile: @escaping (String) -> Void,
                     launchAgent: @escaping (String, [String], String, [String: String],
                                             @escaping @MainActor @Sendable (Data) -> Void,
                                             @escaping @MainActor @Sendable (Int32) -> Void) throws -> NexusAgentRunningAgent,
                     listSessions: @escaping (String, NexusAgentCLIProvider) -> [NexusAgentSessionSummary] = { _, _ in [] },
                     readTranscript: @escaping (String, NexusAgentCLIProvider) -> [NexusAgentChatMessage]? = { _, _ in nil },
                     transcriptPath: @escaping (String, NexusAgentCLIProvider) -> String? = { _, _ in nil },
                     readTranscriptRaw: @escaping (String, NexusAgentCLIProvider) -> String? = { _, _ in nil }) {
            self.defaults = defaults
            self.home = home
            self.processEnvironment = processEnvironment
            self.stateDirectory = stateDirectory
            self.isExecutable = isExecutable
            self.fileExists = fileExists
            self.readFile = readFile
            self.readTail = readTail
            self.writePrivateFile = writePrivateFile
            self.removeFile = removeFile
            self.isBotProcess = isBotProcess
            self.signal = signal
            self.launchBot = launchBot
            self.schedule = schedule
            self.openFile = openFile
            self.launchAgent = launchAgent
            self.listSessions = listSessions
            self.readTranscript = readTranscript
            self.transcriptPath = transcriptPath
            self.readTranscriptRaw = readTranscriptRaw
        }

        package static var live: Environment {
            let home = NSHomeDirectory()
            return Environment(
                defaults: .standard,
                home: home,
                processEnvironment: ProcessInfo.processInfo.environment,
                stateDirectory: (home as NSString).appendingPathComponent("Library/Application Support/NexusAgent"),
                isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
                fileExists: { FileManager.default.fileExists(atPath: $0) },
                readFile: { try? String(contentsOfFile: $0, encoding: .utf8) },
                readTail: NexusAgentService.readTail,
                writePrivateFile: NexusAgentService.writePrivateFile,
                removeFile: { try? FileManager.default.removeItem(atPath: $0) },
                isBotProcess: NexusAgentService.isNodeProcess,
                signal: { pid, signal in _ = kill(pid, signal) },
                launchBot: NexusAgentService.launchNode,
                schedule: { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay) { work() } },
                openFile: { NSWorkspace.shared.open(URL(fileURLWithPath: $0)) },
                launchAgent: NexusAgentService.launchAgentProcess,
                listSessions: { NexusAgentService.readSessions(home: home, directory: $0, provider: $1) },
                readTranscript: { NexusAgentService.readTranscript(home: home, conversationID: $0, provider: $1) },
                transcriptPath: { NexusAgentService.transcriptPath(home: home, conversationID: $0, provider: $1) },
                readTranscriptRaw: { id, provider in
                    guard let path = NexusAgentService.transcriptPath(home: home, conversationID: id, provider: provider) else { return nil }
                    return try? String(contentsOfFile: path, encoding: .utf8)
                })
        }
    }

    @Published package private(set) var isRunning = false
    @Published package private(set) var pid: Int32?
    @Published package private(set) var logLines: [String] = []
    @Published package private(set) var configuration = NexusAgentConfiguration()
    @Published package private(set) var problem: Problem?
    /// Saved while the bot runs: it reads its `.env` only at start.
    @Published package private(set) var needsRestart = false
    @Published package private(set) var shortcutRegistrationFailed = false
    @Published package private(set) var agentPath: String?
    @Published package var isPinned: Bool = false {
        didSet {
            if isPinned, let panel {
                panel.level = .floating
                panel.hidesOnDeactivate = false
            }
        }
    }

    package var activeProvider: NexusAgentCLIProvider {
        get { configuration.activeProvider }
        set { updateActiveProvider(newValue) }
    }

    package let session: NexusAgentQuickPromptSession
    private let environment: Environment
    /// Its own id, clear of every other hotkey's: 25 was also the first
    /// capture tool's, so each could answer to the other's key
    /// (`hotkey_ids_are_unique` in bazel/source_lints.py).
    private let hotkey = QuickToolHotkey(id: 90)
    /// The bot this app launched, as opposed to one adopted from the PID file.
    private var managedPID: Int32?
    private var pollTimer: Timer?
    private var didAutoStart = false
    private var panel: NSPanel?
    private var modeObserver: AnyCancellable?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?

    /// A bot gets this long to stop on SIGTERM before it is killed.
    package static let stopGrace: TimeInterval = 3

    package init(environment: Environment) {
        self.environment = environment
        session = NexusAgentQuickPromptSession(environment: environment)
        super.init()
        session.service = self
        session.onTurnFinished = { [weak self] reply, isError in
            guard let self, self.panel?.isVisible != true else { return }
            let name = self.configuration.activeProvider.name
            if isError {
                Notifier.post(title: "\(name) — Failed", body: String(reply.prefix(200)))
            } else if !reply.isEmpty {
                let firstLine = reply.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? reply
                Notifier.post(title: "\(name) — Done", body: String(firstLine.prefix(200)))
            }
        }
        hotkey.onPress = { [weak self] in self?.toggleQuickPrompt() }
    }

    // MARK: - Paths

    package var botDirectory: String {
        NexusAgentSupport.botDirectory(configured: environment.defaults[Preferences.nexusAgentBotDirectory],
                                       home: environment.home)
    }

    package var envFilePath: String { (botDirectory as NSString).appendingPathComponent(".env") }
    package var logPath: String { (environment.stateDirectory as NSString).appendingPathComponent("bot.log") }
    package var pidFilePath: String { (environment.stateDirectory as NSString).appendingPathComponent(".bot.pid") }
    private var entryPointPath: String {
        (botDirectory as NSString).appendingPathComponent(NexusAgentSupport.botEntryPoint)
    }

    package var isBotInstalled: Bool { environment.fileExists(entryPointPath) }

    // MARK: - Preferences

    package func syncWithPreferences() {
        let available = AppFeature.nexusAgent.isAvailable(in: environment.defaults)
        let enabled = available && environment.defaults[Preferences.nexusAgentShortcutEnabled]
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.nexusAgentShortcut, fallback: .nexusAgentDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut,
                                                  storageKey: DefaultsKey.nexusAgentShortcut)
        guard available else {
            // Uninstalled in the hub: nothing stays resident, the bot included.
            stopPolling()
            hideQuickPrompt()
            session.stop()
            panel = nil
            if isRunning || managedPID != nil { stop() }
            didAutoStart = false
            return
        }
        // Once per launch, and only when asked for: a bot already running
        // (started by the standalone app, say) is adopted instead.
        if !didAutoStart {
            didAutoStart = true
            refreshStatus()
            if environment.defaults[Preferences.nexusAgentAutoStart], !isRunning {
                start()
            }
        }
    }

    package func suspend() {
        hotkey.unregister()
        hideQuickPrompt()
    }

    /// The bot outlives the app, as it does the standalone one; only the
    /// reply in flight belongs to this process.
    package func prepareForQuit() {
        session.stop()
        stopPolling()
    }

    // MARK: - Configuration

    /// Reads the bot's `.env` and finds the agent, for the page.
    package func load() {
        configuration = environment.readFile(envFilePath).map(NexusAgentEnvFile.parse) ?? NexusAgentConfiguration()
        agentPath = NexusAgentSupport.locateAgent(named: configuration.activeProvider.executableName,
                                                  environment: environment.processEnvironment,
                                                  home: environment.home,
                                                  isExecutable: environment.isExecutable)
    }


    package func updateActiveProvider(_ provider: NexusAgentCLIProvider) {
        configuration.activeProvider = provider
        agentPath = NexusAgentSupport.locateAgent(named: provider.executableName,
                                                  environment: environment.processEnvironment,
                                                  home: environment.home,
                                                  isExecutable: environment.isExecutable)
        session.refreshSessions(configuration: configuration)
    }

    /// Writes the page's values into the `.env`, keeping the rest of it.
    @discardableResult
    package func save(_ next: NexusAgentConfiguration) -> Bool {
        guard environment.fileExists(botDirectory) else {
            problem = .missingBot
            return false
        }
        let content = NexusAgentEnvFile.render(next, over: environment.readFile(envFilePath))
        guard environment.writePrivateFile(envFilePath, content) else {
            problem = .saveFailed
            return false
        }
        configuration = NexusAgentEnvFile.parse(content)
        problem = nil
        if isRunning { needsRestart = true }
        return true
    }

    // MARK: - Bot

    /// Brings `isRunning` in line with the processes: the one this app
    /// launched, or the one the PID file names if it is still Node.
    package func refreshStatus() {
        if let managedPID {
            setRunning(managedPID)
            return
        }
        if let text = environment.readFile(pidFilePath),
           let recorded = NexusAgentSupport.processID(fromPIDFile: text),
           environment.isBotProcess(recorded) {
            setRunning(recorded)
            return
        }
        if environment.fileExists(pidFilePath) { environment.removeFile(pidFilePath) }
        setRunning(nil)
    }

    package func start() {
        refreshStatus()
        guard !isRunning else { return }
        load()
        guard isBotInstalled else { problem = .missingBot; return }
        guard configuration.isConfigured else { problem = .missingToken; return }
        guard let node = NexusAgentSupport.locateNode(home: environment.home,
                                                      isExecutable: environment.isExecutable) else {
            problem = .missingNode
            return
        }
        let childEnvironment = NexusAgentSupport.childEnvironment(base: environment.processEnvironment,
                                                                  home: environment.home)
        do {
            let launched = try environment.launchBot(node, botDirectory, logPath, childEnvironment) { [weak self] exited in
                self?.botDidExit(exited)
            }
            managedPID = launched
            _ = environment.writePrivateFile(pidFilePath, "\(launched)")
            problem = nil
            needsRestart = false
            setRunning(launched)
            readLog()
        } catch {
            problem = .startFailed
        }
    }

    /// SIGTERM, then SIGKILL if the bot is still there after the grace
    /// period. Only the recorded bot is signalled, never a match by name.
    package func stop(then next: (@MainActor () -> Void)? = nil) {
        refreshStatus()
        guard let target = pid else {
            next?()
            return
        }
        environment.signal(target, SIGTERM)
        managedPID = nil
        environment.removeFile(pidFilePath)
        needsRestart = false
        setRunning(nil)
        awaitExit(of: target, remaining: Self.stopGrace, then: next)
    }

    package func restart() {
        stop { [weak self] in self?.start() }
    }

    package func openLog() {
        guard environment.fileExists(logPath) else { return }
        environment.openFile(logPath)
    }

    private func awaitExit(of target: Int32, remaining: TimeInterval, then next: (@MainActor () -> Void)?) {
        guard environment.isBotProcess(target) else {
            next?()
            return
        }
        guard remaining > 0 else {
            environment.signal(target, SIGKILL)
            next?()
            return
        }
        let step = 0.25
        environment.schedule(step) { [weak self] in
            self?.awaitExit(of: target, remaining: remaining - step, then: next)
        }
    }

    private func botDidExit(_ exited: Int32) {
        guard managedPID == exited else { return }
        managedPID = nil
        if let text = environment.readFile(pidFilePath),
           NexusAgentSupport.processID(fromPIDFile: text) == exited {
            environment.removeFile(pidFilePath)
        }
        setRunning(nil)
        readLog()
    }

    private func setRunning(_ next: Int32?) {
        if pid != next { pid = next }
        if isRunning != (next != nil) { isRunning = next != nil }
    }

    // MARK: - Polling

    /// Only while the page is up: nothing polls at rest.
    package func startPolling() {
        load()
        refreshStatus()
        readLog()
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshStatus()
                self?.readLog()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    package func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func readLog() {
        let next = environment.readTail(logPath, 16 * 1024).map { NexusAgentSupport.tail($0) } ?? []
        if next != logLines { logLines = next }
    }

    // MARK: - Quick Prompt

    package var isQuickPromptVisible: Bool { panel?.isVisible == true }

    package func toggleQuickPrompt() {
        if isQuickPromptVisible, panel?.isKeyWindow == true {
            hideQuickPrompt()
        } else {
            showQuickPrompt()
        }
    }

    package func showQuickPrompt() {
        guard AppFeature.nexusAgent.isAvailable(in: environment.defaults) else { return }
        load()
        let panel = ensurePanel()
        installMonitors(for: panel)
        if !panel.isVisible || !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            apply(session.mode, to: panel, frame: NexusAgentQuickPromptLayout.initialFrame(
                for: session.mode, screen: NSScreen.pointerVisibleFrame), animated: false)
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        session.focusSerial += 1
        if session.conversationID != nil && session.mode == .chat {
            session.startTranscriptFollower(provider: configuration.activeProvider)
        }
    }

    package func hideQuickPrompt() {
        session.stopTranscriptFollower()
        guard let panel else { return }
        removeMonitors()
        panel.orderOut(nil)
    }

    package func dockToNotch() {
        hideQuickPrompt()
        NotchService.shared.agentTab = .chat
        NotchService.shared.select(.agents)
    }

    /// Borderless panels refuse key status by default; the prompt needs it
    /// so typing and Esc work without activating the app.
    private final class KeyablePromptPanel: OverlayPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let size = NexusAgentQuickPromptLayout.size(for: session.mode)
        let panel = KeyablePromptPanel(contentRect: NSRect(origin: .zero, size: size),
                                       styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                       backing: .buffered,
                                       defer: false)
        panel.title = "Vitruvian"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.delegate = self
        let host = NSHostingController(rootView: ServiceViews.factory.nexusAgentQuickPrompt())
        host.sizingOptions = []
        panel.contentViewController = host
        self.panel = panel
        apply(session.mode, to: panel, frame: NexusAgentQuickPromptLayout.initialFrame(
            for: session.mode, screen: NSScreen.pointerVisibleFrame), animated: false)
        // Pill, drawer and chat each have their own size; the panel follows.
        modeObserver = session.$mode.removeDuplicates().dropFirst().sink { [weak self, weak panel] mode in
            guard let self, let panel else { return }
            let screen = panel.screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
            self.apply(mode, to: panel, frame: NexusAgentQuickPromptLayout.frame(
                for: mode, from: panel.frame, screen: screen), animated: panel.isVisible)
            if mode == .chat && self.session.conversationID != nil {
                self.session.startTranscriptFollower(provider: self.configuration.activeProvider)
            } else if mode != .chat {
                self.session.stopTranscriptFollower()
            }
        }
        return panel
    }

    /// Sizes the panel for `mode`; only the chat can be resized by hand.
    private func apply(_ mode: NexusAgentQuickPromptMode, to panel: NSPanel, frame: CGRect, animated: Bool) {
        typealias Layout = NexusAgentQuickPromptLayout
        if Layout.isResizable(mode) {
            panel.styleMask.insert(.resizable)
            panel.minSize = Layout.chatMinimumSize
            panel.maxSize = Layout.chatMaximumSize
        } else {
            panel.styleMask.remove(.resizable)
            panel.minSize = frame.size
            panel.maxSize = frame.size
        }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(frame, display: true, animate: false)
            return
        }
        let spring = CASpringAnimation()
        spring.stiffness = Layout.springStiffness
        spring.damping = Layout.springDamping
        NSAnimationContext.runAnimationGroup { context in
            context.duration = spring.settlingDuration
            // Ease out with a small overshoot, like the spring it times.
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.25, 0.64, 1)
            panel.animator().setFrame(frame, display: true)
        }
    }

    package func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        typealias Layout = NexusAgentQuickPromptLayout
        guard Layout.isResizable(session.mode) else { return sender.frame.size }
        return NSSize(width: min(max(Layout.chatMinimumSize.width, frameSize.width), Layout.chatMaximumSize.width),
                      height: min(max(Layout.chatMinimumSize.height, frameSize.height), Layout.chatMaximumSize.height))
    }

    /// Esc closes the prompt, and so does a click outside it. A reply in
    /// flight keeps streaming into the session while it is hidden.
    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCmdW = flags == .command && event.charactersIgnoringModifiers == "w"
            let isCmdN = flags == .command && event.charactersIgnoringModifiers == "n"
            if isCmdN {
                self.session.newChat()
                return nil
            }
            guard event.keyCode == UInt16(kVK_Escape) || isCmdW else { return event }
            // Mid-composition Esc belongs to the input method.
            if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            self.hideQuickPrompt()
            return nil
        }
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return event }
            guard !self.isPinned else { return event }
            if event.window !== panel, !Self.mouseIsInside(panel) { self.hideQuickPrompt() }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return }
            guard !self.isPinned else { return }
            if event.windowNumber != panel.windowNumber, !Self.mouseIsInside(panel),
               // Keys on the Accessibility Keyboard are clicks outside the panel.
               !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) {
                self.hideQuickPrompt()
            }
        }
    }

    private static func mouseIsInside(_ panel: NSPanel) -> Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    private func removeMonitors() {
        for monitor in [keyMonitor, localClickMonitor, outsideClickMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = nil
        localClickMonitor = nil
        outsideClickMonitor = nil
    }

    // MARK: - Live effects

    nonisolated private static func readTail(_ path: String, _ limit: Int) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > UInt64(limit) ? end - UInt64(limit) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }
        var text = String(decoding: data, as: UTF8.self)
        // A cut first line is noise; drop it unless the read began at the top.
        if start > 0, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        return text
    }

    nonisolated private static func writePrivateFile(_ path: String, _ content: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            return true
        } catch {
            return false
        }
    }

    nonisolated private static func isNodeProcess(_ pid: Int32) -> Bool {
        guard pid > 0, kill(pid, 0) == 0 || errno == EPERM else { return false }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        return (String(cString: buffer) as NSString).lastPathComponent == "node"
    }

    nonisolated private static func launchNode(_ node: String, _ directory: String, _ logPath: String,
                                               _ environment: [String: String],
                                               _ onExit: @escaping @MainActor @Sendable (Int32) -> Void) throws -> Int32 {
        let logURL = URL(fileURLWithPath: logPath)
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // A fresh log per start, as the standalone app keeps it: bounded,
        // and the page's tail is this run's.
        guard FileManager.default.createFile(atPath: logPath, contents: nil),
              let log = FileHandle(forWritingAtPath: logPath) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [NexusAgentSupport.botEntryPoint]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { finished in
            let exited = finished.processIdentifier
            try? log.close()
            DispatchQueue.main.async { onExit(exited) }
        }
        do {
            try process.run()
        } catch {
            try? log.close()
            throw error
        }
        return process.processIdentifier
    }

    /// Output is read on a thread of its own until EOF, and each chunk is
    /// queued to the main thread before the exit is, so the session sees the
    /// whole reply before the turn ends.
    nonisolated private static func launchAgentProcess(_ path: String, _ arguments: [String], _ directory: String,
                                                       _ environment: [String: String],
                                                       _ onOutput: @escaping @MainActor @Sendable (Data) -> Void,
                                                       _ onExit: @escaping @MainActor @Sendable (Int32) -> Void) throws -> NexusAgentRunningAgent {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        // Only the child keeps the write end, so its exit reaches the reader as EOF.
        try? pipe.fileHandleForWriting.close()
        let reader = pipe.fileHandleForReading
        Thread.detachNewThread {
            while true {
                let chunk = reader.availableData
                if chunk.isEmpty { break }
                DispatchQueue.main.async { onOutput(chunk) }
            }
            process.waitUntilExit()
            let status = process.terminationStatus
            try? reader.close()
            DispatchQueue.main.async { onExit(status) }
        }
        let pid = process.processIdentifier
        return NexusAgentRunningAgent(terminate: {
            // agy leads a process group of its own; signalling the group
            // also ends the tools it started, which hold the pipe open.
            if getpgid(pid) == pid { _ = kill(-pid, SIGTERM) }
            process.terminate()
        })
    }
}

extension NexusAgentService {
    /// Sends the draft as one Quick Prompt turn with the bot's settings.
    package func sendQuickPrompt() {
        session.send(session.draft, configuration: configuration, agentPath: agentPath)
    }

    /// Retries the last failed prompt if any.
    package func retryQuickPrompt() {
        guard let prompt = session.lastFailedPrompt else { return }
        session.send(prompt, configuration: configuration, agentPath: agentPath)
    }

    /// Reads agy or claude conversation index; empty when provider has none.
    nonisolated static func readSessions(home: String, directory: String, provider: NexusAgentCLIProvider = .antigravity) -> [NexusAgentSessionSummary] {
        if provider.id == NexusAgentCLIProvider.claude.id {
            return NexusAgentSessionSummary.parseClaudeSessions(home: home, directory: directory)
        }
        if provider.id == NexusAgentCLIProvider.ollama.id {
            return []
        }
        guard let database = NexusAgentSessionSummary.antigravitySummariesDatabase(home: home) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", database, NexusAgentSessionSummary.query]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        let filterDirectory = (directory.isEmpty || directory == home) ? "" : directory
        return NexusAgentSessionSummary.parse(
            data, directory: filterDirectory,
            archivedIds: NexusAgentSessionSummary.antigravityArchivedSessionIds(home: home))
    }

    /// Reads conversation transcript from ~/.gemini/antigravity/brain/<id>/.system_generated/logs/transcript.jsonl
    /// or ~/.claude/projects/*/<id>.jsonl
    package nonisolated static func readTranscript(home: String, conversationID: String, provider: NexusAgentCLIProvider = .antigravity) -> [NexusAgentChatMessage]? {
        let fileManager = FileManager.default
        if provider.id == NexusAgentCLIProvider.claude.id {
            let claudeProjectsDir = (home as NSString).appendingPathComponent(".claude/projects")
            if let subdirs = try? fileManager.contentsOfDirectory(atPath: claudeProjectsDir) {
                for subdir in subdirs {
                    let candidatePath = (claudeProjectsDir as NSString).appendingPathComponent(subdir).appending("/\(conversationID).jsonl")
                    if fileManager.fileExists(atPath: candidatePath),
                       let content = try? String(contentsOfFile: candidatePath, encoding: .utf8) {
                        return parseClaudeTranscript(content)
                    }
                }
            }
            let agyPath = (home as NSString).appendingPathComponent(".gemini/antigravity/brain/\(conversationID)/.system_generated/logs/transcript.jsonl")
            if fileManager.fileExists(atPath: agyPath),
               let content = try? String(contentsOfFile: agyPath, encoding: .utf8) {
                return parseTranscript(content)
            }
            return nil
        }

        let agyPath = (home as NSString).appendingPathComponent(".gemini/antigravity/brain/\(conversationID)/.system_generated/logs/transcript.jsonl")
        if fileManager.fileExists(atPath: agyPath),
           let content = try? String(contentsOfFile: agyPath, encoding: .utf8) {
            return parseTranscript(content)
        }

        let claudeProjectsDir = (home as NSString).appendingPathComponent(".claude/projects")
        if let subdirs = try? fileManager.contentsOfDirectory(atPath: claudeProjectsDir) {
            for subdir in subdirs {
                let candidatePath = (claudeProjectsDir as NSString).appendingPathComponent(subdir).appending("/\(conversationID).jsonl")
                if fileManager.fileExists(atPath: candidatePath),
                   let content = try? String(contentsOfFile: candidatePath, encoding: .utf8) {
                    return parseClaudeTranscript(content)
                }
            }
        }
        return nil
    }

    package nonisolated static func parseClaudeTranscript(_ content: String) -> [NexusAgentChatMessage]? {
        var messages: [NexusAgentChatMessage] = []
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }

            if type == "user" {
                var userText = ""
                if let message = json["message"] as? [String: Any] {
                    if let strContent = message["content"] as? String {
                        userText = strContent
                    } else if let blocks = message["content"] as? [[String: Any]] {
                        userText = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
                    }
                } else if let strContent = json["content"] as? String {
                    userText = strContent
                }
                let cleaned = extractUserPrompt(userText)
                if !cleaned.isEmpty {
                    messages.append(NexusAgentChatMessage(role: .user, text: cleaned))
                }
            } else if type == "assistant" {
                var assistantText = ""
                var thinkingParts: [String] = []
                var steps: [NexusAgentToolStep] = []

                let contentBlocks: [[String: Any]]
                if let message = json["message"] as? [String: Any] {
                    if let blocks = message["content"] as? [[String: Any]] {
                        contentBlocks = blocks
                    } else if let strContent = message["content"] as? String {
                        assistantText = strContent
                        contentBlocks = []
                    } else {
                        contentBlocks = []
                    }
                } else if let blocks = json["content"] as? [[String: Any]] {
                    contentBlocks = blocks
                } else if let strContent = json["content"] as? String {
                    assistantText = strContent
                    contentBlocks = []
                } else {
                    contentBlocks = []
                }

                for block in contentBlocks {
                    let blockType = block["type"] as? String ?? ""
                    if blockType == "text", let text = block["text"] as? String {
                        if !assistantText.isEmpty { assistantText += "\n" }
                        assistantText += text
                    } else if blockType == "thinking", let thinking = block["thinking"] as? String {
                        thinkingParts.append(thinking)
                    } else if blockType == "tool_use" {
                        let name = block["name"] as? String ?? "tool"
                        let input = block["input"] as? [String: Any]
                        var summary: String?
                        if name == "Bash" {
                            if let command = input?["command"] as? String {
                                let firstLine = command.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? command
                                summary = String(firstLine.prefix(80))
                            }
                        } else if name == "Task" {
                            summary = input?["description"] as? String ?? input?["prompt"] as? String
                        } else if name == "Read" || name == "Edit" {
                            summary = input?["file_path"] as? String
                        } else {
                            summary = input?["description"] as? String ?? name
                        }
                        steps.append(NexusAgentToolStep(title: summary ?? name, detail: name, isFinished: true))
                    }
                }

                let trimmedText = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
                let thinkingText = thinkingParts.isEmpty ? nil : thinkingParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedText.isEmpty || !steps.isEmpty || thinkingText != nil {
                    messages.append(NexusAgentChatMessage(
                        role: .agent,
                        text: trimmedText,
                        toolSteps: steps.isEmpty ? nil : steps,
                        thinkingText: thinkingText
                    ))
                }
            }
        }
        return messages.isEmpty ? nil : messages
    }

    package nonisolated static func parseTranscript(_ content: String) -> [NexusAgentChatMessage]? {
        var messages: [NexusAgentChatMessage] = []
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }
            if type == "USER_INPUT", let rawContent = json["content"] as? String {
                let cleaned = extractUserPrompt(rawContent)
                if !cleaned.isEmpty {
                    messages.append(NexusAgentChatMessage(role: .user, text: cleaned))
                }
            } else if type == "PLANNER_RESPONSE" {
                let text = (json["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let thinking = json["thinking"] as? String
                var steps: [NexusAgentToolStep] = []
                if let toolCalls = json["tool_calls"] as? [[String: Any]] {
                    for call in toolCalls {
                        if let name = call["name"] as? String {
                            let summary = (call["args"] as? [String: Any])?["toolSummary"] as? String
                            steps.append(NexusAgentToolStep(title: summary ?? name, detail: summary != nil ? name : nil, isFinished: true))
                        }
                    }
                }
                if !text.isEmpty || !steps.isEmpty || thinking != nil {
                    messages.append(NexusAgentChatMessage(role: .agent, text: text, toolSteps: steps.isEmpty ? nil : steps, thinkingText: thinking))
                }
            }
        }
        return messages.isEmpty ? nil : messages
    }

    package nonisolated static func transcriptPath(home: String, conversationID: String, provider: NexusAgentCLIProvider) -> String? {
        let fileManager = FileManager.default
        if provider.id == NexusAgentCLIProvider.claude.id {
            let claudeProjectsDir = (home as NSString).appendingPathComponent(".claude/projects")
            if let subdirs = try? fileManager.contentsOfDirectory(atPath: claudeProjectsDir) {
                for subdir in subdirs {
                    let candidatePath = (claudeProjectsDir as NSString).appendingPathComponent(subdir).appending("/\(conversationID).jsonl")
                    if fileManager.fileExists(atPath: candidatePath) {
                        return candidatePath
                    }
                }
            }
            let agyPath = (home as NSString).appendingPathComponent(".gemini/antigravity/brain/\(conversationID)/.system_generated/logs/transcript.jsonl")
            if fileManager.fileExists(atPath: agyPath) {
                return agyPath
            }
            return nil
        }

        let agyPath = (home as NSString).appendingPathComponent(".gemini/antigravity/brain/\(conversationID)/.system_generated/logs/transcript.jsonl")
        if fileManager.fileExists(atPath: agyPath) {
            return agyPath
        }

        let claudeProjectsDir = (home as NSString).appendingPathComponent(".claude/projects")
        if let subdirs = try? fileManager.contentsOfDirectory(atPath: claudeProjectsDir) {
            for subdir in subdirs {
                let candidatePath = (claudeProjectsDir as NSString).appendingPathComponent(subdir).appending("/\(conversationID).jsonl")
                if fileManager.fileExists(atPath: candidatePath) {
                    return candidatePath
                }
            }
        }
        return nil
    }

    package nonisolated static func parseActiveSubagents(from transcriptContent: String) -> [NexusAgentActiveSubagent] {
        var spawned: [NexusAgentActiveSubagent] = []
        var completedSubagents: Set<String> = []

        for line in transcriptContent.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            var textContent = ""
            if let content = json["content"] as? String {
                textContent = content
            } else if let message = json["message"] as? [String: Any] {
                if let content = message["content"] as? String {
                    textContent = content
                } else if let blocks = message["content"] as? [[String: Any]] {
                    textContent = blocks.compactMap { $0["text"] as? String ?? $0["content"] as? String }.joined(separator: " ")
                }
            }

            if !textContent.isEmpty {
                if textContent.contains("sender=") || textContent.contains("Message sent to") || textContent.contains("Completed At:") || textContent.contains("Completed") {
                    for s in spawned {
                        if textContent.contains("sender=\(s.typeName)") || textContent.contains("sender=\(s.id)") || textContent.contains(s.id) || (textContent.contains(s.role) && textContent.contains("Completed")) {
                            completedSubagents.insert(s.id)
                        }
                    }
                }
            }

            if let type = json["type"] as? String, type == "SYSTEM_MESSAGE" || type == "USER_INPUT" {
                if let content = json["content"] as? String {
                    for s in spawned {
                        if content.contains("sender=\(s.typeName)") || content.contains("sender=\(s.id)") {
                            completedSubagents.insert(s.id)
                        }
                    }
                }
            }

            // Claude tool_result completion checking
            if let directToolUseID = json["tool_use_id"] as? String {
                completedSubagents.insert(directToolUseID)
            }
            let checkBlocks: [[String: Any]]
            if let message = json["message"] as? [String: Any], let blocks = message["content"] as? [[String: Any]] {
                checkBlocks = blocks
            } else if let blocks = json["content"] as? [[String: Any]] {
                checkBlocks = blocks
            } else {
                checkBlocks = []
            }
            for block in checkBlocks {
                if (block["type"] as? String) == "tool_result" {
                    if let toolUseID = block["tool_use_id"] as? String {
                        completedSubagents.insert(toolUseID)
                    }
                }
            }

            // Antigravity invoke_subagent tool calls
            if let toolCalls = json["tool_calls"] as? [[String: Any]] {
                for call in toolCalls {
                    guard let name = call["name"] as? String, name == "invoke_subagent",
                          let args = call["args"] as? [String: Any] else { continue }

                    var subagentsRaw: [[String: Any]] = []
                    if let rawArray = args["Subagents"] as? [[String: Any]] {
                        subagentsRaw = rawArray
                    } else if let rawString = args["Subagents"] as? String,
                              let subData = rawString.data(using: .utf8),
                              let decoded = try? JSONSerialization.jsonObject(with: subData) as? [[String: Any]] {
                        subagentsRaw = decoded
                    }

                    for sub in subagentsRaw {
                        let typeName = sub["TypeName"] as? String ?? "subagent"
                        let role = sub["Role"] as? String ?? typeName
                        let prompt = sub["Prompt"] as? String ?? ""
                        let model = sub["Model"] as? String ?? "inherit"
                        let id = "\(typeName)-\(role)-\(spawned.count)"
                        let active = NexusAgentActiveSubagent(id: id, typeName: typeName, role: role, prompt: prompt, model: model, isRunning: true)
                        spawned.append(active)
                    }
                }
            }

            // Claude Code Task tool calls in assistant turns
            let lineType = json["type"] as? String
            if lineType == "assistant" {
                let assistantBlocks: [[String: Any]]
                if let message = json["message"] as? [String: Any], let blocks = message["content"] as? [[String: Any]] {
                    assistantBlocks = blocks
                } else if let blocks = json["content"] as? [[String: Any]] {
                    assistantBlocks = blocks
                } else {
                    assistantBlocks = []
                }
                for block in assistantBlocks {
                    if (block["type"] as? String) == "tool_use", (block["name"] as? String) == "Task" {
                        let toolId = block["id"] as? String ?? UUID().uuidString
                        let input = block["input"] as? [String: Any]
                        let subagentType = input?["subagent_type"] as? String ?? "subagent"
                        let description = input?["description"] as? String ?? subagentType
                        let prompt = input?["prompt"] as? String ?? ""
                        let active = NexusAgentActiveSubagent(id: toolId, typeName: subagentType, role: description, prompt: prompt, model: "claude", isRunning: true)
                        spawned.append(active)
                    }
                }
            }
        }

        return spawned.filter { !completedSubagents.contains($0.id) }
    }

    package nonisolated static func extractUserPrompt(_ raw: String) -> String {
        NexusAgentSessionSummary.extractUserPrompt(raw)
    }

    // MARK: - Session Archiving

    package func archiveSession(_ summary: NexusAgentSessionSummary, configuration: NexusAgentConfiguration) {
        Self.archiveSession(home: environment.home, id: summary.id, provider: configuration.activeProvider)
    }

    package func unarchiveSession(_ summary: NexusAgentSessionSummary, configuration: NexusAgentConfiguration) {
        Self.unarchiveSession(home: environment.home, id: summary.id, provider: configuration.activeProvider)
    }

    nonisolated package static func archiveSession(home: String, id: String, provider: NexusAgentCLIProvider) {
        if provider.id == NexusAgentCLIProvider.antigravity.id {
            setAntigravityArchived(home: home, id: id, archived: true)
        } else if provider.id == NexusAgentCLIProvider.claude.id {
            var hidden = UserDefaults.standard.stringArray(forKey: "vitruvian.claude.hiddenSessionIds") ?? []
            if !hidden.contains(id) {
                hidden.append(id)
                UserDefaults.standard.set(hidden, forKey: "vitruvian.claude.hiddenSessionIds")
            }
            updateClaudeVSCodeHiddenState(home: home, id: id, isArchived: true)
        }
    }

    nonisolated package static func unarchiveSession(home: String, id: String, provider: NexusAgentCLIProvider) {
        if provider.id == NexusAgentCLIProvider.antigravity.id {
            setAntigravityArchived(home: home, id: id, archived: false)
        } else if provider.id == NexusAgentCLIProvider.claude.id {
            var hidden = UserDefaults.standard.stringArray(forKey: "vitruvian.claude.hiddenSessionIds") ?? []
            if hidden.contains(id) {
                hidden.removeAll { $0 == id }
                UserDefaults.standard.set(hidden, forKey: "vitruvian.claude.hiddenSessionIds")
            }
            updateClaudeVSCodeHiddenState(home: home, id: id, isArchived: false)
        }
    }

    /// Records the archive state where agy itself reads it: the annotation
    /// beside the conversation, `annotations/<id>.pbtxt`. The index's `killed`
    /// column means an aborted run, so it is left alone.
    nonisolated private static func setAntigravityArchived(home: String, id: String, archived: Bool,
                                                          now: Date = Date()) {
        guard !id.isEmpty, id == (id as NSString).lastPathComponent, id != ".", id != ".." else { return }
        let files = FileManager.default
        let roots = NexusAgentSessionSummary.antigravityDataDirectories
            .map { (home as NSString).appendingPathComponent($0) }
        let annotation = { (root: String) in root + "/annotations/\(id).pbtxt" }
        let existing = roots.filter { files.fileExists(atPath: annotation($0)) }
        // Unarchiving clears every copy, since any one of them archives the session.
        let targets = archived
            ? [roots.first { files.fileExists(atPath: $0 + "/conversations/\(id).db") } ?? existing.first ?? roots[0]]
            : existing
        for root in targets {
            let path = annotation(root)
            let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            try? files.createDirectory(atPath: root + "/annotations", withIntermediateDirectories: true)
            try? NexusAgentSessionSummary.antigravityAnnotation(text, archived: archived, now: now)
                .write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    nonisolated private static func runSqlite(database: String, sql: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database, sql]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    nonisolated private static func updateClaudeVSCodeHiddenState(home: String, id: String, isArchived: Bool) {
        let appSupport = (home as NSString).appendingPathComponent("Library/Application Support")
        let dbPaths = [
            (appSupport as NSString).appendingPathComponent("Code/User/globalStorage/state.vscdb"),
            (appSupport as NSString).appendingPathComponent("Code - Insiders/User/globalStorage/state.vscdb"),
        ]
        for dbPath in dbPaths where FileManager.default.fileExists(atPath: dbPath) {
            let queryProcess = Process()
            queryProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            queryProcess.arguments = [
                "-json",
                dbPath,
                "SELECT value FROM ItemTable WHERE key = 'Anthropic.claude-code';"
            ]
            let pipe = Pipe()
            queryProcess.standardOutput = pipe
            queryProcess.standardError = FileHandle.nullDevice
            guard (try? queryProcess.run()) != nil else { continue }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            queryProcess.waitUntilExit()
            guard queryProcess.terminationStatus == 0,
                  let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = rows.first,
                  let valueStr = first["value"] as? String,
                  let valueData = valueStr.data(using: .utf8),
                  var stateObj = try? JSONSerialization.jsonObject(with: valueData) as? [String: Any] else { continue }

            var hiddenList = stateObj["hiddenSessionIds"] as? [String] ?? []
            if isArchived {
                if !hiddenList.contains(id) { hiddenList.append(id) }
            } else {
                hiddenList.removeAll { $0 == id }
            }
            stateObj["hiddenSessionIds"] = hiddenList

            guard let updatedData = try? JSONSerialization.data(withJSONObject: stateObj),
                  let updatedStr = String(data: updatedData, encoding: .utf8) else { continue }

            let safeValue = updatedStr.replacingOccurrences(of: "'", with: "''")
            let updateSql = "UPDATE ItemTable SET value = '\(safeValue)' WHERE key = 'Anthropic.claude-code';"
            runSqlite(database: dbPath, sql: updateSql)
        }
    }
}
