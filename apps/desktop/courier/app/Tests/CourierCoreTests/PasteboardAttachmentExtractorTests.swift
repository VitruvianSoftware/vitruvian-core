// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import UniformTypeIdentifiers
import XCTest

@MainActor
final class PasteboardAttachmentExtractorTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteboardAttachmentExtractorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    private func makeTestImage(width: Int = 8, height: Int = 8) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    func testExtractsPNGClipboardImageAndAttachesToComposer() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        let image = makeTestImage()
        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        let pngData = try XCTUnwrap(rep.representation(using: .png, properties: [:]))

        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)

        XCTAssertTrue(PasteboardAttachmentExtractor.hasFilesOrImage(on: pasteboard))

        let fixedDate = Date(timeIntervalSince1970: 1_762_320_000)
        let urls = PasteboardAttachmentExtractor.extractFiles(
            from: pasteboard,
            tempDirectory: tempDir,
            now: fixedDate
        )
        XCTAssertEqual(urls.count, 1)
        let url = try XCTUnwrap(urls.first)
        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("Pasted Image "))
        XCTAssertEqual(try Data(contentsOf: url), pngData)

        let composer = ComposerModel()
        composer.open("!room:test")
        composer.attach(urls)
        XCTAssertEqual(composer.attachments.count, 1)
        XCTAssertEqual(composer.attachments.first?.url, url)
    }

    func testExtractsNSImageTIFFFromPasteboardAsPNG() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        let image = makeTestImage(width: 12, height: 12)
        pasteboard.clearContents()
        pasteboard.writeObjects([image])

        XCTAssertTrue(PasteboardAttachmentExtractor.hasFilesOrImage(on: pasteboard))

        let urls = PasteboardAttachmentExtractor.extractFiles(
            from: pasteboard,
            tempDirectory: tempDir
        )
        XCTAssertEqual(urls.count, 1)
        let url = try XCTUnwrap(urls.first)
        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertNotNil(NSImage(contentsOf: url))
    }

    func testMultiplePastesAtSameTimestampCreateDistinctAttachmentURLs() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        let image = makeTestImage()
        pasteboard.clearContents()
        pasteboard.writeObjects([image])

        let sameInstant = Date(timeIntervalSince1970: 1_762_320_000)
        let first = PasteboardAttachmentExtractor.extractFiles(
            from: pasteboard,
            tempDirectory: tempDir,
            now: sameInstant
        )
        let second = PasteboardAttachmentExtractor.extractFiles(
            from: pasteboard,
            tempDirectory: tempDir,
            now: sameInstant
        )
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertNotEqual(first.first, second.first)
        XCTAssertEqual(first.first?.lastPathComponent, second.first?.lastPathComponent)

        let composer = ComposerModel()
        composer.open("!room:test")
        composer.attach(first)
        composer.attach(second)
        XCTAssertEqual(composer.attachments.count, 2)
    }

    func testPrefersFileURLsOverPasteboardIconPreview() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        let existingFile = tempDir.appendingPathComponent("report.pdf")
        try Data("pdf-bytes".utf8).write(to: existingFile)

        let image = makeTestImage()
        pasteboard.clearContents()
        pasteboard.writeObjects([existingFile as NSURL, image])

        let urls = PasteboardAttachmentExtractor.extractFiles(
            from: pasteboard,
            tempDirectory: tempDir
        )
        XCTAssertEqual(urls, [existingFile])
    }

    func testIgnoresRichTextOrSpreadsheetCopyWithTIFFPreview() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        let image = makeTestImage()
        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let rtfData = Data("{\\rtf1\\ansi hello}".utf8)

        pasteboard.clearContents()
        pasteboard.declareTypes([.rtf, .string, .tiff], owner: nil)
        pasteboard.setData(rtfData, forType: .rtf)
        pasteboard.setString("hello from spreadsheet", forType: .string)
        pasteboard.setData(tiffData, forType: .tiff)

        XCTAssertFalse(PasteboardAttachmentExtractor.hasFilesOrImage(on: pasteboard))
        XCTAssertTrue(
            PasteboardAttachmentExtractor.extractFiles(
                from: pasteboard,
                tempDirectory: tempDir
            ).isEmpty
        )
    }
}
