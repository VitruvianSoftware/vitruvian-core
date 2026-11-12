// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CryptoKit
import Foundation
import VitruvianCore
import VitruvianServices

/// The list of tools: its signature, reading it, where it comes from, and
/// how it is asked for. No test here touches the network.
enum CatalogueListTests {
    static func run(_ suite: TestSuite) {
        signing(suite)
        theAppsKey(suite)
        reading(suite)
        installable(suite)
        sources(suite)
        requests(suite)
    }

    /// RFC 8032, section 7.1, TEST 1 and TEST 2: public keys, messages and
    /// signatures, in hex. Another implementation made them, so the app's
    /// check is held to Ed25519 itself, not to CryptoKit's signer.
    static let vectors: [(key: String, message: String, signature: String)] = [
        ("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "",
         "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"),
        ("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "72",
         "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"),
    ]

    static func hex(_ text: String) -> Data {
        Data(stride(from: 0, to: text.count, by: 2).map {
            UInt8(text[text.index(text.startIndex, offsetBy: $0)..<text.index(text.startIndex, offsetBy: $0 + 2)], radix: 16)!
        })
    }

    static func signing(_ suite: TestSuite) {
        let verified = vectors.map { vector in
            CatalogueSigning.verify(hex(vector.message), signatureFile: Data((hex(vector.signature).base64EncodedString() + "\n").utf8),
                                    publicKey: hex(vector.key).base64EncodedString())
        }
        suite.expect(verified == [true, true], "a list signed by Ed25519's own test vectors verifies (\(verified))")

        let list = CatalogueFixtures.list([CatalogueFixtures.entry()])
        let signature = CatalogueFixtures.signature(list)
        let key = CatalogueFixtures.publicKey
        var changed = list
        changed[changed.count / 2] ^= 0x01
        let other = Curve25519.Signing.PrivateKey()
        suite.expect(CatalogueSigning.verify(list, signatureFile: signature, publicKey: key)
                         && !CatalogueSigning.verify(changed, signatureFile: signature, publicKey: key)
                         && !CatalogueSigning.verify(list + Data(" ".utf8), signatureFile: signature, publicKey: key)
                         && !CatalogueSigning.verify(list, signatureFile: CatalogueFixtures.signature(list, by: other),
                                                     publicKey: key),
                     "a list verifies only with its own bytes and the key that signed it: one changed byte, one "
                         + "added byte or another key is refused")
        let short = Data((Data(repeating: 1, count: 63).base64EncodedString() + "\n").utf8)
        let padded = Data(("  " + String(decoding: signature, as: UTF8.self) + "\r\n").utf8)
        suite.expect(!CatalogueSigning.verify(list, signatureFile: short, publicKey: key)
                         && !CatalogueSigning.verify(list, signatureFile: Data("not base64\n".utf8), publicKey: key)
                         && !CatalogueSigning.verify(list, signatureFile: Data(repeating: 0x41, count: 4096), publicKey: key)
                         && !CatalogueSigning.verify(list, signatureFile: signature, publicKey: "short")
                         && CatalogueSigning.verify(list, signatureFile: padded, publicKey: key),
                     "a signature file that is not 64 bytes in base64, or is too long, is refused; spaces and a line "
                         + "ending around it are not")
    }

    static func theAppsKey(_ suite: TestSuite) {
        let raw = Data(base64Encoded: CatalogueSigning.publicKey)
        let published = vectors.map { hex($0.key) }
        suite.expect(raw?.count == 32 && raw.flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) } != nil
                         && !published.contains(raw ?? Data())
                         && CatalogueSource.production.publicKey == CatalogueSigning.publicKey,
                     "the app is built with a catalog key: 32 bytes, a key, not a published test key, and the one "
                         + "the website's list is checked with")
    }

    static func reading(_ suite: TestSuite) {
        let permits = CatalogueFixtures.source.permits
        let read = Catalogue.read(CatalogueFixtures.list([
            CatalogueFixtures.entry(),
            CatalogueFixtures.entry(["id": "com.acme.tool", "panels": [] as [String]]),
            CatalogueFixtures.entry(["id": "com.acme.extension", "panels": ["island", "settings"]]),
        ]), permits: permits)
        let entry = read?.tools.first
        suite.expect(read?.tools.count == 3 && entry?.id == ToolID("com.acme.deploys")
                         && entry?.name.text(for: "fr") == "Déploiements" && entry?.version == "1.2.0"
                         && entry?.download.size == 4096 && entry?.uses == ["clipboard.write", "notify", "storage"]
                         && entry?.commands.map(\.id) == ["copyLatest"]
                         && read?.tools.map(\.panels) == [nil, [], ["island", "settings"]]
                         && read?.generated == ISO8601DateFormatter().date(from: "2026-11-02T10:00:00Z"),
                     "a list is read: each entry's words, version, download, what it says it uses, and its panel placements")

        let broken: [(String, [String: Any], [String: Any])] = [
            ("an id with no dot", ["id": "deploys"], [:]),
            ("an id with a slash", ["id": "com.acme/deploys"], [:]),
            ("a version that is not semver", ["version": "1.2"], [:]),
            ("an app version that is not semver", ["minimumAppVersion": "latest"], [:]),
            ("a checksum in capitals", [:], ["sha256": String(repeating: "A", count: 64)]),
            ("a short checksum", [:], ["sha256": "abc"]),
            ("an empty download", [:], ["size": 0]),
            ("a download over 256 MB", [:], ["size": 268_435_457]),
            ("a download over http", [:], ["url": "http://catalog.test/deploys.zip"]),
            ("a source over http", ["source": "http://github.com/acme/deploys"], [:]),
            ("a name with no English", ["name": ["fr": "Déploiements"]], [:]),
            ("no commands at all", ["commands": NSNull()], [:]),
        ]
        let dropped = broken.filter { _, change, download in
            Catalogue.read(CatalogueFixtures.list([CatalogueFixtures.entry(change, download: download),
                                                   CatalogueFixtures.entry(["id": "com.acme.other"])]),
                           permits: permits)?.tools.map(\.id.rawValue) != ["com.acme.other"]
        }.map(\.0)
        suite.expect(dropped.isEmpty, "an entry that breaks a rule is left out and the others are kept (\(dropped))")
        let twice = Catalogue.read(CatalogueFixtures.list([CatalogueFixtures.entry(),
                                                          CatalogueFixtures.entry(["version": "9.0.0"])]),
                                   permits: permits)
        suite.expect(twice?.tools.map(\.version) == ["1.2.0"], "an id listed twice is read once, the first time")
        suite.expect(Catalogue.read(CatalogueFixtures.list([], version: 2), permits: permits) == nil
                         && Catalogue.read(Data("{}".utf8), permits: permits) == nil
                         && Catalogue.read(CatalogueFixtures.list([], generated: "yesterday"), permits: permits) == nil
                         && Catalogue.read(Data(repeating: 0x20, count: Catalogue.mostBytes + 1), permits: permits) == nil,
                     "a list of another version, with no date, or over a megabyte is no list")
    }

    static func installable(_ suite: TestSuite) {
        let list = CatalogueFixtures.list([
            CatalogueFixtures.entry(),
            CatalogueFixtures.entry(["id": "com.acme.next", "protocol": "3"]),
            CatalogueFixtures.entry(["id": "com.acme.newer", "minimumAppVersion": "9.0.0"]),
        ])
        let catalogue = Catalogue.read(list, permits: CatalogueFixtures.source.permits)
        suite.expect(catalogue?.installable(appVersion: "3.43.0").map(\.id.rawValue) == ["com.acme.deploys"]
                         && catalogue?.installable(appVersion: "9.0.0").map(\.id.rawValue)
                         == ["com.acme.deploys", "com.acme.newer"]
                         && catalogue?.installable(appVersion: "dev").count == 2,
                     "the app offers only a tool that speaks its protocol and asks for no newer app; a development "
                         + "build is new enough for all")
        suite.expect(Catalogue.isNewer("1.3.0", than: "1.2.0") && Catalogue.isNewer("1.2.0", than: "1.2.0-beta.1")
                         && Catalogue.isNewer("1.10.0", than: "1.9.0") && !Catalogue.isNewer("1.2.0", than: "1.2.0")
                         && !Catalogue.isNewer("1.1.9", than: "1.2.0") && !Catalogue.isNewer("2", than: "1.0.0")
                         && !Catalogue.isNewer("1.3.0", than: "dev"),
                     "one version is newer than another as semver says, and never when either is not a version")
    }

    static func sources(_ suite: TestSuite) {
        let production = CatalogueSource.production
        suite.expect(production.list.absoluteString == "https://vitruviansoftware.dev/tools/catalog/tools.json"
                         && production.signature.absoluteString == "https://vitruviansoftware.dev/tools/catalog/tools.json.sig"
                         && production.permits(URL(string: "https://github.com/a/b/releases/download/v1/b.zip")!)
                         && !production.permits(URL(string: "http://github.com/a/b.zip")!)
                         && !production.permits(URL(string: "http://127.0.0.1:8737/tools.json")!)
                         && !production.permits(URL(string: "file:///tmp/tools.json")!),
                     "the app reads the website's signed list, and fetches over https only")

        let key = CatalogueFixtures.publicKey
        let rehearsal = CatalogueSource.rehearsal(["VITRUVIAN_CATALOGUE_URL": "http://127.0.0.1:8737/tools.json",
                                                   "VITRUVIAN_CATALOGUE_KEY": key])
        suite.expect(rehearsal?.signature.absoluteString == "http://127.0.0.1:8737/tools.json.sig"
                         && rehearsal?.publicKey == key
                         && rehearsal?.permits(URL(string: "http://127.0.0.1:8737/downloads/a.zip")!) == true
                         && rehearsal?.permits(URL(string: "http://example.com/a.zip")!) == false,
                     "a rehearsal reads a list on this Mac, over plain http to 127.0.0.1 and nowhere else")
        let refused = [
            ["VITRUVIAN_CATALOGUE_URL": "http://127.0.0.1:8737/tools.json"],
            ["VITRUVIAN_CATALOGUE_KEY": key],
            ["VITRUVIAN_CATALOGUE_URL": "http://example.com/tools.json", "VITRUVIAN_CATALOGUE_KEY": key],
            ["VITRUVIAN_CATALOGUE_URL": "http://127.0.0.1:8737/tools.json", "VITRUVIAN_CATALOGUE_KEY": "short"],
        ].filter { CatalogueSource.rehearsal($0) != nil }
        suite.expect(refused.isEmpty, "a rehearsal needs both variables, an address on this Mac and a key")
    }

    static func requests(_ suite: TestSuite) {
        let url = URL(string: "https://vitruviansoftware.dev/tools/catalog/tools.json")!
        let first = URLSessionCatalogueFetcher.urlRequest(for: CatalogueRequest(url: url, limit: 10))
        let again = URLSessionCatalogueFetcher.urlRequest(for: CatalogueRequest(url: url, etag: "\"abc\"", limit: 10))
        suite.expect(first.value(forHTTPHeaderField: "If-None-Match") == nil
                         && again.value(forHTTPHeaderField: "If-None-Match") == "\"abc\""
                         && again.cachePolicy == .reloadIgnoringLocalCacheData && again.httpMethod == "GET",
                     "the list is asked for with the ETag of the copy the app has, and no cache but the app's own")
    }
}
