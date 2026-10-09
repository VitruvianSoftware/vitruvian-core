// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import Combine
import VitruvianCore

/// The island's subscriptions to the services whose state it shows: changes
/// that resize its strip or its pages, the notices those services raise, and
/// the music hooks. Each source is named here once. What a change does stays
/// with `NotchService`, which hands its reactions in as `Island`.
package final class NotchEventBindings {
    /// Where the events come from. The app passes `.system()`. Each source is
    /// asked for only when its module or notice is on, so a service the
    /// island does not show is never started for it.
    package struct Sources {
        /// The timer's session, on the main queue.
        package var timer: () -> AnyPublisher<Void, Never>
        /// The Watch reading: its state, its headline and whether it holds a
        /// picture, on the main queue.
        package var watch: () -> AnyPublisher<Void, Never>
        /// The playing song with its cover and tint, delivered at once.
        package var music: () -> AnyPublisher<(NotchPlayback?, NSImage?, NotchArtworkTint?), Never>
        /// The reading that ends a song, delivered at once, before it is published.
        package var trackEnds: () -> AnyPublisher<Void, Never>
        /// Whether a song is loaded and whether it plays, on the main queue.
        package var musicActivity: () -> AnyPublisher<Void, Never>
        /// The playing song's title, as it changes.
        package var songTitles: () -> AnyPublisher<String?, Never>
        /// A new song, delivered at once on the main thread.
        package var trackChanges: () -> AnyPublisher<Void, Never>
        /// The tools page's tiles: editing, a hosted utility, hidden items.
        /// Skips the three values the sources hold when bound.
        package var tools: () -> AnyPublisher<Void, Never>
        /// The fan card appearing or leaving, on the main queue.
        package var fanCard: () -> AnyPublisher<Void, Never>
        /// The download list, on the main queue.
        package var downloads: () -> AnyPublisher<Void, Never>
        /// Sets or clears what runs when a download arrives.
        package var setDownloadArrival: (((NotchDownloadItem) -> Void)?) -> Void
        /// What changes the agent strip's size, on the main queue.
        package var agentActivity: () -> AnyPublisher<Void, Never>
        /// The calendar countdown, on the main queue.
        package var calendar: () -> AnyPublisher<Void, Never>
        /// A Keep Awake session starting, ending or moving its end, on the main queue.
        package var keepAwake: () -> AnyPublisher<Void, Never>
        /// Finished turns, limits and the budget, on the main queue.
        package var agentEvents: () -> AnyPublisher<AgentUsageEvent, Never>
        /// System notifications the island may show.
        package var systemNotifications: () -> AnyPublisher<NotchSystemNotification, Never>
        /// Hides the system's own banner for a notification the island showed.
        package var hideNativeNotification: (UUID) -> Void
        /// Each copy the clipboard history captures, on the main queue.
        package var clipboardCaptures: () -> AnyPublisher<Void, Never>
        /// Music starting, not music already playing when the island came
        /// up, on the main queue.
        package var musicStarts: () -> AnyPublisher<Void, Never>
        /// Sets or clears what runs when a download fails.
        package var setDownloadFailure: ((() -> Void)?) -> Void
        /// Keep Awake turning on or off, on the main queue.
        package var keepAwakeTurns: () -> AnyPublisher<Void, Never>

        package init(timer: @escaping () -> AnyPublisher<Void, Never>,
                     watch: @escaping () -> AnyPublisher<Void, Never>,
                     music: @escaping () -> AnyPublisher<(NotchPlayback?, NSImage?, NotchArtworkTint?), Never>,
                     trackEnds: @escaping () -> AnyPublisher<Void, Never>,
                     musicActivity: @escaping () -> AnyPublisher<Void, Never>,
                     songTitles: @escaping () -> AnyPublisher<String?, Never>,
                     trackChanges: @escaping () -> AnyPublisher<Void, Never>,
                     tools: @escaping () -> AnyPublisher<Void, Never>,
                     fanCard: @escaping () -> AnyPublisher<Void, Never>,
                     downloads: @escaping () -> AnyPublisher<Void, Never>,
                     setDownloadArrival: @escaping (((NotchDownloadItem) -> Void)?) -> Void,
                     agentActivity: @escaping () -> AnyPublisher<Void, Never>,
                     calendar: @escaping () -> AnyPublisher<Void, Never>,
                     keepAwake: @escaping () -> AnyPublisher<Void, Never>,
                     agentEvents: @escaping () -> AnyPublisher<AgentUsageEvent, Never>,
                     systemNotifications: @escaping () -> AnyPublisher<NotchSystemNotification, Never>,
                     hideNativeNotification: @escaping (UUID) -> Void,
                     clipboardCaptures: @escaping () -> AnyPublisher<Void, Never>,
                     musicStarts: @escaping () -> AnyPublisher<Void, Never> = { Empty().eraseToAnyPublisher() },
                     setDownloadFailure: @escaping ((() -> Void)?) -> Void = { _ in },
                     keepAwakeTurns: @escaping () -> AnyPublisher<Void, Never> = { Empty().eraseToAnyPublisher() }) {
            self.timer = timer
            self.watch = watch
            self.music = music
            self.trackEnds = trackEnds
            self.musicActivity = musicActivity
            self.songTitles = songTitles
            self.trackChanges = trackChanges
            self.tools = tools
            self.fanCard = fanCard
            self.downloads = downloads
            self.setDownloadArrival = setDownloadArrival
            self.agentActivity = agentActivity
            self.calendar = calendar
            self.keepAwake = keepAwake
            self.agentEvents = agentEvents
            self.systemNotifications = systemNotifications
            self.hideNativeNotification = hideNativeNotification
            self.clipboardCaptures = clipboardCaptures
            self.musicStarts = musicStarts
            self.setDownloadFailure = setDownloadFailure
            self.keepAwakeTurns = keepAwakeTurns
        }

        /// The app's services.
        @MainActor
        package static func system() -> Sources {
            Sources(
                timer: {
                    NotchTimerService.shared.$session.removeDuplicates().receive(on: DispatchQueue.main)
                        .map { _ in () }.eraseToAnyPublisher()
                },
                watch: {
                    // The strip resizes with its reading, and when the area turns
                    // out to hold only a picture.
                    let watch = NotchWatchService.shared
                    return Publishers.CombineLatest3(watch.$state.removeDuplicates(),
                                                     watch.$headline.removeDuplicates(),
                                                     watch.$preview.map { $0 != nil }.removeDuplicates())
                        .receive(on: DispatchQueue.main).map { _ in () }.eraseToAnyPublisher()
                },
                music: {
                    let music = NotchMusicService.shared
                    return music.$playback.combineLatest(music.$artwork, music.$artworkTint)
                        .map { ($0, $1, $2) }.eraseToAnyPublisher()
                },
                trackEnds: { NotchMusicService.shared.trackEnds.eraseToAnyPublisher() },
                musicActivity: {
                    NotchMusicService.shared.$playback.map { ($0 != nil, $0?.isPlaying == true) }
                        .removeDuplicates { $0 == $1 }.receive(on: DispatchQueue.main)
                        .map { _ in () }.eraseToAnyPublisher()
                },
                songTitles: { NotchMusicService.shared.$playback.map { $0?.track.title }.eraseToAnyPublisher() },
                trackChanges: { NotchMusicService.shared.trackChanges.eraseToAnyPublisher() },
                tools: {
                    let launcher = QuickLauncherService.shared
                    // Four publishers, each of which emits once on subscription:
                    // the count dropped below has to match the count merged.
                    return launcher.$isEditing.map { _ in () }
                        .merge(with: launcher.$activeUtility.map { _ in () }, launcher.$hiddenItemsRaw.map { _ in () },
                               ToolRegistry.shared.$revision.map { _ in () })
                        .dropFirst(4).receive(on: DispatchQueue.main).eraseToAnyPublisher()
                },
                fanCard: {
                    SystemMonitor.shared.$snapshot.map { $0.fanSpeeds.isEmpty }.removeDuplicates().dropFirst()
                        .receive(on: DispatchQueue.main).map { _ in () }.eraseToAnyPublisher()
                },
                downloads: {
                    NotchDownloadService.shared.$items.receive(on: DispatchQueue.main)
                        .map { _ in () }.eraseToAnyPublisher()
                },
                setDownloadArrival: { NotchDownloadService.shared.onArrival = $0 },
                agentActivity: {
                    // Only what changes the island's size or strip: a turn starting or
                    // ending, the first read landing, which agents have cards, and
                    // which are working, since each one's mark widens the strip.
                    AgentUsageService.shared.$snapshot
                        .map { ($0.loaded, $0.live.isEmpty, $0.seen, Set($0.live.map(\.provider))) }
                        .removeDuplicates(by: ==)
                        .receive(on: DispatchQueue.main).map { _ in () }.eraseToAnyPublisher()
                },
                calendar: {
                    NotchCalendarService.shared.$countdown.removeDuplicates().receive(on: DispatchQueue.main)
                        .map { _ in () }.eraseToAnyPublisher()
                },
                keepAwake: {
                    // A session starting or ending, or its end moving, which can
                    // change the reading and the wings it needs.
                    let awake = KeepAwakeManager.shared
                    return awake.$isActive.combineLatest(awake.$endDate).removeDuplicates { $0 == $1 }
                        .receive(on: DispatchQueue.main).map { _ in () }.eraseToAnyPublisher()
                },
                agentEvents: {
                    AgentUsageService.shared.events.receive(on: DispatchQueue.main).eraseToAnyPublisher()
                },
                systemNotifications: { NotchNotificationService.shared.received.eraseToAnyPublisher() },
                hideNativeNotification: { NotchNotificationService.shared.hideNative($0) },
                clipboardCaptures: {
                    ClipboardHistoryService.shared.capturedEntry.receive(on: DispatchQueue.main)
                        .map { _ in () }.eraseToAnyPublisher()
                },
                musicStarts: {
                    NotchMusicService.shared.$playback.map { $0?.isPlaying == true }
                        .removeDuplicates().dropFirst().filter { $0 }.receive(on: DispatchQueue.main)
                        .map { _ in () }.eraseToAnyPublisher()
                },
                setDownloadFailure: { NotchDownloadService.shared.onFailure = $0 },
                keepAwakeTurns: {
                    KeepAwakeManager.shared.$isActive.removeDuplicates().dropFirst().receive(on: DispatchQueue.main)
                        .map { _ in () }.eraseToAnyPublisher()
                })
        }
    }

    /// What the island does with each event.
    package struct Island {
        /// Something a strip or the island's size shows changed.
        package var resize: () -> Void
        /// A song is playing: keep it, its cover and its tint, so the strip
        /// can still show them once playback is gone.
        package var rememberMusic: (NotchPlayback, NSImage?, NotchArtworkTint?) -> Void
        /// The playing song is about to end.
        package var holdEndingTrack: () -> Void
        /// A new song to name in the capsule.
        package var nameSong: () -> Void
        /// The song changed while the strip still shows the previous one.
        package var trackChanged: () -> Void
        /// The tools page's tiles changed.
        package var toolsChanged: () -> Void
        /// The fan card appeared or left.
        package var fanCardChanged: () -> Void
        /// A download arrived.
        package var downloadArrived: (NotchDownloadItem) -> Void
        /// An agent finished a turn, neared or renewed a limit, or reached the budget.
        package var agentEvent: (AgentUsageEvent) -> Void
        /// A system notification to show. Returns whether the island now
        /// stands in for the system's banner.
        package var systemNotification: (NotchSystemNotification) -> Bool
        /// The clipboard history captured a copy.
        package var clipboardCaptured: () -> Void
        /// Music started playing.
        package var musicStarted: () -> Void
        /// A download failed.
        package var downloadFailed: () -> Void
        /// The calendar countdown changed.
        package var calendarChanged: () -> Void
        /// Keep Awake turned on or off.
        package var keepAwakeChanged: () -> Void

        package init(resize: @escaping () -> Void,
                     rememberMusic: @escaping (NotchPlayback, NSImage?, NotchArtworkTint?) -> Void,
                     holdEndingTrack: @escaping () -> Void,
                     nameSong: @escaping () -> Void,
                     trackChanged: @escaping () -> Void,
                     toolsChanged: @escaping () -> Void,
                     fanCardChanged: @escaping () -> Void,
                     downloadArrived: @escaping (NotchDownloadItem) -> Void,
                     agentEvent: @escaping (AgentUsageEvent) -> Void,
                     systemNotification: @escaping (NotchSystemNotification) -> Bool,
                     clipboardCaptured: @escaping () -> Void,
                     musicStarted: @escaping () -> Void = {},
                     downloadFailed: @escaping () -> Void = {},
                     calendarChanged: @escaping () -> Void = {},
                     keepAwakeChanged: @escaping () -> Void = {}) {
            self.resize = resize
            self.rememberMusic = rememberMusic
            self.holdEndingTrack = holdEndingTrack
            self.nameSong = nameSong
            self.trackChanged = trackChanged
            self.toolsChanged = toolsChanged
            self.fanCardChanged = fanCardChanged
            self.downloadArrived = downloadArrived
            self.agentEvent = agentEvent
            self.systemNotification = systemNotification
            self.clipboardCaptured = clipboardCaptured
            self.musicStarted = musicStarted
            self.downloadFailed = downloadFailed
            self.calendarChanged = calendarChanged
            self.keepAwakeChanged = keepAwakeChanged
        }
    }

    /// Which modules and notices are on when the island binds.
    package struct Settings {
        package var modules: [NotchModule]
        /// Whether the island shows a notice for this event.
        package var routes: (NotchEvent) -> Bool
        /// Whether the strip shows a Keep Awake session.
        package var keepAwakeActivity: Bool
        /// Whether fan control is available, which gives the system page its fan card.
        package var fanControl: Bool

        package init(modules: [NotchModule], routes: @escaping (NotchEvent) -> Bool,
                     keepAwakeActivity: Bool, fanControl: Bool) {
            self.modules = modules
            self.routes = routes
            self.keepAwakeActivity = keepAwakeActivity
            self.fanControl = fanControl
        }
    }

    private let sources: Sources
    private let island: Island
    private var subscriptions = Set<AnyCancellable>()

    package init(sources: Sources, island: Island) {
        self.sources = sources
        self.island = island
    }

    /// Replaces every subscription with the ones `settings` asks for.
    /// `heldSongTitles` is the title of the song a notice holds, which names
    /// the next song once the notice lets it go.
    package func bind(_ settings: Settings, heldSongTitles: AnyPublisher<String?, Never>) {
        subscriptions.removeAll()
        let modules = settings.modules
        let island = island
        if modules.contains(.timer) {
            sources.timer().sink { island.resize() }.store(in: &subscriptions)
        }
        if modules.contains(.watch) {
            sources.watch().sink { island.resize() }.store(in: &subscriptions)
        }
        if modules.contains(.music) {
            sources.music()
                .sink { playback, artwork, tint in
                    // @Published sends before storing the new value. Keep the last
                    // visible track and cover before playback disappears.
                    guard let playback else { return }
                    island.rememberMusic(playback, artwork, tint)
                }.store(in: &subscriptions)
            // Received at once, before the reading that ends the song is
            // published, so the strip leaves as its own song, cover included.
            sources.trackEnds()
                .sink { island.holdEndingTrack() }
                .store(in: &subscriptions)
            sources.musicActivity().sink { island.resize() }.store(in: &subscriptions)
            sources.musicStarts().sink { island.musicStarted() }.store(in: &subscriptions)
            // A capsule names each new song for a moment: the song playing,
            // or the next one once the notice releases the song it held.
            sources.songTitles().removeDuplicates().map { _ in () }
                .merge(with: heldSongTitles.removeDuplicates().map { _ in () })
                .receive(on: DispatchQueue.main)
                .sink { island.nameSong() }
                .store(in: &subscriptions)
        }
        if settings.routes(.track) {
            // Received at once, on the main thread, while the strip still
            // shows the previous song.
            sources.trackChanges()
                .sink { island.trackChanged() }
                .store(in: &subscriptions)
        }
        if modules.contains(.tools) {
            // The tools page is a rail sized by its tiles; editing or a
            // hosted utility turns it into a page.
            sources.tools().sink { island.toolsChanged() }.store(in: &subscriptions)
        }
        if modules.contains(.system), settings.fanControl {
            // The fan card only exists once the page's first sample lands; the
            // strip that was sized without it reserves its row again.
            sources.fanCard().sink { island.fanCardChanged() }.store(in: &subscriptions)
        }
        if settings.routes(.download) {
            sources.downloads().sink { island.resize() }.store(in: &subscriptions)
            sources.setDownloadArrival { island.downloadArrived($0) }
            sources.setDownloadFailure { island.downloadFailed() }
        }
        if modules.contains(.agents) {
            sources.agentActivity().sink { island.resize() }.store(in: &subscriptions)
        }
        if modules.contains(.calendar) {
            sources.calendar().sink { island.calendarChanged(); island.resize() }.store(in: &subscriptions)
        }
        // The companion is wide awake while Keep Awake holds the Mac up, and
        // yawns as it lets go.
        sources.keepAwakeTurns().sink { island.keepAwakeChanged() }.store(in: &subscriptions)
        if settings.keepAwakeActivity {
            sources.keepAwake().sink { island.resize() }.store(in: &subscriptions)
        }
        if settings.routes(.agents) {
            sources.agentEvents().sink { island.agentEvent($0) }.store(in: &subscriptions)
        }
        if settings.routes(.systemNotification) {
            let hideNative = sources.hideNativeNotification
            sources.systemNotifications().sink { item in
                if island.systemNotification(item) { hideNative(item.id) }
            }.store(in: &subscriptions)
        }
        if settings.routes(.clipboard) {
            sources.clipboardCaptures().sink { island.clipboardCaptured() }.store(in: &subscriptions)
        }
    }

    /// Drops every subscription.
    package func unbind() {
        subscriptions.removeAll()
    }
}
