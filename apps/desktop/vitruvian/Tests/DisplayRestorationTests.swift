// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Switching displays off and back on, on a started production service over
/// a scripted desk: the built-in panel (1) and two external screens (2, 3).
/// Every scenario goes through what the app itself calls: a tap on a row,
/// the start-up and termination restores, the lid and a cable coming out.
/// The reconfiguration call and the lid are the rig's; no display changes.
enum DisplayRestorationTests {
    private typealias Rig = BrightnessRig

    private static func desk() -> (Rig.Desk, BrightnessService) {
        let desk = Rig.Desk()
        let panel = Rig.Display(id: 1, systemLevel: 0.5)
        panel.builtIn = true
        desk.displays = [panel, Rig.Display(id: 2), Rig.Display(id: 3)]
        let service = BrightnessService(environment: desk.environment)
        service.start()
        desk.drain()
        return (desk, service)
    }

    private static func tap(_ desk: Rig.Desk, _ service: BrightnessService, _ id: CGDirectDisplayID) {
        guard let row = service.displays.first(where: { $0.id == id }) else { return }
        service.toggleDisplay(row)
        desk.drain()
    }

    /// A cable comes out or goes back in, and the debounce settles.
    private static func plug(_ desk: Rig.Desk, _ id: CGDirectDisplayID, in plugged: Bool) {
        desk.display(id).online = plugged
        desk.display(id).active = plugged
        desk.screens.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        desk.runDelayed()
    }

    private static func switchedOff(_ desk: Rig.Desk) -> [Int] {
        desk.defaults.array(forKey: DefaultsKey.displaysSwitchedOff) as? [Int] ?? []
    }

    static func run(_ suite: TestSuite) {
        startup(suite)
        termination(suite)
        taps(suite)
        headless(suite)
        lidReads(suite)
        identities(suite)
        relaunch(suite)
    }

    private static func savedIdentities(_ desk: Rig.Desk) -> [String: String] {
        desk.defaults.dictionary(forKey: DefaultsKey.displaysSwitchedOffFingerprints) as? [String: String] ?? [:]
    }

    /// Before a display is switched off, the monitor behind its number is
    /// written down beside it. A number macOS later hands to another monitor
    /// is never switched on for the one that left (upstream #2677).
    private static func identities(_ suite: TestSuite) {
        var (desk, service) = desk()
        tap(desk, service, 2)
        tap(desk, service, 3)
        suite.expect(switchedOff(desk) == [2, 3]
                     && savedIdentities(desk) == ["2": "monitor-2", "3": "monitor-3"],
                     "switching displays off saves the monitor behind each number")
        tap(desk, service, 2)
        suite.expect(switchedOff(desk) == [3] && savedIdentities(desk) == ["3": "monitor-3"],
                     "switching one back on forgets only its record and identity")
        tap(desk, service, 3)
        suite.expect(switchedOff(desk).isEmpty && savedIdentities(desk).isEmpty,
                     "the last switch-on clears both repair records")
        desk.tearDown()

        // Sleep or an input change can read the switched-off monitor as
        // active for a moment; its row and its recovery stay.
        (desk, service) = Self.desk()
        tap(desk, service, 2)
        plug(desk, 2, in: true)
        plug(desk, 2, in: false)
        desk.configurations = []
        service.restoreDisplaysBeforeTermination()
        desk.drain()
        suite.expect(desk.configurations == ["on:2"] && switchedOff(desk).isEmpty,
                     "a switched-off monitor briefly read as active is still switched back on at the end")
        desk.tearDown()

        // The number comes back behind another monitor.
        (desk, service) = Self.desk()
        tap(desk, service, 2)
        desk.display(2).fingerprint = "monitor-9"
        desk.configurations = []
        service.restoreDisplaysBeforeTermination()
        desk.drain()
        suite.expect(desk.configurations.isEmpty && switchedOff(desk).isEmpty && savedIdentities(desk).isEmpty
                     && !service.displays.contains { $0.id == 2 },
                     "a monitor that inherits a switched-off display's number is never switched on for it")
        desk.tearDown()

        (desk, service) = Self.desk()
        tap(desk, service, 2)
        desk.display(2).fingerprint = "monitor-9"
        plug(desk, 2, in: true)
        suite.expect(switchedOff(desk).isEmpty && savedIdentities(desk).isEmpty,
                     "a rebuild that finds another monitor behind the number retires the switched-off row")
        desk.tearDown()

        (desk, service) = Self.desk()
        tap(desk, service, 2)
        desk.display(2).fingerprint = "monitor-9"
        desk.configurations = []
        tap(desk, service, 2)
        suite.expect(desk.configurations.isEmpty && service.displayControlFailure == .failed
                     && switchedOff(desk).isEmpty,
                     "a tap to switch on a number now behind another monitor switches nothing on")
        desk.tearDown()

        // CoreGraphics answers zeroes for a connection with nothing on it,
        // all ones for a number no display uses, and the unknown vendor for
        // a monitor IOKit cannot identify. None names another monitor.
        for unknown in ["0:0:0", "4294967295:4294967295:4294967295", "1970170734:0:0"] {
            (desk, service) = Self.desk()
            tap(desk, service, 2)
            desk.display(2).fingerprint = unknown
            desk.configureSucceeds = false
            service.restoreDisplaysBeforeTermination()
            desk.drain()
            suite.expect(desk.configurations.last == "on:2" && switchedOff(desk) == [2]
                         && savedIdentities(desk) == ["2": "monitor-2"],
                         "a number that reads \(unknown) is still switched on, and keeps its row when that fails")
            desk.tearDown()
        }

        // The built-in's number never passes to another monitor.
        (desk, service) = Self.desk()
        tap(desk, service, 1)
        suite.expect(switchedOff(desk) == [1] && savedIdentities(desk).isEmpty,
                     "the built-in panel saves no identity")
        desk.display(1).fingerprint = "monitor-9"
        service.restoreDisplaysBeforeTermination()
        desk.drain()
        suite.expect(desk.configurations == ["off:1", "on:1"] && switchedOff(desk).isEmpty,
                     "the built-in panel comes back even when it reads as another monitor while off")
        desk.tearDown()
    }

    /// A relaunch that finds a display a previous run left off, with display
    /// control itself off: the service was never started.
    private static func relaunch(_ suite: TestSuite) {
        func idle(saved identity: String?) -> (Rig.Desk, BrightnessService) {
            let desk = Rig.Desk()
            let panel = Rig.Display(id: 1, systemLevel: 0.5)
            panel.builtIn = true
            let external = Rig.Display(id: 2)
            external.online = false
            external.active = false
            desk.displays = [panel, external]
            desk.defaults.set([2], forKey: DefaultsKey.displaysSwitchedOff)
            if let identity {
                desk.defaults.set(["2": identity], forKey: DefaultsKey.displaysSwitchedOffFingerprints)
            }
            desk.configureSucceeds = false
            let service = BrightnessService(environment: desk.environment)
            service.restoreDisplaysLeftOff()
            desk.drain()
            return (desk, service)
        }
        func wake(_ desk: Rig.Desk) {
            desk.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
            desk.workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            desk.drain()
        }

        var (desk, service) = idle(saved: "monitor-2")
        let attempts = desk.configurations.count
        suite.expect(attempts > 0 && switchedOff(desk) == [2] && savedIdentities(desk) == ["2": "monitor-2"],
                     "a startup restore that fails keeps the record and the monitor's identity")
        wake(desk)
        suite.expect(desk.configurations.count == attempts, "waking waits for the connections to settle")
        desk.runDelayed()
        suite.expect(desk.configurations.count == attempts + 1 && switchedOff(desk) == [2],
                     "the two wake notifications make one retry, and a failed one keeps the recovery")
        desk.configureSucceeds = true
        wake(desk)
        desk.runDelayed()
        suite.expect(desk.configurations.last == "on:2" && switchedOff(desk).isEmpty && savedIdentities(desk).isEmpty,
                     "a later wake brings the monitor back while display control stays off")
        wake(desk)
        suite.expect(desk.delayed.isEmpty, "with nothing left to restore, a wake schedules nothing")
        withExtendedLifetime(service) {}
        desk.tearDown()

        (desk, service) = idle(saved: "monitor-2")
        let before = desk.configurations.count
        desk.display(2).fingerprint = "monitor-9"
        desk.configureSucceeds = true
        wake(desk)
        desk.runDelayed()
        suite.expect(desk.configurations.count == before && switchedOff(desk).isEmpty && savedIdentities(desk).isEmpty,
                     "a number that wakes behind another monitor is retired, not switched on")
        withExtendedLifetime(service) {}
        desk.tearDown()

        // A record from before identities were saved is switched on by number.
        (desk, service) = idle(saved: nil)
        suite.expect(desk.configurations.first == "on:2" && switchedOff(desk) == [2],
                     "a record without an identity is still switched on by number, and kept when that fails")
        withExtendedLifetime(service) {}
        desk.tearDown()
    }

    private static func startup(_ suite: TestSuite) {
        var (desk, service) = desk()
        desk.display(1).online = false
        desk.defaults.set([1], forKey: DefaultsKey.displaysSwitchedOff)
        desk.lidClosed = true
        service.restoreDisplaysLeftOff()
        service.restoreDisplaysLeftOff()
        desk.drain()
        suite.expect(desk.configurations.isEmpty && desk.lidSubscriptions == 1 && switchedOff(desk) == [1],
                     "closed startup retains its record and owns only one observer")
        desk.lidMoved(closed: false)
        desk.drain()
        suite.expect(desk.configurations == ["on:1"] && switchedOff(desk).isEmpty && desk.lidStops == 1,
                     "lid-open notification alone restores startup intent and releases observation")
        desk.tearDown()

        (desk, service) = Self.desk()
        desk.display(1).online = false
        desk.defaults.set([1], forKey: DefaultsKey.displaysSwitchedOff)
        desk.lidClosed = true
        desk.onLidSubscribe = { desk.lidClosed = false }
        service.restoreDisplaysLeftOff()
        desk.drain()
        suite.expect(desk.configurations == ["on:1"] && switchedOff(desk).isEmpty,
                     "subscribe-then-recheck catches an opening during observer registration")
        desk.tearDown()

        // A new explicit switch-off lands before the recheck an older
        // deferred restoration queued, and cancels it.
        (desk, service) = Self.desk()
        service.toggleDisplay(service.displays.first { $0.id == 1 }!)
        desk.work.drain()
        desk.defaults.set([1], forKey: DefaultsKey.displaysSwitchedOff)
        desk.lidClosed = true
        service.restoreDisplaysLeftOff()
        desk.lidClosed = false
        desk.drain()
        suite.expect(desk.configurations == ["off:1"] && desk.lidStops == 1 && switchedOff(desk) == [1],
                     "new explicit disable cancels older deferred recovery before queued recheck")
        desk.tearDown()
    }

    private static func termination(_ suite: TestSuite) {
        let (desk, service) = desk()
        defer { desk.tearDown() }
        tap(desk, service, 1)
        suite.expect(desk.configurations == ["off:1"] && switchedOff(desk) == [1]
                     && service.displays.first { $0.id == 1 }?.isActive == false,
                     "switching a display off keeps its row and writes the intention down")
        suite.expect(!desk.isWatchingLid, "an intentionally disabled display is not watched for the lid")
        desk.lidClosed = true
        service.restoreDisplaysBeforeTermination()
        desk.lidClosed = false
        desk.configureSucceeds = false
        desk.drain()
        suite.expect(desk.configurations == ["off:1", "on:1"] && switchedOff(desk) == [1]
                     && desk.lidStops == 0 && desk.isWatchingLid,
                     "feature-stop recovery retains failed intent without looping on transaction notifications")
        desk.lidMoved(closed: true)
        desk.drain()
        desk.configureSucceeds = true
        desk.lidMoved(closed: false)
        desk.drain()
        suite.expect(switchedOff(desk).isEmpty && desk.lidStops == 1 && desk.configurations.last == "on:1",
                     "later opening clears persisted recovery after success")
        let made = desk.configurations.count
        service.restoreDisplaysBeforeTermination()
        desk.drain()
        suite.expect(desk.configurations.count == made, "later opening clears the managed snapshot too")

        // Display numbers are reissued after a reconnection, so the gamma
        // restore before a switch-off checks the monitor like the others.
        for sameMonitor in [true, false] {
            let (dimmedDesk, dimmed) = Self.desk()
            defer { dimmedDesk.tearDown() }
            dimmed.setBrightness(0.5, for: 2)
            dimmedDesk.drain()
            if !sameMonitor { dimmedDesk.display(2).fingerprint = "another-monitor" }
            dimmedDesk.events = []
            tap(dimmedDesk, dimmed, 2)
            suite.expect(dimmedDesk.events.prefix(2) == (sameMonitor ? ["picture:1.0", "off:2"] : ["off:2"]),
                         "the pre-switch-off gamma restore checks the display fingerprint, found \(dimmedDesk.events)")
        }
    }

    private static func taps(_ suite: TestSuite) {
        var (desk, service) = desk()
        tap(desk, service, 1)
        desk.lidClosed = true
        tap(desk, service, 1)
        suite.expect(service.displayControlFailure == .closedLid && desk.configurations == ["off:1"]
                     && desk.lidSubscriptions == 1,
                     "a tap denied by the closed lid says so and is remembered for the lid opening")
        desk.lidMoved(closed: false)
        desk.drain()
        suite.expect(desk.configurations == ["off:1", "on:1"] && service.displayControlFailure == nil
                     && desk.lidStops == 1,
                     "opening the lid finishes the remembered tap and clears its message")
        tap(desk, service, 1)
        desk.configureSucceeds = false
        tap(desk, service, 1)
        suite.expect(service.displayControlFailure == .failed && !desk.isWatchingLid,
                     "an open-lid transaction failure remains generic and is not remembered")
        desk.tearDown()

        for initialFailure in [BrightnessService.DisplayControlFailure.failed, .closedLid] {
            (desk, service) = Self.desk()
            tap(desk, service, 1)
            desk.lidClosed = true
            service.restoreDisplaysLeftOff()
            desk.drain()
            desk.lidClosed = initialFailure == .closedLid
            desk.configureSucceeds = false
            tap(desk, service, 1)
            suite.expect(service.displayControlFailure == initialFailure,
                         "production manual completion publishes the actual failure")
            desk.lidMoved(closed: true)
            desk.drain()
            desk.lidMoved(closed: false)
            desk.drain()
            suite.expect(service.displayControlFailure == initialFailure && switchedOff(desk) == [1],
                         "failed deferred restoration preserves the existing error and recovery intent")
            desk.lidMoved(closed: true)
            desk.drain()
            desk.configureSucceeds = true
            desk.lidMoved(closed: false)
            desk.drain()
            suite.expect(service.displayControlFailure == nil && switchedOff(desk).isEmpty,
                         "successful deferred restoration clears generic and closed-lid errors")
            desk.tearDown()
        }

        for startup in [true, false] {
            (desk, service) = Self.desk()
            tap(desk, service, 1)
            desk.lidClosed = true
            tap(desk, service, 1)
            desk.lidClosed = false
            if startup { service.restoreDisplaysLeftOff() } else { service.restoreDisplaysBeforeTermination() }
            desk.drain()
            suite.expect(service.displayControlFailure == nil && switchedOff(desk).isEmpty,
                         "startup and feature-stop success share restoration error cleanup")
            desk.tearDown()
        }
    }

    /// The last screen comes unplugged while this app has others switched
    /// off: one comes back, the built-in panel first.
    private static func headless(_ suite: TestSuite) {
        var (desk, service) = desk()
        tap(desk, service, 1)
        tap(desk, service, 2)
        plug(desk, 3, in: false)
        suite.expect(desk.configurations == ["off:1", "off:2", "on:1"] && switchedOff(desk) == [2],
                     "losing the last display brings back one switched-off display, the panel first")
        desk.tearDown()

        (desk, service) = Self.desk()
        tap(desk, service, 1)
        desk.lidClosed = true
        tap(desk, service, 1)
        tap(desk, service, 2)
        plug(desk, 3, in: false)
        suite.expect(desk.configurations.last == "on:2" && desk.isWatchingLid && switchedOff(desk) == [1],
                     "a remembered tap outlives a headless recovery that brought another display back")
        desk.lidMoved(closed: false)
        desk.drain()
        suite.expect(desk.configurations.last == "on:1" && !desk.isWatchingLid,
                     "opening the lid then finishes the tap as well")
        desk.tearDown()

        (desk, service) = Self.desk()
        tap(desk, service, 1)
        plug(desk, 3, in: false)
        desk.lidClosed = true
        plug(desk, 2, in: false)
        suite.expect(service.displayControlFailure == .closedLid,
                     "headless restoration preserves the closed-lid denial reason")
        desk.lidMoved(closed: false)
        desk.drain()
        suite.expect(service.displayControlFailure == nil && desk.configurations.last == "on:1",
                     "successful headless deferred recovery removes its panel error")
        desk.tearDown()

        (desk, service) = Self.desk()
        tap(desk, service, 1)
        tap(desk, service, 2)
        desk.lidClosed = true
        plug(desk, 3, in: false)
        suite.expect(!desk.isWatchingLid && desk.configurations.last == "on:2" && switchedOff(desk) == [1],
                     "headless success cancels only the newly queued closed-lid candidate")
        let made = desk.configurations.count
        desk.lidMoved(closed: false)
        desk.drain()
        suite.expect(desk.configurations.count == made,
                     "superseded headless intent does not restore another display after lid opening")
        desk.tearDown()

        (desk, service) = Self.desk()
        tap(desk, service, 1)
        tap(desk, service, 2)
        // Only the panel is owed from an earlier run.
        desk.defaults.set([1], forKey: DefaultsKey.displaysSwitchedOff)
        desk.lidClosed = true
        service.restoreDisplaysLeftOff()
        desk.drain()
        plug(desk, 3, in: false)
        suite.expect(desk.isWatchingLid && desk.configurations.last == "on:2",
                     "headless success preserves an independently owed restoration")
        desk.lidMoved(closed: false)
        desk.drain()
        suite.expect(desk.configurations.last == "on:1" && !desk.isWatchingLid,
                     "independent deferred restoration still completes after headless success")
        desk.tearDown()

        (desk, service) = Self.desk()
        tap(desk, service, 1)
        tap(desk, service, 2)
        desk.lidClosed = true
        desk.configureSucceeds = false
        plug(desk, 3, in: false)
        suite.expect(desk.isWatchingLid && service.displayControlFailure == .failed,
                     "a failed headless round keeps the closed panel's request and reports the real failure")
        desk.configureSucceeds = true
        plug(desk, 3, in: true)
        plug(desk, 3, in: false)
        suite.expect(!desk.isWatchingLid && desk.configurations.last == "on:2",
                     "repeated headless attempts retain ownership until a later external success")
        desk.tearDown()

        (desk, service) = Self.desk()
        tap(desk, service, 1)
        tap(desk, service, 2)
        desk.lidClosed = true
        desk.configureSucceeds = false
        plug(desk, 3, in: false)
        desk.lidClosed = false
        service.restoreDisplaysBeforeTermination()
        desk.drain()
        desk.lidClosed = true
        desk.configureSucceeds = true
        plug(desk, 3, in: true)
        plug(desk, 3, in: false)
        suite.expect(desk.isWatchingLid && desk.configurations.last == "on:2",
                     "a failed restore-all request promotes prior headless intent")
        desk.tearDown()

        (desk, service) = Self.desk()
        tap(desk, service, 1)
        tap(desk, service, 2)
        desk.configureSucceeds = false
        plug(desk, 3, in: false)
        suite.expect(service.displayControlFailure == .failed,
                     "a genuine headless transaction failure is not mislabeled as a closed-lid denial")
        desk.tearDown()
    }

    /// The lid is read again at the transaction, and that reading decides.
    private static func lidReads(_ suite: TestSuite) {
        var (desk, service) = desk()
        tap(desk, service, 1)
        tap(desk, service, 2)
        desk.lidClosed = true
        desk.configureSucceeds = false
        plug(desk, 3, in: false)
        suite.expect(desk.isWatchingLid, "failed headless round keeps the closed internal request queued")
        let made = desk.configurations.count
        desk.lidReads = [false, true]
        desk.lidMoved(closed: true)
        desk.drain()
        suite.expect(desk.configurations.count == made && desk.isWatchingLid,
                     "a deferred retry that closes at the transaction keeps headless ownership")
        desk.configureSucceeds = true
        plug(desk, 3, in: true)
        plug(desk, 3, in: false)
        suite.expect(!desk.isWatchingLid && switchedOff(desk) == [1] && desk.configurations.last == "on:2",
                     "later external headless success cancels only the internal headless request")
        let afterCancel = desk.configurations.count
        desk.lidMoved(closed: false)
        desk.drain()
        suite.expect(desk.configurations.count == afterCancel && switchedOff(desk) == [1],
                     "opening after cancellation does not enable the internal display")
        desk.tearDown()

        (desk, service) = Self.desk()
        tap(desk, service, 1)
        tap(desk, service, 2)
        desk.lidReads = [true, false]
        plug(desk, 3, in: false)
        suite.expect(!desk.isWatchingLid && desk.configurations.last == "on:2",
                     "headless candidate retry uses the shared transaction-time lid result")
        let headlessDone = desk.configurations.count
        desk.lidMoved(closed: false)
        desk.drain()
        suite.expect(desk.configurations.count == headlessDone,
                     "opening after a successful external headless recovery does not enable the internal display")
        desk.tearDown()

        // A tap on the panel waits behind the start-up restoration's recheck;
        // the lid opens in between, so the recheck succeeds first.
        (desk, service) = Self.desk()
        tap(desk, service, 1)
        service.toggleDisplay(service.displays.first { $0.id == 1 }!)
        desk.work.drain()
        desk.lidReads = [true, true]
        service.restoreDisplaysLeftOff()
        desk.drain()
        suite.expect(service.displayControlFailure == nil
                     && desk.configurations.filter { $0 == "on:1" }.count == 1,
                     "queued manual completion cannot republish denial after earlier queued recovery succeeds")
        desk.tearDown()
    }
}
