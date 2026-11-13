// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What a click outside the island's window does. Pinning, menus, sheets and
/// the other working surfaces keep the island, as do the island's own area, a
/// visible copy of it on another display, its status item and the
/// Accessibility Keyboard. A screenshot preview closes through its controller,
/// which keeps it while a share link is still being made; anything else
/// collapses.
package enum NotchClickElsewhere {
    package enum Outcome: Equatable {
        case keep
        case collapse
        case dismissPreview
    }

    package static func outcome(keepsSurface: Bool, overIsland: Bool, overVisibleCopy: Bool,
                                overStatusItem: Bool, overAssistiveKeyboard: Bool,
                                showsCapturePreview: Bool) -> Outcome {
        guard !keepsSurface, !overIsland, !overVisibleCopy, !overStatusItem,
              !overAssistiveKeyboard else { return .keep }
        return showsCapturePreview ? .dismissPreview : .collapse
    }

    /// Closing a preview while a share link is being made would delete that link.
    package static func closesPreview(sharing: Bool) -> Bool { !sharing }
}
