// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The module's hover handling on a real island (`NotchIslandFixture`), with
/// the fixture's clock and pointer. No input is posted and the user's
/// preferences are never read or changed.
enum NotchHoverTests {
    private static var defaults: UserDefaults!
    private static var islands: [NotchIslandFixture] = []

    /// A simulated cutout on an external display left of the main one, or a
    /// built-in display's camera housing.
    private static func display(physical: Bool) -> NotchDisplayInfo {
        physical
            ? NotchDisplayInfo(id: NotchIslandFixture.display.id, frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                               visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 924), safeAreaTop: 32,
                               cameraWidth: 180, backingScale: 2, isBuiltIn: true, hasMenuBar: true)
            : NotchDisplayInfo(id: NotchIslandFixture.display.id, frame: CGRect(x: -1920, y: 900, width: 1920, height: 1080),
                               visibleFrame: CGRect(x: -1920, y: 900, width: 1920, height: 1058), safeAreaTop: 0,
                               cameraWidth: 0, backingScale: 2, isBuiltIn: false, hasMenuBar: true)
    }

    /// A started island with hover at its defaults, its menus leaving it
    /// room, and the pointer resting at the top of its display.
    private static func island(physical: Bool = false, before: (NotchIslandFixture) -> Void = { _ in })
        -> NotchIslandFixture {
        defaults.set(true, forKey: DefaultsKey.notchOpenOnHover)
        defaults.set(true, forKey: DefaultsKey.notchHoverExpands)
        defaults.set(false, forKey: DefaultsKey.notchHideUntilHover)
        defaults.set(NotchSupport.defaultHoverDelay, forKey: DefaultsKey.notchHoverDelay)
        let fixture = NotchIslandFixture(defaults: defaults)
        fixture.displays = [display(physical: physical)]
        fixture.menusReadable = true
        fixture.menuRoom = 64
        before(fixture)
        fixture.start()
        fixture.pointer = top(fixture)
        islands.append(fixture)
        return fixture
    }

    private static func top(_ fixture: NotchIslandFixture) -> CGPoint {
        CGPoint(x: fixture.displays[0].frame.midX, y: fixture.displays[0].frame.maxY)
    }

    /// The pointer leaves for the far corner, and the window reports it.
    private static func leave(_ fixture: NotchIslandFixture) {
        fixture.pointer = CGPoint(x: fixture.displays[0].frame.minX, y: fixture.displays[0].frame.minY)
        fixture.island.hover(false)
    }

    private static func song(_ title: String, playing: Bool = true) -> NotchPlayback {
        NotchPlayback(track: RadialNowPlayingSnapshot(title: title, artist: "Artist", album: nil, artworkData: nil,
                                                      appBundleIdentifier: "org.example.player", appPID: 42),
                      isPlaying: playing, elapsed: 0, duration: 200, rate: 1, sampledAt: Date(), canSeek: false)
    }

    /// Music playing on the closed island.
    private static func playMusic(_ fixture: NotchIslandFixture) {
        fixture.services.playback = song("Song")
    }

    private static func runTimer(_ fixture: NotchIslandFixture) {
        fixture.services.timerSession = NotchTimerSession(anchor: fixture.services.timerNow + 300)
    }

    private static func captureOptions() -> ScreenCaptureSelectionOptions {
        ScreenCaptureSelectionOptions(availableTools: [.screenshot], selectedTool: .screenshot, showsCaptureMenu: false)
    }

    private static func lock(_ fixture: NotchIslandFixture) {
        fixture.post(session: "com.apple.screenIsLocked")
    }

    private static func hide(_ fixture: NotchIslandFixture) {
        defaults.set(true, forKey: DefaultsKey.notchHideUntilHover)
        fixture.island.syncWithPreferences()
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vitruviansoftware.vitruvian.tests.notch-hover"
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
        defaults.set(NotchSilhouette.notch.rawValue, forKey: DefaultsKey.notchSilhouette)
        defaults.set(NotchIdleContent.music.rawValue, forKey: DefaultsKey.notchIdleContent)
        defaults.set(true, forKey: DefaultsKey.notchShowPlayingMusic)
        defaults.set(false, forKey: DefaultsKey.notchTrackChange)
        defaults.set(false, forKey: DefaultsKey.notchCoversMenus)
        for event in [NotchEvent.capture, .volume, .systemNotification] { defaults.set(true, forKey: event.preferenceKey) }
        for key in [DefaultsKey.notchNotificationsEnabled, DefaultsKey.notchShelf, DefaultsKey.notchDragReveal] {
            defaults.set(true, forKey: key)
        }
        func expect(_ condition: Bool, _ message: String) {
            suite.expect(condition, message)
        }
        let volume = NotchNotice(event: .volume, title: "Volume", detail: "50%", symbol: "speaker.wave.2.fill", level: 0.5)

        for physical in [false, true] {
            for reduced in [false, true] {
                let picker = island(physical: physical) {
                    runTimer($0)
                    playMusic($0)
                }
                picker.reducesMotion = reduced
                picker.island.hover(true)
                suite.expect(picker.island.showsCompactActivityPicker && picker.pendingWork == 0,
                             "hover exposes named choices without an automatic opening deadline, including Reduce Motion")
                picker.advance(2)
                suite.expect(!picker.island.expanded && !picker.island.peeking,
                             "the activity chooser stays available while the person decides")
                picker.notifications.post(name: NSMenu.didBeginTrackingNotification, object: nil)
                picker.settle()
                leave(picker)
                suite.expect(picker.island.showsCompactActivityPicker, "moving into the combination menu keeps its picker visible")
                picker.notifications.post(name: NSMenu.didEndTrackingNotification, object: nil)
                picker.settle()
                leave(picker)
                suite.expect(!picker.island.showsCompactActivityPicker, "leaving hides the activity chooser")
                picker.pointer = top(picker)
                picker.island.open()
                picker.island.hover(true)
                suite.expect(!picker.island.showsCompactActivityPicker, "the chooser does not cover an open page")
                picker.island.collapse()
                picker.island.presentCaptureControls(captureOptions(), cancel: {})
                suite.expect(!picker.island.showsCompactActivityPicker, "capture controls retain priority")
                picker.island.endCaptureControls()
                _ = picker.island.show(volume)
                suite.expect(picker.island.notice != nil && !picker.island.showsCompactActivityPicker,
                             "system notices retain priority")
                picker.runScheduled()
                defaults.set(true, forKey: DefaultsKey.notchHideInFullscreen)
                picker.fullscreen = [NotchIslandFixture.display.id]
                picker.island.syncWithPreferences()
                suite.expect(picker.island.hiddenInFullscreen && !picker.island.showsCompactActivityPicker,
                             "full-screen content hiding retains priority")
                defaults.set(false, forKey: DefaultsKey.notchHideInFullscreen)
            }
        }
        for physical in [false, true] {
            let clickOnly = island(physical: physical)
            defaults.set(false, forKey: DefaultsKey.notchOpenOnHover)
            let resting = clickOnly.island.surfaceSize
            clickOnly.island.hover(true)
            let emphasized = clickOnly.island.surfaceSize
            suite.expect(emphasized.height == resting.height + 5 && emphasized.width >= resting.width
                         && emphasized.width <= resting.width + 20 && clickOnly.pendingWork == 0,
                         "click-only islands pulse within available menu space without scheduling an opening")
            leave(clickOnly)
            suite.expect(clickOnly.island.surfaceSize == resting,
                         "leaving restores the resting island size")
        }
        let hiddenPulse = island()
        hide(hiddenPulse)
        let hiddenResting = hiddenPulse.island.surfaceSize
        hiddenPulse.island.hover(true)
        suite.expect(hiddenPulse.island.surfaceSize == hiddenResting,
                     "an invisible island does not pulse before its hover reveal")
        let reducedMotion = island()
        defaults.set(false, forKey: DefaultsKey.notchOpenOnHover)
        reducedMotion.reducesMotion = true
        let reducedResting = reducedMotion.island.surfaceSize
        reducedMotion.island.hover(true)
        suite.expect(reducedMotion.island.surfaceSize == reducedResting,
                     "Reduce Motion leaves the resting island still on hover")
        for physical in [false, true] {
            for opensOnHover in [false, true] {
                let compactPulse = island(physical: physical, before: playMusic)
                defaults.set(opensOnHover, forKey: DefaultsKey.notchOpenOnHover)
                let compactResting = compactPulse.island.surfaceSize
                compactPulse.island.hover(true)
                suite.expect(compactPulse.island.compactActivity == .music
                             && compactPulse.island.surfaceSize.height == compactResting.height + (opensOnHover ? 0 : 5),
                             "a compact activity waits at rest for a hover opening and pulses for a click opening")
                leave(compactPulse)
                suite.expect(compactPulse.island.surfaceSize == compactResting,
                             "the compact activity returns to its original size on exit")
            }
        }
        let fullscreen = island(physical: true, before: playMusic)
        defaults.set(true, forKey: DefaultsKey.notchHideInFullscreen)
        defaults.set(true, forKey: DefaultsKey.notchHideUntilHover)
        defaults.set(false, forKey: DefaultsKey.notchHoverExpands)
        fullscreen.fullscreen = [NotchIslandFixture.display.id]
        fullscreen.island.syncWithPreferences()
        fullscreen.runScheduled()
        // Stepping aside closed the island under the resting pointer, which
        // holds hover back until the pointer leaves and comes back.
        leave(fullscreen)
        let blackSize = fullscreen.island.surfaceSize
        fullscreen.pointer = top(fullscreen)
        fullscreen.island.hover(true)
        suite.expect(blackSize == fullscreen.island.geometry.restingSize(showsContent: false)
                     && fullscreen.island.surfaceSize == blackSize && fullscreen.pendingWork == 1,
                     "fullscreen keeps the cutout black but schedules configured hover access even with cached music")
        fullscreen.advance(0.26)
        suite.expect(fullscreen.island.peeking && !fullscreen.island.expanded,
                     "hover preview remains available from the black fullscreen cutout")
        let simulatedFullscreen = island()
        simulatedFullscreen.fullscreen = [NotchIslandFixture.display.id]
        simulatedFullscreen.island.syncWithPreferences()
        simulatedFullscreen.island.hover(true)
        simulatedFullscreen.advance(0.26)
        suite.expect(simulatedFullscreen.pendingWork == 0 && !simulatedFullscreen.island.peeking
                     && !simulatedFullscreen.island.expanded,
                     "a simulated cutout hidden in full screen does not open on hover")
        defaults.set(false, forKey: DefaultsKey.notchHideInFullscreen)
        for physical in [false, true] {
            let service = island(physical: physical)
            let resting = service.island.surfaceSize
            service.island.hover(true)
            suite.expect(service.island.surfaceSize == resting && service.pendingWork == 1,
                         "hover opening keeps either display's island at rest instead of previewing before expansion")
            service.advance(0.20)
            suite.expect(!service.island.expanded && service.island.surfaceSize == resting,
                         "the island stays at rest throughout the configured hover opening delay")
            service.island.hover(false) // A tracking exit while the pointer is still inside.
            suite.expect(service.pendingWork == 1, "duplicate tracking events preserve the original opening deadline")
            service.advance(0.06)
            suite.expect(service.island.expanded && service.host?.hasKeyboard == false && service.pendingWork == 0,
                   "a deliberate hover opens after the default 250 ms on both physical and simulated cutouts")
            leave(service)
            service.advance(0.10)
            service.island.hover(false)
            suite.expect(service.pendingWork == 1, "overlapping exit events do not postpone closing")
            service.advance(0.09)
            suite.expect(!service.island.expanded && service.pendingWork == 0,
                   "leaving either display's expanded island closes it within 190 ms")
            service.drift(to: service.pointer)
            suite.expect(!service.watchesMovement,
                   "the first move after the hover-opened island closed releases the pointer observers")
        }
        for physical in [false, true] {
            // A notice already present when the preference changes.
            let hidden = island(physical: physical)
            _ = hidden.island.show(volume)
            hide(hidden)
            for _ in 0..<100 { hidden.island.refreshPresentation(animated: false) }
            suite.expect(hidden.island.notice != nil && hidden.movementWatchCount == 1,
                   "hidden mode keeps one pair of native movement observers")
            let corner = CGPoint(x: hidden.displays[0].frame.minX, y: hidden.displays[0].frame.minY)
            hidden.move(to: top(hidden))
            hidden.advance(0.20)
            suite.expect(!hidden.island.expanded, "a hidden island honors the saved activation delay")
            hidden.move(to: corner)
            hidden.advance(0.20)
            suite.expect(!hidden.island.expanded, "leaving the invisible region cancels pending activation")
            hidden.move(to: top(hidden))
            hidden.advance(0.26)
            suite.expect(hidden.island.expanded && hidden.host?.hasKeyboard == false,
                   "movement reveals either display without a visible window or menu measurement")
            suite.expect(hidden.movementWatchCount == 0, "revealing hands hover back to native window tracking")
            leave(hidden)
            hidden.advance(0.20)
            suite.expect(!hidden.island.expanded && hidden.island.acceptsSystemFeedback
                         && !hidden.island.showsSystemFeedback,
                   "leaving returns the revealed island to its hidden state")
            hidden.island.stop()
            suite.expect(hidden.movementWatchCount == 0, "stopping releases both hidden hover observers")
        }
        // Hidden hover and following the pointer both watch through
        // `NotchMovementWatch.Environment.system`, whose handler in this app is this one.
        if let event = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
            var moves = 0
            let handler = NotchMovementWatch.Environment.passingThrough { moves += 1 }
            suite.expect(handler(event) === event && moves == 1,
                         "hidden hover and following the pointer never consume the original local event")
        } else {
            suite.expect(false, "a mouse-moved event can be made")
        }
        for expands in [false, true] {
            let hidden = island()
            defaults.set(expands, forKey: DefaultsKey.notchHoverExpands)
            hide(hidden)
            hidden.host?.concealForMissionControl()
            hidden.island.hover(true)
            suite.expect(hidden.pendingWork == 0, "Mission Control cannot start a hidden island's hover deadline")
            hidden.host?.restoreFromMissionControl()
            hidden.island.hover(true)
            suite.expect(hidden.pendingWork == 1, "leaving Mission Control allows a fresh hidden hover deadline")
            hidden.host?.concealForMissionControl()
            hidden.advance(0.26)
            suite.expect(!hidden.island.expanded && !hidden.island.peeking && hidden.host?.revealChecks == 1,
                         "Mission Control starting during the hover delay blocks expansion and preview")

            let visible = island()
            defaults.set(expands, forKey: DefaultsKey.notchHoverExpands)
            visible.island.hover(true)
            suite.expect(visible.pendingWork == 1,
                         "a visible island has a pending hover deadline before Mission Control")
            visible.host?.concealForMissionControl()
            visible.advance(0.26)
            suite.expect(!visible.island.expanded && !visible.island.peeking && visible.host?.revealChecks == 1,
                         "Mission Control blocks a pending visible hover without a mouse-exit event")
            visible.host?.restoreFromMissionControl()
            suite.expect(visible.pendingWork == 1,
                         "restoring Mission Control restarts a hover deadline when the pointer stayed over the island")
            visible.advance(0.26)
            suite.expect(expands ? visible.island.expanded : visible.island.peeking,
                         "the restored hover opens the island after its normal delay")
        }
        let capturePreview = island()
        var previewHovered: Bool?
        _ = capturePreview.island.presentCapture(
            id: UUID(), content: AnyView(EmptyView()), height: 120, takeFocus: false, closeOnCollapse: false,
            fallback: {}, close: {}, hover: { previewHovered = $0 })
        previewHovered = nil
        capturePreview.host?.concealForMissionControl()
        capturePreview.host?.restoreFromMissionControl()
        suite.expect(previewHovered == true,
                     "restoring with the pointer over a capture preview keeps its auto-dismiss paused")

        let departed = island()
        departed.island.hover(true)
        departed.advance(0.26)
        suite.expect(departed.island.expanded && departed.host?.hasKeyboard == false,
                     "the island is open from hover before Mission Control")
        departed.host?.concealForMissionControl()
        departed.pointer = CGPoint(x: departed.displays[0].frame.minX, y: departed.displays[0].frame.minY)
        departed.host?.restoreFromMissionControl()
        suite.expect(departed.island.expanded && departed.pendingWork == 1,
                     "restoration notices that the pointer left while Mission Control owned input")
        departed.advance(0.19)
        suite.expect(!departed.island.expanded,
                     "the hover-open island closes after its normal pointer exit delay")

        // AppKit's last exit can come while the pointer is still in the margin
        // around the floating controls. Leaving from there over transparent
        // pixels or out of the window reports nothing more to the island.
        func openWithPointerInMargin() -> (NotchIslandFixture, CGRect) {
            let service = island()
            service.island.hover(true)
            service.advance(0.26)
            let open = service.host!.frame
            service.host?.hoverExtras = [CGRect(x: open.midX - 38, y: open.minY - 72, width: 76, height: 88)]
            service.pointer = CGPoint(x: open.midX, y: open.minY - 60)
            service.island.hover(false)
            return (service, open)
        }
        let (margin, open) = openWithPointerInMargin()
        suite.expect(margin.island.expanded && margin.pendingWork == 0 && margin.movementWatchCount == 1,
                     "an exit reported in the controls' margin keeps the island open and follows the pointer")
        margin.drift(to: CGPoint(x: open.midX + 20, y: open.minY - 30))
        margin.advance(0.5)
        suite.expect(margin.island.expanded, "slow travel through the margin keeps the island open")
        margin.drift(to: CGPoint(x: open.midX, y: open.minY - 400))
        margin.advance(0.10)
        margin.drift(to: CGPoint(x: open.midX - 20, y: open.minY - 50))
        margin.advance(0.20)
        suite.expect(margin.island.expanded, "slipping back into the margin unreported cancels the pending close")
        margin.drift(to: CGPoint(x: open.midX, y: open.minY - 400))
        margin.advance(0.19)
        suite.expect(!margin.island.expanded, "leaving from the margin with no further report still closes the island")
        margin.drift(to: CGPoint(x: open.midX, y: open.minY - 420))
        suite.expect(!margin.watchesMovement, "the closed island stops following the pointer")

        let (reported, _) = openWithPointerInMargin()
        reported.island.hover(true)
        suite.expect(!reported.watchesMovement && reported.island.expanded,
                     "an entry AppKit reports hands hover back to its tracking")
        let (stopped, _) = openWithPointerInMargin()
        stopped.island.stop()
        stopped.drift(to: CGPoint(x: open.midX, y: open.minY - 400))
        suite.expect(!stopped.watchesMovement && stopped.pendingWork == 0,
                     "stopping the island releases the pointer observers")
        // Pinning, a drag from the shelf, or a menu or dialog keeps the island
        // and ends the watch. A menu that closes with the pointer still in the
        // margin starts it again.
        for protect: (NotchIslandFixture) -> Void in [
            { $0.island.pinned = true }, { $0.island.fileDragChanged(true, internalDrag: true) },
            { $0.services.hasModalWindow = true }
        ] {
            let (held, _) = openWithPointerInMargin()
            protect(held)
            held.drift(to: CGPoint(x: open.midX, y: open.minY - 400))
            held.advance(1)
            suite.expect(held.island.expanded && !held.watchesMovement,
                         "pinning, a shelf drag, a menu or a dialog keeps the island and stops following the pointer")
        }
        let (menu, _) = openWithPointerInMargin()
        menu.services.hasModalWindow = true
        menu.drift(to: CGPoint(x: open.midX + 20, y: open.minY - 30))
        menu.services.hasModalWindow = false
        menu.island.hover(false)
        suite.expect(menu.movementWatchCount == 1,
                     "a menu that closes with the pointer in the margin follows the pointer again")
        menu.drift(to: CGPoint(x: open.midX, y: open.minY - 400))
        menu.advance(0.19)
        menu.drift(to: CGPoint(x: open.midX, y: open.minY - 420))
        suite.expect(!menu.island.expanded && !menu.watchesMovement,
                     "leaving after the menu closes the island and releases the pointer observers")
        let clickOpened = island()
        clickOpened.island.open()
        clickOpened.host?.hoverExtras = [CGRect(x: open.midX - 38, y: open.minY - 72, width: 76, height: 88)]
        clickOpened.pointer = CGPoint(x: open.midX, y: open.minY - 60)
        clickOpened.island.hover(false)
        suite.expect(!clickOpened.watchesMovement,
                     "an island opened by a click, which leaving does not close, never follows the pointer")
        // Passing quickly over the closed island to a display above: the last
        // exit arrives while the pointer still touches the island's top edge.
        do {
            let passed = island()
            defaults.set(false, forKey: DefaultsKey.notchOpenOnHover)
            let edge = passed.host!.frame
            let resting = passed.island.surfaceSize
            passed.pointer = CGPoint(x: edge.midX, y: edge.maxY - 1)
            passed.island.hover(true)
            passed.island.hover(false)
            suite.expect(passed.island.surfaceSize.height == resting.height + 5 && passed.movementWatchCount == 1,
                         "an exit reported at the top edge keeps the emphasis and follows the pointer")
            passed.drift(to: CGPoint(x: edge.midX, y: edge.maxY + 300))
            suite.expect(passed.island.surfaceSize == resting,
                         "the first move on the display above clears the closed island's hover emphasis")
            suite.expect(!passed.watchesMovement,
                         "the closed island stops following the pointer once the emphasis is gone")
            // Fast enough, AppKit reports no exit at all after the entry.
            let silent = island()
            defaults.set(false, forKey: DefaultsKey.notchOpenOnHover)
            silent.pointer = CGPoint(x: edge.midX, y: edge.maxY - 1)
            silent.island.hover(true)
            suite.expect(silent.island.surfaceSize.height == resting.height + 5 && silent.movementWatchCount == 1,
                         "the closed island follows the pointer while its hover emphasis shows")
            silent.drift(to: CGPoint(x: edge.midX + 10, y: edge.maxY - 2))
            suite.expect(silent.island.surfaceSize.height == resting.height + 5,
                         "moving over the island keeps its hover emphasis")
            silent.drift(to: CGPoint(x: edge.midX, y: edge.maxY + 300))
            suite.expect(silent.island.surfaceSize == resting && !silent.watchesMovement,
                         "an unreported exit to the display above still clears the emphasis and its observers")
            // A notice that holds back a preview leaves the island emphasized
            // under a resting pointer, so following goes on past the deadline.
            let interrupted = island()
            defaults.set(false, forKey: DefaultsKey.notchHoverExpands)
            interrupted.pointer = CGPoint(x: edge.midX, y: edge.maxY - 1)
            interrupted.island.hover(true)
            _ = interrupted.island.show(volume)
            interrupted.runScheduled()
            suite.expect(interrupted.island.notice == nil && !interrupted.island.peeking
                         && interrupted.movementWatchCount == 1,
                         "a preview a notice held back keeps following the emphasized island")
            interrupted.drift(to: CGPoint(x: edge.midX, y: edge.maxY + 300))
            suite.expect(interrupted.island.surfaceSize == resting && !interrupted.watchesMovement,
                         "an unreported exit after the notice still clears the emphasis and its observers")
            // A second activity that starts during a hover opening shows the
            // picker instead, which still needs the pointer followed out.
            let joined = island(before: runTimer)
            joined.pointer = CGPoint(x: edge.midX, y: edge.maxY - 1)
            joined.island.hover(true)
            playMusic(joined)
            joined.island.refreshPresentation(animated: false)
            joined.advance(1)
            suite.expect(!joined.island.expanded && joined.island.showsCompactActivityPicker
                         && joined.movementWatchCount == 1,
                         "a picker that appears during a hover opening keeps following the pointer")
            joined.drift(to: CGPoint(x: edge.midX, y: edge.maxY + 300))
            suite.expect(!joined.island.showsCompactActivityPicker && !joined.watchesMovement,
                         "an unreported exit to the display above still hides that picker and releases its observers")
        }
        // A full opening has no hover emphasis, but still needs an uninterrupted
        // stay. Leaving without a tracking exit must discard the old deadline.
        for physical in [false, true] {
            for reduced in [false, true] {
                let returning = island(physical: physical)
                defaults.set(0.6, forKey: DefaultsKey.notchHoverDelay)
                returning.reducesMotion = reduced
                let edge = returning.host!.frame
                let entry = CGPoint(x: edge.midX, y: edge.maxY - 1)
                let above = CGPoint(x: edge.midX, y: edge.maxY + 300)
                let resting = returning.island.surfaceSize
                func pendingOpenings() -> Int { returning.pendingDelays.filter { $0 == 0.6 }.count }
                returning.pointer = entry
                returning.island.hover(true)
                suite.expect(returning.island.surfaceSize == resting && pendingOpenings() == 1
                             && returning.movementWatchCount == 1,
                             "hover opening follows the pointer without emphasizing the island, including Reduce Motion")
                returning.advance(0.4)
                returning.drift(to: above)
                suite.expect(pendingOpenings() == 0,
                             "a move to the display above cancels the opening even without a tracking exit")
                suite.expect(!returning.watchesMovement, "leaving a pending hover opening releases its pointer observers")
                returning.advance(0.05)
                returning.pointer = entry
                returning.island.hover(true)
                suite.expect(pendingOpenings() == 1, "returning after an unreported exit starts a fresh hover deadline")
                returning.advance(0.16)
                suite.expect(!returning.island.expanded && returning.island.surfaceSize == resting,
                             "the original opening deadline cannot open an island the pointer left and reentered")
                returning.advance(0.43)
                suite.expect(!returning.island.expanded, "reentry waits for the full configured delay")
                returning.advance(0.02)
                suite.expect(returning.island.expanded && !returning.watchesMovement,
                             "the fresh hover opens once and releases the pending opening's pointer observers")
                returning.island.collapse()
                returning.island.hover(true)
                suite.expect(!returning.island.expanded && pendingOpenings() == 0 && returning.movementWatchCount == 1,
                             "an explicit close under the pointer follows its departure without reopening")
                returning.drift(to: above)
                suite.expect(!returning.watchesMovement,
                             "an unreported departure after an explicit close releases its observers")
                returning.pointer = entry
                returning.island.hover(true)
                returning.advance(0.59)
                suite.expect(!returning.island.expanded, "reopening after an explicit close waits for the full hover delay")
                returning.advance(0.02)
                suite.expect(returning.island.expanded && !returning.watchesMovement,
                             "the first return after an explicit close opens normally even without a tracking exit")
            }
        }
        // A timed capture still attached to the closed island would hear each
        // followed move as the pointer leaving and restart its dismissal.
        do {
            let attached = island()
            defaults.set(false, forKey: DefaultsKey.notchOpenOnHover)
            var previewHovered: Bool?
            _ = attached.island.presentCapture(
                id: UUID(), content: AnyView(EmptyView()), height: 120, takeFocus: false, closeOnCollapse: false,
                fallback: {}, close: {}, hover: { previewHovered = $0 })
            attached.pointer = CGPoint(x: 0, y: 0)
            attached.island.collapse()
            attached.island.hover(false)
            let resting = attached.island.surfaceSize
            let edge = attached.host!.frame
            attached.pointer = CGPoint(x: edge.midX, y: edge.maxY - 1)
            attached.island.hover(true)
            suite.expect(attached.island.captureContent != nil && attached.island.surfaceSize.height == resting.height + 5
                            && previewHovered == true && !attached.watchesMovement,
                         "the closed island holding a capture keeps it paused and does not follow the pointer")
        }
        // Opening or peeking on hover ends the closed island's follow at once,
        // so the next move cannot tell a page or preview the pointer left.
        for expands in [true, false] {
            let opening = island()
            defaults.set(expands, forKey: DefaultsKey.notchHoverExpands)
            let edge = opening.host!.frame
            let resting = opening.island.surfaceSize
            opening.pointer = CGPoint(x: edge.midX, y: edge.maxY - 1)
            opening.island.hover(true)
            suite.expect(opening.island.surfaceSize.height == resting.height + (expands ? 0 : 5)
                         && opening.movementWatchCount == 1,
                         "both hover modes follow the pointer before revealing content, while only the preview emphasizes it")
            opening.advance(0.26)
            suite.expect((expands ? opening.island.expanded : opening.island.peeking) && !opening.watchesMovement,
                         "opening or peeking on hover drops the closed island's pointer observers")
        }
        let disables: [(NotchIslandFixture) -> Void] = [
            { lock($0) },
            { fixture in
                fixture.displays = []
                fixture.island.syncWithPreferences()
            },
            // Turning hidden mode off, or hover opening off, is a preference change.
            { fixture in
                defaults.set(false, forKey: DefaultsKey.notchHideUntilHover)
                fixture.island.syncWithPreferences()
            },
            { fixture in
                defaults.set(false, forKey: DefaultsKey.notchOpenOnHover)
                fixture.island.syncWithPreferences()
            }
        ]
        for disable in disables {
            let hidden = island()
            hide(hidden)
            let watching = hidden.movementWatchCount
            disable(hidden)
            suite.expect(watching == 1 && !hidden.watchesMovement,
                   "suspension, missing display and preference changes release hidden hover observers")
        }
        let passing = island()
        passing.island.hover(true)
        passing.advance(0.20)
        leave(passing)
        passing.advance(1)
        suite.expect(!passing.island.expanded, "leaving before the opening deadline cancels expansion")

        let reentering = island()
        reentering.island.hover(true)
        reentering.advance(0.20)
        leave(reentering)
        reentering.advance(0.02)
        reentering.pointer = top(reentering)
        reentering.island.hover(true)
        reentering.advance(0.20)
        suite.expect(!reentering.island.expanded, "separate short passes cannot accumulate time toward opening")
        reentering.advance(0.06)
        suite.expect(reentering.island.expanded, "reentering requires a fresh uninterrupted activation delay")

        for delay in [0.10, 0.25, 0.65, 1.0] {
            for expands in [false, true] {
                let custom = island()
                defaults.set(delay, forKey: DefaultsKey.notchHoverDelay)
                defaults.set(expands, forKey: DefaultsKey.notchHoverExpands)
                custom.island.hover(true)
                custom.advance(delay - 0.01)
                suite.expect(!custom.island.expanded && !custom.island.peeking,
                             "hover waits for the full configured delay in both opening modes")
                custom.advance(0.02)
                suite.expect(expands ? custom.island.expanded : custom.island.peeking,
                       "both expansion and preview honor the selected activation time")
            }
        }

        let adjusted = island()
        adjusted.island.hover(true)
        leave(adjusted)
        defaults.set(0.65, forKey: DefaultsKey.notchHoverDelay)
        adjusted.pointer = top(adjusted)
        adjusted.island.hover(true)
        adjusted.advance(0.30)
        suite.expect(!adjusted.island.expanded, "a changed activation time applies on the next entry without restarting")
        adjusted.advance(0.36)
        suite.expect(adjusted.island.expanded, "the updated activation time completes normally")

        let active = island(before: playMusic)
        let reopening = active.island.reopeningModule
        active.island.hover(true)
        active.advance(0.26)
        expect(active.island.expanded && active.island.selected == reopening,
               "hover opens without naming a page, so the island's own reopening rule decides")

        let returning = island()
        returning.island.hover(true)
        returning.advance(0.26)
        leave(returning)
        returning.advance(0.10)
        returning.pointer = top(returning)
        returning.island.hover(true)
        returning.advance(1)
        suite.expect(returning.island.expanded && returning.pendingWork == 0,
               "returning before the closing deadline cancels closing without reopening")

        let preview = island()
        defaults.set(false, forKey: DefaultsKey.notchHoverExpands)
        preview.island.hover(true)
        preview.advance(0.26)
        suite.expect(preview.island.peeking && !preview.island.expanded && preview.pendingWork == 0,
               "preview-only mode responds promptly without expanding the panel")
        leave(preview)
        preview.advance(0.13)
        suite.expect(!preview.island.peeking, "a preview closes within 130 ms of leaving")

        for protect: (NotchIslandFixture) -> Void in [
            { $0.island.pinned = true }, { $0.island.fileDragChanged(true, internalDrag: true) },
            { $0.services.hasModalWindow = true }, { $0.island.presentCaptureControls(captureOptions(), cancel: {}) },
            { $0.host?.willPress?() }, { _ = $0.island.show(volume) }, { $0.island.fileDragChanged(true) },
            { lock($0) }, { $0.island.stop() },
            { _ in defaults.set(false, forKey: DefaultsKey.notchOpenOnHover) }
        ] {
            let protected = island()
            protected.island.hover(true)
            protect(protected)
            protected.advance(1)
            suite.expect(!protected.island.expanded && !protected.island.peeking,
                   "a pending hover rechecks eligibility before opening")
            // Capture controls follow the pointer for their own reasons.
            let capturing = protected.island.captureControls != nil
            protected.drift(to: CGPoint(x: protected.displays[0].frame.minX, y: protected.displays[0].frame.minY))
            suite.expect(capturing || !protected.watchesMovement,
                         "an aborted hover opening releases its pointer observers once the pointer moves away")
        }
        for protect: (NotchIslandFixture) -> Void in [
            { $0.island.pinned = true }, { $0.island.fileDragChanged(true, internalDrag: true) },
            { $0.services.hasModalWindow = true }, { $0.island.presentCaptureControls(captureOptions(), cancel: {}) },
            { lock($0) }, { $0.island.stop() }
        ] {
            let protected = island()
            protected.island.open(takeFocus: false)
            leave(protected)
            protect(protected)
            let presented = protected.host?.transitions.count ?? 0
            protected.advance(1)
            suite.expect(protected.host.map { !$0.transitions.dropFirst(presented).contains(.dismiss) } == true,
                   "a pending departure cannot interrupt pinning, dragging, capture, a menu or suspension")
        }
        let clicked = island()
        clicked.island.open()
        leave(clicked)
        clicked.advance(1)
        suite.expect(clicked.island.expanded, "a panel opened by click stays open when the pointer leaves")

        let keyboard = island()
        keyboard.island.open(takeFocus: false)
        leave(keyboard)
        keyboard.services.assistiveKeyboardActive = true
        keyboard.advance(1)
        expect(keyboard.island.expanded, "moving to the Accessibility Keyboard preserves the working panel")

        let popover = island()
        popover.island.open(takeFocus: false)
        let corner = popover.displays[0].frame.origin
        let child = NSWindow(contentRect: CGRect(origin: corner, size: CGSize(width: 240, height: 200)),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        child.alphaValue = 0
        child.ignoresMouseEvents = true
        child.isReleasedWhenClosed = false
        popover.host?.panel.addChildWindow(child, ordered: .above)
        child.orderFrontRegardless()
        leave(popover)
        popover.advance(1)
        expect(popover.island.expanded && child.isVisible,
               "moving into a popover hanging from the island keeps a hover-opened panel")
        popover.host?.panel.removeChildWindow(child)
        child.close()
        notificationContracts(volume: volume, expect: expect)
        trackNoticeContracts(expect: expect)
    }

    /// A new song's notice waits for playback to settle, and the compact
    /// strip keeps the song it showed until the notice covers it.
    private static func trackNoticeContracts(expect: (Bool, String) -> Void) {
        defaults.set(true, forKey: DefaultsKey.notchTrackChange)
        defer { defaults.set(false, forKey: DefaultsKey.notchTrackChange) }
        /// An island whose strip shows `title`, the pointer away from it.
        func showing(_ title: String?) -> NotchIslandFixture {
            let fixture = island(physical: true) { fixture in
                if let title { fixture.services.playback = song(title) }
            }
            fixture.pointer = CGPoint(x: 0, y: 0)
            return fixture
        }
        func changeSong(_ fixture: NotchIslandFixture, to title: String, playing: Bool = true) {
            fixture.services.playback = song(title, playing: playing)
            fixture.events.trackChanges.send()
        }
        let skipped = showing("Old")
        changeSong(skipped, to: "New")
        expect(skipped.island.heldMusic?.playback.track.title == "Old" && skipped.island.notice == nil,
               "a new song leaves the strip on the song it showed while the notice waits")
        skipped.advance(0.3)
        skipped.island.refreshPresentation(animated: false)
        changeSong(skipped, to: "Newer")
        skipped.advance(0.49)
        expect(skipped.island.heldMusic?.playback.track.title == "Old" && skipped.island.notice == nil,
               "skipping again restarts the wait and keeps the song still on screen")
        skipped.advance(0.02)
        expect(skipped.island.notice?.event == .track && skipped.island.notice?.title == "Newer"
               && skipped.island.heldMusic == nil,
               "the notice shows where playback settled and releases the strip behind it")
        for block: (NotchIslandFixture) -> Void in [{ $0.island.open() },
                                                     { $0.services.playback = song("New", playing: false) }] {
            let blocked = showing("Old")
            changeSong(blocked, to: "New")
            block(blocked)
            blocked.advance(0.5)
            expect(blocked.island.notice == nil && blocked.island.heldMusic == nil,
                   "a notice that cannot show releases the strip to the current song")
        }
        let hidden = showing(nil)
        changeSong(hidden, to: "New")
        expect(hidden.island.heldMusic == nil, "nothing is held when the strip was not on screen")

        // A long gap takes the strip away before the next song plays.
        let arriving = showing(nil)
        changeSong(arriving, to: "New")
        expect(arriving.island.compactActivity == nil && arriving.island.heldMusic == nil,
               "a new song with no strip song to keep waits for its notice too")
        arriving.advance(0.5)
        expect(arriving.island.notice?.title == "New",
               "the notice shows the song first, and the closed island may show it after, with its menu room read again")
        arriving.runScheduled()
        expect(arriving.island.compactActivity == .music, "once the notice has gone, the song takes the strip")
        let unnoticed = showing(nil)
        changeSong(unnoticed, to: "New")
        unnoticed.island.open()
        unnoticed.advance(0.5)
        unnoticed.island.collapse()
        expect(unnoticed.island.notice == nil && unnoticed.island.compactActivity == .music,
               "a song whose notice cannot show is released to the island at once")
        let kept = showing("Old")
        changeSong(kept, to: "New")
        expect(kept.island.compactActivity == .music && kept.island.heldMusic?.playback.track.title == "Old",
               "a song on the strip is kept in place instead")
        let ending = showing(nil)
        ending.events.trackEnds.send()
        expect(ending.island.heldMusic == nil, "nothing is held for a song that was not on the strip")
        let ended = showing("Old")
        ended.events.trackEnds.send()
        ended.services.playback = song("Other")
        ended.island.refreshPresentation(animated: false)
        ended.events.trackEnds.send()
        expect(ended.island.heldMusic?.playback.track.title == "Old",
               "a song that ends leaves the strip as the song it showed")
    }

    /// A mirrored banner arrives with its own dismissal pending, as `show`
    /// leaves it when the pointer is elsewhere.
    private static func notificationContracts(volume: NotchNotice, expect: (Bool, String) -> Void) {
        func banner(_ body: String = "Hello") -> NotchNotice {
            NotchNotice(event: .systemNotification, title: "Alex", detail: body, symbol: "bell.fill",
                        notification: NotchNotificationContent(app: "Chat", title: "Alex", subtitle: "", body: body),
                        notificationID: UUID())
        }
        let bannerTime = NotchEvent.systemNotification.duration
        /// Whether the banner's own dismissal is pending.
        func timed(_ fixture: NotchIslandFixture) -> Bool { fixture.pendingDelays.contains(bannerTime) }
        /// Shown while the pointer is elsewhere, then the pointer is back over the island.
        func arrive(_ fixture: NotchIslandFixture, _ notice: NotchNotice = banner()) {
            let resting = fixture.pointer
            fixture.pointer = CGPoint(x: fixture.displays[0].frame.minX, y: fixture.displays[0].frame.minY)
            _ = fixture.island.show(notice)
            fixture.pointer = resting
        }
        for physical in [false, true] {
            let service = island(physical: physical)
            arrive(service)
            service.island.hover(true)
            expect(!timed(service) && service.island.notice != nil,
                   "a banner under the pointer waits there like a native one instead of timing out")
            service.advance(0.20)
            expect(!service.island.noticeExpanded && !service.island.expanded, "the preview honors the activation delay")
            service.advance(0.06)
            expect(service.island.noticeExpanded && !service.island.expanded && service.pendingWork == 0,
                   "a deliberate hover opens the whole message in place rather than the island's page")
            expect(service.island.surfaceSize.width == service.island.geometry.notificationPreviewWidth
                   && service.island.surfaceSize.height > service.island.geometry.notice.height,
                   "the held preview grows into a card sized for its message")
            service.advance(5)
            expect(service.island.noticeExpanded && service.island.notice != nil,
                   "an opened preview stays as long as the pointer does")
            service.island.hover(true) // A tracking re-entry after the resize.
            expect(service.pendingWork == 0, "re-entry over an open preview schedules nothing")
            leave(service)
            service.advance(0.10)
            expect(service.island.notice != nil, "leaving gives the same short grace an expanded island gets")
            service.advance(0.09)
            expect(service.island.notice == nil && !service.island.noticeExpanded && !service.island.expanded,
                   "leaving an opened preview closes it without touching the island's page")
        }

        let pass = island()
        arrive(pass)
        pass.island.hover(true)
        pass.advance(0.10)
        leave(pass)
        pass.advance(0.20)
        expect(!pass.island.noticeExpanded && pass.island.notice != nil && timed(pass),
               "a quick pass neither opens the preview nor drops the banner")
        pass.advance(2.9)
        expect(pass.island.notice != nil, "after a pass the banner gets its full time again")
        pass.advance(0.2)
        expect(pass.island.notice == nil, "the restarted banner still ends on its own")

        let clickOnly = island()
        defaults.set(false, forKey: DefaultsKey.notchOpenOnHover)
        arrive(clickOnly)
        clickOnly.island.hover(true)
        clickOnly.advance(2)
        expect(!timed(clickOnly) && clickOnly.island.notice != nil && !clickOnly.island.noticeExpanded
               && clickOnly.pendingWork == 0,
               "click-only opening still holds the banner under the pointer without opening it")
        leave(clickOnly)
        clickOnly.advance(0.2)
        expect(clickOnly.island.notice != nil && timed(clickOnly), "the resumed banner counts from the moment the pointer left")
        clickOnly.advance(2.9)
        expect(clickOnly.island.notice != nil, "the resumed banner keeps its full duration")
        clickOnly.advance(0.2)
        expect(clickOnly.island.notice == nil, "a held banner resumes its timer once the pointer leaves")

        let preview = island()
        defaults.set(false, forKey: DefaultsKey.notchHoverExpands)
        arrive(preview)
        preview.island.hover(true)
        preview.advance(0.26)
        expect(preview.island.noticeExpanded && !preview.island.peeking,
               "hover-preview mode opens the message itself instead of the page strip")

        // A click on the island suppresses hover until the pointer leaves.
        let suppressed = island()
        arrive(suppressed)
        suppressed.host?.willPress?()
        suppressed.island.hover(true)
        suppressed.advance(1)
        expect(!suppressed.island.noticeExpanded && suppressed.island.notice != nil && !timed(suppressed),
               "a hover suppressed by a click still holds the banner but does not open it")

        let behind = island()
        behind.island.open()
        arrive(behind)
        behind.island.hover(true)
        expect(timed(behind) && !behind.island.noticeExpanded,
               "a banner hidden behind the open island keeps its own timer")

        for protect: (NotchIslandFixture) -> Void in [{ $0.services.hasModalWindow = true },
                                                       { $0.services.assistiveKeyboardActive = true }] {
            let held = island()
            arrive(held)
            held.island.hover(true)
            held.advance(0.26)
            expect(held.island.noticeExpanded, "precondition: the preview is open")
            protect(held)
            leave(held)
            held.advance(0.2)
            expect(held.island.notice == nil && !held.island.expanded,
                   "a dialog, menu or the Accessibility Keyboard keeps the island, never a banner the pointer left")
        }

        let hidden = island()
        hide(hidden)
        arrive(hidden)
        expect(hidden.island.notice == nil, "a hidden island takes no banner it cannot show")
        hidden.move(to: top(hidden))
        hidden.advance(0.26)
        expect(!hidden.island.noticeExpanded && hidden.island.expanded,
               "hidden mode reveals the island as usual instead of holding a banner it cannot show")
        defaults.set(false, forKey: DefaultsKey.notchHideUntilHover)

        // Notification replacement and preference changes run the production handlers.
        let exitRace = island()
        arrive(exitRace)
        exitRace.island.hover(true)
        exitRace.advance(0.26)
        leave(exitRace)
        exitRace.advance(0.05)
        let fresh = banner("Fresh message after exit")
        expect(exitRace.island.show(fresh), "a new notification is accepted after exit")
        exitRace.advance(0.14)
        expect(exitRace.island.notice?.notificationID == fresh.notificationID,
               "new notification must survive the previous preview exit deadline")
        expect(!exitRace.island.noticeExpanded && timed(exitRace),
               "a new message outside the pointer starts as a timed banner")
        exitRace.advance(2.9)
        expect(exitRace.island.notice == nil, "the replacement closes after its own full display time")

        let whileInside = island()
        arrive(whileInside)
        whileInside.island.hover(true)
        whileInside.advance(0.26)
        let freshInside = banner("Fresh message while inside")
        expect(whileInside.island.show(freshInside), "a new notification is accepted inside")
        whileInside.advance(5)
        expect(whileInside.island.notice?.notificationID == freshInside.notificationID && whileInside.island.noticeExpanded,
               "replacing a held notification inside keeps the new message readable")
        leave(whileInside)
        whileInside.advance(0.2)
        expect(whileInside.island.notice == nil, "leaving the replacement closes its preview")

        let preferenceChange = island()
        arrive(preferenceChange)
        preferenceChange.island.hover(true)
        preferenceChange.advance(0.26)
        hide(preferenceChange)
        leave(preferenceChange)
        preferenceChange.advance(10)
        expect(preferenceChange.island.notice == nil || timed(preferenceChange),
               "enabling hidden mode must release the held notification after pointer exit")
        defaults.set(false, forKey: DefaultsKey.notchHideUntilHover)
        preferenceChange.island.syncWithPreferences()
        expect(!preferenceChange.island.noticeExpanded,
               "returning from hidden mode must not resurrect a preview with the pointer elsewhere")

        for expandedPreview in [false, true] {
            let disabled = island()
            arrive(disabled)
            disabled.island.hover(true)
            if expandedPreview { disabled.advance(0.26) }
            defaults.set(false, forKey: NotchEvent.systemNotification.preferenceKey)
            disabled.island.syncWithPreferences()
            disabled.advance(5)
            expect(disabled.island.notice == nil && disabled.pendingWork == 0 && !disabled.island.noticeExpanded,
                   "disabling notification routing clears both a pending and an open preview")
            defaults.set(true, forKey: NotchEvent.systemNotification.preferenceKey)
        }
        let unchanged = island()
        arrive(unchanged)
        unchanged.island.hover(true)
        unchanged.advance(0.26)
        unchanged.island.syncWithPreferences()
        expect(unchanged.island.noticeExpanded && unchanged.island.notice != nil,
               "an unrelated preference sync preserves a readable notification")

        let closingPeek = island()
        defaults.set(false, forKey: DefaultsKey.notchHoverExpands)
        closingPeek.island.hover(true)
        closingPeek.advance(0.26)
        defaults.set(true, forKey: DefaultsKey.notchHoverExpands)
        arrive(closingPeek, volume)
        leave(closingPeek)
        defaults.set(false, forKey: NotchEvent.volume.preferenceKey)
        closingPeek.island.syncWithPreferences()
        closingPeek.advance(0.2)
        expect(!closingPeek.island.peeking && closingPeek.island.notice == nil,
               "disabling feedback preserves the island's already scheduled pointer-exit close")
        defaults.set(true, forKey: NotchEvent.volume.preferenceKey)

        let replaced = island()
        arrive(replaced)
        replaced.island.hover(true)
        replaced.advance(0.26)
        expect(replaced.island.noticeExpanded, "precondition: the preview is open")
        _ = replaced.island.show(volume)
        leave(replaced)
        replaced.advance(0.2)
        expect(replaced.island.notice?.event == .volume && replaced.pendingDelays.contains(volume.event.duration),
               "leaving after a different notice took over never touches that notice")

        let overPeek = island()
        defaults.set(false, forKey: DefaultsKey.notchHoverExpands)
        let peekResting = overPeek.island.surfaceSize
        overPeek.island.hover(true)
        overPeek.advance(0.26)
        expect(overPeek.island.peeking, "precondition: the peek strip is open")
        expect(overPeek.island.show(banner("While peeking")), "a message is accepted over the peek strip")
        overPeek.advance(0.26)
        expect(overPeek.island.noticeExpanded && !overPeek.island.peeking,
               "a message arriving over the peek strip opens as a preview in its place")
        leave(overPeek)
        overPeek.advance(0.2)
        expect(overPeek.island.notice == nil && !overPeek.island.peeking && !overPeek.island.expanded
               && overPeek.island.surfaceSize == peekResting,
               "closing that preview returns the island to rest without a stale peek strip")
        defaults.set(true, forKey: DefaultsKey.notchHoverExpands)

        let pendingOpen = island()
        pendingOpen.island.hover(true)
        pendingOpen.advance(0.10)
        expect(pendingOpen.island.show(banner("Before the island opens")),
               "a message is accepted while an opening is pending")
        pendingOpen.advance(0.20)
        expect(!pendingOpen.island.expanded && !pendingOpen.island.noticeExpanded,
               "the pending opening yields to the banner and the preview waits its own delay")
        pendingOpen.advance(0.06)
        expect(!pendingOpen.island.expanded && pendingOpen.island.noticeExpanded,
               "the banner then opens as a preview instead of the island")

        let interrupted = island()
        arrive(interrupted)
        interrupted.island.hover(true)
        interrupted.advance(0.26)
        expect(interrupted.island.show(volume) && interrupted.island.notice?.event == .volume
               && !interrupted.island.noticeExpanded,
               "volume feedback takes the place of an open preview as a plain notice")
        interrupted.advance(1.7)
        expect(interrupted.island.notice == nil, "that feedback ends on its own")
        // The pointer never left, so nothing may be waiting to open the island.
        interrupted.runScheduled()
        expect(!interrupted.island.expanded && !interrupted.island.peeking && !interrupted.island.noticeExpanded,
               "and leaves nothing pending")
        leave(interrupted)
        interrupted.advance(0.2)
        expect(!interrupted.island.expanded && interrupted.island.notice == nil,
               "leaving afterwards has nothing left to close")

        // A new reading of the same level only fits its width; another notice
        // takes its place the usual way.
        let reading = island()
        leave(reading)
        let full = NotchNotice(event: .volume, title: "Volume", detail: "100%", symbol: "speaker.wave.3.fill", level: 1)
        let bright = NotchNotice(event: .brightness, title: "Brightness", detail: "100%", symbol: "sun.max.fill", level: 1)
        expect(reading.island.show(volume) && reading.host?.steadies.last == false,
               "a level shown on its own arrives the usual way")
        expect(reading.island.show(full) && reading.host?.steadies.last == true,
               "a new reading of the same level eases to its width in place")
        expect(reading.island.show(bright) && reading.host?.steadies.last == false,
               "another kind of notice replaces it the usual way")

        // A burst keeps the banner's width, so the island does not resize
        // with each message and a banner held near its end stays in reach.
        let wide = banner(String(repeating: "A long message in a busy chat ", count: 8))
        let burst = island()
        leave(burst)
        expect(burst.island.show(wide) && burst.island.show(banner("ok")), "precondition: a burst replaces the banner")
        expect(burst.island.surfaceSize == burst.island.geometry.noticeSize(wings: wide.wings(in: burst.island.geometry)),
               "a message replacing a banner still on screen keeps its width")
        burst.advance(3.1)
        let alone = banner("ok")
        expect(burst.island.notice == nil && burst.island.show(alone) && alone.preferredWingWidth < wide.preferredWingWidth
               && burst.island.surfaceSize == burst.island.geometry.noticeSize(wings: alone.wings(in: burst.island.geometry)),
               "the next message on its own takes only the width it needs")
        let held = island()
        leave(held)
        expect(held.island.show(wide), "precondition: a wide banner is shown")
        let frame = held.island.geometry.frame(for: held.island.surfaceSize)
        held.pointer = CGPoint(x: frame.maxX - 4, y: frame.midY)
        held.island.hover(true)
        expect(held.island.show(banner("ok")) && held.host?.containsHover(held.pointer) == true && !timed(held),
               "a message arriving over a banner held near its end stays under the pointer")
    }
}
