// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianToolProtocol

/// A tool that runs as its own program, as the tool host sees it: the
/// second kind of `HostedTool`. It owns the tool's program from one run to
/// the next. It starts it when it is first needed, stops it when it has
/// been idle, holds it back after a crash, and gives up on one that keeps
/// crashing.
///
/// It answers "can this run?" from what it already knows: the last list
/// the tool sent, and how the tool stands. It never sends a message to
/// find out.
@MainActor
package final class ExternalTool: HostedTool {
    package enum Standing: Equatable, Sendable {
        /// The host has not started it, or has stopped it.
        case off
        /// No program runs. The next need starts one.
        case resting
        /// A program runs and has not been greeted yet.
        case starting
        case running
        /// Its program is being ended.
        case stopping
        /// It crashed, and is held back until its wait is over.
        case waiting
        /// It crashed too often. It stays stopped until `revive`.
        case gaveUp
    }

    package struct Events {
        /// How the tool stands, or what it can run, changed: whoever lists
        /// its commands should look again.
        package var onChange: @MainActor () -> Void
        /// The tool stopped working. Called once for the life of the app.
        package var onStoppedWorking: @MainActor () -> Void
        /// A command was asked for and did not run.
        package var onCommandFailed: @MainActor () -> Void
        /// The tool sent a page for one of its panels: the panel's id, and
        /// the page as the tool wrote it.
        package var onRender: @MainActor (String, JSONValue) -> Void
        /// A run of the tool's program ended, however it ended: every panel
        /// it had open ends with it.
        package var onRunEnded: @MainActor () -> Void

        package init(onChange: @escaping @MainActor () -> Void = {},
                     onStoppedWorking: @escaping @MainActor () -> Void = {},
                     onCommandFailed: @escaping @MainActor () -> Void = {},
                     onRender: @escaping @MainActor (String, JSONValue) -> Void = { _, _ in },
                     onRunEnded: @escaping @MainActor () -> Void = {}) {
            self.onChange = onChange
            self.onStoppedWorking = onStoppedWorking
            self.onCommandFailed = onCommandFailed
            self.onRender = onRender
            self.onRunEnded = onRunEnded
        }
    }

    /// Makes the link for one run of the tool's program.
    package typealias MakeLink = @MainActor (ToolLink.Events) -> ToolLink

    package let id: ToolID
    /// What the tool said for its author to read.
    package let log: ToolLog

    private let commands: Set<String>
    private let startsAtLaunch: Bool
    private let clock: any ToolClock
    private let limits: ToolLimits
    private let makeLink: MakeLink
    private let events: Events

    private var allowed = false
    private var gaveUp = false
    private var link: ToolLink?
    /// The commands the tool said can run now; nil until it has said, and
    /// then every command can.
    private var runnable: Set<String>?
    /// Commands asked for while the program was starting.
    private var held: [String] = []
    /// Panels opened while the program was starting, with who waits for
    /// each first page.
    private var heldOpens: [(panel: String, then: @MainActor (Result<JSONValue, ToolLink.Failure>) -> Void)] = []
    /// The panels the person has open. While one is, the tool is not
    /// stopped for being idle.
    private var openPanels: Set<String> = []
    /// When each recent crash happened.
    private var crashes: [TimeInterval] = []
    private var nextWait: TimeInterval
    private var waitTimer: (any ToolTimer)?
    private var idleTimer: (any ToolTimer)?
    /// When this run of the program was greeted.
    private var readySince: TimeInterval?
    private var toldItStopped = false

    package init(manifest: ToolManifest, clock: any ToolClock, limits: ToolLimits = .standard,
                 makeLink: @escaping MakeLink, events: Events = Events()) {
        id = manifest.id
        log = ToolLog(limit: limits.logBytes)
        commands = Set(manifest.tool.commands.map(\.id.name))
        startsAtLaunch = manifest.activation.contains(.onLaunch)
        self.clock = clock
        self.limits = limits
        self.makeLink = makeLink
        self.events = events
        nextWait = limits.firstRestartWait
    }

    package var standing: Standing {
        guard allowed else { return .off }
        if gaveUp { return .gaveUp }
        if let link {
            switch link.state {
            case .ready: return .running
            case .idle, .starting: return .starting
            case .stopping, .ended: return .stopping
            }
        }
        return waitTimer == nil ? .resting : .waiting
    }

    // MARK: - HostedTool

    /// The host allows the tool to run. A tool that starts with the app
    /// starts now; any other waits for its first command.
    package func start() {
        guard !allowed else { return }
        allowed = true
        settle()
        events.onChange()
    }

    /// Stops the tool's program, with a goodbye, and starts nothing until
    /// `start` is called again.
    package func stop() {
        guard allowed else { return }
        allowed = false
        waitTimer?.cancel()
        waitTimer = nil
        idleTimer?.cancel()
        idleTimer = nil
        dropHeld()
        link?.shutdown()
        events.onChange()
    }

    package func canRun(_ command: CommandID) -> Bool {
        // A tool the app is stopping for what it did cannot run anything,
        // from that moment and not only once its program is gone.
        guard command.tool == id, commands.contains(command.name), allowed, !gaveUp, waitTimer == nil,
              link?.fault == nil else { return false }
        return runnable?.contains(command.name) ?? true
    }

    /// Runs a command, starting the program first when none runs. A
    /// command that cannot run, or that the tool then refuses or does not
    /// answer, is reported through `onCommandFailed`.
    package func run(_ command: CommandID) {
        guard canRun(command) else {
            events.onCommandFailed()
            return
        }
        if let link, link.state == .ready {
            send(command.name, on: link)
        } else if held.count < limits.commandsHeld {
            held.append(command.name)
            settle()
        } else {
            events.onCommandFailed()
        }
    }

    package var hasEnded: Bool { link?.hasEnded ?? true }

    // MARK: - Panels

    /// Asks for a panel's first page, starting the program first when none
    /// runs, as a command does. `then` hears the answer as the tool wrote
    /// it, or why there is none, once. While the panel is open the tool is
    /// not stopped for being idle.
    package func open(panel: String, then: @escaping @MainActor (Result<JSONValue, ToolLink.Failure>) -> Void) {
        guard allowed, !gaveUp, waitTimer == nil, link?.fault == nil else { return then(.failure(.notReady)) }
        openPanels.insert(panel)
        idleTimer?.cancel()
        idleTimer = nil
        if let link, link.state == .ready {
            link.open(panel: panel, then: then)
        } else if heldOpens.count < limits.commandsHeld {
            heldOpens.append((panel, then))
            settle()
        } else {
            then(.failure(.notReady))
        }
    }

    /// Tells the tool what the person did in an open panel. Nothing is
    /// started for it: a panel is open only while the program runs.
    package func event(_ event: UIEventParams, then: @escaping @MainActor (Result<JSONValue, ToolLink.Failure>) -> Void) {
        guard openPanels.contains(event.panel), let link, link.state == .ready else { return then(.failure(.notReady)) }
        link.event(event, then: then)
    }

    /// Tells the tool a panel went away. Once none is open the tool may be
    /// stopped for being idle again.
    package func close(panel: String) {
        guard openPanels.remove(panel) != nil else { return }
        link?.close(panel: panel)
        restartIdleTimer()
    }

    /// Tells the tool where its slot is now, or that it went. Only while
    /// the program runs: nothing is started for it.
    package func slot(_ params: UISlotParams) {
        guard standing == .running else { return }
        link?.slot(params)
    }

    /// Stops the program for something it did through one of its panels.
    package func misbehaved(_ fault: ToolLink.Fault) {
        link?.misbehaved(fault)
    }

    /// True while the panel is open.
    package func isOpen(panel: String) -> Bool {
        openPanels.contains(panel)
    }

    package func escalate() {
        link?.escalate()
    }

    // MARK: - For Settings, later

    /// Lets a tool that gave up try again, as if it had never crashed.
    package func revive() {
        guard gaveUp else { return }
        gaveUp = false
        crashes = []
        nextWait = limits.firstRestartWait
        settle()
        events.onChange()
    }

    /// Passes on new values of the tool's own preferences, when it runs.
    package func preferencesChanged(_ values: [String: JSONValue]) {
        link?.preferencesChanged(values)
    }

    /// Passes on the app's new language, when the tool runs.
    package func languageChanged(_ language: String) {
        link?.languageChanged(language)
    }

    // MARK: - One run

    /// Starts the program when it is wanted and nothing stands in the way,
    /// and fails the commands that were waiting when something does.
    private func settle() {
        guard allowed, !gaveUp, waitTimer == nil else {
            dropHeld()
            return
        }
        guard link == nil, startsAtLaunch || !held.isEmpty || !heldOpens.isEmpty else { return }
        runnable = nil
        readySince = nil
        let link = makeLink(ToolLink.Events(
            onChange: { [weak self] in self?.linkChanged() },
            onRunnable: { [weak self] names in
                self?.runnable = Set(names)
                self?.events.onChange()
            },
            onLog: { [weak self] text, source in self?.log.add(text, from: source) },
            onAsked: { [weak self] in self?.restartIdleTimer() },
            onRender: { [weak self] panel, tree in self?.events.onRender(panel, tree) },
            onEnd: { [weak self] end in self?.linkEnded(end) }))
        self.link = link
        log.add("starting", from: .runtime)
        link.start()
    }

    private func linkChanged() {
        guard let link else { return }
        if link.state == .ready, readySince == nil {
            readySince = clock.now
            restartIdleTimer()
            let waiting = held
            held = []
            for command in waiting { send(command, on: link) }
            let opening = heldOpens
            heldOpens = []
            for (panel, then) in opening { link.open(panel: panel, then: then) }
        }
        events.onChange()
    }

    private func send(_ command: String, on link: ToolLink) {
        restartIdleTimer()
        link.run(command) { [weak self] outcome in
            if case .failure = outcome { self?.events.onCommandFailed() }
        }
    }

    private func linkEnded(_ end: ToolLink.End) {
        link = nil
        runnable = nil
        idleTimer?.cancel()
        idleTimer = nil
        // A panel ends with its tool's program.
        openPanels = []
        events.onRunEnded()
        switch end {
        case .stopped:
            log.add("stopped", from: .runtime)
        case .exited(let status):
            log.add("ended by itself" + (status.map { ", status \($0)" } ?? ": it could not be started"),
                    from: .runtime)
            crashed()
        case .misbehaved(let fault):
            log.add("stopped by the app: \(fault)", from: .runtime)
            crashed()
        }
        settle()
        events.onChange()
    }

    /// The program ended without being asked to. It is held back for a wait
    /// that doubles each time, and given up on when it keeps happening.
    private func crashed() {
        let now = clock.now
        if !toldItStopped {
            toldItStopped = true
            events.onStoppedWorking()
        }
        // A run that stayed up for a whole window earns the short wait back.
        if let readySince, now - readySince >= limits.crashWindow { nextWait = limits.firstRestartWait }
        crashes = crashes.filter { now - $0 < limits.crashWindow } + [now]
        guard crashes.count < limits.crashesBeforeGivingUp else {
            gaveUp = true
            log.add("crashed \(crashes.count) times within \(Int(limits.crashWindow)) seconds: not started again",
                    from: .runtime)
            return
        }
        let wait = nextWait
        nextWait = min(nextWait * 2, limits.longestRestartWait)
        waitTimer = clock.after(wait) { [weak self] in
            guard let self else { return }
            waitTimer = nil
            settle()
            events.onChange()
        }
    }

    /// A tool that starts on a command is stopped once nothing has been
    /// asked of it, or by it, for a while. One that starts with the app
    /// keeps running.
    private func restartIdleTimer() {
        guard !startsAtLaunch, openPanels.isEmpty else { return }
        idleTimer?.cancel()
        idleTimer = clock.after(limits.idleStop) { [weak self] in
            guard let self else { return }
            idleTimer = nil
            if let link, link.state == .ready { link.shutdown() }
        }
    }

    private func dropHeld() {
        let opening = heldOpens
        heldOpens = []
        for (panel, then) in opening {
            openPanels.remove(panel)
            then(.failure(.notReady))
        }
        guard !held.isEmpty else { return }
        held = []
        events.onCommandFailed()
    }
}
