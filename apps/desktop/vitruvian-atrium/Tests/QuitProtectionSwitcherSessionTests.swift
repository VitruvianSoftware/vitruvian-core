// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import VitruvianAtriumServices

/// The native Command-Tab switcher as quit protection follows it from the
/// tap's events. Only values are built; no event reaches the system.
enum QuitProtectionSwitcherSessionTests {
    static func run(_ suite: TestSuite) {
        var session = NativeSwitcherSession()
        var periodAsked = 0
        func send(_ key: Int64, _ type: CGEventType = .keyDown, flags: CGEventFlags = .maskCommand,
                  period: Bool = false) {
            session.observe(type, flags: flags, keyCode: key) { periodAsked += 1; return period }
        }

        send(12)
        suite.expect(!session.isActive && periodAsked == 0,
                     "Command-Q alone opens no switcher and never reads the keyboard layout")
        send(48)
        suite.expect(session.isActive, "Command-Tab opens the native switcher")
        send(48, .keyUp)
        send(48, flags: [.maskCommand, .maskShift])
        send(12)
        suite.expect(session.isActive, "Tab up, reverse navigation and its Q keep the switcher open")
        send(0, .flagsChanged, flags: [])
        suite.expect(!session.isActive, "letting go of Command closes the switcher")

        send(48)
        send(53)
        suite.expect(!session.isActive, "Escape dismisses the switcher")
        send(48)
        let askedBefore = periodAsked
        send(47, period: true)
        suite.expect(!session.isActive && periodAsked == askedBefore + 1, "Command-period dismisses the switcher")
        send(48)
        send(47, period: false)
        suite.expect(session.isActive, "a key that is not a period on this layout leaves the switcher open")
        session.end()
        suite.expect(!session.isActive, "a stopped tap forgets the switcher")

        send(48, flags: [.maskCommand, .maskControl])
        send(48, flags: [.maskCommand, .maskAlternate])
        suite.expect(!session.isActive, "Control or Option with Command-Tab is not the native switcher")

        // The live switcher shortcut decides, read only on Command key downs.
        var tableReads = 0
        func sendLive(_ key: Int64, _ type: CGEventType = .keyDown, flags: CGEventFlags = .maskCommand,
                      opens: Bool) {
            session.observe(type, flags: flags, keyCode: key, opensSwitcher: { tableReads += 1; return opens }) {
                false
            }
        }
        sendLive(48, opens: false)
        suite.expect(!session.isActive && tableReads == 1,
                     "Command-Tab with the system row off or remapped opens no native switcher")
        sendLive(50, opens: true)
        suite.expect(session.isActive, "a remapped system switcher key opens the native switcher")
        sendLive(50, .keyUp, opens: true)
        sendLive(0, .flagsChanged, flags: [], opens: true)
        sendLive(6, flags: [], opens: true)
        suite.expect(!session.isActive && tableReads == 2,
                     "key ups, modifier changes and typing without Command never read the shortcut table")
    }
}
