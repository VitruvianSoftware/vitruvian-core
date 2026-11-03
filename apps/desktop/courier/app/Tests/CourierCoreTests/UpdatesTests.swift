// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest

@testable import CourierCore

/// Courier's own updates: reading the release list, choosing the newest, and installing only what passes every check.
/// Nothing here reaches the network, mounts a disk image or replaces an app: FakeUpdates answers instead.
@MainActor
final class UpdatesTests: XCTestCase {
    /// The network and the Mac, as the updater sees them, recorded.
    private final class FakeUpdates: UpdateEnvironment, @unchecked Sendable {
        private let lock = NSLock()
        var tagListReply = UpdateReply(status: 200, body: refList(["courier-v0.6.0", "courier-v0.7.1"]))
        var checksumReply = UpdateReply(status: 200, body: Data("\(String(repeating: "ab", count: 32))  Courier-0.7.1-universal.dmg\n".utf8))
        var fileChecksum = String(repeating: "ab", count: 32)
        var signedImage = true
        var signedApp = true
        var notarized = true
        var versionInside: String? = "0.7.1"
        var writable = true
        private(set) var requests: [URL] = []
        private(set) var downloads: [URL] = []
        private(set) var copies: [(URL, URL)] = []
        private(set) var installer: [String]?
        private(set) var mounted = 0
        private(set) var unmounted = 0

        func send(_ request: URLRequest) async throws -> UpdateReply {
            lock.withLock { requests.append(request.url!) }
            return request.url == CourierReleases.tagListURL ? tagListReply : checksumReply
        }

        func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
            lock.withLock { downloads.append(url) }
            progress(0.5)
            progress(1)
        }

        func sha256(of _: URL) throws -> String { fileChecksum }
        func satisfies(_ url: URL, requirement: String) -> Bool {
            if url.pathExtension == "dmg" {
                return signedImage && requirement == CourierReleases.diskImageRequirement
            }
            return signedApp && requirement == CourierReleases.appRequirement
        }

        func passesGatekeeper(_: URL) -> Bool { notarized }
        func mount(_: URL) throws -> URL {
            lock.withLock { mounted += 1 }
            return URL(fileURLWithPath: "/Volumes/CourierFake")
        }

        func unmount(_: URL) { lock.withLock { unmounted += 1 } }
        func bundleVersion(of _: URL) -> String? { versionInside }
        func copy(_ source: URL, to destination: URL) throws { lock.withLock { copies.append((source, destination)) } }
        func isWritableDirectory(_: URL) -> Bool { writable }
        func remove(_: URL) {}
        func launchInstaller(script _: String, arguments: [String]) throws { lock.withLock { installer = arguments } }
    }

    /// A git `ls-refs` reply naming these tags.
    private nonisolated static func refList(_ tags: [String]) -> Data {
        var data = Data()
        for tag in tags {
            let line = "\(String(repeating: "0", count: 40)) refs/tags/\(tag)\n"
            data += Data(String(format: "%04x", line.utf8.count + 4).utf8) + Data(line.utf8)
        }
        return data + Data("0000".utf8)
    }

    private var suites: [String] = []

    override func tearDown() async throws {
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        suites = []
    }

    private func model(_ fake: FakeUpdates, version: String? = "0.7.0",
                       quit: @escaping @MainActor () -> Void = {}) -> UpdateModel {
        let suite = "courier.updates.\(UUID().uuidString)"
        suites.append(suite)
        return UpdateModel(currentVersion: version,
                           appURL: URL(fileURLWithPath: "/Applications/Courier.app"),
                           environment: fake,
                           defaults: ScratchDefaults.suite(named: suite)!,
                           now: { Date(timeIntervalSince1970: 1_800_000_000) },
                           processID: 4242,
                           quit: quit)
    }

    func testReadsTheReleaseListAndPicksTheNewestRelease() throws {
        let tags = try XCTUnwrap(CourierReleases.tags(fromRefList: Self.refList(
            ["courier-v0.9.0", "courier-v0.10.0", "courier-v1.0.0-beta.1", "courier-viewer-v9.0.0", "courier-vjunk"]))
        )
        XCTAssertEqual(tags.count, 5)
        XCTAssertEqual(CourierReleases.newestVersion(in: tags)?.description, "0.10.0",
                       "by version, not alphabetically; a pre-release and another product don't count")
        XCTAssertNil(CourierReleases.tags(fromRefList: Data("0010ERR denied\n".utf8)))
        XCTAssertNil(CourierReleases.tags(fromRefList: Data("zzzz".utf8)))
        XCTAssertNil(CourierReleases.tags(fromRefList: Self.refList(["courier-v1.0.0"]).dropLast(4)),
                     "a reply cut short is not a list")
        XCTAssertEqual(String(decoding: CourierReleases.tagListRequestBody, as: UTF8.self),
                       "0014command=ls-refs\n00010023ref-prefix refs/tags/courier-v\n0000")
        XCTAssertNil(SemanticVersion("1.2"))
        XCTAssertNil(SemanticVersion("1.2.3-beta"))
        XCTAssertNil(SemanticVersion("１.2.3"), "only ASCII digits")
        XCTAssertLessThan(try XCTUnwrap(SemanticVersion("0.9.9")), try XCTUnwrap(SemanticVersion("0.10.0")))

        let version = try XCTUnwrap(SemanticVersion("0.7.1"))
        XCTAssertEqual(CourierReleases.diskImageURL(for: version).absoluteString,
                       "https://github.com/VitruvianSoftware/vitruvian-core/releases/download/courier-v0.7.1/Courier-0.7.1-universal.dmg")
        XCTAssertEqual(CourierReleases.checksumURL(for: version).lastPathComponent, "Courier-0.7.1-universal.dmg.sha256")
        XCTAssertEqual(CourierReleases.checksum(fromSidecar: Data("\(String(repeating: "AB", count: 32))  x.dmg\n".utf8)),
                       String(repeating: "ab", count: 32))
        XCTAssertNil(CourierReleases.checksum(fromSidecar: Data("not-a-checksum  x.dmg".utf8)))
    }

    func testCheckOffersOnlyANewerRelease() async {
        let fake = FakeUpdates()
        let updates = model(fake)
        await updates.check()
        XCTAssertEqual(updates.phase, .available(SemanticVersion("0.7.1")!))
        XCTAssertEqual(updates.lastChecked, Date(timeIntervalSince1970: 1_800_000_000))

        let current = model(fake, version: "0.7.1")
        await current.check()
        XCTAssertEqual(current.phase, .upToDate)

        let ahead = model(fake, version: "0.8.0")
        await ahead.check()
        XCTAssertEqual(ahead.phase, .upToDate, "never a downgrade")

        fake.tagListReply = UpdateReply(status: 429)
        let limited = model(fake)
        await limited.check()
        guard case .failed = limited.phase else { return XCTFail("a refused check says so: \(limited.phase)") }
        XCTAssertNil(limited.lastChecked)

        let unversioned = model(fake, version: nil)
        await unversioned.check()
        guard case .failed = unversioned.phase else { return XCTFail("a build with no version isn't offered one") }
    }

    func testAutomaticChecksCanBeTurnedOff() async {
        let fake = FakeUpdates()
        let updates = model(fake)
        XCTAssertTrue(updates.checksAutomatically, "on by default")
        updates.checksAutomatically = false
        await updates.automaticCheck()
        XCTAssertTrue(fake.requests.isEmpty)
        XCTAssertEqual(updates.phase, .idle)
        updates.checksAutomatically = true
        await updates.automaticCheck()
        XCTAssertEqual(fake.requests, [CourierReleases.tagListURL])
    }

    func testInstallsOnlyAfterEveryCheckPasses() async throws {
        let fake = FakeUpdates()
        var quits = 0
        let updates = model(fake, quit: { quits += 1 })
        await updates.check()
        await updates.installUpdate()

        let version = try XCTUnwrap(SemanticVersion("0.7.1"))
        XCTAssertEqual(updates.phase, .installing(version))
        XCTAssertEqual(fake.downloads, [CourierReleases.diskImageURL(for: version)])
        XCTAssertTrue(fake.requests.contains(CourierReleases.checksumURL(for: version)))
        XCTAssertEqual(fake.copies.first?.0.path, "/Volumes/CourierFake/Courier.app")
        XCTAssertEqual(fake.copies.first?.1.path, "/Applications/.Courier.app.update-0.7.1")
        XCTAssertEqual(fake.installer, ["/Applications/Courier.app", "/Applications/.Courier.app.update-0.7.1", "4242",
                                        "/usr/bin/open"])
        XCTAssertEqual(fake.mounted, 1)
        XCTAssertEqual(fake.unmounted, 1, "the disk image is put away")
        XCTAssertEqual(quits, 1, "Courier quits so the installer can swap the apps")
    }

    func testRefusesWhatFailsAnyCheck() async {
        let failures: [(String, (FakeUpdates) -> Void)] = [
            ("checksum", { $0.fileChecksum = String(repeating: "cd", count: 32) }),
            ("missing checksum", { $0.checksumReply = UpdateReply(status: 404) }),
            ("disk image signature", { $0.signedImage = false }),
            ("app signature", { $0.signedApp = false }),
            ("notarization", { $0.notarized = false }),
            ("version", { $0.versionInside = "0.7.0" }),
            ("read-only folder", { $0.writable = false }),
        ]
        for (name, breakIt) in failures {
            let fake = FakeUpdates()
            breakIt(fake)
            var quits = 0
            let updates = model(fake, quit: { quits += 1 })
            await updates.check()
            await updates.installUpdate()
            guard case .failed = updates.phase else {
                XCTFail("\(name): \(updates.phase)")
                continue
            }
            XCTAssertNil(fake.installer, "\(name): nothing is installed")
            XCTAssertEqual(quits, 0, "\(name): Courier keeps running")
            XCTAssertEqual(fake.mounted, fake.unmounted, "\(name): a mounted image is put away")
        }
    }

    /// The installer script itself, on two stand-in apps in a temporary folder: it waits for the process, swaps the
    /// apps, and opens the result; when the new one is missing, the old one stays.
    func testInstallerScriptSwapsTheAppsAndKeepsTheOldOneOnFailure() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("courier-installer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = folder.appendingPathComponent("Courier.app")
        let new = folder.appendingPathComponent(".Courier.app.update-0.7.1")
        let opened = folder.appendingPathComponent("opened")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: app.appendingPathComponent("version"))
        try Data("new".utf8).write(to: new.appendingPathComponent("version"))
        let opener = folder.appendingPathComponent("open.sh")
        try Data("#!/bin/sh\necho \"$1\" > '\(opened.path)'\n".utf8).write(to: opener)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: opener.path)

        func run(_ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", UpdateModel.installerScript, "courier-update"] + arguments
            try process.run()
            process.waitUntilExit()
        }
        // A process ID no process has (above the kernel's limit), so it doesn't wait.
        try run([app.path, new.path, "999999999", opener.path])
        XCTAssertEqual(try String(contentsOf: app.appendingPathComponent("version"), encoding: .utf8), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: new.path))
        XCTAssertEqual(try String(contentsOf: opened, encoding: .utf8).trimmingCharacters(in: .newlines), app.path)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.contains("update-old") }
        XCTAssertEqual(leftovers, [], "the old app is removed once the new one is in")

        try run([app.path, folder.appendingPathComponent("missing").path, "999999999", opener.path])
        XCTAssertEqual(try String(contentsOf: app.appendingPathComponent("version"), encoding: .utf8), "new",
                       "with nothing to put in its place, the installed app stays")
    }
}
