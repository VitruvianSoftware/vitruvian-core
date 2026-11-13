// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianAtriumCore
import VitruvianAtriumDesign
import VitruvianAtriumServices
import VitruvianAtriumUI

/// The module's real scans and removal guard, in a fixture home folder and
/// shared Library folder where Launch Services knows no app. No cleaning is
/// performed.
enum CleanerEligibilityTests {
    typealias Item = JunkCleaner.Item

    /// A fixture's home folder: no app is registered with Launch Services,
    /// and screenshots are saved in `screenshots`. The shared Library folder
    /// is `Library` beside the home folder, never the real `/Library`.
    static func places(home: URL, screenshots: [URL] = []) -> JunkCleaner.Places {
        JunkCleaner.Places(home: home.path,
                           systemLibrary: home.deletingLastPathComponent().appendingPathComponent("Library").path,
                           screenshotFolders: { screenshots }, isRegistered: { _ in false })
    }

    static func item(_ url: URL, _ category: CleanerSupport.Category = .leftovers, detail: String,
                     recommended: Bool = false) -> Item {
        Item(url: url, category: category, size: 1, detail: detail, recommended: recommended)
    }

    static func owner(_ url: URL, metadata: Bool = false) -> String? {
        JunkCleaner.leftoverOwner(entry: url.lastPathComponent, url: url, usesContainerMetadata: metadata)
    }

    static func setAttribute(_ name: String, _ data: Data, on url: URL) {
        url.withUnsafeFileSystemRepresentation { path in
            _ = data.withUnsafeBytes { setxattr(path!, name, $0.baseAddress, data.count, 0, 0) }
        }
    }

    /// The exact bytes macOS writes for the flag and a last opened date.
    static let screenCaptureFlag = Data([0x62, 0x70, 0x6C, 0x69, 0x73, 0x74, 0x30, 0x30, 0x09, 0x08,
                                         0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1,
                                         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x09])

    static func lastUsedAttribute(_ date: Date) -> Data {
        var seconds = Int64(date.timeIntervalSince1970).littleEndian
        var data = Data(bytes: &seconds, count: 8)
        data.append(Data(count: 8))
        return data
    }

    static func runScreenshotRules(_ suite: TestSuite) {
        let home = "/Users/someone"
        suite.expect(CleanerSupport.screenshotFolder(location: nil, home: home) == home + "/Desktop"
                     && CleanerSupport.screenshotFolder(location: "  ", home: home) == home + "/Desktop"
                     && CleanerSupport.screenshotFolder(location: "~/Documents/Shots", home: home)
                        == home + "/Documents/Shots"
                     && CleanerSupport.screenshotFolder(location: "/Volumes/Work/Shots", home: home)
                        == "/Volumes/Work/Shots"
                     && CleanerSupport.screenshotFolder(location: "relative", home: home) == home + "/Desktop",
                     "the screenshot folder follows the system setting, the Desktop by default")
        suite.expect(CleanerSupport.isScreenCaptureFlag(screenCaptureFlag)
                     && !CleanerSupport.isScreenCaptureFlag(Data())
                     && !CleanerSupport.isScreenCaptureFlag(
                        try! PropertyListSerialization.data(fromPropertyList: false, format: .binary, options: 0)),
                     "only a true capture flag marks a screenshot")
        let opened = Date(timeIntervalSince1970: 1_781_716_463)
        suite.expect(CleanerSupport.lastUsedDate(fromAttribute: Data([0xEF, 0xD5, 0x32, 0x6A, 0, 0, 0, 0,
                                                                     0, 0, 0, 0, 0, 0, 0, 0])) == opened
                     && CleanerSupport.lastUsedDate(fromAttribute: Data([1, 2])) == nil,
                     "the last opened date reads the system timespec")
        let utc = TimeZone(identifier: "UTC")!
        let taken = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21 14:13:20 UTC
        suite.expect(CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 14.13.20.png",
                                                               created: taken, timeZone: utc)
                     && CleanerSupport.screenshotKeepsDefaultName("Captura de Tela 2026-09-21 às 14.13.20 (2).png",
                                                                  created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("button spacing.png",
                                                                   created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-03-01 at 09.00.00.png",
                                                                   created: taken, timeZone: utc),
                     "a renamed capture is no longer a default screenshot")
        // A rename that keeps the name macOS gave it and adds to it is still a
        // rename. Duplicating a capture in Finder is the everyday case, and the
        // day period on a twelve hour Mac has to survive the same check.
        suite.expect(CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 2.13.20\u{202F}PM.png",
                                                               created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 14.13.20 copy.png",
                                                                   created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 2.13.20\u{202F}PM copy.png",
                                                                   created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 14.13.20 ui.png",
                                                                   created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 14.13.20 ok.png",
                                                                   created: taken, timeZone: utc)
                     // A mark is a rename too, and must not reduce to the empty
                     // tail that an untouched twenty four hour name carries.
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 14.13.20 !.png",
                                                                   created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 14.13.20 \u{1F525}.png",
                                                                   created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 2.13.20\u{202F}PM!.png",
                                                                   created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 2.13.20\u{202F}PM \u{2B50}.png",
                                                                   created: taken, timeZone: utc)
                     // A single letter is a day period in some locale, so only
                     // a twelve hour clock may carry one: 14.13.20 cannot.
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 14.13.20 M.png",
                                                                   created: taken, timeZone: utc)
                     // An invisible character is not the absence of a suffix.
                     && !CleanerSupport.screenshotKeepsDefaultName("Screenshot 2026-09-21 at 14.13.20 \u{200B}.png",
                                                                   created: taken, timeZone: utc)
                     // The day periods themselves keep working, spacing and all.
                     && CleanerSupport.screenshotKeepsDefaultName("Captura de pantalla 2026-09-21 a las 2.13.20 p. m..png",
                                                                  created: taken, timeZone: utc)
                     && CleanerSupport.screenshotKeepsDefaultName("\u{622A}\u{5C4F}2026-09-21 2.13.20\u{4E0B}\u{5348}.png",
                                                                  created: taken, timeZone: utc)
                     && !CleanerSupport.screenshotKeepsDefaultName("button spacing 2026-09-21.png",
                                                                   created: taken, timeZone: utc),
                     "a capture renamed by adding to its name is no longer a default screenshot")
        let now = taken.addingTimeInterval(31 * 86_400)
        suite.expect(CleanerSupport.isForgottenScreenshot(created: taken, modified: taken, lastUsed: nil,
                                                          now: now, days: 30)
                     && !CleanerSupport.isForgottenScreenshot(created: taken, modified: taken,
                                                              lastUsed: now.addingTimeInterval(-86_400),
                                                              now: now, days: 30)
                     && !CleanerSupport.isForgottenScreenshot(created: taken, modified: nil, lastUsed: nil,
                                                              now: now, days: 60)
                     && !CleanerSupport.isForgottenScreenshot(created: taken, modified: nil, lastUsed: nil,
                                                              now: now, days: 0),
                     "a screenshot is forgotten only after the chosen days without being opened")
    }

    static func runScreenshotScan(_ suite: TestSuite, root: URL) throws {
        let manager = FileManager.default
        let folder = root.appendingPathComponent("Shots", isDirectory: true)
        try manager.createDirectory(at: folder.appendingPathComponent("Kept"), withIntermediateDirectories: true)
        let places = Self.places(home: root, screenshots: [folder])
        func canRemove(_ item: Item) -> Bool { JunkCleaner.mayRemove(item, installed: [], places: places) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let old = Date().addingTimeInterval(-45 * 86_400)
        let oldName = "Screenshot \(formatter.string(from: old)) at 10.00.00.png"
        let newName = "Screenshot \(formatter.string(from: Date())) at 10.00.00.png"
        func capture(_ name: String, in dir: URL = folder, created: Date = old,
                     marked: Bool = true, opened: Date? = nil) throws -> URL {
            let url = dir.appendingPathComponent(name)
            try Data(repeating: 7, count: 8192).write(to: url)
            try manager.setAttributes([.creationDate: created, .modificationDate: created], ofItemAtPath: url.path)
            if marked { setAttribute(CleanerSupport.screenCaptureAttribute, screenCaptureFlag, on: url) }
            if let opened { setAttribute(CleanerSupport.lastUsedDateAttribute, lastUsedAttribute(opened), on: url) }
            return url
        }
        let forgotten = try capture(oldName)
        _ = try capture("plain " + oldName, marked: false)
        _ = try capture("button spacing.png")
        _ = try capture(newName, created: Date())
        _ = try capture(oldName.replacingOccurrences(of: ".png", with: " (2).png"),
                        opened: Date().addingTimeInterval(-86_400))
        let moved = try capture(oldName, in: folder.appendingPathComponent("Kept"))

        let found = JunkCleaner.scanScreenshots(in: [folder], days: 30)
        suite.expect(found.map { $0.url.resolvingSymlinksInPath().path }
                        == [forgotten.resolvingSymlinksInPath().path]
                     && found.allSatisfy { $0.category == .screenshots && !$0.recommended },
                     "only an old, unopened, marked capture under its own name is listed, unchecked")
        suite.expect(JunkCleaner.scanScreenshots(in: [folder], days: 60).isEmpty,
                     "a longer age leaves a younger capture alone")
        suite.expect(canRemove(item(forgotten, .screenshots, detail: "")),
                     "a listed capture can be moved to the Trash")
        suite.expect(!canRemove(item(moved, .screenshots, detail: "")),
                     "a capture outside the top of the screenshot folder is never removed")
        removexattr(forgotten.path, CleanerSupport.screenCaptureAttribute, 0)
        suite.expect(!canRemove(item(forgotten, .screenshots, detail: "")),
                     "a file that no longer proves it is a capture is never removed")
    }

    static func leftovers(in directory: URL, installed: Set<String>, places: JunkCleaner.Places,
                          metadata: Bool = false) -> [Item] {
        var items: [Item] = []
        JunkCleaner.appendLeftovers(in: directory.path, usesContainerMetadata: metadata,
                                    installed: installed, places: places, fm: .default, into: &items)
        return items
    }

    static func checkSupportDirectories(_ suite: TestSuite, home: URL, places: JunkCleaner.Places) throws {
        func canRemove(_ item: Item, installed: Set<String> = []) -> Bool {
            JunkCleaner.mayRemove(item, installed: installed, places: places)
        }
        let manager = FileManager.default
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let battle = support.appendingPathComponent("Battle.net", isDirectory: true)
        try manager.createDirectory(at: battle.appendingPathComponent("Versions", isDirectory: true),
                                    withIntermediateDirectories: true)
        try manager.createDirectory(at: support.appendingPathComponent("Battle.net.plist"),
                                    withIntermediateDirectories: true)
        try Data([1]).write(to: support.appendingPathComponent("maker.com"))

        let other = home.deletingLastPathComponent()
            .appendingPathComponent("another-user/Library/Application Support/Battle.net", isDirectory: true)
        try manager.createDirectory(at: other, withIntermediateDirectories: true)
        let shared = URL(fileURLWithPath: places.systemLibrary, isDirectory: true)
            .appendingPathComponent("Application Support/Battle.net", isDirectory: true)
        try manager.createDirectory(at: shared, withIntermediateDirectories: true)
        let battlePath = battle.resolvingSymlinksInPath().path
        let sharedPath = shared.resolvingSymlinksInPath().path
        let otherPath = other.resolvingSymlinksInPath().path
        let before = JunkCleaner.scanLeftovers(installed: [], places: places)
        suite.expect(!before.contains { $0.url.resolvingSymlinksInPath().path == otherPath }
                     && !canRemove(item(other, detail: "Battle.net")),
                     "another user's support directory is outside the scan and removal roots")
        guard let row = before.first(where: { $0.url.resolvingSymlinksInPath().path == battlePath }),
              let sharedRow = before.first(where: { $0.url.resolvingSymlinksInPath().path == sharedPath }) else {
            suite.expect(false, "unowned support directories in both libraries are offered for review")
            return
        }
        suite.expect([row, sharedRow].allSatisfy { $0.detail == "Battle.net" && !$0.recommended && canRemove($0) },
                     "an uninstalled app's domain directories are optional leftovers")
        let installed: Set<String> = ["net.battle.app", "com.maker"]
        let found = JunkCleaner.scanLeftovers(installed: installed, places: places)
        suite.expect(!found.contains { $0.url.lastPathComponent == "Battle.net" }
                     && !canRemove(row, installed: installed) && !canRemove(sharedRow, installed: installed),
                     "an installed Battle.net is protected in both libraries at scan and after a stale selection")
        suite.expect(Set(found.map { $0.url.lastPathComponent }) == ["Battle.net.plist", "maker.com"]
                     && found.allSatisfy { canRemove($0, installed: installed) },
                     "only the raw name of a support directory establishes reverse ownership")
        // The checks that follow read this Application Support folder too.
        for url in [battle, support.appendingPathComponent("Battle.net.plist"),
                    support.appendingPathComponent("maker.com"), shared] {
            try manager.removeItem(at: url)
        }
    }

    static func checkOrphanedAgents(_ suite: TestSuite, home: URL, places: JunkCleaner.Places) throws {
        let agents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let missingProgram = agents.appendingPathComponent("missing").path
        for label in ["test.editor", "editor.test"] {
            try PropertyListSerialization.data(fromPropertyList: ["Label": label, "Program": missingProgram],
                                               format: .xml, options: 0)
                .write(to: agents.appendingPathComponent(label + ".plist"))
        }
        let found = JunkCleaner.scanOrphanedLaunchPlists(installed: ["editor.test"], places: places)
        suite.expect(found.map(\.detail) == ["test.editor"] && found.allSatisfy(\.recommended),
                     "the orphaned agent is still offered while the installed label stays protected")
    }

    static func run(_ suite: TestSuite) {
        let manager = FileManager.default
        // The home folder sits in a sandbox beside the fixture's shared Library.
        let sandbox = manager.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("vitruvian-cleaner-\(UUID().uuidString)", isDirectory: true)
        let root = sandbox.appendingPathComponent("user", isDirectory: true)
        defer { try? manager.removeItem(at: sandbox) }
        let places = Self.places(home: root)
        func canRemove(_ item: Item, installed: Set<String> = []) -> Bool {
            JunkCleaner.mayRemove(item, installed: installed, places: places)
        }
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            try checkSupportDirectories(suite, home: root, places: places)
            try checkOrphanedAgents(suite, home: root, places: places)
            let installed: Set<String> = ["editor.test"]
            for category in [CleanerSupport.Category.caches, .logs] {
                let dir = root.appendingPathComponent(category == .caches ? "Library/Caches" : "Library/Logs")
                try manager.createDirectory(at: dir, withIntermediateDirectories: true)
                for name in ["logitec.localized", "Vendor.LoCaLiZeD", "com.vendor.editor", "test.editor"] {
                    let folder = dir.appendingPathComponent(name)
                    try manager.createDirectory(at: folder, withIntermediateDirectories: true)
                    try Data(repeating: 1, count: 4096).write(to: folder.appendingPathComponent("data"))
                }
                var scanned: [Item] = []
                JunkCleaner.appendLeftovers(in: dir.path, usesContainerMetadata: false,
                                            installed: [], places: places, fm: manager, into: &scanned)
                let claimed = Set(scanned.map { $0.url.standardizedFileURL.path })
                let found = category == .caches ? JunkCleaner.scanCaches(excluding: claimed, places: places)
                    : JunkCleaner.scanLogs(excluding: claimed, places: places)
                suite.expect(found.isEmpty,
                             "localized folders cannot return as recommended \(category) after leftover scanning")
                let optional = leftovers(in: dir, installed: installed, places: places)
                let optionalClaimed = Set(optional.map { $0.url.standardizedFileURL.path })
                let unclaimed = category == .caches
                    ? JunkCleaner.scanCaches(excluding: optionalClaimed, places: places)
                    : JunkCleaner.scanLogs(excluding: optionalClaimed, places: places)
                suite.expect(optional.contains {
                    $0.detail == "test.editor" && !$0.recommended && canRemove($0, installed: installed)
                } && unclaimed.isEmpty,
                             "a reversed id cannot promote an optional \(category) leftover to scheduled cleanup")
                let normal = category == .caches ? JunkCleaner.scanCaches(excluding: [], places: places)
                    : JunkCleaner.scanLogs(excluding: [], places: places)
                suite.expect(normal.contains { $0.detail == "com.vendor.editor" && $0.recommended },
                             "ordinary \(category) remain recommended")
                for name in ["logitec.localized", "Vendor.LoCaLiZeD"] {
                    suite.expect(!canRemove(item(dir.appendingPathComponent(name), category, detail: name,
                                                 recommended: true)),
                                 "stale recommended \(category) cannot remove \(name)")
                }
            }
            // Leftovers sit directly in one of the Library folders the scan reads.
            let support = root.appendingPathComponent("Library/Application Support", isDirectory: true)
            let preferences = root.appendingPathComponent("Library/Preferences", isDirectory: true)
            let containers = root.appendingPathComponent("Library/Containers", isDirectory: true)
            for folder in [support, preferences, containers] {
                try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            for name in ["logitec.localized", "Logitech.localized", "Vendor.LoCaLiZeD",
                         "com.vendor.editor.localized"] {
                let folder = support.appendingPathComponent(name, isDirectory: true)
                try manager.createDirectory(at: folder, withIntermediateDirectories: false)
                suite.expect(owner(folder) == nil,
                             "localized directory \(name) is not offered as an app leftover")
                suite.expect(!canRemove(item(folder, detail: name)),
                             "a previously listed localized directory \(name) cannot be removed")
            }

            for id in ["com.vendor.editor", "com.vendor.localized.editor", "com.vendor.localized", "io.app"] {
                let preference = preferences.appendingPathComponent(id + ".plist")
                try Data().write(to: preference)
                suite.expect(owner(preference) == id,
                             "a real preference file retains its exact owner \(id)")
                suite.expect(canRemove(item(preference, detail: id)),
                             "an unowned preference for \(id) remains eligible after scanning")
                suite.expect(!canRemove(item(preference, detail: id), installed: [id]),
                             "preferences for an installed owner \(id) remain protected")
            }
            let reversed = preferences.appendingPathComponent("test.editor.plist")
            try Data().write(to: reversed)
            suite.expect(canRemove(item(reversed, detail: "test.editor"), installed: installed),
                         "an installed reversed id does not protect an unrelated preference")

            let container = containers.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try manager.createDirectory(at: container, withIntermediateDirectories: false)
            try PropertyListSerialization.data(fromPropertyList: [
                "MCMMetadataIdentifier": "com.vendor.localized",
            ], format: .xml, options: 0).write(to: container.appendingPathComponent(
                ".com.apple.containermanagerd.metadata.plist"))
            suite.expect(owner(container, metadata: true) == "com.vendor.localized"
                         && canRemove(item(container, detail: "com.vendor.localized")),
                         "container metadata remains an identifier rather than a directory name")
            for id in ["test.editor", "editor.test"] {
                let owned = containers.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try manager.createDirectory(at: owned, withIntermediateDirectories: false)
                try PropertyListSerialization.data(fromPropertyList: ["MCMMetadataIdentifier": id],
                                                   format: .xml, options: 0)
                    .write(to: owned.appendingPathComponent(".com.apple.containermanagerd.metadata.plist"))
            }
            let contained = leftovers(in: containers, installed: installed, places: places, metadata: true)
            suite.expect(Set(contained.map(\.detail)) == ["com.vendor.localized", "test.editor"]
                         && contained.allSatisfy { canRemove($0, installed: installed) },
                         "container metadata protects the actual owner and keeps unrelated leftovers eligible")

            runScreenshotRules(suite)
            try runScreenshotScan(suite, root: root)
        } catch {
            suite.expect(false, "cleaner eligibility fixture failed: \(error)")
        }
    }
}
