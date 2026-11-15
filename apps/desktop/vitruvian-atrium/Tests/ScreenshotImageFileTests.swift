// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import UniformTypeIdentifiers
import VitruvianAtriumCore
import VitruvianAtriumDesign
import VitruvianAtriumServices
import VitruvianAtriumUI

/// The editor's file outputs, through the production encoder and the
/// screenshot service's save, drag and share paths. The save settings go in
/// the test's own `UserDefaults.standard` (a container under the test's
/// TEST_TMPDIR) and are removed afterwards.
enum ScreenshotImageFileTests {
    private typealias Service = ScreenshotService

    static func run(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let keys = [DefaultsKey.screenshotSaveFolder, DefaultsKey.screenshotFileNamePattern,
                    DefaultsKey.screenshotFileNumberNext]
        defer {
            try? FileManager.default.removeItem(at: folder)
            for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            UserDefaults.standard.set(folder.path, forKey: DefaultsKey.screenshotSaveFolder)
            UserDefaults.standard.set("edited-%#", forKey: DefaultsKey.screenshotFileNamePattern)
            UserDefaults.standard.set(7, forKey: DefaultsKey.screenshotFileNumberNext)
            let context = CGContext(data: nil, width: 128, height: 96, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 128, height: 96))
            let opaque = context.makeImage()!
            let export = ScreenshotRenderer.Export(image: opaque, scale: 2)
            for preferred in [MediaImageFormat.jpeg, .png, .heic, .pdf] {
                guard let file = ScreenshotImageFile.encode(export, preferredFormat: preferred),
                      let source = CGImageSourceCreateWithData(file.data as CFData, nil) else {
                    suite.expect(false, "the editor can encode \(preferred.rawValue) or its PNG fallback")
                    continue
                }
                suite.expect(CGImageSourceGetType(source) as String? == file.format.contentType.identifier,
                             "file data and extension agree after preferred-format encoding or fallback")
                if preferred == .jpeg || preferred == .png {
                    suite.expect(file.format == preferred, "an opaque \(preferred.rawValue) keeps its source format")
                }
                if preferred == .pdf {
                    suite.expect(file.format == .png, "a document is exported as a static PNG rather than claiming its original structure")
                }
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                suite.expect((properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == 128
                    && (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == 96,
                             "file encoding preserves the edited pixel dimensions")
                if file.format == .jpeg || file.format == .png {
                    suite.expect((properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue == 144,
                                 "file encoding preserves the editor DPI scale")
                }
                let destination = Service.saveDestination(strings: .enUS, fileExtension: file.format.fileExtension)
                try file.data.write(to: destination.url)
                suite.expect(destination.url.deletingLastPathComponent().path == folder.path
                    && destination.url.pathExtension == file.format.fileExtension
                    && destination.consumedNumber != nil,
                             "saving retains the configured folder and number sequence with the actual format")
            }
            let defaultDestination = Service.saveDestination(strings: .enUS)
            suite.expect(defaultDestination.url.pathExtension == "png", "ordinary screenshots keep their default PNG naming")
            guard let dragged = Service.temporaryExportFile(image: opaque, scale: 2,
                                                            strings: .enUS, preferredFormat: .jpeg) else {
                suite.expect(false, "an imported JPEG can be exported as a drag file")
                return
            }
            defer { try? FileManager.default.removeItem(at: dragged.deletingLastPathComponent()) }
            let dragSource = CGImageSourceCreateWithURL(dragged as CFURL, nil)
            suite.expect(dragged.pathExtension == "jpg" && dragSource.flatMap(CGImageSourceGetType) as String? == "public.jpeg",
                         "drag files use matching JPEG bytes and extension")
            checkDrag(Service.dragItemProvider(image: opaque, scale: 2, strings: .enUS,
                                               preferredFormat: .jpeg), format: .jpeg, suite: suite)
            checkDrag(Service.dragItemProvider(image: opaque, scale: 2, strings: .enUS),
                      format: .png, suite: suite)
            context.clear(CGRect(x: 3, y: 4, width: 1, height: 1))
            checkDrag(Service.dragItemProvider(image: context.makeImage()!, scale: 2,
                                               strings: .enUS, preferredFormat: .jpeg),
                      format: .png, suite: suite)
        } catch {
            suite.expect(false, "file-output fixtures: \(error)")
        }
        transparency(suite)
    }

    private static func checkDrag(_ provider: NSItemProvider?, format: MediaImageFormat, suite: TestSuite) {
        guard let provider, provider.hasItemConformingToTypeIdentifier(format.contentType.identifier) else {
            suite.expect(false, "the drag provider advertises the source format or transparent PNG fallback")
            return
        }
        // The provider answers on its own queue; the result comes back to
        // the main thread through a box (Swift 6 forbids sending a captured var).
        nonisolated final class Delivery: @unchecked Sendable {
            var finished = false
            var matches = false
        }
        let delivery = Delivery()
        provider.loadInPlaceFileRepresentation(forTypeIdentifier: format.contentType.identifier) { url, inPlace, error in
            let source = url.flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
            let valid = error == nil && url.flatMap { UTType(filenameExtension: $0.pathExtension) } == format.contentType
                && source.flatMap(CGImageSourceGetType) as String? == format.contentType.identifier
            if inPlace, let folder = url?.deletingLastPathComponent(),
               folder.lastPathComponent.hasPrefix("ScreenshotDrag-") {
                try? FileManager.default.removeItem(at: folder)
            }
            DispatchQueue.main.async {
                delivery.matches = valid
                delivery.finished = true
            }
        }
        let deadline = Date(timeIntervalSinceNow: 2)
        while !delivery.finished, Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        }
        suite.expect(delivery.finished && delivery.matches, "the drag provider delivers matching bytes and extension for \(format.rawValue)")
    }

    private static func transparency(_ suite: TestSuite) {
        let layouts: [CGBitmapInfo] = [
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Big),
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).union(.byteOrder32Little)
        ]
        for layout in layouts {
            guard let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: layout.rawValue) else {
                suite.expect(false, "the transparency fixture supports its bitmap layout")
                continue
            }
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            let opaque = ScreenshotImageFile.encode(.init(image: context.makeImage()!, scale: 1), preferredFormat: .jpeg)
            suite.expect(opaque?.format == .jpeg, "opaque pixels with zero color channels are not mistaken for transparency")
            context.clear(CGRect(x: 3, y: 4, width: 1, height: 1))
            let file = ScreenshotImageFile.encode(.init(image: context.makeImage()!, scale: 1), preferredFormat: .jpeg)
            suite.expect(file?.format == .png, "even one transparent interior pixel switches JPEG output to lossless PNG")
            if let file, let source = CGImageSourceCreateWithData(file.data as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                suite.expect(ScreenshotCanvasSupportTests.pixel(image, x: 3, y: 3)[3] == 0,
                             "the PNG fallback preserves the transparent pixel")
            } else {
                suite.expect(false, "the transparent PNG fallback is readable")
            }
        }
    }
}
