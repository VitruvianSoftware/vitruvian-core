// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// What the music page offers below its player: the mixer, and the lyrics and
/// queue buttons. The page's size and its drawing both read it here, so the
/// island never reserves a row the page leaves empty, or squeezes the player
/// under one it did not reserve.
package struct NotchMusicControls: Equatable {
    package let mixer: Bool
    package let lyrics: Bool
    package let queue: Bool

    package init(mixer: Bool, lyrics: Bool, queue: Bool) {
        self.mixer = mixer
        self.lyrics = lyrics
        self.queue = queue
    }

    /// Lyrics and the queue count once their switch is on and their feature
    /// is available. Whether the island shows Music at all is the page's own
    /// question: the Settings preview draws the page either way.
    package init(lyricsEnabled: Bool, queueEnabled: Bool, in defaults: UserDefaults = .standard) {
        self.init(mixer: AppFeature.mixer.isAvailable(in: defaults),
                  lyrics: lyricsEnabled && AppFeature.notchLyrics.isAvailable(in: defaults),
                  queue: queueEnabled && AppFeature.notchQueue.isAvailable(in: defaults))
    }

    package init(in defaults: UserDefaults = .standard) {
        self.init(lyricsEnabled: defaults.bool(forKey: DefaultsKey.notchLyricsEnabled),
                  queueEnabled: defaults.bool(forKey: DefaultsKey.notchQueueEnabled), in: defaults)
    }

    /// Whether the page draws a row of controls at all.
    package var hasRow: Bool { mixer || lyrics || queue }
}
