// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CoreGraphics
import VitruvianToolProtocol

/// Where the Agents page's slot is: the Chat tab's place, kept for a tool
/// whose manifest declares `contributes.slot` with `agents`, which draws
/// itself there and is told where it is with `ui/slot`.
package enum AgentsSlot: Equatable, Sendable {
    /// The slot is not on the screen.
    case hidden
    /// The slot shows, in this rectangle, in screen points from the bottom
    /// left of the main screen, as AppKit counts them.
    case shown(CGRect)

    /// Whether the slot shows now: the island is open on the Agents page,
    /// its Chat tab is chosen, a tool is in the slot, and the place has
    /// been measured with a size.
    package static func state(expanded: Bool, section: NotchSectionItem, tab: NotchAgentTab, slotTool: Bool,
                              rect: CGRect?) -> AgentsSlot {
        guard expanded, section == .module(.agents), tab == .chat, slotTool, let rect,
              rect.width > 0, rect.height > 0 else { return .hidden }
        return .shown(rect)
    }

    /// What the slot's tools are told when the slot goes from `old` to
    /// `new`: where it shows now, or that it went, and whether because the
    /// person popped the tool out. Nil when nothing changed, so a tool is
    /// not told the same twice.
    package static func message(from old: AgentsSlot, to new: AgentsSlot, poppedOut: Bool = false) -> UISlotParams? {
        switch (old, new) {
        case (.hidden, .hidden):
            return nil
        case (.shown(let before), .shown(let now)) where before == now:
            return nil
        case (_, .shown(let rect)):
            return UISlotParams(visible: true, x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width),
                                height: Double(rect.height))
        case (.shown, .hidden):
            return UISlotParams(visible: false, popOut: poppedOut)
        }
    }
}
