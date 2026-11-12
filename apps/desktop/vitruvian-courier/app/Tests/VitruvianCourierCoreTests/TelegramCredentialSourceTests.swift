// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// Where Telegram's app ID comes from: the one built into the app, then the one in the Keychain, then none. Every
/// value here is made up.
final class TelegramCredentialSourceTests: XCTestCase {
    private let builtIn = TelegramCredentials(apiID: "1111111", apiHash: String(repeating: "0a", count: 16))
    private let saved = TelegramCredentials(apiID: "2222222", apiHash: String(repeating: "b1", count: 16))

    private func keychain(_ credentials: TelegramCredentials?) throws -> InMemoryCredentialStore {
        let store = InMemoryCredentialStore()
        try credentials?.save(to: store)
        return store
    }

    // MARK: - The order

    func testBuiltInWinsOverTheKeychain() throws {
        let source = TelegramCredentialSource(store: try keychain(saved), builtIn: { [builtIn] in builtIn })
        XCTAssertEqual(source.resolve(), builtIn)
        XCTAssertTrue(source.hasCredentials)
    }

    func testKeychainIsUsedWhenThereIsNoBuiltIn() throws {
        let source = TelegramCredentialSource(store: try keychain(saved), builtIn: { nil })
        XCTAssertEqual(source.resolve(), saved)
    }

    func testNothingAnywhereIsNone() throws {
        let source = TelegramCredentialSource(store: try keychain(nil), builtIn: { nil })
        XCTAssertNil(source.resolve())
        XCTAssertFalse(source.hasCredentials)
    }

    func testAnInvalidBuiltInIsIgnored() throws {
        let bad = TelegramCredentials(apiID: "0", apiHash: "not hex")
        let withKeychain = TelegramCredentialSource(store: try keychain(saved), builtIn: { bad })
        XCTAssertEqual(withKeychain.resolve(), saved, "the next source is used")
        let without = TelegramCredentialSource(store: try keychain(nil), builtIn: { bad })
        XCTAssertNil(without.resolve(), "an invalid pair is no pair")
    }

    func testAnInvalidKeychainPairIsIgnored() throws {
        let bad = TelegramCredentials(apiID: "12", apiHash: "short")
        XCTAssertNil(TelegramCredentialSource(store: try keychain(bad), builtIn: { nil }).resolve())
    }

    func testHalfAKeychainPairIsNone() {
        let half = InMemoryCredentialStore([TelegramCredentials.apiIDAccount: "1234567"])
        XCTAssertNil(TelegramCredentialSource(store: half, builtIn: { nil }).resolve())
    }

    func testAPairSavedNowIsFoundNow() throws {
        let store = try keychain(nil)
        let source = TelegramCredentialSource(store: store, builtIn: { nil })
        XCTAssertNil(source.resolve())
        try saved.save(to: store)
        XCTAssertEqual(source.resolve(), saved)
    }

    func testSpacesAroundAPackagedValueDoNotCount() {
        let source = TelegramCredentialSource(
            store: InMemoryCredentialStore(),
            builtIn: { TelegramCredentials(apiID: " 1111111 ", apiHash: " \(String(repeating: "0a", count: 16)) ") })
        XCTAssertEqual(source.resolve(), builtIn)
    }

    // MARK: - The packaged file

    private func plist(_ dictionary: [String: Any]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TelegramApp-\(UUID().uuidString).plist")
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testReadsTheFileTheInjectorWrites() throws {
        let url = try plist(["api_id": 1_111_111, "api_hash": builtIn.apiHash])
        XCTAssertEqual(TelegramBuiltIn.load(plistAt: url), builtIn)
    }

    func testAFileThatDoesNotFitIsNone() throws {
        let hash = builtIn.apiHash
        XCTAssertNil(TelegramBuiltIn.load(plistAt: try plist(["api_id": "1111111", "api_hash": hash])),
                     "the id is an integer, not a string")
        XCTAssertNil(TelegramBuiltIn.load(plistAt: try plist(["api_id": 1.5, "api_hash": hash])))
        XCTAssertNil(TelegramBuiltIn.load(plistAt: try plist(["api_id": true, "api_hash": hash])))
        XCTAssertNil(TelegramBuiltIn.load(plistAt: try plist(["api_id": 0, "api_hash": hash])))
        XCTAssertNil(TelegramBuiltIn.load(plistAt: try plist(["api_id": 2_147_483_648, "api_hash": hash])))
        XCTAssertNil(TelegramBuiltIn.load(plistAt: try plist(["api_id": 1_111_111])), "no hash")
        XCTAssertNil(TelegramBuiltIn.load(plistAt: try plist(["api_hash": hash])), "no id")
        XCTAssertNil(TelegramBuiltIn.load(plistAt: try plist(["api_id": 1_111_111, "api_hash": "xyz"])))
        XCTAssertNil(TelegramBuiltIn.load(plistAt: FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-\(UUID().uuidString).plist")))
        let garbage = FileManager.default.temporaryDirectory.appendingPathComponent("garbage-\(UUID().uuidString).plist")
        try Data("not a plist".utf8).write(to: garbage)
        addTeardownBlock { try? FileManager.default.removeItem(at: garbage) }
        XCTAssertNil(TelegramBuiltIn.load(plistAt: garbage))
    }

    func testABundleWithoutTheFileHasNone() {
        // The test runner's own bundle carries no app ID.
        XCTAssertNil(TelegramBuiltIn.load(from: .main))
    }

    func testTheValuesAreNeverInADescription() {
        XCTAssertFalse(String(describing: builtIn).contains(builtIn.apiHash))
        XCTAssertFalse(String(reflecting: builtIn).contains(builtIn.apiID))
    }
}
