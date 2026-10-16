// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Darwin
import XCTest

@testable import CourierCore

/// A received file has no name or extension on disk; the copy made to open it has both, and is quarantined.
final class OpenFileCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("courier-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - The name

    func testTheFilesOwnNameIsKept() {
        XCTAssertEqual(OpenFileCache.fileName(for: "report.pdf", mimeType: "application/pdf"), "report.pdf")
        XCTAssertEqual(OpenFileCache.fileName(for: "Holiday photo.JPG", mimeType: ""), "Holiday photo.JPG")
    }

    func testAnEmptyNameFallsBackToFileWithAnExtensionFromTheMimeType() {
        XCTAssertEqual(OpenFileCache.fileName(for: "", mimeType: "image/png"), "file.png")
        XCTAssertEqual(OpenFileCache.fileName(for: "   ", mimeType: "application/pdf"), "file.pdf")
        XCTAssertEqual(OpenFileCache.fileName(for: "", mimeType: ""), "file")
        XCTAssertEqual(OpenFileCache.fileName(for: "", mimeType: "application/x-made-up-type"), "file")
    }

    func testANameWithoutAnExtensionGetsOneFromTheMimeType() {
        // A voice note's body is "Voice message"; it still has to open in an audio app.
        XCTAssertEqual(OpenFileCache.fileName(for: "Voice message", mimeType: "audio/mpeg"), "Voice message.mp3")
        XCTAssertEqual(OpenFileCache.fileName(for: "Voice message", mimeType: ""), "Voice message")
    }

    func testTheNameIsMadeSafe() {
        let traversal = OpenFileCache.fileName(for: "../../etc/passwd", mimeType: "")
        XCTAssertFalse(traversal.contains("/"))
        XCTAssertFalse(traversal.hasPrefix("."))
        XCTAssertEqual(OpenFileCache.fileName(for: ".hidden", mimeType: ""), "hidden")
        XCTAssertEqual(OpenFileCache.fileName(for: "...", mimeType: ""), "file")
        XCTAssertEqual(OpenFileCache.fileName(for: "a:b\u{0}c\nd.txt", mimeType: ""), "a_b_c_d.txt")
        XCTAssertEqual(OpenFileCache.fileName(for: "dir/name.txt", mimeType: ""), "dir_name.txt")
    }

    func testALongNameIsCutAndKeepsItsExtension() {
        let long = String(repeating: "a", count: 300) + ".pdf"
        let name = OpenFileCache.fileName(for: long, mimeType: "")
        XCTAssertEqual(name.count, OpenFileCache.longestName)
        XCTAssertTrue(name.hasSuffix(".pdf"))
        let noExtension = OpenFileCache.fileName(for: String(repeating: "b", count: 300), mimeType: "")
        XCTAssertEqual(noExtension.count, OpenFileCache.longestName)
    }

    // MARK: - The copy

    private func makeSource(_ content: String = "made up") throws -> URL {
        // As the engine keeps them: <dir>/ab/<hash>, no extension.
        let folder = directory.appendingPathComponent("media/ab", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent(String(repeating: "ab", count: 32))
        try Data(content.utf8).write(to: source)
        return source
    }

    func testTheCopyHasTheRealNameAndTheContent() throws {
        let cache = OpenFileCache(root: directory.appendingPathComponent("cache"))
        let source = try makeSource("hello")
        let copy = try cache.prepare(source: source, fileName: "notes.txt", mimeType: "text/plain")
        XCTAssertEqual(copy.lastPathComponent, "notes.txt")
        XCTAssertTrue(copy.path.hasPrefix(cache.root.path))
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "hello")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "the engine's file is left alone")
    }

    func testTheCopyIsQuarantined() throws {
        let cache = OpenFileCache(root: directory.appendingPathComponent("cache"))
        let copy = try cache.prepare(source: try makeSource(), fileName: "run.command", mimeType: "")
        let values = try copy.resourceValues(forKeys: [.quarantinePropertiesKey])
        XCTAssertNotNil(values.quarantineProperties, "Gatekeeper has to check what can run")
        // The mark itself: the extended attribute Gatekeeper reads.
        XCTAssertGreaterThan(getxattr(copy.path, "com.apple.quarantine", nil, 0, 0, 0), 0)

        let source = try makeSource()
        let original = try source.resourceValues(forKeys: [.quarantinePropertiesKey])
        XCTAssertNil(original.quarantineProperties, "only the copy is marked")
        XCTAssertLessThan(getxattr(source.path, "com.apple.quarantine", nil, 0, 0, 0), 0)
    }

    func testTheSameFileGivesTheSameCopyAndDifferentFilesDoNot() throws {
        let cache = OpenFileCache(root: directory.appendingPathComponent("cache"))
        let source = try makeSource()
        let first = try cache.prepare(source: source, fileName: "a.txt", mimeType: "")
        let again = try cache.prepare(source: source, fileName: "a.txt", mimeType: "")
        XCTAssertEqual(first, again)

        let other = directory.appendingPathComponent("media/cd/other")
        try FileManager.default.createDirectory(at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("other".utf8).write(to: other)
        let second = try cache.prepare(source: other, fileName: "a.txt", mimeType: "")
        XCTAssertNotEqual(first, second, "two files with one name do not collide")
    }

    func testAMissingSourceThrowsAndLeavesNothing() throws {
        let cache = OpenFileCache(root: directory.appendingPathComponent("cache"))
        let missing = directory.appendingPathComponent("media/none")
        XCTAssertThrowsError(try cache.prepare(source: missing, fileName: "a.txt", mimeType: ""))
    }

    func testClearRemovesEveryCopy() throws {
        let cache = OpenFileCache(root: directory.appendingPathComponent("cache"))
        let copy = try cache.prepare(source: try makeSource(), fileName: "a.txt", mimeType: "")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
        cache.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.root.path))
        cache.clear() // nothing there: no trouble
    }
}
