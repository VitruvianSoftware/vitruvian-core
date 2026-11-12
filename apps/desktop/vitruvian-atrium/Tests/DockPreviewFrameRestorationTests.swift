// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

enum DockPreviewFrameRestorationTests {
    typealias Restoration = DockPreviewFrameRestoration
    static let item = SwitcherItem(id: "window", title: "Window", appName: "App", pid: 10, windowOwnerPID: 11,
                                   windowID: 12, isOnScreen: true, isAppHidden: false, isMinimized: false,
                                   isFullscreen: false, isOnHiddenSpace: false, frame: .zero)
    static var currentScreen: Restoration.Screen?
    static var focused: CGWindowID? = 12
    static var frontmost: pid_t? = 10
    static var restores = 0
    static var checks = 0
    /// Each wait the restore asks for, and the check it schedules, run one at a time.
    static var delays: [TimeInterval] = []
    static var pending: [@MainActor () -> Void] = []
    static let host = Restoration.RestoreHost(
        screen: { _ in currentScreen.map { ($0.frame, $0.visibleFrame) } },
        frontmostPID: { frontmost },
        focusedWindow: { _ in focused },
        restore: { _, _, _ in restores += 1 },
        after: { delay, work in
            // The restore is only ever started on the test's thread.
            MainActor.assumeIsolated {
                delays.append(delay)
                pending.append(work)
            }
        })

    static func step() {
        guard !pending.isEmpty else { return }
        pending.removeFirst()()
    }

    static func run(_ suite: TestSuite) {
        let original = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let bottom = CGRect(x: 0, y: 25, width: 1440, height: 810)
        let left = CGRect(x: 65, y: 25, width: 1375, height: 875)
        let right = CGRect(x: 0, y: 25, width: 1375, height: 875)
        for visible in [bottom, left, right] {
            suite.expect(DockPreviewFrameSupport.wasConstrained(visible, original: original, visibleFrame: visible),
                         "a maximized window recovers from a bottom or side Dock constraint")
        }
        let custom = CGRect(x: 100, y: 400, width: 700, height: 500)
        suite.expect(DockPreviewFrameSupport.wasConstrained(custom.intersection(bottom), original: custom,
                                                           visibleFrame: bottom),
                     "a partially clipped custom size can be restored without maximizing it")
        suite.expect(DockPreviewFrameSupport.wasConstrained(custom.offsetBy(dx: 0, dy: -65), original: custom,
                                                           visibleFrame: bottom),
                     "a window moved above the Dock keeps its original position and size")
        for actual in [original, CGRect(x: 100, y: 100, width: 600, height: 400),
                       bottom.offsetBy(dx: 20, dy: 0), .zero] {
            suite.expect(!DockPreviewFrameSupport.wasConstrained(actual, original: original, visibleFrame: bottom),
                         "unchanged, manually moved, resized and missing windows are left alone")
        }
        suite.expect(!DockPreviewFrameSupport.wasConstrained(bottom, original: original, visibleFrame: original),
                     "no window is restored when the Dock did not reduce the work area")
        let secondaryOffset = CGVector(dx: -1440, dy: -900)
        suite.expect(DockPreviewFrameSupport.wasConstrained(
            left.offsetBy(dx: secondaryOffset.dx, dy: secondaryOffset.dy),
            original: original.offsetBy(dx: secondaryOffset.dx, dy: secondaryOffset.dy),
            visibleFrame: left.offsetBy(dx: secondaryOffset.dx, dy: secondaryOffset.dy)),
                     "secondary screens with negative global coordinates preserve their geometry")

        let screen = Restoration.Screen(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                        visibleFrame: original)
        func restore(attempt: Int = 0, isCurrent: @escaping @MainActor @Sendable () -> Bool = { true }) {
            Restoration.restore(item, original: original, screen: screen, heldVisibleFrame: bottom,
                                isCurrent: isCurrent, attempt: attempt, host: host)
        }
        currentScreen = Restoration.Screen(id: 1, frame: screen.frame, visibleFrame: bottom)
        restores = 0
        delays = []
        pending = []
        restore()
        step()
        suite.expect(restores == 0 && pending.count == 1,
                     "activation never restores against the Dock-reduced work area, and checks again")
        currentScreen = screen
        step()
        suite.expect(restores == 1 && pending.isEmpty, "the selected window is restored once the work area recovers")
        suite.expect(delays == [0.15, 0.05], "the first check waits for the hold to end, later ones come sooner")

        for scenario in 0..<5 {
            currentScreen = screen
            focused = scenario == 0 ? 99 : 12
            frontmost = scenario == 4 ? 99 : 10
            if scenario == 1 { currentScreen = nil }
            if scenario == 2 { currentScreen?.frame.size.width = 1280 }
            checks = 0
            restore(isCurrent: { checks += 1; return scenario != 3 })
            step()
            suite.expect(checks == 1 && restores == 1 && pending.isEmpty,
                         "focus changes, another app in front, disconnected or reconfigured displays and newer holds cancel restoration")
        }
        focused = 12
        frontmost = 10
        currentScreen = Restoration.Screen(id: 1, frame: screen.frame, visibleFrame: bottom)
        checks = 0
        restore(attempt: 15, isCurrent: { checks += 1; return true })
        step()
        currentScreen = screen
        step()
        suite.expect(checks == 1 && restores == 1 && pending.isEmpty,
                     "an unrecovered work area has a bounded retry budget")
    }
}
