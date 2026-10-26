// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreServices
import Darwin
import Foundation
import XCTest

@testable import CourierCore

@MainActor
final class AttachmentDownloaderTests: XCTestCase {
    private var tempRoot: URL!
    private var downloadsDir: URL!
    private var mediaStoreDir: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("courier-downloader-\(UUID().uuidString)", isDirectory: true)
        downloadsDir = tempRoot.appendingPathComponent("Downloads", isDirectory: true)
        mediaStoreDir = tempRoot.appendingPathComponent("media/ab", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mediaStoreDir, withIntermediateDirectories: true)

        suiteName = "courier.downloader.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDownWithError() throws {
        if let suiteName {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    private func makeMediaFile(named hashName: String, content: String) throws -> URL {
        let url = mediaStoreDir.appendingPathComponent(hashName)
        try Data(content.utf8).write(to: url, options: .atomic)
        return url
    }

    func testDownloadsToConfiguredFolderWithQuarantineAndDeduplicatesName() throws {
        let preferences = ComposerPreferences(defaults: defaults)
        preferences.downloadsDirectoryPath = downloadsDir.path
        preferences.alwaysAskWhereToSaveFiles = false

        var promptCount = 0
        let downloader = AttachmentDownloader(preferences: preferences) { _, _ in
            promptCount += 1
            return nil
        }

        let source1 = try makeMediaFile(named: String(repeating: "a1", count: 32), content: "PDF-version-1")
        let source2 = try makeMediaFile(named: String(repeating: "b2", count: 32), content: "PDF-version-2")
        let source3 = try makeMediaFile(named: String(repeating: "c3", count: 32), content: "PDF-version-3")

        let saved1 = try XCTUnwrap(downloader.download(sourcePath: source1.path, suggestedName: "spec.pdf"))
        let saved2 = try XCTUnwrap(downloader.download(sourcePath: source2.path, suggestedName: "spec.pdf"))
        let saved3 = try XCTUnwrap(downloader.download(sourcePath: source3.path, suggestedName: "spec.pdf"))

        XCTAssertEqual(promptCount, 0, "save panel must not run when alwaysAskWhereToSaveFiles is false")
        XCTAssertEqual(saved1.standardizedFileURL, downloadsDir.appendingPathComponent("spec.pdf").standardizedFileURL)
        XCTAssertEqual(saved2.standardizedFileURL, downloadsDir.appendingPathComponent("spec (1).pdf").standardizedFileURL)
        XCTAssertEqual(saved3.standardizedFileURL, downloadsDir.appendingPathComponent("spec (2).pdf").standardizedFileURL)

        // Never overwrite earlier files on name collision.
        XCTAssertEqual(try String(contentsOf: saved1, encoding: .utf8), "PDF-version-1")
        XCTAssertEqual(try String(contentsOf: saved2, encoding: .utf8), "PDF-version-2")
        XCTAssertEqual(try String(contentsOf: saved3, encoding: .utf8), "PDF-version-3")

        // Verify quarantine metadata has kLSQuarantineTypeOtherDownload.
        for saved in [saved1, saved2, saved3] {
            let resourceValues = try saved.resourceValues(forKeys: [.quarantinePropertiesKey])
            XCTAssertNotNil(resourceValues.quarantineProperties)
            XCTAssertGreaterThan(getxattr(saved.path, "com.apple.quarantine", nil, 0, 0, 0), 0)
        }

        // Never download from a remote URL; only local media store files are copied.
        XCTAssertThrowsError(try downloader.download(sourcePath: "https://example.com/spec.pdf", suggestedName: "spec.pdf"))
        XCTAssertThrowsError(try downloader.download(sourcePath: "mxc://courier.local/abcd", suggestedName: "spec.pdf"))
    }

    func testAlwaysAskPromptsSavePanelAndHonorsCancel() throws {
        let preferences = ComposerPreferences(defaults: defaults)
        preferences.downloadsDirectoryPath = downloadsDir.path
        preferences.alwaysAskWhereToSaveFiles = true

        let source = try makeMediaFile(named: String(repeating: "d4", count: 32), content: "custom-save-payload")
        let customDir = tempRoot.appendingPathComponent("CustomChosen", isDirectory: true)
        try FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)

        var prompts: [(String, URL)] = []
        var nextPanelResponse: URL? = nil
        let downloader = AttachmentDownloader(preferences: preferences) { suggestedName, defaultDir in
            prompts.append((suggestedName, defaultDir))
            return nextPanelResponse
        }

        // 1. User cancels the save panel -> returns nil and writes nothing.
        let cancelled = try downloader.download(sourcePath: source.path, suggestedName: "spec.pdf")
        XCTAssertNil(cancelled)
        XCTAssertEqual(prompts.count, 1)
        XCTAssertEqual(prompts.first?.0, "spec.pdf")
        XCTAssertEqual(prompts.first?.1.standardizedFileURL, downloadsDir.standardizedFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloadsDir.appendingPathComponent("spec.pdf").path))

        // 2. User chooses a custom path in the save panel -> writes quarantined copy there.
        let chosenURL = customDir.appendingPathComponent("renamed-report.pdf")
        nextPanelResponse = chosenURL
        let saved = try XCTUnwrap(downloader.download(sourcePath: source.path, suggestedName: "spec.pdf"))
        XCTAssertEqual(saved.standardizedFileURL, chosenURL.standardizedFileURL)
        XCTAssertEqual(try String(contentsOf: saved, encoding: .utf8), "custom-save-payload")

        let resourceValues = try saved.resourceValues(forKeys: [.quarantinePropertiesKey])
        XCTAssertNotNil(resourceValues.quarantineProperties)
        XCTAssertGreaterThan(getxattr(saved.path, "com.apple.quarantine", nil, 0, 0, 0), 0)
    }
}
