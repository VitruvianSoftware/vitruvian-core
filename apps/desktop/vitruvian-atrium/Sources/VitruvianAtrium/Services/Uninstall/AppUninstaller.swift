// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreServices
import Darwin
import Security
import VitruvianAtriumCore
import VitruvianAtriumDesign

/// Finds the files an app leaves around — caches, preferences, logs, support
/// folders, containers, preference panes, plugins — and removes only what you
/// pick. Ordinary files go to the Trash; after an extra confirmation, a
/// package-managed app is delegated to its package manager before the remaining
/// choices go to the Trash.
@MainActor
package final class AppUninstaller: ObservableObject {
    package static let shared = AppUninstaller()

    package enum Phase: Equatable {
        case empty
        case scanning
        case results
        case removing
        case done(freed: Int64, failed: [Leftover])
    }

    package struct Target: Equatable {
        package let name: String
        package let bundleID: String?
        package let url: URL
        package let icon: NSImage

        package static func == (lhs: Target, rhs: Target) -> Bool { lhs.url == rhs.url }

        // Spelled out because a memberwise initializer never leaves its module.
        package init(name: String, bundleID: String?, url: URL, icon: NSImage) {
            self.name = name
            self.bundleID = bundleID
            self.url = url
            self.icon = icon
        }
    }

    package enum Category: Int, CaseIterable {
        case app, support, caches, preferences, containers, logs, state, other

        package var sortRank: Int { rawValue }
    }

    package struct Leftover: Identifiable, Equatable {
        package let id = UUID()
        package let url: URL
        package let category: Category
        package let size: Int64
        package let ownerBundleID: String?
        package let ownerGroupID: String?
        package let evidenceBundleID: String?
        package let confidence: UninstallerSupport.LeftoverMatch
        package let fileIdentity: UninstallerSupport.FileIdentity
        package var include: Bool = true

        package var name: String { url.lastPathComponent }

        package static func == (lhs: Leftover, rhs: Leftover) -> Bool {
            lhs.id == rhs.id && lhs.include == rhs.include
        }

        // Spelled out because a memberwise initializer never leaves its module.
        package init(url: URL, category: Category, size: Int64, ownerBundleID: String?, ownerGroupID: String?, evidenceBundleID: String?, confidence: UninstallerSupport.LeftoverMatch, fileIdentity: UninstallerSupport.FileIdentity, include: Bool = true) {
            self.url = url
            self.category = category
            self.size = size
            self.ownerBundleID = ownerBundleID
            self.ownerGroupID = ownerGroupID
            self.evidenceBundleID = evidenceBundleID
            self.confidence = confidence
            self.fileIdentity = fileIdentity
            self.include = include
        }
    }

    @Published package private(set) var phase: Phase = .empty
    @Published package private(set) var target: Target?
    @Published package private(set) var homebrewPackage: HomebrewPackage?
    @Published package private(set) var homebrewCheckFailed = false
    /// The app the last selection turned down, so the empty state can say
    /// why instead of springing back in silence (#1582). An accepted
    /// selection or a reset clears it.
    @Published package private(set) var refusal: UninstallerSupport.RefusedApp?
    @Published package var items: [Leftover] = []
    private var allowedRemovalPaths = Set<String>()
    private var targetSelection: UninstallerSupport.Selection?
    private var targetTrashMove: UninstallerSupport.TrashMove?
    private var homebrewRemovalSize: Int64 = 0
    private var homebrewRemovedApplication = false
    private var homebrewRemovalObservation: AnyCancellable?
    private var scanCancellation: UninstallerSupport.ScanCancellation?

    private struct ScanCandidate {
        let url: URL
        let category: Category
        let ownerBundleID: String?
        let ownerGroupID: String?
        let evidenceBundleID: String?
        let confidence: UninstallerSupport.LeftoverMatch
        var include: Bool
    }

    /// The package manager calls the uninstaller makes, so a package-managed
    /// removal can be driven without Homebrew.
    @MainActor
    package protocol PackageManager: AnyObject {
        var operation: HomebrewOperation? { get }
        var operationStatus: HomebrewOperationStatus? { get }
        var operationStatuses: AnyPublisher<HomebrewOperationStatus?, Never> { get }
        func packageManagingApplication(at url: URL,
                                        completion: @escaping (Result<HomebrewPackage?, HomebrewOwnershipError>) -> Void)
        /// `fromUninstaller` marks the run as this window's, so its log can
        /// be reopened from the uninstaller once its card has closed.
        func uninstall(_ package: HomebrewPackage, fromUninstaller: Bool)
    }

    /// What a scan reads, captured on the main thread before it leaves.
    package struct Scan: Sendable {
        package let appURL: URL
        package let bundleID: String
        /// A witnessed move from an Applications folder to the Trash stands in
        /// for the install root the app no longer sits in, so its data can
        /// still be found.
        package let fromTrashMove: Bool
        package let cancellation: UninstallerSupport.ScanCancellation

        // Spelled out because a memberwise initializer never leaves its module.
        package init(appURL: URL, bundleID: String, fromTrashMove: Bool = false,
                     cancellation: UninstallerSupport.ScanCancellation) {
            self.appURL = appURL
            self.bundleID = bundleID
            self.fromTrashMove = fromTrashMove
            self.cancellation = cancellation
        }
    }

    /// The two answers one scan waits for: the leftovers it found and what
    /// the package manager says about the app. Written on the main thread
    /// only, by whichever of the two finishes first.
    private final class ScanAnswers: @unchecked Sendable {
        var leftovers: [Leftover]?
        var ownership: Result<HomebrewPackage?, HomebrewOwnershipError>?
    }

    /// What a removal takes with it off the main thread: the chosen rows and
    /// the proofs that what they point at is still what was scanned.
    package struct Removal: Sendable {
        package let chosen: [Leftover]
        package let allowedPaths: Set<String>
        /// The app as it was taken, with the proofs that what is on disk is
        /// still it: every row is removed only while they still hold.
        package let selection: UninstallerSupport.Selection
        /// The witnessed move to the Trash this cleanup belongs to, if any.
        package let trashMove: UninstallerSupport.TrashMove?
        package let alreadyFreed: Int64
        package let packageRemovedApplication: Bool

        package var targetURL: URL { selection.url }
        package var targetBundleID: String { selection.bundleID }

        // Spelled out because a memberwise initializer never leaves its module.
        package init(chosen: [Leftover], allowedPaths: Set<String>,
                     selection: UninstallerSupport.Selection,
                     trashMove: UninstallerSupport.TrashMove? = nil,
                     alreadyFreed: Int64, packageRemovedApplication: Bool) {
            self.chosen = chosen
            self.allowedPaths = allowedPaths
            self.selection = selection
            self.trashMove = trashMove
            self.alreadyFreed = alreadyFreed
            self.packageRemovedApplication = packageRemovedApplication
        }
    }

    /// Everything the uninstaller reaches outside itself: the threads its
    /// scan and removal run on, the disk work itself, the apps it quits, the
    /// package manager and the HUD. `live` is the Mac; a test hands in its
    /// own, so every transition runs without reading the disk or the Trash.
    package struct Environment {
        /// Runs scan or removal work off the main thread, after `delay`.
        package var background: @Sendable (_ delay: TimeInterval, _ work: @escaping @Sendable () -> Void) -> Void
        /// Brings a background result back to the main thread.
        package var main: @Sendable (_ work: @escaping @MainActor @Sendable () -> Void) -> Void
        /// Finds an app's leftovers; nil once its scan is cancelled.
        package var scan: @Sendable (Scan) -> [Leftover]?
        /// Trashes the chosen rows and reports what went and what stayed.
        package var remove: @Sendable (Removal) -> (freed: Int64, failed: [Leftover])
        /// Quits the app, and every app embedded in it, before the bundle moves.
        package var quit: (_ bundle: URL) -> Void
        package var packages: any PackageManager
        package var notify: (_ icon: String, _ message: String) -> Void
        /// Clears the Command Bar state of an app the removal took away: its
        /// shortcut, name, pin, hidden row and use.
        package var removeCommandBarState: @MainActor (_ app: URL, _ bundleID: String?) -> Void
        /// Asks before cleaning up after an app Finder moved to the Trash,
        /// since the move has no author: an update moves an app there too.
        /// `live` runs the uninstaller's alert; a test answers it.
        package var confirmTrashCleanup: @MainActor (_ appName: String) -> Bool

        // Spelled out because a memberwise initializer never leaves its module.
        package init(background: @escaping @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void,
                     main: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
                     scan: @escaping @Sendable (Scan) -> [Leftover]?,
                     remove: @escaping @Sendable (Removal) -> (freed: Int64, failed: [Leftover]),
                     quit: @escaping (URL) -> Void,
                     packages: any PackageManager,
                     notify: @escaping (String, String) -> Void,
                     removeCommandBarState: @escaping @MainActor (URL, String?) -> Void = { _, _ in },
                     confirmTrashCleanup: @escaping @MainActor (String) -> Bool = { _ in false }) {
            self.background = background
            self.main = main
            self.scan = scan
            self.remove = remove
            self.quit = quit
            self.packages = packages
            self.notify = notify
            self.removeCommandBarState = removeCommandBarState
            self.confirmTrashCleanup = confirmTrashCleanup
        }

        /// Main-actor: it hands over the shared package manager.
        @MainActor package static var live: Environment {
            Environment(
                background: { delay, work in
                    let queue = DispatchQueue.global(qos: .userInitiated)
                    if delay > 0 {
                        queue.asyncAfter(deadline: .now() + delay, execute: work)
                    } else {
                        queue.async(execute: work)
                    }
                },
                main: { work in DispatchQueue.main.async { work() } },
                scan: { AppUninstaller.scan($0) },
                remove: { AppUninstaller.remove($0) },
                quit: { targetURL in
                    for app in NSWorkspace.shared.runningApplications where
                        app.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == targetURL
                        || UninstallerSupport.isNestedBundle(app.bundleURL, in: targetURL) {
                        app.terminate()
                    }
                },
                packages: HomebrewManager.shared,
                notify: { QuickToolHUD.show(icon: $0, message: $1) },
                removeCommandBarState: { AppUninstaller.removeCommandBarState(ofRemovedAppAt: $0, bundleID: $1) },
                confirmTrashCleanup: { appName in
                    let alert = NSAlert()
                    alert.messageText = appName
                    alert.informativeText = L10n.shared.s.uninstallerConfirmTrashCleanup
                    alert.addButton(withTitle: L10n.shared.s.uninstallerCancel)
                    alert.addButton(withTitle: L10n.shared.s.uninstallerRemove)
                    return alert.runModal() == .alertSecondButtonReturn
                })
        }
    }

    private let environment: Environment

    package init(environment: Environment = .live) {
        self.environment = environment
    }

    package var selectedSize: Int64 { items.filter(\.include).reduce(0) { $0 + $1.size } }
    package var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    package var selectedHomebrewPackage: HomebrewPackage? {
        guard items.contains(where: { $0.category == .app && $0.include }) else { return nil }
        return homebrewPackage
    }
    package var isRemovingWithHomebrew: Bool {
        guard let package = selectedHomebrewPackage,
              let status = environment.packages.operationStatus else { return false }
        return status.action == .uninstall
            && status.package?.id == package.id
            && status.isActive
    }

    /// An unsolicited offer must not replace a checklist the person is using.
    package func canOfferTrashCleanup(of move: UninstallerSupport.TrashMove) -> Bool {
        switch phase {
        case .empty, .done:
            return targetSelection?.identity != move.selection.identity && Self.trashMoveIsCurrent(move)
        case .scanning, .results, .removing:
            return false
        }
    }

    /// Read from the removal lane as well as the main thread; it asks
    /// Launch Services and the running apps, neither of which is main-only.
    nonisolated
    private static func trashMoveIsCurrent(_ move: UninstallerSupport.TrashMove) -> Bool {
        let id = move.selection.bundleID
        return move.isLastCopy(registered: NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id),
                               running: !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty,
                               home: FileManager.default.homeDirectoryForCurrentUser)
    }

    package var isRemoving: Bool {
        phase == .removing || isRemovingWithHomebrew
    }

    package var canRemoveSelected: Bool {
        phase == .results && !isRemoving && !homebrewCheckFailed
            && items.contains(where: \.include)
    }

    /// What the Homebrew confirmation showed, since the panel, Settings and the
    /// command bar share this uninstaller and can change it while it is open.
    package struct HomebrewRemovalConfirmation {
        package let package: HomebrewPackage
        package let targetURL: URL
        package let selectedIDs: Set<UUID>

        // Spelled out because a memberwise initializer never leaves its module.
        package init(package: HomebrewPackage, targetURL: URL, selectedIDs: Set<UUID>) {
            self.package = package
            self.targetURL = targetURL
            self.selectedIDs = selectedIDs
        }
    }

    package var homebrewRemovalConfirmation: HomebrewRemovalConfirmation? {
        guard canRemoveSelected,
              let package = selectedHomebrewPackage, let target else { return nil }
        return HomebrewRemovalConfirmation(package: package, targetURL: target.url,
                                           selectedIDs: Set(items.filter(\.include).map(\.id)))
    }

    // MARK: - Selection & scan

    /// Reads an app bundle and starts scanning for its leftovers.
    @discardableResult
    package func select(appURL: URL, trashMove: UninstallerSupport.TrashMove? = nil) -> Bool {
        guard !isRemoving else { return false }
        let selection: UninstallerSupport.Selection
        switch UninstallerSupport.evaluate(appURL) {
        case let .success(accepted):
            selection = accepted
        case let .failure(reason):
            refusal = UninstallerSupport.RefusedApp(name: UninstallerSupport.appName(at: appURL),
                                                    refusal: reason)
            return false
        }
        refusal = nil
        let bundleID = selection.bundleID
        let selectedURL = selection.url
        let name = UninstallerSupport.appName(at: appURL)
        let isTrashed = UninstallerSupport.isInTrash(selectedURL, home: FileManager.default.homeDirectoryForCurrentUser)
        if isTrashed || trashMove != nil {
            guard let trashMove, trashMove.selection == selection,
                  environment.packages.operation == nil, Self.trashMoveIsCurrent(trashMove) else {
                refusal = UninstallerSupport.RefusedApp(name: name, refusal: .unverifiedTrashMove)
                return false
            }
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)

        target = Target(name: name, bundleID: bundleID, url: selectedURL, icon: icon)
        targetSelection = selection
        targetTrashMove = trashMove
        homebrewPackage = nil
        homebrewCheckFailed = false
        homebrewRemovalSize = 0
        homebrewRemovedApplication = false
        homebrewRemovalObservation?.cancel()
        homebrewRemovalObservation = nil
        items = []
        allowedRemovalPaths = []
        // A new selection supersedes any scan still running, even for the
        // same app, so only this scan can deliver results.
        scanCancellation?.cancel()
        let cancellation = UninstallerSupport.ScanCancellation()
        scanCancellation = cancellation
        phase = .scanning

        // Homebrew takes about as long to answer as the scan, so both start
        // now and the results show once each has finished, in either order.
        // Both answers land on the main thread, so they need no lock.
        let answers = ScanAnswers()
        let scan = environment.scan, main = environment.main
        let request = Scan(appURL: selectedURL, bundleID: bundleID,
                           fromTrashMove: trashMove != nil, cancellation: cancellation)
        environment.packages.packageManagingApplication(at: trashMove?.originalURL ?? selectedURL) { [weak self] result in
            answers.ownership = result
            self?.deliverScan(answers, name: name, selectedURL: selectedURL, cancellation: cancellation)
        }
        environment.background(0) { [weak self] in
            guard !cancellation.isCancelled, let found = scan(request) else { return }
            // A scan superseded while it ran hands nothing back to the main thread.
            guard !cancellation.isCancelled else { return }
            main { [weak self] in
                answers.leftovers = found
                self?.deliverScan(answers, name: name, selectedURL: selectedURL, cancellation: cancellation)
            }
        }
        return true
    }

    /// Shows what a scan found, once both the leftovers and the package
    /// manager's answer are in. Drops the result if the user picked a
    /// different app (or reset) while this scan was running: never show A's
    /// files under B.
    private func deliverScan(_ answers: ScanAnswers, name: String, selectedURL: URL,
                             cancellation: UninstallerSupport.ScanCancellation) {
        guard let found = answers.leftovers, let result = answers.ownership,
              !cancellation.isCancelled,
              phase == .scanning, target?.url == selectedURL,
              let selection = targetSelection else { return }
        guard selection.isCurrent else {
            reset()
            return
        }
        if let trashMove = targetTrashMove {
            guard Self.trashMoveIsCurrent(trashMove), environment.packages.operation == nil else {
                reset()
                refusal = UninstallerSupport.RefusedApp(name: name, refusal: .unverifiedTrashMove)
                return
            }
            // A cask still owning the original installation path may be
            // updating or waiting to reinstall its app. Keep its data.
            if case .success(.some) = result {
                reset()
                refusal = UninstallerSupport.RefusedApp(name: name, refusal: .unverifiedTrashMove)
                return
            }
        }
        items = found
        switch result {
        case let .success(package):
            homebrewPackage = package
            homebrewCheckFailed = false
        case .failure:
            homebrewPackage = nil
            homebrewCheckFailed = true
        }
        allowedRemovalPaths = Set(found.map { $0.url.standardizedFileURL.path })
        scanCancellation = nil
        phase = .results
    }

    /// Takes a drop onto either uninstaller surface: the first app among the
    /// dropped files, or else the first file. The answer is the drop's, so an
    /// app the uninstaller refuses springs back instead of landing.
    @discardableResult
    package func selectDropped(_ urls: [URL]) -> Bool {
        guard let app = urls.first(where: { $0.pathExtension == "app" }) ?? urls.first else {
            return false
        }
        return select(appURL: app)
    }

    package func setInclude(_ include: Bool, for id: UUID) {
        guard !isRemoving else { return }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].include = include
    }

    /// What the select-all checkbox above the results shows for the rows.
    package var bulkSelection: UninstallerSupport.BulkSelection {
        UninstallerSupport.BulkSelection(included: items.filter(\.include).count, total: items.count)
    }

    /// Checks or clears every detected file at once. Like a single row, it
    /// refuses to change a removal that already started.
    package func setAllIncluded(_ include: Bool) {
        guard !isRemoving else { return }
        var updated = items
        for index in updated.indices {
            updated[index].include = include
        }
        items = updated
    }

    package func retryHomebrewCheck() {
        guard phase == .results, homebrewCheckFailed, let target else { return }
        select(appURL: target.url, trashMove: targetTrashMove)
    }

    /// Drops the refusal note, for an uninstaller view that opens or closes.
    package func clearRefusal() {
        refusal = nil
    }

    package func reset() {
        guard !isRemoving else { return }
        refusal = nil
        scanCancellation?.cancel()
        scanCancellation = nil
        target = nil
        targetSelection = nil
        targetTrashMove = nil
        homebrewPackage = nil
        homebrewCheckFailed = false
        homebrewRemovalSize = 0
        homebrewRemovedApplication = false
        homebrewRemovalObservation?.cancel()
        homebrewRemovalObservation = nil
        items = []
        allowedRemovalPaths = []
        phase = .empty
    }

    // MARK: - Removal

    package func removeSelected() {
        guard canRemoveSelected, selectedHomebrewPackage == nil else { return }
        let chosen = items.filter(\.include)
        guard !chosen.isEmpty, let selection = targetSelection else { return }
        if let move = targetTrashMove {
            guard environment.packages.operation == nil, Self.trashMoveIsCurrent(move) else {
                phase = .done(freed: 0, failed: chosen)
                return
            }
            // The rename has no author. During a non-atomic update the install
            // path can still be empty, just as it is after an uninstall, so
            // the person says whether this was an uninstall.
            let name = target?.name ?? move.selection.url.lastPathComponent
            guard environment.confirmTrashCleanup(name),
                  canRemoveSelected, targetTrashMove == move, items.filter(\.include) == chosen else { return }
            phase = .removing
            environment.packages.packageManagingApplication(at: move.originalURL) { [weak self] result in
                guard let self else { return }
                guard case .success(nil) = result, self.environment.packages.operation == nil,
                      Self.trashMoveIsCurrent(move) else {
                    self.phase = .done(freed: 0, failed: chosen)
                    return
                }
                self.remove(chosen, selection: selection, trashMove: move)
            }
            return
        }
        phase = .removing
        remove(chosen, selection: selection, trashMove: nil)
    }

    private func remove(_ chosen: [Leftover], selection: UninstallerSupport.Selection,
                        trashMove: UninstallerSupport.TrashMove?) {
        let targetURL = selection.url
        let targetBundleID = selection.bundleID
        // Quit the app and any background app embedded inside it before the
        // bundle moves. Embedded helpers do not always share the main bundle ID.
        // A Trash cleanup never quits anything: Finder already moved the
        // bundle, and a replacement at the install path belongs to an update.
        if trashMove == nil, selection.isCurrent {
            environment.quit(targetURL)
        }

        let removal = Removal(chosen: chosen, allowedPaths: allowedRemovalPaths,
                              selection: selection, trashMove: trashMove,
                              alreadyFreed: homebrewRemovalSize,
                              packageRemovedApplication: homebrewRemovedApplication)
        let remove = environment.remove, main = environment.main
        environment.background(0.3) { [weak self] in
            let (freed, failed) = remove(removal)
            main { [weak self] in
                // The user may have dismissed the flow while files moved.
                guard let self, self.phase == .removing else { return }
                self.items = []
                self.phase = .done(freed: freed, failed: failed)
                // A Trash cleanup leaves the app's own row to Finder, so the
                // command bar keeps what it knows until the app itself goes.
                if trashMove == nil {
                    self.environment.removeCommandBarState(targetURL, targetBundleID)
                }
            }
        }
    }

    /// The live removal: re-proves every row against what was scanned, moves
    /// what still belongs to the app to the Trash, and asks Finder (one
    /// administrator prompt) for whatever this process may not move itself.
    nonisolated
    private static func remove(_ removal: Removal) -> (freed: Int64, failed: [Leftover]) {
        remove(removal, roster: { knownApplicationURLs(candidateBundleIDs: $0) })
    }

    /// `roster` builds the known applications for these bundle identifiers.
    /// Only the shared-data claims read it, and building it opens every
    /// installed app, so it is built only when the removal may claim shared
    /// data, the same gate the scan uses.
    nonisolated
    package static func remove(_ removal: Removal,
                               roster: (Set<String>) -> [URL]) -> (freed: Int64, failed: [Leftover]) {
        let chosen = removal.chosen
        let allowedPaths = removal.allowedPaths
        let selection = removal.selection
        let trashMove = removal.trashMove
        let targetURL = removal.targetURL
        let targetBundleID = removal.targetBundleID
        let candidateBundleIDs = Set(chosen.compactMap(\.ownerBundleID))
        let candidateGroupIDs = Set(chosen.compactMap(\.ownerGroupID))
        let evidenceBundleIDs = Set(chosen.compactMap(\.evidenceBundleID))
        let fm = FileManager.default
        var freed = removal.alreadyFreed
        var stubborn: [Leftover] = []
        var failed: [Leftover] = []
        let targetIsOriginal = selection.isCurrent
        let targetWasRemovedByPackageManager = removal.packageRemovedApplication
            && UninstallerSupport.isConfirmedAbsent(at: targetURL)
        let mayClaimSharedData = (targetIsOriginal || targetWasRemovedByPackageManager)
            && (!candidateBundleIDs.isEmpty || !candidateGroupIDs.isEmpty)
        let lookupBundleIDs = candidateBundleIDs.union(evidenceBundleIDs).union([targetBundleID])
        // Only the shared-data claims below read this roster, and building
        // it opens every installed app. Same gate `select()` already uses.
        let knownApplications = mayClaimSharedData ? roster(lookupBundleIDs) : []
        let knownApplicationIDs = Self.applicationBundleIdentifiers(in: knownApplications)
        // If the app survives elsewhere, nothing it shares with that copy is
        // this removal's to take.
        let canRemoveData = mayClaimSharedData && UninstallerSupport.sharedDataIsExclusive(
            selectedURL: targetURL, bundleID: targetBundleID, knownApplications: knownApplicationIDs)
        let exclusiveBundleIDs = canRemoveData ? Self.exclusiveOwnedBundleIDs(
            in: targetURL, candidates: candidateBundleIDs,
            knownApplicationIDs: knownApplicationIDs,
            requiresCurrentOwnership: !targetWasRemovedByPackageManager) : []
        let exclusiveEvidenceBundleIDs = canRemoveData ? UninstallerSupport.exclusiveBundleIDs(
            evidenceBundleIDs, selectedURL: targetURL,
            knownApplications: knownApplicationIDs) : []
        let currentGroupIDs: Set<String>
        if targetIsOriginal, !candidateGroupIDs.isEmpty {
            currentGroupIDs = Self.signingIdentity(
                in: targetURL, requireValidSignature: true).groupIDs
                .intersection(candidateGroupIDs)
        } else if targetWasRemovedByPackageManager {
            currentGroupIDs = candidateGroupIDs
        } else {
            currentGroupIDs = []
        }
        let exclusiveGroupIDs = canRemoveData ? Self.exclusiveGroupIDs(
            currentGroupIDs, selectedURL: targetURL,
            knownApplications: knownApplications) : []
        var removedTarget = targetWasRemovedByPackageManager
        /// Whether the app still answers for this row. A Trash cleanup owns
        /// nothing but the app's data, and only while its move still stands.
        func targetAllowsRemoval(of item: Leftover) -> Bool {
            if let trashMove {
                return item.category != .app && Self.trashMoveIsCurrent(trashMove)
            }
            // A replacement can arrive during the inventory or between
            // rows. Only this uninstall's own move can explain an absence.
            if removedTarget, item.category != .app {
                return UninstallerSupport.isConfirmedAbsent(at: targetURL)
            }
            return selection.isCurrent
        }
        for item in chosen {
            guard targetAllowsRemoval(of: item) else {
                failed.append(item)
                continue
            }
            if item.category != .app {
                let keepsOwnership: Bool
                if let groupID = item.ownerGroupID {
                    keepsOwnership = exclusiveGroupIDs.contains(groupID)
                } else if let bundleID = item.ownerBundleID {
                    let evidenceIsExclusive = item.evidenceBundleID.map(
                        exclusiveEvidenceBundleIDs.contains) ?? true
                    keepsOwnership = exclusiveBundleIDs.contains(bundleID)
                        && evidenceIsExclusive
                } else {
                    keepsOwnership = false
                }
                guard keepsOwnership else {
                    failed.append(item)
                    continue
                }
            }
            guard Self.removalIsStillSafe(item.url,
                                          expectedIdentity: item.fileIdentity,
                                          allowedPaths: allowedPaths,
                                          targetURL: targetURL) else {
                // The package manager or another pass may have taken the path.
                // Only a confirmed absence counts as success; a still-present
                // path, or one we can no longer read, stays a failure.
                switch UninstallerSupport.unmovedRow(at: item.url, mayEscalate: false) {
                case .freed: freed += item.size
                case .stubborn, .failed: failed.append(item)
                }
                continue
            }
            do {
                try fm.trashItem(at: item.url, resultingItemURL: nil)
                if item.category == .app { removedTarget = true }
                freed += item.size
            } catch {
                // Finder can wait indefinitely at an administrator prompt.
                // Only a regular uninstall delegates to it; a replacement may
                // appear while Finder is waiting on a Trash cleanup.
                switch UninstallerSupport.unmovedRow(at: item.url, mayEscalate: trashMove == nil) {
                case .freed: freed += item.size
                case .stubborn: stubborn.append(item)
                case .failed: failed.append(item)
                }
            }
        }

        // Items we lack rights for (root-owned apps, /Library files) go
        // through Finder, which shows the administrator prompt and moves
        // them to the Trash exactly like a drag would. One batch, one
        // prompt; afterwards whatever still exists counts as failed.
        if !stubborn.isEmpty {
            let stillSafe = stubborn.filter {
                targetAllowsRemoval(of: $0)
                    && Self.removalIsStillSafe($0.url,
                                               expectedIdentity: $0.fileIdentity,
                                               allowedPaths: allowedPaths,
                                               targetURL: targetURL)
            }
            failed.append(contentsOf: stubborn.filter { item in
                !stillSafe.contains(where: { $0.id == item.id })
            })
            Self.trashViaFinder(stillSafe.map(\.url))
            for item in stillSafe {
                switch UninstallerSupport.unmovedRow(at: item.url, mayEscalate: false) {
                case .freed: freed += item.size
                case .stubborn, .failed: failed.append(item)
                }
            }
        }
        return (freed, failed)
    }

    /// After Homebrew has removed its package receipt and app artifact, clean
    /// only the other items the person selected. The app itself is excluded so
    /// this flow never tries to remove the same bundle twice.
    package func removeSelectedWithHomebrew(confirmation: HomebrewRemovalConfirmation) {
        guard canRemoveSelected,
              target?.url == confirmation.targetURL,
              targetSelection?.isCurrent == true,
              selectedHomebrewPackage?.id == confirmation.package.id,
              Set(items.filter(\.include).map(\.id)) == confirmation.selectedIDs else {
            environment.notify("exclamationmark.circle", L10n.shared.s.uninstallerConfirmationExpired)
            return
        }
        let package = confirmation.package
        let manager = environment.packages
        guard manager.operation == nil else { return }
        homebrewRemovalObservation?.cancel()
        // The last finished run keeps its log, so its status is still the
        // current value: skip it, or it would read as this removal's result.
        homebrewRemovalObservation = manager.operationStatuses
            .dropFirst()
            .compactMap { $0 }
            .filter { $0.action == .uninstall && $0.package?.id == package.id }
            .sink { [weak self] status in
                guard status.result != .running else { return }
                self?.homebrewRemovalObservation?.cancel()
                self?.homebrewRemovalObservation = nil
                if status.result == .succeeded {
                    self?.finishRemovalAfterHomebrew(package: package)
                }
            }
        manager.uninstall(package, fromUninstaller: true)
        if manager.operation == nil { homebrewRemovalObservation = nil }
    }

    private func finishRemovalAfterHomebrew(package: HomebrewPackage) {
        guard phase == .results,
              homebrewPackage?.id == package.id,
              let app = items.first(where: { $0.category == .app && $0.include }),
              let targetURL = target?.url else { return }
        // Completion is published before the stored status stops reading as
        // active. Clear the package before changing the guarded selection,
        // and credit the app only after its absence is confirmed.
        homebrewRemovedApplication = true
        homebrewPackage = nil
        setInclude(false, for: app.id)
        if UninstallerSupport.isConfirmedAbsent(at: targetURL) {
            homebrewRemovalSize = app.size
        } else if FileManager.default.fileExists(atPath: targetURL.path) {
            // Package removal succeeded but left the bundle. Re-select only the
            // app so removeSelected can finish it under the package flag,
            // counting size once when it is actually gone.
            homebrewRemovalSize = 0
            setInclude(true, for: app.id)
        } else {
            // A failed lookup is not proof of removal. Keep the failure visible.
            homebrewRemovalSize = 0
            homebrewRemovedApplication = false
            setInclude(true, for: app.id)
            phase = .done(freed: 0, failed: [app])
            return
        }
        if items.contains(where: \.include) {
            removeSelected()
        } else {
            phase = .done(freed: homebrewRemovalSize, failed: [])
            environment.removeCommandBarState(targetURL, target?.bundleID)
        }
    }

    /// A remaining copy keeps the preferences shared under its bundle ID.
    /// Only apps with shared preferences need the folder and Spotlight scan;
    /// path-specific state can go without it, even while the bar is disabled.
    static func removeCommandBarState(ofRemovedAppAt url: URL, bundleID: String?) {
        let bundleIDs: Set<String> = bundleID.map {
            CommandBarService.shared.hasStoredApplicationState(bundleID: $0) ? [$0] : []
        } ?? []
        DispatchQueue.global(qos: .utility).async {
            guard UninstallerSupport.isConfirmedAbsent(at: url) else { return }
            let remaining: Set<String> = bundleIDs.isEmpty ? [] : Set(InstalledApps.installedApplications(
                includeSystemApplications: true,
                spotlightPaths: CommandBarService.spotlightApplicationPaths())
                .compactMap(\.bundleID))
            DispatchQueue.main.async {
                // A reinstall while the scan was pending must keep its state.
                guard UninstallerSupport.isConfirmedAbsent(at: url) else { return }
                CommandBarService.shared.removeApplicationState(
                    bundleIDs: bundleIDs, urls: [url], remainingBundleIDs: remaining)
            }
        }
    }

    /// Asks Finder to trash `urls` in one batch. Finder owns the privilege
    /// elevation (the standard administrator prompt) and the result is a
    /// reversible move to the Trash, never a permanent delete. Waits until the
    /// user answers the prompt; a cancel simply leaves the items in place.
    nonisolated
    private static func trashViaFinder(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard AppleScriptRunner.consentToAutomate(bundleID: "com.apple.finder") else { return }
        // In-process Apple Events (see AppleScriptRunner): the Finder Automation
        // consent is attributed to this app and re-requested if it was lost,
        // instead of a fragile osascript subprocess. Paths are embedded as
        // escaped string literals (no argv).
        let targets = urls
            .map { "set end of targets to POSIX file \(AppleScriptRunner.literal($0.path))" }
            .joined(separator: "\n")
        let source = """
        set targets to {}
        \(targets)
        tell application "Finder" to delete targets
        """
        _ = AppleScriptRunner.run(source)
    }

    // MARK: - Scanning

    /// The live scan: what the bundle owns, what it may claim among shared
    /// data, and the leftovers that follow. Nil once it has been cancelled.
    nonisolated
    private static func scan(_ request: Scan) -> [Leftover]? {
        let selectedURL = request.appURL
        let cancellation = request.cancellation
        let ownedBundleIDs = Self.allBundleIDs(in: selectedURL, fm: .default)
        // A witnessed move to the Trash stands in for the install root the
        // app has just left, so its data can still be found.
        let trusted = request.fromTrashMove || UninstallerSupport.applicationIsInTrustedInstallRoot(
            selectedURL, home: FileManager.default.homeDirectoryForCurrentUser)
        let knownApplications = trusted
            ? Self.knownApplicationURLs(candidateBundleIDs: ownedBundleIDs)
            : []
        let knownApplicationIDs = Self.applicationBundleIdentifiers(in: knownApplications)
        // If the primary app survives, even an old exclusive helper must not
        // claim its live parent's profile through a display-name match.
        let mayClaimSharedData = trusted && UninstallerSupport.sharedDataIsExclusive(
            selectedURL: selectedURL, bundleID: request.bundleID,
            knownApplications: knownApplicationIDs)
        let exclusiveBundleIDs = mayClaimSharedData
            ? Self.exclusiveOwnedBundleIDs(
                in: selectedURL, candidates: ownedBundleIDs,
                knownApplicationIDs: knownApplicationIDs)
            : []
        guard !cancellation.isCancelled else { return nil }
        let signing = Self.signingIdentity(in: selectedURL, requireValidSignature: true)
        let exclusiveGroupIDs = mayClaimSharedData
            ? Self.exclusiveGroupIDs(
                signing.groupIDs, selectedURL: selectedURL,
                knownApplications: knownApplications)
            : []
        return Self.collect(appURL: selectedURL,
                            primaryBundleID: request.bundleID,
                            exclusiveBundleIDs: exclusiveBundleIDs,
                            teamIDs: signing.teamIDs,
                            exclusiveGroupIDs: exclusiveGroupIDs,
                            cancellation: cancellation)
    }

    nonisolated
    private static func collect(appURL: URL,
                                primaryBundleID: String,
                                exclusiveBundleIDs: Set<String>,
                                teamIDs: Set<String>,
                                exclusiveGroupIDs: Set<String>,
                                cancellation: UninstallerSupport.ScanCancellation) -> [Leftover] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        // The target header already identifies the trashed app. Keep the
        // bundle out of the checklist, including Select All and space totals.
        let appAlreadyTrashed = UninstallerSupport.isInTrash(
            appURL, home: fm.homeDirectoryForCurrentUser)
        var paths = appAlreadyTrashed ? [] : [ScanCandidate(url: appURL, category: .app,
                                   ownerBundleID: nil, ownerGroupID: nil,
                                   evidenceBundleID: nil,
                                   confidence: .exact, include: true)]
        let info = UninstallerSupport.infoDictionary(of: appURL)
        var displayNames = UninstallerSupport.displayNames(
            localizedName: fm.displayName(atPath: appURL.path),
            fileName: appURL.lastPathComponent,
            bundleName: info?["CFBundleName"] as? String,
            bundleDisplayName: info?["CFBundleDisplayName"] as? String
        )
        if let executable = info?["CFBundleExecutable"] as? String {
            displayNames.append(executable)
        }
        let identity = UninstallerSupport.identity(
            primaryBundleID: primaryBundleID,
            bundleIDs: exclusiveBundleIDs,
            displayNames: displayNames,
            teamIDs: teamIDs,
            groupIDs: exclusiveGroupIDs
        )
        let allowedRoots = scanRoots(home: home)

        let folders = UninstallerSupport.searchFolders(
            home: URL(fileURLWithPath: home, isDirectory: true),
            darwinCache: darwinUserDirectory(_CS_DARWIN_USER_CACHE_DIR),
            darwinTemp: darwinUserDirectory(_CS_DARWIN_USER_TEMP_DIR)
        )
        // Each folder is listed and matched on its own, and Spotlight is one
        // more lookup, so they all run side by side. Matches keep the order
        // they had one after another: the folders in turn, then Spotlight.
        var matches = [[ScanCandidate]](repeating: [], count: folders.count + 1)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: folders.count + 1) { index in
            guard !cancellation.isCancelled else { return }
            var found: [ScanCandidate] = []
            if index < folders.count {
                appendMatches(in: folders[index], identity: identity, fm: FileManager(), into: &found)
            } else {
                appendSpotlightMatches(identity: identity, roots: spotlightRoots(home: home),
                                       fm: FileManager(), into: &found)
            }
            lock.lock()
            matches[index] = found
            lock.unlock()
        }
        guard !cancellation.isCancelled else { return [] }
        paths += matches.joined()

        // Last line of defense: nothing outside the scanned roots (or the app
        // bundle itself) may ever reach the removal list.
        let appPath = appURL.standardizedFileURL.path
        let safe = dedupe(paths).filter { candidate in
            let path = candidate.url.standardizedFileURL.path
            if path == appPath {
                return !UninstallerSupport.isSymbolicLink(candidate.url)
            }
            guard let root = allowedRoots.first(where: { path.hasPrefix($0.path + "/") }) else {
                return false
            }
            return UninstallerSupport.removalPathIsSafe(candidate.url, within: root)
        }
        return safe
            .compactMap { candidate -> Leftover? in
                // Sizing walks every folder found; stop there too.
                guard !cancellation.isCancelled,
                      let fileIdentity = UninstallerSupport.fileIdentity(at: candidate.url) else {
                    return nil
                }
                return Leftover(url: candidate.url, category: candidate.category,
                                size: directorySize(of: candidate.url, fm: fm),
                                ownerBundleID: candidate.ownerBundleID,
                                ownerGroupID: candidate.ownerGroupID,
                                evidenceBundleID: candidate.evidenceBundleID,
                                confidence: candidate.confidence,
                                fileIdentity: fileIdentity,
                                include: !appAlreadyTrashed && candidate.include)
            }
            .sorted { ($0.category.sortRank, -$0.size) < ($1.category.sortRank, -$1.size) }
    }

    nonisolated
    private static func appendMatches(in folder: UninstallerSupport.SearchFolder,
                                      identity: UninstallerSupport.Identity,
                                      fm: FileManager,
                                      into paths: inout [ScanCandidate]) {
        let listings = dirListings(at: folder.url, remainingDepth: folder.extraChildDepth, fm: fm)
        guard !listings.isEmpty else { return }
        let category = category(for: folder.kind)
        let matchingIdentity: UninstallerSupport.Identity
        if folder.requiresSignedGroup {
            matchingIdentity = UninstallerSupport.Identity(
                bundleIDs: [], nameTokens: [], teamIDs: [], groupIDs: identity.groupIDs)
        } else {
            matchingIdentity = folder.allowsNameMatches
                ? identity : UninstallerSupport.technicalIdentity(identity)
        }
        var claimed = Set<String>()
        for hit in UninstallerSupport.leftoverHitRecords(
            listings: listings,
            identity: matchingIdentity,
            extraChildDepth: folder.extraChildDepth,
            crashReporter: folder.crashReporter
        ) {
            claimed.insert(hit.path)
            appendHit(hit, folder: folder.url, category: category, identity: matchingIdentity,
                      crashReporter: folder.crashReporter, into: &paths)
        }
        guard folder.readsContainerMetadata else { return }
        for listing in listings where !claimed.contains(listing.name) {
            let url = folder.url.appendingPathComponent(listing.name)
            guard let identifier = containerMetadataIdentifier(at: url) else { continue }
            let match = UninstallerSupport.containerMetadataMatches(identifier, identity: matchingIdentity)
            guard match != .none else { continue }
            claimed.insert(listing.name)
            let groupID = UninstallerSupport.matchingGroupID(identifier, identity: matchingIdentity)
                ?? UninstallerSupport.matchingGroupID(listing.name, identity: matchingIdentity)
            let owner = groupID == nil
                ? (UninstallerSupport.ownerBundleID(for: identifier, identity: matchingIdentity)
                    ?? UninstallerSupport.ownerBundleID(for: listing.name, identity: matchingIdentity)
                    ?? matchingIdentity.bundleIDs.min(by: { $0.count < $1.count }))
                : nil
            guard owner != nil || groupID != nil else { continue }
            let evidence = groupID == nil
                ? UninstallerSupport.verifiedBundleID(identifier) : nil
            paths.append(ScanCandidate(url: url, category: category,
                                       ownerBundleID: owner, ownerGroupID: groupID,
                                       evidenceBundleID: evidence,
                                       confidence: match, include: match == .exact))
        }
    }

    nonisolated
    private static func appendHit(_ hit: UninstallerSupport.Hit,
                                  folder: URL,
                                  category: Category,
                                  identity: UninstallerSupport.Identity,
                                  crashReporter: Bool,
                                  into paths: inout [ScanCandidate]) {
        let relative = hit.path
        let name = (relative as NSString).lastPathComponent
        let identifier = hit.bundleIdentifier
            ?? CleanerSupport.bundleIDCandidate(fromEntryName: name)
        let groupID = identifier.flatMap {
            UninstallerSupport.matchingGroupID($0, identity: identity)
        } ?? UninstallerSupport.matchingGroupID(name, identity: identity)
        let owner = groupID == nil
            ? (identifier.flatMap { UninstallerSupport.ownerBundleID(for: $0, identity: identity) }
                ?? UninstallerSupport.ownerBundleID(for: name, identity: identity,
                                                crashReporter: crashReporter)
                ?? identity.bundleIDs.min(by: { $0.count < $1.count }))
            : nil
        guard owner != nil || groupID != nil else { return }
        let url = relative.split(separator: "/").reduce(folder) {
            $0.appendingPathComponent(String($1))
        }
        paths.append(ScanCandidate(url: url, category: category,
                                   ownerBundleID: owner, ownerGroupID: groupID,
                                   evidenceBundleID: groupID == nil ? identifier : nil,
                                   confidence: hit.confidence,
                                   include: hit.confidence == .exact))
    }

    nonisolated
    private static func dirListings(at url: URL,
                                    remainingDepth: Int,
                                    fm: FileManager) -> [UninstallerSupport.DirListing] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let entries = try? fm.contentsOfDirectory(at: url,
                                                        includingPropertiesForKeys: Array(keys),
                                                        options: []) else { return [] }
        return entries.compactMap { entry -> UninstallerSupport.DirListing? in
            let name = entry.lastPathComponent
            guard !name.hasPrefix(".") else { return nil }
            let values = try? entry.resourceValues(forKeys: keys)
            guard values?.isSymbolicLink != true else { return nil }
            var children: [UninstallerSupport.DirListing] = []
            if remainingDepth > 0, values?.isDirectory == true {
                children = dirListings(at: entry, remainingDepth: remainingDepth - 1, fm: fm)
            }
            let bundleIdentifier = packageExtensions.contains(entry.pathExtension.lowercased())
                ? UninstallerSupport.verifiedBundleID(UninstallerSupport.bundleIdentifier(of: entry))
                : nil
            return UninstallerSupport.DirListing(name: name, children: children,
                                                  bundleIdentifier: bundleIdentifier)
        }
    }

    nonisolated
    private static func containerMetadataIdentifier(at url: URL) -> String? {
        let metadata = url.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
        guard let dict = NSDictionary(contentsOf: metadata) as? [String: Any] else { return nil }
        return dict["MCMMetadataIdentifier"] as? String
    }

    nonisolated
    private static func appendSpotlightMatches(identity: UninstallerSupport.Identity,
                                               roots: [URL],
                                               fm: FileManager,
                                               into paths: inout [ScanCandidate]) {
        guard let expression = UninstallerSupport.leftoverSpotlightExpression(identity: identity)
        else { return }
        let scopes = roots.map(\.path).filter { fm.fileExists(atPath: $0) }
        guard !scopes.isEmpty,
              let query = MDQueryCreate(kCFAllocatorDefault, expression as CFString, nil, nil)
        else { return }
        MDQuerySetMaxCount(query, 200)
        MDQuerySetSearchScope(query, scopes as CFArray, 0)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return }
        let count = min(MDQueryGetResultCount(query), 200)
        var added = 0
        for index in 0..<count {
            guard added < 80,
                  let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = unsafeBitCast(raw, to: MDItem.self)
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String,
                  UninstallerSupport.leftoverSpotlightPathIsAllowed(path, roots: roots)
            else { continue }
            let url = URL(fileURLWithPath: path)
            let matchingIdentity = UninstallerSupport.spotlightIdentity(for: path, identity: identity)
            let match = UninstallerSupport.leftoverMatch(
                url.lastPathComponent, identity: matchingIdentity)
            guard match != .none else { continue }
            let groupID = UninstallerSupport.matchingGroupID(
                url.lastPathComponent, identity: matchingIdentity)
            let evidence = groupID == nil
                ? CleanerSupport.bundleIDCandidate(fromEntryName: url.lastPathComponent) : nil
            let owner = groupID == nil
                ? (UninstallerSupport.ownerBundleID(
                    for: evidence ?? url.lastPathComponent, identity: matchingIdentity)
                    ?? matchingIdentity.bundleIDs.min(by: { $0.count < $1.count }))
                : nil
            guard owner != nil || groupID != nil else { continue }
            paths.append(ScanCandidate(url: url, category: category(forPath: path),
                                       ownerBundleID: owner, ownerGroupID: groupID,
                                       evidenceBundleID: evidence,
                                       confidence: match, include: false))
            added += 1
        }
    }

    nonisolated
    private static func category(forPath path: String) -> Category {
        if path.contains("/Caches") { return .caches }
        if path.contains("/Preferences") { return .preferences }
        if path.contains("/Group Containers") || path.contains("/Containers") { return .containers }
        if path.contains("/Logs") { return .logs }
        if path.contains("/Saved Application State") { return .state }
        if path.contains("/Application Support") { return .support }
        return .other
    }

    nonisolated
    private static func codeSigningIdentity(at appURL: URL,
                                            requireValidSignature: Bool)
        -> (teamIDs: Set<String>, groupIDs: Set<String>) {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return ([], []) }
        if requireValidSignature,
           SecStaticCodeCheckValidity(staticCode, [], nil) != errSecSuccess {
            return ([], [])
        }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let info else { return ([], []) }
        let dict = info as NSDictionary
        var teamIDs: Set<String> = []
        if let team = dict[kSecCodeInfoTeamIdentifier] as? String {
            teamIDs.insert(team)
        }
        var groupIDs: Set<String> = []
        if let entitlements = dict[kSecCodeInfoEntitlementsDict] as? [String: Any],
           let groups = entitlements["com.apple.security.application-groups"] as? [String] {
            groupIDs.formUnion(groups.filter { !$0.isEmpty })
        }
        return (teamIDs, groupIDs)
    }

    /// Main app plus owned executable extensions. Resource bundles and
    /// arbitrary nested apps are excluded because their identifiers may be
    /// shared by unrelated products.
    nonisolated
    private static func signingIdentity(in appURL: URL,
                                        requireValidSignature: Bool)
        -> (teamIDs: Set<String>, groupIDs: Set<String>) {
        if requireValidSignature, !codeSignatureIsValid(at: appURL) {
            return ([], [])
        }
        var result = codeSigningIdentity(at: appURL,
                                         requireValidSignature: requireValidSignature)
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = fm.enumerator(at: appURL,
                                             includingPropertiesForKeys: Array(keys),
                                             options: [.skipsHiddenFiles],
                                             errorHandler: nil) else { return result }
        var inspected = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values?.isDirectory == true,
                  ownedEmbeddedCode(url, in: appURL) else { continue }
            inspected += 1
            guard inspected <= 256 else { break }
            let nested = codeSigningIdentity(at: url,
                                             requireValidSignature: requireValidSignature)
            result.teamIDs.formUnion(nested.teamIDs)
            result.groupIDs.formUnion(nested.groupIDs)
        }
        return result
    }

    nonisolated
    private static func codeSignatureIsValid(at url: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return false }
        return SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess
    }

    nonisolated
    private static func category(for kind: UninstallerSupport.Kind) -> Category {
        switch kind {
        case .support: return .support
        case .caches: return .caches
        case .preferences: return .preferences
        case .containers: return .containers
        case .logs: return .logs
        case .state: return .state
        case .other: return .other
        }
    }

    nonisolated
    private static func knownApplicationURLs(candidateBundleIDs: Set<String>) -> [URL] {
        var urls = InstalledApps.installedApplications(
            includeSystemApplications: true, spotlightPaths: CommandBarService.spotlightApplicationPaths()).map(\.url)
        urls += NSWorkspace.shared.runningApplications.compactMap(\.bundleURL)
        for id in candidateBundleIDs {
            urls += NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id)
        }
        var seen = Set<String>()
        return urls.compactMap { url in
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
                  FileManager.default.fileExists(atPath: resolved.path),
                  seen.insert(resolved.path).inserted else { return nil }
            return resolved
        }
    }

    nonisolated
    private static func exclusiveOwnedBundleIDs(in selectedURL: URL,
                                                candidates: Set<String>,
                                                knownApplicationIDs: [(url: URL, bundleID: String)],
                                                requiresCurrentOwnership: Bool = true) -> Set<String> {
        var eligible = candidates
        if requiresCurrentOwnership {
            let current = allBundleIDs(in: selectedURL, fm: .default)
            eligible = Set(candidates.filter { candidate in
                current.contains(where: {
                    $0.caseInsensitiveCompare(candidate) == .orderedSame
                })
            })
        }
        return UninstallerSupport.exclusiveBundleIDs(eligible,
                                                     selectedURL: selectedURL,
                                                     knownApplications: knownApplicationIDs)
    }

    nonisolated
    private static func applicationBundleIdentifiers(in applications: [URL])
        -> [(url: URL, bundleID: String)] {
        // Walking every installed app's bundle is most of a scan's time.
        // Each walk is independent, so they run side by side.
        var bundleIDs = [Set<String>](repeating: [], count: applications.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: applications.count) { index in
            // An extension or login item can change without modifying its
            // parent's Info.plist. Ownership must include the current children.
            let ids = allBundleIDs(in: applications[index], fm: FileManager())
            lock.lock()
            bundleIDs[index] = ids
            lock.unlock()
        }
        return zip(applications, bundleIDs).flatMap { url, ids in ids.map { (url, $0) } }
    }

    nonisolated
    private static func exclusiveGroupIDs(_ candidates: Set<String>,
                                          selectedURL: URL,
                                          knownApplications: [URL]) -> Set<String> {
        guard !candidates.isEmpty else { return [] }
        let selectedPath = selectedURL.resolvingSymlinksInPath().standardizedFileURL.path
        var claimedElsewhere = Set<String>()
        for url in knownApplications {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard path != selectedPath, !path.hasPrefix(selectedPath + "/") else { continue }
            let groups = signingIdentity(in: url, requireValidSignature: false).groupIDs
            claimedElsewhere.formUnion(groups.intersection(candidates))
            if claimedElsewhere == candidates { break }
        }
        return candidates.subtracting(claimedElsewhere)
    }

    nonisolated
    private static func removalIsStillSafe(_ url: URL,
                                           expectedIdentity: UninstallerSupport.FileIdentity,
                                           allowedPaths: Set<String>,
                                           targetURL: URL?) -> Bool {
        let path = url.standardizedFileURL.path
        guard allowedPaths.contains(path), let targetURL,
              UninstallerSupport.fileIdentity(at: url) == expectedIdentity else { return false }
        if path == targetURL.standardizedFileURL.path {
            return !UninstallerSupport.isSymbolicLink(url)
        }
        guard let root = scanRoots(home: NSHomeDirectory()).first(where: {
            path.hasPrefix($0.path + "/")
        }) else { return false }
        return UninstallerSupport.removalPathIsSafe(url, within: root)
    }

    nonisolated
    private static func allBundleIDs(in appURL: URL, fm: FileManager) -> Set<String> {
        var result = Set<String>()
        if let primary = UninstallerSupport.verifiedBundleID(UninstallerSupport.bundleIdentifier(of: appURL)) {
            result.insert(primary)
        }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = fm.enumerator(at: appURL,
                                             includingPropertiesForKeys: Array(keys),
                                             options: [.skipsHiddenFiles],
                                             errorHandler: nil) else { return result }
        var inspected = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values?.isDirectory == true,
                  ownedEmbeddedCode(url, in: appURL),
                  let id = UninstallerSupport.verifiedBundleID(UninstallerSupport.bundleIdentifier(of: url))
            else { continue }
            inspected += 1
            guard inspected <= 256 else { break }
            result.insert(id)
        }
        return result
    }

    nonisolated
    private static func ownedEmbeddedCode(_ url: URL, in appURL: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "appex", "xpc":
            return true
        case "app":
            let loginItems = appURL.appendingPathComponent(
                "Contents/Library/LoginItems", isDirectory: true).standardizedFileURL.path
            return url.standardizedFileURL.path.hasPrefix(loginItems + "/")
        default:
            return false
        }
    }

    nonisolated
    private static let packageExtensions: Set<String> = [
        "app", "appex", "bundle", "framework", "plugin", "webplugin",
        "prefpane", "qlgenerator", "mdimporter", "service", "saver",
        "colorpicker", "wdgt", "component", "vst", "vst3", "clap", "dpm",
        "aaxplugin", "dictionary", "action", "workflow", "mailbundle",
    ]

    nonisolated
    private static func scanRoots(home: String) -> [URL] {
        var roots = [
            URL(fileURLWithPath: home + "/Library", isDirectory: true),
            URL(fileURLWithPath: "/Library", isDirectory: true),
            URL(fileURLWithPath: home + "/.config", isDirectory: true),
            URL(fileURLWithPath: home + "/.cache", isDirectory: true),
            URL(fileURLWithPath: home + "/.local/share", isDirectory: true),
            URL(fileURLWithPath: "/private/var/db/receipts", isDirectory: true),
            URL(fileURLWithPath: "/Users/Shared/Library", isDirectory: true),
        ]
        if let cache = darwinUserDirectory(_CS_DARWIN_USER_CACHE_DIR) { roots.append(cache) }
        if let temp = darwinUserDirectory(_CS_DARWIN_USER_TEMP_DIR) { roots.append(temp) }
        return roots.map(\.standardizedFileURL)
    }

    nonisolated
    private static func spotlightRoots(home: String) -> [URL] {
        [
            URL(fileURLWithPath: home + "/Library", isDirectory: true),
            URL(fileURLWithPath: "/Library", isDirectory: true),
            URL(fileURLWithPath: "/Users/Shared/Library", isDirectory: true),
        ].map(\.standardizedFileURL)
    }

    nonisolated
    private static func darwinUserDirectory(_ name: Int32) -> URL? {
        let length = confstr(name, nil, 0)
        guard length > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(name, &buffer, length) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer), isDirectory: true).standardizedFileURL
    }

    /// Drops exact duplicates and any path nested inside another already found.
    /// An exact match upgrades a related one already recorded at the same path.
    nonisolated
    private static func dedupe(_ paths: [ScanCandidate]) -> [ScanCandidate] {
        var seen = Set<String>()
        var roots: [String] = []
        var out: [ScanCandidate] = []
        let exactPaths = paths.filter { $0.confidence == .exact }
            .map { $0.url.standardizedFileURL.path }
        for candidate in paths.sorted(by: { $0.url.path.count < $1.url.path.count }) {
            let path = candidate.url.standardizedFileURL.path
            if candidate.confidence == .related,
               exactPaths.contains(where: { $0.hasPrefix(path + "/") }) {
                continue
            }
            if let index = out.firstIndex(where: { $0.url.standardizedFileURL.path == path }) {
                let include = out[index].include || candidate.include
                if out[index].confidence != .exact, candidate.confidence == .exact {
                    out[index] = candidate
                }
                out[index].include = include
                continue
            }
            if seen.contains(path) { continue }
            if roots.contains(where: { path.hasPrefix($0 + "/") }) { continue }
            seen.insert(path)
            roots.append(path)
            out.append(candidate)
        }
        return out
    }

    nonisolated
    private static func directorySize(of url: URL, fm: FileManager) -> Int64 {
        if UninstallerSupport.isSymbolicLink(url) { return fileSize(url) }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return fileSize(url) }

        var total: Int64 = 0
        if let enumerator = fm.enumerator(at: url,
                                          includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
                                          options: [], errorHandler: nil) {
            for case let item as URL in enumerator {
                if UninstallerSupport.isSymbolicLink(item) {
                    enumerator.skipDescendants()
                    continue
                }
                total += fileSize(item)
            }
        }
        return total
    }

    nonisolated
    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
    }
}

extension HomebrewManager: AppUninstaller.PackageManager {
    package var operationStatuses: AnyPublisher<HomebrewOperationStatus?, Never> {
        $operationStatus.eraseToAnyPublisher()
    }
}
