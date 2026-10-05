// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The production brightness step and writes, on a started service over a
/// scripted desk: a DDC monitor that answers reads and takes writes, and a
/// built-in panel on the system pipeline. No monitor is read or written.
enum BrightnessStepTests {
    private typealias Rig = BrightnessRig

    /// A started service over one external DDC monitor, routes built.
    private static func monitorDesk(level: UInt16 = 50, extendedDimming: Bool = false)
        -> (Rig.Desk, BrightnessService, Rig.Monitor) {
        let desk = Rig.Desk()
        let monitor = Rig.Monitor(current: level)
        let display = Rig.Display(id: 2, monitor: monitor)
        desk.displays = [display]
        if extendedDimming {
            desk.defaults.set([display.pathKey], forKey: DefaultsKey.brightnessExtendedDimmingPaths)
        }
        let service = BrightnessService(environment: desk.environment)
        service.start()
        desk.drain()
        return (desk, service, monitor)
    }

    private static func level(_ service: BrightnessService, _ id: CGDirectDisplayID = 2) -> Double {
        service.displays.first { $0.id == id }?.brightness ?? -1
    }

    private static func close(_ value: Double, _ expected: Double) -> Bool {
        abs(value - expected) < 0.0001
    }

    static func run(_ suite: TestSuite) {
        let (desk, service, monitor) = monitorDesk()
        defer { desk.tearDown() }
        suite.expect(service.displays.map(\.method) == [.ddc] && service.displays.first?.readable == true
                     && close(level(service), 0.5),
                     "a monitor that answers DDC gets a readable route at the level it reports")

        monitor.current = 80
        desk.advance(seconds: 5)
        var reads = monitor.reads
        service.step(2, method: .ddc, delta: 0.1, showOSD: false)
        desk.drain()
        suite.expect(monitor.reads == reads + 1 && close(level(service), 0.9) && monitor.written.last == 90,
                     "a step after a pause starts from the level the monitor reports")

        desk.advance(seconds: 5)
        service.step(2, method: .ddc, delta: 0.1, showOSD: false)
        desk.work.drain()
        service.setBrightness(0.3, for: 2)
        desk.drain()
        suite.expect(close(level(service), 0.4) && monitor.written.last == 40,
                     "a level set while the monitor was read wins over the older read")

        reads = monitor.reads
        service.step(2, method: .ddc, delta: 0.1, showOSD: false)
        desk.drain()
        suite.expect(monitor.reads == reads && close(level(service), 0.5),
                     "steps in a burst use the running level instead of reading the monitor again")

        desk.advance(seconds: 5)
        service.step(2, method: .ddc, delta: 0.1, showOSD: false)
        service.step(2, method: .ddc, delta: 0.1, showOSD: false)
        desk.drain()
        suite.expect(close(level(service), 0.7) && monitor.written.last == 70,
                     "a press while the monitor is read joins the step that read commits")

        desk.defaults.set(true, forKey: DefaultsKey.brightnessOSDEnabled)
        service.step(2, method: .ddc, delta: 0.1, showOSD: true)
        desk.drain()
        suite.expect(desk.overlays == ["2:0.800"], "a written step shows the overlay")
        desk.islandShowsBrightness = true
        service.step(2, method: .ddc, delta: 0.1, showOSD: true)
        desk.drain()
        suite.expect(desk.overlays == ["2:0.800"], "a step the island shows leaves the overlay away")

        extendedRange(suite)
        systemWrites(suite)
    }

    /// A monitor with dimming below its hardware minimum: the lower quarter
    /// of the slider scales the picture, the rest drives the monitor.
    private static func extendedRange(_ suite: TestSuite) {
        let (desk, service, monitor) = monitorDesk(extendedDimming: true)
        defer { desk.tearDown() }
        let reported = BrightnessSupport.reconnectedDimLevel(
            BrightnessSupport.extendedDimmingLevel(hardware: 0.5, remembered: nil, pictureDimmed: false))
        suite.expect(close(level(service), reported) && service.extendedDimmingPreferred == [2],
                     "a monitor with extra dimming reports its level on the extended scale")

        service.setBrightness(0.125, for: 2)
        desk.drain()
        desk.advance(seconds: 5)
        let reads = monitor.reads
        service.step(2, method: .ddc, delta: 0.1, showOSD: false)
        desk.drain()
        suite.expect(monitor.reads == reads && close(level(service), 0.225),
                     "a step in the extended software range uses the known picture level")

        service.setBrightness(0.625, for: 2)
        desk.drain()
        monitor.current = 80
        desk.advance(seconds: 5)
        service.step(2, method: .ddc, delta: 0.1, showOSD: false)
        desk.drain()
        let mapped = BrightnessSupport.extendedDimmingLevel(hardware: 0.8, remembered: nil, pictureDimmed: false)
        suite.expect(close(level(service), mapped + 0.1),
                     "a stale hardware-range step maps the monitor's actual DDC level")

        service.setBrightness(0.625, for: 2)
        desk.drain()
        monitor.current = 58
        monitor.forgetWrites()
        desk.advance(seconds: 5)
        service.step(2, method: .ddc, delta: -BrightnessSupport.brightnessKeyStep, showOSD: false)
        desk.drain()
        suite.expect(monitor.written == [50],
                     "a physical monitor adjustment cannot suppress a step back to the app's previous value")
    }

    /// A key step on a system display eases by the change from the level the
    /// system reports. Everything else writes the level itself, once, so a
    /// change the system refuses or ignores is never added twice (issue #2149).
    private static func systemWrites(_ suite: TestSuite) {
        func panelDesk(easing: Bool = true) -> (Rig.Desk, BrightnessService, Rig.Display) {
            let desk = Rig.Desk()
            desk.easingAvailable = easing
            let panel = Rig.Display(id: 1, systemLevel: 0.5)
            panel.builtIn = true
            desk.displays = [panel]
            let service = BrightnessService(environment: desk.environment)
            service.start()
            desk.drain()
            return (desk, service, panel)
        }
        let (desk, service, panel) = panelDesk()
        defer { desk.tearDown() }
        suite.expect(service.displays.map(\.method) == [.system], "the built-in panel takes the system route")

        func keyStep(from reported: Float, easing: Rig.Easing = .lands) -> [String] {
            panel.systemLevel = reported
            desk.easing = easing
            desk.systemCalls = []
            desk.advance(seconds: 5)
            service.step(1, method: .system, delta: 0.0625, showOSD: false)
            desk.drain()
            return desk.systemCalls
        }
        suite.expect(keyStep(from: 0.5) == ["ease 0.0625"] && panel.systemLevel == 0.5625,
                     "a key step on a system display eases by the change from the reported level")
        desk.systemCalls = []
        service.setBrightness(0.25, for: 1)
        desk.drain()
        suite.expect(desk.systemCalls == ["set 0.25"] && panel.systemLevel == 0.25,
                     "a slider write on a system display lands at once")
        panel.systemLevel = 0.5
        service.setBrightness(0.25, for: 1)
        service.step(1, method: .system, delta: 0.0625, showOSD: false)
        desk.drain()
        suite.expect(panel.systemLevel == 0.3125,
                     "a key step right after a slider move steps from the level still on its way")
        let fallback = ["ease 0.0625", "set 0.5625"]
        suite.expect(keyStep(from: 0.5, easing: .refused) == fallback && panel.systemLevel == 0.5625,
                     "an eased step the system refuses gets the level written directly")
        suite.expect(keyStep(from: 0.5, easing: .ignored) == fallback && panel.systemLevel == 0.5625,
                     "an eased step the system ignores gets the level written once, never the change twice")
        suite.expect(keyStep(from: 1) == ["set 1.0"] && panel.systemLevel == 1,
                     "a step already at the end of the range writes the level without easing")
        service.setBrightness(0.5, for: 1)
        desk.drain()
        panel.asleep = true
        panel.systemLevel = 0.2
        desk.systemCalls = []
        service.step(1, method: .system, delta: 0.0625, showOSD: false)
        desk.drain()
        panel.asleep = false
        suite.expect(desk.systemCalls == ["set 0.5625"],
                     "an asleep display steps from the last known level and gets it directly")

        let (plain, plainService, plainPanel) = panelDesk(easing: false)
        defer { plain.tearDown() }
        plainService.step(1, method: .system, delta: 0.0625, showOSD: false)
        plain.drain()
        suite.expect(plain.systemCalls == ["set 0.5625"] && plainPanel.systemLevel == 0.5625,
                     "a system without the easing call gets the level directly")
    }
}
