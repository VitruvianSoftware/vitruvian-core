// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore
import VitruvianDesign

/// A display as the menu panel sees it. `NSScreen` is one.
@MainActor
package protocol MenuPanelScreen: AnyObject {
    var frame: CGRect { get }
    var visibleFrame: CGRect { get }
    var isStillAttached: Bool { get }
    var displayID: CGDirectDisplayID { get }
}

/// A window as the menu panel sees it: the panel's own, the Settings window,
/// a status button's. `NSWindow` is one.
@MainActor
package protocol MenuPanelWindow: AnyObject {
    associatedtype Screen: MenuPanelScreen
    var frame: CGRect { get }
    var screen: Screen? { get }
    var windowNumber: Int { get }
    func convertToScreen(_ rect: CGRect) -> CGRect
    func frameRect(forContentRect contentRect: CGRect) -> CGRect
    func setFrame(_ frameRect: CGRect, display flag: Bool)
    func makeKey()
    func orderFrontRegardless()
    func close()
    /// Lays the content out now, so the window reports the size it needs.
    func layOutContent()
}

/// A status item's button, which the panel hangs from. `NSStatusBarButton` is one.
@MainActor
package protocol MenuPanelButton: AnyObject {
    associatedtype Window: MenuPanelWindow
    var window: Window? { get }
    var bounds: CGRect { get }
    /// The button's bounds in its window's coordinates.
    func boundsInWindow() -> CGRect
}

/// The popover the panel is shown in. `NSPopover` is one.
@MainActor
package protocol MenuPanelPopover: AnyObject {
    associatedtype Window: MenuPanelWindow
    associatedtype Button: MenuPanelButton
    var isShown: Bool { get }
    var animates: Bool { get set }
    /// The window holding the panel while it is shown.
    var panelWindow: Window? { get }
    /// Shows the panel hanging below `button`.
    func show(below button: Button)
    func performClose(_ sender: Any?)
    func close()
}

/// The kinds of display, window, button and popover the panel works with.
package protocol MenuPanelPlatform {
    associatedtype Screen: MenuPanelScreen
    associatedtype Window: MenuPanelWindow where Window.Screen == Screen
    associatedtype Button: MenuPanelButton where Button.Window == Window
    associatedtype Popover: MenuPanelPopover where Popover.Window == Window, Popover.Button == Button
}

/// The app's: AppKit's own.
package enum AppKitMenuPanel: MenuPanelPlatform {
    package typealias Screen = NSScreen
    package typealias Window = NSWindow
    package typealias Button = NSStatusBarButton
    package typealias Popover = NSPopover
}

extension AppKitMenuPanel {
    /// The invisible point a metric popover hangs from while it moves between
    /// status items, before it is configured: a floating overlay, which window
    /// managers do not list.
    @MainActor
    package static func makePositioningPanel(at anchor: CGRect) -> NSPanel {
        OverlayPanel(contentRect: anchor,
                     styleMask: [.borderless, .nonactivatingPanel],
                     backing: .buffered,
                     defer: false)
    }
}

extension NSScreen: MenuPanelScreen {}

extension NSWindow: MenuPanelWindow {
    package func layOutContent() { contentView?.layoutSubtreeIfNeeded() }
}

extension NSStatusBarButton: MenuPanelButton {
    package func boundsInWindow() -> CGRect { convert(bounds, to: nil) }
}

extension NSPopover: MenuPanelPopover {
    package var panelWindow: NSWindow? { contentViewController?.view.window }
    package func show(below button: NSStatusBarButton) {
        show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

/// The main menu panel's presentation: where it opens, how it holds its spot
/// while the menu bar shifts, how it closes, and how it comes back after
/// something other than Vitruvian closed it. `AppDelegate` owns the popover
/// and the rest of the panel (its monitors, its keys, following activation)
/// and reaches this through `Environment`.
@MainActor
package final class MenuPanelPresenter<P: MenuPanelPlatform> {
    /// What the presentation reads and drives outside itself. The app passes
    /// AppKit's screens, events and notifications, the main queue, the
    /// services the panel shares and its own hooks.
    @MainActor
    package struct Environment {
        package var screens: () -> [P.Screen]
        package var screenWithMenuBar: () -> P.Screen?
        /// The usable area of the display under the pointer.
        package var pointerVisibleFrame: () -> CGRect
        package var currentEvent: () -> NSEvent?
        package var activate: () -> Void
        package var main: (@escaping @MainActor () -> Void) -> Void
        /// Follows a window's moves and resizes, saying whether its content
        /// was resized, and returns what `stopObserving` takes.
        package var observeGeometry: (_ window: P.Window, _ changed: @escaping @MainActor (_ resized: Bool) -> Void) -> [Any]
        package var stopObserving: (Any) -> Void
        /// The main status item's button.
        package var statusButton: () -> P.Button?
        package var holdStatusBadge: (Bool) -> Void
        /// What the panel's content shows and measures against
        /// (`MenuPanelFocus`, `PanelInteractionState`).
        package var setPopoverVisible: (Bool) -> Void
        package var setSwitchingAnchor: (Bool) -> Void
        package var setAnchorScreen: (P.Screen?) -> Void
        package var preventsDismissal: () -> Bool
        package var endDismissalProtection: () -> Void
        /// Lets the sampling and caches the open panel uses go.
        package var releaseResources: () -> Void
        package var configureWindow: (P.Window) -> Void
        /// Hangs the popover from a stable positioning view when the anchor
        /// needs one; true when it does.
        package var usePositioningView: (P.Window) -> Bool
        package var installDismissMonitors: () -> Void
        package var removeDismissMonitors: () -> Void
        package var beginActivationTracking: () -> Void
        package var endActivationTracking: () -> NSRunningApplication?
        package var returnActivation: (_ source: NSRunningApplication?, _ reason: PanelCloseReason?) -> Void
        /// Closes the panel the way the app's own actions do.
        package var closePanel: () -> Void
        package var settingsWindow: () -> P.Window?
        package var isTerminating: () -> Bool

        package init(screens: @escaping () -> [P.Screen],
                     screenWithMenuBar: @escaping () -> P.Screen?,
                     pointerVisibleFrame: @escaping () -> CGRect,
                     currentEvent: @escaping () -> NSEvent?,
                     activate: @escaping () -> Void,
                     main: @escaping (@escaping @MainActor () -> Void) -> Void,
                     observeGeometry: @escaping (P.Window, @escaping @MainActor (Bool) -> Void) -> [Any],
                     stopObserving: @escaping (Any) -> Void,
                     statusButton: @escaping () -> P.Button?,
                     holdStatusBadge: @escaping (Bool) -> Void,
                     setPopoverVisible: @escaping (Bool) -> Void,
                     setSwitchingAnchor: @escaping (Bool) -> Void,
                     setAnchorScreen: @escaping (P.Screen?) -> Void,
                     preventsDismissal: @escaping () -> Bool,
                     endDismissalProtection: @escaping () -> Void,
                     releaseResources: @escaping () -> Void,
                     configureWindow: @escaping (P.Window) -> Void,
                     usePositioningView: @escaping (P.Window) -> Bool,
                     installDismissMonitors: @escaping () -> Void,
                     removeDismissMonitors: @escaping () -> Void,
                     beginActivationTracking: @escaping () -> Void,
                     endActivationTracking: @escaping () -> NSRunningApplication?,
                     returnActivation: @escaping (NSRunningApplication?, PanelCloseReason?) -> Void,
                     closePanel: @escaping () -> Void,
                     settingsWindow: @escaping () -> P.Window?,
                     isTerminating: @escaping () -> Bool) {
            self.screens = screens
            self.screenWithMenuBar = screenWithMenuBar
            self.pointerVisibleFrame = pointerVisibleFrame
            self.currentEvent = currentEvent
            self.activate = activate
            self.main = main
            self.observeGeometry = observeGeometry
            self.stopObserving = stopObserving
            self.statusButton = statusButton
            self.holdStatusBadge = holdStatusBadge
            self.setPopoverVisible = setPopoverVisible
            self.setSwitchingAnchor = setSwitchingAnchor
            self.setAnchorScreen = setAnchorScreen
            self.preventsDismissal = preventsDismissal
            self.endDismissalProtection = endDismissalProtection
            self.releaseResources = releaseResources
            self.configureWindow = configureWindow
            self.usePositioningView = usePositioningView
            self.installDismissMonitors = installDismissMonitors
            self.removeDismissMonitors = removeDismissMonitors
            self.beginActivationTracking = beginActivationTracking
            self.endActivationTracking = endActivationTracking
            self.returnActivation = returnActivation
            self.closePanel = closePanel
            self.settingsWindow = settingsWindow
            self.isTerminating = isTerminating
        }
    }

    package let popover: P.Popover
    private let environment: Environment
    package var popoverClosedAt = Date.distantPast
    package var popoverIsClosing = false
    package var popoverCloseIsAppRequested = false
    /// The last visible geometry and event destination survive AppKit's teardown.
    package var popoverLastFrame: CGRect?
    package var popoverLastWindowNumber: Int?
    package var popoverForeignReopenAt = Date.distantPast
    package var popoverIsSwitchingAnchor = false
    package private(set) var popoverCloseReason: PanelCloseReason?
    private var popoverCloseCompletions: [() -> Void] = []

    package init(popover: P.Popover, environment: Environment) {
        self.popover = popover
        self.environment = environment
    }

    /// Where the user last physically clicked a status button, captured at
    /// action time. The deferred metric re-shows fire up to ~0.2s after the
    /// click, and re-reading the pointer there would chase a flicked-away
    /// cursor; the captured point is immune to that. Accessibility presses
    /// (no mouse event) capture nothing, so they never "correct" toward a
    /// pointer parked anywhere on screen.
    package var lastStatusClick: (point: NSPoint, at: Date)?
    package var popoverAnchor: PanelAnchor?
    package var lastGoodPanelAnchor: PanelAnchor?
    package private(set) var popoverDriftObservers: [Any] = []
    package var popoverPositioningPanel: P.Window?

    /// How long a captured click still counts as "where the icon is".
    package static var statusClickFreshness: TimeInterval { 0.5 }

    package static var statusClickEventTypes: Set<NSEvent.EventType> {
        [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
    }

    /// The spot an open panel holds: the horizontal middle and the top edge it
    /// must keep across content resizes, plus the screen the menu bar icon was
    /// on. The screen travels with the anchor instead of being read back from
    /// the panel's window, because a window already flung to a corner can
    /// report a different display and would then be clamped against that one.
    package struct PanelAnchor {
        /// The opening popover window's horizontal center, used while direct
        /// frame correction is still responsible for placement.
        package let midX: CGFloat
        /// The opening arrow's screen-space tip, used once the popover hangs
        /// from a stable positioning view. With a trustworthy status frame this
        /// is the status button's center, while `midX` is the already-placed
        /// window's center; AppKit's horizontal edge clamp can make them differ.
        /// Fallback anchors know only one x coordinate and use it for both.
        package let tipX: CGFloat
        package let top: CGFloat
        package let screen: P.Screen?
        /// False when it came from a fallback, so a guess never becomes the
        /// remembered good anchor for the rest of the session.
        package let trusted: Bool
        /// True when the anchor is known to beat the status item's frame from
        /// the moment the panel opens, because a physical click landed clearly
        /// outside that frame. Otherwise the anchor waits: while the frame
        /// still describes a spot in the menu bar the system places the panel
        /// better than any remembered point can, following the icon as the bar
        /// shuffles items around it.
        package let overridesSoundFrame: Bool
        /// The button the anchor was taken from, so "does the frame still
        /// describe the bar?" asks the item the panel is actually hanging off
        /// (a metric item, not necessarily the main icon).
        package weak var button: P.Button?
    }

    package func statusButtonMidX(_ button: P.Button) -> CGFloat? {
        guard let window = button.window else { return nil }
        return window.convertToScreen(button.boundsInWindow()).midX
    }

    package func captureStatusClick() {
        guard let event = environment.currentEvent(),
              Self.statusClickEventTypes.contains(event.type),
              (0...Self.statusClickFreshness).contains(ProcessInfo.processInfo.systemUptime - event.timestamp)
        else {
            lastStatusClick = nil
            return
        }
        lastStatusClick = (NSEvent.mouseLocation, Date())
    }

    package var freshStatusClick: NSPoint? {
        guard let click = lastStatusClick,
              (0...Self.statusClickFreshness).contains(Date().timeIntervalSince(click.at)) else { return nil }
        return click.point
    }

    /// The on-screen midX the open panel must center on, or nil when the
    /// button's reported frame can be trusted. A fresh physical click landing
    /// clearly outside the frame the button claims to occupy is the macOS 27
    /// stale-frame mismatch (see StatusItemAnchorSupport): the click marks
    /// where the icon is actually drawn, so the panel centers there. The
    /// positioning rect cannot express this (AppKit intersects it with the
    /// button's bounds), so the correction moves the popover's window instead.
    package func correctedPopoverMidX(for button: P.Button) -> CGFloat? {
        guard let click = freshStatusClick,
              let reportedMidX = statusButtonMidX(button),
              StatusItemAnchorSupport.anchorDriftX(clickX: click.x,
                                                   reportedMidX: reportedMidX,
                                                   buttonWidth: button.bounds.width) != nil
        else { return nil }
        return click.x
    }

    /// The screen the menu bar icon lives on, for the panel's height cap and
    /// for clamping it once it is open.
    package func statusScreen(for button: P.Button) -> P.Screen? {
        // Replicated menu bars (including Sidecar) can report the status
        // window on a different display. The captured click identifies the
        // actual bar, including vertically arranged screens with the same x.
        if let click = freshStatusClick,
           let clicked = environment.screens().first(where: { NSMouseInRect(click, $0.frame, false) }) {
            return clicked
        }
        if let frame = button.window?.frame,
           let hosting = environment.screens().first(where: { $0.frame.intersects(frame) }) {
            return hosting
        }
        // A window parked out of the visible area reports no screen of its own,
        // and that is exactly the state this path exists for, so fall back to
        // the display that owns the bar rather than to whichever one happens to
        // hold the key window.
        return button.window?.screen ?? environment.screenWithMenuBar()
    }

    /// Whether the item the panel hangs off still reports a frame that sits in
    /// a menu bar. While it does, the system's own placement wins and the
    /// remembered anchor stays out of the way; once it stops (a bar that hides
    /// itself parks the window out of the visible area) the anchor takes over.
    package func frameStillDescribesMenuBar(_ anchor: PanelAnchor) -> Bool {
        guard let frame = anchor.button?.window?.frame,
              let screen = anchor.screen, screen.isStillAttached else { return false }
        return StatusItemAnchorSupport.isTrustworthyStatusFrame(frame, screenFrames: [screen.frame])
    }

    package func statusFrameNeedsAnchorOverride(_ anchor: PanelAnchor) -> Bool {
        anchor.overridesSoundFrame || !frameStillDescribesMenuBar(anchor)
    }

    /// The spot the panel must hold while it is open, decided at the moment it
    /// opens: the user has just clicked the icon, so the menu bar is up and its
    /// frame is at its most trustworthy. Everything after that (a bar that
    /// slides away, a status item stranded at the slot it was born in) is read
    /// from a frame that no longer describes where the icon is.
    package func resolvePanelAnchor(for button: P.Button, window: P.Window) -> PanelAnchor {
        let screen = statusScreen(for: button)
        let statusFrame = button.window?.frame
        let frameIsSound = statusFrame.map {
            StatusItemAnchorSupport.isTrustworthyStatusFrame($0, screenFrames: screen.map { [$0.frame] } ?? [])
        } ?? false
        if frameIsSound, statusFrame != nil {
            // Where the popover has just been placed is the anchor: with a
            // sound frame the system put it exactly right, including its own
            // clamping near a screen edge, so holding that spot changes
            // nothing about how an open panel looks. It is held in reserve,
            // though, and only applied once that frame stops describing the
            // bar. A fresh physical click that clearly disagrees with the
            // frame is the stranded item instead, and then the click marks
            // where the icon really is and outranks the frame right away.
            let corrected = correctedPopoverMidX(for: button)
            return PanelAnchor(midX: corrected ?? window.frame.midX,
                               tipX: corrected ?? statusButtonMidX(button) ?? window.frame.midX,
                               top: window.frame.maxY,
                               screen: screen,
                               trusted: true,
                               overridesSoundFrame: corrected != nil,
                               button: button)
        }
        // A real click outranks both a frame on another display and a spot
        // remembered from an earlier opening. Reset the top as well as x:
        // the first AppKit placement may have used an entirely different bar.
        if let click = freshStatusClick, let screen,
           NSMouseInRect(click, screen.frame, false) {
            return PanelAnchor(midX: click.x, tipX: click.x,
                               top: screen.visibleFrame.maxY, screen: screen,
                               trusted: true, overridesSoundFrame: true, button: button)
        }
        // Without a click or a usable frame, reuse this session's last spot
        // before falling back to the corner of the screen that owns the bar.
        // The remembered spot is only worth reusing while it still describes
        // somewhere that exists. One captured on a display that has since been
        // unplugged would put the panel against an edge of the display that is
        // left, which is the very thing this is here to prevent.
        if let remembered = lastGoodPanelAnchor,
           let rememberedScreen = remembered.screen,
           rememberedScreen.isStillAttached,
           rememberedScreen.displayID == screen?.displayID {
            // Reused for an item whose frame is already pointing nowhere, so it
            // has to act now rather than wait for a frame that will not recover.
            return PanelAnchor(midX: remembered.midX, tipX: remembered.tipX,
                               top: remembered.top,
                               screen: screen, trusted: true,
                               overridesSoundFrame: true, button: button)
        }
        lastGoodPanelAnchor = nil
        let visible = screen?.visibleFrame ?? window.frame
        return PanelAnchor(midX: visible.maxX, tipX: visible.maxX,
                           top: visible.maxY, screen: screen,
                           trusted: false, overridesSoundFrame: true, button: button)
    }

    /// Keeps the popover at the opening anchor when its status item stops being
    /// trustworthy. Ordinary menu-bar movement remains AppKit's responsibility;
    /// an untrustworthy frame instead gets a stable screen-space positioning
    /// view so both the window and its arrow survive later geometry changes.
    package func beginPopoverDriftCorrection(window: P.Window, anchor: PanelAnchor) {
        endPopoverDriftCorrection()
        armPopoverDriftCorrection(window: window, anchor: anchor)
    }

    /// Re-arms drift correction after AppKit re-shows the popover against our
    /// stable positioning view. Keeping the panel out of the ordinary teardown
    /// prevents `popoverDidClose` from closing the new anchor mid-switch.
    package func beginPopoverDriftCorrection(window: P.Window,
                                             anchor: PanelAnchor,
                                             preserving positioningPanel: P.Window) {
        endPopoverDriftCorrection(preserving: positioningPanel)
        popoverPositioningPanel = positioningPanel
        positioningPanel.orderFrontRegardless()
        armPopoverDriftCorrection(window: window, anchor: anchor)
    }

    package func armPopoverDriftCorrection(window: P.Window, anchor: PanelAnchor) {
        popoverAnchor = anchor
        if anchor.trusted { lastGoodPanelAnchor = anchor }
        environment.setAnchorScreen(anchor.screen)
        if popoverPositioningPanel != nil {
            _ = environment.usePositioningView(window)
        } else {
            applyPopoverDriftFrame(window)
        }
        popoverLastFrame = window.frame
        popoverLastWindowNumber = window.windowNumber
        popoverDriftObservers += environment.observeGeometry(window) { [weak self, weak window] contentResized in
            guard let self, let window else { return }
            self.popoverLastFrame = window.frame
            // Once the popover hangs from the stable view, that view is the
            // only authority for placement. Recompute its screen-space
            // position on both resize and move; applying the old midX frame
            // as well would fight AppKit's tip-aware edge clamping.
            if self.popoverPositioningPanel != nil {
                _ = self.environment.usePositioningView(window)
                return
            }
            if contentResized, self.environment.usePositioningView(window) { return }
            self.applyPopoverDriftFrame(window)
            guard contentResized else { return }
            // A status-item frame can become untrustworthy after the
            // popover opens. AppKit may run another placement pass after
            // publishing the resize, so check once more on the next turn.
            self.environment.main { [weak self, weak window] in
                guard let self,
                      let window,
                      self.popover.isShown,
                      window === self.popover.panelWindow else { return }
                _ = self.environment.usePositioningView(window)
            }
        }
    }

    package func applyPopoverDriftFrame(_ window: P.Window) {
        guard let anchor = popoverAnchor,
              // A healthy bar places the panel better than the anchor can, and
              // keeps it under an icon that shifts as items come and go, so the
              // anchor stays dormant until that frame stops meaning anything.
              statusFrameNeedsAnchorOverride(anchor),
              let visible = anchorVisibleFrame(anchor, window: window) else { return }
        let frame = window.frame
        let target = StatusItemAnchorSupport.pinnedPanelFrame(size: frame.size,
                                                              anchorMidX: anchor.midX,
                                                              anchorTop: anchor.top,
                                                              visibleFrame: visible)
        // The 2pt tolerance breaks the loop with our own setFrame's didMove.
        guard abs(frame.midX - target.midX) > 2 || abs(frame.maxY - target.maxY) > 2 else { return }
        window.setFrame(target, display: true)
    }

    /// The usable area the panel is clamped to. Prefers the anchor's own screen
    /// and only falls back when that display has since been unplugged.
    package func anchorVisibleFrame(_ anchor: PanelAnchor, window: P.Window) -> CGRect? {
        if let screen = anchor.screen, screen.isStillAttached {
            return screen.visibleFrame
        }
        return (window.screen ?? environment.screenWithMenuBar())?.visibleFrame
    }

    package func endPopoverDriftCorrection(preserving positioningPanel: P.Window? = nil) {
        popoverDriftObservers.forEach(environment.stopObserving)
        popoverDriftObservers.removeAll()
        if popoverPositioningPanel !== positioningPanel {
            popoverPositioningPanel?.close()
        }
        popoverPositioningPanel = nil
        popoverAnchor = nil
        // Nothing is measuring itself against a screen with the panel closed,
        // and holding one keeps a display object alive for no reason.
        environment.setAnchorScreen(nil)
    }

    package func showPopover(anchor button: P.Button? = nil,
                             allowRecentClose: Bool = false,
                             animate: Bool = true,
                             activate: Bool = true,
                             restoring savedAnchor: PanelAnchor? = nil) {
        guard !popover.isShown, !popoverIsClosing else { return }
        // The click that just transient-dismissed the popover also lands here;
        // reopening would make the panel look impossible to close.
        guard allowRecentClose || Date().timeIntervalSince(popoverClosedAt) > 0.35 else { return }
        guard let button = button ?? environment.statusButton() else { return }

        // The panel measures itself against this while the popover lays out, so
        // it has to be known before the content is asked for its size.
        environment.setAnchorScreen(savedAnchor?.screen ?? statusScreen(for: button))
        environment.holdStatusBadge(true)
        if !animate {
            popover.animates = false
        }
        environment.setPopoverVisible(true)
        popover.show(below: button)
        environment.setPopoverVisible(popover.isShown)
        if !animate {
            popover.animates = true
        }
        if let window = popover.panelWindow {
            environment.configureWindow(window)
            window.layOutContent()
            window.makeKey()
            popoverIsClosing = false
            popoverCloseIsAppRequested = false
            popoverCloseReason = nil
        } else {
            environment.holdStatusBadge(false)
        }
        if activate {
            environment.beginActivationTracking()
            environment.activate()
        }
        // Only arm the monitors and the anchor if the popover actually presented
        // — otherwise popoverDidClose never fires and both would leak, holding a
        // display object and a window observer for the rest of the session.
        guard popover.isShown else {
            environment.holdStatusBadge(false)
            endPopoverDriftCorrection()
            _ = environment.endActivationTracking()
            return
        }
        if let window = popover.panelWindow {
            beginPopoverDriftCorrection(window: window,
                                        anchor: savedAnchor ?? resolvePanelAnchor(for: button, window: window))
        }
        environment.installDismissMonitors()
    }

    package func shouldDismissPopover(forLocalEvent event: NSEvent) -> Bool {
        guard !environment.preventsDismissal() else { return false }
        guard let settingsWindow = environment.settingsWindow(),
              event.windowNumber == settingsWindow.windowNumber && event.windowNumber > 0,
              let popoverFrame = popover.panelWindow?.frame else {
            return false
        }
        return settingsWindow.frame.intersects(popoverFrame)
    }

    package func closePopoverNow(animated: Bool, reason: PanelCloseReason,
                                 completion: (() -> Void)?) {
        guard popover.isShown else {
            completion?()
            return
        }
        if let completion { popoverCloseCompletions.append(completion) }
        popoverCloseIsAppRequested = true
        // Any request in the same close that hands work to something else
        // wins, so a dismissal racing an action never takes activation back.
        if popoverCloseReason?.dismissesWithoutTakeover != false {
            popoverCloseReason = reason
        }
        guard !popoverIsClosing else { return }

        popoverIsClosing = true
        if animated {
            popover.performClose(nil)
        } else {
            popover.animates = false
            popover.close()
            popover.animates = true
        }
    }

    package func runPopoverCloseCompletions() {
        let completions = popoverCloseCompletions
        popoverCloseCompletions.removeAll()
        completions.forEach { $0() }
    }

    package func popoverWillClose(_ notification: Notification) {
        popoverIsClosing = true
        if !popoverIsSwitchingAnchor {
            popoverClosedAt = Date()
        }
    }

    package func popoverDidClose(_ notification: Notification) {
        if !popover.isShown {
            environment.setPopoverVisible(false)
        }
        // Decided before anything below is torn down, and treated like a
        // metric anchor switch: the panel is about to be shown again in the
        // same turn, so the sampling and caches it is using stay alive.
        let recoveryAnchor = anchorAfterForeignClose()
        if recoveryAnchor != nil {
            popoverIsSwitchingAnchor = true
            environment.setSwitchingAnchor(true)
        }
        if !popoverIsSwitchingAnchor && !popover.isShown {
            environment.holdStatusBadge(false)
        }
        if !popoverIsSwitchingAnchor {
            releasePanelResources()
        }
        environment.removeDismissMonitors()
        endPopoverDriftCorrection()
        environment.endDismissalProtection()
        popoverClosedAt = popoverIsSwitchingAnchor ? .distantPast : Date()
        popoverIsClosing = false
        popoverCloseIsAppRequested = false
        let closeReason = popoverCloseReason
        popoverCloseReason = nil
        runPopoverCloseCompletions()
        if let recoveryAnchor {
            reopenPanelAfterForeignClose(anchor: recoveryAnchor)
        } else if !popoverIsSwitchingAnchor {
            environment.returnActivation(environment.endActivationTracking(), closeReason)
        }
    }

    /// What the panel was holding open only for as long as it was on screen.
    package func releasePanelResources() {
        environment.releaseResources()
    }

    /// Preserve the corrected anchor, not just the status item's stale frame.
    /// A recent event targeting this panel is required; a parked pointer is not
    /// evidence that an unrelated system close should be undone.
    package func anchorAfterForeignClose() -> PanelAnchor? {
        guard !environment.isTerminating(), !popoverIsSwitchingAnchor,
              let anchor = popoverAnchor, anchor.screen?.isStillAttached == true,
              let button = anchor.button, button.window != nil,
              StatusItemAnchorSupport.shouldReopenPanel(
                  closedByApp: popoverCloseIsAppRequested,
                  lastFrame: popoverLastFrame,
                  panelWindowNumber: popoverLastWindowNumber,
                  event: environment.currentEvent(),
                  secondsSinceLastReopen: Date().timeIntervalSince(popoverForeignReopenAt))
        else { return nil }
        return anchor
    }

    /// Reuses the anchor within the close callback. If presentation fails or
    /// another close follows immediately, release the resources held for recovery.
    package func reopenPanelAfterForeignClose(anchor: PanelAnchor) {
        popoverForeignReopenAt = Date()
        if let button = anchor.button {
            showPopover(anchor: button, allowRecentClose: true, animate: false, activate: false,
                        restoring: anchor)
        }
        environment.main { [weak self] in
            guard let self else { return }
            self.popoverIsSwitchingAnchor = false
            self.environment.setSwitchingAnchor(false)
            if !self.popover.isShown {
                self.environment.holdStatusBadge(false)
                self.releasePanelResources()
                _ = self.environment.endActivationTracking()
            }
        }
    }

    package func positionSettingsWindow(_ window: P.Window, force: Bool, on targetScreen: P.Screen? = nil) {
        window.layOutContent()
        let popoverWindow = popover.isShown ? popover.panelWindow : nil
        let screen = targetScreen.flatMap { $0.isStillAttached ? $0 : nil } ?? popoverWindow?.screen ?? window.screen
        let visible = screen?.visibleFrame ?? environment.pointerVisibleFrame()
        let shouldCenter = force || screen?.displayID != window.screen?.displayID || !visible.intersects(window.frame)
        let margin: CGFloat = 40
        let availableWidth = max(1, visible.width - margin)
        let availableHeight = max(1, visible.height - margin)
        let minFrame = window.frameRect(forContentRect: NSRect(
            x: 0, y: 0,
            width: SettingsWindowSupport.minContentWidth,
            height: SettingsWindowSupport.minContentHeight
        )).size
        let width = min(max(window.frame.width, minFrame.width), availableWidth)
        let height = min(max(window.frame.height, minFrame.height), availableHeight)
        var frame = shouldCenter
            ? NSRect(x: visible.midX - width / 2,
                     y: visible.midY - height / 2,
                     width: width,
                     height: height)
            : NSRect(x: window.frame.minX,
                     y: window.frame.minY,
                     width: width,
                     height: height)

        if let popoverFrame = popoverWindow?.frame,
           visible.intersects(popoverFrame),
           frame.intersects(popoverFrame) {
            let placement = SettingsWindowSupport.panelPlacement(
                preferredFrame: frame, panelFrame: popoverFrame, visibleFrame: visible)
            frame = placement.frame
            if placement.closesPanel {
                environment.closePanel()
            }
        } else if shouldCenter {
            frame.origin.x = min(max(frame.origin.x, visible.minX + margin / 2), visible.maxX - width - margin / 2)
            frame.origin.y = min(max(frame.origin.y, visible.minY + margin / 2), visible.maxY - height - margin / 2)
        }
        window.setFrame(frame.integral, display: false)
    }
}
