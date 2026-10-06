// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import VitruvianCore
import VitruvianDesign

/// Scans only the top level of Downloads, surfaces files that macOS itself
/// attributes to WhatsApp, and moves reviewed/eligible items to the Trash.
/// It never reads file contents or reaches into WhatsApp's container.
@MainActor
package final class WhatsAppDownloadManager: ObservableObject {
    package static let shared = WhatsAppDownloadManager()

    package enum Phase: Equatable {
        case idle, scanning, results, cleaning
        case done(moved: Int, bytes: Int64, failed: Int)
        case failed
    }

    package enum AccessStatus: Equatable {
        case unknown, available, denied
    }

    package struct Candidate: Identifiable, Equatable {
        package let id: String
        package let url: URL
        package let size: Int64
        package let downloadedAt: Date
        package let modifiedAt: Date
        package let category: WhatsAppDownloadCategory
        package let managedRoot: URL
        package let allowsDescendants: Bool
        /// Filed away by the organizer: manual review still lists it, the
        /// automation never touches it.
        package let organized: Bool
        package let eligibleForRules: Bool
        package let eligibleForAutomaticCleanup: Bool
        package var excluded: Bool
        package var include: Bool

        package var name: String { url.lastPathComponent }

        // Spelled out because a memberwise initializer never leaves its module.
        package init(id: String, url: URL, size: Int64, downloadedAt: Date, modifiedAt: Date, category: WhatsAppDownloadCategory, managedRoot: URL, allowsDescendants: Bool, organized: Bool, eligibleForRules: Bool, eligibleForAutomaticCleanup: Bool, excluded: Bool, include: Bool) {
            self.id = id
            self.url = url
            self.size = size
            self.downloadedAt = downloadedAt
            self.modifiedAt = modifiedAt
            self.category = category
            self.managedRoot = managedRoot
            self.allowsDescendants = allowsDescendants
            self.organized = organized
            self.eligibleForRules = eligibleForRules
            self.eligibleForAutomaticCleanup = eligibleForAutomaticCleanup
            self.excluded = excluded
            self.include = include
        }
    }

    @Published package private(set) var phase: Phase = .idle
    @Published package private(set) var accessStatus: AccessStatus = .unknown
    @Published package var candidates: [Candidate] = []
    package private(set) var reviewVisible = false

    private let queue = DispatchQueue(label: "com.vitruviansoftware.vitruvian.whatsapp-downloads",
                                      qos: .userInitiated)
    private var operationToken = UUID()

    private init() {}

    package var selectedCount: Int { candidates.filter(\.include).count }
    package var selectedBytes: Int64 { candidates.filter(\.include).reduce(0) { $0 + $1.size } }
    package var eligibleCount: Int { candidates.filter { $0.eligibleForRules && !$0.excluded }.count }
    package var automaticEligibleCount: Int {
        candidates.filter { $0.eligibleForAutomaticCleanup && !$0.excluded }.count
    }
    package var totalBytes: Int64 { candidates.reduce(0) { $0 + $1.size } }

    package var downloadsURL: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    package func reset() {
        operationToken = UUID()
        candidates = []
        phase = .idle
    }

    package func setReviewVisible(_ visible: Bool) {
        reviewVisible = visible
    }

    package func scan() {
        guard phase != .scanning, phase != .cleaning else { return }
        guard let root = downloadsURL else {
            accessStatus = .denied
            phase = .failed
            return
        }

        let token = UUID()
        operationToken = token
        candidates = []
        phase = .scanning

        let settings = Self.settingsSnapshot()
        let excluded = Set(UserDefaults.standard.stringArray(
            forKey: DefaultsKey.whatsAppDownloadsExclusions) ?? [])

        queue.async { [weak self] in
            let result: Result<[Candidate], Error>
            do {
                let sourceURLs = try FileManager.default.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: Array(Self.resourceKeys),
                    options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
                var locations = sourceURLs.map { ($0, root, false, false) }
                for path in WhatsAppDownloadOrganizer.managedDestinationPaths() {
                    let url = URL(fileURLWithPath: path).standardizedFileURL
                    if !WhatsAppDownloadSupport.isDirectChild(url, of: root) {
                        // Organized files stay reviewable by hand but are
                        // never trashed automatically: the person filed them
                        // away to keep them, and the page only promises the
                        // automation watches the top level of Downloads.
                        locations.append((url, url.deletingLastPathComponent(), false, true))
                    }
                }
                let now = Date()
                let found = locations.compactMap { url, managedRoot, recursive, organized in
                    Self.candidate(at: url, root: managedRoot,
                                   allowsDescendants: recursive, organized: organized,
                                   settings: settings, excluded: excluded, now: now)
                }.sorted {
                    if $0.downloadedAt != $1.downloadedAt { return $0.downloadedAt > $1.downloadedAt }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                result = .success(found)
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.operationToken == token else { return }
                switch result {
                case let .success(found):
                    UserDefaults.standard[Preferences.whatsAppDownloadsAccessConfirmed] = true
                    self.accessStatus = .available
                    self.candidates = found
                    self.phase = .results
                case .failure:
                    UserDefaults.standard[Preferences.whatsAppDownloadsAccessConfirmed] = false
                    self.accessStatus = .denied
                    self.candidates = []
                    self.phase = .failed
                }
            }
        }
    }

    package func setInclude(_ include: Bool, for id: String) {
        guard let index = candidates.firstIndex(where: { $0.id == id }),
              !candidates[index].excluded else { return }
        candidates[index].include = include
    }

    package func selectRules() {
        for index in candidates.indices {
            candidates[index].include = candidates[index].eligibleForRules
                && !candidates[index].excluded
        }
    }

    package func selectAutomaticRules() {
        for index in candidates.indices {
            candidates[index].include = candidates[index].eligibleForAutomaticCleanup
                && !candidates[index].excluded
        }
    }

    package func exclude(_ id: String) {
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        var exclusions = Set(UserDefaults.standard.stringArray(
            forKey: DefaultsKey.whatsAppDownloadsExclusions) ?? [])
        exclusions.insert(id)
        UserDefaults.standard.set(Array(exclusions).sorted(),
                                  forKey: DefaultsKey.whatsAppDownloadsExclusions)
        candidates[index].excluded = true
        candidates[index].include = false
    }

    package func removeExclusion(_ id: String) {
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        var exclusions = Set(UserDefaults.standard.stringArray(
            forKey: DefaultsKey.whatsAppDownloadsExclusions) ?? [])
        exclusions.remove(id)
        UserDefaults.standard.set(Array(exclusions).sorted(),
                                  forKey: DefaultsKey.whatsAppDownloadsExclusions)
        candidates[index].excluded = false
        candidates[index].include = candidates[index].eligibleForRules
    }

    package func reveal(_ id: String) {
        guard let candidate = candidates.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([candidate.url])
    }

    package func cleanSelected(automatic: Bool) {
        let chosen = candidates.filter(\.include)
        guard !chosen.isEmpty, downloadsURL != nil else { return }
        phase = .cleaning
        let token = UUID()
        operationToken = token
        let settings = Self.settingsSnapshot()

        queue.async { [weak self] in
            var movedIDs = Set<String>()
            var movedBytes: Int64 = 0
            var failed = 0
            let fm = FileManager.default

            for original in chosen {
                guard let current = Self.candidate(at: original.url, root: original.managedRoot,
                                                   allowsDescendants: original.allowsDescendants,
                                                   organized: original.organized,
                                                   settings: settings,
                                                   excluded: [], now: Date()),
                      current.id == original.id else {
                    failed += 1
                    continue
                }
                if automatic && !current.eligibleForAutomaticCleanup { continue }
                do {
                    try fm.trashItem(at: current.url, resultingItemURL: nil)
                    movedIDs.insert(current.id)
                    movedBytes += current.size
                } catch {
                    failed += 1
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.operationToken == token else { return }
                self.candidates.removeAll { movedIDs.contains($0.id) }
                self.recordCleanup(moved: movedIDs.count, bytes: movedBytes,
                                   failed: failed, automatic: automatic)
                self.phase = .done(moved: movedIDs.count, bytes: movedBytes, failed: failed)
            }
        }
    }

    /// Records a successful scheduled pass that had nothing eligible. This is
    /// still useful proof that the automation is alive.
    package func completeAutomaticWithoutCleaning() {
        recordCleanup(moved: 0, bytes: 0, failed: 0, automatic: true)
        phase = .done(moved: 0, bytes: 0, failed: 0)
    }

    private func recordCleanup(moved: Int, bytes: Int64, failed: Int, automatic: Bool) {
        let defaults = UserDefaults.standard
        defaults[Preferences.whatsAppDownloadsLastCleanup] = Date().timeIntervalSince1970
        defaults[Preferences.whatsAppDownloadsLastCleanupCount] = moved
        defaults[Preferences.whatsAppDownloadsLastCleanupBytes] = Int(bytes)
        defaults[Preferences.whatsAppDownloadsLastCleanupFailed] = failed
        defaults[Preferences.whatsAppDownloadsLastCleanupAutomatic] = automatic
    }

    private struct SettingsSnapshot {
        let retentionDays: Int
        let categories: Set<WhatsAppDownloadCategory>
        let includeExisting: Bool
        let automaticStartDate: Date?
    }

    private static func settingsSnapshot() -> SettingsSnapshot {
        let defaults = UserDefaults.standard
        let start = defaults[Preferences.whatsAppDownloadsAutomaticStartDate]
        return SettingsSnapshot(
            retentionDays: WhatsAppDownloadSupport.sanitizedRetentionDays(
                defaults[Preferences.whatsAppDownloadsRetentionDays]),
            categories: WhatsAppDownloadSupport.decodedCategories(
                defaults[Preferences.whatsAppDownloadsCategories]),
            includeExisting: defaults[Preferences.whatsAppDownloadsIncludeExisting],
            automaticStartDate: start > 0 ? Date(timeIntervalSince1970: start) : nil)
    }

    nonisolated private static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey, .isDirectoryKey,
        .isPackageKey, .isHiddenKey, .fileSizeKey, .contentTypeKey,
        .quarantinePropertiesKey, .addedToDirectoryDateKey, .creationDateKey,
        .contentModificationDateKey,
    ]

    nonisolated private static func candidate(at url: URL,
                                  root: URL,
                                  allowsDescendants: Bool = false,
                                  organized: Bool = false,
                                  settings: SettingsSnapshot,
                                  excluded: Set<String>,
                                  now: Date) -> Candidate? {
        let standardizedURL = url.standardizedFileURL
        let standardizedRoot = root.standardizedFileURL
        let isInManagedLocation = allowsDescendants
            ? WhatsAppDownloadSupport.isDescendant(standardizedURL, of: standardizedRoot)
            : WhatsAppDownloadSupport.isDirectChild(standardizedURL, of: standardizedRoot)
        guard isInManagedLocation,
              !WhatsAppDownloadSupport.isIncompleteFile(extension: standardizedURL.pathExtension),
              let values = try? standardizedURL.resourceValues(forKeys: resourceKeys),
              values.isRegularFile == true,
              values.isDirectory != true,
              values.isPackage != true,
              values.isSymbolicLink != true,
              values.isAliasFile != true,
              values.isHidden != true,
              let quarantine = values.quarantineProperties,
              WhatsAppDownloadSupport.isWhatsAppAgent(
                quarantine["LSQuarantineAgentName"] as? String),
              let downloadedAt = (quarantine["LSQuarantineTimeStamp"] as? Date)
                ?? values.addedToDirectoryDate ?? values.creationDate,
              let fingerprint = fingerprint(for: standardizedURL)
        else { return nil }

        let modifiedAt = values.contentModificationDate ?? downloadedAt
        let category = WhatsAppDownloadSupport.category(
            contentTypeIdentifier: values.contentType?.identifier,
            extension: standardizedURL.pathExtension)
        let rules = WhatsAppDownloadSupport.isEligibleForRules(
            category: category, downloadedAt: downloadedAt, modifiedAt: modifiedAt,
            now: now, retentionDays: settings.retentionDays,
            enabledCategories: settings.categories)
        let automatic = !organized && WhatsAppDownloadSupport.isEligibleForAutomaticCleanup(
            category: category, downloadedAt: downloadedAt, modifiedAt: modifiedAt,
            now: now, retentionDays: settings.retentionDays,
            enabledCategories: settings.categories,
            includeExisting: settings.includeExisting,
            automaticStartDate: settings.automaticStartDate)
        let isExcluded = excluded.contains(fingerprint)
        return Candidate(id: fingerprint, url: standardizedURL,
                         size: Int64(values.fileSize ?? 0),
                         downloadedAt: downloadedAt, modifiedAt: modifiedAt,
                         category: category, managedRoot: standardizedRoot,
                         allowsDescendants: allowsDescendants, organized: organized,
                         eligibleForRules: rules,
                         eligibleForAutomaticCleanup: automatic,
                         excluded: isExcluded, include: rules && !isExcluded)
    }

    nonisolated private static func fingerprint(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else { return nil }
        return "\(device):\(inode)"
    }
}
