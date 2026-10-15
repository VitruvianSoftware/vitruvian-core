// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import XCTest

import HomeSpeakerCore
import HomeSpeakerToolCore

/// What the tool's settings say about the Google sign-in client comes from
/// the profile it runs as: the client shipped with that HomeSpeaker, or
/// none. Every file here is in a folder of the test's own; no test reads
/// the person's secrets.
final class AccountTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("homespeaker-account-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var toolFolder: URL { root.appendingPathComponent("tool") }

    private func profile() throws -> HomeSpeakerProfile {
        try FileManager.default.createDirectory(at: toolFolder, withIntermediateDirectories: true)
        return .extension(
            dataFolder: root.appendingPathComponent("data"), toolFolder: toolFolder,
            messagePrefix: "test.\(UUID().uuidString).homespeaker")
    }

    private func account(_ profile: HomeSpeakerProfile) -> SecretStoreAccount {
        SecretStoreAccount(
            store: SecretStore(fileURL: root.appendingPathComponent("secrets.json")),
            antigravityTokens: root.appendingPathComponent("none.json"),
            profile: profile)
    }

    private func shipClient(_ id: String) throws {
        try Data(#"{"client_id": "\#(id)", "client_secret": "s"}"#.utf8)
            .write(to: toolFolder.appendingPathComponent("google-oauth-client.json"))
    }

    func testHasBundledOAuthClientReadsTheProfile() throws {
        let profile = try profile()
        let account = account(profile)
        XCTAssertFalse(account.hasBundledOAuthClient, "nothing shipped")
        XCTAssertFalse(account.hasOAuthClient, "and no client of the person's own: Sign In stays off")

        try shipClient("shipped.apps.googleusercontent.com")
        XCTAssertTrue(account.hasBundledOAuthClient, "the profile's shipped client")
        XCTAssertTrue(account.hasOAuthClient, "which is enough to sign in")
    }

    func testAnEmptyShippedFileIsNotAClient() throws {
        let account = account(try profile())
        try Data().write(to: toolFolder.appendingPathComponent("google-oauth-client.json"))
        XCTAssertFalse(account.hasBundledOAuthClient)
        XCTAssertFalse(account.hasOAuthClient)
    }

    func testThePersonsOwnClientNeedsNoShippedOne() throws {
        let account = account(try profile())
        try account.saveOAuthClient(id: "mine", secret: "s")
        XCTAssertTrue(account.hasOAuthClient)
        XCTAssertFalse(account.hasBundledOAuthClient, "still nothing shipped")
    }
}
