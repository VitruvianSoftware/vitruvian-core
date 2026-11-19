// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import VitruvianCourierCore

/// Pictures in a chat are made small off the main actor and kept, a bounded number, so scrolling back is cheap.
final class ThumbnailLoaderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vitruvian-courier-thumbnails-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A plain grey PNG of the given size.
    private func makePNG(_ name: String, width: Int, height: Int) throws -> String {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let url = directory.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url.path
    }

    func testABigPictureIsMadeNoBiggerThan640() async throws {
        let path = try makePNG("big.png", width: 2000, height: 1000)
        let loader = ThumbnailLoader()
        let thumbnail = await loader.thumbnail(atPath: path)
        let image = try XCTUnwrap(thumbnail?.image)
        XCTAssertEqual(image.width, 640)
        XCTAssertEqual(image.height, 320, "the proportions stay")

        let tall = try makePNG("tall.png", width: 600, height: 3000)
        let tallThumbnail = await loader.thumbnail(atPath: tall)
        let tallImage = try XCTUnwrap(tallThumbnail?.image)
        XCTAssertEqual(tallImage.height, 640)
        XCTAssertEqual(tallImage.width, 128)
    }

    func testASmallPictureIsNotEnlarged() async throws {
        let path = try makePNG("small.png", width: 120, height: 60)
        let thumbnail = await ThumbnailLoader().thumbnail(atPath: path)
        let image = try XCTUnwrap(thumbnail?.image)
        XCTAssertEqual(image.width, 120)
        XCTAssertEqual(image.height, 60)
    }

    func testTheSizeOfAPictureIsKnownWithoutLoadingIt() async throws {
        let path = try makePNG("big.png", width: 2000, height: 1000)
        let loader = ThumbnailLoader()
        let size = await loader.pixelSize(atPath: path)
        XCTAssertEqual(size?.width, 2000)
        XCTAssertEqual(size?.height, 1000)
        let none = await loader.pixelSize(atPath: directory.appendingPathComponent("missing.png").path)
        XCTAssertNil(none)
    }

    func testAMissingOrBrokenFileGivesNothing() async throws {
        let loader = ThumbnailLoader()
        let missing = await loader.thumbnail(atPath: directory.appendingPathComponent("missing.png").path)
        XCTAssertNil(missing)
        let broken = directory.appendingPathComponent("broken.png")
        try Data("not a picture".utf8).write(to: broken)
        let result = await loader.thumbnail(atPath: broken.path)
        XCTAssertNil(result)
        let empty = await loader.thumbnail(atPath: "")
        XCTAssertNil(empty)
    }

    func testAPictureIsKeptSoItIsNotReadAgain() async throws {
        let path = try makePNG("a.png", width: 800, height: 800)
        let loader = ThumbnailLoader()
        let first = await loader.thumbnail(atPath: path)
        try FileManager.default.removeItem(atPath: path) // were it read again, it would be gone
        let second = await loader.thumbnail(atPath: path)
        XCTAssertNotNil(second)
        XCTAssertTrue(first?.image === second?.image, "the very same image")
        let count = await loader.cachedCount
        XCTAssertEqual(count, 1)
    }

    func testTheKeptPicturesAreBoundedAndTheLeastRecentGoFirst() async throws {
        let loader = ThumbnailLoader(maxCount: 2)
        let a = try makePNG("a.png", width: 50, height: 50)
        let b = try makePNG("b.png", width: 50, height: 50)
        let c = try makePNG("c.png", width: 50, height: 50)
        _ = await loader.thumbnail(atPath: a)
        _ = await loader.thumbnail(atPath: b)
        _ = await loader.thumbnail(atPath: a) // a is the most recent now
        _ = await loader.thumbnail(atPath: c) // b goes
        let count = await loader.cachedCount
        XCTAssertEqual(count, 2)
        let kept = await loader.cachedPaths
        XCTAssertEqual(Set(kept), [a, c])
    }

    func testTheKeptPicturesAreBoundedByMemoryToo() async throws {
        // Each 100 x 100 picture is 40,000 bytes of pixels.
        let loader = ThumbnailLoader(maxCount: 100, maxBytes: 100_000)
        for name in ["a", "b", "c", "d"] {
            _ = await loader.thumbnail(atPath: try makePNG("\(name).png", width: 100, height: 100))
        }
        let count = await loader.cachedCount
        XCTAssertEqual(count, 2, "two fit in 100,000 bytes")
    }

    func testCachedThumbnailMirrorReflectsStoreEvictionAndLargeEXIFOrientation() async throws {
        let loader = ThumbnailLoader(maxCount: 2)
        let a = try makePNG("mirror-a.png", width: 80, height: 60)
        let b = try makePNG("mirror-b.png", width: 80, height: 60)
        let c = try makePNG("mirror-c.png", width: 80, height: 60)

        XCTAssertNil(loader.cachedThumbnail(atPath: a), "mirror never loads synchronously before thumbnail(atPath:)")
        let loadedA = await loader.thumbnail(atPath: a)
        XCTAssertNotNil(loadedA)
        XCTAssertTrue(loader.cachedThumbnail(atPath: a)?.image === loadedA?.image)

        _ = await loader.thumbnail(atPath: b)
        _ = await loader.thumbnail(atPath: c) // evicts oldest (a)
        XCTAssertNil(loader.cachedThumbnail(atPath: a), "evicted entry leaves the synchronous mirror too")
        XCTAssertNotNil(loader.cachedThumbnail(atPath: b))
        XCTAssertNotNil(loader.cachedThumbnail(atPath: c))

        // Large (> 640 px) portrait JPEG stored landscape with EXIF orientation 6 decodes upright.
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        let cg = try XCTUnwrap(context.makeImage())
        let exifURL = directory.appendingPathComponent("exif6-large.jpg")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(exifURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let rotated = await loader.thumbnail(atPath: exifURL.path)
        let rotatedImage = try XCTUnwrap(rotated?.image)
        XCTAssertEqual(rotatedImage.height, 640)
        XCTAssertLessThan(rotatedImage.width, rotatedImage.height, "EXIF orientation 6 rotates >640px thumbnail upright")
    }

    func testSmallEXIFOrientation6JPEGDrawsUpright() async throws {
        let loader = ThumbnailLoader()
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        let cg = try XCTUnwrap(context.makeImage())
        let exifURL = directory.appendingPathComponent("exif6-small.jpg")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(exifURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let rotated = await loader.thumbnail(atPath: exifURL.path)
        let rotatedImage = try XCTUnwrap(rotated?.image)
        XCTAssertEqual(rotatedImage.width, 300)
        XCTAssertEqual(rotatedImage.height, 400)
        XCTAssertLessThan(rotatedImage.width, rotatedImage.height, "EXIF orientation 6 rotates <=640px thumbnail upright")
    }
}
