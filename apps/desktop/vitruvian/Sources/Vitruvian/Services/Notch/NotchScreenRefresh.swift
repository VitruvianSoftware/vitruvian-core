// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// Keeping the island current as the displays, the app in front and the
/// preferences change: one deferred pass per burst of preference or screen
/// notifications, the menu reader run only while the island can use what it
/// measures, what another app coming forward does to the island, and moving
/// the closed island to another display.
@MainActor
package final class NotchScreenRefresh {
    /// The main queue, Accessibility, the menu preference, the app in front
    /// and the pointer. The app passes `.system`.
    package struct Environment {
        /// Runs work on the main queue after a delay, zero for the next turn.
        package var schedule: @MainActor (_ delay: TimeInterval, _ work: DispatchWorkItem) -> Void
        package var accessibilityGranted: @MainActor () -> Bool
        /// The island may sit over the menus (`NotchSupport.coversMenus()`).
        package var coversMenus: @MainActor () -> Bool
        package var frontmostBundleID: @MainActor () -> String?
        /// This app, whose own activation keeps its island.
        package var ownBundleID: String?
        package var mouseLocation: @MainActor () -> CGPoint

        package init(schedule: @escaping @MainActor (TimeInterval, DispatchWorkItem) -> Void,
                     accessibilityGranted: @escaping @MainActor () -> Bool,
                     coversMenus: @escaping @MainActor () -> Bool,
                     frontmostBundleID: @escaping @MainActor () -> String?,
                     ownBundleID: String?,
                     mouseLocation: @escaping @MainActor () -> CGPoint) {
            self.schedule = schedule
            self.accessibilityGranted = accessibilityGranted
            self.coversMenus = coversMenus
            self.frontmostBundleID = frontmostBundleID
            self.ownBundleID = ownBundleID
            self.mouseLocation = mouseLocation
        }

        @MainActor package static var system: Environment {
            Environment(
                schedule: { delay, work in
                    if delay > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                    } else {
                        DispatchQueue.main.async(execute: work)
                    }
                },
                accessibilityGranted: { AXIsProcessTrusted() },
                coversMenus: { NotchSupport.coversMenus() },
                frontmostBundleID: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
                ownBundleID: Bundle.main.bundleIdentifier,
                mouseLocation: { NSEvent.mouseLocation })
        }
    }

    /// The island's side: what it is doing, and what it does when asked.
    package struct Island {
        package var running: () -> Bool
        package var suspended: () -> Bool
        package var hiddenInFullscreen: () -> Bool
        package var hiddenUntilHover: () -> Bool
        package var expanded: () -> Bool
        package var peeking: () -> Bool
        package var showsNotice: () -> Bool
        package var showsCaptureControls: () -> Bool
        package var holdsDrag: () -> Bool
        package var choosingFileDropDestination: () -> Bool
        package var keepsWorkingSurface: () -> Bool
        /// A song held for its New track notice keeps its old display's geometry.
        package var holdsMusic: () -> Bool
        package var pinned: () -> Bool
        package var openedByHover: () -> Bool
        package var clickedSinceOpening: () -> Bool
        package var showsClipboard: () -> Bool
        package var idleContent: () -> NotchIdleContent
        package var hasCompactActivity: () -> Bool
        package var geometry: () -> NotchGeometry
        /// Displays that share Spaces show the menu bar on the main one only.
        package var displayHasMenuBar: () -> Bool
        package var containsHover: (CGPoint) -> Bool

        package var syncWithPreferences: () -> Void
        package var fullscreenEnvironmentDidChange: () -> Void
        /// The room the menus leave beside the camera (`applyMenuSpace`).
        package var applyMenuSpace: (CGFloat?) -> Void
        /// Forgets the measured room and redraws without it.
        package var withdrawMenuSpace: () -> Void
        package var refreshPresentation: () -> Void
        package var resignKey: () -> Void
        package var rememberPasteTarget: () -> Void
        package var collapse: () -> Void
        /// Takes `displayID` and lays the island out on it (`updateScreen`).
        package var takeDisplay: (CGDirectDisplayID) -> Void
        package var syncVisibleConsumers: () -> Void

        /// The menu reader (`NotchMenuSpaceReader`).
        package var startMenuSpace: () -> Void
        package var stopMenuSpace: () -> Void
        package var invalidateMenuSpace: () -> Void
        package var readMenuSpace: () -> Void

        package init(running: @escaping () -> Bool, suspended: @escaping () -> Bool,
                     hiddenInFullscreen: @escaping () -> Bool, hiddenUntilHover: @escaping () -> Bool,
                     expanded: @escaping () -> Bool, peeking: @escaping () -> Bool,
                     showsNotice: @escaping () -> Bool, showsCaptureControls: @escaping () -> Bool,
                     holdsDrag: @escaping () -> Bool, choosingFileDropDestination: @escaping () -> Bool,
                     keepsWorkingSurface: @escaping () -> Bool, holdsMusic: @escaping () -> Bool,
                     pinned: @escaping () -> Bool, openedByHover: @escaping () -> Bool,
                     clickedSinceOpening: @escaping () -> Bool, showsClipboard: @escaping () -> Bool,
                     idleContent: @escaping () -> NotchIdleContent, hasCompactActivity: @escaping () -> Bool,
                     geometry: @escaping () -> NotchGeometry, displayHasMenuBar: @escaping () -> Bool,
                     containsHover: @escaping (CGPoint) -> Bool,
                     syncWithPreferences: @escaping () -> Void,
                     fullscreenEnvironmentDidChange: @escaping () -> Void,
                     applyMenuSpace: @escaping (CGFloat?) -> Void, withdrawMenuSpace: @escaping () -> Void,
                     refreshPresentation: @escaping () -> Void, resignKey: @escaping () -> Void,
                     rememberPasteTarget: @escaping () -> Void, collapse: @escaping () -> Void,
                     takeDisplay: @escaping (CGDirectDisplayID) -> Void,
                     syncVisibleConsumers: @escaping () -> Void,
                     startMenuSpace: @escaping () -> Void, stopMenuSpace: @escaping () -> Void,
                     invalidateMenuSpace: @escaping () -> Void, readMenuSpace: @escaping () -> Void) {
            self.running = running
            self.suspended = suspended
            self.hiddenInFullscreen = hiddenInFullscreen
            self.hiddenUntilHover = hiddenUntilHover
            self.expanded = expanded
            self.peeking = peeking
            self.showsNotice = showsNotice
            self.showsCaptureControls = showsCaptureControls
            self.holdsDrag = holdsDrag
            self.choosingFileDropDestination = choosingFileDropDestination
            self.keepsWorkingSurface = keepsWorkingSurface
            self.holdsMusic = holdsMusic
            self.pinned = pinned
            self.openedByHover = openedByHover
            self.clickedSinceOpening = clickedSinceOpening
            self.showsClipboard = showsClipboard
            self.idleContent = idleContent
            self.hasCompactActivity = hasCompactActivity
            self.geometry = geometry
            self.displayHasMenuBar = displayHasMenuBar
            self.containsHover = containsHover
            self.syncWithPreferences = syncWithPreferences
            self.fullscreenEnvironmentDidChange = fullscreenEnvironmentDidChange
            self.applyMenuSpace = applyMenuSpace
            self.withdrawMenuSpace = withdrawMenuSpace
            self.refreshPresentation = refreshPresentation
            self.resignKey = resignKey
            self.rememberPasteTarget = rememberPasteTarget
            self.collapse = collapse
            self.takeDisplay = takeDisplay
            self.syncVisibleConsumers = syncVisibleConsumers
            self.startMenuSpace = startMenuSpace
            self.stopMenuSpace = stopMenuSpace
            self.invalidateMenuSpace = invalidateMenuSpace
            self.readMenuSpace = readMenuSpace
        }
    }

    private let environment: Environment
    private let island: Island
    private var preferenceSyncWork: DispatchWorkItem?
    private var screenRefreshWork: DispatchWorkItem?

    package init(environment: Environment, island: Island) {
        self.environment = environment
        self.island = island
    }

    package var hasPendingPreferenceSync: Bool { preferenceSyncWork != nil }
    package var hasPendingScreenRefresh: Bool { screenRefreshWork != nil }

    /// AppStorage can notify during drawing. A preference import or a group
    /// of edits only needs one deferred pass over the final saved settings.
    package func schedulePreferenceSync() {
        guard island.running(), preferenceSyncWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.preferenceSyncWork = nil
            guard self.island.running() else { return }
            self.island.syncWithPreferences()
        }
        preferenceSyncWork = work
        environment.schedule(0, work)
    }

    /// A pass of its own is running, or the island stopped.
    package func cancelPreferenceSync() {
        preferenceSyncWork?.cancel(); preferenceSyncWork = nil
    }

    /// Display changes arrive in bursts, brightness included; the island
    /// refreshes once they settle.
    package func screenParametersDidChange() {
        guard island.running(), !island.suspended() else { return }
        screenRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.screenRefreshWork = nil
            guard self.island.running(), !self.island.suspended() else { return }
            self.invalidateMenuSpace()
            self.island.syncWithPreferences()
        }
        screenRefreshWork = work
        environment.schedule(0.1, work)
    }

    package func cancelScreenRefresh() {
        screenRefreshWork?.cancel(); screenRefreshWork = nil
    }

    package func invalidateMenuSpace() {
        island.invalidateMenuSpace()
        // Keep the last measured layout until its replacement arrives, so a
        // switch does not blink; the read that follows withdraws the cutout
        // once the new menu bar reaches the camera.
        island.readMenuSpace()
    }

    package func syncMenuSpaceMonitoring() {
        guard !island.hiddenInFullscreen() else { island.stopMenuSpace(); return }
        let geometry = island.geometry()
        // The explicit cover-menus choice also keeps a simulated island at
        // rest. Otherwise its visibility follows AX menu measurements, which
        // can change just because focus moves to another app or display.
        // A display without a menu bar, beside the main one when displays
        // share Spaces, has no menus to leave room for either.
        if island.running(), !island.suspended(), environment.coversMenus() || !island.displayHasMenuBar() {
            // Nothing to measure: the island keeps the room an empty bar
            // would leave it, over whatever menus and status items are there.
            island.stopMenuSpace()
            island.applyMenuSpace(NotchMenuBarLayout.sideRoom(screen: geometry.screen, cameraWidth: geometry.cameraWidth,
                                                              barHeight: geometry.menuBarHeight, occupied: []))
            return
        }
        guard environment.accessibilityGranted() else {
            island.stopMenuSpace()
            if geometry.compactSideRoom != nil { island.withdrawMenuSpace() }
            return
        }
        let wanted = island.running() && !island.suspended() && !island.hiddenUntilHover() && !island.expanded()
            && !island.showsCaptureControls()
            && (island.idleContent() != .none || island.hasCompactActivity() || !geometry.isNotched)
        guard wanted else { island.stopMenuSpace(); return }
        island.startMenuSpace()
    }

    package func applicationDidActivate() {
        guard !island.suspended() else { return }
        island.fullscreenEnvironmentDidChange()
        invalidateMenuSpace()
        let identifier = environment.frontmostBundleID()
        guard identifier != environment.ownBundleID, identifier != AssistiveKeyboard.bundleID else { return }
        island.resignKey()
        if island.expanded(), island.showsClipboard() { island.rememberPasteTarget() }
        if island.expanded(), !island.pinned(), !island.keepsWorkingSurface(), !island.showsCaptureControls(),
           NotchSupport.closesOnActivation(openedByHover: island.openedByHover(), clicked: island.clickedSinceOpening(),
                                           pointerInside: island.containsHover(environment.mouseLocation())) {
            island.collapse()
        }
    }

    /// Only a closed island at rest follows the pointer to another display.
    package var canFollowPointer: Bool {
        !island.expanded() && !island.peeking() && !island.showsNotice() && !island.showsCaptureControls()
            && !island.holdsDrag() && !island.choosingFileDropDestination() && !island.keepsWorkingSurface()
            && !island.holdsMusic()
    }

    package func move(to displayID: CGDirectDisplayID) {
        island.takeDisplay(displayID)
        // The menu space measured so far belongs to the display it left.
        invalidateMenuSpace()
        island.syncVisibleConsumers()
        island.refreshPresentation()
    }
}
