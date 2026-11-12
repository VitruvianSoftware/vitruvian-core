// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit

/// What the island asks of the services that follow it.
///
/// The Shelf, the brightness keys and the precise volume roller each read the
/// island (`NotchService.shared`) to decide whether it shows their feedback or
/// takes their files. The island used to call back into each of them by name,
/// so every pair was a `.shared` cycle. Now the composition root
/// (`main.swift`) fills this in, and the island names none of them.
///
/// Every hook defaults to doing nothing, which is what the island needs when
/// nothing follows it, as in a test.
package struct NotchCollaborators {
    /// The island started or stopped taking volume and brightness feedback:
    /// the keys go back to the system while nothing can show them.
    package var feedbackRoutingDidChange: () -> Void
    /// The island's file routing changed, so the Shelf resyncs.
    package var fileRoutingDidChange: () -> Void
    /// Whether the Shelf would take what is being dragged over the island.
    package var shelfCanAccept: (NSPasteboard) -> Bool
    /// Hands files dropped on the island to the Shelf; false when it took none.
    package var shelfAccept: (NSPasteboard) -> Bool
    /// The island closed around the Command Bar on its own, from a click
    /// away or a page opened in its place, so the bar closes too.
    package var commandBarIslandDidClose: () -> Void

    package init(feedbackRoutingDidChange: @escaping () -> Void = {},
                 fileRoutingDidChange: @escaping () -> Void = {},
                 shelfCanAccept: @escaping (NSPasteboard) -> Bool = { _ in false },
                 shelfAccept: @escaping (NSPasteboard) -> Bool = { _ in false },
                 commandBarIslandDidClose: @escaping () -> Void = {}) {
        self.feedbackRoutingDidChange = feedbackRoutingDidChange
        self.fileRoutingDidChange = fileRoutingDidChange
        self.shelfCanAccept = shelfCanAccept
        self.shelfAccept = shelfAccept
        self.commandBarIslandDidClose = commandBarIslandDidClose
    }
}
