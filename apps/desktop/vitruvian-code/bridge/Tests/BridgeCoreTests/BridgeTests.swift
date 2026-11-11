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

@testable import BridgeCore

/// The bridge's decisions, with a downloader that never touches the network
/// and an unzipper that only writes down what it was asked.
final class BridgeTests: XCTestCase {
    private let fm = FileManager.default
    private var root = URL(fileURLWithPath: "/")

    override func setUp() {
        super.setUp()
        root = fm.temporaryDirectory.appendingPathComponent("bridge-tests-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fm.removeItem(at: root)
        super.tearDown()
    }

    // MARK: - A fake network

    final class FakeNetwork: ReleaseNetwork, @unchecked Sendable {
        var releases: [String: Release] = [:]  // "repo@tag" or "repo@latest"
        var files: [URL: Data] = [:]
        var asked: [String] = []
        var failDownloads = false

        func release(repository: String, tag: String?) async throws -> Release? {
            asked.append("\(repository)@\(tag ?? "latest")")
            return releases["\(repository)@\(tag ?? "latest")"]
        }

        func download(_ url: URL) async throws -> Data {
            if failDownloads { throw BridgeError.download("offline") }
            guard let data = files[url] else { throw BridgeError.download("404 \(url.lastPathComponent)") }
            return data
        }
    }

    private func asset(_ name: String) -> Asset { Asset(name: name, url: URL(string: "https://example.com/dl/\(name)")!) }

    /// A release the way the workflow publishes one: the new app's zip with its
    /// checksum, the DMGs, and the bridge's "universal" zip.
    private func release(_ version: String, tag: String? = nil, withChecksum: Bool = true) -> Release {
        var assets = [asset("VitruvianCode-\(version)-macos.zip"), asset("VitruvianCode-\(version)-macos.dmg"),
                      asset("VitruvianCode-\(version)-arm64.dmg"), asset("NexusAgent-\(version)-universal.zip")]
        if withChecksum { assets.append(asset("VitruvianCode-\(version)-macos.zip.sha256")) }
        return Release(tag: tag ?? "v\(version)", assets: assets)
    }

    private func zipBytes() -> Data { Data("pretend this is a zip".utf8) }

    private func network(_ version: String = "1.33.0") -> FakeNetwork {
        let net = FakeNetwork()
        let release = release(version)
        net.releases["VitruvianSoftware/vitruvian-code@v\(version)"] = release
        net.files[asset("VitruvianCode-\(version)-macos.zip").url] = zipBytes()
        net.files[asset("VitruvianCode-\(version)-macos.zip.sha256").url] =
            Data("\(Checksum.sha256Hex(zipBytes()))  VitruvianCode-\(version)-macos.zip\n".utf8)
        return net
    }

    /// An unzipper that writes the app folder, as ditto would.
    private func fakeInstaller(appName: String = "Vitruvian Code.app", fail: Bool = false) -> Installer {
        Installer(unzip: { _, folder in
            if fail { throw BridgeError.install("boom") }
            let app = folder.appendingPathComponent(appName)
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            try Data("new".utf8).write(to: app.appendingPathComponent("Contents/marker"))
        })
    }

    private func bridge(_ net: FakeNetwork, installer: Installer? = nil, version: String = "1.33.0") -> Bridge {
        Bridge(version: version, network: net, installer: installer ?? fakeInstaller(),
               destination: root.appendingPathComponent("Applications/Vitruvian Code.app"),
               scratch: root.appendingPathComponent("scratch"))
    }

    // MARK: - Which asset

    func testTheNewAppsZipIsPickedByExactNameAndTheBridgeZipNever() throws {
        let picked = try Releases.select(in: release("1.33.0"))
        XCTAssertEqual(picked.zip.name, "VitruvianCode-1.33.0-macos.zip")
        XCTAssertEqual(picked.checksum.name, "VitruvianCode-1.33.0-macos.zip.sha256")
        XCTAssertFalse(picked.zip.name.contains("universal"))
        // Only the bridge's zip (the one old updaters take) and a dmg: nothing to install.
        let only = Release(tag: "v1.33.0", assets: [asset("NexusAgent-1.33.0-universal.zip"), asset("VitruvianCode-1.33.0-macos.dmg")])
        XCTAssertThrowsError(try Releases.select(in: only)) { XCTAssertEqual($0 as? BridgeError, .noAsset("VitruvianCode-1.33.0-macos.zip")) }
        // Another version's zip is not this release's.
        let wrong = Release(tag: "v1.33.0", assets: [asset("VitruvianCode-1.32.0-macos.zip"), asset("VitruvianCode-1.32.0-macos.zip.sha256")])
        XCTAssertThrowsError(try Releases.select(in: wrong))
    }

    func testAZipWithoutItsChecksumIsRefused() {
        XCTAssertThrowsError(try Releases.select(in: release("1.33.0", withChecksum: false))) {
            XCTAssertEqual($0 as? BridgeError, .noChecksum("VitruvianCode-1.33.0-macos.zip"))
        }
    }

    func testVersionsComeOutOfEveryTagShape() {
        XCTAssertEqual(Releases.version(fromTag: "v1.2.3"), "1.2.3")
        XCTAssertEqual(Releases.version(fromTag: "vitruvian-code-v1.2.3"), "1.2.3")
        XCTAssertEqual(Releases.version(fromTag: "nexus-agent-v1.20.1"), "1.20.1")
        XCTAssertEqual(Releases.version(fromTag: "1.2.3"), "1.2.3")
    }

    func testTheReleaseIsFoundByItsTagThenByLatestInEachRepository() async throws {
        // Its own tag, in the first repository.
        var net = network()
        var found = try await Releases.find(version: "1.33.0", network: net)
        XCTAssertEqual(found.tag, "v1.33.0")
        XCTAssertEqual(net.asked, ["VitruvianSoftware/vitruvian-code@v1.33.0"])

        // The first repository does not exist yet (the rename is not done): the old name has it.
        net = FakeNetwork()
        net.releases["VitruvianSoftware/nexus-agent@v1.33.0"] = release("1.33.0")
        found = try await Releases.find(version: "1.33.0", network: net)
        XCTAssertEqual(found.tag, "v1.33.0")
        XCTAssertEqual(net.asked, ["VitruvianSoftware/vitruvian-code@v1.33.0", "VitruvianSoftware/nexus-agent@v1.33.0"])

        // No release with this tag at all: the latest of the first repository, then of the next.
        net = FakeNetwork()
        net.releases["VitruvianSoftware/nexus-agent@latest"] = release("1.40.0")
        found = try await Releases.find(version: "1.33.0", network: net)
        XCTAssertEqual(found.version, "1.40.0")
        XCTAssertEqual(net.asked.suffix(2), ["VitruvianSoftware/vitruvian-code@latest", "VitruvianSoftware/nexus-agent@latest"])

        // A release that has no new-app zip is passed over.
        net = FakeNetwork()
        net.releases["VitruvianSoftware/vitruvian-code@v1.33.0"] = Release(tag: "v1.33.0", assets: [asset("NexusAgent-1.33.0-universal.zip")])
        net.releases["VitruvianSoftware/nexus-agent@v1.33.0"] = release("1.33.0")
        found = try await Releases.find(version: "1.33.0", network: net)
        XCTAssertEqual(found.assets.count, 5)

        net = FakeNetwork()
        do {
            _ = try await Releases.find(version: "1.33.0", network: net)
            XCTFail("nothing to find")
        } catch {
            XCTAssertEqual(error as? BridgeError, .noRelease)
        }
    }

    func testGitHubsJsonIsRead() throws {
        let json = #"{"tag_name":"v1.2.3","assets":[{"name":"a.zip","browser_download_url":"https://x/a.zip"},{"name":"bad"}]}"#
        let release = try XCTUnwrap(GitHubNetwork.parse(Data(json.utf8)))
        XCTAssertEqual(release.tag, "v1.2.3")
        XCTAssertEqual(release.assets, [Asset(name: "a.zip", url: URL(string: "https://x/a.zip")!)])
        XCTAssertNil(GitHubNetwork.parse(Data("{}".utf8)))
    }

    // MARK: - The checksum

    func testTheChecksumMustMatch() throws {
        let data = zipBytes()
        let good = Data("\(Checksum.sha256Hex(data))  file.zip\n".utf8)
        XCTAssertNoThrow(try Checksum.verify(data, against: good))
        XCTAssertNoThrow(try Checksum.verify(data, against: Data(Checksum.sha256Hex(data).uppercased().utf8)), "bare digits, any case")
        XCTAssertThrowsError(try Checksum.verify(Data("other".utf8), against: good)) { XCTAssertEqual($0 as? BridgeError, .checksumMismatch) }
        for bad in ["", "not a digest", String(repeating: "g", count: 64), "abc123"] {
            XCTAssertThrowsError(try Checksum.verify(data, against: Data(bad.utf8))) { XCTAssertEqual($0 as? BridgeError, .badChecksumFile, bad) }
        }
        XCTAssertEqual(Checksum.sha256Hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    // MARK: - Where it installs

    func testItInstallsBesideItselfWhenThatFolderIsWritable() {
        let home = URL(fileURLWithPath: "/Users/a")
        let there = InstallLocation.destination(bundleURL: URL(fileURLWithPath: "/Applications/NexusAgent.app"), home: home, isWritable: { _ in true })
        XCTAssertEqual(there.path, "/Applications/Vitruvian Code.app")
        let custom = InstallLocation.destination(bundleURL: URL(fileURLWithPath: "/Users/a/Apps/NexusAgent.app"), home: home, isWritable: { _ in true })
        XCTAssertEqual(custom.path, "/Users/a/Apps/Vitruvian Code.app")
    }

    func testATranslocatedOrReadOnlyHomeFallsBackToApplications() {
        let home = URL(fileURLWithPath: "/Users/a")
        let moved = URL(fileURLWithPath: "/private/var/folders/x/T/AppTranslocation/ABC/d/NexusAgent.app")
        XCTAssertEqual(InstallLocation.destination(bundleURL: moved, home: home, isWritable: { _ in true }).path,
                       "/Applications/Vitruvian Code.app")
        let readOnly = URL(fileURLWithPath: "/Volumes/Disk/NexusAgent.app")
        XCTAssertEqual(InstallLocation.destination(bundleURL: readOnly, home: home, isWritable: { $0.path == "/Applications" }).path,
                       "/Applications/Vitruvian Code.app")
        XCTAssertEqual(InstallLocation.destination(bundleURL: readOnly, home: home, isWritable: { _ in false }).path,
                       "/Users/a/Applications/Vitruvian Code.app")
    }

    // MARK: - The whole run

    func testItDownloadsChecksInstallsAndHandsOver() async throws {
        let net = network()
        var lines: [String] = []
        var run = bridge(net)
        run.progress = { lines.append($0) }
        var opened: [URL] = []
        var trashed = 0
        let result = await run.installAndHandOver(open: { opened.append($0) }, trashSelf: { trashed += 1 })

        XCTAssertEqual(result, .success(run.destination))
        XCTAssertEqual(try String(contentsOf: run.destination.appendingPathComponent("Contents/marker"), encoding: .utf8), "new")
        XCTAssertEqual(opened, [run.destination])
        XCTAssertEqual(trashed, 1)
        XCTAssertEqual(lines.first, "Looking for Vitruvian Code…")
        XCTAssertTrue(lines.contains("Installing…"))
        XCTAssertFalse(fm.fileExists(atPath: run.scratch.path), "scratch space is cleaned up")
    }

    func testAnAppAlreadyThereIsReplacedOnlyOnceTheNewOneIsWhole() async throws {
        let net = network()
        let run = bridge(net)
        try fm.createDirectory(at: run.destination.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: run.destination.appendingPathComponent("Contents/marker"))

        // A download that does not unpack leaves the old app as it was.
        let broken = bridge(net, installer: fakeInstaller(fail: true))
        var trashed = 0
        let failed = await broken.installAndHandOver(open: { _ in XCTFail("not opened") }, trashSelf: { trashed += 1 })
        XCTAssertEqual(failed, .failure(.install("boom")))
        XCTAssertEqual(try String(contentsOf: run.destination.appendingPathComponent("Contents/marker"), encoding: .utf8), "old")
        XCTAssertEqual(trashed, 0)

        let ok = await run.installAndHandOver(open: { _ in }, trashSelf: {})
        XCTAssertEqual(ok, .success(run.destination))
        XCTAssertEqual(try String(contentsOf: run.destination.appendingPathComponent("Contents/marker"), encoding: .utf8), "new")
    }

    func testAFailureNeverTrashesTheBridge() async {
        var trashed = 0
        func fails(_ net: FakeNetwork, _ expected: BridgeError, installer: Installer? = nil) async {
            let result = await bridge(net, installer: installer).installAndHandOver(open: { _ in XCTFail("opened") }, trashSelf: { trashed += 1 })
            XCTAssertEqual(result, .failure(expected))
        }
        await fails(FakeNetwork(), .noRelease)

        let offline = network()
        offline.failDownloads = true
        await fails(offline, .download("offline"))

        let tampered = network()
        tampered.files[asset("VitruvianCode-1.33.0-macos.zip").url] = Data("tampered".utf8)
        await fails(tampered, .checksumMismatch)

        let noSum = network()
        noSum.releases["VitruvianSoftware/vitruvian-code@v1.33.0"] = release("1.33.0", withChecksum: false)
        await fails(noSum, .noRelease)

        await fails(network(), .install("the download has no Vitruvian Code.app"), installer: fakeInstaller(appName: "Wrong.app"))
        XCTAssertEqual(trashed, 0, "the bridge is the person's way back, so it stays")
    }

    func testAFailedTrashDoesNotUndoASuccessfulInstall() async {
        struct Nope: Error {}
        let run = bridge(network())
        let result = await run.installAndHandOver(open: { _ in }, trashSelf: { throw Nope() })
        XCTAssertEqual(result, .success(run.destination))
    }
}
