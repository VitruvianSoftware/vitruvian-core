// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Combine
import Foundation
import os
import VitruvianCore
import VitruvianToolProtocol

/// A web panel's page, as the panel host holds it. The host is the one
/// owner of every page: when a panel closes, or its tool ends, the host
/// lets go of it and the page is gone. The web view itself is drawn by the
/// UI layer, which makes one of these for the host to keep.
@MainActor
package protocol ToolWebPage: AnyObject {
    /// Delivers one of the app's notices to the page's
    /// `window.vitruvian.on` handlers, with the params the tool is sent.
    func emit(_ name: String, _ params: JSONValue)
    /// The page goes: it stops loading and running.
    func close()
}

extension RestingStatus {
    /// The page a click on the closed island's wing opens, when the mark it
    /// shows is a tool's: that tool's island page, unless the mark says all
    /// is well, which asks for nothing. `pages` is the island pages the
    /// Tools area lists, so a tool with no island page, or one whose page
    /// the person hid, gives nil. Nil too for the built-in mark and for no
    /// mark: the click then does what it always did.
    package static func opens(_ mark: RestingMark?, pages: [ToolPanelHost.Key]) -> ToolPanelHost.Key? {
        guard case .tool(let tool, let status)? = mark, status.state != .ok else { return nil }
        return pages.first { $0.tool == tool }
    }

    /// What the closed island's status mark says now, for the island's one
    /// button: the words of the tool's mark the wing shows. Nil when the
    /// wing shows no tool's mark: none is set, the built-in mark wins, or
    /// the Nexus session is running and the wing shows that instead.
    @MainActor package static func saidNow(language: AppLanguage) -> String? {
        guard !NexusAgentService.shared.session.isRunning else { return nil }
        let gitHub = GitHubService.shared
        let store = ExternalToolStore.shared
        let mark = winner(gitHub: Self.gitHub(watching: gitHub.watchedRepositories.count,
                                              aggregate: gitHub.summary.aggregate),
                          tools: shown(of: store.statusTools(), statuses: ToolPanelHost.shared.statuses))
        guard case .tool(let id, let status)? = mark else { return nil }
        let tool = store.installed[id]?.tool
        let name = tool?.name.text(for: language.rawValue) ?? tool?.manifest.tool.name ?? id.rawValue
        return words(for: status, toolName: name, language: language, strings: FeatureStrings.externalTools(language))
    }

    /// Fires when what `saidNow` gives may have changed.
    @MainActor package static var saidChanges: AnyPublisher<Void, Never> {
        Publishers.Merge5(ToolPanelHost.shared.$statuses.map { _ in }.eraseToAnyPublisher(),
                          ToolRegistry.shared.objectWillChange.eraseToAnyPublisher(),
                          GitHubService.shared.objectWillChange.eraseToAnyPublisher(),
                          NexusAgentService.shared.session.objectWillChange.eraseToAnyPublisher(),
                          L10n.shared.objectWillChange.eraseToAnyPublisher())
            .eraseToAnyPublisher()
    }
}

/// What tools from outside draw: for every panel the person has open, the
/// last page its tool sent, and the tool's badge. It asks a tool for a
/// panel's page, draws at most four of the pages a tool sends unprompted in
/// a second, passes on what the person did, and passes a web panel's calls
/// to the tool's program.
///
/// It lives on the main actor and never waits. A page is read away from the
/// main thread (`Parts.read`), and drawn on it.
@MainActor
package final class ToolPanelHost: ObservableObject {
    /// One panel of one tool.
    package struct Key: Hashable, Sendable {
        package let tool: ToolID
        package let panel: String

        package init(tool: ToolID, panel: String) {
            self.tool = tool
            self.panel = panel
        }
    }

    /// What an open panel shows.
    package enum Shown: Equatable, Sendable {
        /// The tool has not answered yet.
        case waiting
        /// The last page the tool sent.
        case page(UITree)
        /// A web panel's page, a file inside `folder`.
        case web(page: URL, folder: URL)
        /// It could not be shown: the page did not load, or the tool did
        /// not answer. The tool's log says which.
        case notShown
    }

    /// The tool's mark beside it in the island's Tools area.
    package enum Badge: Equatable, Sendable {
        case count(Int)
        case dot
    }

    /// Why the host would not do what it was asked. Each is the protocol's
    /// "params are wrong", -32602, for whoever needs a code.
    package enum Refusal: Error, Equatable, Sendable {
        /// The tool's manifest declares no panel with this id.
        case unknownPanel(String)
        /// The panel is not in the place it was opened in.
        case wrongPlace(String)
        /// The panel is not open.
        case notOpen(String)
        /// The tool's manifest declares no status, so it may set none.
        case noStatus

        package var error: RPCErrorObject {
            switch self {
            case .noStatus:
                return RPCErrorObject(code: RPCErrorCode.invalidParams, message: "the manifest declares no status")
            case .unknownPanel: return RPCErrorObject(code: RPCErrorCode.invalidParams, message: "no such panel")
            case .wrongPlace: return RPCErrorObject(code: RPCErrorCode.invalidParams, message: "not a panel of this place")
            case .notOpen: return RPCErrorObject(code: RPCErrorCode.invalidParams, message: "the panel is not open")
            }
        }
    }

    /// Everything the host reaches, so a test can stand in for each.
    package struct Parts {
        package var clock: any ToolClock
        package var limits: ToolLimits
        /// The live tool with this id.
        package var tool: @MainActor (ToolID) -> ExternalTool?
        /// What the tool's manifest says, for its panels.
        package var described: @MainActor (ToolID) -> ExternalToolManifest?
        /// The app's copy of the tool's folder, where a web panel's page is.
        package var folder: @MainActor (ToolID) -> URL?
        /// Reads a page away from the main thread, then hands it back on the
        /// main thread.
        package var read: @MainActor (JSONValue, @escaping @MainActor (Result<UITree, ToolPanelProblem>) -> Void) -> Void
        /// A line for the tool's log.
        package var log: @MainActor (ToolID, String) -> Void
        /// The alert sound, for something the person did that did nothing.
        package var beep: @MainActor () -> Void
        /// The tool did what the app does not put up with, through a web
        /// panel: it is stopped as a flood is.
        package var misbehaved: @MainActor (ToolID) -> Void
        /// Opens a link of a tool's page through the tool's own `open`
        /// service. False when it was refused, or nothing opened it.
        package var openLink: @MainActor (ToolID, URL) -> Bool

        package init(clock: any ToolClock, limits: ToolLimits = .standard,
                     tool: @escaping @MainActor (ToolID) -> ExternalTool?,
                     described: @escaping @MainActor (ToolID) -> ExternalToolManifest?,
                     folder: @escaping @MainActor (ToolID) -> URL?,
                     read: @escaping @MainActor (JSONValue, @escaping @MainActor (Result<UITree, ToolPanelProblem>) -> Void)
                         -> Void = ToolPanelHost.readAway,
                     log: @escaping @MainActor (ToolID, String) -> Void = { _, _ in },
                     beep: @escaping @MainActor () -> Void = {},
                     misbehaved: @escaping @MainActor (ToolID) -> Void = { _ in },
                     openLink: @escaping @MainActor (ToolID, URL) -> Bool = { _, _ in false }) {
            self.clock = clock
            self.limits = limits
            self.tool = tool
            self.described = described
            self.folder = folder
            self.read = read
            self.log = log
            self.beep = beep
            self.misbehaved = misbehaved
            self.openLink = openLink
        }

        /// The app as it is.
        @MainActor package static let live = Parts(
            clock: SystemToolClock.shared,
            tool: { ExternalToolStore.shared.tool($0) },
            described: { id in ExternalToolStore.shared.installed[id]?.tool },
            folder: { id in ExternalToolStore.shared.installed[id]?.files },
            log: { id, text in ExternalToolStore.shared.tool(id)?.log.add(text, from: .runtime) },
            beep: { CapabilityBroker.shared.backings.notify.beep() },
            misbehaved: { ExternalToolStore.shared.tool($0)?.misbehaved(.flood) },
            openLink: { id, url in
                guard let manifest = ExternalToolStore.shared.installed[id]?.tool.manifest else { return false }
                return (try? CapabilityBroker.shared.services(for: manifest).open.url(url).get()) == true
            })
    }

    /// Reads a page on a queue of its own and hands it back on the main
    /// thread. A page may weigh 256 KB: reading it is kept off the thread
    /// that draws.
    package static func readAway(_ value: JSONValue,
                                 then: @escaping @MainActor (Result<UITree, ToolPanelProblem>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let read = ToolPanelTree.read(value)
            DispatchQueue.main.async { MainActor.assumeIsolated { then(read) } }
        }
    }

    package static let shared = ToolPanelHost(parts: .live)

    /// What each open panel shows. A panel that is not here is not open.
    @Published package private(set) var shown: [Key: Shown] = [:]
    /// Each tool's badge. A tool with none is not here.
    @Published package private(set) var badges: [ToolID: Badge] = [:]
    /// The window panels that are open, in the order they were opened.
    @Published package private(set) var windows: [Key] = []
    /// The island page that is open, when one is.
    @Published package private(set) var island: Key?
    /// Each tool's status, the last it set, as shown: a change is published
    /// at most once a second for each tool. A tool with none is not here.
    /// Whether a tool's is drawn is the store's to say (`statusTools`).
    @Published package private(set) var statuses: [ToolID: ToolStatus] = [:]

    private let parts: Parts
    /// For each open panel: when a page it was sent was last drawn, the page
    /// waiting to be drawn, the timer that will draw it, and a count that
    /// tells a page read late from the newest.
    private var drawing: [Key: Drawing] = [:]
    /// The pages of open web panels, the host's to keep and to let go of.
    private var pages: [Key: any ToolWebPage] = [:]
    /// For each web panel, the second its calls are counted in, how many it
    /// has had, and how many seconds before it in a row had too many.
    private var calls: [Key: Calls] = [:]
    /// For each tool: when its status was last shown, the one waiting to be
    /// shown, and the timer that will show it.
    private var statusPacing: [ToolID: StatusPacing] = [:]

    private struct StatusPacing {
        var last: TimeInterval?
        /// The newest status not shown yet. The inner nil is "none".
        var pending: ToolStatus??
        var timer: (any ToolTimer)?
    }

    private struct Drawing {
        var last: TimeInterval?
        var pending: JSONValue?
        var timer: (any ToolTimer)?
        var sequence = 0
    }

    private struct Calls {
        var second: TimeInterval
        var count = 0
        var busySeconds = 0
    }

    package init(parts: Parts) {
        self.parts = parts
    }

    // MARK: - Opening and closing

    /// Opens one of a tool's panels in `place`: asks the tool for its first
    /// page, or shows a web panel's page. Gives back why it was not opened.
    @discardableResult
    package func open(_ key: Key, in place: ToolPanelPlacement) -> Refusal? {
        guard let panel = parts.described(key.tool)?.panel(key.panel) else { return .unknownPanel(key.panel) }
        guard panel.placement == place else { return .wrongPlace(key.panel) }
        guard shown[key] == nil else { return nil }
        guard let tool = parts.tool(key.tool) else { return .notOpen(key.panel) }
        if let entry = panel.entry {
            if let folder = parts.folder(key.tool), let page = ToolWebPolicy.entry(entry, in: folder) {
                shown[key] = .web(page: page, folder: folder)
            } else {
                shown[key] = .notShown
                parts.log(key.tool, "the page of the panel \(key.panel), \(entry), is not a file inside the tool's folder")
            }
        } else {
            shown[key] = .waiting
        }
        drawing[key] = Drawing()
        if place == .window, !windows.contains(key) { windows.append(key) }
        if place == .island { island = key }
        tool.open(panel: key.panel) { [weak self] answer in self?.opened(key, answer) }
        return nil
    }

    /// Closes an open panel and tells its tool. Its page goes, and any page
    /// still waiting to be drawn with it.
    package func close(_ key: Key) {
        guard shown[key] != nil else { return }
        forgetPanel(key)
        parts.tool(key.tool)?.close(panel: key.panel)
    }

    private func opened(_ key: Key, _ answer: Result<JSONValue, ToolLink.Failure>) {
        guard let now = shown[key] else { return }
        switch answer {
        case .success(let value):
            guard case .waiting = now else { return }
            guard let tree = value["tree"] else { return }
            draw(key, tree)
        case .failure(let failure):
            parts.log(key.tool, "the panel \(key.panel) was not opened: \(failure)")
            if case .waiting = now { shown[key] = .notShown }
        }
    }

    // MARK: - Pages a tool sends

    /// A page the tool sent unprompted. One for a panel its manifest does
    /// not declare, or that is not open, is dropped and logged. Of the pages
    /// that come quicker than four a second for one panel, the last one is
    /// drawn when the second allows.
    package func rendered(_ tool: ToolID, panel: String, tree: JSONValue) {
        let key = Key(tool: tool, panel: panel)
        guard parts.described(tool)?.panel(panel) != nil else {
            return parts.log(tool, "a page for the panel \(panel), which the manifest does not declare, was dropped")
        }
        guard shown[key] != nil, var state = drawing[key] else {
            return parts.log(tool, "a page for the panel \(panel), which is not open, was dropped")
        }
        let gap = 1 / Double(UILimits.rendersPerSecond)
        let now = parts.clock.now
        if state.timer == nil, state.last.map({ now - $0 >= gap }) ?? true {
            state.last = now
            drawing[key] = state
            draw(key, tree)
        } else {
            state.pending = tree
            if state.timer == nil {
                let wait = max(0, (state.last ?? now) + gap - now)
                state.timer = parts.clock.after(wait) { [weak self] in self?.drawWaiting(key) }
            }
            drawing[key] = state
        }
    }

    private func drawWaiting(_ key: Key) {
        guard var state = drawing[key] else { return }
        state.timer = nil
        guard let tree = state.pending else {
            drawing[key] = state
            return
        }
        state.pending = nil
        state.last = parts.clock.now
        drawing[key] = state
        draw(key, tree)
    }

    /// Reads a page away from the main thread and draws it, unless a newer
    /// one was started meanwhile or the panel closed. A page that cannot be
    /// read leaves the last one drawn, and the tool's log says why.
    private func draw(_ key: Key, _ tree: JSONValue) {
        guard var state = drawing[key] else { return }
        state.sequence += 1
        let mine = state.sequence
        drawing[key] = state
        parts.read(tree) { [weak self] read in
            guard let self, self.drawing[key]?.sequence == mine, self.shown[key] != nil else { return }
            switch read {
            case .success(let page):
                self.shown[key] = .page(page)
            case .failure(.tooLarge(let bytes)):
                self.parts.log(key.tool, "a page of \(bytes) bytes for the panel \(key.panel) was not drawn: "
                    + "the most is \(UILimits.maxTreeBytes)")
            case .failure(.notWellFormed(let place)):
                self.parts.log(key.tool, "a page for the panel \(key.panel) was not drawn: \(place) is not well formed")
            }
        }
    }

    // MARK: - What the person did

    /// Tells the tool what the person did in an open panel. The answer's
    /// page is drawn at once; `keep` leaves the page as it is; `open` opens
    /// one of the tool's windows. An event that was not answered plays the
    /// alert sound.
    @discardableResult
    package func act(_ key: Key, block: String, event: UIEventKind, value: JSONValue? = nil) -> Refusal? {
        guard shown[key] != nil else { return .notOpen(key.panel) }
        guard let tool = parts.tool(key.tool) else { return .notOpen(key.panel) }
        let params = UIEventParams(panel: key.panel, block: block, event: event, value: value)
        tool.event(params) { [weak self] answer in self?.answered(key, answer) }
        return nil
    }

    private func answered(_ key: Key, _ answer: Result<JSONValue, ToolLink.Failure>) {
        switch answer {
        case .success(let value):
            guard shown[key] != nil else { return }
            if let tree = value["tree"], value["keep"]?.boolValue != true {
                // The answer to the person is newer than any page waiting.
                drawing[key]?.pending = nil
                draw(key, tree)
            }
            if let window = value["open"]?.stringValue { openAsked(key.tool, window) }
        case .failure(let failure):
            parts.log(key.tool, "what the person did in the panel \(key.panel) was not answered: \(failure)")
            parts.beep()
        }
    }

    /// A window the tool asked to open in answer to the person. Only one of
    /// its own window panels.
    private func openAsked(_ tool: ToolID, _ panel: String) {
        if let refusal = open(Key(tool: tool, panel: panel), in: .window) {
            parts.log(tool, "the window \(panel) was not opened: \(refusal.error.message)")
        }
    }

    /// The schemes a `link` block may open.
    nonisolated package static let linkSchemes: Set<String> = ["http", "https", "mailto"]

    /// The person clicked a `link` block. It opens through the tool's own
    /// `open` service, so a tool whose manifest does not list `open` is
    /// refused, and the alert sound plays, as for a command that did not
    /// run.
    package func follow(_ key: Key, _ url: URL) {
        guard shown[key] != nil else { return }
        guard let scheme = url.scheme?.lowercased(), Self.linkSchemes.contains(scheme), parts.openLink(key.tool, url) else {
            parts.log(key.tool, "the link \(url.absoluteString) of the panel \(key.panel) was not opened")
            return parts.beep()
        }
    }

    // MARK: - A web panel's page

    /// Keeps a web panel's page for as long as the panel is open. A page
    /// for a panel that is not open is closed at once.
    package func keep(_ page: any ToolWebPage, for key: Key) {
        guard shown[key] != nil else { return page.close() }
        if let old = pages[key], old !== page { old.close() }
        pages[key] = page
    }

    /// The page kept for an open web panel.
    package func page(for key: Key) -> (any ToolWebPage)? {
        pages[key]
    }

    /// A web panel's page could not be shown: it did not load, or tried to
    /// go outside its folder. `why` goes to the tool's log.
    package func notShown(_ key: Key, why: String) {
        guard shown[key] != nil else { return }
        shown[key] = .notShown
        parts.log(key.tool, "the page of the panel \(key.panel) could not be shown: \(why)")
    }

    /// A web panel's page tried to go where it may not: outside its tool's
    /// folder, to the network, or to a new window. It was not let; the page
    /// stays, and the tool's log says where it tried to go.
    package func refused(_ key: Key, _ url: URL?) {
        guard shown[key] != nil else { return }
        parts.log(key.tool, "the page of the panel \(key.panel) tried to go to \(url?.absoluteString ?? "a new window"), "
            + "outside the tool's folder, and was not let")
    }

    /// A call a web panel's page made with `window.vitruvian.call`. A
    /// request a tool may make of the app is passed to the tool's program
    /// only when its manifest lists what it needs in `uses`; a method of
    /// the tool's own starts with `tool/`; anything else is not a method.
    /// The page is held to the link's flood rule: more than so many calls a
    /// second are refused, and enough such seconds in a row stop the tool.
    /// `reply` hears the answer once.
    package func call(_ key: Key, method: String, params: JSONValue?,
                      reply: @escaping @MainActor (Result<JSONValue, RPCErrorObject>) -> Void) {
        guard shown[key] != nil, let tool = parts.tool(key.tool), let manifest = parts.described(key.tool) else {
            return reply(.failure(Refusal.notOpen(key.panel).error))
        }
        if let known = ToolMethod(rawValue: method) {
            guard known.sender == .tool, known.isAnswered else {
                return reply(.failure(RPCErrorObject(code: RPCErrorCode.methodNotFound, message: "unknown method")))
            }
            if let service = known.service,
               !manifest.manifest.capabilities.contains(where: { $0.capability.rawValue == service.rawValue }) {
                return reply(.failure(RefusalCode.notInUses.error(service: service)))
            }
        } else if !method.hasPrefix(UIBridgeCall.toolsOwn) {
            return reply(.failure(RPCErrorObject(code: RPCErrorCode.methodNotFound, message: "unknown method")))
        }
        guard counted(key) else { return reply(.failure(RefusalCode.unavailable.error())) }
        let asked = (try? JSONValue(encoding: UIBridgeCall(method: method, params: params))) ?? .null
        tool.event(UIEventParams(panel: key.panel, event: .bridge, value: asked)) { answer in
            switch answer {
            case .success(let value): reply(.success(value["reply"] ?? .null))
            case .failure(.refused(let error)): reply(.failure(error))
            case .failure: reply(.failure(RefusalCode.unavailable.error()))
            }
        }
    }

    /// Counts one call against its second. False when that second has had
    /// too many; enough such seconds in a row is a flood, and the tool is
    /// stopped.
    private func counted(_ key: Key) -> Bool {
        let now = parts.clock.now
        var state = calls[key] ?? Calls(second: now)
        let elapsed = now - state.second
        if elapsed >= 1 {
            let wasBusy = state.count > parts.limits.messagesPerSecond
            state.busySeconds = wasBusy && elapsed < 2 ? state.busySeconds + 1 : 0
            state.second = elapsed < 2 ? state.second + 1 : now
            state.count = 0
        }
        state.count += 1
        calls[key] = state
        guard state.count > parts.limits.messagesPerSecond else { return true }
        if state.busySeconds + 1 >= parts.limits.floodSeconds {
            parts.log(key.tool, "the page of the panel \(key.panel) made too many calls: the tool is stopped")
            parts.misbehaved(key.tool)
        }
        return false
    }

    /// Tells a tool's open web pages one of the app's notices, as its
    /// program is told it.
    package func tellPages(of tool: ToolID, _ method: ToolMethod, _ params: JSONValue) {
        for (key, page) in pages where key.tool == tool { page.emit(method.rawValue, params) }
    }

    // MARK: - The badge

    /// A tool's badge, from its `ui/badge`: a count above zero, else a dot,
    /// else none.
    package func badge(_ tool: ToolID, _ asked: UIBadgeParams) {
        if let count = asked.count, count > 0 {
            badges[tool] = .count(count)
        } else if asked.dot == true {
            badges[tool] = .dot
        } else {
            badges[tool] = nil
        }
    }

    // MARK: - The status

    /// The seconds between two changes of one tool's status that are shown.
    package static let statusSeconds: TimeInterval = 1

    /// A tool's status, from its `ui/status`: kept in place of the last
    /// one, or taken away for `none`. Gives back why it was not: a tool
    /// whose manifest declares no status may set none.
    ///
    /// The first change after a quiet second is shown at once. Later ones
    /// within the second replace each other, and the newest is shown when
    /// the second is up.
    @discardableResult
    package func status(_ tool: ToolID, _ asked: UIStatusParams) -> Refusal? {
        guard parts.described(tool)?.showsStatus == true else { return .noStatus }
        let next = ToolStatus(asked)
        var pacing = statusPacing[tool] ?? StatusPacing()
        let now = parts.clock.now
        if pacing.timer == nil, pacing.last.map({ now - $0 >= Self.statusSeconds }) ?? true {
            pacing.last = now
            statusPacing[tool] = pacing
            show(next, for: tool)
        } else {
            pacing.pending = .some(next)
            if pacing.timer == nil {
                let wait = max(0, (pacing.last ?? now) + Self.statusSeconds - now)
                pacing.timer = parts.clock.after(wait) { [weak self] in self?.showWaitingStatus(of: tool) }
            }
            statusPacing[tool] = pacing
        }
        return nil
    }

    private func showWaitingStatus(of tool: ToolID) {
        guard var pacing = statusPacing[tool] else { return }
        pacing.timer = nil
        guard let next = pacing.pending else {
            statusPacing[tool] = pacing
            return
        }
        pacing.pending = nil
        pacing.last = parts.clock.now
        statusPacing[tool] = pacing
        show(next, for: tool)
    }

    /// Publishes a tool's status, when it is another than the one shown.
    private func show(_ status: ToolStatus?, for tool: ToolID) {
        if statuses[tool] != status { statuses[tool] = status }
    }

    /// A tool's status goes, and any waiting to be shown with it.
    private func forgetStatus(of tool: ToolID) {
        statusPacing.removeValue(forKey: tool)?.timer?.cancel()
        if statuses[tool] != nil { statuses[tool] = nil }
    }

    // MARK: - A tool that ends

    /// A run of the tool's program ended: every panel it had open ends with
    /// it, and so does its status, which never outlives its program. Its
    /// badge stays until the tool is switched off or removed.
    package func toolEnded(_ tool: ToolID) {
        for key in shown.keys where key.tool == tool { forgetPanel(key) }
        forgetStatus(of: tool)
    }

    /// The tool was switched off, updated or removed: its panels, its
    /// status and its badge go.
    package func forget(_ tool: ToolID) {
        toolEnded(tool)
        forgetStatus(of: tool)
        badges[tool] = nil
    }

    private func forgetPanel(_ key: Key) {
        shown[key] = nil
        drawing[key]?.timer?.cancel()
        drawing[key] = nil
        calls[key] = nil
        pages.removeValue(forKey: key)?.close()
        windows.removeAll { $0 == key }
        if island == key { island = nil }
    }
}
