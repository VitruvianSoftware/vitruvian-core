// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianAtriumCore

/// Clicks on the menu bar's first row above the closed island, which the
/// menu bar owns even above the island's window level. They open the
/// island, or the page of the notice the press landed on. Only mouse clicks
/// are observed, with no event tap and no Accessibility requirement, and
/// only while the island can take them.
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
        /// The notice the strip shows, the outgoing one included, if any.
        package var stripNotice: () -> NotchNotice?
        /// Whether a notice is still current, not just leaving.
        package var hasCurrentNotice: () -> Bool
        /// Whether the island is a capsule floating below the menu bar.
        package var floats: () -> Bool
        /// Whether a point is still on the capsule's strip at its widest,
        /// for a capsule that shrank under a stationary press.
        package var capsuleContains: (CGPoint) -> Bool
        /// A press and release that began on a notice: that notice's action.
        package var activate: (NotchNotice) -> Void

        package init(area: @escaping () -> CGRect?, floatingGap: @escaping () -> CGFloat?,
                     keepsWorkingSurface: @escaping () -> Bool, containsDestination: @escaping (CGPoint) -> Bool,
                     pressed: @escaping () -> Void, clicked: @escaping () -> Void,
                     stripNotice: @escaping () -> NotchNotice? = { nil },
                     hasCurrentNotice: @escaping () -> Bool = { false },
                     floats: @escaping () -> Bool = { false },
                     capsuleContains: @escaping (CGPoint) -> Bool = { _ in false },
                     activate: @escaping (NotchNotice) -> Void = { _ in }) {
            self.area = area
            self.floatingGap = floatingGap
            self.keepsWorkingSurface = keepsWorkingSurface
            self.containsDestination = containsDestination
            self.pressed = pressed
            self.clicked = clicked
            self.stripNotice = stripNotice
            self.hasCurrentNotice = hasCurrentNotice
            self.floats = floats
            self.capsuleContains = capsuleContains
            self.activate = activate
        }
    }

    /// A press on the edge, until it is released: the island's area then,
    /// where it landed, and the notice it landed on, whose action it keeps.
    package struct Press {
        package let area: CGRect
        package let point: CGPoint
        package let notice: NotchNotice?
    }

    private let environment: Environment
    private let island: Island
    private var monitors: [Any] = []
    package private(set) var press: Press?
    /// The island's area when a press began on the edge, until it is released.
    package var pressArea: CGRect? { press?.area }

    package init(environment: Environment, island: Island) {
        self.environment = environment
        self.island = island
    }

    package var isMonitoring: Bool { !monitors.isEmpty }

    /// Watches clicks while the island takes them, and stops otherwise.
    package func sync() {
        guard island.area() != nil else { remove(); return }
        // A newer notice replaced the one the press landed on.
        if let original = press?.notice, let shown = island.stripNotice(), original.clickTarget != shown.clickTarget {
            press = nil
        }
        guard monitors.isEmpty else { return }
        monitors = environment.addMonitors { [weak self] type, locate, isIslandWindow in
            self?.handle(type, locate: locate, isIslandWindow: isIslandWindow)
        }
    }

    package func remove() {
        monitors.forEach(environment.removeMonitor)
        monitors.removeAll()
        press = nil
    }

    private func handle(_ type: EventType, locate: () -> CGPoint?, isIslandWindow: Bool) {
        guard type == .leftMouseDown || press != nil else { return }
        guard let point = locate() else {
            press = nil
            return
        }
        handle(type, at: point, isIslandWindow: isIslandWindow)
    }

    /// One event at a point on screen (y up).
    package func handle(_ type: EventType, at point: CGPoint, isIslandWindow: Bool) {
        guard let area = island.area() else { press = nil; return }
        let local = CGPoint(x: point.x - area.minX, y: area.maxY - point.y)
        switch type {
        case .leftMouseDown:
            press = nil
            // The menu bar a capsule leaves above itself takes its clicks too.
            guard !isIslandWindow, !island.keepsWorkingSurface(),
                  CGRect(x: 0, y: 0, width: area.width, height: 1 + (island.floatingGap() ?? 0)).contains(local),
                  island.containsDestination(point) else { return }
            press = Press(area: area, point: point, notice: island.stripNotice())
            island.pressed()
        case .leftMouseUp:
            let pressed = press
            press = nil
            // Keep the original action through expiry. A notice arriving under a
            // resting press still leaves its wings to the menu bar.
            guard let pressed, !island.keepsWorkingSurface() else { return }
            // A new banner changes even the generic opening to its inbox.
            guard pressed.notice != nil || island.stripNotice()?.notificationID == nil else { return }
            if island.floats(), pressed.notice != nil, !island.hasCurrentNotice(), point == pressed.point {
                // The capsule may have shrunk away from a stationary click.
                // The original point was hit-tested and must still be clear of menus.
                guard island.capsuleContains(point) else { return }
            } else {
                // The hover pulse can settle between press and release; the
                // click stays on the island in either size.
                guard NotchSupport.screenEdgeArea(area, contains: point)
                        || (island.stripNotice() == nil && NotchSupport.screenEdgeArea(pressed.area, contains: point)),
                      island.containsDestination(point) else { return }
            }
            if let original = pressed.notice { island.activate(original) } else { island.clicked() }
        case .leftMouseDragged:
            // A press at the screen's edge reports a drag at once, often without
            // moving. Only a drag that leaves the island cancels the click.
            guard !NotchSupport.screenEdgeArea(area, contains: point),
                  !(press.map { NotchSupport.screenEdgeArea($0.area, contains: point) } ?? false) else { return }
            press = nil
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
        /// Whether the strip shows a notice, the outgoing one included. A
        /// notice takes these clicks too.
        package var hasNotice: Bool
        /// Whether a notification's preview is held open, with controls of its own.
        package var noticeExpanded: Bool
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
                     compactActivityGeometry: NotchGeometry, surfaceSize: CGSize, noticeExpanded: Bool = false) {
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
            self.noticeExpanded = noticeExpanded
        }
    }

    /// Where a click at the top of the screen counts as a click on the
    /// closed island, in screen coordinates, or nil while it takes none.
    package static func area(for island: Resting) -> CGRect? {
        guard island.running, !island.suspended, !island.expanded, !island.hasCaptureControls, !island.noticeExpanded,
              !island.dragPlaceholder, !island.heldDrag, island.panelTakesClicks == true else { return nil }
        let geometry = island.compactActivityIsVisible ? island.compactActivityGeometry : island.geometry
        // A notice can be visible even when a menu occupies the simulated cutout.
        guard geometry.isNotched || geometry.compactSideRoom != nil else { return nil }
        var size = island.surfaceSize
        if geometry.floats { size.width = min(size.width, NotchCapsuleLayout.availableWidth(geometry)) }
        // The menu bar still gets these clicks, so beside a camera a notice
        // leaves the items under its wings alone, as an activity's strip does.
        let area = geometry.activationArea(in: size, hasHeader: island.peeking,
                                           compactActivity: island.compactActivityIsVisible || island.hasNotice)
        guard !area.isEmpty else { return nil }
        let frame = geometry.frame(for: size)
        return CGRect(x: frame.minX + area.minX, y: frame.maxY - area.maxY, width: area.width, height: area.height)
    }

    /// A press at the edge holds hover back until the release decides.
    package static func pressed(hoverWork: inout DispatchWorkItem?, hoverState: inout NotchHoverState) {
        hoverWork?.cancel(); hoverWork = nil
        hoverState.close(pointerInside: true)
    }
}
