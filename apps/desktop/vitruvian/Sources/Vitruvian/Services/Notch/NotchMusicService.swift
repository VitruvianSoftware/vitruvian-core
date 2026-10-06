// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
@preconcurrency import Dispatch
import VitruvianCore
import VitruvianDesign

/// A running Now Playing adapter: whether it still runs, the pipe its
/// commands go into, and ending it.
package struct NotchMusicAdapterLink {
    package var isRunning: () -> Bool
    /// Runs on the command queue.
    package var write: (Data) throws -> Void
    package var end: () -> Void

    // Spelled out because a memberwise initializer never leaves its module.
    package init(isRunning: @escaping () -> Bool, write: @escaping (Data) throws -> Void,
                 end: @escaping () -> Void) {
        self.isRunning = isRunning
        self.write = write
        self.end = end
    }
}

@MainActor
package final class NotchMusicService: ObservableObject {
    /// What the service reaches outside itself: the adapter, the main queue
    /// its replies come back on, delayed work and the clock, the queue
    /// commands are written on, the settings, the lyrics and the Apple Event
    /// system. `live` runs the bundled adapter; tests pass one they feed by
    /// hand.
    @MainActor
    package struct Environment {
        /// Starts the adapter, following every player or only music apps. It
        /// hands each chunk it prints to `read`, off the main thread, and
        /// calls `ended` once it exits. Nil when it cannot start.
        package var launch: (_ watchAll: Bool, _ read: @escaping @Sendable (Data) -> Void,
                             _ ended: @escaping @Sendable () -> Void) -> NotchMusicAdapterLink?
        package var main: @Sendable (sending @escaping @MainActor () -> Void) -> Void
        /// Runs `work` on the main queue after `delay` unless it is cancelled first.
        package var after: (_ delay: TimeInterval, _ work: DispatchWorkItem) -> Void
        package var uptime: () -> TimeInterval
        /// The serial queue the adapter's commands are written on.
        package var commands: (@escaping () -> Void) -> Void
        package var defaults: UserDefaults
        package var lyricsChanged: (NotchPlayback?) -> Void
        package var hideLyrics: () -> Void
        package var automation: NotchMusicAutomationFlow.Environment

        // Spelled out because a memberwise initializer never leaves its module.
        package init(launch: @escaping (_ watchAll: Bool, _ read: @escaping @Sendable (Data) -> Void,
                                        _ ended: @escaping @Sendable () -> Void) -> NotchMusicAdapterLink?,
                     main: @escaping @Sendable (sending @escaping @MainActor () -> Void) -> Void,
                     after: @escaping (_ delay: TimeInterval, _ work: DispatchWorkItem) -> Void,
                     uptime: @escaping () -> TimeInterval,
                     commands: @escaping (@escaping () -> Void) -> Void,
                     defaults: UserDefaults,
                     lyricsChanged: @escaping (NotchPlayback?) -> Void,
                     hideLyrics: @escaping () -> Void,
                     automation: NotchMusicAutomationFlow.Environment) {
            self.launch = launch
            self.main = main
            self.after = after
            self.uptime = uptime
            self.commands = commands
            self.defaults = defaults
            self.lyricsChanged = lyricsChanged
            self.hideLyrics = hideLyrics
            self.automation = automation
        }

        package static var live: Environment {
            let queue = DispatchQueue(label: "com.vitruviansoftware.vitruvian.notch-music", qos: .utility)
            return Environment(
                launch: { watchAll, read, ended in launchAdapter(watchAll: watchAll, read: read, ended: ended) },
                main: { work in DispatchQueue.main.async { work() } },
                after: { DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1) },
                uptime: { ProcessInfo.processInfo.systemUptime },
                commands: { queue.async(execute: $0) },
                defaults: .standard,
                lyricsChanged: { NotchLyricsService.shared.playbackChanged($0) },
                hideLyrics: { NotchLyricsService.shared.hide() },
                automation: .live(queue: queue))
        }

        private static var adapter: [String]? {
            guard let script = Bundle.main.url(forResource: "now-playing", withExtension: "pl"),
                  let library = Bundle.main.privateFrameworksURL?.appendingPathComponent("libVitruvianNowPlaying.dylib"),
                  FileManager.default.fileExists(atPath: library.path) else { return nil }
            return [script.path, library.path]
        }

        private static func launchAdapter(watchAll: Bool, read: @escaping @Sendable (Data) -> Void,
                                          ended: @escaping @Sendable () -> Void) -> NotchMusicAdapterLink? {
            guard let arguments = adapter else { return nil }
            let process = Process()
            let output = Pipe()
            let input = Pipe()
            // A child can exit between checking isRunning and writing a command.
            // Keep that race an error, never a SIGPIPE that terminates the app.
            guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { return nil }
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = arguments + [watchAll ? "watch_all" : "watch"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.standardInput = input
            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil }
                else { read(data) }
            }
            process.terminationHandler = { _ in ended() }
            do {
                try process.run()
            } catch {
                output.fileHandleForReading.readabilityHandler = nil
                return nil
            }
            return NotchMusicAdapterLink(
                isRunning: { process.isRunning },
                write: { try input.fileHandleForWriting.write(contentsOf: $0) },
                end: {
                    output.fileHandleForReading.readabilityHandler = nil
                    try? input.fileHandleForWriting.close()
                    if process.isRunning {
                        process.terminate()
                        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                        }
                    }
                })
        }
    }

    package static let shared = NotchMusicService(environment: .live)
    private let environment: Environment
    @Published package private(set) var playback: NotchPlayback?
    @Published package private(set) var sources: [NotchPlaybackSource] = []
    @Published package private(set) var sourceIsAutomatic = true
    /// The chosen source, which the automatic player can stand in for while
    /// it waits for its next track.
    @Published package private(set) var selectedSourcePID: Int32?
    /// True from the first request until the adapter's first reply. Until then
    /// a missing playback is unknown, not "nothing playing".
    @Published package private(set) var awaitingPlayback = false
    @Published package private(set) var artwork: NSImage?
    @Published package private(set) var artworkTint: NotchArtworkTint?
    @Published package private(set) var commandFailed = false
    @Published package private(set) var commandPending = false
    package var automationAvailability: NotchMusicAutomation.Availability? { automation.availability }
    package var requestingAutomation: Bool { automation.requesting }
    /// The queue shown and its covers (`NotchUpcomingQueue`).
    @Published private var upcomingQueue = NotchUpcomingQueue<NSImage>(decode: NSImage.init(data:))
    package var upcoming: NotchQueueSnapshot? { upcomingQueue.snapshot }
    package var upcomingArtwork: [String: NSImage] { upcomingQueue.artwork }
    @Published package private(set) var queueLoading = false
    @Published package private(set) var queueActionPending = false
    @Published package private(set) var queueActionFailed = false
    /// A player moved on to another song; see NotchTrackChange. Sent before
    /// the song is published, while every surface still shows the old one.
    package let trackChanges = PassthroughSubject<Void, Never>()
    /// The song shown stops, and no other plays yet: a gap between songs
    /// outlasted its grace period, or another player's paused song took over
    /// from a pause. Sent before that reading is published.
    package let trackEnds = PassthroughSubject<Void, Never>()
    /// Immediate visual acknowledgement of an accepted swipe, before metadata arrives.
    package let gestureSkips = PassthroughSubject<Bool, Never>()
    private var trackChange = NotchTrackChange()
    private struct Reading {
        let playback: NotchPlayback?
        let artwork: NSImage?
        let tint: NotchArtworkTint?
        let sources: [NotchPlaybackSource]
        let automatic: Bool?
        let selectedPID: Int32?

        // Spelled out because a memberwise initializer never leaves its module.
        package init(playback: NotchPlayback?, artwork: NSImage?, tint: NotchArtworkTint?, sources: [NotchPlaybackSource], automatic: Bool?, selectedPID: Int32?) {
            self.playback = playback
            self.artwork = artwork
            self.tint = tint
            self.sources = sources
            self.automatic = automatic
            self.selectedPID = selectedPID
        }
    }
    /// An empty reading waiting out a gap between songs; see receive(_:).
    private var gapReading: Reading?
    private var gapWork: DispatchWorkItem?
    private var queueVisible = false
    private var queueRequest: UUID?
    private var queueReply: [String: Any]?
    private var link: NotchMusicAdapterLink?
    private var generation = UUID()
    private var wantsPlayback = false
    private var includeOtherPlayers = false
    private var restartCount = 0
    private var restartWork: DispatchWorkItem?
    private var launchedAt: TimeInterval?
    /// The adapter keeps an explicit choice only while it runs, and it stops
    /// on lock, sleep or when the page closes. Tied to a process, so it is
    /// never saved across launches of the app.
    private var chosenSource: NotchPlaybackSource.Selection?
    private var restoringSource = false
    private var artworkCache = NotchArtworkCache<(image: NSImage, tint: NotchArtworkTint?)>()
    private var artworkWork: DispatchWorkItem?
    private lazy var commandWriter = NotchMusicCommandWriter(schedule: environment.commands)
    /// Control through Apple Events for players whose own commands do not
    /// reach them (`NotchMusicAutomationFlow`).
    private lazy var automation: NotchMusicAutomationFlow = NotchMusicAutomationFlow(
        host: .init(playback: { [weak self] in self?.playback },
                    generation: { [weak self] in self?.generation ?? UUID() },
                    commandPending: { [weak self] in self?.commandPending ?? false },
                    setCommandPending: { [weak self] in self?.commandPending = $0 },
                    setCommandFailed: { [weak self] in self?.commandFailed = $0 },
                    validate: { [weak self] id, context in self?.send(.validate(id, context)) ?? false },
                    willChange: { [weak self] in self?.objectWillChange.send() }),
        environment: environment.automation)

    package init(environment: Environment) {
        self.environment = environment
    }

    package func start() {
        let includeOtherPlayers = environment.defaults[Preferences.notchIncludeOtherPlayers]
        if wantsPlayback {
            guard self.includeOtherPlayers != includeOtherPlayers else { return }
            stop()
        }
        self.includeOtherPlayers = includeOtherPlayers
        wantsPlayback = true
        awaitingPlayback = true
        restartCount = 0
        launch()
    }

    private func launch() {
        guard wantsPlayback, link == nil else { return }
        let requested = UUID()
        generation = requested
        let main = environment.main
        var cachedArtwork: Data?
        var cachedImage: NSImage?
        var cachedTint: NotchArtworkTint?
        let reader = NotchMusicPipeReader { [weak self] data in
            let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let reply, reply["validationRequest"] != nil {
                main {
                    guard let self, self.generation == requested else { return }
                    self.receiveValidation(reply)
                }
                return
            }
            if let reply,
               reply["queueRequest"] != nil || reply["queueAction"] != nil {
                main {
                    guard let self, self.generation == requested else { return }
                    self.receiveQueue(reply)
                }
                return
            }
            if let sent = reply?["sent"] as? Bool {
                main {
                    guard let self, self.generation == requested else { return }
                    self.commandFailed = !sent
                }
                return
            }
            let next = NotchPlayback.decode(data, previousArtwork: cachedArtwork,
                                           commandContext: reply.flatMap(NotchPlaybackContext.init(reply:)),
                                           canSendCommandsDirectly: reply?["canSendCommandsDirectly"] as? Bool == true)
            if cachedArtwork != next?.track.artworkData {
                cachedArtwork = next?.track.artworkData
                cachedImage = cachedArtwork.flatMap { ImageThumbnailer.thumbnail(data: $0, pointSize: 160, scale: 2) }
                cachedTint = cachedImage.flatMap(NotchMusicService.artworkTint(of:))
            }
            let image = cachedImage
            let tint = cachedTint
            let automatic = reply?["sourceIsAutomatic"] as? Bool
            let selectedPID = automatic == false ? NotchPlaybackSource.decodePID(reply?["selectedPID"]) : nil
            let sources = NotchPlaybackSource.decode(reply?["sources"], selectedPID: selectedPID)
            main {
                guard let self, self.generation == requested,
                      self.acceptsSourceReply(automatic: automatic, sources: sources) else { return }
                self.receive(Reading(playback: next, artwork: image, tint: tint, sources: sources,
                                     automatic: automatic, selectedPID: selectedPID))
            }
        }
        let link = environment.launch(includeOtherPlayers, { reader.append($0) }, { [weak self] in
            main {
                guard let self, self.generation == requested else { return }
                self.connectionEnded()
            }
        })
        guard let link else { connectionEnded(); return }
        commandWriter.start()
        self.link = link
        launchedAt = environment.uptime()
        restoreSource()
    }

    /// A new adapter starts in Automatic. It finishes its first discovery
    /// before reading any command, so it checks the choice against fresh sources.
    private func restoreSource() {
        guard let chosenSource else { restoringSource = false; return }
        restoringSource = send(.source(chosenSource))
    }

    /// A restarted adapter reads once in Automatic before the restored choice
    /// reaches it. That reading is not shown, so the automatic player does not
    /// flash. A choice the adapter reports gone is forgotten.
    private func acceptsSourceReply(automatic: Bool?, sources: [NotchPlaybackSource]) -> Bool {
        let restoring = restoringSource
        restoringSource = false
        guard automatic == true, let chosenSource else { return true }
        guard sources.contains(where: { $0.selection == chosenSource }) else {
            self.chosenSource = nil
            return true
        }
        return !restoring
    }

    /// A player moving on to its next song can clear its metadata for a
    /// moment, which reads as nothing playing or as another player's paused
    /// song standing in, or report the next song paused before it starts. The
    /// page would empty or change and shrink, and the compact strip leave,
    /// until the next song plays. The last song stays through such a gap and
    /// the next reading replaces it at once. Later readings of the gap never
    /// extend the grace period.
    private func receive(_ reading: Reading) {
        // A player that still lists a song when another player's paused song
        // takes its place was paused. During a gap it had left, the song it
        // lists again can be its next one, still loading.
        let listing = gapWork == nil ? reading.sources : []
        if let current = playback, !awaitingPlayback,
           NotchTrackChange.isBetweenSongs(reading.playback, after: current, sources: listing) {
            gapReading = reading
            guard gapWork == nil else { return }
            let requested = generation
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.generation == requested, let reading = self.gapReading else { return }
                self.endPlaybackGap()
                self.apply(reading)
            }
            gapWork = work
            environment.after(NotchPlayback.gapGracePeriod, work)
            return
        }
        endPlaybackGap()
        apply(reading)
    }

    private func endPlaybackGap() {
        gapWork?.cancel()
        gapWork = nil
        gapReading = nil
    }

    private func apply(_ reading: Reading) {
        let first = awaitingPlayback
        if trackChange.isNewSong(reading.playback, first: first) { trackChanges.send() }
        else if !first, let current = playback, NotchTrackChange.isBetweenSongs(reading.playback, after: current) {
            trackEnds.send()
        }
        updateArtwork(reading.artwork, tint: reading.tint, playback: reading.playback)
        playback = reading.playback
        sources = reading.sources
        sourceIsAutomatic = reading.automatic ?? true
        selectedSourcePID = reading.selectedPID
        awaitingPlayback = false
        updateAutomation(for: reading.playback)
        environment.lyricsChanged(reading.playback)
        updateQueue()
    }

    private func connectionEnded() {
        // An adapter that ran for over a minute is not crash looping, so its
        // exit gets a fresh budget instead of leaving music off until a restart.
        if let launchedAt, environment.uptime() - launchedAt > 60 { restartCount = 0 }
        launchedAt = nil
        disconnect()
        guard wantsPlayback, restartCount < 2 else { awaitingPlayback = false; return }
        restartCount += 1
        let requested = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wantsPlayback, self.generation == requested else { return }
            self.restartWork = nil
            self.launch()
        }
        restartWork = work
        environment.after(Double(restartCount), work)
    }

    private func updateArtwork(_ image: NSImage?, tint: NotchArtworkTint?, playback: NotchPlayback?) {
        artworkWork?.cancel()
        artworkWork = nil
        artworkCache.update(image.map { (image: $0, tint: tint) }, for: playback)
        artwork = artworkCache.artwork?.image
        artworkTint = artworkCache.artwork?.tint
        guard let deadline = artworkCache.expiresAt else { return }
        let requested = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == requested, self.artworkCache.expiresAt == deadline else { return }
            self.artworkCache.expire(at: deadline)
            self.artwork = self.artworkCache.artwork?.image
            self.artworkTint = self.artworkCache.artwork?.tint
            self.artworkWork = nil
        }
        artworkWork = work
        environment.after(max(0, deadline.timeIntervalSinceNow), work)
    }

    /// One averaged pixel is all a halo needs, and it costs nothing next to
    /// decoding the cover itself. Runs on the reader's queue, once per cover.
    /// The pipe reader computes this on its own queue.
    nonisolated private static func artworkTint(of image: NSImage) -> NotchArtworkTint? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return NotchArtworkTint.from(red: Double(pixel[0]) / 255,
                                     green: Double(pixel[1]) / 255,
                                     blue: Double(pixel[2]) / 255)
    }

    package func stop() {
        wantsPlayback = false
        awaitingPlayback = false
        restartWork?.cancel()
        restartWork = nil
        restartCount = 0
        trackChange.reset()
        disconnect()
    }

    private func disconnect() {
        endPlaybackGap()
        artworkWork?.cancel()
        artworkWork = nil
        artworkCache = .init()
        automation.reset()
        commandWriter.stop()
        queueVisible = false
        environment.hideLyrics()
        queueRequest = nil
        queueReply = nil
        upcomingQueue.show(nil)
        upcomingQueue.forgetCovers()
        queueLoading = false
        queueActionPending = false
        queueActionFailed = false
        generation = UUID()
        link?.end()
        link = nil
        playback = nil
        sources = []
        sourceIsAutomatic = true
        selectedSourcePID = nil
        artwork = nil
        artworkTint = nil
        commandFailed = false
    }

    package typealias Command = NotchPlaybackCommand

    package func selectSource(_ selection: NotchPlaybackSource.Selection?) {
        // Choosing what is already in effect changes nothing in the adapter,
        // so the page, its lyrics and the island's size stay as they are. A
        // choice stays in effect while the automatic player fills its gap.
        if selection == nil ? sourceIsAutomatic
            : !sourceIsAutomatic && selectedSourcePID == selection?.pid { return }
        guard selection == nil || sources.contains(where: { $0.selection == selection }),
              send(.source(selection)) else { return }
        chosenSource = selection
        cancelAutomationAction()
        setQueueVisible(false)
        // Remove the old controls while the adapter validates and reads the
        // new source. No gesture can borrow the previous player's context.
        endPlaybackGap()
        playback = nil
        artwork = nil
        artworkTint = nil
        awaitingPlayback = true
        updateAutomation(for: nil)
        environment.lyricsChanged(nil)
    }

    package func setQueueVisible(_ visible: Bool) {
        queueVisible = visible && NotchQueueSupport.isEnabled(in: environment.defaults) && playback != nil
        guard queueVisible else {
            commandWriter.setQueueRequest(nil)
            if queueRequest != nil { send(.queueStop) }
            queueRequest = nil
            queueReply = nil
            upcomingQueue.show(nil)
            queueLoading = false
            queueActionPending = false
            queueActionFailed = false
            return
        }
        guard queueRequest == nil else { return }
        refreshQueue()
    }

    package func syncQueuePreference() {
        guard !NotchQueueSupport.isEnabled(in: environment.defaults) else { return }
        setQueueVisible(false)
        upcomingQueue.forgetCovers()
    }

    package func refreshQueue() {
        guard queueVisible, NotchQueueSupport.isEnabled(in: environment.defaults), playback != nil else { return }
        let request = UUID()
        queueRequest = request
        commandWriter.setQueueRequest(request)
        queueReply = nil
        upcomingQueue.show(nil)
        queueLoading = true
        queueActionFailed = false
        queueActionPending = false
        if !send(.queue(request)) { queueLoading = false; queueActionFailed = true }
    }

    package var upcomingIsHeld: Bool { upcomingQueue.isHeld(for: playback) }

    package var upcomingRows: [NotchQueueItem] { upcomingQueue.rows(for: playback) }

    package func playQueued(_ item: NotchQueueItem) {
        Self.playQueued(item, visible: queueVisible, request: queueRequest, upcoming: upcoming, playback: playback,
                        pending: &queueActionPending, failed: &queueActionFailed, in: environment.defaults) { send($0) }
    }

    /// Sends a queue row's selection, bound to the process, song and offset
    /// shown, unless the queue is hidden, held for another song or busy.
    package static func playQueued(_ item: NotchQueueItem, visible: Bool, request: UUID?,
                                   upcoming: NotchQueueSnapshot?, playback: NotchPlayback?,
                                   pending: inout Bool, failed: inout Bool, in defaults: UserDefaults = .standard,
                                   send: (Command) -> Bool) {
        guard visible, NotchQueueSupport.isEnabled(in: defaults), let request, let upcoming,
              let playback, upcoming.currentIdentifier == playback.itemIdentifier,
              upcoming.pid == playback.track.appPID, upcoming.canPlay,
              upcoming.items.contains(where: { $0.id == item.id && $0.offset == item.offset }),
              !pending else { return }
        failed = false
        pending = true
        let selected = NotchQueueSelection(requestID: request, pid: upcoming.pid,
            currentIdentifier: upcoming.currentIdentifier, itemIdentifier: item.id, offset: item.offset)
        if !send(.queuePlay(selected)) { pending = false; failed = true }
    }

    private func receiveQueue(_ reply: [String: Any]) {
        guard let request = queueRequest, NotchQueueSupport.isEnabled(in: environment.defaults) else { return }
        if reply["queueAction"] as? String == request.uuidString {
            queueActionPending = false
            queueActionFailed = reply["queueActionOK"] as? Bool != true
        } else if reply["queueRequest"] as? String == request.uuidString {
            queueLoading = false
            queueReply = reply
            updateQueue()
        }
    }

    private func updateQueue() {
        upcomingQueue.receive(queueReply, request: queueRequest, playback: playback, enabled: NotchQueueSupport.isEnabled(in: environment.defaults))
    }

    package func seek(to position: Double, in track: RadialNowPlayingSnapshot, context: NotchPlaybackContext?) {
        guard let playback, playback.track == track,
              let context, context == playback.commandContext,
              let position = playback.seekPosition(position, allowed: canSeek) else { return }
        send(.seek(position), context: context)
    }

    @discardableResult
    package func send(_ command: Command) -> Bool {
        send(command, context: playback?.commandContext)
    }

    package func skipFromGesture(forward: Bool) {
        let command: Command = forward ? .next : .previous
        guard canPerform(command), send(command) else { return }
        gestureSkips.send(forward)
    }

    @discardableResult
    package func send(_ command: Command, context: NotchPlaybackContext?) -> Bool {
        switch command {
        case .queue, .queuePlay: guard queueVisible, NotchQueueSupport.isEnabled(in: environment.defaults) else { return false }
        default: break
        }
        switch command {
        case .source, .queueStop: break
        default: guard playback != nil else { return false }
        }
        guard let link, link.isRunning() else { return false }
        if command.requiresPlaybackContext {
            // A song held through a gap has no player left to reach, and a
            // command would come back as a failure.
            guard gapWork == nil, let context, context == playback?.commandContext else { return false }
            guard !commandPending, let playback else { return false }
            if !playback.canSendCommandsDirectly { return beginAutomation(command, playback: playback) }
        }
        let requested = generation
        let requestedQueue = command.queueRequest
        commandFailed = false
        let main = environment.main
        return commandWriter.submit(command, context: context, write: { data in
            try link.write(data)
        }, failed: { [weak self] in
            main {
                guard let self, self.generation == requested,
                      requestedQueue == nil || self.queueRequest == requestedQueue else { return }
                self.commandFailed = true
                self.cancelAutomationAction()
                self.queueLoading = false
                self.queueActionPending = false
                self.queueActionFailed = self.queueRequest != nil
            }
        })
    }

    package var canSeek: Bool { automation.canSeek }

    package func canPerform(_ command: Command) -> Bool { automation.canPerform(command) }

    /// The player itself says it cannot skip this way, so the button is hidden.
    package func lacksTrackSkipping(_ command: Command) -> Bool { automation.lacksTrackSkipping(command) }

    package func refreshAutomation() { automation.refresh() }

    private func updateAutomation(for playback: NotchPlayback?) { automation.update(for: playback) }

    /// Consent never queues the old gesture (`NotchMusicAutomationFlow`).
    package func requestAutomationAccess() { automation.requestAccess() }

    private func beginAutomation(_ command: Command, playback: NotchPlayback) -> Bool {
        automation.begin(command, playback: playback)
    }

    private func receiveValidation(_ reply: [String: Any]) { automation.receiveValidation(reply) }

    private func cancelAutomationAction() { automation.cancelAction() }

}

/// Pipe callbacks may split a UTF-8 character or join several replies. Parsing
/// stays serial and bounded before any metadata reaches the main thread.
/// `buffer` and `receive` are touched only on `queue`, so it is
/// `@unchecked Sendable`.
private final class NotchMusicPipeReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.vitruviansoftware.vitruvian.notch-music-reader", qos: .utility)
    private var buffer = Data()
    private let receive: (Data) -> Void
    init(receive: @escaping (Data) -> Void) { self.receive = receive }

    func append(_ data: Data) {
        // Backpressure keeps native metadata bursts from queuing unbounded
        // buffers. The pipe invokes this off-main and delivery never waits on UI.
        queue.sync {
            self.buffer.append(data)
            if self.buffer.count > RadialNowPlayingSupport.maximumAdapterReplyBytes {
                self.buffer.removeAll(keepingCapacity: false)
                return
            }
            while let end = self.buffer.firstIndex(of: 0x0A) {
                let line = Data(self.buffer[..<end])
                self.buffer.removeSubrange(...end)
                self.receive(line)
            }
        }
    }
}
