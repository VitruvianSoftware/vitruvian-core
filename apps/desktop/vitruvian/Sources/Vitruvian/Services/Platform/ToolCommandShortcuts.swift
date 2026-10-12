// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// The shortcuts people gave to tool commands: one preference, a map from a
/// command id's text to a combination. Keyed by the text, not by
/// `CommandID`, so an entry whose tool is switched off, not registered this
/// launch, or misspelled in a restored backup is carried through untouched.
/// It returns with its tool. Until then it holds nothing (`held`): its keys
/// can be given to another command, and then the entry goes. The entries of
/// a tool the person removed are cleared (`forgetting`).
package enum ToolCommandShortcuts {
    /// As many as the Command Bar's row shortcuts.
    package static let limit = 64

    package static func decode(_ raw: String?) -> [String: GlobalShortcut] { ShortcutMap.decode(raw) }
    package static func encode(_ shortcuts: [String: GlobalShortcut]) -> String? { ShortcutMap.encode(shortcuts) }

    package static func shortcut(for id: CommandID, in shortcuts: [String: GlobalShortcut]) -> GlobalShortcut? {
        shortcuts[id.rawValue]
    }

    /// The id text of the command that holds `shortcut`, other than `excluded`.
    package static func holder(of shortcut: GlobalShortcut, in shortcuts: [String: GlobalShortcut],
                               excluding excluded: CommandID?) -> String? {
        shortcuts.first { $0.value == shortcut && $0.key != excluded?.rawValue }?.key
    }

    /// Of what is saved, the shortcuts that hold their combination now:
    /// those of the commands in `asking`, which are here and ask for a
    /// shortcut, each with a row on the Shortcuts page. The entry of a
    /// command that is not here holds nothing: no key, and no claim on its
    /// combination. The person cannot see it, so could never clear it.
    package static func held(_ shortcuts: [String: GlobalShortcut], by asking: Set<CommandID>) -> [String: GlobalShortcut] {
        shortcuts.filter { CommandID($0.key).map(asking.contains) ?? false }
    }

    /// Why `shortcut` may not be given to `id`, or nil when it may. It is
    /// taken only when one of `held`, a command that is here, has it. An
    /// entry of a command that is not here gives way, and its place with
    /// it (`ShortcutMap.setting` moves the combination), so one combination
    /// still has one owner. The list is full by everything that is saved.
    package static func assignmentIssue(_ shortcut: GlobalShortcut, for id: CommandID,
                                        in saved: [String: GlobalShortcut],
                                        held: [String: GlobalShortcut]) -> ShortcutMap.AssignmentIssue? {
        guard ShortcutMap.isUsable(shortcut) else { return .invalid }
        if let owner = holder(of: shortcut, in: held, excluding: id) { return .occupied(owner) }
        let afterGivingWay = saved.filter { $0.value != shortcut || $0.key == id.rawValue }
        return ShortcutMap.hasRoom(for: id.rawValue, in: afterGivingWay, limit: limit) ? nil : .full
    }

    /// `shortcuts` without those of one tool's commands, and the id texts
    /// that were dropped. A command belongs to a tool by its whole id, so a
    /// tool whose id only starts the same keeps what it has.
    package static func forgetting(_ tool: ToolID, in shortcuts: [String: GlobalShortcut])
        -> (kept: [String: GlobalShortcut], dropped: [String]) {
        let dropped = shortcuts.keys.filter { CommandID($0)?.tool == tool }.sorted()
        return (shortcuts.filter { !dropped.contains($0.key) }, dropped)
    }

    /// What is saved in `defaults`, as far as it can be read.
    package static func load(from defaults: UserDefaults) -> [String: GlobalShortcut] {
        decode(defaults[Preferences.toolCommandShortcuts])
    }

    /// Saves `shortcuts` in `defaults`. An entry already saved whose value
    /// cannot be read as a combination is in no list `decode` gives, so it
    /// is carried over as it was unless `shortcuts` has its key: a change to
    /// one command's shortcut deletes nothing else. With nothing left to
    /// keep, the preference goes back to its default.
    package static func save(_ shortcuts: [String: GlobalShortcut], to defaults: UserDefaults) {
        var stored = unreadableEntries(defaults[Preferences.toolCommandShortcuts])
        for (key, shortcut) in shortcuts { stored[key] = shortcut.storageValue }
        guard !stored.isEmpty else {
            defaults.removeValue(for: Preferences.toolCommandShortcuts)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // Text that will not encode is not a reason to lose what is saved.
        guard let data = try? encoder.encode(stored), let text = String(data: data, encoding: .utf8) else { return }
        defaults[Preferences.toolCommandShortcuts] = text
    }

    private static func unreadableEntries(_ raw: String?) -> [String: String] {
        guard let raw, let data = raw.data(using: .utf8),
              let stored = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return stored.filter { GlobalShortcut(storageValue: $0.value) == nil }
    }

    /// The name a command's hotkey is claimed under, and its take-over of a
    /// macOS shortcut kept under.
    package static func takeOverKey(for id: CommandID) -> String {
        "\(DefaultsKey.toolCommandShortcuts).\(id.rawValue)"
    }
}
