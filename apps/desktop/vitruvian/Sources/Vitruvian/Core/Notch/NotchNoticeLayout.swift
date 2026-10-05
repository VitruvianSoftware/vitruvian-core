// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit

/// A text notice beside the camera: its symbol and text on one side, the
/// detail on the other. The island sizes its wings with these, and
/// `NotchNoticeView` draws with them.
package enum NotchNoticeLayout {
    /// The symbol's column, and the space between it and the text.
    package static let symbolWidth: CGFloat = 18
    package static let spacing: CGFloat = 8
    /// The inset from the island's curved end.
    package static let inset: CGFloat = 16
    /// The narrowest wing a notice or a banner takes.
    package static let minimumWing: CGFloat = 88
    package static let textSize: CGFloat = 11
    // NSFont is immutable once made, so any thread may share it.
    /// The text measured in the font it is drawn in.
    nonisolated(unsafe) package static let font = NSFont.monospacedDigitSystemFont(ofSize: textSize, weight: .medium)

    /// The inset a wing keeps from the curved end; a narrow one keeps a sixth of itself.
    package static func inset(wing: CGFloat) -> CGFloat { min(inset, wing / 6) }
}
