// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianAtriumCore
import VitruvianAtriumDesign
import VitruvianAtriumServices
import VitruvianAtriumUI

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
        var dragMoves: [CGPoint] = []
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
            islandDragMoved: { self.dragMoves.append($0) },
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
            defaults = ScratchDefaults.suite(named: domain)!
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

        // Only a tile dragged from the island tells it where the drag is, and
        // only while the drag lasts.
        for fromIsland in [false, true] {
            let session = Context.Session()
            let source = fromIsland ? session.islandWindow! : Context.Window()
            session.drag.moved(to: CGPoint(x: 1, y: 1))
            session.drag.begin(ids: [UUID()], from: source)
            session.drag.moved(to: CGPoint(x: 2, y: 2))
            session.drag.complete(dropAccepted: false)
            session.drag.moved(to: CGPoint(x: 3, y: 3))
            suite.expect(session.dragMoves == (fromIsland ? [CGPoint(x: 2, y: 2)] : []),
                   "only a drag from the island, while it lasts, can move the island aside")
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
        fileDragProtection(suite)
    }

    /// Package content, read from a real file system fixture: the rule the
    /// Shelf uses to offer only a copy, and the drag state that carries it.
    private static func fileDragProtection(_ suite: TestSuite) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("vitruvian-shelf-drag-tests-\(UUID())")
        defer { try? fm.removeItem(at: root) }
        do {
            let package = root.appendingPathComponent("Library.app", isDirectory: true)
            let resources = package.appendingPathComponent("Contents/Resources", isDirectory: true)
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            let inside = resources.appendingPathComponent("photo.jpeg")
            let plain = root.appendingPathComponent("plain.jpeg")
            try Data("package content".utf8).write(to: inside)
            try Data("ordinary file".utf8).write(to: plain)
            let directoryLink = root.appendingPathComponent("exports", isDirectory: true)
            let fileLink = root.appendingPathComponent("photo-link")
            let packageLink = root.appendingPathComponent("package-link")
            try fm.createSymbolicLink(at: directoryLink, withDestinationURL: resources)
            try fm.createSymbolicLink(at: fileLink, withDestinationURL: inside)
            try fm.createSymbolicLink(at: packageLink, withDestinationURL: package)

            let cases: [(URL, Bool, String)] = [
                (inside, true, "package content"),
                (resources, true, "a directory inside a package"),
                (directoryLink.appendingPathComponent("photo.jpeg"), true, "content through a directory symlink"),
                (plain, false, "an ordinary file"),
                (package, false, "a whole package"),
                (fileLink, false, "a symlink to a package file"),
                (packageLink, false, "a symlink to a whole package"),
            ]
            for (url, protected, label) in cases {
                let holds = ShelfInteractionSupport.holdsPackageContent([url])
                suite.expect(holds == protected, "package content is recognised for \(label)")
                let offersMove = ShelfInteractionSupport.offersMoveOutside(
                    removeAfterDrop: true, dragIncludesPinned: false, dragIncludesPackageContent: holds)
                // Exercise a same-volume destination using only the offered
                // operation. Everything here belongs to this temporary fixture.
                let destination = root.appendingPathComponent("drop-\(UUID())")
                if offersMove {
                    try fm.moveItem(at: url, to: destination)
                } else {
                    try fm.copyItem(at: url, to: destination)
                }
                suite.expect(fm.fileExists(atPath: destination.path)
                        && fm.fileExists(atPath: url.path) == protected,
                       "the offered transfer leaves package contents in place and permits legitimate moves for \(label)")
                if url == fileLink || url == packageLink {
                    suite.expect(fm.fileExists(atPath: inside.path),
                           "moving the symlink itself leaves its package target untouched")
                }
                if offersMove {
                    try fm.moveItem(at: destination, to: url)
                } else {
                    try fm.removeItem(at: destination)
                }
            }
            suite.expect(ShelfInteractionSupport.holdsPackageContent([plain, inside])
                    && !ShelfInteractionSupport.holdsPackageContent([plain, fileLink])
                    && !ShelfInteractionSupport.holdsPackageContent([]),
                   "a mixed drag is protected by any one package file in it")

            // The drag carries the decision and forgets it when it ends.
            for accepted in [false, true] {
                let session = Context.Session()
                let id = UUID()
                session.drag.begin(ids: [id], from: Context.Window(), holdsPackageContent: true)
                suite.expect(session.drag.holdsPackageContent, "a drag holding package content says so")
                session.drag.complete(dropAccepted: accepted)
                suite.expect(!session.drag.holdsPackageContent && session.removed == (accepted ? [id] : []),
                       "ending a protected drag clears the protection and retires only an accepted tile")
                session.drag.begin(ids: [UUID()], from: Context.Window())
                suite.expect(!session.drag.holdsPackageContent,
                       "a subsequent ordinary drag does not retain the previous package protection")
                session.drag.complete(dropAccepted: false)
            }
        } catch {
            suite.expect(false, "shelf drag protection fixture failed: \(error)")
        }
    }
}
