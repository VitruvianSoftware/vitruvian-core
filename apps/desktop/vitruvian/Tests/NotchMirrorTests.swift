// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// With the island on every display, each other display shows a copy of
/// what it shows closed. The copies run the module's own `NotchMirrors`;
/// displays, windows, Spaces and preferences are controlled boundaries.
enum NotchMirrorContract {
    /// A copy's window, recording what it was asked to do.
    final class Host: NotchMirrorHost {
        var panelSharingType = NSWindow.SharingType.readOnly
        var panelIsVisible = false
        var visibleWindowID: CGWindowID? { nil }
        var orders = 0
        var presented: [(size: CGSize, geometry: NotchGeometry, animated: Bool, transition: NotchContentTransition)] = []
        var hides = 0, closes = 0
        var outline: (enabled: Bool, color: NSColor)?
        var activationRect = CGRect.zero
        var activate: (() -> Void)?
        func orderPanelFront() { panelIsVisible = true; orders += 1 }
        func presentCopy(size: CGSize, geometry: NotchGeometry, animated: Bool, transitionContent: NotchContentTransition) {
            presented.append((size, geometry, animated, transitionContent))
        }
        func hideCopy() { hides += 1; panelIsVisible = false }
        func close() { closes += 1; panelIsVisible = false }
        func setOutline(enabled: Bool, color: NSColor) { outline = (enabled, color) }
        func setActivationArea(_ rect: CGRect, title: String, willPress: @escaping () -> Void, activate: @escaping () -> Void) {
            activationRect = rect
            self.activate = activate
        }
    }

    struct Screen {
        let id: CGDirectDisplayID
        let frame: CGRect
        let notched: Bool
        init(_ id: CGDirectDisplayID, _ frame: CGRect, notched: Bool = false) {
            self.id = id
            self.frame = frame
            self.notched = notched
        }
    }

    /// The displays, Spaces, preferences and island the copies read.
    final class World {
        var screens: [Screen] = []
        var separateSpaces = false
        var fullscreen: Set<CGDirectDisplayID> = []
        var hidesUntilHover = false, coversMenus = true, showsInCaptures = true
        var outlineEnabled = false, hidesInFullscreen = false
        var showsOnAllDisplays = true, running = true, suspended = false, hasWindow = true
        var displayID: CGDirectDisplayID? = 1
        var activity: NotchCompactActivity?
        var idleContent = NotchIdleContent.none
        var made: [Host] = []
        var activated: [CGDirectDisplayID] = []
        /// The companion rests or visits in the closed island.
        var mascotVisible = false

        /// A built-in display with a camera housing, or an external one with a capsule.
        func baseGeometry(for screen: Screen) -> NotchGeometry {
            NotchGeometry(screen: screen.frame, safeAreaTop: screen.notched ? 32 : 0,
                          cameraWidth: screen.notched ? 185 : 0, menuBarHeight: screen.notched ? 32 : 24,
                          silhouette: .capsule)
        }
        /// Each activity's capsule a fixed width wider than the bare one, so sizes are traceable.
        func capsuleStripSize(for activity: NotchCompactActivity, companion: NotchCompactActivity?,
                              geometry: NotchGeometry) -> CGSize {
            CGSize(width: geometry.restingSize(showsContent: false).width + 40, height: geometry.stripHeight)
        }
        func compactGeometry(for activity: NotchCompactActivity, companion: NotchCompactActivity?,
                             base: NotchGeometry) -> NotchGeometry {
            base.compactTimerGeometry(showsDownloads: false, wing: 60)
        }

        func makeMirrors() -> NotchMirrors<Host> {
            NotchMirrors(
                environment: NotchMirrors.Environment(
                    displays: { [unowned self] in
                        self.screens.map { screen in
                            NotchMirrors.Display(id: screen.id,
                                                 hasMenuBar: self.separateSpaces || self.screens.first?.id == screen.id)
                        }
                    },
                    baseGeometry: { [unowned self] id in
                        self.screens.first(where: { $0.id == id }).map(self.baseGeometry(for:))
                    },
                    fullscreenDisplays: { [unowned self] ids in Set(ids.filter(self.fullscreen.contains)) },
                    hidesUntilHover: { [unowned self] in self.hidesUntilHover },
                    coversMenus: { [unowned self] in self.coversMenus },
                    showsInCaptures: { [unowned self] in self.showsInCaptures },
                    outlineEnabled: { [unowned self] in self.outlineEnabled },
                    hidesInFullscreen: { [unowned self] in self.hidesInFullscreen },
                    openTitle: { "Open" }),
                island: { [unowned self] in
                    guard self.showsOnAllDisplays, self.running, !self.suspended, self.hasWindow else { return nil }
                    return NotchMirrors.Island(displayID: self.displayID, activity: self.activity,
                                               companion: nil, showsIdleContent: self.idleContent != .none,
                                               showsMascot: { [unowned self] in
                                                   self.mascotVisible && ($0.floats || $0.restingWingWidth > 0)
                                               })
                },
                stripSize: { [unowned self] in self.capsuleStripSize(for: $0, companion: $1, geometry: $2) },
                compactGeometry: { [unowned self] in self.compactGeometry(for: $0, companion: $1, base: $2) },
                makeHost: { [unowned self] _, _, _ in
                    let host = Host()
                    self.made.append(host)
                    return host
                },
                activate: { [unowned self] in self.activated.append($0) })
        }
    }

    /// The island a click on a copy summons, recording what it was asked.
    final class Island {
        var showsOnAllDisplays = true, running = true, suspended = false
        var settling = false
        var settled: [() -> Void] = []
        var displayID: CGDirectDisplayID? = 1
        var displays: Set<CGDirectDisplayID> = [1, 2]
        var expanded = false, peeking = false, canFollowPointer = true
        var opened = 0, collapses = 0
        var moves: [CGDirectDisplayID] = []
        /// Wired the way `NotchService` wires it.
        lazy var summons = NotchIslandSummons(island: .init(
            showsCopies: { [unowned self] in self.running && !self.suspended && self.showsOnAllDisplays },
            displayID: { [unowned self] in self.displayID },
            isOpen: { [unowned self] in self.expanded || self.peeking },
            collapse: { [unowned self] in self.collapses += 1; self.expanded = false; self.peeking = false },
            whenSettled: { [unowned self] action in
                if self.settling { self.settled.append(action) } else { action() }
            },
            canMove: { [unowned self] in self.running && !self.suspended && self.canFollowPointer },
            move: { [unowned self] id in
                guard self.displays.contains(id) else { return false }
                self.displayID = id
                self.moves.append(id)
                return true
            },
            open: { [unowned self] in self.opened += 1; self.expanded = true }))
    }

    static func run(_ suite: TestSuite) {
        let builtIn = Screen(1, CGRect(x: 0, y: 0, width: 1470, height: 956), notched: true)
        let external = Screen(2, CGRect(x: 1470, y: -86, width: 1920, height: 1080))
        let world = World()
        world.screens = [builtIn, external]
        let mirrors = world.makeMirrors()

        mirrors.sync()
        let capsule = mirrors.copies[2]
        suite.expect(mirrors.copies.count == 1 && mirrors.copies[1] == nil && capsule?.model.shown == true
                     && capsule?.host.presented.count == 1 && capsule?.host.presented.first?.animated == false
                     && capsule?.host.panelIsVisible == true && capsule?.model.activity == nil
                     && mirrors.showsAny,
                     "every display but the island's own shows a copy, at once")
        let external2 = world.baseGeometry(for: external)
        suite.expect(capsule?.model.geometry.floats == true && capsule?.model.geometry.screen == external.frame
                     && capsule?.model.size == external2.restingSize(showsContent: false)
                     && capsule?.host.activationRect == CGRect(origin: .zero, size: capsule?.model.size ?? .zero)
                     && mirrors.hasCapsule,
                     "a copy draws its own display's island, a capsule at rest there, and all of it takes a click")
        mirrors.sync()
        suite.expect(capsule?.host.presented.count == 1 && world.made.count == 1,
                     "an island that changes nothing a copy shows leaves the copy as it is")

        world.outlineEnabled = true
        world.activity = .timer
        mirrors.sync()
        suite.expect(capsule?.host.presented.count == 2 && capsule?.host.presented.last?.transition == .replace
                     && capsule?.host.presented.last?.animated == true
                     && capsule?.model.size.width == external2.restingSize(showsContent: false).width + 40
                     && capsule?.host.outline?.enabled == true && capsule?.host.outline?.color == .systemOrange,
                     "a timer starting reshapes each copy as the island does, in the timer's outline")

        // The island follows the pointer to the external display.
        world.displayID = 2
        mirrors.sync()
        let notch = mirrors.copies[1]
        var builtInBase = world.baseGeometry(for: builtIn)
        builtInBase.compactSideRoom = NotchMenuBarLayout.sideRoom(screen: builtInBase.screen, cameraWidth: builtInBase.cameraWidth,
                                                                  barHeight: builtInBase.menuBarHeight, occupied: [])
        let strip = world.compactGeometry(for: .timer, companion: nil, base: builtInBase)
        suite.expect(capsule?.model.shown == false && capsule?.host.hides == 1 && capsule?.host.panelIsVisible == false
                     && notch?.model.shown == true && notch?.model.geometry.isNotched == true
                     && notch?.model.strip == strip && notch?.model.size == strip.compactActivitySize
                     && notch?.host.presented.last?.animated == false,
                     "the copy steps aside where the island arrives and one appears where it left, drawn for the camera")
        suite.expect(notch?.model.geometry.compactSideRoom == builtInBase.compactSideRoom,
                     "an island that may cover menus gives its copy the room of an empty bar")

        world.hidesUntilHover = true
        mirrors.sync()
        suite.expect(notch?.model.shown == false && notch?.host.hides == 1 && !mirrors.showsAny,
                     "an island hidden until the pointer reaches it hides its copies too")
        world.hidesUntilHover = false
        mirrors.sync()
        suite.expect(notch?.model.shown == true, "a copy returns with the island at rest")

        world.hidesInFullscreen = true
        world.fullscreen = [1]
        mirrors.updateFullscreenDisplays(showsOnAllDisplays: world.showsOnAllDisplays)
        mirrors.sync()
        suite.expect(mirrors.fullscreenDisplays == [1] && notch?.model.shown == false && notch?.host.hides == 2,
                     "a copy leaves a display in full screen when the island hides there")
        mirrors.updateFullscreenDisplays(showsOnAllDisplays: false)
        suite.expect(mirrors.fullscreenDisplays.isEmpty, "with the island on one display no copy reads Spaces")
        world.hidesInFullscreen = false
        mirrors.updateFullscreenDisplays(showsOnAllDisplays: world.showsOnAllDisplays)
        suite.expect(mirrors.fullscreenDisplays.isEmpty, "only the choice to hide in full screen reads Spaces")
        world.fullscreen = []
        mirrors.sync()
        suite.expect(notch?.model.shown == true && notch?.host.presented.last?.animated == false,
                     "leaving full screen shows the copy again at once")

        // Displays with their own menu bars and menus the island must not cover.
        world.separateSpaces = true
        world.coversMenus = false
        world.displayID = 1
        mirrors.sync()
        suite.expect(mirrors.copies[2]?.model.shown == false,
                     "a capsule never covers menus it cannot measure on another display")
        world.displayID = 2
        mirrors.sync()
        suite.expect(mirrors.copies[1]?.model.shown == true && mirrors.copies[1]?.model.geometry.compactSideRoom == nil,
                     "a copy on a camera keeps the camera covered without wings")
        world.coversMenus = true
        world.separateSpaces = false

        // The companion rests in each copy too, beside that display's camera.
        world.displayID = 2
        world.activity = nil
        world.mascotVisible = true
        mirrors.sync()
        suite.expect(mirrors.copies[1]?.model.size == mirrors.copies[1]?.model.geometry.collapsed
                     && (mirrors.copies[1]?.model.size.width ?? 0) > builtInBase.cameraWidth,
                     "a copy beside a camera opens its wings for the resting companion")
        world.mascotVisible = false
        mirrors.sync()

        // A click on a copy asks for the island on that display.
        mirrors.copies[1]?.host.activate?()
        suite.expect(world.activated == [1], "clicking a copy asks for the island on its display")

        // Unplugging a display closes its copy; leaving the choice closes them all.
        world.displayID = 1
        mirrors.sync()
        let unplugged = mirrors.copies[2]?.host
        world.screens = [builtIn]
        mirrors.sync()
        suite.expect(mirrors.copies[2] == nil && unplugged?.closes == 1, "a display that goes away takes its copy along")
        world.screens = [builtIn, external]
        mirrors.sync()
        let hosts = mirrors.copies.values.map(\.host)
        world.showsOnAllDisplays = false
        mirrors.sync()
        suite.expect(mirrors.copies.isEmpty && !hosts.isEmpty && hosts.allSatisfy { $0.closes == 1 },
                     "choosing one display closes every copy")
        world.showsOnAllDisplays = true
        world.showsInCaptures = false
        mirrors.sync()
        suite.expect(!mirrors.copies.isEmpty && mirrors.copies.values.allSatisfy { $0.host.panelSharingType == .none },
                     "copies stay out of screenshots with the island")
        world.running = false
        mirrors.sync()
        suite.expect(mirrors.copies.isEmpty, "a stopped island leaves no copies")
        world.running = true
        mirrors.sync()
        let lastHosts = mirrors.copies.values.map(\.host)
        mirrors.close()
        suite.expect(mirrors.copies.isEmpty && !lastHosts.isEmpty && lastHosts.allSatisfy { $0.closes == 1 },
                     "closing the copies closes each window once")

        let model = NotchMirrorModel(geometry: external2, size: CGSize(width: 100, height: 24))
        suite.expect(!model.update(geometry: external2, strip: external2, size: CGSize(width: 100, height: 24), activity: nil)
                     && model.update(geometry: external2, strip: external2, size: CGSize(width: 120, height: 24), activity: nil)
                     && model.update(geometry: external2, strip: external2, size: CGSize(width: 120, height: 24), activity: .music)
                     && model.activity == .music,
                     "a copy is only redrawn when what it shows changes")

        runActivation(suite)
    }

    /// A click on a copy brings the island to its display, open, closing it
    /// on the display it was open on.
    private static func runActivation(_ suite: TestSuite) {
        let island = Island()
        island.displayID = 2
        island.expanded = true
        island.summons.bring(to: 1)
        suite.expect(island.collapses == 1 && island.moves == [1] && island.displayID == 1 && island.opened == 1,
                     "clicking a copy closes the island, moves it to that display and opens it there")
        let opened = island.opened
        island.canFollowPointer = false
        island.summons.bring(to: 2)
        island.canFollowPointer = true
        suite.expect(island.opened == opened, "a notice or a drag keeps the island where it is")
        island.summons.bring(to: 1)
        suite.expect(island.opened == opened && island.moves == [1], "a click on the island's own display does nothing")

        let settling = Island()
        settling.expanded = true
        settling.settling = true
        settling.summons.bring(to: 2)
        suite.expect(settling.collapses == 1 && settling.moves.isEmpty && settling.opened == 0,
                     "the island closes at once and waits for its window to settle before moving")
        settling.settled.forEach { $0() }
        suite.expect(settling.moves == [2] && settling.opened == 1, "once settled, it moves there and opens")

        let unplugged = Island()
        unplugged.displays = [1]
        unplugged.summons.bring(to: 2)
        suite.expect(unplugged.moves.isEmpty && unplugged.opened == 0 && unplugged.collapses == 0,
                     "a closed island is not collapsed again, and a display unplugged before it settles is not opened on")
        let single = Island()
        single.showsOnAllDisplays = false
        single.expanded = true
        single.summons.bring(to: 2)
        suite.expect(single.collapses == 0 && single.moves.isEmpty,
                     "with the island on one display, a stray copy click changes nothing")
        let stopping = Island()
        stopping.settling = true
        stopping.summons.bring(to: 2)
        stopping.suspended = true
        stopping.settled.forEach { $0() }
        suite.expect(stopping.moves.isEmpty && stopping.opened == 0,
                     "an island suspended while it settles stays where it is")
    }
}
