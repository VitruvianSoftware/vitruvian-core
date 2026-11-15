// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import VitruvianAtriumCore
import VitruvianAtriumServices

extension NotchPresentationRefreshContract {
    /// A game's own full screen, read once a second on a real island with an
    /// inert window. The window list is the fixture's; nothing is read.
    static func appFullscreenChecks(_ suite: TestSuite) {
        let hides = defaults.bool(forKey: DefaultsKey.notchHideInFullscreen)
        defer { defaults.set(hides, forKey: DefaultsKey.notchHideInFullscreen) }
        defaults.set(false, forKey: DefaultsKey.notchHideInFullscreen)
        let fixture = island()
        suite.expect(fixture.appFullscreenTick == nil,
                     "with full-screen hiding off, the island reads no window list")
        defaults.set(true, forKey: DefaultsKey.notchHideInFullscreen)
        fixture.island.syncWithPreferences()
        suite.expect(fixture.appFullscreenTick != nil && !fixture.island.hiddenInFullscreen,
                     "with full-screen hiding on, the island reads the frontmost app's windows each second")
        fixture.appFullscreen = [fixture.displays[0].id]
        fixture.appFullscreenTick?()
        suite.expect(fixture.island.hiddenInFullscreen,
                     "a game going full screen while it stays frontmost hides the island at the next read")
        fixture.appFullscreen = []
        fixture.appFullscreenTick?()
        suite.expect(!fixture.island.hiddenInFullscreen, "leaving a game's own full screen brings the island back")
        // An app's own full screen changes nothing else on screen, so the
        // island eases away and comes back in from the screen edge, as it
        // does at any hide. A full-screen Space slides the whole screen, so
        // the island goes and returns with it at once.
        suite.expect(fixture.host?.presentAnimations.last == true && fixture.host?.revealFromHidden == true,
                     "leaving a game's own full screen reveals the island from the screen edge, with motion")
        fixture.appFullscreen = [fixture.displays[0].id]
        fixture.appFullscreenTick?()
        fixture.fullscreen = [fixture.displays[0].id]
        fixture.appFullscreen = []
        fixture.appFullscreenTick?()
        suite.expect(fixture.island.hiddenInFullscreen,
                     "a full-screen Space taking over a game's own full screen keeps the island away")
        fixture.fullscreen = []
        fixture.post(workspace: NSWorkspace.activeSpaceDidChangeNotification)
        suite.expect(!fixture.island.hiddenInFullscreen && fixture.host?.presentAnimations.last == false
                     && fixture.host?.revealFromHidden == false,
                     "full screen last held by a Space brings the island back at once")
        defaults.set(false, forKey: DefaultsKey.notchHideInFullscreen)
        fixture.island.syncWithPreferences()
        suite.expect(fixture.appFullscreenTick == nil, "turning full-screen hiding off stops the reads")
        fixture.island.stop()
    }
}
