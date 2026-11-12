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

/// Zips made byte by byte, so a test can make one no tool would: an entry
/// that leaves its folder, a link, an encrypted entry. Entries are stored,
/// not compressed.
enum TestZip {
    struct Item {
        let name: String
        let data: Data
        /// The Unix mode, file type included.
        let mode: UInt32

        init(_ name: String, _ data: Data, mode: UInt32 = 0o100644) {
            self.name = name
            self.data = data
            self.mode = mode
        }
    }

    static func make(_ items: [Item], encrypted: Bool = false) -> Data {
        var local = Data()
        var central = Data()
        let flags: UInt16 = encrypted ? 1 : 0
        for item in items {
            let crc = crc32(item.data)
            let name = Data(item.name.utf8)
            let size = UInt32(item.data.count)
            let offset = UInt32(local.count)
            // The local header: signature, version, flags, stored, time, date.
            local += le32(0x0403_4B50) + le16(20) + le16(flags)
            local += le16(0) + le16(0) + le16(0)
            local += le32(crc) + le32(size) + le32(size)
            local += le16(UInt16(name.count)) + le16(0)
            local += name + item.data
            // The directory: made on Unix (3), then the same, then the mode.
            central += le32(0x0201_4B50) + Data([20, 3]) + le16(20) + le16(flags)
            central += le16(0) + le16(0) + le16(0)
            central += le32(crc) + le32(size) + le32(size)
            central += le16(UInt16(name.count)) + le16(0) + le16(0) + le16(0) + le16(0)
            central += le32(item.mode << 16) + le32(offset) + name
        }
        var end = le32(0x0605_4B50) + le16(0) + le16(0)
        end += le16(UInt16(items.count)) + le16(UInt16(items.count))
        end += le32(UInt32(central.count)) + le32(UInt32(local.count)) + le16(0)
        return local + central + end
    }

    /// A tool's folder, zipped: the manifest test's example at `version`,
    /// with its program, and `extra` items after.
    static func tool(version: String = "1.2.0", id: String = "com.acme.deploys", extra: [Item] = []) -> Data {
        let manifest = ExternalToolManifestTests.file(#"{"version": "\#(version)", "id": "\#(id)"}"#)
        return make([Item("vitruvian-tool.json", manifest), Item("bin/", Data(), mode: 0o040755),
                     Item("bin/deploys", Data("#!/bin/sh\n".utf8), mode: 0o100755)] + extra)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    private static func le32(_ value: UInt32) -> Data {
        le16(UInt16(value & 0xFFFF)) + le16(UInt16(value >> 16))
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}
