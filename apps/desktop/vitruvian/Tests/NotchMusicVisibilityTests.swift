// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The module's island (`NotchIslandFixture`) starts and stops its playback
/// reader as it presents. The services keep their last playback after every
/// stop, so cached music cannot make the assertions pass merely because a
/// test double cleared it.
enum NotchMusicVisibilityTests {
    /// A display with the camera housing a physical notch has, or none.
    private static func display(physical: Bool) -> NotchDisplayInfo {
        NotchDisplayInfo(id: NotchIslandFixture.display.id, frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                         visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 924),
                         safeAreaTop: physical ? 32 : 0, cameraWidth: physical ? 180 : 0,
                         backingScale: 2, isBuiltIn: physical, hasMenuBar: true)
    }

    private static func playback(_ playing: Bool) -> NotchPlayback {
        NotchPlayback(track: RadialNowPlayingSnapshot(title: "Song", artist: "Artist", album: nil, artworkData: nil,
                                                      appBundleIdentifier: "org.example.player", appPID: 42),
                      isPlaying: playing, elapsed: 0, duration: 200, rate: 1, sampledAt: Date(), canSeek: false)
    }

    private static func captureOptions() -> ScreenCaptureSelectionOptions {
        ScreenCaptureSelectionOptions(availableTools: [.screenshot], selectedTool: .screenshot, showsCaptureMenu: false)
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vitruviansoftware.vitruvian.tests.notch-music-visibility"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        var islands: [NotchIslandFixture] = []
        defer {
            islands.forEach { $0.island.stop() }
            defaults.removePersistentDomain(forName: domain)
        }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for feature in AppFeature.allCases { defaults.set(true, forKey: feature.availabilityKey) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(false, forKey: DefaultsKey.notchTrackChange)
        for event in [NotchEvent.capture, .accessory, .download] { defaults.set(true, forKey: event.preferenceKey) }
        defaults.set(true, forKey: DefaultsKey.notchKeepAwakeActivity)
        defaults.set(true, forKey: DefaultsKey.notchAccessoriesEnabled)
        /// A started island on one display, whose menus leave it room.
        func island(physical: Bool = true, playing: Bool? = nil) -> NotchIslandFixture {
            let fixture = NotchIslandFixture(defaults: defaults)
            fixture.displays = [display(physical: physical)]
            fixture.menuRoom = 100
            if let playing { fixture.services.playback = playback(playing) }
            fixture.start()
            islands.append(fixture)
            return fixture
        }

        let persistent = island()
        var persistentCloses = 0
        let persistentID = UUID()
        let persistentShown = persistent.island.presentCapture(
            id: persistentID, content: AnyView(EmptyView()), height: 120, takeFocus: false, closeOnCollapse: true,
            fallback: {}, close: { persistentCloses += 1 }, hover: { _ in })
        persistent.island.collapse()
        persistent.island.collapse()
        suite.expect(persistentShown && persistentCloses == 1 && persistent.island.captureContent == nil
                     && !persistent.island.isCaptureVisible(id: persistentID),
                     "collapsing a persistent capture closes and detaches it exactly once")

        let timed = island()
        var timedCloses = 0
        let timedShown = timed.island.presentCapture(
            id: UUID(), content: AnyView(EmptyView()), height: 120, takeFocus: false, closeOnCollapse: false,
            fallback: {}, close: { timedCloses += 1 }, hover: { _ in })
        timed.island.collapse()
        suite.expect(timedShown && timedCloses == 0 && timed.island.captureContent != nil,
                     "collapsing a timed capture leaves its timer-owned close path intact")

        let hidesInFullscreen = defaults.object(forKey: DefaultsKey.notchHideInFullscreen)
        defer { defaults.set(hidesInFullscreen, forKey: DefaultsKey.notchHideInFullscreen) }
        for physical in [true, false] {
            defaults.set(NotchIdleContent.music.rawValue, forKey: DefaultsKey.notchIdleContent)
            defaults.set(true, forKey: DefaultsKey.notchShowPlayingMusic)
            let fixture = island(physical: physical, playing: true)
            let service = fixture.island
            let reader = fixture.services
            let closed = service.geometry.restingSize(showsContent: false)
            suite.expect(reader.musicRunning && service.compactActivity == .music && service.surfaceSize.width > closed.width,
                   "enabled playback first appears beside both physical and simulated cameras")

            defaults.set(true, forKey: DefaultsKey.notchHideInFullscreen)
            fixture.fullscreen = [NotchIslandFixture.display.id]
            service.syncWithPreferences()
            suite.expect(service.hiddenInFullscreen && !reader.musicRunning && service.surfaceSize == closed,
                         "fullscreen keeps a black cutout and stops the automatic playback reader")
            defaults.set(true, forKey: DefaultsKey.notchOutlineEnabled)
            service.syncWithPreferences()
            suite.expect(service.geometry.outline == true && service.surfaceSize == closed,
                         "fullscreen draws no outline, so its cutout keeps to the camera without the outline's room")
            defaults.set(false, forKey: DefaultsKey.notchOutlineEnabled)
            service.syncWithPreferences()
            // A copy on another display, which is not in full screen. The
            // copies appear as the island presents, and its next sync reads them.
            fixture.displays.append(NotchIslandFixture.secondDisplay)
            defaults.set(NotchDisplay.all.rawValue, forKey: DefaultsKey.notchDisplay)
            service.syncWithPreferences()
            service.syncWithPreferences()
            suite.expect(!fixture.mirrors.isEmpty && reader.musicRunning,
                         "copies on other displays keep the song while the island rests in fullscreen")
            defaults.set(NotchDisplay.automatic.rawValue, forKey: DefaultsKey.notchDisplay)
            service.syncWithPreferences()
            service.syncWithPreferences()
            fixture.displays.removeLast()
            suite.expect(!reader.musicRunning, "without copies fullscreen stops the reader again")
            service.open(.music)
            suite.expect(reader.musicRunning && service.surfaceSize == service.expandedSize,
                         "manually opening Music in fullscreen starts its reader")
            service.collapse()
            suite.expect(!reader.musicRunning && service.surfaceSize == closed,
                         "closing Music in fullscreen stops its reader and restores the black cutout")
            fixture.fullscreen = []
            service.syncWithPreferences()
            suite.expect(reader.musicRunning, "leaving fullscreen restarts the playback reader when music is enabled")

            defaults.set(NotchIdleContent.none.rawValue, forKey: DefaultsKey.notchIdleContent)
            service.syncWithPreferences()
            suite.expect(!reader.musicRunning && service.compactActivity == nil && service.idleContent == .none
                   && service.surfaceSize == closed,
                   "selecting Nothing retracts already visible music and stops its reader with cached playback still present")
            let reopened = island(physical: physical, playing: true)
            suite.expect(!reopened.services.musicRunning && reopened.island.compactActivity == nil
                   && reopened.island.surfaceSize == closed,
                   "a fresh island honors saved Nothing while playback metadata is still available")
            defaults.set(true, forKey: DefaultsKey.notchTrackChange)
            service.syncWithPreferences()
            suite.expect(reader.musicRunning && service.compactActivity == nil && service.surfaceSize == closed,
                   "announcing new songs keeps the reader on with Nothing at rest, without a music strip")
            defaults.set(false, forKey: DefaultsKey.notchTrackChange)
            service.syncWithPreferences()
            suite.expect(!reader.musicRunning, "turning new song notices off stops that reader again")
            for automatic in [false, true] {
                defaults.set(automatic, forKey: DefaultsKey.notchShowPlayingMusic)
                for module in [NotchModule.music, .controls] {
                    service.open(module)
                    suite.expect(reader.musicRunning && service.surfaceSize == service.expandedSize,
                           "Nothing still starts the music reader when its explicit controls open")
                    for playing in [true, false, true] {
                        reader.playback = playback(playing)
                        service.syncWithPreferences()
                        suite.expect(reader.musicRunning && service.compactActivity == nil,
                               "playback updates keep manually opened controls usable without enabling automatic music")
                    }
                    service.collapse()
                    suite.expect(!reader.musicRunning && !service.expanded && service.surfaceSize == closed,
                           "closing manually opened controls stops the reader and never leaves a music strip behind")
                }
            }

            defaults.set(NotchIdleContent.music.rawValue, forKey: DefaultsKey.notchIdleContent)
            defaults.set(false, forKey: DefaultsKey.notchShowPlayingMusic)
            service.syncWithPreferences()
            suite.expect(!reader.musicRunning && service.idleContent == .none && service.compactActivity == nil
                   && service.surfaceSize == closed,
                   "disabled automatic music stops the reader even when resting content is Music")
            defaults.set(true, forKey: DefaultsKey.notchShowPlayingMusic)
            for playing in [true, false, true] {
                reader.playback = playback(playing)
                service.syncWithPreferences()
                suite.expect(reader.musicRunning && (service.compactActivity == .music) == playing
                       && (service.surfaceSize == closed) == !playing,
                       "re-enabling music detects resume while paused playback occupies no wings")
            }
            // A song that starts while none is on the strip waits for its notice.
            defaults.set(true, forKey: DefaultsKey.notchTrackChange)
            reader.playback = playback(false)
            service.syncWithPreferences()
            reader.playback = playback(true)
            fixture.events.trackChanges.send()
            suite.expect(service.compactActivity == nil && service.idleContent == .none && service.surfaceSize == closed,
                   "a new song waiting for its notice leaves the closed island at rest, cover included")
            fixture.runScheduled()
            suite.expect(service.compactActivity == .music, "once released, the playing song takes the strip")
            defaults.set(false, forKey: DefaultsKey.notchTrackChange)
            defaults.set(true, forKey: DefaultsKey.notchOpenOnHover)
            defaults.set(true, forKey: DefaultsKey.notchHideUntilHover)
            service.syncWithPreferences()
            // Hidden until hover: the island takes feedback but shows none at rest.
            suite.expect(!reader.musicRunning && service.acceptsSystemFeedback && !service.showsSystemFeedback,
                   "hidden mode stops the resting music reader even with cached playing metadata")
            service.open(.music)
            suite.expect(reader.musicRunning, "revealing hidden music controls starts their reader on demand")
            service.collapse()
            suite.expect(!reader.musicRunning && service.acceptsSystemFeedback && !service.showsSystemFeedback,
                   "closing hidden music controls releases their reader again")
            service.presentCaptureControls(captureOptions(), cancel: {})
            suite.expect(reader.musicRunning, "visible capture controls can retain enabled resting music")
            service.endCaptureControls()
            suite.expect(service.captureControls == nil && !service.showsSystemFeedback && !reader.musicRunning,
                   "canceling capture returns hidden mode to rest without retaining the music reader")
            service.endCaptureControls()
            suite.expect(!reader.musicRunning, "a repeated capture cleanup cannot restart hidden music")
            defaults.set(false, forKey: DefaultsKey.notchHideUntilHover)
            service.syncWithPreferences()
            suite.expect(reader.musicRunning, "returning to a visible mode resumes the resting music reader")
            service.presentCaptureControls(captureOptions(), cancel: {})
            service.endCaptureControls()
            suite.expect(reader.musicRunning, "ending capture in a visible mode preserves enabled resting music")
            defaults.set(NotchIdleContent.battery.rawValue, forKey: DefaultsKey.notchIdleContent)
            defaults.set(false, forKey: DefaultsKey.notchShowPlayingMusic)
            service.syncWithPreferences()
            suite.expect(!reader.musicRunning && service.idleContent == .battery && service.compactActivity == nil
                   && service.surfaceSize == service.geometry.restingSize(showsContent: true),
                   "hiding music preserves the chosen battery indicator during active playback")
            fixture.hasBattery = false
            service.syncWithPreferences()
            suite.expect(service.idleContent == .none && service.compactActivity == nil && service.surfaceSize == closed,
                   "a Mac without a battery rests empty instead of showing a battery without its charge")
            defaults.set(true, forKey: DefaultsKey.notchShowPlayingMusic)
            service.syncWithPreferences()
            suite.expect(reader.musicRunning && service.compactActivity == .music,
                   "a saved battery choice keeps showing playing music on a Mac without a battery")
            defaults.set(false, forKey: DefaultsKey.notchHideInFullscreen)
        }

        defaults.set(NotchIdleContent.none.rawValue, forKey: DefaultsKey.notchIdleContent)
        let fixture = island(playing: true)
        let service = fixture.island
        let reader = fixture.services
        for surface in ["sections", "appPanel", "unrelated", "hiddenModule", "hiddenControl"] {
            defaults.set(surface == "hiddenModule" ? "music" : "", forKey: DefaultsKey.notchHiddenModules)
            defaults.set(surface == "hiddenControl" ? "music" : "", forKey: DefaultsKey.notchHiddenControls)
            service.syncWithPreferences()
            switch surface {
            case "sections": service.open(.music, sections: true)
            case "appPanel": service.open(.music, appPanel: true)
            case "unrelated": service.open(.files)
            case "hiddenModule": service.open(.music)
            default: service.open(.controls)
            }
            suite.expect(!reader.musicRunning, "\(surface) cannot retain an invisible on-demand music reader")
        }
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        defaults.set("", forKey: DefaultsKey.notchHiddenControls)
        service.syncWithPreferences()
        service.collapse()
        reader.timerSession = NotchTimerSession(anchor: reader.timerNow + 300)
        reader.downloads = [NotchDownloadItem(id: "archive", url: URL(fileURLWithPath: "/tmp/archive.zip"),
                                              name: "archive.zip", receivedBytes: 512, fraction: 0.5, completed: false)]
        suite.expect(service.compactActivity == .timer, "Nothing for resting music preserves a running timer")
        service.selectCompactActivity(.timer)
        suite.expect(service.compactCompanions(of: .timer).contains(.downloads) && service.compactCompanion == nil,
                     "the production Timer selection does not borrow the active download wing")
        service.selectCompactCombination(NotchActivityCombination(primary: .timer, companion: .downloads))
        suite.expect(service.compactCompanion == .downloads,
                     "the production strip shows only the explicitly selected companion")
        service.selectCompactActivity(.timer)
        suite.expect(service.compactCompanion == nil,
                     "choosing Timer again removes the explicit pair in the production strip")
        reader.timerSession = NotchTimerSession()
        suite.expect(service.compactActivity == .downloads, "Nothing for resting music preserves active downloads")
        let notice = NotchNotice(event: .accessory, title: "Wireless Headphones", detail: "Connected", symbol: "headphones")
        let noticeShown = service.show(notice)
        suite.expect(noticeShown && service.surfaceSize == service.geometry.noticeSize(wingWidth: notice.preferredWingWidth)
               && service.surfaceSize.width > service.geometry.notice.width,
               "a device notice widens the actual presentation beyond the compact level indicator")
        fixture.runScheduled()
        suite.expect(service.notice == nil && service.surfaceSize == service.compactActivityGeometry.compactActivitySize,
               "dismissing a device notice restores the underlying activity's width")
        reader.keepAwakeActive = true
        suite.expect(service.compactActivity == .downloads, "a download outranks a running Keep Awake session")
        reader.downloads = []
        // The timer's wings, rebuilt from the room they took beside the camera.
        let keepAwake = service.compactActivityGeometry
        suite.expect(service.compactActivity == .keepAwake
                     && keepAwake == service.geometry.compactTimerGeometry(showsDownloads: false,
                                                                          wing: keepAwake.compactSideRoom ?? 0)
                     && service.surfaceSize == keepAwake.compactActivitySize,
                     "a running Keep Awake session takes the timer's wings in the closed island")
        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956), safeAreaTop: 32,
                                     cameraWidth: 180, menuBarHeight: 32, compactSideRoom: 100)
        suite.expect(geometry.compactCalendarGeometry(wing: 66, paired: true).compactActivityWingWidth == 66
                     && geometry.compactCalendarGeometry(wing: 66).compactActivityWingWidth == 72,
                     "an event beside music takes the wings its pair needs, and alone keeps room for its title")
    }
}
