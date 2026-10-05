// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The closed-lid screen dimming, through the real manager and its lid watch
/// over the contract's machine. A fresh machine's lid is closed, so every
/// scenario here opens it before arming; closing it again is what dims.
enum KeepAwakeDimmingTests {
    private typealias C = KeepAwakeLidSleepContract

    /// A closed-lid session with the option armed and the lid open.
    private static func armed(reading: Double? = 0.6) -> C.Rig {
        let rig = C.active { machine, _ in machine.lid = false }
        rig.machine.reading = reading
        rig.manager.dimScreenOnLidClose = true
        return rig
    }

    private static func close(_ rig: C.Rig) {
        rig.machine.lid = true
        rig.machine.lidEvent()
    }

    private static func open(_ rig: C.Rig) {
        rig.machine.lid = false
        rig.machine.lidEvent()
    }

    static func run(expect: (Bool, String) -> Void) {
        let alreadyClosed = C.active()
        alreadyClosed.machine.reading = 0.7
        alreadyClosed.manager.dimScreenOnLidClose = true
        expect(alreadyClosed.machine.written == [0] && alreadyClosed.savedBrightness == 0.7
               && alreadyClosed.machine.lidWatches == 1,
               "enabling dimming with the lid already closed dims without waiting for another lid event")

        let closing = armed()
        close(closing)
        expect(closing.machine.written == [0] && closing.savedBrightness == 0.6,
               "closing the lid saves the current brightness and dims the panel to zero")

        for reading in [0.0, nil] as [Double?] {
            let unreadable = armed(reading: reading)
            close(unreadable)
            expect(unreadable.machine.written.isEmpty && unreadable.savedBrightness == nil,
                   "a panel that already reads asleep is left alone instead of being saved as zero")
        }

        let opening = armed()
        close(opening)
        open(opening)
        expect(opening.machine.written == [0, 0.6] && opening.savedBrightness == nil,
               "opening the lid restores the saved brightness and clears the recovery marker")
        expect(opening.machine.lidWatches == 1, "one lid watch serves the whole session")

        let toggledOff = armed()
        close(toggledOff)
        toggledOff.manager.dimScreenOnLidClose = false
        expect(toggledOff.machine.written == [0, 0.6] && toggledOff.savedBrightness == nil,
               "switching the option off while dimmed restores at once, without waiting for the lid to open")

        let sessionEnded = armed()
        close(sessionEnded)
        sessionEnded.manager.deactivate(reason: .manual)
        expect(sessionEnded.machine.written == [0, 0.6] && sessionEnded.savedBrightness == nil,
               "the closed-lid session ending while dimmed restores without waiting for the lid to open")

        let tornDown = armed()
        close(tornDown)
        let stale = tornDown.machine.lidChanged
        tornDown.manager.dimScreenOnLidClose = false
        tornDown.machine.written = []
        stale?()
        tornDown.machine.drain()
        expect(tornDown.machine.written.isEmpty && tornDown.machine.lidWatchesEnded == 1,
               "a lid notification that lands after the mode already ended changes nothing")

        let recovering = C.make { _, defaults in
            defaults.set(0.4, forKey: DefaultsKey.dimmedDisplaySavedBrightness)
        }
        recovering.manager.recoverIfNeeded()
        expect(recovering.machine.written == [0.4] && recovering.savedBrightness == nil,
               "a brightness saved before a crash is restored and cleared on the next launch")

        let panelMissing = C.make { machine, defaults in
            machine.writeSucceeds = false
            defaults.set(0.4, forKey: DefaultsKey.dimmedDisplaySavedBrightness)
        }
        panelMissing.manager.recoverIfNeeded()
        for _ in 0..<8 { panelMissing.machine.advance() }
        expect(panelMissing.machine.lidWatches == 1 && panelMissing.savedBrightness == 0.4,
               "a launch restore that finds no panel keeps its marker and watches the lid")
        panelMissing.machine.writeSucceeds = true
        open(panelMissing)
        expect(panelMissing.machine.written == [0.4] && panelMissing.savedBrightness == nil
               && panelMissing.machine.lidWatchesEnded == 1,
               "the lid opening after launch finishes that restore")

        let nothingToRecover = C.make()
        nothingToRecover.manager.recoverIfNeeded()
        expect(nothingToRecover.machine.written.isEmpty, "launch recovery does nothing when no brightness was saved")

        // A restore that briefly finds no panel — right as the lid opens —
        // keeps the saved level instead of clearing it on a merely attempted
        // write, and a queued retry completes it once the panel is back.
        let retrying = armed()
        close(retrying)
        retrying.machine.writeSucceeds = false
        open(retrying)
        expect(retrying.machine.written == [0] && retrying.savedBrightness == 0.6,
               "a restore that finds no panel yet keeps the saved level and its marker instead of clearing them")
        retrying.machine.writeSucceeds = true
        retrying.machine.advance()
        expect(retrying.machine.written == [0, 0.6] && retrying.savedBrightness == nil,
               "the queued retry restores it once the panel answers, with no further lid event needed")

        // Exhausting every retry while the option is switched off keeps the
        // lid watch armed instead of tearing it down, so a later real
        // lid-open event still gets a chance to finish the restore.
        let exhausted = armed()
        close(exhausted)
        exhausted.machine.writeSucceeds = false
        exhausted.manager.dimScreenOnLidClose = false
        for _ in 0..<8 { exhausted.machine.advance() }
        expect(exhausted.machine.written == [0] && exhausted.savedBrightness == 0.6
               && exhausted.machine.later.isEmpty && exhausted.machine.lidWatchesEnded == 0,
               "exhausting the retries after the option is switched off still owes the restore and keeps watching the lid")
        open(exhausted)
        exhausted.machine.reading = 0.3
        close(exhausted)
        expect(exhausted.machine.written == [0] && exhausted.savedBrightness == 0.6,
               "closing the lid again with the option off leaves the owed level alone")
        exhausted.machine.writeSucceeds = true
        open(exhausted)
        expect(exhausted.machine.written == [0, 0.6] && exhausted.savedBrightness == nil
               && exhausted.machine.lidWatchesEnded == 1,
               "the lid actually opening finishes the owed restore and only then releases the watch")
    }
}
