// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Runs the production handoff of a history image to the screenshot editor,
/// on the real queues, with the history and the editor replaced by a record.
struct ClipboardHistoryImageEditorTests {
    /// What the handoff did. Only the main thread touches it.
    final class Record {
        var hidden = false
        var failures = 0
        var capture: ScreenshotSelectionController.Capture?
        var openedOnMain = false
    }

    static func editing(_ record: Record, directory: URL) -> ClipboardHistoryService.ImageEditing {
        .init(isAvailable: { true }, directory: { directory },
              background: { work in DispatchQueue.global(qos: .userInitiated).async { work() } },
              main: { work in DispatchQueue.main.async { work() } },
              beep: { record.failures += 1 },
              dismissHistory: { record.hidden = true },
              openEditor: { capture in
                  record.capture = capture
                  record.openedOnMain = Thread.isMainThread
              })
    }

    private static func pump(until done: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: 2)
        while !done(), Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        }
    }

    static func run(_ suite: TestSuite) {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 960, pixelsHigh: 640,
                                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                          isPlanar: false, colorSpaceName: .deviceRGB,
                                          bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: 0, y: 0)
            try bitmap.representation(using: .png, properties: [:])!.write(
                to: directory.appendingPathComponent("older.png"))
            let entry = ClipboardHistoryEntry(text: "", copiedAt: .distantPast, kind: .image,
                                               imageFile: "older.png", imageWidth: 960, imageHeight: 640)
            let record = Record()
            let changeCount = NSPasteboard.general.changeCount
            ClipboardHistoryService.editImage(entry, editing: editing(record, directory: directory))
            pump { record.capture != nil }
            let capture = record.capture
            suite.expect(capture?.image.width == 960 && capture?.image.height == 640,
                         "history handoff opens the original image in the screenshot editor")
            suite.expect(capture?.scale == 1 && capture?.anchorRect == .zero,
                         "stored image uses the shared editor conversion and no screen anchor")
            suite.expect(record.hidden && record.openedOnMain,
                         "history dismisses and presents the editor on the main thread")
            let image = ClipboardHistoryImageSupport.editorImage(for: entry, directory: directory)
            var rect = CGRect(origin: .zero, size: image?.size ?? .zero)
            let original = image?.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            suite.expect(original?.width == 960 && original?.height == 640,
                         "editing an older entry loads the stored original beyond thumbnail resolution")
            let pixel = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                  bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            if let corner = original?.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)) {
                pixel.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            let bytes = pixel.data!.assumingMemoryBound(to: UInt8.self)
            suite.expect(bytes[0] == 255 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 255,
                         "the editor receives the selected historical image pixels")
            suite.expect(NSPasteboard.general.changeCount == changeCount,
                         "loading a historical image does not replace the current clipboard")
            try FileManager.default.removeItem(at: directory.appendingPathComponent("older.png"))
            let missing = Record()
            ClipboardHistoryService.editImage(entry, editing: editing(missing, directory: directory))
            pump { missing.failures > 0 }
            suite.expect(missing.failures == 1 && missing.capture == nil && !missing.hidden,
                         "a missing image reports failure without dismissing history or opening an editor")
            suite.expect(ClipboardHistoryImageSupport.editorImage(for: entry, directory: directory) == nil,
                         "a removed historical image cannot fall back to the current clipboard")
            try Data("not an image".utf8).write(to: directory.appendingPathComponent("older.png"))
            suite.expect(ClipboardHistoryImageSupport.editorImage(for: entry, directory: directory) == nil,
                         "a corrupt stored image is rejected")
            for unsupported in [ClipboardHistoryEntry(text: "plain text"),
                                ClipboardHistoryEntry(text: "", kind: .files, filePaths: ["older.png"]),
                                ClipboardHistoryEntry(text: "", kind: .image),
                                ClipboardHistoryEntry(text: "", kind: .image, imageFile: "../older.png")] {
                suite.expect(ClipboardHistoryImageSupport.editorImage(for: unsupported, directory: directory) == nil,
                             "only a named image inside the history store can be edited")
            }
        } catch {
            suite.expect(false, "history image editor fixture: \(error)")
        }
    }
}
