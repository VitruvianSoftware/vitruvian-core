// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The raw wheel tap's decision runs as shipped on real wheel events. Only
/// the exception lists it asks and the defaults it reads are replaced here.
enum LinearScrollTapTests {
    /// The apps the wheel is excepted for. Only the test's own thread touches it.
    nonisolated final class Exceptions: @unchecked Sendable {
        var excepted: Set<MouseExceptionScope> = []
    }

    static func run(_ suite: TestSuite) {
        let name = "com.vitruviansoftware.vitruvian.tests.linear-scroll-tap.\(UUID().uuidString)"
        let defaults = Foundation.UserDefaults(suiteName: name)!
        let exceptions = Exceptions()
        let targets = ScrollInverter.WheelTapTargets(excludes: { scope, _, _ in exceptions.excepted.contains(scope) },
                                                     isOwnWindow: { _ in false })
        defer { defaults.removePersistentDomain(forName: name) }
        func configure(linear: Bool = true, installed: Bool = true, lines: Int = 3,
                       invert: Bool = false, inverterInstalled: Bool = true,
                       sidewaysKey: ScrollHorizontalModifier? = nil) {
            defaults.set(installed, forKey: AppFeature.linearScroll.availabilityKey)
            defaults.set(linear, forKey: DefaultsKey.linearScrollEnabled)
            defaults.set(lines, forKey: DefaultsKey.linearScrollLines)
            defaults.set(inverterInstalled, forKey: AppFeature.scrollInverter.availabilityKey)
            defaults.set(invert, forKey: DefaultsKey.scrollInverterEnabled)
            defaults.set(sidewaysKey != nil, forKey: AppFeature.scrollHorizontal.availabilityKey)
            defaults.set(sidewaysKey != nil, forKey: DefaultsKey.scrollHorizontalEnabled)
            defaults.set(sidewaysKey?.rawValue, forKey: DefaultsKey.scrollHorizontalModifier)
            exceptions.excepted = []
        }
        /// One event through the shipped decision, with the state one tap keeps
        /// across events; nil when it was held back. Events built here carry
        /// this process's id, which the tap skips as its own glide frames, so
        /// the decision is given an id no event carries.
        func carry(_ event: CGEvent, through state: inout ScrollInverter.WheelTapState) -> CGEvent? {
            ScrollInverter.adjustWheel(event, state: &state, defaults: defaults, ownProcessID: -1,
                                       targets: targets) ? event : nil
        }
        /// One event through a tap that has seen nothing before it.
        func deliver(_ event: CGEvent) -> CGEvent? {
            var fresh = ScrollInverter.WheelTapState()
            return carry(event, through: &fresh)
        }

        // Notches as a plain Bluetooth wheel sends them with macOS acceleration
        // on: slow, medium and fast turns of the same single notch.
        configure()
        let slow = deliver(wheel(line: 1, fixed: 0.1, point: 1))
        let medium = deliver(wheel(line: 1, fixed: 0.403, point: 5))
        let fast = deliver(wheel(line: 7, fixed: 7.298, point: 73))
        suite.expect([slow, medium, fast].allSatisfy { $0.map(verticalLine) == 3 },
                     "a slow, a medium and a fast notch leave the wheel tap as the same three lines")

        let pointOnly = deliver(wheel(line: 0, fixed: 0, point: 10))
        suite.expect(pointOnly.map(verticalLine) == 3,
                     "a discrete point-only wheel event survives the raw tap and moves one notch")

        configure(lines: 1)
        let fraction = deliver(wheel(line: 1, fixed: 1.5, point: 15))
        suite.expect(fraction.map(verticalLine) == 1 && fraction.map(verticalFixed) == 1,
                     "a high-resolution notch whose line already matches still loses its extra half line")

        configure()
        var carrying = ScrollInverter.WheelTapState()
        let quarters = (0..<4).map { _ in carry(wheel(line: 0, fixed: 0.25, point: 0), through: &carrying) }
        let delivered = quarters.compactMap { $0 }
        suite.expect(delivered.map(verticalLine).reduce(0, +) == 3
                        && delivered.allSatisfy { verticalLine($0) != 0 },
                     "four quarter notches add up to one notch, and a quarter that moves no whole line is held back")

        configure()
        var afterException = ScrollInverter.WheelTapState()
        _ = carry(wheel(line: 0, fixed: 0.25, point: 0), through: &afterException)
        exceptions.excepted = [.linearScroll]
        _ = carry(wheel(line: 1, fixed: 1, point: 10), through: &afterException)
        exceptions.excepted = []
        suite.expect(carry(wheel(line: 0, fixed: 0.25, point: 0), through: &afterException) == nil,
                     "a fractional notch does not carry through an excepted app")

        configure()
        var afterOff = ScrollInverter.WheelTapState()
        _ = carry(wheel(line: 0, fixed: 0.25, point: 0), through: &afterOff)
        configure(linear: false)
        _ = carry(wheel(line: 1, fixed: 1, point: 10), through: &afterOff)
        configure()
        suite.expect(carry(wheel(line: 0, fixed: 0.25, point: 0), through: &afterOff) == nil,
                     "a fractional notch does not carry through a disabled interval")

        configure()
        exceptions.excepted = [.linearScroll]
        let excepted = deliver(wheel(line: 4, fixed: 4, point: 40))
        suite.expect(excepted.map(verticalLine) == 4 && excepted.map(verticalFixed) == 4,
                     "an app on linear scrolling's own list gets the wheel exactly as macOS sent it")

        configure(linear: false)
        let off = deliver(wheel(line: 4, fixed: 4, point: 40))
        configure(installed: false)
        let uninstalled = deliver(wheel(line: 4, fixed: 4, point: 40))
        suite.expect(off.map(verticalLine) == 4 && uninstalled.map(verticalLine) == 4,
                     "linear scrolling switched off or uninstalled leaves the wheel alone")

        configure(invert: true)
        let flipped = deliver(wheel(line: 4, fixed: 4, point: 40))
        configure(invert: true, inverterInstalled: false)
        let inverterRemoved = deliver(wheel(line: 4, fixed: 4, point: 40))
        suite.expect(flipped.map(verticalLine) == -3 && inverterRemoved.map(verticalLine) == 3,
                     "the capped notch is flipped only while the inverter is installed, not because linear scrolling keeps the tap up")

        configure(invert: true)
        exceptions.excepted = [.scrollDirection]
        let directionExcepted = deliver(wheel(line: 4, fixed: 4, point: 40))
        suite.expect(directionExcepted.map(verticalLine) == 3,
                     "an app excepted from the direction change is still capped by linear scrolling")

        configure(sidewaysKey: .option)
        let sideways = deliver(wheel(line: 4, fixed: 4, point: 40, flags: .maskAlternate))
        suite.expect(sideways.map(verticalLine) == 0
                        && sideways?.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 3,
                     "a modifier-held notch is capped before it is turned sideways")

        configure()
        let nativeZoom = deliver(wheel(line: 4, fixed: 4, point: 40, flags: .maskControl))
        suite.expect(nativeZoom.map(verticalLine) == 4 && nativeZoom.map(verticalFixed) == 4,
                     "Control-wheel keeps native zoom when Control is not the horizontal shortcut")
        configure(sidewaysKey: .control)
        let controlSideways = deliver(wheel(line: 4, fixed: 4, point: 40, flags: .maskControl))
        suite.expect(controlSideways.map(verticalLine) == 0
                        && controlSideways?.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 3,
                     "the explicit Control-to-horizontal shortcut still receives the fixed notch")
        exceptions.excepted = [.scrollDirection]
        let exceptedZoom = deliver(wheel(line: 4, fixed: 4, point: 40, flags: .maskControl))
        suite.expect(exceptedZoom.map(verticalLine) == 4,
                     "a direction exception also preserves Control-wheel zoom")

        configure()
        let continuous = deliver(wheel(continuous: true, line: 0, fixed: 4, point: 40))
        suite.expect(continuous?.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 30
                        && continuous.map(verticalFixed) == 3,
                     "a wheel reported as continuous is capped in the points and lines apps read")

        configure()
        let trackpad = wheel(continuous: true, line: 0, fixed: 4, point: 40)
        trackpad.setIntegerValueField(.scrollWheelEventScrollPhase, value: 1)
        suite.expect(deliver(trackpad)?.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 40,
                     "a trackpad gesture passes through untouched")
    }

    private static func verticalLine(_ event: CGEvent) -> Int64 {
        event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
    }

    private static func verticalFixed(_ event: CGEvent) -> Double {
        event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
    }

    private static func wheel(continuous: Bool = false, line: Int64, fixed: Double, point: Int64,
                              flags: CGEventFlags = []) -> CGEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                            wheel1: 0, wheel2: 0, wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: line)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixed)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: point)
        event.flags = flags
        return event
    }
}
