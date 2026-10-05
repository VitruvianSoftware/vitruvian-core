// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

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

        var environment: NotchFullscreenVisibility.Environment {
            NotchFullscreenVisibility.Environment(
                hidesInFullscreen: { [unowned self] in self.hides },
                showsFullscreen: { [unowned self] id in
                    self.reads += 1
                    return self.topology?.isFullscreen(on: id, separateSpaces: true)
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
                refreshPresentation: { [unowned self] in self.calls.append("refreshPresentation") })
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
        suite.expect(!island.hidden && desk.reads == 0 && island.routingChanges == 0,
                     "the opt-in preference avoids Space queries while disabled")
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
        volumeLifecycleChecks(topology, suite)
    }

    /// The precise volume roller wants its tap while its own option is on, or
    /// while the island takes the volume keys, which it gives up in a
    /// full-screen Space. Wired the way `main.swift` wires them, through key
    /// routing. The stand-in tap is always refused, so a roller that wants its
    /// tap reports it failed, and one that stops clears that.
    private static func volumeLifecycleChecks(_ topology: Topology, _ suite: TestSuite) {
        for preciseVolume in [false, true] {
            let suiteName = "vitru.tests.notch-fullscreen-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
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
