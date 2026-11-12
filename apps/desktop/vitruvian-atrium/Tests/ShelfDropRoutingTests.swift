// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Production destination methods run against controlled delivery results.
/// Native transport and payload integrity have separate transfer tests. The
/// island's canvas is the module's own `NotchCanvasDrop`, the shelf takes
/// drops through the module's own `ShelfDropIntake`, and the media tools are
/// the module's own `NotchFileToolsService` and `NotchMediaDrop`.
enum ShelfDropRoutingContract {
    enum Features {
        static var shelf = Feature()
        static var mediaTools = Feature()
        struct Feature { var isAvailable = true }
    }
    enum IslandModules {
        static var enabled = true
        static var visibleModules: [NotchModule] = [.files]
        static func isEnabled() -> Bool { enabled }
        static func modules() -> [NotchModule] { visibleModules }
        static func showsFiles() -> Bool { isEnabled() && modules().contains(.files) }
    }
    enum Switches {
        static var standard = Store()
        struct Store {
            var enabled = true
            func bool(forKey key: String) -> Bool { enabled }
        }
    }
    /// The shelf, holding the module's own `ShelfDropIntake` wired the way
    /// `ShelfService` wires it, over scripted deliveries.
    final class Shelf {
        static var shared = Shelf()
        let dockedPanel = NSObject()
        var dockCompletions = 0
        var interactionNotes = 0
        /// How many files the pasteboard promises.
        var promises = 0
        var accepts = true
        var ordinaryAccepts = 0
        var promisedAccepts = 0
        /// What the last promised delivery was handed.
        var delivered: (receivers: Int, pasteboard: NSPasteboard)?

        lazy var intake = ShelfDropIntake(
            enabled: { Features.shelf.isAvailable && Switches.standard.enabled },
            promises: { [unowned self] _ in (0..<self.promises).map { _ in NSFilePromiseReceiver() } },
            receive: { [unowned self] receivers, pasteboard, _ in
                self.promisedAccepts += 1
                self.delivered = (receivers.count, pasteboard)
                return self.accepts
            },
            add: { [unowned self] _, _ in
                self.ordinaryAccepts += 1
                return self.accepts
            },
            dock: { [unowned self] in self.dockedPanel },
            dockDidAccept: { [unowned self] in self.dockCompletions += 1 },
            noteInteraction: { [unowned self] in self.interactionNotes += 1 })

        func acceptDrop(pasteboard: NSPasteboard) -> Bool { intake.accept(pasteboard) }
        func fileURLs(from pasteboard: NSPasteboard) -> [URL] { ShelfPasteboardSupport.fileURLs(from: pasteboard) }
    }
    /// The island, holding the module's own `NotchFileDrop` wired the way
    /// `NotchService` wires it, to this contract's shelf and media tools. It
    /// keeps the island's names for the drop, as `NotchService` forwards them.
    final class Notch {
        var acceptsUserInteraction = true
        var captureControls: Int?
        var modules: [NotchModule] = [.files]
        var heldDrag = true
        var dragPlaceholder = true
        var pinned = false
        var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 32, cameraWidth: 180)
        var surfaceSize: CGSize { geometry.expandedSize(module: .files) }
        var opened: [NotchModule] = []
        /// Announcements that the drop's destinations change, as `objectWillChange`.
        var changes = 0

        lazy var fileDrop = NotchFileDrop(
            environment: NotchFileDrop.Environment(
                offersMedia: { FileTools.shared.drop.content(for: $0) != nil },
                mediaAccepts: { FileTools.shared.drop.accepts },
                openMedia: { FileTools.shared.drop.open($0) },
                hideMedia: { FileTools.shared.service.hideMedia() },
                shelfEnabled: { Features.shelf.isAvailable && Switches.standard.enabled },
                shelfAccept: { Shelf.shared.acceptDrop(pasteboard: $0) }),
            island: NotchFileDrop.Island(
                acceptsUserInteraction: { [unowned self] in self.acceptsUserInteraction },
                capturing: { [unowned self] in self.captureControls != nil },
                showsFiles: { [unowned self] in self.modules.contains(.files) },
                mediaArea: { [unowned self] in
                    NotchFileToolsSupport.mediaDropArea(in: self.geometry, size: self.surfaceSize)
                },
                willChange: { [unowned self] in self.changes += 1 },
                openFiles: { [unowned self] in self.open(.files, takeFocus: $0) },
                refreshPresentation: {},
                landed: { [unowned self] in
                    self.heldDrag = false
                    self.dragPlaceholder = false
                },
                cheer: { [unowned self] in self.reactions.append(.celebrate) }))
        /// The companion's reactions to what the island took.
        var reactions: [NotchMascotReaction] = []

        var choosingFileDropDestination: Bool { fileDrop.choosingDestination }
        var targetsMediaDrop: Bool { fileDrop.targetsMedia }
        var canAcceptFileDrop: Bool { fileDrop.canAccept }
        func beginFileDrop(_ pasteboard: NSPasteboard) { fileDrop.begin(pasteboard) }
        @discardableResult
        func updateFileDrop(at point: CGPoint) -> Bool { fileDrop.update(at: point) }
        func endFileDrop() { fileDrop.end() }
        func accept(_ pasteboard: NSPasteboard) -> Bool { fileDrop.accept(pasteboard) }

        func open(_ module: NotchModule, takeFocus: Bool = true) {
            opened.append(module)
        }
    }
    /// The media tools: the module's own service over this contract's
    /// switches, and its own drop decision wired the way the service wires
    /// it, except that whether the tools are already working, and whether a
    /// tool takes what it is opened on, are scripted.
    final class FileTools {
        static var shared = FileTools()
        /// The tools are already working, on media or an archive.
        var busy = false
        /// A tool takes the inputs it is opened on.
        var opens = true
        let service = NotchFileToolsService(environment: .init(
            available: {
                IslandModules.showsFiles() && Features.mediaTools.isAvailable && Features.shelf.isAvailable
            },
            shelfEnabled: { Switches.standard.enabled }))
        lazy var drop = NotchMediaDrop(
            offered: { [unowned self] in self.service.offersMediaDrop },
            busy: { [unowned self] in self.busy },
            openMedia: { [unowned self] in self.opens && self.service.openMedia($0, inputs: $1) })
        /// The inputs of the media workspace, shown or not.
        var inputs: [URL] { service.mediaSession?.inputs ?? [] }
    }
}

enum ShelfDropRoutingTests {
    private typealias Context = ShelfDropRoutingContract

    static func run(_ suite: TestSuite) {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        for promised in [false, true] {
            for accepted in [false, true] {
                Context.Features.shelf.isAvailable = true
                Context.Switches.standard.enabled = true
                Context.Shelf.shared = Context.Shelf()
                let shelf = Context.Shelf.shared
                shelf.promises = promised ? 2 : 0
                shelf.accepts = accepted
                let notch = Context.Notch()
                let canvas = NotchCanvasDrop()
                canvas.actions = NotchFileDropActions(
                    canAccept: { _ in notch.canAcceptFileDrop }, enter: { _ in },
                    accept: { notch.accept($0) }, exit: {})
                suite.expect(canvas.begin(board, localSource: true) == [],
                       "the island leaves internal tile drags to their merge destinations")
                suite.expect(!canvas.finish(board) && shelf.promisedAccepts + shelf.ordinaryAccepts == 0,
                       "an unaccepted gesture never reaches file delivery")
                suite.expect(canvas.begin(board, localSource: false) == .copy,
                       "an external drag remains accepted by the stable island destination")
                suite.expect(canvas.finish(board) == accepted,
                       "the island reports the actual shelf admission result")
                suite.expect(shelf.promisedAccepts == (promised ? 1 : 0)
                       && shelf.ordinaryAccepts == (promised ? 0 : 1),
                       "promised attachments reach native delivery instead of their fallback text")
                suite.expect(!promised || (shelf.delivered?.receivers == 2 && shelf.delivered?.pasteboard === board),
                       "a promised delivery gets every promise and the whole drop, so plain companions stay attached")
                suite.expect(notch.opened == (accepted ? [.files] : [])
                       && notch.heldDrag == !accepted && notch.dragPlaceholder == !accepted,
                       "only accepted deliveries open files and release the island placeholder")
                suite.expect(notch.reactions == (accepted ? [.celebrate] : []),
                       "the companion cheers only a file that landed")
                suite.expect(!canvas.finish(board), "one gesture cannot deliver twice")

                suite.expect(shelf.intake.accept(board, destination: NSObject()) == accepted
                       && shelf.dockCompletions == 0,
                       "a drop into another window leaves the dock alone")
                suite.expect(shelf.intake.accept(board, destination: shelf.dockedPanel) == accepted
                       && shelf.dockCompletions == (accepted ? 1 : 0),
                       "the separate dock keeps its completion behavior through the shared receiver")

                // A promised file is delivered asynchronously; noteInteraction()
                // has to run at drop time or an edge peek can retract before it arrives.
                let notesBefore = shelf.interactionNotes
                suite.expect(shelf.intake.accept(board, destination: NSObject()) == accepted
                       && shelf.interactionNotes == notesBefore + (accepted ? 1 : 0)
                       && shelf.dockCompletions == (accepted ? 1 : 0),
                       "an accepted panel drop notes interaction at drop time, before delivery")
            }
        }
        for revoked in 0..<5 {
            Context.Features.shelf.isAvailable = true
            Context.Switches.standard.enabled = true
            Context.Shelf.shared = Context.Shelf()
            let shelf = Context.Shelf.shared
            shelf.promises = 1
            let notch = Context.Notch()
            let canvas = NotchCanvasDrop()
            canvas.actions = NotchFileDropActions(
                canAccept: { _ in notch.canAcceptFileDrop }, enter: { _ in },
                accept: { notch.accept($0) }, exit: {})
            _ = canvas.begin(board, localSource: false)
            switch revoked {
            case 0: Context.Features.shelf.isAvailable = false
            case 1: Context.Switches.standard.enabled = false
            case 2: notch.modules = []
            case 3: notch.acceptsUserInteraction = false
            default: notch.captureControls = 1
            }
            suite.expect(!canvas.finish(board) && shelf.promisedAccepts == 0 && notch.opened.isEmpty,
                   "a destination disabled after hover cannot start an attachment delivery")
        }
        Context.Features.shelf.isAvailable = true
        Context.Switches.standard.enabled = true
        mediaDrops(suite)
    }

    private static func mediaDrops(_ suite: TestSuite) {
        let board = NSPasteboard.withUniqueName()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notch-media-drop-\(UUID().uuidString)", isDirectory: true)
        func reset() {
            Context.Features.shelf.isAvailable = true
            Context.Features.mediaTools.isAvailable = true
            Context.Switches.standard.enabled = true
            Context.IslandModules.enabled = true
            Context.IslandModules.visibleModules = [.files]
            Context.Shelf.shared = Context.Shelf()
            Context.FileTools.shared = Context.FileTools()
        }
        defer {
            board.releaseGlobally()
            try? FileManager.default.removeItem(at: folder)
            reset()
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let image = folder.appendingPathComponent("image.png")
            let secondImage = folder.appendingPathComponent("second.jpg")
            let video = folder.appendingPathComponent("video.mov")
            let note = folder.appendingPathComponent("note.txt")
            for url in [image, secondImage, video, note] { try Data([0]).write(to: url) }
            let inputs: [([URL], MediaTool?)] = [
                ([image], .imageCompressor), ([image, secondImage], .imageCompressor),
                ([video], .videoCompressor), ([video, image], nil), ([image, note], nil),
                ([video, video], nil), ([note], nil), ([folder], nil),
                ([folder.appendingPathComponent("missing.png")], nil),
                ([URL(string: "https://example.com/image.png")!], nil), ([], nil),
            ]
            for (urls, tool) in inputs {
                for optimize in [false, true] {
                    reset()
                    board.clearContents()
                    board.writeObjects(urls as [NSURL])
                    let notch = Context.Notch()
                    notch.beginFileDrop(board)
                    suite.expect(notch.choosingFileDropDestination == (tool != nil),
                           "only complete compatible file batches offer optimization: \(urls.map(\.lastPathComponent))")
                    let area = NotchFileToolsSupport.mediaDropArea(in: notch.geometry, size: notch.surfaceSize)
                    _ = notch.updateFileDrop(at: optimize ? CGPoint(x: area.midX, y: area.midY) : CGPoint(x: 40, y: area.midY))
                    let accepted = notch.accept(board)
                    let files = Context.FileTools.shared
                    suite.expect(accepted && files.service.mediaSession?.tool == (optimize ? tool : nil),
                           "dropping in each destination opens exactly its selected tool or the shelf")
                    if optimize, tool != nil {
                        suite.expect(files.inputs == urls && !notch.pinned && Context.Shelf.shared.ordinaryAccepts == 0,
                               "optimization receives the full input batch without pinning the island or shelving source files")
                    } else {
                        suite.expect(Context.Shelf.shared.ordinaryAccepts == 1 && !notch.pinned,
                               "ordinary drops keep the original shelf delivery path")
                    }
                    suite.expect(!notch.choosingFileDropDestination && !notch.targetsMediaDrop,
                           "a finished drop removes its transient destinations")
                }
            }
            reset()
            board.clearContents()
            let text = NSPasteboardItem()
            text.setString("companion", forType: .string)
            board.writeObjects([image as NSURL, text])
            suite.expect(Context.FileTools.shared.drop.content(for: board) == nil,
                   "a text companion prevents partial optimization of a mixed drag")

            for revoked in 0..<8 {
                reset()
                board.clearContents()
                board.writeObjects([image as NSURL])
                let notch = Context.Notch()
                notch.beginFileDrop(board)
                let area = NotchFileToolsSupport.mediaDropArea(in: notch.geometry, size: notch.surfaceSize)
                _ = notch.updateFileDrop(at: CGPoint(x: area.midX, y: area.midY))
                let files = Context.FileTools.shared
                switch revoked {
                case 0: Context.Features.mediaTools.isAvailable = false
                case 1: Context.Features.shelf.isAvailable = false
                case 2: Context.Switches.standard.enabled = false
                case 3: Context.IslandModules.enabled = false
                case 4: Context.IslandModules.visibleModules = []
                case 5: files.busy = true
                case 6: notch.acceptsUserInteraction = false
                default: notch.captureControls = 1
                }
                suite.expect(!notch.accept(board) && files.inputs.isEmpty && Context.Shelf.shared.ordinaryAccepts == 0,
                       "revoked access or running work rejects optimization without rerouting or replacing work")
                suite.expect(!notch.choosingFileDropDestination && !notch.targetsMediaDrop,
                       "a refused drop clears its transient presentation")
            }
            reset()
            board.clearContents()
            board.writeObjects([image as NSURL])
            let notch = Context.Notch()
            notch.beginFileDrop(board)
            let offered = notch.changes
            let area = NotchFileToolsSupport.mediaDropArea(in: notch.geometry, size: notch.surfaceSize)
            _ = notch.updateFileDrop(at: CGPoint(x: area.midX, y: area.midY))
            _ = notch.updateFileDrop(at: CGPoint(x: area.midX, y: area.midY))
            let targeted = notch.changes
            notch.endFileDrop()
            suite.expect(notch.choosingFileDropDestination == false && offered == 2 && targeted == 3 && notch.changes == 5,
                   "the island announces each change of the drop's destinations, and only a change")
            suite.expect(!notch.choosingFileDropDestination && Context.FileTools.shared.service.mediaSession == nil,
                   "leaving a drag never creates a media workspace")

            for initiallyPinned in [false, true] {
                reset()
                let repeatDrop = Context.Notch()
                repeatDrop.pinned = initiallyPinned
                let files = Context.FileTools.shared
                for (input, optimize) in [(image, true), (secondImage, false), (secondImage, true), (video, true)] {
                    board.clearContents()
                    board.writeObjects([input as NSURL])
                    repeatDrop.beginFileDrop(board)
                    suite.expect(repeatDrop.choosingFileDropDestination,
                           "every new compatible drag offers both destinations even with an existing media workspace")
                    let area = NotchFileToolsSupport.mediaDropArea(in: repeatDrop.geometry, size: repeatDrop.surfaceSize)
                    _ = repeatDrop.updateFileDrop(at: CGPoint(x: optimize ? area.midX : 40, y: area.midY))
                    suite.expect(repeatDrop.accept(board) && files.service.mediaPresented == optimize && repeatDrop.pinned == initiallyPinned,
                           "each drop follows its new destination and leaves the user's pin choice untouched")
                    if optimize { suite.expect(files.inputs == [input], "a new optimization replaces only the deliberately selected input") }
                    else { suite.expect(files.inputs == [image], "choosing the shelf hides media without discarding its previous work") }
                }
                let media = files.service
                let id = media.mediaSession!.id
                media.updateMediaHeight(id: id, height: 321.3)
                suite.expect(media.mediaContentHeight == 322, "media records its actual content height at a stable whole-point boundary")
                for rejected in [CGFloat.nan, .infinity, 0, -1] { media.updateMediaHeight(id: id, height: rejected) }
                media.updateMediaHeight(id: UUID(), height: 900)
                suite.expect(media.mediaContentHeight == 322, "invalid sizes and callbacks from a replaced workspace cannot stretch the island")
                media.updateMediaHeight(id: id, height: 240)
                suite.expect(media.mediaContentHeight == 240, "hiding extra media controls shrinks the recorded content height")
                files.busy = true
                repeatDrop.beginFileDrop(board)
                let area = NotchFileToolsSupport.mediaDropArea(in: repeatDrop.geometry, size: repeatDrop.surfaceSize)
                suite.expect(repeatDrop.choosingFileDropDestination
                       && !repeatDrop.updateFileDrop(at: CGPoint(x: area.midX, y: area.midY)),
                       "running media keeps the chooser available but cannot be overwritten by another drop")
                suite.expect(repeatDrop.updateFileDrop(at: CGPoint(x: 40, y: area.midY)) && repeatDrop.accept(board)
                       && !media.mediaPresented && media.mediaSession?.id == id,
                       "the shelf remains usable while an optimization continues without interruption")
                media.showMedia()
                suite.expect(media.mediaPresented && media.mediaSession?.id == id,
                       "returning to media resumes the same work and results")
                files.busy = false
                files.opens = false
                suite.expect(!files.drop.open(board) && media.mediaSession?.id == id,
                       "a tool that refuses its inputs cannot claim success using a previous media session")
            }

            for finishOutside in [false, true] {
                reset()
                board.clearContents()
                board.writeObjects([image as NSURL])
                let destination = Context.Notch()
                let canvas = NotchCanvasDrop()
                // The visible island, where the canvas reports the drag.
                let visible = CGRect(origin: .zero, size: destination.surfaceSize)
                canvas.actions = NotchFileDropActions(
                    canAccept: { _ in destination.canAcceptFileDrop },
                    enter: { destination.beginFileDrop($0) },
                    accept: { destination.accept($0) },
                    exit: { destination.endFileDrop() },
                    update: { destination.updateFileDrop(at: $0) })
                func moved(to point: CGPoint) -> NSDragOperation {
                    canvas.update(board, at: point, visible: visible.contains(point), localSource: false)
                }
                let area = NotchFileToolsSupport.mediaDropArea(in: destination.geometry, size: destination.surfaceSize)
                suite.expect(moved(to: CGPoint(x: 40, y: area.midY)) == .copy && !destination.targetsMediaDrop,
                       "native dragging starts on the shelf side")
                suite.expect(moved(to: CGPoint(x: area.midX, y: area.midY)) == .copy && destination.targetsMediaDrop,
                       "moving across the island highlights the media destination")
                let release = finishOutside ? CGPoint(x: -1, y: -1) : CGPoint(x: 40, y: area.midY)
                suite.expect(canvas.perform(board, at: release, visible: visible.contains(release)) == !finishOutside
                       && Context.FileTools.shared.service.mediaSession == nil,
                       "the release point is rechecked even when the last drag update targeted media")
                suite.expect(Context.Shelf.shared.ordinaryAccepts == (finishOutside ? 0 : 1)
                       && !destination.choosingFileDropDestination,
                       "releasing outside cancels cleanly and releasing over the shelf preserves its route")
            }
        } catch { suite.expect(false, "media drop fixtures failed: \(error)") }
    }
}
