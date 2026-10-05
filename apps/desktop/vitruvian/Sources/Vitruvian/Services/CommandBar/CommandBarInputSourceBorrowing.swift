// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore

/// The bar's own keyboard layout: an ASCII layout borrowed when the bar
/// opens and the person's own source put back when it closes or the app
/// quits. `CommandBarService` owns it and says which presentation is
/// current; tests pass a `System` of doubles, so nothing here can switch a
/// real input source.
@MainActor
package final class CommandBarInputSourceBorrowing {
    /// The preference, the Text Input Sources calls and the main loop.
    @MainActor
    package struct System {
        /// Whether borrowing is turned on, read fresh on every open.
        package var isEnabled: () -> Bool
        package var currentSourceID: () -> String?
        package var snapshots: () -> [InputSourceSelection.Snapshot]
        /// Answers whether the system took the request.
        package var select: (_ sourceID: String) -> Bool
        /// Runs work on the next turn of the main loop.
        package var nextTurn: (@escaping @MainActor @Sendable () -> Void) -> Void

        package init(isEnabled: @escaping () -> Bool,
                     currentSourceID: @escaping () -> String?,
                     snapshots: @escaping () -> [InputSourceSelection.Snapshot],
                     select: @escaping (_ sourceID: String) -> Bool,
                     nextTurn: @escaping (@escaping @MainActor @Sendable () -> Void) -> Void) {
            self.isEnabled = isEnabled
            self.currentSourceID = currentSourceID
            self.snapshots = snapshots
            self.select = select
            self.nextTurn = nextTurn
        }

        package static var live: System {
            System(isEnabled: { UserDefaults.standard.bool(forKey: DefaultsKey.commandBarASCIILayoutEnabled) },
                   currentSourceID: { InputSourceSelection.currentSourceID() },
                   snapshots: { InputSourceSelection.snapshots() },
                   select: { InputSourceSelection.select(sourceID: $0) },
                   nextTurn: { work in DispatchQueue.main.async { work() } })
        }
    }

    private let system: System
    /// The presentation now on screen; a new opening replaces it.
    private let presentationID: () -> UUID

    package init(system: System = .live, presentationID: @escaping () -> UUID) {
        self.system = system
        self.presentationID = presentationID
    }

    /// The input source the bar switched away from on open, put back on
    /// close. Recorded whenever TIS accepts the switch: a switch that never
    /// landed restores a source the bar never left — a no-op — while a
    /// missing record would strand the typist on the borrowed layout.
    package private(set) var suspendedInputSourceID: String?

    package var hasBorrowedInputSource: Bool {
        suspendedInputSourceID != nil
    }

    /// One-shot switch to the first enabled ASCII layout, read fresh on every
    /// open like every other preference on this path. TIS talks to the
    /// text-input server from the main thread, the way the Super key switch
    /// already does.
    package func adoptASCIIInputSource() {
        let apply = {
            guard self.system.isEnabled() else {
                self.restoreSuspendedInputSource()
                return
            }
            let currentID = self.system.currentSourceID()
            guard let target = InputSourceSelection.asciiLayoutID(
                currentID: currentID,
                snapshots: self.system.snapshots())
            else { return }
            // The record belongs to acceptance, not the landing: a switch
            // that never landed only restores a source the bar never left —
            // a no-op — while a missed record strands the typist on the
            // borrowed layout.
            guard self.system.select(target) else { return }
            self.suspendedInputSourceID = currentID
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.sync(execute: apply)
        }
    }

    package func restoreSuspendedInputSource() {
        guard let sourceID = suspendedInputSourceID else { return }
        // The switch waits for the next turn of the main loop. A close reached
        // through a key (Esc, Return, ⌘,) runs inside that key event's own
        // dispatch, and TIS quietly ignores a source switch asked for there —
        // the same hide() restores fine from a click or the hotkey, which
        // stand outside any key event. Waiting is safe: the presentation id
        // is captured now, and beginPresentation replaces it on the next
        // open. Keep the original source until restoration actually runs:
        // reopening while ASCII is still active borrows the same source.
        let presentationID = self.presentationID()
        system.nextTurn { [weak self] in
            guard let self, self.presentationID() == presentationID,
                  self.suspendedInputSourceID == sourceID else { return }
            self.restoreBorrowedInputSource()
        }
    }

    /// The termination path cannot wait for another main-loop turn. Keep a
    /// refused restoration pending so a later close or termination can retry.
    package func restoreBorrowedInputSource() {
        guard let sourceID = suspendedInputSourceID,
              system.select(sourceID) else { return }
        suspendedInputSourceID = nil
    }
}
