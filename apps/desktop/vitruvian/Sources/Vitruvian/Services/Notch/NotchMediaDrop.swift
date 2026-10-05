// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// The island's media tools as a drop destination. They take a drop only
/// while they are offered and not already working, and only when every
/// dragged item is a file that one tool optimizes. A drop with promised files
/// or other items stays on the shelf, where every companion is kept.
package struct NotchMediaDrop {
    /// The tools are offered as a destination now.
    package var offered: () -> Bool
    /// The tools are already working.
    package var busy: () -> Bool
    /// Opens a tool on its inputs, reporting whether it took them.
    package var openMedia: (MediaTool, [URL]) -> Bool

    package init(offered: @escaping () -> Bool, busy: @escaping () -> Bool,
                 openMedia: @escaping (MediaTool, [URL]) -> Bool) {
        self.offered = offered
        self.busy = busy
        self.openMedia = openMedia
    }

    /// The tools can take a drop now.
    package var accepts: Bool {
        !busy() && offered()
    }

    /// The tool a drop would open, with its inputs, or nil when it belongs on
    /// the shelf.
    package func content(for pasteboard: NSPasteboard) -> (tool: MediaTool, inputs: [URL])? {
        guard offered(),
              !pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil) else { return nil }
        let inputs = ShelfPasteboardSupport.fileURLs(from: pasteboard)
        // Mixed payloads stay in the shelf, where every companion is preserved.
        guard inputs.count >= (pasteboard.pasteboardItems?.count ?? 0) else { return nil }
        guard let tool = NotchFileToolsSupport.optimizationTool(for: inputs) else { return nil }
        return (tool, inputs)
    }

    /// Opens the tool the drop asks for, reporting whether it took the drop.
    package func open(_ pasteboard: NSPasteboard) -> Bool {
        guard accepts, let content = content(for: pasteboard) else { return false }
        return openMedia(content.tool, content.inputs)
    }
}
