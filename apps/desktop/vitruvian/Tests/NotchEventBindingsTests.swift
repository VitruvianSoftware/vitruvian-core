// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import Combine
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Drives the module's own `NotchEventBindings` through subjects of its own,
/// never the app's services, and records what reaches the island.
enum NotchEventBindingsTests {
    final class Recorder {
        var resizes = 0, remembered: [String] = [], endings = 0, songs = 0, trackChanges = 0
        var tools = 0, fanCards = 0, downloads: [String] = [], agentEvents = 0, clipboard = 0
        var notifications: [UUID] = [], hidden: [UUID] = [], replacesBanner = true
        var arrival: ((NotchDownloadItem) -> Void)?
        var asked: [String] = []
    }

    static func run(_ suite: TestSuite) {
        let recorder = Recorder()
        let timer = PassthroughSubject<Void, Never>(), watch = PassthroughSubject<Void, Never>()
        let music = PassthroughSubject<(NotchPlayback?, NSImage?, NotchArtworkTint?), Never>()
        let trackEnds = PassthroughSubject<Void, Never>(), musicActivity = PassthroughSubject<Void, Never>()
        let songTitles = PassthroughSubject<String?, Never>(), heldTitles = PassthroughSubject<String?, Never>()
        let trackChanges = PassthroughSubject<Void, Never>(), tools = PassthroughSubject<Void, Never>()
        let fanCard = PassthroughSubject<Void, Never>(), downloads = PassthroughSubject<Void, Never>()
        let agentActivity = PassthroughSubject<Void, Never>(), calendar = PassthroughSubject<Void, Never>()
        let keepAwake = PassthroughSubject<Void, Never>()
        let agentEvents = PassthroughSubject<AgentUsageEvent, Never>()
        let notifications = PassthroughSubject<NotchSystemNotification, Never>()
        let clipboard = PassthroughSubject<Void, Never>()
        func source<P: Publisher>(_ name: String, _ subject: P) -> () -> AnyPublisher<P.Output, Never>
        where P.Failure == Never {
            { recorder.asked.append(name); return subject.eraseToAnyPublisher() }
        }
        let sources = NotchEventBindings.Sources(
            timer: source("timer", timer), watch: source("watch", watch), music: source("music", music),
            trackEnds: source("trackEnds", trackEnds), musicActivity: source("musicActivity", musicActivity),
            songTitles: source("songTitles", songTitles), trackChanges: source("trackChanges", trackChanges),
            tools: source("tools", tools), fanCard: source("fanCard", fanCard),
            downloads: source("downloads", downloads), setDownloadArrival: { recorder.arrival = $0 },
            agentActivity: source("agentActivity", agentActivity), calendar: source("calendar", calendar),
            keepAwake: source("keepAwake", keepAwake), agentEvents: source("agentEvents", agentEvents),
            systemNotifications: source("systemNotifications", notifications),
            hideNativeNotification: { recorder.hidden.append($0) },
            clipboardCaptures: source("clipboard", clipboard))
        let bindings = NotchEventBindings(sources: sources, island: NotchEventBindings.Island(
            resize: { recorder.resizes += 1 },
            rememberMusic: { playback, _, _ in recorder.remembered.append(playback.track.title ?? "") },
            holdEndingTrack: { recorder.endings += 1 },
            nameSong: { recorder.songs += 1 },
            trackChanged: { recorder.trackChanges += 1 },
            toolsChanged: { recorder.tools += 1 },
            fanCardChanged: { recorder.fanCards += 1 },
            downloadArrived: { recorder.downloads.append($0.name) },
            agentEvent: { _ in recorder.agentEvents += 1 },
            systemNotification: { recorder.notifications.append($0.id); return recorder.replacesBanner },
            clipboardCaptured: { recorder.clipboard += 1 }))
        func settings(_ modules: [NotchModule], routes: Set<NotchEvent> = [], keepAwake: Bool = false,
                      fanControl: Bool = false) -> NotchEventBindings.Settings {
            NotchEventBindings.Settings(modules: modules, routes: { routes.contains($0) },
                                        keepAwakeActivity: keepAwake, fanControl: fanControl)
        }
        /// Lets the song titles, which hop to the main queue, arrive.
        func drainMain() {
            // Set by the main queue and read on the main thread.
            nonisolated(unsafe) var drained = false
            DispatchQueue.main.async { drained = true }
            let deadline = Date().addingTimeInterval(2)
            while !drained, Date() < deadline { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        }

        bindings.bind(settings([.timer]), heldSongTitles: heldTitles.eraseToAnyPublisher())
        suite.expect(recorder.asked == ["timer"], "only the sources of modules that are on are asked for")
        timer.send()
        watch.send()
        calendar.send()
        suite.expect(recorder.resizes == 1, "a bound module's change resizes the island, and no other does")

        recorder.asked.removeAll()
        bindings.bind(settings([.music, .watch, .agents, .calendar, .tools],
                               routes: [.track, .download, .agents, .systemNotification, .clipboard],
                               keepAwake: true),
                      heldSongTitles: heldTitles.eraseToAnyPublisher())
        suite.expect(!recorder.asked.contains("timer") && !recorder.asked.contains("fanCard")
                        && recorder.asked.contains("music") && recorder.asked.contains("keepAwake"),
                     "binding again asks for the new set: \(recorder.asked)")
        let resizesBefore = recorder.resizes
        timer.send()
        suite.expect(recorder.resizes == resizesBefore, "binding again drops the subscriptions it replaces")
        for subject in [watch, musicActivity, downloads, agentActivity, calendar, keepAwake] { subject.send() }
        suite.expect(recorder.resizes == resizesBefore + 6, "each bound source resizes the island once")

        func song(_ title: String) -> NotchPlayback {
            NotchPlayback(track: RadialNowPlayingSnapshot(title: title, artist: "Artist", album: nil, artworkData: nil,
                                                          appBundleIdentifier: "org.example.player", appPID: 42),
                          isPlaying: true, elapsed: 0, duration: 200, rate: 1, sampledAt: Date(), canSeek: false)
        }
        music.send((song("First"), nil, nil))
        music.send((nil, nil, nil))
        suite.expect(recorder.remembered == ["First"], "a song is kept while it plays, and nothing once playback is gone")
        trackEnds.send()
        trackChanges.send()
        tools.send()
        suite.expect(recorder.endings == 1 && recorder.trackChanges == 1 && recorder.tools == 1,
                     "the music hooks and the tools page reach the island")

        songTitles.send("First")
        songTitles.send("First")
        heldTitles.send("Held")
        drainMain()
        suite.expect(recorder.songs == 2, "each new title, playing or held, is named once")

        recorder.arrival?(NotchDownloadItem(id: "file", url: URL(fileURLWithPath: "/tmp/file.zip"), name: "file.zip",
                                           receivedBytes: nil, fraction: 1, completed: true, active: false))
        suite.expect(recorder.downloads == ["file.zip"], "a download's arrival reaches the island")
        agentEvents.send(.budgetReached(spent: 1, budget: 1))
        clipboard.send()
        suite.expect(recorder.agentEvents == 1 && recorder.clipboard == 1, "agent events and copies reach the island")

        let content = NotchNotificationContent(app: "Mail", title: "Hello", subtitle: "", body: "World")
        let shown = NotchSystemNotification(id: UUID(), content: content, received: Date(), canOpen: false)
        notifications.send(shown)
        recorder.replacesBanner = false
        let kept = NotchSystemNotification(id: UUID(), content: content, received: Date(), canOpen: false)
        notifications.send(kept)
        suite.expect(recorder.notifications == [shown.id, kept.id] && recorder.hidden == [shown.id],
                     "the system's banner hides only for a notification the island stands in for")

        bindings.unbind()
        let after = (recorder.resizes, recorder.clipboard)
        watch.send()
        clipboard.send()
        suite.expect(recorder.resizes == after.0 && recorder.clipboard == after.1, "unbound, nothing reaches the island")
    }
}
