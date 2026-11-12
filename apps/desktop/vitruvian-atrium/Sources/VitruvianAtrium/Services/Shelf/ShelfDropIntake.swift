// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit

/// What the shelf does with a drop. Promised files go to native delivery
/// together with the plain items dropped alongside them; anything else is
/// read from the pasteboard now. A drop onto the docked shelf completes the
/// dock. Native destinations call this synchronously from
/// `performDragOperation`, while the sender can still fulfil file promises.
package struct ShelfDropIntake {
    /// The shelf is available and switched on.
    package var enabled: () -> Bool
    /// The files the pasteboard promises.
    package var promises: (NSPasteboard) -> [NSFilePromiseReceiver]
    /// Starts receiving promised files with the pasteboard's other items,
    /// onto the shelf or merged into the item with the given id.
    package var receive: (_ receivers: [NSFilePromiseReceiver], _ pasteboard: NSPasteboard, _ target: UUID?) -> Bool
    /// Reads the pasteboard onto the shelf, or merges it into the item with
    /// the given id.
    package var add: (_ pasteboard: NSPasteboard, _ target: UUID?) -> Bool
    /// The docked shelf's window, if there is one.
    package var dock: () -> AnyObject?
    package var dockDidAccept: () -> Void
    /// Marks the shelf as in use. A promised file reaches the shelf, and
    /// with it the interaction, only once its asynchronous delivery
    /// completes, which can be after the grace window in `endEdgePeekDrag`
    /// has retracted an edge peek. Noting the drop clears the peek first, so
    /// that retract does nothing.
    package var noteInteraction: () -> Void

    package init(enabled: @escaping () -> Bool,
                 promises: @escaping (NSPasteboard) -> [NSFilePromiseReceiver],
                 receive: @escaping (_ receivers: [NSFilePromiseReceiver], _ pasteboard: NSPasteboard,
                                     _ target: UUID?) -> Bool,
                 add: @escaping (_ pasteboard: NSPasteboard, _ target: UUID?) -> Bool,
                 dock: @escaping () -> AnyObject?, dockDidAccept: @escaping () -> Void,
                 noteInteraction: @escaping () -> Void) {
        self.enabled = enabled
        self.promises = promises
        self.receive = receive
        self.add = add
        self.dock = dock
        self.dockDidAccept = dockDidAccept
        self.noteInteraction = noteInteraction
    }

    /// Takes a drop onto the shelf, or into the item `target`.
    package func accept(_ pasteboard: NSPasteboard, into target: UUID? = nil) -> Bool {
        guard enabled() else { return false }
        let receivers = promises(pasteboard)
        return receivers.isEmpty ? add(pasteboard, target) : receive(receivers, pasteboard, target)
    }

    /// Takes a drop that landed in `destination`, completing the dock when
    /// that is the docked shelf, and noting the interaction at drop time.
    package func accept(_ pasteboard: NSPasteboard, into target: UUID? = nil, destination: AnyObject?) -> Bool {
        let accepted = accept(pasteboard, into: target)
        if accepted {
            if destination === dock() { dockDidAccept() }
            noteInteraction()
        }
        return accepted
    }
}
