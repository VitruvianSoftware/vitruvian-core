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

import CryptoKit
import Foundation
import RemoteMenuCore
import XCTest

final class PhoneAppUpdateTests: XCTestCase {
    // The shape `catalog-publish` signs (catalog/android/vitruvian-remote.json).
    func feed(_ version: String, code: Int? = nil, url: String? = nil, kind: String = "vitruvian-android-update") -> Data {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        let c = code ?? (parts.count == 3 ? parts[0] * 10000 + parts[1] * 100 + parts[2] : 0)
        let u = url ?? "https://github.com/VitruvianSoftware/vitruvian-core/releases/download/vitruvian-remote-v\(version)/VitruvianRemote-\(version).apk"
        return Data("""
        {"kind":"\(kind)","schema":1,"packageName":"dev.vitruvian.remote","version":"\(version)","versionCode":\(c),"minSdk":26,"published":"2026-11-18","apk":{"url":"\(u)","size":9682039,"sha256":"6e751e3699e145c06c97936167ef687cd4dcb28eaa291fb9bf2c9190c25ba7fd"},"notes":[]}
        """.utf8)
    }

    let key = Curve25519.Signing.PrivateKey()
    var publicKey: String { key.publicKey.rawRepresentation.base64EncodedString() }
    func sign(_ d: Data) throws -> String { try key.signature(for: d).base64EncodedString() }

    // MARK: Version comparison

    func testVersionCodeMatchesThePhonesFormula() {
        XCTAssertEqual(PhoneAppVersion.code("0.1.47"), 147)
        XCTAssertEqual(PhoneAppVersion.code("1.2.3"), 10203)
        XCTAssertEqual(PhoneAppVersion.code("12.0.9"), 120009)
        XCTAssertNil(PhoneAppVersion.code("0.1"))
        XCTAssertNil(PhoneAppVersion.code("0.1.47-dev"))
        XCTAssertNil(PhoneAppVersion.code("dev"))
        XCTAssertNil(PhoneAppVersion.code("0.100.1"))
        XCTAssertNil(PhoneAppVersion.code("0.1.x"))
    }

    func testBehindComparesNumbersNotText() {
        XCTAssertTrue(PhoneAppVersion.isBehind(phone: "0.1.47", latest: "0.1.48"))
        XCTAssertTrue(PhoneAppVersion.isBehind(phone: "0.1.9", latest: "0.1.10"))
        XCTAssertTrue(PhoneAppVersion.isBehind(phone: "0.9.9", latest: "1.0.0"))
        XCTAssertFalse(PhoneAppVersion.isBehind(phone: "0.1.48", latest: "0.1.48"))
        XCTAssertFalse(PhoneAppVersion.isBehind(phone: "0.1.49", latest: "0.1.48"))
        XCTAssertFalse(PhoneAppVersion.isBehind(phone: "0.1.10", latest: "0.1.9"))
        XCTAssertFalse(PhoneAppVersion.isBehind(phone: "dev", latest: "0.1.48"))
    }

    // MARK: Signature and feed checks

    func testAcceptsAFeedSignedWithTheKey() throws {
        let d = feed("0.1.48")
        XCTAssertEqual(PhoneAppFeed.verifiedVersion(feed: d, signature: try sign(d), publicKey: publicKey), "0.1.48")
    }

    func testRefusesAFeedChangedAfterSigning() throws {
        let signed = feed("0.1.48")
        let sig = try sign(signed)
        XCTAssertNil(PhoneAppFeed.verifiedVersion(feed: feed("0.1.49"), signature: sig, publicKey: publicKey))
    }

    func testRefusesAFeedSignedWithAnotherKey() throws {
        let d = feed("0.1.48")
        let other = try Curve25519.Signing.PrivateKey().signature(for: d).base64EncodedString()
        XCTAssertNil(PhoneAppFeed.verifiedVersion(feed: d, signature: other, publicKey: publicKey))
    }

    func testRefusesGarbageSignatures() {
        let d = feed("0.1.48")
        XCTAssertNil(PhoneAppFeed.verifiedVersion(feed: d, signature: "", publicKey: publicKey))
        XCTAssertNil(PhoneAppFeed.verifiedVersion(feed: d, signature: "not base64!", publicKey: publicKey))
        XCTAssertNil(PhoneAppFeed.verifiedVersion(feed: d, signature: Data(count: 64).base64EncodedString(), publicKey: publicKey))
    }

    func testTheRealKeyRefusesATestSignature() throws {
        // Default key = catalog/public-key.txt; our throwaway key must not pass for it.
        let d = feed("0.1.48")
        XCTAssertNil(PhoneAppFeed.verifiedVersion(feed: d, signature: try sign(d)))
    }

    func testRefusesSignedFeedsItDoesNotUnderstand() throws {
        for d in [
            feed("0.1.48", kind: "vitruvian-tool-catalog"),
            feed("0.1.48", code: 999),
            feed("0.1.48", url: "https://example.com/VitruvianRemote-0.1.48.apk"),
            feed("0.1.48-rc1", code: 148),
        ] {
            XCTAssertNil(PhoneAppFeed.verifiedVersion(feed: d, signature: try sign(d), publicKey: publicKey))
        }
    }

    func testPublicKeyMatchesTheCatalogKeyFile() throws {
        // Under Bazel the file is a data dependency in runfiles; `swift test` falls back to the tree.
        var candidates: [URL] = []
        let env = ProcessInfo.processInfo.environment
        if let root = env["TEST_SRCDIR"], let ws = env["TEST_WORKSPACE"] {
            candidates.append(URL(fileURLWithPath: root).appendingPathComponent(ws).appendingPathComponent("catalog/public-key.txt"))
        }
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            candidates.append(dir.appendingPathComponent("catalog/public-key.txt"))
            dir.deleteLastPathComponent()
        }
        guard let text = candidates.lazy.compactMap({ try? String(contentsOf: $0, encoding: .utf8) }).first else {
            return XCTFail("catalog/public-key.txt not found")
        }
        XCTAssertEqual(text.trimmingCharacters(in: .whitespacesAndNewlines), PhoneAppFeed.publicKey)
    }

    // MARK: The menu line

    let running = AgentState.running(version: "1.9.0")
    func phone(_ app: String?) -> PhoneLink {
        PhoneLink(connected: true, device: .init(model: "Pixel Fold", android: "16", appVersion: app))
    }

    func testSaysWhenThePhoneIsBehind() {
        let s = StatusSnapshot(state: running, phone: phone("0.1.47"), latestPhoneApp: "0.1.48")
        XCTAssertEqual(s.phoneUpdateLine,
                       "Phone app 0.1.47 · update 0.1.48 available — open Settings → About on the phone")
    }

    func testSaysNothingWhenCurrentUnknownOrUnverified() {
        XCTAssertNil(StatusSnapshot(state: running, phone: phone("0.1.48"), latestPhoneApp: "0.1.48").phoneUpdateLine)
        XCTAssertNil(StatusSnapshot(state: running, phone: phone(nil), latestPhoneApp: "0.1.48").phoneUpdateLine)
        XCTAssertNil(StatusSnapshot(state: running, phone: phone("0.1.47"), latestPhoneApp: nil).phoneUpdateLine)
        var gone = phone("0.1.47")
        gone.connected = false
        XCTAssertNil(StatusSnapshot(state: running, phone: gone, latestPhoneApp: "0.1.48").phoneUpdateLine)
    }

    func testDecodesTheAppVersionFromTheAgent() throws {
        let json = #"{"connected":true,"device":{"model":"Pixel Fold","android":"16","app_version":"0.1.47"},"since":null,"tools":[],"trust_until":null}"#
        let p = try JSONDecoder().decode(PhoneLink.self, from: Data(json.utf8))
        XCTAssertEqual(p.device?.appVersion, "0.1.47")
    }

    // MARK: The cache

    func testCacheKeepsAVerifiedFeed() async throws {
        let d = feed("0.1.48")
        let sig = try sign(d)
        let cache = PhoneAppFeedCache(publicKey: publicKey, fetch: { (d, sig) })
        await cache.refresh()
        let latest = await cache.latest()
        XCTAssertEqual(latest, "0.1.48")
    }

    func testCacheDropsAFeedThatStopsVerifying() async throws {
        let good = feed("0.1.48")
        let sig = try sign(good)
        let served = Served((good, sig))
        let cache = PhoneAppFeedCache(publicKey: publicKey, fetch: { served.value })
        await cache.refresh()
        served.value = (feed("0.1.99"), sig)
        await cache.refresh()
        let latest = await cache.latest()
        XCTAssertNil(latest)
    }

    func testCacheToleratesAMissingFeed() async {
        let cache = PhoneAppFeedCache(fetch: { nil })
        await cache.refresh()
        let latest = await cache.latest()
        XCTAssertNil(latest)
    }
}

private final class Served: @unchecked Sendable {
    var value: (Data, String)?
    init(_ v: (Data, String)?) { value = v }
}
