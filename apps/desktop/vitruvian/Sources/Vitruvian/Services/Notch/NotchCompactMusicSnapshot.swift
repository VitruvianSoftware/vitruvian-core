// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import VitruvianCore
import VitruvianDesign

/// The last visible compact track stays intact while its island retracts.
package struct NotchCompactMusicSnapshot {
    package let playback: NotchPlayback
    package let artwork: NSImage?
    package let tint: NotchArtworkTint?
    package let geometry: NotchGeometry
    /// The left side of a strip that was naming its song.
    package var namedWing: CGFloat? = nil
    /// A capsule that was naming its song for the pointer.
    package var namesSong = false

    // Spelled out because a memberwise initializer never leaves its module.
    package init(playback: NotchPlayback, artwork: NSImage?, tint: NotchArtworkTint?, geometry: NotchGeometry) {
        self.playback = playback
        self.artwork = artwork
        self.tint = tint
        self.geometry = geometry
    }
}
