// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Runs the editor's actual aiming lifecycle, and the undo that can take its
/// zoom away, on the production editor model. The recording opens as a
/// five-second 1000×500 picture and the preview composer only counts what it
/// is asked for: no file sits behind the take and nothing is decoded.
enum RecorderZoomAimingTests {
    /// What the preview was asked to compose, and what it handed back.
    final class Composer {
        var count = 0
        let composition: AVMutableVideoComposition = {
            let composition = AVMutableVideoComposition()
            composition.frameDuration = CMTime(value: 1, timescale: 60)
            composition.renderSize = CGSize(width: 1000, height: 1000)
            return composition
        }()
    }

    /// One open editor over a take in a scratch folder.
    final class Stage {
        let model: RecorderEditorModel
        let composer: Composer
        private let folder: URL
        private let suiteName: String

        init() {
            folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("vitru-recorder-aiming-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let suiteName = "vitru.tests.recorder-aiming-\(UUID().uuidString)"
            self.suiteName = suiteName
            let composer = Composer()
            self.composer = composer
            let source = RecorderEditorModel.Environment.Source(
                duration: 5, size: CGSize(width: 1000, height: 500), frameRate: 60, audioTracks: [:])
            let environment = RecorderEditorModel.Environment(
                defaults: UserDefaults(suiteName: suiteName)!,
                loadSource: { _ in source },
                previewDelay: 0,
                composePreview: { _ in
                    composer.count += 1
                    return .composition(composer.composition)
                })
            model = RecorderEditorModel(take: RecorderTakeStore.Take(id: UUID(), folder: folder),
                                        environment: environment)
            Self.pump { self.model.duration > 0 }
            // A square picture from a wide recording always has a plan to
            // compose, with or without a zoom.
            model.document.aspect = RecorderSupport.Aspect.square.rawValue
            settle()
        }

        func tearDown() {
            UserDefaults().removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: folder)
        }

        /// One zoom over the whole recording, added as its own edit.
        func addZoom() -> UUID {
            let zoom = RecorderTimeline.ZoomSegment(start: 0, end: 5, amount: 2)
            model.document.zoomSegments = [zoom]
            settle()
            return zoom.id
        }

        var showsComposition: Bool { model.player.currentItem?.videoComposition != nil }

        func focus(_ id: UUID) -> CGPoint? {
            guard let zoom = model.zoom(id), let x = zoom.focusX, let y = zoom.focusY else { return nil }
            return CGPoint(x: x, y: y)
        }

        /// Lets the main actor run what the editor queued: its load, and any
        /// preview it asked for.
        func settle() {
            let deadline = Date(timeIntervalSinceNow: 0.03)
            while Date() < deadline {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
            }
        }

        /// The preview was composed again, exactly once, since `count`.
        func composedOnce(since count: Int) -> Bool {
            Self.pump { self.composer.count > count }
            settle()
            return composer.count == count + 1 && showsComposition
        }

        private static func pump(until done: () -> Bool) {
            let deadline = Date(timeIntervalSinceNow: 2)
            while !done(), Date() < deadline {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
            }
        }
    }

    static func run(_ suite: TestSuite) {
        aiming(suite)
        removedByUndo(suite)
        blurArea(suite)
    }

    private static func aiming(_ suite: TestSuite) {
        let stage = Stage()
        defer { stage.tearDown() }
        let model = stage.model
        let id = stage.addZoom()
        suite.expect(stage.composer.count > 0 && stage.showsComposition,
                     "an edited recording shows its composed preview")

        var count = stage.composer.count
        model.beginAiming()
        suite.expect(!model.isAimingZoom && stage.showsComposition,
                     "aiming requires a selected zoom and otherwise leaves the preview alone")
        model.selectedZoomID = id
        model.play()
        model.beginAiming()
        suite.expect(model.isAimingZoom && !model.isPlaying && !stage.showsComposition,
                     "choosing a zoom focus pauses and removes the composed zoom and backdrop")
        model.aim(at: CGPoint(x: 150, y: 125), in: CGSize(width: 200, height: 200))
        suite.expect(stage.focus(id) == CGPoint(x: 0.75, y: 0.75) && !model.isAimingZoom
                     && stage.composedOnce(since: count),
                     "a click maps through the full letterboxed source and restores the edited preview")

        count = stage.composer.count
        model.beginAiming()
        model.endAiming()
        suite.expect(!model.isAimingZoom && stage.composedOnce(since: count),
                     "Escape restores the edited preview without changing the selected focus")
        count = stage.composer.count
        model.endAiming()
        stage.settle()
        suite.expect(stage.composer.count == count, "ending an inactive picker does not rebuild again")

        model.beginAiming()
        model.aim(at: CGPoint(x: 10, y: 10), in: CGSize(width: 200, height: 200))
        suite.expect(stage.focus(id) == CGPoint(x: 0.75, y: 0.75) && stage.composedOnce(since: count),
                     "a click outside the source keeps the old focus and still restores the preview")

        count = stage.composer.count
        model.endAiming()
        model.beginAiming()
        model.endAiming()
        model.beginAiming()
        stage.settle()
        suite.expect(stage.composer.count == count && !stage.showsComposition,
                     "a preview still on its way is dropped when aiming begins again")

        count = stage.composer.count
        model.selectedZoomID = nil
        suite.expect(!model.isAimingZoom && stage.composedOnce(since: count),
                     "deselecting or deleting the zoom exits raw-preview mode")

        model.selectedZoomID = id
        model.beginAiming()
        model.selectedBlurID = UUID()
        model.beginPickingBlurArea()
        stage.settle()
        suite.expect(!model.isAimingZoom && model.isPickingBlurArea && !stage.showsComposition,
                     "switching to blur selection leaves only one active picker over the full source")
        model.beginAiming()
        stage.settle()
        suite.expect(model.isAimingZoom && !model.isPickingBlurArea && !stage.showsComposition,
                     "switching back to zoom aiming ends blur selection")

        count = stage.composer.count
        model.setSelectedZoomFocus(nil)
        suite.expect(stage.focus(id) == nil && !model.isAimingZoom && stage.composedOnce(since: count),
                     "following the pointer cancels manual aiming and restores the edited preview")
        count = stage.composer.count
        model.beginAiming()
        model.setSelectedZoomFocus(nil)
        suite.expect(!model.isAimingZoom && stage.composedOnce(since: count),
                     "following the pointer restores the preview even when the focus was already unset")
    }

    /// Undo can take away the zoom being aimed. Its selection goes with it,
    /// or the next click on the picture would set the focus of nothing.
    private static func removedByUndo(_ suite: TestSuite) {
        let stage = Stage()
        defer { stage.tearDown() }
        let model = stage.model
        let added = stage.addZoom()
        model.selectedZoomID = added
        model.beginAiming()
        let count = stage.composer.count
        model.undo()
        suite.expect(model.zoom(added) == nil && model.selectedZoomID == nil,
                     "undoing a zoom's creation also clears its selection")
        suite.expect(!model.isAimingZoom && stage.composedOnce(since: count),
                     "undo ends aiming at the removed zoom and restores the edited preview")
        model.beginAiming()
        suite.expect(!model.isAimingZoom, "aiming cannot begin for a zoom that undo removed")
        model.redo()
        suite.expect(model.zoom(added) != nil && model.selectedZoomID == nil,
                     "redo brings the zoom back without reviving the stale selection")
        model.selectedZoomID = added
        var replaced = model.document
        replaced.zoomSegments = []
        model.document = replaced
        suite.expect(model.selectedZoomID == nil && model.canUndo,
                     "an ordinary edit that replaces the zooms drops the selection and stays undoable")
        model.undo()
        suite.expect(model.zoom(added) != nil, "undoing that edit brings the zoom back")

        let blurred = Stage()
        defer { blurred.tearDown() }
        let blur = RecorderBlurRegion(start: 0, end: 5)
        blurred.model.document.blurs = [blur]
        blurred.settle()
        blurred.model.selectedBlurID = blur.id
        blurred.model.beginPickingBlurArea()
        let rebuilds = blurred.composer.count
        blurred.model.undo()
        suite.expect(blurred.model.document.blurs.isEmpty && blurred.model.selectedBlurID == nil,
                     "undoing a blur's creation also clears its selection")
        suite.expect(!blurred.model.isPickingBlurArea && blurred.composedOnce(since: rebuilds),
                     "undo ends drawing the removed blur's area and restores the edited preview")
    }

    /// A drag on the stage redraws the selected blur's area in the recorded
    /// picture's own space and keeps everything else about it.
    private static func blurArea(_ suite: TestSuite) {
        let stage = Stage()
        defer { stage.tearDown() }
        let model = stage.model
        let blur = RecorderBlurRegion(start: 1, end: 4, strength: 5)
        model.document.blurs = [blur]
        stage.settle()
        model.selectedBlurID = blur.id
        model.beginPickingBlurArea()
        let count = stage.composer.count
        model.pickBlurArea(from: CGPoint(x: 50, y: 75), to: CGPoint(x: 150, y: 100),
                           in: CGSize(width: 200, height: 200))
        let drawn = model.document.blurs.first
        suite.expect(drawn.map { abs($0.x - 0.25) < 0.0001 && abs($0.y - 0.25) < 0.0001
                                 && abs($0.width - 0.5) < 0.0001 && abs($0.height - 0.25) < 0.0001 } == true,
                     "a drag sets the blur's area in the recorded picture's own space")
        suite.expect(drawn?.strength == 5 && drawn?.start == 1 && drawn?.end == 4,
                     "redrawing a blur's area keeps its strength")
        suite.expect(!model.isPickingBlurArea && stage.composedOnce(since: count),
                     "drawing the area ends the picker and restores the edited preview")
        model.undo()
        suite.expect(model.document.blurs == [blur], "one undo takes the drawn area back")
    }
}
