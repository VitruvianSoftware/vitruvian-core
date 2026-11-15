// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import VitruvianAtriumCore
import VitruvianAtriumDesign
import VitruvianAtriumServices
import VitruvianAtriumUI

/// The module's own full-screen visibility and volume roller, over a scripted
/// preference, Spaces and island. No desktop Space changes and no event tap is
/// installed.
enum NotchFullscreenTests {
    typealias Topology = SpaceWindowBridge.Topology

    /// The preference and the Spaces.
    final class Desk {
        var hides = false
        var topology: Topology?
        var reads = 0
        /// The displays an app covers with a full screen of its own.
        var appCovered: Set<CGDirectDisplayID> = []
        var appReads = 0

        var environment: NotchFullscreenVisibility.Environment {
            NotchFullscreenVisibility.Environment(
                hidesInFullscreen: { [unowned self] in self.hides },
                showsFullscreenSpace: { [unowned self] id in
                    self.reads += 1
                    return self.topology?.isFullscreen(on: id, separateSpaces: true)
                },
                showsAppFullscreen: { [unowned self] id in
                    self.appReads += 1
                    return self.appCovered.contains(id)
                })
        }
    }

    /// The island's side, recording what it is asked to do.
    final class Island {
        var hidden = false
        /// Running and not suspended.
        var active = true
        var calls: [String] = []
        var routingChanges = 0
        /// What `updateScreen` does on this island, if anything.
        var screenUpdate: (() -> Void)?
        /// What the composition root runs when key routing changes.
        var onRoutingChange: (() -> Void)?
        /// Whether each refresh eased the island, in order, and whether it
        /// brought it back in from the screen edge.
        var refreshAnimations: [Bool] = []
        var refreshReveals: [Bool] = []

        var side: NotchFullscreenVisibility.Island {
            NotchFullscreenVisibility.Island(
                hidden: { [unowned self] in self.hidden },
                setHidden: { [unowned self] in self.hidden = $0 },
                isActive: { [unowned self] in self.active },
                cancelHover: { [unowned self] in self.calls.append("cancelHover") },
                releaseDrag: { [unowned self] in self.calls.append("releaseDrag") },
                cancelCaptureControls: { [unowned self] in self.calls.append("cancelCaptureControls") },
                dismissNotice: { [unowned self] in self.calls.append("dismissNotice") },
                collapse: { [unowned self] in self.calls.append("collapse") },
                feedbackRoutingDidChange: { [unowned self] in
                    self.routingChanges += 1
                    self.onRoutingChange?()
                },
                updateScreen: { [unowned self] in
                    self.calls.append("updateScreen")
                    self.screenUpdate?()
                },
                updateFullscreenDisplays: { [unowned self] in self.calls.append("updateFullscreenDisplays") },
                syncMirrors: { [unowned self] in self.calls.append("syncMirrors") },
                syncVisibleConsumers: { [unowned self] in self.calls.append("syncVisibleConsumers") },
                refreshPresentation: { [unowned self] animated, revealing in
                    self.calls.append("refreshPresentation")
                    self.refreshAnimations.append(animated)
                    self.refreshReveals.append(revealing)
                })
        }
    }

    static func run(_ suite: TestSuite) {
        let topology = Topology(displays: [
            .init(displayID: 1, spaces: [10, 11], fullscreenSpaces: [11], currentSpace: 10),
            .init(displayID: 2, spaces: [20, 21], fullscreenSpaces: [21], currentSpace: 21)
        ])
        suite.expect(!topology.isFullscreen(on: 1, separateSpaces: true)
                     && topology.isFullscreen(on: 2, separateSpaces: true),
                     "fullscreen on another monitor does not hide the island's desktop")
        suite.expect(topology.isFullscreen(on: 1, separateSpaces: false),
                     "a shared fullscreen Space applies to all monitors")
        suite.expect(!topology.isFullscreen(on: 99, separateSpaces: true),
                     "an unknown monitor is not mistaken for another monitor's fullscreen Space")
        let unknown = Topology(displays: [
            .init(displayID: nil, spaces: [10, 11], fullscreenSpaces: [11], currentSpace: 11)
        ])
        suite.expect(unknown.isFullscreen(on: 1, separateSpaces: false)
                     && !unknown.isFullscreen(on: 1, separateSpaces: true),
                     "a shared Space can omit its display UUID")

        let desk = Desk()
        desk.topology = topology
        let island = Island()
        let visibility = NotchFullscreenVisibility(environment: desk.environment, island: island.side)
        visibility.update(displayID: 2)
        suite.expect(!island.hidden && desk.reads == 0 && desk.appReads == 0 && island.routingChanges == 0,
                     "the opt-in preference avoids Space and window queries while disabled")
        desk.hides = true
        visibility.update(displayID: 2)
        suite.expect(island.hidden && island.calls == ["cancelHover", "releaseDrag", "cancelCaptureControls",
                                                       "dismissNotice", "collapse"],
                     "entering fullscreen clears hover emphasis, pending reveals, banners, departing notices, drags and capture controls")
        suite.expect(island.routingChanges == 1,
                     "entering fullscreen hands the brightness keys back to the system")
        island.calls = []
        visibility.update(displayID: 2)
        suite.expect(island.calls.isEmpty && island.routingChanges == 1,
                     "unchanged fullscreen state does not repeat dismissal or key routing")
        visibility.update(displayID: 1)
        suite.expect(!island.hidden && island.calls.isEmpty && island.routingChanges == 2,
                     "returning to a desktop restores eligibility and key routing without stepping aside again")
        visibility.update(displayID: 2)
        desk.hides = false
        visibility.update(displayID: 2)
        suite.expect(!island.hidden, "disabling the option restores eligibility in fullscreen")
        desk.hides = true
        desk.topology = nil
        visibility.update(displayID: 2)
        suite.expect(!island.hidden, "unavailable Space queries leave the island reachable")
        desk.appCovered = [2]
        visibility.update(displayID: 2)
        suite.expect(island.hidden, "an app's own full screen hides the island even with the Spaces unreadable")
        desk.appCovered = []
        visibility.update(displayID: 2)
        desk.topology = topology

        island.calls = []
        visibility.environmentDidChange()
        suite.expect(island.calls == ["updateScreen", "updateFullscreenDisplays", "syncMirrors"],
                     "an unchanged fullscreen state leaves consumers and a transition on screen alone")
        island.calls = []
        island.screenUpdate = { island.hidden = true }
        visibility.environmentDidChange()
        suite.expect(island.calls == ["updateScreen", "updateFullscreenDisplays", "syncMirrors",
                                      "syncVisibleConsumers", "refreshPresentation"],
                     "a fullscreen change reevaluates the display, consumers and presentation together")
        island.screenUpdate = nil
        island.calls = []
        island.active = false
        visibility.environmentDidChange()
        suite.expect(island.calls.isEmpty, "Space changes cannot reveal a locked or sleeping session")
        desk.hides = false
        let idle = Island()
        NotchFullscreenVisibility(environment: desk.environment, island: idle.side).environmentDidChange()
        suite.expect(idle.calls.isEmpty, "with the option off, app and Space changes do no fullscreen work")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchHideInFullscreen] as? Bool == false
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchHideInFullscreen),
                     "fullscreen hiding is opt-in and included in settings backup")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchHoverInFullscreen] as? Bool == false
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchHoverInFullscreen),
                     "fullscreen hover is a separate opt-in included in settings backup")
        fullscreenMotionChecks(suite)
        appFullscreenWindowChecks(suite)
        volumeLifecycleChecks(topology, suite)
    }

    /// An app's own full screen eases the island away and back; a full-screen
    /// Space already slides the screen, so the island follows it at once.
    private static func fullscreenMotionChecks(_ suite: TestSuite) {
        let desk = Desk()
        desk.hides = true
        let island = Island()
        let visibility = NotchFullscreenVisibility(environment: desk.environment, island: island.side)
        // The island reevaluates its own display as the Space or the app changes.
        island.screenUpdate = { visibility.update(displayID: 1) }
        func change(space: Bool = false, app: Bool = false) {
            desk.topology = Topology(displays: [
                .init(displayID: 1, spaces: [10, 11], fullscreenSpaces: [11], currentSpace: space ? 11 : 10)
            ])
            desk.appCovered = app ? [1] : []
            visibility.environmentDidChange()
        }
        change(app: true)
        suite.expect(island.hidden && island.refreshAnimations == [true] && island.refreshReveals == [false],
                     "an app's own full screen hides the island with the usual animation")
        change()
        suite.expect(!island.hidden && island.refreshAnimations == [true, true]
                     && island.refreshReveals == [false, true],
                     "leaving an app's own full screen reveals the island from the screen edge")
        change(space: true)
        suite.expect(island.hidden && island.refreshAnimations.last == false
                     && island.refreshReveals.last == false,
                     "entering a full-screen Space hides the island at once")
        change()
        suite.expect(!island.hidden && island.refreshAnimations.last == false
                     && island.refreshReveals.last == false,
                     "leaving a full-screen Space shows the island at once")
        change(app: true)
        change(space: true, app: true)
        change(app: true)
        change()
        suite.expect(island.refreshAnimations.suffix(2) == [true, true] && island.refreshReveals.last == true,
                     "an app's full screen keeps its animation after a Space came and went over it")
        change(app: true)
        change(space: true, app: true)
        change(space: true)
        change()
        suite.expect(island.refreshAnimations.suffix(1) == [false] && island.refreshReveals.suffix(1) == [false],
                     "full screen last held by a Space ends at once, whatever began it")
        // The island coming back for a reason of its own forgets how it went.
        change(space: true)
        visibility.forgetHidden()
        island.hidden = false
        change(app: true)
        suite.expect(island.hidden && island.refreshAnimations.last == true,
                     "an island that stopped in a full-screen Space eases away at the next app full screen")
    }

    /// Window lists recorded from GLFW full screen (Minecraft) and ordinary
    /// desktop windows on a 14-inch notched display.
    private static func appFullscreenWindowChecks(_ suite: TestSuite) {
        typealias Real = NotchAppFullscreen
        let built = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let external = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let displays: [CGDirectDisplayID: CGRect] = [1: built, 2: external]
        func window(_ bounds: CGRect, pid: pid_t = 42, layer: Int = 25, alpha: Double = 1,
                    number: CGWindowID = 1) -> Real.WindowInfo {
            Real.WindowInfo(number: number, ownerPID: pid, layer: layer, alpha: alpha, bounds: bounds)
        }
        func covered(_ windows: [Real.WindowInfo], front: pid_t? = 42,
                     menuBarHidden: Bool = false) -> Set<CGDirectDisplayID> {
            Real.coveredDisplays(windows: windows, frontmostPID: front, ownPID: 7, displays: displays,
                                 menuBarHidden: menuBarHidden, confirmed: []).displays
        }
        suite.expect(covered([window(built)]) == [1],
                     "a raised borderless window over the whole display is an app's own full screen")
        suite.expect(covered([window(external)]) == [2], "a game on a second display covers only that display")
        suite.expect(covered([window(CGRect(x: 0.5, y: -0.4, width: 1511.2, height: 982.6))]) == [1],
                     "a point of rounding on an edge still covers the display")
        suite.expect(covered([window(built)], front: 99).isEmpty,
                     "a raised window of an app with no level 0 window there does not hide the island")
        suite.expect(covered([window(built, layer: 0), window(built, layer: 0, number: 2)], front: 99) == [],
                     "a level 0 window never confirmed does not hide the island from the background")
        suite.expect(covered([window(built), window(built, layer: 0, number: 2)], front: 99) == [1],
                     "an app in front on a display with a raised window covers it from the background")
        suite.expect(covered([window(built, pid: 99, layer: 0, number: 2), window(built)], front: 99).isEmpty,
                     "a raised window under another app's normal window does not hide the island")
        suite.expect(covered([window(built)], front: nil).isEmpty, "no frontmost app hides nothing")
        suite.expect(covered([window(built, pid: 7)], front: 7).isEmpty, "the island's own windows never count")
        suite.expect(covered([window(built, layer: 0)]).isEmpty,
                     "a normal window filling the display under an auto-hidden menu bar keeps the island")
        suite.expect(covered([window(CGRect(x: 200, y: 100, width: 1000, height: 700), layer: 0),
                              window(built, layer: -1, number: 2)], menuBarHidden: true).isEmpty,
                     "a window below the normal level never counts as an app's full screen")
        // VLC 3 own full screen on a 3440x1440 display: video window at level 0
        // over the whole display, menu bar hidden by the app.
        let ultrawide = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let vlc = [window(ultrawide, layer: 0, number: 10),
                   window(CGRect(x: 1478, y: 1300, width: 483, height: 84), layer: 8, number: 11)]
        suite.expect(Real.coveredDisplays(windows: vlc, frontmostPID: 42, ownPID: 7, displays: [3: ultrawide],
                                          menuBarHidden: true, confirmed: []).displays == [3],
                     "a level 0 window filling the display covers it when the app hides the menu bar")
        suite.expect(Real.coveredDisplays(windows: vlc, frontmostPID: 42, ownPID: 7, displays: [3: ultrawide],
                                          menuBarHidden: false, confirmed: []).displays.isEmpty,
                     "the same window keeps the island when the menu bar stays visible")
        multiDisplayChecks(suite)
        suite.expect(covered([window(CGRect(x: 0, y: 33, width: 1512, height: 949), layer: 0)],
                             menuBarHidden: true).isEmpty,
                     "a level 0 window below the menu bar is not full screen even with the menu bar hidden")
        suite.expect(covered([window(built, layer: 0, alpha: 0)], menuBarHidden: true).isEmpty,
                     "an invisible level 0 window is not full screen with the menu bar hidden")
        suite.expect(covered([window(CGRect(x: 0, y: 33, width: 1512, height: 949), layer: 3)]).isEmpty,
                     "a raised window below the menu bar is not full screen")
        suite.expect(covered([window(built, alpha: 0)]).isEmpty, "an invisible overlay is not full screen")
        suite.expect(!Real.covers(built, .zero), "an empty display frame is never covered")
    }

    /// Measured with VLC in its own full screen on display A and an app
    /// clicked on display B. Lists run front to back, in CG coordinates.
    private static func multiDisplayChecks(_ suite: TestSuite) {
        typealias Real = NotchAppFullscreen
        let a = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let b = CGRect(x: 3440, y: 193, width: 1800, height: 1169)
        let displays: [CGDirectDisplayID: CGRect] = [1: a, 2: b]
        let (vlcPID, otherPID, dockPID, serverPID): (pid_t, pid_t, pid_t, pid_t) = (42, 50, 60, 70)
        func w(_ number: CGWindowID, _ pid: pid_t, _ layer: Int, _ bounds: CGRect,
               alpha: Double = 1) -> Real.WindowInfo {
            Real.WindowInfo(number: number, ownerPID: pid, layer: layer, alpha: alpha, bounds: bounds)
        }
        let controls = w(11, vlcPID, 8, CGRect(x: 1478, y: 1300, width: 483, height: 84), alpha: 0)
        let video = w(10, vlcPID, 0, a)
        let menuBar = w(20, serverPID, 24, CGRect(x: 3440, y: 193, width: 1800, height: 24))
        let dock = w(21, dockPID, 20, a)
        let appOnB = w(30, otherPID, 0, CGRect(x: 3500, y: 250, width: 1200, height: 800))
        func read(_ windows: [Real.WindowInfo], front: pid_t, hidden: Bool, confirmed: Set<CGWindowID>)
            -> (displays: Set<CGDirectDisplayID>, confirmed: Set<CGWindowID>) {
            Real.coveredDisplays(windows: windows, frontmostPID: front, ownPID: 7, displays: displays,
                                 menuBarHidden: hidden, confirmed: confirmed)
        }
        let first = read([controls, video], front: vlcPID, hidden: true, confirmed: [])
        suite.expect(first.displays == [1] && first.confirmed == [10],
                     "VLC frontmost with the menu bar hidden covers its display and is confirmed")
        let maximized = read([controls, video], front: vlcPID, hidden: false, confirmed: first.confirmed)
        suite.expect(maximized.displays.isEmpty && maximized.confirmed.isEmpty,
                     "restoring the menu bar forgets full screen even when a maximized window keeps its number and bounds")
        let focusB = [menuBar, dock, appOnB, video, controls]
        suite.expect(read(focusB, front: otherPID, hidden: false, confirmed: maximized.confirmed).displays.isEmpty,
                     "moving focus away does not revive a maximized window's expired full-screen confirmation")
        let moved = read(focusB, front: otherPID, hidden: false, confirmed: first.confirmed)
        suite.expect(moved.displays == [1] && moved.confirmed == [10],
                     "focus on another display keeps the confirmed full-screen window covered")
        let sameAppOnB = w(31, vlcPID, 0, appOnB.bounds)
        let sameApp = read([sameAppOnB, video], front: vlcPID, hidden: false, confirmed: first.confirmed)
        suite.expect(sameApp.displays == [1] && sameApp.confirmed == [10],
                     "another normal window of the same app taking focus on a second display keeps the video confirmed")
        suite.expect(read(focusB, front: otherPID, hidden: false, confirmed: []).displays.isEmpty,
                     "a level 0 window never confirmed keeps the island once focus moves")
        let clicked = read([w(40, otherPID, 0, CGRect(x: 200, y: 100, width: 1000, height: 700)), dock, video],
                           front: otherPID, hidden: false, confirmed: moved.confirmed)
        suite.expect(clicked.displays.isEmpty && clicked.confirmed == [10],
                     "a normal window above the video shows the island without forgetting the video's full screen")
        let uncovered = read(focusB, front: otherPID, hidden: false, confirmed: clicked.confirmed)
        suite.expect(uncovered.displays == [1] && uncovered.confirmed == [10],
                     "removing the covering window hides the island over the video without giving VLC focus")
        let left = read([menuBar, appOnB, w(10, vlcPID, 0, CGRect(x: 600, y: 200, width: 1200, height: 700))],
                        front: vlcPID, hidden: false, confirmed: [10])
        suite.expect(left.displays.isEmpty && left.confirmed.isEmpty,
                     "leaving full screen uncovers the display and forgets the window")
        let resizedBehind = read([appOnB, w(10, vlcPID, 0, CGRect(x: 600, y: 200, width: 1200, height: 700))],
                                 front: otherPID, hidden: false, confirmed: clicked.confirmed)
        suite.expect(resizedBehind.displays.isEmpty && resizedBehind.confirmed.isEmpty,
                     "a background window that stops filling the display loses its full-screen confirmation")
        let closed = read([appOnB], front: otherPID, hidden: false, confirmed: first.confirmed)
        let invisible = read([appOnB, w(10, vlcPID, 0, a, alpha: 0)],
                             front: otherPID, hidden: false, confirmed: first.confirmed)
        suite.expect(closed.confirmed.isEmpty && invisible.confirmed.isEmpty,
                     "closed and invisible windows lose their full-screen confirmation")
        suite.expect(read([dock, appOnB], front: otherPID, hidden: false, confirmed: []).displays.isEmpty
                     && read([menuBar, dock, appOnB], front: otherPID, hidden: false, confirmed: []).displays.isEmpty,
                     "the Dock's full-display level 20 window alone never covers")
        suite.expect(read([video], front: 7, hidden: false, confirmed: [10]).displays == [1],
                     "the island's own focus does not uncover a confirmed full-screen window")
    }

    /// The precise volume roller wants its tap while its own option is on, or
    /// while the island takes the volume keys, which it gives up in a
    /// full-screen Space. Wired the way `main.swift` wires them, through key
    /// routing. The stand-in tap is always refused, so a roller that wants its
    /// tap reports it failed, and one that stops clears that.
    private static func volumeLifecycleChecks(_ topology: Topology, _ suite: TestSuite) {
        for preciseVolume in [false, true] {
            let suiteName = "vitru.tests.notch-fullscreen-\(UUID().uuidString)"
            let defaults = ScratchDefaults.suite(named: suiteName)!
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(preciseVolume, forKey: DefaultsKey.preciseVolumeRollerEnabled)
            let desk = Desk()
            desk.hides = true
            desk.topology = topology
            let island = Island()
            let visibility = NotchFullscreenVisibility(environment: desk.environment, island: island.side)
            var taps = 0
            let volume = PreciseVolumeRollerService(environment: .init(
                defaults: defaults,
                mixerAvailable: { true },
                islandTakesVolume: { !island.hidden },
                accessibilityGranted: { true },
                sessionIsActive: { true },
                createTap: { _, _ in
                    taps += 1
                    return nil
                }))
            island.onRoutingChange = { volume.syncWithPreferences() }
            var displayID: CGDirectDisplayID = 2
            island.screenUpdate = { visibility.update(displayID: displayID) }

            visibility.update(displayID: displayID)
            volume.syncWithPreferences()
            suite.expect(island.hidden && volume.tapFailed == preciseVolume && (taps > 0) == preciseVolume,
                         "fullscreen startup keeps the tap only when the precise volume roller needs it")
            displayID = 1
            visibility.environmentDidChange()
            suite.expect(!island.hidden && volume.tapFailed,
                         "returning to the desktop restores the volume tap without a preference change")
            displayID = 2
            visibility.environmentDidChange()
            suite.expect(island.hidden && volume.tapFailed == preciseVolume,
                         "entering fullscreen releases the notch tap but preserves the precise volume roller")
        }
    }
}
