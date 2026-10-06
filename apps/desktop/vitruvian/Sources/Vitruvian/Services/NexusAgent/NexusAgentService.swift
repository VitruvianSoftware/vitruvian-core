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
        /// agy's recent conversations for a folder, newest first.
        package var listSessions: (_ directory: String) -> [NexusAgentSessionSummary]

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
                     listSessions: @escaping (String) -> [NexusAgentSessionSummary] = { _ in [] }) {
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
                listSessions: { NexusAgentService.readSessions(home: home, directory: $0) })
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

    package let session: NexusAgentQuickPromptSession
    private let environment: Environment
    private let hotkey = QuickToolHotkey(id: 25)
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
        agentPath = NexusAgentSupport.locateAgent(environment: environment.processEnvironment,
                                                  home: environment.home,
                                                  isExecutable: environment.isExecutable)
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
    }

    package func hideQuickPrompt() {
        guard let panel else { return }
        removeMonitors()
        panel.orderOut(nil)
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
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            // Mid-composition Esc belongs to the input method.
            if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            self.hideQuickPrompt()
            return nil
        }
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return event }
            if event.window !== panel, !Self.mouseIsInside(panel) { self.hideQuickPrompt() }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return }
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

    /// Reads agy's conversation index read-only; empty when agy has none.
    nonisolated static func readSessions(home: String, directory: String) -> [NexusAgentSessionSummary] {
        let database = (home as NSString).appendingPathComponent(".gemini/antigravity/conversation_summaries.db")
        guard FileManager.default.fileExists(atPath: database) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", "-readonly", database, NexusAgentSessionSummary.query]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        return NexusAgentSessionSummary.parse(data, directory: directory)
    }
}
