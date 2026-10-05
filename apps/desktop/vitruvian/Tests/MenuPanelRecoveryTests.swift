// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The real panel presentation (`MenuPanelPresenter`) over a controlled
/// platform: displays, windows, a status button and a popover that only
/// record what is asked of them. Native event objects are data only; nothing
/// is posted and no window is created.
enum MenuPanelRecoveryTests {
    final class Screen: MenuPanelScreen {
        var frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        var visibleFrame = CGRect(x: 0, y: 0, width: 1920, height: 1050)
        var isStillAttached = true
        var displayID: CGDirectDisplayID = 1
    }
    final class Window: MenuPanelWindow {
        var frame: CGRect
        var screen: MenuPanelRecoveryTests.Screen?
        var windowNumber = 71
        /// Where the window learns which display it is on, and reports its moves.
        weak var fixture: Fixture?
        init(_ frame: CGRect, fixture: Fixture?) {
            self.frame = frame
            self.fixture = fixture
            screen = fixture?.screens.first
        }
        func convertToScreen(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: frame.minX, dy: frame.minY) }
        func frameRect(forContentRect rect: CGRect) -> CGRect {
            CGRect(origin: rect.origin, size: CGSize(width: rect.width, height: rect.height + 28))
        }
        func setFrame(_ rect: CGRect, display: Bool) {
            frame = rect
            screen = fixture?.screens.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }
            fixture?.moved(self)
        }
        func makeKey() {}
        func orderFrontRegardless() {}
        func close() {}
        func layOutContent() {}
    }
    final class Button: MenuPanelButton {
        var window: MenuPanelRecoveryTests.Window?
        var bounds = CGRect(x: 0, y: 0, width: 36, height: 30)
        init(fixture: Fixture) { window = MenuPanelRecoveryTests.Window(CGRect(x: 682, y: 1050, width: 36, height: 30), fixture: fixture) }
        func boundsInWindow() -> CGRect { bounds }
    }
    final class Popover: MenuPanelPopover {
        var animates = true
        var isShown = false
        var panelWindow: MenuPanelRecoveryTests.Window?
        var fails = false
        var attempts = 0
        var measuredScreen: MenuPanelRecoveryTests.Screen?
        weak var fixture: Fixture?
        // The animated close keeps the panel on screen until it finishes.
        func performClose(_ sender: Any?) {}
        func close() { isShown = false }
        func show(below button: MenuPanelRecoveryTests.Button) {
            attempts += 1
            measuredScreen = fixture?.anchorScreen
            guard !fails, let window = button.window else { return }
            panelWindow = MenuPanelRecoveryTests.Window(CGRect(x: window.frame.midX - 166, y: 530, width: 332, height: 500), fixture: fixture)
            isShown = true
        }
    }
    enum Panel: MenuPanelPlatform {
        typealias Screen = MenuPanelRecoveryTests.Screen
        typealias Window = MenuPanelRecoveryTests.Window
        typealias Button = MenuPanelRecoveryTests.Button
        typealias Popover = MenuPanelRecoveryTests.Popover
    }
    typealias Host = MenuPanelPresenter<Panel>

    /// Everything the presentation reads or drives outside itself, recorded.
    final class Fixture {
        var screens = [Screen()]
        let popover = Popover()
        lazy var button: Button? = Button(fixture: self)
        var currentEvent: NSEvent?
        var jobs: [@MainActor () -> Void] = []
        var observers: [(token: NSObject, window: Window, changed: @MainActor (Bool) -> Void)] = []
        var popoverVisible = false
        var switchingAnchor = false
        var anchorScreen: Screen?
        var viewKeepsOpen = false
        var presentingModal = false
        var badgeHeld = false
        var releases = 0
        var monitors = false
        var activationTracking = false
        var activationTrackingStarts = 0
        var handbackReasons: [PanelCloseReason?] = []
        var settingsWindow: Window?
        var isTerminating = false

        func window(_ frame: CGRect) -> Window { Window(frame, fixture: self) }

        /// The main queue runs what was queued for it.
        func drain() {
            while !jobs.isEmpty { jobs.removeFirst()() }
        }

        func moved(_ window: Window) {
            for observer in observers where observer.window === window { observer.changed(false) }
        }

        lazy var host = Host(popover: popover, environment: .init(
            screens: { [unowned self] in self.screens },
            screenWithMenuBar: { [unowned self] in self.screens.first },
            pointerVisibleFrame: { [unowned self] in self.screens.first?.visibleFrame ?? .zero },
            currentEvent: { [unowned self] in self.currentEvent },
            activate: {},
            main: { [unowned self] in self.jobs.append($0) },
            observeGeometry: { [unowned self] window, changed in
                let token = NSObject()
                self.observers.append((token: token, window: window, changed: changed))
                return [token]
            },
            stopObserving: { [unowned self] token in self.observers.removeAll { $0.token === token as AnyObject } },
            statusButton: { [unowned self] in self.button },
            holdStatusBadge: { [unowned self] in self.badgeHeld = $0 },
            setPopoverVisible: { [unowned self] in self.popoverVisible = $0 },
            setSwitchingAnchor: { [unowned self] in self.switchingAnchor = $0 },
            setAnchorScreen: { [unowned self] in self.anchorScreen = $0 },
            preventsDismissal: { [unowned self] in self.viewKeepsOpen || self.presentingModal },
            endDismissalProtection: { [unowned self] in
                self.viewKeepsOpen = false
                self.presentingModal = false
            },
            releaseResources: { [unowned self] in self.releases += 1 },
            configureWindow: { _ in },
            usePositioningView: { _ in false },
            installDismissMonitors: { [unowned self] in self.monitors = true },
            removeDismissMonitors: { [unowned self] in self.monitors = false },
            beginActivationTracking: { [unowned self] in
                self.activationTracking = true
                self.activationTrackingStarts += 1
            },
            endActivationTracking: { [unowned self] in
                self.activationTracking = false
                return nil
            },
            returnActivation: { [unowned self] _, reason in self.handbackReasons.append(reason) },
            closePanel: { [unowned self] in self.popover.isShown = false },
            settingsWindow: { [unowned self] in self.settingsWindow },
            isTerminating: { [unowned self] in self.isTerminating }))

        init() { popover.fixture = self }
    }

    static func event(_ type: NSEvent.EventType = .leftMouseDown, window: Int = 71,
                      location: CGPoint = CGPoint(x: 100, y: 100), age: TimeInterval = 0) -> NSEvent? {
        let timestamp = ProcessInfo.processInfo.systemUptime - age
        if type == .keyDown || type == .keyUp || type == .flagsChanged {
            return NSEvent.keyEvent(with: type, location: location, modifierFlags: [], timestamp: timestamp,
                windowNumber: window, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)
        }
        return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: timestamp,
            windowNumber: window, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)
    }

    static func run(_ expect: (Bool, String) -> Void) {
        // Fixtures stay alive for the whole run: each presenter reaches its
        // fixture unowned, as the app's reaches its delegate weakly.
        var fixtures: [Fixture] = []
        defer { fixtures.removeAll() }
        func setup(corrected: Bool = false, present: Bool = true) -> Fixture {
            let fixture = Fixture()
            fixtures.append(fixture)
            if corrected {
                fixture.button!.window!.frame.origin.x = 1482
                fixture.host.lastStatusClick = (CGPoint(x: 700, y: 1065), Date())
            }
            if present { fixture.host.showPopover(animate: false, activate: false) }
            expect(fixture.popoverVisible == fixture.popover.isShown,
                   "panel presentation follows the actual show result")
            fixture.currentEvent = event()
            return fixture
        }
        func close(_ fixture: Fixture) {
            fixture.popover.isShown = false
            fixture.host.popoverWillClose(Notification(name: Notification.Name("willClose")))
            fixture.host.popoverDidClose(Notification(name: Notification.Name("closed")))
        }
        // A close Vitruvian asks for itself, which marks it app requested.
        func requestClose(_ fixture: Fixture, _ reason: PanelCloseReason) {
            fixture.host.closePopoverNow(animated: false, reason: reason, completion: nil)
            fixture.host.popoverWillClose(Notification(name: Notification.Name("willClose")))
            fixture.host.popoverDidClose(Notification(name: Notification.Name("closed")))
        }
        for corrected in [false, true] {
            let fixture = setup(corrected: corrected)
            let host = fixture.host
            expect(host.popoverLastFrame?.midX == 700, "recovery remembers the final visible position, including initial correction")
            host.lastStatusClick = (CGPoint(x: 700, y: 1065), Date().addingTimeInterval(-5))
            close(fixture)
            expect(fixture.popover.isShown && host.popoverLastFrame?.midX == 700,
                   "fresh panel click recovers at its existing anchor even after the opening click expires")
            expect(fixture.popoverVisible,
                   "panel content stays active after a successful anchor recovery")
            expect(fixture.releases == 0, "recovery preserves metric focus and sampling")
            fixture.drain()
            expect(!host.popoverIsSwitchingAnchor && fixture.monitors, "recovery ends switching and keeps dismissal monitors")
            close(fixture); fixture.drain()
            expect(!fixture.popover.isShown && fixture.releases > 0 && !fixture.badgeHeld,
                   "immediate second close stays closed and releases resources")
            expect(!fixture.popoverVisible,
                   "closed panel content stops observing live section updates")
        }
        for origin in [CGPoint.zero, CGPoint(x: 1920, y: 0), CGPoint(x: -1366, y: 0),
                       CGPoint(x: 0, y: 1080), CGPoint(x: 0, y: -1024)] {
            let fixture = setup(present: false)
            let host = fixture.host
            let clickedScreen = Screen()
            clickedScreen.displayID = 2
            clickedScreen.frame = CGRect(origin: origin, size: CGSize(width: 1366, height: 1024))
            clickedScreen.visibleFrame = CGRect(origin: origin, size: CGSize(width: 1366, height: 1000))
            if origin == .zero {
                // Sidecar is the primary display, with the Mac to its right.
                fixture.screens[0].frame.origin.x = 1366
                fixture.screens[0].visibleFrame.origin.x = 1366
                fixture.button!.window!.frame.origin.x += 1366
                fixture.screens.insert(clickedScreen, at: 0)
            } else {
                fixture.screens.append(clickedScreen)
            }
            // The reported status frame stays on the Mac. The click is on the
            // iPad's top row, including the shared boundary in a vertical layout.
            let point = CGPoint(x: origin.x + 700, y: clickedScreen.frame.maxY)
            host.lastStatusClick = (point, Date())
            host.showPopover(animate: false, activate: false)
            expect(fixture.popover.measuredScreen === clickedScreen,
                   "panel height uses the clicked display before presentation at \(origin)")
            expect(host.popoverAnchor?.screen === clickedScreen
                   && host.popoverAnchor?.overridesSoundFrame == true,
                   "click overrides a valid status frame on another display at \(origin)")
            let frame = fixture.popover.panelWindow!.frame
            expect(clickedScreen.visibleFrame.contains(frame) && frame.midX == point.x
                   && frame.maxY == clickedScreen.visibleFrame.maxY,
                   "panel opens below the clicked menu bar at \(origin)")

            host.lastStatusClick = (point, Date().addingTimeInterval(-5))
            close(fixture)
            expect(fixture.popover.measuredScreen === clickedScreen
                   && host.popoverLastFrame == frame,
                   "recovery retains the clicked display after the opening click expires at \(origin)")
            fixture.drain()
        }
        do {
            let fixture = setup(present: false)
            let other = Screen()
            other.displayID = 2
            other.frame.origin.x = 1920
            fixture.screens.append(other)
            fixture.host.lastStatusClick = (CGPoint(x: 2600, y: 1065), Date().addingTimeInterval(-1))
            fixture.host.showPopover(animate: false, activate: false)
            expect(fixture.host.popoverAnchor?.screen === fixture.screens[0]
                   && fixture.host.popoverAnchor?.overridesSoundFrame == false,
                   "an expired click cannot move a later presentation to another display")
        }
        do {
            let fixture = setup()
            fixture.popover.isShown = false
            fixture.host.endPopoverDriftCorrection()
            fixture.button!.window!.frame.origin.y = 1100
            fixture.host.lastStatusClick = (CGPoint(x: 1100, y: 1065), Date())
            fixture.host.showPopover(animate: false, activate: false)
            expect(fixture.host.popoverLastFrame?.midX == 1100,
                   "a new physical click takes priority over a remembered anchor")
        }
        do {
            let fixture = setup(present: false)
            let host = fixture.host
            let screen = Screen()
            screen.displayID = 2
            screen.frame.origin.x = 1920
            screen.visibleFrame.origin.x = 1920
            fixture.screens.append(screen)
            fixture.button!.window!.frame.origin.x += 1920
            host.showPopover(animate: false, activate: false)
            let panel = fixture.popover.panelWindow!
            panel.setFrame(CGRect(x: 3200, y: 530, width: 332, height: 500), display: false)
            let settings = fixture.window(CGRect(x: 100, y: 100, width: 800, height: 700))
            host.positionSettingsWindow(settings, force: false)
            expect(screen.visibleFrame.contains(settings.frame) && !settings.frame.intersects(panel.frame),
                   "reopened Settings moves from the Mac to the panel's display")
            let placed = settings.frame
            host.positionSettingsWindow(settings, force: false)
            expect(settings.frame == placed, "Settings keeps its position on the requested display")
            fixture.popover.isShown = false
            let freshSettings = fixture.window(CGRect(x: 100, y: 100, width: 800, height: 700))
            host.positionSettingsWindow(freshSettings, force: true, on: screen)
            expect(screen.visibleFrame.contains(freshSettings.frame),
                   "new Settings uses the invocation display even without an open panel")
            screen.isStillAttached = false
            fixture.screens.removeLast()
            freshSettings.screen = fixture.screens.first
            host.positionSettingsWindow(freshSettings, force: false, on: screen)
            expect(fixture.screens[0].visibleFrame.contains(freshSettings.frame),
                   "Settings stays reachable if the requested display disconnects before placement")
        }
        for invalidEvent in [nil, event(.keyDown), event(age: 1), event(age: -1)] {
            let fixture = setup(present: false)
            fixture.host.lastStatusClick = (CGPoint(x: 1100, y: 1065), Date())
            fixture.currentEvent = invalidEvent
            fixture.host.captureStatusClick()
            expect(fixture.host.lastStatusClick == nil,
                   "keyboard, accessibility and stale events clear the previous status click")
        }
        for kind in ["requested", "missing event", "other window", "old click", "future click", "outside",
                     "movement", "escape", "key release", "modifier", "no frame", "no window number",
                     "missing button", "missing window", "screen detached", "terminating", "switching"] {
            let fixture = setup()
            let host = fixture.host
            switch kind {
            case "requested": host.popoverCloseIsAppRequested = true
            case "missing event": fixture.currentEvent = nil
            case "other window": fixture.currentEvent = event(window: 72)
            case "old click": fixture.currentEvent = event(age: 1)
            case "future click": fixture.currentEvent = event(age: -1)
            case "outside": fixture.currentEvent = event(location: CGPoint(x: -1, y: 10))
            case "movement": fixture.currentEvent = event(.mouseMoved)
            case "escape": fixture.currentEvent = event(.keyDown)
            case "key release": fixture.currentEvent = event(.keyUp)
            case "modifier": fixture.currentEvent = event(.flagsChanged)
            case "no frame": host.popoverLastFrame = nil
            case "no window number": host.popoverLastWindowNumber = nil
            case "missing button": host.popoverAnchor = nil
            case "missing window": fixture.button!.window = nil
            case "screen detached": fixture.screens[0].isStillAttached = false
            case "terminating": fixture.isTerminating = true
            default: host.popoverIsSwitchingAnchor = true
            }
            close(fixture); fixture.drain()
            expect(!fixture.popover.isShown && fixture.popover.attempts == 1, "no automatic reopen for \(kind)")
        }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp] {
            let fixture = setup(); fixture.currentEvent = event(type); close(fixture)
            expect(fixture.popover.isShown, "fresh click phase \(type.rawValue) targets the panel")
            fixture.drain()
        }
        do {
            let fixture = setup(); fixture.popover.fails = true; close(fixture); fixture.drain()
            expect(!fixture.popover.isShown && !fixture.monitors && fixture.releases > 0
                   && !fixture.badgeHeld && fixture.host.popoverDriftObservers.isEmpty,
                   "failed presentation releases observers, sampling and held status badge")
            expect(!fixture.popoverVisible,
                   "failed presentation leaves panel content inactive")
        }
        do {
            let fixture = setup(); close(fixture); close(fixture); fixture.drain()
            expect(fixture.popover.attempts == 2 && !fixture.popover.isShown && fixture.releases > 0,
                   "a close before recovery completion releases resources without recursion")
        }
        do {
            let fixture = setup()
            let window = fixture.popover.panelWindow!
            window.setFrame(CGRect(x: 600, y: 400, width: 332, height: 650), display: false)
            expect(fixture.host.popoverLastFrame == window.frame, "later movement refreshes the recovery frame")
            fixture.host.popoverCloseIsAppRequested = true; close(fixture)
            expect(fixture.observers.isEmpty, "normal close leaves no geometry observer")
        }
        do {
            let fixture = setup()
            let host = fixture.host
            host.popoverWillClose(Notification(name: Notification.Name("willClose")))
            expect(host.popoverIsClosing && !host.popoverCloseIsAppRequested,
                   "popoverWillClose marks closing in progress without marking app requested")
            fixture.popover.isShown = false
            host.popoverDidClose(Notification(name: Notification.Name("didClose")))
            expect(fixture.popover.isShown && !host.popoverIsClosing && !host.popoverCloseIsAppRequested,
                   "system willClose followed by didClose allows panel recovery and clears closing flags")
        }
        do {
            let fixture = setup()
            let host = fixture.host
            host.popoverCloseIsAppRequested = true
            host.popoverWillClose(Notification(name: Notification.Name("willClose")))
            expect(host.popoverIsClosing && host.popoverCloseIsAppRequested,
                   "app-requested close preserves app-requested flag through willClose")
            fixture.popover.isShown = false
            host.popoverDidClose(Notification(name: Notification.Name("didClose")))
            expect(!fixture.popover.isShown && !host.popoverIsClosing && !host.popoverCloseIsAppRequested,
                   "app-requested willClose followed by didClose stays closed without recovery")
        }
        do {
            let fixture = setup()
            let host = fixture.host
            let sideSettings = fixture.window(CGRect(x: 50, y: 100, width: 400, height: 400))
            sideSettings.windowNumber = 88
            fixture.settingsWindow = sideSettings
            let sideEvent = event(window: 88)!
            expect(!host.shouldDismissPopover(forLocalEvent: sideEvent),
                   "side-by-side Settings window does not dismiss the live preview panel")

            let overlappingSettings = fixture.window(CGRect(x: 500, y: 500, width: 400, height: 400))
            overlappingSettings.windowNumber = 89
            fixture.settingsWindow = overlappingSettings
            let overlapEvent = event(window: 89)!
            expect(host.shouldDismissPopover(forLocalEvent: overlapEvent),
                   "overlapping Settings window dismisses the panel")

            fixture.viewKeepsOpen = true
            expect(!host.shouldDismissPopover(forLocalEvent: overlapEvent),
                   "dismissal protection keeps panel open even when Settings window overlaps")
            fixture.viewKeepsOpen = false

            fixture.presentingModal = true
            expect(!host.shouldDismissPopover(forLocalEvent: overlapEvent),
                   "modal presentation keeps panel open even when Settings window overlaps")
            fixture.presentingModal = false

            let popoverEvent = event(window: 71)!
            expect(!host.shouldDismissPopover(forLocalEvent: popoverEvent),
                   "interaction with the panel itself does not dismiss the popover")

            let unrelatedEvent = event(window: 99)!
            expect(!host.shouldDismissPopover(forLocalEvent: unrelatedEvent),
                   "interaction with unrelated window does not dismiss the popover")
        }
        for reason in [PanelCloseReason.escape, .statusItem, .outsideClick, .action] {
            let fixture = setup()
            requestClose(fixture, reason)
            expect(!fixture.popover.isShown && fixture.handbackReasons == [reason] && !fixture.activationTracking,
                   "a \(reason) close ends activation tracking and passes its reason to the handback")
        }
        do {
            let fixture = setup()
            let host = fixture.host
            host.closePopoverNow(animated: true, reason: .escape, completion: nil)
            host.closePopoverNow(animated: true, reason: .action, completion: nil)
            host.closePopoverNow(animated: true, reason: .statusItem, completion: nil)
            fixture.popover.isShown = false
            host.popoverWillClose(Notification(name: Notification.Name("willClose")))
            host.popoverDidClose(Notification(name: Notification.Name("closed")))
            expect(fixture.handbackReasons == [.action], "an action joining a dismissal keeps activation where it goes")
        }
        do {
            let fixture = setup(); fixture.currentEvent = event(age: 1); close(fixture)
            expect(!fixture.popover.isShown && fixture.handbackReasons == [nil],
                   "a close Vitruvian did not ask for carries no reason to hand activation back")
        }
        do {
            let fixture = setup()
            expect(fixture.activationTrackingStarts == 0, "a panel shown without activating remembers no app")
            requestClose(fixture, .escape)
            fixture.host.showPopover(allowRecentClose: true, animate: false)
            expect(fixture.activationTrackingStarts == 1 && fixture.activationTracking,
                   "a click that activates the panel starts following the app in front")
            requestClose(fixture, .escape)
            expect(!fixture.activationTracking, "closing the panel stops following activation")
        }
        do {
            let fixture = setup(); fixture.activationTracking = true; close(fixture)
            expect(fixture.popover.isShown && fixture.handbackReasons.isEmpty && fixture.activationTracking,
                   "a panel reopened in place after a foreign close keeps activation and its tracking")
            fixture.drain()
            requestClose(fixture, .escape); fixture.drain()
            expect(fixture.handbackReasons == [.escape] && !fixture.activationTracking,
                   "the close after a recovery still hands activation back")
        }
        do {
            let fixture = setup(); fixture.activationTracking = true; fixture.popover.fails = true
            close(fixture); fixture.drain()
            expect(!fixture.popover.isShown && !fixture.activationTracking,
                   "a recovery that fails to reopen stops following activation")
        }
        do {
            let fixture = setup(); fixture.activationTracking = true
            fixture.host.popoverIsSwitchingAnchor = true; requestClose(fixture, .statusItem)
            expect(fixture.handbackReasons.isEmpty && fixture.activationTracking,
                   "moving the panel between metric anchors keeps activation and its tracking")
        }
    }
}
