// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// Who holds a combination among the two lists `GlobalShortcutRole.conflict`
/// cannot see: Command Bar row shortcuts and tool command shortcuts. Every
/// place that records a global shortcut asks here after it has asked the
/// role check and the window-layout check, so one combination has one owner.
@MainActor
package enum ShortcutConflicts {
    package enum Holder: Equatable {
        /// A Command Bar row, by its stable key.
        case commandBarRow(String)
        /// A tool command, by its id text. It may not be registered now.
        case toolCommand(String)
    }

    /// The rule, with everything it reads handed in. Both maps are what is
    /// saved, not what is a key right now: a command whose tool is switched
    /// off or not registered still holds its combination. An entry with no
    /// id at all is nobody's, and holds nothing.
    package static func holder(of shortcut: GlobalShortcut, rows: [String: GlobalShortcut],
                               commands: [String: GlobalShortcut],
                               excludingRow: String?, excludingCommand: CommandID?) -> Holder? {
        if let row = rows.first(where: { $0.value == shortcut && $0.key != excludingRow })?.key {
            return .commandBarRow(row)
        }
        let named = commands.filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if let command = ToolCommandShortcuts.holder(of: shortcut, in: named, excluding: excludingCommand) {
            return .toolCommand(command)
        }
        return nil
    }

    /// What a refusal calls a holder, with the lookups handed in. A row the
    /// catalog cannot name is called by the list it is in. A command the
    /// registry cannot name is called by its id text, which `holder` never
    /// gives empty.
    package static func name(of holder: Holder, rowTitle: (String) -> String?, rowFallback: String,
                             commandTitle: (CommandID) -> String?) -> String {
        switch holder {
        case .commandBarRow(let key):
            return rowTitle(key) ?? rowFallback
        case .toolCommand(let text):
            return CommandID(text).flatMap(commandTitle) ?? text
        }
    }

    /// The holder's name as the other shortcut rows would name it, or nil
    /// when the combination is free of both lists. Row shortcuts count while
    /// the Command Bar is installed, which is when the bar itself keeps them.
    package static func title(for shortcut: GlobalShortcut, excludingRow: String? = nil,
                              excludingCommand: CommandID? = nil) -> String? {
        let rows = AppFeature.commandBar.isAvailable ? CommandBarService.shared.rowShortcuts : [:]
        guard let holder = holder(of: shortcut, rows: rows, commands: ToolShortcutRegistrar.shared.shortcuts,
                                  excludingRow: excludingRow, excludingCommand: excludingCommand)
        else { return nil }
        let language = L10n.shared.language
        return name(of: holder,
                    rowTitle: { CommandBarService.shared.entryTitle(forStableKey: $0) },
                    rowFallback: FeatureStrings.commandBar(language).rowShortcutsTitle,
                    commandTitle: { ToolRegistry.shared.title(for: $0, language: language) })
    }
}
