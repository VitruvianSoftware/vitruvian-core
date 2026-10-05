// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import UniformTypeIdentifiers
import VitruvianCore
import VitruvianDesign

@MainActor
package final class NotchLyricsService: ObservableObject {
    /// The island a lyrics import returns to, as it is now.
    package struct Island {
        package var window: (any IslandWindowing)?
        package var acceptsUserInteraction: Bool
        package var expanded: Bool
        package var selected: NotchModule
        package var showingAppPanel: Bool
        package var showingMetric: Bool
        package var showingCaptureControls: Bool

        package init(window: (any IslandWindowing)?, acceptsUserInteraction: Bool, expanded: Bool,
                     selected: NotchModule, showingAppPanel: Bool, showingMetric: Bool,
                     showingCaptureControls: Bool) {
            self.window = window
            self.acceptsUserInteraction = acceptsUserInteraction
            self.expanded = expanded
            self.selected = selected
            self.showingAppPanel = showingAppPanel
            self.showingMetric = showingMetric
            self.showingCaptureControls = showingCaptureControls
        }
    }

    /// A file chooser for lyrics, as the import drives it.
    @MainActor
    package struct Chooser {
        /// Opens on its own at `level`, staying up while another app is
        /// active, and reports how it closed and the file chosen.
        package var begin: (_ level: NSWindow.Level, _ message: String,
                            _ completion: @escaping (NSApplication.ModalResponse, URL?) -> Void) -> Void
        package var makeKeyAndOrderFront: () -> Void
        package var cancel: () -> Void

        package init(begin: @escaping (NSWindow.Level, String, @escaping (NSApplication.ModalResponse, URL?) -> Void) -> Void,
                     makeKeyAndOrderFront: @escaping () -> Void, cancel: @escaping () -> Void) {
            self.begin = begin
            self.makeKeyAndOrderFront = makeKeyAndOrderFront
            self.cancel = cancel
        }

        init(_ panel: NSOpenPanel) {
            self.init(begin: { level, message, completion in
                panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText, .plainText]
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.message = message
                // An attached sheet moves/reskins a borderless island. Keep the chooser
                // independent and above its parent instead, without changing the pin.
                panel.level = level
                // Like the sheet it replaces, it stays up while another app is active.
                panel.hidesOnDeactivate = false
                panel.begin { [weak panel] response in completion(response, panel?.url) }
            }, makeKeyAndOrderFront: { panel.makeKeyAndOrderFront(nil) },
            cancel: { panel.cancel(nil) })
        }
    }

    /// What the service reads and drives. `system` is the preferences, the
    /// lyrics service online, the island, an open panel and the dispatch
    /// queues; tests pass doubles.
    @MainActor
    package struct Environment {
        package var isEnabled: () -> Bool
        package var onlineEnabled: () -> Bool
        /// Starts a lookup that reports its body, or nil and whether it
        /// failed rather than found nothing, off the main queue. Returns its
        /// cancellation.
        package var lookup: (URL, @escaping @Sendable (Data?, Bool) -> Void) -> () -> Void
        package var island: () -> Island
        package var makeChooser: () -> Chooser
        package var activate: () -> Void
        package var reopenMusic: () -> Void
        package var main: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
        package var background: @Sendable (@escaping @Sendable () -> Void) -> Void

        package init(isEnabled: @escaping () -> Bool,
                     onlineEnabled: @escaping () -> Bool,
                     lookup: @escaping (URL, @escaping @Sendable (Data?, Bool) -> Void) -> () -> Void,
                     island: @escaping () -> Island,
                     makeChooser: @escaping () -> Chooser,
                     activate: @escaping () -> Void,
                     reopenMusic: @escaping () -> Void,
                     main: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
                     background: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void) {
            self.isEnabled = isEnabled
            self.onlineEnabled = onlineEnabled
            self.lookup = lookup
            self.island = island
            self.makeChooser = makeChooser
            self.activate = activate
            self.reopenMusic = reopenMusic
            self.main = main
            self.background = background
        }

        package static var system: Environment {
            Environment(
                isEnabled: { NotchLyricsSupport.isEnabled() },
                onlineEnabled: { NotchLyricsSupport.onlineEnabled() },
                lookup: { url, completion in
                    let session = NotchLyricsDownload.load(url, completion: completion)
                    return { session.invalidateAndCancel() }
                },
                island: {
                    let notch = NotchService.shared
                    return Island(window: notch.presentationWindow,
                                  acceptsUserInteraction: notch.acceptsUserInteraction,
                                  expanded: notch.expanded, selected: notch.selected,
                                  showingAppPanel: notch.showingAppPanel,
                                  showingMetric: notch.selectedMetric != nil,
                                  showingCaptureControls: notch.captureControls != nil)
                },
                makeChooser: { Chooser(NSOpenPanel()) },
                activate: { NSApp.activate(ignoringOtherApps: true) },
                reopenMusic: { NotchService.shared.open(.music, feedback: false) },
                main: { work in DispatchQueue.main.async { work() } },
                background: { work in DispatchQueue.global(qos: .userInitiated).async { work() } })
        }
    }

    package static let shared = NotchLyricsService()
    package enum State: Equatable { case idle, consent, loading, unavailable, failed, ready }
    @Published package private(set) var state: State = .idle
    @Published private var memory = NotchLyricsMemory()
    package var lyrics: NotchLyrics? { memory.lyrics }
    package var offset: Double { memory.offset }
    package var track: NotchMusicIdentity? { memory.track }
    private var cancelLookup: (() -> Void)?
    private var generation = UUID()
    package private(set) var visible = false
    private var online = false
    private var importPanel: Chooser?
    /// Names the chooser now open, so a late answer from another is ignored.
    private var importToken: UUID?
    package var isImporting: Bool { importPanel != nil }
    private let environment: Environment

    package init(environment: Environment = .system) {
        self.environment = environment
    }

    package func update(playback: NotchPlayback?, visible: Bool) {
        guard environment.isEnabled() else { stop(); return }
        let next = playback.map(NotchMusicIdentity.init)
        let wanted = visible && next != nil
        let online = environment.onlineEnabled()
        let changedTrack = next != nil && next != track
        guard changedTrack || wanted != self.visible || online != self.online else { return }
        cancel()
        if changedTrack { memory.select(next) }
        self.visible = wanted
        self.online = online
        guard wanted, let track else { state = lyrics == nil ? .idle : .ready; return }
        if lyrics != nil { state = .ready; return }
        guard online else { state = .consent; return }
        load(track)
    }

    /// Called for actual adapter metadata, including an explicit empty snapshot.
    /// A hidden view supplies no such evidence and must not discard an import.
    package func playbackChanged(_ playback: NotchPlayback?) {
        guard environment.isEnabled() else { stop(); return }
        let next = playback.map(NotchMusicIdentity.init)
        guard next != track else { return }
        let wasVisible = visible
        cancel()
        memory.select(next)
        visible = false
        state = .idle
        if let playback { update(playback: playback, visible: wasVisible) }
    }

    package func retry() {
        guard visible, environment.onlineEnabled(), let track else { return }
        cancel()
        load(track)
    }

    package func adjustOffset(by amount: Double) { memory.adjustOffset(by: amount) }
    package func resetOffset() { memory.resetOffset() }

    package func hide() {
        cancel()
        visible = false
        if !environment.isEnabled() { memory.clear() }
        state = lyrics == nil ? .idle : .ready
    }

    package func stop() {
        cancel()
        visible = false
        online = false
        memory.clear()
        state = .idle
    }

    private func cancel() {
        generation = UUID()
        cancelLookup?()
        cancelLookup = nil
        importPanel?.cancel()
        importPanel = nil
        importToken = nil
    }

    private func load(_ track: NotchMusicIdentity) {
        guard let url = NotchLyricsSupport.lookupURL(for: track) else { state = .unavailable; return }
        state = .loading
        let requested = generation
        let main = environment.main
        cancelLookup = environment.lookup(url) { [weak self] data, failed in
            let lyrics = data.flatMap { NotchLyricsSupport.decode($0, for: track) }
            main { [weak self] in
                guard let self, self.visible, self.generation == requested, self.track == track,
                      self.environment.onlineEnabled() else { return }
                self.cancelLookup = nil
                guard self.memory.replace(lyrics, for: track) else { return }
                self.state = lyrics != nil ? .ready : failed ? .failed : .unavailable
            }
        }
    }

    package func importLyrics() {
        guard visible, environment.isEnabled(), let track, importPanel == nil,
              let parent = environment.island().window,
              canReturnToLyrics(parent, track: track) else { return }
        let panel = environment.makeChooser()
        let token = UUID()
        importPanel = panel
        importToken = token
        let requested = generation
        let main = environment.main
        let background = environment.background
        panel.begin(NSWindow.Level(rawValue: parent.level.rawValue + 1),
                    FeatureStrings.notchMusicExtras(L10n.shared.language).importHint) { [weak self, weak parent] response, selectedURL in
            guard let self, self.importToken == token else { return }
            self.importPanel = nil
            self.importToken = nil
            guard let parent, self.generation == requested,
                  self.canReturnToLyrics(parent, track: track) else { return }
            defer {
                let returnGeneration = self.generation
                // Dismissal restores the old key window after this callback.
                main { [weak self, weak parent] in
                    guard let self, let parent, self.generation == returnGeneration,
                          self.importPanel == nil, self.canReturnToLyrics(parent, track: track) else { return }
                    self.environment.reopenMusic()
                }
            }
            guard response == .OK, let url = selectedURL else { return }
            self.cancel()
            let importedGeneration = self.generation
            background {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                var lines: [NotchLyricLine] = []
                if let handle = try? FileHandle(forReadingFrom: url) {
                    defer { try? handle.close() }
                    if let data = try? handle.read(upToCount: NotchLyricsSupport.maximumBytes + 1),
                       data.count <= NotchLyricsSupport.maximumBytes,
                       let text = String(data: data, encoding: .utf8) {
                        lines = NotchLyricsSupport.parse(text, duration: track.duration)
                    }
                }
                let imported = lines
                main {
                    guard self.generation == importedGeneration, self.track == track, self.visible,
                          self.environment.isEnabled() else { return }
                    guard self.memory.replace(imported.isEmpty ? nil : NotchLyrics(lines: imported, plain: "", instrumental: false),
                                              for: track) else { return }
                    self.state = imported.isEmpty ? .failed : .ready
                }
            }
        }
        // isImporting keeps the music surface alive through activation and
        // pointer exit. Completion restores focus after native dismissal.
        environment.activate()
        // Activation alone can leave the nonactivating island holding focus.
        panel.makeKeyAndOrderFront()
    }

    private func canReturnToLyrics(_ window: any IslandWindowing, track expected: NotchMusicIdentity) -> Bool {
        let island = environment.island()
        return visible && track == expected && environment.isEnabled()
            && island.acceptsUserInteraction && island.window === window && window.isVisible
            && island.expanded && island.selected == .music && !island.showingAppPanel
            && !island.showingMetric && !island.showingCaptureControls
    }
}

/// A single ephemeral request, bounded while bytes arrive. Redirects are refused
/// so track metadata can only reach the host disclosed by the opt-in control.
private final class NotchLyricsDownload: NSObject, URLSessionDataDelegate {
    private var data = Data()
    private var accepted = false
    private var missing = false
    /// Runs on the session's delegate queue.
    private let completion: @Sendable (Data?, Bool) -> Void
    private init(completion: @escaping @Sendable (Data?, Bool) -> Void) { self.completion = completion }

    static func load(_ url: URL, completion: @escaping @Sendable (Data?, Bool) -> Void) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = ["User-Agent": "Vitruvian", "Accept": "application/json"]
        let delegate = NotchLyricsDownload(completion: completion)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        session.dataTask(with: url).resume()
        session.finishTasksAndInvalidate()
        return session
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode
        missing = status == 404
        accepted = status == 200 && response.expectedContentLength <= NotchLyricsSupport.maximumBytes
        completionHandler(accepted ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard accepted, chunk.count <= NotchLyricsSupport.maximumBytes - data.count else {
            accepted = false
            dataTask.cancel()
            return
        }
        data.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        completion(error == nil && accepted ? data : nil, !missing && (error != nil || !accepted))
    }
}
