// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The module's own `NotchScreenEdgeClicks` with controlled event delivery,
/// never posted input. The island's click area and its reaction to a press
/// come from production, copied from `NotchService` into `Service`.
enum NotchScreenEdgeClickTests {
    final class Panel { var isVisible = true; var ignoresMouseEvents = false }
    final class Host { var acceptsPoint = true; func containsDestination(_ point: CGPoint) -> Bool { acceptsPoint } }
    /// The system's event monitors: each one installed is a handler here.
    enum Monitors {
        typealias Handler = (NSEvent.EventType, () -> CGPoint?, Bool) -> Void
        nonisolated(unsafe) static var handlers: [Int: Handler] = [:]
        nonisolated(unsafe) static var nextID = 0
        nonisolated(unsafe) static let environment = NotchScreenEdgeClicks.Environment(
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
        var captureControls: Bool?, notice: Bool?
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
        var screenEdgeClicks: NotchScreenEdgeClicks!
        func syncScreenEdgeClicks() { screenEdgeClicks.sync() }
        func removeScreenEdgeClickMonitors() { screenEdgeClicks.remove() }
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
                clicked: { [unowned service] in service.open() }))
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
            { $0.captureControls = true }, { $0.notice = true }, { $0.dragPlaceholder = true }, { $0.heldDrag = true }
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
        service.geometry = NotchGeometry(screen: service.geometry.screen, safeAreaTop: 0, cameraWidth: 0)
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
                                             silhouette: .capsule)
            capsule.syncScreenEdgeClicks()
            let point = CGPoint(x: capsule.geometry.screen.midX, y: capsule.geometry.screen.maxY - depth)
            capsule.screenEdgeClicks.handle(.leftMouseDown, at: point, isIslandWindow: false)
            capsule.screenEdgeClicks.handle(.leftMouseUp, at: point, isIslandWindow: false)
            suite.expect(capsule.openings == (opens ? 1 : 0),
                         "a click \(depth) points below the top edge \(opens ? "opens" : "leaves") a floating capsule")
            capsule.removeScreenEdgeClickMonitors()
        }
    }
}
