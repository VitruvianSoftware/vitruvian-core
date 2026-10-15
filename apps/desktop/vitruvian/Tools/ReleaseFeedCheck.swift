// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

// Checks, against the live internet, what the unit tests check against
// fixtures: the app's own update check (`UpdateService`) finds the newest
// release and the universal disk image, and every link on Settings > About
// opens. With --verify-download it also downloads that image and checks it
// the way the installer does before it swaps anything.
//
//   bazel run --config=macos-app //apps/desktop/vitruvian:release_feed_check
//   bazel run --config=macos-app //apps/desktop/vitruvian:release_feed_check -- --verify-download
//
// A bare binary reports its version as "dev", which every release is newer
// than, so the check always names the newest stable release. It asks GitHub
// without a token, as the app does: 60 requests an hour from one address.

import Foundation
import VitruvianCore
import VitruvianServices

let verifyDownload = CommandLine.arguments.contains("--verify-download")
/// The newest stable release on the day this check was written.
let oldestAcceptable = "3.51.0"
var failures = 0

func report(_ passed: Bool, _ line: String) {
    print("\(passed ? "PASS" : "FAIL")  \(line)")
    if !passed { failures += 1 }
}

/// Waits on a background request without blocking the main queue's work.
func wait(until done: () -> Bool, seconds: TimeInterval) {
    let deadline = Date().addingTimeInterval(seconds)
    while !done(), Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}

func status(of url: URL) -> Int {
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    nonisolated(unsafe) var code = 0
    nonisolated(unsafe) var finished = false
    URLSession.shared.dataTask(with: request) { _, response, _ in
        code = (response as? HTTPURLResponse)?.statusCode ?? 0
        finished = true
    }.resume()
    wait(until: { finished }, seconds: 20)
    return code
}

@discardableResult
func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { return (-1, "\(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

MainActor.assumeIsolated {
    print("Update check (UpdateService, live GitHub API)")
    let service = UpdateService.shared
    service.check(manual: true)
    wait(until: { service.state != .checking }, seconds: 45)
    var offered: (version: String, url: URL)?
    switch service.state {
    case let .available(version):
        report(!UpdateServiceSupport.isNewer(oldestAcceptable, than: version),
               "newest stable release is \(version) (\(oldestAcceptable) or newer expected)")
        if let url = service.downloadURL {
            report(url.lastPathComponent == VitruvianReleases.diskImageName(version: version),
                   "it would download \(url.absoluteString)")
            offered = (version, url)
        } else {
            report(false, "it found no disk image to download")
        }
    default:
        report(false, "the check ended as \(service.state)")
    }

    print("\nSettings > About links")
    for (name, url) in [("View on GitHub", AppInfo.repositoryURL), ("Website", AppInfo.websiteURL),
                        ("Price list", AgentPriceSource.remote)] {
        let code = status(of: url)
        report(code == 200, "\(name): HTTP \(code)  \(url.absoluteString)")
    }

    guard verifyDownload, let offered else { return }
    print("\nThe download, checked as the installer checks it")
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("release-feed-check-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let image = folder.appendingPathComponent(offered.url.lastPathComponent)
    nonisolated(unsafe) var saved = false
    URLSession.shared.downloadTask(with: offered.url) { location, _, _ in
        if let location { saved = (try? FileManager.default.moveItem(at: location, to: image)) != nil }
    }.resume()
    wait(until: { saved }, seconds: 600)
    report(saved, "downloaded \(image.lastPathComponent)")
    guard saved else { return }

    let imageCheck = run("/usr/bin/codesign",
                         ["-v", "--strict", "-R=\(UpdateInstallerSupport.diskImageRequirement)", image.path])
    report(imageCheck.status == 0,
           "the disk image is signed by Vitruvian's team (installer step fail-dmg-verify) \(imageCheck.output.trimmingCharacters(in: .whitespacesAndNewlines))")

    let mount = folder.appendingPathComponent("mount", isDirectory: true)
    try? FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
    let attach = run("/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-readonly", "-quiet",
                                          "-mountpoint", mount.path])
    report(attach.status == 0, "the disk image mounts")
    guard attach.status == 0 else { return }
    defer { run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"]) }
    let app = mount.appendingPathComponent("Vitruvian.app")
    let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
    let bundleVersion = plist?["CFBundleShortVersionString"] as? String
    report(bundleVersion == offered.version,
           "the app inside is version \(bundleVersion ?? "none") (installer step fail-version)")
    let appCheck = run("/usr/bin/codesign",
                       ["-v", "--deep", "--strict", "-R=\(UpdateInstallerSupport.appRequirement)", app.path])
    report(appCheck.status == 0,
           "the app is signed by Vitruvian's team (installer step fail-verify) \(appCheck.output.trimmingCharacters(in: .whitespacesAndNewlines))")
    let gatekeeper = run("/usr/sbin/spctl", ["-a", "-t", "exec", "-vv", app.path])
    report(gatekeeper.status == 0,
           "Gatekeeper accepts the app (installer step fail-verify): \(gatekeeper.output.trimmingCharacters(in: .whitespacesAndNewlines))")
    let universal = run("/usr/bin/lipo", ["-archs", app.appendingPathComponent("Contents/MacOS/Vitruvian").path])
    report(universal.output.contains("x86_64") && universal.output.contains("arm64"),
           "the app is universal: \(universal.output.trimmingCharacters(in: .whitespacesAndNewlines))")
}

print(failures == 0 ? "\nRELEASE FEED CHECK OK" : "\nRELEASE FEED CHECK FAILED (\(failures))")
exit(failures == 0 ? 0 : 1)
