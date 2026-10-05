// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// Clicks on the menu bar's first row above the closed island, which the
/// menu bar owns even above the island's window level. They open the
/// island. Only mouse clicks are observed, with no event tap and no
/// Accessibility requirement, and only while the island can take them.
package final class NotchScreenEdgeClicks {
    package typealias EventType = NSEvent.EventType

    /// How the clicks reach the system's events. The app passes `.system`.
    package struct Environment {
        /// Starts watching left-button presses, drags and releases, in this
        /// app and in others, and returns what `removeMonitor` takes. Each
        /// event reports its type, finds its point on screen (y up, measured
        /// from the bottom of the display with the menu bar) only when
        /// asked, and says whether the island's own window received it.
        package var addMonitors: (_ handler: @escaping (EventType, () -> CGPoint?, Bool) -> Void) -> [Any]
        package var removeMonitor: (Any) -> Void

        package init(addMonitors: @escaping (_ handler: @escaping (EventType, () -> CGPoint?, Bool) -> Void) -> [Any],
                     removeMonitor: @escaping (Any) -> Void) {
            self.addMonitors = addMonitors
            self.removeMonitor = removeMonitor
        }

        package static func system(islandWindow: @escaping () -> NSWindow?) -> Environment {
            Environment(addMonitors: { handler in
                let events: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
                let deliver: (NSEvent) -> Void = { event in
                    handler(event.type, {
                        guard let location = event.cgEvent?.location, let primary = NSScreen.withMenuBar else { return nil }
                        return CGPoint(x: location.x, y: primary.frame.maxY - location.y)
                    }, event.window === islandWindow())
                }
                var tokens: [Any] = []
                if let token = NSEvent.addGlobalMonitorForEvents(matching: events, handler: deliver) { tokens.append(token) }
                if let token = NSEvent.addLocalMonitorForEvents(matching: events, handler: { deliver($0); return $0 }) {
                    tokens.append(token)
                }
                return tokens
            }, removeMonitor: NSEvent.removeMonitor)
        }
    }

    /// The island's side of a click, read as each event arrives.
    package struct Island {
        /// Where the island takes edge clicks on screen, or nil while it takes none.
        package var area: () -> CGRect?
        /// The gap a floating capsule leaves below the top edge.
        package var floatingGap: () -> CGFloat?
        /// A menu or a modal on the island keeps its own clicks.
        package var keepsWorkingSurface: () -> Bool
        /// Whether the island's window reaches a point, so transparent corners do not count.
        package var containsDestination: (CGPoint) -> Bool
        /// A press began on the edge: the island stops reacting to hover until it is released.
        package var pressed: () -> Void
        /// A press and release on the edge: the island opens.
        package var clicked: () -> Void

        package init(area: @escaping () -> CGRect?, floatingGap: @escaping () -> CGFloat?,
                     keepsWorkingSurface: @escaping () -> Bool, containsDestination: @escaping (CGPoint) -> Bool,
                     pressed: @escaping () -> Void, clicked: @escaping () -> Void) {
            self.area = area
            self.floatingGap = floatingGap
            self.keepsWorkingSurface = keepsWorkingSurface
            self.containsDestination = containsDestination
            self.pressed = pressed
            self.clicked = clicked
        }
    }

    private let environment: Environment
    private let island: Island
    private var monitors: [Any] = []
    /// The island's area when a press began on the edge, until it is released.
    package private(set) var pressArea: CGRect?

    package init(environment: Environment, island: Island) {
        self.environment = environment
        self.island = island
    }

    package var isMonitoring: Bool { !monitors.isEmpty }

    /// Watches clicks while the island takes them, and stops otherwise.
    package func sync() {
        guard island.area() != nil else { remove(); return }
        guard monitors.isEmpty else { return }
        monitors = environment.addMonitors { [weak self] type, locate, isIslandWindow in
            self?.handle(type, locate: locate, isIslandWindow: isIslandWindow)
        }
    }

    package func remove() {
        monitors.forEach(environment.removeMonitor)
        monitors.removeAll()
        pressArea = nil
    }

    private func handle(_ type: EventType, locate: () -> CGPoint?, isIslandWindow: Bool) {
        guard type == .leftMouseDown || pressArea != nil else { return }
        guard let point = locate() else {
            pressArea = nil
            return
        }
        handle(type, at: point, isIslandWindow: isIslandWindow)
    }

    /// One event at a point on screen (y up).
    package func handle(_ type: EventType, at point: CGPoint, isIslandWindow: Bool) {
        guard let area = island.area() else { pressArea = nil; return }
        let local = CGPoint(x: point.x - area.minX, y: area.maxY - point.y)
        switch type {
        case .leftMouseDown:
            pressArea = nil
            // The menu bar a capsule leaves above itself takes its clicks too.
            guard !isIslandWindow, !island.keepsWorkingSurface(),
                  CGRect(x: 0, y: 0, width: area.width, height: 1 + (island.floatingGap() ?? 0)).contains(local),
                  island.containsDestination(point) else { return }
            pressArea = area
            island.pressed()
        case .leftMouseUp:
            let pressedArea = pressArea
            pressArea = nil
            // The hover pulse can settle between press and release; the click
            // stays on the island in either size.
            guard let pressed = pressedArea,
                  NotchSupport.screenEdgeArea(pressed, contains: point) || NotchSupport.screenEdgeArea(area, contains: point),
                  island.containsDestination(point) else { return }
            island.clicked()
        case .leftMouseDragged:
            // A press at the screen's edge reports a drag at once, often without
            // moving. Only a drag that leaves the island cancels the click.
            guard !NotchSupport.screenEdgeArea(area, contains: point),
                  !(pressArea.map { NotchSupport.screenEdgeArea($0, contains: point) } ?? false) else { return }
            pressArea = nil
        default:
            break
        }
    }
}

extension NotchScreenEdgeClicks {
    /// The closed island as the screen edge sees it.
    package struct Resting {
        package var running: Bool
        package var suspended: Bool
        package var expanded: Bool
        package var peeking: Bool
        package var hasCaptureControls: Bool
        package var hasNotice: Bool
        package var dragPlaceholder: Bool
        package var heldDrag: Bool
        /// Whether the island's window is on screen and takes clicks; nil without one.
        package var panelTakesClicks: Bool?
        package var compactActivityIsVisible: Bool
        package var geometry: NotchGeometry
        package var compactActivityGeometry: NotchGeometry
        package var surfaceSize: CGSize

        package init(running: Bool, suspended: Bool, expanded: Bool, peeking: Bool, hasCaptureControls: Bool,
                     hasNotice: Bool, dragPlaceholder: Bool, heldDrag: Bool, panelTakesClicks: Bool?,
                     compactActivityIsVisible: Bool, geometry: NotchGeometry,
                     compactActivityGeometry: NotchGeometry, surfaceSize: CGSize) {
            self.running = running
            self.suspended = suspended
            self.expanded = expanded
            self.peeking = peeking
            self.hasCaptureControls = hasCaptureControls
            self.hasNotice = hasNotice
            self.dragPlaceholder = dragPlaceholder
            self.heldDrag = heldDrag
            self.panelTakesClicks = panelTakesClicks
            self.compactActivityIsVisible = compactActivityIsVisible
            self.geometry = geometry
            self.compactActivityGeometry = compactActivityGeometry
            self.surfaceSize = surfaceSize
        }
    }

    /// Where a click at the top of the screen counts as a click on the
    /// closed island, in screen coordinates, or nil while it takes none.
    package static func area(for island: Resting) -> CGRect? {
        guard island.running, !island.suspended, !island.expanded, !island.hasCaptureControls, !island.hasNotice,
              !island.dragPlaceholder, !island.heldDrag, island.panelTakesClicks == true else { return nil }
        let geometry = island.compactActivityIsVisible ? island.compactActivityGeometry : island.geometry
        let area = geometry.activationArea(in: island.surfaceSize, hasHeader: island.peeking,
                                           compactActivity: island.compactActivityIsVisible)
        guard !area.isEmpty else { return nil }
        let frame = geometry.frame(for: island.surfaceSize)
        return CGRect(x: frame.minX + area.minX, y: frame.maxY - area.maxY, width: area.width, height: area.height)
    }

    /// A press at the edge holds hover back until the release decides.
    package static func pressed(hoverWork: inout DispatchWorkItem?, hoverState: inout NotchHoverState) {
        hoverWork?.cancel(); hoverWork = nil
        hoverState.close(pointerInside: true)
    }
}
