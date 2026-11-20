// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest

@testable import VitruvianCourierCore

private final class LockedStrings: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.withLock { values.append(value) }
    }

    func contains(_ value: String) -> Bool {
        lock.withLock { values.contains(value) }
    }
}

@MainActor
final class LocalFileFactsQATests: XCTestCase {
    private var tempDirs: [URL] = []

    override func tearDown() async throws {
        LocalFileFacts.setWarmer { _ in }
        for dir in tempDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDirs = []
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("courier-localfilefacts-qa-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempDirs.append(url)
        return url
    }

    private func pump(for interval: TimeInterval, until condition: (() -> Bool)? = nil) {
        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            if condition?() == true { break }
        }
    }

    func testNegativeCacheHoldsMissingResultForHalfSecondThenReprobesAndNotifiesWhenFileAppears() throws {
        let dir = try makeTempDir()
        let fileURL = dir.appendingPathComponent("late-download.bin")
        let path = fileURL.path

        let warmedPaths = LockedStrings()
        LocalFileFacts.setWarmer { p in
            warmedPaths.append(p)
        }

        var notifications = 0
        let observer = NotificationCenter.default.addObserver(
            forName: ImagePixelSizeReader.didLearnSizeNotification,
            object: nil,
            queue: .main
        ) { note in
            if (note.userInfo?[ImagePixelSizeReader.pathUserInfoKey] as? String) == path {
                MainActor.assumeIsolated { notifications += 1 }
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        // 1. cachedExists never starts a background probe.
        XCTAssertNil(LocalFileFacts.cachedExists(path))
        pump(for: 0.08)
        XCTAssertNil(LocalFileFacts.cachedExists(path), "cachedExists must not trigger background disk lookup")

        // 2. First exists() returns nil immediately from memory and starts background lookup.
        let t0 = Date()
        XCTAssertNil(LocalFileFacts.exists(path))
        pump(for: 1.0) { LocalFileFacts.cachedExists(path) != nil }
        XCTAssertEqual(LocalFileFacts.cachedExists(path), false)
        XCTAssertEqual(LocalFileFacts.exists(path), false)
        XCTAssertEqual(notifications, 0, "learning initial missing state must not post didLearnSizeNotification")

        // 3. Create the file on disk while still well inside the 0.5 s negative cache window.
        try Data("hello".utf8).write(to: fileURL)
        let elapsedBeforeExpiry = Date().timeIntervalSince(t0)
        if elapsedBeforeExpiry < LocalFileFacts.missingLifetime - 0.15 {
            XCTAssertEqual(
                LocalFileFacts.exists(path),
                false,
                "negative cache must trust missing result during missingLifetime (0.5s)"
            )
            pump(for: 0.08)
            XCTAssertEqual(
                LocalFileFacts.cachedExists(path),
                false,
                "within 0.5s window, exists() must not re-probe disk yet"
            )
            XCTAssertEqual(notifications, 0)
        }

        // 4. Wait past the 0.5 s negative cache lifetime, then query exists() again.
        let remaining = (LocalFileFacts.missingLifetime + 0.08) - Date().timeIntervalSince(t0)
        if remaining > 0 {
            pump(for: remaining)
        }

        // Expired missing still returns false synchronously without blocking, while scheduling background re-probe.
        XCTAssertEqual(LocalFileFacts.exists(path), false)
        pump(for: 1.5) { LocalFileFacts.cachedExists(path) == true && notifications >= 1 }

        XCTAssertEqual(LocalFileFacts.cachedExists(path), true, "background re-probe after 0.5s must discover newly created file")
        XCTAssertEqual(LocalFileFacts.exists(path), true)
        XCTAssertEqual(notifications, 1, "transition from missing to present must post didLearnSizeNotification once")
        XCTAssertTrue(warmedPaths.contains(path), "warmer must run when file becomes present")
    }

    func testDirectoriesCountAsMissingAndPathsExtractDeduplicatedLocalCandidates() throws {
        let dir = try makeTempDir()
        let subDir = dir.appendingPathComponent("not-a-file", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let warmedPaths = LockedStrings()
        LocalFileFacts.setWarmer { p in
            warmedPaths.append(p)
        }

        LocalFileFacts.warm(paths: [subDir.path])
        XCTAssertEqual(LocalFileFacts.cachedExists(subDir.path), false, "directories must not be treated as existing media files")
        XCTAssertFalse(warmedPaths.contains(subDir.path))

        let e1 = Event(
            eventID: "$1", roomID: "!r", sender: "@a:local", senderName: "A",
            mine: false, type: "m.room.message", content: .object(["msgtype": .string("m.text"), "body": .string("hi")]),
            ts: 1, seq: 1, status: .sent,
            mediaPath: "/tmp/a",
            thumbnailPath: "/tmp/b",
            linkPreviews: [
                LinkPreviewItem(matchedURL: "https://example.com/1", imagePath: "/tmp/c"),
                LinkPreviewItem(matchedURL: "https://example.com/2", imagePath: "/tmp/a"),
                LinkPreviewItem(matchedURL: "https://example.com/3", imagePath: ""),
            ]
        )
        let e2 = Event(
            eventID: "$2", roomID: "!r", sender: "@a:local", senderName: "A",
            mine: false, type: "m.room.message", content: .object(["msgtype": .string("m.text"), "body": .string("yo")]),
            ts: 2, seq: 2, status: .sent,
            mediaPath: "/tmp/b",
            thumbnailPath: "/tmp/d"
        )
        XCTAssertEqual(LocalFileFacts.paths(in: [e1, e2]), ["/tmp/a", "/tmp/b", "/tmp/c", "/tmp/d"])
    }
}
