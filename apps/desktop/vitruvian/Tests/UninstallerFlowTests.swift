// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The production uninstaller and the command bar's uninstall review run with
/// recorded scans, removals and package-manager calls on a manual queue.
/// Files are disposable bundles; no installed apps, Homebrew or Trash are used.
enum UninstallerFlowTests {
    /// Background work and main-queue handoffs wait here until drained, in
    /// the order they were queued. Only the test's own thread touches it.
    nonisolated final class Queue: @unchecked Sendable {
        var pending: [() -> Void] = []
        func drain() {
            while !pending.isEmpty { pending.removeFirst()() }
        }
        /// Runs only the oldest waiting work.
        func step() {
            if !pending.isEmpty { pending.removeFirst()() }
        }
    }

    /// The disk as the scan and the removal see it: every app leaves itself
    /// and one support folder, and a removal frees what it was given unless
    /// told to fail. Only the test's own thread touches it.
    nonisolated final class Disk: @unchecked Sendable {
        static let appSize: Int64 = 10
        static let supportSize: Int64 = 5
        var scans = 0
        var failing = false
        var removals: [AppUninstaller.Removal] = []
        var onScan: (@MainActor () -> Void)?

        func leftovers(_ scan: AppUninstaller.Scan) -> [AppUninstaller.Leftover]? {
            scans += 1
            // The manual queue runs this on the test's thread.
            MainActor.assumeIsolated { onScan?() }
            guard let identity = UninstallerSupport.fileIdentity(at: scan.appURL) else { return [] }
            let support = scan.appURL.deletingLastPathComponent()
                .appendingPathComponent(scan.bundleID, isDirectory: true)
            return [
                AppUninstaller.Leftover(url: scan.appURL, category: .app, size: Self.appSize,
                                        ownerBundleID: scan.bundleID, ownerGroupID: nil,
                                        evidenceBundleID: nil, confidence: .exact,
                                        fileIdentity: identity),
                AppUninstaller.Leftover(url: support, category: .support, size: Self.supportSize,
                                        ownerBundleID: scan.bundleID, ownerGroupID: nil,
                                        evidenceBundleID: nil, confidence: .exact,
                                        fileIdentity: .init(device: 0, inode: 1)),
            ]
        }

        func remove(_ removal: AppUninstaller.Removal) -> (freed: Int64, failed: [AppUninstaller.Leftover]) {
            removals.append(removal)
            if failing { return (removal.alreadyFreed, removal.chosen) }
            return (removal.chosen.reduce(removal.alreadyFreed) { $0 + $1.size }, [])
        }
    }

    /// Homebrew as the uninstaller sees it. Clearing the log forgets a
    /// finished status the way the real manager does when it is idle.
    final class Brew: AppUninstaller.PackageManager {
        var operation: HomebrewOperation?
        let statuses = CurrentValueSubject<HomebrewOperationStatus?, Never>(nil)
        var operationStatus: HomebrewOperationStatus? { statuses.value }
        var operationStatuses: AnyPublisher<HomebrewOperationStatus?, Never> { statuses.eraseToAnyPublisher() }
        var lookup: ((HomebrewPackage?) -> Void)?
        var uninstalled: [String] = []

        func packageManagingApplication(at url: URL, completion: @escaping (HomebrewPackage?) -> Void) {
            lookup = completion
        }
        func clearLog() {
            if operation == nil { statuses.send(nil) }
        }
        func uninstall(_ package: HomebrewPackage) { uninstalled.append(package.name) }
        func publish(_ result: HomebrewOperationResult, for package: HomebrewPackage) {
            statuses.send(HomebrewOperationStatus(action: .uninstall, package: package, phase: .uninstalling,
                                                  result: result, startedAt: Date()))
        }
    }

    /// What the uninstaller quit and announced.
    final class Record {
        var quits: [URL] = []
        var hud: [String] = []
        /// Apps whose Command Bar shortcut a finished removal released.
        var released: [String] = []
    }

    /// The bar's field and rows as the review moves them, with the field's
    /// own rule: a changed query tells the review first.
    final class Bar {
        var mode: CommandBarService.Mode = .search
        var savedQuery = ""
        var warning: String?
        var available = true
        var forgotten: [URL] = []
        /// Each return to search, with the query it asked for (nil: the kept one).
        var returns: [String?] = []
        var review: CommandBarUninstallReview?
        var query = "" {
            didSet {
                guard query != oldValue else { return }
                review?.queryChanged()
            }
        }

        func host(defaults: UserDefaults) -> CommandBarUninstallReview.Host {
            .init(isAvailable: { [unowned self] in self.available },
                  defaults: defaults,
                  mode: { [unowned self] in self.mode },
                  setMode: { [unowned self] in self.mode = $0 },
                  saveQuery: { [unowned self] in self.savedQuery = self.query },
                  returnToSearch: { [unowned self] query in
                      self.returns.append(query)
                      self.mode = .search
                      self.query = query ?? self.savedQuery
                  },
                  setWarning: { [unowned self] in self.warning = $0 },
                  refreshPanelLayout: {},
                  forget: { [unowned self] in self.forgotten.append($0) })
        }
    }

    /// Finder's consent and its selection script. Only the test's own thread
    /// touches it.
    nonisolated final class Script: @unchecked Sendable {
        var status = Permissions.AutomationStatus.undetermined
        var ok = true
        var requests = 0
        var reads = 0
        var automation: FinderBridge.Automation {
            FinderBridge.Automation(
                consent: { _ in
                    self.requests += 1
                    return self.status == .granted
                },
                status: { self.status },
                run: { _ in
                    self.reads += 1
                    return self.ok ? (true, "/Applications/Fixture.app\n") : (false, "Finder got an error.")
                })
        }
    }

    static func run(_ suite: TestSuite) {
        finderConsent(suite)
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("uninstaller-flow-\(UUID())")
        let suiteName = "vitru.tests.uninstaller-flow-\(UUID())"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            suite.expect(false, "a scratch defaults suite opens")
            return
        }
        defaults.set(true, forKey: DefaultsKey.uninstallerCommandBarEnabled)
        let queue = Queue()
        let disk = Disk()
        let brew = Brew()
        let record = Record()
        let uninstaller = AppUninstaller(environment: .init(
            background: { _, work in queue.pending.append(work) },
            main: { work in queue.pending.append { MainActor.assumeIsolated { work() } } },
            scan: { disk.leftovers($0) },
            remove: { disk.remove($0) },
            quit: { record.quits.append($0) },
            packages: brew,
            notify: { _, message in record.hud.append(message) },
            releaseShortcut: { app, bundleID in record.released.append("\(app.path) \(bundleID ?? "-")") }))
        let bar = Bar()
        let review = CommandBarUninstallReview(uninstaller: uninstaller, host: bar.host(defaults: defaults))
        bar.review = review
        let text = L10n.shared.s
        defer {
            queue.pending = []
            disk.onScan = nil
            bar.review = nil
            defaults.removePersistentDomain(forName: suiteName)
            try? fm.removeItem(at: root)
        }
        func makeApp(_ name: String) throws -> URL {
            let url = root.appendingPathComponent(name + ".app", isDirectory: true)
            let contents = url.appendingPathComponent("Contents", isDirectory: true)
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            try writeInfo(name, to: contents.appendingPathComponent("Info.plist"))
            return url
        }
        /// Atomic, so the rewritten file is a different file to the identity check.
        func writeInfo(_ name: String, to url: URL) throws {
            let data = try PropertyListSerialization.data(fromPropertyList: [
                "CFBundleIdentifier": "org.vitruvian.fixture.\(name)",
                "CFBundlePackageType": "APPL", "CFBundleName": name,
            ], format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
        }
        do {
            let a = try makeApp("First")
            let b = try makeApp("Second")
            let first = HomebrewPackage(kind: .cask, name: "first", displayName: "First")

            // Scanning, and every way a scan can be overtaken.
            bar.query = "First"
            review.begin(appURL: a, entryID: "a")
            suite.expect(bar.mode == .uninstallReview(entryID: "a") && bar.savedQuery == "First"
                         && bar.warning == nil && uninstaller.phase == .scanning && uninstaller.target?.url == a,
                         "accepted selection opens its review")
            queue.drain()
            let lateScan = brew.lookup
            review.stepBack()
            lateScan?(nil)
            suite.expect(lateScan != nil && uninstaller.phase == .empty && uninstaller.target == nil
                         && bar.mode == .search && bar.query == "First" && bar.returns == [nil],
                         "canceling while scanning prevents its late result from returning")
            disk.scans = 0
            _ = uninstaller.select(appURL: a)
            uninstaller.reset()
            queue.drain()
            suite.expect(disk.scans == 0 && uninstaller.phase == .empty,
                         "canceling a scan stops its background work instead of letting it run to the end")
            brew.lookup = nil
            disk.onScan = { uninstaller.reset() }
            _ = uninstaller.select(appURL: a)
            queue.drain()
            disk.onScan = nil
            suite.expect(disk.scans == 1 && brew.lookup == nil && uninstaller.phase == .empty,
                         "a scan canceled while it runs delivers nothing")
            disk.scans = 0
            _ = uninstaller.select(appURL: a)
            _ = uninstaller.select(appURL: a)
            queue.drain()
            suite.expect(disk.scans == 1 && brew.lookup != nil,
                         "a new selection supersedes a scan still running, even of the same app")
            uninstaller.reset()
            brew.lookup = nil
            disk.onScan = { _ = uninstaller.select(appURL: a) }
            _ = uninstaller.select(appURL: a)
            queue.step()
            disk.onScan = nil
            suite.expect(queue.pending.count == 1, "a scan superseded while it runs hands nothing back")
            uninstaller.reset()
            queue.pending = []
            _ = uninstaller.select(appURL: a)
            queue.step()
            _ = uninstaller.select(appURL: a)
            queue.step()
            suite.expect(brew.lookup == nil, "a scan superseded on its way back asks for no package")
            uninstaller.reset()
            queue.pending = []
            _ = uninstaller.select(appURL: a)
            queue.drain()
            let canceledScan = brew.lookup
            uninstaller.reset()
            _ = uninstaller.select(appURL: a)
            canceledScan?(nil)
            suite.expect(uninstaller.phase == .scanning && uninstaller.items.isEmpty,
                         "a canceled scan cannot deliver into a new scan of the same app")
            uninstaller.reset()
            queue.pending = []
            brew.lookup = nil
            _ = uninstaller.select(appURL: b)
            try writeInfo("Second", to: b.appendingPathComponent("Contents/Info.plist"))
            queue.drain()
            suite.expect(brew.lookup == nil && uninstaller.phase == .empty && uninstaller.target == nil,
                         "a bundle replaced while it was scanned is dropped before its package is asked")
            _ = uninstaller.select(appURL: b)
            queue.drain()
            try writeInfo("Second", to: b.appendingPathComponent("Contents/Info.plist"))
            brew.lookup?(nil)
            suite.expect(uninstaller.phase == .empty && uninstaller.target == nil,
                         "a bundle replaced while its package was asked is dropped")
            review.begin(appURL: a, entryID: "a")
            queue.drain()
            brew.lookup?(nil)
            suite.expect(uninstaller.phase == .results && uninstaller.items.map(\.url).first == a
                         && uninstaller.items.count == 2 && uninstaller.homebrewRemovalConfirmation == nil,
                         "current scan delivers the accepted app")

            // A plain removal, and what it holds on to while it runs.
            for key in [kVK_Tab, kVK_Space, kVK_UpArrow, kVK_DownArrow] {
                suite.expect(!review.handleKey(key, searchFieldFocused: false)
                             && !review.handleKey(key, searchFieldFocused: true),
                             "checklist key \(key) reaches the native control")
            }
            suite.expect(!review.handleKey(kVK_Return, searchFieldFocused: false) && uninstaller.phase == .results,
                         "Return on a focused control cannot submit removal instead")
            suite.expect(review.handleKey(kVK_Return, searchFieldFocused: true) && uninstaller.phase == .removing
                         && record.quits == [a],
                         "Return in the search field retains the review action, quitting the app before it moves")
            let originalItems = uninstaller.items
            review.stepBack()
            review.begin(appURL: b, entryID: "b")
            suite.expect(bar.mode == .search && bar.warning == text.uninstallerRemoving
                         && uninstaller.target?.url == a && uninstaller.items == originalItems,
                         "choosing another app after leaving a removal preserves the active operation")
            uninstaller.reset()
            review.close()
            suite.expect(uninstaller.phase == .removing && uninstaller.target?.url == a,
                         "other surfaces cannot reset an active plain removal")
            uninstaller.setInclude(false, for: originalItems[0].id)
            suite.expect(uninstaller.items == originalItems, "an active removal keeps its captured selection")
            suite.expect(record.released.isEmpty, "an app's shortcut stays while its removal is still running")
            queue.drain()
            suite.expect(uninstaller.phase == .done(freed: Disk.appSize + Disk.supportSize, failed: [])
                         && disk.removals.last?.chosen == originalItems && disk.removals.last?.targetURL == a
                         && disk.removals.last?.packageRemovedApplication == false,
                         "a removal takes the rows it captured and reports what it freed")
            suite.expect(record.released == ["\(a.path) org.vitruvian.fixture.First"],
                         "a finished removal releases the removed app's Command Bar shortcut, once")
            uninstaller.reset()
            suite.expect(uninstaller.phase == .empty && uninstaller.target == nil,
                         "a finished operation can be dismissed normally")

            // A package-managed app: its confirmation, and its cleanup.
            review.begin(appURL: a, entryID: "a")
            queue.drain()
            brew.lookup?(first)
            suite.expect(uninstaller.phase == .results && uninstaller.selectedHomebrewPackage == first,
                         "a Homebrew-managed app offers its package")
            suite.expect(bar.warning == nil, "an accepted row clears the last refusal")
            let other = HomebrewPackage(kind: .cask, name: "other", displayName: "Other")
            brew.statuses.send(HomebrewOperationStatus(action: .upgrade, package: first, phase: .upgrading,
                                                       result: .running, startedAt: Date()))
            let upgrading = uninstaller.isRemoving
            brew.publish(.running, for: other)
            suite.expect(!upgrading && !uninstaller.isRemoving,
                         "only the package's own removal counts as removing the app")
            if let app = uninstaller.items.first(where: { $0.category == .app }) {
                uninstaller.setInclude(false, for: app.id)
                suite.expect(uninstaller.selectedHomebrewPackage == nil
                             && uninstaller.homebrewRemovalConfirmation == nil,
                             "unchecking the app leaves its package out")
                uninstaller.setInclude(true, for: app.id)
            }
            brew.publish(.succeeded, for: first)
            review.submit()
            suite.expect(bar.mode == .uninstallHomebrewConfirm(entryID: "a") && brew.uninstalled.isEmpty,
                         "a Homebrew-managed app asks for its own confirmation first")
            suite.expect(review.handleKey(kVK_Escape, searchFieldFocused: false)
                         && bar.mode == .uninstallReview(entryID: "a") && uninstaller.phase == .results,
                         "Escape cancels just the package confirmation")
            review.submit()
            suite.expect(review.handleKey(kVK_ANSI_KeypadEnter, searchFieldFocused: true)
                         && brew.uninstalled == ["first"] && bar.mode == .uninstallReview(entryID: "a"),
                         "confirming runs the package removal and returns to its checklist")
            suite.expect(uninstaller.phase == .results,
                         "a finished status from an earlier operation is not read as this removal's result")
            brew.publish(.succeeded, for: other)
            brew.publish(.failed, for: first)
            suite.expect(uninstaller.phase == .results && uninstaller.homebrewPackage == first,
                         "another package's removal, or this one failing, leaves the checklist as it was")
            review.submit()
            review.submit()
            brew.publish(.running, for: first)
            review.begin(appURL: b, entryID: "b")
            uninstaller.reset()
            review.close()
            suite.expect(uninstaller.isRemoving && uninstaller.target?.url == a
                         && uninstaller.homebrewPackage == first && uninstaller.homebrewRemovalConfirmation == nil
                         && bar.warning == text.uninstallerRemoving,
                         "a new selection or reset cannot discard package cleanup in progress")
            record.quits = []
            brew.publish(.succeeded, for: first)
            suite.expect(uninstaller.phase == .removing && uninstaller.homebrewPackage == nil
                         && record.quits == [a],
                         "a package removal that left its app hands the rest of the removal on")
            queue.drain()
            suite.expect(disk.removals.last?.chosen.map(\.category) == [.app, .support]
                         && disk.removals.last?.packageRemovedApplication == true
                         && disk.removals.last?.alreadyFreed == 0,
                         "the app the package left is trashed with the rest and counted once")
            uninstaller.reset()

            review.begin(appURL: a, entryID: "a")
            queue.drain()
            brew.lookup?(first)
            if let confirmation = uninstaller.homebrewRemovalConfirmation,
               let support = uninstaller.items.first(where: { $0.category == .support }) {
                let second = HomebrewPackage(kind: .cask, name: "second", displayName: "Second")
                record.hud = []
                brew.uninstalled = []
                uninstaller.setInclude(false, for: support.id)
                uninstaller.removeSelectedWithHomebrew(confirmation: confirmation)
                uninstaller.setInclude(true, for: support.id)
                uninstaller.removeSelectedWithHomebrew(confirmation: .init(
                    package: second, targetURL: a, selectedIDs: confirmation.selectedIDs))
                uninstaller.removeSelectedWithHomebrew(confirmation: .init(
                    package: first, targetURL: b, selectedIDs: confirmation.selectedIDs))
                suite.expect(brew.uninstalled.isEmpty && record.hud == Array(repeating: text.uninstallerConfirmationExpired, count: 3),
                             "a Homebrew confirmation for other rows, another package or another app runs nothing, found \(brew.uninstalled)")
                brew.operation = HomebrewOperation(action: .install, package: nil)
                uninstaller.removeSelectedWithHomebrew(confirmation: confirmation)
                brew.operation = nil
                suite.expect(brew.uninstalled.isEmpty && record.hud.count == 3,
                             "another package operation still running starts nothing")
                uninstaller.removeSelectedWithHomebrew(confirmation: confirmation)
                suite.expect(brew.uninstalled == ["first"], "an unchanged Homebrew confirmation runs its package")
                try fm.removeItem(at: a)
                brew.publish(.succeeded, for: first)
                queue.drain()
                suite.expect(disk.removals.last?.chosen.map(\.category) == [.support]
                             && disk.removals.last?.alreadyFreed == Disk.appSize
                             && uninstaller.phase == .done(freed: Disk.appSize + Disk.supportSize, failed: []),
                             "a package removal that took its app trashes only the rest and counts the app once")
            } else {
                suite.expect(false, "a Homebrew-managed app offers a package confirmation")
            }
            // Leave the finished review the way a person would.
            review.stepBack()
            bar.forgotten = []
            uninstaller.reset()

            // Rejections and every way out of the review.
            review.begin(appURL: root.appendingPathComponent("Missing.app"), entryID: "missing")
            suite.expect(bar.mode == .search && bar.warning == text.uninstallerSelectionUnavailable,
                         "a vanished application reports rejection without opening an empty review")
            let link = root.appendingPathComponent("Link.app")
            try fm.createSymbolicLink(at: link, withDestinationURL: b)
            suite.expect(!uninstaller.select(appURL: link), "a symlink cannot be accepted as a removable bundle")
            defaults.set(false, forKey: DefaultsKey.uninstallerCommandBarEnabled)
            review.begin(appURL: b, entryID: "b")
            suite.expect(bar.mode == .search && uninstaller.phase == .empty,
                         "disabling the toggle rejects a previously offered row")
            defaults.set(true, forKey: DefaultsKey.uninstallerCommandBarEnabled)
            bar.available = false
            review.begin(appURL: b, entryID: "b")
            suite.expect(bar.mode == .search && uninstaller.phase == .empty,
                         "uninstalling the feature rejects a previously offered row")
            bar.available = true
            bar.query = "Sec"
            suite.expect(bar.warning == nil, "typing clears a refusal")
            review.begin(appURL: b, entryID: "b")
            review.finderRequestID = UUID()
            review.close()
            suite.expect(uninstaller.phase == .empty && uninstaller.target == nil && review.finderRequestID == nil,
                         "closing the bar mid-review leaves no checklist or Finder request behind")
            // The bar closes on search.
            bar.mode = .search
            _ = uninstaller.select(appURL: b)
            review.close()
            suite.expect(uninstaller.phase == .scanning && uninstaller.target?.url == b,
                         "closing the bar leaves a selection made elsewhere alone")
            uninstaller.reset()
            review.begin(appURL: b, entryID: "b")
            queue.drain()
            brew.lookup?(first)
            review.submit()
            review.finderRequestID = UUID()
            bar.query = "A new search"
            suite.expect(bar.mode == .search && uninstaller.phase == .empty && bar.query == "A new search"
                         && bar.warning == nil,
                         "typing or pasting a new query leaves both uninstall steps and preserves that query")
            suite.expect(review.finderRequestID == nil, "new search cancels a pending explicit Finder action")

            // Finishing: what leaves the lists and what stays.
            bar.query = "Second"
            review.begin(appURL: b, entryID: "b")
            queue.drain()
            brew.lookup?(nil)
            disk.failing = true
            review.submit()
            queue.drain()
            review.submit()
            suite.expect(bar.forgotten.isEmpty && bar.mode == .search && bar.query.isEmpty
                         && uninstaller.phase == .empty,
                         "failed removals keep the still-installed app in both lists")
            disk.failing = false
            review.begin(appURL: b, entryID: "b")
            queue.drain()
            brew.lookup?(nil)
            review.submit()
            queue.drain()
            try fm.removeItem(at: b)
            review.stepBack()
            suite.expect(bar.forgotten == [b] && bar.mode == .search && bar.query.isEmpty
                         && uninstaller.phase == .empty,
                         "a confirmed removal disappears from the browse list and Finder shortcut")
            suite.expect(Defaults.registeredDefaults[DefaultsKey.uninstallerCommandBarEnabled] as? Bool == false,
                         "the integration starts off")
            suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.uninstallerCommandBarEnabled),
                         "backup includes the command-bar preference")
        } catch {
            suite.expect(false, "uninstaller fixture failed: \(error)")
        }
    }

    /// Finder's selection is read only with consent already given; only an
    /// explicit action may ask for it.
    private static func finderConsent(_ suite: TestSuite) {
        let script = Script()
        for status in [Permissions.AutomationStatus.undetermined, .denied, .notDeterminable] {
            script.status = status
            suite.expect(FinderBridge.selectionURLs(requestPermission: false, automation: script.automation).isEmpty
                         && script.requests == 0 && script.reads == 0,
                         "passive Finder lookup never asks for missing consent")
        }
        script.status = .granted
        suite.expect(FinderBridge.selectionURLs(requestPermission: false, automation: script.automation)
                         == [URL(fileURLWithPath: "/Applications/Fixture.app")]
                     && script.requests == 0 && script.reads == 1,
                     "existing Finder permission allows the contextual selection")
        _ = FinderBridge.selectionURLs(requestPermission: true, automation: script.automation)
        suite.expect(script.requests == 1 && script.reads == 2, "explicit Finder action is the consent boundary")
        script.status = .denied
        _ = FinderBridge.selectionURLs(requestPermission: true, automation: script.automation)
        suite.expect(script.requests == 2 && script.reads == 2, "a refused explicit request reads nothing")
        script.status = .granted
        script.ok = false
        suite.expect(FinderBridge.selectionURLs(requestPermission: false, automation: script.automation).isEmpty,
                     "a failed Finder read selects nothing, not its error text")
    }
}
