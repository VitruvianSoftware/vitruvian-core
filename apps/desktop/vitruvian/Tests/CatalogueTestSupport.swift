// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CryptoKit
import Foundation
import VitruvianCore
import VitruvianServices

/// The network, for the catalog's tests, with none: each address answers
/// from a table, in pieces, at once, on the thread that asked. An address
/// with no answer fails.
final class FakeCatalogueFetcher: CatalogueFetching, @unchecked Sendable {
    enum Answer {
        case body(Data, etag: String?)
        case notModified
        case failed
    }

    var answers: [URL: Answer] = [:]
    /// Every request made, in order.
    private(set) var asked: [CatalogueRequest] = []
    /// How many bytes each piece of a body holds.
    var piece = 1024

    func fetch(_ request: CatalogueRequest, permits: @escaping @Sendable (URL) -> Bool,
               body: @escaping @Sendable (Data) -> Bool, done: @escaping @Sendable (CatalogueResponse) -> Void) {
        asked.append(request)
        guard permits(request.url), let answer = answers[request.url] else { return done(.failed) }
        switch answer {
        case .notModified: done(.notModified)
        case .failed: done(.failed)
        case .body(let data, let etag):
            if let asked = request.etag, asked == etag { return done(.notModified) }
            var at = 0
            while at < data.count {
                let chunk = data.subdata(in: at..<min(at + piece, data.count))
                at += chunk.count
                guard at <= request.limit, body(chunk) else { return done(.stopped) }
            }
            done(.complete(etag: etag))
        }
    }
}

/// Lists of tools for the tests, signed with a key made for the run.
enum CatalogueFixtures {
    static let key = Curve25519.Signing.PrivateKey()
    static var publicKey: String { key.publicKey.rawRepresentation.base64EncodedString() }

    static let source = CatalogueSource(list: URL(string: "https://catalog.test/tools.json")!,
                                        signature: URL(string: "https://catalog.test/tools.json.sig")!,
                                        publicKey: publicKey)

    /// A signature file for `data`, as the catalog's workflow writes one.
    static func signature(_ data: Data, by signer: Curve25519.Signing.PrivateKey = key) -> Data {
        Data(((try? signer.signature(for: data))?.base64EncodedString() ?? "").utf8) + Data("\n".utf8)
    }

    /// One entry, as JSON, with some of its fields replaced.
    static func entry(_ change: [String: Any] = [:], download: [String: Any] = [:]) -> [String: Any] {
        var tool: [String: Any] = [
            "id": "com.acme.deploys", "name": ["en": "Deploys", "fr": "Déploiements"], "publisher": "Acme",
            "summary": ["en": "Copies the address of your latest deploy."], "version": "1.2.0", "protocol": "1",
            "minimumAppVersion": "3.43.0", "source": "https://github.com/acme/deploys",
            "download": ["url": "https://catalog.test/deploys-1.2.0.zip", "sha256": String(repeating: "0", count: 64),
                         "size": 4096] as [String: Any],
            "uses": ["clipboard.write", "notify", "storage"],
            "commands": [["id": "copyLatest", "title": ["en": "Copy latest deploy"]]],
        ]
        var pinned = tool["download"] as? [String: Any] ?? [:]
        for (key, value) in download { pinned[key] = value }
        tool["download"] = pinned
        for (key, value) in change { tool[key] = value }
        return tool
    }

    /// A list's bytes.
    static func list(_ tools: [[String: Any]], generated: String = "2026-11-02T10:00:00Z", version: Int = 1) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["version": version, "generated": generated, "tools": tools],
                                     options: [.sortedKeys])) ?? Data()
    }
}
