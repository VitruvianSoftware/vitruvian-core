// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit

/// A drag over the island's canvas. The canvas says where the drag is and
/// whether that point is on the visible island; this decides whether the drag
/// is taken and hands it to the island's file drop actions. Drags from inside
/// the app keep their own reorder and merge destinations.
@MainActor
package final class NotchCanvasDrop {
    /// What the island does with a drop, or nil while it takes none.
    package var actions: NotchFileDropActions? {
        didSet { if actions == nil { accepting = false } }
    }
    /// The drag over the canvas is being taken.
    package private(set) var accepting = false

    package init() {}

    /// A drag arrived. `localSource` drags come from inside the app.
    package func begin(_ pasteboard: NSPasteboard, localSource: Bool) -> NSDragOperation {
        accepting = !localSource && actions?.canAccept(pasteboard) == true
        if accepting { actions?.enter(pasteboard) }
        return accepting ? .copy : []
    }

    /// Delivers a taken drag, and only once.
    package func finish(_ pasteboard: NSPasteboard) -> Bool {
        guard accepting else { return false }
        defer { exit() }
        return actions?.accept(pasteboard) == true
    }

    /// The drag moved to `point` in the canvas, on the visible island or off it.
    package func update(_ pasteboard: NSPasteboard, at point: CGPoint, visible: Bool,
                        localSource: Bool) -> NSDragOperation {
        guard visible else {
            if accepting { exit() }
            return []
        }
        let operation = accepting ? .copy : begin(pasteboard, localSource: localSource)
        if accepting, actions?.update?(point) == false { return [] }
        return operation
    }

    /// The drag left the canvas.
    package func exit() {
        accepting = false
        actions?.exit()
    }

    /// The drag was released at `point`. The release point is checked again,
    /// whatever the last update targeted.
    package func perform(_ pasteboard: NSPasteboard, at point: CGPoint, visible: Bool) -> Bool {
        guard visible, !(accepting && actions?.update?(point) == false) else {
            exit()
            return false
        }
        return finish(pasteboard)
    }
}
