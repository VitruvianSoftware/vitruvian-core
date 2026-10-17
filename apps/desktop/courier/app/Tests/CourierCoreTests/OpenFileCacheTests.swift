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
        XCTAssertEqual(name.utf8.count, OpenFileCache.longestNameBytes)
        XCTAssertTrue(name.hasSuffix(".pdf"))
        let noExtension = OpenFileCache.fileName(for: String(repeating: "b", count: 300), mimeType: "")
        XCTAssertEqual(noExtension.utf8.count, OpenFileCache.longestNameBytes)
    }

    func testTheCapIsInBytesAndNeverCutsThroughACharacter() {
        // 100 characters of CJK are 300 bytes; an emoji is 4.
        let cjk = OpenFileCache.fileName(for: String(repeating: "漢", count: 100) + ".pdf", mimeType: "")
        XCTAssertLessThanOrEqual(cjk.utf8.count, OpenFileCache.longestNameBytes)
        XCTAssertTrue(cjk.hasSuffix(".pdf"))
        XCTAssertNotNil(String(data: Data(cjk.utf8), encoding: .utf8))
        XCTAssertEqual(cjk.utf8.count, 4 + 65 * 3, "as many whole characters as fit")

        let emoji = OpenFileCache.fileName(for: String(repeating: "😀", count: 80) + ".png", mimeType: "")
        XCTAssertLessThanOrEqual(emoji.utf8.count, OpenFileCache.longestNameBytes)
        XCTAssertTrue(emoji.hasSuffix(".png"))
        XCTAssertFalse(emoji.unicodeScalars.contains("\u{FFFD}"))
        XCTAssertEqual(emoji.dropLast(4).unicodeScalars.count, (OpenFileCache.longestNameBytes - 4) / 4)

        // Short enough in bytes: untouched.
        XCTAssertEqual(OpenFileCache.fileName(for: String(repeating: "漢", count: 60) + ".pdf", mimeType: ""),
                       String(repeating: "漢", count: 60) + ".pdf")
    }

    func testInvisibleCharactersCannotDisguiseTheType() {
        // U+202E reverses what follows: "evil" + RLO + "fdp.command" would show as "evilcommand.pdf" in a title bar.
        XCTAssertEqual(OpenFileCache.fileName(for: "evil\u{202E}fdp.command", mimeType: ""), "evilfdp.command")
        XCTAssertEqual(OpenFileCache.fileName(for: "a\u{200D}b\u{200B}c\u{200E}d\u{200F}e.txt", mimeType: ""), "abcde.txt")
        XCTAssertEqual(OpenFileCache.fileName(for: "\u{202A}x\u{202B}y\u{202C}z\u{202D}.txt", mimeType: ""), "xyz.txt")
        XCTAssertEqual(OpenFileCache.fileName(for: "p\u{2066}q\u{2067}r\u{2068}s\u{2069}.txt", mimeType: ""), "pqrs.txt")
        XCTAssertEqual(OpenFileCache.fileName(for: "line\u{2028}one\u{2029}two.txt", mimeType: ""), "lineonetwo.txt")
        XCTAssertEqual(OpenFileCache.fileName(for: "\u{202E}\u{200D}", mimeType: ""), "file", "nothing left: the fallback")
        // The extension that remains is the real one.
        let shown = OpenFileCache.fileName(for: "photo\u{202E}gpj.app", mimeType: "")
        XCTAssertEqual((shown as NSString).pathExtension, "app")
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

    func testAFileInPlaceIsAlwaysQuarantinedEvenWhileOtherOpensAreCopying() throws {
        let cache = OpenFileCache(root: directory.appendingPathComponent("cache"))
        let source = try makeSource(String(repeating: "x", count: 4_000_000))
        let final = cache.root
        let stop = ManagedAtomicFlag()
        var unmarked = 0
        let watcher = Thread {
            while !stop.isSet {
                // Whenever the file is there, it has the mark: no gap between the copy and the quarantine.
                let found = (try? FileManager.default.subpathsOfDirectory(atPath: final.path)) ?? []
                for path in found where path.hasSuffix("/run.command") {
                    let full = final.appendingPathComponent(path).path
                    if getxattr(full, "com.apple.quarantine", nil, 0, 0, 0) < 0, errno == ENOATTR { unmarked += 1 }
                }
            }
        }
        watcher.start()
        var results = [URL?](repeating: nil, count: 16)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: 16) { index in
            let copy = try? cache.prepare(source: source, fileName: "run.command", mimeType: "")
            lock.withLock { results[index] = copy }
        }
        stop.set()
        while !watcher.isFinished { usleep(1000) }

        XCTAssertEqual(unmarked, 0, "a copy without the mark was in place")
        let copies = results.compactMap { $0 }
        XCTAssertEqual(copies.count, 16, "every open got a file")
        XCTAssertEqual(Set(copies).count, 1, "and the same one")
        XCTAssertGreaterThan(getxattr(copies[0].path, "com.apple.quarantine", nil, 0, 0, 0), 0)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: copies[0].deletingLastPathComponent().path)
        XCTAssertEqual(leftovers, ["run.command"], "no partial copy is left behind")
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

/// A flag one thread sets and another reads.
private final class ManagedAtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
