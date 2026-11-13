// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianAtriumCore
import VitruvianAtriumDesign
import VitruvianAtriumServices
import VitruvianAtriumUI

/// The module's own `NotchScreenEdgeClicks` with controlled event delivery,
/// never posted input. The island's click area and its reaction to a press
/// are the module's, fed this island's state the way `NotchService` feeds them.
enum NotchScreenEdgeClickTests {
    final class Panel { var isVisible = true; var ignoresMouseEvents = false }
    final class Host { var acceptsPoint = true; func containsDestination(_ point: CGPoint) -> Bool { acceptsPoint } }
    /// The system's event monitors: each one installed is a handler here.
    enum Monitors {
        typealias Handler = (NSEvent.EventType, () -> CGPoint?, Bool) -> Void
        static var handlers: [Int: Handler] = [:]
        static var nextID = 0
        static let environment = NotchScreenEdgeClicks.Environment(
            addMonitors: { handler in
                // A global and a local monitor, as the app installs.
                (0..<2).map { _ -> Any in
                    nextID += 1
                    handlers[nextID] = handler
                    return nextID
                }
            },
            removeMonitor: { handlers[$0 as! Int] = nil })
    }
    class State {
        var running = true, suspended = false, expanded = false, peeking = false
        var captureControls: Bool?, notice: NotchNotice?, departingNotice: NotchNotice?
        var noticeExpanded = false
        var stripNotice: NotchNotice? { notice ?? (expanded || peeking ? nil : departingNotice) }
        var dragPlaceholder = false, heldDrag = false, compactActivityIsVisible = false, keepsWorkingSurface = false
        var panel: Panel? = Panel()
        var windowHost: Host? = Host()
        var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                     safeAreaTop: 32, cameraWidth: 180)
        var compactActivityGeometry: NotchGeometry { geometry }
        var hoverEmphasized = false
        var surfaceSize: CGSize {
            let size = peeking ? geometry.expanded : compactActivityIsVisible ? geometry.compactActivitySize : geometry.collapsed
            return hoverEmphasized ? NotchHoverEmphasis.size(from: size, geometry: geometry) : size
        }
        var hoverWork: DispatchWorkItem?
        var hoverState = NotchHoverState()
        var openings = 0
        /// The notices a click on the edge acted on, in order.
        var activated: [NotchNotice] = []
        var screenEdgeClicks: NotchScreenEdgeClicks!
        func syncScreenEdgeClicks() { screenEdgeClicks.sync() }
        func removeScreenEdgeClickMonitors() { screenEdgeClicks.remove() }
    }

    final class Service: State {
        func open() { openings += 1; expanded = true; syncScreenEdgeClicks() }
        func activate(_ notice: NotchNotice) {
            activated.append(notice)
            self.notice = nil
            departingNotice = nil
            expanded = true
            syncScreenEdgeClicks()
        }
        var screenEdgeClickArea: CGRect? {
            NotchScreenEdgeClicks.area(for: .init(
                running: running, suspended: suspended, expanded: expanded, peeking: peeking,
                hasCaptureControls: captureControls != nil, hasNotice: stripNotice != nil,
                dragPlaceholder: dragPlaceholder, heldDrag: heldDrag,
                panelTakesClicks: panel.map { $0.isVisible && !$0.ignoresMouseEvents },
                compactActivityIsVisible: compactActivityIsVisible, geometry: geometry,
                compactActivityGeometry: compactActivityGeometry, surfaceSize: surfaceSize,
                noticeExpanded: noticeExpanded))
        }
        func screenEdgePressed() {
            NotchScreenEdgeClicks.pressed(hoverWork: &hoverWork, hoverState: &hoverState)
        }
    }

    /// Wired the way `NotchService` wires its own.
    static func makeService() -> Service {
        let service = Service()
        service.screenEdgeClicks = NotchScreenEdgeClicks(
            environment: Monitors.environment,
            island: NotchScreenEdgeClicks.Island(
                area: { [unowned service] in service.screenEdgeClickArea },
                floatingGap: { [unowned service] in service.geometry.floatingGap },
                keepsWorkingSurface: { [unowned service] in service.keepsWorkingSurface },
                containsDestination: { [unowned service] in service.windowHost?.containsDestination($0) == true },
                pressed: { [unowned service] in service.screenEdgePressed() },
                clicked: { [unowned service] in service.open() },
                stripNotice: { [unowned service] in service.stripNotice },
                hasCurrentNotice: { [unowned service] in service.notice != nil },
                floats: { [unowned service] in service.geometry.floats },
                capsuleContains: { [unowned service] point in
                    let geometry = service.geometry
                    let free = CGSize(width: NotchCapsuleLayout.availableWidth(geometry), height: geometry.stripHeight)
                    return geometry.contains(point, in: free)
                },
                activate: { [unowned service] in service.activate($0) }))
        return service
    }

    static func run(_ suite: TestSuite) {
        for screen in [CGRect(x: 0, y: 0, width: 1470, height: 956),
                       CGRect(x: -1920, y: 956, width: 1920, height: 1080)] {
            let service = makeService()
            service.geometry = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 180)
            service.syncScreenEdgeClicks()
            for _ in 0..<100 { service.syncScreenEdgeClicks() }
            suite.expect(Monitors.handlers.count == 2 && service.screenEdgeClicks.isMonitoring,
                         "refreshes keep exactly one pair of edge-click monitors")
            let top = CGPoint(x: screen.midX, y: screen.maxY)
            func send(_ type: NSEvent.EventType, _ point: CGPoint, window: Panel? = nil) {
                // Each event reaches one monitor, as in this app or another one.
                Monitors.handlers.values.first?(type, { point }, window != nil && window === service.panel)
            }
            send(.leftMouseUp, top)
            send(.leftMouseDown, CGPoint(x: screen.minX, y: screen.maxY)); send(.leftMouseUp, top)
            send(.leftMouseDown, CGPoint(x: top.x, y: top.y - 2)); send(.leftMouseUp, top)
            send(.leftMouseDown, CGPoint(x: top.x, y: top.y + 0.5)); send(.leftMouseUp, top)
            send(.leftMouseDown, top, window: service.panel); send(.leftMouseUp, top)
            suite.expect(service.openings == 0, "release-only, nearby menus, lower clicks and native notch clicks never cause duplicate opening")
            send(.leftMouseDown, top); send(.leftMouseDragged, CGPoint(x: screen.minX, y: screen.maxY)); send(.leftMouseUp, top)
            send(.leftMouseDown, top); send(.leftMouseUp, CGPoint(x: screen.minX, y: screen.maxY))
            suite.expect(service.openings == 0, "dragging off the island or releasing outside cancels an edge click")
            service.windowHost?.acceptsPoint = false
            send(.leftMouseDown, top); send(.leftMouseUp, top)
            service.windowHost?.acceptsPoint = true
            service.keepsWorkingSurface = true
            send(.leftMouseDown, top); send(.leftMouseUp, top)
            service.keepsWorkingSurface = false
            suite.expect(service.openings == 0, "transparent corners and an active menu or modal preserve their own interactions")
            send(.leftMouseDown, top)
            Monitors.handlers.values.first?(.leftMouseUp, { nil }, false)
            suite.expect(service.openings == 0 && service.screenEdgeClicks.pressArea == nil,
                         "an event with no point on screen drops the press")
            let pendingHover = DispatchWorkItem {}
            service.hoverWork = pendingHover
            send(.leftMouseDown, top)
            suite.expect(service.openings == 0 && pendingHover.isCancelled && service.hoverState.suppressed,
                         "pressing the edge cancels hover and waits for release")
            send(.leftMouseUp, CGPoint(x: top.x, y: top.y - 0.5))
            suite.expect(service.openings == 1 && Monitors.handlers.isEmpty,
                         "a menu-bar click opens exactly once on either display, then removes both monitors")
            service.removeScreenEdgeClickMonitors()
        }
        for disable in [
            { (s: Service) in s.running = false }, { $0.suspended = true }, { $0.expanded = true },
            { $0.panel?.isVisible = false }, { $0.panel?.ignoresMouseEvents = true },
            { $0.captureControls = true }, { $0.notice = track; $0.noticeExpanded = true },
            { $0.dragPlaceholder = true }, { $0.heldDrag = true }
        ] {
            let service = makeService()
            service.syncScreenEdgeClicks()
            let point = CGPoint(x: service.geometry.screen.midX, y: service.geometry.screen.maxY)
            service.screenEdgeClicks.handle(.leftMouseDown, at: point, isIslandWindow: false)
            disable(service)
            service.syncScreenEdgeClicks()
            service.screenEdgeClicks.handle(.leftMouseUp, at: point, isIslandWindow: false)
            suite.expect(service.openings == 0 && service.screenEdgeClicks.pressArea == nil
                         && Monitors.handlers.isEmpty,
                         "leaving an eligible presentation cancels the press and removes every monitor")
        }
        let steady = makeService()
        steady.syncScreenEdgeClicks()
        let edge = CGPoint(x: steady.geometry.screen.midX, y: steady.geometry.screen.maxY)
        steady.screenEdgeClicks.handle(.leftMouseDown, at: edge, isIslandWindow: false)
        steady.screenEdgeClicks.handle(.leftMouseDragged, at: edge, isIslandWindow: false)
        steady.screenEdgeClicks.handle(.leftMouseDragged, at: CGPoint(x: edge.x + 3, y: edge.y - 2), isIslandWindow: false)
        steady.screenEdgeClicks.handle(.leftMouseUp, at: edge, isIslandWindow: false)
        suite.expect(steady.openings == 1,
                     "the drag a press at the screen's edge reports, within the island, keeps the click")
        steady.removeScreenEdgeClickMonitors()
        let late = makeService()
        late.geometry = NotchGeometry(screen: late.geometry.screen, safeAreaTop: 32, cameraWidth: 180, compactSideRoom: 64)
        late.syncScreenEdgeClicks()
        guard let resting = late.screenEdgeClickArea else { suite.expect(false, "a resting island takes edge clicks"); return }
        let centre = CGPoint(x: resting.midX, y: resting.maxY)
        late.screenEdgeClicks.handle(.leftMouseDown, at: centre, isIslandWindow: false)
        // The entry is reported after the press, so the pulse lands before the release.
        late.hoverEmphasized = true
        guard let pulsed = late.screenEdgeClickArea else { suite.expect(false, "a pulsing island takes edge clicks"); return }
        // Released where only the grown island reaches.
        late.screenEdgeClicks.handle(.leftMouseUp, at: CGPoint(x: pulsed.maxX - 4, y: pulsed.maxY), isIslandWindow: false)
        suite.expect(pulsed.maxX - 4 > resting.maxX && late.openings == 1,
                     "a click the hover pulse grows under still opens the island")
        late.removeScreenEdgeClickMonitors()
        let service = makeService()
        service.geometry = NotchGeometry(screen: service.geometry.screen, safeAreaTop: 0, cameraWidth: 0,
                                         compactSideRoom: 0)
        service.compactActivityIsVisible = true
        service.syncScreenEdgeClicks()
        suite.expect(service.screenEdgeClickArea?.width == service.geometry.cameraWidth
                     && service.screenEdgeClickArea?.maxY == service.geometry.screen.maxY,
                     "the simulated camera retains the same screen-edge activation area as a physical cutout")
        let point = CGPoint(x: service.geometry.screen.midX, y: service.geometry.screen.maxY)
        service.screenEdgeClicks.handle(.leftMouseDown, at: point, isIslandWindow: false)
        service.screenEdgeClicks.handle(.leftMouseUp, at: point, isIslandWindow: false)
        suite.expect(service.openings == 1 && !service.screenEdgeClicks.isMonitoring,
                     "clicking the top edge opens a simulated notch exactly once and stops its closed-state monitors")
        // A capsule floats below the top edge; the menu bar above it still
        // opens it, and the capsule itself takes its own clicks.
        for (depth, opens) in [(CGFloat(0), true), (1.5, true), (2.5, true), (3.5, false)] {
            let capsule = makeService()
            capsule.geometry = NotchGeometry(screen: capsule.geometry.screen, safeAreaTop: 0, cameraWidth: 0,
                                             compactSideRoom: 64, silhouette: .capsule)
            capsule.syncScreenEdgeClicks()
            let point = CGPoint(x: capsule.geometry.screen.midX, y: capsule.geometry.screen.maxY - depth)
            capsule.screenEdgeClicks.handle(.leftMouseDown, at: point, isIslandWindow: false)
            capsule.screenEdgeClicks.handle(.leftMouseUp, at: point, isIslandWindow: false)
            suite.expect(capsule.openings == (opens ? 1 : 0),
                         "a click \(depth) points below the top edge \(opens ? "opens" : "leaves") a floating capsule")
            capsule.removeScreenEdgeClickMonitors()
        }
        runNotices(suite)
    }

    private static let track = NotchNotice(event: .track, title: "Song", detail: "Artist", symbol: "music.note")
    private static let volume = NotchNotice(event: .volume, title: "Volume", detail: "50%", symbol: "speaker.wave.2.fill")

    /// The menu bar owns the top row, so a notice needs these clicks as much
    /// as the resting island does, and a press keeps the notice it landed on.
    private static func runNotices(_ suite: TestSuite) {
        for shown in [track, volume] {
            let service = makeService()
            service.notice = shown
            service.syncScreenEdgeClicks()
            let top = CGPoint(x: service.geometry.screen.midX, y: service.geometry.screen.maxY)
            service.screenEdgeClicks.handle(.leftMouseDown, at: top, isIslandWindow: false)
            service.screenEdgeClicks.handle(.leftMouseUp, at: top, isIslandWindow: false)
            suite.expect(service.activated == [shown] && service.openings == 0 && !service.screenEdgeClicks.isMonitoring,
                         "a top-edge click on a \(shown.event) notice acts on that notice, then removes the monitors")
        }
        let native = makeService()
        native.notice = track
        native.syncScreenEdgeClicks()
        let nativeTop = CGPoint(x: native.geometry.screen.midX, y: native.geometry.screen.maxY)
        native.screenEdgeClicks.handle(.leftMouseDown, at: nativeTop, isIslandWindow: true)
        native.screenEdgeClicks.handle(.leftMouseUp, at: nativeTop, isIslandWindow: true)
        suite.expect(native.activated.isEmpty && native.openings == 0,
                     "a click the notice's own window receives is not handled twice")
        native.removeScreenEdgeClickMonitors()

        for stillDeparting in [true, false] {
            let expiring = makeService()
            expiring.notice = track
            expiring.syncScreenEdgeClicks()
            let top = CGPoint(x: expiring.geometry.screen.midX, y: expiring.geometry.screen.maxY)
            expiring.screenEdgeClicks.handle(.leftMouseDown, at: top, isIslandWindow: false)
            expiring.notice = nil
            expiring.departingNotice = stillDeparting ? track : nil
            expiring.syncScreenEdgeClicks()
            expiring.screenEdgeClicks.handle(.leftMouseUp, at: top, isIslandWindow: false)
            suite.expect(expiring.activated == [track] && expiring.openings == 0,
                         "the press keeps its notice through the outgoing animation and after expiry")
            expiring.removeScreenEdgeClickMonitors()
        }

        let arriving = makeService()
        arriving.syncScreenEdgeClicks()
        let top = CGPoint(x: arriving.geometry.screen.midX, y: arriving.geometry.screen.maxY)
        arriving.screenEdgeClicks.handle(.leftMouseDown, at: top, isIslandWindow: false)
        arriving.notice = volume
        arriving.screenEdgeClicks.handle(.leftMouseUp, at: top, isIslandWindow: false)
        suite.expect(arriving.openings == 1 && arriving.activated.isEmpty,
                     "a press on the resting island keeps its normal opening when a notice arrives")

        let winged = makeService()
        winged.notice = track
        winged.syncScreenEdgeClicks()
        let wing = CGPoint(x: winged.geometry.screen.midX + 150, y: winged.geometry.screen.maxY)
        winged.screenEdgeClicks.handle(.leftMouseDown, at: wing, isIslandWindow: false)
        winged.screenEdgeClicks.handle(.leftMouseUp, at: wing, isIslandWindow: false)
        suite.expect(winged.screenEdgeClickArea?.width == winged.geometry.cameraWidth
                     && winged.screenEdgeClickArea?.midX == winged.geometry.screen.midX
                     && winged.activated.isEmpty && winged.openings == 0,
                     "beside a camera a notice takes top-edge clicks over the camera only")
        winged.removeScreenEdgeClickMonitors()

        let first = NotchNotice(event: .systemNotification, title: "First", detail: "", symbol: "bell",
                                notificationID: UUID())
        let next = NotchNotice(event: .systemNotification, title: "Next", detail: "", symbol: "bell",
                               notificationID: UUID())
        let banner = makeService()
        banner.syncScreenEdgeClicks()
        banner.screenEdgeClicks.handle(.leftMouseDown, at: top, isIslandWindow: false)
        banner.notice = first
        banner.syncScreenEdgeClicks()
        banner.screenEdgeClicks.handle(.leftMouseUp, at: top, isIslandWindow: false)
        suite.expect(banner.notice == first && banner.openings == 0 && banner.activated.isEmpty,
                     "a banner arriving over a resting press keeps its message and its native action")
        for expires in [false, true] {
            banner.notice = first
            banner.syncScreenEdgeClicks()
            banner.screenEdgeClicks.handle(.leftMouseDown, at: top, isIslandWindow: false)
            banner.notice = next
            banner.syncScreenEdgeClicks()
            if expires { banner.notice = nil; banner.syncScreenEdgeClicks() }
            banner.screenEdgeClicks.handle(.leftMouseUp, at: top, isIslandWindow: false)
            suite.expect(banner.activated.isEmpty && banner.openings == 0,
                         "a replacement cancels the old press even if the replacement also expires")
        }
        banner.notice = next
        banner.syncScreenEdgeClicks()
        banner.screenEdgeClicks.handle(.leftMouseDown, at: top, isIslandWindow: false)
        banner.screenEdgeClicks.handle(.leftMouseUp, at: top, isIslandWindow: false)
        suite.expect(banner.activated == [next], "a new press acts on the replacement banner")
        banner.removeScreenEdgeClickMonitors()

        let meter = makeService()
        let reading = NotchNotice(event: .volume, title: "Volume", detail: "50%", symbol: "speaker", level: 0.5)
        meter.notice = reading
        meter.syncScreenEdgeClicks()
        meter.screenEdgeClicks.handle(.leftMouseDown, at: top, isIslandWindow: false)
        meter.notice = NotchNotice(event: .volume, title: "Volume", detail: "60%", symbol: "speaker", level: 0.6)
        meter.syncScreenEdgeClicks()
        meter.screenEdgeClicks.handle(.leftMouseUp, at: top, isIslandWindow: false)
        suite.expect(meter.activated == [reading], "an updated level keeps the original control's click")
        meter.removeScreenEdgeClickMonitors()
    }
}
