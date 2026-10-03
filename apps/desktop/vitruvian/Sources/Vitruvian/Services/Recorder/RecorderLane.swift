// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Which lane of the recorder editor's rail this is. They behave identically on
/// purpose: one set of gestures to learn, whatever kind of thing is on the rail.
enum RecorderLaneKind {
    case zoom
    case text
    case image
    case blur
}

/// One block on a lane, whatever it happens to be.
struct RecorderLaneItem {
    let id: UUID
    let start: Double
    let end: Double
    let label: String
    let glyph: String
}
