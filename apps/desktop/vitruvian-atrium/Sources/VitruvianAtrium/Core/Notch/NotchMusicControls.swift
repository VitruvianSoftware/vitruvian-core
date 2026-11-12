// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// What the music page offers beside its player: the lyrics and queue
/// buttons, each once its switch is on and its feature is available.
package struct NotchMusicControls: Equatable {
    package let lyrics: Bool
    package let queue: Bool

    package init(lyrics: Bool, queue: Bool) {
        self.lyrics = lyrics
        self.queue = queue
    }

    /// Whether the island shows Music at all is the page's own question: the
    /// Settings preview draws the page either way.
    package init(lyricsEnabled: Bool, queueEnabled: Bool, in defaults: UserDefaults = .standard) {
        self.init(lyrics: lyricsEnabled && AppFeature.notchLyrics.isAvailable(in: defaults),
                  queue: queueEnabled && AppFeature.notchQueue.isAvailable(in: defaults))
    }
}
