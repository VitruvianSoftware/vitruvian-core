// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianAtriumCore
import VitruvianAtriumServices

/// The production ownership lookup, against a stand-in brew that answers what
/// the test tells it. No real brew command, installed application or package
/// receipt is touched by these checks.
enum HomebrewOwnershipTests {
    typealias Lookup = Result<HomebrewPackage?, HomebrewOwnershipError>

    private static func isUnmanaged(_ result: Lookup?) -> Bool {
        if case .success(nil)? = result { return true }
        return false
    }

    private static func isUnavailable(_ result: Lookup?) -> Bool {
        if case .failure? = result { return true }
        return false
    }

    private static func packageName(_ result: Lookup?) -> String? {
        if case let .success(package)? = result { return package?.name }
        return nil
    }

    static func run(_ suite: TestSuite) {
        let app = URL(fileURLWithPath: "/Applications/Editor.app")
        let inventory = #"{"formulae":[],"casks":[{"token":"editor","name":["Editor"],"installed":"1","artifacts":[{"app":["Source.app",{"target":"Editor.app"}],"target":"/Applications/Editor.app"}]}]}"#
        let empty = #"{"formulae":[],"casks":[]}"#

        for output in ["timed out", "not JSON", "{}",
                       #"{"casks":[{"token":"--invalid","installed":"1","artifacts":[]}]}"#,
                       #"{"casks":[{"token":"editor","installed":"1"}]}"#] {
            suite.expect((try? HomebrewParser.parseInstalledCaskRecords(output)) == nil,
                         "malformed inventory is not an empty one (\(output))")
        }
        suite.expect((try? HomebrewParser.parseInstalledCaskRecords("Warning: catalog notice\n" + inventory))?.count == 1
                     && (try? HomebrewParser.parseInstalledCaskRecords(empty))?.isEmpty == true,
                     "a notice before the inventory, or no casks at all, still reads as an inventory")

        guard let records = try? HomebrewParser.parseInstalledCaskRecords(inventory) else {
            suite.expect(false, "valid installed metadata parses")
            return
        }
        suite.expect(packageName(HomebrewOwnershipSupport.packageManagingApplication(
            atPath: app.path, installed: records)) == "editor",
                     "the exact installed path resolves to its cask")
        suite.expect(isUnmanaged(HomebrewOwnershipSupport.packageManagingApplication(
            atPath: "/Users/test/Desktop/Editor.app", installed: records)),
                     "a same-named copy outside the exact installed path stays independent")
        suite.expect(isUnavailable(HomebrewOwnershipSupport.packageManagingApplication(
            atPath: app.path, installed: records + records)),
                     "ambiguous ownership blocks both package and ordinary removal")
        let relative = HomebrewCaskRecord(token: "editor", displayName: "Editor", installedVersion: "1",
                                          appFileNames: ["Editor.app"])
        suite.expect(isUnavailable(HomebrewOwnershipSupport.packageManagingApplication(
            atPath: app.path, installed: [relative])),
                     "an installed app without its target path needs verification, not a guessed owner")
        let custom = HomebrewCaskRecord(token: "editor", displayName: "Editor", installedVersion: "1",
                                        appFileNames: ["Renamed.app"],
                                        appPaths: ["/Users/test/Applications/Renamed.app"])
        suite.expect(packageName(HomebrewOwnershipSupport.packageManagingApplication(
            atPath: "/Users/test/Applications/Renamed.app", installed: [custom])) == "editor",
                     "exact ownership supports a renamed app in a custom app directory")
        if let package = try? HomebrewOwnershipSupport.packageManagingApplication(atPath: app.path, installed: records).get() {
            suite.expect(HomebrewCommandBuilder.uninstall(brewPath: "/opt/homebrew/bin/brew", package: package).arguments
                         == ["uninstall", "--cask", "editor"],
                         "verified casks keep normal uninstall without automatic zap or force")
        } else {
            suite.expect(false, "the exact app resolves before building its uninstall command")
        }

        var answer: Lookup?
        let absent = HomebrewManager(locateBrew: { nil })
        absent.packageManagingApplication(at: app) { answer = $0 }
        suite.expect(isUnmanaged(answer), "a Mac without Homebrew still supports ordinary removal")

        lookups(suite, app: app, inventory: inventory, empty: empty)
    }

    /// The manager's own reads, through a stand-in brew that logs each call
    /// and prints the reply and exit status the test left for it.
    private static func lookups(_ suite: TestSuite, app: URL, inventory: String, empty: String) {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("vitru-brew-ownership-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: folder) }
        let calls = folder.appendingPathComponent("calls.log")
        let reply = folder.appendingPathComponent("reply")
        let status = folder.appendingPathComponent("status")
        let stub = folder.appendingPathComponent("brew")
        let script = "#!/bin/sh\necho \"$*\" >> \"\(calls.path)\"\ncat \"\(reply.path)\"\nexit \"$(cat \"\(status.path)\")\"\n"
        func answerWith(_ code: Int32, _ output: String) {
            try? output.write(to: reply, atomically: true, encoding: .utf8)
            try? "\(code)".write(to: status, atomically: true, encoding: .utf8)
        }
        func ran() -> [String] {
            ((try? String(contentsOf: calls, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        }
        guard (try? fm.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
              (try? script.write(to: stub, atomically: true, encoding: .utf8)) != nil,
              (try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)) != nil else {
            suite.expect(false, "the stand-in brew is staged")
            return
        }
        let manager = HomebrewManager(locateBrew: { stub.path })
        // The first brew run waits on the login shell for its environment.
        func wait(until done: () -> Bool) {
            let deadline = Date().addingTimeInterval(60)
            while Date() < deadline, !done() {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
        }

        answerWith(0, "Warning: catalog notice\n" + inventory)
        var answer: Lookup?
        var concurrent: Lookup?
        manager.packageManagingApplication(at: app) { answer = $0 }
        manager.packageManagingApplication(at: app) { concurrent = $0 }
        wait { answer != nil && concurrent != nil }
        suite.expect(packageName(answer) == "editor" && packageName(concurrent) == "editor"
                     && ran() == ["info --json=v2 --installed"],
                     "concurrent lookups share one installed inventory read and both learn its owner: ran \(ran())")

        for (code, output) in [(Int32(1), inventory), (0, "not JSON")] {
            answer = nil
            answerWith(code, output)
            manager.packageManagingApplication(at: app) { answer = $0 }
            wait { answer != nil }
            suite.expect(isUnavailable(answer),
                         "a failed or malformed inventory is not an unmanaged app (status \(code), \(output))")
        }

        answer = nil
        answerWith(0, empty)
        manager.packageManagingApplication(at: app) { answer = $0 }
        wait { answer != nil }
        suite.expect(isUnmanaged(answer), "a verified empty inventory permits ordinary removal")
        let readsBeforeInstall = ran().count
        answer = nil
        answerWith(0, inventory)
        manager.packageManagingApplication(at: app) { answer = $0 }
        wait { answer != nil }
        suite.expect(ran().count == readsBeforeInstall + 1 && packageName(answer) == "editor",
                     "a new lookup reads the inventory again, so it finds a cask installed since the last one")
    }
}
