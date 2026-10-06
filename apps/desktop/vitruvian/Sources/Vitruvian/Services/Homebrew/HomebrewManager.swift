// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Darwin
import Foundation
import VitruvianCore
import VitruvianDesign

@MainActor
package final class HomebrewManager: ObservableObject {
    package static let shared = HomebrewManager()

    @Published package private(set) var brewPath: String?
    @Published package private(set) var installed: [HomebrewPackage] = []
    @Published package private(set) var searchResults: [HomebrewPackage] = []
    @Published package private(set) var selectedPackage: HomebrewPackage?
    @Published package private(set) var isLoadingInstalled = false
    @Published package private(set) var isLoadingOutdated = false
    @Published package private(set) var isSearching = false
    @Published package private(set) var isLoadingPopularity = false
    @Published package private(set) var isLoadingDetails = false
    @Published package private(set) var operation: HomebrewOperation?
    @Published package private(set) var operationStatus: HomebrewOperationStatus?
    @Published package private(set) var log = ""
    @Published package private(set) var errorMessage: String?
    @Published package private(set) var terminalFallbackCommand: String?
    /// A third-party tap Homebrew refused to load until the user trusts it,
    /// with the interrupted work retried right after the one-click trust.
    @Published package private(set) var untrustedTap: String?
    @Published package private(set) var isTrustingTap = false
    private var untrustedTapRetry: (@MainActor @Sendable () -> Void)?
    @Published package private(set) var didOpenInstaller = false
    @Published package private(set) var isShellConfigured = true
    @Published package private(set) var shellConfigProfilePath: String?
    @Published package private(set) var didOpenShellConfig = false
    @Published package private(set) var outdatedPackagesByID: [String: HomebrewPackageUpdate] = [:]

    private let workQueue = DispatchQueue(label: "com.vitruviansoftware.vitruvian.homebrew", qos: .userInitiated)
    private var searchGeneration = 0
    private var detailsGeneration = 0
    private var outdatedGeneration = 0
    private var currentSearchKind: HomebrewPackageKind?
    private var popularityCache: [HomebrewPackageKind: PopularityCacheEntry] = [:]
    private var popularityLoads: Set<HomebrewPackageKind> = []
    private var activeProcess: Process?
    private var cancelRequested = false
    private var installedCaskRecords: [HomebrewCaskRecord] = []
    private var installedCaskRecordsFetchedAt: Date?
    private var ownershipLoads: [String: [(HomebrewPackage?) -> Void]] = [:]
    private var completedOperationCleanup: DispatchWorkItem?
    private lazy var analyticsSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 8
        return URLSession(configuration: configuration)
    }()

    package var isBusy: Bool {
        isLoadingInstalled || isSearching || isLoadingDetails || operation != nil
    }

    package var outdatedCount: Int {
        outdatedPackagesByID.count
    }

    /// Finds brew, or answers nil when it is not installed.
    private let locateBrew: () -> String?

    private convenience init() {
        self.init(locateBrew: {
            HomebrewCommandBuilder.candidatePaths.first {
                FileManager.default.isExecutableFile(atPath: $0)
            }
        })
    }

    /// `shared` looks for brew in Homebrew's two prefixes; tests hand in a
    /// stand-in.
    package init(locateBrew: @escaping () -> String?) {
        self.locateBrew = locateBrew
        brewPath = locateBrew()
    }

    /// - Parameter clearingError: pass `false` when refreshing straight after a
    ///   failed operation, so the reason that operation gave is still on screen
    ///   while the fresh state loads.
    package func refreshInstalled(clearingError: Bool = true) {
        guard let brewPath = detectBrewPath() else {
            self.brewPath = nil
            installed = []
            installedCaskRecords = []
            installedCaskRecordsFetchedAt = nil
            searchResults = []
            selectedPackage = nil
            outdatedGeneration += 1
            outdatedPackagesByID = [:]
            isLoadingOutdated = false
            if clearingError { errorMessage = nil }
            isShellConfigured = true
            shellConfigProfilePath = nil
            didOpenShellConfig = false
            return
        }
        self.brewPath = brewPath
        updateShellConfigStatus(brewPath: brewPath)
        isLoadingInstalled = true
        if clearingError { errorMessage = nil }
        clearUntrustedTap()
        let command = HomebrewCommandBuilder.installed(brewPath: brewPath)
        run(command) { [weak self] status, output in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isLoadingInstalled = false
                guard status == 0 else {
                    if let tap = HomebrewCommandBuilder.untrustedTapName(fromOutput: output) {
                        self.presentUntrustedTap(tap) { [weak self] in self?.refreshInstalled() }
                    } else {
                        self.errorMessage = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    self.outdatedGeneration += 1
                    self.outdatedPackagesByID = [:]
                    self.isLoadingOutdated = false
                    return
                }
                do {
                    self.installed = try HomebrewParser.parseInfoCommandOutput(output).map(self.packageEnriched)
                    self.searchResults = HomebrewSearchResults.reconciled(self.searchResults,
                                                                         installed: self.installed)
                    self.installedCaskRecords = HomebrewParser.parseInstalledCaskRecords(output)
                    self.installedCaskRecordsFetchedAt = Date()
                    self.didOpenInstaller = false
                    if let selected = self.selectedPackage {
                        self.selectedPackage = self.packageEnriched(self.installed.first { $0.id == selected.id } ?? selected)
                    }
                    self.refreshOutdated(brewPath: brewPath)
                } catch {
                    self.errorMessage = error.localizedDescription
                    self.outdatedGeneration += 1
                    self.outdatedPackagesByID = [:]
                    self.isLoadingOutdated = false
                }
            }
        }
    }

    package func search(query: String, kind: HomebrewPackageKind) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        guard let brewPath = brewPath ?? detectBrewPath() else {
            self.brewPath = nil
            searchResults = []
            return
        }
        self.brewPath = brewPath
        searchGeneration += 1
        let generation = searchGeneration
        currentSearchKind = kind
        isSearching = true
        errorMessage = nil
        let command = HomebrewCommandBuilder.search(brewPath: brewPath, kind: kind, query: trimmed)
        run(command) { [weak self] status, output in
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.searchGeneration else { return }
                self.isSearching = false
                if status == 0 {
                    let packages = HomebrewParser.parseSearchOutput(output,
                                                                    kind: kind,
                                                                    installed: self.installed)
                    self.searchResults = self.packagesEnriched(packages, kind: kind)
                    if !packages.isEmpty {
                        self.loadPopularityIfNeeded(kind: kind)
                    }
                } else if output.localizedCaseInsensitiveContains("No formulae or casks found") {
                    self.searchResults = []
                } else {
                    self.searchResults = []
                    self.errorMessage = output.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }

    package func select(_ package: HomebrewPackage) {
        selectedPackage = package
        guard let brewPath = brewPath ?? detectBrewPath() else { return }
        detailsGeneration += 1
        let generation = detailsGeneration
        isLoadingDetails = true
        errorMessage = nil
        let command = HomebrewCommandBuilder.details(brewPath: brewPath, package: package)
        run(command) { [weak self] status, output in
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.detailsGeneration else { return }
                self.isLoadingDetails = false
                guard status == 0 else {
                    if let tap = HomebrewCommandBuilder.untrustedTapName(fromOutput: output) {
                        self.presentUntrustedTap(tap) { [weak self] in self?.select(package) }
                    } else {
                        self.errorMessage = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    return
                }
                do {
                    if let detail = try HomebrewParser.parseInfoCommandOutput(output).first {
                        self.selectedPackage = self.packageEnriched(detail)
                    }
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    package func clearSelection() {
        detailsGeneration += 1
        selectedPackage = nil
        isLoadingDetails = false
    }

    package func install(_ package: HomebrewPackage) {
        perform(.install, package: package)
    }

    package func uninstall(_ package: HomebrewPackage) {
        perform(.uninstall, package: package)
    }

    /// Looks up whether Homebrew owns this exact app bundle. The cached
    /// installed catalog is reused when fresh; otherwise one read-only command
    /// answers every concurrent request for the same path.
    package func packageManagingApplication(at url: URL,
                                    completion: @escaping (HomebrewPackage?) -> Void) {
        let path = url.standardizedFileURL.path
        if let fetchedAt = installedCaskRecordsFetchedAt,
           Date().timeIntervalSince(fetchedAt) < 60 {
            completion(HomebrewOwnershipSupport.packageManagingApplication(
                atPath: path,
                installed: installedCaskRecords
            ))
            return
        }
        if ownershipLoads[path] != nil {
            ownershipLoads[path]?.append(completion)
            return
        }
        ownershipLoads[path] = [completion]
        guard let brewPath = brewPath ?? detectBrewPath() else {
            finishOwnershipLoad(path: path, package: nil)
            return
        }
        self.brewPath = brewPath
        run(HomebrewCommandBuilder.installed(brewPath: brewPath)) { [weak self] status, output in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let records = status == 0 ? HomebrewParser.parseInstalledCaskRecords(output) : []
                if status == 0 {
                    self.installedCaskRecords = records
                    self.installedCaskRecordsFetchedAt = Date()
                }
                let package = HomebrewOwnershipSupport.packageManagingApplication(
                    atPath: path,
                    installed: records
                )
                self.finishOwnershipLoad(path: path, package: package)
            }
        }
    }

    package func upgrade(_ package: HomebrewPackage) {
        perform(.upgrade, package: package)
    }

    package func upgradeAll() {
        perform(.upgradeAll, package: nil)
    }

    /// Upgrades exactly the casks asked for, through the same single
    /// operation lane as every other Homebrew action, so the app never runs
    /// two package commands at once. Used by the app update list, where the
    /// person picks which apps to update.
    package func upgradeCasks(_ tokens: [String]) {
        guard operation == nil,
              let brewPath = brewPath ?? detectBrewPath(),
              let command = HomebrewCommandBuilder.upgradeCasks(brewPath: brewPath, tokens: tokens) else {
            return
        }
        perform(.upgradeAll, package: nil, command: command)
    }

    package func updateHomebrew() {
        perform(.updateHomebrew, package: nil)
    }

    package func cancelOperation() {
        guard operation != nil else { return }
        cancelRequested = true
        if let activeProcess {
            Self.stop(activeProcess)
        }
        appendLog("\nCancelled.\n")
    }

    package func clearLog() {
        completedOperationCleanup?.cancel()
        completedOperationCleanup = nil
        log = ""
        terminalFallbackCommand = nil
        if operation == nil {
            operationStatus = nil
        }
    }

    package func openTerminalFallback() {
        guard let command = terminalFallbackCommand else { return }
        openTerminal(command: command)
    }

    package func openHomebrewInstaller() {
        errorMessage = nil
        if openTerminal(command: HomebrewCommandBuilder.installerCommand) {
            didOpenInstaller = true
        }
    }

    package func openShellConfiguration() {
        guard let brewPath = brewPath ?? detectBrewPath() else { return }
        self.brewPath = brewPath
        errorMessage = nil
        let command = HomebrewCommandBuilder.shellConfigCommand(brewPath: brewPath)
        if openTerminal(command: command) {
            didOpenShellConfig = true
        }
    }

    package func refreshShellConfigurationStatus() {
        guard let brewPath = brewPath ?? detectBrewPath() else {
            isShellConfigured = true
            shellConfigProfilePath = nil
            didOpenShellConfig = false
            return
        }
        updateShellConfigStatus(brewPath: brewPath)
    }

    @discardableResult
    private func openTerminal(command: String) -> Bool {
        let source = """
        tell application "Terminal"
            activate
            do script \(appleScriptString(command))
        end tell
        """
        // In-process Apple Events (see AppleScriptRunner): the Terminal Automation
        // consent is attributed to this app and re-requested if it was lost,
        // instead of a fragile osascript subprocess. Same permission as before.
        let result = AppleScriptRunner.run(source)
        if !result.ok {
            errorMessage = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return false
        }
        return true
    }

    private func perform(_ action: HomebrewOperation.Action,
                         package: HomebrewPackage?,
                         command commandOverride: HomebrewCommand? = nil) {
        guard operation == nil else { return }
        guard let brewPath = brewPath ?? detectBrewPath() else { return }
        guard let command = commandOverride
                ?? standardCommand(for: action, package: package, brewPath: brewPath) else { return }
        operation = HomebrewOperation(action: action, package: package)
        operationStatus = HomebrewOperationStatus(action: action,
                                                  package: package,
                                                  phase: initialPhase(for: action),
                                                  result: .running,
                                                  progressFraction: nil,
                                                  startedAt: Date(),
                                                  finishedAt: nil,
                                                  lastActivity: nil)
        terminalFallbackCommand = nil
        errorMessage = nil
        clearUntrustedTap()
        cancelRequested = false
        completedOperationCleanup?.cancel()
        completedOperationCleanup = nil
        log = ""
        runStreaming(command,
                     onOutput: { [weak self] chunk in
                         self?.appendLog(chunk)
                         self?.updateOperationStatus(from: chunk, action: action)
                     }) { [weak self] status, output in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.activeProcess = nil
                self.operation = nil
                let end = HomebrewOperationEnd(status: status, cancelRequested: self.cancelRequested,
                                               output: output)
                switch end {
                case .succeeded:
                    self.markOperationComplete(result: .succeeded,
                                               phase: .refreshing,
                                               activity: nil)
                    if action.clearsSelectionOnSuccess {
                        if self.selectedPackage?.id == package?.id {
                            self.clearSelection()
                        }
                    }
                case .cancelled:
                    self.markOperationComplete(result: .cancelled,
                                               phase: self.operationStatus?.phase ?? .finalizing,
                                               activity: nil)
                case .needsTerminal:
                    self.terminalFallbackCommand = HomebrewCommandBuilder.shellCommand(command)
                    self.markOperationComplete(result: .needsTerminal,
                                               phase: self.operationStatus?.phase ?? .finalizing,
                                               activity: HomebrewProgressParser.visibleError(from: output))
                case .untrustedTap(let tap):
                    self.presentUntrustedTap(tap) { [weak self] in self?.perform(action, package: package) }
                    self.markOperationComplete(result: .failed,
                                               phase: self.operationStatus?.phase ?? .finalizing,
                                               activity: nil)
                case .failed:
                    let message = HomebrewProgressParser.visibleError(from: output)
                    self.errorMessage = message.isEmpty ? output.trimmingCharacters(in: .whitespacesAndNewlines) : message
                    self.markOperationComplete(result: .failed,
                                               phase: self.operationStatus?.phase ?? .finalizing,
                                               activity: self.errorMessage)
                }
                // Without a re-read the panel keeps showing the versions from
                // before a run that moved most of them (see `refresh`).
                if let refresh = end.refresh {
                    self.refreshInstalled(clearingError: refresh == .clearingError)
                }
                if end == .succeeded, !action.clearsSelectionOnSuccess, let package {
                    self.select(package)
                }
                self.cancelRequested = false
            }
        }
    }

    private func finishOwnershipLoad(path: String, package: HomebrewPackage?) {
        let completions = ownershipLoads.removeValue(forKey: path) ?? []
        completions.forEach { $0(package) }
    }

    private func standardCommand(for action: HomebrewOperation.Action,
                                 package: HomebrewPackage?,
                                 brewPath: String) -> HomebrewCommand? {
        switch action {
        case .install, .uninstall, .upgrade:
            guard let package,
                  HomebrewCommandBuilder.isValidToken(package.name) else { return nil }
            switch action {
            case .install: return HomebrewCommandBuilder.install(brewPath: brewPath, package: package)
            case .uninstall: return HomebrewCommandBuilder.uninstall(brewPath: brewPath, package: package)
            default: return HomebrewCommandBuilder.upgrade(brewPath: brewPath, package: package)
            }
        case .upgradeAll:
            return HomebrewCommandBuilder.upgradeAll(brewPath: brewPath)
        case .updateHomebrew:
            return HomebrewCommandBuilder.update(brewPath: brewPath)
        }
    }

    private func updateOperationStatus(from chunk: String, action: HomebrewOperation.Action) {
        guard var status = operationStatus, status.isActive else { return }
        if let phase = HomebrewProgressParser.phase(in: chunk, action: action) {
            status.phase = phase
        }
        if let progress = HomebrewProgressParser.progressFraction(in: chunk) {
            status.progressFraction = progress
        }
        if let activity = HomebrewProgressParser.activity(in: chunk) {
            status.lastActivity = activity
        }
        operationStatus = status
    }

    private func initialPhase(for action: HomebrewOperation.Action) -> HomebrewOperationPhase {
        switch action {
        case .install, .upgrade, .upgradeAll, .updateHomebrew:
            return .preparing
        case .uninstall:
            return .uninstalling
        }
    }

    private func updateShellConfigStatus(brewPath: String) {
        let expectedLine = HomebrewCommandBuilder.shellEnvLine(brewPath: brewPath)
        let primaryPath = HomebrewCommandBuilder.shellProfilePath()
        let paths = HomebrewCommandBuilder.shellProfilePathsToCheck()
        shellConfigProfilePath = primaryPath
        isShellConfigured = paths.contains { path in
            guard let contents = try? String(contentsOfFile: path) else { return false }
            return contents.contains(expectedLine)
        }
        if isShellConfigured {
            didOpenShellConfig = false
        }
    }

    private func markOperationComplete(result: HomebrewOperationResult,
                                       phase: HomebrewOperationPhase,
                                       activity: String?) {
        guard var status = operationStatus else { return }
        status.result = result
        status.phase = phase
        status.finishedAt = Date()
        if result == .succeeded {
            status.progressFraction = 1
        }
        if let activity, !activity.isEmpty {
            status.lastActivity = activity
        }
        operationStatus = status
        scheduleCompletedOperationCleanup(result: result,
                                          targetID: status.targetID,
                                          finishedAt: status.finishedAt)
    }

    private func loadPopularityIfNeeded(kind: HomebrewPackageKind) {
        if popularityCache[kind]?.isFresh == true {
            applyPopularityToCurrentSearch(kind: kind)
            return
        }
        guard !popularityLoads.contains(kind) else { return }
        popularityLoads.insert(kind)
        isLoadingPopularity = true
        let url = HomebrewAnalytics.url(kind: kind)
        analyticsSession.dataTask(with: url) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.popularityLoads.remove(kind)
                self.isLoadingPopularity = !self.popularityLoads.isEmpty
                guard let data,
                      let values = try? HomebrewAnalytics.parse(data, kind: kind) else { return }
                self.popularityCache[kind] = PopularityCacheEntry(values: values, fetchedAt: Date())
                self.applyPopularityToCurrentSearch(kind: kind)
            }
        }.resume()
    }

    private func applyPopularityToCurrentSearch(kind: HomebrewPackageKind) {
        guard currentSearchKind == kind else { return }
        searchResults = packagesEnriched(searchResults, kind: kind)
        if let selectedPackage, selectedPackage.kind == kind {
            self.selectedPackage = packageEnriched(selectedPackage)
        }
    }

    private func packagesApplyingPopularity(_ packages: [HomebrewPackage],
                                            kind: HomebrewPackageKind) -> [HomebrewPackage] {
        guard let cache = popularityCache[kind], cache.isFresh else {
            return packages
        }
        return HomebrewAnalytics.enrichAndSort(packages, popularity: cache.values)
    }

    private func packageApplyingPopularity(_ package: HomebrewPackage) -> HomebrewPackage {
        guard let popularity = popularityCache[package.kind]?.values[package.name] else {
            return package
        }
        var copy = package
        copy.popularity = popularity
        return copy
    }

    private func refreshOutdated(brewPath: String) {
        outdatedGeneration += 1
        let generation = outdatedGeneration
        isLoadingOutdated = true
        let command = HomebrewCommandBuilder.outdated(brewPath: brewPath)
        run(command) { [weak self] status, output in
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.outdatedGeneration else { return }
                self.isLoadingOutdated = false
                guard status == 0,
                      let updates = try? HomebrewParser.parseOutdatedCommandOutput(output) else {
                    self.outdatedPackagesByID = [:]
                    self.applyOutdatedToCurrentPackages()
                    return
                }
                self.outdatedPackagesByID = updates
                self.applyOutdatedToCurrentPackages()
            }
        }
    }

    private func applyOutdatedToCurrentPackages() {
        installed = installed.map(packageApplyingOutdated)
        searchResults = searchResults.map(packageApplyingOutdated)
        if let selectedPackage {
            self.selectedPackage = packageApplyingOutdated(selectedPackage)
        }
    }

    private func packagesEnriched(_ packages: [HomebrewPackage],
                                  kind: HomebrewPackageKind) -> [HomebrewPackage] {
        packagesApplyingPopularity(packages, kind: kind).map(packageApplyingOutdated)
    }

    private func packageEnriched(_ package: HomebrewPackage) -> HomebrewPackage {
        packageApplyingOutdated(packageApplyingPopularity(package))
    }

    private func packageApplyingOutdated(_ package: HomebrewPackage) -> HomebrewPackage {
        var copy = package
        copy.update = outdatedPackagesByID[package.id]
        return copy
    }

    private func scheduleCompletedOperationCleanup(result: HomebrewOperationResult,
                                                   targetID: String,
                                                   finishedAt: Date?) {
        completedOperationCleanup?.cancel()
        guard result != .running,
              let finishedAt else { return }
        let delay: TimeInterval
        let clearsWholeStatus: Bool
        switch result {
        case .succeeded:
            delay = 8
            clearsWholeStatus = true
        case .cancelled:
            delay = 6
            clearsWholeStatus = true
        case .failed, .needsTerminal:
            delay = 20
            clearsWholeStatus = false
        case .running:
            return
        }

        let item = DispatchWorkItem { [weak self] in
            guard let self,
                  self.operation == nil,
                  self.operationStatus?.targetID == targetID,
                  self.operationStatus?.finishedAt == finishedAt else { return }
            self.log = ""
            if clearsWholeStatus {
                self.terminalFallbackCommand = nil
                self.operationStatus = nil
            }
            self.completedOperationCleanup = nil
        }
        completedOperationCleanup = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// One click on the trust card: marks the tap as trusted for Homebrew
    /// and picks the interrupted work back up.
    package func trustTapAndContinue() {
        guard let tap = untrustedTap, !isTrustingTap,
              HomebrewCommandBuilder.isValidToken(tap),
              let brewPath = brewPath ?? detectBrewPath() else { return }
        isTrustingTap = true
        let retry = untrustedTapRetry
        run(HomebrewCommandBuilder.trustTap(brewPath: brewPath, tap: tap)) { [weak self] status, output in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isTrustingTap = false
                guard status == 0 else {
                    self.errorMessage = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    return
                }
                self.clearUntrustedTap()
                retry?()
            }
        }
    }

    private func presentUntrustedTap(_ tap: String, retry: @escaping @MainActor @Sendable () -> Void) {
        untrustedTap = tap
        untrustedTapRetry = retry
        errorMessage = nil
    }

    private func clearUntrustedTap() {
        untrustedTap = nil
        untrustedTapRetry = nil
    }

    private func detectBrewPath() -> String? {
        locateBrew()
    }

    /// Timeout for read-only Homebrew commands (info, search, outdated).
    /// These are normally fast, but a hung NFS share or locked database can
    /// make them stall indefinitely.
    nonisolated private static let brewReadTimeout: TimeInterval = 30
    /// Install/upgrade/uninstall run on the same serial queue as every read, so a
    /// hung one must end eventually. A big download, a source build and a copy into
    /// Applications are all slow but never silent, so the bound is on silence: a cap
    /// on total time would end work that was still going.
    nonisolated private static let brewSilenceTimeout: TimeInterval = 15 * 60
    nonisolated private static let processTerminationGrace: TimeInterval = 2

    /// Waits for a streaming command to exit, never with `waitUntilExit`: the
    /// bound is on silence (see `brewSilenceTimeout`), so once `silence` has
    /// reached `silenceLimit` the command is stopped and the wait ends.
    nonisolated package static func awaitExit(_ finished: DispatchSemaphore,
                                              silenceLimit: TimeInterval,
                                              silence: () -> TimeInterval,
                                              stop: () -> Void) {
        while finished.wait(timeout: .now() + silenceLimit) == .timedOut {
            if silence() >= silenceLimit {
                stop()
                break
            }
        }
    }

    /// SIGTERM is cooperative. Escalate only when a command ignores it so a
    /// cancelled or timed-out operation cannot keep the serial queue forever.
    nonisolated private static func stop(_ process: Process, finished: DispatchSemaphore? = nil) {
        guard process.isRunning else { return }
        process.terminate()
        if let finished {
            if finished.wait(timeout: .now() + processTerminationGrace) == .timedOut,
               process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + processTerminationGrace)
            }
            return
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + processTerminationGrace) {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    /// Called on `workQueue` only: the first `HomebrewEnvironment.forBrew` read
    /// waits on the login shell.
    nonisolated private static func makeProcess(_ command: HomebrewCommand) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.environment = HomebrewEnvironment.forBrew
        return process
    }

    /// `completion` runs on `workQueue`; every caller hops to the main queue itself.
    private func run(_ command: HomebrewCommand,
                     completion: @escaping @Sendable (_ status: Int32, _ output: String) -> Void) {
        workQueue.async {
            let process = Self.makeProcess(command)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let output = HomebrewProcessOutput()
            let drained = DispatchSemaphore(value: 0)
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    drained.signal()
                    return
                }
                output.append(chunk)
            }
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                completion(-1, error.localizedDescription)
                return
            }
            if finished.wait(timeout: .now() + Self.brewReadTimeout) == .timedOut {
                Self.stop(process, finished: finished)
            }
            _ = drained.wait(timeout: .now() + 1)
            pipe.fileHandleForReading.readabilityHandler = nil
            try? pipe.fileHandleForReading.close()
            completion(process.isRunning ? -1 : process.terminationStatus, output.text)
        }
    }

    /// `onOutput` runs on the main queue, `completion` on `workQueue`.
    private func runStreaming(_ command: HomebrewCommand,
                              onOutput: @escaping @MainActor @Sendable (String) -> Void,
                              completion: @escaping @Sendable (_ status: Int32, _ output: String) -> Void) {
        workQueue.async { [weak self] in
            let process = Self.makeProcess(command)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let output = HomebrewProcessOutput()
            let drained = DispatchSemaphore(value: 0)
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    drained.signal()
                    return
                }
                output.append(data)
                if let chunk = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async { onOutput(chunk) }
                }
            }
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                completion(-1, error.localizedDescription)
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.activeProcess = process
                if self.cancelRequested { Self.stop(process) }
            }
            Self.awaitExit(finished, silenceLimit: Self.brewSilenceTimeout,
                           silence: { output.silence },
                           stop: { Self.stop(process, finished: finished) })
            _ = drained.wait(timeout: .now() + 1)
            pipe.fileHandleForReading.readabilityHandler = nil
            try? pipe.fileHandleForReading.close()
            completion(process.isRunning ? -1 : process.terminationStatus, output.text)
        }
    }

    private func appendLog(_ text: String) {
        log.append(text)
    }

    private func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

/// A brew child's piped output: the readability handler appends on its own
/// thread while `workQueue` reads, and the lock is the only way in.
private final class HomebrewProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var lastOutput = Date()

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(chunk)
        lastOutput = Date()
    }

    /// Time since the last chunk arrived (or since the box was made).
    var silence: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince(lastOutput)
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct PopularityCacheEntry {
    let values: [String: HomebrewPopularity]
    let fetchedAt: Date

    var isFresh: Bool {
        Date().timeIntervalSince(fetchedAt) < 24 * 60 * 60
    }
}
