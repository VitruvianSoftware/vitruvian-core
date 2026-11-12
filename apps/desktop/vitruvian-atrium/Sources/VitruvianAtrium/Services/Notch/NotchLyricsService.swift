// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import UniformTypeIdentifiers
import VitruvianCore
import VitruvianDesign

@MainActor
package final class NotchLyricsService: ObservableObject {
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
        /// Starts a lookup that reads at most the given number of bytes and
        /// reports how it ended, off the main queue. Returns its cancellation.
        package var lookup: (URL, Int, @escaping @Sendable (NotchLyricsDownloadResult) -> Void) -> () -> Void
        package var island: () -> NotchIslandSurface
        package var makeChooser: () -> Chooser
        package var activate: () -> Void
        package var reopenMusic: () -> Void
        package var main: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
        package var background: @Sendable (@escaping @Sendable () -> Void) -> Void
        /// Runs work on the main queue after a delay, and returns its cancellation.
        package var after: (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> () -> Void
        /// System uptime, which spaces the artist checks a second apart.
        package var uptime: () -> TimeInterval
        /// The time that settled lookups and cached artists expire against.
        package var now: () -> Date

        package init(isEnabled: @escaping () -> Bool,
                     onlineEnabled: @escaping () -> Bool,
                     lookup: @escaping (URL, Int, @escaping @Sendable (NotchLyricsDownloadResult) -> Void) -> () -> Void,
                     island: @escaping () -> NotchIslandSurface,
                     makeChooser: @escaping () -> Chooser,
                     activate: @escaping () -> Void,
                     reopenMusic: @escaping () -> Void,
                     main: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
                     background: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
                     after: @escaping (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> () -> Void,
                     uptime: @escaping () -> TimeInterval,
                     now: @escaping () -> Date) {
            self.isEnabled = isEnabled
            self.onlineEnabled = onlineEnabled
            self.lookup = lookup
            self.island = island
            self.makeChooser = makeChooser
            self.activate = activate
            self.reopenMusic = reopenMusic
            self.main = main
            self.background = background
            self.after = after
            self.uptime = uptime
            self.now = now
        }

        package static var system: Environment {
            Environment(
                isEnabled: { NotchLyricsSupport.isEnabled() },
                onlineEnabled: { NotchLyricsSupport.onlineEnabled() },
                lookup: { url, maximumBytes, completion in
                    let session = NotchLyricsDownload.load(url, maximumBytes: maximumBytes, completion: completion)
                    return { session.invalidateAndCancel() }
                },
                island: { NotchIslandSurface.current },
                makeChooser: { Chooser(NSOpenPanel()) },
                activate: { NSApp.activate(ignoringOtherApps: true) },
                reopenMusic: { NotchService.shared.open(.music, feedback: false) },
                main: { work in DispatchQueue.main.async { work() } },
                background: { work in DispatchQueue.global(qos: .userInitiated).async { work() } },
                after: { delay, work in
                    let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
                    return { item.cancel() }
                },
                uptime: { ProcessInfo.processInfo.systemUptime },
                now: { Date() })
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
    /// A lookup that found nothing, kept a short while so reopening the
    /// page does not ask again; Retry and a new song clear it.
    private var settledAttempt: (track: NotchMusicIdentity, failed: Bool, expires: Date)?
    /// Artists verified online, by album and artist, so the next song asks nothing.
    package private(set) var artistCache: [String: (identity: NotchLyricsSupport.ArtistIdentity?, failed: Bool,
                                                    expires: Date)] = [:]
    private var cancelAliasWork: (() -> Void)?
    private var lastAliasRequest: TimeInterval = -.infinity
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
        if changedTrack { memory.select(next); settledAttempt = nil }
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
        settledAttempt = nil
        visible = false
        state = .idle
        if let playback { update(playback: playback, visible: wasVisible) }
    }

    package func retry() {
        guard visible, environment.onlineEnabled(), let track else { return }
        cancel()
        settledAttempt = nil
        let key = NotchLyricsSupport.artistCacheKey(for: track)
        if let cached = artistCache[key], cached.failed || cached.identity == nil {
            artistCache.removeValue(forKey: key)
        }
        load(track)
    }

    package func adjustOffset(by amount: Double) { memory.adjustOffset(by: amount) }
    package func resetOffset() { memory.resetOffset() }

    package func hide() {
        cancel()
        visible = false
        if !environment.isEnabled() {
            memory.clear()
            settledAttempt = nil
            artistCache.removeAll()
        }
        state = lyrics == nil ? .idle : .ready
    }

    package func stop() {
        cancel()
        visible = false
        online = false
        memory.clear()
        settledAttempt = nil
        artistCache.removeAll()
        state = .idle
    }

    private func cancel() {
        generation = UUID()
        cancelAliasWork?()
        cancelAliasWork = nil
        cancelLookup?()
        cancelLookup = nil
        importPanel?.cancel()
        importPanel = nil
        importToken = nil
    }

    private func load(_ track: NotchMusicIdentity) {
        if let attempt = settledAttempt, attempt.track == track, attempt.expires > environment.now() {
            state = attempt.failed ? .failed : .unavailable
            return
        }
        settledAttempt = nil
        guard let url = NotchLyricsSupport.lookupURL(for: track) else { state = .unavailable; return }
        state = .loading
        let requested = generation
        let main = environment.main
        cancelLookup = environment.lookup(url, NotchLyricsSupport.maximumBytes) { [weak self] result in
            let lyrics = result.data.flatMap { NotchLyricsSupport.decode($0, for: track)
                ?? NotchLyricsSupport.decodeCatalogMatch($0, for: track) }
            main { [weak self] in
                guard let self, self.acceptsResult(for: track, generation: requested) else { return }
                self.cancelLookup = nil
                if let lyrics { self.finish(lyrics, for: track, failed: false) }
                else if !result.canSearch { self.finish(nil, for: track, failed: true) }
                else {
                    self.search(track, urls: NotchLyricsSupport.searchURLs(for: track),
                                candidates: [], failed: result.failed, generation: requested)
                }
            }
        }
    }

    private func acceptsResult(for track: NotchMusicIdentity, generation requested: UUID) -> Bool {
        visible && generation == requested && self.track == track && environment.onlineEnabled()
    }

    private func finish(_ lyrics: NotchLyrics?, for track: NotchMusicIdentity, failed: Bool) {
        guard memory.replace(lyrics, for: track) else { return }
        settledAttempt = lyrics == nil
            ? (track, failed, environment.now().addingTimeInterval(failed ? 15 : 60)) : nil
        state = lyrics != nil ? .ready : failed ? .failed : .unavailable
    }

    /// Sequential, bounded catalog fallback. Each callback
    /// rechecks visibility, consent and song identity before issuing another request.
    private func search(_ track: NotchMusicIdentity, urls: [URL], candidates: [NotchLyricsSupport.Candidate],
                        failed: Bool, generation requested: UUID,
                        verifiedArtistAliases: [String] = [], mayResolveAliases: Bool = true, mayDiscover: Bool = true) {
        guard acceptsResult(for: track, generation: requested) else { return }
        guard let url = urls.first else {
            if candidates.isEmpty && !failed && mayDiscover && NotchLyricsSupport.prefersDiscovery(for: track) {
                search(track, urls: NotchLyricsSupport.discoveryURLs(for: track), candidates: [], failed: false,
                       generation: requested, verifiedArtistAliases: verifiedArtistAliases,
                       mayResolveAliases: mayResolveAliases, mayDiscover: false)
                return
            }
            if candidates.isEmpty && !failed && mayResolveAliases {
                resolveArtist(track, generation: requested)
                return
            }
            if candidates.isEmpty && !failed && mayDiscover {
                search(track, urls: NotchLyricsSupport.discoveryURLs(for: track), candidates: [], failed: false,
                       generation: requested, verifiedArtistAliases: verifiedArtistAliases,
                       mayResolveAliases: false, mayDiscover: false)
                return
            }
            finish(NotchLyricsSupport.bestLyrics(in: candidates), for: track, failed: failed)
            return
        }
        let main = environment.main
        cancelLookup = environment.lookup(url, NotchLyricsSupport.maximumSearchBytes) { [weak self] result in
            let found = result.data.map { NotchLyricsSupport.searchCandidates($0, for: track,
                                                        verifiedArtistAliases: verifiedArtistAliases) } ?? []
            let knownRecording = result.data.map { NotchLyricsSupport.containsCatalogRecording($0, for: track) } ?? false
            main { [weak self] in
                guard let self, self.acceptsResult(for: track, generation: requested) else { return }
                self.cancelLookup = nil
                let accumulated = candidates + found
                if !result.canSearch {
                    self.finish(NotchLyricsSupport.bestLyrics(in: accumulated), for: track, failed: true)
                } else {
                    self.search(track, urls: Array(urls.dropFirst()), candidates: accumulated,
                                failed: failed || result.failed, generation: requested,
                                verifiedArtistAliases: verifiedArtistAliases,
                                mayResolveAliases: mayResolveAliases && !knownRecording,
                                mayDiscover: mayDiscover && !knownRecording)
                }
            }
        }
    }

    /// Alias verification is a last resort, not a request on every track. Only
    /// exact metadata identity membership is accepted, never a search score.
    private func resolveArtist(_ track: NotchMusicIdentity, generation requested: UUID) {
        let key = NotchLyricsSupport.artistCacheKey(for: track)
        if let cached = artistCache[key], cached.expires > environment.now() {
            searchArtist(track, identity: cached.identity, failed: cached.failed, generation: requested)
            return
        }
        guard let url = NotchLyricsSupport.artistIdentityURL(for: track) else {
            finish(nil, for: track, failed: false)
            return
        }
        requestArtistMetadata(url, track: track, generation: requested) { [weak self] result in
            guard let self else { return }
            guard let data = result.data else {
                self.cacheArtist(nil, for: track, failed: true, generation: requested)
                return
            }
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let broad = (object?["count"] as? Int ?? 0) > 5
            let artists = NotchLyricsSupport.artistIdentities(data, for: track, allowTruncated: broad)
            if artists.count == 1 && artists[0].queryNames.isEmpty,
               let recordingURL = NotchLyricsSupport.artistRecordingURL(for: track, candidates: artists) {
                self.requestArtistMetadata(recordingURL, track: track, generation: requested) { [weak self] reply in
                    guard let self else { return }
                    let identity = reply.data.flatMap {
                        NotchLyricsSupport.recordingArtistIdentity($0, for: track, candidates: artists)
                    }
                    self.cacheArtist(identity, for: track, failed: reply.data == nil, generation: requested)
                }
            } else if artists.count == 1 && !broad {
                self.cacheArtist(artists.first, for: track, failed: false, generation: requested)
            } else if !artists.isEmpty, let albumURL = NotchLyricsSupport.artistAlbumURL(for: track) {
                self.requestArtistMetadata(albumURL, track: track, generation: requested) { [weak self] reply in
                    guard let self else { return }
                    let identity = reply.data.flatMap {
                        NotchLyricsSupport.artistIdentity($0, for: track, candidates: artists)
                    }
                    self.cacheArtist(identity, for: track, failed: reply.data == nil, generation: requested)
                }
            } else {
                self.cacheArtist(nil, for: track, failed: false, generation: requested)
            }
        }
    }

    /// MusicBrainz requires at most one request per second. A cancelled or
    /// superseded delayed request never leaves this process.
    private func requestArtistMetadata(_ url: URL, track: NotchMusicIdentity, generation requested: UUID,
                                       completion: @escaping @MainActor @Sendable (NotchLyricsDownloadResult) -> Void) {
        let delay = max(0, 1.05 - (environment.uptime() - lastAliasRequest))
        let main = environment.main
        cancelAliasWork = environment.after(delay) { [weak self] in
            guard let self, self.acceptsResult(for: track, generation: requested) else { return }
            self.cancelAliasWork = nil
            self.lastAliasRequest = self.environment.uptime()
            self.cancelLookup = self.environment.lookup(url, NotchLyricsSupport.maximumBytes) { [weak self] result in
                main { [weak self] in
                    guard let self, self.acceptsResult(for: track, generation: requested) else { return }
                    self.cancelLookup = nil
                    completion(result)
                }
            }
        }
    }

    private func cacheArtist(_ identity: NotchLyricsSupport.ArtistIdentity?, for track: NotchMusicIdentity,
                             failed: Bool, generation requested: UUID) {
        guard acceptsResult(for: track, generation: requested) else { return }
        let now = environment.now()
        artistCache = artistCache.filter { $0.value.expires > now }
        if artistCache.count >= 32, let oldest = artistCache.min(by: { $0.value.expires < $1.value.expires })?.key {
            artistCache.removeValue(forKey: oldest)
        }
        artistCache[NotchLyricsSupport.artistCacheKey(for: track)] =
            (identity, failed, now.addingTimeInterval(failed ? 15 : identity == nil ? 600 : 3600))
        searchArtist(track, identity: identity, failed: failed, generation: requested)
    }

    private func searchArtist(_ track: NotchMusicIdentity, identity: NotchLyricsSupport.ArtistIdentity?,
                              failed: Bool, generation requested: UUID) {
        guard acceptsResult(for: track, generation: requested) else { return }
        guard let identity else {
            if !failed && !NotchLyricsSupport.prefersDiscovery(for: track) {
                search(track, urls: NotchLyricsSupport.discoveryURLs(for: track), candidates: [], failed: false,
                       generation: requested, mayResolveAliases: false, mayDiscover: false)
            } else { finish(nil, for: track, failed: failed) }
            return
        }
        search(track, urls: NotchLyricsSupport.aliasSearchURLs(for: track, identity: identity),
               candidates: [], failed: false, generation: requested,
               verifiedArtistAliases: identity.names, mayResolveAliases: false,
               mayDiscover: !NotchLyricsSupport.prefersDiscovery(for: track))
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
        visible && track == expected && environment.isEnabled() && environment.island().shows(.music, in: window)
    }
}

/// An ephemeral request, bounded while bytes arrive. Redirects are refused
/// so track metadata can only reach the hosts disclosed by the opt-in control.
private final class NotchLyricsDownload: NSObject, URLSessionDataDelegate {
    private var data = Data()
    private var accepted = false
    private var status: Int?
    /// Runs on the session's delegate queue.
    private let completion: @Sendable (NotchLyricsDownloadResult) -> Void
    private let maximumBytes: Int
    private init(maximumBytes: Int, completion: @escaping @Sendable (NotchLyricsDownloadResult) -> Void) {
        self.maximumBytes = maximumBytes
        self.completion = completion
    }

    static func load(_ url: URL, maximumBytes: Int = NotchLyricsSupport.maximumBytes,
                     completion: @escaping @Sendable (NotchLyricsDownloadResult) -> Void) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        // MusicBrainz asks every client to name itself and a way to reach its
        // maintainers.
        configuration.httpAdditionalHeaders = [
            "User-Agent": "\(AppInfo.name)/\(AppInfo.version) (\(AppInfo.repositoryURL.absoluteString))",
            "Accept": "application/json",
        ]
        let delegate = NotchLyricsDownload(maximumBytes: maximumBytes, completion: completion)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        session.dataTask(with: url).resume()
        session.finishTasksAndInvalidate()
        return session
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        status = (response as? HTTPURLResponse)?.statusCode
        accepted = status == 200 && response.expectedContentLength <= maximumBytes
        completionHandler(accepted ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard accepted, chunk.count <= maximumBytes - data.count else {
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
        if error == nil && accepted { completion(.payload(data)) }
        else if status == 404 { completion(.missing) }
        else if let status, (500...599).contains(status) { completion(.serviceUnavailable) }
        else { completion(.failed) }
    }
}
