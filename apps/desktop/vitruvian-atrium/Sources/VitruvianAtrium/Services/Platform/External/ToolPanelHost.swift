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
    /// island lists as sections, so a tool with no island page, or one whose page
    /// the person hid, gives nil. Nil too for no mark: the click then does
    /// what it always did. Nil while a Nexus session runs: the wings show
    /// the session then, not the tool's mark, so the click goes where the
    /// wings point, the Agents page.
    package static func opens(_ mark: RestingMark?, pages: [ToolPanelHost.Key],
                              nexusRunning: Bool) -> ToolPanelHost.Key? {
        guard !nexusRunning else { return nil }
        guard case .tool(let tool, let status)? = mark, status.state != .ok else { return nil }
        return pages.first { $0.tool == tool }
    }

    /// What the closed island's status mark says now, for the island's one
    /// button: the words of the tool's mark the wing shows. Nil when the
    /// wing shows no tool's mark: none is set.
    @MainActor package static func saidNow(language: AppLanguage) -> String? {
        let store = ExternalToolStore.shared
        let mark = winner(tools: shown(of: store.statusTools(), statuses: ToolPanelHost.shared.statuses))
        guard case .tool(let id, let status)? = mark else { return nil }
        let tool = store.installed[id]?.tool
        let name = tool?.name.text(for: language.rawValue) ?? tool?.manifest.tool.name ?? id.rawValue
        return words(for: status, toolName: name, language: language, strings: FeatureStrings.externalTools(language))
    }

    /// Fires when what `saidNow` gives may have changed.
    @MainActor package static var saidChanges: AnyPublisher<Void, Never> {
        Publishers.Merge3(ToolPanelHost.shared.$statuses.map { _ in }.eraseToAnyPublisher(),
                          ToolRegistry.shared.objectWillChange.eraseToAnyPublisher(),
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
        /// It could not be shown: the page did not load, the tool did not
        /// answer, or the tool's first page was refused. The tool's log says
        /// which; a refused page is also held here, so the panel can say why
        /// where the page would be.
        case notShown(ToolPanelProblem?)
    }

    /// The tool's mark on its section's tile in Explore.
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
        /// The tool's manifest declares no slot, so it may not dock.
        case noSlot

        package var error: RPCErrorObject {
            switch self {
            case .noStatus:
                return RPCErrorObject(code: RPCErrorCode.invalidParams, message: "the manifest declares no status")
            case .noSlot:
                return RPCErrorObject(code: RPCErrorCode.invalidParams, message: "the manifest declares no slot")
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
        /// Brings Settings to the front on the Extensions page, showing this
        /// tool's detail, where its settings panel is drawn.
        package var openSettings: @MainActor (ToolID) -> Void
        /// Shows a tool's notice: a line in the island, and a macOS
        /// notification when it asks for one.
        package var notice: @MainActor (NotifyNoticeParams) -> Void
        /// Opens the island on the Agents page's Chat tab, where the slot is.
        package var dockAgents: @MainActor () -> Void

        package init(clock: any ToolClock, limits: ToolLimits = .standard,
                     tool: @escaping @MainActor (ToolID) -> ExternalTool?,
                     described: @escaping @MainActor (ToolID) -> ExternalToolManifest?,
                     folder: @escaping @MainActor (ToolID) -> URL?,
                     read: @escaping @MainActor (JSONValue, @escaping @MainActor (Result<UITree, ToolPanelProblem>) -> Void)
                         -> Void = ToolPanelHost.readAway,
                     log: @escaping @MainActor (ToolID, String) -> Void = { _, _ in },
                     beep: @escaping @MainActor () -> Void = {},
                     misbehaved: @escaping @MainActor (ToolID) -> Void = { _ in },
                     openLink: @escaping @MainActor (ToolID, URL) -> Bool = { _, _ in false },
                     openSettings: @escaping @MainActor (ToolID) -> Void = { _ in },
                     notice: @escaping @MainActor (NotifyNoticeParams) -> Void = { _ in },
                     dockAgents: @escaping @MainActor () -> Void = {}) {
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
            self.openSettings = openSettings
            self.notice = notice
            self.dockAgents = dockAgents
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
            },
            openSettings: { id in
                // The island closes first, as for its own Settings buttons;
                // the menu bar panel stays beside Settings.
                NotchService.shared.perform {
                    SettingsRouter.shared.request(extension: id)
                    appShell()?.openSettingsWindow()
                }
            },
            notice: { asked in
                _ = NotchService.shared.show(NotchNotice(event: .agents, title: asked.title, detail: asked.detail ?? "",
                                                         symbol: asked.icon))
                if asked.system == true { Notifier.post(title: asked.title, body: asked.detail ?? "") }
            },
            dockAgents: { NotchService.shared.dockAgentsSlot() })
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
    /// How many pages each panel has been sent, the same as the last or
    /// not: a page drawn again unchanged is still the tool's answer. Set
    /// before `shown`, whose change publishes it.
    package private(set) var revisions: [Key: Int] = [:]
    /// Each tool's badge. A tool with none is not here.
    @Published package private(set) var badges: [ToolID: Badge] = [:]
    /// The window panels that are open, in the order they were opened.
    @Published package private(set) var windows: [Key] = []
    /// The island page that is open, when one is.
    @Published package private(set) var island: Key?
    /// The island pages the menu bar panel shows too, each with the views
    /// that show it, one token for each: the popover's card and the card in
    /// the copy of the panel inside the island can both be up, and an
    /// extension's new card can appear before its old one goes. A page here
    /// stays open while the island lets go of it, and the other way round.
    package private(set) var inMenuPanel: [Key: Set<UUID>] = [:]
    /// The pages Settings shows besides the place they belong to, each with
    /// the views that show it, one token for each: the Dynamic Island page
    /// draws an extension's island page and its settings page there. A
    /// viewer never closes a page another place shows, and the page stays
    /// open for it while that place lets go (`openAsViewer`).
    package private(set) var viewers: [Key: Set<UUID>] = [:]
    /// Each tool's status, the last it set, as shown: a change is published
    /// at most once a second for each tool. A tool with none is not here.
    /// Whether a tool's is drawn is the store's to say (`statusTools`).
    @Published package private(set) var statuses: [ToolID: ToolStatus] = [:]

    private let parts: Parts
    /// The settings pages the Extensions sheet has open: the place they
    /// belong to, which a viewer leaving does not close.
    private var inSettings: Set<Key> = []
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
    /// The tools whose undeclared words were left out in this run of their
    /// program, and logged: once for each run.
    private var wordsLeftOut: Set<ToolID> = []

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
        guard shown[key] == nil else {
            // Open already, for the menu bar panel or a viewer: this place
            // shows the same page, and the tool is asked nothing.
            hold(key, in: place)
            return nil
        }
        guard let tool = parts.tool(key.tool) else { return .notOpen(key.panel) }
        begin(key, panel)
        hold(key, in: place)
        tool.open(panel: key.panel) { [weak self] answer in self?.opened(key, answer) }
        return nil
    }

    /// `place` shows the open panel `key`: the one it belongs to.
    private func hold(_ key: Key, in place: ToolPanelPlacement) {
        switch place {
        case .island: island = key
        case .settings: inSettings.insert(key)
        case .window: if !windows.contains(key) { windows.append(key) }
        }
    }

    /// What every opening shows first: a web panel's page, or a wait for
    /// the tool's first page.
    private func begin(_ key: Key, _ panel: ToolPanelDescriptor) {
        if let entry = panel.entry {
            if let folder = parts.folder(key.tool), let page = ToolWebPolicy.entry(entry, in: folder) {
                shown[key] = .web(page: page, folder: folder)
            } else {
                shown[key] = .notShown(nil)
                parts.log(key.tool, "the page of the panel \(key.panel), \(entry), is not a file inside the tool's folder")
            }
        } else {
            shown[key] = .waiting
        }
        drawing[key] = Drawing()
    }

    /// The place a panel belongs to lets go of it: the island, the
    /// Extensions sheet or its window. The panel closes and its tool is
    /// told; its page goes, and any page still waiting to be drawn with it.
    /// A page the menu bar panel or a viewer shows too stays open for them:
    /// only the place lets go.
    package func close(_ key: Key) {
        guard shown[key] != nil else { return }
        if island == key { island = nil }
        inSettings.remove(key)
        if windows.contains(key) { windows.removeAll { $0 == key } }
        closeIfNoneShows(key)
    }

    /// Closes the panel and tells its tool, unless a place, the menu bar
    /// panel or a viewer still shows it.
    private func closeIfNoneShows(_ key: Key) {
        guard shown[key] != nil, island != key, !inSettings.contains(key), !windows.contains(key),
              inMenuPanel[key] == nil, viewers[key] == nil else { return }
        forgetPanel(key)
        parts.tool(key.tool)?.close(panel: key.panel)
    }

    // MARK: - The menu bar panel

    /// Shows a tool's island page in the menu bar panel's Extensions tab
    /// too. Whichever place shows it, there is one page and one session:
    /// a page the island has open is shown as it is, and the tool is asked
    /// nothing; one that is not is asked for as the island asks, without
    /// becoming the island's page. Each view that shows it opens it with a
    /// token of its own, and lets go of that token alone
    /// (`closeInMenuPanel`), so the order views come and go in does not
    /// matter.
    @discardableResult
    package func openInMenuPanel(_ key: Key, viewer: UUID) -> Refusal? {
        guard let panel = parts.described(key.tool)?.panel(key.panel) else { return .unknownPanel(key.panel) }
        guard panel.placement == .island else { return .wrongPlace(key.panel) }
        guard shown[key] == nil else {
            inMenuPanel[key, default: []].insert(viewer)
            return nil
        }
        guard let tool = parts.tool(key.tool) else { return .notOpen(key.panel) }
        begin(key, panel)
        inMenuPanel[key, default: []].insert(viewer)
        tool.open(panel: key.panel) { [weak self] answer in self?.opened(key, answer) }
        return nil
    }

    /// Whether the menu bar panel's tab draws a line in place of the page:
    /// a web page the island shows. A web page is one web view, which only
    /// one place can hold, and the island keeps it. The tab draws the page
    /// again when the island lets go.
    nonisolated package static func defersToIsland(_ key: Key, shown: Shown?, island: Key?) -> Bool {
        guard case .web? = shown else { return false }
        return island == key
    }

    /// `defersToIsland` for an open panel, as the host stands now.
    package func defersToIsland(_ key: Key) -> Bool {
        Self.defersToIsland(key, shown: shown[key], island: island)
    }

    /// One view of the menu bar panel no longer shows the page: only its own
    /// token goes. A token the host does not hold, of a view whose page
    /// already ended with its tool, does nothing. When no view is left, and
    /// neither the island nor a viewer in Settings shows the page, the page
    /// closes and the tool is told, as when the island closes it.
    package func closeInMenuPanel(_ key: Key, viewer: UUID) {
        guard var views = inMenuPanel[key], views.remove(viewer) != nil else { return }
        inMenuPanel[key] = views.isEmpty ? nil : views
        closeIfNoneShows(key)
    }

    // MARK: - Viewers

    /// Shows one of a tool's panels in Settings' Dynamic Island page too, as
    /// the menu bar panel shows an island page: `place` is where the panel
    /// belongs, the island for its island page or Settings for its settings
    /// page. There is one page and one session whichever views show it: a
    /// page that is open already is shown as it is, and the tool is asked
    /// nothing; one that is not is asked for as its place asks, without
    /// becoming that place's page. Each view opens it with a token of its
    /// own and lets go of that token alone (`closeAsViewer`).
    @discardableResult
    package func openAsViewer(_ key: Key, in place: ToolPanelPlacement, viewer: UUID) -> Refusal? {
        guard let panel = parts.described(key.tool)?.panel(key.panel) else { return .unknownPanel(key.panel) }
        guard panel.placement == place else { return .wrongPlace(key.panel) }
        guard shown[key] == nil else {
            viewers[key, default: []].insert(viewer)
            return nil
        }
        guard let tool = parts.tool(key.tool) else { return .notOpen(key.panel) }
        begin(key, panel)
        viewers[key, default: []].insert(viewer)
        tool.open(panel: key.panel) { [weak self] answer in self?.opened(key, answer) }
        return nil
    }

    /// One viewer no longer shows the page: only its own token goes. A
    /// token the host does not hold, of a view whose page already ended
    /// with its tool, does nothing. When no viewer is left, and neither the
    /// panel's place nor the menu bar panel shows it, the page closes and
    /// the tool is told.
    package func closeAsViewer(_ key: Key, viewer: UUID) {
        guard var held = viewers[key], held.remove(viewer) != nil else { return }
        viewers[key] = held.isEmpty ? nil : held
        closeIfNoneShows(key)
    }

    private func opened(_ key: Key, _ answer: Result<JSONValue, ToolLink.Failure>) {
        guard let now = shown[key] else { return }
        switch answer {
        case .success(let value):
            // Still waiting, or a page the tool sent unprompted before this
            // answer was refused: the answer's page is drawn all the same.
            guard Self.awaitsAPage(now) else { return }
            guard let tree = value["tree"] else { return }
            draw(key, tree)
        case .failure(let failure):
            parts.log(key.tool, "the panel \(key.panel) was not opened: \(failure)")
            if case .waiting = now { shown[key] = .notShown(nil) }
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
    /// read leaves the last one drawn, and the tool's log says why. When
    /// none was drawn yet, the panel is not shown and holds why, the newest
    /// reason, so it says so where the page would be rather than waiting for
    /// ever.
    private func draw(_ key: Key, _ tree: JSONValue) {
        guard var state = drawing[key] else { return }
        state.sequence += 1
        let mine = state.sequence
        drawing[key] = state
        parts.read(tree) { [weak self] read in
            guard let self, self.drawing[key]?.sequence == mine, self.shown[key] != nil else { return }
            switch read {
            case .success(let page):
                self.revisions[key, default: 0] += 1
                self.shown[key] = .page(page)
            case .failure(let problem):
                switch problem {
                case .tooLarge(let bytes):
                    self.parts.log(key.tool, "a page of \(bytes) bytes for the panel \(key.panel) was not drawn: "
                        + "the most is \(UILimits.maxTreeBytes)")
                case .notWellFormed(let place):
                    self.parts.log(key.tool, "a page for the panel \(key.panel) was not drawn: \(place) is not well formed")
                }
                if Self.awaitsAPage(self.shown[key]) { self.shown[key] = .notShown(problem) }
            }
        }
    }

    /// Whether a panel has drawn no page yet and waits for one: it is
    /// waiting, or only refused pages came. A refused page then says why in
    /// its place, the newest reason; a panel that drew a page keeps it.
    private static func awaitsAPage(_ shown: Shown?) -> Bool {
        switch shown {
        case .waiting?, .notShown(.some)?: return true
        case .page?, .web?, .notShown(nil)?, nil: return false
        }
    }

    /// The tool's name in `language`, as it wrote it, for what the app says
    /// in place of one of its panels; its id when the app knows no name.
    package func name(of tool: ToolID, language: String) -> String {
        let described = parts.described(tool)
        return described?.name.text(for: language) ?? described?.manifest.tool.name ?? tool.rawValue
    }

    // MARK: - What the person did

    /// Tells the tool what the person did in an open panel. The answer's
    /// page is drawn at once; `keep` leaves the page as it is; `open` opens
    /// one of the tool's windows, or its own settings. An event that was not
    /// answered plays the alert sound.
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

    /// A window the tool asked to open in answer to the person, or its
    /// settings. Only one of its own window panels, or its own settings
    /// panel: the id is looked up in the asking tool's manifest, so no tool
    /// can name another's. Its settings panel opens Settings on the tool's
    /// detail (`ProtocolFeature.openSettings`); anything else is refused as
    /// a window that is not one.
    private func openAsked(_ tool: ToolID, _ panel: String) {
        if parts.described(tool)?.panel(panel)?.placement == .settings {
            return parts.openSettings(tool)
        }
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
        shown[key] = .notShown(nil)
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

    // MARK: - The notice and the slot

    /// A tool's notice, from its `notify/notice`, which the broker let
    /// through behind `notify`.
    package func notice(_ tool: ToolID, _ asked: NotifyNoticeParams) {
        parts.notice(asked)
    }

    /// A tool asks for its slot, with `ui/dock`: the island opens on it.
    /// Gives back why it did not: a tool whose manifest declares no slot
    /// has none to show.
    @discardableResult
    package func dock(_ tool: ToolID) -> Refusal? {
        guard parts.described(tool)?.slot == .agents else { return .noSlot }
        parts.dockAgents()
        return nil
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
    ///
    /// Words and a start time from a tool whose manifest does not declare
    /// them are left out: the mark is drawn all the same, and the tool's log
    /// says so once for each run of its program.
    @discardableResult
    package func status(_ tool: ToolID, _ asked: UIStatusParams) -> Refusal? {
        guard parts.described(tool)?.showsStatus == true else { return .noStatus }
        var kept = asked
        if parts.described(tool)?.showsActivity != true, asked.activity != nil || asked.since != nil {
            kept = UIStatusParams(state: asked.state, text: asked.text, icon: asked.icon)
            if wordsLeftOut.insert(tool).inserted {
                parts.log(tool, "the words of its status were left out: the manifest does not declare them")
            }
        }
        let next = ToolStatus(kept)
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
        wordsLeftOut.remove(tool)
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
        inMenuPanel[key] = nil
        viewers[key] = nil
        inSettings.remove(key)
        drawing[key]?.timer?.cancel()
        drawing[key] = nil
        calls[key] = nil
        pages.removeValue(forKey: key)?.close()
        windows.removeAll { $0 == key }
        if island == key { island = nil }
    }
}
