// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The production drag completion runs with stand-in windows, a recording
/// shelf and island, and preferences of its own.
enum ShelfDragCompletionContract {
    final class Window {}

    final class Session {
        let defaults: UserDefaults
        var islandWindow: Window? = Window()
        var expanded = true
        var selected: NotchModule = .files
        var showingAppPanel = false
        var showingSections = false
        var islandPinned = false
        var heldDrag = false
        var islandClosures = 0
        var panel: Window?
        var dockedPanel: Window?
        var isPinned = false
        var isVisible = false
        var dockedVisible = false
        var protectedIDs: Set<UUID> = []
        var removed: [UUID] = []
        var floatingClosures = 0
        var dockedClosures = 0
        private(set) lazy var drag = ShelfInternalDrag(host: .init(
            defaults: defaults,
            island: {
                .init(window: self.islandWindow, expanded: self.expanded, selected: self.selected,
                      showingAppPanel: self.showingAppPanel, showingSections: self.showingSections,
                      pinned: self.islandPinned)
            },
            holdIsland: { self.heldDrag = $0 },
            collapseIsland: {
                precondition(!self.heldDrag, "release the drag before trying to collapse")
                self.islandClosures += 1
                self.expanded = false
            },
            floating: { .init(window: self.panel, isVisible: self.isVisible) },
            floatingIsPinned: { self.isPinned },
            hideFloating: { self.floatingClosures += 1; self.isVisible = false },
            docked: { .init(window: self.dockedPanel, isVisible: self.dockedVisible) },
            collapseDocked: { self.dockedClosures += 1; self.dockedVisible = false },
            endInteraction: {},
            protectedIDs: { self.protectedIDs },
            removeItems: { self.removed += $0 }))

        init(closeAfterDrop: Bool = true, removeAfterDrop: Bool = true) {
            let domain = "com.vitruviansoftware.vitruvian.tests.shelf-drag.\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: domain)!
            defaults.set(closeAfterDrop, forKey: DefaultsKey.shelfCloseAfterDrop)
            defaults.set(removeAfterDrop, forKey: DefaultsKey.shelfRemoveAfterDrop)
        }
    }
}

enum ShelfDragCompletionTests {
    private typealias Context = ShelfDragCompletionContract

    static func run(_ suite: TestSuite) {
        for pinned in [false, true] {
            for close in [false, true] {
                for accepted in [false, true] {
                    for merged in [false, true] {
                        let session = Context.Session(closeAfterDrop: close)
                        session.islandPinned = pinned
                        session.isPinned = !pinned
                        let id = UUID()
                        session.drag.begin(ids: [id], from: session.islandWindow)
                        session.drag.wasMerged = merged
                        suite.expect(session.heldDrag, "a drag from the notch holds its working surface")
                        session.drag.complete(dropAccepted: accepted)
                        let transferred = accepted && !merged
                        suite.expect(session.islandClosures == (transferred && close && !pinned ? 1 : 0),
                               "notch completion honors accepted drops, local merges, its pin and the close preference")
                        suite.expect(session.removed == (transferred ? [id] : []) && !session.heldDrag
                               && !session.drag.isActive && !session.drag.wasMerged,
                               "completion preserves removal policy and always releases the drag's source")
                        suite.expect(session.floatingClosures == 0 && session.dockedClosures == 0,
                               "closing an embedded shelf leaves the separate presentations alone")
                    }
                }
            }
        }

        for docked in [false, true] {
            let session = Context.Session(removeAfterDrop: false)
            let source = Context.Window()
            if docked { session.dockedPanel = source } else { session.panel = source }
            session.isVisible = !docked
            session.dockedVisible = docked
            session.islandPinned = true
            session.drag.begin(ids: [UUID()], from: source)
            suite.expect(!session.heldDrag, "a separate shelf cannot hold an unrelated notch open")
            session.drag.complete(dropAccepted: true)
            suite.expect(session.floatingClosures == (docked ? 0 : 1) && session.dockedClosures == (docked ? 1 : 0)
                   && session.islandClosures == 0 && session.removed.isEmpty,
                   "separate shelf completion retains its own close, pin and removal behavior")
        }

        let pinnedSession = Context.Session()
        let pinnedID = UUID(), looseID = UUID()
        pinnedSession.protectedIDs = [pinnedID]
        pinnedSession.drag.begin(ids: [pinnedID, looseID], from: Context.Window())
        pinnedSession.drag.complete(dropAccepted: true)
        suite.expect(pinnedSession.removed == [looseID],
               "a pinned shelf item survives a drag-out that removes the rest")

        for changedSurface in 0..<5 {
            let session = Context.Session()
            let source = session.islandWindow!
            session.panel = Context.Window()
            session.isVisible = true
            session.drag.begin(ids: [UUID()], from: source)
            switch changedSurface {
            case 0: session.selected = .music
            case 1: session.showingSections = true
            case 2: session.showingAppPanel = true
            case 3: session.expanded = false
            default: session.islandWindow = Context.Window(); session.heldDrag = false
            }
            session.drag.complete(dropAccepted: true)
            suite.expect(session.islandClosures == 0 && session.floatingClosures == 0,
                   "an old drag cannot close a different destination or a replacement notch window")
        }
    }
}
