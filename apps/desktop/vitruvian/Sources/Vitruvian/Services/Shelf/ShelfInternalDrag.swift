// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore

/// A drag of shelf items out of a shelf, from its start to its end: which
/// items left, whether a drop inside the shelf merged them, and what the
/// shelf they came from does once they land. `ShelfService` owns it; tests
/// pass doubles for the shelves and the island.
@MainActor
package final class ShelfInternalDrag {
    /// The island's Files page as the drag finds it.
    package struct Island {
        package var window: AnyObject?
        package var expanded: Bool
        package var selected: NotchModule
        package var showingAppPanel: Bool
        package var showingSections: Bool
        package var pinned: Bool

        package init(window: AnyObject?, expanded: Bool, selected: NotchModule, showingAppPanel: Bool,
                     showingSections: Bool, pinned: Bool) {
            self.window = window
            self.expanded = expanded
            self.selected = selected
            self.showingAppPanel = showingAppPanel
            self.showingSections = showingSections
            self.pinned = pinned
        }
    }

    /// One of the shelf's own windows: the floating shelf or the docked one.
    package struct Shelf {
        package var window: AnyObject?
        package var isVisible: Bool

        package init(window: AnyObject?, isVisible: Bool) {
            self.window = window
            self.isVisible = isVisible
        }
    }

    package struct Host {
        package var defaults: UserDefaults
        package var island: () -> Island
        /// Holds the island open while a drag from it lasts, or lets it go.
        package var holdIsland: (Bool) -> Void
        package var collapseIsland: () -> Void
        package var floating: () -> Shelf
        package var floatingIsPinned: () -> Bool
        package var hideFloating: () -> Void
        package var docked: () -> Shelf
        package var collapseDocked: () -> Void
        package var endInteraction: () -> Void
        /// Items a drag out never takes away, such as pinned ones.
        package var protectedIDs: () -> Set<UUID>
        package var removeItems: ([UUID]) -> Void

        package init(defaults: UserDefaults, island: @escaping () -> Island,
                     holdIsland: @escaping (Bool) -> Void, collapseIsland: @escaping () -> Void,
                     floating: @escaping () -> Shelf, floatingIsPinned: @escaping () -> Bool,
                     hideFloating: @escaping () -> Void, docked: @escaping () -> Shelf,
                     collapseDocked: @escaping () -> Void, endInteraction: @escaping () -> Void,
                     protectedIDs: @escaping () -> Set<UUID>, removeItems: @escaping ([UUID]) -> Void) {
            self.defaults = defaults
            self.island = island
            self.holdIsland = holdIsland
            self.collapseIsland = collapseIsland
            self.floating = floating
            self.floatingIsPinned = floatingIsPinned
            self.hideFloating = hideFloating
            self.docked = docked
            self.collapseDocked = collapseDocked
            self.endInteraction = endInteraction
            self.protectedIDs = protectedIDs
            self.removeItems = removeItems
        }
    }

    /// The items being dragged, empty while no drag is under way.
    package private(set) var ids: [UUID] = []
    /// A drop inside the shelf took the items in already.
    package var wasMerged = false
    private weak var window: AnyObject?
    private let host: Host

    package var isActive: Bool { !ids.isEmpty }

    package init(host: Host) {
        self.host = host
    }

    package func begin(ids: [UUID], from window: AnyObject?) {
        self.window = window
        if let window, window === host.island().window {
            host.holdIsland(true)
        }
        self.ids = ids
        wasMerged = false
    }

    private func finish(dropAccepted: Bool) -> [UUID] {
        defer {
            ids = []
            wasMerged = false
            if let window, window === host.island().window {
                host.holdIsland(false)
            }
            window = nil
        }
        guard dropAccepted, !wasMerged else { return [] }
        return ids
    }

    package func complete(dropAccepted: Bool) {
        let source = window
        let fromIsland = source != nil && source === host.island().window
        let draggedIDs = finish(dropAccepted: dropAccepted)
        host.endInteraction()
        guard !draggedIDs.isEmpty else { return }

        let removableIDs = ShelfInteractionSupport.removableAfterDrag(draggedIDs, protectedIDs: host.protectedIDs())
        if ShelfInteractionSupport.shouldRemoveAfterDrag(
            dropAccepted: dropAccepted,
            draggedItemCount: removableIDs.count,
            removeAfterDrop: host.defaults[Preferences.shelfRemoveAfterDrop]) {
            host.removeItems(removableIDs)
        }
        if ShelfInteractionSupport.shouldCloseAfterDrag(
            dropAccepted: dropAccepted,
            draggedItemCount: draggedIDs.count,
            closeAfterDrop: host.defaults[Preferences.shelfCloseAfterDrop],
            pinned: fromIsland ? host.island().pinned : host.floatingIsPinned()) {
            if fromIsland {
                let island = host.island()
                if island.expanded, island.selected == .files, !island.showingAppPanel, !island.showingSections {
                    host.collapseIsland()
                }
            } else if host.floating().isVisible, let source, source === host.floating().window {
                host.hideFloating()
            } else if host.docked().isVisible, let source, source === host.docked().window {
                host.collapseDocked()
            }
        }
    }
}
