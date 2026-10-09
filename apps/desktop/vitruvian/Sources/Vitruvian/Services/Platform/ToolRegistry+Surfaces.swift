// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

extension ToolRegistry {
    /// The commands a surface should add to its own fixed list: those that
    /// ask for it and that the list does not already offer. One action, one
    /// entry. With only the app's own tools registered this is empty for the
    /// wheel and the panel.
    package func extraCommands(on surface: ToolSurface) -> [CommandDescriptor] {
        let offered: Set<CommandID>
        switch surface {
        case .radial: offered = Set(RadialMenuTool.allCases.map(\.command.id))
        case .quickPanel: offered = Set(QuickLauncherItem.allCases.compactMap { $0.command?.id })
        case .commandBar: offered = []
        }
        return commands(on: surface).filter { !offered.contains($0.id) }
    }
}
