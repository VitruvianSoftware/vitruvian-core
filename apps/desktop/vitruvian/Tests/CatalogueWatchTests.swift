// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CryptoKit
import Foundation
import VitruvianCore
import VitruvianServices

/// Keeping the list current: when it is fetched, what is kept, what is
/// refused, and which tools have a newer version. Time is a manual clock and
/// the network is a table.
enum CatalogueWatchTests {
    static func run(_ suite: TestSuite) {
        nothingInstalled(suite)
        aToolFromTheCatalog(suite)
        notOurs(suite)
        olderThanBefore(suite)
        keptAcrossLaunches(suite)
        updates(suite)
        aToolAddedFromAFolder(suite)
    }

    final class Rig {
        let bench = ExternalToolStoreTests.Bench()
        let fetcher = FakeCatalogueFetcher()
        let clock = ManualToolClock()
        var kept: URL { bench.root.appendingPathComponent("Catalog.json") }
        private(set) var watch: CatalogueWatch!

        init(appVersion: String = "3.43.0") {
            watch = makeWatch(appVersion: appVersion)
        }

        /// A watch as the app makes one at its next launch: the same files.
        func makeWatch(appVersion: String = "3.43.0") -> CatalogueWatch {
            let bench = self.bench
            return CatalogueWatch(parts: .init(fetcher: fetcher, source: CatalogueFixtures.source, clock: clock,
                                               kept: kept, appVersion: appVersion, listed: { bench.store.listed },
                                               toMain: { work in MainActor.assumeIsolated { work() } }))
        }

        /// Serves a list, signed by `signer`, with an ETag.
        func serve(_ tools: [[String: Any]], generated: String = "2026-11-02T10:00:00Z",
                   signer: Curve25519.Signing.PrivateKey = CatalogueFixtures.key, etag: String = "\"a\"") {
            let list = CatalogueFixtures.list(tools, generated: generated)
            fetcher.answers[CatalogueFixtures.source.list] = .body(list, etag: etag)
            fetcher.answers[CatalogueFixtures.source.signature] = .body(CatalogueFixtures.signature(list, by: signer),
                                                                        etag: nil)
        }

        /// A tool in the store, as installed from the catalog at `version`,
        /// or from a folder when `fromCatalog` is false.
        func install(version: String = "1.2.0", fromCatalog: Bool = true) {
            let folder = bench.folder("v\(version)", manifest: ExternalToolManifestTests.file(#"{"version": "\#(version)"}"#))
            let origin = CatalogueOrigin(id: "com.acme.deploys", version: version, source: "https://github.com/acme/deploys",
                                         download: "https://catalog.test/deploys-\(version).zip")
            if case .success(let offer) = bench.store.offer(from: folder, catalogue: fromCatalog ? origin : nil) {
                bench.store.add(ToolConsent(to: offer))
            }
        }

        var asked: [String] { fetcher.asked.map { $0.url.lastPathComponent + ($0.etag.map { " " + $0 } ?? "") } }

        func close() {
            bench.close()
        }
    }

    static func ready(_ watch: CatalogueWatch) -> Catalogue? {
        if case .ready(let catalogue) = watch.state { return catalogue }
        return nil
    }

    static func nothingInstalled(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.close() }
        rig.serve([CatalogueFixtures.entry()])
        rig.watch.start()
        rig.clock.advance(by: CatalogueWatch.day * 3)
        suite.expect(rig.fetcher.asked.isEmpty && rig.watch.state == .unknown,
                     "with no tool from the catalog installed, nothing is fetched at launch or after, day after day")
        rig.watch.refresh()
        suite.expect(rig.asked == ["tools.json", "tools.json.sig"] && ready(rig.watch)?.tools.count == 1
                         && rig.watch.entries.map(\.id.rawValue) == ["com.acme.deploys"]
                         && rig.bench.exists(rig.kept),
                     "opening the catalog fetches the list and its signature, and keeps the list that verified")
    }

    static func aToolFromTheCatalog(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.close() }
        rig.install()
        rig.serve([CatalogueFixtures.entry()])
        rig.watch.start()
        suite.expect(rig.asked == ["tools.json", "tools.json.sig"] && ready(rig.watch) != nil,
                     "with a tool from the catalog installed, the list is fetched at launch")
        rig.clock.advance(by: CatalogueWatch.day - 1)
        let before = rig.fetcher.asked.count
        rig.clock.advance(by: 1)
        suite.expect(before == 2 && rig.asked == ["tools.json", "tools.json.sig", "tools.json \"a\""]
                         && ready(rig.watch) != nil,
                     "a day later it is asked for again with the ETag it came with, and an unchanged list costs "
                         + "one answer, its signature not fetched again")
        rig.clock.advance(by: CatalogueWatch.day)
        suite.expect(rig.fetcher.asked.count == 4, "and again the day after")
    }

    static func notOurs(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.close() }
        rig.serve([CatalogueFixtures.entry()], signer: Curve25519.Signing.PrivateKey())
        rig.watch.refresh()
        suite.expect(rig.watch.state == .notOurs && rig.watch.entries.isEmpty && !rig.bench.exists(rig.kept),
                     "a list signed with another key is refused, offers nothing and is not kept")
        rig.fetcher.answers[CatalogueFixtures.source.signature] = .failed
        rig.watch.refresh()
        suite.expect(rig.watch.state == .unreachable, "a list whose signature cannot be fetched is not used")
    }

    static func olderThanBefore(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.close() }
        rig.serve([CatalogueFixtures.entry()])
        rig.watch.refresh()
        let kept = try? Data(contentsOf: rig.kept)
        rig.serve([CatalogueFixtures.entry(["version": "1.0.0"])], generated: "2026-10-01T10:00:00Z", etag: "\"b\"")
        rig.watch.refresh()
        suite.expect(rig.watch.state == .notOurs && (try? Data(contentsOf: rig.kept)) == kept,
                     "a list signed by us but older than the one accepted before is refused, and the kept one stays")
    }

    static func keptAcrossLaunches(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.close() }
        rig.install()
        rig.serve([CatalogueFixtures.entry(["version": "1.3.0"])])
        rig.watch.start()
        rig.fetcher.answers = [:]
        let next = rig.makeWatch()
        next.start()
        suite.expect(ready(next)?.tools.first?.version == "1.3.0"
                         && next.update(for: rig.bench.store.listed[0])?.version == "1.3.0",
                     "at the next launch the kept list is used, verified again, when the network is not there")
        // One byte more in the kept list: its signature no longer fits it.
        if var file = (try? JSONSerialization.jsonObject(with: Data(contentsOf: rig.kept))) as? [String: Any],
           let list = (file["list"] as? String).flatMap({ Data(base64Encoded: $0) }) {
            file["list"] = (list + Data(" ".utf8)).base64EncodedString()
            try? JSONSerialization.data(withJSONObject: file).write(to: rig.kept)
        }
        let tampered = rig.makeWatch()
        tampered.start()
        suite.expect(tampered.state == .unreachable, "a kept file that is not one the app wrote is not used")
    }

    static func updates(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.close() }
        rig.install()
        let listed = { rig.bench.store.listed[0] }
        let cases: [(String, [String: Any], String?)] = [
            ("a newer version", ["version": "1.3.0"], "1.3.0"),
            ("the same version", [:], nil),
            ("an older version", ["version": "1.1.0"], nil),
            ("a newer version this app cannot speak", ["version": "1.3.0", "protocol": "3"], nil),
            ("a newer version for a newer app", ["version": "1.3.0", "minimumAppVersion": "9.0.0"], nil),
        ]
        var wrong: [String] = []
        for (index, (reason, change, update)) in cases.enumerated() {
            rig.serve([CatalogueFixtures.entry(change)], generated: "2026-11-0\(index + 2)T10:00:00Z", etag: "\"\(index)\"")
            rig.watch.refresh()
            if rig.watch.update(for: listed())?.version != update { wrong.append(reason) }
        }
        suite.expect(wrong.isEmpty, "a tool from the catalog has an update only when the catalog lists a newer "
                         + "version this app can install (\(wrong.joined(separator: ", ")))")

    }

    /// A tool added from a folder whose id the catalog lists: offered the
    /// catalog's version only when it is newer than the one agreed to.
    static func aToolAddedFromAFolder(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.close() }
        rig.install(fromCatalog: false)
        rig.serve([CatalogueFixtures.entry(["version": "1.3.0"])])
        rig.watch.start()
        suite.expect(rig.fetcher.asked.isEmpty,
                     "a tool added from a folder does not make the app fetch the list at launch")
        rig.watch.refresh()
        let listed = { rig.bench.store.listed[0] }
        suite.expect(listed().record.catalogue == nil && rig.watch.update(for: listed())?.version == "1.3.0"
                         && CatalogueWatch.comparedVersion(of: listed()) == "1.2.0",
                     "a tool added from a folder is offered the catalog's newer version under its id, compared at "
                         + "the version the person agreed to")

        let cases: [(String, [String: Any])] = [
            ("the same version", [:]),
            ("an older version", ["version": "1.1.0"]),
            ("another tool's newer version", ["id": "com.acme.other", "version": "9.0.0"]),
            ("a newer version this app cannot speak", ["version": "1.3.0", "protocol": "3"]),
        ]
        var wrong: [String] = []
        for (index, (reason, change)) in cases.enumerated() {
            rig.serve([CatalogueFixtures.entry(change)], generated: "2026-11-0\(index + 3)T10:00:00Z",
                      etag: "\"f\(index)\"")
            rig.watch.refresh()
            if rig.watch.update(for: listed()) != nil { wrong.append(reason) }
        }
        suite.expect(wrong.isEmpty, "a tool added from a folder is never offered the catalog's version when it is "
                         + "not newer (\(wrong.joined(separator: ", ")))")

        // The app's copy is rewritten: it is held back at the next launch.
        rig.serve([CatalogueFixtures.entry(["version": "1.3.0"])], generated: "2026-11-09T10:00:00Z", etag: "\"h\"")
        rig.watch.refresh()
        try? ExternalToolManifestTests.file(#"{"version": "1.2.0", "uses": ["notify"]}"#)
            .write(to: rig.bench.files.appendingPathComponent("vitruvian-tool.json"))
        let next = rig.bench.relaunched()
        next.store.restore()
        suite.expect(next.store.listed.first?.isHeld == true
                         && next.store.listed.first.flatMap(rig.watch.update(for:)) == nil,
                     "a held-back tool added from a folder is not offered the catalog's version: only its folder "
                         + "brings it back")
    }
}
