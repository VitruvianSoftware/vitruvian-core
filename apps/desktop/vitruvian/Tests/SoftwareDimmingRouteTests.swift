// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Moving one display between the DDC and the gamma route, on a started
/// production service over a scripted desk. Turning the choice off is the
/// half that has a screen to put back: the scaled curve is this app's and the
/// level behind it belongs to the gamma route, so both have to go before the
/// monitor takes the slider back (issue #1589).
enum SoftwareDimmingRouteTests {
    private typealias Rig = BrightnessRig

    /// The display as a row sees it. A monitor behind a converter is active,
    /// external, routed over DDC and answers no reads.
    enum Method { case ddc, software }
    struct Display {
        var isActive = true
        var isBuiltIn = false
        var method: Method? = .ddc
        var readable = false
        var canChooseDimming = true
    }

    /// A display row: which rows offer the dimming choice is the shipped rule.
    final class Row {
        var display = Display()
        var chosen = false
        var compact = false
        var offered: Bool {
            SoftwareDimmingButton.offersChoice(
                isActive: display.isActive, isBuiltIn: display.isBuiltIn,
                canChooseDimming: display.canChooseDimming, isDDC: display.method == .ddc,
                readable: display.readable, chosen: chosen, compact: compact)
        }
    }

    private static let id: CGDirectDisplayID = 7

    /// A started service over one external monitor, routes built.
    private static func desk(answersReads: Bool = true, forcedSoftware: Bool = false,
                             extendedDimming: Bool = false)
        -> (Rig.Desk, BrightnessService, Rig.Display, Rig.Monitor) {
        let desk = Rig.Desk()
        let monitor = Rig.Monitor(current: 50)
        monitor.answersReads = answersReads
        let display = Rig.Display(id: id, monitor: monitor)
        desk.displays = [display]
        if forcedSoftware {
            desk.defaults.set([display.pathKey], forKey: DefaultsKey.brightnessForcedSoftwarePaths)
            desk.defaults.set([display.pathKey], forKey: DefaultsKey.brightnessDDCWriteOnlyPaths)
        }
        if extendedDimming {
            desk.defaults.set([display.pathKey], forKey: DefaultsKey.brightnessExtendedDimmingPaths)
        }
        let service = BrightnessService(environment: desk.environment)
        service.start()
        desk.drain()
        return (desk, service, display, monitor)
    }

    private static func row(_ service: BrightnessService) -> BrightnessDisplay? {
        service.displays.first { $0.id == id }
    }

    private static func near(_ value: Float?, _ expected: Float) -> Bool {
        value.map { abs($0 - expected) < 0.0001 } ?? false
    }

    static func run(expect: (Bool, String) -> Void) {
        choiceOff(expect)
        choiceOn(expect)
        extendedChoice(expect)
        restoration(expect)
        extendedWrites(expect)
        rows(expect)

        // A display the rebuild has not routed yet has no path to record the
        // choice against, so nothing is written and no screen is touched.
        let unrouted = Rig.Desk()
        defer { unrouted.tearDown() }
        unrouted.displays = [Rig.Display(id: id, monitor: Rig.Monitor(current: 50))]
        let idle = BrightnessService(environment: unrouted.environment)
        idle.setSoftwareDimmingPreferred(false, for: id)
        expect(unrouted.defaults.object(forKey: DefaultsKey.brightnessForcedSoftwarePaths) == nil
               && unrouted.defaults.object(forKey: DefaultsKey.brightnessDDCWriteOnlyPaths) == nil
               && unrouted.work.pending.isEmpty && unrouted.main.pending.isEmpty
               && unrouted.displays[0].gammaWrites.isEmpty,
               "a display with no known DDC path is left alone entirely")
    }

    private static func choiceOff(_ expect: (Bool, String) -> Void) {
        let (desk, service, display, monitor) = desk(answersReads: false, forcedSoftware: true)
        defer { desk.tearDown() }
        service.setBrightness(0.35, for: id)
        desk.drain()
        expect(row(service)?.method == .software && row(service)?.canChooseDimming == true
               && service.softwareDimmingPreferred == [id] && near(display.pictureScale, 0.35),
               "a display chosen for software dimming dims its picture on the gamma route")

        let writes = display.gammaWrites.count
        let reads = monitor.reads
        service.setSoftwareDimmingPreferred(false, for: id)
        expect(desk.defaults.stringArray(forKey: DefaultsKey.brightnessForcedSoftwarePaths) == []
               && desk.defaults.stringArray(forKey: DefaultsKey.brightnessDDCWriteOnlyPaths) == [],
               "turning the choice off releases the display and lets the channel be probed again")
        expect(display.gammaWrites.count == writes && desk.main.pending.isEmpty,
               "nothing touches the screen before the work queue runs")
        desk.work.drain()
        expect(near(display.pictureScale, 1), "the picture goes back to its own curve when the choice goes off")
        expect(desk.work.pending.isEmpty && desk.main.pending.count == 1 && monitor.reads == reads,
               "the rebuild waits for the restored curve, so the probe reads an undimmed display")
        desk.drain()
        expect(row(service)?.method == .ddc && monitor.reads > reads,
               "the display is rebuilt onto the DDC route once the picture is back")
        expect(row(service)?.brightness == 0.5,
               "the slider starts from the monitor rather than the level the gamma route left behind")
    }

    private static func choiceOn(_ expect: (Bool, String) -> Void) {
        let (desk, service, display, _) = desk()
        defer { desk.tearDown() }
        service.setBrightness(0.35, for: id)
        desk.drain()
        service.setSoftwareDimmingPreferred(true, for: id)
        expect(desk.defaults.stringArray(forKey: DefaultsKey.brightnessForcedSoftwarePaths) == [display.pathKey]
               && desk.work.pending.count == 1,
               "choosing software dimming pins the display and rebuilds it straight away")
        desk.drain()
        expect(display.gammaWrites.isEmpty && row(service)?.method == .software
               && service.softwareDimmingPreferred == [id],
               "choosing it never restores a curve, which would undo the dim being asked for")
    }

    private static func extendedChoice(_ expect: (Bool, String) -> Void) {
        let (desk, service, display, monitor) = desk()
        defer { desk.tearDown() }
        service.setBrightness(0.05, for: id)
        service.setExtendedDimmingPreferred(true, for: id)
        expect(desk.defaults.stringArray(forKey: DefaultsKey.brightnessExtendedDimmingPaths) == [display.pathKey],
               "extended dimming is saved for this monitor")
        desk.drain()
        expect(!monitor.written.contains(5) && service.extendedDimmingPreferred == [id],
               "extended dimming drops a write in the old slider scale and rebuilds the route")

        service.setBrightness(0.625, for: id)
        desk.drain()
        let writes = display.gammaWrites.count
        let reads = monitor.reads
        service.setExtendedDimmingPreferred(false, for: id)
        expect(desk.defaults.stringArray(forKey: DefaultsKey.brightnessExtendedDimmingPaths) == [],
               "turning extended dimming off forgets it for this monitor")
        service.step(id, method: .ddc, delta: 0.0625, showOSD: false)
        desk.work.drain()
        expect(monitor.reads == reads + 1, "turning extended dimming off clears its remembered slider level")
        desk.drain()
        expect(display.gammaWrites.count == writes,
               "turning extended dimming off leaves an unchanged gamma curve alone")

        let (dimmedDesk, dimmed, dimmedDisplay, _) = Self.desk(extendedDimming: true)
        defer { dimmedDesk.tearDown() }
        dimmed.setBrightness(0.1, for: id)
        dimmedDesk.drain()
        dimmed.setExtendedDimmingPreferred(false, for: id)
        dimmedDesk.work.drain()
        expect(near(dimmedDisplay.pictureScale, 1) && dimmedDesk.main.pending.count == 1,
               "turning extended dimming off restores a curve the app actually dimmed, before the rebuild")
    }

    /// Stopping puts back only curves this app dimmed, on the monitor it
    /// dimmed them on.
    private static func restoration(_ expect: (Bool, String) -> Void) {
        let desk = Rig.Desk()
        defer { desk.tearDown() }
        desk.displays = [7, 8, 9].map { Rig.Display(id: $0) }
        let service = BrightnessService(environment: desk.environment)
        service.start()
        desk.drain()
        service.setBrightness(0.5, for: 7)
        service.setBrightness(0.5, for: 9)
        desk.drain()
        desk.display(9).fingerprint = "another-monitor"
        for display in desk.displays { display.gammaWrites = [] }
        service.restoreDisplaysBeforeTermination()
        expect(desk.display(7).gammaWrites == [Rig.Display.identityCurve]
               && desk.display(8).gammaWrites.isEmpty && desk.display(9).gammaWrites.isEmpty,
               "stopping restores only curves this app dimmed on the same monitor")
        service.restoreDisplaysBeforeTermination()
        expect(desk.display(7).gammaWrites.count == 1, "a curve once restored is not written again")

        // Stopping the service puts the curve back and forgets the dim with
        // it, so starting again reads the monitor instead of redoing a curve.
        let (stoppedDesk, stopped, stoppedDisplay, _) = Self.desk(extendedDimming: true)
        defer { stoppedDesk.tearDown() }
        stopped.setBrightness(0.1, for: id)
        stoppedDesk.drain()
        stopped.stop()
        stoppedDesk.drain()
        let restored = stoppedDisplay.gammaWrites.count
        stopped.start()
        stoppedDesk.drain()
        expect(near(stoppedDisplay.pictureScale, 1) && stoppedDisplay.gammaWrites.count == restored,
               "a curve put back on stopping is not written again when the service starts")
    }

    /// The lower quarter of the slider scales the picture, the rest drives
    /// the monitor, and the two never leave the screen darker than asked.
    private static func extendedWrites(_ expect: (Bool, String) -> Void) {
        let (desk, service, _, _) = desk(extendedDimming: true)
        defer { desk.tearDown() }
        desk.events = []
        service.setBrightness(0.125, for: id)
        desk.drain()
        expect(desk.events == ["ddc:0", "picture:0.5"],
               "the monitor reaches its hardware minimum before the picture dims")
        desk.events = []
        service.setBrightness(0.0625, for: id)
        desk.drain()
        expect(desk.events == ["picture:0.25"],
               "dragging within the software range does not repeat a slow DDC write")
        desk.events = []
        service.setBrightness(0.625, for: id)
        desk.drain()
        expect(desk.events == ["picture:1.0", "ddc:50"],
               "the unmodified picture returns before hardware brightness rises")
        service.setBrightness(0.0625, for: id)
        desk.drain()
        desk.gammaSucceeds = false
        desk.events = []
        service.setBrightness(1, for: id)
        desk.drain()
        expect(desk.events == ["picture:1.0"],
               "a failed picture restore never raises the hardware brightness")
    }

    /// Which rows offer the choice at all. The rule is the same on both
    /// surfaces, since they share the control.
    private static func rows(_ expect: (Bool, String) -> Void) {
        let row = Row()
        expect(row.offered, "a monitor whose channel takes writes and answers no reads is offered the choice")
        row.display.readable = true
        expect(row.offered, "a readable DDC monitor offers optional dimming below its hardware minimum")
        row.compact = true
        expect(!row.offered, "the compact panel leaves the extra dimming choice to Settings")
        row.chosen = true
        expect(row.offered, "extra dimming stays in the compact panel once it is on, so it can be turned off")
        row.chosen = false
        row.display.readable = false
        expect(row.offered, "the compact panel keeps the write-only way out")
        row.display.readable = true
        row.compact = false
        row.display.canChooseDimming = false
        expect(!row.offered, "a display with no stable connection path cannot save a dimming choice")
        row.display.canChooseDimming = true
        row.display.readable = false
        row.display.isBuiltIn = true
        expect(!row.offered, "the built-in display never routes over DDC, so it is never asked about")
        row.display.isBuiltIn = false
        row.display.isActive = false
        expect(!row.offered, "a display that is switched off has nothing to dim")
        row.display.isActive = true
        row.display.method = .software
        expect(!row.offered, "a display already on the gamma route for its own reasons is not a choice")
        row.chosen = true
        expect(row.offered,
               "a display moved here by hand keeps the control, or there would be no way back to DDC")
        row.display.isActive = false
        expect(!row.offered, "not even a chosen display offers the control while it is switched off")
    }
}
