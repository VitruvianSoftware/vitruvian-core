// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The module's island (`NotchIslandFixture`) presents through a recording
/// window host, without showing UI or starting the island's hardware
/// consumers. Mode changes model AppStorage: they alter computed geometry
/// without publishing a service property.
enum NotchPresentationRefreshContract {
    static var defaults: UserDefaults!
    private static var islands: [NotchIslandFixture] = []

    /// A 13-inch display with a camera housing, or the same without one.
    static func display(physical: Bool = true) -> NotchDisplayInfo {
        NotchDisplayInfo(id: NotchIslandFixture.display.id, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                         visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 868),
                         safeAreaTop: physical ? 32 : 0, cameraWidth: physical ? 210 : 0,
                         backingScale: 2, isBuiltIn: physical, hasMenuBar: true)
    }

    /// A point on the island, just below the top edge of the display.
    static let onIsland = CGPoint(x: 720, y: 899)
    static let away = CGPoint(x: 720, y: 450)

    /// A started island over this suite's preferences, whose menus leave
    /// `room` beside the camera; nil leaves them unmeasured.
    static func island(physical: Bool = true, room: CGFloat? = 100,
                       before: (NotchIslandFixture) -> Void = { _ in }) -> NotchIslandFixture {
        let fixture = NotchIslandFixture(defaults: defaults)
        fixture.displays = [display(physical: physical)]
        fixture.pointer = away
        fixture.menusReadable = room != nil
        fixture.menuRoom = room
        before(fixture)
        fixture.start()
        islands.append(fixture)
        return fixture
    }

    static func playback(_ title: String, playing: Bool = true) -> NotchPlayback {
        NotchPlayback(track: RadialNowPlayingSnapshot(title: title, artist: "Artist", album: nil, artworkData: nil,
                                                      appBundleIdentifier: "org.example.player", appPID: 42),
                      isPlaying: playing, elapsed: 0, duration: 200, rate: 1, sampledAt: Date(), canSeek: false)
    }

    /// A timer counting down in the island's services.
    static func runTimer(_ fixture: NotchIslandFixture) {
        fixture.services.timerSession = NotchTimerSession(anchor: fixture.services.timerNow + 300)
    }

    static func captureOptions() -> ScreenCaptureSelectionOptions {
        ScreenCaptureSelectionOptions(availableTools: [.screenshot], selectedTool: .screenshot, showsCaptureMenu: false)
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vitruviansoftware.vitruvian.tests.notch-presentation-refresh"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        Self.defaults = defaults
        defer {
            islands.forEach { $0.island.stop() }
            islands.removeAll()
            Self.defaults = nil
            defaults.removePersistentDomain(forName: domain)
        }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for feature in AppFeature.allCases { defaults.set(true, forKey: feature.availabilityKey) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(NotchSize.spacious.rawValue, forKey: DefaultsKey.notchSize)
        // The cutout these checks measure, rather than the floating capsule.
        defaults.set(NotchSilhouette.notch.rawValue, forKey: DefaultsKey.notchSilhouette)
        defaults.set(NotchTimerMode.timer.rawValue, forKey: DefaultsKey.notchTimerMode)
        for event in [NotchEvent.capture, .volume, .systemNotification] { defaults.set(true, forKey: event.preferenceKey) }
        for key in [DefaultsKey.notchNotificationsEnabled, DefaultsKey.notchShelf, DefaultsKey.notchDragReveal] {
            defaults.set(true, forKey: key)
        }
        defaults.set(false, forKey: DefaultsKey.notchOpenOnHover)
        defaults.set(false, forKey: DefaultsKey.notchHideUntilHover)
        defaults.set(false, forKey: DefaultsKey.notchCoversMenus)
        compactMusicDepartureChecks(suite)
        mascotYieldChecks(suite)

        let outlined = island()
        defaults.set(true, forKey: DefaultsKey.notchOutlineEnabled)
        outlined.island.refreshPresentation(animated: false)
        suite.expect(outlined.host?.outlineEnabled == true && outlined.host?.outlineColor == .white,
                     "the optional outline reaches the resting island")
        runTimer(outlined)
        outlined.island.refreshPresentation(animated: false)
        suite.expect(outlined.host?.outlineColor == .systemOrange,
                     "the compact timer tints the optional outline orange")
        defaults.set(false, forKey: DefaultsKey.notchOutlineEnabled)
        outlined.island.refreshPresentation(animated: false)
        suite.expect(outlined.host?.outlineEnabled == false,
                     "turning the outline off updates the existing island")

        let toolbar = island()
        suite.expect(toolbar.island.expandedGeometry.headerCameraGap == 210,
                     "a standard wide page puts its header beside the camera")
        let toolbarShown = toolbar.island.presentCapture(
            id: UUID(), content: AnyView(EmptyView()), actions: AnyView(EmptyView()), height: 150, takeFocus: false,
            closeOnCollapse: false, fallback: {}, close: {}, hover: { _ in })
        suite.expect(toolbarShown && toolbar.island.expandedGeometry.headerCameraGap == 0
                     && toolbar.island.expandedGeometry.headerTopInset == 42
                     && toolbar.host?.activationRect.height == 42,
                     "a capture toolbar keeps a full row below the camera without losing actions to the cutout")
        toolbar.island.toggleSections()
        suite.expect(toolbar.island.expandedGeometry.headerCameraGap == 210,
                     "leaving capture editing restores the compact header layout")
        var titled = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 32, cameraWidth: 210)
        titled.headerTitleWidth = 108
        suite.expect(titled.headerCameraGap == 0 && titled.headerTopInset == 42,
                     "a page title wider than the camera's side takes the full row below it")
        titled.headerTitleWidth = 107
        suite.expect(titled.headerCameraGap == 210 && titled.headerTopInset == 0,
                     "a page title that fits keeps its place beside the camera")
        captureControlsChecks(suite)

        // A timer and a song compete, and the pointer rests on the strip.
        defaults.set(NotchIdleContent.music.rawValue, forKey: DefaultsKey.notchIdleContent)
        defaults.set(true, forKey: DefaultsKey.notchShowPlayingMusic)
        let picker = island {
            runTimer($0)
            $0.services.playback = playback("Song")
        }
        picker.move(to: onIsland)
        picker.island.selectCompactActivity(.music)
        picker.island.refreshPresentation(animated: false)
        suite.expect(picker.island.showsCompactActivityPicker && picker.island.compactActivity == .music
                     && picker.host!.activationRect.maxY <= picker.island.compactActivityGeometry.compactActivitySize.height,
                     "the native open button never covers the activity choices below the strip")
        // A song changing leaves the timer alone on the island for a moment.
        picker.services.playback = nil
        picker.island.refreshPresentation(animated: false)
        suite.expect(picker.island.compactActivity == .timer,
                     "production refresh keeps a chosen activity through a gap and shows what remains")
        picker.services.playback = playback("Song")
        picker.island.refreshPresentation(animated: false)
        suite.expect(picker.island.compactActivity == .music, "the chosen activity comes back instead of the timer")
        picker.services.playback = nil
        picker.services.timerSession = NotchTimerSession()
        picker.island.refreshPresentation(animated: false)
        runTimer(picker)
        picker.services.playback = playback("Song")
        suite.expect(picker.island.compactActivity == .timer,
                     "production refresh forgets the choice once nothing is left to show")
        defaults.set(NotchIdleContent.none.rawValue, forKey: DefaultsKey.notchIdleContent)

        defaults.set(true, forKey: DefaultsKey.notchHideInFullscreen)
        let fullscreen = island(before: { runTimer($0) })
        fullscreen.fullscreen = [NotchIslandFixture.display.id]
        fullscreen.island.syncWithPreferences()
        fullscreen.island.pinned = true
        fullscreen.island.refreshPresentation()
        let cutout = fullscreen.island.geometry.restingSize(showsContent: false)
        suite.expect(fullscreen.host?.panel.isVisible == true && !fullscreen.island.acceptsSystemFeedback
                     && fullscreen.island.acceptsUserInteraction && fullscreen.host?.panel.level == NotchPanel.normalLevel
                     && fullscreen.edgeMonitors > 0 && fullscreen.host?.targetSize == cutout
                     && fullscreen.host?.activationRect.size == cutout,
                     "fullscreen keeps a black, clickable cutout without automatic feedback or activity wings")
        fullscreen.host?.activate?()
        fullscreen.island.refreshPresentation()
        suite.expect(fullscreen.island.expanded && fullscreen.host?.panel.isVisible == true
                     && fullscreen.island.acceptsUserInteraction && !fullscreen.island.acceptsSystemFeedback
                     && fullscreen.host?.targetSize == fullscreen.island.surfaceSize,
                     "clicking the fullscreen cutout opens the island")
        fullscreen.island.collapse()
        fullscreen.island.refreshPresentation()
        suite.expect(fullscreen.host?.panel.isVisible == true && fullscreen.host?.targetSize == cutout,
                     "closing in fullscreen returns to the clickable black cutout")
        fullscreen.fullscreen = []
        fullscreen.island.syncWithPreferences()
        suite.expect(fullscreen.host?.panel.isVisible == true && fullscreen.island.acceptsSystemFeedback,
                     "leaving fullscreen restores ordinary content and feedback routing")

        let simulatedFullscreen = island(physical: false, room: 64)
        simulatedFullscreen.fullscreen = [NotchIslandFixture.display.id]
        simulatedFullscreen.island.syncWithPreferences()
        suite.expect(simulatedFullscreen.host?.panel.isVisible == false && simulatedFullscreen.edgeMonitors == 0
                     && simulatedFullscreen.island.acceptsUserInteraction,
                     "a simulated cutout with no camera to cover stays out of full-screen content")
        simulatedFullscreen.island.open()
        suite.expect(simulatedFullscreen.host?.panel.isVisible == true
                     && simulatedFullscreen.host?.panel.level == NotchPanel.fullscreenLevel,
                     "a simulated island opened by a shortcut yields to the menu bar in fullscreen")
        simulatedFullscreen.island.collapse()
        suite.expect(simulatedFullscreen.host?.panel.isVisible == false,
                     "closing a simulated island in fullscreen hides it again")
        simulatedFullscreen.island.open()
        simulatedFullscreen.fullscreen = []
        simulatedFullscreen.island.syncWithPreferences()
        suite.expect(simulatedFullscreen.host?.panel.level == NotchPanel.normalLevel,
                     "leaving fullscreen restores the usual panel level")
        defaults.set(true, forKey: DefaultsKey.notchCoversMenus)
        simulatedFullscreen.fullscreen = [NotchIslandFixture.display.id]
        simulatedFullscreen.island.syncWithPreferences()
        simulatedFullscreen.island.open()
        suite.expect(simulatedFullscreen.host?.panel.level == NotchPanel.normalLevel,
                     "the explicit cover-menus preference keeps the usual panel level")
        defaults.set(false, forKey: DefaultsKey.notchCoversMenus)
        defaults.set(false, forKey: DefaultsKey.notchHideInFullscreen)

        let missionControl = island()
        missionControl.host?.concealForMissionControl()
        suite.expect(!missionControl.island.acceptsSystemFeedback && !missionControl.island.acceptsUserInteraction
                     && !missionControl.island.showsSystemFeedback,
                     "a concealed island leaves system feedback available to its other presenters")
        missionControl.host?.restoreFromMissionControl()
        suite.expect(missionControl.island.acceptsSystemFeedback && missionControl.island.showsSystemFeedback,
                     "leaving Mission Control restores island feedback routing")

        let material = island(room: 0)
        material.island.refreshPresentation(animated: false)
        suite.expect(!material.island.usesGlassSurface && material.host?.usesGlass == false,
                     "compact presentation remains opaque regardless of camera or footer height")
        defaults.set(true, forKey: DefaultsKey.notchOpenOnHover)
        defaults.set(false, forKey: DefaultsKey.notchHoverExpands)
        material.move(to: onIsland)
        material.advance(2)
        suite.expect(material.island.peeking && material.host?.usesGlass == true, "peek requests the glass backdrop")
        material.island.open()
        suite.expect(material.host?.usesGlass == true, "expanded content requests the glass backdrop")
        material.island.collapse()
        _ = material.island.presentCommandBar()
        suite.expect(material.island.showingCommandBar && !material.island.usesGlassSurface
                     && material.host?.usesGlass == false,
                     "the Command Bar keeps the open island black, as its drop is")
        material.island.collapse()
        // A banner that arrives while the pointer is away, then held by it.
        material.move(to: away)
        let banner = NotchNotice(event: .systemNotification, title: "Alex", detail: "Hello", symbol: "bell.fill",
                                 notification: NotchNotificationContent(app: "Chat", title: "Alex", subtitle: "", body: "Hello"),
                                 notificationID: UUID())
        let bannerShown = material.island.show(banner)
        material.move(to: onIsland)
        material.advance(2)
        suite.expect(bannerShown && material.island.noticeExpanded && material.host?.usesGlass == true,
                     "expanded notification requests the glass backdrop")
        defaults.set(true, forKey: DefaultsKey.notchHoverExpands)

        let closing = island()
        closing.island.open()
        let open = closing.host?.frame ?? .zero
        let closedFrame = closing.island.geometry.frame(for: closing.island.geometry.collapsed)
        for (point, stillOver) in [(CGPoint(x: open.midX, y: open.minY + 4), false),
                                   (CGPoint(x: closedFrame.midX, y: closedFrame.maxY - 1), true)] {
            closing.island.open()
            closing.pointer = point
            closing.island.collapse()
            closing.island.refreshPresentation()
            // A pointer that has not moved: the window reports it over the
            // closed island, or it arrives there afterwards.
            if stillOver { closing.island.hover(true) } else { closing.move(to: onIsland) }
            closing.advance(2)
            suite.expect(closing.island.expanded == !stillOver, stillOver
                ? "a pointer still over the closed island keeps it from reopening until it leaves"
                : "closing away from a pointer that has not moved lets its next approach open the island")
            closing.move(to: away)
        }
        defaults.set(false, forKey: DefaultsKey.notchOpenOnHover)

        let fixture = island()
        let service = fixture.island
        service.open(.timer)
        var contentSize = service.surfaceSize
        var invalidations = 0
        let subscription = service.objectWillChange.sink {
            invalidations += 1
            contentSize = service.surfaceSize
        }
        defer { subscription.cancel() }
        var mismatches = 0
        fixture.host?.onPresent = { size in
            if contentSize != size { mismatches += 1 }
        }
        // The timer and the stopwatch share one height, so only a change
        // that resizes the island may publish.
        var resizes = 0
        for mode in [NotchTimerMode.pomodoro, .timer, .stopwatch, .pomodoro, .stopwatch, .timer] {
            let before = service.surfaceSize
            defaults.set(mode.rawValue, forKey: DefaultsKey.notchTimerMode)
            service.refreshPresentation(animated: false)
            if service.surfaceSize != before { resizes += 1 }
            suite.expect(contentSize == service.surfaceSize,
                   "switching Timer, Pomodoro and Stopwatch updates the content height without reopening the island")
        }
        suite.expect(mismatches == 0, "content is invalidated before the native window receives its new size")
        suite.expect(resizes == 4 && invalidations == resizes,
               "each mode change with a new size publishes it, and one keeping the size stays quiet")
        for _ in 0..<1000 { service.refreshPresentation() }
        suite.expect(invalidations == resizes, "unchanged presentations do not repeatedly invalidate SwiftUI layout")

        var session = NotchTimerSession()
        session.start(mode: .timer, minutes: 15, now: fixture.services.timerNow)
        fixture.services.timerSession = session
        service.refreshPresentation()
        let activeSize = contentSize
        let beforeModeChange = invalidations
        defaults.set(NotchTimerMode.pomodoro.rawValue, forKey: DefaultsKey.notchTimerMode)
        service.refreshPresentation()
        suite.expect(contentSize == activeSize && invalidations == beforeModeChange,
               "changing the saved setup mode preserves an active timer's layout")
        fixture.services.timerSession = NotchTimerSession()
        service.refreshPresentation()
        suite.expect(contentSize == service.surfaceSize && contentSize.height > activeSize.height && mismatches == 0,
               "canceling returns to the newly selected setup with synchronized content and window sizes")
        defaults.set(NotchTimerMode.timer.rawValue, forKey: DefaultsKey.notchTimerMode)

        let captureID = UUID()
        _ = service.presentCapture(id: captureID, content: AnyView(EmptyView()), height: 210, takeFocus: false,
                                   closeOnCollapse: false, fallback: {}, close: {}, hover: { _ in })
        let previewSize = contentSize
        service.updateCaptureHeight(id: captureID, height: 268)
        suite.expect(contentSize.height == previewSize.height + 58 && fixture.host?.targetSize == contentSize,
               "an embedded shared link expands both the capture content and its native window")
        service.updateCaptureHeight(id: captureID, height: 210)
        suite.expect(contentSize == previewSize, "removing a shared link restores the original preview height")
        service.updateCaptureHeight(id: UUID(), height: 268)
        suite.expect(contentSize == previewSize, "a replaced capture cannot resize its successor")
        service.open(.timer)
        let timerSize = contentSize
        service.updateCaptureHeight(id: captureID, height: 268)
        suite.expect(contentSize == timerSize, "sharing completion in a hidden preview does not resize the visible timer")
        service.open(.captures)
        service.pinned = true
        service.removeCapture(id: captureID)
        suite.expect(service.expanded && service.captureContent == nil && contentSize == service.expandedSize
               && fixture.host?.targetSize == contentSize,
               "dismissing a pinned capture clears the preview size and restores the full recent-captures area")

        let simulated = island(physical: false, room: nil)
        suite.expect(simulated.host?.panel.isVisible == false && simulated.edgeMonitors == 0,
               "an unmeasured simulated cutout does not cover a menu or receive screen-edge clicks")
        simulated.menusReadable = true
        simulated.menuRoom = 0
        simulated.island.syncWithPreferences()
        suite.expect(simulated.host?.panel.isVisible == true && simulated.edgeMonitors > 0
               && simulated.host?.frame == simulated.island.geometry.frame(for: simulated.island.surfaceSize),
               "a confirmed free center can show the simulated cutout without side room")
        let bareSize = simulated.island.surfaceSize
        let geometry = simulated.island.geometry
        let occupied = [CGRect(x: geometry.screen.midX - 15, y: geometry.screen.maxY - 24, width: 90, height: 24)]
        let blocked = NotchMenuBarLayout.sideRoom(screen: geometry.screen, cameraWidth: geometry.cameraWidth,
                                                 barHeight: geometry.menuBarHeight, occupied: occupied)
        suite.expect(blocked == nil, "a real center collision is distinct from zero-width free wings")
        simulated.menuRoom = blocked
        simulated.measureMenus()
        suite.expect(simulated.island.surfaceSize == bareSize && simulated.host?.panel.isVisible == false
               && simulated.edgeMonitors == 0,
               "a center collision hides even an unchanged bare simulated cutout")
        for active in [false, true] {
            if active { runTimer(simulated) }
            simulated.menuRoom = 64
            simulated.measureMenus()
            suite.expect(simulated.host?.panel.isVisible == true && simulated.edgeMonitors > 0,
                   "free menu space restores idle and active simulated content")
            simulated.menuRoom = nil
            simulated.measureMenus()
            suite.expect(simulated.host?.panel.isVisible == false && simulated.edgeMonitors == 0,
                   "idle and active simulated content both release menus when clearance is lost")
            simulated.island.refreshPresentation(animated: false)
            suite.expect(simulated.host?.panel.isVisible == false,
                   "a later refresh cannot redisplay compact activity over an occupied center")
        }
        simulated.island.open()
        suite.expect(simulated.host?.panel.isVisible == true
               && simulated.host?.frame.maxY == simulated.island.geometry.screen.maxY,
               "explicitly opening tools remains available without a menu measurement")
        suite.expect(simulated.host?.revealFromHidden == false,
               "ordinary openings keep their existing presentation behavior")
        simulated.island.collapse()
        suite.expect(simulated.host?.hideAnimations.last == true,
               "closing an expanded island without safe menu space animates its withdrawal")
        suite.expect(simulated.host?.panel.isVisible == false,
               "closing tools withdraws their simulated cutout if the center is still unverified")

        for isPhysical in [false, true] {
            // An activity and a notice are showing before the island hides.
            let hidden = island(physical: isPhysical, room: isPhysical ? 100 : 0, before: { runTimer($0) })
            let noticeShown = hidden.island.show(NotchNotice(event: .volume, title: "Volume", detail: "50%",
                                                             symbol: "speaker.wave.2.fill", level: 0.5))
            defaults.set(true, forKey: DefaultsKey.notchOpenOnHover)
            defaults.set(true, forKey: DefaultsKey.notchHideUntilHover)
            hidden.island.syncWithPreferences()
            hidden.island.refreshPresentation()
            suite.expect(noticeShown && hidden.island.notice != nil && hidden.host?.panel.isVisible == false
                   && hidden.edgeMonitors == 0 && !hidden.island.showsSystemFeedback,
                   "hidden mode withdraws the entire window, including compact activity and an existing notice")
            suite.expect(hidden.host?.hideAnimations.last == true,
                   "closing a hidden-until-hover island requests an animated withdrawal")
            hidden.island.refreshPresentation(animated: false)
            suite.expect(hidden.host?.hideAnimations.last == false,
                   "a nonanimated refresh preserves immediate withdrawal")
            hidden.island.open()
            suite.expect(hidden.host?.panel.isVisible == true && hidden.island.showsSystemFeedback,
                         "explicit openings remain visible in hidden mode")
            suite.expect(hidden.host?.revealFromHidden == true,
                   "opening a hidden island requests a reveal from the screen edge")
            hidden.island.collapse()
            hidden.island.presentCaptureControls(captureOptions(), cancel: {})
            suite.expect(hidden.host?.panel.isVisible == true, "capture controls remain visible until dismissed")
            suite.expect(hidden.host?.revealFromHidden == false,
                   "capture controls keep their own presentation in hidden-until-hover mode")
            hidden.island.endCaptureControls()
            hidden.island.fileDragChanged(true)
            suite.expect(hidden.host?.panel.isVisible == true, "an explicit file drag can still reveal its destination")
            hidden.island.fileDragChanged(false)
            suite.expect(hidden.host?.panel.isVisible == false, "ending the interaction hides the window again")
            defaults.set(false, forKey: DefaultsKey.notchHideUntilHover)
            defaults.set(false, forKey: DefaultsKey.notchOpenOnHover)
        }
        let physical = island(room: nil, before: { runTimer($0) })
        physical.island.refreshPresentation(animated: false)
        let strip = physical.island.compactActivityGeometry
        suite.expect(physical.host?.panel.isVisible == true && !strip.compactActivityUsesFooter
               && strip.compactActivityWingWidth == 0
               && physical.host?.targetSize.height == physical.island.geometry.menuBarHeight,
               "an active timer on a physical camera retracts its wings and stays at menu-bar height without a menu measurement")
    }

    /// Posts counted from any thread; the island posts them on the main one.
    nonisolated private final class PostCount: @unchecked Sendable {
        var value = 0
    }

    /// The companion resting in the closed island fades out ahead of an
    /// activity's strip, told once by the refresh that brings the strip.
    private static func mascotYieldChecks(_ suite: TestSuite) {
        defaults[Preferences.notchMascotEnabled] = true
        defaults.set(NotchIdleContent.none.rawValue, forKey: DefaultsKey.notchIdleContent)
        defer { defaults.removeValue(for: Preferences.notchMascotEnabled) }
        let yields = PostCount()
        let token = NotificationCenter.default.addObserver(forName: .notchMascotRestYields, object: nil,
                                                           queue: nil) { _ in yields.value += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        func arrival(reduceMotion: Bool = false, activity: Bool = true) -> (first: Int, again: Int) {
            let fixture = island()
            fixture.reducesMotion = reduceMotion
            // At rest in view first, as the island draws it.
            fixture.island.refreshPresentation(animated: false)
            yields.value = 0
            if activity { fixture.services.timerSession = NotchTimerSession(anchor: fixture.services.timerNow + 300) }
            fixture.island.refreshPresentation()
            let first = yields.value
            fixture.island.refreshPresentation()
            return (first, yields.value - first)
        }
        let arrived = arrival()
        suite.expect(arrived.first == 1 && arrived.again == 0,
                     "an activity taking the resting companion's place tells it once to fade out ahead of the strip")
        suite.expect(arrival(reduceMotion: true).first == 0 && arrival(activity: false).first == 0,
                     "Reduce Motion or nothing arriving leaves it where it rests")
    }

    private static func compactMusicDepartureChecks(_ suite: TestSuite) {
        defaults.set(NotchIdleContent.music.rawValue, forKey: DefaultsKey.notchIdleContent)
        defaults.set(true, forKey: DefaultsKey.notchShowPlayingMusic)
        defer {
            defaults.set(NotchIdleContent.none.rawValue, forKey: DefaultsKey.notchIdleContent)
            defaults.set(false, forKey: DefaultsKey.notchTrackChange)
        }
        let oldCover = NSImage(size: NSSize(width: 1, height: 1))
        let newCover = NSImage(size: NSSize(width: 2, height: 2))
        let tint = NotchArtworkTint(red: 0.2, green: 0.4, blue: 0.8)
        let playing = { (title: String) in { (fixture: NotchIslandFixture) in fixture.services.playback = playback(title) } }

        let changed = island {
            $0.services.playback = playback("One")
            $0.services.artwork = oldCover
        }
        changed.services.playback = playback("Two")
        changed.island.refreshPresentation(animated: false)
        changed.services.artwork = newCover
        changed.services.artworkTint = tint
        changed.island.refreshPresentation(animated: false)
        changed.services.playback = playback("Two", playing: false)
        changed.island.refreshPresentation()
        let departing = changed.island.departingMusic
        suite.expect(changed.host?.transitions.last == .depart && departing?.playback.track.title == "Two"
                     && departing?.artwork === newCover && departing?.tint == tint,
                     "a track and cover changed during playback remain current through departure")

        let stopped = island(before: playing("Three"))
        stopped.services.playback = playback("Three", playing: false)
        suite.expect(stopped.island.lingeringMusic?.playback.track.title == "Three",
                     "music that just stopped stays drawn until the refresh that lets it depart")
        stopped.island.refreshPresentation()
        suite.expect(stopped.island.departingMusic?.playback.track.title == "Three" && stopped.island.lingeringMusic == nil,
                     "its departure takes over the same track, with nothing drawn in between")
        let live = island(before: playing("Four"))
        suite.expect(live.island.compactActivity == .music && live.island.lingeringMusic == nil,
                     "live music is drawn as itself, never as a lingering copy")
        live.island.open()
        suite.expect(live.island.lingeringMusic == nil, "an open island draws its page, not a lingering song")

        defaults[Preferences.notchMascotEnabled] = true
        defaults.set(NotchIdleContent.none.rawValue, forKey: DefaultsKey.notchIdleContent)
        let resting = island()
        resting.island.refreshPresentation(animated: false)
        suite.expect(resting.island.mascotRestedInView,
                     "a refresh remembers the companion resting in view, so what arrives over it can crossfade from it")
        resting.island.open()
        suite.expect(!resting.island.mascotRestedInView,
                     "the open island hides the closed one, so nothing crossfades from a companion it does not show")
        defaults.removeValue(for: Preferences.notchMascotEnabled)
        defaults.set(NotchIdleContent.music.rawValue, forKey: DefaultsKey.notchIdleContent)

        let closing = island(before: playing("One"))
        closing.services.playback = playback("One", playing: false)
        closing.island.refreshPresentation()
        suite.expect(closing.host?.transitions.last == .depart && closing.island.departingMusic?.playback.track.title == "One",
                     "closing the last playing source keeps its compact track for the departure")
        closing.services.playback = playback("One")
        closing.island.refreshPresentation()
        suite.expect(closing.host?.transitions.last == .reveal && closing.island.departingMusic == nil,
                     "new playback interrupts a departing track and reveals its replacement")

        // A new song waits for its notice; the strip keeps the one it shows.
        defaults.set(true, forKey: DefaultsKey.notchTrackChange)
        let held = island(before: playing("One"))
        held.events.trackChanges.send()
        held.services.playback = playback("Two")
        held.island.refreshPresentation(animated: false)
        held.services.playback = playback("Two", playing: false)
        held.island.refreshPresentation()
        suite.expect(held.host?.transitions.last == .depart && held.island.departingMusic?.playback.track.title == "One",
                     "music that stops before a new song's notice departs as the song still on screen")
        held.island.refreshPresentation(animated: false)
        suite.expect(held.island.heldMusic == nil,
                     "a strip hidden for another reason ends the hold, so it returns with the live song")
        let holding = island(before: playing("One"))
        holding.events.trackChanges.send()
        holding.services.playback = playback("Two")
        holding.island.refreshPresentation(animated: false)
        suite.expect(holding.island.heldMusic?.playback.track.title == "One",
                     "while the strip stays on screen, a new reading keeps the song it shows")
        // A song held as it ended is released by the refresh that follows,
        // even one that hides the island before it reads the strip again.
        let hiding = island(before: playing("One"))
        hiding.events.trackChanges.send()
        defaults.set(true, forKey: DefaultsKey.notchOpenOnHover)
        defaults.set(true, forKey: DefaultsKey.notchHideUntilHover)
        hiding.island.refreshPresentation(animated: false)
        defaults.set(false, forKey: DefaultsKey.notchHideUntilHover)
        defaults.set(false, forKey: DefaultsKey.notchOpenOnHover)
        let unmeasured = island(physical: false, before: playing("One"))
        unmeasured.events.trackChanges.send()
        unmeasured.menuRoom = nil
        unmeasured.measureMenus()
        suite.expect([hiding, unmeasured].allSatisfy { $0.island.heldMusic == nil && $0.host?.panel.isVisible == false },
                     "hiding the island ends a hold, so the strip comes back with the live song")
        defaults.set(false, forKey: DefaultsKey.notchTrackChange)

        let replacement = island(before: playing("One"))
        replacement.services.playback = playback("One", playing: false)
        runTimer(replacement)
        replacement.island.refreshPresentation()
        suite.expect(replacement.host?.transitions.last == .replace,
                     "a compact timer replaces the disappearing music with a fade")

        // The picker changes the strip inside its surface, so the song chosen
        // away is no departure for the host to fade through every choice.
        let chosen = island {
            $0.services.playback = playback("Two")
            runTimer($0)
        }
        chosen.move(to: onIsland)
        chosen.island.selectCompactActivity(.music)
        let presented = chosen.host?.transitions.count ?? 0
        chosen.island.selectCompactActivity(.timer)
        suite.expect(chosen.island.showsCompactActivityPicker && chosen.island.compactActivity == .timer
                     && chosen.host.map { Array($0.transitions.dropFirst(presented)) } == [NotchContentTransition.none],
                     "choosing another activity over a song changes the strip in place, without the host's fade")

        let reduced = island(before: playing("Three"))
        reduced.reducesMotion = true
        reduced.services.playback = playback("Three", playing: false)
        reduced.island.refreshPresentation()
        suite.expect(reduced.host?.transitions.last == NotchContentTransition.none && reduced.island.departingMusic == nil,
                     "Reduce Motion removes the music strip immediately")
    }
}
