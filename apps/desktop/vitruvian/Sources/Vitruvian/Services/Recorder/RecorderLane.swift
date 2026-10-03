// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Which lane of the recorder editor's rail this is. They behave identically on
/// purpose: one set of gestures to learn, whatever kind of thing is on the rail.
package enum RecorderLaneKind {
    case zoom
    case text
    case image
    case blur
}

/// One block on a lane, whatever it happens to be.
package struct RecorderLaneItem {
    package let id: UUID
    package let start: Double
    package let end: Double
    package let label: String
    package let glyph: String

    // Spelled out because a memberwise initializer never leaves its module.
    package init(id: UUID, start: Double, end: Double, label: String, glyph: String) {
        self.id = id
        self.start = start
        self.end = end
        self.label = label
        self.glyph = glyph
    }
}
