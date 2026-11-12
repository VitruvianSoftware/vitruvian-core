// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// One tile of the Quick panel: one of the app's own, or a registry command
/// that no built-in tile runs. Its raw value is what the saved order and the
/// hidden set hold. A built-in tile's is its enum raw value, as it always
/// was; a command's is its command id. The slash tells them apart: no enum
/// raw value has one, and every command id has exactly one.
package enum QuickLauncherTile: Hashable, Identifiable, PanelOrderItem {
    case builtin(QuickLauncherItem)
    case command(CommandID)

    package init?(rawValue: String) {
        if let item = QuickLauncherItem(rawValue: rawValue) {
            self = .builtin(item)
        } else if let id = CommandID(rawValue) {
            self = .command(id)
        } else {
            return nil
        }
    }

    package var rawValue: String {
        switch self {
        case .builtin(let item): return item.rawValue
        case .command(let id): return id.rawValue
        }
    }

    package var id: String { rawValue }

    package var builtin: QuickLauncherItem? {
        if case .builtin(let item) = self { return item }
        return nil
    }

    package var commandID: CommandID? {
        if case .command(let id) = self { return id }
        return nil
    }
}
