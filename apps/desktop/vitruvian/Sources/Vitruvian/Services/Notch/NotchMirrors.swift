// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// What a copy of the island asks of the window that draws it.
/// `NotchWindowHost` is the real one; tests stand in for it.
package protocol NotchMirrorHost: AnyObject {
    var panelSharingType: NSWindow.SharingType { get set }
    var panelIsVisible: Bool { get }
    /// The window's number while it is on screen, so screenshots can leave it out.
    var visibleWindowID: CGWindowID? { get }
    func orderPanelFront()
    func presentCopy(size: CGSize, geometry: NotchGeometry, animated: Bool, transitionContent: NotchContentTransition)
    func hideCopy()
    func close()
    func setOutline(enabled: Bool, color: NSColor)
    func setActivationArea(_ rect: CGRect, title: String, willPress: @escaping () -> Void, activate: @escaping () -> Void)
}

// The island's mirrors drive their hosts on the main thread.
extension NotchWindowHost: @preconcurrency NotchMirrorHost {
    package var panelSharingType: NSWindow.SharingType {
        get { panel.sharingType }
        set { panel.sharingType = newValue }
    }
    package var panelIsVisible: Bool { panel.isVisible }
    package var visibleWindowID: CGWindowID? {
        panel.isVisible && panel.windowNumber > 0 ? CGWindowID(panel.windowNumber) : nil
    }
    package func orderPanelFront() { panel.orderFrontRegardless() }
    package func presentCopy(size: CGSize, geometry: NotchGeometry, animated: Bool,
                             transitionContent: NotchContentTransition) {
        present(size: size, geometry: geometry, animated: animated, transitionContent: transitionContent)
    }
    package func hideCopy() { hide(animated: false) }
}

/// A copy's window, whatever built it: the island's copies take theirs from
/// its environment.
package final class AnyNotchMirrorHost: NotchMirrorHost {
    private let host: any NotchMirrorHost

    package init(_ host: any NotchMirrorHost) {
        self.host = host
    }

    package var panelSharingType: NSWindow.SharingType {
        get { host.panelSharingType }
        set { host.panelSharingType = newValue }
    }
    package var panelIsVisible: Bool { host.panelIsVisible }
    package var visibleWindowID: CGWindowID? { host.visibleWindowID }
    package func orderPanelFront() { host.orderPanelFront() }
    package func presentCopy(size: CGSize, geometry: NotchGeometry, animated: Bool,
                             transitionContent: NotchContentTransition) {
        host.presentCopy(size: size, geometry: geometry, animated: animated, transitionContent: transitionContent)
    }
    package func hideCopy() { host.hideCopy() }
    package func close() { host.close() }
    package func setOutline(enabled: Bool, color: NSColor) { host.setOutline(enabled: enabled, color: color) }
    package func setActivationArea(_ rect: CGRect, title: String, willPress: @escaping () -> Void,
                                   activate: @escaping () -> Void) {
        host.setActivationArea(rect, title: title, willPress: willPress, activate: activate)
    }
}

/// The closed island as every other display draws it, each copy in a window
/// of its own. With the island on every display, it follows the pointer as
/// it does when it only follows it, and each other display shows a copy of
/// what it shows closed. The copies are drawn for their own displays, a
/// capsule or a notch, and they take no part in hovering or notices. A click
/// on one asks for the island there.
package final class NotchMirrors<Host: NotchMirrorHost> {
    /// One attached display, as the copies need it.
    package struct Display {
        package let id: CGDirectDisplayID
        /// Whether a menu bar shows there, which a copy may have to give way to.
        package let hasMenuBar: Bool

        package init(id: CGDirectDisplayID, hasMenuBar: Bool) {
            self.id = id
            self.hasMenuBar = hasMenuBar
        }
    }

    /// The island while it shows copies: where it is and what it shows closed.
    package struct Island {
        package var displayID: CGDirectDisplayID?
        package var activity: NotchCompactActivity?
        package var companion: NotchCompactActivity?
        package var showsIdleContent: Bool

        package init(displayID: CGDirectDisplayID?, activity: NotchCompactActivity?,
                     companion: NotchCompactActivity?, showsIdleContent: Bool) {
            self.displayID = displayID
            self.activity = activity
            self.companion = companion
            self.showsIdleContent = showsIdleContent
        }
    }

    /// The displays, Spaces and preferences the copies follow. The app reads
    /// the system's; tests pass their own.
    package struct Environment {
        package var displays: () -> [Display]
        /// The island at rest on a display, as the island would be drawn there.
        package var baseGeometry: (CGDirectDisplayID) -> NotchGeometry?
        /// Which of these displays show a full-screen Space.
        package var fullscreenDisplays: ([CGDirectDisplayID]) -> Set<CGDirectDisplayID>
        package var hidesUntilHover: () -> Bool
        package var coversMenus: () -> Bool
        package var showsInCaptures: () -> Bool
        package var outlineEnabled: () -> Bool
        package var hidesInFullscreen: () -> Bool
        package var openTitle: () -> String

        package init(displays: @escaping () -> [Display],
                     baseGeometry: @escaping (CGDirectDisplayID) -> NotchGeometry?,
                     fullscreenDisplays: @escaping ([CGDirectDisplayID]) -> Set<CGDirectDisplayID>,
                     hidesUntilHover: @escaping () -> Bool,
                     coversMenus: @escaping () -> Bool,
                     showsInCaptures: @escaping () -> Bool,
                     outlineEnabled: @escaping () -> Bool,
                     hidesInFullscreen: @escaping () -> Bool,
                     openTitle: @escaping () -> String) {
            self.displays = displays
            self.baseGeometry = baseGeometry
            self.fullscreenDisplays = fullscreenDisplays
            self.hidesUntilHover = hidesUntilHover
            self.coversMenus = coversMenus
            self.showsInCaptures = showsInCaptures
            self.outlineEnabled = outlineEnabled
            self.hidesInFullscreen = hidesInFullscreen
            self.openTitle = openTitle
        }
    }

    /// A copy: the window that draws it and what it draws.
    package struct Copy {
        package let host: Host
        package let model: NotchMirrorModel
    }

    package private(set) var copies: [CGDirectDisplayID: Copy] = [:]
    /// Displays showing a full-screen Space, read as Spaces change.
    package private(set) var fullscreenDisplays: Set<CGDirectDisplayID> = []

    private let environment: Environment
    private let island: () -> Island?
    private let stripSize: (NotchCompactActivity, NotchCompactActivity?, NotchGeometry) -> CGSize
    private let compactGeometry: (NotchCompactActivity, NotchCompactActivity?, NotchGeometry) -> NotchGeometry
    private let makeHost: (NotchMirrorModel, NotchGeometry, CGSize) -> Host
    private let activate: (CGDirectDisplayID) -> Void

    /// `island` is nil while there are to be no copies: the island is not on
    /// every display, not running, or has no window. `stripSize` and
    /// `compactGeometry` size a capsule's strip and a camera's strip as the
    /// island sizes its own. `activate` brings the island to a display.
    package init(environment: Environment,
                 island: @escaping () -> Island?,
                 stripSize: @escaping (NotchCompactActivity, NotchCompactActivity?, NotchGeometry) -> CGSize,
                 compactGeometry: @escaping (NotchCompactActivity, NotchCompactActivity?, NotchGeometry) -> NotchGeometry,
                 makeHost: @escaping (NotchMirrorModel, NotchGeometry, CGSize) -> Host,
                 activate: @escaping (CGDirectDisplayID) -> Void) {
        self.environment = environment
        self.island = island
        self.stripSize = stripSize
        self.compactGeometry = compactGeometry
        self.makeHost = makeHost
        self.activate = activate
    }

    /// Whether another display shows a copy of the closed island now.
    package var showsAny: Bool { copies.values.contains { $0.model.shown } }
    /// Whether any copy is a capsule, whose width follows a song's title.
    package var hasCapsule: Bool { copies.values.contains { $0.model.geometry.floats } }
    package var visibleWindowIDs: [CGWindowID] { copies.values.compactMap { $0.host.visibleWindowID } }

    package func sync() {
        guard let island = island() else { close(); return }
        let displays = environment.displays()
        for (id, copy) in copies where !displays.contains(where: { $0.id == id }) {
            copy.host.close()
            copies[id] = nil
        }
        // An island hidden until the pointer reaches it hides its copies as well.
        let hidesAtRest = environment.hidesUntilHover()
        let outline = environment.outlineEnabled()
        let activity = island.activity
        for display in displays {
            let id = display.id
            var base: NotchGeometry?
            if id != island.displayID, !hidesAtRest, !fullscreenDisplays.contains(id),
               var geometry = environment.baseGeometry(id) {
                geometry.compactSideRoom = sideRoom(on: display, geometry: geometry)
                // A simulated island needs the menus' room at rest, as the island does.
                if geometry.isNotched || geometry.compactSideRoom != nil { base = geometry }
            }
            guard let base else {
                if let copy = copies[id], copy.model.shown {
                    copy.model.shown = false
                    copy.host.hideCopy()
                }
                continue
            }
            let (strip, size) = surface(on: base, island: island)
            let copy = copies[id] ?? makeCopy(geometry: base, size: size)
            copies[id] = copy
            if copy.model.outline != outline || copy.model.timerOutline != (activity == .timer) {
                copy.model.outline = outline
                copy.model.timerOutline = activity == .timer
                copy.host.setOutline(enabled: outline, color: activity == .timer ? .systemOrange : .white)
            }
            let sharing: NSWindow.SharingType = environment.showsInCaptures() ? .readOnly : .none
            if copy.host.panelSharingType != sharing { copy.host.panelSharingType = sharing }
            let revealing = !copy.model.shown
            let previous = copy.model.activity
            guard copy.model.update(geometry: base, strip: strip, size: size, activity: activity) || revealing else { continue }
            copy.model.shown = true
            // Shown at once where the island just left, so the two trade places.
            copy.host.presentCopy(size: size, geometry: base, animated: !revealing,
                                  transitionContent: !revealing && previous != activity ? .replace : .none)
            copy.host.setActivationArea(CGRect(origin: .zero, size: size), title: environment.openTitle(),
                                        willPress: {}, activate: { [weak self] in self?.activate(id) })
            if !copy.host.panelIsVisible { copy.host.orderPanelFront() }
        }
    }

    package func close() {
        guard !copies.isEmpty else { return }
        copies.values.forEach { $0.host.close() }
        copies.removeAll()
    }

    /// Only the copies ask which displays are in full screen, and only when
    /// the island hides there; the island asks for its own display.
    package func updateFullscreenDisplays(showsOnAllDisplays: Bool) {
        guard showsOnAllDisplays, environment.hidesInFullscreen() else { fullscreenDisplays = []; return }
        fullscreenDisplays = environment.fullscreenDisplays(environment.displays().map(\.id))
    }

    /// A copy's closed surface: the strip of what the island shows, drawn
    /// for that display, or the island at rest there.
    private func surface(on base: NotchGeometry, island: Island) -> (strip: NotchGeometry, size: CGSize) {
        guard let activity = island.activity else {
            return (base, base.restingSize(showsContent: !base.floats && island.showsIdleContent))
        }
        if base.floats { return (base, stripSize(activity, island.companion, base)) }
        let strip = compactGeometry(activity, island.companion, base)
        return (strip, strip.compactActivitySize)
    }

    /// Another display's menus are never measured. A copy covers them when
    /// the island may, or where there are none, and otherwise gives way.
    private func sideRoom(on display: Display, geometry: NotchGeometry) -> CGFloat? {
        guard environment.coversMenus() || !display.hasMenuBar else { return nil }
        return NotchMenuBarLayout.sideRoom(screen: geometry.screen, cameraWidth: geometry.cameraWidth,
                                           barHeight: geometry.menuBarHeight, occupied: [])
    }

    private func makeCopy(geometry: NotchGeometry, size: CGSize) -> Copy {
        let model = NotchMirrorModel(geometry: geometry, size: size)
        return Copy(host: makeHost(model, geometry, size), model: model)
    }
}
