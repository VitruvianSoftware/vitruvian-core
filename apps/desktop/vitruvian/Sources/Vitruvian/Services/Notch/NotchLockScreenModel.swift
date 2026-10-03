// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import VitruvianCore

/// What the lock screen may show, settled when it appears: preferences cannot
/// change while the Mac is locked, so the views never read them again.
final class NotchLockScreenModel: ObservableObject {
    struct Gates: Equatable {
        var music = false
        var timer = false
        var agents = false
        var downloads = false
        var countdown = false
        var timeLeft = false
    }

    @Published var gates = Gates()
    /// Kept for the whole time the Mac stays locked, across the display
    /// sleeping and waking, and cleared once it unlocks.
    @Published var playedWhileLocked = false
    @Published var padlockOpen = false

    func showsMusic(_ playback: NotchPlayback?) -> Bool {
        gates.music && playback.map {
            NotchLockScreenSupport.showsMusic(isPlaying: $0.isPlaying, playedWhileLocked: playedWhileLocked)
        } == true
    }
}
