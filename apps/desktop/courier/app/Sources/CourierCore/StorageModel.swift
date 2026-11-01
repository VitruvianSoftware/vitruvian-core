// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

public enum StorageCleanupAgeChoice: Int, CaseIterable, Codable, Sendable, Identifiable {
    case oneWeek = 7
    case oneMonth = 30
    case threeMonths = 90
    case oneYear = 365
    case allTime = 0

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .oneWeek: String(localized: "Delete media older than 1 week")
        case .oneMonth: String(localized: "Delete media older than 1 month")
        case .threeMonths: String(localized: "Delete media older than 3 months")
        case .oneYear: String(localized: "Delete media older than 1 year")
        case .allTime: String(localized: "Delete Media…")
        }
    }

    public var shortDurationLabel: String {
        switch self {
        case .oneWeek: String(localized: "1 week")
        case .oneMonth: String(localized: "1 month")
        case .threeMonths: String(localized: "3 months")
        case .oneYear: String(localized: "1 year")
        case .allTime: String(localized: "All time")
        }
    }

    public var olderThanMS: Int64? {
        rawValue > 0 ? Int64(rawValue) * 86_400_000 : nil
    }
}

@MainActor
public final class StorageModel: ObservableObject {
    @Published public private(set) var usage: StorageUsageResult?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isCleaning: Bool = false
    @Published public var selectedAgeChoice: StorageCleanupAgeChoice = .oneMonth
    @Published public var roomFilterQuery: String = ""
    @Published public private(set) var lastStatusMessage: String?
    @Published public private(set) var lastErrorMessage: String?

    public let appModel: AppModel
    private let explicitLifecycle: SystemLifecycleModel?

    public init(appModel: AppModel, lifecycle: SystemLifecycleModel? = nil) {
        self.appModel = appModel
        self.explicitLifecycle = lifecycle
    }

    public var effectiveLifecycle: SystemLifecycleModel {
        explicitLifecycle ?? appModel.lifecycle ?? AppLockGate.shared.lifecycle
    }

    private var canMutateOrRead: Bool {
        AppLockGate.shared.canPerform(.settingsChange, lifecycle: effectiveLifecycle)
    }

    public var filteredRooms: [RoomStorageUsage] {
        guard let rooms = usage?.rooms else { return [] }
        let trimmed = roomFilterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rooms }
        return rooms.filter { room in
            if room.name.localizedCaseInsensitiveContains(trimmed) { return true }
            if room.network.localizedCaseInsensitiveContains(trimmed) { return true }
            if let networkDisplay = NetworkNames.displayName(of: room.network),
               networkDisplay.localizedCaseInsensitiveContains(trimmed) {
                return true
            }
            return false
        }
    }

    public func setUsageForTesting(_ usage: StorageUsageResult) {
        self.usage = usage
    }

    public func refresh() async {
        guard canMutateOrRead else { return }
        guard let client = appModel.client else { return }
        isLoading = true
        lastErrorMessage = nil
        defer { isLoading = false }
        do {
            let result: StorageUsageResult = try await client.call("storage.usage", Empty())
            guard canMutateOrRead else { return }
            usage = result
        } catch {
            lastErrorMessage = EngineErrorText.text(
                for: error,
                fallback: String(localized: "Couldn’t read local storage usage.")
            )
        }
    }

    public func clearMedia(olderThan choice: StorageCleanupAgeChoice) async {
        guard canMutateOrRead else { return }
        guard let client = appModel.client else { return }
        isCleaning = true
        lastErrorMessage = nil
        defer { isCleaning = false }
        do {
            let params = StorageCleanupParams(olderThanMS: choice.olderThanMS)
            let result: StorageCleanupResult = try await client.call("storage.cleanup", params)
            let formatted = Self.formatBytes(result.freedBytes)
            lastStatusMessage = String(localized: "Cleared \(formatted) of cached media")
            await refresh()
        } catch {
            lastErrorMessage = EngineErrorText.text(
                for: error,
                fallback: String(localized: "Couldn’t delete cached media.")
            )
        }
    }

    public func clearMedia(forRoomID roomID: String) async {
        guard canMutateOrRead else { return }
        let trimmed = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let client = appModel.client else { return }
        isCleaning = true
        lastErrorMessage = nil
        defer { isCleaning = false }
        do {
            let params = StorageCleanupParams(roomIDs: [trimmed])
            let result: StorageCleanupResult = try await client.call("storage.cleanup", params)
            let formatted = Self.formatBytes(result.freedBytes)
            lastStatusMessage = String(localized: "Cleared \(formatted) of cached media")
            await refresh()
        } catch {
            lastErrorMessage = EngineErrorText.text(
                for: error,
                fallback: String(localized: "Couldn’t delete media in this chat.")
            )
        }
    }

    public func clearAllCache() async {
        guard canMutateOrRead else { return }
        guard let client = appModel.client else { return }
        isCleaning = true
        lastErrorMessage = nil
        defer { isCleaning = false }
        do {
            let params = StorageCleanupParams(includeStickers: true)
            let result: StorageCleanupResult = try await client.call("storage.cleanup", params)
            let formatted = Self.formatBytes(result.freedBytes)
            lastStatusMessage = String(localized: "Cleared \(formatted) of cached media")
            await refresh()
        } catch {
            lastErrorMessage = EngineErrorText.text(
                for: error,
                fallback: String(localized: "Couldn’t clear media cache.")
            )
        }
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        let clamped = max(0, bytes)
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: clamped)
    }
}
