// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import VitruvianCore

/// The last visible compact track stays intact while its island retracts.
struct NotchCompactMusicSnapshot {
    let playback: NotchPlayback
    let artwork: NSImage?
    let tint: NotchArtworkTint?
    let geometry: NotchGeometry
}
