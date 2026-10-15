// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Where the update check looks, and which release and disk image it picks.
/// The replies come from Tests/Fixtures/release-feed, captured from GitHub
/// on 2026-10-15 at 08:40 PDT, when 3.52.1 was Vitruvian's newest release
/// and this network had 0 of its 60 api.github.com requests left:
/// - ls-refs-vitruvian-v.pkt: git's reply to the app's own tag list request.
/// - ls-refs-vitruvian.pkt: the same with the prefix `vitruvian`, so the SDK's,
///   tool-github's and the rolling beta's tags are mixed in.
/// - head-*.txt: the status and headers of HEAD on a release download link
///   (after GitHub's redirect), for an image that is there and one that is not.
/// - changelog-at-vitruvian-v3.52.1.md: the top of the changelog at the tag.
enum VitruvianReleaseFeedContract {
    nonisolated static func fixture(_ name: String) -> Data {
        (try? Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/release-feed/\(name)"))) ?? Data()
    }

    /// A captured `curl -sIL` reply: its status line and headers.
    nonisolated static func headReply(_ name: String) -> VitruvianReleases.Reply {
        let lines = String(decoding: fixture(name), as: UTF8.self).split(separator: "\n")
        let status = lines.first.flatMap { $0.split(separator: " ").dropFirst().first }.flatMap { Int($0) } ?? 0
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 { headers[String(parts[0])] = parts[1].trimmingCharacters(in: .whitespaces) }
        }
        return VitruvianReleases.Reply(status: status, headers: headers)
    }

    /// One pkt-line of an ls-refs reply, as git writes it.
    nonisolated static func refLine(_ tag: String) -> Data {
        let payload = Data("0000000000000000000000000000000000000000 refs/tags/\(tag)\n".utf8)
        return Data(String(format: "%04x", payload.count + 4).utf8) + payload
    }

    /// The captured tag list with more tags added before its closing `0000`.
    nonisolated static func refList(adding tags: [String]) -> Data {
        var data = fixture("ls-refs-vitruvian-v.pkt").dropLast(4)
        for tag in tags { data += refLine(tag) }
        return Data(data) + Data("0000".utf8)
    }

    /// GitHub as the fixtures captured it. api.github.com answers as it did
    /// that morning: 403, no requests left. Every request is recorded.
    nonisolated final class FixtureGitHub: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [String] = []
        var tagList = VitruvianReleases.Reply(status: 200, body: VitruvianReleaseFeedContract.fixture("ls-refs-vitruvian-v.pkt"))
        var image = VitruvianReleaseFeedContract.headReply("head-Vitruvian-3.52.1-universal.dmg.txt")
        var failure: Error?

        var requests: [String] { lock.withLock { recorded } }

        var transport: VitruvianReleases.Transport {
            { [self] request in
                let url = request.url?.absoluteString ?? ""
                let method = request.httpMethod ?? "GET"
                lock.withLock { recorded.append("\(method) \(url)") }
                if let failure { throw failure }
                if request.url?.host == "api.github.com" {
                    return VitruvianReleases.Reply(status: 403, headers: ["X-RateLimit-Remaining": "0"])
                }
                switch (method, url) {
                case ("POST", VitruvianReleases.tagListURL.absoluteString)
                    where request.httpBody == VitruvianReleases.tagListRequestBody
                        && request.value(forHTTPHeaderField: "Git-Protocol") == "version=2":
                    return tagList
                case ("HEAD", VitruvianReleases.diskImageURL(tag: "vitruvian-v3.52.1", version: "3.52.1").absoluteString):
                    return image
                case ("HEAD", _):
                    return VitruvianReleaseFeedContract.headReply("head-missing-image.txt")
                case ("GET", VitruvianReleases.changelogURL(tag: "vitruvian-v3.52.1").absoluteString):
                    return VitruvianReleases.Reply(status: 200, body: VitruvianReleaseFeedContract.fixture("changelog-at-vitruvian-v3.52.1.md"))
                default:
                    return VitruvianReleases.Reply(status: 404)
                }
            }
        }
    }

    nonisolated final class Box<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Value?
        var value: Value? {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    /// Runs `body` off the main thread and waits for it, turning the run loop.
    static func wait<Value: Sendable>(_ body: @escaping @Sendable () async -> Value) -> Value? {
        let box = Box<Value>()
        Task.detached { box.value = await body() }
        let deadline = Date().addingTimeInterval(10)
        while box.value == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return box.value
    }

    static func run(_ suite: TestSuite) {
        suite.expect(VitruvianReleases.tagListURL.absoluteString
                == "https://github.com/VitruvianSoftware/vitruvian-core.git/git-upload-pack",
               "the update check lists Vitruvian's release tags in the public vitruvian-core repository")
        suite.expect(String(decoding: VitruvianReleases.tagListRequestBody, as: UTF8.self)
                == "0014command=ls-refs\n00010025ref-prefix refs/tags/vitruvian-v\n0000",
               "the tag list request is git's ls-refs for the vitruvian-v tags, byte for byte the one captured")
        suite.expect(VitruvianReleases.diskImageURL(tag: "vitruvian-v3.52.1", version: "3.52.1").absoluteString
                == "https://github.com/VitruvianSoftware/vitruvian-core/releases/download/vitruvian-v3.52.1/Vitruvian-3.52.1-universal.dmg",
               "the updater downloads the release's universal disk image")
        suite.expect(VitruvianReleases.changelogURL(tag: "vitruvian-v3.52.1").absoluteString
                == "https://raw.githubusercontent.com/VitruvianSoftware/vitruvian-core/vitruvian-v3.52.1/apps/desktop/vitruvian/CHANGELOG.md",
               "the release notes come from the app's changelog at the release's tag")

        let versions: [(String, String?)] = [
            ("vitruvian-v3.51.0", "3.51.0"),
            ("vitruvian-v3.52.0-beta.1", "3.52.0-beta.1"),
            ("vitruvian-beta-latest", nil),
            ("vitruvian-viewer-v1.0.0", nil),
            ("vitruvian-sdk-v1.4.0", nil),
            ("vitruvian-tool-github-v1.2.0", nil),
            ("v3.51.0", nil),
            ("vitruvian-v3.51", nil),
            ("vitruvian-v3.51.0/../x", nil),
        ]
        for (tag, expected) in versions {
            suite.expect(VitruvianReleases.version(ofTag: tag) == expected,
                   "only a Vitruvian release tag names a version: \(tag)")
        }

        // git's reply, in git's order: alphabetical, so 3.10.0 before 3.9.0.
        let tags = VitruvianReleases.tags(fromRefList: fixture("ls-refs-vitruvian-v.pkt")) ?? []
        suite.expect(tags.count == 80 && tags.allSatisfy { $0.hasPrefix("vitruvian-v") }
                && tags.contains("vitruvian-v3.52.1") && tags.last == "vitruvian-v3.9.0",
               "git's reply is read as the 80 vitruvian-v tags it held on 2026-10-15")
        let wide = VitruvianReleases.tags(fromRefList: fixture("ls-refs-vitruvian.pkt")) ?? []
        suite.expect(wide.contains("vitruvian-beta-latest") && wide.contains { $0.hasPrefix("vitruvian-sdk-v") }
                && wide.contains { $0.hasPrefix("vitruvian-tool-github-v") },
               "the wider fixture mixes in other products' tags")
        suite.expect(VitruvianReleases.newestTag(in: wide, includeBetas: false) == "vitruvian-v3.52.1"
                && VitruvianReleases.newestTag(in: tags, includeBetas: false) == "vitruvian-v3.52.1",
               "the newest stable release is found by version among other products' tags")
        let lookalike = VitruvianReleases.tags(fromRefList: refList(adding: ["vitruvian-viewer-v9.0.0"])) ?? []
        suite.expect(lookalike.contains("vitruvian-viewer-v9.0.0")
                && VitruvianReleases.newestTag(in: lookalike, includeBetas: true) == "vitruvian-v3.52.1",
               "another product whose tag starts with vitruvian-v is never taken for Vitruvian's newest release")
        let withBeta = tags + ["vitruvian-v3.53.0-beta.1"]
        suite.expect(VitruvianReleases.newestTag(in: withBeta, includeBetas: false) == "vitruvian-v3.52.1"
                && VitruvianReleases.newestTag(in: withBeta, includeBetas: true) == "vitruvian-v3.53.0-beta.1",
               "a newer pre-release counts only with betas on")

        let real = fixture("ls-refs-vitruvian-v.pkt")
        let errorLine = Data("0019ERR access denied\n".utf8)
        suite.expect(VitruvianReleases.tags(fromRefList: Data("0000".utf8)) == []
                && VitruvianReleases.tags(fromRefList: Data()) == nil
                && VitruvianReleases.tags(fromRefList: real.dropLast(4)) == nil
                && VitruvianReleases.tags(fromRefList: real.dropLast(30)) == nil
                && VitruvianReleases.tags(fromRefList: errorLine) == nil
                && VitruvianReleases.tags(fromRefList: Data("{\"message\":\"Not Found\"}".utf8)) == nil
                && VitruvianReleases.tags(fromRefList: Data("<!DOCTYPE html>".utf8)) == nil,
               "a reply that is not a complete tag list (cut short, an error, a web page) names no release")

        // The whole check, against the fixtures.
        let github = FixtureGitHub()
        let found = wait { await VitruvianReleases.findNewest(includeBetas: false, transport: github.transport) }
        let release = try? found?.get()
        suite.expect(release?.tag == "vitruvian-v3.52.1" && release?.version == "3.52.1"
                && release?.diskImageURL == VitruvianReleases.diskImageURL(tag: "vitruvian-v3.52.1", version: "3.52.1"),
               "the check finds 3.52.1 and its universal image from git's tag list and the download link")
        suite.expect(release?.diskImageBytes == 86_364_217,
               "the updater bounds the download by the size the HEAD reply gave")
        suite.expect(github.requests == [
                    "POST https://github.com/VitruvianSoftware/vitruvian-core.git/git-upload-pack",
                    "HEAD https://github.com/VitruvianSoftware/vitruvian-core/releases/download/vitruvian-v3.52.1/Vitruvian-3.52.1-universal.dmg",
                ],
               "the check asks git, then the download link, and never api.github.com: \(github.requests)")

        if let release {
            let candidate = release.candidate(notes: nil)
            suite.expect(candidate.tagName == "3.52.1" && !candidate.isPrerelease && !candidate.isDraft,
                   "the offered version is the tag's version, which is what the installer expects inside the image")
            suite.expect(UpdateServiceSupport.selectUpdate(from: [candidate], currentVersion: "3.52.0",
                                                           includeBetas: false)?.tagName == "3.52.1"
                    && UpdateServiceSupport.selectUpdate(from: [candidate], currentVersion: "3.52.1",
                                                         includeBetas: false) == nil,
                   "an app on 3.52.0 is offered 3.52.1, and an app on 3.52.1 is up to date")
            let notes = wait { await VitruvianReleases.releaseNotes(for: release, transport: github.transport) }
            suite.expect(notes??.hasPrefix("### Bug Fixes") == true
                    && notes??.contains("update check and updater work again") == true
                    && notes??.contains("3.52.0") == false,
                   "the release notes are 3.52.1's own section of the changelog at its tag")
            suite.expect(github.requests.last
                    == "GET https://raw.githubusercontent.com/VitruvianSoftware/vitruvian-core/vitruvian-v3.52.1/apps/desktop/vitruvian/CHANGELOG.md",
                   "the notes are read from raw.githubusercontent.com, not the API")
        }

        let notUploaded = FixtureGitHub()
        notUploaded.image = headReply("head-missing-image.txt")
        let pending = try? wait { await VitruvianReleases.findNewest(includeBetas: false, transport: notUploaded.transport) }?.get()
        suite.expect(pending?.version == "3.52.1" && pending?.diskImageURL == nil
                && pending.flatMap { UpdateServiceSupport.selectUpdate(from: [$0.candidate(notes: nil)],
                                                                       currentVersion: "3.52.0", includeBetas: false) } == nil,
               "a release whose universal image is not uploaded yet offers no download")

        let limited = FixtureGitHub()
        limited.tagList = VitruvianReleases.Reply(status: 429)
        let refusedImage = FixtureGitHub()
        refusedImage.image = VitruvianReleases.Reply(status: 500)
        let offline = FixtureGitHub()
        offline.failure = URLError(.notConnectedToInternet)
        let empty = FixtureGitHub()
        empty.tagList = VitruvianReleases.Reply(status: 200, body: Data("0000".utf8))
        suite.expect(wait { await VitruvianReleases.findNewest(includeBetas: false, transport: limited.transport) }
                    == .failure(.rateLimited)
                && wait { await VitruvianReleases.findNewest(includeBetas: false, transport: refusedImage.transport) }
                    == .failure(.status(500))
                && wait { await VitruvianReleases.findNewest(includeBetas: false, transport: empty.transport) }
                    == .failure(.noRelease),
               "a failed check says why: GitHub's limit, an HTTP status, or no release found")
        if case let .failure(.unreachable(text))? = wait({
            await VitruvianReleases.findNewest(includeBetas: false, transport: offline.transport)
        }) {
            suite.expect(!text.isEmpty, "with no connection, the check says so in the system's words")
        } else {
            suite.expect(false, "with no connection, the check says so in the system's words")
        }

        suite.expect(VitruvianReleases.refusal(status: 200, rateLimitRemaining: "59") == nil,
               "a 200 reply is read")
        suite.expect(VitruvianReleases.refusal(status: 403, rateLimitRemaining: "0") == .rateLimited
                && VitruvianReleases.refusal(status: 429, rateLimitRemaining: nil) == .rateLimited,
               "GitHub's request limit is told apart from other refusals")
        suite.expect(VitruvianReleases.refusal(status: 403, rateLimitRemaining: "12") == .status(403)
                && VitruvianReleases.refusal(status: 404, rateLimitRemaining: nil) == .status(404),
               "any other refusal names its HTTP status instead of a bare dash")
        for language in AppLanguage.allCases {
            let strings = Strings.localized(language)
            suite.expect(!strings.updateRateLimited.isEmpty && !strings.updateNoReleaseFound.isEmpty,
                   "the update check's failure reasons are written in \(language.rawValue)")
        }
    }
}

/// Who the updater and the fan helper trust: the team that signs Vitruvian's
/// releases (3.51.0 is signed by Q5MH753M3F, `codesign -dv`), never the team
/// upstream signs with.
enum UpdateSignerContract {
    static func run(_ suite: TestSuite) {
        suite.expect(FanControlIdentifiers.teamID == "Q5MH753M3F",
               "the app trusts the Developer ID team that signs Vitruvian's releases")
        let script = UpdateInstallerSupport.installerScript()
        suite.expect(script.contains("DMG_VERIFY_REQ='\(UpdateInstallerSupport.diskImageRequirement)'")
                && script.contains("VERIFY_REQ='\(UpdateInstallerSupport.appRequirement)'"),
               "the installer checks the image and the app against the stated requirements")
        suite.expect(UpdateInstallerSupport.diskImageRequirement
                == "anchor apple generic and certificate leaf[subject.OU] = \"Q5MH753M3F\""
                && UpdateInstallerSupport.appRequirement
                == "identifier \"com.vitruviansoftware.vitruvian\" and anchor apple generic and certificate leaf[subject.OU] = \"Q5MH753M3F\"",
               "the installer accepts only an image and an app that Vitruvian's team signed")
        suite.expect(!script.contains("3D485NHW29")
                && !FanControlIdentifiers.appCodeRequirement.contains("3D485NHW29")
                && !FanControlIdentifiers.helperCodeRequirement.contains("3D485NHW29"),
               "nothing trusts upstream's signing team")
    }
}

/// Settings > About: its links lead somewhere, it says what the About box
/// says, and its icon is the app's own.
enum AboutPageContract {
    static func run(_ suite: TestSuite) {
        suite.expect(AppInfo.repositoryURL.absoluteString
                == "https://github.com/VitruvianSoftware/vitruvian-core/tree/main/apps/desktop/vitruvian",
               "View on GitHub opens this app's source in the public vitruvian-core repository")
        suite.expect(AgentPriceSource.remote.absoluteString
                == "https://raw.githubusercontent.com/VitruvianSoftware/vitruvian-core/main/apps/desktop/vitruvian/Resources/agent-prices.json",
               "the price list is fetched from the copy in the public repository")

        // The About box reads Info.plist; the bare harness has none, so it
        // shows the fallback, which must be the same words.
        let plist = (try? Data(contentsOf: URL(fileURLWithPath: "Resources/Info.plist")))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        let aboutBox = plist?["NSHumanReadableCopyright"] as? String
        suite.expect(aboutBox == "© 2026 VitruvianSoftware. Portions © 2026 Vorssaint."
                && AppInfo.copyrightNotice == aboutBox && AppInfo.copyright == aboutBox,
               "Settings > About shows the About box's copyright, which credits VitruvianSoftware and keeps Vorssaint's notice")

        suite.expect(UpdateShowcaseInfo.remoteMediaURL == nil,
               "the showcase asks no server for a video Vitruvian does not publish")
        let loader = UpdateShowcaseMediaLoader()
        loader.load()
        suite.expect(loader.state == .failed,
               "with no video to fetch, the showcase shows its unavailable state at once")

        // Drawn as it is on screen, with the app icon from the source tree.
        // The picture is kept with the test's outputs for a person to look at.
        let icon = NSImage(contentsOf: URL(fileURLWithPath: "Resources/Brand/AppIcon-Default.png"))
        suite.expect(icon != nil, "the app icon artwork is in the test's data")
        guard let icon else { return }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            // In the grouped form the page uses, so the row's own background
            // is behind the icon, as on screen.
            let host = NSHostingView(rootView: Form { Section { AboutHeader(icon: icon) } }
                .formStyle(.grouped)
                .frame(width: 600, height: 460))
            host.appearance = NSAppearance(named: appearance)
            host.frame = CGRect(x: 0, y: 0, width: 600, height: 460)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = host.appearance
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            let header = NSHostingView(rootView: AboutHeader(icon: icon).frame(width: 560))
            suite.expect(header.fittingSize.height > AboutHeader.iconSize + 80,
                   "the About header lays out the icon above its text")
            if let directory = ProcessInfo.processInfo.environment["TEST_UNDECLARED_OUTPUTS_DIR"],
               let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let name = appearance == .aqua ? "about-header-light.png" : "about-header-dark.png"
                try? bitmap.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
            }
            window.contentView = nil
        }
    }
}
