// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices

/// Installing from the catalog, up to the agreement sheet and no further: the
/// download, its checks in their order, the zip, and the offer. The network is
/// a table; the zip is unpacked by the real ditto, under the temporary folder.
enum CatalogueInstallerTests {
    static func run(_ suite: TestSuite) {
        archive(suite)
        unpacking(suite)
        anOffer(suite)
        refusals(suite)
        aStoreRefusal(suite)
        anUpdate(suite)
        fromAFolderOntoTheCatalog(suite)
        onlyItsOwn(suite)
    }

    /// Every file under `folder`, by its path inside it, with its bytes; a
    /// folder is listed with no bytes.
    static func snapshot(_ folder: URL) -> [String: Data] {
        var files: [String: Data] = [:]
        let base = folder.resolvingSymlinksInPath().path
        guard let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return files }
        for case let url as URL in walk {
            let path = String(url.resolvingSymlinksInPath().path.dropFirst(base.count))
            files[path] = (try? Data(contentsOf: url)) ?? Data()
        }
        return files
    }

    typealias Item = TestZip.Item

    /// A store's bench, with an installer beside it over a table of answers.
    final class Rig {
        let bench: ExternalToolStoreTests.Bench
        let fetcher = FakeCatalogueFetcher()
        let installer: CatalogueInstaller
        var scratch: URL { bench.root.appendingPathComponent("catalog", isDirectory: true) }

        init(storeLimits: ToolLimits = .standard) {
            bench = ExternalToolStoreTests.Bench(limits: storeLimits)
            let bench = self.bench
            installer = CatalogueInstaller(
                parts: .init(fetcher: fetcher, source: CatalogueFixtures.source,
                             scratch: bench.root.appendingPathComponent("catalog", isDirectory: true),
                             work: { $0() }, toMain: { work in MainActor.assumeIsolated { work() } }),
                store: { bench.store })
        }

        /// An entry for `zip`, served at its address, with what the entry pins
        /// changed by `pin`.
        func entry(_ zip: Data, version: String = "1.2.0", pin: [String: Any] = [:]) -> CatalogueEntry {
            let url = "https://catalog.test/deploys-\(version)-\(UUID().uuidString).zip"
            var download: [String: Any] = ["url": url, "sha256": TestZip.sha256(zip), "size": zip.count]
            for (key, value) in pin { download[key] = value }
            fetcher.answers[URL(string: url)!] = .body(zip, etag: nil)
            let list = CatalogueFixtures.list([CatalogueFixtures.entry(["version": version], download: download)])
            return Catalogue.read(list, permits: CatalogueFixtures.source.permits)!.tools[0]
        }

        func prepare(_ entry: CatalogueEntry) -> Result<ToolOffer, CatalogueRefusal>? {
            var result: Result<ToolOffer, CatalogueRefusal>?
            installer.prepare(entry) { result = $0 }
            return result
        }

        /// What is left in the installer's own folder.
        var leftover: [String] {
            (try? FileManager.default.contentsOfDirectory(atPath: scratch.path)) ?? []
        }

        func close() {
            bench.close()
        }
    }

    static func archive(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.close() }
        try? FileManager.default.createDirectory(at: rig.scratch, withIntermediateDirectories: true)
        func vet(_ data: Data, limits: ToolLimits = .standard) -> Result<CatalogueArchive.Listing, CatalogueArchive.Problem> {
            let file = rig.scratch.appendingPathComponent("\(UUID().uuidString).zip")
            try? data.write(to: file)
            return CatalogueArchive.vet(file, limits: limits)
        }
        let good = vet(TestZip.tool())
        suite.expect(good == .success(.init(names: ["vitruvian-tool.json", "bin/", "bin/deploys"],
                                            bytes: (try? good.get().bytes) ?? -1)),
                     "a tool's zip is read from its directory, every name and the bytes they unpack to")

        var few = ToolLimits()
        few.folderItems = 2
        var small = ToolLimits()
        small.folderBytes = 100
        let refused: [(String, Data, ToolLimits, CatalogueArchive.Problem)] = [
            ("a name that walks up", TestZip.tool(extra: [Item("../escaped.txt", Data("x".utf8))]), .standard,
             .leavesTheFolder("../escaped.txt")),
            ("a name inside that walks up", TestZip.tool(extra: [Item("bin/../../x", Data())]), .standard,
             .leavesTheFolder("bin/../../x")),
            ("an absolute name", TestZip.tool(extra: [Item("/tmp/escaped.txt", Data())]), .standard,
             .leavesTheFolder("/tmp/escaped.txt")),
            ("a backslash", TestZip.tool(extra: [Item("bin\\deploys.exe", Data())]), .standard,
             .leavesTheFolder("bin\\deploys.exe")),
            ("a link", TestZip.tool(extra: [Item("bin/elsewhere", Data("/etc".utf8), mode: 0o120777)]), .standard,
             .link("bin/elsewhere")),
            ("an encrypted entry", TestZip.make([Item("vitruvian-tool.json", Data())], encrypted: true), .standard,
             .encrypted("vitruvian-tool.json")),
            ("too many things", TestZip.tool(), few, .tooBig),
            ("too many bytes", TestZip.tool(), small, .tooBig),
            ("no zip at all", Data("not a zip".utf8), .standard, .notAZip),
        ]
        let missed = refused.filter { vet($0.1, limits: $0.2) != .failure($0.3) }.map(\.0)
        suite.expect(missed.isEmpty, "a zip is refused before anything is unpacked when it would leave its folder, "
                         + "holds a link or an encrypted entry, holds too much, or is no zip (\(missed))")
        let names = ["a", "a/b", "a/", "bin/deploys", "x..y"].filter(CatalogueArchive.isInside)
        let outside = ["", "/a", "~/a", "a/../b", "./a", "a//b", "..", "a\\b", "a\u{0}b"].filter(CatalogueArchive.isInside)
        suite.expect(names.count == 5 && outside.isEmpty, "a name stays inside its folder only when no part of it "
                         + "is empty, . or .., and it is not absolute (\(outside))")
    }

    static func unpacking(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.close() }
        try? FileManager.default.createDirectory(at: rig.scratch, withIntermediateDirectories: true)
        let zip = rig.scratch.appendingPathComponent("tool.zip")
        let folder = rig.scratch.appendingPathComponent("tool", isDirectory: true)
        try? TestZip.tool().write(to: zip)
        guard case .success(let listing) = CatalogueArchive.vet(zip, limits: .standard),
              CatalogueArchive.unpack(zip, into: folder) else {
            suite.expect(false, "a tool's zip is unpacked by ditto")
            return
        }
        let program = folder.appendingPathComponent("bin/deploys")
        suite.expect(CatalogueArchive.looksRight(folder, listing: listing, limits: .standard)
                         && FileManager.default.isExecutableFile(atPath: program.path)
                         && !ToolFolders.isQuarantined(program)
                         && (try? ExternalToolManifest.read(folder: folder).get())?.manifest.id == ToolID("com.acme.deploys"),
                     "unpacked, the folder is the tool: its program can be run, nothing is quarantined, and its "
                         + "manifest reads")
        try? Data("planted".utf8).write(to: folder.appendingPathComponent("bin/planted"))
        let planted = CatalogueArchive.looksRight(folder, listing: listing, limits: .standard)
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("bin/planted"))
        try? FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("bin/link"),
                                                    withDestinationURL: URL(fileURLWithPath: "/etc"))
        suite.expect(!planted && !CatalogueArchive.looksRight(folder, listing: listing, limits: .standard),
                     "after unpacking, a file the zip did not name, or a link, means the folder is not the tool")
    }

    static func anOffer(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.close() }
        let zip = TestZip.tool()
        let entry = rig.entry(zip)
        let result = rig.prepare(entry)
        guard case .success(let offer)? = result else {
            suite.expect(false, "a tool from the catalog is offered (\(String(describing: result)))")
            return
        }
        suite.expect(offer.catalogue == entry.origin && offer.tool.manifest.id == entry.id && offer.replaces == nil
                         && rig.installer.owns(offer.folder)
                         && rig.fetcher.asked.map(\.limit) == [zip.count] && rig.fetcher.asked.map(\.etag) == [nil],
                     "the download is asked for with its pinned size as the limit, and the offer says it came "
                         + "from the catalog")
        suite.expect(rig.bench.store.listed.isEmpty && rig.bench.records.isEmpty && rig.bench.started.isEmpty
                         && !rig.bench.exists(rig.bench.files) && !rig.bench.exists(rig.bench.recordsFile)
                         && !rig.bench.store.isInstalled(entry.id),
                     "until the person agrees nothing is installed, started or remembered")

        let added = rig.bench.store.add(ToolConsent(to: offer, on: Date(timeIntervalSince1970: 1_760_000_000)))
        rig.installer.finished(with: offer)
        let record = rig.bench.records.first
        suite.expect((try? added.get()) != nil && record?.catalogue == entry.origin
                         && record?.agreement.source == entry.download.url.absoluteString
                         && rig.bench.exists(rig.bench.files.appendingPathComponent("bin/deploys"))
                         && rig.leftover.isEmpty,
                     "once the person agrees the tool is added as from a folder, remembered as from the catalog, "
                         + "and the download's folder is deleted")
    }

    static func refusals(_ suite: TestSuite) {
        let zip = TestZip.tool()
        let cases: [(String, (Rig) -> CatalogueEntry, CatalogueRefusal)] = [
            ("a download that does not come", { rig in
                let entry = rig.entry(zip)
                rig.fetcher.answers[entry.download.url] = .failed
                return entry
            }, .unreachable),
            ("a download larger than its pin", { $0.entry(zip + Data(repeating: 0, count: 4096), pin: ["size": zip.count]) },
             .mismatch),
            ("a download smaller than its pin", { $0.entry(zip, pin: ["size": zip.count + 1]) }, .mismatch),
            ("a download whose checksum is not its pin", { rig in
                // Another good tool of the same size: only the checksum tells them apart.
                let listed = TestZip.tool(extra: [Item("README", Data("a".utf8))])
                let served = TestZip.tool(extra: [Item("README", Data("b".utf8))])
                return rig.entry(served, pin: ["sha256": TestZip.sha256(listed)])
            }, .mismatch),
            ("a zip that walks out of its folder",
             { $0.entry(TestZip.tool(extra: [Item("../escaped.txt", Data("x".utf8))])) }, .notTheTool),
            ("a zip with a link", { $0.entry(TestZip.tool(extra: [Item("bin/etc", Data("/etc".utf8), mode: 0o120777)])) },
             .notTheTool),
            ("a zip of another tool", { $0.entry(TestZip.tool(id: "com.acme.other")) }, .notTheTool),
            ("a zip of another version", { $0.entry(TestZip.tool(version: "1.3.0")) }, .notTheTool),
            ("a zip that is no tool", { $0.entry(TestZip.make([Item("README", Data("hi".utf8))])) }, .notTheTool),
        ]
        var wrong: [String] = []
        var left: [String] = []
        for (reason, makeEntry, refusal) in cases {
            let rig = Rig()
            let result = rig.prepare(makeEntry(rig))
            if result != .failure(refusal) { wrong.append(reason) }
            let escaped = rig.bench.root.appendingPathComponent("escaped.txt")
            if !rig.leftover.isEmpty || rig.bench.exists(escaped) || !rig.bench.store.listed.isEmpty
                || rig.bench.exists(rig.bench.support) {
                left.append(reason)
            }
            rig.close()
        }
        suite.expect(wrong.isEmpty, "each check refuses with its own reason, in its order: the size and the "
                         + "checksum before the zip, the zip before the manifest (\(wrong.joined(separator: ", ")))")
        suite.expect(left.isEmpty, "a refusal at any step leaves nothing on disk and nothing in the store "
                         + "(\(left.joined(separator: ", ")))")

        let rig = Rig()
        defer { rig.close() }
        var plain = rig.entry(zip)
        let list = CatalogueFixtures.list([CatalogueFixtures.entry(download: ["url": "http://catalog.test/a.zip",
                                                                             "sha256": TestZip.sha256(zip),
                                                                             "size": zip.count])])
        let lenient = CatalogueSource(list: CatalogueFixtures.source.list, signature: CatalogueFixtures.source.signature,
                                      publicKey: CatalogueFixtures.publicKey, allowsThisMac: true)
        plain = Catalogue.read(list, permits: { lenient.permits($0) || $0.scheme == "http" })?.tools[0] ?? plain
        let asked = rig.fetcher.asked.count
        suite.expect(rig.prepare(plain) == .failure(.unreachable) && rig.fetcher.asked.count == asked,
                     "a download over plain http is not even asked for")
    }

    static func aStoreRefusal(_ suite: TestSuite) {
        var tight = ToolLimits()
        tight.folderItems = 2
        let rig = Rig(storeLimits: tight)
        defer { rig.close() }
        let result = rig.prepare(rig.entry(TestZip.tool()))
        suite.expect(result == .failure(.store(.tooBig(bytes: tight.folderBytes, items: 2))) && rig.leftover.isEmpty,
                     "a folder the store refuses is refused as one the person picked would be, and deleted")
    }

    static func anUpdate(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.close() }
        guard case .success(let first)? = rig.prepare(rig.entry(TestZip.tool())),
              (try? rig.bench.store.add(ToolConsent(to: first)).get()) != nil else {
            suite.expect(false, "a tool from the catalog is installed")
            return
        }
        rig.installer.finished(with: first)
        try? Data("kept".utf8).write(to: rig.bench.data.appendingPathComponent("saved"))
        let newer = rig.entry(TestZip.tool(version: "1.3.0"), version: "1.3.0")
        guard case .success(let offer)? = rig.prepare(newer) else {
            suite.expect(false, "a newer version from the catalog is offered")
            return
        }
        suite.expect(offer.replaces?.version == "1.2.0" && offer.manifestChanged,
                     "a newer version is offered as an update, and the sheet says its manifest changed")
        _ = rig.bench.store.add(ToolConsent(to: offer))
        rig.installer.finished(with: offer)
        suite.expect(rig.bench.records.first?.catalogue?.version == "1.3.0"
                         && rig.bench.exists(rig.bench.data.appendingPathComponent("saved")) && rig.leftover.isEmpty,
                     "updated from the catalog, it keeps what it saved and is remembered at the new version")

        let picked = rig.bench.folder(manifest: ExternalToolManifestTests.file(#"{"version": "1.4.0"}"#))
        rig.bench.add(picked)
        suite.expect(rig.bench.records.first?.catalogue == nil && rig.bench.exists(picked),
                     "updated from a folder, it is a tool added by hand from then on")
    }

    /// A tool added from a folder, updated from the catalog: the download is
    /// checked as for any install, its saved data stays byte for byte, and it
    /// is a tool from the catalog from then on.
    static func fromAFolderOntoTheCatalog(_ suite: TestSuite) {
        let id = ExternalToolStoreTests.id
        let rig = Rig()
        defer { rig.close() }
        let picked = rig.bench.folder("Remote")
        try? Data("only in the folder".utf8).write(to: picked.appendingPathComponent("notes"))
        rig.bench.add(picked)
        let nested = rig.bench.data.appendingPathComponent("cache/day", isDirectory: true)
        try? FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try? Data("kept".utf8).write(to: rig.bench.data.appendingPathComponent("saved"))
        try? Data((0...255).map { UInt8($0) }).write(to: nested.appendingPathComponent("bytes.bin"))
        let saved = snapshot(rig.bench.data)

        // A download that is not the one the catalog pins changes nothing.
        let zip = TestZip.tool(version: "1.3.0")
        let bad = rig.entry(zip, version: "1.3.0", pin: ["sha256": TestZip.sha256(TestZip.tool(version: "1.4.0"))])
        suite.expect(rig.prepare(bad) == .failure(.mismatch) && rig.bench.records.first?.catalogue == nil
                         && rig.bench.records.first?.agreement.version == "1.2.0" && rig.bench.store.isInstalled(id)
                         && rig.leftover.isEmpty,
                     "a tool added from a folder is updated from the catalog only with the download the catalog pins: "
                         + "a refused download leaves it as it was")

        let entry = rig.entry(zip, version: "1.3.0")
        guard case .success(let offer)? = rig.prepare(entry) else {
            suite.expect(false, "a tool added from a folder is offered its newer version from the catalog")
            return
        }
        suite.expect(offer.replaces?.version == "1.2.0" && offer.catalogue == entry.origin
                         && offer.movesFromFolder == picked.resolvingSymlinksInPath().path && offer.manifestChanged
                         && rig.bench.records.first?.catalogue == nil && rig.bench.store.installed[id]?.tool.version == "1.2.0",
                     "the offer replaces the tool added from a folder, names that folder, and until the person "
                         + "agrees the tool stands as it was")
        let later = Date(timeIntervalSince1970: 1_780_000_000)
        guard case .success = rig.bench.store.add(ToolConsent(to: offer, on: later)) else {
            suite.expect(false, "agreed to, the tool is updated from the catalog")
            return
        }
        rig.installer.finished(with: offer)
        let record = rig.bench.records.first
        suite.expect(snapshot(rig.bench.data) == saved && saved.count == 4,
                     "updating a tool added from a folder from the catalog keeps what it saved, byte for byte")
        suite.expect(rig.bench.records.count == 1 && record?.catalogue == entry.origin
                         && record?.agreement.source == entry.download.url.absoluteString
                         && record?.agreement.version == "1.3.0" && record?.agreement.date == later
                         && rig.bench.store.installed[id]?.tool.version == "1.3.0"
                         && !rig.bench.exists(rig.bench.files.appendingPathComponent("notes"))
                         && rig.bench.exists(picked.appendingPathComponent("notes")) && rig.leftover.isEmpty,
                     "updated from the catalog, a tool added from a folder is recorded as from the catalog: its copy "
                         + "is the download's, and the folder it came from is not touched")

        // From then on it is compared as a tool from the catalog.
        let after = rig.bench.relaunched()
        after.store.restore()
        suite.expect(after.store.listed.first?.record.catalogue == entry.origin && after.store.isInstalled(id)
                         && CatalogueWatch.comparedVersion(of: after.store.listed[0]) == "1.3.0",
                     "at the next launch it is a tool from the catalog, compared at the version it came from")
        let newer = rig.entry(TestZip.tool(version: "1.4.0"), version: "1.4.0")
        guard case .success(let next)? = rig.prepare(newer) else { return }
        suite.expect(next.movesFromFolder == nil && next.replaces?.version == "1.3.0",
                     "its next update from the catalog is the usual one")
        rig.installer.finished(with: next)
    }

    static func onlyItsOwn(_ suite: TestSuite) {
        let rig = Rig()
        defer { rig.close() }
        let picked = rig.bench.folder()
        guard case .success(let offer) = rig.bench.store.offer(from: picked) else {
            suite.expect(false, "a picked folder is offered")
            return
        }
        rig.installer.finished(with: offer)
        try? FileManager.default.createDirectory(at: rig.scratch.appendingPathComponent("left/tool"),
                                                 withIntermediateDirectories: true)
        let owned = rig.installer.owns(rig.scratch.appendingPathComponent("left/tool"))
        rig.installer.sweep()
        suite.expect(rig.bench.exists(picked) && !rig.installer.owns(picked) && owned
                         && !rig.installer.owns(rig.scratch) && !rig.bench.exists(rig.scratch),
                     "the installer deletes only its own folders: a folder the person picked is never touched, and "
                         + "at launch what a quit left behind goes")
    }
}
