// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

extension NotchPresentationRefreshContract {
    /// The module's capture controls on a real island, with an inert window
    /// and the fixture's clock. Pointer locations are values only; no events
    /// or windows reach the desktop.
    static func captureControlsChecks(_ suite: TestSuite) {
        /// Presents the controls as a capture does: compact, with a pointer
        /// already resting on them held back until it leaves.
        func begin(pointerInside: Bool = false, before: (NotchIslandFixture) -> Void = { _ in }) -> NotchIslandFixture {
            let fixture = island(before: before)
            fixture.pointer = pointerInside ? onIsland : away
            fixture.island.presentCaptureControls(captureOptions(), cancel: {})
            return fixture
        }
        func move(_ fixture: NotchIslandFixture, inside: Bool) {
            fixture.move(to: inside ? onIsland : away)
        }

        // Both previews arrive through presentCapture, as the screenshot
        // preview sends them, so whether one stays until dismissed comes
        // from what it was presented with.
        let persistent = island()
        var persistentCloseCount = 0
        var persistentClosedAfterTakeover = false
        let persistentShown = persistent.island.presentCapture(
            id: UUID(), content: AnyView(EmptyView()), height: 120, takeFocus: false, closeOnCollapse: true,
            fallback: {}, close: {
                persistentCloseCount += 1
                persistentClosedAfterTakeover = persistent.island.captureControls != nil
                    && persistent.island.captureContent == nil
            }, hover: { _ in })
        suite.expect(persistentShown && persistent.island.expanded && persistent.island.selected == .captures
                     && persistent.host?.hasKeyboard == false,
                     "a preview that stays until dismissed opens the captures page without the keyboard")
        persistent.island.presentCaptureControls(captureOptions(), cancel: {})
        suite.expect(persistentCloseCount == 1 && persistentClosedAfterTakeover,
                     "capture controls detach a persistent preview before closing it after island takeover")
        persistent.island.endCaptureControls()

        let timed = island()
        var timedCloseCount = 0
        _ = timed.island.presentCapture(
            id: UUID(), content: AnyView(EmptyView()), height: 120, takeFocus: true, closeOnCollapse: false,
            fallback: {}, close: { timedCloseCount += 1 }, hover: { _ in })
        suite.expect(timed.host?.hasKeyboard == true,
                     "a timed preview that prefers the keyboard asks the island for it")
        timed.island.presentCaptureControls(captureOptions(), cancel: {})
        suite.expect(timedCloseCount == 0 && timed.island.captureContent != nil,
                     "capture controls leave a timed preview owned by its existing dismissal timer")
        timed.island.endCaptureControls()

        let idle = begin()
        var surfaceUpdates: [(CGRect, CGFloat)] = []
        idle.island.captureControls?.onCaptureControlsSurfaceChange = { surfaceUpdates.append(($0, $1)) }
        idle.island.refreshPresentation(animated: false)
        let compactSurfaceBottom = idle.island.geometry.floatingDrop + idle.island.surfaceSize.height
        suite.expect(surfaceUpdates.last?.0 == idle.island.geometry.screen
               && surfaceUpdates.last?.1 == compactSurfaceBottom,
               "compact capture controls publish their bottom edge to the selection overlay")
        for _ in 0..<8 {
            idle.advance(0.5)
            move(idle, inside: false)
        }
        suite.expect(idle.island.captureControlsCollapsed && idle.island.captureControls != nil,
               "capture controls start compact and stay so while the pointer selects elsewhere")
        suite.expect(idle.host?.panel.isVisible == true && idle.host?.activationRect.isEmpty == false,
               "compact capture controls keep a clickable target that opens them")
        move(idle, inside: true)
        idle.advance(0.2)
        suite.expect(idle.island.captureControlsCollapsed, "a brief pass over the compact target does not open controls")
        idle.advance(0.1)
        suite.expect(!idle.island.captureControlsCollapsed, "a deliberate hover opens the controls")
        let openSurfaceBottom = idle.island.geometry.floatingDrop + idle.island.surfaceSize.height
        suite.expect(surfaceUpdates.last?.1 == openSurfaceBottom
               && openSurfaceBottom > compactSurfaceBottom,
               "opening capture controls republishes their larger bottom edge")

        move(idle, inside: true)
        suite.expect(idle.host?.panel.acceptsMouseMovedEvents == true && idle.host?.panel.ignoresMouseEvents == false,
               "expanded controls retain movement delivery so their transparent edges cannot swallow the next selection")
        idle.advance(6)
        suite.expect(!idle.island.captureControlsCollapsed, "controls stay open while the pointer uses them")
        move(idle, inside: false)
        idle.advance(0.1)
        move(idle, inside: true)
        idle.advance(1)
        suite.expect(!idle.island.captureControlsCollapsed,
                     "a pointer that slips off and returns at once keeps the controls open")
        move(idle, inside: false)
        idle.advance(0.1)
        move(idle, inside: false)
        idle.advance(0.1)
        suite.expect(idle.island.captureControlsCollapsed && idle.island.captureControls != nil,
               "leaving the controls closes them soon, however the pointer moves, without cancelling the capture")
        suite.expect(surfaceUpdates.last?.1 == compactSurfaceBottom,
               "leaving capture controls republishes their compact bottom edge")

        idle.host?.activate?()
        suite.expect(!idle.island.captureControlsCollapsed, "the compact activation target opens capture controls")
        idle.advance(2.5)
        suite.expect(!idle.island.captureControlsCollapsed,
               "controls opened with the pointer elsewhere wait for a control to take keyboard focus")
        idle.advance(1)
        suite.expect(idle.island.captureControlsCollapsed,
                     "controls opened with the pointer elsewhere close when none does")

        move(idle, inside: true)
        idle.advance(0.3)
        suite.expect(!idle.island.captureControlsCollapsed, "hovering again after the controls closed opens them")
        let expandedFrame = idle.host!.frame
        idle.island.collapseCaptureControls()
        move(idle, inside: true)
        suite.expect(idle.host?.panel.acceptsMouseMovedEvents == true && idle.host?.panel.ignoresMouseEvents == false,
               "the compact target still reports the movement that exits its controls")
        idle.advance(1)
        suite.expect(idle.island.captureControlsCollapsed,
                     "manual collapse cannot immediately reopen under a stationary pointer")
        idle.host?.animatingFrame = expandedFrame
        idle.move(to: CGPoint(x: expandedFrame.midX, y: expandedFrame.minY + 1))
        suite.expect(idle.host?.panel.ignoresMouseEvents == true && idle.host?.panel.acceptsMouseMovedEvents == false,
               "the disappearing part of a collapsing window cannot swallow a selection click")
        idle.host?.animatingFrame = nil
        move(idle, inside: false)
        suite.expect(idle.host?.panel.acceptsMouseMovedEvents == false && idle.host?.panel.ignoresMouseEvents == true,
               "leaving the compact target returns pointer delivery to the selection surface")
        move(idle, inside: true)
        idle.advance(0.3)
        suite.expect(!idle.island.captureControlsCollapsed, "a deliberate hover reopens the same capture")

        idle.island.captureControls?.hasFocusedControl = true
        idle.island.scheduleCaptureControlsCollapse()
        move(idle, inside: false)
        idle.advance(6)
        suite.expect(!idle.island.captureControlsCollapsed,
                     "keyboard editing keeps the controls open after the pointer leaves")
        idle.island.captureControls?.hasFocusedControl = false
        idle.island.scheduleCaptureControlsCollapse()
        idle.advance(3)
        suite.expect(idle.island.captureControlsCollapsed, "leaving keyboard controls restores the idle deadline")

        // The selection overlay reports a drag through the options.
        idle.island.expandCaptureControls()
        idle.island.captureControls?.onSelectionProgressChange?(true)
        suite.expect(idle.island.captureControlsCollapsed && idle.host?.panel.isVisible == false
               && idle.host?.panel.ignoresMouseEvents == true && idle.host?.panel.acceptsMouseMovedEvents == false,
               "starting selection immediately removes the entire capture window and its hit target")
        move(idle, inside: true)
        idle.island.expandCaptureControls()
        idle.advance(4)
        idle.island.refreshPresentation()
        suite.expect(idle.host?.panel.isVisible == false && idle.island.captureControlsCollapsed,
               "hover, reopening actions and presentation refresh cannot obscure a live drag")
        move(idle, inside: false)
        idle.island.captureControls?.onSelectionProgressChange?(false)
        suite.expect(idle.host?.panel.isVisible == true && idle.island.captureControlsCollapsed,
               "an empty selection restores only the compact target for another attempt")
        move(idle, inside: true)
        idle.island.endCaptureControls()
        let keyRequests = idle.host?.keyboardRequests
        idle.advance(5)
        suite.expect(idle.island.captureControls == nil && idle.host?.keyboardRequests == keyRequests,
               "ending capture cancels a pending hover without reopening anything")
        suite.expect(idle.pendingWork == 0 && !idle.watchesMovement,
               "capture teardown leaves no scheduled work or capture monitors")

        let replaced = begin()
        replaced.island.expandCaptureControls()
        let oldOptions = replaced.island.captureControls
        let oldDeadline = replaced.scheduled.last?.work
        replaced.island.endCaptureControls()
        replaced.island.presentCaptureControls(captureOptions(), cancel: {})
        replaced.island.expandCaptureControls()
        withExtendedLifetime(oldOptions) { oldDeadline?.perform() }
        suite.expect(oldDeadline != nil && !replaced.island.captureControlsCollapsed,
               "even a delivered stale callback cannot collapse a replacement session")
        replaced.island.endCaptureControls()

        // A lowered capsule on a display without a camera housing.
        defaults.set(NotchSilhouette.capsule.rawValue, forKey: DefaultsKey.notchSilhouette)
        defaults.set(12.0, forKey: DefaultsKey.notchCapsuleFitDrop)
        let dropped = island(physical: false, room: 64)
        defaults.set(NotchSilhouette.notch.rawValue, forKey: DefaultsKey.notchSilhouette)
        defaults.removeObject(forKey: DefaultsKey.notchCapsuleFitDrop)
        dropped.island.presentCaptureControls(captureOptions(), cancel: {})
        var droppedSurface: (CGRect, CGFloat)?
        dropped.island.captureControls?.onCaptureControlsSurfaceChange = { droppedSurface = ($0, $1) }
        dropped.island.refreshPresentation(animated: false)
        suite.expect(dropped.island.geometry.floatingDrop > 0
               && droppedSurface?.0 == dropped.island.geometry.screen
               && droppedSurface?.1 == dropped.island.geometry.floatingDrop + dropped.island.surfaceSize.height,
               "a lowered capsule publishes its drop plus height so it cannot cover the full-screen action")
        dropped.island.endCaptureControls()

        let resting = begin(pointerInside: true)
        resting.advance(1)
        suite.expect(resting.island.captureControlsCollapsed,
                     "a pointer already on the island when capture starts does not open the controls")
        move(resting, inside: false)
        move(resting, inside: true)
        resting.advance(0.3)
        suite.expect(!resting.island.captureControlsCollapsed, "once that pointer leaves, hovering opens the controls")
        resting.island.endCaptureControls()

        let missionControl = begin()
        let host = missionControl.host!
        host.concealForMissionControl()
        missionControl.island.endCaptureControls()
        suite.expect(host.input.askedWhileConcealed == false && host.panel.ignoresMouseEvents == true,
                     "ending capture updates the saved input policy while Mission Control keeps the panel click-through")
        host.restoreFromMissionControl()
        suite.expect(host.panel.ignoresMouseEvents == false,
                     "the resting island accepts clicks again after Mission Control")
        suite.expect(host.panel.isVisible == host.input.restoring,
                     "a visible island stays marked as restoring while it fades back in")
        host.finishMissionControlFade()
        suite.expect(!host.input.restoring, "the finished fade ends the restore")

        let moving = begin()
        move(moving, inside: true)
        let movingHost = moving.host!
        movingHost.concealForMissionControl()
        move(moving, inside: true)
        suite.expect(movingHost.input.askedWhileConcealed && moving.host?.panel.ignoresMouseEvents == true,
                     "a concealed hit test cannot determine the saved capture input policy")
        movingHost.restoreFromMissionControl()
        suite.expect(moving.host?.panel.ignoresMouseEvents == false && moving.host?.panel.acceptsMouseMovedEvents == true,
                     "restoring Mission Control recomputes the capture policy for a pointer over the controls")
        movingHost.concealForMissionControl()
        moving.pointer = away
        movingHost.restoreFromMissionControl()
        suite.expect(moving.host?.panel.ignoresMouseEvents == true && moving.host?.panel.acceptsMouseMovedEvents == false,
                     "restoring Mission Control also handles a pointer that moved away without a local event")
        moving.island.endCaptureControls()

        var hidden = NotchWindowInputPolicy()
        _ = hidden.present(hidingWhenSettled: true, panelIgnores: false)
        let hiddenIgnores = hidden.ask(ignored: false)
        suite.expect(hiddenIgnores && hidden.askedBeforeHide == false,
                     "a hidden island retains its new input policy for the next reveal")
    }
}
