// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import XCTest

@testable import GitHubToolCore

final class WatchlistTests: XCTestCase {
    func testCommasSpacesAndLinesSeparate() {
        XCTAssertEqual(Watchlist.parse("acme/web, acme/api\nacme/worker acme/web;x/y").map(\.fullName),
                       ["acme/web", "acme/api", "acme/worker", "x/y"])
    }

    func testTheAppsJSONArrayIsReadToo() {
        XCTAssertEqual(Watchlist.parse(#"["VitruvianSoftware/vitruvian-core", "acme/web"]"#).map(\.fullName),
                       ["VitruvianSoftware/vitruvian-core", "acme/web"])
    }

    func testEmptyAndMalformedGiveNothing() {
        XCTAssertEqual(Watchlist.parse(""), [])
        XCTAssertEqual(Watchlist.parse("  ,  "), [])
        XCTAssertEqual(Watchlist.parse("nota repo, /x, y/").map(\.fullName), [])
    }

    func testTextIsCommaSeparated() {
        XCTAssertEqual(Watchlist.text([RepoKey(owner: "a", name: "b"), RepoKey(owner: "c", name: "d")]), "a/b, c/d")
        XCTAssertEqual(Watchlist.parse(Watchlist.defaultText), [Watchlist.defaultRepository])
    }
}

final class SecretStoreTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("github-tool-secrets-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func testATokenIsKeptForTheOwnerAloneAndCleared() throws {
        let store = SecretStore(folder: folder.appendingPathComponent("data", isDirectory: true))
        XCTAssertNil(store.token())
        try store.save(token: "gho_secret")
        XCTAssertEqual(store.token(), "gho_secret")
        let file = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        XCTAssertEqual((file[.posixPermissions] as? Int).map { $0 & 0o777 }, 0o600)
        let parent = try FileManager.default.attributesOfItem(atPath: store.fileURL.deletingLastPathComponent().path)
        XCTAssertEqual((parent[.posixPermissions] as? Int).map { $0 & 0o777 }, 0o700)
        store.clear()
        XCTAssertNil(store.token())
        store.clear()
    }

    func testAnEmptyOrUnreadableFileIsNoToken() throws {
        let store = SecretStore(folder: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"token": ""}"#.utf8).write(to: store.fileURL)
        XCTAssertNil(store.token())
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertNil(store.token())
    }

    func testTheTokenNeverShowsInADescription() {
        XCTAssertEqual("\(AccessToken("gho_x"))", "AccessToken(redacted)")
        XCTAssertFalse(String(reflecting: AccessToken("gho_x")).contains("gho_x"))
    }
}
