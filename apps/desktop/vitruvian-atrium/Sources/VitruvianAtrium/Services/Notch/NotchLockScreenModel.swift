// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign

/// What the lock screen may show, settled when it appears: preferences cannot
/// change while the Mac is locked, so the views never read them again.
@MainActor
package final class NotchLockScreenModel: ObservableObject {
    package struct Gates: Equatable {
        package var music = false
        package var timer = false
        package var agents = false
        package var downloads = false
        package var countdown = false
        package var timeLeft = false

        // Spelled out because a memberwise initializer never leaves its module.
        package init(music: Bool = false, timer: Bool = false, agents: Bool = false, downloads: Bool = false, countdown: Bool = false, timeLeft: Bool = false) {
            self.music = music
            self.timer = timer
            self.agents = agents
            self.downloads = downloads
            self.countdown = countdown
            self.timeLeft = timeLeft
        }
    }

    @Published package var gates = Gates()
    /// Kept for the whole time the Mac stays locked, across the display
    /// sleeping and waking, and cleared once it unlocks.
    @Published package var playedWhileLocked = false
    @Published package var padlockOpen = false

    package func showsMusic(_ playback: NotchPlayback?) -> Bool {
        gates.music && playback.map {
            NotchLockScreenSupport.showsMusic(isPlaying: $0.isPlaying, playedWhileLocked: playedWhileLocked)
        } == true
    }
}
