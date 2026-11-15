// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import Foundation
import UniformTypeIdentifiers
import VitruvianAtriumCore
import VitruvianAtriumDesign
import VitruvianAtriumServices
import VitruvianAtriumUI

/// The editor's export format, GIF size and frame rate controls, on the
/// production editor model. The recording opens as a 1920×1080 picture; no
/// file sits behind the take and the preview composes nothing.
enum RecorderExportControlsTests {
    static func run(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitru-recorder-export-controls-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suiteName = "vitru.tests.recorder-export-controls-\(UUID().uuidString)"
        defer {
            UserDefaults().removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: folder)
        }
        let source = RecorderEditorModel.Environment.Source(
            duration: 5, size: CGSize(width: 1920, height: 1080), frameRate: 60, audioTracks: [:])
        let environment = RecorderEditorModel.Environment(
            defaults: ScratchDefaults.suite(named: suiteName)!,
            loadSource: { _ in source },
            previewDelay: 0,
            composePreview: { _ in .composition(nil) })
        let model = RecorderEditorModel(take: RecorderTakeStore.Take(id: UUID(), folder: folder),
                                        environment: environment)
        let deadline = Date(timeIntervalSinceNow: 2)
        while model.sourceSize.width == 0, Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        }
        suite.expect(model.sourceSize == CGSize(width: 1920, height: 1080), "the editor opens the 1920×1080 take")

        var gif = model.document
        gif.exportFormat = "gif"
        gif.gifScalePercent = 50
        model.document = gif
        suite.expect(model.exportSize == CGSize(width: 960, height: 540),
                     "editor dimensions follow selected GIF scale independently of video quality")
        model.setGIFScalePercent(1)
        suite.expect(model.exportSize == CGSize(width: 56, height: 32),
                     "editor GIF dimensions reflect the encoder minimum short side")
        model.setExportFormat(.video)
        suite.expect(model.exportSize == CGSize(width: 1920, height: 1080),
                     "switching back to video restores its independent quality dimensions")
        model.setGIFScalePercent(75)
        model.setGIFFrameRate(20)
        model.setExportFormat(.gif)
        suite.expect(model.document.quality == "balanced"
            && model.document.resolvedGIFScalePercent == 75
            && model.document.resolvedGIFFrameRate == 20,
                     "format, GIF size and FPS edits preserve independent video quality")
        model.setGIFScalePercent(400)
        model.setGIFFrameRate(99)
        suite.expect(model.document.gifScalePercent == 100 && model.document.gifFrameRate == 12,
                     "the controls clamp GIF size and reject an out-of-range frame rate")

        // A GIF on its way to the clipboard keeps the editor busy.
        let beforeBusyEdit = model.document
        let publication = model.beginClipboardPublication()
        model.setExportFormat(.video)
        model.setGIFScalePercent(50)
        model.setGIFFrameRate(10)
        suite.expect(model.isExporting && model.document == beforeBusyEdit,
                     "export controls reject edits while export is in progress")
        model.cancelExport()
        suite.expect(!model.isExporting && publication.isCancelled,
                     "cancelling queued GIF publication immediately releases the editor")
        suite.expect(!model.completeClipboardPublication(publication),
                     "late GIF publication after cancellation cannot finish the copy")

        let stale = model.beginClipboardPublication()
        model.cancelExport()
        let current = model.beginClipboardPublication()
        suite.expect(!model.completeClipboardPublication(stale) && model.isExporting,
                     "stale publication completion cannot clear a later export's busy state")
        suite.expect(model.completeClipboardPublication(current) && !model.isExporting,
                     "uncancelled GIF publication completes and releases the editor")

        for format in [RecorderSupport.ExportFormat.video, .gif] {
            let selection = RecorderEditorExportSelection(format: format)
            suite.expect(selection.output == (format == .gif ? .gif : .video)
                    && selection.fileExtension == (format == .gif ? "gif" : "mp4"),
                         "save and copy choose the selected format's encoder and extension")
            suite.expect(selection.contentType.identifier
                    == (format == .gif ? "com.compuserve.gif" : "public.mpeg-4"),
                         "Save As uses the selected format content type")
        }
        suite.expect(RecorderSupport.gifOutputSize(source: CGSize(width: 768, height: 432), scalePercent: 25)
                == CGSize(width: 192, height: 108)
                && RecorderSupport.gifOutputSize(source: CGSize(width: 768, height: 432), scalePercent: 250)
                == CGSize(width: 768, height: 432),
                     "GIF scale is a percentage of the canvas, never above full size")
    }
}
