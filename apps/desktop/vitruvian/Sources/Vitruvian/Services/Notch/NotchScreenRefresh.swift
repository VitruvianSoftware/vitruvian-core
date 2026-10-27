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
        /// Hidden until hover, the island still shows its activities
        /// (`NotchSupport.hiddenShowsActivity()`).
        package var hiddenShowsActivity: @MainActor () -> Bool
        package var frontmostBundleID: @MainActor () -> String?
        /// This app, whose own activation keeps its island.
        package var ownBundleID: String?
        package var mouseLocation: @MainActor () -> CGPoint

        package init(schedule: @escaping @MainActor (TimeInterval, DispatchWorkItem) -> Void,
                     accessibilityGranted: @escaping @MainActor () -> Bool,
                     coversMenus: @escaping @MainActor () -> Bool,
                     hiddenShowsActivity: @escaping @MainActor () -> Bool,
                     frontmostBundleID: @escaping @MainActor () -> String?,
                     ownBundleID: String?,
                     mouseLocation: @escaping @MainActor () -> CGPoint) {
            self.schedule = schedule
            self.accessibilityGranted = accessibilityGranted
            self.coversMenus = coversMenus
            self.hiddenShowsActivity = hiddenShowsActivity
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
                hiddenShowsActivity: { NotchSupport.hiddenShowsActivity() },
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
        /// Takes `displayID`, without laying the island out on it yet.
        package var selectDisplay: (CGDirectDisplayID) -> Void
        /// Lays the island out on the display it has taken, or on the one the
        /// preferences choose instead (`updateScreen`).
        package var updateScreen: () -> Void
        package var currentDisplayID: () -> CGDirectDisplayID?
        /// Whether an attached display has this identifier.
        package var displayExists: (CGDirectDisplayID?) -> Bool
        package var syncVisibleConsumers: () -> Void

        /// The island's window, by identity: a move waiting for its turn must
        /// not act on a window that replaced the one it was started for.
        package var hostIdentity: () -> AnyObject?
        /// The window is on screen now, and may leave and come back.
        package var canRelocateOnScreen: () -> Bool
        /// Orders the window out so its frame moves offscreen; false when it
        /// was not on screen.
        package var orderOutForRelocation: () -> Bool
        package var orderFrontForRelocation: () -> Void
        package var cancelHostRelocation: () -> Void
        package var hideHost: () -> Void
        /// The copies of the island on the other displays.
        package var syncMirrors: () -> Void
        package var syncScreenEdgeClicks: () -> Void
        /// The music wave across a move: drawn on the copy about to be
        /// uncovered, repeated by the window covering it, kept on the copy
        /// leaving, then let go.
        package var holdWave: (CGDirectDisplayID) -> Void
        package var matchWave: () -> Void
        package var keepWave: () -> Void
        package var releaseWave: () -> Void

        /// The menu reader (`NotchMenuSpaceReader`).
        package var startMenuSpace: () -> Void
        package var stopMenuSpace: () -> Void
        package var invalidateMenuSpace: () -> Void
        package var readMenuSpace: () -> Void
        /// The companion is on, and needs the menus measured to know where
        /// its wings fit.
        package var mascotWantsRoom: () -> Bool

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
                     selectDisplay: @escaping (CGDirectDisplayID) -> Void,
                     updateScreen: @escaping () -> Void,
                     currentDisplayID: @escaping () -> CGDirectDisplayID?,
                     displayExists: @escaping (CGDirectDisplayID?) -> Bool,
                     syncVisibleConsumers: @escaping () -> Void,
                     hostIdentity: @escaping () -> AnyObject?,
                     canRelocateOnScreen: @escaping () -> Bool,
                     orderOutForRelocation: @escaping () -> Bool,
                     orderFrontForRelocation: @escaping () -> Void,
                     cancelHostRelocation: @escaping () -> Void,
                     hideHost: @escaping () -> Void,
                     syncMirrors: @escaping () -> Void,
                     syncScreenEdgeClicks: @escaping () -> Void,
                     holdWave: @escaping (CGDirectDisplayID) -> Void,
                     matchWave: @escaping () -> Void,
                     keepWave: @escaping () -> Void,
                     releaseWave: @escaping () -> Void,
                     startMenuSpace: @escaping () -> Void, stopMenuSpace: @escaping () -> Void,
                     invalidateMenuSpace: @escaping () -> Void, readMenuSpace: @escaping () -> Void,
                     mascotWantsRoom: @escaping () -> Bool = { false }) {
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
            self.selectDisplay = selectDisplay
            self.updateScreen = updateScreen
            self.currentDisplayID = currentDisplayID
            self.displayExists = displayExists
            self.syncVisibleConsumers = syncVisibleConsumers
            self.hostIdentity = hostIdentity
            self.canRelocateOnScreen = canRelocateOnScreen
            self.orderOutForRelocation = orderOutForRelocation
            self.orderFrontForRelocation = orderFrontForRelocation
            self.cancelHostRelocation = cancelHostRelocation
            self.hideHost = hideHost
            self.syncMirrors = syncMirrors
            self.syncScreenEdgeClicks = syncScreenEdgeClicks
            self.holdWave = holdWave
            self.matchWave = matchWave
            self.keepWave = keepWave
            self.releaseWave = releaseWave
            self.startMenuSpace = startMenuSpace
            self.stopMenuSpace = stopMenuSpace
            self.invalidateMenuSpace = invalidateMenuSpace
            self.mascotWantsRoom = mascotWantsRoom
            self.readMenuSpace = readMenuSpace
        }
    }

    private let environment: Environment
    private let island: Island
    private var preferenceSyncWork: DispatchWorkItem?
    private var screenRefreshWork: DispatchWorkItem?
    /// Set while the live window is on its way to another display, so the copy
    /// there stays up until that window has been drawn for it and ordered in.
    package private(set) var mirrorHeldForArrival: CGDirectDisplayID?
    /// Bumped on every move, so a reveal queued for the display just left does
    /// not order the window in after a newer move, or after the island stops.
    private var relocationTicket = 0

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
        // An island hidden until it shows activity measures on, to have its
        // room when one comes.
        let wanted = island.running() && !island.suspended()
            && (!island.hiddenUntilHover() || environment.hiddenShowsActivity()) && !island.expanded()
            && !island.showsCaptureControls()
            && (island.idleContent() != .none || island.hasCompactActivity() || !geometry.isNotched
                || island.mascotWantsRoom())
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

    /// Moves the island to `destination`. On screen, it leaves first, so the
    /// window server cannot stretch it across to the other display, with a
    /// copy underneath so the display it leaves does not blink empty; it comes
    /// back on the next turn, once what it shows has been drawn for the display
    /// it landed on. A newer move, a stop or a replaced window takes over.
    package func move(to destination: CGDirectDisplayID) {
        guard let host = island.hostIdentity() else { return }
        let reveal = island.canRelocateOnScreen()
        relocationTicket += 1
        let ticket = relocationTicket
        let origin = island.currentDisplayID()
        func isCurrent() -> Bool { relocationTicket == ticket && island.hostIdentity() === host }
        island.selectDisplay(destination)
        mirrorHeldForArrival = reveal ? destination : nil
        if reveal {
            // Keep the copy on the display being entered until the window is
            // drawn for it. The copy on the display being left goes underneath.
            island.syncMirrors()
            guard isCurrent() else { return }
            // Only the copy that was covered. The one on the display being
            // entered is already drawing its wave; laying it out again flickers it.
            if let origin { island.holdWave(origin) }
            _ = island.orderOutForRelocation()
        } else {
            island.releaseWave()
        }
        guard isCurrent() else { return }
        island.updateScreen()
        guard isCurrent() else { return }
        // Preferences or a disconnected display may choose a different screen.
        if reveal { mirrorHeldForArrival = island.currentDisplayID() }
        // The menu space measured so far belongs to the display it left.
        invalidateMenuSpace()
        island.syncVisibleConsumers()
        island.refreshPresentation()
        guard reveal, isCurrent() else { return }
        let arrival = island.currentDisplayID()
        // SwiftUI draws the new display's shape at the end of this turn, while
        // the window is still out. It comes back on the next one, over the copy.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.relocationTicket == ticket, self.island.hostIdentity() === host else { return }
            self.arrive(ticket: ticket, host: host, planned: arrival)
        }
        environment.schedule(0, work)
    }

    /// The queued half of a move: the window returns over the copy it
    /// covers, which then steps aside.
    private func arrive(ticket: Int, host: AnyObject, planned arrival: CGDirectDisplayID?) {
        func isCurrent() -> Bool { relocationTicket == ticket && island.hostIdentity() === host }
        guard island.running(), !island.suspended() else {
            cancelRelocation()
            island.hideHost()
            island.cancelHostRelocation()
            island.syncMirrors()
            return
        }
        // A screen can disappear before its debounced notification runs.
        // Settle on the currently selected screen, or let teardown cancel us.
        let missing = !island.displayExists(island.currentDisplayID())
        if missing {
            island.updateScreen()
            guard isCurrent() else { return }
            invalidateMenuSpace()
            island.syncVisibleConsumers()
        }
        if missing || island.currentDisplayID() != arrival {
            mirrorHeldForArrival = island.currentDisplayID()
            island.refreshPresentation()
            guard isCurrent() else { return }
        }
        // Take the bars already on that display, then cover them. Hiding the
        // copy while it still holds its wave keeps those bars from falling to
        // dots on the way out.
        island.matchWave()
        guard isCurrent() else { return }
        island.orderFrontForRelocation()
        guard isCurrent() else { return }
        mirrorHeldForArrival = nil
        island.keepWave()
        island.syncMirrors()
        guard isCurrent() else { return }
        island.releaseWave()
        island.syncScreenEdgeClicks()
    }

    /// Ends any move under way: the one that was queued becomes inert, and
    /// the copies let go of the waves they were holding.
    package func cancelRelocation() {
        relocationTicket += 1
        mirrorHeldForArrival = nil
        island.releaseWave()
    }
}
