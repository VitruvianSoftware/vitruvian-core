// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// `StoragePrefsSubView.tsx`, `StorageOverviewChart.tsx`, and `StorageByRoomList.tsx`.
public struct StorageSettingsPane: View {
    @ObservedObject public var model: StorageModel
    @ObservedObject public var lifecycle: SystemLifecycleModel
    public var highlightedSettingID: String? = nil

    @State private var isConfirmingBulkCleanup = false
    @State private var isConfirmingClearAllCache = false
    @State private var roomPendingCleanup: RoomStorageUsage?

    @MainActor
    public init(
        model: StorageModel,
        lifecycle: SystemLifecycleModel? = nil,
        highlightedSettingID: String? = nil
    ) {
        self.model = model
        self.lifecycle = lifecycle ?? model.effectiveLifecycle
        self.highlightedSettingID = highlightedSettingID
    }

    public var body: some View {
        ScrollViewReader { proxy in
            Form {
                overviewSection
                cleanupSection
                byRoomSection
            }
            .formStyle(.grouped)
            .disabled(lifecycle.isLocked)
            .task {
                if model.usage == nil {
                    await model.refresh()
                }
            }
            .onChange(of: highlightedSettingID, initial: true) { _, targetID in
                if let targetID {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                }
            }
            .confirmationDialog(
                model.selectedAgeChoice.label,
                isPresented: $isConfirmingBulkCleanup,
                titleVisibility: .visible
            ) {
                Button(model.selectedAgeChoice.label, role: .destructive) {
                    let choice = model.selectedAgeChoice
                    Task { await model.clearMedia(olderThan: choice) }
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                Text(CommandSet.deleteMediaConfirmation)
            }
            .confirmationDialog(
                CommandSet.deleteMediaTitle,
                isPresented: $isConfirmingClearAllCache,
                titleVisibility: .visible
            ) {
                Button(CommandSet.deleteMediaTitle, role: .destructive) {
                    Task { await model.clearAllCache() }
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                Text(CommandSet.deleteMediaConfirmation)
            }
            .confirmationDialog(
                CommandSet.deleteMediaInThisChatTitle,
                isPresented: Binding(
                    get: { roomPendingCleanup != nil },
                    set: { shown in if !shown { roomPendingCleanup = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let room = roomPendingCleanup {
                    Button(CommandSet.deleteMediaInThisChatTitle, role: .destructive) {
                        let targetID = room.roomID
                        roomPendingCleanup = nil
                        Task { await model.clearMedia(forRoomID: targetID) }
                    }
                }
                Button(String(localized: "Cancel"), role: .cancel) {
                    roomPendingCleanup = nil
                }
            } message: {
                Text(CommandSet.deleteMediaConfirmation)
            }
        }
    }

    private var overviewSection: some View {
        Section(String(localized: "Disk Usage on This Mac")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SettingsNavigationModel.title(for: "storage.overview"))
                            .font(.subheadline.weight(.semibold))
                        Text(String(localized: "Photos, videos, voice notes, files, and message history stored locally on this Mac."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .disabled(model.isLoading || model.isCleaning)
                }

                if let usage = model.usage {
                    StorageOverviewChartView(usage: usage)
                } else {
                    Text(String(localized: "Calculating local disk usage…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }

                if let status = model.lastStatusMessage {
                    Label(status, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
                if let err = model.lastErrorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .settingAnchor("storage.overview", highlighted: highlightedSettingID)
        }
    }

    private var cleanupSection: some View {
        Section(String(localized: "Free Up Space")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Picker(
                        SettingsNavigationModel.title(for: "storage.cleanupByAge"),
                        selection: $model.selectedAgeChoice
                    ) {
                        ForEach(StorageCleanupAgeChoice.allCases) { choice in
                            Text(choice.shortDurationLabel).tag(choice)
                        }
                    }

                    Button(model.selectedAgeChoice.label) {
                        isConfirmingBulkCleanup = true
                    }
                    .controlSize(.small)
                    .disabled(model.isCleaning)

                    Button(String(localized: "Clear All Cached Media…")) {
                        isConfirmingClearAllCache = true
                    }
                    .controlSize(.small)
                    .disabled(model.isCleaning)
                }

                Text(CommandSet.deleteMediaConfirmation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingAnchor("storage.cleanupByAge", highlighted: highlightedSettingID)
        }
    }

    private var byRoomSection: some View {
        Section(String(localized: "Storage by Chat")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField(
                        String(localized: "Filter chats by name or network…"),
                        text: $model.roomFilterQuery
                    )
                    .textFieldStyle(.roundedBorder)
                }

                StorageByRoomListView(
                    rooms: model.filteredRooms,
                    isCleaning: model.isCleaning,
                    onClearRoom: { room in
                        roomPendingCleanup = room
                    }
                )
            }
            .settingAnchor("storage.byRoom", highlighted: highlightedSettingID)
        }
    }
}

public struct StorageOverviewChartView: View {
    public let usage: StorageUsageResult

    public init(usage: StorageUsageResult) {
        self.usage = usage
    }

    private struct Segment: Identifiable {
        let id: String
        let label: String
        let bytes: Int64
        let color: Color
    }

    private var segments: [Segment] {
        [
            Segment(id: "photos", label: String(localized: "Photos & Videos"), bytes: usage.photosAndVideosBytes, color: .blue),
            Segment(id: "files", label: String(localized: "Files & Documents"), bytes: usage.filesBytes, color: .teal),
            Segment(id: "audio", label: String(localized: "Voice Notes & Audio"), bytes: usage.audioBytes, color: .purple),
            Segment(id: "stickers", label: String(localized: "Stickers & GIFs"), bytes: usage.stickersBytes, color: .orange),
            Segment(id: "other", label: String(localized: "Other Media"), bytes: usage.otherMediaBytes, color: .pink),
            Segment(id: "db", label: String(localized: "Messages Database"), bytes: usage.databaseBytes, color: .secondary),
        ]
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(StorageModel.formatBytes(usage.totalBytes))
                    .font(.title2.weight(.bold).monospacedDigit())
                Text(String(localized: "total on this Mac"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            GeometryReader { geo in
                let total = max(1, Double(usage.totalBytes))
                HStack(spacing: 2) {
                    ForEach(segments.filter { $0.bytes > 0 }) { seg in
                        let width = max(4, CGFloat(Double(seg.bytes) / total) * geo.size.width)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(seg.color)
                            .frame(width: width)
                    }
                }
            }
            .frame(height: 12)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], alignment: .leading, spacing: 6) {
                ForEach(segments) { seg in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(seg.color)
                            .frame(width: 8, height: 8)
                        Text(seg.label)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(StorageModel.formatBytes(seg.bytes))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

public struct StorageByRoomListView: View {
    public let rooms: [RoomStorageUsage]
    public let isCleaning: Bool
    public let onClearRoom: (RoomStorageUsage) -> Void

    public init(
        rooms: [RoomStorageUsage],
        isCleaning: Bool,
        onClearRoom: @escaping (RoomStorageUsage) -> Void
    ) {
        self.rooms = rooms
        self.isCleaning = isCleaning
        self.onClearRoom = onClearRoom
    }

    public var body: some View {
        if rooms.isEmpty {
            Text(String(localized: "No cached chat media matching this filter."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        } else {
            VStack(spacing: 6) {
                ForEach(rooms) { room in
                    HStack(spacing: 10) {
                        NetworkBadge(
                            network: room.network,
                            name: NetworkNames.displayName(of: room.network) ?? room.network,
                            size: 16
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(room.name.isEmpty ? room.roomID : room.name)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Text(
                                String(
                                    localized: "\(room.itemCount) media items • \(NetworkNames.displayName(of: room.network) ?? room.network)"
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(StorageModel.formatBytes(room.mediaBytes))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button(CommandSet.deleteMediaInThisChatTitle) {
                            onClearRoom(room)
                        }
                        .controlSize(.small)
                        .disabled(isCleaning || room.mediaBytes <= 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                    )
                }
            }
        }
    }
}
