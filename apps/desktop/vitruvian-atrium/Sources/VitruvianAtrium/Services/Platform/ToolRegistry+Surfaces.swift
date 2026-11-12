// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

extension ToolRegistry {
    /// The commands a surface should add to its own fixed list: those that
    /// ask for it and that the list does not already offer. One action, one
    /// entry. With only the app's own tools registered this is empty for the
    /// wheel and the panel.
    ///
    /// The island's Tools grid (`.quickPanel`) is for the app's own tools and
    /// for outside tools with no page of their own in the island. An outside
    /// tool that has one offers its actions there, so the grid leaves its
    /// commands out even when they ask for it. Every other surface keeps
    /// them.
    package func extraCommands(on surface: ToolSurface) -> [CommandDescriptor] {
        let offered: Set<CommandID>
        switch surface {
        case .radial: offered = Set(RadialMenuTool.allCases.map(\.command.id))
        case .quickPanel: offered = Set(QuickLauncherItem.allCases.compactMap { $0.command?.id })
        // The app's own commands have their shortcuts through
        // `GlobalShortcutRole` and do not ask for this surface.
        case .commandBar, .shortcut: offered = []
        }
        let listed = commands(on: surface).filter { !offered.contains($0.id) }
        guard surface == .quickPanel else { return listed }
        return listed.filter { !hasIslandPage($0.id.tool) }
    }
}
