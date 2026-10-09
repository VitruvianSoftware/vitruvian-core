// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// The shortcuts people gave to tool commands: one preference, a map from a
/// command id's text to a combination. Keyed by the text, not by
/// `CommandID`, so an entry whose tool is switched off, not registered this
/// launch, or misspelled in a restored backup is carried through untouched.
/// It returns with its tool, and until then still holds its combination.
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

    /// The name a command's hotkey is claimed under, and its take-over of a
    /// macOS shortcut kept under.
    package static func takeOverKey(for id: CommandID) -> String {
        "\(DefaultsKey.toolCommandShortcuts).\(id.rawValue)"
    }
}
