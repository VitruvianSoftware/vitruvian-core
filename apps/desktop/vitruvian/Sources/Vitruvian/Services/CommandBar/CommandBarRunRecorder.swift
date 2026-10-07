// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// What running a row teaches the command bar: its use, counted and saved,
/// and the search that found it, remembered for as long as the app runs. The
/// bar hands it the field as it stands, and how to close and to type.
@MainActor
package final class CommandBarRunRecorder {
    /// The field at the moment a row runs.
    package struct Field {
        package var mode: CommandBarService.Mode
        package var query: String
        /// What was typed before an argument or the actions list took the field.
        package var savedQuery: String
        package var queryBeforeCompletion: String?
        package var selectedText: String
        package var isVisible: Bool

        package init(mode: CommandBarService.Mode, query: String, savedQuery: String,
                     queryBeforeCompletion: String?, selectedText: String, isVisible: Bool) {
            self.mode = mode
            self.query = query
            self.savedQuery = savedQuery
            self.queryBeforeCompletion = queryBeforeCompletion
            self.selectedText = selectedText
            self.isVisible = isVisible
        }
    }

    package struct Host {
        package var field: () -> Field
        package var hide: () -> Void
        /// Types text at the caret of the app the person was using.
        package var type: (String) -> Void
        package var defaults: UserDefaults
        /// The bar closes because a row ran, and again once it has closed:
        /// the companion leaves glad and hops for it back in the island.
        package var closingForRun: () -> Void
        package var closedForRun: () -> Void

        package init(field: @escaping () -> Field, hide: @escaping () -> Void,
                     type: @escaping (String) -> Void, defaults: UserDefaults,
                     closingForRun: @escaping () -> Void = {}, closedForRun: @escaping () -> Void = {}) {
            self.field = field
            self.hide = hide
            self.type = type
            self.defaults = defaults
            self.closingForRun = closingForRun
            self.closedForRun = closedForRun
        }
    }

    /// Which row answered which few letters, for as long as the app runs. Not
    /// stored: the bar forgets everything typed into it when it goes.
    package var queryMemory = CommandBarQueryMemory()
    /// Counts choices, so the memory can order its own entries without a clock.
    package private(set) var queryMemoryStep = 0
    /// Decoded once when preferences reload, never while a keystroke ranks
    /// rows. The second cache keeps already-keyed prefixes for this opening.
    package var queryHabitStore = CommandBarQueryHabitStoreCache()
    package var preparedHabitQuery = CommandBarQueryHabits.PreparationCache()
    /// The saved usage, read once when preferences reload.
    package var usage: [String: CommandBarUse] = [:]
    /// What was in the field, and what was selected, at the instant a row ran.
    /// Closing the bar wipes both before the row's own closure gets to work,
    /// so they are handed over here instead of being read back from a panel
    /// that is already gone.
    package private(set) var queryWhenRun = ""
    package private(set) var selectionWhenRun = ""

    private let host: Host

    package init(host: Host) {
        self.host = host
    }

    /// A new opening starts with nothing handed over.
    package func forgetRun() {
        queryWhenRun = ""
        selectionWhenRun = ""
    }

    /// The other tones of the selected emoji, for the person whose default is
    /// not the one this message wants. Usage still belongs to the same emoji;
    /// the chosen tone applies only to this insertion, not the preference.
    package func skinToneActions(for entry: CommandBarEntry) -> [CommandBarService.RowAction] {
        // The id carries the emoji itself, untoned, so the base needs no lookup.
        guard let base = CommandBarPreferences.emojiIdentity(fromRowID: entry.id),
              CommandBarEmoji.acceptsSkinTone(base) else { return [] }
        let current = CommandBarPreferences.skinTone(
            from: host.defaults[Preferences.commandBarEmojiSkinTone])
        return CommandBarEmoji.SkinTone.allCases.filter { $0 != current }.map { tone in
            let character = CommandBarEmoji.applying(tone, to: base)
            return CommandBarService.RowAction(id: "emojiSkinTone.\(tone.rawValue)",
                                               title: character,
                                               symbolName: "hand.raised") { [weak self] in
                guard let self else { return }
                self.record(entry)
                self.host.hide()
                self.host.type(character)
            }
        }
    }

    /// Normal insertion and one-off variants share the same learning history.
    package func record(_ entry: CommandBarEntry) {
        let field = host.field()
        let now = Date().timeIntervalSince1970
        let typedQuery: String
        switch field.mode {
        case .argument, .actions:
            typedQuery = CommandBarCompletion.queryForLearning(
                current: field.savedQuery, beforeCompletion: field.queryBeforeCompletion)
        default:
            typedQuery = CommandBarCompletion.queryForLearning(
                current: field.query, beforeCompletion: field.queryBeforeCompletion)
        }
        let trimmedQuery = typedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let learningQuery = CommandBarSearch.emojiQuery(from: trimmedQuery) ?? trimmedQuery
        if entry.countsUsage, field.isVisible {
            // Only what is on screen teaches anything: a row run from its own
            // combination was never typed for.
            queryMemoryStep &+= 1
            queryMemory.record(query: learningQuery, id: entry.id, step: queryMemoryStep)
        }
        if entry.countsUsage {
            let stored = host.defaults.string(forKey: DefaultsKey.commandBarUsage)
            let next = CommandBarUsage.recording(CommandBarUsage.decode(stored),
                                                 id: entry.id,
                                                 now: now)
            host.defaults.set(CommandBarUsage.encode(next), forKey: DefaultsKey.commandBarUsage)
            usage = next
        }
        if entry.countsUsage, !learningQuery.isEmpty {
            let prepared = CommandBarQueryHabits.prepare(
                learningQuery, cache: &preparedHabitQuery)
            if !prepared.isEmpty {
                queryHabitStore.record(preparedQuery: prepared,
                                       resultID: entry.id,
                                       now: now)
            }
        }
    }

    /// Runs a row: it is recorded, the field is handed over, and the bar
    /// closes unless the row keeps it open.
    package func finish(_ entry: CommandBarEntry, value: Int?) {
        record(entry)
        // Handed over before hiding, which wipes the field and the selection.
        let field = host.field()
        queryWhenRun = field.query
        selectionWhenRun = field.selectedText
        guard !entry.keepsBarOpen else {
            entry.run(value)
            return
        }
        host.closingForRun()
        host.hide()
        host.closedForRun()
        entry.run(value)
    }
}
