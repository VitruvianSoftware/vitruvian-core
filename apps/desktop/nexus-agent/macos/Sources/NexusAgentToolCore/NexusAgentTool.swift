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

import Combine
import Foundation
import NexusAgentCore
import VitruvianToolKit
import VitruvianToolProtocol

/// The app, as the tool's core reaches it, on the main thread. The program
/// answers each over the kit's waker, on the kit's thread; the tests record.
@MainActor
public protocol ToolLink: AnyObject {
    func badge(count: Int?, dot: Bool)
    func render(panel: String, _ tree: UITree)
    func showMessage(_ message: String, icon: String)
    func log(_ message: String)
    func setValue(_ value: JSONValue, for key: String)
    func setRunnable(_ commands: [String])
}

/// The Quick Prompt's window, which the program owns.
@MainActor
public protocol QuickPromptWindow: AnyObject {
    var isVisible: Bool { get }
    func show()
    func hide()
    func toggle()
}

/// The shared engine with the one thing the tool adds: whether its window
/// shows the chat, which decides how a finished turn is told.
@MainActor
public final class ToolEngine: NexusAgentEngine {
    public var chatIsVisible: () -> Bool = { false }
    override public var isChatVisible: Bool { chatIsVisible() }
}

/// What the tool is: the engine, its settings, the app and the window,
/// tied together. Everything a handler of the kit's does comes here, on
/// the main thread, and everything the engine says goes back to the app
/// through the link. `main.swift` wires it and decides nothing.
@MainActor
public final class NexusAgentTool {
    public nonisolated static let islandPanel = "agent"
    public nonisolated static let settingsPanel = "settings"

    public enum Command {
        public static let quickPrompt = "quickPrompt"
        public static let newChat = "newChat"
        public static let startBot = "startBot"
        public static let stopBot = "stopBot"
        public static let all = [quickPrompt, newChat, startBot, stopBot]
    }

    public struct Parts {
        public var link: ToolLink
        public var settings: ToolSettings
        public var engine: ToolEngine
        public var window: QuickPromptWindow
        /// Asks the person for a folder; nil when they cancelled.
        public var chooseFolder: () -> String?
        /// Plays the "done" sound.
        public var playDone: () -> Void

        public init(link: ToolLink, settings: ToolSettings, engine: ToolEngine, window: QuickPromptWindow,
                    chooseFolder: @escaping () -> String? = { nil }, playDone: @escaping () -> Void = {}) {
            self.link = link
            self.settings = settings
            self.engine = engine
            self.window = window
            self.chooseFolder = chooseFolder
            self.playDone = playDone
        }
    }

    public let parts: Parts
    public private(set) var language = "en"
    public private(set) var openPanels: Set<String> = []
    public private(set) var awaitingApproval = false
    /// The `.env` as the person is editing it in the settings panel.
    public private(set) var draft = NexusAgentConfiguration()
    private var watching: Set<AnyCancellable> = []
    private var started = false

    public init(parts: Parts) {
        self.parts = parts
        parts.engine.chatIsVisible = { [weak window = parts.window] in window?.isVisible ?? false }
        parts.settings.preferenceChanged = { [weak self] key, value in self?.parts.link.setValue(value, for: key) }
        parts.settings.onApproval = { [weak self] notice in self?.turnNeedsApproval(notice) }
        parts.settings.onFinished = { [weak self] notice, visible in self?.turnFinished(notice, isChatVisible: visible) }
    }

    // MARK: - The app's messages

    /// The app said hello: takes what it handed over, starts the engine
    /// (and the bot, when asked for), and tells the app what may run. The
    /// handed copies of the untitled preferences are cleared once taken.
    public func start(language: String, handed: [String: JSONValue]) {
        self.language = language
        parts.settings.language = language
        let taken = parts.settings.apply(handed: handed)
        for key in taken { parts.link.setValue(.string(""), for: key) }
        if !taken.isEmpty { parts.link.log("took the feature's \(taken.joined(separator: ", ")) into settings.json") }
        if !started {
            started = true
            watch()
            parts.engine.load()
            draft = parts.engine.configuration
            parts.engine.startOncePerLaunch()
        }
        runnableChanged()
        badgeChanged()
    }

    public func preferencesChanged(_ values: [String: JSONValue]) {
        let before = parts.settings.values
        parts.settings.changed(values)
        if before.botDirectory != parts.settings.values.botDirectory {
            parts.engine.load()
            draft = parts.engine.configuration
            refreshOpenPanels()
        }
        if !before.planMode, parts.settings.values.planMode != before.planMode {
            parts.engine.session.planMode = parts.settings.values.planMode
        } else if before.planMode != parts.settings.values.planMode {
            parts.engine.session.planMode = parts.settings.values.planMode
        }
        if before.worktreeMode != parts.settings.values.worktreeMode {
            parts.engine.session.worktreeMode = parts.settings.values.worktreeMode
        }
    }

    public func languageChanged(_ language: String) {
        self.language = language
        parts.settings.language = language
        refreshOpenPanels()
    }

    /// The app said goodbye.
    public func stop() {
        parts.window.hide()
        parts.engine.stopForQuit()
    }

    public func run(command: String) throws {
        switch command {
        case Command.quickPrompt: parts.window.toggle()
        case Command.newChat:
            parts.engine.session.newChat()
            parts.window.show()
        case Command.startBot:
            guard !parts.engine.isRunning else { throw CommandRefused(Words.text("statusRunning", language)) }
            parts.engine.start()
        case Command.stopBot:
            guard parts.engine.isRunning else { throw CommandRefused(Words.text("statusStopped", language)) }
            parts.engine.stop()
        default: throw CommandRefused("no such command")
        }
    }

    // MARK: - Panels

    public func islandPage() -> UITree {
        openPanels.insert(Self.islandPanel)
        parts.engine.startPolling()
        parts.engine.session.refreshSessions(configuration: parts.engine.configuration)
        return Pages.island(status(), language: language)
    }

    public func islandEvent(_ event: PanelEvent) -> PanelAnswer {
        switch event.block {
        case Pages.Block.open?:
            parts.window.show()
            return .keep
        case Pages.Block.newChat?:
            parts.engine.session.newChat()
            parts.window.show()
            return .keep
        case Pages.Block.startBot?:
            parts.engine.start()
        case Pages.Block.stopBot?:
            parts.engine.stop()
        case Pages.Block.sessions?:
            guard let id = event.row, let summary = parts.engine.session.sessions.first(where: { $0.id == id }) else { return .keep }
            parts.engine.session.resume(summary, configuration: parts.engine.configuration)
            parts.window.show()
            return .keep
        default:
            return .keep
        }
        return .page(Pages.island(status(), language: language))
    }

    public func settingsPage() -> UITree {
        openPanels.insert(Self.settingsPanel)
        parts.engine.startPolling()
        draft = parts.engine.configuration
        return settingsTree()
    }

    public func settingsEvent(_ event: PanelEvent) -> PanelAnswer {
        switch event.block {
        case Pages.Block.startBot?: parts.engine.start()
        case Pages.Block.stopBot?: parts.engine.stop()
        case Pages.Block.restartBot?: parts.engine.restart()
        case Pages.Block.openLog?:
            parts.engine.openLog()
            return .keep
        case Pages.Block.token?: draft.botToken = event.text ?? draft.botToken
        case Pages.Block.allowedUsers?: draft.allowedUserIDs = event.text ?? draft.allowedUserIDs
        case Pages.Block.workingFolder?: draft.workingDirectory = event.text ?? draft.workingDirectory
        case Pages.Block.model?: draft.model = event.text ?? draft.model
        case Pages.Block.chooseFolder?:
            guard let folder = parts.chooseFolder() else { return .keep }
            draft.workingDirectory = folder
        case Pages.Block.approval?:
            guard let id = event.row, let mode = NexusAgentApprovalMode(rawValue: id) else { return .keep }
            draft.approvalMode = mode
        case Pages.Block.effort?:
            guard let id = event.row else { return .keep }
            draft.effortChoice = Pages.effortChoice(ofRow: id)
        case Pages.Block.save?:
            guard draft != parts.engine.configuration else { return .keep }
            if parts.engine.save(draft) { draft = parts.engine.configuration }
        default:
            return .keep
        }
        return .page(settingsTree())
    }

    public func panelClosed(_ panel: String) {
        openPanels.remove(panel)
        if openPanels.isEmpty { parts.engine.stopPolling() }
    }

    private func settingsTree() -> UITree {
        Pages.settings(status(), draft: draft, saved: parts.engine.configuration,
                       logLines: parts.engine.logLines, language: language)
    }

    /// What the pages show, read off the engine now.
    public func status() -> Pages.Status {
        var status = Pages.Status()
        status.isRunning = parts.engine.isRunning
        status.pid = parts.engine.pid
        status.problem = parts.engine.problemDescription
        status.needsRestart = parts.engine.needsRestart
        status.replyStreaming = parts.engine.session.isRunning
        status.awaitingApproval = awaitingApproval
        status.lastReply = parts.engine.session.messages.last { $0.role == .agent && !$0.isError }?.text
        status.sessions = parts.engine.session.sessions
        return status
    }

    // MARK: - What the engine says

    private func watch() {
        let engine = parts.engine
        let session = engine.session
        Publishers.MergeMany(
            engine.$isRunning.map { _ in () }.eraseToAnyPublisher(),
            engine.$pid.map { _ in () }.eraseToAnyPublisher(),
            engine.$problem.map { _ in () }.eraseToAnyPublisher(),
            engine.$logLines.map { _ in () }.eraseToAnyPublisher(),
            engine.$needsRestart.map { _ in () }.eraseToAnyPublisher(),
            session.$sessions.map { _ in () }.eraseToAnyPublisher())
            .dropFirst(6)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refreshOpenPanels() }
            .store(in: &watching)
        engine.$isRunning.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.runnableChanged() }
            .store(in: &watching)
        session.$isRunning.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self else { return }
                if running { awaitingApproval = false }
                badgeChanged()
                refreshOpenPanels()
            }
            .store(in: &watching)
    }

    private func refreshOpenPanels() {
        if openPanels.contains(Self.islandPanel) {
            parts.link.render(panel: Self.islandPanel, Pages.island(status(), language: language))
        }
        if openPanels.contains(Self.settingsPanel) {
            parts.link.render(panel: Self.settingsPanel, settingsTree())
        }
    }

    private func runnableChanged() {
        parts.link.setRunnable([Command.quickPrompt, Command.newChat,
                                parts.engine.isRunning ? Command.stopBot : Command.startBot])
    }

    /// One while a turn waits for approval; a dot while a reply arrives.
    private func badgeChanged() {
        if awaitingApproval {
            parts.link.badge(count: 1, dot: false)
        } else {
            parts.link.badge(count: nil, dot: parts.engine.session.isRunning)
        }
    }

    private func turnNeedsApproval(_ notice: NexusAgentTurnNotice) {
        awaitingApproval = true
        badgeChanged()
        refreshOpenPanels()
        parts.link.showMessage(parts.settings.strings.approvalRequiredTitle(provider: notice.providerName),
                               icon: "hand.raised.fill")
    }

    private func turnFinished(_ notice: NexusAgentTurnNotice, isChatVisible: Bool) {
        awaitingApproval = false
        badgeChanged()
        refreshOpenPanels()
        let strings = parts.settings.strings
        let title = notice.failed ? strings.failedTitle(provider: notice.providerName)
            : strings.doneTitle(provider: notice.providerName)
        if notice.endedCleanly { parts.playDone() }
        // The person who can see the chat has seen the reply.
        guard !isChatVisible || notice.failed else { return }
        parts.link.showMessage(title, icon: notice.failed ? "exclamationmark.triangle.fill" : "sparkles")
    }
}
