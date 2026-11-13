// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import VitruvianAtriumCore
import VitruvianAtriumDesign
import VitruvianAtriumServices
import VitruvianAtriumUI

/// The raw wheel tap's decision runs as shipped on real wheel events. Only
/// the exception lists it asks and the defaults it reads are replaced here.
enum LinearScrollTapTests {
    /// The apps the wheel is excepted for. Only the test's own thread touches it.
    nonisolated final class Exceptions: @unchecked Sendable {
        var excepted: Set<MouseExceptionScope> = []
        var ownWindow = false
    }

    /// What Pinch Zoom answers the tap, and how often it was asked.
    nonisolated final class PinchZoomTurns: @unchecked Sendable {
        var verdict = PinchZoomVerdict.notZoom
        var overOwnWindow = false
        var asked = 0
    }

    static func run(_ suite: TestSuite) {
        let name = "com.vitruviansoftware.vitruvian.tests.linear-scroll-tap.\(UUID().uuidString)"
        let defaults = ScratchDefaults.suite(named: name)!
        let exceptions = Exceptions()
        let targets = ScrollInverter.WheelTapTargets(excludes: { scope, _, _ in exceptions.excepted.contains(scope) },
                                                     isOwnWindow: { _ in exceptions.ownWindow })
        defer { defaults.removePersistentDomain(forName: name) }
        func configure(linear: Bool = true, installed: Bool = true, lines: Int = 3,
                       invert: Bool = false, inverterInstalled: Bool = true,
                       sidewaysKey: ScrollHorizontalModifier? = nil,
                       speedKey: ScrollHorizontalModifier? = nil, speedFactor: Int = 3) {
            defaults.set(installed, forKey: AppFeature.linearScroll.availabilityKey)
            defaults.set(linear, forKey: DefaultsKey.linearScrollEnabled)
            defaults.set(lines, forKey: DefaultsKey.linearScrollLines)
            defaults.set(inverterInstalled, forKey: AppFeature.scrollInverter.availabilityKey)
            defaults.set(invert, forKey: DefaultsKey.scrollInverterEnabled)
            defaults.set(sidewaysKey != nil, forKey: AppFeature.scrollHorizontal.availabilityKey)
            defaults.set(sidewaysKey != nil, forKey: DefaultsKey.scrollHorizontalEnabled)
            defaults.set(sidewaysKey?.rawValue, forKey: DefaultsKey.scrollHorizontalModifier)
            defaults.set(speedKey != nil, forKey: AppFeature.scrollSpeed.availabilityKey)
            defaults.set(speedKey != nil, forKey: DefaultsKey.scrollSpeedEnabled)
            defaults.set(speedKey?.rawValue, forKey: DefaultsKey.scrollSpeedModifier)
            defaults.set(speedFactor, forKey: DefaultsKey.scrollSpeedMultiplier)
            exceptions.excepted = []
            exceptions.ownWindow = false
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

        // Modifier-held scroll speed, on the shipped decision.
        configure(linear: false, speedKey: .option, speedFactor: 4)
        let sped = deliver(wheel(line: 2, fixed: 2, point: 20, flags: .maskAlternate))
        suite.expect(sped.map(verticalLine) == 8 && sped?.flags.isEmpty == true,
                     "Option-held speed multiplies the raw notch and consumes the modifier")
        configure(speedKey: .option, speedFactor: 3)
        let linearThenSpeed = deliver(wheel(line: 7, fixed: 7, point: 70, flags: .maskAlternate))
        suite.expect(linearThenSpeed.map(verticalLine) == 9,
                     "linear scrolling caps the notch before speed multiplies it")
        configure(linear: false, sidewaysKey: .option, speedKey: .option, speedFactor: 4)
        let horizontalWins = deliver(wheel(line: 2, fixed: 2, point: 20, flags: .maskAlternate))
        suite.expect(horizontalWins.map(verticalLine) == 0
                        && horizontalWins?.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 2,
                     "horizontal redirection with the same modifier wins over speed")
        configure(linear: false, speedKey: .option, speedFactor: 4)
        exceptions.excepted = [.scrollSpeed]
        let speedExcepted = deliver(wheel(line: 2, fixed: 2, point: 20, flags: .maskAlternate))
        suite.expect(speedExcepted.map(verticalLine) == 2
                        && speedExcepted?.flags.contains(.maskAlternate) == true,
                     "an app on scroll speed's own list keeps the unmodified wheel")
        configure(linear: false, speedKey: .option, speedFactor: 4)
        exceptions.ownWindow = true
        let ownSpeed = deliver(wheel(line: 2, fixed: 2, point: 20, flags: .maskAlternate))
        suite.expect(ownSpeed.map(verticalLine) == 2
                        && ownSpeed?.flags.contains(.maskAlternate) == true,
                     "own windows skip modifier-held speed")
        configure(linear: false, speedKey: .option, speedFactor: 4)
        let continuousMouseSpeed = deliver(wheel(continuous: true, line: 0, fixed: 4, point: 40,
                                                 flags: .maskAlternate))
        suite.expect(continuousMouseSpeed?.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 160,
                     "continuous mouse wheels still multiply under the speed modifier")
        let subline = deliver(wheel(line: 0, fixed: 0.125, point: 0, flags: .maskAlternate))
        suite.expect(subline.map(verticalFixed) == 0.5 && subline.map(verticalLine) == 0
                        && subline?.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 0,
                     "a fixed-point-only wheel tick keeps its scaled fraction without inventing pixels or lines")
        for sign: Int64 in [-1, 1] {
            let large = deliver(wheel(line: sign * 20_000, fixed: Double(sign), point: sign * 1_000_000_000,
                                      flags: .maskAlternate))
            suite.expect(large.map(verticalLine) == Int64(sign > 0 ? Int16.max : Int16.min)
                            && large?.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                                == Int64(sign > 0 ? Int32.max : Int32.min),
                         "scaling a large input saturates the Quartz integer fields without reversing direction")
        }
        configure(lines: 1, speedKey: .option)
        for boostFirst in [true, false] {
            var inverterState = ScrollInverter.WheelTapState()
            let first = carry(wheel(line: 0, fixed: 0.5, point: 5, flags: boostFirst ? .maskAlternate : []),
                              through: &inverterState)
            let second = carry(wheel(line: 0, fixed: 0.5, point: 5, flags: boostFirst ? [] : .maskAlternate),
                               through: &inverterState)
            suite.expect(first.map(verticalLine) == (boostFirst ? 1 : nil)
                            && second.map(verticalLine) == (boostFirst ? 1 : 2)
                            && inverterState.linearCarryVertical == 0,
                         "each half-notch carries the speed of its own tick through a modifier change")
        }

        // Pinch Zoom has its turn at a zoom wheel before the wheel is capped.
        let pinch = PinchZoomTurns()
        let pinchTargets = ScrollInverter.WheelTapTargets(
            excludes: { scope, _, _ in exceptions.excepted.contains(scope) },
            isOwnWindow: { _ in pinch.overOwnWindow },
            pinchZoom: { _, _ in
                pinch.asked += 1
                return pinch.verdict
            })
        func zoomWheel(_ event: CGEvent) -> CGEvent? {
            var fresh = ScrollInverter.WheelTapState()
            return ScrollInverter.adjustWheel(event, state: &fresh, defaults: defaults, ownProcessID: -1,
                                              targets: pinchTargets) ? event : nil
        }
        func configurePinch(installed: Bool = true) {
            configure()
            defaults.set(installed, forKey: AppFeature.scrollZoom.availabilityKey)
            defaults.set(true, forKey: DefaultsKey.pinchZoomEnabled)
            defaults.set(ScrollZoomModifier.option.rawValue, forKey: DefaultsKey.pinchZoomModifier)
            pinch.verdict = .notZoom
            pinch.overOwnWindow = false
            pinch.asked = 0
        }
        defer {
            defaults.removeObject(forKey: AppFeature.scrollZoom.availabilityKey)
            defaults.removeObject(forKey: DefaultsKey.pinchZoomEnabled)
            defaults.removeObject(forKey: DefaultsKey.pinchZoomModifier)
        }
        configurePinch()
        pinch.verdict = .consumed
        suite.expect(zoomWheel(wheel(line: 4, fixed: 4, point: 40, flags: .maskAlternate)) == nil && pinch.asked == 1,
                     "a zoom wheel Pinch Zoom turned into a gesture is dropped")
        configurePinch()
        pinch.verdict = .declined
        let declined = zoomWheel(wheel(line: 4, fixed: 4, point: 40, flags: .maskAlternate))
        suite.expect(declined.map(verticalLine) == 4 && declined.map(verticalFixed) == 4,
                     "a zoom wheel Pinch Zoom declined outside this app's windows goes on as macOS sent it")
        configurePinch()
        pinch.verdict = .declined
        pinch.overOwnWindow = true
        let ownPanel = zoomWheel(wheel(line: 4, fixed: 4, point: 40, flags: .maskAlternate))
        suite.expect(ownPanel.map(verticalLine) == 3,
                     "over one of this app's panels a zoom wheel keeps its ordinary path")
        configurePinch()
        let switcherWheel = zoomWheel(wheel(line: 4, fixed: 4, point: 40, flags: .maskAlternate))
        suite.expect(switcherWheel.map(verticalLine) == 3 && pinch.asked == 1,
                     "a wheel Pinch Zoom leaves, as for the open switcher, keeps its ordinary path")
        configurePinch()
        pinch.verdict = .consumed
        let plain = zoomWheel(wheel(line: 4, fixed: 4, point: 40))
        suite.expect(plain.map(verticalLine) == 3 && pinch.asked == 0,
                     "a wheel without the zoom modifier never reaches Pinch Zoom")
        configurePinch(installed: false)
        pinch.verdict = .consumed
        let removed = zoomWheel(wheel(line: 4, fixed: 4, point: 40, flags: .maskAlternate))
        suite.expect(removed.map(verticalLine) == 3 && pinch.asked == 0,
                     "an uninstalled Pinch Zoom never takes the wheel")
        configurePinch()
        pinch.verdict = .consumed
        exceptions.excepted = [.scrollDirection]
        let exceptedPinch = zoomWheel(wheel(line: 4, fixed: 4, point: 40, flags: .maskAlternate))
        suite.expect(exceptedPinch.map(verticalLine) == 3 && pinch.asked == 0,
                     "an app excepted from Scroll Direction keeps its zoom wheel")
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
