// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import VMStatisticsCompat
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

enum PointerInputFeatureTests {
    static func run(_ suite: TestSuite) {
        func expectFormat(_ format: String, _ expected: [String], _ label: String,
                          file: StaticString = #filePath, line: UInt = #line) {
            let actual = TestFormat.parse(format)?.conversions ?? ["invalid format"]
            suite.expect(actual == expected, "\(label): got \(actual), expected \(expected)",
                         file: file, line: line)
        }
        let layoutDictionary = [kTISPropertyInputSourceType: kTISTypeKeyboardLayout] as CFDictionary
        let layoutSources = (TISCreateInputSourceList(layoutDictionary, true)?.takeRetainedValue()
            as? [TISInputSource]) ?? []
        func testLayoutData(for idString: String) -> Data? {
            guard let source = layoutSources.first(where: {
                guard let identifier = TISGetInputSourceProperty($0, kTISPropertyInputSourceID)
                else { return false }
                return Unmanaged<CFString>.fromOpaque(identifier).takeUnretainedValue() as String
                    == idString
            }), let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            else { return nil }
            return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        }

        // MARK: Keyboard debounce

        var debounceState = KeyboardDebounceState()
        let debounceConfig = KeyboardDebounceConfig(enabled: true,
                                                    globalWindowMs: 50,
                                                    keyWindows: [:])
        func debounceDown(_ keyCode: Int64,
                          at time: TimeInterval,
                          repeat isAutoRepeat: Bool = false,
                          config: KeyboardDebounceConfig) -> Bool {
            debounceState.shouldSuppress(keyCode: keyCode,
                                         isAutoRepeat: isAutoRepeat,
                                         event: .keyDown,
                                         time: time,
                                         config: config)
        }
        func debounceUp(_ keyCode: Int64,
                        at time: TimeInterval,
                        config: KeyboardDebounceConfig) -> Bool {
            debounceState.shouldSuppress(keyCode: keyCode,
                                         isAutoRepeat: false,
                                         event: .keyUp,
                                         time: time,
                                         config: config)
        }
        suite.expect(!debounceDown(37, at: 10.00, config: debounceConfig),
               "debounce accepts the first key press")
        suite.expect(!debounceUp(37, at: 10.01, config: debounceConfig),
               "debounce accepts key release")
        suite.expect(debounceDown(37, at: 10.03, config: debounceConfig),
               "debounce suppresses same-key bounce after release")
        suite.expect(!debounceDown(37, at: 10.06, config: debounceConfig),
               "debounce accepts same-key press after the release window")
        suite.expect(!debounceDown(37, at: 10.07, repeat: true, config: debounceConfig),
               "debounce leaves key auto-repeat alone")
        let fastConfig = KeyboardDebounceConfig(enabled: true,
                                                globalWindowMs: 10,
                                                keyWindows: [:])
        debounceState.reset()
        suite.expect(!debounceDown(0, at: 40.000, config: fastConfig),
               "debounce 10 ms accepts the first fast key press")
        _ = debounceUp(0, at: 40.004, config: fastConfig)
        suite.expect(debounceDown(0, at: 40.009, config: fastConfig),
               "debounce 10 ms suppresses same-key bounce inside the release window")
        suite.expect(!debounceDown(0, at: 40.014, config: fastConfig),
               "debounce 10 ms accepts the same key at the release boundary")
        let defaultDebounceConfig = KeyboardDebounceConfig(enabled: true,
                                                           globalWindowMs: Defaults.defaultKeyboardDebounceWindowMs,
                                                           keyWindows: [:])
        debounceState.reset()
        suite.expect(!debounceDown(0, at: 45.000, config: defaultDebounceConfig),
               "debounce 5 ms default accepts the first fast key press")
        _ = debounceUp(0, at: 45.001, config: defaultDebounceConfig)
        suite.expect(debounceDown(0, at: 45.005, config: defaultDebounceConfig),
               "debounce 5 ms default suppresses same-key bounce inside the release window")
        suite.expect(!debounceDown(0, at: 45.006, config: defaultDebounceConfig),
               "debounce 5 ms default accepts the same key at the release boundary")
        debounceState.reset()
        suite.expect(!debounceDown(37, at: 50.000, config: fastConfig),
               "debounce accepts normal phrase first letter")
        _ = debounceUp(37, at: 50.020, config: fastConfig)
        suite.expect(!debounceDown(14, at: 50.025, config: fastConfig),
               "debounce accepts normal phrase next letter")
        _ = debounceUp(14, at: 50.045, config: fastConfig)
        suite.expect(!debounceDown(17, at: 50.050, config: fastConfig),
               "debounce accepts normal phrase repeated-letter first press")
        _ = debounceUp(17, at: 50.070, config: fastConfig)
        suite.expect(!debounceDown(17, at: 50.110, config: fastConfig),
               "debounce accepts normal phrase repeated-letter second press")
        debounceState.reset()
        suite.expect(!debounceDown(0, at: 60.000, config: fastConfig),
               "debounce accepts the first key in an alternating pattern")
        _ = debounceUp(0, at: 60.004, config: fastConfig)
        suite.expect(!debounceDown(11, at: 60.006, config: fastConfig),
               "debounce accepts a different key inside another key's window")
        _ = debounceUp(11, at: 60.009, config: fastConfig)
        suite.expect(!debounceDown(0, at: 60.011, config: fastConfig),
               "debounce accepts a same-key press after another key was accepted")
        debounceState.reset()
        suite.expect(!debounceDown(0, at: 70.000, config: fastConfig),
               "debounce accepts the first key before duplicate down")
        suite.expect(debounceDown(0, at: 70.004, config: fastConfig),
               "debounce suppresses non-repeat duplicate down while the key is still down")
        suite.expect(!debounceUp(0, at: 70.020, config: fastConfig),
               "debounce still passes the release after a duplicate down")
        debounceState.reset()
        suite.expect(!debounceDown(0, at: 75.000, config: fastConfig),
               "debounce accepts a key before a missing release")
        suite.expect(!debounceDown(0, at: 75.020, config: fastConfig),
               "debounce accepts a same-key press after the window even if release was missed")
        debounceState.reset()
        suite.expect(!debounceDown(0, at: 80.000, config: fastConfig),
               "debounce accepts the first key before an out-of-order event")
        _ = debounceUp(0, at: 80.010, config: fastConfig)
        suite.expect(!debounceDown(0, at: 79.990, config: fastConfig),
               "debounce resets same-key state when event timestamps move backward")
        let perKeyConfig = KeyboardDebounceConfig(enabled: true,
                                                  globalWindowMs: 20,
                                                  keyWindows: [37: 100, 40: 0])
        debounceState.reset()
        _ = debounceDown(37, at: 20.00, config: perKeyConfig)
        _ = debounceUp(37, at: 20.01, config: perKeyConfig)
        suite.expect(debounceDown(37, at: 20.06, config: perKeyConfig),
               "debounce per-key window overrides the global window")
        _ = debounceDown(40, at: 30.00, config: perKeyConfig)
        _ = debounceUp(40, at: 30.005, config: perKeyConfig)
        suite.expect(!debounceDown(40, at: 30.006, config: perKeyConfig),
               "debounce per-key zero disables filtering for that key")
        let encodedKeyWindows = KeyboardDebounceConfig.encodeKeyWindows([37: 100, 40: 0])
        suite.expect(encodedKeyWindows == "37:100,40:0",
               "debounce key windows encode in stable key order")
        suite.expect(KeyboardDebounceConfig.decodeKeyWindows("37:100,bad,40:0,99:999")
               == [37: 100, 40: 0, 99: Defaults.defaultKeyboardDebounceWindowMs],
               "debounce key windows decode and sanitize stored values")
        let preciseConfig = KeyboardDebounceConfig(enabled: true,
                                                   globalWindowMs: 1,
                                                   keyWindows: [:])
        debounceState.reset()
        suite.expect(!debounceDown(0, at: 90.0000, config: preciseConfig),
               "a 1 ms keyboard window accepts the first press")
        _ = debounceUp(0, at: 90.0005, config: preciseConfig)
        suite.expect(debounceDown(0, at: 90.0010, config: preciseConfig),
               "a 1 ms keyboard window still filters a same-key bounce")
        suite.expect(!debounceDown(11, at: 90.0012, config: preciseConfig),
               "different keys pressed within 5 ms are never filtered")
        _ = debounceUp(11, at: 90.0014, config: preciseConfig)
        suite.expect(!debounceDown(0, at: 90.0015, config: preciseConfig),
               "the first key is accepted again after another key")

        // MARK: Mouse click debounce

        let clickConfig = MouseClickDebounceConfig(enabled: true, windowMilliseconds: 25)
        var clickState = MouseClickDebounceState()
        func click(_ button: Int64,
                   _ event: MouseClickDebounceEvent,
                   at milliseconds: UInt64,
                   config: MouseClickDebounceConfig = clickConfig) -> Bool {
            clickState.shouldSuppress(button: button,
                                      event: event,
                                      timestampNanoseconds: milliseconds * 1_000_000,
                                      config: config)
        }
        suite.expect(MouseClickDebounceInput.resolve(type: .leftMouseDown, buttonNumber: 0)
                == MouseClickDebounceInput(button: 0, event: .down)
                && MouseClickDebounceInput.resolve(type: .rightMouseUp, buttonNumber: 1)
                    == MouseClickDebounceInput(button: 1, event: .up)
                && MouseClickDebounceInput.resolve(type: .otherMouseDown, buttonNumber: 2)
                    == MouseClickDebounceInput(button: 2, event: .down)
                && MouseClickDebounceInput.resolve(type: .otherMouseDown, buttonNumber: 3) == nil
                && MouseClickDebounceInput.resolve(type: .leftMouseDragged, buttonNumber: 0)
                    == MouseClickDebounceInput(button: 0, event: .dragged)
                && MouseClickDebounceInput.resolve(type: .otherMouseDragged, buttonNumber: 3) == nil,
               "click debounce owns only primary, secondary and middle button events")
        suite.expect(!click(0, .down, at: 100)
                && !click(0, .dragged, at: 103)
                && !click(0, .up, at: 105),
               "a healthy click passes Down, drag and its final Up without delay")
        suite.expect(click(0, .down, at: 120)
                && click(0, .dragged, at: 122)
                && click(0, .up, at: 125),
               "a bounce click suppresses its Down, drag and matching Up")
        suite.expect(!click(0, .down, at: 130),
               "a click on the filter boundary starts a new accepted press")
        suite.expect(click(0, .down, at: 132),
               "a duplicate Down cannot create a second accepted press")
        suite.expect(!click(0, .up, at: 140),
               "the Up after a duplicate Down still releases the accepted press")
        suite.expect(!click(1, .down, at: 145) && !click(1, .up, at: 150),
               "each standard mouse button owns independent debounce state")
        suite.expect(click(1, .down, at: 160),
               "a second button click inside its own release window is filtered")
        clickState.reset()
        suite.expect(!click(1, .up, at: 165),
               "reset passes an unmatched final Up instead of leaving a button stuck")
        suite.expect(!click(0, .down, at: 200) && !click(0, .up, at: 205),
               "a fresh click is accepted before an out-of-order event")
        suite.expect(!click(0, .down, at: 190),
               "a timestamp moving backwards resets stale button ownership")
        let disabledClickConfig = MouseClickDebounceConfig(enabled: false, windowMilliseconds: 25)
        clickState.reset()
        suite.expect(!click(2, .down, at: 250)
                && !click(2, .up, at: 255)
                && click(2, .down, at: 265)
                && !click(2, .up, at: 266, config: disabledClickConfig),
               "turning the filter off preserves the final release of a suppressed click")
        clickState.reset()
        suite.expect(!click(0, .down, at: 300, config: disabledClickConfig)
                && !click(0, .up, at: 301, config: disabledClickConfig)
                && !click(0, .down, at: 302, config: disabledClickConfig),
               "disabled click debounce is a complete pass-through")
        let preciseClickConfig = MouseClickDebounceConfig(enabled: true, windowMilliseconds: 6)
        clickState.reset()
        suite.expect(!click(0, .down, at: 400, config: preciseClickConfig)
                && !click(0, .up, at: 401, config: preciseClickConfig)
                && !click(0, .down, at: 407, config: preciseClickConfig)
                && !click(0, .up, at: 408, config: preciseClickConfig)
                && click(0, .down, at: 413, config: preciseClickConfig),
               "a 6 ms window keeps a click 6 ms after release and filters one 5 ms after")
        suite.expect(Defaults.sanitizedMouseClickDebounceWindow(5) == 5
                && Defaults.sanitizedMouseClickDebounceWindow(6) == 6
                && Defaults.sanitizedMouseClickDebounceWindow(100) == 100
                && Defaults.sanitizedMouseClickDebounceWindow(4)
                    == Defaults.defaultMouseClickDebounceWindowMs
                && Defaults.sanitizedMouseClickDebounceWindow(0)
                    == Defaults.defaultMouseClickDebounceWindowMs,
               "mouse click debounce accepts any millisecond window from 5 to 100 ms")
        // The tap thread's bookkeeping: a stop keeps the record of a thread
        // still on its way out, so a start meanwhile cannot raise a second one
        // beside it; that start is owed until the thread is gone, and any
        // later lifecycle change makes the owed start stale.
        var tapLifecycle = MouseClickDebounceLifecycle()
        let firstStart = tapLifecycle.requestStart()
        tapLifecycle.requestStop()
        let startWhileStopping = tapLifecycle.requestStart()
        suite.expect(firstStart && !startWhileStopping && tapLifecycle.hasTapThread
                && tapLifecycle.restartsAfterStop,
               "click debounce stops without erasing the record of a tap thread still on its way out")
        let owedStart = tapLifecycle.threadFinished()
        let owedWasCurrent = tapLifecycle.isCurrent(owedStart.generation)
        tapLifecycle.requestStop()
        suite.expect(owedStart.restart && owedWasCurrent && !tapLifecycle.hasTapThread
                && !tapLifecycle.isCurrent(owedStart.generation),
               "a start owed to an exiting tap thread is current until a newer lifecycle change")
        suite.expect(MouseClickDebounceLifecycle.rearmsDisabledTap(enabled: true, sessionIsActive: true,
                                                                  accessibilityGranted: true, stopping: false)
                && !MouseClickDebounceLifecycle.rearmsDisabledTap(enabled: true, sessionIsActive: false,
                                                                   accessibilityGranted: true, stopping: false)
                && !MouseClickDebounceLifecycle.rearmsDisabledTap(enabled: true, sessionIsActive: true,
                                                                   accessibilityGranted: false, stopping: false)
                && !MouseClickDebounceLifecycle.rearmsDisabledTap(enabled: false, sessionIsActive: true,
                                                                   accessibilityGranted: true, stopping: false)
                && !MouseClickDebounceLifecycle.rearmsDisabledTap(enabled: true, sessionIsActive: true,
                                                                   accessibilityGranted: true, stopping: true),
               "a disabled click tap goes straight back on only while wanted, on screen, trusted and not stopping")

        // The production service over `ClickFilterRig`: its session, sleep
        // and wake, main queue and tap thread are the rig's, a started thread
        // runs when the test says, and no tap is ever created.
        do {
            let rig = ClickFilterRig()
            let service = MouseClickDebounceService(environment: rig.environment)
            let ms: UInt64 = 1_000_000
            let press = MouseClickDebounceInput(button: 0, event: .down)
            let release = MouseClickDebounceInput(button: 0, event: .up)
            service.syncWithPreferences()
            suite.expect(rig.threads.count == 1, "a wanted click filter starts the thread that serves its tap")

            let healthyClick = !service.suppresses(press, at: 100 * ms) && !service.suppresses(release, at: 105 * ms)
            let bounce = service.suppresses(press, at: 110 * ms) && service.suppresses(release, at: 112 * ms)
            rig.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
            suite.expect(healthyClick && bounce && !service.suppresses(press, at: 115 * ms),
                   "going to sleep forgets click ownership, so the first press after it is never taken for a bounce")
            _ = service.suppresses(release, at: 117 * ms)

            let bounceBeforeGap = service.suppresses(press, at: 120 * ms)
            _ = service.suppresses(release, at: 121 * ms)
            service.tapWasDisabled()
            suite.expect(bounceBeforeGap && !service.suppresses(press, at: 125 * ms)
                    && rig.mainQueue.count == 1,
                   "click debounce resets before any safe tap re-arm, and rebuilds a tap it cannot re-arm")
            _ = service.suppresses(release, at: 127 * ms)

            // Stopping forgets ownership too, and is a lifecycle change the
            // queued rebuild above must not outlive.
            service.suspend()
            suite.expect(!service.suppresses(press, at: 130 * ms),
                   "click debounce resets ownership when it stops")
            _ = service.suppresses(release, at: 131 * ms)
            rig.drainMain()
            rig.runThreads()
            suite.expect(rig.mainQueue.isEmpty && rig.threads.isEmpty,
                   "click debounce drops disabled-tap recovery after a newer lifecycle change")

            // A wake hands the tap back and builds it again: the old thread is
            // not replaced while it exits, and the start it is owed is made on
            // the main queue, through the preferences, once it is gone.
            service.syncWithPreferences()
            rig.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
            let oneThreadThroughWake = rig.threads.count == 1
            rig.runThreads()
            let restartQueued = rig.threads.isEmpty && rig.mainQueue.count == 1
            rig.drainMain()
            suite.expect(oneThreadThroughWake && restartQueued && rig.threads.count == 1,
                   "click debounce restarts a woken tap on main once its old thread is gone")
            rig.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
            rig.runThreads()
            let staleRestartQueued = rig.mainQueue.count == 1
            service.suspend()
            rig.drainMain()
            suite.expect(staleRestartQueued && rig.threads.isEmpty,
                   "click debounce serializes current restarts on main and drops stale ones")

            // A switched-away session hands the tap back; its return builds it again.
            service.syncWithPreferences()
            rig.sessionCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
            rig.runThreads()
            let handedBack = rig.threads.isEmpty && rig.mainQueue.isEmpty
            rig.sessionCenter.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
            suite.expect(handedBack && rig.threads.count == 1,
                   "click debounce follows the session: its tap goes while away and comes back on return")
            service.suspend()
            rig.runThreads()
            rig.drainMain()
        }

        // An absence with no behaviour to run: the service itself schedules
        // nothing, so a healthy click is never held back by a timer. Read here
        // until the source lints take it.
        let clickDebounceServiceSource = (try? String(
            contentsOfFile: "Sources/Vitruvian/Services/MouseClickDebounce/MouseClickDebounceService.swift",
            encoding: .utf8)) ?? ""
        let clickDebounceServiceCode = clickDebounceServiceSource.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(!clickDebounceServiceCode.isEmpty
                && !clickDebounceServiceCode.contains("Timer(")
                && !clickDebounceServiceCode.contains("asyncAfter"),
               "legacy click filtering adds no timer or delayed release to healthy clicks")

        suite.expect(ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: false, momentumPhase: 0, scrollPhase: 0, scrollCount: 0),
            secondsSinceLastGesturePhase: nil
        ), "classic mouse wheel ticks classify as a wheel")
        suite.expect(ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: true, momentumPhase: 0, scrollPhase: 0, scrollCount: 0),
            secondsSinceLastGesturePhase: nil
        ), "phase-less continuous wheel events classify as a wheel")
        suite.expect(!ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: true, momentumPhase: 0, scrollPhase: 2, scrollCount: 0),
            secondsSinceLastGesturePhase: nil
        ), "touch scrolling phases classify as touch")
        suite.expect(!ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: true, momentumPhase: 3, scrollPhase: 0, scrollCount: 1),
            secondsSinceLastGesturePhase: 0.1
        ), "momentum scrolling classifies as touch")
        suite.expect(!ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: true, momentumPhase: 0, scrollPhase: 0, scrollCount: 2),
            secondsSinceLastGesturePhase: 0.05
        ), "touch transition events (phaseless, counted, right after a phased event) classify as touch")
        suite.expect(ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: true, momentumPhase: 0, scrollPhase: 0, scrollCount: 2),
            secondsSinceLastGesturePhase: 5.0
        ), "counted wheel events long after any gesture classify as a wheel")
        suite.expect(ScrollWheelSupport.isMouseWheel(
            ScrollWheelEventTraits(isContinuous: true, momentumPhase: 0, scrollPhase: 0, scrollCount: 2),
            secondsSinceLastGesturePhase: nil
        ), "counted wheel events classify as a wheel when no gesture was ever seen")
        suite.expect(ScrollWheelSupport.inversionPlan(
            hasVerticalMovement: true, hasHorizontalMovement: false, shiftRedirectsVertical: false,
            invertVertical: true, invertHorizontal: false
        ) == ScrollWheelInversionPlan(vertical: true, horizontal: false),
        "vertical wheel movement follows only the vertical direction setting")
        suite.expect(ScrollWheelSupport.inversionPlan(
            hasVerticalMovement: false, hasHorizontalMovement: true, shiftRedirectsVertical: false,
            invertVertical: true, invertHorizontal: false
        ) == ScrollWheelInversionPlan(vertical: false, horizontal: false),
        "a horizontal wheel stays unchanged when only vertical inversion is on")
        suite.expect(ScrollWheelSupport.inversionPlan(
            hasVerticalMovement: true, hasHorizontalMovement: false, shiftRedirectsVertical: true,
            invertVertical: true, invertHorizontal: false
        ) == ScrollWheelInversionPlan(vertical: false, horizontal: false),
        "Shift-directed wheel movement follows the horizontal setting")
        suite.expect(ScrollWheelSupport.inversionPlan(
            hasVerticalMovement: true, hasHorizontalMovement: false, shiftRedirectsVertical: true,
            invertVertical: false, invertHorizontal: true
        ) == ScrollWheelInversionPlan(vertical: true, horizontal: false),
        "horizontal inversion flips the vertical source tick while Shift redirects it")
        suite.expect(ScrollWheelSupport.inversionPlan(
            hasVerticalMovement: true, hasHorizontalMovement: true, shiftRedirectsVertical: true,
            invertVertical: true, invertHorizontal: false
        ) == ScrollWheelInversionPlan(vertical: true, horizontal: false),
        "a genuine two-axis event keeps each axis independent even with Shift held")
        suite.expect(ScrollWheelSupport.inversionPlan(
            hasVerticalMovement: true, hasHorizontalMovement: false, shiftRedirectsVertical: false,
            invertVertical: false, invertHorizontal: true
        ) == ScrollWheelInversionPlan(vertical: false, horizontal: false),
        "a continuous wheel stays vertical because Shift does not redirect that event type")

        // A modifying tap belongs in the chain only while this login session is
        // the one on screen: fast user switching leaves the process running
        // behind another account, where the tap still takes every scroll event
        // and stalls it (issue #1075).
        suite.expect(SessionActivitySupport.tapShouldRun(featureWanted: true,
                                                   accessibilityGranted: true,
                                                   sessionIsActive: true),
               "a wanted modifying tap runs in the session on screen")
        suite.expect(!SessionActivitySupport.tapShouldRun(featureWanted: true,
                                                    accessibilityGranted: true,
                                                    sessionIsActive: false),
               "a wanted modifying tap is handed back while its session is switched away")
        suite.expect(!SessionActivitySupport.tapShouldRun(featureWanted: false,
                                                    accessibilityGranted: true,
                                                    sessionIsActive: true),
               "an unwanted modifying tap stays off in the session on screen")
        suite.expect(!SessionActivitySupport.tapShouldRun(featureWanted: true,
                                                    accessibilityGranted: false,
                                                    sessionIsActive: true),
               "a modifying tap needs Accessibility even in the session on screen")

        // Launching into a session that is already switched away is announced
        // before the tap owners exist to hear it, so the state is read rather
        // than assumed. Anything unreadable counts as on screen because a
        // wrong off state would never be corrected.
        let onConsoleKey = kCGSessionOnConsoleKey as String
        suite.expect(SessionActivitySupport.isOnConsole([onConsoleKey: true]),
               "a session dictionary saying it holds the console reads as on screen")
        suite.expect(!SessionActivitySupport.isOnConsole([onConsoleKey: false]),
               "a session dictionary saying it does not hold the console reads as off screen")
        suite.expect(SessionActivitySupport.isOnConsole([onConsoleKey: NSNumber(value: 1)]),
               "the console flag is read when it arrives as a number")
        suite.expect(SessionActivitySupport.isOnConsole(nil),
               "an unreadable session reads as on screen because a wrong off would never be corrected")
        suite.expect(SessionActivitySupport.isOnConsole([:]),
               "a session without the console flag reads as on screen because a wrong off would never be corrected")
        suite.expect(SessionActivitySupport.isOnConsole([onConsoleKey: "unexpected"]),
               "an unexpected console flag reads as on screen because a wrong off would never be corrected")

        let privateCenter = NotificationCenter()
        let activity = SessionActivity(center: privateCenter, initialIsActive: { true })
        var observedTransitions: [Bool] = []
        activity.onChange { observedTransitions.append($0) }
        suite.expect(activity.isActive, "session activity starts with the injected initial state")
        privateCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        suite.expect(!activity.isActive, "session activity transitions to inactive on resign")
        privateCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        privateCenter.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        suite.expect(activity.isActive, "session activity transitions to active on become-active")
        suite.expect(observedTransitions == [false, true],
               "the session activity handler records each state change and ignores duplicate notifications")

        suite.expect(MouseNavigationSupport.direction(
            forButtonNumber: MouseNavigationSupport.backButtonNumber) == .back,
               "the first standard mouse side button maps to Back")
        suite.expect(MouseNavigationSupport.direction(
            forButtonNumber: MouseNavigationSupport.forwardButtonNumber) == .forward,
               "the second standard mouse side button maps to Forward")
        suite.expect(MouseNavigationSupport.direction(forButtonNumber: 2) == nil,
               "the middle mouse button is never consumed as navigation")
        suite.expect(MouseNavigationSupport.direction(forButtonNumber: 9) == nil,
               "unrelated extra mouse buttons pass through")
        suite.expect(MouseNavigationSupport.commandCharacter(for: .back) == "[",
               "Back uses the standard Command left bracket menu command")
        suite.expect(MouseNavigationSupport.commandCharacter(for: .forward) == "]",
               "Forward uses the standard Command right bracket menu command")
        suite.expect(MouseNavigationSupport.sanitizedCommandCharacter("ö") == "ö",
               "a key equivalent the system moved the command to is taken as it is")
        suite.expect(MouseNavigationSupport.sanitizedCommandCharacter("[") == "[",
               "a keyboard that types brackets keeps the declared command")
        suite.expect(MouseNavigationSupport.sanitizedCommandCharacter("") == nil,
               "an empty key equivalent means no answer came back")
        suite.expect(MouseNavigationSupport.sanitizedCommandCharacter("ab") == nil,
               "a key equivalent is a single key, never a string of them")
        suite.expect(MouseNavigationSupport.sanitizedCommandCharacter(" ") == nil,
               "a blank key equivalent is not something to look for in a menu")
        suite.expect(MouseNavigationDirection.allCases.count == 2,
               "the side buttons navigate in exactly two directions")
        suite.expect(MouseNavigationSupport.sanitizedCommandCharacter("\t") == nil,
               "a control character is never a key to look for in a menu")
        // Menus spell their shortcut key in upper case whatever the app wrote,
        // and an upper case letter carries Shift on its own: both measured on
        // a real menu, and both decide whether the command is found at all.
        suite.expect(MouseNavigationSupport.matchesCommand(menuCharacter: "Ö", menuModifiers: 0,
                                                     character: "ö", modifiers: 0),
               "a command the system moved onto a letter is found despite the menu's upper case")
        suite.expect(MouseNavigationSupport.matchesCommand(menuCharacter: "[", menuModifiers: 0,
                                                     character: "[", modifiers: 0),
               "the declared bracket keeps being found where the keyboard types it")
        suite.expect(!MouseNavigationSupport.matchesCommand(menuCharacter: "Ö", menuModifiers: 1,
                                                      character: "ö", modifiers: 0),
               "the same key with another modifier is a different command")
        suite.expect(!MouseNavigationSupport.matchesCommand(menuCharacter: "Ä", menuModifiers: 0,
                                                      character: "ö", modifiers: 0),
               "a different key is never the command being looked for")
        suite.expect(!MouseNavigationSupport.matchesCommand(menuCharacter: nil, menuModifiers: 0,
                                                      character: "[", modifiers: 0),
               "a menu item with no shortcut at all is never a match")
        suite.expect(MouseNavigationSupport.menuModifiers(shift: false, option: false, control: false,
                                                    command: true, character: "ö") == 0,
               "Command with a lower case key is the plain shortcut a menu reports as zero")
        suite.expect(MouseNavigationSupport.menuModifiers(shift: false, option: false, control: false,
                                                    command: true, character: "Ö") == 1,
               "an upper case key carries Shift even when nobody asked for it")
        suite.expect(MouseNavigationSupport.menuModifiers(shift: true, option: false, control: false,
                                                    command: true, character: "f") == 1,
               "Shift asked for reads the same as Shift implied by the key")
        suite.expect(MouseNavigationSupport.menuModifiers(shift: false, option: true, control: true,
                                                    command: false, character: "[") == 14,
               "Option, Control and no Command each add their own bit")
        suite.expect(MouseNavigationSupport.shouldPassThrough(bundleIdentifier: "org.mozilla.firefox"),
               "the pass-through browser family keeps the raw side button events")
        suite.expect(MouseNavigationSupport.shouldPassThrough(
            bundleIdentifier: "org.mozilla.firefoxdeveloperedition"),
               "every channel of the browser family passes through via the prefix rule")
        let registeredWebHandlers: Set<String> = ["com.example.browser", "com.apple.WebViewer"]
        suite.expect(MouseNavigationSupport.nativeWebHandlers(
            urlHandlers: ["com.example.browser", "com.example.linkOnly"],
            documentHandlers: ["com.example.browser", "com.example.documentOnly"]
        ) == ["com.example.browser"],
               "only apps registered for web URLs and web documents are treated as browsers")
        suite.expect(MouseNavigationSupport.shouldRefreshWebHandlers(
            isApplicationActivation: false, activatedPID: nil, ownPID: 41),
               "launch, termination and mounted-volume changes refresh registered web handlers")
        suite.expect(MouseNavigationSupport.shouldRefreshWebHandlers(
            isApplicationActivation: true, activatedPID: 41, ownPID: 41),
               "activating Vitruvian refreshes registered web handlers")
        suite.expect(!MouseNavigationSupport.shouldRefreshWebHandlers(
            isApplicationActivation: true, activatedPID: 42, ownPID: 41),
               "activating another app does not repeat the handler lookup")
        suite.expect(!MouseNavigationSupport.shouldRefreshWebHandlers(
            isApplicationActivation: true, activatedPID: nil, ownPID: 41),
               "an activation without an app does not repeat the handler lookup")
        suite.expect(MouseNavigationSupport.shouldPassThrough(
            bundleIdentifier: "com.example.browser", webURLHandlers: registeredWebHandlers),
               "a third-party web handler keeps its native side button events")
        suite.expect(!MouseNavigationSupport.shouldPassThrough(
            bundleIdentifier: "com.apple.WebViewer", webURLHandlers: registeredWebHandlers),
               "a system web handler stays on the menu-command navigation path")
        suite.expect(MouseNavigationSupport.shouldPassThrough(
            bundleIdentifier: "com.parallels.desktop.console"),
               "virtual machines keep the raw side buttons for the guest system")
        suite.expect(!MouseNavigationSupport.shouldPassThrough(bundleIdentifier: "com.apple.finder"),
               "Finder stays on the menu-command navigation path")
        suite.expect(!MouseNavigationSupport.shouldPassThrough(bundleIdentifier: "org.mozillafoundation.x"),
               "prefix matching stops at the org.mozilla. namespace boundary")
        suite.expect(!MouseNavigationSupport.shouldPassThrough(bundleIdentifier: nil),
               "an unknown frontmost app keeps the navigation behavior")

        // MARK: Event timestamps at the HID tap (issue #1689)

        // Apple Silicon ticks mach absolute time every 125/3 ns. At the HID
        // stage hardware events carry those ticks, posted events nanoseconds.
        let appleSilicon = EventTimestamp.Timebase(numer: 125, denom: 3)
        let intel = EventTimestamp.Timebase(numer: 1, denom: 1)
        func ticks(atMilliseconds milliseconds: UInt64) -> UInt64 {
            milliseconds * 1_000_000 * 3 / 125
        }
        let nowTicks = ticks(atMilliseconds: 3_600_000)
        suite.expect(EventTimestamp.nanoseconds(raw: ticks(atMilliseconds: 3_599_998),
                                                nowTicks: nowTicks, timebase: appleSilicon)
                == 3_599_998 * 1_000_000,
               "a hardware event stamped in mach ticks reads as nanoseconds of uptime")
        suite.expect(EventTimestamp.nanoseconds(raw: 3_599_999 * 1_000_000,
                                                nowTicks: nowTicks, timebase: appleSilicon)
                == 3_599_999 * 1_000_000,
               "a posted event already stamped in nanoseconds keeps its value")
        suite.expect(EventTimestamp.nanoseconds(raw: 3_599_999 * 1_000_000,
                                                nowTicks: 3_600_000 * 1_000_000, timebase: intel)
                == 3_599_999 * 1_000_000,
               "a timebase of one nanosecond per tick passes timestamps through")
        suite.expect(EventTimestamp.nanoseconds(ticks: 3_253_805_719_584, timebase: appleSilicon)
                == 135_575_238_316_000
                && EventTimestamp.nanoseconds(ticks: 3_251_232_217_924, timebase: appleSilicon)
                == 135_468_009_080_166,
               "tick conversion rounds down like the timestamps a session tap reports")
        suite.expect(EventTimestamp.nanoseconds(ticks: .max, timebase: appleSilicon) == .max
                && EventTimestamp.nanoseconds(raw: .max, nowTicks: nowTicks,
                                              timebase: appleSilicon) == .max,
               "a nonsense timestamp saturates instead of trapping inside an event tap")
        let liveEvent = CGEvent(source: nil)
        let liveTicks = mach_absolute_time()
        liveEvent?.timestamp = liveTicks
        let liveFromTicks = liveEvent.map(EventTimestamp.nanoseconds(of:))
        let liveNanoseconds = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        liveEvent?.timestamp = liveNanoseconds
        let liveFromNanoseconds = liveEvent.map(EventTimestamp.nanoseconds(of:))
        suite.expect(liveFromTicks.map { $0 <= liveNanoseconds && liveNanoseconds - $0 < 1_000_000_000 }
                == true
                && liveFromNanoseconds == liveNanoseconds,
               "events stamped with this Mac's mach clock or uptime nanoseconds share one clock")

        // A 50 ms window measured in raw ticks would last about 2.1 s here.
        let hidDebounceConfig = KeyboardDebounceConfig(enabled: true,
                                                       globalWindowMs: 50,
                                                       keyWindows: [:])
        func hidKey(_ event: KeyboardDebounceState.EventKind, atMilliseconds milliseconds: UInt64) -> Bool {
            debounceState.shouldSuppress(
                keyCode: 0,
                isAutoRepeat: false,
                event: event,
                timestampNanoseconds: EventTimestamp.nanoseconds(
                    raw: ticks(atMilliseconds: milliseconds), nowTicks: nowTicks, timebase: appleSilicon),
                config: hidDebounceConfig)
        }
        debounceState.reset()
        suite.expect(!hidKey(.keyDown, atMilliseconds: 3_500_000)
                && !hidKey(.keyUp, atMilliseconds: 3_500_060)
                && hidKey(.keyDown, atMilliseconds: 3_500_080)
                && !hidKey(.keyDown, atMilliseconds: 3_500_120)
                && !hidKey(.keyUp, atMilliseconds: 3_500_180)
                && !hidKey(.keyDown, atMilliseconds: 3_500_240),
               "keyboard debounce on HID ticks drops a 20 ms bounce and accepts a press 60 ms after release")
        clickState.reset()
        func hidClick(_ event: MouseClickDebounceEvent, atMilliseconds milliseconds: UInt64) -> Bool {
            clickState.shouldSuppress(
                button: 0,
                event: event,
                timestampNanoseconds: EventTimestamp.nanoseconds(
                    raw: ticks(atMilliseconds: milliseconds), nowTicks: nowTicks, timebase: appleSilicon),
                config: clickConfig)
        }
        suite.expect(!hidClick(.down, atMilliseconds: 3_500_000)
                && !hidClick(.up, atMilliseconds: 3_500_080)
                && hidClick(.down, atMilliseconds: 3_500_090)
                && hidClick(.up, atMilliseconds: 3_500_095)
                && !hidClick(.down, atMilliseconds: 3_500_200)
                && !hidClick(.up, atMilliseconds: 3_500_280),
               "click debounce on HID ticks drops a 10 ms bounce and accepts a click 120 ms later")

        // Keys this app posts are recognised on the event itself. Quit
        // Protection confirms a press by posting a copy of the hardware key
        // down, which keeps both the hardware timestamp and its source process
        // id of 0. KeyboardDebounceTapTests feeds these through the tap handler.
        let ownProcessID = Int64(getpid())
        let hardwareKeyDown = CGEvent(keyboardEventSource: nil, virtualKey: 13, keyDown: true)
        hardwareKeyDown?.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        hardwareKeyDown?.timestamp = ticks(atMilliseconds: 3_599_990)
        let quitProtectionCopy = hardwareKeyDown?.copy()
        quitProtectionCopy?.setIntegerValueField(.eventSourceUserData, value: OwnKeyEvent.quitProtectionMarker)
        suite.expect(hardwareKeyDown.map(OwnKeyEvent.isPosted) == false,
               "a hardware key press still goes through key debounce")
        suite.expect(quitProtectionCopy?.getIntegerValueField(.eventSourceUnixProcessID) == 0
                && quitProtectionCopy?.timestamp == hardwareKeyDown?.timestamp
                && quitProtectionCopy.map(OwnKeyEvent.isPosted) == true,
               "the Quit Protection copy of a held key is recognised although it keeps the hardware pid and time")
        let snippetSource = CGEventSource(stateID: .hidSystemState)
        snippetSource?.userData = OwnKeyEvent.textSnippetMarker
        let snippetKey = CGEvent(keyboardEventSource: snippetSource, virtualKey: 49, keyDown: true)
        snippetKey?.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        suite.expect(snippetKey.map(OwnKeyEvent.isPosted) == true,
               "text a snippet retypes is recognised by its source marker alone")
        suite.expect(OwnKeyEvent.isPosted(sourceProcessID: ownProcessID, userData: 0, ownProcessID: ownProcessID)
                && !OwnKeyEvent.isPosted(sourceProcessID: 1, userData: 0, ownProcessID: ownProcessID)
                && !OwnKeyEvent.isPosted(sourceProcessID: 0, userData: 0x564F, ownProcessID: ownProcessID),
               "keys posted by this process skip debounce while other apps' posted keys do not")

        // MARK: Smooth scrolling

        suite.expect(SmoothScrollSupport.ticks(line: 1, fixedPoint: 1.0) == 1.0,
               "a classic wheel tick reads the same from either delta field")
        suite.expect(SmoothScrollSupport.ticks(line: 0, fixedPoint: 0.25) == 0.25,
               "high-resolution wheels keep their fractional ticks when the integer field truncates to zero")
        suite.expect(SmoothScrollSupport.ticks(line: -2, fixedPoint: 0) == -2,
               "a zero fixed-point field falls back to the integer line delta")

        // MARK: Linear scrolling

        suite.expect(ScrollWheelSupport.linesPerNotchRange.contains(ScrollWheelSupport.defaultLinesPerNotch)
                && ScrollWheelSupport.sanitizedLinesPerNotch(0) == ScrollWheelSupport.defaultLinesPerNotch
                && ScrollWheelSupport.sanitizedLinesPerNotch(-4)
                    == ScrollWheelSupport.linesPerNotchRange.lowerBound
                && ScrollWheelSupport.sanitizedLinesPerNotch(500)
                    == ScrollWheelSupport.linesPerNotchRange.upperBound,
               "lines per notch clamps to its range and an unset value means the default")
        suite.expect(ScrollWheelSupport.linearLines(ticks: 1, linesPerNotch: 3) == 3
                && ScrollWheelSupport.linearLines(ticks: 5, linesPerNotch: 3) == 3
                && ScrollWheelSupport.linearLines(ticks: -4, linesPerNotch: 3) == -3,
               "an accelerated wheel event is capped at one notch, whichever way it turns")
        suite.expect(ScrollWheelSupport.linearLines(ticks: 0.25, linesPerNotch: 4) == 1
                && ScrollWheelSupport.linearLines(ticks: 0, linesPerNotch: 3) == 0
                && ScrollWheelSupport.linearLines(ticks: .nan, linesPerNotch: 3) == 0,
               "a high-resolution fraction of a notch keeps its share and nothing invents movement")
        suite.expect(ScrollWheelSupport.continuousTicks(fixedPointDelta: 2, pointDelta: 30) == 3
                && ScrollWheelSupport.continuousTicks(fixedPointDelta: 2, pointDelta: 0) == 2,
               "a continuous wheel's notch count reads from the points apps see, then the fixed-point lines")
        let fastNotch = ScrollWheelSupport.linearDelta(
            ScrollWheelAxisDelta(line: 3, point: 30, fixedPoint: 3),
            isContinuous: false, linesPerNotch: 3, carry: 0)
        // A slow notch as a plain Bluetooth wheel sends it: macOS has shrunk it
        // to a tenth of a line and one point, while its line count reads one.
        let slowNotch = ScrollWheelSupport.linearDelta(
            ScrollWheelAxisDelta(line: -1, point: -1, fixedPoint: -0.1),
            isContinuous: false, linesPerNotch: 3, carry: 0)
        suite.expect(fastNotch.delta.line == 3 && fastNotch.carry == 0 && slowNotch.delta.line == -3,
               "a fast discrete notch and a slow one are written back as the same lines")
        suite.expect(ScrollWheelSupport.discreteTicks(line: 1, fixedPoint: 0.1, point: 1) == 1
                && ScrollWheelSupport.discreteTicks(line: -7, fixedPoint: -7.3, point: -73) == -1
                && ScrollWheelSupport.discreteTicks(line: 0, fixedPoint: 0.25, point: 2) == 0.25
                && ScrollWheelSupport.discreteTicks(line: 0, fixedPoint: 0, point: 10) == 1
                && ScrollWheelSupport.discreteTicks(line: 0, fixedPoint: .nan, point: 0) == 0,
               "a notch uses its line count, then its fraction, then points when the driver leaves both empty")
        let pointOnlyNotch = ScrollWheelSupport.linearDelta(
            ScrollWheelAxisDelta(line: 0, point: 10, fixedPoint: 0),
            isContinuous: false, linesPerNotch: 3, carry: 0)
        suite.expect(pointOnlyNotch.delta.line == 3 && pointOnlyNotch.carry == 0,
                     "a discrete point-only wheel event is not discarded")
        var fractionCarry = 0.0
        var fractionLines: Int64 = 0
        for _ in 0..<4 {
            let part = ScrollWheelSupport.linearDelta(
                ScrollWheelAxisDelta(line: 0, point: 0, fixedPoint: 0.25),
                isContinuous: false, linesPerNotch: 3, carry: fractionCarry)
            fractionCarry = part.carry
            fractionLines += part.delta.line
        }
        suite.expect(fractionLines == 3 && fractionCarry == 0,
               "four quarter-notch events from a high-resolution wheel add up to exactly one notch")
        let reversedNotch = ScrollWheelSupport.linearDelta(
            ScrollWheelAxisDelta(line: -1, point: 0, fixedPoint: -1),
            isContinuous: false, linesPerNotch: 3, carry: 0.75)
        suite.expect(reversedNotch.delta.line == -3 && reversedNotch.carry == 0,
               "a reversal drops the fraction the other direction left behind")
        let continuousNotch = ScrollWheelSupport.linearDelta(
            ScrollWheelAxisDelta(line: 0, point: 40, fixedPoint: 4),
            isContinuous: true, linesPerNotch: 3, carry: 0)
        suite.expect(continuousNotch.delta == ScrollWheelAxisDelta(line: 3, point: 30, fixedPoint: 3)
                && continuousNotch.carry == 0,
               "a continuous wheel event gets all three fields, measured in whole points")
        suite.expect(SmoothScrollSupport.linearContinuousDistance(
                fixedPointDelta: 4, pointDelta: 40,
                step: Double(SmoothScrollSupport.defaultStep), linesPerNotch: 3)
                == SmoothScrollSupport.continuousDistance(
                    fixedPointDelta: 3, pointDelta: 0, step: Double(SmoothScrollSupport.defaultStep)),
               "the glide measures a linear notch as its lines, not the driver's accelerated points")
        let uninstalledInverter = ScrollDirectionPreferences(isAvailable: { $0 != .scrollInverter },
                                                             boolFor: { _ in true },
                                                             stringFor: { _ in nil })
        suite.expect(!uninstalledInverter.invertVertical && !uninstalledInverter.invertHorizontal,
               "an uninstalled inverter flips nothing even with its switches left on")
        let linearName = "com.vitruviansoftware.vitruvian.tests.linear-lines.\(UUID().uuidString)"
        let linearDefaults = UserDefaults(suiteName: linearName)!
        defer { linearDefaults.removePersistentDomain(forName: linearName) }
        var exceptionChecks = 0
        let excepted = { () -> Bool in exceptionChecks += 1; return true }
        let allowed = { () -> Bool in exceptionChecks += 1; return false }
        linearDefaults.set(false, forKey: DefaultsKey.linearScrollEnabled)
        suite.expect(ScrollWheelSupport.linearLinesPerNotch(defaults: linearDefaults, isAvailable: true,
                                                           isExcepted: excepted) == nil
                        && exceptionChecks == 0,
               "linear scrolling switched off never asks the exception list")
        linearDefaults.set(true, forKey: DefaultsKey.linearScrollEnabled)
        linearDefaults.set(5, forKey: DefaultsKey.linearScrollLines)
        suite.expect(ScrollWheelSupport.linearLinesPerNotch(defaults: linearDefaults, isAvailable: false,
                                                           isExcepted: allowed) == nil,
               "an uninstalled feature caps nothing even with its switch left on")
        suite.expect(ScrollWheelSupport.linearLinesPerNotch(defaults: linearDefaults, isAvailable: true,
                                                           isExcepted: excepted) == nil,
               "an app on linear scrolling's own list is left out of the cap")
        suite.expect(ScrollWheelSupport.linearLinesPerNotch(defaults: linearDefaults, isAvailable: true,
                                                           isExcepted: allowed) == 5,
               "both wheel taps read the same lines per notch while linear scrolling applies")
        var smoothEngine = SmoothScrollSupport.Engine()
        smoothEngine.add(vertical: 40, horizontal: 0)
        suite.expect(smoothEngine.remainingVertical == 40,
               "one wheel tick queues one step of glide")
        smoothEngine.add(vertical: 80, horizontal: 20)
        suite.expect(smoothEngine.remainingVertical == 120 && smoothEngine.remainingHorizontal == 20,
               "same-direction input adds to what is left on each axis")
        smoothEngine.add(vertical: -40, horizontal: 0)
        suite.expect(smoothEngine.remainingVertical == -40 && smoothEngine.remainingHorizontal == 20,
               "reversing one axis abandons only that axis's old tail")
        let reversedFrame = smoothEngine.advance(
            elapsed: SmoothScrollSupport.frameInterval,
            response: SmoothScrollSupport.defaultResponse
        )
        suite.expect(reversedFrame.vertical < 0 && reversedFrame.horizontal > 0,
               "the first frame after a reversal moves in the new direction immediately")
        // Measured against a scroll view: a one-line tick with Shift moves the
        // content the same way a horizontal delta of the SAME sign does, so
        // the redirect must not flip the tick.
        suite.expect(SmoothScrollSupport.axes(vertical: 2, horizontal: 0, shiftPressed: true)
               == SmoothScrollSupport.Axes(vertical: 0, horizontal: 2),
               "Shift routes a vertical wheel tick sideways keeping its sign")
        suite.expect(SmoothScrollSupport.axes(vertical: -2, horizontal: 0, shiftPressed: true)
               == SmoothScrollSupport.Axes(vertical: 0, horizontal: -2),
               "the Shift redirect keeps the sign in the other direction too")
        suite.expect(SmoothScrollSupport.axes(vertical: 2, horizontal: 0, shiftPressed: false)
               == SmoothScrollSupport.Axes(vertical: 2, horizontal: 0),
               "a wheel tick without Shift keeps its vertical axis")
        suite.expect(SmoothScrollSupport.axes(vertical: 2, horizontal: -1, shiftPressed: true)
               == SmoothScrollSupport.Axes(vertical: 2, horizontal: -1),
               "Shift preserves a wheel event that already carries horizontal movement")
        let defaultFrameDelta = SmoothScrollSupport.frameDelta(
            remaining: 100,
            elapsed: SmoothScrollSupport.frameInterval,
            response: SmoothScrollSupport.defaultResponse
        )
        suite.expect(abs(defaultFrameDelta - 18) < 0.5,
               "the registered response keeps the former default's initial movement")
        suite.expect(SmoothScrollSupport.frameDelta(
            remaining: -100,
            elapsed: SmoothScrollSupport.frameInterval,
            response: SmoothScrollSupport.defaultResponse
        ) < 0,
               "negative glides emit negative frames")
        suite.expect(SmoothScrollSupport.frameDelta(
            remaining: 0.8,
            elapsed: SmoothScrollSupport.frameInterval,
            response: SmoothScrollSupport.defaultResponse
        ) == 0.8,
               "small leftovers flush in one final frame")
        suite.expect(SmoothScrollSupport.frameDelta(
            remaining: 3,
            elapsed: SmoothScrollSupport.frameInterval,
            response: SmoothScrollSupport.defaultResponse
        ) == 1
                && SmoothScrollSupport.frameDelta(
                    remaining: 3,
                    elapsed: SmoothScrollSupport.frameInterval / 2,
                    response: SmoothScrollSupport.defaultResponse
                ) == 0.5,
               "the time-based tail keeps moving at the former default cadence")
        suite.expect(SmoothScrollSupport.frameDelta(
            remaining: 100,
            elapsed: SmoothScrollSupport.frameInterval,
            response: SmoothScrollSupport.responseRange.upperBound
        ) > defaultFrameDelta
                && SmoothScrollSupport.frameDelta(
                    remaining: 100,
                    elapsed: SmoothScrollSupport.frameInterval,
                    response: SmoothScrollSupport.responseRange.lowerBound
                ) < defaultFrameDelta,
               "response changes how quickly the glide follows the wheel")
        suite.expect(SmoothScrollSupport.frameDelta(
            remaining: 100,
            elapsed: 1,
            response: SmoothScrollSupport.defaultResponse
        ) == SmoothScrollSupport.frameDelta(
            remaining: 100,
            elapsed: SmoothScrollSupport.maximumFrameInterval,
            response: SmoothScrollSupport.defaultResponse
        ),
               "a stalled run loop cannot dump the entire tail in one frame")
        suite.expect(SmoothScrollSupport.frameDelta(
            remaining: 0,
            elapsed: SmoothScrollSupport.frameInterval,
            response: SmoothScrollSupport.defaultResponse
        ) == 0,
               "no remaining distance emits nothing")
        suite.expect(SmoothScrollSupport.frameDelta(
            remaining: 40,
            elapsed: .nan,
            response: SmoothScrollSupport.defaultResponse
        ) == 0,
               "an invalid elapsed time cannot corrupt the glide")
        suite.expect(SmoothScrollSupport.sanitizedStep(0) == 40,
               "an unset step falls back to the default")
        suite.expect(SmoothScrollSupport.sanitizedStep(500) == 100,
               "the step clamps to its range")
        suite.expect(SmoothScrollSupport.sanitizedResponse(-1) == SmoothScrollSupport.responseRange.lowerBound
                && SmoothScrollSupport.sanitizedResponse(500) == SmoothScrollSupport.responseRange.upperBound,
               "response clamps damaged preferences to its range")
        suite.expect(SmoothScrollSupport.defaultCoast == 0,
               "coast ships off so every upgrade keeps the exact shipped curve")
        suite.expect(SmoothScrollSupport.sanitizedCoast(-1) == SmoothScrollSupport.coastRange.lowerBound
                && SmoothScrollSupport.sanitizedCoast(500) == SmoothScrollSupport.coastRange.upperBound,
               "coast clamps damaged preferences to its range")
        suite.expect(SmoothScrollSupport.frameDelta(
            remaining: 100,
            elapsed: SmoothScrollSupport.frameInterval,
            response: SmoothScrollSupport.defaultResponse,
            coast: SmoothScrollSupport.defaultCoast
        ) == defaultFrameDelta,
               "zero coast emits exactly the shipped first frame")
        // Coast must slow only the landing. A notch glided at zero coast has
        // to match the shipped engine frame for frame, and at full coast the
        // first frame must stay the shipped one while the glide lasts longer.
        func notchFrames(coast: Int?) -> [Double] {
            var engine = SmoothScrollSupport.Engine()
            engine.add(vertical: 40, horizontal: 0)
            var frames: [Double] = []
            while engine.isActive && frames.count < 600 {
                let frame = coast.map {
                    engine.advance(elapsed: SmoothScrollSupport.frameInterval,
                                   response: SmoothScrollSupport.defaultResponse, coast: $0)
                } ?? engine.advance(elapsed: SmoothScrollSupport.frameInterval,
                                    response: SmoothScrollSupport.defaultResponse)
                frames.append(frame.vertical)
            }
            return frames
        }
        let shippedNotch = notchFrames(coast: nil)
        let fullCoastNotch = notchFrames(coast: SmoothScrollSupport.coastRange.upperBound)
        suite.expect(notchFrames(coast: SmoothScrollSupport.defaultCoast) == shippedNotch,
               "zero coast glides a notch exactly like the shipped engine")
        suite.expect(fullCoastNotch.first == shippedNotch.first
                && fullCoastNotch.count >= shippedNotch.count * 3 / 2
                && abs(fullCoastNotch.reduce(0, +) - 40) < 0.000001,
               "full coast keeps the first frame and lands the same notch later")
        // The landing slows gradually rather than dropping to a flat crawl.
        suite.expect(zip(fullCoastNotch.dropLast(), fullCoastNotch.dropFirst().dropLast())
                .allSatisfy { $0 >= $1 - 0.000001 },
               "full coast never speeds back up before the glide lands")
        var reboundEngine = SmoothScrollSupport.Engine()
        reboundEngine.add(vertical: 40, horizontal: 0)
        for _ in 0..<10 {
            _ = reboundEngine.advance(elapsed: SmoothScrollSupport.frameInterval,
                                      response: SmoothScrollSupport.defaultResponse,
                                      coast: SmoothScrollSupport.coastRange.upperBound)
        }
        let remainingBeforeTick = reboundEngine.remainingVertical
        reboundEngine.add(vertical: 40, horizontal: 0)
        let freshTick = reboundEngine.advance(elapsed: SmoothScrollSupport.frameInterval,
                                              response: SmoothScrollSupport.defaultResponse,
                                              coast: SmoothScrollSupport.coastRange.upperBound)
        suite.expect(abs(freshTick.vertical - SmoothScrollSupport.frameDelta(
                    remaining: remainingBeforeTick + 40,
                    elapsed: SmoothScrollSupport.frameInterval,
                    response: SmoothScrollSupport.defaultResponse)) < 0.000001,
               "a tick during a coasting landing answers at the shipped pace again")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.smoothScrollEnabled] as? Bool == false,
               "smooth scrolling ships off by default")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.scrollInverterHorizontalEnabled] as? Bool == false,
               "horizontal scroll inversion ships off by default")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.scrollInverterHorizontalEnabled),
               "horizontal scroll direction follows settings backups")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.smoothScrollStep] as? Int == 40,
               "smooth scrolling step registers its default")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.smoothScrollResponse] as? Int
                == SmoothScrollSupport.defaultResponse
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.smoothScrollResponse),
               "smooth scrolling response registers its default and follows settings backups")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.smoothScrollCoast] as? Int
                == SmoothScrollSupport.defaultCoast
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.smoothScrollCoast),
               "smooth scrolling coast registers its default and follows settings backups")

        var sixtyHertzEngine = SmoothScrollSupport.Engine()
        var oneTwentyHertzEngine = SmoothScrollSupport.Engine()
        sixtyHertzEngine.add(vertical: 80, horizontal: -80)
        oneTwentyHertzEngine.add(vertical: 80, horizontal: -80)
        var sixtyHertzDistance = SmoothScrollSupport.Axes(vertical: 0, horizontal: 0)
        var oneTwentyHertzDistance = SmoothScrollSupport.Axes(vertical: 0, horizontal: 0)
        for _ in 0..<12 {
            let frame = sixtyHertzEngine.advance(
                elapsed: 1.0 / 60.0,
                response: SmoothScrollSupport.defaultResponse
            )
            sixtyHertzDistance = SmoothScrollSupport.Axes(
                vertical: sixtyHertzDistance.vertical + frame.vertical,
                horizontal: sixtyHertzDistance.horizontal + frame.horizontal
            )
        }
        for _ in 0..<24 {
            let frame = oneTwentyHertzEngine.advance(
                elapsed: 1.0 / 120.0,
                response: SmoothScrollSupport.defaultResponse
            )
            oneTwentyHertzDistance = SmoothScrollSupport.Axes(
                vertical: oneTwentyHertzDistance.vertical + frame.vertical,
                horizontal: oneTwentyHertzDistance.horizontal + frame.horizontal
            )
        }
        suite.expect(abs(sixtyHertzDistance.vertical - oneTwentyHertzDistance.vertical) < 0.000001
                && abs(sixtyHertzDistance.horizontal - oneTwentyHertzDistance.horizontal) < 0.000001
                && abs(sixtyHertzEngine.remainingVertical - oneTwentyHertzEngine.remainingVertical) < 0.000001
                && abs(sixtyHertzEngine.remainingHorizontal - oneTwentyHertzEngine.remainingHorizontal) < 0.000001,
               "equal elapsed time produces the same glide at 60 and 120 Hz")

        // Full coast still travels every pixel the wheel asked for, on either
        // cadence: the curve only stretches the response time.
        var coastSixtyHertzEngine = SmoothScrollSupport.Engine()
        var coastOneTwentyHertzEngine = SmoothScrollSupport.Engine()
        coastSixtyHertzEngine.add(vertical: 80, horizontal: -80)
        coastOneTwentyHertzEngine.add(vertical: 80, horizontal: -80)
        var coastSixtyHertzTravelled = SmoothScrollSupport.Axes(vertical: 0, horizontal: 0)
        var coastOneTwentyHertzTravelled = SmoothScrollSupport.Axes(vertical: 0, horizontal: 0)
        for _ in 0..<600 {
            let frame = coastSixtyHertzEngine.advance(
                elapsed: 1.0 / 60.0,
                response: SmoothScrollSupport.defaultResponse,
                coast: SmoothScrollSupport.coastRange.upperBound
            )
            coastSixtyHertzTravelled = SmoothScrollSupport.Axes(
                vertical: coastSixtyHertzTravelled.vertical + frame.vertical,
                horizontal: coastSixtyHertzTravelled.horizontal + frame.horizontal
            )
            if frame.finished { break }
        }
        for _ in 0..<1200 {
            let frame = coastOneTwentyHertzEngine.advance(
                elapsed: 1.0 / 120.0,
                response: SmoothScrollSupport.defaultResponse,
                coast: SmoothScrollSupport.coastRange.upperBound
            )
            coastOneTwentyHertzTravelled = SmoothScrollSupport.Axes(
                vertical: coastOneTwentyHertzTravelled.vertical + frame.vertical,
                horizontal: coastOneTwentyHertzTravelled.horizontal + frame.horizontal
            )
            if frame.finished { break }
        }
        suite.expect(!coastSixtyHertzEngine.isActive && !coastOneTwentyHertzEngine.isActive
                && abs(coastSixtyHertzTravelled.vertical - 80) < 0.001
                && abs(coastSixtyHertzTravelled.horizontal + 80) < 0.001
                && abs(coastOneTwentyHertzTravelled.vertical - 80) < 0.001
                && abs(coastOneTwentyHertzTravelled.horizontal + 80) < 0.001,
               "a full-coast glide lands on the full wheel distance at 60 and 120 Hz")

        suite.expect(FocusFollowsMouseSupport.sanitizedDelay(0)
                == FocusFollowsMouseSupport.delayRange.lowerBound
                && FocusFollowsMouseSupport.sanitizedDelay(2_000)
                == FocusFollowsMouseSupport.delayRange.upperBound,
               "focus follows mouse clamps a damaged delay preference")
        suite.expect(!FocusFollowsMouseSupport.shouldActivate(
            targetWindowID: 42, focusedWindowID: nil, targetAppIsFrontmost: true),
               "hover leaves the active app alone when its focused window cannot be read")
        suite.expect(!FocusFollowsMouseSupport.shouldActivate(
            targetWindowID: 42, focusedWindowID: 42, targetAppIsFrontmost: true),
               "hover does not reactivate the app's focused window")
        suite.expect(FocusFollowsMouseSupport.shouldActivate(
            targetWindowID: 42, focusedWindowID: 43, targetAppIsFrontmost: true),
               "hover can still switch to another window within the active app")
        for focusedWindowID: CGWindowID? in [nil, 42, 43] {
            suite.expect(FocusFollowsMouseSupport.shouldActivate(
                targetWindowID: 42, focusedWindowID: focusedWindowID, targetAppIsFrontmost: false),
                   "hover can activate a background app regardless of its last focused window")
        }
        var focusFollowsMouseState = FocusFollowsMouseState()
        suite.expect(!focusFollowsMouseState.hasPendingEvaluation,
               "focus follows mouse starts without work to poll")
        focusFollowsMouseState.recordMovement(to: CGPoint(x: 40, y: 70), at: 10)
        suite.expect(focusFollowsMouseState.nextEvaluation(at: 10.20, delayMilliseconds: 250) == nil
                && focusFollowsMouseState.hasPendingEvaluation,
               "focus follows mouse waits for the pointer to settle")
        let settledFocus = focusFollowsMouseState.nextEvaluation(at: 10.25, delayMilliseconds: 250)
        suite.expect(settledFocus?.point == CGPoint(x: 40, y: 70)
                && settledFocus.map(focusFollowsMouseState.isCurrent) == true,
               "focus follows mouse evaluates the settled pointer once")
        suite.expect(focusFollowsMouseState.nextEvaluation(at: 11, delayMilliseconds: 250) == nil,
               "focus follows mouse does not refocus without new movement")
        suite.expect(!focusFollowsMouseState.hasPendingEvaluation,
               "a consumed focus evaluation leaves no work to poll while its lookup finishes")
        focusFollowsMouseState.recordMovement(to: CGPoint(x: 90, y: 20), at: 12)
        suite.expect(settledFocus.map(focusFollowsMouseState.isCurrent) == false
                && focusFollowsMouseState.hasPendingEvaluation,
               "a stale window lookup cannot focus after the pointer moves")
        focusFollowsMouseState.recordMovement(to: CGPoint(x: 100, y: 20), at: 12.2)
        suite.expect(focusFollowsMouseState.nextEvaluation(at: 12.25, delayMilliseconds: 250) == nil
                && focusFollowsMouseState.hasPendingEvaluation,
               "new movement restarts the settling delay without dropping pending work")
        suite.expect(focusFollowsMouseState.nextEvaluation(at: 13, delayMilliseconds: 250)?.point
                == CGPoint(x: 100, y: 20),
               "a deferred focus check can consume the settled target after input protections lift")
        focusFollowsMouseState.recordMovement(to: CGPoint(x: 110, y: 20), at: 14)
        focusFollowsMouseState.reset()
        suite.expect(focusFollowsMouseState.point == nil && !focusFollowsMouseState.hasPendingEvaluation,
               "space and wake resets discard the old pointer target")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.focusFollowsMouseEnabled] as? Bool == false
                && Defaults.registeredDefaults[DefaultsKey.focusFollowsMouseDelay] as? Int
                    == FocusFollowsMouseSupport.defaultDelayMilliseconds,
               "focus follows mouse ships off with a safe delay")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.focusFollowsMouseDelay),
               "focus follows mouse preferences follow settings backups")
        // Hover follows drags as well as plain moves, and holds off while any
        // button or modifier is down, the middle and side buttons included.
        let hoverMovement = FocusFollowsMouseService.movementEvents
        suite.expect(hoverMovement.contains(.mouseMoved) && hoverMovement.contains(.leftMouseDragged)
                && hoverMovement.contains(.rightMouseDragged) && hoverMovement.contains(.otherMouseDragged)
                && FocusFollowsMouseService.nothingHeld(pressedMouseButtons: 0, modifierFlags: [])
                && FocusFollowsMouseService.nothingHeld(pressedMouseButtons: 0, modifierFlags: .capsLock)
                && !FocusFollowsMouseService.nothingHeld(pressedMouseButtons: 1 << 2, modifierFlags: [])
                && !FocusFollowsMouseService.nothingHeld(pressedMouseButtons: 1 << 4, modifierFlags: [])
                && !FocusFollowsMouseService.nothingHeld(pressedMouseButtons: 0, modifierFlags: .option),
               "focus follows mouse tracks drags and checks every held mouse button")
        let hoverPoint = CGPoint(x: 40, y: 60)
        suite.expect(FocusFollowsMouseSupport.leavesAlone(hoverPoint, excludes: { scope, point in
                    scope == .focusFollowsMouse && point == hoverPoint
                })
                && !FocusFollowsMouseSupport.leavesAlone(hoverPoint, excludes: { scope, _ in
                    scope != .focusFollowsMouse
                }),
               "focus follows mouse leaves selected apps alone before querying Accessibility")
        // Whether hover may own its monitor and timer at all is the answer
        // SessionActivitySupport.tapShouldRun gives the taps, pinned above.
        suite.expect(FocusFollowsMouseSupport.hitTestProcess(4242, ownProcessID: 7) == 4242
                && FocusFollowsMouseSupport.hitTestProcess(7, ownProcessID: 7) == nil
                && FocusFollowsMouseSupport.hitTestProcess(0, ownProcessID: 7) == nil
                && FocusFollowsMouseSupport.hitTestProcess(-1, ownProcessID: 7) == nil,
               "focus follows mouse cannot re-enter its own Accessibility tree through a global hit test")
        suite.expect(FocusFollowsMouseSupport.handsToActivator(targetWindowID: 5, focusedWindowID: 4,
                                                               targetAppIsFrontmost: false,
                                                               isParkedOnHiddenSpace: { _ in false })
                && !FocusFollowsMouseSupport.handsToActivator(targetWindowID: 5, focusedWindowID: 4,
                                                              targetAppIsFrontmost: false,
                                                              isParkedOnHiddenSpace: { $0 == 5 }),
               "focus follows mouse never hands a window on a hidden Space to the activator, which would travel")

        // A wheel that reports continuously already measures in points, and
        // that field is the one to trust; the line field only fills in for a
        // movement too small to register as a whole point.
        suite.expect(ScrollWheelSupport.pointsPerLine == 10,
               "one scroll line spans ten points")
        suite.expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 4.0, pointDelta: 40, step: 40) == 40,
               "the default step travels the same distance the event asked for")
        suite.expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 4.0, pointDelta: 12, step: 40) == 12,
               "the point field wins, so no assumption about points per line is made")
        suite.expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 4.0, pointDelta: 40, step: 20) == 20,
               "a shorter step halves the distance of a continuous wheel")
        suite.expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 4.0, pointDelta: 40, step: 100) == 100,
               "a longer step stretches the distance of a continuous wheel")
        suite.expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: -0.5, pointDelta: -5, step: 40) == -5,
               "direction survives the conversion")
        suite.expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 0.35, pointDelta: 0, step: 40) == 3.5,
               "a movement below one whole point still glides")
        suite.expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 0, pointDelta: 12, step: 40) == 12,
               "a driver that fills in only whole points still glides")
        suite.expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: 0, pointDelta: 0, step: 40) == 0,
               "an empty event asks for no distance")
        suite.expect(SmoothScrollSupport.continuousDistance(
            fixedPointDelta: .nan, pointDelta: 0, step: 40) == 0,
               "a nonsense delta asks for no distance")

        // The continuous path scales by the step itself and then hands the
        // budget a step of one. Scaling in both places would square the
        // setting, so pin that the budget equals the distance.
        for continuousStep in [20.0, 40.0, 100.0] {
            let distance = SmoothScrollSupport.continuousDistance(
                fixedPointDelta: 4.0, pointDelta: 40, step: continuousStep)
            var engine = SmoothScrollSupport.Engine()
            engine.add(vertical: distance, horizontal: 0)
            suite.expect(engine.remainingVertical == distance,
                   "the step scales a continuous wheel exactly once")
        }

        var exactDistanceEngine = SmoothScrollSupport.Engine()
        exactDistanceEngine.add(vertical: 40.4, horizontal: -17.3)
        var exactVertical = 0.0
        var exactHorizontal = 0.0
        for _ in 0..<600 {
            if !exactDistanceEngine.isActive { break }
            let frame = exactDistanceEngine.advance(
                elapsed: 1.0 / 120.0,
                response: SmoothScrollSupport.responseRange.lowerBound
            )
            exactVertical += frame.vertical
            exactHorizontal += frame.horizontal
        }
        suite.expect(!exactDistanceEngine.isActive
                && abs(exactVertical - 40.4) < 0.000001
                && abs(exactHorizontal + 17.3) < 0.000001,
               "the engine spends the exact distance on both axes")

        // Fractions are carried instead of rounded away, so the glide
        // delivers the whole distance it was given.
        var carriedTotal: Double = 0
        var carry: Double = 0
        for _ in 0..<10 {
            let frame = SmoothScrollSupport.wholePixels(0.6, carry: carry)
            carriedTotal += frame.pixels
            carry = frame.carry
        }
        suite.expect(abs(carriedTotal + carry - 6) < 0.000001,
               "ten six-tenths of a pixel are all still there, posted or waiting")
        suite.expect(carriedTotal >= 5,
               "never more than one pixel is left waiting")
        suite.expect(SmoothScrollSupport.wholePixels(0.4, carry: 0).pixels == 0,
               "a fraction alone posts nothing yet")
        suite.expect(SmoothScrollSupport.wholePixels(0.4, carry: 0).carry == 0.4,
               "the fraction is kept for the next frame")
        suite.expect(SmoothScrollSupport.wholePixels(-1.5, carry: 0).pixels == -1,
               "negative frames keep their whole pixels")
        suite.expect(SmoothScrollSupport.wholePixels(-1.5, carry: 0).carry == -0.5,
               "negative frames carry their fraction")
        suite.expect(SmoothScrollSupport.wholePixels(.infinity, carry: 0).pixels == 0,
               "an impossible frame posts nothing")
        suite.expect(SmoothScrollSupport.finalPixels(0.4, carry: 0.3) == 1,
               "the landing frame spends the leftover instead of dropping it")
        suite.expect(SmoothScrollSupport.finalPixels(-0.4, carry: -0.3) == -1,
               "the landing frame spends it in either direction")
        suite.expect(SmoothScrollSupport.finalPixels(0.2, carry: 0) == 0,
               "a landing frame with almost nothing left posts nothing")
        suite.expect(SmoothScrollSupport.finalPixels(.infinity, carry: 0) == 0,
               "an impossible landing frame posts nothing")
        suite.expect(SmoothScrollSupport.carry(0.6, continuing: 5) == 0.6,
               "leftovers survive while the direction holds")
        suite.expect(SmoothScrollSupport.carry(0.6, continuing: -5) == 0,
               "reversing direction drops the leftovers")
        suite.expect(SmoothScrollSupport.carry(0.6, continuing: 0) == 0.6,
               "an empty event leaves the leftovers alone")
        var roundedEngine = SmoothScrollSupport.Engine()
        roundedEngine.add(vertical: 40.4, horizontal: 0)
        var roundedCarry = 0.0
        var roundedDistance = 0.0
        for _ in 0..<600 {
            if !roundedEngine.isActive { break }
            let frame = roundedEngine.advance(
                elapsed: 1.0 / 120.0,
                response: SmoothScrollSupport.defaultResponse
            )
            if frame.finished {
                roundedDistance += SmoothScrollSupport.finalPixels(frame.vertical, carry: roundedCarry)
                roundedCarry = 0
            } else {
                let output = SmoothScrollSupport.wholePixels(frame.vertical, carry: roundedCarry)
                roundedDistance += output.pixels
                roundedCarry = output.carry
            }
        }
        suite.expect(abs(roundedDistance - 40.4) <= 0.5,
               "posted whole-point frames land within half a point of the requested distance")

        // MARK: Window move and resize gestures

        suite.expect(WindowGestureSupport.modifiers(from: nil) == [.control, .command],
               "window gestures fall back to control-command")
        suite.expect(WindowGestureSupport.modifiers(from: "option+shift") == [.option],
               "shift stays reserved for trackpad resizing")
        suite.expect(WindowGestureSupport.modifiers(from: "shift") == [.control, .command],
               "shift alone never takes over ordinary system dragging")
        suite.expect(WindowGestureSupport.modifiers(from: "invalid") == [.control, .command],
               "corrupt window gesture modifiers fall back safely")
        suite.expect(WindowGestureSupport.storageValue(for: [.command, .control]) == "control+command",
               "window gesture modifiers serialize in stable order")
        suite.expect(WindowGestureSupport.modifiersMatch(eventFlags: [.maskControl, .maskCommand],
                                                   expected: [.control, .command]),
               "window gestures match their exact modifier chord")
        suite.expect(!WindowGestureSupport.modifiersMatch(eventFlags: [.maskControl, .maskCommand, .maskShift],
                                                    expected: [.control, .command]),
               "the resize chord does not trigger window movement")
        let resizeModifiers = WindowGestureSupport.resizeModifiers(from: [.control, .command])
        suite.expect(resizeModifiers == [.control, .shift, .command],
               "trackpad resizing adds shift to the chosen move chord")
        suite.expect(WindowGestureSupport.modifiersMatch(eventFlags: [.maskControl, .maskCommand, .maskShift],
                                                   expected: resizeModifiers),
               "trackpad resizing matches its exact primary-drag chord")
        suite.expect(!WindowGestureSupport.modifiersMatch(eventFlags: [.maskControl, .maskCommand, .maskShift, .maskAlternate],
                                                    expected: resizeModifiers),
               "unexpected extra modifiers do not trigger trackpad resizing")
        suite.expect(WindowGestureSupport.movedOrigin(from: CGPoint(x: 100, y: 80),
                                                pointerStart: CGPoint(x: 300, y: 200),
                                                pointerNow: CGPoint(x: 345, y: 175))
               == CGPoint(x: 145, y: 55),
               "window movement follows the full pointer delta")
        let gestureFrame = CGRect(x: 100, y: 80, width: 600, height: 420)
        suite.expect(WindowGestureSupport.resizeEdges(at: CGPoint(x: 110, y: 90), in: gestureFrame)
               == [.left, .top],
               "a top-left press resizes from both matching edges")
        suite.expect(WindowGestureSupport.resizeEdges(at: CGPoint(x: 400, y: 90), in: gestureFrame)
               == [.top],
               "a top-center press resizes only the top edge")
        suite.expect(!WindowGestureSupport.resizeEdges(at: CGPoint(x: 400, y: 290), in: gestureFrame).isEmpty,
               "the center region always chooses a usable nearest edge")
        suite.expect(WindowGestureSupport.resizedFrame(from: gestureFrame,
                                                 pointerStart: CGPoint(x: 110, y: 90),
                                                 pointerNow: CGPoint(x: 160, y: 120),
                                                 edges: [.left, .top])
               == CGRect(x: 150, y: 110, width: 550, height: 390),
               "top-left resizing keeps the opposite corner anchored")
        suite.expect(WindowGestureSupport.resizedFrame(from: gestureFrame,
                                                 pointerStart: CGPoint(x: 690, y: 490),
                                                 pointerNow: CGPoint(x: 760, y: 540),
                                                 edges: [.right, .bottom])
               == CGRect(x: 100, y: 80, width: 670, height: 470),
               "bottom-right resizing grows in both axes")
        suite.expect(WindowGestureSupport.resizedFrame(from: gestureFrame,
                                                 pointerStart: CGPoint(x: 100, y: 80),
                                                 pointerNow: CGPoint(x: 900, y: 700),
                                                 edges: [.left, .top])
               == CGRect(x: 580, y: 420, width: 120, height: 80),
               "gesture minimum size keeps the far corner fixed")
        suite.expect(WindowGestureSupport.anchoredOrigin(original: gestureFrame,
                                                   requestedOrigin: CGPoint(x: 580, y: 420),
                                                   acceptedSize: CGSize(width: 260, height: 180),
                                                   edges: [.left, .top])
               == CGPoint(x: 440, y: 320),
               "an app-specific minimum size keeps the opposite corner anchored")
        suite.expect(WindowGestureSupport.anchoredOrigin(original: gestureFrame,
                                                   requestedOrigin: gestureFrame.origin,
                                                   acceptedSize: CGSize(width: 760, height: 540),
                                                   edges: [.right, .bottom])
               == gestureFrame.origin,
               "right and bottom resizing keep the original window origin")
        suite.expect(WindowGestureSupport.anchoredOriginIfNeeded(original: gestureFrame,
                                                           requestedOrigin: gestureFrame.origin,
                                                           acceptedSize: CGSize(width: 760, height: 540),
                                                           edges: [.right, .bottom]) == nil,
               "right and bottom resizing never adds a redundant position mutation")
        suite.expect(WindowGestureSupport.anchoredOriginIfNeeded(original: gestureFrame,
                                                           requestedOrigin: CGPoint(x: 580, y: 420),
                                                           acceptedSize: CGSize(width: 260, height: 180),
                                                           edges: [.left, .top])
               == CGPoint(x: 440, y: 320),
               "left and top resizing reanchors only after the accepted size is known")

        // MARK: Click versus drag custody (issue #321)

        let slopOrigin = CGPoint(x: 100, y: 80)
        suite.expect(!WindowGestureSupport.exceedsDragSlop(from: slopOrigin, to: slopOrigin),
               "a press that never moves stays a click")
        suite.expect(!WindowGestureSupport.exceedsDragSlop(from: slopOrigin, to: CGPoint(x: 106, y: 80)),
               "movement exactly at the slop still counts as a click")
        suite.expect(WindowGestureSupport.exceedsDragSlop(from: slopOrigin, to: CGPoint(x: 106.1, y: 80)),
               "movement past the slop becomes a window gesture")
        suite.expect(!WindowGestureSupport.exceedsDragSlop(from: slopOrigin, to: CGPoint(x: 94, y: 80)),
               "the slop is symmetric in both directions")
        suite.expect(WindowGestureSupport.exceedsDragSlop(from: slopOrigin, to: CGPoint(x: 105, y: 85)),
               "diagonal movement is measured as a distance, not per axis")
        suite.expect(!WindowGestureSupport.exceedsDragSlop(from: slopOrigin, to: CGPoint(x: 95, y: 77)),
               "hand jitter under the slop keeps the click")

        suite.expect(WindowGestureSupport.decide(state: .idle,
                                           input: .buttonDown(sameButton: false, chordMatched: false)) == .passThrough,
               "a press without the chord is never touched")
        suite.expect(WindowGestureSupport.decide(state: .idle,
                                           input: .buttonDown(sameButton: false, chordMatched: true)) == .arm,
               "a press with the chord is only held, not taken")
        suite.expect(WindowGestureSupport.decide(state: .idle,
                                           input: .buttonDragged(tracked: false, pastSlop: true)) == .passThrough,
               "movement with nothing held is never touched")
        suite.expect(WindowGestureSupport.decide(state: .idle, input: .buttonUp(tracked: false)) == .passThrough,
               "a release with nothing held is never touched")
        suite.expect(WindowGestureSupport.decide(state: .idle,
                                           input: .tapDisabled(buttonStillDown: false)) == .passThrough,
               "an idle tap has nothing to give back when it is switched off")

        suite.expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDragged(tracked: true, pastSlop: false)) == .hold,
               "jitter under the slop keeps the press held")
        suite.expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDragged(tracked: true, pastSlop: true)) == .promote,
               "movement past the slop turns the held press into a gesture")
        suite.expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDragged(tracked: false, pastSlop: true)) == .flushThenPass,
               "movement of another button gives the held press back")
        suite.expect(WindowGestureSupport.decide(state: .pending, input: .buttonUp(tracked: true)) == .replayThenPass,
               "a release without movement gives the whole click back to the app")
        suite.expect(WindowGestureSupport.decide(state: .pending, input: .buttonUp(tracked: false)) == .flushThenPass,
               "a release of another button gives the held press back")
        suite.expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDown(sameButton: true, chordMatched: true)) == .restartAsIdle,
               "the same button pressing again replaces a held press whose release went missing")
        suite.expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDown(sameButton: true, chordMatched: false)) == .restartAsIdle,
               "a stale held press is cleared even when the new press has no chord")
        suite.expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDown(sameButton: false, chordMatched: true)) == .flushThenRestart,
               "a second button gives the first press back instead of eating it")
        suite.expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDown(sameButton: false, chordMatched: false)) == .flushThenRestart,
               "a second button without the chord also gives the first press back")
        suite.expect(WindowGestureSupport.decide(state: .pending, input: .otherEvent) == .flushThenPass,
               "anything unexpected gives the held press back")
        suite.expect(WindowGestureSupport.decide(state: .pending,
                                           input: .tapDisabled(buttonStillDown: true)) == .flushThenPass,
               "a tap switched off while the button is still down gives the click back")
        suite.expect(WindowGestureSupport.decide(state: .pending,
                                           input: .tapDisabled(buttonStillDown: false)) == .dropState,
               "a press whose release already reached the app is never handed back pressed")
        suite.expect(WindowGestureSupport.decide(state: .pending, input: .accessibilityLost) == .flushThenPass,
               "losing Accessibility mid press still gives the click back")

        suite.expect(WindowGestureSupport.decide(state: .active,
                                           input: .buttonDragged(tracked: true, pastSlop: false)) == .applyMove,
               "a running gesture keeps following the pointer")
        suite.expect(WindowGestureSupport.decide(state: .active, input: .buttonUp(tracked: true)) == .applyFinish,
               "releasing ends a running gesture")
        suite.expect(WindowGestureSupport.decide(state: .active, input: .buttonUp(tracked: false)) == .passThrough,
               "another button is never swallowed by a running gesture")
        suite.expect(WindowGestureSupport.decide(state: .active, input: .otherEvent) == .passThrough,
               "a running gesture never swallows unrelated events")
        suite.expect(WindowGestureSupport.decide(state: .active,
                                           input: .tapDisabled(buttonStillDown: true)) == .dropState,
               "a gesture that already took the press has nothing to give back")
        suite.expect(WindowGestureSupport.decide(state: .active, input: .accessibilityLost) == .dropState,
               "losing Accessibility mid gesture drops it without a phantom click")

        // No path may invent a release, and every held press is given back
        // exactly once: only these decisions replay, and none of them can be
        // reached twice for the same press.
        let allInputs: [WindowGestureInput] = [
            .buttonDown(sameButton: true, chordMatched: true),
            .buttonDown(sameButton: true, chordMatched: false),
            .buttonDown(sameButton: false, chordMatched: true),
            .buttonDown(sameButton: false, chordMatched: false),
            .buttonDragged(tracked: true, pastSlop: true),
            .buttonDragged(tracked: true, pastSlop: false),
            .buttonDragged(tracked: false, pastSlop: true),
            .buttonDragged(tracked: false, pastSlop: false),
            .buttonUp(tracked: true), .buttonUp(tracked: false),
            .otherEvent, .tapDisabled(buttonStillDown: true),
            .tapDisabled(buttonStillDown: false), .accessibilityLost,
        ]
        var pendingExits = 0
        var pendingReplays = 0
        for input in allInputs {
            let decision = WindowGestureSupport.decide(state: .pending, input: input)
            if decision != .hold {
                pendingExits += 1
                if decision == .replayThenPass || decision == .flushThenPass
                    || decision == .flushThenRestart { pendingReplays += 1 }
            }
            let replaying: [WindowGestureDecision] = [.replayThenPass, .flushThenPass, .flushThenRestart]
            suite.expect(!replaying.contains(WindowGestureSupport.decide(state: .idle, input: input)),
                   "nothing is ever replayed while no press is held")
            suite.expect(!replaying.contains(WindowGestureSupport.decide(state: .active, input: input)),
                   "a press already spent on a gesture is never replayed")
        }
        suite.expect(pendingExits == 13 && pendingReplays == 9,
               "every way out of a held press either promotes it, replaces it or gives it back")

        // MARK: Directional pointer layout

        let dirOrigin = CGPoint(x: 200, y: 200)
        suite.expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: dirOrigin) == nil,
               "stationary pointer does not trigger directional layout")
        suite.expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 220, y: 200)) == nil,
               "pointer movement below activation distance produces no action")
        suite.expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 240, y: 200)) == .rightHalf,
               "moving right triggers right half")
        suite.expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 350, y: 200)) == .rightHalf,
               "fast long flick right triggers right half reliably")
        suite.expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 160, y: 200)) == .leftHalf,
               "moving left triggers left half")
        suite.expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 200, y: 240)) == .topHalf,
               "moving up triggers top half")
        suite.expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 200, y: 350)) == .topHalf,
               "fast long flick up triggers top half reliably")
        suite.expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 200, y: 160)) == .bottomHalf,
               "moving down triggers bottom half")
        suite.expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 200, y: 50)) == .bottomHalf,
               "fast long flick down triggers bottom half without accidental minimize")
        suite.expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 240, y: 240)) == .topRight,
               "moving up-right triggers top right")
        suite.expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 160, y: 240)) == .topLeft,
               "moving up-left triggers top left")
        suite.expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 240, y: 160)) == .bottomRight,
               "moving down-right triggers bottom right")
        suite.expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 160, y: 160)) == .bottomLeft,
               "moving down-left triggers bottom left")
        suite.expect(!WindowDirectionalGestureSupport.shouldApplyKeyboardManualOverride(isAutorepeat: true),
               "auto-repeat never forces a manual maximize/minimize override")
        suite.expect(WindowDirectionalGestureSupport.shouldApplyKeyboardManualOverride(isAutorepeat: false),
               "a distinct Space, Return, or Up tap still maximizes while the ring is open")

        // MARK: Middle click tap (issue #161)

        suite.expect(Defaults.sanitizedMiddleClickTapFingers(3) == 3
                   && Defaults.sanitizedMiddleClickTapFingers(4) == 4,
               "tap to middle click accepts three or four fingers")
        suite.expect(Defaults.sanitizedMiddleClickTapFingers(0) == 0
                   && Defaults.sanitizedMiddleClickTapFingers(2) == 0
                   && Defaults.sanitizedMiddleClickTapFingers(-1) == 0,
               "any other tap finger count means off")
        suite.expect(MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                exceededFingerCount: false, buttonPressedDuring: false,
                                                positionUnavailable: false, systemDragGestureEnabled: false,
                                                tapFingers: 3),
               "a quick still three-finger tap fires")
        suite.expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                 exceededFingerCount: false, buttonPressedDuring: false,
                                                 positionUnavailable: false, systemDragGestureEnabled: false,
                                                 tapFingers: 3, secondsSinceLastKeyDown: 0.1),
               "stray trackpad contact while typing never fires a middle click")
        suite.expect(MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                exceededFingerCount: false, buttonPressedDuring: false,
                                                positionUnavailable: false, systemDragGestureEnabled: false,
                                                tapFingers: 3, secondsSinceLastKeyDown: 1.0),
               "tap to middle click resumes after keyboard activity settles")
        suite.expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.2, maxSpreadChange: 0.01,
                                                 exceededFingerCount: false, buttonPressedDuring: false,
                                                 positionUnavailable: false, systemDragGestureEnabled: false,
                                                 tapFingers: 3),
               "a swipe never fires the tap")
        suite.expect(!MiddleClickSupport.tapShouldFire(duration: 0.8, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                 exceededFingerCount: false, buttonPressedDuring: false,
                                                 positionUnavailable: false, systemDragGestureEnabled: false,
                                                 tapFingers: 3),
               "resting fingers never fire the tap")
        suite.expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                 exceededFingerCount: false, buttonPressedDuring: true,
                                                 positionUnavailable: false, systemDragGestureEnabled: false,
                                                 tapFingers: 3),
               "a physical click during the touch belongs to the press path")
        suite.expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                 exceededFingerCount: true, buttonPressedDuring: false,
                                                 positionUnavailable: false, systemDragGestureEnabled: false,
                                                 tapFingers: 3),
               "extra fingers cancel the tap")
        suite.expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                 exceededFingerCount: false, buttonPressedDuring: false,
                                                 positionUnavailable: true, systemDragGestureEnabled: false,
                                                 tapFingers: 3),
               "unreadable touch positions stand the tap down")
        suite.expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                 exceededFingerCount: false, buttonPressedDuring: false,
                                                 positionUnavailable: false, systemDragGestureEnabled: true,
                                                 tapFingers: 3),
               "three-finger tap stands down while the system drag gesture owns it")
        suite.expect(MiddleClickSupport.radialMenuTapFingers(radialMenuWantsTap: true, middleClickTapFingers: 0) == 4
                && MiddleClickSupport.radialMenuTapFingers(radialMenuWantsTap: true, middleClickTapFingers: 3) == 4
                && MiddleClickSupport.radialMenuTapFingers(radialMenuWantsTap: false, middleClickTapFingers: 0) == 0,
               "a radial menu wheel that asks for the tap gets four fingers, beside a three-finger middle click")
        suite.expect(MiddleClickSupport.radialMenuTapFingers(radialMenuWantsTap: true, middleClickTapFingers: 4) == 0,
               "a middle click already on four fingers keeps them")
        let tapWheel = RadialMenuProfile(name: "Tap", trackpadTap: true)
        let legacyWheel = Data(#"[{"name":"Old","shortcut":"","mouseButton":"off","items":[]}]"#.utf8)
        suite.expect(RadialMenuSupport.decodeProfiles(RadialMenuSupport.encodeProfiles([tapWheel])).first?.trackpadTap == true
                && RadialMenuSupport.decodeProfiles(legacyWheel).first?.trackpadTap == false,
               "the trackpad tap is saved with its wheel and off for wheels saved before it")
        suite.expect(RadialMenuSupport.needsAccessibility([tapWheel]),
               "a wheel opened by the trackpad tap needs the event tap's Accessibility permission")
        let shortcutTapWheel = RadialMenuProfile(
            name: "Tap", shortcut: "cmd+shift+space",
            items: [RadialMenuItem(kind: .app, payload: "/System/Library/CoreServices/Finder.app")],
            trackpadTap: true)
        let copiedWheel = shortcutTapWheel.duplicate(named: "Tap 2")
        suite.expect(copiedWheel.id != shortcutTapWheel.id && copiedWheel.name == "Tap 2"
                && copiedWheel.items == shortcutTapWheel.items
                && copiedWheel.shortcut.isEmpty && !copiedWheel.trackpadTap,
               "a duplicated wheel keeps the actions but leaves the shortcut and the trackpad tap to the original")
        suite.expect(MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.01,
                                                exceededFingerCount: false, buttonPressedDuring: false,
                                                positionUnavailable: false, systemDragGestureEnabled: true,
                                                tapFingers: 4),
               "four-finger tap stays available alongside the system drag gesture")
        suite.expect(!MiddleClickSupport.tapShouldFire(duration: 0.15, maxMovement: 0.01, maxSpreadChange: 0.2,
                                                 exceededFingerCount: false, buttonPressedDuring: false,
                                                 positionUnavailable: false, systemDragGestureEnabled: false,
                                                 tapFingers: 4),
               "a pinch or spread never fires the tap even with a still centroid")

        // MARK: Cut and paste move progress (issue #168)

        suite.expect(!CutPasteProgressSupport.isCrossVolume(source: NSNumber(value: 1),
                                                      destination: NSNumber(value: 1)),
               "a move inside one volume never shows progress")
        suite.expect(CutPasteProgressSupport.isCrossVolume(source: NSNumber(value: 1),
                                                     destination: NSNumber(value: 2)),
               "a move between volumes is recognized as a real copy")
        suite.expect(!CutPasteProgressSupport.isCrossVolume(source: nil,
                                                      destination: NSNumber(value: 2)),
               "unknown volume identities fall back to the silent same-volume path")
        suite.expect(CutPasteProgressSupport.fraction(finishedBytes: 0, currentBytes: 0, totalBytes: 0) == nil,
               "an unknown byte total yields an indeterminate bar, not a broken fraction")
        suite.expect(CutPasteProgressSupport.fraction(finishedBytes: 50, currentBytes: 25, totalBytes: 150) == 0.5,
               "progress combines finished files with the growing destination")
        suite.expect(CutPasteProgressSupport.fraction(finishedBytes: 100, currentBytes: 200, totalBytes: 150) == 1.0,
               "progress clamps at full when the destination briefly over-reports")
        suite.expect(CutPasteProgressSupport.fraction(finishedBytes: -5, currentBytes: -5, totalBytes: 100) == 0.0,
               "negative byte readings clamp to an empty bar")
        suite.expect(CutPasteProgressSupport.displayPosition(completed: 1, total: 5) == 2,
               "the counter shows the item currently moving, one past the finished count")
        suite.expect(CutPasteProgressSupport.displayPosition(completed: 5, total: 5) == 5,
               "the counter never runs past the batch size")

        suite.expect(CutPastePrivilegeSupport.needsPrivileges(
            NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)),
               "a destination the account cannot write is worth handing to Finder")
        suite.expect(CutPastePrivilegeSupport.needsPrivileges(
            NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))),
               "a POSIX permission refusal reaches the same retry")
        suite.expect(CutPastePrivilegeSupport.needsPrivileges(
            NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError,
                    userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain,
                                                             code: Int(EPERM))])),
               "the refusal is found in the underlying error too")
        suite.expect(!CutPastePrivilegeSupport.needsPrivileges(
            NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)),
               "a full disk fails the same way for Finder, so it never asks")
        suite.expect(!CutPastePrivilegeSupport.needsPrivileges(
            NSError(domain: NSCocoaErrorDomain, code: NSFileWriteVolumeReadOnlyError)),
               "a read-only volume never raises a dialog it cannot use")
        suite.expect(!CutPastePrivilegeSupport.needsPrivileges(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotWriteToFile)),
               "an unrelated error domain stays a plain failure")
        do {
            let fm = FileManager.default
            let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let destination = root.appendingPathComponent("destination")
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: root) }
            let first = root.appendingPathComponent("first")
            let second = root.appendingPathComponent("second")
            try Data([1]).write(to: first)
            try Data([2]).write(to: second)
            let canceled = CutPastePrivilegeSupport.reconcile(
                [first, second], into: destination, canceled: true, fm: fm)
            suite.expect(canceled.moved == 0 && canceled.failed == 0
                && canceled.stillCut == [first, second],
                   "canceling before a move keeps the whole selection")
            try fm.moveItem(at: first, to: destination.appendingPathComponent("first"))
            let partial = CutPastePrivilegeSupport.reconcile(
                [first, second], into: destination, canceled: true, fm: fm)
            suite.expect(partial.moved == 1 && partial.failed == 0 && partial.stillCut == [second],
                   "canceling after a partial move retains only the unmoved file")
            let failure = CutPastePrivilegeSupport.reconcile(
                [first, second], into: destination, canceled: false, fm: fm)
            suite.expect(failure.moved == 1 && failure.failed == 1 && failure.stillCut.isEmpty,
                   "a partial failure reports the files that actually landed")
            try fm.removeItem(at: second)
            let vanished = CutPastePrivilegeSupport.reconcile(
                [second], into: destination, canceled: false, fm: fm)
            suite.expect(vanished.moved == 0 && vanished.failed == 1,
                   "a missing source without a destination is not a successful move")
            try Data([2]).write(to: destination.appendingPathComponent("second"))
            let success = CutPastePrivilegeSupport.reconcile(
                [first, second], into: destination, canceled: false, fm: fm)
            suite.expect(success.moved == 2 && success.failed == 0 && success.stillCut.isEmpty,
                   "a completed batch clears every cut mark")
        } catch {
            suite.expect(false, "protected-folder move fixtures: \(error)")
        }

        // MARK: Paste copied image as file (issue #429)

        suite.expect(FinderPasteImageSupport.preferredImageType(in: ["public.utf8-plain-text"]) == nil,
               "text never replaces Finder's normal paste")
        suite.expect(FinderPasteImageSupport.preferredImageType(in: ["public.tiff", "public.png"])
                == "public.png",
               "PNG wins when the pasteboard offers several image representations")
        suite.expect(FinderPasteImageSupport.preferredImageType(
            in: ["public.file-url", "public.png"]
        ) == nil, "a copied image file stays a normal Finder file paste")
        suite.expect(FinderPasteImageSupport.preferredImageType(in: ["public.jpeg"])
                == "public.jpeg",
               "a non-PNG image representation can be converted")
        suite.expect(FinderPasteImageSupport.fileName(
            for: Date(timeIntervalSince1970: 0),
            timeZone: TimeZone(secondsFromGMT: 0)!
        ) == "Pasted_Image_19700101_000000.png",
               "pasted images receive the stable timestamped PNG name")

        // MARK: Mouse button shortcuts (issue #282)

        suite.expect(Defaults.registeredDefaults[DefaultsKey.mouseButtonShortcutsEnabled] as? Bool == false,
               "mouse button shortcuts ship off by default")
        suite.expect((Defaults.registeredDefaults[DefaultsKey.mouseButtonShortcuts] as? [String: String])?.isEmpty == true,
               "the mapping dictionary registers empty so it travels with backups")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.panelControlMouseButtonShortcuts] as? Bool == true,
               "the mouse button shortcuts panel row ships visible like its siblings")
        suite.expect(AppFeature.mouseButtonShortcuts.enabledKeys == [DefaultsKey.mouseButtonShortcutsEnabled,
                                                              DefaultsKey.mouseSpacesGestureEnabled]
                && AppFeature.mouseButtonShortcuts.permissions == [.accessibility]
                && AppFeature.mouseButtonShortcuts.group == .mouseKeyboard,
               "the hub knows the feature's switch, permission and group")

        suite.expect(MouseButtonShortcutSupport.canMap(3) && MouseButtonShortcutSupport.canMap(31)
                && MouseButtonShortcutSupport.canMap(MouseButtonShortcutSupport.sideWheelLeftInput)
                && MouseButtonShortcutSupport.canMap(MouseButtonShortcutSupport.sideWheelRightInput)
                && !MouseButtonShortcutSupport.canMap(0) && !MouseButtonShortcutSupport.canMap(1)
                && !MouseButtonShortcutSupport.canMap(2) && !MouseButtonShortcutSupport.canMap(32)
                && !MouseButtonShortcutSupport.canMap(-3),
               "only extra buttons and both side-wheel directions can carry a shortcut")
        suite.expect(MouseButtonShortcutSupport.backButtonNumber == MouseNavigationSupport.backButtonNumber
                && MouseButtonShortcutSupport.forwardButtonNumber == MouseNavigationSupport.forwardButtonNumber,
               "button shortcuts and mouse navigation agree on which button is which")
        let pressedExtraButtons = (1 << 3) | (1 << 31)
        suite.expect(MouseButtonShortcutSupport.isPressed(3, pressedButtons: pressedExtraButtons)
                && MouseButtonShortcutSupport.isPressed(31, pressedButtons: pressedExtraButtons)
                && !MouseButtonShortcutSupport.isPressed(4, pressedButtons: pressedExtraButtons)
                && !MouseButtonShortcutSupport.isPressed(-1, pressedButtons: pressedExtraButtons)
                && !MouseButtonShortcutSupport.isPressed(Int64(Int.bitWidth),
                                                         pressedButtons: pressedExtraButtons),
               "tap recovery keeps custody only for extra buttons still physically held")

        let buttonCombo = GlobalShortcut(keyCode: 0, modifiers: [.command, .shift])
        let decodedButtons = MouseButtonShortcutSupport.decode([
            "3": buttonCombo.storageValue,
            "4": "command:11",
            String(MouseButtonShortcutSupport.sideWheelLeftInput): "command:11",
            "2": "command:11",
            "40": "command:11",
            "junk": "command:11",
            "5": "garbage",
            "6": ":48",
        ])
        suite.expect(decodedButtons.count == 3 && decodedButtons[3] == buttonCombo && decodedButtons[4] != nil
                && decodedButtons[MouseButtonShortcutSupport.sideWheelLeftInput] != nil,
               "decoding keeps valid button and side-wheel mappings and drops everything else")
        suite.expect(MouseButtonShortcutSupport.decode(MouseButtonShortcutSupport.encode(decodedButtons))
                == decodedButtons,
               "mappings round-trip through their stored form")
        suite.expect(MouseButtonShortcutSupport.decode(nil).isEmpty,
               "no stored mappings decode to none")
        suite.expect(MouseButtonShortcutSupport.sortedButtons([
            5: buttonCombo,
            MouseButtonShortcutSupport.sideWheelRightInput: buttonCombo,
            MouseButtonShortcutSupport.sideWheelLeftInput: buttonCombo,
            3: buttonCombo,
            12: buttonCombo,
        ]) == [MouseButtonShortcutSupport.sideWheelLeftInput,
               MouseButtonShortcutSupport.sideWheelRightInput, 3, 5, 12],
               "settings rows keep side-wheel directions together before numbered buttons")
        suite.expect(MouseButtonShortcutSupport.sideWheelInput(isContinuous: false,
                                                         vertical: (0, 0, 0),
                                                         horizontal: (1, 0, 0))
                == MouseButtonShortcutSupport.sideWheelLeftInput
                && MouseButtonShortcutSupport.sideWheelInput(isContinuous: false,
                                                             vertical: (0, 0, 0),
                                                             horizontal: (0, -0.25, 0))
                == MouseButtonShortcutSupport.sideWheelRightInput
                && MouseButtonShortcutSupport.sideWheelInput(isContinuous: true,
                                                             vertical: (0, 0, 0),
                                                             horizontal: (0, 0, 3))
                == MouseButtonShortcutSupport.sideWheelLeftInput
                && MouseButtonShortcutSupport.sideWheelInput(isContinuous: true,
                                                             vertical: (0, 0, 0),
                                                             horizontal: (0, 0, 0)) == nil,
               "side-wheel directions follow AppKit's horizontal sign for discrete and continuous mice")
        suite.expect(MouseButtonShortcutSupport.sideWheelInput(isContinuous: false,
                                                         vertical: (2, 2, 20),
                                                         horizontal: (1, 1, 10)) == nil
                && MouseButtonShortcutSupport.sideWheelInput(isContinuous: false,
                                                             vertical: (1, 1, 10),
                                                             horizontal: (1, 1, 10)) == nil
                && MouseButtonShortcutSupport.sideWheelInput(isContinuous: true,
                                                             vertical: (0, 0, 3),
                                                             horizontal: (0, 0, 4))
                == MouseButtonShortcutSupport.sideWheelLeftInput,
               "vertical and diagonal scrolling cannot leak into a side-wheel shortcut")

        var sideWheelGesture = MouseButtonShortcutSupport.SideWheelGestureGate()
        let wheelLeft = MouseButtonShortcutSupport.sideWheelLeftInput
        let wheelRight = MouseButtonShortcutSupport.sideWheelRightInput
        suite.expect(sideWheelGesture.shouldFire(wheelLeft, at: 0)
                && !sideWheelGesture.shouldFire(wheelLeft, at: 10_000_000)
                && sideWheelGesture.shouldFire(wheelRight, at: 20_000_000)
                && !sideWheelGesture.shouldFire(wheelLeft, at: 30_000_000)
                && !sideWheelGesture.shouldFire(wheelRight, at: 40_000_000),
               "one wheel burst fires each deliberate direction exactly once")
        suite.expect(sideWheelGesture.shouldFire(wheelLeft, at: 300_000_001),
               "a quiet gap arms the next side-wheel gesture")
        sideWheelGesture.reset()
        suite.expect(sideWheelGesture.shouldFire(wheelRight, at: 1),
               "stopping the tap clears the side-wheel gesture state")

        suite.expect(MouseButtonShortcutSupport.firesShortcut(for: 3, isAvailable: true, isEnabled: true,
                                                        mappings: [3: buttonCombo],
                                                        claimedByWheel: { _ in false }) == buttonCombo,
               "an available, enabled mapping fires its combination")
        suite.expect(MouseButtonShortcutSupport.firesShortcut(for: 3, isAvailable: true, isEnabled: true,
                                                        mappings: [3: buttonCombo],
                                                        claimedByWheel: { $0 == 3 }) == nil,
               "the radial menu's summoner button never doubles as a shortcut")
        suite.expect(MouseButtonShortcutSupport.firesShortcut(for: 3, isAvailable: false, isEnabled: true,
                                                        mappings: [3: buttonCombo],
                                                        claimedByWheel: { _ in false }) == nil
                && MouseButtonShortcutSupport.firesShortcut(for: 3, isAvailable: true, isEnabled: false,
                                                            mappings: [3: buttonCombo],
                                                            claimedByWheel: { _ in false }) == nil
                && MouseButtonShortcutSupport.firesShortcut(for: 4, isAvailable: true, isEnabled: true,
                                                            mappings: [3: buttonCombo],
                                                            claimedByWheel: { _ in false }) == nil,
               "hub-off, switch-off and unmapped buttons all stay inert")
        suite.expect(!MouseButtonShortcutSupport.claimsButton(3) && !MouseButtonShortcutSupport.claimsButton(4),
               "with the feature off no button is claimed away from navigation")
        suite.expect(MouseButtonShortcutSupport.buttonName(for: 3, strings: .enUS)
                == MouseButtonFeatureStrings.enUS.backButtonName
                && MouseButtonShortcutSupport.buttonName(for: 4, strings: .enUS)
                == MouseButtonFeatureStrings.enUS.forwardButtonName
                && MouseButtonShortcutSupport.buttonName(
                    for: MouseButtonShortcutSupport.sideWheelLeftInput, strings: .enUS) == "Side wheel left"
                && MouseButtonShortcutSupport.buttonName(
                    for: MouseButtonShortcutSupport.sideWheelRightInput, strings: .enUS) == "Side wheel right"
                && MouseButtonShortcutSupport.buttonName(for: 5, strings: .enUS) == "Button 6",
               "buttons and side-wheel directions have clear names")

        // MARK: Spaces and Mission Control drag (issue #1012)

        let spaceStep = MouseSpacesGestureSupport.spaceStep
        let overviewStep = MouseSpacesGestureSupport.overviewStep
        let spaceCooldown = MouseSpacesGestureSupport.spaceRepeatCooldown

        var dragRight = MouseSpacesGestureSupport.Tracker(origin: .zero)
        suite.expect(dragRight.advance(to: CGPoint(x: spaceStep - 1, y: 0), now: 0) == nil
                && dragRight.advance(to: CGPoint(x: spaceStep, y: 0), now: 0.1) == .spaceRight,
               "one whole step to the right moves one Space to the right, and not a pixel sooner")
        var dragLeft = MouseSpacesGestureSupport.Tracker(origin: .zero)
        suite.expect(dragLeft.advance(to: CGPoint(x: -spaceStep, y: 0), now: 0) == .spaceLeft,
               "the same step to the left moves the other way")
        var dragUp = MouseSpacesGestureSupport.Tracker(origin: .zero)
        suite.expect(dragUp.advance(to: CGPoint(x: 0, y: -overviewStep + 1), now: 0) == nil
                && dragUp.advance(to: CGPoint(x: 0, y: -overviewStep), now: 0.1) == .missionControl,
               "dragging up opens Mission Control once the vertical step is behind it")
        var dragDown = MouseSpacesGestureSupport.Tracker(origin: .zero)
        suite.expect(dragDown.advance(to: CGPoint(x: 0, y: overviewStep), now: 0) == .appExpose,
               "dragging down opens App Exposé, the way the trackpad swipe does")

        var nudge = MouseSpacesGestureSupport.Tracker(origin: .zero)
        let nudged = (1...12).compactMap {
            nudge.advance(to: CGPoint(x: CGFloat($0) * 5, y: CGFloat($0) * 3), now: Double($0) * 0.02)
        }
        suite.expect(nudged.isEmpty && !nudge.didFire && nudge.axis == nil,
               "a drag that stays under both steps does nothing, so the press is still a plain click")

        var wildPointer = MouseSpacesGestureSupport.Tracker(origin: .zero)
        suite.expect(wildPointer.advance(to: CGPoint(x: CGFloat.nan, y: CGFloat.infinity), now: 0) == nil
                && !wildPointer.didFire,
               "a pointer position that is not a number moves nothing")

        var heldDrag = MouseSpacesGestureSupport.Tracker(origin: .zero)
        suite.expect(heldDrag.advance(to: CGPoint(x: spaceStep, y: 0), now: 0) == .spaceRight
                && heldDrag.advance(to: CGPoint(x: spaceStep * 2, y: 0), now: spaceCooldown / 2) == nil
                && heldDrag.advance(to: CGPoint(x: spaceStep * 2 + 1, y: 0),
                                    now: spaceCooldown + 0.01) == .spaceRight,
               "a held drag repeats one Space per step, never faster than the slide animation")

        var flick = MouseSpacesGestureSupport.Tracker(origin: .zero)
        _ = flick.advance(to: CGPoint(x: spaceStep, y: 0), now: 0)
        _ = flick.advance(to: CGPoint(x: spaceStep * 6, y: 0), now: spaceCooldown / 2)
        suite.expect(flick.advance(to: CGPoint(x: spaceStep * 6, y: 0),
                             now: spaceCooldown + 0.01) == .spaceRight
                && flick.advance(to: CGPoint(x: spaceStep * 6, y: 0),
                                 now: spaceCooldown * 2 + 0.02) == nil,
               "a fast flick banks one further Space change, not a burst that outlives the hand")

        var diagonal = MouseSpacesGestureSupport.Tracker(origin: .zero)
        suite.expect(diagonal.advance(to: CGPoint(x: spaceStep, y: 0), now: 0) == .spaceRight
                && diagonal.advance(to: CGPoint(x: spaceStep, y: -overviewStep * 3),
                                    now: spaceCooldown + 0.01) == nil
                && diagonal.axis == .horizontal,
               "a press that started switching Spaces never throws up Mission Control halfway through")

        var overviewPress = MouseSpacesGestureSupport.Tracker(origin: .zero)
        suite.expect(overviewPress.advance(to: CGPoint(x: 0, y: -overviewStep), now: 0) == .missionControl
                && overviewPress.advance(to: CGPoint(x: 0, y: -overviewStep * 4), now: 1) == nil
                && overviewPress.didFire,
               "an overview is a toggle, so one press opens it exactly once")

        var bothAxes = MouseSpacesGestureSupport.Tracker(origin: .zero)
        suite.expect(bothAxes.advance(to: CGPoint(x: spaceStep, y: overviewStep * 2), now: 0) == .appExpose,
               "a step past both thresholds is read as the axis that went furthest past its own")

        suite.expect(MouseSpacesGestureSupport.resolved(.spaceRight, followsDrag: true) == .spaceLeft
                && MouseSpacesGestureSupport.resolved(.spaceLeft, followsDrag: true) == .spaceRight
                && MouseSpacesGestureSupport.resolved(.missionControl, followsDrag: true) == .missionControl
                && MouseSpacesGestureSupport.resolved(.appExpose, followsDrag: true) == .appExpose
                && MouseSpacesGestureSupport.resolved(.spaceRight, followsDrag: false) == .spaceRight
                && MouseSpacesGestureSupport.resolved(.spaceLeft, followsDrag: false) == .spaceLeft,
               "the Space can follow the hand instead of the pointer, and the overviews never swap")

        suite.expect(MouseSpacesGestureSupport.canBind(3) && MouseSpacesGestureSupport.canBind(31)
                && !MouseSpacesGestureSupport.canBind(2) && !MouseSpacesGestureSupport.canBind(32)
                && !MouseSpacesGestureSupport.canBind(MouseButtonShortcutSupport.sideWheelLeftInput),
               "the drag lives on an extra button, never on a side-wheel tick there is no way to hold")

        suite.expect(MouseSpacesGestureSupport.boundButton(isAvailable: true, isEnabled: true, button: 4,
                                                     hasShortcut: { _ in false },
                                                     claimedByWheel: { _ in false }) == 4,
               "an available, enabled and unclaimed button drives the drag")
        suite.expect(MouseSpacesGestureSupport.boundButton(isAvailable: true, isEnabled: true, button: 4,
                                                     hasShortcut: { $0 == 4 },
                                                     claimedByWheel: { _ in false }) == nil
                && MouseSpacesGestureSupport.boundButton(isAvailable: true, isEnabled: true, button: 4,
                                                         hasShortcut: { _ in false },
                                                         claimedByWheel: { $0 == 4 }) == nil
                && MouseSpacesGestureSupport.boundButton(isAvailable: false, isEnabled: true, button: 4,
                                                         hasShortcut: { _ in false },
                                                         claimedByWheel: { _ in false }) == nil
                && MouseSpacesGestureSupport.boundButton(isAvailable: true, isEnabled: false, button: 4,
                                                         hasShortcut: { _ in false },
                                                         claimedByWheel: { _ in false }) == nil
                && MouseSpacesGestureSupport.boundButton(isAvailable: true, isEnabled: true, button: 0,
                                                         hasShortcut: { _ in false },
                                                         claimedByWheel: { _ in false }) == nil,
               "the drag never takes a button from a shortcut, from the wheel, or from a switched-off hub")
        suite.expect(MouseButtonShortcutSupport.spacesGestureButton() == nil,
               "with nothing configured the drag claims no button away from navigation")

        // The bound button's press goes through the same decision the tap
        // makes. The drag alone keeps the tap alive with the shortcut switch
        // off, so the press reads that switch itself and hands the click back
        // whole: a mapping left behind is inert and its button is the app's.
        do {
            let mapped = GlobalShortcut(keyCode: Int64(kVK_ANSI_K), modifiers: [.command])
            func pressRoute(_ button: Int64, draining: Bool = false, capturing: Bool = false,
                            excepted: Bool = false, shortcutsOn: Bool = true,
                            mappings: [Int64: GlobalShortcut]) -> MouseButtonShortcutSupport.PressRoute {
                MouseButtonShortcutSupport.route(press: button, isDraining: draining, isCapturing: capturing,
                                                 isExcepted: { excepted }, spacesButton: 4,
                                                 isAvailable: true, isEnabled: shortcutsOn,
                                                 mappings: mappings, claimedByWheel: { _ in false })
            }
            suite.expect(pressRoute(4, mappings: [:]) == .holdForSpaces
                    && pressRoute(4, shortcutsOn: false, mappings: [:]) == .holdForSpaces
                    && pressRoute(4, excepted: true, mappings: [:]) == .pass
                    && pressRoute(4, capturing: true, mappings: [:]) == .capture
                    && pressRoute(4, draining: true, mappings: [:]) == .pass,
                   "the bound button's press is held back by the tap that already receives its drags")
            suite.expect(pressRoute(3, shortcutsOn: false, mappings: [3: mapped]) == .pass
                    && pressRoute(3, mappings: [3: mapped]) == .fire(mapped),
                   "a tap kept up for the drag alone never fires a mapping the shortcut switch turned "
                       + "off, and that button's click passes through whole")
        }
        suite.expect(nudge.givesPressBack && !overviewPress.givesPressBack,
               "a press that never fired goes back, so a tap on that button keeps its ordinary click")

        // The drag presses what the system registered for each command, read
        // back by its symbolic hotkey id, and nothing else.
        do {
            let registered = SpaceWindowBridge.SpaceShortcut(keyCode: 1, flags: [])
            var askedHotKeys: [Int32] = []
            let answers = [MouseSpacesGestureSupport.Action.spaceLeft, .spaceRight, .missionControl, .appExpose]
                .map { action in
                    MouseButtonShortcutService.registeredShortcut(
                        for: action,
                        space: { askedHotKeys.append($0.hotKeyID); return registered },
                        overview: { askedHotKeys.append($0.hotKeyID); return nil })
                }
            suite.expect(askedHotKeys == [79, 81, 32, 33] && answers.map { $0 != nil } == [true, true, false, false],
                   "the drag asks with the system's own registered combinations, never a simulated gesture")
        }
        suite.expect(SpaceWindowBridge.SpaceDirection.left.hotKeyID == 79
                && SpaceWindowBridge.SpaceDirection.right.hotKeyID == 81
                && SpaceWindowBridge.SpaceOverview.missionControl.hotKeyID == 32
                && SpaceWindowBridge.SpaceOverview.appExpose.hotKeyID == 33,
               "the Space steps and the overviews keep their system symbolic hotkey ids")
        do {
            var valueAsked: [Int32] = []
            func registered(enabled: Bool, keyCode: UInt32) -> SpaceWindowBridge.SpaceShortcut? {
                SpaceWindowBridge.registeredShortcut(79, isEnabled: { _ in enabled }, value: { id in
                    valueAsked.append(id)
                    return (keyCode: keyCode, modifiers: 0x40000)
                })
            }
            let live = registered(enabled: true, keyCode: 124)
            let switchedOff = registered(enabled: false, keyCode: 124)
            let keyless = registered(enabled: true, keyCode: 0)
            suite.expect(live?.keyCode == 124 && live?.flags == .maskControl
                    && switchedOff == nil && keyless == nil && valueAsked == [79, 79],
                   "a Spaces shortcut switched off in System Settings is never read back or pressed")
        }

        // A capture holds the tap up by itself, and so does a bound drag.
        suite.expect(MouseButtonShortcutSupport.tapWanted(shortcutsEnabled: false, hasMappings: false,
                                                          isCapturing: true, spacesButton: nil)
                && MouseButtonShortcutSupport.tapWanted(shortcutsEnabled: false, hasMappings: true,
                                                        isCapturing: false, spacesButton: 4)
                && MouseButtonShortcutSupport.tapWanted(shortcutsEnabled: true, hasMappings: true,
                                                        isCapturing: false, spacesButton: nil)
                && !MouseButtonShortcutSupport.tapWanted(shortcutsEnabled: false, hasMappings: true,
                                                         isCapturing: false, spacesButton: nil)
                && !MouseButtonShortcutSupport.tapWanted(shortcutsEnabled: true, hasMappings: false,
                                                         isCapturing: false, spacesButton: nil),
               "a capture holds the tap up by itself: the press asked for may be the drag's, "
                   + "whose switch is not the shortcut switch")


        // A synthesized press has to carry the same flags a finger produces,
        // or the system matches it against no shortcut of its own (issue #401).
        suite.expect(GlobalShortcut(keyCode: Int64(kVK_ANSI_N), modifiers: [.command, .shift])
                .syntheticEventFlags == [.maskCommand, .maskShift],
               "an ordinary key goes out with its modifiers and nothing else")
        suite.expect(GlobalShortcut(keyCode: Int64(kVK_RightArrow), modifiers: [.control, .command])
                .syntheticEventFlags == [.maskControl, .maskCommand, .maskSecondaryFn, .maskNumericPad],
               "an arrow goes out as a function key of the numeric pad, the way it arrives")
        suite.expect(GlobalShortcut(keyCode: Int64(kVK_F13), modifiers: [.control, .option, .command])
                .syntheticEventFlags
                == [.maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn],
               "an F key goes out as a function key")
        suite.expect(GlobalShortcut(keyCode: Int64(kVK_PageDown), modifiers: [.command])
                .syntheticEventFlags == [.maskCommand, .maskSecondaryFn]
                && GlobalShortcut(keyCode: Int64(kVK_ForwardDelete), modifiers: [.command])
                .syntheticEventFlags == [.maskCommand, .maskSecondaryFn],
               "the navigation block counts as function keys too")
        suite.expect(GlobalShortcut(keyCode: Int64(kVK_ANSI_Keypad5), modifiers: [.control])
                .syntheticEventFlags == [.maskControl, .maskNumericPad],
               "a keypad key goes out as part of the keypad, without the function flag")
        suite.expect(GlobalShortcut(keyCode: Int64(kVK_Delete), modifiers: [.command])
                .syntheticEventFlags == [.maskCommand]
                && GlobalShortcut(keyCode: Int64(kVK_Escape), modifiers: [.command])
                .syntheticEventFlags == [.maskCommand]
                && GlobalShortcut(keyCode: Int64(kVK_Return), modifiers: [.control, .option])
                .syntheticEventFlags == [.maskControl, .maskAlternate],
               "the keys beside them are ordinary and stay ordinary")

        // MARK: Super key (issue #330)

        suite.expect(Defaults.registeredDefaults[DefaultsKey.superKeyEnabled] as? Bool == false,
               "the super key ships off by default")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.superKeySource] as? String
                == SuperKeySource.capsLock.rawValue,
               "the super key keeps Caps Lock as its default source")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.superKeyModifiers] as? String
                == SuperKeySupport.defaultModifierStorageValue,
               "the super key starts with all four modifiers")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.superKeySoloAction] as? String
                == SuperKeySoloAction.none.rawValue,
               "a tap on its own does nothing until the user picks something")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.panelControlSuperKey] as? Bool == true,
               "the super key panel row ships visible like its siblings")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.superKeyMappingApplied] == nil
                && Defaults.registeredDefaults[DefaultsKey.superKeyMappedSource] == nil,
               "mapping recovery state is never registered or backed up")
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.superKeyMappingApplied)
                && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.superKeyMappedSource)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.superKeyEnabled)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.superKeySource)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.superKeyModifiers)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.superKeySoloAction),
               "the Super key preferences travel in a backup, the mapping state stays behind")
        suite.expect(AppFeature.superKey.enabledKeys == [DefaultsKey.superKeyEnabled]
                && AppFeature.superKey.permissions == [.accessibility]
                && AppFeature.superKey.group == .mouseKeyboard
                && AppFeature.superKey.energyProfile == .inputs,
               "the hub knows the super key's switch and native input switching needs no Automation")
        suite.expect(FeatureVisibilitySupport.features(for: .superKey) == [.superKey]
                && !FeatureVisibilitySupport.isPageVisible(.superKey, isAvailable: { _ in false }),
               "the page leaves the sidebar when the feature is off in the hub")
        suite.expect(SuperKeySoloAction.sanitized("escape") == .escape
                && SuperKeySoloAction.sanitized("capsLock") == .capsLock
                && SuperKeySoloAction.sanitized("inputSource") == .inputSource
                && SuperKeySoloAction.sanitized("nonsense") == SuperKeySoloAction.none
                && SuperKeySoloAction.sanitized(nil) == SuperKeySoloAction.none,
               "a stored solo action is trusted only when the app still knows it")
        suite.expect(SuperKeySource.sanitized("rightCommand") == .rightCommand
                && SuperKeySource.sanitized("nonsense") == .capsLock
                && SuperKeySource.sanitized(nil) == .capsLock
                && SuperKeySource.capsLock.usage == 0x700000039
                && SuperKeySource.rightControl.usage == 0x7000000E4
                && SuperKeySource.rightShift.usage == 0x7000000E5
                && SuperKeySource.rightOption.usage == 0x7000000E6
                && SuperKeySource.rightCommand.usage == 0x7000000E7
                && Set(SuperKeySource.allCases.map(\.usage)).count == SuperKeySource.allCases.count
                && Set(SuperKeySource.allCases.map(\.keyCode)).count == SuperKeySource.allCases.count,
               "stored sources are validated and each supported key has distinct HID data")
        suite.expect(SuperKeySource.capsLock.systemImage == "capslock"
                && SuperKeySource.rightCommand.systemImage == "command"
                && SuperKeySource.rightOption.systemImage == "option"
                && SuperKeySource.rightControl.systemImage == "control"
                && SuperKeySource.rightShift.systemImage == "shift",
               "each super key source has a matching system image")
        suite.expect(SuperKeySupport.modifiers(from: "control+option+command")
                == [.control, .option, .command]
                && SuperKeySupport.modifiers(from: "shift") == .validMask
                && SuperKeySupport.modifiers(from: "control+") == .validMask
                && SuperKeySupport.modifiers(from: "") == .validMask
                && SuperKeySupport.modifiers(from: "invalid") == .validMask
                && SuperKeySupport.modifiers(from: nil) == .validMask,
               "stored Super key modifiers require a shortcut modifier or use the default")
        suite.expect(SuperKeySupport.storageValue(for: [.control, .option, .command])
                == "control+option+command"
                && SuperKeySupport.storageValue(for: [])
                    == SuperKeySupport.defaultModifierStorageValue,
               "Super key modifiers keep stable storage and never save an empty combination")
        suite.expect(SuperKeySupport.soloEffect(action: .none,
                                          longHold: false,
                                          repeated: false) == .none
                && SuperKeySupport.soloEffect(action: .escape,
                                              longHold: false,
                                              repeated: false) == .escape
                && SuperKeySupport.soloEffect(action: .escape,
                                              longHold: true,
                                              repeated: true) == .none
                && SuperKeySupport.soloEffect(action: .capsLock,
                                              longHold: true,
                                              repeated: false) == .capsLock
                && SuperKeySupport.soloEffect(action: .capsLock,
                                              longHold: false,
                                              repeated: true) == .none,
               "existing solo actions keep their tap, hold and repeat behavior")
        suite.expect(SuperKeySupport.soloEffect(action: .inputSource,
                                          longHold: false,
                                          repeated: false) == .inputSource
                && SuperKeySupport.soloEffect(action: .inputSource,
                                              longHold: false,
                                              repeated: true) == .inputSource
                && SuperKeySupport.soloEffect(action: .inputSource,
                                              longHold: true,
                                              repeated: false) == .capsLock
                && SuperKeySupport.soloEffect(action: .inputSource,
                                              longHold: true,
                                              repeated: true) == .capsLock,
               "the input-source action switches on a quick press and reserves a hold for Caps Lock")
        suite.expect(SuperKeySupport.nextInputSourceID(currentID: "abc",
                                                 enabledIDs: ["abc", "pinyin", "kana"]) == "pinyin"
                && SuperKeySupport.nextInputSourceID(currentID: "kana",
                                                     enabledIDs: ["abc", "pinyin", "kana"]) == "abc"
                && SuperKeySupport.nextInputSourceID(currentID: "missing",
                                                     enabledIDs: ["abc", "pinyin"]) == "abc"
                && SuperKeySupport.nextInputSourceID(currentID: nil,
                                                     enabledIDs: ["abc"]) == nil,
               "input sources cycle through the enabled system list without a hard-coded shortcut")

        let capsMapping = SuperKeyMapping(source: SuperKeySource.capsLock.usage,
                                          destination: SuperKeySupport.triggerUsage)
        let rightCommandMapping = SuperKeyMapping(source: SuperKeySource.rightCommand.usage,
                                                  destination: SuperKeySupport.triggerUsage)
        let foreignMapping = SuperKeyMapping(source: 0x700000064, destination: 0x700000035)
        suite.expect(SuperKeySupport.mappings(enablingSuperKey: true, existing: []) == [capsMapping],
               "turning the key on maps caps lock to the key it arrives as")
        suite.expect(SuperKeySupport.mappings(enablingSuperKey: true, existing: [foreignMapping])
                == [capsMapping, foreignMapping],
               "a mapping the user set up elsewhere survives turning the feature on")
        suite.expect(SuperKeySupport.mappings(enablingSuperKey: true,
                                        existing: [capsMapping, foreignMapping],
                                        source: .rightCommand,
                                        ownedSource: .capsLock)
                == [rightCommandMapping, foreignMapping],
               "changing sources removes the old owned mapping before adding the new one")
        suite.expect(SuperKeySupport.mappings(enablingSuperKey: false,
                                        existing: [capsMapping, foreignMapping],
                                        ownedSource: .capsLock)
                == [foreignMapping],
               "turning it off removes only the entry this feature owns")
        let foreignCapsMapping = SuperKeyMapping(source: SuperKeySource.capsLock.usage,
                                                 destination: 0x700000029)
        let foreignRightCommandMapping = SuperKeyMapping(source: SuperKeySource.rightCommand.usage,
                                                         destination: 0x700000029)
        suite.expect(SuperKeySupport.hasMappingConflict(in: [foreignCapsMapping])
                && SuperKeySupport.mappings(enablingSuperKey: true,
                                            existing: [foreignCapsMapping]) == [foreignCapsMapping]
                && SuperKeySupport.mappings(enablingSuperKey: false,
                                            existing: [foreignCapsMapping]) == [foreignCapsMapping],
               "an existing Caps Lock mapping is refused and preserved in both directions")
        suite.expect(SuperKeySupport.hasMappingConflict(in: [foreignRightCommandMapping],
                                                  source: .rightCommand),
               "an existing mapping on a selected right-side source blocks activation")
        suite.expect(SuperKeySupport.hasMappingConflict(in: [capsMapping])
                && !SuperKeySupport.hasMappingConflict(in: [capsMapping],
                                                       ownedSource: .capsLock)
                && SuperKeySupport.mappings(enablingSuperKey: true,
                                            existing: [capsMapping]) == [capsMapping],
               "an identical external Caps Lock mapping is not claimed without ownership proof")
        suite.expect(SuperKeySupport.mappingArgument([capsMapping])
                == "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":30064771129,\"HIDKeyboardModifierMappingDst\":30064771181}]}",
               "the mapping table goes out in the form the system takes")
        suite.expect(SuperKeySupport.mappingArgument([]) == "{\"UserKeyMapping\":[]}",
               "an empty table clears the mapping")
        suite.expect(SuperKeySupport.mappingsMatch([capsMapping, foreignMapping],
                                             [foreignMapping, capsMapping])
                && !SuperKeySupport.mappingsMatch([capsMapping], [foreignMapping]),
               "mapping readback compares the complete table without depending on its order")
        suite.expect(SuperKeySupport.mappingMarkerAfterClear(previous: true,
                                                       readbackConfirmed: false)
                && !SuperKeySupport.mappingMarkerAfterClear(previous: true,
                                                            readbackConfirmed: true)
                && !SuperKeySupport.mappingMarkerAfterClear(previous: false,
                                                            readbackConfirmed: false),
               "only confirmed clear readback removes the write-ahead mapping marker")
        suite.expect(SuperKeySupport.mappingRequestIsAuthorized(
            requestGeneration: 4,
            currentGeneration: 4,
            tapIsCurrent: true,
            stopping: false
        )
                && !SuperKeySupport.mappingRequestIsAuthorized(
                    requestGeneration: 4,
                    currentGeneration: 5,
                    tapIsCurrent: true,
                    stopping: false
                )
                && !SuperKeySupport.mappingRequestIsAuthorized(
                    requestGeneration: 4,
                    currentGeneration: 4,
                    tapIsCurrent: false,
                    stopping: false
                ),
               "a stop or replaced event tap invalidates a queued Super key mapping")
        suite.expect(SuperKeyMappingGuard.cleanupSource(in: [
            "Vitruvian", SuperKeyMappingGuard.cleanupArgument, "capsLock",
        ]) == .capsLock
                && SuperKeyMappingGuard.cleanupSource(in: [
                    "Vitruvian", SuperKeyMappingGuard.cleanupArgument, "rightCommand",
                ]) == .rightCommand
                && SuperKeyMappingGuard.cleanupSource(in: [
                    "Vitruvian", SuperKeyMappingGuard.cleanupArgument, "invalid",
                ]) == nil,
               "the crash guard accepts only a real Super key source")

        let mappingReport = """
        RegistryID  Key                   Value
        100000a84   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        100000a85   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        """
        suite.expect(SuperKeySupport.parseMappings(mappingReport) == [capsMapping],
               "the same entry on two keyboards is read once")
        suite.expect(SuperKeySupport.mappingReportConfirms(mappingReport, expected: [capsMapping]),
               "mapping readback confirms the requested table on every keyboard")
        let partiallyMappedReport = mappingReport + """

        100000a86   UserKeyMapping   (
        )
        """
        suite.expect(!SuperKeySupport.mappingReportConfirms(partiallyMappedReport,
                                                      expected: [capsMapping])
                && !SuperKeySupport.mappingReportConfirms("", expected: []),
               "one unmapped keyboard or a missing readback cannot confirm a global write")
        suite.expect(SuperKeySupport.parseMappings("RegistryID  Key  Value\n100000a84 UserKeyMapping (null)").isEmpty
                && SuperKeySupport.parseMappings("").isEmpty,
               "a keyboard with no mapping reads as none")
        let heterogeneousUserMappingReport = """
        RegistryID  Key                   Value
        100000a84   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771125;
                HIDKeyboardModifierMappingSrc = 30064771172;
            }
        )
        100000a85   UserKeyMapping   (
        )
        """
        suite.expect(SuperKeySupport.consistentMappings(
            heterogeneousUserMappingReport,
            property: SuperKeySupport.userMappingProperty
        ) == nil, "device-specific key mappings are never copied onto every keyboard")
        let ownedDifferenceReport = """
        RegistryID  Key                   Value
        100000a84   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
                {
                HIDKeyboardModifierMappingDst = 30064771125;
                HIDKeyboardModifierMappingSrc = 30064771172;
            }
        )
        100000a85   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771125;
                HIDKeyboardModifierMappingSrc = 30064771172;
            }
        )
        """
        suite.expect(SuperKeySupport.consistentMappings(
            ownedDifferenceReport,
            property: SuperKeySupport.userMappingProperty,
            ownedSource: .capsLock
        ) == [foreignMapping], "a newly connected keyboard can converge when only the owned mapping differs")
        suite.expect(SuperKeyMappingGuard.mappingsAfterCleanup(
            ownedDifferenceReport,
            source: .capsLock
        ) == [foreignMapping],
               "the crash guard removes only the mapping owned by the Super key")

        let noActionReport = """
        HIDKeyboardModifierMappingPairs = {
          HIDKeyboardModifierMappingSrc = 30064771129;
          HIDKeyboardModifierMappingDst = "-1";
        }
        """
        suite.expect(SuperKeySupport.parseMappings(noActionReport)
                == [SuperKeyMapping(source: SuperKeySource.capsLock.usage,
                                    destination: UInt64.max)],
               "hidutil's signed no-action value keeps its unsigned HID meaning")
        // The page is the only place a refused mapping is visible, so the
        // reason has to reach it ahead of whatever the key itself reads as.
        suite.expect(SuperKeyStatusLine.current(enabled: true, failure: .foreignMapping,
                                                pausedForApplication: true, running: true)
                == .refused(.foreignMapping)
                && SuperKeyStatusLine.current(enabled: true, failure: nil,
                                              pausedForApplication: true, running: true) == .paused
                && SuperKeyStatusLine.current(enabled: true, failure: nil,
                                              pausedForApplication: false, running: true) == .active
                && SuperKeyStatusLine.current(enabled: true, failure: nil,
                                              pausedForApplication: false, running: false) == nil
                && SuperKeyStatusLine.current(enabled: false, failure: .systemRefused,
                                              pausedForApplication: false, running: true) == nil,
               "the Super key page names a refused mapping ahead of the working state")

        var superKeyState = SuperKeySupport.State()
        suite.expect(superKeyState.decide(.otherKey) == .pass,
               "with the key up, typing is untouched")
        suite.expect(superKeyState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 0
        )) == .swallow,
               "the key itself never reaches an app")
        suite.expect(superKeyState.isHeld
                && superKeyState.decide(.otherKey) == .addModifiers
                && superKeyState.decide(.otherKey) == .addModifiers,
               "every key pressed while it is held carries the configured modifiers")
        suite.expect(superKeyState.decide(.triggerUp(timestamp: 1)) == .swallow && !superKeyState.isHeld,
               "releasing after a combination does nothing on its own")

        // What the watchdog leans on: a press whose release never arrived is
        // let go of, and typing goes back to normal without the key being
        // touched again.
        var lostReleaseState = SuperKeySupport.State()
        _ = lostReleaseState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 0
        ))
        suite.expect(lostReleaseState.decide(.otherKey) == .addModifiers,
               "a press with no release still carries the modifiers while it stands")
        lostReleaseState.reset()
        suite.expect(lostReleaseState.decide(.otherKey) == .pass,
               "letting go of a press whose release was lost gives typing back")
        suite.expect(lostReleaseState.decide(.triggerUp(timestamp: 1)) == .swallow,
               "a release arriving after the press was let go does nothing")

        var soloState = SuperKeySupport.State()
        _ = soloState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 1_000_000_000
        ))
        suite.expect(soloState.decide(.triggerUp(timestamp: 1_499_999_999)) == .soloTap(repeated: false),
               "a quick no-repeat press is the solo tap")
        _ = soloState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 2_000_000_000
        ))
        suite.expect(soloState.decide(.triggerDown(
            isRepeat: true, hasPrimaryModifiers: false, timestamp: 2_100_000_000
        )) == .swallow
                && soloState.decide(.triggerUp(timestamp: 2_500_000_000)) == .soloHold(repeated: true),
               "a repeated press held long enough is a repeated solo hold")
        _ = soloState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 3_000_000_000
        ))
        _ = soloState.decide(.otherModifier)
        suite.expect(soloState.decide(.triggerUp(timestamp: 4_000_000_000)) == .swallow,
               "holding it together with another modifier is not a tap either")

        // Drag chords read their modifiers off the mouse-down, not off any
        // keyboard event (#888), so the service classifies mouse presses
        // like other keys and stamps them from a tap at the HID stage, the
        // one place guaranteed to run before every session tap that reads
        // the flags. Moves and drags stay out of that tap.
        do {
            let pressMask = (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
                | (CGEventMask(1) << CGEventType.rightMouseDown.rawValue)
                | (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            let pressesAreKeys = SuperKeyService.mouseDownTypes.allSatisfy { type in
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero,
                        mouseButton: .left)
                    .map { SuperKeyService.classify(type: type, source: .capsLock, event: $0) == .otherKey }
                    == true
            }
            suite.expect(SuperKeyService.mouseDownTypes == [.leftMouseDown, .rightMouseDown, .otherMouseDown]
                    && SuperKeyService.mouseEventMask == pressMask
                    && SuperKeyService.mouseTapLocation == .cghidEventTap
                    && pressesAreKeys,
                   "every mouse press while the super key is held carries the modifiers, stamped at the HID stage")

            // A mouse event carries no keycode of its own: the field reads
            // back as whatever it holds, 0 (the keycode for A) as a rule. The
            // mouse types are answered before the keycode is read, so even a
            // press whose event holds the trigger's code is just another key.
            // The event here is the trigger's own key press, passed as a mouse
            // press: a classifier that read the keycode first would answer it
            // as the trigger.
            func isTriggerDown(_ event: SuperKeySupport.Event) -> Bool {
                guard case .triggerDown = event else { return false }
                return true
            }
            let triggerPress = CGEvent(keyboardEventSource: nil,
                                       virtualKey: CGKeyCode(SuperKeySupport.triggerKeyCode), keyDown: true)
            suite.expect(triggerPress?.getIntegerValueField(.keyboardEventKeycode) == SuperKeySupport.triggerKeyCode
                    && triggerPress.map {
                        SuperKeyService.classify(type: .otherMouseDown, source: .capsLock, event: $0)
                    } == .otherKey
                    && triggerPress.map {
                        isTriggerDown(SuperKeyService.classify(type: .keyDown, source: .capsLock, event: $0))
                    } == true,
                   "a mouse press is answered before the super key ever reads a keycode")
        }
        // A refused mouse tap counts as dead so the health check rebuilds it,
        // but exactly once: the rebuild takes the healthy keyboard tap down
        // with it, and a system that refuses refuses the retry too, so an
        // unbounded flag would hiccup super-key input at whatever rate
        // syncWithPreferences fires. The count has to outlive the teardown its
        // own value asked for, so only a created tap puts it back to zero.
        do {
            var refusals = SuperKeyMouseTapRefusals()
            refusals.requested(created: false)
            let firstRefusalRebuilds = refusals.tapsNeedRebuild(keyboardTapEnabled: true, mouseTapEnabled: nil)
            refusals.requested(created: false)
            let secondRefusalRebuilds = refusals.tapsNeedRebuild(keyboardTapEnabled: true, mouseTapEnabled: nil)
            refusals.requested(created: true)
            suite.expect(firstRefusalRebuilds && !secondRefusalRebuilds && refusals.count == 0
                    && refusals.tapsNeedRebuild(keyboardTapEnabled: true, mouseTapEnabled: false)
                    && refusals.tapsNeedRebuild(keyboardTapEnabled: false, mouseTapEnabled: true)
                    && !refusals.tapsNeedRebuild(keyboardTapEnabled: true, mouseTapEnabled: true)
                    && !refusals.tapsNeedRebuild(keyboardTapEnabled: nil, mouseTapEnabled: nil),
                   "a refused mouse tap is worth one rebuild, and the count survives it")
        }

        var noRepeatHoldState = SuperKeySupport.State()
        _ = noRepeatHoldState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 6_000_000_000
        ))
        suite.expect(noRepeatHoldState.decide(.triggerUp(timestamp: 6_500_000_000)) == .soloHold(repeated: false),
               "a no-repeat press at the hold threshold is a solo hold")

        var fastRepeatState = SuperKeySupport.State()
        _ = fastRepeatState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 8_000_000_000
        ))
        suite.expect(fastRepeatState.decide(.triggerDown(
            isRepeat: true, hasPrimaryModifiers: false, timestamp: 8_100_000_000
        )) == .swallow
                && fastRepeatState.decide(.triggerUp(timestamp: 8_499_999_999)) == .soloTap(repeated: true),
               "a fast repeat remains a quick press and records the repeat")

        var preheldModifierState = SuperKeySupport.State()
        _ = preheldModifierState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: true, timestamp: 7_000_000_000
        ))
        suite.expect(preheldModifierState.isHeld
                && !preheldModifierState.isAlone
                && preheldModifierState.decide(.triggerUp(timestamp: 7_500_000_000)) == .swallow,
               "a pre-held modifier cancels solo action while keeping Superkey held")

        var resetSoloState = SuperKeySupport.State()
        _ = resetSoloState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 0
        ))
        _ = resetSoloState.decide(.triggerDown(
            isRepeat: true, hasPrimaryModifiers: false, timestamp: 1
        ))
        resetSoloState.reset()
        _ = resetSoloState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 5_000_000_000
        ))
        suite.expect(resetSoloState.decide(.triggerUp(timestamp: 5_499_999_999)) == .soloTap(repeated: false),
               "reset clears the previous press timestamp and repeat state")

        var lateRepeatState = SuperKeySupport.State()
        _ = lateRepeatState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 0
        ))
        lateRepeatState.reset()
        suite.expect(lateRepeatState.decide(.triggerDown(
            isRepeat: true, hasPrimaryModifiers: false, timestamp: 1_000_000_000
        )) == .swallow
                && !lateRepeatState.isHeld
                && lateRepeatState.decide(.triggerUp(timestamp: 1_500_000_000)) == .swallow,
               "a repeat after reset cannot revive a solo press")

        var strandedState = SuperKeySupport.State()
        _ = strandedState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 0
        ))
        strandedState.reset()
        suite.expect(strandedState.decide(.otherKey) == .pass,
               "a key held while the tap goes away cannot leave typing stuck in modifiers")
        var unmappedKeyboardState = SuperKeySupport.State()
        suite.expect(unmappedKeyboardState.decide(.sourceKey) == .interceptAndRemap,
               "a raw source key is intercepted while that keyboard's mapping is repaired")

        // MARK: Mouse app exceptions (issue #358)

        suite.expect(MouseExceptionScope.allCases.allSatisfy {
                    (Defaults.registeredDefaults[$0.defaultsKey] as? [String])?.isEmpty == true
               },
               "every feature's exception list registers empty, so they all start out working everywhere")
        suite.expect(Set(MouseExceptionScope.allCases.map(\.defaultsKey)).count == MouseExceptionScope.allCases.count,
               "each feature keeps its own list, never a key shared with another")
        suite.expect(MouseExceptionScope.smoothScroll.feature == .smoothScroll
                && MouseExceptionScope.linearScroll.feature == .linearScroll
                && MouseExceptionScope.scrollDirection.feature == .scrollInverter
                && MouseExceptionScope.focusFollowsMouse.feature == .focusFollowsMouse
                && MouseExceptionScope.navigation.feature == .mouseNavigation
                && MouseExceptionScope.buttonShortcuts.feature == .mouseButtonShortcuts
                && MouseExceptionScope.middleClick.feature == .middleClick
                && MouseExceptionScope.superKey.feature == .superKey,
               "each list knows the feature that owns it, so it hides with that feature")
        suite.expect(MouseExceptionScope.allCases.allSatisfy { $0.feature.group == .mouseKeyboard },
               "every exception list belongs to a mouse-and-keyboard feature")
        suite.expect(Defaults.sanitizedBundleIdentifierList(["  com.example.a  ", "", "com.example.a", "com.example.b"])
                == ["com.example.a", "com.example.b"],
               "the exception list drops blanks, spaces and repeats")

        let exceptionSet: Set<String> = ["com.example.modeler"]
        suite.expect(MouseAppExceptionSupport.isExcepted("com.example.modeler", exceptions: exceptionSet)
                && !MouseAppExceptionSupport.isExcepted("com.example.other", exceptions: exceptionSet)
                && !MouseAppExceptionSupport.isExcepted(nil, exceptions: exceptionSet)
                && !MouseAppExceptionSupport.isExcepted("com.example.modeler", exceptions: []),
               "an app is excepted only when its identifier is on a list that has entries")
        suite.expect(MouseAppExceptionSupport.isExcepted(["com.example.modeler"],
                                                    exceptions: exceptionSet)
                && MouseAppExceptionSupport.isExcepted(
                    ["com.example.helper", "com.example.modeler"],
                    exceptions: exceptionSet)
                && !MouseAppExceptionSupport.isExcepted(["com.example.other"],
                                                         exceptions: exceptionSet),
               "a source app or one of its bundled helpers can carry an exception")
        // A program started from a launcher — the Java process behind a game
        // is the reported one — has no bundle identifier at all, so the file
        // being run stands in as its identity (issue #1009). An app that has
        // an identifier keeps answering only to that, so nothing already
        // listed changes meaning.
        suite.expect(MouseAppExceptionSupport.identity(bundleID: "com.example.modeler",
                                                 executablePath: "/Applications/Modeler.app/Contents/MacOS/Modeler")
                == "com.example.modeler",
               "an app with a bundle identifier answers to it and not to its executable")
        suite.expect(MouseAppExceptionSupport.identity(bundleID: nil,
                                                 executablePath: "/opt/game/runtime/bin/java")
                == "/opt/game/runtime/bin/java",
               "a program with no bundle identifier answers to the file being run")
        suite.expect(MouseAppExceptionSupport.identity(bundleID: nil, executablePath: nil) == nil
                && MouseAppExceptionSupport.identity(bundleID: nil, executablePath: "java") == nil,
               "a program with nothing to be named by is never excepted by accident")
        suite.expect(MouseAppExceptionSupport.isExecutablePathIdentity("/opt/game/runtime/bin/java")
                && !MouseAppExceptionSupport.isExecutablePathIdentity("com.example.modeler"),
               "a stored path is told from a bundle identifier by its leading slash")
        suite.expect(MouseAppExceptionSupport.isExcepted(
                   MouseAppExceptionSupport.identity(bundleID: nil,
                                                     executablePath: "/opt/game/runtime/bin/java"),
                   exceptions: ["/opt/game/runtime/bin/java"])
                && !MouseAppExceptionSupport.isExcepted(
                    MouseAppExceptionSupport.identity(bundleID: nil,
                                                      executablePath: "/opt/other/bin/java"),
                    exceptions: ["/opt/game/runtime/bin/java"]),
               "a listed program path excepts that program and no other")
        suite.expect(InstalledApps.name(for: "/opt/game/runtime/bin/java") == "java",
               "a listed program path is shown by its file name, not the whole path")

        // The stored path is the one the file sheet handed back and the
        // matched one is the file the running program reports, and the same
        // file arrives at the two ends under different names as soon as
        // anything on the way is a link — measured on this Mac, the sheet
        // answers /private/tmp/… for a file the running program answers
        // /tmp/… for. Both ends resolve, so they meet.
        let identityRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-identity-\(getpid())", isDirectory: true)
        let runtimeBinary = identityRoot.appendingPathComponent("runtime/bin/launcher")
        try? FileManager.default.createDirectory(at: runtimeBinary.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: runtimeBinary.path, contents: Data())
        let linkedBinary = identityRoot.appendingPathComponent("launcher")
        try? FileManager.default.createSymbolicLink(at: linkedBinary, withDestinationURL: runtimeBinary)
        let pickedThroughLink = MouseAppExceptionSupport.executablePathIdentity(linkedBinary.path)
        let reportedByTheSystem = MouseAppExceptionSupport.identity(bundleID: nil,
                                                                    executablePath: runtimeBinary.path)
        suite.expect(pickedThroughLink != nil
                && pickedThroughLink != linkedBinary.path
                && pickedThroughLink == reportedByTheSystem,
               "a program picked through a link stores the file it links to")
        suite.expect(MouseAppExceptionSupport.isExcepted(reportedByTheSystem,
                                                   exceptions: Set([pickedThroughLink].compactMap { $0 })),
               "the program the system reports matches the entry the picker stored")

        // A file sheet that takes programs can be walked into a bundle, and
        // what is stored has to be what the system will report once the file
        // runs. Measured on this Mac: a bundle's own executable run straight
        // from disk is reported as com.example.withid, while a runtime shipped
        // deeper in that same bundle — the shape issue #1009 is about — is
        // reported with no identifier and stays a path. Filing that runtime
        // under the app above it would break the case this all exists for.
        func makeTestBundle(_ name: String, identifier: String?) -> URL {
            let bundle = identityRoot.appendingPathComponent("\(name).app")
            for file in ["Contents/MacOS/\(name)", "Contents/runtime/bin/java"] {
                let url = bundle.appendingPathComponent(file)
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: url.path, contents: Data())
            }
            var info: [String: Any] = ["CFBundleExecutable": name, "CFBundlePackageType": "APPL"]
            if let identifier { info["CFBundleIdentifier"] = identifier }
            if let plist = try? PropertyListSerialization.data(fromPropertyList: info,
                                                               format: .xml,
                                                               options: 0) {
                try? plist.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
            }
            return bundle
        }
        let namedBundle = makeTestBundle("Modeler", identifier: "com.example.modeler")
        let namelessBundle = makeTestBundle("Bare", identifier: nil)
        suite.expect(MouseAppExceptionSupport.pickedIdentity(for: namedBundle) == "com.example.modeler"
                && MouseAppExceptionSupport.pickedIdentity(
                    for: namedBundle.appendingPathComponent("Contents/MacOS/Modeler"))
                    == "com.example.modeler",
               "an app is stored by its identifier whether its bundle or the binary inside it was picked")
        let bundledRuntime = namedBundle.appendingPathComponent("Contents/runtime/bin/java")
        suite.expect(MouseAppExceptionSupport.pickedIdentity(for: bundledRuntime)
                == MouseAppExceptionSupport.executablePathIdentity(bundledRuntime.path),
               "a runtime shipped inside an app keeps its own path, never the identifier of the app above it")
        suite.expect(MouseAppExceptionSupport.pickedIdentity(for: namelessBundle)
                == MouseAppExceptionSupport.executablePathIdentity(
                    namelessBundle.appendingPathComponent("Contents/MacOS/Bare").path),
               "an app whose Info.plist names no identifier is stored by the binary it runs")
        suite.expect(MouseAppExceptionSupport.pickedIdentity(for: runtimeBinary)
                == MouseAppExceptionSupport.executablePathIdentity(runtimeBinary.path),
               "a program that is not packaged as an app is stored by its own file")
        try? FileManager.default.removeItem(at: identityRoot)

        // The list sanitizer runs over stored entries, and a file name may
        // legally end in a space: trimming a path would look for a spelling
        // the running program never reports, so only an identifier is trimmed.
        suite.expect(Defaults.sanitizedBundleIdentifierList(["/opt/game/bin/java ", " com.example.a "])
                == ["/opt/game/bin/java ", "com.example.a"],
               "a stored path keeps its exact file name while an identifier is trimmed")

        suite.expect(InstalledApps.location(for: "com.example.modeler") == nil,
               "a bundle identifier names its app on its own and carries no location")
        suite.expect(InstalledApps.location(for: NSHomeDirectory() + "/runtimes/zulu-8.jre/bin/java")
                == "~/runtimes/zulu-8.jre/bin",
               "a path identity is located by its directory, spelled from home")
        suite.expect(InstalledApps.location(for: "/opt/game/bin/java") == "/opt/game/bin",
               "a path outside home keeps its absolute directory")

        // Running programs that are not packaged as apps (issue #865): a bare
        // executable run under .regular activation policy (e.g. a game
        // launcher's runtime process) answers to its resolved file path when it
        // has no bundle identifier, while an ordinary .app bundle keeps its
        // bundle row and background/accessory processes stay excluded.
        let runningTestRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-running-\(getpid())", isDirectory: true)
        let runningTargetBinary = runningTestRoot.appendingPathComponent("bin/java")
        let runningSymlinkBinary = runningTestRoot.appendingPathComponent("bin/java_link")
        try? FileManager.default.createDirectory(at: runningTargetBinary.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: runningTargetBinary.path, contents: Data())
        try? FileManager.default.createSymbolicLink(at: runningSymlinkBinary, withDestinationURL: runningTargetBinary)
        let resolvedRunningPath = MouseAppExceptionSupport.executablePathIdentity(runningTargetBinary.path)

        let regularBareApp = InstalledApps.runningApplication(
            activationPolicy: .regular,
            bundleID: nil,
            bundleURL: runningSymlinkBinary,
            executableURL: runningSymlinkBinary,
            localizedName: "java",
            acceptsExecutables: true
        )
        if let regularBareApp, let resolvedRunningPath {
            suite.expect(regularBareApp.identity == resolvedRunningPath
                    && regularBareApp.bundleID == nil
                    && regularBareApp.name == "java"
                    && regularBareApp.url.path == resolvedRunningPath,
                   "a running regular bare executable produces a path row with its resolved path identity")
        } else {
            suite.expect(false, "a running regular bare executable resolves its path row setup")
        }

        let runningWrapper = runningTestRoot.appendingPathComponent("zulu-8.jre", isDirectory: true)
        let runningWrapperBinary = runningWrapper.appendingPathComponent("bin/java")
        try? FileManager.default.createDirectory(at: runningWrapperBinary.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: runningWrapperBinary.path, contents: Data())
        let wrapperBareApp = InstalledApps.runningApplication(
            activationPolicy: .regular,
            bundleID: nil,
            bundleURL: runningWrapper,
            executableURL: runningWrapperBinary,
            localizedName: "java",
            acceptsExecutables: true
        )
        let resolvedWrapperPath = MouseAppExceptionSupport.executablePathIdentity(runningWrapperBinary.path)
        if let wrapperBareApp, let resolvedWrapperPath {
            suite.expect(wrapperBareApp.identity == resolvedWrapperPath
                    && wrapperBareApp.bundleID == nil
                    && wrapperBareApp.url.path == resolvedWrapperPath,
                   "a running executable inside a non-app wrapper produces a path row")
        } else {
            suite.expect(false, "a non-app wrapper executable resolves its path row setup")
        }

        let appBundleURL = URL(fileURLWithPath: "/Applications/TextEdit.app")
        let regularBundleApp = InstalledApps.runningApplication(
            activationPolicy: .regular,
            bundleID: "com.apple.TextEdit",
            bundleURL: appBundleURL,
            executableURL: appBundleURL.appendingPathComponent("Contents/MacOS/TextEdit"),
            localizedName: "TextEdit",
            acceptsExecutables: true
        )
        suite.expect(regularBundleApp != nil
                && regularBundleApp?.identity == "com.apple.TextEdit"
                && regularBundleApp?.bundleID == "com.apple.TextEdit"
                && regularBundleApp?.url == appBundleURL
                && regularBundleApp?.name == "TextEdit",
               "a running regular app bundle produces an unchanged bundle row")

        let accessoryBareApp = InstalledApps.runningApplication(
            activationPolicy: .accessory,
            bundleID: nil,
            bundleURL: nil,
            executableURL: runningTargetBinary,
            localizedName: "java",
            acceptsExecutables: true
        )
        let prohibitedBareApp = InstalledApps.runningApplication(
            activationPolicy: .prohibited,
            bundleID: nil,
            bundleURL: nil,
            executableURL: runningTargetBinary,
            localizedName: "java",
            acceptsExecutables: true
        )
        suite.expect(accessoryBareApp == nil && prohibitedBareApp == nil,
               "an accessory or prohibited bare executable is ignored")

        let embeddedBundleBareApp = InstalledApps.runningApplication(
            activationPolicy: .regular,
            bundleID: "com.example.embedded",
            bundleURL: nil,
            executableURL: runningTargetBinary,
            localizedName: "embedded_tool",
            acceptsExecutables: true
        )
        suite.expect(embeddedBundleBareApp != nil
                && embeddedBundleBareApp?.identity == "com.example.embedded"
                && embeddedBundleBareApp?.bundleID == "com.example.embedded"
                && embeddedBundleBareApp?.identity != runningTargetBinary.path,
               "a bare executable that reports a bundle identifier uses that identifier and not its path")

        let duplicateProcessApp = InstalledApps.runningApplication(
            activationPolicy: .regular,
            bundleID: nil,
            bundleURL: nil,
            executableURL: runningTargetBinary,
            localizedName: "java",
            acceptsExecutables: true
        )
        if let regularBareApp, let duplicateProcessApp, let resolvedRunningPath {
            let deduplicated = InstalledApps.deduplicatedAndFiltered(
                [regularBareApp, duplicateProcessApp],
                excluding: []
            )
            suite.expect(deduplicated.count == 1
                    && deduplicated.first?.identity == resolvedRunningPath,
                   "duplicate processes with the same path identity collapse to one entry")

            let excludedPathApps = InstalledApps.deduplicatedAndFiltered(
                [regularBareApp],
                excluding: [resolvedRunningPath]
            )
            let unexcludedPathApps = InstalledApps.deduplicatedAndFiltered(
                [regularBareApp],
                excluding: ["/other/path/java"]
            )
            suite.expect(excludedPathApps.isEmpty && unexcludedPathApps.count == 1,
                   "an exclusion set containing a path identity drops that program")
        } else {
            suite.expect(false, "running path identities resolve before they are deduplicated or excluded")
        }

        let reverseJavaApps = InstalledApps.deduplicatedAndFiltered([
            InstalledApps.InstalledApp(id: "/runtimes/zulu/bin/java",
                                       name: "java",
                                       bundleID: nil,
                                       url: URL(fileURLWithPath: "/runtimes/zulu/bin/java"),
                                       isSystem: false,
                                       explicitIdentity: "/runtimes/zulu/bin/java"),
            InstalledApps.InstalledApp(id: "/runtimes/temurin/bin/java",
                                       name: "java",
                                       bundleID: nil,
                                       url: URL(fileURLWithPath: "/runtimes/temurin/bin/java"),
                                       isSystem: false,
                                       explicitIdentity: "/runtimes/temurin/bin/java")
        ], excluding: [])
        suite.expect(reverseJavaApps.compactMap(\.identity) == ["/runtimes/temurin/bin/java", "/runtimes/zulu/bin/java"],
               "same-named executable rows sort by identity")

        let unacceptedBareApp = InstalledApps.runningApplication(
            activationPolicy: .regular,
            bundleID: nil,
            bundleURL: nil,
            executableURL: runningTargetBinary,
            localizedName: "java",
            acceptsExecutables: false
        )
        suite.expect(unacceptedBareApp == nil,
               "a bare executable is omitted when the caller does not accept executables")

        let emptyIdentifierBareApp = InstalledApps.runningApplication(
            activationPolicy: .regular,
            bundleID: "",
            bundleURL: runningSymlinkBinary,
            executableURL: runningSymlinkBinary,
            localizedName: "java",
            acceptsExecutables: true
        )
        suite.expect(emptyIdentifierBareApp == nil,
               "an empty bundle identifier is dropped, as the taps would never match it")

        try? FileManager.default.removeItem(at: runningTestRoot)

        // Both ends of that agreement go through the support enum: the picker
        // stores only what it resolved, and the taps read a running program
        // by the same rule. An identity resolved at one end and taken raw at
        // the other silently matches nothing (issue #1009), so a pick reached
        // through a link has to land on the same entry the running program
        // reports, whichever way into the list it took.
        do {
            let pickedRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("vitruvian-picked-\(getpid())", isDirectory: true)
            let pickedProgram = pickedRoot.appendingPathComponent("bin/java")
            let pickedLink = pickedRoot.appendingPathComponent("bin/java_link")
            try? FileManager.default.createDirectory(at: pickedProgram.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: pickedProgram.path, contents: Data())
            try? FileManager.default.createSymbolicLink(at: pickedLink, withDestinationURL: pickedProgram)
            defer { try? FileManager.default.removeItem(at: pickedRoot) }
            let resolvedProgram = MouseAppExceptionSupport.executablePathIdentity(pickedProgram.path)
            suite.expect(resolvedProgram != nil
                    && MouseAppExceptionSupport.addedIdentity(picked: pickedProgram, acceptsExecutables: true)
                        == resolvedProgram
                    && MouseAppExceptionSupport.addedIdentity(picked: pickedLink, acceptsExecutables: true)
                        == resolvedProgram
                    && MouseAppExceptionSupport.addedIdentity(picked: pickedProgram, acceptsExecutables: false) == nil
                    && MouseAppExceptionSupport.addedIdentity(picked: pickedProgram,
                                                              explicitIdentity: "com.example.running",
                                                              acceptsExecutables: false) == "com.example.running"
                    && MouseAppExceptionSupport.addedIdentity(picked: pickedProgram,
                                                              explicitIdentity: "/opt/game/bin/java",
                                                              acceptsExecutables: false) == nil,
                   "every value the picker adds is one the support enum resolved")
            suite.expect(MouseAppExceptions.identity(bundleID: nil, executableURL: pickedLink) == resolvedProgram
                    && MouseAppExceptions.identity(bundleID: nil, executableURL: pickedLink) != pickedLink.path
                    && MouseAppExceptions.identity(bundleID: "com.example.app", executableURL: pickedLink)
                        == "com.example.app",
                   "the taps read an executable path only through the support enum")
        }

        // A list row's location caption is what tells path identities apart —
        // every bundled runtime displays as "java" (issue #1009) — and sibling
        // runtimes differ only after a long shared directory prefix, so the
        // caption truncates from the HEAD: cutting the middle or tail would
        // hide the one component that differs. Both pickers take it from here.
        do {
            let pathCaption = InstalledApps.RowCaption(text: "/opt/game/bin", cut: .head)
            let pathRow = InstalledApps.InstalledApp(id: "/opt/game/bin/java", name: "java", bundleID: nil,
                                                     url: URL(fileURLWithPath: "/opt/game/bin/java"),
                                                     isSystem: false, explicitIdentity: "/opt/game/bin/java")
            let bundleRow = InstalledApps.InstalledApp(id: "com.apple.TextEdit", name: "TextEdit",
                                                       bundleID: "com.apple.TextEdit",
                                                       url: URL(fileURLWithPath: "/Applications/TextEdit.app"),
                                                       isSystem: true)
            suite.expect(InstalledApps.listCaption(for: "/opt/game/bin/java") == pathCaption
                    && InstalledApps.listCaption(for: "com.example.modeler") == nil
                    && InstalledApps.pickerCaption(for: pathRow) == pathCaption
                    && InstalledApps.pickerCaption(for: bundleRow)
                        == InstalledApps.RowCaption(text: "com.apple.TextEdit", cut: .middle),
                   "each path identity picker shows where its file sits and truncates from the head")
        }

        // Every way into a list is sanitized by the one sanitizer: an
        // identifier is trimmed, and a path keeps its exact file name, which
        // may legally end in a space the running program reports too.
        do {
            let listDefaults = UserDefaults(suiteName: "vitru.tests.mouse-exception-lists")!
            listDefaults.removePersistentDomain(forName: "vitru.tests.mouse-exception-lists")
            defer { listDefaults.removePersistentDomain(forName: "vitru.tests.mouse-exception-lists") }
            let listKey = MouseExceptionScope.middleClick.defaultsKey
            listDefaults.set(["/opt/game/bin/java ", " com.example.a "], forKey: listKey)
            let exceptionLists = MouseAppExceptions(defaults: listDefaults)
            let loadedList = exceptionLists.list(.middleClick)
            exceptionLists.add("/opt/other/bin/java ", to: .middleClick)
            exceptionLists.add(" com.example.b ", to: .middleClick)
            exceptionLists.add(" com.example.a", to: .middleClick)
            let sanitizedList = ["/opt/game/bin/java ", "com.example.a", "/opt/other/bin/java ", "com.example.b"]
            suite.expect(loadedList == ["/opt/game/bin/java ", "com.example.a"]
                    && exceptionLists.list(.middleClick) == sanitizedList
                    && listDefaults.stringArray(forKey: listKey) == sanitizedList,
                   "the exception list is sanitized through the one sanitizer, never beside it")
        }

        // The leading-slash test IS the rule that tells a stored path from a
        // bundle identifier, spelled once, inside isExecutablePathIdentity
        // (bazel/source_lints.py checks that no other file re-tests it).
        suite.expect(MouseAppExceptionSupport.sourceProcessID(42) == 42
                && MouseAppExceptionSupport.sourceProcessID(0) == nil
                && MouseAppExceptionSupport.sourceProcessID(-1) == nil
                && MouseAppExceptionSupport.sourceProcessID(Int64(Int32.max) + 1) == nil,
               "only positive process ids supported by the workspace enter source tracking")

        let pointer = CGPoint(x: 100, y: 100)
        let ownWindow = MouseAppExceptionSupport.Window(
            frame: CGRect(x: 0, y: 0, width: 400, height: 400), layer: 0, processID: 9)
        let systemWindow = MouseAppExceptionSupport.Window(
            frame: CGRect(x: 0, y: 0, width: 400, height: 400), layer: 25, processID: 3)
        let hiddenWindow = MouseAppExceptionSupport.Window(
            frame: CGRect(x: 0, y: 0, width: 400, height: 400), layer: 0, alpha: 0, processID: 4)
        let frontWindow = MouseAppExceptionSupport.Window(
            frame: CGRect(x: 50, y: 50, width: 300, height: 300), layer: 0, processID: 5)
        let panelWindow = MouseAppExceptionSupport.Window(
            frame: CGRect(x: 60, y: 60, width: 100, height: 100), layer: 3, processID: 6)
        let behindWindow = MouseAppExceptionSupport.Window(
            frame: CGRect(x: 0, y: 0, width: 400, height: 400), layer: 0, processID: 7)
        let underlayWindow = MouseAppExceptionSupport.Window(
            frame: CGRect(x: 0, y: 0, width: 400, height: 400), layer: -2_147_483_601, processID: 8)
        suite.expect(MouseAppExceptionSupport.pointerWindow(
                in: [ownWindow, systemWindow, hiddenWindow, frontWindow, behindWindow],
                at: pointer, ownProcessID: 9) == frontWindow,
               "the pointer's window is the frontmost real window under it")
        suite.expect(MouseAppExceptionSupport.pointerWindow(
                in: [underlayWindow], at: pointer, ownProcessID: 9) == nil,
               "a window living below every real one never answers for the pointer")
        suite.expect(MouseAppExceptionSupport.pointerWindow(
                in: [panelWindow, frontWindow], at: pointer, ownProcessID: 9) == panelWindow,
               "an app's floating panel answers for its app")
        suite.expect(MouseAppExceptionSupport.pointerWindow(
                in: [frontWindow], at: CGPoint(x: 380, y: 380), ownProcessID: 9) == nil,
               "a pointer outside every window resolves to nothing")

        suite.expect(MouseAppExceptionSupport.cacheHolds(region: frontWindow.frame, resolvedPoint: pointer,
                                                   resolvedAt: 10, point: CGPoint(x: 120, y: 120), now: 10.2),
               "a fresh answer keeps serving while the pointer stays inside its window")
        suite.expect(!MouseAppExceptionSupport.cacheHolds(region: frontWindow.frame, resolvedPoint: pointer,
                                                    resolvedAt: 10, point: CGPoint(x: 380, y: 380), now: 10.2),
               "the pointer leaving the window asks the window server again")
        suite.expect(!MouseAppExceptionSupport.cacheHolds(region: frontWindow.frame, resolvedPoint: pointer,
                                                    resolvedAt: 10, point: pointer,
                                                    now: 10 + MouseAppExceptionSupport.resolveLifetime),
               "an answer expires, so a window that opened under a resting pointer is noticed")
        suite.expect(MouseAppExceptionSupport.cacheHolds(region: nil, resolvedPoint: pointer,
                                                   resolvedAt: 10, point: pointer, now: 10.2)
                && !MouseAppExceptionSupport.cacheHolds(region: nil, resolvedPoint: pointer,
                                                        resolvedAt: 10,
                                                        point: CGPoint(x: 101, y: 100), now: 10.2),
               "an answer of nothing only covers the exact spot it was resolved at")
        suite.expect(MouseAppExceptionSupport.cacheNamesWindow(region: frontWindow.frame, point: pointer)
                && !MouseAppExceptionSupport.cacheNamesWindow(region: frontWindow.frame,
                                                              point: CGPoint(x: 380, y: 380))
                && !MouseAppExceptionSupport.cacheNamesWindow(region: nil, point: pointer),
               "an expired answer still names its own window, and no other")

        // Hold the main queue while a real pointer lookup runs elsewhere. A
        // synchronous hop would miss the deadline even with a cold cache.
        // Volatile preferences keep this fixture out of the user's settings.
        do {
            let defaults = UserDefaults.standard
            let savedArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
            var arguments = savedArguments
            for scope in MouseExceptionScope.allCases {
                arguments[scope.defaultsKey] = ["com.example.mouse-exception-test"]
            }
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            let cacheClock = PointerInputTestClock()
            let exceptions = MouseAppExceptions(uptime: cacheClock.read)
            defer {
                defaults.setVolatileDomain(savedArguments, forName: UserDefaults.argumentDomain)
            }

            func queryWithoutMain(_ label: String) {
                let finished = DispatchGroup()
                finished.enter()
                Thread {
                    for index in 0..<100 {
                        let point = CGPoint(x: -10_000 - index, y: -10_000)
                        for scope in [MouseExceptionScope.middleClick, .scrollDirection] {
                            _ = exceptions.excludesPointerTarget(scope, at: point)
                        }
                    }
                    finished.leave()
                }.start()
                suite.expect(finished.wait(timeout: .now() + 0.5) == .success,
                       "\(label) pointer lookups return while the main queue is held")
                // Drain both the refresh and a failed synchronous lookup so
                // a regression fails an assertion rather than wedging tests.
                var drained = false
                DispatchQueue.main.async { drained = true }
                let deadline = Date().addingTimeInterval(5)
                while (!drained || finished.wait(timeout: .now()) != .success),
                      Date() < deadline {
                    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
                }
                suite.expect(drained && finished.wait(timeout: .now()) == .success,
                       "pointer lookups and the queued refresh finish once main is available")
            }

            /// The verdict a tap gets while the app under the pointer has not
            /// been resolved yet.
            func verdictWithoutMain(_ point: CGPoint) -> Bool {
                var verdict = false
                let answered = DispatchGroup()
                answered.enter()
                Thread {
                    verdict = exceptions.excludesPointerTarget(.middleClick, at: point)
                    answered.leave()
                }.start()
                let deadline = Date().addingTimeInterval(5)
                while answered.wait(timeout: .now()) != .success, Date() < deadline {
                    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
                }
                return verdict
            }

            queryWithoutMain("cold-cache")
            queryWithoutMain("changed-window")
            cacheClock.advance(by: MouseAppExceptionSupport.resolveLifetime)
            queryWithoutMain("expired-cache")
            suite.expect(verdictWithoutMain(CGPoint(x: -20_000, y: -20_000)),
                   "an app that cannot be told apart from a listed one keeps the feature's hands off")
            for scope in MouseExceptionScope.allCases { arguments[scope.defaultsKey] = [String]() }
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            // The suite runs on the main thread.
            MainActor.assumeIsolated { exceptions.reload() }
            queryWithoutMain("empty-list")
            suite.expect(!verdictWithoutMain(CGPoint(x: -20_010, y: -20_010)),
                   "an empty list stands nothing down")
        }

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.mouseExceptions(language)
            suite.expect(Set(MouseExceptionScope.allCases.map { strings.caption(for: $0) }).count
                    == MouseExceptionScope.allCases.count,
                   "each list explains its own feature, never the same line twice (\(language.rawValue))")
        }


        for language in AppLanguage.allCases {
            let strings = FeatureStrings.switcherAppRules(language)
            suite.expect(Set([strings.showWithoutWindows, strings.windowsOnly, strings.hidden]).count == 3,
                   "each per-app switcher choice is distinct for \(language.rawValue)")
        }

        suite.expect(FinderRenameSupport.acceptsFocusedRole("AXOutline")
                && !FinderRenameSupport.acceptsFocusedRole("AXTextField")
                && !FinderRenameSupport.acceptsFocusedRole("AXTextArea")
                && !FinderRenameSupport.acceptsFocusedRole(nil),
               "Finder rename only acts outside editable fields with a known focus")




        // MARK: Precise volume roller

        var volumeGate = PreciseVolumeRollerGate()
        suite.expect(volumeGate.accepts(.up, at: 100.00),
               "precise volume accepts the first wheel step")
        suite.expect(!volumeGate.accepts(.up, at: 100.01),
               "precise volume drops repeats that arrive inside the spacing window")
        suite.expect(volumeGate.accepts(.up, at: 100.05),
               "precise volume accepts a later step in the same direction")

        var reversalGate = PreciseVolumeRollerGate()
        suite.expect(reversalGate.accepts(.up, at: 200.00),
               "precise volume reversal setup accepts the initial direction")
        suite.expect(!reversalGate.accepts(.down, at: 200.08),
               "precise volume ignores the first opposite pulse inside the reversal window")
        suite.expect(!reversalGate.accepts(.down, at: 200.16),
               "precise volume waits for a stable opposite direction")
        suite.expect(reversalGate.accepts(.down, at: 200.24),
               "precise volume accepts the confirmed opposite direction")

        var oldDirectionGate = PreciseVolumeRollerGate()
        suite.expect(oldDirectionGate.accepts(.up, at: 300.00),
               "precise volume accepts first old-direction step")
        suite.expect(oldDirectionGate.accepts(.down, at: 300.40),
               "precise volume accepts an opposite step after the reversal window")
        var fastStreamGate = PreciseVolumeRollerGate()
        let fastAccepted = stride(from: 400.00, through: 400.10, by: 0.02)
            .filter { fastStreamGate.accepts(.up, at: $0) }
        suite.expect(fastAccepted.count == 3,
               "precise volume rate-limits sustained fast input instead of starving it")
        suite.expect(PreciseVolumeMediaKey.volumeUp.rollerDirection == .up
                && PreciseVolumeMediaKey.volumeDown.rollerDirection == .down
                && PreciseVolumeMediaKey.mute.rollerDirection == nil,
               "precise volume only remaps volume up and down media keys")
        var optionPress = PreciseVolumeKeyOwnership()
        suite.expect(optionPress.leavesToSystem(keyCode: 0, isDown: true, isRepeat: false,
                                                option: true, commandOrControl: false)
                && optionPress.leavesToSystem(keyCode: 0, isDown: true, isRepeat: true,
                                              option: false, commandOrControl: false)
                && optionPress.leavesToSystem(keyCode: 0, isDown: false, isRepeat: false,
                                              option: false, commandOrControl: false),
               "precise volume leaves an Option press to the system until its release")
        var commandPress = PreciseVolumeKeyOwnership()
        suite.expect(commandPress.leavesToSystem(keyCode: 1, isDown: true, isRepeat: false,
                                                 option: false, commandOrControl: true),
               "precise volume leaves a Command or Control press to the system")
        var plainPress = PreciseVolumeKeyOwnership()
        suite.expect(!plainPress.leavesToSystem(keyCode: 0, isDown: true, isRepeat: false,
                                                option: false, commandOrControl: false)
                && !plainPress.leavesToSystem(keyCode: 0, isDown: true, isRepeat: true,
                                              option: true, commandOrControl: false)
                && !plainPress.leavesToSystem(keyCode: 0, isDown: false, isRepeat: false,
                                              option: true, commandOrControl: false),
               "precise volume keeps remapping a plain press when Option joins mid-press")
        var unseenPress = PreciseVolumeKeyOwnership()
        suite.expect(unseenPress.leavesToSystem(keyCode: 0, isDown: true, isRepeat: true,
                                                option: true, commandOrControl: false)
                && unseenPress.leavesToSystem(keyCode: 0, isDown: false, isRepeat: false,
                                              option: true, commandOrControl: false),
               "precise volume leaves a press whose key-down it never saw to the system")
        var unseenPlainPress = PreciseVolumeKeyOwnership()
        suite.expect(unseenPlainPress.leavesToSystem(keyCode: 1, isDown: true, isRepeat: true,
                                                     option: false, commandOrControl: false)
                && unseenPlainPress.leavesToSystem(keyCode: 1, isDown: false, isRepeat: false,
                                                   option: false, commandOrControl: false),
               "precise volume leaves unseen plain repeats and releases to the system")
        var lostRelease = PreciseVolumeKeyOwnership()
        _ = lostRelease.leavesToSystem(keyCode: 0, isDown: true, isRepeat: false,
                                       option: true, commandOrControl: false)
        suite.expect(!lostRelease.leavesToSystem(keyCode: 0, isDown: true, isRepeat: false,
                                                 option: false, commandOrControl: false),
               "precise volume remaps a fresh plain press even when the last release was lost")
        let fineStep = PreciseVolumeKeyEvents.fineStep(0)
        suite.expect(fineStep.count == 2 && fineStep.allSatisfy(PreciseVolumeKeyEvents.isPosted),
               "precise volume marks its own fine-step events so its tap never counts them as a press")
        suite.expect(CGEvent(source: nil).map { !PreciseVolumeKeyEvents.isPosted($0) } == true,
               "a physical volume event is not taken for one precise volume posted")

        // MARK: Brightness key base (issue #370)

        let pressed = Date(timeIntervalSince1970: 1_800_000_000)
        suite.expect(BrightnessSupport.trustsRememberedLevel(lastKnownAt: pressed,
                                                       now: pressed.addingTimeInterval(1),
                                                       window: 3),
               "a level written a moment ago is still the running value")
        suite.expect(!BrightnessSupport.trustsRememberedLevel(lastKnownAt: pressed,
                                                        now: pressed.addingTimeInterval(3),
                                                        window: 3),
               "a level older than the window is asked about again")
        suite.expect(!BrightnessSupport.trustsRememberedLevel(lastKnownAt: nil,
                                                        now: pressed, window: 3),
               "a display never written to is asked about")
        suite.expect(!BrightnessSupport.trustsRememberedLevel(lastKnownAt: pressed.addingTimeInterval(60),
                                                        now: pressed, window: 3),
               "a clock that jumped backwards never makes a stale level look fresh")
        // The step itself is unchanged; what changed is the value it starts
        // from, so the arithmetic stays pinned.
        suite.expect(BrightnessSupport.steppedBrightness(0.8, delta: 1 / 16.0) > 0.8
                && BrightnessSupport.steppedBrightness(0.0, delta: 1 / 16.0) > 0,
               "a step still moves in the direction asked for")

        // MARK: Modifying mouse taps are handed back across a session switch
        // The session watcher's two halves are driven above, through a private
        // notification center. Mouse acceleration reads the session it starts
        // in by the same rule as the watcher: unreadable counts as on screen.
        suite.expect(MouseAccelerationService.sessionIsOnScreen(nil)
                && MouseAccelerationService.sessionIsOnScreen([:])
                && MouseAccelerationService.sessionIsOnScreen([onConsoleKey: true])
                && !MouseAccelerationService.sessionIsOnScreen([onConsoleKey: false]),
               "mouse acceleration shares the safe initial session-state fallback")
        // The tap owners cannot be reached from this list (they need the event
        // chain): bazel/source_lints.py checks that each one follows the
        // session, asks before re-arming a tap the window server disabled, and
        // hands its port back on teardown.

        // The taps that filter ordinary clicks and wheel events are served by
        // a thread of their own. On the main run loop each of those events
        // waits for whatever this app is drawing or asking Accessibility,
        // which is felt as click lag in whatever app is in front.
        // A plain port stands in for a tap's: served by the pointer thread and
        // given back, it is invalidated there, on a thread run as input work.
        do {
            var pointerPortContext = CFMachPortContext()
            if let pointerPort = CFMachPortCreate(kCFAllocatorDefault, PointerTapHandBack.received,
                                                  &pointerPortContext, nil),
               let pointerSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, pointerPort, 0) {
                CFMachPortSetInvalidationCallBack(pointerPort, PointerTapHandBack.invalidated)
                PointerTapRunLoop.add(pointerSource)
                PointerTapRunLoop.remove(pointerSource, invalidating: pointerPort)
                let deadline = Date().addingTimeInterval(5)
                while PointerTapHandBack.shared.handedBack == nil, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.005)
                }
                let handedBack = PointerTapHandBack.shared.handedBack
                suite.expect(!CFMachPortIsValid(pointerPort) && handedBack?.onMainThread == false,
                       "the pointer thread hands back the port of every tap it gives up")
                suite.expect(handedBack?.qualityOfService == .userInteractive,
                       "the pointer thread is scheduled as input work")
            } else {
                suite.expect(false, "a plain mach port stands in for a tap's on the pointer thread")
            }
        }
        // The inverter and middle click serve their taps there, never on the
        // main run loop, which bazel/source_lints.py checks.

        // A normal quit forces the mouse-button tap off with the other input
        // taps instead of syncing it, which would wait for the Up of a button
        // still held: that Up never reaches a process going away.
        suite.expect(QuitInputRelease.allCases.contains(.mouseButtonShortcuts),
               "normal termination releases mouse-button tap state instead of waiting for a future Up")
        // A grant re-syncs every feature that declares it, so quit protection
        // is covered by its catalog entry, not by a hand-kept list.
        do {
            let grantDefaults = UserDefaults(suiteName: "vitru.tests.accessibility-grant")!
            grantDefaults.removePersistentDomain(forName: "vitru.tests.accessibility-grant")
            defer { grantDefaults.removePersistentDomain(forName: "vitru.tests.accessibility-grant") }
            grantDefaults.set(true, forKey: AppFeature.quitWindowProtection.availabilityKey)
            let grantLog = PointerGrantLog()
            let grantRuntime = FeatureRuntime(environment: .init(
                defaults: grantDefaults, perform: { grantLog.actions.append($0) },
                availabilityDidChange: {}, savedPreferences: { [:] }))
            grantRuntime.permissionDidChange(.accessibility)
            let afterAccessibility = grantLog.actions
            grantLog.actions.removeAll()
            grantRuntime.permissionDidChange(.screenRecording)
            suite.expect(afterAccessibility.contains(.quitProtection)
                    && !grantLog.actions.contains(.quitProtection),
                   "granting Accessibility starts quit protection without a relaunch")
        }
        // The App Switcher's scroll navigation and a stepped loupe notch end
        // the glide before the raw tick passes; the glide's own frames pass
        // and leave it alone, without the loupe being asked.
        var loupeAsked = false
        let ownFrameEntry = SmoothScrollSupport.wheelEntry(switcherNavigating: false, isOwnEvent: true,
                                                           steppedLoupeWantsRawWheel: { loupeAsked = true; return true })
        suite.expect(SmoothScrollSupport.wheelEntry(switcherNavigating: false, isOwnEvent: false,
                                                    steppedLoupeWantsRawWheel: { true }) == .passThroughEndingGlide
                && SmoothScrollSupport.wheelEntry(switcherNavigating: false, isOwnEvent: false,
                                                  steppedLoupeWantsRawWheel: { false }) == .glide
                && SmoothScrollSupport.wheelEntry(switcherNavigating: true, isOwnEvent: false,
                                                  steppedLoupeWantsRawWheel: { false }) == .passThroughEndingGlide
                && ownFrameEntry == .passThrough && !loupeAsked,
               "entering stepped magnifier zoom cancels the fast glide before passing the raw notch")
        // A refused wheel tap gets one more look while a session switch
        // settles, and never a second: the inverter and smooth scrolling both
        // ask this before scheduling a retry, and a working tap or a stop
        // earns the next refusal its own.
        var wheelTapRetry = TapCreationRetry()
        let wheelTapRefusals = [wheelTapRetry.refused(), wheelTapRetry.refused(), wheelTapRetry.refused()]
        wheelTapRetry.reset()
        suite.expect(wheelTapRefusals == [true, false, false] && wheelTapRetry.refused(),
               "a refused wheel tap is retried once instead of polling forever")

        // The production glide over `GlideRig`: the screen under the pointer,
        // its display links, the timer, the clock and the posted frames are
        // the rig's. A tick is 400 pixels upward.
        func glideTick(_ glide: SmoothScrollGlide) {
            glide.feed(vertical: -10, horizontal: 0, step: 40, flags: [], redirected: false, continuous: false,
                       response: SmoothScrollSupport.defaultResponse, coast: SmoothScrollSupport.defaultCoast)
        }
        // Two frames of one tick, the first lasting `duration` and the
        // second arriving `gap` after it, as the display link reports them.
        func pacedFrames(duration: TimeInterval, gap: TimeInterval) -> [Int32] {
            let paced = GlideRig()
            let pacedGlide = SmoothScrollGlide(environment: paced.environment)
            glideTick(pacedGlide)
            paced.fire("link:2", at: 10, duration: duration)
            paced.fire("link:2", at: 10 + gap, duration: duration)
            return paced.posted
        }
        let quickFrames = pacedFrames(duration: 1.0 / 120.0, gap: 1.0 / 120.0)
        let longFirstFrame = pacedFrames(duration: 1.0 / 30.0, gap: 1.0 / 120.0)
        let longGap = pacedFrames(duration: 1.0 / 120.0, gap: 1.0 / 30.0)
        suite.expect(quickFrames.count == 2 && longFirstFrame.count == 2 && longGap.count == 2
                && abs(longFirstFrame[0]) > abs(quickFrames[0]) && longGap[0] == quickFrames[0]
                && abs(longGap[1]) > abs(quickFrames[1]),
               "smooth scrolling follows the active display's native cadence and elapsed frame time")
        do {
            let rig = GlideRig()
            let glide = SmoothScrollGlide(environment: rig.environment)
            glide.attach()
            glideTick(glide)
            let pacedByDisplay = rig.started == ["link:2"] && glide.isGliding
            rig.display = 3
            rig.screens.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            let followedDisplay = rig.started == ["link:2", "link:3"] && rig.invalidated == ["link:2"]
            rig.fire("link:2", at: 11, duration: 1.0 / 120.0)
            let replacedLinkIgnored = rig.posted.isEmpty
            rig.hasScreen = false
            rig.screens.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            let fellBack = rig.started.last == "timer" && rig.invalidated == ["link:2", "link:3"]
                && rig.posted.count == 1
            rig.screens.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            suite.expect(pacedByDisplay && followedDisplay && replacedLinkIgnored && fellBack
                    && rig.started.filter { $0 == "timer" }.count == 1,
                   "smooth scrolling follows display changes and keeps a no-screen timer fallback")

            let postedBeforeSleep = rig.posted.count
            rig.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
            rig.fireTimers()
            suite.expect(!glide.isGliding && rig.invalidated.last == "timer"
                    && rig.posted.count == postedBeforeSleep,
                   "smooth scrolling cannot carry a pre-sleep glide into the next wake")

            // Stopping releases whichever scheduler runs, and the observers
            // with it: afterwards neither a screen change nor sleep reaches a
            // new glide.
            glideTick(glide)
            glide.detach()
            let releasedTimer = !glide.isGliding && rig.invalidated.last == "timer"
            rig.hasScreen = true
            rig.display = 2
            glideTick(glide)
            glide.detach()
            let releasedLink = !glide.isGliding && rig.invalidated.last == "link:2"
            glideTick(glide)
            let startedAfterStop = rig.started.count
            rig.display = 3
            rig.screens.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            rig.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
            suite.expect(releasedTimer && releasedLink && rig.started.count == startedAfterStop && glide.isGliding,
                   "smooth scrolling releases either scheduler and its lifecycle observers on stop")
            glide.stop()
        }
        // The disabled-tap branch decides with `SessionActivitySupport.tapShouldRun`
        // (checked above) and ends the glide with `SmoothScrollGlide.stop()`
        // (checked here). That the branch does both is still read: the
        // tap-owner session check reads the same branch for its own wiring,
        // and it goes behind a seam together with that check.
        let smoothScrollSource = (try? String(
            contentsOfFile: "Sources/Vitruvian/Services/SmoothScrollService.swift",
            encoding: .utf8)) ?? ""
        let smoothTapDisabled = smoothScrollSource.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
            .components(separatedBy: "tapDisabledByTimeout")
            .dropFirst().first?.components(separatedBy: "return").first ?? ""
        suite.expect(smoothTapDisabled.contains("tapDisabledByUserInput")
                && smoothTapDisabled.contains("stopGlide()")
                && smoothTapDisabled.contains("AppFeature.smoothScroll.isAvailable")
                && smoothTapDisabled.contains("DefaultsKey.smoothScrollEnabled")
                && smoothTapDisabled.contains("AXIsProcessTrusted()")
                && smoothTapDisabled.contains("SessionActivity.shared.isActive"),
               "a disabled smooth-scroll tap drops its tail and re-arms only while fully wanted")
        // Cleaning Mode leaves with the login session: a switched-away session
        // cannot keep a filter tap in the chain, so the lock ends at once, and
        // the features it suspended wait for the session to come back. A tap
        // the window server switched off goes back only into the session on
        // screen, and only with Accessibility. Ending the lock invalidates the
        // tap's port, as the repository contract requires of every tap owner.
        suite.expect(CleaningSessionSupport.sessionChanged(isActive: false, locked: true,
                                                           featuresAwaitSession: false)
                == .endLockKeepingFeaturesSuspended
                && CleaningSessionSupport.sessionChanged(isActive: false, locked: false,
                                                         featuresAwaitSession: false) == .keep
                && CleaningSessionSupport.sessionChanged(isActive: true, locked: false,
                                                         featuresAwaitSession: true) == .resumeSuspendedFeatures
                && CleaningSessionSupport.sessionChanged(isActive: true, locked: false,
                                                         featuresAwaitSession: false) == .keep
                && CleaningSessionSupport.tapDisabled(sessionIsActive: true, accessibilityGranted: true,
                                                      hasTap: true) == .rearm
                && CleaningSessionSupport.tapDisabled(sessionIsActive: false, accessibilityGranted: true,
                                                      hasTap: true) == .endLock(restoreSuspendedFeatures: false)
                && CleaningSessionSupport.tapDisabled(sessionIsActive: true, accessibilityGranted: false,
                                                      hasTap: true) == .endLock(restoreSuspendedFeatures: true),
               "Cleaning Mode ends and releases its filter tap when the login session leaves the screen")

        // MARK: Command-Q / Command-W protection
        suite.expect(QuitProtectionSupport.sanitizedHoldDuration(100) == 250,
               "quit protection clamps a too-short hold duration")
        suite.expect(QuitProtectionSupport.sanitizedHoldDuration(3_000) == 2_000,
               "quit protection clamps an overly long hold duration")
        suite.expect(QuitProtectionSupport.sanitizedHoldDuration(.nan)
                == QuitProtectionSupport.defaultHoldDurationMilliseconds
                && QuitProtectionSupport.sanitizedHoldDuration(.infinity)
                    == QuitProtectionSupport.defaultHoldDurationMilliseconds,
               "quit protection replaces non-finite hold durations with its default")
        suite.expect(QuitProtectionSupport.sanitizedDoublePressInterval(100) == 200,
               "quit protection clamps a too-short double-press interval")
        suite.expect(QuitProtectionSupport.sanitizedDoublePressInterval(3_000) == 1_500,
               "quit protection clamps an overly long double-press interval")
        suite.expect(QuitProtectionSupport.sanitizedDoublePressInterval(.nan)
                == QuitProtectionSupport.defaultDoublePressIntervalMilliseconds
                && QuitProtectionSupport.sanitizedDoublePressInterval(-.infinity)
                    == QuitProtectionSupport.defaultDoublePressIntervalMilliseconds,
               "quit protection replaces non-finite double-press intervals with its default")
        suite.expect(!SettingsBackupSupport.valueLooksRight(
                    DefaultsKey.quitProtectionQuitDoubleIntervalMs, Double.nan)
                && !SettingsBackupSupport.valueLooksRight(
                    DefaultsKey.quitProtectionQuitDoubleIntervalMs, Double.infinity),
               "settings backups reject non-finite numeric preferences")
        suite.expect(QuitProtectionSupport.isWithinDoublePressInterval(
            firstTimestamp: 1_000_000_000,
            secondTimestamp: 2_500_000_000,
            intervalMilliseconds: 1_500
        ), "a second press on the interval edge confirms")
        suite.expect(!QuitProtectionSupport.isWithinDoublePressInterval(
            firstTimestamp: 1_000_000_000,
            secondTimestamp: 2_500_000_001,
            intervalMilliseconds: 1_500
        ), "a second press after the interval starts a new confirmation")
        suite.expect(QuitProtectionSupport.usesNativeQuitRequest(for: .quit)
                && !QuitProtectionSupport.usesNativeQuitRequest(for: .close),
               "quit confirmation asks the target app to terminate while close stays a window shortcut")

        suite.expect(QuitProtectionSupport.scopeAllows(.all, bundleIdentifier: nil, exceptions: []),
               "all-app scope protects even an app without a bundle identifier")
        suite.expect(QuitProtectionSupport.scopeAllows(.selectedOnly,
                                                 bundleIdentifier: "com.example.editor",
                                                 exceptions: ["com.example.editor"]),
               "selected-only scope protects a selected bundle")
        suite.expect(!QuitProtectionSupport.scopeAllows(.selectedOnly,
                                                  bundleIdentifier: "com.example.other",
                                                  exceptions: ["com.example.editor"]),
               "selected-only scope leaves an unselected bundle alone")
        suite.expect(!QuitProtectionSupport.scopeAllows(.allExceptSelected,
                                                  bundleIdentifier: "com.example.editor",
                                                  exceptions: ["com.example.editor"]),
               "all-except scope leaves a selected bundle alone")
        suite.expect(QuitProtectionSupport.scopeAllows(.allExceptSelected,
                                                 bundleIdentifier: "com.example.other",
                                                 exceptions: ["com.example.editor"]),
               "all-except scope protects an unselected bundle")

        suite.expect(QuitProtectionSupport.matchesKey(keyCharacter: "\u{439}", keyCode: 12,
                                                commandLabel: "Q", shortcut: .quit),
               "a Cyrillic layout is protected on the key Command-Q quits from, "
               + "which types \u{439} rather than q")
        suite.expect(!QuitProtectionSupport.matchesKey(keyCharacter: "'", keyCode: 12,
                                                 commandLabel: "'", shortcut: .quit),
               "a Dvorak layout leaves the key Command-Q does not quit from alone")
        suite.expect(QuitProtectionSupport.matchesKey(keyCharacter: "q", keyCode: 0,
                                                commandLabel: nil, shortcut: .quit),
               "quit protection falls back to the typed character without a layout")
        suite.expect(QuitProtectionSupport.matchesKey(keyCharacter: nil, keyCode: 13,
                                                commandLabel: nil, shortcut: .close),
               "quit protection falls back to the W key code with neither a character nor a layout")
        suite.expect(QuitProtectionSupport.isBaseShortcut(keyCharacter: "q", keyCode: 12,
                                                    commandLabel: "Q",
                                                    command: true, control: false,
                                                    option: false, shift: false, shortcut: .quit),
               "plain Command-Q is recognized")
        suite.expect(!QuitProtectionSupport.isBaseShortcut(keyCharacter: "q", keyCode: 12,
                                                     commandLabel: "Q",
                                                     command: true, control: false,
                                                     option: false, shift: true, shortcut: .quit),
               "Shift-Command-Q is not mistaken for plain Command-Q")
        suite.expect(QuitProtectionSupport.isExtraShortcut(keyCharacter: "q", keyCode: 12,
                                                     commandLabel: "Q",
                                                     command: true, control: false,
                                                     option: false, shift: true,
                                                     shortcut: .quit, extraModifier: .shift),
               "Shift-Command-Q is recognized as an extra-modifier confirmation")
        suite.expect(QuitProtectionSupport.isExtraShortcut(keyCharacter: "w", keyCode: 13,
                                                     commandLabel: "W",
                                                     command: true, control: true,
                                                     option: false, shift: false,
                                                     shortcut: .close, extraModifier: .control),
               "Control-Command-W is recognized as an extra-modifier confirmation")
        suite.expect(!QuitProtectionSupport.isExtraShortcut(keyCharacter: "q", keyCode: 12,
                                                      commandLabel: "Q",
                                                      command: true, control: false,
                                                      option: true, shift: false,
                                                      shortcut: .quit, extraModifier: .shift),
               "an unrelated modifier combination is not protected")

        // Feeds the matcher what the tap sees for a key on an installed layout:
        // the bare character the event carries and the Command-table label.
        func layoutProtects(_ layoutID: String, _ keyCode: Int64,
                            _ shortcut: QuitProtectionShortcut) -> Bool? {
            guard let data = testLayoutData(for: layoutID) else { return nil }
            GlobalShortcut.refreshLayoutLabels(layoutData: data)
            return QuitProtectionSupport.matchesKey(
                keyCharacter: GlobalShortcut.layoutKeyLabel(for: keyCode, usesCommand: false),
                keyCode: keyCode,
                commandLabel: GlobalShortcut.layoutKeyLabel(for: keyCode, usesCommand: true),
                shortcut: shortcut)
        }
        let usID = "com.apple.keylayout.US"
        if let quit = layoutProtects(usID, 12, .quit), let close = layoutProtects(usID, 13, .close) {
            suite.expect(quit && close, "US layout keeps Command-Q and Command-W on their own keys")
        }
        let russianID = "com.apple.keylayout.Russian"
        if let quit = layoutProtects(russianID, 12, .quit),
           let close = layoutProtects(russianID, 13, .close) {
            suite.expect(quit && close,
                   "a Cyrillic layout still quits and closes from the Latin Q and W keys")
        }
        let greekID = "com.apple.keylayout.Greek"
        if let quit = layoutProtects(greekID, 12, .quit), let close = layoutProtects(greekID, 13, .close) {
            suite.expect(quit && close, "a Greek layout still quits and closes from the Latin Q and W keys")
        }
        let dvorakID = "com.apple.keylayout.Dvorak"
        if let quit = layoutProtects(dvorakID, 7, .quit), let close = layoutProtects(dvorakID, 43, .close),
           let quote = layoutProtects(dvorakID, 12, .quit) {
            suite.expect(quit && close && !quote,
                   "Dvorak moves Command-Q and Command-W to the keys it types q and w on, "
                   + "and leaves the key that types ' alone")
        }
        let dvorakCommandID = "com.apple.keylayout.DVORAK-QWERTYCMD"
        if let quit = layoutProtects(dvorakCommandID, 12, .quit),
           let close = layoutProtects(dvorakCommandID, 13, .close) {
            suite.expect(quit && close, "the Dvorak layout that reverts to QWERTY under Command is followed there")
        }
        let frenchID = "com.apple.keylayout.French"
        if let quit = layoutProtects(frenchID, 0, .quit), let close = layoutProtects(frenchID, 6, .close) {
            suite.expect(quit && close, "French AZERTY moves Command-Q and Command-W to its own q and w keys")
        }
        GlobalShortcut.refreshLayoutLabels()

        let quitProtectionKeys = [
            DefaultsKey.quitProtectionQuitEnabled,
            DefaultsKey.quitProtectionQuitMode,
            DefaultsKey.quitProtectionQuitHoldDurationMs,
            DefaultsKey.quitProtectionQuitDoubleIntervalMs,
            DefaultsKey.quitProtectionQuitExtraModifier,
            DefaultsKey.quitProtectionQuitScope,
            DefaultsKey.quitProtectionQuitExceptions,
            DefaultsKey.quitProtectionQuitShowFeedback,
            DefaultsKey.quitProtectionCloseEnabled,
            DefaultsKey.quitProtectionCloseMode,
            DefaultsKey.quitProtectionCloseHoldDurationMs,
            DefaultsKey.quitProtectionCloseDoubleIntervalMs,
            DefaultsKey.quitProtectionCloseExtraModifier,
            DefaultsKey.quitProtectionCloseScope,
            DefaultsKey.quitProtectionCloseExceptions,
            DefaultsKey.quitProtectionCloseShowFeedback,
        ]
        suite.expect(quitProtectionKeys.allSatisfy { Defaults.registeredDefaults[$0] != nil },
               "quit and close protection settings have registered defaults")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: Set<String>(quitProtectionKeys)),
               "quit and close protection settings are included in portable backup")

        for language in AppLanguage.allCases {
            let quitProtection = FeatureStrings.quitProtection(language)
            for shortcut in QuitProtectionShortcut.allCases {
                expectFormat(quitProtection.holdHUDFormat(for: shortcut), ["@"],
                             "\(language.rawValue) \(shortcut.rawValue) protection hold HUD format")
                expectFormat(quitProtection.doubleHUDFormat(for: shortcut), ["@"],
                             "\(language.rawValue) \(shortcut.rawValue) protection double HUD format")
                expectFormat(quitProtection.extraHUDFormat(for: shortcut), ["@"],
                             "\(language.rawValue) \(shortcut.rawValue) protection modifier HUD format")
            }
        }

        GlobalShortcut.refreshLayoutLabels()
    }
}

/// The lock guards the time, so the pointer thread may read it.
private nonisolated final class PointerInputTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 0

    func read() -> TimeInterval {
        lock.withLock { value }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { value += interval }
    }
}

/// What the thread that handed a port back looked like. Recorded on that
/// thread and read on the main one, so the lock guards it.
private nonisolated final class PointerTapHandBack: @unchecked Sendable {
    static let shared = PointerTapHandBack()
    /// A port nothing is ever sent to has nothing to receive.
    static let received: CFMachPortCallBack = { _, _, _, _ in }
    /// Written here, outside the main actor: the thread that invalidates the
    /// port calls it, and a closure written in main-actor code would check for
    /// the main thread first and stop the tests.
    static let invalidated: CFMachPortInvalidationCallBack = { _, _ in
        PointerTapHandBack.shared.record(Thread.current)
    }

    private let lock = NSLock()
    private var recorded: (onMainThread: Bool, qualityOfService: QualityOfService)?

    var handedBack: (onMainThread: Bool, qualityOfService: QualityOfService)? {
        lock.withLock { recorded }
    }

    func record(_ thread: Thread) {
        let observed = (onMainThread: thread.isMainThread, qualityOfService: thread.qualityOfService)
        lock.withLock { recorded = observed }
    }
}

/// The binding actions a runtime asked of the live services.
private final class PointerGrantLog {
    var actions: [FeatureBindingAction] = []
}

/// The click filter's outside world for one test: its preference, the
/// session, sleep and wake, the main queue and the tap thread. A started
/// thread waits here until the test runs its body, and no tap is created, so
/// no real click is filtered. Only the test's own thread touches it.
nonisolated final class ClickFilterRig: @unchecked Sendable {
    var wanted = true
    let sessionCenter = NotificationCenter()
    let workspace = NotificationCenter()
    lazy var session = SessionActivity(center: sessionCenter, initialIsActive: { true })
    var threads: [@Sendable () -> Void] = []
    var mainQueue: [@Sendable () -> Void] = []

    var environment: MouseClickDebounceService.Environment {
        MouseClickDebounceService.Environment(
            featureWanted: { [unowned self] in self.wanted },
            windowMilliseconds: { 25 },
            accessibilityGranted: { true },
            session: session,
            workspaceNotifications: workspace,
            main: { [unowned self] work in self.mainQueue.append(work) },
            startThread: { [unowned self] body in self.threads.append(body) },
            createTap: { _ in nil })
    }

    /// Runs each started thread to its end, as the tap thread would.
    func runThreads() {
        while !threads.isEmpty { threads.removeFirst()() }
    }

    func drainMain() {
        while !mainQueue.isEmpty { mainQueue.removeFirst()() }
    }
}

/// The smooth-scroll glide's outside world for one test: the screen under
/// the pointer, the display links and timers it starts, the clock and the
/// frames it posts. Nothing reaches a screen or the event stream.
final class GlideRig {
    var hasScreen = true
    var display: CGDirectDisplayID? = 2
    /// Each scheduler started and invalidated, as "link:<display>" or "timer".
    var started: [String] = []
    var invalidated: [String] = []
    /// The vertical distance of every posted frame.
    var posted: [Int32] = []
    let screens = NotificationCenter()
    let workspace = NotificationCenter()
    private var linkFrames: [String: @MainActor (TimeInterval, TimeInterval) -> Void] = [:]
    private var timerFires: [@MainActor @Sendable () -> Void] = []

    var environment: SmoothScrollGlide.Environment {
        SmoothScrollGlide.Environment(
            screenUnderPointer: { [unowned self] in
                guard self.hasScreen else { return nil }
                let label = "link:\(self.display ?? 0)"
                return SmoothScrollGlide.Screen(displayID: self.display, startDisplayLink: { [unowned self] frame in
                    self.started.append(label)
                    self.linkFrames[label] = frame
                    return SmoothScrollGlide.Scheduler(invalidate: { [unowned self] in self.invalidated.append(label) })
                })
            },
            startTimer: { [unowned self] _, fire in
                self.started.append("timer")
                self.timerFires.append(fire)
                return SmoothScrollGlide.Scheduler(invalidate: { [unowned self] in self.invalidated.append("timer") })
            },
            uptime: { 100 },
            post: { [unowned self] vertical, _, _ in self.posted.append(vertical) },
            screenNotifications: screens,
            sleepNotifications: workspace)
    }

    /// A frame from the display link started under `label`.
    func fire(_ label: String, at timestamp: TimeInterval, duration: TimeInterval) {
        linkFrames[label]?(timestamp, duration)
    }

    /// One tick of every timer started so far.
    func fireTimers() {
        for fire in timerFires { fire() }
    }
}
