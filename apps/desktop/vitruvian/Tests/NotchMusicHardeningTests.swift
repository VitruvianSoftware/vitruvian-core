// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The production lyrics service runs on a session of doubles: the
/// preferences, the lookups, the file chooser, the island and both queues. No
/// request is sent, no panel opens and nothing activates.
enum NotchLyricsContract {
    /// Work waiting for its queue. Only the test's own thread touches it.
    nonisolated final class Queue: @unchecked Sendable {
        var jobs: [() -> Void] = []
        func drain() { while !jobs.isEmpty { jobs.removeFirst()() } }
    }

    final class Lookup {
        let url: URL
        let answer: @Sendable (Data?, Bool) -> Void
        var cancelled = false
        init(url: URL, answer: @escaping @Sendable (Data?, Bool) -> Void) {
            self.url = url
            self.answer = answer
        }
    }

    final class Window: IslandWindowing {
        var isVisible = true
        var level = NSWindow.Level(rawValue: 26)
        var focused = false
        var focusReturns = 0
        func makeKey() { focused = true }
    }

    /// The island as the import sees it.
    final class Notch {
        var window: Window? = Window()
        var acceptsUserInteraction = true
        var expanded = true
        var selected: NotchModule = .music
        var pinned = false
    }

    final class Chooser {
        static weak var current: Chooser?
        var level: NSWindow.Level?
        var focused = false
        var cancelled = false
        var url: URL?
        private var completed: ((NSApplication.ModalResponse, URL?) -> Void)?
        var chooser: NotchLyricsService.Chooser {
            .init(begin: { level, _, completion in
                Self.current = self
                self.level = level
                self.completed = completion
            }, makeKeyAndOrderFront: { self.focused = true },
            cancel: { self.cancelled = true; self.finish(.cancel) })
        }
        func finish(_ response: NSApplication.ModalResponse) {
            if Self.current === self { Self.current = nil }
            completed?(response, url)
        }
    }

    final class Session {
        var enabled = true
        var online = false
        var lookups: [Lookup] = []
        var choosers: [Chooser] = []
        /// Whether the open chooser already had focus at each activation.
        var activationsAfterFocus: [Bool] = []
        let notch = Notch()
        let main = Queue()
        let worker = Queue()
        private(set) lazy var service = NotchLyricsService(environment: .init(
            isEnabled: { self.enabled },
            onlineEnabled: { self.enabled && self.online },
            lookup: { url, answer in
                let lookup = Lookup(url: url, answer: answer)
                self.lookups.append(lookup)
                return { lookup.cancelled = true }
            },
            island: {
                NotchIslandSurface(window: self.notch.window, acceptsUserInteraction: self.notch.acceptsUserInteraction,
                                   expanded: self.notch.expanded, selected: self.notch.selected)
            },
            makeChooser: {
                let chooser = Chooser()
                self.choosers.append(chooser)
                return chooser.chooser
            },
            activate: {
                // Activating the app collapses an island that is not pinned,
                // unless the chooser is already up to hold it open.
                if Chooser.current == nil, !self.notch.pinned { self.notch.expanded = false }
                self.activationsAfterFocus.append(Chooser.current?.focused == true)
            },
            reopenMusic: {
                self.notch.selected = .music
                self.notch.window?.focused = true
                self.notch.window?.focusReturns += 1
            },
            main: { [main = self.main] work in main.jobs.append { MainActor.assumeIsolated { work() } } },
            background: { [worker = self.worker] work in worker.jobs.append(work) }))

        /// Answers a lookup with lyrics for `title` and lets the reply land.
        func answer(_ lookup: Lookup?, title: String, line: String = "Imported") {
            let body: [String: Any] = ["trackName": title, "artistName": "Example", "albumName": "Recording",
                                       "duration": 180.0, "syncedLyrics": "[00:01]\(line)", "plainLyrics": ""]
            lookup?.answer(try? JSONSerialization.data(withJSONObject: body), false)
            main.drain()
        }
    }
}

/// A real music service over an adapter the test feeds by hand. Replies go in
/// as the adapter's own JSON lines and commands come out as the lines it would
/// read. The main queue, delayed work, the clock and the command queue run
/// when the test says. No process starts and nothing reaches a player.
enum NotchMusicCommandContract {
    /// Work waiting for its queue. Only the test's own thread touches it.
    nonisolated final class Jobs: @unchecked Sendable {
        var jobs: [() -> Void] = []
        func drain() { while !jobs.isEmpty { jobs.removeFirst()() } }
    }

    /// One adapter the service launched: what it was told and whether it runs.
    final class Link {
        let watchAll: Bool
        let read: @Sendable (Data) -> Void
        let ended: @Sendable () -> Void
        var running = true
        var failsWrites = false
        var written: [Data] = []
        init(watchAll: Bool, read: @escaping @Sendable (Data) -> Void, ended: @escaping @Sendable () -> Void) {
            self.watchAll = watchAll
            self.read = read
            self.ended = ended
        }
        var requests: [NotchPlaybackRequest] {
            written.compactMap {
                String(data: $0, encoding: .utf8).flatMap {
                    NotchPlaybackRequest(message: $0.trimmingCharacters(in: .newlines))
                }
            }
        }
    }

    /// The adapters, the clock and the delayed work, as the service sees them.
    final class Machine {
        var links: [Link] = []
        var now: TimeInterval = 0
        var delayed: [(at: TimeInterval, work: DispatchWorkItem)] = []
        var lyrics: [String?] = []
    }

    /// Automation that never finds a player, so no Apple Event is ever asked for.
    static var inertAutomation: NotchMusicAutomationFlow.Environment {
        .init(system: NotchMusicAutomation.System(target: { _ in nil }, isCurrent: { _ in false },
                                                  inspect: { _ in nil }, access: { _ in .unavailable },
                                                  consent: { _ in false }, deliver: { _ in nil }, uptime: { 0 }),
              worker: { _ in }, interactive: { _ in }, main: { _ in }, after: { _, _ in })
    }

    final class Harness {
        let machine: Machine
        let main: Jobs
        let commands: Jobs
        let defaultsName: String
        let defaults: UserDefaults
        let service: NotchMusicService
        /// The song still shown each time a new one, or an ended one, is announced.
        var announcedOver: [String?] = []
        var endedOver: [String?] = []
        private var subscriptions: Set<AnyCancellable> = []

        init() {
            let machine = Machine(), main = Jobs(), commands = Jobs()
            let name = "vitru.tests.notch-music.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            self.machine = machine
            self.main = main
            self.commands = commands
            defaultsName = name
            self.defaults = defaults
            service = NotchMusicService(environment: .init(
                launch: { watchAll, read, ended in
                    let link = Link(watchAll: watchAll, read: read, ended: ended)
                    machine.links.append(link)
                    return NotchMusicAdapterLink(isRunning: { link.running },
                                                 write: {
                                                     if link.failsWrites { throw CocoaError(.fileWriteUnknown) }
                                                     link.written.append($0)
                                                 },
                                                 end: { link.running = false })
                },
                main: { work in main.jobs.append { MainActor.assumeIsolated { work() } } },
                after: { delay, work in machine.delayed.append((machine.now + delay, work)) },
                uptime: { machine.now },
                commands: { commands.jobs.append($0) },
                defaults: defaults,
                lyricsChanged: { machine.lyrics.append($0?.track.title) },
                hideLyrics: {},
                automation: NotchMusicCommandContract.inertAutomation))
            service.trackChanges.sink { [unowned self] in announcedOver.append(service.playback?.track.title) }
                .store(in: &subscriptions)
            service.trackEnds.sink { [unowned self] in endedOver.append(service.playback?.track.title) }
                .store(in: &subscriptions)
        }

        deinit {
            defaults.removePersistentDomain(forName: defaultsName)
        }

        var links: [Link] { machine.links }
        var launches: [Bool] { machine.links.map(\.watchAll) }
        /// Delayed work still waiting to run.
        var pendingDelays: Int { machine.delayed.filter { !$0.work.isCancelled }.count }

        /// What the newest adapter, or `link`, has read so far.
        func requests(_ link: Link? = nil) -> [NotchPlaybackRequest] {
            commands.drain()
            return (link ?? machine.links.last)?.requests ?? []
        }

        /// The newest adapter prints one reading: `playback`, or nothing
        /// playing, with the players it lists. It lands on the main queue.
        func feed(_ playback: NotchPlayback?, sources: [NotchPlaybackSource] = [], automatic: Bool = true,
                  selectedPID: Int32? = nil, from link: Link? = nil) {
            var reply: [String: Any] = ["sourceIsAutomatic": automatic, "sources": sources.map(\.reply)]
            if let selectedPID { reply["selectedPID"] = selectedPID }
            if let playback {
                let track = playback.track
                reply["pid"] = track.appPID ?? 0
                reply["displayID"] = track.appBundleIdentifier ?? ""
                reply["isPlaying"] = playback.isPlaying
                reply[RadialNowPlayingSupport.titleKey] = track.title ?? ""
                if let artist = track.artist { reply[RadialNowPlayingSupport.artistKey] = artist }
                if let album = track.album { reply[RadialNowPlayingSupport.albumKey] = album }
                reply[RadialNowPlayingSupport.playbackRateKey] = playback.rate
                reply["kMRMediaRemoteNowPlayingInfoElapsedTime"] = playback.elapsed
                reply["kMRMediaRemoteNowPlayingInfoDuration"] = playback.duration
                reply["canSeek"] = playback.canSeek
                if let item = playback.itemIdentifier { reply["itemIdentifier"] = item }
                if let context = playback.commandContext { reply["playbackRevision"] = context.revision.uuidString }
                reply["canSendCommandsDirectly"] = playback.canSendCommandsDirectly
            }
            let data = try! JSONSerialization.data(withJSONObject: reply)
            (link ?? machine.links.last)?.read(data + Data([0x0A]))
            main.drain()
        }

        /// The newest adapter exits.
        func end() {
            machine.links.last?.running = false
            machine.links.last?.ended()
            main.drain()
        }

        /// Moves the clock on and runs the delayed work that falls due, in order.
        func advance(_ seconds: TimeInterval) {
            machine.now += seconds
            while let index = machine.delayed.indices.filter({ machine.delayed[$0].at <= machine.now })
                .min(by: { machine.delayed[$0].at < machine.delayed[$1].at }) {
                let work = machine.delayed.remove(at: index).work
                if !work.isCancelled { work.perform() }
                main.drain()
            }
        }

        /// Whether the page shows this song, as far as a reading says.
        func shows(_ expected: NotchPlayback?) -> Bool {
            let shown = service.playback
            return shown?.track.title == expected?.track.title && shown?.isPlaying == expected?.isPlaying
                && shown?.track.appBundleIdentifier == expected?.track.appBundleIdentifier
        }
    }
}

enum NotchMusicHardeningTests {
    private final class Scheduler {
        var work: [() -> Void] = []
        func enqueue(_ action: @escaping () -> Void) { work.append(action) }
        func drain() { while !work.isEmpty { work.removeFirst()() } }
    }

    static func run(_ suite: TestSuite) {
        sourcePriority(suite)
        sourceSwitching(suite)
        sourceRestore(suite)
        sourcePreference(suite)
        artworkInheritance(suite)
        trackChanges(suite)
        playbackGap(suite)
        standInGap(suite)
        NotchPlaybackRoutingTests.run(suite)
        lyricExpansion(suite)
        lyricLifecycle(suite)
        lyricPicker(suite)
        queueSelection(suite)
        queueHold(suite)
        framing(suite)
        pendingCommands(suite)
        controlLifecycle(suite)
        NotchMusicAutomationTests.run(suite)
    }

    private static func sourceSwitching(_ suite: TestSuite) {
        let harness = NotchMusicCommandContract.Harness()
        let service = harness.service
        service.start()
        var current = playback("music")
        current.commandContext = NotchPlaybackContext(pid: 42, revision: UUID())
        current.canSendCommandsDirectly = true
        let browser = NotchPlaybackSource(pid: 202, bundleIdentifier: "test.browser", isMusicApp: false,
                                          isPlaying: true, hasTrack: true)
        harness.feed(current, sources: [browser])
        service.selectSource(.init(pid: 202, bundleIdentifier: "missing.app"))
        suite.expect(harness.shows(current) && harness.requests().isEmpty,
                     "an obsolete source menu cannot clear playback or queue a selection")
        service.selectSource(browser.selection)
        suite.expect(service.playback == nil && service.awaitingPlayback,
                     "source switching retires the old controls until new playback arrives")
        suite.expect(!service.send(.toggle, context: current.commandContext),
                     "a control rendered before the source switch cannot send to the old player")
        suite.expect(harness.requests().last == NotchPlaybackRequest(command: .source(browser.selection)),
                     "the production writer preserves the exact source chosen by the user")
        let count = harness.requests().count
        service.selectSource(browser.selection)
        suite.expect(service.awaitingPlayback && harness.requests().count == count + 1,
                     "a discovered source is selectable from the empty playback state")
        suite.expect(!service.send(.toggle) && !service.send(.next) && !service.send(.seek(10)),
                     "allowing source selection without playback never enables transport commands")
        let written = harness.requests().count
        harness.feed(current, sources: [browser])
        service.selectSource(nil)
        suite.expect(harness.shows(current) && harness.requests().count == written,
                     "choosing Automatic while it is already in effect leaves the page and the adapter alone")
        let music = NotchPlaybackSource(pid: 42, bundleIdentifier: "test.music", isMusicApp: true,
                                        isPlaying: true, hasTrack: true)
        harness.feed(current, sources: [browser, music], automatic: false, selectedPID: 42)
        service.selectSource(.init(pid: 42, bundleIdentifier: "test.music"))
        suite.expect(harness.shows(current) && harness.requests().count == written,
                     "choosing the source already shown leaves the page and the adapter alone")
        // The chosen browser waits for its next video while music fills the gap.
        harness.feed(current, sources: [browser, music], automatic: false, selectedPID: 202)
        service.selectSource(browser.selection)
        suite.expect(harness.shows(current) && harness.requests().count == written,
                     "choosing the source that waits for its next track leaves the stand-in shown")
        harness.feed(nil, sources: [browser], automatic: false, selectedPID: 202)
        harness.advance(10)
        service.selectSource(nil)
        suite.expect(service.playback == nil
                     && harness.requests().last == NotchPlaybackRequest(command: .source(nil)),
                     "a selected source that is not responding can be released from the empty state")
        service.stop()
    }

    /// The adapter keeps a choice only while it runs, and it stops on lock,
    /// sleep or when the page closes. The service gives the choice back.
    private static func sourceRestore(_ suite: TestSuite) {
        let harness = NotchMusicCommandContract.Harness()
        let service = harness.service
        let browser = NotchPlaybackSource(pid: 202, bundleIdentifier: "test.browser", isMusicApp: false,
                                          isPlaying: true, hasTrack: true)
        let restore = NotchPlaybackRequest(command: .source(browser.selection))
        service.start()
        harness.feed(nil, sources: [browser])
        service.selectSource(browser.selection)
        service.stop()
        service.start()
        suite.expect(harness.links.count == 2 && harness.requests() == [restore],
                     "locking, sleeping or closing the page gives the next adapter the chosen source back")
        let song = playback("song")
        harness.feed(song, sources: [browser])
        suite.expect(service.playback == nil, "the new adapter's reading from before the restored choice is not shown")
        harness.feed(song, sources: [browser])
        suite.expect(harness.shows(song), "only that one reading is held back")
        harness.end()
        harness.advance(10)
        suite.expect(harness.links.count == 3 && harness.requests() == [restore],
                     "an adapter restarted after it ended gets back a choice it still listed")
        harness.feed(playback("stale"), sources: [browser], from: harness.links[1])
        harness.links[1].ended()
        harness.main.drain()
        suite.expect(service.playback == nil && harness.pendingDelays == 0 && harness.links.count == 3,
                     "an adapter that was replaced can neither show a reading nor end its successor")
        harness.feed(nil, sources: [])
        harness.end()
        harness.advance(10)
        suite.expect(harness.links.count == 4 && harness.requests().isEmpty,
                     "a choice the adapter reports gone is forgotten, and not restored")
        harness.feed(nil, sources: [browser])
        service.selectSource(browser.selection)
        harness.feed(nil, sources: [browser], automatic: false, selectedPID: 202)
        service.selectSource(nil)
        service.stop()
        service.start()
        suite.expect(harness.requests().isEmpty, "choosing Automatic forgets the choice")
        service.stop()
    }

    private static func sourcePreference(_ suite: TestSuite) {
        let harness = NotchMusicCommandContract.Harness()
        let service = harness.service
        let browser = NotchPlaybackSource(pid: 20, bundleIdentifier: "test.browser", isMusicApp: false,
                                          isPlaying: true, hasTrack: true)
        let restore = NotchPlaybackRequest(command: .source(browser.selection))
        service.start()
        suite.expect(harness.launches == [false], "automatic playback starts with music apps only")
        service.start()
        suite.expect(harness.launches == [false], "an unchanged playback scope does not restart the adapter")
        harness.feed(nil, sources: [browser])
        service.selectSource(browser.selection)
        harness.defaults.set(true, forKey: DefaultsKey.notchIncludeOtherPlayers)
        service.start()
        suite.expect(harness.launches == [false, true] && harness.requests() == [restore],
                     "including other players restarts discovery and preserves a manual choice")
        harness.defaults.set(false, forKey: DefaultsKey.notchIncludeOtherPlayers)
        service.start()
        suite.expect(harness.launches == [false, true, false] && harness.requests() == [restore],
                     "turning the option off restores music-only discovery without losing the chosen source")
        service.stop()
    }

    /// The island announces a new song, never what a playing song keeps
    /// reporting or what a reader finds when it starts.
    private static func trackChanges(_ suite: TestSuite) {
        func reading(_ title: String?, artist: String? = "Artist", player: String = "com.example.player",
                     playing: Bool = true, elapsed: TimeInterval = 0) -> NotchPlayback {
            NotchPlayback(track: RadialNowPlayingSnapshot(title: title, artist: artist, album: nil, artworkData: nil,
                                                          appBundleIdentifier: player, appPID: 42),
                          isPlaying: playing, elapsed: elapsed, duration: 200, rate: 1, sampledAt: Date(), canSeek: true)
        }
        var tracker = NotchTrackChange()
        suite.expect(!tracker.isNewSong(reading("One"), first: true), "the reader's first song only sets where the player is")
        suite.expect(!tracker.isNewSong(reading("One", elapsed: 30), first: false)
                     && !tracker.isNewSong(reading("One", playing: false), first: false)
                     && !tracker.isNewSong(reading("One"), first: false),
                     "seeking, pausing and resuming the same song is not a new song")
        suite.expect(tracker.isNewSong(reading("Two"), first: false), "a player moving on to another song is a new song")
        suite.expect(!tracker.isNewSong(reading("Two", artist: nil), first: false)
                     && !tracker.isNewSong(reading("Two", artist: "Artist"), first: false),
                     "a reading that lacks the artist still names the same song")
        suite.expect(!tracker.isNewSong(reading("Three", playing: false), first: false)
                     && tracker.isNewSong(reading("Three"), first: false),
                     "the next song counts once it plays, even when first reported paused")
        suite.expect(!tracker.isNewSong(reading("Elsewhere", player: "com.example.other"), first: false)
                     && !tracker.isNewSong(reading("Three"), first: false),
                     "another player standing in between tracks is a new song for neither")
        suite.expect(!tracker.isNewSong(reading(nil), first: false) && !tracker.isNewSong(reading("  "), first: false)
                     && !tracker.isNewSong(nil, first: false),
                     "a reading without a title is never announced")
        suite.expect(!tracker.isNewSong(reading("Four"), first: true) && !tracker.isNewSong(reading("Four"), first: false),
                     "a reader that starts again or changes source reports its song without announcing it")
        tracker.reset()
        suite.expect(!tracker.isNewSong(reading("Five"), first: false),
                     "after the reader stops, a player's first song is not a change")
        let playing = reading("Song")
        suite.expect(NotchTrackChange.isBetweenSongs(nil, after: playing)
                     && NotchTrackChange.isBetweenSongs(reading("Other", player: "com.example.other", playing: false), after: playing)
                     && NotchTrackChange.isBetweenSongs(reading("Next", playing: false), after: playing),
                     "nothing playing, another player's paused song or the next song paused is a player between songs")
        suite.expect(!NotchTrackChange.isBetweenSongs(reading("Song", playing: false), after: playing)
                     && !NotchTrackChange.isBetweenSongs(reading("Song", artist: nil, playing: false), after: playing)
                     && !NotchTrackChange.isBetweenSongs(reading("Next"), after: playing)
                     && !NotchTrackChange.isBetweenSongs(reading("Other", player: "com.example.other"), after: playing)
                     && !NotchTrackChange.isBetweenSongs(reading("Other", player: "com.example.other", playing: false),
                                                         after: reading("Song", playing: false)),
                     "a pause, a song that plays, or a change after a paused song is shown at once")
        func listing(hasTrack: Bool) -> NotchPlaybackSource {
            NotchPlaybackSource(pid: 42, bundleIdentifier: "com.example.player", isMusicApp: false,
                                isPlaying: false, hasTrack: hasTrack)
        }
        suite.expect(!NotchTrackChange.isBetweenSongs(reading("Other", player: "com.example.other", playing: false),
                                                      after: playing, sources: [listing(hasTrack: true)]),
                     "a player paused while automatic playback moves to another player's paused song is a pause")
        suite.expect(NotchTrackChange.isBetweenSongs(reading("Other", player: "com.example.other", playing: false),
                                                     after: playing, sources: [listing(hasTrack: false)])
                     && NotchTrackChange.isBetweenSongs(reading("Next", playing: false), after: playing,
                                                        sources: [listing(hasTrack: true)]),
                     "a stand-in for a player that lists no song, or that player's own next song paused, is still a gap")
        suite.expect(NotchEvent.track.priority == 0 && NotchEvent.track.duration == 3,
                     "a new song gives way to any other notice and leaves after three seconds")
    }

    /// A player moving on to its next song can report nothing playing for a
    /// moment. The production reading path keeps the last song through it.
    private static func playbackGap(_ suite: TestSuite) {
        let harness = NotchMusicCommandContract.Harness()
        let service = harness.service
        let player = NotchPlaybackSource(pid: 42, bundleIdentifier: "org.example.player", isMusicApp: true,
                                         isPlaying: true, hasTrack: true)
        let other = NotchPlaybackSource(pid: 202, bundleIdentifier: "test.browser", isMusicApp: false,
                                        isPlaying: false, hasTrack: true)
        func controllable(_ item: String) -> NotchPlayback {
            var song = playback(item)
            song.commandContext = NotchPlaybackContext(pid: 42, revision: UUID())
            song.canSendCommandsDirectly = true
            return song
        }
        let current = controllable("current"), next = controllable("next")
        service.start()
        harness.feed(current, sources: [player, other])
        harness.feed(nil, sources: [other])
        suite.expect(harness.shows(current) && service.sources == [player, other] && !service.awaitingPlayback,
                     "a player between songs keeps its last song and sources instead of the empty page")
        suite.expect(!service.send(.next) && !service.commandFailed,
                     "the held song's controls send nothing, so a press cannot read as a failure")
        harness.feed(nil, sources: [other])
        suite.expect(harness.pendingDelays == 1, "another empty reading does not extend the grace period")
        harness.feed(next, sources: [player, other])
        suite.expect(harness.shows(next) && harness.pendingDelays == 0 && harness.announcedOver == ["current"],
                     "the next song replaces the held one at once, announced while the old one is still shown")
        suite.expect(service.send(.next), "the next song's controls work at once")
        harness.advance(10)
        suite.expect(harness.shows(next), "the ended gap cannot clear the next song later")
        harness.feed(nil, sources: [other])
        harness.advance(10)
        suite.expect(service.playback == nil && service.sources == [other] && !service.awaitingPlayback,
                     "playback that stays gone empties the page after the grace period, with the latest sources")
        harness.feed(next, sources: [player, other])
        harness.feed(nil, sources: [other])
        service.selectSource(other.selection)
        harness.advance(10)
        suite.expect(service.playback == nil && service.awaitingPlayback,
                     "choosing another source during a gap still waits for that source's first reading")
        harness.feed(current, sources: [player, other])
        harness.feed(nil, sources: [other])
        service.stop()
        harness.advance(10)
        suite.expect(service.playback == nil && harness.pendingDelays == 0,
                     "stopping during a gap ends it, and the held song cannot come back")
    }

    /// Between songs another player's paused song can stand in, or the next
    /// song can be reported paused before it starts. The production reading
    /// path keeps the song that played through both, as through an empty one.
    private static func standInGap(_ suite: TestSuite) {
        let harness = NotchMusicCommandContract.Harness()
        let service = harness.service
        let player = NotchPlaybackSource(pid: 42, bundleIdentifier: "org.example.player", isMusicApp: true,
                                         isPlaying: true, hasTrack: true)
        let other = NotchPlaybackSource(pid: 202, bundleIdentifier: "test.music", isMusicApp: true,
                                        isPlaying: false, hasTrack: true)
        func paused(_ song: NotchPlayback) -> NotchPlayback {
            NotchPlayback(track: song.track, isPlaying: false, elapsed: 0, duration: song.duration, rate: 0,
                          sampledAt: song.sampledAt, canSeek: false, itemIdentifier: song.itemIdentifier)
        }
        let current = playback("current"), next = playback("next"), later = playback("later")
        let standIn = paused(NotchPlayback(track: RadialNowPlayingSnapshot(title: "Elsewhere", artist: "Other", album: nil,
                                                                           artworkData: nil, appBundleIdentifier: "test.music",
                                                                           appPID: 202),
                                           isPlaying: false, elapsed: 30, duration: 200, rate: 0,
                                           sampledAt: Date(timeIntervalSinceReferenceDate: 0), canSeek: false))
        service.start()
        harness.feed(current, sources: [player, other])
        harness.feed(standIn, sources: [other])
        suite.expect(harness.shows(current) && service.sources == [player, other] && harness.pendingDelays == 1,
                     "another player's paused song standing in between songs keeps the song that played")
        let listed = NotchPlaybackSource(pid: 42, bundleIdentifier: "org.example.player", isMusicApp: false,
                                         isPlaying: false, hasTrack: true)
        harness.feed(standIn, sources: [listed, other])
        suite.expect(harness.shows(current) && harness.pendingDelays == 1,
                     "a player that lists its next song again while it loads keeps the gap going")
        harness.feed(next, sources: [player, other])
        suite.expect(harness.shows(next) && harness.pendingDelays == 0 && harness.announcedOver == ["current"],
                     "the next song replaces it at once, announced while the song before is still shown")
        harness.feed(paused(later), sources: [player, other])
        suite.expect(harness.shows(next) && harness.pendingDelays == 1,
                     "the next song reported paused before it starts keeps the song that played")
        suite.expect(harness.endedOver.isEmpty, "a gap that ends in a new song ends nothing")
        harness.advance(10)
        suite.expect(harness.shows(paused(later)) && harness.pendingDelays == 0,
                     "a song that stays paused is shown after the grace period")
        suite.expect(harness.endedOver == ["next"], "the end of the song is announced while it is still shown")
        harness.feed(later, sources: [player, other])
        harness.feed(paused(later), sources: [player, other])
        suite.expect(harness.shows(paused(later)) && harness.pendingDelays == 0 && harness.endedOver == ["next"],
                     "pausing the song that plays is shown at once, and ends nothing")
        harness.feed(later, sources: [player, other])
        harness.feed(standIn, sources: [listed, other])
        suite.expect(harness.shows(standIn) && harness.pendingDelays == 0 && service.sources == [listed, other],
                     "a pause that hands automatic playback to another player's paused song is shown at once")
        suite.expect(harness.endedOver == ["next", "later"], "the strip leaves such a pause as its own song")
    }

    /// The adapter flags bytes equal to its previous reading as unchanged,
    /// even when that reading belonged to the previous song.
    private static func artworkInheritance(_ suite: TestSuite) {
        let start = Date(timeIntervalSince1970: 100)
        func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }
        func reading(_ title: String, _ artwork: String = "") -> NotchPlayback? {
            NotchPlayback.decode(Data("{\"pid\":42,\"kMRMediaRemoteNowPlayingInfoTitle\":\"\(title)\"\(artwork)}".utf8),
                                 previousArtwork: Data([1, 2, 3]))
        }
        let first = reading("First", ",\"artworkBase64\":\"AQID\"")
        let repeated = reading("Second", ",\"artworkUnchanged\":true")
        let missing = reading("Second")
        let own = reading("Second", ",\"artworkBase64\":\"BAUG\"")
        suite.expect(repeated?.track.artworkData == first?.track.artworkData && missing?.track.artworkData == nil,
                     "an unchanged-artwork reply for a new song decodes to the previous song's cover")
        var cache = NotchArtworkCache<String>()
        cache.update("first", for: first, now: start)
        cache.update("first", for: repeated, now: at(0.2))
        cache.update("first", for: repeated, now: at(0.4))
        suite.expect(cache.artwork == "first" && cache.expiresAt == nil,
                     "a cover repeated on a new song stays visible without flickering")
        cache.update(nil, for: missing, now: at(0.8))
        cache.expire(at: at(1.6))
        suite.expect(cache.artwork == "first", "the repeated cover keeps the usual grace period")
        cache.expire(at: at(1.8))
        suite.expect(cache.artwork == nil, "a new song without artwork cannot keep the previous song's cover")

        cache = NotchArtworkCache<String>()
        cache.update("first", for: first, now: start)
        cache.update("first", for: repeated, now: at(0.2))
        cache.update(nil, for: missing, now: at(10))
        suite.expect(cache.artwork == "first" && cache.expiresAt == nil,
                     "songs sharing one cover keep it through later metadata-only replies")
        cache = NotchArtworkCache<String>()
        cache.update("first", for: first, now: start)
        cache.update("first", for: repeated, now: at(0.2))
        cache.update("second", for: own, now: at(0.4))
        cache.update(nil, for: missing, now: at(0.8))
        suite.expect(cache.artwork == "second" && cache.expiresAt == nil,
                     "the new song's own cover survives its metadata-only replies")
    }

    private static func sourcePriority(_ suite: TestSuite) {
        func source(_ pid: Int32, music: Bool, playing: Bool = true, track: Bool = true) -> NotchPlaybackSource {
            NotchPlaybackSource(pid: pid, bundleIdentifier: "test.player.\(pid)", isMusicApp: music,
                                isPlaying: playing, hasTrack: track)
        }
        let music = source(10, music: true)
        let paused = source(10, music: true, playing: false)
        let browser = source(20, music: false)
        let other = source(30, music: true)
        suite.expect(NotchPlaybackSource.isMusicApplication(bundleIdentifier: "com.apple.Music", parentBundleIdentifier: nil,
                                                             category: nil)
                     && NotchPlaybackSource.isMusicApplication(bundleIdentifier: "com.spotify.client.helper",
                                                               parentBundleIdentifier: "com.spotify.client", category: nil)
                     && NotchPlaybackSource.isMusicApplication(bundleIdentifier: "com.example.player",
                                                               parentBundleIdentifier: nil, category: "public.app-category.music")
                     && !NotchPlaybackSource.isMusicApplication(bundleIdentifier: "com.example.browser",
                                                                parentBundleIdentifier: nil, category: "public.app-category.video"),
                     "music apps and Spotify helpers stay eligible while video apps are excluded")
        func choose(_ sources: [NotchPlaybackSource], previous: Int32? = nil, system: Int32? = 20,
                    includeOtherPlayers: Bool = false) -> NotchPlaybackSource? {
            NotchPlaybackSource.preferred(in: sources, previousPID: previous, systemPID: system,
                                          includeOtherPlayers: includeOtherPlayers)
        }
        suite.expect(choose([browser, music]) == music, "a browser video cannot take controls from playing music")
        suite.expect(choose([music, browser]) == music, "source discovery order does not change music priority")
        suite.expect(choose([browser, paused], previous: 10) == paused && choose([browser]) == nil,
                     "music-only automatic playback ignores videos, even when they own the system session")
        suite.expect(choose([browser, paused], previous: 10, includeOtherPlayers: true) == browser
                     && choose([browser], includeOtherPlayers: true) == browser,
                     "the opt-in restores automatic playback from other apps")
        suite.expect(choose([paused, browser], previous: 10, system: 10, includeOtherPlayers: true) == browser,
                     "a playing browser takes over when the system player still points at paused music")
        suite.expect(choose([browser], previous: nil, system: 99, includeOtherPlayers: true) == browser,
                     "a newly registered playing client does not need an existing follow relationship")
        suite.expect(choose([music, browser], previous: 20, system: 20, includeOtherPlayers: true) == music,
                     "including other players preserves priority for actively playing music")
        let idleBrowser = source(20, music: false, playing: false)
        suite.expect(NotchPlaybackSource.preferred(in: [music, browser], previousPID: 10, systemPID: 10,
                                                   selection: browser.selection) == browser,
                     "an explicit browser selection overrides simultaneous music playback")
        suite.expect(choose([paused, idleBrowser], previous: 10, system: 10, includeOtherPlayers: true) == paused,
                     "an unrelated paused browser cannot replace a music resume control")
        suite.expect(NotchPlaybackSource.preferred(in: [music, idleBrowser], previousPID: 20, systemPID: 10,
                                                   selection: browser.selection) == idleBrowser,
                     "pausing a chosen browser keeps its resume control reachable")
        suite.expect(NotchPlaybackSource.preferred(in: [music], previousPID: 20, systemPID: 10,
                                                   selection: browser.selection) == music,
                     "closing the chosen source restores automatic selection")
        suite.expect(NotchPlaybackSource.preferred(in: [music, source(20, music: false, track: false)],
                                                   previousPID: 20, systemPID: 10, selection: browser.selection) == music,
                     "a chosen source that loses its track no longer hides available playback")
        let decoded = NotchPlaybackSource.decode([browser.reply, music.reply, browser.reply])
        suite.expect(decoded == [music, browser], "source replies have stable ordering and reject duplicate processes")
        var helper = browser
        helper.displayName = "Browser"
        suite.expect(NotchPlaybackSource.decode([helper.reply]) == [helper] && helper.selection == browser.selection,
                     "a browser helper displays its owning app without changing the command destination")
        helper.displayName = String(repeating: "x", count: 257)
        suite.expect(NotchPlaybackSource.decode([helper.reply]).first?.displayName == nil,
                     "unbounded source names fall back to the local application name")
        var malformed = browser.reply
        malformed["pid"] = true
        suite.expect(NotchPlaybackSource.decode([malformed]).isEmpty
                     && NotchPlaybackSource.decode(Array(repeating: browser.reply, count: 17)).isEmpty,
                     "invalid and unbounded source replies cannot populate the chooser")
        var waiting = browser.reply
        waiting["hasTrack"] = false
        let chosen = NotchPlaybackSource.decode([waiting], selectedPID: 20).first
        suite.expect(NotchPlaybackSource.decode([waiting]).isEmpty && chosen?.pid == 20 && chosen?.hasTrack == false,
                     "a source without a track is listed only while it is the chosen one")
        suite.expect(NotchPlaybackSource.decodePID(20) == 20 && NotchPlaybackSource.decodePID(true) == nil,
                     "the chosen source's process is validated like a listed one")
        for command in [NotchPlaybackCommand.source(browser.selection), .source(nil)] {
            let request = NotchPlaybackRequest(command: command)
            suite.expect(request.message.flatMap(NotchPlaybackRequest.init(message:)) == request,
                         "source selection round-trips without borrowing a playback revision")
        }
        for message in ["source 0 YXBw", "source 20 !!!", "source 20 ", "source-auto extra"] {
            suite.expect(NotchPlaybackRequest(message: message) == nil, "malformed source choices are rejected")
        }
        suite.expect(choose([idleBrowser, paused], previous: 10) == paused,
               "pausing music keeps its resume control reachable once nothing is playing")
        suite.expect(choose([idleBrowser, paused]) == paused, "reopening the music surface can still reach paused music")
        suite.expect(choose([browser, paused, other], previous: 10) == other,
               "playing music still outranks a playing browser and a paused music app")
        // A music app open but stopped, a video playing in the browser: the
        // island used to go blank, since paused music outranked everything.
        suite.expect(choose([paused, browser], previous: nil, system: 20, includeOtherPlayers: true) == browser,
               "with other players enabled, a stopped music app does not hide a playing video")
        suite.expect(choose([browser, source(10, music: true, track: false)], includeOtherPlayers: true) == browser,
               "with other players enabled, an empty music app does not hide browser playback")
        suite.expect(choose([browser], previous: 10, includeOtherPlayers: true) == browser,
                     "with other players enabled, closing the music app releases its priority")
        suite.expect(choose([source(10, music: true, track: false)], previous: 10) == nil,
               "clearing the track never preserves a stale music selection")
        suite.expect(choose([music, other, browser], previous: 30) == other,
               "two playing music apps keep the previously controlled app")
        suite.expect(choose([paused, other, browser], previous: 10) == other,
               "newly playing music takes priority over another app's paused track")
        suite.expect(choose([music, other], system: 30) == other,
               "the system's choice breaks an initial tie between playing music apps")
        suite.expect(choose([browser], system: 99) == nil, "an unrelated remembered video never becomes a fallback")
        suite.expect(choose([source(0, music: true), browser], includeOtherPlayers: true) == browser,
                     "invalid process identities are not controllable")
        suite.expect(choose([], previous: 10) == nil, "no surviving session leaves no command destination")
    }

    private static func lyricExpansion(_ suite: TestSuite) {
        let repeated = String(repeating: "[00:01]", count: 2000) + String(repeating: "x", count: 110_000)
        suite.expect(repeated.utf8.count < NotchLyricsSupport.maximumBytes,
               "the expansion regression fixture fits inside the transport's input bound")
        suite.expect(NotchLyricsSupport.parse(repeated, duration: 180).isEmpty,
               "many timestamps cannot amplify a small response into hundreds of megabytes")
        let voices = (0..<2000).map { "[00:01]voice \($0)" }.joined(separator: "\n")
        let grouped = NotchLyricsSupport.parse(voices, duration: 180)
        suite.expect(grouped.count == 1 && grouped.first?.text.hasPrefix("voice 0\nvoice 1\n") == true
               && grouped.first?.text.hasSuffix("voice 1999") == true,
               "grouping equal timestamps preserves ordered voices with one final join")
        suite.expect(grouped.reduce(0) { $0 + $1.text.utf8.count } <= NotchLyricsSupport.maximumBytes,
               "the expanded display text stays within the same byte budget")
        let distinct = (0..<2000).map { "[\($0 / 60):\($0 % 60)]" }.joined() + String(repeating: "界", count: 30)
        suite.expect(distinct.utf8.count < NotchLyricsSupport.maximumBytes
               && NotchLyricsSupport.parse(distinct, duration: 2200).isEmpty,
               "the expansion bound counts UTF-8 bytes across distinct timestamps as well")
        let normal = NotchLyricsSupport.parse("[00:01][00:03]Chorus\n[00:02]", duration: 10)
        suite.expect(normal.map(\.text) == ["Chorus", "", "Chorus"], "normal repeated verses and timed instrumental gaps still work")
    }

    private static func playback(_ item: String) -> NotchPlayback {
        let track = RadialNowPlayingSnapshot(title: item, artist: "Example", album: "Recording",
            artworkData: nil, appBundleIdentifier: "org.example.player", appPID: 42)
        return NotchPlayback(track: track, isPlaying: true, elapsed: 0, duration: 180, rate: 1,
            sampledAt: Date(timeIntervalSinceReferenceDate: 0), canSeek: false, itemIdentifier: item)
    }

    private static func lyricLifecycle(_ suite: TestSuite) {
        let session = NotchLyricsContract.Session()
        let service = session.service
        let current = playback("current"), next = playback("next")
        let imported = NotchLyrics(lines: [NotchLyricLine(time: 1, text: "Imported")], plain: "", instrumental: false)
        session.online = true
        service.update(playback: current, visible: true)
        session.answer(session.lookups.last, title: "current")
        service.adjustOffset(by: 0.75)
        suite.expect(service.state == .ready && service.lyrics == imported, "a found lookup shows its lyrics")
        service.hide()
        suite.expect(!service.visible && service.lyrics == imported && service.offset == 0.75,
               "the real hide path keeps this song's lyrics and adjustment")
        service.update(playback: current, visible: true)
        suite.expect(service.state == .ready && service.lyrics == imported && session.lookups.count == 1
               && service.offset == 0.75, "returning to the same song reuses its lyrics without a network request")
        service.update(playback: current, visible: false)
        service.update(playback: nil, visible: false)
        suite.expect(service.lyrics == imported, "hiding or stopping the metadata consumer is not evidence that the song changed")
        service.playbackChanged(next)
        suite.expect(service.track == NotchMusicIdentity(next) && service.lyrics == nil && service.offset == 0,
               "an observed track change clears the one-song cache while hidden")
        service.playbackChanged(current)
        service.update(playback: current, visible: true)
        let earlier = session.lookups.last
        service.playbackChanged(next)
        session.answer(earlier, title: "current")
        suite.expect(earlier?.cancelled == true && service.track == NotchMusicIdentity(next) && service.lyrics == nil
               && service.state == .loading, "a late result cannot replace the new recording's lyrics")
        service.retry()
        let replaced = session.lookups.last
        service.retry()
        session.answer(replaced, title: "next", line: "Stale")
        suite.expect(replaced?.cancelled == true && service.lyrics == nil && service.state == .loading,
               "a retried lookup ignores the answer of the one it replaced")
        service.playbackChanged(nil)
        suite.expect(service.track == nil && service.lyrics == nil, "an actual empty playback snapshot clears the cache")
        service.update(playback: current, visible: true)
        let download = session.lookups.last
        service.importLyrics()
        let panel = session.choosers.last
        service.hide()
        session.answer(download, title: "current")
        suite.expect(download?.cancelled == true && panel?.cancelled == true && !service.isImporting
               && service.lyrics == nil, "hiding executes the real cancellation path for both remote lookup and file selection")
        let lookups = session.lookups.count
        service.update(playback: current, visible: false)
        suite.expect(session.lookups.count == lookups, "a hidden song never starts an online lookup")
        service.update(playback: current, visible: true)
        suite.expect(session.lookups.count == lookups + 1, "reopening an uncached song starts one fresh lookup")
        session.answer(session.lookups.last, title: "current")
        service.adjustOffset(by: 1)
        service.stop()
        suite.expect(service.track == nil && service.lyrics == nil && service.offset == 0 && !service.visible,
               "explicit shutdown releases the retained song, lyrics and offset")
        service.update(playback: current, visible: true)
        session.answer(session.lookups.last, title: "current")
        session.enabled = false
        service.hide()
        suite.expect(service.lyrics == nil && service.track == nil, "feature removal clears the cache even when it arrives through the hide path")
    }

    private static func lyricPicker(_ suite: TestSuite) {
        typealias Context = NotchLyricsContract
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notch-lyrics-picker-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("selected.lrc")
            try "[00:01]Selected verse".write(to: file, atomically: true, encoding: .utf8)
            let existing = folder.appendingPathComponent("existing.lrc")
            try "[00:01]Existing verse".write(to: existing, atomically: true, encoding: .utf8)
            for pinned in [false, true] {
                let session = Context.Session()
                let service = session.service
                let notch = session.notch
                let parent = notch.window!
                notch.pinned = pinned
                service.update(playback: playback("same-song"), visible: true)
                service.importLyrics()
                guard let panel = session.choosers.last, service.isImporting else {
                    suite.expect(false, "a visible lyrics surface can choose a file"); continue
                }
                suite.expect(panel.focused && (panel.level?.rawValue ?? 0) > parent.level.rawValue
                       && notch.expanded && notch.pinned == pinned && session.activationsAfterFocus == [false],
                       "lyrics imports focus a standalone chooser above the island without moving it or changing its pin")
                panel.url = file
                panel.finish(.OK)
                suite.expect(!parent.focused && service.lyrics == nil,
                       "the picker waits for native dismissal and imports off the presentation lane")
                session.main.drain()
                suite.expect(parent.focused && parent.focusReturns == 1 && notch.selected == .music && notch.pinned == pinned,
                       "dismissal returns to the same music and lyrics surface without pinning it")
                session.worker.drain()
                session.main.drain()
                suite.expect(service.lyrics?.lines.first?.text == "Selected verse" && service.visible,
                       "the real bounded import and parser retain the chosen lyrics for the unchanged song")
            }
            for interruption in 0..<6 {
                let session = Context.Session()
                let service = session.service
                let parent = session.notch.window!
                service.update(playback: playback("same-song"), visible: true)
                service.importLyrics()
                let panel = session.choosers.last!
                panel.url = file
                switch interruption {
                case 0: service.hide()
                case 1: service.playbackChanged(playback("next-song"))
                case 2: session.notch.acceptsUserInteraction = false
                case 3: session.notch.selected = .downloads
                case 4: session.notch.window = Context.Window()
                default: session.enabled = false
                }
                panel.finish(.OK)
                session.worker.drain()
                session.main.drain()
                suite.expect(parent.focusReturns == 0 && service.lyrics == nil,
                       "hide, track change, lock, another section, replacement or disable rejects the old import and focus")
            }
            let late = Context.Session()
            late.service.update(playback: playback("same-song"), visible: true)
            late.service.importLyrics()
            let first = late.choosers.last!
            late.service.hide()
            late.service.update(playback: playback("same-song"), visible: true)
            late.service.importLyrics()
            first.finish(.OK)
            suite.expect(late.service.isImporting && late.choosers.count == 2,
                   "a late answer from an earlier chooser leaves the open one in place")
            let moved = Context.Session()
            moved.service.update(playback: playback("same-song"), visible: true)
            moved.service.importLyrics()
            moved.choosers.last?.finish(.cancel)
            moved.notch.selected = .downloads
            moved.main.drain()
            suite.expect(moved.notch.window?.focusReturns == 0,
                   "an island that moved on before the next turn is not reopened")
            let superseded = Context.Session()
            superseded.service.update(playback: playback("same-song"), visible: true)
            superseded.service.importLyrics()
            superseded.choosers.last?.url = file
            superseded.choosers.last?.finish(.OK)
            superseded.online = true
            superseded.service.update(playback: playback("same-song"), visible: true)
            superseded.worker.drain()
            superseded.main.drain()
            suite.expect(superseded.service.lyrics == nil && superseded.service.state == .loading,
                   "work started after the file was chosen supersedes its late result")
            let session = Context.Session()
            let cancelled = session.service
            let window = session.notch.window!
            cancelled.update(playback: playback("same-song"), visible: true)
            cancelled.importLyrics()
            session.choosers.last?.url = existing
            session.choosers.last?.finish(.OK)
            session.worker.drain()
            session.main.drain()
            let old = cancelled.lyrics
            cancelled.adjustOffset(by: 0.5)
            cancelled.importLyrics()
            session.choosers.last?.finish(.cancel)
            session.main.drain()
            suite.expect(old?.lines.first?.text == "Existing verse" && cancelled.lyrics == old && cancelled.offset == 0.5
                   && session.worker.jobs.isEmpty && window.focused,
                   "Cancel keeps the current lyrics and adjustment and returns without reading a file")
            cancelled.importLyrics()
            session.choosers.last?.url = file
            session.choosers.last?.finish(.OK)
            let returns = window.focusReturns
            cancelled.hide()
            session.worker.drain()
            session.main.drain()
            suite.expect(window.focusReturns == returns && cancelled.lyrics == old,
                   "leaving after dismissal cancels both the queued focus return and a late file result")
        } catch { suite.expect(false, "lyrics picker fixture failed: \(error)") }
    }

    private static func selection(_ request: UUID, item: String = "next") -> NotchQueueSelection {
        NotchQueueSelection(requestID: request, pid: 42, currentIdentifier: "current", itemIdentifier: item, offset: 2)
    }

    private static func queueSelection(_ suite: TestSuite) {
        let selected = selection(UUID())
        suite.expect(selected.matches(pid: 42, currentIdentifier: "current", itemIdentifier: "next", offset: 2),
               "the native action can match exactly the immutable row the user chose")
        suite.expect(!selected.matches(pid: 43, currentIdentifier: "current", itemIdentifier: "next", offset: 2)
               && !selected.matches(pid: 42, currentIdentifier: "changed", itemIdentifier: "next", offset: 2)
               && !selected.matches(pid: 42, currentIdentifier: "current", itemIdentifier: "different", offset: 2)
               && !selected.matches(pid: 42, currentIdentifier: "current", itemIdentifier: "next", offset: 3),
               "a refreshed native cache cannot retarget a queued click to another player, track, entry or offset")
        let command = NotchPlaybackCommand.queuePlay(selected)
        suite.expect(command.message.flatMap(NotchPlaybackCommand.init(message:)) == command,
               "process, anchor track and native offset all survive the command transport")
        suite.expect(NotchPlaybackCommand(message: "queue-play \(selected.requestID.uuidString) bmV4dA==") == nil,
               "the old unbound command shape is rejected")
        suite.expect(!selection(UUID(), item: "bad\0item").isValid,
               "the row, writer and native bridge share rejection of NUL identifiers")

        let domain = "com.vitruviansoftware.vitruvian.tests.notch-queue-selection"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        let row = NotchQueueItem(id: "next", offset: 2, title: "Next", artist: "", duration: 0)
        let current = playback("current")
        var upcoming = NotchQueueSnapshot(requestID: selected.requestID, currentIdentifier: "current", pid: 42,
            items: [row], canPlay: true)
        var visible = true
        var pending = false
        var failed = false
        var sendAllowed = false
        var commands: [NotchPlaybackCommand] = []
        func playQueued(_ item: NotchQueueItem) {
            NotchMusicService.playQueued(item, visible: visible, request: selected.requestID, upcoming: upcoming,
                                         playback: current, pending: &pending, failed: &failed, in: defaults) {
                commands.append($0)
                return sendAllowed && $0.message != nil
            }
        }
        playQueued(row)
        suite.expect(!pending && failed,
               "the real row action releases pending state when the writer rejects a command")
        commands.removeAll()
        sendAllowed = true
        playQueued(row)
        suite.expect(commands == [.queuePlay(selected)] && pending && !failed,
               "the real UI action captures its displayed process, current song, requested item and native offset")
        playQueued(row)
        suite.expect(commands.count == 1, "a row action already waiting for its reply blocks another")
        visible = false
        pending = false
        playQueued(row)
        suite.expect(commands.count == 1, "a hidden queue cannot enqueue another row action")
        visible = true
        defaults.set(false, forKey: DefaultsKey.notchQueueEnabled)
        playQueued(row)
        suite.expect(commands.count == 1, "a queue turned off in Settings cannot enqueue a row action")
        defaults.set(true, forKey: DefaultsKey.notchQueueEnabled)
        commands.removeAll()
        upcoming = NotchQueueSnapshot(requestID: selected.requestID, currentIdentifier: "current", pid: 42,
            items: [NotchQueueItem(id: "next", offset: 2, title: "Next", artist: "", duration: 0, artwork: Data([1]))],
            canPlay: true)
        playQueued(row)
        suite.expect(commands == [.queuePlay(selected)], "a row drawn before its cover arrived still plays")
    }

    private static func queueHold(_ suite: TestSuite) {
        var decodes = 0
        var queue = NotchUpcomingQueue<Data> { data in
            decodes += 1
            return data
        }
        let request = UUID()
        let cover = Data([1, 2, 3])
        func reply(anchor: String, pid: Int32 = 42, rows: [[String: Any]]) -> [String: Any] {
            ["queueRequest": request.uuidString, "queueAvailable": true, "currentIdentifier": anchor,
             "pid": pid, "queueCanPlay": true, "queueItems": rows]
        }
        let covered = reply(anchor: "a", rows: [["id": "b", "offset": 1, "title": "B", "artworkBase64": cover.base64EncodedString()],
                                                ["id": "c", "offset": 2, "title": "C"]])
        queue.receive(covered, request: request, playback: playback("a"), enabled: true)
        suite.expect(queue.snapshot?.items.map(\.id) == ["b", "c"] && queue.artwork == ["b": cover]
               && !queue.isHeld(for: playback("a")), "a decoded queue publishes the covers its rows carry")
        let shown = queue.snapshot
        queue.receive(covered, request: request, playback: playback("b"), enabled: true)
        suite.expect(queue.snapshot == shown && queue.artwork == ["b": cover],
               "a song change keeps the rows and covers on screen until the new song's queue arrives")
        suite.expect(queue.isHeld(for: playback("b")) && queue.rows(for: playback("b")).map(\.id) == ["c"],
               "held rows leave out the song now playing and refuse row actions")
        suite.expect(decodes == 1, "keeping the rows on screen decodes no cover again")
        queue.receive(reply(anchor: "b", rows: [["id": "c", "offset": 1, "title": "C"]]),
                      request: request, playback: playback("b"), enabled: true)
        suite.expect(queue.snapshot?.currentIdentifier == "b" && !queue.isHeld(for: playback("b"))
               && queue.rows(for: playback("b")).map(\.id) == ["c"], "the new song's queue replaces the held rows")
        var anonymous = playback("b")
        anonymous.itemIdentifier = nil
        var old = covered
        old["queueRequest"] = UUID().uuidString
        let endings: [(NotchPlayback, [String: Any])] = [
            (playback("b"), ["queueRequest": request.uuidString, "queueAvailable": false]),
            (playback("b"), reply(anchor: "a", pid: 43, rows: [])),
            (playback("b"), old),
            (anonymous, covered)
        ]
        for (current, ending) in endings {
            queue.receive(covered, request: request, playback: playback("a"), enabled: true)
            queue.receive(ending, request: request, playback: current, enabled: true)
            suite.expect(queue.snapshot == nil && queue.artwork.isEmpty,
                   "an unavailable queue, another player, an old request or an unidentified song clears the rows")
        }
        let empties: [(name: String, request: UUID?, playback: NotchPlayback?, enabled: Bool)] = [
            ("a queue turned off", request, playback("a"), false),
            ("no request", nil, playback("a"), true),
            ("nothing playing", request, nil, true),
        ]
        for (name, ask, current, enabled) in empties {
            queue.receive(covered, request: request, playback: playback("a"), enabled: true)
            queue.receive(covered, request: ask, playback: current, enabled: enabled)
            suite.expect(queue.snapshot == nil && queue.artwork.isEmpty && !queue.isHeld(for: current)
                         && queue.rows(for: current).isEmpty, "\(name) shows no rows")
        }
    }

    private static func framing(_ suite: TestSuite) {
        let request = UUID()
        let large = NotchQueueSelection(requestID: request, pid: 42,
            currentIdentifier: String(repeating: "c", count: 512), itemIdentifier: String(repeating: "n", count: 512), offset: 20)
        let context = NotchPlaybackContext(pid: 42, revision: UUID())
        let commands = [NotchPlaybackCommand.queue(request), .queuePlay(large), .queueStop, .previous, .next]
            .map { NotchPlaybackRequest(command: $0, context: context) }
        let batch = Data(commands.compactMap(\.message).map { $0 + "\n" }.joined().utf8)
        suite.expect(batch.count > 1024, "the framing fixture exceeds the old combined-buffer limit")
        var framer = NotchPlaybackCommandFramer()
        suite.expect(framer.append(batch).compactMap { $0 } == commands, "one pipe delivery preserves every complete command, including queue-stop")
        var split = NotchPlaybackCommandFramer()
        var decoded: [NotchPlaybackRequest] = []
        for byte in batch { decoded += split.append(Data([byte])).compactMap { $0 } }
        suite.expect(decoded == commands, "commands survive arbitrary byte boundaries")
        var bad = NotchPlaybackCommandFramer()
        let next = NotchPlaybackRequest(command: .next, context: context)
        let oversized = Data((String(repeating: "x", count: NotchPlaybackCommand.maximumMessageBytes + 1) + "\nqueue-stop\n" + next.message! + "\n").utf8)
        let recovered = bad.append(oversized)
        suite.expect(recovered.count == 3 && recovered[0] == nil && recovered[1]?.command == .queueStop && recovered[2] == next,
               "an oversized frame cannot swallow the following cancellation or valid command")
        var unterminated = NotchPlaybackCommandFramer()
        suite.expect(unterminated.append(Data(String(repeating: "x", count: 100_000).utf8)).isEmpty,
               "a long unterminated frame is discarded without retaining the growing input")
        suite.expect(unterminated.append(Data("\nqueue-stop\n".utf8)).compactMap { $0?.command } == [.queueStop],
               "the framer resumes at the next newline after a rejected partial frame")
        for message in ["toggle", "next", "previous", "seek 75", "play 0 \(context.revision) next",
                        "play 42 invalid next", "play 42 \(context.revision) queue-stop"] {
            suite.expect(NotchPlaybackRequest(message: message) == nil, "unbound or malformed playback context cannot reach native dispatch")
        }
    }

    private static func pendingCommands(_ suite: TestSuite) {
        let scheduler = Scheduler()
        let writer = NotchMusicCommandWriter(schedule: scheduler.enqueue)
        var written: [NotchPlaybackCommand] = []
        var failures = 0
        func write(_ data: Data) throws {
            let message = String(data: data, encoding: .utf8)!.trimmingCharacters(in: .newlines)
            if let request = NotchPlaybackRequest(message: message) { written.append(request.command) }
        }
        let first = UUID(), second = UUID()
        writer.start(); writer.setQueueRequest(first)
        suite.expect(writer.submit(.queue(first), write: write, failed: { failures += 1 }), "an active query is accepted for scheduling")
        writer.setQueueRequest(nil)
        _ = writer.submit(.queueStop, write: write, failed: { failures += 1 })
        scheduler.drain()
        suite.expect(written == [.queueStop] && failures == 0, "closing the queue cancels an unsent query while preserving its native stop")
        written.removeAll()
        writer.setQueueRequest(first)
        _ = writer.submit(.queuePlay(selection(first)), write: write, failed: { failures += 1 })
        writer.setQueueRequest(second)
        _ = writer.submit(.queue(second), write: write, failed: { failures += 1 })
        scheduler.drain()
        suite.expect(written == [.queue(second)], "replacing the queue request cancels an unsent play from the previous surface")
        written.removeAll()
        let context = NotchPlaybackContext(pid: 42, revision: UUID())
        _ = writer.submit(.previous, context: context, write: write, failed: { failures += 1 })
        writer.stop(); writer.start()
        scheduler.drain()
        suite.expect(written.isEmpty, "a new adapter process cannot inherit an old pending transport command")
        writer.setQueueRequest(first)
        suite.expect(!writer.submit(.queuePlay(selection(first, item: "bad\0item")), write: write, failed: { failures += 1 })
               && scheduler.work.isEmpty, "invalid identifiers are rejected synchronously so the UI can release its pending state")
        _ = writer.submit(.queue(first), write: { _ in throw NSError(domain: "Test", code: 1) }, failed: { failures += 1 })
        scheduler.drain()
        suite.expect(failures == 1, "an actual write failure is delivered to its still-active request")
        _ = writer.submit(.queue(first), write: { _ in writer.stop(); throw NSError(domain: "Test", code: 1) }, failed: { failures += 1 })
        scheduler.drain()
        suite.expect(failures == 1, "a retired request's write failure cannot alter its replacement")
        suite.expect(!writer.submit(.next, context: context, write: write, failed: { failures += 1 }), "stopped transports reject new commands immediately")
    }

    private static func controlLifecycle(_ suite: TestSuite) {
        typealias Adapter = NotchPlaybackRoutingContract
        defer {
            Adapter.metadata = [:]
            Adapter.publish(nil)
        }
        let harness = NotchMusicCommandContract.Harness()
        let service = harness.service
        let nativePath = NSObject()
        let native = Adapter.Target(pid: 42, path: nativePath)
        var metadata: [String: Any] = ["kMRMediaRemoteNowPlayingInfoTitle": "same-title",
                                      "kMRMediaRemoteNowPlayingInfoContentItemIdentifier": "A"]
        Adapter.metadata[ObjectIdentifier(nativePath)] = metadata
        let context = Adapter.publish(native, info: metadata)!
        var current = playback("same-title")
        current.commandContext = context
        current.canSendCommandsDirectly = true
        service.start()
        harness.feed(current)
        service.seek(to: 75, in: service.playback!.track, context: context)
        // The shared playback helper disables seeking; explicitly enable it for this control fixture.
        suite.expect(harness.requests().isEmpty, "read-only native playback cannot enqueue a seek")
        current = NotchPlayback(track: current.track, isPlaying: true, elapsed: 0, duration: 180, rate: 1,
                                sampledAt: Date(), canSeek: true, itemIdentifier: "A", commandContext: context,
                                canSendCommandsDirectly: true)
        harness.feed(current)
        service.seek(to: 75, in: service.playback!.track, context: context)
        suite.expect(harness.requests().last == NotchPlaybackRequest(command: .seek(75), context: context),
               "the production seek and writer preserve the gesture's process and recording revision")
        service.seek(to: 500, in: service.playback!.track, context: context)
        suite.expect(harness.requests().last == NotchPlaybackRequest(command: .seek(180), context: context),
               "a seek past the end lands at the end")
        harness.links.last?.running = false
        suite.expect(!service.send(.toggle), "a command to an adapter that already exited is refused")
        harness.links.last?.running = true
        Adapter.command = nil
        Adapter.sendPlaybackCommand(NotchPlaybackRequest(command: .seek(75), context: context))
        suite.expect(Adapter.command == 24 && Adapter.destination === nativePath,
               "a stable gesture traverses the real writer, decoder, validation and native dispatch")
        var changed = current
        metadata["kMRMediaRemoteNowPlayingInfoContentItemIdentifier"] = "B"
        Adapter.metadata[ObjectIdentifier(nativePath)] = metadata
        changed.commandContext = Adapter.publish(native, info: metadata)
        Adapter.command = nil
        Adapter.sendPlaybackCommand(NotchPlaybackRequest(command: .seek(75), context: context))
        suite.expect(Adapter.command == nil,
               "a written gesture from the old recording is rejected when native playback changes before dispatch")
        let shownTrack = service.playback!.track
        harness.feed(changed)
        let before = harness.requests().count
        service.seek(to: 90, in: shownTrack, context: context)
        suite.expect(!service.send(.toggle, context: context) && !service.send(.next, context: nil),
               "an obsolete rendered control or missing revision cannot borrow the current recording")
        suite.expect(harness.requests().count == before,
               "identical visible metadata cannot retarget an earlier gesture after the recording revision changes")
        _ = service.send(.previous)
        suite.expect(harness.requests().last?.context == changed.commandContext,
               "the gesture route captures its current playback context at submission")
        harness.links.last?.failsWrites = true
        suite.expect(service.send(.previous) && !service.commandFailed, "a command is accepted before it is written")
        _ = harness.requests()
        harness.main.drain()
        suite.expect(service.commandFailed, "a write the adapter cannot take reports the command failed")
        harness.links.last?.failsWrites = false
        _ = service.send(.next)
        let link = harness.links.last!
        service.stop()
        suite.expect(harness.requests(link).count == before + 1,
               "closing the last music consumer cancels its still-unwritten controls")

        suite.expect(!service.awaitingPlayback, "a stopped subscription is not waiting for a reading")
        service.start()
        let launches = harness.links.count
        suite.expect(service.awaitingPlayback, "a fresh subscription waits for the adapter's first reply before reporting nothing playing")
        harness.end()
        for _ in 0..<100 { service.start() }
        harness.advance(0.5)
        suite.expect(harness.links.count == launches && harness.pendingDelays == 1,
               "preference updates cannot bypass a pending recovery or launch extra helpers")
        suite.expect(service.awaitingPlayback, "a pending recovery keeps the first reading outstanding")
        harness.advance(10)
        suite.expect(harness.links.count == launches + 1, "unexpected termination receives one delayed recovery while music is wanted")
        harness.feed(playback("stale"), from: harness.links[harness.links.count - 2])
        suite.expect(service.playback == nil && service.awaitingPlayback,
                     "a reading from an adapter that was replaced is not shown")
        harness.end()
        harness.advance(10)
        harness.end()
        for _ in 0..<100 { service.start() }
        suite.expect(harness.links.count == launches + 2 && harness.pendingDelays == 0,
               "persistent failure stops after two retries even if preferences continue changing")
        suite.expect(!service.awaitingPlayback, "giving up on the adapter ends the wait so the empty state can show")
        service.stop()
        service.start()
        harness.end()
        let cancelledLaunches = harness.links.count
        service.stop()
        harness.advance(10)
        suite.expect(harness.links.count == cancelledLaunches && !service.awaitingPlayback,
               "disabling, hiding the last consumer or suspending cancels delayed recovery")
        service.start()
        harness.end()
        service.stop()
        service.start()
        let replacementLaunches = harness.links.count
        harness.advance(10)
        suite.expect(harness.links.count == replacementLaunches,
               "a delayed recovery from an ended subscription cannot launch inside its replacement")
        // Two quick exits spend the budget. An adapter that then runs for over
        // a minute before it ends is not crash looping.
        harness.end()
        harness.advance(10)
        harness.end()
        harness.advance(10)
        harness.machine.now += 61
        let budgetLaunches = harness.links.count
        harness.end()
        harness.advance(10)
        suite.expect(harness.links.count == budgetLaunches + 1,
               "an adapter that ran for over a minute gets a fresh restart budget")
        harness.machine.now += 30
        harness.end()
        harness.advance(10)
        harness.machine.now += 30
        harness.end()
        suite.expect(harness.pendingDelays == 0 && !service.awaitingPlayback,
               "exits within a minute after that still stop after two retries")
        harness.machine.now += 61
        harness.end()
        suite.expect(harness.pendingDelays == 0, "an adapter that is gone already cannot end twice")

        for raw: Any in [true, 0, -1, 42.5, Double(Int32.max) + 1] {
            suite.expect(NotchPlaybackContext(reply: ["pid": raw, "playbackRevision": UUID().uuidString]) == nil,
                   "metadata cannot bind controls to malformed process identities")
        }
        let raw: [String: Any] = ["pid": 42, "playbackRevision": context.revision.uuidString]
        suite.expect(NotchPlaybackContext(reply: raw) == context,
               "the recording revision survives the adapter reply without depending on UUID letter case")
        suite.expect(harness.machine.lyrics.contains("same-title"), "each reading reaches the lyrics")
    }
}
