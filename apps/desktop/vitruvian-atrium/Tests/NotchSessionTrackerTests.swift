// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Drives the island's session tracker through notification centers of its
/// own, with no delivery queue, so each posted notification is applied before
/// the next line runs. The tracker is the module's own type, not a copy.
enum NotchSessionTrackerTests {
    static func run(_ suite: TestSuite) {
        let workspace = NotificationCenter()
        let distributed = NotificationCenter()
        let tracker = NotchSessionTracker(workspace: workspace, distributed: distributed, queue: nil)
        var state = NotchSessionState()
        var reports = 0
        tracker.start { change in
            reports += 1
            change(&state)
        }
        func post(_ center: NotificationCenter, _ name: Notification.Name) { center.post(name: name, object: nil) }
        func post(_ center: NotificationCenter, _ name: String) { post(center, Notification.Name(name)) }

        post(workspace, NSWorkspace.willSleepNotification)
        suite.expect(state.sleeping && !state.canPresent, "system sleep suspends the island")
        post(distributed, "com.apple.screensaver.didstart")
        post(workspace, NSWorkspace.didWakeNotification)
        suite.expect(!state.sleeping && !state.screenSaverRunning,
                     "waking ends sleep and any screen saver whose stop went unannounced")

        post(workspace, NSWorkspace.screensDidSleepNotification)
        suite.expect(state.displaysSleeping && state.canRunTimer && !state.canPresent,
                     "a dark display hides the island but keeps the timer running")
        post(workspace, NSWorkspace.screensDidWakeNotification)
        suite.expect(!state.displaysSleeping && state.canPresent, "a lit display shows the island again")

        post(workspace, NSWorkspace.sessionDidResignActiveNotification)
        suite.expect(!state.onConsole && !state.canRunTimer, "another user at the console stops the timer")
        post(workspace, NSWorkspace.sessionDidBecomeActiveNotification)
        suite.expect(state.onConsole, "the console coming back restores the session")

        post(distributed, "com.apple.screenIsLocked")
        suite.expect(state.locked && state.showsLockScreen, "locking shows the lock screen")
        post(distributed, "com.apple.screensaver.didstart")
        suite.expect(state.screenSaverRunning && !state.showsLockScreen, "a screen saver covers the lock screen")
        post(distributed, "com.apple.screenIsUnlocked")
        suite.expect(!state.locked && !state.screenSaverRunning,
                     "an unlock ends any screen saver, announced or not")
        post(distributed, "com.apple.screensaver.didstart")
        post(distributed, "com.apple.screensaver.didstop")
        suite.expect(!state.screenSaverRunning, "a screen saver's stop is followed")

        let before = reports
        post(workspace, Notification.Name("com.apple.screenIsLocked"))
        post(distributed, NSWorkspace.willSleepNotification)
        suite.expect(reports == before && !state.locked && !state.sleeping,
                     "each notification is read only from the center that sends it")

        tracker.start { change in
            reports += 1
            change(&state)
        }
        post(workspace, NSWorkspace.willSleepNotification)
        suite.expect(reports == before + 1, "starting again replaces the observers instead of adding a second set")

        tracker.stop()
        post(workspace, NSWorkspace.didWakeNotification)
        post(distributed, "com.apple.screenIsLocked")
        suite.expect(reports == before + 1 && state.sleeping && !state.locked, "a stopped tracker reports nothing")
    }
}
