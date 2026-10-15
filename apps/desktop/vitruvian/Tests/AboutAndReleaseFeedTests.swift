// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Where the update check looks, and which release and disk image it picks.
/// The tags and the release below are shaped like GitHub's real replies for
/// vitruvian-core on 2026-10-15, when 3.51.0 was Vitruvian's newest release.
enum VitruvianReleaseFeedContract {
    static func run(_ suite: TestSuite) {
        suite.expect(VitruvianReleases.tagsURL.absoluteString
                == "https://api.github.com/repos/VitruvianSoftware/vitruvian-core/git/matching-refs/tags/vitruvian-v",
               "the update check lists Vitruvian's release tags in the public vitruvian-core repository")
        suite.expect(VitruvianReleases.releaseURL(tag: "vitruvian-v3.51.0").absoluteString
                == "https://api.github.com/repos/VitruvianSoftware/vitruvian-core/releases/tags/vitruvian-v3.51.0",
               "the update check reads the release of the tag it chose, in the same repository")

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

        // Alphabetical, as GitHub sends it: 3.10.0 before 3.9.0, other
        // products and the rolling beta mixed in.
        let refs = Data("""
        [
          {"ref": "refs/tags/vitruvian-beta-latest"},
          {"ref": "refs/tags/vitruvian-sdk-v1.4.0"},
          {"ref": "refs/tags/vitruvian-v3.10.0"},
          {"ref": "refs/tags/vitruvian-v3.50.2"},
          {"ref": "refs/tags/vitruvian-v3.51.0"},
          {"ref": "refs/tags/vitruvian-v3.52.0-beta.1"},
          {"ref": "refs/tags/vitruvian-v3.9.0"},
          {"ref": "refs/tags/vitruvian-viewer-v9.0.0"}
        ]
        """.utf8)
        suite.expect(VitruvianReleases.newestTag(refsJSON: refs, includeBetas: false) == "vitruvian-v3.51.0",
               "the newest stable release is found by version among other products' tags")
        suite.expect(VitruvianReleases.newestTag(refsJSON: refs, includeBetas: true) == "vitruvian-v3.52.0-beta.1",
               "with betas on, a newer pre-release tag is the newest")
        suite.expect(VitruvianReleases.newestTag(refsJSON: Data("[]".utf8), includeBetas: false) == nil
                && VitruvianReleases.newestTag(refsJSON: Data("{\"message\":\"Not Found\"}".utf8), includeBetas: false) == nil,
               "a reply with no release tag, or an error body, names no release")

        let base = "https://github.com/VitruvianSoftware/vitruvian-core/releases/download/vitruvian-v3.51.0/"
        func asset(_ name: String, _ size: Int64) -> VitruvianReleases.Release.Asset {
            VitruvianReleases.Release.Asset(name: name, browserDownloadURL: URL(string: base + name)!, size: size)
        }
        // In the order GitHub lists them: the arm64 image comes first.
        let assets = [
            asset("Vitruvian-3.51.0-arm64.dmg", 45_817_427),
            asset("Vitruvian-3.51.0-universal.dmg", 86_335_559),
            asset("Vitruvian-3.51.0-universal.zip", 86_410_973),
            asset("Vitruvian-3.51.0-x86_64.dmg", 47_343_462),
            asset("Vitruvian-3.51.0.dmg", 86_335_559),
        ]
        let release = VitruvianReleases.Release(tagName: "vitruvian-v3.51.0", prerelease: false, draft: false,
                                                assets: assets, body: "## 3.51.0\n- Notes")
        let candidate = VitruvianReleases.candidate(from: release)
        suite.expect(candidate?.dmgURL?.absoluteString == base + "Vitruvian-3.51.0-universal.dmg"
                && candidate?.dmgExpectedBytes == 86_335_559,
               "the updater downloads the release's universal disk image, not the first image it lists")
        suite.expect(candidate?.tagName == "3.51.0",
               "the offered version is the tag's version, which is what the installer expects inside the image")
        let incomplete = VitruvianReleases.Release(tagName: "vitruvian-v3.51.0", prerelease: false, draft: false,
                                                   assets: [assets[0], assets[3]], body: nil)
        suite.expect(VitruvianReleases.candidate(from: incomplete)?.dmgURL == nil,
               "a release without its universal image yet offers no download")
        suite.expect(VitruvianReleases.candidate(from: VitruvianReleases.Release(
                    tagName: "vitruvian-sdk-v1.4.0", prerelease: false, draft: false, assets: assets, body: nil)) == nil,
               "another product's release is never a Vitruvian update")

        if let candidate {
            suite.expect(UpdateServiceSupport.selectUpdate(from: [candidate], currentVersion: "3.50.2",
                                                           includeBetas: false)?.tagName == "3.51.0",
                   "an app on 3.50.2 is offered 3.51.0")
            suite.expect(UpdateServiceSupport.selectUpdate(from: [candidate], currentVersion: "3.51.0",
                                                           includeBetas: false) == nil,
                   "an app on 3.51.0 is up to date")
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
