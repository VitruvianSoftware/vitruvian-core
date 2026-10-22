// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Combine
import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianToolProtocol

/// Tells the tools in the Agents page's slot where it is (`ui/slot`): when
/// the island opens on the Chat tab, when the slot moves, and when it goes,
/// because the island closed, another tab or page was chosen, or the person
/// popped the tool out. What to say is `AgentsSlot`'s; this only watches.
@MainActor
package final class AgentsSlotReporter {
    package static let shared = AgentsSlotReporter()

    /// Where the Chat tab's place was last measured on the screen; nil while
    /// it is not drawn.
    private var rect: CGRect?
    private var last: AgentsSlot = .hidden
    private var watching: AnyCancellable?

    private init() {}

    /// Starts watching the island, once. The page calls it as it appears.
    package func start() {
        guard watching == nil else { return }
        let notch = NotchService.shared
        // `@Published` tells before it changes: the state is read a turn
        // later, when it has.
        watching = Publishers.Merge3(notch.$expanded.map { _ in () }, notch.$currentSection.map { _ in () },
                                     notch.$agentTab.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
    }

    /// The Chat tab's place, measured on the screen; nil when it went.
    package func measured(_ rect: CGRect?) {
        self.rect = rect
        refresh()
    }

    /// The person asked for the tool in a window of its own: the slot goes,
    /// and the tools are told why, before the island closes.
    package func popOut() {
        send(.hidden, poppedOut: true)
        NotchService.shared.collapse()
    }

    private func refresh() {
        let notch = NotchService.shared
        let slotTool = !ExternalToolStore.shared.slotTools(.agents).isEmpty
        send(AgentsSlot.state(expanded: notch.expanded, section: notch.currentSection, tab: notch.agentTab,
                              slotTool: slotTool, rect: rect))
    }

    private func send(_ next: AgentsSlot, poppedOut: Bool = false) {
        defer { last = next }
        guard let message = AgentsSlot.message(from: last, to: next, poppedOut: poppedOut) else { return }
        ExternalToolStore.shared.tellSlot(.agents, message)
    }
}
