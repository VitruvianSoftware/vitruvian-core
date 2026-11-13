// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import VitruvianAtriumCore
import VitruvianAtriumDesign
import VitruvianAtriumServices
import VitruvianAtriumUI

enum ScreenshotImageImportTests {
    static func run(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.screenshot(language)
            suite.expect([strings.largeImageTitle, strings.largeImageMessageFormat,
                          strings.editReducedImage,
                          strings.imageImportFailed].allSatisfy { !$0.isEmpty },
                         "large-image choices and failures are localized in \(language.rawValue)")
        }
        let resize = MediaImageResizeMode.maxDimension(ScreenshotImageImport.maximumDimension)
        suite.expect(resize.targetSize(for: CGSize(width: 11479, height: 8199)) == CGSize(width: 6000, height: 4286),
                     "editor reduction uses the media longest-side sizing policy")
        suite.expect(resize.targetSize(for: CGSize(width: 40, height: 20)) == CGSize(width: 40, height: 20),
                     "the longest-side policy never enlarges a small image")
        for edge in [6000, 6001] {
            let image = ScreenshotCanvasSupportTests.image(width: edge, height: 1)
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            let input = ScreenshotImageImport(data: data)
            suite.expect(input?.requiresSizeChoice == (edge > 6000)
                && input?.reducedMaximumDimension == 6000,
                         "the size prompt starts above the 6000-pixel longest side, regardless of area")
            suite.expect(input?.decode()?.image.width == 6000,
                         "the import decoder never bypasses the 6000-pixel limit")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer {
            board.releaseGlobally()
            try? FileManager.default.removeItem(at: folder)
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            let bitmap = NSBitmapImageRep(cgImage: ScreenshotCanvasSupportTests.image(width: 40, height: 20))
            bitmap.size = CGSize(width: 20, height: 10)
            let data = bitmap.representation(using: .png, properties: [:])!
            let url = folder.appendingPathComponent("source.png")
            try data.write(to: url)
            board.writeObjects([url as NSURL])
            board.setData(NSBitmapImageRep(cgImage: ScreenshotCanvasSupportTests.image(width: 2, height: 2))
                .representation(using: .tiff, properties: [:]), forType: .tiff)
            let input = ScreenshotImageImport(pasteboard: board)
            suite.expect(input?.pixelSize == CGSize(width: 40, height: 20)
                && input?.requiresSizeChoice == false,
                         "a copied file wins over its small clipboard preview without decoding it")
            let original = input?.decode()
            suite.expect(original?.image.width == 40 && original?.image.height == 20 && original?.scale == 2,
                         "small-image import preserves full pixels and DPI scale")
            let smaller = CGImageSourceCreateWithData(data as CFData, nil)
                .flatMap { MediaImageProcessing.decode($0, maximumDimension: 10) }
            suite.expect(smaller?.width == 10 && smaller?.height == 5,
                         "Image I/O reduces pixels proportionally rather than only compressing file bytes")
            suite.expect(try Data(contentsOf: url) == data, "image import leaves the source file unchanged")
            board.clearContents()
            board.setData(data, forType: .png)
            suite.expect(ScreenshotImageImport(pasteboard: board)?.decode()?.image.width == 40,
                         "plain clipboard PNG data still opens without a file URL")
            board.clearContents()
            board.setData(bitmap.representation(using: .tiff, properties: [:]), forType: .tiff)
            suite.expect(ScreenshotImageImport(pasteboard: board)?.decode()?.scale == 2,
                         "plain clipboard TIFF data retains its image density")
            let jpeg = NSMutableData()
            let destination = CGImageDestinationCreateWithData(jpeg, "public.jpeg" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, bitmap.cgImage!,
                                      [kCGImagePropertyOrientation: 6] as CFDictionary)
            suite.expect(CGImageDestinationFinalize(destination), "the oriented image fixture can be encoded")
            let rotated = ScreenshotImageImport(data: jpeg as Data)
            suite.expect(rotated?.sourceFormat == .jpeg, "the input format survives oriented image import")
            suite.expect(rotated?.pixelSize == CGSize(width: 20, height: 40)
                && rotated?.decode()?.image.width == 20 && rotated?.decode()?.image.height == 40,
                         "metadata and image import honor EXIF orientation")
            let pdf = NSMutableData()
            var page = CGRect(x: 0, y: 0, width: 40, height: 20)
            let context = CGContext(consumer: CGDataConsumer(data: pdf)!, mediaBox: &page, nil)!
            context.beginPDFPage(nil)
            context.fill(page)
            context.endPDFPage()
            context.closePDF()
            let pdfURL = folder.appendingPathComponent("source.pdf")
            try (pdf as Data).write(to: pdfURL)
            suite.expect(ScreenshotImageImport(url: pdfURL)?.decode() != nil,
                         "file editing retains the AppKit fallback for images Image I/O cannot decode")
            board.clearContents()
            board.setString("plain text", forType: .string)
            suite.expect(ScreenshotImageImport(pasteboard: board) == nil
                && ScreenshotImageImport(data: Data("broken image".utf8)) == nil,
                         "text and malformed images are rejected")
        } catch {
            suite.expect(false, "image import fixtures: \(error)")
        }
        nativeClipboardImages(suite, heic: primaryHEIC(suite))
    }

    private static func primaryHEIC(_ suite: TestSuite) -> Data? {
        // Image I/O encoded a red 128x96 secondary image and a blue 6001x32
        // primary image at index 1 with EXIF orientation 6. Keeping the fixture
        // avoids requiring a HEIC encoder on the machine running these tests.
        let url = URL(fileURLWithPath: "Tests/Fixtures/ScreenshotPrimaryImage.heic")
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            suite.expect(false, "the multi-image HEIC fixture is readable")
            return nil
        }
        suite.expect(CGImageSourceGetCount(source) == 2 && CGImageSourceGetPrimaryImageIndex(source) == 1,
                     "the HEIC fixture's primary image is not its first image")
        for input in [ScreenshotImageImport(url: url), ScreenshotImageImport(data: data)] {
            suite.expect(input?.pixelSize == CGSize(width: 32, height: 6001)
                && input?.requiresSizeChoice == true && input?.sourceFormat == .png,
                         "HEIC file and data imports use oriented primary-image dimensions for the size choice")
            guard let decoded = input?.decode() else {
                suite.expect(false, "the primary HEIC image can be decoded")
                continue
            }
            suite.expect(decoded.image.width == 32 && decoded.image.height == 6000,
                         "HEIC import reduces the selected primary image rather than its smaller sibling")
            let pixel = ScreenshotCanvasSupportTests.pixel(decoded.image, x: 8, y: 8)
            suite.expect(pixel[2] > 230 && pixel[0] < 30,
                         "the imported HEIC pixels belong to the blue primary image")
        }
        let first = MediaImageProcessing.decode(source, maximumDimension: 6000)
        suite.expect(first?.width == 128 && first?.height == 96,
                     "media callers that omit the image index retain their first-image decoding policy")
        let unscaled = MediaImageProcessing.decode(source, at: 1, maximumDimension: 10_000)
        suite.expect(unscaled?.width == 32 && unscaled?.height == 6001,
                     "explicit image selection applies orientation without enlarging smaller images")
        suite.expect((try? Data(contentsOf: url)) == data, "HEIC import leaves the source file unchanged")
        return data
    }

    private final class PromisedTIFF: NSObject, NSPasteboardItemDataProvider {
        let data: Data
        var reads = 0
        init(data: Data) {
            self.data = data
            super.init()
        }
        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                        provideDataForType type: NSPasteboard.PasteboardType) {
            reads += 1
            item.setData(data, forType: type)
        }
    }

    private static func nativeClipboardImages(_ suite: TestSuite, heic: Data?) {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let bitmap = NSBitmapImageRep(cgImage: ScreenshotCanvasSupportTests.image(width: 6001, height: 1))
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [:]),
              let tiff = NSBitmapImageRep(cgImage: ScreenshotCanvasSupportTests.image(width: 40, height: 20))
                .tiffRepresentation else {
            suite.expect(false, "native clipboard fixtures can be encoded")
            return
        }
        // A single blue 6001x32 image encoded by Image I/O, so preserving the
        // HEIC source format is tested without needing an encoder at runtime.
        let singleURL = URL(fileURLWithPath: "Tests/Fixtures/ScreenshotNativeImage.heic")
        guard let singleHEIC = try? Data(contentsOf: singleURL) else {
            suite.expect(false, "the single-image HEIC fixture is readable")
            return
        }
        var samples: [(type: NSPasteboard.PasteboardType, data: Data,
                       format: MediaImageFormat, width: Int, height: Int)] = [
            (.init("public.jpeg"), jpeg, .jpeg, 6001, 1),
            (.init("public.heic"), singleHEIC, .heic, 6001, 32)
        ]
        if let heic { samples.append((.init("public.heic"), heic, .png, 32, 6001)) }
        for sample in samples {
            board.clearContents()
            suite.expect(board.setData(sample.data, forType: sample.type),
                         "the private clipboard accepts native \(sample.type.rawValue) data")
            let native = ScreenshotImageImport(pasteboard: board)
            suite.expect(native?.sourceFormat == sample.format && native?.requiresSizeChoice == true
                && native?.pixelSize == CGSize(width: sample.width, height: sample.height),
                         "native clipboard images preserve their format policy and primary dimensions")

            let provider = PromisedTIFF(data: tiff)
            let item = NSPasteboardItem()
            item.setData(sample.data, forType: sample.type)
            item.setDataProvider(provider, forTypes: [.tiff])
            board.clearContents()
            suite.expect(board.writeObjects([item]), "the private clipboard accepts a deferred TIFF fallback")
            let input = ScreenshotImageImport(pasteboard: board)
            suite.expect(provider.reads == 0 && input?.requiresSizeChoice == true
                && input?.sourceFormat == sample.format,
                         "native JPEG and HEIC metadata are read without materializing the TIFF fallback")
            let decoded = input?.decode()
            suite.expect(decoded?.image.width == min(6000, sample.width)
                && decoded?.image.height == min(6000, sample.height)
                && provider.reads == 0,
                         "confirmed native clipboard imports resize without requesting TIFF data")
        }

        let provider = PromisedTIFF(data: tiff)
        let item = NSPasteboardItem()
        item.setData(Data("broken jpeg".utf8), forType: .init("public.jpeg"))
        item.setDataProvider(provider, forTypes: [.tiff])
        board.clearContents()
        suite.expect(board.writeObjects([item]), "the fallback fixture reaches the private clipboard")
        let fallback = ScreenshotImageImport(pasteboard: board)
        suite.expect(provider.reads == 1 && fallback?.sourceFormat == .png
            && fallback?.pixelSize == CGSize(width: 40, height: 20)
            && fallback?.decode()?.image.width == 40,
                     "invalid native data still falls back to a valid promised TIFF")
    }
}
